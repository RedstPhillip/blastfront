extends Control
class_name LoadoutPage

## The loadout. A bench on the left presents the build: the carbine large and lit with callouts on its
## sockets, the operator with the armor callouts, a nameplate and the key stats under each. The locker is
## docked on the right: the shop (set flow only), slot filters and every owned part in sections.
## There is no separate details panel: hovering a part shows it on the bench (hologram on the gun or the
## operator, nameplate readout, stat deltas), so the build stays the focus. A prompt line at the bottom
## names what the mouse or pad can do right now and reports purchases, merges and refusals.
## Works in the sandbox pause menu (everything unlocked, no shop) and in the set intermission (shop,
## blueprints, recycler, merges).

const MERGE_DIALOG_SCENE: PackedScene = preload("res://scenes/ui/loadout/merge_dialog.tscn")
const BASE_RELOAD_TIME: float = 1.2
const BASE_AMMO: float = 3.0
const DOCK_WIDTH: float = 392.0
const DOCK_PAD: float = 24.0
const BENCH_LEFT: float = 40.0
const BAY_SIZE: Vector2 = Vector2(480.0, 320.0)
const GRID_COLUMNS: int = 5
const GRID_GAP: int = 6
const SHOP_TILE: Vector2 = Vector2(52.0, 52.0)
const SLOT_ORDER: Array[StringName] = [&"front", &"middle", &"ammo", &"shield", &"vest", &"boots"]
const WEAPON_SLOTS: Array[StringName] = [&"front", &"middle", &"ammo"]
const ARMOR_SLOTS: Array[StringName] = [&"shield", &"vest", &"boots"]
const WEAPON_STAT_PRIORITY: Array[StringName] = [
	&"damage", &"fire_interval", &"reload_time", &"ammo_max", &"projectile_speed", &"projectile_max_distance",
	&"shots_per_fire", &"shot_spread_degrees", &"shot_random_spread_degrees", &"projectile_gravity",
	&"recoil_rotation_degrees", &"projectile_scale", &"projectile_linear_damping",
]
const ARMOR_STAT_PRIORITY: Array[StringName] = [
	&"max_health", &"move_speed", &"air_speed", &"jump_velocity", &"damage_reduction",
	&"stationary_damage_reduction", &"freeze_resistance", &"reflect_chance", &"delayed_damage_duration",
	&"block_strength", &"frosty_radius", &"healing_rate", &"pull_strength", &"adrenaline_speed_bonus",
	&"escape_speed_bonus", &"chase_speed_bonus",
]
const WEAPON_ATTRIBUTE_NAMES: Dictionary = {
	&"damage": "Damage", &"fire_interval": "Fire rate", &"reload_time": "Reload", &"ammo_max": "Ammo",
	&"projectile_speed": "Velocity", &"projectile_gravity": "Bullet drop", &"projectile_linear_damping": "Drag",
	&"projectile_max_distance": "Range", &"projectile_scale": "Bullet size", &"shots_per_fire": "Pellets",
	&"shot_spread_degrees": "Spread", &"shot_random_spread_degrees": "Scatter", &"recoil_rotation_degrees": "Recoil",
}
const ARMOR_ATTRIBUTE_NAMES: Dictionary = {
	&"max_health": "Health", &"move_speed": "Speed", &"air_speed": "Air speed", &"jump_velocity": "Jump",
	&"damage_reduction": "Armor", &"stationary_damage_reduction": "Armor standing still", &"freeze_resistance": "Freeze resist",
	&"reflect_chance": "Reflect", &"delayed_damage_duration": "Damage delay", &"block_strength": "Block",
	&"frosty_radius": "Frost radius", &"frosty_duration": "Frost time", &"frosty_speed_multiplier": "Enemy speed",
	&"healing_radius": "Heal radius", &"healing_rate": "Healing", &"pull_radius": "Pull radius", &"pull_strength": "Pull force",
	&"instant_reload_on_block": "Reload on block", &"adrenaline_duration": "Adrenaline", &"adrenaline_speed_bonus": "Adrenaline speed",
	&"escape_speed_bonus": "Low-health speed", &"chase_speed_bonus": "Chase speed",
}
const WEAPON_ATTRIBUTE_SUFFIXES: Dictionary = {
	&"fire_interval": "/s", &"reload_time": "s", &"shot_spread_degrees": "°", &"shot_random_spread_degrees": "°", &"recoil_rotation_degrees": "°",
}
const ARMOR_ATTRIBUTE_SUFFIXES: Dictionary = {
	&"freeze_resistance": "%", &"reflect_chance": "%", &"frosty_speed_multiplier": "%", &"delayed_damage_duration": "s",
	&"frosty_duration": "s", &"adrenaline_duration": "s", &"healing_rate": "/s",
}
const WEAPON_ATTRIBUTE_DECIMALS: Dictionary = {&"fire_interval": 1, &"reload_time": 2, &"projectile_scale": 2}
const ARMOR_ATTRIBUTE_DECIMALS: Dictionary = {&"delayed_damage_duration": 1, &"frosty_duration": 1, &"adrenaline_duration": 1}
const WEAPON_LOWER_IS_BETTER: Array[StringName] = [
	&"reload_time", &"projectile_gravity", &"projectile_linear_damping", &"shot_spread_degrees", &"shot_random_spread_degrees", &"recoil_rotation_degrees",
]
const ARMOR_LOWER_IS_BETTER: Array[StringName] = [&"frosty_speed_multiplier"]
const WEAPON_STRIP_KEYS: Array[StringName] = [&"damage", &"fire_interval", &"reload_time", &"ammo_max", &"projectile_speed"]
const ARMOR_STRIP_KEYS: Array[StringName] = [&"max_health", &"move_speed", &"jump_velocity", &"damage_reduction"]
const MAX_EFFECTS: int = 3
const HOVER_CLEAR_DELAY: float = 0.15

var _shop_enabled: bool = false
var _top_inset: float = 0.0
var _weapon_bay: LoadoutWeaponBay = null
var _operator: LoadoutOperatorStage = null
var _weapon_plate: LoadoutNameplate = null
var _armor_plate: LoadoutNameplate = null
var _weapon_stats: LoadoutStatStrip = null
var _armor_stats: LoadoutStatStrip = null
var _title: Label = null
var _subtitle: Label = null
var _dock: Control = null
var _dock_content: VBoxContainer = null
var _filter: StringName = &""
var _filter_tabs: Dictionary = {}
var _filter_row: Control = null
var _locker_scroll: ScrollContainer = null
var _locker_list: VBoxContainer = null
var _locker_drop: LoadoutInventoryDrop = null
var _sections: Dictionary = {}
var _empty_label: Label = null
var _coin_label: Label = null
var _coin_value: int = -1
var _offer_tiles: Array[LoadoutRewardTile] = []
var _saved_tiles: Array[LoadoutRewardTile] = []
var _recycler: LoadoutRecycler = null
var _saved_caption: Label = null
var _saved_row: Control = null
var _prompt_bar: UiPromptBar = null
var _merge_dialog: LoadoutMergeDialog = null
var _pending_merge_source: WeaponExtensionItem = null
var _pending_merge_target: WeaponExtensionItem = null
var _pending_armor_merge_source: ArmorItemData = null
var _pending_armor_merge_target: ArmorItemData = null
var _inspecting: bool = false
var _hover_clear_timer: float = 0.0
var _animate_changes: bool = false
var _opened: bool = false
var _bench_nodes: Array[Control] = []
var _floor_y: float = 340.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_shop_enabled = NetworkSession.uses_set_flow()
	_build()
	_merge_dialog = MERGE_DIALOG_SCENE.instantiate() as LoadoutMergeDialog
	add_child(_merge_dialog)
	_merge_dialog.confirmed.connect(_confirm_pending_merge)
	_merge_dialog.cancelled.connect(_cancel_pending_merge)
	_connect_inventory_signals()
	InputDevice.device_changed.connect(_on_device_changed)
	resized.connect(_layout)
	_layout()
	_refresh_all(false)
	_show_overview()
	_play_open()
	if InputDevice.using_gamepad:
		_focus_first_tile.call_deferred()


