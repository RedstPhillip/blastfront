extends State

func physics_update(delta: float) -> void:
	player.update_grounded()
	player.apply_horizontal_movement(delta, player.speed, player.ground_acceleration, player.ground_friction)

	if player.has_buffered_jump() and player.can_jump():
		player.jump()
		state_machine.change_state("JumpState")
		return

	player.move_and_slide()
	player.maintain_hover_height(delta)
	player.update_visual_movement(delta)

	if not player.update_grounded():
		state_machine.change_state("FallState")
