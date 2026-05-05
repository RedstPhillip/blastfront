extends State


func enter():
	print("Entered Run");

func physics_update(delta: float):
	var direction: float = player.get_move_direction();

	player.velocity.x = direction * player.speed;

	if player.is_jump_pressed():
		state_machine.change_state("JumpState");
		return;

	player.move_and_slide();
	
	if (not player._ray_l.is_colliding() and not player._ray_r.is_colliding()):
		state_machine.change_state("FallState")
