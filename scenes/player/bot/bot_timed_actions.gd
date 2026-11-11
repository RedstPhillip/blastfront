class_name BotTimedActions
extends RefCounted

## Reactions a bot has decided on but times for later: a block just before the round lands, a slide under it,
## a dash out of its way. At most one of each kind waits at a time; tick() hands back the ones that are due,
## and the brain carries them out (checking they still make sense then).

var _pending: Dictionary = {}


func schedule(kind: StringName, delay: float, data: Variant = null) -> void:
	_pending[kind] = {"time": delay, "data": data}


func is_pending(kind: StringName) -> bool:
	return _pending.has(kind)


func data_of(kind: StringName) -> Variant:
	return (_pending[kind] as Dictionary)["data"] if _pending.has(kind) else null


func cancel(kind: StringName) -> void:
	_pending.erase(kind)


## Counts every waiting action down; the due ones leave the list and come back as {"kind", "data"}.
func tick(delta: float) -> Array[Dictionary]:
	var due: Array[Dictionary] = []
	for kind in _pending.keys():
		var entry: Dictionary = _pending[kind]
		entry["time"] = float(entry["time"]) - delta
		if float(entry["time"]) <= 0.0:
			due.append({"kind": kind, "data": entry["data"]})
	for action in due:
		_pending.erase(action["kind"])
	return due
