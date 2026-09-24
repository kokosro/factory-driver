extends SceneTree
## Headless minimap test: THE GPS GUIDER (scripts/gps_minimap.gd). Run via
## tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/minimap_test.gd
##
## The node on both scenes: main.tscn's HUD makes it in code (a child named
## GpsMinimap, the car handed over, visible at load) and it draws without
## error; the pad has no skeleton road, so it holds no map data, parses
## nothing (load_count 0), selects no road and its one line says "no map
## data". The key: P in the map, plain, and on no other action, the
## engine's built-ins walked too; a tap hides the layer and its line, a
## tap shows them, toggle() the same. THE CORE, pure, on a synthetic table
## (a straight road along +x, a quarter circle of 80 m radius on its end,
## a road 480 m to the side, one 520 m to the side, one 700 m along both
## world axes, and an L of 100 m legs far away): the window's set for a
## pose is the roads within 500 m of the car in the car's frame - on an
## axis heading the 520 m road is out, on a diagonal heading it is in (the
## turned square reaches 707 m along a world axis) and the 700/700 one,
## inside that reach's box, is out (the codex cross-review's F1: was ->
## the world-aligned square alone, the 520 m road out at any heading);
## heading-up
## puts a point 100 m ahead of a car heading +x straight above the panel's
## centre, a point 100 m to the right (+z) to the right, and heading -z
## (yaw 0) the same; the arc from the straight's middle runs 400 m along
## the straight only (every panel x the centre's, every radius INF, the
## next name the bend's), and from 200 m before the bend it goes through
## the junction into the bend: the radius 80 m at every interior bend
## point, the panel x moving right, the length short of 400 m at the
## bend's dead end; a straight and a bend are different geometry; the L's
## vertex reads the same 70.71 m (amber) whether the arc starts 99 m or
## 1 m before it (F2: was -> 50.00 m, red, from 1 m). THE
## RING: eifel_ring.tscn loaded, the table is the RoadBuilder's built
## roads (road_count of them, fewer than the skeleton's segments), built
## once; the window at the spawn holds only built roads, the arc starts on
## the pit lane under the car and runs its 400 m, the names readout is
## set, and one _draw's points on the real data - every road's polyline
## points plus the arc's per-band runs, exactly what is submitted (F3:
## was -> the arc's chords drawn one by one and counted as points) - stay
## under the budget (DRAW_POINT_BUDGET); the car at rest draws nothing new, the car moved
## 3 m draws once; the table is not rebuilt by any of it.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"
const RING_SCENE := "res://scenes/eifel_ring.tscn"

## Physics frames to let the car settle on the ground at the start.
const SETTLE_FRAMES := 20

## Frames the car is left at rest to see no redraw [physics ticks].
const REST_FRAMES := 30

## The synthetic bend's radius [m] and how far the car sits before it [m].
const BEND_RADIUS_M := 80.0
const BEFORE_BEND_M := 200.0

var _failures := 0
var _main: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	_main = packed.instantiate()
	root.add_child(_main)
	await _step(SETTLE_FRAMES)
	var car := _main.get_node_or_null("Car") as ArcadeCar
	var hud := _main.get_node_or_null("HUD") as HUD
	if not _check(car != null and hud != null, "Car and HUD exist"):
		_finish()
		return
	var minimap := hud.minimap
	if not _check(minimap != null and minimap.get_parent() == hud and minimap.name == "GpsMinimap" and minimap.car == car, "the HUD made the minimap in code: a child named GpsMinimap, the car handed over"):
		_finish()
		return

	_check_key()
	_check_fullscreen()
	await _check_pad(minimap)
	await _check_toggle(minimap)
	_check_core()

	_main.queue_free()
	await _step(2)
	await _check_ring()
	_finish()


# =============================================================================
#  The key
# =============================================================================

