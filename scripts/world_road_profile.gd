class_name WorldRoadProfile
extends RoadProfile
## The Ring's road as a height field: a RoadProfile backed by the draped
## skeleton (docs/design/4b/data-pipeline.md §5, implementation-plan.md
## §2.2). data/regions/eifel_ring/drape.json, written offline by
## tools/world/drape.py from the DGM1 tiles and skeleton.json, carries per
## covered segment the platform's centre height at 2 m stations, a crossfall
## per skeleton point and the crest/dip/bank labels; and a terrain lattice
## of the raw DEM over the 42-tile core. This class reads both files into
## typed roads and answers the four calls the car and the pad make of a
## profile with the world instead of the pad:
##   * sample_height(x, z): on a road, the platform: the centre height along
##     the nearest segment plus the crossfall across it (a 2 % crown on a
##     straight, superelevation into a bend, the Karussell's bank); within
##     BLEND_BAND_M outside the paved edge, the platform's edge eased into
##     the terrain (smoothstep); off the road, the terrain lattice, bilinear.
##   * ramp_gradient(x, z): the surface gradient of that height field by
##     central differences over GRADIENT_SPAN_M (the shape of
##     RoadProfile.elevation_slope): what gravity pulls the car down.
##   * elevation_height / elevation_mask: the same field and 1 inside the
##     drape's coverage, so anything drawn from the profile draws the world.
## The field is single-valued: where two roads cross at different layers
## (a bridge over a road) the nearest centreline's height is answered and
## the field steps at the crossing; the assembler (4B-4) builds a deck as
## its own mesh and the car on it reads that. A known limit, held by the
## suite's slope check on the loop's own roads.
## OUTSIDE THE COVERAGE (the core is E 352-359 km × N 5577-5583 km; the
## skeleton spans the whole bbox) the profile is flat: height 0, gradient
## Vector2.ZERO, mask 0 (implementation-plan.md §2.4). The pad's own layers
## (micro-bumps, the test dip, the licence ramp, the swells) are zeroed at
## construction: the world carries none of them.
##
## Pure, as RoadProfile's header rules: same (x, z), same height, every
## run; nothing in the sampling path draws randoms or keeps mutable state.
## The one index there is (a cell grid over the covered chords, CELL_M) is
## built once in from_data(), never lazily: 3 314 covered segments, ~18 000
## chords, about 100 000 cell entries, tens of milliseconds.
##
## chosen for the drape: the file is read by static functions in this
## class (read_file(), validate(), the *_of() typed readers, the mirrored
## rules), the shape of SkeletonLoader, and an instance is built from parsed
## dictionaries by from_data() so a test can hand it a synthetic fixture
## without a file; ring() builds the Ring's. One new file, as
## implementation-plan.md §4B-3 lists, rather than a loader and a profile.
## The drape's rules (the stations, the bridge and tunnel heights, the
## crossfall, the labels) are mirrored here from drape.py, operation for
## operation on 64-bit floats, so the suite can prove them on a fixture
## without python and hold the checked-in file's labels to a recount.

## Where the Ring's drape is; the skeleton is SkeletonLoader.PATH.
const PATH := "res://data/regions/eifel_ring/drape.json"

## The drape pipeline's version this profile reads (drape.py's
## PIPELINE_VERSION); another version's file is refused.
const DRAPE_PIPELINE_VERSION := 1

## The pinned snapshot and frame, as SkeletonLoader holds them.
const PINNED_OSM_BASE := SkeletonLoader.PINNED_OSM_BASE

# --- the rules, mirrored from tools/world/drape.py (the file carries them
# in `rules`; validate() refuses a file whose rules are not these) --------

## Stations along a segment [m]: where the centre height is carried.
const STATION_STEP_M := 2.0

## Crossfall: the crown on a straight [rise over run] and how the
## superelevation is drawn from a bend's radius (e = GAIN / R, capped).
const CROWN := 0.02
const SUPERELEVATION_GAIN_M := 8.0  # [m]
const SUPERELEVATION_MAX := 0.04  # R2: ≤ 4 % on public roads
const HAIRPIN_RADIUS_M := 30.0  # [m] R3: a hairpin's radius ...
const HAIRPIN_SUPERELEVATION_MAX := 0.06  # ... and its 6 % cap

## Crest/dip labels: the 20 m second difference beyond this is a crest
## (convex, negative) or a dip [1/m]; the windows in stations.
const CREST_CURVATURE := 0.004
## A label's curvature is rounded to 1e-5 in the file: one beyond the
## threshold by less than half a step rounds onto it (validate allows that).
const CURVATURE_HALF_STEP := 0.5e-5
const WINDOW_20_STATIONS := 5
const WINDOW_40_STATIONS := 10

## Tunnels: |layer| × this below the DEM [m], ramped in over this from a portal [m].
const TUNNEL_DEPTH_PER_LAYER_M := 6.0
const TUNNEL_RAMP_M := 30.0

## The blend band outside the paved edge [m] (§5; the pad's
## LANE_BAND_HALF_WIDTH is the same idea).
const BLEND_BAND_M := 6.0

## The Karussell's bank (ring-region-decisions.md §3, branch (c)): way
## 414785755 takes the R9 element's numbers in drape.py; mirrored for the
## fixture path.
const KARUSSELL_WAY := SkeletonLoader.KARUSSELL_WAY
const KARUSSELL_BANK := 0.30
const KARUSSELL_BOWL_M := 6.5  # [m]
const KARUSSELL_STRIP_M := 1.0  # [m]

## The file's rounding: heights to the centimetre, crossfall to 1e-4,
## curvature to 1e-5, chainage to the millimetre (drape.py, chosen there).
const HEIGHT_DECIMALS := 2
const CROSSFALL_DECIMALS := 4
const CURVATURE_DECIMALS := 5
const CHAINAGE_DECIMALS := 3

# --- the sampler ----------------------------------------------------------------

## Central-difference span of ramp_gradient [m] (implementation-plan.md §2.2).
const GRADIENT_SPAN_M := 1.0

## The cell grid over the covered chords [m]: a chord is filed under every
## cell its box, grown by its own road's reach (the paved half width plus
## the blend band: a road with a tagged width up to twice its class's
## reaches further than the raceway's 4.25 + 6 m), overlaps; a sample looks
## in its own cell only and a chord counts only within its road's reach.
## was one fixed reach of 10.25 m for every road -> each road's own (the
## codex review of 4B-3: a wider road's band was cut off at 10.25 m while
## its platform still contributed, a step in the field).
const CELL_M := 20.0

