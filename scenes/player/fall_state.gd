extends State

var fall_time := 0.0

@export var fall_curve: Curve
@export var fall_duration := 0.3
@export var fall_strength := 800

func enter():
	fall_time = 0.0;
	print("Entered Fall");

func physics_update(delta: float):
	var direction: float = player.get_move_direction();
	
	player.velocity.x = direction * player.air_speed;
	
	fall_time += delta;
	var t = clamp(fall_time / fall_duration, 0.0, 1.0);
	
	var curve_value = fall_curve.sample(t);
	player.velocity.y = curve_value * fall_strength;
		
	player.move_and_slide();
	
	if player.is_on_wall_only() and direction != 0:
		state_machine.change_state("WallState");
		return;
		
	if player._ray_l.is_colliding() or player._ray_r.is_colliding():
		state_machine.change_state("RunState")
