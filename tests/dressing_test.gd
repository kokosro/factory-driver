extends SceneTree
## Headless dressing test (implementation-plan.md §4B-7): the Ring's first
## dressing pass - terrain forms (T), forest masses (V) and the sky and
## haze (S) - held to the canon's tables through the catalogue and the
## region file. THE LANDCOVER FILE (data/regions/eifel_ring/landcover.json,
## tools/world/landcover.py): read the way TerrainBuilder reads it, passes
## validate_landcover(); its header pinned to the snapshot and the
## skeleton's query chain; its fetch record the honest one - the pinned
## q4_landcover.ql's sha256 recomputed from the query text (verbatim here),
## the six selectors fetched in parts on 2026-09-26 because every Overpass
## endpoint refused the query whole (the refusal cited in the header), each
## part's query rebuilt from its selector and hashed to the header's
## query_sha256, the folded answer_sha256 recomputed from the parts', the
## trees part recorded missing with its refusal; the raw files hashed to
## the header where the snapshot store is on this machine; the projection
## samples in the header reproduced by SkeletonLoader.wgs84_to_local within
## the millimetre (the python port and the loader agree). THE REGION TABLE:
## dressing.json beside focus.json (the buildings test pins focus.json's
## four top keys, so the dressing choices are a file of their own)
## validates, names S1 / S5, and every tint is under the canon's luminance
## cap; focus.json is untouched and still validates. THE CATALOGUE: every element the three
## builders instantiate is an id in ElementCatalogue of the right family,
## and nothing outside their declared lists is instantiated. THE SCENE
## (scenes/eifel_ring.tscn, loaded as the ring drive test loads it): the
## three nodes build; NO PHYSICS - not one CollisionObject3D, CollisionShape3D
## or Area3D under them, every child a MeshInstance3D. THE LATTICE PLAN: the
## bands read from the catalogue (2 / 10 / 50 / 200 m, 200 m, 2 km) are
## the builder's; every near-band vertex sits on a lattice node (x and z
## multiples of the 10 m step from the origin, y the node's own height),
## every mid vertex on a 50 m corner; a near tile has a node within 200 m
## of a road and a mid tile none, on the builder's distance field; and the
## distance field itself is held to a brute-force point-to-chord distance
## at a sample of tiles' nearest nodes within half a lattice step's
## diagonal; the platform strips stand at every 2 m station and every
## skeleton point with no gap over 2 m, their offsets the paved edge, the
## blend band's end and the apron. THE WALLS: every one of the ~79 000 V4
## cards is within 60 m of a covered road on the builder's own distance,
## and a sample every 400th card is within 60 m by brute force over every
## chord; every card's polygon is a forest of the landcover; no edge-
## sampled tree stands beyond the 60 m. THE CEILING: per road and side the
## trees charged to it are at most floor(length / 8 m), recounted from the
## tree list; at 10 points along the Nordschleife (every ninth loop
## segment's first point) the trees within 500 m are under the §5 ceiling
## (2 sides × the covered road length inside the disc / 8 m) and the
## MEANINGFUL objects within 500 m - the forests with a card in the disc,
## the water planes with a vertex in it, the tree rows with a tree in it:
## the masses, not the cards - are at most the region table's twenty
## (ring-region-decisions.md §5, "the canon's 'twenty meaningful objects'
## is the audit"; the number held is the table's
## meaningful_objects_within_500_m = 20; measured 2-8 forests per disc).
## THE AUTHORED ASSETS (4B-ASSETS-1, assets/blender/README.md; the driver's
## issue-0023): the three tree archetypes load from their .glb into the
## forest builder with a bark and a foliage surface, 100-500 triangles
## each, their foliage UVs inside the atlas; the four materials are the
## authored textures (the wall's and the foliage's alpha-scissored and
## double-sided, the bark's opaque), every one multiplying the vertex
## colour; every surface of every chunk carries UVs and one of the four;
## the vertex and triangle counts are the exact accounting of cards x 4 /
## x 2 plus every tree's archetype; a tree's transform is its hashed yaw
## and its height over the archetype's, its shade in [0.8, 1]; a V1 in a
## row wears the row tree; sampled vertex colours stay under the luminance
## cap; the asphalt set (road_asphalt_1024_*) is 1024², greyscale-neutral,
## the ruts darker and smoother than the lane centres and mirrored about
## u 0.5, the shoulders darker still, the tile seamless along the road;
## the vegetation textures greyscale-neutral with their alpha (the wall's
## top row open sky, its foot solid). The suite never runs Blender: the
## PNG / .glb files are checked in; regeneration is the README's command.
## THE HAZE: the environment's fog is depth fog (not volumetric), begins
## at S5's normal_saturation_to_m, its colour the sky material's horizon;
## the four-band curve sampled at 50 / 200 / 500 / 1 000 m falls in the
## catalogue's four bands in order, is 0 / 0.15 / 0.45 at the band ends,
## and the engine's one-exponent curve (the depth mode's formula, mirrored)
## is within FIT_TOLERANCE of it at every sample; one sun at S1's 45° and
## the table's bearing. DETERMINISM: the scene built twice describes
## itself the same and places the same cards. No network, no python, no
## wall clock in a check. Exits 0 on success, 1 on any fault.

const RING_SCENE := "res://scenes/eifel_ring.tscn"
const SETTLE_FRAMES := 20

## The pinned snapshot (ring-region-decisions.md §1), its own literal.
const PINNED_OSM_BASE := "2026-09-22T08:45:51Z"

## The pinned q4_landcover query (tools/world/extract_osm.py, verbatim):
## what the header's query_sha256 has to be the sha256 of.
const Q4_QUERY := '[out:json][timeout:300][bbox:50.30,6.80,50.45,7.10][date:"2026-09-22T08:45:51Z"];\n(\n  way["landuse"~"^(forest|farmland|meadow|grass|residential|industrial)$"];\n  relation["landuse"~"^(forest|farmland|meadow)$"];\n  way["natural"~"^(wood|water|scrub|heath|cliff|bare_rock|tree_row)$"];\n  node["natural"="tree"];\n  way["waterway"~"^(river|stream|riverbank)$"];\n  way["place"~"^(village|town)$"]; node["place"~"^(village|town|hamlet)$"];\n);\nout geom;\n'
## A part's query as extract_landcover_parts.py writes it: the settings
## line, the selector in a union block, out geom.
const PART_SETTINGS := '[out:json][timeout:300][bbox:50.30,6.80,50.45,7.10][date:"2026-09-22T08:45:51Z"];\n'
## The six selectors, in part order; the fourth was refused.
const PART_NAMES := ["q4_landcover_part1_landuse_ways", "q4_landcover_part2_landuse_relations", "q4_landcover_part3_natural_ways", "q4_landcover_part4_trees", "q4_landcover_part5_waterways", "q4_landcover_part6_places"]
const REFUSED_PART := "q4_landcover_part4_trees"

## The lattice table (element-library.md §2; the catalogue's T1) [m].
const PLATFORM_M := 2.0
const NEAR_M := 10.0
const NEAR_WITHIN_M := 200.0
const MID_M := 50.0
const MID_TO_M := 2000.0
const FAR_M := 200.0
## The distance field's tolerance: the roads are rasterised onto the
## nearest nodes, half a step's diagonal at most.
const DISTANCE_TOLERANCE_M := 7.1
## Sampling strides (deterministic): tiles for the brute-force distance,
## cards for the brute-force 60 m.
const TILE_SAMPLE_STRIDE := 401
const CARD_SAMPLE_STRIDE := 400

## The forest rule and the ceilings (ring-region-decisions.md §5).
const WALL_WITHIN_M := 60.0
const TREE_SPAN_M := 8.0
const AUDIT_RADIUS_M := 500.0
const LOOP_SAMPLES := 10
const MEANINGFUL_CEILING := 20

## The haze bands (the catalogue's S5) and the sample distances.
const BAND_ENDS_M := [100.0, 300.0, 800.0]
const HAZE_SAMPLES_M := [50.0, 200.0, 500.0, 1000.0]
const BAND_NAMES := ["normal saturation", "slight haze", "reduced contrast", "increasingly sky-coloured"]

## The sun (S1 varies default, the table's bearing).
const SUN_ELEVATION_DEG := 45.0
const SUN_AZIMUTH_DEG := 210.0

## The authored assets (assets/blender/README.md): the archetype triangle
## band, the texture sizes, the asphalt tile's rut / lane-centre / shoulder
## columns in u and the pixel stride of the neutrality sample.
const ARCHETYPE_TRIANGLES := [100, 500]
const ASPHALT_SIZE := 1024
const CARD_TEXTURE_SIZE := 512
const BARK_TEXTURE_SIZE := 256
const ASPHALT_DIR := "res://assets/textures/road/"
const VEGETATION_DIR := "res://assets/textures/vegetation/"
const RUT_U := [0.13, 0.37, 0.63, 0.87]
const LANE_CENTRE_U := [0.25, 0.75]
const SHOULDER_U := 0.01
const PIXEL_STRIDE := 37

