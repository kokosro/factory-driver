class_name TyreMarks
extends MultiMeshInstance3D
## Tyre marks: the rubber a tyre leaves on the tarmac where it works beyond its
## grip - locked under the handbrake or a full pedal without ABS, spinning on a
## clutch let in for good without TCS, scrubbing sideways in a slide. Each
## physics tick the car's slip state is read, per axle (its two wheels share
## it), and a wheel that is past MARK_SLIP_RATIO or MARK_SLIP_ANGLE trails
## marks: quads lying on the ground from where its contact patch was to where
## it is now, one every MARK_SPACING of the way. The marks fade over
## MARK_LIFETIME and live in a pool of MAX_MARKS; when it is full the oldest
## is laid anew.
##
## A mark runs the way the contact patch travelled over the ground, not the way
## the wheel points (in a straight lockup or a launch the two are the same; in
## a slide a tyre going sideways still leaves its mark along its path), and is
## as long as the patch got over the ground: what a locked wheel leaves,
## whose own speed is 0, and what a spinning one leaves, whose own speed is
## three times the car's.
##
## Purely visual and read-only: nothing in here touches the car, and nothing in
## the car or the pad reads the marks. All of it is plain data worked out from
## the car's state on physics ticks - no clock but the ticks' own delta, no
## random numbers - so the same drive leaves the same marks, to the bit. A
## reset of the car (reset_to / reset_to_spawn, seen through its
## reset_counter) CLEARS the marks: the pad is as it was before the drive.

# --- Tuning ------------------------------------------------------------------

## Size of the pool [marks]. Spaced MARK_SPACING apart that is 512 m of one
## wheel's trail: a stop from 90 km/h on locked fronts is 114 marks, a handbrake
## slide from 60 km/h 110, the 360 spin test ~450, the scripted slalom, sawing
## at full lock with the fronts scrubbing half the way, ~650. A full pool costs
## ~0.2 ms a tick.
const MAX_MARKS := 1024

## A mark fades from MARK_COLOR's alpha to nothing over this long [s of physics time],
## then its place in the pool is free.
const MARK_LIFETIME := 30.0

## A wheel marks past this slip ratio, either way (no unit). Over what the car's
## own aids hold a tyre at (ArcadeCar.DRIVE_SLIP_RATIO 0.25 under TCS, 0.24
## measured flat out through the gears, 0.10 in a launch; ABS_SLIP_RATIO 0.15
## under ABS), far under what it gets to without them (2.8 spinning, -1
## locked).
const MARK_SLIP_RATIO := 0.35

## ... or past this slip angle, either way [rad], ~11.5 degrees: twice the
## tyres' peak (FRONT_ / REAR_PEAK_SLIP_ANGLE 0.11 / 0.10), where a tyre has
## stopped cornering and slides.
const MARK_SLIP_ANGLE := 0.2

## A trailing wheel lays a mark every this far over the ground [m]: a long slide
## is a mark per half metre and wheel, not one per tick.
const MARK_SPACING := 0.5

## What is left of a trail when the tyre grips again is laid too, if it is at
## least this long [m]; anything shorter is dropped (a mark needs a direction).
const MARK_MIN_LENGTH := 0.05

## Width of a mark [m]: the tread of the placeholder tyre (wheel.tscn's is 0.26
## wide, shoulders and all).
const TYRE_WIDTH := 0.22

## Height of the marks over the ground [m]: just over the thickest paint
## (TestPad.PAINT_LIFT 0.02), rubber goes down on top of the lines.
const MARK_LIFT := 0.022

## Dark rubber; the alpha is what a fresh mark has, the tarmac shows through.
const MARK_COLOR := Color(0.03, 0.03, 0.035, 0.75)

## An empty place in the pool: a quad of no size.
const NO_MARK := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

## The car whose tyres mark, and the pad they mark: the marks lie on the ground
## the pad shows (its elevation_height, what everything on the pad lies on; the
## micro-bumps the wheels ride are not in the ground mesh). Without either
## nothing is laid.
@export var car: ArcadeCar
@export var pad: TestPad

## The pool, MAX_MARKS places: where each mark lies (a unit quad's transform,
## world space; NO_MARK = empty) and how old it is [s]. The live marks are
## mark_count places in a ring, oldest first, ending before _next_mark: marks
## are laid in order and all live as long, so they go in the order they came.
var mark_transforms: Array[Transform3D] = []
var mark_ages := PackedFloat64Array()
var mark_count := 0

var _next_mark := 0

## Per wheel (the order of ArcadeCar.WHEEL_CONTACT_POINTS): whether it was
## marking on the last tick, and where its trail has been laid up to.
var _trailing: Array[bool] = [false, false, false, false]
var _trail_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]

## The car's reset_counter as last seen.
var _resets_seen := 0


