# Pipe Survivor — Development Roadmap

Companion to `docs/pipe_survivor_spec.md`. Phases are ordered by dependency: each phase's
exit criteria must hold before the next begins. "Driving feel first" (spec §8) is the
gating principle.

---

## Phase 0 — Driving Feel Core (complete)

**Status:** Vehicle movement, gravity, steering, spiralling, centripetal load, and
multi-section traversal are working. Bend/straight/junction geometry and section snapping work.
Smooth steering-rate ramping is implemented. `tests/run.sh` verifies full-network traversal,
steering, branch driving, and tube-property correctness headlessly.

**Remaining polish (carried into Phase 1):**
- Camera behaviour and speed-feel tuning (exports now exist on the vehicle).
- Confirm half-lit pipe cause (normals/winding) and fix in mesh generation.

**Exit criteria:** `tests/run.sh` passes; vehicle can traverse the full authored network
without NaN, radius stays within pipe, section transitions are seamless. **Met.**

---

## Phase 1 — Driving Feel Polish & Lighting

**Goal:** Make the core fantasy (tube driving) feel right before anything else.

Deliverables:
1. **[Done]** Steering ramp: `steering_amount` moves toward input with a tunable rate
   (`steer_accel` export).
2. **[Done]** Camera: smooth lag and look-ahead along tube axis, roll inherited from vehicle.
3. **[Partial]** Speed feel: `gravity`, `speed`, `acceleration`, `friction`, `turn_speed`,
   `steer_accel` are now exports. A speed HUD readout is still missing.
4. **[Partial]** Lighting: ambient world environment added; per-section emissive/area lights
   and `AreaLight3D` rest-zone lighting still pending.
5. **[Open]** Resolve half-lit normals: flipping straight normals inward was tried and
   reverted (made it worse). Needs visual diagnosis in the editor before another fix.

**Exit criteria:** A playtester can drive the full network and report "feels good"; no
half-lit surfaces; `tests/run.sh` still green.

---

## Phase 2 — Junctions (the big architectural step)

**Status:** Core junction system is complete. Exit-branch, Y-split, and trident topologies
are supported via toggles. Centreline-based tube properties, CSG union mesh with per-fragment
wall colours, seam validation, and branch driving all work and are covered by the harness.
Remaining polish: `has_trunk`/branch selection UI, cache persistence to disk.

**Goal:** Turn the linear chain into a tree so routing decisions exist.

Deliverables (spec §6):
1. **[Done]** `PipeSection` interface: `exit` → `exits: Array[Marker3D]`; `get_tube_properties`
   and `contains_point` updated.
2. **[Done]** `PipeNetwork.add_section(packed, props, from_section, from_exit)`; branch
   attachment no longer assumes `sections.back()`.
3. **[Done]** `JunctionPipeSection`: radius, trunk length, branch angle, branch length,
   decision offset, `has_trunk`, `left_branch`, `right_branch` exports. Supports exit-branch,
   Y-split, and trident topologies. Exit markers and centrelines follow the enabled set.
4. **[Done]** Centrelines first: `Curve3D` cubic Bezier per path; `get_tube_properties` uses
   `get_closest_offset`; exit markers at endpoints with matching orientation.
5. **[Done]** Mesh: trunk/branch `CSGCylinder3D` primitives combined with a `CSGCombiner3D`
   union. Flat mouth and branch-start caps are stripped, normals flipped inward, and the single
   resulting mesh drives both rendering and trimesh collision. Verified zero internal-wall
   triangles and a drivable junction. Future optimisation: cache/bake the union mesh and reduce
   its triangle count (currently ~530).

6. **[Done]** Blend length / approach zone: `blend_length` export controls how far before the
   decision point the branch tubes start, creating a tunable overlap/transition zone. The CSG
   union blends the intersection automatically.

7. **[Done]** Wall-colour shader: per-fragment nearest-branch colouring via
   `junction_color.gdshader`. Branch starts and directions are passed as uniforms;
   disabled branches are pushed far away. Vertex colours are still set as a fallback.

8. **[Done]** Mesh caching: built meshes are cached in a static dictionary keyed by junction
   parameters, so identical junctions reuse the same mesh.
6. **[Partial]** Branch identification: branches have distinct colours via material overrides.
   Still missing: the per-fragment Voronoi wall-colour shader for a blended mesh.
7. **[Done]** Junction integrated into `main.gd`; harness drives through a branch.

