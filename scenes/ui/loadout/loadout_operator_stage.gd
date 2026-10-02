class_name LoadoutOperatorStage
extends Control

## The operator on a lit pedestal: spotlight, team-coloured backglow, slow dust in the light and the three
## armor sockets along the bottom with callouts to the body. Armor can be dropped anywhere on the stage;
## while dragging, the matching socket lights up and a hologram of the piece appears on the character.

signal armor_dropped(item: ArmorItemData)
signal reward_dropped(payload: Dictionary)
signal armor_removed(category: StringName)
signal slot_selected(category: StringName)
signal slot_inspected(category: StringName)

const SLOTS: Array[StringName] = [&"shield", &"vest", &"boots"]
const CHIP_WIDTH: float = 128.0
const PUPPET_SCALE: float = 0.7

var _puppet: LoadoutOperatorPuppet = null
var _overlay: Control = null
var _under: Control = null
var _chips: Dictionary = {}
var _equipped: Dictionary = {}
var _accent: Color = Color.WHITE
var _time: float = 0.0
var _drag_category: StringName = &""
var _drag_item: ArmorItemData = null
var _drag_over: bool = false
var _motes: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _name_label: Label = null
var _caption: Label = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_accent = LoadoutStyle.local_accent()
	_under = Control.new()
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.draw.connect(_draw_under)
	add_child(_under)
	_puppet = LoadoutOperatorPuppet.new()
	_puppet.scale = Vector2.ONE * PUPPET_SCALE
	add_child(_puppet)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_caption = LoadoutStyle.caption("", LoadoutStyle.TEXT_MUTED, 10)
	add_child(_caption)
	_name_label = LoadoutStyle.label(UiStyle.player_name(ExtensionInventory.get_local_player_slot()).to_upper(), UiStyle.FONT_DISPLAY, 16, LoadoutStyle.TEXT)
	add_child(_name_label)
	for category in SLOTS:
		var chip: LoadoutSocketChip = LoadoutSocketChip.new()
		chip.slot = category
		chip.custom_minimum_size = Vector2(CHIP_WIDTH, LoadoutSocketChip.CHIP_SIZE.y)
		chip.size = chip.custom_minimum_size
		chip.drop_owner = self
		chip.inspected.connect(func(_chip: LoadoutSocketChip) -> void: slot_inspected.emit(category))
		chip.remove_requested.connect(func(removed: StringName) -> void: armor_removed.emit(removed))
		chip.selected.connect(func(picked: StringName) -> void: slot_selected.emit(picked))
		add_child(chip)
		_chips[category] = chip
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	for index in range(14):
		_motes.append({"x": rng.randf(), "y": rng.randf(), "speed": rng.randf_range(0.015, 0.04), "phase": rng.randf() * TAU, "size": rng.randf_range(0.8, 1.8)})
	resized.connect(_layout)
	_layout()


func get_chip(category: StringName) -> LoadoutSocketChip:
	return _chips.get(category, null)


func set_weapon(config: Dictionary, animate: bool) -> void:
	_puppet.set_weapon(config, animate)


func set_armor(equipped: Dictionary, animate: bool) -> void:
	for category in SLOTS:
		var item: ArmorItemData = equipped.get(category, null) as ArmorItemData
		var before: ArmorItemData = _equipped.get(category, null) as ArmorItemData
		var changed: bool = item != before or not _equipped.has(category)
		(_chips[category] as LoadoutSocketChip).set_item(item, animate and changed)
		if changed:
			_puppet.set_armor(category, item, animate)
			if animate:
				_burst(category, 12 if item != null else 5)
	_equipped = equipped.duplicate()


func flash_slot(category: StringName) -> void:
	var chip: LoadoutSocketChip = _chips.get(category, null)
	if chip != null:
		chip.highlight = 1.0
		chip.set_process(true)


