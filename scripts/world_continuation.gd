class_name WorldContinuation
extends RefCounted
## The world beyond the drape (OFFROAD-1; decisions.org DAF72FC6, OPEN-WORLD
## CONTINUITY: "everything reachable, no walls, the world continues
## procedurally beyond the OSM data - deterministic hash randomness via
## hash_unit(), never RNG"). The drape's coverage box (x 0..7000, z
## -6000..0; WorldRoadProfile.covers) is where the DEM's heights are; the
## frozen profile answers exactly 0 outside it, so the world ended in a
## flat edge the fog half-hid. This is the height field OUTSIDE the box:
## static, stateless, no RNG, no wall clock - the same (x, z) gives the
## same height on every machine and every run, so the RingProfile wrapper
## (what the car reads) and the terrain skirt (what the eye sees) call the
## ONE function, height(), and agree to the bit.
##
## THE FIELD, for a point p outside the box at distance d from it (the
## Euclidean distance to the box: 0 on its edge, the gap to the nearest
## edge or corner beyond):
##   * the EDGE VALUE: the real field's height at q, the point of the box
##     nearest p (the profile's elevation_height there: the lattice, or a
##     road platform where a covered road reaches the edge), so at d = 0
##     the continuation IS the real field - continuous at the edge;
##   * the RELIEF: fBm value noise, OCTAVES octaves of smoothstep-
##     interpolated lattice values in [-1, 1] (each lattice corner
##     TerrainBuilder.hash_unit(i, "continuation:k", j) on the corner's
##     quantised cell coordinates and the octave's salt), each octave a
##     wavelength OCTAVE_WAVELENGTHS_M[k] and an amplitude
##     OCTAVE_AMPLITUDES_M[k] - the amplitudes FITTED to the drape lattice's
##     MEASURED relief (the structure function, the rms height difference
##     at lag L over the 701 x 601 lattice, height std 67.4 m over the
##     whole: 90.7 m at 2 048 m, 58.8 at 1 024, 40.0 at 512, 26.9 at 256,
##     16.2 at 128, 9.1 at 64, 3.3 at 20; .scratch measurement of
##     2026-09-27 on scenes/eifel_ring.tscn's terrain) so the invented
##     hills have the Eifel's slopes: the model's 88.8 / 63.7 / 41.0 / 26.3 /
##     16.3 / 9.0 / 2.9 m at the same lags (the fit run on a python replica
##     of hash_unit and this noise, .scratch/offroad-1/fit_noise.py,
##     2 500 random pairs a lag along both axes);
##   * the BLEND: the relief is weighed in by smoothstep(d /
##     CONTINUATION_BLEND_M) from 0 at the edge to 1 at the band's end, so
##     within the band the field is the edge value plus a fraction of the
##     relief: |h(just outside) - h(just inside)| is the lattice's own slope
##     over the gap, under EDGE_TOLERANCE_M at EDGE_EPSILON_M;
##   * the MARGIN: the continuation reaches CONTINUATION_MARGIN_M (6 km:
##     twice the haze's sky-coloured distance, SkySet.SKY_COLOURED_FULL_M
##     3 000 m; NOT infinite - the honest limit) and over its last
##     CONTINUATION_FADE_M the whole is faded to 0 (smoothstep), flat 0
##     beyond: the fog hides the fade and the flat, the field never steps.
## Inside the box height() answers the profile's own value (the edge value
## at d = 0 with no relief): a caller may ask anywhere.
##
## THE HASH COST: hash_unit() formats and hashes a string per corner, a few
## microseconds; a sample costs 4 corners x OCTAVES. The car's reads
## outside the box are a handful a tick (fine); the terrain skirt's
## 120 000 vertices would not be, so height() takes an optional corner
## cache (a Dictionary the caller owns; none passed = a throwaway one):
## the same corner hashed once per build. The cache changes nothing but
## the time.

## How far beyond the box the continuation reaches [m], the blend band
## over which its relief is weighed in from the edge value [m], and the
## band at the margin's end over which the whole fades to flat 0 [m].
const CONTINUATION_MARGIN_M := 6000.0
const CONTINUATION_BLEND_M := 800.0
const CONTINUATION_FADE_M := 1000.0

## The octaves (see the header): wavelengths [m] and amplitudes [m], the
## amplitudes fitted to the lattice's measured structure function.
const OCTAVES := 5
const OCTAVE_WAVELENGTHS_M: Array[float] = [2048.0, 1024.0, 512.0, 256.0, 128.0]
const OCTAVE_AMPLITUDES_M: Array[float] = [175.0, 38.0, 31.0, 27.0, 15.5]
## The salt every corner hash carries (with the octave's index).
const SALT := "continuation"

## The continuity contract at the edge: sampled EDGE_EPSILON_M either side
## of the box, the heights differ by under EDGE_TOLERANCE_M (the lattice's
## slope over 2 cm: under 1 cm at 45 %).
const EDGE_EPSILON_M := 0.01
const EDGE_TOLERANCE_M := 0.01


