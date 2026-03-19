pub mod catalog;
pub mod icons;
pub mod layout;
pub mod presets;
pub mod sockets;
pub mod styling;

pub use catalog::*;
pub use icons::*;
pub use layout::*;
pub use presets::*;
pub use sockets::*;
pub use styling::*;

#[cfg(test)]
mod tests {
    use super::*;
    use mapmap_core::module::ModulePartType;

    #[test]
    fn test_node_catalog_not_empty() {
        let catalog = build_node_catalog();
        assert!(!catalog.is_empty(), "Node catalog should not be empty");
    }

    #[test]
    fn test_node_catalog_coverage() {
        let catalog = build_node_catalog();

        let has_trigger = catalog
            .iter()
            .any(|item| matches!(item.part_type, ModulePartType::Trigger(_)));
        let has_layer = catalog
            .iter()
            .any(|item| matches!(item.part_type, ModulePartType::Layer(_)));
        let has_mask = catalog
            .iter()
            .any(|item| matches!(item.part_type, ModulePartType::Mask(_)));
        let has_effect = catalog
            .iter()
            .any(|item| matches!(item.part_type, ModulePartType::Modulizer(_)));
        let has_output = catalog
            .iter()
            .any(|item| matches!(item.part_type, ModulePartType::Output(_)));

        assert!(
            has_trigger,
            "Catalog should contain at least one Trigger node"
        );
        assert!(has_layer, "Catalog should contain at least one Layer node");
        assert!(has_mask, "Catalog should contain at least one Mask node");
        assert!(
            has_effect,
            "Catalog should contain at least one Effect node"
        );
        assert!(
            has_output,
            "Catalog should contain at least one Output node"
        );
    }

    #[test]
    fn test_node_catalog_search_tags() {
        let catalog = build_node_catalog();
        for item in catalog {
            assert!(
                !item.search_tags.is_empty(),
                "Node {} should have search tags",
                item.label
            );
            assert!(
                item.search_tags
                    .chars()
                    .all(|c| c.is_lowercase() || c.is_whitespace()),
                "Search tags for {} should be entirely lowercase for easier matching",
                item.label
            );
        }
    }
}
