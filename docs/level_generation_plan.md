# Pipe Survivor — Level Generation Plan v2

**Goal:** turn the current linear hand-off chain into a seeded, run-based level that
supports *Vampire Survivors*-style pressure: the player travels a long, meandering
route through a **topological tube network with loops and side paths**, while a spawn
director ramps enemy **density** first and enemy **quality** later, ending in a boss.

This document supersedes the v1 plan. It keeps the working geometry pipeline
(`SectionGraph` → `PipeNetwork.add_section` → marker snapping) and adds a macro
topology layer, a connector section for exact loop closure, and a threat director.

---

## 1. Design Pillars

| Pillar | Meaning |
|---|---|
| **Run-based** | 12–18 minute floor, weak start → escalating pressure → boss payoff. |
| **Always moving** | The critical path is a clear, meandering route; stopping is dangerous. |
| **Route choice** | Loops and side paths offer risk/reward, escape space and flanking routes. |
| **Density → quality** | First half ramps how many enemies; second half ramps how dangerous they are. |
| **Deterministic** | Same seed → same macro graph, geometry, and director schedule. |
| **Debuggable** | Every generated level can be dumped as a graph/metrics summary. |
| **Validated** | Topology, geometry, seams, caps and threat monotonicity are checked headlessly. |

---

## 2. Gameplay Loop

1. Spawn in a sealed starting pipe. The **main path** is marked by signs/lighting.
2. Move forward; ambient enemies spawn behind and ahead. Early enemies are slow and weak.
3. At **junctions**, choose:
   - continue on the main path,
   - take a **side path** ending in a reward chamber (elite + upgrade), or
   - take a **loop** that rejoins the main path later (shortcut / flanking route).
4. Every zone boundary has a **rest chamber**: heal, choose a spell/sigil upgrade, see a
   short breather before the next ramp.
5. Enemy density rises until roughly 40–50% progress, then plateaus while elites,
   new archetypes and champion waves appear.
6. The final node is the **boss arena**; boss stats scale with the director's threat level.

Backtracking is allowed. Difficulty is driven by **furthest progress reached**, never by
current position, so retreating to a loop cannot farm an easier state.

### Progress metric

```
main_path_length = Σ length of macro edges on the critical route
progress(player) = max(main_path_distance_reached) / main_path_length   // 0..1, monotonic
```

Loops and side paths add local distance but do **not** count toward `progress`.

---

## 3. Topology Model

### 3.1 Macro graph

Generation produces a `MacroGraph`:

```
MacroNode
  id
  kind: ENTRY | CHAMBER | JUNCTION | REST | REWARD | BOSS
  position_hint: Vector3           # 2.5D placement, refined by the builder
  ports: Array[Port]               # each port becomes a section exit marker
  zone: int                        # 1..5, drives radius/enemies
  main_index: int                  # order along the critical path (-1 for side nodes)
  metadata: Dictionary

MacroEdge
  id
  from_node, from_port
  to_node, to_port
  kind: MAIN | LOOP | SIDE
  length_hint
  radius
  realization: CHAIN | CONNECTOR   # CHAIN = straights/bends, CONNECTOR = spline tube
  sections: Array[SectionNode]     # filled by subdivision
```

The macro graph is the authority for topology; the section graph is an implementation
detail used by the existing builder.

### 3.2 Main meandering path

The critical route is a single sequence `M0 … Mn`:

- Start with a forward-biased heading.
- At each anchor, choose a turn from `{-45°, 0°, +45°}` (occasionally 90° near zone
  boundaries), biased toward the global forward axis but away from already occupied space.
- Anchor spacing 60–150 units, with ±15° roll variation for 3D interest.
- A coarse spatial hash rejects anchors whose clearance to existing main-path segments is
  below `2 * radius + margin`.
- The route must keep a minimum global forward progress; if it turns back too far, the
  anchor is discarded and re-rolled.

The result is a serpentine, readable main path rather than a random walk. It may curve in
3D, but should not fold onto itself.

### 3.3 Loops

A loop is a `LOOP` macro edge joining two ports on the main path:

- Candidate pair `(Mi, Mj)` with `j >= i + 2` (skip at least one anchor).
- Prefer pairs 3–8 sections apart; this creates kiting space without skipping the whole floor.
- Each anchor offers at most one loop port; junction sections have a spare branch port.
- Loop count target: **2–4** for a 12–18 minute run (`cyclomatic number C = E − V + 1`).
- Loop radius = radius of the lower-zone anchor (seam continuity).
- Loop edges are realized as `CONNECTOR` sections, so both ends land exactly on the
  junction branch markers even when the main path curved between them.

