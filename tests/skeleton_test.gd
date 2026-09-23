extends SceneTree
## Headless skeleton test: the Ring's checked-in skeleton
## (data/regions/eifel_ring/skeleton.json, written offline by
## tools/world/skeleton.py from the pinned OSM snapshot) is read the way
## SkeletonLoader reads it and has to pass its validation, then is held to
## what the plan asks (implementation-plan.md §4B-2): the snapshot id present
## and pinned; every junction with ≥ 2 segments and every listed segment
## there (both ways round); widths by class the table's; relation 38566's
## members closing into one loop (first point == last point within 0.5 m)
## and its length within 1 % of 20 830 m; the projection held to pyproj's
## numbers on a pinned reference table (< 0.01 m at the origin, < 0.5 m at
## 20 km) through the loader's own forward projection; the checked-in
## Karussell sample's three ways present with their endpoints where the
## sample's lat/lon say. Then a five-way fixture built here (never on disk)
## goes through the same checks, and validate() on fixtures broken in code
## names the field. No network, no python: the extract is not the suite's.
## The DP proofs (every removed node < 0.3 m off its chord, every node with
## a heading change > 1° kept) need the raw snapshot and pyproj and live in
## `tools/world/skeleton.py --selftest`, run by hand and reported.
## Seconds, right after the element catalogue test in run_tests.sh: static
## data that fails first. Exits 0 on success, 1 on any fault.

## The pinned snapshot (ring-region-decisions.md §1, put in stone): held
## here as its own literal so a change in the loader's constant is a change
## here too ("was ->").
const PINNED_OSM_BASE := "2026-09-22T08:45:51Z"
const BBOX := [50.3, 6.8, 50.45, 7.1]
const E0 := 352000.0  # [m]
const N0 := 5577000.0  # [m]

## data-pipeline.md §4's width table [m], total paved: the numbers the file
## has to carry by class (the *_link classes and motorway/trunk as skeleton.py
## chose, flagged there).
const WIDTH_TABLE_M := {
	"motorway": 7.5, "trunk": 7.5, "motorway_link": 7.5, "trunk_link": 7.5,
	"primary": 7.0, "primary_link": 7.0,
	"secondary": 6.5, "secondary_link": 6.5,
	"tertiary": 6.0, "tertiary_link": 6.0, "unclassified": 6.0,
	"residential": 5.5, "living_street": 5.5,
	"service": 3.0, "track": 3.0,
	"raceway": 8.5,
}
const KARUSSELL_WAY := 414785755
const KARUSSELL_WIDTH_M := 7.5  # [m] ring-region-decisions.md §2

## The Nordschleife: relation 38566, official lap 20.830 km
## (docs/nordschleife-data-sources.md §4; ring-region-decisions.md §2), the
## loop's chords within 1 % of it (implementation-plan.md §4B-2).
const NORDSCHLEIFE_RELATION := 38566
const LAP_LENGTH_M := 20830.0
const LAP_TOLERANCE := 0.01
const JOIN_TOLERANCE_M := 0.5  # [m] the plan's closure tolerance

## The projection reference: pyproj 3.8.0 (PROJ 9.8.1), EPSG:4326 ->
## EPSG:25832 always_xy, then x = E - E0, z = -(N - N0), mm-rounded; lat/lon
## to 1e-9°. The origin, 20 km east and north of it, the bbox corners and
## the Karussell sample's way endpoints. Regenerate with
## `venv/bin/python tools/world/skeleton.py --reference` (the venv:
## python3 -m venv venv && venv/bin/pip install pyproj).
const REFERENCE := [
	{"name": "origin", "lat": 50.326491642, "lon": 6.920696712, "x": 0.000, "z": 0.000},
	{"name": "20 km east", "lat": 50.331175920, "lon": 7.201525108, "x": 20000.000, "z": 0.000},
	{"name": "20 km north", "lat": 50.506240741, "lon": 6.912810023, "x": 0.000, "z": -20000.000},
	{"name": "bbox south-west", "lat": 50.300000000, "lon": 6.800000000, "x": -8677.226, "z": 2698.197},
	{"name": "bbox north-east", "lat": 50.450000000, "lon": 7.100000000, "x": 13112.423, "z": -13390.509},
	{"name": "sample way 414785755 first node", "lat": 50.372269000, "lon": 6.985930000, "x": 4780.602, "z": -4961.756},
	{"name": "sample way 414785755 last node", "lat": 50.371908000, "lon": 6.986479000, "x": 4818.551, "z": -4920.563},
	{"name": "sample way 414785756 first node", "lat": 50.371908000, "lon": 6.986479000, "x": 4818.551, "z": -4920.563},
	{"name": "sample way 414785756 last node", "lat": 50.376422000, "lon": 6.997834000, "x": 5639.457, "z": -5400.625},
	{"name": "sample way 799394513 first node", "lat": 50.374428000, "lon": 6.986927000, "x": 4857.991, "z": -5199.872},
	{"name": "sample way 799394513 last node", "lat": 50.372269000, "lon": 6.985930000, "x": 4780.602, "z": -4961.756},
]
const ORIGIN_ERROR_M := 0.01  # [m] the plan's limit at the origin
const FAR_ERROR_M := 0.5  # [m] the plan's limit at 20 km
const SAMPLE_PATH := "res://docs/design/4b/samples/nordschleife-karussell-sample.json"

