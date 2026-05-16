//! Visual capture and readback utilities.

use anyhow::{anyhow, Context, Result};
use image::RgbaImage;
use std::path::Path;

/// Queues a copy of a texture to a readback buffer.
///
/// Returns the buffer and the padded bytes per row.
pub fn queue_readback_copy(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    texture: &wgpu::Texture,
    width: u32,
    height: u32,
) -> (wgpu::Buffer, u32) {
    let bytes_per_pixel = 4;
    let unpadded_bytes_per_row: u32 = width * bytes_per_pixel;
    let padded_bytes_per_row = unpadded_bytes_per_row.div_ceil(wgpu::COPY_BYTES_PER_ROW_ALIGNMENT)
        * wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;

    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Capture Readback Buffer"),
        size: (padded_bytes_per_row * height) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });

    encoder.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo {
            texture,
            mip_level: 0,
            origin: wgpu::Origin3d::ZERO,
            aspect: wgpu::TextureAspect::All,
        },
        wgpu::TexelCopyBufferInfo {
            buffer: &buffer,
            layout: wgpu::TexelCopyBufferLayout {
                offset: 0,
                bytes_per_row: Some(padded_bytes_per_row),
                rows_per_image: Some(height),
            },
        },
        wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
    );

    (buffer, padded_bytes_per_row)
}

/// Saves a readback buffer to a PNG file.
pub fn save_readback_buffer(
    device: &wgpu::Device,
    buffer: wgpu::Buffer,
    width: u32,
    height: u32,
    padded_bytes_per_row: u32,
    format: wgpu::TextureFormat,
    output_path: &Path,
) -> Result<()> {
    let slice = buffer.slice(..);
    slice.map_async(wgpu::MapMode::Read, |_| {});

    // In a real app, we might want to poll outside this function,
    // but for simple capture this is fine.
    let _ = device.poll(wgpu::PollType::Wait { timeout: None, submission_index: None });

    let mapped = slice.get_mapped_range();
    let mut rgba = Vec::with_capacity((width * height * 4) as usize);

    for row in mapped.chunks_exact(padded_bytes_per_row as usize).take(height as usize) {
        for pixel in row[..(width * 4) as usize].chunks_exact(4) {
            match format {
                wgpu::TextureFormat::Bgra8Unorm | wgpu::TextureFormat::Bgra8UnormSrgb => {
                    rgba.extend_from_slice(&[pixel[2], pixel[1], pixel[0], pixel[3]]);
                }
                _ => rgba.extend_from_slice(pixel),
            }
        }
    }

    drop(mapped);
    buffer.unmap();

    save_rgba_png(width, height, &rgba, output_path)
}

