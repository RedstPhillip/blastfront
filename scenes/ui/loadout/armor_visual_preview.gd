extends Control
class_name ArmorVisualPreview

## Fits one armor piece's ArmorArt into the control (inventory tiles, socket chips, the inspector).

const FILL: float = 0.8

var _item: ArmorItemData = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_armor_item(item: ArmorItemData) -> bool:
	_item = item
	queue_redraw()
	return item != null


func clear() -> void:
	_item = null
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if _item == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var fit: Vector2 = size * FILL
	ArmorArt.draw_icon(self, Rect2((size - fit) * 0.5, fit), ArmorArt.art_id_for(_item), _item.get_mark(), {"team": LoadoutStyle.local_accent()})
