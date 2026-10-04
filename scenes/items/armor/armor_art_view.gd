class_name ArmorArtView
extends Node2D

## One armor piece drawn with ArmorArt in world units (shield in hand, vest on the body, a boot on a
## foot, and the bigger operator on the loadout stage, whose anchors scale it up). Animated views redraw
## every frame for the soft effect glow.

var art_id: StringName = &""
var mark: int = 1
var team_color: Color = ArmorArt.DEFAULT_TEAM
## Outline thickness in art units; in-match pieces are small on screen and want a heavier one.
var outline: float = ArmorArt.OUTLINE_WIDTH
var animated: bool = false

var _time: float = 0.0


static func create(item: ArmorItemData, team: Color, outline_width: float = ArmorArt.OUTLINE_WIDTH, animate: bool = false) -> ArmorArtView:
	var view: ArmorArtView = ArmorArtView.new()
	view.name = "ArmorArtView"
	view.art_id = ArmorArt.art_id_for(item)
	view.mark = item.get_mark() if item != null else 1
	view.team_color = team
	view.outline = outline_width
	view.animated = animate
	return view


func _ready() -> void:
	set_process(animated)


func set_team_color(color: Color) -> void:
	if team_color == color:
		return
	team_color = color
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	if art_id == &"":
		return
	var xform: Transform2D = Transform2D(0.0, Vector2.ONE * ArmorArt.WORLD_SCALE, 0.0, Vector2.ZERO)
	ArmorArt.draw_piece(self, xform, art_id, mark, {"team": team_color, "outline": outline})
	if animated:
		ArmorArt.draw_fx(self, xform, art_id, mark, _time)
