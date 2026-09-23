class_name SkeletonLoader
extends RefCounted
## The Ring's road skeleton (docs/design/4b/data-pipeline.md §4) as the game
## reads it: data/regions/eifel_ring/skeleton.json, written offline by
## tools/world/skeleton.py from the pinned OSM snapshot, read here into typed
## segments, junctions and loops. A segment is one piece of one OSM way
## between two junctions: its class, its paved width and where the width
## came from, the OSM tags the pipeline carries, and its centreline as
## [x, z] region metres (heights come with the drape, 4B-3). A junction is a
## node two or more ways share, with the segments that end there. A loop is
## an ordered chain of segments that closes: the Nordschleife, relation
## 38566. Nothing consumes it yet: no mesh, no profile, no scene reads the
## skeleton in 4B-2 (the plan's 4B-3 and 4B-4 do). It loads, it answers the
## lookups, and validate() says what is wrong with a skeleton.
##
## A class of static functions, as ElementCatalogue is, and no autoload.
## validate() is stateless: it takes what JSON.parse_string made of a file
## and returns one line per fault; empty = valid. The lookups keep the one
## piece of state there is: the file read once, on the first lookup.
##
## chosen for the skeleton: wgs84_to_local() is the pipeline's projection
## done again here (EPSG:4326 -> EPSG:25832, then the region's affine), so
## the suite can hold the file's coordinates to pyproj's without pyproj,
## and so a region file may later name a place by lat/lon. The game still
## never projects at run time; the skeleton is already in metres.

## Where the Ring's skeleton is. One region in 4B; a region id chooses the
## folder when there are more (4C).
const PATH := "res://data/regions/eifel_ring/skeleton.json"

## The pinned snapshot the Ring region was put in stone on
## (ring-region-decisions.md §1): a skeleton from another one is a
## documented re-pin, never something the loader takes quietly.
const PINNED_OSM_BASE := "2026-09-22T08:45:51Z"

## The Ring bbox [deg]: south, west, north, east (ring-region-decisions.md §1).
const BBOX := [50.3, 6.8, 50.45, 7.1]

## The region frame, put in stone (ring-region-decisions.md §1,
## data-pipeline.md §3): ETRS89 / UTM zone 32N, the origin on a DGM1 tile
## corner. Game x = E - E0, z = -(N - N0), y = height.
const EPSG := 25832
const E0 := 352000.0  # [m] easting of the origin
const N0 := 5577000.0  # [m] northing of the origin

## Total paved width by highway class [m], data-pipeline.md §4's table; the
## *_link classes at their parent's value and motorway/trunk at the 7.5 m
## carriageway, as tools/world/skeleton.py chose (flagged there).
const CLASS_WIDTH_M := {
	"motorway": 7.5, "trunk": 7.5, "motorway_link": 7.5, "trunk_link": 7.5,
	"primary": 7.0, "primary_link": 7.0,
	"secondary": 6.5, "secondary_link": 6.5,
	"tertiary": 6.0, "tertiary_link": 6.0, "unclassified": 6.0,
	"residential": 5.5, "living_street": 5.5,
	"service": 3.0, "track": 3.0,
	"raceway": 8.5,
}

## The Karussell, way 414785755: 7.5 m where the rest of the R17 is 8.5 m
## (ring-region-decisions.md §2, put in stone).
const KARUSSELL_WAY := 414785755
const KARUSSELL_WIDTH_M := 7.5  # [m]

## Where a segment's width came from: the class table, or an OSM width=*
## tag inside the plausibility band (skeleton.py's choice, flagged there:
## [0.5, 2.0] × the class value). A raceway never takes the tag.
const WIDTH_SOURCES := ["class", "tag"]
const TAG_WIDTH_BAND := [0.5, 2.0]  # [× class width]
const WIDTH_TAG_IGNORED_CLASSES := ["raceway"]

## The OSM tags a segment carries when the way has them (§4 item 4), the
## values as OSM strings.
const CARRIED_TAGS := ["bridge", "layer", "maxspeed", "name", "oneway", "ref", "surface", "tunnel"]

## A segment id is the OSM way id and the split index: "414785755-0". A
## junction id is the OSM node id. Both are stable across rebuilds.
const SEGMENT_ID_PATTERN := "^[1-9][0-9]*-(0|[1-9][0-9]*)$"
const JUNCTION_ID_PATTERN := "^[1-9][0-9]*$"
const QUERY_SHA_PATTERN := "^[0-9a-f]{64}$"

