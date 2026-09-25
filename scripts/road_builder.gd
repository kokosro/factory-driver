class_name RoadBuilder
extends Node3D
## The Ring's road as geometry: every drape-covered skeleton segment swept
## into a strip mesh with a trimesh collider, built headless in _ready from
## the checked-in files (implementation-plan.md §4B-4; the elements of
## element-library.md: R17 the circuit strip, R9 the banked cross-section
## at the Karussell, R18 the pit lane and access links as plain strips). No
## bake step, no editor.
##
## THE SURFACE IS THE FIELD. The car reads the road only through its
## injected profile (implementation-plan.md §2.2: sample_height under each
## wheel, ramp_gradient under the centre), so the mesh has to be that field
## and nothing beside it: every vertex's height is asked of the
## WorldRoadProfile at the vertex's own (x, z) - the platform, the other
## road where one is nearer (a junction, a layer crossing: the profile's
## single-valued step shows in the mesh as it is felt in the car). Between
## the vertices the mesh is linear, so the cross-sections stand at every
## breakpoint of the field along the road: the drape's 2 m stations (the
## centre height is linear between them), every skeleton point (the
## crossfall is linear between them), and the chainages where the crossfall
## crosses 0 or ±CROWN (the crown's share kinks there): along an edge the
## field is then exactly linear from one section to the next. Across a quad
## the field is bilinear (centre(s) + b(s) × offset) and a triangle pair
## twists off it by Δb × half width / 4 at the quad's centre, so an interval
## is split into as many pieces as hold that under MESH_TOLERANCE_M -
## computed from the crossfall, not probed (the predecessor's recursive
## probing asked the profile millions of times: minutes, not seconds).
## Each section is a mitred cross-section (the bisector at a kink, stretched
## by 1 / cos of half the kink so the edges stay at the paved half width),
## the geometry read from the files as 64-bit floats and chained by
## WorldRoadProfile.chainages, never through SkeletonLoader.Segment.points
## (single precision: 1.2 mm per mantissa step 20 km from the origin).
##
## chosen for the ring build:
##   * the mesh carries the paved platform only (2 × half width): the blend
##     band is terrain and the lattice ground is a later dressing pass
##     (4B-7); nothing is faked beyond the edge;
##   * the vertex heights come from the profile, not from a parallel copy of
##     its rules; the tests hold them to sample_height;
##   * one MeshInstance3D and one StaticBody3D per road (the renderer culls
##     per strip; one trimesh per road keeps each shape small);
##   * the trimesh colliders sit on ROAD_COLLISION_LAYER with an empty
##     mask, a layer the car's mask (1) does not include: the CharacterBody3D
##     stays upright (car.gd's road notes: pitch and roll are the body's on
##     it) and its box, GROUND_CLEARANCE over the road, would be shoved by a
##     true trimesh on any grade past ~5 % (0.12 m over the 2.1 m to the
##     box's end). The car stands on the profile, as the plan's seam says,
##     and meets the road the way it meets the pad: one level floor put
##     under it every tick at the profile's height (test_pad.gd's
##     _follow_car; the pad's proven arrangement - a level follower under
##     the car, the profile's heights through the springs - carried onto
##     sloped chords; the floor reads the SAME corrected profile the mesh
##     and the car read, no third height source; Conductor-approved
##     2026-09-23), what its underside finds bottomed out and what stops a
##     car with no springs from falling through the world - here a slab
##     (FLOOR_SIZE_M square, FLOOR_THICKNESS_M thick, its top at the road),
##     not the pad's endless WorldBoundaryShape3D: the physics server takes
##     a moved static body's place at its next step, so the floor is where
##     the car WAS for one tick, and a car reset onto lower ground (R after
##     a climb, the test's stands) sits inside a half-space for that tick
##     and is ejected up to it (measured: 69 m). A slab left behind on the
##     old ground is not under the car at all. The trimesh is the road's
##     physical surface for everything else and for what comes later;
##   * THE LOOP'S RIGHT OF WAY at layer crossings: the field is single-
##     valued (world_road_profile.gd's header: the nearest centreline
##     answers), so where a road passes under or over the loop the field
##     steps to that road's height inside the loop's paved width - measured
##     on the loop, ten crossings, steps of 1.6-6.2 m against the corrected
##     loop (a track bridge over
##     Antoniusbuche +2.88 m at 1 901 m from Döttinger Höhe stopped the
##     test drive dead; the tunnel under the Döttinger Höhe straight -2.76
##     m; the roads under the five loop bridges -1.8 to -6.0 m). The car
##     reads sample_height(x, z) alone and the profile has no hint which
##     road it is on, so no pure rule serves both roads; the loop is the
##     deliverable: every covered road off the loop whose centreline
##     overlaps the loop's platform at another height is uncovered in the
##     parsed drape (apply_right_of_way, after the rim rule, before the
##     profile) - those ten are the crossing structures themselves, 18-94 m
##     each, about 450 m of side road in all, not built this iteration; an
##     underpass or deck element is a later pass, and until then a side
##     road simply reaches its junction with the loop. A crossing between
##     two roads off the loop stays as it is: the single-valued field's
##     recorded known issue, not this iteration's. Recorded in
##     `crossings`, listed by the test; chosen for the ring build,
##     confirmed by the orchestrator 2026-09-23 (a measured obstacle, the
##     alternative in a frozen file, a goal-honouring transform), the
##     Conductor may veto with a trivial revert;
##   * THE RIM RULE for the bridge approaches (the Conductor's ruling on
##     4B-3's known issue; drape.json stays byte-identical, the rule is
##     applied to the PARSED data here before the profile is built, so the
##     car and the mesh carry the same heights): the DGM1 is a ground model
##     with the bridges removed and its hole reaches past the OSM bridge
##     way's ends, so a bridge's own abutment samples and the untagged
##     approach's last metres sit on the valley floor (Breidscheid: the
##     approach falls 338.76 → 334.20 over its last 8 m at 62-65 %, the deck
##     334.20 → 332.94, the next approach climbs 332.94 → 337.00 over 8 m at
##     50 %). The ruling's own wording - "extend the deck where its linear
##     extension sits > 1 m above the approach ground" - measured false at
##     every loop bridge: the abutment samples ARE the hole's floor, the
##     deck's extension lies below the ground everywhere. What the ruling
##     requires all the same is that the 64 % spike resolve, and this rule
##     honours it; Conductor-endorsed 2026-09-23, amendment 1 of the bridge
##     fix ("my ruling's literal
##     mechanism had a false premise - I presumed deck-above-hole; the
##     loop's abutments ARE hole floors, the V drops to them - while the
##     same ruling's explicit requirement 'the 64.4 % slope spike must
##     resolve' stands. The rim rule honors it honestly: straight deck
##     between the first 20 % rims, lift-only, 50 m cap, 2-segment junction
##     walk, pure function of the parsed data, applied before
##     WorldRoadProfile.from_data so mesh and car drive one corrected
##     field, drape.json byte-identical, 41226730-0 deliberately untouched
##     with its below-ground instance recorded as the reading the rule does
##     not take"): from each end of a covered
##     bridge, walk outward along untagged covered approach segments,
##     through junctions along the best-continuing segment (amendment 2
##     below), at most APPROACH_REACH_M; the RIM
##     is the first outward station after which the onward station-to-
##     station slope stays under RIM_SLOPE for the next
##     RIM_LOOKAHEAD_STATIONS stations (the hole's walls climb 50-65 % per
##     metre, their tails 14.5 %, the loop's honest grades top at 15.8 %;
##     was the first station whose ONE onward slope is under 0.20 -> 0.08
##     over two stations, the ROAD-GEOMETRY FIX-NOW landing after
##     docs/issues-analysis-2026-09-24.md §4.3: the 20 % criterion sat the
##     rim at the foot of the hole-wall's 14.5 % tail and left its crest,
##     a 25-point crest in 3 m that launched the car 0.750 m at 30 m/s at
##     Döttinger Höhe (issue 0020) and a sag-then-crest at Breidscheid's
##     east rim (issue 0011); measured on this tree, the rims move
##     683303211-0 6.00 -> 8.00 m out (553.97 -> 554.26: the deck line
##     -1.1 -> -0.7 % meeting the approach's -1 %, the grade change per
##     metre 11.8 -> 0.9 %), 683006908-0 8.00 -> 10.00 m (337.00 ->
##     337.29: Breidscheid's line -5.14 -> -4.06 % meeting -5.0 %, 12.7 ->
##     under 5 %/m), Hohenrain's west rim 7.49 -> 9.49 m and its east
##     8.13 (was 4.13) m along the T13 continuation, 41395652-0's west
##     2.21 -> 4.21 m; the Breidscheid west rim 8.44 m / 338.76 m and
##     41395673-0's east 8.00 m / 627.42 m unchanged; 15 bridges lifted,
##     was 13 - every one of the 13 still lifts, 41795617-0 (a track
##     crossing under the loop the right of way uncovers again) and
##     827648314-0 (a track, 0.237 m) join; no loop station at 20 % or
##     more, as before; the doc's ~0.05 measured too - it walks over the
##     west Breidscheid approach's honest 4.0-5.5 % climb to 16.44 m out
##     and moves a rim the doc expects unchanged, so 0.08); the deck is
##     drawn straight
##     between the two rims and every station of the bridge and of the
##     approaches between the rims that lies below that line is lifted onto
##     it - never lowered, so never below the abutment samples. An end whose
##     abutment already climbs under RIM_SLOPE for the look-ahead is its
##     own rim (nothing moves
##     there); an end whose walk finds no rim within reach (a tagged or
##     uncovered segment, no continuation, the reach) has no rim, and a
##     bridge with such an end is not lifted at all - nothing where no rim
##     is found (the endorsed rule; the codex review of 4B-4 found the
##     unfound end's abutment serving as the line's end, 134220315-0's
##     lift drawn to it, and the walk taking a two-segment junction's
##     other segment before the turn filter: both fixed, the filter the
##     same at every junction). AMENDMENT 2, Conductor-endorsed 2026-09-23: the walk
##     may continue THROUGH a junction of three or more along the outgoing
##     covered untagged segment whose direction best continues the
##     incoming heading (a turn of CONTINUATION_MAX_TURN_DEG at most), the
##     same rim, the same 50 m, lift-only as before - measured first with
##     two-segment junctions only, Hohenrain's 41395668-0 east end kept a
##     59 % wall: its approach 41395670-0 is 4.1 m long and ends at the
##     four-way T13 junction still climbing at 54-60 %, and "leaving a
##     ~60 % wall on the loop is a data artifact the canon forbids the car
##     to feel; the walk's 2-segment-junction limit was a simplicity choice,
##     not physics" (the Conductor) - the junction's arity, not the road's
##     shape, was all that stopped the walk. 41226730-0 (the codex review's
##     instance,
##     its deck 1.472 m under the DEM at chainage 94): its one approach
##     climbs away at 1-2 %, its other end stands at a junction the rule
##     does not walk through; nothing changes there - the rule does not
##     govern a deck under the ground. Known issue left: the blend band
##     beside a lifted approach still eases into the RAW lattice, which
##     holds the hole, so a lip can stand at a hole's mouth off the paved
##     width until the terrain pass.

