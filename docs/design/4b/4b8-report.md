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


## ROAD-7 / F1-COLLISION-1

This addendum supersedes the original visual-only F1 decision above. Both
rails now stand **1.5 m beyond pavement**, retaining R15's own kerb widths.
Ten probes on the frozen tree-approach straight, 1 m beyond pavement, classify
**grass/gravel** through unchanged `Surfaces`; every post's chord-normal
projection is 1.5 m from its paved edge within 3 mm, including mitres.

The exit table is derived from skeleton junction membership and drape coverage,
not just runtime swept side roads. Every covered side road at least 5 m joining
the loop qualifies. All openings are centred at the junction's loop chainage,
with **12.2 m minimum** (the extra 0.2 m allows for post/beam thickness).

**Measure the approach, not just the shared node.** The initial minimum-width
openings left 34 rail/approach-centreline intersections, including fuel access
about 13 m before its node. The builder now surveys the ungapped 4 m bays;
for each approach, any bay within its paved half-width plus 0.1 m expands the
centred opening to enclose that bay's chainage, with another 0.1 m at the end.
The local search bound follows the side segment's own length and road widths.
There is no hand-authored exit-width table. The resulting openings span
**12.2–109.851 m**; 44 junction openings union to **43 disjoint gaps**.
Tests check the remaining rail bays clear every approach's paved strip, in
addition to checking the required centred 12 m and absence of gap geometry.

The shallow pit approach `199642470-0` contains the frozen spawn
`(2037.199, -1355.401)` within 0.000288 m of its centreline. Its loop projection
is 12,982.181 m, **25.254 m before junction 312821860**. The initial minimum
opening left a rail through that spawn, shifting it 0.669 m in the reset
test. The geometry-derived **103.070 m** centred opening clears the whole
approach's rail overlap, including the spawn; no scene change or additional
visual-only exception is needed. Fuel access receives **42.400 m**.

### Exit table

| Junction | Loop chainage (m) | Covered side segments | Centred opening before union (m) |
|---|---:|---|---:|
| 1714130368 | 5066.951 | 198509975-0 | 54.103 |
| 2083242424 | 14387.687 | 696037724-0 | 39.574 |
| 2084149822 | 12641.561 | 769107217-1 | 12.200 |
| 2084199510 | 19612.689 | 696037709-0 | 41.579 |
| 2084302010 | 3613.575 | 159310586-0 | 12.200 |
| 2084978602 | 6969.269 | 696037694-0 | 18.739 |
| 312821860 | 13007.435 | 199642470-0 | 103.070 |
| 344791325 | 11129.635 | 42746353-0 | 52.930 |
| 4663077364 | 16615.139 | 1391805017-0 | 14.478 |
| 6535972613 | 8697.096 | 1391805024-0 | 34.393 |
| 6535972624 | 8431.501 | 1391805023-0 | 23.202 |
| 6535972634 | 8077.484 | 830373792-0 | 35.168 |
| 6535972644 | 7506.583 | 1391805022-0 | 29.365 |
| 6535972646 | 7341.312 | 696037693-1 | 18.824 |
| 6535972651 | 6800.314 | 696037695-0 | 32.828 |
| 6535972663 | 6377.571 | 1391805020-0 | 35.341 |
| 6535972673 | 5490.570 | 1391805019-0 | 61.339 |
| 6535972688 | 4964.552 | 1391805018-0 | 33.304 |
| 6535972704 | 2993.835 | 696037703-0 | 67.870 |
| 6535972707 | 2356.130 | 696037704-0 | 24.459 |
| 6535972710 | 1287.902 | 696037705-0 | 48.004 |
| 6535972721 | 525.081 | 696037706-0 | 26.363 |
| 6535972727 | 20678.305 | 696037708-0 | 36.810 |
| 6535972733 | 18914.072 | 696037710-0 | 28.344 |
| 6535972745 | 18593.288 | 829601966-0 | 26.775 |
| 6535972774 | 17691.040 | 696037713-0 | 30.279 |
| 6535972784 | 17085.701 | 829600699-0 | 35.601 |
| 6535972789 | 16852.176 | 696037715-0 | 24.551 |
| 6535972812 | 16448.401 | 1391805016-0 | 49.002 |
| 6535972816 | 16018.102 | 696037719-0 | 68.403 |
| 6535972819 | 15722.446 | 696037720-0 | 45.092 |
| 6535972824 | 15067.407 | 696037722-0 | 31.014 |
| 6535972832 | 14829.009 | 696037723-0 | 42.218 |
| 65385874 | 12549.324 | 31009283-0 | 82.847 |
| 65385895 | 12625.956 | 31009257-0 | 28.288 |
| 65385912 | 12735.477 | 27852583-0, 769107218-0 | 41.245 |
| 65385942 | 12877.100 | 26543901-0 | 42.400 |
| 65386397 | 15637.853 | 420556741-0 | 27.905 |
| 65387218 | 107.818 | 159310267-0 | 31.836 |
| 65387230 | 143.893 | 1549311960-0 | 31.987 |
| 65391140 | 5368.062 | 696037699-0 | 56.324 |
| 65391385 | 6540.610 | 1391805021-0 | 33.421 |
| 65391925 | 9858.062 | 68276602-0 | 12.324 |
| 65392139 | 11406.826 | 42746353-4 | 109.851 |

