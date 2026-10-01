extends SceneTree

## Builds res://ui/theme/blastfront_theme.tres, the project-wide default UI theme.
## Run headless: godot --headless --path . -s res://tools/build_theme.gd
## Palette mirrors scenes/ui/ui_style.gd (kept local so this tool has no runtime dependencies).

const OUTPUT_PATH: String = "res://ui/theme/blastfront_theme.tres"
const ICONS: String = "res://ui/theme/icons/"

const INK: Color = Color(0.031, 0.055, 0.06, 1.0)
const PANEL: Color = Color(0.043, 0.075, 0.08, 0.92)
const PANEL_RAISED: Color = Color(0.075, 0.12, 0.125, 0.96)
const FIELD: Color = Color(0.03, 0.05, 0.055, 0.95)
const LINE: Color = Color(0.56, 0.78, 0.74, 0.22)
const LINE_STRONG: Color = Color(0.62, 0.86, 0.8, 0.45)
const TEXT: Color = Color(0.93, 0.96, 0.93, 1.0)
const TEXT_DIM: Color = Color(0.62, 0.71, 0.68, 1.0)
const TEXT_MUTED: Color = Color(0.37, 0.46, 0.44, 1.0)
const ACCENT: Color = Color(1.0, 0.71, 0.28, 1.0)
const ACCENT_HOT: Color = Color(1.0, 0.84, 0.5, 1.0)
const ACCENT_DEEP: Color = Color(0.78, 0.45, 0.08, 1.0)


