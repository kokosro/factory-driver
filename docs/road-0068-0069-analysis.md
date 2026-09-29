# ROAD-0068 / ROAD-0069 Geometry Analysis

**Scope.** Read-only diagnosis of the two 2026-09-28 driver reports in Eifel Ring. Measurements below use the issue poses, the nearest telemetry samples, and point-to-polyline distance against the checked-in skeleton. `skeleton.json` and `drape.json` are compact one-line JSON files, so their data citations are `:1` plus the named record.

## 1. Important correction to the framing

The odometer is a persistent vehicle-distance ledger, not Nordschleife chainage: it survives sessions and records metres driven by the car (`scripts/odometer_store.gd:3-10`, `scripts/telemetry.gd:352-354`). Therefore 662,656 m and 663,905 m cannot identify a loop segment by themselves. The prior ROAD-3 document's statement that odometer is ring chainage is not valid for these data (`docs/road-3-analysis.md:33-45`).

The reliable correlations are the issue world pose and session-0184 sample lines. There are no reset events in this session.

## 2. Issue 0068 — right tyres beyond a real loop edge

Issue pose: `(1918.733, 614.433, -1273.017)`, heading `153.1°`, speed `0.438 m/s`.

The exact matching telemetry sample is line 2119: position and heading match to the recorded precision, and both axle reports are `gravel` (`0184_081650_free.jsonl:2119`). The surrounding 25 samples, lines 2107-2131, remain `gravel/gravel` while the car rotates slowly through 152.29–153.93°; this is not a one-tick classifier flicker.

### 2.1 Road identity and wheel reconstruction

The closest road is loop segment `1009142895-0`, **Hatzenbogen**, 3.851 m from the car centre; it is a `raceway`, width **8.5 m**, and is in `loops[0].segments` (`data/regions/eifel_ring/skeleton.json:1`, records `1009142895-0` and `loops.nordschleife`). The next side road is 12.852 m away, so it is not the surface being driven.

`RoadBuilder` makes half width directly from `segment.width_m` (`scripts/road_builder.gd:604-635`). Thus this pavement runs from 4.25 m left to right of its centreline.

Using the car's four documented contacts — ±0.86 m lateral and ±1.30 m longitudinal (`scripts/car.gd:2260-2275`) — and the issue pose gives:

| Wheel | Reconstructed contact `(x,z)` | Distance to `1009142895-0` centreline | Classification |
|---|---:|---:|---|
| front-left | `(1918.912, -1271.469)` | 2.935 m | road |
| front-right | `(1917.378, -1272.247)` | 4.654 m | gravel |
| rear-left | `(1920.088, -1273.787)` | 3.049 m | road |
| rear-right | `(1918.554, -1274.565)` | 4.768 m | gravel |

The two right contacts are respectively 0.404 m and 0.518 m outside the paved edge. This exactly explains the telemetry's axle-level `gravel/gravel`: telemetry records the lower-grip wheel of each axle, not four individual wheel names (`scripts/surfaces.gd:108-114`; `scripts/telemetry.gd:407-411`).

### 2.2 Why stepping off did not produce a hump

The driver was physically off asphalt in the surface model, but not off the road-height field:

- The road profile keeps the platform height through a **6 m blend band** outside pavement, easing it into terrain; only beyond that does it return raw terrain (`scripts/world_road_profile.gd:12-21`, `117-120`).
- Both tyres were only 0.4–0.5 m outside the edge: less than one-tenth of that blend distance.
- The 1.5 m shoulder rule classifies that interval as gravel, rather than road (`scripts/terrain_builder.gd:1111-1126`; `data/regions/eifel_ring/surfaces.json:4-7`).
- Gravel does reduce grip to 0.62, adds 1.6 m/s² rolling drag, and names a 3.5 cm bump amplitude (`data/regions/eifel_ring/surfaces.json:15-20`), but its bump is deliberately suppressed anywhere the profile still answers a road — including the blend band (`scripts/ring_profile.gd:29-38`, `90-99`, `134-148`).

So the report is accurate: the tyre was off pavement and had gravel grip, yet its suspension height was still the smoothly continued road surface. There is no discrete kerb, lip, rumble strip, or collision-driven edge step.

