# Pipe Survivor — Level Generation System Plan

## 1. Overview

Replace the hand-authored section chain in `main.gd` with a **seeded, procedural level
generator** that produces a connected, navigable pipe network with difficulty progression,
junctions, rest zones, enemies, and a boss arena. The generator must be deterministic
(given a seed), robust (no invalid geometry), and produce varied, interesting layouts.

Instancing/LOD is deferred to a later epic; this plan focuses on **topology, geometry,
and gameplay content placement**.

---

## 2. Current State

- `PipeNetwork.add_section()` already supports arbitrary attachment (`from_section`,
  `from_exit`), so a **tree/graph** of sections is possible.
- Sections are self-positioning via marker snapping; no manual transforms.
- `get_section_at()` is sticky with nearest-midpoint fallback.
- The harness validates: radius continuity, no NaN, traversal, mesh normals.
- `main.gd` hand-assembles ~19 sections in a linear chain with one junction.

---

## 3. Design Goals

| Goal | Rationale |
|---|---|
| **Deterministic** | Same seed → same level (replay, debugging, sharing). |
| **Navigable** | Player can always reach the boss; no soft-locks. |
| **Varied** | Different seeds feel different (topology, radii, bends). |
| **Progressive** | Difficulty ramps: wider→narrower, gentle→sharp bends, more enemies. |
| **Validated** | Self-intersection, radius mismatch, and disconnected sections are rejected. |
| **Extensible** | New section types (loops, chambers) plug in without rewriting the generator. |
| **Fast** | Generation completes in < 1 second for a full floor. |

---

## 4. Architecture

### 4.1 Core Components

```
LevelGenerator (Node)
├── LevelConfig (Resource)       — seed, floor number, difficulty params, section counts
├── SectionPool (Resource)       — weighted list of available section templates
├── SectionGraph (class)         — nodes + edges, with metadata
├── PlacementValidator (class)    — self-intersection, radius, connectivity checks
├── ContentPlacer (class)        — rest zones, signs, enemies, boss, spawners
└── NetworkBuilder (class)       — converts SectionGraph → PipeNetwork.add_section calls
```

### 4.2 Section Graph

A level is a **directed graph** of `SectionNode` objects:

```
class SectionNode:
    id: int
    type: SectionType (STRAIGHT, BEND, JUNCTION, REST_ZONE, BOSS_ARENA)
    params: Dictionary (entry_radius, exit_radius, length, bend_angle, roll_angle, etc.)
    exits: Array[int]           # indices of child SectionNodes
    parent: int                 # index of parent (-1 for root)
    depth: int                  # distance from entry (for difficulty scaling)
    position: Vector3           # world position (computed by builder)
    transform: Transform3D      # world transform (computed by builder)
    metadata: Dictionary        # e.g. "has_rest_zone", "enemy_count"
```

The graph is built first, then embedded in 3D via `NetworkBuilder`.

### 4.3 Section Types & Templates

| Type | Params | Notes |
|---|---|---|
| `STRAIGHT` | entry_radius, exit_radius, length | Doubles as size adaptor. |
| `BEND` | tube_radius, length (arc), bend_angle, roll_angle | roll_angle enables 3D bends. |
| `JUNCTION` | tube_radius, trunk_length, branch_angle, branch_length, has_trunk, left/right | Y-split, exit-branch, trident. |
| `REST_ZONE` | radius, length | Wide chamber; replaces a straight section. |
| `BOSS_ARENA` | radius, length | Widest section; terminal node. |

Each template has a **difficulty tier** (1-5) and **weight** for random selection.

### 4.4 Difficulty Tiers

| Tier | Radius range | Bend angle | Bend frequency | Junction freq | Enemies |
|---|---|---|---|---|---|
| 1 (start) | 12-16 | 10-20° | low | none | none |
| 2 | 10-14 | 15-30° | medium | 0-1 | chasers |
| 3 | 8-12 | 20-45° | medium | 1-2 | chasers + ambushers |
| 4 | 6-10 | 30-60° | high | 2-3 | all types |
| 5 (boss) | 8-12 | 20-40° | medium | 1 | boss + enemies |

Radius continuity: adjacent sections must have matching radii at the seam (±0.5).

