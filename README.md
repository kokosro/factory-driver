# factory-driver

## How to run

Requires **Godot 4.7** (developed against 4.7.2 stable). No other dependencies; all
geometry is generated in-engine.

```sh
./run.sh
```

`run.sh` uses `godot` from your `PATH` (falling back to `/opt/homebrew/bin/godot`) and
imports the project on first launch. Alternatively, open the folder in the Godot 4.7
editor (*Import* → select `project.godot`) and press **F5**.

### Controls

| Action                                  | Keys            |
| --------------------------------------- | --------------- |
| Accelerate                              | `Up` or `W`     |
| Brake; press again at a stop to reverse | `Down` or `S`   |
| Steer left / right                      | `Left` / `Right` or `A` / `D` |
| Handbrake (hold mid-corner to slide)    | `Space`         |
| Shift down / up (switches to manual)    | `Q` / `E`       |
| Toggle automatic / manual gearbox       | `M`             |
| Reset the car to the start line         | `R`             |
| Cycle camera: chase, cockpit, front, overhead, wheel | `C` |
| Look back (hold)                        | `B`             |
| X-ray view on / off                     | `X`             |
| Start handling test 1 - 5 (mission mode) | `1` - `5`      |
| Abort the running test / close its result | `Esc` (`R` also aborts) |

The brake always brakes: it slows the car to a stop whichever way it rolls and holds it there, and never turns into reverse by itself. Reverse engages only on a fresh press of `Down` / `S` while the car is stopped; in reverse, `Down` / `S` is the throttle and `Up` / `W` the brake, and a fresh press of `Up` / `W` while stopped (or once the car rolls nose-first, as out of a J-turn) engages forward again. Holding `Up` / `W` through the stop also engages forward after a moment and drives away in one motion (the J-turn exit); reverse still needs a fresh press. The handbrake loosens the rear tyres, so steering while holding it swings the tail out. The HUD shows speed in km/h (prefixed with `R` while reverse is engaged). Above it, the tach line shows engine RPM and the gear (e.g. `3000 rpm | G4`, with `M` in manual) and turns red near the redline. The gearbox starts in automatic and goes back to automatic when you reset the car.

### Driving feel

The car uses a custom arcade controller in plain GDScript (`scripts/car.gd`), not Godot's
vehicle physics. Every handling parameter lives in the commented `DRIVING FEEL TUNING`
block at the top of that file.

#### Under the hood

The car goes by its tyres. It is a rigid body on two axles carrying a velocity and a yaw
rate, and nothing moves it but forces at the contact patches. Every physics tick each
axle looks at how its patch really moves over the road: the slip angle (where the wheels
point against where that end of the car is going) and the slip ratio (wheel speed against
road speed, wound up by engine and brake torque) make one slip vector, which goes through
a tyre curve (peak of `TYRE_MU` x axle load at `FRONT_PEAK_SLIP_ANGLE` /
`REAR_PEAK_SLIP_ANGLE` / `PEAK_SLIP_RATIO`, easing to `TYRE_SLIDE_GRIP` of that once the
tyre slides). The force points against the slip, so a tyre has one grip to share between
driving, braking and cornering (friction circle, with `MIN_COMBINED_GRIP` as the arcade
floor). The forces act along and across each wheel's heading; their sum accelerates the
1300 kg, their moments about the centre of mass wind the yaw inertia
(`YAW_GYRATION_RADIUS`) up and down. Heading and direction of travel are separate things,
tied together only by the tyres: the steering sets the front wheel angle and nothing
else. It is raw: the wheel angle is exactly the steering input x `MAX_STEER_LOCK` (~27
degrees) at any speed, in any slide, and nothing but you turns the wheels. A held key at
speed is far more lock than the front tyres can use, so they scrub and the car pushes
wide: that is the tyres' honest answer, and short presses are how you ask for less.

- **Driven wheels** - `DRIVEN_WHEELS` is `RWD`, `FWD` or `AWD` (`TORQUE_DISTRIBUTION`
  front / rear). The Boxster is `RWD`. Nothing about the layouts is scripted: rear drive
  spends rear grip and pushes, so full throttle in a low gear steps the tail out; front
  drive pulls and steers with the same tyres, so power pushes the nose wide and a launch
  is traction-limited as the load moves off the driven axle; all-wheel drive sits in
  between and puts the most power down. On/off keys cannot feather a throttle, so
  wheelspin is held at `DRIVE_SLIP_RATIO`.
- **Brake bias** - the foot brake is split `BRAKE_BIAS_FRONT` (0.6) front / rear, each axle
  capped by its own grip with ABS holding the wheels at `ABS_SLIP_RATIO`. A full stop has
  the fronts at their limit and the rears under theirs: about 0.9 g, ~36 m from 90 km/h,
  the nose pushing wide if you brake and steer at once. The handbrake locks the rear
  wheels outright.