## The Nordschleife's loop: relation 38566, the R17 spine.
const NORDSCHLEIFE_LOOP := "nordschleife"
const NORDSCHLEIFE_RELATION := 38566

## How close two endpoints have to be to be one point [m]: the plan's
## closure tolerance (implementation-plan.md §4B-2), and the tolerance a
## junction sits from its segments' ends. The file is millimetre-rounded,
## so anything looser than a millimetre would do; 0.5 m is the plan's.
const JOIN_TOLERANCE_M := 0.5

## The schema (data-pipeline.md §4 item 6 plus the two additive fields:
## width_source, and loops).
const TOP_KEYS := ["snapshot", "origin", "segments", "junctions", "loops"]
const SNAPSHOT_KEYS := ["osm_base", "bbox", "query_sha"]
const ORIGIN_KEYS := ["epsg", "e0", "n0"]
const SEGMENT_REQUIRED_KEYS := ["id", "osm_way", "class", "width_m", "width_source", "points"]
const JUNCTION_KEYS := ["id", "x", "z", "segments"]
const LOOP_KEYS := ["id", "rel", "segments"]

## The projection's constants: GRS80 (ETRS89's ellipsoid) and UTM zone 32N.
## The forward transverse Mercator in Krüger's series to the sixth power of
## the third flattening (Karney 2011, "Transverse Mercator with an accuracy
## of a few nanometers"): sub-millimetre across the zone. WGS84 -> ETRS89 is
## the null transformation pyproj uses too (the datums agree to the metre
## and better in Europe at OSM's precision; the ellipsoids to 0.1 mm).
const GRS80_A := 6378137.0  # [m] semi-major axis
const GRS80_INVERSE_FLATTENING := 298.257222101
const UTM_K0 := 0.9996  # scale on the central meridian
const UTM32_LON0_DEG := 9.0  # [deg] central meridian of zone 32
const UTM_FALSE_EASTING := 500000.0  # [m]
const UTM_FALSE_NORTHING := 0.0  # [m] northern hemisphere


## One piece of one OSM way between two junctions.
class Segment:
	extends RefCounted
	var id: String
	var osm_way: int
	var road_class: String
	var width_m: float
	var width_source: String
	## The carried OSM tags that the way has (CARRIED_TAGS), values as strings.
	var tags: Dictionary
	## The centreline, [x, z] region metres, at least two points.
	var points: PackedVector2Array

	func first() -> Vector2:
		return points[0]

	func last() -> Vector2:
		return points[points.size() - 1]

	## The centreline's length [m], chord by chord.
	func length() -> float:
		var total := 0.0
		for i: int in range(1, points.size()):
			total += points[i].distance_to(points[i - 1])
		return total


## A node two or more ways share: where segments end.
class Junction:
	extends RefCounted
	var id: String
	var position: Vector2
	var segments: PackedStringArray


## An ordered chain of segments that closes.
class Loop:
	extends RefCounted
	var id: String
	var rel: int
	var segments: PackedStringArray


## The file read once: what JSON.parse_string made of it, and the typed
## records built from it. Only the lookups touch these.
static var _data: Dictionary = {}
static var _segments: Dictionary = {}
static var _junctions: Dictionary = {}
static var _loops: Dictionary = {}


## What JSON.parse_string makes of the file at `path`: null where it is
## missing or is not JSON. What validate() takes; what the test reads the
## same way.
static func read_file(path: String = PATH) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Whether `id` is a segment id of the documented form.
static func is_segment_id(id: String) -> bool:
	return RegEx.create_from_string(SEGMENT_ID_PATTERN).search(id) != null


## Whether `id` is a junction id of the documented form.
static func is_junction_id(id: String) -> bool:
	return RegEx.create_from_string(JUNCTION_ID_PATTERN).search(id) != null


## The table's paved width for a class [m], or -1.0 for a class outside it.
static func class_width(road_class: String) -> float:
	return CLASS_WIDTH_M.get(road_class, -1.0)


## What the pipeline gives a segment whose width is by class: the table's
## value, or the Karussell's.
static func width_by_class(osm_way: int, road_class: String) -> float:
	if osm_way == KARUSSELL_WAY:
		return KARUSSELL_WIDTH_M
	return class_width(road_class)