---

## 5. Generation Algorithm

### 5.1 High-Level Flow

```
generate(config):
    rng = SeededRNG(config.seed)
    graph = SectionGraph()
    entry = graph.add_node(STRAIGHT, tier=1, params=defaults)
    current = entry
    depth = 0
    max_depth = config.target_depth (e.g. 8-12 sections)

    while depth < max_depth:
        tier = difficulty_at(depth, max_depth)
        # Decide: continue, branch, or rest zone
        roll = rng.next_float()
        if depth % config.rest_interval == 0 and depth > 0:
            node = add_rest_zone(graph, current, tier)
        elif roll < config.junction_prob(tier) and depth < max_depth - 2:
            node = add_junction(graph, current, tier, rng)
            # Recursively generate each branch (shorter)
            for each branch exit:
                generate_branch(graph, node, exit, tier+1, rng, remaining_depth)
        else:
            node = add_continuation(graph, current, tier, rng)
        current = node
        depth += 1

    # Terminal: boss arena
    boss = graph.add_node(BOSS_ARENA, tier=5, attached to current)
    graph.validate()
    return graph
```

### 5.2 Continuation Selection

`add_continuation(graph, parent, tier, rng)`:
1. Pick a section type from the weighted pool for this tier.
2. Compute params: radius = clamp(parent.exit_radius + rng.range(-2, 2), tier.min_radius, tier.max_radius).
   Length = rng.range(tier.min_length, tier.max_length).
3. If type is BEND: bend_angle = rng.range(tier.min_angle, tier.max_angle), roll_angle = rng.choice([0, 90, 180, 270]) for 3D variety.
4. Validate radius continuity: |new.entry_radius - parent.exit_radius| < 0.5.
5. If invalid, retry with different params (up to 5 attempts), else fall back to STRAIGHT with matching radius.
6. Add node, attach to parent's exit 0.

### 5.3 Junction Generation

`add_junction(graph, parent, tier, rng)`:
1. Pick topology: has_trunk (rng 60%), left_branch (rng 70%), right_branch (rng 70%). Ensure at least 2 exits.
2. tube_radius = parent.exit_radius (or clamped to tier range).
3. branch_angle = rng.range(20, 45).
4. branch_length = rng.range(60, 120).
5. decision_offset = rng.range(15, 30).
6. Add JUNCTION node.
7. For each enabled exit, generate a sub-branch: a short chain (2-4 sections) ending in a dead end or reconnecting.
8. Sub-branches use tier+1 difficulty.

### 5.4 Sub-Branch Generation

`generate_branch(graph, junction, exit_index, tier, rng, depth_budget)`:
1. current = junction, exit = exit_index
2. for i in range(depth_budget):
   - type = pick from pool (tier)
   - params = compute (radius from previous exit)
   - add node, attach to current/exit
   - current = node, exit = 0
   - if rng.next() < config.dead_end_prob: break (branch ends)
3. No boss arena on branches (only trunk reaches boss).

### 5.5 Self-Intersection Avoidance

After generating the graph, embed it in 3D:
1. Walk the graph depth-first from entry.
2. For each node, compute its transform from parent's exit transform (existing snapping).
3. Check if the new section's bounding cylinder intersects any previous section's bounding cylinder (axis-aligned or OBB).
4. If intersection: try rotating the bend's roll_angle by 90° (for bends) or reject the branch.
5. If still intersecting: prune that branch (convert junction to fewer exits or remove branch).

Simplification for v1: only check trunk path for intersections; branches are short and unlikely to collide. Full collision checking can be added later.

### 5.6 Validation

`graph.validate()`:
- Every node reachable from entry.
- Every non-root node has a parent.
- All exit indices are valid.
- No section has zero radius.
- Radius continuity: |child.entry_radius - parent.exit_radius| < 1.0 for all edges.
- At least one path reaches the boss arena.
- Depth of boss arena >= config.min_depth.

If validation fails, regenerate with seed+1 (up to 10 retries).

---

## 6. Content Placement

### 6.1 Enemies

- **Spawner placement**: Add an `EnemySpawner` to every straight section of tier >= 2.
- **Ambush placement**: When generating a junction, spawn 1-2 ambushers at untraveled exits.
- **Boss**: Single boss at the arena.

