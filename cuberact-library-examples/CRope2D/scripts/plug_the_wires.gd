extends Node2D
## Plug the wires. A mini-game. Four colored cables hang from the breaker
## panel; drag each plug into the socket of the matching color anywhere on
## the screen. A correctly seated plug starts an animated current pulse
## running down the wire (a scrolling Gradient on CRopeDirectRenderMod), and
## once all four are live, the big bulb in the top bar lights up. ENTER resets.

const SCALE := 0.54 # the whole scene is uniformly scaled down from the old 2000 space to fit 1080 height
const SEGMENT_LENGTH := 4.0
const BAR_HEIGHT := 180.0 * SCALE
const PULSE_WAVELENGTH := 100.0 * SCALE # physical px between current pulses (same flow look on any cable length)
# Plug / socket geometry (local space, +X = insertion direction). The wide plug body is
# blocked by the socket block; only the two pins fit the two slots cut into the mouth face.
const PIN_DY := 22.0 * SCALE        # pin centre, half-spacing
const PIN_HALF_W := 7.0 * SCALE     # pin half thickness
const PIN_FACE_X := 24.0 * SCALE    # plug front face (pins start here)
const PIN_LEN := 42.0 * SCALE       # pin length
const BODY_BACK_X := -52.0 * SCALE  # plug back (rounded), where the cable attaches
const SLOT_HALF_H := 15.0 * SCALE   # socket slot half-height (wider than a pin → tolerance)
const SLOT_DEPTH := 46.0 * SCALE    # how deep the slots cut into the mouth
const SOCKET_RADIUS := 72.0 * SCALE     # socket disc radius (the body is a disc with a flat mouth face)
const SOCKET_FLAT_DEPTH := 40.0 * SCALE # how far the flat mouth face is sliced into the disc
# A seated plug is pinned by two joints. It unplugs when the DevTools drag force, projected
# along the socket's outward direction, exceeds this (i.e. you pull it straight out hard enough).
const BREAK_FORCE := 22000.0 * SCALE
# A point is fed in at the box whenever the average length of the two box-adjacent segments exceeds
# PAYOUT_RATIO x segment_length (and the cable is under MAX_POINTS). No rewind, no other conditions.
const PAYOUT_RATIO := 1.35
const MAX_POINTS := 600 # hard per-cable point cap; the cable stops growing once it reaches this
const FLASH_TIME := 0.2 # seconds for the port ring to fade from its lit tint back to the cable colour after payout
const HOLE_COLOR := Color(0.03, 0.03, 0.05) # the dark hole in the centre of the cable port
const ROPE_SHADER := preload("res://cuberact-library-examples/commons/rope.gdshader")
const BOX_X := 50.0 # x of the cable ports, near the left edge of the play area
const INITIAL_SEGMENTS := 5 # cable segments out of the box at startup (a nicer drop animation than one)
# Draw order (ports / top bar / obstacles stay at the default z 0, the bottom layer)
const Z_CABLE := 1 # cables draw above the bottom layer
const Z_TOP := 2   # plugs and sockets draw above the cables

const WIRES := [
	{"color": Color(0.85, 0.25, 0.2), "panel_y": 335.0, "socket": Vector2(1600, 1004), "socket_rot": 6.0},
	{"color": Color(0.95, 0.7, 0.15), "panel_y": 475.0, "socket": Vector2(1490, 621), "socket_rot": 80.0},
	{"color": Color(0.25, 0.75, 0.85), "panel_y": 616.0, "socket": Vector2(1760, 486), "socket_rot": 24.0},
	{"color": Color(0.35, 0.75, 0.3), "panel_y": 756.0, "socket": Vector2(1780, 216), "socket_rot": 65.0},
]

