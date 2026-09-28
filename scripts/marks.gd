class_name MarksLayer
extends MultiMeshInstance3D
## SKIDMARKS-1 (2026-09-28): the rubber a tyre leaves on the TARMAC wherever
## the car is - the Ring, not only the pad. Driver issue-0003, verbatim:
## "there is no tire markings left on tarmac, this is not only for this
## zone, it's everywhere on the green hell". One of these per car in every
## scene, made and placed by the MarksWatch autoload (scripts/marks_watch.gd;
## the TelemetryWatch precedent), named "Marks" under the car's scene root.
##
## WHAT MARKS: every physics tick the car's public slip numbers are read,
## per axle (the car exposes them per axle; an axle's two wheels share
## them), and a wheel whose axle is past one of three thresholds trails
## rubber - a STREAK of quads lying on the road from where the wheel's
## contact patch was to where it is now, one quad every SPACING_M of the
## way (a long slide is a quad per half metre and wheel, not one a tick;
## 4 096 quads are 2 km of streak). The three triggers, each an intensity
## 0..1 that ramps from its threshold to its "solid" point, the quad's
## alpha the largest of the three over the ticks it covers:
##   - LATERAL: |slip angle| past LATERAL_ONSET_PEAKS (1.5) times the
##     axle's own peak slip angle (ArcadeCar.FRONT_ / REAR_PEAK_SLIP_ANGLE,
##     0.11 / 0.10 rad) - 0 there, solid at LATERAL_SOLID_PEAKS (3.0) times
##     the peak. Under 1.5 peaks a tyre still corners; normal cornering and
##     straight driving leave nothing.
##   - WHEELSPIN: a DRIVEN axle's slip ratio past SPIN_ONSET_RATIO -
##     ArcadeCar.DRIVE_SLIP_RATIO (0.25, what the clutch limit holds a
##     launch at and TCS holds the rears at) times SPIN_ONSET_FACTOR (1.15)
##     = 0.2875 - solid at SPIN_SOLID_RATIO (1.0; a clutch dumped without
##     TCS spins the rears to 2.8). An ordinary launch leaves nothing;
##     genuine spinning does.
##   - LOCK: |slip ratio| past LOCK_ONSET_RATIO (0.5) on either axle
##     (ABS holds a wheel at 0.15; a locked wheel reads -1) - solid at
##     LOCK_SOLID_RATIO (1.0): the streak runs the way the wheel's contact
##     patch travels over the ground.
## The wheel's SURFACE gates all three: where the scene has a Surfaces node
## (the Ring) the wheel's contact point (car.global_transform *
## ArcadeCar.WHEEL_CONTACT_POINTS[i], read live: a car's config re-derives
## the points) is classified (Surfaces.classify, a pure read) and only
## "road" marks - grass, gravel, a field or the forest floor never; where
## there is none (the pad: all tarmac) every wheel is on road.
##
## WHERE A QUAD LIES: on the ground the profile shows - car.road_profile's
## elevation_height at the contact point (on the Ring the RingProfile's
## sample_height, bit-exact on a road; on the pad the elevation without the
## micro-bumps the wheels ride, which the ground mesh does not show) -
## lifted LIFT_M (0.025 m) to clear z-fighting with the road (and ROAD-3's
## skirt), tilted to the slope between the streak's two ends and to the
## crossfall across it (two more height reads per quad), TYRE_WIDTH_FRONT /
## _REAR wide (the rears wider), as long as the patch's way over the
## ground. Dark rubber (RUBBER), the alpha per quad (MultiMesh instance
## colours, vertex colour as albedo, alpha blended): ALPHA_SOLID (0.7) at
## an intensity of 1, in a line down to 0 at the threshold.
##
## HOW LONG: a quad lives LIFETIME_S (180 s of physics time) fading in a
## line from its own alpha to nothing, then its place is free; the pool
## holds MAX_QUADS (4 096) and, full, lays over the oldest. The colours are
## refreshed in stride (every quad once per COLOUR_REFRESH_TICKS, a 32nd of
## the pool a tick): a fade of 180 s does not show a half-second's lag, and
## a full pool costs a hundred-odd colour writes a tick, not four thousand.
## A reset of the car (reset_to / reset_to_spawn: reset_counter) ENDS every
## streak without laying it (no streak from the old place to the new) and
## keeps the quads: the rubber is on the road, R does not sweep it. A step
## over MAX_STEP_M in one tick drops the streak too.
##
## PURELY VISUAL, READ-ONLY, DETERMINISTIC: nothing here writes the car,
## the Surfaces node or the profile; no collision shape; no random, no
## wall clock - the ticks' own delta is the only time. Every quad's origin
## is snapped to POSITION_SNAP (0.001 m) and its alpha to ALPHA_SNAP
## (0.001) as it is laid, so the same drive lays the same records to the
## bit (tests/marks_test.gd holds two fresh scenes to it).
##
## Ticks at process_physics_priority -1: after the bubble's -2, in the
## Surfaces node's own group (which stands before this node in tree order)
## and before the car's 0, so a tick reads the slip numbers and the
## transform the car's last tick left together, one state.

