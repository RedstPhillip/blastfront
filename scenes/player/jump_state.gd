extends State

var jump_time := 0.0

@export var jump_curve: Curve
@export var jump_duration := 0.3
@export var jump_strength := 900

func enter():
	jump_time = 0.0;
	print("Entered Jump");

func physics_update(delta: float):
	var direction = Input.get_axis("left", "right")
	player.velocity.x = direction * player.air_speed
	
	jump_time += delta
	var t = clamp(jump_time / jump_duration, 0.0, 1.0);
	var curve_value = jump_curve.sample(t)
	
	player.velocity.y = -jump_strength * curve_value
	
	player.move_and_slide()

	if player.velocity.y >= 0 or t >= 1.0:
		state_machine.change_state("FallState")
