class_name GpsMinimap
extends Control
## THE GPS GUIDER: an in-drive minimap in the HUD's top-right corner, so a
## distance and the next curve can be judged from behind the wheel (the
## user's request: "the world shows only road + car - distances and the
## next curve are unjudgeable"). A window of WINDOW_M around the car, the
## road centrelines in it drawn to their paved widths, the car as an arrow
## at the centre, and THE AHEAD-ARC: the road under the car followed
## AHEAD_M along the way the car points, drawn thicker over the rest with
## every chord coloured by the bend's sharpness there (the radius of the
## circle through three consecutive skeleton points - honest geometry, no
## labels) - a bend to the left curves left on the map, a tight one reads
## red. A nav tool for the drive, not the world map of the spawn UI.
##
## THE DATA is the Ring's skeleton as the RoadBuilder beside the HUD has
## already parsed it (scripts/road_builder.gd, skeleton_data: the file is
## read once by the build, never again here) through SkeletonLoader's own
## typed reader (segments_of), kept as one local table of region-metre
## points built once (load_segments) and indexed by a grid of CELL_M cells;
## a query for the window reads the cells around the car, never the whole
## file. Nothing is parsed per frame: load_count says how often the table
## was built (the test holds it at one).
##
## No RoadBuilder beside the HUD (the pad: main.tscn has no skeleton road,
## its elements are the test pad's own) means NO MAP DATA: the panel draws
## nothing and one dim line says so where the map would be, so the driver
## who presses the key sees the tool answer; the key hides the line as it
## hides the map.
##
## This node only ever READS the car: its position and its heading, in
## _physics_process as the HUD reads the pedals; it presses no input and
## moves nothing. Made in code by the HUD (scripts/hud.gd, _start_minimap:
## the issue flagger's idiom, the one node in both scenes that holds the
## car), not a scene edit.
##
## chosen for the minimap: HEADING-UP. The nav canon for "what comes next":
## the road ahead is always up, a left bend on the map is a left bend on
## the wheel, and no reading of the code argued for north-up - the
## transform is one rotation either way, and the ahead-arc's walk is the
## same. THE LOCAL FRAME: every point is taken car-relative in metres
## first (point - car), then rotated and scaled to pixels; world
## coordinates are never scaled. The region's metres run to 10 km from the
## origin, where a float32 Vector2 still has millimetres, and a difference
## of two such points keeps them; a product of a world coordinate by the
## pixel scale would not. THE ROADS DRAWN are the ones the RoadBuilder
## built (its strips: the drape-covered segments after the loop's right of
## way, 3 304 of the skeleton's 16 771) - the skeleton's other segments
## have no road in the world and a
## map that shows a road the car cannot drive is a lie to the driver; the
## pure loaders take any segment list, so the tests feed synthetic ones.
## THE JUNCTION RULE for the ahead-arc: the walk goes straight on (the
## continuation with the smallest turn), as a driver with no route set
## does; a dead end ends the arc. THE KEY: P (physical 80), plain, free of
## every action of the game's (project.godot's [input]: no P) and of the
## engine's built-ins (H is ui_filedialog_show_hidden; the free plain
## letters were J, O, P, U, Y, Z - measured by walking InputMap headless,
## 2026-09-23), and handled raw by nothing (the one raw key check in
## scripts/ is the HUD's Esc in the issue box). P for the map, next to O,
## under the right hand off the arrows.
##
## OPEN, for the driver, not built here: issue dots on the map (the store's
## records carry x/z: a dot per open issue in the window would be a dozen
## lines, but the store is read only when the flag files, and a minimap
## that reads a file at ready is a second reader of a frozen store);
## sector names / a route; a north tick; zoom levels (WINDOW_M is fixed).
## The "next named place" readout IS here, trivially: the arc's walk
## already crosses the roads ahead, so the first road with another name
## than the current one is one comparison per road (NamesLabel).

## The key: P, the map. See the header for the conflict check.
const ACTION := &"minimap_show"

