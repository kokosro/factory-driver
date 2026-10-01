class_name SkySet
extends Node
## The Ring's sky and light (implementation-plan.md §4B-7; element-library.md
## §4): the region's sky set S1 (clear day: one sun, one sky) and the S5
## distance haze, put on the scene's WorldEnvironment and Sun at _ready from
## the catalogue's numbers and the region table's choices
## (ring-region-decisions.md §5, PUT IN STONE: "Sky set: S1 clear day as
## default ... Haze table S5 exactly as the canon's ... haze colour = the
## plate's horizon"). Nothing here touches the car, the road or the
## physics: a light and an environment are all this node configures.
##
## S1 - the sun: one DirectionalLight3D, its elevation the catalogue's
## sun_elevation_deg default (45°, S1 varies) and its azimuth the region
## table's (the scene's own bearing kept: the Sun node of eifel_ring.tscn
## stood in the south-south-west, bearing 210°, at 50° elevation - was 50°
## -> 45°, the catalogue's default; the bearing unchanged), "slightly warm
## highlights" as a light colour, shadows on and "clearly readable but not
## pitch black" through the sky's ambient contribution (the environment's
## ambient source is its background, the sky). One sky: the scene's
## ProceduralSkyMaterial stays the S1 plate (the canon's "photographic
## skybox" is an asset this pass does not add: no new binary assets; the
## plate's horizon colour is what S5 needs and the material carries it).
##
## The ambient (ATMOS-1; the canon's Lighting: "very restrained ambient
## illumination", "shadows clearly readable but not pitch black", "neutral
## midtones"): the environment's ambient light is the sky's irradiance
## mixed with a flat neutral colour - AMBIENT_SKY_CONTRIBUTION of the sky,
## the rest AMBIENT_COLOUR, the whole times AMBIENT_ENERGY (Godot's
## ambient_light_sky_contribution, ambient_light_color and
## ambient_light_energy, the source the sky named outright). Before
## ATMOS-1 the sky was the entire ambient (the engine's default for a sky
## background) and the plate's saturated zenith flooded every shadow blue:
## the probe's shaded road read 40 to 56 more blue than red (0-255) and
## the darkest 5 % of every shot had 2.4 to 2.5 times the blue of the red.
## Under a neutral flat colour with a small share of the sky the shadows
## are neutral-dark and the sky's cool cast is a hint, the haze's job
## keeping the distance cool. The sun is untouched by this: its colour,
## energy, elevation and bearing stand where S1 put them.
##
## S5 - the haze: the canon's four bands, "0-100 m normal saturation /
## 100-300 m slight haze / 300-800 m reduced contrast / 800 m+ increasingly
## sky-colored", are the catalogue's stone distances (S5.stone_parameters:
## normal_saturation_to_m 100, slight_haze_to_m 300, reduced_contrast_to_m
## 800, sky_coloured_from_m 800). The canon names the bands, not the
## amounts, so the amounts are chosen here and named: haze fraction 0 to
## the first band's end, SLIGHT_HAZE (0.15) at the second's, REDUCED_CONTRAST
## (0.45) at the third's, and 1.0 (all sky) at SKY_COLOURED_FULL_M (3 000
## m), linear between (haze_at). Godot's depth fog is one power curve, not
## a polyline: the environment gets fog_depth_begin = the first band's end,
## fog_depth_end = SKY_COLOURED_FULL_M, fog_density 1 and the exponent that
## puts the engine's curve through the slight-haze point (fitted_curve);
## depth_fog_at mirrors the engine's formula (pow(smoothstep(begin, end,
## depth), curve) × density: the depth mode's fog_process, Godot 4.3+) so
## the suite can hold the engine's curve to the four-band table within
## FIT_TOLERANCE at every band (tests/dressing_test.gd measures 0.082 vs
## 0.075 at 200 m, 0.271 vs 0.270 at 500 m, 0.522 vs 0.500 at 1 000 m). Depth
## fog, "not volumetric cinematic fog": volumetric fog stays off. The haze
## colour is the sky plate's horizon colour, read from the material, never
## a second constant. fog_sky_affect 0: the sky is the plate, the haze
## tends toward its horizon.
##
## The region table (data/regions/eifel_ring/dressing.json, read through
## TerrainBuilder.region_dressing()) names the set
## ("S1"), the haze ("S5") and the sun's bearing; the catalogue carries
## the stone. A table naming another set is refused with a push_error and
## the scene keeps what it had: nothing is guessed.
##
## THE WEATHER (WEATHER-1; docs/art-direction.md, Weather and Sky: "Rain is
## particularly useful for this aesthetic. Don't turn it into a modern
## weather showcase. Use: darkened asphalt, simple rain streaks, grey sky,
## slightly reduced visibility, car reflections on road, taillight
## reflections, occasional spray. The wet road should become noticeably
## more reflective." and "Blue sky with soft clouds. Grey overcast. Orange
## sunset. Dark blue evening."): FD_WEATHER in the environment, read once
## in apply(), the FD_SOUND shape. Unset or "0" is the clear day above,
## to the bit: no weather key in `applied`, the describe() line as it
## was, no copy of anything, no node added, no signal connected. "overcast",
## "sunset", "evening" and "rain" name a row of WEATHER_STATES (consts
## here: the catalogue is frozen and carries no weather); anything else
## is refused with a push_error naming it and the scene stays clear. A
## state runs AFTER the clear path, on top of it: the sun's elevation,
## colour and energy (the bearing stays the table's: a sunset sets where
## the sun stands; the shadows stay on), whether the plate draws the
## sun's disc (not under cloud), the ambient trio, the plate's four
## colours and the haze. THE PLATE IS COPIED, NOT WRITTEN: the scene's
## Environment, Sky and ProceduralSkyMaterial are sub-resources of the
## packed scene, shared by every instance of it in the process, so a
## state takes its own copies (_weather_plate) and hands them to the
## WorldEnvironment - a weather scene never leaks its plate into a clear
## scene loaded after it (the dressing test loads a clear scene after the
## four states and holds it identical to the one before). The haze keeps
## its mechanism: the colour is re-read from the (new) plate's horizon,
## so it greys under cloud and warms at sunset by itself, and the curve
## is re-fitted by the same fitted_curve through the state's table - the
## clear amounts times the state's `haze` multiplier, reaching the sky at
## the state's `all_sky_m`. The two go together: one exponent can only
## follow a table whose amounts grew if its end came in (measured: x 1.2
## fits at 2 350 m, x 1.4 at 1 900 m, each within FIT_TOLERANCE at the
## dressing test's four samples; x 1.4 at the clear 3 000 m is 0.13 off
## at 1 000 m), and the nearer end IS the "slightly reduced visibility" -
## 1.9 km of landscape under rain, never a fog wall.
##
## RAIN adds two things. THE WET ROAD: RoadBuilder.wet_road() on the scene
## root's "Road" child, one deferred call after apply() (the strips exist
## by then on the sync build and under the loading scene alike; a scene
## without a Road - the pad - is skipped quietly). THE STREAKS: one
## CPUParticles3D child ("Rain") built in code - RAIN_STREAKS thin
## vertical quads born on a RAIN_BOX_M.x by RAIN_BOX_M.z plane
## RAIN_ABOVE_M over the car and falling RAIN_BOX_M.y straight down at
## RAIN_SPEED_MPS (no wind in v1), unshaded, half-transparent, no
## texture; every randomness parameter 0 and the emitter's seed fixed
## (RAIN_SEED), the lifetime the box's height over the speed. The field
## rides with the car, position only (local coordinates: the density
## around the car is the same at any speed - the period's rain hangs on
## the viewer; a streak fades in over RAIN_FADE_FROM_M..RAIN_FADE_TO_M
## from the camera), put there each physics tick off the tree's physics_frame
## signal (connected under rain only); the car is the first ArcadeCar
## under the scene root, or the next one to enter it (node_added, the
## watchers' way), or `rain_anchor` when a probe names another node; no
## car, no rain: the field hides and stops emitting. THE REFLECTIONS:
## the rain's Environment copy has screen-space reflections on (see
## RAIN_SSR_MAX_STEPS) - the car and its taillights in the wet road.
## NOT IN V1 (parked):
## wet GRIP (scripts/surfaces.gd and the region's surfaces.json are
## frozen: a wet surface class needs a freeze ruling of its own), puddle
## geometry, drips on the camera, wind-driven rain, spray. Nothing here
## touches the car or the physics in any state.

