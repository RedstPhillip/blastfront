class_name LoadoutWeaponBay
extends Control

## The workbench: the configured carbine at a fixed size and position, three labelled sockets around it
## and drag & drop straight onto the gun. While a part is dragged its socket pulses (the shared drop-target
## language, see LoadoutStyle.drop_color); with the cursor over the gun it holds steady and the gun shows the
## part installed, in its real colours. Dropping snaps the part in with a flash, sparks and a small recoil of
## the whole weapon, and the replaced part flies off. Dropping the twin of the installed part merges them.

signal part_dropped(item: WeaponExtensionItem)
signal merge_requested(source: WeaponExtensionItem, target: WeaponExtensionItem)
signal reward_dropped(payload: Dictionary, slot: StringName)
signal part_removed(slot: StringName)
signal slot_selected(slot: StringName)
signal slot_inspected(slot: StringName)

const SLOTS: Array[StringName] = [&"middle", &"front", &"ammo"]
const GUN_SCALE: float = 1.72
const SNAP_TIME: float = 0.34
const EJECT_TIME: float = 0.22
const SLOT_DIRECTIONS: Dictionary = {
	&"front": Vector2(1.0, 0.0),
	&"middle": Vector2(0.0, -1.0),
	&"ammo": Vector2(0.0, 1.0),
}

var _config: Dictionary = {}
var _equipped: Dictionary = {}
## The gun and its effects live on Node2D canvases: the idle sway moves them every frame, and moving a Node2D
## (unlike a Control) does not redraw it, so the vector art is only rebuilt when the build changes.
var _gun_canvas: Node2D = null
var _fx_canvas: Node2D = null
## Centre of the bay; the gun canvas sways and turns around it.
var _pivot: Vector2 = Vector2.ZERO
var _overlay: Control = null
var _chips: Dictionary = {}
var _gun_origin: Vector2 = Vector2.ZERO
var _time: float = 0.0
var _snaps: Dictionary = {}
var _ejects: Array[Dictionary] = []
var _sparks: Array[Dictionary] = []
var _kick: Vector2 = Vector2.ZERO
var _kick_spin: float = 0.0
var _drag_slot: StringName = &""
var _drag_id: StringName = &""
var _drag_mark: int = 1
var _drag_merge_target: WeaponExtensionItem = null
var _drag_over: bool = false
var _hover_slot: StringName = &""
var _parallax: Vector2 = Vector2.ZERO
var _accent: Color = Color(0.32, 0.67, 1.0)
var _title: Label = null
var _subtitle: Label = null


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	_accent = LoadoutStyle.local_accent()
	_gun_canvas = Node2D.new()
	_gun_canvas.draw.connect(_draw_gun)
	add_child(_gun_canvas)
	_fx_canvas = Node2D.new()
	_fx_canvas.draw.connect(_draw_fx)
	_gun_canvas.add_child(_fx_canvas)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	_title = LoadoutStyle.label("B7 CARBINE", UiStyle.FONT_DISPLAY, 16, LoadoutStyle.TEXT)
	add_child(_title)
	_subtitle = LoadoutStyle.caption("", LoadoutStyle.TEXT_MUTED, 10)
	add_child(_subtitle)
	for slot in SLOTS:
		var chip: LoadoutSocketChip = LoadoutSocketChip.new()
		chip.slot = slot
		chip.drop_owner = self
		chip.inspected.connect(func(_chip: LoadoutSocketChip) -> void: slot_inspected.emit(slot))
		chip.remove_requested.connect(func(removed: StringName) -> void: part_removed.emit(removed))
		chip.selected.connect(func(picked: StringName) -> void: slot_selected.emit(picked))
		add_child(chip)
		_chips[slot] = chip
	resized.connect(_layout)
	_layout()


func get_chip(slot: StringName) -> LoadoutSocketChip:
	return _chips.get(slot, null)


## Sets the equipped parts. With animate, changed sockets snap in / eject with effects.
func set_equipped(equipped: Dictionary, animate: bool) -> void:
	var next_config: Dictionary = WeaponArt.config_from_equipped(equipped)
	for slot in SLOTS:
		var before: StringName = WeaponArt.part_id(_config, slot)
		var after: StringName = WeaponArt.part_id(next_config, slot)
		var chip: LoadoutSocketChip = _chips[slot]
		chip.set_item(equipped.get(slot, null), animate and before != after)
		if not animate or before == after:
			continue
		if before != &"":
			_ejects.append({"slot": slot, "id": before, "mark": WeaponArt.part_mark(_config, slot), "t": 0.0})
		_snaps[slot] = 0.0
		_burst(slot, 14 if after != &"" else 6)
		_kick += SLOT_DIRECTIONS[slot] * (-5.0 if after != &"" else 3.0)
		_kick_spin += 0.02 if slot == &"middle" else -0.015
	_config = next_config
	_equipped = equipped.duplicate()
	_update_title()
	_gun_canvas.queue_redraw()
	set_process(true)


