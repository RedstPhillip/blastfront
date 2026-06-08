extends Panel
class_name LoadoutPreviewFrame

const EMPTY_COLOR: Color = Color8(58, 66, 74, 220)
const DEFAULT_CORNER_RADIUS: int = 8
const CONDITION_TEXTURE_SCALE: int = 4


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


static func create_condition_texture(width: int, height: int, base_color: Color, alpha: float, corner_radius: int = DEFAULT_CORNER_RADIUS, highlighted: bool = false) -> Texture2D:
	var texture_width: int = width * CONDITION_TEXTURE_SCALE
	var texture_height: int = height * CONDITION_TEXTURE_SCALE
	var scaled_radius: float = float(corner_radius * CONDITION_TEXTURE_SCALE)
	var border_width: float = float((3.25 if highlighted else 2.25) * CONDITION_TEXTURE_SCALE)
	var image: Image = Image.create(texture_width, texture_height, false, Image.FORMAT_RGBA8)
	var alpha_boost: float = 1.0 if not highlighted else 1.08
	var low_color: Color = Color(base_color.r * 0.26, base_color.g * 0.26, base_color.b * 0.26, minf(alpha * alpha_boost, 1.0))
	var mid_color: Color = Color(base_color.r * 0.76, base_color.g * 0.76, base_color.b * 0.76, minf(alpha * alpha_boost, 1.0))
	var high_color: Color = Color(
		minf(base_color.r + (0.34 if highlighted else 0.24), 1.0),
		minf(base_color.g + (0.34 if highlighted else 0.24), 1.0),
		minf(base_color.b + (0.34 if highlighted else 0.24), 1.0),
		minf(alpha * alpha_boost, 1.0)
	)
	var accent_color: Color = Color(
		minf(base_color.r * 0.65 + 0.18, 1.0),
		minf(base_color.g * 0.65 + 0.18, 1.0),
		minf(base_color.b * 0.65 + 0.18, 1.0),
		minf(alpha * alpha_boost, 1.0)
	)
	var border_color: Color = Color(
		minf(base_color.r + (0.52 if highlighted else 0.34), 1.0),
		minf(base_color.g + (0.52 if highlighted else 0.34), 1.0),
		minf(base_color.b + (0.52 if highlighted else 0.34), 1.0),
		1.0 if highlighted else 0.9
	)
	for y in range(texture_height):
		for x in range(texture_width):
			var point: Vector2 = Vector2(x, y)
			if not _is_inside_rounded_rect(point, Vector2(texture_width, texture_height), scaled_radius):
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				continue
			var inner_size: Vector2 = Vector2(texture_width, texture_height) - Vector2.ONE * border_width * 2.0
			var inner_point: Vector2 = point - Vector2.ONE * border_width
			var inside_inner: bool = _is_inside_rounded_rect(inner_point, inner_size, maxf(1.0, scaled_radius - border_width))
			var uv: Vector2 = Vector2(
				float(x) / maxf(1.0, float(texture_width - 1)),
				float(y) / maxf(1.0, float(texture_height - 1))
			)
			var diagonal: float = smoothstep(0.0, 1.0, (uv.x * 0.72 + (1.0 - uv.y) * 0.92) * 0.62)
			var top_glow: float = smoothstep(0.0, 1.0, maxf(0.0, 1.0 - uv.distance_to(Vector2(0.76, 0.16)) * 1.48))
			var lower_glow: float = smoothstep(0.0, 1.0, maxf(0.0, 1.0 - uv.distance_to(Vector2(0.24, 0.78)) * 1.72))
			var sweep: float = smoothstep(0.0, 0.18, 0.18 - absf((uv.x * 0.82 + uv.y * 0.42) - 0.56))
			var vignette: float = smoothstep(0.18, 0.88, uv.distance_to(Vector2(0.5, 0.5)))
			var color: Color = low_color.lerp(mid_color, diagonal)
			color = color.lerp(accent_color, lower_glow * 0.24)
			color = color.lerp(high_color, top_glow * (0.34 if highlighted else 0.26))
			color = color.lerp(Color(1.0, 1.0, 1.0, color.a), sweep * (0.13 if highlighted else 0.08))
			color = color.darkened(vignette * 0.20)
			if not inside_inner:
				color = color.lerp(border_color, 0.94 if highlighted else 0.86)
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)


static func _is_inside_rounded_rect(point: Vector2, rect_size: Vector2, radius: float) -> bool:
	if point.x < 0.0 or point.y < 0.0 or point.x > rect_size.x - 1.0 or point.y > rect_size.y - 1.0:
		return false
	var inner_min: Vector2 = Vector2(radius, radius)
	var inner_max: Vector2 = rect_size - Vector2(radius + 1.0, radius + 1.0)
	if point.x >= inner_min.x and point.x <= inner_max.x:
		return true
	if point.y >= inner_min.y and point.y <= inner_max.y:
		return true
	var corner_center: Vector2 = Vector2(
		inner_min.x if point.x < inner_min.x else inner_max.x,
		inner_min.y if point.y < inner_min.y else inner_max.y
	)
	return point.distance_to(corner_center) <= radius