ROAD-3/4 did add a **visual** asphalt skirt: 0.5 m outward and 0.3 m down (`scripts/road_builder.gd:300-324`, `938-974`). It has no collider (`scripts/road_builder.gd:304-307`), while the car is deliberately supported by `road_profile.sample_height`, not road mesh collision (`scripts/road_builder.gd:42-63`; `scripts/car.gd:4786-4791`). It can improve the picture but cannot make the wheel feel an edge.

## 3. Issue 0069 — a genuine 3 m drivable side track

Issue pose: `(969.409, 576.206, -1573.217)`, heading `-55.9°`, stationary.

Session 0184 lines 9660-9688 are stationary at that pose and consistently report `front_surface=road`, `rear_surface=gravel`; line 9673 is the exact position match (`0184_081650_free.jsonl:9660-9688`).

### 3.1 Road identity, width, and contacts

The nearest segment is `314755146-2`, a non-loop `track`, **3.0 m paved width**, covered in drape, at 0.919 m from the car centreline (`data/regions/eifel_ring/skeleton.json:1`, record `314755146-2`; `data/regions/eifel_ring/drape.json:1`, record `314755146-2`). The nearest loop segment is `799394497-0` / Hocheichen, 15.633 m away, so this is unquestionably a side road, not a narrow part of the circuit.

The reconstructed contacts are:

| Wheel | Distance to side-road centreline | Result |
|---|---:|---|
| front-left | 0.122 m | road |
| front-right | 0.556 m | road |
| rear-left | 2.394 m | gravel |
| rear-right | 1.960 m | gravel |

The 3.0 m pavement has a 1.5 m half-width. Both rear contacts are 0.460–0.894 m beyond it, but still inside the 1.5 m gravel shoulder. This produces exactly the recorded `road/gravel` axle result.

The vehicle's track is **1.72 m** (`2 × 0.86 m`) and wheelbase is **2.60 m** (`2 × 1.30 m`) (`scripts/car.gd:2260-2275`, `scripts/car.gd:4230`). A centred, square-on car could technically fit its 1.72 m wheel track inside 3 m with only 0.64 m total lateral margin. But the reported car is sideways: the wheelbase projects across the narrow road, which is why its rear wheels exceed the edges despite the body centre being on it.

“1.5 lanes” is not a defined project unit, but the data's `track` class is 3.0 m, so the natural interpretation is **4.5 m paved width**. At this exact pose, retaining all contacts on asphalt requires `2 × 2.394 = 4.788 m`; therefore **5.0 m** is the practical minimum if the intent is “a stopped, sideways car's four wheels remain paved,” while 4.5 m satisfies the literal 1.5-lane target and leaves the last ~0.14 m in shoulder.

### 3.2 It is drivable today, not terrain-only

Yes: the side road is deliberately drivable in the current architecture.

- Its drape record is `covered: true` (`data/regions/eifel_ring/drape.json:1`, `314755146-2`).
- `RoadBuilder` sweeps every valid covered drape segment and uses the skeleton width as the paved strip width (`scripts/road_builder.gd:604-635`).
- Terrain reads the same covered segments into ribbons at the same half width (`scripts/terrain_builder.gd:939-968`).
- The car samples the profile at each wheel, rather than terrain collision (`scripts/car.gd:4786-4791`).

Thus the 3 m strip is both visually paved and physically sampled as a road. Terrain is only the surrounding visual/supporting surface; it does not make this road “fake.”

## 4. Network scale and width inventory

The skeleton contains **16,771 segments**: **92 loop** segments and **16,679 non-loop/side** segments. All 92 loop segments are covered; 3,222 side segments are covered. The current drivable build then excludes ten off-loop layer-crossing structures by rule, not because ordinary side roads are non-drivable (`scripts/road_builder.gd:64-87`, `1160-1205`; `tests/ring_drive_test.gd:78-80`, `413`).

| Group | Width distribution |
|---|---|
| loop | 91 × 8.5 m; 1 × 7.5 m Karussell |
| all side segments | 11,718 × 3 m; 2,171 × 5.5 m; 1,211 × 6 m; 602 × 7 m; 513 × 6.5 m; 206 × 2 m; remaining tagged widths |
| covered side segments | 2,323 × 3 m; 255 × 6 m; 248 × 5.5 m; 210 × 7 m; 80 × 8.5 m; 49 × 6.5 m; small remainder |