- **Weight and aero** - axle loads shift forward under braking and rearward under power
  (`CG_HEIGHT`), and grow with speed from downforce (`DOWNFORCE_COEFF`, split by
  `AERO_BALANCE_FRONT`), so fast corners hold more than slow ones and the tail gets more
  planted the faster you go. Drag is `DRAG_COEFF` x `FRONTAL_AREA`; top speed ~234 km/h.
- **Low-speed blend** - a force model degenerates at a standstill, so below
  `LOW_SPEED_BLEND_END` (4 m/s) the forces are blended with plain rolling geometry:
  parking is precise, the car stands still on the brake, and there is no visible switch.

Slides and spins: the handbrake locks the rear wheels, which then only drag and barely
hold the tail sideways. A stability assist (`SLIDE_YAW_DAMPING`, bounded by
`MAX_ASSIST_YAW_ACCEL`) leans on the nose swinging away from the direction of travel; it
compares the yaw rate with the rate the tyre forces are really bending the path, knows
nothing about where the steering points and never turns the car for you. The wheels stay
where you put them: a key held into a slide keeps feeding it, and you catch the slide
with opposite lock, which is there all the way to full lock at once, handbrake or not
(`SLIDE_CATCH_ANGLE` survives only inside the assist, as where it starts to leave a slide
that is coming back alone). The assist fades once the tail is more
than ~25 degrees out (`SPIN_COMMIT_ANGLE`) and is off while the handbrake is held, so a
committed flick goes all the way round. A tap of handbrake with steering gives a drift
that comes back on its own; holding both from ~90 km/h until the car is nearly round,
then centring the steering and braking once it has lined up, gives a 180; from ~125 km/h,
steering the other way while the car travels backwards and releasing the handbrake past
half way completes a 360. In reverse there is no assist: a flick of the steering at
~40 km/h swings the nose round (J-turn).

The test pad is built to make motion readable: noise-textured asphalt with repair
patches, ground ticks every 10 m, a chequered START / FINISH zone, painted skid pad
rings with reference posts, tall perimeter pylons and cones that topple when hit (they
never slow the car).

#### The living road

The pad is not flat any more. One seeded height field (`scripts/road_profile.gd`, a
`RoadProfile` resource wired to both the pad and the car in `scenes/main.tscn`) says how
high the tarmac is at every point, in three layers:

- **Elevation** - a gentle swell: 1.0 m on an 800 m wave plus 0.18 m on a 200 m wave,
  never steeper than 1.5 % (measured 1.35 % down the lane). This is the layer you see:
  the ground mesh is shaped to it, every marking, cone, board, pylon and shed stands on
  it, and the car's body rides it. It is exactly level round the start line, the stop
  box, the slalom and the skid pad (the certifications run on level ground) and far from
  the course, and across the straight's lane it depends on the distance down the
  straight only, so the lane never leans sideways. Down the straight the first crest
  (+1.1 m) comes at about 520 m, the hollow (-1.1 m) at about 900 m.
- **Micro-bumps** - value noise up to 12 mm (3.8 mm RMS), 0.6 to 4 m long, mean-neutral.
  Felt, not drawn.
- **A test dip** - one 6 cm deep, 10 m long smooth dip right of the straight past the
  slalom (x = 25, z = -450, a yellow bar painted at either lip): a test fixture, so the
  crest test has a known crest to drive over. Felt, not drawn.

The car feels it through a suspension load layer on top of the tyre model, which itself is
untouched: every wheel has a spring and damper (`RIDE_FREQUENCY` 1.4 Hz,
`RIDE_DAMPING_RATIO` 0.4, behind a tyre that swallows the shortest ripples,
`TYRE_ENVELOPE_RATE`) following the road under it. A bump pushes load into its wheel; a
crest dropping away faster than the car can follow takes load off, and grip with it -
nobody scripts the crest, it falls out of the spring. Each axle's load is the sum of its
two wheels (`wheel_loads` on the car, front left / front right / rear left / rear right),
so grip breathes a few per cent with the road at speed; on a flat road the layer adds
exactly nothing. The wheels are drawn following the road (up to 4 cm of travel) while the
body rides the swell.

### Tests

```sh
tests/run_tests.sh
```

Runs a headless import, then `tests/smoke_test.gd`, which loads the main scene and
drives the car with simulated input (including the fences round the force model: power
against coasting through the same corner, cornering force building tick by tick, the
RWD / FWD / AWD signatures, brake bias, downforce and the low-speed blend; and round
the road: the profile is pure, mean-neutral, gentle and level where the certifications
run, every wheel's load swings over the bumps at speed while the axle means hold, the
crest test drives over the test dip and sees each wheel unload going in and load up at
the bottom, and cones, board posts and pylons stand on the ground), then the
handling tests below, then
`tests/camera_test.gd` (cycles the camera through its five views and drives under each, holds the look-back
and toggles the X-ray)
and `tests/mission_test.gd` (plays every mission through the mission manager with the
scripted driver pressing the keys, plus one run with its steering held off that has to
come out FAILED, and an abort).