func _initialize() -> void:
	var theme: Theme = Theme.new()
	theme.default_font = load("res://assets/fonts/blastfront_ui_font.tres")
	theme.default_font_size = 18
	var bold: Font = load("res://assets/fonts/blastfront_hud_font.tres")

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))

	var button_normal: StyleBoxFlat = _box(PANEL_RAISED, LINE_STRONG, 4, 1, 16, 8)
	var button_hover: StyleBoxFlat = _box(Color(0.11, 0.17, 0.17, 1.0), ACCENT, 4, 2, 16, 8)
	var button_pressed: StyleBoxFlat = _box(Color(0.05, 0.08, 0.08, 1.0), ACCENT_DEEP, 4, 2, 16, 8)
	var button_disabled: StyleBoxFlat = _box(Color(0.05, 0.07, 0.07, 0.6), Color(0.3, 0.36, 0.35, 0.3), 4, 1, 16, 8)
	for type_name in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", type_name, button_normal)
		theme.set_stylebox("hover", type_name, button_hover)
		theme.set_stylebox("pressed", type_name, button_pressed)
		theme.set_stylebox("focus", type_name, _focus())
		theme.set_stylebox("disabled", type_name, button_disabled)
		theme.set_color("font_color", type_name, TEXT)
		theme.set_color("font_hover_color", type_name, ACCENT_HOT)
		theme.set_color("font_pressed_color", type_name, ACCENT)
		theme.set_color("font_focus_color", type_name, ACCENT_HOT)
		theme.set_color("font_disabled_color", type_name, TEXT_MUTED)
		theme.set_font("font", type_name, bold)
	theme.set_icon("arrow", "OptionButton", load(ICONS + "option_arrow.png"))
	theme.set_constant("arrow_margin", "OptionButton", 10)

	for type_name in ["CheckBox", "CheckButton"]:
		var empty: StyleBoxEmpty = StyleBoxEmpty.new()
		empty.content_margin_left = 4
		empty.content_margin_right = 4
		empty.content_margin_top = 4
		empty.content_margin_bottom = 4
		theme.set_stylebox("normal", type_name, empty)
		theme.set_stylebox("hover", type_name, empty)
		theme.set_stylebox("pressed", type_name, empty)
		theme.set_stylebox("hover_pressed", type_name, empty)
		theme.set_stylebox("focus", type_name, _focus())
		theme.set_color("font_color", type_name, TEXT)
		theme.set_color("font_hover_color", type_name, ACCENT_HOT)
		theme.set_color("font_pressed_color", type_name, TEXT)
		theme.set_color("font_hover_pressed_color", type_name, ACCENT_HOT)
		theme.set_constant("h_separation", type_name, 10)
	theme.set_icon("unchecked", "CheckBox", load(ICONS + "checkbox_off.png"))
	theme.set_icon("checked", "CheckBox", load(ICONS + "checkbox_on.png"))
	theme.set_icon("unchecked_disabled", "CheckBox", load(ICONS + "checkbox_off.png"))
	theme.set_icon("checked_disabled", "CheckBox", load(ICONS + "checkbox_on.png"))
	theme.set_icon("unchecked", "CheckButton", load(ICONS + "toggle_off.png"))
	theme.set_icon("checked", "CheckButton", load(ICONS + "toggle_on.png"))
	theme.set_icon("unchecked_disabled", "CheckButton", load(ICONS + "toggle_off.png"))
	theme.set_icon("checked_disabled", "CheckButton", load(ICONS + "toggle_on.png"))

	var panel_style: StyleBoxFlat = _box(PANEL, LINE, 8, 1, 14, 12)
	panel_style.shadow_color = Color(0, 0, 0, 0.4)
	panel_style.shadow_size = 14
	panel_style.shadow_offset = Vector2(0, 6)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	theme.set_stylebox("panel", "Panel", panel_style)

	var popup: StyleBoxFlat = _box(Color(0.05, 0.085, 0.09, 0.98), LINE_STRONG, 6, 1, 6, 6)
	theme.set_stylebox("panel", "PopupMenu", popup)
	theme.set_stylebox("hover", "PopupMenu", _box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.18), Color(0, 0, 0, 0), 4, 0, 8, 4))
	theme.set_color("font_color", "PopupMenu", TEXT)
	theme.set_color("font_hover_color", "PopupMenu", ACCENT_HOT)
	theme.set_color("font_disabled_color", "PopupMenu", TEXT_MUTED)
	theme.set_constant("v_separation", "PopupMenu", 8)
	theme.set_stylebox("panel", "PopupPanel", popup)

	var track: StyleBoxFlat = _box(FIELD, LINE, 4, 1, 0, 3)
	var fill: StyleBoxFlat = _box(ACCENT_DEEP, Color(0, 0, 0, 0), 4, 0, 0, 3)
	var fill_hot: StyleBoxFlat = _box(ACCENT, Color(0, 0, 0, 0), 4, 0, 0, 3)
	theme.set_stylebox("slider", "HSlider", track)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill_hot)
	theme.set_icon("grabber", "HSlider", load(ICONS + "grabber.png"))
	theme.set_icon("grabber_highlight", "HSlider", load(ICONS + "grabber_hover.png"))
	theme.set_icon("grabber_disabled", "HSlider", load(ICONS + "grabber.png"))

	theme.set_stylebox("background", "ProgressBar", _box(FIELD, LINE, 3, 1, 0, 0))
	theme.set_stylebox("fill", "ProgressBar", _box(ACCENT, Color(0, 0, 0, 0), 3, 0, 0, 0))
	theme.set_color("font_color", "ProgressBar", TEXT)

	for orientation in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", orientation, _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 4, 0, 2, 2))
		theme.set_stylebox("grabber", orientation, _box(Color(LINE_STRONG.r, LINE_STRONG.g, LINE_STRONG.b, 0.55), Color(0, 0, 0, 0), 4, 0, 2, 2))
		theme.set_stylebox("grabber_highlight", orientation, _box(ACCENT, Color(0, 0, 0, 0), 4, 0, 2, 2))
		theme.set_stylebox("grabber_pressed", orientation, _box(ACCENT_HOT, Color(0, 0, 0, 0), 4, 0, 2, 2))

	theme.set_stylebox("normal", "LineEdit", _box(FIELD, LINE_STRONG, 4, 1, 10, 6))
	theme.set_stylebox("focus", "LineEdit", _box(FIELD, ACCENT, 4, 2, 10, 6))
	theme.set_color("font_color", "LineEdit", TEXT)
	theme.set_color("caret_color", "LineEdit", ACCENT)
	theme.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))

	theme.set_stylebox("panel", "TooltipPanel", _box(Color(0.02, 0.035, 0.04, 0.97), ACCENT, 4, 1, 10, 6))
	theme.set_color("font_color", "TooltipLabel", TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 15)

	theme.set_stylebox("tab_selected", "TabContainer", _box(PANEL_RAISED, ACCENT, 4, 0, 16, 8, true))
	theme.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.03, 0.05, 0.05, 0.8), LINE, 4, 0, 16, 8))
	theme.set_stylebox("tab_hovered", "TabContainer", _box(Color(0.08, 0.13, 0.13, 0.9), LINE_STRONG, 4, 0, 16, 8))
	theme.set_stylebox("panel", "TabContainer", _box(PANEL, LINE, 6, 1, 16, 14))
	theme.set_color("font_selected_color", "TabContainer", ACCENT_HOT)
	theme.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	theme.set_color("font_hovered_color", "TabContainer", TEXT)
	theme.set_font("font", "TabContainer", bold)
	for type_name in ["TabBar"]:
		theme.set_stylebox("tab_selected", type_name, _box(PANEL_RAISED, ACCENT, 4, 0, 16, 8, true))
		theme.set_stylebox("tab_unselected", type_name, _box(Color(0.03, 0.05, 0.05, 0.8), LINE, 4, 0, 16, 8))
		theme.set_stylebox("tab_hovered", type_name, _box(Color(0.08, 0.13, 0.13, 0.9), LINE_STRONG, 4, 0, 16, 8))
		theme.set_color("font_selected_color", type_name, ACCENT_HOT)
		theme.set_color("font_unselected_color", type_name, TEXT_DIM)
		theme.set_color("font_hovered_color", type_name, TEXT)
		theme.set_font("font", type_name, bold)

	var separator: StyleBoxLine = StyleBoxLine.new()
	separator.color = LINE
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	theme.set_constant("separation", "HSeparator", 14)
	var vseparator: StyleBoxLine = StyleBoxLine.new()
	vseparator.color = LINE
	vseparator.thickness = 1
	vseparator.vertical = true
	theme.set_stylebox("separator", "VSeparator", vseparator)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://ui/theme"))
	var error: Error = ResourceSaver.save(theme, OUTPUT_PATH)
	print("theme saved: ", OUTPUT_PATH, " error=", error)
	quit()


func _box(bg: Color, border: Color, radius: int, border_width: int, margin_h: float, margin_v: float, accent_top: bool = false) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	if accent_top:
		style.border_width_top = 3
		style.border_color = ACCENT
	style.set_corner_radius_all(radius)
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	style.anti_aliasing = true
	return style


func _focus() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.draw_center = false
	style.border_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	style.expand_margin_left = 2
	style.expand_margin_right = 2
	style.expand_margin_top = 2
	style.expand_margin_bottom = 2
	return style