The two locations are therefore representative of distinct cases:

- 0068: an **8.5 m loop strip**, with intentional shoulder classification but no physical edge feature.
- 0069: a **3.0 m covered side track**, a common network default that is drivable but unsuitable for the requested sideways-car use.

No side segment can be correlated to the two lifetime-odometer values alone; the supplied positions identify `1009142895-0` and `314755146-2`.

The region design explicitly says every q1 road class has road physics (`docs/design/4b/ring-region-decisions.md:18-20`) and includes tracks/service roads as drivable/plain (`docs/design/4b/ring-region-decisions.md:38-40`). So 0069 is a valid scope complaint, not a misunderstanding of intended access.

## 5. Ranked fix proposal

### 1. Widen the specifically intended side-road class/segments — highest value

Set selected drivable `track` segments, beginning with `314755146-2`, to **5.0 m paved**. This exceeds the literal 4.5 m / 1.5-lane reading just enough to contain this demonstrated sideways pose. Do not indiscriminately widen all 2,323 covered 3 m tracks without a design rule; many are real access tracks and widening them changes the world's road hierarchy.

Files/process:

- `data/regions/eifel_ring/skeleton.json` width records, then deterministic `tools/world/drape.py` regeneration of `drape.json`;
- update profile/ring-drive pins and add a regression placing the car sideways on `314755146-2`;
- no `car.gd` or scene edit.

Risk: **medium process / low cert-mechanics risk**. Skeleton and drape are byte-pinned data artifacts (`tests/ring_drive_test.gd:352`, `365-382`), and historical gates explicitly keep both unchanged in later feature work (`docs/night-shift-3.md:101-105`). They are not casual editable knobs. But the certified metrics are on-road baseline drives and a widened non-loop side road does not alter their profile queries; verify byte-identical metric lines regardless.

Rough effort: 1–2 days including regeneration, pins, targeted test, and full gate.

### 2. Add an actual edge treatment, not merely more gravel classification — highest value for 0068 feel

Add a **0.10–0.15 m raised/rumble transition over roughly 0.3–0.5 m** at selected loop edges, with a distinct shoulder/kerb surface response. Keep the existing 1.5 m gravel shoulder outside it. The key requirement is that `RingProfile.sample_height` changes at the edge: visual terrain/skirt edits alone cannot create felt suspension motion.

Files:

- editable `scripts/road_builder.gd` for matching render geometry;
- editable `scripts/terrain_builder.gd` for the adjoining verge strip;
- `data/regions/eifel_ring/surfaces.json` and `scripts/surfaces.gd` for a named kerb/rumble class and grip/drag;
- likely `scripts/ring_profile.gd` for the physically felt height feature, because the current profile deliberately returns the inner smooth field anywhere a road answers (`scripts/ring_profile.gd:90-99`).

Risk: **medium**. Implement it strictly outside the existing paved loop width so on-asphalt samples remain bit-identical. The current 0068 tyres are only 0.4–0.5 m out, so this would address the report directly. Add an on-road bit-equality test and an off-edge wheel-height/acceleration test.

Rough effort: 2–4 days.

### 3. Racing-line kerbs/rumble strips — best fidelity, broader design decision

Add kerbs only at selected Nordschleife corners/runoff edges, not as a blanket road perimeter. This aligns with the driver's “other elements of the road” suggestion and with source documentation noting limited runoff and close barriers (`docs/nordschleife-data-sources.md:40-42`).

Files are the same as proposal 2, plus a new data table identifying eligible loop chainages/edges. Avoid modifying `scenes/eifel_ring.tscn` and `scripts/car.gd`, both frozen in the established gated workflow (`docs/night-shift-3.md:66`; `docs/pad-physics-diagnosis.md:68`).

Risk: **highest design and validation cost**, but cert-safe if kerbs lie outside the certified driving envelope. The historic cert assertion is byte-identical metric lines; it must remain so, not merely remain “close.”

Rough effort: 4–7 days including authored placement criteria, profile/render implementation, and regression coverage.