## Chord entries are packed as road index × CHORD_STRIDE + chord index.
const CHORD_STRIDE := 65536

# --- the schema ---------------------------------------------------------------

const TOP_KEYS := ["snapshot", "origin", "dem", "coverage", "rules", "lattice", "segments"]
const SNAPSHOT_KEYS := ["osm_base", "bbox", "query_sha", "skeleton_pipeline_version", "skeleton_sha256", "pipeline_version"]
const DEM_KEYS := ["source", "epsg", "vertical_datum", "grid_m", "tiles"]
const TILE_KEYS := ["name", "sha256", "verified"]
const COVERAGE_KEYS := ["x_min", "x_max", "z_min", "z_max"]
const LATTICE_KEYS := ["step_m", "x0", "z0", "cols", "rows", "heights"]
const SEGMENT_KEYS := ["id", "covered", "heights", "dense", "crossfall", "labels"]
const LABEL_KINDS := ["crest", "dip", "bank"]
const GEOMETRY_LABEL_KEYS := ["at", "kind", "curvature_20m", "curvature_40m"]
const BANK_LABEL_KEYS := ["at", "kind", "to", "bank", "bowl_m", "strip_m"]
const RULES := {
	"station_step_m": STATION_STEP_M, "crown": CROWN,
	"superelevation_gain_m": SUPERELEVATION_GAIN_M, "superelevation_max": SUPERELEVATION_MAX,
	"hairpin_radius_m": HAIRPIN_RADIUS_M, "hairpin_superelevation_max": HAIRPIN_SUPERELEVATION_MAX,
	"crest_curvature": CREST_CURVATURE,
	"tunnel_depth_per_layer_m": TUNNEL_DEPTH_PER_LAYER_M, "tunnel_ramp_m": TUNNEL_RAMP_M,
	"blend_band_m": BLEND_BAND_M,
}
const TILE_NAME_PATTERN := "^(dgm1|dom1)_32_[0-9]{3}_[0-9]{4}_1_rp_[0-9]{4}\\.tif$"
const SHA256_PATTERN := "^[0-9a-f]{64}$"
const DEM_EPSG := 25832
const DEM_VERTICAL_DATUM := "DHHN2016"
const DEM_GRID_M := 1.0


## One covered segment as the sampler holds it: the centreline in 64-bit
## floats (the chainage has to come out to the bit the pipeline's did), the
## dense centre heights, the crossfall per point, and the bank if any.
class Road:
	extends RefCounted
	var id: String
	var xs: PackedFloat64Array
	var zs: PackedFloat64Array
	## Chainage at every point [m].
	var chain: PackedFloat64Array
	var length: float
	var half_width: float
	## The centre height at the stations (STATION_STEP_M, then the end).
	var dense: PackedFloat64Array
	var crossfall: PackedFloat64Array
	var bank: bool = false
	var bank_to: float = 0.0
	var bank_slope: float = 0.0
	var bank_strip: float = 0.0

	## How far from the centreline the road has a say [m]: the paved half
	## width plus the blend band.
	func reach() -> float:
		return half_width + BLEND_BAND_M


## The drape's coverage box in game metres; flat outside it.
var _x_min := 0.0
var _x_max := 0.0
var _z_min := 0.0
var _z_max := 0.0

## The terrain lattice: row-major from (x0, z0), rows along +z.
var _lattice: PackedFloat64Array
var _lattice_step := 0.0
var _lattice_x0 := 0.0
var _lattice_z0 := 0.0
var _lattice_cols := 0
var _lattice_rows := 0

## The covered roads and the cell grid over their chords: cell -> Array of
## packed chord entries (an Array, not a packed one: a packed array read
## out of a Dictionary is a copy, appends to it would be lost).
var _roads: Array[Road] = []
var _cells: Dictionary = {}


# =============================================================================
#  THE FILE
# =============================================================================

## What JSON.parse_string makes of the file at `path`: null where it is
## missing or is not JSON. What validate() and from_data() take.
static func read_file(path: String = PATH) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## The Ring's profile: the checked-in skeleton and drape. Null when either
## file is missing or not JSON (the caller decides; the suite asserts).
static func ring() -> WorldRoadProfile:
	var skeleton: Variant = SkeletonLoader.read_file()
	var drape: Variant = read_file()
	if not skeleton is Dictionary or not drape is Dictionary:
		return null
	return from_data(skeleton, drape)


## A profile from parsed dictionaries: the skeleton's segments give the
## geometry and widths, the drape the heights. Only covered drape segments
## whose skeleton segment exists become roads; the rest of the skeleton is
## not a road for the profile (terrain, or flat outside coverage). The pad's
## layers are zeroed here. The index is built here, once.
static func from_data(skeleton_data: Dictionary, drape_data: Dictionary) -> WorldRoadProfile:
	var profile := WorldRoadProfile.new()
	profile.micro_amplitude = 0.0
	profile.swell_amplitude = 0.0
	profile.second_swell_amplitude = 0.0
	profile.test_dip_depth = 0.0
	profile.ramp_height = 0.0
	var coverage: Dictionary = drape_data.get("coverage", {})
	profile._x_min = float(coverage.get("x_min", 0.0))
	profile._x_max = float(coverage.get("x_max", 0.0))
	profile._z_min = float(coverage.get("z_min", 0.0))
	profile._z_max = float(coverage.get("z_max", 0.0))
	var lattice: Dictionary = drape_data.get("lattice", {})
	profile._lattice_step = float(lattice.get("step_m", 0.0))
	profile._lattice_x0 = float(lattice.get("x0", 0.0))
	profile._lattice_z0 = float(lattice.get("z0", 0.0))
	profile._lattice_cols = int(lattice.get("cols", 0))
	profile._lattice_rows = int(lattice.get("rows", 0))
	profile._lattice = PackedFloat64Array()
	if lattice.get("heights") is Array:
		profile._lattice.resize(lattice.heights.size())
		for i: int in lattice.heights.size():
			profile._lattice[i] = float(lattice.heights[i]) if _is_number(lattice.heights[i]) else NAN
	var segments := SkeletonLoader.segments_of(skeleton_data)
	var raw_points := _raw_points_of(skeleton_data)
	for raw: Variant in drape_data.get("segments", []):
		if not raw is Dictionary or not raw.get("covered", false) or not segments.has(raw.get("id")):
			continue
		var road := _road_of(raw, segments[raw.id], raw_points[raw.id])
		if road != null:
			profile._roads.append(road)
	profile._build_cells()
	return profile