var _failures := 0


func _initialize() -> void:
	var data: Variant = SkeletonLoader.read_file()
	_check_file(data)
	if data is Dictionary:
		var segments := SkeletonLoader.segments_of(data)
		var junctions := SkeletonLoader.junctions_of(data)
		_check_snapshot(data)
		_check_segments(segments)
		_check_junctions(junctions, segments)
		_check_widths(segments)
		_check_loop(SkeletonLoader.loops_of(data), segments)
		_check_projection()
		_check_sample(segments)
		_check_lookups(segments, junctions)
	_check_fixture()
	_check_broken_fixtures()
	print("SKELETON TEST PASSED" if _failures == 0 else "SKELETON TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


## The file is there, is JSON, parses twice to the same bytes, and passes
## validate() with nothing to say.
func _check_file(data: Variant) -> void:
	var reparsed: Variant = SkeletonLoader.read_file()
	_ok(data is Dictionary and var_to_bytes(data) == var_to_bytes(reparsed), "%s parses, and parsed twice it comes out the same" % SkeletonLoader.PATH, "%s: %s" % [SkeletonLoader.PATH, "not a JSON object" if not data is Dictionary else "parsed twice, it does not come out the same"])
	var errors := SkeletonLoader.validate(data)
	for error: String in errors:
		printerr("  FAIL  ", error)
	_failures += errors.size()
	_ok(errors.is_empty(), "the skeleton passes SkeletonLoader.validate() with nothing to say")


## The snapshot id present and pinned, the bbox the Ring's, the origin the
## frame put in stone.
func _check_snapshot(data: Dictionary) -> void:
	var snapshot: Dictionary = data.get("snapshot", {})
	_ok(snapshot.get("osm_base") == PINNED_OSM_BASE, "snapshot.osm_base is the pinned %s" % PINNED_OSM_BASE, "snapshot.osm_base is %s, the pinned snapshot is %s" % [snapshot.get("osm_base"), PINNED_OSM_BASE])
	_ok(snapshot.get("bbox") == BBOX, "snapshot.bbox is the Ring's %s" % [BBOX], "snapshot.bbox is %s" % [snapshot.get("bbox")])
	_ok(snapshot.get("query_sha") is String and snapshot.query_sha.length() == 64, "snapshot.query_sha is a sha256 of the six queries: %s" % snapshot.get("query_sha"))
	_ok(snapshot.get("pipeline_version") == 1, "snapshot.pipeline_version is the pipeline's %d" % snapshot.get("pipeline_version", -1), "snapshot.pipeline_version is %s" % [snapshot.get("pipeline_version")])
	var origin: Dictionary = data.get("origin", {})
	_ok(origin.get("epsg") == 25832 and origin.get("e0") == E0 and origin.get("n0") == N0, "origin is EPSG:25832, E0 %d, N0 %d" % [E0, N0], "origin is %s" % [origin])


## Every segment: an id of the form, unique (the dictionary is by id, so
## the count says it), at least two finite points, sorted by id.
func _check_segments(segments: Dictionary) -> void:
	var ids := segments.keys()
	var forms := 0
	var short := 0
	var sorted := true
	var points := 0
	for i: int in ids.size():
		var segment: SkeletonLoader.Segment = segments[ids[i]]
		forms += 1 if SkeletonLoader.is_segment_id(segment.id) and str(segment.osm_way) == segment.id.split("-")[0] else 0
		short += 1 if segment.points.size() < 2 else 0
		sorted = sorted and (i == 0 or ids[i - 1] < ids[i])
		points += segment.points.size()
	_ok(forms == ids.size() and not ids.is_empty(), "%d segments, every id of the form way-index and unique, osm_way the id's way" % ids.size(), "%d of %d segment ids of the form" % [forms, ids.size()])
	_ok(short == 0, "every segment has ≥ 2 points (%d points in all)" % points, "%d segments with fewer than 2 points" % short)
	_ok(sorted, "segments are sorted by id")


## Every junction has ≥ 2 segments, each there and ending on it; and every
## segment end that sits on a junction is listed by it (the reverse).
func _check_junctions(junctions: Dictionary, segments: Dictionary) -> void:
	var at := {}
	var too_few := 0
	var missing := 0
	var away := 0
	for junction: SkeletonLoader.Junction in junctions.values():
		at["%.3f,%.3f" % [junction.position.x, junction.position.y]] = junction
		too_few += 1 if junction.segments.size() < 2 else 0
		for id: String in junction.segments:
			if not segments.has(id):
				missing += 1
			elif junction.position.distance_to(segments[id].first()) > JOIN_TOLERANCE_M and junction.position.distance_to(segments[id].last()) > JOIN_TOLERANCE_M:
				away += 1
	var unlisted := 0
	var ends_on_junctions := 0
	for segment: SkeletonLoader.Segment in segments.values():
		for endpoint: Vector2 in [segment.first(), segment.last()]:
			var junction: Variant = at.get("%.3f,%.3f" % [endpoint.x, endpoint.y])
			if junction != null:
				ends_on_junctions += 1
				unlisted += 1 if not segment.id in junction.segments else 0
	_ok(too_few == 0 and not junctions.is_empty(), "%d junctions, every one with ≥ 2 segments" % junctions.size(), "%d junctions with fewer than 2 segments" % too_few)
	_ok(missing == 0 and away == 0, "every segment a junction lists is there and ends within %s m of it" % JOIN_TOLERANCE_M, "%d listed segments missing, %d not ending on their junction" % [missing, away])
	_ok(unlisted == 0, "every segment end on a junction is listed by it (%d ends)" % ends_on_junctions, "%d segment ends on a junction not listed by it" % unlisted)


## Widths: by class the table's, one line per class in the file; by tag
## inside the band; the Karussell 7.5 m.
func _check_widths(segments: Dictionary) -> void:
	var by_class := {}
	var by_tag := {}
	var wrong := {}
	var raceway_by_tag := 0
	var karussell := []
	for segment: SkeletonLoader.Segment in segments.values():
		var expected: float = WIDTH_TABLE_M.get(segment.road_class, -1.0)
		if segment.osm_way == KARUSSELL_WAY:
			karussell.append(segment.width_m)
			expected = KARUSSELL_WIDTH_M
		if segment.width_source == "class":
			by_class[segment.road_class] = by_class.get(segment.road_class, 0) + 1
			if segment.width_m != expected:
				wrong[segment.road_class] = wrong.get(segment.road_class, 0) + 1
		else:
			by_tag[segment.road_class] = by_tag.get(segment.road_class, 0) + 1
			raceway_by_tag += 1 if segment.road_class == "raceway" else 0
			if not SkeletonLoader.tag_width_plausible(segment.road_class, segment.width_m):
				wrong[segment.road_class] = wrong.get(segment.road_class, 0) + 1
	var classes := by_class.keys()
	classes.sort()
	for road_class: String in classes:
		_ok(not wrong.has(road_class), "%s: %d segments by class at %.1f m (the table's), %d by tag inside [%.2f, %.2f] m" % [road_class, by_class[road_class], WIDTH_TABLE_M.get(road_class, -1.0), by_tag.get(road_class, 0), 0.5 * WIDTH_TABLE_M.get(road_class, -1.0), 2.0 * WIDTH_TABLE_M.get(road_class, -1.0)], "%s: %d segments with a width that is not the table's or outside the band" % [road_class, wrong.get(road_class, 0)])
	_ok(raceway_by_tag == 0, "no raceway takes a width=* tag (OSM width=5 ignored, ring-region-decisions.md §2)", "%d raceway segments by tag" % raceway_by_tag)
	_ok(not karussell.is_empty() and karussell.count(KARUSSELL_WIDTH_M) == karussell.size(), "the Karussell (way %d) is %.1f m wide" % [KARUSSELL_WAY, KARUSSELL_WIDTH_M], "the Karussell's widths are %s" % [karussell])


## The Nordschleife loop: relation 38566, one chain of raceway segments each
## joining the last within 0.5 m, closing, within 1 % of the lap.
func _check_loop(loops: Dictionary, segments: Dictionary) -> void:
	var loop: SkeletonLoader.Loop = loops.get(SkeletonLoader.NORDSCHLEIFE_LOOP)
	if loop == null:
		_ok(false, "", "no loop named %s" % SkeletonLoader.NORDSCHLEIFE_LOOP)
		return
	_ok(loop.rel == NORDSCHLEIFE_RELATION, "loop %s is relation %d" % [loop.id, NORDSCHLEIFE_RELATION], "loop %s is relation %d" % [loop.id, loop.rel])
	var raceway := 0
	var oneway := 0
	var ways := {}
	for i: int in loop.segments.size():
		var id: String = loop.segments[i]
		var segment: SkeletonLoader.Segment = segments.get(id)
		if segment == null:
			_ok(false, "", "loop segment %d (%s) is not in the skeleton" % [i, id])
			continue
		raceway += 1 if segment.road_class == "raceway" else 0
		oneway += 1 if segment.tags.get("oneway") == "yes" else 0
		ways[segment.osm_way] = true
		if i > 0:
			var previous: SkeletonLoader.Segment = segments.get(loop.segments[i - 1])
			var gap := _join_gap(previous, segment)
			_ok(gap <= JOIN_TOLERANCE_M, "loop segment %d %s (%s) joins %s within %.3f m" % [i, id, segment.tags.get("name", "unnamed"), previous.id, gap], "loop segment %d %s is %.3f m from %s" % [i, id, gap, previous.id])
	var fault := SkeletonLoader.loop_fault(loop, segments)
	_ok(fault == "", "the loop closes: its last point meets its first within %s m" % JOIN_TOLERANCE_M, fault)
	var length := SkeletonLoader.loop_length(loop, segments)
	_ok(absf(length - LAP_LENGTH_M) <= LAP_TOLERANCE * LAP_LENGTH_M, "the loop is %.1f m over %d segments of %d ways, within 1 %% of the %d m lap" % [length, loop.segments.size(), ways.size(), LAP_LENGTH_M], "the loop is %.1f m, not within 1 %% of %d m" % [length, LAP_LENGTH_M])
	_ok(raceway == loop.segments.size() and oneway == loop.segments.size(), "every loop segment is a raceway and oneway=yes", "%d raceway, %d oneway of %d" % [raceway, oneway, loop.segments.size()])


## The closest pair of endpoints of two segments [m].
func _join_gap(a: SkeletonLoader.Segment, b: SkeletonLoader.Segment) -> float:
	var gap := INF
	for p: Vector2 in [a.first(), a.last()]:
		for q: Vector2 in [b.first(), b.last()]:
			gap = minf(gap, p.distance_to(q))
	return gap


## The loader's projection held to pyproj's reference: < 0.01 m at the
## origin, < 0.5 m elsewhere (20 km and the rest of the table).
func _check_projection() -> void:
	for row: Dictionary in REFERENCE:
		var got := SkeletonLoader.wgs84_to_local(row.lat, row.lon)
		var error := got.distance_to(Vector2(row.x, row.z))
		var limit: float = ORIGIN_ERROR_M if row.name == "origin" else FAR_ERROR_M
		_ok(error < limit, "projection at %s: (%.3f, %.3f) within %.4f m of pyproj's (%.3f, %.3f), limit %.2f m" % [row.name, got.x, got.y, error, row.x, row.z, limit], "projection at %s is (%.3f, %.3f), pyproj's is (%.3f, %.3f): %.3f m off" % [row.name, got.x, got.y, row.x, row.z, error])


## The checked-in Karussell sample's three ways are in the skeleton, and
## their endpoints (projected here from the sample's lat/lon) sit where the
## file's points are, within 0.5 m (the sample is rounded to 1e-6°).
func _check_sample(segments: Dictionary) -> void:
	var sample: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAMPLE_PATH))
	_ok(sample is Dictionary and sample.get("osm_base") == PINNED_OSM_BASE, "the sample is from the pinned snapshot too")
	if not sample is Dictionary:
		return
	var by_way := {}
	for segment: SkeletonLoader.Segment in segments.values():
		by_way.get_or_add(segment.osm_way, []).append(segment)
	for way: Dictionary in sample.elements:
		var pieces: Array = by_way.get(int(way.id), [])
		if pieces.is_empty():
			_ok(false, "", "sample way %d (%s) is not in the skeleton" % [way.id, way.tags.get("name")])
			continue
		pieces.sort_custom(func(a: SkeletonLoader.Segment, b: SkeletonLoader.Segment) -> bool: return int(a.id.split("-")[1]) < int(b.id.split("-")[1]))
		var first_node: Array = way.geometry_latlon[0]
		var last_node: Array = way.geometry_latlon[way.geometry_latlon.size() - 1]
		var first_error: float = SkeletonLoader.wgs84_to_local(first_node[0], first_node[1]).distance_to(pieces[0].first())
		var last_error: float = SkeletonLoader.wgs84_to_local(last_node[0], last_node[1]).distance_to(pieces[pieces.size() - 1].last())
		_ok(first_error < JOIN_TOLERANCE_M and last_error < JOIN_TOLERANCE_M, "sample way %d (%s) is in the skeleton as %d segment(s), endpoints within %.3f m of the sample's lat/lon" % [way.id, way.tags.get("name"), pieces.size(), maxf(first_error, last_error)], "sample way %d: endpoints %.3f m and %.3f m off" % [way.id, first_error, last_error])


