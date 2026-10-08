extends State

## The slide (Movement research): low along the ground under a smaller hitbox, easing from a burst to a jog;
## under a ceiling too low to stand it keeps crawling until there is room. Jumping out needs that room too.
## Running off a ledge ends it in the fall.

func enter() -> void:
	player.begin_slide()


func exit() -> void:
	player.end_slide()


func physics_update(delta: float) -> void:
	if player.has_buffered_jump() and player.can_jump() and player.has_headroom():
		player.jump_out_of_slide()
		state_machine.change_state("JumpState")
		return

	var finished: bool = player.update_slide(delta)
	player.move_and_slide_scaled()
	player.maintain_hover_height(delta)
	player.update_visual_movement(delta)

	if not player.is_grounded():
		state_machine.change_state("FallState")
	elif finished:
		state_machine.change_state("RunState")