## The skeleton's points as 64-bit pairs, by segment id (SkeletonLoader's
## PackedVector2Array is single precision; the chainage needs the file's
## own numbers).
static func _raw_points_of(skeleton_data: Dictionary) -> Dictionary:
	var found := {}
	for raw: Variant in skeleton_data.get("segments", []):
		if raw is Dictionary and raw.get("id") is String and raw.get("points") is Array:
			found[raw.id] = raw.points
	return found


static func _road_of(raw: Dictionary, segment: SkeletonLoader.Segment, points: Array) -> Road:
	var road := Road.new()
	road.id = segment.id
	road.xs = PackedFloat64Array()
	road.zs = PackedFloat64Array()
	for point: Variant in points:
		road.xs.append(float(point[0]))
		road.zs.append(float(point[1]))
	road.chain = chainages(road.xs, road.zs)
	road.length = road.chain[road.chain.size() - 1]
	road.half_width = segment.width_m * 0.5
	road.dense = PackedFloat64Array()
	for h: Variant in raw.get("dense", []):
		if not _is_number(h):
			return null
		road.dense.append(float(h))
	if road.dense.size() != station_chainages(road.length).size():
		return null
	road.crossfall = PackedFloat64Array()
	for e: Variant in raw.get("crossfall", []):
		road.crossfall.append(float(e) if _is_number(e) else 0.0)
	if road.crossfall.size() != road.xs.size():
		return null
	for label: Variant in raw.get("labels", []):
		if label is Dictionary and label.get("kind") == "bank":
			road.bank = true
			road.bank_to = float(label.get("to", road.length))
			road.bank_slope = float(label.get("bank", 0.0))
			road.bank_strip = float(label.get("strip_m", 0.0))
	return road


## Files every chord of every road under the cells its box, grown by the
## road's own reach, overlaps.
func _build_cells() -> void:
	_cells = {}
	for r: int in _roads.size():
		var road := _roads[r]
		var reach := road.reach()
		for c: int in range(road.xs.size() - 1):
			var x_lo := minf(road.xs[c], road.xs[c + 1]) - reach
			var x_hi := maxf(road.xs[c], road.xs[c + 1]) + reach
			var z_lo := minf(road.zs[c], road.zs[c + 1]) - reach
			var z_hi := maxf(road.zs[c], road.zs[c + 1]) + reach
			var packed := r * CHORD_STRIDE + c
			for i: int in range(floori(z_lo / CELL_M), floori(z_hi / CELL_M) + 1):
				for j: int in range(floori(x_lo / CELL_M), floori(x_hi / CELL_M) + 1):
					var key := Vector2i(j, i)
					if not _cells.has(key):
						_cells[key] = []
					_cells[key].append(packed)


# =============================================================================
#  THE PROFILE
# =============================================================================

## Height of the road at (x, z) [m]: the world's height field alone (the
## pad's layers are zero here).
func sample_height(x: float, z: float) -> float:
	return elevation_height(x, z)


## The height field: the platform on a road, the blend band beside it, the
## terrain lattice elsewhere inside the coverage; exactly 0 outside.
func elevation_height(x: float, z: float) -> float:
	if not covers(x, z):
		return 0.0
	var found := _nearest_chord(x, z)
	if found.is_empty():
		return terrain_height(x, z)
	var road: Road = _roads[found.road]
	var distance: float = found.distance
	if distance <= road.half_width:
		return _platform_height(road, found.chainage, found.offset)
	var edge := _platform_height(road, found.chainage, signf(found.offset) * road.half_width)
	var eased := smoothstep(0.0, 1.0, (distance - road.half_width) / BLEND_BAND_M)
	return lerpf(edge, terrain_height(x, z), eased)


## 1 inside the drape's coverage, 0 outside: the world is drawn where it is.
func elevation_mask(x: float, z: float) -> float:
	return 1.0 if covers(x, z) else 0.0


## The surface gradient of the height field at (x, z): rise per metre along
## x and along z, by central differences over GRADIENT_SPAN_M. Exactly
## Vector2.ZERO where any tap is outside the coverage (flat there, no cliff
## at the edge).
func ramp_gradient(x: float, z: float) -> Vector2:
	var span := GRADIENT_SPAN_M
	if not (covers(x - span, z) and covers(x + span, z) and covers(x, z - span) and covers(x, z + span)):
		return Vector2.ZERO
	var slope_x := (elevation_height(x + span, z) - elevation_height(x - span, z)) / (2.0 * span)
	var slope_z := (elevation_height(x, z + span) - elevation_height(x, z - span)) / (2.0 * span)
	return Vector2(slope_x, slope_z)


## Whether (x, z) is inside the drape's coverage box.
func covers(x: float, z: float) -> bool:
	return x >= _x_min and x <= _x_max and z >= _z_min and z <= _z_max


## The terrain lattice's height at (x, z) [m], bilinear between its nodes;
## 0 outside the lattice.
func terrain_height(x: float, z: float) -> float:
	if _lattice_cols < 2 or _lattice_rows < 2 or _lattice_step <= 0.0:
		return 0.0
	var fx := (x - _lattice_x0) / _lattice_step
	var fz := (z - _lattice_z0) / _lattice_step
	if fx < 0.0 or fz < 0.0 or fx > _lattice_cols - 1 or fz > _lattice_rows - 1:
		return 0.0
	var j0 := mini(floori(fx), _lattice_cols - 2)
	var i0 := mini(floori(fz), _lattice_rows - 2)
	var tx := fx - j0
	var tz := fz - i0
	var top := lerpf(_lattice[i0 * _lattice_cols + j0], _lattice[i0 * _lattice_cols + j0 + 1], tx)
	var bottom := lerpf(_lattice[(i0 + 1) * _lattice_cols + j0], _lattice[(i0 + 1) * _lattice_cols + j0 + 1], tx)
	return lerpf(top, bottom, tz)


## The coverage box [x_min, z_min, x_max, z_max] in game metres.
func coverage() -> Rect2:
	return Rect2(_x_min, _z_min, _x_max - _x_min, _z_max - _z_min)


## How many covered roads the profile holds.
func road_count() -> int:
	return _roads.size()


## What the profile sees at (x, z), for tests and tools: whether it is
## covered, the nearest road (id, chainage [m], signed offset to the right
## of travel [m], distance to the centreline [m]) when one is within reach,
## the centre height there, the terrain and the height returned.
func describe(x: float, z: float) -> Dictionary:
	var out := {"covered": covers(x, z), "height": elevation_height(x, z), "terrain": terrain_height(x, z), "road": ""}
	if not out.covered:
		return out
	var found := _nearest_chord(x, z)
	if found.is_empty():
		return out
	var road: Road = _roads[found.road]
	out.road = road.id
	out.chainage = found.chainage
	out.offset = found.offset
	out.distance = found.distance
	out.centre = centre_height(road, found.chainage)
	out.on_road = found.distance <= road.half_width
	return out


