class_name BuildingsShells
extends Node3D
## 4B-8: the Ring's second dressing pass, outside Road/Terrain/Forest.
## ShellsWatch attaches Buildings before _ready; LoadingScreen claims it
## before the Ring enters the tree. prepare/place/mesh_jobs/run_job are data
## stages, add_job/finish_build main-thread node stages with the loader's
## budget. CHUNK_ORDER is first-seen (element, 1 km chunk), then solid chunks,
## as in ForestWalls; no per-house node or body, no running RNG.
##
## The pinned reduction holds 2 839 footprints (2 828 B0, 1 B1, 6 B2,
## 1 B3, 3 B4), 750 mapped poles and 151 residential polygons. q4 dropped
## residential from landcover.json: buildings.py recovers its original ways.
## The 22 economy records remain distinct, including E1/E3 at one OSM way.
## E11 shifts 8 + 4*hash_unit(osm,"booth_offset") metres away from the
## nearest R17 centreline. B9's missing booth footprint uses half the B6
## canopy footprint; E8 uses its recorded bounds. No invented OSM footprint.
##
## Dimensions named by the catalogue are read there. The brief supplies
## 3 m/storey, two default storeys, 800 m selection, ±10 m F9 stagger and
## 0–2 cars/100 m. Unspecified asset detail is proportional construction:
## posts/canopy/kiosk fractions of B6, F4 twice a two-storey house, parked
## cars one third of B6. Named colours translate to restrained albedos here.
## B0 uses the actual footprint; only footprints exceeding its 60-triangle
## budget lose least-area corners, measured in shell metadata, never in the
## source file. Roof halves are clipped at the ridge and triangulated.
##
## F1 is rule-placed on the 92 loop segments, BOTH sides, visual only.
## Collision is deferred to the driver's ruling: the frozen bubble drive
## crosses the paved edge towards a tree 11 m out. We retain continuous
## visual rails (no collision cannot stop that drive); the report measures
## their crossing. R15 strips are visual concrete edges, 0.12 m from R15;
## the cross-section itself remains the road builder's responsibility.
## F14 has no recorded run-off data; F10's board reuse is unresolved;
## F2/F3/F5/F6 are not placed. OSM barriers are reported counts only.

const PATH := "res://data/regions/eifel_ring/buildings.json"
const CHUNK_M := ForestWalls.CHUNK_M
const STOREY_M := 3.0 # 4B-8 placement brief
const DEFAULT_LEVELS := 2.0
const VILLAGE_M := 800.0
const STAGGER_M := 10.0
const PARK_SPAN_M := 100.0
const PARK_MAX := 2 # ring-region-decisions §5
const BOOTH_OFFSET_MIN := 8.0
const BOOTH_OFFSET_MAX := 12.0

var build_deferred := false
var road: RoadBuilder
var terrain: TerrainBuilder
var profile: WorldRoadProfile
var data := {}
var catalogue := {}
var counts := {}
var elements := {}
var shells: Array[Dictionary] = []
var props: Array[Dictionary] = []
var rail_posts: Array[Dictionary] = []
var kerb_segments: Array[String] = []
var bodies: Array[StaticBody3D] = []
var boxes := PackedFloat64Array()
var bubble: PhysicsBubble
var build_ms := 0
var _jobs: Array[MeshJob] = []
var _residential: Array[Dictionary] = []
var _material: StandardMaterial3D
var _segments := {}
var _loop: PackedStringArray
var _roads := {}

class MeshJob:
	extends RefCounted
	var name: String
	var element: String
	var solid := false
	var members: Array[Dictionary] = []
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var faces := PackedVector3Array()
	var triangles_by_id := {}
	var box := PackedFloat64Array([INF, INF, -INF, -INF])

static func of(scene: Node) -> BuildingsShells:
	var existing := scene.get_node_or_null("Buildings") as BuildingsShells
	if existing != null:
		return existing
	var r := scene.get_node_or_null("Road") as RoadBuilder
	var t := scene.get_node_or_null("Terrain") as TerrainBuilder
	if r == null or t == null or not scene.get_node_or_null("Forest") is ForestWalls:
		return null
	var node := BuildingsShells.new()
	node.name = "Buildings"
	node.road = r
	node.terrain = t
	scene.add_child(node)
	return node

func _ready() -> void:
	if build_deferred:
		return
	if terrain == null or terrain.profile == null:
		push_error("BuildingsShells: no terrain profile")
		return
	var started := Time.get_ticks_msec()
	prepare(terrain.profile)
	place()
	for job: MeshJob in mesh_jobs():
		run_job(job)
	for job: MeshJob in mesh_jobs():
		add_job(job)
	finish_build(started)

