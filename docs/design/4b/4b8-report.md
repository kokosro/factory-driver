# 4B-8 — buildings, furniture and village streets

Worktree implementation on `main`, based on `14ca646`; no commit or push.
This report records the offline inputs, measured placements, constraints and
verification for review. The existing scene and all 26 frozen files compare
byte-for-byte with HEAD. No test step or verdict marker was added: the suite
still has 32 test steps and 34 markers. Pre-existing untracked files were left
alone.

## Derived data

`tools/world/buildings.py` reads the supplied local q5/q6/q7 answers, verifies
all three answer hashes against their manifest, and writes sorted, compact,
UTF-8 JSON with mm-rounded coordinates and no generation timestamp.
`landcover.py` supplies the existing exact port of SkeletonLoader's projection.
A second derivation compares byte-identically with the checked-in output.

`landcover.json` deliberately omitted residential areas in 4B-7. The new
reduction recovers the 151 residential ways from q4 part 1, using the existing
`outer`/`inner` ring schema, and the six named place nodes from q4 part 6.
Twelve residential polygons intersect an 800 m disc around a named place;
buildings qualify when their area centroid lies inside one of those polygons.
Grandstands additionally qualify within 800 m of a place or the Nordschleife.
Both supplementary q4 files and the skeleton/drape/catalogue rule inputs carry
hashes in provenance. The original landcover file is unchanged.

| Footprint class | Count |
|---|---:|
| B0 house | 2,828 |
| B1 barn/farm | 1 |
| B2 church | 6 |
| B3 castle | 1 |
| B4 grandstand | 3 |
| B5 industrial/warehouse | 0 |
| Total | 2,839 |

There are 750 mapped F4 poles. Recorded, unplaced barrier ways: 75 guardrails,
99 fences, 123 walls and 2 retaining walls. The q5 source contains 12 grandstands;
three meet this pass's village/loop proximity rule.

The castle is way **31010481**, its original 16-point closed ring (15 unique
corners), area centroid **(2395.277, -2184.475)** region metres, extruded **20 m**.
The placement tolerance in the test is **5 mm**.

Provenance discrepancy: the castle answer matches manifest SHA-256
`154f58c0186b74ee0ae92bc24890117271efb9d1b9c9ae0a51d9e6ef569d57d8`.
The on-disk q7 query hashes to
`50cf4a8311d827ed320fadf55f8efe35c21a80597604eaebabdc32d7077d8350`, while the
manifest records
`4dc5e26b53a7567545be4abf7de2fffc81e3c50a694c59623e072ed0771e5e48`.
Both are preserved, with an explicit mismatch flag. q5/q6 individual query
hashes are calculated from their pinned `.ql` files; their manifest supplies
the aggregate query hash. No network request or raw-store write was made.

## Economic shells and construction

All **22** Buildings records have one shell: **9 B6**, **9 B7**, **2 B8**, **2 B9**.
The E1 and E3 records sharing the Porsche site's OSM way remain two records and
two shells, as requested. Positions are Record.position(), except E11's offset.

- B6: catalogue **12 × 8 m**, four posts, canopy slab/colour band, kiosk;
  six boxes / 72 triangles, with open space below the canopy in collision too.
- B7: catalogue **15 × 10 m**, closed hall, shallow roof, roller-door panel.
- B8: catalogue **20 × 12 m**, shallow-roof hall, dark blue-grey glass front.
- B9: pitched roof, no chimney, sign quad. E8 uses projected record bounds
  (approximately **13.383 × 7.972 m**). E11 has no recorded building footprint:
  it uses half the B6 footprint, **6 × 4 m**, explicitly a booth proportion.
- E2.1, node **12023011572**, remains at **50.3780403, 6.9492187**:
  approximately **(2187.984, -5674.748)** in region metres.
- E11 moves **8 + 4 × hash_unit(osm, "booth_offset") m** along the vector away
  from the nearest R17 centreline point. Measured displacement **8.990336 m**,
  final position approximately **(2056.356, -1183.639)**. No record is edited.

Village heights are `building:levels × 3 m`, default two levels. Roof pitch
comes from B0's catalogue default, 45 degrees; barn and hall pitches are lower
proportions. Churches have nave, tower and pointed spire; grandstands have tiers
and a roof plane. Houses use pale render/ochre and slate-grey roofs, the castle
pale stone. Heights outside the DGM lattice use **WorldContinuation**, matching
Terrain rather than placing Adenau's northern buildings at y=0.