var _failures := 0
var _loop: SkeletonLoader.Loop


func _initialize() -> void:
	var landcover: Variant = TerrainBuilder.read_landcover()
	_check_landcover_file(landcover)
	_check_region_table()
	_check_catalogue()
	_check_authored_textures()
	_loop = SkeletonLoader.loop(SkeletonLoader.NORDSCHLEIFE_LOOP)
	var scene := await _load_scene()
	if scene != null:
		var terrain: TerrainBuilder = scene.get_node("Terrain")
		var forest: ForestWalls = scene.get_node("Forest")
		var sky: SkySet = scene.get_node("Sky")
		var road: RoadBuilder = scene.get_node("Road")
		_check_scene(scene, terrain, forest, sky, road)
		_check_no_physics(terrain, forest)
		_check_lattice_plan(terrain)
		_check_strips(terrain)
		_check_walls(terrain, forest, landcover)
		_check_assets(forest)
		_check_ceiling(terrain, forest)
		_check_haze(scene, sky)
		_check_elements(terrain, forest, sky)
		var first := "%s | %s | %s" % [terrain.describe(), forest.describe(), sky.describe()]
		var first_cards := forest.card_x.size()
		var first_card := Vector2(forest.card_x[first_cards - 1], forest.card_z[first_cards - 1]) if first_cards > 0 else Vector2.ZERO
		var first_tree := forest.tree_transform(forest.tree_x.size() - 1) if forest.tree_x.size() > 0 else Transform3D.IDENTITY
		scene.queue_free()
		await _step(2)
		var again := await _load_scene()
		if again != null:
			var terrain2: TerrainBuilder = again.get_node("Terrain")
			var forest2: ForestWalls = again.get_node("Forest")
			var sky2: SkySet = again.get_node("Sky")
			var second := "%s | %s | %s" % [terrain2.describe(), forest2.describe(), sky2.describe()]
			var second_card := Vector2(forest2.card_x[forest2.card_x.size() - 1], forest2.card_z[forest2.card_z.size() - 1]) if forest2.card_x.size() > 0 else Vector2.ZERO
			var second_tree := forest2.tree_transform(forest2.tree_x.size() - 1) if forest2.tree_x.size() > 0 else Transform3D.IDENTITY
			_ok(first == second and first_card == second_card and first_tree == second_tree, "determinism: the scene built twice describes itself the same (%s), places its last card at the same point (%s) and stands its last tree in the same transform (was -> the card alone; the tree's hashed yaw and scale since 4B-ASSETS-1)" % [second, second_card], "first: %s / %s / %s, second: %s / %s / %s" % [first, first_card, first_tree, second, second_card, second_tree])
			again.queue_free()
			await _step(2)
	print("DRESSING TEST PASSED" if _failures == 0 else "DRESSING TEST FAILED: %d fault(s)" % _failures)
	quit(0 if _failures == 0 else 1)


## An ok line or a FAIL line, counted.
func _ok(condition: bool, what: String, reason: String = "") -> void:
	if condition:
		print("  ok    ", what)
	else:
		_failures += 1
		printerr("  FAIL  ", reason if reason != "" else what)


func _step(frames: int) -> void:
	for i: int in frames:
		await physics_frame


func _load_scene() -> Node:
	var packed: PackedScene = load(RING_SCENE)
	if packed == null:
		_ok(false, "", "the ring scene does not load")
		return null
	await physics_frame
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	return scene


# =============================================================================
#  THE LANDCOVER FILE
# =============================================================================

func _check_landcover_file(data: Variant) -> void:
	_ok(FileAccess.file_exists(TerrainBuilder.LANDCOVER_PATH), "the landcover is checked in at %s" % TerrainBuilder.LANDCOVER_PATH)
	_ok(data is Dictionary, "the landcover parses as a JSON object")
	if not data is Dictionary:
		return
	var errors := TerrainBuilder.validate_landcover(data)
	_ok(errors.is_empty(), "the landcover passes TerrainBuilder.validate_landcover() with nothing to say", "validate_landcover says %s" % [errors])
	var skeleton: Variant = SkeletonLoader.read_file()
	var query_sha: String = skeleton.snapshot.query_sha if skeleton is Dictionary else ""
	_ok(data.snapshot.osm_base == PINNED_OSM_BASE and data.snapshot.query_sha == query_sha and data.pipeline_version == TerrainBuilder.LANDCOVER_PIPELINE_VERSION, "snapshot pinned: osm_base %s, query_sha the skeleton's %s, pipeline version %d" % [data.snapshot.osm_base, query_sha.substr(0, 8), data.pipeline_version], "snapshot %s, version %s" % [data.snapshot, data.pipeline_version])
	_ok(data.counts.forests > 1000 and data.counts.fields > 1000 and data.counts.water > 50 and data.counts.waterways > 500 and data.counts.tree_rows > 10, "the file holds the bbox's landcover: %s" % [data.counts], "counts %s" % [data.counts])
	# The fetch record and its chain.
	var fetch: Dictionary = data.provenance.fetch
	var q4_sha := _sha256_of(Q4_QUERY.to_utf8_buffer())
	_ok(fetch.query_file == "q4_landcover.ql" and fetch.query_sha256 == q4_sha, "provenance.fetch.query_sha256 %s is the sha256 of the pinned q4_landcover.ql text (verbatim here, %d bytes)" % [fetch.query_sha256.substr(0, 12), Q4_QUERY.to_utf8_buffer().size()], "query_sha256 %s, the query text hashes to %s" % [fetch.query_sha256, q4_sha])
	_ok(fetch.get("refused", "").contains("refused by every endpoint on 2026-09-26") and fetch.refused.contains("out of memory"), "the header says the pinned query was refused whole and why (memory on the servers)", "refused: %s" % fetch.get("refused"))
	var parts: Array = fetch.get("parts", [])
	var parts_ok := parts.size() == 5
	var joined := ""
	var elements := 0
	var seen := []
	for part: Dictionary in parts:
		var text := PART_SETTINGS + "(\n  " + String(part.selector).replace("; ", ";\n  ") + "\n);\nout geom;\n"
		var sha := _sha256_of(text.to_utf8_buffer())
		var in_q4 := true
		for piece: String in String(part.selector).split("; "):
			in_q4 = in_q4 and Q4_QUERY.contains(piece if piece.ends_with(";") else piece + ";")
		parts_ok = parts_ok and sha == part.query_sha256 and in_q4 and part.served_timestamp_osm_base >= PINNED_OSM_BASE and _is_sha(part.answer_sha256) and part.answer_elements > 0 and part.part in PART_NAMES
		joined += part.answer_sha256
		elements += part.answer_elements
		seen.append(part.part)
	_ok(parts_ok, "the five fetched parts: each selector verbatim in q4, its query rebuilt and hashed to the part's query_sha256, served at or past the attic date: %s" % [seen], "parts: %s" % [parts])
	var folded := _sha256_of(joined.to_utf8_buffer())
	_ok(fetch.answer_sha256 == folded and fetch.answer_elements <= elements and fetch.answer_elements > 5000, "the folded answer_sha256 %s is the sha256 of the parts' shas in order; %d elements folded from %d (an element in two parts once)" % [folded.substr(0, 12), fetch.answer_elements, elements], "answer_sha256 %s vs %s, elements %d of %d" % [fetch.answer_sha256, folded, fetch.answer_elements, elements])
	var missing: Array = fetch.get("parts_missing", [])
	_ok(missing.size() == 1 and missing[0].part == REFUSED_PART and String(missing[0].selector).contains('node["natural"="tree"]') and String(missing[0].why).contains("out of memory") and data.counts.trees == 0, "the trees part is recorded missing with its refusal (%s) and the file holds no natural=tree node: the dressing samples V1/V2 from the forest edges" % [String(missing[0].why).substr(0, 60) if missing.size() == 1 else missing], "parts_missing %s, trees %s" % [missing, data.counts.trees])
	var folder: String = fetch.folder
	if DirAccess.dir_exists_absolute(folder):
		var on_disk := true
		for part: Dictionary in parts:
			var answer_path: String = folder.path_join(part.answer_file)
			var query_path: String = folder.path_join(part.query_file)
			if not FileAccess.file_exists(answer_path) or not FileAccess.file_exists(query_path):
				on_disk = false
				continue
			var bytes := FileAccess.get_file_as_bytes(answer_path)
			on_disk = on_disk and _sha256_of(bytes) == part.answer_sha256 and bytes.size() == part.answer_bytes and _sha256_of(FileAccess.get_file_as_bytes(query_path)) == part.query_sha256
		_ok(on_disk, "the snapshot store is on this machine: every part's .json hashes to its answer_sha256 and its .ql to its query_sha256 (%s)" % folder, "a part on disk does not hash to the header")
		_ok(not FileAccess.file_exists(folder.path_join("q4_landcover.json")), "no whole q4_landcover.json is in the store (the pinned query was never answered whole)")
	else:
		_ok(true, "the snapshot store %s is not on this machine: the parts' shas stand as the header records them" % folder)
	# The projection samples.
	var samples: Array = data.provenance.projection.samples
	var within := samples.size() == 3
	var worst := 0.0
	for sample: Dictionary in samples:
		var got := SkeletonLoader.wgs84_to_local(sample.lat, sample.lon)
		var error := got.distance_to(Vector2(sample.x, sample.z))
		worst = maxf(worst, error)
		within = within and error < 0.005
	_ok(within, "the three projection samples in the header reproduce through SkeletonLoader.wgs84_to_local within 5 mm (worst %.5f m; the loader answers a single-precision Vector2, 1 mm per ulp at 12 km, and the port itself agrees with the skeleton's pyproj points to 0.7 mm at all 9 188 way starts: landcover.py --prove)" % worst, "samples %s, worst %.5f m" % [samples, worst])
	var first_point_ok := true
	for sample: Dictionary in samples:
		var found := false
		for list_name: String in ["forests", "fields", "water", "waterways"]:
			for record: Dictionary in data[list_name]:
				if int(record.osm) == int(sample.osm) and record.type == "way":
					var point: Array = record.outer[0][0] if record.has("outer") else record.points[0]
					found = found or (point[0] == sample.x and point[1] == sample.z)
		first_point_ok = first_point_ok and found
	_ok(first_point_ok, "each sample is the first point of its way's ring or line in the file")


