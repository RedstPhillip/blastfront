class_name KillCamRecorder
extends RefCounted

## The last few seconds of a round, kept for the kill cam: every physics frame each fighter's pose (position,
## velocity, aim, motion flags, health, own clock) and every round in flight (id, position, rotation, speed,
## look), plus one-shot events with their timestamps. Everything lives in preallocated packed arrays used as a
## ring, so recording allocates nothing but the per-frame list of rounds (and only while rounds fly).
## Times are game seconds (the physics delta, so hitstop and slow motion are recorded as they played).

const CAPACITY: int = 360
## How much of the past is kept at most; older frames and events are overwritten / dropped.
const SECONDS: float = 5.0
const MAX_EVENTS: int = 48
const FIGHTERS: int = 2
## Floats per round in flight: replay id, x, y, rotation, speed, style index, scale.
const ROUND_STRIDE: int = 7
const AIM_REACH: float = 140.0

const FLAG_ELIMINATED: int = 1
const FLAG_FACING_LEFT: int = 1 << 1
const FLAG_GROUNDED: int = 1 << 2
const FLAG_SLIDE: int = 1 << 3
const FLAG_SLAM: int = 1 << 4
const FLAG_DASH: int = 1 << 5
const FLAG_BLOCK: int = 1 << 6
const FLAG_CLING: int = 1 << 7
const FLAG_WALL_LEFT: int = 1 << 8
const FLAG_WALL_RIGHT: int = 1 << 9
const FLAG_SWIM: int = 1 << 10
const FLAG_SLOWED: int = 1 << 11
const FLAG_FROZEN: int = 1 << 12
const STATE_SHIFT: int = 16
## Motion states as recorded (see _motion_state); the index sits in the flags above STATE_SHIFT.
const STATES: Array[StringName] = [&"run", &"jump", &"fall", &"wall", &"dash", &"swim", &"slide", &"slam"]

var clock: float = 0.0

var _times: PackedFloat64Array = PackedFloat64Array()
var _msec: PackedInt64Array = PackedInt64Array()
var _position: PackedVector2Array = PackedVector2Array()
var _velocity: PackedVector2Array = PackedVector2Array()
var _aim: PackedVector2Array = PackedVector2Array()
var _flags: PackedInt32Array = PackedInt32Array()
var _health: PackedInt32Array = PackedInt32Array()
var _clock_scale: PackedFloat32Array = PackedFloat32Array()
var _rounds: Array[PackedFloat32Array] = []
var _events: Array[Dictionary] = []
var _head: int = 0
var _count: int = 0
var _empty_rounds: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	_times.resize(CAPACITY)
	_msec.resize(CAPACITY)
	_position.resize(CAPACITY * FIGHTERS)
	_velocity.resize(CAPACITY * FIGHTERS)
	_aim.resize(CAPACITY * FIGHTERS)
	_flags.resize(CAPACITY * FIGHTERS)
	_health.resize(CAPACITY * FIGHTERS)
	_clock_scale.resize(CAPACITY * FIGHTERS)
	_rounds.resize(CAPACITY)
	_rounds.fill(_empty_rounds)


func reset() -> void:
	_head = 0
	_count = 0
	_events.clear()


func frame_count() -> int:
	return _count


func oldest_time() -> float:
	return _times[_physical(0)] if _count > 0 else clock


func newest_time() -> float:
	return _times[_physical(_count - 1)] if _count > 0 else clock


## One physics frame: the two fighters (index 0 = slot 1) and the rounds under projectiles_root.
func record(delta: float, fighters: Array[Player], projectiles_root: Node) -> void:
	clock += delta
	var index: int = _head
	_times[index] = clock
	_msec[index] = Time.get_ticks_msec()
	for fighter_index in range(FIGHTERS):
		var at: int = index * FIGHTERS + fighter_index
		var fighter: Player = fighters[fighter_index] if fighter_index < fighters.size() else null
		if fighter == null or not is_instance_valid(fighter):
			_flags[at] = FLAG_ELIMINATED
			continue
		_position[at] = fighter.global_position
		_velocity[at] = fighter.velocity
		# Where the gun points (a point along it), not the raw aim: the gun keeps its last direction when the
		# aim point sits on the body, and the replay must show what was on screen.
		var gun: Gun = fighter.get_gun()
		_aim[at] = fighter.global_position + gun.get_shot_direction() * AIM_REACH if gun != null else fighter.get_aim_world_position()
		_flags[at] = pose_flags(fighter)
		_health[at] = fighter.health_component.health if fighter.health_component != null else 0
		_clock_scale[at] = fighter.time_scale
	_rounds[index] = _capture_rounds(projectiles_root)
	_head = (_head + 1) % CAPACITY
	_count = mini(_count + 1, CAPACITY)
	_drop_old_events()