## 6. Conclusion

0068 is not missing shoulder classification: the right tyres were correctly classified as gravel. It lacks a physical edge because the height field intentionally blends for 6 m and the visual skirt has no collision role.

0069 is a correctly drivable but objectively narrow covered side track: 3.0 m is one lane, not the requested 1.5 lanes. A **5.0 m** local/selected-side-road target is the smallest robust response to the demonstrated sideways beaching, while a separately scoped edge-profile feature is the right response to 0068.

## §7 The ROAD-6 ruling

Issue-0069: "this is a side road, the car is sideways. The road is so small that the car is now syspended with the middle of the car on the road and wheels outside the road. this is a lateral road, not the main circuit road. i believe these roads should be drivable, so they need to be at least one an a half lanes"

The paved target is **5.0 m**, containing the demonstrated 4.788 m contact envelope.
Selection is deterministic: covered non-loop `track` segments of exactly 3.0 m
qualify if mandatory `314755146-2`, if an endpoint junction also lists a loop
segment, or if the entire polyline lies within 250 m of the loop's junctions.
Loop membership comes from `loops[0].segments`; endpoint membership comes from
`junctions[].segments`. Distance means distance to the set of those junctions:
every chord is covered by the union of their closed 250 m disks. Analytic
chord/disk interval merging checks the whole line, including between vertices.
Widths already at least 5 m and non-track classes remain unchanged.

**217 selected**: 217 proximity, zero eligible endpoint neighbours, mandatory
segment included in proximity (216 proximity-only plus one mandatory/proximity).
There are 92 loop junctions; their adjoining non-loop covered roads are service
or raceway, not eligible tracks. Of the selected widths, 127 were class defaults
and 90 were OSM-tag widths. `width_source: road6` records the override honestly;
skeleton pipeline version is 2, with the loader and synthetic fixtures updated.
The ten reader-side crossing exclusions remain: two selected tracks are crossing
structures, so 215 widened strips are swept. Covered control `1017207294-0` stays
3.0 m outside the rule. No segment coordinates, topology or loop widths changed.

Full selected id list:

1079720769-0, 1079720770-0, 115841312-0, 115841722-0, 115844410-0, 125938924-0, 1267959798-0, 1318192429-0, 132472315-4, 1362042117-0, 1436709136-0, 1497876849-0, 1497894588-2, 1504014682-0, 198509976-0, 198509976-1, 198509977-0, 198509978-0, 218651335-0, 218651336-0, 218651338-0, 218651341-0, 218651342-0, 218651342-1, 218651343-0, 218651343-1, 218651343-2, 218651343-3, 218651344-0, 218651344-1, 232419552-0, 232419646-0, 235828206-0, 235828208-0, 235828208-1, 235828209-0, 235828209-1, 235828209-2, 235828284-0, 235828284-1, 235829137-0, 235829445-1, 235992189-1, 235992190-0, 235992190-1, 235992190-2, 26956364-0, 26956364-1, 288003116-0, 29175254-2, 29175254-3, 29896214-1, 29898554-0, 299065689-0, 299065689-1, 299065690-0, 299065691-0, 299065693-0, 299065693-1, 299065694-0, 299065698-0, 31009224-0, 31009224-1, 31009224-2, 31009224-3, 31009224-4, 313991420-1, 313991425-0, 313991425-1, 313991425-2, 313991426-0, 313991426-1, 313991427-0, 314755143-0, 314755146-0, 314755146-1, 314755146-2, 314755147-0, 314755148-0, 314755148-1, 314755151-0, 314755152-0, 314755152-1, 325813597-0, 325813599-0, 325813599-1, 326074028-0, 342137295-0, 342137295-1, 343707421-0, 343707422-0, 343707423-0, 343707423-1, 343707424-0, 343707938-4, 356729556-1, 38901548-7, 39629069-6, 39629069-7, 39726277-0, 39726277-1, 40277347-0, 40277347-1, 40277347-2, 40277347-3, 40277347-4, 40277347-5, 41454279-2, 41454280-0, 41454281-0, 41454281-1, 41454281-2, 41454282-0, 41454284-0, 41454287-2, 41454288-0, 41454290-0, 41454299-0, 41454300-0, 41454320-0, 41454324-0, 41455739-0, 41455743-0, 41455748-0, 41459258-0, 41459258-1, 41459258-2, 41459260-0, 41795612-0, 41795615-0, 41795617-0, 41795633-0, 41795633-1, 41842486-13, 41842486-8, 420556737-0, 420556739-0, 422688801-0, 422688801-1, 437726506-0, 437726524-0, 437726524-1, 437726524-2, 437726525-1, 437726525-2, 437726539-0, 464083619-0, 464504685-1, 464504685-2, 464504685-3, 47494185-0, 484767448-0, 484767448-1, 484767449-0, 549430972-1, 602094843-0, 612131151-0, 612131152-0, 612634087-0, 64004273-0, 64004274-0, 64004277-2, 64004277-3, 64004277-4, 64004277-5, 64004277-6, 64004277-7, 64004277-8, 683006911-0, 683134845-0, 683289898-0, 683289899-0, 696630804-0, 699245733-0, 699245734-0, 699245735-0, 699245736-0, 699258488-0, 699258489-0, 699258490-0, 699258490-1, 699258499-0, 699258500-0, 699258501-0, 699273914-0, 699273920-0, 699283195-0, 699283200-0, 699283200-1, 699283200-2, 699283201-0, 699283215-1, 699283216-0, 699283217-0, 699283217-1, 825819245-0, 827657660-0, 828126281-0, 828126281-1, 829597634-0, 829597636-2, 829597637-0, 830369719-0, 830373064-0, 830373066-0, 830375191-0, 832284558-0, 832284559-0, 832284559-2, 832284559-3, 846956207-0, 846956207-1, 846961562-0, 849444903-0, 89902109-0, 89902109-1, 89902109-5

