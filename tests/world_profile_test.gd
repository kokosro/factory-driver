extends SceneTree
## Headless world-profile test: the Ring's checked-in drape
## (data/regions/eifel_ring/drape.json, written offline by
## tools/world/drape.py from the 42 verified DGM1 tiles and skeleton.json)
## is read the way WorldRoadProfile reads it and has to pass its validation
## against the skeleton, then is held to what the plan asks
## (implementation-plan.md §4B-3, data-pipeline.md §5): the snapshot and
## the skeleton it was draped on pinned, the 42 tiles each sha-verified,
## the coverage the 7 km × 6 km core and the lattice spanning it; every
## Nordschleife segment covered; the crest/dip labels recounted here from
## the file's own dense heights (the rules mirrored) and equal to the
## file's; every draped bridge deck linear between its abutments; the
## Karussell's bank (branch (c): 30 % over 6.5 m with the 1 m strip) read
## across the bowl; the reference heights: the loop's lowest sample at the
## Breidscheid bridge 333 ± 2 m, its highest at T13 (the Sabine-Schmitz-
## Kurve) 627.5 ± 2 m, the Hohe Acht way's top 616.8 ± 2 m (the pins,
## re-measured, ring-region-decisions.md §3); the world's slopes beyond the
## pad's MAX_SLOPE; the documented fallback outside coverage. Then a
## 3 × 3 km fixture built here (never on disk): a plane with a bowl and two
## crests, draped through the mirrored rules, holds sample_height to the
## plane within 1 mm, its gradient to the plane's slope within 1e-4,
## bilinear continuity across the lattice's seams, the crown and the
## superelevation across the platform, a bridge deck linear between its
## abutments, a tunnel below the ground, the crest labelled where the
## curvature says, the bank's bowl; and validate() on fixtures broken in
## code names the field. JUNCTION RIGHT-OF-WAY (issues-analysis-2026-09-24.md
## §4.4, triage item 4): the loop's segments are the profile's priority
## roads (Road.priority from the skeleton's loops entry) and inside a loop
## road's own paved width a nearer non-loop chord no longer answers; held
## here on the flags (92 loop roads, no other), on a square-loop fixture
## with a service road running inside the loop's width (the loop answers on
## its platform, the service road in the blend band beside it, and with no
## loops entry the old rule), and on the corrected field the car reads (the
## rim rule and the crossing right of way applied as RoadBuilder.build()
## does) at the loop's 44 junctions with a covered non-loop participant and
## at the driver's five sites (0012, 0018, 0017, 0021-part, 0001-residual):
## no station inside the loop's paved width read from a non-loop road
## (was 4 690), every junction under the loop's own kink bound, the
## one-step jumps at the sites down to the loop's own; with it the rim
## walk stays on the loop at T13 (road_builder.gd), so the stub's lifted
## end meets the loop's own continuation, not the Boxengasse's. ROAD-SMOOTHING
## (2026-09-23, tools/world/drape.py's
## header): the checked-in file's plain segments are Whittaker-smoothed
## (lambda 5, the crest/dip runs held to the raw data) and every
## junction's ends stitched in height and crossfall, write-side; held
## here from the file's own numbers: the loop's station-to-station grade
## change at the 90th and 99th percentiles against the raw file's, every
## junction's covered ends on one height and one crossfall, the driver's
## issue-0005 stair (junction 65386044) and issue-0001's T13 ridge
## (junction 312821860) flat in the file and in the field, and the raw ->
## smoothed evidence over ±50 m at the three issue sites (the raw
## numbers pinned from the file before the smoothing, b8d4e531...). The
## noisy fixture (a seeded noise band on a plane with a 30 m crest) needs
## numpy and lives in drape.py --selftest; its evidence is cited in
## docs/design/4b/data-pipeline.md §5. No network, no python, no DGM1:
## drape.py is never run by the suite. Seconds, right after the skeleton
## test in run_tests.sh: static data that fails first. Writes nothing
## under /tmp. Exits 0 on success, 1 on any fault.

## The pinned snapshot (ring-region-decisions.md §1), its own literal.
const PINNED_OSM_BASE := "2026-09-22T08:45:51Z"

## The DGM1 core (data-pipeline.md §2.2): E 352-359 km × N 5577-5583 km in
## game metres, 42 tiles; the lattice at 10 m over it.
const CORE_X := [0.0, 7000.0]
const CORE_Z := [-6000.0, 0.0]
const CORE_TILES := 42
const LATTICE_STEP_M := 10.0
const LATTICE_COLS := 701
const LATTICE_ROWS := 601

## The reference heights (ring-region-decisions.md §3, re-measured at
## 4B-3 and pinned with a "was ->" there and in docs/nordschleife-data-
## sources.md §1): the sample points are not coordinates the docs record
## but derived here from the file itself: the loop's lowest dense sample IS
## the Breidscheid bridge (the loop's valley floor, its lowest point by
## every recorded source) and its highest IS T13 / the Sabine-Schmitz-Kurve;
## the Hohe Acht way (414785756, the checked-in sample's) is the cross-check
## that the tiles and the datum are right: 616.50 m measured against the
## officially recorded 616.8 m.
## was Breidscheid ~320 ± 5 -> 333 ± 2 m (measured 332.94; the raw DGM1
## ground on the track line within 100 m of the bridge reads 331.8-343 m,
## the stream bed itself 327.1 m: the ~320 figure was the myth, not a
## tolerance to widen); was Hohe Acht ~620 ± 5 -> the loop's top 627.5 ± 2 m
## at T13 (measured 627.52), the Hohe Acht way itself 616.8 ± 2 m.
const BREIDSCHEID_M := 333.0
const LOOP_TOP_M := 627.5
const HOHE_ACHT_M := 616.8
const REFERENCE_TOLERANCE_M := 2.0
const HOHE_ACHT_WAY := 414785756

## The world exceeds the pad's gentle-slope assumption (road_profile.gd's
## MAX_SLOPE 0.015; implementation-plan.md §2.3): the loop's steepest
## gradient is well past it and under the recorded 27 % stretches' order.
const PAD_MAX_SLOPE := 0.015
const LOOP_SLOPE_CEILING := 0.35

## Rounding of the file's heights [m]: what a linear check allows per end.
const HEIGHT_ROUNDING_M := 0.005

## The 200-sample set's sha256 as read on the checked-in file, pinned so a
## change in the profile's arithmetic on it is a documented "was ->",
## never a silent drift. was b167c232... (4B-3's landing, 00db178) ->
## bab692ef... (ROAD-SMOOTHING, 2026-09-23: the file's heights changed -
## the plain segments Whittaker-smoothed, the junctions stitched - the
## profile's arithmetic did not) -> e5b34889... (the codex review's
## fix-forward: the crossfall stitched as a world-space tilt, F1/F4) ->
## 647200ff... (the ROAD-GEOMETRY FIX-NOW landing, 2026-09-25: the file's
## crossfall arrays regenerated under the crossfall-twist rule and the
## Karussell blend - the heights untouched; the profile's arithmetic
## changed only inside the Karussell's two 30 m ramps, where the plane is
## blended into the bowl).
const SAMPLES_DIGEST := "647200ff7f718f029180abf4c45407e2fb0d10eefd1b0d6153b5ebe2e4efecd9"

## The codex review's precision repro: the segment and the pipeline's value.
const MIRROR_SEGMENT := "1017207289-0"
const MIRROR_HEIGHT_M := 698.02

## The fixture: a plane 400 + 0.05 x - 0.02 z [m] over 3 × 3 km with a
## bowl 20 m deep, 200 m radius at (1500, -1500), a crest 3 m high, 30 m
## long across the straight at z = -800 (x within 50 of 800) and another
## across the bridge at x = 1100 (z within 50 of -400). The roads' stations
## land on centimetre-exact plane values, so the file's rounding costs
## nothing on the plane.
const PLANE_BASE := 400.0
const PLANE_SLOPE_X := 0.05
const PLANE_SLOPE_Z := -0.02
const BOWL_CENTRE := Vector2(1500.0, -1500.0)
const BOWL_RADIUS_M := 200.0
const BOWL_DEPTH_M := 20.0
const CREST_HEIGHT_M := 3.0
const CREST_HALF_LENGTH_M := 15.0
const FIXTURE_SIZE_M := 3000.0
const MM := 0.001

var _failures := 0


