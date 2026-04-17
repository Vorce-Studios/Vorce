1. **Blend Modes Support in Render Content**
   - Import the `BlendMode` and convert `RenderOp::blend_mode` to `Compositor` equivalents.
   - Note: However, the issue explicitly stated: "Ensure that render-visible node and output features are either truly effective in the runtime render path or intentionally gated with clear diagnostics." and "evaluation.rs still emits explicit `blend_mode_unsupported` and `masks_unsupported` diagnostics...". Wait, the previous message from user "ja sollst du" means I should implement the compositor.
   - Let's update `app_struct.rs` and `init.rs` to expose the compositor without the underscore `_compositor -> compositor`.
   - Update `content.rs` to utilize `ctx.compositor` when drawing layers. This means allocating an intermediate texture for layers that have a blend mode to perform ping-pong blending or using the compositor.

Wait, if I implement compositor logic inside `content.rs`, it changes the single-pass MeshRenderer to a multi-pass approach where layers are composed together.
Let me double check the compositor API.
