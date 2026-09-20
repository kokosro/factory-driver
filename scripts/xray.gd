extends Node3D
## X-ray view of the car. The xray_view action fades the body panels and shows
## what the physics is modelling underneath: a ladder chassis, the engine ahead
## of the rear axle (mid-engined), the gearbox on the rear axle line driving the
## rear wheels, the axles and a brake disc at every wheel. All primitives, built
## here in code. Purely visual: nothing in here touches the car's physics.
##
## Lives on a hidden Node3D under the car, next to its Body node.

# --- Tuning ------------------------------------------------------------------
# Positions and sizes are in the car's own space: origin on the ground under
# the middle of the car, nose towards -Z, +X to the driver's right, +Y up.

## Opacity of the body panels while the X-ray is on (0 = gone, 1 = solid).
const BODY_ALPHA := 0.22

## Chassis: the two rails run the length of the car, this far either side of
## the centre line [m], at this height [m] ...
const RAIL_OFFSET_X := 0.45
const RAIL_HEIGHT := 0.42

## ... each this big: width, height, length [m] ...
const RAIL_SIZE := Vector3(0.08, 0.1, 3.8)

## ... tied together by cross-members at these stations along the car [m]:
## nose, behind the front axle, ahead of the engine, tail.
const CROSS_MEMBER_Z: Array[float] = [-1.85, -0.75, 0.1, 1.85]

## Cross-member section: width and height [m]. They span rail to rail.
const CROSS_MEMBER_SECTION := Vector2(0.08, 0.08)

## Engine block, between the cabin and the rear axle: centre and size [m].
const ENGINE_CENTRE := Vector3(0.0, 0.6, 0.55)
const ENGINE_SIZE := Vector3(0.6, 0.4, 0.6)

## Gearbox and differential in one casing, on the rear axle line: centre and
## size [m].
const GEARBOX_CENTRE := Vector3(0.0, 0.42, 1.3)
const GEARBOX_SIZE := Vector3(0.36, 0.3, 0.42)

## Driveshaft from the back of the engine into the gearbox: height of its axis
## [m], the two ends along the car [m] and its radius [m].
const DRIVESHAFT_HEIGHT := 0.48
const DRIVESHAFT_FROM_Z := 0.85
const DRIVESHAFT_TO_Z := 1.09
const DRIVESHAFT_RADIUS := 0.045

## Axles, hub to hub at wheel-centre height [m]. The rear one carries the drive
## out of the gearbox; the front one is an undriven beam, drawn thinner.
const AXLE_HEIGHT := 0.34
const AXLE_Z := 1.3
const AXLE_LENGTH := 1.4
const REAR_AXLE_RADIUS := 0.035
const FRONT_AXLE_RADIUS := 0.022

## Brake discs, just inboard of each wheel: distance from the centre line [m],
## radius and thickness [m].
const DISC_OFFSET_X := 0.69
const DISC_RADIUS := 0.27
const DISC_THICKNESS := 0.03

const CHASSIS_COLOR := Color(0.62, 0.68, 0.76, 1)
const ENGINE_COLOR := Color(1.0, 0.62, 0.1, 1)
const GEARBOX_COLOR := Color(0.95, 0.85, 0.25, 1)
const DRIVELINE_COLOR := Color(0.3, 0.85, 0.95, 1)
const DISC_COLOR := Color(0.9, 0.92, 0.95, 1)

## Body materials faded while the X-ray is on, with what they were before.
var _body_materials: Array[BaseMaterial3D] = []
var _saved_transparency: Array[int] = []
var _saved_albedo: Array[Color] = []

var _on := false


func _ready() -> void:
	visible = false
	_collect_body_materials()
	_build()


func _physics_process(_delta: float) -> void:
	# Polled here, like the car's own keys.
	if Input.is_action_just_pressed("xray_view"):
		set_on(not _on)


func _exit_tree() -> void:
	# The body materials are shared resources: never leave them faded.
	set_on(false)


