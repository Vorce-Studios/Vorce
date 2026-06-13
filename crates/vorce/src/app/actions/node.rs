use crate::app::core::app_struct::App;
use anyhow::Result;
use vorce_ui::NodeEditorAction;
fn handle_node_action(app: &mut App, action: NodeEditorAction) -> Result<()> {
    if let Some(graph_id) = app.ui_state.node_editor_panel.graph_id {
        if let Some(graph) = app.state.shader_graphs_mut().get_mut(&graph_id) {
            let mut needs_update = false;

            match action {
                NodeEditorAction::AddNode(node_type, pos) => {
                    let _id = graph.add_node(node_type);
                    if let Some(node) = graph.nodes.get_mut(&_id) {
                        node.position = (pos.x, pos.y);
                    }
                    needs_update = true;
                }
                NodeEditorAction::RemoveNode(node_id) => {
                    graph.remove_node(node_id);
                    needs_update = true;
                }
                NodeEditorAction::SelectNode(_) => {
                    // Selection is handled in UI state mostly.
                }
                NodeEditorAction::AddConnection(_from, from_socket, to, to_socket) => {
                    if let Err(e) = graph.connect(_from, &from_socket, to, &to_socket) {
                        tracing::warn!("Failed to connect nodes: {}", e);
                    } else {
                        needs_update = true;
                    }
                }
                NodeEditorAction::UpdateGraph(_) => {
                    needs_update = true;
                }
                _ => {}
            }

            if needs_update {
                app.ui_state.node_editor_panel.load_graph(graph);
                app.state.dirty = true;

                // Compile Graph
                if let Err(e) = app
                    .effect_chain_renderer
                    .update_shader_graph(&mut app.shader_graph_manager, graph_id)
                {
                    tracing::error!("Shader Compile Error: {}", e);
                } else {
                    tracing::info!("Shader Graph {} compiled successfully", graph_id);
                }
            }
        }
    }
    Ok(())
}

/// Process pending MCP actions

pub fn handle(app: &mut App, action: NodeEditorAction) -> Result<()> {
    handle_node_action(app, action)
}
