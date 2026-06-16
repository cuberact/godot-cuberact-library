extends Node2D
## Grand curtain. A theater curtain made of dense rope strands hanging from
## the proscenium. Drag the brass slider on the top beam (or press SPACE) to draw
## the curtain: the strand roots slide aside in a wave from the center, the
## strands swing, and the Cuberact logo is revealed in the spotlight.

const STRANDS := 46
const STRAND_SPACING := 43.5
const STRAND_LENGTH := 972.0
const SEGMENT_LENGTH := 10.0
const TOP_Y := 76.0
# Brass slider mounted on the proscenium beam: drag it left -> right to open the curtain.
const SLIDER_LEFT := 520.0
const SLIDER_RIGHT := 1400.0
const SLIDER_Y := 39.0
const HANDLE_HALF := Vector2(18.0, 14.0)
const OPEN_SPREAD := 0.45 # how far the edge strands lag behind the center ones (the center-out wave)

var _dev_tools: Node
var _rng := RandomNumberGenerator.new()
var _roots: Array[Node2D] = []
var _home_x: Array[float] = []  # closed position per strand
var _open_x: Array[float] = []  # open position per strand (bunched at the edges)
var _open_amount := 0.0
var _handle: Polygon2D
var _dragging := false
var _tween: Tween

func _ready() -> void:
	_rng.randomize()
	_dev_tools = get_node_or_null("DevTools")
	if _dev_tools:
		_dev_tools.add_controls_entries([
			["Left mouse", "drag the slider on the beam to open / close the curtain"],
			["SPACE", "open / close the curtain"],
		])
	var logo: Sprite2D = $Logo
	logo.scale = Vector2.ONE * (410.0 / logo.texture.get_width())
	var center := (STRANDS - 1) * 0.5
	for i in STRANDS:
		_spawn_strand(i)
		# Left half bunches against the left edge, right half against the right edge.
		_open_x.append(40.0 + i * 9.0 if i <= int(center) else 1880.0 - (STRANDS - 1 - i) * 9.0)
	_build_slider()
	_set_open(0.0)

## Drives both the slider handle and the strand roots from a single open amount (0 = closed, 1 = open).
func _set_open(t: float) -> void:
	_open_amount = t
	_handle.position.x = lerpf(SLIDER_LEFT, SLIDER_RIGHT, t)
	var center := (STRANDS - 1) * 0.5
	for i in STRANDS:
		var d := absf(i - center) / center # 0 at the center, 1 at the edges
		var local := clampf((t - d * OPEN_SPREAD) / (1.0 - OPEN_SPREAD), 0.0, 1.0)
		_roots[i].position.x = lerpf(_home_x[i], _open_x[i], local)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_SPACE:
		_kill_tween()
		_tween = create_tween()
		_tween.tween_method(_set_open, _open_amount, 1.0 if _open_amount < 0.5 else 0.0, 4.6) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

## Slider dragging. Handled in _input (ahead of DevTools' _unhandled_input) and consumed, so grabbing
## the handle never also grabs a body or pans the camera.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _over_handle(get_global_mouse_position()):
			_dragging = true
			_kill_tween()
			get_viewport().set_input_as_handled()
		elif not event.pressed and _dragging:
			_dragging = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _dragging:
		var t := clampf((get_global_mouse_position().x - SLIDER_LEFT) / (SLIDER_RIGHT - SLIDER_LEFT), 0.0, 1.0)
		_set_open(t)
		get_viewport().set_input_as_handled()

func _over_handle(p: Vector2) -> bool:
	return absf(p.x - _handle.position.x) <= HANDLE_HALF.x and absf(p.y - SLIDER_Y) <= HANDLE_HALF.y

func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()

func _build_slider() -> void:
	var track := Polygon2D.new()
	track.polygon = PackedVector2Array([
		Vector2(SLIDER_LEFT - 18, SLIDER_Y - 9), Vector2(SLIDER_RIGHT + 18, SLIDER_Y - 9),
		Vector2(SLIDER_RIGHT + 18, SLIDER_Y + 9), Vector2(SLIDER_LEFT - 18, SLIDER_Y + 9),
	])
	track.color = Color(0.1, 0.06, 0.03)
	track.z_index = 50
	add_child(track)
	_handle = Polygon2D.new()
	_handle.polygon = PackedVector2Array([
		Vector2(-HANDLE_HALF.x, -HANDLE_HALF.y), Vector2(HANDLE_HALF.x, -HANDLE_HALF.y),
		Vector2(HANDLE_HALF.x, HANDLE_HALF.y), Vector2(-HANDLE_HALF.x, HANDLE_HALF.y),
	])
	_handle.color = Color(0.72, 0.56, 0.22)
	_handle.position.y = SLIDER_Y
	_handle.z_index = 51
	add_child(_handle)

func _spawn_strand(i: int) -> void:
	var x := 960.0 + (i - (STRANDS - 1) * 0.5) * STRAND_SPACING
	var root := Node2D.new()
	root.position = Vector2(x, TOP_Y)
	add_child(root)
	_roots.append(root)
	_home_x.append(x)

	var seg_count := maxi(int(STRAND_LENGTH / SEGMENT_LENGTH), 8)
	var data := CRopeData.new()
	data.create_line_by_count(root.position, root.position + Vector2(0, STRAND_LENGTH), seg_count)

	var rope := CRope2D.new()
	rope.data = data
	rope.collision_mask = 0
	rope.solver_mode = CRope2D.SOLVER_RED_BLACK
	rope.substeps = 6
	rope.damping = 0.6
	rope.force_modules = [CRopeWorldGravityForceMod.new()]
	rope.line_modules = [CRopeSmoothLineMod.new(), CRopeSimplifyLineMod.new()]
	var renderer := CRopeDirectRenderMod.new()
	renderer.width = 60.0
	var velvet := Color(0.5, 0.06, 0.09)
	renderer.color = velvet.lightened(_rng.randf_range(0.0, 0.12)) if i % 2 == 0 else velvet.darkened(_rng.randf_range(0.0, 0.15))
	rope.render_modules = [renderer]
	add_child(rope)
	var anchor := CRopeAnchor.new()
	anchor.index = 0
	anchor.node_path = rope.get_path_to(root)
	anchor.pull_strength = 0.0
	anchor.collision_resolve = false
	rope.anchors = [anchor]
	if _dev_tools:
		_dev_tools.register_debug_rope(rope)
