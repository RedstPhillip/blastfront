class_name HudRewardFlight
extends Control

## Research points travelling from where they were won to the research counter in the HUD. The tokens
## burst out of the source, hang for a beat, then fly in one after another on a curve; each arrival ticks
## the counter up with a rising note, and the last one lands with the reward chime. The counter holds the
## new total back until the tokens arrive, so the number and the motion tell the same story.

const GROUP: StringName = &"hud_reward_flight"
const COUNTER_GROUP: StringName = &"hud_rp_counter"
const BURST_SECONDS: float = 0.42
const FLIGHT_SECONDS: float = 0.5
const STAGGER: float = 0.075

var _tokens: Array[Dictionary] = []


## world_position is in the game world; amount is how many points (one token each, at most 12).
static func launch(world_position: Vector2, amount: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or amount <= 0:
		return
	var host: HudRewardFlight = tree.get_first_node_in_group(GROUP) as HudRewardFlight
	if host != null:
		host.spawn(world_position, amount)


## Same as launch, from a point already in screen space (e.g. an order row in the HUD).
static func launch_from_screen(screen_position: Vector2, amount: int) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null or amount <= 0:
		return
	var host: HudRewardFlight = tree.get_first_node_in_group(GROUP) as HudRewardFlight
	if host != null:
		host.spawn_screen(screen_position, amount)


func _ready() -> void:
	add_to_group(GROUP)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)


func spawn(world_position: Vector2, amount: int) -> void:
	spawn_screen(get_viewport().get_canvas_transform() * world_position, amount)


func spawn_screen(origin: Vector2, amount: int) -> void:
	var counter: Node = get_tree().get_first_node_in_group(COUNTER_GROUP)
	if counter != null and counter.has_method(&"reserve_points"):
		counter.reserve_points(amount)
	var count: int = mini(amount, 12)
	for index in range(count):
		var angle: float = -PI * 0.5 + lerpf(-0.9, 0.9, (float(index) + 0.5) / float(count)) + randf_range(-0.12, 0.12)
		_tokens.append({
			"p": origin,
			"v": Vector2.from_angle(angle) * randf_range(170.0, 240.0),
			"t": -float(index) * 0.012,
			"index": index,
			"last": index == count - 1,
			"extra": (amount - count) if index == count - 1 else 0,
			"from": Vector2.ZERO,
			"spin": randf_range(-4.0, 4.0),
		})
	set_process(true)


func _target() -> Vector2:
	var counter: Node = get_tree().get_first_node_in_group(COUNTER_GROUP)
	if counter != null and counter.has_method(&"get_points_target"):
		return counter.get_points_target()
	return Vector2(48.0, 40.0)


func _process(delta: float) -> void:
	var target: Vector2 = _target()
	for index in range(_tokens.size() - 1, -1, -1):
		var token: Dictionary = _tokens[index]
		token["t"] = float(token["t"]) + delta
		var t: float = float(token["t"])
		if t < 0.0:
			continue
		var launch_at: float = BURST_SECONDS + float(token["index"]) * STAGGER
		if t < launch_at:
			# Burst: thrown out, slowing to a hover.
			var v: Vector2 = token["v"]
			v = v * exp(-6.5 * delta)
			token["v"] = v
			token["p"] = (token["p"] as Vector2) + v * delta
			token["from"] = token["p"]
			continue
		var f: float = clampf((t - launch_at) / FLIGHT_SECONDS, 0.0, 1.0)
		var eased: float = f * f * (2.2 - 1.2 * f)
		var from: Vector2 = token["from"]
		var control: Vector2 = from.lerp(target, 0.35) + Vector2(0.0, -90.0)
		token["p"] = from.lerp(control, eased).lerp(control.lerp(target, eased), eased)
		if f >= 1.0:
			_arrive(token)
			_tokens.remove_at(index)
	queue_redraw()
	if _tokens.is_empty():
		set_process(false)


func _arrive(token: Dictionary) -> void:
	var counter: Node = get_tree().get_first_node_in_group(COUNTER_GROUP)
	if counter != null and counter.has_method(&"release_points"):
		counter.release_points(1 + int(token["extra"]))
	AudioDirector.play(&"research_tick", -2.0, 1.0 + 0.07 * float(token["index"]))
	if token["last"]:
		AudioDirector.play(&"research_reward")


func _draw() -> void:
	for token in _tokens:
		var t: float = float(token["t"])
		if t < 0.0:
			continue
		var p: Vector2 = token["p"]
		var appear: float = clampf(t / 0.08, 0.0, 1.0)
		var radius: float = 6.5 * appear
		ResearchNodeButton.draw_rp_glyph(self, p, radius + 2.0, Color(0.0, 0.03, 0.03, 0.7 * appear))
		ResearchNodeButton.draw_rp_glyph(self, p, radius, UiStyle.TEAL.lerp(Color.WHITE, 0.15))