**Fuel-station access is junction 65385942 / 26543901-0**, centred at
12,877.100 m. The remaining rail does not cross its approach's paved strip.
There are posts at both edges on both sides of every merged opening
(**172 terminal positions**); no post or beam bay spans an opening.
Overlapping openings are unioned, and loop-seam openings are handled cyclically.

### Re-measured clearance

Measurement preceded collision enablement. The full relocated visual rail still
crosses the tree approach exactly once, on its negative side at chainage
9,912–9,916 m. The tree corridor starts at `683303211-0`'s first point, goes
through `(4469.06, -2744.16)`, and extends 10 m beyond it. The offroad corridor
is the conservative 300 m line `(6120, -2640)` → `(6120, -2940)`.

Only the **five negative-side bays from 9,904 to 9,924 m** remain visual-only,
with their four interior posts. Both terminal posts remain solid. This is
`683303211-0` local chainage **12.160–32.160 m**; all other outside-gap F1
posts and bays are solid. The exception is explicit in the builder and pinned
in the existing dressing test. Clearance tests measure every projected edge
of the actual collider triangles (including folds and post width), not chunk
boxes or only placement centres.

| Geometry | Tree corridor | Offroad corridor |
|---|---:|---:|
| Economic shells (original 4B-8 boundary measurement, rechecked) | 105.559 m | 1,697.080 m |
| Relocated full visual rail, before exception (placement lines) | 0 m; one crossing | 1,029.828 m |
| Final solid rail collider faces | 2.368849 m | 1,029.782349 m |

Rail solids reuse the economic shells' chunk path: **21 rail chunks**, one
layer-1 `StaticBody3D` with one backface-enabled `ConcavePolygonShape3D` each,
controlled by the existing Buildings `PhysicsBubble`. No car means layer 0;
within 80 m of the body's box it activates on layer 1, beyond 110 m it
returns to layer 0. Tests exercise both transitions on all rail chunks.

| Census | Before | After |
|---|---:|---:|
| F1 posts | 10,392 | 9,660 |
| F1 beam bays | 10,392 | 9,574 |
| Solid F1 posts / bays | 0 / 0 | 9,656 / 9,569 |
| Rail collider face vertices | 0 | 230,178 |
| Buildings collision chunks | 12 | 33 |
| Buildings visual meshes | 227 | 227 |
| Buildings children / mesh jobs | 240 / 239 | 261 / 260 |

Each beam still uses six triangles, each post two. Terminal posts make the
old "eight triangles per bay" census unsuitable at gaps; the test now verifies
`2 × posts + 6 × bays`. All runtime counts are separate from the immutable
historical `buildings.json` reduction counts; other furniture still matches
those original counts. A second scene and sync/async comparisons continue to
check determinism, child order, all mesh arrays and all collider faces.

See [ROAD-7 validation and frozen-gate limitations](../../road-0068-0069-analysis.md#standalone-validation-and-unresolved-frozen-gates)
for standalone results, the full pin ledger, the unchanged ring-drive SHA
conflict and the offroad boundary-tolerance failure. Neither failure is hidden
by a test edit; full host certification is still outstanding.


Final Buildings digest prefix **c91220c9e775c1da → 1ef2afe47edc751e**;
vertices **586,254 → 567,138**, triangles **195,418 → 189,046**. The final
independent sync/async builds match, including all 33 colliders, and preserve
the 250 ms frame ceiling. Dressing passes **146** checks, including full
approach-strip clearance; reset passes all **34**, with no scene edit.
