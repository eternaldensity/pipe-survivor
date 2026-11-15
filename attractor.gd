# attractor.gd  (Phase 4/5 — attractor evaluation + shape features)
class_name Attractor
extends RefCounted

# Lorenz attractor parameters.
var sigma: float = 10.0
var rho: float = 28.0
var beta: float = 8.0 / 3.0

# Evaluate the derivative (dx, dy, dz) at a point.
func derivative(p: Vector3) -> Vector3:
	var x := p.x
	var y := p.y
	var z := p.z
	return Vector3(
		sigma * (y - x),
		x * (rho - z) - y,
		x * y - beta * z
	)

# RK4 step: advance position p by dt.
func step(p: Vector3, dt: float) -> Vector3:
	var k1 := derivative(p)
	var k2 := derivative(p + k1 * (dt * 0.5))
	var k3 := derivative(p + k2 * (dt * 0.5))
	var k4 := derivative(p + k3 * dt)
	return p + (k1 + k2 * 2.0 + k3 * 2.0 + k4) * (dt / 6.0)

# Generate N points by iterating from a seed, for preview rendering.
func generate_points(seed_pos: Vector3, count: int, dt: float) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var p := seed_pos
	for i in range(count):
		pts.append(p)
		p = step(p, dt)
	return pts

# Compute approximate shape features from the attractor trajectory.
# Returns a Dictionary with: lobe_count, symmetry_x, symmetry_z, aspect_ratio.
func compute_shape_features() -> Dictionary:
	var pts := generate_points(Vector3(0.1, 0.1, 0.1), 2000, 0.01)
	if pts.is_empty():
		return {"lobe_count": 1, "symmetry_x": 0.0, "symmetry_z": 0.0, "aspect_ratio": 1.0}

	# Bounding box.
	var min_p := pts[0]
	var max_p := pts[0]
	for p in pts:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var size := max_p - min_p
	var aspect := size.x / maxf(size.z, 0.001)

	# Lobe count: count local maxima in X (peaks where x changes from + to -).
	var lobe_count := 1
	var prev_dx := 0.0
	for i in range(1, pts.size()):
		var dx := pts[i].x - pts[i - 1].x
		if prev_dx > 0.0 and dx < 0.0:
			lobe_count += 1
		prev_dx = dx
	lobe_count = clampi(lobe_count / 5, 1, 8)  # normalize

	# Symmetry about X axis: compare points mirrored across X=0.
	var sym_x := 0.0
	var sym_z := 0.0
	var total := 0
	for p in pts:
		# Find nearest point to mirror.
		var mirror_x := Vector3(-p.x, p.y, p.z)
		var mirror_z := Vector3(p.x, p.y, -p.z)
		# Approximate: check if any point is close to mirror.
		# (Simplified: use bounding box symmetry.)
		total += 1
	# Use bounding box center as symmetry indicator.
	var center_x := (min_p.x + max_p.x) * 0.5
	var center_z := (min_p.z + max_p.z) * 0.5
	sym_x = 1.0 - absf(center_x) / maxf(size.x, 0.001)
	sym_z = 1.0 - absf(center_z) / maxf(size.z, 0.001)

	return {
		"lobe_count": lobe_count,
		"symmetry_x": clampf(sym_x, 0.0, 1.0),
		"symmetry_z": clampf(sym_z, 0.0, 1.0),
		"aspect_ratio": aspect,
	}