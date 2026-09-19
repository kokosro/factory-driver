extends Node3D
## Factory test pad: builds the visual reference markers that make speed and
## steering readable on an otherwise featureless plane. Everything is generated
## in-engine from primitive meshes and hash noise; there are no imported assets.
##
## Layout (the car spawns at the origin facing -Z):
##   * textured asphalt with tarmac patches, a ground grid and small motion
##     ticks every 10 m, for a constant sense of motion in every direction,
##   * a chequered START / FINISH zone with a gantry around the spawn point,
##   * a 1 km two-lane straight down -Z with distance boards every 100 m,
##   * a stop box painted on the straight, with brake markers before it,
##   * a slalom line of cones to the right of the straight,
##   * a skid pad to the left: a paler disc with painted rings, two concentric
##     cone circles and a ring of reference posts,
##   * tall pylons on a distant perimeter, so sideways motion reads at speed,
##   * a row of sheds far right, as tall parallax references (these collide).
## Painted markings, posts, pylons and cones are visual only and can be driven
## through; cones the car touches topple without slowing it down.
##
## Missions and handling tests ask the pad where things are: see the
## "Course queries" section (cone groups, slalom gates, skid circle, stop box).

const GRID_EXTENT := 1500.0  # Half-size of the gridded area [m].
const GRID_SPACING := 25.0  # Distance between grid lines [m].

const STRAIGHT_START_Z := 20.0  # Where the lane markings begin, behind the car [m].
const STRAIGHT_LENGTH := 1000.0  # Measured from the start line [m].
const START_LINE_Z := -4.0  # Just ahead of the spawn point [m].
const LANE_HALF_WIDTH := 6.0  # Edge lines sit this far from the centre line [m].
const DASH_LENGTH := 4.0
const DASH_PERIOD := 12.0
const DISTANCE_BOARD_SPACING := 100.0

const SLALOM_X := 20.0
const SLALOM_FIRST_Z := -60.0
const SLALOM_SPACING := 18.0
const SLALOM_CONE_COUNT := 14

const SKID_PAD_CENTRE := Vector3(-70.0, 0.0, -90.0)
const SKID_PAD_INNER_RADIUS := 22.0
const SKID_PAD_OUTER_RADIUS := 34.0
const SKID_PAD_SURFACE_RADIUS := 40.0  # The paler disc the circles sit on [m].
const SKID_PAD_RING_WIDTH := 0.35  # Painted rings under the cone circles [m].
const SKID_PAD_EDGE_STRIPE_WIDTH := 0.1  # Thin dark stripe either side of a ring [m].
const SKID_PAD_POST_RADIUS := 46.0  # Ring of reference posts around the pad [m].
const SKID_PAD_POST_COUNT := 12

const START_ZONE_CHEQUER_ROWS := 2  # Chequered band just past the start line.
const START_ZONE_CHEQUER_SIZE := 1.0  # Edge of one chequer square [m].
const START_BOX_SIZE := Vector2(3.4, 6.6)  # Staging box painted round the spawn [m].
const GANTRY_HALF_WIDTH := 8.0
const GANTRY_HEIGHT := 5.5

const STOP_BOX_CENTRE := Vector3(0.0, 0.0, -150.0)
const STOP_BOX_SIZE := Vector2(3.6, 7.0)  # Along X and Z [m]; the car is 1.8 x 4.2.
const STOP_BOX_MARKER_DISTANCES: Array[float] = [30.0, 20.0, 10.0]  # Before the box [m].

const MOTION_TICK_SPACING := 10.0  # Small ground dashes on this lattice [m].
const MOTION_TICK_OFFSET := 5.0  # Shifts the lattice off the 25 m grid lines [m].
const MOTION_TICK_SIZE := Vector2(0.14, 0.9)
const MOTION_TICK_X_EXTENT := 300.0  # Ticks cover |x| up to this [m] ...
const MOTION_TICK_Z_MIN := -1100.0  # ... and z from here ...
const MOTION_TICK_Z_MAX := 150.0  # ... to here [m].

