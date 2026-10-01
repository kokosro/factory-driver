# L2 Proximity Streaming — Design

Ruling-ready design for L2-STREAMING-1 phase 1 (plan.org ID 9E724743): streaming the world
around the car as it drives, so the Ring loads as a thin base and the heavy dressing builds
by proximity. Every proposal below is marked **PROPOSED**; nothing is implemented. Claims
about existing code cite files and lines verified 2026-10-01 against HEAD (48ea96e).

## 1. Canon

- **ASYNC WORLD LOADING + STREAMING** (decisions.org C07BE6F1, 2026-09-27, the driver):
  "no freezing load, world-around-the-car streaming, research how the big ones do it."
  The canon note recorded with it steers the mechanism: "the physics bubble (5BE9FBA3) is
  the natural ally: chunk-based collision activation already exists — the loading/streaming
  system should mirror the bubble's chunk topology."
- **The loading brief** (plan.org 2D076B0B, folded into LOADING-1): L1 loading screen
  landed (commit 1277e54), **L2 proximity streaming is next**, L3 continent after.
- **OPEN WORLD CONTINUITY** (decisions.org DAF72FC6): "everything reachable, procedural
  beyond the data" — L2 must not wall the world into a loaded box; the continuation bands
  and the profile already answer beyond the drape.
- **INTERACTIVE PHYSICS BUBBLE** (decisions.org 5BE9FBA3): proximity-activated collision is
  canon — L2 extends its pattern from collision layers to build/retire.
- loading.gd's own header draws the boundary this design crosses: "The world-around-the-car
  streaming is L2 and not this pass: the whole Ring is built, once, off the main thread."
  (scripts/loading.gd:15-17.)

## 2. What exists today, in code terms

### 2.1 The one-shot async build (L1, landed)

`LoadingScreen` (scripts/loading.gd) instantiates `eifel_ring.tscn` **outside the tree**,
claims its four builders (`build_deferred = true`, loading.gd:283-287), and runs 13 stages
(loading.gd:289-301, header table 30-57):

| stage | kind | waits for | measured weight s (loading.gd:141-145) |
|---|---|---|---|
| road_prepare | task | — | 1.8 |
| road_sweep | group | road_prepare | 4.9 |
| terrain_fields | task | road_prepare | 2.3 |
| terrain_meshes | group | terrain_fields | 6.5 |
| forest_place | task | terrain_fields | 1.7 |
| forest_meshes | group | forest_place | 0.7 |
| road_nodes | nodes | road_sweep | 0.6 |
| terrain_nodes | nodes | terrain_meshes | 0.5 |
| forest_nodes | nodes | forest_meshes | 0.5 |
| buildings_prepare / place / meshes / nodes | task/task/group/nodes | terrain_fields… | 0.1 / 0.2 / 0.5 / 0.1 |

Sum ≈ 20.4 s of stage wall time (mostly serial per the dependency graph; the windowed run
measured 1,016 frames, mean 16.7 ms, longest in-scene frame 69.2 ms — plan.org 516). Data
stages are pure arithmetic on `WorkerThreadPool` (DATA_THREADS = 4, loading.gd:130); node
stages make meshes/bodies on the main thread only, yielding under `NODE_BUDGET_MS = 8.0`
(loading.gd:135). **No stage reads the car's position**: the build is position-independent,
all chunks, once, in `CHUNK_ORDER` (loading.gd:67-77), then `_handover` swaps the Ring in
as the current scene (loading.gd:517-538). The fallback builds sync, honestly, never a
broken scene (loading.gd:89-97).

### 2.2 What is ALREADY chunked (stream-shaped, waiting for a scheduler)

