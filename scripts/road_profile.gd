class_name RoadProfile
extends Resource
## The road's height field: how high the tarmac is at (x, z) [m]. One pure,
## seeded function, so the car (which feels it), the pad (which renders it and
## stands things on it) and the tests (which check both) all read the same
## road. Nothing in the sampling path draws random numbers or keeps state: same
## (x, z), same height, every run.
##
## Four layers:
##   * ELEVATION: a gentle swell a few hundred metres long, the only layer the
##     ground mesh shows (the car rides all three on its springs). Zero round every
##     certification feature (start line, stop box, slalom line, skid pad) and
##     far from the course; inside the straight's lane it depends on z only, so
##     the lane never leans sideways.
##   * MICRO-BUMPS: centimetre-scale value noise, metres long. Felt in the
##     wheel loads and the ride, not rendered in the ground mesh (the wheels
##     are drawn on them). Mean-neutral.
##   * TEST DIP: one short smooth depression off the course, a test fixture (see
##     TEST_DIP_CENTRE), so a test can drive a wheel over a known crest.
##   * LICENCE RAMP: the hill start's hill (see RAMP_X), course content: a
##     straight ramp up, a level top, a straight ramp down, behind the start
##     gantry to the left. Part of the elevation (shown, stood on, ridden),
##     and unlike the swell it PULLS: the car feels its gradient as gravity
##     down the slope (ramp_gradient; ArcadeCar's road notes). Exactly 0
##     outside its footprint.
##
## The exported values are the knobs of one road; they default to the named
## constants, which is what main.tscn's road uses. All amplitudes 0 = a flat
## road. One profile resource is shared by the car and the pad in main.tscn.

# =============================================================================
#  ROAD TUNING
#  Heights and lengths are metres, slopes are rise over run (0.015 = 1.5 %).
# =============================================================================

## Same seed = same road, every run. Every noise octave derives its own seed
## from this one arithmetically (see _octave_seed).
const ROAD_PROFILE_SEED := 986

# --- Micro-bumps -------------------------------------------------------------

## Most the micro-bumps ever add or take away [m]: the octave amplitudes sum to
## this, so |micro_height| never exceeds it. Typical (RMS) is about a fifth.
const MICRO_AMPLITUDE := 0.012

## Lattice cell of each value-noise octave [m]; the bumps an octave makes are
## about two cells long (~4 m, ~1.6 m and ~0.6 m).
const MICRO_OCTAVE_CELLS: Array[float] = [2.0, 0.8, 0.3]

## Share of MICRO_AMPLITUDE each octave gets (sums to 1): long bumps are the
## tall ones.
const MICRO_OCTAVE_SHARES: Array[float] = [0.5, 0.3, 0.2]

# Every octave is centred (value noise is 0..1, minus 0.5), so the bumps have
# no DC part: measured mean 0.06 mm over the 200 m lane strip x = 0,
# z = 0 .. -200 in 5 cm steps (RMS 3.8 mm there), and under 0.25 mm over 1 km
# under either wheel track. The smoke test holds the strip to 0.5 mm.

# --- Elevation ---------------------------------------------------------------

## Main swell: amplitude [m] and wavelength [m]. Slope at most
## TAU * amplitude / wavelength = 0.79 %.
const SWELL_AMPLITUDE := 1.0
const SWELL_WAVELENGTH := 800.0

## Second, shorter swell on top, the one that makes crests a car can feel
## (vertical acceleration goes with speed^2 * amplitude / wavelength^2):
## amplitude [m] and wavelength [m]. Slope at most 0.57 %.
const SECOND_SWELL_AMPLITUDE := 0.18
const SECOND_SWELL_WAVELENGTH := 200.0

## Both swells run down the straight (along -Z) and cross zero at this z [m],
## where the lane leaves the flat of the slalom's buffer: the masks ramp up
## while the swell itself is still small, which keeps the ramps gentle.
const SWELL_ANCHOR_Z := -320.0

## Off the lane the swells' wave fronts lean: metres of phase per metre of x.
## Different for the two, so the ground away from the straight rolls in two
## directions instead of lying in straight furrows.
const SWELL_SKEW := 0.3
const SECOND_SWELL_SKEW := -0.5

