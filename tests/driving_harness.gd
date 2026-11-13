extends SceneTree
## Headless driving + geometry regression harness.
## Run via: tests/run.sh  (or godot --headless --path . --script tests/driving_harness.gd)
## Exit code 0 = all checks passed, 1 = one or more failures.

var failures: Array[String] = []
var check_count := 0

func _fail(msg: String) -> void:
	failures.append(msg)
	print("FAIL: ", msg)

func _assert(cond: bool, msg: String) -> void:
	check_count += 1
	if not cond:
		_fail(msg)

func _init() -> void:
	await _run_all()
	if failures.is_empty():
		print("RESULT: PASS (%d checks)" % check_count)
		quit(0)
	else:
		print("RESULT: FAIL (%d failures)" % failures.size())
		for f in failures:
			print("  - ", f)
		quit(1)

func _run_all() -> void:
	await _test_driving()
	await _test_steering()
	await _test_properties()

func _test_driving() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Input.action_press("ui_up")
	var nan_count := 0
	var min_r := 1e9
	var max_r := 0.0
	var seen: Array[String] = []
	var last := ""
	for i in range(6000):
		await process_frame
		var v = main.get_node("Vehicle")
		var net = main.get_node("PipeNetwork")
		var sec = net.get_section_at(v.global_position)
		if sec == null:
			_fail("driving: null section at frame %d" % i)
			break
		if sec.name != last:
			seen.append(sec.name)
			last = sec.name
		var r : float = (v.global_position - v.tube_origin).length()
		if r < min_r: min_r = r
		if r > max_r: max_r = r
		for c in [v.global_position.x, v.global_position.y, v.global_position.z,
				  v.velocity.x, v.velocity.y, v.velocity.z,
				  v.tube_axis.x, v.tube_axis.y, v.tube_axis.z]:
			if is_nan(c) or is_inf(c):
				nan_count += 1
	Input.action_release("ui_up")
	_assert(nan_count == 0, "driving: NaN/INF detected (%d)" % nan_count)
	_assert(seen.size() >= 4, "driving: too few sections traversed (%d)" % seen.size())
	_assert(min_r > 5.0 and max_r < 15.0, "driving: radius out of range [%.2f, %.2f]" % [min_r, max_r])
	print("driving: sections=%d min_r=%.3f max_r=%.3f nan=%d" % [seen.size(), min_r, max_r, nan_count])
	main.queue_free()
	await process_frame

func _test_steering() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Input.action_press("ui_up")
	var nan_count := 0
	var min_r := 1e9
	var max_r := 0.0
	for i in range(2000):
		await process_frame
		var v = main.get_node("Vehicle")
		if i % 120 < 60:
			Input.action_press("ui_left")
			Input.action_release("ui_right")
		else:
			Input.action_press("ui_right")
			Input.action_release("ui_left")
		var net = main.get_node("PipeNetwork")
		var sec = net.get_section_at(v.global_position)
		if sec == null:
			_fail("steering: null section at frame %d" % i)
			break
		var r : float = (v.global_position - v.tube_origin).length()
		if r < min_r: min_r = r
		if r > max_r: max_r = r
		for c in [v.global_position.x, v.global_position.y, v.global_position.z,
				  v.velocity.x, v.velocity.y, v.velocity.z,
				  v.tube_axis.x, v.tube_axis.y, v.tube_axis.z]:
			if is_nan(c) or is_inf(c):
				nan_count += 1
	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	_assert(nan_count == 0, "steering: NaN/INF detected (%d)" % nan_count)
	_assert(min_r > 5.0 and max_r < 15.0, "steering: radius out of range [%.2f, %.2f]" % [min_r, max_r])
	print("steering: min_r=%.3f max_r=%.3f nan=%d" % [min_r, max_r, nan_count])
	main.queue_free()
	await process_frame

func _test_properties() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var net = main.get_node("PipeNetwork")
	for s in net.sections:
		if s is StraightPipeSection:
			var ss := s as StraightPipeSection
			var fwd := ss.global_transform.basis.z
			for k in range(5):
				var t := float(k) / 4.0
				var wp := ss.entry.global_position + (ss.exit.global_position - ss.entry.global_position) * t
				var p := ss.get_tube_properties(wp)
				_assert(abs(p["axis"].length() - 1.0) < 1e-5, "straight axis not unit (%s)" % ss.name)
				_assert((wp - p["origin"]).length() < 1e-3, "straight origin off centerline (%s)" % ss.name)
				_assert(ss.contains_point(wp), "straight contains_point false on centerline (%s)" % ss.name)
		elif s is JunctionPipeSection:
			var js := s as JunctionPipeSection
			js._build_paths()
			for path in js._paths:
				var spt: Vector3 = path[0]
				var ept: Vector3 = path[1]
				for k in range(5):
					var t := float(k) / 4.0
					var lp := spt.lerp(ept, t)
					var wp := js.to_global(lp)
					var p := js.get_tube_properties(wp)
					_assert(abs(p["axis"].length() - 1.0) < 1e-4, "junction axis not unit (%s)" % js.name)
					_assert((wp - p["origin"]).length() < 1e-2, "junction origin off centreline (%s)" % js.name)
					_assert(js.contains_point(wp), "junction contains_point false on centreline (%s)" % js.name)
		elif s is BendPipeSection:
			var bs := s as BendPipeSection
			var r := bs._bend_radius
			var ang := bs._angle_rad
			var roll := deg_to_rad(bs.roll_angle)
			var roll_basis := Basis(Vector3(0, 0, 1), roll)
			for k in range(11):
				var a := float(k) / 10.0 * ang
				var lp := roll_basis * Vector3(r * (1.0 - cos(a)), 0.0, r * sin(a))
				var wp := bs.to_global(lp)
				var p := bs.get_tube_properties(wp)
				_assert(abs(p["axis"].length() - 1.0) < 1e-5, "bend axis not unit (%s)" % bs.name)
				_assert((wp - p["origin"]).length() < 1e-2, "bend origin off centerline (%s)" % bs.name)
				_assert(bs.contains_point(wp), "bend contains_point false on centerline (%s)" % bs.name)
	print("properties: checked %d sections" % net.sections.size())
	main.queue_free()
	await process_frame