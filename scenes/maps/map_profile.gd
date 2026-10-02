class_name MapProfile
extends Node

## Describes a playable world: its name, ambience loop and physical conditions. Lives in the map scene;
## applies its conditions while the map is loaded and restores the defaults when it leaves.

const GROUP: StringName = &"map_profile"

@export var world_id: StringName = &"verdant"
@export var display_name: String = "Verdant Ridge"
@export var ambience: StringName = &"ambience_wind"
@export_range(0.3, 1.5, 0.01) var gravity_scale: float = 1.0
@export_range(0.3, 1.5, 0.01) var projectile_gravity_scale: float = 1.0


func _enter_tree() -> void:
	add_to_group(GROUP)
	WorldConditions.gravity_scale = gravity_scale
	WorldConditions.projectile_gravity_scale = projectile_gravity_scale
	WorldConditions.wind = Vector2.ZERO


func _exit_tree() -> void:
	WorldConditions.reset()


static func current(tree: SceneTree) -> MapProfile:
	return tree.get_first_node_in_group(GROUP) as MapProfile
