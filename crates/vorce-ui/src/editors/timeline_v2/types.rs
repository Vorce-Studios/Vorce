use vorce_core::module::ModuleId;

/// Actions triggered by timeline
#[derive(Debug, Clone)]
pub enum TimelineAction {
    Play,
    Pause,
    Stop,
    Seek(f32),
    SelectModule(ModuleId),
    AddMarker(f32),
    RemoveMarker(u64),
    ToggleMarkerPause(u64),
    JumpNextMarker,
    JumpPrevMarker,
    BindParameter {
        effect_type: vorce_core::effects::EffectType,
        module_id: ModuleId,
        parameter_name: String,
        initial_value: f32,
    },
}

/// Lightweight module descriptor for timeline arrangement UI.
#[derive(Debug, Clone)]
pub struct TimelineModule<'a> {
    /// Module ID
    pub id: ModuleId,
    /// Module display name
    // Optimization: Borrow name string to prevent allocation overhead in UI hot loop.
    pub name: &'a str,
}
