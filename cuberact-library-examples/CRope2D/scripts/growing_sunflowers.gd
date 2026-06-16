extends Node2D
## Growing sunflowers. Ropes that grow at runtime, point by point, via
## CRopeData.append(). Each stem sways in a light breeze and leans toward
## the draggable sun (a custom phototropism force). A sunflower head blooms
## at every tip and leaves unfurl along the stem. SPACE replants the garden.

const VINE_COUNT := 50
const SCALE := 0.54 # the whole scene is uniformly scaled down from the old 2000 space to fit 1080 height
# Short segments added often: the tip grows in small steps so it reads as smooth
const SEGMENT_LENGTH := 11.0 * SCALE

var _dev_tools: Node
var _rng := RandomNumberGenerator.new()
var _vines: Array[Dictionary] = []
var _basal: Array[Dictionary] = []
var _sky: Polygon2D

func _ready() -> void:
	_rng.randomize()
	_sky = $Sky
	_dev_tools = get_node_or_null("DevTools")
	if _dev_tools:
		_dev_tools.add_controls_entries([
			["Left mouse", "drag the sun"],
			["SPACE", "replant the garden"],
		])
	_decorate_sun()
	_plant_garden()
	_spawn_basal_leaves()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE:
		_replant()

func _physics_process(delta: float) -> void:
	var t := clampf($Sun.position.y / (1600.0 * SCALE), 0.0, 1.0)
	var top := Color(0.30, 0.52, 0.82).lerp(Color(0.10, 0.10, 0.26), t)
	var bot := Color(0.66, 0.80, 0.92).lerp(Color(0.86, 0.42, 0.30), t)
	_sky.vertex_colors = PackedColorArray([top, top, bot, bot])
	for bl in _basal:
		if bl.delay > 0.0:
			bl.delay -= delta
		elif bl.t < 1.0:
			bl.node.visible = true
			bl.t += delta * bl.rate
			bl.node.scale = bl.base_scale * smoothstep(0.0, 1.0, clampf(bl.t, 0.0, 1.0))
	var sun_pos: Vector2 = $Sun.position
	for vine in _vines:
		var rope: CRope2D = vine.rope
		if not is_instance_valid(rope) or rope.data == null:
			continue
		var count := rope.data.get_count()
		if count < vine.max_points:
			vine.timer -= delta
			if vine.timer <= 0.0:
				vine.timer = vine.interval
				_grow(rope.data)
		var pts := rope.data.get_points()
		var flower: Node2D = vine.flower
		flower.position = flower.position.lerp(pts[count - 1], 0.3)
		flower.scale = Vector2.ONE * vine.flower_scale * clampf(float(count) / float(vine.max_points), 0.15, 1.0)
		var dir := sun_pos - flower.position
		if dir.length() > 1.0:
			dir = dir.normalized()
			var face_up := -dir.y
			var head: Node2D = vine.head
			head.scale = Vector2(1.0, lerpf(0.3, 1.0, absf(face_up)))
			head.rotation = lerp_angle(head.rotation, dir.x * 0.45, 0.12)
			vine.gold.modulate.a = clampf(0.5 + face_up * 0.7, 0.0, 1.0)
			vine.green.modulate.a = clampf(0.5 - face_up * 0.7, 0.0, 1.0)
		flower.visible = true
		for leaf in vine.leaves:
			if count <= leaf.index + 1:
				continue
			var tan: Vector2 = (pts[leaf.index] - pts[leaf.index - 1]).normalized()
			leaf.node.position = pts[leaf.index]
			leaf.node.rotation = tan.angle() + leaf.side * 0.95
			leaf.node.scale = Vector2.ONE * leaf.scale * clampf(float(count - leaf.index) / 12.0, 0.0, 1.0)
			leaf.node.visible = true

func _grow(data: CRopeData) -> void:
	var pts := data.get_points()
	var n := pts.size()
	var dir := (pts[n - 1] - pts[n - 2]).normalized()
	dir = dir.rotated(_rng.randf_range(-0.35, 0.35))
	dir = (dir + Vector2(0, -0.4)).normalized()
	data.append(pts[n - 1] + dir * SEGMENT_LENGTH)