## Within this far of the centre line the elevation depends on z only [m]
## (TestPad.LANE_HALF_WIDTH): a car going dead straight down the lane never
## sees a side slope. Beyond it x eases in, fully by LANE_BLEND_END [m].
const LANE_BAND_HALF_WIDTH := 6.0
const LANE_BLEND_END := 20.0

# With these numbers (and MASK_RAMP below) the measured steepest slope is
# 1.35 % along the lane (x = 0, z = 150 .. -1300, at z = -1120) and 1.39 %
# anywhere on the ground mesh (5 m lattice); the smoke test holds the lane to
# MAX_SLOPE. In the lane the first crest (+1.0 m) is at z = -520, the trough
# (-1.1 m) at z = -900.

## Slope the elevation stays under [rise over run].
const MAX_SLOPE := 0.015

# --- Flat zones --------------------------------------------------------------

# The elevation is exactly 0 within each zone's radius and ramps up to its full
# self over MASK_RAMP beyond it (smoothstep). Positions mirror TestPad's course
# constants; the micro-bumps are everywhere, flat zones included.

## Start line: centre (x, z) [m] and flat radius [m].
const START_ZONE_CENTRE := Vector2(0.0, -4.0)
const START_ZONE_RADIUS := 30.0

## Stop box: centre [m] and flat radius [m].
const STOP_ZONE_CENTRE := Vector2(0.0, -150.0)
const STOP_ZONE_RADIUS := 35.0

## Slalom line: x [m], first and last cone z [m], flat within this far of the
## line between them [m].
const SLALOM_ZONE_X := 20.0
const SLALOM_ZONE_FIRST_Z := -60.0
const SLALOM_ZONE_LAST_Z := -300.0
const SLALOM_ZONE_BUFFER := 25.0

## Skid pad: centre [m] and flat radius [m]: the disc (40 m), the ring of posts
## round it (46 m) and room to run wide.
const SKID_ZONE_CENTRE := Vector2(-70.0, -90.0)
const SKID_ZONE_RADIUS := 56.0

## Distance over which a flat zone ramps up to the full elevation [m]. Long,
## because the ramp's own slope is 1.5 * elevation / ramp: 140 m measured
## 1.63 % beside the skid pad, 180 m keeps the whole pad under MAX_SLOPE.
const MASK_RAMP := 180.0

## The elevation lives inside this box (x from -350 to 350, z from -1250 to
## 250) [m] and fades to exactly 0 over FAR_FIELD_RAMP [m] outside it: the far
## field is flat, so the pad's ground mesh only has to cover the box plus ramp.
const FAR_FIELD_MIN := Vector2(-350.0, -1250.0)
const FAR_FIELD_MAX := Vector2(350.0, 250.0)
const FAR_FIELD_RAMP := 250.0

# --- Test dip (a test fixture, not course content) ---------------------------

## One smooth depression off the course, right of the straight and past the
## slalom, so the crest test has a known crest to drive a wheel over: centre
## (x, z) [m], length along z [m] (one raised-cosine wave), width along x [m]
## (the same shape across) and depth [m]. Exactly 0 outside that footprint.
## Like the micro-bumps it is felt, not rendered; the pad paints a bar at
## either lip.
const TEST_DIP_CENTRE := Vector2(25.0, -450.0)
const TEST_DIP_LENGTH := 10.0
const TEST_DIP_WIDTH := 16.0
const TEST_DIP_DEPTH := 0.06

# --- Licence ramp (course content: the licence course's hill start) ----------