## The road colliders' layer (bit 2) and mask (none): see the header.
const ROAD_COLLISION_LAYER := 2
const ROAD_COLLISION_MASK := 0

## The floor slab under the car (see the header): its side [m] and its
## thickness [m]; its top is at the road's height under the car.
const FLOOR_SIZE_M := 40.0
const FLOOR_THICKNESS_M := 0.1

## How far the mesh may interpolate off the field inside a quad [m]: the
## twist bound Δb × half width / 4 is held under it by splitting the
## interval into as many pieces as that takes; an interval split finer
## than MIN_SECTION_M [m] between sections is counted (fine_split_count).
const MESH_TOLERANCE_M := 0.001
const MIN_SECTION_M := 0.05

## Two chainages closer than this are one section [m].
const SAME_CHAINAGE_M := 1e-6

## A mitred corner's reach is capped at this multiple of the half width
## (a kink of 120° or more: a service road turning back on itself).
const MAX_MITRE := 2.0

## The rim rule (see the header): the rim is the first outward station
## after which the onward station-to-station climb stays under RIM_SLOPE
## [rise over run] for the next RIM_LOOKAHEAD_STATIONS stations (2 m
## each: 4 m), and the walk from a bridge's end goes at most
## APPROACH_REACH_M along the approaches [m]. was RIM_SLOPE 0.20 with no
## look-ahead -> 0.08 with two (the ROAD-GEOMETRY FIX-NOW landing,
## docs/issues-analysis-2026-09-24.md §4.3: the DGM1 hole-wall's tail
## climbs at 14.5 % over its last 2 m and ends in a labelled crest onto
## honest ground; 14.5 % is under 20 %, so the rim sat at the foot of the
## tail and the car was launched over the crest - issue 0020, 0.750 m of
## air at 30 m/s at Döttinger Höhe, issue 0011's sag-then-crest at
## Breidscheid's east rim. The doc's ~0.05 was measured too: the west
## Breidscheid approach 683061814-1 climbs away from the hole at an honest
## 4.0-5.5 % per station, so 0.05 walks over it to 16.44 m out and moves
## a rim the doc expects unchanged; 0.08 sits between the loop's honest
## grades at a rim (5.5 % there) and the tails (14.5 %) - the look-ahead
## is what separates a 2 m tail from a hill).
const RIM_SLOPE := 0.08
const RIM_LOOKAHEAD_STATIONS := 2
const APPROACH_REACH_M := 50.0
## Amendment 2 (see the header): at a junction of three or more the walk
## follows the covered untagged segment that best continues the incoming
## heading, turning no more than this [deg].
const CONTINUATION_MAX_TURN_DEG := 60.0

