class_name WorldNotice
extends Node

## Names a world's rule once, shortly after a match on it starts, in the HUD's notice corner: for rules
## that are always on (Rimefall's ice) and so have no warning of their own to teach them.

@export var title: String = ""
@export var detail: String = ""
@export var color: Color = Color.WHITE
@export var delay: float = 1.6


func _ready() -> void:
	if title == "":
		return
	await get_tree().create_timer(delay, false).timeout
	if is_inside_tree():
		HudToasts.notify(title, detail, color, &"")