func _exit_tree() -> void:
	var connections: Array = [
		[ArmorInventory.inventory_changed, _on_armor_changed],
		[ArmorInventory.loadout_changed, _on_armor_changed],
		[ExtensionInventory.inventory_changed, _on_extension_inventory_changed],
		[ExtensionInventory.loadout_changed, _on_extension_loadout_changed],
		[RoundRewardInventory.rewards_changed, _refresh_shop],
		[OnlineMatch.state_changed, _refresh_coins],
		[ResearchManager.research_changed, _refresh_shop],
		[InputDevice.device_changed, _on_device_changed],
	]
	for pair in connections:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])


func _connect_inventory_signals() -> void:
	ArmorInventory.inventory_changed.connect(_on_armor_changed)
	ArmorInventory.loadout_changed.connect(_on_armor_changed)
	ExtensionInventory.inventory_changed.connect(_on_extension_inventory_changed)
	ExtensionInventory.loadout_changed.connect(_on_extension_loadout_changed)
	RoundRewardInventory.rewards_changed.connect(_refresh_shop)
	OnlineMatch.state_changed.connect(_refresh_coins)
	ResearchManager.research_changed.connect(_refresh_shop)


## Leaves room above the page, e.g. for the intermission tab bar. The page title is dropped there: the tab
## already says where you are.
func set_top_inset(pixels: float) -> void:
	_top_inset = pixels
	_layout()


func _process(delta: float) -> void:
	if not _inspecting:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if _dragging() or _is_inspectable(hovered) or (InputDevice.using_gamepad and focused is LoadoutItemTile and is_ancestor_of(focused)):
		_hover_clear_timer = HOVER_CLEAR_DELAY
		return
	_hover_clear_timer -= delta
	if _hover_clear_timer <= 0.0:
		_show_overview()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), LoadoutStyle.BACKDROP)
	# The bench is a space, not a void: a broad haze behind the build and a pool of light on the floor the
	# gun and the operator stand over.
	var bench_width: float = size.x - DOCK_WIDTH
	LoadoutStyle.draw_glow(self, Vector2(bench_width * 0.5, _floor_y - 90.0), Vector2(bench_width * 0.62, 260.0), Color(0.62, 0.86, 0.8, 0.03), 48)
	LoadoutStyle.draw_glow(self, Vector2(bench_width * 0.5, _floor_y + 6.0), Vector2(bench_width * 0.5, 54.0), Color(0.72, 0.9, 0.84, 0.035), 48)
	LoadoutStyle.draw_gradient_rect(self, Rect2(0.0, size.y - 180.0, size.x, 180.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.28))


# --- Construction ----------------------------------------------------------------------------------------

func _build() -> void:
	_title = LoadoutStyle.label("LOADOUT", UiStyle.FONT_DISPLAY, 28, LoadoutStyle.TEXT)
	add_child(_title)
	_subtitle = LoadoutStyle.caption(_context_line(), LoadoutStyle.TEXT_MUTED, 11)
	add_child(_subtitle)

	_weapon_bay = LoadoutWeaponBay.new()
	_weapon_bay.size = BAY_SIZE
	_weapon_bay.part_dropped.connect(_equip_extension)
	_weapon_bay.reward_dropped.connect(_on_weapon_reward_dropped)
	_weapon_bay.part_removed.connect(_unequip_extension_slot)
	_weapon_bay.slot_selected.connect(_select_slot)
	_weapon_bay.slot_inspected.connect(_inspect_weapon_slot)
	add_child(_weapon_bay)

	_operator = LoadoutOperatorStage.new()
	_operator.armor_dropped.connect(_equip_armor)
	_operator.reward_dropped.connect(_on_armor_reward_dropped)
	_operator.armor_removed.connect(_unequip_armor_category)
	_operator.slot_selected.connect(_select_slot)
	_operator.slot_inspected.connect(_inspect_armor_slot)
	add_child(_operator)

	_weapon_plate = LoadoutNameplate.new()
	add_child(_weapon_plate)
	_armor_plate = LoadoutNameplate.new()
	add_child(_armor_plate)
	_weapon_stats = LoadoutStatStrip.new()
	add_child(_weapon_stats)
	_armor_stats = LoadoutStatStrip.new()
	add_child(_armor_stats)

	_prompt_bar = UiPromptBar.new()
	add_child(_prompt_bar)

	_bench_nodes = [_title, _subtitle, _weapon_bay, _operator, _weapon_plate, _armor_plate, _weapon_stats, _armor_stats, _prompt_bar]
	_build_dock()


func _context_line() -> String:
	if not _shop_enabled:
		return "SANDBOX  ·  EVERY PART UNLOCKED"
	var completed: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0)) + int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	return "BEFORE SET %d" % (completed + 1)


func _build_dock() -> void:
	_dock = Control.new()
	_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.draw.connect(_draw_dock)
	add_child(_dock)
	_dock_content = VBoxContainer.new()
	_dock_content.add_theme_constant_override("separation", 0)
	_dock_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock.add_child(_dock_content)
	if _shop_enabled:
		_build_shop()
	_dock_content.add_child(_section_caption("LOCKER", null))
	_dock_content.add_child(_spacer(8.0))
	_filter_row = _build_filter_row()
	_dock_content.add_child(_filter_row)
	_dock_content.add_child(_spacer(12.0))

	_locker_drop = LoadoutInventoryDrop.new()
	_locker_drop.page = self
	_locker_drop.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock_content.add_child(_locker_drop)
	_locker_scroll = ScrollContainer.new()
	_locker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_locker_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_locker_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(_locker_scroll.get_v_scroll_bar())
	_locker_drop.add_child(_locker_scroll)
	_locker_list = VBoxContainer.new()
	_locker_list.add_theme_constant_override("separation", 0)
	_locker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_locker_list.mouse_filter = Control.MOUSE_FILTER_PASS
	_locker_scroll.add_child(_locker_list)
	for slot in SLOT_ORDER:
		_sections[slot] = _build_section(slot)
	_empty_label = LoadoutStyle.label("", UiStyle.FONT_BODY, 13, LoadoutStyle.TEXT_MUTED)
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_label.visible = false
	_locker_drop.add_child(_empty_label)


func _spacer(height: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0.0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer


## Small caps caption with a hairline running to the right edge; an optional control sits on the right.
func _section_caption(text: String, right: Control) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 20.0)
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label: Label = LoadoutStyle.caption(text, LoadoutStyle.TEXT_SECONDARY, 11)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var line: Control = Control.new()
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.draw.connect(func() -> void: line.draw_line(Vector2(0.0, line.size.y * 0.5), Vector2(line.size.x, line.size.y * 0.5), LoadoutStyle.HAIRLINE, 1.0))
	row.add_child(line)
	if right != null:
		right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(right)
	return row


func _build_shop() -> void:
	var coin_box: Control = Control.new()
	coin_box.custom_minimum_size = Vector2(80.0, 22.0)
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_label = LoadoutStyle.label("0", UiStyle.FONT_DISPLAY, 18, LoadoutStyle.COIN)
	_coin_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_coin_label.size = Vector2(62.0, 22.0)
	_coin_label.position = Vector2(18.0, -3.0)
	_coin_label.pivot_offset = Vector2(62.0, 11.0)
	coin_box.add_child(_coin_label)
	coin_box.draw.connect(func() -> void: LoadoutStyle.draw_coin(coin_box, Vector2(80.0 - 4.0 - _coin_text_width() - 9.0, 10.0), 5.5))
	_coin_label.set_meta("box", coin_box)
	_dock_content.add_child(_section_caption("SHOP", coin_box))
	_dock_content.add_child(_spacer(10.0))
	var offers: HBoxContainer = HBoxContainer.new()
	offers.add_theme_constant_override("separation", 6)
	offers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dock_content.add_child(offers)
	for index in [0, 2, 4, 1, 3, 5]:
		var tile: LoadoutRewardTile = _make_reward_tile(RoundRewardInventory.SOURCE_OFFER, index)
		offers.add_child(tile)
		_offer_tiles.append(tile)
	var saved_block: VBoxContainer = VBoxContainer.new()
	saved_block.add_theme_constant_override("separation", 0)
	saved_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saved_row = saved_block
	saved_block.add_child(_spacer(14.0))
	_saved_caption = LoadoutStyle.caption("SAVED BLUEPRINTS", LoadoutStyle.TEXT_MUTED, 10)
	saved_block.add_child(_saved_caption)
	saved_block.add_child(_spacer(6.0))
	var saved_row: HBoxContainer = HBoxContainer.new()
	saved_row.add_theme_constant_override("separation", 6)
	saved_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	saved_block.add_child(saved_row)
	for index in range(RoundRewardInventory.MAX_SAVED_SLOT_COUNT):
		var saved: LoadoutRewardTile = _make_reward_tile(RoundRewardInventory.SOURCE_SAVED, index)
		saved_row.add_child(saved)
		_saved_tiles.append(saved)
	_recycler = LoadoutRecycler.new()
	_recycler.custom_minimum_size = SHOP_TILE
	_recycler.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_recycler.recycled.connect(_on_reward_recycled)
	saved_row.add_child(_recycler)
	_dock_content.add_child(saved_block)
	_dock_content.add_child(_spacer(22.0))


