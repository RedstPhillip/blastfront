extends Control
class_name LoadoutPage

## The loadout: weapon workbench (left), details and shop (centre), operator and armor (right).
## Inventories keep a stable order and keep installed items in place (marked as installed) so the grid
## never reshuffles. Every change animates on the stages, updates the stat strips with counting numbers
## and plays a matching sound. Works in the sandbox pause menu (everything unlocked, no shop) and in the
## set intermission (shop, blueprints, recycler, merges).

const BASE_RELOAD_TIME: float = 1.2
const BASE_AMMO: float = 3.0
const COLUMN_GAP: int = 12
const WEAPON_COLUMN_WIDTH: float = 512.0
const CENTER_COLUMN_WIDTH: float = 280.0
const WEAPON_GRID_COLUMNS: int = 7
const ARMOR_GRID_COLUMNS: int = 6
const MIN_GRID_ROWS: int = 5
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
	&"damage": "Damage", &"fire_interval": "Fire rate", &"reload_time": "Reload time", &"ammo_max": "Ammo",
	&"projectile_speed": "Projectile speed", &"projectile_gravity": "Bullet drop", &"projectile_linear_damping": "Air resistance",
	&"projectile_max_distance": "Range", &"projectile_scale": "Projectile size", &"shots_per_fire": "Projectiles",
	&"shot_spread_degrees": "Spread", &"shot_random_spread_degrees": "Random spread", &"recoil_rotation_degrees": "Recoil",
}
const ARMOR_ATTRIBUTE_NAMES: Dictionary = {
	&"max_health": "Health", &"move_speed": "Movement speed", &"air_speed": "Air speed", &"jump_velocity": "Jump power",
	&"damage_reduction": "Protection", &"stationary_damage_reduction": "Still protection", &"freeze_resistance": "Freeze resist",
	&"reflect_chance": "Reflect chance", &"delayed_damage_duration": "Damage delay", &"block_strength": "Block strength",
	&"frosty_radius": "Frost radius", &"frosty_duration": "Frost duration", &"frosty_speed_multiplier": "Enemy speed",
	&"healing_radius": "Heal radius", &"healing_rate": "Healing", &"pull_radius": "Pull radius", &"pull_strength": "Pull force",
	&"instant_reload_on_block": "Block reload", &"adrenaline_duration": "Adrenaline time", &"adrenaline_speed_bonus": "Adrenaline speed",
	&"escape_speed_bonus": "Low HP speed", &"chase_speed_bonus": "Chase speed",
}
const WEAPON_ATTRIBUTE_SUFFIXES: Dictionary = {
	&"fire_interval": "/s", &"reload_time": "s", &"shot_spread_degrees": "°", &"shot_random_spread_degrees": "°", &"recoil_rotation_degrees": "°",
}
const ARMOR_ATTRIBUTE_SUFFIXES: Dictionary = {
	&"freeze_resistance": "%", &"reflect_chance": "%", &"frosty_speed_multiplier": "%", &"delayed_damage_duration": "s",
	&"frosty_duration": "s", &"adrenaline_duration": "s", &"healing_rate": "/s",
}
const WEAPON_ATTRIBUTE_DECIMALS: Dictionary = {&"fire_interval": 2, &"reload_time": 2, &"projectile_scale": 2}
const ARMOR_ATTRIBUTE_DECIMALS: Dictionary = {&"delayed_damage_duration": 1, &"frosty_duration": 1, &"adrenaline_duration": 1}
const WEAPON_LOWER_IS_BETTER: Array[StringName] = [
	&"reload_time", &"projectile_gravity", &"projectile_linear_damping", &"shot_spread_degrees", &"shot_random_spread_degrees", &"recoil_rotation_degrees",
]
const ARMOR_LOWER_IS_BETTER: Array[StringName] = [&"frosty_speed_multiplier"]
const WEAPON_FILTERS: Array[StringName] = [&"", &"front", &"middle", &"ammo"]
const ARMOR_FILTERS: Array[StringName] = [&"", &"shield", &"vest", &"boots"]
const HOVER_CLEAR_DELAY: float = 0.15

var _shop_enabled: bool = false
var _root_margin: MarginContainer = null
var _columns: Array[Control] = []
var _weapon_bay: LoadoutWeaponBay = null
var _operator: LoadoutOperatorStage = null
var _weapon_stats: LoadoutStatStrip = null
var _armor_stats: LoadoutStatStrip = null
var _weapon_grid: GridContainer = null
var _armor_grid: GridContainer = null
var _weapon_scroll: ScrollContainer = null
var _armor_scroll: ScrollContainer = null
var _weapon_filter: StringName = &""
var _armor_filter: StringName = &""
var _weapon_tabs: Dictionary = {}
var _armor_tabs: Dictionary = {}
var _weapon_tiles: Array[LoadoutItemTile] = []
var _armor_tiles: Array[LoadoutItemTile] = []
var _inspector: LoadoutInspector = null
var _coin_label: Label = null
var _offer_tiles: Array[LoadoutRewardTile] = []
var _saved_tiles: Array[LoadoutRewardTile] = []
var _recycler: LoadoutRecycler = null
var _saved_caption: Label = null
var _saved_row: Control = null
var _empty_labels: Dictionary = {}
var _merge_dialog: LoadoutMergeDialog = null
var _pending_merge: Array = []
var _inspecting: bool = false
var _hover_clear_timer: float = 0.0
var _animate_changes: bool = false
var _last_weapon_equipped: Dictionary = {}
var _last_armor_equipped: Dictionary = {}
var _opened: bool = false
var _backdrop: bool = true
var _prompt_bar: UiPromptBar = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_to_group(&"modal_ui")
	_shop_enabled = NetworkSession.uses_set_flow()
	_build_layout()
	_merge_dialog = LoadoutMergeDialog.new()
	add_child(_merge_dialog)
	_merge_dialog.confirmed.connect(_confirm_pending_merge)
	_merge_dialog.cancelled.connect(_cancel_pending_merge)
	_connect_inventory_signals()
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