## The elements this node instantiates: ids in the catalogue (the test
## holds each to ElementCatalogue.entry).
const ELEMENTS := ["S1", "S5"]

## The haze amounts at the band ends (chosen for the dressing, see above).
const SLIGHT_HAZE := 0.15
const REDUCED_CONTRAST := 0.45
## Where "increasingly sky-coloured" reaches the sky [m] (chosen; the
## canon's last band has no end).
const SKY_COLOURED_FULL_M := 3000.0
## How far the engine's one-exponent curve may sit from the four-band
## polyline at a sampled distance (measured 0.02 at 1 000 m, the worst).
const FIT_TOLERANCE := 0.03

## The sun's light: "slightly warm highlights".
const SUN_COLOUR := Color(1.0, 0.965, 0.9, 1.0)
const SUN_ENERGY := 1.0
## The ambient, restrained (see above): the flat neutral colour, its
## energy, and the sky's share of the mix.
const AMBIENT_COLOUR := Color(0.45, 0.45, 0.45, 1.0)
const AMBIENT_ENERGY := 1.0
const AMBIENT_SKY_CONTRIBUTION := 0.15
## The sun's bearing, clockwise from north [deg], when the region table
## names none (the scene's Sun stood here).
const DEFAULT_SUN_AZIMUTH_DEG := 210.0
## The sun's height above the ground it looks at [m] (a directional light's
## position is cosmetic; kept clear of the terrain).
const SUN_HEIGHT_M := 20.0

