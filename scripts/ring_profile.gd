class_name RingProfile
extends WorldRoadProfile
## The Ring's profile as the car reads it (OFFROAD-1): a composition
## wrapper over the real WorldRoadProfile (`inner`, the one
## RoadBuilder built from the drape and handed the car) that answers
## EVERY public member of the frozen class verbatim through the inner -
## the same object, the same bits - and overrides the three height reads
## (sample_height, elevation_height, ramp_gradient) in exactly two places
## the inner does not reach:
##   * OFF-ROAD INSIDE THE COVERAGE - the micro-profile (plan.org
##     ECD301C4, SURFACES & GRIP DEPTH: "grip varies by surface type and
##     condition, suspension/tire feel"; the driver's "like going through
##     water" off the road): the inner's lattice height plus cm-scale
##     bumps, deterministic value noise (WorldContinuation.value_noise on
##     hash_unit, never RNG) at BUMP_WAVELENGTHS_M with BUMP_SHARES, the
##     amplitude the ground surface's `bump` from
##     data/regions/eifel_ring/surfaces.json (TerrainBuilder.ground_surface_at:
##     forest floor, field stubble, grass), weighed in from ZERO at the
##     widest road's reach (the widest paved half width plus
##     WorldRoadProfile.BLEND_BAND_M) over BUMP_FADE_M of the terrain's
##     road distance field
##     (TerrainBuilder.road_distance_at, the lattice's exact Euclidean
##     distance transform bilinear between nodes: within half a lattice
##     step of the true distance, so the fade may stand a fraction up at
##     the reach edge - a step under 0.4 of the amplitude, millimetres).
##   * OUTSIDE THE COVERAGE - the continuation (WorldContinuation.height:
##     decisions.org DAF72FC6, no walls, the world continues), where the
##     inner answers a flat 0.
## ON A ROAD OR IN ITS BLEND BAND the reads PASS THROUGH THE INNER BIT-
## EXACT: the wrapper asks inner.describe(x, z) once - the one public read
## that names the road answering a point - and where a road answers it
## returns the describe's own `height` (the inner's elevation_height
## computed inside that call, the same bits sample_height returns) and
## the inner's own ramp_gradient. The certified ring drives and the
## bubble test's end-position-to-the-bit pins are on-road drives: they
## read the inner's arithmetic and nothing else (tests/offroad_test.gd
## holds sample_height equal to the inner's to the bit along the drive-
## start straight, and every delegated member equal on a grid).
##
## THE SEAM, honestly: the terrain MESH is built from the inner (the
## Terrain and Forest nodes consumed the original profile in their
## _ready; Surfaces swaps road.profile and car.road_profile for this
## wrapper at its first physics tick, after every _ready), so the mesh
## does not show the bumps: they are the car's read only, through its
## existing per-wheel road_profile.sample_height path (car.gd
## _road_height_under_wheel, frozen), which is where the suspension
## excitation comes from; RoadBuilder's floor follower reads the wrapper
## too (cm-scale, coherent with the wheels). The road mesh is the same
## either way: its vertices are on-road reads. Off-road the car stands
## on a field the eye sees a centimetre or two off; on-road, nothing
## differs.
##
## Pure, as the frozen header rules: same (x, z), same height, every
## run; no RNG, no wall clock, no mutable state in the sampling path (the
## bump's corner hashes go through a throwaway cache per call).

## The bump octaves [m] and their shares of the amplitude (the pad's own
## micro-profile is 2 / 0.8 / 0.3 cells at 1.2 cm; the field's are
## coarser: a tyre's 0.3 m contact patch averages anything finer).
const BUMP_WAVELENGTHS_M: Array[float] = [2.5, 0.9]
const BUMP_SHARES: Array[float] = [0.65, 0.35]
## The salt of the bump corners (WorldContinuation's is its own).
const BUMP_SALT := "bump"
## The bumps are weighed in over this beyond the road's reach [m].
const BUMP_FADE_M := 20.0

## The real profile: everything delegates to it.
var inner: WorldRoadProfile
## The terrain (the ground classification and the road distance field);
## null = no bumps anywhere (the inner's field off-road).
var terrain: TerrainBuilder
## Bump amplitude [m] by ground surface name (Surfaces reads the table
## and fills this); a surface not here bumps 0.
var bump_by_surface: Dictionary = {}


## The wrapper over `real`, with the terrain and the table's bumps.
static func over(real: WorldRoadProfile, terrain_node: TerrainBuilder, bumps: Dictionary) -> RingProfile:
	var wrapper := RingProfile.new()
	wrapper.inner = real
	wrapper.terrain = terrain_node
	wrapper.bump_by_surface = bumps
	return wrapper


