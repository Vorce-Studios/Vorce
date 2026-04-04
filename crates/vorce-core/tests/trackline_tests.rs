#[cfg(test)]
mod trackline_tests {
    use vorce_core::animation::{AnimationClip, AnimationPlayer, Marker};

    #[test]
    fn test_trackline_mode_pauses_at_marker() {
        let mut clip = AnimationClip::new("test".into());
        clip.duration = 10.0;
        // Trackline mode is now implemented via a flag on the player
        let mut marker1 = Marker::new(1, 2.0, "Pause 1".into());
        marker1.pause_at = true;
        clip.add_marker(marker1);

        let mut marker2 = Marker::new(2, 5.0, "Pause 2".into());
        marker2.pause_at = true;
        clip.add_marker(marker2);

        let mut player = AnimationPlayer::new(clip);
        player.pause_at_markers = true;
        player.play();

        // Update past the first marker
        player.update(2.5);

        // Should have paused exactly at 2.0
        assert_eq!(player.current_time, 2.0);
        assert!(!player.playing);

        // Play again, update past second marker
        player.play();
        player.update(4.0);

        // Should have paused exactly at 5.0
        assert_eq!(player.current_time, 5.0);
        assert!(!player.playing);
    }
}
