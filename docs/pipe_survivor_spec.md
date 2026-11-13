# Pipe Survivor — Design & Development Specification

**Engine:** Godot 4.7, Forward+ renderer, GDScript
**Platform:** Desktop native
**Status:** Early prototype (vehicle movement + procedural pipe network working; junctions in design)

> **Note to the reading agent:** This document records design intent and decisions reached in conversation. The actual code is the source of truth for implementation details. Where this document and the code disagree on a *how*, trust the code; where they disagree on a *why* or a *where we're heading*, trust this document. Items marked **[Decided]**, **[Leaning]**, or **[Open]** indicate confidence.

---

## 1. Concept

A high-speed vehicle game set entirely inside a network of large tubes. Instead of "gravity is down", there is a force pushing the vehicle **away from the centre line of the current tube**, so the vehicle can drive on any part of the tube wall (floor, walls, ceiling) equally. Tubes branch, bend, and change size in arbitrary 3D directions. Increasing hordes of enemy vehicles turn it into a **Survivors-like** (Vampire Survivors genre): survive escalating pressure while routing through the network and fighting with a magic system.

The magic system is built on **strange attractors** (see §3). The tube network is the whole world, not a level containing a tube.

The long-held core fantasy is the tube-driving itself ("something I've had inside me for years"). **Driving feel is load-bearing for everything else** and must be right before magic/enemies matter.