## Whether an OSM width=* of `width` metres is plausible for a class: inside
## the band, and the class one that takes the tag at all.
static func tag_width_plausible(road_class: String, width: float) -> bool:
	var by_class := class_width(road_class)
	if by_class < 0.0 or road_class in WIDTH_TAG_IGNORED_CLASSES:
		return false
	return width >= TAG_WIDTH_BAND[0] * by_class and width <= TAG_WIDTH_BAND[1] * by_class


## The snapshot block of the loaded file: osm_base, bbox, query_sha.
static func snapshot() -> Dictionary:
	return _file().get("snapshot", {})


## The origin block of the loaded file: epsg, e0, n0.
static func origin() -> Dictionary:
	return _file().get("origin", {})


## Every segment of the loaded file, in file order (sorted by id).
static func segments() -> Array[Segment]:
	var found: Array[Segment] = []
	for segment: Segment in _typed_segments().values():
		found.append(segment)
	return found


## The segment with this id, or null.
static func segment(id: String) -> Segment:
	return _typed_segments().get(id)


## Every junction of the loaded file, in file order (sorted by id).
static func junctions() -> Array[Junction]:
	var found: Array[Junction] = []
	for junction: Junction in _typed_junctions().values():
		found.append(junction)
	return found


## The junction with this id, or null.
static func junction(id: String) -> Junction:
	return _typed_junctions().get(id)


## Every loop of the loaded file, in file order.
static func loops() -> Array[Loop]:
	var found: Array[Loop] = []
	for loop: Loop in _typed_loops().values():
		found.append(loop)
	return found


## The loop with this id (NORDSCHLEIFE_LOOP), or null.
static func loop(id: String) -> Loop:
	return _typed_loops().get(id)


## The typed segments of `data` (what read_file() returns), keyed by id in
## file order; whatever is not a segment with a String id is skipped
## (validate() reports those). Points come out as Vector2(x, z).
static func segments_of(data: Variant) -> Dictionary:
	var found := {}
	if not data is Dictionary or not data.get("segments") is Array:
		return found
	for raw: Variant in data.segments:
		if not raw is Dictionary or not raw.get("id") is String or not raw.get("points") is Array:
			continue
		var segment := Segment.new()
		segment.id = raw.id
		segment.osm_way = int(raw.get("osm_way", 0))
		segment.road_class = str(raw.get("class", ""))
		segment.width_m = float(raw.get("width_m", 0.0))
		segment.width_source = str(raw.get("width_source", ""))
		for tag: String in CARRIED_TAGS:
			if raw.has(tag):
				segment.tags[tag] = str(raw[tag])
		var points := PackedVector2Array()
		for point: Variant in raw.points:
			if point is Array and point.size() == 2 and _is_number(point[0]) and _is_number(point[1]):
				points.append(Vector2(point[0], point[1]))
		segment.points = points
		found[segment.id] = segment
	return found


## The typed junctions of `data`, keyed by id in file order.
static func junctions_of(data: Variant) -> Dictionary:
	var found := {}
	if not data is Dictionary or not data.get("junctions") is Array:
		return found
	for raw: Variant in data.junctions:
		if not raw is Dictionary or not raw.get("id") is String or not raw.get("segments") is Array:
			continue
		var junction := Junction.new()
		junction.id = raw.id
		junction.position = Vector2(float(raw.get("x", 0.0)), float(raw.get("z", 0.0)))
		for id: Variant in raw.segments:
			junction.segments.append(str(id))
		found[junction.id] = junction
	return found


## The typed loops of `data`, keyed by id in file order.
static func loops_of(data: Variant) -> Dictionary:
	var found := {}
	if not data is Dictionary or not data.get("loops") is Array:
		return found
	for raw: Variant in data.loops:
		if not raw is Dictionary or not raw.get("id") is String or not raw.get("segments") is Array:
			continue
		var loop := Loop.new()
		loop.id = raw.id
		loop.rel = int(raw.get("rel", 0))
		for id: Variant in raw.segments:
			loop.segments.append(str(id))
		found[loop.id] = loop
	return found