## THE WEATHER SWITCH (WEATHER-1; see the header): the environment
## variable and its states. Each row: the sun (elevation above the
## horizon, colour, energy, whether the plate draws its disc), the
## ambient trio, the plate's four colours, the haze table's multiplier
## and where the table reaches the sky. Display colours, restrained
## saturation (the canon's palette: "Keep saturation restrained").
const ENV_VAR := "FD_WEATHER"
const WEATHER_OFF := "0"
const WEATHER_RAIN := "rain"
const WEATHER_STATES := {
	# "Grey overcast": the sun a weak cool-grey light behind the cloud (no
	# disc), the ambient flatter and brighter with half of it the sky's.
	"overcast": {
		"sun_elevation_deg": 45.0, "sun_colour": Color(0.8, 0.82, 0.85, 1.0), "sun_energy": 0.45, "sun_disc": false,
		"ambient_colour": Color(0.55, 0.56, 0.58, 1.0), "ambient_energy": 1.0, "ambient_sky_contribution": 0.5,
		"sky_top": Color(0.56, 0.59, 0.63, 1.0), "sky_horizon": Color(0.7, 0.72, 0.75, 1.0),
		"ground_bottom": Color(0.16, 0.17, 0.19, 1.0), "ground_horizon": Color(0.7, 0.72, 0.75, 1.0),
		"haze": 1.2, "all_sky_m": 2350.0,
	},
	# "Orange sunset": the sun 10° up and warm, a warm dim ambient, an
	# orange horizon under a deep blue top; the clear air's haze table.
	"sunset": {
		"sun_elevation_deg": 10.0, "sun_colour": Color(1.0, 0.62, 0.36, 1.0), "sun_energy": 0.8, "sun_disc": true,
		"ambient_colour": Color(0.42, 0.36, 0.34, 1.0), "ambient_energy": 0.8, "ambient_sky_contribution": 0.25,
		"sky_top": Color(0.2, 0.3, 0.52, 1.0), "sky_horizon": Color(0.9, 0.6, 0.42, 1.0),
		"ground_bottom": Color(0.12, 0.11, 0.12, 1.0), "ground_horizon": Color(0.9, 0.6, 0.42, 1.0),
		"haze": 1.0, "all_sky_m": 3000.0,
	},
	# "Dark blue evening": the sun all but set (4°, a fifth of its light,
	# cool), a dim bluish ambient, a dark blue plate; the clear table.
	"evening": {
		"sun_elevation_deg": 4.0, "sun_colour": Color(0.55, 0.62, 0.85, 1.0), "sun_energy": 0.2, "sun_disc": false,
		"ambient_colour": Color(0.2, 0.24, 0.34, 1.0), "ambient_energy": 0.8, "ambient_sky_contribution": 0.3,
		"sky_top": Color(0.05, 0.08, 0.2, 1.0), "sky_horizon": Color(0.16, 0.22, 0.38, 1.0),
		"ground_bottom": Color(0.03, 0.04, 0.07, 1.0), "ground_horizon": Color(0.16, 0.22, 0.38, 1.0),
		"haze": 1.0, "all_sky_m": 3000.0,
	},
	# Rain: the overcast plate darker and greyer, "slightly reduced
	# visibility" (the table x 1.4, all sky at 1.9 km), and the wet road
	# and the streaks (see the header).
	"rain": {
		"sun_elevation_deg": 45.0, "sun_colour": Color(0.72, 0.75, 0.8, 1.0), "sun_energy": 0.3, "sun_disc": false,
		"ambient_colour": Color(0.48, 0.5, 0.53, 1.0), "ambient_energy": 0.9, "ambient_sky_contribution": 0.5,
		"sky_top": Color(0.4, 0.43, 0.47, 1.0), "sky_horizon": Color(0.56, 0.58, 0.61, 1.0),
		"ground_bottom": Color(0.12, 0.13, 0.14, 1.0), "ground_horizon": Color(0.56, 0.58, 0.61, 1.0),
		"haze": 1.4, "all_sky_m": 1900.0,
	},
}

