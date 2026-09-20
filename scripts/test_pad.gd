class_name TestPad
extends Node3D
## Factory test pad: builds the visual reference markers that make speed and
## steering readable on an otherwise featureless plane. Everything is generated
## in-engine from primitive meshes and hash noise; there are no imported assets.
##
## Layout (the car spawns at the origin facing -Z):
##   * the ground itself, shaped to the elevation of the road (RoadProfile): a
##     gentle swell down the straight and across the open pad, level round the
##     start, the stop box, the slalom and the skid pad; everything below lies
##     or stands on it,
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

# The ground mesh: a lattice of heights over everywhere the road's elevation is
# not 0, fine where the course is, coarser beyond; level ground from its edge
# out to GROUND_FAR_EXTENT. Both steps divide GRID_SPACING, so every grid line
# runs along a row of mesh vertices.
const GROUND_MESH_MIN := RoadProfile.FAR_FIELD_MIN - Vector2.ONE * RoadProfile.FAR_FIELD_RAMP  # (x, z) [m].
const GROUND_MESH_MAX := RoadProfile.FAR_FIELD_MAX + Vector2.ONE * RoadProfile.FAR_FIELD_RAMP  # (x, z) [m].
const GROUND_CORE_MIN := Vector2(-300.0, -1100.0)  # The finely meshed part (x, z) [m]: where the ticks and patches are.
const GROUND_CORE_MAX := Vector2(300.0, 150.0)
const GROUND_FINE_STEP := 5.0  # Vertex spacing in the core [m]: the mesh strays < 2 mm from the swell.
const GROUND_COARSE_STEP := 12.5  # Vertex spacing outside it [m]: < 1 cm.
const GROUND_FAR_EXTENT := 2000.0  # Half-size of the whole ground [m].
const GROUND_FAR_OVERLAP := 1.0  # The level far field tucks this far under the mesh's (level) rim [m] ...
const GROUND_FAR_DROP := 0.002  # ... this far below it [m], so no seam shows.

const PAINT_TILT_MIN_SPAN := 0.5  # Shortest baseline a marking's tilt is measured over [m].
const PATCH_LIFT := 0.006  # Height of the repair patches above the ground [m].
const MOTION_TICK_LIFT := 0.012  # Height of the motion ticks above the ground [m].
const GRID_LIFT := 0.01  # Height of the grid lines above the ground [m].
const PAINT_LIFT := 0.02  # Height of the lane edge lines above the ground [m].
const TEST_DIP_BAR_SIZE := Vector2(6.0, 0.3)  # Painted bar at either lip of the road's test dip [m].

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

## The road: the height field the ground is shaped to, everything on the pad
## stands on and the car feels. In main.tscn the same resource as the car's.
## None = the default road (RoadProfile's constants), handed on to a car that
## has none of its own, so pad and car never disagree about the ground.
@export var road_profile: RoadProfile

var _materials: Dictionary[Color, StandardMaterial3D] = {}
var _cone_mesh: CylinderMesh
var _cones: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _ground_image: Image
var _ground_material: StandardMaterial3D
var _ground_collider: CollisionShape3D

## The ground mesh's lattice: vertex x and z coordinates [m], the elevation at
## every vertex (row by row along z) and where a coordinate sits in its list.
var _ground_xs := PackedFloat64Array()
var _ground_zs := PackedFloat64Array()
var _ground_heights := PackedFloat64Array()
var _ground_x_index: Dictionary[float, int] = {}
var _ground_z_index: Dictionary[float, int] = {}


func _ready() -> void:
	if road_profile == null:
		road_profile = RoadProfile.new()
	if car != null and car.road_profile == null:
		car.road_profile = road_profile
	_rng.seed = GROUND_TEXTURE_SEED
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 0.04
	_cone_mesh.bottom_radius = 0.28
	_cone_mesh.height = 0.75
	_cone_mesh.radial_segments = 12
	_cone_mesh.rings = 1
	_ground_collider = get_node_or_null("Ground/CollisionShape3D") as CollisionShape3D

	_build_ground_surface()
	_build_patches()
	_build_grid()
	_build_motion_ticks()
	_build_start_zone()
	_build_straight()
	_build_stop_box()
	_build_test_dip()
	_build_slalom()
	_build_skid_pad()
	_build_pylons()
	_build_sheds()


func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("reset_car"):
		reset_cones()
	_follow_car()
	_update_cones(delta)


# =============================================================================
#  Course queries: what missions and handling tests ask the pad
# =============================================================================