## The length of a loop [m]: its segments' lengths summed, from `segments`
## (segments_of()'s dictionary); a segment that is not there adds nothing
## (validate() names it).
static func loop_length(loop: Loop, segments: Dictionary) -> float:
	var total := 0.0
	for id: String in loop.segments:
		if segments.has(id):
			total += segments[id].length()
	return total


## Whether a loop's segments chain and close: each shares an endpoint with
## the one before within JOIN_TOLERANCE_M, and the last comes back to where
## the first started. Empty if so, else what broke, for validate().
static func loop_fault(loop: Loop, segments: Dictionary) -> String:
	if loop.segments.size() < 2:
		return "%s has %d segment(s), a loop chains at least two" % [loop.id, loop.segments.size()]
	for id: String in loop.segments:
		if not segments.has(id):
			return "%s names segment %s, which is not there" % [loop.id, id]
	var first: Segment = segments[loop.segments[0]]
	var second: Segment = segments[loop.segments[1]]
	var start: Vector2
	var cursor: Vector2
	if _joins(first.last(), second):
		start = first.first()
		cursor = first.last()
	elif _joins(first.first(), second):
		start = first.last()
		cursor = first.first()
	else:
		return "%s: %s and %s share no endpoint within %s m" % [loop.id, first.id, second.id, JOIN_TOLERANCE_M]
	for i: int in range(1, loop.segments.size()):
		var next: Segment = segments[loop.segments[i]]
		if cursor.distance_to(next.first()) <= JOIN_TOLERANCE_M:
			cursor = next.last()
		elif cursor.distance_to(next.last()) <= JOIN_TOLERANCE_M:
			cursor = next.first()
		else:
			return "%s: %s does not join %s within %s m" % [loop.id, next.id, loop.segments[i - 1], JOIN_TOLERANCE_M]
	if cursor.distance_to(start) > JOIN_TOLERANCE_M:
		return "%s does not close: its last point is %.3f m from its first" % [loop.id, cursor.distance_to(start)]
	return ""


## WGS84 (lat, lon) [deg] -> region (x, z) [m]: the pipeline's projection
## (data-pipeline.md §3) done here. Not rounded: the file's points are
## millimetre-rounded by the pipeline; a caller compares within a tolerance.
static func wgs84_to_local(lat_deg: float, lon_deg: float) -> Vector2:
	var f := 1.0 / GRS80_INVERSE_FLATTENING
	var n := f / (2.0 - f)
	var n2 := n * n
	var n3 := n2 * n
	var n4 := n3 * n
	var n5 := n4 * n
	var n6 := n5 * n
	var rectifying_radius := GRS80_A / (1.0 + n) * (1.0 + n2 / 4.0 + n4 / 64.0 + n6 / 256.0)
	var alpha := [
		n / 2.0 - 2.0 * n2 / 3.0 + 5.0 * n3 / 16.0 + 41.0 * n4 / 180.0 - 127.0 * n5 / 288.0 + 7891.0 * n6 / 37800.0,
		13.0 * n2 / 48.0 - 3.0 * n3 / 5.0 + 557.0 * n4 / 1440.0 + 281.0 * n5 / 630.0 - 1983433.0 * n6 / 1935360.0,
		61.0 * n3 / 240.0 - 103.0 * n4 / 140.0 + 15061.0 * n5 / 26880.0 + 167603.0 * n6 / 181440.0,
		49561.0 * n4 / 161280.0 - 179.0 * n5 / 168.0 + 6601661.0 * n6 / 7257600.0,
		34729.0 * n5 / 80640.0 - 3418889.0 * n6 / 1995840.0,
		212378941.0 * n6 / 319334400.0,
	]
	var e := sqrt(f * (2.0 - f))
	var phi := deg_to_rad(lat_deg)
	var lam := deg_to_rad(lon_deg - UTM32_LON0_DEG)
	var tau := tan(phi)
	var sigma := _sinh(e * _atanh(e * tau / sqrt(1.0 + tau * tau)))
	var tau_prime := tau * sqrt(1.0 + sigma * sigma) - sigma * sqrt(1.0 + tau * tau)
	var xi_prime := atan2(tau_prime, cos(lam))
	var eta_prime := _asinh(sin(lam) / sqrt(tau_prime * tau_prime + cos(lam) * cos(lam)))
	var xi := xi_prime
	var eta := eta_prime
	for j: int in range(1, 7):
		xi += alpha[j - 1] * sin(2.0 * j * xi_prime) * _cosh(2.0 * j * eta_prime)
		eta += alpha[j - 1] * cos(2.0 * j * xi_prime) * _sinh(2.0 * j * eta_prime)
	var easting := UTM_FALSE_EASTING + UTM_K0 * rectifying_radius * eta
	var northing := UTM_FALSE_NORTHING + UTM_K0 * rectifying_radius * xi
	return Vector2(easting - E0, -(northing - N0))