### Generation and pins

Generator path, no manual JSON edits. The original skeleton generator reproduced
the original artifact byte-for-byte using the archived
`/Users/kokos/Downloads/fd-4B2-osm.zip`, extracted to
`/tmp/road6-inputs/tmp/fd-4B2-osm`. Both stages used
`/Users/kokos/.claude/jobs/a61f3c60/venv/bin/python`. Reproduce with:

```sh
python tools/world/skeleton.py --snapshot <snapshot> --coverage-drape data/regions/eifel_ring/drape.json --out data/regions/eifel_ring/skeleton.json
python tools/world/drape.py --tiles /Users/kokos/.claude/jobs/a61f3c60/dgm1 --skeleton data/regions/eifel_ring/skeleton.json --out data/regions/eifel_ring/drape.json
```

Coverage is the DEM centerline coverage, independent of width. The first run used
the saved old drape as coverage input; a repeat using the newly generated drape
produced identical skeleton and drape bytes. The full drape generator resampled
the DEM, smoothed and stitched all records. Inspection and structural comparison
prove its `dense`, `crossfall`, coverage, lattice and all other non-snapshot fields
are unchanged: this generator does not use width in these arrays. The runtime
road and terrain builders consume width for their strips and fields.

SHA-256 old -> new (deliberate certificate data change):

- skeleton: `f5f2498f1517ec6ebeb6a3f8d48f3beafbebc1fbb6824f90dc0ce02237b2333d` -> `3c05fc5633b2b1bf34ee7572e44877b78eab840e7657bcbeee97e6f39050c11e`. The new regression pins these bytes; drape also pins its skeleton SHA.
- drape: `d36ccf27690be2596d39b28258e7ab4564eecf5503b467d5a3e47764e7233ea0` -> `9909c378787636792fc64381d7b6150a5fc0b80da8e5737b5ce2f8f294229e9a`. `ring_drive_test.gd` retains exact byte equality.
- World-profile 200-sample digest: `647200ff7f718f029180abf4c45407e2fb0d10eefd1b0d6153b5ebe2e4efecd9` -> `aabf29b2a3f05f2d12af64d0efd57e2be348e26cb551db6dacadc7674954231a`, from wider side-road fields. These are world-height samples, not pad-drive cert metrics.

