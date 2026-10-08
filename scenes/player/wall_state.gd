extends State

## Sliding down a wall while holding into it; with Wall Jumps Mk III the slide starts with a short cling.

func physics_update(delta: float) -> void:
	var clinging: bool = player.update_wall_cling(delta)
	player.apply_horizontal_movement(
		delta,
		player.air_speed,
		player.air_acceleration,
		player.air_friction
	)
	if clinging:
		player.velocity.y = 0.0
	else:
		player.apply_gravity(delta, GameSettings.PLAYER_WALL_GRAVITY_MULTIPLIER)
		player.velocity.y = minf(player.velocity.y, player.wall_slide_speed)

	if player.can_wall_jump():
		player.wall_jump()
		state_machine.change_state("JumpState")
		return

	player.move_and_slide_scaled()
	player.update_visual_movement(delta)

	if not player.is_on_wall():
		state_machine.change_state("FallState")
		return

	if player.is_grounded():
		state_machine.change_state("RunState")