static func pose_flags(fighter: Player) -> int:
	var flags: int = 0
	if fighter.is_eliminated():
		flags |= FLAG_ELIMINATED
	if fighter.last_dir < 0.0:
		flags |= FLAG_FACING_LEFT
	if fighter.is_grounded():
		flags |= FLAG_GROUNDED
	if fighter.is_sliding():
		flags |= FLAG_SLIDE
	if fighter.is_slamming():
		flags |= FLAG_SLAM
	if fighter.is_dashing():
		flags |= FLAG_DASH
	if fighter.is_blocking():
		flags |= FLAG_BLOCK
	if fighter.is_wall_clinging():
		flags |= FLAG_CLING
	var wall_x: float = fighter.get_wall_contact_x()
	if wall_x > 0.0:
		flags |= FLAG_WALL_LEFT
	elif wall_x < 0.0:
		flags |= FLAG_WALL_RIGHT
	if fighter.is_swimming():
		flags |= FLAG_SWIM
	if fighter.is_time_frozen():
		flags |= FLAG_FROZEN
	elif fighter.is_time_slowed():
		flags |= FLAG_SLOWED
	flags |= _motion_state(flags, fighter.velocity.y) << STATE_SHIFT
	return flags


## What the body is doing (index into STATES), read off the flags just gathered so the owner and a remote
## copy record the same thing.
static func _motion_state(flags: int, velocity_y: float) -> int:
	if flags & FLAG_SLIDE:
		return 6
	if flags & FLAG_SLAM:
		return 7
	if flags & FLAG_DASH:
		return 4
	if flags & FLAG_SWIM:
		return 5
	if flags & FLAG_GROUNDED:
		return 0
	if flags & (FLAG_WALL_LEFT | FLAG_WALL_RIGHT):
		return 3
	return 1 if velocity_y < 0.0 else 2


static func state_of(flags: int) -> StringName:
	return STATES[clampi(flags >> STATE_SHIFT, 0, STATES.size() - 1)]


func _capture_rounds(projectiles_root: Node) -> PackedFloat32Array:
	if projectiles_root == null or projectiles_root.get_child_count() == 0:
		return _empty_rounds
	var rounds: PackedFloat32Array = PackedFloat32Array()
	for child in projectiles_root.get_children():
		var round_node: Projectile = child as Projectile
		if round_node == null or round_node.is_queued_for_deletion():
			continue
		rounds.append(float(round_node.replay_id))
		rounds.append(round_node.global_position.x)
		rounds.append(round_node.global_position.y)
		rounds.append(round_node.rotation)
		rounds.append(round_node.velocity.length())
		rounds.append(float(round_node.visual_style_index))
		rounds.append(round_node.projectile_scale)
	return rounds


func add_event(kind: StringName, world_position: Vector2, data: Dictionary) -> void:
	if _events.size() >= MAX_EVENTS:
		_events.pop_front()
	_events.append({"t": clock, "kind": kind, "position": world_position, "data": data})