func _plant_garden() -> void:
	for i in VINE_COUNT:
		var x := 200.0 + 1600.0 * (i + 0.5) / VINE_COUNT + _rng.randf_range(-40.0, 40.0)
		_spawn_vine(Vector2(x, 1900 * SCALE))

func _replant() -> void:
	for vine in _vines:
		for key in ["rope", "root", "flower"]:
			if is_instance_valid(vine[key]):
				vine[key].queue_free()
		for leaf in vine.leaves:
			if is_instance_valid(leaf.node):
				leaf.node.queue_free()
	_vines.clear()
	for bl in _basal:
		if is_instance_valid(bl.node):
			bl.node.queue_free()
	_basal.clear()
	_plant_garden()
	_spawn_basal_leaves()

func _spawn_vine(root_pos: Vector2) -> void:
	var root := Node2D.new()
	root.position = root_pos
	add_child(root)

	var data := CRopeData.new()
	data.create_line_by_count(root_pos, root_pos + Vector2(0, -2.0 * SEGMENT_LENGTH), 2)

	var rope := CRope2D.new()
	rope.data = data
	rope.collision_mask = 0
	rope.substeps = 6
	rope.damping = 0.92

	var base_rise := _rng.randf_range(120.0, 180.0) * SCALE
	var rise := CRopeGravityForceMod.new()
	rise.gravity = Vector2(0, -base_rise)
	var breeze := CRopeWindForceMod.new()
	breeze.direction = Vector2(1, 0)
	breeze.strength = _rng.randf_range(12.0, 25.0) * SCALE
	breeze.variation = 0.9
	breeze.frequency = _rng.randf_range(0.2, 0.35)
	rope.line_modules = [CRopeSmoothLineMod.new()]

	var renderer := CRopeDirectRenderMod.new()
	renderer.width = _rng.randf_range(8.0, 13.0) * SCALE
	var hue := _rng.randf_range(0.3, 0.42)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([
		Color.from_hsv(hue, 0.85, 0.3),
		Color.from_hsv(hue, 0.6, 0.8),
	])
	renderer.gradient = grad
	renderer.joint_mode = Line2D.LINE_JOINT_SHARP
	renderer.begin_cap_mode = Line2D.LINE_CAP_ROUND
	renderer.end_cap_mode = Line2D.LINE_CAP_ROUND
	rope.render_modules = [renderer]
	add_child(rope)

	# The flower (the rope tip) is what seeks the sun, and it weighs the tip down.
	# The stem keeps its own upward vigor, so it stays upright and bears the head.
	var flower_force := FlowerForce.new()
	flower_force.sun = $Sun
	flower_force.weight = _rng.randf_range(90.0, 130.0) * SCALE
	flower_force.pull = _rng.randf_range(100.0, 150.0) * SCALE
	rope.force_modules = [rise, breeze, flower_force]

	var anchor := CRopeAnchor.new()
	anchor.index = 0
	anchor.node_path = rope.get_path_to(root)
	anchor.pull_strength = 0.0
	anchor.collision_resolve = false
	rope.anchors = [anchor]

	var max_pts := _rng.randi_range(60, 105)
	var fl := _spawn_flower()
	var flower: Node2D = fl.node
	flower.position = root_pos
	flower.visible = false  # revealed on the first physics frame, once scaled down from its full default size

	var leaf_green := Color.from_hsv(_rng.randf_range(0.28, 0.36), 0.55, 0.5)
	var leaves: Array[Dictionary] = []
	var leaf_count := _rng.randi_range(2, 3)
	for li in leaf_count:
		var frac := lerpf(0.3, 0.82, (float(li) + 0.5) / float(leaf_count))
		var leaf_node := _spawn_leaf(leaf_green)
		leaf_node.visible = false
		leaves.append({
			"node": leaf_node,
			"index": int(max_pts * frac),
			"side": -1.0 if li % 2 == 0 else 1.0,
			"scale": _rng.randf_range(0.7, 1.0) * SCALE,
		})

	if _dev_tools:
		_dev_tools.register_debug_rope(rope)

	_vines.append({
		"rope": rope,
		"root": root,
		"flower": flower,
		"head": fl.head,
		"gold": fl.gold,
		"green": fl.green,
		"leaves": leaves,
		"max_points": max_pts,
		"interval": _rng.randf_range(0.06, 0.12),
		"timer": 0.5,
		"flower_scale": _rng.randf_range(0.5, 0.75) * SCALE,
	})