## The point at `chainage` along the road with this id, or null.
func point_along(id: String, chainage: float) -> Variant:
	for road: Road in _roads:
		if road.id == id:
			return _point_at(road, chainage)
	return null


## The platform's centre height at a chainage [m]: the dense stations,
## linear between them.
func centre_height(road: Road, chainage: float) -> float:
	var s := clampf(chainage, 0.0, road.length)
	var whole := floori(road.length / STATION_STEP_M + 1e-9)
	var k := mini(floori(s / STATION_STEP_M), whole)
	if k < whole:
		return lerpf(road.dense[k], road.dense[k + 1], (s - k * STATION_STEP_M) / STATION_STEP_M)
	# Past the last whole station: to the end sample, if there is one.
	if road.dense.size() > whole + 1:
		var rest := road.length - whole * STATION_STEP_M
		return lerpf(road.dense[whole], road.dense[whole + 1], (s - whole * STATION_STEP_M) / rest)
	return road.dense[whole]


## The crossfall at a chainage: the points' values, linear between them.
func crossfall_at(road: Road, chainage: float) -> float:
	var s := clampf(chainage, 0.0, road.length)
	for i: int in range(1, road.chain.size()):
		if road.chain[i] >= s:
			var span := road.chain[i] - road.chain[i - 1]
			var u := 0.0 if span <= 0.0 else (s - road.chain[i - 1]) / span
			return lerpf(road.crossfall[i - 1], road.crossfall[i], u)
	return road.crossfall[road.crossfall.size() - 1]


## The platform's height at a chainage and a signed offset to the right of
## travel [m] (clamped to the paved half width): the centre height plus the
## crossfall's shape (the crown fading into a plane as the superelevation
## grows), or the bank's bowl where the road has one.
func _platform_height(road: Road, chainage: float, offset: float) -> float:
	var o := clampf(offset, -road.half_width, road.half_width)
	var centre := centre_height(road, chainage)
	var e := crossfall_at(road, chainage)
	if road.bank and chainage <= road.bank_to:
		# u: distance from the low edge; flat over the strip, then the bank;
		# anchored so the centre sits at the DEM's centre height.
		var u := signf(e) * o + road.half_width
		var low := centre - road.bank_slope * maxf(road.half_width - road.bank_strip, 0.0)
		return low + road.bank_slope * maxf(u - road.bank_strip, 0.0)
	var crown_share := 1.0 - minf(absf(e) / CROWN, 1.0)
	return centre + e * o - crown_share * CROWN * absf(o)


## The nearest chord to (x, z) among those filed under its cell and within
## their own road's reach: the road index, the chord's chainage at the
## closest point, the signed offset to the right of travel and the
## distance. Empty when no road reaches the point.
func _nearest_chord(x: float, z: float) -> Dictionary:
	var key := Vector2i(floori(x / CELL_M), floori(z / CELL_M))
	if not _cells.has(key):
		return {}
	var best_distance := INF
	var best := {}
	for packed: int in _cells[key]:
		var r := packed / CHORD_STRIDE
		var c := packed % CHORD_STRIDE
		var road := _roads[r]
		var ax := road.xs[c]
		var az := road.zs[c]
		var dx := road.xs[c + 1] - ax
		var dz := road.zs[c + 1] - az
		var chord := road.chain[c + 1] - road.chain[c]
		if chord <= 0.0:
			continue
		var t := clampf(((x - ax) * dx + (z - az) * dz) / (chord * chord), 0.0, 1.0)
		var cx := ax + t * dx
		var cz := az + t * dz
		var distance := sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz))
		if distance <= road.reach() and distance < best_distance:
			best_distance = distance
			# Right of travel in the x-east / z-south frame: (-tz, tx).
			var offset := ((x - ax) * (-dz) + (z - az) * dx) / chord
			best = {"road": r, "chainage": road.chain[c] + t * chord, "offset": offset, "distance": distance}
	return best


func _point_at(road: Road, chainage: float) -> Vector2:
	var s := clampf(chainage, 0.0, road.length)
	for i: int in range(1, road.chain.size()):
		if road.chain[i] >= s:
			var span := road.chain[i] - road.chain[i - 1]
			var u := 0.0 if span <= 0.0 else (s - road.chain[i - 1]) / span
			return Vector2(road.xs[i - 1] + u * (road.xs[i] - road.xs[i - 1]), road.zs[i - 1] + u * (road.zs[i] - road.zs[i - 1]))
	return Vector2(road.xs[road.xs.size() - 1], road.zs[road.zs.size() - 1])


# =============================================================================
#  THE RULES (mirrored from drape.py; the fixture path and the recount)
# =============================================================================

## Chainage at every point [m]: chord lengths summed, sqrt(dx² + dz²) as
## the pipeline computes them.
static func chainages(xs: PackedFloat64Array, zs: PackedFloat64Array) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0])
	for i: int in range(1, xs.size()):
		var dx := xs[i] - xs[i - 1]
		var dz := zs[i] - zs[i - 1]
		out.append(out[i - 1] + sqrt(dx * dx + dz * dz))
	return out


## The stations along a segment of `length`: 0, step, ... up to the length,
## and the end itself when it is more than a millimetre past the last
## whole station (drape.py's station_chainages).
static func station_chainages(length: float, step: float = STATION_STEP_M) -> PackedFloat64Array:
	var whole := floori(length / step + 1e-9)
	var out := PackedFloat64Array()
	for k: int in range(whole + 1):
		out.append(k * step)
	if length - whole * step > 1e-3:
		out.append(length)
	return out


## Menger curvature of the circle through three points [1/m], negative for
## a left turn in the x-east / z-south frame, 0 when collinear.
static func signed_curvature(x0: float, z0: float, x1: float, z1: float, x2: float, z2: float) -> float:
	var ax := x1 - x0
	var az := z1 - z0
	var bx := x2 - x1
	var bz := z2 - z1
	var cross := ax * bz - az * bx
	var a := sqrt(ax * ax + az * az)
	var b := sqrt(bx * bx + bz * bz)
	var c := sqrt((x2 - x0) * (x2 - x0) + (z2 - z0) * (z2 - z0))
	if a == 0.0 or b == 0.0 or c == 0.0:
		return 0.0
	return 2.0 * cross / (a * b * c)


