extends State
func physics_update(delta: float) -> void:
	var direction: float = player.apply_horizontal_movement(delta, player.speed, player.air_acceleration, player.air_friction)
	player.apply_better_jump_gravity(delta)

	if player.has_buffered_jump() and player.can_jump():
		player.jump()
		state_machine.change_state("JumpState")
		return

	if player.can_wall_jump():
		player.wall_jump()
		state_machine.change_state("JumpState")
		return

	player.move_and_slide()
	player.update_visual_movement(delta)

	if player.is_on_wall() and direction != 0:
		state_machine.change_state("WallState")
		return

	if player.update_grounded():
		state_machine.change_state("RunState")
