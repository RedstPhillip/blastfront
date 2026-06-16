extends Button
class_name ResearchNodeButton

signal research_selected(research_id: StringName)
signal research_hovered(research_id: StringName)
signal research_unhovered

const COLOR_ECONOMY: Color = Color8(205, 151, 65, 255)
const COLOR_MOVEMENT: Color = Color8(137, 148, 101, 255)
const COLOR_MISC: Color = Color8(176, 91, 62, 255)
const COLOR_LOCKED: Color = Color8(91, 88, 80, 255)
const COLOR_PLANNED: Color = Color8(67, 64, 59, 255)

var research_id: StringName = &""
var definition: Dictionary = {}
var _loaded_icon_path: String = ""

@onready var _icon_texture: TextureRect = %IconTexture
@onready var _stars_label: Label = %StarsLabel
@onready var _lock_label: Label = %LockLabel
@onready var _cost_label: Label = %CostLabel


func _ready() -> void:
	pressed.connect(_on_pressed)
	mouse_entered.connect(_on_mouse_entered)
	focus_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	focus_exited.connect(_on_mouse_exited)
	GameJuice.attach_button_feedback(self)
	refresh()


func setup(next_definition: Dictionary) -> void:
	definition = next_definition.duplicate(true)
	research_id = StringName(str(definition.get("id", "")))
	if is_node_ready():
		refresh()


func refresh() -> void:
	if definition.is_empty():
		return
	var branch: StringName = StringName(str(definition.get("branch", "")))
	var available: bool = definition.get("available", true) == true
	var current_mark: int = ResearchManager.get_mark(research_id)
	var max_mark: int = int(definition.get("max_mark", 1))
	var next_cost: int = ResearchManager.get_next_cost(research_id)
	var can_buy: bool = ResearchManager.can_purchase(research_id)
	var requirements_met: bool = current_mark > 0 or _requirements_met()
	var accent: Color = _branch_color(branch)
	if not available:
		accent = COLOR_PLANNED
	elif current_mark <= 0 and not requirements_met:
		accent = COLOR_LOCKED

	_refresh_icon(accent, available, requirements_met)
	_stars_label.text = _stars(current_mark, max_mark)
	var star_color: Color = Color(1.0, 0.82, 0.24, 1.0) if current_mark > 0 else Color(0.74, 0.65, 0.48, 0.95)
	if not available or (current_mark <= 0 and not requirements_met):
		star_color = Color(0.42, 0.40, 0.36, 0.9)
	_stars_label.add_theme_color_override("font_color", star_color)
	_lock_label.visible = not available or (current_mark <= 0 and not requirements_met)
	_lock_label.text = "SOON" if not available else "LOCK"
	_cost_label.visible = available and requirements_met and current_mark < max_mark and next_cost > 0
	_cost_label.text = "%d RP" % next_cost
	_cost_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.28, 1.0) if can_buy else Color(0.78, 0.66, 0.47, 0.92))
	disabled = not available or current_mark >= max_mark or not requirements_met or not can_buy
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not disabled else Control.CURSOR_ARROW
	_apply_styles(accent, current_mark > 0, can_buy)
	tooltip_text = _build_tooltip(current_mark, max_mark, available, requirements_met)


func _refresh_icon(accent: Color, available: bool, requirements_met: bool) -> void:
	var icon_path: String = str(definition.get("icon_path", ""))
	if icon_path != _loaded_icon_path:
		_loaded_icon_path = icon_path
		var icon_resource: Resource = load(icon_path) if not icon_path.is_empty() else null
		_icon_texture.texture = icon_resource as Texture2D
	if not available:
		_icon_texture.modulate = Color8(125, 119, 107, 180)
	elif not requirements_met:
		_icon_texture.modulate = Color(accent.r, accent.g, accent.b, 0.58)
	else:
		_icon_texture.modulate = accent.lightened(0.28)


func _requirements_met() -> bool:
	var requirements_variant: Variant = definition.get("requires", [])
	if not (requirements_variant is Array):
		return true
	var requirements: Array = requirements_variant
	for requirement_variant in requirements:
		if not (requirement_variant is Dictionary):
			continue
		var requirement: Dictionary = requirement_variant
		var required_id: StringName = StringName(str(requirement.get("id", "")))
		if ResearchManager.get_mark(required_id) < int(requirement.get("mark", 1)):
			return false
	return true


func _build_tooltip(current_mark: int, max_mark: int, available: bool, requirements_met: bool) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append(str(definition.get("name", "Research")))
	lines.append(str(definition.get("description", "")))
	lines.append("Level: MK%d / MK%d" % [current_mark, max_mark])
	if not available:
		lines.append("Planned research - currently disabled.")
	elif not requirements_met:
		lines.append("Requires the connected previous research.")
	elif current_mark >= max_mark:
		lines.append("Fully researched.")
	else:
		lines.append("Next level: %d Research Points" % ResearchManager.get_next_cost(research_id))
	return "\n".join(lines)


func _apply_styles(accent: Color, unlocked: bool, can_buy: bool) -> void:
	var normal: StyleBoxFlat = _style(accent, 0.16 if unlocked else 0.07, 2)
	var hover: StyleBoxFlat = _style(accent.lightened(0.22), 0.28, 3)
	var pressed_style: StyleBoxFlat = _style(accent.lightened(0.32), 0.36, 3)
	var disabled_style: StyleBoxFlat = _style(accent, 0.1 if unlocked else 0.035, 1)
	if can_buy:
		normal.shadow_color = Color(0, 0, 0, 0.42)
		normal.shadow_size = 5
	add_theme_stylebox_override("normal", normal)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("focus", hover)
	add_theme_stylebox_override("pressed", pressed_style)
	add_theme_stylebox_override("disabled", disabled_style)


func _style(accent: Color, background_alpha: float, border_width: int) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(
		0.075 + accent.r * 0.08,
		0.065 + accent.g * 0.07,
		0.05 + accent.b * 0.05,
		0.94
	)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.48 + background_alpha)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(8)
	style.content_margin_left = 4.0
	style.content_margin_top = 4.0
	style.content_margin_right = 4.0
	style.content_margin_bottom = 4.0
	return style


func _branch_color(branch: StringName) -> Color:
	match branch:
		ResearchManager.BRANCH_ECONOMY:
			return COLOR_ECONOMY
		ResearchManager.BRANCH_MOVEMENT:
			return COLOR_MOVEMENT
		_:
			return COLOR_MISC


func _stars(current_mark: int, max_mark: int) -> String:
	var result: String = ""
	for star_index in range(max_mark):
		result += "\u2605" if star_index < current_mark else "\u2606"
	return result


func _on_pressed() -> void:
	research_selected.emit(research_id)


func _on_mouse_entered() -> void:
	research_hovered.emit(research_id)


func _on_mouse_exited() -> void:
	research_unhovered.emit()
