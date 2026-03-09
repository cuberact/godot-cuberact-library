## Wave line module - adds a sine wave offset to rope points
## Creates a wavy visual effect on the rope
class_name WaveLineModule extends CRopeLineMod

@export var amplitude: float = 20.0
@export var frequency: float = 0.1
@export var speed: float = 5.0

var _time: float = 0.0

func _process_line(input: PackedVector2Array) -> PackedVector2Array:
	# Use Engine time since Resource doesn't have delta
	_time = Time.get_ticks_msec() / 1000.0
	var result: PackedVector2Array = input.duplicate()
	var size: int = result.size()
	for i in size:
		var wave: float = sin(i * frequency + _time * speed) * amplitude
		# Offset perpendicular to the rope direction
		var dir: Vector2
		if i < size - 1:
			dir = (result[i + 1] - result[i]).normalized()
		elif i > 0:
			dir = (result[i] - result[i - 1]).normalized()
		else:
			dir = Vector2.RIGHT
		var perpendicular: Vector2 = Vector2(-dir.y, dir.x)
		result[i] += perpendicular * wave
	return result
