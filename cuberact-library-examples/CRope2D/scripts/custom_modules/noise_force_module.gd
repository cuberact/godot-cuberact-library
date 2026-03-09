## Noise force module - applies random forces to simulate turbulence
## Creates a shaking/vibrating effect on the rope
class_name NoiseForceModule extends CRopeForceMod

@export var strength: float = 500.0
@export var frequency: float = 10.0

var _time: float = 0.0

func _update_forces(forces: PackedVector2Array, data: CRopeData, delta: float) -> PackedVector2Array:
	_time += delta
	for i in forces.size():
		var noise_x: float = sin(_time * frequency + i * 0.5) * strength
		var noise_y: float = cos(_time * frequency * 1.3 + i * 0.7) * strength
		forces[i] += Vector2(noise_x, noise_y)
	return forces
