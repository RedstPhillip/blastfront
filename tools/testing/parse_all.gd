extends SceneTree

## Compiles every script under res:// (except addons) once and prints "PARSE OK <count>" at the end. The
## regression scenarios only load what they reach; this catches parse and type errors everywhere else.
## Run: run_probe.sh parse_all.gd headless  (any "SCRIPT ERROR" or "Failed to load script" line is a fail).

var _count: int = 0
var _failed: PackedStringArray = PackedStringArray()


func _initialize() -> void:
	_scan("res://")
	if _failed.is_empty():
		print("PARSE OK %d" % _count)
	else:
		print("PARSE FAILED %d of %d: %s" % [_failed.size(), _count, ", ".join(_failed)])
	quit()


func _scan(dir_path: String) -> void:
	for sub in DirAccess.get_directories_at(dir_path):
		if sub.begins_with(".") or sub == "addons" or sub == "tools":
			continue
		_scan(dir_path.path_join(sub))
	for file in DirAccess.get_files_at(dir_path):
		if not file.ends_with(".gd"):
			continue
		var path: String = dir_path.path_join(file)
		_count += 1
		var script: Script = load(path) as Script
		if script == null or not script.can_instantiate():
			_failed.append(path)