**Exit criteria:** A junction scene loads, vehicle can choose either branch, snapping/collision
valid, `tests/run.sh` extended with a junction traversal case passes. Seam radius continuity is
enforced by the harness (the wide test section tapers back to the junction radius).

---

## Phase 3 — Rest Zones & Crafting Shell

**Goal:** Places where spellcrafting happens.

**Status:** Rest zone, crafting UI with preset sigils and parameter tuning, and signage are
implemented. The crafting UI shows 3 preset sigils, parameter sliders (sigma, rho, beta),
and a live attractor preview. Full sigil preview integration and signage iconography are
still pending.

Deliverables:
1. **[Done]** Rest-zone structure scene (wide chamber with trigger volume).
2. **[Done]** Vehicle slows on entry; "REST ZONE" label appears.
3. **[Partial]** Crafting UI overlay: presets, parameter sliders, and attractor preview.
   Full sigil preview integration pending.
4. **[Partial]** Signage: 3D sign with text and coloured indicator. Full iconography using
   attractor sigil vocabulary and branch colours still pending.

**Exit criteria:** Player can drive to a rest zone, stop, and see the crafting shell; signs
visible before junctions.

---

## Phase 4 — First Spell Prototype

**Goal:** One working attractor-driven mechanic.

**Status:** Attractor evaluation (Lorenz, RK4) and a vector-field spell zone are implemented.
The vehicle casts on `ui_accept` (Enter/Space) with a 2s cooldown. The zone applies the
attractor derivative as a velocity nudge to bodies inside for 5s. An `AttractorPreview`
node renders the Lorenz shape as a line strip above the vehicle in rest zones. Preset
sigils and the full crafting UI are still pending.

Deliverables:
1. **[Done]** Attractor evaluation (RK4) for Lorenz in GDScript, bounded parameters.
2. **[Done]** Vector-field zone spell: region applies attractor derivative as velocity nudge
   to entities for N seconds; fires from vehicle down the tube.
3. **[Partial]** Live preview of attractor shape: `AttractorPreview` node renders the
   Lorenz shape as a line strip above the vehicle in rest zones. Full crafting-UI
   integration pending.
4. **[Open]** Preset sigils ("cards") as starting spells; name → seeded sigil (spec §3.6).

**Exit criteria:** Player can cast a vector-field zone that affects a test projectile/debris;
shape preview renders. **Partially met** (cast works and affects vehicle velocity; preview
renders above vehicle in rest zones).

---

## Phase 5 — Enemies & Spawning

**Goal:** Survivors-like pressure from the network topology.

**Status:** Enemy archetypes (chaser + ambusher) and topology-driven ambushes implemented.
Chasers are fast (speed 15, health 2) and always chase. Ambushers are slow (speed 8, health 4)
and wait until the player is within 40 units, then activate. When the player passes a
junction, ambushers spawn at untraveled exits. A `weakness_sigil` property is reserved for
Phase 4 spell integration.

Deliverables:
1. **[Done]** Enemy vehicle scene using the same gravity/physics.
2. **[Done]** Enemy archetypes: chaser and ambusher with distinct stats and behaviour.
3. **[Done]** Topology-driven ambushes: when the player passes a junction, ambushers spawn
   at untraveled exits.
4. **[Partial]** Spawner: places chasers behind the player, ambushers at junctions. Faster-
   from-behind logic still pending.
5. **[Open]** At least two archetypes that make sigil shape matter (spec §2.5).

**Exit criteria:** Horde spawns and chases; player can survive ~60s with the Phase 4 spell.

---

## Phase 6 — Boss

**Goal:** A Lorenz-style boss with a live, never-exactly-repeating attack pattern.

Deliverables:
1. Boss scene with attractor-driven movement/attacks (attractor as verb, spec §3.4).
2. Boss arena (larger tube chamber or rest-zone-adjacent).
3. Win/lose flow.

**Exit criteria:** Boss fight is playable and readable; player can win and lose.

---

## Phase 7 — Vertical Slice & Ship

**Goal:** Small, shippable package.

Deliverables:
1. One tube-network "floor": handful of spells, enemy types, one boss.
2. Main menu, pause, game-over, basic audio.
3. Performance pass (instancing, collision cost).
4. Build/export for desktop.

**Exit criteria:** A new player can install and complete the slice without developer help.

---

## Cross-cutting: Testing

- Keep `tests/run.sh` green on every commit.
- Extend the harness with each new subsystem (junction traversal, spell cast, enemy spawn).
- Preserve any discovered failure as a replayable case under `tests/cases/`.
- Run the harness in CI once a runner is available.