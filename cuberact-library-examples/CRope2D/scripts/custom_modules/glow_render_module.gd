## Glow render module - creates a glowing effect around the rope
## Draws multiple layers with decreasing opacity for glow effect
class_name GlowRenderModule extends CRopeRenderMod

## Core glow color
@export var glow_color: Color = Color(0.5, 0.8, 1.0, 1.0)
## Number of glow layers (more = smoother but slower)
@export_range(2, 10, 1) var glow_layers: int = 4
## Base width multiplier for innermost glow layer
@export var inner_width_multiplier: float = 1.5
## Width multiplier for outermost glow layer
@export var outer_width_multiplier: float = 4.0
## Opacity of innermost glow layer
@export_range(0.0, 1.0, 0.01) var inner_opacity: float = 0.8
## Opacity of outermost glow layer
@export_range(0.0, 1.0, 0.01) var outer_opacity: float = 0.05
## Draw core line on top
@export var draw_core: bool = true
## Core line color (usually brighter than glow)
@export var core_color: Color = Color.WHITE
## Core line width multiplier
@export var core_width_multiplier: float = 0.5
## Pulse effect enabled
@export var pulse_enabled: bool = false
## Pulse speed (cycles per second)
@export var pulse_speed: float = 2.0
## Pulse intensity (0 = no pulse, 1 = full pulse)
@export_range(0.0, 1.0, 0.01) var pulse_intensity: float = 0.3

var _canvas: Node2D = null
var _time: float = 0.0
var _cached_render_points: PackedVector2Array

func _render(data: CRopeData, render_points: PackedVector2Array) -> void:
	var r: CRope2D = get_rope()
	if r == null:
		return
	if _canvas == null:
		_canvas = Node2D.new()
		_canvas.name = "GlowRenderCanvas"
		_canvas.draw.connect(_on_draw)
		r.add_child(_canvas)
	_cached_render_points = render_points
	if pulse_enabled:
		_time = Time.get_ticks_msec() / 1000.0
	_canvas.queue_redraw()

func _cleanup() -> void:
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
		_canvas = null

func _on_draw() -> void:
	var r: CRope2D = get_rope()
	if r == null or _canvas == null:
		return
	if _cached_render_points.size() < 2:
		return
	var base_width: float = r.get_collision_width()
	# Calculate pulse multiplier
	var pulse_mult: float = 1.0
	if pulse_enabled:
		var pulse: float = (sin(_time * pulse_speed * TAU) + 1.0) * 0.5
		pulse_mult = 1.0 + pulse * pulse_intensity
	# Draw glow layers from outside to inside
	for i in range(glow_layers - 1, -1, -1):
		var t: float = float(i) / float(glow_layers - 1) if glow_layers > 1 else 0.0
		var width_mult: float = lerpf(inner_width_multiplier, outer_width_multiplier, t)
		var opacity: float = lerpf(inner_opacity, outer_opacity, t)
		var layer_width: float = base_width * width_mult * pulse_mult
		var layer_color: Color = glow_color
		layer_color.a = opacity * pulse_mult
		_canvas.draw_polyline(_cached_render_points, layer_color, layer_width, true)
	# Draw core on top
	if draw_core:
		var core_width: float = base_width * core_width_multiplier
		_canvas.draw_polyline(_cached_render_points, core_color, core_width, true)