## The hill start's ramp, in the licence yard behind the start gantry (TestPad,
## "Licence course"): full height within RAMP_HALF_WIDTH of the axis x = RAMP_X,
## falling straight to 0 over RAMP_FLANK beyond; along z, 0 from RAMP_FOOT_Z
## back, rising straight to RAMP_HEIGHT at RAMP_CREST_Z, level to
## RAMP_TOP_END_Z and falling straight to 0 at RAMP_TAIL_Z (the ramp climbs
## towards -z, the way everything on the pad is driven: from the back of the
## yard towards the gantry). Every knee is on the pad's 5 m ground lattice
## (TestPad.GROUND_FINE_STEP) and the profile is straight between them, so the
## ground mesh shows the ramp exactly along its axis and across its top (see
## the mesh note in TestPad._build_licence_course). Grade RAMP_HEIGHT / rise
## length: 1.6 / 20 = 8 %, a real hill start's hill (the user's licence design,
## 2026-09-22 23:20: "HILL START on a ramp - handbrake + clutch bite,
## rolling-back tolerance"). Clear of every certified feature: the nearest
## certified point, the start line at z = -4, is 44 m from its tail.
const RAMP_X := -30.0  # Axis of the ramp [m].
const RAMP_HALF_WIDTH := 5.0  # Full height this far either side of the axis [m] ...
const RAMP_FLANK := 5.0  # ... then straight down to 0 over this much more [m].
const RAMP_FOOT_Z := 95.0  # The rise starts here [m] ...
const RAMP_CREST_Z := 75.0  # ... is at full height from here [m] ...
const RAMP_TOP_END_Z := 60.0  # ... to here [m] ...
const RAMP_TAIL_Z := 40.0  # ... and is back at 0 here [m].
const RAMP_HEIGHT := 1.6  # [m]: 8 % over the 20 m rise.

# =============================================================================
#  THIS ROAD
# =============================================================================

## Noise seed of this road.
@export var profile_seed := ROAD_PROFILE_SEED

## Bound of the micro-bumps [m]. 0 = none.
@export_range(0.0, 0.025, 0.001) var micro_amplitude := MICRO_AMPLITUDE

## The two swells [m]. 0 = level ground.
@export_range(0.0, 1.5, 0.01) var swell_amplitude := SWELL_AMPLITUDE
@export_range(120.0, 2000.0, 1.0) var swell_wavelength := SWELL_WAVELENGTH
@export_range(0.0, 1.5, 0.01) var second_swell_amplitude := SECOND_SWELL_AMPLITUDE
@export_range(120.0, 2000.0, 1.0) var second_swell_wavelength := SECOND_SWELL_WAVELENGTH

## Depth of the test dip [m]. 0 = none.
@export_range(0.0, 0.1, 0.005) var test_dip_depth := TEST_DIP_DEPTH

## Height of the licence ramp [m]. 0 = none (a flat yard).
@export_range(0.0, 3.0, 0.01) var ramp_height := RAMP_HEIGHT


## A road with every layer switched off: what a car without a road drives on.
static func flat() -> RoadProfile:
	var profile := RoadProfile.new()
	profile.micro_amplitude = 0.0
	profile.swell_amplitude = 0.0
	profile.second_swell_amplitude = 0.0
	profile.test_dip_depth = 0.0
	profile.ramp_height = 0.0
	return profile


## Height of the road at (x, z) [m], every layer: what a tyre rolls over.
func sample_height(x: float, z: float) -> float:
	return elevation_height(x, z) + micro_height(x, z) + test_dip_height(x, z)


## The elevation layer alone [m]: what the ground mesh shows and what
## everything placed on the pad stands on: the swells, and the licence ramp
## on top of them where it is.
# was the swells alone -> the licence ramp added where it is (exactly 0
# everywhere else: the swell's number is returned untouched there, every
# certified run's road the bit it was).
func elevation_height(x: float, z: float) -> float:
	var ramp := ramp_height_at(x, z)
	var mask := elevation_mask(x, z)
	if mask <= 0.0:
		return ramp
	# x as the swells see it: 0 across the lane band, eased in beyond it.
	var across := signf(x) * _eased_beyond_lane(absf(x))
	var along := SWELL_ANCHOR_Z - z
	var main := swell_amplitude * sin(TAU * (along + SWELL_SKEW * across) / swell_wavelength)
	var second := second_swell_amplitude * sin(TAU * (along + SECOND_SWELL_SKEW * across) / second_swell_wavelength)
	var swell := mask * (main + second)
	if ramp != 0.0:
		return swell + ramp
	return swell


