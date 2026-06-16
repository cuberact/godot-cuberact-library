# CRope2D Documentation

## Overview

CRope2D is a GDExtension node for Godot 4.5+ that simulates 2D rope physics using Verlet integration. It supports collision detection, anchoring to scene nodes, breaking under tension, and fully modular rendering.

The system is built around a **modular architecture** — forces, line processing, breaking, and rendering are all handled by interchangeable module resources:

```
CRope2D (Node2D)
├── data: CRopeData              — point positions, segment length
├── anchors: CRopeAnchor[]       — attach rope points to nodes
├── force_modules: CRopeForceMod[]   — gravity, wind, magnets, custom
├── line_modules: CRopeLineMod[]     — smooth, simplify, subdivide, custom
├── break_modules: CRopeBreakMod[]   — tension break, custom
└── render_modules: CRopeRenderMod[] — direct, Line2D, debug, custom
```

## Quick Start

### Editor Setup

1. Add a **CRope2D** node to your scene
2. In the inspector, set the **rope_path** points and click **"Create RopeData"**
3. Click **"Create Modules"** to add default modules (gravity, smooth, simplify, direct renderer)
4. Add **CRopeAnchor** entries to attach rope ends to other nodes
5. Run the scene

### GDScript Setup

```gdscript
# Create rope data
var data = CRopeData.new()
data.create_path_by_count([
	Vector2(100, 100),
	Vector2(250, 50),
	Vector2(400, 100)
], 30)

# Create rope node
var rope = CRope2D.new()
rope.data = data

# Anchors
var anchor_start = CRopeAnchor.new()
anchor_start.index = 0
anchor_start.node_path = NodePath("../LeftPost")

var anchor_end = CRopeAnchor.new()
anchor_end.index = 30
anchor_end.node_path = NodePath("../RightPost")

rope.anchors = [anchor_start, anchor_end]

# Modules
rope.force_modules = [CRopeGravityForceMod.new()]

var smooth = CRopeSmoothLineMod.new()
var simplify = CRopeSimplifyLineMod.new()
rope.line_modules = [smooth, simplify]

var renderer = CRopeDirectRenderMod.new()
renderer.width = 5.0
renderer.color = Color.BROWN
rope.render_modules = [renderer]

add_child(rope)
```

---

## CRope2D

**Inherits:** Node2D

The main simulation node. Points are stored in **local space** — you can freely move, rotate, and duplicate the node. The simulation runs in global space internally via temporary buffers.

> **Scale caveat:** CRope2D does not support scale. The constraint solver enforces `segment_length` in global (unscaled) space, so any scale on the node or its parents makes the simulated rope disagree with the authored local-space data. A warning is printed when a scaled rope enters the tree. Flips and rotations preserve lengths and are fully supported.

### Simulation Properties

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `substeps` | int | 8 | 1–20 | Physics iterations per frame. Higher = more stable but slower. |
| `solver_mode` | int | 0 | 0–1 | Constraint solver variant. 0 = Red-Black (up to 10× faster on long ropes, slightly more elastic), 1 = Sequential (stiffest result per iteration). |
| `solver_iterations` | int | 1 | 1–100 | Constraint solver passes per substep. Higher = stiffer. |
| `solver_bidirectional` | bool | true | — | Run solver both forward (0→N) and backward (N→0). Stabilizes longer ropes. Only used by the Sequential `solver_mode`. |
| `damping` | float | 0.6 | 0–1 | Fraction of velocity removed per second. 0 = no damping, 0.6 = keep 40%/s, 1 = velocity removed instantly. Frame-rate independent. |
| `stiffness` | float | 0.99 | 0.01–1 | Constraint correction strength. 0.01 = stretchy, 1.0 = rigid. |

### Sleep Properties

A settled rope skips the whole simulation and runs only a cheap watchdog until something disturbs it.

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `sleep_enabled` | bool | true | — | Let a settled rope fall asleep and skip simulation. |
| `sleep_tolerance` | float | 1.0 | 0–20 | Max distance (px) any point may drift from the reference snapshot while still counting as calm. |
| `sleep_frames` | int | 60 | 1–600 | Consecutive calm frames required before falling asleep. |
| `sleep_min_awake` | int | 5 | 1–600 | Min calm frames a rope stays awake after a watchdog wake before it may sleep again. |