const PATCH_COUNT := 260  # Faint lighter / darker tarmac repair patches.
const PATCH_MIN_SIZE := 4.0
const PATCH_MAX_SIZE := 18.0
const PATCH_MAX_ALPHA := 0.2

const PYLON_RING_CENTRE := Vector3(0.0, 0.0, -150.0)
const PYLON_RING_RADIUS := 420.0  # Distant perimeter of tall pylons [m].
const PYLON_COUNT := 24
const PYLON_SIZE := Vector3(3.0, 32.0, 3.0)

const GROUND_TEXTURE_SIZE := 256  # Pixels along one edge of the asphalt tile.
const GROUND_TEXTURE_TILE := 6.0  # The tile repeats every this many metres.
const GROUND_TEXTURE_SEED := 1997  # Same seed = same pixels, every run.

## How close the car's footprint has to come to topple a cone [m].
const CONE_TOPPLE_MARGIN := 0.28
const CONE_TOPPLE_TIME := 0.35  # Time a cone takes to fall over [s].
const CONE_PUSH_PER_SPEED := 0.12  # A hit cone skids this far per m/s of car speed [m].
const CONE_MAX_PUSH := 4.0
const CAR_HALF_SIZE := Vector2(0.9, 2.1)  # Car footprint half-extents, X and Z [m].

const GROUP_SLALOM := &"slalom_cones"
const GROUP_SKID_INNER := &"skid_inner_cones"
const GROUP_SKID_OUTER := &"skid_outer_cones"
const GROUP_STOP_BOX := &"stop_box_cones"

const SHED_X := 80.0
const SHED_SIZE := Vector3(24.0, 9.0, 48.0)
const SHED_COLORS: Array[Color] = [
	Color(0.75, 0.3, 0.22), Color(0.25, 0.45, 0.7), Color(0.85, 0.7, 0.25),
	Color(0.3, 0.6, 0.45), Color(0.6, 0.6, 0.65),
]

const COLOR_GRID := Color(0.33, 0.35, 0.38)
const COLOR_PAINT_WHITE := Color(0.93, 0.93, 0.9)
const COLOR_PAINT_YELLOW := Color(0.95, 0.78, 0.15)
const COLOR_CONE_ORANGE := Color(1.0, 0.42, 0.05)
const COLOR_CONE_BLUE := Color(0.15, 0.45, 0.95)
const COLOR_BOARD_RED := Color(0.85, 0.15, 0.15)
const COLOR_PAINT_BLACK := Color(0.06, 0.06, 0.07)
const COLOR_ASPHALT := Color(0.27, 0.28, 0.3)  # Multiplied by the ~0.78 texture.
const COLOR_SKID_SURFACE := Color(0.36, 0.36, 0.35)
const COLOR_MOTION_TICK := Color(0.62, 0.63, 0.6)
const POST_COLORS: Array[Color] = [
	Color(0.9, 0.2, 0.2), Color(0.95, 0.95, 0.92), Color(0.2, 0.5, 0.9), Color(0.95, 0.8, 0.2),
]

## The car that topples cones. Optional: without it the cones just stand.
@export var car: ArcadeCar

var _materials: Dictionary[Color, StandardMaterial3D] = {}
var _cone_mesh: CylinderMesh
var _cones: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _ground_image: Image
var _ground_material: StandardMaterial3D


func _ready() -> void:
	_rng.seed = GROUND_TEXTURE_SEED
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 0.04
	_cone_mesh.bottom_radius = 0.28
	_cone_mesh.height = 0.75
	_cone_mesh.radial_segments = 12
	_cone_mesh.rings = 1

	_build_ground_surface()
	_build_patches()
	_build_grid()
	_build_motion_ticks()
	_build_start_zone()
	_build_straight()
	_build_stop_box()
	_build_slalom()
	_build_skid_pad()
	_build_pylons()
	_build_sheds()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_car"):
		reset_cones()
	_update_cones(delta)


# =============================================================================
#  Course queries: what missions and handling tests ask the pad
# =============================================================================

