class_name Surfaces
extends Node3D
## The car's surface model (OFFROAD-1; plan.org ECD301C4, SURFACES & GRIP
## DEPTH: "grip varies by surface type and condition, suspension/tire
## feel"; the driver's finding: off the road the car felt "like going
## through water" - no surface grip, no micro-profile, the raw 10 m
## lattice with road grip everywhere). Reads the region's surfaces table
## (PATH: named surfaces with a grip multiplier, a rolling drag [m/s^2]
## and a bump amplitude [m]; validate() holds the schema and the bounds,
## the road exactly {1, 0, 0}), classifies each wheel's contact point
## every physics tick and writes the car's three surface inputs
## (scripts/car.gd front_surface_grip / rear_surface_grip /
## surface_rolling_decel: the Conductor's narrow grant, decisions.org
## 5B7CD993 - per-axle honesty, the parameterisation through this table,
## the cert byte-lock proving on-road bit-identity, all three 1.0 / 0.0
## on the road). The car consumes them where its axle grip and its
## rolling drag are formed (car.gd's three lines): the brakes need no
## hook of their own - brake force is delivered through the grip budget.
##
## THE CLASSIFICATION, per wheel (TerrainBuilder.surface_at): the road on
## its paved width; gravel within the table's rules.shoulder_m beyond the
## paved edge; else the terrain's ground - forest floor under the V7
## canopy, field stubble on a T7 field, grass everywhere else and
## outside the coverage. An axle's grip factor is the mean of its two
## wheels' (a two-wheel axle model lumps its wheels; the mean is the
## honest lump), the rolling decel the mean of all four wheels'.
##
## THE PROFILE SWAP: at its FIRST physics tick (process_physics_priority
## -1: after the bubble's -2, before the car's 0; every _ready - Road,
## Terrain, Forest - has consumed the ORIGINAL profile by then, so the
## meshes are the smooth field's) this node wraps road.profile in a
## RingProfile (scripts/ring_profile.gd: the bumps off-road, the
## continuation outside the coverage, the inner bit-exact on a road) and
## hands the SAME object to road.profile and car.road_profile - the ring
## drive test's pin (`road.profile is WorldRoadProfile and
## car.road_profile == road.profile`) holds: a subclass passes `is`, one
## object passes `==`. The car's road_profile setter settles the
## suspension on assignment; the car has not ticked yet, the heights on
## the pit lane are the inner's bits, so the settle is the one its
## _ready did. RoadBuilder's floor follower (priority -1 too, before
## this node in tree order) reads the wrapper from the next tick.
##
## Deterministic: the classification is a pure read of the built terrain
## and the profile; nothing here draws a random or reads a clock.

## Where the table is and its shape.
const PATH := "res://data/regions/eifel_ring/surfaces.json"
const TABLE_KEYS := ["region", "doc", "rules", "surfaces"]
const RULE_KEYS := ["shoulder_m", "note"]
const SURFACE_KEYS := ["grip", "rolling_drag", "bump", "note"]
const SURFACE_NAMES := ["road", "gravel", "grass", "field_stubble", "forest_floor"]
const REGION := "eifel_ring"
## The bounds: grip a multiplier in [GRIP_MIN, GRIP_MAX], drag and bump
## never negative.
const GRIP_MIN := 0.2
const GRIP_MAX := 1.0

@export var road: RoadBuilder
@export var terrain: TerrainBuilder
@export var car: ArcadeCar

## The table as read (empty when the file is missing or invalid: the
## node then writes nothing and describe() says so), the shoulder band
## [m], and the numbers by surface name.
var table: Dictionary = {}
var shoulder_m := 0.0
var grip_by_surface: Dictionary = {}
var drag_by_surface: Dictionary = {}
var bump_by_surface: Dictionary = {}
## The wrapper handed the road and the car (null until the first tick).
var profile: RingProfile = null
## What the wheels stood on at the last tick (FL, FR, RL, RR), the axles'
## names (the lower-grip wheel of the pair: what the driver would call
## it), the numbers written, and how many ticks have run.
var wheel_surfaces: Array[StringName] = [&"road", &"road", &"road", &"road"]
var front_surface: StringName = &"road"
var rear_surface: StringName = &"road"
var front_grip := 1.0
var rear_grip := 1.0
var rolling_decel := 0.0
var ticks := 0
## Off: the wheels are classified but the car is not written.
var enabled := true


func _ready() -> void:
	process_physics_priority = -1
	var data: Variant = read_file()
	var errors := validate(data)
	if not errors.is_empty():
		push_error("Surfaces: %s is not a valid surfaces table: %s" % [PATH, errors])
		return
	table = data
	shoulder_m = float(table.rules.shoulder_m)
	for name: String in table.surfaces:
		var entry: Dictionary = table.surfaces[name]
		grip_by_surface[StringName(name)] = float(entry.grip)
		drag_by_surface[StringName(name)] = float(entry.rolling_drag)
		bump_by_surface[StringName(name)] = float(entry.bump)


func _physics_process(_delta: float) -> void:
	if profile == null:
		swap_profile()
	ticks += 1
	if car == null or table.is_empty():
		return
	for i: int in wheel_surfaces.size():
		var contact: Vector3 = car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]
		wheel_surfaces[i] = classify(contact.x, contact.z)
	front_surface = wheel_surfaces[0] if grip_of(wheel_surfaces[0]) <= grip_of(wheel_surfaces[1]) else wheel_surfaces[1]
	rear_surface = wheel_surfaces[2] if grip_of(wheel_surfaces[2]) <= grip_of(wheel_surfaces[3]) else wheel_surfaces[3]
	front_grip = (grip_of(wheel_surfaces[0]) + grip_of(wheel_surfaces[1])) * 0.5
	rear_grip = (grip_of(wheel_surfaces[2]) + grip_of(wheel_surfaces[3])) * 0.5
	rolling_decel = (drag_of(wheel_surfaces[0]) + drag_of(wheel_surfaces[1]) + drag_of(wheel_surfaces[2]) + drag_of(wheel_surfaces[3])) * 0.25
	if enabled:
		apply_grip(car)


