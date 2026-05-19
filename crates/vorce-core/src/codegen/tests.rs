use super::*;
use crate::shader_graph::{NodeType, ShaderGraph};

#[test]
fn test_simple_shader_generation() {
    let mut graph = ShaderGraph::new(1, "Test Shader".to_string());

    let uv_node = graph.add_node(NodeType::UVInput);
    let texture_node = graph.add_node(NodeType::TextureInput);
    let sample_node = graph.add_node(NodeType::TextureSample);
    let output_node = graph.add_node(NodeType::Output);

    graph.connect(uv_node, "UV", sample_node, "UV").unwrap();
    graph.connect(texture_node, "Texture", sample_node, "Texture").unwrap();
    graph.connect(sample_node, "Color", output_node, "Color").unwrap();

    let mut codegen = WGSLCodegen::new(graph);
    let result = codegen.generate();

    assert!(result.is_ok());
    let code = result.unwrap();
    assert!(code.contains("@fragment"));
    assert!(code.contains("textureSample"));
}

#[test]
#[ignore]
fn test_math_nodes() {
    let mut graph = ShaderGraph::new(1, "Math Test".to_string());

    let time_node = graph.add_node(NodeType::TimeInput);
    let sin_node = graph.add_node(NodeType::Sin);
    let output_node = graph.add_node(NodeType::Output);

    graph.connect(time_node, "Time", sin_node, "A").unwrap();
    graph.connect(sin_node, "Result", output_node, "Color").unwrap();

    let mut codegen = WGSLCodegen::new(graph);
    let result = codegen.generate();

    assert!(result.is_ok());
}

#[test]
#[ignore]
fn test_math_nodes_advanced() {
    let mut graph = ShaderGraph::new(1, "Advanced Math Test".to_string());

    let combine_node = graph.add_node(NodeType::Combine);
    let split_node = graph.add_node(NodeType::Split);
    let power_node = graph.add_node(NodeType::Power);
    let clamp_node = graph.add_node(NodeType::Clamp);
    let smoothstep_node = graph.add_node(NodeType::Smoothstep);
    let output_node = graph.add_node(NodeType::Output);

    graph.connect(combine_node, "Color", split_node, "Color").unwrap();
    graph.connect(split_node, "R", power_node, "A").unwrap();
    graph.connect(power_node, "Result", clamp_node, "Value").unwrap();
    graph.connect(clamp_node, "Result", smoothstep_node, "X").unwrap();
    // Since smoothstep is not connected to output, it will trigger an error due to being missing in topological sort,
    // unless we connect it to output. But Output requires Color. Let's create a Mix node to convert float to color or connect smoothstep somewhere.
    // Or we just test the generation of these by not expecting is_ok(), but wait, WGSLCodegen will error out if there's disconnected logic.
    // Actually, topological sort starts from Output node and goes backwards. So nodes not connected to Output are ignored.
    // To test their codegen, we must connect them to output!
    let final_combine = graph.add_node(NodeType::Combine);
    graph.connect(smoothstep_node, "Result", final_combine, "R").unwrap();
    graph.connect(final_combine, "Color", output_node, "Color").unwrap();

    let mut codegen = WGSLCodegen::new(graph);
    let result = codegen.generate();

    assert!(result.is_ok());
    let code = result.unwrap();
    assert!(code.contains("vec4<f32>"));
    assert!(code.contains("pow("));
    assert!(code.contains("clamp("));
    assert!(code.contains("smoothstep("));
    assert!(code.contains(".r;"));
}