Gameplay roles of loops:

- **Shortcut**: skips a stretch of main path, but the loop itself contains an elite pack.
- **Flank**: parallel route that lets the player escape a bad spawn; ambient spawns can
  appear on either side, so it never becomes a permanent safe lane.
- **Arena**: wide loop creates a natural kite ring around a junction.

### 3.4 Side paths

A side path is a `SIDE` macro edge (or short chain) from a junction branch to a
`REWARD` chamber:

- 3–6 side paths per floor, each 2–5 sections long.
- Ends in a reward chamber: spell/sigil choice, healing shrine, or elite treasure.
- Always sealed with an `EndCap` (no void), and always gives a reward so it is not a trap.
- A side path may optionally rejoin the main path; if it does, it is promoted to a `LOOP`.

### 3.5 Degree and port constraints

| Node kind | Ports | Notes |
|---|---|---|
| `ENTRY` | 1 | Initial main edge only; start cap behind the player. |
| `CHAMBER` | 2 | Pass-through section, may host a set-piece. |
| `JUNCTION` | 2–4 | Main in, main out, plus loop/side ports; maps to `JunctionPipeSection`. |
| `REST` | 2 | Wide chamber with a safe pocket, no ambient spawns inside. |
| `REWARD` | 1 | Terminal side chamber, capped; contains the reward. |
| `BOSS` | 1 | Terminal main node. |

Port records carry the exact transform used by the builder:

```
Port { position, forward (+Z flow), up/roll, radius, node_id, edge_id }
```

Exact port transforms make loop closure a construction-time guarantee, not a search.

---

## 4. Geometry: Chains and Connectors

### 4.1 Main-path edges: `CHAIN`

Main-path edges are subdivided into existing `STRAIGHT`/`BEND` sections chosen to land as
close as possible on the next port. Because both endpoints are fixed ports, the chain
solver gets the endpoint transform as a target, not just a direction:

1. Estimate the turn and distance between ports.
2. Choose a bend angle/roll and straight lengths.
3. Snap the chain to the parent exit, measure the residual error at the target port.
4. Try a small set of bend/roll combinations and keep the best.
5. If the residual exceeds tolerance, fall back to a `CONNECTOR` for that edge.

This preserves the cheap cached straight/bend meshes for the common case.

### 4.2 Loop/side edges: `CONNECTOR` (new section type)

A `ConnectorSection` is a swept tube along a cubic Hermite spline between two ports:

```
P(t) = h00(t) P0 + h10(t) m0 T0 + h01(t) P1 + h11(t) m1 T1
```

- `P0/P1` = start/end port positions; `T0/T1` = port forward directions.
- Tangents `m0/m1` are chosen from the port spacing and capped by a maximum curvature
  (minimum bend radius ≥ `2 * radius`).
- The path is offset sideways from the chord when a straight connector would clip other
  tubes; candidate offsets are tested with a capsule/segment clearance check.
- A parallel-transport frame sweeps `RING_SEGMENTS` rings; radius lerps between the port
  radii (normally equal).
- Mesh is emitted with inward normals and the correct clockwise front-face winding,
  exactly like the straight/bend sections. Collision is a trimesh with back-face collision.
- Entry/exit markers are set to the port transforms, so adjacent sections snap exactly.
- Connectors are cached by `(P0, P1, T0, T1, radius, ring_segments)`.

### 4.3 Seam and cap guarantees

- Every attached seam must have coincident centre, plane normal and radius (existing
  visibility harness).
- Every unconnected mouth is capped (`EndCap` mesh + collision).
- Connectors participate in the same `attached_from`/`attached_exit` bookkeeping.

---

## 5. Generation Pipeline

