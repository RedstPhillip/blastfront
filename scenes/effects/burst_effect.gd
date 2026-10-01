extends Node2D

## One-shot composite effect. Built from FxLib emitters, glow flashes, rings and light flashes;
## frees itself once every child has finished.

const DUST_COLOR: Color = Color(0.78, 0.76, 0.64, 0.5)
const SPARK_COLOR: Color = Color(1.0, 0.78, 0.36, 1.0)
const SHIELD_COLOR: Color = Color(0.55, 0.95, 1.0, 1.0)

var _kind: StringName = &"run_dust"
var _direction: Vector2 = Vector2.UP
var _tint: Color = Color.WHITE
var _power: float = 1.0
var _life: float = 0.5


func configure(kind: StringName, direction: Vector2, tint: Color = Color.WHITE, power: float = 1.0) -> void:
	_kind = kind
	_direction = direction.normalized() if direction.length_squared() > GameSettings.PLAYER_MIN_VECTOR_LENGTH_SQUARED else Vector2.UP
	_tint = tint
	_power = maxf(power, 0.1)


func _ready() -> void:
	_build()
	var timer: SceneTreeTimer = get_tree().create_timer(_life + 0.35, false)
	timer.timeout.connect(queue_free)


func _track(lifetime: float) -> void:
	_life = maxf(_life, lifetime)


func _emit(params: Dictionary) -> void:
	_track(float(params.get("lifetime", 0.4)) * (1.0 + float(params.get("lifetime_randomness", 0.35))))
	FxLib.emit(self, params)