static func read_buildings(path: String = PATH) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("BuildingsShells: missing %s" % path)
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func validate_buildings(raw: Variant) -> PackedStringArray:
	var faults := PackedStringArray()
	if not raw is Dictionary:
		return PackedStringArray(["buildings is not a JSON object"])
	for key: String in ["region", "pipeline_version", "provenance", "counts", "buildings", "poles", "places", "residential", "audit"]:
		if not raw.has(key):
			faults.append("%s missing" % key)
	if raw.get("region") != Buildings.REGION or raw.get("pipeline_version") != 1:
		faults.append("region or pipeline_version differs")
	var provenance: Variant = raw.get("provenance")
	if not provenance is Dictionary or provenance.get("osm_base") != Buildings.PINNED_OSM_BASE:
		faults.append("provenance.osm_base differs from the pinned snapshot")
	else:
		for key: String in ["q5_buildings", "q6_furniture", "q7_castle"]:
			var answer: Dictionary = provenance.get("answers", {}).get(key, {})
			for digest: String in ["answer_sha256", "query_sha256"]:
				var pattern := RegEx.create_from_string("^[0-9a-f]{64}$")
				if pattern.search(str(answer.get(digest, ""))) == null:
					faults.append("provenance.%s.%s is not sha256" % [key, digest])
	var seen := {}
	var classes := {}
	if not raw.get("buildings") is Array:
		faults.append("buildings is not an array")
		return faults
	for record: Variant in raw.buildings:
		if not record is Dictionary:
			faults.append("building is not an object")
			continue
		var id := int(record.get("osm", 0))
		if id <= 0 or seen.has(id):
			faults.append("building %d has invalid/duplicate osm" % id)
		seen[id] = true
		var element := str(record.get("element", ""))
		if not element in ["B0", "B1", "B2", "B3", "B4", "B5"]:
			faults.append("building %d invalid element" % id)
		classes[element] = classes.get(element, 0) + 1
		var fault := TerrainBuilder._ring_fault(record.get("polygon"))
		if fault != "":
			faults.append("building %d polygon: %s" % [id, fault])
		if not TerrainBuilder._is_point(record.get("centroid")):
			faults.append("building %d centroid is not a mm point" % id)
		if not record.get("tags") is Dictionary:
			faults.append("building %d tags is not an object" % id)
	var header: Dictionary = raw.get("counts", {}) if raw.get("counts") is Dictionary else {}
	var header_classes: Dictionary = header.get("classes", {}) if header.get("classes") is Dictionary else {}
	var classes_equal := header_classes.size() == classes.size()
	for id: String in classes:
		classes_equal = classes_equal and header_classes.get(id, -1) == classes[id]
	if not classes_equal or header.get("buildings") != raw.buildings.size():
		faults.append("counts.classes/buildings disagree with records")
	if not raw.get("poles") is Array:
		faults.append("poles is not an array")
	else:
		seen.clear()
		for pole: Variant in raw.poles:
			if not pole is Dictionary or not TerrainBuilder._is_point(pole.get("position")) or pole.get("element") != "F4":
				faults.append("pole has invalid position/element")
				continue
			if int(pole.get("osm", 0)) <= 0 or seen.has(pole.osm):
				faults.append("pole has invalid/duplicate osm")
			seen[pole.osm] = true
		if header.get("poles") != raw.poles.size():
			faults.append("counts.poles disagrees with records")
	if not raw.get("residential") is Array:
		faults.append("residential is not an array")
	else:
		for record: Variant in raw.residential:
			if not record is Dictionary or not record.get("outer") is Array or not record.get("inner") is Array:
				faults.append("residential record has no outer/inner rings")
				continue
			for ring: Variant in record.outer + record.inner:
				var fault := TerrainBuilder._ring_fault(ring)
				if fault != "":
					faults.append("residential polygon: %s" % fault)
		if header.get("residential") != raw.residential.size():
			faults.append("counts.residential disagrees with records")
	if not raw.get("places") is Array:
		faults.append("places is not an array")
	else:
		var named := {}
		for place: Variant in raw.places:
			if not place is Dictionary or not TerrainBuilder._is_point(place.get("position")) or not place.get("name") is String:
				faults.append("place has invalid position/name")
				continue
			named[place.name] = true
		for name_of: String in ["Adenau", "Nürburg", "Breidscheid", "Meuspath", "Herschbroich", "Quiddelbach"]:
			if not named.has(name_of):
				faults.append("place %s missing" % name_of)
	return faults