```
generate(seed, config):
    rng = SeededRNG(seed)

    # 1. Main route
    anchors = place_meandering_route(rng, config)
    graph = build_main_chain(anchors)

    # 2. Zone assignment and port radii
    assign_zones(graph, config)                 # 5 zones, monotonic narrowing
    assign_ports_and_radii(graph)

    # 3. Loops
    for candidate in loop_candidates(graph, rng):
        if graph.loop_count >= config.max_loops: break
        if clearance_ok(candidate): add_loop_edge(graph, candidate)

    # 4. Side paths
    for anchor in choose_side_anchors(graph, rng, config.side_path_count):
        add_side_path(graph, anchor, rng)

    # 5. Realize geometry
    for edge in graph.ordered_edges():
        edge.sections = solve_chain_or_connector(edge)

    # 6. Content, threat zones, rewards
    place_rests(graph)                          # zone boundaries
    place_rewards(graph)                        # end of side paths
    place_setpieces(graph)                      # junctions, loop arenas
    build_threat_curve(graph)

    # 7. Validate, repair, fallback
    return graph if validate(graph) else regenerate(seed + 1)
```

### 5.1 Zone assignment

Zones are assigned by main-path arc length, not node count:

| Zone | Main progress | Radius | Enemy theme |
|---|---|---|---|
| 1 | 0–20% | 12–16 | slow chasers, tutorial density |
| 2 | 20–40% | 10–14 | runners, first ambushers |
| 3 | 40–60% | 9–12 | tanks, mixed packs, first elites |
| 4 | 60–80% | 8–10 | ranged/chargers, elite packs, loop guards |
| 5 | 80–100% | 7–9 | champions, mini-boss, boss arena |

Radius is continuous at every seam and narrows monotonically within tolerance.

### 5.2 Loop placement algorithm

1. Build candidate pairs from anchors `i < j`, `2 ≤ j − i ≤ max_loop_span`.
2. Reject if either anchor already has a loop port.
3. Estimate a connector path; reject if it intersects existing tubes or has curvature
   below the minimum.
4. Score candidates by `shortcut_length * tension` where `tension` favours loops that
   cross the main route's bends and create interesting flanking space.
5. Take the best 2–4, mark their ports, add `LOOP` edges.

Loops are generated **before** side paths so they claim the spare junction branches.

### 5.3 Side-path placement

- Choose anchors in zones 2–4, spaced at least two zones apart.
- The side path starts at a junction branch and ends in a `REWARD` chamber.
- Reward type is seeded: sigil upgrade, spell mod, heal, or elite chest.
- Side path enemies use `zone + 1` threat, so the detour is risky but rewarding.

### 5.4 Self-intersection and clearance

All geometry is checked with capsule/segment distances:

- Anchor segments vs. all existing anchor segments.
- Connector samples vs. section centreline segments (radius-aware).
- Reject/adjust candidates rather than regenerating the whole level.
- If a loop cannot be routed, drop it; the minimum loop count is enforced by trying
  additional candidate pairs before falling back to a new seed.

---

## 6. Threat Director (VS-like escalation)

Replace the current per-network random `EnemySpawner` with a single `ThreatDirector`.

### 6.1 Inputs

```
progress     // 0..1, monotonic furthest main-path progress
zone         // 1..5
player       // position, health, spells
network      // sections, loops, visited graph
time_in_run
```

### 6.2 Two-phase curve

- **Phase A — Density (0–45%):** spawn rate and max-alive climb; enemy types stay simple.
- **Phase B — Quality (45–80%):** density plateaus; new archetypes, elites, and modifiers
  unlock; enemy HP/damage scale.
- **Phase C — Pressure (80–100%):** champion packs and mini-boss waves between the player
  and the arena; boss scaled by threat level.

Suggested starting numbers (all exported/tunable):

| Zone | Progress | Max alive | Spawn interval | Batch | Elite chance | Stat scale |
|---|---|---|---|---|---|---|
| 1 | 0–20% | 8–16 | 3.0 → 2.2 s | 1 | 0% | 1.00 |
| 2 | 20–40% | 16–30 | 2.2 → 1.4 s | 1–2 | 0–5% | 1.10 |
| 3 | 40–60% | 30–40 | 1.4 → 1.0 s | 2 | 5–12% | 1.25 |
| 4 | 60–80% | 38–46 | 1.0 → 0.8 s | 2–3 | 12–22% | 1.45 |
| 5 | 80–100% | 44–50 | 0.8 → 0.6 s | 3 | 22–35% | 1.70 |

`spawn_interval` and `max_alive` are clamped by measured frame time; if the budget is
exceeded, spawns are deferred rather than dropped forever.

### 6.3 Director state machine