## The crossfall for a signed curvature: GAIN / R capped by the class of
## bend, rising to the outside (a left turn, curvature < 0, rises to the
## right: e > 0).
static func superelevation(curvature: float) -> float:
	if curvature == 0.0:
		return 0.0
	var radius := 1.0 / absf(curvature)
	var cap := HAIRPIN_SUPERELEVATION_MAX if radius < HAIRPIN_RADIUS_M else SUPERELEVATION_MAX
	var e := minf(SUPERELEVATION_GAIN_M / radius, cap)
	return e if curvature < 0.0 else -e


## The crossfall at every point: the three-point circle at each interior
## point, the ends their neighbour's, a two-point segment 0 (the crown).
static func crossfall_of(xs: PackedFloat64Array, zs: PackedFloat64Array) -> PackedFloat64Array:
	var n := xs.size()
	var out := PackedFloat64Array()
	out.resize(n)
	out.fill(0.0)
	if n < 3:
		return out
	for i: int in range(1, n - 1):
		out[i] = superelevation(signed_curvature(xs[i - 1], zs[i - 1], xs[i], zs[i], xs[i + 1], zs[i + 1]))
	out[0] = out[1]
	out[n - 1] = out[n - 2]
	return out


## How far below the DEM a tunnel's road sits at chainage s [m].
static func tunnel_depth(s: float, length: float, layer: int) -> float:
	var full := TUNNEL_DEPTH_PER_LAYER_M * maxi(absi(layer), 1)
	var ramp := minf(s, length - s) / TUNNEL_RAMP_M
	return full * clampf(ramp, 0.0, 1.0)


## Crest/dip labels from the dense centre heights (drape.py's labels_of,
## the same operations on the same rounded numbers): one label per run of
## stations beyond the threshold, at the run's steepest station. `dense`
## may hold NAN for a station without a height (no window there).
static func labels_of(dense: PackedFloat64Array, length: float, step: float = STATION_STEP_M) -> Array[Dictionary]:
	var whole := floori(length / step + 1e-9)
	var count := whole + 1
	var labels: Array[Dictionary] = []
	var run_kind := ""
	var run_best := {}
	for k: int in count:
		var kind := ""
		var k20 := NAN
		var k40 := NAN
		if k >= WINDOW_20_STATIONS and k + WINDOW_20_STATIONS < count and not (is_nan(dense[k - WINDOW_20_STATIONS]) or is_nan(dense[k]) or is_nan(dense[k + WINDOW_20_STATIONS])):
			var half := WINDOW_20_STATIONS * step
			k20 = (dense[k + WINDOW_20_STATIONS] - 2.0 * dense[k] + dense[k - WINDOW_20_STATIONS]) / (half * half)
			if k >= WINDOW_40_STATIONS and k + WINDOW_40_STATIONS < count and not (is_nan(dense[k - WINDOW_40_STATIONS]) or is_nan(dense[k + WINDOW_40_STATIONS])):
				var half40 := WINDOW_40_STATIONS * step
				k40 = (dense[k + WINDOW_40_STATIONS] - 2.0 * dense[k] + dense[k - WINDOW_40_STATIONS]) / (half40 * half40)
			if k20 < -CREST_CURVATURE:
				kind = "crest"
			elif k20 > CREST_CURVATURE:
				kind = "dip"
		if kind != run_kind:
			if not run_best.is_empty():
				labels.append(run_best)
			run_kind = kind
			run_best = {}
		if kind != "" and (run_best.is_empty() or absf(k20) > absf(run_best.k20)):
			run_best = {"at": k * step, "kind": kind, "k20": k20, "k40": k40}
	if not run_best.is_empty():
		labels.append(run_best)
	var out: Array[Dictionary] = []
	for label: Dictionary in labels:
		var entry := {"at": _rounded(label.at, CHAINAGE_DECIMALS), "kind": label.kind, "curvature_20m": _rounded(label.k20, CURVATURE_DECIMALS)}
		if not is_nan(label.k40):
			entry["curvature_40m"] = _rounded(label.k40, CURVATURE_DECIMALS)
		out.append(entry)
	return out


## One segment's drape record from a height sampler (drape.py's
## drape_segment): `sample.call(x, z)` returns the DEM's height, or null
## outside it. The skeleton segment's tags give the bridge/tunnel rule; the
## Karussell's way the bank. Null when no point can be sampled. Heights are
## rounded as the file's are; a missing height is null in the record.
static func drape_segment(segment: SkeletonLoader.Segment, points: Array, sample: Callable) -> Variant:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for point: Variant in points:
		xs.append(float(point[0]))
		zs.append(float(point[1]))
	var chain := chainages(xs, zs)
	var length := chain[chain.size() - 1]
	var stations := station_chainages(length)
	var raw_dense: Array = []
	for s: float in stations:
		var p := _along(xs, zs, chain, s)
		raw_dense.append(sample.call(p[0], p[1]))
	var raw_points: Array = []
	for i: int in xs.size():
		raw_points.append(sample.call(xs[i], zs[i]))
	var covered := not raw_dense.has(null) and not raw_points.has(null)
	if raw_points.all(func(h: Variant) -> bool: return h == null) and raw_dense.all(func(h: Variant) -> bool: return h == null):
		return null
	var crossfall := crossfall_of(xs, zs)
	var is_bridge: bool = segment.tags.has("bridge") and segment.tags["bridge"] != "no"
	var is_tunnel: bool = segment.tags.get("tunnel") == "yes"
	if is_bridge or is_tunnel:
		if not covered:
			var nulls_points: Array = []
			nulls_points.resize(xs.size())
			var nulls_dense: Array = []
			nulls_dense.resize(stations.size())
			return {"id": segment.id, "covered": false, "heights": nulls_points, "dense": nulls_dense, "crossfall": _rounded_all(crossfall, CROSSFALL_DECIMALS), "labels": []}
		if is_bridge:
			var h0: float = raw_dense[0]
			var h1: float = raw_dense[raw_dense.size() - 1]
			for k: int in stations.size():
				raw_dense[k] = h0 + (h1 - h0) * (stations[k] / length if length > 0.0 else 0.0)
			for i: int in xs.size():
				raw_points[i] = h0 + (h1 - h0) * (chain[i] / length if length > 0.0 else 0.0)
		else:
			var layer := int(segment.tags.get("layer", "-1")) if segment.tags.get("layer", "-1").is_valid_int() else -1
			for k: int in stations.size():
				raw_dense[k] = raw_dense[k] - tunnel_depth(stations[k], length, layer)
			for i: int in xs.size():
				raw_points[i] = raw_points[i] - tunnel_depth(chain[i], length, layer)
	var dense: Array = []
	var dense_packed := PackedFloat64Array()
	for h: Variant in raw_dense:
		dense.append(null if h == null else _rounded(h, HEIGHT_DECIMALS))
		dense_packed.append(NAN if h == null else _rounded(h, HEIGHT_DECIMALS))
	var heights: Array = []
	for h: Variant in raw_points:
		heights.append(null if h == null else _rounded(h, HEIGHT_DECIMALS))
	var labels: Array[Dictionary] = labels_of(dense_packed, length) if covered else []
	if segment.osm_way == KARUSSELL_WAY:
		var total := 0.0
		for e: float in crossfall:
			total += e
		var sign := 1.0 if total >= 0.0 else -1.0
		crossfall.fill(sign * KARUSSELL_BANK)
		labels.append({"at": 0.0, "kind": "bank", "to": _rounded(length, CHAINAGE_DECIMALS), "bank": KARUSSELL_BANK, "bowl_m": KARUSSELL_BOWL_M, "strip_m": KARUSSELL_STRIP_M})
	return {"id": segment.id, "covered": covered, "heights": heights, "dense": dense, "crossfall": _rounded_all(crossfall, CROSSFALL_DECIMALS), "labels": labels}


