extends Node2D

# Probe field metadata: [display_label, property_name]
# Unit is derived automatically: fields ending in "_time" show "µs", others are plain counts.
const _PROBE_META := [
	["simulate", "simulate_time"],
	["anchor cache", "anchor_cache_time"],
	["force modules", "force_modules_time"],
	["prepare collisions", "prepare_collisions_time"],
	["substeps", "substeps_time"],
	["anchor pull", "anchor_pull_time"],
	["rope sections", "rope_sections_time"],
	["resolve collisions", "resolve_collisions_time"],
	["break modules", "break_modules_time"],
	["line modules", "line_modules_time"],
	["render modules", "render_modules_time"],
	["draw", "draw_time"],
	["render points", "render_points_count"],
	["collision points", "collision_points_count"],
	["collision queries", "collision_queries_count"],
	["collisions", "collision_count"],
]

@export_group("Camera")
@export var init_pos: Vector2 = Vector2(960.0, 540.0)
@export var init_zoom: float = 1.0
@export_range(0.1, 0.9, 0.01) var min_zoom: float = 0.2
@export_range(1, 100, 0.1) var max_zoom: float = 100.0
@export_range(1.01, 2, 0.01) var zoom_speed: float = 1.04

@export_group("Drag nodes")
@export var nodes_mouse_left: Array[Node2D]
@export var nodes_mouse_right: Array[Node2D]
@export var nodes_draw_circles: bool = true
@export var drag_strength: float = 200.0

@export_group("CRope2D")
@export var debug_ropes: Array[CRope2D]
@export_range(1, 1000, 1) var probe_sample_count: int = 60:
	set(value):
		probe_sample_count = value
		for probe in debug_probes:
			probe.sample_count = value
		physics_frame_counter = 0
@export var print_probe: bool = false

# Dragging state - RigidBody2D
var drag_body: RigidBody2D = null
var drag_body_by_left: bool = false
var drag_body_point: Vector2 = Vector2.INF

# Dragging state - StaticBody2D
var drag_static: StaticBody2D = null
var drag_static_by_left: bool = false
var drag_static_point: Vector2 = Vector2.INF

var dragging_nodes_mouse_left: bool = false
var dragging_nodes_mouse_right: bool = false
var dragging_nodes_point: Vector2 = Vector2.ZERO

# Camera state
var is_panning: bool = false

# Physics
var physics_space: PhysicsDirectSpaceState2D

# UI references
@onready var debug_container: VBoxContainer = $CanvasLayer/VBoxContainer
var _lbl_fps_value: Label
var _lbl_vsync_value: Label
var _debug_probe_container: VBoxContainer
var _debug_probe_title: Label
var _debug_probe_values: Array = []
@onready var hint_label: Label = $CanvasLayer/HintLabel
@onready var controls_overlay: ColorRect = $CanvasLayer/ControlsOverlay
@onready var controls_grid: GridContainer = $CanvasLayer/ControlsOverlay/CenterContainer/ControlsGrid

# FPS tracking
var fps_update_timer: float = 0.0
var _cached_zoom: float = -1.0
var _scale_bar: Control
var _debug_panel: PanelContainer
var _probe_panel: PanelContainer
var _hint_panel: PanelContainer
var _debug_ui_visible: bool = false
var _controls_visible: bool = false
static var _hint_enabled: bool = true
var _extra_controls: Array = []
static var _controls_printed: bool = false

var debug_probes: Array[CRopeDebugProbe]
var physics_frame_counter: int = 0

func _ready() -> void:
	if OS.get_name() == "Web":
		%SimpleShadows.visible = false
	window_setup()
	_reset_camera()
	_setup_hint()
	_setup_debug_panel()
	_create_scale_bar()
	_create_info_grid()
	_create_debug_probe_panel()
	_update_vsync_display()
	_print_controls()
	_setup_controls_overlay()

func _process(delta: float) -> void:
	_update_fps_display(delta)
	_update_scale_bar()
	_update_debug_probe_display()

func _physics_process(_delta: float) -> void:
	physics_frame_counter = physics_frame_counter + 1
	if not physics_space:
		physics_space = get_world_2d().direct_space_state
	_update_dragging()
	queue_redraw()