## Leaves room above the columns, e.g. for the intermission tab bar.
## True while the merge dialog is up, so the intermission does not switch pages underneath it.
func is_modal_open() -> bool:
	return _merge_dialog != null and _merge_dialog.is_open()


func set_top_inset(pixels: float) -> void:
	if _root_margin != null:
		_root_margin.add_theme_constant_override("margin_top", int(pixels))


func _process(delta: float) -> void:
	if not _inspecting:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var focused: Control = get_viewport().gui_get_focus_owner()
	if _dragging() or _is_inspectable(hovered) or (focused is LoadoutItemTile and is_ancestor_of(focused)):
		_hover_clear_timer = HOVER_CLEAR_DELAY
		return
	_hover_clear_timer -= delta
	if _hover_clear_timer <= 0.0:
		_show_overview()


## The page washes the world behind it (the blurred match in the pause menu); a host that already draws
## the shared backdrop (the intermission) turns this off.
func set_backdrop(enabled: bool) -> void:
	_backdrop = enabled
	queue_redraw()


func _draw() -> void:
	if _backdrop:
		LoadoutStyle.draw_scrim(self, Rect2(Vector2.ZERO, size))


# --- Layout ----------------------------------------------------------------------------------------------

func _build_layout() -> void:
	_root_margin = MarginContainer.new()
	_root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		_root_margin.add_theme_constant_override(side, 16)
	_root_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root_margin)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", COLUMN_GAP)
	columns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root_margin.add_child(columns)
	columns.add_child(_build_weapon_column())
	columns.add_child(_build_center_column())
	columns.add_child(_build_armor_column())


func _column(width: float) -> VBoxContainer:
	var column: VBoxContainer = VBoxContainer.new()
	column.custom_minimum_size = Vector2(width, 0.0)
	column.add_theme_constant_override("separation", 8)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_columns.append(column)
	return column


func _header(title: String) -> Control:
	return LoadoutStyle.eyebrow(title)


func _build_weapon_column() -> Control:
	var column: VBoxContainer = _column(WEAPON_COLUMN_WIDTH)
	column.add_child(_header("WEAPON"))
	_weapon_bay = LoadoutWeaponBay.new()
	_weapon_bay.custom_minimum_size = Vector2(0.0, 236.0)
	_weapon_bay.part_dropped.connect(_equip_extension)
	_weapon_bay.merge_requested.connect(_on_merge_requested)
	_weapon_bay.reward_dropped.connect(_on_weapon_reward_dropped)
	_weapon_bay.part_removed.connect(_unequip_extension_slot)
	_weapon_bay.slot_selected.connect(func(slot: StringName) -> void: _set_weapon_filter(slot))
	_weapon_bay.slot_inspected.connect(_inspect_weapon_slot)
	column.add_child(_weapon_bay)
	_weapon_stats = LoadoutStatStrip.new()
	column.add_child(_weapon_stats)
	var labels: Dictionary = {&"": "ALL", &"front": "BARREL", &"middle": "OPTIC", &"ammo": "AMMO"}
	column.add_child(_build_filter_row("EXTENSIONS", WEAPON_FILTERS, labels, _weapon_tabs, _set_weapon_filter))
	var panel: Dictionary = _build_inventory_panel(WEAPON_GRID_COLUMNS, &"extension")
	_weapon_scroll = panel["scroll"]
	_weapon_grid = panel["grid"]
	column.add_child(panel["panel"])
	return column


func _build_center_column() -> Control:
	var column: VBoxContainer = _column(CENTER_COLUMN_WIDTH)
	column.add_child(_header("DETAILS"))
	_inspector = LoadoutInspector.new()
	if _shop_enabled:
		_inspector.preview_height = 70.0
		_inspector.row_count = 4
		_inspector.custom_minimum_size = Vector2(0.0, 300.0)
	else:
		_inspector.preview_height = 176.0
		_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_inspector)
	if _shop_enabled:
		column.add_child(_build_shop_panel())
	else:
		column.add_child(_build_tips_panel())
	return column


func _build_armor_column() -> Control:
	var column: VBoxContainer = _column(0.0)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(_header("OPERATOR"))
	_operator = LoadoutOperatorStage.new()
	_operator.custom_minimum_size = Vector2(0.0, 236.0)
	_operator.armor_dropped.connect(_equip_armor)
	_operator.merge_requested.connect(_on_merge_requested)
	_operator.reward_dropped.connect(_on_armor_reward_dropped)
	_operator.armor_removed.connect(_unequip_armor_category)
	_operator.slot_selected.connect(func(category: StringName) -> void: _set_armor_filter(category))
	_operator.slot_inspected.connect(_inspect_armor_slot)
	column.add_child(_operator)
	_armor_stats = LoadoutStatStrip.new()
	column.add_child(_armor_stats)
	var labels: Dictionary = {&"": "ALL", &"shield": "SHIELD", &"vest": "VEST", &"boots": "BOOTS"}
	column.add_child(_build_filter_row("ARMOR", ARMOR_FILTERS, labels, _armor_tabs, _set_armor_filter))
	var panel: Dictionary = _build_inventory_panel(ARMOR_GRID_COLUMNS, &"armor")
	_armor_scroll = panel["scroll"]
	_armor_grid = panel["grid"]
	column.add_child(panel["panel"])
	return column


