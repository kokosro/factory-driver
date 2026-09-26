class_name ForestWalls
extends Node3D
## The Ring's vegetation masses (implementation-plan.md §4B-7; element-
## library.md §6; ring-region-decisions.md §5, PUT IN STONE: "landuse=forest
## edges within 60 m of a road are V4 walls 12-18 m, interiors V7 tint"):
## V4 forest wall cards at the forest polygons' edges within the catalogue's
## road distance, V2 conifers (and V1 broadleaves where the polygon says
## broadleaved) sampled along the same edges under the region's density
## ceiling, V6 tree rows at their OSM nodes; the V7 interior is the
## TerrainBuilder's canopy tint on the terrain itself (the library: "the
## interior is never modelled"). Built headless in _ready from the parsed
## landcover the terrain builder holds and the profile the road builder
## handed the car. VISUALS ONLY: no collision shape, no body, no Area3D.
##
## THE WALL (V4, T6): every edge of every forest ring (outer rings, and
## inner rings with the forest on their outside) is walked in CARD_WIDTH_M
## slots (the last slot stretched to the edge's end; an edge shorter than
## a slot is one slot); in each slot one card per layer -
## V4.stone_parameters.layers, 3 - stands LAYER_DEPTH_M further into the
## forest per layer and shifted a third of a card along per layer (V4's
## "staggered"), with a hashed jitter along the edge; its height is drawn
## from V4.height_m ([12, 18]) by the hash; a card is built only when its
## base is within T6.road_distance_max_m (60 m) of a covered road
## centreline, measured EXACTLY against the chords through a cell index
## (never the lattice's rounded distance: the test recomputes the same
## distance by brute force and holds every card to the 60 m). A card is a
## vertical quad along the edge, its base FOOT_SINK_M into the ground (the
## field's height at its centre: on a slope an 8 m card's ends would float
## or sink otherwise), the front layer the palette's spruce blue-green, the
## layers behind darker to "almost black". Both faces (the material does
## not cull): a wall is seen from the road and from the forest track behind.
##
## THE TREES (V2 / V1): "near road" archetypes, sampled along the same
## edges every TREE_SPACING_M (the ceiling's 8 m) one tree's step into the
## forest, V2 unless the polygon's leaf_type is broadleaved (the Eifel
## default is the conifer); a tree beyond the 60 m is never placed (V7:
## "no trees inside beyond 60 m of a road"); a tree within it is charged to
## the nearest road's side, and a (road, side) whose budget - floor(the
## road's length / 8 m) × the table's trees per 8 m - is spent takes no
## more (ring-region-decisions.md §5, DECIDED: "trees within 60 m of the
## road <= 1 per 8 m of road per side"). V6 tree rows: one tree at every
## node of a natural=tree_row way (the library's "V1 at OSM spacing", the
## row's own species where it says needleleaved), under the same budget
## when within the 60 m. Heights from the catalogue's ranges by the hash.
## natural=tree nodes: the landcover's `trees` list, one V1/V2 each, empty
## at this landing (the attic node-tag query was refused by every Overpass
## endpoint on 2026-09-26; landcover.json's header says so). A tree is a
## trunk (two crossed quads) and, V2, three crossed cards ("trunk + 3
## crossed cards"), V1 three lobes of two crossed quads each ("trunk +
## 3-lobe crown"): 10 and 16 triangles, under V1's 120. Flat colours from
## the palette, no texture, no new asset. V3 (the billboard beyond 80 m
## from the camera) is a distance swap this pass does not do: every tree
## is its near archetype at every distance.
##
## DETERMINISM: no RNG; every jitter and height is TerrainBuilder.hash_unit
## of (region seed, the polygon's OSM id, the purpose, the index). The
## edges are walked in the file's order (by OSM id), so the budgets are
## spent the same way every run.

## The elements this node instantiates (ids in the catalogue).
const ELEMENTS := ["V1", "V2", "V4", "V6"]

## A wall card's width along the edge [m] and the layers' step into the
## forest [m] (chosen for the dressing; the library fixes the layers and
## the heights, not the card).
const CARD_WIDTH_M := 8.0
const LAYER_DEPTH_M := 4.0
## How far a card's base sinks into the ground [m].
const FOOT_SINK_M := 1.0
## The jitter of a card along its edge, as a share of the card's width.
const CARD_JITTER := 0.25

