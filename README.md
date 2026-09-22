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
| Shift down / up (switches to manual; under neutral: reverse) | `Q` / `E` |
| Toggle automatic / manual gearbox       | `M`             |
| Automatic: sport / comfort / eco program (and its driver) | `N` |
| Traction control on / off               | `T`             |
| ABS on / off                            | `G`             |
| Stability control on / off              | `K`             |
| Clutch pedal (hold; manual mode only)   | `Left Shift`    |
| Starter (press to crank; hold to keep cranking) | `I`     |
| Reset the car to the start line         | `R`             |
| Flip an overturned car back on to its wheels (only overturned, and at rest) | `F` |
| Cycle camera: cockpit, front, overhead, wheel, chase (it starts where the car was left) | `C` |
| Look back (hold)                        | `B`             |
| Look left / right (hold)                | `,` / `.`       |
| X-ray view on / off                     | `X`             |
| Start handling test 1 - 5 (mission mode) | `1` - `5`      |
| Abort the running test / close its result | `Esc` (`R` also aborts) |
| Licence book open / close (`1` sits the L0 exam, `2` the skid pad test while it is open; digits answer the theory) | `L` |
| Garage open / close: the pause menu - drive, the study, car, licence, settings (`Esc` also opens it when nothing at all is running, and closes it); inside: `Left` / `Right` tabs, `Up` / `Down` rows, `Enter` go, `PgUp` / `PgDn` scroll, or the mouse | `Tab` |

Look left / right are on `,` and `.` (the `<` / `>` pair, under the right hand's reach from the arrows and next to `B`'s row): `Q` / `E` are the gearbox, `B` is look back. Hold to glance to that side, let go and the view comes back: the chase camera swings ~65 degrees round the car, in the cockpit and the bonnet view the head turns ~60 degrees; the overhead and wheel views have no side to look to. It is a glance, not a view of its own (`C` still cycles the same five), both keys at once look straight ahead, and look back wins over either.

