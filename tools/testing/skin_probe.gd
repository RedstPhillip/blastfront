extends SceneTree

## Builds every world's arena and prints one checksum per arena over the generated dressing (the points and
## colours of every Line2D, Polygon2D and detail mesh). Run it on two copies to prove a refactor of the
## platform skins changed nothing:  run_probe.sh skin_probe.gd headless  (also with PROJ_OVERRIDE=<copy>).

const ARENAS: Array[String] = [
	"res://scenes/maps/arena.tscn",
	"res://scenes/maps/mars/mars_arena.tscn",
	"res://scenes/maps/tidewater/tidewater_arena.tscn",
	"res://scenes/maps/rimefall/rimefall_arena.tscn",
]

var _frame: int = 0
var _arenas: Array[Node] = []


func _initialize() -> void:
	for path in ARENAS:
		if not ResourceLoader.exists(path):
			print("SKIN %s missing" % path)
			_arenas.append(null)
			continue
		var arena: Node = (load(path) as PackedScene).instantiate()
		root.add_child(arena)
		_arenas.append(arena)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 5:
		return false
	for index in range(ARENAS.size()):
		var arena: Node = _arenas[index]
		if arena == null:
			continue
		var digest: HashingContext = HashingContext.new()
		digest.start(HashingContext.HASH_MD5)
		var counts: Dictionary = {"lines": 0, "polygons": 0, "meshes": 0, "vertices": 0}
		for node in arena.find_children("*", "", true, false):
			if node is Line2D:
				counts["lines"] += 1
				digest.update(var_to_bytes([(node as Line2D).points, (node as Line2D).default_color, (node as Line2D).width]))
			elif node is Polygon2D:
				counts["polygons"] += 1
				digest.update(var_to_bytes([(node as Polygon2D).polygon, (node as Polygon2D).color, (node as Polygon2D).vertex_colors]))
			elif node is MeshInstance2D and (node as MeshInstance2D).mesh is ArrayMesh:
				var mesh: ArrayMesh = (node as MeshInstance2D).mesh
				counts["meshes"] += 1
				for surface in range(mesh.get_surface_count()):
					var arrays: Array = mesh.surface_get_arrays(surface)
					counts["vertices"] += (arrays[Mesh.ARRAY_VERTEX] as PackedVector2Array).size()
					digest.update(var_to_bytes([arrays[Mesh.ARRAY_VERTEX], arrays[Mesh.ARRAY_COLOR], node.name, (node as MeshInstance2D).material != null]))
		print("SKIN %s %s %s" % [ARENAS[index].get_file(), digest.finish().hex_encode(), counts])
	return true