A sleeping rope wakes when its node (or a parent) moves, an anchor moves or is added/removed, accumulated forces change (wind, moving magnet), the data is modified, or a collider of any type (including `StaticBody2D` and `TileMap`) appears, moves, rotates or leaves inside the rope bounds. A rope that holds up a `RigidBody2D` on its own stays awake; one whose body is also supported by something else can sleep. Disable `sleep_enabled` for a rope whose hanging weight must be simulated continuously (e.g. a weighted pendulum).

### Collision Properties

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `collision_width` | float | 10.0 | 0.1–200 | Rope diameter for collision (each point tests a circle with `width / 2` radius). |
| `collision_stride` | int | 3 | 1–16 | Resolve collisions every Nth substep from the end. Higher = faster, less precise. |
| `collision_friction` | float | 0.01 | 0–1 | Surface friction. 0 = perfect sliding, 1 = full stop on contact. |
| `collision_force` | float | 4000.0 | 0–10000 | Impulse applied to RigidBody2D colliders. |
| `collision_force_pinched` | float | 0.0 | 0–10000 | Impulse when a point is squeezed between two colliders. `0` (default) disables pinch impulses. |
| `collision_damping_range` | float | 20.0 | 1–100 | Distance range (px) over which depth-based damping ramps up. |
| `collision_mask` | int | 1 | — | Physics layers to collide with. |

**Collision behavior & `collision_stride`:** each rope point is treated as a circle (radius `collision_width / 2`); when it overlaps a collider, the point is pushed out. A natural limitation: sharp corners can push a point outward in a way that stretches the segment between two neighboring points, and the Verlet constraint solver then tries to shorten it back — a tug-of-war between collision resolution and distance constraints, most visible on acute edges. `collision_stride` manages this. The simulation runs multiple substeps per frame; integration and constraint solving happen every substep, but collision resolution does not have to. `collision_stride` controls how many substeps are skipped between collision passes (default 3), and the last substep always resolves collisions. With fewer passes the collision impulses are normalized so the total stays consistent. This lowers collision cost while giving the solver room to work without being constantly fought by collision pushback. Lower it toward 1 for ropes against sharp or fast-moving colliders.

### Module Arrays

| Property | Type | Description |
|----------|------|-------------|
| `force_modules` | Array\[CRopeForceMod\] | Force modules (gravity, wind, magnets). |
| `line_modules` | Array\[CRopeLineMod\] | Line processors (smooth, simplify, subdivide). Applied in order. |
| `break_modules` | Array\[CRopeBreakMod\] | Break detectors (tension-based). First match breaks the rope. |
| `render_modules` | Array\[CRopeRenderMod\] | Renderers (direct, Line2D, debug). All render independently. |

### Other Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `data` | CRopeData | auto-created | Rope point data. Auto-created on first use. |
| `anchors` | Array\[CRopeAnchor\] | \[\] | Anchor points attaching rope to scene nodes. |
| `show_anchor_helpers` | bool | true | Draw anchor visualization in editor. |
| `save_data_on_shortcut` | bool | false | Ctrl+S / Cmd+S saves rope data to `.tres` at runtime. |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `simulate(delta)` | void | Run one simulation step. Called automatically in `_physics_process`. |
| `break_at(index)` | void | Split rope at point index. Creates two new ropes, emits `broken`, destroys original. |
| `duplicate_rope()` | CRope2D | Full independent copy (data, modules, anchors). Use instead of `Node.duplicate()`. |
| `is_sleeping()` | bool | True while the rope is asleep (see Sleep Properties). |
| `wake()` | void | Wake a sleeping rope and reset the calm-frame counter. Call after changes the watchdog can't detect (e.g. editing TileMap cells under the rope). |
| `depenetrate_anchor_offset(anchor)` | void | One-shot: on the next `simulate()`, if the anchor overlaps a collider, permanently adjust its offset to sit on the collider surface. |
| `depenetrate_all_anchor_offsets()` | void | Same as above, for every anchor on the rope. |
| `save_data(path)` | Error | Save current data to `.tres` file. |
| `enable_debug_probe()` | CRopeDebugProbe | Enable performance profiling. Returns probe with timing metrics. |
| `disable_debug_probe()` | void | Disable profiling. |