The brake always brakes: it slows the car to a stop whichever way it rolls and holds it there, and never turns into reverse by itself. Reverse engages only on a fresh press of `Down` / `S` while the car is stopped; in reverse, `Down` / `S` is the throttle and `Up` / `W` the brake, and a fresh press of `Up` / `W` while stopped (or once the car rolls nose-first, as out of a J-turn) engages forward again. Holding `Up` / `W` through the stop also engages forward after a moment and drives away in one motion (the J-turn exit); reverse still needs a fresh press. The handbrake loosens the rear tyres, so steering while holding it swings the tail out. The HUD shows speed in km/h (prefixed with `R` while reverse is engaged), with two thin pedal bars beside it (green throttle, red brake: how far the driver's feet really have the pedals, see The driver below) and a thin fuel bar under them, with a thinner battery bar under that. Above it, the tach line shows engine RPM and the gear (e.g. `3000 rpm | G4`, with `M` in manual, `comfort` or `eco` on the automatic's comfort and eco programs and `STALL` once the engine has stopped) and turns red near the redline; over it sit the two driver aids' lamps, `TCS` and `ABS`, dim unless an aid is switched off (see The driver's controls below). The gearbox starts in whatever the car was last left in - automatic on a car that has not been driven - and goes back to automatic when you reset the car (the switches and the camera view stay as the driver has them; see The car's own file below).

### Driving feel

The car uses a custom arcade controller in plain GDScript (`scripts/car.gd`), not Godot's
vehicle physics. Every handling parameter is documented in the commented `DRIVING FEEL
TUNING` block at the top of that file. The car's own numbers (mass, engine, gearbox,
tyres, springs, the drivers' feet) are read from its config, `configs/cars/boxster_986.json`,
as the first thing a car does, and checked before any of them is used; the values in
`car.gd` are the certified fallback defaults, and everything derived from the numbers is
computed there. The same `car.gd` with a different config is a different car: see
`configs/README.md` for the schema and the split.

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
(1300 degrees a second: centre to lock in 0.35 s) towards what the keys ask for. Let
go and the hands turn nothing: it is the caster that brings the wheel back, like a real
car's (`CASTER_RETURN_RATE_MAX`, `CASTER_FULL_SPEED`) - the rolling front tyres' sideways
force acts behind the steering axis and turns the wheel straight, up to 600 degrees a
second at the tyres' peak (103 degrees of wheel) from 9 m/s up, easing in over the last
degrees (full lock to centre in 1.4 s, a lane change's 100 degrees in 0.8 s), less at a
walk (the same full lock in 5 s at 3 m/s), and standing still not at all: a parked
car's wheel stays where you leave it, and so does a reversing car's (the trail is the
wrong way round backwards; nothing centres the wheel in reverse but you). Unwinding
with the keys the caster helps the hands (full lock to centre in 15 ticks for the 21 it
takes to wind on, so lock to lock is 0.6 s), winding on the assist carries its load. To
straighten up quickly, steer back: the hands are faster. The front wheels are that angle
through the rack (`STEERING_RATIO` 16.4 : 1, which is what 450 degrees for
`MAX_STEER_LOCK`, ~27 degrees, comes to), at any speed, in any slide; nothing but you
turns the wheels, and the cockpit's wheel shows every degree (the yellow mark is 12
o'clock). A held key at speed winds on far more lock than the front tyres can use, so
they scrub and the car pushes wide: that is the tyres' honest answer, and short presses
are how you ask for less. Countersteer is wound on the same way, in proportion: catch a
slide early, by as much as it needs, because opposite lock is well over half a second
away.

Three things sit between the hands and the wheels besides the rack. The steering is
power-assisted the way a road car's is, lighter the slower you go: the hands have their
full speed up to 65 km/h (`STEERING_ASSIST_FULL_SPEED`), so parking is light and quick,
and from there the wheel gets heavier with speed, easing to 0.6 of the hand speed at
137 km/h and above (`STEERING_ASSIST_HIGHWAY`: centre to lock in 0.58 s instead of
0.35, and the same for whoever is driving - the assist multiplies the driver's own
hands). There is 0.75 degrees of play in the rack at centre (`STEERING_PLAY_DEG`): the
hands' motion about dead centre goes into the play before the rack moves, adds up (a
slow steady turn still comes, on the tick it is through) and leaves no standing offset;
a held key is through it on its first tick, so nothing certified changes. And the front
wheels hang on bushings: they trail what the rack asks (`rack_angle`) by a lag of
0.02 s, 0.04 with the front tyres loaded sideways (`STEERING_COMPLIANCE_TAU_MIN` /
`_MAX`; 2.5 degrees behind the test driver's hands at their fastest), and stand on it
exactly once close, so a corner held ends on the rigid rack's radius and yaw rate and
only the turn-in is softer (`wheel_angle` is what the wheels have and what the tyres
and the drawn wheels use).

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
  wheels outright while it is held; let go, the lever is out on that tick and what is
  left is `HANDBRAKE_RELEASE_TORQUE` (4500 Nm) on the rear brakes, dying away over
  `REAR_LOCK_RECOVERY_RATE` (0.33 s) along with the slide grip of a tyre that was
  locked. With nothing asked for that is what carries a flick; with the throttle down
  the engine pulls the rears out of it (1st gear breaks it at once, 2nd further down
  the decay, 3rd not at all), and the car lets its clutch back in for exactly that.
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
than ~25 degrees out (`SPIN_COMMIT_ANGLE`) and is off while the handbrake is held and
while what it leaves on the rear brakes dies away, so a
committed flick goes all the way round. `K` switches the whole assist off (`sc_on`, the
`SC` lamp; see the driver's controls below): the car then rotates on its tyres alone. A
slide nobody is driving settles by itself:
rear tyres that still roll keep their hold sliding sideways (`REAR_TYRE_SLIDE_GRIP`)
where the fronts and a locked wheel let go to `TYRE_SLIDE_GRIP`, so with every key
released the tail is pulled back into line, the sliding tyres scrub the speed off and the
car rolls on straight or comes to rest, held back by the engine whichever way it rolls.
A tap of handbrake with steering gives a drift
that comes back on its own; holding both from ~90 km/h until the car is nearly round,
then steering back to straight (rolling backwards nothing centres the wheel for you)
and braking once it has lined up, gives a 180; from ~125 km/h,
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
once. The handbrake is a lever and still bites instantly - and is out the tick the key
is. Asked for, the throttle beats the clutch the handbrake would hold open: gas during
or just after a pull and the clutch comes back in (0.1 s through the bite point) and the
engine drags the rears out of what is left of the lock - a clutch kick to catch a slide,
where before the throttle did nothing for the 0.4 s the lever took to let go. Which way the car goes is
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
car with feet several times slower. `comfort_driver` and `eco_driver` are who the `N`
key seats together with those two shift programs (see The driver's controls), and
`test_driver` with sport: nobody is racing in comfort or eco, and on keys that are on /
off the feet decide how much of a pedal a tap is. The test driver's 6-tick tap is the
floor, so the only throttle between none and all is a flutter of taps the revs cannot
settle under; the comfort driver's is 0.45 of the pedal (throttle 4.5 / s down and up,
brake 5 / s), the eco driver's 0.35 (3.5 / s, brake 4.5 / s), and because the pedal comes
up at the pace it goes down, an even beat of taps holds it where it is - around a
quarter from nothing, around a half after one longer press - a longer press takes it
further down, a longer gap lets it up. Held, the key still gets to the floor, in 0.22
and 0.29 s. Only the key seats them: `gearbox_mode` set from code and a reset leave
whoever is in the seat, and a driver seated by hand (`set_driver_profile`) stays until
the next press of `N`. An AI driver later is one more caller of `set_driver_input` with
a profile of its own.

#### Fuel, mass, exhaust and creep

The engine burns what its work costs: the combustion torque (the torque curve plus the
engine's losses, times the throttle it really has, the idle controller's share included)
times the engine speed is a power, and the fuel that takes is that power over an
indicated efficiency of 0.30 and petrol's 44 MJ/kg: ~0.6 L/h idling, ~67 L/h flat out
at the limiter, nothing on the overrun with the throttle shut. The tank holds the 986's
64 L (`fuel_l`, `fuel_fraction()`), a new car's tank is full, a reset keeps whatever is
in it (`R` is a reset, not a refuel: a fresh tank comes from a gas station or a canister,
both world content to come with iteration 4C), the running game keeps the level from one
session to the next (see Odometer below), and the thin bar lying under the pedal bars
shows it: amber under 15 %, red under 8 %. With the tank dry nothing burns: the engine
runs down, stops running, and stays down until there is fuel again (a reset on a dry
tank puts the car there running, and it runs down again the same way; with fuel in it the
starter catches, see below). The headless suite is the one place a tank is filled by
hand: a test starting hands the certified car its full tank, which is test furniture,
not game behaviour.

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
- **The licence ramp** - the hill start's hill in the yard behind the gantry (x = -30,
  its foot at z = 95, the crest at 75, level to 60, back down to 40): a straight 8 % rise
  of 1.6 m, a level top, a straight fall, 10 m wide with 5 m flanks, every knee on the
  ground mesh's 5 m lattice so the mesh is the ramp along its axis and across its top
  (at the four corners where a flank crosses a rise the two triangles of a mesh cell cut
  the bilinear height straight: 0.10 m off at worst, nowhere the car is driven). Drawn,
  stood on, ridden - and, unlike the swell, felt as a hill: on it gravity's share along
  the slope pushes the car down it (`ArcadeCar`, "the hill" in the tick), so a car with
  nothing holding it rolls back, the handbrake holds it (the locked rears creep 7 mm/s),
  and a clutch let in against it stalls the engine or pulls away. Off the ramp that share
  is exactly zero: every certified run's physics is the bit it was, and the swell stays
  the gentle, non-pulling approximation it always was.

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
under the body, while the body heaves, pitches and rolls above them. Take the ramp fast
enough and the car leaves the ground like a car: a wheel the road is further below than
that hangs at full droop and carries nothing, with all four off the car flies ballistic
(`is_airborne`: gravity, the air's drag and downforce, no drive, no grip, no steering, no
rolling resistance, no hill), and it comes down with a thud in the springs - measured in
`tests/airborne_test.gd`, and nothing of it on the ground (the user's catch, 2026-09-22:
"the wheels and body fell apart... somehow the joints stretched").

What it comes down on is honest too (the user's 20:35 retest: "every jump ends up on all
4 wheels, like a cat... now there is definitely a bug in the physics simulation"). Past
the small angles (`ATTITUDE_BLEND_START`, 0.1 rad; every certified run stays under 0.06
and keeps its arithmetic to the bit) the wheels' seats are carried round the centre of
mass with the body's real pitch and roll - and drawn so: the wheels go round with the
body, they do not hang on the vertical under a tumbling one - and the body has a
**shell**: the collision box's eight corners, each meeting the road under itself as a
stiff damped stop (`SHELL_RATE` 200 kN/m and `SHELL_DAMPING` 6 kN s/m a corner, inside
the integrator's stability bound) with sliding friction (`SHELL_FRICTION` 0.5) that holds
rather than pushes at rest. With the wheels under the car the shell never touches: the
reference jump's tail hop (3.4 m/s of sink) goes through the springs and stops, fronts
first against the slope, no wheel deeper than 2.6 cm into its stop, the body lying along
the 8 % tail within 0.02 rad by its foot, no bounce, no tumble; the foot of the tail (the
flat catching a body still descending along the slope) is the deepest of it, all four in
their stops and still 2 cm clear of the shell. The shell is for the big jump. Taken
across the ramp's 32 % flank at 30 m/s (the user's own jump, sessions 78 and 79) the car
leaves 0.42 rad nose-up pitching down, flies clean (the pitch rate constant, nothing
touching, 5 m of apex), comes down nose-first at 8.5 m/s of sink on to its two nose
corners (169 kN, the nose ~0.4 m into the road and back out: the shell yields like a
spring, it does not crumple for good), pole-vaults on to its rear wheels and rolls on;
taken across the flank at 50 degrees it comes down on the wheels of one side rolled past
its tipping angle (atan(`HALF_TRACK` / `CG_HEIGHT`) = 60.8 degrees), goes over to 110
degrees, comes back on to its side and stays there, its weight on the shell, no wheel on
the road, nothing driving. Overturned, the shell's friction is the kinetic friction of a
car on the road, `ROLL_FRICTION_COEFF` (0.45) times its weight at the most - not
`SHELL_FRICTION` times what a corner dug 0.4 m into the road carries for a tick - so a
tumble keeps its momentum: handbraked at 30 m/s along the hill's lateral with the wheel
hard right (the user's roll, session 82) the car goes over at 18 m/s, no tick takes more
than 0.45 g off its centre of mass, it scrapes 17 m through the roll and comes down on
its wheels 43 m on. (Before, the same run took 7 g off the centre of mass in one tick and
the car went on turning about the stopped contact - "like the car hit a wall and was
rolling against that wall".) Which it is - on the wheels, on its side, on the roof - is
the numbers' call, not a rule's, and deterministic: the flank jump twice from the same
state is the same run to the bit, and so is the handbrake roll. A wheel's stop is
counted to `GROUND_CLEARANCE` deep (5 cm into the rubber, where the shell's underside is
on the road) and no further: no wheel carries more than ~35 kN plus its damper, whatever
the tumble. (At c5ee9c3 it was 266 kN on one wheel, a rear seat 1.2 m under a body
pitched 1.2 rad by the small-angle formula: the catapult that flung the car into a
tumbling second and third flight over four wheels hanging straight down and let the
springs pull it flat - the cat.) The one place the shell shows on the reference jump is
the ramp's knee at 87 km/h: the front lip, with the fronts 9 cm into their stops, kisses
the 8 % rise for two ticks (3.5 kN). The collision box and the level ground plane under
the car's centre stay what they were, the backstop for a level body 5 cm into all four
stops; the airborne test holds that neither ever touches on any of its landings. Leaned
past 60 degrees a tyre is on its sidewall and carries nothing (faded out from 50), the
car is `is_overturned` and drives nowhere - so honest landings can leave you on your
roof or your side, and `F` (`flip_car`) rights an overturned car that has come to rest
(under 3 m/s) where it lies, heading kept, on its wheels at ride height, at rest, and
changes nothing else: not the fuel, not the wear, not the heat, not the gear, not the
odometer. Upright, in the air or still sliding it is refused; `R` remains the reset it
always was. Both draw the car they leave: the four wheels on the road at their own
corners, the body on its centre line, the scene's layout to the bit (the level picture
writes the whole transform now; it wrote the heights alone and left the rest where the
carried picture had put it - righted off its side the car had "no tires anymore
(visually), only tire marks", off its roof "the wheels are reversed").

The wheels are drawn turning at their axle's real speed, a tick's step at a time, folded
into a quarter turn either way (`WHEEL_DRAW_PERIOD`: the one bar across the rim looks the
same every half turn). That is what a wheel filmed at 60 frames a second shows, the
wagon-wheel effect: the real spin up to ~115 km/h, a flicker around there, then the
wheel seeming to turn backwards, slower the faster the car goes. (A cap on the drawn
spin, 100 rad/s, used to hold the wheels at 95 degrees a tick from 122 km/h up - for
that bar the one step that reads neither way, a shimmer.) Purely visual.

#### The driver's controls

Three aids, all on unless switched off, each with a small lamp over the tach that is dim
while the aid is on and amber with `OFF` behind it once it is not. They are switches on
the dashboard (`tcs_on`, `abs_on`, `sc_on`, and `gearbox_mode` below), not the car's
state: a reset puts the car back and leaves them as the driver has them.

- **TCS** (`T`). The car's traction control is its clutch foot: pulling away it holds
  the revs at the launch floor, passes what the engine makes there, and eases off
  whenever the driven wheels get to a slip ratio of 0.25. Switched off, the launch is
  what a driver without one does: the revs flare to the floor as before, and once they
  are there the clutch is let in for good, all it can pass, with no slip limit. In 1st
  that is far more than the rear tyres hold: they spin up to the engine's speed (slip
  ratio ~2.8 for the 0.10 of a launch with TCS), the clutch is home after 0.8 s on
  spinning wheels instead of 1.9 s, and the engine keeps them spinning until the car has
  caught up. Nothing about the tyres changes; the wheelspin is what the tyre curve makes
  of the torque.
- **ABS** (`G`). With it a braked wheel is held at a slip ratio of 0.15; without it a
  full pedal asks the front axle for more than its tyres have and the front wheels
  lock: wheel speed 0 with the car still moving, sliding on 0.85 of their grip with next
  to no sideways hold. From 90 km/h the stop is 37.8 m for 35.8, and full lock on the
  brakes for a second turns the car by nothing where the ABS car turns 18 degrees, until
  the pedal comes up and the wheels roll again.

- **SC** (`K`). The stability assist of "Slides and spins" above. Switched off it has no
  strength on any branch (`_slide_yaw_damping` is 0, also in reverse and under the
  handbrake, where the assist otherwise keeps a sliver): nothing leans on the nose any
  more, a slide hangs on for as long as the tyres let it and a spin is yours to catch.
  The same 0.2 s flick of the handbrake from 60 km/h swings the nose 0.46 rad off the way
  the car goes for 0.16 with the assist, turns the car 1.6 rad for 0.7 and takes 2 s to
  come back into line for 1. The low-speed blend is not part of it and has no switch: it
  is numerics, what keeps the tyre model meaningful near a standstill, not a driver aid.

The automatic has three shift programs, `N` goes round them (sport, comfort, eco, sport)
and seats each program's driver with it (see The driver): **sport** (up at 6800 rpm,
down under 2800; what the car starts in, and what it was certified with, untouched),
**comfort** (up at 2800 rpm, down under 1600, no kickdown; the tach line says `comfort`)
and **eco** (up at 2000 rpm, down under 1300, and the engine given no more than 0.7 of
its throttle however far down the pedal is; the tach line says `eco`). Manual mode knows
none of them.

Every engine has its own sweet spots for every program, so none of those figures is
picked by hand: `ArcadeCar.derived_shift_points(mode)` reads them off `TORQUE_CURVE` and
the engine's friction, the constants the box shifts by are its results rounded to the
100 rpm, and the smoke test holds the two within 50 rpm of each other - a car with
another curve re-runs the helper. Sport changes up where the full-throttle power has
fallen to 95 % of its peak past the peak (6791 rpm here) and down under the lowest speed
at which the engine makes 90 % of its peak torque (2820 rpm): it lives in the fat of the
curve. Comfort changes up at that same 2820 rpm, where sport would change down - the two
share no revs at all - and down under 75 % of the peak torque (1594 rpm). It was the
torque peak, 4500 rpm, which from the driving seat was "still sporty". Eco changes up at
the highest speed at which the engine still turns fuel into work within 1 % of its best:
the brake efficiency at full throttle, torque / (torque + friction), is 0.894 at
1000 rpm, 0.885 at 2000, 0.872 at 3000, 0.849 at 4500 - best at the bottom and worse with
every rpm of friction, within 1 % up to 2002 rpm - and down under 70 % of the peak torque
(1288 rpm). A lower gear is only taken if it lands a margin under the program's upshift
speed, the same share of it in every program (sport's certified 1000 of 6800 rpm: 400
for comfort, 300 for eco), which is also what keeps comfort and eco from taking back an
upshift into 2nd that lands under their downshift speed. The launch holds the revs no
higher than the program shifts up at (flat out, comfort changed out of 1st with 3950 rpm
on the tach off the launch's 4000 rpm slipping clutch, whatever its shift point), and
the car's own clutch never lets a locked engine under idle, so eco's 1150 rpm into 2nd
is a pull and not a stall. Eco's throttle ceiling was measured both ways, 400 m from
rest with the key held: 0.082 L in 25.9 s with it, 0.119 L in 21.7 s without. Over 300 m
at half a pedal eco burns about 40 % of what sport does.

In manual the shift keys now reach
reverse as well: it is the position under neutral, so `Q` from 1st is neutral as it
always was and `Q` again is reverse (refused while the car rolls forwards, or backwards
fast enough to over-rev the engine through the reverse gear); `E` out of reverse is
neutral, `E` again 1st. In reverse the keys are swapped as they are when the brake key
selected it. The automatic never takes reverse by itself.

**The clutch pedal** (`Left Shift`, manual mode only; the car that shifts for itself is
a two-pedal car) is the driver's left foot, 0.2 s from up to the floor and as long back
up (`clutch_pedal`). The car still works its clutch for gear changes and stops; the
pedal comes on top, and the driver's foot wins: from the moment it is touched until the
clutch is home again the car's feathering stays out of it - no launch floor, no easing
for wheelspin. Held, the clutch is open whatever the throttle does (full throttle: the
limiter, and the car goes nowhere); let go on a revving engine it is a clutch dump,
TCS or not; let go on an idling engine with the throttle only just going down, the
clutch is in before the revs are up and drags the engine down.

**Stall and starter.** Under 450 rpm (`STALL_RPM`) the engine stops running
(`engine_running`), whatever brought it there - the driver's clutch foot, or a dry
tank: no combustion, so no fuel burnt and no exhaust events, the tach runs down to 0
and says `STALL`, the throttle does nothing, the car lets its clutch go and rolls free,
and a stalled automatic does not creep. The car's own clutch never lets it come to
that (it opens above idle coming to a stop and feathers every launch over a floor), so
the automatic cannot be stalled and no certified run comes near it. `I` is the
starter: 150 Nm on a standing crankshaft, easing off to none at 700 rpm; the engine
catches at 500 rpm with fuel in the tank (after ~0.2 s) and the idle controller takes
it up to 900. One press is enough: a fresh press on an engine that is not running cranks
for 0.8 s (`STARTER_CYCLE_TIME`, physics time) whether the key is held or not, as a
modern car's button does, and the tach says `CRANKING` meanwhile; held, the key cranks
for as long as it is held. (It used to crank only while held, and a tap of a tick wound
the engine to ~96 rpm: tapping never restarted a stalled engine.) Cranking burns no
fuel, a dry tank only ever spins at ~620 rpm, for its cycle or for as long as the key is
held, and there
is no bump start (the clutch stays open on an engine that is not running). A reset
starts a stopped engine: it puts a car there that is ready to drive - on the fuel it
has; a reset does not refuel, so a car reset dry stalls again.

**Battery and alternator.** The starter draws on a 12 V, 50 Ah lead-acid battery
(`battery_charge`, 0..1 of what it held new, 2.16 MJ; `battery_wear`, the share of that
lost for good), kept in joules and watts, and the electrical side alone: the alternator's
drag on the belt and the fuel pump, injection and ignition the running engine feeds are
inside the engine's friction figure and its burn already, so nothing electrical adds a
torque to the crankshaft or a drop of fuel, and the battery's ~20 kg are inside the kerb
weight. What the starter really makes is its 150 Nm times the battery's cranking
strength, the square root of the charge - the one empirical line in it, the shape of a
lead-acid's cranking against its state of charge: nearly full to half, away steeply under
a fifth, nothing at empty. Everything else falls out of the torque line against the
engine's friction: from a third of a charge the engine is at 190 rpm where a full battery
has it at 330 and catches after 0.45 s instead of 0.18; under ~13 % it turns and never
catches; empty, nothing turns. The draw is a DC motor's, current with the torque, 1.5 kW
on a standing crankshaft with a full battery and less along the same line: a start costs
~170 J, a ten-thousandth of the battery. With the engine off the key-on load (ECU,
cluster, 30 W) drains it, ~20 h from full to flat. Running, the alternator charges it with
what is left after the ignition's own 150 W: little at idle (300 W at 900 rpm, so 150 W
net), its 1.5 kW from 2500 engine rpm up, at a charge efficiency of 0.85 and tapering off
from 80 % of full; a running engine never fails for want of the battery. A battery run
under 10 % is aged by it: 3 % of its capacity gone for good each time it goes under, and
1 % an hour for as long as it is left there, bounded at 90 % - it fills to less (the bar
never reaches the top), and full, cranks weaker than a new one; a battery that far gone
fills to a tenth and its starter turns nothing. All twelve numbers are the config's
(`battery`, optional: see `configs/README.md`). The bar under the fuel bar shows the
charge tick by tick, unsmoothed, amber under 40 %, red under 20 %; through a crank it
sags by what the crank takes, which on a 50 Ah battery is a ten-thousandth - the honest
figure, and not one you will see move. A reset (`R`, a test starting) is a new battery:
full and healthy, so the test pad never strands anyone; the running game keeps the charge
and the wear from one session to the next (see The car's own file). The temperatures,
the wear and the fuel are what a reset leaves alone: the coolant, the tyres and the
brakes keep whatever heat they held and go on cooling (or warming) from the next tick by
their own laws - the car cools as it cools; R does not turn back time on temperature -
the six wear shares stay (see Wear and aging) and the tank keeps its level. A test
starting is the exception: it hands out the certified fresh car, warm coolant, warm
tyres, cold brakes, new components and a full tank, so every certified run is the
physics it always was.

#### Wear and aging

The car's components age with the kilometres driven and with how they were driven
(`car.gd`, "Wear and aging"; the user's 15:24 verdict, 2026-09-22: "in a real car i get
more hill starts, 15 clutch launches / 46 hard stops is a very fragile car ... the
measurement is more in kilometers driven and how they were driven rather than how many
times i can start the car from a hill"; "we're not looking for drama, we are looking for
real physics simulation"). Nothing in it is new physics: the sim already emits every
quantity wear needs, and wear is bookkeeping over those outputs, a share of each
component's life, 0 new to 1 worn out, grown every tick by the tick's wear-equivalent
metres over the component's rated life - the kilometres of street driving that use the
whole of it up. The wear-equivalent metres are the way the odometer counted this tick
(the same number: the odometer is the single source) plus what the tick's own physics
says the driving cost over a gentle cruise, in metres of the component's life:

- the **clutch** (`clutch_wear`): the metres, plus its slip energy (|clutch torque| x
  |slip| x dt) at 5 m of life per kJ - a launch, an upshift, a clutch ridden on a hill
  (which slips at a standstill: metres of life with no metres of road); nothing extra
  while it is locked;
- each axle's **brakes** (`front_brake_wear`, `rear_brake_wear`): the metres, plus the
  work the discs were given (the same watts the brake temperature is warmed by) at 1 m of
  life per kJ, three times over on any tick the disc is over the fade line;
- each axle's **tyres** (`front_tyre_wear`, `rear_tyre_wear`): the metres (the rolling
  is the rated life's), plus the slip work against the contact patch - the frictional
  energy rubber is abraded by: a slide, a spin, hard cornering - at 0.5 m of life per
  kJ, three times over on any tick the tyre is over its window;
- the **engine** (`engine_wear`): its own metres - its revolutions in top-gear metres
  (the wheel's radius over the top ratio times the final drive, 0.09 m a radian: in top
  gear, locked, exactly the road's way; in 2nd at the same speed twice them; idling, 31
  km/h of them - an engine that runs ages, as the fleet rule of thumb has an hour's idle
  for some 25-30 miles) - times the load's style, 1 + 5 x the square of the load the
  clutch takes off the crank as a share of the curve's peak (a light cruise ~1, flat out
  6); over the overheat line every revolution counts at full load and ten times over.

The style multiplier of a tick, the wear-equivalent metres over the metres, is exactly 1
on a gentle cruise (a locked clutch, the pedal up, the tyres rolling, in top gear) and
over 1 for everything harder: that is what "rated life" means. The lives and the costs
are the config's (`wear`, optional: see `configs/README.md` for the table), from a
research pass on what the real parts take; each is SOURCED or an ESTIMATE, and says so:

| Component | Rated life | Source | On top of the metres |
|---|---|---|---|
| clutch | 175 000 km | sourced: 100 000-250 000 km on the street (986 owners); the midpoint | a flat-out launch ~ 300 m of its life (estimate, 100-500 m): 5 m per kJ of slip |
| brake pads | 50 000 km, either axle | sourced: ~30 000-70 000 km, Porsche-class cars trending high; the midpoint | a full ABS stop from 90 km/h ~ 200 m of a set's life (estimate from ½mv², 100-300 m): 1 m per kJ of disc work, x3 over the fade line |
| rear tyres | 17 000 km | sourced (forum): 10 000-24 000 km for a performance summer rear; the midpoint | a donut ~ 1.25 km of their life (estimate, 0.5-2 km): 0.5 m per kJ of slip work, x3 over the window |
| front tyres | 25 500 km | estimate: no number sourced; the fronts of a mid-engined, rear-driven car carry less and drive nothing, taken as 1.5 x the rears' | the same slip cost |
| engine | 140 000 km | sourced (forum): ~130 000-150 000+ km before major work for this era; the midpoint (the IMS bearing is a separate failure mode, not wear, not modelled) | flat out ~ 6 x a cruise per km (estimate, 2-10x); the square of the load is the estimate's shape |

What the driving comes to, measured by `tests/wear_test.gd` on the certified car: a
flat-out 8 s launch costs the clutch 2.7 ppm (341 m of slip on top of 133 m of road, a
style of 3.6: some 3700 such launches to the first percent, where it was 15); a full stop
from 90 km/h costs the rear pads 5.0 ppm (216 kJ of work on top of 36 m, a style of 7:
~2000 stops to the first percent, where it was 46); a 25 s donut costs the rears 74 ppm
(1574 kJ of slip work, a style of 14: 135 donuts to the first percent, where it was 35);
8 s flat out costs the engine 11.6 ppm (a style of 12); 1.5 km of cruising in 5th at 72
km/h costs every component exactly its rated share of the metres (8.6 ppm of the clutch,
30 of the pads, 59 and 88 of the tyres, 12 of the engine at a style of 1.11), and the
second 750 m the same as the first. The whole certified suite is a few hundred metres:
nothing in it comes within a hundred of a percent.

What wear does, each a multiplier on something that already exists: a worn clutch passes
less torque (more slip, a softer bite, never under 70 % of its capacity); worn brakes
give less for the same pedal (never under 75 %, on top of the fade); worn tyres grip
less (never under 85 %); a worn engine makes less torque (never under 85 % of the
curve). Nothing breaks: a worn-out component works at its floor. Every multiplier is
EXACTLY 1.0 at zero wear, and every multiplier reads the wear at whole hundredths: the
accumulators count every metre, continuously, but the effect moves in one step per 1 %
of wear (`WEAR_EFFECT_STEP`), so under 1 % of wear a multiplier is exactly 1 and the car
is the fresh car to the bit. That staircase is what keeps the certified runs certified:
a handling test's start hands out the new car, a certified run wears it well under a
hundredth of anything (the tests state the numbers), and its physics is the fresh car's
to the bit. From 1 % on the effect steps once a percent, in a line to the floor at worn
out. A worn car's telemetry shows why it is worn: the same slip energy, brake work, slip
work, revolutions and load that grew the shares are the tick's own outputs, and every
claim above is checkable by driving.

Wear is for good. `R` puts the car back and puts in a new battery; it does not un-wear
and it does not refuel: the six shares stay where they were through a reset, as the
temperatures and the tank do. Service comes with the garage (iteration 4A); until then
nothing in the game restores a component. Between sessions the wear rides `user://cars.json` beside the
battery (see The car's own file below); the headless suite and the certified runs read
nothing, every car there starts new.

### Tests

```sh
tests/run_tests.sh
```

Runs a headless import, then `tests/config_test.gd`: every car config under
`configs/cars/` read the way the car reads it and put through the validation, in
seconds, so a broken config fails the suite there and not somewhere in the smoke test. Then
`tests/smoke_test.gd`, which loads the main scene and
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
and 0.6 s lock to lock (the caster helping the first half), the wheel let go on the
move waited for at centre wherever a check lets go, and left at its lock rolling
backwards; and the shape of the tyre curve; and the driver: a tap of the
key is a partial press, a held one reaches exactly 1.0 and a lift decays to 0, the
chauffeur's foot is measurably slower than the test driver's, `set_driver_input`
launches the car with no key down exactly as the key does, holds half a pedal, clamps
what is out of range and keeps the reverse rule, and the HUD's pedal bars follow the
pedals and take 0..1; and fuel, mass, exhaust and creep: idling burns ~0.6 L/h and flat
out some 70 times that, nothing burns on the overrun, a dry tank stops the engine, a
reset keeps it dry to the bit (and a half tank half) while the test start hands out the
full one, fuel handed back by hand takes the starter to run again, the fuel bar reads
the tank and changes colour, `total_mass()` has the
fuel and the payload in it, 300 kg on board ride level and are slower over the same 5 s,
a test's `payload_kg` is loaded at its start, the exhaust fires three times a turn and
its flow follows the throttle, and the car creeps when the brake is let go at a
standstill, stands on a held brake, untouched and in manual; and the driver's controls:
the three switches start on / on / sport, flip on their keys, light their lamps and
survive a reset, a launch without TCS spins the rears far past what the TCS holds them
at and has the clutch home sooner, a stop without ABS locks the front wheels, is longer
and does not steer, the clutch pedal held keeps a car at the limiter standing and let go
is a dump, does nothing in automatic, and let go on an idling engine stalls it, a
stalled engine burns and fires nothing and its car does not creep, the starter catches
it, never on a dry tank, and a reset starts it, reverse sits under neutral on the shift
keys and is refused rolling forwards, comfort leaves 1st at 2800 rpm where sport holds
it to 6800 and eco at 2000, sport to the digit what it was before there were three
programs, each program's constants within 50 rpm of what `derived_shift_points` makes of
the engine, the `N` key goes round sport, comfort and eco, names comfort and eco on the
tach and seats each program's driver, who stays through a reset as eco does, while a
driver seated by hand stays through a reset and a program set from code until the next
press, a 6-tick tap is the floor for the test driver and under half the pedal for the
comfort and eco drivers, eco gives the engine 0.7 with the pedal on the floor or out of
range and nothing for NaN while comfort, sport and manual mode get all of it, 300 m at
half a pedal burn well under 0.6 of sport's fuel on eco with the engine running
throughout, eco's drive cycle up and down the box never changes down within 2 s of a
change up and never brings the engine under idle, and the telemetry's throttle and brake read the pedals; and the handbrake let go: the
lever reads out on the release tick with its hold still on the rear wheels, the gas
after a tap pulls them past the road within 14 ticks while nothing asked for leaves them
locked and the clutch open with the engine idling on, the clutch pedal dumped with the
handbrake held is no dump at all, and the hold is gone inside 0.37 s), then the
handling tests below, then
`tests/camera_test.gd` (cycles the camera through its five views and drives under each, holds the look-back,
toggles the X-ray, holds look left / right from the chase view and the cockpit, turns the
cockpit's steering wheel with the car's, and carries the chase camera straight over its
aim point, which used to trip a colinear look-at warning)
and `tests/mission_test.gd` (plays every mission through the mission manager with the
scripted driver pressing the keys and checks the medal on every banner, plus one run with
its steering held off and one 180 left parked where it stopped, which both have to come
out FAILED, and an abort), and `tests/battery_test.gd` (the electrical system: the
model's own numbers - 2.16 MJ, the alternator's curve at its anchors, the ~13 % a catch
needs worked out from the starter's line against the engine's friction, over the 10 %
deep-discharge line; the suite starts on a full, healthy battery with the store off; the
alternator charges at idle at the curve's 150 W net and at the limiter in neutral at its
1350 W, nine times as fast, and a full battery stays at exactly 1; the key-on drain is
30 W over a tick; a crank starts the engine in 11 ticks for ~170 J, thirty-odd times the
drain over the same ticks, and the HUD's bar sags through it tick by tick, each tick the
car's own charge; from 30 % the crank rpm is lower at the same tick and the catch comes
after 27 ticks instead of 11, from 5 % the engine turns to ~320 rpm and never catches,
empty nothing turns and the charge stays 0, and a battery half worn fills to half and
cranks slower than a new one; the key-on drain taking a battery under the line costs 3 %
once, 10 s down there 1 % an hour on top, back over and under again 3 % more, the
capacity read follows the wear, full is 1 less the wear, and the wear stops at 90 %; the
bar follows the charge at three levels with its colours, hides at 0 and for NaN, clamps at
1, and leaves the fuel bar alone; the store gives both numbers back to the bit in the one
entry beside the odometer, the fuel and the dashboard in the one write, a car, a file or
an entry without them is full and healthy, 26 values that are no share of a battery are
refused with the reason naming the car and the field, the number beside a bad one still
loads, a car that loads 15 % with 25 % worn starts so with a red bar, one saved fuller
than its wear leaves is trimmed, a reset is a new battery and the file is not told; and
NaN, inf and -inf charge and wear read flat, full, flat and none).

The smoke test's last phase is the telemetry recorder (below): it switches the recorder
on in process, points it at `smoke.jsonl` in a tmp dir of the run's own
(`/tmp/fd-3R-smoke-<pid>/`, made by the test, removed when it finishes, so that two
suites can run side by side), starts a real mission
through the mission manager, drives it for 2.5 s, aborts, and reads the file back line
by line - every line one JSON object, the first the `session_start`, every sample
carrying the car's state and every mission sample the run with it, the mission samples
exactly 5 physics ticks apart and the free ones 30, the last line `{"event":"aborted"}`.
Nothing that comes off the wall clock is asserted, and nothing is written under
`user://` (a headless run records nothing by itself, and the phase's own recording goes
to that tmp dir, whose name is never printed), so the suite reads the same on every run.

After the telemetry come the tyre marks (below): none while the tyres grip (flat
out with TCS, a full pedal with ABS), trails under a handbrake slide, every mark a tyre
wide and lying on the ground the pad shows, one every half metre and not one a tick; a
launch with TCS off marks the rears' two tracks for as far as they spun, a stop with ABS
off marks the way the car slid on front wheels standing still; the fade tick by tick and
the place it frees after 30 s; the pool bounded, the oldest mark laid anew; the same
slide from a reset leaving the same marks to the bit; a reset clearing them; no NaN;
and the slide ending in the same place, to the bit, with the marks switched off. Then
their severity: full lock off the throttle from 30 km/h lays nothing, from 45 km/h faint
marks (fresh alpha under 0.3), the handbrake slide's are black against them (most of them
at the full 0.75), and the same scrub leaves the same shades to the bit.

The stability switch comes next: on at the start, `K` flips it and nothing else, the
`SC` lamp in the row of the other two, a reset leaves it alone, switched off the assist
has no strength on any branch, the same flick of the handbrake slides far deeper and
hangs on longer without it, and the low-speed blend still has a creeping car on its
rolling circle.

Then the starter's cycle: a tap of one tick starts a stalled engine (caught after
0.17 s, no fuel burnt cranking, the tach says `CRANKING`), does nothing to a running
one, cranks a dry tank for its 0.8 s and never catches; held, the key cranks on; a reset
in the middle of a cycle ends it.

Then the wheels at 130 km/h: drawn the real step less a half turn, never more than a
quarter turn a tick, which is backwards.

Last the odometer: flat out and a stop are on it to the micrometre, a reset neither
zeroes it nor counts its jump, reverse and a handbrake slide count as the body goes, a
way that is not finite is not counted, never NaN, the HUD's line; and nothing of it on
disk: the store is off in a headless run, the car began the run at 0 whatever
`user://cars.json` holds and its metres never get there (the store itself is tried on a
file next to the telemetry phase's).

And the fuel kept beside it: the car came out of `_ready` with the full tank to the bit,
the store off, whatever `user://cars.json` holds; a level goes through the store and
comes back the float it was, beside the odometer; NaN, inf, under 0, over the tank, words,
null and a bool are no fuel level (a full tank and the reason, as text); and a car that
loads 5 L starts with 5 L, their 3.7 kg and a red bar - a reset keeps the level it has
idled down to, to the bit, the file is not told.

And the dashboard kept with them: the car came out of `_ready` with the aids on, the
sport program, automatic and the camera in the cockpit, the store off; all six settings
go through the store and come back as they went in, in the one entry beside the odometer
and the fuel and in the one write; a switch that is not true or false, a program this
gearbox has not got, a view outside 0 .. 4, a fraction of a view, NaN, inf, words, null
and a list are no driver setting (that one default and the reason, as text, naming the
car and the field); and a car left with the aids off, the eco program, the gearbox in
manual and the bonnet view starts exactly that way, its own eco driver in the seat - a
reset puts the gearbox back in automatic and leaves the rest standing, the file untold.

And the car's config, ahead of the mass checks: the file passes its validation, the car
that read it runs the certified torque curve to the bit, a config without any of its
optional keys is still a car, and a required key left out or a torque anchor that is NaN
is refused by name - by the validation's functions alone, never read into the running
car.

And the wear (`tests/wear_test.gd`): the car comes out of `_ready` with nothing worn -
all six shares exactly 0, every multiplier exactly 1 - and idles so but for the engine's
revolutions; a multiplier is exactly 1 under 1 % of wear, steps once a percent in a line
to the floor and never under it, the config's sixteen numbers are the car's to the bit,
a life of no distance, a cost under zero, a multiplier under 1, a floor outside its
range and an unknown key are refused by name and a config without the table is a car;
the clutch wears exactly the metres plus its slip's metres of a flat-out launch over its
life (68 kJ, 341 m on top of 133 m, 2.7 ppm, the metres alone on the locked ticks, the
brakes their metres alone), the pads exactly the metres plus the work's of a stop from
90 km/h (174 and 216 kJ; the engine its revolutions at no load on the overrun), the
rears exactly the metres plus a donut's slip work with the abuse multiplier on the ticks
over the window (the brakes doing no work on any tick the pedal was off), the engine
exactly its revolutions in top-gear metres times the load's style flat out, at a style
of 1 at the limiter in neutral and idling warm, at full load and ten times over idling
overheated; 1.5 km of cruising in 5th wears every component its rated share of the
metres, the style exactly 1 but for the driven rears and the lightly loaded engine, and
the second half the same as the first; worn brakes stop the car 7 % longer half
worn and 15 % worn out, a hair further inside the same hundredth the same stop to the
bit, and past worn out the same stop to the bit; a worn-out clutch passes at most 350
Nm where the new one passes 500 and slips more ticks; worn tyres hold 0.81 g half worn
and 0.74 g worn out where new ones hold 0.88, past worn out the same to the bit; a
worn-out engine burns for the floor's share of the curve and is slower over the same 8
s; the six shares go through the store to the bit in the one entry beside everything
else in the one write, an old file without them is a new car's and rounds through
untouched at version 1, 78 values that are no share of a life are refused with the
reason naming the car and the field, a car that loads worn components starts with
them; a reset keeps six shares set by hand to the bit and tells the file nothing, and a
handling test's start hands out the new car before its first tick; and NaN, inf and
-inf shares read none, worn out and none, NaN, infinite and negative tick quantities -
the way among them - add nothing.

And the licence ladder (`tests/licence_test.gd`, see [Licence ladder](#licence-ladder)):
the L0 exam sat through the `LicenceManager` the way a player sits it - the book opened
with `L`, the sitting started with `1`, every element driven by a scripted pilot on the
input actions, the theory answered on the digit keys - and every element judged PASSED
on its measured checks (the parallel park 0.24 m inside the side lines and 1.19 m inside
the ends, 1.1 degrees off, 8.3 m reversed; the bay park 0.3 m inside, 0.8 degrees off;
the hill start rolled back 0.6 cm of the 15 allowed, no stall, over the crest at
10.6 m/s; the turn in the road in 2 direction changes, 6.1 m of it reversed, never
outside the lane, 3.4 degrees from facing back; 30.7 m reversed between the lines into
the end box by 0.7 m; 54 km/h at the bar and stopped 13.1 m on, 0.9 m inside the zone;
8 of 8 answered); the gate before, during and after (unlicensed the clutch key leaves
the pedal at 0 and `T`, `G`, `K` are refused with the hint by the lamps; in the sitting
the hill start is driven on the pedal in manual; licensed the pedal moves and the
switches flip); the book holds the number keys and frees them; a practice run on the
complete record that dumps the clutch on the locked axle stalls and fails the sitting
at once at element 4/7 with the three before it passed; a wrong first answer fails one
at 1/7 before a wheel turns; the handbrake let go before the bite rolls back 15.6 cm
and fails the element the moment it does, no stall; the skid pad test (2.04 laps in
31.4 s, every wheel between the rings, no cone down); L1 only on the seventh of seven
passes, a FAILED handling test never recorded; the record to the bit through the store
beside the odometer, the fuel and the wear, an old file untouched at version 1, a level
the passes do not earn written and read as what they earn, 14 non-levels and non-lists
refused with the reason; the per-element memory: the elements passed as the record's
third field (an old licence object without it a clean slate, a malformed one reported),
the level they earn (all seven, or the old exam-level pass alone), the manager seeded
from a file with the theory passed resuming at `ELEMENT 2/7` in manual and driving the
six practical elements to L0 with each saved as it passed - manual through the parks
and the hill start, automatic from the three-point turn on - a stalled hill start on a
record of three leaving the three in the record and on the file with `1` retaking from
the hill start, and a wrong answer on a practice run changing nothing; and the ramp:
8 % up, level, 8 % down, exactly zero at 13 certified points, straight between the
mesh's 5 m points along its axis (0.23 mm).

And the garage (`tests/menu_test.gd`, see [Garage](#garage), [The study](#the-study) and
[Data location](#data-location)): the garage opens on `Tab` and on an `Esc` pressed with
nothing at all up, never on the `Esc` that closes a banner or the book, and refuses to
open over a running test; open, the tree is paused and the car frozen - the same drive
with the garage open for 60 ticks in the middle ends identical to the bit to the same
drive without it (position, velocity, engine, gear, fuel, heat, steering, odometer), and
nothing moves while it is open; the DRIVE page lists the one map there is, the five
tests in order, the L0 sitting and the skid pad, and each row starts its run through the
mission manager or the licence manager (a human run, the theory card up), free driving
closing the door and starting nothing; the study's catalogue is sound (every lesson a
title, an objective, a group and a pilot that is found, or an honest coming-soon flag;
the reused pilots equal to the test and exam definitions in every field; the lesson
pilots' steps only conditions the runner knows and keys the map has; the captions on
steps their pilots have); lessons run for real - the steering lesson through the
garage's row on a car left in manual, eco, TCS off, with the gate taken off and the
managers stood down for it and everything handed back after, the display having shown
both full locks, the throttle and the brake and the captions having followed the steps;
the stall lesson flashing `STALL` and `RUNNING AGAIN` with the engine running at the
end; the TCS lesson flashing `TCS OFF`, `WHEEL SPIN` and `TCS ON`; the donuts lesson
ended on `Esc` with the aids back on; a coming-soon lesson and a lesson over a running
test refused; the STOP BOX walkthrough passing the test's own checks on the certified
pilot; the input display reading the car's steer, pedals, handbrake, gear and aids, and
its events as pure functions of a snapshot; the CAR page reading a whole entry back from
a store file of the test's own and the live car into the same shape; the data folder
resolved from the variable, the bootstrap file or the default, a relative or a Godot
path refused by name, the bootstrap file written, refused and cleared, and the one-time
seed copying byte for byte, never over a file, never touching the source, never twice,
the autoload having seeded nothing with no window; the bar legend naming every bar; every
key the controls text names in the map, `Tab` among them; the LICENCE page's checklist
ticking exactly the three elements a seeded record holds and all dashes on a fresh one;
no folder dialog ever made; and, the window set to the game's own 1280 x 720, every
garage page walked with `Tab`, `Right`, `Down` and `PgDn`, the book on `L`, a lesson's
input display with its caption, the mission line and the banners laid out and measured,
nothing reaching past the screen and every row landing inside the scroll area.

### Handling tests

The fourth step of `tests/run_tests.sh` runs `tests/handling_test.gd`: a scripted driver
takes the real car through five tests on the pad, one after the other from a fresh
start, and prints `PASS name` / `FAIL name` plus a metrics line for each. If a test
cannot be passed, either the driver or the car is not set up properly. The drivers
steer back actively, the way a real driver does: a step's `"steer_deg": 0.0` taps the
keys until the wheel is within a tick of the hands of straight and holds it there
(letting the key go leaves the wheel to the caster, which is slow at a walk, nothing
rolling backwards and nothing standing still).

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
The scripted driver is timed the same way, so its certified times (slalom 28.65 s,
180 15.95 s, 360 18.07 s, stop box 8.72 s, reverse 180 7.72 s) are what the medals are
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

### Licence ladder

Rigorous, real-licence-shaped certifications (the user's design, 2026-09-22 23:20):
cartoon world, serious rules. Press `L` for the licence book, an overlay listing the
ladder, what the car's driver has passed, the rules and the keys; `L` or `Esc` closes it.
While it is open, `1` sits the L0 exam and `2` the skid pad test, and the number keys are
the book's - no handling test starts (`scripts/mission_manager.gd` is told,
`start_keys_locked`); with the book closed, `1`-`5` are the free training they always
were. During a sitting the line under the controls text reads e.g.
`L0 EXAM  ELEMENT 4/7  HILL START — BITE AND AWAY — rolled back 1 cm, crest 12 m  8.3 s`
with the element's objective under it; `Esc` or `R` abandon the sitting (no verdict; the
elements passed so far are already in the record). A banner then says `PASSED  L0 EXAM`
with the licence now held, or `FAILED  L0 EXAM` with the element it failed on, its
measured numbers and the checks missed; `1` under it retakes - from the element that
failed, not from the theory - and `Esc` closes it. `scripts/licence_manager.gd` only picks the exam, moves it
through idle, running, result shown and hands the HUD its strings; the elements and
their checks are the data in `scripts/licence_exams.gd`, run with the scripted driver
off, the human's driving through the same checks the headless test drives. Every
verdict is measured: the car's 1.8 x 4.2 m footprint against painted lines, the pad's
own cones toppled, real roll-back, a real stall, the real handbrake and clutch pedal,
the real speed at the cue. Nothing is a timer.

**L0 CITIZEN** is seven elements in a fixed order, the theory first, then six practical
elements, and **the sitting remembers**: every element passed goes into the car's
record the moment it is passed (saved at once, so it survives a failed later element,
`Esc` and the process ending). Any element failed - a wrong answer, a cone down, a wheel
over a line, a stall - ends the sitting at once; the elements after it are not sat, the
ones before it stay passed, and the next sitting (`1` in the book, `1` under the FAILED
banner, or the garage's DRIVE row) begins at the first element not yet passed. A passed
theory is never retaken. The seventh element passed grants L0. With every element in the
record the exam can be sat again from the theory as a practice run, which changes
nothing: a pass is recorded once and never taken away. The book (`L`) and the garage's
LICENCE page show the checklist - `Theory: PASSED` or `Theory: —`, then each practical
element `[PASSED]` or `[ - ]`. (Until 2026-09-22 the sitting was one sitting, all or
nothing, a retake a new sitting from the theory: the user's verdict, 14:56 + 15:02 -
"it's annoying that if i fail any of the L0 tests i need to get back to theory and not
retry the test i failed, it's like nothing remembers i took the tests". The rule dated
from L0 being two exams, theory and practice, each with its own retake.) **The
instructor's car** is a manual for the first three practical elements - the parallel
park, the bay park and the hill start - and an automatic from the three-point turn on,
"now they've proven they can drive an auto": an element flagged `"manual": true` puts
the gearbox in manual as it starts, and every element's start resets the car, which
re-arms automatic. The elements, in the licence yard behind the start gantry (positive
z, driven towards the gantry like everything else on the pad):

1. **Theory** - 8 question cards on the HUD overlay, three answers each, fixed order,
   digits `1`-`3` answer, 20 s a question. Every question is a rule the sim itself proves
   (what TCS off does to a launch, what ABS holds the fronts at, which wheels the
   handbrake locks, what the clutch let up on a held handbrake does to the engine, when
   the run clock starts, what SC off leaves to the driver, what `R` does to wear, what a
   fresh brake press at a standstill selects). One wrong answer fails the sitting.
2. **Parallel park** - a 2.4 x 7.0 m bay on the right (x = 12, z = 50; the car is
   1.8 x 4.2, so 0.3 m a side and 1.4 m an end), the kerb its right edge, a bumper cone
   0.5 m beyond either end line. Drive past it, reverse in, stop: the whole footprint
   inside the lines (the clearance to the sides and the ends is measured and shown),
   within 10 degrees of the bay's axis, at least 3 m of it reversed, no cone down.
3. **Bay park** - a 2.6 x 5.2 m bay (x = 22, z = 80) off an aisle, painted neighbours
   either side, a cone on either back corner. Nose-first in from the aisle: whole car
   inside the lines, within 10 degrees, no cone down.
4. **Hill start** - up the 8 % ramp, stop with the whole car inside the 3.6 x 8 m hold
   box painted on the rise, hold on the handbrake with the foot off the brake, the clutch
   pedal (`Left Shift`) to the floor, revs up, bite and away over the crest line at
   1.5 m/s or more. Roll-back is measured from where the car stopped, at every tick until
   the crest: 15 cm at most (the handbrake itself lets the locked rears creep 7 mm/s, so
   a driver ten seconds on the lever has 7 cm before the clutch has done anything; the
   clean pull-away - lever and clutch key let go together, revs up - rolls back 0.7 to
   1.1 cm). A stall fails the element on the spot, and the sitting with it (the clutch
   let up to the floor on the locked axle with the throttle open lugs the engine under
   450 rpm; letting the lever go with the pedal still down rolls the car back 16 cm in a
   second). Sat in manual, like the two parks before it (`M` undoes it, and then there
   is no pedal to floor). Mind the car's own rule: a fresh press of the brake at a
   standstill is reverse, so the lever goes on before the foot comes off the brake.
5. **Three-point turn** - on the straight between two white bars (z = -12 and -48),
   from the right-hand side of the lane: turn to face back the way you came, every
   corner of the car inside the lane's edge lines (6 m either side) and between the bars
   the whole time, 2 to 4 direction changes (three- to five-point), at least 1 m of it
   reversed, within 20 degrees of facing back, stopped. The 12 m lane is narrower than
   the car's 13.6 m wall-to-wall turning circle, so it takes the three points.
6. **Reversing course** - a 3.2 m wide, 34 m long lane (x = -14, z = 38 to 72, 0.7 m a
   side) with a cone pair at two gates (4 m apart): reverse up it from its near end, at
   least 25 m, every corner between the lines the whole way, no cone down, stop with the
   whole car inside the 8 m end box.
7. **Emergency stop** - down the yard's middle lane from z = 100: 50 km/h or more at the
   red bar with the STOP board (z = 58; the line says `STOP!`), then stop as hard as the
   car will, the whole car inside the 3.6 x 16 m zone beyond it (z = 33 to 49), no cone
   down at its far corners. From 54 km/h the car stops 13 m past the bar; the zone leaves
   about half a second of reaction either way.

**L1 FACTORY ENTRY** is L0, a recorded PASSED on each of the five handling tests (the
free training on `1`-`5` is exactly what counts: every mission PASSED goes into the
record) and the **skid pad discipline** test, 2A's circle finally judged: from a standing
start on the ring's east side, two full laps between the two cone rings (radii 22 and
34 m round (-70, -90)) with every corner of the car between them the whole way, no cone
down, the laps done inside 50 s. The scripted driver holds a 28 m radius at 43 km/h (the
geometric wheel angle for the radius plus a correction on the radius error and its rate,
the keys tapped so the wheel hovers there) and does the two laps in 31.4 s, never off the
ring; a driver has 19 s in hand.

**The gate.** This is what the licence is for: a driver who holds no L0 cannot work the
clutch pedal key (the pedal stays up, the car works its own clutch as ever) and cannot
switch TCS, ABS or SC off (`T`, `G`, `K` are refused, `LICENSED ONLY — L  licence book`
flashes by the aid lamps for 1.5 s). L0 unlocks both, for good. During a sitting both are
allowed - the instructor's dual-control car, so the parks and the hill start can be sat
in manual. The car knows
nothing of licences: it holds a gate reference (`ArcadeCar.licence_gate`, null by
default = everything allowed, which is every test scene and every certified run) that
the licence manager wires up from `main.tscn`, and asks it the tick a gated key is read.
The smoke test's driver is granted L0 through the manager's record before it tests the
switches and the clutch; the gate itself is the licence test's to check.

**Ranks** - data only, not yet playable (`LicenceExams.RANKS`): test driver (= an L1
holder) -> race driver -> chief test driver, each rank a certification set; the sets for
the second and third are to be written when their content is, and Porsche ownership
stays the North Star's reward. Nothing here builds them.

**The record** lives per car in `user://cars.json` (see [Odometer](#odometer)), under
`licence`: the level held and the exams passed, loaded by the manager when the scene
comes up and saved on every pass, behind the same switch as the rest of the store - the
running game keeps it, the headless suite writes nothing. The future garage (4A) reads
it there; nothing of it is built here.

### Garage

`Tab` opens the garage: the game's menu, a pause overlay over the pad
(`scripts/garage.gd`, the `Garage` layer of `scenes/main.tscn`, built from plain
Controls, no assets). It opens when nothing is running - not over a handling test, a
licence sitting or a lesson - and `Esc` opens it too, but only when nothing at all is up:
no run, no banner, no book. During a run `Esc` keeps its meaning (abort); with a banner
or the book up it closes that first, and the next `Esc` opens the garage. `Tab` or `Esc`
close it. While it is open the scene tree is paused (`SceneTree.paused`): the car, the
managers, the HUD and the telemetry recorder stand still, the driving keys reach nothing,
and when the door closes the pad runs on from exactly where it stood - the same ticks
after the same ticks, to the bit, whether the garage was open in between or not
(`tests/menu_test.gd` holds it there). No time scale, no delta of its own, nothing in the
car knows the garage exists.

Five pages, tabs across the top; `Left` / `Right` change tabs, `Up` / `Down` move the
cursor down the rows, `Enter` goes, `PgUp` / `PgDn` scroll a long page, and the mouse
does all of it too:

- **DRIVE** - free drive on a map (the list holds exactly the maps there are: one, the
  Factory test pad, which is this scene - free drive simply closes the door; `R` puts
  the car back on the start line), the five handling tests with their objective, gold
  time and your stored best, the L0 licence sitting and the skid pad exam. Every row
  starts its run through the mission manager's or the licence manager's own start path
  (`start_mission`, `start_l0_sitting`, `start_skid_pad_test`): nothing is duplicated,
  and a run started here is the same run the keys start.
- **THE STUDY** - the driving school's lessons, see [The study](#the-study).
- **CAR** - the car's condition as it stands: the odometer, the tank, the battery's
  charge and health, the wear of every component as a bar (clutch, front and rear
  brakes, front and rear tyres, engine: each its share of its life used, under 1 % as
  new to the physics), the dashboard (aids, program, automatic or manual, camera view)
  and the licence held - the same fields the store keeps per car (`Garage.condition_text`
  reads a store-shaped entry: the live car's, or a file's, which is what the menu test
  reads it from), and where the car's file is kept this run. Read-only.
- **LICENCE** - the licence held, the rank it is (`TEST DRIVER` from L1; the ranks
  beyond are named as not yet playable), every pass recorded, the L0 sitting's checklist
  (`Theory: PASSED` or `Theory: —`, then each practical element `[PASSED]` or `[ - ]`,
  in the sitting's order, from the record), what the next level still takes, and the
  licence book's own text under it - the same book `L` opens.
- **SETTINGS** - the data folder (see [Data location](#data-location): where it is this
  run and why, the folder chosen, a native folder dialog to choose another, a row to go
  back to the default), the HUD bar legend (every bar and lamp on the HUD, on the
  study's input display and on the CAR page, with the temperatures and shares their
  colours turn at: `HUD.bar_legend`), and the controls.

The garage reads and never writes: the one thing it changes is the bootstrap file when
a folder is chosen. Nothing of it runs in the headless suite unless the test opens it.

Every page fits the 1280 x 720 screen: a row's hint wraps to the frame's width and a
page taller than the frame (THE STUDY's list, the SETTINGS legend) scrolls, `Down` and
`PgDn` reaching every row and line; the licence book, the lesson caption, the mission
line and the banners fit the screen too (a long banner headline in smaller letters,
never under 40 px), and the menu test fails on anything drawn past the screen's edge.

### The study

The heart of the garage: a driving school where the scripted driver drives the real car
in front of you with every input on show (`scripts/study.gd`, the lessons as data in
`scripts/study_lessons.gd`). Optional, any lesson any time nothing else is running, as
often as you like; nothing is judged, recorded or unlocked by a lesson. Pick one on THE
STUDY page: the door closes, the driver takes the wheel, and the input display comes up
bottom left - the steering wheel as a marker on a bar (the left end full left lock, the
right end full right), the throttle, brake and clutch pedals as three pedal bars, the
gear and the program (or `manual`), the engine (`running`, `STALLED`, `CRANKING`), the
handbrake, the clutch pedal's depth, the three aids, a wear readout, and the caption of
the step the driver is on ("Off the throttle, full left lock and the handbrake together:
the locked rears let the tail step out."). Events flash over it as they happen: `STALL`,
`RUNNING AGAIN`, `WHEEL SPIN` (an axle over 0.35 slip, where a tyre lays rubber),
`WHEELS LOCKED`, `OVERHEAT`, `BRAKE FADE`, `TYRES HOT`, an aid switched (`TCS OFF`),
`SHIFT G2`, `REVERSE`. `Esc` (or `R`) ends a lesson early; a `LESSON OVER` banner ends
one that ran out, and `Tab` takes you back to the list to watch it again.

The handling tests' and the exam elements' definitions **are** lesson scripts: a
walkthrough of the 180 spin is the certified 180 driven in front of you by its own
scripted driver, the very dictionary `HandlingTests.spin_180_test()` returns, with a
caption overlay keyed to its steps and nothing copied or changed - a change to a test is
a change to its lesson. The lessons that had no pilot got one written in the same
tests-as-data idiom (`LicenceExams.KIND_LESSON`: a scripted drive on the exam runner
with nothing to judge, whose steps carry a `say` line each), every one probed headless
and its captions written from what was measured. The catalogue:

| Group | Lesson | Pilot |
| --- | --- | --- |
| BASICS | Steering | the study's own: at a walk, full left lock held, let go (the caster brings it back, slowly at a walk), full right, let go, stop (what is left on the wheel stays there) |
| | Manual gear changes | the study's own: 1st to 3rd at the shift light (14.8 and 26.0 m/s), off the throttle, on the brake, down into 2nd at 14 m/s, stop |
| | Stall and recovery | the study's own: manual, the clutch let up as the throttle goes down (the smoke test's stall), clutch down, starter, revs up, clutch, away |
| | Drive modes: sport, comfort, eco | the study's own: full throttle to 72 km/h in each program, `N` between them (sport changes up at 6800 rpm, comfort at ~2800, eco at ~1800 - 2000) |
| | How tyres wear | the study's own: the wear test's donut for 22 s, TCS and SC off (the rears at 116 C and 58 ppm of wear at the end) |
| AIDS ON AND OFF | TCS on / off | the study's own: the same launch twice, `T` between them (the rears held under 0.25 slip, then spinning at 2.6) |
| | ABS on / off | the study's own: the same full stop from 80 km/h twice, `G` between them (the fronts held at 0.15 slip, then locked at -1.0) |
| | SC on / off | the study's own: the same flick of lock and handbrake at 60 km/h twice, `K` between them (79 degrees and straight again; 153 degrees and backwards) |
| MANOEUVRES | Slalom | `SLALOM_TEST`'s driver |
| | Parallel parking, Bay parking, Hill start, Three-point turn, Reversing a lane, Emergency stop, Skid pad circle | the L0 elements' and the skid pad test's drivers |
| | Donuts | the study's own: TCS and SC off, full lock and full throttle from rest for 9 s (698 degrees round) |
| | Drifting | **coming soon**: a held powerslide with countersteer needs a pilot that reads the slide tick by tick; the on / off keys of the idiom are not enough yet |
| | Quick turn | **coming soon**: which manoeuvre it is (an evasive swerve, a U-turn under power) is not settled, so there is no honest demonstration to give |
| TEST WALKTHROUGHS | 180 spin, 360 spin, Stop box, Reverse 180: the J-turn | `SPIN_180`, `SPIN_360`, `STOP_BOX`, `REVERSE_180`'s drivers, captioned step by step |
| THE WORLD | Traffic rules, Traffic lights | **coming soon**: need the roads, junctions and traffic of the 4C world |

The instructor's car: for the length of a lesson the licence gate is taken off the car
(`ArcadeCar.licence_gate = null`, everything allowed, as in a sitting - the stall and
hill start lessons need the clutch key, the aid lessons the switches), the dashboard is
set to what the lesson wants (the aids on, sport, automatic, then the lesson's own
`dashboard`: the donuts and tyre-wear lessons switch TCS and SC off), the licence
manager's keys stand down and the mission keys are held. When the lesson ends, by
itself or on `Esc` or `R`, all of it goes back as it was - the gate, the switches, the
program and its driver, automatic or manual - and every key the driver may have pressed
is released. The car stays where the driver left it, and the tank, the heat and the wear
are whatever the lesson's drive made of them: a handling test's walkthrough starts on the
fresh car as a mission does (its start hands out the full tank and new components), an
exam element's or a study pilot's does not. Hands off the keys while the driver drives:
the keys still reach the car, and a key of yours over the driver's is a different drive.
Nothing is recorded from a lesson in the mission summary (no run starts through the
mission manager), and the free-driving telemetry file simply records what the car did.

### Data location

Everything the game keeps - the car's file `cars.json` (odometer, fuel, dashboard,
battery, wear, licence: see [Odometer](#odometer)), the telemetry under `telemetry/`
(see [Telemetry](#telemetry)) and whatever saves come later - lives in one data folder,
and every one of them still names its files under `user://`: `scripts/data_dir.gd`
says where `user://` really is for this run and resolves each path as it is read or
written (`DataDir.resolve`), nothing else touches a path. The folder is settled once
at startup, before the car reads its store, by the `DataBootstrap` autoload
(`scripts/data_bootstrap.gd`), from two places, the first that says anything winning:

1. the environment variable `FD_DATA_DIR` - an absolute folder;
2. the bootstrap file `user://data_dir.txt` in the default location, one line, an
   absolute folder - what the garage's SETTINGS page writes when a folder is chosen
   there ("Use the default folder" removes it).

Neither set, the default: `user://` itself, which since this iteration is a folder of
the game's own, `factory-driver` under the OS's data dir (`use_custom_user_dir` in
`project.godot`: `~/Library/Application Support/factory-driver` on macOS,
`~/.local/share/factory-driver` on Linux, `%APPDATA%\factory-driver` on Windows),
instead of Godot's generic `Godot/app_userdata/Factory Driver`. A value that is no
absolute folder (a relative path, a `res://` or `user://` path) is reported in the log
and the default is used, never a guess. A folder chosen in the settings takes effect at
the next start: the run that chose it keeps the folder it read. A custom folder is used
*as* the data folder: `cars.json` and `telemetry/` go straight into it.

**The first run in a folder copies.** A data folder without the marker file
`.factory-driver-data` is new to the game and is seeded once, in the running game only,
with a **copy** of what the previous location holds: the default `factory-driver` folder
when a custom folder is used, or the pre-4A Godot default
(`<OS data dir>/Godot/app_userdata/Factory Driver`, where everything was kept before this
iteration) - the first of the two that holds any data. `cars.json` and the whole of
`telemetry/` are copied file by file, never over a file the new folder already has, and
nothing in the old location is moved or deleted: it is left exactly as it was, a backup.
The marker is then written (its text says where the seed came from) and the folder is
never seeded again, whatever the old location holds later. So the first start after
this iteration finds your odometer, fuel, licence and telemetry where they always were,
copied into the new folder, and the SETTINGS page says so. All of it sits behind the
store's own switch (`OdometerStore.enabled`, the telemetry's `should_record`): the
headless suite resolves the folder the same way but seeds nothing and writes nothing;
its own checks run the seed on folders of the test's own.

### Telemetry

Every drive is written down. `scripts/telemetry.gd` (a `TelemetryRecorder` the mission
manager makes in `_ready`) reads the car once every few physics ticks and writes one
JSON object per line - JSON-lines, `.jsonl` - to

```
user://telemetry/<YYYY-MM-DD>/<session>_<HHMMSS>_<context>.jsonl   e.g. 0007_103245_free.jsonl
user://telemetry/index.json
```

(`user://` is the game's data folder, see [Data location](#data-location); the paths are
resolved through it as they are opened.)

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
| `throttle`, `brake`, `handbrake`, `steer` | the two pedals 0..1 as the driver's feet have them (`throttle_pedal` / `brake_pedal`: in reverse the throttle is the brake key's pedal), the handbrake key, steering as a share of full lock, -1 (right) .. +1 (left) |
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

`C` cycles the one camera (`scripts/chase_camera.gd`) through chase, cockpit
(driver's eye, with a dashboard and steering wheel silhouette), front (on the bonnet),
overhead (straight down, north always up so the pad holds still; rises with speed) and
wheel (low by the front-left tyre, looking back at it: watch it steer, spin, lock under
braking, work up and down over the bumps and the tarmac run under its contact patch). It works at any time, including
during a test. Every offset, height and field of view is a commented constant in the
`Modes` block of that file.

It comes up in the view the car was last driven in, and a car that has not been driven
yet comes up in the cockpit, inside it: the view is the driver's, kept per car with the
rest of the dashboard (see The car's own file). The car holds it and the store keeps it;
the camera reads it once when it comes up and hands back every view `C` lands on - and
only those, since the look-back view is held, not chosen.

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

### Tyre marks

A tyre working beyond its grip leaves its rubber on the tarmac (`scripts/tyre_marks.gd`,
the `TyreMarks` node in `scenes/main.tscn`). Every physics tick the marks read the car's
slip state, per axle, and a wheel past a slip ratio of 0.35 or a slip angle of 0.3 rad
(17 degrees, three times the tyres' peak) trails marks. That is over everything the car's
aids hold a tyre at (TCS 0.25, ABS 0.15), so a launch with TCS and a full pedal with ABS
leave nothing; pull the handbrake at speed and all four wheels draw the slide, switch TCS
off (`T`) and launch and the rears lay two black lines for as long as they spin, switch
ABS off (`G`) and stand on the brake and the locked fronts draw the stop. Cornering on
tyres that grip leaves nothing: half lock at any speed, full lock off the throttle up to
~35 km/h. (The slip angle threshold was 0.2 rad, and full lock from 26 km/h marked: too
easily, was the verdict from the driving seat.)

How dark a mark is goes by how far past its grip the tyre was (`mark_severity`, from the
slip state alone): 0 at the thresholds, 1 at a slip ratio of 1 either way (a locked wheel
is at -1, the rears of a launch without TCS at 2.8) or a slip angle of 1 rad, in a line
in between, the worse of the two; a mark takes the worst tick of the half metre it
covers. A fresh mark's alpha runs from 0.15 to 0.75 with it. So fronts ploughing round a
tight corner at 45 km/h leave a shade (alpha ~0.2), full lock at motorway speed a grey
(~0.35), and a locked or spinning tyre a black line.

A mark is a quad a tyre wide (0.22 m) lying on the ground from where the wheel's contact
patch was to where it is now, laid every 0.5 m of the patch's way over the ground - the
way it went, not the way the wheel points, and as long as it went, whatever the wheel's
own speed is (0 locked, three times the car's spinning). The contact point is the one the
suspension looks the road up at; the height is the ground the pad shows (the road's
elevation: the micro-bumps the wheels ride are not in the ground mesh, and a mark laid on
them would dip under it), just over the paint.

The marks fade to nothing over 30 s of physics time, each from its own shade, and live in a pool of 1024 (512 m of
one wheel's trail); when it is full the oldest mark is laid anew. One `MultiMesh` of
quads draws them, colour and alpha per mark, no node per mark; the severities are one
more plain array beside the ages. All of it is plain data
worked out from the car's state on physics ticks, no wall clock and no random numbers:
the same drive leaves the same marks and the same shades, to the bit. Purely visual - the marks read the car
and nothing reads the marks; the only thing the car got for them is a `reset_counter`
that `reset_to` counts up and nothing in the car reads.

A reset **clears** the marks (`R`, a test or mission starting, anything that goes
through `reset_to` / `reset_to_spawn`): the pad is as it was before the drive. Every
threshold, size and time is a commented constant at the top of the script.

### Odometer

The car counts its metres (`odometer_m` on the car, `ODO 12.3 km` over the aid lamps on
the HUD): every physics tick the way its body got over the ground, level, whichever way -
forwards, backwards, sideways in a slide; the body's own way, not the wheels' turning.
It is never reset. `R`, a test starting, anything through `reset_to` puts the car
somewhere, and that jump is not driven: the place the odometer counts from moves along
with the car, the metres stay. A way that is not a finite number is not counted. It is
bookkeeping, a plain add at the end of the tick: nothing in the car reads it, and the
HUD only makes its text anew when the shown tenth of a kilometre changes.

Between sessions the metres live in `user://cars.json` (`scripts/odometer_store.gd`; in
the data folder, see [Data location](#data-location)), an entry per car so the garage
can add its own:

```json
{"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4}}}
```

The car reads its entry when it enters the scene and continues from it (no file, no
entry: 0), writes it every 45 s of physics time and once more when it leaves the scene
tree; a save touches that one number and writes back whatever else the file holds. All
of it sits behind the telemetry's own switch (`TelemetryRecorder.should_record`): on in
the running game, off with no window - the headless test suite reads and writes nothing,
its cars all start at 0 - unless `FD_TELEMETRY=1` asks for it.

The fuel in the tank lives in the same entry (`fuel_l`, litres, full precision), read and
written with the odometer, behind the same switch:

```json
{"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5}}}
```

It is the user's car: driven half empty one day, it is half empty the next - a car left
at 8 % starts at 8 %, the bar red. The level is read once, when the car enters the scene,
before it is stood on its springs (the fuel is weight); no entry is a new car, a full
tank; a `fuel_l` that is no level of this tank (not a number, not finite, under 0, over
the tank) is an error in the log and a full tank. Nothing in the game refuels the car:
`reset_to` (`R`) keeps the tank as it finds it - resetting is not refuelling; a gas
station or a canister will, both world content to come - and tells the file nothing; the
next save on the 45 s cadence writes the tank as it then stands. The headless suite and
the certified handling runs read nothing: every car there starts on the config's full
tank, and every handling run's start hands its car the full tank by hand before its
`reset_to`.

The dashboard lives in the same entry too, under `driver`: the three aid switches
(`tcs_on`, `abs_on`, `sc_on`), the gearbox program by name (`sport`, `comfort` or `eco`),
automatic or manual (`automatic`) and the camera view the driver was looking through
(`camera_view`, 0 chase, 1 cockpit, 2 front, 3 overhead, 4 wheel - the held look-back
view is never one a car is left in). Read once when the car enters the scene, written
with the odometer and the fuel in the same save:

```json
{"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5,
  "driver": {"tcs_on": true, "abs_on": true, "sc_on": true,
    "gearbox_mode": "sport", "automatic": true, "camera_view": 1}}}}
```

These belong to the car, not to the session: whoever drives next starts where the last
driver left it - the aids as they were switched, the program that was selected (its own
driver in the seat with it), manual if it was left in manual, and the same view. A car
that has not been driven yet gets the defaults: every aid on, sport, automatic, and the
cockpit view, inside the car. A setting in the file that is none of its own (a switch
that is not true or false, a program this gearbox has not got, a view outside 0 .. 4) is
an error in the log and that one default; the rest still load. A reset (`R`) still puts
the gearbox back in automatic, as it always did, and leaves the switches and the view
alone - it is the driver who has them. Nothing of this reaches the headless suite or the
certified runs: the store is off there and every car starts on the defaults.

The battery lives in the same entry too, under `battery`: how full (`charge`, 0..1 of
what it held new) and how worn (`capacity_wear`, the share of that lost for good), read
once when the car enters the scene, written with the rest in the same save:

```json
{"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5,
  "driver": {"tcs_on": true, "abs_on": true, "sc_on": true,
    "gearbox_mode": "sport", "automatic": true, "camera_view": 1},
  "battery": {"charge": 0.93, "capacity_wear": 0.0}}}}
```

A battery left flat is flat the next day, and its starter turns nothing until a reset;
what a deep discharge took off its capacity stays taken. No entry is a new car, full and
healthy; a number that is no share of a battery (not a number, not finite, under 0, over
1) is an error in the log and that one default, the other still loads; a charge saved
fuller than its wear leaves is trimmed to what the battery can hold. A reset (`R`, a test
starting) is a fresh battery - full and healthy, the one thing besides the gearbox that a
reset makes new - and tells the file nothing: the next save on the 45 s cadence writes
the battery as it then stands.
The headless suite and the certified runs read nothing: every car there starts full and
healthy.

The wear lives in the same entry too, under `wear`: the six shares of a component's life
used up (`clutch`, `brakes_front`, `brakes_rear`, `tyres_front`, `tyres_rear`, `engine`,
each 0..1; see Wear and aging), read once when the car enters the scene, written with
the rest in the same save:

```json
{"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5,
  "driver": {"tcs_on": true, "abs_on": true, "sc_on": true,
    "gearbox_mode": "sport", "automatic": true, "camera_view": 1},
  "battery": {"charge": 0.93, "capacity_wear": 0.0},
  "wear": {"clutch": 0.012, "brakes_front": 0.03, "brakes_rear": 0.02,
    "tyres_front": 0.05, "tyres_rear": 0.08, "engine": 0.004}}}}
```

What a car has worn out is worn out the next day too. No entry is a new car, nothing
worn; a number that is no share of a life (not a number, not finite, under 0, over 1) is
an error in the log and that one default, the other five still load. A reset (`R`)
leaves the wear where it is - R does not un-wear, as it does not refuel - and tells the
file nothing: the next save on the 45 s cadence writes the wear as it then stands. The file's
version stays 1: an entry written before there was wear has no `wear` object, reads as
a new car's, and is written back with everything else it holds. The headless suite and
the certified runs read nothing: every car there starts new.

The licence lives in the same entry too, under `licence` (see
[Licence ladder](#licence-ladder)): the level held (`level`: -1 none, 0 L0, 1 L1), the
exams passed at this car's wheel (`passed`: the L0 sitting, the skid pad, the five
handling tests by name) and the L0 sitting's elements passed (`elements`: the seven
element names, each kept from the moment it is passed - the sitting resumes at the
first missing one). The level is always what the record earns: L0 with all seven
elements, or with the L0 sitting in `passed` (a record written before there were
elements keeps its licence); a licence object without `elements` reads as none passed
yet, nothing reported, and the file's version stays 1. The licence manager, not the
car, reads it once when the scene comes up and writes it on every pass, its own save;
the car's saves write the entry's other fields round it:

```json
{"version": 1, "cars": {"boxster_986": {"odometer_m": 123.4, "fuel_l": 31.5,
  "driver": {"tcs_on": true, "abs_on": true, "sc_on": true,
    "gearbox_mode": "sport", "automatic": true, "camera_view": 1},
  "battery": {"charge": 0.93, "capacity_wear": 0.0},
  "wear": {"clutch": 0.012, "brakes_front": 0.03, "brakes_rear": 0.02,
    "tyres_front": 0.05, "tyres_rear": 0.08, "engine": 0.004},
  "licence": {"level": 0, "passed": ["L0_CITIZEN", "SLALOM_TEST"],
    "elements": ["THEORY_QUIZ", "PARALLEL_PARK", "BAY_PARK", "HILL_START",
      "TURN_IN_ROAD", "REVERSING_COURSE", "EMERGENCY_STOP"]}}}}
```

Per car, riding this file, because this store is the one per-car ledger there is: the
garage of 4A reads the entry as one thing, the car and who may drive it how. The passes
are the record; the level is written from them and read back from them (a level in the
file that says more than the passes earn is not believed), a convenience for a reader
without the exam data. No entry is an unlicensed driver; a level that is no whole number
in -1 .. 1, or a `passed` that is no list of names, is an error in the log and that one
default, the other still loads. The version stays 1: an entry written before there were
licences has no `licence` object, reads as unlicensed, and is written back with
everything else it holds. The headless suite writes nothing: every driver there starts
unlicensed, and the tests that need the switches and the clutch are granted L0 through
the manager's record.