func _coin_text_width() -> float:
	if _coin_label == null:
		return 0.0
	return UiStyle.FONT_DISPLAY.get_string_size(_coin_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x


func _make_reward_tile(kind: StringName, index: int) -> LoadoutRewardTile:
	var tile: LoadoutRewardTile = LoadoutRewardTile.new()
	tile.set_tile_size(SHOP_TILE)
	tile.source_kind = kind
	tile.source_index = index
	tile.inspected.connect(_on_reward_inspected)
	tile.reward_claimed.connect(_on_reward_claimed)
	tile.reward_moved.connect(_on_reward_moved)
	return tile


func _build_filter_row() -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 24.0)
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var filters: Array[StringName] = [&""]
	filters.append_array(SLOT_ORDER)
	for filter in filters:
		if filter == &"shield":
			var gap: Control = _spacer(0.0)
			gap.custom_minimum_size = Vector2(8.0, 0.0)
			row.add_child(gap)
		var tab: Button = Button.new()
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.text = "ALL" if filter == &"" else LoadoutStyle.slot_label(filter)
		tab.custom_minimum_size = Vector2(0.0, 24.0)
		tab.set_meta("juice_feedback_connected", true)
		tab.add_theme_font_override("font", UiStyle.FONT_BOLD)
		tab.add_theme_font_size_override("font_size", 11)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var style: StyleBoxFlat = LoadoutStyle.flat(Color(0, 0, 0, 0), 0)
			if state in ["pressed", "hover_pressed"]:
				style.border_color = LoadoutStyle.ACCENT
				style.border_width_bottom = 2
			style.content_margin_left = 6.0
			style.content_margin_right = 6.0
			style.content_margin_bottom = 3.0
			tab.add_theme_stylebox_override(state, style)
		tab.add_theme_color_override("font_color", LoadoutStyle.TEXT_MUTED)
		tab.add_theme_color_override("font_hover_color", LoadoutStyle.TEXT_SECONDARY)
		tab.add_theme_color_override("font_pressed_color", LoadoutStyle.TEXT)
		tab.add_theme_color_override("font_hover_pressed_color", LoadoutStyle.TEXT)
		tab.pressed.connect(func() -> void: _set_filter(filter))
		tab.mouse_entered.connect(func() -> void: AudioDirector.play(&"loadout_hover", -4.0))
		row.add_child(tab)
		_filter_tabs[filter] = tab
	return row


func _build_section(slot: StringName) -> Dictionary:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	_locker_list.add_child(box)
	var header: Control = Control.new()
	header.custom_minimum_size = Vector2(0.0, 22.0)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var section: Dictionary = {"box": box, "header": header, "count": 0, "tiles": [] as Array[LoadoutItemTile]}
	header.draw.connect(_draw_section_header.bind(header, slot, section))
	box.add_child(header)
	var grid: GridContainer = GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(grid)
	box.add_child(_spacer(16.0))
	section["grid"] = grid
	return section


