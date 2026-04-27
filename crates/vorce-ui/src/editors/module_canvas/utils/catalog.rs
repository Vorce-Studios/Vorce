use crate::editors::module_canvas::inspector::capabilities;
use vorce_core::module::{
    AudioBand, AudioTriggerOutputConfig, BevyCameraMode, BlendModeType, EffectType, HueMappingMode,
    HueNodeType, LayerType, MaskShape, MaskType, ModulePartType, ModulizerType, OutputType,
    SourceType, TriggerType,
};

pub struct NodeCatalogItem {
    /// User-friendly name for identifying the element.
    pub label: &'static str,
    pub label_lower: String,
    pub search_tags: &'static str,
    pub part_type: ModulePartType,
}

pub fn build_node_catalog() -> Vec<NodeCatalogItem> {
    let shader_supported = capabilities::is_source_type_enum_supported(true, false, false, false);

    #[cfg(feature = "ndi")]
    let ndi_supported = capabilities::is_source_type_enum_supported(false, false, true, false);

    #[cfg(target_os = "windows")]
    let spout_supported = capabilities::is_source_type_enum_supported(false, false, false, true);

    let mut catalog = vec![
        NodeCatalogItem {
            label: "Beat",
            label_lower: "beat".to_string(),
            search_tags: "trigger time rhythm",
            part_type: ModulePartType::Trigger(TriggerType::Beat),
        },
        NodeCatalogItem {
            label: "Audio FFT",
            label_lower: "audio fft".to_string(),
            search_tags: "trigger sound music reactive",
            part_type: ModulePartType::Trigger(TriggerType::AudioFFT {
                band: AudioBand::Bass,
                threshold: 0.5,
                output_config: AudioTriggerOutputConfig::default(),
            }),
        },
        NodeCatalogItem {
            label: "Random",
            label_lower: "random".to_string(),
            search_tags: "trigger chance stochastic",
            part_type: ModulePartType::Trigger(TriggerType::Random {
                min_interval_ms: 500,
                max_interval_ms: 2000,
                probability: 0.5,
            }),
        },
        NodeCatalogItem {
            label: "Fixed Timer",
            label_lower: "fixed timer".to_string(),
            search_tags: "trigger time clock loop",
            part_type: ModulePartType::Trigger(TriggerType::Fixed {
                interval_ms: 1000,
                offset_ms: 0,
            }),
        },
        NodeCatalogItem {
            label: "MIDI",
            label_lower: "midi".to_string(),
            search_tags: "trigger control note cc",
            part_type: ModulePartType::Trigger(TriggerType::Midi {
                channel: 1,
                note: 60,
                device: String::new(),
            }),
        },
        NodeCatalogItem {
            label: "OSC",
            label_lower: "osc".to_string(),
            search_tags: "trigger network control open sound control",
            part_type: ModulePartType::Trigger(TriggerType::Osc {
                address: "/trigger".to_string(),
            }),
        },
        NodeCatalogItem {
            label: "Shortcut",
            label_lower: "shortcut".to_string(),
            search_tags: "trigger keyboard key input",
            part_type: ModulePartType::Trigger(TriggerType::Shortcut {
                key_code: "Space".to_string(),
                modifiers: 0,
            }),
        },
        NodeCatalogItem {
            label: "Media File",
            label_lower: "media file".to_string(),
            search_tags: "source video image movie picture",
            part_type: ModulePartType::Source(SourceType::new_media_file(String::new())),
        },
        NodeCatalogItem {
            label: "3D Text",
            label_lower: "3d text".to_string(),
            search_tags: "source bevy font label",
            part_type: ModulePartType::Source(SourceType::Bevy3DText {
                text: "Hello 3D".to_string(),
                font_size: 20.0,
                color: [1.0, 1.0, 1.0, 1.0],
                position: [0.0, 0.0, 0.0],
                rotation: [0.0, 0.0, 0.0],
                alignment: "Center".to_string(),
            }),
        },
        NodeCatalogItem {
            label: "3D Shape",
            label_lower: "3d shape".to_string(),
            search_tags: "source bevy cube sphere geometry",
            part_type: ModulePartType::Source(SourceType::Bevy3DShape {
                shape_type: vorce_core::module::BevyShapeType::Cube,
                position: [0.0, 0.0, 0.0],
                rotation: [0.0, 0.0, 0.0],
                scale: [1.0, 1.0, 1.0],
                color: [1.0, 0.5, 0.0, 1.0],
                unlit: false,
                outline_width: 0.0,
                outline_color: [1.0, 1.0, 1.0, 1.0],
            }),
        },
        NodeCatalogItem {
            label: "Camera",
            label_lower: "camera".to_string(),
            search_tags: "source bevy view perspective orbit fly",
            part_type: ModulePartType::Source(SourceType::BevyCamera {
                mode: BevyCameraMode::Orbit {
                    radius: 10.0,
                    speed: 10.0,
                    target: [0.0, 0.0, 0.0],
                    height: 5.0,
                },
                fov: 60.0,
                active: true,
            }),
        },
        NodeCatalogItem {
            label: "3D Model",
            label_lower: "3d model".to_string(),
            search_tags: "source bevy gltf obj model mesh",
            part_type: ModulePartType::Source(SourceType::Bevy3DModel {
                path: String::new(),
                position: [0.0, 0.0, 0.0],
                rotation: [0.0, 0.0, 0.0],
                scale: [1.0, 1.0, 1.0],
                color: [1.0, 1.0, 1.0, 1.0],
                unlit: false,
                outline_width: 0.0,
                outline_color: [1.0, 1.0, 1.0, 1.0],
            }),
        },
    ];

    if shader_supported {
        catalog.push(NodeCatalogItem {
            label: "Shader",
            label_lower: "shader".to_string(),
            search_tags: "source glsl generator procedural",
            part_type: ModulePartType::Source(SourceType::Shader {
                name: "Default".to_string(),
                params: Vec::new(),
            }),
        });
    }

    #[cfg(feature = "ndi")]
    if ndi_supported {
        catalog.push(NodeCatalogItem {
            label: "NDI Input",
            label_lower: "ndi input".to_string(),
            search_tags: "source network video stream",
            part_type: ModulePartType::Source(SourceType::NdiInput { source_name: None }),
        });
    }

    #[cfg(target_os = "windows")]
    if spout_supported {
        catalog.push(NodeCatalogItem {
            label: "Spout Input",
            label_lower: "spout input".to_string(),
            search_tags: "source texture share windows",
            part_type: ModulePartType::Source(SourceType::SpoutInput {
                sender_name: String::new(),
            }),
        });
    }

    if capabilities::is_mask_supported() {
        catalog.extend([
            NodeCatalogItem {
                label: "Shape Mask",
                label_lower: "shape mask".to_string(),
                search_tags: "mask circle rectangle alpha",
                part_type: ModulePartType::Mask(MaskType::Shape(MaskShape::Circle)),
            },
            NodeCatalogItem {
                label: "Gradient Mask",
                label_lower: "gradient mask".to_string(),
                search_tags: "mask fade transition alpha",
                part_type: ModulePartType::Mask(MaskType::Gradient { angle: 0.0, softness: 0.5 }),
            },
        ]);
    }

    if capabilities::has_advanced_blend_mode_support() {
        catalog.push(NodeCatalogItem {
            label: "Blend Mode",
            label_lower: "blend mode".to_string(),
            search_tags: "modulator mix composite add multiply screen",
            part_type: ModulePartType::Modulizer(ModulizerType::BlendMode(BlendModeType::Normal)),
        });
    }

    catalog.extend(
        EffectType::all().iter().filter(|effect| capabilities::is_effect_supported(effect)).map(
            |effect| NodeCatalogItem {
                label: effect.name(),
                label_lower: effect.name().to_lowercase(),
                search_tags: "modulator effect filter fx",
                part_type: ModulePartType::Modulizer(ModulizerType::Effect {
                    effect_type: *effect,
                    params: std::collections::HashMap::new(),
                }),
            },
        ),
    );

    catalog.extend([
        NodeCatalogItem {
            label: "Single Layer",
<<<<<<< HEAD
=======
            label_lower: "single layer".to_string(),
>>>>>>> origin/main
            search_tags: "layer composition",
            part_type: ModulePartType::Layer(LayerType::Single {
                id: 0,
                name: "New Layer".to_string(),
                opacity: 1.0,
                blend_mode: None,
                mesh: vorce_core::module::MeshType::default(),
                mapping_mode: false,
            }),
        },
        NodeCatalogItem {
            label: "Single Lamp",
<<<<<<< HEAD
=======
            label_lower: "single lamp".to_string(),
>>>>>>> origin/main
            search_tags: "hue light smart home philips",
            part_type: ModulePartType::Hue(HueNodeType::SingleLamp {
                id: String::new(),
                name: "New Lamp".to_string(),
                brightness: 1.0,
                color: [1.0, 1.0, 1.0],
                effect: None,
                effect_active: false,
            }),
        },
        NodeCatalogItem {
            label: "Multi Lamp",
<<<<<<< HEAD
=======
            label_lower: "multi lamp".to_string(),
>>>>>>> origin/main
            search_tags: "hue light group multi smart home philips",
            part_type: ModulePartType::Hue(HueNodeType::MultiLamp {
                ids: Vec::new(),
                name: "New Group".to_string(),
                brightness: 1.0,
                color: [1.0, 1.0, 1.0],
                effect: None,
                effect_active: false,
            }),
        },
        NodeCatalogItem {
            label: "Entertainment Group",
<<<<<<< HEAD
=======
            label_lower: "entertainment group".to_string(),
>>>>>>> origin/main
            search_tags: "hue entertainment area spatial philips",
            part_type: ModulePartType::Hue(HueNodeType::EntertainmentGroup {
                name: "Entertainment Area".to_string(),
                brightness: 1.0,
                color: [1.0, 1.0, 1.0],
                effect: None,
                effect_active: false,
            }),
        },
        NodeCatalogItem {
            label: "Hue Output",
<<<<<<< HEAD
=======
            label_lower: "hue output".to_string(),
>>>>>>> origin/main
            search_tags: "output hue bridge entertainment spatial philips",
            part_type: ModulePartType::Output(OutputType::Hue {
                bridge_ip: String::new(),
                username: String::new(),
                client_key: String::new(),
                entertainment_area: String::new(),
                lamp_positions: std::collections::HashMap::new(),
                mapping_mode: HueMappingMode::Ambient,
            }),
        },
        NodeCatalogItem {
            label: "Projector Output",
<<<<<<< HEAD
=======
            label_lower: "projector output".to_string(),
>>>>>>> origin/main
            search_tags: "output display screen beamer",
            part_type: ModulePartType::Output(OutputType::Projector {
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
        },
    ]);

    catalog
}