### Signals

**`broken(break_index: int, rope_a: CRope2D, rope_b: CRope2D)`**

Emitted when the rope breaks. `rope_a` contains points 0 to `break_index`, `rope_b` contains points from `break_index + 1` to the end. Either side is `null` when it would consist of a single point, so check before use. The original rope is destroyed (`queue_free`) after emitting this signal.

**`slept()`**

Emitted when the rope falls asleep (see Sleep Properties).

**`woken()`**

Emitted when a sleeping rope wakes up, via the watchdog or `wake()`.

---

## CRopeData

**Inherits:** Resource

Stores rope point positions and simulation parameters. Serializable — saving preserves the full rope state including velocity.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `segment_length` | float | 0.01 | Rest length of each segment (min 0.01). |
| `compression_limit` | float | 0.2 | Minimum segment compression ratio (0–1). Three zones: stretched (>1.0) → corrects to 1.0; comfort zone (limit–1.0) → no correction; over-compressed (<limit) → corrects to limit. |
| `points` | PackedVector2Array | — | Current positions in local space. Serialized. |
| `prev_points` | PackedVector2Array | — | Previous positions (encodes velocity: `vel = points - prev_points`). Serialized. |

### Creation Methods

| Method | Description |
|--------|-------------|
| `create_line_by_count(start, end, count)` | Straight line, fixed segment count. |
| `create_line_by_length(start, end, length)` | Straight line, fixed segment length. |
| `create_path_by_count(path, count)` | Along waypoints, fixed segment count. |
| `create_path_by_length(path, length)` | Along waypoints, fixed segment length. |

### Manipulation Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `get_count()` | int | Number of points. |
| `is_valid()` | bool | True if ≥ 2 points and positive segment_length. |
| `get_rect()` | Rect2 | Bounding box of the points in local space. Empty `Rect2` when there are no points. |
| `align()` | void | Resize prev_points to match points (zero velocity for new entries). |
| `resize(count)` | void | Resize all arrays. New points initialized to `Vector2(0, 0)`. |
| `append(point, index)` | void | Add point at index (-1 = end). |
| `remove(index)` | void | Remove point at index (-1 = last). Won't go below 2 points. |
| `slice(from, to)` | CRopeData | New CRopeData with points `from` to `to` (inclusive). |
| `clear()` | void | Remove all points, reset segment_length to 0. |

### Runtime Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `get_global_points()` | PackedVector2Array | World-space positions. Empty before first `simulate()`. Not serialized. |
| `get_prev_global_points()` | PackedVector2Array | Previous world-space positions. Empty before first `simulate()`. Not serialized. |
| `get_global_count()` | int | Number of points in the global working buffers. Matches `get_count()` during simulation, 0 before the first `simulate()`. |

---

## CRopeAnchor

**Inherits:** Resource

Attaches a rope point to a scene node. When the target is a RigidBody2D, the anchor applies pull forces for two-way physical interaction.

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `index` | int | 0 | Rope point index to anchor (0 = start, segment_count = end). |
| `node_path` | NodePath | "" | Path to target Node2D (relative to CRope2D). |
| `offset_angle` | float | 0.0 | Offset angle (degrees) from node origin. Rotates with the node. |
| `offset_distance` | float | 0.0 | Offset distance (px) from node origin. 0 = exactly at origin. |
| `pull_strength` | float | 3000.0 | Force pulling RigidBody2D targets (0–10000). |
| `pull_damping` | float | 0.5 | Damping on pull force (0–1). Higher = less oscillation. |
| `pull_samples` | int | 2 | Rope segments averaged for pull direction (1–20). Higher = more stable. |
| `collision_resolve` | bool | true | Auto-adjust the anchor each frame to avoid penetrating colliders. Disable when the anchor is intentionally placed on a surface to prevent jitter. |
| `enabled` | bool | true | Active flag. Disabled anchors are ignored. |

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `get_local_offset()` | Vector2 | Cartesian offset computed from `offset_angle` and `offset_distance`. |

---

## Modules

All modules inherit from **CRopeMod** (Resource) and share a common `enabled` property. Modules are stored in typed arrays on CRope2D and execute in array order.

### Module Categories