# Static obstacles the cables (and plugs) must be routed around.
const OBSTACLES := [
	{"shape": "circle", "pos": Vector2(960, 367), "radius": 59.0},
	{"shape": "rect", "pos": Vector2(1160, 551), "size": Vector2(178, 227)},
	{"shape": "circle", "pos": Vector2(700, 205), "radius": 96.0},
	{"shape": "circle", "pos": Vector2(420, 421), "radius": 60.0},
	{"shape": "circle", "pos": Vector2(560, 713), "radius": 108.0},
	{"shape": "circle", "pos": Vector2(1380, 248), "radius": 65.0},
	{"shape": "circle", "pos": Vector2(720, 940), "radius": 86.0},
	{"shape": "rect", "pos": Vector2(1180, 902), "size": Vector2(113, 259)},
]

var _dev_tools: Node
var _wires: Array[Dictionary] = []
var _bulb_glow: Sprite2D
var _bulb_core: Polygon2D
var _indicators: Array = []
var _all_connected := false
var _sockets: Array[Dictionary] = []

func _ready() -> void:
	_dev_tools = get_node_or_null("DevTools")
	if _dev_tools:
		_dev_tools.add_controls_entries([
			["Left mouse", "drag a plug; grab off-center to rotate it"],
			["", "push both pins into the matching socket; it snaps in"],
			["", "drag a seated plug out to overcome the latch"],
			["ENTER", "reset"],
		])
	_build_top_bar()
	_spawn_obstacles()
	# Sockets first so they render behind the plugs (a seated plug shows on top).
	for i in WIRES.size():
		var node := _spawn_socket(WIRES[i])
		_sockets.append({
			"node": node,
			"color": WIRES[i].color,
			"slots": [node.get_node("Slot0"), node.get_node("Slot1")],
			"occupant": null,
		})
	for i in WIRES.size():
		_spawn_wire(WIRES[i], i)

func _spawn_obstacles() -> void:
	var scene := preload("res://cuberact-library-examples/commons/obstacle.tscn")
	for o in OBSTACLES:
		var obs := scene.instantiate()
		obs.position = o.pos
		if o.shape == "circle":
			obs.type = 0 # ObstacleType.CIRCLE
			obs.radius = o.radius
		else:
			obs.type = 1 # ObstacleType.RECT
			obs.rect_size = o.size
		add_child(obs)
		obs.get_node("Visual").color = Color(0.22, 0.23, 0.27)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo() and event.keycode == KEY_ENTER:
		get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	_seat_update()
	_disconnect_update()
	_socket_drag_update()
	for wire in _wires:
		_payout(wire)
		if wire.powered:
			_animate_wire(wire, delta)
		_flash_update(wire, delta)
	if not _all_connected and _all_powered():
		_all_connected = true
		_power_up()

## Seats any plug whose two pins reach both deep slot detectors of a free socket. A plug that
## was just yanked out is blocked from re-seating until it has fully left the slots.
func _seat_update() -> void:
	for wire in _wires:
		if wire.get("seat_blocked", false) and not _plug_in_any_slot(wire.plug):
			wire.seat_blocked = false
	for socket in _sockets:
		if socket.occupant != null:
			continue
		var plug := _plug_in_slots(socket)
		if plug == null:
			continue
		var wire := _wire_of(plug)
		if not wire.is_empty() and wire.seated == null and not wire.get("seat_blocked", false):
			_seat(wire, socket)

## True if the plug currently triggers any socket's two slot detectors.
func _plug_in_any_slot(plug: RigidBody2D) -> bool:
	for socket in _sockets:
		if _plug_in_slots(socket) == plug:
			return true
	return false

## Unplugs a seated plug when the DevTools drag pulls it hard enough straight out of the socket.
func _disconnect_update() -> void:
	var db = _dev_tools.drag_body if _dev_tools else null
	if db == null:
		return
	for wire in _wires:
		if wire.seated == null or wire.plug != db:
			continue
		var grab: Vector2 = db.to_global(_dev_tools.drag_body_point)
		var out_dir := Vector2(-1.0, 0.0).rotated(wire.seated.node.global_rotation)
		var force_out: float = (get_global_mouse_position() - grab).dot(out_dir) * _dev_tools.drag_strength
		if force_out > BREAK_FORCE:
			_unseat(wire)