- **Terrain near band**: 16,300 NEAR tiles (a tile is within 200 m of a covered road;
  50 m, 25 lattice cells each) cut into 1 km chunks — `CHUNK_M := 1000.0`, one
  `MeshInstance3D` per chunk (terrain_builder.gd:319-321); `mesh_jobs()` emits
  `Near_%d_%d` per chunk row-major over the 140×120 tile grid = **42 near chunks**
  (terrain_builder.gd:846-853, CHUNK_M/TILE_M = 20 → 6×7). Each chunk's data stage is a
  `MeshJob`, "a pure function of the fields, disjoint from every other job's"
  (terrain_builder.gd:444-461, 867-883); `add_job` adds it under Terrain
  (terrain_builder.gd:886-890). **The near band is already individually meshed and
  streamable without re-tiling.**
- **Forest**: the same 1 km chunking — `CHUNK_M := 1000.0` (forest_walls.gd:245-247),
  chunk keys `Vector2i(floori(x/CHUNK_M), floori(z/CHUNK_M))` (forest_walls.gd:1317-1318);
  per chunk one walls job, one trees job (baked per-chunk `ArrayMesh`, never a node per
  tree, forest_walls.gd:116-117, 476-514), one trunk body: ONE `StaticBody3D`
  ("Trunks_%d_%d") with ONE `ConcavePolygonShape3D` of every trunk's 12 triangles
  (forest_walls.gd:34-39) — **42 bodies for 19,379 trunks** (forest_walls.gd:40-41).
  Placement is budget-driven and position-independent: cards within 60 m of a covered
  road (forest_walls.gd:67), `CARD_WIDTH_M := 8.0` slots (159), tree ceiling
  `trees_per_span` = 1 per `tree_spacing_m` = 8 m of road per side (300-302, 464),
  budgets spent in file order (150).
- **Buildings**: `CHUNK_M := ForestWalls.CHUNK_M` (buildings_shells.gd:35), chunk keys per
  element + 1 km chunk (576), rails and solids the same (589); their bodies are built
  straight onto `PhysicsBubble.INACTIVE_LAYER` (628-629) and the node owns a `Bubble`
  fed bodies + boxes (668-671). Attached scene-free by `shells_watch.gd` on the
  node_added watcher pattern (shells_watch.gd:10-20).
- **Road**: one strip per covered road in `CHUNK_ORDER` (loading.gd:30-34), 3,314 covered
  segments / 3,304 swept (ring_drive_test.gd:81, 70), the loop's 92 segments
  (`LOOP_SEGMENTS`, ring_drive_test.gd:82).

### 2.3 What is ONE merged mesh (not streamable without splitting)

The Mid band (all 500 mid tiles, one `Mid` job), `Far` (none today — the core has no point
2 km from every road, terrain_builder.gd:29-31), `Water`, one `Band_<road id>` apron per
covered road, and the four `Continuation_` bands (terrain_builder.gd:854-863). The
continuation skirt reaches `CONTINUATION_MARGIN_M = 6000` m out (world_continuation.gd:61),
120,000 cells, 520 skirts, worst edge seam 7.2 mm (plan.org 501). These are the coarse
fill and the horizon: cheap relative to the near band, and they never need to stream.

### 2.4 The existing proximity mechanism (L2's precedent)

`PhysicsBubble` (scripts/physics_bubble.gd, FROZEN): per body, every physics tick, the
body's horizontal BOX within `ACTIVATE_M = 80` of the car goes on layer 1, past
`DEACTIVATE_M = 110` off to layer 0, hysteresis between (61-65, state machine 17-36). The
design properties L2 must copy: distance to the box not the centre (32-36); "no
allocation after attach, no RNG, no wall clock, no dependence on the frame rate: the state
after a tick is a function of the car's position and the state before" (38-46);
`update(at)` public so tests drive it by hand (46). Measured under FD_BUBBLE_PERF=1
(56-57).

### 2.5 The car's physics support chain (what must never stream away)

The car reads **exactly** two things: `WorldRoadProfile.sample_height` and the floor slab.