func _build() -> void:
	match _kind:
		&"run_dust":
			_emit({"amount": 3, "lifetime": 0.42, "direction": Vector2(-_direction.x, -0.35), "spread": 25.0,
				"speed": Vector2(20.0, 60.0), "gravity": Vector2(0, -18), "size": Vector2(0.18, 0.3), "curve": &"puff",
				"color": DUST_COLOR, "damping": Vector2(40, 90)})
		&"wall_dust":
			_emit({"amount": 2, "lifetime": 0.35, "direction": Vector2(_direction.x, -0.6), "spread": 30.0,
				"speed": Vector2(20.0, 50.0), "gravity": Vector2(0, 30), "size": Vector2(0.12, 0.22), "curve": &"puff",
				"color": DUST_COLOR})
			_emit({"texture": FxLib.TEX_DOT, "amount": 2, "lifetime": 0.3, "direction": Vector2(_direction.x, -0.4),
				"spread": 35.0, "speed": Vector2(40.0, 90.0), "gravity": Vector2(0, 500), "size": Vector2(0.07, 0.12),
				"color": Color(0.55, 0.62, 0.45, 0.9)})
		&"jump":
			_emit({"amount": 7, "lifetime": 0.45, "direction": Vector2(0.0, 0.2), "spread": 95.0,
				"speed": Vector2(50.0, 130.0), "gravity": Vector2(0, -30), "size": Vector2(0.2, 0.36), "curve": &"puff",
				"color": DUST_COLOR, "damping": Vector2(120, 220)})
			FxLib.ring(self, Color(1, 1, 1, 0.22), 10.0, 54.0, 0.28, false)
			_track(0.3)
		&"land":
			var strength: float = clampf(_power, 0.4, 1.6)
			_emit({"amount": int(8 * strength), "lifetime": 0.5, "direction": Vector2.RIGHT, "spread": 180.0,
				"speed": Vector2(60.0, 170.0) * strength, "gravity": Vector2(0, -20), "size": Vector2(0.22, 0.42) * strength,
				"curve": &"puff", "color": DUST_COLOR, "damping": Vector2(180, 300), "radius": 6.0})
			_emit({"texture": FxLib.TEX_DEBRIS, "amount": int(5 * strength), "lifetime": 0.45, "direction": Vector2.UP,
				"spread": 70.0, "speed": Vector2(90.0, 200.0) * strength, "gravity": Vector2(0, 900), "size": Vector2(0.12, 0.24),
				"color": Color(0.36, 0.42, 0.3, 1.0), "spin": Vector2(-400, 400)})
			if strength > 1.0:
				FxLib.ring(self, Color(1, 1, 1, 0.3), 16.0, 90.0 * strength, 0.32, false)
		&"hit":
			_build_hit(1.0)
		&"hit_heavy":
			_build_hit(1.6)
		&"impact":
			_build_impact()
		&"block":
			_build_block(SHIELD_COLOR)
		&"reflect":
			_build_block(Color(1.0, 0.92, 0.55, 1.0))
		&"freeze":
			_emit({"texture": FxLib.TEX_SPARK, "amount": 8, "lifetime": 0.4, "direction": _direction, "spread": 180.0,
				"speed": Vector2(40.0, 120.0), "gravity": Vector2(0, 160), "size": Vector2(0.25, 0.45), "align": true,
				"color": Color(0.7, 0.95, 1.0, 0.95), "additive": true})
			_emit({"texture": FxLib.TEX_DOT, "amount": 8, "lifetime": 0.6, "direction": Vector2.UP, "spread": 180.0,
				"speed": Vector2(10.0, 50.0), "gravity": Vector2(0, -20), "size": Vector2(0.08, 0.16), "curve": &"pop",
				"color": Color(0.9, 0.98, 1.0, 0.9)})
			FxLib.ring(self, Color(0.55, 0.88, 1.0, 0.4), 6.0, 40.0, 0.3)
			_spawn_iceflakes(4)
			_track(0.6)
		&"shock":
			_emit({"texture": FxLib.TEX_SPARK, "amount": 10, "lifetime": 0.22, "direction": _direction, "spread": 180.0,
				"speed": Vector2(120.0, 280.0), "gravity": Vector2(0, 200), "size": Vector2(0.3, 0.55), "align": true,
				"color": Color(1.0, 0.95, 0.4, 1.0), "additive": true})
			FxLib.glow_flash(self, Color(1.0, 0.9, 0.3, 0.5), 60.0, 0.18)
			_spawn_electric_arcs(4)
			_track(0.3)
		&"poison":
			_emit({"amount": 5, "lifetime": 0.7, "direction": Vector2.UP, "spread": 50.0, "speed": Vector2(15.0, 45.0),
				"gravity": Vector2(0, -60), "size": Vector2(0.1, 0.22), "curve": &"pop", "color": Color(0.45, 1.0, 0.35, 0.75),
				"radius": 10.0})
		&"spawn":
			_build_spawn()
		&"death":
			_build_death()
		&"explosion":
			_build_explosion()
		&"capture":
			_emit({"texture": FxLib.TEX_SPARK, "amount": 26, "lifetime": 0.8, "direction": Vector2.UP, "spread": 70.0,
				"speed": Vector2(160.0, 380.0), "gravity": Vector2(0, 420), "size": Vector2(0.3, 0.6), "align": true,
				"color": Color(1.0, 0.82, 0.35, 1.0), "additive": true, "fade": &"late"})
			FxLib.ring(self, Color(1.0, 0.8, 0.35, 0.8), 20.0, 220.0, 0.6)
			FxLib.glow_flash(self, Color(1.0, 0.82, 0.4, 0.8), 220.0, 0.5)
			FxLib.light_flash(self, Color(1.0, 0.8, 0.45), 1.6, 260.0, 0.6)
			_track(0.9)
		&"border":
			_emit({"texture": FxLib.TEX_SPARK, "amount": 22, "lifetime": 0.35, "direction": _direction, "spread": 70.0,
				"speed": Vector2(200.0, 460.0), "gravity": Vector2(0, 400), "size": Vector2(0.35, 0.7), "align": true,
				"color": Color(1.0, 0.3, 0.3, 1.0), "additive": true})
			FxLib.ring(self, Color(1.0, 0.25, 0.25, 0.75), 8.0, 120.0, 0.35)
			FxLib.glow_flash(self, Color(1.0, 0.25, 0.2, 0.6), 140.0, 0.3)
			_track(0.4)
		_:
			_emit({"amount": 10, "lifetime": 0.35, "direction": _direction, "spread": 60.0, "speed": Vector2(60.0, 150.0),
				"size": Vector2(0.2, 0.4), "color": _tint})