## Writes the three surface inputs into the car (the header's grant).
func apply_grip(target: ArcadeCar) -> void:
	target.front_surface_grip = front_grip
	target.rear_surface_grip = rear_grip
	target.surface_rolling_decel = rolling_decel


## Wraps the road's profile (the header's THE PROFILE SWAP); once.
func swap_profile() -> void:
	if road == null or road.profile == null:
		return
	if road.profile is RingProfile:
		profile = road.profile
		return
	profile = RingProfile.over(road.profile, terrain, bump_by_surface)
	road.profile = profile
	if car != null:
		car.road_profile = profile


## The surface under a world point (TerrainBuilder.surface_at with the
## table's shoulder; grass without a terrain).
func classify(x: float, z: float) -> StringName:
	if terrain == null:
		return TerrainBuilder.SURFACE_GRASS
	return terrain.surface_at(x, z, shoulder_m)


func grip_of(surface: StringName) -> float:
	return float(grip_by_surface.get(surface, 1.0))


func drag_of(surface: StringName) -> float:
	return float(drag_by_surface.get(surface, 0.0))


func bump_of(surface: StringName) -> float:
	return float(bump_by_surface.get(surface, 0.0))


# =============================================================================
#  THE TABLE
# =============================================================================

## What JSON.parse_string makes of the table: null where it is missing or
## not JSON.
static func read_file(path: String = PATH) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))


## Everything wrong with a table, one line each; empty = valid: the four
## top keys, the region, the rules' shoulder a non-negative number, every
## named surface present with its four keys, grip in [GRIP_MIN,
## GRIP_MAX], rolling_drag and bump >= 0, the road exactly {1, 0, 0}.
static func validate(data: Variant) -> PackedStringArray:
	var errors := PackedStringArray()
	if not data is Dictionary:
		errors.append("not a JSON object (a file that is not there, or not JSON)")
		return errors
	for key: String in TABLE_KEYS:
		if not data.has(key):
			errors.append("%s is missing" % key)
	for key: String in data:
		if not key in TABLE_KEYS:
			errors.append("%s is not in the schema" % key)
	if data.get("region") != REGION:
		errors.append("region is %s, this reader's is %s" % [data.get("region"), REGION])
	var rules: Variant = data.get("rules")
	if not rules is Dictionary:
		errors.append("rules is not an object")
	else:
		for key: String in rules:
			if not key in RULE_KEYS:
				errors.append("rules.%s is not in the schema" % key)
		if not _is_number(rules.get("shoulder_m")) or rules.shoulder_m < 0.0:
			errors.append("rules.shoulder_m is %s, not a non-negative number" % [rules.get("shoulder_m")])
	var surfaces: Variant = data.get("surfaces")
	if not surfaces is Dictionary:
		errors.append("surfaces is not an object")
		return errors
	for name: String in SURFACE_NAMES:
		if not surfaces.has(name):
			errors.append("surfaces.%s is missing" % name)
	for name: String in surfaces:
		if not name in SURFACE_NAMES:
			errors.append("surfaces.%s is not a surface this pass names" % name)
			continue
		var entry: Variant = surfaces[name]
		if not entry is Dictionary:
			errors.append("surfaces.%s is not an object" % name)
			continue
		for key: String in SURFACE_KEYS:
			if not entry.has(key):
				errors.append("surfaces.%s.%s is missing" % [name, key])
		for key: String in entry:
			if not key in SURFACE_KEYS:
				errors.append("surfaces.%s.%s is not in the schema" % [name, key])
		if not _is_number(entry.get("grip")) or entry.grip < GRIP_MIN or entry.grip > GRIP_MAX:
			errors.append("surfaces.%s.grip is %s, not in [%.1f, %.1f]" % [name, entry.get("grip"), GRIP_MIN, GRIP_MAX])
		if not _is_number(entry.get("rolling_drag")) or entry.rolling_drag < 0.0:
			errors.append("surfaces.%s.rolling_drag is %s, not a non-negative number" % [name, entry.get("rolling_drag")])
		if not _is_number(entry.get("bump")) or entry.bump < 0.0:
			errors.append("surfaces.%s.bump is %s, not a non-negative number" % [name, entry.get("bump")])
		if name == "road" and not (entry.get("grip") == 1.0 and entry.get("rolling_drag") == 0.0 and entry.get("bump") == 0.0):
			errors.append("surfaces.road is %s / %s / %s, not the exact {1.0, 0.0, 0.0} of the certified baseline" % [entry.get("grip"), entry.get("rolling_drag"), entry.get("bump")])
	return errors


static func _is_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(value)


## One line: the table and the last tick's read.
func describe() -> String:
	if table.is_empty():
		return "no surfaces table"
	var lines := PackedStringArray()
	for name: String in SURFACE_NAMES:
		lines.append("%s %.2f/%.1f/%.3f" % [name, grip_of(name), drag_of(name), bump_of(name)])
	return "surfaces (grip/drag/bump) %s, shoulder %.1f m; tick %d: wheels %s, front %s %.3f, rear %s %.3f, rolling %.2f m/s^2" % [", ".join(lines), shoulder_m, ticks, wheel_surfaces, front_surface, front_grip, rear_surface, rear_grip, rolling_decel]