## A tree's step into the forest from the edge [m], and its trunk's
## width [m].
const TREE_INSET_M := 1.5
const TRUNK_WIDTH_M := 0.4

## The cell index over the covered chords [m] (a query looks at the 3 × 3
## cells around its own; a chord is filed under every cell its box, grown
## by the wall distance, overlaps: a cell of the wall distance's size is
## enough).
const CELL_M := 60.0
const CHORD_STRIDE := 65536

## A chunk of cards or trees [m]: one MeshInstance3D each for the
## renderer's culling.
const CHUNK_M := 1000.0

@export var road: RoadBuilder
@export var terrain: TerrainBuilder

var profile: WorldRoadProfile
var landcover: Dictionary = {}
var table: Dictionary = {}

## The stone, read from the catalogue at build.
var wall_within_m := 60.0
var layers := 3
var wall_height_m := [12.0, 18.0]
var v2_height_m := [12.0, 25.0]
var v1_height_m := [8.0, 18.0]
var trees_within_m := 60.0
## The region's ceiling: trees per TREE_SPACING_M of road per side.
var trees_per_span := 1
var tree_spacing_m := 8.0

## The covered roads (the terrain builder's ribbons) and the cell index.
var ribbons: Array[TerrainBuilder.Ribbon] = []
var _cells: Dictionary = {}

## Every card: base centre, layer, height, the polygon's OSM id.
var card_x: PackedFloat64Array
var card_z: PackedFloat64Array
var card_layer: PackedByteArray
var card_height: PackedFloat32Array
var card_osm: PackedInt64Array
var card_road_distance: PackedFloat32Array
## The card's edge heading [rad, atan2(ez, ex) in the x-east / z-south
## frame] and its width along the edge [m].
var card_heading: PackedFloat32Array
var card_width: PackedFloat32Array
## Every tree: position, element, height, the source's OSM id, the road
## and side it is charged to ("" / 0 when beyond the 60 m: only V6 rows
## and mapped trees can be there).
var tree_x: PackedFloat64Array
var tree_z: PackedFloat64Array
var tree_element: PackedStringArray
var tree_height: PackedFloat32Array
var tree_osm: PackedInt64Array
var tree_road: PackedStringArray
var tree_side: PackedByteArray
## The budgets: road id -> [left used, right used, allowed per side].
var budgets: Dictionary = {}

var counts := {"forests_walked": 0, "edges": 0, "cards": 0, "cards_skipped_far": 0, "trees": 0, "trees_v1": 0, "trees_v2": 0, "trees_rows": 0, "trees_skipped_far": 0, "trees_skipped_budget": 0, "vertices": 0, "triangles": 0}
var elements: Dictionary = {}
var build_ms := 0
var _material: StandardMaterial3D
var _wall_colours: Array[Color] = []
var _v2_colour: Color
var _v1_colour: Color
var _trunk_colour: Color


func _ready() -> void:
	if terrain == null or terrain.profile == null:
		push_error("ForestWalls: no terrain builder to read the profile and the landcover from")
		return
	build(terrain.profile, terrain.landcover, terrain.ribbons)


## Builds the walls and the trees from the profile (heights), the parsed
## landcover and the covered roads.
func build(built_profile: WorldRoadProfile, landcover_data: Dictionary, roads: Array[TerrainBuilder.Ribbon]) -> void:
	var started := Time.get_ticks_msec()
	profile = built_profile
	landcover = landcover_data
	ribbons = roads
	table = TerrainBuilder.region_dressing()
	_read_stone()
	_read_palette()
	_material = TerrainBuilder._flat_material()
	_build_cells()
	_reset_lists()
	for ribbon: TerrainBuilder.Ribbon in ribbons:
		budgets[ribbon.id] = [0, 0, int(floor(ribbon.length / tree_spacing_m)) * trees_per_span]
	_walk_forests()
	_place_tree_rows()
	_place_mapped_trees()
	_build_meshes()
	build_ms = Time.get_ticks_msec() - started