## The lookups answer from the file, and say nothing for what is not there.
func _check_lookups(segments: Dictionary, junctions: Dictionary) -> void:
	var first: SkeletonLoader.Segment = segments.values()[0]
	_ok(SkeletonLoader.segment(first.id) != null and SkeletonLoader.segment(first.id).id == first.id, "segment(\"%s\") answers" % first.id)
	_ok(SkeletonLoader.segment("1-0") == null and SkeletonLoader.segment("") == null, "segment() of an id that is not there is null")
	_ok(SkeletonLoader.segments().size() == segments.size() and SkeletonLoader.junctions().size() == junctions.size(), "segments() and junctions() are the file's %d and %d" % [segments.size(), junctions.size()])
	var junction: SkeletonLoader.Junction = junctions.values()[0]
	_ok(SkeletonLoader.junction(junction.id) != null and SkeletonLoader.junction("0") == null, "junction(\"%s\") answers, junction(\"0\") is null" % junction.id)
	_ok(SkeletonLoader.loop(SkeletonLoader.NORDSCHLEIFE_LOOP) != null and SkeletonLoader.loop("gp") == null, "loop(\"%s\") answers, loop(\"gp\") is null" % SkeletonLoader.NORDSCHLEIFE_LOOP)
	_ok(SkeletonLoader.snapshot().get("osm_base") == PINNED_OSM_BASE and SkeletonLoader.origin().get("e0") == E0, "snapshot() and origin() answer")


