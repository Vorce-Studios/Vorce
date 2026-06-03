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

    /// A standalone instance. Equivalent to Master in single-instance setups.
    Standalone,

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
    #[serde(default = "Uuid::new_v4")]
    pub session_id: Uuid,

    /// Name of the session
    #[serde(default = "default_session_name")]
    pub session_name: String,

    /// All registered instances in the cluster topology
    #[serde(default)]
    pub instances: Vec<InstanceConfig>,

    /// Mapping of outputs to instances
    #[serde(default)]
    pub output_assignments: Vec<OutputAssignment>,

    /// Local instance ID (which instance is currently running this application)
    /// Not persisted in project files directly, resolved at runtime or startup.
    #[serde(skip)]
    pub local_instance_id: Option<InstanceId>,
}

fn default_session_name() -> String {
    "Default Session".to_string()
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
}
