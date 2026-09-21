extends SceneTree
## Headless smoke test for the main scene. Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --path . --script res://tests/smoke_test.gd
##
## Loads the main scene, checks the key nodes exist, then drives the car with
## simulated input and checks it accelerates, steers, brakes, holds, reverses,
## slides under the handbrake, turns in less on the brakes, shifts gears and
## moves load between the axles, that its drivetrain is a chain of states (free
## revs and the limiter in neutral, a dropped clutch spinning the wheels, the
## launch on a slipping clutch, engine braking by gear, the engine on its own
## through a gear change, wheels drawn at their real speed), that it goes by
## its tyre forces (power against
## coasting in a corner, the path bending only as fast as the tyres can bend
## it, rear / front / all-wheel drive, brake bias, downforce, the low-speed
## blend), and checks the pad's ground texture, course queries and
## drive-through cones, and the road: the profile is pure, mean-neutral, gentle
## and level where it has to be, the wheels feel it (bumps at speed, the test
## dip's crest), and what the pad places stands on it. Last come the slides
## nobody is driving (keys released they come back into line, scrub to a stop,
## or are held back by the engine rolling backwards), the handling tests' run
## clock (a start line on every test; the clock stands until the car is over
## it, starts once and does not start anew) and the handling tests' 180 driven
## to the right, and the driver: elastic pedals (a tap is a partial press, a
## held key gets to the floor, a lift comes back to nothing), driver profiles,
## the car driven through set_driver_input with no key down, and the HUD's
## pedal bars. Then what the engine takes and gives and what the car weighs:
## the tank (burnt by the work done, a little idling, a lot flat out, nothing on
## the overrun; a dry tank stops the engine, a reset fills it), the fuel bar,
## the one mass of the car (total_mass(): fuel and payload in it, a payload
## slows the car and rides level, a test's payload_kg is loaded at its start),
## the exhaust as data (three firings a turn, a flow that follows the throttle)
## and the creep (the brake let go at a standstill, automatic only, a crawl
## under the standstill speed). Then the driver's controls: the TCS and ABS
## switches (a launch with the clutch let in for good and the wheels spinning, a
## stop on locked front wheels that is longer and does not steer), the clutch
## pedal (manual only; held, the car goes nowhere, let go on a revving engine it
## is a dump, let go on an idling one a stall), the stall and the starter (a
## stopped engine burns and fires nothing, a stalled car does not creep, the
## starter catches it, a dry tank never does), reverse under neutral on the
## shift keys, the automatic's comfort and sport programs, and the telemetry's
## two pedal fields reading the pedals. Then the telemetry recorder: a real mission
## driven with it switched on, its JSON-lines file read back and checked line
## by line (see _check_telemetry - it writes to a fixed tmp path, never to
## user://, and asserts nothing that comes off the wall clock). Last come the
## tyre marks: none while the tyres grip, trails under a handbrake slide, a
## launch without TCS and a stop on locked wheels, lying on the ground along the
## way the car went; the pool bounded and the oldest laid anew, the fade and
## the places it frees, the same slide leaving the same marks to the bit, a
## reset clearing them, and the car driving the same with the marks switched
## off; and their severity: cornering on tyres that grip lays nothing, a slow
## scrub a shade, the handbrake black, the same shades every time.
## Then the stability switch: a key, a lamp, the assist gone and a flick of the
## handbrake showing it, the low-speed blend not its to take.
## Then the starter's crank cycle: a tap starts a stalled engine, a dry tank is
## cranked and never catches.
## Then the wheels drawn at speed: the real step less a half turn, the
## wagon-wheel effect.
## Exits 0 on success, 1 on any failed check. Later phases extend this file.

const MAIN_SCENE := "res://scenes/main.tscn"

## How long the handbrake corner holds the handbrake [physics frames], 0.4 s:
## a tap that kicks the tail out and lets the car catch it again. Was 60 (1 s):
## with tyre forces and yaw inertia, a full second at full lock from 60 km/h
## is a committed handbrake turn that ends up facing backwards (what SPIN_180
## is for), not a slide to recover from.
const HANDBRAKE_TAP_FRAMES := 24

## How long after the stop the held-accelerate exit from reverse gets to be
## under way [physics frames], 0.75 s: FORWARD_ENGAGE_GRACE (12 frames) plus
## margin to pick up speed.
const FORWARD_ENGAGE_FRAMES := 45

## Power against coasting through the same corner: least difference in heading
## gained over POWER_CORNER_FRAMES [rad], ~6 degrees. Measured: ~0.35 rad (the
## powered car runs wider: it gains speed, and load moves off the steered
## axle). A car whose throttle does not reach its tyres shows 0.
const POWER_COAST_MIN_YAW_DIFFERENCE := 0.1

## ... and least distance between where the two runs end up [m]. Measured: ~9.
const POWER_COAST_MIN_POSITION_DIFFERENCE := 2.0

## Speed _get_up_to_speed hands the car over at [m/s], ~60 km/h: what 3 s flat
## out from rest used to come to.
const GET_UP_TO_SPEED := 16.5

## Speed the 2nd gear corners start from [m/s], ~65 km/h, and the 1st gear
## ones, ~32 km/h.
const CORNER_ENTRY_SPEED := 18.0
const LOW_GEAR_ENTRY_SPEED := 9.0

## Share of full lock (0..1) the test driver holds in the force-model corners
## at speed (braked turn-in, power / coast, driven wheels, turn-in trace): ~9.6
## degrees of wheel, a little past the front tyres' peak slip angle, where the
## tyres work and throttle, brake and driven wheels show in the line.
## Was 1.0, the bare key -> 0.35 - with raw steering the key is the full 27.5
## degrees at any speed, the fronts scrub far past their peak and the car just
## pushes wide whatever the throttle, brakes or driven wheels do (that push is
## the honest car, see _check_raw_steering). Slip-sensitive steering used to
## ease the lock to ~1.2 peak slip angles by itself; the driver does it now.
const CORNER_STEER := 0.35

## Raw steering checks: speeds the identity is checked at [m/s], ~30 and ~60
## km/h (parking pace is covered by _check_low_speed_blend) ...
const RAW_STEER_SPEEDS: Array[float] = [8.5, 16.7]

## ... how long a key is held before full lock is read off the wheels [physics
## frames], 0.4 s: the hands take 0.35 s (21 ticks) from centre to lock
## (STEERING_HAND_SPEED) ...
# was 24 as twice the 0.2 s STEER_RESPONSE took -> still 24, now 3 ticks more
# than the 900-degree wheel needs at 1300 degrees per second. (30 was tried
# with RAW_STEER_SWAP_FRAMES 54: 1.4 s of held handbrake in all, and the
# lock-to-lock check's car had come to rest, 1 km/h, before the wheel was
# across: no slide left to check it in.)
const RAW_STEER_HOLD_FRAMES := 24

## ... and how long from one lock to the other [physics frames], 0.8 s: the
## hands take 0.70 s of it.
# was 36 (0.6 s, the steering took 0.4 s of it) -> 48 - 900 degrees at 1300
# degrees per second are 42 ticks.
const RAW_STEER_SWAP_FRAMES := 48

## Lock to lock the steering wheel has to take this long [s]: 900 degrees at a
## driver's hand speed. Measured: 0.70 s (42 ticks; 900 / 1300 = 0.692).
const LOCK_TO_LOCK_MIN_TIME := 0.6
const LOCK_TO_LOCK_MAX_TIME := 0.8

## ... and the least time the held-lock slide must really be a slide (rear slip
## angle past SLIDE_CATCH_ANGLE, handbrake let go) for its check to count
## [physics frames], 0.25 s.
const RAW_STEER_MIN_SLIDE_FRAMES := 15

## How fast the test driver rolls the steering on in the turn-in trace [1/s]:
## 0 to CORNER_STEER in 0.2 s (the hands follow: STEERING_HAND_SPEED is 2.9
## locks a second). Was the bare key, which STEER_RESPONSE ramped
## over an eased lock (0.011 rad of wheel on the first tick) -> rolled on by
## the driver: raw, the key alone is 0.04 rad of wheel on the first tick.
const TURN_IN_ROLL_ON_RATE := 1.75

## How long the power / coast corners last [physics frames], 2 s; the 1st gear
## ones 1 s, so the automatic stays in 1st throughout.
const POWER_CORNER_FRAMES := 120
const LOW_GEAR_CORNER_FRAMES := 60

## Turn-in: sideways acceleration on the first tick of steering must stay under
## this share of the peak it builds to ...
const TURN_IN_FIRST_TICK_SHARE := 0.1

## ... and take at least this many ticks to get to half of it (0.1 s): the
## steering ramps, the tyres build slip, the mass answers. A body rotated by
## fiat shows its full sideways acceleration on the first tick.
const TURN_IN_MIN_BUILD_TICKS := 6

## No tick may accelerate the car harder than the tyres and the air can push
## [g]: TYRE_MU x the better axle's grip factor plus downforce and drag come
## to ~1.1 at these speeds.
const MAX_PLAUSIBLE_ACCEL_G := 1.2

## Parking pace for the low-speed blend checks [m/s], inside the blend
## (LOW_SPEED_BLEND_START .. LOW_SPEED_BLEND_END).
const CRAWL_SPEED := 2.0

## Downforce check: how long the carried load is averaged [physics frames],
## 0.5 s, and how close the average has to come to weight + downforce [N]. Was
## 1.0 N on the instantaneous loads - pre-2G flat-ground exactness; the road now
## adds a mean-neutral ripple to the four wheel loads (up to ~1300 N at once at
## 160 km/h, all four together) and a few hundred N of real crest / dip load
## where the swell curves. Measured: the 30-frame average is 61 N off, with
## ~670 N of downforce to find; a car without downforce is 670 N off.
const DOWNFORCE_AVERAGE_FRAMES := 30
const DOWNFORCE_TOLERANCE := 150.0

## Micro-bumps: most their mean may be off 0 over the 200 m lane strip x = 0,
## z = 0 .. -200 in 5 cm steps [m], and least RMS they must show there [m].
## Measured: mean 0.06 mm, RMS 3.8 mm.
const MICRO_MEAN_TOLERANCE := 0.0005
const MICRO_MIN_RMS := 0.001

## The lane's elevation has to be worth the name: least height between its
## lowest and highest point along x = 0 [m]. Measured: 2.2 m.
const LANE_MIN_ELEVATION_RANGE := 1.0

## Bumps at speed: the flat-out run gets this long to build speed, then the
## wheel loads are sampled for this long [physics frames], 6 s and 10 s.
# was 300 (5 s) -> 360 - the car is slower off the line (slipping clutch, the
# engine's inertia in the low gears): after 15 s it was 0.20 m up the swell,
# ROAD_FEEL_MIN_CLIMB wants 0.25. One second more of run-up.
const ROAD_FEEL_RUN_UP_FRAMES := 360
const ROAD_FEEL_SAMPLE_FRAMES := 600

## ... every wheel's load must swing at least this much about its baseline
## (half its axle's static + transfer + aero share) [RMS, share of the wheel's
## static load]. Measured: 0.070 - 0.073. A car that does not feel the road
## shows 0.
const ROAD_FEEL_MIN_RIPPLE := 0.02

## ... and each axle's load, averaged over the run, must stay this close to its
## baseline [N]: the road moves load around, it does not add any. Measured:
## front +13 N, rear +22 N (of ~5000 N and ~8200 N; the run ends on the way up
## the first swell, whose hollow presses the car down a little).
const ROAD_FEEL_MEAN_TOLERANCE := 60.0

## ... and the run has to get onto the swell: least elevation it must reach
## [m]. Measured: 0.43 m, at z = -428.
const ROAD_FEEL_MIN_CLIMB := 0.25

## ... while the body rides the road on its springs: most the car's height may
## be off the elevation under it [m], and least it has to move against it [m].
# was BODY_ON_GROUND_TOLERANCE 0.001 with the car on the floor every tick
# (measured 0: the body was put on the elevation by hand each tick, the floor
# moved under it) -> the body is carried by springs and the check is theirs:
# never on the floor, every wheel inside its travel, the body within
# RIDE_HEIGHT_TOLERANCE of the ground it shows over. Measured flat out down the
# lane: up to 1.3 cm off (the micro-bumps alone are up to 1.2 cm, downforce
# sits the car ~0.7 cm down at 157 km/h), wheel travel up to 2.2 cm. A body
# that never moves against the road is the old teleport: RIDE_HEIGHT_MIN_MOTION.
const RIDE_HEIGHT_TOLERANCE := 0.03
const RIDE_HEIGHT_MIN_MOTION := 0.002

## A spring counts as at rest within this far of its static place [m]:
## 0.01 mm, 0.2 - 0.5 N. Measured: 0.
const REST_TRAVEL_TOLERANCE := 0.00001

## Suspension, drop test: the car is stood this far above its ride height [m]
## and let go; the body has to bounce on its springs at a road car's ride
## frequency [Hz] and be back at rest, every spring within
## SUSPENSION_SETTLED_TRAVEL [m] of its static place, SUSPENSION_SETTLE_FRAMES
## later (3 s). Measured: 1.50 Hz (heave on all four springs, 1.63 Hz undamped),
## 0.04 mm after 3 s.
const SUSPENSION_DROP_HEIGHT := 0.03
const SUSPENSION_MIN_BOUNCE_HZ := 1.2
const SUSPENSION_MAX_BOUNCE_HZ := 1.9
const SUSPENSION_SETTLE_FRAMES := 180
const SUSPENSION_SETTLED_TRAVEL := 0.0005

## Dive, squat and roll: full brake from SUSPENSION_BRAKE_SPEED [m/s], a launch,
## and CORNER_STEER held from GET_UP_TO_SPEED. Each is averaged over
## SUSPENSION_AVERAGE_FRAMES once the first swing is over (the brake and the
## corner after SUSPENSION_SETTLE_IN_FRAMES). Least nose-down pitch under
## braking, nose-up pitch launching and roll out of the corner [rad], least
## front bump travel under braking [m]; measured -0.026, 0.020, -0.038 rad and
## 4.8 cm. And the cross-check that replaces the car's old weight-transfer
## formula: what the springs carry, averaged, against rigid-body statics
## (acceleration x CAR_MASS x CG_HEIGHT over wheelbase or track) [share of the
## load moved]. Measured: 0.07 off under braking (the dive is still swinging
## through the half second it is averaged over), 0.005 in the corner.
const SUSPENSION_BRAKE_SPEED := 30.0
const SUSPENSION_SETTLE_IN_FRAMES := 30
const SUSPENSION_AVERAGE_FRAMES := 30
const SUSPENSION_MIN_DIVE := 0.01
const SUSPENSION_MIN_DIVE_TRAVEL := 0.02
const SUSPENSION_MIN_SQUAT := 0.005
const SUSPENSION_MIN_ROLL := 0.015
const SUSPENSION_STATICS_TOLERANCE := 0.1

## The wheels are drawn on the road: most the bottom of a drawn wheel may be
## off the road under it [m]. Measured: under 0.001 mm (32-bit node positions).
const WHEEL_ON_ROAD_TOLERANCE := 0.0001

## Tyre curve: least share of its peak force a front tyre still has to hold at
## twice its peak slip angle (the wide top of the rubber pass). Measured:
## 0.957; with the narrower top (TYRE_SLIDE_ONSET 2.0) it was 0.941.
const TYRE_WIDE_TOP_MIN_SHARE := 0.95

## Crest test: a standing start this far before the road's test dip [m], flat
## out, crosses it at ~25 m/s (90 km/h), where the dip's 10 m come by at 2.5 Hz:
## close above the ride frequency, the suspension cannot follow it down.
const CREST_RUN_UP := 75.0

## Going in, every wheel's load must dip at least this far below its baseline,
## and at the bottom of the dip rise at least this far above it [share of the
## baseline]. Measured: dips 0.33 - 0.43, rises 0.53 - 0.72.
const CREST_MIN_DIP := 0.2
const CREST_MIN_RISE := 0.25

## A wheel counts as in the dip within this far of its centre [m] (the dip is
## 10 m long), and as past it from CREST_SETTLED_FROM to CREST_SETTLED_TO past
## the centre [m]: there its load must average back to the baseline to within
## CREST_SETTLED_TOLERANCE [share of the baseline]. Measured: 0.012.
const CREST_WINDOW := 7.0
const CREST_SETTLED_FROM := 25.0
const CREST_SETTLED_TO := 45.0
const CREST_SETTLED_TOLERANCE := 0.03

## Placed objects: most the foot of a cone, board post or pylon may be off the
## ground under it [m]. Measured: 0 (they are placed on the same function).
const PLACED_ON_GROUND_TOLERANCE := 0.01

## Slide settle: from ~60 km/h the handbrake goes on with SLIDE_SETTLE_STEER of
## left steering for this many physics frames, then every key is let go and
## the car is watched for SLIDE_SETTLE_WATCH_FRAMES (10 s). Three slides: a
## flick the car comes back from and rolls on, a slide that scrubs it to a
## stop nose-first, and a full second of handbrake that leaves it rolling
## backwards.
const SLIDE_SETTLE_STEER := 0.3
const SLIDE_FLICK_FRAMES := 12
const SLIDE_SCRUB_FRAMES := 40
const SLIDE_BACKWARDS_FRAMES := 60
const SLIDE_SETTLE_WATCH_FRAMES := 600

## The nose counts as back in line with the way the car travels under this
## angle between the two [rad], for good; grip driving stays under ~0.1.
const SLIDE_IN_LINE_ANGLE := 0.1

## The flick (0.2 s of handbrake): the nose is back in line within this [s] and
## the car has turned no further than this on the way [rad]. Measured 1.33 s
## and 0.95 rad (55 degrees), rolling on straight at 9.2 m/s two seconds later;
## with the rear tyres sliding on the fronts' TYRE_SLIDE_GRIP it hung in a
## drift for 2.22 s and turned 1.60 rad (92 degrees).
const SLIDE_FLICK_MAX_IN_LINE_TIME := 1.75
const SLIDE_FLICK_MAX_TURNED := 1.25

## After the flick the car rolls on forwards, at least this fast 3 s after the
## release [m/s]: it came back, it did not spin to a stop. Measured 9.2.
const SLIDE_FLICK_MIN_ROLL_ON_SPEED := 5.0

## The scrub (0.67 s of handbrake): in line and down to CRAWL_SPEED within this
## [s], at rest within SLIDE_SCRUB_MAX_REST_TIME [s]. Measured 1.20 s for both
## and at rest after 4.57 s, the last 3 s of it under 0.3 m/s; it used to swap
## ends instead, in line and at a crawl after 4.63 s and still creeping
## backwards at 1.2 m/s after 10 s.
const SLIDE_SCRUB_MAX_SETTLE_TIME := 2.0
const SLIDE_SCRUB_MAX_REST_TIME := 6.0

## The slide that ends rolling backwards (1 s of handbrake): in a forward gear
## the engine holds the car back that way round too, so between 1 s and 3 s
## after the release it loses at least this much speed [m/s]. Measured 0.78
## (4.22 -> 3.44 m/s); with rolling resistance alone it lost 0.31.
const SLIDE_BACKWARDS_MIN_SPEED_DROP := 0.55

## Largest step per physics frame while a slide settles [m]: the car enters at
## ~16.6 m/s, 0.28 m a frame. Measured 0.26.
const SLIDE_SETTLE_MAX_STEP := 0.5

## A rotation that has stopped [rad/s]. Measured under 0.000001.
const SLIDE_SETTLED_YAW_RATE := 0.01

## The mirrored 180 ends this close to the target heading [degrees]: measured
## 0.8 (rotation -179.2), the certified left-hand run 0.1. The judge's own
## tolerance is 35; a signed judge read this run as 359.2 off.
const MIRRORED_SPIN_MAX_HEADING_ERROR := 10.0

## Drivetrain dynamics: full throttle in neutral gets from idle to the limiter
## within this [s]. Measured 0.78.
const FREE_REV_MAX_TIME := 1.0

## Held against the limiter for 1.5 s, the fuel is cut at least this often and
## the revs swing by more than this [rpm]. Measured 11 cuts, 6964 .. 7200 rpm.
const LIMITER_MIN_CUTS := 5
const LIMITER_MIN_BOUNCE_RPM := 100.0

## Let go at the limiter in neutral, the revs are back at idle within this [s].
## Measured 4.67.
const IDLE_RETURN_MAX_TIME := 6.0

## Coasting downshift 4th -> 3rd at ~80 km/h: the blip raises the revs by at
## least this [rpm] with the clutch open and leaves them within
## DOWNSHIFT_MAX_MISMATCH_RPM of what 3rd wants; through the catch the car
## never slows harder than this [m/s^2] (engine braking in 3rd, drag and
## rolling resistance come to ~0.8). Measured: +520 rpm, 60 rpm off, 0.82 m/s^2.
const DOWNSHIFT_MIN_BLIP_RPM := 400.0
const DOWNSHIFT_MAX_MISMATCH_RPM := 300.0
const DOWNSHIFT_MAX_DECEL := 2.5

## Slip ratio that counts as wheelspin in the clutch-drop check: twice the peak,
## a little under the ArcadeCar.DRIVE_SLIP_RATIO the clutch foot holds.
const WHEELSPIN_SLIP_RATIO := 0.2

## Clutch dropped at the limiter: the engine stays within the limiter's band on
## the slipping clutch for at least this many physics frames, the wheelspin
## lasts longer than this [s], and all that time the tach reads at least this
## far above what the road speed makes in 1st [rpm]. Measured 6 frames (then
## the clutch has dragged the revs down to ~6400, where the engine makes what
## the spinning tyres take), 1.77 s and 1330 rpm.
const CLUTCH_DROP_MIN_LIMITER_FRAMES := 3
const CLUTCH_DROP_MIN_SPIN_TIME := 1.0
const CLUTCH_DROP_MIN_TACH_LEAD := 800.0

## Ordinary launch: the tach gets at least this far above the road's revs
## [rpm] on the slipping clutch (measured 2600), the rear tyres are worked to
## at least this share of their peak slip ratio (measured 1.0: the launch sits
## right at the limit of adhesion), and the clutch is home within
## LAUNCH_MAX_SLIP_TIME [s] (measured 1.63).
const LAUNCH_MIN_FLARE_RPM := 2000.0
const LAUNCH_MIN_PEAK_SLIP_SHARE := 0.8
const LAUNCH_MAX_SLIP_TIME := 2.5

## Lift-off runs start from this speed [m/s], ~80 km/h: 5200 rpm in 2nd,
## 3000 in 4th. Lifting must slow the car at least this many times harder in
## 2nd than in 4th. Measured 1.75 (1.07 vs 0.61 m/s^2, drag and rolling
## resistance in both).
const LIFT_OFF_SPEED := 22.0
const ENGINE_BRAKING_MIN_GEAR_RATIO := 1.4

## Upshift at full throttle: with the clutch open the revs drift down by more
## than SHIFT_MIN_DRIFT_RPM and less than SHIFT_MAX_DRIFT_RPM in the 0.2 s
## (friction alone; a kinematic tach would have dropped the full ~2800 to the
## next gear), then the clutch takes out at least SHIFT_MIN_CATCH_RPM more and
## leaves the engine within this share of the road's revs in 2nd (the tyres'
## slip is the rest) half a second on. Measured: 460 rpm of drift, 1640 of
## catch, the rear tyres chirping at a slip ratio of ~0.2 as it lands.
const SHIFT_MIN_DRIFT_RPM := 200.0
const SHIFT_MAX_DRIFT_RPM := 1200.0
const SHIFT_MIN_CATCH_RPM := 1000.0
const SHIFT_CAUGHT_RPM_TOLERANCE := 0.12

## Wheel visuals: over the first 1.5 s of a launch the drawn rear wheels turn at
## least this many times as far as the fronts. Measured 1.1.
const VISUAL_MIN_SPIN_LEAD := 1.03

# --- Telemetry ------------------------------------------------------------------
# Where the telemetry phase writes. A fixed tmp path, outside user://, deleted
# before the phase so the same file is written every run.

const TELEMETRY_DIR := "/tmp/fd-3E-telemetry"
const TELEMETRY_FILE := TELEMETRY_DIR + "/smoke.jsonl"

## Physics frames of free driving before the mission starts, 1 s: two samples
## at FREE_SAMPLE_STRIDE_TICKS ...
const TELEMETRY_FREE_FRAMES := 60

## ... and how long the mission is driven for [physics frames], 2.5 s: ~30
## samples at SAMPLE_STRIDE_TICKS.
const TELEMETRY_DRIVE_FRAMES := 150

## Fields every sample line carries, whatever the car is doing ...
const TELEMETRY_SAMPLE_FIELDS: Array[String] = [
	"t_session_s", "pos", "heading_deg", "speed_ms", "gear", "rpm",
	"throttle", "brake", "handbrake", "steer", "load_front", "load_rear",
	"slip_front_deg", "slip_rear_deg", "slip_ratio_front", "slip_ratio_rear",
	"yaw_rate_deg_s",
]

## ... the two a sample taken during a mission carries on top ...
const TELEMETRY_MISSION_FIELDS: Array[String] = ["t_run_s", "mission"]

## ... and what the mission block itself holds.
const TELEMETRY_CONTEXT_FIELDS: Array[String] = ["title", "kind", "elapsed_s", "progress"]

## How far apart two sample times may be from the stride they are counted in
## [s]: the times are tick counts times 1/60 s, snapped to 1e-5 s in the file.
const TELEMETRY_STRIDE_TOLERANCE := 0.001

## Least speed the mission samples have to show [m/s], ~20 km/h: the car is
## driven, so the file has to show it moving.
const TELEMETRY_MIN_SAMPLE_SPEED := 5.0

## Pedals: frames a tap of the accelerate key is held for. The test driver's
## foot takes 6 ticks to the floor (throttle_attack 10), so 3 is about half.
const PEDAL_TAP_FRAMES := 3

## The band a tap's peak throttle has to land in (0..1): a partial press,
## clearly neither nothing nor the floor.
const PEDAL_TAP_MIN := 0.2
const PEDAL_TAP_MAX := 0.8

## Frames a held key is watched for, long enough for the slowest profile here
## (the chauffeur's throttle, 20 ticks) to get to the floor ...
const PEDAL_HOLD_FRAMES := 40

## ... and frames a released pedal is given to come back to nothing (the
## chauffeur's throttle takes 24).
const PEDAL_RELEASE_FRAMES := 40

## How much longer the chauffeur's foot has to take to the floor than the test
## driver's, at least (the rates say 10 / 3 = 3.3 times).
const PEDAL_PROFILE_MIN_RATIO := 2.0

## Frames of full throttle for the launch driven twice, by the key and through
## set_driver_input: the 2 s of the first drive in this file.
const DRIVER_INPUT_LAUNCH_FRAMES := 120

## Frames given to half pedal and half lock asked for through set_driver_input
## to arrive (the test driver's hands need 11 ticks for 225 degrees).
const DRIVER_INPUT_SETTLE_FRAMES := 30

## Fuel: frames the engine idles for the idle burn and the firing count (2 s) ...
const FUEL_IDLE_FRAMES := 120

## ... the band the idle burn has to land in [L/h] (~18 Nm at 900 rpm through
## the burn formula: 0.63) ...
const FUEL_IDLE_MIN_L_H := 0.4
const FUEL_IDLE_MAX_L_H := 1.0

## ... frames of full throttle from rest for the burn under load (5 s, through
## 1st and 2nd into 3rd), the least it has to burn in them as a mean rate [L/h]
## and the most (flat out at the limiter is ~67; measured 44.1) ...
const FUEL_LOAD_FRAMES := 300
const FUEL_LOAD_MIN_L_H := 30.0
const FUEL_LOAD_MAX_L_H := 70.0

## ... and on the overrun after it: frames for the foot to come off (the test
## driver's throttle is shut in 2 ticks) and frames watched with it shut.
const FUEL_OVERRUN_LIFT_FRAMES := 5
const FUEL_OVERRUN_FRAMES := 30

## Exhaust: how far the firings counted idling may be off three per turn of the
## crankshaft (share; the engine sits on its idle speed, measured 0.0000) ...
const EXHAUST_EVENTS_TOLERANCE := 0.01

## ... the most the flow may read idling and the least flat out (0..1; measured
## 0.04 and 0.97).
const EXHAUST_IDLE_MAX_FLOW := 0.1
const EXHAUST_LOAD_MIN_FLOW := 0.6

## Dry tank: frames the engine is given to run down on its friction (4 s; it
## takes ~1.7) and frames of full throttle it then gets nowhere on.
const FUEL_DRY_RUN_DOWN_FRAMES := 240
const FUEL_DRY_THROTTLE_FRAMES := 60

## Payload: what is loaded [kg], and the most of the empty car's speed the
## loaded one may have after FUEL_LOAD_FRAMES of full throttle (share). 1600 kg
## against 1300 is 0.81 of the acceleration where the engine sets it (2nd gear
## on); the launch in 1st is the tyres' and costs a loaded car nothing.
## Measured 0.88.
const PAYLOAD_KG := 300.0
const PAYLOAD_MAX_SPEED_SHARE := 0.93

## Creep: frames of throttle before the stop (1 s), frames the brake is held at
## the standstill (1 s), frames the creep is given after the brake is let go
## (10 s), the speed from which the car counts as on the move [m/s] and by when
## it has to be [s] (the dwell is 0.4 of it; measured 1.15), and the band the
## crawl has to have settled in by the end [m/s] (1.1 .. 1.8 km/h; measured
## 0.42 m/s, 1.5 km/h).
const CREEP_RUN_UP_FRAMES := 60
const CREEP_HOLD_FRAMES := 60
const CREEP_WATCH_FRAMES := 600
const CREEP_MOVING_SPEED := 0.1
const CREEP_MAX_PICK_UP_TIME := 2.0
const CREEP_MIN_CRAWL := 0.3
const CREEP_MAX_CRAWL := 0.5

## ... and frames a car nobody has touched is watched standing still (5 s).
const CREEP_UNTOUCHED_FRAMES := 300

## Driver's controls. A launch is watched for 2 s: the clutch is home and the
## wheelspin of a launch without TCS at its height well inside that.
const CONTROLS_LAUNCH_FRAMES := 120

## A launch without TCS has to spin the driven wheels at least this far past
## what the TCS holds them at (slip ratio, no unit): real wheelspin, several
## times DRIVE_SLIP_RATIO, not a rounding difference.
const CONTROLS_MIN_WHEELSPIN := 1.0

## Speed the two stops start from [m/s], 90 km/h.
const CONTROLS_BRAKE_SPEED := 25.0

## A stop on locked front wheels has to be at least this much longer than the
## same stop with ABS (a share, no unit): the fronts slide on TYRE_SLIDE_GRIP
## 0.85 where the ABS holds them near their peak; measured ~6 %.
const CONTROLS_MIN_LOCKED_STOP_SHARE := 1.03

## Frames of full brake and full left lock from CONTROLS_BRAKE_SPEED, 1 s, and
## the most a car on locked fronts may turn in that time as a share of what the
## same car turns with ABS.
const CONTROLS_STEER_FRAMES := 60
const CONTROLS_LOCKED_MAX_TURN_SHARE := 0.25

## Frames the clutch pedal is given to get to the floor (it takes 12), and the
## frames of full throttle against it, 2 s.
const CONTROLS_CLUTCH_FRAMES := 20
const CONTROLS_CLUTCH_HOLD_FRAMES := 120

## Frames a stopped engine is watched for (nothing burnt, nothing fired), and
## the frames the starter is held, 1 s.
const CONTROLS_STALLED_FRAMES := 60

## The starter has to have the engine caught within this [s], and the idle
## controller has it back at idle (within CONTROLS_IDLE_TOLERANCE rpm) 2 s on.
const CONTROLS_MAX_START_TIME := 0.5
const CONTROLS_IDLE_FRAMES := 120
const CONTROLS_IDLE_TOLERANCE := 20.0

## Frames of full throttle the two shift programs are compared over, 10 s: the
## sport program is in 3rd by then, comfort in 4th.
const CONTROLS_MODE_FRAMES := 600

## Frames of half throttle, then of half brake, recorded for the telemetry
## check, 1 s each, and the file they go to (next to the telemetry phase's own).
const CONTROLS_PEDAL_FRAMES := 60
const CONTROLS_TELEMETRY_FILE := TELEMETRY_DIR + "/pedals.jsonl"

## Tyre marks: the grip run is flat out for this many ticks (3 s, through the
## change into 2nd) and then a full pedal to a stop ...
const MARKS_GRIP_FRAMES := 180

## ... the slide is SLIDE_SETTLE_STEER and the handbrake from ~60 km/h for this
## many ticks and everything let go for this many more ...
const MARKS_SLIDE_FRAMES := 40
const MARKS_SLIDE_WATCH_FRAMES := 120

## ... a mark lies on the ground to this [m] (single precision at pad
## distances) ...
const MARKS_GROUND_TOLERANCE := 0.0001

## ... the marks of a straight run are, laid end to end, at least this share of
## twice the way the car went with an axle marking (two wheels; what is short
## of it is the tick a trail starts on and an end under MARK_MIN_LENGTH; and at
## most a tick's way more for each of the four wheels, the tick a trail ends
## on) ...
const MARKS_MIN_TRAIL_SHARE := 0.95

## ... the fade is watched tick by tick for this long (1 s) ...
const MARKS_FADE_FRAMES := 60

## ... and the late mark of the expiry check is laid this many ticks after the
## early ones (1 s).
const MARKS_LATE_FRAMES := 60

## ... the slow scrub is full lock off the throttle from this speed [m/s], 45
## km/h, for this many ticks (4 s): the fronts plough at ~0.38 rad, a little
## over MARK_SLIP_ANGLE; and the corner that must leave nothing is the same
## from this speed [m/s], 30 km/h, where they get to 0.25 rad (what marked at
## the old threshold of 0.2, the user's complaint) ...
const MARKS_SCRUB_SPEED := 12.5
const MARKS_SCRUB_FRAMES := 240
const MARKS_CLEAN_CORNER_SPEED := 8.2