## While a seated socket is dragged via DevTools, the joints alone let the plug lag behind the
## kinematically moved (static) socket. Drive the plug straight to its seated pose so it tracks rigidly.
func _socket_drag_update() -> void:
	var ds = _dev_tools.drag_static if _dev_tools else null
	if ds == null:
		return
	for wire in _wires:
		if wire.seated != null and wire.seated.node == ds:
			var plug: RigidBody2D = wire.plug
			plug.global_position = ds.global_position - Vector2(PIN_FACE_X, 0.0).rotated(plug.global_rotation)
			plug.linear_velocity = Vector2.ZERO
			plug.angular_velocity = 0.0

## Returns the plug whose pins are in BOTH of the socket's deep slot detectors, or null.
func _plug_in_slots(socket: Dictionary) -> RigidBody2D:
	var in0: Array = socket.slots[0].get_overlapping_bodies()
	var in1: Array = socket.slots[1].get_overlapping_bodies()
	for body in in0:
		if in1.has(body):
			return body
	return null

func _wire_of(plug: RigidBody2D) -> Dictionary:
	for wire in _wires:
		if wire.plug == plug:
			return wire
	return {}

## Grows the cable from the box (the last point). When the two box-adjacent segments (the last and
## second-to-last; point 0 is at the plug) are on average longer than PAYOUT_RATIO x segment_length and
## the cable is under MAX_POINTS, one point is fed in just before the box. No mouse/drag dependency.
func _payout(wire: Dictionary) -> void:
	var data: CRopeData = wire.rope.data
	var count := data.get_count()
	if count >= MAX_POINTS:
		return
	var pts := data.points
	var last := count - 1
	var avg := (pts[last].distance_to(pts[last - 1]) + pts[last - 1].distance_to(pts[last - 2])) * 0.5
	if avg <= SEGMENT_LENGTH * PAYOUT_RATIO:
		return
	# Feed one point in just before the box, partway toward its neighbour (no overshoot).
	var pbox: Vector2 = pts[last]
	var to_prev := pts[last - 1] - pbox
	var d := to_prev.length()
	if d < 0.001:
		return
	data.append(pbox + to_prev / d * minf(SEGMENT_LENGTH, d * 0.5), last)
	wire.box_anchor.index = data.get_count() - 1
	wire.flash = 1.0 # the cable just grew → pulse the port ring white

## Brightens the port ring (bezel) to a lighter tint of the cable colour on a payout, then fades it back,
## so it is easy to see at a glance whether the cable is actually growing (ring flashes) or just stretching.
func _flash_update(wire: Dictionary, delta: float) -> void:
	if wire.flash <= 0.0:
		return
	wire.flash = maxf(0.0, wire.flash - delta / FLASH_TIME)
	wire.bezel.color = wire.color.lerp(wire.color.lightened(0.75), wire.flash)

## Repaints the overlay gradient so bright pulses of "current" travel along the cable. One gradient
## stop per cable point gives full geometry resolution, and the pulse pitch and speed are physical
## (driven by PULSE_WAVELENGTH), so the flow looks identical on cables of any length: a longer one
## just shows more pulses. The overlay blends additively: the alpha (spark) decides where it shows.
func _animate_wire(wire: Dictionary, delta: float) -> void:
	wire.phase = fposmod(wire.phase + delta * wire.speed, 1.0)
	var grad: Gradient = wire.gradient
	var count: int = wire.rope.data.get_count()
	if grad.get_point_count() != count: # resize to one stop per cable point
		var offsets := PackedFloat32Array()
		var colors := PackedColorArray()
		offsets.resize(count)
		colors.resize(count)
		for i in count:
			offsets[i] = float(i) / float(count - 1)
			colors[i] = Color(0, 0, 0, 0)
		grad.offsets = offsets
		grad.colors = colors
	var bright := Color(1.0, 1.0, 0.82)
	# i * SEGMENT_LENGTH is point i's arc length from the plug; +phase scrolls pulses box -> plug.
	for i in count:
		var wave := fposmod(float(i) * SEGMENT_LENGTH / PULSE_WAVELENGTH + wire.phase, 1.0)
		var spark := clampf(1.0 - absf(wave - 0.5) / 0.18, 0.0, 1.0)
		spark *= spark
		grad.set_color(i, Color(bright.r, bright.g, bright.b, spark * 0.9))