## Slalom cone base positions in driving order (first = nearest the start).
static func slalom_cone_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for i in SLALOM_CONE_COUNT:
		positions.append(Vector3(SLALOM_X, 0.0, SLALOM_FIRST_Z - i * SLALOM_SPACING))
	return positions


## The skid circle: drive between the inner and the outer radius.
static func skid_circle() -> Dictionary:
	return {
		"centre": SKID_PAD_CENTRE,
		"inner_radius": SKID_PAD_INNER_RADIUS,
		"outer_radius": SKID_PAD_OUTER_RADIUS,
		"inner_group": GROUP_SKID_INNER,
		"outer_group": GROUP_SKID_OUTER,
	}


## The stop box on the straight: its centre and its size along X and Z.
static func stop_box() -> Dictionary:
	return {"centre": STOP_BOX_CENTRE, "size": STOP_BOX_SIZE, "group": GROUP_STOP_BOX}


## Standing positions of every cone in a group (GROUP_* constants).
func get_cone_positions(group: StringName) -> Array[Vector3]:
	var positions: Array[Vector3] = []
	for cone in _cones:
		if cone.group == group:
			positions.append(cone.home)
	return positions


## How many cones of a group the car has knocked over since the last reset.
func get_toppled_count(group: StringName) -> int:
	var count := 0
	for cone in _cones:
		if cone.group == group and cone.toppled:
			count += 1
	return count


## True if the cone of `group` standing at `home` has been knocked over.
func is_cone_toppled(group: StringName, home: Vector3) -> bool:
	for cone in _cones:
		if cone.group == group and cone.toppled and cone.home.distance_to(home) < 0.01:
			return true
	return false


## Stands every cone back up where it belongs.
func reset_cones() -> void:
	for cone in _cones:
		cone.toppled = false
		cone.fall = 0.0
		var node: MeshInstance3D = cone.node
		node.transform = Transform3D(Basis.IDENTITY, cone.home + Vector3.UP * _cone_mesh.height * 0.5)


## The asphalt material on the ground plane (albedo texture = the noise tile).
func get_ground_material() -> StandardMaterial3D:
	return _ground_material


## The source image of the asphalt tile, for checks that cannot read the GPU.
func get_ground_image() -> Image:
	return _ground_image


# =============================================================================
#  Builders
# =============================================================================

## Asphalt: one tileable noise texture, projected in world space so every
## surface that uses it lines up, tinted per surface by the albedo colour.
func _build_ground_surface() -> void:
	_ground_image = AsphaltTexture.build_image(GROUND_TEXTURE_SIZE, GROUND_TEXTURE_SEED)
	_ground_material = _make_asphalt_material(COLOR_ASPHALT)
	var ground_mesh := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if ground_mesh != null:
		ground_mesh.material_override = _ground_material


func _make_asphalt_material(tint: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = ImageTexture.create_from_image(_ground_image)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true
	material.uv1_scale = Vector3.ONE / GROUND_TEXTURE_TILE
	material.roughness = 0.95
	return material


## Tarmac repair patches: big faint rectangles, slightly lighter or darker than
## the road, scattered over the driving area. One MultiMesh, see-through so the
## asphalt grain shows through them.
func _build_patches() -> void:
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.95
	quad.material = material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = PATCH_COUNT
	for i in PATCH_COUNT:
		var centre := Vector3(
			_rng.randf_range(-MOTION_TICK_X_EXTENT, MOTION_TICK_X_EXTENT), 0.006,
			_rng.randf_range(MOTION_TICK_Z_MIN, MOTION_TICK_Z_MAX)
		)
		var size := Vector3(
			_rng.randf_range(PATCH_MIN_SIZE, PATCH_MAX_SIZE), 1.0,
			_rng.randf_range(PATCH_MIN_SIZE, PATCH_MAX_SIZE)
		)
		var patch_basis := Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12)).scaled_local(size)
		multimesh.set_instance_transform(i, Transform3D(patch_basis, centre))
		var shade := 0.0 if _rng.randf() < 0.6 else 1.0
		multimesh.set_instance_color(i, Color(shade, shade, shade, _rng.randf_range(0.08, PATCH_MAX_ALPHA)))
	_add_multimesh("Patches", multimesh)