## The point at chainage s as [x, z] in 64-bit floats: the mirror's station
## math never passes through a Vector2 (single precision would move a
## station by a fraction of a millimetre and flip a centimetre rounding:
## the codex review's 698.03 for the pipeline's 698.02 on 1017207289-0).
static func _along(xs: PackedFloat64Array, zs: PackedFloat64Array, chain: PackedFloat64Array, s: float) -> PackedFloat64Array:
	if s <= 0.0:
		return PackedFloat64Array([xs[0], zs[0]])
	for i: int in range(1, xs.size()):
		if chain[i] >= s:
			var span := chain[i] - chain[i - 1]
			var u := 0.0 if span <= 0.0 else (s - chain[i - 1]) / span
			return PackedFloat64Array([xs[i - 1] + u * (xs[i] - xs[i - 1]), zs[i - 1] + u * (zs[i] - zs[i - 1])])
	return PackedFloat64Array([xs[xs.size() - 1], zs[zs.size() - 1]])


## floor(value × 10^decimals + 0.5) / 10^decimals with -0.0 folded to 0.0:
## drape.py's rounded(), the same four IEEE operations, so a recount lands
## on the file's digits. The scales are exact literals, not pow().
const ROUNDING_SCALES := {2: 100.0, 3: 1000.0, 4: 10000.0, 5: 100000.0}


static func _rounded(value: float, decimals: int) -> float:
	var scale: float = ROUNDING_SCALES[decimals]
	var out := floorf(value * scale + 0.5) / scale
	return 0.0 if out == 0.0 else out


static func _rounded_all(values: PackedFloat64Array, decimals: int) -> Array:
	var out: Array = []
	for v: float in values:
		out.append(_rounded(v, decimals))
	return out


# =============================================================================
#  VALIDATION
# =============================================================================