func _build_hit(intensity: float) -> void:
	var paint: Color = Color(_tint.r, _tint.g, _tint.b, 1.0)
	_emit({"texture": FxLib.TEX_DOT, "amount": int(12 * intensity), "lifetime": 0.55, "direction": _direction, "spread": 48.0,
		"speed": Vector2(140.0, 360.0) * intensity, "gravity": Vector2(0, 980), "size": Vector2(0.14, 0.32), "curve": &"shrink",
		"color": paint, "damping": Vector2(10, 40), "fade": &"late"})
	_emit({"texture": FxLib.TEX_SPARK, "amount": int(7 * intensity), "lifetime": 0.2, "direction": _direction, "spread": 38.0,
		"speed": Vector2(260.0, 520.0), "gravity": Vector2(0, 300), "size": Vector2(0.3, 0.55), "align": true,
		"color": Color(1.0, 0.96, 0.85, 1.0), "additive": true})
	FxLib.glow_flash(self, Color(1.0, 1.0, 1.0, 0.55), 70.0 * intensity, 0.14)
	FxLib.ring(self, Color(paint.r, paint.g, paint.b, 0.6), 8.0, 64.0 * intensity, 0.24)
	_track(0.65)


func _build_impact() -> void:
	var normal: Vector2 = _direction
	_emit({"texture": FxLib.TEX_SPARK, "amount": 9, "lifetime": 0.22, "direction": normal, "spread": 62.0,
		"speed": Vector2(180.0, 420.0), "gravity": Vector2(0, 820), "size": Vector2(0.22, 0.42), "align": true,
		"color": SPARK_COLOR, "additive": true, "damping": Vector2(0, 40)})
	_emit({"amount": 3, "lifetime": 0.55, "direction": normal, "spread": 40.0, "speed": Vector2(25.0, 70.0),
		"gravity": Vector2(0, -25), "size": Vector2(0.22, 0.38), "curve": &"puff", "color": Color(0.7, 0.72, 0.64, 0.42),
		"damping": Vector2(40, 90)})
	_emit({"texture": FxLib.TEX_DEBRIS, "amount": 4, "lifetime": 0.5, "direction": normal, "spread": 55.0,
		"speed": Vector2(90.0, 220.0), "gravity": Vector2(0, 980), "size": Vector2(0.1, 0.2), "spin": Vector2(-600, 600),
		"color": Color(0.24, 0.3, 0.22, 1.0), "fade": &"late"})
	FxLib.glow_flash(self, Color(1.0, 0.72, 0.35, 0.5), 46.0, 0.12)
	_track(0.6)


func _build_block(color: Color) -> void:
	_emit({"texture": FxLib.TEX_SPARK, "amount": 16, "lifetime": 0.3, "direction": _direction, "spread": 75.0,
		"speed": Vector2(220.0, 480.0), "gravity": Vector2(0, 520), "size": Vector2(0.3, 0.6), "align": true,
		"color": color, "additive": true})
	_emit({"texture": FxLib.TEX_DOT, "amount": 8, "lifetime": 0.4, "direction": _direction, "spread": 90.0,
		"speed": Vector2(60.0, 180.0), "gravity": Vector2(0, 200), "size": Vector2(0.06, 0.12), "curve": &"pop",
		"color": Color(1, 1, 1, 0.95), "additive": true})
	FxLib.ring(self, Color(color.r, color.g, color.b, 0.85), 10.0, 92.0, 0.26)
	FxLib.glow_flash(self, Color(color.r, color.g, color.b, 0.75), 120.0, 0.2)
	FxLib.light_flash(self, color, 1.2, 140.0, 0.22)
	_track(0.45)


func _build_spawn() -> void:
	var spawn_color: Color = _tint.lerp(Color(0.75, 0.95, 1.0, 1.0), 0.35)
	_emit({"texture": FxLib.TEX_SPARK, "amount": 20, "lifetime": 0.7, "direction": Vector2.UP, "spread": 18.0,
		"speed": Vector2(120.0, 320.0), "gravity": Vector2(0, -60), "size": Vector2(0.25, 0.5), "align": true,
		"color": spawn_color, "additive": true, "radius": 14.0, "fade": &"late"})
	_emit({"amount": 10, "lifetime": 0.6, "direction": Vector2.RIGHT, "spread": 180.0, "speed": Vector2(60.0, 160.0),
		"gravity": Vector2(0, -20), "size": Vector2(0.2, 0.4), "curve": &"puff", "color": Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.35),
		"damping": Vector2(160, 260)})
	FxLib.ring(self, Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.9), 12.0, 150.0, 0.45)
	FxLib.glow_flash(self, Color(spawn_color.r, spawn_color.g, spawn_color.b, 0.9), 160.0, 0.45)
	FxLib.light_flash(self, spawn_color, 1.4, 220.0, 0.5)
	_spawn_light_column(spawn_color)
	_track(0.8)


