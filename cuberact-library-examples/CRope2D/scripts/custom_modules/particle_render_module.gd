## Particle render module - emits particles along the rope
## Creates GPUParticles2D nodes at rope points for visual effects
class_name ParticleRenderModule extends CRopeRenderMod

## Emit mode determines where particles spawn
enum EmitMode {
	ALL_POINTS,      ## Emit from all rope points
	ENDPOINTS,       ## Emit only from first and last point
	MOVING_POINTS,   ## Emit from points with velocity above threshold
	TENSION_POINTS,  ## Emit from points under high tension
}
## Where to emit particles
@export var emit_mode: EmitMode = EmitMode.MOVING_POINTS
## Velocity threshold for MOVING_POINTS mode
@export var velocity_threshold: float = 50.0
## Tension threshold for TENSION_POINTS mode (segment stretch ratio)
@export var tension_threshold: float = 1.5
## Particle material (required)
@export var particle_material: ParticleProcessMaterial
## Number of particles per emitter
@export var amount: int = 8
## Lifetime of particles
@export var lifetime: float = 0.5
## One-shot mode (emit once per condition)
@export var one_shot: bool = false
## Emitter visibility when not emitting
@export var hide_inactive: bool = true

var _emitters: Array[GPUParticles2D] = []
var _container: Node2D = null

func _render(data: CRopeData, _render_points: PackedVector2Array) -> void:
	var r: CRope2D = get_rope()
	if r == null or particle_material == null or data == null:
		return
	if _container == null:
		_container = Node2D.new()
		_container.name = "ParticleContainer"
		r.add_child(_container)
	var points: PackedVector2Array = data.get_points()
	var prev_points: PackedVector2Array = data.get_prev_points()
	var count: int = points.size()
	_ensure_emitters(count)
	# Determine which points should emit
	var emit_flags: Array[bool] = []
	emit_flags.resize(count)
	match emit_mode:
		EmitMode.ALL_POINTS:
			for i in count:
				emit_flags[i] = true
		EmitMode.ENDPOINTS:
			for i in count:
				emit_flags[i] = (i == 0 or i == count - 1)
		EmitMode.MOVING_POINTS:
			for i in count:
				var vel: Vector2 = points[i] - prev_points[i]
				emit_flags[i] = vel.length() > velocity_threshold * r.get_physics_process_delta_time()
		EmitMode.TENSION_POINTS:
			var seg_len: float = data.get_segment_length()
			for i in count:
				if i < count - 1:
					var dist: float = points[i].distance_to(points[i + 1])
					emit_flags[i] = dist > seg_len * tension_threshold
				else:
					emit_flags[i] = false
	# Update emitter positions and states
	for i in count:
		var em: GPUParticles2D = _emitters[i]
		em.position = points[i]
		em.emitting = emit_flags[i]
		if hide_inactive:
			em.visible = emit_flags[i] or em.emitting

func _cleanup() -> void:
	for em in _emitters:
		if is_instance_valid(em):
			em.queue_free()
	_emitters.clear()
	if _container != null and is_instance_valid(_container):
		_container.queue_free()
		_container = null

func _ensure_emitters(count: int) -> void:
	while _emitters.size() < count:
		var em: GPUParticles2D = GPUParticles2D.new()
		em.process_material = particle_material
		em.amount = amount
		em.lifetime = lifetime
		em.one_shot = one_shot
		em.emitting = false
		_container.add_child(em)
		_emitters.append(em)
	while _emitters.size() > count:
		var em: GPUParticles2D = _emitters.pop_back()
		if is_instance_valid(em):
			em.queue_free()
