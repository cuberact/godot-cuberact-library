## Tension color render module - colors rope based on segment tension
## Visualizes stress/strain along the rope with gradient colors
class_name TensionColorRenderModule extends CRopeRenderMod

## Color when segment is at rest length (no tension)
@export var color_relaxed: Color = Color(1.0, 1.0, 1.0, 0.0)
## Color when segment is stretched to threshold
@export var color_stretched: Color = Color(1.0, 0.2, 0.2, 1.0)
## Stretch ratio at which color_stretched is fully applied (1.0 = 100% stretch)
@export_range(0.1, 5.0, 0.1) var stretch_threshold: float = 1.0
## Line width (0 = use rope width)
@export var width: float = 0.0
## Draw antialiased lines
@export var antialiased: bool = false

var _canvas: Node2D = null
var _cached_render_points: PackedVector2Array

func _render(data: CRopeData, render_points: PackedVector2Array) -> void:
	var r: CRope2D = get_rope()
	if r == null:
		return
	if _canvas == null:
		_canvas = Node2D.new()
		_canvas.name = "TensionColorCanvas"
		_canvas.draw.connect(_on_draw)
		r.add_child(_canvas)
	_cached_render_points = render_points
	_canvas.queue_redraw()

func _cleanup() -> void:
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
		_canvas = null

func _on_draw() -> void:
	var r: CRope2D = get_rope()
	if r == null or _canvas == null:
		return
	var data: CRopeData = r.get_data()
	if data == null:
		return
	var sim_points: PackedVector2Array = data.get_points()
	if _cached_render_points.size() < 2 or sim_points.size() < 2:
		return
	var seg_len: float = data.get_segment_length()
	var line_width: float = width if width > 0.0 else r.get_collision_width()
	# Calculate tension from simulation points, draw with render points
	var seg_count: int = sim_points.size() - 1
	var render_count: int = _cached_render_points.size() - 1
	for i in render_count:
		# Map render segment to simulation segment
		var sim_idx: int = mini(i * seg_count / render_count, seg_count - 1)
		var dist: float = sim_points[sim_idx].distance_to(sim_points[sim_idx + 1])
		var ratio: float = dist / seg_len if seg_len > 0.0 else 1.0
		var t: float = clampf((ratio - 1.0) / stretch_threshold, 0.0, 1.0)
		var color: Color = color_relaxed.lerp(color_stretched, t)
		_canvas.draw_line(_cached_render_points[i], _cached_render_points[i + 1], color, line_width, antialiased)
