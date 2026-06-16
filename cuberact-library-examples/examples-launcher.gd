extends Control

## Scene launcher. Displays example scenes from a static registry.
## DirAccess scanning doesn't work in exported .pck builds, so scenes are listed explicitly.
## When adding a new example, add it to _SCENE_REGISTRY below.

const DevTools = preload("res://cuberact-library-examples/commons/dev_tools.gd")

const _SCENE_REGISTRY := [
	["CRope2D", "res://cuberact-library-examples/CRope2D/e01-jellyfish.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e02-plug_the_wires.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e03-kite.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e04-growing_sunflowers.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e05-firefly_meadow.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e06-gravity_force_module.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e07-magnet_force_module.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e08-simplify_line_module.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e09-subdivide_line_module.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e10-custom_render_module.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e11-debug_render_module.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e12-break_module.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e13-simple_pendulum.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e14-playground.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e15-grappling_hook.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e16-stress_test.tscn"],
	["CRope2D", "res://cuberact-library-examples/CRope2D/e17-grand_curtain.tscn"],
]

@onready var scene_list: VBoxContainer = %SceneList
@onready var label_version: Label = %LabelVersion

func _ready() -> void:
	DevTools.window_setup()
	label_version.text = "v" + CuberactLib.get_version()
	_populate_scene_list()

func _populate_scene_list() -> void:
	for entry in _SCENE_REGISTRY:
		var path: String = entry[1]
		var display := path.get_file().get_basename()
		_add_scene_button({"display": display, "path": path})

func _add_scene_button(scene_entry: Dictionary) -> void:
	var button := Button.new()
	button.text = "   " + scene_entry.display
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 26)
	var base_style := StyleBoxFlat.new()
	base_style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	base_style.content_margin_top = 8
	base_style.content_margin_bottom = 8
	button.add_theme_stylebox_override("normal", base_style)
	button.add_theme_stylebox_override("pressed", base_style)
	button.add_theme_stylebox_override("focus", base_style)
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.2, 0.4, 0.7, 0.3)
	hover_style.content_margin_top = 8
	hover_style.content_margin_bottom = 8
	button.add_theme_stylebox_override("hover", hover_style)
	var path: String = scene_entry.path
	button.pressed.connect(func(): get_tree().change_scene_to_file(path))
	scene_list.add_child(button)