## Height of the road at (x, z) [m], micro-bumps and all: what a tyre rolls
## over there.
func sample_height(x: float, z: float) -> float:
	return road_profile.sample_height(x, z)


## Height of the ground at (x, z) [m] as the pad shows it: the road's elevation.
## What everything placed on the pad stands on.
func elevation_height(x: float, z: float) -> float:
	return road_profile.elevation_height(x, z)


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


## The ground's collision is one endless level plane. Every tick it is put at
## the height of the road's elevation under the car. The car does not stand on
## it: its body rides on its springs, ArcadeCar.GROUND_CLEARANCE above the road
## (was: the car's collision box lay on this plane and the car lifted itself by
## the elevation change every tick). The plane is what the body's underside
## meets if the suspension ever bottoms out, 5 cm into the bump stops, and what
## stops a car with no springs left from falling through the world. Only the
## collision shape moves; the ground mesh stays put. (The sheds are the only
## other things that collide.)
func _follow_car() -> void:
	if car == null or _ground_collider == null:
		return
	var height := elevation_height(car.global_position.x, car.global_position.z)
	if _ground_collider.position.y != height:
		_ground_collider.position.y = height


# =============================================================================
#  Builders
# =============================================================================

## Asphalt: one tileable noise texture, projected in world space so every
## surface that uses it lines up, tinted per surface by the albedo colour. The
## ground it goes on is a mesh shaped to the road's elevation (the micro-bumps
## are felt, not shown), replacing whatever mesh the scene's
## Ground/MeshInstance3D came with.
func _build_ground_surface() -> void:
	_ground_image = AsphaltTexture.build_image(GROUND_TEXTURE_SIZE, GROUND_TEXTURE_SEED)
	_ground_material = _make_asphalt_material(COLOR_ASPHALT)
	var ground_mesh := get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	if ground_mesh == null:
		ground_mesh = MeshInstance3D.new()
		ground_mesh.name = "GroundSurface"
		add_child(ground_mesh)
	ground_mesh.mesh = _build_ground_mesh()
	ground_mesh.material_override = _ground_material


## The ground: the elevation sampled on the lattice, plus four level quads out
## to GROUND_FAR_EXTENT (the elevation is 0 all along the lattice's rim).
func _build_ground_mesh() -> ArrayMesh:
	_ground_xs = _lattice_lines(GROUND_MESH_MIN.x, GROUND_CORE_MIN.x, GROUND_CORE_MAX.x, GROUND_MESH_MAX.x)
	_ground_zs = _lattice_lines(GROUND_MESH_MIN.y, GROUND_CORE_MIN.y, GROUND_CORE_MAX.y, GROUND_MESH_MAX.y)
	var columns := _ground_xs.size()
	var rows := _ground_zs.size()
	for ix in columns:
		_ground_x_index[_ground_xs[ix]] = ix
	for iz in rows:
		_ground_z_index[_ground_zs[iz]] = iz

	_ground_heights.resize(columns * rows)
	var vertices := PackedVector3Array()
	vertices.resize(columns * rows)
	for iz in rows:
		var z := _ground_zs[iz]
		for ix in columns:
			var height := elevation_height(_ground_xs[ix], z)
			_ground_heights[iz * columns + ix] = height
			vertices[iz * columns + ix] = Vector3(_ground_xs[ix], height, z)

	# Normals from the neighbours' heights; the rim is level.
	var normals := PackedVector3Array()
	normals.resize(columns * rows)
	normals.fill(Vector3.UP)
	for iz in range(1, rows - 1):
		var run_z := _ground_zs[iz + 1] - _ground_zs[iz - 1]
		for ix in range(1, columns - 1):
			var i := iz * columns + ix
			var slope_x := (_ground_heights[i + 1] - _ground_heights[i - 1]) / (_ground_xs[ix + 1] - _ground_xs[ix - 1])
			var slope_z := (_ground_heights[i + columns] - _ground_heights[i - columns]) / run_z
			if slope_x != 0.0 or slope_z != 0.0:
				normals[i] = Vector3(-slope_x, 1.0, -slope_z).normalized()

	# Two triangles per cell, wound clockwise seen from above (front face up).
	var indices := PackedInt32Array()
	indices.resize((columns - 1) * (rows - 1) * 6)
	var next := 0
	for iz in rows - 1:
		for ix in columns - 1:
			var i := iz * columns + ix
			indices[next] = i
			indices[next + 1] = i + 1
			indices[next + 2] = i + columns + 1
			indices[next + 3] = i
			indices[next + 4] = i + columns + 1
			indices[next + 5] = i + columns
			next += 6

	# The level far field, tucked a little under the rim.
	var far := GROUND_FAR_EXTENT
	var inner_min := GROUND_MESH_MIN + Vector2.ONE * GROUND_FAR_OVERLAP
	var inner_max := GROUND_MESH_MAX - Vector2.ONE * GROUND_FAR_OVERLAP
	for quad: Rect2 in [
		Rect2(-far, -far, far * 2.0, far + inner_min.y),
		Rect2(-far, inner_max.y, far * 2.0, far - inner_max.y),
		Rect2(-far, inner_min.y, far + inner_min.x, inner_max.y - inner_min.y),
		Rect2(inner_max.x, inner_min.y, far - inner_max.x, inner_max.y - inner_min.y),
	]:
		var first := vertices.size()
		for corner: Vector2 in [quad.position, Vector2(quad.end.x, quad.position.y), quad.end, Vector2(quad.position.x, quad.end.y)]:
			vertices.append(Vector3(corner.x, -GROUND_FAR_DROP, corner.y))
			normals.append(Vector3.UP)
		for offset: int in [0, 1, 2, 0, 2, 3]:
			indices.append(first + offset)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Lattice coordinates along one axis: coarse steps from `from` to `core_from`,
