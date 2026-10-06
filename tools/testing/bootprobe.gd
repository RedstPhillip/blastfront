extends SceneTree

# Where does boot time go? Prints engine+autoload time, then the cost of loading the heavy resources one
# by one (each load is cached afterwards, so the order shows incremental cost).

func _initialize() -> void:
	print("BOOT autoloads_done_ms %d" % Time.get_ticks_msec())
	var paths: Array = [
		"res://assets/fonts/russo_one/RussoOne-Regular.ttf",
		"res://ui/theme/blastfront_theme.tres",
		"res://scenes/menus/main_menu.tscn",
		"res://scenes/game.tscn",
		"res://scenes/menus/online_locker_room.tscn",
		"res://scenes/menus/intermission_menu.tscn",
		"res://scenes/app/main.tscn",
	]
	for path in paths:
		var t0: int = Time.get_ticks_usec()
		var res: Resource = load(path)
		print("BOOT load %-60s %8.1f ms" % [path, (Time.get_ticks_usec() - t0) / 1000.0])
	var t1: int = Time.get_ticks_usec()
	var main: Node = (load("res://scenes/app/main.tscn") as PackedScene).instantiate()
	print("BOOT instantiate main %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	t1 = Time.get_ticks_usec()
	root.add_child(main)
	print("BOOT add main (ready + menu) %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	print("BOOT total_ms %d" % Time.get_ticks_msec())
	quit()
