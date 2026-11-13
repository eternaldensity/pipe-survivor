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
2. **[Open]** Camera: follow smoothing, look-ahead along tube axis, roll with vehicle.
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

**Goal:** Turn the linear chain into a tree so routing decisions exist.

Deliverables (spec §6):
1. **[Done]** `PipeSection` interface: `exit` → `exits: Array[Marker3D]`; `get_tube_properties`
   and `contains_point` updated.
2. **[Done]** `PipeNetwork.add_section(packed, props, from_section, from_exit)`; branch
   attachment no longer assumes `sections.back()`.
3. **[Partial]** `JunctionPipeSection`: radius, trunk length, branch angle, branch length
   exports; Y-split with trunk + two branches. Still missing: blend length, `has_trunk`,
   selectable left/right branches, trident topology.
4. **[Done]** Centrelines first: `Curve3D` cubic Bezier per path; `get_tube_properties` uses
   `get_closest_offset`; exit markers at endpoints with matching orientation.
5. **[Partial]** Mesh: rings swept along each centreline with trimesh + backface collision.
   Still missing: blended transition zone (~3× radius) so the separate tubes merge smoothly.
6. **[Partial]** Branch identification: branches have distinct colours via material overrides.
   Still missing: the per-fragment Voronoi wall-colour shader for a blended mesh.
7. **[Done]** Junction integrated into `main.gd`; harness drives through a branch.

**Exit criteria:** A junction scene loads, vehicle can choose either branch, snapping/collision
valid, `tests/run.sh` extended with a junction traversal case passes.

---

## Phase 3 — Rest Zones & Crafting Shell

**Goal:** Places where spellcrafting happens.

Deliverables:
1. Rest-zone structure scene placed in the network (a wider, lit chamber).
2. Vehicle slows on entry; crafting UI overlay (placeholder) appears.
3. Signage/iconography system: signs before splits using attractor sigil vocabulary and
   branch colours (spec §2.4).

**Exit criteria:** Player can drive to a rest zone, stop, and see the crafting shell; signs
visible before junctions.

---

## Phase 4 — First Spell Prototype

**Goal:** One working attractor-driven mechanic.

Deliverables:
1. Attractor evaluation (RK4) for one family (e.g. Lorenz) in GDScript, bounded parameters.
2. Vector-field zone spell: region applies attractor derivative as velocity nudge to entities
   for N seconds; fires from vehicle down the tube.
3. Live preview of attractor shape in crafting UI.
4. Preset sigils ("cards") as starting spells; name → seeded sigil (spec §3.6).

**Exit criteria:** Player can cast a vector-field zone that affects a test projectile/debris;
shape preview renders.

---

## Phase 5 — Enemies & Spawning

**Goal:** Survivors-like pressure from the network topology.

Deliverables:
1. Enemy vehicle scene using the same gravity/physics.
2. Spawner driven by topology: faster enemies from behind, ambushes from passed junctions.
3. At least two archetypes; one should make sigil shape matter (spec §2.5).

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