func _layout() -> void:
	if _puppet == null:
		return
	_overlay.size = size
	_under.size = size
	var chip_y: float = size.y - LoadoutSocketChip.CHIP_SIZE.y - 10.0
	var gap: float = 8.0
	var chip_width: float = floorf((size.x - 20.0 - gap * 2.0) / 3.0)
	for index in range(SLOTS.size()):
		var chip: Control = _chips[SLOTS[index]]
		chip.custom_minimum_size = Vector2(chip_width, LoadoutSocketChip.CHIP_SIZE.y)
		chip.size = chip.custom_minimum_size
		chip.position = Vector2(10.0 + float(index) * (chip_width + gap), chip_y)
	_puppet.position = Vector2(size.x * 0.44, chip_y - 116.0 * PUPPET_SCALE - 26.0)
	_caption.position = Vector2(16.0, 34.0)
	_name_label.position = Vector2(16.0, 12.0)
	queue_redraw()


func _pedestal_center() -> Vector2:
	return _puppet.position + Vector2(0.0, 122.0 * PUPPET_SCALE)


# --- Drag & drop -----------------------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var item: ArmorItemData = _drag_item_of(data)
	var accepted: bool = item != null and StringName(str((data as Dictionary).get("source", ""))) != &"slot"
	_set_drag_over(accepted)
	return accepted


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	_set_drag_over(false)
	if StringName(str(payload.get("type", ""))) == &"round_reward":
		reward_dropped.emit(payload)
		return
	var item: ArmorItemData = payload.get("item", null) as ArmorItemData
	if item != null:
		armor_dropped.emit(item)


func _drag_item_of(data: Variant) -> ArmorItemData:
	if not (data is Dictionary):
		return null
	var payload: Dictionary = data
	var type: StringName = StringName(str(payload.get("type", "")))
	if type == &"round_reward" and StringName(str(payload.get("reward_type", ""))) != RoundRewardInventory.REWARD_ARMOR:
		return null
	if type != &"round_reward" and type != &"armor_item":
		return null
	return payload.get("item", null) as ArmorItemData


func _set_drag_over(over: bool) -> void:
	if _drag_over == over:
		return
	_drag_over = over
	_puppet.set_ghost(_drag_category, _drag_item if over else null)
	if over:
		AudioDirector.play(&"ui_hover", -6.0, 0.8)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		_drag_item = _drag_item_of(get_viewport().gui_get_drag_data())
		_drag_category = _drag_item.category if _drag_item != null else &""
		for category in SLOTS:
			(_chips[category] as LoadoutSocketChip).set_drag_state(_drag_item != null, category == _drag_category)
	elif what == NOTIFICATION_DRAG_END:
		_set_drag_over(false)
		_drag_item = null
		_drag_category = &""
		for category in SLOTS:
			(_chips[category] as LoadoutSocketChip).set_drag_state(false, false)


# --- Animation & drawing ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if _drag_over and get_viewport().gui_is_dragging() and not get_global_rect().has_point(get_global_mouse_position()):
		_set_drag_over(false)
	for index in range(_sparks.size() - 1, -1, -1):
		var spark: Dictionary = _sparks[index]
		spark["life"] = float(spark["life"]) - delta
		if float(spark["life"]) <= 0.0:
			_sparks.remove_at(index)
			continue
		spark["v"] = (spark["v"] as Vector2) * exp(-3.5 * delta) + Vector2(0.0, 200.0 * delta)
		spark["p"] = (spark["p"] as Vector2) + (spark["v"] as Vector2) * delta
	_overlay.queue_redraw()
	_under.queue_redraw()


