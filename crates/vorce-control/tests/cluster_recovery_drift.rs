use uuid::Uuid;
use vorce_core::cluster::{ClusterConfig, InstanceConfig, InstanceRole};

#[test]
fn test_cluster_recovery_reconnect() {
    let mut cluster = ClusterConfig::new("Test Session");

    let mut instance1 = InstanceConfig::new("Node A", InstanceRole::Slave, "192.168.1.100");
    instance1.is_online = true;

    cluster.add_instance(instance1.clone());

    // Simulate instance1 disconnecting
    let mut offline_instance1 = instance1.clone();
    offline_instance1.is_online = false;
    cluster.update_instance_state(offline_instance1);

    assert_eq!(cluster.instances[0].is_online, false);

    // Simulate instance1 reconnecting
    let mut reconnect_instance1 = instance1.clone();
    reconnect_instance1.is_online = true;
    cluster.update_instance_state(reconnect_instance1);

    assert_eq!(cluster.instances[0].is_online, true);
}

#[test]
fn test_cluster_reconciliation_stale_peer_state() {
    let mut local_cluster = ClusterConfig::new("Test Session");
    let mut remote_cluster = ClusterConfig::new("Test Session");

    let instance1 = InstanceConfig::new("Node A", InstanceRole::Slave, "192.168.1.100");

    local_cluster.add_instance(instance1.clone());
    remote_cluster.add_instance(instance1.clone());

    // Local cluster sees Node A as offline (stale state)
    local_cluster.instances[0].is_online = false;

    // Remote cluster sees Node A as online
    remote_cluster.instances[0].is_online = true;

    // Reconcile local with remote
    local_cluster.reconcile(&remote_cluster);

    // Local should now see Node A as online (prioritizing online state)
    assert_eq!(local_cluster.instances[0].is_online, true);

    // If remote has a stale offline state, it shouldn't downgrade local's online state
    let mut remote_cluster_stale = ClusterConfig::new("Test Session");
    let mut stale_instance = instance1.clone();
    stale_instance.is_online = false;
    remote_cluster_stale.add_instance(stale_instance);

    local_cluster.reconcile(&remote_cluster_stale);
    assert_eq!(local_cluster.instances[0].is_online, true); // Still online
}

#[test]
fn test_cluster_reconciliation_deterministic_drift() {
    let mut local_cluster = ClusterConfig::new("Test Session");
    let mut remote_cluster = ClusterConfig::new("Test Session");

    let id = Uuid::new_v4();
    let local_instance = InstanceConfig {
        id,
        name: "Node Local".to_string(),
        role: InstanceRole::Slave,
        address: "10.0.0.1".to_string(),
        is_online: true,
    };

    let remote_instance = InstanceConfig {
        id,
        name: "Node Remote".to_string(), // Name drifted
        role: InstanceRole::Slave,
        address: "10.0.0.2".to_string(), // Address drifted
        is_online: true,
    };

    local_cluster.add_instance(local_instance.clone());
    remote_cluster.add_instance(remote_instance.clone());

    // Drift: Both online, but properties differ
    local_cluster.reconcile(&remote_cluster);

    // Should resolve deterministically to max value (lexicographically for strings)
    assert_eq!(local_cluster.instances[0].name, "Node Remote");
    assert_eq!(local_cluster.instances[0].address, "10.0.0.2");
}

#[test]
fn test_cluster_reconciliation_output_assignments() {
    let mut local_cluster = ClusterConfig::new("Test Session");
    let mut remote_cluster = ClusterConfig::new("Test Session");

    // We use hardcoded UUIDs so one is definitely smaller than the other
    let id1 = Uuid::parse_str("00000000-0000-0000-0000-000000000001").unwrap();
    let id2 = Uuid::parse_str("00000000-0000-0000-0000-000000000002").unwrap();

    local_cluster.assign_output(1, id2); // Local assigned to id2
    remote_cluster.assign_output(1, id1); // Remote assigned to id1

    local_cluster.reconcile(&remote_cluster);

    // Should deterministically pick the smaller UUID
    assert_eq!(local_cluster.output_assignments[0].assigned_instance, id1);
}
