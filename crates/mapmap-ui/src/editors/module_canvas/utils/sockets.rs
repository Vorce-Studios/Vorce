use mapmap_core::module::{ModulePartType, ModuleSocket, ModuleSocketType};

pub fn get_sockets_for_part_type(
    part_type: &ModulePartType,
) -> (Vec<ModuleSocket>, Vec<ModuleSocket>) {
    match part_type {
        ModulePartType::Trigger(_) => (
            vec![],
            vec![ModuleSocket {
                name: "Trigger Out".to_string(),
                socket_type: ModuleSocketType::Trigger,
            }],
        ),
        ModulePartType::Source(_) => (
            vec![ModuleSocket {
                name: "Trigger In".to_string(),
                socket_type: ModuleSocketType::Trigger,
            }],
            vec![ModuleSocket {
                name: "Media Out".to_string(),
                socket_type: ModuleSocketType::Media,
            }],
        ),
        ModulePartType::Mask(_) => (
            vec![
                ModuleSocket {
                    name: "Media In".to_string(),
                    socket_type: ModuleSocketType::Media,
                },
                ModuleSocket {
                    name: "Mask In".to_string(),
                    socket_type: ModuleSocketType::Media,
                },
            ],
            vec![ModuleSocket {
                name: "Media Out".to_string(),
                socket_type: ModuleSocketType::Media,
            }],
        ),
        ModulePartType::Modulizer(_) => (
            vec![
                ModuleSocket {
                    name: "Media In".to_string(),
                    socket_type: ModuleSocketType::Media,
                },
                ModuleSocket {
                    name: "Trigger In".to_string(),
                    socket_type: ModuleSocketType::Trigger,
                },
            ],
            vec![ModuleSocket {
                name: "Media Out".to_string(),
                socket_type: ModuleSocketType::Media,
            }],
        ),
        ModulePartType::Mesh(_) => (vec![], vec![]),
        ModulePartType::Layer(_) => (
            vec![ModuleSocket {
                name: "Media In".to_string(),
                socket_type: ModuleSocketType::Media,
            }],
            vec![ModuleSocket {
                name: "Layer Out".to_string(),
                socket_type: ModuleSocketType::Layer,
            }],
        ),
        ModulePartType::Output(_) => (
            vec![ModuleSocket {
                name: "Layer In".to_string(),
                socket_type: ModuleSocketType::Layer,
            }],
            vec![],
        ),
        ModulePartType::Hue(_) => (
            vec![
                ModuleSocket {
                    name: "Brightness".to_string(),
                    socket_type: ModuleSocketType::Trigger,
                },
                ModuleSocket {
                    name: "Color (RGB)".to_string(),
                    socket_type: ModuleSocketType::Media,
                },
                ModuleSocket {
                    name: "Strobe".to_string(),
                    socket_type: ModuleSocketType::Trigger,
                },
            ],
            vec![],
        ),
    }
}