## fine steps to `core_to`, coarse steps on to `to` (all whole steps apart).
func _lattice_lines(from: float, core_from: float, core_to: float, to: float) -> PackedFloat64Array:
	var lines := PackedFloat64Array()
	for i in roundi((core_from - from) / GROUND_COARSE_STEP):
		lines.append(from + i * GROUND_COARSE_STEP)
	for i in roundi((core_to - core_from) / GROUND_FINE_STEP):
		lines.append(core_from + i * GROUND_FINE_STEP)
	for i in roundi((to - core_to) / GROUND_COARSE_STEP) + 1:
		lines.append(core_to + i * GROUND_COARSE_STEP)
	return lines


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
## the road, scattered over the driving area. One mesh, see-through so the
## asphalt grain shows through them; every patch is cut into pieces no longer
## than the ground mesh's own, each corner laid on the ground, so a big patch
## follows the swell instead of bridging it.
func _build_patches() -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.95

	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for i in PATCH_COUNT:
		var centre := Vector3(
			_rng.randf_range(-MOTION_TICK_X_EXTENT, MOTION_TICK_X_EXTENT), 0.0,
			_rng.randf_range(MOTION_TICK_Z_MIN, MOTION_TICK_Z_MAX)
		)
		var size := Vector2(
			_rng.randf_range(PATCH_MIN_SIZE, PATCH_MAX_SIZE),
			_rng.randf_range(PATCH_MIN_SIZE, PATCH_MAX_SIZE)
		)
		var turn := Basis(Vector3.UP, _rng.randf_range(-0.12, 0.12))
		var shade := 0.0 if _rng.randf() < 0.6 else 1.0
		var color := Color(shade, shade, shade, _rng.randf_range(0.08, PATCH_MAX_ALPHA))

		var columns := ceili(size.x / GROUND_FINE_STEP)
		var rows := ceili(size.y / GROUND_FINE_STEP)
		var first := vertices.size()
		for row in rows + 1:
			for column in columns + 1:
				var local := Vector3((float(column) / columns - 0.5) * size.x, 0.0, (float(row) / rows - 0.5) * size.y)
				var point := centre + turn * local
				point.y = _ground_y(point.x, point.z) + PATCH_LIFT
				vertices.append(point)
				colors.append(color)
		for row in rows:
			for column in columns:
				var corner := first + row * (columns + 1) + column
				for offset: int in [0, 1, columns + 2, 0, columns + 2, columns + 1]:
					indices.append(corner + offset)

	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var instance := MeshInstance3D.new()
	instance.name = "Patches"
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


## Motion ticks: a short painted dash every 10 m in both directions, turned
## alternately along X and Z, each a slightly different grey. Close enough
## together that a few stream past the car every second at any speed. Each lies
## on the ground where it is, tilted to the slope.
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
			var tick_basis := _ground_basis(x, z, MOTION_TICK_SIZE * 0.5, turn)
			transforms.append(Transform3D(tick_basis, Vector3(x, _ground_y(x, z) + MOTION_TICK_LIFT, z)))

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


