extends State


func enter():
	print("Entered Wall");

func physics_update(delta: float):
	player.velocity.y += player.gravity * delta;
	
	if player.velocity.y > player.wall_slide_speed:
		player.velocity.y = player.wall_slide_speed;
	
	player.move_and_slide();
	
	if not player.is_on_wall() or Input.get_axis("left", "right") == 0:
		state_machine.change_state("FallState");
		
	if player._ray_l.is_colliding() or player._ray_r.is_colliding():
		state_machine.change_state("RunState")