## THE RAIN STREAKS ("simple rain streaks", not a storm; see the header):
## how many, the box they fill (x across, y the fall, z along) [m], how
## far over the car they are born [m] (the rest of the fall is under the
## car's height: a road falling away at 20 % is 4 m down at the box's
## edge), the fall [m/s], one streak's quad [m], its colour (unshaded,
## no texture) and the emitter's fixed seed.
const RAIN_STREAKS := 360
const RAIN_BOX_M := Vector3(40.0, 25.0, 40.0)
const RAIN_ABOVE_M := 20.0
const RAIN_SPEED_MPS := 12.0
const RAIN_STREAK_M := Vector2(0.02, 0.5)
const RAIN_COLOUR := Color(0.8, 0.84, 0.9, 0.35)
const RAIN_SEED := 1
## A streak fades in between these distances from the camera [m]: one a
## metre from the lens is a bar across the frame, not a streak.
const RAIN_FADE_FROM_M := 1.0
const RAIN_FADE_TO_M := 5.0
## THE REFLECTIONS (rain; "car reflections on road, taillight
## reflections"): a rougher-to-smoother road alone mirrors only the sky
## plate and the sun, so the rain's own Environment copy turns on the
## engine's screen-space reflections - what is on screen (the car, its
## taillights, the tree line) mirrored in the wet road, nothing rendered
## twice. The march's steps and the fades (the engine's units).
const RAIN_SSR_MAX_STEPS := 64
const RAIN_SSR_FADE_IN := 0.15
const RAIN_SSR_FADE_OUT := 2.0
const RAIN_NODE := "Rain"
## The scene root's child the wet road is asked of.
const ROAD_NODE := "Road"

@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D

## What was applied: the set id, the haze id, the numbers (for the test and
## for describe()).
var applied: Dictionary = {}