| Category | Virtual Method | Parameters | Returns |
|----------|---------------|------------|---------|
| **CRopeForceMod** | `_update_forces` | `forces: PackedVector2Array, data: CRopeData, delta: float` | `PackedVector2Array` |
| **CRopeLineMod** | `_process_line` | `input: PackedVector2Array` | `PackedVector2Array` |
| **CRopeBreakMod** | `_check_break` | `data: CRopeData` | `int` (-1 or break index) |
| **CRopeRenderMod** | `_render` | `data: CRopeData, render_points: PackedVector2Array` | void |
| **CRopeRenderMod** | `_cleanup` | — | void |

All base classes also expose `get_rope() -> CRope2D` to access the parent rope from within a module.

---

### Force Modules

#### CRopeGravityForceMod

Applies constant gravity to all points.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `gravity` | Vector2 | (0, 980) | Gravity vector. |

#### CRopeWorldGravityForceMod

Applies the gravity of the rope's physics space, read fresh every frame. The rope follows the same gravity as physics bodies, including runtime changes via `PhysicsServer2D.area_set_param` (a change wakes a sleeping rope). Nothing to configure. Area2D gravity zones are not supported.

#### CRopeWindForceMod

Oscillating wind force using sine wave: `direction.normalized() * strength * (1 - variation/2 + sin(time * frequency * TAU) * variation/2)`.

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `direction` | Vector2 | (1, 0) | — | Base wind direction. |
| `strength` | float | 200.0 | 0–1000 | Maximum wind force. |
| `variation` | float | 0.3 | 0–1 | Oscillation amplitude. 0 = constant, 1 = full swing. |
| `frequency` | float | 1.0 | 0.01+ | Oscillation speed. |

#### CRopeMagnetForceMod

Attracts or repels rope points toward/from a target node.

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `attractor` | NodePath | "" | — | Path to target Node2D. |
| `strength` | float | 500.0 | -5000–5000 | Positive = attract, negative = repel. |
| `falloff_mode` | FalloffMode | SMOOTH | — | How force diminishes with distance (see below). |
| `dead_zone` | float | 20.0 | 1–500 | Minimum effective distance (px). |
| `reach` | float | 0.0 | 0–5000 | Maximum distance. 0 = infinite. |

**FalloffMode enum** (defined on CRopeForceMod):

| Value | Name | Description |
|-------|------|-------------|
| 0 | `FALLOFF_CONSTANT` | Full strength regardless of distance. |
| 1 | `FALLOFF_LINEAR` | Linear falloff with distance. |
| 2 | `FALLOFF_SMOOTH` | Smooth (cubic) falloff. |
| 3 | `FALLOFF_GRAVITY` | Inverse-square falloff (1/r²). |

---

### Line Modules

#### CRopeSimplifyLineMod

Reduces point count using the Ramer-Douglas-Peucker algorithm.

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `tolerance` | float | 1.0 | 0.1–20 | Maximum deviation (px) before a point is kept. |

#### CRopeSmoothLineMod

Laplacian smoothing — reduces sharp angles between segments.

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `iterations` | int | 2 | 1–10 | Number of smoothing passes. |
| `strength` | float | 0.4 | 0–0.5 | Smoothing strength per pass. Capped at 0.5 to prevent oscillation. |

#### CRopeSubdivideLineMod

Chaikin's corner-cutting subdivision — creates smooth curves from few control points.

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `iterations` | int | 2 | 1–4 | Subdivision passes. Each roughly doubles point count. |

---

### Break Modules

#### CRopeTensionBreakMod

Breaks the rope when segment stretch exceeds a threshold.

| Property | Type | Default | Range | Description |
|----------|------|---------|-------|-------------|
| `segment_stretch_threshold` | float | 2.0 | 1.1–4.0 | Stretch multiplier that triggers a break candidate. |
| `neighbor_check_count` | int | 2 | 0–10 | Neighboring segments to check (with decreasing threshold). |
| `require_anchors` | bool | true | — | Only break between two active anchors. |
| `collision_test` | bool | false | — | Perform a physics shape query at the break point. |
| `collision_test_radius` | float | 0.0 | 0–200 | Radius for collision test. 0 = use `collision_width / 2`. |

---

### Render Modules

#### CRopeDirectRenderMod