## Centres the plug into the ideal pose, then pins it there with two joints anchored at the
## socket's slot centres. (PinJoint2D locks the current pose and can't pull, so we snap first.)
func _seat(wire: Dictionary, socket: Dictionary) -> void:
	var plug: RigidBody2D = wire.plug
	var sn: Node2D = socket.node
	# Snap to the ideal pose: front face at the mouth, in the closest 180-deg orientation.
	var da := absf(angle_difference(plug.global_rotation, sn.global_rotation))
	var db := absf(angle_difference(plug.global_rotation, sn.global_rotation + PI))
	var target_rot: float = sn.global_rotation if da <= db else sn.global_rotation + PI
	plug.global_transform = Transform2D(target_rot, sn.global_position - Vector2(PIN_FACE_X, 0.0).rotated(target_rot))
	plug.linear_velocity = Vector2.ZERO
	plug.angular_velocity = 0.0
	wire.seated = socket
	socket.occupant = wire
	wire.joints = []
	for pin_y in [PIN_DY, -PIN_DY]:
		var joint := PinJoint2D.new()
		add_child(joint)
		joint.global_position = sn.to_global(Vector2(PIN_LEN, pin_y)) # socket slot centre
		joint.node_a = joint.get_path_to(sn)
		joint.node_b = joint.get_path_to(plug)
		wire.joints.append(joint)
	if wire.color.is_equal_approx(socket.color):
		_power_on(wire)
	_spark(sn.global_position, socket.color)

## Releases the plug: destroys the joints and stops the current if it was flowing.
func _unseat(wire: Dictionary) -> void:
	for joint in wire.get("joints", []):
		joint.queue_free()
	wire.joints = []
	var socket = wire.seated
	if socket != null:
		socket.occupant = null
	wire.seated = null
	wire.seat_blocked = true # don't re-seat until the plug has left the slots
	if wire.powered:
		_power_off(wire)
		if _all_connected:
			_all_connected = false
			_power_down()

func _power_on(wire: Dictionary) -> void:
	wire.powered = true
	# Sleep stays enabled: the current animates by repainting the overlay gradient, which redraws the
	# Line2D on its own. The rope itself doesn't need to keep simulating, so a seated cable can sleep.
	wire.rope.render_modules = [wire.base_renderer, wire.overlay] # current overlay on top
	_animate_wire(wire, 0.0) # paint the pulse before the overlay's first draw
	_light_indicator(wire.indicator)

func _power_off(wire: Dictionary) -> void:
	wire.powered = false
	wire.rope.render_modules = [wire.base_renderer] # drop the overlay (its Line2D is freed)
	wire.speed = 0.7
	_dim_indicator(wire.indicator)

func _dim_indicator(indicator: Dictionary) -> void:
	indicator.core.color = indicator.color.darkened(0.72)
	indicator.glow.modulate = Color(1, 1, 1, 0.0)

func _power_up() -> void:
	for wire in _wires:
		wire.speed = 1.3
	_bulb_core.color = Color(1.0, 0.92, 0.6)
	_bulb_glow.modulate = Color(1, 1, 1, 1)
	_spark(_bulb_glow.global_position, Color(1.0, 0.9, 0.5))

func _power_down() -> void:
	for wire in _wires:
		wire.speed = 0.7
	_bulb_core.color = Color(0.3, 0.3, 0.32)
	_bulb_glow.modulate = Color(1, 1, 1, 0.04)

func _all_powered() -> bool:
	for wire in _wires:
		if not wire.powered:
			return false
	return true

func _spark(pos: Vector2, color: Color) -> void:
	var spark := Sprite2D.new()
	spark.texture = _make_radial_texture(color)
	spark.position = pos
	spark.scale = Vector2.ONE * 0.3 * SCALE
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	spark.material = add_mat
	add_child(spark)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector2.ONE * 1.6 * SCALE, 0.4)
	tween.tween_property(spark, "modulate:a", 0.0, 0.4)
	tween.chain().tween_callback(spark.queue_free)