func _burst(category: StringName, count: int) -> void:
	var origin: Vector2 = _puppet.position + _puppet.get_anchor_position(category) * PUPPET_SCALE
	for index in range(count):
		var direction: Vector2 = Vector2.UP.rotated(randf_range(-1.6, 1.6))
		_sparks.append({
			"p": origin + direction * randf_range(4.0, 14.0),
			"v": direction * randf_range(70.0, 190.0),
			"life": randf_range(0.3, 0.55),
			"max": 0.55,
			"c": _accent.lerp(Color.WHITE, randf() * 0.7),
		})


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(LoadoutStyle.flat(Color(1, 1, 1, 0.022), 6), rect)
	var pedestal: Vector2 = _pedestal_center()
	var light_top: Vector2 = Vector2(pedestal.x, 0.0)
	draw_polygon(
		PackedVector2Array([light_top + Vector2(-30.0, 0.0), light_top + Vector2(30.0, 0.0), pedestal + Vector2(100.0, 0.0), pedestal + Vector2(-100.0, 0.0)]),
		PackedColorArray([Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)])
	)
	LoadoutStyle.draw_glow(self, pedestal + Vector2(0.0, -70.0), Vector2(140.0, 105.0), Color(_accent.r, _accent.g, _accent.b, 0.08))
	LoadoutStyle.draw_glow(self, pedestal + Vector2(0.0, 12.0), Vector2(118.0, 15.0), Color(0.0, 0.0, 0.0, 0.6))
	var lip: PackedVector2Array = PackedVector2Array()
	for index in range(21):
		var angle: float = PI * float(index) / 20.0
		lip.append(pedestal + Vector2(cos(angle) * 88.0, sin(angle) * 14.0 + 7.0))
	for index in range(20, -1, -1):
		var angle: float = PI * float(index) / 20.0
		lip.append(pedestal + Vector2(cos(angle) * 88.0, sin(angle) * 14.0))
	draw_colored_polygon(lip, Color(0.06, 0.065, 0.075, 1.0))
	draw_colored_polygon(_ellipse(pedestal, Vector2(88.0, 14.0), 40), Color(0.13, 0.138, 0.155, 1.0))
	draw_colored_polygon(_ellipse(pedestal, Vector2(66.0, 10.0), 36), Color(0.105, 0.112, 0.128, 1.0))
	draw_polyline(_ellipse_arc(pedestal, Vector2(88.0, 14.0), PI * 0.04, PI * 0.96, 30), Color(_accent.r, _accent.g, _accent.b, 0.7), 1.5, true)


func _draw_under() -> void:
	var pedestal: Vector2 = _pedestal_center()
	var pulse: float = fmod(_time * 0.35, 1.0)
	_under.draw_polyline(_ellipse(pedestal, Vector2(66.0, 10.0) * (0.35 + pulse * 0.65), 40), Color(1, 1, 1, (1.0 - pulse) * 0.18), 1.0, true)


func _draw_overlay() -> void:
	var pedestal: Vector2 = _pedestal_center()
	for mote in _motes:
		var t: float = fmod(float(mote["y"]) - _time * float(mote["speed"]), 1.0)
		if t < 0.0:
			t += 1.0
		var x: float = pedestal.x + (float(mote["x"]) - 0.5) * 150.0 * (1.0 - t * 0.6) + sin(_time * 0.7 + float(mote["phase"])) * 6.0
		var y: float = pedestal.y - t * pedestal.y
		var alpha: float = sin(t * PI) * 0.22
		_overlay.draw_circle(Vector2(x, y), float(mote["size"]), Color(1.0, 0.97, 0.9, alpha), true, -1.0, true)
	for category in SLOTS:
		var chip: LoadoutSocketChip = _chips[category]
		var anchor: Vector2 = chip.position + Vector2(chip.size.x * 0.5, 0.0)
		var target: Vector2 = _puppet.position + _puppet.get_anchor_position(category) * PUPPET_SCALE
		var active: bool = _drag_category == category
		var color: Color = Color(1, 1, 1, 0.1)
		if active:
			color = Color(LoadoutStyle.ACCENT.r, LoadoutStyle.ACCENT.g, LoadoutStyle.ACCENT.b, 0.55 + 0.35 * sin(_time * 7.0))
		var elbow: Vector2 = Vector2(anchor.x, lerpf(anchor.y, target.y, 0.5))
		_overlay.draw_polyline(PackedVector2Array([anchor, elbow, target]), color, 1.0, true)
		var installed: bool = _equipped.get(category, null) != null
		_overlay.draw_circle(target, 3.0 if not active else 4.5 + sin(_time * 7.0), color if (not installed or active) else Color(1, 1, 1, 0.55), true, -1.0, true)
	for spark in _sparks:
		var life: float = float(spark["life"]) / float(spark["max"])
		var p: Vector2 = spark["p"]
		var c: Color = spark["c"]
		_overlay.draw_circle(p, 1.4 * life + 0.4, Color(c.r, c.g, c.b, life), true, -1.0, true)


func _ellipse(center: Vector2, radius: Vector2, segments: int) -> PackedVector2Array:
	return _ellipse_arc(center, radius, 0.0, TAU, segments)


func _ellipse_arc(center: Vector2, radius: Vector2, from: float, to: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for index in range(segments + 1):
		var angle: float = lerpf(from, to, float(index) / float(segments))
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points