## P, plain, and nothing else on plain P: every action's key events walked,
## the engine's built-in ui_ actions among them (the flag test's own
## check, on this key).
func _check_key() -> void:
	var events := InputMap.action_get_events(GpsMinimap.ACTION) if InputMap.has_action(GpsMinimap.ACTION) else []
	var on_p := events.size() == 1 and events[0] is InputEventKey and (events[0] as InputEventKey).physical_keycode == KEY_P and (events[0] as InputEventKey).get_modifiers_mask() == 0
	var others := PackedStringArray()
	for action in InputMap.get_actions():
		if action == GpsMinimap.ACTION:
			continue
		for event in InputMap.action_get_events(action):
			if not event is InputEventKey:
				continue
			var key := event as InputEventKey
			if (key.physical_keycode == KEY_P or key.keycode == KEY_P) and key.get_modifiers_mask() == 0 and not key.command_or_control_autoremap:
				others.append(String(action))
	_check(on_p and others.is_empty(), "the minimap's key is P (minimap_show, physical 80), no other action - the engine's built-ins included - is on plain P (%s)" % (", ".join(others) if not others.is_empty() else "none"))


## The game starts windowed: display/window/size/mode in project.godot is
## 0, which the engine's own enum calls windowed
## (DisplayServer.WINDOW_MODE_WINDOWED; the setting's editor hint lists
## Windowed, Minimized, Maximized, Fullscreen, Exclusive Fullscreen -
## verified on 4.7.2 headless). was 4, Exclusive Fullscreen (the minimap
## iteration's approved extra, 2026-09-23); REVISION 2026-09-24: the driver
## remote-desktops into the dev machine, which fights exclusive fullscreen -
## the default is windowed again, fullscreen stays available (nothing
## removed, only the default). Read off ProjectSettings, honestly, the
## setting, the enum and the hint together: headless there is no window.
func _check_fullscreen() -> void:
	var mode: int = ProjectSettings.get_setting("display/window/size/mode", -1)
	var names := PackedStringArray()
	for property: Dictionary in ProjectSettings.get_property_list():
		if property.name == "display/window/size/mode":
			names = String(property.hint_string).split(",")
	var mode_name := names[mode] if mode >= 0 and mode < names.size() else "?"
	_check(mode == 0 and mode == DisplayServer.WINDOW_MODE_WINDOWED and mode_name == "Windowed", "the game starts windowed: display/window/size/mode is %d, the engine's WINDOW_MODE_WINDOWED (%d), which the setting's own hint names %s (was 4, Exclusive Fullscreen (the minimap iteration's approved extra, 2026-09-23); REVISION 2026-09-24: the driver remote-desktops into the dev machine - the default is windowed again, fullscreen stays available)" % [mode, DisplayServer.WINDOW_MODE_WINDOWED, mode_name])


# =============================================================================
#  The pad: no map data
# =============================================================================

## main.tscn has no RoadBuilder: nothing parsed, nothing selected, the line
## up, a draw that puts no point through.
func _check_pad(minimap: GpsMinimap) -> void:
	await _process_frames(2)
	_check(minimap.visible, "the minimap is on at scene load")
	_check(not minimap.has_map_data and minimap.load_count == 0 and minimap.roads.is_empty(), "the pad has no map data: no RoadBuilder beside the HUD, the table never built (load_count %d, %d roads)" % [minimap.load_count, minimap.roads.size()])
	_check(minimap.status_visible() and (minimap.get_node("Status") as Label).text == GpsMinimap.NO_DATA_TEXT, "the pad's line says %s" % [GpsMinimap.NO_DATA_TEXT])
	_check(minimap.roads_in_window(car_xz(minimap), Vector2(0, -1)).is_empty() and minimap.ahead_arc(car_xz(minimap), Vector2(0, -1)).is_empty(), "no road in the window and no arc on the pad")
	_check(minimap.draw_count >= 1 and minimap.last_draw_point_count == 0, "the pad's minimap drew (%d draws) without error and put no point through" % minimap.draw_count)


static func car_xz(minimap: GpsMinimap) -> Vector2:
	return Vector2(minimap.car.global_position.x, minimap.car.global_position.z)


# =============================================================================
#  The toggle
# =============================================================================

## The key hides the layer (the line with it) and shows it again; toggle()
## does the same.
func _check_toggle(minimap: GpsMinimap) -> void:
	await _tap(GpsMinimap.ACTION)
	var hidden := not minimap.visible and not minimap.is_visible_in_tree()
	await _tap(GpsMinimap.ACTION)
	_check(hidden and minimap.visible, "a tap of the key hides the minimap and its line, a tap shows them again")
	minimap.toggle()
	var off := not minimap.visible
	minimap.toggle()
	_check(off and minimap.visible, "toggle() does the same")