## Preparation runs on one worker in the loader: static caches are warmed
## on the main thread by warm_catalogue first, no RenderingServer calls.
func warm_catalogue() -> void:
	for id: String in ["B0", "B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8", "B9", "F1", "F2", "F4", "F9", "F15", "R15", "R17"]:
		catalogue[id] = ElementCatalogue.entry(id)
	Buildings.records()
	TerrainBuilder.region_seed()
	SkeletonLoader.segments()
	SkeletonLoader.loop(SkeletonLoader.NORDSCHLEIFE_LOOP)

func prepare(built_profile: WorldRoadProfile) -> void:
	profile = built_profile
	if catalogue.is_empty():
		warm_catalogue()
	var raw: Variant = read_buildings()
	var faults := validate_buildings(raw)
	if not faults.is_empty():
		push_error("BuildingsShells: %s" % "; ".join(faults))
		return
	data = raw
	counts = {"economy": 0, "footprints": 0, "poles": 0, "delineators": 0, "kerb_segments": 0, "parked_cars": 0, "parking_ceiling": 0, "guardrail_posts": 0, "guardrail_spans": 0, "bodies": 0, "meshes": 0, "vertices": 0, "triangles": 0, "simplified_houses": 0}
	for record: Dictionary in data.residential:
		var polygon := polygon_of(record.outer[0])
		_residential.append({"polygon": polygon, "box": polygon_box(polygon)})
	for segment: SkeletonLoader.Segment in SkeletonLoader.segments():
		_segments[segment.id] = segment
	_loop = SkeletonLoader.loop(SkeletonLoader.NORDSCHLEIFE_LOOP).segments
	for r: WorldRoadProfile.Road in profile._roads:
		_roads[r.id] = r

func place() -> void:
	if data.is_empty():
		return
	_place_shells()
	_place_furniture()
	_group_jobs()

