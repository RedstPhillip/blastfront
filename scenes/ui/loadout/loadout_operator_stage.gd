class_name LoadoutOperatorStage
extends Control

## The operator on the bench: the player's character on a low pedestal with a team-coloured backglow,
## and a column of three armor callouts (shield, vest, boots) tied to the body by leader lines. Armor can
## be dropped anywhere on the stage; while dragging, the matching callout lights up and a hologram of the
## piece appears on the character. Hovering armor in the locker shows the same hologram.

signal armor_dropped(item: ArmorItemData)
signal reward_dropped(payload: Dictionary)
signal armor_removed(category: StringName)
signal slot_selected(category: StringName)
signal slot_inspected(category: StringName)

const SLOTS: Array[StringName] = [&"shield", &"vest", &"boots"]
const PUPPET_SCALE: float = 0.72
const CALLOUT_WIDTH: float = 148.0
## Callout tops relative to the body centre.
const CALLOUT_TOPS: Dictionary = {&"shield": -76.0, &"vest": -10.0, &"boots": 80.0}

var _puppet: LoadoutOperatorPuppet = null
var _overlay: Control = null
var _chips: Dictionary = {}
var _equipped: Dictionary = {}
var _accent: Color = Color.WHITE
var _time: float = 0.0
var _drag_category: StringName = &""
var _drag_item: ArmorItemData = null
var _drag_over: bool = false
var _preview_item: ArmorItemData = null
var _sparks: Array[Dictionary] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_accent = LoadoutStyle.local_accent()
	_puppet = LoadoutOperatorPuppet.new()
	_puppet.scale = Vector2.ONE * PUPPET_SCALE
	add_child(_puppet)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	for category in SLOTS:
		var chip: LoadoutSocketChip = LoadoutSocketChip.new()
		chip.slot = category
		chip.align_right = true
		chip.custom_minimum_size = Vector2(CALLOUT_WIDTH, LoadoutSocketChip.CHIP_SIZE.y)
		chip.size = chip.custom_minimum_size
		chip.drop_owner = self
		chip.inspected.connect(func(_chip: LoadoutSocketChip) -> void: slot_inspected.emit(category))
		chip.remove_requested.connect(func(removed: StringName) -> void: armor_removed.emit(removed))
		chip.selected.connect(func(picked: StringName) -> void: slot_selected.emit(picked))
		add_child(chip)
		_chips[category] = chip
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
	if _preview_item != null and _equipped.get(_preview_item.category, null) == _preview_item:
		set_preview(null)


## Hologram of an armor piece the player is looking at in the locker (null clears).
func set_preview(item: ArmorItemData) -> void:
	if item != null and _equipped.get(item.category, null) == item:
		item = null
	if item == _preview_item:
		return
	_preview_item = item
	if not _drag_over:
		_puppet.set_ghost(item.category if item != null else &"", item)


func set_linked_slot(category: StringName) -> void:
	for key in SLOTS:
		(_chips[key] as LoadoutSocketChip).set_linked(key == category)


func flash_slot(category: StringName) -> void:
	var chip: LoadoutSocketChip = _chips.get(category, null)
	if chip != null:
		chip.highlight = 1.0
		chip.set_process(true)


func _layout() -> void:
	if _puppet == null:
		return
	_overlay.size = size
	var body_x: float = CALLOUT_WIDTH + 104.0
	_puppet.position = Vector2(body_x, size.y * 0.5 - 22.0)
	for category in SLOTS:
		(_chips[category] as Control).position = Vector2(0.0, _puppet.position.y + float(CALLOUT_TOPS[category]))
	queue_redraw()


func _pedestal_center() -> Vector2:
	return _puppet.position + Vector2(0.0, 124.0 * PUPPET_SCALE)