## Motion ticks: a short painted dash every 10 m in both directions, turned
## alternately along X and Z, each a slightly different grey. Close enough
## together that a few stream past the car every second at any speed.
func _build_motion_ticks() -> void:
	var quad := PlaneMesh.new()
	quad.size = MOTION_TICK_SIZE
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.85
	quad.material = material

	var transforms: Array[Transform3D] = []
	var columns := int(MOTION_TICK_X_EXTENT / MOTION_TICK_SPACING)
	var rows := int((MOTION_TICK_Z_MAX - MOTION_TICK_Z_MIN) / MOTION_TICK_SPACING)
	var straight_end_z := START_LINE_Z - STRAIGHT_LENGTH
	for column in range(-columns, columns):
		var x := column * MOTION_TICK_SPACING + MOTION_TICK_OFFSET
		for row in rows:
			var z := MOTION_TICK_Z_MIN + row * MOTION_TICK_SPACING + MOTION_TICK_OFFSET
			# Not on a grid line, and not inside the straight's own lane markings.
			if is_zero_approx(fmod(x, GRID_SPACING)) or is_zero_approx(fmod(z, GRID_SPACING)):
				continue
			if absf(x) < LANE_HALF_WIDTH + 0.5 and z < STRAIGHT_START_Z and z > straight_end_z:
				continue
			var turn := 0.0 if (column + row) % 2 == 0 else PI * 0.5
			transforms.append(Transform3D(Basis(Vector3.UP, turn), Vector3(x, 0.012, z)))

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, _vary(COLOR_MOTION_TICK, 0.12))
	_add_multimesh("MotionTicks", multimesh)


## START / FINISH: a staging box round the spawn point, a chequered band past
## the start line and a gantry over the lane.
func _build_start_zone() -> void:
	var group := _add_group("StartZone")
	_add_box_outline(group, Vector3.ZERO, START_BOX_SIZE, 0.15, COLOR_PAINT_WHITE)

	var squares := int(LANE_HALF_WIDTH * 2.0 / START_ZONE_CHEQUER_SIZE)
	for row in START_ZONE_CHEQUER_ROWS:
		for column in squares:
			var color := COLOR_PAINT_WHITE if (row + column) % 2 == 0 else COLOR_PAINT_BLACK
			var centre := Vector3(
				-LANE_HALF_WIDTH + (column + 0.5) * START_ZONE_CHEQUER_SIZE, 0.0,
				START_LINE_Z - 0.3 - (row + 0.5) * START_ZONE_CHEQUER_SIZE
			)
			_add_paint(group, centre, Vector2.ONE * START_ZONE_CHEQUER_SIZE, _vary(color, 0.04))

	# Yellow hatching either side of the staging box.
	for side: float in [-1.0, 1.0]:
		for i in 5:
			var stripe := _add_paint_at_angle(group, Vector3(side * 4.0, 0.0, 3.0 - i * 1.5), Vector2(0.3, 2.6), _vary(COLOR_PAINT_YELLOW, 0.05), side * 0.7)
			stripe.name = "Hatch"

	for side: float in [-1.0, 1.0]:
		_add_box(group, Vector3(side * GANTRY_HALF_WIDTH, GANTRY_HEIGHT * 0.5, START_LINE_Z), Vector3(0.5, GANTRY_HEIGHT, 0.5), COLOR_BOARD_RED)
	var beam_segments := 8
	var segment_width := GANTRY_HALF_WIDTH * 2.0 / beam_segments
	for i in beam_segments:
		var color := COLOR_PAINT_WHITE if i % 2 == 0 else COLOR_PAINT_BLACK
		var centre := Vector3(-GANTRY_HALF_WIDTH + (i + 0.5) * segment_width, GANTRY_HEIGHT, START_LINE_Z)
		_add_box(group, centre, Vector3(segment_width, 0.8, 0.4), color)
	_add_label(group, Vector3(0.0, GANTRY_HEIGHT + 1.3, START_LINE_Z), "START / FINISH")


