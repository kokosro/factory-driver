# FACTORY DRIVER — 4B IMPLEMENTATION PLAN: SMALL GATED ITERATIONS (design, 2026-09-23)
# Status: 4B-PREP design package, documents only. Nothing here is built yet.
# Rule of order (the driver): "once we build the elements it will be easier to procedural generate
# the world from data" → LIBRARY before PIPELINE before WORLD.

## 0. THE PATTERN EVERY ITERATION FOLLOWS (docs/night-shift-3.md, "METHOD")

- One orchestrator + one external claude_code/codex job per iteration; small scope; a commit each.
- Double gates: `./tests/run_tests.sh` twice, byte-identical output (modulo the documented
  pid-path artifact), plus `./tests/run_tests.sh --parallel`, plus an independent re-run on a
  `git archive HEAD` copy (tests/README.md), then push.
- Tests additive-only; no check weakened; every changed expectation cited "was ->"; certs
  byte-locked: SLALOM 28.65 / SPIN_180 15.95 / SPIN_360 18.07 / STOP_BOX 8.72 / REVERSE_180 7.72
  (the suite's `metrics:` lines). Headless only: never `./run.sh`, never the editor.
- The suite today: 13 steps after the import, 1292 "  ok " lines (self-check at the end of this
  package). Every iteration below adds a step or extends one; the count only grows.
- Definition of done is verifiable with `./tests/run_tests.sh` alone.

## 1. THE ITERATIONS

### 4B-1 — Element data model + in-repo element catalogue
- Goal: the library of element-library.md as DATA the game can load: ids, family, priority, canon
  line, stone parameters, varying parameters with ranges, texture budget. No meshes yet.
- Files: NEW `scripts/element_catalogue.gd` (static data + `entry(id)`, `by_family`,
  `validate()`), NEW `configs/elements/*.json` (one file per family R/T/S/B/E/V/F) with
  `configs/validation.gd`-style checks, NEW `tests/element_catalogue_test.gd`, `tests/run_tests.sh`
  gains the step. README's test table gains a row.
- Tests (additive): every id unique and of the documented form; every entry cites a canon line
  (non-empty `canon`); every varying parameter has a range and its default inside it; priorities
  1-9 only; the E-table's privilege names are from the fixed vocabulary; `validate()` on a broken
  fixture reports the field. Count: ~60 entries × 5 checks ≈ 300 ok lines.
- DoD: the new step prints "  ok" for every entry; suite twice byte-identical; certs untouched.

### 4B-2 — OSM extraction + skeleton for the Ring bbox
- Goal: the offline extract → project → skeleton stages (data-pipeline.md §2-4) as a script outside
  the engine, and the small checked-in Ring skeleton the engine can read.
- Files: NEW `tools/world/extract_osm.py` (the q1-q6 queries, snapshot naming),
  NEW `tools/world/skeleton.py` (project EPSG:25832, split at junctions, DP 0.3 m, widths by class),
  NEW `scripts/skeleton_loader.gd` (reads skeleton.json into typed segments/junctions),
  NEW `data/regions/eifel_ring/skeleton.json` (≤ 1 MB; else generated and git-ignored — open
  question 4 of data-pipeline.md), NEW `tests/skeleton_test.gd` + step.
- Tests (additive), on the checked-in sample (docs/design/4b/samples/) and on a synthetic 5-way
  fixture: projection round-trip error < 0.01 m at the origin and < 0.5 m at 20 km; every
  junction has ≥ 2 segments; DP keeps every node with heading change > 1°; widths by class match
  the table; relation 38566's members close into one loop (first point == last point within
  0.5 m); total loop length within 1 % of 20 830 m; the snapshot id is present and pinned.
- DoD: skeleton_test ok; no network in any test (the extract script is not run by the suite).

### 4B-3 — Elevation drape + terrain
- Goal: DGM1 tiles → mosaic → heights along the skeleton and a terrain lattice (data-pipeline.md
  §5); the Karussell decision tree run and recorded.
