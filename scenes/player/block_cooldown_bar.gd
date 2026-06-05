class_name BlockCooldownBar
extends Node2D

@export var bar_width: float = GameSettings.BLOCK_COOLDOWN_BAR_WIDTH
@export var bar_height: float = GameSettings.BLOCK_COOLDOWN_BAR_HEIGHT
@export var offset_y: float = GameSettings.BLOCK_COOLDOWN_BAR_OFFSET_Y

@onready var _player: Player = get_parent() as Player


func _ready() -> void:
	var mat: CanvasItemMaterial = CanvasItemMaterial.new()
	mat.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = mat
	hide()


func _process(_delta: float) -> void:
	if _player == null or not _player.is_block_cooling_down():
		hide()
		return

	show()
	queue_redraw()


func _draw() -> void:
	if _player == null:
		return

	var ratio: float = _player.get_block_cooldown_ratio()
	var pos: Vector2 = Vector2(-bar_width * GameSettings.HALF, offset_y)
	draw_rect(Rect2(pos, Vector2(bar_width, bar_height)), GameSettings.BLOCK_COOLDOWN_BAR_BACKGROUND_COLOR)
	draw_rect(Rect2(pos, Vector2(bar_width * ratio, bar_height)), GameSettings.BLOCK_COOLDOWN_BAR_FILL_COLOR)
	draw_rect(
		Rect2(pos, Vector2(bar_width, bar_height)),
		GameSettings.BLOCK_COOLDOWN_BAR_BORDER_COLOR,
		false,
		GameSettings.BLOCK_COOLDOWN_BAR_BORDER_WIDTH
	)