## Ground grid: one mesh of flat ribbons. A line that crosses the ground mesh
## takes its heights from the row of mesh vertices it runs along (both lattice
## steps divide GRID_SPACING), so it lies on the ground exactly; level stretches
## and the level far field get by with their end points.
func _build_grid() -> void:
	var ribbons := Ribbons.new()
	var line_count := int(GRID_EXTENT / GRID_SPACING)
	var columns := _ground_xs.size()
	for i in range(-line_count, line_count + 1):
		var offset := i * GRID_SPACING
		# Along Z at x = offset, then along X at z = offset.
		var along_z := PackedVector3Array([Vector3(offset, GRID_LIFT, -GRID_EXTENT)])
		if _ground_x_index.has(offset):
			var ix := _ground_x_index[offset]
			for iz in _ground_zs.size():
				along_z.append(Vector3(offset, _ground_heights[iz * columns + ix] + GRID_LIFT, _ground_zs[iz]))
		along_z.append(Vector3(offset, GRID_LIFT, GRID_EXTENT))
		ribbons.add(along_z, Vector3.RIGHT * 0.075)

		var along_x := PackedVector3Array([Vector3(-GRID_EXTENT, GRID_LIFT, offset)])
		if _ground_z_index.has(offset):
			var iz := _ground_z_index[offset]
			for ix in columns:
				along_x.append(Vector3(_ground_xs[ix], _ground_heights[iz * columns + ix] + GRID_LIFT, offset))
		along_x.append(Vector3(GRID_EXTENT, GRID_LIFT, offset))
		ribbons.add(along_x, Vector3.FORWARD * 0.075)
	var instance := ribbons.commit(_get_material(COLOR_GRID))
	instance.name = "Grid"
	add_child(instance)


func _build_straight() -> void:
	var group := _add_group("Straight")
	var end_z := START_LINE_Z - STRAIGHT_LENGTH

	# Solid yellow edge lines, as ribbons laid on the ground at every row of
	# the ground mesh they cross, and a wide white start line.
	var edge_lines := Ribbons.new()
	for side: float in [-1.0, 1.0]:
		var x := side * LANE_HALF_WIDTH
		var points := PackedVector3Array()
		var z := STRAIGHT_START_Z
		while z > end_z:
			points.append(Vector3(x, _ground_y(x, z) + PAINT_LIFT, z))
			z -= GROUND_FINE_STEP
		points.append(Vector3(x, _ground_y(x, end_z) + PAINT_LIFT, end_z))
		edge_lines.add(points, Vector3.LEFT * 0.125)
	var edge_instance := edge_lines.commit(_get_material(COLOR_PAINT_YELLOW))
	edge_instance.name = "EdgeLines"
	group.add_child(edge_instance)
	_add_paint(group, Vector3(0.0, 0.0, START_LINE_Z), Vector2(LANE_HALF_WIDTH * 2.0, 0.6), COLOR_PAINT_WHITE)

	# Dashed white centre line.
	var dash_z := STRAIGHT_START_Z - DASH_LENGTH * 0.5
	while dash_z > end_z:
		_add_paint(group, Vector3(0.0, 0.0, dash_z), Vector2(0.2, DASH_LENGTH), COLOR_PAINT_WHITE)
		dash_z -= DASH_PERIOD

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


## The road's test dip (RoadProfile.TEST_DIP_CENTRE) is felt, not shown: a
## yellow bar at either lip says where it is.
func _build_test_dip() -> void:
	if road_profile.test_dip_depth <= 0.0:
		return
	var group := _add_group("TestDip")
	var centre := RoadProfile.TEST_DIP_CENTRE
	for side: float in [-1.0, 1.0]:
		var lip_z := centre.y + side * RoadProfile.TEST_DIP_LENGTH * 0.5
		_add_paint(group, Vector3(centre.x, 0.0, lip_z), TEST_DIP_BAR_SIZE, COLOR_PAINT_YELLOW)


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


## Sheds: solid, so each stands on the lowest corner of its footprint.
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


## Height of the ground at (x, z) [m]: where anything placed there stands. All
## the placement helpers below go through it; the `centre` / `base` they take
## counts its height from the ground.
func _ground_y(x: float, z: float) -> float:
	return elevation_height(x, z)