func _draw_section_header(header: Control, slot: StringName, section: Dictionary) -> void:
	var text: String = LoadoutStyle.slot_label(slot)
	var linked: bool = _filter == slot
	var color: Color = LoadoutStyle.ACCENT if linked else LoadoutStyle.TEXT_MUTED
	header.draw_string(UiStyle.FONT_BOLD, Vector2(0.0, 11.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
	var width: float = UiStyle.FONT_BOLD.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var count_text: String = str(int(section["count"]))
	header.draw_string(UiStyle.FONT_BOLD, Vector2(width + 6.0, 11.0), count_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, LoadoutStyle.with_alpha(LoadoutStyle.TEXT_MUTED, 0.22))


func _style_scrollbar(bar: VScrollBar) -> void:
	var track: StyleBoxFlat = LoadoutStyle.flat(Color(1, 1, 1, 0.0), 2)
	track.content_margin_left = 3.0
	track.content_margin_right = 0.0
	var grabber: StyleBoxFlat = LoadoutStyle.flat(Color(1, 1, 1, 0.16), 2)
	var grabber_hot: StyleBoxFlat = LoadoutStyle.flat(Color(1, 1, 1, 0.36), 2)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hot)
	bar.add_theme_stylebox_override("grabber_pressed", grabber_hot)
	bar.custom_minimum_size = Vector2(5.0, 0.0)


# --- Layout ----------------------------------------------------------------------------------------------

func _layout() -> void:
	if _weapon_bay == null:
		return
	var top: float = maxf(_top_inset, 0.0)
	var titled: bool = top < 1.0
	_title.visible = titled
	_subtitle.visible = titled
	_title.position = Vector2(BENCH_LEFT + 8.0, 26.0)
	_subtitle.position = Vector2(BENCH_LEFT + 10.0, 62.0)
	var bench_top: float = 104.0 if titled else top + 22.0
	var bench_right: float = size.x - DOCK_WIDTH - 20.0
	_weapon_bay.position = Vector2(BENCH_LEFT - 2.0, bench_top)
	_weapon_bay.size = BAY_SIZE
	var operator_left: float = _weapon_bay.position.x + BAY_SIZE.x - 30.0
	_operator.position = Vector2(operator_left, bench_top)
	_operator.size = Vector2(bench_right - operator_left, BAY_SIZE.y)
	_floor_y = bench_top + 238.0
	var plate_y: float = bench_top + BAY_SIZE.y + 16.0
	var weapon_column: Rect2 = Rect2(BENCH_LEFT + 8.0, plate_y, operator_left - BENCH_LEFT - 28.0, 0.0)
	var armor_column: Rect2 = Rect2(operator_left + 20.0, plate_y, bench_right - operator_left - 20.0, 0.0)
	_weapon_plate.position = weapon_column.position
	_weapon_plate.size = Vector2(weapon_column.size.x, LoadoutNameplate.HEIGHT)
	_armor_plate.position = armor_column.position
	_armor_plate.size = Vector2(armor_column.size.x, LoadoutNameplate.HEIGHT)
	_weapon_stats.position = weapon_column.position + Vector2(0.0, LoadoutNameplate.HEIGHT + 14.0)
	_weapon_stats.size = Vector2(weapon_column.size.x, 44.0)
	_armor_stats.position = armor_column.position + Vector2(0.0, LoadoutNameplate.HEIGHT + 14.0)
	_armor_stats.size = Vector2(armor_column.size.x, 44.0)
	_prompt_bar.position = Vector2(BENCH_LEFT + 8.0, size.y - 42.0)
	_prompt_bar.size = Vector2(bench_right - BENCH_LEFT - 8.0, 22.0)

	_dock.position = Vector2(size.x - DOCK_WIDTH, top)
	_dock.size = Vector2(DOCK_WIDTH, size.y - top)
	var dock_top: float = 30.0 if titled else 20.0
	_dock_content.position = Vector2(DOCK_PAD, dock_top)
	_dock_content.size = Vector2(DOCK_WIDTH - DOCK_PAD * 2.0 + 6.0, _dock.size.y - dock_top - 20.0)
	_empty_label.position = Vector2(0.0, 36.0)
	_empty_label.size = Vector2(DOCK_WIDTH - DOCK_PAD * 2.0, 80.0)
	queue_redraw()


func _draw_dock() -> void:
	_dock.draw_rect(Rect2(Vector2.ZERO, _dock.size), LoadoutStyle.DOCK)
	_dock.draw_line(Vector2(0.5, 0.0), Vector2(0.5, _dock.size.y), LoadoutStyle.HAIRLINE, 1.0)


func _focus_first_tile() -> void:
	for slot in SLOT_ORDER:
		for tile in _sections[slot]["tiles"]:
			if tile.visible and tile.item != null:
				tile.grab_focus()
				return


func _play_open() -> void:
	for index in range(_bench_nodes.size()):
		var node: Control = _bench_nodes[index]
		var resting: float = node.position.y
		node.modulate.a = 0.0
		node.position.y = resting + 10.0
		var tween: Tween = node.create_tween().set_parallel(true)
		var delay: float = 0.02 * float(mini(index, 6))
		tween.tween_property(node, "modulate:a", 1.0, 0.22).set_delay(delay)
		tween.tween_property(node, "position:y", resting, 0.3).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var dock_x: float = _dock.position.x
	_dock.position.x = dock_x + 28.0
	_dock.modulate.a = 0.0
	var dock_tween: Tween = _dock.create_tween().set_parallel(true)
	dock_tween.tween_property(_dock, "position:x", dock_x, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	dock_tween.tween_property(_dock, "modulate:a", 1.0, 0.2)
	# The carbine assembles itself once the bench has faded in.
	_weapon_bay.set_equipped({}, false)
	get_tree().create_timer(0.18, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(_weapon_bay):
			_weapon_bay.set_equipped(ExtensionInventory.get_equipped_for_local(), true)
			if not ExtensionInventory.get_equipped_for_local().values().filter(func(v: Variant) -> bool: return v != null).is_empty():
				AudioDirector.play(&"loadout_snap", -6.0)
		_opened = true)


# --- Refresh ---------------------------------------------------------------------------------------------

func _refresh_all(animate: bool) -> void:
	_refresh_weapon(animate)
	_refresh_armor(animate)
	_refresh_shop()
	_update_tabs()


func _refresh_weapon(animate: bool) -> void:
	var equipped: Dictionary = ExtensionInventory.get_equipped_for_local()
	if _opened or animate:
		_weapon_bay.set_equipped(equipped, animate)
	_operator.set_weapon(WeaponArt.config_from_equipped(equipped), animate)
	_fill_locker()
	_update_weapon_stats(animate)
	if not _inspecting:
		_show_overview()


func _refresh_armor(animate: bool) -> void:
	var equipped: Dictionary = {}
	for category in ArmorItemData.category_ids():
		equipped[category] = ArmorInventory.get_equipped_item(category)
	_operator.set_armor(equipped, animate)
	_fill_locker()
	_update_armor_stats(animate)
	if not _inspecting:
		_show_overview()


func _owned_items(slot: StringName) -> Array:
	if slot in WEAPON_SLOTS:
		return _sorted_extensions().filter(func(item: WeaponExtensionItem) -> bool: return item.get_slot() == slot)
	return _sorted_armor().filter(func(item: ArmorItemData) -> bool: return item.category == slot)


func _sorted_extensions() -> Array[WeaponExtensionItem]:
	var items: Array[WeaponExtensionItem] = []
	for item in ExtensionInventory.get_inventory_for_local():
		if item != null and item.definition != null:
			items.append(item)
	for item in ExtensionInventory.get_equipped_for_local().values():
		var extension: WeaponExtensionItem = item as WeaponExtensionItem
		if extension != null and not items.has(extension):
			items.append(extension)
	var order: Dictionary = {}
	var definitions: Array[WeaponExtensionDefinition] = ExtensionInventory.get_all_definitions()
	for index in range(definitions.size()):
		order[definitions[index].get_id()] = index
	items.sort_custom(func(a: WeaponExtensionItem, b: WeaponExtensionItem) -> bool:
		var def_a: int = int(order.get(a.get_definition_id(), 99))
		var def_b: int = int(order.get(b.get_definition_id(), 99))
		if def_a != def_b:
			return def_a < def_b
		if a.mark != b.mark:
			return a.mark > b.mark
		if not is_equal_approx(a.condition, b.condition):
			return a.condition > b.condition
		return a.get_instance_id() < b.get_instance_id())
	return items


func _sorted_armor() -> Array[ArmorItemData]:
	var items: Array[ArmorItemData] = []
	for item in ArmorInventory.inventory:
		if item != null:
			items.append(item)
	for category in ArmorItemData.category_ids():
		var equipped: ArmorItemData = ArmorInventory.get_equipped_item(category)
		if equipped != null and not items.has(equipped):
			items.append(equipped)
	items.sort_custom(func(a: ArmorItemData, b: ArmorItemData) -> bool:
		var base_a: String = LoadoutStyle.base_name(a.get_hover_title())
		var base_b: String = LoadoutStyle.base_name(b.get_hover_title())
		if base_a != base_b:
			return base_a < base_b
		if a.get_mark() != b.get_mark():
			return a.get_mark() > b.get_mark()
		return a.get_instance_id() < b.get_instance_id())
	return items


## Fills every locker section. Tile nodes are reused so hover state and focus survive refreshes.
func _fill_locker() -> void:
	var equipped_extensions: Array = ExtensionInventory.get_equipped_for_local().values()
	var total: int = 0
	for slot in SLOT_ORDER:
		var section: Dictionary = _sections[slot]
		var items: Array = _owned_items(slot)
		section["count"] = items.size()
		total += items.size()
		var pool: Array[LoadoutItemTile] = section["tiles"]
		while pool.size() < items.size():
			var tile: LoadoutItemTile = LoadoutItemTile.new()
			tile.set_tile_size(Vector2(_tile_width(), _tile_width()))
			tile.inspected.connect(_on_tile_inspected)
			tile.activated.connect(_on_tile_activated)
			tile.secondary_activated.connect(_on_tile_secondary)
			tile.merge_requested.connect(_on_merge_requested)
			(section["grid"] as GridContainer).add_child(tile)
			pool.append(tile)
		for index in range(pool.size()):
			var tile: LoadoutItemTile = pool[index]
			tile.visible = index < items.size()
			if index >= items.size():
				tile.setup(null)
				continue
			var item: Variant = items[index]
			if item is WeaponExtensionItem:
				var is_equipped: bool = equipped_extensions.has(item)
				tile.setup(item, is_equipped, not is_equipped and ExtensionInventory.has_merge_partner_for_local(item))
			else:
				var is_worn: bool = ArmorInventory.get_equipped_item((item as ArmorItemData).category) == item
				tile.setup(item, is_worn, not is_worn and ArmorInventory.has_merge_partner_for_local(item))
		(section["box"] as Control).visible = items.size() > 0 and (_filter == &"" or _filter == slot)
		(section["header"] as Control).queue_redraw()
	_update_empty_state(total)


func _tile_width() -> float:
	var content: float = DOCK_WIDTH - DOCK_PAD * 2.0
	return floorf((content - float(GRID_GAP * (GRID_COLUMNS - 1))) / float(GRID_COLUMNS))


func _update_empty_state(total: int) -> void:
	var shown: int = total if _filter == &"" else int(_sections[_filter]["count"])
	_empty_label.visible = shown == 0
	if total == 0:
		_empty_label.text = "Your locker is empty.\nBuy parts above, or drag an offer straight onto your build." if _shop_enabled else "Nothing in the locker."
	else:
		_empty_label.text = "No %s parts yet." % LoadoutStyle.slot_label(_filter).to_lower()


func _refresh_shop() -> void:
	if _recycler != null:
		_recycler.refresh()
	if not _shop_enabled:
		return
	var saved_count: int = ResearchManager.get_blueprint_slot_count()
	var saved_visible: bool = saved_count > 0 or (_recycler != null and _recycler.visible)
	_saved_row.visible = saved_visible
	_saved_caption.text = "SAVED BLUEPRINTS" if saved_count > 0 else "RECYCLE"
	for tile in _offer_tiles:
		tile.setup_reward(RoundRewardInventory.SOURCE_OFFER, tile.source_index, RoundRewardInventory.get_offer(tile.source_index))
	for tile in _saved_tiles:
		tile.visible = tile.source_index < saved_count
		tile.setup_reward(RoundRewardInventory.SOURCE_SAVED, tile.source_index, RoundRewardInventory.get_saved_reward(tile.source_index))
	_refresh_coins()


func _refresh_coins() -> void:
	if _coin_label != null:
		var balance: int = OnlineMatch.get_local_coin_balance()
		if _coin_value >= 0 and balance != _coin_value:
			_pop_label(_coin_label, 1.18)
		_coin_value = balance
		_coin_label.text = "%d" % balance
		(_coin_label.get_meta("box") as Control).queue_redraw()
	for tile in _offer_tiles:
		tile.refresh_affordability()
	for tile in _saved_tiles:
		tile.refresh_affordability()


func _pop_label(label: Control, amount: float) -> void:
	label.scale = Vector2.ONE * amount
	label.create_tween().tween_property(label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _update_tabs() -> void:
	for filter in _filter_tabs.keys():
		var tab: Button = _filter_tabs[filter]
		tab.set_pressed_no_signal(filter == _filter)
	_weapon_bay.set_linked_slot(_filter if _filter in WEAPON_SLOTS else &"")
	_operator.set_linked_slot(_filter if _filter in ARMOR_SLOTS else &"")


func _set_filter(filter: StringName) -> void:
	if filter == _filter and filter != &"":
		filter = &""
	_filter = filter
	AudioDirector.play(&"ui_toggle", -4.0)
	_fill_locker()
	_update_tabs()
	_locker_scroll.scroll_vertical = 0


## A socket on the bench was clicked: show its parts in the locker (clicking again shows everything).
func _select_slot(slot: StringName) -> void:
	_set_filter(slot)
	if slot in WEAPON_SLOTS:
		_weapon_bay.flash_slot(slot)
	else:
		_operator.flash_slot(slot)


# --- Stats -----------------------------------------------------------------------------------------------

func _update_weapon_stats(animate: bool) -> void:
	_weapon_stats.set_stats(_weapon_stat_entries(_get_current_weapon_modifiers()), animate)


func _update_armor_stats(animate: bool) -> void:
	_armor_stats.set_stats(_armor_stat_entries(ArmorInventory.get_scaled_attributes()), animate)


func _weapon_stat_entries(modifiers: Dictionary) -> Array:
	return [
		{"key": &"damage", "label": "DAMAGE", "value": _weapon_display_value(&"damage", modifiers), "max": 45.0, "text": func(v: float) -> String: return "%d" % int(roundf(v))},
		{"key": &"fire_interval", "label": "FIRE RATE", "value": _weapon_display_value(&"fire_interval", modifiers), "max": 4.0, "text": func(v: float) -> String: return "%.1f/s" % v},
		{"key": &"reload_time", "label": "RELOAD", "value": _weapon_display_value(&"reload_time", modifiers), "max": 2.4, "lower_is_better": true, "text": func(v: float) -> String: return "%.2fs" % v},
		{"key": &"ammo_max", "label": "AMMO", "value": _weapon_display_value(&"ammo_max", modifiers), "max": 6.0, "text": func(v: float) -> String: return "%d" % int(roundf(v))},
		{"key": &"projectile_speed", "label": "VELOCITY", "value": _weapon_display_value(&"projectile_speed", modifiers), "max": 2000.0, "text": func(v: float) -> String: return "%d" % int(roundf(v))},
	]


func _armor_stat_entries(modifiers: Dictionary) -> Array:
	return [
		{"key": &"max_health", "label": "HEALTH", "value": _armor_display_value(&"max_health", modifiers), "max": 160.0, "text": func(v: float) -> String: return "%d" % int(roundf(v))},
		{"key": &"move_speed", "label": "SPEED", "value": _armor_display_value(&"move_speed", modifiers), "max": 340.0, "text": func(v: float) -> String: return "%d" % int(roundf(v))},
		{"key": &"jump_velocity", "label": "JUMP", "value": GameSettings.PLAYER_JUMP_VELOCITY + float(modifiers.get(&"jump_velocity", 0.0)), "max": 700.0, "text": func(v: float) -> String: return "%d" % int(roundf(v))},
		{"key": &"damage_reduction", "label": "ARMOR", "value": float(modifiers.get(&"damage_reduction", 0.0)), "max": 8.0, "text": func(v: float) -> String: return "%.1f" % v if absf(v - roundf(v)) > 0.05 else "%d" % int(roundf(v))},
	]


func _preview_weapon(item: WeaponExtensionItem) -> void:
	if item == null or _is_weapon_extension_equipped(item):
		_weapon_stats.set_preview({})
		_weapon_bay.set_preview(null)
		return
	var preview: Dictionary = _build_weapon_preview_modifiers(item, _get_current_weapon_modifiers())
	var values: Dictionary = {}
	for entry in _weapon_stat_entries(preview):
		values[entry["key"]] = entry["value"]
	_weapon_stats.set_preview(values)
	_weapon_bay.set_preview(item)


func _preview_armor(item: ArmorItemData) -> void:
	if item == null or ArmorInventory.get_equipped_item(item.category) == item:
		_armor_stats.set_preview({})
		_operator.set_preview(null)
		return
	var preview: Dictionary = _build_armor_preview_modifiers(item, ArmorInventory.get_scaled_attributes())
	var values: Dictionary = {}
	for entry in _armor_stat_entries(preview):
		values[entry["key"]] = entry["value"]
	_armor_stats.set_preview(values)
	_operator.set_preview(item)


# --- Nameplates ------------------------------------------------------------------------------------------

func _show_overview() -> void:
	_inspecting = false
	_weapon_stats.set_preview({})
	_armor_stats.set_preview({})
	_weapon_bay.set_preview(null)
	_operator.set_preview(null)
	_show_weapon_default()
	_show_armor_default()
	_set_prompts(_default_prompts())


func _show_weapon_default() -> void:
	var mods: int = 0
	for slot in WEAPON_SLOTS:
		if ExtensionInventory.get_equipped_item_for_local(slot) != null:
			mods += 1
	var state: String = "STOCK" if mods == 0 else "%d OF 3 MODS FITTED" % mods
	_weapon_plate.show_content("B7 CARBINE", [[state, LoadoutStyle.TEXT_SECONDARY]], "")


func _show_armor_default() -> void:
	var worn: int = 0
	for category in ARMOR_SLOTS:
		if ArmorInventory.get_equipped_item(category) != null:
			worn += 1
	var color_name: String = OnlineMatch.get_player_color_name(ExtensionInventory.get_local_player_slot()).to_upper()
	var state: String = "NO ARMOR" if worn == 0 else "%d OF 3 PIECES" % worn
	_armor_plate.show_content("OPERATOR", [[color_name, LoadoutStyle.local_accent()], [state, LoadoutStyle.TEXT_SECONDARY]], "")


func _item_segments(item: Variant, price: int = -1) -> Array:
	var info: Dictionary = LoadoutStyle.item_info(item)
	var segments: Array = [[LoadoutStyle.slot_label(info["slot"]), LoadoutStyle.TEXT_MUTED], ["MK " + LoadoutStyle.roman(int(info["mark"])), LoadoutStyle.TEXT_SECONDARY]]
	segments.append(["%s  %d%%" % [str(info["grade"]).to_upper(), int(roundf(float(info["condition"])))], info["color"]])
	if price >= 0:
		segments.append([str(price), LoadoutStyle.COIN if OnlineMatch.get_local_coin_balance() >= price else LoadoutStyle.NEGATIVE, "coin"])
	return segments


func _short_description(description: String) -> String:
	if description.is_empty():
		return ""
	var sentences: PackedStringArray = description.split(". ")
	return sentences[0] + ("" if sentences[0].ends_with(".") else ".")


## While something is being dragged the bench keeps showing the dragged item.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary:
			var dragged: Variant = (data as Dictionary).get("item", null)
			var price: int = -1
			if StringName(str((data as Dictionary).get("type", ""))) == &"round_reward":
				price = RoundRewardInventory.get_reward_price(StringName(str(data.get("source_kind", ""))), int(data.get("source_index", -1)))
			if dragged is WeaponExtensionItem:
				_inspect_extension(dragged, _is_weapon_extension_equipped(dragged), price)
			elif dragged is ArmorItemData:
				_inspect_armor(dragged, ArmorInventory.get_equipped_item((dragged as ArmorItemData).category) == dragged, price)
			var from_slot: bool = StringName(str((data as Dictionary).get("source", ""))) == &"slot"
			_set_prompts([["DROP", "Off the bench to remove"]] if from_slot else [["DROP", "On the build to fit" if price < 0 else "On the build to buy and fit"]])
	elif what == NOTIFICATION_DRAG_END:
		_set_prompts(_default_prompts())
		if _inspecting:
			_hover_clear_timer = HOVER_CLEAR_DELAY


func _dragging() -> bool:
	return is_inside_tree() and get_viewport().gui_is_dragging()


func _on_tile_inspected(tile: LoadoutItemTile) -> void:
	if _dragging():
		return
	AudioDirector.play(&"loadout_hover")
	if tile.item is WeaponExtensionItem:
		_inspect_extension(tile.item, tile.equipped)
	elif tile.item is ArmorItemData:
		_inspect_armor(tile.item, tile.equipped)
	_set_prompts(_item_prompts(tile.equipped, tile.merge_ready, -1))


func _inspect_extension(item: WeaponExtensionItem, equipped: bool, price: int = -1) -> void:
	if item == null or item.definition == null:
		return
	_inspecting = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	var effects: Array = []
	if equipped:
		effects = _effect_segments({}, item.build_effective_stats().get("attributes", {}), true)
	else:
		var current: Dictionary = _get_current_weapon_modifiers()
		effects = _effect_segments(current, _build_weapon_preview_modifiers(item, current), true)
	_weapon_plate.show_content(LoadoutStyle.item_info(item)["name"].to_upper(), _item_segments(item, price), _short_description(item.definition.description), effects)
	_show_armor_default()
	_armor_stats.set_preview({})
	_operator.set_preview(null)
	_preview_weapon(null if equipped else item)


func _inspect_armor(item: ArmorItemData, equipped: bool, price: int = -1) -> void:
	if item == null:
		return
	_inspecting = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	var effects: Array = []
	if equipped:
		effects = _effect_segments({}, item.get_scaled_attributes(), false)
	else:
		var current: Dictionary = ArmorInventory.get_scaled_attributes()
		effects = _effect_segments(current, _build_armor_preview_modifiers(item, current), false)
	_armor_plate.show_content(LoadoutStyle.item_info(item)["name"].to_upper(), _item_segments(item, price), _short_description(item.description), effects)
	_show_weapon_default()
	_weapon_stats.set_preview({})
	_weapon_bay.set_preview(null)
	_preview_armor(null if equipped else item)


func _inspect_weapon_slot(slot: StringName) -> void:
	if _dragging():
		return
	var item: WeaponExtensionItem = ExtensionInventory.get_equipped_item_for_local(slot)
	if item != null:
		_inspect_extension(item, true)
	else:
		_inspecting = true
		_hover_clear_timer = HOVER_CLEAR_DELAY
		_weapon_plate.show_content(LoadoutStyle.slot_label(slot), [["EMPTY", LoadoutStyle.TEXT_MUTED], [_owned_text(slot), LoadoutStyle.TEXT_SECONDARY]], "")
		_preview_weapon(null)
	_set_prompts(_socket_prompts(item != null))


func _inspect_armor_slot(category: StringName) -> void:
	if _dragging():
		return
	var item: ArmorItemData = ArmorInventory.get_equipped_item(category)
	if item != null:
		_inspect_armor(item, true)
	else:
		_inspecting = true
		_hover_clear_timer = HOVER_CLEAR_DELAY
		_armor_plate.show_content(LoadoutStyle.slot_label(category), [["EMPTY", LoadoutStyle.TEXT_MUTED], [_owned_text(category), LoadoutStyle.TEXT_SECONDARY]], "")
		_preview_armor(null)
	_set_prompts(_socket_prompts(item != null))


func _owned_text(slot: StringName) -> String:
	var count: int = _owned_items(slot).size()
	return "NONE IN THE LOCKER" if count == 0 else "%d IN THE LOCKER" % count


func _on_reward_inspected(tile: LoadoutItemTile) -> void:
	if _dragging():
		return
	AudioDirector.play(&"loadout_hover")
	var reward_tile: LoadoutRewardTile = tile as LoadoutRewardTile
	if reward_tile == null or reward_tile.reward.is_empty():
		return
	var price: int = int(reward_tile.reward.get("price", 0))
	if reward_tile.item is WeaponExtensionItem:
		_inspect_extension(reward_tile.item, false, price)
	elif reward_tile.item is ArmorItemData:
		_inspect_armor(reward_tile.item, false, price)
	_set_prompts(_item_prompts(false, false, price))


# --- Prompts ---------------------------------------------------------------------------------------------

func _on_device_changed(_using_gamepad: bool) -> void:
	_set_prompts(_default_prompts())


func _pad() -> bool:
	return InputDevice.using_gamepad


func _default_prompts() -> Array:
	if _pad():
		return [["A", "Fit / take off"], ["B", "Back"]]
	var prompts: Array = [["LMB", "Fit / take off"], ["RMB", "Take off"], ["DRAG", "Onto the build"]]
	if not _shop_enabled:
		prompts.append(["ESC", "Back"])
	return prompts


func _item_prompts(equipped: bool, merge_ready: bool, price: int) -> Array:
	if price >= 0:
		return [["A" if _pad() else "LMB", "Buy"], ["DRAG", "Onto the build to buy and fit"]] if not _pad() else [["A", "Buy"]]
	var prompts: Array = []
	if equipped:
		prompts.append(["A" if _pad() else "LMB", "Take off"])
	else:
		prompts.append(["A" if _pad() else "LMB", "Fit"])
		if merge_ready and not _pad():
			prompts.append(["DRAG", "Onto its twin to merge"])
	return prompts


func _socket_prompts(filled: bool) -> Array:
	var prompts: Array = [["LMB", "Show matching parts"]]
	if filled:
		prompts.append(["RMB", "Take off"])
	return prompts


func _set_prompts(prompts: Array) -> void:
	_prompt_bar.set_prompts(prompts)


func _notify(text: String, color: Color) -> void:
	_prompt_bar.notify(text, color)


# --- Actions ---------------------------------------------------------------------------------------------

func _on_tile_activated(tile: LoadoutItemTile) -> void:
	if tile.item is WeaponExtensionItem:
		if tile.equipped:
			_unequip_extension_slot((tile.item as WeaponExtensionItem).get_slot())
		else:
			_equip_extension(tile.item)
	elif tile.item is ArmorItemData:
		if tile.equipped:
			_unequip_armor_category((tile.item as ArmorItemData).category)
		else:
			_equip_armor(tile.item)
	if is_instance_valid(tile) and tile.is_hovered_tile():
		_set_prompts(_item_prompts(tile.equipped, tile.merge_ready, -1))


func _on_tile_secondary(tile: LoadoutItemTile) -> void:
	if not tile.equipped:
		return
	_on_tile_activated(tile)


func _equip_extension(item: WeaponExtensionItem) -> void:
	if item == null or _is_weapon_extension_equipped(item):
		return
	_animate_changes = true
	if ExtensionInventory.equip_item_for_local(item):
		AudioDirector.play(&"loadout_snap")
		_pop_tile_for(item)
	_animate_changes = false
	_inspect_extension(item, true)


func _unequip_extension_slot(slot: StringName) -> void:
	var item: WeaponExtensionItem = ExtensionInventory.get_equipped_item_for_local(slot)
	if item == null:
		return
	_animate_changes = true
	ExtensionInventory.unequip_local(slot)
	_animate_changes = false
	AudioDirector.play(&"loadout_detach")
	_pop_tile_for(item)
	_inspect_weapon_slot(slot)


func _equip_armor(item: ArmorItemData) -> void:
	if item == null or ArmorInventory.get_equipped_item(item.category) == item:
		return
	_animate_changes = true
	ArmorInventory.equip_item(item)
	_animate_changes = false
	AudioDirector.play(&"loadout_armor")
	_pop_tile_for(item)
	_inspect_armor(item, true)


func _unequip_armor_category(category: StringName) -> void:
	var item: ArmorItemData = ArmorInventory.get_equipped_item(category)
	if item == null:
		return
	_animate_changes = true
	ArmorInventory.unequip_category(category)
	_animate_changes = false
	AudioDirector.play(&"loadout_detach")
	_pop_tile_for(item)
	_inspect_armor_slot(category)


func _pop_tile_for(item: Variant) -> void:
	for slot in SLOT_ORDER:
		for tile in _sections[slot]["tiles"]:
			if tile.visible and tile.item == item:
				tile.pop()
				return


func _on_extension_inventory_changed(player_slot: int) -> void:
	if player_slot != ExtensionInventory.get_local_player_slot():
		return
	_fill_locker()


func _on_extension_loadout_changed(player_slot: int) -> void:
	if player_slot != ExtensionInventory.get_local_player_slot():
		return
	_refresh_weapon(_animate_changes)


func _on_armor_changed() -> void:
	_refresh_armor(_animate_changes)


func unequip_from_inventory_drop(payload: Dictionary) -> void:
	var item: Variant = payload.get("item", null)
	if item is WeaponExtensionItem and _is_weapon_extension_equipped(item):
		_unequip_extension_slot((item as WeaponExtensionItem).get_slot())
	elif item is ArmorItemData and ArmorInventory.get_equipped_item((item as ArmorItemData).category) == item:
		_unequip_armor_category((item as ArmorItemData).category)
	elif StringName(str(payload.get("type", ""))) == &"round_reward":
		_on_reward_claimed(StringName(str(payload.get("source_kind", ""))), int(payload.get("source_index", -1)))


# --- Shop ------------------------------------------------------------------------------------------------

func _refuse_purchase(price: int) -> void:
	AudioDirector.play(&"shop_denied")
	_notify("NEED %d COINS  ·  YOU HAVE %d" % [price, OnlineMatch.get_local_coin_balance()], LoadoutStyle.NEGATIVE)
	if _coin_label != null:
		_coin_label.modulate = Color(1.0, 0.45, 0.42)
		_coin_label.create_tween().tween_property(_coin_label, "modulate", Color.WHITE, 0.5)


func _on_reward_claimed(source_kind: StringName, source_index: int) -> void:
	var price: int = RoundRewardInventory.get_reward_price(source_kind, source_index)
	if not RoundRewardInventory.can_afford_reward(source_kind, source_index):
		_refuse_purchase(price)
		return
	var item: Variant = _reward_item(source_kind, source_index)
	if RoundRewardInventory.claim_reward(source_kind, source_index):
		AudioDirector.play(&"shop_purchase")
		_notify("BOUGHT %s  ·  −%d" % [str(LoadoutStyle.item_info(item).get("name", "BLUEPRINT")).to_upper(), price], LoadoutStyle.POSITIVE)
		if item != null:
			_reveal_in_locker(item)


func _reward_item(source_kind: StringName, source_index: int) -> Variant:
	var reward: Dictionary = RoundRewardInventory.get_offer(source_index) if source_kind == RoundRewardInventory.SOURCE_OFFER else RoundRewardInventory.get_saved_reward(source_index)
	return reward.get("item", null)


## Shows a freshly bought part where it landed: its section comes into view and the card pops.
func _reveal_in_locker(item: Variant) -> void:
	var slot: StringName = StringName(str(LoadoutStyle.item_info(item).get("slot", "")))
	if _filter != &"" and _filter != slot:
		_set_filter(&"")
	await get_tree().process_frame
	for tile in _sections.get(slot, {}).get("tiles", []):
		if tile.visible and tile.item == item:
			tile.pop()
			_locker_scroll.ensure_control_visible(tile)
			return


func _on_weapon_reward_dropped(payload: Dictionary, target_slot: StringName) -> void:
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	var item: WeaponExtensionItem = payload.get("item", null) as WeaponExtensionItem
	if item == null or item.get_slot() != target_slot:
		return
	var price: int = RoundRewardInventory.get_reward_price(source_kind, source_index)
	if not RoundRewardInventory.can_afford_reward(source_kind, source_index):
		_refuse_purchase(price)
		return
	if not RoundRewardInventory.claim_reward(source_kind, source_index):
		return
	AudioDirector.play(&"shop_purchase")
	_notify("BOUGHT AND FITTED  ·  −%d" % price, LoadoutStyle.POSITIVE)
	_equip_extension(item)


func _on_armor_reward_dropped(payload: Dictionary) -> void:
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	var item: ArmorItemData = payload.get("item", null) as ArmorItemData
	if item == null:
		return
	var price: int = RoundRewardInventory.get_reward_price(source_kind, source_index)
	if not RoundRewardInventory.can_afford_reward(source_kind, source_index):
		_refuse_purchase(price)
		return
	if not RoundRewardInventory.claim_reward(source_kind, source_index):
		return
	AudioDirector.play(&"shop_purchase")
	_notify("BOUGHT AND FITTED  ·  −%d" % price, LoadoutStyle.POSITIVE)
	_equip_armor(item)


func _on_reward_moved(payload: Dictionary, target_kind: StringName, target_index: int) -> void:
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	var moved: bool = false
	if target_kind == RoundRewardInventory.SOURCE_SAVED:
		moved = RoundRewardInventory.move_to_saved(source_kind, source_index, target_index)
	else:
		moved = RoundRewardInventory.move_to_offer(source_kind, source_index, target_index)
	if moved:
		AudioDirector.play(&"item_move")
		if target_kind == RoundRewardInventory.SOURCE_SAVED:
			_notify("BLUEPRINT SAVED FOR LATER", LoadoutStyle.TEXT)


func _on_reward_recycled(refund: int) -> void:
	AudioDirector.play(&"recycle")
	_notify("RECYCLED  ·  +%d" % refund, LoadoutStyle.POSITIVE)


# --- Merging ---------------------------------------------------------------------------------------------

func _on_merge_requested(source: Variant, target: Variant) -> void:
	if source is WeaponExtensionItem and target is WeaponExtensionItem:
		_request_extension_merge(source, target)
	elif source is ArmorItemData and target is ArmorItemData:
		_request_armor_merge(source, target)


func _request_extension_merge(source_item: WeaponExtensionItem, target_item: WeaponExtensionItem) -> void:
	if not ExtensionInventory.can_merge_items(source_item, target_item):
		_show_merge_error("ONLY TWO OF THE SAME PART AND MARK CAN MERGE")
		return
	var next_mark: int = source_item.mark + 1
	var cost: int = ExtensionInventory.get_merge_cost_for_items(source_item, target_item)
	if OnlineMatch.get_local_coin_balance() < cost:
		_show_not_enough_merge_coins(next_mark, cost, "extensions")
		return
	_pending_armor_merge_source = null
	_pending_armor_merge_target = null
	_pending_merge_source = source_item
	_pending_merge_target = target_item
	_merge_dialog.show_merge("WEAPON PART", "MERGE INTO MK %s" % LoadoutStyle.roman(next_mark), source_item, target_item, next_mark, cost, OnlineMatch.get_local_coin_balance())


func _request_armor_merge(source_item: ArmorItemData, target_item: ArmorItemData) -> void:
	if not ArmorInventory.can_merge_items(source_item, target_item):
		_show_merge_error("ONLY TWO OF THE SAME PIECE AND MARK CAN MERGE")
		return
	var next_mark: int = source_item.get_mark() + 1
	var cost: int = ArmorInventory.get_merge_cost_for_items(source_item, target_item)
	if OnlineMatch.get_local_coin_balance() < cost:
		_show_not_enough_merge_coins(next_mark, cost, "armor")
		return
	_pending_merge_source = null
	_pending_merge_target = null
	_pending_armor_merge_source = source_item
	_pending_armor_merge_target = target_item
	_merge_dialog.show_merge("ARMOR", "MERGE INTO MK %s" % LoadoutStyle.roman(next_mark), source_item, target_item, next_mark, cost, OnlineMatch.get_local_coin_balance())


func _confirm_pending_merge() -> void:
	if _pending_armor_merge_source != null:
		var armor_source: ArmorItemData = _pending_armor_merge_source
		var armor_target: ArmorItemData = _pending_armor_merge_target
		_pending_armor_merge_source = null
		_pending_armor_merge_target = null
		var armor_cost: int = ArmorInventory.get_merge_cost_for_items(armor_source, armor_target)
		var merged_armor: ArmorItemData = ArmorInventory.try_merge_items_for_local(armor_source, armor_target)
		if merged_armor == null:
			_show_merge_error("MERGE FAILED  ·  CHECK COINS AND MARKS")
			return
		AudioDirector.play(&"merge")
		_refresh_coins()
		_pop_tile_for(merged_armor)
		_inspect_armor(merged_armor, false)
		_notify("MERGED INTO MK %s  ·  −%d" % [LoadoutStyle.roman(merged_armor.get_mark()), armor_cost], LoadoutStyle.ACCENT)
		return
	var source: WeaponExtensionItem = _pending_merge_source
	var target: WeaponExtensionItem = _pending_merge_target
	_pending_merge_source = null
	_pending_merge_target = null
	if source == null or target == null:
		return
	var cost: int = ExtensionInventory.get_merge_cost_for_items(source, target)
	var merged: WeaponExtensionItem = ExtensionInventory.try_merge_items_for_local(source, target)
	if merged == null:
		_show_merge_error("MERGE FAILED  ·  CHECK COINS AND MARKS")
		return
	AudioDirector.play(&"merge")
	_refresh_coins()
	_pop_tile_for(merged)
	_inspect_extension(merged, false)
	_notify("MERGED INTO MK %s  ·  −%d" % [LoadoutStyle.roman(merged.mark), cost], LoadoutStyle.ACCENT)


func _cancel_pending_merge() -> void:
	_pending_merge_source = null
	_pending_merge_target = null
	_pending_armor_merge_source = null
	_pending_armor_merge_target = null
	_merge_dialog.hide_dialog()


func _show_merge_error(text: String) -> void:
	AudioDirector.play(&"shop_denied")
	_notify(text, LoadoutStyle.NEGATIVE)


func _show_not_enough_merge_coins(next_mark: int, cost: int, label: String) -> void:
	var body: String = "Merging into MK%d costs %d coins. You have %d." % [next_mark, cost, OnlineMatch.get_local_coin_balance()]
	_refuse_purchase(cost)
	_merge_dialog.show_coin_warning(body, label)


# --- Stat helpers ----------------------------------------------------------------------------------------

func _get_current_weapon_modifiers() -> Dictionary:
	var stats: Dictionary = ExtensionInventory.build_effective_stats_for_player(ExtensionInventory.get_local_player_slot())
	var attributes: Variant = stats.get("attributes", {})
	return (attributes as Dictionary).duplicate() if attributes is Dictionary else {}


func _is_weapon_extension_equipped(item: WeaponExtensionItem) -> bool:
	return item != null and ExtensionInventory.get_equipped_item_for_local(item.get_slot()) == item


func _build_weapon_preview_modifiers(item: WeaponExtensionItem, current: Dictionary) -> Dictionary:
	var preview: Dictionary = current.duplicate()
	var equipped_item: WeaponExtensionItem = ExtensionInventory.get_equipped_item_for_local(item.get_slot())
	if equipped_item != null:
		_apply_numeric_modifiers(preview, equipped_item.build_effective_stats().get("attributes", {}), -1.0)
	_apply_numeric_modifiers(preview, item.build_effective_stats().get("attributes", {}), 1.0)
	return preview


func _build_armor_preview_modifiers(item: ArmorItemData, current: Dictionary) -> Dictionary:
	var preview: Dictionary = current.duplicate()
	var equipped_item: ArmorItemData = ArmorInventory.get_equipped_item(item.category)
	if equipped_item != null:
		_apply_numeric_modifiers(preview, equipped_item.get_scaled_attributes(), -1.0)
	_apply_numeric_modifiers(preview, item.get_scaled_attributes(), 1.0)
	return preview


func _apply_numeric_modifiers(target: Dictionary, incoming_variant: Variant, factor: float) -> void:
	if not (incoming_variant is Dictionary):
		return
	var incoming: Dictionary = incoming_variant
	for raw_key in incoming.keys():
		var value: Variant = incoming[raw_key]
		if value is int or value is float:
			var key: StringName = StringName(str(raw_key))
			target[key] = float(target.get(key, 0.0)) + float(value) * factor


## The effects of an item the stat strip does not show, as coloured "Name +delta" segments.
func _effect_segments(before: Dictionary, after: Dictionary, weapon: bool) -> Array:
	var segments: Array = []
	var priority: Array[StringName] = WEAPON_STAT_PRIORITY if weapon else ARMOR_STAT_PRIORITY
	var strip: Array[StringName] = WEAPON_STRIP_KEYS if weapon else ARMOR_STRIP_KEYS
	for key in _ordered_changed_keys(before, after, priority):
		if strip.has(key):
			continue
		var before_value: float = _weapon_display_value(key, before) if weapon else _armor_display_value(key, before)
		var after_value: float = _weapon_display_value(key, after) if weapon else _armor_display_value(key, after)
		if is_equal_approx(before_value, after_value):
			continue
		var lower_better: bool = WEAPON_LOWER_IS_BETTER.has(key) if weapon else ARMOR_LOWER_IS_BETTER.has(key)
		var diff: float = after_value - before_value
		var better: bool = diff < 0.0 if lower_better else diff > 0.0
		var suffix: String = str((WEAPON_ATTRIBUTE_SUFFIXES if weapon else ARMOR_ATTRIBUTE_SUFFIXES).get(key, ""))
		var decimals: int = int((WEAPON_ATTRIBUTE_DECIMALS if weapon else ARMOR_ATTRIBUTE_DECIMALS).get(key, 0))
		var name: String = str((WEAPON_ATTRIBUTE_NAMES if weapon else ARMOR_ATTRIBUTE_NAMES).get(key, str(key).replace("_", " ").capitalize()))
		var sign: String = "+" if diff > 0.0 else "−"
		segments.append(["%s %s%s" % [name, sign, _format_value(absf(diff), suffix, decimals)], LoadoutStyle.POSITIVE if better else LoadoutStyle.NEGATIVE])
		if segments.size() >= MAX_EFFECTS:
			break
	return segments


func _format_value(value: float, suffix: String, decimals: int) -> String:
	var text: String = str(int(roundf(value)))
	if decimals == 1:
		text = "%.1f" % value
	elif decimals >= 2:
		text = "%.2f" % value
	return text + suffix


func _ordered_changed_keys(current: Dictionary, preview: Dictionary, priority: Array[StringName]) -> Array[StringName]:
	var result: Array[StringName] = []
	for key in priority:
		if _numeric_value_changed(key, current, preview):
			result.append(key)
	for source in [current, preview]:
		for raw_key in source.keys():
			var key: StringName = StringName(str(raw_key))
			if not result.has(key) and _numeric_value_changed(key, current, preview):
				result.append(key)
	return result


func _numeric_value_changed(key: StringName, current: Dictionary, preview: Dictionary) -> bool:
	var current_value: Variant = current.get(key, 0.0)
	var preview_value: Variant = preview.get(key, 0.0)
	if not (current_value is int or current_value is float) or not (preview_value is int or preview_value is float):
		return false
	return not is_equal_approx(float(current_value), float(preview_value))


func _weapon_display_value(attribute: StringName, modifiers: Dictionary) -> float:
	var modifier: float = float(modifiers.get(attribute, 0.0))
	match attribute:
		&"damage":
			return maxf(1.0, float(GameSettings.PROJECTILE_DAMAGE) + modifier)
		&"fire_interval":
			return 1.0 / maxf(0.03, GameSettings.GUN_FIRE_INTERVAL + modifier)
		&"reload_time":
			return maxf(0.1, BASE_RELOAD_TIME + modifier)
		&"ammo_max":
			return maxf(1.0, BASE_AMMO + modifier)
		&"projectile_speed":
			return maxf(1.0, GameSettings.GUN_PROJECTILE_SPEED + modifier)
		&"projectile_gravity":
			return GameSettings.GUN_PROJECTILE_GRAVITY + modifier
		&"projectile_linear_damping":
			return maxf(0.0, GameSettings.GUN_PROJECTILE_LINEAR_DAMPING + modifier)
		&"projectile_max_distance":
			return maxf(50.0, GameSettings.GUN_PROJECTILE_MAX_DISTANCE + modifier)
		&"projectile_scale":
			return maxf(0.1, 1.0 + modifier)
		&"shots_per_fire":
			return maxf(1.0, 1.0 + modifier)
		&"recoil_rotation_degrees":
			return maxf(0.0, GameSettings.GUN_RECOIL_ROTATION_DEGREES + modifier)
	return modifier


func _armor_display_value(attribute: StringName, modifiers: Dictionary) -> float:
	var modifier: float = float(modifiers.get(attribute, 0.0))
	match attribute:
		&"max_health":
			return float(GameSettings.DEFAULT_MAX_HEALTH) + modifier
		&"move_speed":
			return GameSettings.PLAYER_SPEED + modifier
		&"jump_velocity":
			return GameSettings.PLAYER_JUMP_VELOCITY + modifier
		&"freeze_resistance", &"reflect_chance", &"frosty_speed_multiplier":
			return modifier * 100.0
	return modifier


func _is_inspectable(control: Control) -> bool:
	var current: Control = control
	while current != null:
		if current is LoadoutItemTile or current is LoadoutSocketChip:
			return true
		if current is LoadoutWeaponBay or current is LoadoutOperatorStage:
			return true
		current = current.get_parent_control()
	return false


## True while a dialog on the page (the merge confirmation) owns Escape.
func is_modal_open() -> bool:
	return _merge_dialog != null and _merge_dialog.visible
