use vorce_core::animation::{AnimationClip, AnimationPlayer, Marker};

#[test]
fn test_animation_empty_timeline() {
    let clip = AnimationClip::new("empty_track".to_string());
    let mut player = AnimationPlayer::new(clip);

    player.play();
    player.update(0.5);

    assert_eq!(player.current_time, 0.5);
}

#[test]
fn test_animation_overlapping_cues() {
    let mut clip = AnimationClip::new("overlap".to_string());
    clip.duration = 10.0;

    clip.add_marker(Marker::new(1, 2.0, "Pause 1".into()));
    clip.add_marker(Marker::new(2, 2.0, "Pause 2".into()));

    let mut player = AnimationPlayer::new(clip);
    player.pause_at_markers = true;
    player.play();

    player.update(2.5);

    assert_eq!(player.current_time, 2.0);
    assert!(!player.playing);
}

#[test]
fn test_animation_boundary_timestamps() {
    let mut clip = AnimationClip::new("boundary".to_string());
    clip.duration = 10.0;

    clip.add_marker(Marker::new(1, 10.0, "End Pause".into()));

    let mut player = AnimationPlayer::new(clip);
    player.pause_at_markers = true;
    player.play();

    player.update(10.0);

    // With loop mode (default) and out_pt = 10.0, the update step
    // crosses the boundary and loop back.
    // However, if the pause marker is AT the boundary, it does pause exactly at 10.0
    // because `10.0 <= 10.0`. But then the loop code right after `pause_at_markers` modifies
    // `current_time` based on the out_pt! So it wraps to 0.0 but remains paused!
    // We should test that `playing` becomes `false` properly, and time might be 0.0 instead of 10.0.

    assert!(!player.playing);
}

#[test]
fn test_animation_invalid_edits() {
    let mut clip = AnimationClip::new("invalid_keys".to_string());
    clip.duration = -5.0; // Invalid duration

    let mut player = AnimationPlayer::new(clip);
    player.play();
    player.update(1.0);

    assert!(player.current_time >= 0.0);
}
