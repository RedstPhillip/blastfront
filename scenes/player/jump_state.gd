extends State
func physics_update(delta: float) -> void:
	player.apply_horizontal_movement(delta, player.speed, player.air_acceleration, player.air_friction)
	player.apply_better_jump_gravity(delta)

	player.move_and_slide()
	player.update_visual_movement(delta)

	if player.velocity.y >= 0.0:
		state_machine.change_state("FallState")
