extends Node2D
## Jellyfish. Pulsing bells drifting through dark water, each trailing six
## rope tentacles. A periodic thrust force and a squash of the bell visual
## make the pulse; the tentacles follow with high water damping. Light shafts,
## a vignette and a bioluminescent pulse flowing down the tentacle gradients
## dress the scene.

const JELLY_COUNT := 10
const SEGMENT_LENGTH := 11.0
const BELL_FLATTEN := 0.8
const BIOLUME_STRENGTH := 0.8
const TENTACLE_COUNT := 10
const TENTACLE_WIDTH := 5
const TENTACLE_LENGTH := 185

const GRASS_COUNT := 300
const GRASS_MIN_LENGTH := 140.0
const GRASS_MAX_LENGTH := 560.0
const GRASS_SHORT_BIAS := 1.0  # 1.0 = uniform lengths, higher = more short blades
const GRASS_LIFT_MIN := 32.0  # buoyancy = how upright the blades stand
const GRASS_LIFT_MAX := 54.0
const GRASS_CURRENT_MIN := 0.0  # current swing strength, waves both left and right
const GRASS_CURRENT_MAX := 43.0
const GRASS_HUE_MIN := 0.42  # cool teal to cyan, recedes behind the jellyfish
const GRASS_HUE_MAX := 0.58
const GRASS_ALPHA_ROOT := 0.0
const GRASS_ALPHA_TIP := 0.2

# Effect toggles, live-editable while running via the Remote tab
@export_group("Toggles")
@export var rays_on := true
@export var vignette_on := true
@export var biolume_on := true
@export var bell_glow_on := true
@export var plankton_on := true

var _biolume_falloff := Curve.new()
var _dev_tools: Node
var _rng := RandomNumberGenerator.new()
var _jellies: Array[Dictionary] = []
var _rays: Array[Dictionary] = []
var _vignette: Sprite2D
var _plankton: CPUParticles2D
var _time := 0.0

func _ready() -> void:
	_rng.randomize()
	# Hand-tuned biolume pulse falloff (0 = bell, 1 = tip), ends at zero to avoid a pop
	_biolume_falloff.add_point(Vector2(0.0, 1.0))
	_biolume_falloff.add_point(Vector2(0.5, 0.8), -0.99, -0.99)
	_biolume_falloff.add_point(Vector2(1.0, 0.0))
	_dev_tools = get_node_or_null("DevTools")
	if _dev_tools:
		_dev_tools.add_controls_entries([["Left mouse", "drag jellyfish or seagrass"]])
	_plankton = get_node_or_null("Bubbles")
	_spawn_rays()
	_spawn_seagrass()
	for i in JELLY_COUNT:
		var pos := Vector2(200.0 + 1520.0 * (i + 0.5) / JELLY_COUNT, _rng.randf_range(340, 560))
		_spawn_jelly(pos)
	_spawn_vignette()