```
AMBIENT   → normal budget, spawn behind/off-screen
PRESSURE  → when player health drops or a loop is entered: spawn ahead to cut off
WAVE      → every 45–75 s: one coordinated pack from a loop/side port
BREATHER  → 10 s after a rest chamber: reduced budget
BOSS      → arena seals, director stops ambient spawns, boss adds only
```

Spawn placement rules:

- Never inside a wall: sample a point on a section centreline with radial offset
  `< radius - enemy_radius`.
- Prefer: behind the player on the main path (chase), or out of a loop/side port
  (flank), or just beyond the next bend (surprise).
- Enforce a minimum distance from the player (e.g. 25–40 units) and a maximum (80).
- Ambushers may pre-place at untravelled junction exits, as today.

### 6.4 Enemy progression

| Tier | Archetypes | Role |
|---|---|---|
| 1 | Chaser | Basic pursuit; slow. |
| 2 | Runner | Faster, lower HP; punishes standing still. |
| 3 | Tank / Ambusher | Walls and junction traps. |
| 4 | Charger / Ranged | Lane denial, forces movement. |
| 5 | Champion | Elite modifiers, telegraphs, big HP. |

Elite modifiers (stack 1–2): `Armored`, `Hasted`, `Volatile` (death burst), `Splitter`,
`Shielded` (weak to a sigil family). Elites drop guaranteed upgrades/XP.

### 6.5 Boss scaling

Boss HP/damage = base × `stat_scale` at the arena zone; number of adds and attack
frequency follow the same curve. The boss arena is capped, so the fight cannot spill
into the void.

---

## 7. Content Cadence

| Progress | Beat |
|---|---|
| 0% | Start chamber, first weak pack, sign "FOLLOW THE PIPE" |
| 15–20% | First rest chamber + spell choice |
| 20% | First junction: side path + loop choice |
| 40% | Mid-zone rest, first elite |
| 50–60% | Loop arena / champion wave |
| 75% | Final rest, boss warning sign |
| 100% | Boss arena |

Rest chambers are safe pockets: no ambient spawns within the chamber, healing/shield,
and one choice. Side-path rewards are always visible from the junction sign.

---

## 8. Validation & Invariants

### 8.1 Topology

- Graph is connected; boss reachable from entry.
- `loop_count ∈ [config.min_loops, config.max_loops]` (2–4 default).
- `side_path_count ∈ [3, 6]`; every side path ends in a `REWARD` node.
- No node degree exceeds 4; no orphan ports.
- Main path length within target bounds (e.g. 45–75 sections).
- Loops connect anchors at least two macro nodes apart.
- Determinism: same seed → identical graph hash.

### 8.2 Geometry

- All seams: gap < 0.75, plane angle < 5°, radius mismatch < 0.75 (existing harness).
- Every section renders from inside; every triangle winding matches Godot's clockwise
  front-face convention.
- No uncapped mouth.
- No centreline segment closer than `r1 + r2 + margin` to another non-adjacent segment.
- Connector curvature radius ≥ `2 * tube_radius`.

### 8.3 Gameplay

- Threat level/stat scale is monotonic non-decreasing with progress.
- Director never exceeds `max_alive` or the frame-time budget.
- Spawn points are inside the tube and at least `min_spawn_distance` from the player.
- Elite/champion unlocks only after their configured progress thresholds.
- No reward chamber is unreachable or un-rewarded.

---

## 9. Testing Strategy

### 9.1 Generation harness (new: `tests/generation_harness.gd`)

For seeds 0–99:

- generate and validate topology (connectivity, loops, side paths, degrees),
- assert main-path length and zone order,
- assert loop anchors and connector closure (endpoint equals port transform),
- assert clearance and curvature,
- hash the graph summary for determinism,
- assert generation time < 1 s per level; print worst seed.

### 9.2 Geometry harness (extend `tests/visibility_harness.gd`)

- Connectors are included in winding, seam, cap and enclosure checks.
- Loop connectors at junction ports must pass the same seam gap/radius tests.

### 9.3 Director harness (new: `tests/director_harness.gd`)

Simulate progress 0→1 and time:

- threat curve monotonic,
- density plateau then quality ramp,
- elite/champion thresholds,
- max-alive/budget clamps,
- spawn positions valid (inside tube, distance band),
- boss scaling.

### 9.4 Run simulation (stretch)

Headless auto-drive along the main path plus loops for N seeds; assert the player can
reach the boss, no section oscillation deadlocks, and the director keeps pressure.

---