func _initialize() -> void:
	var skeleton: Variant = SkeletonLoader.read_file()
	var drape: Variant = WorldRoadProfile.read_file()
	_check_files(skeleton, drape)
	if skeleton is Dictionary and drape is Dictionary:
		_check_snapshot(skeleton, drape)
		_check_dem_and_coverage(drape)
		var profile := WorldRoadProfile.from_data(skeleton, drape)
		var segments := SkeletonLoader.segments_of(skeleton)
		var raw_points := _raw_points(skeleton)
		_check_segments(skeleton, drape, segments)
		_check_label_recount(drape, raw_points)
		_check_bridges(drape, segments, raw_points)
		_check_karussell(drape, profile)
		_check_reference_heights(skeleton, drape, raw_points, profile)
		_check_slopes(skeleton, drape, raw_points, profile)
		_check_fallback(profile)
		_check_ring(profile)
		_check_smoothing(skeleton, drape, raw_points, profile)
		_check_geometry_fences(skeleton, drape, raw_points, profile)
		_check_right_of_way(skeleton, drape, raw_points, profile)
	_check_fixture()
	_check_right_of_way_fixture()
	_check_broken_fixtures()
	print("WORLD PROFILE TEST PASSED" if _failures == 0 else "WORLD PROFILE TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


func _raw_points(skeleton: Dictionary) -> Dictionary:
	var found := {}
	for raw: Variant in skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String:
			found[raw.id] = raw.points
	return found


# =============================================================================
#  THE REAL FILE
# =============================================================================

## The drape is there, is JSON, parses twice to the same bytes, and passes
## validate() against the skeleton with nothing to say.
func _check_files(skeleton: Variant, drape: Variant) -> void:
	var reparsed: Variant = WorldRoadProfile.read_file()
	_ok(drape is Dictionary and var_to_bytes(drape) == var_to_bytes(reparsed), "%s parses, and parsed twice it comes out the same" % WorldRoadProfile.PATH, "%s: %s" % [WorldRoadProfile.PATH, "not a JSON object" if not drape is Dictionary else "parsed twice, it does not come out the same"])
	_ok(skeleton is Dictionary, "the skeleton it was draped on is there")
	var errors := WorldRoadProfile.validate(drape, skeleton)
	for error: String in errors:
		printerr("  FAIL  ", error)
	_failures += errors.size()
	_ok(errors.is_empty(), "the drape passes WorldRoadProfile.validate() against the skeleton with nothing to say")
	if drape is Dictionary:
		var keys: Array = drape.keys()
		keys.sort()
		_ok(keys == ["coverage", "dem", "lattice", "origin", "rules", "segments", "snapshot"], "the schema's seven top keys: %s" % [keys])


## The snapshot pinned, the skeleton it was draped on the checked-in one.
func _check_snapshot(skeleton: Dictionary, drape: Dictionary) -> void:
	var snapshot: Dictionary = drape.snapshot
	_ok(snapshot.osm_base == PINNED_OSM_BASE and snapshot.query_sha == skeleton.snapshot.query_sha, "snapshot.osm_base is the pinned %s and query_sha the skeleton's" % PINNED_OSM_BASE, "snapshot is %s" % [snapshot])
	_ok(snapshot.pipeline_version == 1 and snapshot.skeleton_pipeline_version == 1, "drape pipeline_version 1 on skeleton pipeline_version 1", "versions %s / %s" % [snapshot.get("pipeline_version"), snapshot.get("skeleton_pipeline_version")])
	var skeleton_sha := FileAccess.get_sha256(SkeletonLoader.PATH)
	_ok(snapshot.skeleton_sha256 == skeleton_sha, "snapshot.skeleton_sha256 is the checked-in skeleton's %s" % skeleton_sha, "snapshot.skeleton_sha256 is %s, the checked-in skeleton is %s (draped on another skeleton)" % [snapshot.skeleton_sha256, skeleton_sha])
	var origin: Dictionary = drape.origin
	_ok(origin.epsg == SkeletonLoader.EPSG and origin.e0 == SkeletonLoader.E0 and origin.n0 == SkeletonLoader.N0, "origin is the Ring's frame", "origin is %s" % [origin])


## The DEM's 42 tiles each verified against the metalink's sha256; the
## coverage the core; the lattice spanning it at 10 m.
func _check_dem_and_coverage(drape: Dictionary) -> void:
	var dem: Dictionary = drape.dem
	var verified := 0
	for tile: Dictionary in dem.tiles:
		verified += 1 if tile.verified else 0
	_ok(dem.tiles.size() == CORE_TILES and verified == CORE_TILES, "dem: %d DGM1 tiles, %d sha256-verified against the metalinks, %s, EPSG:%d, %s" % [dem.tiles.size(), verified, dem.source, dem.epsg, dem.vertical_datum], "dem: %d tiles, %d verified" % [dem.tiles.size(), verified])
	var coverage: Dictionary = drape.coverage
	_ok(coverage.x_min == CORE_X[0] and coverage.x_max == CORE_X[1] and coverage.z_min == CORE_Z[0] and coverage.z_max == CORE_Z[1], "coverage is the core: x %s..%s, z %s..%s (E 352-359 km × N 5577-5583 km)" % [coverage.x_min, coverage.x_max, coverage.z_min, coverage.z_max], "coverage is %s" % [coverage])
	var lattice: Dictionary = drape.lattice
	_ok(lattice.step_m == LATTICE_STEP_M and lattice.cols == LATTICE_COLS and lattice.rows == LATTICE_ROWS and lattice.heights.size() == LATTICE_COLS * LATTICE_ROWS, "lattice: %d × %d nodes at %s m = %d heights over the core" % [lattice.cols, lattice.rows, lattice.step_m, lattice.heights.size()], "lattice is %s × %s at %s" % [lattice.get("cols"), lattice.get("rows"), lattice.get("step_m")])
	var lowest := INF
	var highest := -INF
	for h: float in lattice.heights:
		lowest = minf(lowest, h)
		highest = maxf(highest, h)
	_ok(lowest > 300.0 and highest < 700.0, "the lattice's heights run %.2f..%.2f m: absolute DHHN2016 metres (the Eifel's valleys and hills)" % [lowest, highest], "lattice heights %.2f..%.2f" % [lowest, highest])


## Every drape segment a skeleton segment; every loop segment covered; the
## counts of the honest coverage (was -> cited when the pipeline changes).
func _check_segments(skeleton: Dictionary, drape: Dictionary, segments: Dictionary) -> void:
	var covered := 0
	var partial := 0
	var loop_covered := 0
	var ids := {}
	for raw: Dictionary in drape.segments:
		ids[raw.id] = raw
		covered += 1 if raw.covered else 0
		partial += 0 if raw.covered else 1
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	for id: String in loop.segments:
		loop_covered += 1 if ids.has(id) and ids[id].covered else 0
	_ok(covered + partial == drape.segments.size() and covered > 0, "%d segments in the drape: %d covered, %d partly inside the core (heights where they are, no labels), the other %d of the skeleton's %d outside it" % [drape.segments.size(), covered, partial, segments.size() - drape.segments.size(), segments.size()])
	_ok(loop_covered == loop.segments.size(), "every one of the loop's %d segments is covered (the Nordschleife lies inside the core)" % loop.segments.size(), "%d of %d loop segments covered" % [loop_covered, loop.segments.size()])
	var stations := 0
	for raw: Dictionary in drape.segments:
		stations += raw.dense.size()
	_ok(stations > 100000, "%d centre-height stations at 2 m along the covered roads" % stations)


## The crest/dip labels recounted here from the file's own dense heights
## by the mirrored rule equal the file's, segment for segment.
func _check_label_recount(drape: Dictionary, raw_points: Dictionary) -> void:
	var mismatches := 0
	var counted := 0
	var crests := 0
	var dips := 0
	var first := ""
	for raw: Dictionary in drape.segments:
		if not raw.covered:
			continue
		var xs := PackedFloat64Array()
		var zs := PackedFloat64Array()
		for point: Array in raw_points[raw.id]:
			xs.append(point[0])
			zs.append(point[1])
		var chain := WorldRoadProfile.chainages(xs, zs)
		var mine := WorldRoadProfile.labels_of(PackedFloat64Array(raw.dense), chain[chain.size() - 1])
		var theirs: Array = raw.labels.filter(func(label: Dictionary) -> bool: return label.kind != "bank")
		counted += 1
		for label: Dictionary in theirs:
			crests += 1 if label.kind == "crest" else 0
			dips += 1 if label.kind == "dip" else 0
		if JSON.stringify(mine) != JSON.stringify(theirs):
			mismatches += 1
			if first == "":
				first = "%s: recounted %s, file %s" % [raw.id, JSON.stringify(mine), JSON.stringify(theirs)]
	_ok(mismatches == 0 and counted > 0, "the labels recounted from the dense heights equal the file's on all %d covered segments (%d crests, %d dips; the 20 m curvature beyond 0.004 /m)" % [counted, crests, dips], "%d of %d segments' labels differ from a recount; first: %s" % [mismatches, counted, first])


## Every covered bridge segment's dense heights are linear between its
## abutments (data-pipeline.md §5), one line each.
func _check_bridges(drape: Dictionary, segments: Dictionary, raw_points: Dictionary) -> void:
	var bridges := 0
	for raw: Dictionary in drape.segments:
		if not raw.covered:
			continue
		var segment: SkeletonLoader.Segment = segments[raw.id]
		if not segment.tags.has("bridge") or segment.tags["bridge"] == "no":
			continue
		bridges += 1
		var h0: float = raw.dense[0]
		var h1: float = raw.dense[raw.dense.size() - 1]
		var stations := WorldRoadProfile.station_chainages(_length_of(raw_points[raw.id]))
		var worst := 0.0
		for k: int in raw.dense.size():
			var expected := h0 + (h1 - h0) * (stations[k] / stations[stations.size() - 1] if stations[stations.size() - 1] > 0.0 else 0.0)
			worst = maxf(worst, absf(raw.dense[k] - expected))
		_ok(worst <= 2.0 * HEIGHT_ROUNDING_M + 1e-9, "bridge %s (%s, %d stations): deck linear between abutments %.2f and %.2f m, worst %.3f m off" % [raw.id, segment.tags.get("name", segment.tags.get("ref", "unnamed")), raw.dense.size(), h0, h1, worst], "bridge %s: a station %.3f m off the deck's line" % [raw.id, worst])
	_ok(bridges > 0, "%d bridge segments draped in the core" % bridges)


## The Karussell: the bank's crossfall 30 % over the plateau, ramped over
## 30 m at each end from the neighbours' stitched plane values (the
## Karussell blend: the array is the mirror's karussell_crossfall of its
## own two end values, to the file's rounding), the one bank label with
## the R9 numbers and at 30 / to length - 30 / ramp_m 30, and the bowl
## read across the platform: a flat 1 m strip at the inside, 1.95 m up to
## the outside edge, the centre at the DEM's. was crossfall +0.30 at all
## 29 points and the label at 0 / to 152.915 (no ramp).
func _check_karussell(drape: Dictionary, profile: WorldRoadProfile) -> void:
	var record: Dictionary = {}
	for raw: Dictionary in drape.segments:
		if raw.id == "%d-0" % SkeletonLoader.KARUSSELL_WAY:
			record = raw
	if record.is_empty():
		_ok(false, "", "the Karussell (way %d) is not in the drape" % SkeletonLoader.KARUSSELL_WAY)
		return
	var banks: Array = record.labels.filter(func(label: Dictionary) -> bool: return label.kind == "bank")
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for point: Array in _raw_points(SkeletonLoader.read_file())[record.id]:
		xs.append(point[0])
		zs.append(point[1])
	var chain := WorldRoadProfile.chainages(xs, zs)
	var length := chain[chain.size() - 1]
	var expected := WorldRoadProfile.karussell_crossfall(PackedFloat64Array(record.crossfall), chain, 0.3)
	var ramped_right := true
	var plateau := 0
	var nearest_76 := 0
	for i: int in chain.size():
		ramped_right = ramped_right and floorf(expected[i] * 10000.0 + 0.5) / 10000.0 == float(record.crossfall[i])
		if chain[i] >= WorldRoadProfile.KARUSSELL_RAMP_M and chain[i] <= length - WorldRoadProfile.KARUSSELL_RAMP_M:
			plateau += 1
			ramped_right = ramped_right and record.crossfall[i] == 0.3
		if absf(chain[i] - 76.0) < absf(chain[nearest_76] - 76.0):
			nearest_76 = i
	var label_right: bool = banks.size() == 1 and banks[0] == {"at": WorldRoadProfile.KARUSSELL_RAMP_M, "kind": "bank", "to": floorf((length - WorldRoadProfile.KARUSSELL_RAMP_M) * 1000.0 + 0.5) / 1000.0, "bank": 0.3, "bowl_m": 6.5, "strip_m": 1.0, "ramp_m": WorldRoadProfile.KARUSSELL_RAMP_M}
	_ok(ramped_right and plateau >= 15 and record.crossfall[nearest_76] == 0.3 and record.crossfall[0] < 0.0 and record.crossfall[record.crossfall.size() - 1] < 0.0 and label_right, "the Karussell (%s): the crossfall ramped over 30 m from each end's stitched plane value (%+.4f at the entry, %+.4f at the exit: the neighbours' tilts in its frame) to +0.30 over the %d plateau points of its %d (the point nearest chainage 76 reads +0.3000), the array the mirror's ramp of its own ends to the file's rounding, one bank label 30 %% over 6.5 m with a 1 m strip at 30 / to %.3f / ramp_m 30 (branch (c), ring-region-decisions.md §3; was +0.30 at all 29 points, at 0 / to 152.915, before the Karussell blend)" % [record.id, record.crossfall[0], record.crossfall[record.crossfall.size() - 1], plateau, record.crossfall.size(), banks[0].get("to", 0.0) if banks.size() == 1 else 0.0], "the Karussell's crossfall %s, labels %s, ramped as the mirror says %s, plateau %d" % [record.crossfall, record.labels, ramped_right, plateau])
	var at: Vector2 = profile.point_along(record.id, 70.0)
	var ahead: Vector2 = profile.point_along(record.id, 71.0)
	var travel := (ahead - at).normalized()
	var right := Vector2(-travel.y, travel.x)
	var inside := profile.sample_height(at.x - 3.75 * right.x, at.y - 3.75 * right.y)
	var strip := profile.sample_height(at.x - 2.75 * right.x, at.y - 2.75 * right.y)
	var centre := profile.sample_height(at.x, at.y)
	var outside := profile.sample_height(at.x + 3.75 * right.x, at.y + 3.75 * right.y)
	var described := profile.describe(at.x, at.y)
	_ok(absf(strip - inside) < MM and absf(outside - inside - 1.95) < MM and absf(centre - described.centre) < MM and outside > centre and centre > inside, "across the bowl at chainage 70: inside edge %.2f, strip end %.2f (flat), centre %.2f (the DEM's), outside edge %.2f: 1.95 m of bank rising to the right of travel (a left-hander)" % [inside, strip, centre, outside], "across the bowl: %.3f %.3f %.3f %.3f" % [inside, strip, centre, outside])


## The reference heights, the sample points derived from the file (see the
## constants' note), and sample_height at those points returning them.
func _check_reference_heights(skeleton: Dictionary, drape: Dictionary, raw_points: Dictionary, profile: WorldRoadProfile) -> void:
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var records := {}
	for raw: Dictionary in drape.segments:
		records[raw.id] = raw
	var lowest := {"h": INF}
	var highest := {"h": -INF}
	var hohe_acht := -INF
	for id: String in loop.segments:
		var raw: Dictionary = records[id]
		var stations := WorldRoadProfile.station_chainages(_length_of(raw_points[id]))
		for k: int in raw.dense.size():
			var h: float = raw.dense[k]
			if h < lowest.h:
				lowest = {"h": h, "id": id, "s": stations[k]}
			if h > highest.h:
				highest = {"h": h, "id": id, "s": stations[k]}
		if id.begins_with("%d-" % HOHE_ACHT_WAY):
			for h: float in raw.dense:
				hohe_acht = maxf(hohe_acht, h)
	var low_at: Vector2 = profile.point_along(lowest.id, lowest.s)
	var high_at: Vector2 = profile.point_along(highest.id, highest.s)
	_ok(absf(lowest.h - BREIDSCHEID_M) <= REFERENCE_TOLERANCE_M, "Breidscheid: the loop's lowest sample is %.2f m at %s chainage %.0f (%.1f, %.1f), within %s ± %s m (was ~320 ± 5: the raw DGM1 ground there agrees to the centimetre)" % [lowest.h, lowest.id, lowest.s, low_at.x, low_at.y, BREIDSCHEID_M, REFERENCE_TOLERANCE_M], "Breidscheid: the loop's lowest sample is %.2f m at %s, not within %s ± %s" % [lowest.h, lowest.id, BREIDSCHEID_M, REFERENCE_TOLERANCE_M])
	_ok(absf(highest.h - LOOP_TOP_M) <= REFERENCE_TOLERANCE_M, "T13: the loop's highest sample is %.2f m at %s chainage %.0f (%.1f, %.1f), within %s ± %s m (was Hohe Acht ~620 ± 5)" % [highest.h, highest.id, highest.s, high_at.x, high_at.y, LOOP_TOP_M, REFERENCE_TOLERANCE_M], "the loop's highest sample is %.2f m at %s, not within %s ± %s" % [highest.h, highest.id, LOOP_TOP_M, REFERENCE_TOLERANCE_M])
	_ok(absf(hohe_acht - HOHE_ACHT_M) <= REFERENCE_TOLERANCE_M, "Hohe Acht (way %d): its top station is %.2f m, within the recorded %s ± %s m: the tiles and the datum are right" % [HOHE_ACHT_WAY, hohe_acht, HOHE_ACHT_M, REFERENCE_TOLERANCE_M], "Hohe Acht's top is %.2f m, not within %s ± %s" % [hohe_acht, HOHE_ACHT_M, REFERENCE_TOLERANCE_M])
	var low_sample := profile.sample_height(low_at.x, low_at.y)
	var high_sample := profile.sample_height(high_at.x, high_at.y)
	_ok(absf(low_sample - lowest.h) <= HEIGHT_ROUNDING_M and absf(high_sample - highest.h) <= HEIGHT_ROUNDING_M, "sample_height on the centreline returns those stations: %.3f and %.3f m" % [low_sample, high_sample], "sample_height returns %.3f and %.3f, the stations are %.2f and %.2f" % [low_sample, high_sample, lowest.h, highest.h])
	_ok(highest.h - lowest.h > 280.0 and highest.h - lowest.h < 310.0, "the loop climbs %.1f m from its lowest to its highest point (the recorded ~300 m)" % (highest.h - lowest.h))


func _length_of(points: Array) -> float:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for point: Array in points:
		xs.append(point[0])
		zs.append(point[1])
	var chain := WorldRoadProfile.chainages(xs, zs)
	return chain[chain.size() - 1]


## The world's gradient along the loop: past the pad's MAX_SLOPE, under the
## ceiling, and non-zero on the Hohe Acht climb. Measured only where the
## sample and its four taps all read the loop segment itself: where another
## road crosses at another layer (a bridge over a road: T13's 41395673-0
## over 421642912-0, 3.2 m below) the single-valued field steps to the
## nearest centreline's height, a documented limit of the profile (the
## assembler builds decks as their own meshes, 4B-4); those stations are
## counted, not measured. The stations within ABUTMENT_M of a bridge-tagged
## loop segment's end are measured apart: the DGM1 (a ground model, bridges
## removed) shows the valley floor for some metres past the OSM bridge way's
## ends, so the untagged approaches dip into that hole — measured 4B-3: 19
## loop stations, all at abutments (Breidscheid both sides, T13 / Sabine-
## Schmitz-Kurve, Döttinger Höhe, Hohenrain, Galgenkopf), up to 64 %; a
## known issue recorded for the Conductor (docs/night-shift-3.md, 4B-3),
## reported here, not hidden.
const ABUTMENT_M := 12.0
const ABUTMENT_SLOPE_CEILING := 0.70


func _check_slopes(skeleton: Dictionary, drape: Dictionary, raw_points: Dictionary, profile: WorldRoadProfile) -> void:
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var segments := SkeletonLoader.segments_of(skeleton)
	var abutments: Array[Vector2] = []
	for id: String in loop.segments:
		var segment: SkeletonLoader.Segment = segments[id]
		if segment.tags.has("bridge") and segment.tags["bridge"] != "no":
			abutments.append(segment.first())
			abutments.append(segment.last())
	var steepest := 0.0
	var where := ""
	var sampled := 0
	var crossings := 0
	var at_abutments := 0
	var abutment_steepest := 0.0
	var abutment_where := ""
	for id: String in loop.segments:
		var stations := WorldRoadProfile.station_chainages(_length_of(raw_points[id]))
		for k: int in range(0, stations.size(), 5):
			var at: Vector2 = profile.point_along(id, stations[k])
			var own := true
			for tap: Vector2 in [Vector2.ZERO, Vector2(-1.0, 0.0), Vector2(1.0, 0.0), Vector2(0.0, -1.0), Vector2(0.0, 1.0)]:
				own = own and profile.describe(at.x + tap.x, at.y + tap.y).road == id
			if not own:
				crossings += 1
				continue
			var slope := profile.ramp_gradient(at.x, at.y).length()
			var near_abutment := false
			for abutment: Vector2 in abutments:
				near_abutment = near_abutment or at.distance_to(abutment) <= ABUTMENT_M
			if near_abutment:
				at_abutments += 1
				if slope > abutment_steepest:
					abutment_steepest = slope
					abutment_where = "%s chainage %.0f" % [id, stations[k]]
				continue
			sampled += 1
			if slope > steepest:
				steepest = slope
				where = "%s chainage %.0f" % [id, stations[k]]
	_ok(steepest > PAD_MAX_SLOPE and steepest < LOOP_SLOPE_CEILING, "the loop's steepest gradient over %d stations on the loop's own roads away from bridge abutments is %.1f %% at %s: past the pad's MAX_SLOPE %.1f %% (the world profile exceeds it by design), under %.0f %%; %d stations skipped where another road is within a metre (a layer crossing or a junction)" % [sampled, 100.0 * steepest, where, 100.0 * PAD_MAX_SLOPE, 100.0 * LOOP_SLOPE_CEILING, crossings], "the loop's steepest gradient is %.3f at %s" % [steepest, where])
	_ok(abutment_steepest < ABUTMENT_SLOPE_CEILING, "at the %d stations within %.0f m of the loop's %d bridge abutments the steepest is %.1f %% at %s: the DGM1's bridge hole past the OSM bridge way's ends (a known issue, recorded; under %.0f %%)" % [at_abutments, ABUTMENT_M, abutments.size(), 100.0 * abutment_steepest, abutment_where, 100.0 * ABUTMENT_SLOPE_CEILING], "at an abutment the gradient is %.3f at %s" % [abutment_steepest, abutment_where])
	var at: Vector2 = profile.point_along("%d-1" % HOHE_ACHT_WAY, 20.0)
	var gradient := profile.ramp_gradient(at.x, at.y)
	_ok(gradient != Vector2.ZERO and gradient.length() > 0.02, "on the Hohe Acht way the gradient is (%.4f, %.4f): gravity has a share along the slope" % [gradient.x, gradient.y], "the Hohe Acht gradient is %s" % [gradient])
	var samples := PackedFloat64Array()
	for i: int in 200:
		var x := 1000.0 + (i * 37) % 5000
		var z := -5000.0 + (i * 53) % 4000
		samples.append(profile.sample_height(x, z))
	var same := true
	for i: int in 200:
		var x := 1000.0 + (i * 37) % 5000
		var z := -5000.0 + (i * 53) % 4000
		same = same and profile.sample_height(x, z) == samples[i]
	_ok(same, "pure: 200 samples asked twice come back bit for bit")
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	for h: float in samples:
		context.update(("%.6f\n" % h).to_utf8_buffer())
	var digest := context.finish().hex_encode()
	_ok(digest == SAMPLES_DIGEST, "the 200 samples read the same as at the ROAD-GEOMETRY FIX-NOW landing: sha256 %s (was ROAD-SMOOTHING's e5b34889..., 4B-3's b167c232... before it: the crossfall arrays regenerated, the heights the same; no covered segment is wider than 8.5 m, so the per-road reach changes nothing here)" % digest, "the 200 samples' digest is %s, pinned %s" % [digest, SAMPLES_DIGEST])
	_check_mirror_precision(skeleton)


## The mirror's station math in 64-bit floats: segment 1017207289-0 draped
## on the plane 400 + 0.05 x - 0.02 z has its chainage-4 station at a
## height of 698.02499711 m, a centimetre boundary; through a single-
## precision Vector2 the station moved a fraction of a millimetre and the
## file's 698.02 became 698.03 (the codex review's finding). The reader's
## value is held to a 64-bit interpolation done here and to the pipeline's.
func _check_mirror_precision(skeleton: Dictionary) -> void:
	var segments := SkeletonLoader.segments_of(skeleton)
	for raw: Dictionary in skeleton.segments:
		if raw.id != MIRROR_SEGMENT:
			continue
		var record: Variant = WorldRoadProfile.drape_segment(segments[raw.id], raw.points, func(x: float, z: float) -> Variant: return _plane(x, z))
		var xs := PackedFloat64Array()
		var zs := PackedFloat64Array()
		for point: Array in raw.points:
			xs.append(point[0])
			zs.append(point[1])
		var chain := WorldRoadProfile.chainages(xs, zs)
		var u := 4.0 / chain[1]
		var x64 := xs[0] + u * (xs[1] - xs[0])
		var z64 := zs[0] + u * (zs[1] - zs[0])
		var expected := floorf(_plane(x64, z64) * 100.0 + 0.5) / 100.0
		_ok(record.dense[2] == expected and record.dense[2] == MIRROR_HEIGHT_M, "the mirror drapes %s chainage 4 on the plane to %.2f m: the 64-bit interpolation's (%.8f m rounds to it), the pipeline's (was 698.03 through a Vector2)" % [MIRROR_SEGMENT, record.dense[2], _plane(x64, z64)], "the mirror gives %.2f at chainage 4, 64-bit says %.2f, the pipeline %.2f" % [record.dense[2], expected, MIRROR_HEIGHT_M])
		return
	_ok(false, "", "segment %s is not in the skeleton" % MIRROR_SEGMENT)


## Outside the coverage: height 0, gradient zero, mask 0; a tap outside
## makes the gradient zero at the edge; inside and off every road the
## lattice's terrain.
func _check_fallback(profile: WorldRoadProfile) -> void:
	_ok(profile.sample_height(-10.0, -10.0) == 0.0 and profile.ramp_gradient(-10.0, -10.0) == Vector2.ZERO and profile.elevation_mask(-10.0, -10.0) == 0.0 and profile.sample_height(7500.0, -3000.0) == 0.0 and profile.sample_height(3000.0, -6500.0) == 0.0, "outside the coverage (west of x = 0, east of 7000, north of z = -6000) the profile is flat: height 0, gradient (0, 0), mask 0")
	_ok(profile.ramp_gradient(0.5, -0.5) == Vector2.ZERO and profile.sample_height(0.5, -0.5) > 300.0 and profile.elevation_mask(0.5, -0.5) == 1.0, "half a metre inside the edge the height is the world's (%.2f m) and the gradient is zero: a tap outside makes no cliff" % profile.sample_height(0.5, -0.5))
	var described := profile.describe(6500.0, -100.0)
	_ok(described.road == "" and absf(described.height - profile.terrain_height(6500.0, -100.0)) < 1e-9 and described.height > 300.0, "off every road (%.0f, %.0f) the height is the lattice's terrain, %.2f m" % [6500.0, -100.0, described.height], "off-road describe: %s" % [described])


## ring() builds the same profile from the files.
func _check_ring(profile: WorldRoadProfile) -> void:
	var ring := WorldRoadProfile.ring()
	var same := ring != null and ring.road_count() == profile.road_count()
	for point: Vector2 in [Vector2(2247.813, -5557.306), Vector2(4800.0, -4960.0), Vector2(3000.0, -3000.0)]:
		same = same and ring != null and ring.sample_height(point.x, point.y) == profile.sample_height(point.x, point.y)
	_ok(same, "WorldRoadProfile.ring() reads the checked-in files into the same profile (%d roads)" % profile.road_count())
	_ok(profile.micro_amplitude == 0.0 and profile.test_dip_depth == 0.0 and profile.ramp_height == 0.0 and profile.swell_amplitude == 0.0 and profile.second_swell_amplitude == 0.0, "the pad's layers are zero on the world profile: no micro-bumps, no test dip, no licence ramp, no swells")


# =============================================================================
#  ROAD-SMOOTHING: THE FILE'S OWN EVIDENCE
# =============================================================================

## The raw file's numbers (b8d4e531..., before the smoothing), measured
## 2026-09-23 with the same arithmetic and pinned here as the "before".
## The loop's plain segments' station-to-station grade change (the 2 m
## second difference, |h[k+1] - 2 h[k] + h[k-1]| / 4 [1/m], taken at the
## UNIFORM stations only - both neighbouring intervals exactly 2 m; the
## codex review's F6: the end station past the last whole one is under
## a shorter interval and read as a 2 m one inflated the 99th percentile)
## at the 90th and 99th percentiles: 0.0075 and 0.0125 (1.5 % and 2.5 %
## per station; was 0.0075 / 0.0150 with the uneven ends counted); after
## the smoothing at most the centimetre rounding's own quantum 0.0025 and
## twice it.
const RAW_LOOP_KINK_P90 := 0.0075
const RAW_LOOP_KINK_P99 := 0.0125
const LOOP_KINK_P90_MAX := 0.0025
const LOOP_KINK_P99_MAX := 0.0050
## Junctions with two or more covered ends in the raw file: 2 158 of them
## had a crossfall gap over 2 % at 1 562 (29 on the loop), the largest
## 0.34 (the Karussell's bank, excluded from the stitch); the heights
## already agreed everywhere (the same DEM sample).
const RAW_CROSSFALL_GAP_JUNCTIONS := 1562
const RAW_CROSSFALL_GAP_LOOP := 29
## The driver's issue-0005 ("two tiles of the road connect, but one is
## higher than the other ... like a stair", car at x 1594.015 z -1218.086):
## junction 65386044, 1009142895-0's end onto 799394496-0's start, both
## at 585.23 m with crossfall -0.0077 and +0.04: the platform 4.25 m
## right of the centre stepped 0.255 m and 0.150 m left. Issue-0001 ("the
## road tile is very pointy", x 2017.926 z -1373.37): junction 312821860,
## the pit lane 199642470-0 meeting the loop at T13 with -0.04 against
## the loop's +0.04, a 0.340 m ridge at the paved edge.
const ISSUE_0005_JUNCTION := "65386044"
const ISSUE_0005_SEGMENTS := ["1009142895-0", "799394496-0"]
const ISSUE_0005_CAR := Vector2(1594.015, -1218.086)
const RAW_ISSUE_0005_STAIR_M := [0.255, 0.150]
const ISSUE_0001_JUNCTION := "312821860"
const ISSUE_0001_SEGMENTS := ["1009142894-0", "1009142894-1", "199642470-0"]
const ISSUE_0001_CAR := Vector2(2017.926, -1373.37)
const RAW_ISSUE_0001_RIDGE_M := 0.340
const STAIR_MAX_M := 0.005
## A written crossfall is the target tilt's component along the end's own
## right normal, rounded to 1e-4 in the file; the target recomputed here
## from rounded values may differ by another rounding.
const TILT_TOLERANCE := 2.0e-4
## drape.py's CLASS_RANK.
const CLASS_RANK := {"raceway": 0, "primary": 1, "primary_link": 2, "secondary": 3, "secondary_link": 4, "tertiary": 5, "tertiary_link": 6, "unclassified": 7, "residential": 8, "living_street": 9, "service": 10, "track": 11}
## The field probe across a seam: 5 cm along either segment at ±4 m; the
## grade over those 10 cm and the rounding allow this much.
const SEAM_PROBE_ALONG_M := 0.05
const SEAM_PROBE_OFFSET_M := 4.0
const SEAM_PROBE_MAX_M := 0.03
## The raw -> smoothed evidence over ±50 m along the owning segments at
## the three issue sites (the Conductor's requirement): the window's
## grade-change peak-to-peak [1/m] in the raw file (uniform stations only,
## re-measured for the codex review's F6: the same seven values), and the crest label
## in it with its amplitude over the 20 m window (h[k] - (h[k-5] +
## h[k+5]) / 2) in the raw file. Issue-0002's car stood on the bridge deck
## 41395681-0 (rigid: the deck is the same bytes) over the primary
## 828126276-0.
const WINDOW_HALF_M := 50.0
const WINDOWS := [
	{"issue": "issue-0001", "id": "199642470-0", "at": 46.9, "raw_p2p": 0.2675, "max_p2p": 0.2675, "raw_label": {"kind": "crest", "at": 10.0, "amplitude": 2.330}},
	{"issue": "issue-0001", "id": "1009142894-0", "at": 47.3, "raw_p2p": 0.2300, "max_p2p": 0.2300, "raw_label": {"kind": "crest", "at": 10.0, "amplitude": 2.275}},
	{"issue": "issue-0001", "id": "1009142894-1", "at": 0.0, "raw_p2p": 0.0150, "max_p2p": 0.0100, "raw_label": {}},
	{"issue": "issue-0002", "id": "41395681-0", "at": 24.1, "raw_p2p": 0.0050, "max_p2p": 0.0050, "raw_label": {}},
	{"issue": "issue-0002", "id": "828126276-0", "at": 13.1, "raw_p2p": 0.0550, "max_p2p": 0.0075, "raw_label": {}},
	{"issue": "issue-0005", "id": "1009142895-0", "at": 465.2, "raw_p2p": 0.0200, "max_p2p": 0.0075, "raw_label": {}},
	{"issue": "issue-0005", "id": "799394496-0", "at": 0.0, "raw_p2p": 0.0175, "max_p2p": 0.0075, "raw_label": {}},
]
const AMPLITUDE_KEPT_M := 0.011


func _check_smoothing(skeleton: Dictionary, drape: Dictionary, raw_points: Dictionary, profile: WorldRoadProfile) -> void:
	var records := {}
	for raw: Dictionary in drape.segments:
		records[raw.id] = raw
	var segments := SkeletonLoader.segments_of(skeleton)
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	# The loop's station-to-station grade change.
	var kinks := PackedFloat64Array()
	for id: String in loop.segments:
		var segment: SkeletonLoader.Segment = segments[id]
		if (segment.tags.has("bridge") and segment.tags["bridge"] != "no") or segment.tags.get("tunnel") == "yes":
			continue
		var dense: Array = records[id].dense
		var uniform := _uniform_count(_length_of(raw_points[id]))
		for k: int in range(1, uniform - 1):
			kinks.append(absf((dense[k + 1] - 2.0 * dense[k] + dense[k - 1]) / 4.0))
	kinks.sort()
	var p90: float = kinks[int(floor(0.9 * (kinks.size() - 1)))]
	var p99: float = kinks[int(floor(0.99 * (kinks.size() - 1)))]
	_ok(kinks.size() > 10000 and p90 <= LOOP_KINK_P90_MAX + 1e-9 and p99 <= LOOP_KINK_P99_MAX + 1e-9, "smoothing: over the loop's %d plain stations the station-to-station grade change is %.4f /m at the 90th percentile and %.4f at the 99th (%.1f %% and %.1f %% per 2 m station; was %.4f and %.4f in the raw file, %.1f %% and %.1f %%: the centimetre rounding's quantum is %.4f)" % [kinks.size(), p90, p99, 200.0 * p90, 200.0 * p99, RAW_LOOP_KINK_P90, RAW_LOOP_KINK_P99, 200.0 * RAW_LOOP_KINK_P90, 200.0 * RAW_LOOP_KINK_P99, LOOP_KINK_P90_MAX], "loop grade change p90 %.4f p99 %.4f over %d stations" % [p90, p99, kinks.size()])
	# Every junction's covered ends: one height; every plain non-bank end's
	# crossfall the node's world tilt seen in its own frame (the rule
	# mirrored: a rigid participant's tilt holds, else the class/loop
	# winners' mean of the plain ends' tilt vectors).
	var junctions := 0
	var height_gaps := 0
	var tilt_misses := 0
	var worst_height := 0.0
	var worst_tilt := 0.0
	var tilt_nodes := 0
	var rigid_nodes := 0
	var plain_ends := 0
	var stub_ends := 0
	var bank_ends := 0
	var first_miss := ""
	var loop_ids := {}
	for id: String in loop.segments:
		loop_ids[id] = true
	# Pass one: every junction's draped ends, with each end's crossfall
	# BEFORE the stitch recomputed from the skeleton's points through the
	# mirror's crossfall_of (was read back from the file's neighbour point,
	# which the stitch did not touch; the runoff after the stitch moves it
	# now), and the rigid tilt each node holds (a bridge's, a tunnel's, a
	# partly covered segment's: rigid_pick's order), for the stub rule.
	var originals := {}
	var node_ends := {}
	var junction_at_end := {}
	var rigid_tilt_at := {}
	for raw: Dictionary in skeleton.junctions:
		var heights := PackedFloat64Array()
		var ends: Array[Dictionary] = []
		for id: String in raw.segments:
			if not records.has(id):
				continue
			var points: Array = raw_points[id]
			var record: Dictionary = records[id]
			var at_start: bool = Vector2(points[0][0], points[0][1]).distance_to(Vector2(raw.x, raw.z)) < 1e-6
			var at_end: bool = Vector2(points[points.size() - 1][0], points[points.size() - 1][1]).distance_to(Vector2(raw.x, raw.z)) < 1e-6
			for start: bool in ([true] if at_start and not at_end else ([false] if at_end and not at_start else ([true, false] if at_start else []))):
				var end: int = 0 if start else record.dense.size() - 1
				var end_point: int = 0 if start else record.crossfall.size() - 1
				if record.dense[end] != null:
					heights.append(record.dense[end])
				junction_at_end["%s:%s" % [id, "0" if start else "1"]] = raw.id
				var right := _end_right_normal(points, start)
				if right == Vector2.ZERO:
					continue
				var segment: SkeletonLoader.Segment = segments[id]
				var rigid: bool = (segment.tags.has("bridge") and segment.tags["bridge"] != "no") or segment.tags.get("tunnel") == "yes" or not record.covered
				if not originals.has(id):
					var xs := PackedFloat64Array()
					var zs := PackedFloat64Array()
					for point: Array in points:
						xs.append(point[0])
						zs.append(point[1])
					originals[id] = WorldRoadProfile.crossfall_of(xs, zs)
				var mirrored: PackedFloat64Array = originals[id]
				var original: float = mirrored[end_point]
				ends.append({"id": id, "start": start, "rank": _class_rank(segment.road_class), "loop": loop_ids.has(id), "rigid": rigid, "bank": segments[id].osm_way == SkeletonLoader.KARUSSELL_WAY, "length": _length_of(points), "right": right, "cf": record.crossfall[end_point], "tilt": right * (float(record.crossfall[end_point]) if rigid else original)})
		if heights.size() >= 2:
			junctions += 1
			var gap: float = _span_of(heights)
			worst_height = maxf(worst_height, gap)
			if gap > 2.0 * HEIGHT_ROUNDING_M + 1e-9:
				height_gaps += 1
		node_ends[raw.id] = ends
		var rigid_here: Array[Dictionary] = ends.filter(func(e: Dictionary) -> bool: return e.rigid)
		if not rigid_here.is_empty():
			rigid_here.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a.rank, 0 if a.loop else 1, a.id, 0 if a.start else 1] < [b.rank, 0 if b.loop else 1, b.id, 0 if b.start else 1])
			rigid_tilt_at[raw.id] = rigid_here[0].tilt
	# Pass two: the node's tilt (the stitch's rule mirrored: a rigid
	# participant's own - a stub between a rigid end and this node holding
	# that rigid tilt counts as one, the stub rule - else the class/loop
	# winners' mean of the plain ends' pre-stitch tilt vectors; the
	# Karussell's bank does not vote) and every plain, stub and bank end
	# carrying it in its own frame.
	var targets := {}
	for raw: Dictionary in skeleton.junctions:
		var ends: Array[Dictionary] = node_ends.get(raw.id, [] as Array[Dictionary])
		if ends.size() < 2:
			continue
		for e: Dictionary in ends:
			e["stub"] = false
			if e.rigid or e.bank or e.length >= WorldRoadProfile.HAIRPIN_SUPERELEVATION_MAX / WorldRoadProfile.SUPERELEVATION_RUNOFF_PER_M:
				continue
			var other: String = junction_at_end.get("%s:%s" % [e.id, "1" if e.start else "0"], "")
			if other != "" and other != raw.id and rigid_tilt_at.has(other):
				e["stub"] = true
				e["tilt"] = rigid_tilt_at[other]
		var plain: Array[Dictionary] = ends.filter(func(e: Dictionary) -> bool: return not e.rigid and not e.bank and not e.stub)
		var genuine: Array[Dictionary] = ends.filter(func(e: Dictionary) -> bool: return e.rigid)
		var stubs: Array[Dictionary] = ends.filter(func(e: Dictionary) -> bool: return e.stub)
		# A genuine rigid participant outranks a held stub; a node with
		# nothing writable (plain, stub or bank) is skipped, and so is one
		# with nothing to take a tilt from (the codex cross-review's F1:
		# a node holding only rigid participants and held stubs used to be
		# skipped and the stub kept its 0 against the deck).
		var rigid_ends: Array[Dictionary] = genuine if not genuine.is_empty() else stubs
		var banks: Array[Dictionary] = ends.filter(func(e: Dictionary) -> bool: return e.bank and not e.rigid)
		if plain.is_empty() and banks.is_empty() and stubs.is_empty():
			continue
		if plain.is_empty() and rigid_ends.is_empty():
			continue
		var target := Vector2.ZERO
		if not rigid_ends.is_empty():
			rigid_ends.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return [a.rank, 0 if a.loop else 1, a.id, 0 if a.start else 1] < [b.rank, 0 if b.loop else 1, b.id, 0 if b.start else 1])
			target = rigid_ends[0].tilt
			rigid_nodes += 1
		else:
			var best_rank := 99
			for e: Dictionary in plain:
				best_rank = mini(best_rank, e.rank)
			var winners: Array[Dictionary] = plain.filter(func(e: Dictionary) -> bool: return e.rank == best_rank)
			var on_loop: Array[Dictionary] = winners.filter(func(e: Dictionary) -> bool: return e.loop)
			if not on_loop.is_empty():
				winners = on_loop
			for e: Dictionary in winners:
				target += e.tilt
			target /= winners.size()
		tilt_nodes += 1
		targets[raw.id] = target
		for e: Dictionary in ends:
			if e.rigid:
				continue
			if e.stub:
				stub_ends += 1
			elif e.bank:
				bank_ends += 1
			else:
				plain_ends += 1
			var miss: float = absf(e.cf - target.dot(e.right))
			worst_tilt = maxf(worst_tilt, miss)
			if miss > TILT_TOLERANCE:
				tilt_misses += 1
				if first_miss == "":
					first_miss = "node %s: %s %s cf %.4f vs the target's %.5f (target %s from %s)" % [raw.id, e.id, "start" if e.start else "end", e.cf, target.dot(e.right), target, ends]
	_ok(junctions > 2000 and height_gaps == 0 and tilt_nodes > 2000 and tilt_misses == 0 and stub_ends > 0 and bank_ends == 2, "junctions: at all %d nodes with two or more draped ends the ends' centre heights agree to the centimetre (the largest gap %.3f m); at all %d nodes with two or more ends every one of the %d plain ends carries the node's world tilt in its own frame - a rigid participant's own (bridge, tunnel, partly covered, or a stub under %.0f m holding one through: %d nodes, %d stub ends) else the class/loop winners' mean of the ends' own pre-stitch tilts (each recomputed from the skeleton's points through the mirror's crossfall_of; was read back from the neighbour point, which the runoff now moves) - and so do the Karussell's %d ends, which do not vote - within %.4f (the worst %.5f; was a crossfall gap over 2 %% at %d junctions, %d of them on the loop: each segment's end took its own bend's crossfall; and, with the first stitch, one signed value written to every frame)" % [junctions, worst_height, tilt_nodes, plain_ends, WorldRoadProfile.HAIRPIN_SUPERELEVATION_MAX / WorldRoadProfile.SUPERELEVATION_RUNOFF_PER_M, rigid_nodes, stub_ends, bank_ends, TILT_TOLERANCE, worst_tilt, RAW_CROSSFALL_GAP_JUNCTIONS, RAW_CROSSFALL_GAP_LOOP], "%d height gaps (worst %.3f), %d tilt misses (worst %.5f) over %d / %d junctions, %d stub ends, %d bank ends; the first: %s" % [height_gaps, worst_height, tilt_misses, worst_tilt, junctions, tilt_nodes, stub_ends, bank_ends, first_miss])
	# Issue-0005's stair, from the file and from the field.
	var a: Dictionary = records[ISSUE_0005_SEGMENTS[0]]
	var b: Dictionary = records[ISSUE_0005_SEGMENTS[1]]
	var stair_right: float = absf(_edge_height(a, a.dense.size() - 1, a.crossfall.size() - 1, 4.25) - _edge_height(b, 0, 0, 4.25))
	var stair_left: float = absf(_edge_height(a, a.dense.size() - 1, a.crossfall.size() - 1, -4.25) - _edge_height(b, 0, 0, -4.25))
	var nearest_5: Dictionary = profile.describe(ISSUE_0005_CAR.x, ISSUE_0005_CAR.y)
	_ok(nearest_5.get("road") == ISSUE_0005_SEGMENTS[0] and absf(nearest_5.get("chainage", 0.0) - 465.2) < 0.5 and a.dense[a.dense.size() - 1] == b.dense[0] and absf(a.crossfall[a.crossfall.size() - 1] - b.crossfall[0]) <= TILT_TOLERANCE and stair_right <= STAIR_MAX_M and stair_left <= STAIR_MAX_M, "issue-0005 (\"like a stair\", the car at (%.3f, %.3f) on %s chainage %.1f, %.2f m from its centreline): at junction %s %s ends and %s starts at one centre height %.2f m and one tilt (crossfall %+.4f and %+.4f in their own frames, 2° apart), so the platform's edges 4.25 m out meet within %.3f m right and %.3f m left (was %.3f m and %.3f m: crossfall -0.0077 against +0.04 at one height)" % [ISSUE_0005_CAR.x, ISSUE_0005_CAR.y, nearest_5.get("road"), nearest_5.get("chainage", 0.0), nearest_5.get("distance", 0.0), ISSUE_0005_JUNCTION, ISSUE_0005_SEGMENTS[0], ISSUE_0005_SEGMENTS[1], b.dense[0], a.crossfall[a.crossfall.size() - 1], b.crossfall[0], stair_right, stair_left, RAW_ISSUE_0005_STAIR_M[0], RAW_ISSUE_0005_STAIR_M[1]], "issue-0005: heights %s / %s, crossfall %s / %s, stair %.3f / %.3f, the car over %s" % [a.dense[a.dense.size() - 1], b.dense[0], a.crossfall[a.crossfall.size() - 1], b.crossfall[0], stair_right, stair_left, nearest_5.get("road")])
	var probe := _seam_probe(profile, raw_points[ISSUE_0005_SEGMENTS[0]], raw_points[ISSUE_0005_SEGMENTS[1]])
	_ok(probe.worst <= SEAM_PROBE_MAX_M, "issue-0005 in the field: sample_height %.2f m before and after the node at %.0f m left, on the centreline and %.0f m right steps %.3f, %.3f and %.3f m (the grade over those %.1f m and the rounding; a stair of 0.15-0.26 m read here before)" % [SEAM_PROBE_ALONG_M, SEAM_PROBE_OFFSET_M, SEAM_PROBE_OFFSET_M, probe.steps[0], probe.steps[1], probe.steps[2], 2.0 * SEAM_PROBE_ALONG_M], "the field steps %s across the seam" % [probe.steps])
	# Issue-0001's ridge at T13.
	var pit: Dictionary = records[ISSUE_0001_SEGMENTS[2]]
	var loop_in: Dictionary = records[ISSUE_0001_SEGMENTS[0]]
	var loop_out: Dictionary = records[ISSUE_0001_SEGMENTS[1]]
	var right_in := _end_right_normal(raw_points[ISSUE_0001_SEGMENTS[0]], false)
	var right_out := _end_right_normal(raw_points[ISSUE_0001_SEGMENTS[1]], true)
	var right_pit := _end_right_normal(raw_points[ISSUE_0001_SEGMENTS[2]], false)
	# The loop's tilt at the node: the stitch's own target, from the pass
	# above (was reconstructed as the mean of the two loop ends' written
	# tilt vectors, exact only when their right normals coincide).
	var loop_tilt: Vector2 = targets.get(ISSUE_0001_JUNCTION, (right_in * loop_in.crossfall[loop_in.crossfall.size() - 1] + right_out * loop_out.crossfall[0]) / 2.0)
	var pit_cf: float = pit.crossfall[pit.crossfall.size() - 1]
	# The pit lane's tilt against the loop's, both in world space, as an
	# edge height 4.25 m out along the pit lane's own right normal: the
	# ridge the driver saw (was -0.04 against +0.04 in the pit lane's
	# frame at a 0.9 rad join).
	var ridge: float = absf(pit_cf - loop_tilt.dot(right_pit)) * 4.25
	var nearest_1: Dictionary = profile.describe(ISSUE_0001_CAR.x, ISSUE_0001_CAR.y)
	_ok(nearest_1.get("distance", 99.0) < 4.25 and absf(pit_cf - loop_tilt.dot(right_pit)) <= TILT_TOLERANCE and pit.dense[pit.dense.size() - 1] == loop_out.dense[0] and ridge <= STAIR_MAX_M, "issue-0001 (\"very pointy\", the car at (%.3f, %.3f) over %s, %.2f m from its centreline, %.2f m from the T13 junction %s): the pit lane %s ends on the loop's node at the loop's height %.2f m and carries the loop's world tilt (%.4f, %.4f) in its own frame, crossfall %+.4f = the tilt's component along its right normal (%.3f, %.3f), the join %.2f rad off the loop's line (was -0.04 against the loop's +0.04: a %.3f m ridge at the paved edge; now %.4f m)" % [ISSUE_0001_CAR.x, ISSUE_0001_CAR.y, nearest_1.get("road"), nearest_1.get("distance", 0.0), ISSUE_0001_CAR.distance_to(Vector2(2015.436, -1370.741)), ISSUE_0001_JUNCTION, ISSUE_0001_SEGMENTS[2], loop_out.dense[0], loop_tilt.x, loop_tilt.y, pit_cf, right_pit.x, right_pit.y, right_pit.angle_to(right_out), RAW_ISSUE_0001_RIDGE_M, ridge], "issue-0001: pit crossfall %s vs the loop tilt's component %.5f, heights %s / %s, ridge %.4f, the car over %s" % [pit_cf, loop_tilt.dot(right_pit), pit.dense[pit.dense.size() - 1], loop_out.dense[0], ridge, nearest_1.get("road")])
	# The ±50 m windows at the three sites.
	for window: Dictionary in WINDOWS:
		var record: Dictionary = records[window.id]
		var stations := WorldRoadProfile.station_chainages(_length_of(raw_points[window.id]))
		var uniform := _uniform_count(_length_of(raw_points[window.id]))
		var inside: Array[int] = []
		for k: int in uniform:
			if absf(stations[k] - window.at) <= WINDOW_HALF_M:
				inside.append(k)
		var changes := PackedFloat64Array()
		for k: int in inside:
			if k >= 1 and k <= uniform - 2:
				changes.append((record.dense[k + 1] - 2.0 * record.dense[k] + record.dense[k - 1]) / 4.0)
		var p2p: float = _span_of(changes)
		var label_text := ""
		var label_ok := true
		var raw_label: Dictionary = window.raw_label
		if not raw_label.is_empty():
			var k := int(round(raw_label.at / WorldRoadProfile.STATION_STEP_M))
			var amplitude: float = record.dense[k] - 0.5 * (record.dense[k - 5] + record.dense[k + 5])
			var labelled := false
			for label: Dictionary in record.labels:
				labelled = labelled or (label.kind == raw_label.kind and label.at == raw_label.at)
			label_ok = labelled and absf(amplitude - raw_label.amplitude) <= AMPLITUDE_KEPT_M
			label_text = "; the raw file's %s label at chainage %.0f is still there and its amplitude over the 20 m window is %.3f m (raw %.3f m, kept within %.3f m: the run is held to the raw heights)" % [raw_label.kind, raw_label.at, amplitude, raw_label.amplitude, AMPLITUDE_KEPT_M]
		_ok(inside.size() >= 10 and p2p <= window.max_p2p + 1e-9 and p2p <= window.raw_p2p + 1e-9 and label_ok, "%s, %s over %.0f..%.0f m (%d uniform stations, %d second differences): the grade-change peak-to-peak is %.4f /m, %.1f %% per station (raw %.4f, %.1f %%; at most %.4f asked)%s" % [window.issue, window.id, stations[inside[0]], stations[inside[inside.size() - 1]], inside.size(), changes.size(), p2p, 200.0 * p2p, window.raw_p2p, 200.0 * window.raw_p2p, window.max_p2p, label_text], "%s %s: p2p %.4f (raw %.4f, max %.4f), label ok %s" % [window.issue, window.id, p2p, window.raw_p2p, window.max_p2p, label_ok])