There is a genuine footprint/budget conflict: detailed OSM outlines can require
more than B0's **60 triangles** even before adding a roof and chimney. The data
retains every original point. **55 B0 outlines** lose least-area corners only
until the actual two clipped roof halves, walls and chimney fit 60 triangles.
The worst measured source-vertex displacement to the simplified boundary is
**7.988 m**, on way **533644057**. All other footprints are retained. This is an
explicit geometric approximation, not an exact extrusion claim for those 55.

The catalogue specifies no numeric RGB colours, post sections, canopy thickness,
spire proportions or booth dimensions. These are documented proportional asset
construction in the builder, derived from the catalogue footprints, R15's kerb
height and the brief's 3 m storey. No new catalogue values were inserted. This
is a flat-colour shell pass: no raster textures are allocated, and mesh texture
metadata truthfully reports 0 pixels within the canon's budgets.

## Furniture and streets

| Placement | Count |
|---|---:|
| F1 posts, both sides of the 92-segment Nordschleife | 10,392 |
| F1 folded beam bays | 10,392 |
| F4 mapped poles with crossarms | 750 |
| F9 delineators, with reflector quads | 984 |
| Adenau residential segments with R15 kerb strips | 46 |
| F15 parked cars | 17 |
| Parking ceiling for qualifying complete 100 m slots | 32 |

F1 post phase carries across OSM segment boundaries, every **4 m** of loop
chainage; the final closing bay is shorter. Each bay has six beam triangles and
two post triangles, exactly the catalogue's eight-triangle budget. Mitres join
segment ends; both sides remain continuous. Sampled straight post positions and
chainages pass the **4 m ± 5 mm** check.

F4 follows the explicit mapped-node instruction; there is no invented 50 m
fallback population. F9 uses the catalogue's **50 m** spacing, **1 m** height,
hash-staggered ±10 m stations, both sides of primary/secondary roads outside
residential polygons. The existing RoadBuilder right-of-way pass omits some
grade-separated roads: runtime F9 is 984, versus 988 before that ruling. The
Python count audit selects the corresponding B-road underpasses geometrically
by differing layer and centreline crossing; it does not replace the runtime's
height-based ruling.

R15 is a visible **0.12 m** edge strip on both sides of qualifying Adenau
residential segments (sample **103880915-0**). Selection is by centreline chord
midpoint within 800 m; boundary chords are kept whole. The road cross-section
itself remains RoadBuilder's responsibility. This deliberately records the
brief's exception to the library's "no separate mesh" wording.

Parking is hash-chosen 0–2 cars per complete 100 m road slot in Adenau, catalogue
mean 1; none elsewhere. Cars are unbranded two-box silhouettes, aligned with the
road, visually simpler than the hero.

**No furniture or village building has collision.** Only the 22 economic shells
supply solids. F1 collision remains queued for the driver's ruling: the frozen
bubble drive crosses one rail on its way from the centreline to the tree. Rails
are retained continuously as visuals; no segment gap is needed for the drive.

Skipped explicitly: **F14** (no recorded run-off spots), **F10** (board reuse
unresolved), **F2/F3/F5/F6** (no additional placement/assets authored; optional
city-limit signs left out). **Eifelstadion way 429774835** is absent from the
supplied answers, so no footprint/tier was invented for it.

## Clearance evidence

The Python audit measures q5 footprint boundaries, not only centroids:

| Measurement | Result |
|---|---:|
| Buildings within 120 m of grass spot (6120, -2640) | 0 |
| Nearest footprint to grass spot | 315.948 m |
| Buildings within 15 m of approach segment 683303211-0 | 0 |
| Nearest footprint to approach segment | 44.217 m |
| Nearest recorded OSM guardrail to any skeleton raceway | 1.528 m |
| Nearest recorded OSM guardrail to the Nordschleife | 2.015 m |

The supplied claim that all OSM guardrails were at least 2 km from the raceway
is false for these answers. The closest-to-loop way is **472070092**. Placement
still follows the requested rule rather than these OSM barriers.

The new solid footprints are at least **105.559 m** from the bubble tree drive
line extended 10 m past the tree, and **1,697.080 m** from a conservative 300 m
northward off-road corridor beginning at the grass spot. Both exceed the
requested 2 m clearance. The visual F1 has **one** intersection with the tree
approach; its collision-free status is deliberate and tested through the frozen
drive tests.