func _ready() -> void:
	# The marks lie where they were laid: nothing to interpolate, and a place in
	# the pool laid anew must not sweep across the pad from where it was.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = _material()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_MARKS
	mark_transforms.resize(MAX_MARKS)
	mark_ages.resize(MAX_MARKS)
	if car:
		_resets_seen = car.reset_counter
	clear()


func _physics_process(delta: float) -> void:
	if car and car.reset_counter != _resets_seen:
		_resets_seen = car.reset_counter
		clear()
	_age_marks(delta)
	if car and pad:
		_trail_wheels()


## Takes every mark off the pad and ends every trail.
func clear() -> void:
	for slot in MAX_MARKS:
		_free_slot(slot)
	mark_count = 0
	_next_mark = 0
	for i in _trailing.size():
		_trailing[i] = false


## Place in the pool of the oldest live mark (meaningless while mark_count is 0).
func oldest_mark() -> int:
	return posmod(_next_mark - mark_count, MAX_MARKS)


## Opacity of the mark in `slot` right now, MARK_COLOR's alpha fresh .. 0 faded
## out (and 0 for an empty place).
func mark_alpha(slot: int) -> float:
	if mark_transforms[slot] == NO_MARK:
		return 0.0
	return MARK_COLOR.a * clampf(1.0 - mark_ages[slot] / MARK_LIFETIME, 0.0, 1.0)


## Lays one mark on the ground from `from` to `to` (world space, on the ground)
## in the next place of the pool - the oldest mark's, once the pool is full.
## Nothing is laid for less than MARK_MIN_LENGTH over the ground or anything
## not finite.
func lay_mark(from: Vector3, to: Vector3) -> void:
	var along := to - from
	var length := along.length()
	# Across the mark, level; as long as the mark is over the ground.
	var across := Vector3.UP.cross(along)
	if not is_finite(length) or across.length() < MARK_MIN_LENGTH:
		return
	# The unit quad lies in its own XZ plane: X across the mark, Z along it, Y
	# off the ground (tilted to the slope between the mark's two ends).
	along /= length
	across = across.normalized()
	var lie := Basis(across * TYRE_WIDTH, along.cross(across), along * length)
	var slot := _next_mark
	mark_transforms[slot] = Transform3D(lie, (from + to) * 0.5 + Vector3.UP * MARK_LIFT)
	mark_ages[slot] = 0.0
	multimesh.set_instance_transform(slot, mark_transforms[slot])
	multimesh.set_instance_color(slot, MARK_COLOR)
	_next_mark = (slot + 1) % MAX_MARKS
	mark_count = mini(mark_count + 1, MAX_MARKS)


## True while a tyre of an axle with this slip state works beyond its grip.
static func tyre_marks(slip_angle: float, slip_ratio: float) -> bool:
	return absf(slip_ratio) > MARK_SLIP_RATIO or absf(slip_angle) > MARK_SLIP_ANGLE


## Every live mark is `delta` older and that much paler; the ones past
## MARK_LIFETIME go, oldest first.
func _age_marks(delta: float) -> void:
	var slot := oldest_mark()
	for i in mark_count:
		mark_ages[slot] += delta
		multimesh.set_instance_color(slot, Color(MARK_COLOR, mark_alpha(slot)))
		slot = (slot + 1) % MAX_MARKS
	while mark_count > 0 and mark_ages[oldest_mark()] >= MARK_LIFETIME:
		_free_slot(oldest_mark())
		mark_count -= 1


## The four wheels' trails, from the car as its tick left it.
func _trail_wheels() -> void:
	var front := tyre_marks(car.front_slip_angle, car.front_slip_ratio)
	var rear := tyre_marks(car.rear_slip_angle, car.rear_slip_ratio)
	for i in ArcadeCar.WHEEL_CONTACT_POINTS.size():
		# Where the suspension looks the road up, on the ground the pad shows.
		var contact := car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]
		contact.y = pad.elevation_height(contact.x, contact.z)
		if not (front if i < 2 else rear):
			if _trailing[i]:
				lay_mark(_trail_from[i], contact)
				_trailing[i] = false
		elif not _trailing[i]:
			_trailing[i] = true
			_trail_from[i] = contact
		elif _trail_from[i].distance_to(contact) >= MARK_SPACING:
			lay_mark(_trail_from[i], contact)
			_trail_from[i] = contact


func _free_slot(slot: int) -> void:
	mark_transforms[slot] = NO_MARK
	mark_ages[slot] = 0.0
	multimesh.set_instance_transform(slot, NO_MARK)
	multimesh.set_instance_color(slot, Color(MARK_COLOR, 0.0))


## Lit like the tarmac it lies on, the colour and the fade per mark: the
## multimesh's instance colours come in as vertex colours.
func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.9
	return material
