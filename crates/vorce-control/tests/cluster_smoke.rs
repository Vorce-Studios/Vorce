use vorce_core::cluster::{ClusterConfig, InstanceConfig, InstanceRole};
use uuid::Uuid;

#[test]
fn test_smoke_multi_instance_control_local_projector() {
    let mut cluster = ClusterConfig::new("Test Session");

    // Add Master
    let master = InstanceConfig::new("Master", InstanceRole::Master, "127.0.0.1");
    cluster.add_instance(master);

    // Add local slave (same machine, multi-projector target)
    let local_slave = InstanceConfig::new("Local Slave", InstanceRole::Slave, "127.0.0.1");
    let slave_id = local_slave.id;
    cluster.add_instance(local_slave);

    // Assign multiple outputs to the slave
    let _out_1_id = Uuid::new_v4();
    let _out_2_id = Uuid::new_v4();

    cluster.assign_output(1, slave_id);
    cluster.assign_output(2, slave_id);

    // Verify
    assert_eq!(cluster.instances.len(), 2);
    assert_eq!(cluster.output_assignments.len(), 2);

    let assigned_to_slave = cluster.output_assignments.iter()
        .filter(|a| a.assigned_instance == slave_id)
        .count();

    assert_eq!(assigned_to_slave, 2);
}