func _build_death() -> void:
	var paint: Color = Color(_tint.r, _tint.g, _tint.b, 1.0)
	_emit({"texture": FxLib.TEX_DOT, "amount": 34, "lifetime": 0.9, "direction": Vector2.UP, "spread": 180.0,
		"speed": Vector2(180.0, 620.0), "gravity": Vector2(0, 1100), "size": Vector2(0.18, 0.48), "color": paint,
		"damping": Vector2(0, 30), "fade": &"late"})
	_emit({"texture": FxLib.TEX_DEBRIS, "amount": 12, "lifetime": 1.0, "direction": Vector2.UP, "spread": 160.0,
		"speed": Vector2(200.0, 520.0), "gravity": Vector2(0, 1200), "size": Vector2(0.35, 0.7), "color": paint.darkened(0.15),
		"spin": Vector2(-720, 720), "fade": &"late"})
	_emit({"texture": FxLib.TEX_SPARK, "amount": 22, "lifetime": 0.35, "direction": Vector2.UP, "spread": 180.0,
		"speed": Vector2(300.0, 760.0), "gravity": Vector2(0, 300), "size": Vector2(0.35, 0.7), "align": true,
		"color": Color(1.0, 0.95, 0.85, 1.0), "additive": true})
	_emit({"texture": FxLib.TEX_SMOKE, "amount": 7, "lifetime": 1.1, "direction": Vector2.UP, "spread": 180.0,
		"speed": Vector2(30.0, 110.0), "gravity": Vector2(0, -40), "size": Vector2(0.4, 0.75), "curve": &"puff",
		"color": paint.darkened(0.5).lerp(Color(0.2, 0.22, 0.22), 0.5), "fade": &"smoke", "spin": Vector2(-60, 60),
		"damping": Vector2(60, 120)})
	FxLib.ring(self, Color(1.0, 1.0, 1.0, 0.9), 18.0, 240.0, 0.5)
	FxLib.ring(self, Color(paint.r, paint.g, paint.b, 0.8), 10.0, 170.0, 0.65)
	FxLib.glow_flash(self, Color(1.0, 0.95, 0.85, 1.0), 260.0, 0.35)
	FxLib.light_flash(self, paint.lightened(0.3), 2.4, 320.0, 0.6)
	_track(1.4)


func _build_explosion() -> void:
	var p: float = _power
	_emit({"texture": FxLib.TEX_GLOW, "amount": 10, "lifetime": 0.42, "direction": Vector2.UP, "spread": 180.0,
		"speed": Vector2(40.0, 140.0) * p, "gravity": Vector2(0, -160), "size": Vector2(0.45, 0.85) * p, "curve": &"pop",
		"color": Color(1, 1, 1, 1), "fade": &"fire", "additive": true, "radius": 10.0 * p, "z": 3})
	_emit({"texture": FxLib.TEX_SMOKE, "amount": 12, "lifetime": 1.3, "direction": Vector2.UP, "spread": 180.0,
		"speed": Vector2(40.0, 160.0) * p, "gravity": Vector2(0, -70), "size": Vector2(0.45, 0.95) * p, "curve": &"puff",
		"color": Color(0.16, 0.15, 0.15, 0.9), "fade": &"smoke", "spin": Vector2(-50, 50), "damping": Vector2(80, 160),
		"radius": 14.0 * p})
	_emit({"texture": FxLib.TEX_SPARK, "amount": 30, "lifetime": 0.55, "direction": Vector2.UP, "spread": 180.0,
		"speed": Vector2(280.0, 760.0) * p, "gravity": Vector2(0, 900), "size": Vector2(0.35, 0.75), "align": true,
		"color": Color(1.0, 0.75, 0.3, 1.0), "additive": true, "damping": Vector2(0, 30)})
	_emit({"texture": FxLib.TEX_DEBRIS, "amount": 12, "lifetime": 0.9, "direction": Vector2.UP, "spread": 120.0,
		"speed": Vector2(200.0, 520.0) * p, "gravity": Vector2(0, 1300), "size": Vector2(0.15, 0.35), "spin": Vector2(-720, 720),
		"color": Color(0.12, 0.13, 0.12, 1.0), "fade": &"late"})
	FxLib.ring(self, Color(1.0, 0.85, 0.6, 0.95), 20.0, 230.0 * p, 0.42)
	FxLib.ring(self, Color(1.0, 1.0, 1.0, 0.5), 10.0, 150.0 * p, 0.25)
	FxLib.glow_flash(self, Color(1.0, 0.8, 0.45, 1.0), 300.0 * p, 0.4)
	FxLib.light_flash(self, Color(1.0, 0.65, 0.3), 2.8, 360.0 * p, 0.7)
	_track(1.7)