func _read_stone() -> void:
	var t6 := ElementCatalogue.entry("T6")
	var v4 := ElementCatalogue.entry("V4")
	var v2 := ElementCatalogue.entry("V2")
	var v1 := ElementCatalogue.entry("V1")
	var v7 := ElementCatalogue.entry("V7")
	if not t6.is_empty():
		wall_within_m = float(t6.stone_parameters.get("road_distance_max_m", wall_within_m))
	if not v4.is_empty():
		layers = int(v4.stone_parameters.get("layers", layers))
		wall_height_m = [float(v4.stone_parameters.height_m[0]), float(v4.stone_parameters.height_m[1])]
	if not v2.is_empty():
		v2_height_m = [float(v2.varies.height_m.range[0]), float(v2.varies.height_m.range[1])]
	if not v1.is_empty():
		v1_height_m = [float(v1.varies.height_m.range[0]), float(v1.varies.height_m.range[1])]
	if not v7.is_empty():
		trees_within_m = float(v7.stone_parameters.get("trees_within_m", trees_within_m))
	var density: Variant = table.get("density", {})
	if density is Dictionary and density.has("trees_within_60_m_per_8_m_per_side"):
		trees_per_span = int(density.trees_within_60_m_per_8_m_per_side)


func _read_palette() -> void:
	_wall_colours = [
		TerrainBuilder.tint("V4_front", Color(0.16, 0.26, 0.2)),
		TerrainBuilder.tint("V4_middle", Color(0.11, 0.19, 0.15)),
		TerrainBuilder.tint("V4_back", Color(0.07, 0.12, 0.1)),
	]
	_v2_colour = TerrainBuilder.tint("V2", Color(0.15, 0.25, 0.19))
	_v1_colour = TerrainBuilder.tint("V1", Color(0.2, 0.3, 0.14))
	_trunk_colour = TerrainBuilder.tint("trunk", Color(0.25, 0.2, 0.15))


func _reset_lists() -> void:
	card_x = PackedFloat64Array()
	card_z = PackedFloat64Array()
	card_layer = PackedByteArray()
	card_height = PackedFloat32Array()
	card_osm = PackedInt64Array()
	card_road_distance = PackedFloat32Array()
	card_heading = PackedFloat32Array()
	card_width = PackedFloat32Array()
	tree_x = PackedFloat64Array()
	tree_z = PackedFloat64Array()
	tree_element = PackedStringArray()
	tree_height = PackedFloat32Array()
	tree_osm = PackedInt64Array()
	tree_road = PackedStringArray()
	tree_side = PackedByteArray()
	budgets = {}


# =============================================================================
#  THE ROAD DISTANCE
# =============================================================================

func _build_cells() -> void:
	_cells = {}
	var reach := maxf(wall_within_m, trees_within_m)
	for r: int in ribbons.size():
		var ribbon := ribbons[r]
		for c: int in range(ribbon.xs.size() - 1):
			var x_lo := minf(ribbon.xs[c], ribbon.xs[c + 1]) - reach
			var x_hi := maxf(ribbon.xs[c], ribbon.xs[c + 1]) + reach
			var z_lo := minf(ribbon.zs[c], ribbon.zs[c + 1]) - reach
			var z_hi := maxf(ribbon.zs[c], ribbon.zs[c + 1]) + reach
			var packed := r * CHORD_STRIDE + c
			for i: int in range(floori(z_lo / CELL_M), floori(z_hi / CELL_M) + 1):
				for j: int in range(floori(x_lo / CELL_M), floori(x_hi / CELL_M) + 1):
					var key := Vector2i(j, i)
					if not _cells.has(key):
						_cells[key] = []
					_cells[key].append(packed)


