extends Node2D
## Stress test. Spawns N ropes hanging from the ceiling with varying lengths and
## pastel colors. A config panel on start lets you set the rope count before spawning.

static var _last_rope_count: int = 100

@export var rope_count: int = _last_rope_count
@export var rope_width: float = 20.0
@export var rope_min_length: float = 750.0
@export var rope_max_length: float = 950.0

var _rope_shader: Shader
var _walls: Node2D
var _dev_tools: Node
var _last_hue: float = randf()
var _config_layer: CanvasLayer

func _ready() -> void:
	_rope_shader = load("res://cuberact-library-examples/commons/rope.gdshader")
	_walls = $Walls
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
	vbox.add_theme_constant_override("separation", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	var title := Label.new()
	title.text = name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var count_label := Label.new()
	count_label.text = "Ropes"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 32)
	count_label.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	vbox.add_child(count_label)

	var value_label := Label.new()
	value_label.text = str(rope_count)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 64)
	value_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	vbox.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = 1
	slider.max_value = 200
	slider.step = 1
	slider.value = rope_count
	slider.custom_minimum_size.x = 500
	vbox.add_child(slider)

	slider.value_changed.connect(func(val: float):
		value_label.text = str(int(val))
	)

	vbox.add_child(HSeparator.new())

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
		rope_count = int(slider.value)
		_last_rope_count = rope_count
		_config_layer.queue_free()
		_spawn_ropes()
	)

func _spawn_ropes() -> void:
	var center_x := 960.0
	var margin := 100.0
	var max_span := 1920.0 - 2.0 * margin
	var rope_spacing := max_span / 100.0
	for i in rope_count:
		var x: float
		if rope_count == 1:
			x = center_x
		else:
			var span := minf((rope_count - 1) * rope_spacing, max_span)
			var t: float = float(i) / (rope_count - 1)
			x = center_x - span / 2.0 + t * span
		var length := lerpf(rope_min_length, rope_max_length, randf())
		var seg_count := int(length / rope_width)
		var start := Vector2(x, 4.0)
		var rope := _create_rope(start, seg_count)
		rope.name = "Rope_%d" % i
		add_child(rope)
		# Anchor the rope top to the Walls node at (x, 0)
		var anchor := CRopeAnchor.new()
		anchor.index = 0
		anchor.node_path = rope.get_path_to(_walls)
		anchor.offset_angle = rad_to_deg(atan2(start.y, start.x))
		anchor.offset_distance = start.length()
		anchor.collision_resolve = false
		rope.anchors = [anchor]
		if _dev_tools:
			_dev_tools.register_debug_rope(rope)

func _create_rope(start: Vector2, seg_count: int) -> CRope2D:
	var data := CRopeData.new()
	var end := start + Vector2(0.0, seg_count * rope_width)
	data.create_line_by_count(start, end, seg_count)
	# Pre-shrink segments so gravity stretch settles near the target length
	data.segment_length *= 0.99
	var rope := CRope2D.new()
	rope.data = data
	rope.collision_width = rope_width
	rope.force_modules = [CRopeWorldGravityForceMod.new()]
	rope.line_modules = [CRopeSmoothLineMod.new(), CRopeSimplifyLineMod.new()]
	var renderer := CRopeDirectRenderMod.new()
	renderer.width = rope_width
	renderer.joint_mode = Line2D.LINE_JOINT_SHARP
	renderer.begin_cap_mode = Line2D.LINE_CAP_NONE
	renderer.end_cap_mode = Line2D.LINE_CAP_NONE
	var debug_renderer := CRopeDebugRenderMod.new()
	debug_renderer.set_all_draws(false)
	debug_renderer.draw_overlay = true
	debug_renderer.wake_color = Color.from_rgba8(0, 0, 0, 0)
	rope.render_modules = [renderer, debug_renderer]
	var mat := ShaderMaterial.new()
	mat.shader = _rope_shader
	var base_color := _generate_random_pastel()
	var darker_color := base_color.darkened(0.3)
	mat.set_shader_parameter("rope_color1", darker_color)
	mat.set_shader_parameter("rope_color2", base_color)
	rope.material = mat
	return rope

func _generate_random_pastel() -> Color:
	_last_hue = fmod(_last_hue + 0.618033988749895, 1.0)
	var saturation := randf_range(0.4, 0.6)
	var value := randf_range(0.85, 0.95)
	return Color.from_hsv(_last_hue, saturation, value)