## How much of the elevation (x, z) gets, 0..1: exactly 0 in the flat zones and
## in the far field, 1 on the open pad. A zone is measured from the nearest
## point of the stretch of x the lane band shares a height with (see
## _lane_span), which makes the mask, like the swells, a function of z only
## inside the band, and never shrinks a flat zone.
func elevation_mask(x: float, z: float) -> float:
	var point := Vector2(x, z)
	var outside := (point - point.clamp(FAR_FIELD_MIN, FAR_FIELD_MAX)).length()
	var mask := 1.0 - smoothstep(0.0, FAR_FIELD_RAMP, outside)
	if mask <= 0.0:
		return 0.0
	var span := _lane_span(x)
	mask *= _zone_mask(_distance_from_span(span, z, START_ZONE_CENTRE), START_ZONE_RADIUS)
	mask *= _zone_mask(_distance_from_span(span, z, STOP_ZONE_CENTRE), STOP_ZONE_RADIUS)
	mask *= _zone_mask(_distance_from_span(span, z, SKID_ZONE_CENTRE), SKID_ZONE_RADIUS)
	var on_slalom := Vector2(SLALOM_ZONE_X, clampf(z, SLALOM_ZONE_LAST_Z, SLALOM_ZONE_FIRST_Z))
	mask *= _zone_mask(_distance_from_span(span, z, on_slalom), SLALOM_ZONE_BUFFER)
	return mask


## The micro-bump layer alone [m], within +/- micro_amplitude.
func micro_height(x: float, z: float) -> float:
	if micro_amplitude <= 0.0:
		return 0.0
	var height := 0.0
	for octave in MICRO_OCTAVE_CELLS.size():
		var noise := _value_noise(x / MICRO_OCTAVE_CELLS[octave], z / MICRO_OCTAVE_CELLS[octave], _octave_seed(octave))
		# Centred: 0..1 becomes -1..1, no DC part.
		height += MICRO_OCTAVE_SHARES[octave] * (noise - 0.5) * 2.0
	return micro_amplitude * height


## The test dip alone [m]: 0 .. -test_dip_depth, 0 outside its footprint.
func test_dip_height(x: float, z: float) -> float:
	var u := (x - TEST_DIP_CENTRE.x) / (TEST_DIP_WIDTH * 0.5)
	var v := (z - TEST_DIP_CENTRE.y) / (TEST_DIP_LENGTH * 0.5)
	if absf(u) >= 1.0 or absf(v) >= 1.0:
		return 0.0
	return -test_dip_depth * 0.25 * (1.0 + cos(PI * u)) * (1.0 + cos(PI * v))


## The licence ramp alone [m]: 0 .. ramp_height, exactly 0 outside its
## footprint (see RAMP_X). Straight across its top and along its rises.
func ramp_height_at(x: float, z: float) -> float:
	if ramp_height <= 0.0:
		return 0.0
	var across := _ramp_across(x)
	if across <= 0.0:
		return 0.0
	var along := _ramp_along(z)
	if along <= 0.0:
		return 0.0
	return ramp_height * across * along


## The slope of the licence ramp at (x, z): its rise per metre along x and
## along z [-] (RAMP_HEIGHT / 20 m: -0.08 on the rise, which climbs towards
## -z, +0.08 on the fall, 0 on the top). What gravity pulls the car down
## (ArcadeCar). Exactly Vector2.ZERO outside the footprint and on the level
## top; on a knee the steeper side's slope.
func ramp_gradient(x: float, z: float) -> Vector2:
	if ramp_height <= 0.0:
		return Vector2.ZERO
	var across := _ramp_across(x)
	var along := _ramp_along(z)
	if across <= 0.0 or along <= 0.0:
		return Vector2.ZERO
	# The flanks fall away from the axis on either side ...
	var d_across := 0.0
	if absf(x - RAMP_X) > RAMP_HALF_WIDTH:
		d_across = -signf(x - RAMP_X) / RAMP_FLANK
	# ... the rise climbs towards -z, the fall drops towards -z.
	var d_along := 0.0
	if z > RAMP_CREST_Z:
		d_along = -1.0 / (RAMP_FOOT_Z - RAMP_CREST_Z)
	elif z < RAMP_TOP_END_Z:
		d_along = 1.0 / (RAMP_TOP_END_Z - RAMP_TAIL_Z)
	return Vector2(ramp_height * d_across * along, ramp_height * across * d_along)