## The window: half the side of the square around the car that the panel
## shows [m]. "~500 m around the driver" - 500 m ahead, behind and to each
## side; fixed zoom in v1.
const WINDOW_M := 500.0

## The panel [px], square, and its margin from the screen's top-right
## corner [px]; the pixels per metre follow from the two (0.22 px/m).
const PANEL_PX := 220.0
const MARGIN_PX := 16.0
const SCALE_PX_PER_M := PANEL_PX / (2.0 * WINDOW_M)

## The ahead-arc's length along the road [m]: "~300-500 m" - 400, inside
## the window along any road that does not double back.
const AHEAD_M := 400.0

## How far from a centreline the car still counts as on that road [m]:
## the widest road is 8.5 m, the car off the road by a lane is still
## nearest to it; past 30 m there is no road under the car and no arc.
const NEAREST_ROAD_M := 30.0

## Two segment ends this close are one junction [m]: the skeleton's own
## join tolerance.
const JOIN_TOLERANCE_M := SkeletonLoader.JOIN_TOLERANCE_M

## The grid index's cell [m]: the turned window's world-aligned box (up to
## 2 x sqrt(2) x WINDOW_M a side) reads at most 4 x 4 cells of it, and the
## end index's cell [m], 2 m, so a join within JOIN_TOLERANCE_M is found
## in the cell and its eight neighbours.
const CELL_M := 500.0
const END_CELL_M := 2.0

## The car moves this far [m] or turns this much [deg] before the map is
## drawn again; at 35 m/s that is every second tick, at rest never.
const MOVE_REDRAW_M := 1.0
const TURN_REDRAW_DEG := 2.0

## Line widths [px]: a road narrower than MIN_LINE_PX at the scale (a 3 m
## track is 0.66 px) is drawn MIN_LINE_PX wide so it stays visible; the
## ahead-arc is ARC_WIDTH_PX over everything; the car's arrow is CAR_PX
## from its centre to its nose.
const MIN_LINE_PX := 1.5
const ARC_WIDTH_PX := 3.0
const CAR_PX := 7.0

## The sharpness bands, by the bend radius at a point [m]: a radius under
## SHARP_RADIUS_M reads sharp (a hairpin, a second-gear corner), under
## MEDIUM_RADIUS_M medium (a third-gear bend), the rest gentle (a fast
## sweep or a straight). The chord takes the sharper of its two ends.
const SHARP_RADIUS_M := 60.0
const MEDIUM_RADIUS_M := 150.0
const BAND_GENTLE := 0
const BAND_MEDIUM := 1
const BAND_SHARP := 2

## What one _draw may hand to draw_polyline in points, the roads and the
## arc together: the frame-cost budget the test holds the real Ring to
## (last_draw_point_count). The count is exactly what is submitted: every
## window road's polyline points, plus the arc's per-band polylines - the
## point where the band changes is the end of one run and the start of
## the next, and counts twice. Measured at the spawn, the densest place
## the car starts in (the paddock's service roads around the pit lane):
## 362 built roads in the window, 1 806 points, 2026-09-23; 3 000 leaves
## the margin for a denser spot without letting a draw grow unnoticed.
# was -> the arc drawn chord by chord with draw_line and counted as its N
# points while 2(N-1) endpoints were submitted: 1 782 counted at the
# spawn over 373 roads of the world-aligned window (the codex
# cross-review's F3; F1 turned the window, 362 roads).
const DRAW_POINT_BUDGET := 3000

## Colours: the panel, its border, a plain road, the loop (raceway class),
## the arc's three bands, the car.
const PANEL_COLOR := Color(0.05, 0.06, 0.08, 0.7)
const BORDER_COLOR := Color(1, 1, 1, 0.25)
const ROAD_COLOR := Color(0.6, 0.6, 0.58, 0.8)
const RACEWAY_COLOR := Color(0.85, 0.85, 0.8, 0.95)
const ARC_GENTLE_COLOR := Color(0.35, 0.9, 0.45, 1)
const ARC_MEDIUM_COLOR := Color(1.0, 0.7, 0.15, 1)
const ARC_SHARP_COLOR := Color(1.0, 0.25, 0.2, 1)
const CAR_COLOR := Color(0.4, 0.75, 1.0, 1)
const TEXT_COLOR := Color(1, 1, 1, 0.6)

