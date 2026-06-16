extends Node2D
## Kite. A little guy on the meadow flies a kite in gusty wind. He is a
## static figure with one physical arm holding the line; the line collides
## with the ground and the scene frame, so the kite can drag it over the
## grass. Ten ribbon tails of various lengths flutter from the kite's tip.

const SCALE := 0.54 # the whole scene is uniformly scaled down from the old 2000 space to fit 1080 height
const SEGMENT_LENGTH := 22.0 * SCALE
const KITE_START := Vector2(1280, 720 * SCALE)
const GUY_POS := Vector2(520, 1745 * SCALE)
const TAIL_COUNT := 10
const WINCH_STEP := 0.05
const MIN_LINE_POINTS := 4

var _dev_tools: Node
var _rng := RandomNumberGenerator.new()
var _kite: RigidBody2D
var _arm: RigidBody2D
var _guy: RigidBody2D
var _line: CRope2D
var _kite_anchor: CRopeAnchor
var _max_line_points := 0
var _winch_timer := 0.0
var _time := 0.0
var _clouds: Array[Node2D] = []
var _cloud_speeds: Array[float] = []
var _tail_winds: Array[Dictionary] = []

func _ready() -> void:
	_rng.randomize()
	_dev_tools = get_node_or_null("DevTools")
	if _dev_tools:
		_dev_tools.add_controls_entries([
			["W / S", "unwind / wind the line"],
			["A / D", "walk left / right"],
			["SPACE", "jump"]
		])
	$Ground/Visual.color = Color(0.3, 0.55, 0.32)
	_spawn_clouds()
	_spawn_kite()
	_spawn_guy()
	_spawn_line()
	var hue := _rng.randf()
	for i in TAIL_COUNT:
		hue = fmod(hue + 0.618033988749895, 1.0)
		var length := _rng.randf_range(220.0, 880.0) * SCALE
		var angle := 90.0 + (float(i) - (TAIL_COUNT - 1) * 0.5) * 1.2
		_spawn_tail(angle, length, Color.from_hsv(hue, 0.75, 0.95), Color.from_hsv(hue, 0.3, 1.0))

func _physics_process(delta: float) -> void:
	_time += delta
	# Gusty lift from overlapping sines. The wind blows toward the upper right
	# on average: the horizontal force is almost never negative (the kite only
	# drifts left in brief lulls), and the lift swings around the kite's weight
	# so it keeps rising and sinking instead of parking at the ceiling.
	var gust := sin(_time * 0.7) * 0.5 + sin(_time * 1.9 + 1.3) * 0.3 + sin(_time * 0.23 + 2.1) * 0.45
	var sway := sin(_time * 0.4 + 0.7) * 0.6 + sin(_time * 1.1 + 4.0) * 0.4
	# The kite catches wind through its own motion through the air. Ambient wind
	# blows right, so whenever the kite is hauled upwind (by the guy running, or
	# by reeling the line in) its apparent wind rises and it lifts harder; drifting
	# downwind spills the wind and it sinks. No winch special-case, just the force.
	var catch := clampf((250.0 * SCALE - _kite.linear_velocity.x) / (250.0 * SCALE), 0.72, 1.6)
	_kite.apply_force(Vector2((280.0 + gust * 120.0 + sway * 160.0) * SCALE, -(850.0 + gust * 220.0) * catch * SCALE))
	# Tails stream downwind to the right, driven by the same gusts that lift the
	# kite: they whip out near-horizontal on a strong gust and droop in the lulls
	var tail_strength := (90.0 + maxf(gust + 0.3, 0.0) * 240.0) * SCALE
	for tw in _tail_winds:
		tw.mod.strength = tail_strength * tw.mult
	_update_winch(delta)
	var walk := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		walk -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		walk += 1.0
	if walk != 0.0:
		_guy.linear_velocity.x = move_toward(_guy.linear_velocity.x, walk * 300.0 * SCALE, 2400.0 * SCALE * delta)
	for i in _clouds.size():
		var cloud := _clouds[i]
		cloud.position.x += _cloud_speeds[i] * delta
		if cloud.position.x > 2100.0:
			cloud.position.x = -200.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE:
		# Jump roughly one body height, only while touching something
		if _guy.get_contact_count() > 0:
			_guy.apply_impulse(Vector2(0, -_guy.mass * 626.0 * SCALE))