## True while the X-ray view is showing.
func is_on() -> bool:
	return _on


## Shows or hides the X-ray. Safe to call with the state it already has.
func set_on(on: bool) -> void:
	if on == _on:
		return
	_on = on
	visible = on
	if on:
		_saved_transparency.clear()
		_saved_albedo.clear()
		for material in _body_materials:
			_saved_transparency.append(material.transparency)
			_saved_albedo.append(material.albedo_color)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = BODY_ALPHA
	else:
		for i in _body_materials.size():
			_body_materials[i].transparency = _saved_transparency[i] as BaseMaterial3D.Transparency
			_body_materials[i].albedo_color = _saved_albedo[i]


## Every material on the car's Body meshes, each once: the paint is shared by
## three panels.
func _collect_body_materials() -> void:
	var body := get_parent().get_node_or_null("Body")
	if not body:
		return
	for child in body.get_children():
		var panel := child as MeshInstance3D
		if not panel or not panel.mesh:
			continue
		var material := panel.mesh.surface_get_material(0) as BaseMaterial3D
		if material and not _body_materials.has(material):
			_body_materials.append(material)


func _build() -> void:
	var chassis_material := _material(CHASSIS_COLOR)
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(side * RAIL_OFFSET_X, RAIL_HEIGHT, 0.0), RAIL_SIZE, chassis_material)
	var cross_member_size := Vector3(RAIL_OFFSET_X * 2.0 - RAIL_SIZE.x, CROSS_MEMBER_SECTION.y, CROSS_MEMBER_SECTION.x)
	for z in CROSS_MEMBER_Z:
		_add_box(Vector3(0.0, RAIL_HEIGHT, z), cross_member_size, chassis_material)

	_add_box(ENGINE_CENTRE, ENGINE_SIZE, _material(ENGINE_COLOR))
	_add_box(GEARBOX_CENTRE, GEARBOX_SIZE, _material(GEARBOX_COLOR))

	var driveline_material := _material(DRIVELINE_COLOR)
	var driveshaft_centre := Vector3(0.0, DRIVESHAFT_HEIGHT, (DRIVESHAFT_FROM_Z + DRIVESHAFT_TO_Z) * 0.5)
	_add_cylinder(driveshaft_centre, DRIVESHAFT_RADIUS, DRIVESHAFT_TO_Z - DRIVESHAFT_FROM_Z, Vector3.BACK, driveline_material)
	_add_cylinder(Vector3(0.0, AXLE_HEIGHT, AXLE_Z), REAR_AXLE_RADIUS, AXLE_LENGTH, Vector3.RIGHT, driveline_material)
	_add_cylinder(Vector3(0.0, AXLE_HEIGHT, -AXLE_Z), FRONT_AXLE_RADIUS, AXLE_LENGTH, Vector3.RIGHT, chassis_material)

	var disc_material := _material(DISC_COLOR)
	for side: float in [-1.0, 1.0]:
		for end: float in [-1.0, 1.0]:
			_add_cylinder(Vector3(side * DISC_OFFSET_X, AXLE_HEIGHT, end * AXLE_Z), DISC_RADIUS, DISC_THICKNESS, Vector3.RIGHT, disc_material)


## Flat, unshaded colour: the parts sit in the body's shadow and have to read
## through the faded panels like a diagram.
func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _add_box(centre: Vector3, size: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	_add_part(mesh, Transform3D(Basis.IDENTITY, centre))


## A cylinder of `length` centred on `centre`, its axis along `axis` (a unit
## vector along X or Z).
func _add_cylinder(centre: Vector3, radius: float, length: float, axis: Vector3, material: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 20
	mesh.rings = 1
	mesh.material = material
	# The mesh's own axis is +Y: turn that onto `axis`.
	_add_part(mesh, Transform3D(Basis(Quaternion(Vector3.UP, axis)), centre))


func _add_part(mesh: Mesh, xform: Transform3D) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.transform = xform
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(part)
