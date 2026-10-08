extends State

func physics_update(delta: float) -> void:
	player.apply_ground_movement(delta)

	if player.has_buffered_jump() and player.can_jump():
		player.jump()
		state_machine.change_state("JumpState")
		return

	player.move_and_slide_scaled()
	player.maintain_hover_height(delta)
	player.update_visual_movement(delta)

	if not player.is_grounded():
		state_machine.change_state("FallState")
