extends State

## The dash (Movement research): a flat burst along the held direction that ignores gravity until it runs
## out or meets a wall (it climbs low lips on the way), then hands back to running or falling. A jump on
## the ground cancels it and keeps the speed.

func enter() -> void:
	player.begin_dash()


func exit() -> void:
	player.end_dash()


func physics_update(delta: float) -> void:
	if player.has_buffered_jump() and player.can_jump():
		player.end_dash()
		player.jump()
		state_machine.change_state("JumpState")
		return

	player.velocity = Vector2(player.get_dash_direction() * GameSettings.PLAYER_DASH_SPEED, 0.0)
	player.move_and_slide_scaled()
	player.maintain_hover_height(delta)
	player.update_visual_movement(delta)

	# A lip in the ground should not stop the burst: hop onto it if there is room above.
	if player.is_on_wall() and player.try_dash_step_up():
		player.move_and_slide_scaled()
	if player.advance_dash(delta) or player.is_on_wall():
		state_machine.change_state("RunState" if player.is_grounded() else "FallState")