# =============================================================================
#  The core, pure: the synthetic table
# =============================================================================

func _segment(id: String, points: PackedVector2Array, width_m: float, road_class: String, name: String) -> SkeletonLoader.Segment:
	var segment := SkeletonLoader.Segment.new()
	segment.id = id
	segment.osm_way = int(id.split("-")[0])
	segment.road_class = road_class
	segment.width_m = width_m
	segment.width_source = "class"
	segment.points = points
	if name != "":
		segment.tags["name"] = name
	return segment


## A straight along +x from 0 to 500 m, a quarter circle of BEND_RADIUS_M
## from its end turning to +z (the right of a car heading +x), a road at
## z = 480 m beside the straight's middle, one at z = 520 m, one 700 m
## along both world axes from the straight's middle, and far away at
## (-3000, -3000) an L of two 100 m legs.
func _synthetic() -> Array[SkeletonLoader.Segment]:
	var straight := PackedVector2Array()
	for i in 6:
		straight.append(Vector2(i * 100.0, 0.0))
	var bend := PackedVector2Array()
	for i in 7:
		var angle := deg_to_rad(i * 15.0)
		bend.append(Vector2(500.0 + BEND_RADIUS_M * sin(angle), BEND_RADIUS_M - BEND_RADIUS_M * cos(angle)))
	return [
		_segment("1-0", straight, 6.0, "tertiary", "Straight"),
		_segment("2-0", bend, 6.0, "tertiary", "Bend"),
		_segment("3-0", PackedVector2Array([Vector2(250.0, 480.0), Vector2(350.0, 480.0)]), 3.0, "track", ""),
		_segment("4-0", PackedVector2Array([Vector2(250.0, 520.0), Vector2(350.0, 520.0)]), 3.0, "track", ""),
		_segment("5-0", PackedVector2Array([Vector2(1000.0, 700.0), Vector2(1010.0, 700.0)]), 3.0, "track", ""),
		_segment("6-0", PackedVector2Array([Vector2(-3100.0, -3000.0), Vector2(-3000.0, -3000.0), Vector2(-3000.0, -2900.0)]), 6.0, "tertiary", "Elbow"),
	]