func flash_slot(slot: StringName) -> void:
	var chip: LoadoutSocketChip = _chips.get(slot, null)
	if chip != null:
		chip.highlight = 1.0
		chip.set_process(true)


func _update_title() -> void:
	var count: int = 0
	for slot in SLOTS:
		if WeaponArt.part_id(_config, slot) != &"":
			count += 1
	_subtitle.text = "STOCK" if count == 0 else "%d / 3 MODS" % count


func _layout() -> void:
	if _gun_canvas == null:
		return
	_pivot = size * 0.5
	_gun_canvas.position = _pivot
	_gun_canvas.queue_redraw()
	_overlay.size = size
	_gun_origin = Vector2(size.x * 0.5 - 26.0 * GUN_SCALE, size.y * 0.5 + 2.0)
	(_chips[&"middle"] as Control).position = Vector2(12.0, 12.0)
	(_chips[&"front"] as Control).position = Vector2(size.x - LoadoutSocketChip.CHIP_SIZE.x - 12.0, 12.0)
	(_chips[&"ammo"] as Control).position = Vector2(size.x - LoadoutSocketChip.CHIP_SIZE.x - 12.0, size.y - LoadoutSocketChip.CHIP_SIZE.y - 12.0)
	_title.position = Vector2(16.0, size.y - 42.0)
	_subtitle.position = Vector2(17.0, size.y - 22.0)
	queue_redraw()


## Gun space to bay space (before the sway).
func _gun_xform() -> Transform2D:
	return Transform2D(0.0, Vector2.ONE * GUN_SCALE, 0.0, _gun_origin)


## Gun space to the swaying canvas' own space.
func _canvas_gun_xform() -> Transform2D:
	return Transform2D(0.0, -_pivot) * _gun_xform()


func _slot_screen_position(slot: StringName) -> Vector2:
	var local: Vector2 = _gun_xform() * (WeaponArt.SLOT_FOCUS[slot] as Vector2)
	if slot == &"front":
		var muzzle: Vector2 = WeaponArt.muzzle_position(_config)
		local = _gun_xform() * Vector2(lerpf(WeaponArt.SOCKET_POSITIONS[&"front"].x, muzzle.x, 0.45), -5.0)
	return _gun_canvas.get_transform() * (local - _pivot)


# --- Drag & drop -----------------------------------------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	var info: Dictionary = _drag_info(data)
	var accepted: bool = not info.is_empty() and StringName(str(data.get("source", ""))) != &"slot"
	_set_drag_over(accepted)
	return accepted


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var payload: Dictionary = data
	var info: Dictionary = _drag_info(payload)
	_set_drag_over(false)
	if info.is_empty():
		return
	if StringName(str(payload.get("type", ""))) == &"round_reward":
		reward_dropped.emit(payload, info["slot"])
	elif _drag_merge_target != null:
		merge_requested.emit(info["item"], _drag_merge_target)
	else:
		part_dropped.emit(info["item"])