## Everything that is wrong with `data` (what read_file() returns), one
## line each; empty if it is a valid skeleton of the pinned snapshot. The
## schema first, then every segment on its own, then the junctions against
## the segments (each junction at the end of every segment it lists, every
## segment end that sits on a junction listed there), then the loops.
static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary:
		errors.append("not a JSON object (a file that is not there, or not JSON)")
		return errors
	for key: String in TOP_KEYS:
		if not data.has(key):
			errors.append("%s is missing" % key)
	for key: String in data:
		if not key in TOP_KEYS:
			errors.append("%s is not in the schema" % key)
	_check_snapshot(errors, data.get("snapshot"))
	_check_origin(errors, data.get("origin"))
	var segments := segments_of(data)
	_check_segments(errors, data.get("segments"), segments)
	_check_junctions(errors, data.get("junctions"), segments)
	_check_loops(errors, data.get("loops"), segments)
	return errors


## The skeleton's file, parsed once; empty when it is not there or not JSON.
static func _file() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = read_file()
		if parsed is Dictionary:
			_data = parsed
	return _data


static func _typed_segments() -> Dictionary:
	if _segments.is_empty():
		_segments = segments_of(_file())
	return _segments


static func _typed_junctions() -> Dictionary:
	if _junctions.is_empty():
		_junctions = junctions_of(_file())
	return _junctions


static func _typed_loops() -> Dictionary:
	if _loops.is_empty():
		_loops = loops_of(_file())
	return _loops


## The snapshot block: the pinned osm_base, the Ring bbox, a sha256.
static func _check_snapshot(errors: PackedStringArray, snapshot: Variant) -> void:
	if not snapshot is Dictionary:
		errors.append("snapshot is not an object")
		return
	for key: String in SNAPSHOT_KEYS:
		if not snapshot.has(key):
			errors.append("snapshot.%s is missing" % key)
	for key: String in snapshot:
		if not key in SNAPSHOT_KEYS:
			errors.append("snapshot.%s is not in the schema" % key)
	if snapshot.has("osm_base") and snapshot.osm_base != PINNED_OSM_BASE:
		errors.append("snapshot.osm_base is %s, the pinned snapshot is %s (a re-pin is a documented decision)" % [snapshot.osm_base, PINNED_OSM_BASE])
	if snapshot.has("bbox") and not _same_numbers(snapshot.bbox, BBOX):
		errors.append("snapshot.bbox is %s, the Ring's is %s" % [snapshot.bbox, BBOX])
	if snapshot.has("query_sha") and not (snapshot.query_sha is String and RegEx.create_from_string(QUERY_SHA_PATTERN).search(snapshot.query_sha) != null):
		errors.append("snapshot.query_sha is %s, not a sha256 hex" % snapshot.get("query_sha"))


## The origin block: the region frame put in stone.
static func _check_origin(errors: PackedStringArray, origin: Variant) -> void:
	if not origin is Dictionary:
		errors.append("origin is not an object")
		return
	for key: String in ORIGIN_KEYS:
		if not origin.has(key):
			errors.append("origin.%s is missing" % key)
	for key: String in origin:
		if not key in ORIGIN_KEYS:
			errors.append("origin.%s is not in the schema" % key)
	var expected := {"epsg": EPSG, "e0": E0, "n0": N0}
	for key: String in expected:
		if origin.has(key) and not (_is_number(origin[key]) and origin[key] == expected[key]):
			errors.append("origin.%s is %s, the Ring's is %s" % [key, origin[key], expected[key]])


