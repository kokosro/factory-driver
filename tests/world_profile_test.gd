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
## code names the field. ROAD-SMOOTHING (2026-09-23, tools/world/drape.py's
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
## profile's arithmetic did not).
const SAMPLES_DIGEST := "bab692efff0c06a8ae5dee74e597955ff58142289bec82063d69426385227486"

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
	_check_fixture()
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


## The Karussell: crossfall 30 % everywhere, the one bank label with the
## R9 numbers, and the bowl read across the platform: a flat 1 m strip at
## the inside, 1.95 m up to the outside edge, the centre at the DEM's.
func _check_karussell(drape: Dictionary, profile: WorldRoadProfile) -> void:
	var record: Dictionary = {}
	for raw: Dictionary in drape.segments:
		if raw.id == "%d-0" % SkeletonLoader.KARUSSELL_WAY:
			record = raw
	if record.is_empty():
		_ok(false, "", "the Karussell (way %d) is not in the drape" % SkeletonLoader.KARUSSELL_WAY)
		return
	var banks: Array = record.labels.filter(func(label: Dictionary) -> bool: return label.kind == "bank")
	_ok(record.crossfall.count(0.3) == record.crossfall.size() and banks.size() == 1 and banks[0].bank == 0.3 and banks[0].bowl_m == 6.5 and banks[0].strip_m == 1.0 and banks[0].at == 0.0, "the Karussell (%s): crossfall +0.30 at all %d points, one bank label 30 %% over 6.5 m with a 1 m strip (branch (c), ring-region-decisions.md §3)" % [record.id, record.crossfall.size()], "the Karussell's crossfall %s, labels %s" % [record.crossfall, record.labels])
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
	_ok(digest == SAMPLES_DIGEST, "the 200 samples read the same as at ROAD-SMOOTHING's landing: sha256 %s (was 4B-3's b167c232...: the smoothed file; no covered segment is wider than 8.5 m, so the per-road reach changes nothing here)" % digest, "the 200 samples' digest is %s, pinned %s" % [digest, SAMPLES_DIGEST])
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
## second difference, |h[k+1] - 2 h[k] + h[k-1]| / 4 [1/m]) at the 90th
## and 99th percentiles: 0.0075 and 0.0150 (1.5 % and 3.0 % per station);
## after the smoothing at most the centimetre rounding's own quantum
## 0.0025 and twice it.
const RAW_LOOP_KINK_P90 := 0.0075
const RAW_LOOP_KINK_P99 := 0.0150
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
## The field probe across a seam: 5 cm along either segment at ±4 m; the
## grade over those 10 cm and the rounding allow this much.
const SEAM_PROBE_ALONG_M := 0.05
const SEAM_PROBE_OFFSET_M := 4.0
const SEAM_PROBE_MAX_M := 0.03
## The raw -> smoothed evidence over ±50 m along the owning segments at
## the three issue sites (the Conductor's requirement): the window's
## grade-change peak-to-peak [1/m] in the raw file, and the crest label
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
		for k: int in range(1, dense.size() - 1):
			kinks.append(absf((dense[k + 1] - 2.0 * dense[k] + dense[k - 1]) / 4.0))
	kinks.sort()
	var p90: float = kinks[int(floor(0.9 * (kinks.size() - 1)))]
	var p99: float = kinks[int(floor(0.99 * (kinks.size() - 1)))]
	_ok(kinks.size() > 10000 and p90 <= LOOP_KINK_P90_MAX + 1e-9 and p99 <= LOOP_KINK_P99_MAX + 1e-9, "smoothing: over the loop's %d plain stations the station-to-station grade change is %.4f /m at the 90th percentile and %.4f at the 99th (%.1f %% and %.1f %% per 2 m station; was %.4f and %.4f in the raw file, %.1f %% and %.1f %%: the centimetre rounding's quantum is %.4f)" % [kinks.size(), p90, p99, 200.0 * p90, 200.0 * p99, RAW_LOOP_KINK_P90, RAW_LOOP_KINK_P99, 200.0 * RAW_LOOP_KINK_P90, 200.0 * RAW_LOOP_KINK_P99, LOOP_KINK_P90_MAX], "loop grade change p90 %.4f p99 %.4f over %d stations" % [p90, p99, kinks.size()])
	# Every junction's covered ends: one height, one crossfall.
	var junctions := 0
	var height_gaps := 0
	var crossfall_gaps := 0
	var worst_height := 0.0
	var worst_crossfall := 0.0
	var crossfall_nodes := 0
	for raw: Dictionary in skeleton.junctions:
		var heights := PackedFloat64Array()
		var crossfalls := PackedFloat64Array()
		for id: String in raw.segments:
			if not records.has(id):
				continue
			var points: Array = raw_points[id]
			var record: Dictionary = records[id]
			var at_start: bool = Vector2(points[0][0], points[0][1]).distance_to(Vector2(raw.x, raw.z)) < 1e-6
			var end: int = 0 if at_start else record.dense.size() - 1
			var end_point: int = 0 if at_start else record.crossfall.size() - 1
			if record.dense[end] != null:
				heights.append(record.dense[end])
			if segments[id].osm_way != SkeletonLoader.KARUSSELL_WAY:
				crossfalls.append(record.crossfall[end_point])
		if heights.size() >= 2:
			junctions += 1
			var gap: float = _span_of(heights)
			worst_height = maxf(worst_height, gap)
			if gap > 2.0 * HEIGHT_ROUNDING_M + 1e-9:
				height_gaps += 1
		if crossfalls.size() >= 2:
			crossfall_nodes += 1
			var gap: float = _span_of(crossfalls)
			worst_crossfall = maxf(worst_crossfall, gap)
			if gap > 1e-9:
				crossfall_gaps += 1
	_ok(junctions > 2000 and height_gaps == 0 and crossfall_nodes > 2000 and crossfall_gaps == 0, "junctions: at all %d nodes with two or more draped ends the ends' centre heights agree to the centimetre (the largest gap %.3f m) and at all %d nodes with two or more non-bank ends the end crossfalls are equal (the largest gap %.4f; was a gap over 2 %% at %d junctions, %d of them on the loop: each segment's end took its own bend's crossfall)" % [junctions, worst_height, crossfall_nodes, worst_crossfall, RAW_CROSSFALL_GAP_JUNCTIONS, RAW_CROSSFALL_GAP_LOOP], "%d height gaps (worst %.3f), %d crossfall gaps (worst %.4f) over %d / %d junctions" % [height_gaps, worst_height, crossfall_gaps, worst_crossfall, junctions, crossfall_nodes])
	# Issue-0005's stair, from the file and from the field.
	var a: Dictionary = records[ISSUE_0005_SEGMENTS[0]]
	var b: Dictionary = records[ISSUE_0005_SEGMENTS[1]]
	var stair_right: float = absf(_edge_height(a, a.dense.size() - 1, a.crossfall.size() - 1, 4.25) - _edge_height(b, 0, 0, 4.25))
	var stair_left: float = absf(_edge_height(a, a.dense.size() - 1, a.crossfall.size() - 1, -4.25) - _edge_height(b, 0, 0, -4.25))
	var nearest_5: Dictionary = profile.describe(ISSUE_0005_CAR.x, ISSUE_0005_CAR.y)
	_ok(nearest_5.get("road") == ISSUE_0005_SEGMENTS[0] and absf(nearest_5.get("chainage", 0.0) - 465.2) < 0.5 and a.dense[a.dense.size() - 1] == b.dense[0] and a.crossfall[a.crossfall.size() - 1] == b.crossfall[0] and stair_right <= STAIR_MAX_M and stair_left <= STAIR_MAX_M, "issue-0005 (\"like a stair\", the car at (%.3f, %.3f) on %s chainage %.1f, %.2f m from its centreline): at junction %s %s ends and %s starts at one centre height %.2f m and one crossfall %+.4f, so the platform's edges 4.25 m out meet within %.3f m right and %.3f m left (was %.3f m and %.3f m: crossfall -0.0077 against +0.04 at one height)" % [ISSUE_0005_CAR.x, ISSUE_0005_CAR.y, nearest_5.get("road"), nearest_5.get("chainage", 0.0), nearest_5.get("distance", 0.0), ISSUE_0005_JUNCTION, ISSUE_0005_SEGMENTS[0], ISSUE_0005_SEGMENTS[1], b.dense[0], b.crossfall[0], stair_right, stair_left, RAW_ISSUE_0005_STAIR_M[0], RAW_ISSUE_0005_STAIR_M[1]], "issue-0005: heights %s / %s, crossfall %s / %s, stair %.3f / %.3f, the car over %s" % [a.dense[a.dense.size() - 1], b.dense[0], a.crossfall[a.crossfall.size() - 1], b.crossfall[0], stair_right, stair_left, nearest_5.get("road")])
	var probe := _seam_probe(profile, raw_points[ISSUE_0005_SEGMENTS[0]], raw_points[ISSUE_0005_SEGMENTS[1]])
	_ok(probe.worst <= SEAM_PROBE_MAX_M, "issue-0005 in the field: sample_height %.2f m before and after the node at %.0f m left, on the centreline and %.0f m right steps %.3f, %.3f and %.3f m (the grade over those %.1f m and the rounding; a stair of 0.15-0.26 m read here before)" % [SEAM_PROBE_ALONG_M, SEAM_PROBE_OFFSET_M, SEAM_PROBE_OFFSET_M, probe.steps[0], probe.steps[1], probe.steps[2], 2.0 * SEAM_PROBE_ALONG_M], "the field steps %s across the seam" % [probe.steps])
	# Issue-0001's ridge at T13.
	var pit: Dictionary = records[ISSUE_0001_SEGMENTS[2]]
	var loop_in: Dictionary = records[ISSUE_0001_SEGMENTS[0]]
	var loop_out: Dictionary = records[ISSUE_0001_SEGMENTS[1]]
	var ridge: float = absf(_edge_height(pit, pit.dense.size() - 1, pit.crossfall.size() - 1, 4.25) - _edge_height(loop_out, 0, 0, 4.25))
	var nearest_1: Dictionary = profile.describe(ISSUE_0001_CAR.x, ISSUE_0001_CAR.y)
	_ok(nearest_1.get("distance", 99.0) < 4.25 and pit.crossfall[pit.crossfall.size() - 1] == loop_out.crossfall[0] and loop_in.crossfall[loop_in.crossfall.size() - 1] == loop_out.crossfall[0] and pit.dense[pit.dense.size() - 1] == loop_out.dense[0] and ridge <= STAIR_MAX_M, "issue-0001 (\"very pointy\", the car at (%.3f, %.3f) over %s, %.2f m from its centreline, %.2f m from the T13 junction %s): the pit lane %s ends on the loop's node at the loop's own crossfall %+.4f and height %.2f m (was -0.04 against the loop's +0.04: a %.3f m ridge at the paved edge; now %.3f m)" % [ISSUE_0001_CAR.x, ISSUE_0001_CAR.y, nearest_1.get("road"), nearest_1.get("distance", 0.0), ISSUE_0001_CAR.distance_to(Vector2(2015.436, -1370.741)), ISSUE_0001_JUNCTION, ISSUE_0001_SEGMENTS[2], loop_out.crossfall[0], loop_out.dense[0], RAW_ISSUE_0001_RIDGE_M, ridge], "issue-0001: pit crossfall %s, loop %s / %s, heights %s / %s, ridge %.3f, the car over %s" % [pit.crossfall[pit.crossfall.size() - 1], loop_in.crossfall[loop_in.crossfall.size() - 1], loop_out.crossfall[0], pit.dense[pit.dense.size() - 1], loop_out.dense[0], ridge, nearest_1.get("road")])
	# The ±50 m windows at the three sites.
	for window: Dictionary in WINDOWS:
		var record: Dictionary = records[window.id]
		var stations := WorldRoadProfile.station_chainages(_length_of(raw_points[window.id]))
		var inside: Array[int] = []
		for k: int in stations.size():
			if absf(stations[k] - window.at) <= WINDOW_HALF_M:
				inside.append(k)
		var changes := PackedFloat64Array()
		for i: int in range(1, inside.size() - 1):
			changes.append((record.dense[inside[i + 1]] - 2.0 * record.dense[inside[i]] + record.dense[inside[i - 1]]) / 4.0)
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
		_ok(inside.size() >= 10 and p2p <= window.max_p2p + 1e-9 and p2p <= window.raw_p2p + 1e-9 and label_ok, "%s, %s over %.0f..%.0f m (%d stations): the grade-change peak-to-peak is %.4f /m, %.1f %% per station (raw %.4f, %.1f %%; at most %.4f asked)%s" % [window.issue, window.id, stations[inside[0]], stations[inside[inside.size() - 1]], inside.size(), p2p, 200.0 * p2p, window.raw_p2p, 200.0 * window.raw_p2p, window.max_p2p, label_text], "%s %s: p2p %.4f (raw %.4f, max %.4f), label ok %s" % [window.issue, window.id, p2p, window.raw_p2p, window.max_p2p, label_ok])


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
	_ok(bend_record.id == "4-0" and bend_record.crossfall == [0.04, 0.04, 0.04] and absf(bend_right - bend_left - 0.16) < MM, "fixture: the left-hand bend is superelevated 4 %% (R 70.7 m, capped): crossfall [0.04, 0.04, 0.04], 16 cm higher 2 m right than 2 m left", "bend crossfall %s, across %.3f" % [bend_record.crossfall, bend_right - bend_left])
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
	_ok(karussell_record.id == "414785755-0" and karussell_record.crossfall == [0.3, 0.3, 0.3] and karussell_record.labels.back().kind == "bank" and absf(bowl_strip - bowl_inside) < MM and absf(bowl_outside - bowl_inside - 1.95) < MM and absf(bowl_centre - _plane(2050.0, -2600.0)) < MM, "fixture: way 414785755 takes the bank: flat over the 1 m strip, 1.95 m up at the outside edge, the centre on the ground", "bank: crossfall %s, across %.3f %.3f %.3f %.3f" % [karussell_record.crossfall, bowl_inside, bowl_strip, bowl_centre, bowl_outside])
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