### Rejected alternative
A Grid Wars / Vampire Survivors twin-stick arena was considered and dropped (a game called *Geometry Survivor* already exists on Steam, and the tube concept is the author's real interest).

---

## 2. Game Frame

### 2.1 Core loop **[Decided]**
1. **Drive** through the tube network at speed, making routing decisions at junctions.
2. **Fight** a growing horde of enemy vehicles using attractor-based spells while driving.
3. **Rest** at rest-zone structures between driving sections; this is where spellcrafting happens.

### 2.2 Scope **[Decided]**
Small and shippable: one tight mechanic done well. Initial target is a prototype of the driving feel, then one tube-network "floor" with a handful of spells and enemy types, then a boss.

### 2.3 Rest zones **[Decided]**
Spellcrafting cannot be done while also driving at high speed in 3D, and choosing/comparing spell variants is not feasible mid-drive. So crafting happens in **rest zones: physical structures in the world** that the player drives to. The vehicle slows, the world quiets, and the player does spellcrafting. The rest zone is a *place*, not a pause menu.
- **[Open]** Whether rest zones are safe, or enemies can pressure the player while crafting (creating tension around lingering).

### 2.4 Routing and signage **[Decided]**
- The player makes real routing decisions at junctions.
- **Signs with iconography** appear before splits to communicate the properties of upcoming paths (threat, reward, rest zone, boss chamber, etc.).
- Sign iconography should use the **attractor sigil visual vocabulary**, so players learn to read attractor glyphs as navigational language.
- **Wall colour as lane indicator [Decided]:** each branch's walls are coloured so the driver can see at a glance which path is which ("follow the blue wall"). Signs use the same colours.
- Possible extension **[Leaning]**: wall colour also hints at the spell environment / attractor family associated with a branch, merging navigation and spellcrafting decisions.

### 2.5 Enemies **[Leaning]**
- Enemies are also vehicles in the tube network, subject to the same centrifugal gravity.
- Horde has spatial logic: faster enemies catch up from behind, ambushes come from junctions already passed, the tube topology effectively *is* the spawn system.
- Enemy archetypes should make **sigil shape matter** (e.g. an enemy weak to certain geometric features). A guiding principle: *every system decision should answer "does this make the sigil shape matter more or less?"*

### 2.6 Bosses **[Leaning]**
Boss attack patterns are driven by **live attractor dynamics** (see §3.4).

---

## 3. Magic System: Strange Attractors

### 3.1 Why attractors
Strange attractors are deterministic but never exactly repeat; chaotic (sensitive to initial conditions) yet bounded. That gives "magic that feels alive but is not just an RNG." The attractor's *geometry is the lore*: each family has a recognisable visual identity at no extra art cost.

### 3.2 The attractor as a source of structured information
The attractor does **not** have to directly govern a spell's path. It is a source of geometric, dynamic and statistical information that can be routed into many things:

- **Static shape** → spell classification, AoE layout, hit patterns.
- **Live flow / dynamics** → vector-field zones, rhythm/pulses, enemy/boss behaviour.
- **Parameters** → spell stats derived from geometric features, volatility near bifurcation.
- **Sensitive dependence** → divergence between near-identical casts (only where it can be player-controlled; see 3.4).

### 3.3 Sigil reading (geometry as spell meaning) **[Leaning]**
The shape of a crafted attractor is read like a rune and classified into an effect. Proposed grammar (mostly independent axes, so combinations produce rich outcomes):

| Shape feature | Maps naturally to |
|---|---|
| Lobe count | Number of targets / instances |
| Self-intersection / weave density | Binding / stacking effects (snares, DoT stacks) |
| Rotational symmetry order | Summon/echo count |
| Aspect ratio | Beam/line vs nova/AoE |
| Fractal / fill density | Area saturation (thicker storm/cloud) |
| Chirality (winding direction) | Polarity (drain vs grant, push vs pull) |
| Proximity to bifurcation boundary | Volatility (stable vs wild variant) |
| Map (discrete) vs flow (continuous) | Illusion/glamour vs elemental force |

Design tension to respect: keep core power stats (damage, size, duration) **blending smoothly** across a regime; reserve hard qualitative flips for deliberate "edge of chaos" tuning near bifurcations.

A throwaway prototype ("sigil reader", Clifford attractor with sliders for a/b/c/d and a live readout of lobes/symmetry/weave/aspect/fill/polarity) exists only as a thought experiment; it is not part of the game code. It proved the mapping can be *felt* by playing with it, but its classifiers are heuristics, not rigorous.

### 3.4 Player vs boss asymmetry **[Decided]**
- **Player spells: attractor as *noun*.** A fixed, crafted object with known properties. Spell behaviour is **repeatable by default**, varying only by **controllable factors**. No RNG-seeded chaos for the player. Chaos, where present, is seeded by player state: aim, movement state/velocity at cast, cast timing relative to other effects, spell sequence. ("Expressive determinism": different output means the player *did* something different.)
- **Boss patterns: attractor as *verb*.** A live, never-exactly-repeating-but-bounded process. A Lorenz-style boss stays within two lobes and eventually flips; players learn to read the system rather than a scripted rotation.

### 3.5 Candidate output mappings
- **Vector-field zone [leaning toward this as the lead mechanic]:** for N seconds a region applies the attractor's derivative as a velocity nudge to entities inside (enemies, projectiles, debris, even the player). Natural fit for a tube cross-section as a container. Enables coupling/interference between overlapping fields.
- **Swarm cloud:** many jittered initial conditions all trace the same attractor shape; each mote unique, collectively coherent.
- **Single trajectory bolt / carved zone / stat modulation:** possible, lower priority.
- Spell geometry interacts with tube geometry (e.g. a dense-fill spell plugs a tube section behind the player; an elongated spell reaches far down the tube ahead).

### 3.6 Crafting UX **[Leaning]**
- Players start with **named preset sigils** found like cards ("Tidecaller's Weave"), not raw parameters. Raw parameter tuning is an endgame unlock.
- During tuning always show a **live preview of the shape**; the geometry is the feedback.
- Crafting happens in rest zones (§2.3).
- Discovery loop: nudge dials, watch the shape, engine reveals what you drew, bind/name it into a personal grimoire.
- A caster's **name can deterministically generate a personal sigil** (word → seeded PRNG → attractor family + parameters).

### 3.7 Attractor families under consideration
Lorenz, Thomas, Rössler, Aizawa, Four-Wing, Halvorsen, Dadras, Chen, Sprott B (all with verified bounded-chaotic parameter ranges in the reference generator), plus Clifford (a discrete *map* rather than a flow).

### 3.8 Reference material
A browser-based strange attractor "specimen" generator (JS, RK4 integration, 1.5M points, density splatting, log tone-mapping, bloom, depth shading, per-word seeding) was reviewed as a visual and mathematical reference. It is a reference for rendering and for the family parameter ranges, not part of the game code.

Comparable games for contrast: *Noita* and *Magicraft* (both use discrete modifier chains; the attractor approach differs by offering continuous tunable families and never-identical-but-bounded behaviour).

---

## 4. Tube World & Driving Physics

### 4.1 Local gravity **[Implemented]**
- Project's default 3D gravity is set to **0**. All gravity is custom.
- Each frame the vehicle asks the pipe network for the properties of the tube it's in: `axis` (centreline tangent, world space), `origin` (nearest point on centreline), `radius`.
- "Outward" = from the nearest centreline point toward the vehicle. Gravity pulls along outward (into the wall). `up_direction` = inward.
- The vehicle's basis is smoothly slerped to keep its local Y pointing toward the tube centre.

### 4.2 Vehicle **[Implemented, to be refined]**
- `CharacterBody3D` (custom physics rather than `RigidBody3D`).
- Steering rotates heading around the surface normal; throttle drives along the facing direction. A slightly angled heading therefore produces a **spiral** path.
- Less-straight driving means more "curving upward": increased centripetal load on the wall, and reduced forward progress along the tube axis (falls out of the velocity vector, no special code).
- Centripetal term added to press the vehicle into the wall while spiralling.
- Author plans to add smooth steering-rate ramping (currently all-or-nothing). Camera is placed behind/above in the vehicle's local frame.
- **[Open]** Pure circumferential strafing without forward motion is currently impossible; judged probably unnecessary.

### 4.3 Collision
- Pipe collision is generated as **trimesh (`ConcavePolygonShape3D`) with Backface Collision enabled** (required because the vehicle collides from the inside).
- Collision generation is skipped in the editor (`Engine.is_editor_hint()`).

---

## 5. Pipe Network Architecture **[Implemented unless marked]**

### 5.1 Concept
The world is a chain/graph of **pipe sections**. Each section is a scene with **an `Entry` marker and one or more exit markers**. `PipeNetwork` assembles them programmatically by snapping each new section's entry transform onto a previous section's exit transform. No manual positioning.

### 5.2 Marker convention (important)
- `Marker3D` nodes. **The blue (+Z) axis points in the direction of travel** at both entry and exit. (Entry +Z points into the section; Exit +Z points out of it.)
- Snapping: `section.global_transform = exit_T * entry_local.affine_inverse()`.
- Because the full transform (rotation included) is carried, bends and rolls compose correctly down the chain.

### 5.3 Class structure
- **`PipeSection`** (base, `class_name`, `@tool`): shared interface — `entry`, `exit(s)`, `get_tube_properties(world_pos) -> Dictionary {axis, origin, radius}`, `contains_point(world_pos) -> bool`.
- **`StraightPipeSection`**: `entry_radius`, `exit_radius`, `length`. A cylinder/frustum (so it doubles as a size adaptor). Markers repositioned in `_ready` from `length`. Mesh built as a `CylinderMesh` with caps disabled.
- **`BendPipeSection`**: `tube_radius`, `tube_length` (arc length), `bend_angle` (degrees), `roll_angle` (degrees, rotation of the bend plane around the entry's Z axis, so bends can go left/right/up/down/diagonal). Bend radius is derived: `bend_radius = tube_length / angle_rad` and must exceed `tube_radius` (asserted). Mesh is procedurally swept along the arc.
- Design decision: **different scenes + different scripts sharing a base class**, since `get_tube_properties` and mesh generation are genuinely different logic per shape, not parameter differences.
- **`PipeNetwork`**: owns `sections`, `add_section(packed_scene, props_dict)` (props applied *before* `add_child` so `_ready` sees them), and `get_section_at(world_pos)`.
- `main.gd` builds the initial network in `_ready`.

### 5.4 Section lookup
`get_section_at` is **sticky**: stay in the current section while `contains_point` is true, then search other sections via `contains_point`, with nearest-midpoint as a last-resort fallback. Containment margins are small (a few units).

### 5.5 Bend tube-properties details (hard-won)
- Arc angle is found by `atan2` seeded then refined with a few Newton steps (raw `atan2` was unstable on the inside/outside of bends).
- Tangent is computed **analytically** as `(sin θ, 0, cos θ)` in unrolled local space, then rolled and transformed to world. This replaced an earlier finite-difference sample at `angle ± ε`, which degenerated at clamped arc endpoints and for very small bend angles.
- Blending properties between adjacent sections near joins was tried and made things worse; it was reverted.

### 5.6 Known gotchas (carry forward)
- `@tool` on a derived script requires `@tool` on the base class too.
- `@tool` `_ready` can run repeatedly in the editor and duplicate generated children; guard collision generation and clear previous children.
- Leftover node transforms in the `.tscn` (e.g. a rotated `MeshInstance3D` or `Entry` marker) can silently fight code-set transforms. Reset with `transform = Transform3D.IDENTITY`.
- Straight and bend meshes must use the **same ring segment count** (shared constant `PipeSection.RING_SEGMENTS = 32`); mismatched counts caused an edge-on collision bump at joins.
- Marker rotation signs for bend exits were tuned empirically; read the code rather than re-deriving.
- Marker gizmos for `@tool`-set rotation may display stale in the editor even when runtime snapping is correct.

---

## 6. Planned: Junctions

### 6.1 Topology vocabulary **[Decided]**
Not literal 90° T-branches. Instead, tree-branch / motorway-exit style:
- **Exit branch:** straight-ahead trunk plus one side branch peeling off at a modest angle.
- **Y-split:** no trunk; two symmetric branches diverging at equal and opposite angles.
- **Trident:** straight-ahead trunk plus two mirrored side branches.

These are one parameterised `JunctionPipeSection` (extends `PipeSection`), proposed exports: `tube_radius`, `trunk_length`, `branch_angle`, `branch_length`, `blend_length`, `has_trunk`, `left_branch`, `right_branch`. **[Open]** target `branch_angle` range (shallow 10–20° exit-ramp style only vs up to ~45°).

### 6.2 Interface change
The single `exit` becomes an **array of exit markers** (`exits`). `PipeNetwork.add_section` gains a `from_exit` index (and ideally a `from_section` reference) so a branch can be attached to any exit of any prior section, turning the chain into a **tree/graph**. The `sections.back()` assumption must go.

### 6.3 Internal structure **[Leaning]**
Entry tube → approach zone (single tube; signage appears here; length tunable because higher speeds need more reading distance) → decision point (centrelines visibly diverge) → blend zone (cross-section morphs) → separated exit tubes. Centrelines should diverge early and clearly enough for readability even if the mesh blend is smooth. This implies a minimum straight length before any junction.

### 6.4 Centrelines first
Everything else (mesh, collision, `get_tube_properties`, `contains_point`, signage placement) derives from centrelines. Proposed: each path is a cubic Bézier / Godot `Curve3D` tangent to the entry direction at the start and the exit direction at the end. `get_tube_properties` finds the nearest centreline (`Curve3D.get_closest_offset`) and returns its tangent/origin. Exit markers are placed at curve endpoints with matching orientation.

### 6.5 Mesh **[Open, hardest remaining piece]**
Sweep a cross-section ring along each centreline and blend rings in the transition zone so one circle becomes multiple circles without a hard crease (a medial-axis style weighted blend was suggested; transition length roughly 3× tube radius). The asymmetric exit branch is the hardest case; solving it should make Y-split and trident special cases. Collision must remain a valid trimesh with backface collision, with consistent ring segment counts at all mouths.

### 6.6 Wall-colour shader **[Leaning]**
Colour via a **shader rather than material boundaries in the mesh**: per-fragment, compute which exit centreline a surface point is nearest and mix that exit's colour, with a `smoothstep` soft edge at the Voronoi-style boundary (the medial surface between exits). Before the decision point walls are neutral; after it they show their exit's colour. Shader parameters can later signal state (blocked branch desaturated/flickering, rest-zone branch glowing warmer). Uniforms would carry exit directions (in local space) and colours. Note the sketched shader used `NORMAL` as a proxy; a position-relative-to-centreline formulation is likely more correct.

---

## 7. Immediate Known Issues / Next Steps

1. **Half-lit pipes (normals bug).** On existing pipes, one half of the cross-section (split lengthways) appears dark and the break is disjoint between pipes, so it is not the directional light. Suspected: inverted or inconsistent normals and/or winding on half the ring. Diagnose with the editor's normal-visualisation / debug draw modes, then fix in mesh generation (bend) and check the straight pipe's `CylinderMesh` (front-face cull used to see the inside). Fix before building junction meshes so they inherit correct conventions. **Status note:** flipping straight-pipe normals inward via `SurfaceTool.generate_normals(true)` was tried and reverted — it made rendering worse. The root cause is still unconfirmed; treat this as needs visual diagnosis rather than a known code fix.
2. **Junction implementation:** exit array refactor in `PipeSection`/`PipeNetwork` → junction centrelines → `get_tube_properties`/`contains_point` → markers → mesh blend → colour shader.
3. **Lighting for enclosed tubes:** a single directional light pointing down the tube leaves it dark; the enclosed environment needs deliberate lighting (emissive/area lights, e.g. `AreaLight3D` for rest zones).
4. **Driving feel polish:** smooth steering ramp, camera behaviour, speed feel.
5. **Rest zone structure and crafting UI** once the driving and network are solid.
6. **First spell prototype:** likely a vector-field zone and/or a swarm cloud firing from the vehicle in the tube.
7. **Enemy vehicles, spawning from network topology, one boss with an attractor-driven pattern.**

### Godot 4.7 features worth using
HDR output (glowing attractor visuals against dark tubes), `AreaLight3D` (rest zones), inline shader previews (custom tube/spell shaders), `Path3D` snap-to-collider and 3D vertex snapping (network layout), `DrawableTexture2D`.

---

## 8. Guiding Principles

- Driving feel first; everything else depends on it.
- Spatial solutions over UI solutions (rest zones are places; lane colours are in the world).
- Player magic is repeatable and controllable; chaos belongs to bosses and to player-seeded inputs, never hidden RNG.
- Geometry is meaning: sigil shape should matter mechanically, visually, and in navigation language.
- Keep the architecture honest: shared interface, per-shape implementations, programmatic assembly.
- Stay small and shippable.