func _anchor(category: StringName) -> Vector2:
	return _puppet.position + _puppet.get_anchor_position(category) * PUPPET_SCALE


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
	if over:
		_puppet.set_ghost(_drag_category, _drag_item)
		AudioDirector.play(&"ui_hover", -6.0, 0.8)
	else:
		_puppet.set_ghost(_preview_item.category if _preview_item != null else &"", _preview_item)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		_drag_item = _drag_item_of(data)
		_drag_category = _drag_item.category if _drag_item != null else &""
		var dragging_something: bool = data is Dictionary
		for category in SLOTS:
			(_chips[category] as LoadoutSocketChip).set_drag_state(dragging_something, category == _drag_category)
		_puppet.set_ghost(&"", null)
	elif what == NOTIFICATION_DRAG_END:
		_set_drag_over(false)
		_drag_item = null
		_drag_category = &""
		for category in SLOTS:
			(_chips[category] as LoadoutSocketChip).set_drag_state(false, false)


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	var category: StringName = _category_near(button.position)
	if category == &"":
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		slot_selected.emit(category)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_RIGHT and _equipped.get(category, null) != null:
		armor_removed.emit(category)
		accept_event()


func _category_near(point: Vector2) -> StringName:
	var best: StringName = &""
	var best_distance: float = 34.0
	for category in SLOTS:
		var distance: float = point.distance_to(_anchor(category))
		if distance < best_distance:
			best_distance = distance
			best = category
	return best


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


func _burst(category: StringName, count: int) -> void:
	var origin: Vector2 = _anchor(category)
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
	var pedestal: Vector2 = _pedestal_center()
	LoadoutStyle.draw_glow(self, pedestal + Vector2(0.0, -86.0), Vector2(120.0, 112.0), Color(_accent.r, _accent.g, _accent.b, 0.07))
	LoadoutStyle.draw_glow(self, pedestal + Vector2(0.0, 10.0), Vector2(96.0, 12.0), Color(0.0, 0.0, 0.0, 0.55))
	# Low disc: dark rim, lighter top, a thin team-coloured edge on the front.
	var lip: PackedVector2Array = PackedVector2Array()
	for index in range(21):
		var angle: float = PI * float(index) / 20.0
		lip.append(pedestal + Vector2(cos(angle) * 70.0, sin(angle) * 11.0 + 6.0))
	for index in range(20, -1, -1):
		var angle: float = PI * float(index) / 20.0
		lip.append(pedestal + Vector2(cos(angle) * 70.0, sin(angle) * 11.0))
	draw_colored_polygon(lip, Color(0.03, 0.05, 0.055, 1.0))
	draw_colored_polygon(_ellipse(pedestal, Vector2(70.0, 11.0), 40), Color(0.09, 0.125, 0.13, 1.0))
	draw_polyline(_ellipse_arc(pedestal, Vector2(70.0, 11.0), PI * 0.06, PI * 0.94, 30), Color(_accent.r, _accent.g, _accent.b, 0.55), 1.2, true)


func _draw_overlay() -> void:
	for category in SLOTS:
		var chip: LoadoutSocketChip = _chips[category]
		var tick: Vector2 = chip.position + chip.tick_point()
		var target: Vector2 = _anchor(category)
		var color: Color = chip.accent_color()
		var line_color: Color = LoadoutStyle.with_alpha(color, color.a * (0.7 if chip.is_hot() else 0.3))
		var elbow: Vector2 = tick + Vector2(14.0, 0.0)
		_overlay.draw_polyline(PackedVector2Array([tick, elbow, target]), line_color, 1.0, true)
		var installed: bool = _equipped.get(category, null) != null
		if chip.target_active and chip.compatible_drag:
			var radius: float = 4.5 + 1.5 * sin(_time * 7.0)
			_overlay.draw_arc(target, radius + 5.0, 0.0, TAU, 24, LoadoutStyle.with_alpha(color, 0.35), 1.2, true)
			_overlay.draw_circle(target, radius, color, true, -1.0, true)
		elif installed:
			_overlay.draw_circle(target, 3.0, LoadoutStyle.with_alpha(color, 0.9), true, -1.0, true)
		else:
			_overlay.draw_arc(target, 3.5, 0.0, TAU, 16, line_color, 1.2, true)
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