## The loop's right of way (see the header): a covered road off the loop
## that shares no junction with it, on another OSM layer (its `layer` tag
## against the loop segment's, 0 untagged), whose centreline passes within
## half a station of a loop station (CROSSING_DISTANCE_M: a centreline that
## crosses the loop's passes within a metre of one of its 2 m stations; a
## road running beside the loop does not) at a centre height more than
## CROSSING_HEIGHT_M apart, crosses the loop and is uncovered. Each test
## alone over-matches: the pit lane beside T13 lies on another layer 8 m
## away, the GP links join the T13 junction on another layer at the hole's
## floor. The height [m]: the loop's true layer crossings measured 1.6 to
## 6.0 m; a grade join (the Döttinger Höhe access, the pit lane) shares the
## loop's height at the junction and sits under it.
const CROSSING_DISTANCE_M := 1.0
const CROSSING_HEIGHT_M := 0.5

## The asphalt: the pad's texture at this size and seed, tinted the
## canon's medium cool grey, repeated every UV_METRES [m] along and across.
const ASPHALT_TEXTURE_SIZE := 256
const ASPHALT_TEXTURE_SEED := 4
const ASPHALT_TINT := Color(0.46, 0.47, 0.5, 1.0)
const UV_METRES := 4.0

## Where the car is; given the profile once it is built (as TestPad hands
## the pad's to a car without one), and followed by the floor.
@export var car: ArcadeCar

## The profile the road was built from: the car's, after _ready.
var profile: WorldRoadProfile

## The parsed files the build read: the skeleton as it is, the drape after
## the rim rule (what the profile was built from).
var skeleton_data: Dictionary = {}
var drape_data: Dictionary = {}

## What the rim rule did, one entry per covered bridge it changed (see
## apply_rim_rule), and what the loop's right of way did, one entry per
## crossing structure uncovered (see apply_right_of_way).
var lifts: Array[Dictionary] = []
var crossings: Array[Dictionary] = []

## The built strips by segment id, and the build's numbers: wall time
## [ms], roads swept, cross-sections placed (of which the twist bound added
## `splits`), vertices, triangles, bodies.
var strips: Dictionary = {}
var build_ms := 0
var road_count := 0
var section_count := 0
var split_count := 0
var fine_split_count := 0
var vertex_count := 0
var triangle_count := 0
var body_count := 0

var _material: StandardMaterial3D
var _floor: StaticBody3D


## One road's strip: the cross-sections' chainages [m], the offsets across
## [m, right of travel positive] every section carries a vertex at, the
## vertices (section-major: section k's are k × offsets.size() ..), the
## triangle indices, and the nodes that show and carry it.
class Strip:
	extends RefCounted
	var id: String
	var chainages: PackedFloat64Array
	var offsets: PackedFloat64Array
	var vertices: PackedVector3Array
	var indices: PackedInt32Array
	var mesh_instance: MeshInstance3D
	var body: StaticBody3D

	## The vertex of section `k` at offset index `i`.
	func vertex(k: int, i: int) -> Vector3:
		return vertices[k * offsets.size() + i]


## The road as the sweep needs it: the 64-bit centreline and its chainage,
## the crossfall per point, the half width, the bank if it has one, and the
## offsets across every section carries a vertex at.
class Road:
	extends RefCounted
	var id: String
	var xs: PackedFloat64Array
	var zs: PackedFloat64Array
	var chain: PackedFloat64Array
	var length: float
	var half_width: float
	var crossfall: PackedFloat64Array
	var bank: bool = false
	var offsets: PackedFloat64Array


func _ready() -> void:
	# The floor is put under the car before the car's own step each tick
	# (see _follow_car): a reset onto lower ground would otherwise leave
	# the plane over the car for a tick and eject it.
	process_physics_priority = -1
	# A reset stands the car somewhere new: the floor follows it the same
	# tick (ArcadeCar.reset_performed; the codex cross-review's F1,
	# ROAD-SIDE RESET MEMORY, 2026-09-24: the road-side reset memory broke
	# the slab's old assumption that a slab left behind on the old ground is
	# never under the car - a reset to a pose recorded near where the car was
	# put can land it inside the stale slab's 40 m footprint and the field
	# under it can be higher than the destination's road).
	if car != null:
		car.reset_performed.connect(_follow_car)
	build()


func _physics_process(_delta: float) -> void:
	_follow_car()


## Reads the files, applies the rim rule, builds the profile, the strips
## and the floor; hands the car the profile. Refuses (push_error, nothing
## built) when a file is missing or not JSON: a scene that says so beats
## one that drives on nothing.
func build() -> void:
	var started := Time.get_ticks_msec()
	var skeleton: Variant = SkeletonLoader.read_file()
	var drape: Variant = WorldRoadProfile.read_file()
	if not skeleton is Dictionary or not drape is Dictionary:
		push_error("RoadBuilder: the skeleton or the drape is missing or not JSON (%s, %s)" % [SkeletonLoader.PATH, WorldRoadProfile.PATH])
		return
	skeleton_data = skeleton
	var ruled := apply_rim_rule(skeleton, drape)
	lifts = ruled.lifts
	var cleared := apply_right_of_way(skeleton, ruled.drape)
	drape_data = cleared.drape
	crossings = cleared.crossings
	profile = WorldRoadProfile.from_data(skeleton_data, drape_data)
	if car != null:
		car.road_profile = profile
		# The world's R: the last pose recorded with all four wheels on the
		# road, not the pit (ArcadeCar.reset_car; the user's complaint,
		# 2026-09-23: R sent the car back to the pit spawn 5 km in). Set here,
		# beside the profile, the one place a scene hands the car a
		# WorldRoadProfile - the profile with the on-road query the recording
		# reads (describe) - so the flag cannot drift from the road it needs;
		# main.tscn's pad has no RoadBuilder and keeps its start-line reset.
		car.reset_to_last_pose = true
	_material = _asphalt_material()
	var segments := SkeletonLoader.segments_of(skeleton_data)
	var raw_points := _raw_points_of(skeleton_data)
	for raw: Variant in drape_data.get("segments", []):
		if not raw is Dictionary or not raw.get("covered", false) or not segments.has(raw.get("id")):
			continue
		var road := _road_of(raw, segments[raw.id], raw_points[raw.id])
		if road == null:
			continue
		var strip := _sweep(road)
		_add_nodes(strip)
		strips[strip.id] = strip
		road_count += 1
		section_count += strip.chainages.size()
		vertex_count += strip.vertices.size()
		triangle_count += strip.indices.size() / 3
		body_count += 1
	_add_floor()
	build_ms = Time.get_ticks_msec() - started