func _drag_info(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {}
	var payload: Dictionary = data
	var type: StringName = StringName(str(payload.get("type", "")))
	var item: WeaponExtensionItem = payload.get("item", null) as WeaponExtensionItem
	if item == null or item.definition == null:
		return {}
	if type == &"round_reward" and StringName(str(payload.get("reward_type", ""))) != RoundRewardInventory.REWARD_EXTENSION:
		return {}
	if type != &"round_reward" and type != &"weapon_extension_item":
		return {}
	return {"slot": item.get_slot(), "id": item.get_definition_id(), "mark": item.mark, "item": item, "type": type}


func _set_drag_over(over: bool) -> void:
	if _drag_over == over:
		return
	_drag_over = over
	if _drag_slot != &"":
		(_chips[_drag_slot] as LoadoutSocketChip).set_armed(over)
	if over:
		AudioDirector.play(&"ui_hover", -6.0, 0.8)
	_gun_canvas.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		var info: Dictionary = _drag_info(data)
		_drag_slot = info.get("slot", &"")
		_drag_id = info.get("id", &"")
		_drag_mark = int(info.get("mark", 1))
		_drag_merge_target = null
		var installed: WeaponExtensionItem = _equipped.get(_drag_slot, null) as WeaponExtensionItem
		if info.get("type", &"") == &"weapon_extension_item" and StringName(str((data as Dictionary).get("source", ""))) != &"slot" \
				and ExtensionInventory.can_merge_items(info.get("item", null), installed):
			_drag_merge_target = installed
		for slot in SLOTS:
			(_chips[slot] as LoadoutSocketChip).set_drag_state(_drag_slot != &"", slot == _drag_slot, _drag_mark + 1 if _drag_merge_target != null else 0)
		set_process(true)
	elif what == NOTIFICATION_DRAG_END:
		_drag_slot = &""
		_drag_id = &""
		_drag_merge_target = null
		_drag_over = false
		for slot in SLOTS:
			(_chips[slot] as LoadoutSocketChip).set_drag_state(false, false)
		_gun_canvas.queue_redraw()


# --- Animation -------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var animating: bool = false
	for slot in _snaps.keys():
		_snaps[slot] = float(_snaps[slot]) + delta / SNAP_TIME
		if float(_snaps[slot]) >= 1.0:
			_snaps.erase(slot)
		else:
			animating = true
	for index in range(_ejects.size() - 1, -1, -1):
		_ejects[index]["t"] = float(_ejects[index]["t"]) + delta / EJECT_TIME
		if float(_ejects[index]["t"]) >= 1.0:
			_ejects.remove_at(index)
		else:
			animating = true
	for index in range(_sparks.size() - 1, -1, -1):
		var spark: Dictionary = _sparks[index]
		spark["life"] = float(spark["life"]) - delta
		if float(spark["life"]) <= 0.0:
			_sparks.remove_at(index)
			continue
		spark["v"] = (spark["v"] as Vector2) * exp(-4.0 * delta) + Vector2(0.0, 260.0 * delta)
		spark["p"] = (spark["p"] as Vector2) + (spark["v"] as Vector2) * delta
	if _drag_over and get_viewport().gui_is_dragging() and not get_global_rect().has_point(get_global_mouse_position()):
		_set_drag_over(false)
	var mouse: Vector2 = get_local_mouse_position()
	var inside: bool = Rect2(Vector2.ZERO, size).has_point(mouse)
	var target_parallax: Vector2 = ((mouse / maxf(size.x, 1.0)) - Vector2(0.5, 0.5)) * Vector2(6.0, 4.0) if inside else Vector2.ZERO
	_parallax = _parallax.lerp(target_parallax, 1.0 - exp(-4.0 * delta))
	_kick = _kick.lerp(Vector2.ZERO, 1.0 - exp(-9.0 * delta))
	_kick_spin = lerpf(_kick_spin, 0.0, 1.0 - exp(-8.0 * delta))
	_gun_canvas.position = _pivot + Vector2(0.0, sin(_time * 1.3) * 2.0) + _parallax + _kick
	_gun_canvas.rotation = sin(_time * 0.9) * 0.006 + _parallax.x * 0.002 + _kick_spin
	_update_hover_slot(mouse, inside)
	if animating:
		_gun_canvas.queue_redraw()
	_fx_canvas.queue_redraw()
	_overlay.queue_redraw()


func _update_hover_slot(mouse: Vector2, inside: bool) -> void:
	var best: StringName = &""
	if inside and not get_viewport().gui_is_dragging():
		var best_distance: float = 34.0
		for slot in SLOTS:
			var distance: float = mouse.distance_to(_slot_screen_position(slot))
			if distance < best_distance:
				best_distance = distance
				best = slot
	if best != _hover_slot:
		_hover_slot = best
		_gun_canvas.queue_redraw()
		if best != &"":
			slot_inspected.emit(best)
			AudioDirector.play(&"ui_hover", -10.0, 1.15)


func _burst(slot: StringName, count: int) -> void:
	var origin: Vector2 = _slot_screen_position(slot)
	var direction: Vector2 = -(SLOT_DIRECTIONS[slot] as Vector2)
	for index in range(count):
		var spread: Vector2 = direction.rotated(randf_range(-1.3, 1.3))
		_sparks.append({
			"p": origin + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)),
			"v": spread * randf_range(80.0, 230.0) + Vector2(0.0, -60.0),
			"life": randf_range(0.25, 0.5),
			"max": 0.5,
			"c": WeaponArt.GOLD.lerp(Color.WHITE, randf() * 0.6),
		})