func _update_winch(delta: float) -> void:
	var wind_in := Input.is_physical_key_pressed(KEY_S)
	var wind_out := Input.is_physical_key_pressed(KEY_W)
	if wind_in == wind_out:
		return
	_winch_timer -= delta
	if _winch_timer > 0.0:
		return
	_winch_timer = WINCH_STEP
	var data := _line.data
	var count := data.get_count()
	if wind_in and count > MIN_LINE_POINTS:
		data.remove(1)
	elif wind_out and count < _max_line_points:
		var pts := data.get_points()
		data.append(pts[0].lerp(pts[1], 0.5), 1)
	_kite_anchor.index = data.get_count() - 1

func _spawn_kite() -> void:
	_kite = RigidBody2D.new()
	_kite.position = KITE_START
	_kite.mass = 0.6
	_kite.gravity_scale = SCALE
	_kite.linear_damp = 1.0
	_kite.angular_damp = 4.0
	# Layer 2: the line and the tails (mask 1) pass through the kite body,
	# while the kite itself collides with the ground, the frame and the guy
	_kite.collision_layer = 2
	_kite.collision_mask = 3
	_kite.z_index = 6
	var col := CollisionPolygon2D.new()
	var diamond := PackedVector2Array([
		Vector2(0, -75) * SCALE, Vector2(55, 0) * SCALE, Vector2(0, 75) * SCALE, Vector2(-55, 0) * SCALE,
	])
	col.polygon = diamond
	_kite.add_child(col)

	var upper := Polygon2D.new()
	upper.polygon = PackedVector2Array([Vector2(0, -75) * SCALE, Vector2(55, 0) * SCALE, Vector2(-55, 0) * SCALE])
	upper.color = Color(0.9, 0.2, 0.18)
	_kite.add_child(upper)
	var lower := Polygon2D.new()
	lower.polygon = PackedVector2Array([Vector2(-55, 0) * SCALE, Vector2(55, 0) * SCALE, Vector2(0, 75) * SCALE])
	lower.color = Color(1.0, 0.55, 0.15)
	_kite.add_child(lower)
	var spar_v := Polygon2D.new()
	spar_v.polygon = PackedVector2Array([Vector2(-2, -75) * SCALE, Vector2(2, -75) * SCALE, Vector2(2, 75) * SCALE, Vector2(-2, 75) * SCALE])
	spar_v.color = Color(0.3, 0.2, 0.12)
	_kite.add_child(spar_v)
	var spar_h := Polygon2D.new()
	spar_h.polygon = PackedVector2Array([Vector2(-55, -2) * SCALE, Vector2(55, -2) * SCALE, Vector2(55, 2) * SCALE, Vector2(-55, 2) * SCALE])
	spar_h.color = Color(0.3, 0.2, 0.12)
	_kite.add_child(spar_h)
	add_child(_kite)