func _spawn_wire(config: Dictionary, index: int) -> void:
	var start := Vector2(BOX_X, config.panel_y)
	var outlet := Node2D.new()
	outlet.position = start
	add_child(outlet)
	var housing := Polygon2D.new()
	housing.polygon = PackedVector2Array([Vector2(-30 * SCALE, -32 * SCALE), Vector2(20 * SCALE, -32 * SCALE), Vector2(20 * SCALE, 32 * SCALE), Vector2(-30 * SCALE, 32 * SCALE)])
	housing.color = Color(0.14, 0.14, 0.18)
	outlet.add_child(housing)
	var bezel := Polygon2D.new()
	bezel.polygon = _circle_polygon(21.0 * SCALE)
	bezel.color = config.color
	outlet.add_child(bezel)
	var hole := Polygon2D.new()
	hole.polygon = _circle_polygon(13.0 * SCALE)
	hole.color = HOLE_COLOR
	outlet.add_child(hole)

	# The plug starts parked right at the box mouth (cable wound inside); it unwinds only while dragged.
	var plug := _spawn_plug(start + Vector2(64, 12) * SCALE, config.color)

	var end: Vector2 = plug.position + Vector2(-52, 0) * SCALE
	var data := CRopeData.new()
	# Point 0 at the plug, last point at the box, so the braid reads as cable coming out of the slit.
	data.create_line_by_count(end, start, INITIAL_SEGMENTS) # short cable already out; the rest unwinds on drag
	data.segment_length = SEGMENT_LENGTH

	var rope := CRope2D.new()
	rope.data = data
	rope.sleep_enabled = true
	rope.sleep_tolerance = 4.0
	rope.sleep_frames = 30
	rope.sleep_min_awake = 5
	rope.collision_mask = 1 # collide with walls and obstacles (layer 1)
	rope.collision_width = 16.0 * SCALE
	rope.damping = 0.5
	rope.solver_mode = CRope2D.SOLVER_RED_BLACK
	rope.force_modules = [CRopeWorldGravityForceMod.new()]
	rope.line_modules = [CRopeSmoothLineMod.new()]
	# Base look: the braided rope shader on the node, tinted to the cable colour. The DirectRenderMod
	# feeds length-based UVs, so the braid keeps a fixed physical pitch and flows as cable is pulled out.
	var mat := ShaderMaterial.new()
	mat.shader = ROPE_SHADER
	mat.set_shader_parameter("rope_color1", config.color.darkened(0.4))
	mat.set_shader_parameter("rope_color2", config.color)
	rope.material = mat
	var base_renderer := CRopeDirectRenderMod.new()
	base_renderer.width = 26.0 * SCALE
	base_renderer.begin_cap_mode = Line2D.LINE_CAP_ROUND
	base_renderer.end_cap_mode = Line2D.LINE_CAP_ROUND
	base_renderer.joint_mode = Line2D.LINE_JOINT_SHARP
	rope.render_modules = [base_renderer]
	rope.z_index = Z_CABLE
	add_child(rope)

	# Current overlay: a separate Line2D module (its own additive material), drawn on top only when
	# powered; an animated colour+alpha gradient runs the "current" along the braid.
	var overlay := CRopeLine2DRenderMod.new()
	overlay.width = 11.0 * SCALE
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	overlay.material = add_mat
	var pulse := Gradient.new() # resized to one stop per cable point in _animate_wire
	overlay.gradient = pulse

	var anchor_outlet := CRopeAnchor.new()
	anchor_outlet.index = data.get_count() - 1 # box = last point
	anchor_outlet.node_path = rope.get_path_to(outlet)
	anchor_outlet.pull_strength = 0.0
	anchor_outlet.collision_resolve = false

	var anchor_plug := CRopeAnchor.new()
	anchor_plug.index = 0 # plug = first point
	anchor_plug.node_path = rope.get_path_to(plug)
	anchor_plug.offset_angle = 180.0
	anchor_plug.offset_distance = 52.0 * SCALE
	anchor_plug.pull_strength = 1200.0 * SCALE
	anchor_plug.pull_damping = 0.6
	anchor_plug.collision_resolve = false

	rope.anchors = [anchor_outlet, anchor_plug]

	if _dev_tools:
		_dev_tools.register_debug_rope(rope)

	_wires.append({
		"plug": plug,
		"color": config.color,
		"rope": rope,
		"box_anchor": anchor_outlet,
		"bezel": bezel,
		"flash": 0.0,
		"base_renderer": base_renderer,
		"overlay": overlay,
		"gradient": pulse,
		"phase": 0.0,
		"speed": 0.7,
		"indicator": _indicators[index],
		"powered": false,
		"seated": null,
		"joints": [],
	})