## The unit vector to the right of travel at a segment's end (x-east /
## z-south: right = (-tz, tx)), from the end's first non-degenerate chord
## walking inward; Vector2.ZERO when every chord is zero (drape.py's
## end_right_normal).
static func _end_right_normal(points: Array, start: bool) -> Vector2:
	var n := points.size()
	for i: int in range(n - 1):
		var p: Array = points[i] if start else points[n - 2 - i]
		var q: Array = points[i + 1] if start else points[n - 1 - i]
		var dx: float = q[0] - p[0]
		var dz: float = q[1] - p[1]
		var length := sqrt(dx * dx + dz * dz)
		if length > 0.0:
			return Vector2(-dz / length, dx / length)
	return Vector2.ZERO


static func _class_rank(road_class: String) -> int:
	return CLASS_RANK.get(road_class, CLASS_RANK.size())


## The uniform stations of a segment: 0, 2, ... up to the last whole one
## (the end station past it, if any, is under a shorter interval).
static func _uniform_count(length: float) -> int:
	return floori(length / WorldRoadProfile.STATION_STEP_M + 1e-9) + 1


## The largest value less the smallest.
static func _span_of(values: PackedFloat64Array) -> float:
	var lowest := INF
	var highest := -INF
	for v: float in values:
		lowest = minf(lowest, v)
		highest = maxf(highest, v)
	return highest - lowest


