extends SceneTree
## Headless topology generation harness for the v2 MacroGraph.
## Run: godot --headless --path . --script tests/generation_harness.gd

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
	var config := {
		"main_anchors": 12,
		"anchor_spacing_min": 60.0,
		"anchor_spacing_max": 130.0,
		"clearance_radius": 40.0,
		"min_loops": 2,
		"max_loops": 4,
		"side_paths": 4,
		"side_paths_min": 3,
		"side_paths_max": 6,
		"max_loop_span": 8,
		"min_main_nodes": 8,
		"max_main_nodes": 18,
		"max_radius": 16.0,
		"min_radius": 6.0,
	}

	var rng := RandomNumberGenerator.new()
	var worst_time := 0.0
	var worst_seed := 0
	var hash0 := ""
	for seed in range(100):
		rng.seed = seed
		var t0 := Time.get_ticks_msec()
		var g: MacroGraph = MacroGraph.generate(config, rng)
		var dt := Time.get_ticks_msec() - t0
		if dt > worst_time:
			worst_time = dt
			worst_seed = seed
		var v := g.validate(config)
		_assert(bool(v["ok"]), "seed %d validation failed: %s" % [seed, str(v["errors"])])
		# extra invariants
		_assert(g.is_graph_connected(), "seed %d not connected" % seed)
		_assert(g.boss_reachable(), "seed %d boss unreachable" % seed)
		_assert(g.loop_count() >= 2 and g.loop_count() <= 4, "seed %d loop count %d" % [seed, g.loop_count()])
		_assert(g.side_path_count() >= 3 and g.side_path_count() <= 6, "seed %d side paths %d" % [seed, g.side_path_count()])
		# determinism check on first seed
		if seed == 0:
			hash0 = g.hash_summary()

	# Determinism: regenerate seed 0 and compare hash.
	rng.seed = 0
	var g2: MacroGraph = MacroGraph.generate(config, rng)
	_assert(g2.hash_summary() == hash0, "determinism: seed 0 hash mismatch")

	print("generation: 100 seeds, worst time %.1f ms (seed %d), loops %d-%d, side paths %d-%d"
		% [worst_time, worst_seed,
			2, 4, 3, 6])
	_assert(worst_time < 1000.0, "generation too slow: %.1f ms (seed %d)" % [worst_time, worst_seed])
	print("determinism: OK")