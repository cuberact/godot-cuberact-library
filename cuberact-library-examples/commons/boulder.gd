@tool
extends RigidBody2D

@export_tool_button("Rnd", "Reload") var randomize_action: Callable = randomize_boulder
@export var boulder_seed: int = 0

@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D
@onready var visual_polygon: Polygon2D = $Polygon2D

static var COLOR_GRAVITY := Color(0.75, 0.15, 0.2, 1.0)
static var COLOR_NO_GRAVITY := Color(0.2, 0.7, 0.25, 1.0)
static var COLOR_NEGATIVE := Color(0.55, 0.15, 0.7, 1.0)

static var rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	if boulder_seed == 0:
		randomize_boulder()
	else:
		generate_boulder()

func randomize_boulder() -> void:
	boulder_seed = randi()
	generate_boulder()

func generate_boulder() -> void:
	rng.seed = boulder_seed
	var radius := rng.randf_range(40.0, 60.0)
	var points := PackedVector2Array()
	var angle := 0.0
	var threshold := rng.randf_range(30.0, 80.0)
	points.append(Vector2(1.0, 0.0) * radius)
	for i in 1000:
		angle += rng.randf_range(5.0, threshold)
		if angle > 358.0:
			break
		var a := deg_to_rad(angle)
		points.append(Vector2(cos(a), sin(a)) * radius)
	points.append(points[0])
	collision_polygon.polygon = points
	visual_polygon.polygon = points
	update_color()
	queue_redraw()

var _saved_gravity_scale: float = NAN

func toggle_gravity() -> void:
	if gravity_scale != 0.0:
		_saved_gravity_scale = gravity_scale
		gravity_scale = 0.0
	else:
		gravity_scale = _saved_gravity_scale if not is_nan(_saved_gravity_scale) else 1.0
		_saved_gravity_scale = NAN
	update_color()

func _set(property: StringName, _value: Variant) -> bool:
	if property == &"gravity_scale" and is_node_ready():
		call_deferred("update_color")
	return false

func update_color() -> void:
	if gravity_scale < 0.0:
		var abs_gs := absf(gravity_scale)
		if abs_gs < 1.0:
			visual_polygon.color = COLOR_NEGATIVE.lightened((1.0 - abs_gs) * 0.6)
		else:
			visual_polygon.color = COLOR_NEGATIVE.darkened(clampf((abs_gs - 1.0) / 4.0, 0.0, 0.7))
	elif gravity_scale == 0.0:
		visual_polygon.color = COLOR_NO_GRAVITY
	elif gravity_scale < 1.0:
		visual_polygon.color = COLOR_GRAVITY.lightened((1.0 - gravity_scale) * 0.6)
	else:
		visual_polygon.color = COLOR_GRAVITY.darkened(clampf((gravity_scale - 1.0) / 4.0, 0.0, 0.7))