func _physics_process(delta: float) -> void:
	_time += delta
	if _vignette:
		_vignette.visible = vignette_on
	if _plankton:
		_plankton.visible = plankton_on
	for ray in _rays:
		ray.node.visible = rays_on
		if not rays_on:
			continue
		ray.node.rotation = sin(_time * 0.08 + ray.phase) * 0.03
		ray.node.position.x = ray.base_x + sin(_time * 0.05 + ray.phase * 2.3) * 35.0
		ray.node.modulate.a = 0.55 + 0.25 * sin(_time * 0.31 + ray.phase) + 0.2 * sin(_time * 0.17 + ray.phase * 1.7)
	for jelly in _jellies:
		var bell: RigidBody2D = jelly.bell
		var cycle := fposmod(_time * jelly.freq + jelly.phase, TAU) / TAU
		var contraction := smoothstep(0.0, 0.1, cycle) * (1.0 - smoothstep(0.1, 1.0, cycle))
		var thrust := sin(cycle / 0.15 * PI) if cycle < 0.15 else 0.0
		var drift := sin(_time * 0.2 + jelly.phase) * 32.0
		var boost := 1.0 + (bell.position.y - 450.0) * 0.0004
		bell.apply_force(Vector2(drift, -thrust * 1130.0).rotated(bell.rotation) * boost)
		# Slowly right the bell toward upright (~25 s from a 90-degree tilt)
		bell.angular_velocity -= wrapf(bell.rotation, -PI, PI) * 0.8 * delta
		var squash := Vector2(1.0 - 0.28 * contraction, 1.0 + 0.2 * contraction)
		jelly.dome.scale = squash
		jelly.inner.scale = squash
		# Collider follows the squash (capsule is rotated, so height = width axis)
		jelly.shape.radius = 20.0 * squash.y
		jelly.shape.height = maxf(68.0 * squash.x, jelly.shape.radius * 2.0 + 1.0)
		jelly.glow.visible = bell_glow_on
		var flash := sin(cycle / 0.2 * PI) if cycle < 0.2 else 0.0
		jelly.glow.scale = Vector2(0.49, 0.39) * squash * (1.0 + 0.25 * flash)
		var glow_level := 0.75 + 0.85 * flash
		jelly.glow.modulate = Color(glow_level, glow_level, glow_level)
		var wave := (cycle - 0.08) / 0.55
		var wave_strength := 0.0
		if biolume_on and wave >= 0.0 and wave <= 1.0:
			wave_strength = _biolume_falloff.sample(wave) * BIOLUME_STRENGTH
		for t in jelly.tentacles:
			var p := Vector2(cos(t.rad), sin(t.rad) * BELL_FLATTEN) * 30.0 * squash
			t.anchor.offset_distance = p.length()
			t.anchor.offset_angle = rad_to_deg(p.angle())
			if wave_strength > 0.0:
				var cols := PackedColorArray(t.base_colors)
				for k in cols.size():
					var d := (float(k) / float(cols.size() - 1) - wave) * 6.0
					var g := wave_strength * exp(-d * d)
					if g > 0.02:
						var c := cols[k].lightened(0.7 * g)
						c.a = minf(c.a + 0.6 * g, 1.0)
						cols[k] = c
				t.grad.colors = cols
				t.lit = true
			elif t.lit:
				t.grad.colors = t.base_colors
				t.lit = false

func _spawn_jelly(pos: Vector2) -> void:
	var bell := RigidBody2D.new()
	bell.position = pos
	bell.mass = 1.5
	bell.gravity_scale = 0.07
	bell.linear_damp = 1.4
	bell.angular_damp = 4.0
	bell.collision_layer = 1
	var shape := CapsuleShape2D.new()
	shape.radius = 20.0
	shape.height = 68.0
	var col := CollisionShape2D.new()
	col.shape = shape
	col.rotation = PI / 2
	col.position = Vector2(0, -3)
	bell.add_child(col)

	var hue := _rng.randf_range(0.64, 0.92)
	var body_color := Color.from_hsv(hue, _rng.randf_range(0.4, 0.62), 1.0, 0.6)

	var glow := Sprite2D.new()
	glow.texture = _make_radial_texture(body_color)
	glow.scale = Vector2(0.49, 0.39)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add_mat
	bell.add_child(glow)

	var dome := Polygon2D.new()
	dome.polygon = _dome_polygon(35.0)
	dome.color = body_color
	bell.add_child(dome)
	var inner := Polygon2D.new()
	inner.polygon = _dome_polygon(24.0)
	inner.position = Vector2(0, 3)
	inner.color = body_color.lightened(0.8)
	bell.add_child(inner)

	add_child(bell)

	var tentacles: Array[Dictionary] = []
	for t in TENTACLE_COUNT:
		var angle := lerpf(40.0, 140.0, float(t) / float(TENTACLE_COUNT - 1))
		var info := _spawn_tentacle(bell, angle, body_color)
		info["rad"] = deg_to_rad(angle)
		tentacles.append(info)

	_jellies.append({
		"bell": bell,
		"dome": dome,
		"inner": inner,
		"glow": glow,
		"shape": shape,
		"tentacles": tentacles,
		"freq": _rng.randf_range(1.1, 1.6),
		"phase": _rng.randf_range(0.0, TAU),
	})