## The strip of the road with this id, or null.
func strip(id: String) -> Strip:
	return strips.get(id)


## One line on what was built: the counts (the wall time is build_ms, kept
## apart so the suite's line is the same on every machine).
func describe() -> String:
	return "%d roads, %d sections (%d added by the twist bound), %d vertices, %d triangles, %d bodies" % [road_count, section_count, split_count, vertex_count, triangle_count, body_count]


# =============================================================================
#  THE SWEEP
# =============================================================================

## The road from its drape record, its skeleton segment and its raw
## points; null when the record is not one the profile would hold (the
## profile refuses the same: a missing height, a misaligned crossfall).
func _road_of(raw: Dictionary, segment: SkeletonLoader.Segment, points: Array) -> Road:
	var road := Road.new()
	road.id = segment.id
	road.xs = PackedFloat64Array()
	road.zs = PackedFloat64Array()
	for point: Variant in points:
		road.xs.append(float(point[0]))
		road.zs.append(float(point[1]))
	road.chain = WorldRoadProfile.chainages(road.xs, road.zs)
	road.length = road.chain[road.chain.size() - 1]
	if road.length <= 0.0:
		return null
	for h: Variant in raw.get("dense", []):
		if not (h is float or h is int):
			return null
	road.crossfall = PackedFloat64Array()
	for e: Variant in raw.get("crossfall", []):
		road.crossfall.append(float(e) if (e is float or e is int) else 0.0)
	if road.crossfall.size() != road.xs.size():
		return null
	road.half_width = segment.width_m * 0.5
	# R17 / R18: the edge, the crown line, the edge. R9: the edge, the
	# strip's end (where the bank's bowl begins: the field's kink), the
	# edge - the bank rises to the side the crossfall says.
	road.offsets = PackedFloat64Array([-road.half_width, 0.0, road.half_width])
	for label: Variant in raw.get("labels", []):
		if label is Dictionary and label.get("kind") == "bank":
			road.bank = true
			var strip_edge := float(label.get("strip_m", 0.0)) - road.half_width
			road.offsets[1] = strip_edge if road.crossfall[0] >= 0.0 else -strip_edge
	return road


## The skeleton's points as 64-bit pairs by segment id.
func _raw_points_of(skeleton: Dictionary) -> Dictionary:
	var found := {}
	for raw: Variant in skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String and raw.get("points") is Array:
			found[raw.id] = raw.points
	return found


func _sweep(road: Road) -> Strip:
	var chainages := _section_chainages(road)
	var across := road.offsets.size()
	var strip := Strip.new()
	strip.id = road.id
	strip.chainages = chainages
	strip.offsets = road.offsets
	strip.vertices = PackedVector3Array()
	strip.vertices.resize(chainages.size() * across)
	var cursor := 0
	for k: int in chainages.size():
		var s := chainages[k]
		while cursor < road.xs.size() - 2 and road.chain[cursor + 1] <= s + SAME_CHAINAGE_M:
			cursor += 1
		var frame := _frame(road, s, cursor)
		for i: int in across:
			# The vertex as the mesh stores it (single precision), its height
			# the field's at that stored point: at a layer crossing two
			# centrelines tie within a fraction of a millimetre and the
			# answer flips by metres, so the sample has to be taken where the
			# vertex is, not where it was computed.
			var vertex := Vector3(frame[0] + frame[2] * road.offsets[i], 0.0, frame[1] + frame[3] * road.offsets[i])
			vertex.y = profile.sample_height(vertex.x, vertex.z)
			strip.vertices[k * across + i] = vertex
	# Two triangles per quad, the diagonal from (section k, offset i) to
	# (section k + 1, offset i + 1). Wound as the pad's ground is
	# (test_pad.gd's _build_ground_mesh): along, then across to the right.
	strip.indices = PackedInt32Array()
	strip.indices.resize((chainages.size() - 1) * (across - 1) * 6)
	var next_index := 0
	for k: int in chainages.size() - 1:
		for i: int in across - 1:
			var a := k * across + i
			var b := (k + 1) * across + i
			var c := (k + 1) * across + i + 1
			var d := k * across + i + 1
			strip.indices[next_index] = a
			strip.indices[next_index + 1] = b
			strip.indices[next_index + 2] = c
			strip.indices[next_index + 3] = a
			strip.indices[next_index + 4] = c
			strip.indices[next_index + 5] = d
			next_index += 6
	return strip


## Where the road's cross-sections stand: the field's breakpoints along it
## (the stations, the interior skeleton points, the crossfall's crossings
## of 0 and ±CROWN), sorted and deduplicated, then every interval split
## into as many pieces as keep the quads' twist under MESH_TOLERANCE_M.
func _section_chainages(road: Road) -> PackedFloat64Array:
	var breakpoints := WorldRoadProfile.station_chainages(road.length)
	for i: int in range(1, road.chain.size() - 1):
		breakpoints.append(road.chain[i])
	if not road.bank:
		for i: int in range(1, road.chain.size()):
			var e0 := road.crossfall[i - 1]
			var e1 := road.crossfall[i]
			for level: float in [-WorldRoadProfile.CROWN, 0.0, WorldRoadProfile.CROWN]:
				if (e0 - level) * (e1 - level) < 0.0:
					breakpoints.append(road.chain[i - 1] + (level - e0) / (e1 - e0) * (road.chain[i] - road.chain[i - 1]))
	breakpoints.sort()
	var out := PackedFloat64Array()
	var cursor := 0
	var previous_e := road.crossfall[0]
	for s: float in breakpoints:
		if out.is_empty():
			out.append(s)
			continue
		var previous := out[out.size() - 1]
		if s - previous <= SAME_CHAINAGE_M:
			continue
		while cursor < road.xs.size() - 2 and road.chain[cursor + 1] < s:
			cursor += 1
		var e := _crossfall_on(road, s, cursor)
		if not road.bank:
			var pieces := _twist_pieces(road, previous_e, e, previous, s)
			for p: int in range(1, pieces):
				out.append(previous + (s - previous) * p / pieces)
				split_count += 1
		previous_e = e
		out.append(s)
	return out


## How many pieces an interval whose crossfall runs from e0 to e1 needs
## so a quad's twist, Δb × half width / 4 (b the platform's slope across
## on either side of the crown line: ±e less the crown's share), stays
## under the tolerance; at least one. The count is the tolerance's alone:
## it is not clamped to the interval's length over MIN_SECTION_M (the
## codex review of 4B-4: a 0.05 m interval whose crossfall swings 0.02 ->
## 0.03 on a 4 m half width needs 10 pieces and the clamp returned one,
## 10 mm of twist left in the mesh); an interval split finer than
## MIN_SECTION_M is counted in fine_split_count and reported, not hidden.
func _twist_pieces(road: Road, e0: float, e1: float, s0: float, s1: float) -> int:
	var worst := 0.0
	for side: float in [-1.0, 1.0]:
		var b0 := side * e0 - _crown_share(e0) * WorldRoadProfile.CROWN
		var b1 := side * e1 - _crown_share(e1) * WorldRoadProfile.CROWN
		worst = maxf(worst, absf(b1 - b0))
	var pieces := maxi(ceili(worst * road.half_width / (4.0 * MESH_TOLERANCE_M) - 1e-9), 1)
	if pieces > 1 and (s1 - s0) / pieces < MIN_SECTION_M:
		fine_split_count += 1
	return pieces


