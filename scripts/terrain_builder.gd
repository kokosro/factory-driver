class_name TerrainBuilder
extends Node3D
## The Ring's terrain forms (implementation-plan.md §4B-7; element-library.md
## §2, the T-family): the drape's terrain lattice built into meshes whose
## spacing follows the T-family's stone table by distance from the road,
## the forms T1-T4 / T7 / T8 / T9 classified for their tint only, the V7
## forest interior as a dark canopy tint on the same surface, and the water
## planes; built headless in _ready from the checked-in files (the drape's
## lattice and the skeleton through the RoadBuilder's parsed copies and the
## profile it handed the car, landcover.json for the polygons). VISUALS
## ONLY: no collision shape, no body, no Area3D, nothing the car can read -
## the car stands on the injected WorldRoadProfile and nothing here changes
## it (the ring drive test's output is the same byte for byte).
##
## THE LATTICE PLAN (the catalogue's T1.stone_parameters, never a number
## of this file's own): "2 m at the road platform, 10 m within 200 m, 50 m
## to 2 km, 200 m beyond". The drape's lattice is 10 m over the 7 km × 6 km
## core (the only heights there are: outside the core the profile is flat
## and nothing is built). The plan is over 50 m TILES (a tile is 5 × 5
## lattice cells; 140 × 120 tiles) and 200 m BLOCKS (4 × 4 tiles):
##   * distance: every lattice node's distance to the nearest covered road
##     centreline, an exact Euclidean distance transform (Felzenszwalb &
##     Huttenlocher's, in cell units, the roads rasterised onto the nodes
##     nearest their centrelines: a node's distance is the centreline's
##     within half a lattice step);
##   * a tile whose nearest node is within 200 m of a road is NEAR: its 25
##     cells are drawn at the lattice's 10 m; a block whose 16 tiles are all
##     beyond 2 km is FAR: one 200 m quad (T9, the distant ridge); every
##     other tile is MID: one 50 m quad. Measured on the Ring's core: 16 300
##     near tiles, 500 mid, no far block (the core has no point 2 km from
##     every road; T9 is the rule with nothing to draw at first focus);
##   * where a coarser tile meets a finer one its edge is a straight chord
##     across nodes the finer side draws exactly, so the coarser edge hangs
##     a skirt SKIRT_M down: the crack a chord above the fine surface would
##     open is closed by it (the classic LOD skirt; the crack the other way
##     is a step, not a hole);
##   * the platform band, 2 m: the road builder's own strip is the platform
##     at the drape's 2 m stations (implementation-plan.md §4B-4), and the
##     terrain's share of the band is the BLEND BAND beside it (the
##     profile's BLEND_BAND_M outside the paved edge, where the platform is
##     eased into the lattice) plus an APRON beyond: one strip per covered
##     road, sections at every 2 m station AND every skeleton point (the
##     field's breakpoints; a chord's right normal, mitred at the points
##     as the road builder's are), offsets at the paved edge, the blend
##     band's end and the apron's end either side, every vertex's height
##     the profile's own field at the vertex (elevation_height: the
##     platform's edge, the eased band, the terrain beyond), so the strip
##     and the road meet edge to edge. The apron reaches one lattice cell's
##     diagonal beyond the blend band and dives APRON_UNDERCUT_M under the
##     lattice: the near mesh drops every cell that has a node inside a
##     road's reach (a 10 m cell across the platform would hide the road
##     in a cutting), and the apron is what shows in those cells.
## The 10 m band draws the lattice's own nodes (row-major, 10 m apart: the
## test holds every vertex to the grid), never a resampling.
##
## THE FORMS, for tint only (a vertex colour; one StandardMaterial3D with
## the colour as albedo: the canon's "one slope material blend:
## grass->rock by slope, no splat painting"): the slope at a node from the
## lattice's central differences, T1 below T1.slope_max_pct, T2 in
## T2.slope_pct, T3 above T3.slope_min_pct (the catalogue's numbers); T4
## the valley floor: a node within VALLEY_RISE_M of the lowest ground in a
## VALLEY_WINDOW_M window that has VALLEY_RELIEF_M of relief and is not
## steep (the library's "DGM1 local minima", made a rule here); T7 a node
## inside a landcover field polygon (farmland / meadow / grass, its patch
## tint one of T7's 2-3 by the seeded hash of the polygon's OSM id); V7 a
## node inside a forest polygon (the canopy tint; the library's "interior is
## a dark canopy plane on the terrain": the terrain IS the plane, tinted);
## T8 water polygons as flat planes at the lowest lattice height under them
## and river / stream ways as thin strips on the lattice (T4's thread: "a
## river is a T8 strip"); T9 the far band's tint. The palette is the region
## table's (dressing.json `palette.tints`, ring-region-decisions.md
## §5: muted forest / olive greens, grey slate, grey-green water), capped
## under the canon's ~0.6 luminance. Placeholder materials: flat colours,
## no texture, no new asset (the canon's tiled 1024 grass is 4B-8+).
##
## DETERMINISM (data-pipeline.md §7): no RNG, no wall clock; every choice
## (a field's patch tint) is fnv1a(region_id) hashed with (osm_id, purpose)
## - hash_unit(). The same files build the same meshes; build_ms is the
## only number that differs between runs and it is never printed by a test.
##
## THE REGION TABLE: dressing.json beside focus.json (region_dressing(),
## validate_dressing()) names the region's choices - the sky set, the
## haze, the sun's bearing, the palette's tints, the density ceilings - and
## cites its lines in ring-region-decisions.md §5; the catalogue carries
## the stone (the lattice table, the slopes, the 60 m, the band distances).
## The three dressing nodes read the table through this class.

## Where the landcover is (tools/world/landcover.py writes it) and where the
## region's dressing table is (beside Buildings.PATH: the buildings test
## pins focus.json's four top keys, a check that stays, so the region's
## sky set, palette and ceilings are a second region file of the folder).
const LANDCOVER_PATH := "res://data/regions/eifel_ring/landcover.json"
const DRESSING_PATH := "res://data/regions/eifel_ring/dressing.json"
const LANDCOVER_PIPELINE_VERSION := 1
const REGION := "eifel_ring"

## The elements this node instantiates (ids in the catalogue).
const ELEMENTS := ["T1", "T2", "T3", "T4", "T7", "T8", "T9", "V7"]

## The plan's units [m]: a tile is the mid band's spacing, a block the far
## band's; both read from the catalogue at build (T1.stone_parameters) and
## held equal to these by the test.
const TILE_M := 50.0
const BLOCK_M := 200.0

## The skirt a coarser edge hangs down where it meets a finer tile [m].
const SKIRT_M := 6.0

## The apron beyond the blend band [m]: one lattice cell's diagonal, so the
## strip covers every cell the near mesh drops; and how far under the
## lattice its outer edge dives [m] (the blend band's end sits
## BLEND_UNDERCUT_M under, a step no eye finds, so the apron never crosses
## the lattice's own quads where both are drawn).
const APRON_M := 15.0
const APRON_UNDERCUT_M := 0.3
const BLEND_UNDERCUT_M := 0.03

## The valley rule (T4): within this of the window's lowest ground, in a
## window of this size with at least this relief.
const VALLEY_RISE_M := 6.0
const VALLEY_WINDOW_M := 300.0
const VALLEY_RELIEF_M := 40.0

