extends Node
## Tracks rope break events and updates DevTools debug_ropes accordingly.
## When a rope breaks, unregisters the original and registers both fragments.

@export var dev_tools: Node
@export var ropes: Array[CRope2D]

func _ready() -> void:
	for rope in ropes:
		if rope:
			_track_rope(rope)

func _track_rope(rope: CRope2D) -> void:
	rope.broken.connect(_on_rope_broken.bind(rope))

func _on_rope_broken(_break_index: int, rope_a: CRope2D, rope_b: CRope2D, original: CRope2D) -> void:
	if not dev_tools:
		return
	# Defer to avoid interfering with break_at() internals (disable/enable_debug_probe
	# called mid-break can crash the native code).
	_deferred_swap.call_deferred(original, rope_a, rope_b)

func _deferred_swap(original: CRope2D, rope_a: CRope2D, rope_b: CRope2D) -> void:
	dev_tools.unregister_debug_rope(original)
	if rope_a:
		dev_tools.register_debug_rope(rope_a)
		_track_rope(rope_a)
	if rope_b:
		dev_tools.register_debug_rope(rope_b)
		_track_rope(rope_b)