func _draw() -> void:
	var mouse := get_global_mouse_position()
	var circle_radius := _screen_to_world_scale(10.0)
	var line_width := _screen_to_world_scale(2.0)
	if drag_body and drag_body_point.is_finite():
		var grab_point_global := drag_body.to_global(drag_body_point)
		draw_circle(grab_point_global, circle_radius, Color.AQUA)
		draw_line(grab_point_global, mouse, Color.AQUA, line_width)
	if drag_static and drag_static_point.is_finite():
		var grab_point_global := drag_static.to_global(drag_static_point)
		draw_circle(grab_point_global, circle_radius, Color.AQUA)
	if nodes_draw_circles:
		for node in nodes_mouse_left:
			if node:
				draw_circle(node.global_position, circle_radius, Color.AQUA if dragging_nodes_mouse_left else Color.BLACK)
		for node in nodes_mouse_right:
			if node:
				draw_circle(node.global_position, circle_radius, Color.AQUA if dragging_nodes_mouse_right else Color.BLACK)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventKey:
		_handle_keyboard(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT:
		_handle_left_click(event)
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_right_click(event)
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_handle_middle_click(event)
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		if event.pressed:
			_zoom_camera(zoom_speed)
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if event.pressed:
			_zoom_camera(1.0 / zoom_speed)

func _handle_left_click(event: InputEventMouseButton) -> void:
	if event.pressed:
		# Hidden: click on probe title prints debug state to console
		if _probe_panel.visible and _debug_probe_title.get_global_rect().has_point(event.position):
			print(_build_probe_text())
		# Hidden: click on VSync value toggles VSync
		if OS.get_name() != "Web" and debug_container.visible and _lbl_vsync_value.get_global_rect().has_point(event.position):
			_toggle_vsync()
		if not drag_body and not drag_static:
			var body := _try_pickup_body()
			if body is RigidBody2D:
				drag_body_by_left = true
				_start_dragging(body)
			elif body is StaticBody2D:
				drag_static_by_left = true
				_start_dragging_static(body)
			elif not nodes_mouse_left.is_empty():
				dragging_nodes_point = event.global_position
				dragging_nodes_mouse_left = true
	else:
		if drag_body and drag_body_by_left:
			_stop_dragging()
		if drag_static and drag_static_by_left:
			_stop_dragging_static()
		dragging_nodes_mouse_left = false

func _handle_right_click(event: InputEventMouseButton) -> void:
	if event.pressed:
		if not drag_body and not drag_static:
			var body := _try_pickup_body()
			if body is RigidBody2D:
				drag_body_by_left = false
				_start_dragging(body)
			elif body is StaticBody2D:
				drag_static_by_left = false
				_start_dragging_static(body)
			elif not nodes_mouse_right.is_empty():
				dragging_nodes_point = event.global_position
				dragging_nodes_mouse_right = true
	else:
		if drag_body and not drag_body_by_left:
			_stop_dragging()
		if drag_static and not drag_static_by_left:
			_stop_dragging_static()
		dragging_nodes_mouse_right = false

func _handle_middle_click(event: InputEventMouseButton) -> void:
	if event.pressed:
		var body := _try_pickup_body()
		if body is RigidBody2D and body.has_method("toggle_gravity"):
			body.toggle_gravity()
			return
	is_panning = event.pressed

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_panning:
		var camera := _get_camera()
		if camera:
			camera.global_position -= event.relative / camera.zoom
	if drag_static:
		var mouse_global := get_global_mouse_position()
		var grab_point_global := drag_static.to_global(drag_static_point)
		drag_static.global_position += mouse_global - grab_point_global
	var delta = event.global_position - dragging_nodes_point
	dragging_nodes_point = event.global_position
	if dragging_nodes_mouse_left:
		for node in nodes_mouse_left:
			if node:
				node.global_position += delta
	if dragging_nodes_mouse_right:
		for node in nodes_mouse_right:
			if node:
				node.global_position += delta

func _handle_keyboard(event: InputEventKey) -> void:
	if event.pressed and event.keycode == KEY_F1:
		_controls_visible = not _controls_visible
		controls_overlay.visible = _controls_visible
		_hint_panel.visible = _hint_enabled and not _controls_visible
	elif event.pressed and event.keycode == KEY_F2:
		debug_container.visible = not debug_container.visible
		_debug_ui_visible = not _debug_ui_visible
		debug_probes.clear()
		for rope in debug_ropes:
			if not is_instance_valid(rope):
				continue
			if _debug_ui_visible:
				var probe = rope.enable_debug_probe()
				probe.sample_count = probe_sample_count
				debug_probes.append(probe)
			else:
				rope.disable_debug_probe()
		if _debug_ui_visible:
			physics_frame_counter = 0
	elif event.pressed and event.keycode == KEY_F12:
		_hint_enabled = not _hint_enabled
		_hint_panel.visible = _hint_enabled and not _controls_visible
	elif event.pressed and event.keycode == KEY_F10:
		_save_screenshot()
	elif event.pressed and event.keycode == KEY_V:
		if OS.get_name() != "Web":
			_toggle_vsync()
	elif event.pressed and event.keycode == KEY_ESCAPE:
		if _controls_visible:
			_controls_visible = false
			controls_overlay.visible = false
			_hint_panel.visible = _hint_enabled
		else:
			get_tree().change_scene_to_file("res://cuberact-library-examples/examples-launcher.tscn")
	elif event.keycode == KEY_R:
		_reset_camera()

## Registers a rope for debug tracking. If debug UI is visible, immediately enables its probe.
func register_debug_rope(rope: CRope2D) -> void:
	if not rope or debug_ropes.has(rope):
		return
	debug_ropes.append(rope)
	if _debug_ui_visible:
		var probe = rope.enable_debug_probe()
		probe.sample_count = probe_sample_count
		debug_probes.append(probe)
		physics_frame_counter = 0

## Unregisters a rope from debug tracking. If debug UI is visible, disables its probe.
func unregister_debug_rope(rope: CRope2D) -> void:
	var idx := debug_ropes.find(rope)
	if idx < 0:
		return
	if _debug_ui_visible and idx < debug_probes.size():
		if is_instance_valid(rope):
			rope.disable_debug_probe()
		debug_probes.remove_at(idx)
		physics_frame_counter = 0
	debug_ropes.remove_at(idx)

func _print_controls() -> void:
	if _controls_printed:
		return
	_controls_printed = true
	var lines: PackedStringArray = []
	lines.append("cuberact-library v" + CuberactLib.get_version())
	lines.append("")
	for entry in _get_controls_entries():
		lines.append("  %-12s %s" % [entry[0], entry[1]])
	print("\n".join(lines))

## Adds scene-specific control entries to the overlay. Each entry is [key, description].
func add_controls_entries(entries: Array) -> void:
	_extra_controls.append_array(entries)
	_rebuild_controls_overlay()

func _setup_controls_overlay() -> void:
	_rebuild_controls_overlay()

func _rebuild_controls_overlay() -> void:
	for child in controls_grid.get_children():
		child.queue_free()
	# Scene-specific controls first (visually distinct color to stand out)
	if not _extra_controls.is_empty():
		var scene_color := Color(1.0, 0.85, 0.5)
		for entry in _extra_controls:
			_add_control_row(entry[0], entry[1], scene_color)
		_add_spacer_row()
	# General controls
	var general_color := Color(0.7, 0.8, 1.0)
	for entry in _get_general_entries():
		_add_control_row(entry[0], entry[1], general_color)
	# System controls
	_add_spacer_row()
	var system_color := Color(0.6, 0.6, 0.65)
	_add_control_row("F1", "show/hide controls", system_color)
	_add_control_row("F2", "show/hide FPS and debug", system_color)
	_add_control_row("F10", "save screenshot", system_color)
	_add_control_row("F12", "show/hide hint", system_color)
	_add_control_row("ESC", "back to launcher", system_color)

## Adds a single key-description row to the controls grid.
func _add_control_row(key: String, description: String, key_color: Color) -> void:
	var key_label := Label.new()
	key_label.text = key
	key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	key_label.add_theme_font_size_override("font_size", 28)
	key_label.add_theme_color_override("font_color", key_color)
	key_label.add_theme_color_override("font_outline_color", Color.BLACK)
	key_label.add_theme_constant_override("outline_size", 5)
	controls_grid.add_child(key_label)
	var desc_label := Label.new()
	desc_label.text = description
	desc_label.add_theme_font_size_override("font_size", 28)
	desc_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	desc_label.add_theme_color_override("font_outline_color", Color.BLACK)
	desc_label.add_theme_constant_override("outline_size", 5)
	controls_grid.add_child(desc_label)

## Adds an empty spacer row to create visual gap between control groups.
func _add_spacer_row() -> void:
	var spacer1 := Control.new()
	spacer1.custom_minimum_size.y = 16
	controls_grid.add_child(spacer1)
	var spacer2 := Control.new()
	spacer2.custom_minimum_size.y = 16
	controls_grid.add_child(spacer2)

## Returns general control entries (mouse, camera, etc.).
func _get_general_entries() -> Array:
	var entries: Array = []
	if not nodes_mouse_left.is_empty():
		entries.append(["Left mouse", "drag anchors / drag bodies"])
	else:
		entries.append(["Left mouse", "drag bodies"])
	if not nodes_mouse_right.is_empty():
		entries.append(["Right mouse", "drag anchors / drag bodies"])
	else:
		entries.append(["Right mouse", "drag bodies"])
	entries.append(["Middle mouse", "camera pan / toggle boulder gravity"])
	entries.append(["Mouse wheel", "camera zoom"])
	entries.append(["R", "camera reset"])
	if OS.get_name() != "Web":
		entries.append(["V", "toggle VSync"])
	return entries

## Returns all control entries as a flat list (for console printing).
func _get_controls_entries() -> Array:
	var entries := _get_general_entries()
	entries.append_array(_extra_controls)
	entries.append(["F1", "show/hide controls"])
	entries.append(["F2", "show/hide FPS and debug"])
	entries.append(["F10", "save screenshot"])
	entries.append(["F12", "show/hide hint"])
	entries.append(["ESC", "back to launcher"])
	return entries

func _get_camera() -> Camera2D:
	return get_viewport().get_camera_2d()

func _zoom_camera(factor: float) -> void:
	var camera := _get_camera()
	if not camera:
		return
	camera.zoom *= factor
	camera.zoom = camera.zoom.clamp(
		Vector2(min_zoom, min_zoom),
		Vector2(max_zoom, max_zoom)
	)

func _try_pickup_body() -> PhysicsBody2D:
	if not physics_space:
		return null
	var query := PhysicsPointQueryParameters2D.new()
	query.position = get_global_mouse_position()
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var results := physics_space.intersect_point(query, 1)
	for result in results:
		var collider = result["collider"]
		if (collider is RigidBody2D or collider is StaticBody2D) and not collider.is_in_group("no_drag"):
			return collider
	return null

func _start_dragging(body: RigidBody2D) -> void:
	drag_body = body
	drag_body_point = drag_body.to_local(get_global_mouse_position())

func _update_dragging() -> void:
	if not drag_body:
		return
	var drag_body_point_global := drag_body.to_global(drag_body_point)
	var mouse_global := get_global_mouse_position()
	var direction := mouse_global - drag_body_point_global
	var force := direction * drag_strength
	drag_body.linear_velocity = Vector2.ZERO
	drag_body.angular_velocity = 0.0
	drag_body.apply_force(force, drag_body_point_global- drag_body.global_transform.origin)

func _stop_dragging() -> void:
	if not drag_body:
		return
	drag_body = null
	drag_body_point = Vector2.INF

func _start_dragging_static(body: StaticBody2D) -> void:
	drag_static = body
	drag_static_point = drag_static.to_local(get_global_mouse_position())

func _stop_dragging_static() -> void:
	if not drag_static:
		return
	drag_static = null
	drag_static_point = Vector2.INF

## Creates a semi-transparent background style for debug panels.
func _create_bg_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.5)
	style.set_content_margin_all(12)
	return style