## The nearest covered road within `limit` of (x, z): {distance, road (the
## ribbon's id), side (1 right of travel, 0 left)}; empty when none.
func nearest_road(x: float, z: float, limit: float) -> Dictionary:
	var key := Vector2i(floori(x / CELL_M), floori(z / CELL_M))
	if not _cells.has(key):
		return {}
	var best_distance := INF
	var best := {}
	for packed: int in _cells[key]:
		var r := packed / CHORD_STRIDE
		var c := packed % CHORD_STRIDE
		var ribbon := ribbons[r]
		var ax := ribbon.xs[c]
		var az := ribbon.zs[c]
		var dx := ribbon.xs[c + 1] - ax
		var dz := ribbon.zs[c + 1] - az
		var chord := ribbon.chain[c + 1] - ribbon.chain[c]
		if chord <= 0.0:
			continue
		var t := clampf(((x - ax) * dx + (z - az) * dz) / (chord * chord), 0.0, 1.0)
		var cx := ax + t * dx
		var cz := az + t * dz
		var d := sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz))
		if d <= limit and d < best_distance:
			best_distance = d
			var offset := ((x - ax) * (-dz) + (z - az) * dx) / chord
			best = {"distance": d, "road": ribbon.id, "side": 1 if offset >= 0.0 else 0}
	return best


# =============================================================================
#  THE WALK
# =============================================================================

func _walk_forests() -> void:
	for record: Variant in landcover.get("forests", []):
		if not record is Dictionary:
			continue
		var osm := int(record.osm)
		var broadleaved: bool = record.get("leaf_type", "") == "broadleaved"
		counts.forests_walked += 1
		var index := 0
		for ring: Array in record.get("outer", []):
			index = _walk_ring(ring, osm, broadleaved, 1.0, index)
		for ring: Array in record.get("inner", []):
			index = _walk_ring(ring, osm, broadleaved, -1.0, index)


## One ring's edges: the cards and the trees along each. `forest_side` is
## +1 when the forest is inside the ring, -1 for a hole. Returns the next
## card index (the hash's).
func _walk_ring(ring: Array, osm: int, broadleaved: bool, forest_side: float, index: int) -> int:
	var area := 0.0
	for k: int in range(ring.size() - 1):
		area += ring[k][0] * ring[k + 1][1] - ring[k + 1][0] * ring[k][1]
	var inward_sign := (1.0 if area > 0.0 else -1.0) * forest_side
	for k: int in range(ring.size() - 1):
		var ax: float = ring[k][0]
		var az: float = ring[k][1]
		var bx: float = ring[k + 1][0]
		var bz: float = ring[k + 1][1]
		var dx := bx - ax
		var dz := bz - az
		var length := sqrt(dx * dx + dz * dz)
		if length < 0.5:
			continue
		counts.edges += 1
		var ex := dx / length
		var ez := dz / length
		var nx := -ez * inward_sign
		var nz := ex * inward_sign
		# Only an edge that comes near a road can hold a card: a cheap
		# rejection through the lattice's distance before the exact test.
		if terrain != null and terrain.distance_at(ax, az) > wall_within_m + length + terrain.step and terrain.distance_at(bx, bz) > wall_within_m + length + terrain.step:
			continue
		var slots := maxi(1, ceili(length / CARD_WIDTH_M))
		var width := length / slots
		for slot: int in slots:
			for layer: int in layers:
				var jitter := (TerrainBuilder.hash_unit(osm, "card_jitter", index) - 0.5) * CARD_JITTER * width
				var along := (float(slot) + 0.5 + float(layer) / float(layers)) * width + jitter
				along = clampf(along, width * 0.5, length - width * 0.5)
				var depth := float(layer) * LAYER_DEPTH_M
				var x := ax + ex * along + nx * depth
				var z := az + ez * along + nz * depth
				var found := nearest_road(x, z, wall_within_m)
				if found.is_empty() or not profile.covers(x, z):
					counts.cards_skipped_far += 1
					index += 1
					continue
				var height := lerpf(wall_height_m[0], wall_height_m[1], TerrainBuilder.hash_unit(osm, "card_height", index))
				card_x.append(x)
				card_z.append(z)
				card_layer.append(layer)
				card_height.append(height)
				card_osm.append(osm)
				card_road_distance.append(found.distance)
				card_heading.append(atan2(ez, ex))
				card_width.append(width)
				counts.cards += 1
				index += 1
		# The trees along the edge, one step into the forest.
		var trees := maxi(1, floori(length / tree_spacing_m))
		var tree_gap := length / trees
		for t: int in trees:
			var along := (float(t) + 0.5) * tree_gap + (TerrainBuilder.hash_unit(osm, "tree_jitter", index) - 0.5) * tree_gap * 0.5
			var x := ax + ex * along + nx * TREE_INSET_M
			var z := az + ez * along + nz * TREE_INSET_M
			_place_tree(x, z, "V1" if broadleaved else "V2", osm, index, true)
			index += 1
	return index