## The pad's line, and the names readout's join.
const NO_DATA_TEXT := "GPS  no map data"
const NAMES_JOIN := "  >  "


## One road on the map: a skeleton segment's centreline in region metres
## and what is drawn from it.
class MapRoad:
	extends RefCounted
	var id: String
	## The way's name tag, else its ref, else "".
	var name: String
	var road_class: String
	var width_m: float
	## [x, z] region metres, at least two points.
	var points: PackedVector2Array
	## The points' bounding box, region metres.
	var bounds: Rect2


## The car being watched. Read only.
var car: ArcadeCar

## The table, built once (load_segments), in the order given.
var roads: Array[MapRoad] = []

## Whether there is anything to draw: false on the pad.
var has_map_data := false

## How often the table was built: 1 on the Ring, 0 on the pad.
var load_count := 0

## The pose the map was last drawn for: the car's centre [region m] and
## its unit forward in the xz-plane (yaw 0 is -z).
var pose_position := Vector2.ZERO
var pose_forward := Vector2(0, -1)

## What the last pose selected: the roads in the window and the arc
## (see ahead_arc).
var window_roads: Array[MapRoad] = []
var arc: Dictionary = {}

## The last _draw's points through draw_polyline, and how many draws ran.
var last_draw_point_count := 0
var draw_count := 0

## The grid index: cell -> the indices into `roads` whose bounds touch it;
## the end index: 2 m cell -> [road index, end] pairs (end 0 = first
## point, 1 = last).
var _cells: Dictionary = {}
var _ends: Dictionary = {}

## Whether a pose was ever taken off the car.
var _posed := false

var _status: Label
var _names: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(PANEL_PX + MARGIN_PX)
	offset_top = MARGIN_PX
	offset_right = -MARGIN_PX
	offset_bottom = MARGIN_PX + PANEL_PX
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status = _label("Status", Vector2(0, 0), Vector2(PANEL_PX, 20), HORIZONTAL_ALIGNMENT_RIGHT)
	_status.text = NO_DATA_TEXT
	_names = _label("NamesLabel", Vector2(4, PANEL_PX - 22), Vector2(PANEL_PX - 8, 20), HORIZONTAL_ALIGNMENT_LEFT)
	if roads.is_empty():
		_load_beside()
	_refresh_status()


## The tick: the key first (matched exactly: a modified P is another key),
## then the car's pose, the map redrawn only once it has moved
## MOVE_REDRAW_M or turned TURN_REDRAW_DEG since the last draw.
func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed(ACTION, true):
		toggle()
	if car == null or not visible or not has_map_data:
		return
	var at := Vector2(car.global_position.x, car.global_position.z)
	var forward := Vector2(-car.global_basis.z.x, -car.global_basis.z.z)
	if forward.length_squared() < 1e-6:
		forward = pose_forward
	else:
		forward = forward.normalized()
	if _posed and at.distance_to(pose_position) < MOVE_REDRAW_M and rad_to_deg(absf(forward.angle_to(pose_forward))) < TURN_REDRAW_DEG:
		return
	_posed = true
	set_pose(at, forward)


## Shows or hides the map (and the pad's line); shown again, it is drawn
## again.
func toggle() -> void:
	visible = not visible
	if visible:
		queue_redraw()


# =============================================================================
#  The table
# =============================================================================

## Builds the table from a parsed skeleton (what SkeletonLoader.read_file
## returns, through its segments_of), keeping only the segments whose ids
## are keys of `built` when it is not empty (the RoadBuilder's strips).
## Returns the roads kept.
func load_skeleton(data: Variant, built: Dictionary = {}) -> int:
	var kept: Array[SkeletonLoader.Segment] = []
	for segment: SkeletonLoader.Segment in SkeletonLoader.segments_of(data).values():
		if built.is_empty() or built.has(segment.id):
			kept.append(segment)
	return load_segments(kept)