# =============================================================================
#  THE REGION TABLE AND THE CATALOGUE
# =============================================================================

func _check_region_table() -> void:
	var file: Variant = TerrainBuilder.read_dressing()
	_ok(FileAccess.file_exists(TerrainBuilder.DRESSING_PATH) and file is Dictionary, "the region's dressing table is checked in beside the focus table at %s (the buildings test pins focus.json's four top keys; that check stays)" % TerrainBuilder.DRESSING_PATH)
	if not file is Dictionary:
		return
	var focus := {"dressing": file}
	var errors := TerrainBuilder.validate_dressing(file)
	_ok(errors.is_empty(), "the dressing table passes TerrainBuilder.validate_dressing() with nothing to say", "validate_dressing says %s" % [errors])
	var still_valid := Buildings.validate(Buildings.read_file())
	_ok(still_valid.is_empty() and file.region == Buildings.REGION, "the focus table is untouched and still passes Buildings.validate(); the dressing table names the same region %s" % file.region, "Buildings.validate says %s, region %s" % [still_valid, file.get("region")])
	var table := TerrainBuilder.region_dressing()
	_ok(table.get("sky_set") == "S1" and table.get("haze") == "S5", "the table names S1 as the sky set and S5 as the haze (PUT IN STONE, ring-region-decisions.md §5)", "table: %s / %s" % [table.get("sky_set"), table.get("haze")])
	var tints: Dictionary = table.get("palette", {}).get("tints", {})
	var brightest := 0.0
	for key: String in tints:
		var t: Array = tints[key]
		brightest = maxf(brightest, TerrainBuilder.luminance(Color(t[0], t[1], t[2])))
	_ok(tints.size() == TerrainBuilder.TINT_KEYS.size() and brightest <= TerrainBuilder.LUMINANCE_CAP, "the palette names all %d tints this pass draws, the brightest at luminance %.2f under the canon's %.1f cap" % [tints.size(), brightest, TerrainBuilder.LUMINANCE_CAP], "%d tints, brightest %.2f" % [tints.size(), brightest])
	_ok(table.get("density", {}).get("meaningful_objects_within_500_m") == MEANINGFUL_CEILING and table.get("density", {}).get("trees_within_60_m_per_8_m_per_side") == 1, "the table's ceilings: 1 tree per 8 m of road per side within 60 m, %d meaningful objects within 500 m" % MEANINGFUL_CEILING, "density %s" % [table.get("density")])
	# Broken blocks are named.
	var broken: Dictionary = focus.dressing.duplicate(true)
	broken.palette.tints.T1 = [0.9, 0.9, 0.9]
	_ok(_names(TerrainBuilder.validate_dressing(broken), "dressing.palette.tints.T1 has luminance"), "validate_dressing() names a tint over the luminance cap")
	broken = focus.dressing.duplicate(true)
	broken.sky_set = "B1"
	_ok(_names(TerrainBuilder.validate_dressing(broken), "dressing.sky_set is B1, not an S id"), "validate_dressing() names a sky set that is no S id")
	broken = focus.dressing.duplicate(true)
	broken.erase("haze")
	_ok(_names(TerrainBuilder.validate_dressing(broken), "dressing.haze is missing"), "validate_dressing() names a missing haze")
	broken = focus.dressing.duplicate(true)
	broken.colour = "blue"
	_ok(_names(TerrainBuilder.validate_dressing(broken), "dressing.colour is not in the schema"), "validate_dressing() names a key the schema does not know")
	broken = focus.dressing.duplicate(true)
	broken.region = "mosel"
	_ok(_names(TerrainBuilder.validate_dressing(broken), "dressing.region is mosel"), "validate_dressing() names another region's table")
	# A broken landcover is named too.
	var landcover: Dictionary = TerrainBuilder.read_landcover()
	var bad: Dictionary = {"region": landcover.region, "pipeline_version": 1, "snapshot": landcover.snapshot, "origin": landcover.origin, "provenance": {}, "counts": {"forests": 1, "fields": 0, "water": 0, "waterways": 0, "rock": 0, "trees": 0, "tree_rows": 0}, "forests": [{"osm": 1, "type": "way", "kind": "forest", "outer": [[[0.0, 0.0], [10.0, 0.0], [10.0, 10.0]]], "inner": []}], "fields": [], "water": [], "waterways": [], "rock": [], "trees": [], "tree_rows": []}
	_ok(_names(TerrainBuilder.validate_landcover(bad), "a ring that does not close") or _names(TerrainBuilder.validate_landcover(bad), "fewer than four points"), "validate_landcover() names an unclosed ring")
	bad.forests[0].outer = [[[0.0, 0.0], [10.0001, 0.0], [10.0, 10.0], [0.0, 0.0]]]
	_ok(_names(TerrainBuilder.validate_landcover(bad), "not an mm-rounded"), "validate_landcover() names a coordinate not rounded to the millimetre")
	bad.forests[0].outer = [[[0.0, 0.0], [10.0, 0.0], [10.0, 10.0], [0.0, 0.0]]]
	bad.counts.forests = 2
	_ok(_names(TerrainBuilder.validate_landcover(bad), "counts.forests is 2, the list holds 1"), "validate_landcover() names a count off its list")
	bad.counts.forests = 1
	bad.snapshot = {"osm_base": "2026-09-23T00:00:00Z", "bbox": landcover.snapshot.bbox, "query_sha": landcover.snapshot.query_sha}
	_ok(_names(TerrainBuilder.validate_landcover(bad), "snapshot.osm_base is 2026-09-23T00:00:00Z"), "validate_landcover() names a snapshot that is not the pinned one")
	_ok(_names(TerrainBuilder.validate_landcover(null), "not a JSON object"), "validate_landcover() names a file that is not JSON")


func _check_catalogue() -> void:
	for pair: Array in [[TerrainBuilder.ELEMENTS, "T"], [ForestWalls.ELEMENTS, "V"], [SkySet.ELEMENTS, "S"]]:
		for id: String in pair[0]:
			var entry := ElementCatalogue.entry(id)
			var family: String = "V" if id == "V7" else pair[1]
			_ok(not entry.is_empty() and entry.get("family") == id[0] and (id[0] == family or (pair[1] == "T" and id == "V7")), "%s is in the catalogue: %s (%s)" % [id, entry.get("title", "?"), entry.get("canon", "").substr(0, 60)], "%s: %s" % [id, entry])
	var t1: Dictionary = ElementCatalogue.entry("T1").stone_parameters
	_ok(t1.lattice_at_road_platform_m == PLATFORM_M and t1.lattice_within_200_m == NEAR_M and t1.lattice_to_2_km_m == MID_M and t1.lattice_beyond_2_km_m == FAR_M, "the catalogue's lattice table is 2 / 10 / 50 / 200 m (T1.stone_parameters)", "T1: %s" % [t1])
	var s5: Dictionary = ElementCatalogue.entry("S5").stone_parameters
	_ok(s5.normal_saturation_to_m == BAND_ENDS_M[0] and s5.slight_haze_to_m == BAND_ENDS_M[1] and s5.reduced_contrast_to_m == BAND_ENDS_M[2] and s5.sky_coloured_from_m == BAND_ENDS_M[2], "the catalogue's haze table is 100 / 300 / 800 / 800+ m (S5.stone_parameters)", "S5: %s" % [s5])
	var t6: Dictionary = ElementCatalogue.entry("T6").stone_parameters
	var v4: Dictionary = ElementCatalogue.entry("V4").stone_parameters
	_ok(t6.road_distance_max_m == WALL_WITHIN_M and v4.layers == 3 and v4.height_m[0] == 12 and v4.height_m[1] == 18 and ElementCatalogue.entry("V7").stone_parameters.trees_within_m == WALL_WITHIN_M, "the catalogue's forest rule: walls within %.0f m of a road, 3 layers, 12-18 m; no tree beyond %.0f m (T6, V4, V7)" % [WALL_WITHIN_M, WALL_WITHIN_M], "T6 %s, V4 %s" % [t6, v4])


