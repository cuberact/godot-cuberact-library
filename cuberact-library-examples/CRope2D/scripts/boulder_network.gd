extends Node2D
## Spawns boulders with zero gravity and connects them with ropes,
## forming a dense interconnected network.

static var _last_boulder_count: int = 10
static var _last_rope_count: int = 10
static var _last_rope_gravity: bool = false

@export var boulder_count: int = _last_boulder_count
@export var rope_count: int = _last_rope_count
@export var rope_gravity: bool = _last_rope_gravity
@export var rope_width: float = 16.0
@export var min_boulder_distance: float = 280.0

var _boulder_scene: PackedScene
var _rope_shader: Shader
var _dev_tools: Node
var _last_hue: float = randf()
var _config_layer: CanvasLayer

const AREA_MIN := 250.0
const AREA_MAX := 1750.0

func _ready() -> void:
	_boulder_scene = load("res://cuberact-library-examples/commons/boulder.tscn")
	_rope_shader = load("res://cuberact-library-examples/commons/rope.gdshader")
	_dev_tools = get_node_or_null("DevTools")
	_show_config_panel()

func _show_config_panel() -> void:
	_config_layer = CanvasLayer.new()
	add_child(_config_layer)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.75)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_config_layer.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_config_layer.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Boulder count
	var boulder_value := _add_slider(vbox, "Boulders", boulder_count, 4, 20)

	# Total rope count
	var ropes_value := _add_slider(vbox, "Ropes", rope_count, 1, 30)

	# Gravity toggle — label left, button right
	var gravity_spacer_top := Control.new()
	gravity_spacer_top.custom_minimum_size.y = 10
	vbox.add_child(gravity_spacer_top)
	var gravity_row := HBoxContainer.new()
	gravity_row.add_theme_constant_override("separation", 20)
	vbox.add_child(gravity_row)
	var gravity_spacer_bottom := Control.new()
	gravity_spacer_bottom.custom_minimum_size.y = 10
	vbox.add_child(gravity_spacer_bottom)

	var gravity_label := Label.new()
	gravity_label.text = "Rope gravity"
	gravity_label.add_theme_font_size_override("font_size", 32)
	gravity_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	gravity_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gravity_row.add_child(gravity_label)

	var gravity_btn := Button.new()
	gravity_btn.add_theme_font_size_override("font_size", 32)
	gravity_btn.custom_minimum_size.x = 100
	var gravity_on_style := StyleBoxFlat.new()
	gravity_on_style.bg_color = Color(0.15, 0.45, 0.2, 0.8)
	gravity_on_style.content_margin_top = 8
	gravity_on_style.content_margin_bottom = 8
	gravity_on_style.content_margin_left = 24
	gravity_on_style.content_margin_right = 24
	var gravity_off_style := StyleBoxFlat.new()
	gravity_off_style.bg_color = Color(0.3, 0.3, 0.3, 0.6)
	gravity_off_style.content_margin_top = 8
	gravity_off_style.content_margin_bottom = 8
	gravity_off_style.content_margin_left = 24
	gravity_off_style.content_margin_right = 24
	var gravity_state := [rope_gravity]
	var update_gravity_btn := func():
		gravity_btn.text = "ON" if gravity_state[0] else "OFF"
		var s: StyleBoxFlat = gravity_on_style if gravity_state[0] else gravity_off_style
		gravity_btn.add_theme_stylebox_override("normal", s)
		gravity_btn.add_theme_stylebox_override("hover", s)
	update_gravity_btn.call()
	gravity_btn.pressed.connect(func():
		gravity_state[0] = not gravity_state[0]
		update_gravity_btn.call()
	)
	gravity_row.add_child(gravity_btn)

	vbox.add_child(HSeparator.new())

	# START button
	var start_btn := Button.new()
	start_btn.text = "START"
	start_btn.add_theme_font_size_override("font_size", 40)
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.2, 0.4, 0.7, 0.8)
	btn_style.content_margin_top = 12
	btn_style.content_margin_bottom = 12
	btn_style.content_margin_left = 60
	btn_style.content_margin_right = 60
	start_btn.add_theme_stylebox_override("normal", btn_style)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = Color(0.3, 0.5, 0.8, 0.9)
	btn_hover.content_margin_top = 12
	btn_hover.content_margin_bottom = 12
	btn_hover.content_margin_left = 60
	btn_hover.content_margin_right = 60
	start_btn.add_theme_stylebox_override("hover", btn_hover)
	vbox.add_child(start_btn)

	start_btn.pressed.connect(func():
		boulder_count = int(boulder_value.text)
		rope_count = int(ropes_value.text)
		rope_gravity = gravity_state[0]
		_last_boulder_count = boulder_count
		_last_rope_count = rope_count
		_last_rope_gravity = rope_gravity
		_config_layer.queue_free()
		_spawn_network()
	)

func _add_slider(parent: VBoxContainer, label_text: String, initial: int, min_val: int, max_val: int) -> Label:
	var label := Label.new()
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	parent.add_child(label)

	var value_label := Label.new()
	value_label.text = str(initial)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 56)
	value_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	parent.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 1
	slider.value = initial
	slider.custom_minimum_size.x = 500
	parent.add_child(slider)

	slider.value_changed.connect(func(val: float):
		value_label.text = str(int(val))
	)

	return value_label

