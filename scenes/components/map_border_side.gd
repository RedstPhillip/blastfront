class_name MapBorderSide
extends Node2D

signal body_entered(body: Node)

@onready var _warning_line: ColorRect = $WarningLine
@onready var _particles: CPUParticles2D = $Particles
@onready var _border_area: Area2D = $BorderArea
@onready var _collision_shape: CollisionShape2D = $BorderArea/CollisionShape2D


func _ready() -> void:
	_border_area.body_entered.connect(_on_body_entered)


func configure(line_color: Color, collision_mask: int) -> void:
	_warning_line.color = line_color
	_border_area.collision_mask = collision_mask


func set_warning(rect: Rect2, particle_amount: int) -> void:
	_warning_line.position = rect.position
	_warning_line.size = rect.size
	_warning_line.show()

	_particles.position = rect.get_center()
	var emission_extents: Vector2 = rect.size * 0.5
	if rect.size.x < rect.size.y:
		emission_extents.x = rect.size.x * 1.5
	else:
		emission_extents.y = rect.size.y * 1.5
	_particles.emission_rect_extents = emission_extents
	_particles.amount = maxi(particle_amount, 1)
	_particles.visible = particle_amount > 0
	_particles.emitting = particle_amount > 0


func hide_warning() -> void:
	_warning_line.hide()
	_particles.emitting = false
	_particles.hide()


func set_collision_rect(center: Vector2, size: Vector2) -> void:
	_border_area.position = center
	var rectangle: RectangleShape2D = _collision_shape.shape as RectangleShape2D
	if rectangle != null:
		rectangle.size = size


func _on_body_entered(body: Node) -> void:
	body_entered.emit(body)