## The platform's height at a record's end station, `offset` metres right
## of the centre: the file's centre height plus the crossfall's shape
## (world_road_profile.gd's _platform_height without the bank).
static func _edge_height(record: Dictionary, station: int, point: int, offset: float) -> float:
	var e: float = record.crossfall[point]
	var crown_share := 1.0 - minf(absf(e) / WorldRoadProfile.CROWN, 1.0)
	return record.dense[station] + e * offset - crown_share * WorldRoadProfile.CROWN * absf(offset)


## The field just before and just after the node where segment `a` ends
## and `b` starts, at -4, 0 and +4 m right of travel: the three steps and
## the worst.
static func _seam_probe(profile: WorldRoadProfile, a: Array, b: Array) -> Dictionary:
	var node := Vector2(a[a.size() - 1][0], a[a.size() - 1][1])
	var da := (node - Vector2(a[a.size() - 2][0], a[a.size() - 2][1])).normalized()
	var db := (Vector2(b[1][0], b[1][1]) - node).normalized()
	var steps := PackedFloat64Array()
	var worst := 0.0
	for o: float in [-SEAM_PROBE_OFFSET_M, 0.0, SEAM_PROBE_OFFSET_M]:
		var before := node - da * SEAM_PROBE_ALONG_M + Vector2(-da.y, da.x) * o
		var after := node + db * SEAM_PROBE_ALONG_M + Vector2(-db.y, db.x) * o
		var step := absf(profile.sample_height(after.x, after.y) - profile.sample_height(before.x, before.y))
		steps.append(step)
		worst = maxf(worst, step)
	return {"steps": steps, "worst": worst}


# =============================================================================
#  THE ROAD-GEOMETRY FIX-NOW FENCES (2026-09-25, issues-analysis-2026-09-24.md)
# =============================================================================

