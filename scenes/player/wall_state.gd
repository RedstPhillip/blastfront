extends State


func enter():
	pass

func physics_update(delta: float):
	var direction: float = player.get_move_direction()

	player.velocity.x = move_toward(player.velocity.x, direction * player.air_speed, player.air_acceleration * delta)
	player.apply_gravity(delta, 0.55)
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
