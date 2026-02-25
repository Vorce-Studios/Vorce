use egui::Pos2;

/// Check if a point is close to a cubic bezier curve.
///
/// Uses broad-phase AABB check followed by segment approximation.
pub fn is_bezier_hovered(
    start: Pos2,
    end: Pos2,
    ctrl1: Pos2,
    ctrl2: Pos2,
    pointer_pos: Pos2,
    threshold: f32,
) -> bool {
    // OPTIMIZATION: Broad-phase AABB Check
    let min_x = start.x.min(end.x).min(ctrl1.x).min(ctrl2.x) - threshold;
    let max_x = start.x.max(end.x).max(ctrl1.x).max(ctrl2.x) + threshold;
    let min_y = start.y.min(end.y).min(ctrl1.y).min(ctrl2.y) - threshold;
    let max_y = start.y.max(end.y).max(ctrl1.y).max(ctrl2.y) + threshold;

    let in_aabb = pointer_pos.x >= min_x
        && pointer_pos.x <= max_x
        && pointer_pos.y >= min_y
        && pointer_pos.y <= max_y;

    if !in_aabb {
        return false;
    }

    // Iterative Bezier calculation (De Casteljau's algorithm logic unrolled/simplified)
    let steps = 20;
    let mut prev_p = start;

    for i in 1..=steps {
        let t = i as f32 / steps as f32;
        let l1 = start.lerp(ctrl1, t);
        let l2 = ctrl1.lerp(ctrl2, t);
        let l3 = ctrl2.lerp(end, t);
        let q1 = l1.lerp(l2, t);
        let q2 = l2.lerp(l3, t);
        let p = q1.lerp(q2, t);

        // Distance to segment
        let segment = p - prev_p;
        let len_sq = segment.length_sq();
        if len_sq > 0.0 {
            let t_proj = ((pointer_pos - prev_p).dot(segment) / len_sq).clamp(0.0, 1.0);
            let closest = prev_p + segment * t_proj;
            if pointer_pos.distance(closest) < threshold {
                return true;
            }
        }
        prev_p = p;
    }

    false
}

/// Calculate time delta from drag delta
pub fn calculate_drag_delta_time(delta_x: f32, width: f32, duration: f32) -> f32 {
    if width <= 0.0 {
        return 0.0;
    }
    (delta_x / width) * duration
}

/// Clamp time value within valid range
pub fn clamp_time(time: f32, min_val: f32, max_val: f32) -> f32 {
    time.clamp(min_val, max_val)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_bezier_hit_detection() {
        let start = Pos2::new(0.0, 0.0);
        let end = Pos2::new(100.0, 0.0);
        let ctrl1 = Pos2::new(25.0, 50.0); // Curve goes up
        let ctrl2 = Pos2::new(75.0, 50.0);

        // Point on start
        assert!(is_bezier_hovered(start, end, ctrl1, ctrl2, start, 5.0));

        // Point on end
        assert!(is_bezier_hovered(start, end, ctrl1, ctrl2, end, 5.0));

        // Point in middle (approximate top of curve at t=0.5)
        // Bezier at 0.5: 0.125*P0 + 0.375*P1 + 0.375*P2 + 0.125*P3
        // y = 0 + 0.375*50 + 0.375*50 + 0 = 37.5
        let mid_point = Pos2::new(50.0, 37.5);
        assert!(is_bezier_hovered(start, end, ctrl1, ctrl2, mid_point, 5.0));

        // Point far away
        let far_point = Pos2::new(50.0, 100.0);
        assert!(!is_bezier_hovered(start, end, ctrl1, ctrl2, far_point, 5.0));

        // Point near but outside threshold
        let near_miss = Pos2::new(50.0, 37.5 + 6.0); // 6.0 > 5.0
        assert!(!is_bezier_hovered(start, end, ctrl1, ctrl2, near_miss, 5.0));
    }

    #[test]
    fn test_drag_delta_time() {
        assert_eq!(calculate_drag_delta_time(10.0, 100.0, 10.0), 1.0);
        assert_eq!(calculate_drag_delta_time(50.0, 100.0, 10.0), 5.0);
        assert_eq!(calculate_drag_delta_time(0.0, 100.0, 10.0), 0.0);
        assert_eq!(calculate_drag_delta_time(10.0, 0.0, 10.0), 0.0); // Handle division by zero case safely (returns 0.0)
    }

    #[test]
    fn test_clamp_time() {
        assert_eq!(clamp_time(5.0, 0.0, 10.0), 5.0);
        assert_eq!(clamp_time(-1.0, 0.0, 10.0), 0.0);
        assert_eq!(clamp_time(15.0, 0.0, 10.0), 10.0);
    }
}
