use egui::TextureHandle;
use vorce_core::runtime_paths;

pub fn ensure_icons_loaded(
    plug_icons: &mut std::collections::HashMap<String, TextureHandle>,
    ctx: &egui::Context,
) {
    if !plug_icons.is_empty() {
        return;
    }

    let paths = [runtime_paths::resource_path("stecker_icons")];

    let files = [
        "audio-jack1.1.svg",
        "audio-jack_1.2.svg",
        "audio-jack_2.svg",
        "plug.svg",
        "power-plug.svg",
        "usb-cable.svg",
    ];

    for path_str in paths {
        let base_path = path_str.as_path();
        if base_path.exists() {
            for file in files {
                let path = base_path.join(file);
                if let Some(texture) = load_svg_icon(&path, ctx) {
                    plug_icons.insert(file.to_string(), texture);
                }
            }
            if !plug_icons.is_empty() {
                break;
            }
        }
    }
}

fn load_svg_icon(path: &std::path::Path, ctx: &egui::Context) -> Option<TextureHandle> {
    let svg_data = std::fs::read(path).ok()?;
    let options = resvg::usvg::Options::default();
    let tree = resvg::usvg::Tree::from_data(&svg_data, &options).ok()?;
    let size = tree.size();
    let width = size.width().round() as u32;
    let height = size.height().round() as u32;

    let mut pixmap = resvg::tiny_skia::Pixmap::new(width, height)?;
    resvg::render(&tree, resvg::tiny_skia::Transform::default(), &mut pixmap.as_mut());

    let mut pixels = Vec::with_capacity((width * height) as usize);
    for pixel in pixmap.pixels() {
        // Preserve original RGBA from SVG
        pixels.push(egui::Color32::from_rgba_premultiplied(
            pixel.red(),
            pixel.green(),
            pixel.blue(),
            pixel.alpha(),
        ));
    }

    let image = egui::ColorImage {
        size: [width as usize, height as usize],
        pixels,
        source_size: egui::Vec2::new(width as f32, height as f32),
    };

    Some(ctx.load_texture(
        path.file_name()?.to_string_lossy(),
        image,
        egui::TextureOptions {
            magnification: egui::TextureFilter::Linear,
            minification: egui::TextureFilter::Linear,
            wrap_mode: egui::TextureWrapMode::ClampToEdge,
            mipmap_mode: None,
        },
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    #[test]
    fn test_ensure_icons_loaded_already_loaded() {
        let mut plug_icons = HashMap::new();
        // Insert a dummy to make it non-empty
        // TextureHandle is usually constructed via Context, but since we just check is_empty we can't easily mock TextureHandle without a Context.
        // Actually, TextureHandle does not have a public default or easy mock unless we have a Context.
        let ctx = egui::Context::default();
        let handle =
            ctx.load_texture("dummy", egui::ColorImage::example(), egui::TextureOptions::default());
        plug_icons.insert("dummy".to_string(), handle);

        let initial_len = plug_icons.len();
        ensure_icons_loaded(&mut plug_icons, &ctx);
        // Should return early because it's not empty, so len remains same
        assert_eq!(plug_icons.len(), initial_len);
    }

    #[test]
    fn test_ensure_icons_loaded_empty() {
        let mut plug_icons = HashMap::new();
        let ctx = egui::Context::default();

        // This will try to load from the filesystem.
        // In CI/sandbox, it might fail to find the icons, leaving the map empty,
        // or if it finds them, it will load them. We just assert it doesn't panic.
        ensure_icons_loaded(&mut plug_icons, &ctx);
    }
}