func _spawn_guy() -> void:
	_guy = RigidBody2D.new()
	var guy := _guy
	guy.position = GUY_POS
	guy.mass = 2.5
	guy.gravity_scale = SCALE
	guy.linear_damp = 0.5
	# Contact monitoring for the grounded check (jumping)
	guy.contact_monitor = true
	guy.max_contacts_reported = 4
	# He can never tip over, only translate
	guy.lock_rotation = true
	# Layer 2: the kite line and tails (mask 1) pass through him.
	# Mask 3: he collides with the grass, the frame (1) and the kite body (2).
	guy.collision_layer = 2
	guy.collision_mask = 3
	var shape := RectangleShape2D.new()
	shape.size = Vector2(64, 200) * SCALE
	var col := CollisionShape2D.new()
	col.shape = shape
	col.position = Vector2(0, 5) * SCALE
	guy.add_child(col)

	var wood := Color(0.85, 0.65, 0.45)
	for side in [-1.0, 1.0]:
		var leg := Polygon2D.new()
		leg.polygon = PackedVector2Array([
			Vector2(12.0 * side - 10.0, 40) * SCALE, Vector2(12.0 * side + 10.0, 40) * SCALE,
			Vector2(12.0 * side + 10.0, 105) * SCALE, Vector2(12.0 * side - 10.0, 105) * SCALE,
		])
		leg.color = Color(0.25, 0.35, 0.6)
		guy.add_child(leg)
	var torso := Polygon2D.new()
	torso.polygon = PackedVector2Array([
		Vector2(-28, -40) * SCALE, Vector2(28, -40) * SCALE, Vector2(28, 40) * SCALE, Vector2(-28, 40) * SCALE,
	])
	torso.color = Color(0.7, 0.25, 0.2)
	guy.add_child(torso)
	var left_arm := Polygon2D.new()
	left_arm.polygon = PackedVector2Array([
		Vector2(-28, -34) * SCALE, Vector2(-40, -30) * SCALE, Vector2(-44, 28) * SCALE, Vector2(-32, 28) * SCALE,
	])
	left_arm.color = Color(0.7, 0.25, 0.2).darkened(0.15)
	guy.add_child(left_arm)
	var head := Polygon2D.new()
	head.polygon = _circle_polygon(21.0 * SCALE)
	head.position = Vector2(0, -62) * SCALE
	head.color = wood
	guy.add_child(head)
	var eye := Polygon2D.new()
	eye.polygon = _circle_polygon(3.5 * SCALE)
	eye.position = Vector2(9, -66) * SCALE
	eye.color = Color(0.1, 0.08, 0.06)
	guy.add_child(eye)
	add_child(guy)

	# One physical arm pinned at the shoulder, the line tugs it around
	var shoulder := GUY_POS + Vector2(28, -34) * SCALE
	_arm = RigidBody2D.new()
	_arm.position = shoulder + Vector2(0, 29) * SCALE
	_arm.mass = 0.3
	_arm.gravity_scale = SCALE
	_arm.linear_damp = 0.2
	_arm.angular_damp = 2.0
	_arm.collision_layer = 0
	_arm.collision_mask = 0
	var hand_shape := CircleShape2D.new()
	hand_shape.radius = 9.0 * SCALE
	var hand_col := CollisionShape2D.new()
	hand_col.shape = hand_shape
	hand_col.position = Vector2(0, 29) * SCALE
	_arm.add_child(hand_col)
	var sleeve := Polygon2D.new()
	sleeve.polygon = PackedVector2Array([
		Vector2(-7, -29) * SCALE, Vector2(7, -29) * SCALE, Vector2(7, 18) * SCALE, Vector2(-7, 18) * SCALE,
	])
	sleeve.color = Color(0.7, 0.25, 0.2).darkened(0.1)
	_arm.add_child(sleeve)
	var hand := Polygon2D.new()
	hand.polygon = _circle_polygon(9.0 * SCALE)
	hand.position = Vector2(0, 26) * SCALE
	hand.color = wood
	_arm.add_child(hand)
	add_child(_arm)

	var joint := PinJoint2D.new()
	joint.position = shoulder
	# Maximum bias: the joint corrects almost the whole position error every
	# step, so the arm stays glued to the shoulder while the guy is dragged
	joint.bias = 0.9
	add_child(joint)
	joint.node_a = joint.get_path_to(guy)
	joint.node_b = joint.get_path_to(_arm)

func _spawn_line() -> void:
	var hand := _arm.position + Vector2(0, 26) * SCALE
	var attach := _kite.position + Vector2(-55, 0) * SCALE
	var seg_count := maxi(int(hand.distance_to(attach) / SEGMENT_LENGTH), 4)
	_max_line_points = seg_count * 3
	var data := CRopeData.new()
	data.create_line_by_count(hand, attach, seg_count)

	var rope := CRope2D.new()
	rope.data = data
	rope.collision_width = 8.0 * SCALE
	rope.damping = 0.3
	rope.z_index = 6
	var wind := CRopeWindForceMod.new()
	wind.direction = Vector2(1, 0)
	wind.strength = 80.0 * SCALE
	wind.variation = 0.6
	wind.frequency = 0.4
	var gravity := CRopeGravityForceMod.new()
	gravity.gravity = Vector2(0, 980.0 * SCALE)
	rope.force_modules = [gravity, wind]
	rope.line_modules = [CRopeSmoothLineMod.new()]
	var renderer := CRopeDirectRenderMod.new()
	renderer.width = 5.0 * SCALE
	renderer.color = Color(0.35, 0.32, 0.3)
	rope.render_modules = [renderer]
	add_child(rope)

	var anchor_hand := CRopeAnchor.new()
	anchor_hand.index = 0
	anchor_hand.node_path = rope.get_path_to(_arm)
	anchor_hand.offset_angle = 90.0
	anchor_hand.offset_distance = 26.0 * SCALE
	anchor_hand.pull_strength = 600.0 * SCALE
	anchor_hand.pull_damping = 0.5
	anchor_hand.collision_resolve = false

	var anchor_kite := CRopeAnchor.new()
	anchor_kite.index = seg_count
	anchor_kite.node_path = rope.get_path_to(_kite)
	anchor_kite.offset_angle = 180.0
	anchor_kite.offset_distance = 55.0 * SCALE
	anchor_kite.pull_strength = 2500.0 * SCALE
	anchor_kite.pull_damping = 0.4
	anchor_kite.collision_resolve = false

	rope.anchors = [anchor_hand, anchor_kite]
	_line = rope
	_kite_anchor = anchor_kite

	if _dev_tools:
		_dev_tools.register_debug_rope(rope)

