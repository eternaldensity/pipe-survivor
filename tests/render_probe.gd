extends SceneTree
## Renders screenshots from inside the first straight, bend, junction, rest
## zone and boss arena of the generated level, plus a couple of junction seams
## and a sealed dead end.
## Run: xvfb-run -a godot --path . --script tests/render_probe.gd

var cam: Camera3D

func _init() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(40):
		await process_frame
	var vehicle = main.get_node("Vehicle")
	vehicle.set_physics_process(false)
	var net = main.get_node("PipeNetwork")

	cam = Camera3D.new()
	cam.fov = 80.0
	cam.near = 0.05
	main.add_child(cam)
	cam.current = true

	var done := {}
	for s in net.sections:
		var sec: PipeSection = s
		var key := ""
		if sec is BossArena:
			key = "BossArena"
		elif sec is RestZone:
			key = "RestZone"
		elif sec is JunctionPipeSection:
			key = "JunctionPipeSection"
		elif sec is BendPipeSection:
			key = "BendPipeSection"
		elif sec is StraightPipeSection:
			key = "StraightPipeSection"
		if key == "" or done.has(key):
			continue
		done[key] = true
		await _shoot(sec, key)

	# Junction-to-child seams: stand just before the child entry and look along
	# its axis, so any gap/misalignment is plainly visible.
	var seams := 0
	for s in net.sections:
		var sec: PipeSection = s
		if not (sec.attached_from is JunctionPipeSection):
			continue
		var axis := sec.entry.global_transform.basis.z.normalized()
		await _shoot_at(sec.entry.global_position - axis * 7.0,
			sec.entry.global_position + axis * 8.0, "Seam%d" % seams)
		seams += 1
		if seams >= 2:
			break

	# First sealed dead end.
	for s in net.sections:
		var cap := s.get_node_or_null("EndCap") as MeshInstance3D
		if cap == null:
			continue
		if s is StraightPipeSection and s.name == "StraightPipeSection":
			continue  # skip the start cap; the dead ends are more interesting
		var axis := cap.global_transform.basis.z.normalized()
		await _shoot_at(cap.global_position - axis * 8.0,
			cap.global_position, "DeadEnd")
		break
	quit(0)

func _shoot(sec: PipeSection, key: String) -> void:
	var a := sec.entry.global_position
	var b := sec.exit.global_position
	var mid := a.lerp(b, 0.4)
	var props := sec.get_tube_properties(mid)
	var axis: Vector3 = props["axis"].normalized()
	await _shoot_at(mid - axis * 2.0, mid - axis * 2.0 + axis * 10.0, key)

func _shoot_at(pos: Vector3, target: Vector3, key: String) -> void:
	cam.global_position = pos
	var up := Vector3.UP
	if absf((target - pos).normalized().dot(up)) > 0.98:
		up = Vector3.RIGHT
	cam.look_at(target, up)
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := "/tmp/opencode/view_%s.png" % key
	img.save_png(out)
	print("SAVED ", out)