## Builds the table from typed segments, in the order given: the roads,
## the grid index and the end index. A segment with under two points is
## no road and is left out. Returns the roads kept.
func load_segments(segments: Array[SkeletonLoader.Segment]) -> int:
	roads = []
	_cells = {}
	_ends = {}
	for segment: SkeletonLoader.Segment in segments:
		if segment.points.size() < 2:
			continue
		var road := MapRoad.new()
		road.id = segment.id
		road.name = String(segment.tags.get("name", segment.tags.get("ref", "")))
		road.road_class = segment.road_class
		road.width_m = segment.width_m
		road.points = segment.points
		road.bounds = _bounds_of(segment.points)
		var index := roads.size()
		roads.append(road)
		var low := _cell_of(road.bounds.position, CELL_M)
		var high := _cell_of(road.bounds.end, CELL_M)
		for cx: int in range(low.x, high.x + 1):
			for cz: int in range(low.y, high.y + 1):
				var cell := Vector2i(cx, cz)
				if not _cells.has(cell):
					_cells[cell] = []
				_cells[cell].append(index)
		_add_end(index, 0, road.points[0])
		_add_end(index, 1, road.points[road.points.size() - 1])
	has_map_data = not roads.is_empty()
	load_count += 1
	_posed = false
	window_roads = []
	arc = {}
	_refresh_status()
	queue_redraw()
	return roads.size()


## The RoadBuilder beside the HUD (the scene root's child named Road, as the
## HUD finds the garage), its parsed skeleton and its built strips; nothing
## without one (the pad).
func _load_beside() -> void:
	var hud := get_parent()
	var scene := hud.get_parent() if hud != null else null
	var road: Node = scene.get_node_or_null("Road") if scene != null else null
	if road is RoadBuilder and not (road as RoadBuilder).skeleton_data.is_empty():
		load_skeleton((road as RoadBuilder).skeleton_data, (road as RoadBuilder).strips)


# =============================================================================
#  The queries (pure: the same pose and table, the same answer)
# =============================================================================

## The roads the panel shows for a pose: the square of WINDOW_M around
## `at` (the car's centre, region m) in the car's frame - heading-up, the
## square turns with `forward`. Read from the grid over the turned
## square's world-aligned box (WINDOW_M x (|forward.x| + |forward.y|) each
## way: WINDOW_M on an axis heading, sqrt(2) x WINDOW_M on a diagonal
## one), kept where the road's bounds and the turned square overlap
## (_in_turned_window: both rectangles' axes tried, exact for two
## rectangles), in table order.
# was -> the world-aligned square of WINDOW_M alone: at a diagonal heading
# a road drawn whole on the panel (up to 707 m along a world axis) was
# left out of the set (the codex cross-review's F1).
func roads_in_window(at: Vector2, forward: Vector2) -> Array[MapRoad]:
	var reach := WINDOW_M * (absf(forward.x) + absf(forward.y))
	var box := Rect2(at - Vector2(reach, reach), Vector2(2.0 * reach, 2.0 * reach))
	var low := _cell_of(box.position, CELL_M)
	var high := _cell_of(box.end, CELL_M)
	var seen := {}
	for cx: int in range(low.x, high.x + 1):
		for cz: int in range(low.y, high.y + 1):
			for index: int in _cells.get(Vector2i(cx, cz), []):
				if not seen.has(index) and roads[index].bounds.intersects(box) and _in_turned_window(roads[index].bounds, at, forward):
					seen[index] = true
	var found: Array[int] = []
	for index: int in seen:
		found.append(index)
	found.sort()
	var result: Array[MapRoad] = []
	for index: int in found:
		result.append(roads[index])
	return result