func _build_grid() -> void:
	var group := _add_group("Grid")
	var line_count := int(GRID_EXTENT / GRID_SPACING)
	var length := GRID_EXTENT * 2.0
	for i in range(-line_count, line_count + 1):
		var offset := i * GRID_SPACING
		_add_paint(group, Vector3(offset, 0.0, 0.0), Vector2(0.15, length), COLOR_GRID, 0.01)
		_add_paint(group, Vector3(0.0, 0.0, offset), Vector2(length, 0.15), COLOR_GRID, 0.01)


func _build_straight() -> void:
	var group := _add_group("Straight")
	var end_z := START_LINE_Z - STRAIGHT_LENGTH
	var total_length := STRAIGHT_START_Z - end_z
	var mid_z := (STRAIGHT_START_Z + end_z) * 0.5

	# Solid yellow edge lines and a wide white start line.
	for side: float in [-1.0, 1.0]:
		_add_paint(group, Vector3(side * LANE_HALF_WIDTH, 0.0, mid_z), Vector2(0.25, total_length), COLOR_PAINT_YELLOW)
	_add_paint(group, Vector3(0.0, 0.0, START_LINE_Z), Vector2(LANE_HALF_WIDTH * 2.0, 0.6), COLOR_PAINT_WHITE)

	# Dashed white centre line.
	var z := STRAIGHT_START_Z - DASH_LENGTH * 0.5
	while z > end_z:
		_add_paint(group, Vector3(0.0, 0.0, z), Vector2(0.2, DASH_LENGTH), COLOR_PAINT_WHITE)
		z -= DASH_PERIOD

	# Distance boards: a pair of posts and a label every 100 m, colours
	# alternating so neighbouring boards are easy to tell apart at speed.
	var board_count := int(STRAIGHT_LENGTH / DISTANCE_BOARD_SPACING)
	for i in range(1, board_count + 1):
		var distance := i * DISTANCE_BOARD_SPACING
		var board_z := START_LINE_Z - distance
		var color := COLOR_BOARD_RED if i % 2 == 1 else COLOR_PAINT_WHITE
		for side: float in [-1.0, 1.0]:
			var post_x := side * (LANE_HALF_WIDTH + 1.5)
			_add_box(group, Vector3(post_x, 1.25, board_z), Vector3(0.35, 2.5, 0.35), color)
			_add_label(group, Vector3(post_x, 3.3, board_z), "%d m" % distance)
		_add_paint(group, Vector3(0.0, 0.0, board_z), Vector2(LANE_HALF_WIDTH * 2.0, 0.3), color)


func _build_slalom() -> void:
	var group := _add_group("Slalom")
	for cone_position in slalom_cone_positions():
		_add_cone(group, cone_position, COLOR_CONE_ORANGE, GROUP_SLALOM)
	# A painted spot under every cone (it stays when the cone is knocked away)
	# and entry / exit bars across the line.
	for cone_position in slalom_cone_positions():
		_add_ring(group, 0.0, 0.45, 0.025, _vary(COLOR_PAINT_WHITE, 0.05), 0.0, TAU, cone_position)
	var slalom_end_z := SLALOM_FIRST_Z - (SLALOM_CONE_COUNT - 1) * SLALOM_SPACING
	for bar_z: float in [SLALOM_FIRST_Z + SLALOM_SPACING, slalom_end_z - SLALOM_SPACING]:
		_add_paint(group, Vector3(SLALOM_X, 0.0, bar_z), Vector2(10.0, 0.4), COLOR_PAINT_YELLOW)


