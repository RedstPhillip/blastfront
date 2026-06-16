extends Node2D
class_name AirdropCrate

var _phase: StringName = &"inactive"
var _descent_progress: float = 0.0
var _capture_progress: float = 0.0
var _capturing_slot: int = 0
var _capture_radius: float = GameSettings.AIRDROP_BASE_CAPTURE_RADIUS
var _visual_time: float = 0.0
var _land_feedback_played: bool = false
var _capture_feedback_played: bool = false

@onready var _marker: Sprite2D = %Marker
@onready var _capture_ring: Line2D = %CaptureRing
@onready var _rig: Node2D = %Rig
@onready var _parachute: Sprite2D = %Parachute
@onready var _ropes: Node2D = %Ropes
@onready var _crate: Sprite2D = %Crate
@onready var _capture_panel: PanelContainer = %CapturePanel
@onready var _capture_bar: ProgressBar = %CaptureBar
@onready var _capture_label: Label = %CaptureLabel
@onready var _reward_label: Label = %RewardLabel
@onready var _light: PointLight2D = %PointLight2D


func _ready() -> void:
	_build_capture_ring()
	_apply_visual_state()


func apply_state(state: Dictionary) -> void:
	var previous_phase: StringName = _phase
	_phase = StringName(str(state.get("phase", str(_phase))))
	_descent_progress = clampf(float(state.get("descent_progress", _descent_progress)), 0.0, 1.0)
	_capture_progress = clampf(float(state.get("capture_progress", _capture_progress)), 0.0, 1.0)
	_capturing_slot = int(state.get("capturing_slot", _capturing_slot))
	var next_radius: float = maxf(float(state.get("local_capture_radius", _capture_radius)), 24.0)
	if not is_equal_approx(next_radius, _capture_radius):
		_capture_radius = next_radius
		_build_capture_ring()
	_reward_label.text = "+%d RESEARCH" % int(state.get("local_reward", GameSettings.AIRDROP_BASE_RESEARCH_REWARD))
	if previous_phase != _phase:
		_on_phase_transition(previous_phase, _phase)
	_apply_visual_state()


func _process(delta: float) -> void:
	_visual_time += delta
	_marker.rotation += delta * 0.14
	_marker.modulate.a = 0.48 + sin(_visual_time * 3.0) * 0.12
	_capture_ring.modulate.a = 0.34 + sin(_visual_time * 2.4) * 0.08
	if _phase == &"falling":
		var eased_progress: float = 1.0 - pow(1.0 - _descent_progress, 2.2)
		_rig.position.y = lerpf(-470.0, 0.0, eased_progress)
		_rig.position.x = sin(_visual_time * 2.1) * (7.0 * (1.0 - _descent_progress))
		_rig.rotation = sin(_visual_time * 1.8) * 0.025
	elif _phase == &"landed":
		_rig.position = _rig.position.lerp(Vector2.ZERO, clampf(delta * 12.0, 0.0, 1.0))
		_rig.rotation = lerpf(_rig.rotation, 0.0, clampf(delta * 12.0, 0.0, 1.0))
	_capture_bar.value = _capture_progress * 100.0
	if _light.visible:
		_light.energy = 0.52 + sin(_visual_time * 4.0) * 0.08


func _apply_visual_state() -> void:
	var warning: bool = _phase == &"warning"
	var falling: bool = _phase == &"falling"
	var landed: bool = _phase == &"landed"
	_parachute.visible = falling
	_ropes.visible = falling
	_capture_ring.visible = landed
	_capture_panel.visible = landed
	_marker.visible = warning or falling
	_crate.visible = falling or landed
	_light.visible = warning or falling or landed
	_reward_label.text = ""
	_reward_label.visible = false
	_capture_label.text = ""
	_capture_label.visible = false
	var labels: Control = _capture_label.get_parent() as Control
	if labels != null:
		labels.visible = false


func _on_phase_transition(_previous_phase: StringName, next_phase: StringName) -> void:
	if next_phase == &"landed" and not _land_feedback_played:
		_land_feedback_played = true
		GameJuice.spawn_burst(&"impact", global_position, Vector2.UP, Color(0.92, 0.62, 0.24, 0.9))
		GameJuice.play_sound_2d(&"impact", global_position, -3.0, 0.03)
		GameJuice.shake(2.2, 0.12)
	elif next_phase == &"captured" and not _capture_feedback_played:
		_capture_feedback_played = true
		GameJuice.spawn_burst(&"spawn", global_position, Vector2.UP, Color(0.95, 0.75, 0.3, 0.95))
		GameJuice.play_sound_2d(&"spawn", global_position, -1.0, 0.02)
		GameJuice.shake(1.5, 0.09)


func _build_capture_ring() -> void:
	if _capture_ring == null:
		return
	var points: PackedVector2Array = PackedVector2Array()
	var segments: int = 64
	for point_index in range(segments + 1):
		var angle: float = TAU * float(point_index) / float(segments)
		points.append(Vector2(cos(angle), sin(angle) * 0.28) * _capture_radius)
	_capture_ring.points = points