## The node the rain rides with instead of the car (a probe's camera);
## null everywhere else.
var rain_anchor: Node3D
## The streak field (rain only; null in every other state) and the car
## it rides with.
var rain: CPUParticles3D
var _rain_car: Node3D


func _ready() -> void:
	apply()


## Reads the catalogue and the region table and configures the environment
## and the sun. Refuses (push_error, nothing changed) when the table names
## another set than S1/S5 or the catalogue lacks the entries.
func apply() -> void:
	var table := TerrainBuilder.region_dressing()
	var set_id: String = table.get("sky_set", "S1")
	var haze_id: String = table.get("haze", "S5")
	if set_id != "S1" or haze_id != "S5":
		push_error("SkySet: the region table names %s / %s; this pass builds S1 / S5 only" % [set_id, haze_id])
		return
	var clear_day := ElementCatalogue.entry("S1")
	var haze := ElementCatalogue.entry("S5")
	if clear_day.is_empty() or haze.is_empty():
		push_error("SkySet: S1 or S5 is not in the catalogue")
		return
	var bands := haze_bands(haze)
	# WEATHER-1: the state, or "" - the clear day, every line below as it was.
	var asked := OS.get_environment(ENV_VAR)
	var weather := weather_state(asked)
	if weather == "" and asked != "" and asked != WEATHER_OFF:
		push_error("SkySet: %s names no weather (%s); the clear day stands (overcast, sunset, evening, rain, or unset / 0)" % [ENV_VAR, asked])
	var elevation: float = float(clear_day.varies.sun_elevation_deg.default)
	var azimuth: float = float(table.get("sun", {}).get("azimuth_deg", DEFAULT_SUN_AZIMUTH_DEG))
	if sun != null:
		_aim_sun(elevation, azimuth)
	var horizon := Color(0.68, 0.78, 0.88, 1.0)
	if environment != null and environment.environment != null:
		horizon = horizon_colour(environment.environment)
		_apply_ambient(environment.environment)
		_apply_fog(environment.environment, bands, horizon)
	applied = {
		"sky_set": set_id, "haze": haze_id, "suns": int(clear_day.stone_parameters.suns), "skies": int(clear_day.stone_parameters.skies),
		"sun_elevation_deg": elevation, "sun_azimuth_deg": azimuth, "bands": bands, "haze_colour": horizon,
		"fog_depth_begin": bands.normal_to, "fog_depth_end": SKY_COLOURED_FULL_M, "fog_depth_curve": fitted_curve(bands),
		"ambient_colour": AMBIENT_COLOUR, "ambient_energy": AMBIENT_ENERGY, "ambient_sky_contribution": AMBIENT_SKY_CONTRIBUTION,
	}
	if weather != "":
		_apply_weather(weather, bands, azimuth)


## The weather a value of FD_WEATHER names: a key of WEATHER_STATES, or ""
## (the clear day) for unset, "0" and anything that names none (apply()
## says so for the last). Pure: no error, no state.
static func weather_state(value: String) -> String:
	return value if WEATHER_STATES.has(value) else ""