func _spawn_plug(pos: Vector2, color: Color) -> RigidBody2D:
	var plug := RigidBody2D.new()
	plug.position = pos
	plug.mass = 0.6
	plug.linear_damp = 0.6
	plug.angular_damp = 5.0
	plug.collision_layer = 2 # plug
	plug.collision_mask = 1 | 4 # walls/obstacles + sockets
	plug.z_index = Z_TOP
	# Wide body collider, stopped by the socket block
	var body_col := CollisionShape2D.new()
	var body_shape := RectangleShape2D.new()
	body_shape.size = Vector2(PIN_FACE_X - BODY_BACK_X, 76.0 * SCALE)
	body_col.shape = body_shape
	body_col.position = Vector2((PIN_FACE_X + BODY_BACK_X) * 0.5, 0.0)
	plug.add_child(body_col)
	# Two thin pin colliders that fit into the slots
	for pin_y in [PIN_DY, -PIN_DY]:
		var pin_col := CollisionShape2D.new()
		var pin_shape := RectangleShape2D.new()
		pin_shape.size = Vector2(PIN_LEN, PIN_HALF_W * 2.0)
		pin_col.shape = pin_shape
		pin_col.position = Vector2(PIN_FACE_X + PIN_LEN * 0.5, pin_y)
		plug.add_child(pin_col)
	var body := Polygon2D.new()
	body.polygon = _plug_body_polygon()
	body.color = color
	plug.add_child(body)
	var face := Polygon2D.new()
	face.polygon = PackedVector2Array([Vector2(PIN_FACE_X - 8.0 * SCALE, -34.0 * SCALE), Vector2(PIN_FACE_X, -34.0 * SCALE), Vector2(PIN_FACE_X, 34.0 * SCALE), Vector2(PIN_FACE_X - 8.0 * SCALE, 34.0 * SCALE)])
	face.color = color.darkened(0.4)
	plug.add_child(face)
	for pin_y in [PIN_DY, -PIN_DY]:
		var pin := Polygon2D.new()
		pin.polygon = PackedVector2Array([
			Vector2(PIN_FACE_X, pin_y - PIN_HALF_W), Vector2(PIN_FACE_X + PIN_LEN, pin_y - PIN_HALF_W),
			Vector2(PIN_FACE_X + PIN_LEN, pin_y + PIN_HALF_W), Vector2(PIN_FACE_X, pin_y + PIN_HALF_W),
		])
		pin.color = Color(0.72, 0.64, 0.22)
		plug.add_child(pin)
		var tip := Polygon2D.new()
		tip.polygon = PackedVector2Array([
			Vector2(PIN_FACE_X + PIN_LEN - 7.0 * SCALE, pin_y - PIN_HALF_W), Vector2(PIN_FACE_X + PIN_LEN, pin_y - PIN_HALF_W),
			Vector2(PIN_FACE_X + PIN_LEN, pin_y + PIN_HALF_W), Vector2(PIN_FACE_X + PIN_LEN - 7.0 * SCALE, pin_y + PIN_HALF_W),
		])
		tip.color = Color(0.5, 0.45, 0.16)
		plug.add_child(tip)
	add_child(plug)
	return plug

## Plug outline: flat front face (pins side), rounded back (cable side).
func _plug_body_polygon() -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(Vector2(PIN_FACE_X, -38.0 * SCALE))
	var steps := 14
	for i in range(steps + 1):
		var a := deg_to_rad(270.0 - 180.0 * float(i) / float(steps))
		pts.append(Vector2(-14.0 * SCALE, 0.0) + Vector2(cos(a), sin(a)) * 38.0 * SCALE)
	pts.append(Vector2(PIN_FACE_X, 38.0 * SCALE))
	return pts

