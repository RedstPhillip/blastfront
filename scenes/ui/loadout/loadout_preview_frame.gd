extends Panel
class_name LoadoutPreviewFrame

const EMPTY_COLOR: Color = Color8(58, 66, 74, 220)
const DEFAULT_CORNER_RADIUS: int = 8
const FRAME_SHADER: Shader = preload("res://scenes/ui/loadout/card_frame.gdshader")

static var _white_texture: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_condition_color(EMPTY_COLOR)


func set_condition_color(base_color: Color, filled: bool = true) -> void:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	var color: Color = base_color if filled else EMPTY_COLOR
	style.bg_color = Color(color.r * 0.24, color.g * 0.24, color.b * 0.24, 0.24 if filled else 0.12)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(
		minf(color.r + 0.36, 1.0),
		minf(color.g + 0.36, 1.0),
		minf(color.b + 0.36, 1.0),
		0.72 if filled else 0.34
	)
	style.corner_radius_top_left = DEFAULT_CORNER_RADIUS
	style.corner_radius_top_right = DEFAULT_CORNER_RADIUS
	style.corner_radius_bottom_right = DEFAULT_CORNER_RADIUS
	style.corner_radius_bottom_left = DEFAULT_CORNER_RADIUS
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.18)
	style.shadow_size = 2
	style.shadow_offset = Vector2(0.0, 1.0)
	style.content_margin_left = 0.0
	style.content_margin_top = 0.0
	style.content_margin_right = 0.0
	style.content_margin_bottom = 0.0
	add_theme_stylebox_override("panel", style)


## Styles a card/slot background with the frame shader: nothing to build per colour, and hover changes
## only flip a uniform.
static func apply_condition_style(rect: TextureRect, width: int, height: int, base_color: Color, alpha: float, corner_radius: int = DEFAULT_CORNER_RADIUS, highlighted: bool = false) -> void:
	if rect == null:
		return
	var material: ShaderMaterial = rect.material as ShaderMaterial
	if material == null or material.shader != FRAME_SHADER:
		material = ShaderMaterial.new()
		material.shader = FRAME_SHADER
		rect.material = material
	if _white_texture == null:
		var image: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_white_texture = ImageTexture.create_from_image(image)
	rect.texture = _white_texture
	material.set_shader_parameter(&"base_color", base_color)
	material.set_shader_parameter(&"alpha", alpha)
	material.set_shader_parameter(&"highlighted", 1.0 if highlighted else 0.0)
	material.set_shader_parameter(&"rect_size", Vector2(width, height))
	material.set_shader_parameter(&"radius", float(corner_radius))