func _spawn_tentacle(bell: RigidBody2D, attach_angle: float, color: Color) -> Dictionary:
	var rad := deg_to_rad(attach_angle)
	var attach := Vector2(cos(rad), sin(rad) * BELL_FLATTEN) * 30.0
	var start := bell.position + attach
	var length := _rng.randf_range(TENTACLE_LENGTH - 27.0, TENTACLE_LENGTH + 27.0)
	var seg_count := maxi(int(length / SEGMENT_LENGTH), 4)
	var data := CRopeData.new()
	data.create_line_by_count(start, start + Vector2((attach_angle - 90.0) * 0.65, length), seg_count)

	var rope := CRope2D.new()
	rope.data = data
	rope.collision_mask = 1
	rope.collision_width = TENTACLE_WIDTH
	rope.substeps = 6
	rope.damping = 0.9
	var sink := CRopeGravityForceMod.new()
	sink.gravity = Vector2(0, 86)
	var current := CRopeWindForceMod.new()
	current.direction = Vector2(1, 0)
	current.strength = _rng.randf_range(8.0, 16.0)
	current.variation = 0.9
	current.frequency = _rng.randf_range(0.2, 0.25)
	var current2 := CRopeWindForceMod.new()
	current2.direction = Vector2(-1, 0)
	current2.strength = _rng.randf_range(8.0, 16.0)
	current2.variation = 0.9
	current2.frequency = _rng.randf_range(0.1, 0.35)
	rope.force_modules = [sink, current, current2]
	rope.line_modules = [CRopeSmoothLineMod.new()]
	var renderer := CRopeDirectRenderMod.new()
	renderer.width = _rng.randf_range(TENTACLE_WIDTH - 1.0, TENTACLE_WIDTH + 1.0)
	var grad := Gradient.new()
	var offsets := PackedFloat32Array()
	var base_colors := PackedColorArray()
	var root_col := color.lightened(0.2)
	var tip_col := color.lightened(0.0)
	for k in 11:
		var f := float(k) / 10.0
		var c := root_col.lerp(tip_col, f)
		offsets.append(f)
		base_colors.append(Color(c.r, c.g, c.b, lerpf(0.9, 0.05, f)))
	grad.offsets = offsets
	grad.colors = base_colors
	renderer.gradient = grad
	renderer.joint_mode = Line2D.LINE_JOINT_SHARP
	renderer.begin_cap_mode = Line2D.LINE_CAP_NONE
	renderer.end_cap_mode = Line2D.LINE_CAP_NONE

	rope.render_modules = [renderer]
	add_child(rope)

	var anchor := CRopeAnchor.new()
	anchor.index = 0
	anchor.node_path = rope.get_path_to(bell)
	anchor.offset_angle = rad_to_deg(attach.angle())
	anchor.offset_distance = attach.length()
	anchor.pull_strength = 0.0
	anchor.collision_resolve = false
	rope.anchors = [anchor]

	if _dev_tools:
		_dev_tools.register_debug_rope(rope)
	return {"anchor": anchor, "grad": grad, "base_colors": base_colors, "lit": false}

