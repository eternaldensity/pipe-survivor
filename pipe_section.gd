@tool
# pipe_section.gd
class_name PipeSection
extends Node3D

@onready var entry : Marker3D = $Entry
@onready var exit  : Marker3D = $Exit

# Exit markers. Single-exit sections populate this with [exit] in _ready;
# junctions populate it with all of their exit markers.
var ports : Array[Marker3D] = []

# Set by LevelGenerator: position along the main path (0..1), monotonic.
var main_progress: float = 0.0

# Set by PipeNetwork.add_section when this section is snapped onto a prior exit.
var attached_from : PipeSection = null
var attached_exit : int = -1

const RING_SEGMENTS := 32

func get_entry_radius() -> float:
	return 0.0

func get_exit_radius(_exit_index: int = 0) -> float:
	return 0.0

func get_tube_properties(world_pos: Vector3) -> Dictionary:
	push_error("get_tube_properties not implemented in " + name)
	return {}

func sample_centreline_points() -> Array[Vector3]:
	return []

func contains_point(world_pos: Vector3) -> bool:
	push_error("contains_point not implemented in " + name)
	return false

func build_trimesh_collision_async(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null:
		return
	if mi.get_child_count() == 0:
		mi.create_trimesh_collision()
	await get_tree().process_frame
	if mi.get_child_count() == 0:
		return
	var body := mi.get_child(0) as StaticBody3D
	if body == null or body.get_child_count() == 0:
		return
	var shape := body.get_child(0) as CollisionShape3D
	if shape and shape.shape is ConcavePolygonShape3D:
		(shape.shape as ConcavePolygonShape3D).backface_collision = true

## Extract welded boundary edges from a mesh (edges shared by exactly one triangle).
static func welded_boundary_edges(mi: MeshInstance3D) -> Array:
	var edges: Array = []
	if mi == null or mi.mesh == null:
		return edges
	var xf := mi.global_transform
	for surf in range(mi.mesh.get_surface_count()):
		var arr := mi.mesh.surface_get_arrays(surf)
		if arr == null:
			continue
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var raw = arr[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = raw if raw != null else PackedInt32Array()
		if verts.is_empty():
			continue
		var weld := {}
		var positions: Array[Vector3] = []
		var remap := PackedInt32Array()
		remap.resize(verts.size())
		for vi in range(verts.size()):
			var p: Vector3 = verts[vi]
			var key := "%d:%d:%d" % [roundi(p.x * 100.0), roundi(p.y * 100.0), roundi(p.z * 100.0)]
			if weld.has(key):
				remap[vi] = weld[key]
			else:
				remap[vi] = positions.size()
				weld[key] = positions.size()
				positions.append(p)
		var tri_count := idx.size() / 3 if idx.size() > 0 else verts.size() / 3
		var counts := {}
		for t in range(tri_count):
			var i0: int; var i1: int; var i2: int
			if idx.size() > 0:
				i0 = remap[idx[t * 3]]; i1 = remap[idx[t * 3 + 1]]; i2 = remap[idx[t * 3 + 2]]
			else:
				i0 = remap[t * 3]; i1 = remap[t * 3 + 1]; i2 = remap[t * 3 + 2]
			for pair in [[i0, i1], [i1, i2], [i2, i0]]:
				var lo: int = mini(pair[0], pair[1])
				var hi: int = maxi(pair[0], pair[1])
				var ekey := "%d:%d" % [lo, hi]
				if counts.has(ekey):
					counts[ekey] += 1
				else:
					counts[ekey] = 1
		for t in range(tri_count):
			var i0: int; var i1: int; var i2: int
			if idx.size() > 0:
				i0 = remap[idx[t * 3]]; i1 = remap[idx[t * 3 + 1]]; i2 = remap[idx[t * 3 + 2]]
			else:
				i0 = remap[t * 3]; i1 = remap[t * 3 + 1]; i2 = remap[t * 3 + 2]
			for pair in [[i0, i1], [i1, i2], [i2, i0]]:
				var lo: int = mini(pair[0], pair[1])
				var hi: int = maxi(pair[0], pair[1])
				var ekey := "%d:%d" % [lo, hi]
				if counts[ekey] != 1:
					continue
				var a: Vector3 = positions[lo]
				var b: Vector3 = positions[hi]
				edges.append([xf * a, xf * b])
	return edges