## The Karussell's two junctions (entry: 799394513-1 -> 414785755-0, exit:
## 414785755-0 -> 414785756-0) and the 0007 site, probed along the roads'
## own centrelines every PROBE_STEP_M at the nine offsets: the largest
## one-step height jump at any offset; the loop's crossfall twist per
## chord from the file's arrays.
const KARUSSELL_ENTRY := ["799394513-1", "414785755-0"]
const KARUSSELL_EXIT := ["414785755-0", "414785756-0"]
const ISSUE_0007_SEGMENT := "799394513-1"
const ISSUE_0007_RANGE_M := [30.0, 60.0]
const PROBE_STEP_M := 0.25
const PROBE_REACH_M := 10.0
const PROBE_OFFSETS: Array[float] = [-3.75, -3.0, -2.0, -1.0, 0.0, 1.0, 2.0, 3.0, 3.75]
## The fences (the doc's, §3.3 (a) and §4.2): no one-step over this at
## either Karussell junction (was 1.211 m at +3.75 at the entry, 1.281 m
## at the exit) nor at the 0007 site (was 0.342 m at +3.75 at chainage
## 44.7-45.2, the notch's other flank -0.335 at 45.5); no loop chord
## twisting over this (was 19 chords over, the top 0.940 m/m at
## 799394513-1 point 8).
const SEAM_STEP_MAX_M := 0.05
const LOOP_TWIST_MAX := 0.02
const CENTRE_LINE_TOLERANCE_M := 1e-9


func _check_geometry_fences(skeleton: Dictionary, drape: Dictionary, raw_points: Dictionary, profile: WorldRoadProfile) -> void:
	var records := {}
	for raw: Dictionary in drape.segments:
		records[raw.id] = raw
	var segments := SkeletonLoader.segments_of(skeleton)
	# The two Karussell junctions.
	for pair: Array in [KARUSSELL_ENTRY, KARUSSELL_EXIT]:
		var into: Dictionary = _geometry(raw_points[pair[0]])
		into.id = pair[0]
		var out_of: Dictionary = _geometry(raw_points[pair[1]])
		out_of.id = pair[1]
		var worst := 0.0
		var worst_where := ""
		var centre_off := 0.0
		var samples := 0
		for offset: float in PROBE_OFFSETS:
			var previous := NAN
			var track: Array = []
			var s: float = into.length - PROBE_REACH_M
			while s <= into.length + 1e-9:
				track.append([into, s])
				s += PROBE_STEP_M
			s = 0.0
			while s <= PROBE_REACH_M + 1e-9:
				track.append([out_of, s])
				s += PROBE_STEP_M
			for at: Array in track:
				var g: Dictionary = at[0]
				var p := _point_on(g.xs, g.zs, g.chain, at[1])
				var travel := _direction_on(g.xs, g.zs, g.chain, at[1])
				var right := Vector2(-travel.y, travel.x)
				var h := profile.sample_height(p[0] + right.x * offset, p[1] + right.y * offset)
				samples += 1
				if offset == 0.0:
					centre_off = maxf(centre_off, absf(h - profile.describe(p[0], p[1]).get("centre", NAN)))
				if is_finite(previous):
					var step := absf(h - previous)
					if step > worst:
						worst = step
						worst_where = "%+.2f m at %s chainage %.2f" % [offset, g.id, at[1]]
				previous = h
		var name := "entry" if pair == KARUSSELL_ENTRY else "exit"
		_ok(samples > 0 and worst <= SEAM_STEP_MAX_M and centre_off <= CENTRE_LINE_TOLERANCE_M, "the Karussell's %s junction (%s -> %s), probed every %.2f m over ±%.0f m at the nine offsets -3.75..+3.75 (%d samples): the largest one-step height jump is %.3f m (%s), under %.2f m (was %s: the bank met the neighbour's plane as an edge wall); the centre line the file's own dense heights (%.10f m off at most: the blend touches the cross-section only)" % [name, pair[0], pair[1], PROBE_STEP_M, PROBE_REACH_M, samples, worst, worst_where, SEAM_STEP_MAX_M, "-0.878 / +1.211 m at ∓3.75" if name == "entry" else "+1.269 / -1.281 m at ∓3.75", centre_off], "the Karussell's %s: the largest step %.3f m %s, the centre %.10f off" % [name, worst, worst_where, centre_off])
	# The 0007 site.
	var site: Dictionary = _geometry(raw_points[ISSUE_0007_SEGMENT])
	var site_worst := 0.0
	var site_where := ""
	for offset: float in PROBE_OFFSETS:
		var previous := NAN
		var s: float = ISSUE_0007_RANGE_M[0]
		while s <= ISSUE_0007_RANGE_M[1] + 1e-9:
			var p := _point_on(site.xs, site.zs, site.chain, s)
			var travel := _direction_on(site.xs, site.zs, site.chain, s)
			var right := Vector2(-travel.y, travel.x)
			var h := profile.sample_height(p[0] + right.x * offset, p[1] + right.y * offset)
			if is_finite(previous) and absf(h - previous) > site_worst:
				site_worst = absf(h - previous)
				site_where = "%+.2f m at chainage %.2f" % [offset, s]
			previous = h
			s += PROBE_STEP_M
	_ok(site_worst <= SEAM_STEP_MAX_M, "the 0007 site (%s chainage %.0f-%.0f, the \"rear tyres suspended\" notch): the largest one-step height jump at any of the nine offsets is %.3f m (%s), under %.2f m (was 0.342 m at +3.75 at chainage 44.7-45.2 and -0.335 at 45.5: the crossfall flipping -0.04 -> +0.04 -> -0.06 inside the 0.45 m chord at point 8)" % [ISSUE_0007_SEGMENT, ISSUE_0007_RANGE_M[0], ISSUE_0007_RANGE_M[1], site_worst, site_where, SEAM_STEP_MAX_M], "the 0007 site: the largest step %.3f m %s" % [site_worst, site_where])
	# The loop's crossfall twist per chord.
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var chords := 0
	var over := 0
	var top := 0.0
	var top_where := ""
	for id: String in loop.segments:
		var segment: SkeletonLoader.Segment = segments[id]
		if segment.osm_way == SkeletonLoader.KARUSSELL_WAY:
			continue
		var g: Dictionary = _geometry(raw_points[id])
		var crossfall: Array = records[id].crossfall
		for i: int in range(1, crossfall.size()):
			var chord: float = g.chain[i] - g.chain[i - 1]
			if chord <= 0.0:
				continue
			chords += 1
			var twist: float = absf(float(crossfall[i]) - float(crossfall[i - 1])) * segment.width_m * 0.5 / chord
			if twist > LOOP_TWIST_MAX:
				over += 1
			if twist > top:
				top = twist
				top_where = "%s point %d (chord %.2f m, %+.4f -> %+.4f)" % [id, i - 1, chord, crossfall[i - 1], crossfall[i]]
	_ok(chords > 900 and over == 0, "the loop's crossfall twist: over the %d chords of its %d non-bank segments no chord twists the paved edge over %.2f m/m - the top %.4f m/m at %s (was 19 chords over, 7 over 0.05, the top 0.940 at 799394513-1 point 8: the crossfall-twist rule's window and runoff, drape.py)" % [chords, loop.segments.size() - 1, LOOP_TWIST_MAX, top, top_where], "%d of %d loop chords twist over %.2f, the top %.4f at %s" % [over, chords, LOOP_TWIST_MAX, top, top_where])


## A segment's 64-bit geometry from its raw points.
static func _geometry(points: Array) -> Dictionary:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for point: Array in points:
		xs.append(point[0])
		zs.append(point[1])
	var chain := WorldRoadProfile.chainages(xs, zs)
	return {"xs": xs, "zs": zs, "chain": chain, "length": chain[chain.size() - 1], "id": ""}


static func _point_on(xs: PackedFloat64Array, zs: PackedFloat64Array, chain: PackedFloat64Array, s: float) -> PackedFloat64Array:
	for i: int in range(1, chain.size()):
		if chain[i] >= s:
			var span := chain[i] - chain[i - 1]
			var u := 0.0 if span <= 0.0 else (s - chain[i - 1]) / span
			return PackedFloat64Array([xs[i - 1] + u * (xs[i] - xs[i - 1]), zs[i - 1] + u * (zs[i] - zs[i - 1])])
	return PackedFloat64Array([xs[xs.size() - 1], zs[zs.size() - 1]])


## The unit direction of travel at chainage s: the chord's.
static func _direction_on(xs: PackedFloat64Array, zs: PackedFloat64Array, chain: PackedFloat64Array, s: float) -> Vector2:
	for i: int in range(1, chain.size()):
		if chain[i] >= s and chain[i] > chain[i - 1]:
			return Vector2(xs[i] - xs[i - 1], zs[i] - zs[i - 1]).normalized()
	return Vector2(xs[xs.size() - 1] - xs[xs.size() - 2], zs[zs.size() - 1] - zs[zs.size() - 2]).normalized()


# =============================================================================
#  THE JUNCTION RIGHT OF WAY (issues-analysis-2026-09-24.md §4.4)
# =============================================================================

## The loop's paved width is 8.5 m: the nine offsets of PROBE_OFFSETS lie
## inside it. Every junction of the loop whose segments include a covered
## non-loop road (44 of 92 on the checked-in files; the analysis's
## population) is probed the Karussell way: the loop segment into the node
## over its last PROBE_JUNCTION_M, the loop segment out of it over its
## first, at PROBE_STEP_M, at each offset; a station is FOREIGN when a
## non-loop road answers it. Measured on the corrected field before the
## right of way (this tree, priority cleared on every road, which is the
## old rule to the bit): 4 690 foreign stations at the 44 junctions and
## 172 at the other 48 (parallel roads within reach), the largest one-step
## jump 0.625 m (junction 65385912, +3.75), 7 junctions over the loop's
## own kink bound. After: 0 and 0, every junction under the bound, the
## largest 0.136 m at 65387230. With the profile's rule alone the T13
## four-way junction 65385912 kept 0.216 m on the centreline itself
## (offset 0): the rim walk from Hohenrain's east abutment had left the
## loop there for the Boxengasse 769107218-0 (the smaller turn) and lifted
## that branch, while the loop's own 41395670-1 stayed at the file's
## 9.5 % start, 0.24 m under the lifted stub's end - masked before the
## right of way because the branch's lifted chord answered the loop's
## edge and the ±1 m taps at those stations (the ring drive test's rim
## fence read 9 stations there, not 12). The walk now stays on the loop
## (road_builder.gd, CONTINUATION_MAX_TURN_DEG's note): the same rim
## 8.13 m out, 619.09 m, along 41395670-1; that junction reads under
## the bound and the centreline steps by the grade alone.
const PROBE_JUNCTION_M := 6.0
## The loop's own kink bound: the largest step across a bisector on the
## loop's own roads (night-shift-3 line 111, known issue (3)).
const JUNCTION_STEP_MAX_M := 0.197
const T13_JUNCTION := "65385912"
const JUNCTIONS_WITH_SIDE_ROAD := 44
const LOOP_ROADS := 92
## The driver's sites: the loop segment into the junction, the one out of
## it, the car's own offset (0 where the flag point is not on the track),
## and what the field read at the worst offset before (this probe, the
## corrected field): 0012 the service road 1549311960-0 at junction
## 65387230 (0.474 at +3.75, 0.264 at +3, 0.181 at the car's +1.37; the
## analysis: 0.261 at +3); 0018 the service road 696037694-0 at junction
## 2084978602 (0.377 at -3.00, 0.223 at the car's -1.44; the analysis:
## 0.417 at -3.75); 0017 the private service road 198509975-0 at junction
## 1714130368 (0.080 at -3.75); 0001-residual the pit lane 199642470-0 at
## junction 312821860 (the pit lane answering at offsets >= +1: 0.034 at
## +3.75 here, the analysis's 0.099 at +1 / 0.070 at +3.75 over its own
## window). 0021-part is the Hohenrain deck 41395668-0 with the parallel
## Boxengasse-an-T13 bridge 32894824-0 answering its +3.75 edge from
## chainage 7.8 (0.469 here, the analysis's 0.488): probed over the whole
## deck, no junction.
const SITE_0012 := ["245166664-0", "245166664-1", 1.37]
const SITE_0018 := ["799394519-0", "799394519-1", -1.44]
const SITE_0017 := ["414785756-1", "414785756-2", 3.43]
const SITE_0001 := ["1009142894-0", "1009142894-1", 1.0]
const SITE_0021_DECK := "41395668-0"
## What a site may step after: the honest grade over a 0.25 m station
## (0012's 16 % is 0.040) and the file's rounding.
const SITE_STEP_MAX_M := 0.05
## The loop's own wedge at the 0012 junction 65387230: a 7° kink on the
## 16 % grade, where the two loop platforms' chainages of one world point
## differ by ~0.46 m at the +3.75 edge - 0.130 m there, 0.067 at the car's
## +1.37, every station read from a loop road. Not the side road's (that
## read 0.474) and not this rule's to remove: bounded.
const SITE_0012_WEDGE_MAX_M := 0.15