## Wraps the F1 hint label in a yellow panel for better visibility.
func _setup_hint() -> void:
	_hint_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.85, 0.0)
	style.set_content_margin_all(2)
	_hint_panel.add_theme_stylebox_override("panel", style)
	$CanvasLayer.add_child(_hint_panel)
	# Anchor to bottom-right
	_hint_panel.anchor_left = 1.0
	_hint_panel.anchor_top = 1.0
	_hint_panel.anchor_right = 1.0
	_hint_panel.anchor_bottom = 1.0
	_hint_panel.offset_right = 0
	_hint_panel.offset_bottom = 0
	_hint_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_hint_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Reparent hint label into panel
	hint_label.get_parent().remove_child(hint_label)
	_hint_panel.add_child(hint_label)
	hint_label.text = "press F1"
	hint_label.add_theme_color_override("font_color", Color.BLACK)
	hint_label.add_theme_color_override("font_outline_color", Color.TRANSPARENT)
	hint_label.add_theme_constant_override("outline_size", 0)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Keep behind controls overlay
	$CanvasLayer.move_child(_hint_panel, controls_overlay.get_index())
	# Apply the global F12 toggle (persists across examples until app restart)
	_hint_panel.visible = _hint_enabled

## Creates a PanelContainer with background for the FPS/VSync info grid.
func _setup_debug_panel() -> void:
	debug_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel = PanelContainer.new()
	_debug_panel.add_theme_stylebox_override("panel", _create_bg_style())
	_debug_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	debug_container.add_child(_debug_panel)