# =============================================================================
#  THE SCENE
# =============================================================================

func _check_scene(scene: Node, terrain: TerrainBuilder, forest: ForestWalls, sky: SkySet, road: RoadBuilder) -> void:
	_ok(terrain != null and forest != null and sky != null and road != null, "the scene loads headless with Road, Terrain, Forest and Sky")
	_ok(terrain.profile == road.profile and forest.profile == road.profile and road.car != null and road.car.road_profile == road.profile, "the terrain and the forest read the very profile the road handed the car (one height source: the car's)")
	_ok(terrain.counts.near_tiles > 0 and terrain.counts.strips == road.road_count and terrain.counts.vertices > 1000000, "the terrain built: %s" % terrain.describe(), "terrain: %s" % terrain.describe())
	_ok(forest.counts.cards > 10000 and forest.counts.trees > 1000 and forest.counts.forests_walked == TerrainBuilder.read_landcover().counts.forests, "the forest built: %s" % forest.describe(), "forest: %s" % forest.describe())
	_ok(terrain.build_ms > 0 and forest.build_ms > 0, "both builders took measurable time at load (not printed: the suite's lines are the same on every machine)")
	var sky_ok: bool = sky.applied.get("sky_set") == "S1" and sky.applied.get("haze") == "S5"
	_ok(sky_ok, "the sky applied: %s" % sky.describe(), "sky: %s" % [sky.applied])
	var lattice: Dictionary = road.drape_data.lattice
	_ok(terrain.step == lattice.step_m and terrain.cols == lattice.cols and terrain.rows == lattice.rows and terrain.x0 == lattice.x0 and terrain.z0 == lattice.z0, "the terrain's lattice is the drape's: %d × %d at %.0f m from (%.0f, %.0f)" % [terrain.cols, terrain.rows, terrain.step, terrain.x0, terrain.z0])
	var elements_used: Dictionary = terrain.elements
	_ok(elements_used.get("V7", 0) > 100000 and elements_used.get("T7", 0) > 10000 and elements_used.get("T8", 0) > 50, "the landcover reached the terrain: %d V7 canopy vertices, %d T7 field vertices, %d T8 water pieces" % [elements_used.get("V7", 0), elements_used.get("T7", 0), elements_used.get("T8", 0)], "elements %s" % [elements_used])


## Nothing physical under the dressing nodes.
func _check_no_physics(terrain: Node, forest: Node) -> void:
	for node: Node in [terrain, forest]:
		var found := _physics_under(node)
		var children_are_meshes := true
		for child: Node in node.get_children():
			children_are_meshes = children_are_meshes and child is MeshInstance3D
		_ok(found.is_empty() and children_are_meshes and node.get_child_count() > 0, "%s carries %d MeshInstance3D children and not one CollisionObject3D, CollisionShape3D or Area3D anywhere under it (visuals only: the car reads the injected profile)" % [node.name, node.get_child_count()], "%s: physics %s, all meshes %s" % [node.name, found, children_are_meshes])


func _physics_under(node: Node) -> Array[String]:
	var found: Array[String] = []
	for child: Node in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D or child is Area3D or child is PhysicsBody3D:
			found.append(child.get_path())
		found.append_array(_physics_under(child))
	return found


# =============================================================================
#  THE LATTICE PLAN
# =============================================================================

func _check_lattice_plan(terrain: TerrainBuilder) -> void:
	_ok(terrain.band.platform == PLATFORM_M and terrain.band.near == NEAR_M and terrain.band.near_within == NEAR_WITHIN_M and terrain.band.mid == MID_M and terrain.band.mid_to == MID_TO_M and terrain.band.far == FAR_M, "the builder's bands are the catalogue's: %.0f m at the platform, %.0f m within %.0f m, %.0f m to %.0f m, %.0f m beyond" % [terrain.band.platform, terrain.band.near, terrain.band.near_within, terrain.band.mid, terrain.band.mid_to, terrain.band.far], "bands %s" % [terrain.band])
	_ok(TerrainBuilder.TILE_M == MID_M and TerrainBuilder.BLOCK_M == FAR_M and terrain.step == NEAR_M, "a tile is the mid band's %.0f m, a block the far band's %.0f m, the lattice the near band's %.0f m" % [TerrainBuilder.TILE_M, TerrainBuilder.BLOCK_M, terrain.step])
	# Every tile classed by the rule on the builder's own distance field.
	var cells := int(TerrainBuilder.TILE_M / terrain.step)
	var rule_holds := true
	var near := 0
	var mid := 0
	var far := 0
	for ti: int in terrain.tile_rows:
		for tj: int in terrain.tile_cols:
			var lowest := INF
			for a: int in cells + 1:
				for b: int in cells + 1:
					lowest = minf(lowest, terrain.distance[(ti * cells + a) * terrain.cols + tj * cells + b])
			var klass := terrain.tile_class[ti * terrain.tile_cols + tj]
			match klass:
				TerrainBuilder.TILE_NEAR:
					near += 1
					rule_holds = rule_holds and lowest <= NEAR_WITHIN_M
				TerrainBuilder.TILE_MID:
					mid += 1
					rule_holds = rule_holds and lowest > NEAR_WITHIN_M
				TerrainBuilder.TILE_FAR:
					far += 1
					rule_holds = rule_holds and lowest > MID_TO_M
	_ok(rule_holds and near == terrain.counts.near_tiles and mid == terrain.counts.mid_tiles and near + mid + far == terrain.tile_cols * terrain.tile_rows, "every tile is classed by the rule: %d near (a node within %.0f m of a road), %d mid (none within %.0f m), %d far (none within %.0f m) of %d × %d" % [near, NEAR_WITHIN_M, mid, NEAR_WITHIN_M, far, MID_TO_M, terrain.tile_cols, terrain.tile_rows], "rule %s, near %d/%d, mid %d/%d" % [rule_holds, near, terrain.counts.near_tiles, mid, terrain.counts.mid_tiles])
	_ok(terrain.counts.far_blocks == 0 and mid > 0, "the Ring's core has no far block (no point 2 km from every road: T9 is the rule with nothing to draw) and %d mid tiles (measured 500 at the landing)" % mid, "far %d, mid %d" % [terrain.counts.far_blocks, mid])
	# The distance field against brute force at sampled tiles' nearest nodes.
	var sampled := 0
	var worst := 0.0
	for t: int in range(0, terrain.tile_cols * terrain.tile_rows, TILE_SAMPLE_STRIDE):
		var ti := t / terrain.tile_cols
		var tj := t % terrain.tile_cols
		var best_node := -1
		var lowest := INF
		for a: int in cells + 1:
			for b: int in cells + 1:
				var node := (ti * cells + a) * terrain.cols + tj * cells + b
				if terrain.distance[node] < lowest:
					lowest = terrain.distance[node]
					best_node = node
		var x := terrain.x0 + (best_node % terrain.cols) * terrain.step
		var z := terrain.z0 + (best_node / terrain.cols) * terrain.step
		var exact := _brute_distance(terrain.ribbons, x, z)
		worst = maxf(worst, absf(exact - lowest))
		sampled += 1
	_ok(worst <= DISTANCE_TOLERANCE_M, "the distance field holds to a brute-force point-to-chord distance at %d sampled tiles' nearest nodes within %.1f m (half a step's diagonal; worst %.2f m)" % [sampled, DISTANCE_TOLERANCE_M, worst], "worst %.2f m over %d tiles" % [worst, sampled])
	# Near vertices on lattice nodes; mid vertices on tile corners.
	var near_on_grid := true
	var near_checked := 0
	var mid_on_grid := true
	var mid_checked := 0
	for child: Node in terrain.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh: ArrayMesh = child.mesh
		if child.name.begins_with("Near_"):
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for k: int in range(0, vertices.size(), 97):
				var v := vertices[k]
				var j := roundf((v.x - terrain.x0) / terrain.step)
				var i := roundf((v.z - terrain.z0) / terrain.step)
				var on := absf(v.x - (terrain.x0 + j * terrain.step)) < 0.002 and absf(v.z - (terrain.z0 + i * terrain.step)) < 0.002
				on = on and absf(v.y - terrain.heights[int(i) * terrain.cols + int(j)]) < 0.002
				near_on_grid = near_on_grid and on
				near_checked += 1
		elif child.name == "Mid":
			var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for k: int in vertices.size():
				var v := vertices[k]
				var on := absf(fmod(v.x - terrain.x0, MID_M)) < 0.002 or absf(fmod(v.x - terrain.x0, MID_M) - MID_M) < 0.002
				on = on and (absf(fmod(v.z - terrain.z0, MID_M)) < 0.002 or absf(fmod(v.z - terrain.z0, MID_M) - MID_M) < 0.002)
				mid_on_grid = mid_on_grid and on
				mid_checked += 1
	_ok(near_on_grid and near_checked > 1000, "every sampled near-band vertex (%d of them, every 97th) sits on a lattice node at the node's own height: the 10 m band draws the lattice, never a resampling" % near_checked, "near vertices off the grid")
	_ok(mid_on_grid and mid_checked > 0, "every mid-band vertex (%d, the quads and their skirts) sits on a %.0f m tile corner" % [mid_checked, MID_M], "mid vertices off the corners")