## The continuation's height at (x, z) [m] over the real field `inner`:
## the header's field. `cache`: an optional corner cache the caller owns.
static func height(inner: WorldRoadProfile, x: float, z: float, cache: Dictionary = {}) -> float:
	var box := inner.coverage()
	var qx := clampf(x, box.position.x, box.end.x)
	var qz := clampf(z, box.position.y, box.end.y)
	var dx := x - qx
	var dz := z - qz
	var d := sqrt(dx * dx + dz * dz)
	if d >= CONTINUATION_MARGIN_M:
		return 0.0
	var edge := edge_value(inner, qx, qz, cache)
	if d <= 0.0:
		return edge
	var blend := smoothstep(0.0, 1.0, d / CONTINUATION_BLEND_M)
	var fade := 1.0 - smoothstep(0.0, 1.0, (d - (CONTINUATION_MARGIN_M - CONTINUATION_FADE_M)) / CONTINUATION_FADE_M)
	return (edge + blend * relief(x, z, cache)) * fade


## The real field's height at a point of the box's edge [m] (the
## profile's elevation_height: the lattice, or a platform where a covered
## road reaches the edge), through the cache (keyed on the point).
static func edge_value(inner: WorldRoadProfile, qx: float, qz: float, cache: Dictionary = {}) -> float:
	var key := Vector2(qx, qz)
	if cache.has(key):
		return cache[key]
	var edge := inner.elevation_height(qx, qz)
	cache[key] = edge
	return edge


## The Euclidean distance from (x, z) to the box [m]: 0 inside.
static func distance_to_box(inner: WorldRoadProfile, x: float, z: float) -> float:
	var box := inner.coverage()
	var dx := x - clampf(x, box.position.x, box.end.x)
	var dz := z - clampf(z, box.position.y, box.end.y)
	return sqrt(dx * dx + dz * dz)


## The relief alone at (x, z) [m]: the octaves summed, zero-mean, within
## +/- the amplitudes' sum.
static func relief(x: float, z: float, cache: Dictionary = {}) -> float:
	var sum := 0.0
	for k: int in OCTAVES:
		sum += OCTAVE_AMPLITUDES_M[k] * value_noise(x, z, OCTAVE_WAVELENGTHS_M[k], "%s:%d" % [SALT, k], cache)
	return sum


## One octave of value noise in [-1, 1]: the four corners of the cell of
## `wavelength` holding (x, z), smoothstep-interpolated; `purpose` the
## salt of the corners' hashes (an octave's, a bump octave's).
static func value_noise(x: float, z: float, wavelength: float, purpose: String, cache: Dictionary = {}) -> float:
	var u := x / wavelength
	var v := z / wavelength
	var i := floori(u)
	var j := floori(v)
	var tu := smoothstep(0.0, 1.0, u - float(i))
	var tv := smoothstep(0.0, 1.0, v - float(j))
	var a := corner(i, j, purpose, cache)
	var b := corner(i + 1, j, purpose, cache)
	var c := corner(i, j + 1, purpose, cache)
	var e := corner(i + 1, j + 1, purpose, cache)
	var top := a + (b - a) * tu
	var bottom := c + (e - c) * tu
	return (top + (bottom - top) * tv) * 2.0 - 1.0


## A corner's unit in [0, 1): the region's hash of the quantised
## coordinates and the purpose (never an RNG); through the cache (a
## throwaway one when the caller passed none), keyed on the same text.
## THE MIX: hash_unit's text ends in its index field, and FNV-1a's last
## byte only reaches the hash through one multiply - two cells a step
## apart along the last field hashed exactly one prime apart (measured:
## 1226099128 and 1209321509 for j -2948 / -2947, units 0.2855 / 0.2816),
## so a noise keyed on (i, purpose, j) barely varied along z. The cell's
## two indices are folded into one spatial mix (the classic 73856093 /
## 19349663 fold, many digits changing between neighbours) that stands in
## BOTH the id and the index fields, with the purpose and the raw indices
## in the text as well: neighbours differ in every field.
static func corner(i: int, j: int, purpose: String, cache: Dictionary = {}) -> float:
	var key := "%s:%d:%d" % [purpose, i, j]
	if cache.has(key):
		return cache[key]
	var mix := ((i * 73856093) ^ (j * 19349663)) & 0x7FFFFFFF
	var unit := TerrainBuilder.hash_unit(mix, key, mix)
	cache[key] = unit
	return unit


## One line: the constants.
static func describe() -> String:
	return "continuation to %.0f m (blend %.0f m, fade %.0f m), %d octaves %s m at %s m" % [CONTINUATION_MARGIN_M, CONTINUATION_BLEND_M, CONTINUATION_FADE_M, OCTAVES, OCTAVE_WAVELENGTHS_M, OCTAVE_AMPLITUDES_M]
