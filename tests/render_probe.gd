extends SceneTree
## Renders screenshots from inside the first straight, bend, junction, rest
## zone, and boss arena of the generated level.
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
	quit(0)

func _shoot(sec: PipeSection, key: String) -> void:
	var a := sec.entry.global_position
	var b := sec.exit.global_position
	var mid := a.lerp(b, 0.4)
	var props := sec.get_tube_properties(mid)
	var axis: Vector3 = props["axis"].normalized()
	var origin: Vector3 = mid - axis * 2.0
	cam.global_position = origin
	cam.look_at(origin + axis, Vector3.UP)
	for i in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var out := "/tmp/opencode/view_%s.png" % key
	img.save_png(out)
	print("SAVED ", out, " from ", origin, " axis ", axis)
