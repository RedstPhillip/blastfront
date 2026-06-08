extends State

func physics_update(delta: float) -> void:
	var direction: float = player.apply_horizontal_movement(
		delta,
		player.air_speed,
		player.air_acceleration,
		player.air_friction
	)
	player.apply_gravity(delta, GameSettings.PLAYER_WALL_GRAVITY_MULTIPLIER)
	player.velocity.y = minf(player.velocity.y, player.wall_slide_speed)

	if player.can_wall_jump():
		player.wall_jump()
		state_machine.change_state("JumpState")
		return

	player.move_and_slide()
	player.update_visual_movement(delta)

	if not player.is_on_wall():
		state_machine.change_state("FallState")
		return

	if player.update_grounded():
		state_machine.change_state("RunState")
