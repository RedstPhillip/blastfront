extends State


func enter():
	print("Entered Run");

func physics_update(delta: float):
	var direction = Input.get_axis("left", "right");

	player.velocity.x = direction * player.speed;
	player.move_and_slide();
	
	if (not player._ray_l.is_colliding() and not player._ray_r.is_colliding()):
		state_machine.change_state("FallState")

func handle_input(event: InputEvent):
	if event.is_action_pressed("jump"):
		state_machine.change_state("JumpState");