func _create_info_grid() -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	_debug_panel.add_child(grid)
	var key_color := Color(0.6, 0.6, 0.65)
	var val_color := Color(0.98, 0.98, 0.98)
	var fs := 28
	# FPS row
	var fps_key := _create_info_label("FPS", key_color, fs, HORIZONTAL_ALIGNMENT_RIGHT)
	grid.add_child(fps_key)
	_lbl_fps_value = _create_info_label("--", val_color, fs)
	grid.add_child(_lbl_fps_value)
	# VSync row (not shown on web)
	if OS.get_name() != "Web":
		var vsync_key := _create_info_label("VSync", key_color, fs, HORIZONTAL_ALIGNMENT_RIGHT)
		grid.add_child(vsync_key)
		# VSync click-to-toggle detected in _handle_left_click via position check
		_lbl_vsync_value = _create_info_label("--", val_color, fs)
		grid.add_child(_lbl_vsync_value)


func _create_debug_probe_panel() -> void:
	# Wrapper panel with semi-transparent background
	_probe_panel = PanelContainer.new()
	_probe_panel.add_theme_stylebox_override("panel", _create_bg_style())
	_probe_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_probe_panel.visible = false
	$CanvasLayer.add_child(_probe_panel)
	$CanvasLayer.move_child(_probe_panel, controls_overlay.get_index())
	# Anchor to bottom-left, grow upward
	_probe_panel.anchor_left = 0
	_probe_panel.anchor_top = 1
	_probe_panel.anchor_right = 0
	_probe_panel.anchor_bottom = 1
	_probe_panel.offset_left = 0
	_probe_panel.offset_bottom = 0
	_probe_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_probe_panel.grow_horizontal = Control.GROW_DIRECTION_END
	# Content container
	_debug_probe_container = VBoxContainer.new()
	_debug_probe_container.add_theme_constant_override("separation", 8)
	_probe_panel.add_child(_debug_probe_container)
	var key_color := Color(0.6, 0.6, 0.65)
	var val_color := Color(0.98, 0.98, 0.98)
	var fs := 28
	# Title row (click-to-print detected in _handle_left_click via position check)
	_debug_probe_title = _create_info_label("", val_color, fs)
	_debug_probe_container.add_child(_debug_probe_title)
	# Grid with key-value pairs
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	_debug_probe_container.add_child(grid)
	for i in _PROBE_META.size():
		var meta = _PROBE_META[i]
		# First entry ("simulate") is the total, use bright color to distinguish from sub-items
		var kc: Color = val_color if i == 0 else key_color
		var k := _create_info_label(meta[0], kc, fs, HORIZONTAL_ALIGNMENT_RIGHT)
		grid.add_child(k)
		var v := _create_info_label("--", val_color, fs)
		grid.add_child(v)
		_debug_probe_values.append(v)