## The crown's share of the crossfall shape (WorldRoadProfile's
## _platform_height: the 2 % crown fading out as the superelevation grows).
static func _crown_share(e: float) -> float:
	return 1.0 - minf(absf(e) / WorldRoadProfile.CROWN, 1.0)


## The crossfall at chainage s on chord c: the points' values, linear
## between them (the profile's crossfall_at on the builder's own road).
static func _crossfall_on(road: Road, s: float, c: int) -> float:
	var span := road.chain[c + 1] - road.chain[c]
	var u := 0.0 if span <= 0.0 else clampf((s - road.chain[c]) / span, 0.0, 1.0)
	return lerpf(road.crossfall[c], road.crossfall[c + 1], u)


## The centreline at chainage s on chord c (chain[c] <= s < chain[c + 1],
## or the last chord) and the direction across it: [x, z, nx, nz], n
## pointing to the right of travel ((-tz, tx) in the x-east / z-south
## frame, the profile's own sign). Inside a chord n is the chord's unit
## normal; at an interior skeleton point (s at the chord's start) it is
## the mitre of the two chords' normals (the bisector stretched by 1 / cos
## of half the kink, capped at MAX_MITRE) so the strips' edges meet.
func _frame(road: Road, s: float, c: int) -> PackedFloat64Array:
	var span := road.chain[c + 1] - road.chain[c]
	var u := 0.0 if span <= 0.0 else clampf((s - road.chain[c]) / span, 0.0, 1.0)
	var x := road.xs[c] + u * (road.xs[c + 1] - road.xs[c])
	var z := road.zs[c] + u * (road.zs[c + 1] - road.zs[c])
	var normal := _chord_normal(road, c)
	if c > 0 and absf(s - road.chain[c]) <= SAME_CHAINAGE_M:
		var before := _chord_normal(road, c - 1)
		var after := _chord_normal(road, c)
		var mx := before[0] + after[0]
		var mz := before[1] + after[1]
		var m := sqrt(mx * mx + mz * mz)
		if m > 1e-9:
			var half_cos := (mx * after[0] + mz * after[1]) / m
			var stretch := 1.0 / maxf(half_cos, 1.0 / MAX_MITRE)
			normal = PackedFloat64Array([mx / m * stretch, mz / m * stretch])
	return PackedFloat64Array([x, z, normal[0], normal[1]])


## The unit right normal of chord c; a zero-length chord (the profile
## skips those too) takes its predecessor's, or its successor's at the
## start.
func _chord_normal(road: Road, c: int) -> PackedFloat64Array:
	var k := c
	while k > 0 and road.chain[k + 1] - road.chain[k] <= 0.0:
		k -= 1
	while k + 2 < road.chain.size() and road.chain[k + 1] - road.chain[k] <= 0.0:
		k += 1
	var dx := road.xs[k + 1] - road.xs[k]
	var dz := road.zs[k + 1] - road.zs[k]
	var length := sqrt(dx * dx + dz * dz)
	if length <= 0.0:
		return PackedFloat64Array([1.0, 0.0])
	return PackedFloat64Array([-dz / length, dx / length])


# =============================================================================
#  THE NODES
# =============================================================================

## The strip's MeshInstance3D (normals from its own neighbours, UVs in
## metres) and its StaticBody3D with the same triangles as a trimesh.
func _add_nodes(strip: Strip) -> void:
	var across := strip.offsets.size()
	var sections := strip.chainages.size()
	var normals := PackedVector3Array()
	normals.resize(strip.vertices.size())
	var uvs := PackedVector2Array()
	uvs.resize(strip.vertices.size())
	for k: int in sections:
		var k0 := maxi(k - 1, 0)
		var k1 := mini(k + 1, sections - 1)
		for i: int in across:
			var i0 := maxi(i - 1, 0)
			var i1 := mini(i + 1, across - 1)
			var along := strip.vertex(k1, i) - strip.vertex(k0, i)
			var right := strip.vertex(k, i1) - strip.vertex(k, i0)
			var normal := right.cross(along)
			normals[k * across + i] = normal.normalized() if normal.length_squared() > 0.0 else Vector3.UP
			uvs[k * across + i] = Vector2(strip.offsets[i] / UV_METRES, strip.chainages[k] / UV_METRES)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = strip.vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = strip.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _material)
	strip.mesh_instance = MeshInstance3D.new()
	strip.mesh_instance.name = "Strip_" + strip.id
	strip.mesh_instance.mesh = mesh
	add_child(strip.mesh_instance)
	var faces := PackedVector3Array()
	faces.resize(strip.indices.size())
	for f: int in strip.indices.size():
		faces[f] = strip.vertices[strip.indices[f]]
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	strip.body = StaticBody3D.new()
	strip.body.name = "Body_" + strip.id
	strip.body.collision_layer = ROAD_COLLISION_LAYER
	strip.body.collision_mask = ROAD_COLLISION_MASK
	strip.body.add_child(collider)
	add_child(strip.body)


## The floor the car meets (see the header): one level slab on the car's
## layer, put under the car every tick by _follow_car.
func _add_floor() -> void:
	var collider := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(FLOOR_SIZE_M, FLOOR_THICKNESS_M, FLOOR_SIZE_M)
	collider.shape = slab
	collider.position.y = -0.5 * FLOOR_THICKNESS_M
	_floor = StaticBody3D.new()
	_floor.name = "Floor"
	_floor.add_child(collider)
	add_child(_floor)


## The floor to the profile's height under the car (test_pad.gd's
## _follow_car, the same idea): only the collision shape moves, its top at
## the road under the car's centre. Runs before the car's step
## (process_physics_priority) and takes effect at the server's next step,
## so the slab is where the car stood a tick ago: at most one tick's way
## behind (0.5 m at 30 m/s: 0.1 m of height on a 20 % grade, inside the
## 0.12 m GROUND_CLEARANCE between the level box and the level slab).
func _follow_car() -> void:
	if car == null or _floor == null or profile == null:
		return
	var height := profile.sample_height(car.global_position.x, car.global_position.z)
	var place := Vector3(car.global_position.x, height, car.global_position.z)
	if _floor.position != place:
		_floor.position = place