## ... a scrub's marks are all fainter than this (fresh alpha; measured 0.23 at
## most), and the handbrake slide's marks have on average at least this many
## times the alpha of the scrub's darkest, at least this share of them as dark
## as a mark gets (measured 77 of 108: the locked rears').
const MARKS_SCRUB_MAX_ALPHA := 0.3
const MARKS_SLIDE_MIN_DARKER := 2.0
const MARKS_SLIDE_MIN_FULL_SHARE := 0.5

# --- Stability switch ---------------------------------------------------------

## With the stability assist switched off the flick of _check_slide_settle
## (SLIDE_FLICK_FRAMES of handbrake at SLIDE_SETTLE_STEER from ~60 km/h) has to
## swing the nose at least this many times as far off the way the car travels
## as with it (measured 0.46 rad against 0.16), and turn the car at least this
## much further [rad] before it is back in line (measured 1.58 against 0.73).
const SC_MIN_ANGLE_GAIN := 2.0
const SC_MIN_TURN_GAIN := 0.5

## The low-speed blend with the assist off: the car creeps round at full lock
## for this many ticks (5 s), and its yaw rate has to be the rolling circle's
## (speed x tan(wheel angle) / wheelbase) to this share by then.
const SC_CREEP_FRAMES := 300
const SC_ROLLING_TOLERANCE := 0.05

# --- Starter cycle ---------------------------------------------------------------

## A tap of the starter key is watched for this many ticks (2 s); the crank
## cycle it starts may be this many ticks off STARTER_CYCLE_TIME (the tick of
## the tap and the float's last one), and a held key is held for this many
## ticks, 1.5 s, nearly twice the cycle.
const STARTER_WATCH_FRAMES := 120
const STARTER_CYCLE_TOLERANCE_TICKS := 2
const STARTER_HOLD_FRAMES := 90

# --- Wheel strobe ------------------------------------------------------------------

## Speed the drawn wheels are watched at [m/s], 130 km/h: the wheels turn 106
## rad/s, 101 degrees a tick, past the quarter turn from which the one bar
## across the rim reads as turning backwards; the ticks the car is given to
## get there flat out (20 s, it takes ~12) and the ticks the wheels are then
## watched for, still flat out.
const STROBE_SPEED := 36.0
const STROBE_RUN_UP_FRAMES := 1200
const STROBE_FRAMES := 30

var _failures := 0


## Run clock: every test's start line is this far down the pad from its start
## point [m] ...
const RUN_CLOCK_LINE_AHEAD := 4.0

## ... the check sits on the start point for this many ticks (1 s), puts the car
## this far short of the line and over it [m], and lets the clock run for this
## many ticks.
const RUN_CLOCK_WAIT_TICKS := 60
const RUN_CLOCK_STEP := 0.5
const RUN_CLOCK_RUN_TICKS := 30


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		_finish()
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(60)

	var car := main.get_node_or_null("Car") as ArcadeCar
	var hud := main.get_node_or_null("HUD")
	var speed_label := main.get_node_or_null("HUD/SpeedLabel") as Label
	var camera := main.get_node_or_null("ChaseCamera") as Camera3D
	_check(car != null, "car node exists and is an ArcadeCar")
	_check(hud != null and speed_label != null, "HUD with speed label exists")
	_check(camera != null and camera.current, "chase camera exists and is current")
	_check(main.get_node_or_null("Sun") is DirectionalLight3D, "sun light exists")
	_check(main.get_node_or_null("WorldEnvironment") is WorldEnvironment, "world environment exists")
	_check(main.get_node("TestPad").get_child_count() > 1, "test pad generated its markers")
	if car == null or speed_label == null or camera == null:
		_finish()
		return

	# was car.is_on_floor(): the collision box lying on the floor WAS the car
	# standing on the ground -> the body floats GROUND_CLEARANCE above the floor
	# on its springs. Resting is every wheel loaded, no spring off its static
	# place, nothing moving, and the floor not needed.
	var resting := not car.is_on_floor() and absf(car.velocity.y) < 0.0001
	for i in 4:
		resting = resting and car.wheel_loads[i] > 0.0 and absf(car.wheel_travel[i]) < REST_TRAVEL_TOLERANCE
	_check(resting, "car rests on the ground: on its springs, every wheel loaded (travel %.5f m at most, clear of the floor)" % _largest_travel(car))
	_check(absf(car.forward_speed) < 0.01, "car is stationary without input (%.3f m/s)" % car.forward_speed)
	_check(speed_label.text == "0 km/h", "HUD reads 0 km/h at rest ('%s')" % speed_label.text)

	# Accelerate: moves along -Z, HUD follows, camera keeps up.
	Input.action_press("accelerate")
	await _step(120)
	# was > 10.0 m/s and z < -10.0 (measured 12.0 m/s, the kinematic drivetrain put
	# tyre-limited drive on the road from the first tick) -> > 8.0 and < -7.0 -
	# measured 9.5 m/s and 8.2 m: the car pulls away on a slipping clutch while
	# the revs build, and in 1st a quarter of the engine's torque winds up its own
	# inertia. 0 - 100 km/h comes to 7.1 s; the real 986 2.5 takes 6.9.
	_check(car.forward_speed > 8.0, "accelerates forward (%.1f m/s after 2 s)" % car.forward_speed)
	_check(car.global_position.z < -7.0, "travels along -Z (z = %.1f)" % car.global_position.z)
	_check(absf(car.global_position.x) < 0.01, "tracks straight without steering (x = %.3f)" % car.global_position.x)
	_check(speed_label.text == "%d km/h" % roundi(car.speed_kmh), "HUD shows current speed ('%s')" % speed_label.text)
	var camera_gap := camera.global_position.distance_to(car.global_position)
	_check(camera_gap > 3.0 and camera_gap < 15.0, "camera follows the car (%.1f m away)" % camera_gap)

	# Steer left: heading yaws positive, car drifts towards -X.
	var yaw_before := car.global_rotation.y
	Input.action_press("steer_left")
	await _step(45)
	Input.action_release("steer_left")
	_check(angle_difference(yaw_before, car.global_rotation.y) > 0.2, "steers left (yaw %.2f -> %.2f)" % [yaw_before, car.global_rotation.y])
	_check(car.global_position.x < -0.5, "turning left moves the car towards -X (x = %.1f)" % car.global_position.x)

	# Steer right turns the other way (once the steering has re-centred).
	# was 15 frames (the 0.2 s the old steering ramp took, and a little) -> 24 -
	# the hands need 21 ticks to bring the 900-degree wheel back from full lock;
	# after 15 it still stood 125 degrees to the left and the 0.75 s to the
	# right only turned the car 0.17 rad of the 0.2 asked for.
	await _step(24)
	yaw_before = car.global_rotation.y
	Input.action_press("steer_right")
	await _step(45)
	Input.action_release("steer_right")
	_check(angle_difference(yaw_before, car.global_rotation.y) < -0.2, "steers right (yaw %.2f -> %.2f)" % [yaw_before, car.global_rotation.y])
	Input.action_release("accelerate")
	await _step(30)
	_check(absf(car.lateral_speed) < 0.5, "lateral slip settles after steering (%.2f m/s)" % car.lateral_speed)

	# Coast, then brake to a stop: the held brake holds the car, it never turns
	# into reverse by itself.
	var speed_before := car.forward_speed
	await _step(30)
	_check(car.forward_speed < speed_before and car.forward_speed > 0.0, "coasts down gently (%.1f -> %.1f m/s)" % [speed_before, car.forward_speed])
	speed_before = car.forward_speed
	Input.action_press("brake")
	await _step(20)
	# 20 frames on the brakes: what the tyres can hold, no more (drag adds a
	# little). Lower bound was 0.95 -> 0.85 of the all-tyres-at-the-limit figure:
	# the brake force is now split by BRAKE_BIAS_FRONT, the fronts run at their
	# limit under ABS and the rears stay under theirs, so a real stop comes out
	# at ~0.9 of it. The upper bound is the one that matters: never more than
	# the tyres have.
	var brake_drop := speed_before - car.forward_speed
	var grip_drop := ArcadeCar.BRAKE_DECEL * 20.0 / 60.0
	_check(brake_drop > grip_drop * 0.85 and brake_drop < grip_drop * 1.0, "brakes hard, at the tyres' limit (%.1f -> %.1f m/s, all four at the limit would give %.1f)" % [speed_before, car.forward_speed, grip_drop])
	var z_stopped := 0.0
	var lowest_speed := 0.0
	for frame in 240:
		await physics_frame
		lowest_speed = minf(lowest_speed, car.forward_speed)
		if frame == 119:
			z_stopped = car.global_position.z
	_check(absf(car.forward_speed) < 0.01 and lowest_speed > -0.01, "held brake stops the car and never reverses (%.2f m/s, lowest %.2f)" % [car.forward_speed, lowest_speed])
	_check(absf(car.global_position.z - z_stopped) < 0.01 and not car.reverse_engaged, "held brake holds the car still (moved %.3f m in 2 s)" % absf(car.global_position.z - z_stopped))
	_check(not speed_label.text.begins_with("R"), "HUD does not flag reverse under a held brake ('%s')" % speed_label.text)

	# A fresh press of the brake key at a standstill engages reverse.
	Input.action_release("brake")
	await _step(5)
	Input.action_press("brake")
	await _step(240)
	_check(car.reverse_engaged and car.forward_speed < -1.0, "a fresh brake press at a standstill reverses (%.1f m/s)" % car.forward_speed)
	_check(car.forward_speed >= -ArcadeCar.MAX_REVERSE_SPEED - 0.01, "reverse speed is capped (%.1f m/s)" % car.forward_speed)
	_check(speed_label.text.begins_with("R"), "HUD flags reverse ('%s')" % speed_label.text)
	Input.action_release("brake")

	# In reverse the accelerate key is the brake: it stops the car. Held through
	# the stop it engages forward after FORWARD_ENGAGE_GRACE and drives away, the
	# key never released (the J-turn exit in one motion).
	Input.action_press("accelerate")
	var stop_frame := -1
	var engage_frame := -1
	var rolling_back_at_press := car.forward_speed
	for frame in 240:
		await physics_frame
		if stop_frame < 0 and car.reverse_engaged and absf(car.forward_speed) < 0.01:
			stop_frame = frame
		if stop_frame >= 0 and engage_frame < 0 and not car.reverse_engaged:
			engage_frame = frame
		if stop_frame >= 0 and frame == stop_frame + FORWARD_ENGAGE_FRAMES:
			break
	_check(rolling_back_at_press < -1.0 and stop_frame > 0, "held accelerate stops the reversing car, still in reverse (from %.1f m/s, stopped at frame %d)" % [rolling_back_at_press, stop_frame])
	_check(engage_frame > stop_frame and engage_frame - stop_frame <= FORWARD_ENGAGE_FRAMES, "accelerate held through the stop engages forward within the grace (%d frames after the stop)" % (engage_frame - stop_frame))
	_check(not car.reverse_engaged and car.forward_speed > 1.0, "the same held accelerate drives away in one motion (%.1f m/s, %d frames after the stop)" % [car.forward_speed, FORWARD_ENGAGE_FRAMES])
	_check(not speed_label.text.begins_with("R"), "HUD stops flagging reverse after the held exit ('%s')" % speed_label.text)
	Input.action_release("accelerate")

	# Both keys held at a standstill in reverse cancel out: forward never engages.
	Input.action_press("brake")
	await _step(120)
	Input.action_release("brake")
	await _step(5)
	Input.action_press("brake")
	await _step(1)
	Input.action_release("brake")
	await _step(2)
	var in_reverse_before := car.reverse_engaged
	Input.action_press("accelerate")
	Input.action_press("brake")
	var highest_speed := car.forward_speed
	for frame in 180:
		await physics_frame
		highest_speed = maxf(highest_speed, car.forward_speed)
	_check(in_reverse_before and car.reverse_engaged, "both keys held at a standstill in reverse never engage forward (reverse %s -> %s)" % [in_reverse_before, car.reverse_engaged])
	_check(absf(car.forward_speed) < 0.01 and highest_speed < 0.01, "both keys held hold the car (%.2f m/s, highest %.2f)" % [car.forward_speed, highest_speed])
	Input.action_release("accelerate")
	Input.action_release("brake")

	# A fresh press-and-hold of accelerate at a standstill engages forward and
	# drives in one motion too, without waiting for the grace.
	await _step(5)
	Input.action_press("accelerate")
	await _step(2)
	_check(not car.reverse_engaged and car.forward_speed > 0.0, "a fresh accelerate press at a standstill engages forward at once (%.2f m/s after 2 frames)" % car.forward_speed)
	await _step(58)
	_check(not car.reverse_engaged and car.forward_speed > 1.0, "a fresh accelerate press at a standstill drives forward again (%.1f m/s)" % car.forward_speed)
	Input.action_release("accelerate")

	# Reset puts the car back on the start line.
	car.reset_to_spawn()
	await _step(5)
	_check(car.global_position.length() < 0.1, "reset returns the car to spawn")

	# Handbrake in a straight line: slows the car more than coasting, stays
	# straight.
	await _get_up_to_speed(car)
	var speed_start := car.forward_speed
	Input.action_press("handbrake")
	await _step(60)
	Input.action_release("handbrake")
	var drop := speed_start - car.forward_speed
	var coast_drop := ArcadeCar.COAST_DECEL * 1.0
	_check(car.forward_speed > 0.0 and drop > coast_drop + 3.0, "handbrake slows the car without throttle (%.1f -> %.1f m/s)" % [speed_start, car.forward_speed])
	_check(drop < ArcadeCar.BRAKE_DECEL * 0.75, "handbrake is gentler than the brake (lost %.1f m/s in 1 s, the brake takes %.1f)" % [drop, ArcadeCar.BRAKE_DECEL])
	_check(absf(car.global_position.x) < 0.01 and absf(car.lateral_speed) < 0.01, "handbrake in a straight line stays straight (x = %.3f)" % car.global_position.x)

	# Same corner twice, without and with a tap of the handbrake: steer left off
	# the throttle for 2.5 s, the handbrake on for the first HANDBRAKE_TAP_FRAMES.
	var grip := await _corner(car, false)
	var slide := await _corner(car, true)
	_check(slide.peak_slip > grip.peak_slip * 1.5 and slide.peak_slip > grip.peak_slip + 1.5, "handbrake corner slides more (peak slip %.2f vs %.2f m/s)" % [slide.peak_slip, grip.peak_slip])
	_check(slide.peak_yaw > grip.peak_yaw * 1.3, "handbrake corner rotates more (peak yaw %.2f vs %.2f rad/s)" % [slide.peak_yaw, grip.peak_yaw])
	_check(slide.speed_drop > grip.speed_drop, "handbrake corner scrubs more speed (%.1f vs %.1f m/s)" % [slide.speed_drop, grip.speed_drop])
	_check(absf(slide.end_slip) < absf(grip.end_slip) + 0.75, "slip recovers after releasing the handbrake (%.2f vs %.2f m/s)" % [slide.end_slip, grip.end_slip])
	# slide_yaw_rate is now the nose swinging relative to the direction of travel
	# (was: yaw beyond the steering's aim). In this left corner positive = the
	# tail still stepping out, negative = the slide coming back, which is what a
	# caught tail does with the steering still held; it must not be snapping back
	# either.
	_check(slide.end_slide_yaw < 0.1 and slide.end_slide_yaw > -0.3, "tail catches after releasing the handbrake (slide yaw %.3f rad/s, negative = coming back)" % slide.end_slide_yaw)
	_check(grip.finite and slide.finite, "no NaN / inf in speeds or position while cornering")
	_check(maxf(grip.max_step, slide.max_step) < 1.5, "no teleporting while cornering (largest step %.2f m)" % maxf(grip.max_step, slide.max_step))

	# Friction ellipse: grip spent on braking is not there for turning. The same
	# turn-in on the brakes turns the car less, but still turns it.
	var free_turn := await _turn_in(car, false)
	var braked_turn := await _turn_in(car, true)
	_check(braked_turn < free_turn * 0.8, "braking while turning costs turn-in (%.2f vs %.2f rad in 0.75 s)" % [braked_turn, free_turn])
	_check(braked_turn > free_turn * 0.2, "the car still steers on the brakes (%.2f vs %.2f rad in 0.75 s)" % [braked_turn, free_turn])

	car.reset_to_spawn()
	await _step(5)
	_check(car.global_position.length() < 0.1 and car.slide_yaw_rate == 0.0, "reset also clears the slide")

	await _check_drivetrain(car, main.get_node_or_null("HUD/RpmLabel") as Label)
	await _check_drivetrain_dynamics(car, main.get_node_or_null("HUD/RpmLabel") as Label)
	await _check_force_dynamics(car)
	_check_tyre_curve(car)
	await _check_low_speed_blend(car)
	await _check_raw_steering(car)
	await _check_high_speed_stability(car)
	await _check_course(main.get_node("TestPad") as TestPad, car)
	_check_road_profile(main.get_node("TestPad") as TestPad, car)
	await _check_road_feel(main.get_node("TestPad") as TestPad, car)
	await _check_crest(car)
	await _check_suspension(main.get_node("TestPad") as TestPad, car)
	_check_placed_on_ground(main.get_node("TestPad") as TestPad)
	await _check_slide_settle(car)
	_check_run_clock(main.get_node("TestPad") as TestPad, car)
	await _check_mirrored_spin(main.get_node("TestPad") as TestPad, car)
	await _check_pedals(car, hud as HUD)
	await _check_fuel_and_exhaust(car, hud as HUD)
	await _check_mass_and_payload(main.get_node("TestPad") as TestPad, car)
	await _check_creep(car)
	await _check_driver_controls(main, car)
	await _check_telemetry(main, car)
	await _check_tyre_marks(main, car)
	await _check_stability_switch(main, car)
	await _check_starter_cycle(main, car)
	await _check_wheel_strobe(car)

	_finish()


## Gears, RPM, manual shifting and weight transfer.
func _check_drivetrain(car: ArcadeCar, rpm_label: Label) -> void:
	var static_rear := ArcadeCar.REAR_WEIGHT_FRACTION
	var static_front := 1.0 - static_rear
	var stats := _new_stats()

	car.reset_to_spawn()
	await _step(10)
	_check(rpm_label != null, "HUD with tach label exists")
	if rpm_label == null:
		return
	_check(car.gear == 1 and car.automatic, "resting car sits in 1st, automatic (G%d)" % car.gear)
	_check(rpm_label.text.contains("rpm") and rpm_label.text.ends_with("G1"), "HUD tach shows rpm and gear ('%s')" % rpm_label.text)

	# Full throttle from rest in automatic: 1st gear pulls, load moves rearward,
	# RPM climbs with speed, then an upshift drops it.
	Input.action_press("accelerate")
	await _drive(car, 60, stats)
	_check(car.rear_load_fraction > static_rear + 0.05, "acceleration shifts load rearward (rear %.2f, static %.2f)" % [car.rear_load_fraction, static_rear])
	# was read straight after the first second -> once the clutch is home - until
	# then the engine sits at LAUNCH_RPM on a slipping clutch whatever the road
	# speed does (3460 -> 3481 rpm over those 30 frames). Locked, revs and road
	# speed are one again, and that is what this check is about.
	for frame in 120:
		if car.clutch_locked:
			break
		await _drive(car, 1, stats)
	var gear_early := car.gear
	var rpm_early := car.engine_rpm
	await _drive(car, 30, stats)
	_check(car.gear == gear_early and car.engine_rpm > rpm_early + 500.0, "RPM rises with speed in a fixed gear (G%d: %d -> %d rpm)" % [car.gear, rpm_early, car.engine_rpm])
	var rpm_before_shift := car.engine_rpm
	var tach_red := false
	for frame in 300:
		if car.gear != gear_early:
			break
		rpm_before_shift = car.engine_rpm
		tach_red = rpm_label.get_theme_color("font_color") == rpm_label.get_parent().TACH_REDLINE_COLOR
		await _drive(car, 1, stats)
	_check(car.gear == gear_early + 1, "automatic shifts up under throttle (G%d -> G%d)" % [gear_early, car.gear])
	_check(stats.peak_traction_use > 0.999, "rear traction limit caps the drive force in 1st (use %.3f)" % stats.peak_traction_use)
	_check(tach_red, "HUD tach turns the warning colour near redline")
	await _drive(car, roundi(ArcadeCar.SHIFT_TIME * 60.0) + 6, stats)
	_check(car.engine_rpm < rpm_before_shift - 1500.0, "RPM drops on the upshift (%d -> %d rpm)" % [rpm_before_shift, car.engine_rpm])

	# Keep the throttle pinned: the gears keep coming and the car keeps pulling
	# far past what 1st gear alone could reach.
	var first_gear_top := car.speed_at_rpm(1, ArcadeCar.REDLINE_RPM)
	await _drive(car, 1200, stats)
	_check(car.gear >= 4, "gears advance under sustained throttle (G%d after 20 s)" % car.gear)
	_check(car.forward_speed > first_gear_top * 2.0, "speed keeps rising through the gears (%.1f m/s, 1st tops out at %.1f)" % [car.forward_speed, first_gear_top])
	Input.action_release("accelerate")

	# Braking at speed pitches the load onto the front axle.
	Input.action_press("brake")
	await _drive(car, 20, stats)
	Input.action_release("brake")
	_check(car.front_load_fraction > static_front + 0.1, "braking shifts load forward (front %.2f, static %.2f)" % [car.front_load_fraction, static_front])

	# The skidpad complaint: ~60 km/h in 4th has no pull; dropping to 2nd
	# brings the revs and the acceleration back.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 600:
		if car.forward_speed >= 16.7:
			break
		await _drive(car, 1, stats)
	Input.action_release("accelerate")
	while car.gear < 4:
		var gear_was := car.gear
		await _tap("shift_up")
		await _drive(car, 15, stats)
		if car.gear == gear_was:
			break
	_check(car.gear == 4 and not car.automatic, "shift-up key selects 4th and switches to manual (G%d)" % car.gear)
	_check(rpm_label.text.ends_with("G4 M"), "HUD flags manual mode ('%s')" % rpm_label.text)
	var accel_4th := await _measure_pull(car, stats)
	var rpm_4th := car.engine_rpm
	_check(car.gear == 4, "manual mode holds the gear at low revs (G%d, %d rpm)" % [car.gear, rpm_4th])
	await _tap("shift_down")
	await _drive(car, 15, stats)
	await _tap("shift_down")
	await _drive(car, 15, stats)
	var accel_2nd := await _measure_pull(car, stats)
	var rpm_2nd := car.engine_rpm
	_check(car.gear == 2, "shift-down key drops to 2nd (G%d)" % car.gear)
	_check(rpm_2nd > rpm_4th * 1.5, "downshift raises the revs (%d -> %d rpm)" % [rpm_4th, rpm_2nd])
	_check(accel_2nd > accel_4th * 1.5, "downshift restores the pull (%.2f -> %.2f m/s^2 at ~60 km/h)" % [accel_4th, accel_2nd])
	await _tap("toggle_gearbox")
	_check(car.automatic, "toggle key returns to the automatic")

	_check(stats.finite, "no NaN / inf in speeds, RPM or axle loads while driving the gears")
	_check(stats.max_step < 1.5, "no teleporting while driving the gears (largest step %.2f m)" % stats.max_step)
	_check(stats.min_rpm >= ArcadeCar.IDLE_RPM - 1.0 and stats.max_rpm <= ArcadeCar.REDLINE_RPM + 100.0, "RPM stays between idle and the limiter (%d..%d rpm)" % [stats.min_rpm, stats.max_rpm])
	_check(stats.min_load > 0.1 and stats.max_load < 0.9, "axle loads stay sane (%.2f..%.2f)" % [stats.min_load, stats.max_load])
	car.reset_to_spawn()
	await _step(5)


## The drivetrain is a chain of states (engine, clutch, axle wheel speeds), not
## a function of road speed: the engine free-revs and bounces off its limiter,
## a launch flares the revs on a slipping clutch and spins the rear wheels, a
## clutch dropped on a screaming engine keeps them spinning, engine braking
## depends on the gear, a gear change shows the engine on its own and the
## clutch catching it, and the wheels are drawn at the speed they really turn.
func _check_drivetrain_dynamics(car: ArcadeCar, rpm_label: Label) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var stats := _new_stats()

	# (1) Neutral: the throttle revs the engine, not the car. It runs up to the
	# limiter, the limiter cuts the fuel and the revs bounce against it; let go,
	# friction and the idle controller bring it back to idle.
	car.reset_to_spawn()
	await _step(10)
	await _tap("shift_down")
	await _step(roundi(ArcadeCar.SHIFT_TIME * 60.0) + 3)
	_check(car.gear == 0 and not car.automatic, "shift-down from 1st at a standstill selects neutral (G%d)" % car.gear)
	Input.action_press("accelerate")
	var frames_to_limiter := -1
	for frame in 120:
		await _drive(car, 1, stats)
		if car.engine_rpm >= ArcadeCar.REDLINE_RPM - 1.0:
			frames_to_limiter = frame + 1
			break
	_check(frames_to_limiter > 0 and frames_to_limiter * tick < FREE_REV_MAX_TIME, "throttle in neutral free-revs the engine to the limiter (%.2f s from idle, limit %.1f)" % [frames_to_limiter * tick, FREE_REV_MAX_TIME])
	var cuts := 0
	var was_cutting := car.limiter_cutting
	var bounce_low := INF
	var bounce_high := 0.0
	var tach_red := true
	for frame in 90:
		await _drive(car, 1, stats)
		if car.limiter_cutting and not was_cutting:
			cuts += 1
		was_cutting = car.limiter_cutting
		bounce_low = minf(bounce_low, car.engine_rpm)
		bounce_high = maxf(bounce_high, car.engine_rpm)
		tach_red = tach_red and rpm_label.get_theme_color("font_color") == rpm_label.get_parent().TACH_REDLINE_COLOR
	_check(cuts >= LIMITER_MIN_CUTS and bounce_high <= ArcadeCar.REDLINE_RPM + 1.0 and bounce_high - bounce_low > LIMITER_MIN_BOUNCE_RPM and bounce_low > ArcadeCar.LIMITER_RESUME_RPM - LIMITER_MIN_BOUNCE_RPM, "held there, the limiter cuts the fuel and the revs bounce against it (%d cuts in 1.5 s, %d..%d rpm)" % [cuts, bounce_low, bounce_high])
	_check(absf(car.forward_speed) < 0.001 and car.rear_omega == 0.0 and tach_red and rpm_label.text.ends_with("N M"), "the car stands still meanwhile, wheels at rest, the tach red ('%s', %.3f m/s)" % [rpm_label.text, car.forward_speed])

	# (2) Drop the clutch on it: 1st selected with the throttle still wide open.
	# The clutch comes in on an engine at the limiter and passes more than the
	# rear tyres hold: they spin, the clutch foot holds them at DRIVE_SLIP_RATIO,
	# and the revs stay far above what the road speed would make them until the
	# car has caught up. Dead straight all the while.
	await _tap("shift_up")
	var limiter_frames := 0
	var spin_frames := 0
	var least_tach_lead := INF
	var lock_frame := -1
	var spin_speed := 0.0
	for frame in 240:
		await _drive(car, 1, stats)
		var slipping_clutch := not car.clutch_locked and car.clutch_torque > 0.0
		if slipping_clutch and car.engine_rpm >= ArcadeCar.LIMITER_RESUME_RPM:
			limiter_frames += 1
		if slipping_clutch and car.rear_slip_ratio > WHEELSPIN_SLIP_RATIO:
			spin_frames += 1
			least_tach_lead = minf(least_tach_lead, car.engine_rpm - car.wheel_rpm(car.gear))
			spin_speed = car.forward_speed
		if lock_frame < 0 and car.clutch_locked:
			lock_frame = frame
	_check(car.gear == 1 and limiter_frames >= CLUTCH_DROP_MIN_LIMITER_FRAMES, "1st taken at full throttle: the engine is on the limiter against the slipping clutch (%d frames at %d rpm or more)" % [limiter_frames, ArcadeCar.LIMITER_RESUME_RPM])
	_check(spin_frames * tick > CLUTCH_DROP_MIN_SPIN_TIME and least_tach_lead > CLUTCH_DROP_MIN_TACH_LEAD, "... and the rear wheels spin on and on (%.2f s past a slip ratio of %.2f, up to %.1f m/s, the tach never less than %d rpm above the road's)" % [spin_frames * tick, WHEELSPIN_SLIP_RATIO, spin_speed, least_tach_lead])
	_check(lock_frame > 0 and car.clutch_locked and car.rear_slip_ratio < ArcadeCar.PEAK_SLIP_RATIO, "... until the car has caught up: the clutch locks and the tyres hook up (after %.2f s, slip ratio %.3f at the end)" % [lock_frame * tick, car.rear_slip_ratio])
	_check(absf(car.global_position.x) < 0.01 and absf(car.global_rotation.y) < 0.001, "... dead straight all the while (x = %.4f m)" % car.global_position.x)
	Input.action_release("accelerate")

	# ... and with 1st held by hand the limiter is where the car tops out: the
	# revs bounce against it under load too, the speed stays put.
	var speed_at_limiter := car.forward_speed
	cuts = 0
	was_cutting = car.limiter_cutting
	Input.action_press("accelerate")
	for frame in 180:
		await _drive(car, 1, stats)
		if car.limiter_cutting and not was_cutting:
			cuts += 1
		was_cutting = car.limiter_cutting
		if frame == 89:
			speed_at_limiter = car.forward_speed
	Input.action_release("accelerate")
	var first_gear_top := car.speed_at_rpm(1, ArcadeCar.REDLINE_RPM)
	_check(car.gear == 1 and cuts >= LIMITER_MIN_CUTS and absf(car.forward_speed - speed_at_limiter) < 0.3 and absf(car.forward_speed - first_gear_top) < 0.5, "flat out in 1st by hand the limiter holds the car at the top of the gear (%d cuts in 3 s, %.1f m/s, 1st tops out at %.1f)" % [cuts, car.forward_speed, first_gear_top])

	# Back in neutral, throttle closed: friction brings the revs down and the
	# idle controller catches them, no dip under idle, no hunting.
	await _tap("shift_down")
	var idle_frame := -1
	var lowest_rpm := INF
	for frame in 480:
		await _drive(car, 1, stats)
		lowest_rpm = minf(lowest_rpm, car.engine_rpm)
		if idle_frame < 0 and car.engine_rpm < ArcadeCar.IDLE_RPM + 5.0:
			idle_frame = frame
	_check(car.gear == 0 and idle_frame > 0 and idle_frame * tick < IDLE_RETURN_MAX_TIME and lowest_rpm > ArcadeCar.IDLE_RPM - 1.0 and absf(car.engine_rpm - ArcadeCar.IDLE_RPM) < 1.0, "let go in neutral the revs fall back to idle and stay there (from the limiter in %.2f s, lowest %.1f rpm, %.1f at the end)" % [idle_frame * tick, lowest_rpm, car.engine_rpm])

	# (3) The ordinary launch, automatic, flat out from rest: the revs flare to
	# LAUNCH_RPM on the slipping clutch while the road speed is still nothing,
	# and the rear wheels run ahead of the road, worked right up to the tyres'
	# peak, until the car has caught up and the clutch locks.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	var flare_rpm := 0.0
	var flare_road_rpm := 0.0
	var peak_slip := 0.0
	var wheels_lead := true
	lock_frame = -1
	for frame in 180:
		await _drive(car, 1, stats)
		if lock_frame < 0:
			if car.clutch_locked:
				lock_frame = frame
			elif car.engine_rpm - car.wheel_rpm(1) > flare_rpm - flare_road_rpm:
				flare_rpm = car.engine_rpm
				flare_road_rpm = car.wheel_rpm(1)
			# The slip ratio is the wheel speed against the road speed of the same
			# tick (forward_speed has this tick's acceleration in it already).
			wheels_lead = wheels_lead and car.rear_omega > 0.0 and car.rear_slip_ratio > 0.0
			peak_slip = maxf(peak_slip, car.rear_slip_ratio)
	_check(flare_rpm - flare_road_rpm > LAUNCH_MIN_FLARE_RPM and flare_rpm < ArcadeCar.LAUNCH_RPM + 100.0, "launch: the revs flare on the slipping clutch, the tach reads the engine, not the road (%d rpm where the road speed makes %d)" % [flare_rpm, flare_road_rpm])
	_check(wheels_lead and peak_slip > ArcadeCar.PEAK_SLIP_RATIO * LAUNCH_MIN_PEAK_SLIP_SHARE, "... the rear wheels turn faster than the road all the way, worked up to the tyres' peak (slip ratio up to %.3f, peak force at %.2f)" % [peak_slip, ArcadeCar.PEAK_SLIP_RATIO])
	_check(lock_frame > 0 and lock_frame * tick < LAUNCH_MAX_SLIP_TIME and car.clutch_locked and absf(car.engine_omega - car.rear_omega * ArcadeCar.GEAR_RATIOS[1] * ArcadeCar.FINAL_DRIVE) < 0.001, "... until the car has caught up: the clutch locks after %.2f s and engine and rear wheels turn as one shaft" % (lock_frame * tick))
	Input.action_release("accelerate")

	# (4) Engine braking is a matter of gear: lift at the same speed in 2nd and
	# in 4th. Nothing scripts the difference; it is the engine's friction (and
	# its revs) through the ratio.
	var decel_2nd := await _lift_off_decel(car, 2, stats)
	var decel_4th := await _lift_off_decel(car, 4, stats)
	_check(decel_2nd.locked and decel_4th.locked and absf(decel_2nd.entry_speed - decel_4th.entry_speed) < 0.5, "lift-off runs in 2nd and 4th start from the same speed, clutch locked (%.1f vs %.1f m/s)" % [decel_2nd.entry_speed, decel_4th.entry_speed])
	_check(decel_2nd.decel > decel_4th.decel * ENGINE_BRAKING_MIN_GEAR_RATIO and decel_4th.decel > ArcadeCar.COAST_DECEL, "lifting off slows the car harder in 2nd than in 4th (%.2f vs %.2f m/s^2 from %.0f km/h, at %d and %d rpm)" % [decel_2nd.decel, decel_4th.decel, decel_2nd.entry_speed * 3.6, decel_2nd.rpm, decel_4th.rpm])

	# (5) A gear change, flat out in the automatic: while the clutch is open the
	# engine is on its own and drifts down on its friction; then the clutch
	# catches it, dragging it down to the new gear's speed with more torque
	# than the engine makes, which goes into the car.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 600:
		if car.gear == 2:
			break
		await _drive(car, 1, stats)
	var rpm_at_shift := car.engine_rpm
	var drift_frames := 0
	var rpm_after_drift := rpm_at_shift
	var catch_torque := 0.0
	var catch_frames := 0
	var open_torque := 0.0
	for frame in 60:
		await _drive(car, 1, stats)
		if car.clutch_locked:
			break
		if car.clutch_engagement <= 0.0:
			drift_frames += 1
			rpm_after_drift = car.engine_rpm
			open_torque = maxf(open_torque, absf(car.clutch_torque))
		else:
			catch_frames += 1
			catch_torque = maxf(catch_torque, car.clutch_torque)
	var rpm_caught := car.engine_rpm
	var drift := rpm_at_shift - rpm_after_drift
	var chirp := car.rear_slip_ratio
	await _drive(car, 30, stats)
	_check(car.gear == 2 and drift_frames >= roundi(ArcadeCar.SHIFT_TIME * 60.0) - 1 and open_torque == 0.0 and drift > SHIFT_MIN_DRIFT_RPM and drift < SHIFT_MAX_DRIFT_RPM, "upshift: clutch open, the engine drifts down on its own friction (%d -> %d rpm in %.2f s, no torque through the clutch)" % [rpm_at_shift, rpm_after_drift, drift_frames * tick])
	_check(catch_torque > ArcadeCar.engine_torque(4500.0) and rpm_after_drift - rpm_caught > SHIFT_MIN_CATCH_RPM, "... then the clutch catches it (%d -> %d rpm in %.2f s, up to %d Nm through the clutch, the engine's best is %d)" % [rpm_after_drift, rpm_caught, catch_frames * tick, catch_torque, ArcadeCar.engine_torque(4500.0)])
	_check(chirp > ArcadeCar.PEAK_SLIP_RATIO and car.clutch_locked and car.rear_slip_ratio < ArcadeCar.PEAK_SLIP_RATIO and absf(car.engine_rpm - car.wheel_rpm(2)) < SHIFT_CAUGHT_RPM_TOLERANCE * car.wheel_rpm(2), "... the revs it gives up go into the car and chirp the rear tyres (slip ratio %.2f at the catch), hooked up again half a second on (%.3f, %d rpm on a road that makes %d)" % [chirp, car.rear_slip_ratio, car.engine_rpm, car.wheel_rpm(2)])
	Input.action_release("accelerate")

	# ... and on the way down the box the driver blips: clutch open, the revs
	# RISE towards what the lower gear will want, so the catch is small and the
	# rear tyres are not asked to spin the engine up.
	await _reach_speed(car, LIFT_OFF_SPEED)
	car.automatic = false
	car.shift_to(4)
	for frame in 120:
		await _drive(car, 1, stats)
		if car.clutch_locked and not car.is_shifting:
			break
	var rpm_in_4th := car.engine_rpm
	car.shift_to(3)
	var rpm_blipped := rpm_in_4th
	var deepest_slip := 0.0
	var hardest_decel := 0.0
	for frame in 60:
		await _drive(car, 1, stats)
		if car.clutch_engagement <= 0.0:
			rpm_blipped = car.engine_rpm
		deepest_slip = minf(deepest_slip, car.rear_slip_ratio)
		hardest_decel = minf(hardest_decel, car.longitudinal_accel)
	_check(car.gear == 3 and car.clutch_locked and rpm_blipped > rpm_in_4th + DOWNSHIFT_MIN_BLIP_RPM and absf(rpm_blipped - car.wheel_rpm(3)) < DOWNSHIFT_MAX_MISMATCH_RPM, "downshift: clutch open, the driver blips the revs up to the lower gear (%d -> %d rpm, 3rd wants %d)" % [rpm_in_4th, rpm_blipped, car.wheel_rpm(3)])
	_check(deepest_slip > -ArcadeCar.PEAK_SLIP_RATIO * 0.5 and hardest_decel > -DOWNSHIFT_MAX_DECEL, "... so the catch leaves the rear tyres alone (slip ratio no lower than %.3f, never more than %.2f m/s^2 of deceleration)" % [deepest_slip, -hardest_decel])

	# (6) The wheels are drawn at the speed they turn. Flat out from rest the
	# spinning rears visibly outrun the fronts; rolling, a wheel turns by wheel
	# speed x tick; under the handbrake the rears stand still and the fronts
	# roll on.
	var front_spinner := car.get_node("Wheels/FrontLeft/Spin") as Node3D
	var rear_spinner := car.get_node("Wheels/RearLeft/Spin") as Node3D
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	var front_turned := 0.0
	var rear_turned := 0.0
	var drawn_as_turning := true
	for frame in 90:
		var front_before := front_spinner.basis
		var rear_before := rear_spinner.basis
		await _drive(car, 1, stats)
		var front_step := _turned_about_x(front_before, front_spinner.basis)
		var rear_step := _turned_about_x(rear_before, rear_spinner.basis)
		front_turned += front_step
		rear_turned += rear_step
		# Rolling forwards is a negative rotation about +X.
		drawn_as_turning = drawn_as_turning and absf(front_step + car.front_omega * tick) < 0.0001 and absf(rear_step + car.rear_omega * tick) < 0.0001
	_check(drawn_as_turning, "the wheels are drawn turning at their axle's real speed, every tick of a launch")
	_check(rear_turned < front_turned * VISUAL_MIN_SPIN_LEAD and front_turned < 0.0, "... so spinning rear wheels visibly outrun the fronts (%.1f vs %.1f rad in 1.5 s)" % [-rear_turned, -front_turned])
	Input.action_release("accelerate")
	await _get_up_to_speed(car)
	Input.action_press("handbrake")
	await _step(10)
	var front_before := front_spinner.basis
	var rear_before := rear_spinner.basis
	await _step(1)
	_check(car.rear_omega == 0.0 and absf(_turned_about_x(rear_before, rear_spinner.basis)) < 0.000001 and _turned_about_x(front_before, front_spinner.basis) < -0.1, "handbraked rear wheels stand still while the fronts roll on (front %.2f rad a tick at %.0f km/h)" % [_turned_about_x(front_before, front_spinner.basis), car.speed_kmh])
	Input.action_release("handbrake")

	_check(stats.finite and stats.max_step < 1.5, "no NaN / inf / teleporting through the drivetrain checks (largest step %.2f m)" % stats.max_step)
	_check(stats.min_rpm >= ArcadeCar.IDLE_RPM - 1.0 and stats.max_rpm <= ArcadeCar.REDLINE_RPM + 100.0, "RPM stays between idle and the limiter through all of it (%d..%d rpm)" % [stats.min_rpm, stats.max_rpm])
	car.reset_to_spawn()
	await _step(5)