## Whether `bounds` (world-aligned, region m) overlaps the window square
## as the car's frame has it: the bounds' four corners taken car-relative
## (right of travel, ahead), their box against [-WINDOW_M, WINDOW_M]^2.
## With the world-axis test in roads_in_window this is the separating-axis
## test of two rectangles in full.
func _in_turned_window(bounds: Rect2, at: Vector2, forward: Vector2) -> bool:
	var right := Vector2(-forward.y, forward.x)
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
		var offset := corner - at
		var local := Vector2(offset.dot(right), offset.dot(forward))
		low = low.min(local)
		high = high.max(local)
	return low.x <= WINDOW_M and high.x >= -WINDOW_M and low.y <= WINDOW_M and high.y >= -WINDOW_M


## The road nearest `at` among `candidates` within NEAREST_ROAD_M: {road,
## chord (the nearest chord's first point), t (0..1 along it), point,
## distance}; empty with no road that near.
func nearest_road(at: Vector2, candidates: Array[MapRoad]) -> Dictionary:
	var best := {}
	var best_distance := NEAREST_ROAD_M
	for road: MapRoad in candidates:
		if not road.bounds.grow(NEAREST_ROAD_M).has_point(at):
			continue
		for i: int in range(1, road.points.size()):
			var a := road.points[i - 1]
			var b := road.points[i]
			var t := 0.0
			var ab := b - a
			var length_squared := ab.length_squared()
			if length_squared > 0.0:
				t = clampf((at - a).dot(ab) / length_squared, 0.0, 1.0)
			var point := a + ab * t
			var distance := point.distance_to(at)
			if distance < best_distance:
				best_distance = distance
				best = {"road": road, "chord": i - 1, "t": t, "point": point, "distance": distance}
	return best


## The road ahead: from the point of the nearest road under `at` (the
## car's centre, region m), along it the way `forward` points, AHEAD_M along the way, straight on
## at every junction (the continuation with the smallest turn), stopping
## at a dead end. {points: PackedVector2Array (region m, the first the
## car's foot on the road), radii: PackedFloat32Array (the bend radius at
## each point [m], from the point's own skeleton neighbours - across a
## junction the neighbours on both roads -, INF at the arc's two clipped
## ends, at a dead end and on a straight), length: float [m],
## current: String (the road's name under the car), next: String (the
## first other name met along the arc, "" for none), roads: PackedStringArray
## (the ids walked)}; empty with no road under the car.
# was -> the radii were taken from the arc's own points, the clipped start
# and end among them: a bend's radius depended on where the arc started
# (an L of 100 m legs read 70.71 m from its own vertex and 50.00 m with
# the arc starting 1 m before it, amber turned red; the codex
# cross-review's F2).
func ahead_arc(at: Vector2, forward: Vector2) -> Dictionary:
	var foot := nearest_road(at, roads_in_window(at, forward))
	if foot.is_empty():
		return {}
	var road: MapRoad = foot.road
	var chord: int = foot.chord
	var along := road.points[chord + 1] - road.points[chord]
	var ascending := along.dot(forward) >= 0.0
	var points := PackedVector2Array([foot.point])
	var radii := PackedFloat32Array([INF])
	# A road's end vertex on the arc waits for its neighbour on the next
	# road: its index in `points`, and its neighbour on its own road.
	var pending := -1
	var pending_prev := Vector2.ZERO
	var walked := PackedStringArray()
	var visited := {}
	var remaining := AHEAD_M
	var current: String = road.name
	var next := ""
	var direction := forward
	var index := chord + 1 if ascending else chord
	while remaining > 0.0:
		walked.append(road.id)
		visited[road.id] = true
		if road.name != "" and road.name != current and next == "":
			next = road.name
		var step := 1 if ascending else -1
		var last := road.points.size() - 1
		while remaining > 0.0 and index >= 0 and index <= last:
			var target := road.points[index]
			var from := points[points.size() - 1]
			var chord_length := from.distance_to(target)
			if chord_length > 0.0:
				direction = (target - from) / chord_length
				var radius := INF
				if chord_length > remaining:
					target = from + direction * remaining
					chord_length = remaining
				elif index > 0 and index < last:
					radius = bend_radius(road.points[index - 1], target, road.points[index + 1])
				else:
					pending = points.size()
					pending_prev = road.points[index - step]
				points.append(target)
				radii.append(radius)
				remaining -= chord_length
			index += step
		if remaining <= 0.0:
			break
		var end := road.points[last] if ascending else road.points[0]
		var continuation := _continuation(end, direction, visited)
		if continuation.is_empty():
			break
		road = roads[continuation.index]
		ascending = continuation.end == 0
		index = 1 if ascending else road.points.size() - 2
		if pending >= 0:
			radii[pending] = bend_radius(pending_prev, points[pending], road.points[index])
			pending = -1
	return {"points": points, "radii": radii, "length": AHEAD_M - remaining, "current": current, "next": next, "roads": walked}


