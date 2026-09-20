class_name RoadProfile
extends Resource
## The road's height field: how high the tarmac is at (x, z) [m]. One pure,
## seeded function, so the car (which feels it), the pad (which renders it and
## stands things on it) and the tests (which check both) all read the same
## road. Nothing in the sampling path draws random numbers or keeps state: same
## (x, z), same height, every run.
##
## Three layers:
##   * ELEVATION: a gentle swell a few hundred metres long, the only layer the
##     ground mesh shows and the car's body follows. Zero round every
##     certification feature (start line, stop box, slalom line, skid pad) and
##     far from the course; inside the straight's lane it depends on z only, so
##     the lane never leans sideways.
##   * MICRO-BUMPS: centimetre-scale value noise, metres long. Felt in the
##     wheel loads, not rendered and not in the body height. Mean-neutral.
##   * TEST DIP: one short smooth depression off the course, a test fixture (see
##     TEST_DIP_CENTRE), so a test can drive a wheel over a known crest.
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


## A road with every layer switched off: what a car without a road drives on.
static func flat() -> RoadProfile:
	var profile := RoadProfile.new()
	profile.micro_amplitude = 0.0
	profile.swell_amplitude = 0.0
	profile.second_swell_amplitude = 0.0
	profile.test_dip_depth = 0.0
	return profile


## Height of the road at (x, z) [m], every layer: what a tyre rolls over.
func sample_height(x: float, z: float) -> float:
	return elevation_height(x, z) + micro_height(x, z) + test_dip_height(x, z)


## The elevation layer alone [m]: what the ground mesh shows, what the car's
## body follows and what everything placed on the pad stands on.
func elevation_height(x: float, z: float) -> float:
	var mask := elevation_mask(x, z)
	if mask <= 0.0:
		return 0.0
	# x as the swells see it: 0 across the lane band, eased in beyond it.
	var across := signf(x) * _eased_beyond_lane(absf(x))
	var along := SWELL_ANCHOR_Z - z
	var main := swell_amplitude * sin(TAU * (along + SWELL_SKEW * across) / swell_wavelength)
	var second := second_swell_amplitude * sin(TAU * (along + SECOND_SWELL_SKEW * across) / second_swell_wavelength)
	return mask * (main + second)


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