# --- Tuning ------------------------------------------------------------------

## Size of the pool [quads]. Spaced SPACING_M apart that is ~2 km of one
## wheel's streak; four wheels sliding at 20 m/s lay 160 a second.
const MAX_QUADS := 4096

## A quad fades from its own alpha to nothing over this long [s of physics
## time], then its place is free. Minutes: the rubber stays for the next lap.
const LIFETIME_S := 180.0

## LATERAL: onset at this many times the axle's peak slip angle, solid at
## this many (no unit). Front peak 0.11 rad -> 0.165 .. 0.33; rear 0.10 ->
## 0.15 .. 0.30.
const LATERAL_ONSET_PEAKS := 1.5
const LATERAL_SOLID_PEAKS := 3.0

## WHEELSPIN: onset at ArcadeCar.DRIVE_SLIP_RATIO times this (0.25 x 1.15 =
## 0.2875; the clutch limit and TCS hold a launch under 0.25), solid at
## SPIN_SOLID_RATIO.
const SPIN_ONSET_FACTOR := 1.15
const SPIN_SOLID_RATIO := 1.0

## LOCK: onset at this slip ratio either way (ABS holds 0.15), solid at
## LOCK_SOLID_RATIO (a locked wheel reads -1).
const LOCK_ONSET_RATIO := 0.5
const LOCK_SOLID_RATIO := 1.0

## A streaking wheel lays a quad every this far over the ground [m].
const SPACING_M := 0.5

## The rest of a streak is laid when the tyre grips again if it is at least
## this long [m]; shorter is dropped (a quad needs a direction).
const MIN_LENGTH_M := 0.05

## A contact point that moved more than this in one tick [m] was put there,
## not driven (a reset, a teleport: 2 m a tick is 430 km/h): the streak ends.
const MAX_STEP_M := 2.0

## Width of a quad [m]: the tread. The Boxster's 205 fronts and 255 rears.
const TYRE_WIDTH_FRONT := 0.20
const TYRE_WIDTH_REAR := 0.24

## Height of a quad over the ground [m]: clear of z-fighting with the road
## mesh and the pad's paint (TestPad.PAINT_LIFT 0.02).
const LIFT_M := 0.025

## Dark rubber; the alpha of a quad of intensity 1 (the tarmac shows through).
const RUBBER := Color(0.03, 0.03, 0.035, 1.0)
const ALPHA_SOLID := 0.7

## The record's snaps: a quad's origin [m], its alpha, and its age [s] as
## records() reports it.
const POSITION_SNAP := 0.001
const ALPHA_SNAP := 0.001
const AGE_SNAP := 0.00001