## A five-way fixture in the file's shape, built here: a primary crossed by
## a residential (width by tag) at one junction and met by a oneway service
## (width tag outside the band) at another, ending where two raceway ways
## (one with the ignored width=5) make a mini loop. Metres, not lat/lon:
## the shape is the point.
func _fixture() -> Dictionary:
	return {
		"snapshot": {"osm_base": PINNED_OSM_BASE, "bbox": BBOX, "query_sha": "0".repeat(64), "pipeline_version": 1},
		"origin": {"epsg": 25832, "e0": E0, "n0": N0},
		"segments": [
			{"id": "1-0", "osm_way": 1, "class": "primary", "width_m": 7.0, "width_source": "class", "ref": "B 999", "points": [[0.0, 0.0], [100.0, 0.0]]},
			{"id": "1-1", "osm_way": 1, "class": "primary", "width_m": 7.0, "width_source": "class", "ref": "B 999", "points": [[100.0, 0.0], [200.0, 0.0]]},
			{"id": "1-2", "osm_way": 1, "class": "primary", "width_m": 7.0, "width_source": "class", "ref": "B 999", "points": [[200.0, 0.0], [300.0, 0.0]]},
			{"id": "2-0", "osm_way": 2, "class": "residential", "width_m": 4.5, "width_source": "tag", "name": "Ringstraße", "points": [[100.0, -50.0], [100.0, 0.0]]},
			{"id": "2-1", "osm_way": 2, "class": "residential", "width_m": 4.5, "width_source": "tag", "name": "Ringstraße", "points": [[100.0, 0.0], [100.0, 50.0]]},
			{"id": "3-0", "osm_way": 3, "class": "service", "width_m": 3.0, "width_source": "class", "oneway": "yes", "points": [[200.0, -60.0], [200.0, 0.0]]},
			{"id": "4-0", "osm_way": 4, "class": "raceway", "width_m": 8.5, "width_source": "class", "oneway": "yes", "points": [[300.0, 0.0], [350.0, -40.0], [300.0, -80.0]]},
			{"id": "5-0", "osm_way": 5, "class": "raceway", "width_m": 8.5, "width_source": "class", "oneway": "yes", "points": [[300.0, -80.0], [250.0, -40.0], [300.0, 0.0]]},
		],
		"junctions": [
			{"id": "12", "x": 100.0, "z": 0.0, "segments": ["1-0", "1-1", "2-0", "2-1"]},
			{"id": "13", "x": 200.0, "z": 0.0, "segments": ["1-1", "1-2", "3-0"]},
			{"id": "14", "x": 300.0, "z": 0.0, "segments": ["1-2", "4-0", "5-0"]},
			{"id": "42", "x": 300.0, "z": -80.0, "segments": ["4-0", "5-0"]},
		],
		"loops": [{"id": "mini", "rel": 99, "segments": ["4-0", "5-0"]}],
	}


