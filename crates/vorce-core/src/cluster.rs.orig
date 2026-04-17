//! Cluster and Session Management
//!
//! Defines the topology, roles, and session configuration for distributed Vorce instances.
//! This forms the foundation for Multi-PC / Distributed Rendering modes.

use serde::{Deserialize, Serialize};

/// Unique identifier for a cluster instance
pub type InstanceId = uuid::Uuid;

/// Role of an instance within a cluster session
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum InstanceRole {
    /// Standalone instance (no clustering)
    Standalone,
    /// Primary control node (Master)
    Master,
    /// Render/Output node controlled by Master
    Slave,
    /// Headless output node (no UI, just render/output)
    HeadlessOutput,
    /// Peer in a multi-master/collaborative setup (future)
    MultiMasterPeer,
}

/// Represents a single Vorce instance in the cluster
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InstanceConfig {
    /// Unique identifier
    pub id: InstanceId,
    /// User-friendly name
    pub name: String,
    /// Role in the cluster
    pub role: InstanceRole,
    /// IP address or hostname for discovery/control
    pub address: String,
    /// List of output IDs that this instance physically owns/drives
    pub local_outputs: Vec<crate::output::OutputId>,
}

impl InstanceConfig {
    /// Create a new instance configuration
    pub fn new(id: InstanceId, name: String, role: InstanceRole, address: String) -> Self {
        Self {
            id,
            name,
            role,
            address,
            local_outputs: Vec::new(),
        }
    }

    /// Assign a local output to this instance
    pub fn add_local_output(&mut self, output_id: crate::output::OutputId) {
        if !self.local_outputs.contains(&output_id) {
            self.local_outputs.push(output_id);
        }
    }

    /// Remove a local output assignment
    pub fn remove_local_output(&mut self, output_id: crate::output::OutputId) {
        self.local_outputs.retain(|&id| id != output_id);
    }
}

/// Configuration for a cluster session
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterSessionConfig {
    /// Whether clustering is enabled
    pub enabled: bool,
    /// The ID of this local instance
    pub local_instance_id: InstanceId,
    /// List of all known instances in the cluster
    pub instances: Vec<InstanceConfig>,
}

impl Default for ClusterSessionConfig {
    fn default() -> Self {
        let id = uuid::Uuid::new_v4();
        Self {
            enabled: false,
            local_instance_id: id,
            instances: vec![InstanceConfig::new(
                id,
                "Local Instance".to_string(),
                InstanceRole::Standalone,
                "127.0.0.1".to_string(),
            )],
        }
    }
}

impl ClusterSessionConfig {
    /// Get the local instance configuration
    pub fn local_instance(&self) -> Option<&InstanceConfig> {
        self.get_instance(&self.local_instance_id)
    }

    /// Get an instance by ID
    pub fn get_instance(&self, id: &InstanceId) -> Option<&InstanceConfig> {
        self.instances.iter().find(|i| i.id == *id)
    }

    /// Get a mutable instance by ID
    pub fn get_instance_mut(&mut self, id: &InstanceId) -> Option<&mut InstanceConfig> {
        self.instances.iter_mut().find(|i| i.id == *id)
    }

    /// Add or update an instance
    pub fn upsert_instance(&mut self, instance: InstanceConfig) {
        if let Some(existing) = self.get_instance_mut(&instance.id) {
            *existing = instance;
        } else {
            self.instances.push(instance);
        }
    }

    /// Remove an instance by ID (cannot remove local instance)
    pub fn remove_instance(&mut self, id: &InstanceId) -> bool {
        if *id == self.local_instance_id {
            return false;
        }
        let initial_len = self.instances.len();
        self.instances.retain(|i| i.id != *id);
        self.instances.len() < initial_len
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_upsert_instance_new() {
        let mut config = ClusterSessionConfig::default();
        let initial_len = config.instances.len();

        let new_id = uuid::Uuid::new_v4();
        let new_instance = InstanceConfig::new(
            new_id,
            "New Node".to_string(),
            InstanceRole::Slave,
            "192.168.1.100".to_string(),
        );

        config.upsert_instance(new_instance.clone());

        assert_eq!(config.instances.len(), initial_len + 1);

        let retrieved = config.get_instance(&new_id).unwrap();
        assert_eq!(retrieved.name, "New Node");
        assert_eq!(retrieved.role, InstanceRole::Slave);
        assert_eq!(retrieved.address, "192.168.1.100");
    }

    #[test]
    fn test_upsert_instance_update_existing() {
        let mut config = ClusterSessionConfig::default();

        let new_id = uuid::Uuid::new_v4();
        let new_instance = InstanceConfig::new(
            new_id,
            "Node A".to_string(),
            InstanceRole::Slave,
            "192.168.1.10".to_string(),
        );

        // Insert first time
        config.upsert_instance(new_instance);
        let initial_len = config.instances.len();

        // Create updated version with same ID
        let mut updated_instance = InstanceConfig::new(
            new_id,
            "Node A Updated".to_string(),
            InstanceRole::Master,   // Changed role
            "10.0.0.5".to_string(), // Changed address
        );
        updated_instance.add_local_output(1); // 1 is an OutputId

        // Upsert should update, not add
        config.upsert_instance(updated_instance);

        assert_eq!(config.instances.len(), initial_len); // Length shouldn't change

        let retrieved = config.get_instance(&new_id).unwrap();
        assert_eq!(retrieved.name, "Node A Updated");
        assert_eq!(retrieved.role, InstanceRole::Master);
        assert_eq!(retrieved.address, "10.0.0.5");
        assert_eq!(retrieved.local_outputs.len(), 1);
    }
}