- Files: NEW `tools/world/drape.py` (rasterio/GDAL; bilinear; crossfall; bridge/tunnel rules;
  crest/dip labels), NEW `scripts/world_road_profile.gd` (see §2 below: a RoadProfile subclass
  backed by the draped skeleton), NEW `tests/world_profile_test.gd` + step, `data/regions/eifel_ring/
  drape.json`. ring-region-decisions.md §3 gets its "was ->" if the Karussell tree picks (b) or (c).
- Tests (additive), on a synthetic 3 × 3 km height fixture with a known plane and a known bowl (no
  DGM1 in the suite): `sample_height` reproduces the plane within 1 mm; the gradient of the plane
  is its slope to 1e-4; bilinear continuity across tile seams (no step > 1 mm); a bridge deck is
  linear between abutments; a crest label appears where the fixture's curvature says. On the real
  drape file (if checked in): Breidscheid sample within 320 ± 5 m, Hohe Acht within 620 ± 5 m.
- DoD: world_profile_test ok; `RoadProfile.flat()` and the pad's profile untouched (road_profile.gd
  frozen); certs untouched.

### 4B-4 — Drivable road assembly on the real centreline (alongside the pad)
- Goal: the Nordschleife as a drivable road in a NEW scene, from R17/R9/R18 elements swept along
  the draped skeleton; the car driven on it headless. The pad, main.tscn and every cert stay.
- Files: NEW `scripts/road_builder.gd` (sweep a cross-section along a spline: strip mesh + collision
  from the profile), NEW `scenes/eifel_ring.tscn` (WorldEnvironment, Sun, the built road, the car
  with `road_profile = WorldRoadProfile`), `Garage.MAPS` gains the entry and `_free_drive` learns to
  change scene (the honest "not built yet" push_error becomes the change: "was -> "), NEW
  `tests/ring_drive_test.gd` + step.