## A tree at (x, z) if the ceiling allows: within the 60 m it is charged to
## the nearest road's side; beyond it only a mapped tree or a row's
## (`edge_sampled` false) may stand. Returns whether it was placed.
func _place_tree(x: float, z: float, element: String, osm: int, index: int, edge_sampled: bool) -> bool:
	if not profile.covers(x, z):
		return false
	var found := nearest_road(x, z, trees_within_m)
	var road_id := ""
	var side := 0
	if found.is_empty():
		if edge_sampled:
			counts.trees_skipped_far += 1
			return false
	else:
		road_id = found.road
		side = found.side
		var budget: Array = budgets.get(road_id, [0, 0, 0])
		if budget[side] >= budget[2]:
			counts.trees_skipped_budget += 1
			return false
		budget[side] += 1
		budgets[road_id] = budget
	var range_of: Array = v1_height_m if element == "V1" else v2_height_m
	var height := lerpf(range_of[0], range_of[1], TerrainBuilder.hash_unit(osm, "tree_height", index))
	tree_x.append(x)
	tree_z.append(z)
	tree_element.append(element)
	tree_height.append(height)
	tree_osm.append(osm)
	tree_road.append(road_id)
	tree_side.append(side)
	counts.trees += 1
	if element == "V1":
		counts.trees_v1 += 1
	else:
		counts.trees_v2 += 1
	return true


## V6: one tree at every node of a tree row, the row's species.
func _place_tree_rows() -> void:
	for record: Variant in landcover.get("tree_rows", []):
		if not record is Dictionary:
			continue
		var osm := int(record.osm)
		var element := "V2" if record.get("leaf_type", "") == "needleleaved" else "V1"
		var points: Array = record.get("points", [])
		for k: int in points.size():
			if _place_tree(float(points[k][0]), float(points[k][1]), element, osm, k, false):
				counts.trees_rows += 1
				_count_element("V6")


## natural=tree nodes, one each (empty at this landing: see the header).
func _place_mapped_trees() -> void:
	for record: Variant in landcover.get("trees", []):
		if not record is Dictionary:
			continue
		_place_tree(float(record.x), float(record.z), "V1" if record.get("leaf_type", "") == "broadleaved" else "V2", int(record.osm), 0, false)


func _count_element(id: String, by: int = 1) -> void:
	elements[id] = elements.get(id, 0) + by


# =============================================================================
#  THE MESHES
# =============================================================================

func _build_meshes() -> void:
	var wall_chunks := {}
	for i: int in card_x.size():
		var key := Vector2i(floori(card_x[i] / CHUNK_M), floori(card_z[i] / CHUNK_M))
		if not wall_chunks.has(key):
			wall_chunks[key] = PackedInt32Array()
		wall_chunks[key].append(i)
	for key: Vector2i in wall_chunks:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		for i: int in wall_chunks[key]:
			_card_quad(vertices, normals, colours, indices, i)
		_add_mesh("Walls_%d_%d" % [key.x, key.y], vertices, normals, colours, indices)
	_count_element("V4", card_x.size())
	var tree_chunks := {}
	for i: int in tree_x.size():
		var key := Vector2i(floori(tree_x[i] / CHUNK_M), floori(tree_z[i] / CHUNK_M))
		if not tree_chunks.has(key):
			tree_chunks[key] = PackedInt32Array()
		tree_chunks[key].append(i)
	for key: Vector2i in tree_chunks:
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var colours := PackedColorArray()
		var indices := PackedInt32Array()
		for i: int in tree_chunks[key]:
			_tree(vertices, normals, colours, indices, i)
		_add_mesh("Trees_%d_%d" % [key.x, key.y], vertices, normals, colours, indices)
	_count_element("V1", counts.trees_v1)
	_count_element("V2", counts.trees_v2)