func _check_core() -> void:
	var minimap := GpsMinimap.new()
	root.add_child(minimap)
	var loaded := minimap.load_segments(_synthetic())
	_check(loaded == 6 and minimap.has_map_data and minimap.load_count == 1 and minimap.roads.size() == 6, "the synthetic table: 6 roads loaded once")

	# The window: from (300, 0) heading +x the straight, the bend (its
	# bounds reach down to x 500) and the road at 480 m are in, the one at
	# 520 m is out; heading diagonally the square turns and the 520 m road
	# is in (it sits 332..403 m ahead and to the right in the car's frame),
	# the 700/700 road is not (990 m ahead, though inside the turned
	# square's 707 m box along each world axis).
	# was -> the world-aligned square: the 520 m road out at any heading.
	var ids := PackedStringArray()
	for road: GpsMinimap.MapRoad in minimap.roads_in_window(Vector2(300.0, 0.0), Vector2(1.0, 0.0)):
		ids.append(road.id)
	_check(ids == PackedStringArray(["1-0", "2-0", "3-0"]), "the window at (300, 0) heading +x: the roads within 500 m are in (%s), the one at 520 m out" % [", ".join(ids)])
	ids = PackedStringArray()
	for road: GpsMinimap.MapRoad in minimap.roads_in_window(Vector2(300.0, 0.0), Vector2(1.0, 1.0).normalized()):
		ids.append(road.id)
	_check(ids == PackedStringArray(["1-0", "2-0", "3-0", "4-0"]), "the window at (300, 0) heading diagonally: the turned square takes the 520 m road in and leaves the 700/700 one out (%s)" % [", ".join(ids)])
	ids = PackedStringArray()
	for road: GpsMinimap.MapRoad in minimap.roads_in_window(Vector2(3000.0, 3000.0), Vector2(0.0, -1.0)):
		ids.append(road.id)
	_check(ids.is_empty(), "the window at (3000, 3000): nothing")

	# Heading-up: a car heading +x, a point 100 m ahead at +x is straight
	# above the centre (22 px at 0.22 px/m); a point at +z is to its right
	# (the car's basis.x); heading -z (yaw 0) a point at -z is above.
	var centre := minimap.panel_centre()
	var ahead := minimap.to_panel(Vector2(100.0, 0.0), Vector2.ZERO, Vector2(1.0, 0.0))
	var right := minimap.to_panel(Vector2(0.0, 100.0), Vector2.ZERO, Vector2(1.0, 0.0))
	var north := minimap.to_panel(Vector2(0.0, -100.0), Vector2.ZERO, Vector2(0.0, -1.0))
	var expected_up := centre + Vector2(0.0, -100.0 * GpsMinimap.SCALE_PX_PER_M)
	_check(ahead.is_equal_approx(expected_up) and north.is_equal_approx(expected_up), "heading-up: 100 m ahead of a car heading +x is %.1f px straight above the centre (%s), and 100 m ahead of one heading -z the same" % [100.0 * GpsMinimap.SCALE_PX_PER_M, ahead])
	_check(right.is_equal_approx(centre + Vector2(100.0 * GpsMinimap.SCALE_PX_PER_M, 0.0)), "heading-up: 100 m to the right of travel (+z for a car heading +x) is to the right of the centre (%s)" % [right])

	# The arc from the straight's start: 400 m of straight, every panel x
	# the centre's, every radius INF, the names Straight > Bend not yet
	# (the walk never leaves the straight).
	var flat := minimap.ahead_arc(Vector2(10.0, 0.0), Vector2(1.0, 0.0))
	var flat_ok: bool = not flat.is_empty() and is_equal_approx(flat.length, GpsMinimap.AHEAD_M) and flat.roads == PackedStringArray(["1-0"]) and flat.current == "Straight" and flat.next == ""
	var flat_points: PackedVector2Array = minimap.panel_points(flat.points, Vector2(10.0, 0.0), Vector2(1.0, 0.0)) if not flat.is_empty() else PackedVector2Array()
	var flat_straight := flat_points.size() >= 2
	for i in flat_points.size():
		flat_straight = flat_straight and is_equal_approx(flat_points[i].x, centre.x) and flat_points[i].y <= centre.y + 0.001 and is_inf(flat.radii[i])
	_check(flat_ok and flat_straight, "the arc from the straight's start: %.0f m along the straight only, %d panel points all at the centre's x and above it, every radius INF, the road under the car %s" % [flat.get("length", 0.0), flat_points.size(), flat.get("current", "")])

	# The arc from 200 m before the bend: through the junction into the
	# bend, the radius 80 m at its interior points, the panel x moving
	# right, the length the straight's 200 m plus the bend's arc (125.7 m),
	# short of 400 m at the dead end; the next name Bend.
	var at := Vector2(500.0 - BEFORE_BEND_M, 0.0)
	var bent := minimap.ahead_arc(at, Vector2(1.0, 0.0))
	var bent_points: PackedVector2Array = minimap.panel_points(bent.points, at, Vector2(1.0, 0.0)) if not bent.is_empty() else PackedVector2Array()
	var bend_length := BEND_RADIUS_M * PI * 0.5
	var radii_ok := not bent.is_empty()
	var interior := 0
	if radii_ok:
		for i in range(1, bent.points.size() - 1):
			if bent.points[i].x > 500.0 + 0.001:
				interior += 1
				radii_ok = radii_ok and absf(bent.radii[i] - BEND_RADIUS_M) < 0.05
	var rightward := bent_points.size() >= 2 and bent_points[bent_points.size() - 1].x > centre.x + 10.0
	var chord_length := 0.0
	for i in range(1, bent.get("points", PackedVector2Array()).size()):
		chord_length += bent.points[i].distance_to(bent.points[i - 1])
	var expected_length := BEFORE_BEND_M + 2.0 * 6.0 * BEND_RADIUS_M * sin(deg_to_rad(7.5))
	_check(radii_ok and interior == 5 and bent.roads == PackedStringArray(["1-0", "2-0"]) and bent.current == "Straight" and bent.next == "Bend" and absf(bent.length - expected_length) < 0.01 and is_equal_approx(chord_length, bent.length), "the arc from %.0f m before the bend goes through the junction into it: %d interior bend points each of radius %.0f m (%s), the length %.1f m (the straight's %.0f + the bend's %.1f m of chords, a dead end short of %.0f), next name %s" % [BEFORE_BEND_M, interior, BEND_RADIUS_M, bent.get("roads", []), bent.get("length", 0.0), BEFORE_BEND_M, expected_length - BEFORE_BEND_M, GpsMinimap.AHEAD_M, bent.get("next", "")])
	_check(rightward and flat_straight, "curvature visible: the bend's arc ends %.1f px right of the centre, the straight's stays on it - different polyline geometry" % ((bent_points[bent_points.size() - 1].x - centre.x) if rightward else 0.0))
	_check(GpsMinimap.sharpness_band(INF) == GpsMinimap.BAND_GENTLE and GpsMinimap.sharpness_band(BEND_RADIUS_M) == GpsMinimap.BAND_MEDIUM and GpsMinimap.sharpness_band(30.0) == GpsMinimap.BAND_SHARP, "the bands: a straight gentle, %.0f m medium, 30 m sharp" % BEND_RADIUS_M)
	_check(absf(GpsMinimap.bend_radius(Vector2(0, 0), Vector2(BEND_RADIUS_M, BEND_RADIUS_M), Vector2(2.0 * BEND_RADIUS_M, 0)) - BEND_RADIUS_M) < 1e-3 and is_inf(GpsMinimap.bend_radius(Vector2(0, 0), Vector2(1, 0), Vector2(2, 0))), "bend_radius: three points of an %.0f m circle give %.0f m, three in a line INF" % [BEND_RADIUS_M, BEND_RADIUS_M])

	# The L's vertex: the same radius from the skeleton's own neighbours
	# whether the arc starts 99 m before it or 1 m before it - the
	# clipped start is not a neighbour. was -> 70.71 m and 50.00 m, amber
	# and red, from the arc's own points.
	var elbow_radius := GpsMinimap.bend_radius(Vector2(-3100.0, -3000.0), Vector2(-3000.0, -3000.0), Vector2(-3000.0, -2900.0))
	var from_far := minimap.ahead_arc(Vector2(-3099.0, -3000.0), Vector2(1.0, 0.0))
	var from_near := minimap.ahead_arc(Vector2(-3001.0, -3000.0), Vector2(1.0, 0.0))
	var elbow_ok: bool = not from_far.is_empty() and not from_near.is_empty() and from_far.points.size() == 3 and from_near.points.size() == 3 and from_far.points[1] == Vector2(-3000.0, -3000.0) and from_near.points[1] == Vector2(-3000.0, -3000.0)
	elbow_ok = elbow_ok and absf(from_far.radii[1] - elbow_radius) < 0.01 and absf(from_near.radii[1] - elbow_radius) < 0.01 and GpsMinimap.sharpness_band(from_far.radii[1]) == GpsMinimap.BAND_MEDIUM and GpsMinimap.sharpness_band(from_near.radii[1]) == GpsMinimap.BAND_MEDIUM
	_check(elbow_ok, "the L's vertex reads %.2f m from the skeleton's own neighbours whether the arc starts 99 m before it (%.2f m) or 1 m before it (%.2f m), both %s (was -> 50.00 m, red, from 1 m)" % [elbow_radius, from_far.get("radii", PackedFloat32Array([INF, INF]))[1], from_near.get("radii", PackedFloat32Array([INF, INF]))[1], "amber" if elbow_ok else "?"])

	# No road under the car: no arc.
	_check(minimap.ahead_arc(Vector2(300.0, 200.0), Vector2(1.0, 0.0)).is_empty(), "no road within %.0f m of the car, no arc" % GpsMinimap.NEAREST_ROAD_M)
	_check(minimap.load_count == 1, "the queries rebuilt nothing (load_count %d)" % minimap.load_count)
	minimap.queue_free()


