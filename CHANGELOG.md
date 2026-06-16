# Changelog

## [1.1.0] — 2026-06-16

### Added
- **Rope sleep system.** A settled rope skips the whole simulation and runs only a cheap watchdog until something disturbs it. Settling is detected as windowed drift in local space: no point may drift more than `sleep_tolerance` pixels from a reference snapshot for `sleep_frames` consecutive frames. The watchdog wakes the rope on node or anchor movement, anchor add/remove, external data changes, force changes, or a collider arriving, moving, rotating or leaving inside the rope bounds (works for `StaticBody2D` and `TileMap` too). A rope that holds up a `RigidBody2D` on its own stays awake; one whose body is also supported by something else can sleep. New API: `sleep_enabled`, `sleep_tolerance`, `sleep_frames`, `sleep_min_awake`, `is_sleeping()`, `wake()`, signals `slept` and `woken`.
- **`CRopeWorldGravityForceMod`.** Zero-config force module that reads the gravity of the rope's physics space every frame, so it follows project settings and runtime `PhysicsServer2D` changes. A gravity change wakes a sleeping rope.
- **Red-black constraint solver** (`solver_mode`, `SolverMode` enum exposed to GDScript). Up to 10x faster substeps on long ropes. It is now the default solver; the sequential solver remains available.
- **`CRopeDirectRenderMod.gradient`** (Gradient): colors the rope along its length, sampled by normalized arc length. Falls back to the single `color` when unset.
- **`CRopeData.get_rect()`**: bounding box query for the rope points.

### Changed
- **Damping is now per-second, frame-rate and substep independent** (`0.0` = none, `0.6` = keep 40 percent of velocity per second, `1.0` = instant stop). The old scale was nearly ineffective. Default changed from `0.4` to `0.6`. Re-tune any explicitly set damping values in existing scenes.
- **Default solver is now red-black.** At the same `solver_iterations` the rope is slightly more elastic. Increase iterations or switch `solver_mode` to sequential for the previous stiffness.
- **Debug renderer property renames:** `draw_debug_overlay` is now `draw_overlay`, `debug_overlay_color` is now `wake_color`. Added a separate `sleep_color` and an AABB section (`draw_aabb`, `aabb_color`).

### Fixed
- Crash safety for freed anchor and attractor nodes, and for out-of-range break indices.
- `simulate()` is safe against data mutation from signal handlers and force modules.
- Break modules run on current-frame data, so a break no longer loses one simulation step.
- A rope created over existing data no longer starts with stale `prev_points` velocities.
- `break_at` no longer spawns dead single-point ropes and rejects invalid segments.
- Anchors with an index outside the rope data are treated as inactive.
- Anchor target node is cached per rope instead of on the shared anchor resource.
- Physics space state is refreshed each frame instead of cached forever.
- Wind time accumulator wraps to the wave period to avoid float precision loss.
- `create_path_by_count` enforces a minimum segment length on degenerate paths.
- Mesh builder guards zero width, clamps `tile_aspect`, and fixes round-joint preallocation.
- `clone()` copies sleep settings and CanvasItem visual state to broken rope pieces.
- A warning is emitted when a `CRope2D` enters the tree with an unsupported global scale.

### Performance
- Skip the local-to-global transform for unchanged ropes and materialize `prev_points` lazily.
- Skip rope sections and anchor pull when no `RigidBody2D` consumes them.
- Skip pinch detection and `Dictionary` construction for points near a single collider.
- Reuse scratch buffers across subdivide, simplify and the debug renderer; ping-pong buffers in smooth.
- Squared-distance comparisons in simplify and magnet, raw-pointer geometry writes in the mesh builder.

### Examples
- Reworked the example project: new showcase scenes (jellyfish, plug the wires, kite, growing sunflowers, firefly meadow, grand curtain), older single-feature scenes removed, and everything renumbered (17 scenes total).

## [1.0.0] — 2026-03-04

### Added
- CRope2D node — 2D rope physics simulation
  - Verlet integration with configurable stiffness and damping
  - Collision support (StaticBody2D, RigidBody2D, CharacterBody2D)
  - Anchor system (start, end, both, none)
  - Modular architecture with four module types:
    - **Force modules** — gravity, magnet, wind
    - **Line modules** — smooth, simplify, subdivide
    - **Render modules** — direct, Line2D, debug
    - **Break modules** — rope breaking under tension
  - Platform support: macOS, Linux, Windows, Web
  - 13 example scenes demonstrating all features
  - 10 custom GDScript module examples
  - Complete API documentation