## Every segment: an id of the form, unique, in sorted order; osm_way the
## id's way; a class of the table; width by the rules; carried tags as
## strings; at least two finite points; nothing outside the schema.
static func _check_segments(errors: PackedStringArray, raw: Variant, segments: Dictionary) -> void:
	if not raw is Array:
		errors.append("segments is not a list")
		return
	var seen := {}
	var previous := ""
	for i: int in raw.size():
		var element: Variant = raw[i]
		if not element is Dictionary or not element.get("id") is String:
			errors.append("segments[%d] is not a segment with an id" % i)
			continue
		var id: String = element.id
		if seen.has(id):
			errors.append("segment %s is there twice, ids are unique" % id)
		seen[id] = true
		if not is_segment_id(id):
			errors.append("segment %s is not an id of the form way-index" % id)
		elif id < previous:
			errors.append("segment %s comes after %s, segments are sorted by id" % [id, previous])
		previous = id
		for key: String in SEGMENT_REQUIRED_KEYS:
			if not element.has(key):
				errors.append("segment %s.%s is missing" % [id, key])
		for key: String in element:
			if not key in SEGMENT_REQUIRED_KEYS and not key in CARRIED_TAGS:
				errors.append("segment %s.%s is not in the schema" % [id, key])
			elif key in CARRIED_TAGS and not element[key] is String:
				errors.append("segment %s.%s is %s, carried tags are strings" % [id, key, element[key]])
		if element.has("osm_way") and not (_is_whole(element.osm_way) and element.osm_way > 0 and (not is_segment_id(id) or str(int(element.osm_way)) == id.split("-")[0])):
			errors.append("segment %s.osm_way is %s, not the id's way" % [id, element.osm_way])
		var road_class: Variant = element.get("class")
		if element.has("class") and class_width(str(road_class)) < 0.0:
			errors.append("segment %s.class is %s, not a class of the width table" % [id, road_class])
		_check_width(errors, id, element)
		var points: Variant = element.get("points")
		if element.has("points"):
			if not points is Array or points.size() < 2:
				errors.append("segment %s.points has %s, a segment has at least two" % [id, points.size() if points is Array else points])
			else:
				for j: int in points.size():
					var point: Variant = points[j]
					if not (point is Array and point.size() == 2 and _is_number(point[0]) and _is_number(point[1])):
						errors.append("segment %s.points[%d] is %s, not a finite [x, z]" % [id, j, point])
						break
	if segments.size() != seen.size():
		errors.append("%d segments typed of %d with an id" % [segments.size(), seen.size()])


## A segment's width: by class it is the table's (or the Karussell's); by
## tag it is inside the band and the class takes tags.
static func _check_width(errors: PackedStringArray, id: String, element: Dictionary) -> void:
	if not element.has("width_m") or not element.has("width_source") or not element.has("class") or not element.has("osm_way"):
		return
	var width: Variant = element.width_m
	var source: Variant = element.width_source
	var road_class := str(element["class"])
	if not _is_number(width) or width <= 0.0:
		errors.append("segment %s.width_m is %s, not a positive width" % [id, width])
		return
	if not source in WIDTH_SOURCES:
		errors.append("segment %s.width_source is %s, not one of %s" % [id, source, WIDTH_SOURCES])
		return
	if class_width(road_class) < 0.0 or not _is_whole(element.osm_way):
		return
	if source == "class":
		var expected := width_by_class(int(element.osm_way), road_class)
		if width != expected:
			errors.append("segment %s.width_m is %s by class, %s's is %s" % [id, width, road_class, expected])
	elif not tag_width_plausible(road_class, width):
		errors.append("segment %s.width_m is %s by tag, outside %s's band [%s, %s]" % [id, width, road_class, TAG_WIDTH_BAND[0] * class_width(road_class), TAG_WIDTH_BAND[1] * class_width(road_class)])