# =============================================================================
#  The Ring
# =============================================================================

func _check_ring() -> void:
	var packed: PackedScene = load(RING_SCENE)
	if not _check(packed != null, "ring scene loads"):
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	var car := scene.get_node_or_null("Car") as ArcadeCar
	var hud := scene.get_node_or_null("HUD") as HUD
	var road := scene.get_node_or_null("Road") as RoadBuilder
	var minimap: GpsMinimap = hud.minimap if hud != null else null
	if not _check(car != null and road != null and minimap != null and minimap.car == car, "the Ring's Car, Road and the HUD's minimap exist"):
		return
	await _process_frames(2)
	var skeleton_segments: int = road.skeleton_data.get("segments", []).size()
	_check(minimap.has_map_data and minimap.load_count == 1 and minimap.roads.size() == road.road_count and minimap.roads.size() < skeleton_segments, "the Ring's table is the RoadBuilder's built roads, built once: %d of the skeleton's %d segments (chosen for the minimap: the roads that exist in the world)" % [minimap.roads.size(), skeleton_segments])
	_check(not minimap.status_visible() and minimap.visible, "the Ring's minimap is on and its no-data line is down")

	var at := car_xz(minimap)
	var unbuilt := 0
	for r: GpsMinimap.MapRoad in minimap.window_roads:
		if not road.strips.has(r.id):
			unbuilt += 1
	_check(minimap.window_roads.size() > 0 and unbuilt == 0 and minimap.pose_position.distance_to(at) < GpsMinimap.MOVE_REDRAW_M, "the window at the spawn holds %d built roads and no other, the pose within %.0f m of the car" % [minimap.window_roads.size(), GpsMinimap.MOVE_REDRAW_M])
	var arc := minimap.arc
	var arc_ok: bool = not arc.is_empty() and arc.points.size() >= 2 and arc.points[0].distance_to(at) < GpsMinimap.NEAREST_ROAD_M and is_equal_approx(arc.length, GpsMinimap.AHEAD_M)
	_check(arc_ok, "the arc starts on the road under the car (%.1f m from it) and runs %.0f m over %d points and %d roads: %s" % [arc.points[0].distance_to(at) if arc_ok else -1.0, arc.get("length", 0.0), arc.get("points", PackedVector2Array()).size(), arc.get("roads", PackedStringArray()).size(), arc.get("roads", PackedStringArray())])
	_check(minimap.names_text() != "", "the names readout is set: %s" % minimap.names_text())
	_check(minimap.draw_count >= 1 and minimap.last_draw_point_count > 0 and minimap.last_draw_point_count <= GpsMinimap.DRAW_POINT_BUDGET, "one _draw on the real Ring at the spawn puts %d polyline points through, under the budget of %d" % [minimap.last_draw_point_count, GpsMinimap.DRAW_POINT_BUDGET])

	# At rest nothing is drawn again; 3 m along the road, once.
	var draws := minimap.draw_count
	var before := car_xz(minimap)
	await _step(REST_FRAMES)
	await _process_frames(1)
	var moved := car_xz(minimap).distance_to(before)
	_check(moved < GpsMinimap.MOVE_REDRAW_M and minimap.draw_count == draws, "the car at rest for %d ticks (moved %.3f m): no new draw (%d)" % [REST_FRAMES, moved, minimap.draw_count - draws])
	car.global_position += -car.global_basis.z * 3.0
	await _step(2)
	await _process_frames(1)
	_check(minimap.draw_count == draws + 1 and minimap.pose_position.distance_to(car_xz(minimap)) < GpsMinimap.MOVE_REDRAW_M, "the car moved 3 m: one new draw (%d), the pose following" % (minimap.draw_count - draws))
	_check(minimap.load_count == 1 and minimap.roads.size() == road.road_count, "nothing rebuilt the table (load_count %d)" % minimap.load_count)
	scene.queue_free()
	await _step(2)


# =============================================================================
#  Helpers
# =============================================================================

func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _step(2)
	Input.action_release(action)
	await _step(2)


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _process_frames(frames: int) -> void:
	for i in frames:
		await process_frame


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	Input.action_release(GpsMinimap.ACTION)
	if _failures == 0:
		print("MINIMAP TEST PASSED")
	else:
		print("MINIMAP TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
