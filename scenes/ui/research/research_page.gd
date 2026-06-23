extends Control
class_name ResearchPage

const RESEARCH_NODE_SCENE: PackedScene = preload("res://scenes/ui/research/research_node.tscn")
const HOVER_CARD_SIZE: Vector2 = Vector2(330.0, 118.0)

var _nodes_by_id: Dictionary = {}

@onready var _points_label: Label = %PointsLabel
@onready var _tree_canvas: Control = %TreeCanvas
@onready var _connection_layer: Variant = %ConnectionLayer
@onready var _hover_card: PanelContainer = %HoverCard
@onready var _details_title: Label = %DetailsTitle
@onready var _details_body: Label = %DetailsBody
@onready var _details_status: Label = %DetailsStatus


func _ready() -> void:
	_build_tree()
	ResearchManager.research_changed.connect(_refresh)
	ResearchManager.research_points_changed.connect(_on_points_changed)
	_refresh()


func _process(_delta: float) -> void:
	if _hover_card.visible:
		_position_hover_card()


func _exit_tree() -> void:
	if ResearchManager.research_changed.is_connected(_refresh):
		ResearchManager.research_changed.disconnect(_refresh)
	if ResearchManager.research_points_changed.is_connected(_on_points_changed):
		ResearchManager.research_points_changed.disconnect(_on_points_changed)


func _build_tree() -> void:
	var definitions: Array[Dictionary] = ResearchManager.get_all_definitions()
	_connection_layer.set_definitions(definitions)
	for definition in definitions:
		var node: ResearchNodeButton = RESEARCH_NODE_SCENE.instantiate() as ResearchNodeButton
		if node == null:
			continue
		var research_id: StringName = StringName(str(definition["id"]))
		node.position = definition["position"]
		node.setup(definition)
		node.research_selected.connect(_on_research_selected)
		node.research_hovered.connect(_show_research_details)
		node.research_unhovered.connect(_hide_research_details)
		_tree_canvas.add_child(node)
		_nodes_by_id[str(research_id)] = node


func _refresh() -> void:
	_points_label.text = "%d RESEARCH POINTS" % ResearchManager.research_points
	for node_variant in _nodes_by_id.values():
		var node: ResearchNodeButton = node_variant as ResearchNodeButton
		if node != null:
			node.refresh()
	_connection_layer.queue_redraw()


func _on_points_changed(_points: int) -> void:
	_refresh()


func _on_research_selected(research_id: StringName) -> void:
	if ResearchManager.purchase(research_id):
		_show_research_details(research_id)
	else:
		_show_research_details(research_id)


func _show_research_details(research_id: StringName) -> void:
	var definition: Dictionary = ResearchManager.get_definition(research_id)
	if definition.is_empty():
		return
	var current_mark: int = ResearchManager.get_mark(research_id)
	var max_mark: int = int(definition["max_mark"])
	_details_title.text = str(definition["name"])
	_details_body.text = str(definition["description"])
	if definition["available"] != true:
		_details_status.text = "Planned for a later update"
	elif current_mark >= max_mark:
		_details_status.text = "Fully researched - MK%d" % max_mark
	else:
		_details_status.text = "MK%d / MK%d    NEXT COST: %d RP" % [
			current_mark,
			max_mark,
			ResearchManager.get_next_cost(research_id),
		]
	_hover_card.show()
	_hover_card.custom_minimum_size = HOVER_CARD_SIZE
	_hover_card.size = HOVER_CARD_SIZE
	_position_hover_card()


func _hide_research_details() -> void:
	_hover_card.hide()


func _position_hover_card() -> void:
	var mouse_position: Vector2 = get_local_mouse_position()
	var card_size: Vector2 = HOVER_CARD_SIZE
	var target: Vector2 = mouse_position + Vector2(22.0, 18.0)
	var page_size: Vector2 = size
	target.x = clampf(target.x, 14.0, maxf(14.0, page_size.x - card_size.x - 14.0))
	target.y = clampf(target.y, 14.0, maxf(14.0, page_size.y - card_size.y - 14.0))
	_hover_card.position = target