## Stop box: a hatched bay on the straight to brake into, a red stop bar at its
## far end, a cone on each corner and brake markers on the way in.
func _build_stop_box() -> void:
	var group := _add_group("StopBox")
	var half := STOP_BOX_SIZE * 0.5
	_add_box_outline(group, STOP_BOX_CENTRE, STOP_BOX_SIZE, 0.2, COLOR_PAINT_YELLOW)
	_add_paint(group, STOP_BOX_CENTRE + Vector3(0.0, 0.0, -half.y - 0.5), Vector2(STOP_BOX_SIZE.x + 1.6, 0.5), COLOR_BOARD_RED, 0.03)
	for i in 4:
		var z := STOP_BOX_CENTRE.z - half.y + (i + 0.5) * STOP_BOX_SIZE.y / 4.0
		_add_paint_at_angle(group, Vector3(STOP_BOX_CENTRE.x, 0.0, z), Vector2(0.18, STOP_BOX_SIZE.x * 0.95), _vary(COLOR_PAINT_YELLOW, 0.05), 0.9)
	for corner_x: float in [-1.0, 1.0]:
		for corner_z: float in [-1.0, 1.0]:
			var corner := STOP_BOX_CENTRE + Vector3(corner_x * (half.x + 0.5), 0.0, corner_z * (half.y + 0.5))
			_add_cone(group, corner, COLOR_CONE_BLUE, GROUP_STOP_BOX)
	# Brake markers: 3, 2, 1 short bars either side of the lane.
	for i in STOP_BOX_MARKER_DISTANCES.size():
		var marker_z := STOP_BOX_CENTRE.z + half.y + STOP_BOX_MARKER_DISTANCES[i]
		var bars := STOP_BOX_MARKER_DISTANCES.size() - i
		for side: float in [-1.0, 1.0]:
			for bar in bars:
				_add_paint(group, Vector3(side * (LANE_HALF_WIDTH - 1.2), 0.0, marker_z - bar * 0.9), Vector2(1.6, 0.4), _vary(COLOR_PAINT_WHITE, 0.04))


## Skid pad: a paler disc, painted rings under the two cone circles (each with
## thin dark edge stripes), a dashed driving line between them, a centre spot
## and a ring of coloured posts just outside.
func _build_skid_pad() -> void:
	var group := _add_group("SkidPad")
	var surface := _add_ring(group, 0.0, SKID_PAD_SURFACE_RADIUS, 0.015, COLOR_SKID_SURFACE)
	surface.material_override = _make_asphalt_material(COLOR_SKID_SURFACE)
	_add_ring(group, SKID_PAD_SURFACE_RADIUS - 0.4, SKID_PAD_SURFACE_RADIUS, 0.03, _vary(COLOR_PAINT_WHITE, 0.05))

	var ring_colors: Array[Color] = [COLOR_CONE_ORANGE, COLOR_CONE_BLUE]
	var ring_radii: Array[float] = [SKID_PAD_INNER_RADIUS, SKID_PAD_OUTER_RADIUS]
	for i in ring_radii.size():
		var inner := ring_radii[i] - SKID_PAD_RING_WIDTH * 0.5
		var outer := ring_radii[i] + SKID_PAD_RING_WIDTH * 0.5
		_add_ring(group, inner, outer, 0.03, _vary(ring_colors[i].lerp(COLOR_PAINT_WHITE, 0.35), 0.05))
		_add_ring(group, inner - SKID_PAD_EDGE_STRIPE_WIDTH, inner, 0.03, COLOR_PAINT_BLACK)
		_add_ring(group, outer, outer + SKID_PAD_EDGE_STRIPE_WIDTH, 0.03, COLOR_PAINT_BLACK)

	# Dashed driving line midway between the circles, and a centre spot.
	var mid_radius := (SKID_PAD_INNER_RADIUS + SKID_PAD_OUTER_RADIUS) * 0.5
	var dash_count := 36
	for i in dash_count:
		var from := TAU * i / dash_count
		_add_ring(group, mid_radius - 0.1, mid_radius + 0.1, 0.03, _vary(COLOR_PAINT_WHITE, 0.06), from, from + TAU / dash_count * 0.5)
	_add_ring(group, 0.0, 1.2, 0.03, COLOR_PAINT_YELLOW)

	_add_cone_circle(group, SKID_PAD_INNER_RADIUS, 32, COLOR_CONE_ORANGE, GROUP_SKID_INNER)
	_add_cone_circle(group, SKID_PAD_OUTER_RADIUS, 48, COLOR_CONE_BLUE, GROUP_SKID_OUTER)

	for i in SKID_PAD_POST_COUNT:
		var angle := TAU * i / SKID_PAD_POST_COUNT
		var base := SKID_PAD_CENTRE + Vector3(cos(angle), 0.0, sin(angle)) * SKID_PAD_POST_RADIUS
		_add_post(group, base, 0.25, 3.5, POST_COLORS[i % POST_COLORS.size()])