func _asphalt_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = ASPHALT_TINT
	material.albedo_texture = ImageTexture.create_from_image(AsphaltTexture.build_image(ASPHALT_TEXTURE_SIZE, ASPHALT_TEXTURE_SEED))
	material.roughness = 0.9
	return material


# =============================================================================
#  THE LOOP'S RIGHT OF WAY
# =============================================================================

## The drape with the loop's right of way applied (see the header): a
## dictionary of the drape's keys whose `segments` is a new list, the
## records of the crossing structures replaced by copies marked covered
## false (every other record the same object), and `crossings`: one entry
## per uncovered segment, {id, loop, loop_chainage, distance_m, loop_height,
## height, layer, loop_layer}, in the drape's order. A crossing is a
## covered segment off the loop sharing no junction with it, on another
## layer than the loop segment, whose centreline passes within
## CROSSING_DISTANCE_M of one of its stations with a centre height more
## than CROSSING_HEIGHT_M off the loop's there. A pure function of the
## parsed data.
static func apply_right_of_way(skeleton: Dictionary, drape: Dictionary) -> Dictionary:
	var segments := SkeletonLoader.segments_of(skeleton)
	var loops := SkeletonLoader.loops_of(skeleton)
	var out := drape.duplicate(false)
	var crossings: Array[Dictionary] = []
	if not loops.has(SkeletonLoader.NORDSCHLEIFE_LOOP):
		return {"drape": out, "crossings": crossings}
	var loop: SkeletonLoader.Loop = loops[SkeletonLoader.NORDSCHLEIFE_LOOP]
	var raw_points := {}
	for raw: Variant in skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String and raw.get("points") is Array:
			raw_points[raw.id] = raw.points
	var records := {}
	for raw: Variant in drape.get("segments", []):
		if raw is Dictionary and raw.get("covered", false) and segments.has(raw.get("id")) and raw.get("dense") is Array:
			records[raw.id] = raw
	# The segments joining the loop at a junction.
	var joined := {}
	for junction: SkeletonLoader.Junction in SkeletonLoader.junctions_of(skeleton).values():
		var on_loop := false
		for id: String in junction.segments:
			on_loop = on_loop or loop.segments.has(id)
		if on_loop:
			for id: String in junction.segments:
				joined[id] = true
	# The loop's stations: [x, z, height, chainage, layer].
	var stations: Array[PackedFloat64Array] = []
	var station_ids: PackedStringArray = []
	for id: String in loop.segments:
		if not records.has(id):
			continue
		var geometry := _geometry(raw_points[id])
		var dense: Array = records[id].dense
		var chainages := WorldRoadProfile.station_chainages(geometry.length)
		for k: int in mini(chainages.size(), dense.size()):
			if not (dense[k] is float or dense[k] is int):
				continue
			var p := _point_along(geometry, chainages[k])
			stations.append(PackedFloat64Array([p[0], p[1], float(dense[k]), chainages[k], _layer_of(segments[id])]))
			station_ids.append(id)
	var uncovered := {}
	for raw: Variant in drape.get("segments", []):
		if not raw is Dictionary or not records.has(raw.get("id")) or loop.segments.has(raw.id) or joined.has(raw.id):
			continue
		var id: String = raw.id
		var geometry := _geometry(raw_points[id])
		var layer := _layer_of(segments[id])
		var dense: Array = raw.dense
		var found := {}
		for k: int in stations.size():
			var station := stations[k]
			if int(station[4]) == layer or absf(station[0] - geometry.x_mid) > geometry.x_half + CROSSING_DISTANCE_M or absf(station[1] - geometry.z_mid) > geometry.z_half + CROSSING_DISTANCE_M:
				continue
			var nearest := _nearest_on(geometry, station[0], station[1])
			if nearest[0] > CROSSING_DISTANCE_M:
				continue
			var height := _centre_height(dense, geometry.length, nearest[1])
			if absf(height - station[2]) > CROSSING_HEIGHT_M:
				found = {"id": id, "loop": station_ids[k], "loop_chainage": station[3], "distance_m": nearest[0], "loop_height": station[2], "height": height, "layer": layer, "loop_layer": int(station[4])}
				break
		if not found.is_empty():
			crossings.append(found)
			uncovered[id] = true
	var out_segments: Array = []
	for raw: Variant in drape.get("segments", []):
		if raw is Dictionary and uncovered.has(raw.get("id")):
			var copy: Dictionary = raw.duplicate(false)
			copy["covered"] = false
			out_segments.append(copy)
		else:
			out_segments.append(raw)
	out["segments"] = out_segments
	return {"drape": out, "crossings": crossings}


## A segment's OSM layer: its `layer` tag, 0 untagged or not a number.
static func _layer_of(segment: SkeletonLoader.Segment) -> int:
	var tag: String = segment.tags.get("layer", "0")
	return int(tag) if tag.is_valid_int() else 0


## A segment's 64-bit geometry and its box: {xs, zs, chain, length, x_mid,
## z_mid, x_half, z_half}.
static func _geometry(points: Array) -> Dictionary:
	var xs := PackedFloat64Array()
	var zs := PackedFloat64Array()
	for point: Variant in points:
		xs.append(float(point[0]))
		zs.append(float(point[1]))
	var chain := WorldRoadProfile.chainages(xs, zs)
	var x_lo := xs[0]
	var x_hi := xs[0]
	var z_lo := zs[0]
	var z_hi := zs[0]
	for i: int in xs.size():
		x_lo = minf(x_lo, xs[i])
		x_hi = maxf(x_hi, xs[i])
		z_lo = minf(z_lo, zs[i])
		z_hi = maxf(z_hi, zs[i])
	return {"xs": xs, "zs": zs, "chain": chain, "length": chain[chain.size() - 1], "x_mid": 0.5 * (x_lo + x_hi), "z_mid": 0.5 * (z_lo + z_hi), "x_half": 0.5 * (x_hi - x_lo), "z_half": 0.5 * (z_hi - z_lo)}


## The point at chainage s of a geometry: [x, z].
static func _point_along(geometry: Dictionary, s: float) -> PackedFloat64Array:
	var xs: PackedFloat64Array = geometry.xs
	var zs: PackedFloat64Array = geometry.zs
	var chain: PackedFloat64Array = geometry.chain
	for i: int in range(1, chain.size()):
		if chain[i] >= s:
			var span := chain[i] - chain[i - 1]
			var u := 0.0 if span <= 0.0 else (s - chain[i - 1]) / span
			return PackedFloat64Array([xs[i - 1] + u * (xs[i] - xs[i - 1]), zs[i - 1] + u * (zs[i] - zs[i - 1])])
	return PackedFloat64Array([xs[xs.size() - 1], zs[zs.size() - 1]])