func _spawn_network() -> void:
	var positions := _generate_boulder_positions()
	var boulders: Array[RigidBody2D] = []

	# Spawn boulders
	for i in positions.size():
		var boulder: RigidBody2D = _boulder_scene.instantiate()
		boulder.name = "Boulder_%d" % i
		boulder.position = positions[i]
		boulder.gravity_scale = 0.0
		boulder.boulder_seed = randi()
		add_child(boulder)
		boulders.append(boulder)

	# Build rope connections in rounds of random pairing
	var rope_idx := 0
	var remaining := rope_count
	while remaining > 0:
		var indices: Array[int] = []
		for i in boulders.size():
			indices.append(i)
		indices.shuffle()
		var pair_count := indices.size() / 2
		for p in pair_count:
			if remaining <= 0:
				break
			var a := indices[p * 2]
			var b := indices[p * 2 + 1]
			_create_connection(boulders[a], boulders[b], rope_idx)
			rope_idx += 1
			remaining -= 1

func _generate_boulder_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	var candidates_per_round := 30
	for i in boulder_count:
		var best_pos := Vector2(randf_range(AREA_MIN, AREA_MAX), randf_range(AREA_MIN, AREA_MAX))
		var best_min_dist := _min_dist_to_existing(best_pos, positions)
		for c in candidates_per_round:
			var pos := Vector2(randf_range(AREA_MIN, AREA_MAX), randf_range(AREA_MIN, AREA_MAX))
			var d := _min_dist_to_existing(pos, positions)
			if d > best_min_dist:
				best_min_dist = d
				best_pos = pos
		positions.append(best_pos)
	return positions

func _min_dist_to_existing(pos: Vector2, positions: Array[Vector2]) -> float:
	if positions.is_empty():
		return INF
	var min_d := INF
	for p in positions:
		min_d = minf(min_d, pos.distance_to(p))
	return min_d

func _create_connection(boulder_a: RigidBody2D, boulder_b: RigidBody2D, idx: int) -> void:
	var boulder_radius := 80.0
	var start := boulder_a.position
	var end := boulder_b.position
	var dir := (end - start).normalized()
	var spread := randf_range(-30.0, 30.0)
	var spread_rad := deg_to_rad(spread)
	var offset_dir_a := Vector2(dir.x * cos(spread_rad) - dir.y * sin(spread_rad), dir.x * sin(spread_rad) + dir.y * cos(spread_rad))
	var offset_dir_b := Vector2(-dir.x * cos(spread_rad) + dir.y * sin(spread_rad), -dir.x * sin(spread_rad) - dir.y * cos(spread_rad))
	var surface_start := start + offset_dir_a * boulder_radius
	var surface_end := end + offset_dir_b * boulder_radius
	var dist := surface_start.distance_to(surface_end)
	var seg_count := maxi(int(dist / rope_width), 4)

	# Rope data
	var rope_data := CRopeData.new()
	rope_data.create_line_by_count(surface_start, surface_end, seg_count)

	# Rope node
	var rope := CRope2D.new()
	rope.name = "Rope_%d" % idx
	rope.data = rope_data
	rope.substeps = 6
	rope.collision_width = rope_width

	# Force modules
	if rope_gravity:
		var gravity := CRopeGravityForceMod.new()
		gravity.gravity = Vector2(0.0, 980.0)
		rope.force_modules = [gravity]

	# Line modules
	rope.line_modules = [CRopeSmoothLineMod.new(), CRopeSimplifyLineMod.new()]

	# Render modules
	var renderer := CRopeDirectRenderMod.new()
	renderer.width = rope_width
	var debug_renderer := CRopeDebugRenderMod.new()
	debug_renderer.set_all_draws(false)
	debug_renderer.draw_anchors = true
	debug_renderer.anchor_radius = 10.0
	debug_renderer.anchor_color = Color.BLACK
	rope.render_modules = [renderer, debug_renderer]

	# Material
	var mat := ShaderMaterial.new()
	mat.shader = _rope_shader
	var base_color := _generate_random_pastel()
	mat.set_shader_parameter("rope_color1", base_color.darkened(0.3))
	mat.set_shader_parameter("rope_color2", base_color)
	rope.material = mat

	add_child(rope)

	# Anchors — match the spread-adjusted surface points
	var anchor_a := CRopeAnchor.new()
	anchor_a.index = 0
	anchor_a.node_path = rope.get_path_to(boulder_a)
	anchor_a.offset_angle = rad_to_deg(atan2(offset_dir_a.y, offset_dir_a.x))
	anchor_a.offset_distance = boulder_radius
	anchor_a.collision_resolve = false
	anchor_a.enabled = true

	var anchor_b := CRopeAnchor.new()
	anchor_b.index = seg_count
	anchor_b.node_path = rope.get_path_to(boulder_b)
	anchor_b.offset_angle = rad_to_deg(atan2(offset_dir_b.y, offset_dir_b.x))
	anchor_b.offset_distance = boulder_radius
	anchor_b.collision_resolve = false
	anchor_b.enabled = true

	rope.anchors = [anchor_a, anchor_b]
	rope.depenetrate_all_anchor_offsets()

	if _dev_tools:
		_dev_tools.register_debug_rope(rope)

func _generate_random_pastel() -> Color:
	_last_hue = fmod(_last_hue + 0.618033988749895, 1.0)
	var saturation := randf_range(0.4, 0.6)
	var value := randf_range(0.85, 0.95)
	return Color.from_hsv(_last_hue, saturation, value)