## 10. Implementation Phases

### Phase A — Topology data model & validation
- [ ] `MacroGraph`, `MacroNode`, `MacroEdge`, `Port` classes inside `level_generator.gd`.
- [ ] Seeded meandering route placement with spatial hash.
- [ ] Loop/side candidate generation and degree constraints.
- [ ] `tests/generation_harness.gd` for topology only (no geometry yet).
- **Acceptance:** 100 seeds produce connected graphs with 2–4 loops and 3–6 side paths.

### Phase B — Connector geometry
- [ ] `ConnectorSection` (spline sweep, mesh, collision, markers, caching).
- [ ] Clearance/curvature validation for connectors.
- [ ] Extend visibility harness; verify seams/caps/winding on connectors.
- **Acceptance:** loops close exactly; all geometry checks pass on 100 seeds.

### Phase C — Builder v2 (implemented)
- [x] Chain solving via connectors for all macro edges.
- [x] Macro nodes realized as chambers/junctions/rest/reward/boss.
- [x] Ring-center seam alignment.
- [x] v2 is the default; v1 retained as fallback.

### Phase D — ThreatDirector
- [ ] `ThreatDirector` replaces `EnemySpawner` ambient logic (ambush pre-placement kept).
- [ ] Progress tracking from main-path distance (monotonic).
- [ ] Enemy tiers, stat scaling, elites/champions, waves, boss scaling.
- [ ] `tests/director_harness.gd`.
- **Acceptance:** density→quality curve verified; no budget overruns in simulation.

### Phase E — Rewards & polish
- [ ] Reward chambers (spell/sigil/heal/chest) and rest choices.
- [ ] Zone signage and lighting; loop/side markers.
- [ ] Balance pass on 12–18 minute target; seed exposure in the menu.
- [ ] Save/load generated graph for debugging.

---

## 11. Configuration Sketch

```gdscript
class_name LevelConfig
extends Resource

@export var seed: int = 12345
@export var target_run_minutes: float = 15.0
@export var min_main_sections: int = 45
@export var max_main_sections: int = 75
@export var min_loops: int = 2
@export var max_loops: int = 4
@export var max_loop_span: int = 8
@export var side_paths: int = 4
@export var side_path_min_sections: int = 2
@export var side_path_max_sections: int = 5
@export var zone_count: int = 5
@export var min_radius: float = 6.0
@export var max_radius: float = 16.0
@export var rest_per_zone: int = 1
@export var max_alive_start: int = 10
@export var max_alive_end: int = 50
@export var spawn_interval_start: float = 3.0
@export var spawn_interval_end: float = 0.6
@export var elite_start_progress: float = 0.45
@export var champion_start_progress: float = 0.8
@export var generation_version: int = 2
```

---

## 12. Metrics to Log Per Seed

- seed, generation time
- macro node/edge counts, loop count, side-path count
- main-path section count and length
- section type histogram, radius range
- worst seam gap/angle/radius error
- connector count and worst curvature/clearance
- threat curve samples at 0/25/50/75/100%
- graph summary hash (determinism)

---

## 13. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Loop connectors clip existing tubes | Capsule clearance check; side-offset routing; drop loop and try another pair. |
| Connector kinks make the vehicle snag | Minimum curvature radius; seam/plane validation; keep connectors wide. |
| Loops trivialize the run | Limit shortcut distance/spans; put elite packs on loops; main path still gates zones. |
| Enemy density tanks performance | CPU spawn budget from frame time; max-alive caps; instancing later. |
| Difficulty curve feels flat | Data-driven table; log threat curve; playtest per zone. |
| Side paths feel mandatory or useless | Guaranteed reward + `zone + 1` risk; signpost before committing. |
| Deterministic regeneration diverges | Single RNG stream; graph hash test; avoid `randf()` from globals. |

---

## 14. Open Questions

1. Target run length: **12, 15 or 18 minutes**? The tables above assume 15.
2. Should loops be **shortcuts** (skip content) or **detours** (extra content)? Plan supports
   both; default is a shortcut with an elite guard.
3. Keep the current **crafting/spell UI**, or move to VS-style automatic level-up choices?
   Phase E assumes the current UI, with rewards granting spell/sigil choices.
4. Are **mini-bosses** at zone boundaries wanted, or only one final boss?
5. Should the main path be visually distinct (light strips/signs), or should route choice
   be ambiguous for exploration?