## The exact distance from a point to the nearest covered chord.
func _brute_distance(ribbons: Array[TerrainBuilder.Ribbon], x: float, z: float) -> float:
	var best := INF
	for ribbon: TerrainBuilder.Ribbon in ribbons:
		for c: int in range(ribbon.xs.size() - 1):
			var ax := ribbon.xs[c]
			var az := ribbon.zs[c]
			var dx := ribbon.xs[c + 1] - ax
			var dz := ribbon.zs[c + 1] - az
			var chord2 := dx * dx + dz * dz
			if chord2 <= 0.0:
				continue
			var t := clampf(((x - ax) * dx + (z - az) * dz) / chord2, 0.0, 1.0)
			var cx := ax + t * dx
			var cz := az + t * dz
			best = minf(best, sqrt((x - cx) * (x - cx) + (z - cz) * (z - cz)))
	return best


## The platform strips: 2 m stations and every skeleton point, no gap over
## 2 m, offsets at the paved edge, the blend band's end and the apron.
func _check_strips(terrain: TerrainBuilder) -> void:
	var strips_ok := true
	var checked := 0
	var worst_gap := 0.0
	for ribbon: TerrainBuilder.Ribbon in terrain.ribbons:
		var strip: Dictionary = terrain.strips.get(ribbon.id, {})
		if strip.is_empty():
			strips_ok = false
			continue
		var chainages: PackedFloat64Array = strip.chainages
		# The end station stands only when the length is more than a
		# millimetre past the last whole station (WorldRoadProfile
		# .station_chainages, the drape's rule): the strip may end up to
		# 1 mm short of the road.
		var ok: bool = chainages[0] == 0.0 and absf(chainages[chainages.size() - 1] - ribbon.length) <= 1e-3
		for k: int in range(1, chainages.size()):
			worst_gap = maxf(worst_gap, chainages[k] - chainages[k - 1])
			ok = ok and chainages[k] - chainages[k - 1] <= PLATFORM_M + 1e-6
		for s: float in WorldRoadProfile.station_chainages(ribbon.length, PLATFORM_M):
			ok = ok and chainages.bsearch(s) < chainages.size() and absf(chainages[mini(chainages.bsearch(s), chainages.size() - 1)] - s) < 1e-6
		for i: int in range(1, ribbon.chain.size() - 1):
			var at := chainages.bsearch(ribbon.chain[i])
			ok = ok and at < chainages.size() and absf(chainages[at] - ribbon.chain[i]) < 1e-6
		var offsets: PackedFloat64Array = strip.offsets
		var hw := ribbon.half_width
		var blend := WorldRoadProfile.BLEND_BAND_M
		ok = ok and offsets.size() == 6 and offsets[2] == -hw and offsets[3] == hw and offsets[1] == -(hw + blend) and offsets[4] == hw + blend and offsets[0] == -(hw + blend + TerrainBuilder.APRON_M) and offsets[5] == hw + blend + TerrainBuilder.APRON_M
		ok = ok and strip.vertices == chainages.size() * offsets.size()
		strips_ok = strips_ok and ok
		checked += 1
	_ok(strips_ok and checked == terrain.ribbons.size(), "every one of the %d platform strips stands at every %.0f m station from 0 to the road's end (within the station rule's millimetre) and at every skeleton point (widest gap %.3f m), with offsets at the paved edge, the blend band's end (%.0f m out) and the apron (%.0f m further)" % [checked, PLATFORM_M, worst_gap, WorldRoadProfile.BLEND_BAND_M, TerrainBuilder.APRON_M], "strips %s, checked %d of %d" % [strips_ok, checked, terrain.ribbons.size()])
	# A strip's inner edge is the field's platform edge: the road strip's
	# edge height at the same point.
	var pit: Dictionary = terrain.strips.get("199642470-0", {})
	var edge_ok := false
	if not pit.is_empty():
		var vertices: PackedVector3Array = pit.mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var v := vertices[3]  # section 0, the right paved edge
		edge_ok = absf(v.y - terrain.profile.sample_height(v.x, v.z)) < 0.002
	_ok(edge_ok, "the pit lane's strip meets the road at the paved edge: its edge vertex is the profile's height there within 2 mm")


# =============================================================================
#  THE WALLS AND THE TREES
# =============================================================================

func _check_walls(terrain: TerrainBuilder, forest: ForestWalls, landcover: Dictionary) -> void:
	_ok(forest.wall_within_m == WALL_WITHIN_M and forest.layers == 3 and forest.wall_height_m == [12.0, 18.0] and forest.trees_within_m == WALL_WITHIN_M, "the builder's forest rule is the catalogue's: walls within %.0f m, %d layers, %.0f-%.0f m; trees within %.0f m" % [forest.wall_within_m, forest.layers, forest.wall_height_m[0], forest.wall_height_m[1], forest.trees_within_m])
	var cards := forest.card_x.size()
	var all_within := true
	var worst := 0.0
	var heights_ok := true
	var layers_seen := {}
	for i: int in cards:
		worst = maxf(worst, forest.card_road_distance[i])
		all_within = all_within and forest.card_road_distance[i] <= WALL_WITHIN_M
		heights_ok = heights_ok and forest.card_height[i] >= 12.0 and forest.card_height[i] <= 18.0
		layers_seen[forest.card_layer[i]] = true
	_ok(all_within and cards > 10000, "every one of the %d V4 cards is within %.0f m of a covered road on the builder's exact chord distance (the farthest at %.3f m)" % [cards, WALL_WITHIN_M, worst], "cards %d, within %s, worst %.3f" % [cards, all_within, worst])
	_ok(heights_ok and layers_seen.size() == 3, "every card is 12-18 m tall and the three staggered layers are all built")
	var sampled := 0
	var brute_ok := true
	var brute_worst := 0.0
	for i: int in range(0, cards, CARD_SAMPLE_STRIDE):
		var d := _brute_distance(terrain.ribbons, forest.card_x[i], forest.card_z[i])
		brute_worst = maxf(brute_worst, d)
		brute_ok = brute_ok and d <= WALL_WITHIN_M + 1e-6 and absf(d - forest.card_road_distance[i]) < 0.01
		sampled += 1
	_ok(brute_ok, "%d sampled cards (every %dth) are within %.0f m by brute force over every covered chord (worst %.3f m), the builder's distance agreeing to a centimetre" % [sampled, CARD_SAMPLE_STRIDE, WALL_WITHIN_M, brute_worst], "brute force: worst %.3f m" % brute_worst)
	var forest_ids := {}
	for record: Dictionary in landcover.forests:
		forest_ids[int(record.osm)] = true
	var on_forests := true
	for i: int in cards:
		on_forests = on_forests and forest_ids.has(forest.card_osm[i])
	_ok(on_forests, "every card belongs to a forest polygon of the landcover (landuse=forest / natural=wood): no wall without a forest edge")
	_ok(forest.counts.cards_skipped_far > 0, "%d card slots beyond the %.0f m were left empty: the rule refuses, it does not clamp" % [forest.counts.cards_skipped_far, WALL_WITHIN_M])
	# Trees: none beyond the 60 m unless a row's or a mapped tree's.
	var trees := forest.tree_x.size()
	var far_trees := 0
	var far_allowed := true
	var v1 := 0
	var v2 := 0
	for i: int in trees:
		if forest.tree_element[i] == "V1":
			v1 += 1
		else:
			v2 += 1
		if forest.tree_road[i] == "":
			far_trees += 1
			far_allowed = far_allowed and _brute_distance(terrain.ribbons, forest.tree_x[i], forest.tree_z[i]) > WALL_WITHIN_M - 0.01
	_ok(far_allowed and v1 + v2 == trees and v2 > v1, "%d trees (%d V2 conifers, the Eifel default; %d V1 broadleaves where the polygon says so); the %d not charged to a road stand beyond the %.0f m and are tree rows' or mapped trees' only" % [trees, v2, v1, far_trees, WALL_WITHIN_M], "far trees %d allowed %s" % [far_trees, far_allowed])
	_ok(far_trees <= forest.counts.trees_rows and forest.counts.trees_skipped_far > 0, "no edge-sampled tree stands beyond the %.0f m (%d refused; %d rows' trees may)" % [WALL_WITHIN_M, forest.counts.trees_skipped_far, forest.counts.trees_rows], "far trees %d, rows %d" % [far_trees, forest.counts.trees_rows])