## Water: the plane's lift over the lowest lattice height under it, the
## strip half widths of the T4 thread [m], a strip's section step [m].
const WATER_LIFT_M := 0.1
const RIVER_HALF_WIDTH_M := 1.5
const STREAM_HALF_WIDTH_M := 0.75
const WATERWAY_STEP_M := 10.0

## A near-band chunk [m]: the near mesh is cut into these for the
## renderer's culling (one MeshInstance3D each).
const CHUNK_M := 1000.0

## The mitre cap at a skeleton point (RoadBuilder.MAX_MITRE, the same idea).
const MAX_MITRE := 2.0
const SAME_CHAINAGE_M := 1e-6

## The keys of the region table's dressing block and its sub-blocks.
const DRESSING_KEYS := ["region", "stone", "sky_set", "haze", "sun", "palette", "forest", "density"]
const DRESSING_STONE_KEYS := ["doc", "section", "lines", "note"]
const DRESSING_SUN_KEYS := ["azimuth_deg", "note"]
const DRESSING_PALETTE_KEYS := ["vegetation", "forest_wall", "rock", "water", "sky", "tints"]
const DRESSING_FOREST_KEYS := ["wall_tint", "interior_tint", "note"]
const DRESSING_DENSITY_KEYS := ["trees_within_60_m_per_8_m_per_side", "meaningful_objects_within_500_m", "note"]
## The tints the palette has to name (the forms and the masses this pass draws).
const TINT_KEYS := ["T1", "T2", "T3", "T4", "T7a", "T7b", "T7c", "T8", "T9", "V7", "V4_front", "V4_middle", "V4_back", "V2", "V1", "trunk"]
## The canon's luminance cap for environment albedo (element-library.md §3).
const LUMINANCE_CAP := 0.6

## The form codes per node (form[]): what the tint says.
const FORM_T1 := 1
const FORM_T2 := 2
const FORM_T3 := 3
const FORM_T4 := 4
const FORM_T7 := 7
const FORM_V7 := 8
const FORM_T9 := 9

## The landcover raster codes (cover[]).
const COVER_NONE := 0
const COVER_FOREST := 1
const COVER_FIELD := 2
const COVER_WATER := 3
const COVER_ROCK := 4

## The tile classes (tile_class[]).
const TILE_NEAR := 1
const TILE_MID := 2
const TILE_FAR := 3

## A big finite number standing for "no road" in the distance transform.
const FAR_AWAY := 1.0e18

@export var road: RoadBuilder

## The profile the heights come from (the road builder's: what the car
## reads) and the files as parsed.
var profile: WorldRoadProfile
var landcover: Dictionary = {}
var table: Dictionary = {}

## The lattice as built: step [m], origin, size, heights (row-major, rows
## along +z), and the per-node fields the plan and the tints are made of.
var step := 0.0
var x0 := 0.0
var z0 := 0.0
var cols := 0
var rows := 0
var heights: PackedFloat64Array
## Distance to the nearest covered road centreline per node [m].
var distance: PackedFloat64Array
## 1 where the node is inside a road's reach (the profile answers a road).
var reach: PackedByteArray
## The landcover raster per node (COVER_*), and the field's tint index.
var cover: PackedByteArray
var cover_tint: PackedByteArray
## The form per node (FORM_*), its tint, and the slope [%].
var form: PackedByteArray
var node_colours: PackedColorArray
var slope_pct: PackedFloat32Array
## The tile plan: per 50 m tile (row-major, tile_cols × tile_rows), TILE_*.
var tile_cols := 0
var tile_rows := 0
var tile_class: PackedByteArray
## The bands as read from the catalogue [m].
var band := {"platform": 2.0, "near": 10.0, "near_within": 200.0, "mid": 50.0, "mid_to": 2000.0, "far": 200.0}

## The covered roads the strips are swept along (RoadBuilder's Road shape
## without the crossfall: only the centreline and the half width matter
## here; the heights are the profile's).
class Ribbon:
	extends RefCounted
	var id: String
	var xs: PackedFloat64Array
	var zs: PackedFloat64Array
	var chain: PackedFloat64Array
	var length: float
	var half_width: float

var ribbons: Array[Ribbon] = []
## The platform strips by road id: {"chainages": PackedFloat64Array,
## "offsets": PackedFloat64Array, "mesh": MeshInstance3D, "vertices": int}.
var strips: Dictionary = {}

## What was built: counts (no wall time but build_ms).
var counts := {"near_tiles": 0, "mid_tiles": 0, "far_blocks": 0, "near_cells": 0, "near_cells_dropped": 0, "skirts": 0, "strips": 0, "strip_sections": 0, "water_planes": 0, "waterway_strips": 0, "vertices": 0, "triangles": 0}
var elements: Dictionary = {}
var build_ms := 0
var _material: StandardMaterial3D
var _water_material: StandardMaterial3D
var _tints: Dictionary = {}


func _ready() -> void:
	if road != null and road.profile != null:
		build(road.profile, road.skeleton_data, road.drape_data, read_landcover())
	else:
		var skeleton: Variant = SkeletonLoader.read_file()
		var drape: Variant = WorldRoadProfile.read_file()
		if not skeleton is Dictionary or not drape is Dictionary:
			push_error("TerrainBuilder: the skeleton or the drape is missing or not JSON")
			return
		build(WorldRoadProfile.from_data(skeleton, drape), skeleton, drape, read_landcover())


# =============================================================================
#  THE FILES
# =============================================================================