func _spawn_light_column(color: Color) -> void:
	var beam: Sprite2D = Sprite2D.new()
	beam.texture = FxLib.TEX_GLOW
	beam.material = FxLib.additive_material()
	beam.modulate = Color(color.r, color.g, color.b, 0.75)
	beam.scale = Vector2(0.18, 2.4)
	beam.position = Vector2(0, -90)
	beam.z_index = 1
	add_child(beam)
	var tween: Tween = beam.create_tween().set_parallel(true)
	tween.tween_property(beam, "scale:x", 0.02, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_property(beam, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _spawn_iceflakes(count: int) -> void:
	var flake_count: int = maxi(1, int(roundf(float(count) * GameJuice.particles_multiplier)))
	if GameJuice.particles_multiplier <= 0.0:
		return
	for flake_index in range(flake_count):
		var flake: Node2D = Node2D.new()
		flake.z_index = 5
		flake.position = Vector2(randf_range(-16.0, 16.0), randf_range(-18.0, 12.0))
		flake.rotation = randf_range(0.0, TAU)
		flake.scale = Vector2.ONE * randf_range(0.75, 1.35)
		flake.modulate = Color(0.8, 0.96, 1.0, 0.95)
		add_child(flake)
		var radius: float = randf_range(4.0, 7.5)
		for arm_index in range(3):
			var arm: Line2D = Line2D.new()
			arm.width = 1.2
			arm.default_color = Color(0.82, 0.97, 1.0, 0.9)
			arm.antialiased = true
			arm.rotation = float(arm_index) * TAU / 3.0
			arm.points = PackedVector2Array([Vector2(-radius, 0.0), Vector2(radius, 0.0)])
			flake.add_child(arm)
		var tween: Tween = flake.create_tween().set_parallel(true)
		tween.tween_property(flake, "position", flake.position + Vector2(randf_range(-8.0, 8.0), randf_range(-24.0, -8.0)), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(flake, "rotation", flake.rotation + randf_range(-1.4, 1.4), 0.5)
		tween.tween_property(flake, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _spawn_electric_arcs(count: int) -> void:
	if GameJuice.particles_multiplier <= 0.0:
		return
	var arc_count: int = maxi(1, int(roundf(float(count) * GameJuice.particles_multiplier)))
	for arc_index in range(arc_count):
		var arc: Line2D = Line2D.new()
		arc.z_index = 6
		arc.width = randf_range(1.6, 2.6)
		arc.default_color = Color(1.0, 0.96, 0.5, 1.0)
		arc.material = FxLib.additive_material()
		arc.antialiased = true
		arc.points = _build_electric_arc_points(randf_range(16.0, 28.0), randi_range(4, 6))
		arc.rotation = randf_range(0.0, TAU)
		arc.position = Vector2(randf_range(-6.0, 6.0), randf_range(-10.0, 10.0))
		add_child(arc)
		var tween: Tween = arc.create_tween().set_parallel(true)
		tween.tween_property(arc, "scale", Vector2.ONE * randf_range(1.2, 1.6), 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(arc, "modulate:a", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _build_electric_arc_points(length: float, segment_count: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var half_length: float = length * 0.5
	for point_index in range(segment_count + 1):
		var ratio: float = float(point_index) / float(segment_count)
		var y: float = 0.0 if point_index == 0 or point_index == segment_count else randf_range(-5.0, 5.0)
		points.append(Vector2(lerpf(-half_length, half_length, ratio), y))
	return points