## Every quad's colour is written once per this many ticks (its slot's turn).
const COLOUR_REFRESH_TICKS := 32

## An empty place in the pool: a quad of no size.
const NO_QUAD := Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

## The node's name under the scene root (MarksWatcher gives it).
const NODE_NAME := "Marks"

# --- State -------------------------------------------------------------------

## The car whose tyres mark (attach()).
var car: ArcadeCar = null

## The scene's Surfaces node, null where it has none (the pad): the gate.
var surfaces: Surfaces = null

## The pool, MAX_QUADS places: where each quad lies (a unit quad's transform,
## world space; NO_QUAD = empty), its snapped origin in full precision (x, y,
## z per slot: a Transform3D holds 32-bit floats, the record is the double),
## how old it is [s], the alpha it was laid with, and the wheel that laid it
## (0 FL, 1 FR, 2 RL, 3 RR). The live quads are quad_count places in a
## ring, oldest first, ending before _next.
var quad_transforms: Array[Transform3D] = []
var quad_origins := PackedFloat64Array()
var quad_ages := PackedFloat64Array()
var quad_alphas := PackedFloat64Array()
var quad_wheels := PackedInt32Array()
var quad_count := 0

## Quads laid since the node was made (evictions included) and ticks run.
var laid_total := 0
var ticks := 0

var _next := 0
## The highest slot ever used + 1: what the multimesh draws.
var _high_water := 0

## Per wheel (the order of ArcadeCar.WHEEL_CONTACT_POINTS): whether it was
## streaking on the last tick, where its streak has been laid up to, and the
## strongest intensity of the ticks since: what the next quad is laid with.
var _streaking: Array[bool] = [false, false, false, false]
var _streak_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var _streak_intensity: Array[float] = [0.0, 0.0, 0.0, 0.0]

## The car's reset_counter as last seen.
var _resets_seen := 0


func _ready() -> void:
	process_physics_priority = -1
	# The quads lie where they were laid: nothing to interpolate, and a place
	# laid anew must not sweep across the road from where it was.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.material = _material()
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = MAX_QUADS
	multimesh.visible_instance_count = 0
	quad_transforms.resize(MAX_QUADS)
	quad_origins.resize(MAX_QUADS * 3)
	quad_ages.resize(MAX_QUADS)
	quad_alphas.resize(MAX_QUADS)
	quad_wheels.resize(MAX_QUADS)
	for slot in MAX_QUADS:
		quad_transforms[slot] = NO_QUAD
	if car != null:
		_resets_seen = car.reset_counter


## Takes the car to watch and the scene's Surfaces node (null for none).
func attach(target_car: ArcadeCar, scene_surfaces: Surfaces) -> void:
	car = target_car
	surfaces = scene_surfaces
	if car != null:
		_resets_seen = car.reset_counter


func _physics_process(delta: float) -> void:
	ticks += 1
	_age(delta)
	if car == null or not is_instance_valid(car) or not car.is_inside_tree():
		return
	if car.reset_counter != _resets_seen:
		_resets_seen = car.reset_counter
		end_streaks()
	_streak_wheels()


# =============================================================================
#  The triggers (pure functions of the slip numbers: the tests pin them)
# =============================================================================

## The lateral intensity of an axle with peak slip angle `peak` at `slip_angle`
## [rad]: 0 up to LATERAL_ONSET_PEAKS x peak, 1 from LATERAL_SOLID_PEAKS x
## peak, a line between.
static func lateral_intensity(slip_angle: float, peak: float) -> float:
	return clampf(inverse_lerp(LATERAL_ONSET_PEAKS * peak, LATERAL_SOLID_PEAKS * peak, absf(slip_angle)), 0.0, 1.0)


## The wheelspin intensity of a DRIVEN axle at `slip_ratio` (positive = the
## wheels outrun the road): 0 up to spin_onset_ratio(), 1 from
## SPIN_SOLID_RATIO.
static func spin_intensity(slip_ratio: float) -> float:
	return clampf(inverse_lerp(spin_onset_ratio(), SPIN_SOLID_RATIO, slip_ratio), 0.0, 1.0)


