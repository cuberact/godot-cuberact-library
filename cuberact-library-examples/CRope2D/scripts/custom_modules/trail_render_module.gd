## Trail render module - draws ghost trail showing previous rope positions
## Creates a fading afterimage effect for moving ropes
class_name TrailRenderModule extends CRopeRenderMod

## Number of trail frames to store
@export_range(2, 30, 1) var trail_length: int = 10
## Trail color at newest position
@export var color_start: Color = Color(1.0, 1.0, 1.0, 0.5)
## Trail color at oldest position (usually transparent)
@export var color_end: Color = Color(1.0, 1.0, 1.0, 0.0)
## Trail line width at newest position
@export var width_start: float = 10.0
## Trail line width at oldest position
@export var width_end: float = 2.0
## How often to capture a frame (1 = every frame, 2 = every other frame)
@export_range(1, 10, 1) var capture_interval: int = 1
## Only show trail when rope is moving
@export var only_when_moving: bool = true
## Velocity threshold to consider rope as moving
@export var movement_threshold: float = 5.0

var _canvas: Node2D = null
var _trail_history: Array[PackedVector2Array] = []
var _frame_counter: int = 0

func _render(data: CRopeData, render_points: PackedVector2Array) -> void:
	var r: CRope2D = get_rope()
	if r == null or data == null:
		return
	if _canvas == null:
		_canvas = Node2D.new()
		_canvas.name = "TrailRenderCanvas"
		_canvas.z_index = -1  # Draw behind rope
		_canvas.draw.connect(_on_draw)
		r.add_child(_canvas)
	# Capture frame at interval
	_frame_counter += 1
	if _frame_counter >= capture_interval:
		_frame_counter = 0
		if only_when_moving:
			if _is_rope_moving(data):
				_add_trail_frame(render_points)
		else:
			_add_trail_frame(render_points)
	_canvas.queue_redraw()

func _cleanup() -> void:
	_trail_history.clear()
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
		_canvas = null

func _on_draw() -> void:
	if _trail_history.is_empty():
		return
	var history_size: int = _trail_history.size()
	# Draw oldest to newest (so newer trails appear on top)
	for i in history_size:
		var t: float = float(i) / float(history_size - 1) if history_size > 1 else 0.0
		var color: Color = color_end.lerp(color_start, t)
		var width: float = lerpf(width_end, width_start, t)
		var points: PackedVector2Array = _trail_history[i]
		if points.size() >= 2:
			_canvas.draw_polyline(points, color, width, true)

func _add_trail_frame(points: PackedVector2Array) -> void:
	_trail_history.append(points.duplicate())
	while _trail_history.size() > trail_length:
		_trail_history.pop_front()

func _is_rope_moving(data: CRopeData) -> bool:
	var points: PackedVector2Array = data.get_points()
	var prev_points: PackedVector2Array = data.get_prev_points()
	if prev_points.size() != points.size():
		return true
	var total_movement: float = 0.0
	for i in points.size():
		total_movement += points[i].distance_to(prev_points[i])
	var avg_movement: float = total_movement / points.size()
	return avg_movement > movement_threshold * get_rope().get_physics_process_delta_time()
