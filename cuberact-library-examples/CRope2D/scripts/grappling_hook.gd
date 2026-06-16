@tool
class_name GrapplingHook
extends Node2D
## Grappling hook. Shoots a hook toward the mouse, then lets you retract the
## rope or cut it and leave it hanging. Builds and trims CRope2D data at runtime.

signal hook_attached(position: Vector2)
signal hook_retracted
signal hook_cut

@export_flags_2d_physics var target_mask: int = 1
@export var hook_radius: float = 10.0
@export var shoot_impulse_multiplier: float = 4.0
## Frames between removing one segment during retraction
@export var retract_interval: int = 1

enum State { IDLE, SHOOTING, ATTACHED, RETRACTING }
var _state: State = State.IDLE
var _retract_counter: int = 0

var _rope: CRope2D
var _hook_body: RigidBody2D
var _anchor_hook: CRopeAnchor
var _anchor_player: CRopeAnchor
var _anchor_target: CRopeAnchor
var _rope_container: Node2D
var _dev_tools: Node
var _last_hue: float = randf()

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_create_rope_container()
	_dev_tools = get_parent().get_node_or_null("DevTools")
	if _dev_tools:
		_dev_tools.add_controls_entries([
			["Space", "shoot rope towards mouse"],
			["X", "retract rope back"],
			["C", "cut rope (stays in scene)"],
		])

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	match _state:
		State.SHOOTING:
			_process_shooting()
		State.RETRACTING:
			_process_retracting()
		State.IDLE:
			queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_SPACE:
				if _state == State.IDLE:
					shoot(_get_shoot_direction())
			KEY_X:
				if _state == State.ATTACHED:
					retract()
			KEY_C:
				if _state == State.ATTACHED:
					cut()

## Shoots the hook in the given direction. Direction length affects impulse strength.
func shoot(direction: Vector2) -> void:
	if _state != State.IDLE:
		return
	var dir_normalized := direction.normalized()
	_rope = _create_rope()
	_rope_container.add_child(_rope)
	_register_rope(_rope)
	_hook_body = _create_hook_body()
	_rope_container.add_child(_hook_body)
	_hook_body.global_position = global_position + dir_normalized * (hook_radius + _rope.collision_width)
	_setup_rope_for_shooting(dir_normalized)
	_hook_body.apply_central_impulse(direction * shoot_impulse_multiplier)
	_state = State.SHOOTING

## Detaches the rope from target and starts retracting back to player.
func retract() -> void:
	if _state != State.ATTACHED:
		return
	if _anchor_target:
		_rope.anchors = [_anchor_player]
		_anchor_target = null
	_retract_counter = 0
	_state = State.RETRACTING

## Cuts the player from the rope (removes player anchor), rope stays in scene.
func cut() -> void:
	if _state != State.ATTACHED:
		return
	if _anchor_player:
		var anchors := _rope.anchors.duplicate()
		var idx := anchors.find(_anchor_player)
		if idx >= 0:
			anchors.remove_at(idx)
		_rope.anchors = anchors
	_rope = null
	_anchor_hook = null
	_anchor_player = null
	_anchor_target = null
	_state = State.IDLE
	hook_cut.emit()

## Immediately releases the rope and removes it from scene.
func release() -> void:
	if _rope:
		_unregister_rope(_rope)
		_rope.queue_free()
		_rope = null
	if _hook_body:
		_hook_body.queue_free()
		_hook_body = null
	_anchor_hook = null
	_anchor_player = null
	_anchor_target = null
	_state = State.IDLE
	hook_retracted.emit()

func _create_rope_container() -> void:
	_rope_container = Node2D.new()
	_rope_container.name = "RopeContainer"
	get_parent().add_child.call_deferred(_rope_container)
	_move_rope_container_deferred.call_deferred()

func _move_rope_container_deferred() -> void:
	var parent := get_parent()
	var my_index := get_index()
	parent.move_child(_rope_container, my_index + 1)

func _create_rope() -> CRope2D:
	var rope := CRope2D.new()
	rope.substeps = 6
	rope.collision_width = 20.0
	var gravity := CRopeWorldGravityForceMod.new()
	rope.force_modules = [gravity]
	var smooth := CRopeSmoothLineMod.new()
	var simplify := CRopeSimplifyLineMod.new()
	rope.line_modules = [smooth, simplify]
	var renderer := CRopeDirectRenderMod.new()
	renderer.width = 20.0
	var debug_renderer := CRopeDebugRenderMod.new()
	debug_renderer.set_all_draws(false)
	debug_renderer.draw_overlay = true
	debug_renderer.wake_color = Color.from_rgba8(0, 0, 0, 0)
	rope.render_modules = [renderer, debug_renderer]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://cuberact-library-examples/commons/rope.gdshader")
	var base_color := _generate_random_pastel()
	var darker_color := base_color.darkened(0.3)
	mat.set_shader_parameter("rope_color1", darker_color)
	mat.set_shader_parameter("rope_color2", base_color)
	rope.material = mat
	return rope