### 6.2 Rest Zones

- Place a `RestZone` section every `config.rest_interval` sections along the trunk.
- Rest zones are wider (radius +5) and replace a straight section.

### 6.3 Signs

- Place a `Sign` node before each junction (15 units before entry).
- Sign text/color reflects the branch properties (e.g., "NARROW", "REST", "BOSS").

### 6.4 Wall Colour

- Each branch's walls get a distinct colour (already via material overrides).
- Signs use the same colour.

---

## 7. Implementation Plan

### Phase 7.1 — Core Generator (Week 1)
- [ ] Create `level_generator.gd` with `LevelConfig` and `SectionGraph`.
- [ ] Implement `add_continuation`, `add_junction`, `generate_branch`.
- [ ] Implement `NetworkBuilder` (graph → PipeNetwork calls).
- [ ] Implement basic validation (reachability, radius continuity).
- [ ] Replace `main.gd` hand-assembly with `LevelGenerator.generate(seed)`.

### Phase 7.2 — Difficulty & Variety (Week 2)
- [ ] Implement difficulty tiers and parameter scaling.
- [ ] Add roll_angle variety to bends (3D routing).
- [ ] Implement self-intersection avoidance for the trunk.
- [ ] Add rest zone placement.
- [ ] Add enemy spawner placement.

### Phase 7.3 — Content & Polish (Week 3)
- [ ] Sign placement with branch colours.
- [ ] Boss arena placement at terminal node.
- [ ] Validation retries (regenerate on failure).
- [ ] Expose seed in main menu (input field or random).
- [ ] Save/load the generated graph for debugging.

### Phase 7.4 — Testing (Week 4)
- [ ] Extend harness: generate 100 random seeds, validate all.
- [ ] Add traversal test: vehicle reaches boss on generated levels.
- [ ] Add performance test: generation < 1s for 100 seeds.
- [ ] Add edge cases: seed 0, very small/large depth.

---

## 8. Testing Strategy

### 8.1 Unit Tests (Headless)
- `test_level_generator.gd`: generate N seeds, assert validity, no crashes.
- `test_level_traversal.gd`: drive through each generated level, assert reachability.
- `test_level_radius.gd`: assert radius continuity at all seams.
- `tests/visibility_harness.gd`: every section has a mesh, every triangle's winding
  matches Godot's clockwise front-face convention so it renders from inside, radial
  rays from the centreline reach a wall (2976 rays on the default seed), connected
  seams meet with matching centre/normal/radius, and every uncovered mouth is capped.

### 8.2 Invariants
- Every generated level has a path from entry to boss.
- No section has radius < 4 or > 25.
- No two sections of the trunk intersect.
- Generation time < 1s per level.
- 100 consecutive seeds all valid (no regeneration failures).

### 8.3 Property-Based Testing
- Use the existing harness infrastructure.
- Generate levels with random seeds and validate invariants.
- Report the first failing seed and its graph.

---

## 9. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| Self-intersection makes levels invalid | Start with 2D (flat) generation, add 3D bends later. Retry on failure. |
| Branches create dead ends | Limit branch depth; ensure trunk always reaches boss. |
| Performance of CSG mesh generation | Cache by (type, params); pre-build common variants. |
| Difficulty curve feels wrong | Expose tier params as exports; iterate with playtesting. |
| Radius mismatch at seams | Validate and reject; fall back to matching radius. |

---

## 10. Open Questions

1. Should levels be **linear with branches** (spec §6) or **fully procedural graphs**?
2. Should the generator produce **loops** (reconnecting branches) for replayability?
3. What is the target **floor length** (number of sections)? 8-12? 15-20?
4. Should **enemy placement** be part of generation or a separate pass?
5. Should the level be **saved as a resource** for debugging/replay?

---

## 11. Immediate Next Steps

1. Create `level_generator.gd` skeleton with `LevelConfig` and `SectionGraph`.
2. Implement `add_continuation` with radius continuity validation.
3. Replace `main.gd` hand-assembly with `LevelGenerator.generate(12345)`.
4. Run the harness on the generated level.
5. Add junction generation once the linear path works.