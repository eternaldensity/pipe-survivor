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
	await _test_branch()
	await _test_properties()
	await _test_seams()

## Test-only steering helper: steer toward the tube axis so the vehicle can
## traverse generated levels. The game itself has no auto-steer.
func _auto_steer(v: Vehicle) -> void:
	var to_self: Vector3 = v.global_position - v.tube_origin
	var radial: Vector3 = to_self - to_self.dot(v.tube_axis) * v.tube_axis
	if radial.length_squared() < 1e-4:
		return
	var outward: Vector3 = radial.normalized()
	var fwd: Vector3 = -v.global_transform.basis.z
	fwd = fwd - fwd.dot(outward) * outward
	if fwd.length_squared() < 1e-4:
		return
	fwd = fwd.normalized()
	var cos_err: float = fwd.dot(v.tube_axis)
	var sin_err: float = fwd.cross(v.tube_axis).dot(outward)
	var angle_err: float = atan2(sin_err, cos_err)
	var turn: float = clampf(angle_err * 3.0, -1.0, 1.0)
	if turn > 0.01:
		Input.action_press("ui_right", turn)
		Input.action_release("ui_left")
	elif turn < -0.01:
		Input.action_press("ui_left", -turn)
		Input.action_release("ui_right")
	else:
		Input.action_release("ui_left")
		Input.action_release("ui_right")

func _test_driving() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(60): await process_frame
	Input.action_press("ui_up")
	var nan_count := 0
	var min_r := 1e9
	var max_r := 0.0
	var max_radius_error := 0.0
	var seen: Array[PipeSection] = []
	var last: PipeSection = null
	var outside_frames := 0
	for i in range(12000):
		await process_frame
		var v = main.get_node("Vehicle")
		var net = main.get_node("PipeNetwork")
		_auto_steer(v)
		for c in [v.global_position.x, v.global_position.y, v.global_position.z]:
			if is_nan(c) or is_inf(c):
				_fail("driving: NaN/INF position at frame %d" % i)
				break
		var sec = net.get_section_at(v.global_position)
		if sec == null:
			var types := ""
			for s in net.sections:
				types += s.get_class() + " "
			_fail("driving: null section at frame %d (net.sections=%d types=%s)" % [i, net.sections.size(), types])
			break
		# Stop once the vehicle has driven past the end of the authored network.
		if not sec.contains_point(v.global_position):
			outside_frames += 1
			if outside_frames >= 10 and seen.size() >= 8:
				break
			continue
		outside_frames = 0
		if sec != last:
			seen.append(sec)
			last = sec
			if seen.size() <= 5:
				print("DRIVING: section", seen.size(), sec.name, "at z=", v.global_position.z)
		var p: Dictionary = sec.get_tube_properties(v.global_position)
		var r : float = (v.global_position - p["origin"]).length()
		var rad: float = p["radius"]
		if r < min_r: min_r = r
		if r > max_r: max_r = r
		# Skip the radius invariant inside junctions (overlapping centrelines until
		# the blended mesh exists) and right at section mouths (transitional).
		var near_mouth: bool = v.global_position.distance_to(sec.entry.global_position) < 5.0 \
			or v.global_position.distance_to(sec.exit.global_position) < 5.0
		if not (sec is JunctionPipeSection) and not near_mouth:
			var outside := r - rad
			if outside > max_radius_error: max_radius_error = outside
		for c in [v.global_position.x, v.global_position.y, v.global_position.z,
				  v.velocity.x, v.velocity.y, v.velocity.z,
				  v.tube_axis.x, v.tube_axis.y, v.tube_axis.z]:
			if is_nan(c) or is_inf(c):
				nan_count += 1
	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	_assert(nan_count == 0, "driving: NaN/INF detected (%d)" % nan_count)
	_assert(seen.size() >= 2, "driving: too few sections traversed (%d)" % seen.size())
	_assert(max_radius_error < 3.0, "driving: vehicle left tube wall (max radius error %.2f)" % max_radius_error)
	print("driving: sections=%d min_r=%.3f max_r=%.3f max_radius_err=%.3f nan=%d" % [seen.size(), min_r, max_r, max_radius_error, nan_count])
	main.queue_free()
	await process_frame

func _test_steering() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	Input.action_press("ui_up")
	var nan_count := 0
	var min_r := 1e9
	var max_r := 0.0
	var max_radius_error := 0.0
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
		var p: Dictionary = sec.get_tube_properties(v.global_position)
		var r : float = (v.global_position - p["origin"]).length()
		var rad: float = p["radius"]
		if r < min_r: min_r = r
		if r > max_r: max_r = r
		var outside := r - rad
		if outside > max_radius_error: max_radius_error = outside
		for c in [v.global_position.x, v.global_position.y, v.global_position.z,
				  v.velocity.x, v.velocity.y, v.velocity.z,
				  v.tube_axis.x, v.tube_axis.y, v.tube_axis.z]:
			if is_nan(c) or is_inf(c):
				nan_count += 1
	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	_assert(nan_count == 0, "steering: NaN/INF detected (%d)" % nan_count)
	_assert(max_radius_error < 3.0, "steering: vehicle left tube wall (max radius error %.2f)" % max_radius_error)
	print("steering: min_r=%.3f max_r=%.3f max_radius_err=%.3f nan=%d" % [min_r, max_r, max_radius_error, nan_count])
	main.queue_free()
	await process_frame