## The radius of the circle through three points [m] (Menger): INF for
## three in a line or two of them the same point.
static func bend_radius(a: Vector2, b: Vector2, c: Vector2) -> float:
	var ab := b - a
	var bc := c - b
	var twice_area := absf(ab.cross(bc))
	if twice_area < 1e-6:
		return INF
	return ab.length() * bc.length() * (c - a).length() / (2.0 * twice_area)


## The sharpness band of a bend radius [m]: BAND_SHARP under
## SHARP_RADIUS_M, BAND_MEDIUM under MEDIUM_RADIUS_M, else BAND_GENTLE.
static func sharpness_band(radius: float) -> int:
	if radius < SHARP_RADIUS_M:
		return BAND_SHARP
	if radius < MEDIUM_RADIUS_M:
		return BAND_MEDIUM
	return BAND_GENTLE


## A region-metre point in the panel [px], heading-up in the local frame:
## the car-relative offset in metres, its component along `forward` up the
## panel and its component to the right of travel across it, scaled from
## the panel's centre.
func to_panel(point: Vector2, at: Vector2, forward: Vector2) -> Vector2:
	var offset := point - at
	var ahead := offset.dot(forward)
	var right := offset.dot(Vector2(-forward.y, forward.x))
	return panel_centre() + Vector2(right, -ahead) * SCALE_PX_PER_M


func panel_points(points: PackedVector2Array, at: Vector2, forward: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(points.size())
	for i: int in points.size():
		result[i] = to_panel(points[i], at, forward)
	return result


func panel_centre() -> Vector2:
	return Vector2(PANEL_PX, PANEL_PX) * 0.5


## Takes a pose: the window's roads and the arc selected for it, the names
## readout set, the map drawn again.
func set_pose(at: Vector2, forward: Vector2) -> void:
	pose_position = at
	pose_forward = forward
	window_roads = roads_in_window(at, forward)
	arc = ahead_arc(at, forward)
	_refresh_names()
	queue_redraw()


# =============================================================================
#  The drawing
# =============================================================================

## The panel, the window's roads at their widths, the arc as one polyline
## per run of chords of the same band in that band's colour, the car's
## arrow. Nothing at all without map data (the Status line says so).
## Counts the points handed to draw_polyline (DRAW_POINT_BUDGET).
func _draw() -> void:
	draw_count += 1
	last_draw_point_count = 0
	if not has_map_data:
		return
	draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_PX, PANEL_PX)), PANEL_COLOR)
	draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_PX, PANEL_PX)), BORDER_COLOR, false, 1.0)
	for road: MapRoad in window_roads:
		var points := panel_points(road.points, pose_position, pose_forward)
		var color := RACEWAY_COLOR if road.road_class == "raceway" else ROAD_COLOR
		draw_polyline(points, color, maxf(road.width_m * SCALE_PX_PER_M, MIN_LINE_PX))
		last_draw_point_count += points.size()
	if not arc.is_empty():
		var points := panel_points(arc.points, pose_position, pose_forward)
		var radii: PackedFloat32Array = arc.radii
		var run := PackedVector2Array()
		var run_band := -1
		for i: int in range(1, points.size()):
			var band := sharpness_band(minf(radii[i - 1], radii[i]))
			if band != run_band:
				_draw_arc_run(run, run_band)
				run = PackedVector2Array([points[i - 1]])
				run_band = band
			run.append(points[i])
		_draw_arc_run(run, run_band)
	var centre := panel_centre()
	draw_colored_polygon(PackedVector2Array([
		centre + Vector2(0, -CAR_PX),
		centre + Vector2(CAR_PX * 0.7, CAR_PX),
		centre + Vector2(0, CAR_PX * 0.5),
		centre + Vector2(-CAR_PX * 0.7, CAR_PX),
	]), CAR_COLOR)