# --- Drawing ---------------------------------------------------------------------------------------------

func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_style_box(LoadoutStyle.well(), rect)
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.5)
	LoadoutStyle.draw_glow(self, center + Vector2(0.0, -6.0), Vector2(size.x * 0.52, size.y * 0.5), Color(1.0, 1.0, 1.0, 0.045))
	LoadoutStyle.draw_glow(self, center + Vector2(20.0, -6.0), Vector2(size.x * 0.22, size.y * 0.24), Color(1.0, 0.96, 0.9, 0.035))
	var floor_y: float = _gun_origin.y + 52.0 * GUN_SCALE * 0.5 + 18.0
	LoadoutStyle.draw_glow(self, Vector2(center.x + 10.0, floor_y), Vector2(size.x * 0.33, 6.0), Color(0.0, 0.0, 0.0, 0.55))


func _draw_gun() -> void:
	var offsets: Dictionary = {}
	var alphas: Dictionary = {}
	var flashes: Dictionary = {}
	for slot in _snaps.keys():
		var t: float = clampf(float(_snaps[slot]), 0.0, 1.0)
		var settle: float = _ease_out_back(t)
		offsets[slot] = (SLOT_DIRECTIONS[slot] as Vector2) * (1.0 - settle) * 30.0
		alphas[slot] = clampf(t * 3.0, 0.0, 1.0)
		flashes[slot] = (1.0 - t) * 0.85
	if _hover_slot != &"" and not flashes.has(_hover_slot):
		flashes[_hover_slot] = 0.16
	# Armed equip: show the gun as it will be, the dragged part installed in its real colours.
	var config: Dictionary = _config
	if _drag_over and _drag_slot != &"" and _drag_merge_target == null:
		config = _config.duplicate()
		config[_drag_slot] = {"id": _drag_id, "mark": _drag_mark}
	WeaponArt.draw_weapon(_gun_canvas, _canvas_gun_xform(), config, {
		"accent": _accent,
		"offsets": offsets,
		"alphas": alphas,
		"flashes": flashes,
	})
	for eject in _ejects:
		var t: float = float(eject["t"])
		var slot: StringName = eject["slot"]
		var travel: Vector2 = (SLOT_DIRECTIONS[slot] as Vector2) * (t * t * 34.0) + Vector2(0.0, t * t * 18.0)
		WeaponArt.draw_socket_part(_gun_canvas, _canvas_gun_xform(), slot, eject["id"], int(eject["mark"]), travel, 1.0 - t, 0.0, _accent)


func _draw_fx() -> void:
	WeaponArt.draw_fx(_fx_canvas, _canvas_gun_xform(), _config, _time, 1.0)


func _draw_overlay() -> void:
	for slot in SLOTS:
		var chip: LoadoutSocketChip = _chips[slot]
		var target: Vector2 = _slot_screen_position(slot)
		var anchor: Vector2 = chip.position + Vector2(chip.size.x * 0.5, chip.size.y if chip.position.y < size.y * 0.5 else 0.0)
		var active: bool = _drag_slot == slot
		var hovered: bool = _hover_slot == slot
		var color: Color = Color(1, 1, 1, 0.1)
		if active:
			color = LoadoutStyle.drop_color(_drag_over, _time)
		elif hovered:
			color = Color(1, 1, 1, 0.35)
		var elbow: Vector2 = Vector2(anchor.x, lerpf(anchor.y, target.y, 0.55))
		_overlay.draw_polyline(PackedVector2Array([anchor, elbow, target]), color, 1.0, true)
		if active:
			LoadoutStyle.draw_drop_point(_overlay, target, _drag_over, _drag_merge_target != null, _time)
			continue
		var empty: bool = WeaponArt.part_id(_config, slot) == &""
		_overlay.draw_circle(target, 3.0, color if empty else Color(1, 1, 1, 0.55), true, -1.0, true)
	for spark in _sparks:
		var life: float = float(spark["life"]) / float(spark["max"])
		var p: Vector2 = spark["p"]
		var v: Vector2 = spark["v"]
		var c: Color = spark["c"]
		_overlay.draw_line(p, p - v * 0.03, Color(c.r, c.g, c.b, life), 1.6, true)


static func _ease_out_back(t: float) -> float:
	var c1: float = 1.70158
	var c3: float = c1 + 1.0
	return 1.0 + c3 * pow(t - 1.0, 3.0) + c1 * pow(t - 1.0, 2.0)