## The nearest point of a polyline to (x, z): [distance, chainage].
static func _nearest_on(geometry: Dictionary, x: float, z: float) -> PackedFloat64Array:
	var xs: PackedFloat64Array = geometry.xs
	var zs: PackedFloat64Array = geometry.zs
	var chain: PackedFloat64Array = geometry.chain
	var best := PackedFloat64Array([INF, 0.0])
	for c: int in xs.size() - 1:
		var dx := xs[c + 1] - xs[c]
		var dz := zs[c + 1] - zs[c]
		var chord := chain[c + 1] - chain[c]
		if chord <= 0.0:
			continue
		var t := clampf(((x - xs[c]) * dx + (z - zs[c]) * dz) / (chord * chord), 0.0, 1.0)
		var px := xs[c] + t * dx
		var pz := zs[c] + t * dz
		var distance := sqrt((x - px) * (x - px) + (z - pz) * (z - pz))
		if distance < best[0]:
			best = PackedFloat64Array([distance, chain[c] + t * chord])
	return best


## A record's centre height at a chainage: the dense stations, linear
## between them (WorldRoadProfile.centre_height on the raw list).
static func _centre_height(dense: Array, length: float, chainage: float) -> float:
	var s := clampf(chainage, 0.0, length)
	var whole := floori(length / WorldRoadProfile.STATION_STEP_M + 1e-9)
	var k := mini(floori(s / WorldRoadProfile.STATION_STEP_M), whole)
	if k < whole:
		return lerpf(float(dense[k]), float(dense[k + 1]), (s - k * WorldRoadProfile.STATION_STEP_M) / WorldRoadProfile.STATION_STEP_M)
	if dense.size() > whole + 1:
		var rest := length - whole * WorldRoadProfile.STATION_STEP_M
		return lerpf(float(dense[whole]), float(dense[whole + 1]), (s - whole * WorldRoadProfile.STATION_STEP_M) / rest)
	return float(dense[whole])


# =============================================================================
#  THE RIM RULE
# =============================================================================

## The drape with the rim rule applied (see the header): a dictionary of
## the drape's keys whose `segments` is a new list, the records of the
## lifted segments replaced by copies with their `dense` raised (every
## other record the same object), and `lifts`: one entry per covered
## bridge the rule changed, {bridge, start: {approaches, rim_m, rim_height,
## found, wall}, end: {..}, line_slope, stations, max_lift_m}. rim_m is the
## rim's distance from the bridge's end along the approaches (0: the
## abutment is its own rim, or none was found - `found` says which);
## `wall` says a climb of RIM_SLOPE or more was walked over. A pure
## function of the parsed data: the bridges in the drape's order, the
## junctions by id.
static func apply_rim_rule(skeleton: Dictionary, drape: Dictionary) -> Dictionary:
	var segments := SkeletonLoader.segments_of(skeleton)
	var junctions := SkeletonLoader.junctions_of(skeleton)
	var raw_points := {}
	for raw: Variant in skeleton.get("segments", []):
		if raw is Dictionary and raw.get("id") is String and raw.get("points") is Array:
			raw_points[raw.id] = raw.points
	var records := {}
	var dense := {}
	var lengths := {}
	for raw: Variant in drape.get("segments", []):
		if not (raw is Dictionary and raw.get("covered", false) and segments.has(raw.get("id")) and raw.get("dense") is Array):
			continue
		var heights := PackedFloat64Array()
		for h: Variant in raw.dense:
			heights.append(float(h) if (h is float or h is int) else NAN)
		var xs := PackedFloat64Array()
		var zs := PackedFloat64Array()
		for point: Variant in raw_points[raw.id]:
			xs.append(float(point[0]))
			zs.append(float(point[1]))
		var chain := WorldRoadProfile.chainages(xs, zs)
		if heights.size() != WorldRoadProfile.station_chainages(chain[chain.size() - 1]).size():
			continue
		records[raw.id] = raw
		dense[raw.id] = heights
		lengths[raw.id] = chain[chain.size() - 1]
	# Which junction each covered segment's ends stand at ("id:0" its
	# start, "id:1" its end).
	var end_junction := {}
	for junction: SkeletonLoader.Junction in junctions.values():
		for id: String in junction.segments:
			if not records.has(id):
				continue
			var segment: SkeletonLoader.Segment = segments[id]
			if segment.first().distance_to(junction.position) <= SkeletonLoader.JOIN_TOLERANCE_M:
				end_junction[id + ":0"] = junction
			if segment.last().distance_to(junction.position) <= SkeletonLoader.JOIN_TOLERANCE_M:
				end_junction[id + ":1"] = junction
	var changed := {}
	var lifts: Array[Dictionary] = []
	for raw: Variant in drape.get("segments", []):
		if not raw is Dictionary or not records.has(raw.get("id")) or not _is_bridge(segments[raw.id]):
			continue
		var id: String = raw.id
		var length: float = lengths[id]
		var ends: Array[Dictionary] = [
			_rim_of(id, 0, segments, records, dense, lengths, end_junction, raw_points),
			_rim_of(id, 1, segments, records, dense, lengths, end_junction, raw_points),
		]
		# Nothing where no rim is found (the endorsed rule): the deck line
		# needs a rim at BOTH ends - a rim at distance zero (the abutment
		# its own rim) is one, an end whose walk found none is not, and
		# that bridge is left as the file has it (the codex review of
		# 4B-4: an unfound end's abutment used to serve as the line's end,
		# 134220315-0's lift drawn to it). Two abutments that are their own
		# rims stand at no hole: nothing to draw, the deck the file's
		# (measured: the line between them would lift 14 bridges' decks by
		# a rounding's 2-9 mm, 41395681-0 among them).
		if not (ends[0].found and ends[1].found):
			continue
		if ends[0].rim_m <= 0.0 and ends[1].rim_m <= 0.0:
			continue
		var run: float = ends[0].rim_m + length + ends[1].rim_m
		var h0: float = ends[0].rim_height
		var h1: float = ends[1].rim_height
		var raised := 0
		var max_lift := 0.0
		var deck: PackedFloat64Array = dense[id]
		var stations := WorldRoadProfile.station_chainages(length)
		for k: int in stations.size():
			var line: float = h0 + (h1 - h0) * (ends[0].rim_m + stations[k]) / run
			if line > deck[k]:
				max_lift = maxf(max_lift, line - deck[k])
				deck[k] = line
				raised += 1
				changed[id] = true
		for end: int in 2:
			var rim: Dictionary = ends[end]
			for approach: Dictionary in rim.approaches:
				var heights: PackedFloat64Array = dense[approach.id]
				var approach_stations := WorldRoadProfile.station_chainages(lengths[approach.id])
				for k: int in approach_stations.size():
					# From the approach's own station at the junction (out 0: the
					# same ground point as the bridge's abutment sample, lifted
					# with it or the deck would end 4 m over the approach) out
					# to the rim.
					var out: float = approach.offset + (approach_stations[k] if approach.from_start else lengths[approach.id] - approach_stations[k])
					if out < -SAME_CHAINAGE_M or out > rim.rim_m + SAME_CHAINAGE_M:
						continue
					var position: float = ends[0].rim_m - out if end == 0 else ends[0].rim_m + length + out
					var line: float = h0 + (h1 - h0) * position / run
					if line > heights[k]:
						max_lift = maxf(max_lift, line - heights[k])
						heights[k] = line
						raised += 1
						changed[approach.id] = true
		lifts.append({"bridge": id, "start": ends[0], "end": ends[1], "line_slope": (h1 - h0) / run, "stations": raised, "max_lift_m": max_lift})
	var out := drape.duplicate(false)
	var out_segments: Array = []
	for raw: Variant in drape.get("segments", []):
		if raw is Dictionary and changed.has(raw.get("id")):
			var copy: Dictionary = raw.duplicate(false)
			var heights: Array = []
			for h: float in dense[raw.id]:
				heights.append(h)
			copy["dense"] = heights
			out_segments.append(copy)
		else:
			out_segments.append(raw)
	out["segments"] = out_segments
	return {"drape": out, "lifts": lifts}