## One run of the arc's chords in its band's colour; under two points is
## no run.
func _draw_arc_run(run: PackedVector2Array, band: int) -> void:
	if run.size() < 2:
		return
	var color := ARC_SHARP_COLOR if band == BAND_SHARP else (ARC_MEDIUM_COLOR if band == BAND_MEDIUM else ARC_GENTLE_COLOR)
	draw_polyline(run, color, ARC_WIDTH_PX)
	last_draw_point_count += run.size()


func _refresh_status() -> void:
	if _status != null:
		_status.visible = not has_map_data
	if _names != null:
		_names.visible = has_map_data


## The names readout: the road under the car, then the first other name
## along the arc; empty with no road under the car.
func _refresh_names() -> void:
	if _names == null:
		return
	if arc.is_empty():
		_names.text = ""
	elif arc.next == "":
		_names.text = arc.current
	else:
		_names.text = arc.current + NAMES_JOIN + arc.next


func names_text() -> String:
	return _names.text if _names != null else ""


func status_visible() -> bool:
	return _status != null and _status.visible


func _label(label_name: String, at: Vector2, size: Vector2, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = at
	label.size = size
	label.horizontal_alignment = alignment
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


# =============================================================================
#  The indices
# =============================================================================

static func _bounds_of(points: PackedVector2Array) -> Rect2:
	var bounds := Rect2(points[0], Vector2.ZERO)
	for point: Vector2 in points:
		bounds = bounds.expand(point)
	return bounds


static func _cell_of(point: Vector2, cell_m: float) -> Vector2i:
	return Vector2i(floori(point.x / cell_m), floori(point.y / cell_m))


func _add_end(index: int, end: int, point: Vector2) -> void:
	var cell := _cell_of(point, END_CELL_M)
	if not _ends.has(cell):
		_ends[cell] = []
	_ends[cell].append([index, end])


## The road to go on with from `end` (a road's end point), arriving along
## `direction`: of the other roads with an end within JOIN_TOLERANCE_M of
## it and not walked yet, the one leaving with the smallest turn:
## {index, end}; empty at a dead end. Ties go to the lower table index.
func _continuation(end: Vector2, direction: Vector2, visited: Dictionary) -> Dictionary:
	var best := {}
	var best_turn := INF
	var centre := _cell_of(end, END_CELL_M)
	for cx: int in range(centre.x - 1, centre.x + 2):
		for cz: int in range(centre.y - 1, centre.y + 2):
			for entry: Array in _ends.get(Vector2i(cx, cz), []):
				var road: MapRoad = roads[entry[0]]
				if visited.has(road.id):
					continue
				var point: Vector2 = road.points[0] if entry[1] == 0 else road.points[road.points.size() - 1]
				if point.distance_to(end) > JOIN_TOLERANCE_M:
					continue
				var leaving: Vector2 = (road.points[1] - road.points[0]) if entry[1] == 0 else (road.points[road.points.size() - 2] - road.points[road.points.size() - 1])
				if leaving.length_squared() == 0.0:
					continue
				var turn := absf(direction.angle_to(leaving))
				if turn < best_turn or (turn == best_turn and entry[0] < best.get("index", -1)):
					best_turn = turn
					best = {"index": entry[0], "end": entry[1]}
	return best