## The fixture through the loader's checks.
func _check_fixture() -> void:
	var data := _fixture()
	var errors := SkeletonLoader.validate(data)
	_ok(errors.is_empty(), "the five-way fixture passes validate()", "the fixture: %s" % [errors])
	var segments := SkeletonLoader.segments_of(data)
	var junctions := SkeletonLoader.junctions_of(data)
	var loops := SkeletonLoader.loops_of(data)
	_ok(segments.size() == 8 and junctions.size() == 4, "fixture: 5 ways split at 4 junctions make 8 segments")
	var fewer := 0
	for junction: SkeletonLoader.Junction in junctions.values():
		fewer += 1 if junction.segments.size() < 2 else 0
	_ok(fewer == 0 and junctions["12"].segments.size() == 4, "fixture: every junction has ≥ 2 segments, the crossing 4")
	_ok(segments["1-0"].width_m == WIDTH_TABLE_M.primary and segments["3-0"].width_m == WIDTH_TABLE_M.service and segments["4-0"].width_m == WIDTH_TABLE_M.raceway, "fixture: primary 7.0, service 3.0 (width=40 outside the band), raceway 8.5 (width=5 ignored), by class")
	_ok(segments["2-0"].width_source == "tag" and SkeletonLoader.tag_width_plausible("residential", 4.5), "fixture: residential 4.5 m by tag, inside [0.5, 2] × 5.5")
	_ok(segments["3-0"].tags.get("oneway") == "yes" and not segments["1-0"].tags.has("oneway") and segments["2-1"].tags.get("name") == "Ringstraße", "fixture: oneway and name carried only where tagged")
	var forms := 0
	for id: String in segments:
		forms += 1 if SkeletonLoader.is_segment_id(id) else 0
	_ok(forms == 8 and SkeletonLoader.is_junction_id("42") and not SkeletonLoader.is_segment_id("1-") and not SkeletonLoader.is_segment_id("01-0"), "fixture: ids of the form way-index and node id; \"1-\" and \"01-0\" are not")
	var mini: SkeletonLoader.Loop = loops["mini"]
	_ok(SkeletonLoader.loop_fault(mini, segments) == "", "fixture: the two-way mini loop closes within %s m" % JOIN_TOLERANCE_M, SkeletonLoader.loop_fault(mini, segments))
	_ok(is_equal_approx(SkeletonLoader.loop_length(mini, segments), 4.0 * sqrt(50.0 * 50.0 + 40.0 * 40.0)), "fixture: the mini loop is four 64.031 m chords, %.3f m" % SkeletonLoader.loop_length(mini, segments))
	_ok(segments["4-0"].length() == segments["5-0"].length() and is_equal_approx(segments["1-0"].length(), 100.0), "fixture: segment lengths chord by chord")


