extends State

## In the water (Tidewater's tide): the body floats with its head out, moves slowly and drifts on the
## surface. Jump near the surface leaps out of the water; deeper down it is a stroke towards the surface.
## The player script switches into this state when the water closes over the body.

func physics_update(delta: float) -> void:
	player.apply_horizontal_movement(delta, player.speed * Player.SWIM_SPEED_SCALE, Player.SWIM_ACCELERATION, Player.SWIM_FRICTION)
	player.apply_buoyancy(delta)

	if player.has_buffered_jump():
		if player.get_water_depth() <= Player.SWIM_LEAP_DEPTH:
			player.swim_leap()
			state_machine.change_state("JumpState")
			return
		player.swim_stroke()

	player.move_and_slide_scaled()
	player.update_visual_movement(delta)

	var depth: float = player.get_water_depth()
	if player.is_grounded() and depth < Player.SWIM_WADE_DEPTH:
		state_machine.change_state("RunState")
	elif depth < Player.SWIM_EXIT_DEPTH:
		state_machine.change_state("FallState")