func _build_filter_row(title: String, filters: Array[StringName], labels: Dictionary, store: Dictionary, callback: Callable) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 26.0)
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var caption: Label = LoadoutStyle.caption(title, LoadoutStyle.TEXT_SECONDARY, LoadoutStyle.EYEBROW_SIZE)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	for filter in filters:
		var tab: Button = Button.new()
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.custom_minimum_size = Vector2(0.0, 24.0)
		tab.set_meta("juice_feedback_connected", true)
		tab.set_meta("label", labels[filter])
		tab.add_theme_font_override("font", UiStyle.FONT_BOLD)
		tab.add_theme_font_size_override("font_size", 11)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
			var style: StyleBoxFlat = LoadoutStyle.flat(Color(0, 0, 0, 0), 0)
			if state in ["pressed", "hover_pressed"]:
				style.border_color = LoadoutStyle.ACCENT
				style.border_width_bottom = 2
			style.content_margin_left = 8.0
			style.content_margin_right = 8.0
			style.content_margin_bottom = 2.0
			tab.add_theme_stylebox_override(state, style)
		tab.add_theme_color_override("font_color", LoadoutStyle.TEXT_MUTED)
		tab.add_theme_color_override("font_hover_color", LoadoutStyle.TEXT_SECONDARY)
		tab.add_theme_color_override("font_pressed_color", LoadoutStyle.TEXT)
		tab.add_theme_color_override("font_hover_pressed_color", LoadoutStyle.TEXT)
		tab.pressed.connect(func() -> void: callback.call(filter))
		tab.mouse_entered.connect(func() -> void: AudioDirector.play(&"loadout_hover"))
		row.add_child(tab)
		store[filter] = tab
	return row


func _build_inventory_panel(columns: int, kind: StringName) -> Dictionary:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = LoadoutStyle.well()
	style.content_margin_left = 6.0
	style.content_margin_right = 4.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	panel.add_theme_stylebox_override("panel", style)
	var drop: LoadoutInventoryDrop = LoadoutInventoryDrop.new()
	drop.kind = kind
	drop.page = self
	drop.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(drop)
	var empty_label: Label = LoadoutStyle.label("Empty", UiStyle.FONT_BODY, 13, LoadoutStyle.TEXT_MUTED)
	empty_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	empty_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	empty_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.visible = false
	empty_label.z_index = 1
	drop.add_child(empty_label)
	_empty_labels[kind] = empty_label
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_style_scrollbar(scroll.get_v_scroll_bar())
	drop.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = columns
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER | Control.SIZE_EXPAND
	grid.add_theme_constant_override("h_separation", 7)
	grid.add_theme_constant_override("v_separation", 7)
	grid.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(grid)
	return {"panel": panel, "scroll": scroll, "grid": grid}


func _style_scrollbar(bar: VScrollBar) -> void:
	var track: StyleBoxFlat = LoadoutStyle.flat(Color(1, 1, 1, 0.03), 3)
	track.content_margin_left = 2.0
	track.content_margin_right = 2.0
	var grabber: StyleBoxFlat = LoadoutStyle.flat(Color(1, 1, 1, 0.22), 3)
	var grabber_hot: StyleBoxFlat = LoadoutStyle.flat(Color(1, 1, 1, 0.45), 3)
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grabber)
	bar.add_theme_stylebox_override("grabber_highlight", grabber_hot)
	bar.add_theme_stylebox_override("grabber_pressed", grabber_hot)
	bar.custom_minimum_size = Vector2(6.0, 0.0)


