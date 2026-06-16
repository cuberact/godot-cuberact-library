extends Node2D
## Firefly meadow. Fireflies tethered to grass roots by barely visible
## threads. Each one buzzes on its own thin rope, blinking softly. Drag a
## firefly and let it go to watch the tether snap it back.

const FIREFLY_COUNT := 300
const SCALE := 0.54 # the whole scene is uniformly scaled down from the old 2000 space to fit 1080 height
const SEGMENT_LENGTH := 18.0 * SCALE

const FLY_HUE_MIN := 0.0  # yellow to red
const FLY_HUE_MAX := 0.15
const THREAD_HUE_MIN := 0.06  # warm: amber to yellow-green
const THREAD_HUE_MAX := 0.38

var _dev_tools: Node
var _rng := RandomNumberGenerator.new()
var _fireflies: Array[Dictionary] = []
var _time := 0.0

func _ready() -> void:
	_rng.randomize()
	_dev_tools = get_node_or_null("DevTools")
	if _dev_tools:
		_dev_tools.add_controls_entries([["Left mouse", "drag a firefly"]])
	for i in FIREFLY_COUNT:
		var x := 120.0 + 1760.0 * (i + 0.5) / FIREFLY_COUNT + _rng.randf_range(-40.0, 40.0)
		_spawn_firefly(i, Vector2(x, 1870 * SCALE))
	# Draw the scene border over the fireflies so strays vanish past the edge;
	# keep the dev tools overlay on top of the border
	var walls := get_node_or_null("Walls")
	if walls:
		move_child(walls, -1)
	if _dev_tools:
		move_child(_dev_tools, -1)

func _physics_process(delta: float) -> void:
	_time += delta
	for fly in _fireflies:
		var body: RigidBody2D = fly.body
		var blink: float = pow(maxf(sin(_time * fly.blink + fly.phase), 0.0), 4.0)
		fly.glow.modulate.a = 0.15 + 0.6 * blink
		var c: Color = fly.tcolor
		var lit := c.lightened(0.5 * blink)
		fly.grad.colors = PackedColorArray([
			Color(c.r, c.g, c.b, 0.05 + 0.05 * blink),
			Color(lit.r, lit.g, lit.b, 0.18 + 0.5 * blink),
			Color(lit.r, lit.g, lit.b, 0.35 + 0.65 * blink),
		])
		fly.renderer.width = (2.0 + 4.0 * blink) * SCALE
		fly.retarget -= delta
		if fly.retarget <= 0.0:
			fly.retarget = _rng.randf_range(1.0, 2.5)
			fly.target = fly.root + Vector2(_rng.randf_range(-300, 300) * SCALE, -_rng.randf_range(150 * SCALE, fly.reach))
		var steer: Vector2 = (fly.target - body.position).normalized() * 120.0 * SCALE
		steer += Vector2(sin(_time * 9.0 + fly.phase), cos(_time * 11.0 + fly.phase)) * 60.0 * SCALE
		body.apply_force(steer)

func _spawn_firefly(idx: int, root_pos: Vector2) -> void:
	var root := Node2D.new()
	root.position = root_pos
	add_child(root)

	var length := _rng.randf_range(1000.0, 1800.0) * SCALE
	var body := RigidBody2D.new()
	body.position = root_pos + Vector2(0, -length * 1.0)
	body.mass = 0.1
	body.gravity_scale = 0.0
	body.linear_damp = 3.0
	body.collision_mask = 0
	var shape := CircleShape2D.new()
	shape.radius = 10.0 * SCALE
	var col := CollisionShape2D.new()
	col.shape = shape
	body.add_child(col)

	var hue := FLY_HUE_MIN + fposmod(idx * 0.618034, 1.0) * (FLY_HUE_MAX - FLY_HUE_MIN)
	var color := Color.from_hsv(hue, _rng.randf_range(0.5, 0.85), 1.0)
	var thread_hue := THREAD_HUE_MIN + fposmod(idx * 0.618034 + 0.5, 1.0) * (THREAD_HUE_MAX - THREAD_HUE_MIN)
	var thread_color := Color.from_hsv(thread_hue, _rng.randf_range(0.5, 0.85), 1.0)
	var glow := Sprite2D.new()
	glow.texture = _make_radial_texture(color)
	glow.scale = Vector2.ONE * 0.55 * SCALE
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add_mat
	glow.modulate.a = 0.15  # calm baseline; _physics_process drives it, but frame 0 must not flash at full additive alpha
	body.add_child(glow)
	var core := Polygon2D.new()
	core.polygon = _circle_polygon(5.0 * SCALE)
	core.color = color.lightened(0.6)
	body.add_child(core)
	add_child(body)

	var seg_count := maxi(int(length / SEGMENT_LENGTH), 4)
	var data := CRopeData.new()
	data.create_line_by_count(root_pos, body.position, seg_count)
	data.segment_length = data.segment_length * (length / root_pos.distance_to(body.position))

	var rope := CRope2D.new()
	rope.data = data
	rope.sleep_enabled = false
	rope.collision_mask = 0
	rope.substeps = 4
	rope.damping = 0.2
	var sag := CRopeGravityForceMod.new()
	sag.gravity = Vector2(0, 10) * SCALE
	rope.force_modules = [sag]
	rope.line_modules = [CRopeSmoothLineMod.new(), CRopeSimplifyLineMod.new()]
	var renderer := CRopeDirectRenderMod.new()
	renderer.width = 2.0 * SCALE  # calm baseline; _physics_process drives it, but frame 0 must not flash at the default 10px
	renderer.begin_cap_mode = Line2D.LINE_CAP_NONE
	renderer.end_cap_mode = Line2D.LINE_CAP_NONE
	renderer.joint_mode = Line2D.LINE_JOINT_SHARP
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	grad.colors = PackedColorArray([
		Color(thread_color.r, thread_color.g, thread_color.b, 0.05),
		Color(thread_color.r, thread_color.g, thread_color.b, 0.18),
		Color(thread_color.r, thread_color.g, thread_color.b, 0.35),
	])
	renderer.gradient = grad
	rope.render_modules = [renderer]
	add_child(rope)

	var anchor_root := CRopeAnchor.new()
	anchor_root.index = 0
	anchor_root.node_path = rope.get_path_to(root)
	anchor_root.pull_strength = 0.0
	anchor_root.collision_resolve = false

	var anchor_fly := CRopeAnchor.new()
	anchor_fly.index = seg_count
	anchor_fly.node_path = rope.get_path_to(body)
	anchor_fly.pull_strength = 0.0
	anchor_fly.pull_damping = 0.5
	anchor_fly.collision_resolve = false

	rope.anchors = [anchor_root, anchor_fly]

	if _dev_tools:
		_dev_tools.register_debug_rope(rope)

	_fireflies.append({
		"body": body,
		"glow": glow,
		"grad": grad,
		"renderer": renderer,
		"tcolor": thread_color,
		"root": root_pos,
		"reach": length * 1.0,
		"target": body.position,
		"retarget": 0.0,
		"blink": _rng.randf_range(1.2, 2.5),
		"phase": _rng.randf_range(0.0, TAU),
	})

func _make_radial_texture(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([
		color,
		Color(color.r, color.g, color.b, 0.3),
		Color(color.r, color.g, color.b, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture

func _circle_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points
