class_name TidewaterColumns
extends Node2D

## The columns the temple's floors stand on: scenery behind the terrain, nothing to stand on or bump into.
## Dark and flat like the ruins further out, so they read as background, with only a thin moonlit edge.
## Each entry of `columns` is (x, top y, foot y); one mesh for all of them.

@export var columns: PackedVector3Array = PackedVector3Array()
## World x of the moon: the side of each shaft that gets the lit edge.
@export var moon_x: float = 690.0
@export var top_color: Color = Color(0.07, 0.145, 0.175)
@export var foot_color: Color = Color(0.045, 0.1, 0.125)
@export var rim_color: Color = Color(0.5, 0.78, 0.76, 0.32)
@export var shaft_width: float = 13.0


func _ready() -> void:
	var mesh: BackdropMesh = BackdropMesh.new()
	for column in columns:
		_column(mesh, column.x, column.y, column.z)
	mesh.commit(self, "Columns")


func _column(mesh: BackdropMesh, x: float, top: float, foot: float) -> void:
	var half: float = shaft_width * 0.5
	var half_top: float = half * 0.86
	var flute: Color = Color(foot_color.r * 0.72, foot_color.g * 0.72, foot_color.b * 0.72, 0.7)
	# Abacus and echinus under the floor it carries, the shaft, the plinth.
	mesh.box(Rect2(x - half - 4.0, top, shaft_width + 8.0, 4.0), top_color, top_color)
	mesh.quad(Vector2(x - half - 2.0, top + 4.0), Vector2(x + half + 2.0, top + 4.0), Vector2(x + half_top, top + 9.0), Vector2(x - half_top, top + 9.0), top_color)
	mesh.quad_colors(Vector2(x - half_top, top + 9.0), Vector2(x + half_top, top + 9.0), Vector2(x + half, foot - 5.0), Vector2(x - half, foot - 5.0), top_color, top_color, foot_color, foot_color)
	mesh.box(Rect2(x - half - 3.0, foot - 5.0, shaft_width + 6.0, 5.0), foot_color, foot_color)
	for offset in [-0.26, 0.2]:
		mesh.box(Rect2(x + shaft_width * float(offset), top + 13.0, 1.1, maxf(foot - top - 22.0, 1.0)), flute, flute)
	var lit: float = signf(moon_x - x) if absf(moon_x - x) > 1.0 else 1.0
	var clear: Color = Color(rim_color.r, rim_color.g, rim_color.b, 0.0)
	var edge: float = x + lit * half_top
	mesh.quad_colors(Vector2(edge, top + 10.0), Vector2(edge - lit * 1.8, top + 10.0), Vector2(edge - lit * 1.8, foot - 6.0), Vector2(edge, foot - 6.0), rim_color, clear, clear, rim_color)