static func polygon_of(points: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for p: Array in points:
		result.append(Vector2(p[0], p[1]))
	if result.size() > 1 and result[0] == result[-1]:
		result.remove_at(result.size() - 1)
	return result

static func polygon_box(polygon: PackedVector2Array) -> Rect2:
	var box := Rect2(polygon[0], Vector2.ZERO)
	for p: Vector2 in polygon:
		box = box.expand(p)
	return box

func in_residential(p: Vector2) -> bool:
	for record: Dictionary in _residential:
		if record.box.has_point(p) and Geometry2D.is_point_in_polygon(p, record.polygon):
			return true
	return false

func stone(id: String, key: String) -> float:
	return float(catalogue[id].stone_parameters[key])

func _place_shells() -> void:
	for raw: Dictionary in data.buildings:
		var p := Vector2(raw.centroid[0], raw.centroid[1])
		var polygon := polygon_of(raw.polygon)
		var original := polygon.size()
		if raw.element == "B0":
			# Count BOTH clipped roof halves: a concave footprint may
			# cross the ridge more than twice. Never assume n+2 triangles.
			while _house_triangle_budget(polygon) > int(stone("B0", "tris_max")):
				var least := INF
				var remove := 0
				for i: int in polygon.size():
					var area := absf((polygon[i] - polygon[(i - 1 + polygon.size()) % polygon.size()]).cross(polygon[(i + 1) % polygon.size()] - polygon[i]))
					if area < least:
						least = area
						remove = i
				polygon.remove_at(remove)
		var levels := float(raw.tags.get("building:levels", DEFAULT_LEVELS))
		if levels <= 0.0:
			levels = DEFAULT_LEVELS
		var height := levels * STOREY_M
		if raw.element == "B3":
			height = stone("B3", "height_default_m")
		var shell := {"id": str(int(raw.osm)), "osm": int(raw.osm), "element": raw.element, "position": p, "polygon": polygon, "height": height, "solid": false, "source_corners": original, "removed_corners": original - polygon.size()}
		shells.append(shell)
		counts.footprints += 1
		if original > polygon.size():
			counts.simplified_houses += 1
		_count(raw.element)
	var focus: Dictionary = Buildings.read_file()
	for record: Buildings.Record in Buildings.records():
		var p := record.position()
		var footprint := record.footprint_m()
		if record.shell == "B9":
			if record.element == "E11":
				var closest := Vector2.ZERO
				var distance := INF
				for id: String in _loop:
					var segment: SkeletonLoader.Segment = _segments[id]
					for i: int in range(1, segment.points.size()):
						var q := Geometry2D.get_closest_point_to_segment(p, segment.points[i - 1], segment.points[i])
						if p.distance_squared_to(q) < distance:
							distance = p.distance_squared_to(q)
							closest = q
				p += (p - closest).normalized() * lerpf(BOOTH_OFFSET_MIN, BOOTH_OFFSET_MAX, TerrainBuilder.hash_unit(record.osm_id, "booth_offset"))
				footprint = Buildings.shell_footprint("B6") / 2.0
			else:
				for r: Dictionary in focus.records:
					if r.id == record.id:
						var b: Dictionary = r.bounds
						var lo := SkeletonLoader.wgs84_to_local(b.minlat, b.minlon)
						var hi := SkeletonLoader.wgs84_to_local(b.maxlat, b.maxlon)
						footprint = (hi - lo).abs()
		var polygon := rectangle(p, footprint)
		shells.append({"id": record.id, "osm": record.osm_id, "element": record.shell, "position": p, "polygon": polygon, "height": STOREY_M * DEFAULT_LEVELS, "solid": true, "footprint": footprint, "removed_corners": 0})
		counts.economy += 1
		_count(record.shell)

static func _house_triangle_budget(polygon: PackedVector2Array) -> int:
	var box := polygon_box(polygon)
	var across_x := box.size.x <= box.size.y
	var mid := box.get_center().x if across_x else box.get_center().y
	var result := polygon.size() * 2 + 12 # walls and chimney box
	for side: float in [-1.0, 1.0]:
		result += maxi(0, _clip_roof(polygon, across_x, mid, side).size() - 2)
	return result

static func rectangle(p: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size / 2.0
	return PackedVector2Array([p + Vector2(-half.x, -half.y), p + Vector2(half.x, -half.y), p + half, p + Vector2(-half.x, half.y)])

func _count(id: String) -> void:
	elements[id] = elements.get(id, 0) + 1

## Frame at the actual draped road's chainage; mitred chord normals agree
## with its sweep at corners. F1 posts are sampled every four centreline m, with the final closing bay shorter.
func road_frame(id: String, s: float, offset: float) -> Vector2:
	var r: WorldRoadProfile.Road = _roads[id]
	var c := clampi(r.chain.bsearch(clampf(s, 0.0, r.length), false) - 1, 0, r.chain.size() - 2)
	var a := Vector2(r.xs[c], r.zs[c])
	var b := Vector2(r.xs[c + 1], r.zs[c + 1])
	var tangent := (b - a).normalized()
	var point := a.lerp(b, clampf((s - r.chain[c]) / (r.chain[c + 1] - r.chain[c]), 0.0, 1.0))
	var normal := Vector2(-tangent.y, tangent.x)
	var other := normal
	if is_equal_approx(s, r.chain[c]) and c > 0:
		var before := (a - Vector2(r.xs[c-1], r.zs[c-1])).normalized()
		other = Vector2(-before.y, before.x)
	elif is_equal_approx(s, r.chain[c+1]) and c + 2 < r.chain.size():
		var after := (Vector2(r.xs[c+2], r.zs[c+2]) - b).normalized()
		other = Vector2(-after.y, after.x)
	elif id in _loop and (is_zero_approx(s) or is_equal_approx(s, r.length)):
		var index := _loop.find(id)
		var neighbour_id := _loop[(index + (-1 if is_zero_approx(s) else 1) + _loop.size()) % _loop.size()]
		if _roads.has(neighbour_id):
			var neighbour: WorldRoadProfile.Road = _roads[neighbour_id]
			var k := neighbour.xs.size() - 2 if is_zero_approx(s) else 0
			var direction := Vector2(neighbour.xs[k+1]-neighbour.xs[k], neighbour.zs[k+1]-neighbour.zs[k]).normalized()
			other = Vector2(-direction.y, direction.x)
	var bisector := (normal + other).normalized()
	var stretch := 1.0 / maxf(bisector.dot(normal), 1.0 / RoadBuilder.MAX_MITRE)
	return point + bisector * stretch * offset

func _place_furniture() -> void:
	var spacing := stone("F1", "post_spacing_m")
	var accumulated := 0.0
	for id: String in _loop:
		if not _roads.has(id):
			continue
		var r: WorldRoadProfile.Road = _roads[id]
		# Carry the post phase across segment boundaries. Beams below
		# join consecutive posts, including those on different segments.
		for side: float in [-1.0, 1.0]:
			var offset := side * (r.half_width + stone("R17", "kerb_width_m"))
			var s := ceilf(accumulated / spacing) * spacing - accumulated
			while s < r.length:
				var p := road_frame(id, s, offset)
				rail_posts.append({"road": id, "s": s, "loop_s": accumulated + s, "side": side, "position": p})
				props.append({"element": "F1", "kind": "post", "position": p, "road": id, "s": s})
				counts.guardrail_posts += 1
				s += spacing
		accumulated += r.length
	# One six-triangle folded beam per post bay, INCLUDING across OSM
	# segment boundaries. Two post triangles make exactly eight per bay.
	for side: float in [-1.0, 1.0]:
		var run: Array[Vector2] = []
		for post: Dictionary in rail_posts:
			if post.side == side:
				run.append(post.position)
		for i: int in run.size():
			var a := run[i]
			var b := run[(i+1)%run.size()]
			props.append({"element": "F1", "kind": "beam", "position": (a+b)/2.0, "a": a, "b": b})
			counts.guardrail_spans += 1
	elements.F1 = counts.guardrail_posts
	for pole: Dictionary in data.poles:
		props.append({"element": "F4", "kind": "pole", "position": Vector2(pole.position[0], pole.position[1])})
		counts.poles += 1
		_count("F4")
	var adenau := Vector2.ZERO
	for p: Dictionary in data.places:
		if p.name == "Adenau":
			adenau = Vector2(p.position[0], p.position[1])
	for id: String in _roads:
		var r: WorldRoadProfile.Road = _roads[id]
		var segment: SkeletonLoader.Segment = _segments[id]
		if segment.road_class in ["primary", "secondary"]:
			var s := stone("F9", "spacing_m") / 2.0
			var index := 0
			while s < r.length:
				var at := clampf(s + lerpf(-STAGGER_M, STAGGER_M, TerrainBuilder.hash_unit(segment.osm_way, "delineator:" + id, index)), 0, r.length)
				if not in_residential(road_frame(id, at, 0)):
					for side: float in [-1.0, 1.0]:
						var p := road_frame(id, at, side * (r.half_width + stone("R15", "footway_m")))
						props.append({"element": "F9", "kind": "delineator", "position": p})
						counts.delineators += 1
						_count("F9")
				s += stone("F9", "spacing_m")
				index += 1
		if segment.road_class != "residential":
			continue
		var has_kerb := false
		for k: int in range(1, r.chain.size()):
			var mid := (r.chain[k - 1] + r.chain[k]) / 2.0
			if road_frame(id, mid, 0).distance_to(adenau) > VILLAGE_M:
				continue
			has_kerb = true
			for side: float in [-1.0, 1.0]:
				var a := road_frame(id, r.chain[k - 1], side * r.half_width)
				var b := road_frame(id, r.chain[k], side * r.half_width)
				props.append({"element": "R15", "kind": "kerb", "position": (a + b) / 2.0, "a": a, "b": b})
		if not has_kerb:
			continue
		kerb_segments.append(id)
		counts.kerb_segments += 1
		_count("R15")
		for slot: int in int(floor(r.length / PARK_SPAN_M)):
			var at := (slot + 0.5) * PARK_SPAN_M
			if road_frame(id, at, 0).distance_to(adenau) > VILLAGE_M:
				continue
			counts.parking_ceiling += PARK_MAX
			var mean: float = catalogue.F15.varies.count_per_100_m.default
			var number := mini(PARK_MAX, int(floor(TerrainBuilder.hash_unit(segment.osm_way, "park_count:" + id, slot) * (2.0 * mean + 1.0))))
			for car_index: int in number:
				var side := -1.0 if car_index == 0 else 1.0
				var p := road_frame(id, at, side * (r.half_width + stone("R15", "footway_m")))
				var ahead := road_frame(id, minf(at + 1.0, r.length), side * (r.half_width + stone("R15", "footway_m")))
				props.append({"element": "F15", "kind": "car", "position": p, "heading": (ahead - p).angle()})
				counts.parked_cars += 1
				_count("F15")

func _group_jobs() -> void:
	var groups := {}
	for record: Dictionary in shells + props:
		var p: Vector2 = record.position
		var key := "%s_%d_%d" % [record.element, floori(p.x / CHUNK_M), floori(p.y / CHUNK_M)]
		if not groups.has(key):
			var job := MeshJob.new()
			job.name = key
			job.element = record.element
			groups[key] = job
			_jobs.append(job)
		groups[key].members.append(record)
	groups = {}
	for record: Dictionary in shells:
		if not record.solid:
			continue
		var p: Vector2 = record.position
		var key := "Solids_%d_%d" % [floori(p.x / CHUNK_M), floori(p.y / CHUNK_M)]
		if not groups.has(key):
			var job := MeshJob.new()
			job.name = key
			job.solid = true
			groups[key] = job
			_jobs.append(job)
		groups[key].members.append(record)

func mesh_jobs() -> Array[MeshJob]:
	return _jobs

func run_job(job: MeshJob) -> void:
	for record: Dictionary in job.members:
		if record.has("polygon"):
			var start := job.vertices.size()
			_shell_geometry(job, record)
			if not job.solid:
				job.triangles_by_id[record.id] = (job.vertices.size() - start) / 3
		else:
			_prop_geometry(job, record)
	if job.solid:
		job.faces = job.vertices
		for v: Vector3 in job.faces:
			job.box[0] = minf(job.box[0], v.x)
			job.box[1] = minf(job.box[1], v.z)
			job.box[2] = maxf(job.box[2], v.x)
			job.box[3] = maxf(job.box[3], v.z)

func add_job(job: MeshJob) -> void:
	if job.solid:
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(job.faces)
		var collision := CollisionShape3D.new()
		collision.name = "Shape"
		collision.shape = shape
		var body := StaticBody3D.new()
		body.name = job.name
		body.collision_layer = PhysicsBubble.INACTIVE_LAYER
		body.collision_mask = PhysicsBubble.BODY_MASK
		body.add_child(collision)
		add_child(body)
		bodies.append(body)
		boxes.append_array(job.box)
		counts.bodies += 1
	else:
		for record: Dictionary in job.members:
			if job.triangles_by_id.has(record.get("id")):
				record["triangles"] = job.triangles_by_id[record.id]
		if _material == null:
			_material = StandardMaterial3D.new()
			_material.vertex_color_use_as_albedo = true
			_material.cull_mode = BaseMaterial3D.CULL_DISABLED
			_material.roughness = 1.0
			_material.metallic_specular = 0.0
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = job.vertices
		arrays[Mesh.ARRAY_NORMAL] = job.normals
		arrays[Mesh.ARRAY_COLOR] = job.colours
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, _material)
		mesh.set_meta("element", job.element)
		mesh.set_meta("texture_size_px", 0)
		var instance := MeshInstance3D.new()
		instance.name = job.name
		instance.mesh = mesh
		add_child(instance)
		counts.meshes += 1
		counts.vertices += job.vertices.size()
		counts.triangles += job.vertices.size() / 3
	job.vertices = PackedVector3Array()
	job.normals = PackedVector3Array()
	job.colours = PackedColorArray()
	job.faces = PackedVector3Array()

func finish_build(started: int) -> void:
	bubble = PhysicsBubble.new()
	bubble.name = "Bubble"
	add_child(bubble)
	bubble.attach(road.car if road != null else null, bodies, boxes)
	build_ms = Time.get_ticks_msec() - started

func describe() -> String:
	return "Buildings: %s; elements %s" % [JSON.stringify(counts), JSON.stringify(elements)]

# Geometry uses flat colours; no raster assets, texture sizes are zero
# actual allocations. All shell parts enter the same collision face list:
# B6's open canopy remains open, never a closed proxy across the pumps.
func _tri(job: MeshJob, a: Vector3, b: Vector3, c: Vector3, colour: Color) -> void:
	job.vertices.append_array(PackedVector3Array([a, b, c]))
	if not job.solid:
		var n := (c - a).cross(b - a).normalized()
		job.normals.append_array(PackedVector3Array([n, n, n]))
		job.colours.append_array(PackedColorArray([colour, colour, colour]))

func _quad(job: MeshJob, a: Vector3, b: Vector3, c: Vector3, d: Vector3, colour: Color) -> void:
	_tri(job, a, b, c, colour)
	_tri(job, a, c, d, colour)

func _box(job: MeshJob, p: Vector3, size: Vector3, colour: Color, yaw: float = 0.0) -> void:
	var vertices := PackedVector3Array()
	var basis := Basis(Vector3.UP, yaw)
	for y: float in [0.0, size.y]:
		for v: Vector2 in rectangle(Vector2.ZERO, Vector2(size.x, size.z)):
			vertices.append(p + basis * Vector3(v.x, y, v.y))
	for face: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7], [3, 2, 1, 0]]:
		_quad(job, vertices[face[0]], vertices[face[1]], vertices[face[2]], vertices[face[3]], colour)