## Creates a styled label for the info grid.
func _create_info_label(text: String, color: Color, font_size: int, alignment: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = alignment
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 5)
	return lbl

func _update_fps_display(delta: float) -> void:
	fps_update_timer += delta
	if fps_update_timer >= 1.0:
		fps_update_timer = 0.0
		_lbl_fps_value.text = "%d" % Engine.get_frames_per_second()

func _create_scale_bar() -> void:
	_scale_bar = Control.new()
	_scale_bar.custom_minimum_size = Vector2(0, 50)
	_scale_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scale_bar.size_flags_horizontal = Control.SIZE_FILL
	_scale_bar.draw.connect(_draw_scale_bar)
	debug_container.add_child(_scale_bar)
	debug_container.move_child(_scale_bar, 0)

func _update_scale_bar() -> void:
	var camera := _get_camera()
	if not camera:
		return
	var current_zoom := camera.zoom.x
	if current_zoom != _cached_zoom:
		_cached_zoom = current_zoom
		if _scale_bar:
			_scale_bar.queue_redraw()

func _draw_scale_bar() -> void:
	var camera := _get_camera()
	if not camera:
		return
	var zoom := camera.zoom.x
	# 100 Godot units = 1 meter
	var meters_per_pixel := 0.01 / zoom
	# Find a nice round distance for ~150px bar width
	var target_width := 150.0
	var raw_meters := target_width * meters_per_pixel
	var nice_meters := _round_to_nice_number(raw_meters)
	var bar_width := nice_meters / meters_per_pixel
	# Format label
	var label_text: String
	if nice_meters >= 1.0:
		if nice_meters == floorf(nice_meters):
			label_text = "%d m" % int(nice_meters)
		else:
			label_text = "%.1f m" % nice_meters
	else:
		label_text = "%d cm" % int(nice_meters * 100)
	# Layout (right-aligned within the control)
	var right_x := _scale_bar.size.x
	var left_x := right_x - bar_width
	var bar_y := 38.0
	var tick_h := 6.0
	var fg := Color(0.98, 0.98, 0.98)
	var bg := Color.BLACK
	var lw := 2.0
	# Black outline behind lines
	_scale_bar.draw_line(Vector2(left_x, bar_y), Vector2(right_x, bar_y), bg, lw + 4)
	_scale_bar.draw_line(Vector2(left_x, bar_y - tick_h), Vector2(left_x, bar_y + tick_h), bg, lw + 4)
	_scale_bar.draw_line(Vector2(right_x, bar_y - tick_h), Vector2(right_x, bar_y + tick_h), bg, lw + 4)
	# Foreground lines
	_scale_bar.draw_line(Vector2(left_x, bar_y), Vector2(right_x, bar_y), fg, lw)
	_scale_bar.draw_line(Vector2(left_x, bar_y - tick_h), Vector2(left_x, bar_y + tick_h), fg, lw)
	_scale_bar.draw_line(Vector2(right_x, bar_y - tick_h), Vector2(right_x, bar_y + tick_h), fg, lw)
	# Text centered above bar
	var font := _scale_bar.get_theme_default_font()
	var font_size := 24
	var text_width := font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_x := left_x + (bar_width - text_width) / 2.0
	var text_y := bar_y - tick_h - 8.0
	_scale_bar.draw_string_outline(font, Vector2(text_x, text_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 5, bg)
	_scale_bar.draw_string(font, Vector2(text_x, text_y), label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, fg)

## Rounds a value to the nearest "nice" number (1, 2, 5 × 10^n).
func _round_to_nice_number(value: float) -> float:
	var exponent := floorf(log(value) / log(10.0))
	var fraction := value / pow(10.0, exponent)
	var nice: float
	if fraction < 1.5:
		nice = 1.0
	elif fraction < 3.5:
		nice = 2.0
	elif fraction < 7.5:
		nice = 5.0
	else:
		nice = 10.0
	return nice * pow(10.0, exponent)

func _screen_to_world_scale(screen_pixels: float) -> float:
	return screen_pixels / get_viewport().get_canvas_transform().get_scale().x

func _toggle_vsync() -> void:
	var current_mode := DisplayServer.window_get_vsync_mode()
	if current_mode == DisplayServer.VSYNC_DISABLED:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_update_vsync_display()

func _update_vsync_display() -> void:
	if not _lbl_vsync_value:
		return
	var mode := DisplayServer.window_get_vsync_mode()
	_lbl_vsync_value.text = "ON" if mode != DisplayServer.VSYNC_DISABLED else "OFF"

func _reset_camera() -> void:
	var camera := _get_camera()
	if not camera:
		return
	camera.global_position = init_pos
	camera.zoom = Vector2(init_zoom, init_zoom)

## Saves a PNG of the current frame into the screenshot folder, named after the running scene.
## A numeric suffix is appended when a file with that name already exists.
func _save_screenshot() -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := "res://cuberact-library-examples/CRope2D/screenshot"
	var base: String = get_tree().current_scene.scene_file_path.get_file().get_basename()
	var path := "%s/%s.png" % [dir, base]
	var n := 1
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.png" % [dir, base, n]
		n += 1
	image.save_png(path)
	print("Screenshot saved: ", ProjectSettings.globalize_path(path))

func _update_debug_probe_display() -> void:
	if debug_probes.is_empty():
		_probe_panel.visible = false
		return
	_probe_panel.visible = true
	if physics_frame_counter >= probe_sample_count:
		physics_frame_counter = 0
		if debug_probes.size() == 1:
			var rope := debug_ropes[0]
			var probe := debug_probes[0]
			var pts := rope.data.get_count() if is_instance_valid(rope) and rope.data else 0
			_debug_probe_title.text = "CRope2D %d points" % pts
			_update_probe_values_single(probe)
		else:
			var total_points := 0
			for rope in debug_ropes:
				if is_instance_valid(rope) and rope.data:
					total_points += rope.data.get_count()
			_debug_probe_title.text = "Sum of %d ropes, %d points" % [debug_probes.size(), total_points]
			_update_probe_values_sum()
		if print_probe:
			print(_build_probe_text())

func _update_probe_values_single(probe: CRopeDebugProbe) -> void:
	for i in _PROBE_META.size():
		var field: String = _PROBE_META[i][1]
		var val: int = probe.get(field)
		_debug_probe_values[i].text = "%d µs" % val if field.ends_with("_time") else "%d" % val

func _update_probe_values_sum() -> void:
	for i in _PROBE_META.size():
		var field: String = _PROBE_META[i][1]
		var total := 0
		for probe in debug_probes:
			total += probe.get(field)
		_debug_probe_values[i].text = "%d µs" % total if field.ends_with("_time") else "%d" % total

## Builds flat text for console printing.
func _build_probe_text() -> String:
	var lines := PackedStringArray()
	lines.append(_debug_probe_title.text)
	for i in _PROBE_META.size():
		lines.append("  %s: %s" % [_PROBE_META[i][0], _debug_probe_values[i].text])
	return "\n".join(lines)

static var _window_initialized: bool = false
const DESIGN_WIDTH := 1920
const DESIGN_HEIGHT := 1080
const WINDOW_MARGIN := 0.95

static func window_setup() -> void:
	if _window_initialized:
		return
	_window_initialized = true
	var usable := DisplayServer.screen_get_usable_rect()
	var max_w := usable.size.x * WINDOW_MARGIN
	var max_h := usable.size.y * WINDOW_MARGIN
	# Largest 16:9 box that fits the usable screen, capped at the design size.
	var scale := minf(minf(DESIGN_WIDTH, max_w) / DESIGN_WIDTH, minf(DESIGN_HEIGHT, max_h) / DESIGN_HEIGHT)
	var w := int(DESIGN_WIDTH * scale)
	var h := int(DESIGN_HEIGHT * scale)
	DisplayServer.window_set_size(Vector2i(w, h))
	@warning_ignore("integer_division")
	var pos: Vector2i = usable.position + (usable.size - Vector2i(w, h)) / 2
	DisplayServer.window_set_position(pos)