## What JSON.parse_string makes of the landcover file: null where it is
## missing or not JSON.
static func read_landcover(path: String = LANDCOVER_PATH) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Everything wrong with a landcover file, one line each; empty = valid.
## The schema, the pinned snapshot, the origin, the counts against the
## lists, every ring closed with at least four points, every coordinate a
## finite number rounded to the millimetre.
static func validate_landcover(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary:
		errors.append("not a JSON object (a file that is not there, or not JSON)")
		return errors
	for key: String in ["region", "pipeline_version", "snapshot", "origin", "provenance", "counts", "forests", "fields", "water", "waterways", "rock", "trees", "tree_rows"]:
		if not data.has(key):
			errors.append("%s is missing" % key)
	if data.get("region") != REGION:
		errors.append("region is %s, this reader's is %s" % [data.get("region"), REGION])
	if data.get("pipeline_version") != LANDCOVER_PIPELINE_VERSION:
		errors.append("pipeline_version is %s, this reader's is %d" % [data.get("pipeline_version"), LANDCOVER_PIPELINE_VERSION])
	var snapshot: Variant = data.get("snapshot")
	if not snapshot is Dictionary or snapshot.get("osm_base") != SkeletonLoader.PINNED_OSM_BASE:
		errors.append("snapshot.osm_base is %s, the pinned snapshot is %s" % [snapshot.get("osm_base") if snapshot is Dictionary else snapshot, SkeletonLoader.PINNED_OSM_BASE])
	var origin: Variant = data.get("origin")
	if not origin is Dictionary or origin.get("epsg") != SkeletonLoader.EPSG or origin.get("e0") != SkeletonLoader.E0 or origin.get("n0") != SkeletonLoader.N0:
		errors.append("origin is not the region frame (EPSG %d, E0 %.0f, N0 %.0f)" % [SkeletonLoader.EPSG, SkeletonLoader.E0, SkeletonLoader.N0])
	var counts: Variant = data.get("counts")
	for list_name: String in ["forests", "fields", "water", "waterways", "rock", "trees", "tree_rows"]:
		var list: Variant = data.get(list_name)
		if not list is Array:
			errors.append("%s is not a list" % list_name)
			continue
		if counts is Dictionary and counts.get(list_name) != list.size():
			errors.append("counts.%s is %s, the list holds %d" % [list_name, counts.get(list_name), list.size()])
		for i: int in list.size():
			var record: Variant = list[i]
			if not record is Dictionary or not _is_whole(record.get("osm")):
				errors.append("%s[%d] is not a record with an osm id" % [list_name, i])
				continue
			if list_name in ["forests", "fields", "water"] or (list_name == "rock" and record.get("kind") == "bare_rock"):
				for ring_list: String in ["outer", "inner"]:
					if not record.get(ring_list) is Array:
						errors.append("%s %d.%s is not a list of rings" % [list_name, int(record.osm), ring_list])
						continue
					for ring: Variant in record[ring_list]:
						var fault := _ring_fault(ring)
						if fault != "":
							errors.append("%s %d.%s: %s" % [list_name, int(record.osm), ring_list, fault])
				if list_name != "water" and record.get("outer") is Array and record.outer.is_empty():
					errors.append("%s %d has no outer ring" % [list_name, int(record.osm)])
			elif list_name == "trees":
				if not _is_mm(record.get("x")) or not _is_mm(record.get("z")):
					errors.append("trees %d: x/z are not mm-rounded finite numbers" % int(record.osm))
			else:
				var points: Variant = record.get("points", record.get("line"))
				if not points is Array or points.size() < 2:
					errors.append("%s %d has fewer than two points" % [list_name, int(record.osm)])
				else:
					for point: Variant in points:
						if not _is_point(point):
							errors.append("%s %d: a point is not an mm-rounded [x, z]" % [list_name, int(record.osm)])
							break
	return errors


static func _ring_fault(ring: Variant) -> String:
	if not ring is Array or ring.size() < 4:
		return "a ring with fewer than four points"
	for point: Variant in ring:
		if not _is_point(point):
			return "a point is not an mm-rounded [x, z]"
	if ring[0][0] != ring[ring.size() - 1][0] or ring[0][1] != ring[ring.size() - 1][1]:
		return "a ring that does not close"
	return ""


static func _is_point(point: Variant) -> bool:
	return point is Array and point.size() == 2 and _is_mm(point[0]) and _is_mm(point[1])


static func _is_mm(value: Variant) -> bool:
	if not ((value is float or value is int) and is_finite(value)):
		return false
	return absf(value * 1000.0 - roundf(value * 1000.0)) < 1e-6


static func _is_whole(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value) and value == floorf(value)


## The region's dressing table (DRESSING_PATH), read once; empty when the
## file is missing or not JSON (the builders then take their defaults and
## the test says so).
static var _dressing: Dictionary = {}


static func read_dressing(path: String = DRESSING_PATH) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


static func region_dressing() -> Dictionary:
	if _dressing.is_empty():
		var table: Variant = read_dressing()
		if table is Dictionary:
			_dressing = table
	return _dressing


## Everything wrong with a dressing block, one line each; empty = valid.
static func validate_dressing(block: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not block is Dictionary:
		errors.append("dressing is not an object")
		return errors
	for key: String in DRESSING_KEYS:
		if not block.has(key):
			errors.append("dressing.%s is missing" % key)
	for key: String in block:
		if not key in DRESSING_KEYS:
			errors.append("dressing.%s is not in the schema" % key)
	if block.has("region") and block.region != REGION:
		errors.append("dressing.region is %s, this reader's is %s" % [block.region, REGION])
	for id_key: String in ["sky_set", "haze"]:
		var id: Variant = block.get(id_key)
		if id is String and (not ElementCatalogue.is_id(id) or not id.begins_with("S")):
			errors.append("dressing.%s is %s, not an S id" % [id_key, id])
	_check_keys(errors, "dressing.stone", block.get("stone"), DRESSING_STONE_KEYS)
	_check_keys(errors, "dressing.sun", block.get("sun"), DRESSING_SUN_KEYS)
	_check_keys(errors, "dressing.palette", block.get("palette"), DRESSING_PALETTE_KEYS)
	_check_keys(errors, "dressing.forest", block.get("forest"), DRESSING_FOREST_KEYS)
	_check_keys(errors, "dressing.density", block.get("density"), DRESSING_DENSITY_KEYS)
	var sun: Variant = block.get("sun")
	if sun is Dictionary and sun.has("azimuth_deg") and not ((sun.azimuth_deg is float or sun.azimuth_deg is int) and sun.azimuth_deg >= 0.0 and sun.azimuth_deg < 360.0):
		errors.append("dressing.sun.azimuth_deg is %s, not a bearing in [0, 360)" % [sun.azimuth_deg])
	var palette: Variant = block.get("palette")
	if palette is Dictionary and palette.has("tints"):
		if not palette.tints is Dictionary:
			errors.append("dressing.palette.tints is not an object")
		else:
			for key: String in TINT_KEYS:
				var tint: Variant = palette.tints.get(key)
				if not tint is Array or tint.size() != 3:
					errors.append("dressing.palette.tints.%s is missing or not [r, g, b]" % key)
					continue
				var ok := true
				for channel: Variant in tint:
					ok = ok and (channel is float or channel is int) and channel >= 0.0 and channel <= 1.0
				if not ok:
					errors.append("dressing.palette.tints.%s has a channel outside [0, 1]" % key)
				elif luminance(Color(tint[0], tint[1], tint[2])) > LUMINANCE_CAP:
					errors.append("dressing.palette.tints.%s has luminance %.2f, above the canon's %.1f cap" % [key, luminance(Color(tint[0], tint[1], tint[2])), LUMINANCE_CAP])
			for key: String in palette.tints:
				if not key in TINT_KEYS:
					errors.append("dressing.palette.tints.%s is not a tint this pass draws" % key)
	var density: Variant = block.get("density")
	if density is Dictionary:
		for key: String in ["trees_within_60_m_per_8_m_per_side", "meaningful_objects_within_500_m"]:
			if density.has(key) and not (_is_whole(density[key]) and density[key] >= 0):
				errors.append("dressing.density.%s is %s, not a whole number" % [key, density[key]])
	return errors


static func _check_keys(errors: PackedStringArray, where: String, block: Variant, keys: Array) -> void:
	if not block is Dictionary:
		if block != null:
			errors.append("%s is not an object" % where)
		return
	for key: String in block:
		if not key in keys:
			errors.append("%s.%s is not in the schema" % [where, key])


## Rec. 709 luminance of a colour (the canon's albedo cap is judged on it).
static func luminance(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


## A tint from the region table, or the default when the table lacks it.
static func tint(name: String, fallback: Color) -> Color:
	var palette: Variant = region_dressing().get("palette", {})
	if palette is Dictionary and palette.get("tints") is Dictionary and palette.tints.get(name) is Array and palette.tints[name].size() == 3:
		var t: Array = palette.tints[name]
		return Color(t[0], t[1], t[2], 1.0)
	return fallback


# =============================================================================
#  THE HASH (data-pipeline.md §7)
# =============================================================================

## 32-bit FNV-1a of a string.
static func fnv1a(text: String) -> int:
	var h := 0x811c9dc5
	for byte: int in text.to_utf8_buffer():
		h = ((h ^ byte) * 0x01000193) & 0xFFFFFFFF
	return h


## The region's seed: fnv1a(region_id).
static func region_seed() -> int:
	return fnv1a(REGION)


## A unit in [0, 1) for (region seed, osm id, purpose, index): the hash of
## their text, never a running RNG. The same inputs give the same unit on
## every machine and every run.
static func hash_unit(osm_id: int, purpose: String, index: int = 0) -> float:
	return float(fnv1a("%d:%d:%s:%d" % [region_seed(), osm_id, purpose, index])) / 4294967296.0


# =============================================================================
#  THE BUILD
# =============================================================================

## Builds everything from the profile (the heights), the parsed skeleton
## and drape (the covered roads, the lattice) and the parsed landcover
## (null: no polygons, the forms by slope alone). Refuses with a push_error
## when the drape has no lattice.
func build(built_profile: WorldRoadProfile, skeleton_data: Dictionary, drape_data: Dictionary, landcover_data: Variant) -> void:
	var started := Time.get_ticks_msec()
	profile = built_profile
	landcover = landcover_data if landcover_data is Dictionary else {}
	table = region_dressing()
	_read_bands()
	if not _read_lattice(drape_data):
		push_error("TerrainBuilder: the drape has no terrain lattice")
		return
	_read_ribbons(skeleton_data, drape_data)
	_tints = {}
	_material = _flat_material()
	_water_material = _flat_material()
	_water_material.roughness = 0.2
	_water_material.metallic = 0.1
	_compute_distance()
	_compute_reach()
	_rasterise_landcover()
	_classify_forms()
	_plan_tiles()
	_build_near_band()
	_build_mid_and_far()
	_build_strips()
	_build_water()
	build_ms = Time.get_ticks_msec() - started


## The lattice table from the catalogue (T1.stone_parameters, T9's).
func _read_bands() -> void:
	var t1 := ElementCatalogue.entry("T1")
	var t9 := ElementCatalogue.entry("T9")
	if not t1.is_empty():
		var stone: Dictionary = t1.stone_parameters
		band.platform = float(stone.get("lattice_at_road_platform_m", band.platform))
		band.near = float(stone.get("lattice_within_200_m", band.near))
		band.mid = float(stone.get("lattice_to_2_km_m", band.mid))
		band.far = float(stone.get("lattice_beyond_2_km_m", band.far))
	if not t9.is_empty():
		band.mid_to = float(t9.stone_parameters.get("from_km", 2.0)) * 1000.0
		band.far = float(t9.stone_parameters.get("lattice_m", band.far))


func _read_lattice(drape_data: Dictionary) -> bool:
	var lattice: Variant = drape_data.get("lattice")
	if not lattice is Dictionary or not lattice.get("heights") is Array:
		return false
	step = float(lattice.get("step_m", 0.0))
	x0 = float(lattice.get("x0", 0.0))
	z0 = float(lattice.get("z0", 0.0))
	cols = int(lattice.get("cols", 0))
	rows = int(lattice.get("rows", 0))
	if cols < 2 or rows < 2 or step <= 0.0 or lattice.heights.size() != cols * rows:
		return false
	heights = PackedFloat64Array()
	heights.resize(cols * rows)
	for i: int in heights.size():
		heights[i] = float(lattice.heights[i])
	return true


## The covered roads as ribbons (the drape's covered records whose
## skeleton segment exists: what the road builder sweeps).
func _read_ribbons(skeleton_data: Dictionary, drape_data: Dictionary) -> void:
	ribbons = []
	var segments := SkeletonLoader.segments_of(skeleton_data)
	var raw_points := {}
	for raw: Variant in skeleton_data.get("segments", []):
		if raw is Dictionary and raw.get("id") is String:
			raw_points[raw.id] = raw.points
	for raw: Variant in drape_data.get("segments", []):
		if not raw is Dictionary or not raw.get("covered", false) or not segments.has(raw.get("id")):
			continue
		var segment: SkeletonLoader.Segment = segments[raw.id]
		var points: Array = raw_points[raw.id]
		var ribbon := Ribbon.new()
		ribbon.id = raw.id
		ribbon.xs = PackedFloat64Array()
		ribbon.zs = PackedFloat64Array()
		ribbon.xs.resize(points.size())
		ribbon.zs.resize(points.size())
		for i: int in points.size():
			ribbon.xs[i] = float(points[i][0])
			ribbon.zs[i] = float(points[i][1])
		ribbon.chain = WorldRoadProfile.chainages(ribbon.xs, ribbon.zs)
		ribbon.length = ribbon.chain[ribbon.chain.size() - 1]
		ribbon.half_width = segment.width_m / 2.0
		if ribbon.length > 0.0:
			ribbons.append(ribbon)


# =============================================================================
#  THE DISTANCE FIELD
# =============================================================================

## Every node's distance to the nearest covered centreline [m]: the
## centrelines rasterised onto their nearest nodes (a sample every half
## step along every chord), then the exact Euclidean distance transform.
func _compute_distance() -> void:
	var n := cols * rows
	var f := PackedFloat64Array()
	f.resize(n)
	f.fill(FAR_AWAY)
	var half := step * 0.5
	for ribbon: Ribbon in ribbons:
		for c: int in range(ribbon.xs.size() - 1):
			var ax := ribbon.xs[c]
			var az := ribbon.zs[c]
			var dx := ribbon.xs[c + 1] - ax
			var dz := ribbon.zs[c + 1] - az
			var length := ribbon.chain[c + 1] - ribbon.chain[c]
			var pieces := maxi(1, ceili(length / half))
			for k: int in pieces + 1:
				var t := float(k) / float(pieces)
				var j := roundi((ax + t * dx - x0) / step)
				var i := roundi((az + t * dz - z0) / step)
				if j >= 0 and j < cols and i >= 0 and i < rows:
					f[i * cols + j] = 0.0
	distance = edt(f, cols, rows)
	for i: int in n:
		distance[i] = sqrt(distance[i]) * step


## The exact Euclidean distance transform of a grid (Felzenszwalb &
## Huttenlocher 2012): `f` holds 0 at a source and FAR_AWAY elsewhere;
## the result is the squared distance in cell units. Columns first, then
## rows (the transform is separable).
static func edt(f: PackedFloat64Array, width: int, height: int) -> PackedFloat64Array:
	var g := PackedFloat64Array()
	g.resize(width * height)
	var column := PackedFloat64Array()
	column.resize(height)
	for j: int in width:
		for i: int in height:
			column[i] = f[i * width + j]
		var d := edt_1d(column)
		for i: int in height:
			g[i * width + j] = d[i]
	var out := PackedFloat64Array()
	out.resize(width * height)
	var row := PackedFloat64Array()
	row.resize(width)
	for i: int in height:
		for j: int in width:
			row[j] = g[i * width + j]
		var d := edt_1d(row)
		for j: int in width:
			out[i * width + j] = d[j]
	return out


## The one-dimensional transform: the lower envelope of the parabolas
## q -> (x - q)² + f(q).
static func edt_1d(f: PackedFloat64Array) -> PackedFloat64Array:
	var n := f.size()
	var d := PackedFloat64Array()
	d.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat64Array()
	z.resize(n + 1)
	var k := 0
	v[0] = 0
	z[0] = -FAR_AWAY
	z[1] = FAR_AWAY
	for q: int in range(1, n):
		var s := 0.0
		while true:
			var p := v[k]
			s = ((f[q] + float(q) * float(q)) - (f[p] + float(p) * float(p))) / (2.0 * float(q) - 2.0 * float(p))
			if s <= z[k]:
				k -= 1
			else:
				break
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = FAR_AWAY
	k = 0
	for q: int in n:
		while z[k + 1] < float(q):
			k += 1
		var p := v[k]
		d[q] = (float(q) - float(p)) * (float(q) - float(p)) + f[p]
	return d


## The nearest node's distance at a point [m] (for the other builders and
## the test): INF outside the lattice.
func distance_at(x: float, z: float) -> float:
	var j := roundi((x - x0) / step)
	var i := roundi((z - z0) / step)
	if j < 0 or j >= cols or i < 0 or i >= rows:
		return INF
	return distance[i * cols + j]


## Whether every node of a tile (its 6 × 6 nodes) is beyond a distance.
func _tile_min_distance(ti: int, tj: int) -> float:
	var cells := int(TILE_M / step)
	var lowest := INF
	for a: int in cells + 1:
		var i := ti * cells + a
		if i >= rows:
			break
		for b: int in cells + 1:
			var j := tj * cells + b
			if j >= cols:
				break
			lowest = minf(lowest, distance[i * cols + j])
	return lowest


# =============================================================================
#  REACH, LANDCOVER, FORMS
# =============================================================================

## 1 where the profile answers a road at the node: the field there is a
## platform or its blend band, not the lattice.
func _compute_reach() -> void:
	reach = PackedByteArray()
	reach.resize(cols * rows)
	for i: int in rows:
		var z := z0 + i * step
		for j: int in cols:
			var found := profile.describe(x0 + j * step, z)
			reach[i * cols + j] = 1 if found.get("road", "") != "" else 0


## The landcover polygons onto the nodes: fields first, forests over them,
## water and rock last (a node is one thing; the later wins). A polygon's
## inner rings are cut out of it before it is written.
func _rasterise_landcover() -> void:
	cover = PackedByteArray()
	cover.resize(cols * rows)
	cover_tint = PackedByteArray()
	cover_tint.resize(cols * rows)
	if landcover.is_empty():
		return
	var t7 := ElementCatalogue.entry("T7")
	var tints := 3
	if not t7.is_empty():
		tints = int(t7.varies.patch_tints.default)
	for record: Variant in landcover.get("fields", []):
		var index := int(floor(hash_unit(int(record.osm), "field_tint") * tints))
		_fill_polygon(record, COVER_FIELD, index)
	for record: Variant in landcover.get("forests", []):
		_fill_polygon(record, COVER_FOREST, 0)
	for record: Variant in landcover.get("rock", []):
		if record.get("kind") == "bare_rock":
			_fill_polygon(record, COVER_ROCK, 0)
	for record: Variant in landcover.get("water", []):
		_fill_polygon(record, COVER_WATER, 0)


## Scanline fill of a polygon record's outer rings, its inner rings taken
## out, onto the node raster: a node is inside when the ray along +x from
## it crosses the rings an odd number of times (all rings together: the
## even-odd rule makes the holes).
func _fill_polygon(record: Dictionary, code: int, tint_index: int) -> void:
	var rings: Array = []
	for ring: Variant in record.get("outer", []):
		rings.append(ring)
	for ring: Variant in record.get("inner", []):
		rings.append(ring)
	if rings.is_empty():
		return
	var z_lo := INF
	var z_hi := -INF
	for ring: Array in rings:
		for point: Array in ring:
			z_lo = minf(z_lo, point[1])
			z_hi = maxf(z_hi, point[1])
	var i_lo := maxi(0, ceili((z_lo - z0) / step))
	var i_hi := mini(rows - 1, floori((z_hi - z0) / step))
	if i_lo > i_hi:
		return
	var crossings := PackedFloat64Array()
	for i: int in range(i_lo, i_hi + 1):
		var z := z0 + i * step
		crossings.resize(0)
		for ring: Array in rings:
			for k: int in range(ring.size() - 1):
				var az: float = ring[k][1]
				var bz: float = ring[k + 1][1]
				if (az <= z) == (bz <= z):
					continue
				var ax: float = ring[k][0]
				var bx: float = ring[k + 1][0]
				crossings.append(ax + (z - az) / (bz - az) * (bx - ax))
		if crossings.size() < 2:
			continue
		crossings.sort()
		for c: int in range(0, crossings.size() - 1, 2):
			var j_lo := maxi(0, ceili((crossings[c] - x0) / step))
			var j_hi := mini(cols - 1, floori((crossings[c + 1] - x0) / step))
			for j: int in range(j_lo, j_hi + 1):
				cover[i * cols + j] = code
				cover_tint[i * cols + j] = tint_index


## The form per node from the slope (central differences), the valley
## rule, and the landcover raster.
func _classify_forms() -> void:
	var n := cols * rows
	form = PackedByteArray()
	form.resize(n)
	slope_pct = PackedFloat32Array()
	slope_pct.resize(n)
	var t1_max := 15.0
	var t3_min := 45.0
	var t1 := ElementCatalogue.entry("T1")
	var t3 := ElementCatalogue.entry("T3")
	if not t1.is_empty():
		t1_max = float(t1.stone_parameters.get("slope_max_pct", t1_max))
	if not t3.is_empty():
		t3_min = float(t3.stone_parameters.get("slope_min_pct", t3_min))
	# The valley window's lowest and highest ground, on a coarse grid (one
	# sample per tile corner) so the window is cheap: a node reads its
	# nearest coarse sample's window.
	var coarse := int(TILE_M / step)
	var cc := (cols - 1) / coarse + 1
	var cr := (rows - 1) / coarse + 1
	var window := int(VALLEY_WINDOW_M / TILE_M / 2.0)
	var low := PackedFloat64Array()
	var high := PackedFloat64Array()
	low.resize(cc * cr)
	high.resize(cc * cr)
	for a: int in cr:
		for b: int in cc:
			var lo := INF
			var hi := -INF
			for da: int in range(-window, window + 1):
				var ia := mini((a + da) * coarse, rows - 1)
				if a + da < 0:
					continue
				for db: int in range(-window, window + 1):
					var jb := mini((b + db) * coarse, cols - 1)
					if b + db < 0:
						continue
					var h := heights[ia * cols + jb]
					lo = minf(lo, h)
					hi = maxf(hi, h)
			low[a * cc + b] = lo
			high[a * cc + b] = hi
	for i: int in rows:
		var i0 := maxi(i - 1, 0)
		var i1 := mini(i + 1, rows - 1)
		for j: int in cols:
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, cols - 1)
			var node := i * cols + j
			var sx := (heights[i * cols + j1] - heights[i * cols + j0]) / (float(j1 - j0) * step)
			var sz := (heights[i1 * cols + j] - heights[i0 * cols + j]) / (float(i1 - i0) * step)
			var s := sqrt(sx * sx + sz * sz) * 100.0
			slope_pct[node] = s
			var kind := FORM_T1
			if s > t3_min:
				kind = FORM_T3
			elif s >= t1_max:
				kind = FORM_T2
			else:
				var a := roundi(float(i) / coarse)
				var b := roundi(float(j) / coarse)
				var c := mini(a, cr - 1) * cc + mini(b, cc - 1)
				if heights[node] - low[c] <= VALLEY_RISE_M and high[c] - low[c] >= VALLEY_RELIEF_M:
					kind = FORM_T4
			if cover[node] == COVER_FIELD and kind != FORM_T3:
				kind = FORM_T7
			elif cover[node] == COVER_FOREST and kind != FORM_T3:
				kind = FORM_V7
			elif cover[node] == COVER_ROCK:
				kind = FORM_T3
			form[node] = kind
	node_colours = PackedColorArray()
	node_colours.resize(n)
	for node: int in n:
		node_colours[node] = _node_colour(node)


## The tint of a node: its form's colour from the palette.
func _node_colour(node: int) -> Color:
	match form[node]:
		FORM_T2:
			return _tint_of("T2", Color(0.33, 0.38, 0.22))
		FORM_T3:
			return _tint_of("T3", Color(0.42, 0.43, 0.45))
		FORM_T4:
			return _tint_of("T4", Color(0.46, 0.52, 0.28))
		FORM_T7:
			return _tint_of(["T7a", "T7b", "T7c"][mini(cover_tint[node], 2)], Color(0.48, 0.47, 0.3))
		FORM_V7:
			return _tint_of("V7", Color(0.12, 0.2, 0.13))
		FORM_T9:
			return _tint_of("T9", Color(0.45, 0.5, 0.55))
	return _tint_of("T1", Color(0.36, 0.44, 0.24))


func _tint_of(name: String, fallback: Color) -> Color:
	if not _tints.has(name):
		_tints[name] = tint(name, fallback)
	return _tints[name]


## The element a form is counted as.
static func _form_element(kind: int) -> String:
	match kind:
		FORM_T2:
			return "T2"
		FORM_T3:
			return "T3"
		FORM_T4:
			return "T4"
		FORM_T7:
			return "T7"
		FORM_V7:
			return "V7"
		FORM_T9:
			return "T9"
	return "T1"


func _count_element(id: String, by: int = 1) -> void:
	elements[id] = elements.get(id, 0) + by


# =============================================================================
#  THE PLAN
# =============================================================================

## The tile classes by the band rule (see the header).
func _plan_tiles() -> void:
	var cells := int(TILE_M / step)
	tile_cols = (cols - 1) / cells
	tile_rows = (rows - 1) / cells
	tile_class = PackedByteArray()
	tile_class.resize(tile_cols * tile_rows)
	var lowest := PackedFloat64Array()
	lowest.resize(tile_cols * tile_rows)
	for ti: int in tile_rows:
		for tj: int in tile_cols:
			var d := _tile_min_distance(ti, tj)
			lowest[ti * tile_cols + tj] = d
			tile_class[ti * tile_cols + tj] = TILE_NEAR if d <= band.near_within else TILE_MID
	var per_block := int(BLOCK_M / TILE_M)
	for bi: int in tile_rows / per_block:
		for bj: int in tile_cols / per_block:
			var far := true
			for a: int in per_block:
				for b: int in per_block:
					var t := (bi * per_block + a) * tile_cols + bj * per_block + b
					far = far and tile_class[t] != TILE_NEAR and lowest[t] > band.mid_to
			if far:
				for a: int in per_block:
					for b: int in per_block:
						tile_class[(bi * per_block + a) * tile_cols + bj * per_block + b] = TILE_FAR
	for t: int in tile_class.size():
		match tile_class[t]:
			TILE_NEAR:
				counts.near_tiles += 1
			TILE_MID:
				counts.mid_tiles += 1
	counts.far_blocks = _far_block_count()


func _far_block_count() -> int:
	var per_block := int(BLOCK_M / TILE_M)
	var blocks := 0
	for bi: int in tile_rows / per_block:
		for bj: int in tile_cols / per_block:
			if tile_class[(bi * per_block) * tile_cols + bj * per_block] == TILE_FAR:
				blocks += 1
	return blocks


## The class of the tile at a point, or 0 outside the plan.
func tile_class_at(x: float, z: float) -> int:
	var tj := floori((x - x0) / TILE_M)
	var ti := floori((z - z0) / TILE_M)
	if tj < 0 or tj >= tile_cols or ti < 0 or ti >= tile_rows:
		return 0
	return tile_class[ti * tile_cols + tj]


# =============================================================================
#  THE MESHES
# =============================================================================

## The near band: per 1 km chunk, every near tile's cells that no road
## reaches, at the lattice's nodes.
func _build_near_band() -> void:
	var cells := int(TILE_M / step)
	var tiles_per_chunk := int(CHUNK_M / TILE_M)
	var chunk_rows := (tile_rows + tiles_per_chunk - 1) / tiles_per_chunk
	var chunk_cols := (tile_cols + tiles_per_chunk - 1) / tiles_per_chunk
	for ci: int in chunk_rows:
		for cj: int in chunk_cols:
			var used := {}
			var vertices := PackedVector3Array()
			var normals := PackedVector3Array()
			var colours := PackedColorArray()
			var indices := PackedInt32Array()
			for ti: int in range(ci * tiles_per_chunk, mini((ci + 1) * tiles_per_chunk, tile_rows)):
				for tj: int in range(cj * tiles_per_chunk, mini((cj + 1) * tiles_per_chunk, tile_cols)):
					if tile_class[ti * tile_cols + tj] != TILE_NEAR:
						continue
					for a: int in cells:
						var i := ti * cells + a
						for b: int in cells:
							var j := tj * cells + b
							var n00 := i * cols + j
							var n01 := n00 + 1
							var n10 := n00 + cols
							var n11 := n10 + 1
							counts.near_cells += 1
							if reach[n00] == 1 or reach[n01] == 1 or reach[n10] == 1 or reach[n11] == 1:
								counts.near_cells_dropped += 1
								continue
							var v00 := _lattice_vertex(used, vertices, normals, colours, n00)
							var v01 := _lattice_vertex(used, vertices, normals, colours, n01)
							var v10 := _lattice_vertex(used, vertices, normals, colours, n10)
							var v11 := _lattice_vertex(used, vertices, normals, colours, n11)
							# Clockwise seen from above (Godot's front face):
							# north-west, north-east, south-east / north-west, south-east, south-west.
							indices.append_array(PackedInt32Array([v00, v01, v11, v00, v11, v10]))
			if indices.is_empty():
				continue
			_add_mesh("Near_%d_%d" % [ci, cj], vertices, normals, colours, indices, _material)


## A lattice node's vertex in a chunk's arrays, appended on first use.
func _lattice_vertex(used: Dictionary, vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, node: int) -> int:
	if used.has(node):
		return used[node]
	var i := node / cols
	var j := node % cols
	var index := vertices.size()
	vertices.append(Vector3(x0 + j * step, heights[node], z0 + i * step))
	normals.append(_lattice_normal(i, j))
	colours.append(node_colours[node])
	_count_element(_form_element(form[node]))
	used[node] = index
	return index


## The lattice's surface normal at a node: central differences.
func _lattice_normal(i: int, j: int) -> Vector3:
	var i0 := maxi(i - 1, 0)
	var i1 := mini(i + 1, rows - 1)
	var j0 := maxi(j - 1, 0)
	var j1 := mini(j + 1, cols - 1)
	var sx := (heights[i * cols + j1] - heights[i * cols + j0]) / (float(j1 - j0) * step)
	var sz := (heights[i1 * cols + j] - heights[i0 * cols + j]) / (float(i1 - i0) * step)
	return Vector3(-sx, 1.0, -sz).normalized()


## The mid band (one quad per mid tile at the tile corners) and the far
## band (one quad per far block), with skirts on every edge that meets a
## finer neighbour.
func _build_mid_and_far() -> void:
	var cells := int(TILE_M / step)
	var per_block := int(BLOCK_M / TILE_M)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var far_vertices := PackedVector3Array()
	var far_normals := PackedVector3Array()
	var far_colours := PackedColorArray()
	var far_indices := PackedInt32Array()
	for ti: int in tile_rows:
		for tj: int in tile_cols:
			var t := ti * tile_cols + tj
			if tile_class[t] != TILE_MID:
				continue
			var corners := [Vector2i(ti * cells, tj * cells), Vector2i(ti * cells, (tj + 1) * cells), Vector2i((ti + 1) * cells, (tj + 1) * cells), Vector2i((ti + 1) * cells, tj * cells)]
			_quad(vertices, normals, colours, indices, corners, false)
			# Skirts where a neighbour is near (finer).
			for side: int in 4:
				var ni: int = ti + [-1, 0, 1, 0][side]
				var nj: int = tj + [0, 1, 0, -1][side]
				if ni < 0 or ni >= tile_rows or nj < 0 or nj >= tile_cols:
					continue
				if tile_class[ni * tile_cols + nj] == TILE_NEAR:
					_skirt(vertices, normals, colours, indices, corners[side], corners[(side + 1) % 4], false)
	for bi: int in tile_rows / per_block:
		for bj: int in tile_cols / per_block:
			if tile_class[(bi * per_block) * tile_cols + bj * per_block] != TILE_FAR:
				continue
			var i_lo := bi * per_block * cells
			var j_lo := bj * per_block * cells
			var i_hi := mini((bi + 1) * per_block * cells, rows - 1)
			var j_hi := mini((bj + 1) * per_block * cells, cols - 1)
			var corners := [Vector2i(i_lo, j_lo), Vector2i(i_lo, j_hi), Vector2i(i_hi, j_hi), Vector2i(i_hi, j_lo)]
			_quad(far_vertices, far_normals, far_colours, far_indices, corners, true)
			for side: int in 4:
				var nbi: int = bi + [-1, 0, 1, 0][side]
				var nbj: int = bj + [0, 1, 0, -1][side]
				if nbi < 0 or nbi >= tile_rows / per_block or nbj < 0 or nbj >= tile_cols / per_block:
					continue
				if tile_class[(nbi * per_block) * tile_cols + nbj * per_block] != TILE_FAR:
					_skirt(far_vertices, far_normals, far_colours, far_indices, corners[side], corners[(side + 1) % 4], true)
	if not indices.is_empty():
		_add_mesh("Mid", vertices, normals, colours, indices, _material)
	if not far_indices.is_empty():
		_add_mesh("Far", far_vertices, far_normals, far_colours, far_indices, _material)


## One quad over four lattice nodes (row, col), clockwise from above.
func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, corners: Array, far: bool) -> void:
	var base := vertices.size()
	for corner: Vector2i in corners:
		var node := corner.x * cols + corner.y
		vertices.append(Vector3(x0 + corner.y * step, heights[node], z0 + corner.x * step))
		normals.append(_lattice_normal(corner.x, corner.y))
		if far:
			colours.append(_tint_of("T9", Color(0.45, 0.5, 0.55)))
			_count_element("T9")
		else:
			colours.append(_node_colour(node))
			_count_element(_form_element(form[node]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


## A vertical skirt under the edge from node a to node b, SKIRT_M down,
## both faces (the material does not cull).
func _skirt(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, a: Vector2i, b: Vector2i, far: bool) -> void:
	var base := vertices.size()
	var na := a.x * cols + a.y
	var nb := b.x * cols + b.y
	var top_a := Vector3(x0 + a.y * step, heights[na], z0 + a.x * step)
	var top_b := Vector3(x0 + b.y * step, heights[nb], z0 + b.x * step)
	var colour_a := _tint_of("T9", Color(0.45, 0.5, 0.55)) if far else _node_colour(na)
	var colour_b := _tint_of("T9", Color(0.45, 0.5, 0.55)) if far else _node_colour(nb)
	var along := (top_b - top_a).normalized()
	var normal := along.cross(Vector3.UP)
	for v: Vector3 in [top_a, top_b, top_b - Vector3(0.0, SKIRT_M, 0.0), top_a - Vector3(0.0, SKIRT_M, 0.0)]:
		vertices.append(v)
		normals.append(normal)
	colours.append_array(PackedColorArray([colour_a, colour_b, colour_b, colour_a]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	counts.skirts += 1


## The platform band: one strip per covered road (see the header).
func _build_strips() -> void:
	var blend := WorldRoadProfile.BLEND_BAND_M
	for ribbon: Ribbon in ribbons:
		var chainages := _strip_chainages(ribbon)
		var hw := ribbon.half_width
		var offsets := PackedFloat64Array([-(hw + blend + APRON_M), -(hw + blend), -hw, hw, hw + blend, hw + blend + APRON_M])
		var undercut := PackedFloat64Array([APRON_UNDERCUT_M, BLEND_UNDERCUT_M, 0.0, 0.0, BLEND_UNDERCUT_M, APRON_UNDERCUT_M])
		var across := offsets.size()
		var vertices := PackedVector3Array()
		var colours := PackedColorArray()
		vertices.resize(chainages.size() * across)
		colours.resize(chainages.size() * across)
		var cursor := 0
		for k: int in chainages.size():
			var s := chainages[k]
			while cursor < ribbon.xs.size() - 2 and ribbon.chain[cursor + 1] <= s + SAME_CHAINAGE_M:
				cursor += 1
			var frame := _frame(ribbon, s, cursor)
			for i: int in across:
				var vertex := Vector3(frame[0] + frame[2] * offsets[i], 0.0, frame[1] + frame[3] * offsets[i])
				vertex.y = profile.elevation_height(vertex.x, vertex.z) - undercut[i]
				vertices[k * across + i] = vertex
				colours[k * across + i] = _colour_at(vertex.x, vertex.z)
			_count_element(_form_element(form[_node_at(frame[0], frame[1])]))
		var indices := PackedInt32Array()
		indices.resize((chainages.size() - 1) * (across - 1) * 6)
		var next := 0
		for k: int in chainages.size() - 1:
			for i: int in across - 1:
				var a := k * across + i
				var b := (k + 1) * across + i
				var c := (k + 1) * across + i + 1
				var d := k * across + i + 1
				indices[next] = a
				indices[next + 1] = b
				indices[next + 2] = c
				indices[next + 3] = a
				indices[next + 4] = c
				indices[next + 5] = d
				next += 6
		var normals := _strip_normals(vertices, chainages.size(), across)
		var mesh := _add_mesh("Band_" + ribbon.id, vertices, normals, colours, indices, _material)
		strips[ribbon.id] = {"chainages": chainages, "offsets": offsets, "mesh": mesh, "vertices": vertices.size()}
		counts.strips += 1
		counts.strip_sections += chainages.size()


## The strip's sections: every station of the platform band's step from 0
## to the length (the end included) and every interior skeleton point,
## sorted, duplicates within SAME_CHAINAGE_M folded.
func _strip_chainages(ribbon: Ribbon) -> PackedFloat64Array:
	var found := PackedFloat64Array()
	for s: float in WorldRoadProfile.station_chainages(ribbon.length, band.platform):
		found.append(s)
	for i: int in range(1, ribbon.chain.size() - 1):
		found.append(ribbon.chain[i])
	found.sort()
	var out := PackedFloat64Array()
	for s: float in found:
		if out.is_empty() or s - out[out.size() - 1] > SAME_CHAINAGE_M:
			out.append(s)
	return out


## The point at chainage s on chord c and the right normal there, mitred
## at a skeleton point (RoadBuilder._frame's rule).
func _frame(ribbon: Ribbon, s: float, c: int) -> PackedFloat64Array:
	var span := ribbon.chain[c + 1] - ribbon.chain[c]
	var u := 0.0 if span <= 0.0 else clampf((s - ribbon.chain[c]) / span, 0.0, 1.0)
	var x := ribbon.xs[c] + u * (ribbon.xs[c + 1] - ribbon.xs[c])
	var z := ribbon.zs[c] + u * (ribbon.zs[c + 1] - ribbon.zs[c])
	var normal := _chord_normal(ribbon, c)
	if c > 0 and absf(s - ribbon.chain[c]) <= SAME_CHAINAGE_M:
		var before := _chord_normal(ribbon, c - 1)
		var mx := before[0] + normal[0]
		var mz := before[1] + normal[1]
		var m := sqrt(mx * mx + mz * mz)
		if m > 1e-9:
			var half_cos := (mx * normal[0] + mz * normal[1]) / m
			var stretch := 1.0 / maxf(half_cos, 1.0 / MAX_MITRE)
			normal = PackedFloat64Array([mx / m * stretch, mz / m * stretch])
	return PackedFloat64Array([x, z, normal[0], normal[1]])


func _chord_normal(ribbon: Ribbon, c: int) -> PackedFloat64Array:
	var k := c
	while k > 0 and ribbon.chain[k + 1] - ribbon.chain[k] <= 0.0:
		k -= 1
	while k + 2 < ribbon.chain.size() and ribbon.chain[k + 1] - ribbon.chain[k] <= 0.0:
		k += 1
	var dx := ribbon.xs[k + 1] - ribbon.xs[k]
	var dz := ribbon.zs[k + 1] - ribbon.zs[k]
	var length := sqrt(dx * dx + dz * dz)
	if length <= 0.0:
		return PackedFloat64Array([1.0, 0.0])
	return PackedFloat64Array([-dz / length, dx / length])


## A strip's normals from its own neighbours (RoadBuilder._add_nodes).
func _strip_normals(vertices: PackedVector3Array, sections: int, across: int) -> PackedVector3Array:
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	for k: int in sections:
		var k0 := maxi(k - 1, 0)
		var k1 := mini(k + 1, sections - 1)
		for i: int in across:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, across - 1)
			var along := vertices[k1 * across + i] - vertices[k0 * across + i]
			var right := vertices[k * across + i1] - vertices[k * across + i0]
			var normal := right.cross(along)
			normals[k * across + i] = normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
	return normals


## The nearest lattice node of a point.
func _node_at(x: float, z: float) -> int:
	var j := clampi(roundi((x - x0) / step), 0, cols - 1)
	var i := clampi(roundi((z - z0) / step), 0, rows - 1)
	return i * cols + j


## The tint at a point: the nearest node's (the strip's vertices are
## counted once per strip, by the nearest node's form, in _build_strips).
func _colour_at(x: float, z: float) -> Color:
	var j := clampi(roundi((x - x0) / step), 0, cols - 1)
	var i := clampi(roundi((z - z0) / step), 0, rows - 1)
	return node_colours[i * cols + j]


## T8: water polygons as flat planes, river and stream ways as strips.
func _build_water() -> void:
	if landcover.is_empty():
		return
	var water_colour := _tint_of("T8", Color(0.32, 0.4, 0.38))
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	for record: Variant in landcover.get("water", []):
		for ring: Array in record.get("outer", []):
			var polygon := PackedVector2Array()
			var lowest := INF
			var inside := false
			for k: int in range(ring.size() - 1):
				var x: float = ring[k][0]
				var z: float = ring[k][1]
				polygon.append(Vector2(x, z))
				if profile.covers(x, z):
					inside = true
					lowest = minf(lowest, profile.terrain_height(x, z))
			if not inside or polygon.size() < 3:
				continue
			var triangles := Geometry2D.triangulate_polygon(polygon)
			if triangles.is_empty():
				continue
			var base := vertices.size()
			for point: Vector2 in polygon:
				vertices.append(Vector3(point.x, lowest + WATER_LIFT_M, point.y))
				normals.append(Vector3.UP)
				colours.append(water_colour)
			for t: int in triangles:
				indices.append(base + t)
			counts.water_planes += 1
			_count_element("T8")
	for record: Variant in landcover.get("waterways", []):
		var half := RIVER_HALF_WIDTH_M if record.get("kind") == "river" else STREAM_HALF_WIDTH_M
		var points: Array = record.get("points", [])
		var line := PackedVector2Array()
		for point: Array in points:
			if profile.covers(point[0], point[1]):
				line.append(Vector2(point[0], point[1]))
			elif line.size() >= 2:
				_waterway_strip(vertices, normals, colours, indices, line, half, water_colour)
				line = PackedVector2Array()
			else:
				line = PackedVector2Array()
		if line.size() >= 2:
			_waterway_strip(vertices, normals, colours, indices, line, half, water_colour)
	if not indices.is_empty():
		_add_mesh("Water", vertices, normals, colours, indices, _water_material)


## A thin strip along a polyline on the lattice, sections at every point
## and every WATERWAY_STEP_M between.
func _waterway_strip(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, line: PackedVector2Array, half: float, colour: Color) -> void:
	var sections := PackedVector2Array()
	for k: int in range(line.size() - 1):
		var a := line[k]
		var b := line[k + 1]
		var pieces := maxi(1, ceili(a.distance_to(b) / WATERWAY_STEP_M))
		for p: int in pieces:
			sections.append(a.lerp(b, float(p) / float(pieces)))
	sections.append(line[line.size() - 1])
	var base := vertices.size()
	for k: int in sections.size():
		var before := sections[maxi(k - 1, 0)]
		var after := sections[mini(k + 1, sections.size() - 1)]
		var along := (after - before)
		var right := Vector2(-along.y, along.x).normalized() if along.length_squared() > 0.0 else Vector2(1.0, 0.0)
		for side: int in 2:
			var point := sections[k] + right * (half if side == 1 else -half)
			vertices.append(Vector3(point.x, profile.terrain_height(point.x, point.y) + WATER_LIFT_M, point.y))
			normals.append(Vector3.UP)
			colours.append(colour)
	for k: int in sections.size() - 1:
		var a := base + k * 2
		indices.append_array(PackedInt32Array([a, a + 2, a + 3, a, a + 3, a + 1]))
	counts.waterway_strips += 1
	_count_element("T8")


## One MeshInstance3D from arrays: vertices, normals, vertex colours,
## indices; no body, no shape.
func _add_mesh(name_of: String, vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, material: StandardMaterial3D) -> MeshInstance3D:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = name_of
	instance.mesh = mesh
	add_child(instance)
	counts.vertices += vertices.size()
	counts.triangles += indices.size() / 3
	return instance


## The one terrain material: the vertex colour as albedo, rough, both
## faces (a skirt is seen from either side; a slope from below at a bridge).
static func _flat_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color.WHITE
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## One line on what was built (no wall time: the same on every machine).
func describe() -> String:
	return "%d near tiles (%d cells, %d dropped under roads), %d mid tiles, %d far blocks, %d skirts, %d strips of %d sections, %d water planes, %d waterway strips, %d vertices, %d triangles" % [counts.near_tiles, counts.near_cells, counts.near_cells_dropped, counts.mid_tiles, counts.far_blocks, counts.skirts, counts.strips, counts.strip_sections, counts.water_planes, counts.waterway_strips, counts.vertices, counts.triangles]