func events_between(from_time: float, to_time: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _events:
		var t: float = float(event["t"])
		if t > from_time and t <= to_time:
			result.append(event)
	return result


func _drop_old_events() -> void:
	var cutoff: float = clock - SECONDS
	while not _events.is_empty() and float(_events[0]["t"]) < cutoff:
		_events.pop_front()


## One fighter at game time t, interpolated between the two frames around it: position, velocity, aim and
## clock are blended, flags and health come from the earlier frame.
func sample_fighter(fighter_index: int, t: float) -> Dictionary:
	var k: int = _frame_before(t)
	var a: int = _physical(k) * FIGHTERS + fighter_index
	var b: int = _physical(mini(k + 1, _count - 1)) * FIGHTERS + fighter_index
	var weight: float = _weight(k, t)
	return {
		"position": _position[a].lerp(_position[b], weight),
		"velocity": _velocity[a].lerp(_velocity[b], weight),
		"aim": _aim[a].lerp(_aim[b], weight),
		"flags": _flags[a],
		"health": _health[a],
		"scale": lerpf(_clock_scale[a], _clock_scale[b], weight),
	}


func flags_at(fighter_index: int, t: float) -> int:
	return _flags[_physical(_frame_before(t)) * FIGHTERS + fighter_index]


func position_at(fighter_index: int, t: float) -> Vector2:
	return sample_fighter(fighter_index, t)["position"]


## The rounds in flight at time t; a round present in both surrounding frames is blended between them so
## fast rounds glide instead of stepping in slow motion. Same layout as recorded (ROUND_STRIDE floats each).
func rounds_at(t: float) -> PackedFloat32Array:
	if _count == 0:
		return _empty_rounds
	var k: int = _frame_before(t)
	var before: PackedFloat32Array = _rounds[_physical(k)]
	if k + 1 >= _count or before.is_empty():
		return before
	var after: PackedFloat32Array = _rounds[_physical(k + 1)]
	var weight: float = _weight(k, t)
	var blended: PackedFloat32Array = before.duplicate()
	for i in range(0, before.size(), ROUND_STRIDE):
		for j in range(0, after.size(), ROUND_STRIDE):
			if after[j] != before[i]:
				continue
			blended[i + 1] = lerpf(before[i + 1], after[j + 1], weight)
			blended[i + 2] = lerpf(before[i + 2], after[j + 2], weight)
			blended[i + 3] = lerp_angle(before[i + 3], after[j + 3], weight)
			break
	return blended


## Earliest time in [from_time, to_time] at which a round with this id is in flight, or INF.
func first_seen(round_id: float, from_time: float, to_time: float) -> float:
	for k in range(_frame_before(from_time), _count):
		var t: float = _times[_physical(k)]
		if t > to_time:
			break
		var rounds: PackedFloat32Array = _rounds[_physical(k)]
		for i in range(0, rounds.size(), ROUND_STRIDE):
			if rounds[i] == round_id:
				return t
	return INF


## Latest position of a round with this id at or before t (Vector2.INF when it was never seen).
func round_position(round_id: float, t: float) -> Vector2:
	var k: int = _frame_before(t)
	while k >= 0:
		var rounds: PackedFloat32Array = _rounds[_physical(k)]
		for i in range(0, rounds.size(), ROUND_STRIDE):
			if rounds[i] == round_id:
				return Vector2(rounds[i + 1], rounds[i + 2])
		k -= 1
		if _times[_physical(maxi(k, 0))] < t - 0.5:
			break
	return Vector2.INF


## The moment the fighter went down: the first frame of the latest run of frames with it eliminated
## (INF if it is standing at the end of the record).
func elimination_time(fighter_index: int) -> float:
	if _count == 0:
		return INF
	var k: int = _count - 1
	if (_flags[_physical(k) * FIGHTERS + fighter_index] & FLAG_ELIMINATED) == 0:
		return INF
	while k > 0 and (_flags[_physical(k - 1) * FIGHTERS + fighter_index] & FLAG_ELIMINATED) != 0:
		k -= 1
	return _times[_physical(k)]


## The round that most likely landed the kill: of the rounds near the victim in the last frames before
## time t, the closest one. Returns its replay id, or -1.
func killing_round(victim_index: int, t: float, reach: float = 48.0) -> float:
	var best_id: float = -1.0
	var best_distance: float = reach
	var k: int = _frame_before(t)
	var stop: int = maxi(k - 6, 0)
	while k >= stop:
		var victim_at: Vector2 = _position[_physical(k) * FIGHTERS + victim_index]
		var rounds: PackedFloat32Array = _rounds[_physical(k)]
		for i in range(0, rounds.size(), ROUND_STRIDE):
			var distance: float = victim_at.distance_to(Vector2(rounds[i + 1], rounds[i + 2]))
			if distance < best_distance:
				best_distance = distance
				best_id = rounds[i]
		if best_id >= 0.0:
			break
		k -= 1
	return best_id


## The engine's clock (msec) when the frame at game time t was recorded.
func msec_at(t: float) -> int:
	return _msec[_physical(_frame_before(t))] if _count > 0 else Time.get_ticks_msec()


## Health of a fighter at time t (the earlier frame).
func health_at(fighter_index: int, t: float) -> int:
	return _health[_physical(_frame_before(t)) * FIGHTERS + fighter_index]


func _physical(logical: int) -> int:
	return (_head - _count + logical + CAPACITY * 2) % CAPACITY


## Logical index of the last frame at or before t (0 when t is before the record).
func _frame_before(t: float) -> int:
	if _count == 0:
		return 0
	var low: int = 0
	var high: int = _count - 1
	if t >= _times[_physical(high)]:
		return high
	if t <= _times[_physical(0)]:
		return 0
	while high - low > 1:
		var middle: int = (low + high) >> 1
		if _times[_physical(middle)] <= t:
			low = middle
		else:
			high = middle
	return low


func _weight(k: int, t: float) -> float:
	if k + 1 >= _count:
		return 0.0
	var t0: float = _times[_physical(k)]
	var t1: float = _times[_physical(k + 1)]
	return clampf((t - t0) / maxf(t1 - t0, 0.00001), 0.0, 1.0)
