extends Node3D
## Factory test pad: builds the visual reference markers that make speed and
## steering readable on an otherwise featureless plane. Everything is generated
## in-engine from primitive meshes; there are no imported assets.
##
## Layout (the car spawns at the origin facing -Z):
##   * a ground grid, for a constant sense of motion in every direction,
##   * a 1 km two-lane straight down -Z with distance boards every 100 m,
##   * a slalom line of cones to the right of the straight,
##   * a skid pad (two concentric cone circles) to the left,
##   * a row of sheds far right, as tall parallax references (these collide).
## Painted markings and cones are visual only and can be driven through.

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

var _materials: Dictionary[Color, StandardMaterial3D] = {}
var _cone_mesh: CylinderMesh


func _ready() -> void:
	_cone_mesh = CylinderMesh.new()
	_cone_mesh.top_radius = 0.04
	_cone_mesh.bottom_radius = 0.28
	_cone_mesh.height = 0.75
	_cone_mesh.radial_segments = 12
	_cone_mesh.rings = 1

	_build_grid()
	_build_straight()
	_build_slalom()
	_build_skid_pad()
	_build_sheds()


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
	for i in SLALOM_CONE_COUNT:
		_add_cone(group, Vector3(SLALOM_X, 0.0, SLALOM_FIRST_Z - i * SLALOM_SPACING), COLOR_CONE_ORANGE)


func _build_skid_pad() -> void:
	var group := _add_group("SkidPad")
	_add_cone_circle(group, SKID_PAD_INNER_RADIUS, 32, COLOR_CONE_ORANGE)
	_add_cone_circle(group, SKID_PAD_OUTER_RADIUS, 48, COLOR_CONE_BLUE)


func _build_sheds() -> void:
	var group := _add_group("Sheds")
	for i in SHED_COLORS.size():
		var centre := Vector3(SHED_X, SHED_SIZE.y * 0.5, -80.0 - i * 190.0)
		_add_box(group, centre, SHED_SIZE, SHED_COLORS[i], true)


func _add_cone_circle(parent: Node3D, radius: float, count: int, color: Color) -> void:
	for i in count:
		var angle := TAU * i / count
		_add_cone(parent, SKID_PAD_CENTRE + Vector3(cos(angle), 0.0, sin(angle)) * radius, color)


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


func _add_cone(parent: Node3D, base_position: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _cone_mesh
	instance.material_override = _get_material(color)
	instance.position = base_position + Vector3.UP * _cone_mesh.height * 0.5
	parent.add_child(instance)


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
