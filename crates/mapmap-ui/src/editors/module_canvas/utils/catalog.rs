use mapmap_core::module::{
    AudioBand, AudioTriggerOutputConfig, BevyCameraMode, BlendModeType, EffectType, HueNodeType,
    LayerType, MaskShape, MaskType, MeshType, ModulePartType, ModulizerType, OutputType,
    SourceType, TriggerType,
};

pub struct NodeCatalogItem {
    /// User-friendly name for identifying the element.
    pub label: &'static str,
    pub search_tags: &'static str,
    pub part_type: ModulePartType,
}

pub fn build_node_catalog() -> Vec<NodeCatalogItem> {
    vec![
        // Triggers
        NodeCatalogItem {
            label: "🥁 Beat",
            search_tags: "trigger time rhythm",
            part_type: ModulePartType::Trigger(TriggerType::Beat),
        },
        NodeCatalogItem {
            label: "🔊 Audio FFT",
            search_tags: "trigger sound music reactive",
            part_type: ModulePartType::Trigger(TriggerType::AudioFFT {
                band: AudioBand::Bass,
                threshold: 0.5,
                output_config: AudioTriggerOutputConfig::default(),
            }),
        },
        NodeCatalogItem {
            label: "🎲 Random",
            search_tags: "trigger chance stochastic",
            part_type: ModulePartType::Trigger(TriggerType::Random {
                min_interval_ms: 500,
                max_interval_ms: 2000,
                probability: 0.5,
            }),
        },
        NodeCatalogItem {
            label: "⏱️ Fixed Timer",
            search_tags: "trigger time clock loop",
            part_type: ModulePartType::Trigger(TriggerType::Fixed {
                interval_ms: 1000,
                offset_ms: 0,
            }),
        },
        NodeCatalogItem {
            label: "🎹 MIDI",
            search_tags: "trigger control note cc",
            part_type: ModulePartType::Trigger(TriggerType::Midi {
                channel: 1,
                note: 60,
                device: String::new(),
            }),
        },
        NodeCatalogItem {
            label: "📡 OSC",
            search_tags: "trigger network control open sound control",
            part_type: ModulePartType::Trigger(TriggerType::Osc {
                address: "/trigger".to_string(),
            }),
        },
        NodeCatalogItem {
            label: "⌨️ Shortcut",
            search_tags: "trigger keyboard key input",
            part_type: ModulePartType::Trigger(TriggerType::Shortcut {
                key_code: "Space".to_string(),
                modifiers: 0,
            }),
        },
        // Sources
        NodeCatalogItem {
            label: "📁 Media File",
            search_tags: "source video image movie picture",
            part_type: ModulePartType::Source(SourceType::new_media_file(String::new())),
        },
        NodeCatalogItem {
            label: "🎨 Shader",
            search_tags: "source glsl generator procedural",
            part_type: ModulePartType::Source(SourceType::Shader {
                name: "Default".to_string(),
                params: Vec::new(),
            }),
        },
        #[cfg(feature = "ndi")]
        NodeCatalogItem {
            label: "📡 NDI Input",
            search_tags: "source network video stream",
            part_type: ModulePartType::Source(SourceType::NdiInput { source_name: None }),
        },
        #[cfg(target_os = "windows")]
        NodeCatalogItem {
            label: "🚀 Spout Input",
            search_tags: "source texture share windows",
            part_type: ModulePartType::Source(SourceType::SpoutInput {
                sender_name: String::new(),
            }),
        },
        // Bevy Sources
        NodeCatalogItem {
            label: "📝 3D Text",
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
            label: "🧊 3D Shape",
            search_tags: "source bevy cube sphere geometry",
            part_type: ModulePartType::Source(SourceType::Bevy3DShape {
                shape_type: mapmap_core::module::BevyShapeType::Cube,
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
            label: "📹 Camera",
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
        // Masks
        NodeCatalogItem {
            label: "📁 File Mask",
            search_tags: "mask image file picture alpha",
            part_type: ModulePartType::Mask(MaskType::File {
                path: String::new(),
            }),
        },
        NodeCatalogItem {
            label: "⚪ Shape Mask",
            search_tags: "mask circle rectangle alpha",
            part_type: ModulePartType::Mask(MaskType::Shape(MaskShape::Circle)),
        },
        NodeCatalogItem {
            label: "🌈 Gradient Mask",
            search_tags: "mask fade transition alpha",
            part_type: ModulePartType::Mask(MaskType::Gradient {
                angle: 0.0,
                softness: 0.5,
            }),
        },
        // Meshes
        NodeCatalogItem {
            label: "🕸️ Mesh Node",
            search_tags: "mesh grid quad bezier surface geometry",
            part_type: ModulePartType::Mesh(MeshType::Quad {
                tl: (0.0, 0.0),
                tr: (1.0, 0.0),
                br: (1.0, 1.0),
                bl: (0.0, 1.0),
            }),
        },
        // Modulators
        NodeCatalogItem {
            label: "🎚️ Blend Mode",
            search_tags: "modulator mix composite add multiply screen",
            part_type: ModulePartType::Modulizer(ModulizerType::BlendMode(BlendModeType::Normal)),
        },
    ]
    .into_iter()
    .chain(
        // Effects
        EffectType::all().iter().map(|effect| NodeCatalogItem {
            label: effect.name(),
            search_tags: "modulator effect filter fx",
            part_type: ModulePartType::Modulizer(ModulizerType::Effect {
                effect_type: *effect,
                params: std::collections::HashMap::new(),
            }),
        }),
    )
    .chain(vec![
        // Layers
        NodeCatalogItem {
            label: "📄 Single Layer",
            search_tags: "layer composition",
            part_type: ModulePartType::Layer(LayerType::Single {
                id: 0,
                name: "New Layer".to_string(),
                opacity: 1.0,
                blend_mode: None,
                mesh: mapmap_core::module::MeshType::default(),
                mapping_mode: false,
            }),
        },
        NodeCatalogItem {
            label: "📁 Layer Group",
            search_tags: "layer folder collection",
            part_type: ModulePartType::Layer(LayerType::Group {
                name: "New Group".to_string(),
                opacity: 1.0,
                blend_mode: None,
                mesh: mapmap_core::module::MeshType::default(),
                mapping_mode: false,
            }),
        },
        NodeCatalogItem {
            label: "📚 All Layers",
            search_tags: "layer master global",
            part_type: ModulePartType::Layer(LayerType::All {
                opacity: 1.0,
                blend_mode: None,
            }),
        },
        // Hue
        NodeCatalogItem {
            label: "💡 Single Lamp",
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
        // Output
        NodeCatalogItem {
            label: "🖥️ Projector Output",
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
    ])
    .collect()
}