func _height(p: Vector2) -> float:
	# Adenau and several economy records extend beyond the DGM lattice.
	# Use the same continuation as Terrain, never place them at sea level.
	return profile.elevation_height(p.x, p.y) if profile.covers(p.x, p.y) else WorldContinuation.height(profile, p.x, p.y)

static func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)

## The named art colours; no bright white albedo competing with the car.
static func tint(name_of: String) -> Color:
	match name_of:
		"plaster": return Color(0.55, 0.53, 0.47)
		"ochre": return Color(0.52, 0.47, 0.35)
		"roof": return Color(0.16, 0.18, 0.21)
		"glass": return Color(0.10, 0.16, 0.21)
		"metal": return Color(0.46, 0.48, 0.49)
		"stone": return Color(0.50, 0.49, 0.44)
		"timber": return Color(0.29, 0.25, 0.20)
	return Color(0.36, 0.36, 0.34)

func _shell_geometry(job: MeshJob, shell: Dictionary) -> void:
	var p: Vector2 = shell.position
	var y := _height(p)
	var polygon: PackedVector2Array = shell.polygon
	var box := polygon_box(polygon)
	var size := box.size
	var h: float = shell.height
	var id: String = shell.element
	var plaster := tint("plaster").lerp(tint("ochre"), TerrainBuilder.hash_unit(shell.osm, "plaster"))
	if id == "B6":
		# Four posts and kiosk + canopy slab. The colour band is the slab's
		# side, a single muted colour, no brand or floating graphic.
		var post := size.y / stone("B6", "posts") / stone("B6", "posts")
		for corner: Vector2 in rectangle(p, size * 0.75):
			_box(job, _v(corner, y), Vector3(post, h, post), tint("metal"))
		_box(job, _v(p, y + h), Vector3(size.x, post, size.y), tint("glass"))
		_box(job, _v(p + Vector2(size.x / 4.0, 0), y), Vector3(size.x / 4.0, h / 2.0, size.y / 2.0), plaster)
		return
	if id == "B4":
		for tier: int in int(DEFAULT_LEVELS + 1):
			_box(job, _v(box.get_center() + Vector2(0, size.y * (tier - 1) / 3.0), y), Vector3(size.x, h * (tier + 1) / 3.0, size.y / 3.0), tint("stone"))
		_quad(job, _v(box.position, y+h), _v(box.position+Vector2(size.x,0),y+h), _v(box.end,y+h),_v(box.position+Vector2(0,size.y),y+h),tint("roof"))
		return
	var pitched := id != "B3"
	var pitch: float = catalogue.B0.varies.roof_pitch_deg.default
	if id == "B1":
		pitch /= 2.0
	elif id in ["B5", "B7", "B8"]:
		pitch /= 4.0
	var across_x := size.x <= size.y
	var mid := box.get_center().x if across_x else box.get_center().y
	var half := (size.x if across_x else size.y) / 2.0
	var slope := tan(deg_to_rad(pitch)) if pitched else 0.0
	var wall := plaster if id in ["B0", "B9"] else tint("stone" if id in ["B2", "B3"] else "timber" if id == "B1" else "cladding")
	for i: int in polygon.size():
		var a := polygon[i]
		var b := polygon[(i + 1) % polygon.size()]
		_quad(job, _v(a, y), _v(b, y), _v(b, y+h+_roof_rise(b, across_x, mid, half, slope)), _v(a, y+h+_roof_rise(a, across_x, mid, half, slope)), wall)
	var halves: Array[PackedVector2Array] = [polygon]
	if pitched:
		halves = [_clip_roof(polygon, across_x, mid, -1), _clip_roof(polygon, across_x, mid, 1)]
	for part: PackedVector2Array in halves:
		var indices := Geometry2D.triangulate_polygon(part)
		for i: int in range(0, indices.size(), 3):
			var a := part[indices[i]]
			var b := part[indices[i+1]]
			var c := part[indices[i+2]]
			_tri(job,_v(a,y+h+_roof_rise(a,across_x,mid,half,slope)),_v(b,y+h+_roof_rise(b,across_x,mid,half,slope)),_v(c,y+h+_roof_rise(c,across_x,mid,half,slope)),tint("roof") if id != "B3" else wall)
	if id == "B0":
		var chimney := minf(size.x, size.y) / 8.0
		_box(job, _v(box.get_center(), y+h+half*slope), Vector3(chimney, STOREY_M / 2.0, chimney), tint("stone"))
	elif id == "B2":
		var tower := minf(size.x, size.y) / 2.0
		var centre := box.get_center() + Vector2(0, size.y / 4.0)
		_box(job, _v(centre,y), Vector3(tower,h*2.0,tower),wall)
		var corners := rectangle(centre,Vector2.ONE*tower)
		for i: int in 4:
			_tri(job,_v(corners[i],y+h*2),_v(corners[(i+1)%4],y+h*2),_v(centre,y+h*2+tower),tint("roof"))
	elif id in ["B7", "B8", "B9"]:
		var front := box.position.y - stone("R15", "kerb_height_m") / 2.0
		var left := box.position.x + size.x / 8.0
		var right := box.end.x - size.x / 8.0
		var bottom := y + (h / 2.0 if id == "B9" else 0.0)
		var top := y + h * 0.75
		_quad(job,Vector3(left,bottom,front),Vector3(right,bottom,front),Vector3(right,top,front),Vector3(left,top,front),tint("glass") if id == "B8" else tint("metal"))

