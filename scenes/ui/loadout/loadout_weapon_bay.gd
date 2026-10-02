class_name LoadoutWeaponBay
extends Control

## The weapon on the bench: the configured carbine large and lit, three callouts (optic, barrel, ammo)
## tied to their parts by leader lines, drag & drop straight onto the gun. Hovering a part in the locker
## shows it on the gun as a hologram; dropping snaps it in with a flash, sparks and a small recoil of the
## whole weapon, and the replaced part flies off. The gun and the callouts never move with the build, so
## the eye always finds them in the same place.

signal part_dropped(item: WeaponExtensionItem)
signal reward_dropped(payload: Dictionary, slot: StringName)
signal part_removed(slot: StringName)
signal slot_selected(slot: StringName)
signal slot_inspected(slot: StringName)

const SLOTS: Array[StringName] = [&"middle", &"front", &"ammo"]
const GUN_SCALE: float = 1.7
const GUN_SPAN: Vector2 = Vector2(-105.0, 157.0)
const SNAP_TIME: float = 0.34
const EJECT_TIME: float = 0.24
const SLOT_DIRECTIONS: Dictionary = {
	&"front": Vector2(1.0, 0.0),
	&"middle": Vector2(0.0, -1.0),
	&"ammo": Vector2(0.0, 1.0),
}

var _config: Dictionary = {}
var _equipped: Dictionary = {}
var _gun_canvas: Control = null
var _fx_canvas: Control = null
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
var _drag_over: bool = false
var _hover_slot: StringName = &""
var _preview_slot: StringName = &""
var _preview_id: StringName = &""
var _parallax: Vector2 = Vector2.ZERO
var _accent: Color = Color(0.32, 0.67, 1.0)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_accent = LoadoutStyle.local_accent()
	_gun_canvas = Control.new()
	_gun_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gun_canvas.draw.connect(_draw_gun)
	add_child(_gun_canvas)
	_fx_canvas = Control.new()
	_fx_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_canvas.draw.connect(_draw_fx)
	_gun_canvas.add_child(_fx_canvas)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)
	for slot in SLOTS:
		var chip: LoadoutSocketChip = LoadoutSocketChip.new()
		chip.slot = slot
		chip.drop_owner = self
		chip.align_right = slot == &"middle"
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
		_burst(slot, 16 if after != &"" else 6)
		_kick += SLOT_DIRECTIONS[slot] * (-6.0 if after != &"" else 3.0)
		_kick_spin += 0.02 if slot == &"middle" else -0.015
	_config = next_config
	_equipped = equipped.duplicate()
	if _preview_slot != &"" and WeaponArt.part_id(_config, _preview_slot) == _preview_id:
		_preview_slot = &""
		_preview_id = &""
	_gun_canvas.queue_redraw()
	set_process(true)


## Hologram of a part the player is looking at in the locker (null clears).
func set_preview(item: WeaponExtensionItem) -> void:
	var slot: StringName = item.get_slot() if item != null else &""
	var id: StringName = item.get_definition_id() if item != null else &""
	if item != null and WeaponArt.part_id(_config, slot) == id:
		slot = &""
		id = &""
	if slot == _preview_slot and id == _preview_id:
		return
	_preview_slot = slot
	_preview_id = id
	_gun_canvas.queue_redraw()


## Ties a callout to the locker filter so the player sees which socket the list belongs to.
func set_linked_slot(slot: StringName) -> void:
	for key in SLOTS:
		(_chips[key] as LoadoutSocketChip).set_linked(key == slot)


func flash_slot(slot: StringName) -> void:
	var chip: LoadoutSocketChip = _chips.get(slot, null)
	if chip != null:
		chip.highlight = 1.0
		chip.set_process(true)


