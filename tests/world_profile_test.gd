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
## code names the field. No network, no python, no DGM1: drape.py is never
## run by the suite. Seconds, right after the skeleton test in
## run_tests.sh: static data that fails first. Writes nothing under /tmp.
## Exits 0 on success, 1 on any fault.

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
## left-hander, and a diagonal across the lattice's seams at (1000, -1000).
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
	_ok(profile.road_count() == 6 and profile.coverage() == Rect2(0.0, -FIXTURE_SIZE_M, FIXTURE_SIZE_M, FIXTURE_SIZE_M), "fixture: 6 roads, coverage 0..3000 × -3000..0")
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
