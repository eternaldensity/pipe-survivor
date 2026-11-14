shader_type spatial;
render_mode cull_back;

// Branch centreline start (decision point) and direction for each branch.
// Index 0 = trunk, 1 = left, 2 = right.
uniform vec3 branch_start[3];
uniform vec3 branch_dir[3];
uniform vec3 branch_color[3];
uniform float tube_radius = 10.0;
uniform float blend = 2.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Work in local space.
	vec3 lp = VERTEX;
	
	// Find nearest branch centreline.
	float best_dist = 1e9;
	int best_idx = 0;
	for (int i = 0; i < 3; i++) {
		vec3 s = branch_start[i];
		vec3 d = normalize(branch_dir[i]);
		float t = dot(lp - s, d);
		t = clamp(t, 0.0, 1000.0);
		vec3 closest = s + d * t;
		float dist = distance(lp, closest);
		if (dist < best_dist) {
			best_dist = dist;
			best_idx = i;
		}
	}
	
	// Smooth blend at boundaries.
	vec3 col = branch_color[best_idx];
	ALBEDO = col;
}