## The ramp's share across x, 0..1: 1 on the top, straight down the flanks.
func _ramp_across(x: float) -> float:
	var off := absf(x - RAMP_X) - RAMP_HALF_WIDTH
	if off <= 0.0:
		return 1.0
	if off >= RAMP_FLANK:
		return 0.0
	return 1.0 - off / RAMP_FLANK


## The ramp's share along z, 0..1: straight up the rise (towards -z), 1 on
## the top, straight down the fall.
func _ramp_along(z: float) -> float:
	if z >= RAMP_FOOT_Z or z <= RAMP_TAIL_Z:
		return 0.0
	if z > RAMP_CREST_Z:
		return (RAMP_FOOT_Z - z) / (RAMP_FOOT_Z - RAMP_CREST_Z)
	if z >= RAMP_TOP_END_Z:
		return 1.0
	return (z - RAMP_TAIL_Z) / (RAMP_TOP_END_Z - RAMP_TAIL_Z)


## Steepest slope of the elevation at (x, z) [rise over run], by central
## differences over `span` metres.
func elevation_slope(x: float, z: float, span := 1.0) -> float:
	var slope_x := (elevation_height(x + span, z) - elevation_height(x - span, z)) / (2.0 * span)
	var slope_z := (elevation_height(x, z + span) - elevation_height(x, z - span)) / (2.0 * span)
	return Vector2(slope_x, slope_z).length()


## 0 within `radius` of a flat zone, 1 from MASK_RAMP further out.
func _zone_mask(distance: float, radius: float) -> float:
	return smoothstep(radius, radius + MASK_RAMP, distance)


## Distance from the centre line as the swells count it [m]: 0 up to the edge
## of the lane band, then picking up smoothly (the integral of a smoothstep, so
## it never grows faster than x itself), one for one from LANE_BLEND_END.
func _eased_beyond_lane(distance: float) -> float:
	var blend := LANE_BLEND_END - LANE_BAND_HALF_WIDTH
	var s := clampf((distance - LANE_BAND_HALF_WIDTH) / blend, 0.0, 1.0)
	return blend * (s * s * s - 0.5 * s * s * s * s) + maxf(distance - LANE_BLEND_END, 0.0)


## The stretch of x (from .x to .y) that counts as "here" for the flat zones:
## the whole lane band for a point inside it, shrinking to the point itself by
## LANE_BLEND_END. It always contains x.
func _lane_span(x: float) -> Vector2:
	var own := smoothstep(LANE_BAND_HALF_WIDTH, LANE_BLEND_END, absf(x))
	return Vector2(
		lerpf(minf(x, -LANE_BAND_HALF_WIDTH), x, own),
		lerpf(maxf(x, LANE_BAND_HALF_WIDTH), x, own)
	)


## Distance from `centre` (x, z) to the nearest point of `span` at this z [m].
func _distance_from_span(span: Vector2, z: float, centre: Vector2) -> float:
	var dx := maxf(maxf(span.x - centre.x, centre.x - span.y), 0.0)
	return Vector2(dx, z - centre.y).length()


## Seed of one micro-bump octave, off the road's seed.
func _octave_seed(octave: int) -> int:
	return profile_seed + 101 * (octave + 1)


## Value noise, 0..1: hashed lattice corners, smoothstep-interpolated (the
## pattern of AsphaltTexture, unwrapped: the road does not tile).
static func _value_noise(u: float, v: float, noise_seed: int) -> float:
	var cell_x := floori(u)
	var cell_y := floori(v)
	var tx := smoothstep(0.0, 1.0, u - cell_x)
	var ty := smoothstep(0.0, 1.0, v - cell_y)
	var top := lerpf(_hash(cell_x, cell_y, noise_seed), _hash(cell_x + 1, cell_y, noise_seed), tx)
	var bottom := lerpf(_hash(cell_x, cell_y + 1, noise_seed), _hash(cell_x + 1, cell_y + 1, noise_seed), tx)
	return lerpf(top, bottom, ty)


## Integer hash of a lattice coordinate, 0..1. Negative coordinates are fine.
static func _hash(x: int, y: int, hash_seed: int) -> float:
	var h := (x * 374761393 + y * 668265263 + hash_seed * 1442695041) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967295.0
