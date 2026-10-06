extends SceneTree

# Loads every dependency of a scene bottom-up and prints the slowest ones (each path's own cost, since
# its dependencies are already cached when it loads).

var _seen: Dictionary = {}
var _order: Array = []


func _initialize() -> void:
	var target: String = "res://scenes/game.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("target="):
			target = arg.substr(7)
	_walk(target)
	var costs: Array = []
	var total: float = 0.0
	for path in _order:
		var t0: int = Time.get_ticks_usec()
		load(path)
		var ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		costs.append([ms, path])
	costs.sort_custom(func(a, b): return a[0] > b[0])
	print("DEP total %.1f ms over %d resources" % [total, _order.size()])
	for entry in costs.slice(0, 40):
		print("DEP %8.1f ms  %s" % [entry[0], entry[1]])
	quit()


func _walk(path: String) -> void:
	if _seen.has(path):
		return
	_seen[path] = true
	for dep in ResourceLoader.get_dependencies(path):
		var dep_path: String = dep.get_slice("::", 2) if dep.contains("::") else dep
		if dep_path.begins_with("uid://"):
			dep_path = ResourceUID.get_id_path(ResourceUID.text_to_id(dep_path))
		if dep_path != "" and ResourceLoader.exists(dep_path):
			_walk(dep_path)
	_order.append(path)
