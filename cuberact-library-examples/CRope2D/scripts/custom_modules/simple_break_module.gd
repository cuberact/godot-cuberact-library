## Simple break module - breaks rope when total length exceeds threshold
## Breaks at the most stressed point (average stretch of its two adjacent
## segments). Measuring over segment pairs is stable regardless of how the
## constraint solver distributes points. The Red-Black solver settles a
## taut rope into alternating segment lengths, so a single-segment measure
## would be biased.
class_name SimpleBreakModule extends CRopeBreakMod

@export var max_total_stretch: float = 1.5

func _check_break(data: CRopeData) -> int:
	if data == null:
		return -1
	var points: PackedVector2Array = data.points
	var segment_length: float = data.segment_length
	var count: int = points.size()
	if count < 3:
		return -1
	# Calculate total stretch
	var total_length: float = 0.0
	var rest_length: float = segment_length * (count - 1)
	for i in count - 1:
		total_length += points[i].distance_to(points[i + 1])
	var stretch_ratio: float = total_length / rest_length
	if stretch_ratio < max_total_stretch:
		return -1
	# Find the most stressed point
	var max_stress: float = 0.0
	var break_index: int = -1
	for i in range(1, count - 2):  # Avoid breaking at endpoints
		var stress: float = points[i - 1].distance_to(points[i]) + points[i].distance_to(points[i + 1])
		if stress > max_stress:
			max_stress = stress
			break_index = i
	return break_index