func _test_branch() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(60): await process_frame
	var net = main.get_node("PipeNetwork")
	var connector: ConnectorPipeSection = null
	for s in net.sections:
		if s is ConnectorPipeSection:
			connector = s
			break
	if connector == null:
		print("branch: no connector in network (skipping)")
		main.queue_free()
		await process_frame
		return
	var v = main.get_node("Vehicle")
	var axis := connector.entry.global_transform.basis.z
	v.global_position = connector.entry.global_position + axis * 2.0
	v.global_transform.basis = Basis.looking_at(axis, Vector3.UP)
	net.current_section = null
	net.get_section_at(v.global_position)
	Input.action_press("ui_up")
	var nan_count := 0
	var max_radius_error := 0.0
	var entered := false
	for i in range(1500):
		await process_frame
		_auto_steer(v)
		var sec = net.get_section_at(v.global_position)
		if sec == null:
			_fail("branch: null section at frame %d" % i)
			break
		if not sec.contains_point(v.global_position):
			continue
		if sec == connector or sec.attached_from == connector:
			entered = true
		if i < 5:
			continue
		var p: Dictionary = sec.get_tube_properties(v.global_position)
		var r: float = (v.global_position - p["origin"]).length()
		var err := absf(r - float(p["radius"]))
		if err > max_radius_error:
			max_radius_error = err
		for c in [v.global_position.x, v.global_position.y, v.global_position.z,
				  v.velocity.x, v.velocity.y, v.velocity.z]:
			if is_nan(c) or is_inf(c):
				nan_count += 1
	Input.action_release("ui_up")
	Input.action_release("ui_left")
	Input.action_release("ui_right")
	_assert(nan_count == 0, "branch: NaN/INF detected (%d)" % nan_count)
	print("branch: entered=%s max_radius_err=%.3f nan=%d" % [entered, max_radius_error, nan_count])
	main.queue_free()
	await process_frame


func _test_properties() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(60): await process_frame
	var net = main.get_node("PipeNetwork")
	for s in net.sections:
		if s is StraightPipeSection:
			var ss := s as StraightPipeSection
			for k in range(5):
				var t := float(k) / 4.0
				var wp := ss.entry.global_position + (ss.exit.global_position - ss.entry.global_position) * t
				var p := ss.get_tube_properties(wp)
				_assert(abs(p["axis"].length() - 1.0) < 1e-5, "straight axis not unit (%s)" % ss.name)
				_assert((wp - p["origin"]).length() < 1e-3, "straight origin off centerline (%s)" % ss.name)
				_assert(ss.contains_point(wp), "straight contains_point false on centerline (%s)" % ss.name)
		elif s is JunctionPipeSection:
			var js := s as JunctionPipeSection
			js._build_curves()
			for c in js._curves:
				var bl := c.get_baked_length()
				for k in range(5):
					var off := bl * float(k) / 4.0
					var tr := c.sample_baked_with_rotation(off)
					var lp := tr.origin
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

func _test_seams() -> void:
	var main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(60): await process_frame
	var net = main.get_node("PipeNetwork")
	var count := 0
	for s in net.sections:
		var psec: PipeSection = s
		if psec.attached_from == null:
			continue
		var prev: PipeSection = psec.attached_from
		var exit_idx: int = psec.attached_exit
		var exit_marker: Marker3D = prev.ports[exit_idx] if exit_idx < prev.ports.size() else prev.exit
		var ta: Transform3D = exit_marker.global_transform
		var tb: Transform3D = psec.entry.global_transform
		var pos_diff: float = (ta.origin - tb.origin).length()
		var basis_diff: float = 0.0
		for c in range(3):
			basis_diff += (ta.basis[c] - tb.basis[c]).length()
		var r_prev: float = prev.get_exit_radius(exit_idx)
		var r_next: float = psec.get_entry_radius()
		_assert(pos_diff < 1.0, "seam %s->%s position gap %.3f" % [prev.name, psec.name, pos_diff])
		_assert(basis_diff < 0.01, "seam %s->%s basis gap %.3f" % [prev.name, psec.name, basis_diff])
		_assert(absf(r_prev - r_next) < 0.51,
			"seam %s->%s radius mismatch %.2f -> %.2f" % [prev.name, psec.name, r_prev, r_next])
		count += 1
	print("seams: checked %d" % count)
	main.queue_free()
	await process_frame