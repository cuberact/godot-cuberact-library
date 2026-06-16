@tool
extends StaticBody2D

enum ObstacleType { CIRCLE, RECT, POLYGON }

@export var type: ObstacleType = ObstacleType.RECT:
	set(value):
		type = value
		notify_property_list_changed()
		_rebuild()

@export var radius: float = 50.0:
	set(value):
		radius = value
		_rebuild()

@export var rect_size: Vector2 = Vector2(100, 100):
	set(value):
		rect_size = value
		_rebuild()

@export var polygon: PackedVector2Array = PackedVector2Array():
	set(value):
		polygon = value
		_rebuild()

@onready var visual: Polygon2D = $Visual

func _ready() -> void:
	_rebuild()

func _validate_property(property: Dictionary) -> void:
	match property.name:
		"radius":
			if type != ObstacleType.CIRCLE:
				property.usage = PROPERTY_USAGE_NO_EDITOR
		"rect_size":
			if type != ObstacleType.RECT:
				property.usage = PROPERTY_USAGE_NO_EDITOR
		"polygon":
			if type != ObstacleType.POLYGON:
				property.usage = PROPERTY_USAGE_NO_EDITOR

func _rebuild() -> void:
	if not is_node_ready():
		return
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.free()
	match type:
		ObstacleType.CIRCLE:
			_build_circle()
		ObstacleType.RECT:
			_build_rect()
		ObstacleType.POLYGON:
			_build_polygon()
	move_child(visual, -1)

func _build_circle() -> void:
	var shape := CircleShape2D.new()
	shape.radius = radius
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	var points := PackedVector2Array()
	var segments := clampi(int(radius), 16, 100)
	for i in segments:
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	visual.polygon = points

func _build_rect() -> void:
	var shape := RectangleShape2D.new()
	shape.size = rect_size
	var col := CollisionShape2D.new()
	col.shape = shape
	add_child(col)
	var half := rect_size / 2.0
	visual.polygon = PackedVector2Array([
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y),
	])

func _build_polygon() -> void:
	var col := CollisionPolygon2D.new()
	col.polygon = polygon
	add_child(col)
	visual.polygon = polygon
