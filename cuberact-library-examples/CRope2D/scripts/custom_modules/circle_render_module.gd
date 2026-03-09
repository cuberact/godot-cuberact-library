## Circle render module - draws circles at each rope point
## Simple debug visualization using GDScript rendering
class_name CircleRenderModule extends CRopeRenderMod

@export var radius: float = 5.0
@export var color: Color = Color.YELLOW
@export var filled: bool = true

var _canvas: Node2D = null
var _cached_render_points: PackedVector2Array

func _render(data: CRopeData, render_points: PackedVector2Array) -> void:
	var r: CRope2D = get_rope()
	if r == null:
		return
	if _canvas == null:
		_canvas = Node2D.new()
		_canvas.name = "CircleRenderCanvas"
		_canvas.draw.connect(_on_draw)
		r.add_child(_canvas)
	_cached_render_points = render_points
	_canvas.queue_redraw()

func _cleanup() -> void:
	if _canvas != null:
		_canvas.queue_free()
		_canvas = null

func _on_draw() -> void:
	if _canvas == null:
		return
	for point in _cached_render_points:
		if filled:
			_canvas.draw_circle(point, radius, color)
		else:
			_canvas.draw_arc(point, radius, 0, TAU, 32, color, 2.0)