# =============================================================================
#  THE AUTHORED ASSETS (4B-ASSETS-1)
# =============================================================================

func _check_assets(forest: ForestWalls) -> void:
	var loaded := true
	var lines: Array[String] = []
	for key: String in ["V2", "V1", "V6"]:
		var archetype: ForestWalls.Archetype = forest.archetypes.get(key)
		if archetype == null:
			loaded = false
			lines.append("%s missing" % key)
			continue
		var within: bool = archetype.triangles >= ARCHETYPE_TRIANGLES[0] and archetype.triangles <= ARCHETYPE_TRIANGLES[1]
		var two_surfaces: bool = archetype.bark_indices.size() > 0 and archetype.foliage_indices.size() > 0 and archetype.bark_vertices.size() == archetype.bark_uvs.size() and archetype.foliage_vertices.size() == archetype.foliage_uvs.size()
		var uv_inside := true
		for uv: Vector2 in archetype.foliage_uvs:
			uv_inside = uv_inside and uv.x >= -0.001 and uv.x <= 1.001 and uv.y >= -0.001 and uv.y <= 1.001
		loaded = loaded and within and two_surfaces and uv_inside and archetype.height > 5.0
		lines.append("%s %s %d tris / %d verts / %.0f m" % [key, archetype.path.get_file(), archetype.triangles, archetype.vertex_count, archetype.height])
	_ok(loaded, "the three archetypes load from their .glb with a bark and a foliage surface, %d-%d triangles each, the foliage UVs inside the atlas: %s" % [ARCHETYPE_TRIANGLES[0], ARCHETYPE_TRIANGLES[1], ", ".join(lines)], "archetypes: %s" % [", ".join(lines)])
	var wall: StandardMaterial3D = forest.materials.get("wall")
	var bark: StandardMaterial3D = forest.materials.get("bark")
	var spruce: StandardMaterial3D = forest.materials.get("foliage_V2")
	var beech: StandardMaterial3D = forest.materials.get("foliage_V1")
	var cut_ok := true
	for pair: Array in [[wall, ForestWalls.WALL_TEXTURE], [spruce, ForestWalls.FOLIAGE_TEXTURES.V2], [beech, ForestWalls.FOLIAGE_TEXTURES.V1]]:
		var material: StandardMaterial3D = pair[0]
		cut_ok = cut_ok and material != null and material.albedo_texture != null and material.albedo_texture.resource_path == pair[1] and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and material.alpha_scissor_threshold == ForestWalls.ALPHA_SCISSOR and material.cull_mode == BaseMaterial3D.CULL_DISABLED and material.vertex_color_use_as_albedo and material.albedo_color == Color.WHITE
	var bark_ok: bool = bark != null and bark.albedo_texture != null and bark.albedo_texture.resource_path == ForestWalls.BARK_TEXTURE and bark.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED and bark.cull_mode == BaseMaterial3D.CULL_BACK and bark.vertex_color_use_as_albedo
	_ok(cut_ok and bark_ok and forest.materials.size() == 4, "four materials (was one flat vertex-colour material): the wall, the spruce and the beech foliage alpha-scissored at %.1f on the authored textures, both faces drawn; the bark opaque, back faces culled; every one multiplying the vertex colour (the region's tints)" % ForestWalls.ALPHA_SCISSOR, "wall %s bark %s spruce %s beech %s" % [wall, bark, spruce, beech])
	var surfaces := 0
	var surfaces_ok := true
	var seen := {}
	var brightest := 0.0
	var known: Array = forest.materials.values()
	for child: Node in forest.get_children():
		var mesh: ArrayMesh = (child as MeshInstance3D).mesh
		for s: int in mesh.get_surface_count():
			surfaces += 1
			var arrays := mesh.surface_get_arrays(s)
			var material: Material = mesh.surface_get_material(s)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			surfaces_ok = surfaces_ok and material in known and uvs.size() == vertices.size() and colours.size() == vertices.size() and vertices.size() > 0
			for key: String in forest.materials:
				if forest.materials[key] == material:
					seen[key] = seen.get(key, 0) + 1
			for c: int in range(0, colours.size(), PIXEL_STRIDE):
				brightest = maxf(brightest, TerrainBuilder.luminance(colours[c]))
	_ok(surfaces_ok and seen.size() == 4 and surfaces > forest.get_child_count(), "every one of the %d surfaces under Forest's %d chunks carries UVs and vertex colours and wears one of the four materials (%s); the brightest sampled vertex colour at luminance %.2f under the cap %.1f" % [surfaces, forest.get_child_count(), seen, brightest, TerrainBuilder.LUMINANCE_CAP], "surfaces ok %s seen %s brightest %.2f" % [surfaces_ok, seen, brightest])
	_ok(brightest <= TerrainBuilder.LUMINANCE_CAP, "no baked vertex colour is over the canon's luminance cap: a tree's hashed shade only darkens its tint")
	var expected_vertices := forest.card_x.size() * 4
	var expected_triangles := forest.card_x.size() * 2
	var rows_in_row_tree := 0
	var rows_flagged := 0
	var transforms_ok := true
	for i: int in forest.tree_x.size():
		var key := forest.archetype_of(i)
		var archetype: ForestWalls.Archetype = forest.archetypes.get(key)
		if archetype == null:
			transforms_ok = false
			continue
		expected_vertices += archetype.vertex_count
		expected_triangles += archetype.triangles
		if forest.tree_in_row[i] == 1:
			rows_flagged += 1
			if forest.tree_element[i] == "V1":
				rows_in_row_tree += 1
				transforms_ok = transforms_ok and key == "V6"
		if i % CARD_SAMPLE_STRIDE == 0:
			var transform := forest.tree_transform(i)
			var scale := transform.basis.get_scale()
			var expected_scale := forest.tree_height[i] / archetype.height
			var shade := forest.tree_shade(i)
			transforms_ok = transforms_ok and absf(scale.x - expected_scale) < 1e-4 and absf(scale.y - expected_scale) < 1e-4 and absf(scale.z - expected_scale) < 1e-4 and absf(transform.origin.x - forest.tree_x[i]) < 0.002 and absf(transform.origin.z - forest.tree_z[i]) < 0.002 and absf(transform.origin.y - (forest.profile.elevation_height(forest.tree_x[i], forest.tree_z[i]) - ForestWalls.TREE_SINK_M)) < 1e-4 and shade >= ForestWalls.TREE_SHADE_MIN and shade <= 1.0
	_ok(forest.counts.vertices == expected_vertices and forest.counts.triangles == expected_triangles, "the mesh accounting is exact: %d vertices = %d cards x 4 + every tree's archetype, %d triangles = cards x 2 + the archetypes' (was 10 / 16 flat triangles a tree)" % [forest.counts.vertices, forest.card_x.size(), forest.counts.triangles], "counted %d / %d, expected %d / %d" % [forest.counts.vertices, forest.counts.triangles, expected_vertices, expected_triangles])
	_ok(transforms_ok and rows_flagged == forest.counts.trees_rows, "every %dth tree's transform is its point (within the single-precision millimetre at 12 km), its foot %.1f m under the ground, a uniform scale of its height over the archetype's, its shade in [%.1f, 1]; the %d row trees are flagged and the %d V1 among them wear the row tree" % [CARD_SAMPLE_STRIDE, ForestWalls.TREE_SINK_M, ForestWalls.TREE_SHADE_MIN, rows_flagged, rows_in_row_tree], "transforms ok %s, rows flagged %d of %d" % [transforms_ok, rows_flagged, forest.counts.trees_rows])