## A card: a vertical quad along its edge's heading, FOOT_SINK_M into the
## ground at its centre, its layer's colour.
func _card_quad(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, i: int) -> void:
	var heading := card_heading[i]
	var ex := cos(heading)
	var ez := sin(heading)
	var half := card_width[i] * 0.5
	var x := card_x[i]
	var z := card_z[i]
	var base := profile.elevation_height(x, z) - FOOT_SINK_M
	var top := base + card_height[i]
	var colour := _wall_colours[mini(card_layer[i], _wall_colours.size() - 1)]
	var normal := Vector3(-ez, 0.0, ex)
	_quad(vertices, normals, colours, indices, Vector3(x - ex * half, base, z - ez * half), Vector3(x + ex * half, base, z + ez * half), Vector3(x + ex * half, top, z + ez * half), Vector3(x - ex * half, top, z - ez * half), normal, colour)


## A tree: the trunk's two crossed quads, then V2's three crossed cards
## or V1's three lobes of two crossed quads.
func _tree(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, i: int) -> void:
	var x := tree_x[i]
	var z := tree_z[i]
	var h := tree_height[i]
	var base := profile.elevation_height(x, z) - 0.2
	var conifer := tree_element[i] == "V2"
	var trunk_top := base + (0.35 if conifer else 0.45) * h
	_crossed(vertices, normals, colours, indices, Vector3(x, base, z), TRUNK_WIDTH_M, trunk_top - base, 0.0, _trunk_colour, 2)
	if conifer:
		_crossed(vertices, normals, colours, indices, Vector3(x, base + 0.2 * h, z), 0.4 * h, 0.8 * h, 0.0, _v2_colour, 3)
	else:
		var lobe := 0.45 * h
		var crown := base + 0.4 * h
		_crossed(vertices, normals, colours, indices, Vector3(x, crown + 0.2 * h, z), lobe, lobe, 0.0, _v1_colour, 2)
		_crossed(vertices, normals, colours, indices, Vector3(x - 0.18 * h, crown, z), lobe, lobe, PI / 3.0, _v1_colour, 2)
		_crossed(vertices, normals, colours, indices, Vector3(x + 0.18 * h, crown, z), lobe, lobe, -PI / 3.0, _v1_colour, 2)


## `cards` vertical quads of one width and height crossed at a base point,
## turned `turn` and then evenly around.
func _crossed(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, at: Vector3, width: float, height: float, turn: float, colour: Color, cards: int) -> void:
	for c: int in cards:
		var heading := turn + PI * float(c) / float(cards)
		var ex := cos(heading) * width * 0.5
		var ez := sin(heading) * width * 0.5
		var normal := Vector3(-sin(heading), 0.0, cos(heading))
		_quad(vertices, normals, colours, indices, Vector3(at.x - ex, at.y, at.z - ez), Vector3(at.x + ex, at.y, at.z + ez), Vector3(at.x + ex, at.y + height, at.z + ez), Vector3(at.x - ex, at.y + height, at.z - ez), normal, colour)


func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, colour: Color) -> void:
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	normals.append_array(PackedVector3Array([normal, normal, normal, normal]))
	colours.append_array(PackedColorArray([colour, colour, colour, colour]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _add_mesh(name_of: String, vertices: PackedVector3Array, normals: PackedVector3Array, colours: PackedColorArray, indices: PackedInt32Array) -> void:
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	var instance := MeshInstance3D.new()
	instance.name = name_of
	instance.mesh = mesh
	add_child(instance)
	counts.vertices += vertices.size()
	counts.triangles += indices.size() / 3


## One line on what was built (no wall time).
func describe() -> String:
	return "%d forests walked, %d edges, %d cards (%d beyond the %.0f m), %d trees (%d V1, %d V2, %d in rows; %d beyond the %.0f m, %d over the budget), %d vertices, %d triangles" % [counts.forests_walked, counts.edges, counts.cards, counts.cards_skipped_far, wall_within_m, counts.trees, counts.trees_v1, counts.trees_v2, counts.trees_rows, counts.trees_skipped_far, trees_within_m, counts.trees_skipped_budget, counts.vertices, counts.triangles]
