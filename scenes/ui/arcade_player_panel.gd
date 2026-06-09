class_name ArcadePlayerPanel
extends Control

const AMMO_BULLET_ICON_SCENE: PackedScene = preload("res://scenes/ui/ammo_bullet_icon.tscn")

@export var player_slot: int = GameSettings.PLAYER_ONE_SLOT
@export var right_aligned: bool = false

@onready var _backplate: Polygon2D = %Backplate
@onready var _inner_plate: Polygon2D = %InnerPlate
@onready var _accent_edge: Polygon2D = %AccentEdge
@onready var _bottom_edge: ColorRect = %BottomEdge
@onready var _rows: VBoxContainer = $Rows
@onready var _player_label: Label = %PlayerLabel
@onready var _ammo_status_label: Label = %AmmoStatusLabel
@onready var _ammo_icons: HBoxContainer = %AmmoIcons
@onready var _block_state_label: Label = %BlockStateLabel
@onready var _block_bar: ProgressBar = %BlockBar
@onready var _health_value_label: Label = %HealthValueLabel
@onready var _health_bar: ProgressBar = %HealthBar

var _player: Player = null
var _health: HealthComponent = null
var _gun: Node = null
var _block_fill_style: StyleBoxFlat = null
var _health_fill_style: StyleBoxFlat = null
var _last_health: int = -1
var _last_max_ammo: int = -1
var _punch_tween: Tween = null


func _ready() -> void:
	_block_fill_style = _duplicate_flat_style(_block_bar, "fill")
	_health_fill_style = _duplicate_flat_style(_health_bar, "fill")
	_apply_alignment()


func bind_player(player: Player) -> void:
	_player = player
	_health = null
	_gun = null
	_last_health = -1
	_last_max_ammo = -1

	if _player == null:
		hide()
		return

	_health = _player.health_component
	_gun = _player.get_node_or_null("Gun")
	show()
	_refresh_identity()
	_refresh_values(true)


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		hide()
		return
	_refresh_values(false)


func _refresh_identity() -> void:
	var tint: Color = _player.get_visual_tint()
	var display_name: String = "PLAYER %d" % player_slot
	if NetworkSession.is_steam_match_active():
		display_name = OnlineMatch.get_player_color_name(player_slot).to_upper()

	_player_label.text = display_name
	_player_label.add_theme_color_override("font_color", tint.lightened(0.18))
	_accent_edge.color = tint
	_bottom_edge.color = tint
	_backplate.color = Color(tint.darkened(0.48), 0.97)
	_inner_plate.color = Color(tint.darkened(0.72), 0.94)


func _refresh_values(force: bool) -> void:
	_refresh_identity()
	_refresh_health(force)
	_refresh_block()
	_refresh_ammo()


func _refresh_health(force: bool) -> void:
	if _health == null:
		_health_bar.value = 0.0
		_health_value_label.text = "--"
		return

	var current_health: int = _health.health
	var max_health: int = maxi(_health.max_health, 1)
	var health_ratio: float = clampf(float(current_health) / float(max_health), 0.0, 1.0)
	_health_bar.value = health_ratio * 100.0
	_health_value_label.text = "%d / %d" % [current_health, max_health]

	if _health_fill_style != null:
		if health_ratio <= 0.25:
			_health_fill_style.bg_color = Color("#ff3b45")
		elif health_ratio <= 0.55:
			_health_fill_style.bg_color = Color("#ffb52e")
		else:
			_health_fill_style.bg_color = Color("#67e85f")

	if not force and _last_health >= 0 and current_health < _last_health:
		_play_damage_punch()
	_last_health = current_health


