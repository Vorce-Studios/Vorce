//! Cluster and Session Topology Data Model
//!
//! This module defines the core data structures for instance topology,
//! session roles, and output resource allocation across a cluster of Vorce instances.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Unique identifier for a Vorce instance in a cluster
pub type InstanceId = Uuid;

/// Defines the operational role of a Vorce instance within a cluster/session
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
pub enum InstanceRole {
    /// The primary controller of the session. Coordinates timeline, media selection,
    /// and dispatches state updates to Slaves and Headless Nodes.
    /// In a typical setup, there is exactly one Master.
    #[default]
    Master,

    /// A secondary control instance. Can interact with the session but defers
    /// timeline/state authority to the Master. (Future multi-master mode)
    SecondaryMaster,

    /// A rendering node with a user interface. Receives state from the Master
    /// and renders assigned outputs.
    Slave,

    /// A pure rendering node without a user interface. Receives state from the Master
    /// and renders assigned outputs directly to physical displays.
    HeadlessNode,
}

/// Represents a single Vorce instance in the cluster topology
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct InstanceConfig {
    /// Unique identifier for the instance
    pub id: InstanceId,

    /// Human-readable name (e.g., "FOH-Control", "Render-Node-A")
    pub name: String,

    /// The role this instance plays in the cluster
    pub role: InstanceRole,

    /// Network address or hostname for communication
    pub address: String,

    /// Whether this instance is currently connected to the session (runtime state, not persisted)
    #[serde(skip)]
    pub is_online: bool,
}

impl InstanceConfig {
    /// Creates a new InstanceConfig with a random UUID
    pub fn new(name: impl Into<String>, role: InstanceRole, address: impl Into<String>) -> Self {
        Self {
            id: Uuid::new_v4(),
            name: name.into(),
            role,
            address: address.into(),
            is_online: false,
        }
    }
}

/// Represents an output resource (e.g., a projector or display) assigned to an instance
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct OutputAssignment {
    /// ID of the output (references OutputManager configurations)
    pub output_id: u64,

    /// The instance responsible for rendering this output
    pub assigned_instance: InstanceId,
}

/// The complete cluster/session configuration model
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ClusterConfig {
    /// Unique ID for the current session
    pub session_id: Uuid,

    /// Name of the session
    pub session_name: String,

    /// All registered instances in the cluster topology
    pub instances: Vec<InstanceConfig>,

    /// Mapping of outputs to instances
    pub output_assignments: Vec<OutputAssignment>,

    /// Local instance ID (which instance is currently running this application)
    /// Not persisted in project files directly, resolved at runtime or startup.
    #[serde(skip)]
    pub local_instance_id: Option<InstanceId>,
}

impl Default for ClusterConfig {
    fn default() -> Self {
        Self {
            session_id: Uuid::new_v4(),
            session_name: "Default Session".to_string(),
            instances: Vec::new(),
            output_assignments: Vec::new(),
            local_instance_id: None,
        }
    }
}

impl ClusterConfig {
    /// Creates a new cluster configuration
    pub fn new(session_name: impl Into<String>) -> Self {
        Self {
            session_id: Uuid::new_v4(),
            session_name: session_name.into(),
            instances: Vec::new(),
            output_assignments: Vec::new(),
            local_instance_id: None,
        }
    }

    /// Adds an instance to the topology
    pub fn add_instance(&mut self, instance: InstanceConfig) {
        self.instances.push(instance);
    }

    /// Assigns an output to a specific instance
    pub fn assign_output(&mut self, output_id: u64, instance_id: InstanceId) {
        // Remove existing assignment for this output if any
        self.output_assignments.retain(|a| a.output_id != output_id);

        self.output_assignments
            .push(OutputAssignment { output_id, assigned_instance: instance_id });
    }

    /// Gets the instance assigned to a specific output
    pub fn get_instance_for_output(&self, output_id: u64) -> Option<&InstanceConfig> {
        let assignment = self.output_assignments.iter().find(|a| a.output_id == output_id)?;
        self.instances.iter().find(|i| i.id == assignment.assigned_instance)
    }

    /// Gets all outputs assigned to a specific instance
    pub fn get_outputs_for_instance(&self, instance_id: InstanceId) -> Vec<u64> {
        self.output_assignments
            .iter()
            .filter(|a| a.assigned_instance == instance_id)
            .map(|a| a.output_id)
            .collect()
    }