## The lock intensity of an axle at `slip_ratio`, either way: 0 up to
## LOCK_ONSET_RATIO, 1 from LOCK_SOLID_RATIO.
static func lock_intensity(slip_ratio: float) -> float:
	return clampf(inverse_lerp(LOCK_ONSET_RATIO, LOCK_SOLID_RATIO, absf(slip_ratio)), 0.0, 1.0)


## Where wheelspin begins: the car's DRIVE_SLIP_RATIO (read live: a config
## may set it) times SPIN_ONSET_FACTOR.
static func spin_onset_ratio() -> float:
	return ArcadeCar.DRIVE_SLIP_RATIO * SPIN_ONSET_FACTOR


## The intensity an axle marks with, the largest of its three triggers:
## `driven` says whether wheelspin counts for it.
static func axle_intensity(slip_angle: float, slip_ratio: float, peak: float, driven: bool) -> float:
	var intensity := maxf(lateral_intensity(slip_angle, peak), lock_intensity(slip_ratio))
	if driven:
		intensity = maxf(intensity, spin_intensity(slip_ratio))
	return intensity


## The alpha a quad of `intensity` is laid with, snapped (alpha_of(1.0) is
## the solid alpha as laid: ALPHA_SOLID through the snap).
static func alpha_of(intensity: float) -> float:
	return snappedf(ALPHA_SOLID * clampf(intensity, 0.0, 1.0), ALPHA_SNAP)


## Whether the wheels of axle `front` are driven under `layout`.
static func axle_driven(front: bool, layout: ArcadeCar.DrivenWheels) -> bool:
	if layout == ArcadeCar.DrivenWheels.AWD:
		return true
	return front == (layout == ArcadeCar.DrivenWheels.FWD)


# =============================================================================
#  The pool
# =============================================================================

## Place in the pool of the oldest live quad (meaningless while quad_count is 0).
func oldest() -> int:
	return posmod(_next - quad_count, MAX_QUADS)


## Opacity of the quad in `slot` right now: its own alpha faded by its age
## (0 for an empty place).
func quad_alpha(slot: int) -> float:
	if quad_transforms[slot] == NO_QUAD:
		return 0.0
	return quad_alphas[slot] * clampf(1.0 - quad_ages[slot] / LIFETIME_S, 0.0, 1.0)


## The surface under (x, z) as the gate sees it: the Surfaces node's read
## where the scene has one, road everywhere on a scene without.
func surface_at(x: float, z: float) -> StringName:
	if surfaces == null or not is_instance_valid(surfaces):
		return TerrainBuilder.SURFACE_ROAD
	return surfaces.classify(x, z)


## Height of the ground the profile shows at (x, z) [m]: 0 for a car without one.
func ground_height(x: float, z: float) -> float:
	if car == null or car.road_profile == null:
		return 0.0
	return car.road_profile.elevation_height(x, z)


