## Decimate line module - keeps only every Nth point
## Useful for testing line processing and reducing point count
class_name DecimateLineModule extends CRopeLineMod

@export var keep_every: int = 3

func _process_line(input: PackedVector2Array) -> PackedVector2Array:
	if keep_every < 2:
		return input
	var result: PackedVector2Array = PackedVector2Array()
	var size: int = input.size()
	for i in size:
		if i % keep_every == 0 or i == size - 1:
			result.append(input[i])
	return result