## Reaches LIFT_OFF_SPEED flat out, takes `in_gear` by hand, lets the clutch
## lock, then coasts for 1 s; returns the mean deceleration over that second
## [m/s^2], the speed and revs it started from and whether the clutch stayed
## locked.
func _lift_off_decel(car: ArcadeCar, in_gear: int, stats: Dictionary) -> Dictionary:
	await _reach_speed(car, LIFT_OFF_SPEED)
	car.automatic = false
	car.shift_to(in_gear)
	for frame in 120:
		await _drive(car, 1, stats)
		if car.clutch_locked and not car.is_shifting:
			break
	await _drive(car, 10, stats)
	var result := {"entry_speed": car.forward_speed, "rpm": car.engine_rpm, "locked": car.clutch_locked, "decel": 0.0}
	await _drive(car, 60, stats)
	result.locked = result.locked and car.clutch_locked and car.gear == in_gear
	result.decel = result.entry_speed - car.forward_speed
	return result


## How far a wheel spinner turned about its own X axis between two bases [rad],
## signed; good for less than half a turn.
func _turned_about_x(before: Basis, after: Basis) -> float:
	var step := before.inverse() * after
	return atan2(step.y.z, step.y.y)


## The floor under the spin tuning: flat out in a straight line the car must
## not wander, and a steering jab at speed must settle at once, never getting
## near the slip angle where the stability assist lets go.
func _check_high_speed_stability(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	await _step(900)
	_check(car.forward_speed > 40.0, "reaches high speed for the stability checks (%.1f m/s)" % car.forward_speed)
	_check(absf(car.global_position.x) < 0.01 and absf(car.global_rotation.y) < 0.001, "tracks dead straight flat out (x = %.4f m)" % car.global_position.x)

	var peak_slip_angle := 0.0
	Input.action_press("steer_left")
	for frame in 40:
		await physics_frame
		peak_slip_angle = maxf(peak_slip_angle, absf(atan2(car.lateral_speed, car.forward_speed)))
	Input.action_release("steer_left")
	var swings := 0
	var last_sign := 0.0
	for frame in 90:
		await physics_frame
		peak_slip_angle = maxf(peak_slip_angle, absf(atan2(car.lateral_speed, car.forward_speed)))
		if absf(car.yaw_rate) > 0.02:
			if last_sign != 0.0 and signf(car.yaw_rate) != last_sign:
				swings += 1
			last_sign = signf(car.yaw_rate)
	Input.action_release("accelerate")
	_check(peak_slip_angle < ArcadeCar.SPIN_COMMIT_ANGLE * 0.5, "a steering jab at speed stays far from a spin (peak slip angle %.1f deg)" % rad_to_deg(peak_slip_angle))
	_check(swings == 0, "no yaw oscillation after the jab (%d swings)" % swings)
	_check(absf(car.yaw_rate) < 0.01 and absf(car.lateral_speed) < 0.1, "the car settles within 1.5 s of the jab (yaw %.3f rad/s, slip %.2f m/s)" % [car.yaw_rate, car.lateral_speed])
	var heading := car.global_rotation.y
	await _step(60)
	_check(absf(angle_difference(heading, car.global_rotation.y)) < 0.001, "holds its new heading afterwards")


## The car goes by its tyres: what the throttle does in a corner, how a corner
## builds up, what the driven wheels and the brake bias change, and downforce.
func _check_force_dynamics(car: ArcadeCar) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

	# (a) The same corner, same entry speed, same steering: coasting against
	# wide-open throttle. The user's complaint was that the two felt the same.
	var coast := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, false, ArcadeCar.DrivenWheels.RWD)
	var power := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.RWD)
	var yaw_difference := absf(power.yaw - coast.yaw)
	var position_difference: float = power.end_position.distance_to(coast.end_position)
	_check(absf(power.entry_speed - coast.entry_speed) < 0.5, "power / coast corners start from the same speed (%.1f vs %.1f m/s)" % [power.entry_speed, coast.entry_speed])
	_check(yaw_difference > POWER_COAST_MIN_YAW_DIFFERENCE, "throttle changes the corner: heading gained %.2f rad on power vs %.2f coasting (differs by %.2f, margin %.2f)" % [power.yaw, coast.yaw, yaw_difference, POWER_COAST_MIN_YAW_DIFFERENCE])
	_check(position_difference > POWER_COAST_MIN_POSITION_DIFFERENCE, "throttle changes the line: the two runs end %.1f m apart (margin %.1f)" % [position_difference, POWER_COAST_MIN_POSITION_DIFFERENCE])
	_check(power.radius > coast.radius * 1.15, "on power the car runs a wider line than coasting (radius %.1f vs %.1f m)" % [power.radius, coast.radius])
	var again := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.RWD)
	_check(again.end_position == power.end_position and again.yaw == power.yaw, "the same corner driven twice ends in the same place, to the bit")

	# (b) Heading and velocity only meet through the tyres. Turning in, the
	# sideways acceleration has to BUILD: steering ramps, slip angles grow, the
	# mass answers; the nose leads and the direction of travel follows.
	var turn_in := await _turn_in_trace(car, CORNER_ENTRY_SPEED)
	var peak: float = turn_in.peak_accel
	_check(peak > 0.5 * gravity, "turning in builds real cornering force (peak %.1f m/s^2)" % peak)
	_check(turn_in.first_tick_accel < peak * TURN_IN_FIRST_TICK_SHARE, "no sideways jolt on the first tick of steering (%.2f m/s^2, peak %.1f)" % [turn_in.first_tick_accel, peak])
	_check(turn_in.ticks_to_half >= TURN_IN_MIN_BUILD_TICKS, "sideways acceleration builds over several ticks (%d ticks to half the peak, at least %d)" % [turn_in.ticks_to_half, TURN_IN_MIN_BUILD_TICKS])
	_check(turn_in.largest_rise < peak * 0.25, "it builds smoothly, no single tick adds a quarter of it (largest rise %.2f m/s^2)" % turn_in.largest_rise)
	_check(turn_in.heading_lead > 0.01, "the nose turns first and the direction of travel follows (nose leads by up to %.3f rad)" % turn_in.heading_lead)
	_check(turn_in.travel_turned > 0.1, "the direction of travel does follow (turned %.2f rad in 1 s)" % turn_in.travel_turned)
	_check(turn_in.peak_world_accel < MAX_PLAUSIBLE_ACCEL_G * gravity, "the velocity never changes faster than tyres and air can push (peak %.2f g, limit %.2f)" % [turn_in.peak_world_accel / gravity, MAX_PLAUSIBLE_ACCEL_G])

	# (e) The driven wheels give the car its character. 1st gear, moderate
	# speed, wide open in a corner: rear drive spends the rear tyres' grip and
	# the tail steps out; front drive spends the fronts' and the nose pushes
	# wide; all-wheel drive sits in between.
	var low_coast := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, false, ArcadeCar.DrivenWheels.RWD)
	var rwd := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.RWD)
	var fwd := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.FWD)
	var awd := await _steady_corner(car, LOW_GEAR_ENTRY_SPEED, LOW_GEAR_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.AWD)
	# was + 0.03 rad over coasting (measured 0.134 vs 0.034: the kinematic 1st gear
	# lit the rear tyres up at will) -> + 0.02 - measured 0.062 vs 0.035: a
	# quarter of the engine's torque in 1st now goes into its own inertia, the
	# rears run just under their peak (slip ratio ~0.08) instead of spinning, and
	# the tail still steps out 1.8 times as far as coasting. Grip use likewise:
	# was > 0.999 (spinning) -> > 0.9, measured 0.95; and the axle that is not
	# driven was < 0.01 -> < 0.1, measured 0.04 - 0.06: its wheels have inertia
	# now and it is the road that spins them up as the car gathers speed.
	_check(rwd.peak_rear_slip > low_coast.peak_rear_slip * 1.5 and rwd.peak_rear_slip > low_coast.peak_rear_slip + 0.02, "RWD: power in a low gear steps the tail out (peak rear slip angle %.3f rad vs %.3f coasting)" % [rwd.peak_rear_slip, low_coast.peak_rear_slip])
	_check(rwd.peak_rear_use > 0.9 and rwd.peak_front_use < 0.1, "RWD: the drive goes through the rear tyres only (grip use rear %.2f, front %.2f)" % [rwd.peak_rear_use, rwd.peak_front_use])
	_check(fwd.peak_front_use > 0.999 and fwd.peak_rear_use < 0.1, "FWD: the drive goes through the front tyres only (grip use front %.2f, rear %.2f)" % [fwd.peak_front_use, fwd.peak_rear_use])
	_check(fwd.yaw < low_coast.yaw * 0.9 and fwd.yaw < rwd.yaw * 0.9, "FWD: power pushes the nose wide (heading gained %.2f rad vs %.2f coasting, %.2f RWD)" % [fwd.yaw, low_coast.yaw, rwd.yaw])
	_check(fwd.peak_rear_slip < rwd.peak_rear_slip * 0.7, "FWD: the tail stays planted on power (peak rear slip angle %.3f rad vs %.3f RWD)" % [fwd.peak_rear_slip, rwd.peak_rear_slip])
	_check(awd.peak_front_use > 0.1 and awd.peak_rear_use > 0.1, "AWD: both axles drive (grip use front %.2f, rear %.2f)" % [awd.peak_front_use, awd.peak_rear_use])
	_check(awd.peak_rear_slip < rwd.peak_rear_slip * 0.7, "AWD: with the torque shared the tail stays in line (peak rear slip angle %.3f rad vs %.3f RWD)" % [awd.peak_rear_slip, rwd.peak_rear_slip])
	# In 1st all three have more torque than tyre. One gear up, where the tyres
	# can take it, the balance lines up: FWD pushes widest, RWD turns most.
	var fwd_second := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.FWD)
	var awd_second := await _steady_corner(car, CORNER_ENTRY_SPEED, POWER_CORNER_FRAMES, true, ArcadeCar.DrivenWheels.AWD)
	_check(fwd_second.yaw < awd_second.yaw and awd_second.yaw < power.yaw, "in 2nd AWD sits between the two (heading gained: FWD %.2f, AWD %.2f, RWD %.2f rad)" % [fwd_second.yaw, awd_second.yaw, power.yaw])
	_check(awd.speed_gain > rwd.speed_gain and awd.speed_gain > fwd.speed_gain, "AWD puts the most power down out of the corner (+%.1f m/s vs RWD +%.1f, FWD +%.1f)" % [awd.speed_gain, rwd.speed_gain, fwd.speed_gain])
	var rwd_launch := await _launch(car, ArcadeCar.DrivenWheels.RWD)
	var fwd_launch := await _launch(car, ArcadeCar.DrivenWheels.FWD)
	_check(fwd_launch.speed < rwd_launch.speed * 0.8, "FWD launch is traction-limited: load moves off the driven axle (%.1f m/s after 2 s vs %.1f RWD)" % [fwd_launch.speed, rwd_launch.speed])
	_check(fwd_launch.driven_load < rwd_launch.driven_load, "... the driven axle carries %.0f N launching FWD, %.0f N RWD" % [fwd_launch.driven_load, rwd_launch.driven_load])
	for run: Dictionary in [coast, power, low_coast, rwd, fwd, awd, fwd_second, awd_second]:
		_check(run.finite and run.max_step < 1.5, "no NaN / inf / teleporting in the %s corner (largest step %.2f m)" % [run.label, run.max_step])
	_check(car.driven_wheels == ArcadeCar.DRIVEN_WHEELS, "the car is back on its own driven wheels")

	# Brake bias: a full stop in a straight line has the fronts at their limit
	# (ABS) and the rears under theirs.
	await _get_up_to_speed(car)
	Input.action_press("brake")
	await _step(30)
	_check(car.front_traction_use > 0.999 and car.rear_traction_use < 0.95 and car.rear_traction_use > 0.3, "brake bias: fronts at the limit, rears working under theirs (grip use front %.2f, rear %.2f)" % [car.front_traction_use, car.rear_traction_use])
	_check(is_equal_approx(car.front_slip_ratio, -ArcadeCar.ABS_SLIP_RATIO) and car.rear_slip_ratio > -ArcadeCar.PEAK_SLIP_RATIO, "ABS holds the front wheels, the rears never reach their peak (slip ratio front %.3f, rear %.3f)" % [car.front_slip_ratio, car.rear_slip_ratio])
	Input.action_release("brake")

	# Downforce: at speed the axles carry more than the car weighs, the rear
	# more so than the front.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	await _step(900)
	Input.action_release("accelerate")
	await _step(30)
	# was ArcadeCar.CAR_MASS x gravity, the one mass the car had -> what the car
	# weighs now (total_mass(): the base car, the fuel left in the tank, payload).
	var weight := car.total_mass() * gravity
	# The road moves load in and out of the wheels tick by tick, so what the
	# axles carry and what downforce should add are both averaged over
	# DOWNFORCE_AVERAGE_FRAMES before they are compared.
	var carried := 0.0
	var expected := 0.0
	for frame in DOWNFORCE_AVERAGE_FRAMES:
		await physics_frame
		carried += (car.front_axle_load + car.rear_axle_load) / DOWNFORCE_AVERAGE_FRAMES
		expected += ArcadeCar.DOWNFORCE_COEFF * car.forward_speed * car.forward_speed / DOWNFORCE_AVERAGE_FRAMES
	_check(absf(carried - weight - expected) < DOWNFORCE_TOLERANCE and expected > 0.04 * weight, "downforce adds to the axle loads at speed (+%.0f N at %.0f km/h, the car weighs %.0f N)" % [carried - weight, car.speed_kmh, weight])
	car.reset_to_spawn()
	await _step(5)