## A state on top of the clear day apply() just put (see the header): the
## sun, the plate's own copies, the ambient, the haze re-read and
## re-fitted, the numbers into `applied` (the clear keys overwritten where
## the state moved them, `weather` and the state's own added), and under
## rain the streaks now and the wet road one deferred call later.
func _apply_weather(weather: String, bands: Dictionary, azimuth: float) -> void:
	var state: Dictionary = WEATHER_STATES[weather]
	if sun != null:
		_aim_sun(state.sun_elevation_deg, azimuth)
		sun.light_color = state.sun_colour
		sun.light_energy = state.sun_energy
		sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY if state.sun_disc else DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	var horizon: Color = state.sky_horizon
	if environment != null and environment.environment != null:
		var env := _weather_plate(environment.environment, state)
		environment.environment = env
		horizon = horizon_colour(env)
		env.ambient_light_color = state.ambient_colour
		env.ambient_light_energy = state.ambient_energy
		env.ambient_light_sky_contribution = state.ambient_sky_contribution
		_apply_fog(env, bands, horizon, state.haze, state.all_sky_m)
		if weather == WEATHER_RAIN:
			env.ssr_enabled = true
			env.ssr_max_steps = RAIN_SSR_MAX_STEPS
			env.ssr_fade_in = RAIN_SSR_FADE_IN
			env.ssr_fade_out = RAIN_SSR_FADE_OUT
	applied["weather"] = weather
	applied["sun_elevation_deg"] = state.sun_elevation_deg
	applied["sun_colour"] = state.sun_colour
	applied["sun_energy"] = state.sun_energy
	applied["sun_disc"] = state.sun_disc
	applied["ambient_colour"] = state.ambient_colour
	applied["ambient_energy"] = state.ambient_energy
	applied["ambient_sky_contribution"] = state.ambient_sky_contribution
	applied["sky_top"] = state.sky_top
	applied["haze_colour"] = horizon
	applied["haze_multiplier"] = state.haze
	applied["fog_depth_end"] = state.all_sky_m
	applied["fog_depth_curve"] = fitted_curve(bands, state.haze, state.all_sky_m)
	if weather == WEATHER_RAIN and is_inside_tree():
		_start_rain()
		_wet_the_road.call_deferred()


## The state's plate: copies of the scene's Environment, Sky and
## ProceduralSkyMaterial (the packed scene's shared sub-resources are
## never written: see the header) with the state's four colours. A scene
## without a procedural plate gets the Environment's copy alone.
func _weather_plate(shared: Environment, state: Dictionary) -> Environment:
	var env: Environment = shared.duplicate()
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		var sky: Sky = env.sky.duplicate()
		var plate: ProceduralSkyMaterial = sky.sky_material.duplicate()
		plate.sky_top_color = state.sky_top
		plate.sky_horizon_color = state.sky_horizon
		plate.ground_bottom_color = state.ground_bottom
		plate.ground_horizon_color = state.ground_horizon
		sky.sky_material = plate
		env.sky = sky
	return env


## The wet road (rain; one deferred call after apply(), when the strips
## stand): RoadBuilder.wet_road() on the scene root's Road child. A scene
## without one is skipped quietly; `applied.wet_strips` is how many strips
## took the wet material.
func _wet_the_road() -> void:
	if not is_inside_tree() or get_parent() == null:
		return
	var road := get_parent().get_node_or_null(ROAD_NODE) as RoadBuilder
	applied["wet_strips"] = road.wet_road() if road != null else 0


## The streak field (rain; see the header and the RAIN_ constants): built
## once, under this node, riding with the car from the next physics tick.
func _start_rain() -> void:
	if rain != null:
		return
	rain = rain_field()
	rain.name = RAIN_NODE
	rain.emitting = false
	rain.visible = false
	add_child(rain)
	_rain_car = _first_car(get_parent())
	get_tree().node_added.connect(_on_node_added)
	get_tree().physics_frame.connect(_follow_car)
	applied["rain_streaks"] = RAIN_STREAKS


## The streak field's node, from the RAIN_ constants alone (static: the
## test builds one beside the scene's and compares).
static func rain_field() -> CPUParticles3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = RAIN_COLOUR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.billboard_keep_scale = true
	material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	material.distance_fade_min_distance = RAIN_FADE_FROM_M
	material.distance_fade_max_distance = RAIN_FADE_TO_M
	var streak := QuadMesh.new()
	streak.size = RAIN_STREAK_M
	streak.material = material
	var field := CPUParticles3D.new()
	field.mesh = streak
	field.amount = RAIN_STREAKS
	field.lifetime = RAIN_BOX_M.y / RAIN_SPEED_MPS
	field.preprocess = field.lifetime
	field.local_coords = true
	field.one_shot = false
	field.explosiveness = 0.0
	field.randomness = 0.0
	field.lifetime_randomness = 0.0
	field.use_fixed_seed = true
	field.seed = RAIN_SEED
	field.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	field.emission_box_extents = Vector3(RAIN_BOX_M.x * 0.5, 0.0, RAIN_BOX_M.z * 0.5)
	field.direction = Vector3.DOWN
	field.spread = 0.0
	field.flatness = 0.0
	field.gravity = Vector3.ZERO
	field.initial_velocity_min = RAIN_SPEED_MPS
	field.initial_velocity_max = RAIN_SPEED_MPS
	field.particle_flag_align_y = false
	field.particle_flag_rotate_y = false
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return field


