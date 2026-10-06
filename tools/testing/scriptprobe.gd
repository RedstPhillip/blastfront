extends SceneTree

# Loads scripts in the given order (default: a fixed list of suspects first) and prints each load's cost.

func _initialize() -> void:
	var order: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("order="):
			order = Array(arg.substr(6).split(","))
	if order.is_empty():
		order = _all_scripts("res://")
	var costs: Array = []
	for path in order:
		var t0: int = Time.get_ticks_usec()
		load(path)
		costs.append([(Time.get_ticks_usec() - t0) / 1000.0, path])
	costs.sort_custom(func(a, b): return a[0] > b[0])
	for entry in costs.slice(0, 25):
		print("SCR %8.1f ms  %s" % [entry[0], entry[1]])
	quit()


func _all_scripts(dir: String) -> Array:
	var result: Array = []
	var da: DirAccess = DirAccess.open(dir)
	if da == null:
		return result
	for sub in da.get_directories():
		if sub.begins_with(".") or sub == "addons" or sub == "tools":
			continue
		result.append_array(_all_scripts(dir.path_join(sub)))
	for file in da.get_files():
		if file.ends_with(".gd"):
			result.append(dir.path_join(file))
	return result