## (c) The low-speed blend: parking stays precise, the car stands still on the
## brake with the wheels turned, reverse still takes a fresh press, and there
## is no step in the steering on the way up through the blend.
func _check_low_speed_blend(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 120:
		if car.forward_speed >= CRAWL_SPEED:
			break
		await physics_frame
	Input.action_release("accelerate")
	Input.action_press("steer_left")
	await _step(60)
	# Rolling round at full lock: the turning circle of the wheel angle, no slip.
	var turning_radius := car.forward_speed / car.yaw_rate
	var geometric_radius := 2.0 * ArcadeCar.AXLE_DISTANCE / tan(ArcadeCar.MAX_STEER_LOCK)
	_check(car.forward_speed > ArcadeCar.LOW_SPEED_BLEND_START and car.forward_speed < ArcadeCar.LOW_SPEED_BLEND_END, "crawling inside the low-speed blend (%.1f m/s)" % car.forward_speed)
	_check(is_equal_approx(car.wheel_angle, ArcadeCar.MAX_STEER_LOCK), "full lock reaches the wheels at parking pace (%.2f rad)" % car.wheel_angle)
	_check(absf(turning_radius - geometric_radius) < geometric_radius * 0.1, "crawl steering rolls round the turning circle (radius %.2f m, geometry says %.2f)" % [turning_radius, geometric_radius])
	_check(absf(car.rear_slip_angle) < 0.02, "... with no slip at the rear axle (%.3f rad)" % car.rear_slip_angle)

	# Brake to a stop with the wheels still turned, and hold: no creep, no yaw.
	Input.action_press("brake")
	await _step(60)
	var held_position := car.global_position
	var held_yaw := car.global_rotation.y
	await _step(120)
	_check(car.global_position.distance_to(held_position) < 0.005 and absf(angle_difference(held_yaw, car.global_rotation.y)) < 0.001, "holds still on the brake with the wheels turned (moved %.4f m, turned %.5f rad in 2 s)" % [car.global_position.distance_to(held_position), absf(angle_difference(held_yaw, car.global_rotation.y))])
	_check(not car.reverse_engaged, "the held brake still never engages reverse")
	Input.action_release("brake")
	await _step(5)
	Input.action_press("brake")
	await _step(60)
	_check(car.reverse_engaged and car.forward_speed < -1.0, "a fresh brake press at the stop still reverses, steering held (%.1f m/s)" % car.forward_speed)
	_check(car.yaw_rate < -0.05, "... and the same lock swings the nose the other way in reverse (yaw %.2f rad/s)" % car.yaw_rate)
	Input.action_release("brake")
	Input.action_release("steer_left")

	# Up through the blend with the steering held: geometry hands over to the
	# tyres without a step in the yaw rate.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("steer_left")
	Input.action_press("accelerate")
	var largest_yaw_step := 0.0
	var yaw_rate_before := 0.0
	var finite := true
	for frame in 150:
		await physics_frame
		largest_yaw_step = maxf(largest_yaw_step, absf(car.yaw_rate - yaw_rate_before))
		yaw_rate_before = car.yaw_rate
		finite = finite and is_finite(car.yaw_rate) and is_finite(car.lateral_speed) and car.global_position.is_finite()
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	_check(car.forward_speed > ArcadeCar.LOW_SPEED_BLEND_END + 2.0, "accelerated up through the blend and out of it (%.1f m/s)" % car.forward_speed)
	_check(largest_yaw_step < 0.06 and finite, "no step in the yaw rate on the way through the blend (largest change %.3f rad/s in a tick)" % largest_yaw_step)
	car.reset_to_spawn()
	await _step(5)


## Raw steering: the front wheel angle is the (smoothed) steering input times
## MAX_STEER_LOCK, at any speed, in any slide, either way round - nothing but
## the driver turns the wheels. The user's complaints were wheels that turned
## by themselves, barely moved at speed, and stuck on one side of centre under
## the handbrake; slip-sensitive steering and the slide feed did all three.
func _check_raw_steering(car: ArcadeCar) -> void:
	var lock := ArcadeCar.MAX_STEER_LOCK
	# was the steer input easing to the key at STEER_RESPONSE -> the driver's
	# hands winding the 900-degree wheel on at STEERING_HAND_SPEED; the front
	# wheels are the steering wheel through the rack.
	var wheel_lock := ArcadeCar.STEERING_WHEEL_LOCK_DEG
	var locks_per_tick := ArcadeCar.STEERING_HAND_SPEED / wheel_lock / Engine.physics_ticks_per_second
	var ticks_to_lock := ceili(1.0 / locks_per_tick)

	# (1) The identity at speed: on the way to full lock the wheels follow the
	# steering ramp and nothing else, then stand at full lock to the bit.
	var forward_yaw_rate := 0.0
	for entry_speed in RAW_STEER_SPEEDS:
		await _reach_speed(car, entry_speed)
		var speed_kmh := car.speed_kmh
		var identity := true
		var rack := true
		var ramping := true
		var lock_frame := -1
		Input.action_press("steer_left")
		for frame in RAW_STEER_HOLD_FRAMES:
			await physics_frame
			identity = identity and car.wheel_angle == car.steer * lock and car.steer == car.steering_wheel_deg / wheel_lock
			rack = rack and is_equal_approx(car.wheel_angle, deg_to_rad(car.steering_wheel_deg) / ArcadeCar.STEERING_RATIO)
			if lock_frame < 0 and car.wheel_angle == lock:
				lock_frame = frame + 1
			if frame < ticks_to_lock - 1:
				var ramp_share := (frame + 1) * locks_per_tick
				ramping = ramping and car.wheel_angle > 0.0 and is_equal_approx(car.steering_wheel_deg, ramp_share * wheel_lock) and car.wheel_angle <= ramp_share * lock + 0.000001
		_check(ramping, "from %.0f km/h the steering wheel is wound on at the driver's hand speed (%.0f degrees a second), the front wheels with it, never ahead of it" % [speed_kmh, ArcadeCar.STEERING_HAND_SPEED])
		_check(identity, "... the front wheels being the steering wheel's share of its lock x MAX_STEER_LOCK on every tick, to the bit")
		_check(rack, "... which is the steering wheel's angle through the rack: front = wheel / %.1f" % ArcadeCar.STEERING_RATIO)
		_check(lock_frame == ticks_to_lock and car.steering_wheel_deg == wheel_lock, "... centre to lock takes the hands %.2f s (%d ticks), the wheel at %.0f degrees" % [lock_frame / 60.0, lock_frame, car.steering_wheel_deg])
		_check(car.wheel_angle == lock, "... full lock reaches the wheels at that speed, to the bit (%.2f rad)" % car.wheel_angle)
		_check(absf(car.front_slip_angle) > ArcadeCar.FRONT_PEAK_SLIP_ANGLE, "... more than the front tyres can use: they scrub and the car pushes wide (front slip angle %.2f rad, peak %.2f)" % [absf(car.front_slip_angle), ArcadeCar.FRONT_PEAK_SLIP_ANGLE])
		forward_yaw_rate = car.yaw_rate
		Input.action_release("steer_left")

	# (2) Lock held into a slide stays on the wheels. A tap of the handbrake
	# going in, the key held throughout: once the handbrake is let go and the
	# tail is out past SLIDE_CATCH_ANGLE, the slide feed used to take the lock
	# off the wheels and trail them into line. Now they stay where the key
	# puts them, every tick.
	await _get_up_to_speed(car)
	Input.action_press("steer_left")
	Input.action_press("handbrake")
	var held := true
	var slide_frames := 0
	var slide_held := true
	var peak_slide_angle := 0.0
	var rolling_forward := true
	for frame in 150:
		if frame == HANDBRAKE_TAP_FRAMES:
			Input.action_release("handbrake")
		await physics_frame
		rolling_forward = rolling_forward and car.forward_speed > 0.0
		if frame >= RAW_STEER_HOLD_FRAMES:
			held = held and car.wheel_angle == lock
		if frame >= HANDBRAKE_TAP_FRAMES + RAW_STEER_HOLD_FRAMES and absf(car.rear_slip_angle) > ArcadeCar.SLIDE_CATCH_ANGLE:
			slide_frames += 1
			slide_held = slide_held and car.wheel_angle == lock
			peak_slide_angle = maxf(peak_slide_angle, absf(car.rear_slip_angle))
	_check(slide_frames >= RAW_STEER_MIN_SLIDE_FRAMES and rolling_forward, "a handbrake tap with the lock held slides the car, handbrake long let go (%d ticks past SLIDE_CATCH_ANGLE, peak %.2f rad)" % [slide_frames, peak_slide_angle])
	_check(slide_held, "lock held into the slide stays on the wheels on every one of those ticks: no easing off, no trailing into line")
	_check(held, "... and on every other tick of the 2.5 s the key was down")
	Input.action_release("steer_left")
	await _step(RAW_STEER_HOLD_FRAMES)
	_check(car.steer == 0.0 and car.wheel_angle == 0.0 and car.steering_wheel_deg == 0.0, "let go, the steering springs back to centre (wheel angle %.3f rad)" % car.wheel_angle)

	# (3) Under the handbrake the wheels go lock to lock. The complaint: "go
	# straight at speed, handbrake, steer right or left - the wheel gets stuck,
	# can't steer to the opposite side more than straightening."
	await _get_up_to_speed(car)
	Input.action_press("handbrake")
	Input.action_press("steer_left")
	var identity := true
	peak_slide_angle = 0.0
	for frame in RAW_STEER_HOLD_FRAMES:
		await physics_frame
		identity = identity and car.wheel_angle == car.steer * lock
	_check(car.wheel_angle == lock, "handbrake held at speed: full lock one way reaches the wheels (%.2f rad)" % car.wheel_angle)
	Input.action_release("steer_left")
	Input.action_press("steer_right")
	var swap_frame := -1
	for frame in RAW_STEER_SWAP_FRAMES:
		await physics_frame
		identity = identity and car.wheel_angle == car.steer * lock
		if swap_frame < 0 and car.steering_wheel_deg == -wheel_lock:
			swap_frame = frame + 1
		peak_slide_angle = maxf(peak_slide_angle, absf(car.rear_slip_angle))
	_check(swap_frame / 60.0 > LOCK_TO_LOCK_MIN_TIME and swap_frame / 60.0 < LOCK_TO_LOCK_MAX_TIME, "... lock to lock is 900 degrees of steering wheel and takes the hands %.2f s (%d ticks)" % [swap_frame / 60.0, swap_frame])
	_check(car.wheel_angle == -lock, "... and full lock the other way, straight through centre (%.2f rad, the tail %.2f rad out, %.0f km/h)" % [car.wheel_angle, car.rear_slip_angle, car.speed_kmh])
	_check(peak_slide_angle > ArcadeCar.SLIDE_CATCH_ANGLE and car.forward_speed > 0.0, "... in a real slide (peak rear slip angle %.2f rad)" % peak_slide_angle)
	_check(identity, "... the wheels being the steering wheel's share of its lock x MAX_STEER_LOCK on every tick of it, to the bit")
	Input.action_release("steer_right")
	Input.action_release("handbrake")

	# (4) Rolling backwards the wheels stand at the same angle for the same
	# key: it is the car that answers the other way round, not the steering.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("brake")
	for frame in 600:
		if car.forward_speed <= -5.0:
			break
		await physics_frame
	Input.action_release("brake")
	var reverse_speed := car.forward_speed
	Input.action_press("steer_left")
	await _step(RAW_STEER_HOLD_FRAMES)
	_check(car.reverse_engaged and reverse_speed <= -5.0 and car.forward_speed < -1.0, "rolling backwards for the reverse steering check (%.1f m/s)" % reverse_speed)
	_check(car.wheel_angle == lock, "in reverse the same key puts the same full lock on the wheels, to the bit (%.2f rad)" % car.wheel_angle)
	_check(forward_yaw_rate > 0.05 and car.yaw_rate < -0.05, "... and swings the nose the other way (yaw %.2f rad/s, %.2f rolling forwards)" % [car.yaw_rate, forward_yaw_rate])
	Input.action_release("steer_left")
	Input.action_press("steer_right")
	await _step(RAW_STEER_SWAP_FRAMES)
	_check(car.forward_speed < -1.0 and car.wheel_angle == -lock and car.yaw_rate > 0.05, "... the same with the other key: the wheels point where they are steered, the car answers the other way round (%.2f rad, yaw %.2f rad/s)" % [car.wheel_angle, car.yaw_rate])
	Input.action_release("steer_right")
	car.reset_to_spawn()
	await _step(5)


## Ground texture, course queries and drive-through cones.
func _check_course(pad: TestPad, car: ArcadeCar) -> void:
	_check(pad != null, "test pad is a TestPad")
	if pad == null:
		return

	# The asphalt: a real texture on the ground, visibly non-uniform, and the
	# same pixels every time.
	var material := pad.get_ground_material()
	var ground_mesh := pad.get_node_or_null("Ground/MeshInstance3D") as MeshInstance3D
	_check(material != null and material.albedo_texture != null, "ground material has an albedo texture")
	_check(ground_mesh != null and ground_mesh.material_override == material, "ground mesh uses the asphalt material")
	var image := pad.get_ground_image()
	_check(image != null and image.get_width() == TestPad.GROUND_TEXTURE_SIZE, "ground texture image exists (%d px)" % (image.get_width() if image != null else 0))
	if image != null:
		var distinct := {}
		var darkest := 1.0
		var brightest := 0.0
		for i in 64:
			var pixel := image.get_pixel((i * 37) % image.get_width(), (i * 101) % image.get_height())
			distinct[pixel.to_rgba32()] = true
			darkest = minf(darkest, pixel.get_luminance())
			brightest = maxf(brightest, pixel.get_luminance())
		_check(distinct.size() >= 16, "ground texture is non-uniform (%d distinct colours in 64 samples)" % distinct.size())
		_check(brightest - darkest > 0.1, "ground texture has visible contrast (luminance %.2f..%.2f)" % [darkest, brightest])
		var again := AsphaltTexture.build_image(TestPad.GROUND_TEXTURE_SIZE, TestPad.GROUND_TEXTURE_SEED)
		_check(again.get_data() == image.get_data(), "ground texture is deterministic (same seed, same pixels)")
	var ticks := pad.get_node_or_null("MotionTicks") as MultiMeshInstance3D
	_check(ticks != null and ticks.multimesh.instance_count > 1000, "motion ticks cover the ground")

	# What the missions ask the pad.
	var slalom := pad.get_cone_positions(TestPad.GROUP_SLALOM)
	_check(slalom.size() == TestPad.SLALOM_CONE_COUNT and slalom == TestPad.slalom_cone_positions(), "pad reports its %d slalom cones" % slalom.size())
	_check(root.get_tree().get_nodes_in_group(TestPad.GROUP_SLALOM).size() == slalom.size(), "slalom cones are in their node group")
	var circle := TestPad.skid_circle()
	var inner := pad.get_cone_positions(TestPad.GROUP_SKID_INNER)
	var outer := pad.get_cone_positions(TestPad.GROUP_SKID_OUTER)
	var on_circle := not inner.is_empty() and not outer.is_empty()
	for cone in inner:
		on_circle = on_circle and is_equal_approx(cone.distance_to(circle.centre), circle.inner_radius)
	for cone in outer:
		on_circle = on_circle and is_equal_approx(cone.distance_to(circle.centre), circle.outer_radius)
	_check(on_circle, "pad reports the skid circle cones (%d inner, %d outer)" % [inner.size(), outer.size()])
	_check(pad.get_cone_positions(TestPad.GROUP_STOP_BOX).size() == 4, "stop box has its four corner cones")

	# Cones never block: drive straight over the first slalom cone.
	var cone := slalom[0]
	var spawn := car.get_spawn_transform()
	car.reset_to(Transform3D(spawn.basis, Vector3(cone.x, spawn.origin.y, cone.z + 40.0)))
	pad.reset_cones()
	await _step(10)
	Input.action_press("accelerate")
	var speed_at_cone := 0.0
	var slowed := false
	for frame in 300:
		var speed_before := car.forward_speed
		await physics_frame
		if car.forward_speed < speed_before - 0.05:
			slowed = true
		if speed_at_cone == 0.0 and car.global_position.z <= cone.z:
			speed_at_cone = car.forward_speed
		if car.global_position.z < cone.z - 10.0:
			break
	Input.action_release("accelerate")
	_check(car.global_position.z < cone.z - 10.0 and speed_at_cone > 5.0, "car drives through a cone (%.1f m/s at the cone)" % speed_at_cone)
	_check(not slowed and absf(car.global_position.x - cone.x) < 0.01, "the cone does not slow or deflect the car (x off by %.3f m)" % absf(car.global_position.x - cone.x))
	_check(pad.is_cone_toppled(TestPad.GROUP_SLALOM, cone) and pad.get_toppled_count(TestPad.GROUP_SLALOM) == 1, "the cone it hit topples (and only that one)")
	pad.reset_cones()
	_check(pad.get_toppled_count(TestPad.GROUP_SLALOM) == 0, "resetting stands the cones back up")
	car.reset_to_spawn()
	await _step(5)


## The road profile by itself: pure, mean-neutral, gentle, level where the
## certifications run, and one road shared by pad and car.
func _check_road_profile(pad: TestPad, car: ArcadeCar) -> void:
	var road := pad.road_profile
	_check(road != null and road == car.road_profile, "pad and car drive on the same road profile")
	if road == null:
		return

	# Pure: the same point twice, and from a second road built from the same
	# constants, gives the same height to the last bit.
	var twin := RoadProfile.new()
	var pure := true
	for i in 200:
		var x := -300.0 + 7.3 * i
		var z := 140.0 - 6.1 * i
		var height := road.sample_height(x, z)
		pure = pure and height == road.sample_height(x, z) and height == twin.sample_height(x, z) and height == pad.sample_height(x, z)
		pure = pure and road.elevation_height(x, z) == pad.elevation_height(x, z)
	_check(pure, "road height is a pure function of (x, z): same point, same height, on every instance")

	# Micro-bumps: no DC part, but really there, and inside their bound.
	var micro_sum := 0.0
	var micro_squares := 0.0
	var micro_peak := 0.0
	var samples := 4000
	for i in samples:
		var micro := road.micro_height(0.0, -0.05 * i)
		micro_sum += micro
		micro_squares += micro * micro
		micro_peak = maxf(micro_peak, absf(micro))
	var micro_mean := micro_sum / samples
	_check(absf(micro_mean) < MICRO_MEAN_TOLERANCE, "micro-bumps are mean-neutral over a 200 m lane strip (mean %.3f mm, limit %.1f mm)" % [micro_mean * 1000.0, MICRO_MEAN_TOLERANCE * 1000.0])
	_check(sqrt(micro_squares / samples) > MICRO_MIN_RMS and micro_peak <= RoadProfile.MICRO_AMPLITUDE, "micro-bumps are there and bounded (RMS %.1f mm, peak %.1f mm of at most %.0f mm)" % [sqrt(micro_squares / samples) * 1000.0, micro_peak * 1000.0, RoadProfile.MICRO_AMPLITUDE * 1000.0])

	# Elevation along the lane: gentle, worth the name, and a function of z
	# only across the lane band.
	var steepest := 0.0
	var lowest := 0.0
	var highest := 0.0
	var side_pull := 0.0
	for i in 1451:
		var z := 150.0 - i
		var height := road.elevation_height(0.0, z)
		steepest = maxf(steepest, road.elevation_slope(0.0, z))
		lowest = minf(lowest, height)
		highest = maxf(highest, height)
		for x: float in [-RoadProfile.LANE_BAND_HALF_WIDTH, -2.5, 2.5, RoadProfile.LANE_BAND_HALF_WIDTH]:
			side_pull = maxf(side_pull, absf(road.elevation_height(x, z) - height))
	_check(steepest <= RoadProfile.MAX_SLOPE, "the lane's elevation stays gentle (steepest %.2f %%, limit %.1f %%)" % [steepest * 100.0, RoadProfile.MAX_SLOPE * 100.0])
	_check(highest - lowest > LANE_MIN_ELEVATION_RANGE and highest <= 1.5 and lowest >= -1.5, "the lane rises and falls (%.2f m .. %.2f m)" % [lowest, highest])
	_check(side_pull == 0.0, "across the lane band the elevation depends on z only (largest difference %.6f m)" % side_pull)

	# The four flat zones: exactly level, sampled out to a centimetre short of
	# their radius (on the radius itself rounding decides).
	var circle := TestPad.skid_circle()
	var box := TestPad.stop_box()
	var start_zone := 0.0
	var stop_zone := 0.0
	var skid_zone := 0.0
	var slalom_zone := 0.0
	for i in 64:
		var around := Vector3(cos(i * 0.7), 0.0, sin(i * 0.7))
		var reach := (i % 8 + 1) / 8.0
		var at_start := Vector3(0.0, 0.0, TestPad.START_LINE_Z) + around * (RoadProfile.START_ZONE_RADIUS - 0.01) * reach
		var at_stop: Vector3 = box.centre + around * (RoadProfile.STOP_ZONE_RADIUS - 0.01) * reach
		var at_skid: Vector3 = circle.centre + around * (RoadProfile.SKID_ZONE_RADIUS - 0.01) * reach
		start_zone = maxf(start_zone, absf(road.elevation_height(at_start.x, at_start.z)))
		stop_zone = maxf(stop_zone, absf(road.elevation_height(at_stop.x, at_stop.z)))
		skid_zone = maxf(skid_zone, absf(road.elevation_height(at_skid.x, at_skid.z)))
	for cone in TestPad.slalom_cone_positions():
		for side: float in [-1.0, -0.5, 0.0, 0.5, 1.0]:
			slalom_zone = maxf(slalom_zone, absf(road.elevation_height(cone.x + side * (RoadProfile.SLALOM_ZONE_BUFFER - 0.01), cone.z)))
	_check(start_zone == 0.0, "the start zone is level (largest elevation %.6f m within %.0f m of the line)" % [start_zone, RoadProfile.START_ZONE_RADIUS])
	_check(stop_zone == 0.0, "the stop box zone is level (largest elevation %.6f m within %.0f m of the box)" % [stop_zone, RoadProfile.STOP_ZONE_RADIUS])
	_check(slalom_zone == 0.0, "the slalom line is level (largest elevation %.6f m within %.0f m of the cones)" % [slalom_zone, RoadProfile.SLALOM_ZONE_BUFFER])
	_check(skid_zone == 0.0, "the skid pad is level (largest elevation %.6f m within %.0f m of its centre)" % [skid_zone, RoadProfile.SKID_ZONE_RADIUS])


## What each front and each rear wheel would carry on a level road right now
## [N], front then rear: a wheel's baseline, worked out here from rigid-body
## statics, not read off the car. Half the axle's static share and downforce
## share, and the weight the tyre forces move between the axles: they act at
## the road, CG_HEIGHT under the centre of mass, and accelerate the car and
## hold it against the air (which pushes at the height of the centre of mass).
# was read off the car (weight x car.front / rear_load_fraction, the output of
# its weight-transfer formula) -> the formula itself, as a cross-check: the car
# has no such formula any more, its load fractions are what the springs carry,
# road and all, and the springs have to come out on this by themselves.
func _wheel_baselines(car: ArcadeCar) -> Array[float]:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	# was ArcadeCar.CAR_MASS, here and in the transfer -> car.total_mass(), the
	# mass the car's forces and weights work with (fuel and payload in).
	var weight := car.total_mass() * gravity
	var speed := car.forward_speed
	var downforce := ArcadeCar.DOWNFORCE_COEFF * speed * speed
	var air_drag := 0.5 * ArcadeCar.AIR_DENSITY * ArcadeCar.DRAG_COEFF * ArcadeCar.FRONTAL_AREA * speed * absf(speed)
	var transfer := (car.total_mass() * car.longitudinal_accel + air_drag) * ArcadeCar.CG_HEIGHT / (2.0 * ArcadeCar.AXLE_DISTANCE)
	return [
		(weight * (1.0 - ArcadeCar.REAR_WEIGHT_FRACTION) + downforce * ArcadeCar.AERO_BALANCE_FRONT - transfer) * 0.5,
		(weight * ArcadeCar.REAR_WEIGHT_FRACTION + downforce * (1.0 - ArcadeCar.AERO_BALANCE_FRONT) + transfer) * 0.5,
	]


## The shape of the tyre curve (the rubber pass): a smooth rise into the peak,
## a wide top, falling all the way from there, never under its slide grip, and
## a rolling rear that has a limit to go over but holds on better than the
## front.
func _check_tyre_curve(car: ArcadeCar) -> void:
	var front_slide := ArcadeCar.TYRE_SLIDE_GRIP
	var rear_slide := ArcadeCar.REAR_TYRE_SLIDE_GRIP
	var rising := true
	var falling := true
	for i in 100:
		var below := car._tyre_curve(i * 0.01, front_slide)
		var above := car._tyre_curve((i + 1) * 0.01, front_slide)
		rising = rising and above > below
		var past := car._tyre_curve(1.0 + i * 0.1, front_slide)
		var further := car._tyre_curve(1.0 + (i + 1) * 0.1, front_slide)
		falling = falling and further <= past and further >= front_slide
	_check(rising and car._tyre_curve(1.0, front_slide) == 1.0, "the tyre curve rises all the way into its peak (1.000 at the peak slip angle)")
	_check(falling and car._tyre_curve(2.0, front_slide) > TYRE_WIDE_TOP_MIN_SHARE, "... and eases off it over a wide top, down to its slide grip and never under (%.3f of the peak at twice the peak slip angle, %.2f sliding)" % [car._tyre_curve(2.0, front_slide), front_slide])
	_check(rear_slide < 1.0 and rear_slide > front_slide and car._tyre_curve(4.0, rear_slide) < car._tyre_curve(1.5, rear_slide), "... the rolling rear has a limit to go over too, and holds on better past it than the front (%.2f vs %.2f sliding)" % [rear_slide, front_slide])


## The car over bumps at speed: at rest the springs are at rest; flat out down
## the straight every wheel load swings with the road, the axle loads keep
## their mean, the body rides the elevation on its springs.
func _check_road_feel(pad: TestPad, car: ArcadeCar) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	car.reset_to_spawn()
	# was ArcadeCar.CAR_MASS x gravity, worked out before the reset -> the weight
	# of the car as the reset leaves it (total_mass(), the tank full): the static
	# shares are held to the hundredth of a Newton standing (ten ticks of idling
	# burn 0.0002 N of fuel) and to the bit at the reset further down.
	var weight := car.total_mass() * gravity
	var static_loads: Array[float] = [weight * (1.0 - ArcadeCar.REAR_WEIGHT_FRACTION) * 0.5, weight * ArcadeCar.REAR_WEIGHT_FRACTION * 0.5]
	await _step(10)
	var at_rest := car.wheel_loads.size() == 4
	for i in car.wheel_loads.size():
		at_rest = at_rest and absf(car.wheel_loads[i] - static_loads[i / 2]) < 0.01
	_check(at_rest, "standing still every wheel carries its static share (front %.1f N, rear %.1f N)" % [car.wheel_loads[0], car.wheel_loads[2]])

	var stats := _new_stats()
	Input.action_press("accelerate")
	await _drive(car, ROAD_FEEL_RUN_UP_FRAMES, stats)
	var deviation_sum: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var deviation_squares: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var loads_finite := true
	var off_floor := true
	var ground_gap := 0.0
	var lowest_gap := INF
	var most_travel := 0.0
	var highest := 0.0
	for frame in ROAD_FEEL_SAMPLE_FRAMES:
		await _drive(car, 1, stats)
		var baselines := _wheel_baselines(car)
		for i in 4:
			var deviation := car.wheel_loads[i] - baselines[i / 2]
			deviation_sum[i] += deviation
			deviation_squares[i] += deviation * deviation
			loads_finite = loads_finite and is_finite(car.wheel_loads[i]) and car.wheel_loads[i] >= 0.0
		off_floor = off_floor and not car.is_on_floor()
		most_travel = maxf(most_travel, _largest_travel(car))
		var ground := pad.elevation_height(car.global_position.x, car.global_position.z)
		ground_gap = maxf(ground_gap, absf(car.global_position.y - ground))
		lowest_gap = minf(lowest_gap, car.global_position.y - ground)
		highest = maxf(highest, ground)
	Input.action_release("accelerate")

	var least_ripple := INF
	var most_ripple := 0.0
	for i in 4:
		var ripple := sqrt(deviation_squares[i] / ROAD_FEEL_SAMPLE_FRAMES) / static_loads[i / 2]
		least_ripple = minf(least_ripple, ripple)
		most_ripple = maxf(most_ripple, ripple)
	var front_mean := (deviation_sum[0] + deviation_sum[1]) / ROAD_FEEL_SAMPLE_FRAMES
	var rear_mean := (deviation_sum[2] + deviation_sum[3]) / ROAD_FEEL_SAMPLE_FRAMES
	_check(car.forward_speed > 40.0 and highest > ROAD_FEEL_MIN_CLIMB, "flat-out run gets up to speed and onto the swell (%.1f m/s, %.2f m up)" % [car.forward_speed, highest])
	_check(least_ripple > ROAD_FEEL_MIN_RIPPLE, "every wheel's load swings with the road at speed (RMS %.3f .. %.3f of its static load, floor %.2f)" % [least_ripple, most_ripple, ROAD_FEEL_MIN_RIPPLE])
	_check(absf(front_mean) < ROAD_FEEL_MEAN_TOLERANCE and absf(rear_mean) < ROAD_FEEL_MEAN_TOLERANCE, "the road moves load around, it adds none: mean axle loads stay on their baseline (front %+.1f N, rear %+.1f N)" % [front_mean, rear_mean])
	_check(stats.finite and loads_finite, "no NaN / inf / negative wheel loads over the bumps")
	_check(stats.max_step < 1.5, "no teleporting over the bumps (largest step %.2f m)" % stats.max_step)
	_check(off_floor and most_travel < ArcadeCar.SUSPENSION_TRAVEL and ground_gap < RIDE_HEIGHT_TOLERANCE, "the body rides the elevation on its springs, clear of the floor (never more than %.4f m off it, wheel travel up to %.4f m of %.2f)" % [ground_gap, most_travel, ArcadeCar.SUSPENSION_TRAVEL])
	_check(ground_gap - lowest_gap > RIDE_HEIGHT_MIN_MOTION, "... and really on springs: its height over the ground moves (by %.4f m over the run)" % (ground_gap - lowest_gap))
	_check(absf(car.global_position.x) < 0.01 and absf(car.global_rotation.y) < 0.001, "bumps and swell do not pull the car off line (x = %.4f m)" % car.global_position.x)

	car.reset_to_spawn()
	var reset_clean := true
	for i in 4:
		reset_clean = reset_clean and car.wheel_loads[i] == static_loads[i / 2]
	await _step(2)
	for i in 4:
		reset_clean = reset_clean and absf(car.wheel_loads[i] - static_loads[i / 2]) < 0.01
	_check(reset_clean, "reset puts the suspension at rest (front %.1f N, rear %.1f N a tick later)" % [car.wheel_loads[0], car.wheel_loads[2]])
	await _step(5)


## The crest test: drive over the road's test dip. Going in, the road drops
## away under each wheel faster than the car can follow: the load dips. At the
## bottom it comes back up: the load peaks. Past it the load settles again.
## Everything is timed by where each wheel is, not by frames.
func _check_crest(car: ArcadeCar) -> void:
	var dip := RoadProfile.TEST_DIP_CENTRE
	var spawn := car.get_spawn_transform()
	car.reset_to(Transform3D(spawn.basis, Vector3(dip.x, spawn.origin.y, dip.y + CREST_RUN_UP)))
	await _step(10)
	var stats := _new_stats()
	var lowest: Array[float] = [INF, INF, INF, INF]
	var lowest_at: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var highest: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var highest_at: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var settled_sum: Array[float] = [0.0, 0.0, 0.0, 0.0]
	var settled_count: Array[int] = [0, 0, 0, 0]
	var crossing_speed := 0.0
	Input.action_press("accelerate")
	for frame in 900:
		await _drive(car, 1, stats)
		var baselines := _wheel_baselines(car)
		for i in 4:
			# How far this wheel is past the middle of the dip [m].
			var past := dip.y - (car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]).z
			var load_ratio := car.wheel_loads[i] / baselines[i / 2]
			if absf(past) < CREST_WINDOW:
				if load_ratio < lowest[i]:
					lowest[i] = load_ratio
					lowest_at[i] = past
				if load_ratio > highest[i]:
					highest[i] = load_ratio
					highest_at[i] = past
			elif past > CREST_SETTLED_FROM and past < CREST_SETTLED_TO:
				settled_sum[i] += load_ratio
				settled_count[i] += 1
		if crossing_speed == 0.0 and car.global_position.z <= dip.y:
			crossing_speed = car.forward_speed
		if car.global_position.z < dip.y - CREST_SETTLED_TO - 5.0:
			break
	Input.action_release("accelerate")

	var least_dip := INF
	var least_rise := INF
	var dip_first := true
	var worst_settled := 0.0
	for i in 4:
		least_dip = minf(least_dip, 1.0 - lowest[i])
		least_rise = minf(least_rise, highest[i] - 1.0)
		dip_first = dip_first and lowest_at[i] < highest_at[i]
		worst_settled = maxf(worst_settled, absf(settled_sum[i] / maxi(settled_count[i], 1) - 1.0) if settled_count[i] > 0 else INF)
	_check(crossing_speed > 20.0 and crossing_speed < 30.0, "crest run crosses the test dip at speed (%.1f m/s)" % crossing_speed)
	_check(least_dip > CREST_MIN_DIP, "the road dropping away unloads every wheel (front left down to %.2f of its baseline %.1f m before the middle; least dip %.2f, floor %.2f)" % [lowest[0], -lowest_at[0], least_dip, CREST_MIN_DIP])
	_check(least_rise > CREST_MIN_RISE and dip_first, "the bottom of the dip loads every wheel up again, after the dip in load (front left up to %.2f, %.1f m past the middle; least rise %.2f, floor %.2f)" % [highest[0], highest_at[0], least_rise, CREST_MIN_RISE])
	_check(worst_settled < CREST_SETTLED_TOLERANCE, "past the dip the wheel loads settle back on their baseline (mean off by %.3f at most, limit %.2f)" % [worst_settled, CREST_SETTLED_TOLERANCE])
	_check(stats.finite and stats.max_step < 1.5, "no NaN / inf / teleporting through the dip (largest step %.2f m)" % stats.max_step)
	car.reset_to_spawn()
	await _step(5)


## The body on its springs: a drop test (ride frequency, settling), dive under
## braking, squat under power and roll in a corner, each against rigid-body
## statics; travel inside its limits; the wheels drawn on the road and the body
## drawn where the springs have it; reset puts all of it at rest.
func _check_suspension(pad: TestPad, car: ArcadeCar) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var spawn := car.get_spawn_transform()
	var stats := _new_stats()
	var most_travel := 0.0

	# Drop test: stood above its ride height and let go, the body falls into
	# its springs and bounces. Half a period between the first two turning
	# points of its height.
	car.reset_to(Transform3D(spawn.basis, spawn.origin + Vector3.UP * SUSPENSION_DROP_HEIGHT))
	var turning_frames: Array[int] = []
	var speed_before := 0.0
	var lowest_load := INF
	for frame in SUSPENSION_SETTLE_FRAMES:
		await _drive(car, 1, stats)
		if frame > 0 and car.velocity.y * speed_before < 0.0 and turning_frames.size() < 2:
			turning_frames.append(frame)
		speed_before = car.velocity.y
		for i in 4:
			lowest_load = minf(lowest_load, car.wheel_loads[i])
	var bounce_hz := 0.0
	if turning_frames.size() == 2:
		bounce_hz = 60.0 / (2.0 * (turning_frames[1] - turning_frames[0]))
	_check(bounce_hz > SUSPENSION_MIN_BOUNCE_HZ and bounce_hz < SUSPENSION_MAX_BOUNCE_HZ, "dropped %.0f cm onto its springs the body bounces at a road car's ride frequency (%.2f Hz, springs %.1f / %.1f kN/m, dampers %.0f / %.0f N s/m)" % [SUSPENSION_DROP_HEIGHT * 100.0, bounce_hz, ArcadeCar.FRONT_SPRING_RATE / 1000.0, ArcadeCar.REAR_SPRING_RATE / 1000.0, ArcadeCar.FRONT_DAMPER_RATE, ArcadeCar.REAR_DAMPER_RATE])
	_check(_largest_travel(car) < SUSPENSION_SETTLED_TRAVEL and not car.is_on_floor() and lowest_load > 0.0, "... and is at rest again %.0f s later, never having left the road or met the floor (travel %.5f m)" % [SUSPENSION_SETTLE_FRAMES / 60.0, _largest_travel(car)])

	# Dive: full brake at speed. Nose down, front springs in, rear springs out,
	# and the load the springs move onto the front axle is what statics says.
	await _reach_speed(car, SUSPENSION_BRAKE_SPEED)
	Input.action_press("brake")
	var dive := await _suspension_average(car, stats)
	Input.action_release("brake")
	most_travel = maxf(most_travel, dive.most_travel)
	_check(dive.pitch < -SUSPENSION_MIN_DIVE and dive.front_travel > SUSPENSION_MIN_DIVE_TRAVEL and dive.rear_travel < 0.0, "braking dives the nose into the front springs (pitch %.4f rad at %.1f m/s^2, front springs %.1f cm in, rear %.1f cm out)" % [dive.pitch, dive.longitudinal_accel, dive.front_travel * 100.0, -dive.rear_travel * 100.0])
	var dive_moved: float = dive.front_load - dive.front_static
	var dive_statics: float = dive.front_baseline - dive.front_static
	_check(dive_statics > 1000.0 and absf(dive_moved - dive_statics) < SUSPENSION_STATICS_TOLERANCE * dive_statics, "... and the weight that moves onto the front axle comes out of the springs as statics has it (%.0f N, acceleration x mass x CG height / wheelbase says %.0f)" % [dive_moved, dive_statics])

	# Squat: a launch pitches the nose up.
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	await _drive(car, SUSPENSION_SETTLE_IN_FRAMES, stats)
	var squat := await _suspension_average(car, stats)
	Input.action_release("accelerate")
	most_travel = maxf(most_travel, squat.most_travel)
	_check(squat.pitch > SUSPENSION_MIN_SQUAT and squat.rear_travel > 0.0 and squat.front_travel < 0.0, "power squats the tail (pitch %.4f rad at %.1f m/s^2, rear springs %.1f cm in, front %.1f cm out)" % [squat.pitch, squat.longitudinal_accel, squat.rear_travel * 100.0, -squat.front_travel * 100.0])

	# Roll: a left-hand corner leans the body onto its right-hand wheels.
	await _get_up_to_speed(car)
	Input.action_press("steer_left", CORNER_STEER)
	var corner := await _suspension_average(car, stats)
	most_travel = maxf(most_travel, corner.most_travel)
	_check(corner.roll < -SUSPENSION_MIN_ROLL and corner.lateral_accel > 3.0, "cornering rolls the body out of the corner (roll %.4f rad at %.1f m/s^2 to the left: %.1f degrees per g)" % [corner.roll, corner.lateral_accel, absf(rad_to_deg(corner.roll)) / corner.lateral_accel * gravity])
	# was ArcadeCar.CAR_MASS -> car.total_mass(), the mass that is cornering.
	var roll_statics: float = car.total_mass() * corner.lateral_accel * ArcadeCar.CG_HEIGHT / ArcadeCar.HALF_TRACK
	_check(absf(corner.right_minus_left - roll_statics) < SUSPENSION_STATICS_TOLERANCE * roll_statics, "... onto the outside wheels, by what statics has it (right pair %.0f N over the left, acceleration x mass x CG height / half track says %.0f)" % [corner.right_minus_left, roll_statics])

	# What shows, mid-corner: every wheel on the road under it, the body mesh at
	# the springs' pitch and roll.
	var wheels_on_road := 0.0
	var wheel_names: Array[String] = ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]
	for i in 4:
		var wheel := car.get_node("Wheels/" + wheel_names[i]) as Node3D
		var contact := car.global_transform * ArcadeCar.WHEEL_CONTACT_POINTS[i]
		wheels_on_road = maxf(wheels_on_road, absf(wheel.global_position.y - ArcadeCar.WHEEL_RADIUS - pad.sample_height(contact.x, contact.z)))
	var body := car.get_node("Body") as Node3D
	_check(wheels_on_road < WHEEL_ON_ROAD_TOLERANCE, "the wheels are drawn on the road while the body leans over them (furthest off %.4f m)" % wheels_on_road)
	_check(absf(body.rotation.z - car.body_roll) < 0.00001 and absf(body.rotation.x - car.body_pitch) < 0.00001 and car.body_roll != 0.0, "the body is drawn at the springs' own pitch and roll (%.4f / %.4f rad)" % [body.rotation.x, body.rotation.z])
	Input.action_release("steer_left")

	_check(most_travel < ArcadeCar.SUSPENSION_TRAVEL, "full braking, a launch and a corner all stay inside the suspension's travel (%.1f cm of %.0f)" % [most_travel * 100.0, ArcadeCar.SUSPENSION_TRAVEL * 100.0])
	_check(stats.finite and stats.max_step < 1.5, "no NaN / inf / teleporting through the suspension checks (largest step %.2f m)" % stats.max_step)

	car.reset_to_spawn()
	_check(car.pitch_rate == 0.0 and car.roll_rate == 0.0 and car.velocity.y == 0.0 and _largest_travel(car) == 0.0 and absf(body.rotation.z - car.body_roll) < 0.00001 and absf(car.body_pitch) < 0.005 and absf(car.body_roll) < 0.005, "reset stands the body at rest on the road, in the plane of its four wheels (pitch %.5f, roll %.5f rad)" % [car.body_pitch, car.body_roll])
	await _step(5)


## Lets SUSPENSION_SETTLE_IN_FRAMES pass, then averages the body's attitude, the
## spring travel per axle [m], the loads [N], the statics baseline of the front
## axle (_wheel_baselines) and the accelerations over SUSPENSION_AVERAGE_FRAMES.
func _suspension_average(car: ArcadeCar, stats: Dictionary) -> Dictionary:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var mean := {
		"pitch": 0.0, "roll": 0.0, "front_travel": 0.0, "rear_travel": 0.0, "front_load": 0.0, "front_baseline": 0.0,
		"right_minus_left": 0.0, "longitudinal_accel": 0.0, "lateral_accel": 0.0, "most_travel": 0.0,
		# was ArcadeCar.CAR_MASS x gravity -> the weight of the car as it is.
		"front_static": car.total_mass() * gravity * (1.0 - ArcadeCar.REAR_WEIGHT_FRACTION),
	}
	var share := 1.0 / SUSPENSION_AVERAGE_FRAMES
	for frame in SUSPENSION_SETTLE_IN_FRAMES + SUSPENSION_AVERAGE_FRAMES:
		await _drive(car, 1, stats)
		mean.most_travel = maxf(mean.most_travel, _largest_travel(car))
		if frame < SUSPENSION_SETTLE_IN_FRAMES:
			continue
		mean.pitch += car.body_pitch * share
		mean.roll += car.body_roll * share
		mean.front_travel += (car.wheel_travel[0] + car.wheel_travel[1]) * 0.5 * share
		mean.rear_travel += (car.wheel_travel[2] + car.wheel_travel[3]) * 0.5 * share
		mean.front_load += car.front_axle_load * share
		mean.front_baseline += _wheel_baselines(car)[0] * 2.0 * share
		mean.right_minus_left += (car.wheel_loads[1] + car.wheel_loads[3] - car.wheel_loads[0] - car.wheel_loads[2]) * share
		mean.longitudinal_accel += car.longitudinal_accel * share
		mean.lateral_accel += car.lateral_accel * share
	return mean


## What the pad places stands on the ground it shows: cones (their homes),
## the straight's distance board posts and the perimeter pylons.
func _check_placed_on_ground(pad: TestPad) -> void:
	var cone_gap := 0.0
	var cone_count := 0
	for group: StringName in [TestPad.GROUP_SLALOM, TestPad.GROUP_SKID_INNER, TestPad.GROUP_SKID_OUTER, TestPad.GROUP_STOP_BOX]:
		for home in pad.get_cone_positions(group):
			cone_gap = maxf(cone_gap, absf(home.y - pad.elevation_height(home.x, home.z)))
			cone_count += 1
	_check(cone_count > 0 and cone_gap <= PLACED_ON_GROUND_TOLERANCE, "all %d cones stand on the ground (largest gap %.4f m)" % [cone_count, cone_gap])

	# Boxes stand with their middle half their height above the ground.
	var box_gap := 0.0
	var box_count := 0
	var highest_foot := 0.0
	var lowest_foot := 0.0
	for path: String in ["Straight", "Pylons"]:
		var group := pad.get_node_or_null(path)
		if group == null:
			continue
		for child in group.get_children():
			var instance := child as MeshInstance3D
			if instance == null or not instance.mesh is BoxMesh:
				continue
			var size := (instance.mesh as BoxMesh).size
			# Uprights only: board posts and pylon shafts, not paint or caps.
			if size.y < 2.0 or size.y < size.x * 2.0:
				continue
			var foot := instance.position.y - size.y * 0.5
			var ground := pad.elevation_height(instance.position.x, instance.position.z)
			box_gap = maxf(box_gap, absf(foot - ground))
			highest_foot = maxf(highest_foot, foot)
			lowest_foot = minf(lowest_foot, foot)
			box_count += 1
	_check(box_count >= 40 and box_gap <= PLACED_ON_GROUND_TOLERANCE, "all %d board posts and pylons stand on the ground (largest gap %.4f m)" % [box_count, box_gap])
	_check(highest_foot > 0.5 and lowest_foot < -0.5, "... up and down the swell (feet from %.2f m to %.2f m)" % [lowest_foot, highest_foot])