## Lays one quad on the ground from `from` to `to` (world space, on the
## ground already) for wheel `wheel` (0..3) at `intensity` (0..1) in the
## next place of the pool - the oldest quad's, once the pool is full.
## Nothing is laid for less than MIN_LENGTH_M over the ground, for anything
## not finite, or for an intensity that rounds to no alpha. Returns whether
## a quad was laid.
func lay_quad(from: Vector3, to: Vector3, wheel: int, intensity: float) -> bool:
	var along := to - from
	var length := along.length()
	var across := Vector3.UP.cross(along)
	if not is_finite(length) or not is_finite(intensity) or across.length() < MIN_LENGTH_M:
		return false
	var alpha := alpha_of(intensity)
	if alpha <= 0.0:
		return false
	along /= length
	across = across.normalized()
	# The crossfall: the ground at the two edges of the quad's middle.
	var width := TYRE_WIDTH_FRONT if wheel < 2 else TYRE_WIDTH_REAR
	var middle := (from + to) * 0.5
	# ROAD-5: the lip makes the shoulder's height vary ~0.055 m within the
	# band, so the middle's own ground is what the quad lies on - the ends'
	# mean could sit up to half the lip off the field at the origin (measured
	# 0.021 m on the marks test's straight, tolerance 0.005 m).
	middle.y = ground_height(middle.x, middle.z)
	var left := middle - across * (width * 0.5)
	var right := middle + across * (width * 0.5)
	var tilt := ground_height(right.x, right.z) - ground_height(left.x, left.z)
	if is_finite(tilt):
		across = Vector3(across.x * width, tilt, across.z * width)
	else:
		across *= width
	# The unit quad lies in its own XZ plane: X across the streak, Z along
	# it, Y off the ground.
	var normal := along.cross(across.normalized())
	if normal.length() < 0.5:
		return false
	var lie := Basis(across, normal.normalized(), along * length)
	var x := snappedf(middle.x, POSITION_SNAP)
	var y := snappedf(middle.y + LIFT_M, POSITION_SNAP)
	var z := snappedf(middle.z, POSITION_SNAP)
	var slot := _next
	quad_transforms[slot] = Transform3D(lie, Vector3(x, y, z))
	quad_origins[slot * 3] = x
	quad_origins[slot * 3 + 1] = y
	quad_origins[slot * 3 + 2] = z
	quad_ages[slot] = 0.0
	quad_alphas[slot] = alpha
	quad_wheels[slot] = wheel
	multimesh.set_instance_transform(slot, quad_transforms[slot])
	multimesh.set_instance_color(slot, Color(RUBBER, alpha))
	_next = (slot + 1) % MAX_QUADS
	quad_count = mini(quad_count + 1, MAX_QUADS)
	laid_total += 1
	if slot + 1 > _high_water:
		_high_water = slot + 1
		multimesh.visible_instance_count = _high_water
	return true


## Takes every quad off the road and ends every streak.
func clear() -> void:
	for slot in _high_water:
		_free_slot(slot)
	quad_count = 0
	_next = 0
	_high_water = 0
	multimesh.visible_instance_count = 0
	end_streaks()


## Ends every wheel's streak without laying what is left of it.
func end_streaks() -> void:
	for i in _streaking.size():
		_streaking[i] = false
		_streak_intensity[i] = 0.0


## The live quads oldest first, each a record of the snapped numbers: pos
## [x, y, z], alpha (as laid), age [s], wheel, yaw [rad, snapped], length
## [m, snapped]. What a test compares between two drives.
func records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var slot := oldest()
	for i in quad_count:
		var lie := quad_transforms[slot]
		out.append({
			"pos": [quad_origins[slot * 3], quad_origins[slot * 3 + 1], quad_origins[slot * 3 + 2]],
			"alpha": quad_alphas[slot],
			"age": snappedf(quad_ages[slot], AGE_SNAP),
			"wheel": quad_wheels[slot],
			"yaw": snappedf(atan2(lie.basis.z.x, lie.basis.z.z), ALPHA_SNAP),
			"length": snappedf(lie.basis.z.length(), POSITION_SNAP),
		})
		slot = (slot + 1) % MAX_QUADS
	return out


## One line: the pool and the streaks.
func describe() -> String:
	var per_wheel := [0, 0, 0, 0]
	var slot := oldest()
	for i in quad_count:
		per_wheel[quad_wheels[slot]] += 1
		slot = (slot + 1) % MAX_QUADS
	var profile := "none"
	if car != null and car.road_profile != null and car.road_profile.get_script() != null:
		profile = (car.road_profile.get_script() as Script).get_global_name()
	return "marks: %d of %d quads live (FL %d, FR %d, RL %d, RR %d), %d laid in all, tick %d, %s, profile %s, streaking %s" % [quad_count, MAX_QUADS, per_wheel[0], per_wheel[1], per_wheel[2], per_wheel[3], laid_total, ticks, "the scene's Surfaces node gates the road" if surfaces != null else "no Surfaces node: all road", profile, _streaking]