func _spawn_socket(config: Dictionary) -> StaticBody2D:
	# Local frame: +X points into the socket. The body is a disc whose mouth (-X) side is sliced to a
	# flat face at x = 0; two slots are cut into that face. Only the plug's pins fit; the wide body is
	# stopped by the solid parts above, below and between the slots.
	var socket := StaticBody2D.new()
	socket.position = config.socket
	socket.rotation = deg_to_rad(config.socket_rot)
	socket.collision_layer = 1 | 4 # 1 so cables collide with it, 4 so the plug detects it
	socket.collision_mask = 0
	socket.z_index = Z_TOP # draws above the cables; draggable via DevTools (not in the no_drag group)
	var r := SOCKET_RADIUS
	var cx := SOCKET_RADIUS - SOCKET_FLAT_DEPTH # disc centre, behind the flat mouth face
	var a_flat := acos(-cx / r)                 # disc angle that lands on the flat face (x = 0)
	var slot_top := PIN_DY + SLOT_HALF_H
	var slot_bottom := PIN_DY - SLOT_HALF_H
	var a_top := asin(slot_top / r)             # disc angle that lands on the slot-top line
	# Visual: the D-shaped disc, then two dark slots cut into the flat face.
	var body := Polygon2D.new()
	body.polygon = _socket_arc(cx, r, -a_flat, a_flat, 28)
	body.color = config.color
	socket.add_child(body)
	for sy in [PIN_DY, -PIN_DY]:
		var slot_vis := Polygon2D.new()
		slot_vis.polygon = PackedVector2Array([Vector2(-3.0 * SCALE, sy - SLOT_HALF_H), Vector2(SLOT_DEPTH, sy - SLOT_HALF_H), Vector2(SLOT_DEPTH, sy + SLOT_HALF_H), Vector2(-3.0 * SCALE, sy + SLOT_HALF_H)])
		slot_vis.color = Color(0.06, 0.06, 0.08)
		socket.add_child(slot_vis)
	# Collision: four convex pieces tiling the disc minus the two slots, above, below and behind the
	# slots (each following the disc edge), plus the tooth between them.
	var top := PackedVector2Array([Vector2(0, slot_top)])
	top.append_array(_socket_arc(cx, r, a_flat, a_top, 10))
	_add_socket_hull(socket, top)
	var bottom := PackedVector2Array([Vector2(0, -slot_top)])
	bottom.append_array(_socket_arc(cx, r, -a_flat, -a_top, 10))
	_add_socket_hull(socket, bottom)
	var back := PackedVector2Array([Vector2(SLOT_DEPTH, slot_top), Vector2(SLOT_DEPTH, -slot_top)])
	back.append_array(_socket_arc(cx, r, -a_top, a_top, 10))
	_add_socket_hull(socket, back)
	_add_socket_box(socket, Rect2(0, -slot_bottom, SLOT_DEPTH, 2.0 * slot_bottom)) # tooth between the slots
	# Small detectors sunk deep in each slot. Only a fully inserted pin can reach them.
	for i in 2:
		var sy: float = PIN_DY if i == 0 else -PIN_DY
		var area := Area2D.new()
		area.name = "Slot%d" % i
		area.position = Vector2(38.0 * SCALE, sy)
		area.collision_layer = 0
		area.collision_mask = 2 # plug
		var acol := CollisionShape2D.new()
		var ashape := RectangleShape2D.new()
		ashape.size = Vector2(10, 12) * SCALE
		acol.shape = ashape
		area.add_child(acol)
		socket.add_child(area)
	add_child(socket)
	return socket

