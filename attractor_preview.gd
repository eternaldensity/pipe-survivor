# attractor_preview.gd  (Phase 4 — first pass)
class_name AttractorPreview
extends MeshInstance3D

var attractor: Attractor = Attractor.new()
var _mesh: ImmediateMesh = ImmediateMesh.new()

func _ready() -> void:
	mesh = _mesh
	material_override = _make_material()

func _make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.5, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func update_preview() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var pts := attractor.generate_points(Vector3(0.1, 0.1, 0.1), 500, 0.01)
	for p in pts:
		_mesh.surface_add_vertex(p * 0.5)
	_mesh.surface_end()