## validate() on fixtures broken in code, one per fault kind, names the
## thing and the field.
func _check_broken_fixtures() -> void:
	_expect_fault(_broken_snapshot("osm_base", "2026-09-23T00:00:00Z"), "snapshot.osm_base is 2026-09-23T00:00:00Z, the pinned snapshot is", "a snapshot that is not the pinned one")
	_expect_fault(_broken_snapshot("bbox", [50.3, 6.8, 50.45, 7.2]), "snapshot.bbox is", "a bbox that is not the Ring's")
	_expect_fault(_broken_origin("e0", 0.0), "origin.e0 is 0", "an origin that is not the frame's")
	_expect_fault(_broken_segment("1-0", "width_m", 6.0), "segment 1-0.width_m is 6.0 by class, primary's is 7.0", "a width by class that is not the table's")
	_expect_fault(_broken_segment("2-0", "width_m", 12.0), "segment 2-0.width_m is 12.0 by tag, outside residential's band", "a width by tag outside the band")
	_expect_fault(_broken_segment("4-0", "width_source", "tag"), "segment 4-0.width_m is 8.5 by tag, outside raceway's band", "a raceway width by tag")
	_expect_fault(_broken_segment("1-0", "class", "footway"), "segment 1-0.class is footway, not a class of the width table", "a class outside the table")
	_expect_fault(_broken_segment("1-0", "points", [[0.0, 0.0]]), "segment 1-0.points has 1, a segment has at least two", "a segment with one point")
	_expect_fault(_broken_segment("1-0", "osm_way", 7), "segment 1-0.osm_way is 7, not the id's way", "an osm_way that is not the id's")
	_expect_fault(_broken_segment("1-0", "id", "1-3"), "segment 1-1 comes after 1-3, segments are sorted by id", "segments out of order")
	_expect_fault(_broken_segment("1-0", "lanes", "2"), "segment 1-0.lanes is not in the schema", "a key the schema does not know")
	_expect_fault(_broken_junction("42", "segments", ["4-0"]), "junction 42 has 1 segment(s), a junction joins at least two", "a junction with one segment")
	_expect_fault(_broken_junction("42", "segments", ["4-0", "9-0"]), "junction 42 lists segment 9-0, which is not there", "a junction listing a segment that is not there")
	_expect_fault(_broken_junction("42", "segments", ["4-0", "1-0"]), "junction 42 lists segment 1-0, which does not end within 0.5 m of it", "a junction listing a segment that does not end on it")
	_expect_fault(_broken_junction("13", "segments", ["1-1", "1-2"]), "segment 3-0 ends on junction 13, which does not list it", "a segment end on a junction that does not list it")
	_expect_fault(_broken_loop("segments", ["4-0", "1-0"]), "loop mini: 4-0 and 1-0 share no endpoint within 0.5 m", "a loop whose segments do not join")
	_expect_fault(_broken_loop("segments", ["1-0", "1-1"]), "loop mini does not close: its last point is 200.000 m from its first", "a loop that does not close")
	_expect_fault(null, "not a JSON object", "a file that is not JSON")


func _broken_snapshot(key: String, value: Variant) -> Dictionary:
	var data := _fixture()
	data.snapshot[key] = value
	return data


func _broken_origin(key: String, value: Variant) -> Dictionary:
	var data := _fixture()
	data.origin[key] = value
	return data


func _broken_segment(id: String, key: String, value: Variant) -> Dictionary:
	var data := _fixture()
	for segment: Dictionary in data.segments:
		if segment.id == id:
			segment[key] = value
	return data


func _broken_junction(id: String, key: String, value: Variant) -> Dictionary:
	var data := _fixture()
	for junction: Dictionary in data.junctions:
		if junction.id == id:
			junction[key] = value
	return data


func _broken_loop(key: String, value: Variant) -> Dictionary:
	var data := _fixture()
	data.loops[0][key] = value
	return data


## One broken fixture: validate() has to say something with `expected` in it.
func _expect_fault(fixture: Variant, expected: String, what: String) -> void:
	var errors := SkeletonLoader.validate(fixture)
	var named := false
	for error: String in errors:
		if error.contains(expected):
			named = true
	_ok(named, "validate() names %s: \"%s\"" % [what, expected], "validate() on %s says %s, not \"%s\"" % [what, errors, expected])