## The checked-in textures, read as files (never through Blender).
func _check_authored_textures() -> void:
	var base := Image.load_from_file(ASPHALT_DIR + "road_asphalt_1024_basecolor.png")
	var rough := Image.load_from_file(ASPHALT_DIR + "road_asphalt_1024_roughness.png")
	var normal := Image.load_from_file(ASPHALT_DIR + "road_asphalt_1024_normal.png")
	var sizes_ok: bool = base != null and rough != null and normal != null and base.get_width() == ASPHALT_SIZE and base.get_height() == ASPHALT_SIZE and rough.get_width() == ASPHALT_SIZE and rough.get_height() == ASPHALT_SIZE and normal.get_width() == ASPHALT_SIZE and normal.get_height() == ASPHALT_SIZE
	_ok(sizes_ok, "the asphalt set is checked in at %s: basecolor, roughness and normal, %d x %d each (the canon's 'road: repeating 512/1024'; element-library.md §1's road_asphalt_1024)" % [ASPHALT_DIR, ASPHALT_SIZE, ASPHALT_SIZE])
	if not sizes_ok:
		return
	var neutral := true
	var sum := 0.0
	var samples := 0
	for k: int in range(0, ASPHALT_SIZE * ASPHALT_SIZE, PIXEL_STRIDE):
		var c := base.get_pixel(k % ASPHALT_SIZE, k / ASPHALT_SIZE)
		neutral = neutral and c.r8 == c.g8 and c.g8 == c.b8
		sum += c.r
		samples += 1
	var mean := sum / samples
	_ok(neutral and mean > 0.72 and mean < 0.84, "the basecolor is greyscale-neutral (R = G = B at %d sampled pixels; the game multiplies RoadBuilder.ASPHALT_TINT) with a mean of %.3f near the procedural texture's 0.78" % [samples, mean], "neutral %s mean %.3f" % [neutral, mean])
	var rut_mean := 0.0
	for u: float in RUT_U:
		rut_mean += _column_mean(base, int(u * ASPHALT_SIZE)) / RUT_U.size()
	var lane_mean := 0.0
	for u: float in LANE_CENTRE_U:
		lane_mean += _column_mean(base, int(u * ASPHALT_SIZE)) / LANE_CENTRE_U.size()
	var shoulder_mean := (_column_mean(base, int(SHOULDER_U * ASPHALT_SIZE)) + _column_mean(base, ASPHALT_SIZE - 1 - int(SHOULDER_U * ASPHALT_SIZE))) * 0.5
	var mirror := 0.0
	for k: int in RUT_U.size() / 2:
		mirror = maxf(mirror, absf(_column_mean(base, int(RUT_U[k] * ASPHALT_SIZE)) - _column_mean(base, int(RUT_U[RUT_U.size() - 1 - k] * ASPHALT_SIZE))))
	_ok(rut_mean < lane_mean - 0.03 and shoulder_mean < lane_mean - 0.08 and mirror < 0.03, "the layered road reads in the tile: the wheel ruts at u %s average %.3f, darker than the lane centres' %.3f, the shoulders' grime %.3f darker still, the ruts mirrored about u 0.5 within %.3f" % [RUT_U, rut_mean, lane_mean, shoulder_mean, mirror], "rut %.3f lane %.3f shoulder %.3f mirror %.3f" % [rut_mean, lane_mean, shoulder_mean, mirror])
	var rut_rough := 0.0
	for u: float in RUT_U:
		rut_rough += _column_mean(rough, int(u * ASPHALT_SIZE)) / RUT_U.size()
	var lane_rough := 0.0
	for u: float in LANE_CENTRE_U:
		lane_rough += _column_mean(rough, int(u * ASPHALT_SIZE)) / LANE_CENTRE_U.size()
	_ok(rut_rough < lane_rough - 0.1 and lane_rough > 0.7, "the roughness map polishes the ruts: %.3f in the tracks against %.3f at the lane centres ('very mild roughness variation')" % [rut_rough, lane_rough], "rut %.3f lane %.3f" % [rut_rough, lane_rough])
	var seam := _row_difference(base, 0, ASPHALT_SIZE - 1)
	var neighbour := _row_difference(base, 0, 1)
	_ok(seam <= neighbour * 1.5 + 0.01, "the tile is seamless along the road: the first and last rows differ by %.4f, the first two rows by %.4f" % [seam, neighbour], "seam %.4f neighbour %.4f" % [seam, neighbour])
	var flat := 0.0
	var tilt := 0.0
	for k: int in range(0, ASPHALT_SIZE * ASPHALT_SIZE, PIXEL_STRIDE):
		var c := normal.get_pixel(k % ASPHALT_SIZE, k / ASPHALT_SIZE)
		flat += c.b
		tilt += absf(c.r - 0.5) + absf(c.g - 0.5)
	flat /= samples
	tilt /= samples
	_ok(flat > 0.9 and tilt < 0.1, "the normal map is subtle: the sampled blue mean %.3f (nearly flat), the mean tilt %.3f" % [flat, tilt], "flat %.3f tilt %.3f" % [flat, tilt])
	var wall := Image.load_from_file(VEGETATION_DIR + "foliage_wall_512.png")
	var spruce := Image.load_from_file(VEGETATION_DIR + "foliage_spruce_512.png")
	var beech := Image.load_from_file(VEGETATION_DIR + "foliage_beech_512.png")
	var bark := Image.load_from_file(VEGETATION_DIR + "bark_256.png")
	var veg_ok := wall != null and spruce != null and beech != null and bark != null
	if veg_ok:
		veg_ok = wall.get_width() == CARD_TEXTURE_SIZE and wall.get_height() == CARD_TEXTURE_SIZE and spruce.get_width() == CARD_TEXTURE_SIZE and beech.get_width() == CARD_TEXTURE_SIZE and bark.get_width() == BARK_TEXTURE_SIZE and bark.get_height() == BARK_TEXTURE_SIZE
	_ok(veg_ok, "the vegetation textures are checked in at %s: the wall card, the spruce and the beech atlas at %d, the bark at %d (the canon's 'vegetation: 128-512')" % [VEGETATION_DIR, CARD_TEXTURE_SIZE, BARK_TEXTURE_SIZE])
	if not veg_ok:
		return
	var alpha_ok := true
	var grey_ok := true
	for image: Image in [wall, spruce, beech, bark]:
		var under := 0
		var over := 0
		for k: int in range(0, image.get_width() * image.get_height(), PIXEL_STRIDE):
			var c := image.get_pixel(k % image.get_width(), k / image.get_width())
			grey_ok = grey_ok and c.r8 == c.g8 and c.g8 == c.b8
			if c.a < 0.5:
				under += 1
			else:
				over += 1
		if image == bark:
			alpha_ok = alpha_ok and under == 0
		else:
			alpha_ok = alpha_ok and under > 0 and over > 0
	var sky := true
	var foot := true
	for x: int in CARD_TEXTURE_SIZE:
		sky = sky and wall.get_pixel(x, 0).a < 0.5
		foot = foot and wall.get_pixel(x, CARD_TEXTURE_SIZE - 1).a >= 0.5
	_ok(grey_ok and alpha_ok and sky and foot, "the vegetation textures are greyscale-neutral (the tints colour them) and alpha-cut: the wall's top row is open sky and its foot solid, the atlases carry both cut and cover, the bark is opaque", "grey %s alpha %s sky %s foot %s" % [grey_ok, alpha_ok, sky, foot])


func _column_mean(image: Image, x: int) -> float:
	var sum := 0.0
	for y: int in image.get_height():
		sum += image.get_pixel(x, y).r
	return sum / image.get_height()


func _row_difference(image: Image, a: int, b: int) -> float:
	var sum := 0.0
	for x: int in image.get_width():
		sum += absf(image.get_pixel(x, a).r - image.get_pixel(x, b).r)
	return sum / image.get_width()


func _check_ceiling(terrain: TerrainBuilder, forest: ForestWalls) -> void:
	# Per road and side, recounted from the tree list.
	var used := {}
	for i: int in forest.tree_x.size():
		if forest.tree_road[i] == "":
			continue
		var key := "%s/%d" % [forest.tree_road[i], forest.tree_side[i]]
		used[key] = used.get(key, 0) + 1
	var lengths := {}
	for ribbon: TerrainBuilder.Ribbon in terrain.ribbons:
		lengths[ribbon.id] = ribbon.length
	var over := 0
	var busiest := 0.0
	for key: String in used:
		var id: String = key.split("/")[0]
		var allowed := floorf(lengths.get(id, 0.0) / TREE_SPAN_M)
		if used[key] > allowed:
			over += 1
		if allowed > 0.0:
			busiest = maxf(busiest, used[key] / allowed)
	_ok(over == 0 and used.size() > 1000, "the density ceiling holds per road and side: %d (road, side) pairs carry trees, none over floor(length / %.0f m) (the fullest at %.0f %% of its budget)" % [used.size(), TREE_SPAN_M, busiest * 100.0], "%d pairs over the ceiling" % over)
	_ok(forest.counts.trees_skipped_budget > 0, "%d edge samples were refused by a spent budget: the ceiling bites" % forest.counts.trees_skipped_budget)
	# Ten points along the Nordschleife.
	var points: Array[Vector2] = []
	for k: int in LOOP_SAMPLES:
		var segment := SkeletonLoader.segment(_loop.segments[k * _loop.segments.size() / LOOP_SAMPLES])
		points.append(segment.first())
	var water_vertices := PackedVector3Array()
	var water: MeshInstance3D = terrain.get_node_or_null("Water")
	if water != null:
		water_vertices = water.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var all_under := true
	var masses_max := 0
	var trees_max_share := 0.0
	var lines := []
	for p: Vector2 in points:
		var forests := {}
		for i: int in forest.card_x.size():
			if Vector2(forest.card_x[i], forest.card_z[i]).distance_to(p) <= AUDIT_RADIUS_M:
				forests[forest.card_osm[i]] = true
		var trees := 0
		var rows := {}
		for i: int in forest.tree_x.size():
			if Vector2(forest.tree_x[i], forest.tree_z[i]).distance_to(p) <= AUDIT_RADIUS_M:
				trees += 1
				if forest.tree_road[i] == "":
					rows[forest.tree_osm[i]] = true
		var water_planes := 0
		var seen_water := {}
		for k: int in range(0, water_vertices.size(), 3):
			if Vector2(water_vertices[k].x, water_vertices[k].z).distance_to(p) <= AUDIT_RADIUS_M and not seen_water.has(k / 3):
				seen_water[k / 3] = true
		water_planes = 1 if not seen_water.is_empty() else 0
		var length := _road_length_in_disc(terrain.ribbons, p, AUDIT_RADIUS_M)
		var tree_ceiling := 2.0 * length / TREE_SPAN_M
		var masses := forests.size() + rows.size() + water_planes
		masses_max = maxi(masses_max, masses)
		trees_max_share = maxf(trees_max_share, trees / tree_ceiling if tree_ceiling > 0.0 else INF)
		all_under = all_under and trees <= tree_ceiling and masses <= MEANINGFUL_CEILING
		lines.append("(%.0f, %.0f): %d masses, %d trees / %.0f" % [p.x, p.y, masses, trees, tree_ceiling])
	_ok(all_under, "at %d Nordschleife points the objects within %.0f m are under the ceilings: at most %d meaningful masses (forests with a card, tree rows, water) of the table's %d, and the trees at most %.0f %% of §5's 2 × road length / %.0f m; %s" % [LOOP_SAMPLES, AUDIT_RADIUS_M, masses_max, MEANINGFUL_CEILING, trees_max_share * 100.0, TREE_SPAN_M, "; ".join(lines)], "over: %s" % ["; ".join(lines)])