## Tall pylons on a wide circle round the whole course: far enough to sit still
## while you drive straight, close enough to sweep across the screen in a slide.
func _build_pylons() -> void:
	var group := _add_group("Pylons")
	for i in PYLON_COUNT:
		var angle := TAU * i / PYLON_COUNT
		var base := PYLON_RING_CENTRE + Vector3(cos(angle), 0.0, sin(angle)) * PYLON_RING_RADIUS
		var color := POST_COLORS[i % POST_COLORS.size()]
		_add_box(group, base + Vector3.UP * PYLON_SIZE.y * 0.5, PYLON_SIZE, color)
		_add_box(group, base + Vector3.UP * (PYLON_SIZE.y + 1.0), Vector3(5.0, 2.0, 5.0), COLOR_PAINT_BLACK)


func _build_sheds() -> void:
	var group := _add_group("Sheds")
	for i in SHED_COLORS.size():
		var centre := Vector3(SHED_X, SHED_SIZE.y * 0.5, -80.0 - i * 190.0)
		_add_box(group, centre, SHED_SIZE, SHED_COLORS[i], true)


func _add_cone_circle(parent: Node3D, radius: float, count: int, color: Color, group: StringName) -> void:
	for i in count:
		var angle := TAU * i / count
		_add_cone(parent, SKID_PAD_CENTRE + Vector3(cos(angle), 0.0, sin(angle)) * radius, color, group)


func _add_group(group_name: String) -> Node3D:
	var group := Node3D.new()
	group.name = group_name
	add_child(group)
	return group