func _layout() -> void:
	if _gun_canvas == null:
		return
	_gun_canvas.size = size
	_gun_canvas.pivot_offset = size * 0.5
	_fx_canvas.size = size
	_overlay.size = size
	var span_center: float = (GUN_SPAN.x + GUN_SPAN.y) * 0.5
	_gun_origin = Vector2(size.x * 0.5 - span_center * GUN_SCALE, size.y * 0.5 + 4.0)
	var chip_size: Vector2 = LoadoutSocketChip.CHIP_SIZE
	var optic_pin: Vector2 = _gun_xform() * (WeaponArt.SLOT_FOCUS[&"middle"] as Vector2)
	var ammo_pin: Vector2 = _gun_xform() * (WeaponArt.SLOT_FOCUS[&"ammo"] as Vector2)
	(_chips[&"middle"] as Control).position = Vector2(optic_pin.x - 46.0 - chip_size.x, 18.0)
	(_chips[&"front"] as Control).position = Vector2(size.x - chip_size.x - 4.0, 18.0)
	(_chips[&"ammo"] as Control).position = Vector2(ammo_pin.x + 52.0, size.y - chip_size.y - 14.0)
	queue_redraw()


func _gun_xform() -> Transform2D:
	return Transform2D(0.0, Vector2.ONE * GUN_SCALE, 0.0, _gun_origin)


func _slot_screen_position(slot: StringName) -> Vector2:
	var local: Vector2 = _gun_xform() * (WeaponArt.SLOT_FOCUS[slot] as Vector2)
	if slot == &"front":
		var muzzle: Vector2 = WeaponArt.muzzle_position(_config)
		local = _gun_xform() * Vector2(lerpf(WeaponArt.SOCKET_POSITIONS[&"front"].x, muzzle.x, 0.45), -5.0)
	return _gun_canvas.get_transform() * local


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
	else:
		part_dropped.emit(payload.get("item", null) as WeaponExtensionItem)


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
	return {"slot": item.get_slot(), "id": item.get_definition_id()}


func _set_drag_over(over: bool) -> void:
	if _drag_over == over:
		return
	_drag_over = over
	if over:
		AudioDirector.play(&"ui_hover", -6.0, 0.8)
	_gun_canvas.queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var info: Dictionary = _drag_info(get_viewport().gui_get_drag_data())
		_drag_slot = info.get("slot", &"")
		_drag_id = info.get("id", &"")
		var dragging_armor: bool = _drag_slot == &"" and get_viewport().gui_get_drag_data() is Dictionary
		for slot in SLOTS:
			(_chips[slot] as LoadoutSocketChip).set_drag_state(_drag_slot != &"" or dragging_armor, slot == _drag_slot)
		set_process(true)
	elif what == NOTIFICATION_DRAG_END:
		_drag_slot = &""
		_drag_id = &""
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
	_gun_canvas.position = Vector2(0.0, sin(_time * 1.3) * 2.0) + _parallax + _kick
	_gun_canvas.rotation = sin(_time * 0.9) * 0.005 + _parallax.x * 0.002 + _kick_spin
	_update_hover_slot(mouse, inside)
	if animating or _preview_slot != &"" or _drag_over:
		_gun_canvas.queue_redraw()
	_fx_canvas.queue_redraw()
	_overlay.queue_redraw()


func _update_hover_slot(mouse: Vector2, inside: bool) -> void:
	var best: StringName = &""
	if inside and not get_viewport().gui_is_dragging():
		var best_distance: float = 36.0
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


func _gui_input(event: InputEvent) -> void:
	var button: InputEventMouseButton = event as InputEventMouseButton
	if button == null or not button.pressed or _hover_slot == &"":
		return
	if button.button_index == MOUSE_BUTTON_LEFT:
		slot_selected.emit(_hover_slot)
		accept_event()
	elif button.button_index == MOUSE_BUTTON_RIGHT and WeaponArt.part_id(_config, _hover_slot) != &"":
		part_removed.emit(_hover_slot)
		accept_event()


func _burst(slot: StringName, count: int) -> void:
	var origin: Vector2 = _slot_screen_position(slot)
	var direction: Vector2 = -(SLOT_DIRECTIONS[slot] as Vector2)
	for index in range(count):
		var spread: Vector2 = direction.rotated(randf_range(-1.3, 1.3))
		_sparks.append({
			"p": origin + Vector2(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0)),
			"v": spread * randf_range(80.0, 240.0) + Vector2(0.0, -60.0),
			"life": randf_range(0.25, 0.5),
			"max": 0.5,
			"c": WeaponArt.GOLD.lerp(Color.WHITE, randf() * 0.6),
		})


