use crate::editors::module_canvas::inspector::capabilities;
use vorce_core::module::{
    AudioBand, AudioTriggerOutputConfig, BevyCameraMode, BlendModeType, EffectType, HueMappingMode,
    HueNodeType, LayerType, MaskShape, MaskType, ModulePartType, ModulizerType, OutputType,
    SourceType, TriggerType,
};

#[derive(Clone)]
pub struct NodeCatalogItem {
    /// User-friendly name for identifying the element.
    pub label: &'static str,
    pub label_lower: String,
    pub search_tags: &'static str,
    pub search_tags_lower: String,
    pub part_type: ModulePartType,
}

impl NodeCatalogItem {
    pub fn new(label: &'static str, search_tags: &'static str, part_type: ModulePartType) -> Self {
        Self {
            label,
            label_lower: label.to_lowercase(),
            search_tags,
            search_tags_lower: search_tags.to_lowercase(),
            part_type,
        }
    }
}

use std::sync::OnceLock;

static CATALOG: OnceLock<Vec<NodeCatalogItem>> = OnceLock::new();

pub fn build_node_catalog() -> Vec<NodeCatalogItem> {
    if let Some(catalog) = CATALOG.get() {
        return catalog.clone();
    }

    let shader_supported = capabilities::is_source_type_enum_supported(true, false, false, false);

    #[cfg(feature = "ndi")]
    let ndi_supported = capabilities::is_source_type_enum_supported(false, false, true, false);

    #[cfg(target_os = "windows")]
    let spout_supported = capabilities::is_source_type_enum_supported(false, false, false, true);

    let mut catalog = vec![
        NodeCatalogItem::new(
            "Beat",
            "trigger time rhythm",
            ModulePartType::Trigger(TriggerType::Beat),
        ),
        NodeCatalogItem::new(
            "Audio FFT",
            "trigger sound music reactive",
            ModulePartType::Trigger(TriggerType::AudioFFT {
                band: AudioBand::Bass,
                threshold: 0.5,
                output_config: AudioTriggerOutputConfig::default(),
            }),
        ),
        NodeCatalogItem::new(
            "Random",
            "trigger chance stochastic",
            ModulePartType::Trigger(TriggerType::Random {
                min_interval_ms: 500,
                max_interval_ms: 2000,
                probability: 0.5,
            }),
        ),
        NodeCatalogItem::new(
            "Fixed Timer",
            "trigger time clock loop",
            ModulePartType::Trigger(TriggerType::Fixed {
                interval_ms: 1000,
                offset_ms: 0,
            }),
        ),
        NodeCatalogItem::new(
            "MIDI",
            "trigger control note cc",
            ModulePartType::Trigger(TriggerType::Midi {
                channel: 1,
                note: 60,
                device: String::new(),
            }),
        ),
        NodeCatalogItem::new(
            "OSC",
            "trigger network control open sound control",
            ModulePartType::Trigger(TriggerType::Osc {
                address: "/trigger".to_string(),
            }),
        ),
        NodeCatalogItem::new(
            "Shortcut",
            "trigger keyboard key input",
            ModulePartType::Trigger(TriggerType::Shortcut {
                key_code: "Space".to_string(),
                modifiers: 0,
            }),
        ),
        NodeCatalogItem::new(
            "Media File",
            "source video image movie picture",
            ModulePartType::Source(SourceType::new_media_file(String::new())),
        ),
        NodeCatalogItem::new(
            "3D Text",
            "source bevy font label",
            ModulePartType::Source(SourceType::Bevy3DText {
                text: "Hello 3D".to_string(),
                font_size: 20.0,
                color: [1.0, 1.0, 1.0, 1.0],
                position: [0.0, 0.0, 0.0],
                rotation: [0.0, 0.0, 0.0],
                alignment: "Center".to_string(),
            }),
        ),
        NodeCatalogItem::new(
            "3D Shape",
            "source bevy cube sphere geometry",
            ModulePartType::Source(SourceType::Bevy3DShape {
                shape_type: vorce_core::module::BevyShapeType::Cube,
                position: [0.0, 0.0, 0.0],
                rotation: [0.0, 0.0, 0.0],
                scale: [1.0, 1.0, 1.0],
                color: [1.0, 0.5, 0.0, 1.0],
                unlit: false,
                outline_width: 0.0,
                outline_color: [1.0, 1.0, 1.0, 1.0],
            }),
        ),
        NodeCatalogItem::new(
            "Camera",
            "source bevy view perspective orbit fly",
            ModulePartType::Source(SourceType::BevyCamera {
                mode: BevyCameraMode::Orbit {
                    radius: 10.0,
                    speed: 10.0,
                    target: [0.0, 0.0, 0.0],
                    height: 5.0,
                },
                fov: 60.0,
                active: true,
            }),
        ),
        NodeCatalogItem::new(
            "3D Model",
            "source bevy gltf obj model mesh",
            ModulePartType::Source(SourceType::Bevy3DModel {
                path: String::new(),
                position: [0.0, 0.0, 0.0],
                rotation: [0.0, 0.0, 0.0],
                scale: [1.0, 1.0, 1.0],
                color: [1.0, 1.0, 1.0, 1.0],
                unlit: false,
                outline_width: 0.0,
                outline_color: [1.0, 1.0, 1.0, 1.0],
            }),
        ),
    ];

    if shader_supported {
        catalog.push(NodeCatalogItem::new(
            "Shader",
            "source glsl generator procedural",
            ModulePartType::Source(SourceType::Shader {
                name: "Default".to_string(),
                params: Vec::new(),
            }),
        ));
    }

    #[cfg(feature = "ndi")]
    if ndi_supported {
        catalog.push(NodeCatalogItem::new(
            "NDI Input",
            "source network video stream",
            ModulePartType::Source(SourceType::NdiInput { source_name: None }),
        ));
    }

    #[cfg(target_os = "windows")]
    if spout_supported {
        catalog.push(NodeCatalogItem::new(
            "Spout Input",
            "source texture share windows",
            ModulePartType::Source(SourceType::SpoutInput {
                sender_name: String::new(),
            }),
        ));
    }

    if capabilities::is_mask_supported() {
        catalog.extend([
            NodeCatalogItem::new(
                "Shape Mask",
                "mask circle rectangle alpha",
                ModulePartType::Mask(MaskType::Shape(MaskShape::Circle)),
            ),
            NodeCatalogItem::new(
                "Gradient Mask",
                "mask fade transition alpha",
                ModulePartType::Mask(MaskType::Gradient {
                    angle: 0.0,
                    softness: 0.5,
                }),
            ),
        ]);
    }

    if capabilities::has_advanced_blend_mode_support() {
        catalog.push(NodeCatalogItem::new(
            "Blend Mode",
            "modulator mix composite add multiply screen",
            ModulePartType::Modulizer(ModulizerType::BlendMode(BlendModeType::Normal)),
        ));
    }

    catalog.extend(
        EffectType::all()
            .iter()
            .filter(|effect| capabilities::is_effect_supported(effect))
            .map(|effect| {
                NodeCatalogItem::new(
                    effect.name(),
                    "modulator effect filter fx",
                    ModulePartType::Modulizer(ModulizerType::Effect {
                        effect_type: *effect,
                        params: std::collections::HashMap::new(),
                    }),
                )
            }),
    );

    catalog.extend([
        NodeCatalogItem::new(
            "Single Layer",
            "layer composition",
            ModulePartType::Layer(LayerType::Single {
                id: 0,
                name: "New Layer".to_string(),
                opacity: 1.0,
                blend_mode: None,
                mesh: vorce_core::module::MeshType::default(),
                mapping_mode: false,
            }),
        ),
        NodeCatalogItem::new(
            "Single Lamp",
            "hue light smart home philips",
            ModulePartType::Hue(HueNodeType::SingleLamp {
                id: String::new(),
                name: "New Lamp".to_string(),
                brightness: 1.0,
                color: [1.0, 1.0, 1.0],
                effect: None,
                effect_active: false,
            }),
        ),
        NodeCatalogItem::new(
            "Multi Lamp",
            "hue light group multi smart home philips",
            ModulePartType::Hue(HueNodeType::MultiLamp {
                ids: Vec::new(),
                name: "New Group".to_string(),
                brightness: 1.0,
                color: [1.0, 1.0, 1.0],
                effect: None,
                effect_active: false,
            }),
        ),
        NodeCatalogItem::new(
            "Entertainment Group",
            "hue entertainment area spatial philips",
            ModulePartType::Hue(HueNodeType::EntertainmentGroup {
                name: "Entertainment Area".to_string(),
                brightness: 1.0,
                color: [1.0, 1.0, 1.0],
                effect: None,
                effect_active: false,
            }),
        ),
        NodeCatalogItem::new(
            "Hue Output",
            "output hue bridge entertainment spatial philips",
            ModulePartType::Output(OutputType::Hue {
                bridge_ip: String::new(),
                username: String::new(),
                client_key: String::new(),
                entertainment_area: String::new(),
                lamp_positions: std::collections::HashMap::new(),
                mapping_mode: HueMappingMode::Ambient,
            }),
        ),
        NodeCatalogItem::new(
            "Projector Output",
            "output display screen beamer",
            ModulePartType::Output(OutputType::Projector {
                id: 1,
                name: "Projector 1".to_string(),
                hide_cursor: false,
                target_screen: 0,
                show_in_preview_panel: true,
                extra_preview_window: false,
                output_width: 0,
                output_height: 0,
                output_fps: 60.0,
                ndi_enabled: false,
                ndi_stream_name: String::new(),
            }),
        ),
    ]);

    let _ = CATALOG.set(catalog.clone());
    catalog
}