## Everything that is wrong with `drape` (what read_file() returns) against
## `skeleton` (SkeletonLoader.read_file()'s), one line each; empty if it is
## a valid drape of the pinned snapshot on that skeleton. The schema and
## the pins first, the DEM's tiles, the coverage and the lattice against it,
## the rules against this reader's, then every segment: in the skeleton,
## sorted, heights and crossfall aligned with its points, the dense
## stations counted from its length, covered meaning no missing height,
## labels of the documented kinds inside the segment, a bank whose strip
## and bowl add up to the paved width.
static func validate(drape: Variant, skeleton: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not drape is Dictionary:
		errors.append("not a JSON object (a file that is not there, or not JSON)")
		return errors
	for key: String in TOP_KEYS:
		if not drape.has(key):
			errors.append("%s is missing" % key)
	for key: String in drape:
		if not key in TOP_KEYS:
			errors.append("%s is not in the schema" % key)
	_check_snapshot(errors, drape.get("snapshot"), skeleton)
	_check_origin(errors, drape.get("origin"))
	_check_dem(errors, drape.get("dem"))
	var coverage: Variant = drape.get("coverage")
	_check_coverage(errors, coverage)
	_check_lattice(errors, drape.get("lattice"), coverage)
	_check_rules(errors, drape.get("rules"))
	_check_segments(errors, drape.get("segments"), skeleton)
	return errors


static func _check_snapshot(errors: PackedStringArray, snapshot: Variant, skeleton: Variant) -> void:
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
		errors.append("snapshot.osm_base is %s, the pinned snapshot is %s" % [snapshot.osm_base, PINNED_OSM_BASE])
	if snapshot.has("bbox") and not _same_numbers(snapshot.bbox, SkeletonLoader.BBOX):
		errors.append("snapshot.bbox is %s, the Ring's is %s" % [snapshot.bbox, SkeletonLoader.BBOX])
	if snapshot.has("query_sha") and not _is_sha(snapshot.query_sha):
		errors.append("snapshot.query_sha is %s, not a sha256 hex" % [snapshot.query_sha])
	if snapshot.has("skeleton_sha256") and not _is_sha(snapshot.skeleton_sha256):
		errors.append("snapshot.skeleton_sha256 is %s, not a sha256 hex" % [snapshot.skeleton_sha256])
	if snapshot.has("pipeline_version") and snapshot.pipeline_version != DRAPE_PIPELINE_VERSION:
		errors.append("snapshot.pipeline_version is %s, this profile reads %d (an older or newer drape's file)" % [snapshot.pipeline_version, DRAPE_PIPELINE_VERSION])
	if snapshot.has("skeleton_pipeline_version") and snapshot.skeleton_pipeline_version != SkeletonLoader.SKELETON_PIPELINE_VERSION:
		errors.append("snapshot.skeleton_pipeline_version is %s, the skeleton's is %d" % [snapshot.skeleton_pipeline_version, SkeletonLoader.SKELETON_PIPELINE_VERSION])
	if skeleton is Dictionary and skeleton.get("snapshot") is Dictionary:
		for key: String in ["osm_base", "query_sha"]:
			if snapshot.has(key) and skeleton.snapshot.has(key) and snapshot[key] != skeleton.snapshot[key]:
				errors.append("snapshot.%s is %s, the skeleton's is %s (draped on another skeleton)" % [key, snapshot[key], skeleton.snapshot[key]])


static func _check_origin(errors: PackedStringArray, origin: Variant) -> void:
	if not origin is Dictionary:
		errors.append("origin is not an object")
		return
	var expected := {"epsg": SkeletonLoader.EPSG, "e0": SkeletonLoader.E0, "n0": SkeletonLoader.N0}
	for key: String in expected:
		if not origin.has(key):
			errors.append("origin.%s is missing" % key)
		elif not (_is_number(origin[key]) and origin[key] == expected[key]):
			errors.append("origin.%s is %s, the Ring's is %s" % [key, origin[key], expected[key]])
	for key: String in origin:
		if not expected.has(key):
			errors.append("origin.%s is not in the schema" % key)


static func _check_dem(errors: PackedStringArray, dem: Variant) -> void:
	if not dem is Dictionary:
		errors.append("dem is not an object")
		return
	for key: String in DEM_KEYS:
		if not dem.has(key):
			errors.append("dem.%s is missing" % key)
	for key: String in dem:
		if not key in DEM_KEYS:
			errors.append("dem.%s is not in the schema" % key)
	if dem.has("source") and not (dem.source is String and dem.source != ""):
		errors.append("dem.source is %s, not a name" % [dem.source])
	if dem.has("epsg") and dem.epsg != DEM_EPSG:
		errors.append("dem.epsg is %s, the tiles' is %d" % [dem.epsg, DEM_EPSG])
	if dem.has("vertical_datum") and dem.vertical_datum != DEM_VERTICAL_DATUM:
		errors.append("dem.vertical_datum is %s, the tiles' is %s" % [dem.vertical_datum, DEM_VERTICAL_DATUM])
	if dem.has("grid_m") and dem.grid_m != DEM_GRID_M:
		errors.append("dem.grid_m is %s, the DGM1 is %s" % [dem.grid_m, DEM_GRID_M])
	if not dem.has("tiles"):
		return
	if not dem.tiles is Array or dem.tiles.is_empty():
		errors.append("dem.tiles is %s, a list of the pinned tiles" % [dem.tiles])
		return
	var name_pattern := RegEx.create_from_string(TILE_NAME_PATTERN)
	var seen := {}
	var previous := ""
	for i: int in dem.tiles.size():
		var tile: Variant = dem.tiles[i]
		if not tile is Dictionary or not tile.get("name") is String:
			errors.append("dem.tiles[%d] is not a tile with a name" % i)
			continue
		for key: String in TILE_KEYS:
			if not tile.has(key):
				errors.append("dem.tiles[%s].%s is missing" % [tile.name, key])
		for key: String in tile:
			if not key in TILE_KEYS:
				errors.append("dem.tiles[%s].%s is not in the schema" % [tile.name, key])
		if name_pattern.search(tile.name) == null:
			errors.append("dem.tiles[%d] is %s, not a tile of the documented name" % [i, tile.name])
		if seen.has(tile.name):
			errors.append("dem.tiles lists %s twice" % tile.name)
		seen[tile.name] = true
		if tile.name < previous:
			errors.append("dem.tiles: %s comes after %s, tiles are sorted by name" % [tile.name, previous])
		previous = tile.name
		if tile.has("sha256") and not _is_sha(tile.sha256):
			errors.append("dem.tiles[%s].sha256 is %s, not a sha256 hex" % [tile.name, tile.sha256])
		if tile.has("verified") and not tile.verified is bool:
			errors.append("dem.tiles[%s].verified is %s, not a bool" % [tile.name, tile.verified])
		elif tile.get("verified") == false:
			errors.append("dem.tiles[%s] was not verified against the metalink's sha256" % tile.name)


static func _check_coverage(errors: PackedStringArray, coverage: Variant) -> void:
	if not coverage is Dictionary:
		errors.append("coverage is not an object")
		return
	for key: String in COVERAGE_KEYS:
		if not coverage.has(key):
			errors.append("coverage.%s is missing" % key)
		elif not _is_number(coverage[key]):
			errors.append("coverage.%s is %s, not a number" % [key, coverage[key]])
	for key: String in coverage:
		if not key in COVERAGE_KEYS:
			errors.append("coverage.%s is not in the schema" % key)
	if _is_number(coverage.get("x_min")) and _is_number(coverage.get("x_max")) and coverage.x_min >= coverage.x_max:
		errors.append("coverage x %s..%s is empty" % [coverage.x_min, coverage.x_max])
	if _is_number(coverage.get("z_min")) and _is_number(coverage.get("z_max")) and coverage.z_min >= coverage.z_max:
		errors.append("coverage z %s..%s is empty" % [coverage.z_min, coverage.z_max])


static func _check_lattice(errors: PackedStringArray, lattice: Variant, coverage: Variant) -> void:
	if not lattice is Dictionary:
		errors.append("lattice is not an object")
		return
	for key: String in LATTICE_KEYS:
		if not lattice.has(key):
			errors.append("lattice.%s is missing" % key)
	for key: String in lattice:
		if not key in LATTICE_KEYS:
			errors.append("lattice.%s is not in the schema" % key)
	if not (_is_number(lattice.get("step_m")) and lattice.step_m > 0.0):
		errors.append("lattice.step_m is %s, not a positive spacing" % [lattice.get("step_m")])
		return
	if not (_is_whole(lattice.get("cols")) and lattice.cols >= 2 and _is_whole(lattice.get("rows")) and lattice.rows >= 2):
		errors.append("lattice is %s × %s, at least 2 × 2" % [lattice.get("cols"), lattice.get("rows")])
		return
	if not lattice.get("heights") is Array or lattice.heights.size() != int(lattice.cols) * int(lattice.rows):
		errors.append("lattice.heights has %s, cols × rows is %d" % [lattice.heights.size() if lattice.get("heights") is Array else lattice.get("heights"), int(lattice.cols) * int(lattice.rows)])
	else:
		for i: int in lattice.heights.size():
			if not _is_number(lattice.heights[i]):
				errors.append("lattice.heights[%d] is %s, not a finite height" % [i, lattice.heights[i]])
				break
	if coverage is Dictionary and _is_number(lattice.get("x0")) and _is_number(lattice.get("z0")) and _is_number(coverage.get("x_min")) and _is_number(coverage.get("x_max")) and _is_number(coverage.get("z_min")) and _is_number(coverage.get("z_max")):
		if lattice.x0 != coverage.x_min or lattice.z0 != coverage.z_min:
			errors.append("lattice starts at (%s, %s), the coverage at (%s, %s)" % [lattice.x0, lattice.z0, coverage.x_min, coverage.z_min])
		if absf(lattice.x0 + (int(lattice.cols) - 1) * lattice.step_m - coverage.x_max) > 1e-6 or absf(lattice.z0 + (int(lattice.rows) - 1) * lattice.step_m - coverage.z_max) > 1e-6:
			errors.append("lattice ends at (%s, %s), the coverage at (%s, %s)" % [lattice.x0 + (int(lattice.cols) - 1) * lattice.step_m, lattice.z0 + (int(lattice.rows) - 1) * lattice.step_m, coverage.x_max, coverage.z_max])


static func _check_rules(errors: PackedStringArray, rules: Variant) -> void:
	if not rules is Dictionary:
		errors.append("rules is not an object")
		return
	for key: String in RULES:
		if not rules.has(key):
			errors.append("rules.%s is missing" % key)
		elif not (_is_number(rules[key]) and rules[key] == RULES[key]):
			errors.append("rules.%s is %s, this profile's is %s (a file of other rules)" % [key, rules[key], RULES[key]])
	for key: String in rules:
		if not RULES.has(key):
			errors.append("rules.%s is not in the schema" % key)


static func _check_segments(errors: PackedStringArray, raw: Variant, skeleton: Variant) -> void:
	if not raw is Array:
		errors.append("segments is not a list")
		return
	var segments := SkeletonLoader.segments_of(skeleton) if skeleton is Dictionary else {}
	var raw_points := _raw_points_of(skeleton) if skeleton is Dictionary else {}
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
		if id < previous:
			errors.append("segment %s comes after %s, segments are sorted by id" % [id, previous])
		previous = id
		for key: String in SEGMENT_KEYS:
			if not element.has(key):
				errors.append("segment %s.%s is missing" % [id, key])
		for key: String in element:
			if not key in SEGMENT_KEYS:
				errors.append("segment %s.%s is not in the schema" % [id, key])
		if not segments.has(id):
			errors.append("segment %s is not in the skeleton" % id)
			continue
		var segment: SkeletonLoader.Segment = segments[id]
		var xs := PackedFloat64Array()
		var zs := PackedFloat64Array()
		for point: Variant in raw_points[id]:
			xs.append(float(point[0]))
			zs.append(float(point[1]))
		var chain := chainages(xs, zs)
		var length := chain[chain.size() - 1]
		var stations := station_chainages(length).size()
		var covered: Variant = element.get("covered")
		if not covered is bool:
			errors.append("segment %s.covered is %s, not a bool" % [id, covered])
			covered = false
		var missing := 0
		for key: String in ["heights", "dense", "crossfall"]:
			var values: Variant = element.get(key)
			if values == null and not element.has(key):
				continue
			var expected := stations if key == "dense" else xs.size()
			if not values is Array or values.size() != expected:
				errors.append("segment %s.%s has %s, the segment's %s are %d" % [id, key, values.size() if values is Array else values, "stations" if key == "dense" else "points", expected])
				continue
			for j: int in values.size():
				var value: Variant = values[j]
				if value == null and key != "crossfall":
					missing += 1
				elif not _is_number(value):
					errors.append("segment %s.%s[%d] is %s, not a number" % [id, key, j, value])
					break
				elif key == "crossfall" and absf(value) > maxf(HAIRPIN_SUPERELEVATION_MAX, KARUSSELL_BANK):
					errors.append("segment %s.crossfall[%d] is %s, beyond any rule's" % [id, j, value])
					break
		if covered and missing > 0:
			errors.append("segment %s is covered with %d missing height(s)" % [id, missing])
		if not covered and missing == 0 and element.get("heights") is Array and element.get("dense") is Array:
			errors.append("segment %s is not covered with no missing height" % id)
		_check_labels(errors, id, element.get("labels"), length, segment.width_m)


static func _check_labels(errors: PackedStringArray, id: String, labels: Variant, length: float, width: float) -> void:
	if labels == null:
		return
	if not labels is Array:
		errors.append("segment %s.labels is not a list" % id)
		return
	for j: int in labels.size():
		var label: Variant = labels[j]
		if not label is Dictionary or not label.get("kind") is String:
			errors.append("segment %s.labels[%d] is not a label with a kind" % [id, j])
			continue
		if not label.kind in LABEL_KINDS:
			errors.append("segment %s.labels[%d].kind is %s, not one of %s" % [id, j, label.kind, LABEL_KINDS])
			continue
		var keys: Array = BANK_LABEL_KEYS if label.kind == "bank" else GEOMETRY_LABEL_KEYS
		for key: String in label:
			if not key in keys:
				errors.append("segment %s.labels[%d].%s is not in a %s label's schema" % [id, j, key, label.kind])
		if not (_is_number(label.get("at")) and label.at >= 0.0 and label.at <= length + 1e-6):
			errors.append("segment %s.labels[%d].at is %s, outside 0..%.3f" % [id, j, label.get("at"), length])
		if label.kind == "bank":
			for key: String in ["to", "bank", "bowl_m", "strip_m"]:
				if not _is_number(label.get(key)):
					errors.append("segment %s.labels[%d].%s is %s, not a number" % [id, j, key, label.get(key)])
			if _is_number(label.get("bowl_m")) and _is_number(label.get("strip_m")) and absf(label.bowl_m + label.strip_m - width) > 1e-6:
				errors.append("segment %s bank: strip %s + bowl %s is not the paved width %s" % [id, label.strip_m, label.bowl_m, width])
			if _is_number(label.get("bank")) and (label.bank <= 0.0 or label.bank > 1.0):
				errors.append("segment %s bank is %s, not a rise over run in (0, 1]" % [id, label.bank])
		else:
			if not _is_number(label.get("curvature_20m")):
				errors.append("segment %s.labels[%d].curvature_20m is %s, not a number" % [id, j, label.get("curvature_20m")])
			elif (label.kind == "crest") != (label.curvature_20m < 0.0):
				errors.append("segment %s.labels[%d] is a %s with curvature %s" % [id, j, label.kind, label.curvature_20m])
			elif absf(label.curvature_20m) + CURVATURE_HALF_STEP < CREST_CURVATURE:
				errors.append("segment %s.labels[%d] curvature %s is within the threshold %s" % [id, j, label.curvature_20m, CREST_CURVATURE])


static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value)


static func _is_whole(value: Variant) -> bool:
	return _is_number(value) and value == floorf(value)


static func _is_sha(value: Variant) -> bool:
	return value is String and RegEx.create_from_string(SHA256_PATTERN).search(value) != null


static func _same_numbers(a: Variant, b: Array) -> bool:
	if not a is Array or a.size() != b.size():
		return false
	for i: int in b.size():
		if not _is_number(a[i]) or a[i] != b[i]:
			return false
	return true
