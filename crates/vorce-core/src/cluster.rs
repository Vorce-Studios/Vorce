//! Cluster and Session Topology Data Model
//!
//! This module defines the core data structures for instance topology,
//! session roles, and output resource allocation across a cluster of Vorce instances.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// Unique identifier for a Vorce instance in a cluster
pub type InstanceId = Uuid;

/// Defines the operational role of a Vorce instance within a cluster/session
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, Default)]
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

    /// Updates the state of a specific instance. Useful for reconnects and direct peer updates.
    pub fn update_instance_state(&mut self, instance: InstanceConfig) {
        if let Some(existing) = self.instances.iter_mut().find(|i| i.id == instance.id) {
            *existing = instance;
        } else {
            self.instances.push(instance);
            self.instances.sort_by_key(|i| i.id);
        }
    }

    /// Reconciles this cluster configuration with another, deterministically merging state.
    /// Handles stale peer state by prioritizing online status, and resolves conflicts deterministically.
    /// Retrieves the instance configuration for the local node
    pub fn get_local_instance(&self) -> Option<&InstanceConfig> {
        if let Some(id) = self.local_instance_id {
            self.instances.iter().find(|i| i.id == id)
        } else {
            None
        }
    }

    /// Checks if this node is acting as a control plane element
    pub fn is_control_plane(&self) -> bool {
        if let Some(local) = self.get_local_instance() {
            matches!(local.role, InstanceRole::Master | InstanceRole::SecondaryMaster)
        } else {
            false
        }
    }

    pub fn reconcile(&mut self, other: &Self) {
        for other_instance in &other.instances {
            if let Some(existing) = self.instances.iter_mut().find(|i| i.id == other_instance.id) {
                // Resolve stale peer state: prioritize 'is_online == true'
                if other_instance.is_online && !existing.is_online {
                    *existing = other_instance.clone();
                } else if !other_instance.is_online && existing.is_online {
                    // We have the more up-to-date online state, ignore the stale offline state from other
                } else {
                    // Both have same online status. Resolve properties deterministically to avoid drift.
                    if other_instance.address > existing.address {
                        existing.address = other_instance.address.clone();
                    }
                    if other_instance.name > existing.name {
                        existing.name = other_instance.name.clone();
                    }
                    if other_instance.role > existing.role {
                        existing.role = other_instance.role;
                    }
                }
            } else {
                self.instances.push(other_instance.clone());
            }
        }

        // Ensure instances are sorted deterministically
        self.instances.sort_by_key(|i| i.id);

        for other_assignment in &other.output_assignments {
            if let Some(existing) = self
                .output_assignments
                .iter_mut()
                .find(|a| a.output_id == other_assignment.output_id)
            {
                // Deterministic conflict resolution for output assignments: pick the smaller InstanceId
                if other_assignment.assigned_instance < existing.assigned_instance {
                    existing.assigned_instance = other_assignment.assigned_instance;
                }
            } else {
                self.output_assignments.push(other_assignment.clone());
            }
        }

        // Ensure output assignments are sorted deterministically
        self.output_assignments.sort_by_key(|a| a.output_id);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_is_control_plane() {
        let mut cluster = ClusterConfig::new("Test Session");

        // No local instance set
        assert!(!cluster.is_control_plane());

        // Master role
        let master = InstanceConfig::new("Master", InstanceRole::Master, "127.0.0.1");
        cluster.local_instance_id = Some(master.id);
        cluster.add_instance(master);
        assert!(cluster.is_control_plane());

        // SecondaryMaster role
        let sec_master = InstanceConfig::new("SecMaster", InstanceRole::SecondaryMaster, "127.0.0.1");
        cluster.local_instance_id = Some(sec_master.id);
        cluster.add_instance(sec_master);
        assert!(cluster.is_control_plane());

        // Slave role
        let slave = InstanceConfig::new("Slave", InstanceRole::Slave, "127.0.0.1");
        cluster.local_instance_id = Some(slave.id);
        cluster.add_instance(slave);
        assert!(!cluster.is_control_plane());

        // HeadlessNode role
        let headless = InstanceConfig::new("Headless", InstanceRole::HeadlessNode, "127.0.0.1");
        cluster.local_instance_id = Some(headless.id);
        cluster.add_instance(headless);
        assert!(!cluster.is_control_plane());
    }
}
