# attach this script to MapBorder
extends Node2D

# === SETTINGS ===
@export var warn_distance: float = 50.0
@export var line_length: float = 60.0      # small fixed segment
@export var line_thickness: float = 5.0
@export var line_color: Color = Color(1, 0, 0, 0.85)

var _player: Node2D
var _lines: Dictionary = {}

func _ready() -> void:
	_player = get_node("../Player")
	for side in ["left", "right", "top", "bottom"]:
		var cr := ColorRect.new()
		cr.color = line_color
		cr.visible = false
		cr.z_index = 100
		add_child(cr)
		_lines[side] = cr

func _process(_delta: float) -> void:
	if not _player:
		return

	# always up to date, works with any resolution
	var vp   := get_viewport_rect()
	var left   := vp.position.x
	var right  := vp.position.x + vp.size.x
	var top    := vp.position.y
	var bottom := vp.position.y + vp.size.y

	var px := _player.global_position.x
	var py := _player.global_position.y

	_update("left",   px - left   < warn_distance and px > left,   left,   py, true)
	_update("right",  right - px  < warn_distance and px < right,  right,  py, true)
	_update("top",    py - top    < warn_distance and py > top,    px, top,    false)
	_update("bottom", bottom - py < warn_distance and py < bottom, px, bottom, false)

func _update(side: String, near: bool, x: float, y: float, vertical: bool) -> void:
	var cr: ColorRect = _lines[side]
	cr.visible = near
	if not near:
		return

	if vertical:
		cr.size = Vector2(line_thickness, line_length)
		cr.position = Vector2(x - line_thickness / 2.0, y - line_length / 2.0)
	else:
		cr.size = Vector2(line_length, line_thickness)
		cr.position = Vector2(x - line_length / 2.0, y - line_thickness / 2.0)
