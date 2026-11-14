# attractor.gd  (Phase 4 — first pass)
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