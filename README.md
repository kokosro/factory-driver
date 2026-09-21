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
| Look left / right (hold)                | `,` / `.`       |
| X-ray view on / off                     | `X`             |
| Start handling test 1 - 5 (mission mode) | `1` - `5`      |
| Abort the running test / close its result | `Esc` (`R` also aborts) |

Look left / right are on `,` and `.` (the `<` / `>` pair, under the right hand's reach from the arrows and next to `B`'s row): `Q` / `E` are the gearbox, `B` is look back. Hold to glance to that side, let go and the view comes back: the chase camera swings ~65 degrees round the car, in the cockpit and the bonnet view the head turns ~60 degrees; the overhead and wheel views have no side to look to. It is a glance, not a view of its own (`C` still cycles the same five), both keys at once look straight ahead, and look back wins over either.

The brake always brakes: it slows the car to a stop whichever way it rolls and holds it there, and never turns into reverse by itself. Reverse engages only on a fresh press of `Down` / `S` while the car is stopped; in reverse, `Down` / `S` is the throttle and `Up` / `W` the brake, and a fresh press of `Up` / `W` while stopped (or once the car rolls nose-first, as out of a J-turn) engages forward again. Holding `Up` / `W` through the stop also engages forward after a moment and drives away in one motion (the J-turn exit); reverse still needs a fresh press. The handbrake loosens the rear tyres, so steering while holding it swings the tail out. The HUD shows speed in km/h (prefixed with `R` while reverse is engaged), with two thin pedal bars beside it (green throttle, red brake: how far the driver's feet really have the pedals, see The driver below) and a thin fuel bar under them. Above it, the tach line shows engine RPM and the gear (e.g. `3000 rpm | G4`, with `M` in manual) and turns red near the redline. The gearbox starts in automatic and goes back to automatic when you reset the car.

### Driving feel

The car uses a custom arcade controller in plain GDScript (`scripts/car.gd`), not Godot's
vehicle physics. Every handling parameter lives in the commented `DRIVING FEEL TUNING`
block at the top of that file.

#### Under the hood

The car goes by its tyres. It is a rigid body on two axles carrying a velocity and a yaw
rate, and nothing moves it but forces at the contact patches. Every physics tick each
axle looks at how its patch really moves over the road: the slip angle (where the wheels
point against where that end of the car is going) and the slip ratio (the axle's wheel
speed, a state of its own between driveline, brakes and road, against road speed) make
one slip vector, which goes through
a tyre curve (peak of `TYRE_MU` x axle load at `FRONT_PEAK_SLIP_ANGLE` /
`REAR_PEAK_SLIP_ANGLE` / `PEAK_SLIP_RATIO`, easing to `TYRE_SLIDE_GRIP` of that once the
tyre slides). The force points against the slip, so a tyre has one grip to share between
driving, braking and cornering (friction circle, with `MIN_COMBINED_GRIP` as the arcade
floor). The forces act along and across each wheel's heading; their sum accelerates the
1300 kg, their moments about the centre of mass wind the yaw inertia
(`YAW_GYRATION_RADIUS`) up and down. Heading and direction of travel are separate things,
tied together only by the tyres: the steering sets the front wheel angle and nothing
else. There is a real steering wheel in between: 900 degrees lock to lock
(`steering_wheel_deg`, +/- 450), turned by the driver's hands at `STEERING_HAND_SPEED`
(1300 degrees a second: centre to lock in 0.35 s, lock to lock in 0.7 s) towards what
the keys ask for, and back to centre when you let go. The front wheels are that angle
through the rack (`STEERING_RATIO` 16.4 : 1, which is what 450 degrees for
`MAX_STEER_LOCK`, ~27 degrees, comes to), at any speed, in any slide; nothing but you
turns the wheels, and the cockpit's wheel shows every degree (the yellow mark is 12
o'clock). A held key at speed winds on far more lock than the front tyres can use, so
they scrub and the car pushes wide: that is the tyres' honest answer, and short presses
are how you ask for less. Countersteer is wound on the same way, in proportion: catch a
slide early, by as much as it needs, because opposite lock is two thirds of a second
away.

- **Drivetrain** - engine, clutch and wheels each turn at their own speed, tied together
  by torque, not by road speed. The engine speed is integrated from its torque against
  `ENGINE_INERTIA`: in neutral (`Q` from 1st) the throttle free-revs it to the limiter,
  where the fuel cut makes the tach bounce. Pulling away, the revs flare to `LAUNCH_RPM`
  on a slipping clutch until the car has caught up; select 1st on a screaming engine and
  the rear wheels spin for a couple of seconds. Locked, the engine's inertia rides on the
  driven axle through the gear ratio squared, so 1st pulls less than torque x ratio says
  and lifting off holds the car back harder the lower the gear. A gear change opens the
  clutch for `SHIFT_TIME`: the revs drift on their own, then the clutch catches them (an
  upshift at full throttle chirps the tyres; on downshifts the driver blips). 0 - 100
  km/h takes ~7.1 s, as the real 2.5 does.
- **Driven wheels** - `DRIVEN_WHEELS` is `RWD`, `FWD` or `AWD` (`TORQUE_DISTRIBUTION`
  front / rear). The Boxster is `RWD`. Nothing about the layouts is scripted: rear drive
  spends rear grip and pushes, so full throttle in a low gear steps the tail out; front
  drive pulls and steers with the same tyres, so power pushes the nose wide and a launch
  is traction-limited as the load moves off the driven axle; all-wheel drive sits in
  between and puts the most power down. On/off keys cannot feather a clutch, so
  while the clutch slips (a launch, a dropped clutch) wheelspin is held at
  `DRIVE_SLIP_RATIO`; with the clutch locked the wheels are the engine's.
- **Brake bias** - the foot brake is split `BRAKE_BIAS_FRONT` (0.6) front / rear, each axle
  capped by its own grip with ABS holding the wheels at `ABS_SLIP_RATIO`. A full stop has
  the fronts at their limit and the rears under theirs: about 0.9 g, ~36 m from 90 km/h,
  the nose pushing wide if you brake and steer at once. The handbrake locks the rear
  wheels outright.
- **Suspension and weight** - the body is a rigid mass on four real springs, with heave
  (the car's own height, gravity pulling it down), pitch and roll as states. Each corner
  has a spring (`FRONT_` / `REAR_RIDE_FREQUENCY` 1.5 / 1.7 Hz on its corner mass:
  21.9 / 46.0 kN/m), a damper (`RIDE_DAMPING_RATIO` 0.4: 1860 / 3440 N s/m), a share of
  its axle's anti-roll bar and progressive bump stops at +/- `SUSPENSION_TRAVEL` (7 cm).
  What a spring pushes up with is what its tyre presses on the road with: that is the
  wheel load, and the grip. Nothing scripts weight transfer any more: the tyres pull at
  the road, `CG_HEIGHT` under the centre of mass, so braking dives the nose (~1.5
  degrees and ~5 cm of front travel in a full stop) and loads the front tyres, power
  squats the tail, a corner rolls the body onto its outside wheels (2.5 degrees per g).
  The smoke test holds the springs to rigid-body statics (force x CG height / wheelbase
  or track) as a cross-check. The body floats `GROUND_CLEARANCE` (12 cm) over the floor;
  the floor only meets it bottomed out. The cockpit and bonnet cameras ride on the body.
- **Aero** - downforce (`DOWNFORCE_COEFF`, split by `AERO_BALANCE_FRONT`) presses on the
  body and reaches the tyres through the springs, so fast corners hold more than slow
  ones and the tail gets more planted the faster you go. Drag is `DRAG_COEFF` x
  `FRONTAL_AREA`; top speed ~234 km/h.
- **Tyre curve** - rises smoothly into its peak and eases off it over a wide top
  (`TYRE_SLIDE_ONSET` 3 peak slip angles) down to `TYRE_SLIDE_GRIP` (0.85) at the front;
  rear tyres that still roll keep `REAR_TYRE_SLIDE_GRIP` (0.97): there is a limit to go
  over and grip to get back as the slide comes in again, but the rear always holds on
  better than the front.
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
committed flick goes all the way round. A slide nobody is driving settles by itself:
rear tyres that still roll keep their hold sliding sideways (`REAR_TYRE_SLIDE_GRIP`)
where the fronts and a locked wheel let go to `TYRE_SLIDE_GRIP`, so with every key
released the tail is pulled back into line, the sliding tyres scrub the speed off and the
car rolls on straight or comes to rest, held back by the engine whichever way it rolls.
A tap of handbrake with steering gives a drift
that comes back on its own; holding both from ~90 km/h until the car is nearly round,
then centring the steering and braking once it has lined up, gives a 180; from ~125 km/h,
steering the other way while the car travels backwards and releasing the handbrake past
half way completes a 360. In reverse there is no assist: a flick of the steering at
~40 km/h swings the nose round (J-turn).

The test pad is built to make motion readable: noise-textured asphalt with repair
patches, ground ticks every 10 m, a chequered START / FINISH zone, painted skid pad
rings with reference posts, tall perimeter pylons and cones that topple when hit (they
never slow the car).

#### The driver

The car does not read the keys, it has a driver. Whoever is asked - by the keys, or by
code through `car.set_driver_input(throttle, brake, steer)` (0..1, 0..1, -1..+1; an
optional fourth argument pulls the handbrake; `clear_driver_input()` hands the car back
to the keys) - has feet and hands that take time: a held key is a foot going down to
the floor, a tap is a dab at the pedal that never gets there, a lift comes back to
nothing. What the drivetrain is given is where the pedals are (`throttle_pedal`,
`brake_pedal`), and the two thin bars at the right edge of the HUD show exactly that:
green for the throttle, red for the brake, the lift of a gear change included. One
foot works both pedals: asking for the brake alone takes the foot off the throttle at
once. The handbrake is a lever and still bites instantly. Which way the car goes is
decided by what is asked for, not by where the feet are, so reverse is what it was: a
fresh brake at a standstill, never a held one.

How fast the feet and hands are is a driver profile, plain data in `DRIVER_PROFILES`
(`throttle_attack`, `throttle_release`, `brake_attack`, `brake_release` in pedal travel
per second, `steering_hand_speed` in degrees per second); `car.set_driver_profile(...)`
puts another driver in the seat, missing keys are the test driver's. The default
`test_driver` is the one the handling tests are certified with, and as slow as they
allow: throttle down in 0.1 s, brake in 0.05 s, off the throttle in two ticks (the
J-turn's lift has to open the clutch, a lazier one locks it and the scripted driver
misses the goal), all measured in the comments by the constants. `chauffeur` is the same
car with feet several times slower. An AI driver later is one more caller of
`set_driver_input` with a profile of its own.

#### Fuel, mass, exhaust and creep

The engine burns what its work costs: the combustion torque (the torque curve plus the
engine's losses, times the throttle it really has, the idle controller's share included)
times the engine speed is a power, and the fuel that takes is that power over an
indicated efficiency of 0.30 and petrol's 44 MJ/kg: ~0.6 L/h idling, ~67 L/h flat out
at the limiter, nothing on the overrun with the throttle shut. The tank holds the 986's
64 L (`fuel_l`, `fuel_fraction()`), every reset fills it, and the thin bar lying under
the pedal bars shows it: amber under 15 %, red under 8 %. With the tank dry nothing
burns: the engine runs down and stays down until a reset.

The car has one mass, `car.total_mass()`: `BASE_MASS` (the car with a dry tank, 1252 kg)
plus the fuel in the tank (`fuel_mass`, 48 kg full) plus `payload_mass`, a plain variable
for whatever the car carries. On a full tank with nothing loaded that is the 1300 kg
(`KERB_MASS`) everything was tuned and certified with; it gets lighter as it burns.
Every force, inertia and weight reads that one figure: drive, brakes, grip, weight
transfer, yaw inertia. The springs and dampers alone stay those chosen for the 1300 kg
car, so a loaded car rides a little softer, but level: the spring seats carry what the
car weighs now. A handling test may carry `"payload_kg"` in its data; it is loaded at
the start and gone with the next reset (none of the five certified tests carries any).

The exhaust is data, no particles yet: `exhaust_events` counts the combustion events
(the flat six fires three times a turn, none while the fuel is cut) and `exhaust_flow`
(0..1) is how hard it blows, by throttle and revs, a tenth of a second behind the engine.

Creep: in automatic, held on the brake at a standstill in 1st, the car pulls away gently
when the brake is let go, 0.4 s after the foot is off: the clutch comes in by a sliver
(the torque converter's stall push, as a plate clutch gives it), the idling engine
carries it, and the push eases out with speed, so the crawl settles at ~1.5 km/h, under
the standstill speed (the brake pressed anew still selects reverse). The pedals are
never touched, the pedal bars stay empty. Throttle, brake, handbrake, reverse or manual
mode end it, and it takes the brake let go at a standstill to start it again: a car
that came to rest by itself (a reset, a coast-down, a mission's start point) stands
until its driver does something. No creep in reverse or in manual mode.

#### The living road

The pad is not flat any more. One seeded height field (`scripts/road_profile.gd`, a
`RoadProfile` resource wired to both the pad and the car in `scenes/main.tscn`) says how
high the tarmac is at every point, in three layers:

- **Elevation** - a gentle swell: 1.0 m on an 800 m wave plus 0.18 m on a 200 m wave,
  never steeper than 1.5 % (measured 1.35 % down the lane). This is the layer you see:
  the ground mesh is shaped to it, every marking, cone, board, pylon and shed stands on
  it, and the car rides over it on its springs. It is exactly level round the start line, the stop
  box, the slalom and the skid pad (the certifications run on level ground) and far from
  the course, and across the straight's lane it depends on the distance down the
  straight only, so the lane never leans sideways. Down the straight the first crest
  (+1.1 m) comes at about 520 m, the hollow (-1.1 m) at about 900 m.
- **Micro-bumps** - value noise up to 12 mm (3.8 mm RMS), 0.6 to 4 m long, mean-neutral.
  Felt, not drawn in the ground (the wheels are drawn following them).
- **A test dip** - one 6 cm deep, 10 m long smooth dip right of the straight past the
  slalom (x = 25, z = -450, a yellow bar painted at either lip): a test fixture, so the
  crest test has a known crest to drive over. Felt, not drawn.

The car rides it on its suspension (see *Suspension and weight* above); the tyre model
itself knows nothing of the road. Every wheel follows the road under it in full, behind a
tyre that swallows the shortest ripples (`TYRE_ENVELOPE_RATE`). A bump pushes load into
its wheel; a crest dropping away faster than the body can fall after it takes load off,
and grip with it, and past the droop stop the wheel is in the air - nobody scripts the
crest, it falls out of the springs. Each axle's load is the sum of its two wheels
(`wheel_loads` on the car, front left / front right / rear left / rear right; the spring
travel is `wheel_travel`), so grip breathes with the road at speed (~8 % RMS per wheel
flat out down the lane); standing still every wheel carries exactly its static share. The
wheels are drawn on the road, up to `MAX_WHEEL_VISUAL_TRAVEL` (9 cm) from their place
under the body, while the body heaves, pitches and rolls above them.

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
the bottom, and cones, board posts and pylons stand on the ground; round the
suspension: a drop test for the ride frequency, dive, squat and roll held against
rigid-body statics, travel inside its limits, the wheels drawn on the road; round the
steering: the 900-degree wheel wound on at hand speed, the rack, 0.35 s centre to lock
and 0.7 s lock to lock; and the shape of the tyre curve; and the driver: a tap of the
key is a partial press, a held one reaches exactly 1.0 and a lift decays to 0, the
chauffeur's foot is measurably slower than the test driver's, `set_driver_input`
launches the car with no key down exactly as the key does, holds half a pedal, clamps
what is out of range and keeps the reverse rule, and the HUD's pedal bars follow the
pedals and take 0..1; and fuel, mass, exhaust and creep: idling burns ~0.6 L/h and flat
out some 70 times that, nothing burns on the overrun, a dry tank stops the engine and a
reset fills it, the fuel bar reads the tank and changes colour, `total_mass()` has the
fuel and the payload in it, 300 kg on board ride level and are slower over the same 5 s,
a test's `payload_kg` is loaded at its start, the exhaust fires three times a turn and
its flow follows the throttle, and the car creeps when the brake is let go at a
standstill, stands on a held brake, untouched and in manual), then the
handling tests below, then
`tests/camera_test.gd` (cycles the camera through its five views and drives under each, holds the look-back,
toggles the X-ray, holds look left / right from the chase view and the cockpit, turns the
cockpit's steering wheel with the car's, and carries the chase camera straight over its
aim point, which used to trip a colinear look-at warning)
and `tests/mission_test.gd` (plays every mission through the mission manager with the
scripted driver pressing the keys and checks the medal on every banner, plus one run with
its steering held off and one 180 left parked where it stopped, which both have to come
out FAILED, and an abort).

The smoke test's last phase is the telemetry recorder (below): it switches the recorder
on in process, points it at `/tmp/fd-3E-telemetry/smoke.jsonl`, starts a real mission
through the mission manager, drives it for 2.5 s, aborts, and reads the file back line
by line - every line one JSON object, the first the `session_start`, every sample
carrying the car's state and every mission sample the run with it, the mission samples
exactly 5 physics ticks apart and the free ones 30, the last line `{"event":"aborted"}`.
Nothing that comes off the wall clock is asserted, and nothing is written under
`user://` (a headless run records nothing by itself, and the phase's own recording goes
to that fixed tmp path), so the suite reads the same on every run.

### Handling tests

The third step of `tests/run_tests.sh` runs `tests/handling_test.gd`: a scripted driver
takes the real car through five tests on the pad, one after the other from a fresh
start, and prints `PASS name` / `FAIL name` plus a metrics line for each. If a test
cannot be passed, either the driver or the car is not set up properly.

| Test          | Course                                                       | Passes when                                                              |
| ------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `SLALOM_TEST` | the 14-cone slalom line right of the straight                | at most 1 gate missed (wrong side, too wide, cone knocked over), in 45 s |
| `SPIN_180`    | the straight, handbrake turn from ~90 km/h, then back to the start | the spin settles within 35 degrees of 180, spun either way, net forward displacement positive, and the car gets back within 8 m of the start point |
| `SPIN_360`    | the straight, full spin from ~125 km/h, then on to the 400 m board | the spin settles within 35 degrees of 360, spun either way, net forward displacement positive, and the car drives on over the goal line |
| `STOP_BOX`    | the hatched box on the straight, 150 m from the start        | stopped with the whole car inside the box, braked from 72 km/h or more   |
| `REVERSE_180` | the straight, J-turn out of ~40 km/h in reverse, then on to the 100 m board | the flick settles within 35 degrees of 180, reversed at 36 km/h or more, net travel along the reversing line positive, and the car drives on over the goal line, forwards at 18 km/h or more |

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
live progress and the clock against the test's target time, e.g. `GATE 5/14  12.3 / 31.0 s`,
`ROTATION 213° / 360°  12.3 / 19.5 s`, `BRAKE! 62 m to box  6.8 / 9.3 s` or
`REVERSE 28/36 km/h  not started / 8.3 s`, with the objective under it. The target is a time to
beat, 5-10 % over the scripted driver's run (`target_time_s` in the test's data, the gold
time); it judges nothing.
<!-- was: the clock counted from the moment the test began (examples `12.3 / 30.0 s`,
`12.3 / 23.5 s`, `9.8 / 12.5 s`, `3.1 / 11.0 s`; target 5-15 % over the scripted run)
-> the run clock below, and the targets re-measured on it. -->

**The clock times the run, not the nerves.** It reads `not started` until the car crosses
the test's start line, starts on that crossing and stops at the finish: over the goal
line (360, reverse 180), back within 8 m of the start point (180), at a standstill (stop
box), level with the last cone (slalom). Lining up, waiting, even a run-up from further
back are free; reaction time is never scored. The start line is 4 m down the pad from
where the car is put: the painted START / FINISH line under the gantry (z = -4) for the
spins, the stop box and the reverse 180 - which crosses it tail-first - and a white bar
of its own across the slalom's lane (z = -24), since the slalom starts further down the
pad. There is one timed window per run: going back over the line and crossing it again
does not restart the clock, and a run that finishes without ever crossing its line fails.
The scripted driver is timed the same way, so its certified times (slalom 28.75 s,
180 15.83 s, 360 18.23 s, stop box 8.67 s, reverse 180 7.70 s) are what the medals are
set against. The time limit is the one thing still counted from the moment the test
began, so a run nobody drives still ends by itself.
<!-- was: one clock from the moment the test began to the end of the run, the 1 - 2 s
the run is watched for after the finish included; a late start was a slow time. -->

The spins are a manoeuvre and a destination: do the 180 and return to the
start, do the 360 and drive on to the 400 m board, do the J-turn and drive on to the 100 m
board; the rotation is judged the moment the spin settles, then the line reads
`SPIN DONE — RETURN TO START 43 m` or `SPIN DONE — DRIVE ON 87 m`, and the run must get
there to pass. While a run is on, a glowing golden orb floats beside its start point and
a golden chevron stands beside the goal (the exit past the last cone, the box, the board;
the 180's goal is its orb); both are for looks, stand off the driving line and can be driven
through. A run ends by itself: the
slalom after the last cone, the stop box once the car has come to a stop, the spins and
the reverse 180 at their goal (or when the time limit
runs out). A banner then says `PASSED` or `FAILED` with the
measured numbers and, on a fail, the checks that were missed. A pass earns a bronze,
silver or gold medal for its time (`PASSED  SLALOM — GOLD`, the headline tinted to match;
gold is 5-10 % over the scripted driver's run, silver ~25 %, bronze ~50 %, the
`gold_time_s` / `silver_time_s` / `bronze_time_s` of the test's data): pass is pass, the
medal judges nothing. It stays for 5 seconds or
until `Esc`; the car stays drivable under it. Press the same number to retry, another
number for a different test. `Esc` or `R` aborts a run (`R` also puts the car back on
the start line); other number keys are ignored until then.

The verdict is always the test's own (`HandlingTests.result()`), the one the headless
harness prints. `scripts/mission_manager.gd` only picks the test, runs it
(idle, running, result shown) and hands the HUD its strings.

Every run is also written down (see [Telemetry](#telemetry)), and what that leaves
behind comes back on the HUD: the idle mission line ends with your last medal and your
best time on that test (`| last: GOLD, best: 28.8 s`) and a `PASSED` banner shows your
standing best under the medal times (`BEST 28.8 s GOLD — your 4 run(s)`). Before your
first run there is nothing stored and nothing is shown.

### Telemetry

Every drive is written down. `scripts/telemetry.gd` (a `TelemetryRecorder` the mission
manager makes in `_ready`) reads the car once every few physics ticks and writes one
JSON object per line - JSON-lines, `.jsonl` - to

```
user://telemetry/<YYYY-MM-DD>/<session>_<HHMMSS>_<context>.jsonl   e.g. 0007_103245_free.jsonl
user://telemetry/index.json
```

Free driving gets one file for the session, sampled every 30 ticks (2 Hz); each mission
gets a file of its own, sampled every 5 ticks (12 Hz), and the free file pauses while it
runs. The recorder never presses a key and never touches the simulation: it only reads.
It is on whenever there is a window to drive in, off in a headless run unless
`FD_TELEMETRY=1` says otherwise, and the last 20 sessions' files are kept - older ones
are deleted when a session starts.

A sample line holds the time and the car:

| Field | What it is |
| --- | --- |
| `t_session_s`, `t_run_s` | seconds since the recording started and since the test began (the car put on its start point, not the run clock); a tick count times 1/60 s, never a clock reading (`t_run_s` only during a mission) |
| `pos`, `heading_deg` | `[x, y, z]` in metres, and where the nose points in degrees (left positive) |
| `speed_ms` | speed along the nose [m/s], negative while reversing |
| `gear`, `rpm` | 0 neutral, 1-5 forward, -1 reverse engaged; engine speed [rpm] |
| `throttle`, `brake`, `handbrake`, `steer` | pedals 0..1 as the keys are held (the two swap roles in reverse), steering as a share of full lock, -1 (right) .. +1 (left) |
| `load_front`, `load_rear` | share of the load each axle carries (they add to 1) |
| `slip_front_deg`, `slip_rear_deg`, `slip_ratio_front`, `slip_ratio_rear` | how far each axle's tyres are sliding: slip angles [degrees], slip ratios (a speed difference over the road speed, no unit) |
| `yaw_rate_deg_s` | how fast the nose is swinging [degrees/s], left positive |
| `mission` | while a run is on: its `title`, `kind`, `elapsed_s` (since the test began) and the `progress` the HUD shows, which carries the run clock: `run_started` (over the start line) and `run_time_s` (0 until then, standing once at the finish) |

The first line of every file is the `session_start`: the session id, the context, the
engine version, the sampling it was written at - and `started_at`, the wall clock. That
field and the date and time in the file's name are the **only** clock readings there
are; everything else is counted in physics ticks, so the same drive always writes the
same numbers.

A mission's file ends with its verdict, `{"event":"result", "passed": true,
"run_time_s": 28.75, "medal": "gold"}`, or `{"event":"aborted"}` if the run was
cancelled. `run_time_s` is the run clock: from the car crossing the test's start line to
its finish, the time the medal is given for.
<!-- was: `run_time_s` (example 31.3) was the time from the start of the test to the end
of the run -> the run clock, see Mission mode. Times stored before the change are
2.5 - 3.5 s longer for the same drive. --> `index.json` keeps the running summary - `next_session_id`, the `sessions`
whose files are kept, the test driven `last_test`, and per test `best_time_s`, `runs`,
`last_time_s` and `last_medal` (times in seconds, `best_time_s` 0 for a test never
passed) - and that is what the HUD shows back: the idle mission line ends with
`| last: GOLD, best: 28.8 s` and a `PASSED` banner carries
`BEST 28.8 s GOLD — your 4 run(s)` under the medal times. Nothing stored, nothing shown.

### Camera

`C` cycles the one camera (`scripts/chase_camera.gd`) through chase (default), cockpit
(driver's eye, with a dashboard and steering wheel silhouette), front (on the bonnet),
overhead (straight down, north always up so the pad holds still; rises with speed) and
wheel (low by the front-left tyre, looking back at it: watch it steer, spin, lock under
braking, work up and down over the bumps and the tarmac run under its contact patch). It works at any time, including
during a test. Every offset, height and field of view is a commented constant in the
`Modes` block of that file.

Holding `B` looks back, for as long as the key is held. From the inside views (cockpit,
front) you stay in the seat and turn your head round over your shoulder, far enough to see
out of the back; from the outside views (chase, overhead, wheel) the camera cuts to a spot
ahead of the nose, facing back over the car at the road behind. Letting go returns to where
you were. The rear view is held-only, `C` never stops on it.

`X` toggles the X-ray (`scripts/xray.gd`, the `Xray` node in `scenes/car.tscn`): the body
panels turn translucent and a set of primitives shows what the physics models underneath -
ladder chassis, the engine ahead of the rear axle, the gearbox on the rear axle line
driving the rear wheels, the axles and a brake disc at every wheel. It works in any view
and is purely visual: the body materials are restored exactly when it goes off, and the
camera test checks a launch comes out the same with and without it.