# =============================================================================
#  THE THREE OVERRIDDEN READS
# =============================================================================

## Height at (x, z) [m]: the inner's on a road or in its blend band (bit-
## exact), the inner's plus the bumps off-road, the continuation outside.
func sample_height(x: float, z: float) -> float:
	var found := inner.describe(x, z)
	if not found.covered:
		return WorldContinuation.height(inner, x, z)
	if found.road != "":
		return found.height
	return found.height + bump_height(x, z)


## The same field (the inner's elevation_height is its sample_height).
func elevation_height(x: float, z: float) -> float:
	return sample_height(x, z)


## The surface gradient: the inner's where a road answers (bit-exact),
## central differences of this field over GRADIENT_SPAN_M elsewhere (the
## continuation makes the field continuous across the box edge, so no
## tap is zeroed there as the inner's are).
func ramp_gradient(x: float, z: float) -> Vector2:
	var found := inner.describe(x, z)
	if found.covered and found.road != "":
		return inner.ramp_gradient(x, z)
	var span := GRADIENT_SPAN_M
	var slope_x := (sample_height(x + span, z) - sample_height(x - span, z)) / (2.0 * span)
	var slope_z := (sample_height(x, z + span) - sample_height(x, z - span)) / (2.0 * span)
	return Vector2(slope_x, slope_z)


## The bump component at an off-road point [m]: the ground surface's
## amplitude, faded in from the road's reach, times the noise.
func bump_height(x: float, z: float) -> float:
	if terrain == null:
		return 0.0
	var amplitude: float = bump_by_surface.get(terrain.ground_surface_at(x, z), 0.0)
	if amplitude <= 0.0:
		return 0.0
	var weight := bump_weight(x, z)
	if weight <= 0.0:
		return 0.0
	return amplitude * weight * bump_noise(x, z)


## How much of the bump a point gets, 0..1: 0 within the widest road's
## reach (TerrainBuilder.widest_reach: the widest paved half width plus
## the blend band, so no road's band is ever bumped), smoothstep over
## BUMP_FADE_M beyond it, on the terrain's distance field; and 0 at the
## coverage box's edge, smoothstep over the same BUMP_FADE_M inside it
## (the continuation carries no bumps: the field stays continuous there).
func bump_weight(x: float, z: float) -> float:
	var box := inner.coverage()
	var inside := minf(minf(x - box.position.x, box.end.x - x), minf(z - box.position.y, box.end.y - z))
	var edge := smoothstep(0.0, 1.0, inside / BUMP_FADE_M)
	var distance := terrain.road_distance_at(x, z)
	if not is_finite(distance):
		return edge
	var reach: float = terrain.widest_reach
	return edge * smoothstep(0.0, 1.0, (distance - reach) / BUMP_FADE_M)


## The unit noise in [-1, 1]: the octaves' shares.
static func bump_noise(x: float, z: float) -> float:
	var cache := {}
	var sum := 0.0
	for k: int in BUMP_WAVELENGTHS_M.size():
		sum += BUMP_SHARES[k] * WorldContinuation.value_noise(x, z, BUMP_WAVELENGTHS_M[k], "%s:%d" % [BUMP_SALT, k], cache)
	return sum


# =============================================================================
#  EVERY OTHER PUBLIC MEMBER: THE INNER'S, VERBATIM
# =============================================================================

func elevation_mask(x: float, z: float) -> float:
	return inner.elevation_mask(x, z)


func covers(x: float, z: float) -> bool:
	return inner.covers(x, z)


func terrain_height(x: float, z: float) -> float:
	return inner.terrain_height(x, z)


func coverage() -> Rect2:
	return inner.coverage()


func road_count() -> int:
	return inner.road_count()


func describe(x: float, z: float) -> Dictionary:
	return inner.describe(x, z)


func point_along(id: String, chainage: float) -> Variant:
	return inner.point_along(id, chainage)


func centre_height(road: Road, chainage: float) -> float:
	return inner.centre_height(road, chainage)


## RoadProfile's own layers (zeroed in the world; the inner answers them).
func micro_height(x: float, z: float) -> float:
	return inner.micro_height(x, z)


func test_dip_height(x: float, z: float) -> float:
	return inner.test_dip_height(x, z)


func ramp_height_at(x: float, z: float) -> float:
	return inner.ramp_height_at(x, z)


func elevation_slope(x: float, z: float, span := 1.0) -> float:
	return inner.elevation_slope(x, z, span)


## One line: what wraps what.
func describe_wrapper() -> String:
	return "RingProfile over %d roads, bumps %s, fade %.0f m beyond the reach, %s" % [inner.road_count(), bump_by_surface, BUMP_FADE_M, WorldContinuation.describe()]