## Every junction: an id of the form, unique, sorted; finite x, z; at least
## two segments, each there once and ending at the junction; and every
## segment end that sits on a junction's position is listed by it.
static func _check_junctions(errors: PackedStringArray, raw: Variant, segments: Dictionary) -> void:
	if not raw is Array:
		errors.append("junctions is not a list")
		return
	var at := {}
	var seen := {}
	var previous := ""
	for i: int in raw.size():
		var element: Variant = raw[i]
		if not element is Dictionary or not element.get("id") is String:
			errors.append("junctions[%d] is not a junction with an id" % i)
			continue
		var id: String = element.id
		if seen.has(id):
			errors.append("junction %s is there twice, ids are unique" % id)
		seen[id] = true
		if not is_junction_id(id):
			errors.append("junction %s is not an id of the form node id" % id)
		elif id < previous:
			errors.append("junction %s comes after %s, junctions are sorted by id" % [id, previous])
		previous = id
		for key: String in JUNCTION_KEYS:
			if not element.has(key):
				errors.append("junction %s.%s is missing" % [id, key])
		for key: String in element:
			if not key in JUNCTION_KEYS:
				errors.append("junction %s.%s is not in the schema" % [id, key])
		if not (_is_number(element.get("x")) and _is_number(element.get("z"))):
			errors.append("junction %s is at (%s, %s), not finite" % [id, element.get("x"), element.get("z")])
			continue
		var position := Vector2(element.x, element.z)
		var listed: Variant = element.get("segments")
		at[_key_of(position)] = {"id": id, "segments": listed if listed is Array else []}
		if not listed is Array or listed.size() < 2:
			errors.append("junction %s has %s segment(s), a junction joins at least two" % [id, listed.size() if listed is Array else listed])
			continue
		var own := {}
		for sid: Variant in listed:
			if own.has(sid):
				errors.append("junction %s lists %s twice" % [id, sid])
			own[sid] = true
			if not segments.has(sid):
				errors.append("junction %s lists segment %s, which is not there" % [id, sid])
			elif not _joins(position, segments[sid]):
				errors.append("junction %s lists segment %s, which does not end within %s m of it" % [id, sid, JOIN_TOLERANCE_M])
	for segment: Segment in segments.values():
		for endpoint: Vector2 in [segment.first(), segment.last()]:
			var there: Variant = at.get(_key_of(endpoint))
			if there != null and not segment.id in there.segments:
				errors.append("segment %s ends on junction %s, which does not list it" % [segment.id, there.id])


## Every loop: an id, a relation id, and a chain that closes.
static func _check_loops(errors: PackedStringArray, raw: Variant, segments: Dictionary) -> void:
	if not raw is Array:
		errors.append("loops is not a list")
		return
	var seen := {}
	for i: int in raw.size():
		var element: Variant = raw[i]
		if not element is Dictionary or not element.get("id") is String or element.id == "":
			errors.append("loops[%d] is not a loop with an id" % i)
			continue
		var id: String = element.id
		if seen.has(id):
			errors.append("loop %s is there twice, ids are unique" % id)
		seen[id] = true
		for key: String in LOOP_KEYS:
			if not element.has(key):
				errors.append("loop %s.%s is missing" % [id, key])
		for key: String in element:
			if not key in LOOP_KEYS:
				errors.append("loop %s.%s is not in the schema" % [id, key])
		if element.has("rel") and not (_is_whole(element.rel) and element.rel > 0):
			errors.append("loop %s.rel is %s, not a relation id" % [id, element.rel])
		if not element.get("segments") is Array:
			errors.append("loop %s.segments is not a list" % id)
			continue
		var loops := loops_of({"loops": [element]})
		var fault := loop_fault(loops[id], segments)
		if fault != "":
			errors.append("loop " + fault)


## Whether `point` is within JOIN_TOLERANCE_M of either end of `segment`.
static func _joins(point: Vector2, segment: Segment) -> bool:
	return point.distance_to(segment.first()) <= JOIN_TOLERANCE_M or point.distance_to(segment.last()) <= JOIN_TOLERANCE_M


## A millimetre-rounded position as a dictionary key: the file's own
## rounding, so a junction and the segment ends it joins share the key.
static func _key_of(position: Vector2) -> String:
	return "%.3f,%.3f" % [position.x, position.y]


static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value)


static func _is_whole(value: Variant) -> bool:
	return _is_number(value) and value == floorf(value)


## Whether two lists hold the same numbers in the same order.
static func _same_numbers(a: Variant, b: Array) -> bool:
	if not a is Array or a.size() != b.size():
		return false
	for i: int in b.size():
		if not _is_number(a[i]) or a[i] != b[i]:
			return false
	return true


static func _sinh(x: float) -> float:
	return (exp(x) - exp(-x)) / 2.0


static func _cosh(x: float) -> float:
	return (exp(x) + exp(-x)) / 2.0


static func _asinh(x: float) -> float:
	return log(x + sqrt(x * x + 1.0))


static func _atanh(x: float) -> float:
	return 0.5 * log((1.0 + x) / (1.0 - x))