func _spawn_seagrass() -> void:
	for i in GRASS_COUNT:
		var base_x := 40.0 + 1840.0 * float(i) / maxf(float(GRASS_COUNT - 1), 1.0)
		var base := Vector2(base_x + _rng.randf_range(-19.0, 19.0), 1085.0)
		var length := lerpf(GRASS_MIN_LENGTH, GRASS_MAX_LENGTH, pow(_rng.randf(), GRASS_SHORT_BIAS))
		var seg_count := maxi(int(length / 22.0), 8)
		var data := CRopeData.new()
		data.create_line_by_count(base, base + Vector2(_rng.randf_range(-43.0, 43.0), -length), seg_count)
		var rope := CRope2D.new()
		rope.data = data
		rope.collision_width = 2.2 + length * 0.005 + _rng.randf_range(-0.5, 0.5)
		rope.collision_mask = 1
		rope.substeps = 3
		rope.damping = 0.85
		var lift := CRopeGravityForceMod.new()
		lift.gravity = Vector2(0, -_rng.randf_range(GRASS_LIFT_MIN, GRASS_LIFT_MAX))
		var current_r := CRopeWindForceMod.new()
		current_r.direction = Vector2(1, 0)
		current_r.strength = _rng.randf_range(GRASS_CURRENT_MIN, GRASS_CURRENT_MAX)
		current_r.variation = 0.9
		current_r.frequency = _rng.randf_range(0.15, 0.3)
		var current_l := CRopeWindForceMod.new()
		current_l.direction = Vector2(-1, 0)
		current_l.strength = _rng.randf_range(GRASS_CURRENT_MIN, GRASS_CURRENT_MAX)
		current_l.variation = 0.9
		current_l.frequency = _rng.randf_range(0.15, 0.3)
		rope.force_modules = [lift, current_r, current_l]
		rope.line_modules = [CRopeSmoothLineMod.new(), CRopeSimplifyLineMod.new()]
		var renderer := CRopeDirectRenderMod.new()
		renderer.width = rope.collision_width
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 1.0])
		var blade_hue := _rng.randf_range(GRASS_HUE_MIN, GRASS_HUE_MAX)
		if _rng.randf() < 0.15:
			blade_hue = _rng.randf_range(0.6, 0.72)
		var blade_sat := _rng.randf_range(0.25, 0.55)
		var root := Color.from_hsv(blade_hue, blade_sat, _rng.randf_range(0.16, 0.32))
		var tip := Color.from_hsv(blade_hue, blade_sat * _rng.randf_range(0.7, 1.0), _rng.randf_range(0.4, 0.72))
		grad.colors = PackedColorArray([
			Color(root.r, root.g, root.b, GRASS_ALPHA_ROOT),
			Color(tip.r, tip.g, tip.b, GRASS_ALPHA_TIP * _rng.randf_range(0.6, 1.9)),
		])
		renderer.gradient = grad

		rope.render_modules = [renderer]
		add_child(rope)
		var holder := Node2D.new()
		holder.position = base
		add_child(holder)
		var anchor := CRopeAnchor.new()
		anchor.index = 0
		anchor.node_path = rope.get_path_to(holder)
		anchor.pull_strength = 0.0
		anchor.collision_resolve = false
		rope.anchors = [anchor]
		if _dev_tools:
			_dev_tools.register_debug_rope(rope)

func _spawn_rays() -> void:
	for i in 7:
		var ray := Polygon2D.new()
		var top_w := _rng.randf_range(32.0, 108.0)
		var bot_w := top_w * _rng.randf_range(2.0, 2.8)
		var drop := _rng.randf_range(700.0, 1150.0)
		var slant := drop * 0.18 + _rng.randf_range(-40.0, 40.0)
		var base_x := 100.0 + 1700.0 * i / 6.0 + _rng.randf_range(-100.0, 100.0)
		ray.position = Vector2(base_x, -40.0)
		ray.polygon = PackedVector2Array([
			Vector2(-top_w * 0.5, 0), Vector2(0, 0), Vector2(top_w * 0.5, 0),
			Vector2(slant + bot_w * 0.5, drop), Vector2(slant, drop), Vector2(slant - bot_w * 0.5, drop),
		])
		var tint := Color(0.5, 0.85, 0.98)
		var peak := _rng.randf_range(0.04, 0.11)
		ray.vertex_colors = PackedColorArray([
			Color(tint.r, tint.g, tint.b, 0.0), Color(tint.r, tint.g, tint.b, peak), Color(tint.r, tint.g, tint.b, 0.0),
			Color(tint.r, tint.g, tint.b, 0.0), Color(tint.r, tint.g, tint.b, 0.0), Color(tint.r, tint.g, tint.b, 0.0),
		])
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		ray.material = mat
		add_child(ray)
		_rays.append({"node": ray, "phase": _rng.randf_range(0.0, TAU), "base_x": base_x})

func _spawn_vignette() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.0, 0.01, 0.05, 0.0),
		Color(0.0, 0.01, 0.05, 0.0),
		Color(0.0, 0.01, 0.05, 0.6),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1024
	texture.height = 1024
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	_vignette = Sprite2D.new()
	_vignette.texture = texture
	_vignette.position = Vector2(960, 540)
	_vignette.scale = Vector2(1.95, 1.1)
	add_child(_vignette)

func _dome_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		points.append(Vector2(cos(a), sin(a) * BELL_FLATTEN) * radius)
	points.append(Vector2(radius * 0.8, radius * 0.35 * BELL_FLATTEN))
	points.append(Vector2(0, radius * 0.2 * BELL_FLATTEN))
	points.append(Vector2(-radius * 0.8, radius * 0.35 * BELL_FLATTEN))
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