- The profile: the drape's 3,314 covered segments as typed roads, ~18,000 chords, ONE cell
  grid over them (~100,000 entries) "built once in from_data(), never lazily ... tens of
  milliseconds" (world_road_profile.gd:53-57, 487-488, 71); `_nearest_chord` answers the
  loop's right of way (30-42, 867-905). It is pure data — no nodes, nothing to retire.
- The floor slab: `FLOOR_SIZE_M = 40`, `FLOOR_THICKNESS_M = 0.1`
  (road_builder.gd:205-208), "the floor reads the SAME corrected profile the mesh was
  built from" (52-58), re-placed under the car every physics tick (499-503, 1338-1351).

And the decisive fact for streaming safety: **TerrainBuilder is VISUALS ONLY** — "no
collision shape, no body, no Area3D, nothing the car can read - the car stands on the
injected WorldRoadProfile and nothing here changes it (the ring drive test's output is the
same byte for byte)" (terrain_builder.gd:11-13). The forest meshes are visuals too; only
trunks collide, through the bubble (forest_walls.gd:14-16). The road's own strips keep
layer 2 and "never meet the car" (physics_bubble.gd:24-25). So every candidate streamed
element is visual; the car's ground cannot be unpainted under it.

## 3. The L2 design (all PROPOSED)

### 3.1 What stays resident, always

1. `WorldRoadProfile` and its chord cell grid — the car's ground everywhere, built once.
2. All road strip meshes + colliders — the driven path's surface; `ring_drive_test.gd`
   holds every loop-strip vertex to the field within 1 mm (ring_drive_test.gd:14-17,
   118-122), and the car may reach any covered road within seconds.