## Points along the socket disc (centre (cx, 0), radius r) from angle a_from to a_to.
func _socket_arc(cx: float, r: float, a_from: float, a_to: float, steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(a_from, a_to, float(i) / float(steps))
		pts.append(Vector2(cx + cos(a) * r, sin(a) * r))
	return pts

func _add_socket_hull(body: StaticBody2D, points: PackedVector2Array) -> void:
	var col := CollisionShape2D.new()
	var shape := ConvexPolygonShape2D.new()
	shape.set_point_cloud(points) # builds the convex hull; winding doesn't matter
	col.shape = shape
	body.add_child(col)

func _add_socket_box(body: StaticBody2D, rect: Rect2) -> void:
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	col.shape = shape
	col.position = rect.position + rect.size * 0.5
	body.add_child(col)

func _build_top_bar() -> void:
	var w := 1920.0
	var bar := Polygon2D.new()
	bar.polygon = PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, BAR_HEIGHT), Vector2(0, BAR_HEIGHT)])
	bar.vertex_colors = PackedColorArray([
		Color(0.17, 0.18, 0.22), Color(0.17, 0.18, 0.22),
		Color(0.10, 0.10, 0.12), Color(0.10, 0.10, 0.12),
	])
	add_child(bar)
	var rim := Polygon2D.new()
	rim.polygon = PackedVector2Array([Vector2(0, BAR_HEIGHT - 5.0 * SCALE), Vector2(w, BAR_HEIGHT - 5.0 * SCALE), Vector2(w, BAR_HEIGHT), Vector2(0, BAR_HEIGHT)])
	rim.color = Color(0.32, 0.34, 0.4)
	add_child(rim)
	var x := 320.0
	for config in WIRES:
		_build_indicator(Vector2(x, BAR_HEIGHT * 0.5), config.color)
		x += 130.0
	_build_bulb(Vector2(1560, 95.0 * SCALE))

func _build_indicator(pos: Vector2, color: Color) -> void:
	var ring := Polygon2D.new()
	ring.polygon = _circle_polygon(30.0 * SCALE)
	ring.position = pos
	ring.color = Color(0.05, 0.05, 0.07)
	add_child(ring)
	var glow := Sprite2D.new()
	glow.texture = _make_radial_texture(color)
	glow.position = pos
	glow.scale = Vector2.ONE * 0.7 * SCALE
	glow.modulate = Color(1, 1, 1, 0.0)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add_mat
	add_child(glow)
	var core := Polygon2D.new()
	core.polygon = _circle_polygon(20.0 * SCALE)
	core.position = pos
	core.color = color.darkened(0.72)
	add_child(core)
	_indicators.append({"core": core, "glow": glow, "color": color})

func _light_indicator(indicator: Dictionary) -> void:
	indicator.core.color = indicator.color
	indicator.glow.modulate = Color(1, 1, 1, 0.9)

func _build_bulb(pos: Vector2) -> void:
	_bulb_glow = Sprite2D.new()
	_bulb_glow.texture = _make_radial_texture(Color(1.0, 0.85, 0.5))
	_bulb_glow.position = pos
	_bulb_glow.scale = Vector2.ONE * 2.0 * SCALE
	_bulb_glow.modulate = Color(1, 1, 1, 0.04)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_bulb_glow.material = add_mat
	add_child(_bulb_glow)
	var base := Polygon2D.new()
	base.polygon = PackedVector2Array([
		Vector2(-16 * SCALE, -62 * SCALE), Vector2(16 * SCALE, -62 * SCALE), Vector2(13 * SCALE, -38 * SCALE), Vector2(-13 * SCALE, -38 * SCALE),
	])
	base.position = pos
	base.color = Color(0.5, 0.5, 0.52)
	add_child(base)
	_bulb_core = Polygon2D.new()
	_bulb_core.polygon = _circle_polygon(40.0 * SCALE)
	_bulb_core.position = pos
	_bulb_core.color = Color(0.3, 0.3, 0.32)
	add_child(_bulb_core)

func _make_radial_texture(color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	gradient.colors = PackedColorArray([
		color,
		Color(color.r, color.g, color.b, 0.3),
		Color(color.r, color.g, color.b, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 256
	texture.height = 256
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(0.5, 0.0)
	return texture

func _circle_polygon(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		points.append(Vector2(cos(a), sin(a)) * radius)
	return points