## Flat painted marking on the ground. `footprint` is its size along X and Z [m].
## `thickness` doubles as draw order: thicker paint sits on top of thinner paint.
func _add_paint(parent: Node3D, centre: Vector3, footprint: Vector2, color: Color, thickness := 0.02) -> void:
	var size := Vector3(footprint.x, thickness, footprint.y)
	var paint := _add_box(parent, centre + Vector3.UP * thickness * 0.5, size, color)
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _add_box(parent: Node3D, centre: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _get_material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = centre
	parent.add_child(instance)

	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collider := CollisionShape3D.new()
		collider.shape = shape
		var body := StaticBody3D.new()
		body.add_child(collider)
		instance.add_child(body)
	return instance


## A cone in a named group (GROUP_*). No collision: see _update_cones.
func _add_cone(parent: Node3D, base_position: Vector3, color: Color, group: StringName) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _cone_mesh
	instance.material_override = _get_material(color)
	instance.position = base_position + Vector3.UP * _cone_mesh.height * 0.5
	instance.add_to_group(group)
	parent.add_child(instance)
	_cones.append({
		"node": instance, "home": base_position, "group": group,
		"toppled": false, "fall": 0.0, "push": Vector3.ZERO,
	})


## Knock-away-lite: a cone inside the car's footprint falls over and skids off
## the way the car was going. Purely visual; the car never feels it.
func _update_cones(delta: float) -> void:
	if car == null:
		return
	var to_car := car.global_transform.affine_inverse()
	var reach := CAR_HALF_SIZE + Vector2.ONE * CONE_TOPPLE_MARGIN
	for cone in _cones:
		if not cone.toppled:
			var local: Vector3 = to_car * cone.home
			if absf(local.x) < reach.x and absf(local.z) < reach.y:
				cone.toppled = true
				var push := Vector3(car.velocity.x, 0.0, car.velocity.z)
				cone.push = push.limit_length(CONE_MAX_PUSH / CONE_PUSH_PER_SPEED) * CONE_PUSH_PER_SPEED
		elif cone.fall < 1.0:
			cone.fall = minf(cone.fall + delta / CONE_TOPPLE_TIME, 1.0)
			var push: Vector3 = cone.push
			var direction := push.normalized() if push.length() > 0.01 else Vector3.FORWARD
			var tip_axis := Vector3.UP.cross(direction).normalized()
			var tip_basis := Basis(tip_axis, cone.fall * PI * 0.5)
			var height := lerpf(_cone_mesh.height * 0.5, _cone_mesh.bottom_radius, cone.fall)
			var node: MeshInstance3D = cone.node
			node.transform = Transform3D(tip_basis, cone.home + push * cone.fall + Vector3.UP * height)


## Flat painted ring (or disc, or arc) on the ground round `centre`.
func _add_ring(
	parent: Node3D, inner_radius: float, outer_radius: float, height: float, color: Color,
	from_angle := 0.0, to_angle := TAU, centre := SKID_PAD_CENTRE
) -> MeshInstance3D:
	var segments := maxi(int(96.0 * (to_angle - from_angle) / TAU), 2)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_normal(Vector3.UP)
	for i in segments:
		var a0 := lerpf(from_angle, to_angle, float(i) / segments)
		var a1 := lerpf(from_angle, to_angle, float(i + 1) / segments)
		var dir0 := Vector3(cos(a0), 0.0, sin(a0))
		var dir1 := Vector3(cos(a1), 0.0, sin(a1))
		# Two triangles per segment, wound clockwise seen from above (front face up).
		for corner: Vector3 in [
			dir0 * inner_radius, dir0 * outer_radius, dir1 * outer_radius,
			dir0 * inner_radius, dir1 * outer_radius, dir1 * inner_radius,
		]:
			surface.add_vertex(corner)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = _get_material(color)
	instance.position = centre + Vector3.UP * height
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


## Painted rectangle outline, `line` metres wide, lying on the ground.
func _add_box_outline(parent: Node3D, centre: Vector3, size: Vector2, line: float, color: Color) -> void:
	var half := size * 0.5
	for side: float in [-1.0, 1.0]:
		_add_paint(parent, centre + Vector3(side * half.x, 0.0, 0.0), Vector2(line, size.y + line), color, 0.03)
		_add_paint(parent, centre + Vector3(0.0, 0.0, side * half.y), Vector2(size.x + line, line), color, 0.03)


## Painted bar turned by `angle` about the vertical [rad].
func _add_paint_at_angle(parent: Node3D, centre: Vector3, footprint: Vector2, color: Color, angle: float) -> MeshInstance3D:
	var paint := _add_box(parent, centre + Vector3.UP * 0.0125, Vector3(footprint.x, 0.025, footprint.y), color)
	paint.rotation.y = angle
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return paint


## Upright round post standing on `base`. Visual only.
func _add_post(parent: Node3D, base: Vector3, radius: float, height: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	mesh.material = _get_material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = base + Vector3.UP * height * 0.5
	parent.add_child(instance)


func _add_multimesh(node_name: String, multimesh: MultiMesh) -> void:
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multimesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## `color` with its brightness nudged by up to +/- `amount`, so repeated paint
## never looks stamped. Deterministic: the pad's seeded generator.
func _vary(color: Color, amount: float) -> Color:
	var shift := _rng.randf_range(-amount, amount)
	return Color(
		clampf(color.r + shift, 0.0, 1.0), clampf(color.g + shift, 0.0, 1.0),
		clampf(color.b + shift, 0.0, 1.0), color.a
	)


func _add_label(parent: Node3D, label_position: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 160
	label.outline_size = 32
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = label_position
	parent.add_child(label)


func _get_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.8
		_materials[color] = material
	return _materials[color]