### Handling tests

The third step of `tests/run_tests.sh` runs `tests/handling_test.gd`: a scripted driver
takes the real car through five tests on the pad, one after the other from a fresh
start, and prints `PASS name` / `FAIL name` plus a metrics line for each. If a test
cannot be passed, either the driver or the car is not set up properly.

| Test          | Course                                                       | Passes when                                                              |
| ------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `SLALOM_TEST` | the 14-cone slalom line right of the straight                | at most 1 gate missed (wrong side, too wide, cone knocked over), in 45 s |
| `SPIN_180`    | the straight, handbrake turn from ~90 km/h                   | ends within 35 degrees of 180, net forward displacement positive         |
| `SPIN_360`    | the straight, full spin from ~125 km/h                       | ends within 35 degrees of 360, net forward displacement positive         |
| `STOP_BOX`    | the hatched box on the straight, 150 m from the start        | stopped with the whole car inside the box, braked from 72 km/h or more   |
| `REVERSE_180` | the straight, J-turn out of ~40 km/h in reverse              | ends within 35 degrees of 180, driving away forwards at 18 km/h or more, reversed at 36 km/h or more, net travel along the reversing line positive |

The skid circle (painted rings, cone circles) is on the pad and can be queried the same
way, but has no test yet.

The tests are data plus checks in `scripts/handling_tests.gd`, separate from the
headless harness; the pad (`scripts/test_pad.gd`) reports where its cones, slalom gates,
skid circle and stop box are. The mission mode grows from these: a mission runs the same
checks with the scripted driver switched off and a human at the wheel. To tune a test or
the car, run one test with a trace:

```sh
godot --headless --fixed-fps 60 --path . --script res://tests/handling_test.gd -- --only=SPIN_360 --trace
```

### Mission mode

The same five tests, playable. Press `1` (slalom), `2` (180 spin), `3` (360 spin),
`4` (stop box) or `5` (reverse 180): the car is put on that test's start point, the cones stand back up and
the run starts at once. While it runs, the line under the controls text shows the test,
live progress and the clock against the test's target time, e.g. `GATE 5/14  12.3 / 30.0 s`,
`ROTATION 213° / 360°  12.3 / 16.5 s`, `BRAKE! 62 m to box  9.8 / 12.5 s` or
`REVERSE 28/36 km/h  3.1 / 7.0 s`, with the objective under it. The target is a time to
beat, 10-15 % over the scripted driver's run (`target_time_s` in the test's data); it
judges nothing. While a run is on, a glowing golden orb floats beside its start point and,
for the slalom and the stop box, a golden chevron stands beside the goal (the exit past the
last cone, the box); both are for looks, stand off the driving line and can be driven
through. A run ends by itself: the
slalom after the last cone, the spins and the stop box once the car has come to a stop,
the reverse 180 once the car has turned and drives away forwards (or when the time limit
runs out). A banner then says `PASSED` or `FAILED` with the
measured numbers and, on a fail, the checks that were missed. It stays for 5 seconds or
until `Esc`; the car stays drivable under it. Press the same number to retry, another
number for a different test. `Esc` or `R` aborts a run (`R` also puts the car back on
the start line); other number keys are ignored until then.

The verdict is always the test's own (`HandlingTests.result()`), the one the headless
harness prints. `scripts/mission_manager.gd` only picks the test, runs it
(idle, running, result shown) and hands the HUD its strings.

### Camera

`C` cycles the one camera (`scripts/chase_camera.gd`) through chase (default), cockpit
(driver's eye, with a dashboard and steering wheel silhouette), front (on the bonnet),
overhead (straight down, north always up so the pad holds still; rises with speed) and
wheel (low by the front-left tyre, looking back at it: watch it steer, spin, lock under
braking, work up and down over the bumps and the tarmac run under its contact patch). It works at any time, including
during a test. Every offset, height and field of view is a commented constant in the
`Modes` block of that file.

Holding `B` looks back: the camera cuts to a spot ahead of the nose, facing back over the
car at the road behind, for as long as the key is held; letting go returns to the view it
interrupted. The rear view is held-only, `C` never stops on it.

`X` toggles the X-ray (`scripts/xray.gd`, the `Xray` node in `scenes/car.tscn`): the body
panels turn translucent and a set of primitives shows what the physics models underneath -
ladder chassis, the engine ahead of the rear axle, the gearbox on the rear axle line
driving the rear wheels, the axles and a brake disc at every wheel. It works in any view
and is purely visual: the body materials are restored exactly when it goes off, and the
camera test checks a launch comes out the same with and without it.