## The first ArcadeCar under a node, depth first, or null.
static func _first_car(under: Node) -> Node3D:
	if under == null:
		return null
	if under is ArcadeCar:
		return under
	for child: Node in under.get_children():
		var found := _first_car(child)
		if found != null:
			return found
	return null


## A car entering this scene while the rain has none to ride with.
func _on_node_added(node: Node) -> void:
	if node is ArcadeCar and not is_instance_valid(_rain_car) and get_parent() != null and get_parent().is_ancestor_of(node):
		_rain_car = node


## Each physics tick under rain: the field's birth plane RAIN_ABOVE_M
## over the anchor (`rain_anchor`, else the car), position only; no
## anchor, no rain.
func _follow_car() -> void:
	if rain == null:
		return
	var anchor: Node3D = rain_anchor if is_instance_valid(rain_anchor) else _rain_car
	var present := is_instance_valid(anchor) and anchor.is_inside_tree()
	if rain.visible != present:
		rain.visible = present
		rain.emitting = present
	if present:
		rain.global_position = anchor.global_position + Vector3(0.0, RAIN_ABOVE_M, 0.0)


func _exit_tree() -> void:
	if rain != null:
		get_tree().node_added.disconnect(_on_node_added)
		get_tree().physics_frame.disconnect(_follow_car)


## The four band ends from the catalogue's S5 stone parameters [m].
static func haze_bands(haze: Dictionary) -> Dictionary:
	var stone: Dictionary = haze.get("stone_parameters", {})
	return {
		"normal_to": float(stone.get("normal_saturation_to_m", 100.0)),
		"slight_to": float(stone.get("slight_haze_to_m", 300.0)),
		"reduced_to": float(stone.get("reduced_contrast_to_m", 800.0)),
		"sky_from": float(stone.get("sky_coloured_from_m", 800.0)),
	}


## The four-band haze curve [0..1] at a distance [m]: 0 through the first
## band, linear to SLIGHT_HAZE at the second's end, to REDUCED_CONTRAST at
## the third's, to 1 at SKY_COLOURED_FULL_M, 1 beyond. WEATHER-1: a
## state's table is the two amounts times `multiplier`, reaching 1 at
## `all_sky_m` (the clear day's 1 and SKY_COLOURED_FULL_M by default: the
## same arithmetic on the same numbers).
static func haze_at(distance: float, bands: Dictionary, multiplier: float = 1.0, all_sky_m: float = SKY_COLOURED_FULL_M) -> float:
	var slight := SLIGHT_HAZE * multiplier
	var reduced := REDUCED_CONTRAST * multiplier
	if distance <= bands.normal_to:
		return 0.0
	if distance <= bands.slight_to:
		return slight * (distance - bands.normal_to) / (bands.slight_to - bands.normal_to)
	if distance <= bands.reduced_to:
		return lerpf(slight, reduced, (distance - bands.slight_to) / (bands.reduced_to - bands.slight_to))
	if distance <= all_sky_m:
		return lerpf(reduced, 1.0, (distance - bands.reduced_to) / (all_sky_m - bands.reduced_to))
	return 1.0


## The band a distance falls in, by the catalogue's names.
static func band_of(distance: float, bands: Dictionary) -> String:
	if distance <= bands.normal_to:
		return "normal saturation"
	if distance <= bands.slight_to:
		return "slight haze"
	if distance <= bands.reduced_to:
		return "reduced contrast"
	return "increasingly sky-coloured"