# --- Drawing ---------------------------------------------------------------------------------------------

func _draw() -> void:
	# A work light on the bench: warm pool behind the gun and a soft contact shadow below it.
	var center: Vector2 = _gun_origin + Vector2(10.0 * GUN_SCALE, 0.0)
	LoadoutStyle.draw_glow(self, center + Vector2(0.0, -8.0), Vector2(size.x * 0.5, size.y * 0.46), Color(1.0, 0.86, 0.6, 0.05))
	LoadoutStyle.draw_glow(self, center + Vector2(0.0, 74.0), Vector2(size.x * 0.36, 9.0), Color(0.0, 0.0, 0.0, 0.5))


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
	var focus_slot: StringName = _hover_slot
	for slot in SLOTS:
		if (_chips[slot] as LoadoutSocketChip).is_hot() and not (_chips[slot] as LoadoutSocketChip).linked:
			focus_slot = slot
	if focus_slot != &"" and not flashes.has(focus_slot):
		flashes[focus_slot] = 0.18
	var ghosts: Dictionary = {}
	if _drag_over and _drag_slot != &"":
		ghosts[_drag_slot] = _drag_id
		alphas[_drag_slot] = 0.2
	elif _preview_slot != &"" and not get_viewport().gui_is_dragging():
		ghosts[_preview_slot] = _preview_id
		alphas[_preview_slot] = 0.2
	WeaponArt.draw_weapon(_gun_canvas, _gun_xform(), _config, {
		"accent": _accent,
		"offsets": offsets,
		"alphas": alphas,
		"flashes": flashes,
		"ghost": ghosts,
	})
	for eject in _ejects:
		var t: float = float(eject["t"])
		var slot: StringName = eject["slot"]
		var travel: Vector2 = (SLOT_DIRECTIONS[slot] as Vector2) * (t * t * 36.0) + Vector2(0.0, t * t * 22.0)
		WeaponArt.draw_socket_part(_gun_canvas, _gun_xform(), slot, eject["id"], int(eject["mark"]), travel, 1.0 - t, 0.0, _accent)


func _draw_fx() -> void:
	WeaponArt.draw_fx(_fx_canvas, _gun_xform(), _config, _time, 1.0)


func _draw_overlay() -> void:
	for slot in SLOTS:
		var chip: LoadoutSocketChip = _chips[slot]
		var pin: Vector2 = _slot_screen_position(slot)
		var tick: Vector2 = chip.position + chip.tick_point()
		var color: Color = chip.accent_color()
		var hot: bool = chip.is_hot() or _hover_slot == slot
		var line_color: Color = LoadoutStyle.with_alpha(color, color.a * (0.7 if hot else 0.3))
		var out: float = 14.0 if chip.align_right else -14.0
		var elbow: Vector2 = tick + Vector2(out, 0.0)
		_overlay.draw_polyline(PackedVector2Array([tick, elbow, pin]), line_color, 1.0, true)
		var empty: bool = WeaponArt.part_id(_config, slot) == &""
		var drop_ready: bool = chip.target_active and chip.compatible_drag
		if drop_ready:
			var radius: float = 5.0 + 1.5 * sin(_time * 7.0)
			_overlay.draw_arc(pin, radius + 5.0, 0.0, TAU, 24, LoadoutStyle.with_alpha(color, 0.35), 1.2, true)
			_overlay.draw_circle(pin, radius, color, true, -1.0, true)
		elif empty:
			_overlay.draw_arc(pin, 3.5, 0.0, TAU, 16, line_color, 1.2, true)
		else:
			_overlay.draw_circle(pin, 3.0 if not hot else 3.8, LoadoutStyle.with_alpha(color, 0.9), true, -1.0, true)
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