Draws directly into the rope's canvas item (no child nodes). Lightweight.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `width` | float | 10.0 px | Rope width. |
| `color` | Color | (1, 0.4, 0) | Rope color (ignored if gradient is set). |
| `gradient` | Gradient | — | Color gradient along the rope. Overrides `color`. |
| `texture` | Texture2D | — | Optional texture. |
| `joint_mode` | LineJointMode | Sharp | Joint style: Sharp, Bevel, Round. |
| `begin_cap_mode` | LineCapMode | None | Start cap: None, Box, Round. |
| `end_cap_mode` | LineCapMode | None | End cap: None, Box, Round. |
| `sharp_limit` | float | 2.0 | Miter limit for sharp joints. |
| `round_precision` | int | 8 | Vertices for round joints/caps (1–32). |

#### CRopeLine2DRenderMod

Renders via a Line2D child node. Access to all Line2D features including gradient, material, and antialiasing.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `width` | float | 10.0 | Line width (min 0.01). |
| `color` | Color | (1, 0.4, 0) | Line color (ignored if gradient is set). |
| `material` | Material | — | For shader effects. |
| `gradient` | Gradient | — | Color gradient along the rope. Overrides `color`. |
| `texture` | Texture2D | — | Texture applied to the line. |
| `texture_mode` | LineTextureMode | Tile | None, Tile, Stretch. |
| `joint_mode` | LineJointMode | Sharp | Sharp, Bevel, Round. |
| `begin_cap_mode` | LineCapMode | None | None, Box, Round. |
| `end_cap_mode` | LineCapMode | None | None, Box, Round. |
| `sharp_limit` | float | 2.0 | Miter limit for sharp joints. |
| `round_precision` | int | 8 | Vertices for round joints/caps (1–32). |
| `antialiased` | bool | false | Enable line antialiasing. |

#### CRopeDebugRenderMod

Debug overlay for visualizing rope internals. All draw features can be toggled independently. Use `set_all_draws(bool)` to toggle everything at once.

| Feature | Toggle | Default | Visual |
|---------|--------|---------|--------|
| Overlay | `draw_overlay` | ✓ | Rope silhouette in `wake_color` (dark), switches to `sleep_color` (blue) while the rope sleeps |
| AABB | `draw_aabb` | ✗ | Bounding box outline of the rope points |
| Simulation Points | `draw_points` | ✓ | Green dots |
| Render Points | `draw_render_points` | ✓ | Cyan dots |
| Anchors | `draw_anchors` | ✓ | Magenta circles |
| Tension | `draw_tension` | ✗ | Color gradient (green → red) |
| Collision Width | `draw_collision_width` | ✗ | White semi-transparent circles |
| Forces | `draw_forces` | ✗ | Blue arrows |
| Velocity | `draw_velocity` | ✗ | Cyan arrows |
| Previous Points | `draw_prev_points` | ✗ | Black dots |

Each feature has configurable color and size/scale properties (e.g. `point_color`, `point_size`, `force_scale`).

---

## Custom Modules

You can create custom modules in GDScript by extending any module base class. Here's one example per category:

### Custom Force Module

```gdscript
class_name AntigravityForceModule extends CRopeForceMod

@export var strength: float = 1000.0

func _update_forces(forces: PackedVector2Array, data: CRopeData, delta: float) -> PackedVector2Array:
	for i in forces.size():
		forces[i] += Vector2(0.0, -strength)
	return forces
```

### Custom Line Module

```gdscript
class_name WaveLineModule extends CRopeLineMod

@export var amplitude: float = 20.0
@export var frequency: float = 0.1
@export var speed: float = 5.0

func _process_line(input: PackedVector2Array) -> PackedVector2Array:
	var time: float = Time.get_ticks_msec() / 1000.0
	var result: PackedVector2Array = input.duplicate()
	for i in result.size():
		var dir: Vector2
		if i < result.size() - 1:
			dir = (result[i + 1] - result[i]).normalized()
		else:
			dir = (result[i] - result[i - 1]).normalized()
		var perpendicular := Vector2(-dir.y, dir.x)
		result[i] += perpendicular * sin(i * frequency + time * speed) * amplitude
	return result
```

### Custom Break Module