/// Saves raw RGBA pixels to a PNG file.
pub fn save_rgba_png(width: u32, height: u32, pixels: &[u8], output_path: &Path) -> Result<()> {
    if let Some(parent) = output_path.parent() {
        std::fs::create_dir_all(parent)
            .with_context(|| format!("failed to create output directory {}", parent.display()))?;
    }

    let image = RgbaImage::from_raw(width, height, pixels.to_vec())
        .ok_or_else(|| anyhow!("failed to assemble RGBA image buffer"))?;
    image.save(output_path).with_context(|| format!("failed to save {}", output_path.display()))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    use wgpu::util::DeviceExt;

    #[test]
    fn test_save_rgba_png() {
        let dir = tempdir().unwrap();
        let file_path = dir.path().join("test_image.png");

        let width = 2;
        let height = 2;
        // 2x2 image, 4 pixels, 16 bytes
        let pixels: Vec<u8> = vec![
            255, 0, 0, 255, // red
            0, 255, 0, 255, // green
            0, 0, 255, 255, // blue
            255, 255, 0, 255, // yellow
        ];

        let result = save_rgba_png(width, height, &pixels, &file_path);
        assert!(result.is_ok());
        assert!(file_path.exists());

        let loaded_image = image::open(&file_path).unwrap().into_rgba8();
        assert_eq!(loaded_image.width(), width);
        assert_eq!(loaded_image.height(), height);
        assert_eq!(loaded_image.into_raw(), pixels);
    }

    // Creating wgpu instance in tests
    fn get_test_device() -> Option<(wgpu::Device, wgpu::Queue)> {
        pollster::block_on(async {
            let instance = wgpu::Instance::default();
            let adapter = instance
                .request_adapter(&wgpu::RequestAdapterOptions {
                    power_preference: wgpu::PowerPreference::LowPower,
                    force_fallback_adapter: false,
                    compatible_surface: None,
                })
                .await;

            let adapter = adapter.ok()?;

            let (device, queue) =
                adapter.request_device(&wgpu::DeviceDescriptor::default()).await.ok()?;
            Some((device, queue))
        })
    }

    #[test]
    fn test_queue_readback_copy() {
        let (device, _queue) = match get_test_device() {
            Some(dq) => dq,
            None => {
                println!("Skipping wgpu test due to no adapter");
                return;
            }
        };

        let width = 64;
        let height = 64;

        let texture = device.create_texture(&wgpu::TextureDescriptor {
            label: Some("test texture"),
            size: wgpu::Extent3d { width, height, depth_or_array_layers: 1 },
            mip_level_count: 1,
            sample_count: 1,
            dimension: wgpu::TextureDimension::D2,
            format: wgpu::TextureFormat::Rgba8Unorm,
            usage: wgpu::TextureUsages::COPY_SRC | wgpu::TextureUsages::RENDER_ATTACHMENT,
            view_formats: &[],
        });

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test encoder"),
        });

        let (buffer, padded_bytes_per_row) =
            queue_readback_copy(&device, &mut encoder, &texture, width, height);

        let expected_unpadded = width * 4;
        let expected_padded = expected_unpadded.div_ceil(wgpu::COPY_BYTES_PER_ROW_ALIGNMENT)
            * wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;

        assert_eq!(padded_bytes_per_row, expected_padded);
        assert_eq!(buffer.size(), (expected_padded * height) as u64);
        assert!(buffer.usage().contains(wgpu::BufferUsages::COPY_DST));
        assert!(buffer.usage().contains(wgpu::BufferUsages::MAP_READ));
    }

    #[test]
    fn test_save_readback_buffer() {
        let (device, _queue) = match get_test_device() {
            Some(dq) => dq,
            None => {
                println!("Skipping wgpu test due to no adapter");
                return;
            }
        };

        let width = 2;
        let height = 2;
        let bytes_per_pixel = 4;
        let unpadded_bytes_per_row: u32 = width * bytes_per_pixel;
        let padded_bytes_per_row = unpadded_bytes_per_row
            .div_ceil(wgpu::COPY_BYTES_PER_ROW_ALIGNMENT)
            * wgpu::COPY_BYTES_PER_ROW_ALIGNMENT;

        let mut texture_data = vec![0u8; (padded_bytes_per_row * height) as usize];

        // Write simple RGBA values into the padded buffer
        for row in 0..height {
            for col in 0..width {
                let idx = (row * padded_bytes_per_row + col * bytes_per_pixel) as usize;
                texture_data[idx] = 255; // R
                texture_data[idx + 1] = 0; // G
                texture_data[idx + 2] = 0; // B
                texture_data[idx + 3] = 255; // A
            }
        }

        let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("test buffer"),
            contents: &texture_data,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        });

        _queue.submit(std::iter::empty());

        let dir = tempdir().unwrap();
        let file_path = dir.path().join("test_readback.png");

        let result = save_readback_buffer(
            &device,
            buffer,
            width,
            height,
            padded_bytes_per_row,
            wgpu::TextureFormat::Rgba8Unorm,
            &file_path,
        );

        assert!(result.is_ok());
        assert!(file_path.exists());

        let loaded_image = image::open(&file_path).unwrap().into_rgba8();
        assert_eq!(loaded_image.width(), width);
        assert_eq!(loaded_image.height(), height);
        let pixel = loaded_image.get_pixel(0, 0);
        assert_eq!(pixel[0], 255);
        assert_eq!(pixel[1], 0);
        assert_eq!(pixel[2], 0);
        assert_eq!(pixel[3], 255);
    }
}
