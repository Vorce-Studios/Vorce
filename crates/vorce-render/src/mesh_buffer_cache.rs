//! Mesh Buffer Cache - caches GPU buffers for meshes
//!
//! Prevents re-allocating vertex and index buffers every frame for static geometry.

use crate::mesh_renderer::GpuVertex;
use std::collections::HashMap;
use vorce_core::{mapping::MappingId, Mesh, MeshType};
use wgpu::util::DeviceExt;

/// Cached GPU buffers for a mesh
#[derive(Debug)]
pub struct CachedMeshBuffers {
    pub vertex_buffer: wgpu::Buffer,
    pub index_buffer: wgpu::Buffer,
    pub index_count: u32,
    pub mesh_revision: u64,
    pub mesh_type: MeshType,
    pub vertex_count: usize,
}

/// Manages GPU buffers for meshes to avoid per-frame allocation
pub struct MeshBufferCache {
    cache: HashMap<MappingId, CachedMeshBuffers>,
    scratch_vertices: Vec<GpuVertex>,
}

impl MeshBufferCache {
    /// Create a new mesh buffer cache
    pub fn new() -> Self {
        Self {
            cache: HashMap::new(),
            scratch_vertices: Vec::with_capacity(1024), // Pre-allocate some space
        }
    }

    /// Get buffers for a mapping, creating or updating them if necessary
    pub fn get_buffers(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        mapping_id: MappingId,
        mesh: &Mesh,
    ) -> (&wgpu::Buffer, &wgpu::Buffer, u32) {
        // Check if we can reuse the existing buffers (same topology)
        let can_reuse = if let Some(cached) = self.cache.get(&mapping_id) {
            cached.mesh_type == mesh.mesh_type
                && cached.vertex_count == mesh.vertices.len()
                && cached.index_count == mesh.indices.len() as u32
        } else {
            false
        };

        if can_reuse {
            // Because we already checked can_reuse, we can safely unwrap get_mut,
            // but to avoid `expect_used`, we use `if let Some` and `else unreachable!()`.
            if let Some(cached) = self.cache.get_mut(&mapping_id) {
                // If revision changed, update the content
                if cached.mesh_revision != mesh.revision {
                    // Update Vertices (using scratch to avoid allocation)
                    self.scratch_vertices.clear();
                    self.scratch_vertices
                        .extend(mesh.vertices.iter().map(GpuVertex::from_mesh_vertex));

                    queue.write_buffer(
                        &cached.vertex_buffer,
                        0,
                        bytemuck::cast_slice(&self.scratch_vertices),
                    );

                    // Update Indices
                    queue.write_buffer(
                        &cached.index_buffer,
                        0,
                        bytemuck::cast_slice(&mesh.indices),
                    );

                    cached.mesh_revision = mesh.revision;
                }
            } else {
                unreachable!("Cache item must exist if can_reuse is true");
            }

            // We must drop the mutable borrow above before returning an immutable one.
            if let Some(cached) = self.cache.get(&mapping_id) {
                return (&cached.vertex_buffer, &cached.index_buffer, cached.index_count);
            } else {
                unreachable!("Cache item must exist if can_reuse is true");
            }
        }

        // Cache miss or topology change - create new buffers
        // Use scratch buffer for initial creation too to avoid temp Vec allocation
        self.scratch_vertices.clear();
        self.scratch_vertices
            .reserve(mesh.vertices.len().saturating_sub(self.scratch_vertices.capacity()));
        self.scratch_vertices.extend(mesh.vertices.iter().map(GpuVertex::from_mesh_vertex));

        let vertex_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(&format!("Mesh Vertex Buffer {}", mapping_id)),
            contents: bytemuck::cast_slice(&self.scratch_vertices),
            usage: wgpu::BufferUsages::VERTEX | wgpu::BufferUsages::COPY_DST,
        });

        let index_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(&format!("Mesh Index Buffer {}", mapping_id)),
            contents: bytemuck::cast_slice(&mesh.indices),
            usage: wgpu::BufferUsages::INDEX | wgpu::BufferUsages::COPY_DST,
        });

        let index_count = mesh.indices.len() as u32;

        let cached = CachedMeshBuffers {
            vertex_buffer,
            index_buffer,
            index_count,
            mesh_revision: mesh.revision,
            mesh_type: mesh.mesh_type,
            vertex_count: mesh.vertices.len(),
        };

        self.cache.insert(mapping_id, cached);
        if let Some(cached_ref) = self.cache.get(&mapping_id) {
            (&cached_ref.vertex_buffer, &cached_ref.index_buffer, cached_ref.index_count)
        } else {
            unreachable!("Cache item must exist after insertion");
        }
    }

    /// Remove a mapping from the cache
    pub fn remove(&mut self, mapping_id: MappingId) {
        self.cache.remove(&mapping_id);
    }

    /// Clear the cache
    pub fn clear(&mut self) {
        self.cache.clear();
    }
}

impl Default for MeshBufferCache {
    fn default() -> Self {
        Self::new()
    }
}