## A slide nobody is driving ends by itself: the nose comes back into line
## with the travel, the rotation stops and the car scrubs its speed off, or
## rolls on straight if it had speed left.
func _check_slide_settle(car: ArcadeCar) -> void:
	var flick := await _slide_and_let_go(car, SLIDE_FLICK_FRAMES)
	_check(flick.peak_angle > SLIDE_IN_LINE_ANGLE, "a flick of the handbrake slides the car (nose %.2f rad off the travel, from %.1f m/s)" % [flick.peak_angle, flick.entry_speed])
	_check(flick.in_line_at >= 0.0 and flick.in_line_at < SLIDE_FLICK_MAX_IN_LINE_TIME, "keys released, the nose comes back in line (after %.2f s, limit %.2f)" % [flick.in_line_at, SLIDE_FLICK_MAX_IN_LINE_TIME])
	_check(absf(flick.turned) < SLIDE_FLICK_MAX_TURNED, "the car does not hang in a drift on the way (turned %.2f rad, limit %.2f)" % [flick.turned, SLIDE_FLICK_MAX_TURNED])
	_check(flick.speed_at_3s > SLIDE_FLICK_MIN_ROLL_ON_SPEED and flick.end_forward_speed > 0.0 and absf(flick.end_yaw_rate) < SLIDE_SETTLED_YAW_RATE, "it rolls on straight, nose first (%.1f m/s 3 s after the release, yaw rate %.4f rad/s at the end)" % [flick.speed_at_3s, flick.end_yaw_rate])

	var scrub := await _slide_and_let_go(car, SLIDE_SCRUB_FRAMES)
	_check(scrub.peak_angle > 1.0, "a longer pull gets the car well sideways (nose %.2f rad off the travel, %.1f m/s at the release)" % [scrub.peak_angle, scrub.release_speed])
	_check(scrub.in_line_at >= 0.0 and scrub.in_line_at < SLIDE_SCRUB_MAX_SETTLE_TIME, "keys released, the slide straightens out (after %.2f s, limit %.2f)" % [scrub.in_line_at, SLIDE_SCRUB_MAX_SETTLE_TIME])
	_check(scrub.crawl_at >= 0.0 and scrub.crawl_at < SLIDE_SCRUB_MAX_SETTLE_TIME, "the sliding tyres scrub the speed off (under %.1f m/s after %.2f s, limit %.2f)" % [CRAWL_SPEED, scrub.crawl_at, SLIDE_SCRUB_MAX_SETTLE_TIME])
	_check(scrub.rest_at >= 0.0 and scrub.rest_at < SLIDE_SCRUB_MAX_REST_TIME and absf(scrub.end_yaw_rate) < SLIDE_SETTLED_YAW_RATE, "and the car comes to rest (after %.2f s, limit %.2f)" % [scrub.rest_at, SLIDE_SCRUB_MAX_REST_TIME])

	var backwards := await _slide_and_let_go(car, SLIDE_BACKWARDS_FRAMES)
	var speed_drop: float = backwards.speed_at_1s - backwards.speed_at_3s
	_check(backwards.end_forward_speed < 0.0 and backwards.speed_at_3s > CRAWL_SPEED and absf(backwards.end_yaw_rate) < SLIDE_SETTLED_YAW_RATE, "a full second of handbrake leaves the car rolling backwards, the rotation stopped (%.1f m/s 3 s after the release)" % backwards.speed_at_3s)
	_check(speed_drop > SLIDE_BACKWARDS_MIN_SPEED_DROP, "the engine holds it back rolling backwards too (%.2f -> %.2f m/s in 2 s, at least %.2f)" % [backwards.speed_at_1s, backwards.speed_at_3s, SLIDE_BACKWARDS_MIN_SPEED_DROP])

	_check(flick.finite and scrub.finite and backwards.finite, "no NaN / inf in speeds or position while the slides settle")
	var largest_step := maxf(flick.max_step, maxf(scrub.max_step, backwards.max_step))
	_check(largest_step < SLIDE_SETTLE_MAX_STEP, "no teleporting while the slides settle (largest step %.2f m)" % largest_step)


## The handling tests' run clock (HandlingTests, "The run clock"), on every
## test. The data first: a start line, RUN_CLOCK_LINE_AHEAD down the pad from
## the start point. Then a human run (nobody at the controls, nothing pressed)
## with the car put where the check wants it between ticks, so no physics frame
## passes and nothing here depends on how the car drives: a second of sitting
## on the start point and a move away from the line leave the clock at 0 and
## not started; the tick the car is over the line starts it; going back over
## the line and crossing it again does not start it anew.
func _check_run_clock(pad: TestPad, car: ArcadeCar) -> void:
	var delta := 1.0 / Engine.physics_ticks_per_second
	_check(MissionManager.CLOCK_NOT_STARTED == "not started", "the mission line's clock reads '%s' until the start line is crossed" % MissionManager.CLOCK_NOT_STARTED)
	_check(
		TestPad.SLALOM_START_LINE_Z < TestPad.START_LINE_Z and TestPad.SLALOM_START_LINE_Z > TestPad.SLALOM_FIRST_Z,
		"the slalom's own start line lies between the pad's start line and the first cone (z = %.1f)" % TestPad.SLALOM_START_LINE_Z,
	)
	for definition in HandlingTests.all_tests():
		var label: String = definition.name
		var line_z: float = definition.get("start_line_z", NAN)
		var start: Vector3 = car.get_spawn_transform().origin + definition.start_offset
		var own_line := TestPad.SLALOM_START_LINE_Z if definition.kind == HandlingTests.KIND_SLALOM else TestPad.START_LINE_Z
		_check(
			definition.has("start_line_z") and line_z == own_line and is_equal_approx(start.z - line_z, RUN_CLOCK_LINE_AHEAD),
			"%s: has a start line, z = %.1f, %.1f m down the pad from its start point" % [label, line_z, start.z - line_z],
		)

		var run := HandlingTests.begin(definition, car, pad, false)
		var fresh := run.progress()
		var waited: bool = not run.started() and run.run_time() == 0.0 and fresh.get("run_started", true) == false and fresh.get("run_time_s", -1.0) == 0.0
		for i in RUN_CLOCK_WAIT_TICKS:
			run.tick(delta)
		# Away from the line, back up the pad, and to the start point again.
		car.global_position = start + Vector3(0.0, 0.0, RUN_CLOCK_LINE_AHEAD)
		run.tick(delta)
		car.global_position = start
		run.tick(delta)
		waited = waited and not run.started() and run.run_time() == 0.0 and run.elapsed > RUN_CLOCK_WAIT_TICKS * delta
		_check(waited, "%s: sitting on the start point and moving away from the line leave the clock at 0, not started (%.2f s into the test)" % [label, run.elapsed])

		# Just short of the line, then just over it: the crossing tick is 0.
		var short_of_line := Vector3(start.x, start.y, line_z + RUN_CLOCK_STEP)
		var over_line := Vector3(start.x, start.y, line_z - RUN_CLOCK_STEP)
		car.global_position = short_of_line
		run.tick(delta)
		var before := run.started()
		car.global_position = over_line
		run.tick(delta)
		var at_crossing := run.run_time()
		for i in RUN_CLOCK_RUN_TICKS:
			run.tick(delta)
		_check(
			not before and run.started() and at_crossing == 0.0 and is_equal_approx(run.run_time(), RUN_CLOCK_RUN_TICKS * delta) and run.progress().run_started == true,
			"%s: the clock starts the tick the car is over the line, not before (%.3f s after %d ticks)" % [label, run.run_time(), RUN_CLOCK_RUN_TICKS],
		)

		# Back over the line and across it a second time: two more ticks on the
		# same clock, no new start.
		car.global_position = short_of_line
		run.tick(delta)
		car.global_position = over_line
		run.tick(delta)
		_check(
			run.started() and is_equal_approx(run.run_time(), (RUN_CLOCK_RUN_TICKS + 2) * delta),
			"%s: crossing the line a second time does not start the clock anew (%.3f s)" % [label, run.run_time()],
		)
		run.abort()
	car.reset_to_spawn()
	pad.reset_cones()


## The handling tests' 180, mirrored: the same driver with steer_right for
## steer_left and the rotation conditions negated. A spin counts either way
## round. The definition stays here; all_tests() runs the left-hand one.
func _check_mirrored_spin(pad: TestPad, car: ArcadeCar) -> void:
	var definition := HandlingTests.spin_180_test()
	definition.steps = [
		{"when": {}, "press": [&"accelerate"]},
		{"when": {"speed_above": HandlingTests.SPIN_180_ENTRY_SPEED}, "release": [&"accelerate"], "press": [&"steer_right", &"handbrake"], "mark": true},
		{"when": {"rotation_deg_below": -HandlingTests.SPIN_180_CATCH_DEG}, "release": [&"steer_right"]},
		{"when": {"after": HandlingTests.SPIN_180_SETTLE_TIME}, "press": [&"brake"]},
		# was the end of the script -> the 180 ends back at the start: the drive
		# back of the left-hand driver, its dab of lock mirrored too.
		{"when": {"speed_below": HandlingTests.STOPPED_SPEED}, "release": [&"brake", &"handbrake"], "press": [&"accelerate"]},
		{"when": {"speed_above": HandlingTests.SPIN_180_LINE_UP_SPEED}, "press": [&"steer_left"]},
		{"when": {"after": HandlingTests.SPIN_180_LINE_UP_TAP}, "release": [&"steer_left"]},
		{"when": {"goal_distance_below": HandlingTests.SPIN_180_RETURN_BRAKE_DISTANCE}, "release": [&"accelerate"], "press": [&"brake"]},
		{"when": {"goal_distance_below": HandlingTests.GOAL_RADIUS}},
	]
	var run := HandlingTests.begin(definition, car, pad)
	await _step(10)
	var delta := 1.0 / Engine.physics_ticks_per_second
	while not run.finished:
		run.tick(delta)
		await physics_frame
	var outcome := run.result()
	var metrics: Dictionary = outcome.metrics
	_check(outcome.passed, "a 180 to the right passes the same checks as one to the left (%s)" % ", ".join(HandlingTests.format_result(outcome)).replace("  metrics: ", ""))
	_check(metrics.rotation_deg < -90.0, "the rotation metric keeps its sign: right is negative (%.1f degrees)" % metrics.rotation_deg)
	_check(metrics.heading_error_deg < MIRRORED_SPIN_MAX_HEADING_ERROR, "the heading error is measured against the target heading, not the signed rotation (%.1f degrees)" % metrics.heading_error_deg)
	pad.reset_cones()


## The driver between the keys and the pedals: throttle_pedal / brake_pedal are
## where the feet have the pedals, a driver profile says how fast the feet are,
## set_driver_input asks the driver for the same things the keys do, and the
## HUD's two bars show the pedals.
func _check_pedals(car: ArcadeCar, hud: HUD) -> void:
	car.reset_to_spawn()
	await _step(20)
	_check(car.driver_profile == ArcadeCar.DRIVER_PROFILES["test_driver"], "pedals: the test driver is in the seat unless somebody else is put there")
	_check(car.throttle_pedal == 0.0 and car.brake_pedal == 0.0, "pedals: both at rest with no key down (throttle %.2f, brake %.2f)" % [car.throttle_pedal, car.brake_pedal])

	# A tap: the foot starts down, never gets there, and comes back.
	var tap := await _press_and_watch(car, "accelerate", PEDAL_TAP_FRAMES, PEDAL_RELEASE_FRAMES)
	_check(tap.peak_throttle > PEDAL_TAP_MIN and tap.peak_throttle < PEDAL_TAP_MAX, "pedals: a %d-frame tap of accelerate is a partial press (throttle peaks at %.2f)" % [PEDAL_TAP_FRAMES, tap.peak_throttle])
	_check(tap.end_throttle == 0.0 and tap.peak_brake == 0.0, "pedals: the tap comes back to nothing, the brake never moved (throttle %.2f, brake peak %.2f)" % [tap.end_throttle, tap.peak_brake])

	# A held key: up to the floor, tick by tick, and exactly there.
	car.reset_to_spawn()
	await _step(20)
	var hold := await _press_and_watch(car, "accelerate", PEDAL_HOLD_FRAMES, PEDAL_RELEASE_FRAMES)
	_check(hold.peak_throttle == 1.0 and hold.rising, "pedals: a held accelerate key reaches full throttle, never easing on the way (1.0 after %d ticks)" % hold.ticks_to_full)
	_check(hold.ticks_to_full > PEDAL_TAP_FRAMES and hold.first_throttle > 0.0 and hold.first_throttle < 1.0, "pedals: ... by way of a ramp, not a switch (%.2f on the first tick, %.2f s to the floor)" % [hold.first_throttle, hold.ticks_to_full / 60.0])
	_check(hold.end_throttle == 0.0 and hold.ticks_to_release > 0, "pedals: released, the throttle decays to 0 (%d ticks)" % hold.ticks_to_release)
	_check(hold.in_range, "pedals: throttle and brake stay finite and inside 0..1 all the while")

	# The brake is a pedal too. Rolling, so that it is the brake and not reverse.
	var braked := await _press_and_watch(car, "brake", PEDAL_HOLD_FRAMES, PEDAL_RELEASE_FRAMES)
	_check(braked.peak_brake == 1.0 and braked.first_brake > 0.0 and braked.first_brake < 1.0, "pedals: a held brake key ramps to a full brake (%.2f on the first tick, 1.0 after %d ticks)" % [braked.first_brake, braked.ticks_to_full_brake])
	_check(braked.end_brake == 0.0 and braked.peak_throttle == 0.0 and not car.reverse_engaged, "pedals: released, the brake decays to 0; no throttle, no reverse (brake %.2f)" % braked.end_brake)

	# Another driver, other feet: the chauffeur's take longer to the floor.
	car.set_driver_profile(ArcadeCar.DRIVER_PROFILES["chauffeur"])
	car.reset_to_spawn()
	await _step(20)
	var chauffeur := await _press_and_watch(car, "accelerate", PEDAL_HOLD_FRAMES, PEDAL_RELEASE_FRAMES)
	_check(chauffeur.peak_throttle == 1.0 and chauffeur.ticks_to_full >= hold.ticks_to_full * PEDAL_PROFILE_MIN_RATIO, "pedals: the chauffeur profile presses the throttle measurably slower (%d ticks to the floor, the test driver %d)" % [chauffeur.ticks_to_full, hold.ticks_to_full])
	_check(chauffeur.first_throttle < hold.first_throttle and chauffeur.ticks_to_release > hold.ticks_to_release, "pedals: ... from the first tick (%.3f against %.3f), and lets it go slower too (%d ticks against %d)" % [chauffeur.first_throttle, hold.first_throttle, chauffeur.ticks_to_release, hold.ticks_to_release])
	car.set_driver_profile({"throttle_attack": NAN, "brake_attack": -5.0})
	_check(car.driver_profile.throttle_attack == ArcadeCar.DRIVER_PROFILES["test_driver"].throttle_attack and car.driver_profile.brake_attack == 0.0 and car.driver_profile.size() == ArcadeCar.DRIVER_PROFILES["test_driver"].size(), "pedals: a profile's missing and NaN rates are the test driver's, a negative one is 0")
	car.set_driver_profile(ArcadeCar.DRIVER_PROFILES["test_driver"])
	_check(car.driver_profile == ArcadeCar.DRIVER_PROFILES["test_driver"], "pedals: the test driver is back in the seat")

	# The same launch twice: by the key, and through set_driver_input with no
	# key down. One driver either way, so the same car to the last bit.
	car.reset_to_spawn()
	await _step(20)
	Input.action_press("accelerate")
	await _step(DRIVER_INPUT_LAUNCH_FRAMES)
	Input.action_release("accelerate")
	var key_speed := car.forward_speed
	var key_z := car.global_position.z
	car.reset_to_spawn()
	await _step(20)
	var keys_up := true
	for action: String in ["accelerate", "brake", "steer_left", "steer_right", "handbrake"]:
		keys_up = keys_up and not Input.is_action_pressed(action)
	car.set_driver_input(1.0, 0.0, 0.0)
	await _step(DRIVER_INPUT_LAUNCH_FRAMES)
	_check(keys_up and car.forward_speed > 8.0, "driver input: set_driver_input drives the car with no key down (%.1f m/s after 2 s)" % car.forward_speed)
	_check(car.forward_speed == key_speed and car.global_position.z == key_z, "driver input: ... exactly as the accelerate key does (%.4f m/s and z = %.3f, the key %.4f and %.3f)" % [car.forward_speed, car.global_position.z, key_speed, key_z])

	# Half a pedal and half a lock asked for is what the driver holds.
	car.set_driver_input(0.5, 0.0, 0.5)
	await _step(DRIVER_INPUT_SETTLE_FRAMES)
	_check(car.throttle_pedal == 0.5 and is_equal_approx(car.steering_wheel_deg, 0.5 * ArcadeCar.STEERING_WHEEL_LOCK_DEG), "driver input: half throttle and half left lock asked for are held (throttle %.2f, wheel %.0f degrees)" % [car.throttle_pedal, car.steering_wheel_deg])
	_check(is_equal_approx(hud.get_node("ThrottleBarBack/ThrottleBar").scale.y, 0.5) and not hud.get_node("BrakeBarBack/BrakeBar").visible, "HUD: the throttle bar stands at the pedal's half, the brake bar is empty (scale %.2f)" % hud.get_node("ThrottleBarBack/ThrottleBar").scale.y)

	# Out of range is clamped, NaN is nothing asked for.
	car.set_driver_input(7.0, NAN, NAN)
	await _step(DRIVER_INPUT_SETTLE_FRAMES)
	_check(car.throttle_pedal == 1.0 and car.brake_pedal == 0.0 and car.steering_wheel_deg == 0.0 and is_finite(car.forward_speed), "driver input: 7.0 of throttle is full throttle, NaN brake and steering are none (throttle %.2f, brake %.2f, wheel %.0f degrees)" % [car.throttle_pedal, car.brake_pedal, car.steering_wheel_deg])

	# The two pedals mean what the two keys mean: the brake held through the
	# stop holds the car, asked for anew at the standstill it is reverse.
	car.set_driver_input(0.0, 1.0, 0.0)
	var lowest_speed := 0.0
	for frame in 300:
		await physics_frame
		lowest_speed = minf(lowest_speed, car.forward_speed)
	_check(car.brake_pedal == 1.0 and absf(car.forward_speed) < 0.01 and lowest_speed > -0.01 and not car.reverse_engaged, "driver input: a held brake stops the car and never reverses (%.2f m/s, lowest %.2f)" % [car.forward_speed, lowest_speed])
	car.set_driver_input(0.0, 0.0, 0.0)
	await _step(5)
	car.set_driver_input(0.0, 1.0, 0.0)
	await _step(120)
	_check(car.reverse_engaged and car.forward_speed < -1.0 and car.throttle_pedal > 0.0 and car.brake_pedal == 0.0, "driver input: the brake asked for anew at a standstill reverses, and is the throttle there (%.1f m/s, throttle %.2f)" % [car.forward_speed, car.throttle_pedal])

	# Back to the keys: none is down, so the feet come off.
	car.clear_driver_input()
	await _step(PEDAL_RELEASE_FRAMES)
	_check(car.throttle_pedal == 0.0 and car.brake_pedal == 0.0, "driver input: clear_driver_input hands the car back to the keys (pedals %.2f / %.2f with none down)" % [car.throttle_pedal, car.brake_pedal])

	# The HUD's pedal setters: 0..1, clamped, NaN is empty.
	var throttle_bar := hud.get_node("ThrottleBarBack/ThrottleBar") as ColorRect
	var brake_bar := hud.get_node("BrakeBarBack/BrakeBar") as ColorRect
	_check(hud.has_method("set_throttle_bar") and hud.has_method("set_brake_bar") and throttle_bar != null and brake_bar != null, "HUD: pedal bars and their setters exist")
	_check(throttle_bar.color.g > throttle_bar.color.r and brake_bar.color.r > brake_bar.color.g, "HUD: the throttle bar is green, the brake bar red")
	hud.set_throttle_bar(0.25)
	hud.set_brake_bar(1.0)
	_check(throttle_bar.visible and throttle_bar.scale.y == 0.25 and brake_bar.visible and brake_bar.scale.y == 1.0, "HUD: the setters take 0..1 (throttle bar at %.2f, brake bar at %.2f)" % [throttle_bar.scale.y, brake_bar.scale.y])
	hud.set_throttle_bar(3.0)
	hud.set_brake_bar(-2.0)
	_check(throttle_bar.scale.y == 1.0 and not brake_bar.visible, "HUD: out of range is clamped (3.0 is a full bar, -2.0 an empty one)")
	hud.set_throttle_bar(NAN)
	_check(not throttle_bar.visible and is_finite(throttle_bar.scale.y), "HUD: NaN is an empty bar")
	await _step(2)
	_check(not throttle_bar.visible and not brake_bar.visible, "HUD: the bars are the car's pedals again the next tick (both empty, no key down)")
	car.reset_to_spawn()
	await _step(5)


## The tank, the fuel bar and the exhaust: what the engine takes and gives.
func _check_fuel_and_exhaust(car: ArcadeCar, hud: HUD) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var capacity := ArcadeCar.FUEL_TANK_CAPACITY_L
	car.reset_to_spawn()
	_check(car.fuel_l == capacity and car.fuel_fraction() == 1.0, "fuel: a reset car has a full tank (%.1f L of %.0f)" % [car.fuel_l, capacity])

	# Idling: a little fuel, three firings for every turn of the crankshaft.
	var turns := 0.0
	var finite := true
	for frame in FUEL_IDLE_FRAMES:
		turns += car.engine_omega / TAU * tick
		await physics_frame
		finite = finite and is_finite(car.fuel_l) and is_finite(car.exhaust_events) and is_finite(car.exhaust_flow)
	var idle_l_h := (capacity - car.fuel_l) / (FUEL_IDLE_FRAMES * tick) * 3600.0
	_check(idle_l_h > FUEL_IDLE_MIN_L_H and idle_l_h < FUEL_IDLE_MAX_L_H, "fuel: idling burns a little (%.2f L/h at %.0f rpm)" % [idle_l_h, car.engine_rpm])
	var firings_per_turn := car.exhaust_events / turns
	_check(absf(firings_per_turn - 3.0) < 3.0 * EXHAUST_EVENTS_TOLERANCE, "exhaust: the flat six fires three times a turn (%.0f events over %.1f turns idling: %.4f a turn)" % [car.exhaust_events, turns, firings_per_turn])
	var idle_flow := car.exhaust_flow
	var idle_event_rate := car.exhaust_events / (FUEL_IDLE_FRAMES * tick)
	_check(idle_flow > 0.0 and idle_flow < EXHAUST_IDLE_MAX_FLOW, "exhaust: idling it barely blows (flow %.3f)" % idle_flow)

	# Flat out from rest: the work costs fuel, the exhaust blows.
	var fuel_before := car.fuel_l
	var events_before := car.exhaust_events
	var peak_flow := 0.0
	var flow_in_range := true
	Input.action_press("accelerate")
	for frame in FUEL_LOAD_FRAMES:
		await physics_frame
		peak_flow = maxf(peak_flow, car.exhaust_flow)
		flow_in_range = flow_in_range and car.exhaust_flow >= 0.0 and car.exhaust_flow <= 1.0
		finite = finite and is_finite(car.fuel_l) and is_finite(car.exhaust_events) and is_finite(car.exhaust_flow)
	var load_l_h := (fuel_before - car.fuel_l) / (FUEL_LOAD_FRAMES * tick) * 3600.0
	var load_event_rate := (car.exhaust_events - events_before) / (FUEL_LOAD_FRAMES * tick)
	_check(load_l_h > FUEL_LOAD_MIN_L_H and load_l_h < FUEL_LOAD_MAX_L_H, "fuel: flat out burns what the work costs (%.1f L/h over %.0f s from rest, %.0f times the idle burn)" % [load_l_h, FUEL_LOAD_FRAMES * tick, load_l_h / idle_l_h])
	_check(load_event_rate > 2.0 * idle_event_rate, "exhaust: the firings come with the revs (%.0f a second flat out, %.0f idling)" % [load_event_rate, idle_event_rate])
	_check(peak_flow > EXHAUST_LOAD_MIN_FLOW and flow_in_range, "exhaust: the flow follows the throttle and the revs, inside 0..1 (peak %.2f flat out, %.3f idling)" % [peak_flow, idle_flow])

	# The overrun: throttle shut at speed, the engine turned by the car. Nothing
	# burns and nothing fires.
	Input.action_release("accelerate")
	await _step(FUEL_OVERRUN_LIFT_FRAMES)
	var overrun_fuel := car.fuel_l
	var overrun_events := car.exhaust_events
	await _step(FUEL_OVERRUN_FRAMES)
	_check(car.fuel_l == overrun_fuel and car.exhaust_events == overrun_events and car.engine_rpm > 2.0 * ArcadeCar.IDLE_RPM, "fuel: on the overrun nothing burns and nothing fires (throttle shut at %.0f rpm, %.0f km/h)" % [car.engine_rpm, car.speed_kmh])
	_check(car.exhaust_flow < idle_flow, "exhaust: ... and the flow dies away (%.4f)" % car.exhaust_flow)

	# The fuel bar reads the tank.
	var fuel_bar := hud.get_node_or_null("FuelBarBack/FuelBar") as ColorRect
	if not _check(fuel_bar != null and hud.has_method("set_fuel_bar"), "HUD: the fuel bar and its setter exist"):
		return
	car.fuel_l = 0.5 * capacity
	await _step(2)
	_check(fuel_bar.visible and is_equal_approx(fuel_bar.scale.x, car.fuel_fraction()) and absf(fuel_bar.scale.x - 0.5) < 0.001 and fuel_bar.color == HUD.FUEL_COLOR, "HUD: the fuel bar reads the tank (half a tank: bar at %.3f, fuel_fraction %.3f)" % [fuel_bar.scale.x, car.fuel_fraction()])
	car.fuel_l = 0.12 * capacity
	await _step(2)
	var amber := fuel_bar.color == HUD.FUEL_RESERVE_COLOR and is_equal_approx(fuel_bar.scale.x, car.fuel_fraction())
	car.fuel_l = 0.05 * capacity
	await _step(2)
	_check(amber and fuel_bar.color == HUD.FUEL_LOW_COLOR and is_equal_approx(fuel_bar.scale.x, car.fuel_fraction()), "HUD: the fuel bar turns amber under %.0f %% of the tank and red under %.0f %% (bar at %.3f)" % [HUD.FUEL_RESERVE_FRACTION * 100.0, HUD.FUEL_LOW_FRACTION * 100.0, fuel_bar.scale.x])
	hud.set_fuel_bar(3.0)
	var clamped_full := fuel_bar.visible and fuel_bar.scale.x == 1.0
	hud.set_fuel_bar(-2.0)
	var clamped_empty := not fuel_bar.visible
	hud.set_fuel_bar(0.25)
	hud.set_fuel_bar(NAN)
	_check(clamped_full and clamped_empty and not fuel_bar.visible and is_finite(fuel_bar.scale.x), "HUD: the fuel bar's setter takes 0..1, clamped, NaN is an empty bar")

	# The tank itself never holds less than nothing or more than it can.
	car.fuel_l = -5.0
	var never_negative := car.fuel_l == 0.0 and car.fuel_fraction() == 0.0
	car.fuel_l = NAN
	var nan_empty := car.fuel_l == 0.0
	car.fuel_l = 1000.0
	_check(never_negative and nan_empty and car.fuel_l == capacity and car.fuel_fraction() == 1.0, "fuel: the tank holds 0 .. %.0f L whatever it is handed (-5 and NaN are dry, 1000 is full)" % capacity)

	# Dry: the engine runs down and stays down, throttle or not; nothing goes
	# negative or NaN; a reset fills the tank and the engine idles again.
	car.reset_to_spawn()
	car.fuel_l = 0.0
	await _step(FUEL_DRY_RUN_DOWN_FRAMES)
	var ran_down := car.engine_rpm
	var dry_events := car.exhaust_events
	Input.action_press("accelerate")
	var stats := _new_stats()
	await _drive(car, FUEL_DRY_THROTTLE_FRAMES, stats)
	Input.action_release("accelerate")
	_check(ran_down == 0.0 and car.engine_rpm == 0.0 and absf(car.forward_speed) < 0.01 and car.exhaust_events == dry_events, "fuel: with the tank dry the engine runs down and the throttle gets the car nowhere (%.0f rpm, %.3f m/s)" % [car.engine_rpm, car.forward_speed])
	_check(stats.finite and finite and car.fuel_l == 0.0 and car.fuel_fraction() == 0.0 and is_finite(car.exhaust_flow) and car.exhaust_flow >= 0.0, "fuel: never negative, no NaN, tank dry or not (%.1f L, flow %.4f)" % [car.fuel_l, car.exhaust_flow])
	await _step(2)
	_check(not fuel_bar.visible, "HUD: the fuel bar is empty with the tank")
	var spawn := car.get_spawn_transform()
	car.reset_to(spawn)
	var refilled := car.fuel_l == capacity and car.exhaust_events == 0.0
	car.fuel_l = 1.0
	car.reset_to_spawn()
	await _step(5)
	_check(refilled and car.fuel_fraction() > 0.9999 and absf(car.engine_rpm - ArcadeCar.IDLE_RPM) < 1.0 and car.exhaust_events > 0.0, "fuel: reset_to and reset_to_spawn fill the tank, and the engine idles again (%.4f of a tank, %.0f rpm)" % [car.fuel_fraction(), car.engine_rpm])


## The one mass of the car: fuel and payload are in it.
func _check_mass_and_payload(pad: TestPad, car: ArcadeCar) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
	car.reset_to_spawn()
	var full_tank := ArcadeCar.FUEL_TANK_CAPACITY_L * ArcadeCar.FUEL_DENSITY
	_check(is_equal_approx(car.total_mass(), ArcadeCar.KERB_MASS) and is_equal_approx(car.fuel_mass, full_tank) and car.payload_mass == 0.0, "mass: on a full tank, nothing loaded, the car weighs its kerb mass (%.2f kg, %.2f of it fuel)" % [car.total_mass(), car.fuel_mass])

	# The empty car's 5 s of full throttle, and what they burn off it.
	await _step(20)
	Input.action_press("accelerate")
	await _step(FUEL_LOAD_FRAMES)
	Input.action_release("accelerate")
	var empty_speed := car.forward_speed
	var burnt := full_tank - car.fuel_mass
	_check(burnt > 0.0 and is_equal_approx(car.fuel_mass, car.fuel_l * ArcadeCar.FUEL_DENSITY) and is_equal_approx(car.total_mass(), ArcadeCar.BASE_MASS + car.fuel_mass), "mass: the fuel in the tank is in total_mass(), and burns off it (%.1f g lighter after %.0f s flat out: %.3f kg)" % [burnt * 1000.0, FUEL_LOAD_FRAMES / 60.0, car.total_mass()])
	car.fuel_l = 0.0
	await _step(1)
	_check(is_equal_approx(car.total_mass(), ArcadeCar.BASE_MASS) and car.total_mass() < ArcadeCar.KERB_MASS - 40.0, "mass: with the tank dry the car is down to its base mass (%.2f kg)" % car.total_mass())

	# Loaded: heavier, level on its springs, every wheel carrying its share, and
	# slower over the same 5 s.
	car.reset_to_spawn()
	car.payload_mass = PAYLOAD_KG
	await _step(20)
	var weight := car.total_mass() * gravity
	var level := true
	for i in 4:
		var share := (1.0 - ArcadeCar.REAR_WEIGHT_FRACTION) if i < 2 else ArcadeCar.REAR_WEIGHT_FRACTION
		level = level and absf(car.wheel_loads[i] - weight * share * 0.5) < 0.01 and absf(car.wheel_travel[i]) < REST_TRAVEL_TOLERANCE
	_check(is_equal_approx(car.total_mass(), ArcadeCar.KERB_MASS + PAYLOAD_KG) and level, "payload: %.0f kg on board are in total_mass() and on the wheels, the car level on its springs (%.0f kg, front wheels %.1f N, rear %.1f N)" % [PAYLOAD_KG, car.total_mass(), car.wheel_loads[0], car.wheel_loads[2]])
	Input.action_press("accelerate")
	var stats := _new_stats()
	await _drive(car, FUEL_LOAD_FRAMES, stats)
	Input.action_release("accelerate")
	var loaded_speed := car.forward_speed
	_check(loaded_speed < PAYLOAD_MAX_SPEED_SHARE * empty_speed and loaded_speed > 0.5 * empty_speed and stats.finite, "payload: the loaded car is slower over the same %.0f s of full throttle (%.1f m/s against %.1f, %.2f of it)" % [FUEL_LOAD_FRAMES / 60.0, loaded_speed, empty_speed, loaded_speed / empty_speed])
	car.payload_mass = -50.0
	var never_negative := car.payload_mass == 0.0
	car.payload_mass = NAN
	_check(never_negative and car.payload_mass == 0.0 and is_finite(car.total_mass()), "payload: never negative, NaN is nothing loaded")
	car.payload_mass = PAYLOAD_KG
	car.reset_to_spawn()
	_check(car.payload_mass == 0.0 and is_equal_approx(car.total_mass(), ArcadeCar.KERB_MASS), "payload: a reset unloads the car (%.2f kg)" % car.total_mass())

	# A test's payload_kg is loaded at its start; a test without one runs empty.
	var certified_empty := true
	for definition in HandlingTests.all_tests():
		certified_empty = certified_empty and not definition.has("payload_kg")
	var loaded_test := HandlingTests.stop_box_test()
	loaded_test["payload_kg"] = 40.0
	var loaded_run := HandlingTests.begin(loaded_test, car, pad, false)
	var loaded := car.payload_mass
	loaded_run.abort()
	var empty_run := HandlingTests.begin(HandlingTests.stop_box_test(), car, pad, false)
	_check(loaded == 40.0 and car.payload_mass == 0.0 and certified_empty, "payload: a test's payload_kg is on board from its start (%.0f kg), the next test starts empty, no certified test carries any" % loaded)
	empty_run.abort()
	car.reset_to_spawn()
	await _step(5)