func _spawn_basal_leaves() -> void:
	# Big burdock leaves at ground level, drawn over the stem bases so the bare
	# planting line is hidden; they swell in from nothing, staggered
	var count := 36
	for i in count:
		var x := 120.0 + 1760.0 * (i + 0.5) / count + _rng.randf_range(-55.0, 55.0)
		var leaf := _make_burdock_leaf()
		leaf.position = Vector2(x, (1898.0 + _rng.randf_range(-8.0, 6.0)) * SCALE)
		var ang := _rng.randf_range(0.3, 1.2)
		leaf.rotation = ang if _rng.randf() < 0.5 else -ang
		leaf.scale = Vector2.ZERO
		leaf.visible = false  # hidden until it swells in; a zero-scale node flashes at full size on its first frame
		add_child(leaf)
		var s := _rng.randf_range(0.4, 0.78)
		var flip := -1.0 if _rng.randf() < 0.5 else 1.0
		_basal.append({
			"node": leaf,
			"base_scale": Vector2(s * flip, s) * SCALE,
			"delay": _rng.randf_range(2.5, 6.0),
			"t": 0.0,
			"rate": _rng.randf_range(0.18, 0.3),
		})

func _make_burdock_leaf() -> Node2D:
	var node := Node2D.new()
	var h := 210.0
	var w := 230.0
	var green := Color.from_hsv(_rng.randf_range(0.28, 0.36), _rng.randf_range(0.5, 0.72), _rng.randf_range(0.32, 0.5))
	var blade := Polygon2D.new()
	blade.polygon = PackedVector2Array([
		Vector2(0, 0),
		Vector2(-w * 0.28, -h * 0.08),
		Vector2(-w * 0.5, -h * 0.32),
		Vector2(-w * 0.44, -h * 0.6),
		Vector2(-w * 0.2, -h * 0.82),
		Vector2(0, -h),
		Vector2(w * 0.2, -h * 0.82),
		Vector2(w * 0.44, -h * 0.6),
		Vector2(w * 0.5, -h * 0.32),
		Vector2(w * 0.28, -h * 0.08),
	])
	blade.color = green
	node.add_child(blade)
	var vein := green.darkened(0.28)
	var midrib := Polygon2D.new()
	midrib.polygon = PackedVector2Array([Vector2(-3, 0), Vector2(3, 0), Vector2(1.2, -h * 0.95), Vector2(-1.2, -h * 0.95)])
	midrib.color = vein
	node.add_child(midrib)
	for sy in [0.32, 0.58]:
		for sx in [-1.0, 1.0]:
			var side := Polygon2D.new()
			var yb: float = -h * sy
			side.polygon = PackedVector2Array([
				Vector2(0, yb + 4), Vector2(0, yb - 4), Vector2(sx * w * 0.42, -h * (sy + 0.16)),
			])
			side.color = vein
			node.add_child(side)
	return node

func _spawn_flower() -> Dictionary:
	var flower := Node2D.new()
	var head := Node2D.new()
	flower.add_child(head)
	var green := _make_greenback()
	head.add_child(green)
	var gold := _make_goldface()
	head.add_child(gold)
	add_child(flower)
	return {"node": flower, "head": head, "gold": gold, "green": green}