static func _roof_rise(p: Vector2, across_x: bool, mid: float, half: float, slope: float) -> float:
	return maxf(0.0, half - absf((p.x if across_x else p.y) - mid)) * slope

static func _clip_roof(polygon: PackedVector2Array, across_x: bool, mid: float, side: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i: int in polygon.size():
		var a := polygon[i]
		var b := polygon[(i+1)%polygon.size()]
		var da := ((a.x if across_x else a.y) - mid) * side
		var db := ((b.x if across_x else b.y) - mid) * side
		if da >= 0:
			out.append(a)
		if (da > 0 and db < 0) or (da < 0 and db > 0):
			out.append(a.lerp(b, da / (da-db)))
	return out

func _prop_geometry(job: MeshJob, prop: Dictionary) -> void:
	var p: Vector2 = prop.position
	var y := _height(p)
	var height := stone("F9", "height_m")
	var thin := stone("R15", "kerb_height_m")
	match prop.kind:
		"pole":
			var h := STOREY_M * DEFAULT_LEVELS * 2.0
			_box(job,_v(p,y),Vector3(thin,h,thin),tint("timber"))
			_box(job,_v(p,y+h-height),Vector3(STOREY_M,thin,thin),tint("timber"))
		"delineator", "post":
			var h := height if prop.kind == "delineator" else height * 0.75
			_quad(job,Vector3(p.x-thin/2,y,p.y),Vector3(p.x+thin/2,y,p.y),Vector3(p.x+thin/2,y+h,p.y),Vector3(p.x-thin/2,y+h,p.y),tint("plaster") if prop.kind == "delineator" else tint("metal"))
			if prop.kind == "delineator":
				_quad(job,Vector3(p.x-thin/2,y+h-thin,p.y-thin/4),Vector3(p.x+thin/2,y+h-thin,p.y-thin/4),Vector3(p.x+thin/2,y+h,p.y-thin/4),Vector3(p.x-thin/2,y+h,p.y-thin/4),tint("roof"))
		"beam":
			var a: Vector2 = prop.a
			var b: Vector2 = prop.b
			var normal := Vector2(-(b-a).y,(b-a).x).normalized()
			# Three folds = six triangles, plus one post quad = eight
			# per full 4 m bay. Extra corner cuts only trace the spline.
			var levels := [height/2, height*0.625, height*0.75, height*0.875]
			var ya := _height(a)
			var yb := _height(b)
			for k: int in 3:
				var lo := normal * (thin / 2.0 if k%2 == 0 else 0.0)
				var hi := normal * (thin / 2.0 if k%2 == 1 else 0.0)
				_quad(job,_v(a+lo,ya+levels[k]),_v(b+lo,yb+levels[k]),_v(b+hi,yb+levels[k+1]),_v(a+hi,ya+levels[k+1]),tint("metal"))
		"kerb":
			var a: Vector2 = prop.a
			var b: Vector2 = prop.b
			var normal := Vector2(-(b-a).y,(b-a).x).normalized() * thin
			var ya := _height(a)
			var yb := _height(b)
			_quad(job,_v(a,ya),_v(b,yb),_v(b,yb+thin),_v(a,ya+thin),tint("stone"))
			_quad(job,_v(a,ya+thin),_v(b,yb+thin),_v(b+normal,yb+thin),_v(a+normal,ya+thin),tint("stone"))
		"car":
			var size := Buildings.shell_footprint("B6") / 3.0
			var yaw: float = -prop.heading
			_box(job,_v(p,y),Vector3(size.x,height,size.y/2.0),tint("cladding"),yaw)
			_box(job,_v(p,y+height),Vector3(size.x/2,height/2,size.y/2.0),tint("glass"),yaw)
