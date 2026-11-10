extends State

## Ground Slam (Movement research): down in the air hangs for a beat, then dives straight to the floor. The
## landing thumps and, from Mk II, throws enemies close by (see Player.land_slam). A dash out of it (or the
## water closing over the body) ends it without the landing.

func enter() -> void:
	player.begin_slam()


func exit() -> void:
	player.end_slam()


func physics_update(delta: float) -> void:
	player.update_slam(delta)
	player.move_and_slide_scaled()
	player.update_visual_movement(delta)

	if player.is_grounded():
		player.land_slam()
		state_machine.change_state("RunState")