## The right of way on the real files: the flags, the 44 junctions, the
## five sites.
func _check_right_of_way(skeleton: Dictionary, drape: Dictionary, raw_points: Dictionary, profile: WorldRoadProfile) -> void:
	var segments := SkeletonLoader.segments_of(skeleton)
	var loop: SkeletonLoader.Loop = SkeletonLoader.loops_of(skeleton)[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var in_loop := {}
	for id: String in loop.segments:
		in_loop[id] = true
	# The flags, read through describe() at every covered segment's midpoint.
	var loop_priority := 0
	var other_priority := 0
	var answered := 0
	var covered := {}
	for raw: Dictionary in drape.segments:
		if not raw.get("covered", false) or not segments.has(raw.id):
			continue
		covered[raw.id] = true
		var g: Dictionary = _geometry(raw_points[raw.id])
		var mid := _point_on(g.xs, g.zs, g.chain, 0.5 * g.length)
		var described := profile.describe(mid[0], mid[1])
		if described.road != raw.id:
			continue
		answered += 1
		if described.get("priority", false):
			if in_loop.has(raw.id):
				loop_priority += 1
			else:
				other_priority += 1
	_ok(loop_priority == LOOP_ROADS and loop_priority == loop.segments.size() and other_priority == 0 and answered > 3000, "right of way: every one of the loop's %d segments answers its own midpoint as a priority road and none of the other %d covered roads that answer theirs does (Road.priority from the skeleton's loops entry)" % [loop_priority, answered - loop_priority], "priority: %d loop roads of %d, %d other roads, %d segments answering their midpoints" % [loop_priority, loop.segments.size(), other_priority, answered])
	# The corrected field, as RoadBuilder.build() hands it to the car.
	var corrected := WorldRoadProfile.from_data(skeleton, RoadBuilder.apply_right_of_way(skeleton, RoadBuilder.apply_rim_rule(skeleton, drape).drape).drape)
	var ends := {}
	var starts := {}
	for id: String in loop.segments:
		var g: Dictionary = _geometry(raw_points[id])
		ends["%.3f,%.3f" % [g.xs[g.xs.size() - 1], g.zs[g.zs.size() - 1]]] = id
		starts["%.3f,%.3f" % [g.xs[0], g.zs[0]]] = id
	var with_side := 0
	var loop_only := 0
	var foreign_side := 0
	var foreign_loop_only := 0
	var over := 0
	var worst := 0.0
	var worst_where := ""
	var t13 := {}
	for junction: SkeletonLoader.Junction in SkeletonLoader.junctions_of(skeleton).values():
		var on_loop := false
		var side := false
		for id: String in junction.segments:
			if in_loop.has(id):
				on_loop = true
			elif covered.has(id):
				side = true
		if not on_loop:
			continue
		var key := "%.3f,%.3f" % [junction.position.x, junction.position.y]
		if not ends.has(key) or not starts.has(key):
			continue
		var probe := _junction_probe(corrected, raw_points, ends[key], starts[key], PROBE_OFFSETS, in_loop)
		if not side:
			loop_only += 1
			foreign_loop_only += probe.foreign
			continue
		with_side += 1
		foreign_side += probe.foreign
		if junction.id == T13_JUNCTION:
			t13 = probe
		if probe.worst > JUNCTION_STEP_MAX_M:
			over += 1
		if probe.worst > worst:
			worst = probe.worst
			worst_where = "junction %s, %s" % [junction.id, probe.where]
	_ok(with_side == JUNCTIONS_WITH_SIDE_ROAD and loop_only + with_side == LOOP_ROADS and foreign_side == 0 and foreign_loop_only == 0, "right of way: at the loop's %d junctions with a covered non-loop participant, probed every %.2f m over ±%.0f m through the node at the nine offsets -3.75..+3.75 inside the loop's 8.5 m, no station reads a non-loop road (was 4 690 stations: a service road's or the pit lane's own platform inside the loop's width); nor at the other %d loop junctions (was 172: parallel roads within reach)" % [with_side, PROBE_STEP_M, PROBE_JUNCTION_M, loop_only], "%d junctions with a side road (%d loop-only), %d foreign stations there, %d at the loop-only ones" % [with_side, loop_only, foreign_side, foreign_loop_only])
	_ok(over == 0 and worst > 0.0 and worst <= JUNCTION_STEP_MAX_M, "right of way: at every one of those %d junctions the largest one-step jump is under the loop's own kink bound %.3f m - the largest %.3f m (%s; the loop's own wedge there) - (was 0.625 m at the T13 junction and 7 junctions over the bound)" % [with_side, JUNCTION_STEP_MAX_M, worst, worst_where], "%d junctions over %.3f, the worst %.3f at %s" % [over, JUNCTION_STEP_MAX_M, worst, worst_where])
	_ok(not t13.is_empty() and t13.foreign == 0 and t13.worst <= JUNCTION_STEP_MAX_M and t13.centre <= SITE_STEP_MAX_M, "right of way: the T13 four-way junction %s (the 4.1 m stub 41395670-0 -> 41395670-1, with 27852583-0 and the Boxengasse 769107218-0) reads a loop road at every station, steps %.3f m at most and %.3f m on the centreline (was 0.625 m at +3.75 with the Boxengasse's lifted platform answering the loop's edge; with the profile's rule alone 0.216 m on the centreline: the rim walk had lifted the Boxengasse branch and left 41395670-1's start at the file's 9.5 %% - the walk now stays on the loop, road_builder.gd)" % [T13_JUNCTION, t13.worst, t13.centre], "T13: %s" % [t13])
	# The sites.
	var site_12 := _site_probe(corrected, raw_points, SITE_0012, in_loop, true)
	var left_12 := 0.0
	var right_12 := 0.0
	for offset: float in site_12.per_offset:
		if offset <= 0.0:
			left_12 = maxf(left_12, site_12.per_offset[offset])
		else:
			right_12 = maxf(right_12, site_12.per_offset[offset])
	_ok(site_12.foreign == 0 and left_12 <= SITE_STEP_MAX_M and right_12 <= SITE_0012_WEDGE_MAX_M and site_12.per_offset[SITE_0012[2]] <= SITE_0012_WEDGE_MAX_M, "0012 (the emergency-access service road 1549311960-0 inside 245166664-0's width, junction 65387230): over the whole of %s and %.0f m of %s no station reads the service road (was every station at +2..+3.75 for its last metres); the largest one-step jump is %.3f m at the centre and left (the 16 %% grade), %.3f m at the car's +1.37 (was 0.181) and %.3f m at +1..+3.75 (was 0.474 at +3.75, 0.264 at +3): the loop's own 7° wedge at the junction on the 16 %% grade, every station a loop road's, under %.2f m" % [SITE_0012[0], PROBE_JUNCTION_M, SITE_0012[1], left_12, site_12.per_offset[SITE_0012[2]], right_12, SITE_0012_WEDGE_MAX_M], "0012: foreign %d, left %.3f, car %.3f, right %.3f" % [site_12.foreign, left_12, site_12.per_offset[SITE_0012[2]], right_12])
	var site_18 := _site_probe(corrected, raw_points, SITE_0018, in_loop, false)
	_ok(site_18.foreign == 0 and site_18.worst <= SITE_STEP_MAX_M, "0018 (the \"major bump\" at 23.5 m/s: the service road 696037694-0 at junction 2084978602): no station reads the service road and the largest one-step jump at any offset is %.3f m (%s), under %.2f m (was 0.377 at -3.00 and 0.207 at -3.75, 0.223 at the car's -1.44: the service road's platform 0.3-0.6 m above the loop's for 799394519-0's last 7 m)" % [site_18.worst, site_18.where, SITE_STEP_MAX_M], "0018: foreign %d, worst %.3f at %s" % [site_18.foreign, site_18.worst, site_18.where])
	var site_17 := _site_probe(corrected, raw_points, SITE_0017, in_loop, false)
	_ok(site_17.foreign == 0 and site_17.worst <= SITE_STEP_MAX_M, "0017 (the private service road 198509975-0 at junction 1714130368): no station reads it and the largest one-step jump is %.3f m (%s), under %.2f m (was 0.080 at -3.75: the left third read from the service road for 2.5 m)" % [site_17.worst, site_17.where, SITE_STEP_MAX_M], "0017: foreign %d, worst %.3f at %s" % [site_17.foreign, site_17.worst, site_17.where])
	var site_01 := _site_probe(corrected, raw_points, SITE_0001, in_loop, false)
	var right_01 := 0.0
	for offset: float in site_01.per_offset:
		if offset >= 1.0:
			right_01 = maxf(right_01, site_01.per_offset[offset])
	_ok(site_01.foreign == 0 and right_01 <= SITE_STEP_MAX_M and site_01.worst <= SITE_STEP_MAX_M + HEIGHT_ROUNDING_M, "0001-residual (the pit lane 199642470-0 at the T13 junction 312821860, after the ridge fix): no station reads the pit lane (was every station at +1..+3.75 over the loop's last metres) and the largest one-step jump at +1..+3.75 is %.3f m (was 0.034 here, the analysis's 0.099 at +1 and 0.070 at +3.75); the site's largest %.3f m (%s) is the loop's own seam at -3.75" % [right_01, site_01.worst, site_01.where], "0001: foreign %d, right %.3f, worst %.3f at %s" % [site_01.foreign, right_01, site_01.worst, site_01.where])
	var deck: Dictionary = _geometry(raw_points[SITE_0021_DECK])
	deck.id = SITE_0021_DECK
	var track: Array = []
	var s := 0.0
	while s <= deck.length + 1e-9:
		track.append([deck, s])
		s += PROBE_STEP_M
	var deck_probe := _track_probe(corrected, track, PROBE_OFFSETS, in_loop)
	_ok(deck_probe.foreign == 0 and deck_probe.worst <= SITE_STEP_MAX_M, "0021-part (the Hohenrain deck %s, %.0f m, with the Boxengasse-an-T13 bridge 32894824-0 parallel 7.5 m to its right): no station on the deck reads another road and the largest one-step jump at any offset is %.3f m (%s), under %.2f m (was 0.469 at +3.75 from chainage 7.8: the parallel bridge's deck 0.4-0.6 m above)" % [SITE_0021_DECK, deck.length, deck_probe.worst, deck_probe.where, SITE_STEP_MAX_M], "0021: foreign %d, worst %.3f at %s" % [deck_probe.foreign, deck_probe.worst, deck_probe.where])


## A junction probed through the node: the loop segment `a` over its last
## PROBE_JUNCTION_M and `b` over its first, at the offsets; the foreign
## stations, the largest one-step jump (where) and the largest at offset 0.
func _junction_probe(profile: WorldRoadProfile, raw_points: Dictionary, a: String, b: String, offsets: Array, in_loop: Dictionary) -> Dictionary:
	return _track_probe(profile, _junction_track(raw_points, a, b, PROBE_JUNCTION_M), offsets, in_loop)


func _junction_track(raw_points: Dictionary, a: String, b: String, reach: float) -> Array:
	var into: Dictionary = _geometry(raw_points[a])
	into.id = a
	var out_of: Dictionary = _geometry(raw_points[b])
	out_of.id = b
	var track: Array = []
	var s: float = maxf(into.length - reach, 0.0)
	while s <= into.length + 1e-9:
		track.append([into, s])
		s += PROBE_STEP_M
	s = 0.0
	while s <= minf(reach, out_of.length) + 1e-9:
		track.append([out_of, s])
		s += PROBE_STEP_M
	return track


## A site: the nine offsets and the car's own; `whole` probes the whole of
## the segment into the junction (0012's car sits 5 m before it).
func _site_probe(profile: WorldRoadProfile, raw_points: Dictionary, site: Array, in_loop: Dictionary, whole: bool) -> Dictionary:
	var offsets: Array = PROBE_OFFSETS.duplicate()
	if not offsets.has(site[2]):
		offsets.append(site[2])
	var reach: float = INF if whole else PROBE_JUNCTION_M
	if whole:
		reach = _geometry(raw_points[site[0]]).length
	var track := _junction_track(raw_points, site[0], site[1], reach)
	if whole:
		# The segment out of the junction over PROBE_JUNCTION_M only.
		var trimmed: Array = []
		for at: Array in track:
			if at[0].id == site[0] or at[1] <= PROBE_JUNCTION_M + 1e-9:
				trimmed.append(at)
		track = trimmed
	return _track_probe(profile, track, offsets, in_loop)


## The probe itself over a track of [geometry, chainage] stations.
func _track_probe(profile: WorldRoadProfile, track: Array, offsets: Array, in_loop: Dictionary) -> Dictionary:
	var out := {"foreign": 0, "worst": 0.0, "where": "", "centre": 0.0, "per_offset": {}}
	for offset: float in offsets:
		var previous := NAN
		var o_worst := 0.0
		for at: Array in track:
			var g: Dictionary = at[0]
			var p := _point_on(g.xs, g.zs, g.chain, at[1])
			var travel := _direction_on(g.xs, g.zs, g.chain, at[1])
			var right := Vector2(-travel.y, travel.x)
			var described := profile.describe(p[0] + right.x * offset, p[1] + right.y * offset)
			if not in_loop.has(described.road):
				out.foreign += 1
			var h: float = described.height
			if is_finite(previous):
				var step := absf(h - previous)
				if step > o_worst:
					o_worst = step
				if step > out.worst:
					out.worst = step
					out.where = "%+.2f m at %s chainage %.2f" % [offset, g.id, at[1]]
			previous = h
		out.per_offset[offset] = o_worst
		if offset == 0.0:
			out.centre = o_worst
	return out


## The right of way on a fixture built here: a 500 m square loop of four
## raceway segments (8.5 m) on the plane, the bottom side split at a
## junction where a 3 m service road leaves at 4.6° (8 m over 100 m) and
## runs inside the loop's paved width for its first 53 m. On the plane both
## platforms are the plane
## with their own crown, so where the service road's centreline is nearer
## the two answers differ by the crown and the plane's slope: readable.
func _check_right_of_way_fixture() -> void:
	var skeleton := _right_of_way_skeleton(true)
	var drape := _fixture_drape(skeleton)
	var skeleton_errors := SkeletonLoader.validate(skeleton)
	var errors := WorldRoadProfile.validate(drape, skeleton)
	_ok(skeleton_errors.is_empty() and errors.is_empty(), "right-of-way fixture: a 500 m square loop of four raceway segments with a 3 m service road leaving a junction at 4.6° passes SkeletonLoader.validate() and, draped here, WorldRoadProfile.validate()", "right-of-way fixture: %s / %s" % [skeleton_errors, errors])
	var profile := WorldRoadProfile.from_data(skeleton, drape)
	# (2500, -1003): 3 m inside the loop's bottom side (its centreline z =
	# -1000, half width 4.25), 1 m from the service road's centreline (z =
	# -1004 at x = 2500). The loop's platform there: the plane at its
	# centre, 545.00, less the crown over 3 m.
	var on_loop := profile.describe(2500.0, -1003.0)
	var loop_height := _plane(2500.0, -1000.0) - WorldRoadProfile.CROWN * 3.0
	_ok(on_loop.road == "10-1" and on_loop.get("priority", false) and absf(on_loop.height - loop_height) < MM, "right-of-way fixture: at (2500, -1003), 3 m inside the loop's width and 1 m from the service road's centreline, the loop answers (%s, priority) with its own platform %.3f m: the plane less the crown over 3 m" % [on_loop.road, on_loop.height], "right-of-way fixture: %s" % [on_loop])
	# (2540, -1006.5): 6.5 m from the loop's centreline (beyond its half
	# width, inside its blend band), 0.7 m from the service road's (z =
	# -1007.2 at x = 2540): the service road answers, as before.
	var beside := profile.describe(2540.0, -1006.5)
	_ok(beside.road == "14-0" and not beside.get("priority", false) and beside.on_road, "right-of-way fixture: at (2540, -1006.5), 6.5 m from the loop's centreline (in its blend band) and 0.7 m from the service road's, the service road answers (%s): the right of way holds inside the loop's paved width only" % beside.road, "right-of-way fixture beside: %s" % [beside])
	# The service road's own length beyond the loop's width, and the loop
	# where the service road is the farther.
	var own := profile.describe(2549.0, -1007.9)
	var far := profile.describe(2460.0, -998.0)
	_ok(own.road == "14-0" and far.road == "10-1" and far.get("priority", false), "right-of-way fixture: the service road answers on its own centreline where the loop's platform does not reach (%s), the loop where its centreline is the nearer (%s)" % [own.road, far.road], "right-of-way fixture own/far: %s / %s" % [own, far])
	# Without a loops entry no road has priority and the old rule stands.
	var plain := WorldRoadProfile.from_data(_right_of_way_skeleton(false), _fixture_drape(_right_of_way_skeleton(false)))
	var old := plain.describe(2500.0, -1003.0)
	_ok(old.road == "14-0" and not old.get("priority", false) and old.height > loop_height + 0.05, "right-of-way fixture: the same roads with no loops entry give every road priority false and the old rule: at (2500, -1003) the nearer service road answers (%s, %.3f m: its own platform %.3f m above the loop's)" % [old.road, old.height, old.height - loop_height], "right-of-way fixture old rule: %s" % [old])


func _right_of_way_skeleton(with_loop: bool) -> Dictionary:
	var segment := func(id: String, way: int, road_class: String, width: float, points: Array) -> Dictionary:
		return {"id": id, "osm_way": way, "class": road_class, "width_m": width, "width_source": "class", "points": points}
	return {
		"snapshot": {"osm_base": PINNED_OSM_BASE, "bbox": SkeletonLoader.BBOX, "query_sha": "0".repeat(64), "pipeline_version": 1},
		"origin": {"epsg": SkeletonLoader.EPSG, "e0": SkeletonLoader.E0, "n0": SkeletonLoader.N0},
		"segments": [
			segment.call("10-0", 10, "raceway", 8.5, [[2200.0, -1000.0], [2450.0, -1000.0]]),
			segment.call("10-1", 10, "raceway", 8.5, [[2450.0, -1000.0], [2700.0, -1000.0]]),
			segment.call("11-0", 11, "raceway", 8.5, [[2700.0, -1000.0], [2700.0, -500.0]]),
			segment.call("12-0", 12, "raceway", 8.5, [[2700.0, -500.0], [2200.0, -500.0]]),
			segment.call("13-0", 13, "raceway", 8.5, [[2200.0, -500.0], [2200.0, -1000.0]]),
			segment.call("14-0", 14, "service", 3.0, [[2450.0, -1000.0], [2550.0, -1008.0]]),
		],
		"junctions": [
			{"id": "1", "x": 2200.0, "z": -1000.0, "segments": ["10-0", "13-0"]},
			{"id": "2", "x": 2450.0, "z": -1000.0, "segments": ["10-0", "10-1", "14-0"]},
			{"id": "3", "x": 2700.0, "z": -1000.0, "segments": ["10-1", "11-0"]},
			{"id": "4", "x": 2700.0, "z": -500.0, "segments": ["11-0", "12-0"]},
			{"id": "5", "x": 2200.0, "z": -500.0, "segments": ["12-0", "13-0"]},
		],
		"loops": [{"id": "square", "rel": 1, "segments": ["10-0", "10-1", "11-0", "12-0", "13-0"]}] if with_loop else [],
	}


# =============================================================================
#  THE FIXTURE
# =============================================================================

## The fixture's height at (x, z) [m]: the plane, the bowl, the two crests.
static func _fixture_height(x: float, z: float) -> float:
	var h := PLANE_BASE + PLANE_SLOPE_X * x + PLANE_SLOPE_Z * z
	var d := Vector2(x, z).distance_to(BOWL_CENTRE)
	h -= BOWL_DEPTH_M * maxf(0.0, 1.0 - (d / BOWL_RADIUS_M) * (d / BOWL_RADIUS_M))
	if absf(x - 800.0) < 50.0:
		var u := absf(z + 800.0) / CREST_HALF_LENGTH_M
		h += CREST_HEIGHT_M * maxf(0.0, 1.0 - u * u)
	if absf(z + 400.0) < 50.0:
		var u := absf(x - 1100.0) / CREST_HALF_LENGTH_M
		h += CREST_HEIGHT_M * maxf(0.0, 1.0 - u * u)
	return h


static func _plane(x: float, z: float) -> float:
	return PLANE_BASE + PLANE_SLOPE_X * x + PLANE_SLOPE_Z * z


## The sampler the fixture's drape reads (a Callable): the height, or null
## half a cell outside the 3 km box (the mosaic's rule).
func _fixture_sample(x: float, z: float) -> Variant:
	if x < 0.5 or x > FIXTURE_SIZE_M - 0.5 or z < -FIXTURE_SIZE_M + 0.5 or z > -0.5:
		return null
	return _fixture_height(x, z)


## The fixture's skeleton: a straight over the crest, a bridge over the
## other crest, a tunnel, a left-hand bend, the Karussell's way as a
## left-hander, a diagonal across the lattice's seams at (1000, -1000), and
## a 14 m road by tag (twice primary's class width, the widest the skeleton
## admits) along x across cell boundaries: its reach is 7 + 6 = 13 m.
func _fixture_skeleton() -> Dictionary:
	return {
		"snapshot": {"osm_base": PINNED_OSM_BASE, "bbox": SkeletonLoader.BBOX, "query_sha": "0".repeat(64), "pipeline_version": 1},
		"origin": {"epsg": SkeletonLoader.EPSG, "e0": SkeletonLoader.E0, "n0": SkeletonLoader.N0},
		"segments": [
			{"id": "1-0", "osm_way": 1, "class": "primary", "width_m": 7.0, "width_source": "class", "points": [[800.0, -600.0], [800.0, -1000.0]]},
			{"id": "2-0", "osm_way": 2, "class": "primary", "width_m": 7.0, "width_source": "class", "bridge": "yes", "layer": "1", "points": [[1000.0, -400.0], [1200.0, -400.0]]},
			{"id": "3-0", "osm_way": 3, "class": "primary", "width_m": 7.0, "width_source": "class", "tunnel": "yes", "layer": "-1", "points": [[1000.0, -200.0], [1200.0, -200.0]]},
			{"id": "4-0", "osm_way": 4, "class": "secondary", "width_m": 6.5, "width_source": "class", "points": [[200.0, -200.0], [300.0, -200.0], [300.0, -300.0]]},
			{"id": "414785755-0", "osm_way": SkeletonLoader.KARUSSELL_WAY, "class": "raceway", "width_m": 7.5, "width_source": "class", "points": [[2000.0, -2600.0], [2100.0, -2600.0], [2100.0, -2700.0]]},
			{"id": "5-0", "osm_way": 5, "class": "residential", "width_m": 5.5, "width_source": "class", "points": [[950.0, -1050.0], [1050.0, -950.0]]},
			{"id": "6-0", "osm_way": 6, "class": "primary", "width_m": 14.0, "width_source": "tag", "points": [[2400.0, -2200.0], [2700.0, -2200.0]]},
		],
		"junctions": [],
		"loops": [],
	}


## The fixture's drape: the lattice of the fixture at 10 m, every segment
## through the mirrored drape rules.
func _fixture_drape(skeleton: Dictionary) -> Dictionary:
	var cols := int(FIXTURE_SIZE_M / LATTICE_STEP_M) + 1
	var heights: Array = []
	heights.resize(cols * cols)
	for i: int in cols:
		for j: int in cols:
			heights[i * cols + j] = _fixture_height(j * LATTICE_STEP_M, -FIXTURE_SIZE_M + i * LATTICE_STEP_M)
	var segments: Array = []
	var typed := SkeletonLoader.segments_of(skeleton)
	for raw: Dictionary in skeleton.segments:
		var record: Variant = WorldRoadProfile.drape_segment(typed[raw.id], raw.points, _fixture_sample)
		if record != null:
			segments.append(record)
	return {
		"snapshot": {"osm_base": PINNED_OSM_BASE, "bbox": SkeletonLoader.BBOX, "query_sha": "0".repeat(64), "skeleton_pipeline_version": 1, "skeleton_sha256": "0".repeat(64), "pipeline_version": 1},
		"origin": {"epsg": SkeletonLoader.EPSG, "e0": SkeletonLoader.E0, "n0": SkeletonLoader.N0},
		"dem": {"source": "synthetic plane + bowl + crests", "epsg": 25832, "vertical_datum": "DHHN2016", "grid_m": 1.0, "tiles": [{"name": "dgm1_32_352_5577_1_rp_2025.tif", "sha256": "0".repeat(64), "verified": true}]},
		"coverage": {"x_min": 0.0, "x_max": FIXTURE_SIZE_M, "z_min": -FIXTURE_SIZE_M, "z_max": 0.0},
		"rules": WorldRoadProfile.RULES.duplicate(),
		"lattice": {"step_m": LATTICE_STEP_M, "x0": 0.0, "z0": -FIXTURE_SIZE_M, "cols": cols, "rows": cols, "heights": heights},
		"segments": segments,
	}


func _check_fixture() -> void:
	var skeleton := _fixture_skeleton()
	var drape := _fixture_drape(skeleton)
	_ok(_fixture_sample(123.0, -456.0) == _fixture_height(123.0, -456.0) and _fixture_sample(0.4, -1.0) == null and _fixture_sample(2999.6, -1.0) == null, "fixture: the sampler is the fixture's height, null half a cell outside")
	var errors := WorldRoadProfile.validate(drape, skeleton)
	_ok(errors.is_empty(), "fixture: the 3 × 3 km drape built here passes validate()", "fixture: %s" % [errors])
	var profile := WorldRoadProfile.from_data(skeleton, drape)
	_ok(profile.road_count() == 7 and profile.coverage() == Rect2(0.0, -FIXTURE_SIZE_M, FIXTURE_SIZE_M, FIXTURE_SIZE_M), "fixture: 7 roads, coverage 0..3000 × -3000..0")
	# The plane, off every road and on the straight's centreline.
	var worst := 0.0
	for point: Vector2 in [Vector2(100.0, -100.0), Vector2(2500.0, -2900.0), Vector2(123.4, -2345.6), Vector2(2999.0, -1.0)]:
		worst = maxf(worst, absf(profile.sample_height(point.x, point.y) - _plane(point.x, point.y)))
	_ok(worst < MM, "fixture: off-road sample_height reproduces the plane within 1 mm (worst %.6f m)" % worst)
	worst = 0.0
	for z: float in [-620.0, -700.0, -750.0, -860.0, -980.0]:
		worst = maxf(worst, absf(profile.sample_height(800.0, z) - _plane(800.0, z)))
	_ok(worst < MM, "fixture: on the straight's centreline (away from the crest) sample_height is the plane within 1 mm (worst %.6f m)" % worst)
	# The gradient.
	var gradient := profile.ramp_gradient(500.0, -2500.0)
	_ok(absf(gradient.x - PLANE_SLOPE_X) < 1e-4 and absf(gradient.y - PLANE_SLOPE_Z) < 1e-4, "fixture: off-road the gradient is the plane's (%.4f, %.4f) within 1e-4" % [gradient.x, gradient.y], "gradient %s" % [gradient])
	gradient = profile.ramp_gradient(800.0, -700.0)
	_ok(absf(gradient.x) < 1e-4 and absf(gradient.y - PLANE_SLOPE_Z) < 1e-4, "fixture: on the straight's centreline the gradient is (%.4f, %.4f): the crown cancels across, the plane's slope along" % [gradient.x, gradient.y], "centreline gradient %s" % [gradient])
	# The bowl.
	_ok(absf(profile.sample_height(BOWL_CENTRE.x, BOWL_CENTRE.y) - (_plane(BOWL_CENTRE.x, BOWL_CENTRE.y) - BOWL_DEPTH_M)) < MM and absf(profile.sample_height(1600.0, -1500.0) - (_plane(1600.0, -1500.0) - 15.0)) < MM, "fixture: the bowl is 20 m deep at its centre and 15 m deep 100 m out (lattice nodes, exact)")
	var bowl_gradient := profile.ramp_gradient(BOWL_CENTRE.x, BOWL_CENTRE.y)
	_ok(absf(bowl_gradient.x - PLANE_SLOPE_X) < 1e-4 and absf(bowl_gradient.y - PLANE_SLOPE_Z) < 1e-4, "fixture: at the bowl's floor the gradient is the plane's again (the bowl is flat there)")
	# Seams: no step across the lattice's lines at x = 1000 and z = -1000, off-road and on the diagonal road.
	var step_off := absf(profile.sample_height(1000.0 - 0.0005, -1000.0 - 0.0005) - profile.sample_height(1000.0 + 0.0005, -1000.0 + 0.0005))
	var step_x := absf(profile.sample_height(2000.0 - 0.0005, -2500.0) - profile.sample_height(2000.0 + 0.0005, -2500.0))
	var step_on := absf(profile.sample_height(1000.0 - 0.0005, -1000.0 + 0.0005) - profile.sample_height(1000.0 + 0.0005, -1000.0 - 0.0005))
	var on_road: Dictionary = profile.describe(1000.0, -1000.0)
	_ok(step_off < MM and step_x < MM and step_on < MM and on_road.road == "5-0", "fixture: bilinear continuity across the lattice seams at (1000, -1000) and x = 2000: steps %.6f / %.6f m off-road, %.6f m on the diagonal road" % [step_off, step_x, step_on], "seam steps %.6f %.6f %.6f, road %s" % [step_off, step_x, step_on, on_road.road])
	# The crown and the blend band on the straight (travel north: right is +x).
	var centre := profile.sample_height(800.0, -700.0)
	var crown := profile.sample_height(802.0, -700.0)
	var edge := profile.sample_height(803.5, -700.0)
	var half_band := profile.sample_height(806.5, -700.0)
	var beyond := profile.sample_height(809.5, -700.0)
	_ok(absf(centre - crown - 0.04) < MM and absf(centre - edge - 0.07) < MM, "fixture: the 2 %% crown: 4 cm down 2 m out, 7 cm down at the 3.5 m edge")
	_ok(absf(beyond - _plane(809.5, -700.0)) < MM and absf(half_band - 0.5 * (edge + _plane(806.5, -700.0))) < MM, "fixture: the 6 m blend band: halfway between the edge and the terrain 3 m out, the terrain itself 6 m out")
	# The superelevation on the bend (east then north: a left-hander, rising to the right = +z).
	var bend_left := profile.sample_height(250.0, -202.0)
	var bend_right := profile.sample_height(250.0, -198.0)
	var bend_record: Dictionary = drape.segments[3]
	# was crossfall [0.04, 0.04, 0.04] and 16 cm across: the three-point
	# circle through the corner's neighbours 100 m away read R 70.7 m; the
	# crossfall-twist rule reads the 90° turn over its 20 m window, R 12.7 m,
	# a hairpin's cap (WorldRoadProfile.CURVATURE_WINDOW_M).
	_ok(bend_record.id == "4-0" and bend_record.crossfall == [0.06, 0.06, 0.06] and absf(bend_right - bend_left - 0.24) < MM, "fixture: the left-hand bend is superelevated 6 %% (a 90° turn over the 20 m window: R 12.7 m, under the hairpin radius, capped; was 4 %% from the three-point circle's R 70.7 m): crossfall [0.06, 0.06, 0.06], 24 cm higher 2 m right than 2 m left", "bend crossfall %s, across %.3f" % [bend_record.crossfall, bend_right - bend_left])
	# The bridge over the second crest.
	var bridge_record: Dictionary = drape.segments[1]
	var bridge_mid := profile.sample_height(1100.0, -400.0)
	var bridge_linear := true
	for k: int in bridge_record.dense.size():
		bridge_linear = bridge_linear and absf(bridge_record.dense[k] - (458.0 + 0.1 * k)) < 1e-9
	_ok(bridge_record.id == "2-0" and bridge_linear and absf(bridge_mid - 463.0) < MM and absf(_fixture_height(1100.0, -400.0) - 466.0) < 1e-9 and bridge_record.labels.is_empty(), "fixture: the bridge's deck is linear between its abutments 458 and 468 m: 463 m over the 3 m crest under it (the ground reads 466), no crest labelled", "bridge dense linear %s, mid %.3f, labels %s" % [bridge_linear, bridge_mid, bridge_record.labels])
	# The tunnel.
	var tunnel_record: Dictionary = drape.segments[2]
	_ok(tunnel_record.id == "3-0" and absf(profile.sample_height(1000.0, -200.0) - 454.0) < MM and absf(profile.sample_height(1015.0, -200.0) - 451.75) < MM and absf(profile.sample_height(1100.0, -200.0) - 453.0) < MM, "fixture: the tunnel is at the ground at its portal (454 m), 3 m under it 15 m in, 6 m under it (layer -1) at mid-length: 453 m under the 459 m ground", "tunnel: %.3f %.3f %.3f" % [profile.sample_height(1000.0, -200.0), profile.sample_height(1015.0, -200.0), profile.sample_height(1100.0, -200.0)])
	# The crest label on the straight.
	var straight_record: Dictionary = drape.segments[0]
	var kinds: Array = straight_record.labels.map(func(label: Dictionary) -> String: return "%s@%.0f" % [label.kind, label.at])
	var crests: Array = straight_record.labels.filter(func(label: Dictionary) -> bool: return label.kind == "crest")
	_ok(straight_record.id == "1-0" and crests.size() == 1 and absf(crests[0].at - 200.0) <= 2.0 and not kinds.has("dip@200"), "fixture: the straight's crest at z = -800 (chainage 200, one station either side: the top is sampled at 2 m) is labelled a crest, its feet dips: %s" % [kinds], "straight labels %s" % [kinds])
	var crest_label: Dictionary = crests[0]
	_ok(crest_label.curvature_20m < -WorldRoadProfile.CREST_CURVATURE and crest_label.has("curvature_40m") and crest_label.curvature_40m < 0.0, "fixture: the crest's 20 m curvature %.5f /m is beyond -0.004, its 40 m curvature %.5f" % [crest_label.curvature_20m, crest_label.curvature_40m])
	_ok(absf(profile.sample_height(800.0, -800.0) - (_plane(800.0, -800.0) + CREST_HEIGHT_M)) <= HEIGHT_ROUNDING_M, "fixture: the crest's top is 3 m over the plane on the road (the physics reads the height, not the label)")
	# The bank on the fixture's Karussell (east then north: a left-hander, the low edge to the left = -z).
	var karussell_record: Dictionary = drape.segments[4]
	var bowl_inside := profile.sample_height(2050.0, -2603.75)
	var bowl_strip := profile.sample_height(2050.0, -2602.75)
	var bowl_centre := profile.sample_height(2050.0, -2600.0)
	var bowl_outside := profile.sample_height(2050.0, -2596.25)
	# was crossfall [0.3, 0.3, 0.3] and the label at 0 to 200: the Karussell
	# blend ramps the array over 30 m from each end's own plane value (the
	# corner's 0.06 here, a junction's stitched tilt in the pipeline) and
	# the label carries at 30, to 170, ramp_m 30.
	var bank_label: Dictionary = karussell_record.labels.back()
	_ok(karussell_record.id == "414785755-0" and karussell_record.crossfall == [0.06, 0.3, 0.06] and bank_label == {"at": 30.0, "kind": "bank", "to": 170.0, "bank": 0.3, "bowl_m": 6.5, "strip_m": 1.0, "ramp_m": 30.0} and absf(bowl_strip - bowl_inside) < MM and absf(bowl_outside - bowl_inside - 1.95) < MM and absf(bowl_centre - _plane(2050.0, -2600.0)) < MM, "fixture: way 414785755 takes the bank: the array ramped [0.06, 0.3, 0.06] with the label at 30 / to 170 / ramp_m 30 (was 0.3 at every point, at 0 / to 200), and at chainage 50 flat over the 1 m strip, 1.95 m up at the outside edge, the centre on the ground", "bank: crossfall %s, label %s, across %.3f %.3f %.3f %.3f" % [karussell_record.crossfall, bank_label, bowl_inside, bowl_strip, bowl_centre, bowl_outside])
	_check_fixture_blend(profile)
	_check_twist_rule(profile)
	_check_legacy_bank(skeleton, drape)
	# The 14 m road (travel east: right is +z): its full band, no step at the old 10.25 m cutoff.
	var wide_centre := profile.sample_height(2550.0, -2200.0)
	var wide_edge := profile.sample_height(2550.0, -2193.0)
	var wide_half := profile.sample_height(2550.0, -2190.0)
	var wide_beyond := profile.sample_height(2550.0, -2187.0)
	var wide_before := profile.sample_height(2550.0, -2200.0 + 10.25 - 0.0005)
	var wide_after := profile.sample_height(2550.0, -2200.0 + 10.25 + 0.0005)
	var wide_at_11: Dictionary = profile.describe(2550.0, -2189.0)
	_ok(absf(wide_centre - _plane(2550.0, -2200.0)) < MM and absf(wide_centre - wide_edge - 0.14) < MM and absf(wide_half - 0.5 * (wide_edge + _plane(2550.0, -2190.0))) < MM and absf(wide_beyond - _plane(2550.0, -2187.0)) < MM, "fixture: the 14 m road's crown 14 cm down at its 7 m edge, its band halfway at 10 m and the terrain at 13 m (was cut off at 10.25 m for every road)")
	_ok(absf(wide_before - wide_after) < MM and wide_at_11.road == "6-0" and wide_at_11.distance == 11.0, "fixture: no step across the old 10.25 m cutoff (%.6f m) and the road still reaches 11 m out" % absf(wide_before - wide_after), "step %.6f, road at 11 m: %s" % [absf(wide_before - wide_after), wide_at_11.road])
	# Outside.
	_ok(profile.sample_height(-1.0, -1.0) == 0.0 and profile.ramp_gradient(-1.0, -1.0) == Vector2.ZERO and profile.elevation_mask(-1.0, -1.0) == 0.0 and profile.sample_height(3001.0, -1500.0) == 0.0, "fixture: outside the 3 km box the profile is flat: 0, (0, 0), mask 0")
	# The stations and the mirrored rules on their own.
	var stations := WorldRoadProfile.station_chainages(101.5)
	_ok(stations.size() == 52 and stations[50] == 100.0 and stations[51] == 101.5 and WorldRoadProfile.station_chainages(100.0).size() == 51, "fixture: stations every 2 m, the uneven end kept (101.5 m: 52 stations)")
	_ok(WorldRoadProfile.superelevation(-1.0 / 200.0) == 0.04 and WorldRoadProfile.superelevation(1.0 / 400.0) == -0.02 and WorldRoadProfile.superelevation(-1.0 / 20.0) == 0.06 and WorldRoadProfile.superelevation(0.0) == 0.0, "fixture: superelevation 8 / R: R 200 m -> 4 %% (the cap), R 400 m -> 2 %% to the left, a 20 m hairpin 6 %%, straight 0")
	_ok(WorldRoadProfile.tunnel_depth(0.0, 200.0, -1) == 0.0 and WorldRoadProfile.tunnel_depth(15.0, 200.0, -1) == 3.0 and WorldRoadProfile.tunnel_depth(100.0, 200.0, -2) == 12.0, "fixture: tunnel depth 0 at the portal, 3 m 15 m in, 12 m for layer -2")


# =============================================================================
#  BROKEN FIXTURES
# =============================================================================

## The Karussell blend on the fixture's way (travel east then north; the
## bank rises to the right = +z on the first leg, +x on the second): at
## chainage 0 the plane with the end's 0.06, at chainage 10 (a third of
## the entry ramp, weight 1/3) the plane (crossfall lerped to 0.084) and
## the bowl mixed 2:1 at every offset, at 190 (a third into the exit ramp
## from its end) the same, the centre the ground at all three; and no
## step at the ramps' ends along the edge.
func _check_fixture_blend(profile: WorldRoadProfile) -> void:
	var c0 := _plane(2000.0, -2600.0)
	var entry_left := profile.sample_height(2000.0, -2603.75)
	var entry_right := profile.sample_height(2000.0, -2596.25)
	_ok(absf(entry_left - (c0 - 0.225)) < MM and absf(entry_right - (c0 + 0.225)) < MM and absf(profile.sample_height(2000.0, -2600.0) - c0) < MM, "fixture blend: at the Karussell's entry (chainage 0) the platform is the plane with the end's 0.06: -0.225 / +0.225 m at ∓3.75, the centre on the ground (%.3f / %.3f / %.3f)" % [entry_left, profile.sample_height(2000.0, -2600.0), entry_right], "entry: %.4f %.4f vs %.4f ± 0.225" % [entry_left, entry_right, c0])
	var c10 := _plane(2010.0, -2600.0)
	var e10 := 0.06 + (0.3 - 0.06) * 0.1
	var expected := {}
	for o: float in [-3.75, -2.75, 0.0, 3.75]:
		var plane := c10 + e10 * o
		var bowl := c10 - 0.3 * 2.75 + 0.3 * maxf(o + 2.75, 0.0)
		expected[o] = lerpf(plane, bowl, 1.0 / 3.0)
	var worst := 0.0
	for o: float in expected:
		worst = maxf(worst, absf(profile.sample_height(2010.0, -2600.0 + o) - expected[o]))
	_ok(worst < MM, "fixture blend: at chainage 10 (weight 1/3, crossfall %.3f) every offset is the plane and the bowl mixed 2:1: %.3f / %.3f / %.3f / %.3f m about the centre at -3.75 / -2.75 / 0 / +3.75 (worst %.6f m off)" % [e10, expected[-3.75] - c10, expected[-2.75] - c10, expected[0.0] - c10, expected[3.75] - c10, worst], "blend at 10: worst %.6f" % worst)
	# The reader lerps the array between the points: at 190 the crossfall
	# is between the corner's 0.3 (chainage 100) and the end's 0.06 (200),
	# 0.084 - the ramp is evaluated at the skeleton's points, the plane
	# between them the reader's own lerp (the pipeline's Karussell has 29
	# points 3.6-14 m apart, the fixture's three 100 m).
	var c190 := _plane(2100.0, -2690.0)
	var e190 := 0.3 + (0.06 - 0.3) * 0.9
	worst = 0.0
	for o: float in [-3.75, -2.75, 0.0, 3.75]:
		var plane := c190 + e190 * o
		var bowl := c190 - 0.3 * 2.75 + 0.3 * maxf(o + 2.75, 0.0)
		worst = maxf(worst, absf(profile.sample_height(2100.0 + o, -2690.0) - lerpf(plane, bowl, 1.0 / 3.0)))
	_ok(worst < MM, "fixture blend: at chainage 190 (10 m before the exit, weight 1/3, the crossfall the array's lerp %.3f) the same 2:1 mix at every offset (worst %.6f m off)" % [e190, worst], "blend at 190: worst %.6f" % worst)
	# Along the outside edge through both ramps' ends: no step.
	var largest := 0.0
	for k: int in 80:
		var s := 25.0 + k * 0.25
		var a := profile.sample_height(2000.0 + s, -2596.25)
		var b := profile.sample_height(2000.0 + s + 0.25, -2596.25)
		largest = maxf(largest, absf(b - a))
	_ok(largest < 0.03, "fixture blend: along the outside edge from chainage 25 to 45 (through the ramp's end at 30) no 0.25 m step over 3 cm (the largest %.4f m: the plane's edge lift arriving over 30 m plus the ground's slope)" % largest, "edge step %.4f" % largest)


## F4 (the codex cross-review of the ROAD-GEOMETRY landing): a bank label
## WITHOUT ramp_m reads through the 4B-3 branch verbatim whatever its
## `at` says - the bowl from chainage 0 to `to`, the side from the
## crossfall at the read point - and the plane past `to`; the fixture's
## Karussell with its label rewritten to at 30 / to 120 and no ramp_m.
func _check_legacy_bank(skeleton: Dictionary, drape: Dictionary) -> void:
	var legacy: Dictionary = drape.duplicate(true)
	var label: Dictionary = legacy.segments[4].labels.back()
	label.erase("ramp_m")
	label.at = 30.0
	label.to = 120.0
	var errors := WorldRoadProfile.validate(legacy, skeleton)
	var profile := WorldRoadProfile.from_data(skeleton, legacy)
	var c0 := _plane(2000.0, -2600.0)
	var inside0 := profile.sample_height(2000.0, -2603.75)
	var outside0 := profile.sample_height(2000.0, -2596.25)
	var c50 := _plane(2050.0, -2600.0)
	var inside50 := profile.sample_height(2050.0, -2603.75)
	var c150 := _plane(2100.0, -2650.0)
	var e150 := 0.3 + (0.06 - 0.3) * 0.5
	var right150 := profile.sample_height(2103.75, -2650.0)
	_ok(errors.is_empty() and absf(inside0 - (c0 - 0.825)) < MM and absf(outside0 - (c0 + 1.125)) < MM and absf(inside50 - (c50 - 0.825)) < MM and absf(right150 - (c150 + e150 * 3.75)) < MM, "F4: a bank label without ramp_m (at 30, to 120) validates and reads as 4B-3 read it: the bowl from chainage 0 (inside edge -0.825, outside +1.125 m about the centre) through 50, the plane past `to` (chainage 150: +%.3f m at +3.75, the array's lerped crossfall %.3f) - was the plane at chainage 0 for such a label (-1.125 at the inside edge, a 0.30 m step at 30 where the bowl began)" % [e150 * 3.75, e150], "legacy bank: errors %s, at 0 %.3f / %.3f (centre %.3f), at 50 %.3f (centre %.3f), at 150 %.3f (centre %.3f)" % [errors, inside0, outside0, c0, inside50, c50, right150, c150])


## The crossfall-twist rule through the mirror (WorldRoadProfile.crossfall_of
## and runoff) on the skeleton's own points: the 0007 site's segment
## 799394513-1 (its points 8/9 0.45 m apart, where the three-point circle
## flipped -0.04 -> +0.04 -> -0.06) reads one sign through points 6-10 and
## changes by at most SUPERELEVATION_RUNOFF_PER_M per metre between any
## two consecutive points; runoff keeps a bounded array bit for bit, pins
## the ends when asked, and bounds a spike; a straight is still 0.
func _check_twist_rule(_profile: WorldRoadProfile) -> void:
	var skeleton: Variant = SkeletonLoader.read_file()
	var points: Array = []
	for raw: Dictionary in skeleton.segments:
		if raw.id == "799394513-1":
			points = raw.points
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for point: Array in points:
		xs.append(point[0])
		zs.append(point[1])
	var chain := WorldRoadProfile.chainages(xs, zs)
	var e := WorldRoadProfile.crossfall_of(xs, zs)
	var steepest := 0.0
	for i: int in range(1, e.size()):
		if chain[i] > chain[i - 1]:
			steepest = maxf(steepest, absf(e[i] - e[i - 1]) / (chain[i] - chain[i - 1]))
	var one_sign := e.size() > 10 and signf(e[6]) == signf(e[7]) and signf(e[7]) == signf(e[8]) and signf(e[8]) == signf(e[9]) and signf(e[9]) == signf(e[10])
	_ok(points.size() == 27 and one_sign and steepest <= WorldRoadProfile.SUPERELEVATION_RUNOFF_PER_M + 1e-9, "the crossfall-twist rule on 799394513-1's 27 points: points 6-10 read one sign (%.4f %.4f %.4f %.4f %.4f; was -0.04 -> +0.04 -> -0.06 across the 0.45 m chord at point 8, a 0.94 m/m edge twist) and the crossfall changes by at most %.5f per metre between consecutive points (the bound %.3f)" % [e[6], e[7], e[8], e[9], e[10], steepest, WorldRoadProfile.SUPERELEVATION_RUNOFF_PER_M], "twist rule: %d points, one sign %s, steepest %.5f/m: %s" % [points.size(), one_sign, steepest, e])
	var again := WorldRoadProfile.runoff(e, chain, true)
	var spike := WorldRoadProfile.runoff(PackedFloat64Array([0.0, 0.0, 0.06, 0.0, 0.0]), PackedFloat64Array([0.0, 10.0, 10.5, 11.0, 40.0]), true)
	var spike_bounded := true
	for i: int in range(1, 5):
		spike_bounded = spike_bounded and absf(spike[i] - spike[i - 1]) <= WorldRoadProfile.SUPERELEVATION_RUNOFF_PER_M * ([0.0, 10.0, 10.5, 11.0, 40.0][i] - [0.0, 10.0, 10.5, 11.0, 40.0][i - 1]) + 1e-12
	_ok(again == e and spike[0] == 0.0 and spike[4] == 0.0 and spike[2] > 0.0 and spike[2] < 0.06 and spike_bounded, "runoff: a bounded array comes back bit for bit; a 0.06 spike between points 0.5 m apart on a 40 m straight is spread under the bound with the ends pinned at 0 (the spike's point %.4f, its neighbours %.4f / %.4f)" % [spike[2], spike[1], spike[3]], "runoff: same %s, spike %s" % [again == e, spike])
	_ok(WorldRoadProfile.crossfall_of(PackedFloat64Array([0.0, 100.0]), PackedFloat64Array([0.0, 0.0])) == PackedFloat64Array([0.0, 0.0]) and WorldRoadProfile.crossfall_of(PackedFloat64Array([0.0, 100.0, 200.0]), PackedFloat64Array([0.0, 0.0, 0.0])) == PackedFloat64Array([0.0, 0.0, 0.0]), "a straight still reads 0 (the crown) through the twist rule, two points or three")


func _check_broken_fixtures() -> void:
	var skeleton := _fixture_skeleton()
	var drape := _fixture_drape(skeleton)
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.snapshot.osm_base = "2026-09-23T00:00:00Z"), skeleton, "snapshot.osm_base is 2026-09-23T00:00:00Z, the pinned snapshot is", "a snapshot that is not the pinned one")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.snapshot.pipeline_version = 2), skeleton, "snapshot.pipeline_version is 2, this profile reads 1", "another drape pipeline's version")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.snapshot.query_sha = "abc"), skeleton, "snapshot.query_sha is abc, the skeleton's is", "a drape of another skeleton's queries")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.rules.crown = 0.03), skeleton, "rules.crown is 0.03, this profile's is 0.02", "a file of other rules")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.lattice.heights.pop_back()), skeleton, "lattice.heights has 90600, cols × rows is 90601", "a lattice short of a height")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.lattice.x0 = 5.0), skeleton, "lattice starts at (5.0, -3000.0), the coverage at (0.0, -3000.0)", "a lattice off the coverage")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.coverage.x_max = -1.0), skeleton, "coverage x 0.0..-1.0 is empty", "an empty coverage")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.dem.epsg = 4326), skeleton, "dem.epsg is 4326, the tiles' is 25832", "a DEM in another CRS")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.dem.tiles[0].verified = false), skeleton, "was not verified against the metalink's sha256", "a tile not verified")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[0].id = "9-0"), skeleton, "segment 9-0 is not in the skeleton", "a segment the skeleton does not have")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[0].dense.pop_back()), skeleton, "segment 1-0.dense has 200, the segment's stations are 201", "a dense list short of a station")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[0].heights[0] = null), skeleton, "segment 1-0 is covered with 1 missing height(s)", "a covered segment with a missing height")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[0].labels[0].kind = "hump"), skeleton, "kind is hump, not one of", "a label of an unknown kind")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[0].labels[0].curvature_20m = 0.001), skeleton, "curvature 0.001 is within the threshold 0.004", "a label within the threshold")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[0].labels[0].curvature_20m = -0.01), skeleton, "is a dip with curvature -0.01", "a dip with a crest's curvature")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[4].labels.back().strip_m = 2.0), skeleton, "bank: strip 2.0 + bowl 6.5 is not the paved width 7.5", "a bank that does not fill the width")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[4].labels.back().ramp_m = 40.0), skeleton, "bank: the ramp 40.0 does not fit before at 30.0", "a bank ramp longer than the bowl's start")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[4].labels.back().to = 190.0), skeleton, "bank: the ramp 30.0 does not fit after to 190.0", "a bank ramp past the segment's end")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[4].labels.back().ramp_m = -1.0), skeleton, "bank ramp_m is -1.0, not a length", "a negative bank ramp")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[4].labels.back().at = 185.0), skeleton, "bank: at 185.0 is past to 170.0", "a bank starting after it ends")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments[0].crossfall[0] = 0.5), skeleton, "segment 1-0.crossfall[0] is 0.5, beyond any rule's", "a crossfall beyond every rule")
	_expect_fault(_broken(drape, func(d: Dictionary) -> void: d.segments.reverse()), skeleton, "comes after", "segments out of order")
	_expect_fault(null, skeleton, "not a JSON object", "a file that is not JSON")


func _broken(drape: Dictionary, breaker: Callable) -> Dictionary:
	var copy: Dictionary = drape.duplicate(true)
	breaker.call(copy)
	return copy


func _expect_fault(fixture: Variant, skeleton: Dictionary, expected: String, what: String) -> void:
	var errors := WorldRoadProfile.validate(fixture, skeleton)
	var named := false
	for error: String in errors:
		if error.contains(expected):
			named = true
	_ok(named, "validate() names %s: \"%s\"" % [what, expected], "validate() on %s says %s, not \"%s\"" % [what, errors, expected])