func _build_shop_panel() -> Control:
	var panel: PanelContainer = PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var style: StyleBoxFlat = LoadoutStyle.well()
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	panel.add_theme_stylebox_override("panel", style)
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var header: HBoxContainer = HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var title: Control = LoadoutStyle.eyebrow("SHOP", 22.0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coin_label = Label.new()
	UiStyle.style_label(_coin_label, UiStyle.FONT_DISPLAY, 16, WeaponArt.GOLD)
	header.add_child(_coin_label)
	var offers: GridContainer = GridContainer.new()
	offers.columns = 3
	offers.add_theme_constant_override("h_separation", 7)
	offers.add_theme_constant_override("v_separation", 7)
	offers.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(offers)
	for index in [0, 2, 4, 1, 3, 5]:
		var tile: LoadoutRewardTile = _make_reward_tile(RoundRewardInventory.SOURCE_OFFER, index)
		offers.add_child(tile)
		_offer_tiles.append(tile)
	_saved_caption = LoadoutStyle.caption("SAVED", LoadoutStyle.TEXT_MUTED, 10)
	column.add_child(_saved_caption)
	var saved_row: HBoxContainer = HBoxContainer.new()
	_saved_row = saved_row
	saved_row.add_theme_constant_override("separation", 7)
	column.add_child(saved_row)
	for index in range(RoundRewardInventory.MAX_SAVED_SLOT_COUNT):
		var saved: LoadoutRewardTile = _make_reward_tile(RoundRewardInventory.SOURCE_SAVED, index)
		saved_row.add_child(saved)
		_saved_tiles.append(saved)
	# Sell zone: parts and armor always, blueprints once Recycling is researched.
	_recycler = LoadoutRecycler.new()
	_recycler.sold.connect(_on_item_sold)
	column.add_child(_recycler)
	return panel


func _make_reward_tile(kind: StringName, index: int) -> LoadoutRewardTile:
	var tile: LoadoutRewardTile = LoadoutRewardTile.new()
	tile.source_kind = kind
	tile.source_index = index
	tile.inspected.connect(_on_reward_inspected)
	tile.reward_claimed.connect(_on_reward_claimed)
	tile.reward_moved.connect(_on_reward_moved)
	return tile


## The shared prompt bar, as on the other between-rounds pages.
func _build_tips_panel() -> Control:
	_prompt_bar = UiPromptBar.new()
	_prompt_bar.compact = true
	_prompt_bar.size_flags_vertical = Control.SIZE_SHRINK_END
	_prompt_bar.set_prompts([["LMB", "Install"], ["RMB", "Remove"], ["DRAG", "Move"]])
	return _prompt_bar


func _focus_first_tile() -> void:
	for tile in _weapon_tiles:
		if tile.visible and tile.item != null:
			tile.grab_focus()
			return


func _play_open() -> void:
	for index in range(_columns.size()):
		var column: Control = _columns[index]
		column.modulate.a = 0.0
		var tween: Tween = column.create_tween().set_parallel(true)
		tween.tween_property(column, "modulate:a", 1.0, 0.22).set_delay(0.04 * float(index))
		column.position.y = 14.0
		tween.tween_property(column, "position:y", 0.0, 0.32).set_delay(0.04 * float(index)).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# The carbine assembles itself once the bay has faded in.
	_weapon_bay.set_equipped({}, false)
	get_tree().create_timer(0.16, true, false, true).timeout.connect(func() -> void:
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
	_fill_weapon_grid()
	_update_weapon_stats(animate)
	_last_weapon_equipped = equipped
	if not _inspecting and _inspector != null:
		_show_overview()


func _refresh_armor(animate: bool) -> void:
	var equipped: Dictionary = {}
	for category in ArmorItemData.category_ids():
		equipped[category] = ArmorInventory.get_equipped_item(category)
	_operator.set_armor(equipped, animate)
	_fill_armor_grid()
	_update_armor_stats(animate)
	_last_armor_equipped = equipped
	if not _inspecting and _inspector != null:
		_show_overview()


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
	var slot_order: Dictionary = {&"front": 0, &"middle": 1, &"ammo": 2}
	items.sort_custom(func(a: WeaponExtensionItem, b: WeaponExtensionItem) -> bool:
		var slot_a: int = int(slot_order.get(a.get_slot(), 9))
		var slot_b: int = int(slot_order.get(b.get_slot(), 9))
		if slot_a != slot_b:
			return slot_a < slot_b
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
	var category_order: Dictionary = {&"shield": 0, &"vest": 1, &"boots": 2}
	items.sort_custom(func(a: ArmorItemData, b: ArmorItemData) -> bool:
		var cat_a: int = int(category_order.get(a.category, 9))
		var cat_b: int = int(category_order.get(b.category, 9))
		if cat_a != cat_b:
			return cat_a < cat_b
		var base_a: String = _base_name(a.get_hover_title())
		var base_b: String = _base_name(b.get_hover_title())
		if base_a != base_b:
			return base_a < base_b
		if a.get_mark() != b.get_mark():
			return a.get_mark() > b.get_mark()
		return a.get_instance_id() < b.get_instance_id())
	return items


func _fill_weapon_grid() -> void:
	var equipped: Array = ExtensionInventory.get_equipped_for_local().values()
	var shown: Array = []
	for item in _sorted_extensions():
		if _weapon_filter == &"" or item.get_slot() == _weapon_filter:
			shown.append(item)
	(_empty_labels[&"extension"] as Label).visible = shown.is_empty()
	_fill_grid(_weapon_grid, _weapon_tiles, shown, WEAPON_GRID_COLUMNS, func(tile: LoadoutItemTile, item: Variant) -> void:
		var extension: WeaponExtensionItem = item as WeaponExtensionItem
		var is_equipped: bool = extension != null and equipped.has(extension)
		tile.setup(extension, is_equipped, extension != null and not is_equipped and ExtensionInventory.has_merge_partner_for_local(extension)))


func _fill_armor_grid() -> void:
	var equipped: Array = []
	for category in ArmorItemData.category_ids():
		equipped.append(ArmorInventory.get_equipped_item(category))
	var shown: Array = []
	for item in _sorted_armor():
		if _armor_filter == &"" or item.category == _armor_filter:
			shown.append(item)
	(_empty_labels[&"armor"] as Label).visible = shown.is_empty()
	_fill_grid(_armor_grid, _armor_tiles, shown, ARMOR_GRID_COLUMNS, func(tile: LoadoutItemTile, item: Variant) -> void:
		var armor: ArmorItemData = item as ArmorItemData
		var is_equipped: bool = armor != null and equipped.has(armor)
		tile.setup(armor, is_equipped, armor != null and not is_equipped and ArmorInventory.has_merge_partner_for_local(armor)))


## Reuses tile nodes so hover state and focus survive refreshes; pads with empty cells to whole rows.
func _fill_grid(grid: GridContainer, pool: Array[LoadoutItemTile], items: Array, columns: int, apply: Callable) -> void:
	var rows: int = maxi(MIN_GRID_ROWS, ceili(float(items.size()) / float(columns)))
	var count: int = rows * columns
	while pool.size() < count:
		var tile: LoadoutItemTile = LoadoutItemTile.new()
		tile.inspected.connect(_on_tile_inspected)
		tile.activated.connect(_on_tile_activated)
		tile.secondary_activated.connect(_on_tile_secondary)
		tile.merge_requested.connect(_on_merge_requested)
		grid.add_child(tile)
		pool.append(tile)
	for index in range(pool.size()):
		var tile: LoadoutItemTile = pool[index]
		tile.visible = index < count
		apply.call(tile, items[index] if index < items.size() else null)


func _refresh_shop() -> void:
	if _recycler != null:
		_recycler.refresh()
	if not _shop_enabled:
		return
	var saved_count: int = ResearchManager.get_blueprint_slot_count()
	var saved_visible: bool = saved_count > 0
	_saved_caption.visible = saved_visible
	_saved_row.visible = saved_visible
	for tile in _offer_tiles:
		tile.setup_reward(RoundRewardInventory.SOURCE_OFFER, tile.source_index, RoundRewardInventory.get_offer(tile.source_index))
	for tile in _saved_tiles:
		tile.visible = tile.source_index < saved_count
		tile.setup_reward(RoundRewardInventory.SOURCE_SAVED, tile.source_index, RoundRewardInventory.get_saved_reward(tile.source_index))
	_refresh_coins()


func _refresh_coins() -> void:
	if _coin_label != null:
		_coin_label.text = "%d" % OnlineMatch.get_local_coin_balance()
	for tile in _offer_tiles:
		tile.refresh_affordability()
	for tile in _saved_tiles:
		tile.refresh_affordability()


func _update_tabs() -> void:
	var extension_counts: Dictionary = {&"": 0, &"front": 0, &"middle": 0, &"ammo": 0}
	for item in _sorted_extensions():
		extension_counts[&""] += 1
		extension_counts[item.get_slot()] = int(extension_counts.get(item.get_slot(), 0)) + 1
	for filter in _weapon_tabs.keys():
		var tab: Button = _weapon_tabs[filter]
		tab.text = "%s %d" % [tab.get_meta("label"), int(extension_counts.get(filter, 0))]
		tab.set_pressed_no_signal(filter == _weapon_filter)
	var armor_counts: Dictionary = {&"": 0, &"shield": 0, &"vest": 0, &"boots": 0}
	for item in _sorted_armor():
		armor_counts[&""] += 1
		armor_counts[item.category] = int(armor_counts.get(item.category, 0)) + 1
	for filter in _armor_tabs.keys():
		var tab: Button = _armor_tabs[filter]
		tab.text = "%s %d" % [tab.get_meta("label"), int(armor_counts.get(filter, 0))]
		tab.set_pressed_no_signal(filter == _armor_filter)


func _set_weapon_filter(filter: StringName) -> void:
	if filter == _weapon_filter and filter != &"":
		filter = &""
	_weapon_filter = filter
	AudioDirector.play(&"ui_toggle", -4.0)
	_fill_weapon_grid()
	_update_tabs()
	_weapon_scroll.scroll_vertical = 0
	if filter != &"":
		_weapon_bay.flash_slot(filter)


func _set_armor_filter(filter: StringName) -> void:
	if filter == _armor_filter and filter != &"":
		filter = &""
	_armor_filter = filter
	AudioDirector.play(&"ui_toggle", -4.0)
	_fill_armor_grid()
	_update_tabs()
	_armor_scroll.scroll_vertical = 0
	if filter != &"":
		_operator.flash_slot(filter)


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
	_armor_stats.set_preview({})
	if item == null or _is_weapon_extension_equipped(item):
		_weapon_stats.set_preview({})
		return
	var preview: Dictionary = _build_weapon_preview_modifiers(item, _get_current_weapon_modifiers())
	var values: Dictionary = {}
	for entry in _weapon_stat_entries(preview):
		values[entry["key"]] = entry["value"]
	_weapon_stats.set_preview(values)


func _preview_armor(item: ArmorItemData) -> void:
	_weapon_stats.set_preview({})
	if item == null or ArmorInventory.get_equipped_item(item.category) == item:
		_armor_stats.set_preview({})
		return
	var preview: Dictionary = _build_armor_preview_modifiers(item, ArmorInventory.get_scaled_attributes())
	var values: Dictionary = {}
	for entry in _armor_stat_entries(preview):
		values[entry["key"]] = entry["value"]
	_armor_stats.set_preview(values)


# --- Inspector -------------------------------------------------------------------------------------------

func _show_overview() -> void:
	_inspecting = false
	_weapon_stats.set_preview({})
	_armor_stats.set_preview({})
	var equipped: Dictionary = ExtensionInventory.get_equipped_for_local()
	var rows: Array = []
	var fallback: Dictionary = {&"front": "Stock", &"middle": "Iron sights", &"ammo": "Standard"}
	for slot in [&"front", &"middle", &"ammo"]:
		var item: WeaponExtensionItem = equipped.get(slot, null) as WeaponExtensionItem
		rows.append(_overview_row(LoadoutStyle.slot_label(slot), _base_name(item.get_display_name()) if item != null else fallback[slot], item != null))
	# With six rows each armor slot gets its own; with four (intermission) one row says which slots are
	# filled — the names are on the operator's sockets right next to it.
	var worn_slots: PackedStringArray = PackedStringArray()
	for category in [&"shield", &"vest", &"boots"]:
		var armor: ArmorItemData = ArmorInventory.get_equipped_item(category)
		if _inspector.row_count >= 6:
			rows.append(_overview_row(LoadoutStyle.slot_label(category), _base_name(armor.get_hover_title()) if armor != null else "—", armor != null))
		elif armor != null:
			worn_slots.append(LoadoutStyle.slot_label(category).capitalize())
	if _inspector.row_count < 6:
		rows.append(_overview_row("ARMOR", "  ·  ".join(worn_slots) if not worn_slots.is_empty() else "—", not worn_slots.is_empty()))
	var completed: int = int(OnlineMatch.match_points.get(GameSettings.PLAYER_ONE_SLOT, 0)) + int(OnlineMatch.match_points.get(GameSettings.PLAYER_TWO_SLOT, 0))
	var subtitle: String = "SANDBOX" if not _shop_enabled else "BEFORE SET %d" % (completed + 1)
	var mods: int = 0
	for slot in [&"front", &"middle", &"ammo"]:
		if equipped.get(slot, null) != null:
			mods += 1
	var armor_count: int = 0
	for category in [&"shield", &"vest", &"boots"]:
		if ArmorInventory.get_equipped_item(category) != null:
			armor_count += 1
	_inspector.show_overview(subtitle, WeaponArt.config_from_equipped(equipped), rows)
	_inspector.set_summary("%d / 3 MODS   ·   %d / 3 ARMOR" % [mods, armor_count])
	_inspector.set_hint(_default_hint())


func _overview_row(slot_label: String, value: String, installed: bool) -> Dictionary:
	return {"name": slot_label, "value": value, "color": LoadoutStyle.TEXT if installed else LoadoutStyle.TEXT_MUTED, "name_color": LoadoutStyle.TEXT_MUTED}


func _default_hint() -> String:
	if InputDevice.using_gamepad:
		return "A  INSTALL / REMOVE"
	return ""


## While something is being dragged the details stay on the dragged item. A copy of an installed part
## merges when dropped on the stage, so its details then show the merge instead of a swap.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		var data: Variant = get_viewport().gui_get_drag_data()
		if data is Dictionary:
			var dragged: Variant = (data as Dictionary).get("item", null)
			var price: int = -1
			if StringName(str((data as Dictionary).get("type", ""))) == &"round_reward":
				price = RoundRewardInventory.get_reward_price(StringName(str(data.get("source_kind", ""))), int(data.get("source_index", -1)))
			var installed: Variant = _installed_in_slot_of(dragged)
			if price < 0 and StringName(str((data as Dictionary).get("source", ""))) == &"inventory" and _merged_preview(dragged, installed) != null:
				_inspect_merge_drag(dragged, installed)
			elif dragged is WeaponExtensionItem:
				_inspect_extension(dragged, _is_weapon_extension_equipped(dragged), price)
			elif dragged is ArmorItemData:
				_inspect_armor(dragged, ArmorInventory.get_equipped_item((dragged as ArmorItemData).category) == dragged, price)


func _installed_in_slot_of(item: Variant) -> Variant:
	if item is WeaponExtensionItem:
		return ExtensionInventory.get_equipped_item_for_local((item as WeaponExtensionItem).get_slot())
	if item is ArmorItemData:
		return ArmorInventory.get_equipped_item((item as ArmorItemData).category)
	return null


func _inspect_merge_drag(dragged: Variant, installed: Variant) -> void:
	var result: Variant = _merged_preview(dragged, installed)
	var caption: String = "IF MERGED  ·  MK %s" % LoadoutStyle.roman(_mark_of(result))
	var rows: Array = _merge_rows(installed, result)
	var hint: String = "DROP ON ITS TWIN TO MERGE  ·  %d" % _merge_cost(dragged, installed)
	_inspecting = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	_weapon_stats.set_preview({})
	_armor_stats.set_preview({})
	if dragged is WeaponExtensionItem:
		_inspector.show_extension(dragged, _short_description((dragged as WeaponExtensionItem).definition.description), caption, rows, hint)
	else:
		_inspector.show_armor(dragged, _short_description((dragged as ArmorItemData).description), caption, rows, hint)


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


func _inspect_extension(item: WeaponExtensionItem, equipped: bool, price: int = -1) -> void:
	if item == null or item.definition == null:
		return
	_inspecting = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	var current: Dictionary = _get_current_weapon_modifiers()
	var rows: Array = []
	var caption: String = "IF INSTALLED"
	if equipped:
		caption = "INSTALLED"
		var without: Dictionary = current.duplicate()
		_apply_numeric_modifiers(without, item.build_effective_stats().get("attributes", {}), -1.0)
		rows = _stat_rows(_ordered_changed_keys(without, current, WEAPON_STAT_PRIORITY), without, current, true, true)
	else:
		var preview: Dictionary = _build_weapon_preview_modifiers(item, current)
		rows = _stat_rows(_ordered_changed_keys(current, preview, WEAPON_STAT_PRIORITY), current, preview, true)
	var hint: String = "CLICK TO REMOVE" if equipped else "CLICK TO INSTALL"
	if price >= 0:
		hint = "CLICK TO BUY  ·  %d" % price
	elif not equipped and ExtensionInventory.has_merge_partner_for_local(item):
		hint = "DROP ON ITS TWIN TO MERGE  ·  %d" % ExtensionInventory.get_merge_cost_for_next_mark(item.mark + 1)
	elif _shop_enabled:
		hint += "  ·  SELLS FOR %d" % RoundRewardInventory.sell_value(item)
	_inspector.show_extension(item, _short_description(item.definition.description), caption, rows, hint)
	_preview_weapon(item)


func _inspect_armor(item: ArmorItemData, equipped: bool, price: int = -1) -> void:
	if item == null:
		return
	_inspecting = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	var current: Dictionary = ArmorInventory.get_scaled_attributes()
	var rows: Array = []
	var caption: String = "IF EQUIPPED"
	if equipped:
		caption = "EQUIPPED"
		var without: Dictionary = current.duplicate()
		_apply_numeric_modifiers(without, item.get_scaled_attributes(), -1.0)
		rows = _stat_rows(_ordered_changed_keys(without, current, ARMOR_STAT_PRIORITY), without, current, false, true)
	else:
		var preview: Dictionary = _build_armor_preview_modifiers(item, current)
		rows = _stat_rows(_ordered_changed_keys(current, preview, ARMOR_STAT_PRIORITY), current, preview, false)
	var hint: String = "CLICK TO TAKE OFF" if equipped else "CLICK TO EQUIP"
	if price >= 0:
		hint = "CLICK TO BUY  ·  %d" % price
	elif not equipped and ArmorInventory.has_merge_partner_for_local(item):
		hint = "DROP ON ITS TWIN TO MERGE  ·  %d" % ArmorInventory.get_merge_cost_for_next_mark(item.get_mark() + 1)
	elif _shop_enabled:
		hint += "  ·  SELLS FOR %d" % RoundRewardInventory.sell_value(item)
	_inspector.show_armor(item, _short_description(item.description), caption, rows, hint)
	_preview_armor(item)


func _inspect_weapon_slot(slot: StringName) -> void:
	if _dragging():
		return
	var item: WeaponExtensionItem = ExtensionInventory.get_equipped_item_for_local(slot)
	if item != null:
		_inspect_extension(item, true)
		return
	_inspecting = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	var count: int = 0
	for owned in _sorted_extensions():
		if owned.get_slot() == slot:
			count += 1
	_inspector.show_slot(slot, "%d owned" % count, [], "CLICK TO FILTER")


func _inspect_armor_slot(category: StringName) -> void:
	if _dragging():
		return
	var item: ArmorItemData = ArmorInventory.get_equipped_item(category)
	if item != null:
		_inspect_armor(item, true)
		return
	_inspecting = true
	_hover_clear_timer = HOVER_CLEAR_DELAY
	var count: int = 0
	for owned in _sorted_armor():
		if owned.category == category:
			count += 1
	_inspector.show_slot(category, "%d owned" % count, [], "CLICK TO FILTER")


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


## Stat rows for the inspector. A change you could make reads "before › after"; for something already
## installed (as_contribution) it reads what that part adds right now, e.g. "+0.43/s", so it never looks
## like it would be applied a second time.
func _stat_rows(keys: Array[StringName], before: Dictionary, after: Dictionary, weapon: bool, as_contribution: bool = false) -> Array:
	var rows: Array = []
	for key in keys:
		var before_value: float = _weapon_display_value(key, before) if weapon else _armor_display_value(key, before)
		var after_value: float = _weapon_display_value(key, after) if weapon else _armor_display_value(key, after)
		if is_equal_approx(before_value, after_value):
			continue
		var lower_better: bool = WEAPON_LOWER_IS_BETTER.has(key) if weapon else ARMOR_LOWER_IS_BETTER.has(key)
		var better: bool = after_value < before_value if lower_better else after_value > before_value
		var suffix: String = str((WEAPON_ATTRIBUTE_SUFFIXES if weapon else ARMOR_ATTRIBUTE_SUFFIXES).get(key, ""))
		var decimals: int = int((WEAPON_ATTRIBUTE_DECIMALS if weapon else ARMOR_ATTRIBUTE_DECIMALS).get(key, 0))
		var name: String = str((WEAPON_ATTRIBUTE_NAMES if weapon else ARMOR_ATTRIBUTE_NAMES).get(key, str(key).replace("_", " ").capitalize()))
		var before_text: String = _format_value(before_value, suffix, decimals)
		var after_text: String = _format_value(after_value, suffix, decimals)
		# A difference too small to show (e.g. a copy in slightly different condition) is no change.
		if before_text == after_text:
			continue
		var value_text: String = "%s  ›  %s" % [before_text, after_text]
		if as_contribution:
			var difference: float = after_value - before_value
			if _format_value(absf(difference), "", decimals) in ["0", "0.0", "0.00"]:
				continue
			value_text = ("+" if difference > 0.0 else "−") + _format_value(absf(difference), suffix, decimals)
		rows.append({
			"name": name,
			"value": value_text,
			"color": LoadoutStyle.POSITIVE if better else LoadoutStyle.NEGATIVE,
		})
		if rows.size() >= LoadoutInspector.ROW_COUNT:
			break
	if rows.is_empty():
		rows.append({"name": "No stat effect" if as_contribution else "No stat changes", "value": "", "color": LoadoutStyle.TEXT_MUTED, "name_color": LoadoutStyle.TEXT_MUTED})
	return rows


func _format_value(value: float, suffix: String, decimals: int) -> String:
	var text: String = str(int(roundf(value)))
	if decimals == 1:
		text = "%.1f" % value
	elif decimals >= 2:
		text = "%.2f" % value
	return text + suffix


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
		_pop_tile_for(_weapon_tiles, item)
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
	_pop_tile_for(_weapon_tiles, item)
	_inspect_weapon_slot(slot)


func _equip_armor(item: ArmorItemData) -> void:
	if item == null or ArmorInventory.get_equipped_item(item.category) == item:
		return
	_animate_changes = true
	ArmorInventory.equip_item(item)
	_animate_changes = false
	AudioDirector.play(&"loadout_armor")
	_pop_tile_for(_armor_tiles, item)
	_inspect_armor(item, true)


func _unequip_armor_category(category: StringName) -> void:
	var item: ArmorItemData = ArmorInventory.get_equipped_item(category)
	if item == null:
		return
	_animate_changes = true
	ArmorInventory.unequip_category(category)
	_animate_changes = false
	AudioDirector.play(&"loadout_detach")
	_pop_tile_for(_armor_tiles, item)
	_inspect_armor_slot(category)


func _pop_tile_for(pool: Array[LoadoutItemTile], item: Variant) -> void:
	for tile in pool:
		if tile.visible and tile.item == item:
			tile.pop()
			return


func _on_extension_inventory_changed(player_slot: int) -> void:
	if player_slot != ExtensionInventory.get_local_player_slot():
		return
	_fill_weapon_grid()
	_update_tabs()


func _on_extension_loadout_changed(player_slot: int) -> void:
	if player_slot != ExtensionInventory.get_local_player_slot():
		return
	_refresh_weapon(_animate_changes)


func _on_armor_changed() -> void:
	_refresh_armor(_animate_changes)
	_update_tabs()


func unequip_from_inventory_drop(payload: Dictionary) -> void:
	var item: Variant = payload.get("item", null)
	if item is WeaponExtensionItem and _is_weapon_extension_equipped(item):
		_unequip_extension_slot((item as WeaponExtensionItem).get_slot())
	elif item is ArmorItemData and ArmorInventory.get_equipped_item((item as ArmorItemData).category) == item:
		_unequip_armor_category((item as ArmorItemData).category)
	elif StringName(str(payload.get("type", ""))) == &"round_reward":
		_on_reward_claimed(StringName(str(payload.get("source_kind", ""))), int(payload.get("source_index", -1)))


# --- Shop ------------------------------------------------------------------------------------------------

func _on_reward_claimed(source_kind: StringName, source_index: int) -> void:
	var price: int = RoundRewardInventory.get_reward_price(source_kind, source_index)
	if not RoundRewardInventory.can_afford_reward(source_kind, source_index):
		AudioDirector.play(&"shop_denied")
		_inspector.show_message("Not enough coins", "SHOP  ·  %d COINS NEEDED" % price, "", LoadoutStyle.DANGER)
		return
	if RoundRewardInventory.claim_reward(source_kind, source_index):
		AudioDirector.play(&"shop_purchase")
		_inspector.show_message("Purchased", "INVENTORY  ·  -%d COINS" % price, "", UiStyle.SUCCESS)


func _on_weapon_reward_dropped(payload: Dictionary, target_slot: StringName) -> void:
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	var item: WeaponExtensionItem = payload.get("item", null) as WeaponExtensionItem
	if item == null or item.get_slot() != target_slot:
		return
	var price: int = RoundRewardInventory.get_reward_price(source_kind, source_index)
	if not RoundRewardInventory.can_afford_reward(source_kind, source_index):
		AudioDirector.play(&"shop_denied")
		_inspector.show_message("Not enough coins", "SHOP  ·  %d COINS NEEDED" % price, "", LoadoutStyle.DANGER)
		return
	if not RoundRewardInventory.claim_reward(source_kind, source_index):
		return
	AudioDirector.play(&"shop_purchase")
	_equip_extension(item)


func _on_armor_reward_dropped(payload: Dictionary) -> void:
	var source_kind: StringName = StringName(str(payload.get("source_kind", "")))
	var source_index: int = int(payload.get("source_index", -1))
	var item: ArmorItemData = payload.get("item", null) as ArmorItemData
	if item == null:
		return
	var price: int = RoundRewardInventory.get_reward_price(source_kind, source_index)
	if not RoundRewardInventory.can_afford_reward(source_kind, source_index):
		AudioDirector.play(&"shop_denied")
		_inspector.show_message("Not enough coins", "SHOP  ·  %d COINS NEEDED" % price, "", LoadoutStyle.DANGER)
		return
	if not RoundRewardInventory.claim_reward(source_kind, source_index):
		return
	AudioDirector.play(&"shop_purchase")
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


func _on_item_sold(refund: int, title: String) -> void:
	AudioDirector.play(&"recycle")
	AudioDirector.play(&"coins")
	_inspector.show_message(title, "+%d COINS" % refund, "", UiStyle.SUCCESS)


# --- Merging ---------------------------------------------------------------------------------------------

## Dropping a part on its twin opens the merge band; it shows the real result (mark, condition, stat gain)
## and only opens when the merge is possible and affordable. Otherwise the inspector says why.
func _on_merge_requested(source: Variant, target: Variant) -> void:
	var result: Variant = _merged_preview(source, target)
	if result == null:
		_show_merge_error("Can't merge", "Same part, same MK")
		return
	var cost: int = _merge_cost(source, target)
	var balance: int = OnlineMatch.get_local_coin_balance()
	if balance < cost:
		_show_merge_error("Not enough coins", "MK %s  ·  %d / %d" % [LoadoutStyle.roman(_mark_of(result)), balance, cost])
		return
	_pending_merge = [source, target]
	var better: Variant = source if float(LoadoutStyle.item_info(source).get("condition", 0.0)) >= float(LoadoutStyle.item_info(target).get("condition", 0.0)) else target
	_merge_dialog.open(source, target, result, _merge_rows(better, result), cost, balance)


func _confirm_pending_merge() -> void:
	if _pending_merge.size() != 2:
		return
	var source: Variant = _pending_merge[0]
	var target: Variant = _pending_merge[1]
	_pending_merge = []
	var cost: int = _merge_cost(source, target)
	var merged: Variant = null
	if source is WeaponExtensionItem:
		merged = ExtensionInventory.try_merge_items_for_local(source, target)
	else:
		merged = ArmorInventory.try_merge_items_for_local(source, target)
	if merged == null:
		_show_merge_error("Merge failed", "")
		return
	AudioDirector.play(&"merge")
	_refresh_coins()
	if merged is WeaponExtensionItem:
		_pop_tile_for(_weapon_tiles, merged)
		_inspect_extension(merged, _is_weapon_extension_equipped(merged))
	else:
		_pop_tile_for(_armor_tiles, merged)
		_inspect_armor(merged, ArmorInventory.get_equipped_item((merged as ArmorItemData).category) == merged)
	_inspector.flash(LoadoutStyle.ACCENT)


func _cancel_pending_merge() -> void:
	_pending_merge = []


func _merged_preview(source: Variant, target: Variant) -> Variant:
	if source is WeaponExtensionItem and target is WeaponExtensionItem:
		return ExtensionInventory.preview_merged_item(source, target)
	if source is ArmorItemData and target is ArmorItemData:
		return ArmorInventory.preview_merged_item(source, target)
	return null


func _merge_cost(source: Variant, target: Variant) -> int:
	if source is WeaponExtensionItem:
		return ExtensionInventory.get_merge_cost_for_items(source, target)
	return ArmorInventory.get_merge_cost_for_items(source, target)


func _mark_of(item: Variant) -> int:
	return int(LoadoutStyle.item_info(item).get("mark", 0))


## Stat changes from running the merged result instead of the better of the two copies.
func _merge_rows(before_item: Variant, result: Variant) -> Array:
	if result is WeaponExtensionItem:
		var current: Dictionary = _get_current_weapon_modifiers()
		var before: Dictionary = _build_weapon_preview_modifiers(before_item, current)
		var after: Dictionary = _build_weapon_preview_modifiers(result, current)
		return _stat_rows(_ordered_changed_keys(before, after, WEAPON_STAT_PRIORITY), before, after, true)
	var current_armor: Dictionary = ArmorInventory.get_scaled_attributes()
	var before_armor: Dictionary = _build_armor_preview_modifiers(before_item, current_armor)
	var after_armor: Dictionary = _build_armor_preview_modifiers(result, current_armor)
	return _stat_rows(_ordered_changed_keys(before_armor, after_armor, ARMOR_STAT_PRIORITY), before_armor, after_armor, false)


func _show_merge_error(title: String, body: String) -> void:
	AudioDirector.play(&"shop_denied")
	_inspector.show_message(title, "MERGE", body, LoadoutStyle.DANGER)


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


func _short_description(description: String) -> String:
	if description.is_empty():
		return ""
	var sentences: PackedStringArray = description.split(". ")
	return sentences[0] + ("" if sentences[0].ends_with(".") else ".")


func _base_name(text: String) -> String:
	var index: int = text.rfind(" MK")
	return text.substr(0, index) if index > 0 else text