func _make_goldface() -> Node2D:
	var face := Node2D.new()
	var gold := Color.from_hsv(_rng.randf_range(0.1, 0.14), 0.85, 1.0)
	var glow := Sprite2D.new()
	glow.texture = _make_radial_texture(gold)
	glow.scale = Vector2.ONE * 0.7
	glow.modulate.a = 0.5
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add_mat
	face.add_child(glow)
	var petal := PackedVector2Array([
		Vector2(22, -7), Vector2(42, -6), Vector2(60, 0), Vector2(42, 6), Vector2(22, 7),
	])
	for i in 18:
		var p := Polygon2D.new()
		p.polygon = petal
		p.rotation = TAU * float(i) / 18.0
		p.color = gold.darkened(0.04 * float(i % 3))
		face.add_child(p)
	var disc := Polygon2D.new()
	disc.polygon = _circle_polygon(30.0)
	disc.color = Color(0.3, 0.17, 0.07)
	face.add_child(disc)
	var disc_mid := Polygon2D.new()
	disc_mid.polygon = _circle_polygon(21.0)
	disc_mid.color = Color(0.43, 0.27, 0.11)
	face.add_child(disc_mid)
	var disc_core := Polygon2D.new()
	disc_core.polygon = _circle_polygon(10.0)
	disc_core.color = Color(0.24, 0.13, 0.06)
	face.add_child(disc_core)
	return face

func _make_greenback() -> Node2D:
	var back := Node2D.new()
	var disc := Polygon2D.new()
	disc.polygon = _circle_polygon(48.0)
	disc.color = Color(0.26, 0.4, 0.19)
	back.add_child(disc)
	var bract := PackedVector2Array([Vector2(40, -10), Vector2(66, 0), Vector2(40, 10)])
	for i in 12:
		var b := Polygon2D.new()
		b.polygon = bract
		b.rotation = TAU * float(i) / 12.0
		b.color = Color(0.2, 0.33, 0.15)
		back.add_child(b)
	var center := Polygon2D.new()
	center.polygon = _circle_polygon(30.0)
	center.color = Color(0.31, 0.46, 0.23)
	back.add_child(center)
	return back

func _spawn_leaf(color: Color) -> Polygon2D:
	var leaf := Polygon2D.new()
	var l := 56.0
	var w := 24.0
	leaf.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(l * 0.35, -w), Vector2(l * 0.72, -w * 0.65),
		Vector2(l, 0), Vector2(l * 0.72, w * 0.65), Vector2(l * 0.35, w),
	])
	leaf.color = color
	var rib := Polygon2D.new()
	rib.polygon = PackedVector2Array([
		Vector2(0, -1.6), Vector2(l, -0.5), Vector2(l, 0.5), Vector2(0, 1.6),
	])
	rib.color = color.darkened(0.3)
	leaf.add_child(rib)
	add_child(leaf)
	return leaf

func _decorate_sun() -> void:
	var sun: Node2D = $Sun
	var glow := Sprite2D.new()
	glow.texture = _make_radial_texture(Color(1.0, 0.85, 0.5))
	glow.scale = Vector2.ONE * 1.8
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add_mat
	sun.add_child(glow)
	var core := Polygon2D.new()
	core.polygon = _circle_polygon(46.0)
	core.color = Color(1.0, 0.95, 0.75)
	sun.add_child(core)

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
	for i in 20:
		var a := TAU * i / 20.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points

## Acts on the flower alone (the rope tip), pulling it toward the sun and
## weighing it down. The stem's own upward force keeps the rest of it upright,
## so the stem stays standing and bears the head while the bloom leans to light.
class FlowerForce extends CRopeForceMod:
	var sun: Node2D
	var weight := 0.0
	var pull := 0.0

	func _update_forces(forces: PackedVector2Array, data: CRopeData, _delta: float) -> PackedVector2Array:
		var n := forces.size()
		if n < 2 or sun == null or not is_instance_valid(sun):
			return forces
		var pts := data.get_points()
		var sp := sun.global_position
		# Pull the flexible upper stem toward the sun, strongest at the flower, so
		# the top arcs right over toward a low sun while the woody base stays put
		var span := maxi(int(float(n) * 0.5), 1)
		var start := n - span
		for i in range(start, n):
			forces[i] += (sp - pts[i]).normalized() * pull * (float(i - start + 1) / float(span))
		# The heavy head weighs the very tip down
		forces[n - 1] += Vector2(0, weight)
		return forces