Measured build: 3304 swept roads unchanged; sections 361393 -> 369357,
vertices 1085645 -> 1109537, triangles 1435286 -> 1467142 (wider crossfall
requires more twist subdivisions). Terrain vertices 2772530 -> 2771991,
triangles 4466373 -> 4465491, capped vertices 361787 -> 364819; wider
footprints drop 106275 near cells. Async hashes, previous documented -> measured:
Road `dfa68bb59bdb78c7` -> `a76bb21a8ba8d268`;
Terrain `b5646e3bd1f1a7a8` -> `cee78c6ead17be04`;
Forest `37d8d855599b8de2` -> `ec3096859e758d72` (field-dependent placement).
The async test compares full hashes and describe/count reports between independent
sync and async builds; it has no literal expected hashes to replace. Its measured
history is updated, and the exact equality checks remain intact. The ring test
also measures rather than literal-pins its describe counts.

### Regression and measured gates

`tests/side_road_test.gd` follows marks in the runner. Nine checks pin the skeleton,
5 m issue width, unchanged covered control, sideways heading, four individual
`Surfaces.classify` contacts and front/rear `road` readings at
`(969.409, 576.206, -1573.217)`, yaw -55.9°. All nine passed.
The configured suite grows 2904 -> 2913 checks and 31 -> 32 markers.
Two Python rule tests pass (boundaries, whole chords, mandatory/endpoint/proximity,
class/width/coverage/loop exclusions and deterministic repeats).

Targeted Godot assertion verdicts: skeleton 171, world profile 154, ring drive 68,
dressing 120, reset 34, async build 15, side road 9: all passed. Their logs have
three sandbox startup errors each (user log writes and macOS certificate access),
so these are assertion results, not clean full gates.

**Full gates blocked by the sandbox.** Two sequential runner attempts and one
`--parallel` attempt each exit 1 at import: Godot cannot save
`/Users/kokos/Library/Application Support/Godot/editor_settings-4.7.tres`.
Logs: `/tmp/road6-suite-1.log`, `/tmp/road6-suite-2.log`,
`/tmp/road6-suite-parallel.log`. Each has three ERROR lines and no metrics lines;
the cert comparisons cannot be IDENTICAL to the nonempty base. No pad metric
drift was observed because the runner never reached those drives. Full-suite
counts, output equality and cert byte identity remain unverified; no sandbox
workaround or physics change was made. All 16 frozen files, including
`surfaces.json`, retain their pre-edit SHA-256 values (`tests/visual_probe.gd`
was additionally compared against the untouched HEAD blob).

README.md has no documented side-track width policy, so it is unchanged.


## §8 ROAD-7 / F1-COLLISION-1 (2026-09-29)

The five-point ruling supersedes ROAD-6's proximity/class selection: **every
DEM-covered non-loop segment below 5 m becomes 5 m**, regardless of class or
original tag. `widen_side_tracks` retains its pipeline entry point, with
`width_source: road7` and skeleton pipeline **2 → 3**. The loader accepts the
new provenance and verifies its 5 m value. The mandatory `314755146-2` remains
5 m. All 92 loop records, coordinates, topology and uncovered widths are
unchanged; loop widths remain 91 × 8.5 m and one × 7.5 m.

Of 3,222 covered side segments, 1,060 → **3,222** are at least 5 m. ROAD-7
carries **2,379 overrides**, including the 217 already widened by ROAD-6
(provenance-only change) and **2,162 newly widened records**:

| Class | Old → new pavement | Newly widened segments |
|---|---|---:|
| service | 3 → 5 m | 1,219 |
| track | 3 → 5 m | 887 |
| track | 2 → 5 m | 50 |
| track | 4 → 5 m | 3 |
| track | 1.5 → 5 m | 3 |

The complete segment-by-segment old/new width and provenance inventory is
[road7-width-changes.csv](road7-width-changes.csv), including all 217 prior
ROAD-6 selections. Total skeleton segment count stays **16,771**; covered
side count stays **3,222** and runtime swept count stays **3,304**.

### Reproduction evidence