func _process_shooting() -> void:
	_extend_rope_towards_player()
	var collision := _check_hook_collision()
	if not collision.is_empty():
		_attach_hook(collision)
		return

func _process_retracting() -> void:
	_shorten_rope_from_player()
	if _rope.data.get_count() <= 2:
		release()

func _setup_rope_for_shooting(direction: Vector2) -> void:
	var seg_len := _rope.collision_width
	_rope.data.clear()
	_rope.data.append(_hook_body.global_position)
	_rope.data.append(global_position)
	_rope.data.segment_length = seg_len
	_anchor_hook = CRopeAnchor.new()
	_anchor_hook.index = 0
	_anchor_hook.node_path = _rope.get_path_to(_hook_body)
	var hook_offset := -direction * hook_radius
	_anchor_hook.offset_angle = rad_to_deg(atan2(hook_offset.y, hook_offset.x))
	_anchor_hook.offset_distance = hook_offset.length()
	_anchor_hook.pull_strength = 0.0
	_rope.anchors = [_anchor_hook]

func _extend_rope_towards_player() -> void:
	if not _hook_body:
		return
	var seg_len := _rope.collision_width
	var last_index := _rope.data.get_count() - 1
	var last_pos := _rope.data.points[last_index]
	while last_pos.distance_to(global_position) > seg_len:
		var dir_to_player := (global_position - last_pos).normalized()
		var new_pos := last_pos + dir_to_player * seg_len
		_rope.data.append(new_pos)
		last_index = _rope.data.get_count() - 1
		last_pos = _rope.data.points[last_index]

func _shorten_rope_from_player() -> void:
	_retract_counter += 1
	if _retract_counter < retract_interval:
		return
	_retract_counter = 0
	if _rope.data.get_count() <= 2:
		return
	_rope.data.remove()
	if _anchor_player:
		_anchor_player.index = _rope.data.get_count() - 1

func _check_hook_collision() -> Dictionary:
	if not _hook_body:
		return {}
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsShapeQueryParameters2D.new()
	var shape := CircleShape2D.new()
	shape.radius = hook_radius
	query.shape = shape
	query.transform.origin = _hook_body.global_position
	query.collision_mask = target_mask
	query.exclude = [_hook_body.get_rid()]
	var results := space_state.intersect_shape(query, 1)
	if results.is_empty():
		return {}
	return results[0]

func _attach_hook(collision: Dictionary) -> void:
	if not _hook_body:
		return
	var hit_position := _hook_body.global_position
	var collider: Node2D = collision.collider
	_hook_body.queue_free()
	_hook_body = null
	_extend_rope_to_relaxed()
	_anchor_target = CRopeAnchor.new()
	_anchor_target.index = 0
	_anchor_target.node_path = _rope.get_path_to(collider)
	var target_offset := collider.to_local(hit_position)
	_anchor_target.offset_angle = rad_to_deg(atan2(target_offset.y, target_offset.x))
	_anchor_target.offset_distance = target_offset.length()
	_anchor_player = CRopeAnchor.new()
	_anchor_player.index = _rope.data.get_count() - 1
	_anchor_player.node_path = _rope.get_path_to(self)
	_rope.anchors = [_anchor_target, _anchor_player]
	_anchor_hook = null
	_state = State.ATTACHED
	hook_attached.emit(hit_position)

func _extend_rope_to_relaxed() -> void:
	var seg_len := _rope.collision_width
	var actual_length := 0.0
	for i in range(_rope.data.get_count() - 1):
		actual_length += _rope.data.points[i].distance_to(_rope.data.points[i + 1])
	var relaxed_length := (_rope.data.get_count() - 1) * seg_len
	while relaxed_length < actual_length:
		var last_index := _rope.data.get_count() - 1
		var last_pos: Vector2 = _rope.data.points[last_index]
		var dir_to_player := (global_position - last_pos).normalized()
		var new_pos := last_pos + dir_to_player * seg_len
		_rope.data.append(new_pos)
		relaxed_length += seg_len

func _create_hook_body() -> RigidBody2D:
	var body := RigidBody2D.new()
	body.gravity_scale = 1.0
	body.mass = 10.0
	body.linear_damp = 0.0
	body.angular_damp = 0.0
	body.continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	var coll := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = hook_radius
	coll.shape = shape
	body.add_child(coll)
	return body

func _get_shoot_direction() -> Vector2:
	return get_global_mouse_position() - global_position

func _register_rope(rope: CRope2D) -> void:
	if _dev_tools:
		_dev_tools.register_debug_rope(rope)

func _unregister_rope(rope: CRope2D) -> void:
	if _dev_tools:
		_dev_tools.unregister_debug_rope(rope)

func _generate_random_pastel() -> Color:
	_last_hue = fmod(_last_hue + 0.618033988749895, 1.0)
	var saturation := randf_range(0.4, 0.6)
	var value := randf_range(0.85, 0.95)
	return Color.from_hsv(_last_hue, saturation, value)
