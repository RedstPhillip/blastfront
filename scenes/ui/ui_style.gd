class_name UiStyle
extends RefCounted

## Shared visual language for HUD and menus: palette, fonts and stylebox factories.

const INK: Color = Color(0.031, 0.055, 0.06, 1.0)
const PANEL: Color = Color(0.043, 0.075, 0.08, 0.88)
const PANEL_SOLID: Color = Color(0.055, 0.094, 0.1, 1.0)
const PANEL_RAISED: Color = Color(0.082, 0.133, 0.137, 0.95)
const LINE: Color = Color(0.56, 0.78, 0.74, 0.22)
const LINE_STRONG: Color = Color(0.62, 0.86, 0.8, 0.45)
const TEXT: Color = Color(0.93, 0.96, 0.93, 1.0)
const TEXT_DIM: Color = Color(0.62, 0.71, 0.68, 1.0)
const TEXT_MUTED: Color = Color(0.37, 0.46, 0.44, 1.0)
const ACCENT: Color = Color(1.0, 0.71, 0.28, 1.0)
const ACCENT_HOT: Color = Color(1.0, 0.84, 0.5, 1.0)
const ACCENT_DEEP: Color = Color(0.78, 0.45, 0.08, 1.0)
const TEAL: Color = Color(0.36, 0.9, 0.78, 1.0)
const DANGER: Color = Color(1.0, 0.3, 0.35, 1.0)
const SUCCESS: Color = Color(0.49, 0.89, 0.55, 1.0)
const SHIELD: Color = Color(0.55, 0.93, 1.0, 1.0)

const FONT_DISPLAY: Font = preload("res://assets/fonts/blastfront_combat_font.tres")
const FONT_BOLD: Font = preload("res://assets/fonts/blastfront_hud_font.tres")
const FONT_UI: Font = preload("res://assets/fonts/blastfront_ui_font.tres")
const FONT_BODY: Font = preload("res://assets/fonts/blastfront_body_font.tres")


static func panel(bg: Color = PANEL, border: Color = LINE, radius: int = 6, border_width: int = 1, skew: float = 0.0) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.skew = Vector2(skew, 0.0)
	style.anti_aliasing = true
	return style


static func with_margins(style: StyleBoxFlat, horizontal: float, vertical: float) -> StyleBoxFlat:
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style


static func with_shadow(style: StyleBoxFlat, size: int = 12, offset: Vector2 = Vector2(0, 6), color: Color = Color(0, 0, 0, 0.45)) -> StyleBoxFlat:
	style.shadow_size = size
	style.shadow_offset = offset
	style.shadow_color = color
	return style


static func style_label(label: Label, font: Font, size: int, color: Color = TEXT, outline: int = 0) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if outline > 0:
		label.add_theme_constant_override("outline_size", outline)
		label.add_theme_color_override("font_outline_color", Color(0.0, 0.02, 0.02, 0.9))


static func player_color(slot: int) -> Color:
	if NetworkSession.is_steam_match_active():
		return OnlineMatch.get_player_color(slot)
	return GameSettings.player_color_value(GameSettings.ONLINE_DEFAULT_REMOTE_COLOR if slot == GameSettings.PLAYER_TWO_SLOT else GameSettings.ONLINE_DEFAULT_LOCAL_COLOR)


static func player_name(slot: int) -> String:
	if NetworkSession.is_steam_match_active():
		return OnlineMatch.get_player_color_name(slot).to_upper()
	if NetworkSession.is_bot_duel() and slot == GameSettings.PLAYER_TWO_SLOT:
		return "CPU"
	if NetworkSession.is_training() and slot != GameSettings.PLAYER_ONE_SLOT:
		return "TARGET"
	if slot == GameSettings.PLAYER_ONE_SLOT:
		return "YOU"
	return "PLAYER %d" % slot


static func difficulty_name(value: int) -> String:
	match value:
		0:
			return "EASY"
		2:
			return "HARD"
		_:
			return "NORMAL"


## Applies the shared skewed button look. Primary buttons are amber; secondary ones are dark glass.
static func style_button(button: Button, primary: bool, font_size: int = 20) -> void:
	var skew: float = 0.18
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var pressed: StyleBoxFlat
	if primary:
		normal = with_margins(panel(ACCENT, ACCENT_HOT, 3, 1, skew), 26, 10)
		hover = with_margins(panel(ACCENT_HOT, Color.WHITE, 3, 2, skew), 26, 10)
		pressed = with_margins(panel(ACCENT_DEEP, ACCENT, 3, 1, skew), 26, 10)
		button.add_theme_color_override("font_color", INK)
		button.add_theme_color_override("font_hover_color", INK)
		button.add_theme_color_override("font_focus_color", INK)
		button.add_theme_color_override("font_pressed_color", INK)
	else:
		normal = with_margins(panel(Color(0.06, 0.1, 0.105, 0.9), LINE_STRONG, 3, 1, skew), 26, 10)
		hover = with_margins(panel(Color(0.1, 0.16, 0.16, 0.95), ACCENT, 3, 2, skew), 26, 10)
		pressed = with_margins(panel(Color(0.04, 0.07, 0.07, 1.0), ACCENT_DEEP, 3, 1, skew), 26, 10)
		button.add_theme_color_override("font_color", TEXT)
		button.add_theme_color_override("font_hover_color", ACCENT_HOT)
		button.add_theme_color_override("font_focus_color", ACCENT_HOT)
		button.add_theme_color_override("font_pressed_color", ACCENT)
	var disabled: StyleBoxFlat = with_margins(panel(Color(0.06, 0.08, 0.08, 0.6), Color(0.3, 0.36, 0.35, 0.35), 3, 1, skew), 26, 10)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", TEXT_MUTED)
	button.add_theme_font_override("font", FONT_BOLD)
	button.add_theme_font_size_override("font_size", font_size)