## The creep: the brake let go at a standstill, automatic, and the car crawls.
func _check_creep(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	# A car nobody has touched stands where it was put.
	car.reset_to_spawn()
	var start := car.global_position
	await _step(CREEP_UNTOUCHED_FRAMES)
	_check(absf(car.forward_speed) < 0.01 and car.global_position.distance_to(start) < 0.01, "creep: a car nobody has touched stands still (%.3f m/s after %.0f s)" % [car.forward_speed, CREEP_UNTOUCHED_FRAMES * tick])

	# Drive off, brake to a stop and stay on the brake: held, the car stands.
	var stopped := await _brake_to_a_stop(car)
	var held_still := stopped
	for frame in CREEP_HOLD_FRAMES:
		await physics_frame
		held_still = held_still and car.forward_speed == 0.0
	_check(held_still and not car.reverse_engaged, "creep: on a held brake the car stands (%.3f m/s, %.0f s on the brake at the standstill)" % [car.forward_speed, CREEP_HOLD_FRAMES * tick])

	# The brake let go: the car picks itself up and crawls, the feet on nothing.
	Input.action_release("brake")
	var moving_at := -1.0
	var feet_off := true
	var finite := true
	var top_speed := 0.0
	for frame in CREEP_WATCH_FRAMES:
		await physics_frame
		if moving_at < 0.0 and car.forward_speed >= CREEP_MOVING_SPEED:
			moving_at = (frame + 1) * tick
		# The brake foot takes its 6 ticks to come off; from then on, nothing.
		if frame >= PEDAL_RELEASE_FRAMES:
			feet_off = feet_off and car.throttle_pedal == 0.0 and car.brake_pedal == 0.0
		finite = finite and is_finite(car.forward_speed) and is_finite(car.clutch_torque) and is_finite(car.engine_rpm)
		top_speed = maxf(top_speed, car.forward_speed)
	_check(moving_at >= 0.0 and moving_at < CREEP_MAX_PICK_UP_TIME, "creep: the brake let go, the automatic picks the car up (%.1f m/s %.2f s after the release)" % [CREEP_MOVING_SPEED, moving_at])
	_check(car.forward_speed > CREEP_MIN_CRAWL and top_speed < CREEP_MAX_CRAWL and top_speed < ArcadeCar.STANDSTILL_SPEED, "creep: it settles at a crawl, under the standstill speed (%.2f m/s, %.1f km/h %.0f s after the release, never above %.2f)" % [car.forward_speed, car.speed_kmh, CREEP_WATCH_FRAMES * tick, top_speed])
	_check(feet_off and finite and car.clutch_torque > 0.0 and not car.clutch_locked and car.gear == 1 and absf(car.engine_rpm - ArcadeCar.IDLE_RPM) < 50.0, "creep: through the slipping clutch on the idling engine, both pedals at nothing (clutch %.1f Nm, %.0f rpm)" % [car.clutch_torque, car.engine_rpm])

	# Off on the throttle, stopped on the brake again: the throttle ends the
	# creep, the held brake holds the car, and let go it arms the creep anew.
	stopped = await _brake_to_a_stop(car)
	held_still = stopped
	for frame in CREEP_HOLD_FRAMES:
		await physics_frame
		held_still = held_still and car.forward_speed == 0.0
	Input.action_release("brake")
	moving_at = -1.0
	for frame in CREEP_WATCH_FRAMES:
		await physics_frame
		if moving_at < 0.0 and car.forward_speed >= CREEP_MOVING_SPEED:
			moving_at = (frame + 1) * tick
	_check(held_still and moving_at >= 0.0 and moving_at < CREEP_MAX_PICK_UP_TIME and car.forward_speed > CREEP_MIN_CRAWL and car.forward_speed < CREEP_MAX_CRAWL, "creep: stopped on the brake again the car stands, let go it creeps again (moving after %.2f s, %.2f m/s at the end)" % [moving_at, car.forward_speed])

	# The brake pressed anew at a crawl is the brake pressed anew at a
	# standstill: reverse. The creep is over, the car backs up.
	Input.action_press("brake")
	await _step(CREEP_HOLD_FRAMES)
	Input.action_release("brake")
	_check(car.reverse_engaged and car.forward_speed < 0.0, "creep: the brake pressed anew selects reverse from the crawl as from rest (%.1f m/s)" % car.forward_speed)

	# Manual: the same stop, the same release, and the car stands.
	car.reset_to_spawn()
	car.automatic = false
	stopped = await _brake_to_a_stop(car)
	Input.action_release("brake")
	await _step(CREEP_UNTOUCHED_FRAMES)
	_check(stopped and not car.automatic and car.gear == 1 and absf(car.forward_speed) < 0.01, "creep: none in manual mode (%.3f m/s, %.0f s after the brake was let go in 1st)" % [car.forward_speed, CREEP_UNTOUCHED_FRAMES * tick])
	car.reset_to_spawn()
	await _step(5)


## The driver's controls: what the TCS, ABS and gearbox mode switches, the
## clutch pedal, the starter and the shift keys' way into reverse do.
func _check_driver_controls(main: Node, car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var rpm_label := main.get_node("HUD/RpmLabel") as Label
	var tcs_lamp := main.get_node_or_null("HUD/TcsLamp") as Label
	var abs_lamp := main.get_node_or_null("HUD/AbsLamp") as Label
	var in_range := true

	# (1) The switches: on, on and sport unless somebody flips them, a key each,
	# a lamp for each aid, and a reset leaves them alone.
	car.reset_to_spawn()
	await _step(5)
	_check(car.tcs_on and car.abs_on and car.gearbox_mode == ArcadeCar.GearboxMode.SPORT and car.engine_running and car.clutch_pedal == 0.0, "controls: the car starts with TCS and ABS on, in the sport program, the engine running, the clutch pedal up")
	_check(tcs_lamp != null and abs_lamp != null and tcs_lamp.text == "TCS" and abs_lamp.text == "ABS" and tcs_lamp.get_theme_color("font_color") == HUD.AID_ON_COLOR, "controls: the HUD's two aid lamps are quiet while the aids are on ('%s', '%s', dim)" % [tcs_lamp.text if tcs_lamp else "?", abs_lamp.text if abs_lamp else "?"])
	await _tap("tcs_toggle")
	await _tap("abs_toggle")
	await _tap("gearbox_mode")
	await _step(2)
	_check(not car.tcs_on and not car.abs_on and car.gearbox_mode == ArcadeCar.GearboxMode.COMFORT, "controls: the TCS, ABS and gearbox mode keys flip their switches (TCS %s, ABS %s, comfort %s)" % [car.tcs_on, car.abs_on, car.gearbox_mode == ArcadeCar.GearboxMode.COMFORT])
	_check(tcs_lamp.text == "TCS OFF" and abs_lamp.text == "ABS OFF" and abs_lamp.get_theme_color("font_color") == HUD.AID_OFF_COLOR and rpm_label.text.ends_with("G1 comfort"), "controls: the lamps light up and say OFF, the tach names the comfort program ('%s', '%s', '%s')" % [tcs_lamp.text, abs_lamp.text, rpm_label.text])
	car.reset_to_spawn()
	await _step(5)
	_check(not car.tcs_on and not car.abs_on and car.gearbox_mode == ArcadeCar.GearboxMode.COMFORT and car.automatic, "controls: a reset leaves the switches as the driver has them (it puts the car back, not the dashboard)")
	await _tap("tcs_toggle")
	await _tap("abs_toggle")
	await _tap("gearbox_mode")
	await _step(2)
	_check(car.tcs_on and car.abs_on and car.gearbox_mode == ArcadeCar.GearboxMode.SPORT and tcs_lamp.text == "TCS" and abs_lamp.text == "ABS" and rpm_label.text.ends_with("G1"), "controls: the same keys switch them back on, the HUD is quiet again ('%s')" % rpm_label.text)

	# (2) TCS: the same launch with and without. With, the clutch is feathered
	# and the driven wheels held at DRIVE_SLIP_RATIO; without, the clutch is let
	# in for good once the revs are up and the tyres are spun past their peak.
	var with_tcs := await _controls_launch(car)
	car.tcs_on = false
	var without_tcs := await _controls_launch(car)
	car.tcs_on = true
	_check(with_tcs.peak_slip > ArcadeCar.PEAK_SLIP_RATIO * 0.5 and with_tcs.peak_slip <= ArcadeCar.DRIVE_SLIP_RATIO + 0.001, "controls: with TCS a launch never spins the rears past the slip the clutch is feathered to (peak slip ratio %.3f, limit %.2f)" % [with_tcs.peak_slip, ArcadeCar.DRIVE_SLIP_RATIO])
	_check(without_tcs.peak_slip > with_tcs.peak_slip + CONTROLS_MIN_WHEELSPIN and without_tcs.peak_slip > ArcadeCar.PEAK_SLIP_RATIO, "controls: without it the clutch dumps and the rears spin far past their peak (peak slip ratio %.2f against %.3f, the tyres' peak is at %.2f)" % [without_tcs.peak_slip, with_tcs.peak_slip, ArcadeCar.PEAK_SLIP_RATIO])
	_check(without_tcs.locked_at > 0.0 and without_tcs.locked_at < with_tcs.locked_at, "controls: without TCS the clutch is home sooner, on spinning wheels (%.2f s after the key against %.2f s)" % [without_tcs.locked_at, with_tcs.locked_at])
	_check(without_tcs.running and without_tcs.speed > with_tcs.speed * 0.8 and without_tcs.min_rpm >= ArcadeCar.IDLE_RPM - 1.0 and without_tcs.max_rpm <= ArcadeCar.REDLINE_RPM + 100.0, "controls: the car still gets away and the engine never comes near a stall (%.1f m/s after %.0f s against %.1f, %d..%d rpm)" % [without_tcs.speed, CONTROLS_LAUNCH_FRAMES * tick, with_tcs.speed, without_tcs.min_rpm, without_tcs.max_rpm])
	_check(with_tcs.finite and without_tcs.finite, "controls: no NaN / inf through either launch")

	# (3) ABS: the same full stop with and without, then the same stop with the
	# steering wheel turned.
	var with_abs := await _controls_stop(car, 0.0)
	car.abs_on = false
	var without_abs := await _controls_stop(car, 0.0)
	car.abs_on = true
	_check(with_abs.stopped and with_abs.locked_ticks == 0 and with_abs.min_front_omega > 0.0, "controls: with ABS a full pedal from %.0f km/h never locks a wheel (front wheels never slower than %.1f rad/s above walking pace)" % [CONTROLS_BRAKE_SPEED * 3.6, with_abs.min_front_omega])
	_check(without_abs.stopped and without_abs.locked_ticks > without_abs.moving_ticks * 0.8 and without_abs.min_front_slip <= -0.999, "controls: without it the front wheels lock: wheel speed 0 with the car still moving, slip ratio %.2f, for %d of the stop's %d ticks" % [without_abs.min_front_slip, without_abs.locked_ticks, without_abs.moving_ticks])
	_check(without_abs.distance > with_abs.distance * CONTROLS_MIN_LOCKED_STOP_SHARE, "controls: the locked stop is the longer one (%.1f m against %.1f m with ABS)" % [without_abs.distance, with_abs.distance])
	_check(with_abs.finite and without_abs.finite and absf(without_abs.drift) < 0.05 and absf(with_abs.drift) < 0.05, "controls: both stops are finite and dead straight (%.3f and %.3f m off line)" % [with_abs.drift, without_abs.drift])
	var steered_with_abs := await _controls_stop(car, 1.0)
	car.abs_on = false
	var steered_without_abs := await _controls_stop(car, 1.0)
	car.abs_on = true
	_check(steered_with_abs.turned > 0.1 and absf(steered_without_abs.turned) < steered_with_abs.turned * CONTROLS_LOCKED_MAX_TURN_SHARE, "controls: locked front wheels do not steer (full lock on the brakes for %.0f s turns the car %.1f degrees, %.1f with ABS)" % [CONTROLS_STEER_FRAMES * tick, rad_to_deg(steered_without_abs.turned), rad_to_deg(steered_with_abs.turned)])
	_check(steered_without_abs.rolling_again, "controls: the pedal let go, the front wheels roll again (%.1f rad/s a second later, the road passes at %.1f)" % [steered_without_abs.front_omega_after, steered_without_abs.road_omega_after])

	# (4) The clutch pedal: manual mode, the left foot. Held, the clutch is open
	# whatever the throttle does; let go on a revving engine it is a dump.
	car.reset_to_spawn()
	car.automatic = false
	await _step(5)
	Input.action_press("clutch_pedal")
	var pedal_ticks := 0
	for frame in CONTROLS_CLUTCH_FRAMES:
		await physics_frame
		in_range = in_range and car.clutch_pedal >= 0.0 and car.clutch_pedal <= 1.0
		if car.clutch_pedal < 1.0:
			pedal_ticks = frame + 2
	_check(car.clutch_pedal == 1.0 and pedal_ticks == roundi(60.0 / ArcadeCar.CLUTCH_PEDAL_SPEED), "controls: the clutch key is a foot going down, on the floor after %d ticks (%.2f s)" % [pedal_ticks, pedal_ticks * tick])
	Input.action_press("accelerate")
	var stood := true
	for frame in CONTROLS_CLUTCH_HOLD_FRAMES:
		await physics_frame
		stood = stood and car.forward_speed == 0.0 and car.clutch_torque == 0.0 and car.clutch_engagement == 0.0
	_check(stood and car.engine_rpm > ArcadeCar.LIMITER_RESUME_RPM - 100.0, "controls: clutch pedal down, full throttle for %.0f s revs the engine to the limiter and moves the car nowhere (%.3f m/s, %d rpm)" % [CONTROLS_CLUTCH_HOLD_FRAMES * tick, car.forward_speed, car.engine_rpm])
	Input.action_release("clutch_pedal")
	var dump_slip := 0.0
	var dump_finite := true
	for frame in CONTROLS_LAUNCH_FRAMES:
		await physics_frame
		dump_slip = maxf(dump_slip, car.rear_slip_ratio)
		dump_finite = dump_finite and is_finite(car.forward_speed) and is_finite(car.engine_rpm) and is_finite(car.clutch_torque) and is_finite(car.rear_slip_ratio)
		in_range = in_range and car.clutch_pedal >= 0.0 and car.clutch_pedal <= 1.0
	Input.action_release("accelerate")
	_check(car.tcs_on and dump_slip > without_tcs.peak_slip and car.forward_speed > 5.0 and car.engine_running and dump_finite, "controls: let go at the limiter it is a clutch dump, TCS or not: the driver's foot wins over the car's feathering (peak slip ratio %.1f, %.1f m/s after %.0f s)" % [dump_slip, car.forward_speed, CONTROLS_LAUNCH_FRAMES * tick])
	car.reset_to_spawn()
	await _step(5)
	Input.action_press("clutch_pedal")
	await _step(CONTROLS_CLUTCH_FRAMES)
	var pedal_in_automatic := car.clutch_pedal
	Input.action_press("accelerate")
	await _step(CONTROLS_LAUNCH_FRAMES)
	Input.action_release("accelerate")
	Input.action_release("clutch_pedal")
	# (To the millimetre a second, not to the bit: the car idled a third of a
	# second longer before this launch, and is that much fuel lighter.)
	_check(car.automatic and pedal_in_automatic == 0.0 and car.clutch_locked and absf(car.forward_speed - with_tcs.speed) < 0.001, "controls: in automatic there is no clutch pedal: the key held, the launch is the launch (%.3f m/s after %.0f s, %.3f without the key)" % [car.forward_speed, CONTROLS_LAUNCH_FRAMES * tick, with_tcs.speed])

	# (5) The stall: the pedal let go on an idling engine with the throttle only
	# just going down. The clutch is in before the revs are up and drags the
	# engine under STALL_RPM. Nothing burns, nothing fires, the tach falls to 0.
	car.reset_to_spawn()
	car.automatic = false
	await _step(5)
	Input.action_press("clutch_pedal")
	await _step(CONTROLS_CLUTCH_FRAMES)
	Input.action_release("clutch_pedal")
	Input.action_press("accelerate")
	var stalled_at := -1.0
	for frame in CONTROLS_LAUNCH_FRAMES:
		await physics_frame
		if not car.engine_running:
			stalled_at = (frame + 1) * tick
			break
	await _step(2)
	_check(stalled_at > 0.0 and not car.engine_running, "controls: the clutch pedal let go on an idling engine as the throttle goes down stalls it (%.2f s after the release, the car lurched to %.2f m/s)" % [stalled_at, car.forward_speed])
	_check(car.throttle_pedal == 1.0 and car.clutch_engagement == 0.0 and car.clutch_torque == 0.0, "controls: the throttle does nothing for a stalled engine, and the car lets its clutch go (throttle pedal %.2f, clutch %.1f Nm)" % [car.throttle_pedal, absf(car.clutch_torque)])
	Input.action_release("accelerate")

	# A stalled automatic does not creep. The lurch of the stall still has the
	# car rolling: stopped on the brake, the brake held and let go (what starts
	# the creep of a running car, see _check_creep), it stands.
	await _tap("toggle_gearbox")
	var lurch_speed := car.forward_speed
	Input.action_press("brake")
	await _step(CREEP_HOLD_FRAMES)
	var held_at_rest := car.forward_speed == 0.0
	Input.action_release("brake")
	await _step(CREEP_UNTOUCHED_FRAMES)
	_check(lurch_speed > ArcadeCar.STANDSTILL_SPEED and held_at_rest and car.automatic and car.gear == 1 and not car.reverse_engaged and not car.engine_running and car.forward_speed == 0.0, "controls: a stalled car does not creep (automatic, 1st, stopped from %.2f m/s and held on the brake, %.3f m/s %.0f s after the brake was let go)" % [lurch_speed, car.forward_speed, CREEP_UNTOUCHED_FRAMES * tick])
	var fuel_stalled := car.fuel_l
	var events_stalled := car.exhaust_events
	await _step(CONTROLS_STALLED_FRAMES)
	_check(car.engine_rpm == 0.0 and rpm_label.text.begins_with("0 rpm") and rpm_label.text.ends_with("STALL"), "controls: the tach has fallen to 0 and says so ('%s')" % rpm_label.text)
	_check(car.fuel_l == fuel_stalled and car.exhaust_events == events_stalled and car.exhaust_flow < 0.001, "controls: a stalled engine burns nothing and fires nothing (%.6f L and %.1f events, unchanged over %.0f s; exhaust flow %.4f)" % [car.fuel_l, car.exhaust_events, CONTROLS_STALLED_FRAMES * tick, car.exhaust_flow])

	# (6) The starter: held, it turns the engine until it catches, and the idle
	# controller takes it from there.
	var fuel_before_start := car.fuel_l
	Input.action_press("starter")
	var caught_at := -1.0
	var fuel_at_catch := 0.0
	for frame in CONTROLS_STALLED_FRAMES:
		await physics_frame
		if caught_at < 0.0 and car.engine_running:
			caught_at = (frame + 1) * tick
			fuel_at_catch = car.fuel_l
	Input.action_release("starter")
	_check(caught_at > 0.0 and caught_at < CONTROLS_MAX_START_TIME and fuel_at_catch == fuel_before_start, "controls: the starter key turns the engine until it catches, and cranking burns no fuel (caught after %.2f s)" % caught_at)
	await _step(CONTROLS_IDLE_FRAMES)
	_check(car.engine_running and absf(car.engine_rpm - ArcadeCar.IDLE_RPM) < CONTROLS_IDLE_TOLERANCE and car.fuel_l < fuel_before_start and car.exhaust_events > events_stalled and not rpm_label.text.contains("STALL"), "controls: caught, the idle controller has it and it burns and fires again (%d rpm, '%s')" % [car.engine_rpm, rpm_label.text])
	Input.action_press("starter")
	var idle_stats := _new_stats()
	await _drive(car, CONTROLS_STALLED_FRAMES, idle_stats)
	Input.action_release("starter")
	_check(idle_stats.max_rpm - idle_stats.min_rpm < CONTROLS_IDLE_TOLERANCE and idle_stats.finite, "controls: the starter leaves a running engine alone (%d..%d rpm with the key held)" % [idle_stats.min_rpm, idle_stats.max_rpm])

	# A dry tank: the engine runs down and stops running, the starter spins it
	# and it never catches; fuel in the tank, it does.
	car.fuel_l = 0.0
	await _step(FUEL_DRY_RUN_DOWN_FRAMES)
	var ran_down := not car.engine_running and car.engine_rpm == 0.0
	Input.action_press("starter")
	await _step(CONTROLS_IDLE_FRAMES)
	_check(ran_down and not car.engine_running and car.engine_rpm > ArcadeCar.STALL_RPM and car.engine_rpm < ArcadeCar.STARTER_FREE_RPM and car.fuel_l == 0.0, "controls: on a dry tank the engine stops and the starter only spins it (%d rpm after %.0f s of cranking, not running)" % [car.engine_rpm, CONTROLS_IDLE_FRAMES * tick])
	car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
	await _step(CONTROLS_STALLED_FRAMES)
	Input.action_release("starter")
	_check(car.engine_running, "controls: fuel in the tank, the same cranking engine catches (%d rpm)" % car.engine_rpm)
	car.fuel_l = 0.0
	await _step(FUEL_DRY_RUN_DOWN_FRAMES)
	var dead := not car.engine_running
	car.reset_to_spawn()
	await _step(CONTROLS_STALLED_FRAMES)
	_check(dead and car.engine_running and absf(car.engine_rpm - ArcadeCar.IDLE_RPM) < CONTROLS_IDLE_TOLERANCE, "controls: a reset starts a stopped engine: the car is put there ready to drive (%d rpm)" % car.engine_rpm)

	# (7) Reverse on the shift keys: under neutral, at a standstill.
	await _tap("shift_down")
	await _step(roundi(ArcadeCar.SHIFT_TIME * 60.0) + 3)
	var in_neutral := car.gear == 0 and not car.reverse_engaged
	await _tap("shift_down")
	await _step(roundi(ArcadeCar.SHIFT_TIME * 60.0) + 3)
	_check(in_neutral and car.reverse_engaged and not car.automatic and rpm_label.text.ends_with("R M"), "controls: shift-down from 1st is neutral as ever, one more from neutral is reverse ('%s')" % rpm_label.text)
	_check(not car.shift_down() and car.reverse_engaged, "controls: there is nothing under reverse")
	Input.action_press("brake")
	await _step(CONTROLS_LAUNCH_FRAMES)
	Input.action_release("brake")
	var backing_speed := car.forward_speed
	_check(backing_speed < -3.0 and car.reverse_engaged, "controls: in reverse the brake key is the throttle, as it is when the brake key selected it (%.1f m/s)" % backing_speed)
	await _tap("shift_up")
	await _step(roundi(ArcadeCar.SHIFT_TIME * 60.0) + 3)
	_check(car.gear == 0 and not car.reverse_engaged and rpm_label.text.ends_with("N M"), "controls: shift-up out of reverse is neutral ('%s', still rolling back at %.1f m/s)" % [rpm_label.text, car.forward_speed])
	car.reset_to_spawn()
	await _step(5)
	Input.action_press("accelerate")
	await _step(CREEP_RUN_UP_FRAMES)
	Input.action_release("accelerate")
	await _tap("shift_down")
	await _step(roundi(ArcadeCar.SHIFT_TIME * 60.0) + 3)
	var rolling_speed := car.forward_speed
	var rolling_in_neutral := car.gear == 0
	await _tap("shift_down")
	await _step(roundi(ArcadeCar.SHIFT_TIME * 60.0) + 3)
	_check(rolling_in_neutral and rolling_speed > ArcadeCar.STANDSTILL_SPEED and not car.reverse_engaged and car.gear == 0 and car.forward_speed > 0.0, "controls: rolling forwards the box refuses reverse and stays in neutral (%.1f m/s)" % rolling_speed)
	await _tap("shift_up")
	await _step(roundi(ArcadeCar.SHIFT_TIME * 60.0) + 3)
	_check(car.gear == 1 and not car.reverse_engaged, "controls: shift-up from neutral is 1st again (G%d)" % car.gear)
	await _tap("toggle_gearbox")
	var never_reversed := true
	for frame in CREEP_WATCH_FRAMES:
		await physics_frame
		never_reversed = never_reversed and not car.reverse_engaged and car.gear >= 1
	_check(car.automatic and never_reversed, "controls: the automatic never takes reverse by itself, coasting down to a crawl it is in G%d" % car.gear)

	# (8) Comfort and sport: the same 8 s flat out from rest.
	var sport := await _controls_shift_program(car, ArcadeCar.GearboxMode.SPORT, true)
	var comfort := await _controls_shift_program(car, ArcadeCar.GearboxMode.COMFORT, true)
	_check(sport.first_shift_rpm >= ArcadeCar.UPSHIFT_RPM and comfort.first_shift_rpm >= ArcadeCar.COMFORT_UPSHIFT_RPM and comfort.first_shift_rpm < sport.first_shift_rpm - 2000.0, "controls: flat out, comfort leaves 1st at %d rpm where sport holds it to %d" % [comfort.first_shift_rpm, sport.first_shift_rpm])
	_check(comfort.gear > sport.gear and comfort.speed < sport.speed and comfort.peak_rpm < sport.peak_rpm, "controls: %.0f s on comfort end a gear further up the box and slower (G%d at %.1f m/s, never over %d rpm; sport G%d at %.1f m/s)" % [CONTROLS_MODE_FRAMES * tick, comfort.gear, comfort.speed, comfort.peak_rpm, sport.gear, sport.speed])
	var manual_comfort := await _controls_shift_program(car, ArcadeCar.GearboxMode.COMFORT, false)
	_check(manual_comfort.gear == 1 and manual_comfort.peak_rpm > ArcadeCar.UPSHIFT_RPM and manual_comfort.first_shift_rpm == 0.0, "controls: manual mode knows neither program: 1st is held to the limiter (G%d, %d rpm)" % [manual_comfort.gear, manual_comfort.peak_rpm])
	_check(sport.finite and comfort.finite and manual_comfort.finite and car.gearbox_mode == ArcadeCar.GearboxMode.SPORT, "controls: no NaN / inf through the three runs, and the car is back on sport")

	# (9) Telemetry: the throttle and brake fields are the pedals. Half a pedal
	# asked for through set_driver_input, no key down, reads half in the file.
	var manager := main.get_node_or_null("MissionManager") as MissionManager
	var recorder: TelemetryRecorder = manager.telemetry if manager else null
	if _check(recorder != null and not recorder.recording, "controls: the telemetry recorder is there and idle"):
		if FileAccess.file_exists(CONTROLS_TELEMETRY_FILE):
			DirAccess.remove_absolute(CONTROLS_TELEMETRY_FILE)
		car.reset_to_spawn()
		await _step(5)
		recorder.record_to_file(CONTROLS_TELEMETRY_FILE)
		car.set_driver_input(0.5, 0.0, 0.0)
		await _step(CONTROLS_PEDAL_FRAMES)
		var throttle_was := car.throttle_pedal
		car.set_driver_input(0.0, 0.5, 0.0)
		await _step(CONTROLS_PEDAL_FRAMES)
		var brake_was := car.brake_pedal
		await _step(2)
		recorder.stop()
		car.clear_driver_input()
		var peak_throttle := 0.0
		var peak_brake := 0.0
		var samples := 0
		for raw in FileAccess.get_file_as_string(CONTROLS_TELEMETRY_FILE).split("\n"):
			var value: Variant = JSON.parse_string(raw) if not raw.strip_edges().is_empty() else null
			if value is Dictionary and (value as Dictionary).has("throttle"):
				samples += 1
				peak_throttle = maxf(peak_throttle, float(value.throttle))
				peak_brake = maxf(peak_brake, float(value.brake))
		_check(samples >= 3 and throttle_was == 0.5 and absf(brake_was - 0.5) < 0.001 and absf(peak_throttle - 0.5) < 0.001 and absf(peak_brake - 0.5) < 0.001 and not Input.is_action_pressed("accelerate"), "controls: the telemetry's throttle and brake are the pedals: half a pedal with no key down reads %.3f and %.3f (%d samples)" % [peak_throttle, peak_brake, samples])

	_check(in_range and car.clutch_pedal == 0.0 and car.tcs_on and car.abs_on, "controls: the clutch pedal stayed inside 0..1 throughout, and the aids are back on")
	car.reset_to_spawn()
	await _step(5)


## Full throttle from rest for CONTROLS_LAUNCH_FRAMES: the peak slip ratio of
## the driven rears, the speed at the end, when the clutch locked [s], the rev
## range, whether the engine was still running and everything stayed finite.
func _controls_launch(car: ArcadeCar) -> Dictionary:
	car.reset_to_spawn()
	await _step(10)
	var seen := {"peak_slip": 0.0, "speed": 0.0, "locked_at": -1.0, "min_rpm": INF, "max_rpm": 0.0, "running": true, "finite": true}
	Input.action_press("accelerate")
	for frame in CONTROLS_LAUNCH_FRAMES:
		await physics_frame
		seen.peak_slip = maxf(seen.peak_slip, car.rear_slip_ratio)
		seen.min_rpm = minf(seen.min_rpm, car.engine_rpm)
		seen.max_rpm = maxf(seen.max_rpm, car.engine_rpm)
		if seen.locked_at < 0.0 and car.clutch_locked:
			seen.locked_at = (frame + 1) / float(Engine.physics_ticks_per_second)
		seen.finite = seen.finite and is_finite(car.forward_speed) and is_finite(car.engine_rpm) and is_finite(car.rear_slip_ratio) and is_finite(car.clutch_torque) and car.global_position.is_finite()
	Input.action_release("accelerate")
	seen.speed = car.forward_speed
	seen.running = car.engine_running
	return seen


## A full stop from CONTROLS_BRAKE_SPEED, the steering asked for `steer_left`
## of its lock (0 = straight) for the first CONTROLS_STEER_FRAMES of it: the
## stopping distance [m], the ticks the car was still moving above walking pace
## and those of them the front wheels stood still, their lowest speed and slip
## ratio meanwhile, how far off its line the car ended [m], how far it turned
## in the steered part [rad], and, the pedal let go after that part of a
## steered stop, whether the front wheels picked the road's speed up again.
func _controls_stop(car: ArcadeCar, steer_left: float) -> Dictionary:
	await _reach_speed(car, CONTROLS_BRAKE_SPEED)
	var seen := {
		"stopped": false, "distance": 0.0, "moving_ticks": 0, "locked_ticks": 0, "min_front_omega": INF,
		"min_front_slip": 0.0, "drift": 0.0, "turned": 0.0, "finite": true,
		"rolling_again": false, "front_omega_after": 0.0, "road_omega_after": 0.0,
	}
	var start := car.global_position
	var yaw_before := car.global_rotation.y
	Input.action_press("brake")
	if steer_left > 0.0:
		Input.action_press("steer_left", steer_left)
	for frame in CREEP_WATCH_FRAMES:
		await physics_frame
		if car.forward_speed > CRAWL_SPEED:
			seen.moving_ticks += 1
			seen.min_front_omega = minf(seen.min_front_omega, car.front_omega)
			seen.min_front_slip = minf(seen.min_front_slip, car.front_slip_ratio)
			if car.front_omega == 0.0:
				seen.locked_ticks += 1
		seen.finite = seen.finite and is_finite(car.forward_speed) and is_finite(car.front_omega) and is_finite(car.rear_omega) and is_finite(car.front_slip_ratio) and is_finite(car.yaw_rate) and car.global_position.is_finite()
		if steer_left > 0.0 and frame + 1 == CONTROLS_STEER_FRAMES:
			break
		if car.forward_speed == 0.0:
			seen.stopped = true
			break
	Input.action_release("brake")
	Input.action_release("steer_left")
	seen.distance = car.global_position.distance_to(start)
	seen.drift = car.global_position.x - start.x
	seen.turned = angle_difference(yaw_before, car.global_rotation.y)
	if steer_left > 0.0:
		await _step(60)
		seen.front_omega_after = car.front_omega
		seen.road_omega_after = car.forward_speed / ArcadeCar.WHEEL_RADIUS
		seen.rolling_again = car.forward_speed > CRAWL_SPEED and absf(car.front_slip_ratio) < 0.05
	return seen


## CONTROLS_MODE_FRAMES flat out from rest on the automatic's `mode` program (or
## in manual mode, `automatic` false, with that program selected): the engine
## speed the road was turning 1st at on the tick the box left it [rpm] (0 if it
## never did), the gear and speed at the end, the highest engine speed seen.
## Leaves the car on the sport program.
func _controls_shift_program(car: ArcadeCar, mode: ArcadeCar.GearboxMode, automatic: bool) -> Dictionary:
	car.reset_to_spawn()
	car.gearbox_mode = mode
	car.automatic = automatic
	await _step(10)
	var seen := {"first_shift_rpm": 0.0, "gear": 0, "speed": 0.0, "peak_rpm": 0.0, "finite": true}
	var rpm_in_first := 0.0
	Input.action_press("accelerate")
	for frame in CONTROLS_MODE_FRAMES:
		await physics_frame
		if car.gear == 1:
			rpm_in_first = car.wheel_rpm(1)
		elif seen.first_shift_rpm == 0.0:
			seen.first_shift_rpm = rpm_in_first
		seen.peak_rpm = maxf(seen.peak_rpm, car.engine_rpm)
		seen.finite = seen.finite and is_finite(car.forward_speed) and is_finite(car.engine_rpm)
	Input.action_release("accelerate")
	seen.gear = car.gear
	seen.speed = car.forward_speed
	car.gearbox_mode = ArcadeCar.GearboxMode.SPORT
	return seen


## CREEP_RUN_UP_FRAMES of throttle, then onto the brake until the car stands:
## returns true once it does, the brake key still held.
func _brake_to_a_stop(car: ArcadeCar) -> bool:
	Input.action_press("accelerate")
	await _step(CREEP_RUN_UP_FRAMES)
	Input.action_release("accelerate")
	Input.action_press("brake")
	for frame in CREEP_WATCH_FRAMES:
		await physics_frame
		if car.forward_speed == 0.0:
			return true
	return false


## Holds `action` for `hold_frames` and lets go for `release_frames`, and says
## what the two pedals did meanwhile: their peaks, their values on the first
## tick of the press and at the end, the ticks to a full pedal and from the
## release back to nothing, whether the throttle only ever rose while held, and
## whether both stayed finite and inside 0..1.
func _press_and_watch(car: ArcadeCar, action: String, hold_frames: int, release_frames: int) -> Dictionary:
	var seen := {
		"peak_throttle": 0.0, "peak_brake": 0.0, "first_throttle": -1.0, "first_brake": -1.0,
		"end_throttle": 0.0, "end_brake": 0.0, "ticks_to_full": 0, "ticks_to_full_brake": 0,
		"ticks_to_release": 0, "rising": true, "in_range": true,
	}
	var last_throttle := car.throttle_pedal
	var moved := 0
	Input.action_press(action)
	for frame in hold_frames + release_frames:
		if frame == hold_frames:
			Input.action_release(action)
			moved = 0
		var before := Vector2(car.throttle_pedal, car.brake_pedal)
		await physics_frame
		var now := Vector2(car.throttle_pedal, car.brake_pedal)
		if now == before:
			continue
		moved += 1
		for pedal: float in [now.x, now.y]:
			if not is_finite(pedal) or pedal < 0.0 or pedal > 1.0:
				seen.in_range = false
		if frame < hold_frames:
			if seen.first_throttle < 0.0:
				seen.first_throttle = now.x
				seen.first_brake = now.y
			if now.x < last_throttle:
				seen.rising = false
			if now.x == 1.0 and seen.ticks_to_full == 0:
				seen.ticks_to_full = moved
			if now.y == 1.0 and seen.ticks_to_full_brake == 0:
				seen.ticks_to_full_brake = moved
		else:
			seen.ticks_to_release = moved
		last_throttle = now.x
		seen.peak_throttle = maxf(seen.peak_throttle, now.x)
		seen.peak_brake = maxf(seen.peak_brake, now.y)
	seen.end_throttle = car.throttle_pedal
	seen.end_brake = car.brake_pedal
	return seen


## Telemetry: the recorder writes a drive down and we read it back.
##
## The recorder is off in a headless run, so the phase switches it on in
## process and points it at a fixed tmp file (TELEMETRY_FILE, deleted first):
## the suite writes nothing under user:// at all, and the last check here says
## so. Then a real mission through the MissionManager - its signals do the work
## - driven with the same simulated keys as the rest of this test, and aborted.
##
## What is asserted is the schema, the tick-derived timestamps, the sampling
## stride and the event lines. The wall clock in the file is never asserted:
## the session_start line's `started_at` (and, in a normal session, the file's
## own name) are the only clock readings there are, and both are documented as
## such in scripts/telemetry.gd. Everything else is counted in physics ticks,
## so this phase reads the same on every run.
func _check_telemetry(main: Node, car: ArcadeCar) -> void:
	var manager := main.get_node_or_null("MissionManager") as MissionManager
	var recorder: TelemetryRecorder = manager.telemetry if manager else null
	if not _check(manager != null and recorder != null and not recorder.recording, "the mission manager owns a telemetry recorder, recording nothing with no window"):
		return
	# Whether user://telemetry was there before the phase: on a machine that has
	# really been driven it is, and it must come out unchanged either way.
	var user_dir_before := DirAccess.dir_exists_absolute(TelemetryRecorder.ROOT_DIR)

	DirAccess.make_dir_recursive_absolute(TELEMETRY_DIR)
	if FileAccess.file_exists(TELEMETRY_FILE):
		DirAccess.remove_absolute(TELEMETRY_FILE)
	car.reset_to_spawn()
	await _step(10)
	recorder.record_to_file(TELEMETRY_FILE)
	_check(recorder.recording and FileAccess.file_exists(TELEMETRY_FILE), "switched on in process it records to the fixed tmp file (%s)" % TELEMETRY_FILE)
	await _step(TELEMETRY_FREE_FRAMES)

	_check(manager.start_mission(0), "a real mission starts through the manager with the recorder listening")
	var peak_speed := 0.0
	Input.action_press("accelerate")
	for frame in TELEMETRY_DRIVE_FRAMES:
		if frame == 60:
			Input.action_press("steer_left")
		if frame == 105:
			Input.action_release("steer_left")
		await physics_frame
		peak_speed = maxf(peak_speed, car.forward_speed)
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	manager.abort_mission()
	await _step(2)
	_check(not recorder.recording, "aborting the run closes the file and ends the recording")
	car.reset_to_spawn()
	(main.get_node("TestPad") as TestPad).reset_cones()

	# Read it back.
	var lines := PackedStringArray()
	for raw in FileAccess.get_file_as_string(TELEMETRY_FILE).split("\n"):
		if not raw.strip_edges().is_empty():
			lines.append(raw)
	if not _check(lines.size() > 10, "the file is written, one line per sample (%d lines)" % lines.size()):
		return
	var objects: Array[Dictionary] = []
	for line in lines:
		var value: Variant = JSON.parse_string(line)
		if value is Dictionary:
			objects.append(value)
	if not _check(objects.size() == lines.size(), "every line is one JSON object (%d of %d lines parsed)" % [objects.size(), lines.size()]):
		return

	var header := objects[0]
	_check(
		header.get("event", "") == "session_start" and header.has("started_at") and header.has("godot_version")
			and int(header.get("sample_stride_ticks", 0)) == TelemetryRecorder.SAMPLE_STRIDE_TICKS
			and int(header.get("physics_ticks_per_second", 0)) == Engine.physics_ticks_per_second,
		"the first line is the session_start object: the wall-clock start (its content is not asserted), the engine, and the %d-tick stride it was sampled at" % TelemetryRecorder.SAMPLE_STRIDE_TICKS,
	)

	var events: Array[Dictionary] = []
	var free_samples: Array[Dictionary] = []
	var mission_samples: Array[Dictionary] = []
	for object in objects:
		if object.has("event"):
			events.append(object)
		elif object.has("mission"):
			mission_samples.append(object)
		else:
			free_samples.append(object)

	var missing := PackedStringArray()
	var shaped := true
	var sample_speed := 0.0
	for sample: Dictionary in free_samples + mission_samples:
		for field in TELEMETRY_SAMPLE_FIELDS:
			if not sample.has(field) and not missing.has(field):
				missing.append(field)
		var position: Variant = sample.get("pos", null)
		shaped = shaped and position is Array and (position as Array).size() == 3
		sample_speed = maxf(sample_speed, float(sample.get("speed_ms", 0.0)))
	_check(
		missing.is_empty() and shaped,
		"every sample carries the car's state: position, heading, speed, gear, rpm, pedals, steering, axle loads, slip angles, slip ratios, yaw rate (missing: %s)" % ("none" if missing.is_empty() else ", ".join(missing)),
	)
	_check(sample_speed > TELEMETRY_MIN_SAMPLE_SPEED and sample_speed <= peak_speed + 0.01, "the samples are the car's own state, not zeroes (fastest sample %.1f m/s, the car's own peak %.1f)" % [sample_speed, peak_speed])

	var context_missing := PackedStringArray()
	for sample: Dictionary in mission_samples:
		for field in TELEMETRY_MISSION_FIELDS:
			if not sample.has(field) and not context_missing.has(field):
				context_missing.append(field)
		var context: Variant = sample.get("mission", null)
		if context is Dictionary:
			for field in TELEMETRY_CONTEXT_FIELDS:
				if not (context as Dictionary).has(field) and not context_missing.has(field):
					context_missing.append(field)
		else:
			context_missing.append("mission (not an object)")
	_check(
		not mission_samples.is_empty() and context_missing.is_empty(),
		"every sample taken during the mission carries the run with it: run time, title, kind, elapsed, progress (%d samples, missing: %s)" % [mission_samples.size(), "none" if context_missing.is_empty() else ", ".join(context_missing)],
	)
	var slalom := HandlingTests.all_tests()[0]
	var first_context: Dictionary = mission_samples[0].get("mission", {}) if not mission_samples.is_empty() else {}
	var first_progress: Dictionary = first_context.get("progress", {})
	_check(
		first_context.get("title", "") == slalom.title and first_context.get("kind", "") == String(slalom.kind) and first_progress.get("kind", "") == String(slalom.kind),
		"the mission block names the test that was running ('%s', kind '%s', progress of the same kind)" % [first_context.get("title", "?"), first_context.get("kind", "?")],
	)

	# The stride, in the only clock the samples know: tick counts times 1/60 s.
	var stride := TelemetryRecorder.SAMPLE_STRIDE_TICKS / 60.0
	var worst_gap := 0.0
	var whole_ticks := true
	for index in range(1, mission_samples.size()):
		var gap: float = float(mission_samples[index].get("t_run_s", 0.0)) - float(mission_samples[index - 1].get("t_run_s", 0.0))
		worst_gap = maxf(worst_gap, absf(gap - stride))
	for sample: Dictionary in mission_samples:
		var ticks: float = float(sample.get("t_session_s", 0.0)) * 60.0
		whole_ticks = whole_ticks and absf(ticks - roundf(ticks)) < 0.01
	_check(
		mission_samples.size() > TELEMETRY_DRIVE_FRAMES / TelemetryRecorder.SAMPLE_STRIDE_TICKS - 3 and worst_gap < TELEMETRY_STRIDE_TOLERANCE,
		"mission samples stand exactly %d ticks apart (%.4f s; worst gap off by %.5f s over %d samples)" % [TelemetryRecorder.SAMPLE_STRIDE_TICKS, stride, worst_gap, mission_samples.size()],
	)
	_check(whole_ticks, "the timestamps are counted in whole physics ticks, not read off the clock")

	var free_stride := TelemetryRecorder.FREE_SAMPLE_STRIDE_TICKS / 60.0
	var worst_free_gap := 0.0
	var free_plain := true
	for index in range(1, free_samples.size()):
		var gap: float = float(free_samples[index].get("t_session_s", 0.0)) - float(free_samples[index - 1].get("t_session_s", 0.0))
		worst_free_gap = maxf(worst_free_gap, absf(gap - free_stride))
	for sample: Dictionary in free_samples:
		free_plain = free_plain and not sample.has("t_run_s")
	_check(
		free_samples.size() >= 2 and worst_free_gap < TELEMETRY_STRIDE_TOLERANCE and free_plain,
		"free driving before the mission is sampled coarser, every %d ticks, with no mission on the line (%d samples, worst gap off by %.5f s)" % [TelemetryRecorder.FREE_SAMPLE_STRIDE_TICKS, free_samples.size(), worst_free_gap],
	)

	var last: Dictionary = objects.back()
	_check(events.size() == 2 and last.get("event", "") == "aborted" and last.size() == 1, "the last line is the abort event and nothing else ('%s')" % lines[lines.size() - 1])
	_check(
		DirAccess.dir_exists_absolute(TelemetryRecorder.ROOT_DIR) == user_dir_before,
		"recording to the fixed path left user://telemetry alone (%s)" % ("it was there before the phase and is unchanged" if user_dir_before else "never created"),
	)


## Tyre marks: the pool in main.tscn, read like the HUD reads the car - what the
## marks script has in its arrays, nothing off the renderer (headless there is
## none).
func _check_tyre_marks(main: Node, car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var pad := main.get_node("TestPad") as TestPad
	var marks := main.get_node_or_null("TyreMarks") as TyreMarks
	if not _check(marks != null and marks.car == car and marks.pad == pad, "marks: main.tscn has the tyre marks, wired to the car and the pad"):
		return
	var finite := true

	# (1) One multimesh of quads, coloured per mark, and the pool empty.
	var multimesh := marks.multimesh
	var material := (multimesh.mesh.surface_get_material(0) as BaseMaterial3D) if multimesh and multimesh.mesh else null
	_check(
		multimesh != null and multimesh.mesh is QuadMesh and multimesh.use_colors and multimesh.instance_count == TyreMarks.MAX_MARKS and marks.get_child_count() == 0,
		"marks: one MultiMesh of %d quads with a colour each, not a node per mark (%d children)" % [TyreMarks.MAX_MARKS, marks.get_child_count()],
	)
	_check(material != null and material.vertex_color_use_as_albedo and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "marks: the material takes colour and alpha per mark (vertex colour as albedo, alpha blended)")
	_check(TyreMarks.MARK_LIFETIME >= 20.0 and TyreMarks.MARK_LIFETIME <= 40.0, "marks: a mark lives 20..40 s (%.0f s)" % TyreMarks.MARK_LIFETIME)
	car.reset_to_spawn()
	await _step(5)
	_check(marks.mark_count == 0 and _marks_empty_places(marks) == TyreMarks.MAX_MARKS, "marks: nothing on the pad after a reset (%d marks, %d of %d places empty)" % [marks.mark_count, _marks_empty_places(marks), TyreMarks.MAX_MARKS])
	_check(
		not TyreMarks.tyre_marks(0.0, ArcadeCar.DRIVE_SLIP_RATIO) and not TyreMarks.tyre_marks(0.0, -ArcadeCar.ABS_SLIP_RATIO) and not TyreMarks.tyre_marks(ArcadeCar.FRONT_PEAK_SLIP_ANGLE, 0.0)
			and TyreMarks.tyre_marks(0.0, -1.0) and TyreMarks.tyre_marks(0.0, 1.0) and TyreMarks.tyre_marks(-0.5, 0.0),
		"marks: a tyre held by TCS (%.2f) or ABS (%.2f) or at its peak slip angle (%.2f rad) marks nothing, a locked, a spinning and a sideways one do (past %.2f / %.2f rad)" % [ArcadeCar.DRIVE_SLIP_RATIO, ArcadeCar.ABS_SLIP_RATIO, ArcadeCar.FRONT_PEAK_SLIP_ANGLE, TyreMarks.MARK_SLIP_RATIO, TyreMarks.MARK_SLIP_ANGLE],
	)
	# The user's verdict on the first marks: cornering marked too easily (the
	# slip angle threshold was 0.2, twice the peak) and every mark was as dark as
	# every other. The threshold is past 2.5 peaks now, and a mark has a severity.
	_check(
		not TyreMarks.tyre_marks(ArcadeCar.FRONT_PEAK_SLIP_ANGLE * 2.5, 0.0) and not TyreMarks.tyre_marks(-ArcadeCar.FRONT_PEAK_SLIP_ANGLE * 2.5, 0.0) and TyreMarks.tyre_marks(ArcadeCar.FRONT_PEAK_SLIP_ANGLE * 4.0, 0.0),
		"marks: a front at two and a half times its peak slip angle (%.3f rad, what full lock gets it to from 30 km/h) marks nothing, at four times it does" % (ArcadeCar.FRONT_PEAK_SLIP_ANGLE * 2.5),
	)
	var severity_rises := true
	for i in 100:
		severity_rises = severity_rises and TyreMarks.mark_severity(0.0, i * 0.03) <= TyreMarks.mark_severity(0.0, (i + 1) * 0.03) and TyreMarks.mark_severity(i * 0.015, 0.0) <= TyreMarks.mark_severity((i + 1) * 0.015, 0.0)
	_check(
		TyreMarks.mark_severity(TyreMarks.MARK_SLIP_ANGLE, TyreMarks.MARK_SLIP_RATIO) == 0.0 and TyreMarks.mark_severity(0.0, 0.0) == 0.0 and TyreMarks.mark_severity(0.0, -1.0) == 1.0 and TyreMarks.mark_severity(0.0, 2.8) == 1.0
			and TyreMarks.mark_severity(-PI * 0.5, 0.0) == 1.0 and TyreMarks.mark_severity(0.4, 0.0) == TyreMarks.mark_severity(-0.4, 0.0) and TyreMarks.mark_severity(0.4, 0.0) > 0.0 and TyreMarks.mark_severity(0.4, 0.0) < 0.5 and severity_rises,
		"marks: a mark's severity is 0 at the thresholds, 1 for a locked wheel (-1), a spinning one (2.8) and a tyre going sideways, rises all the way in between and knows no left or right (%.3f at 0.4 rad)" % TyreMarks.mark_severity(0.4, 0.0),
	)
	_check(
		TyreMarks.mark_fresh_alpha(0.0) == TyreMarks.MARK_FAINT_ALPHA and TyreMarks.mark_fresh_alpha(1.0) == TyreMarks.MARK_COLOR.a and TyreMarks.MARK_FAINT_ALPHA >= 0.1 and TyreMarks.MARK_FAINT_ALPHA <= 0.2 and TyreMarks.MARK_COLOR.a == 0.75,
		"marks: a fresh mark's alpha goes from a faint %.2f at no severity to %.2f at full" % [TyreMarks.MARK_FAINT_ALPHA, TyreMarks.MARK_COLOR.a],
	)

	# (2) Gripping: flat out from rest with TCS, through a gear change, and a
	# full pedal to a stop with ABS, dead straight. Not a mark.
	var peak_drive_slip := 0.0
	var peak_brake_slip := 0.0
	Input.action_press("accelerate")
	for frame in MARKS_GRIP_FRAMES:
		await physics_frame
		peak_drive_slip = maxf(peak_drive_slip, car.rear_slip_ratio)
	Input.action_release("accelerate")
	var grip_speed := car.forward_speed
	Input.action_press("brake")
	for frame in CREEP_WATCH_FRAMES:
		await physics_frame
		peak_brake_slip = minf(peak_brake_slip, minf(car.front_slip_ratio, car.rear_slip_ratio))
		if car.forward_speed == 0.0:
			break
	Input.action_release("brake")
	_check(
		car.tcs_on and car.abs_on and marks.mark_count == 0 and grip_speed > 10.0 and car.forward_speed == 0.0,
		"marks: none while the tyres grip - flat out to %.1f m/s with TCS (slip ratio %.2f at most) and a full pedal to a stop with ABS (%.2f): %d marks" % [grip_speed, peak_drive_slip, peak_brake_slip, marks.mark_count],
	)

	# (3) The handbrake slide leaves trails, and every mark of them is a quad
	# TYRE_WIDTH wide lying on the ground the pad shows, no longer than the
	# spacing and a tick's travel, the newer the younger.
	var slide := await _marks_slide(car, marks)
	finite = finite and slide.finite
	_check(slide.count > 0 and slide.peak_rear_slip == -1.0, "marks: a handbrake slide from %.0f km/h leaves marks (%d of them, the rears locked at a slip ratio of %.2f, the tail out to %.2f rad)" % [slide.entry_speed * 3.6, slide.count, slide.peak_rear_slip, slide.peak_rear_angle])
	var worst_width := 0.0
	var worst_height := 0.0
	var shortest := INF
	var longest := 0.0
	var worst_lean := 0.0
	var face_up := true
	var in_order := marks.oldest_mark() == 0
	for slot in marks.mark_count:
		var mark := marks.mark_transforms[slot]
		worst_width = maxf(worst_width, absf(mark.basis.x.length() - TyreMarks.TYRE_WIDTH))
		worst_height = maxf(worst_height, absf(mark.origin.y - pad.elevation_height(mark.origin.x, mark.origin.z) - TyreMarks.MARK_LIFT))
		shortest = minf(shortest, mark.basis.z.length())
		longest = maxf(longest, mark.basis.z.length())
		worst_lean = maxf(worst_lean, 1.0 - mark.basis.y.normalized().dot(Vector3.UP))
		face_up = face_up and mark.basis.determinant() > 0.0
		in_order = in_order and (slot == 0 or marks.mark_ages[slot] <= marks.mark_ages[slot - 1])
	_check(worst_width < 0.00001 and worst_height < MARKS_GROUND_TOLERANCE and worst_lean < 0.001 and face_up, "marks: every mark is a tyre wide (%.2f m) and lies on the ground the pad shows, %.3f m over it (off by %.6f m at most), face up and not mirrored" % [TyreMarks.TYRE_WIDTH, TyreMarks.MARK_LIFT, worst_height])
	_check(
		shortest >= TyreMarks.MARK_MIN_LENGTH and longest < TyreMarks.MARK_SPACING + slide.max_step + 0.1 and slide.count < slide.wheel_ticks,
		"marks: a trail is a mark every %.1f m, not one a tick (%.2f .. %.2f m long; %d marks from %d ticks of a wheel marking)" % [TyreMarks.MARK_SPACING, shortest, longest, slide.count, slide.wheel_ticks],
	)
	var slide_full := 0
	var slide_alpha_sum := 0.0
	var slide_darkest := 0.0
	var severities_in_range := true
	for slot in marks.mark_count:
		var severity := marks.mark_severities[slot]
		severities_in_range = severities_in_range and severity >= 0.0 and severity <= 1.0
		slide_alpha_sum += TyreMarks.mark_fresh_alpha(severity)
		slide_darkest = maxf(slide_darkest, TyreMarks.mark_fresh_alpha(severity))
		if severity == 1.0:
			slide_full += 1
	var slide_mean_alpha := slide_alpha_sum / maxi(marks.mark_count, 1)
	_check(
		severities_in_range and slide_darkest == TyreMarks.MARK_COLOR.a and slide_full >= slide.count * MARKS_SLIDE_MIN_FULL_SHARE,
		"marks: the handbrake slide marks dark and heavy - %d of its %d marks as dark as a mark gets (alpha %.2f, the locked rears'), %.2f on average" % [slide_full, slide.count, slide_darkest, slide_mean_alpha],
	)
	_check(in_order and marks.mark_ages[0] > marks.mark_ages[marks.mark_count - 1], "marks: the pool fills in order, the first mark the oldest (%.2f s, the last %.2f s)" % [marks.mark_ages[0], marks.mark_ages[marks.mark_count - 1]])

	# (4) The fade, tick by tick, with nothing driving: alpha down every tick,
	# by the tick's share of the lifetime.
	var slot_watched := marks.mark_count - 1
	var fading := true
	var alpha_before := marks.mark_alpha(slot_watched)
	var alpha_start := alpha_before
	var age_start := marks.mark_ages[slot_watched]
	for frame in MARKS_FADE_FRAMES:
		await physics_frame
		var alpha := marks.mark_alpha(slot_watched)
		fading = fading and alpha < alpha_before and alpha > 0.0
		alpha_before = alpha
	var age_gained := marks.mark_ages[slot_watched] - age_start
	var alpha_lost := alpha_start - alpha_before
	# was alpha lost = MARK_COLOR.a x the share of the lifetime, every mark as
	# dark as every other -> the mark's own fresh alpha x that share (the user's
	# verdict: no severity in the marks; see mark_severity). The same fade, from
	# wherever the mark started.
	var fresh_alpha := TyreMarks.mark_fresh_alpha(marks.mark_severities[slot_watched])
	_check(
		fading and absf(age_gained - MARKS_FADE_FRAMES * tick) < 0.000001 and absf(alpha_lost - fresh_alpha * age_gained / TyreMarks.MARK_LIFETIME) < 0.000001,
		"marks: a mark fades every physics tick (alpha %.4f -> %.4f over %.0f s, %.4f s older)" % [alpha_start, alpha_before, MARKS_FADE_FRAMES * tick, age_gained],
	)
	finite = finite and _marks_finite(marks)

	# (5) The same slide again leaves the same marks, to the bit; and the car
	# drives it the same with the marks switched off.
	var again := await _marks_slide(car, marks)
	finite = finite and again.finite
	_check(
		again.count == slide.count and again.transforms == slide.transforms and again.ages == slide.ages and again.severities == slide.severities and again.next == slide.next,
		"marks: the same slide from a reset leaves the same marks, transforms, ages and severities to the bit (%d and %d marks)" % [slide.count, again.count],
	)
	marks.process_mode = Node.PROCESS_MODE_DISABLED
	var unmarked := await _marks_slide(car, marks)
	marks.process_mode = Node.PROCESS_MODE_INHERIT
	_check(
		unmarked.end == slide.end and unmarked.end_speed == slide.end_speed and unmarked.end_yaw_rate == slide.end_yaw_rate and unmarked.end_rpm == slide.end_rpm,
		"marks: the car never reads them - the slide with the marks switched off ends where it ends with them, to the bit (%.3f, %.3f, heading %.4f rad, %.3f m/s)" % [slide.end.origin.x, slide.end.origin.z, slide.end.basis.get_euler().y, slide.end_speed],
	)

	# (6) A reset clears the marks: reset_to_spawn, reset_to and the key alike.
	marks.lay_mark(Vector3(5.0, 0.0, 5.0), Vector3(5.5, 0.0, 5.0))
	var before_reset := marks.mark_count
	car.reset_to_spawn()
	await _step(2)
	var after_spawn_reset := marks.mark_count
	marks.lay_mark(Vector3(5.0, 0.0, 5.0), Vector3(5.5, 0.0, 5.0))
	car.reset_to(car.get_spawn_transform().translated(Vector3(3.0, 0.0, 0.0)))
	await _step(2)
	var after_reset_to := marks.mark_count
	marks.lay_mark(Vector3(5.0, 0.0, 5.0), Vector3(5.5, 0.0, 5.0))
	await _tap("reset_car")
	_check(
		before_reset > 0 and after_spawn_reset == 0 and after_reset_to == 0 and marks.mark_count == 0 and _marks_empty_places(marks) == TyreMarks.MAX_MARKS,
		"marks: a reset clears them (%d marks before reset_to_spawn, %d after; %d after reset_to; %d after the reset key; every place empty)" % [before_reset, after_spawn_reset, after_reset_to, marks.mark_count],
	)

	# (7) The launch without TCS: the rears spin and mark, the fronts roll - the
	# marks are, end to end, the way the car went on spinning rears, twice (two
	# wheels), in the two rear wheel tracks.
	car.tcs_on = false
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	var spin := await _marks_watch(car, CONTROLS_LAUNCH_FRAMES, false)
	Input.action_release("accelerate")
	car.tcs_on = true
	await _step(2)
	var spin_trail := _marks_trail_length(marks)
	var off_track := 0.0
	for slot in marks.mark_count:
		off_track = maxf(off_track, absf(absf(marks.mark_transforms[slot].origin.x) - ArcadeCar.HALF_TRACK))
	_check(
		marks.mark_count > 0 and spin.front_way == 0.0 and spin.rear_way > 1.0 and off_track < 0.01
			and spin_trail >= spin.rear_way * 2.0 * MARKS_MIN_TRAIL_SHARE and spin_trail <= spin.rear_way * 2.0 + spin.max_step * 4.0,
		"marks: a launch with TCS off leaves the rears' wheelspin on the road (slip ratio %.2f: %.1f m on spinning rears, %.1f m of marks in their two tracks, %d marks; the fronts none)" % [spin.peak_rear_slip, spin.rear_way, spin_trail, marks.mark_count],
	)
	finite = finite and _marks_finite(marks)

	# (8) The stop without ABS: the fronts stand still and their marks are as
	# long as the way the car slid on them - the length is the patch's way over
	# the ground, the wheel's own speed is 0.
	car.abs_on = false
	await _reach_speed(car, CONTROLS_BRAKE_SPEED)
	Input.action_press("brake")
	var stop := await _marks_watch(car, CREEP_WATCH_FRAMES, true)
	Input.action_release("brake")
	car.abs_on = true
	await _step(2)
	var stop_trail := _marks_trail_length(marks)
	var stop_way: float = (stop.front_way + stop.rear_way) * 2.0
	_check(
		stop.locked_way > 20.0 and stop.locked_way <= stop.front_way and stop_trail >= stop_way * MARKS_MIN_TRAIL_SHARE and stop_trail <= stop_way + stop.max_step * 4.0,
		"marks: a stop on locked fronts (ABS off, wheel speed 0 for %.1f m) marks the way the car slid: %.1f m on marking fronts, %.1f m on marking rears, %.1f m of marks (%d)" % [stop.locked_way, stop.front_way, stop.rear_way, stop_trail, marks.mark_count],
	)
	finite = finite and _marks_finite(marks)

	# (9) The pool is bounded: one mark more than it holds goes where the oldest
	# was, and the count stands.
	car.reset_to_spawn()
	await _step(2)
	for i in TyreMarks.MAX_MARKS:
		marks.lay_mark(Vector3(i, 0.0, 50.0), Vector3(i + 0.5, 0.0, 50.0))
	var full_count := marks.mark_count
	var first_place := marks.mark_transforms[0]
	var second_place := marks.mark_transforms[1]
	marks.lay_mark(Vector3(0.0, 0.0, 60.0), Vector3(0.5, 0.0, 60.0))
	_check(
		full_count == TyreMarks.MAX_MARKS and marks.mark_count == TyreMarks.MAX_MARKS and marks.mark_transforms.size() == TyreMarks.MAX_MARKS and marks.mark_ages.size() == TyreMarks.MAX_MARKS,
		"marks: the pool is bounded - %d marks laid, %d on the pad, %d places" % [TyreMarks.MAX_MARKS + 1, marks.mark_count, marks.mark_transforms.size()],
	)
	_check(
		marks.mark_transforms[0] != first_place and marks.mark_transforms[0].origin.z == 60.0 and marks.mark_transforms[1] == second_place and marks.oldest_mark() == 1,
		"marks: full, the oldest mark is the one laid anew (place 0 moved from z = %.0f to %.0f, place 1 is the oldest now and lies where it lay)" % [first_place.origin.z, marks.mark_transforms[0].origin.z],
	)
	marks.lay_mark(Vector3(1.0, 0.0, 70.0), Vector3(1.0, 0.0, 70.0))
	marks.lay_mark(Vector3(NAN, 0.0, 70.0), Vector3(1.0, 0.0, 70.0))
	_check(marks.oldest_mark() == 1 and _marks_finite(marks), "marks: a mark of no length or not finite is not laid (the pool as it was)")

	# (10) The end of the fade frees the place: three marks, a fourth
	# MARKS_LATE_FRAMES later, and physics time to the early ones' lifetime.
	car.reset_to_spawn()
	await _step(2)
	for i in 3:
		marks.lay_mark(Vector3(i, 0.0, 50.0), Vector3(i + 0.5, 0.0, 50.0))
	await _step(MARKS_LATE_FRAMES)
	marks.lay_mark(Vector3(3.0, 0.0, 50.0), Vector3(3.5, 0.0, 50.0))
	var lifetime_frames := ceili(TyreMarks.MARK_LIFETIME / tick)
	await _step(lifetime_frames - MARKS_LATE_FRAMES - 2)
	var early_alpha := marks.mark_alpha(0)
	var count_before_end := marks.mark_count
	await _step(4)
	_check(
		count_before_end == 4 and early_alpha > 0.0 and early_alpha < 0.001 and marks.mark_count == 1 and marks.oldest_mark() == 3
			and marks.mark_transforms[0] == TyreMarks.NO_MARK and marks.mark_alpha(0) == 0.0 and marks.mark_ages[0] == 0.0 and marks.mark_alpha(3) > 0.0,
		"marks: at the end of its %.0f s a mark is gone and its place free (alpha %.5f two ticks before; of 4 marks the late one is left, alpha %.4f)" % [TyreMarks.MARK_LIFETIME, early_alpha, marks.mark_alpha(3)],
	)
	await _step(MARKS_LATE_FRAMES)
	_check(marks.mark_count == 0 and _marks_empty_places(marks) == TyreMarks.MAX_MARKS, "marks: %.0f s later the late one has gone too, the pool is empty (%d marks)" % [MARKS_LATE_FRAMES * tick, marks.mark_count])

	# (11) Cornering on tyres that grip lays nothing: full lock off the throttle
	# from 30 km/h, the user's complaint about the first marks (they began at a
	# slip angle of 0.2 rad, and this corner gets the fronts to 0.25).
	var clean := await _marks_corner(car, marks, MARKS_CLEAN_CORNER_SPEED)
	finite = finite and clean.finite
	_check(
		clean.count == 0 and clean.peak_front_angle > 0.2 and clean.peak_front_angle < TyreMarks.MARK_SLIP_ANGLE,
		"marks: full lock off the throttle from %.0f km/h lays nothing (the fronts to %.3f rad, the marks begin at %.2f; they began at 0.20)" % [clean.entry_speed * 3.6, clean.peak_front_angle, TyreMarks.MARK_SLIP_ANGLE],
	)

	# (12) Severity: the same from 45 km/h has the fronts ploughing just past the
	# threshold, and what they leave is a shade; the handbrake slide's marks are
	# black against it. And a shade is the same shade every time.
	var scrub := await _marks_corner(car, marks, MARKS_SCRUB_SPEED)
	var scrub_again := await _marks_corner(car, marks, MARKS_SCRUB_SPEED)
	finite = finite and scrub.finite and scrub_again.finite
	_check(
		scrub.count > 0 and scrub.darkest < MARKS_SCRUB_MAX_ALPHA and scrub.faintest >= TyreMarks.MARK_FAINT_ALPHA and scrub.peak_rear_angle < TyreMarks.MARK_SLIP_ANGLE,
		"marks: the same from %.0f km/h, the fronts ploughing at %.2f rad, leaves faint marks (%d of them, fresh alpha %.3f .. %.3f; the rears none)" % [scrub.entry_speed * 3.6, scrub.peak_front_angle, scrub.count, scrub.faintest, scrub.darkest],
	)
	_check(
		slide_darkest > scrub.darkest * MARKS_SLIDE_MIN_DARKER and slide_mean_alpha > scrub.darkest * MARKS_SLIDE_MIN_DARKER,
		"marks: a handbrake mark is darker than a slow scrub's - alpha %.2f at its darkest and %.2f on average against the scrub's darkest %.3f" % [slide_darkest, slide_mean_alpha, scrub.darkest],
	)
	_check(
		scrub_again.count == scrub.count and scrub_again.severities == scrub.severities and scrub_again.transforms == scrub.transforms,
		"marks: the same scrub again leaves the same shades, severities and transforms to the bit (%d and %d marks)" % [scrub.count, scrub_again.count],
	)

	_check(finite and _marks_finite(marks), "marks: no NaN / inf in any mark's transform, age or severity throughout")
	car.reset_to_spawn()
	await _step(2)


## The marks' scripted slide: from a reset to ~60 km/h, SLIDE_SETTLE_STEER of
## left steering and the handbrake for MARKS_SLIDE_FRAMES, everything let go
## for MARKS_SLIDE_WATCH_FRAMES. Returns what the pool holds at the end (count,
## copies of the transforms, ages and severities, the next place), how the rears slid, the
## ticks of a wheel marking (two an axle), the longest step of a tick [m], where and how
## the car ended and whether the pool was finite on every tick.
func _marks_slide(car: ArcadeCar, marks: TyreMarks) -> Dictionary:
	await _get_up_to_speed(car)
	var slide := {
		"entry_speed": car.forward_speed, "peak_rear_slip": 0.0, "peak_rear_angle": 0.0, "wheel_ticks": 0,
		"max_step": 0.0, "finite": true, "count": 0, "transforms": [], "ages": PackedFloat64Array(), "severities": PackedFloat32Array(), "next": 0,
		"end": Transform3D.IDENTITY, "end_speed": 0.0, "end_yaw_rate": 0.0, "end_rpm": 0.0,
	}
	Input.action_press("steer_left", SLIDE_SETTLE_STEER)
	Input.action_press("handbrake")
	for frame in MARKS_SLIDE_FRAMES + MARKS_SLIDE_WATCH_FRAMES:
		if frame == MARKS_SLIDE_FRAMES:
			Input.action_release("handbrake")
			Input.action_release("steer_left")
		var before := car.global_position
		await physics_frame
		slide.max_step = maxf(slide.max_step, car.global_position.distance_to(before))
		slide.peak_rear_slip = minf(slide.peak_rear_slip, car.rear_slip_ratio)
		slide.peak_rear_angle = maxf(slide.peak_rear_angle, absf(car.rear_slip_angle))
		if TyreMarks.tyre_marks(car.front_slip_angle, car.front_slip_ratio):
			slide.wheel_ticks += 2
		if TyreMarks.tyre_marks(car.rear_slip_angle, car.rear_slip_ratio):
			slide.wheel_ticks += 2
		slide.finite = slide.finite and _marks_finite(marks)
	slide.count = marks.mark_count
	slide.transforms = marks.mark_transforms.duplicate()
	slide.ages = marks.mark_ages.duplicate()
	slide.severities = marks.mark_severities.duplicate()
	slide.next = marks.oldest_mark() + marks.mark_count
	slide.end = car.global_transform
	slide.end_speed = car.forward_speed
	slide.end_yaw_rate = car.yaw_rate
	slide.end_rpm = car.engine_rpm
	return slide


## The marks' scripted corner: from a reset to `speed`, off the throttle, full
## left lock for MARKS_SCRUB_FRAMES, the wheel let go and two ticks for the last
## of a trail. Returns the speed going in, the axles' peak slip angles, what the
## pool holds at the end (count, copies of the transforms and severities, the
## faintest and the darkest fresh alpha) and whether it was finite on every tick.
func _marks_corner(car: ArcadeCar, marks: TyreMarks, speed: float) -> Dictionary:
	await _reach_speed(car, speed)
	var corner := {
		"entry_speed": car.forward_speed, "peak_front_angle": 0.0, "peak_rear_angle": 0.0, "finite": true,
		"count": 0, "transforms": [], "severities": PackedFloat32Array(), "faintest": INF, "darkest": 0.0,
	}
	Input.action_press("steer_left")
	for frame in MARKS_SCRUB_FRAMES:
		await physics_frame
		corner.peak_front_angle = maxf(corner.peak_front_angle, absf(car.front_slip_angle))
		corner.peak_rear_angle = maxf(corner.peak_rear_angle, absf(car.rear_slip_angle))
		corner.finite = corner.finite and _marks_finite(marks)
	Input.action_release("steer_left")
	await _step(2)
	corner.count = marks.mark_count
	corner.transforms = marks.mark_transforms.duplicate()
	corner.severities = marks.mark_severities.duplicate()
	for slot in marks.mark_count:
		var alpha := TyreMarks.mark_fresh_alpha(marks.mark_severities[slot])
		corner.faintest = minf(corner.faintest, alpha)
		corner.darkest = maxf(corner.darkest, alpha)
	return corner


## Steps `frames` ticks of a straight run (to a standstill at the latest, if
## `until_rest`): the way the car went while the front tyres were marking, the
## rear ones, and of the fronts' the way on wheels standing still [m], the
## longest way of a tick [m] and the rears' peak slip ratio.
func _marks_watch(car: ArcadeCar, frames: int, until_rest: bool) -> Dictionary:
	var seen := {"front_way": 0.0, "rear_way": 0.0, "locked_way": 0.0, "max_step": 0.0, "peak_rear_slip": 0.0}
	for frame in frames:
		var before := car.global_position
		await physics_frame
		var way := car.global_position.distance_to(before)
		seen.max_step = maxf(seen.max_step, way)
		if TyreMarks.tyre_marks(car.front_slip_angle, car.front_slip_ratio):
			seen.front_way += way
			if car.front_omega == 0.0:
				seen.locked_way += way
		if TyreMarks.tyre_marks(car.rear_slip_angle, car.rear_slip_ratio):
			seen.rear_way += way
		seen.peak_rear_slip = maxf(seen.peak_rear_slip, absf(car.rear_slip_ratio))
		if until_rest and car.forward_speed == 0.0:
			break
	return seen


## The live marks laid end to end [m].
func _marks_trail_length(marks: TyreMarks) -> float:
	var length := 0.0
	var slot := marks.oldest_mark()
	for i in marks.mark_count:
		length += marks.mark_transforms[slot].basis.z.length()
		slot = (slot + 1) % TyreMarks.MAX_MARKS
	return length


## True if every place of the marks' pool holds finite numbers.
func _marks_finite(marks: TyreMarks) -> bool:
	for slot in TyreMarks.MAX_MARKS:
		if not marks.mark_transforms[slot].is_finite() or not is_finite(marks.mark_ages[slot]) or not is_finite(marks.mark_severities[slot]):
			return false
	return true


## How many places of the marks' pool are empty.
func _marks_empty_places(marks: TyreMarks) -> int:
	var empty := 0
	for slot in TyreMarks.MAX_MARKS:
		if marks.mark_transforms[slot] == TyreMarks.NO_MARK and marks.mark_ages[slot] == 0.0 and marks.mark_severities[slot] == 0.0 and marks.mark_alpha(slot) == 0.0:
			empty += 1
	return empty


## The stability switch: on unless switched off, a key, a lamp, left alone by a
## reset; off, the assist is gone on every branch and a slide shows it; the
## low-speed blend is not the switch's to take.
func _check_stability_switch(main: Node, car: ArcadeCar) -> void:
	var sc_lamp := main.get_node_or_null("HUD/ScLamp") as Label
	var abs_lamp := main.get_node_or_null("HUD/AbsLamp") as Label
	var tcs_lamp := main.get_node_or_null("HUD/TcsLamp") as Label
	car.reset_to_spawn()
	await _step(5)
	_check(InputMap.has_action("sc_toggle") and car.sc_on, "stability: the car starts with the stability assist on, and there is a key for it")
	if not _check(sc_lamp != null and sc_lamp.text == "SC" and sc_lamp.get_theme_color("font_color") == HUD.AID_ON_COLOR, "stability: the HUD's third aid lamp is quiet while the assist is on ('%s', dim)" % (sc_lamp.text if sc_lamp else "?")):
		return
	_check(
		sc_lamp.offset_right <= tcs_lamp.offset_left and tcs_lamp.offset_right <= abs_lamp.offset_left and sc_lamp.offset_top == abs_lamp.offset_top and sc_lamp.offset_bottom == abs_lamp.offset_bottom,
		"stability: the lamp sits in the row of the other two, left of them and clear of them (SC to %.0f, TCS from %.0f to %.0f, ABS from %.0f)" % [sc_lamp.offset_right, tcs_lamp.offset_left, tcs_lamp.offset_right, abs_lamp.offset_left],
	)
	var damping_on := car._slide_yaw_damping(20.0, 0.0)
	await _tap("sc_toggle")
	await _step(2)
	_check(not car.sc_on and car.tcs_on and car.abs_on, "stability: the SC key switches the assist off and leaves TCS and ABS alone (SC %s, TCS %s, ABS %s)" % [car.sc_on, car.tcs_on, car.abs_on])
	_check(sc_lamp.text == "SC OFF" and sc_lamp.get_theme_color("font_color") == HUD.AID_OFF_COLOR and tcs_lamp.text == "TCS" and abs_lamp.text == "ABS", "stability: the lamp lights up and says OFF, the other two stay quiet ('%s', '%s', '%s')" % [sc_lamp.text, tcs_lamp.text, abs_lamp.text])
	var damping_off := car._slide_yaw_damping(20.0, 0.0)
	var damping_off_slow := car._slide_yaw_damping(ArcadeCar.SPIN_MIN_SPEED * 0.5, 0.0)
	var damping_off_sideways := car._slide_yaw_damping(0.0, 20.0)
	car.reverse_engaged = true
	var damping_off_reverse := car._slide_yaw_damping(-20.0, 0.0)
	car.sc_on = true
	var damping_on_reverse := car._slide_yaw_damping(-20.0, 0.0)
	car.sc_on = false
	_check(
		damping_on == ArcadeCar.SLIDE_YAW_DAMPING and damping_on_reverse == ArcadeCar.SPIN_YAW_DAMPING and damping_off == 0.0 and damping_off_slow == 0.0 and damping_off_sideways == 0.0 and damping_off_reverse == 0.0,
		"stability: switched off, the assist has no strength on any branch - rolling straight %.1f -> %.1f 1/s, and none at a crawl, sideways or in reverse (%.1f with it on)" % [damping_on, damping_off, damping_on_reverse],
	)
	car.reset_to_spawn()
	await _step(5)
	_check(not car.sc_on and not car.reverse_engaged and sc_lamp.text == "SC OFF", "stability: a reset leaves the switch as the driver has it (SC %s, '%s')" % [car.sc_on, sc_lamp.text])

	# The same flick of the handbrake with and without: with the assist the tail
	# is checked and the car rolls on; without, the nose swings far further out
	# and the car turns far further before its tyres have it back.
	var without := await _slide_and_let_go(car, SLIDE_FLICK_FRAMES)
	var still_off := not car.sc_on
	car.sc_on = true
	var with := await _slide_and_let_go(car, SLIDE_FLICK_FRAMES)
	_check(
		still_off and without.peak_angle > with.peak_angle * SC_MIN_ANGLE_GAIN and absf(without.turned) > absf(with.turned) + SC_MIN_TURN_GAIN,
		"stability: the same flick of the handbrake slides far deeper without the assist - the nose %.2f rad off the way the car goes against %.2f, the car turned %.2f rad against %.2f" % [without.peak_angle, with.peak_angle, absf(without.turned), absf(with.turned)],
	)
	_check(
		(without.in_line_at < 0.0 or without.in_line_at > with.in_line_at) and with.in_line_at >= 0.0,
		"stability: ... and hangs on longer (back in line %.2f s after the release against %.2f s; -1 = never)" % [without.in_line_at, with.in_line_at],
	)
	_check(without.finite and with.finite and without.max_step < SLIDE_SETTLE_MAX_STEP, "stability: no NaN / inf and no teleporting through either slide (largest step %.2f m without)" % without.max_step)

	# The low-speed blend is numerics, not an aid: with the assist off a car
	# creeping round at full lock is still eased onto its rolling circle.
	car.sc_on = false
	car.reset_to_spawn()
	await _step(5)
	await _brake_to_a_stop(car)
	await _step(CREEP_HOLD_FRAMES)
	Input.action_release("brake")
	Input.action_press("steer_left")
	await _step(SC_CREEP_FRAMES)
	var rolling_yaw_rate := car.forward_speed * tan(car.wheel_angle) / (2.0 * ArcadeCar.AXLE_DISTANCE)
	var creep_speed := car.forward_speed
	var creep_yaw_rate := car.yaw_rate
	Input.action_release("steer_left")
	car.sc_on = true
	_check(
		creep_speed > 0.1 and creep_speed < ArcadeCar.LOW_SPEED_BLEND_END and rolling_yaw_rate > 0.0 and absf(creep_yaw_rate - rolling_yaw_rate) < rolling_yaw_rate * SC_ROLLING_TOLERANCE,
		"stability: the low-speed blend has no switch - assist off, creeping at %.2f m/s on full lock the car turns at %.4f rad/s, its rolling circle's %.4f" % [creep_speed, creep_yaw_rate, rolling_yaw_rate],
	)
	car.reset_to_spawn()
	await _step(5)
	_check(car.sc_on and sc_lamp.text == "SC", "stability: switched back on, the lamp is quiet again ('%s')" % sc_lamp.text)


## The starter's crank cycle: a tap of the key cranks for STARTER_CYCLE_TIME,
## which starts a stalled engine; a dry tank is cranked for as long and never
## catches; held, the key cranks for as long as it is held.
func _check_starter_cycle(main: Node, car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var rpm_label := main.get_node("HUD/RpmLabel") as Label
	var cycle_ticks := roundi(ArcadeCar.STARTER_CYCLE_TIME / tick)
	_check(ArcadeCar.STARTER_CYCLE_TIME >= 0.5 and ArcadeCar.STARTER_CYCLE_TIME <= 1.5, "starter: a press cranks for 0.5..1.5 s (%.1f s)" % ArcadeCar.STARTER_CYCLE_TIME)

	# (1) Stalled as the controls phase stalls it (the clutch pedal let go on an
	# idling engine), fuel in the tank: one tap, a tick long, and hands off.
	car.reset_to_spawn()
	car.automatic = false
	await _step(5)
	Input.action_press("clutch_pedal")
	await _step(CONTROLS_CLUTCH_FRAMES)
	Input.action_release("clutch_pedal")
	Input.action_press("accelerate")
	for frame in CONTROLS_LAUNCH_FRAMES:
		await physics_frame
		if not car.engine_running:
			break
	Input.action_release("accelerate")
	await _brake_to_a_stop(car)
	Input.action_release("brake")
	await _step(CONTROLS_STALLED_FRAMES)
	var stalled := not car.engine_running and car.engine_rpm == 0.0 and not car.cranking() and rpm_label.text.ends_with("STALL")
	var fuel_before := car.fuel_l
	await _tap("starter")
	var key_up := not Input.is_action_pressed("starter")
	var said_cranking := rpm_label.text.ends_with("CRANKING") and not rpm_label.text.contains("STALL")
	var cranked_hands_off := car.cranking()
	var caught_at := -1.0
	var fuel_at_catch := 0.0
	for frame in STARTER_WATCH_FRAMES:
		await physics_frame
		said_cranking = said_cranking or (rpm_label.text.ends_with("CRANKING") and not car.engine_running)
		if caught_at < 0.0 and car.engine_running:
			caught_at = (frame + 2) * tick
			fuel_at_catch = car.fuel_l
	_check(stalled and key_up and cranked_hands_off, "starter: a tap of the key, one tick long, on a stalled engine and the starter cranks on with the key up")
	_check(caught_at > 0.0 and caught_at < 1.0 and fuel_at_catch == fuel_before, "starter: the tap starts the engine, and cranking burns no fuel (caught %.2f s after the press; a tick of cranking used to leave it at ~96 rpm)" % caught_at)
	_check(said_cranking and not rpm_label.text.contains("CRANKING") and not rpm_label.text.contains("STALL"), "starter: the tach says CRANKING while it does, and nothing of it once the engine runs ('%s')" % rpm_label.text)
	_check(car.engine_running and not car.cranking() and car._crank_timer == 0.0 and absf(car.engine_rpm - ArcadeCar.IDLE_RPM) < CONTROLS_IDLE_TOLERANCE and car.fuel_l < fuel_before, "starter: the catch ends the cycle, the idle controller has the engine and it burns again (%d rpm)" % car.engine_rpm)

	# (2) A tap on a running engine is nothing: no cycle waits for the next stall.
	var idle_stats := _new_stats()
	await _tap("starter")
	var armed := car.cranking() or car._crank_timer > 0.0
	await _drive(car, CONTROLS_STALLED_FRAMES, idle_stats)
	_check(not armed and idle_stats.max_rpm - idle_stats.min_rpm < CONTROLS_IDLE_TOLERANCE and idle_stats.finite, "starter: a tap on a running engine starts no cycle and leaves it alone (%d..%d rpm)" % [idle_stats.min_rpm, idle_stats.max_rpm])

	# (3) A dry tank: the tap cranks its cycle, the engine spins and never
	# catches, and at the end of the cycle the starter lets go.
	car.fuel_l = 0.0
	await _step(FUEL_DRY_RUN_DOWN_FRAMES)
	var ran_down := not car.engine_running and car.engine_rpm == 0.0
	await _tap("starter")
	var cranking_ticks := 1
	var peak_rpm := 0.0
	var ever_ran := false
	while car.cranking() and cranking_ticks < STARTER_WATCH_FRAMES:
		await physics_frame
		cranking_ticks += 1
		peak_rpm = maxf(peak_rpm, car.engine_rpm)
		ever_ran = ever_ran or car.engine_running
	for frame in STARTER_WATCH_FRAMES:
		await physics_frame
		ever_ran = ever_ran or car.engine_running
	_check(
		ran_down and not ever_ran and absi(cranking_ticks - cycle_ticks) <= STARTER_CYCLE_TOLERANCE_TICKS and peak_rpm > ArcadeCar.STALL_RPM and peak_rpm < ArcadeCar.STARTER_FREE_RPM,
		"starter: on a dry tank the tap cranks for its cycle and the engine never catches (%d ticks of cranking, %.2f s; spun to %d rpm)" % [cranking_ticks, cranking_ticks * tick, peak_rpm],
	)
	_check(not car.cranking() and not car.engine_running and car.engine_rpm == 0.0 and car.fuel_l == 0.0 and rpm_label.text.ends_with("STALL"), "starter: the cycle over, the starter lets go and the engine stands (%d rpm, '%s')" % [car.engine_rpm, rpm_label.text])

	# (4) Held, the key cranks for as long as it is held, past the cycle; let go
	# after that, the starter stops with it.
	Input.action_press("starter")
	await _step(STARTER_HOLD_FRAMES)
	var held_cranking := car.cranking() and car.engine_rpm > ArcadeCar.STALL_RPM and not car.engine_running
	var held_rpm := car.engine_rpm
	Input.action_release("starter")
	await _step(2)
	_check(STARTER_HOLD_FRAMES > cycle_ticks and held_cranking and not car.cranking(), "starter: held, the key cranks for as long as it is held (still spinning at %d rpm after %.1f s, the cycle is %.1f s), and the starter stops when it is let go" % [held_rpm, STARTER_HOLD_FRAMES * tick, ArcadeCar.STARTER_CYCLE_TIME])

	# (5) A reset in the middle of a cycle: the engine runs, as after any reset,
	# and the cycle is over.
	await _step(CONTROLS_STALLED_FRAMES)
	await _tap("starter")
	var mid_cycle := car.cranking()
	car.reset_to_spawn()
	await _step(CONTROLS_STALLED_FRAMES)
	_check(mid_cycle and car.engine_running and not car.cranking() and car._crank_timer == 0.0 and absf(car.engine_rpm - ArcadeCar.IDLE_RPM) < CONTROLS_IDLE_TOLERANCE, "starter: a reset in the middle of a cycle starts the engine as ever and ends the cycle (%d rpm)" % car.engine_rpm)


## The wheels at speed: drawn turning by their real step folded into a quarter
## turn either way, which past 115 km/h reads as turning backwards - the
## wagon-wheel effect the user missed under the old cap on the drawn spin.
func _check_wheel_strobe(car: ArcadeCar) -> void:
	var tick := 1.0 / Engine.physics_ticks_per_second
	var front_spinner := car.get_node("Wheels/FrontLeft/Spin") as Node3D
	var rear_spinner := car.get_node("Wheels/RearRight/Spin") as Node3D
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in STROBE_RUN_UP_FRAMES:
		if car.forward_speed >= STROBE_SPEED:
			break
		await physics_frame
	var largest_step := 0.0
	var worst_residual := 0.0
	var slowest_omega := INF
	var backwards := true
	for frame in STROBE_FRAMES:
		var front_before := front_spinner.basis
		var rear_before := rear_spinner.basis
		await physics_frame
		var steps := [_turned_about_x(front_before, front_spinner.basis), _turned_about_x(rear_before, rear_spinner.basis)]
		var omegas := [car.front_omega, car.rear_omega]
		for axle in 2:
			largest_step = maxf(largest_step, absf(steps[axle]))
			# Rolling forwards is a negative rotation about +X: drawn step + real
			# step is nothing, or whole half turns (what the one bar hides).
			worst_residual = maxf(worst_residual, absf(wrapf(steps[axle] + omegas[axle] * tick, -ArcadeCar.WHEEL_DRAW_PERIOD * 0.5, ArcadeCar.WHEEL_DRAW_PERIOD * 0.5)))
			slowest_omega = minf(slowest_omega, omegas[axle])
			backwards = backwards and steps[axle] > 0.0
	Input.action_release("accelerate")
	_check(ArcadeCar.WHEEL_DRAW_PERIOD == PI and slowest_omega * tick > ArcadeCar.WHEEL_DRAW_PERIOD * 0.5 and slowest_omega * tick < ArcadeCar.WHEEL_DRAW_PERIOD, "strobe: at %.0f km/h the wheels turn more than a quarter turn a tick (%.1f rad/s, %.2f rad a tick; the bar across the rim looks the same every half turn)" % [car.speed_kmh, slowest_omega, slowest_omega * tick])
	_check(largest_step <= ArcadeCar.WHEEL_DRAW_PERIOD * 0.5 + 0.0001 and worst_residual < 0.0001, "strobe: they are drawn the real step less a half turn, never more than a quarter turn a tick (%.3f rad at most, %.6f rad off the real picture)" % [largest_step, worst_residual])
	_check(backwards, "strobe: ... which is a wheel turning backwards, every tick: the wagon-wheel effect (was a cap of 100 rad/s on the drawn spin, 95 degrees a tick and a shimmer at any speed over 122 km/h)")
	car.reset_to_spawn()
	await _step(5)


## Resets the car and accelerates it in a straight line to ~60 km/h.
# was 3 s flat out, which got to 16.5 m/s, just into 2nd -> flat out until
# GET_UP_TO_SPEED - with a clutch to slip and the engine's inertia riding along
# in 1st the same 3 s end at 14.5 m/s, still in 1st at 6100 rpm: a different
# car to hand over (engine braking through 1st on top of the rear brakes puts
# the rears at their ABS limit, honestly so). The checks that start from here
# are about ~60 km/h in 2nd, so that is what the driver delivers.
func _get_up_to_speed(car: ArcadeCar) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 600:
		if car.forward_speed >= GET_UP_TO_SPEED:
			break
		await physics_frame
	Input.action_release("accelerate")


## Drives one left corner (optionally with a tap of the handbrake going in) and
## returns peak slip / yaw, the end state and per-frame sanity stats.
func _corner(car: ArcadeCar, handbrake: bool) -> Dictionary:
	await _get_up_to_speed(car)
	var stats := {
		"peak_slip": 0.0, "peak_yaw": 0.0, "speed_drop": 0.0,
		"end_slip": 0.0, "end_slide_yaw": 0.0, "finite": true, "max_step": 0.0,
	}
	var speed_start := car.forward_speed
	Input.action_press("steer_left")
	if handbrake:
		Input.action_press("handbrake")
	for frame in 150:
		if frame == HANDBRAKE_TAP_FRAMES:
			Input.action_release("handbrake")
		if frame == 60:
			stats.speed_drop = speed_start - car.forward_speed
		var before := car.global_position
		await physics_frame
		var moved := car.global_position.distance_to(before)
		stats.max_step = maxf(stats.max_step, moved)
		if not (is_finite(car.forward_speed) and is_finite(car.lateral_speed) and is_finite(car.yaw_rate) and car.global_position.is_finite()):
			stats.finite = false
		if frame < 60:
			stats.peak_slip = maxf(stats.peak_slip, absf(car.lateral_speed))
			stats.peak_yaw = maxf(stats.peak_yaw, absf(car.yaw_rate))
	Input.action_release("steer_left")
	# Slip where the tyres are: the rear axle's sideways speed. (lateral_speed is
	# taken at the middle of the wheelbase, where a car rolling round a corner
	# with no slip at all still shows yaw rate x AXLE_DISTANCE of it, more the
	# slower and tighter it turns.)
	stats.end_slip = tan(car.rear_slip_angle) * absf(car.forward_speed)
	stats.end_slide_yaw = car.slide_yaw_rate
	return stats


## From ~60 km/h: handbrake and SLIDE_SETTLE_STEER of left steering for
## `handbrake_frames`, then every key released for SLIDE_SETTLE_WATCH_FRAMES.
## Returns when [s after the release] the nose was back in line for good
## (SLIDE_IN_LINE_ANGLE; under ArcadeCar.SPIN_MIN_SPEED the angle means
## nothing and counts as in line), when the car was down to CRAWL_SPEED and
## when at rest, each for good (-1 = never), how far it turned on the way
## [rad], its speed 1 s and 3 s after the release, the end state and per-frame
## sanity stats.
func _slide_and_let_go(car: ArcadeCar, handbrake_frames: int) -> Dictionary:
	await _get_up_to_speed(car)
	var slide := {
		"entry_speed": car.forward_speed, "release_speed": 0.0, "peak_angle": 0.0, "turned": 0.0,
		"in_line_at": -1.0, "crawl_at": -1.0, "rest_at": -1.0, "speed_at_1s": 0.0, "speed_at_3s": 0.0,
		"end_forward_speed": 0.0, "end_yaw_rate": 0.0, "finite": true, "max_step": 0.0,
	}
	Input.action_press("steer_left", SLIDE_SETTLE_STEER)
	Input.action_press("handbrake")
	await _step(handbrake_frames)
	Input.action_release("handbrake")
	Input.action_release("steer_left")
	slide.release_speed = Vector2(car.velocity.x, car.velocity.z).length()
	var in_line_frame := 0
	var crawl_frame := 0
	var rest_frame := 0
	var previous_yaw := car.global_rotation.y
	for frame in SLIDE_SETTLE_WATCH_FRAMES:
		var before := car.global_position
		await physics_frame
		slide.max_step = maxf(slide.max_step, car.global_position.distance_to(before))
		if not (is_finite(car.forward_speed) and is_finite(car.lateral_speed) and is_finite(car.yaw_rate) and car.global_position.is_finite()):
			slide.finite = false
		slide.turned += angle_difference(previous_yaw, car.global_rotation.y)
		previous_yaw = car.global_rotation.y
		var travel := Vector2(car.velocity.x, car.velocity.z)
		var nose := Vector2(-car.global_basis.z.x, -car.global_basis.z.z)
		var angle := absf(nose.angle_to(travel)) if travel.length() >= ArcadeCar.SPIN_MIN_SPEED else 0.0
		slide.peak_angle = maxf(slide.peak_angle, angle)
		if angle >= SLIDE_IN_LINE_ANGLE:
			in_line_frame = frame + 1
		if travel.length() >= CRAWL_SPEED:
			crawl_frame = frame + 1
		if travel.length() >= ArcadeCar.REST_SPEED:
			rest_frame = frame + 1
		if frame == 59:
			slide.speed_at_1s = travel.length()
		if frame == 179:
			slide.speed_at_3s = travel.length()
	var tick := 1.0 / Engine.physics_ticks_per_second
	slide.in_line_at = in_line_frame * tick if in_line_frame < SLIDE_SETTLE_WATCH_FRAMES else -1.0
	slide.crawl_at = crawl_frame * tick if crawl_frame < SLIDE_SETTLE_WATCH_FRAMES else -1.0
	slide.rest_at = rest_frame * tick if rest_frame < SLIDE_SETTLE_WATCH_FRAMES else -1.0
	slide.end_forward_speed = car.forward_speed
	slide.end_yaw_rate = car.yaw_rate
	return slide


## Accelerates to `entry_speed` on the car's own drivetrain, then holds
## CORNER_STEER of left steering for `frames` with the throttle wide open or
## closed on `layout`. Returns the heading gained [rad], the mean radius of the line [m],
## where it ended, peak slip angles / grip use, the speed gained and per-frame
## sanity stats.
func _steady_corner(car: ArcadeCar, entry_speed: float, frames: int, on_power: bool, layout: ArcadeCar.DrivenWheels) -> Dictionary:
	await _reach_speed(car, entry_speed)
	var run := {
		"label": "%s %s" % [ArcadeCar.DrivenWheels.keys()[layout], "power" if on_power else "coast"],
		"entry_speed": car.forward_speed, "yaw": 0.0, "radius": 0.0, "end_position": Vector3.ZERO, "speed_gain": 0.0,
		"peak_front_slip": 0.0, "peak_rear_slip": 0.0, "peak_front_use": 0.0, "peak_rear_use": 0.0,
		"finite": true, "max_step": 0.0,
	}
	var yaw_before := car.global_rotation.y
	var travelled := 0.0
	car.driven_wheels = layout
	Input.action_press("steer_left", CORNER_STEER)
	if on_power:
		Input.action_press("accelerate")
	for frame in frames:
		var before := car.global_position
		await physics_frame
		var moved := car.global_position.distance_to(before)
		travelled += moved
		run.max_step = maxf(run.max_step, moved)
		run.yaw += angle_difference(yaw_before, car.global_rotation.y)
		yaw_before = car.global_rotation.y
		run.peak_front_slip = maxf(run.peak_front_slip, absf(car.front_slip_angle))
		run.peak_rear_slip = maxf(run.peak_rear_slip, absf(car.rear_slip_angle))
		if on_power:
			run.peak_front_use = maxf(run.peak_front_use, car.front_traction_use)
			run.peak_rear_use = maxf(run.peak_rear_use, car.rear_traction_use)
		if not (is_finite(car.forward_speed) and is_finite(car.lateral_speed) and is_finite(car.yaw_rate) and car.global_position.is_finite()):
			run.finite = false
	Input.action_release("steer_left")
	Input.action_release("accelerate")
	car.driven_wheels = ArcadeCar.DRIVEN_WHEELS
	run.radius = travelled / maxf(absf(run.yaw), 0.001)
	run.end_position = car.global_position
	run.speed_gain = car.forward_speed - run.entry_speed
	return run


## Coasts straight at `entry_speed`, then rolls on CORNER_STEER of left
## steering (TURN_IN_ROLL_ON_RATE) and holds it, 1 s in all, and follows, tick
## by tick, the sideways acceleration the tyres make, the change
## of the world velocity, and how far the nose and the direction of travel
## have each turned.
func _turn_in_trace(car: ArcadeCar, entry_speed: float) -> Dictionary:
	await _reach_speed(car, entry_speed)
	var trace := {
		"first_tick_accel": 0.0, "peak_accel": 0.0, "ticks_to_half": 0, "largest_rise": 0.0,
		"heading_lead": 0.0, "travel_turned": 0.0, "peak_world_accel": 0.0,
	}
	var accels: Array[float] = []
	var heading_start := car.global_rotation.y
	var travel_start := atan2(-car.velocity.x, -car.velocity.z)
	var velocity_before := car.velocity
	for frame in 60:
		Input.action_press("steer_left", minf(CORNER_STEER, (frame + 1) * TURN_IN_ROLL_ON_RATE / 60.0))
		await physics_frame
		accels.append(car.lateral_accel)
		var horizontal_change := Vector2(car.velocity.x - velocity_before.x, car.velocity.z - velocity_before.z)
		trace.peak_world_accel = maxf(trace.peak_world_accel, horizontal_change.length() * 60.0)
		velocity_before = car.velocity
		var heading_turned := angle_difference(heading_start, car.global_rotation.y)
		trace.travel_turned = angle_difference(travel_start, atan2(-car.velocity.x, -car.velocity.z))
		trace.heading_lead = maxf(trace.heading_lead, heading_turned - trace.travel_turned)
	Input.action_release("steer_left")
	trace.first_tick_accel = absf(accels[0])
	for accel in accels:
		trace.peak_accel = maxf(trace.peak_accel, accel)
	for i in accels.size():
		if i > 0:
			trace.largest_rise = maxf(trace.largest_rise, accels[i] - accels[i - 1])
		if trace.ticks_to_half == 0 and accels[i] >= trace.peak_accel * 0.5:
			trace.ticks_to_half = i + 1
	return trace


## Full throttle from rest for 2 s on `layout`; returns the speed reached and
## the load on the driven axle at the end.
func _launch(car: ArcadeCar, layout: ArcadeCar.DrivenWheels) -> Dictionary:
	car.reset_to_spawn()
	await _step(10)
	car.driven_wheels = layout
	Input.action_press("accelerate")
	await _step(120)
	Input.action_release("accelerate")
	var launch := {
		"speed": car.forward_speed,
		"driven_load": car.front_axle_load if layout == ArcadeCar.DrivenWheels.FWD else car.rear_axle_load,
	}
	car.driven_wheels = ArcadeCar.DRIVEN_WHEELS
	return launch


## Resets the car and accelerates it in a straight line to `speed`, then lifts.
func _reach_speed(car: ArcadeCar, speed: float) -> void:
	car.reset_to_spawn()
	await _step(10)
	Input.action_press("accelerate")
	for frame in 600:
		if car.forward_speed >= speed:
			break
		await physics_frame
	Input.action_release("accelerate")


## Turns in to the left (CORNER_STEER) for 0.75 s from ~60 km/h, off the
## throttle, optionally hard on the brakes; returns how far the car turned [rad].
func _turn_in(car: ArcadeCar, braking: bool) -> float:
	await _get_up_to_speed(car)
	var yaw_before := car.global_rotation.y
	Input.action_press("steer_left", CORNER_STEER)
	if braking:
		Input.action_press("brake")
	await _step(45)
	Input.action_release("steer_left")
	Input.action_release("brake")
	return angle_difference(yaw_before, car.global_rotation.y)


## Full throttle for 0.5 s; returns the average acceleration [m/s^2].
func _measure_pull(car: ArcadeCar, stats: Dictionary) -> float:
	var speed_start := car.forward_speed
	Input.action_press("accelerate")
	await _drive(car, 30, stats)
	Input.action_release("accelerate")
	return (car.forward_speed - speed_start) / 0.5


## Largest suspension travel of the four wheels right now [m], either way.
func _largest_travel(car: ArcadeCar) -> float:
	var largest := 0.0
	for travel in car.wheel_travel:
		largest = maxf(largest, absf(travel))
	return largest


## Presses and releases an action over two physics frames.
func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame


func _new_stats() -> Dictionary:
	return {
		"finite": true, "max_step": 0.0, "peak_traction_use": 0.0,
		"min_rpm": INF, "max_rpm": 0.0, "min_load": 1.0, "max_load": 0.0,
	}


## Steps `frames` physics frames, folding per-frame sanity stats into `stats`.
func _drive(car: ArcadeCar, frames: int, stats: Dictionary) -> void:
	for frame in frames:
		var before := car.global_position
		await physics_frame
		stats.max_step = maxf(stats.max_step, car.global_position.distance_to(before))
		var values := [car.forward_speed, car.lateral_speed, car.yaw_rate, car.engine_rpm, car.front_load_fraction, car.rear_load_fraction]
		for value: float in values:
			if not is_finite(value):
				stats.finite = false
		if not car.global_position.is_finite():
			stats.finite = false
		stats.peak_traction_use = maxf(stats.peak_traction_use, car.rear_traction_use)
		stats.min_rpm = minf(stats.min_rpm, car.engine_rpm)
		stats.max_rpm = maxf(stats.max_rpm, car.engine_rpm)
		stats.min_load = minf(stats.min_load, minf(car.front_load_fraction, car.rear_load_fraction))
		stats.max_load = maxf(stats.max_load, maxf(car.front_load_fraction, car.rear_load_fraction))


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	if _failures == 0:
		print("SMOKE TEST PASSED")
	else:
		printerr("SMOKE TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)
