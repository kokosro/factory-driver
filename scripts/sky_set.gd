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
## The sun's bearing, clockwise from north [deg], when the region table
## names none (the scene's Sun stood here).
const DEFAULT_SUN_AZIMUTH_DEG := 210.0
## The sun's height above the ground it looks at [m] (a directional light's
## position is cosmetic; kept clear of the terrain).
const SUN_HEIGHT_M := 20.0

@export var environment: WorldEnvironment
@export var sun: DirectionalLight3D

## What was applied: the set id, the haze id, the numbers (for the test and
## for describe()).
var applied: Dictionary = {}


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
	var elevation: float = float(clear_day.varies.sun_elevation_deg.default)
	var azimuth: float = float(table.get("sun", {}).get("azimuth_deg", DEFAULT_SUN_AZIMUTH_DEG))
	if sun != null:
		_aim_sun(elevation, azimuth)
	var horizon := Color(0.68, 0.78, 0.88, 1.0)
	if environment != null and environment.environment != null:
		horizon = horizon_colour(environment.environment)
		_apply_fog(environment.environment, bands, horizon)
	applied = {
		"sky_set": set_id, "haze": haze_id, "suns": int(clear_day.stone_parameters.suns), "skies": int(clear_day.stone_parameters.skies),
		"sun_elevation_deg": elevation, "sun_azimuth_deg": azimuth, "bands": bands, "haze_colour": horizon,
		"fog_depth_begin": bands.normal_to, "fog_depth_end": SKY_COLOURED_FULL_M, "fog_depth_curve": fitted_curve(bands),
	}


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
## the third's, to 1 at SKY_COLOURED_FULL_M, 1 beyond.
static func haze_at(distance: float, bands: Dictionary) -> float:
	if distance <= bands.normal_to:
		return 0.0
	if distance <= bands.slight_to:
		return SLIGHT_HAZE * (distance - bands.normal_to) / (bands.slight_to - bands.normal_to)
	if distance <= bands.reduced_to:
		return lerpf(SLIGHT_HAZE, REDUCED_CONTRAST, (distance - bands.slight_to) / (bands.reduced_to - bands.slight_to))
	if distance <= SKY_COLOURED_FULL_M:
		return lerpf(REDUCED_CONTRAST, 1.0, (distance - bands.reduced_to) / (SKY_COLOURED_FULL_M - bands.reduced_to))
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
## end and end at SKY_COLOURED_FULL_M.
static func fitted_curve(bands: Dictionary) -> float:
	var s := smoothstep(bands.normal_to, SKY_COLOURED_FULL_M, bands.slight_to)
	return log(SLIGHT_HAZE) / log(s)


## The sky plate's horizon colour: the ProceduralSkyMaterial's, else the
## PhysicalSkyMaterial's ground colour, else a pale blue.
static func horizon_colour(env: Environment) -> Color:
	if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
		return env.sky.sky_material.sky_horizon_color
	return Color(0.68, 0.78, 0.88, 1.0)


func _apply_fog(env: Environment, bands: Dictionary, horizon: Color) -> void:
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
	env.fog_depth_end = SKY_COLOURED_FULL_M
	env.fog_depth_curve = fitted_curve(bands)


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
	return "%s + %s: sun %.0f° at bearing %.0f°, haze begins %.0f m, all sky at %.0f m, curve %.3f, colour %s" % [applied.sky_set, applied.haze, applied.sun_elevation_deg, applied.sun_azimuth_deg, applied.fog_depth_begin, applied.fog_depth_end, applied.fog_depth_curve, applied.haze_colour]