- Tests (additive): the mesh's vertices lie on `sample_height` within 1 mm; the scripted driver
  (HandlingTests' cruise steps) drives 2 km from Döttinger Höhe without leaving the paved width;
  the hill step is non-zero on a 5 % stretch and exactly zero on the flat pad (the byte-lock
  argument of §2); determinism: two runs' odometer and final position identical to the bit.
- DoD: ring_drive_test ok; the 13 existing steps byte-identical; certs 28.65/15.95/18.07/8.72/7.72.

### 4B-5 — Typed buildings + privileges data model
- Goal: the E-table as data with the privilege vocabulary put in stone; the Ring's nine stations,
  nine workshops, two dealerships, the test centre, the office placed from the region file.
- Files: NEW `scripts/buildings.gd` (typed record: shell, privileges, demand, owner; `can(privilege)`),
  NEW `data/regions/eifel_ring/focus.json` (the region table of ring-region-decisions.md), NEW
  `tests/buildings_test.gd` + step; B-shell placeholder meshes (boxes with the canon's recipe).
- Tests (additive): exactly 9 E2 in the Ring file, exactly 1 social (deterministic pick by seed,
  same id every run); every E1 has `build_cars`; no E1 has `sell_fuel` unless the file says so;
  the E11 sits within 50 m of way 26543901's first node; every E-record's shell is a B-id in the
  catalogue; an unknown privilege name is refused with the reason.
- DoD: buildings_test ok; nothing in the car or the pad touched.

### 4B-6 — First-run map UI (spawn pin → test centre → voucher → first car)
- Goal: first-run-flow.md, steps 1-3 and 6-8, on the garage's menu patterns; world.json.
- Files: NEW `scripts/world_map.gd` + `scenes/world_map.tscn`, NEW `scripts/voucher_ledger.gd`,
  NEW `scripts/world_store.gd` (world.json; `DataDir.SEEDED_FILES` += "world.json"), NEW
  `configs/cars/fd_1001.json` (serial-number car; validation passes), `garage.gd` gains the "World
  map" row and the dealership row (additive rows; `page_rows` shape unchanged), NEW
  `tests/first_run_test.gd` + step; menu_test.gd's overflow walk extended to the new layer
  (additive checks, the 1280 × 720 rule of 4A.1).
- Tests (additive): a fresh world.json → the map opens first; pin in the Ring bbox lists the one
  centre; choosing it writes spawn_region/test_centre and places the car in the yard; driving the
  L0 sitting through the manager as licence_test does grants L0 AND one unspent voucher, once
  (a practice run adds none: "was -> " none needed, `licence_changed` fires once); the rental
  refuses the aid switches and the eco lock holds; taking the car adds `fd_1001` to cars.json
  with defaults and marks the voucher spent; every new surface fits 1280 × 720.
- DoD: first_run_test ok; licence_test.gd byte-identical (the FROZEN semantics untouched).

### 4B-7 — Dressing pass 1: terrain forms, forest masses, sky and haze on the Ring
- Goal: T1-T9, V4/V7, S1/S5 assembled from the region file; the first canon-true screenshot
  candidate ("a silver 911 entering a long sweeping mountain curve. Dark pine trees frame the road").
- Files: NEW `scripts/terrain_builder.gd`, `scripts/forest_walls.gd`, `scripts/sky_set.gd`; the
  ring scene gains them; NEW `tests/dressing_test.gd` + step.
- Tests (additive): lattice spacing by distance band as specified; V4 walls only within 60 m of a
  q1 road; haze bands at 100/300/800 m (fog curve sampled); object count within 500 m of the car
  on 10 sampled Nordschleife points ≤ the region's ceiling; no element outside the catalogue.
- DoD: dressing_test ok; ring_drive_test byte-identical (dressing adds no physics).

### 4B-8 — Dressing pass 2: buildings, furniture, village streets
- Goal: B-shells from footprints, F1 guardrails on R17, F4/F9 spacing, R15 kerbs in Adenau.
- Files: NEW `scripts/furniture_builder.gd`, `scripts/building_shells.gd`; tests extended.
- Tests (additive): guardrail posts every 4 m along R17 within 5 mm; the Nürburg castle B3 at
  way 31010481's centroid; parked-car count ≤ ceiling; texture sizes within the canon's budget
  table (asserted on the resources' metadata).
- DoD: as 4B-7.

After 4B-8 the Ring is "put in stone" as ring-region-decisions.md says; 4C begins the continent
skeleton (Geofabrik pbf), cats, troc.

## 2. GRAVITY-ON-SLOPES SCOPING (design only in 4B-PREP; built in 4B-3/4B-4)

### 2.1 What slope behaviour the world needs
- Grade resistance on climbs: m·g·sinθ against the drive (Steilstrecke, the road up to Nürburg,
  the 18 % Flugplatz → Hohe Acht stretches: docs/nordschleife-data-sources.md §1).
- Gravity pull + engine braking on descents (Fuchsröhre 11 %): a car in gear slows by engine
  braking, in neutral it runs away; the brakes' thermal model (already real) sees the extra work.
- Weight transfer on grade: on a slope the static axle loads shift by m·g·sinθ·h_cg / wheelbase;
  the car's four springs already produce this from the corner heights (`_corner_forces`,
  car.gd:4871) when the road under each wheel is at its real height.
- Hill start: the existing precedent (the 8 % ramp, licence_exams.gd:552 `hill_start_element`,
  road_profile.gd:149-172): handbrake + clutch bite, roll-back tolerance 0.15 m.
- Crests and dips: lift-off and compression from `sample_height` per wheel: already how the car
  reads the pad's swell and the test dip (road_profile.gd:9-25).
- Cross-slope (the Karussell bank, superelevation): lateral gravity share into the corner; the
  bank holds the car in.

### 2.2 The injection seam (car.gd untouched)
The car reads the road ONLY through the injected profile:
- `@export var road_profile: RoadProfile` (car.gd:2818) — main.tscn hands the pad's resource to
  both the pad and the car (scenes/main.tscn:46 and :56).
- Height under a wheel: `_road_height_under_wheel` → `road_profile.sample_height(contact.x,
  contact.z)` (car.gd:4692-4696).
- Gradient under the centre: `_ramp_gradient` → `road_profile.ramp_gradient(global_position.x,
  global_position.z)` (car.gd:4679-4682), `Vector2.ZERO` without a profile.
- The hill step of the tick (car.gd:4130-4144, header 90-98): with a wheel on the road
  (`carried > 0`), `pull = -total_mass() * _gravity`, added along the car (`pushing`) and across
  (`right_force`) as `pull * (grade · dir)`; "Off the ramp the gradient is exactly zero and
  nothing is added"; in the air nothing (3AC).

So a NEW `WorldRoadProfile extends RoadProfile` (4B-3) overriding `sample_height(x, z)` (bilinear
on the draped skeleton + terrain lattice) and `ramp_gradient(x, z)` (the surface gradient of that
height field: central differences over 1 m, the shape of `elevation_slope`, road_profile.gd:339)
delivers every behaviour in §2.1 through the existing calls. `elevation_height` and
`elevation_mask` are overridden too so anything drawn from the profile draws the world. Nothing
in scripts/car.gd changes; nothing in scripts/road_profile.gd changes.

### 2.3 Why the flat-track certs stay byte-locked
- On the pad the profile is the pad's `RoadProfile`, not the subclass: `ramp_gradient` returns
  `Vector2.ZERO` everywhere but the licence ramp (road_profile.gd:295-312), and the ramp is 44 m
  clear of every certified feature (road_profile.gd:160-164; tests/licence_test.gd's
  `CERTIFIED_POINTS` asserts zero at each). The hill step adds nothing; every existing check sees
  the physics it saw.
- `MAX_SLOPE 0.015` (road_profile.gd:96) documents the pad's gentle-slope assumption (1.5 %) under
  which "the springs push straight up and gravity never pulls the car downhill" (car.gd:90-93)
  is an honest approximation. The world profile EXCEEDS it explicitly (Fuchsröhre 11 %, short
  27 %): there, `ramp_gradient` is non-zero everywhere and the hill step carries gravity's full
  along-slope and across-slope share; the small-angle body attitude (car.gd:87-90, "pitch and
  roll are small angles") is the remaining approximation to review in 4B-4's test on the 18 %
  stretch (expected: fine to ~20 %, since sin 11° = 0.19 and cos = 0.98).
- Airborne (3AC/3AD) is unchanged: the hill step is gated on `carried > 0`.
- The test that pins it: 4B-4's "hill step is exactly zero on the flat pad" plus the existing
  suite byte-identical.

### 2.4 The DGM1 dependency
Slope truth comes from the drape (4B-3). Without DGM1 tiles the world profile falls back to the
skeleton's flat heights (0 gradient everywhere) and the suite still passes on synthetic fixtures;
the real slopes are only asserted where the drape file is present. SRTM-30 is the fallback
outside Rheinland-Pfalz (recorded §1); its 30 m grid gives gradients too coarse for the hill step
to be honest below ~50 m wavelength: to be documented per region, never smoothed into a fake.

## 3. RISKS AND WHAT WE WILL NOT DO
- Godot single-precision at 20 km: the region origin (data-pipeline.md §3) keeps it to mm.
- Mesh count: the lattice bands cap it; the canon's "twenty meaningful objects" is a test (4B-7).
- No check weakened for the world: if the Ring's slopes expose a body-attitude limit, the fix is
  in car.gd with its own iteration, was-> cited, certs re-baselined honestly as 3AA did.
- No network in the suite, ever; no GUI; no editor.

## Open questions
1. 4B-2's skeleton in the repo (≤ 1 MB) or generated: decides whether 4B-3's real-drape asserts
   run in the suite or only locally.
2. The change-scene path in `Garage._free_drive` (4B-4): a plain `change_scene_to_file` loses the
   car's state; is the car re-instanced from cars.json (the store already has everything but the
   parking spot: "Not kept yet: where the car was parked", odometer_store.gd:23)?
3. Where the rental's aid lock lives: a second reason in `LicenceManager.allows`, or a separate
   gate object on `ArcadeCar.licence_gate` (the car accepts any object with `allows`)?
4. The body-attitude small-angle limit on 18-27 % grades: measure in 4B-4 before deciding whether
   car.gd needs an iteration.
5. Is one external job per iteration still right when 4B-2/4B-3 are Python tooling rather than
   GDScript (the gates are the same, the reviewer's expertise differs)?