```gdscript
class_name SimpleBreakModule extends CRopeBreakMod

@export var max_total_stretch: float = 1.5

func _check_break(data: CRopeData) -> int:
	var points := data.points
	var count := points.size()
	if count < 3:
		return -1
	var total_length: float = 0.0
	for i in count - 1:
		total_length += points[i].distance_to(points[i + 1])
	if total_length / (data.segment_length * (count - 1)) < max_total_stretch:
		return -1
	# Find the most stressed point — average of its two adjacent segments.
	# Measuring over segment pairs is stable regardless of how the constraint
	# solver distributes points along a taut rope (the Red-Black solver
	# settles into alternating segment lengths).
	var max_stress: float = 0.0
	var break_index: int = -1
	for i in range(1, count - 2):
		var stress := points[i - 1].distance_to(points[i]) + points[i].distance_to(points[i + 1])
		if stress > max_stress:
			max_stress = stress
			break_index = i
	return break_index
```

### Custom Render Module

```gdscript
class_name CircleRenderModule extends CRopeRenderMod

@export var radius: float = 5.0
@export var color: Color = Color.YELLOW

var _canvas: Node2D = null
var _cached_points: PackedVector2Array

func _render(data: CRopeData, render_points: PackedVector2Array) -> void:
	var r := get_rope()
	if r == null:
		return
	if _canvas == null:
		_canvas = Node2D.new()
		_canvas.name = "CircleRenderCanvas"
		_canvas.draw.connect(_on_draw)
		r.add_child(_canvas)
	_cached_points = render_points
	_canvas.queue_redraw()

func _cleanup() -> void:
	if _canvas != null:
		_canvas.queue_free()
		_canvas = null

func _on_draw() -> void:
	for point in _cached_points:
		_canvas.draw_circle(point, radius, color)
```

More examples are available in `cuberact-library-examples/CRope2D/scripts/custom_modules/`.

---

## Simulation Pipeline

Each frame, `simulate(delta)` runs the following steps in order:

1. **Anchor cache** — resolve node paths, compute anchor positions, apply collision correction to anchors. A sleeping rope runs only a cheap watchdog here and skips the rest of the frame until disturbed (see Sleep Properties).
2. **Local → Global transform** — transform points from local to global space for simulation
3. **Force modules** — all force modules contribute to a shared forces array
4. **Prepare collisions** — broadphase AABB query marks points near colliders
5. **Substep loop** (runs `substeps` times):
   - **Integrate forces** — Verlet integration: `pos += velocity + force * dt²`, with damping and anchor lerp
   - **Solve constraints** — maintain segment lengths (forward + optional backward pass)
   - **Resolve collisions** — every `collision_stride`-th substep: push points out of colliders, apply friction, detect pinch
6. **Rope sections** — group rope between anchors, calculate tension per section
7. **Anchor pull** — reaction forces on RigidBody2D anchors based on section tension
8. **Global → Local transform** — transform points from global back to local space
9. **Break modules** — evaluate break conditions on current-frame local data; on a break the remaining steps are skipped
10. **Line modules** — line modules transform render points (smooth, simplify, etc.)
11. **Render modules** — render modules draw the final visual

---

## CRopeDebugProbe

**Inherits:** RefCounted

Performance profiling object returned by `CRope2D.enable_debug_probe()`. All timing values are in microseconds (µs), averaged over the last `sample_count` frames (default 30).

### Timing Properties

| Property | Description |
|----------|-------------|
| `simulate_time` | Total simulation time. |
| `anchor_cache_time` | Anchor resolution and positioning. |
| `force_modules_time` | Force module execution. |
| `prepare_collisions_time` | Broadphase collision marking. |
| `substeps_time` | All substeps (integration + constraints + collisions). |
| `resolve_collisions_time` | Collision resolution within substeps. |
| `rope_sections_time` | Section and tension calculation. |
| `anchor_pull_time` | Pull force application. |
| `break_modules_time` | Break module checks. |
| `line_modules_time` | Line module processing. |
| `render_modules_time` | Render module execution. |
| `draw_time` | Actual draw calls. |

### Count Properties

| Property | Description |
|----------|-------------|
| `collision_count` | Collisions detected per frame. |
| `collision_queries_count` | Physics queries issued per frame. |
| `collision_points_count` | Points marked collision-active by the broadphase. |
| `render_points_count` | Points passed to renderers (after line processing). |