static func _is_bridge(segment: SkeletonLoader.Segment) -> bool:
	return segment.tags.has("bridge") and segment.tags["bridge"] != "no"


static func _is_plain(segment: SkeletonLoader.Segment) -> bool:
	return not _is_bridge(segment) and segment.tags.get("tunnel") != "yes"


## The rim past one end of bridge `id` (end 0 its start, 1 its end):
## {approaches: [{id, from_start, offset}], rim_m, rim_height, found,
## wall}. The walk (see the header) goes from the abutment outward along
## plain covered approaches, through a two-segment junction onto its other
## segment and through a bigger one onto the segment that best continues
## the heading (_continuation, amendment 2), at most APPROACH_REACH_M,
## listing every approach it entered with the outward distance its near
## end stands at (`offset`) and whether its chainage runs outward
## (`from_start`); the outward stations' heights are read in order and the
## rim is the first station whose onward slopes stay under RIM_SLOPE for
## the next RIM_LOOKAHEAD_STATIONS stations. rim_m is
## 0 and rim_height the bridge's own abutment sample when the abutment is
## its own rim (found) or when no rim is within reach (not found); an end
## not found draws no deck line (apply_rim_rule).
static func _rim_of(id: String, end: int, segments: Dictionary, records: Dictionary, dense: Dictionary, lengths: Dictionary, end_junction: Dictionary, raw_points: Dictionary) -> Dictionary:
	var deck: PackedFloat64Array = dense[id]
	var abutment := deck[0] if end == 0 else deck[deck.size() - 1]
	var out := {"approaches": [] as Array[Dictionary], "rim_m": 0.0, "rim_height": abutment, "found": false, "wall": false}
	var distances := PackedFloat64Array([0.0])
	var heights := PackedFloat64Array([abutment])
	var walked := 0.0
	var current := id
	var heading := _outward_heading(raw_points[id], end == 1)
	var junction: SkeletonLoader.Junction = end_junction.get("%s:%d" % [id, end])
	while junction != null and walked < APPROACH_REACH_M:
		var next_id := _continuation(junction, current, heading, segments, records, end_junction, raw_points)
		if next_id == "":
			break
		var from_start: bool = end_junction.get(next_id + ":0") == junction
		var stations := WorldRoadProfile.station_chainages(lengths[next_id])
		var approach_heights: PackedFloat64Array = dense[next_id]
		for step: int in stations.size():
			var k := step if from_start else stations.size() - 1 - step
			var distance: float = walked + (stations[k] if from_start else lengths[next_id] - stations[k])
			if distance - distances[distances.size() - 1] <= SAME_CHAINAGE_M:
				continue
			distances.append(distance)
			heights.append(approach_heights[k])
		out.approaches.append({"id": next_id, "from_start": from_start, "offset": walked})
		walked += lengths[next_id]
		current = next_id
		heading = _outward_heading(raw_points[next_id], from_start)
		junction = end_junction.get(next_id + (":1" if from_start else ":0"))
	for k: int in distances.size() - 1:
		if distances[k] > APPROACH_REACH_M:
			break
		# The rim: every one of the next RIM_LOOKAHEAD_STATIONS onward
		# climbs under RIM_SLOPE (was the next one alone under 0.20: the
		# hole-wall's 14.5 % tail passed and its crest stayed, see the
		# constants). Fewer stations left in the walk than the look-ahead
		# asks: the ones there have to pass (the reach or the walk's end
		# truncates the look-ahead, never waives it).
		var eases := true
		for j: int in RIM_LOOKAHEAD_STATIONS:
			var i := k + j
			if i + 1 >= distances.size():
				break
			var slope := (heights[i + 1] - heights[i]) / (distances[i + 1] - distances[i])
			if slope >= RIM_SLOPE:
				eases = false
				break
		if eases:
			out.rim_m = distances[k]
			out.rim_height = heights[k]
			out.found = true
			break
		out.wall = true
	return out


## The segment the walk leaves `junction` on, coming off `current` with
## the outward `heading`: the plain covered segment leaving the junction
## with the smallest turn from the heading, CONTINUATION_MAX_TURN_DEG at
## most (amendment 2; the same filter at every junction, whatever its
## arity), the first in the junction's order on a tie. "" when there is
## none plain and covered, or none within the turn.
static func _continuation(junction: SkeletonLoader.Junction, current: String, heading: Vector2, segments: Dictionary, records: Dictionary, end_junction: Dictionary, raw_points: Dictionary) -> String:
	var best := ""
	var best_turn := INF
	for candidate: String in junction.segments:
		if candidate == current or not records.has(candidate) or not _is_plain(segments[candidate]):
			continue
		# Into the candidate from the junction: the reverse of its outward
		# heading at that end. Every junction's candidates go through the
		# same turn filter, a two-segment junction's too (the codex review
		# of 4B-4: a 2-way junction's other segment used to be taken before
		# the heading check, so a hairpin would have been walked through).
		var leaves_from_start: bool = end_junction.get(candidate + ":0") == junction
		var outgoing := -_outward_heading(raw_points[candidate], not leaves_from_start)
		var turn := absf(heading.angle_to(outgoing))
		if turn <= deg_to_rad(CONTINUATION_MAX_TURN_DEG) and turn < best_turn:
			best_turn = turn
			best = candidate
	return best


## The unit direction of travel at a segment's far end when its chainage
## runs outward (`from_start`: the last chord's direction) or inward (the
## first chord's, reversed), from the file's own points.
static func _outward_heading(points: Array, from_start: bool) -> Vector2:
	var n := points.size()
	var direction := Vector2(float(points[n - 1][0]) - float(points[n - 2][0]), float(points[n - 1][1]) - float(points[n - 2][1])) if from_start else Vector2(float(points[0][0]) - float(points[1][0]), float(points[0][1]) - float(points[1][1]))
	return direction.normalized()
