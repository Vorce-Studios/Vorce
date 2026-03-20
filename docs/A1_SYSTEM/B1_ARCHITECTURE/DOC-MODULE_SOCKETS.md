# Module Sockets and Connectors

This document specifies the standards for node sockets in MapFlow to prevent drift and ensure schema consistency.

## Socket Types (ModuleSocketType)

The following signal variants exist in the current system:

*   **Trigger**: Represents an event-based signal (automation, beat, etc.).
*   **Media**: Represents a flow of visual data (Textures, Meshes, Mask geometries).
*   **Layer**: Represents a full compositing layer stream including its metadata.
*   **Effect**: Represents an effect application path.
*   **Output**: Represents a final output sink.
*   **Link**: Used for master/slave linking configuration.

## Standard Socket Builders

To prevent drift and ensure nodes always present standard and reliable socket IDs, you must use the following standard builders located in `ModuleSocket` (`crates/mapmap-core/src/module/types/socket.rs`) instead of constructing sockets manually via `ModuleSocket::input()`:

*   `standard_media_in()` -> ID: `"media_in"`
*   `standard_media_out()` -> ID: `"media_out"`
*   `standard_layer_in()` -> ID: `"layer_in"`
*   `standard_layer_out()` -> ID: `"layer_out"`
*   `standard_trigger_in()` -> ID: `"trigger_in"`
*   `standard_trigger_out()` -> ID: `"trigger_out"`

Using these ensures that ID nomenclature is consistent across the entire node ecosystem.