## Wiring, pins and validation

`ShellsWatch` follows the existing deferred `node_added` watcher pattern.
`BuildingsShells.of()` is idempotent, attaches `Buildings` as a scene-root child
before its own work, and is also called by LoadingScreen before the Ring enters
the tree. The direct path builds in `_ready`; the async path claims the node
and runs prepare, place/group, mesh jobs and budgeted main-thread node creation.
Furniture is folded into this builder to minimise new files.

The final builder has **227 visual chunks**, **12 solid chunks**, **240 children**
including Bubble, **586,254 vertices** and **195,418 triangles**. Each solid chunk
has one StaticBody3D and one backface-enabled ConcavePolygonShape3D. PhysicsBubble
receives the road's car and chunk bounds; without a car the bodies remain layer
0. No node is added underneath Terrain/Road/Forest.

Pins extended, additively:

- Async stages: **9 → 13**; compared builders **3 → 4**. Describe/counts,
  child order, every mesh array and every collider face are compared for
  Buildings too; its two chunk stages have **239 jobs** each. The frame ceiling
  remains **250 ms**, and cancellation/fallback/handover checks remain.
- Buildings data: **no footprint dataset → 2,839**, with the class, pole,
  residential and place counts above; malformed-ring/class/count/duplicate
  fixtures added. All original 22-record constants remain unchanged.
- Dressing: **no Buildings checks →** placements, catalogue dimensions,
  canopy composition, castle centroid, B0 budget, bubble wiring, continuation
  height, rule-count pins, rail spacing/budget, actual kerb height, parking
  ceiling, texture metadata, clearance and second-scene determinism.
- Existing Road digest **af1cd69f426516cc**, Terrain **5c5ee1f6ba4d1b4a**,
  Forest **3241b4b76c9e000a** remain unchanged. Buildings' digest is
  **c91220c9e775c1da**, identical between independent sync/async builds.

All required tests are invoked individually after an import, with logs and
FD_DATA_DIR directed into a temporary directory inside the repo. The frozen
bubble and off-road tests are also run. Godot launches successfully, but the
sandbox emits a native `get_system_ca_certificates` error on runtime startup;
import additionally cannot save the user's external Godot editor settings.
These are environment errors: a clean `run_tests.sh` gate (which rejects any
engine ERROR line) must be verified by the orchestrator outside this restriction.
No application data is written to the user's factory-driver directory.

Final verification results (all individual processes exited 0; native sandbox
errors above remain, so these are assertion results):

| Test | Result |
|---|---|
| config | PASS (3 assertions) |
| element_catalogue | PASS (457 assertions) |
| skeleton | PASS (171 assertions) |
| world_profile | PASS (154 assertions) |
| buildings | PASS (116 assertions) |
| dressing | PASS (138 assertions) |
| async | PASS (17 assertions) |
| bubble | PASS (17 assertions) |
| offroad | PASS (36 assertions) |

Import completed and registered the scripts without GDScript errors; it also
exited 0, with the native certificate/editor-settings errors described above.
The final async/dressing scripts also pass `--check-only`. Python derivation
repeated byte-identically; `git diff --check` is clean. The full suite was not
run, and no claim is made that its strict engine-error gate passes here.

Derived file: **917,644 bytes**, SHA-256
`6ce807725f0b8a2216527b8225bc1d7026880891cc68e705d791d803dde1d087`.

## Files

Created:

- `data/regions/eifel_ring/buildings.json`
- `tools/world/buildings.py`
- `scripts/buildings_shells.gd` and its generated `.gd.uid`
- `scripts/shells_watch.gd` and its generated `.gd.uid`
- `docs/design/4b/4b8-report.md`

Edited:

- `project.godot` — ShellsWatch autoload
- `scripts/loading.gd` — claim Buildings and run four additional stages
- `tests/buildings_test.gd` — derived-data validation and count pins
- `tests/dressing_test.gd` — additive shell/furniture/clearance checks
- `tests/async_build_test.gd` — fourth builder, thirteen stages, digest history

No changes to `scripts/buildings.gd`, `tests/run_tests.sh`, the scene, catalogue,
skeleton, drape, physics/car/profile scripts or frozen tests.