## The covered road length inside a disc [m], chords sampled in 20 pieces.
func _road_length_in_disc(ribbons: Array[TerrainBuilder.Ribbon], centre: Vector2, radius: float) -> float:
	var length := 0.0
	for ribbon: TerrainBuilder.Ribbon in ribbons:
		for c: int in range(ribbon.xs.size() - 1):
			var a := Vector2(ribbon.xs[c], ribbon.zs[c])
			var b := Vector2(ribbon.xs[c + 1], ribbon.zs[c + 1])
			if a.distance_to(centre) > radius + 200.0 and b.distance_to(centre) > radius + 200.0:
				continue
			var chord := a.distance_to(b)
			for s: int in 20:
				if a.lerp(b, (s + 0.5) / 20.0).distance_to(centre) <= radius:
					length += chord / 20.0
	return length


# =============================================================================
#  THE HAZE AND THE SUN
# =============================================================================

func _check_haze(scene: Node, sky: SkySet) -> void:
	var env: Environment = scene.get_node("WorldEnvironment").environment
	var bands := SkySet.haze_bands(ElementCatalogue.entry("S5"))
	_ok(env.fog_enabled and env.fog_mode == Environment.FOG_MODE_DEPTH and not env.volumetric_fog_enabled, "the haze is Godot depth fog, volumetric fog off (\"Not volumetric cinematic fog\")")
	_ok(env.fog_depth_begin == BAND_ENDS_M[0] and env.fog_depth_end == SkySet.SKY_COLOURED_FULL_M and env.fog_density == 1.0 and env.fog_sky_affect == 0.0, "the fog begins at S5's %.0f m (normal saturation to there), reaches the sky at %.0f m, density 1, the sky plate untouched" % [env.fog_depth_begin, env.fog_depth_end], "begin %.0f end %.0f density %.2f sky %.2f" % [env.fog_depth_begin, env.fog_depth_end, env.fog_density, env.fog_sky_affect])
	var horizon := SkySet.horizon_colour(env)
	_ok(env.fog_light_color == horizon and horizon == Color(0.68, 0.78, 0.88, 1.0), "the haze colour is the sky plate's horizon colour %s (read from the material, not a second constant)" % [horizon], "fog %s, horizon %s" % [env.fog_light_color, horizon])
	var curve_ok := true
	var lines := []
	for k: int in HAZE_SAMPLES_M.size():
		var d: float = HAZE_SAMPLES_M[k]
		var table := SkySet.haze_at(d, bands)
		var engine: float = SkySet.depth_fog_at(d, env.fog_depth_begin, env.fog_depth_end, env.fog_depth_curve, env.fog_density)
		var band := SkySet.band_of(d, bands)
		curve_ok = curve_ok and band == BAND_NAMES[k] and absf(engine - table) <= SkySet.FIT_TOLERANCE
		lines.append("%.0f m: %s, table %.3f, engine %.3f" % [d, band, table, engine])
	_ok(curve_ok, "the four-band curve sampled at 50 / 200 / 500 / 1 000 m falls in the catalogue's bands in order and the engine's depth curve (exponent %.3f) is within %.2f of it: %s" % [env.fog_depth_curve, SkySet.FIT_TOLERANCE, "; ".join(lines)], "; ".join(lines))
	var ends_ok := SkySet.haze_at(BAND_ENDS_M[0], bands) == 0.0 and is_equal_approx(SkySet.haze_at(BAND_ENDS_M[1], bands), SkySet.SLIGHT_HAZE) and is_equal_approx(SkySet.haze_at(BAND_ENDS_M[2], bands), SkySet.REDUCED_CONTRAST) and is_equal_approx(SkySet.haze_at(SkySet.SKY_COLOURED_FULL_M, bands), 1.0) and SkySet.haze_at(0.0, bands) == 0.0
	_ok(ends_ok, "the table's amounts at the band ends: 0 to %.0f m, %.2f at %.0f m, %.2f at %.0f m, 1 at %.0f m (the amounts chosen for the dressing; the distances the canon's)" % [BAND_ENDS_M[0], SkySet.SLIGHT_HAZE, BAND_ENDS_M[1], SkySet.REDUCED_CONTRAST, BAND_ENDS_M[2], SkySet.SKY_COLOURED_FULL_M])
	var engine_monotone := true
	var previous := -1.0
	for d: int in range(0, 3001, 50):
		var value: float = SkySet.depth_fog_at(float(d), env.fog_depth_begin, env.fog_depth_end, env.fog_depth_curve, env.fog_density)
		engine_monotone = engine_monotone and value >= previous and value <= 1.0
		previous = value
	_ok(engine_monotone and previous == 1.0, "the engine's curve rises monotonically from 0 to 1 at %.0f m" % SkySet.SKY_COLOURED_FULL_M)
	# The sun.
	var suns := 0
	for node: Node in _all_under(scene):
		if node is DirectionalLight3D:
			suns += 1
	var sun: DirectionalLight3D = scene.get_node("Sun")
	var travel := -sun.global_transform.basis.z
	var elevation := rad_to_deg(asin(-travel.y))
	var bearing := fmod(rad_to_deg(atan2(-travel.x, travel.z)) + 360.0, 360.0)
	_ok(suns == 1 and absf(elevation - SUN_ELEVATION_DEG) < 0.01 and absf(bearing - SUN_AZIMUTH_DEG) < 0.01 and sun.shadow_enabled, "one sun (S1: one sun, one sky), at %.1f° elevation (the catalogue's default; was the scene's 50°) from bearing %.0f° (the table's), shadows on" % [elevation, bearing], "suns %d, elevation %.2f, bearing %.2f" % [suns, elevation, bearing])
	_ok(env.sky != null and env.sky.sky_material is ProceduralSkyMaterial and env.background_mode == Environment.BG_SKY, "one sky: the scene's procedural plate (no new asset: the photographic skybox is a later pass)")


func _all_under(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(_all_under(child))
	return found


# =============================================================================
#  THE CATALOGUE HELD TO WHAT WAS BUILT
# =============================================================================

func _check_elements(terrain: TerrainBuilder, forest: ForestWalls, sky: SkySet) -> void:
	for pair: Array in [[terrain.elements, TerrainBuilder.ELEMENTS, "terrain"], [forest.elements, ForestWalls.ELEMENTS, "forest"], [{"S1": 1, "S5": 1}, SkySet.ELEMENTS, "sky"]]:
		var used: Dictionary = pair[0]
		var declared: Array = pair[1]
		var inside := true
		for id: String in used:
			inside = inside and id in declared and not ElementCatalogue.entry(id).is_empty()
		_ok(inside and not used.is_empty(), "the %s instantiates %s: every id declared and in the catalogue, nothing outside it" % [pair[2], used], "%s used %s" % [pair[2], used])


# =============================================================================
#  HELPERS
# =============================================================================

func _names(errors: PackedStringArray, expected: String) -> bool:
	for error: String in errors:
		if error.contains(expected):
			return true
	return false


func _sha256_of(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()


func _is_sha(value: Variant) -> bool:
	return value is String and RegEx.create_from_string("^[0-9a-f]{64}$").search(value) != null