## Orientation of something flat lying on the ground at (x, z), turned by `turn`
## about the vertical [rad]: tilted to the slope between the ends of its
## footprint (`half_size`: half its length along its own X and Z [m]). On level
## ground exactly the turn and nothing else.
func _ground_basis(x: float, z: float, half_size: Vector2, turn := 0.0) -> Basis:
	var flat := Basis(Vector3.UP, turn)
	var reach_x := flat.x * maxf(half_size.x, PAINT_TILT_MIN_SPAN)
	var reach_z := flat.z * maxf(half_size.y, PAINT_TILT_MIN_SPAN)
	var rise_x := _ground_y(x + reach_x.x, z + reach_x.z) - _ground_y(x - reach_x.x, z - reach_x.z)
	var rise_z := _ground_y(x + reach_z.x, z + reach_z.z) - _ground_y(x - reach_z.x, z - reach_z.z)
	if rise_x == 0.0 and rise_z == 0.0:
		return flat
	var along_x := (reach_x * 2.0 + Vector3.UP * rise_x).normalized()
	var along_z := (reach_z * 2.0 + Vector3.UP * rise_z).normalized()
	var up := along_z.cross(along_x).normalized()
	return Basis(along_x, up, along_x.cross(up))


## Flat painted marking lying on the ground. `footprint` is its size along X and
## Z [m]. `thickness` doubles as draw order: thicker paint sits on top of
## thinner paint. Short enough to lie straight: the long lines are Ribbons.
func _add_paint(parent: Node3D, centre: Vector3, footprint: Vector2, color: Color, thickness := 0.02) -> void:
	var size := Vector3(footprint.x, thickness, footprint.y)
	var paint := _add_box(parent, centre + Vector3.UP * thickness * 0.5, size, color)
	paint.basis = _ground_basis(centre.x, centre.z, footprint * 0.5)
	paint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A box with its `centre` this high above the ground. A `solid` one collides,
## and stands on the lowest corner of its footprint rather than its middle.
func _add_box(parent: Node3D, centre: Vector3, size: Vector3, color: Color, solid := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _get_material(color)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	var ground := _ground_y(centre.x, centre.z)
	if solid:
		for corner_x: float in [-0.5, 0.5]:
			for corner_z: float in [-0.5, 0.5]:
				ground = minf(ground, _ground_y(centre.x + corner_x * size.x, centre.z + corner_z * size.z))
	instance.position = centre + Vector3.UP * ground
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


## A cone in a named group (GROUP_*), standing on the ground at `base_position`
## (its home, ground height included). No collision: see _update_cones.
func _add_cone(parent: Node3D, base_position: Vector3, color: Color, group: StringName) -> void:
	base_position.y += _ground_y(base_position.x, base_position.z)
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


## Flat painted ring (or disc, or arc) on the ground round `centre`, level: the
## pad only paints them where the ground is (skid pad, slalom spots).
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
	instance.position = centre + Vector3.UP * (_ground_y(centre.x, centre.z) + height)
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
	paint.basis = _ground_basis(centre.x, centre.z, footprint * 0.5, angle)
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
	instance.position = base + Vector3.UP * (_ground_y(base.x, base.z) + height * 0.5)
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


## Billboard text, `label_position` counting its height from the ground.
func _add_label(parent: Node3D, label_position: Vector3, text: String) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 160
	label.outline_size = 32
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = label_position + Vector3.UP * _ground_y(label_position.x, label_position.z)
	parent.add_child(label)


func _get_material(color: Color) -> StandardMaterial3D:
	if not _materials.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.8
		_materials[color] = material
	return _materials[color]


## Flat painted lines too long to lie straight on the swell: each a strip of
## quads through a list of points on the ground, all in one mesh.
class Ribbons:
	var _vertices := PackedVector3Array()
	var _indices := PackedInt32Array()

	## One line through `points` (already lifted to paint height), reaching
	## `half_width` to either side: a vector across the line [m], pointing to
	## the right of the way the points run, so the quads face up. Points in
	## the middle of a level stretch are left out.
	func add(points: PackedVector3Array, half_width: Vector3) -> void:
		var previous := -1
		for i in points.size():
			var inside := i > 0 and i < points.size() - 1
			if inside and points[i - 1].y == points[i].y and points[i].y == points[i + 1].y:
				continue
			var first := _vertices.size()
			_vertices.append(points[i] - half_width)
			_vertices.append(points[i] + half_width)
			if previous >= 0:
				for index: int in [previous, previous + 1, first + 1, previous, first + 1, first]:
					_indices.append(index)
			previous = first

	func commit(material: Material) -> MeshInstance3D:
		var normals := PackedVector3Array()
		normals.resize(_vertices.size())
		normals.fill(Vector3.UP)
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = _vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_INDEX] = _indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return instance
