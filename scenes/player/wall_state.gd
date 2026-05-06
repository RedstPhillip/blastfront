extends State


func enter():
	pass

func physics_update(delta: float):
	var direction: float = player.get_move_direction()

	player.velocity.x = move_toward(player.velocity.x, direction * player.air_speed, player.air_acceleration * delta)
	player.apply_gravity(delta, 0.55)
	player.velocity.y = minf(player.velocity.y, player.wall_slide_speed)

	if player.has_buffered_jump():
		var wall_direction := signf(direction)
		if wall_direction == 0.0:
			wall_direction = -signf(player.get_wall_normal().x)
		player.velocity.x = -wall_direction * player.wall_jump_velocity.x
		player.velocity.y = player.wall_jump_velocity.y
		player.consume_jump_buffer()
		state_machine.change_state("JumpState")
		return
	
	player.move_and_slide()
	player.update_visual_movement(delta)
	
	if not player.is_on_wall() or direction == 0.0:
		state_machine.change_state("FallState")
		return
		
	if player.update_grounded():
		state_machine.change_state("RunState")