Before any generator edit, both current generators reproduced the checked-in
files byte-for-byte (`cmp`, exit 0), skeleton `3c05fc56…` and drape `9909c378…`.
The supplied `fd-port` snapshot directory lacked q1/q2 JSON. The unchanged
archived `/Users/kokos/Downloads/fd-4B2-osm.zip` supplied those answers; it was
extracted under this repo's `.road7-work/inputs/`, with the generator checking
its manifest and six queries. Python was the existing
`/Users/kokos/.claude/jobs/a61f3c60/venv/bin/python`, with bytecode writes disabled.
The DEM was read from `/Users/kokos/.claude/jobs/a61f3c60/dgm1`, as in ROAD-6.
No files were written to either external location.

Commands (outputs and logs inside this repo):

```sh
PYTHONDONTWRITEBYTECODE=1 <venv>/bin/python tools/world/skeleton.py --snapshot .road7-work/inputs/tmp/fd-4B2-osm --coverage-drape .road7-work/baseline-drape.json --out data/regions/eifel_ring/skeleton.json
PYTHONDONTWRITEBYTECODE=1 <venv>/bin/python tools/world/drape.py --tiles <dgm1> --skeleton data/regions/eifel_ring/skeleton.json --out data/regions/eifel_ring/drape.json
```

A second generation used the newly generated drape as coverage and wrote
separate repeat artifacts; both `cmp` checks again exited 0. Structural
comparison confirms **all non-snapshot drape data is unchanged**, including
DEM pins, heights, dense arrays, crossfalls, lattice and coverage. The
snapshot's skeleton hash and skeleton pipeline version are the only drape
changes. The generator's self-test also exercises covered tagged residential,
service, mandatory-track selection, exclusions and idempotence.

### Pin ledger for the host commit

| Pin | Before | After |
|---|---|---|
| skeleton SHA-256 | `3c05fc5633b2b1bf34ee7572e44877b78eab840e7657bcbeee97e6f39050c11e` | `bcdd9456b5376b2bc21ec69187c2f0daa7e906f506d53818394ea3b3ce733de3` |
| drape SHA-256 | `9909c378787636792fc64381d7b6150a5fc0b80da8e5737b5ce2f8f294229e9a` | `d62e1f32ca938b66fcc6b6f6c3c53622889095666c6cc9524e814872851bae54` |
| world-profile 200 samples | `aabf29b2a3f05f2d12af64d0efd57e2be348e26cb551db6dacadc7674954231a` | `9cdcc4c57f7fa054ff027751971b62fc55964bc82c193a628215d6f6a6de70da` |
| road-edge 4,965 queries | `fc59167f9f745e5f1eb497afa1d634a2b090ae99b4b0327ad3050fe8dd820d03` | `482b425b054fae5ccd833727a7f67780d7b4499264bc84dc9855e02ec7e5320a` |
| skeleton version / synthetic fixtures | 2 | 3 |