func _refresh_block() -> void:
	if _player == null:
		return

	var ratio: float = _player.get_block_cooldown_ratio()
	_block_bar.value = ratio * 100.0
	if _player.is_blocking():
		_block_state_label.text = "ACTIVE"
		_block_state_label.add_theme_color_override("font_color", Color("#8ff4ff"))
		if _block_fill_style != null:
			_block_fill_style.bg_color = Color("#8ff4ff")
	elif ratio >= 0.999:
		_block_state_label.text = "READY"
		_block_state_label.add_theme_color_override("font_color", Color("#35d9f3"))
		if _block_fill_style != null:
			_block_fill_style.bg_color = Color("#35d9f3")
	else:
		_block_state_label.text = "CHARGING %d%%" % int(roundf(ratio * 100.0))
		_block_state_label.add_theme_color_override("font_color", Color("#ffd365"))
		if _block_fill_style != null:
			_block_fill_style.bg_color = Color("#218fa8")


func _refresh_ammo() -> void:
	if _gun == null or not _gun.has_method("get_current_ammo"):
		_ammo_status_label.text = "NO AMMO"
		_ammo_status_label.show()
		_ammo_icons.hide()
		return

	var current_ammo: int = int(_gun.call("get_current_ammo"))
	var max_ammo: int = int(_gun.call("get_max_ammo"))
	var reloading: bool = bool(_gun.call("is_reloading"))
	if max_ammo != _last_max_ammo:
		_rebuild_ammo_icons(max_ammo)

	if reloading:
		_ammo_status_label.text = "RELOAD"
		_ammo_status_label.show()
	else:
		_ammo_status_label.hide()

	_ammo_icons.show()
	for icon_index in range(_ammo_icons.get_child_count()):
		var icon: AmmoBulletIcon = _ammo_icons.get_child(icon_index) as AmmoBulletIcon
		if icon != null:
			icon.set_loaded(icon_index < current_ammo and not reloading)


func _rebuild_ammo_icons(max_ammo: int) -> void:
	for child in _ammo_icons.get_children():
		child.queue_free()
	for icon_index in range(maxi(max_ammo, 0)):
		var icon: AmmoBulletIcon = AMMO_BULLET_ICON_SCENE.instantiate() as AmmoBulletIcon
		if icon != null:
			_ammo_icons.add_child(icon)
	_last_max_ammo = max_ammo


func _play_damage_punch() -> void:
	if _punch_tween != null and _punch_tween.is_valid():
		_punch_tween.kill()
	pivot_offset = size * GameSettings.HALF
	scale = Vector2(1.035, 1.035)
	modulate = Color(1.0, 0.76, 0.76, 1.0)
	_punch_tween = create_tween()
	_punch_tween.set_parallel(true)
	_punch_tween.tween_property(self, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_punch_tween.tween_property(self, "modulate", Color.WHITE, 0.14)


func _apply_alignment() -> void:
	if right_aligned:
		_backplate.polygon = PackedVector2Array([
			Vector2(0.0, 62.0),
			Vector2(65.0, 12.0),
			Vector2(410.0, 12.0),
			Vector2(410.0, 122.0),
			Vector2(0.0, 122.0),
		])
		_inner_plate.polygon = PackedVector2Array([
			Vector2(11.0, 67.0),
			Vector2(73.0, 20.0),
			Vector2(410.0, 20.0),
			Vector2(410.0, 114.0),
			Vector2(11.0, 114.0),
		])
		_accent_edge.polygon = PackedVector2Array([
			Vector2(0.0, 62.0),
			Vector2(65.0, 12.0),
			Vector2(410.0, 12.0),
			Vector2(410.0, 20.0),
			Vector2(68.0, 20.0),
			Vector2(0.0, 70.0),
		])
		_rows.offset_left = 73.0
		_rows.offset_right = 390.0
		_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_health_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	else:
		_rows.offset_left = 20.0
		_rows.offset_right = 338.0
		_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_health_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _duplicate_flat_style(control: Control, style_name: StringName) -> StyleBoxFlat:
	var source_style: StyleBox = control.get_theme_stylebox(style_name)
	if source_style is StyleBoxFlat:
		var flat_style: StyleBoxFlat = (source_style as StyleBoxFlat).duplicate() as StyleBoxFlat
		control.add_theme_stylebox_override(style_name, flat_style)
		return flat_style
	return null
