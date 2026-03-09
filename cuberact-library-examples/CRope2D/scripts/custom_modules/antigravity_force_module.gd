## Antigravity force module - pushes rope upward
## Use together with CRopeGravityForceMod to see the effect (rope should float slowly upward)
class_name AntigravityForceModule extends CRopeForceMod

@export var strength: float = 1000.0

func _update_forces(forces: PackedVector2Array, data: CRopeData, delta: float) -> PackedVector2Array:
	for i in forces.size():
		forces[i] += Vector2(0.0, -strength)
	return forces