The road-edge digest samples the combined world field: wider nearby side-road
fields affect some loop queries even though loop data itself is unchanged.
The loop-only physical lip and rumble mesh census remain unchanged. No car,
surface, road-profile, ring-profile, bubble, scene or catalogue edit was used.
Rail placement, exit table, collision counts and clearance evidence follow in
[4b8-report.md](design/4b/4b8-report.md#road-7--f1-collision-1).


The runtime digests printed by `async_build_test` (16-hex prefixes; full
sync/async digests still compared) moved as follows:

| Builder | Before | After |
|---|---|---|
| Road | `af1cd69f426516cc` | `e84b7f4c3a8ef510` |
| Terrain | `5c5ee1f6ba4d1b4a` | `787f0642584fd0bb` |
| Forest | `3241b4b76c9e000a` | `9082e0a1bdf6f057` |
| Buildings | `c91220c9e775c1da` | `1ef2afe47edc751e` |

Road sections **369,357 → 441,723**, paved vertices **1,109,537 → 1,326,635**,
paved triangles **1,467,142 → 1,756,606**; road count stays 3,304. Road
meshes/shapes stay 6,700/3,305; the 92 rumble meshes retain 135,444 vertices
and 179,856 triangles. Terrain now has **2,766,897 vertices / 4,456,307
triangles**, with **388,003** capped vertices (was 364,933), 110,867 near
cells dropped, 3,352 meshes. Forest has **2,598,435 vertices / 2,183,322
triangles**, 19,379 trunks in 42 bodies and 84 meshes. Buildings visual
vertices **586,254 → 567,138**, triangles **195,418 → 189,046**. Rail census
and per-stage job changes are in the companion report. Synthetic snapshot
version pins also moved in `reset_test.gd`; its logic did not change.

### Standalone validation and unresolved frozen gates

Each invocation used `FD_DATA_DIR="$PWD/.road7-work/data"`,
`godot --headless --path . --log-file "$PWD/.road7-work/<name>-engine.log"
-s tests/<name>_test.gd`, with stdout/stderr captured under `.road7-work`.
No full-suite invocation, git commit or push was made. Final assertion results:

| Test | Result |
|---|---|
| skeleton | PASS, 173 checks |
| world_profile | PASS, 154 checks |
| side_road | PASS, 10 checks |
| road_edge | PASS, 18 checks |
| dressing | PASS, 146 checks |
| reset | PASS, 34 checks |
| async_build | PASS, 17 checks; 250 ms ceiling retained |
| bubble (frozen, extra verification) | PASS, 17 checks |
| offroad (frozen, extra verification) | **FAIL, 1 of 36 checks** |

The offroad failure is a measured consequence of the wider road field at the
DEM boundary, not rail contact. At `(2450, -6000.01)`, the test's ±1 cm samples
differ by **0.010613583 m**, above its 0.010000000 m limit. Re-evaluating the
saved baseline geometry with the same unchanged profile gives **0.007177782 m**.
Newly widened track **235829445-2** now contributes its blend band there:
inside/edge heights are 375.843464647 / 375.854078182 m, versus the baseline
terrain's 375.902822266 / 375.910000000 m. The road/profile/continuation and
frozen test are unmodified; no tolerance relaxation was applied. The offroad
drive and its repeated-scene determinism checks pass. This needs a ruling
before a clean full-suite certification can be claimed.

There is also an explicit freeze/pin conflict: **`ring_drive_test.gd` remains
byte-identical**, so its literal `DRAPE_SHA256` still names the old `9909c378…`
artifact, and its synthetic snapshot still names pipeline version 2. The
standalone ring-drive test was not run or claimed to pass. The host must resolve
whether those two data pins may move to `d62e1f32…` / 3; merely changing headers
in other test files cannot satisfy its SHA assertion. No exception to the
frozen-file rule was assumed.

All runtime Godot logs contain the native macOS `get_system_ca_certificates`
error already documented in 4B-8. Thus PASS means assertion/process success,
not a clean runner error gate. No GDScript errors remain in final test logs.
The full 34-step suite and its certification metrics remain for the host.
Frozen files, including all element JSON, mission ladder and the runner, were
compared byte-for-byte against HEAD; all 22 matched. `git diff --check` passed.

### Independent review rerun

The working tree already contained the implementation when this review began.
The reviewer recovered the generator and artifacts from HEAD `e805384` into
`.road7-work/review/`, regenerated the baseline skeleton and DEM drape, and
obtained `cmp` exit 0 for both. Two fresh ROAD-7 skeleton/DEM drape generations
also compared equal to the working artifacts (all four `cmp` exits 0), and
the generator self-test passed. The 44 exit IDs independently derived from
skeleton membership and drape coverage exactly match the companion report.
All 22 frozen files still match HEAD; the drape's non-snapshot data and every
loop segment record are unchanged.

The boundary probe was rerun against baseline and ROAD-7 data using the same
frozen profile code: **0.007177782 m → 0.010613583 m**, confirming the unresolved
offroad tolerance conflict above. Review logs, generated comparison files and
isolated application data are under `.road7-work/review/`. The sandbox also
denied `ps` process inspection; this did not prevent the standalone runs.

Fresh standalone results: skeleton **173**, world_profile **154**, side_road
**10**, road_edge **18**, dressing **146**, reset **34**, async_build **17**
checks passed; all seven processes exited 0. Async retained its 250 ms ceiling
and every sync/async geometry comparison. Dressing re-measured rail collider
clearance as **2.368849 m / 1,029.782349 m**. All seven logs contain only the
known native certificate-store error among ERROR lines, with no script errors.
The previously recorded full frozen bubble/offroad runs were not repeated in
this review; the offroad boundary probe was. Full-suite certification remains
with the host, and no commit or push was performed.
