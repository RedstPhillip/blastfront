class_name GrenadeDetonator
extends Node

var origin: Vector2
var delay: float = 0.5
var radius: float = 80.0
var damage: int = 10
var _elapsed: float = 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= delay:
		_explode()
		queue_free()


func _explode() -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return

	var players: Array[Node] = tree.get_nodes_in_group(GameSettings.PLAYERS_GROUP)
	for node in players:
		var player: Player = node as Player
		if player == null or player.is_eliminated():
			continue

		var dist: float = player.global_position.distance_to(origin)
		if dist > radius:
			continue

		var falloff: float = 1.0 - (dist / radius)
		var final_damage: int = maxi(1, int(roundf(damage * falloff)))
		player.health_component.damage(final_damage)
		player.apply_hit_feedback(origin, final_damage)