## The engine's depth fog at a distance: pow(smoothstep(begin, end, depth),
## curve) × density (Godot's depth fog mode, mirrored).
static func depth_fog_at(distance: float, begin: float, end: float, curve: float, density: float) -> float:
	return pow(smoothstep(begin, end, distance), curve) * density


## The exponent that puts the engine's curve through the slight-haze point
## (SLIGHT_HAZE at the second band's end) with begin at the first band's
## end and end at SKY_COLOURED_FULL_M. WEATHER-1: a state's point is
## SLIGHT_HAZE × `multiplier`, its end `all_sky_m` (the defaults the
## clear day's).
static func fitted_curve(bands: Dictionary, multiplier: float = 1.0, all_sky_m: float = SKY_COLOURED_FULL_M) -> float:
	var s := smoothstep(bands.normal_to, all_sky_m, bands.slight_to)
	return log(SLIGHT_HAZE * multiplier) / log(s)


## The sky plate's horizon colour: the ProceduralSkyMaterial's, else the
## PhysicalSkyMaterial's ground colour, else a pale blue.
static func horizon_colour(env: Environment) -> Color:
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		return env.sky.sky_material.sky_horizon_color
	return Color(0.68, 0.78, 0.88, 1.0)


## The restrained ambient: the sky's irradiance at AMBIENT_SKY_CONTRIBUTION
## over the flat AMBIENT_COLOUR, times AMBIENT_ENERGY. The sky stays the
## background and the reflection source (the plate is what the car and the
## road mirror); only the ambient's share of it is held down.
func _apply_ambient(env: Environment) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_color = AMBIENT_COLOUR
	env.ambient_light_energy = AMBIENT_ENERGY
	env.ambient_light_sky_contribution = AMBIENT_SKY_CONTRIBUTION


func _apply_fog(env: Environment, bands: Dictionary, horizon: Color, multiplier: float = 1.0, all_sky_m: float = SKY_COLOURED_FULL_M) -> void:
	env.volumetric_fog_enabled = false
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = horizon
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = 0.0
	env.fog_density = 1.0
	env.fog_aerial_perspective = 0.0
	env.fog_sky_affect = 0.0
	env.fog_height_density = 0.0
	env.fog_depth_begin = bands.normal_to
	env.fog_depth_end = all_sky_m
	env.fog_depth_curve = fitted_curve(bands, multiplier, all_sky_m)


## Points the sun: elevation above the horizon and bearing clockwise from
## north, in the x-east / z-south frame (north is -z).
func _aim_sun(elevation_deg: float, azimuth_deg: float) -> void:
	var el := deg_to_rad(elevation_deg)
	var az := deg_to_rad(azimuth_deg)
	var toward_sun := Vector3(sin(az) * cos(el), sin(el), -cos(az) * cos(el))
	var at := Vector3(0.0, SUN_HEIGHT_M, 0.0)
	sun.look_at_from_position(at, at - toward_sun, Vector3.UP)
	sun.light_color = SUN_COLOUR
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = true


## One line on what was applied (no wall clock).
func describe() -> String:
	if applied.is_empty():
		return "nothing applied"
	var line := "%s + %s: sun %.0f° at bearing %.0f°, ambient %s x %.2f with %.2f of the sky, haze begins %.0f m, all sky at %.0f m, curve %.3f, colour %s" % [applied.sky_set, applied.haze, applied.sun_elevation_deg, applied.sun_azimuth_deg, applied.ambient_colour, applied.ambient_energy, applied.ambient_sky_contribution, applied.fog_depth_begin, applied.fog_depth_end, applied.fog_depth_curve, applied.haze_colour]
	if not applied.has("weather"):
		return line
	line += ", weather %s (sun %s x %.2f, haze x %.2f)" % [applied.weather, applied.sun_colour, applied.sun_energy, applied.haze_multiplier]
	if applied.has("rain_streaks"):
		line += ", %d rain streaks, wet road on %d strips" % [applied.rain_streaks, applied.get("wet_strips", 0)]
	return line