# =============================================================================
#  The ticks
# =============================================================================

## Every live quad is `delta` older; the ones past LIFETIME_S go, oldest
## first; the colours of this tick's stride of slots are written anew.
func _age(delta: float) -> void:
	var slot := oldest()
	for i in quad_count:
		quad_ages[slot] += delta
		slot = (slot + 1) % MAX_QUADS
	while quad_count > 0 and quad_ages[oldest()] >= LIFETIME_S:
		_free_slot(oldest())
		quad_count -= 1
	var turn := ticks % COLOUR_REFRESH_TICKS
	slot = turn
	while slot < _high_water:
		if quad_transforms[slot] != NO_QUAD:
			multimesh.set_instance_color(slot, Color(RUBBER, quad_alpha(slot)))
		slot += COLOUR_REFRESH_TICKS


## The four wheels' streaks, from the car as its last tick left it. A quad is
## as strong as the strongest tick of the way it covers: the last of a
## streak, laid on the tick the tyre grips again, is the slide's and not
## that tick's.
func _streak_wheels() -> void:
	var layout: ArcadeCar.DrivenWheels = car.driven_wheels
	var front := axle_intensity(car.front_slip_angle, car.front_slip_ratio, ArcadeCar.FRONT_PEAK_SLIP_ANGLE, axle_driven(true, layout))
	var rear := axle_intensity(car.rear_slip_angle, car.rear_slip_ratio, ArcadeCar.REAR_PEAK_SLIP_ANGLE, axle_driven(false, layout))
	var points: Array[Vector3] = ArcadeCar.WHEEL_CONTACT_POINTS
	var transform := car.global_transform
	for i in mini(points.size(), _streaking.size()):
		var contact := transform * points[i]
		var intensity := front if i < 2 else rear
		var marking := intensity > 0.0 and surface_at(contact.x, contact.z) == TerrainBuilder.SURFACE_ROAD
		if marking:
			contact.y = ground_height(contact.x, contact.z)
		if not marking:
			if _streaking[i]:
				contact.y = ground_height(contact.x, contact.z)
				if _streak_from[i].distance_to(contact) <= MAX_STEP_M + SPACING_M:
					lay_quad(_streak_from[i], contact, i, _streak_intensity[i])
				_streaking[i] = false
			continue
		if not _streaking[i]:
			_streaking[i] = true
			_streak_from[i] = contact
			_streak_intensity[i] = intensity
			continue
		var way := _streak_from[i].distance_to(contact)
		if way > MAX_STEP_M + SPACING_M:
			# Put there, not driven: the streak starts anew here.
			_streak_from[i] = contact
			_streak_intensity[i] = intensity
			continue
		_streak_intensity[i] = maxf(_streak_intensity[i], intensity)
		if way >= SPACING_M:
			lay_quad(_streak_from[i], contact, i, _streak_intensity[i])
			_streak_from[i] = contact
			_streak_intensity[i] = intensity


func _free_slot(slot: int) -> void:
	quad_transforms[slot] = NO_QUAD
	quad_origins[slot * 3] = 0.0
	quad_origins[slot * 3 + 1] = 0.0
	quad_origins[slot * 3 + 2] = 0.0
	quad_ages[slot] = 0.0
	quad_alphas[slot] = 0.0
	quad_wheels[slot] = 0
	multimesh.set_instance_transform(slot, NO_QUAD)
	multimesh.set_instance_color(slot, Color(RUBBER, 0.0))


## Lit like the tarmac it lies on, the colour and the fade per quad: the
## multimesh's instance colours come in as vertex colours.
func _material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 0.9
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return material