    /// Resolves a multimaster conflict between a current update and a new update.
    pub fn resolve_conflict(
        &self,
        current: Option<&UpdateMetadata>,
        new_update: &UpdateMetadata,
    ) -> ConflictResolution {
        let Some(current) = current else {
            return ConflictResolution::Accepted;
        };

        if new_update.timestamp_ms < current.timestamp_ms {
            return ConflictResolution::RejectedStale;
        }

        if new_update.timestamp_ms == current.timestamp_ms {
            if new_update.sequence <= current.sequence {
                return ConflictResolution::RejectedStale;
            }

            let current_instance = self.instances.iter().find(|i| i.id == current.instance_id);
            let new_instance = self.instances.iter().find(|i| i.id == new_update.instance_id);

            let current_is_master = current_instance.map_or(false, |i| i.role == InstanceRole::Master);
            let new_is_master = new_instance.map_or(false, |i| i.role == InstanceRole::Master);

            if current_is_master && !new_is_master {
                return ConflictResolution::RejectedWinner(current.instance_id);
            }
            if new_is_master && !current_is_master {
                return ConflictResolution::Accepted;
            }

            if current.instance_id < new_update.instance_id {
                return ConflictResolution::RejectedWinner(current.instance_id);
            }
        }

        ConflictResolution::Accepted
    }
}

/// Conflict resolution result
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConflictResolution {
    /// Update is accepted
    Accepted,
    /// Update is rejected because it is stale (older timestamp or sequence)
    RejectedStale,
    /// Update is rejected because another instance won the conflict
    RejectedWinner(InstanceId),
}

/// A state update metadata for conflict resolution
#[derive(Debug, Clone)]
pub struct UpdateMetadata {
    /// ID of the instance making the update
    pub instance_id: InstanceId,
    /// Timestamp of the update in milliseconds
    pub timestamp_ms: u64,
    /// Sequence number for tie-breaking updates within the same millisecond
    pub sequence: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_multimaster_winner_selection() {
        let mut cluster = ClusterConfig::new("Test Session");
        let master = InstanceConfig::new("Master", InstanceRole::Master, "127.0.0.1");
        let secondary = InstanceConfig::new("Sec", InstanceRole::SecondaryMaster, "127.0.0.2");
        let master_id = master.id;
        let sec_id = secondary.id;
        cluster.add_instance(master);
        cluster.add_instance(secondary);

        let current = UpdateMetadata { instance_id: master_id, timestamp_ms: 100, sequence: 1 };
        let new_update = UpdateMetadata { instance_id: sec_id, timestamp_ms: 100, sequence: 2 };

        // Master wins over secondary even if secondary has higher sequence
        assert_eq!(cluster.resolve_conflict(Some(&current), &new_update), ConflictResolution::RejectedWinner(master_id));

        let new_master_update = UpdateMetadata { instance_id: master_id, timestamp_ms: 100, sequence: 2 };
        let sec_current = UpdateMetadata { instance_id: sec_id, timestamp_ms: 100, sequence: 1 };

        // Master wins over secondary
        assert_eq!(cluster.resolve_conflict(Some(&sec_current), &new_master_update), ConflictResolution::Accepted);
    }

    #[test]
    fn test_multimaster_stale_updates() {
        let cluster = ClusterConfig::new("Test Session");
        let instance = Uuid::new_v4();
        let current = UpdateMetadata { instance_id: instance, timestamp_ms: 200, sequence: 5 };

        let older_time = UpdateMetadata { instance_id: instance, timestamp_ms: 100, sequence: 10 };
        assert_eq!(cluster.resolve_conflict(Some(&current), &older_time), ConflictResolution::RejectedStale);

        let older_seq = UpdateMetadata { instance_id: instance, timestamp_ms: 200, sequence: 4 };
        assert_eq!(cluster.resolve_conflict(Some(&current), &older_seq), ConflictResolution::RejectedStale);

        let same_seq = UpdateMetadata { instance_id: instance, timestamp_ms: 200, sequence: 5 };
        assert_eq!(cluster.resolve_conflict(Some(&current), &same_seq), ConflictResolution::RejectedStale);
    }

    #[test]
    fn test_multimaster_rejection_paths() {
        let cluster = ClusterConfig::new("Test Session");
        // ID1 < ID2
        let id1 = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
        let id2 = Uuid::parse_str("00000000-0000-0000-0000-000000000002").unwrap();

        let current = UpdateMetadata { instance_id: id1, timestamp_ms: 100, sequence: 1 };
        let new_update = UpdateMetadata { instance_id: id2, timestamp_ms: 100, sequence: 2 };

        // When both have same role (None here) and timestamp, smaller UUID wins
        assert_eq!(cluster.resolve_conflict(Some(&current), &new_update), ConflictResolution::RejectedWinner(id1));

        let current2 = UpdateMetadata { instance_id: id2, timestamp_ms: 100, sequence: 1 };
        let new_update2 = UpdateMetadata { instance_id: id1, timestamp_ms: 100, sequence: 2 };

        // Smaller UUID wins
        assert_eq!(cluster.resolve_conflict(Some(&current2), &new_update2), ConflictResolution::Accepted);
    }
}