func _spawn_tail(attach_angle: float, length: float, color_a: Color, color_b: Color) -> void:
	var rad := deg_to_rad(attach_angle)
	var start := _kite.position + Vector2(cos(rad), sin(rad)) * 72.0 * SCALE
	var seg_count := maxi(int(length / (_rng.randf_range(50.0, 60.0) * SCALE)), 4)
	var data := CRopeData.new()
	data.create_line_by_count(start, start + Vector2(0, length), seg_count)

	var rope := CRope2D.new()
	rope.data = data
	rope.collision_width = 8.0 * SCALE
	rope.substeps = 4
	rope.damping = 0.5
	rope.z_index = 5

	var sag := CRopeGravityForceMod.new()
	sag.gravity = Vector2(0, 150) * SCALE
	var flutter := CRopeWindForceMod.new()
	flutter.direction = Vector2(1, 0)
	var mult := _rng.randf_range(0.85, 1.15)
	flutter.strength = 160.0 * SCALE * mult
	flutter.variation = 0.4
	flutter.frequency = _rng.randf_range(0.6, 1.0)
	rope.force_modules = [sag, flutter]
	_tail_winds.append({"mod": flutter, "mult": mult})

	rope.line_modules = [CRopeSubdivideLineMod.new()]
	var renderer := CRopeLine2DRenderMod.new()
	renderer.width = 8.0 * SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([color_a, color_b])
	renderer.gradient = grad
	renderer.joint_mode = Line2D.LINE_JOINT_ROUND
	renderer.begin_cap_mode = Line2D.LINE_CAP_ROUND
	renderer.end_cap_mode = Line2D.LINE_CAP_ROUND
	renderer.antialiased = true

	rope.render_modules = [renderer]
	add_child(rope)

	var anchor := CRopeAnchor.new()
	anchor.index = 0
	anchor.node_path = rope.get_path_to(_kite)
	anchor.offset_angle = attach_angle
	anchor.offset_distance = 72.0 * SCALE
	anchor.pull_strength = 0.0
	anchor.collision_resolve = false
	rope.anchors = [anchor]

	if _dev_tools:
		_dev_tools.register_debug_rope(rope)

func _spawn_clouds() -> void:
	var texture := _make_radial_texture(Color(1, 1, 1))
	for i in 6:
		var cloud := Node2D.new()
		cloud.position = Vector2(_rng.randf_range(0, 1920), _rng.randf_range(150, 900) * SCALE)
		cloud.modulate.a = _rng.randf_range(0.55, 0.75)
		for blob in 3:
			var sprite := Sprite2D.new()
			sprite.texture = texture
			sprite.position = Vector2((blob - 1) * _rng.randf_range(75.0, 115.0) * SCALE, absf(blob - 1) * 20.0 * SCALE)
			var s := _rng.randf_range(0.9, 1.3) * (1.4 if blob == 1 else 0.9)
			sprite.scale = Vector2(s * 1.6, s * 0.9) * SCALE
			cloud.add_child(sprite)
		add_child(cloud)
		_clouds.append(cloud)
		_cloud_speeds.append(_rng.randf_range(12.0, 30.0) * SCALE)

func _circle_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points

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