3. The floor slab — already follows the car (2.5).
4. The bubble and ALL its bodies (42 trunk bodies, rail/solid bodies) resident on layer 0 —
   they are the bubble's fixed input set; the bubble's contract ("after any jump ... the
   bubble around the new position is right at the next tick", physics_bubble.gd:44-46)
   requires bodies to exist before the car can reach them, and they are cheap.
5. The coarse fill: Mid, Far, Water, the per-road apron bands, the four continuation
   bands — the horizon and the ground under everything; one merged mesh each, small.
6. `terrain_fields`' per-node data (heights, distance, reach, cover, form, tile plan) — the
   pure-function source every streamed chunk job reads (terrain_builder.gd:384-406).

### 3.2 What streams, and the bands

The streaming unit is the **existing 1 km chunk** (42 terrain near chunks; the forest and
buildings grids use the same keys). No re-tiling is needed for the near band — the
brief's assumption that tiles are merged was stale; the seam already exists.

Bands around the car (start pose at handover, then every tick), radius on chunk BOX
distance, the bubble's own measure:

- `R_HANDOVER ≈ 2,000 m` — built before handover: near chunks + forest chunks + building
  chunks whose box is within it. Covers ~13 of 42 chunks on the 42 km² core.
- `R_BUILD ≈ 3,000 m` — streamed in after handover, nearest first.
- `R_RETIRE_IN ≈ 3,000 m / R_RETIRE_OUT ≈ 4,500 m` (slice 3, hysteresis, the bubble's
  80/110 ratio) — a chunk whose box passes out is freed; it rebuilds on approach.

Honest scale of the win, from the measured weights: road (6.7 s) + fields (2.3 s) +
forest_place (1.7 s) + buildings prep/place (0.3 s) are resident work that must finish
before handover regardless; the vicinity's share of terrain_meshes/forest_meshes/buildings
_meshes/nodes is roughly 2.5-3 s. Handover moves from ≈20.4 s of stage-sum to ≈13-14 s
(~1/3 earlier), and the remaining ~29 chunks (~4.5 s of worker time) stream while the car
already drives. **L2 v1's gain is time-to-handover, not memory** — everything stays
resident unless slice 3/4 retire it (Q2).

### 3.3 The mechanism

- **A streaming scheduler** on the watcher pattern (`shells_watch.gd`/`marks_watch.gd`
  precedent: autoload + `node_added`, never a builder edit) owning three decisions per
  tick, each a pure function of the car's position and the chunk state, no RNG, no wall
  clock — the bubble's determinism section copied verbatim as a requirement.
- **Build budget**: data-stage jobs on workers exactly as today (the loading scene's seam);
  node-stage adds on the main thread under the SAME `NODE_BUDGET_MS = 8.0` frame budget
  (loading.gd:132-135) — "a chunk's mesh a few ms" (loading.gd:134), so several adds fit
  a frame and no frame is ever held. The no-freeze canon is met by construction: nothing
  new runs on the main thread un-budgeted.
- **Lifecycle**: absent → data job (worker) → added (main, budgeted) → resident →
  (slice 3) retired (mesh freed, tallies kept) → rebuilt byte-equal on approach. Every
  transition logs through the FD_LOADING_FRAMES-style probe, never the suite's lines.
- **Determinism**: the data stages are pure functions of the checked-in files — "No RNG,
  no wall clock in any result; only the wall clock's order of thread completion differs"
  (loading.gd:76-77). A streamed build therefore produces byte-identical chunk data to the
  one-shot build BY CONSTRUCTION; what changes is order and timing. The pins move
  accordingly (3.5, slice 1).
- **Ordering**: the streaming order is (distance band from the car, then `CHUNK_ORDER`
  index) — deterministic for a given position, stable for tests. The one-shot sync build
  (every `_ready` path, every suite scene) is untouched: `build_deferred` stays false
  there and the scheduler never attaches.

### 3.4 The loading screen's 13 stages become base + vicinity + a silent tail

- Before handover: the same 13 stages, but the `*_meshes`/`*_nodes` groups cover only the
  base (resident set) + the vicinity (R_HANDOVER). `stages_report()` keeps its shape; the
  bar's weights re-split from the measured stage table (loading.gd:141-145).
- After handover: the remaining chunks build with **no bar** — the screen is gone; a debug
  probe line reports the tail. The handover contract "the car stands, the window answers,
  the world completes behind it" is the canon's own sentence, extended.

### 3.5 Why the frozen suite stays green

- **ring_drive_test.gd** (FROZEN) loads the scene directly and builds sync; the scheduler
  never attaches to a sync build. Its pins — drape sha (71), 3,314/3,304/92 (81-82, 70),
  mesh==field (14-17), the 2 km scripted drive with determinism to the bit (40-48) — read
  the profile, the floor slab, and road strips, all resident (3.1). Streaming visual
  chunks cannot enter its output.
- **The cert drives** are pad drives; the pad has no streaming (the scheduler keys on the
  Ring scene's Road/Terrain/Forest trio, as `shells_watch.gd:14` does). The 33-line cert
  base is untouched.
- **async_build_test.gd**: today it pins whole-graph equality at handover — digests
  Road/Terrain/Forest sync==async (252-268), children "the reference's names in the
  reference's order: CHUNK_ORDER held" (257-261), exactly 13 stages (277), bar monotonic
  to 100 % (286). L2 changes what is present AT handover, so slice 1 moves these pins
  honestly, once, in the open: per-chunk SHA-256 equality (each streamed chunk's arrays ==
  the one-shot chunk's, the async test's hash walk (380-414) reused per chunk), set
  equality at completion, the 13-stage pin re-scoped to the new contract, and the
  one-shot path re-verified unchanged. No old pin relaxed silently — the landing message
  carries the moved pins, as ROAD-6's did (async_build_test.gd:63-122 precedent).
- **The driver's data dir**: streaming writes nothing (builds are re-derivable pure
  functions; a disk cache is not in this design and would need its own ruling).

## 4. Constraints, named honestly

1. **The driven path is always covered** — guaranteed structurally: the profile + floor
   slab are resident and visuals-only chunks stream. A missing terrain chunk under the car
   changes no physics read; it shows a hole (see slice 3's stand-in for the retire case).
2. **No freeze ever** — C07BE6F1's exact words; met by the budgeted node stage and worker
   data stage, unchanged from LOADING-1's proven mechanism.
3. **Cert-frozen files untouched** — car.gd, road_profile*.gd, ring_profile.gd,
   surfaces.gd, physics_bubble.gd, visual_probe.gd, eifel_ring.tscn, the frozen tests:
   L2 touches loading.gd, the builders' job surfaces additively if at all, and new files
   (the scheduler, its test). world_road_profile.gd is frozen and needs no change — it is
   already position-independent and resident.
4. **Determinism of the Ring loads under streaming** — the async test's sync==async
   digest equality is the pin; L2 extends it per chunk (3.5). The streamed build's
   completion-time graph equals the one-shot's modulo child ORDER, which slice 1 re-pins
   explicitly; byte-equality per chunk is the stronger guarantee kept.
5. **Forest budget semantics**: tree budgets are spent in file order over the whole walk
   (forest_walls.gd:150) — streaming chunks of MESHES never re-runs placement, so budgets
   cannot drift. Placement stays one-shot; only mesh/node building streams.

## 5. Sliceable build order (each gate-testable, smallest first)

1. **Scheduler + per-chunk determinism, no behaviour change**: the loading scene gains the
   streaming scheduler but still builds and hands over everything; node adds may take
   proximity order with the one-shot order when the hook is off. New
   `tests/streaming_test.gd`: streamed==one-shot byte-equal per chunk at pinned car
   positions (the pit anchor + two core corners). async_build_test's order/set pins moved
   openly (the landing names every moved pin).
2. **Thin-base handover**: handover when base + R_HANDOVER vicinity stands; the tail
   streams under NODE_BUDGET_MS, no bar. Tests: handover happens with far chunks absent;
   a scripted 2 km drive over streamed ground reads the profile byte-identical (the
   ring_drive determinism argument, re-run on the async path); async test's stage/bar
   checks re-scoped.
3. **Retire path + hysteresis for forest + building meshes**: bubble-style
   R_RETIRE_IN/OUT, pure function of position, freed meshes rebuild byte-equal on return;
   bodies stay resident. Tests: drive away/back, chunk bytes equal first build; no count
   drift (describe() tallies are session totals; streamed/retired counters ADDITIVE only).
4. **Terrain near-band retirement with a 50 m stand-in** (only if Q2 rules for it): a
   retiring near chunk swaps to one Mid-style 50 m quad per tile built from the same
   fields (pure), so no hole shows; rebuild restores the fine mesh. The hard slice — new
   mesh data, new pins — gated on the driver's memory answer.
5. **Loading screen re-plumb**: stage names/weights re-scoped to base + vicinity, the
   silent tail documented, menu_test's sync pin (menu_test pins use_async_build false,
   loading.gd:117-119) and the async stage-count pin moved in ONE ruled landing.

## 6. Questions only the driver can answer

1. **Pop-in at handover**: when the thin base hands over, the first seconds show bare
   road + coarse terrain + vicinity dressing while the far half of the Ring builds behind
   you. How bare may those seconds look — is ~2 km of dressed vicinity enough, or should
   handover wait for a wider band (slower first metre)?
2. **Memory vs return pop-in**: keep every built chunk resident (no rebuild hitch ever,
   everything stays in RAM — the 2.77 M-vertex terrain bake plus the forest's baked
   meshes) or retire far chunks and accept a rebuild on return? The host has 12 GB free
   of 24; the honest trade is RAM against a possible hitch/pop at the retire boundary.
3. **The loading screen's fate**: once L2 lands, does the loading screen shrink to the
   base+vicinity seconds and vanish the moment the car can roll — or do you still want it
   held until a wider band is ready?
4. **Map overview**: while the loading screen lasts, should it show the Ring map / route
   (the GPS minimap's data is ready by then), or stay the plain progress bar?
5. **Side-road strips**: the loop's road meshes stay resident forever. May the 3,212
   covered side roads' strip meshes stream too (the profile answers their ground either
   way), or is every road's mesh resident, period?
