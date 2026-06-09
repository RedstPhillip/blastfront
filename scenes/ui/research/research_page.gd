extends Control
class_name ResearchPage

const RESEARCH_NODE_SCENE: PackedScene = preload("res://scenes/ui/research/research_node.tscn")

var _nodes_by_id: Dictionary = {}

@onready var _points_label: Label = %PointsLabel
@onready var _tree_canvas: Control = %TreeCanvas
@onready var _connection_layer: Control = %ConnectionLayer
@onready var _details_title: Label = %DetailsTitle
@onready var _details_body: Label = %DetailsBody
@onready var _details_status: Label = %DetailsStatus


func _ready() -> void:
	_build_tree()
	ResearchManager.research_changed.connect(_refresh)
	ResearchManager.research_points_changed.connect(_on_points_changed)
	_refresh()


func _exit_tree() -> void:
	if ResearchManager.research_changed.is_connected(_refresh):
		ResearchManager.research_changed.disconnect(_refresh)
	if ResearchManager.research_points_changed.is_connected(_on_points_changed):
		ResearchManager.research_points_changed.disconnect(_on_points_changed)


func _build_tree() -> void:
	var definitions: Array[Dictionary] = ResearchManager.get_all_definitions()
	_connection_layer.call("set_definitions", definitions)
	for definition in definitions:
		var node: Button = RESEARCH_NODE_SCENE.instantiate() as Button
		if node == null:
			continue
		var research_id: StringName = StringName(str(definition.get("id", "")))
		node.position = definition.get("position", Vector2.ZERO)
		node.call("setup", definition)
		node.connect("research_selected", _on_research_selected)
		node.connect("research_hovered", _show_research_details)
		_tree_canvas.add_child(node)
		_nodes_by_id[str(research_id)] = node


func _refresh() -> void:
	_points_label.text = "%d RESEARCH POINTS" % ResearchManager.research_points
	for node_variant in _nodes_by_id.values():
		var node: Node = node_variant as Node
		if node != null:
			node.call("refresh")
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
	var max_mark: int = int(definition.get("max_mark", 1))
	_details_title.text = str(definition.get("name", "Research"))
	_details_body.text = str(definition.get("description", ""))
	if definition.get("available", true) != true:
		_details_status.text = "PLANNED  |  This research is visible but currently disabled."
	elif current_mark >= max_mark:
		_details_status.text = "FULLY RESEARCHED  |  MK%d" % max_mark
	else:
		_details_status.text = "MK%d / MK%d  |  NEXT: %d RP" % [
			current_mark,
			max_mark,
			ResearchManager.get_next_cost(research_id),
		]
