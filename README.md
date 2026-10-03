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
The game starts windowed (`display/window/size/mode` 0 in `project.godot`; was 4, exclusive
fullscreen, the minimap iteration's approved extra, 2026-09-23; REVISION 2026-09-24: the driver
remote-desktops into the dev machine, which fights exclusive fullscreen - the default is windowed
again, fullscreen stays available: set the mode to 4, nothing was removed).

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
| Reset the car: on the pad to the start line; on a world map (the Ring) to the last place all four wheels were supported on the road, heading along it, the velocity zeroed - the fuel, the heat and the wear kept, nothing else touched (was the start line everywhere, 2026-09-24) | `R` |
| Flip an overturned car back on to its wheels (only overturned, and at rest) | `F` |
| Cycle camera: cockpit, front, overhead, wheel, chase (it starts where the car was left) | `C` |
| Look back (hold)                        | `B`             |
| Look left / right (hold)                | `,` / `.`       |
| X-ray view on / off                     | `X`             |
| Start handling test 1 - 5 (mission mode) | `1` - `5`      |
| Abort the running test / close its result | `Esc` (`R` also aborts) |
| Licence book open / close (`1` sits the L0 exam, `2` the skid pad test while it is open; digits answer the theory) | `L` |
| Garage open / close: the pause menu - drive, the study, car, licence, settings (`Esc` also opens it when nothing at all is running, and closes it); inside: `Left` / `Right` tabs, `Up` / `Down` rows, `Enter` go, `PgUp` / `PgDn` scroll, or the mouse | `Tab` |
| Flag an issue: press to start a session (the HUD says `ISSUE issue-0007 recording`), drive to show the problem, press again to stop; a box then asks what is wrong, the game paused while you type - `Enter` files it, `Esc` files it as typed so far (and opens the garage, as `Esc` does with nothing running). See [The issue flag](#the-issue-flag) | `V` |
| GPS minimap on / off (top right, on by default): ~500 m around the car heading-up, the roads at their widths, the car's arrow, and the road ahead ~400 m coloured by the bend's sharpness (green gentle, amber medium, red sharp) with the road's name and the next name along it; the pad has no map data and says so | `P` |

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

### The physics bubble

The canon (decisions.org 5BE9FBA3, the driver's ruling of 2026-09-26): *"because the Cat
Matrix Car Sim game is an open world, we want everything around the player to have
interaction, simulating the physics which gives the feel of the car... if a driver is not
near the element, the element doesn't get a collision box, if a driver comes near it gets a
collision box, making sure to deactivate the ones that are less likely to be hit because
the driver drove away. It's like creating the physics bubble where a car is."* The open
world is interactive through a proximity-activated physics bubble travelling with the car:
elements carry no permanent collision, inside the bubble collision is active, driven-away
elements are deactivated; the mechanism is the standing one for all world interaction -
the trees are its first consumer (BUBBLE-1), the buildings and the furniture follow (4B-8).

**The trunks.** `scripts/forest_walls.gd` gives every tree a trunk prism - six vertical
faces (12 triangles) around the tree's point from its foot (the field less 0.2 m, the read
`tree_transform` makes) to the crown base, the archetype's bark surface's top at the tree's
scale (V2 12.4 m, V1 7.0 m, V6 4.5 m at archetype scale), its radius the bark surface's
widest horizontal extent measured from the imported .glb (V2 0.32 m, V1 0.35 m, V6 0.25 m
held to the 0.30-0.45 band) times the tree's scale. The prisms of one tree chunk (1 km) are
ONE `StaticBody3D` ("Trunks_x_z", a sibling of the chunk's meshes) with ONE
`CollisionShape3D` holding ONE `ConcavePolygonShape3D` of every trunk's faces in tree
order, back faces solid (a closed hull the car is always outside of): 42 bodies for the
trunks (19 379 since FOREST-2 moved the edge trees; was 19 339), never a node per tree; a
wall card is a picture and gets nothing. The meshes, the
placement, the lists and the counts are byte-equal to before (the dressing test's
accounting holds it); `describe()` gained "19 339 trunk prisms in 42 bodies" (19 379 since
FOREST-2). Was -> the
forest was visuals only: no collision shape, no body, no Area3D under it.

**The bubble.** `scripts/physics_bubble.gd` (`PhysicsBubble`, the "Bubble" child Forest
builds in `_build_colliders`; the scene file is untouched - Forest takes the car from the
road's export) is fed the bodies, each body's horizontal box (the chunk's trunks' extent,
the radius included) and the car, and steps every physics tick before the road's floor
follower and the car (`process_physics_priority` -2, so a body switched on this tick is
solid to the car this tick): a body whose box is within `ACTIVATE_M` 80 m of the car goes
ACTIVE - `collision_layer` 1, the car's mask (`scripts/car.gd` is frozen at the
`CharacterBody3D` default, mask 1; the trunks stand on the one layer the car meets, beside
the road's follower floor slab; the road's own strips keep layer 2 and never meet the car)
- and a body whose box is past `DEACTIVATE_M` 110 m goes INACTIVE, `collision_layer` 0 (on
no layer a body pairs with nothing). A layer write, never a shape toggle
(`CollisionShape3D.disabled` removes and re-adds the shape from the broadphase; the layer
is one integer on a body that stays where it is). Between the radii a body keeps its
state: the hysteresis band, so a car idling at one radius never flickers a body on and
off. The distance is to the body's BOX, not its centre: a chunk is 1 km across, so a trunk
20 m from the car can stand 500 m from its chunk's centre; the box distance is 0 inside
the chunk and the gap to its nearest edge outside, so every trunk within 80 m of the car
is under an active body. Cost: one pass over 42 bodies a tick (squared distances against
squared radii, a write only on a change), never over the ~19 000 elements, no allocation
after the build, no RNG, no wall clock; the state after a tick is a function of the car's
position and the state before, outside the band of the position alone - after any jump
(`reset_to`, the reset test's teleport) the bubble around the new position is right at
the next tick. The radii: at the ring drive's cruise (18 m/s; 30 m/s on the straights)
the sim stops from 30 m/s in under 50 m, so a body switched on 80 m out is solid long
before the car can reach a trunk under it; the fog's 100-300 m band is what the chase
camera sees, so the bubble sits inside the driver's view; the 30 m band is sixty ticks'
way at 30 m/s and more, so a body is toggled once per approach and never twice for a
tick's jitter. The car is stopped by an active trunk the way it is carried by the floor
slab: it reads its velocity back after `move_and_slide`, no car change (measured in
`tests/bubble_test.gd`: 17.67 m/s into a 0.34 m spruce, held at the box's nose, a 7.5 mm
variation over two seconds of floored throttle). A forest built without a road or a car
(a fixture) stands its bodies on no layer and leaves them there.

### Surfaces, the off-road feel and the continuation

OFFROAD-1, the driver's two findings: off the road the car felt *"like going through
water"* (no surface grip model, no micro-profile: the raw 10 m lattice with road grip
everywhere), and the terrain read snow-covered green (*"the roads are different, but it's
hard to see them as they are covered like it has snowed with green texture on them"*). The
canon: decisions.org DAF72FC6 (OPEN-WORLD CONTINUITY: everything reachable, no walls, the
world continues procedurally beyond the OSM data, deterministic hash randomness via
`hash_unit()`, never RNG), plan.org ECD301C4 (SURFACES & GRIP DEPTH: grip varies by surface
type and condition, suspension/tire feel), the driver's rule that everything is
parameterised from the start, and `docs/art-direction.md` for the colours.

**The terrain's colour space.** Godot reads a mesh's VERTEX colours as linear albedo as they
are (`BaseMaterial3D.vertex_color_is_srgb` is off by default; a colour texture is converted
from sRGB on import, a vertex colour never is), and the palette's tints in
`data/regions/eifel_ring/dressing.json` are display colours. Read as linear, T1's
(0.36, 0.44, 0.24) - display luminance 0.41 - was an albedo of display value ~(0.63, 0.70,
0.53): the visual probe's lit T1 hillside (the Karussell shot, a lattice slope of 14 % at
NdotL 0.605 to the 45° sun, the restrained ambient 0.45 × 0.85 + 0.15 of the sky, Filmic,
sRGB) measured (191, 202, 163), display luminance 0.77 - the snow. `TerrainBuilder.albedo()`
converts a tint once (`Color.srgb_to_linear`) at the vertex writer, the stored vertex
colour the linear value; the forest's `tint()` reads stay raw (`scripts/forest_walls.gd`,
frozen: its tints multiply an sRGB-converted texture and were measured to the canon as they
are - converted too, the wall cards went from (46, 62, 52) to (10, 23, 15) in the probe,
black). Beside the conversion the nine terrain tints were re-authored down (T1 (0.36, 0.44,
0.24) -> (0.28, 0.35, 0.19), the others in the table's note) so the lit terrain lands in
display luminance 0.30-0.45: the same box now reads (98, 117, 77), luminance 0.43, muted
olive; the walls unchanged; the road ribbon brighter than everything beside it.

**The surfaces.** `data/regions/eifel_ring/surfaces.json` names the region's surfaces as
data: a grip multiplier on the axle's tyre grip, a rolling drag [m/s²] and a bump amplitude
[m] - road {1.0, 0.0, 0.0} exactly (the certified baseline), gravel {0.62, 1.6, 0.035},
grass {0.55, 0.9, 0.02}, field stubble {0.7, 1.0, 0.025}, forest floor {0.48, 1.2, 0.05},
each with its note, and the shoulder rule (1.5 m beyond the paved edge is gravel);
`Surfaces.validate()` holds the schema and the bounds (grip in [0.2, 1.0], drag and bump
non-negative, the road exact). `scripts/surfaces.gd` (the `Surfaces` node, a scene-root
sibling after Road at physics priority -1) classifies each wheel's contact point every
tick - the road on its paved width, gravel within the shoulder, else
`TerrainBuilder.surface_at`'s ground: forest floor under the V7 canopy, field stubble on a
T7 field, grass everywhere else and outside the coverage - and writes the car's three
surface inputs: the Conductor's narrow grant (decisions.org 5B7CD993) added
`front_surface_grip`, `rear_surface_grip` and `surface_rolling_decel` to `scripts/car.gd`
(three public vars, three consumption points: each axle's grip multiplied, the rolling drag
`COAST_DECEL + surface_rolling_decel`; nothing else moved). Per-axle honesty: the front pair
and the rear pair are classified on their own (an axle's factor the mean of its two wheels).
On the road all three read 1.0 / 1.0 / 0.0 and the certified drives are byte-identical.
The brakes need no hook: brake force is delivered through the grip budget.

**The wrapper and the micro-profile.** `scripts/ring_profile.gd` (`RingProfile`, a
`WorldRoadProfile`) wraps the real profile as `inner` and delegates every public member
to it verbatim; the Surfaces node swaps it into `road.profile` and `car.road_profile` at
its first physics tick, after every `_ready` consumed the original (Terrain and Forest keep
the smooth field; the ring drive test's pin `road.profile is WorldRoadProfile and
car.road_profile == road.profile` holds: a subclass, one object). On a road or in its blend
band the three height reads pass through the inner BIT-EXACT (the wrapper asks
`inner.describe()` once and returns its own `height`); off-road inside the coverage they
add the micro-profile - deterministic value noise on `hash_unit` at 2.5 m and 0.9 m
wavelengths, the amplitude the ground surface's `bump`, weighed in from zero at the
widest road's reach over 20 m of the terrain's distance field and faded to zero at the
coverage box's edge - the car's read only, through its existing per-wheel
`sample_height` path (the terrain mesh does not show it: the seam, stated in the header);
outside the coverage they answer the continuation. Measured on the fence's grass drive:
the pinned throttle launches at a peak 2.71 m/s² against the road's 6.87, 11.7 m/s at
tick 300 against 22.7; the wheels' travel-rate variance 0.0021 (m/s)² against 0.0002 with
the bumps zeroed.

**The continuation.** `scripts/world_continuation.gd` (`WorldContinuation`, static,
stateless): outside the drape's coverage box (x 0..7000, z -6000..0; the frozen profile
answers a flat 0 there) the height is the real field's value at the nearest point of the
box's edge plus fBm value noise - five octaves at 2 048 / 1 024 / 512 / 256 / 128 m with
amplitudes 175 / 38 / 31 / 27 / 15.5 m FITTED to the lattice's measured relief (the rms
height difference at lag L over the 701 × 601 lattice: 90.7 m at 2 048 m, 58.8 at 1 024,
40.0 at 512, 26.9 at 256, 16.2 at 128, 9.1 at 64; height std 67.4 m; the model 88.8 /
63.7 / 41.0 / 26.3 / 16.3 / 9.0 at the same lags) - weighed in over an 800 m blend band
from the edge, reaching 6 km out (twice the haze's sky-coloured distance; NOT infinite,
the honest limit) and faded to flat 0 over its last kilometre. Every corner hash is
`hash_unit` on the cell's indices folded into a spatial mix (FNV-1a's last byte only
reaches the hash through one multiply, so adjacent cells keyed on a trailing index hashed
one prime apart and the noise barely varied along z: measured, fixed). The terrain draws
it: four bands of 50 m quads (120 000 cells, 121 484 vertices) from the box's edge to the
margin, every vertex the same static function the car reads, tinted T9, a 6 m skirt
hanging along the box's edge (`describe()` gained "120000 continuation cells to 6000 m
(520 skirts)"; the build about a second longer). At the edge the field is continuous to
under 1 cm (measured 7 mm worst over 484 points, 1 cm either side).

**What moved, honestly.** The certified ring drives, the licence certs and the reset test
are byte-identical to before (on-road reads pass through the inner; the three car inputs
read 1.0 / 1.0 / 0.0 on the pavement). `tests/bubble_test.gd` still passes all 17 checks,
but its tree stop is an off-road approach by design - the car leaves the straight across
the shoulder and the forest floor to hit a spruce 11.5 m out - so it now arrives at tick
239 at 16.09 m/s (was tick 235 at 17.67 m/s, the figures *The physics bubble* above
records from BUBBLE-1; since FOREST-2's re-picked tree one slot further along: tick 264 at
16.57 m/s from 44.4 m out), is in contact 63 of its 359 ticks (was 112 of 355), slides 0.242 m
along the trunk (was 0.192 m), and its control passes the tree in 267 ticks (was 259); the
held distance 2.438 m, the never-past rule and the radii's events are unchanged. The
bubble test's census line reads five nodes more (the four continuation bands and the
Surfaces node).

### The forest edge (FOREST-2)

The driver's three demands of 2026-09-26 (plan.org): the V4 forest-wall cards read "like a
green wall, covering the whole tree forest" (no sky cut through, no gaps between the trees,
the forest never seen through near its edge; the wall must fill the gaps BEHIND the
archetype trees, not stand in front of them); "trees must be distributed more natural,
these ones are an unnatural row"; and the wall ends must be feathered, not vertical
cut-offs. Two root causes, both measured, both mended in `scripts/forest_walls.gd` and
`assets/blender/scripts/foliage.py` and nowhere else.

**The recipe was one skyline.** `_card_quad` mapped every card to the FULL u wrap of the
512² wall texture (u0 the card's hash, u1 = u0 + 1), so every card showed the same skyline
phase-turned; and the texture itself was a rolling canopy band with small holes near its
top (opaque over 0.764 of the tile, the bottom 291 rows solid, the skyline within 0.14-0.29
of the height, std 0.032, not one column gap - a hedge). Now (the constants at the head of
`forest_walls.gd`, THE CARD RECIPE): a card shows a hashed SLICE of u, 0.14-0.30 of the
texture for an 8 m card (`CARD_U_WINDOW` 0.22 ± `CARD_U_WINDOW_JITTER` / 2, scaled by the
card's width so a tree column keeps its world width on a short or stretched card), the
mirror hash as before; its v-window is [top, 1] with the top in its layer's band
(`CARD_V_TOP`: the front at most 0.05 - no column of the texture reaches over 0.05 from the
top, so the front never cuts a crown; the middle 0.03-0.08, the back 0.06-0.14, a step
lower for the depth under their darker tints); a hashed fifth of the slots draw no card in
any layer (`CARD_GAP_RATE` 0.2, the demand's 15-25 %; measured 6 154 of 30 777 slots,
20.0 %) so the forest shows through; and where a layer's run of cards ends - the slot
before one the 60 m rule refuses or an edge skipped as far from any road; a ring's edges
are one closed sequence, so a polygon corner is no end, and a gap is a window, not an end
- the last two slots taper (`FEATHER_SLOTS`), the terminal card to a hashed 0.5-0.7 of its
stone height (`FEATHER_END_MIN` / `_MAX`) and wearing the texture's thinning band
(`FEATHER_U_BAND` u 0.70-0.86, three short narrow columns set apart), the slot before at
the ramp's midpoint: the wall sinks and thins out (measured 1 967 feathered cards, 1 016
terminal). Not a v-shift for the ends: showing the texture's interior at a card's top puts
a straight cut through the canopy, the chop itself. The texture (`foliage.py`
`wall_columns` / `wall_alpha` / `wall_grey`) is now a row of 16 individual spruce columns
of varied height and width - a jagged skyline (the first opaque row per column 0.05-0.89 of
the height, std 0.166), daylight between the tips running down to where the neighbours'
crowns meet and to the crown bases where a short column stands between tall ones (22
column gaps with sky below 60 % of the height), holes through the crowns' outer parts, dark
trunks up the gaps, a solid undergrowth band at the foot (54 rows) - opaque over 0.607 of
the tile, mean grey 0.569 where opaque; `assets/blender/README.md` has the full measure.
The tints (`dressing.json` V4_front / middle / back) are untouched.

**The row was the hash.** Every jitter, height, yaw and shade went through
`TerrainBuilder.hash_unit(osm, purpose, index)` with consecutive indices, and hash_unit's
text ends in the index: two consecutive indices reach FNV-1a's last byte one multiply
apart, so their units differ by 0.004 (measured on way 420556746, tree_height 12356..12359:
0.7418, 0.7457, 0.7652, 0.7691) - every tree along an edge the same height to 5 cm, the same
jitter and the same yaw, every card of a run the same height and the same texture phase. A
20 % gap draw on the raw units came in 1 278 runs with the longest 27 slots (216 m without
a wall) over 30 000 slots. `ForestWalls.unit()` now folds the OSM id and the index into a
spatial mix (the continuation's `corner()` fold, (index × 73856093) xor (osm × 19349663))
that stands in hash_unit's id field with the index still in its own: the same draw gives
4 756 runs, the longest 7 - a fair draw; still no RNG, the same (osm, purpose, index) the
same unit everywhere. The edge trees themselves stand `TREE_INSET_M` 0.75 m into the forest
(was 1.5: at the card line, breaking the wall's face instead of hiding behind it), jittered
± 40 % of their gap along the edge (`TREE_JITTER`, was ± 25 %) and scattered ± 0.4 m across it
(`TREE_SCATTER_M`, new).

**The counts.** 63 190 cards (was 79 102; 10 679 slot-layers beyond the 60 m, was 13 229),
19 379 trees (118 V1, 19 261 V2, 32 in rows; was 19 339: 116 / 19 223 / 32), 2 598 435
vertices and 2 183 322 triangles (was 2 657 227 / 2 210 858), 19 379 trunk prisms in the same
42 bodies (697 644 face vertices, was 696 204); `describe()` now says "30777 slots, 63190
cards (10679 beyond the 60 m, 6154 slots open as gaps, 1967 cards feathered)".
`scripts/physics_bubble.gd`'s header still says "19 339 trunks" (frozen; the staleness
accepted).

**The fences** (`tests/dressing_test.gd`, 118 checks, was 113): the gapped slots' share of
the slots within 2 % of the builder's rate and the slots' cards accounting exactly (built +
far + 3 × gapped); every feathered taper in [0.5, 1], every terminal card's slice inside the
thinning band; every card's u slice its width's share of the 0.14-0.30 window and its v top
in its layer's band, the front's highest 0.050; the edge trees' inset, jitter and scatter
the demand's; the wall texture's skyline std over 0.1 of the height, at least 8 column gaps
below 60 %, the thinning band sparser than the rest by 0.1, the bottom 8 rows solid; the
scene built twice still describes itself the same to the bit. `tests/bubble_test.gd` moved
ONLY its named-tree constants (the Conductor's narrow freeze exception: the fixture pins an
edge-sampled tree by literals and FOREST-2 legitimately moved every edge-sampled tree):
index 12369 of the same way 420556746 beside the same straight, the one whose geometry
matches the old fixture's (21.15 m tall, radius 0.338 m; the tree nearest the old point,
index 12370, is a 17.30 m spruce whose thinner prism the box overshot by 0.14 m at the
bite before the trunk pushed it out, and the frozen never-past fence refused it). The
visual probe (frozen, the one sanctioned windowed run): before `.scratch/fd-visual/
forest-2-before/`, after `forest-2-after/`; the straight reads as many spruces of many
heights with gaps and trunks between them, the far end of a gap shows a neighbour's
staggered deeper card with a vertical edge (the stagger fills two-thirds of a gap: the
recipe's cost, noted).

### The async load (LOADING-1)

The canon (decisions.org C07BE6F1, the driver's ruling of 2026-09-27): no freezing load.
The Ring's build was synchronous in `_ready` - the garage's drive row changed the scene
and the window held for ~17 s under the macOS loading bubble while the road, the terrain
and the forest were built on the main thread. Now the Ring row lands on a loading screen
(`scripts/loading.gd`, `scenes/loading.tscn`; the pad's row stays direct, its build is
trivial): the Ring scene is instantiated but not added to the tree (no `_ready` runs), its
three builders are claimed (`build_deferred`), and the build runs as two stages over the
same functions the synchronous build runs. The DATA STAGE is pure arithmetic on
`WorkerThreadPool` tasks - `RoadBuilder.prepare_data` (the files, the rim rule, the right
of way, the profile, the roads in CHUNK_ORDER), then one `sweep_road` per road as a group
task; `TerrainBuilder.compute_fields` (the lattice, the distance field, the raster, the
forms, the plan), then its `mesh_jobs()` as a group; `ForestWalls.place` (the walk, the
trees), then its chunk jobs as a group - each chunk into its own slot, the tallies a job
makes its own and merged on the main thread, the forest's index memo grown to every
chunk's need before a job runs; the one shared write is the road's two twist-bound counts,
which the frozen ring drive test pins as the builder's own members incremented from inside
the sweep, so they take a Mutex (a sum: the same total in any thread order). The NODE STAGE is
the main thread's, over frames under an 8 ms budget each: `add_strip`, `add_job`, the
floor, the trunk bodies, the bubble - no Node is ever made off the main thread. Then the
Ring is added under the root as the current scene and the loading scene frees itself; the
Surfaces node swaps its wrapper in at its first tick as ever, so the ring drive test's pin
(`road.profile is WorldRoadProfile and car.road_profile == road.profile`) holds across the
handover. CHUNK_ORDER is each builder's own sequential order (the drape's segment order,
the near chunks row-major then Mid, Far, the bands, the water, the continuation, the wall /
tree / trunk chunks in first-seen order): the workers fill the slots in the clock's order
and the node stage consumes them in CHUNK_ORDER, so the children, the meshes, the bodies
and the counts are the synchronous build's byte for byte - `tests/async_build_test.gd`
hashes the two builds against each other. The screen: a progress bar weighted by the
stages' measured wall times and filled per chunk, the percentage, the stage running with
its chunks done / total, in the garage's own palette; `Esc` abandons the load and returns
to the pad (the tasks cancelled at their next chunk and waited for, the partial Ring freed).
The setting `application/use_async_build` (project.godot, default true) routes the row;
false takes the Ring direct, the synchronous path every suite test loads through (a direct
instantiation never sees the setting: the builders build in `_ready` unless the loading
scene has claimed them, so only `tests/menu_test.gd`, which activates the garage's row,
pins it false in its `_initialize` - the Conductor's grant - and its one additive check
sets it true for itself to see the row land on the loading scene and then on the Ring).
The fallback: a stage that cannot run (the files missing, a drape without a lattice) is a
`push_warning`, the screen says so for a frame, and a fresh Ring is added the ordinary way
- the synchronous build, the freeze, honestly - never a broken scene; a script error inside
a worker's task is the one failure this does not catch. MEASURED (this machine,
2026-09-27): GDScript does not spread across the pool - the road sweep took 4 917 ms on
the main thread, 4 935 ms on one worker, 4 325 ms on four and 4 383 ms on eight (the
interpreter's shared refcounts and object locks serialise it; `DATA_THREADS` caps a group
at four) - so the async load takes about what the synchronous one did, 16.4-16.6 s
headless here; the gain is the canon's: the main thread's longest frame during the load
is 53-55 ms (the loading scene's own count) and 96-98 ms for the handover's frame (13 579
nodes entering the tree), against 17 s held before. The frame-delta log of the sanctioned
windowed run is under `.scratch/loading-1/` (untracked). LOADING-1 built the whole Ring
behind the bar; since L2-STREAMING-1 the bar covers the resident base and the car's
vicinity and the rest streams behind the driving car - the next section.

### The thin handover and the streaming tail (L2-STREAMING-1)

The canon's second half (decisions.org C07BE6F1: "world-around-the-car streaming") under
the driver's ruling FD79B028 of 2026-10-01 on `docs/design/l2-streaming-design.md`: about
2 km of dressed vicinity is enough, the loading screen vanishes the moment the car can
roll, the tail streams with no bar, every road's mesh stays resident, and far chunks
retire and rebuild on return. Landed: the design's slices 1 and 2 (the thin handover, the
tail), slice 3 (THE RETIREMENT below) and slice 4 (THE STAND-IN below it: a retired
terrain near chunk's 50 m stand-in). Not yet: the screen itself is as it was (slice 5).

THE SCHEDULER (`scripts/streaming_scheduler.gd`, class `StreamingScheduler`, the autoload
`Streaming`, registered after every other autoload) follows the ShellsWatch / MarksWatch
pattern: it watches the tree's `node_added`, no builder is edited for it and no scene file
names it. The loading scene claims its Ring there while the Ring is still outside the tree
(`claim()`: only a scene outside the tree whose four builders are `build_deferred` is
taken, so a Ring instanced the ordinary way - every suite scene, the fallback - and the
pad never stream) and hands each of the three dressing lists through `split()` as its
group stage is submitted. Back come, in CHUNK_ORDER, the RESIDENT jobs - the terrain's
Mid, Far, Water, every road's `Band_` apron and the four continuation bands; the forest's
trunk bodies; the buildings' rail and solid bodies (both physics bubbles take their whole
body set once, in `finish_build`, as ever) - and the VICINITY: the 1 km chunks
(`Near_<row>_<col>`, `Walls_` / `Trees_<x>_<z>`, a buildings mesh `<element>_<x>_<z>`)
whose box is within `R_HANDOVER_M` = 2 000 m of the car's start position, the distance to
the box as the bubble measures it. The thirteen stages are the same thirteen; the three
group stages and their node stages count what came back, so the bar reads 100 % and the
handover happens when the base and the vicinity stand. The road's stages are untouched:
the profile, every strip, every collider and the floor slab are in before the car is.

THE TAIL is the scheduler's. When the claimed Ring enters the tree it streams the other
chunks: each chunk's data stage on a `WorkerThreadPool` task, four in flight at most, each
chunk's node stage on the main thread under the same 8 ms a frame - the loading scene's
seam and its two numbers, so nothing new runs on the main thread un-budgeted. The next
chunk is always the pending one with the smallest (band, builder, CHUNK_ORDER index) -
the band the chunk's box distance from where the car is NOW in whole kilometres, the
builders in the order Terrain, Forest, Buildings - and the chunks are added in the order
they were dispatched, never in the order the workers finished: for a standing car the
arrival order is a pure function of its position, and the tests pin it. No RNG; the wall
clock is read for the frame budget and the probe line only. A streamed chunk is the
one-shot build's to the byte (each job is a pure function of the checked-in files). When
the Ring leaves the tree (Esc to the pad, a scene change, the window closed) the tasks in
flight are waited for and everything is dropped; a Ring abandoned before the handover is
released by the loading scene. `FD_LOADING_FRAMES=1` adds one line per streamed chunk and
a summary (never in the suite's lines).

WHAT THE CAR STANDS ON never streams: the car reads `WorldRoadProfile.sample_height` and
the floor slab, both resident; every streamed chunk is a picture (the terrain is visuals
only, a wall card and a crown carry no shape, a shell's mesh none either). A chunk not
yet there shows a hole and changes no physics read: `tests/streaming_test.gd` drives the
ring drive test's 2 km from Döttinger Höhe - 2.8 km from the pit, ground whose dressing
was absent at the handover - once on a one-shot build and once starting at the handover
with the tail still streaming, and lands on the same odometer and position to the bit.
A builder's `counts` and `describe()` are session totals merged per add: at the handover
they read the base plus the vicinity and reach the one-shot build's values to the integer
when the tail completes - and stay there: a retirement takes nothing from them and a
rebuild adds nothing to them. The scheduler's own counters (`chunks_total`,
`chunks_at_handover`, `chunks_streamed`, and since slice 3 `chunks_retired` and
`chunks_rebuilt`) are additive: none of them ever falls while the Ring is claimed.

THE RETIREMENT (slice 3; the ruling: "RETIRE far chunks and accept a rebuild on return -
bubble-style hysteresis"). Once the tail has completed - every chunk built once, the
builders' totals whole; the step that completes it retires nothing, so `tail_completed`
fires on a whole Ring - every step of the scheduler holds the tail's chunks against two
radii, the distance again the car's to the chunk's box: `R_RETIRE_OUT_M` = 4 500 m and
`R_RETIRE_IN_M` = 3 000 m. A chunk standing whose box is FARTHER than 4 500 m is retired:
its node (the `MeshInstance3D` and the `ArrayMesh` it holds) is taken from under its
builder and freed; its job record (the name and the inputs of its data stage) is kept,
and so is every tally. A retired chunk whose box comes NEARER than 3 000 m goes back into
the tail's own pending set and is rebuilt by the tail's own path - no second one: nearest
first by the same (band, builder, CHUNK_ORDER) key, its data stage on a worker (the
builder's `add_job` released the first build's arrays, so the stage runs again on a fresh
copy of the record - a pure function of the checked-in files: the same bytes), its node
stage on the main thread. Between the two radii, and exactly on either, nothing changes:
a chunk standing stays, a retired one stays retired, so a car idling at one radius never
flickers a chunk. The frees share the frame's 8 ms node budget with the adds (the adds
first), in the order (builder, CHUNK_ORDER); the decision is a function of the car's
position and the chunk states alone - the budget decides how many frames a standing car's
retirements take, never their order nor where they end. WHAT RETIRES is only what the
scheduler streamed - the tail's `Near_`, `Walls_` / `Trees_` and buildings mesh chunks.
What never does: the vicinity's chunks (built behind the bar by the loading scene, within
2 000 m of where the car started - they stand for the session wherever the car goes),
every resident job (Mid, Far, Water, the aprons, the continuation, the trunk, rail and
solid bodies), everything under Road, and anything on a Ring the scheduler never claimed
(a one-shot Ring, the pad). A retired forest or buildings chunk leaves air; a retired
terrain near chunk leaves its stand-in (THE STAND-IN, next - until slice 4 it left a hole);
the car's physics reads none of it. `FD_LOADING_FRAMES=1` adds one line per retirement and
per rebuild.

THE STAND-IN (slice 4; the ruling: "terrain near-band retirement with the 50 m stand-in";
the design: "a retiring near chunk swaps to one Mid-style 50 m quad per tile built from
the same fields (pure), so no hole shows; rebuild restores the fine mesh"). A terrain near
chunk that retires leaves `Standin_<row>_<col>` in its place under Terrain:
`TerrainBuilder.standin_job()`, a pure function of the same resident fields the near mesh
reads (the heights, the reach, the tile plan, the nodes' colours, the lattice's normals),
built and added by the scheduler inside the retirement itself, on the main thread, after
the near mesh is freed and at that child's own index - so the children's order is the
transitions', never the frames'. The rebuild's add frees the stand-in FIRST and adds the
near mesh after it, in one call: no frame shows both, none shows neither. The stand-in
retires with its chunk and comes back with it - nothing of it stands for the session - and
it is in no tally: it never goes through `add_job`, the builders' `counts`, `elements` and
`describe()` and the scheduler's five counters do not move for one (`chunks_stood_in()` is
the state). A new claim and a Ring's exit forget every stand-in: they are the Ring's
children and are freed with it. THE ROAD RULE: a near tile with no lattice node inside a
road's reach is ONE quad at its four corner nodes (the mid band's 50 m quad, 2 triangles
for the near mesh's 50); a near tile with one keeps its 10 m cells, each kept or dropped
by the near mesh's own rule (a cell with a node inside a road's reach is the apron's, and
the aprons are resident). A 50 m chord across a reached tile would roof a road in a
cutting, and a reached tile left out would open a 50 m slit beside every road; this way
the stand-in covers exactly the cells the near mesh covered and no quad lies over a road
(probed: every ribbon's paved width and shoulder sampled each metre, 2 232 505 samples in
near tiles, 0 inside a tile drawn at 50 m). THE SKIRTS: a 50 m quad's edge hangs the LOD
skirt (6 m) where the tile across it draws finer - a reached tile of the same chunk, or
any near tile of the next chunk, whether that chunk stands at 10 m or as its own stand-in
(the rule never reads another chunk's state) - and none toward a mid tile (the mid band
hangs its own) nor between two 50 m quads. The same material, the same colour reads; no
body, no shape. `FD_LOADING_FRAMES=1` adds one line per stand-in put up and taken down.

MEASURED, the stand-in (this machine, 2026-10-03, headless; `standin_job()` over every
near chunk of a one-shot Ring, and the streamed Ring at the pit anchor stepped by hand).
THE HONEST SIZE: the stand-in keeps what its coverage needs, BY DESIGN, and the Ring has
3 304 roads - about half its near cells lie in tiles one reaches. Triangles, over the 42
near chunks: 593 266 -> 280 238 (47 %); a chunk's stand-in 2 842 to 8 892 for a near mesh
of 7 398 to 16 820, from 24 % (`Near_5_4`: 3 796 for 16 018) to 69 % (`Near_5_1`: 5 102
for 7 398), the largest `Near_2_4`'s 8 892 for 12 992 (68 %). Arrays as built: 20.8 MB ->
13.1 MB - a retired near chunk gives back 37 % of its near mesh's arrays and keeps 63 %;
that is the trade slice 4 makes for the hole it closes. In the process's static memory:
the pit anchor's tail has 24 near chunks, which hold 6.38 MB standing and 4.39 MB as
stand-ins (69 % kept); with the car standing at the pit 3 of them are away and their
stand-ins hold 0.50 MB (1 199.74 MB against 1 199.25 MB with the three freed by hand,
slice 3's state); with the whole tail away 1 146.4 MB against slice 3's 1 142.0 MB. THE
MAIN THREAD: the stand-in's data stage runs inside the retirement, 3.3 to 7.4 ms a chunk
(mean 6.3 ms, GDScript), its add 0.25 ms. The 8 ms node budget is read before each
retirement, so one begins only while the frame's budget lasts and the one that runs past
it is the frame's last: a step with one terrain retirement measured 4.1 to 9.4 ms, with
two 11.3 to 15.6 ms (the pit, then the car put 57 km off at once: 24 near chunks over 13
steps), a step of 122 forest and buildings retirements 0.7 ms. THE NAMED FOLLOW-UP, not
built: the stand-in's data stage on a worker, as the rebuild's is - a prefetch or an
asynchronous retirement, either one new machinery and new pins - if the driver ever feels
that frame at the 4.5 km radius.

MEASURED, the retirement (this machine, 2026-10-03, headless, the car standing at the pit
anchor): of the 259 chunks of the tail 125 lie past 4 500 m and retire in the first frame
after the tail's completion (one frame, 6.5 ms) - 3 terrain near chunks, 6 forest chunks
and 116 buildings meshes; 86 lie in the 3 000-4 500 m band and 48 inside 3 000 m and
stand; the 94 of the vicinity are never the scheduler's. At the Karussell 123 of 262
retire, at Aremberg 162 of 289. THE HONEST SIZE OF THE GAIN, again: the process's static
memory reads 1 141 MB at the handover, 1 210 MB with the Ring whole and 1 199 MB after
those 125 retirements - 11 MB back of the tail's 70, about 1 % of the whole, because the
streamable chunks are a small part of what stands (the roads and their 3 304 aprons are
resident by the ruling) and the Ring's 42 km² core is mostly within 4.5 km of anywhere on
it: from the pit only 3 of the 42 near chunks are far enough to retire. What this landing
gives is, as before, the mechanism: the retire path, its hysteresis, the rebuild's byte
pins and the additive counters that slice 4 and any wider streaming stand on.

MEASURED (this machine, 2026-10-01, headless, `.scratch/streaming-1/`, untracked): of 353
streamable chunks 94 stand at the handover from the pit anchor and 259 stream after it,
in 1.2-1.3 s, the tail's longest frame 12-20 ms. THE HONEST SIZE OF THE GAIN: the handover
itself barely moved - 43.7-45.6 s over four runs against 43.9-47.8 s over four before,
inside the run-to-run spread (the frame after the handover 146 ms against 139-141) -
because the streamable chunks are a small part of the build. One thread's data stage,
measured per job kind: the 42 near chunks 0.7 s, the forest's walls and trees 0.5 s, the
buildings' meshes about as much, against 30.0 s for the 3 304 `Band_` aprons (one per
covered road: the platform strips, the carve and the caps since ROAD-3..7) and 1.3 s for
the continuation - the design's weights (loading.gd's table, 6.5 s for all terrain
meshes) predate the road widening. The aprons are resident by the ruling and the design
(the coarse fill, the ground beside every road), so the time to the first metre is
theirs; streaming them by proximity is the lever that would move the handover and needs
its own ruling. What this landing gives is the mechanism - the scheduler, the per-chunk
byte pins, the thin handover's contract - with every pin that had to move moved in the
open (`tests/async_build_test.gd`'s header, THE MOVED PINS).

### The road body and the carve (ROAD-3)

The driver's finding: the road flickered against the ground and read as a flat sheet laid on
the grass. Two root causes, both measured before anything was changed
(`.scratch/road-3/separation_probe.gd`, untracked: a headless probe that reads every
terrain platform strip and the road strip of the same id as parametric sheets - sections x
offsets, the meshes' own vertices, only the quads their indices draw - and samples both at the
same chainage and offset across the paved width, at every terrain section and the midpoints
between; separation is road height minus terrain height, at or under 0 is terrain on or over
the road):

* **the terrain drew one flat quad across the paved width** at the field's own height, and its
  paved-edge columns sat *at* the road's edge - the same plane as the road mesh wherever the
  crossfall is a plane (every bend at or over the 2 % crown), the same line along every edge.
  The depth buffer chose either from one pixel to the next: the flicker. At a layer crossing
  the quad's straight chord between two edges answered by different roads stood metres over
  the lower road. Before: every one of the 229 171 strip sections had terrain at or above the
  road, 1 665 494 of 2 740 140 samples (60.8 %; 869 215 of 910 076 at the paved edges), the
  worst 8.45 m over (82512873-0 at a crossing), all 3 304 roads;
* **the road had no body**: a surface with nothing under its edge, so the verge met it on the
  same plane and nothing said "slab".

**The carve** (`scripts/terrain_builder.gd`, THE CARVE at `CARVE_DEPTH_M`): the footprint - the
paved width plus the shoulder band - is carved out of the platform strip. No quad is drawn
across the paved width at all (the road mesh is the only surface there; a chord across the
Karussell's bowl would stand over its flat strip, so nothing is drawn under the road), the
paved-edge columns stand `CARVE_DEPTH_M` (0.5 m) under the field, a verge column at the road
body's foot (`RoadBuilder.SKIRT_OUT_M`, 0.5 m out) is held `CARVE_LIP_M` (0.07 m) *above* where
that foot stands and never above its own field's undercut (so the foot is buried: no gap under
the body's edge on an embankment, no gutter beside it on flat ground - the grass meets the bevel
about 0.44 m out), a shoulder column at the shoulder band's end (`CARVE_SHOULDER_M` 1.5 m, the
surfaces table's `rules.shoulder_m`) at the field's undercut, the blend band and the apron
beyond as before: ten columns a section, was six. The fields, the forms, `surface_at`, the
distance field and the car's read are untouched: a wheel on the shoulder stands where it stood,
the ground drawn under it a little lower (0.2 m at the verge column on flat ground, 0.03 m at
the shoulder's end). The near lattice, the mid tiles, the water and the continuation are
byte-identical. The terrain's count moves: 2 772 530 vertices / 4 466 373 triangles (was
1 855 846 / 3 111 171); the describe() line gains the capped count below, its other numbers stay.

**The cap** (THE CAP at `CAP_SAMPLE_M`; the driver's *"hill covering the road"*, issues 0024-0065
in `docs/road-3-analysis.md`): the carve alone left the NEIGHBOURING strips over a road - a side
road's blend and apron chords fan across the loop at every junction (the field beside a side
road's end eases toward the raw lattice, metres up in a cutting, and the chord to the next row on
the loop's pavement crossed the loop's edge that high), and beside a parallel road the same. A
second probe (`.scratch/road-3/spill_probe.gd`, untracked: every 10th section of every road at
the centre and both paved edges against every OTHER strip within reach, projected onto that
strip's own chainage and offset, and against any drawn lattice cell) measured 14 330 of 112 758
points with another road's strip above the road on the committed tree (5 732 by over 10 cm, 747
by over a metre, the worst 6.73 m; 8 481 sections on 2 789 roads; the lattice cells never - a
cell a road crosses always has a node in the road's reach and is dropped). Now every strip
vertex inside another road's footprint (its paved width plus the shoulder band) is capped under
that road: `cap_at()` reads the profile's own chord index and answers the other road's platform
height at the vertex's chainage and offset less `CARVE_DEPTH_M`; `strip_caps()` takes the lowest
of that at the vertex, at its quad neighbours (so no chord out of a capped vertex rises over the
pavement) and along its row's apron chords sampled every 2.5 m (a 3 m road's 6 m footprint can
fall between two columns). 331 888 vertices capped, counted in the describe() line. After: 6
points of the 112 758 (4 sections, 4 roads), the worst 0.94 m - each a strip END standing on
another road's pavement (a side road drawn to the loop's centreline; its end row is capped, the
chord from the row before is not, a 2 m cutting at the join) - and at every one of the nine
reported issue spots nothing stands over the road (the committed tree had 325813597-0's strip
0.22 m over issue 0026's spot and 696037709-0's 1.78 m over 0065's).

**The road body** (`scripts/road_builder.gd`, THE ROAD BODY at `SKIRT_OUT_M`): a visual-only
skirt along both paved edges, one `MeshInstance3D` per road (`Skirt_<id>`, after its strip and
its body under Road), no collider, no part of the strip's arrays: a bevel from the paved edge
`SKIRT_OUT_M` (0.5 m) out along the section's own across direction (the mitre's stretch kept,
so the foot runs parallel to the edge) and `SKIRT_DOWN_M` (0.3 m) down, the foot pushed further
to `SKIRT_FOOT_UNDER_M` (0.1 m) under the field where the field has fallen away from the edge
(an embankment: the foot never hangs in the air) - `skirt_foot_height()`, the one rule the
terrain's verge column reads too. Built in the data stage (`sweep_road`, the profile read is
pure, so the loading scene's workers build it as they build the strip) and added in the node
stage beside the strip's nodes; tinted the asphalt's darker side (`SKIRT_TINT`, the canon's
neutral-dark), rough, no texture. The road's certified counters and `describe()` are byte for
byte what they were (3 304 roads, 361 393 sections, 1 085 645 vertices, 1 435 286 triangles,
3 304 bodies): the skirt's own are `skirt_vertex_count` (1 445 572, four a section) and
`skirt_triangle_count` (1 432 356). Under Road the children are now Strip_, Body_, Skirt_ per
road (9 912 and the floor, was 6 608).

**After** (the separation probe on this tree): 5 samples at 5 of the 229 171 sections still
read terrain at or above the road, all at a paved edge, on 3 roads (the worst 0.80 m over on
32743989-0) - each a place where the single-valued field steps between two terrain sections
(another road answers one section and this road the next, a layer crossing: the road mesh
itself walls there, and the terrain's 2 m chord between its sections crosses that wall) - the
profile's recorded known issue, not the carve's (was 23 at 22 sections on 17 roads before the
cap, the carve alone); everywhere else the paved-edge columns are 0.5 m under the road (878 439
of the 910 076 edge samples between 0.5 and 1 m, 29 310 between 0.4 and 0.5: the crossfall's
chord between sections, 2 239 over a metre: capped). In the shoulder band, 0.25 m beyond the
edge the terrain is under the skirt at every one of 458 342 sampled sections (by at least
0.148 m); at the foot it stands the lip above it as designed. The visual probe's four shots (before `.scratch/fd-visual/road-3-before/`,
after `road-3-after/`, untracked) show the straight's edge as a slab with a dark bevel and the
verge meeting it, the ruts shot's edge line no longer a seam.

**The fences** (`tests/dressing_test.gd`, 120 checks, was 118): the strips' ten columns at the
named offsets (was six); the pit lane's edge vertex `CARVE_DEPTH_M` under the profile within
2 mm (was at the profile's height); THE CARVE on every strip - no quad across the paved width,
at every 7th section both paved-edge columns 0.5 m under the field, both verge columns the lip
above the foot and never above their field's undercut, both shoulder columns at the field's
undercut, within 2 mm, or under THE CAP where one holds (`strip_caps` recomputed on the built
vertices, every capped vertex at or under it); THE ROAD BODY - every strip's `Skirt_<id>` under Road, one surface,
four vertices a section and a quad a side between sections, no physics, its edge vertices the
strip's own to the bit, its feet `SKIRT_OUT_M` out at `skirt_foot_height` within 2 mm, the
road's counters the platform's alone. `tests/async_build_test.gd` (its header's was ->) hashes
the skirts and the carved strips in both builds as it hashes everything else: the async build's
meshes are still the sync build's to the byte. The certification metrics are byte-identical (a
mesh under the road is not a force). Frozen files untouched.

### The loop edge and the kerbs (ROAD-5, ROAD-8)

**The lip (ROAD-5, issue-0068** *"felt like there was no hump ... physically doesn't feel like
i'm stepping off the road"*): a loop-only physical edge in `scripts/world_road_profile.gd`,
`edge_lift` - zero on pavement, 0.11 m at 0.15 m outside the paved edge, zero again at 0.40 m,
piecewise linear, then the six-metre shoulder blend exactly as before; only a road whose
`priority` came from the skeleton's loop membership gets it (the 92 loop segments, each at its
own half width, the 7.5 m Karussell included), and `ramp_gradient` keeps sampling the smooth
field without it so gravity is byte-identical on pavement. `RoadBuilder._rumble_arrays` draws
it: both edges of every loop strip, vertices at the toe, the 0.15 m crest and the outer toe on
the physical field + 0.02 m of paint, red/white every 2 m of chainage, no collision shape (the
car reads the profile). `docs/road-5-implementation.md` carries the measurements.

**The kerbs (ROAD-8, `docs/road-0068-0069-analysis.md` §5.3: kerbs at selected corners, never
a blanket perimeter):** a table, `data/regions/eifel_ring/kerbs.json` (version 1, 25 entries on
18 named corner segments: Hatzenbogen x3, Hocheichen x2, Flugplatz x2, Schwedenkreuz, Aremberg x2,
Adenauer Forst x2, Metzgesfeld, Kallenhard x2, Wehrseifen x2, Breidscheid, Bergwerk, Steilstrecke,
Brünnchen, Eiskurve, Mini-Karussell, Schwalbenschwanz, Galgenkopf), each naming a loop segment, a
side in travel direction, a type and a chainage window, with a basis string like the
dealership's - the segment's `name` in skeleton.json, the loop's own turn geometry for the
corner's inside, `docs/nordschleife-data-sources.md` §4 (limited runoff, barriers close) for the
outside bands, and the driver's own laps of 2026-09-28 (telemetry sessions 0190 and 0192, read
only) where the line clipped that edge. 18 are `raised` (the inside of the tight corners) and 7
`flat` (fast-corner entries and exits, and outside runoff edges where a raised kerb would trip a
fast car). Excluded on purpose: the Karussell (its bank is its own mechanism), Döttinger Höhe
and the certified ring drive's 2 km from it, and the segments right after that stretch. Inside a
window the kerb REPLACES the lip on that side through the lip's own `height + lift` line
(`kerb_lift`): **flat** is 0.02 m of paint over 1.2 m outside pavement (0.15 m ramps), flatter
than the lip by design; **raised** is the lip's own shape amplified 1.5 x to 0.165 m at the
0.15 m crest with teeth - a ±0.02 m sine along the chainage at 0.5 m wavelength (60 Hz at
30 m/s), zero at every tooth boundary, riding the crest between 0.05 and 0.40 m out - never
under the plain lip, zero at the paved edge and zero again at 0.40 m where the blend band
resumes. Both fade in and out over 2 m of chainage at the window's ends, so at the ends the kerb
is the plain lip to the bit. Loop-only by construction (the edge branch runs for priority
roads alone; `set_kerbs` refuses an entry naming a side road, an unknown road or a window past
the road's length). On asphalt bit-identical (the road edge test's 4965-point paved digest is
unchanged); gravity untouched (`ramp_gradient` byte-identical across every window); off every
window byte-identical to a kerb-free profile from the same files. Grip unchanged: a wheel on a
kerb is what `Surfaces.classify` names it today (the 1.5 m shoulder rule: gravel) - a named
kerb surface class is a follow-up needing a freeze ruling on surfaces.json / surfaces.gd; the
feel is the height feature through the suspension, as the lip's is. The render
(`RoadBuilder._kerb_arrays`, the data stage): one `Kerb_<id>_<n>` mesh per entry under Road
after the strip's other nodes, rows at the strip's own sections plus the window's ends and,
for a raised kerb, a 0.125 m grid so the teeth show, five offsets across, every vertex on the
physical field + 0.02 m; the raised bands take the rumble's red/white shader, the flat a plain
paint material; no collision shape. Census (measured): 25 meshes, 69 150 vertices, 110 440
triangles; the rumble census stays 92 / 135 444 / 179 856. `tests/road_edge_test.gd` grows
18 -> 39 checks.

### Data sources & licences

The Ring region's world data under `data/regions/eifel_ring/` is derived from two public
sources (`docs/design/4b/data-pipeline.md` §8 has the verified wording and the licence links):
- Road geometry: © OpenStreetMap contributors — data licensed under ODbL 1.0,
  https://www.openstreetmap.org/copyright
- Elevation: © GeoBasis-DE / LVermGeoRP 2026, dl-de/by-2-0 (https://www.govdata.de/dl-de/by-2-0),
  www.lvermgeo.rlp.de, DGM1 Rheinland-Pfalz [Daten bearbeitet] (also offered under CC BY-SA 4.0;
  we attribute under DL-DE BY 2.0). The DGM1 tiles themselves are not in the repository.

### Tests

```sh
tests/run_tests.sh
```

Runs a headless import, then `tests/config_test.gd`: every car config under
`configs/cars/` read the way the car reads it and put through the validation, in
seconds, so a broken config fails the suite there and not somewhere in the smoke test. Then
`tests/element_catalogue_test.gd`: the seven element files under `configs/elements/` (the
4B element library, `docs/design/4b/element-library.md`, as data: 81 entries, R 18 / T 9 /
S 6 / B 11 / E 14 / V 8 / F 15) read the way `ElementCatalogue` reads them and put through
its validation, in seconds and before anything drives, so a broken entry fails the suite
there; then every entry held, one line per check, to what the plan asks of the catalogue:
an id of the documented form, unique, in its family's file; a canon line cited; a priority
of 1-9 that is its family's; every varying parameter with a range or choices and its
default inside; a texture size inside the family's budget; every economy building's shell
a B entry that exists and its privileges from the fixed vocabulary; the files parsed twice
to the same bytes; `entry()` and `by_family()` answering; and `validate()` on sixteen
fixtures broken in code (a duplicate id, an id of the wrong form or of another family's
letter, an empty canon line, a default outside its range or none of its choices, a
priority of 0, of 10 or not the family's, a privilege outside the vocabulary, a shell
naming no B entry or no B id, a texture over budget, a stone parameter that is no number,
a key outside the schema, a file that is not JSON) naming the entry and the field. Then
`tests/skeleton_test.gd`: the Ring's road skeleton under `data/regions/eifel_ring/`
(the pinned OSM snapshot's drivable ways projected to region metres, split at junctions,
simplified and widened offline by `tools/world/skeleton.py`; `docs/design/4b/data-pipeline.md`
§4) read the way `SkeletonLoader` reads it and put through its validation, in seconds and
before anything drives; then held to what the plan asks of the skeleton: the snapshot id
present and pinned to 2026-09-22T08:45:51Z, the bbox and the origin the Ring's; every
segment id of the form way-index and unique, every segment with two or more points,
sorted; every junction with two or more segments, each there and ending on it, and every
segment end on a junction listed by it; widths by class the table's, one line per class,
a width by tag inside its band, no raceway taking one, the Karussell 7.5 m; relation
38566's segments chaining one into the next within 0.5 m, closing, all raceway and oneway,
the loop within 1 % of the 20 830 m lap; the loader's own forward projection held to
pyproj's on a pinned reference table (within 0.01 m at the origin, 0.5 m at 20 km); the
checked-in Karussell sample's three ways present with their endpoints where the sample's
lat/lon say; the lookups answering; a five-way fixture built in code through the same
checks (a crossing, a dead end, widths by class and by tag, a two-way loop closing); and
`validate()` on eighteen fixtures broken in code (an unpinned snapshot, a foreign bbox or
origin, a width that is not the table's or outside the band, a raceway width by tag, a
class outside the table, a one-point segment, a mismatched way, segments out of order, an
unknown key, a one-segment junction, a junction listing a segment that is missing or does
not end on it, a segment end its junction does not list, a loop that does not join or
close, a file that is not JSON) naming the thing and the field. Then
`tests/world_profile_test.gd`: the Ring's elevation drape under `data/regions/eifel_ring/`
(the 42 verified DGM1 tiles mosaicked and sampled along the skeleton offline by
`tools/world/drape.py`: the platform's centre height every 2 m, a crossfall per point - since
the ROAD-GEOMETRY FIX-NOW landing the superelevation of the heading change over a 20 m window
run off at 0.004 per metre, was the three-point circle's whose sign flipped on short chords -,
the bridge and tunnel rules, crest/dip labels, a 10 m terrain lattice of the raw ground;
`docs/design/4b/data-pipeline.md` §5) read the way `WorldRoadProfile` reads it and put
through its validation against the skeleton, in seconds and before anything drives; then
held to what the plan asks of the drape: the snapshot pinned and the skeleton it was draped
on the checked-in one by sha256, the 42 tiles each sha256-verified against the metalinks,
the coverage the 7 km × 6 km core and the lattice spanning it; every Nordschleife segment
covered; the crest/dip labels recounted from the file's own heights by the mirrored rule and
equal to the file's (1 927 crests, 1 874 dips; was 2 551 / 2 465 before ROAD-SMOOTHING);
every draped bridge deck linear between its abutments, one line each;
the Karussell's bank (branch (c) of the decision tree: 30 % over 6.5 m with the 1 m strip;
since the ROAD-GEOMETRY FIX-NOW landing ramped over 30 m at each end from the neighbours'
stitched plane values, the array held to the mirror's ramp and the label to at 30 / to 122.915
/ ramp_m 30, was +0.30 at all 29 points with a step against the neighbours)
read across the bowl; the reference heights derived from the file itself, the loop's lowest
sample at the Breidscheid bridge 333 ± 2 m, its highest at T13 627.5 ± 2 m, the Hohe Acht way
616.8 ± 2 m (measured, `docs/design/4b/ring-region-decisions.md` §3); the loop's steepest
gradient past the pad's `MAX_SLOPE` and under 35 % away from bridge abutments, the abutments
reported apart; the documented fallback outside coverage (height 0, gradient zero, mask 0)
and no cliff at the edge; purity; `ring()` the same profile; the smoothing's evidence from
the file's own numbers (ROAD-SMOOTHING, 2026-09-23, `docs/design/4b/data-pipeline.md` §5:
the plain segments' centre heights Whittaker-smoothed at λ 5 with the crest/dip runs held to
the raw data, every junction's ends stitched in height and crossfall, write-side): the loop's
station-to-station grade change at the 90th and 99th percentiles down to the centimetre
rounding's own 0.5 % and 1.0 % (was 1.5 % and 3.0 %), every junction's draped ends on one
height and one crossfall (was a crossfall gap over 2 % at 1 562 junctions, 29 on the loop;
each end's pre-stitch tilt recomputed through the mirror's `crossfall_of`, a stub under 15 m
between a rigid end and a node holding the rigid tilt through - 28 such ends -, the
Karussell's two ends carrying the node's tilt without voting),
the driver's issue-0005 stair at junction 65386044 (0.255 m and 0.150 m at the paved
edges, now 0.000) and issue-0001's T13 ridge (the pit lane's −4 % against the loop's +4 %,
0.340 m, now 0.000) flat in the file and in the field, and the raw -> smoothed evidence over
±50 m at the three issue sites with the crest labels there kept at the raw amplitude; the
ROAD-GEOMETRY FIX-NOW fences (2026-09-25, `docs/issues-analysis-2026-09-24.md`): at both
Karussell junctions the largest one-step height jump at any of nine offsets within ±10 m is
0.038 m (entry) and 0.034 m (exit), under 0.05 (was -0.878 / +1.211 and +1.269 / -1.281 m at
the paved edges: the bowl meeting the neighbours' planes as a wall), the centre line the file's
own heights through both; the 0007 site's largest one-step 0.049 m (was 0.342, the crossfall
flipping across a 0.45 m chord); no loop chord twisting the paved edge over 0.02 m/m (was 19,
the top 0.940); and the twist rule's mirror on 799394513-1's own points; the JUNCTION
RIGHT-OF-WAY fences (2026-09-26, `docs/issues-analysis-2026-09-24.md` §4.4, triage item 4:
`WorldRoadProfile.Road.priority` from the skeleton's loops entry, one comparison in
`_nearest_chord`): the loop's 92 segments the profile's priority roads and no other, and on
the corrected field the car reads (the rim rule and the crossing right of way applied as
`RoadBuilder.build()` does) at the loop's 44 junctions with a covered non-loop participant,
probed every 0.25 m over ±6 m through the node at nine offsets inside the loop's 8.5 m, no
station read from a non-loop road (was 4 690: a service road's or the pit lane's platform
inside the loop's width; 172 more at the other 48 junctions from parallel roads), the largest
one-step jump 0.136 m at every one of them under the loop's own 0.197 m kink bound (was 0.625 m
and 7 junctions over), the T13 four-way junction named (with the profile's rule alone it kept
0.216 m on the centreline: the rim walk from Hohenrain's east abutment left the loop there for
the Boxengasse 769107218-0, the smaller turn, and lifted that branch while the loop's own
41395670-1 stayed at the file's 9.5 % start, masked until the loop answered inside its own
width - so the rim walk now stays on the loop where a loop segment is within its turn,
`road_builder.gd`, the same rim 8.13 m out along 41395670-1 at 619.09 m, was 619.07 m along
the branch, the other 14 lifts the same to the byte); the driver's sites: 0018 0.047 m at any offset (was
0.377), 0017 0.028 m (was 0.080), the Hohenrain deck of 0021 0.009 m (was 0.469 from the
parallel Boxengasse-an-T13 bridge), 0001's pit lane answering nothing (was offsets ≥ +1),
0012 0.042 m at the centre and left, 0.067 at the car's +1.37 (was 0.181) and 0.130 at the
right edge (was 0.474 / 0.264 at +3), the loop's own 7° wedge at junction 65387230 on the
16 % grade, bounded at 0.15 m; the 200 pinned samples' digest unchanged (no sample lies where
the rule bites); then a
3 × 3 km fixture built in code (a plane with a bowl and two crests, six roads through the
mirrored drape rules): the
plane within 1 mm off-road and on a centreline, its gradient within 1e-4, the bowl's depth,
bilinear continuity across the lattice's seams, the 2 % crown and the 6 m blend band, a
left-hand bend superelevated 6 % (a 90° corner over the 20 m window reads the hairpin cap;
was 4 % from the three-point circle's R 70.7 m), a bridge deck linear over the crest under it,
a tunnel at
the ground at its portal and 6 m under it inside, the crest labelled at its top, the bank's
bowl on way 414785755 with its 30 m ramps blended from the plane at both ends (the array
[0.06, 0.3, 0.06], the label at 30 / to 170 / ramp_m 30; the platform at a third of the ramp
the plane and the bowl mixed 2:1 at every offset, no 0.25 m step over 3 cm along the edge
through the ramp's end), a 4B-3 bank label without `ramp_m` reading through the 4B-3 branch
verbatim whatever its `at` says, the runoff on a spike, a straight still 0, the fallback
outside the box; a second fixture for the right of way, a 500 m square loop of four raceway
segments with a 3 m service road leaving a junction at 4.6° and running inside the loop's
width for 53 m (the loop answers on its platform with its own crown, the service road in the
blend band beside it and on its own length, and the same roads with no loops entry the old
rule: the nearer service road); and `validate()` on twenty-two fixtures
broken in code (an unpinned snapshot, another pipeline's version, another skeleton's
queries, other rules, a lattice short of a height or off the coverage, an empty coverage, a
DEM in another CRS, an unverified tile, a segment the skeleton lacks, a dense list short of a
station, a covered segment with a missing height, a label of an unknown kind or within the
threshold or of the wrong sign, a bank not filling the width, a bank ramp that does not fit
before `at` or after `to`, a negative ramp, a bank starting after it ends, a crossfall beyond
every rule,
segments out of order, a file that is not JSON) naming the thing and the field. Then
`tests/buildings_test.gd`: the Ring's focus table under `data/regions/eifel_ring/` (the
region's put-in-stone table of typed buildings, `docs/design/4b/ring-region-decisions.md` §4
as data: the nine gas stations, the nine workshops, the two dealerships, the test centre and
the proving-ground office, each with its library element, its OSM id, its WGS84 position as
OSM records it and its privileges; implementation-plan.md §4B-5) read the way `Buildings`
reads it and put through its validation, in seconds and before anything drives; then held to
what the plan asks: exactly nine E2 and exactly the stone table's nine amenity=fuel ids;
exactly one social station by the library's round(0.1 × 9) = 1, the stone table's node
1711333738, the same id on a second derivation; every E1 holding `build_cars`, none holding
`sell_fuel` (the file says so for none); the E11 within 50 m of way 26543901's first node,
the record projected through `SkeletonLoader` and the node from the checked-in skeleton (it
sits on the node: 0.000 m); every record's shell a B entry of the catalogue and its element's
own, with the placeholder footprint the library states (B6 12 × 8, B7 15 × 10, B8 20 × 12 m;
B9 none); `can()` refusing a name outside the vocabulary with the reason, the vocabulary
`ElementCatalogue.PRIVILEGES` referenced and never copied; the provenance header held to what
it cites (the query text's sha256, the fetched answer's where the snapshot store is on the
machine, the attic chain to the 4B-2 manifest's sha); and `validate()` on twenty fixtures
broken in code (a privilege outside the vocabulary or held twice, an E1 without `build_cars`
or selling fuel without the file saying so, a shell naming no B entry, not the element's or no
B id, an element the catalogue lacks, an owner outside none|driver|npc, a position outside the
bbox, a social flag on a workshop, two or no social stations among nine, a duplicate id, one
element placed twice from one OSM id, a key outside the schema, a record without its stone
citation, an unpinned snapshot, a sha field that is no sha256, a file that is not JSON)
naming the record and the field, and one mended (an E1 selling fuel with the file saying so)
accepted. Then
`tests/dressing_test.gd`: the Ring's first dressing pass (implementation-plan.md §4B-7;
`scripts/terrain_builder.gd`, `scripts/forest_walls.gd`, `scripts/sky_set.gd`, the three
nodes `scenes/eifel_ring.tscn` gained; the terrain visuals only, not one collision shape,
body or Area3D under it - the car reads the injected profile - and under the forest, since
BUBBLE-1, only the physics bubble's per-chunk trunk bodies (was -> not one collision object
under either; the ring drive test's output stays the same byte for byte: the trunks stand
off the paved width). The landcover file `data/regions/eifel_ring/landcover.json`
(written offline by `tools/world/landcover.py` from the pinned snapshot's q4_landcover
selectors - fetched in parts by `tools/world/extract_landcover_parts.py` on 2026-09-26
because every Overpass endpoint refused the pinned query whole, out of memory; the trees
part refused too and recorded missing) read the way `TerrainBuilder` reads it and put
through `validate_landcover()`; its header held to the pinned snapshot and the skeleton's
query chain, the pinned q4 query text's sha256 (the text verbatim in the test), every
part's query rebuilt from its selector and hashed to the header, the folded answer sha
recomputed from the parts', the raw files hashed to the header where the snapshot store is
on the machine, and the header's three projection samples reproduced through
`SkeletonLoader.wgs84_to_local` within 5 mm (the python port agrees with pyproj's skeleton
points to 0.7 mm at all 9 188 way starts, `landcover.py --prove`). The region's
dressing table (`data/regions/eifel_ring/dressing.json` beside the focus table, whose four
top keys the buildings test pins; ring-region-decisions.md §5: S1 / S5, the sun's bearing,
the palette's tints under the canon's 0.6 luminance cap, the density ceilings) through
`validate_dressing()`, and `focus.json` untouched and still silent under `Buildings.validate()`; since
OFFROAD-1 a T1 vertex carrying the palette's tint converted to linear (`TerrainBuilder.albedo()`,
*Surfaces, the off-road feel and the continuation* below), the Surfaces node a scene-root sibling
(Terrain's children still meshes only), and Terrain and Forest reading the `RingProfile`'s inner while
the car reads the wrapper (was -> the very profile the road handed the car). Every element the
three builders instantiate an id of the catalogue (T1-T4, T7-T9, V7; V1, V2, V4, V6; S1,
S5) and nothing outside their declared lists. The scene loaded as the ring drive test loads
it: the lattice plan's bands the catalogue's T1 table (2 m at the platform, 10 m within
200 m, 50 m to 2 km, 200 m beyond), every tile classed by that rule on the builder's
distance field (16 300 near tiles, 500 mid, no far block: the core has no point 2 km from
every road), the field held to a brute-force point-to-chord distance at sampled tiles'
nearest nodes within half a lattice step's diagonal, every sampled near-band vertex on a
lattice node at the node's own height, every mid vertex on a 50 m corner, the 3 304
platform strips at every 2 m station and every skeleton point with no gap over 2 m and
the pit lane's strip meeting the road at the paved edge 0.5 m under it within 2 mm (ROAD-3's
carve, and its two fences - no quad across the paved width, the road body's skirts - see *The
road body and the carve*); every one of the
~63 000 V4 wall cards (FOREST-2; was ~79 000: a fifth of the 30 777 slots are gaps) within
60 m of a covered road (the farthest 59.999 m), a sample every 400th within 60 m by brute
force over every chord, every card on a forest polygon, 12-18 m tall in three layers,
~10 700 slot-layers beyond the 60 m left empty (was ~13 000); the card recipe's fences
(see *The forest edge*: the gap share, the feathers, every window legal, the texture's
skyline and gaps); no edge-sampled
tree beyond the 60 m; the density ceiling per road and side (at most floor(length / 8 m)
trees, recounted from the tree list; the fullest side at its budget, ~1 300 samples
refused); at ten Nordschleife points the objects within 500 m under the ceilings - at
most 8 meaningful masses (forests with a card, tree rows, water) of the table's twenty,
the trees at most a fifth of §5's 2 × road length / 8 m; the haze Godot depth fog (not
volumetric) beginning at S5's 100 m, its colour the sky plate's horizon, the four-band
curve sampled at 50 / 200 / 500 / 1 000 m in the catalogue's bands in order and the
engine's one-exponent curve within 0.03 of it; one sun at S1's 45° (was the scene's 50°)
from the table's bearing 210°; and the scene built twice describing itself the same and
placing its last card at the same point; and since 4B-ASSETS-2 the Ring's road material
(`scripts/road_builder.gd`, one StandardMaterial3D on every strip) wearing the
Blender-authored asphalt set under `assets/textures/road/` - basecolor, roughness and normal
each 1024² (was the test pad's 256² procedural texture, which the pad keeps), the albedo
colour `RoadBuilder.ASPHALT_TINT` kept (the neutral basecolor's 0.777 mean was authored for
that multiply, so the road keeps its value), the normal map on at the builder's
`NORMAL_SCALE` 2.0 (the map is very shallow as authored; assets/blender/README.md allows up
to 4) - and the README's UV contract (u = (offset - left_paved_edge) / paved_width, 0 at the
left paved edge to 1 at the right; v = chainage / 8 m; was metres / 4 both ways) held on
every one of the 3 304 strips at every one of the 1 085 645 vertices within a thousandth of
a tile, the road built twice carrying the same UVs and material; the geometry untouched (the
ring drive test's lines the same byte for byte); and since BUBBLE-1 the trunk accounting
(see *The physics bubble*): the 42 trunk bodies are the 42 tree chunks, one StaticBody3D
with one ConcavePolygonShape3D each, back faces solid, the 19 379 prisms (FOREST-2; was
19 339) every tree and no card, every one of the 697 644 face vertices (was 696 204) on its
own tree's cylinder at the tree's slot
(the axis at the tree's point, the radius the archetype's measured trunk × the tree's scale,
0.19-0.54 m, the rows the foot and the crown base) within 2 mm, every disc inside its body's
box, and the forest built twice carrying the same faces and boxes. Then
`tests/ring_drive_test.gd`: the Nordschleife as a drivable road (`scenes/eifel_ring.tscn`,
built headless at load by `scripts/road_builder.gd` from the checked-in skeleton and drape,
implementation-plan.md §4B-4): drape.json pinned by sha256 (d36ccf27..., the ROAD-GEOMETRY
FIX-NOW regeneration after its codex cross-review; was aac02239... at the landing and
ROAD-SMOOTHING's f3ca142b... before; the two transforms below correct
parsed data, never the file); the rim rule and the loop's right of way pure functions of the
parsed data (twice, the same); the scene loads with every covered segment but the ten
crossing structures swept (3 304 roads, 361 393 sections, 1 085 645 vertices, 1 435 286
triangles - was 378 093 / 1 134 279 / 1 499 156 before the crossfall-twist rule's runoff
took the short-chord twists out of the arrays and the Karussell strip gained a fourth vertex
on its crown line for the blend; 329 394 / 988 182 / 1 304 320 before ROAD-SMOOTHING's crossfall stitch put a
ramp on every segment's end chord for the twist bound to split, and 383 146 / 1 149 438 /
1 519 368 with the first stitch, before the codex review's world-space re-tilt -, one trimesh StaticBody3D
per road on layer 2 and a follower floor slab on layer 1
put under the car every tick from the same corrected profile), the car at the pit anchor on
a WorldRoadProfile; the mesh is the field: every vertex of the loop's and the pit strips on
the corrected profile's `sample_height` within 1 mm (70 373 vertices; was 70 947), the quads' edges and
centres within the twist bound away from the skeleton's kinks (the field's own step between
two chords measured and reported there, as at junctions); the rim rule (the rim the first
outward station after which the climb stays under `RIM_SLOPE` 8 % for two stations; was the
first station climbing under 20 %, the ROAD-GEOMETRY FIX-NOW landing after
`docs/issues-analysis-2026-09-24.md` §4.3: the 20 % let the DGM1 hole-wall's 14.5 % tail and
its crest through - the hump that launched the car 0.750 m at Döttinger Höhe, issue 0020, and
Breidscheid's east sag-then-crest, issue 0011): Breidscheid's rims 8.44 m and 10.00 m out at
338.76 and 337.29 m and its deck line -4.06 % (was 8.00 m / 337.00 m / -5.14 %), every loop
bridge's abutment spike before and after through `ramp_gradient` (65 % -> 5.0 %, 57 % -> 5.0 %,
32 % -> 0.8 %, 43 % -> 0.9 % - was 6.8 %, the tail -, 46 % -> 3.9 %, 62 % -> 3.2 % via
amendment 2's continuation through the T13 junction, 61 % -> 2.9 %, 41395681-0 already clean;
the "before" numbers are the smoothed file's abutment walls, was 64 / 32 / 61 / 52 / 59 / 54 %
on the raw file), the rim fence - within 15 m of every lifted rim on the loop the grade along
the road changes by at most 3.5 %/m, under 5 (was 12.7 and 11.8 %/m at the two humps; read
along the walked chain - the deck inward, the approaches outward through their junctions, at
least 26 of 31 readings per rim, the boundaries compared over the real gap; was clamped to the
rim's own segment) -, the look-ahead's own fixture (a walk ending with one onward slope gives
no rim, one more station gives one at 4.0 m), the
whole lifts table (15 bridges, was 13: every one still lifts, two tracks join), no station on
the loop's own field at
20 % or more, every deck a straight line in the mesh, 41226730-0 untouched and below the
ground; the loop's right of way: the ten crossing structures (id, distance along the lap,
height step, removed) and the whole loop swept every metre with no step over 0.5 m left (the
largest 0.16 m; was 0.41 m at the T13 four-way junction, where the rim rule's lift through the
junction now lands on the stitched node); the driver's issue-0002 "big hole in the road"
localised: the car on the loop's bridge deck 41395681-0 over the primary 828126276-0, one of
the ten unbuilt crossing structures, the ground 5.6 m below the deck - a missing bridge side
and an unbuilt road under it, reader-side work recorded, not a height in the file;
the scripted pure-pursuit driver's 2 km from Döttinger Höhe along the loop's one-way
direction with no wheel off the paved width (the worst lateral offset, the speeds, the
crossings passed clean, the follower floor on the field every tick); the hill step made
executable (the world profile's gradient non-zero at the loop's steepest honest sample,
`RoadProfile.flat()`'s exactly zero at the same point); the Karussell's 30 % bank through
`ramp_gradient` with the drape's sign; body attitude measured on the bank and on the
steepest stretch (pitch and roll against the small-angle model, sanity bounds only); and
determinism: a second scene instanced fresh and driven the same 2 km lands on the same
odometer and position to the bit. 
Then
`tests/bubble_test.gd`: the physics bubble (BUBBLE-1, decisions.org 5BE9FBA3; *The physics
bubble* below): the Ring scene loaded as the ring drive test loads it, Forest carrying one
`StaticBody3D` per tree chunk (42) with one `ConcavePolygonShape3D` of the chunk's trunk
prisms and the one `PhysicsBubble` child fed the road's car, every body on mask 0 and on
layer 1 (the car's mask) or 0, no shape ever disabled; the archetypes' trunks measured from
the .glb bark surfaces (V2 0.32 m, V1 0.35 m, V6 0.25 m held to 0.30, at archetype scale;
the tops the crown bases 12.4 / 7.0 / 4.5 m); the radii ordered (80 m < 110 m); the bubble
right at the pit after the settle. The named tree (since FOREST-2: index 12369, OSM
420556746, a V2 spruce at (4469.06, -2744.16) beside the drive-start straight 683303211-0,
chainage 43.1, 11.0 m off the centreline, 21.15 m tall, its prism radius 0.338 m; was ->
index 12355 at (4475.91, -2747.53), chainage 35.4, 11.5 m right, 21.34 m tall, radius
0.341 m, the scale 1.067), its 36 faces at its slot in chunk (4,-3)'s body. The tree stop
as BUBBLE-1 measured it (since FOREST-2: from 44.4 m out, the bite at tick 264 at 16.57 m/s,
79 of 384 ticks in contact, held at 2.426 m and never nearer than 2.425, the creep 2.5 mm,
the slide 0.052 m, the control 290 ticks and 5.19 m past): from the straight's centreline
at chainage 0, 37.2 m out, throttle pinned
and pure pursuit on the tree's point, the car bites the body at tick 235 at 17.67 m/s
(`get_slide_collision_count()` against that body and no other), is held at 2.438 m from
the axis to its origin (the prism's inscribed 0.296 to 0.341 m plus the box's half-length
2.1 m nose-first; the box never nearer the axis than 0.332 m: never past), and 120 more
ticks of the same pinned throttle vary the distance to the axis by 7.5 mm (under 1 cm)
while the nose slides 0.19 m along the round trunk's face (the axis 0.15 m off the car's
centreline at the end, inside the nose; measured, the driver's creep against a round
trunk). The control: the bubble off (every body on layer 0) the same drive passes through
- no collision, the box through the axis, the origin 5 m past it - and the bubble re-forms
in a tick when re-enabled. The radii: from 1 300 m along the loop past Döttinger Höhe the
loop driver drives 700 m (2 577 ticks, 43 s) and EVERY tick every body's state is held
against the position the bubble saw - activated only under 80 m, deactivated only past 110
m, unchanged otherwise, no body toggled twice - the four events at ticks 471 / 944 / 1 328
/ 2 097 (chunk (3,-2) on at 80.0 m and off at 110.0 m, (3,-3) off, (2,-2) on); run twice
on scenes instanced fresh, first thing on each, the same events at the same ticks and the
same end position to the bit. The teleport: `reset_to` 2 205 m away to 5 000 m along the
loop, after one tick every body within 80 m active and every one past 110 m inactive. Zero
allocation: the node census of the tree and of Forest, the bodies, the state array and the
face counts the same before and after every drive. With `FD_BUBBLE_PERF=1` in the
environment the test also prints wall-time `perf:` lines (the builds, every tick of the
radii drive, the activation ticks, an `update()` micro-benchmark) - never in the suite.
Then
`tests/offroad_test.gd`: the surfaces and the continuation (OFFROAD-1; *Surfaces, the
off-road feel and the continuation* above): the surfaces table checked in, valid, the five
surfaces named, the road exactly {1.0, 0.0, 0.0}, every other surface losing grip and
adding drag and bumps, and `validate()` naming a grip out of bounds, a negative drag, a
missing surface, a road off the baseline and a surface the pass does not name; the Ring
scene loaded as the ring drive test loads it: the Surfaces node after Road at priority -1,
`road.profile` a `RingProfile` (a `WorldRoadProfile`) and `car.road_profile` the same
object, Terrain and Forest on the inner, the wrapper carrying the table's bumps, the pit
lane's wheels all on the road with the car reading 1.0 / 1.0 / 0.0; every delegated member
equal to the inner's to the bit at 1 221 grid points 250 m apart over the box and 1 km
around it, `coverage()`, `road_count()` and `point_along()` the inner's; `sample_height`,
`elevation_height` and `ramp_gradient` equal to the inner's to the bit at every one of the
3 429 strip vertices of the certified loop drive's first 2 km from the drive-start straight
and between sections on the centreline; the named points classifying as named (the
straight's centreline the road, 0.75 m beyond its paved edge gravel, 3 m beyond it the
forest floor, (6120, -2640) grass, (2890, -4510) field stubble, (5340, -3460) forest floor,
(-100, -3000) outside the coverage grass); the field continuous at the box's edge (484
points, 1 cm either side, within 1 cm), a ray west out of the box carrying relief inside
the 6 km margin and exactly 0 beyond it, a gradient out there where the inner's is zero;
the four continuation bands with 120 000 cells and 520 skirts, every sampled vertex at the
static field's height (or a skirt's 6 m under) in T9, every vertex on the box's edge the
wrapper's own height; the grass drive - the car reset to (6120, -2640), a T1 node 110 m
south of the 3 m track 420472180-0, nose north, throttle pinned 660 ticks: every wheel on
grass from the first tick, the axle grips 0.55 and the rolling decel 0.9, the launch peak
2.71 m/s² under 0.6 of the road reference's 6.87 (11.7 m/s at tick 300 against 22.7),
the wheels' travel-rate variance over ticks 60-300 above the floor and four times the
control's (the same drive with the bumps zeroed), the front axle reading the track's 1.0
at tick 600 and the rear at 607, and reset onto the straight's centreline the three inputs
back at 1.0 / 1.0 / 0.0 within two ticks; and two scenes instanced fresh driven the same
660 ticks on the grass first thing landing on the same position with the same peak to the
bit, the continuation the same at 2 812 points outside the box to the bit. Then
`tests/async_build_test.gd`: the async load (LOADING-1; *The async load* above): the Ring
built once the way every test loads it (the reference) and once through
`scenes/loading.tscn` under the root - (a), re-scoped by L2-STREAMING-1 (the moved pins,
each was -> now, are in the test's header): AT THE HANDOVER the children under Road
(10 030) the reference's names in the reference's order with its `describe()` line and
seven counters, and the children under Terrain (3 328 of 3 352), Forest (79 of 127) and
Buildings (74 of 261) the reference's order held to the resident set and the chunks
within 2 000 m of the car by the test's own arithmetic, the far chunks absent; AT THE
TAIL'S COMPLETION the `describe()` lines, the counts and the element tallies equal, the
children the reference's set name for name, the 259 streamed ones standing after the
handover's in the pinned (band, builder, CHUNK_ORDER) order, a SHA-256 per child equal
to the reference's child of the same name, and the SHA-256 per builder over every surface
array and every collider's faces, the children walked in the reference's order, equal
(the digests' first sixteen hex characters printed as the pin - the values the old
child-order walk printed); (b) every stage's chunks counted - the sweep
and the road node stage 3 304 roads, the terrain's two stages 3 329 jobs, the forest's two
78, the buildings' 73: the resident jobs plus the vicinity's chunks (was the whole lists:
3 353, 126, 260) - every stage done to its total, the scheduler's counters the same
arithmetic (353 streamable, 94 before the handover, 259 after), the bar never falling and
at 100 % at the handover;
(c) the main thread never blocked: the longest process frame measured from outside the
loading scene (the handover's enter-tree included), the scene's own longest frame and
every frame of the streaming tail under 250 ms (the numbers only on a failure, or with
`FD_LOADING_FRAMES=1`); (d) the car
on the road's profile, the same object, the floor slab under it, the builders still marked
deferred; (e) the setting true by default, the Ring routed and the pad not, false routing
nothing; (f) the fallback - a loading scene pointed at `scenes/car.tscn`, which has no
builders, warns and hands over that scene built the ordinary way; (g) the abandonment - a
loading scene freed while its stages run waits for its tasks and leaves nothing of the
Ring under the root, its claim at the streaming scheduler released. Beside the suite, a
standalone (not a step of `run_tests.sh`): `tests/streaming_test.gd` (L2-STREAMING-1;
*The thin handover and the streaming tail* above) - the scheduler registered last, its
numbers and pure functions, `claim()` refusing everything but the loading scene's Ring, a
sync Ring and the pad leaving it idle; the one-shot Ring as the reference with a SHA-256
per child; the streamed Ring at the pit anchor - the handover with the far chunks absent,
the ring drive test's own driver over its 2 km begun at the handover with the tail still
streaming and landing on the one-shot build's odometer and position to the bit, all four
wheels carried and inside the paved width every tick, then at the tail's completion every
child byte-equal, the `describe()` lines and counts the one-shot's, the scheduler's
counters adding up; the streamed Ring with the car put at the Karussell and at Aremberg -
another vicinity each, the tail in the pinned order for the standing car, every child
byte-equal; THE RETIREMENT (slice 3), every expected set and order the test's own state
machine over the chunk boxes - the standing car's streamed chunks past 4 500 m retired in
order with their meshes freed and no tally moved, the same along the pit's 2 km drive;
by hand (`step(at)`) away to the other corner and back, both radii walked on one chunk's
own box (standing to 4 500 m exactly, retired past it and all the way back in to 3 000 m
exactly, rebuilt inside it), 40 km off the Ring the handover's Ring again name for name
(since slice 4 with the stand-ins of the tail's near chunks after its children),
then a 4 000 m lattice of stops across the tail until every one of its chunks has been
retired and rebuilt at least once, each rebuild through the scheduler's pending set in
the pinned order and byte-identical to its first build and to the one-shot reference;
a one-shot Ring and the pad never retired; no count drift, the scheduler's counters only
ever risen; THE STAND-IN (slice 4), what one has to be from the test's own arithmetic on
the builder's fields, never the builder's function - every stand-in standing (the car at
each corner, then far off the Ring: every near chunk of the tail) covering exactly the
cells its near mesh covered, the unreached tiles as one 50 m quad, the reached tiles at
10 m, nothing over a reached cell, the skirts under the edges that meet a finer tile and no
other, every vertex a lattice node at `heights[]` to the bit, no tally moved; THE ROAD
RULE on the Karussell's near chunk walked by hand through both radii twice at the pit -
its coverage cell for cell the near mesh's, two mutants (the rule inverted: a quad on
every near tile; the reached tiles left out) failing the same judge, the stand-in freed at
the rebuild with the near mesh back to the byte and the second stand-in the first one's
bytes; a new claim and a Ring's exit forgetting every stand-in; and a Ring unloaded with
its tail in flight leaving the scheduler idle. Then
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
nothing moves while it is open; the DRIVE page lists the two maps, the world map row,
the five tests in order, the L0 sitting and the skid pad, and each row starts its run
through the mission manager or the licence manager (a human run, the theory card up),
free driving closing the door and starting nothing, the world map row opening the
first-run map layer not forced and `Esc` closing it without opening the garage (4B-6);
the study's catalogue is sound (every lesson a
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
`issues.json` seeded beside `cars.json` (was: `cars.json` alone), the autoload having
seeded nothing with no window; the telemetry kept for good - a recorder of the test's
own started over 25 stored sessions deleting none of them (was: the oldest five), an
index naming sessions whose files were deleted by hand loading clean and the next
session starting, `index.json` deleted and recreated with the ids over from 1 and a
taken name never written over; the bar legend naming every bar; every
key the controls text names in the map, `Tab` among them; the LICENCE page's checklist
ticking exactly the three elements a seeded record holds and all dashes on a fresh one;
no folder dialog ever made; and, the window set to the game's own 1280 x 720, every
garage page walked with `Tab`, `Right`, `Down` and `PgDn`, the world map's three zooms
from the garage's row the same way, the book on `L`, a lesson's
input display with its caption, the mission line and the banners laid out and measured,
nothing reaching past the screen and every row landing inside the scroll area.

And the issue flag (`tests/issue_flag_test.gd`, see [The issue flag](#the-issue-flag)):
the key `V` in the map and on nothing else, plain, the engine's built-ins walked too
(the one modified `V`, the engine's paste, named); a session on the key - the HUD's line
up with `issue-0001`, the counter of no file -, the car driven, the key again - the line
down, the overlay up with its caption, the box empty and focused, the tree paused and the
car frozen for 30 ticks with the throttle down, the key doing nothing while the box is
up -, the text typed character by character through the input pipeline, `Enter` filing
it and the tree running on; the suite's own default path proven untouched (the store off
with no window, the default path refused to read and to write, a session on no path of
its own writing nothing, `user://issues.json` not there after); then, on a file of the
test's own, the binding against the real recorder main.tscn's mission manager makes:
recording to a debug file the record is bound to telemetry with session id 0, honestly,
the range the recorder's own clock at the two ticks and its length the flagger's own
tick count, the car's state the car's at the start in its seven fields, the wall clock
stamped at both ends; `Esc` in the box filing what is typed and the garage opening over
it on the same key; the recorder's own session id set to 42 by hand and the record
carrying 42, read off the recorder; the recorder stopped and the record bound to the
odometer and the wall clock with the telemetry explicitly absent, the same keys the same
ticks apart; the three records read back from the file to the bit with the counter at
4, the id format pinned (`issue-0007`, four digits at least), sixteen faults in a broken
fixture each named by record and field with the default used, records without a usable
id left out by position, a counter behind the ids brought up past them, an id already
taken re-issued from the counter and a free one kept; and a bare HUD in a scene with no
recorder (was the Ring's case; since 2026-09-25 a scene with a car cannot be without one,
so this is a scene with no car), the main scene's recorder recording all the while and not
found, binding to the odometer and the clock and filing to its own file.

And the reset memory (`tests/reset_test.gd`; `R` on a world map returns to the last place
all four wheels were supported on the road - was the spawn everywhere, the user's complaint
on the Ring, 2026-09-23): the pad's car with the flag off and a plain `RoadProfile` never
records, and `R` at the spawn, after a drive through the car's own `reset_car` and after
a drive through a tap of the action puts it on the start line as before; a synthetic
`WorldRoadProfile` built in memory (one straight over a level plane) handed to the pad's
car with the flag on: no pose until it stands on the road, then its x, z and heading as a
yaw-only basis with origin.y exactly 0 (not the car's own transform: `reset_to` stands the
car that height over the road), nothing recorded 30 m beside the road with all four wheels
supported on the plane (the on-road gate, not the wheels), `R` from the field landing on
the road at the recorded pose; the Ring with the flag set by `RoadBuilder` beside the
profile: nothing recorded before the first tick, the settled car recording the pit and the
first `R` landing on the spawn, the scripted follower driving 400 m from Döttinger Höhe on
four wheels every tick with the recorded pose within one tick's way of the car, the stopped
car's recorded pose its own to the millimetre, the pose kept while the car is put in the
field (the spot probed off every road: 30 m to the right there is a side road), a tap of `R`
putting it back there on the road at rest in 1st automatic with the fuel the drive left,
2.4 km from the spawn, and driving on from it; a second Ring instanced fresh holding no
pose and its first `R` landing on the spawn.

And the refuel at a station (`tests/refuel_test.gd`; `scripts/refuel.gd`, the one place in the
game a tank is filled - the driver's "running low on fuel already" on the Ring): the key
is `U`, plain, on no other action with the engine's built-ins walked (`H`, the first
candidate, is the engine's own plain `ui_filedialog_show_hidden`, as the flagger and the
minimap found); the focus table's nine E2 stations all `can("sell_fuel")`, the radius
30 m; the pure core on a synthetic station at exactly (0, 0): near at 10 m and at 30 m
(inclusive), not at 30.001 m or 4 km, the nearer of two, and the real nine at the certified
spawn none within 30 m (E2.4 the nearest at 311 m: the Ring is inert at the spawn); the
Ring scene with the `Refuel` node wired to the car and the HUD, its line a `Label` under the
HUD, hidden at the spawn with nothing filled and the key dead there; the car put at E2.4
through `reset_to` with the tank at 20 L and the engine off: the line up with the exact
text `FUEL STATION near — hold U to fill`, the key held 30 ticks filling the tank to
exactly `FUEL_TANK_CAPACITY_L` on one tick, `fuel_mass` exactly `fuel_l x FUEL_DENSITY` a
tick later, a second hold at a full tank filling nothing more, the six wear marks, the
battery's wear and charge and the odometer set by hand before the fill moving nowhere
toward new, the line down and the key dead again 100 m off; the pad with no `Refuel` node
by name or class, no line, the key filling nothing there and the scene file naming no
refuel; and a fresh car under a bare `Refuel` node filled the same way holding the
identical `fuel_l` and `fuel_mass` bits. Since TROC-1 slice 4 the wired fill is a trade
(was ECON-3's paid fill): with the obligations ledger pointed at a file of the test's own
(and a credits file of 50 wired beside it as the witness that the dormant credits path is
unreached), the car at E2.4 4 L short sees the line `... (barter — you will owe E2.4: fuel
4 L)`, the first tick with the key held fills the tank and writes exactly one record
(`OBL-0001`, creditor `E2.4`, debtor `player`, owed `fuel 4 L`, kind `fuel-voucher`, origin
`refuel`, open) while the credits file's bytes stay as they were; the key held 30 ticks
from 20 L leaves one fill and one more record (`fuel 44 L`), the other 29 ticks writing
nothing; a 0.3 L gap is owed as `fuel 1 L`; a later build's obligations file refuses the
trade on every tick and the tank stays short; the overrides cleared, the fill is free and
the line the old text again, the driver's own `obligations.json` never touched.

And telemetry everywhere (`tests/telemetry_watch_test.gd`; see [Telemetry](#telemetry)),
the never-again fence for "telemetry missing because it wasn't in the scene": with
`FD_TELEMETRY=0` pinned first (no test writes driver data), the `TelemetryWatch` autoload
registered in `project.godot`, standing under the root and connected to the tree's
`node_added`; both strides pinned at 1 (was 5 and 30); every scene under `scenes/` that
instances `car.tscn` found by scanning the `.tscn` files and held equal to the test's own
list (`main.tscn`, `eifel_ring.tscn`: a scene that gains a car must join it); each of the
two loaded whole and settled - the car has exactly one `TelemetryRecorder`, the scene
root's last child, attached to it and idle; on the pad the mission manager's `telemetry`
is that recorder and it listens to the three mission signals, on the Ring no manager;
the HUD's flagger finds nothing recording, then, the recorder switched on to the test's
own `/tmp/fd-TW-telemetry-<pid>/<scene>.jsonl`, finds that recorder; a second under the
throttle key inside an issue flag session started and stopped on the flagger itself: the
record bound to telemetry, session 0 (a debug recording), a real range in the recorder's
own clock (was on the Ring: the odometer and the wall clock, 0.0 - 0.0 s), the car
having driven, the overlay up and the tree paused, filed as `issue-0001` of the test's
own file; the `.jsonl` read back: the `session_start` line naming both strides as 1 at
60 ticks a second, one sample per physics tick with none missed (63 ticks, 63 samples),
the timestamps 0, 1/60, 2/60 ..., every field of the sample, the last sample the car's
own position to the snap with the throttle let go, and the size measured and printed
(309 bytes a sample on the pad, 330 on the Ring - the numbers under Telemetry); the
scene freed, the recorder gone and the watcher holding none. Then a bare `car.tscn`
straight under the root: a recorder under the root with no manager, stopped and freed
when the car leaves the tree (5 ticks, 5 samples in its file), a fresh one when it
comes back, none once it is gone. Last, `user://telemetry` untouched.

And the first run (`tests/first_run_test.gd`; see [First run](#first-run)), 4B-6, with
`FD_TELEMETRY=0` pinned first and the world record on a file of the test's own through
`WorldStore.path_override` (the data folder never read or written): the world store
(`scripts/world_store.gd`) on a file of its own - defaults on no file, a voucher added,
listed unspent, spent once and not twice, a save writing back what it does not know, a
field none of its own reported by name and read as its default, the rental written and
cleared, `user://world.json` resolved through `DataDir`, `active_path` empty headless;
`world.json` in `DataDir.SEEDED_FILES` (was `cars.json` and `issues.json`) and seeded
beside `cars.json`; the pad scene loaded on a fresh (absent) world file with its `WorldMap`
layer up at `_ready` and after, the tree paused, forced - `Esc` and `Tab` doing nothing and
the garage refusing to open under it - the voucher ledger on the licence manager; the
continent listing the one pin (the Ring's bbox, `SkeletonLoader.BBOX`, holding the
school's and the dealership's lat/lon), `Enter` on it listing the region's test centres
from the focus table - exactly one, E8.1 Fahrschule Hecken - and `Enter` on that the yard
card with the measured estate decision and "Go to the yard" as its last row, `Right` and
`Left` zooming in and out; "Go to the yard" writing `spawn_region eifel_ring` and
`test_centre E8.1`, closing the map, running the tree and putting the car on the yard's
start line (x 0, z 100, facing -Z, inside z 30..110), where it stays; a second pad scene
on the record present keeping its map hidden and its car at the spawn, a third with
`pending_yard` arriving in the yard; the L0 sitting sat through the licence manager as
the licence test sits it (the book, key 1, the pilot on the input actions) and PASSED,
`licence_changed` fired ONCE with L0 and the ledger having written ONE voucher (kind car,
class general, dealership E4.1, granted by L0, unspent); a full PRACTICE run passed with
`licence_changed` fired no more and the one voucher still; the ledger alone on a bare
manager granting once on seven `record_element` calls and never a second, unspent or
spent (an L0 or L1 announced after the spend grants none); the rental (`scripts/rental_gate.gd`) started on the licensed car - the gate in
front of the licence manager, a child of the car, ECO pinned with eco's driver, the
record active for 3 600 s - `T`, `G`, `K` and `N` pressed through the car's own ticks
flipping nothing (the car's own program cycle put back the same tick, counted), the hint
up and down, the clutch key delegated to the manager and moving the pedal, the hour on
the tick clock ending the rental by itself with the manager back on the car, the record
cleared and the switches flipping again, the hour up while THE STUDY holds the gate
aside keeping an ended gate that answers as the manager, and a car leaving the tree
ending its rental and clearing the record; taking the car (`scripts/first_car.gd`) - the
voucher spent, `fd_1001`'s entry in the test's `cars.json` read back through the store's
own loaders as a new car's (odometer 0, the FD-1001's 64 L tank, the dashboard, battery,
wear and licence defaults, no problems), the Boxster's entry untouched, `active_car`
`fd_1001`, a rental ended by it, a second take refused, nothing written with the store
off; `configs/cars/fd_1001.json` valid, FD-1001 / `fd_1001`, no trademark; the
dealership on the Ring - the DRIVE page's world-map row and the two dealership rows
greyed at the pit with the hint naming E4.1 in Adenau, live once the car stands at E4.1
(`reset_to`), the loaner row starting the rental on the Ring's car (no manager to stand
in front of; a stale "active" record in the file greys nothing), the take row spending the voucher, ending the rental and writing no entry,
the rows gone after, the CAR page naming the car owned, the world-map row instancing the
layer beside the Ring's garage and `Esc` closing it; and, the window at 1280 x 720, the
DRIVE page with the dealership's rows (greyed on the pad, live on the Ring) and the
map opened from the garage's row and its three zooms walked with `Right` - nothing past
the screen, every row inside the scroll area, `PgDn` reaching the end.

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

- **DRIVE** - free drive on a map (the list holds exactly the maps there are: the
  Factory test pad, which is this scene - free drive simply closes the door; `R` puts
  the car back on the start line - and the Ring, which comes up behind the loading
  screen, see [The async load](#the-async-load-loading-1)), the world map (the first run's layer,
  see [First run](#first-run), opened again from here; `Esc` comes back), the
  dealership's rows while you hold an unspent voucher ("Take the FD-1001 (voucher)" and
  "Take the loaner (1 h, eco)", greyed with the way there in their hint until the car
  stands at the dealership on the Ring), the five handling tests with their objective,
  gold time and your stored best, the L0 licence sitting and the skid pad exam. Every row
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
  reads it from), the car you own on the voucher once taken, and where the car's file is
  kept this run. Read-only.
- **LICENCE** - the licence held, the rank it is (`TEST DRIVER` from L1; the ranks
  beyond are named as not yet playable), every pass recorded, the L0 sitting's checklist
  (`Theory: PASSED` or `Theory: —`, then each practical element `[PASSED]` or `[ - ]`,
  in the sitting's order, from the record), what the next level still takes, and the
  licence book's own text under it - the same book `L` opens.
- **SETTINGS** - the data folder (see [Data location](#data-location): where it is this
  run and why, the folder chosen, a native folder dialog to choose another, a row to go
  back to the default), the sound settings (SOUND-5, see
  [The cat mix as a setting](#sound-sound-1-sound-2-sound-3-sound-4-sound-5): a row that
  flips the household's cat mix and keeps the choice, a row that steps a master trim 0.5 dB
  quieter a press, both taking effect on the next drive), the HUD bar legend (every bar
  and lamp on the HUD, on the study's input display and on the CAR page, with the
  temperatures and shares their colours turn at: `HUD.bar_legend`), and the controls.

The garage reads and never writes: the one thing it changes is the bootstrap file when
a folder is chosen. Nothing of it runs in the headless suite unless the test opens it.

Every page fits the 1280 x 720 screen: a row's hint wraps to the frame's width and a
page taller than the frame (THE STUDY's list, the SETTINGS legend) scrolls, `Down` and
`PgDn` reaching every row and line; the licence book, the lesson caption, the mission
line and the banners fit the screen too (a long banner headline in smaller letters,
never under 40 px), and the menu test fails on anything drawn past the screen's edge.

### First run

The first thing a new driver does (docs/design/4b/first-run-flow.md, 4B-6): with no world
record - `user://world.json` (`scripts/world_store.gd`, beside `cars.json`, seeded with it,
version 1: the driver's `spawn_region`, `test_centre`, `vouchers`, `rental` and
`active_car`; the licence stays in `cars.json` per car) holding no `spawn_region` - the
pad scene opens the **world map** (`scripts/world_map.gd`, the `WorldMap` layer of
`scenes/main.tscn`) before anything else, the tree paused, and `Esc` does nothing there:
there is no world to go back to. Three zooms, `Right` / `Left` between them, `Up` /
`Down` and `Enter` on the rows: the CONTINENT, a plain raster of Europe with one pin per
region built (the Ring's bbox; the rendering source is deferred, no tiles service);
the REGION, its test centres from the region's focus table (the Ring has one, E8.1
Fahrschule Hecken, way 667524970); the TEST CENTRE, the yard card and its last row, "Go
to the yard", which writes the pin's choice and puts the car on the yard's start line,
facing the course. The pad's licence course IS the yard (the flow's §3), so the choice
lands on the pad, in the yard behind the gantry (x 0, z 100, the emergency lane's start);
from another scene the pad is changed to. THE STUDY and the L0 sitting are where they
always were (the garage, the licence book).

The yard's placement, measured on the checked-in drape lattice with the game's own
projection (the E8 rule, ring-region-decisions.md line 118: the pad's course on the
flattest 100 m patch within 300 m of the school under 1.5 % slope, else the industrial
estate by Meuspath and the school building a B9): the school projects to (948.421,
-6156.388), beyond the lattice's northern edge, and the flattest patch in the covered band
within 300 m measures 7.50 % (the orchestrator's coarser scan 8.195 %); within 300 m of
the estate's Porsche house (E3.1, (4414.961, -2550.796)) the patch centred (4515, -2300)
measures 1.092 % (1.54 m of spread over the 141.4 m diagonal, heights 527.97..529.51 m).
The yard goes to the estate at (4515, -2300); the school stays a B9 (recorded in
`scripts/world_map.gd`; the decisions file and the focus table are frozen this iteration).

Passing the L0 sitting grants **a voucher** for one general-class car
(`scripts/voucher_ledger.gd`: it listens to the licence manager's `licence_changed` and
writes `{"kind": "car", "class": "general", "dealership": "E4.1", "granted_by": "L0",
"spent": false}` into `world.json` - once: the manager announces a level only when it
moves and a practice run records nothing, and the ledger never adds a second L0 voucher,
spent or not, besides; `record_pass` and the licence are untouched). The dealership is the Ring's E4,
Autohaus Rausch, way 831174023, unbranded (PUT IN STONE). At it, on the Ring, the
garage's DRIVE page offers **the loaner** - a rental for an hour on the tick clock
(`scripts/rental_gate.gd`: a gate in front of the licence gate that refuses `T`, `G`, `K`
and `N`, pins the program to eco with eco's driver seated and the aids on every tick,
and ends by itself at the hour, when you take a car of your own or when the car leaves
the scene - a scene change or the game closing returns the loaner; deterministic,
pausable) - and **the first car**, "Take the FD-1001 (voucher)" (`scripts/first_car.gd`,
`configs/cars/fd_1001.json`: a serial-number car of the Boxster's shape, Porsche-inspired
and a step stronger, no trademark): the voucher is spent, `fd_1001`'s entry goes into
`cars.json` with a new car's defaults (its own licence: unlicensed, the flow's open
question 1) and `active_car` is written. What is DEFERRED, honestly: the car in the scene
stays the Boxster - `car.gd` is frozen, its config path a const read once, and its
tuning lives in static vars shared by every car in the process - so the swap waits for a
per-instance car; the CAR page names the car owned meanwhile.

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
battery, wear, licence: see [Odometer](#odometer)), the issue store `issues.json` (see
[The issue flag](#the-issue-flag)), the telemetry under `telemetry/`
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
*as* the data folder: `cars.json`, `issues.json` and `telemetry/` go straight into it.

**The first run in a folder copies.** A data folder without the marker file
`.factory-driver-data` is new to the game and is seeded once, in the running game only,
with a **copy** of what the previous location holds: the default `factory-driver` folder
when a custom folder is used, or the pre-4A Godot default
(`<OS data dir>/Godot/app_userdata/Factory Driver`, where everything was kept before this
iteration) - the first of the two that holds any data. `cars.json`, `issues.json`
(was: `cars.json` alone - a fresh folder lost the issue store, fixed 2026-09-24), the
later stores (`world.json`, `campaign.json`, `credits.json`, `obligations.json` and, since
SOUND-5, `sound_settings.json`) and
the whole of `telemetry/` are copied file by file, never over a file the new folder
already has, and
nothing in the old location is moved or deleted: it is left exactly as it was, a backup.
The marker is then written (its text says where the seed came from) and the folder is
never seeded again, whatever the old location holds later. So the first start after
this iteration finds your odometer, fuel, licence and telemetry where they always were,
copied into the new folder, and the SETTINGS page says so. All of it sits behind the
store's own switch (`OdometerStore.enabled`, the telemetry's `should_record`): the
headless suite resolves the folder the same way but seeds nothing and writes nothing;
its own checks run the seed on folders of the test's own.

### Sync: the driver state between machines

The test sessions happen on one machine and the analysis on another, so the data
folder travels: `tools/sync_driverstate.sh` packs the driver state - new/changed files in
`telemetry/` (excluding `index.json`), fresh `issues.json` and `cars.json`, nothing else -
into one bundle, uploads it encrypted through `ird ipfs add --encrypt`, and pulls it
back down on the other side and **merges** it into that machine's data folder. The loop:

```
# on the test machine, after driving
FD_SYNC_PASSWORD=... tools/sync_driverstate.sh push          # prints the CID
# on the dev machine
FD_SYNC_PASSWORD=... tools/sync_driverstate.sh pull <cid>    # merges, reports every decision
```

The data folder is resolved exactly as the game resolves it (`FD_DATA_DIR`, else the
bootstrap file `data_dir.txt` in the default location, else the default folder; a value
that is no absolute folder is reported and the default used), so what the game reads is
what is packed and what is merged into.

**Push remembers what it sent.** The data root's `.sync-pushed.json` records SHA-256
hashes after a successful upload, replaced atomically; a failed upload is retried.
Already-pushed telemetry is skipped, and unchanged telemetry and stores mean no upload
and no storage credits spent. A missing or unusable manifest warns and packs the full
tree. The manifest stays on the pushing machine, outside every bundle.

**A pull never clobbers.** Every telemetry file the bundle holds is copied in only
where the same relative path is not there yet; a file already on this machine wins and
nothing is ever deleted. `issues.json` is unioned by record id: the local record wins
on a collision, the bundle's records that are new here are appended after the local
ones, and `next_issue_id` becomes the highest of the two files' counters and the
highest id present plus one. `telemetry/index.json` is rebuilt from what is on disk
after the merge: `sessions` the ids of every session file present, `next_session_id`
the highest of both indexes' and the highest id on disk plus one, the local `last_test`
and `best` kept (the bundle's are printed so you can decide; with no local index at all,
the bundle's are adopted). `cars.json` stays the local one - the odometer is per-machine
state - and the bundle's odometer per car is printed for the same reason; with no local
`cars.json` at all the bundle's is **not** written either (the game seeds this machine's
own at its first drive; copy it by hand if this machine should start from the other
one's odometer - the Conductor's ruling, 2026-09-24, after the take-it-whole variant
was built and rejected). Every decision is in the output.

**The password.** The bundle is encrypted with the password in `FD_SYNC_PASSWORD`,
which the script never stores, never generates and never prints; it passes it to `ird`
with `--no-input`, so nothing is ever prompted for, and refuses to run without it.
(While `ird` runs, the password sits in its process arguments, visible to the machine's
own process list and to a shell trace; the script keeps it out of its own output and
temp files.)
**Losing the password loses the bundle** (`ird`'s own warning: lost passwords are
unrecoverable) - the same password on both machines, kept where you keep passwords.

### Telemetry

Every drive is written down, **wherever the car is**. `scripts/telemetry.gd` (a
`TelemetryRecorder`) reads the car every physics tick and writes one JSON object per
line - JSON-lines, `.jsonl` - to

```
user://telemetry/<YYYY-MM-DD>/<session>_<HHMMSS>_<context>.jsonl   e.g. 0007_103245_free.jsonl
user://telemetry/index.json
```

(`user://` is the game's data folder, see [Data location](#data-location); the paths are
resolved through it as they are opened.)

**Telemetry everywhere** (2026-09-25). The recorder is put on the car by the
`TelemetryWatch` autoload (`scripts/telemetry_watch.gd`, registered in `project.godot`
next to `DataBootstrap`): it watches the scene tree and, the frame an `ArcadeCar`
enters any scene, appends a `TelemetryRecorder` for it as the scene root's last child
and starts the session. No scene wires recording any more, so no scene can be without
it. (Was: `main.tscn`'s mission manager made the recorder in its `_ready` and
`eifel_ring.tscn` made none - every drive on the Ring went unrecorded, and the 22
issues flagged there have no replay evidence, `docs/issues-analysis-2026-09-24.md`
§1.4. The driver's canon: "car telemetry must be saved regardless where the car is in
the world ... so that we don't ever have the problem of telemetry missing because it
wasn't in the scene".) The mission manager adopts the watcher's recorder for its car
and the recorder listens to its runs; the Ring has no missions, so only free driving
is written there. The suite fences it: `tests/telemetry_watch_test.gd` loads every
scene in `scenes/` that instances the car (the list held against a scan of the
`.tscn` files) and fails unless each car has exactly one recorder attached that
writes when switched on.

**Replay grade.** Both streams are sampled every physics tick - 60 Hz, the full field
set (was: free driving every 30 ticks at 2 Hz, a mission every 5 ticks at 12 Hz). Free
driving gets one file for the session; each mission gets a file of its own, and the
free file pauses while it runs. Measured (the watch test prints it): one sample is
~310 bytes on the pad and ~330 on the Ring (longer coordinates), so a session writes
about 1.1-1.2 MB a minute, 64-68 MiB (67-71 MB) an hour, about 1.1 GB per 16-hour
driving day. Those are free-driving samples; a mission's samples carry the run's own
block (`t_run_s`, `mission` with its progress) and are larger, so a mission file grows
faster than that average. Accepted under the driver's ruling below: nothing is deleted, the driver
clears what they want gone. A lighter hybrid - the core fields every tick, the rich
ones coarser - remains a possible later landing if the driver ever asks; it is not
built. The recorder never presses a key and never touches the simulation: it only
reads. It is on whenever there is a window to drive in, off in a headless run unless
`FD_TELEMETRY=1` says otherwise, and **every session's files are kept for good**: the
game never deletes telemetry. (Was: the last 20 sessions' files were kept and the
oldest deleted when a session started; the driver's decision, 2026-09-24: "let them
grow and let user delete any historical telemetry if they need disk space".)

**Cleaning up by hand.** When disk space is wanted, delete what you like under the
data folder's `telemetry/`:

- the session files `telemetry/<YYYY-MM-DD>/<NNNN>_<HHMMSS>_<context>.jsonl` are safe
  to delete, any of them, whole date folders included: nothing in the game opens a
  session file by name after it is written. An issue record (see
  [The issue flag](#the-issue-flag)) names its session by id, so deleting that
  session's file leaves the issue without its evidence, nothing more;
- `index.json`'s `sessions` list is informational - the ids started so far - and is
  never used to open a file, so a listed session whose file is gone harms nothing:
  the index loads, the next session starts, the list grows on. (The menu test proves
  it: ten files and a whole date folder deleted under an index naming them, the next
  session started clean, no engine error);
- `index.json` itself can be deleted too, and then, honestly, something is lost: the
  game recreates it at the next session start with `next_session_id` back at 1 - the
  ids are reused, but a session file is never written over (a name already taken gets
  `_2`, `_3`, ...) - and the best times and the last test the HUD shows are gone with
  it (`| last: GOLD, best: 28.8 s` reads empty again until the next run). And an issue
  record bound to session 7 then names two session 7s, the old and the new: keep
  `index.json` unless the counter and the bests may go.

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
started so far (every id, for good; was: the ids whose files were kept), the test driven
`last_test`, and per test `best_time_s`, `runs`,
`last_time_s` and `last_medal` (times in seconds, `best_time_s` 0 for a test never
passed) - and that is what the HUD shows back: the idle mission line ends with
`| last: GOLD, best: 28.8 s` and a `PASSED` banner carries
`BEST 28.8 s GOLD — your 4 run(s)` under the medal times. Nothing stored, nothing shown.

### The issue flag

The driver's complaint channel, worked from behind the wheel. Press `V` while driving
and a flagging session starts: the HUD puts `ISSUE issue-0007  recording` over the
odometer, the car's state is taken down and the drive is bound to the telemetry; drive
around showing the problem; press `V` again and the session stops: a box in the middle
of the screen asks what is wrong, the game paused while you type (the garage's own
pause; the box alone keeps processing), `Enter` files it, `Esc` files it as typed so far
("" for nothing - the drive is the evidence; the garage then opens on that same `Esc`,
as it does on any `Esc` with nothing running, and `Tab` or `Esc` closes it). Later you
tell the Conductor "analyse the issues" and the store and the sessions it names are
read together. `scripts/issue_flagger.gd` (an `IssueFlagger` the HUD makes in `_ready`:
the HUD is the one node the pad and the Ring share that holds the car, so the flag
works on both maps) only ever reads the car and polls its own key; `scripts/issue_store.gd`
keeps the records in

```
user://issues.json
```

(resolved through the data folder like everything else): `{"version": 1,
"next_issue_id": 8, "issues": [...]}`, one record per issue:

| Field | What it is |
| --- | --- |
| `id` | `issue-0007`: the file's own counter, four digits at least, never reused; shown before the drive, written after it |
| `status`, `description` | `open` until somebody closes it; the text typed, `""` when none was |
| `started_at`, `stopped_at` | the wall clock at the two presses, the telemetry's own idiom: for finding a drive again, nothing is measured against them |
| `duration_s` | the session's length counted in physics ticks (1/60 s each): the same drive the same number; a pause stops it |
| `binding` | `telemetry` when a recorder was recording in the scene, `odometer+wallclock` when none was (since 2026-09-25 every scene with a car has one - the `TelemetryWatch` autoload's - so this is the recorder switched off: headless, `FD_TELEMETRY=0`; was: the Ring had no recorder, so every Ring issue was bound this way) |
| `session_id`, `t_start_s`, `t_stop_s` | bound to telemetry: THE RECORDER'S OWN session id (its `session_start` line's, its file name's; 0 in a debug recording) and the range inside that session in the recorder's own clock, the samples' `t_session_s`; unbound: 0 and 0.0 - 0.0, explicitly absent |
| `odometer_start_m`, `odometer_stop_m` | the odometer at the two presses [m], on either map: an odometer range is a range anywhere |
| `car_state` | at the start: `x`, `y`, `z` [m], `heading_deg` (left positive), `speed_ms` (negative reversing), `gear` (0 neutral, 1-5, -1 reverse), `odometer_m` - the sample's own fields and snaps |

Behind the telemetry's own switch: on in the running game, off with no window, so the
headless suite reads and writes nothing under `user://` (a test hands the store a file
of its own). What is in the file and is none of its own reads as its default and is
reported by record and field; a record without a usable id is left out, with a word.

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

### Skidmarks (SKIDMARKS-1)

The pad's tyre marks above are a node of `main.tscn`; the Ring had none - driver
issue-0003: "there is no tire markings left on tarmac, this is not only for this zone,
it's everywhere on the green hell". So the marks go everywhere the car goes, the way the
telemetry does: the `MarksWatch` autoload (`scripts/marks_watch.gd`, registered in
`project.godot` after `TelemetryWatch`) puts a `MarksLayer` (`scripts/marks.gd`, the node
`Marks`) under the scene root of every car that enters any scene, one deferred call after
the car, in front of the `TelemetryRecorder` (which stays the root's last child), and frees
it when the car leaves. A scene root that already carries a `TyreMarks` node for the car -
the pad - gets no second layer; the Ring gets this one.

Every physics tick (priority -1: after the bubble, with `Surfaces`, before the car) the
layer reads the car's public slip numbers per axle and, for each wheel of an axle past a
threshold whose contact point (`global_transform * WHEEL_CONTACT_POINTS[i]`) the scene's
`Surfaces` node classifies as **road** - grass, gravel, a field and the forest floor never
mark; a scene without the node is all road - trails a streak on the tarmac: a quad every
0.5 m of the contact patch's way over the ground, from where it was to where it is, the
way it went (a locked wheel's streak is as long as the car slid). Three triggers, each an
intensity 0..1 from its onset to its solid point, a quad's alpha the largest over the way
it covers, 0.7 at solid: **lateral** - the slip angle past 1.5 times the axle's own peak
(`FRONT_` / `REAR_PEAK_SLIP_ANGLE`: 0.165 / 0.15 rad), solid at 3 peaks; **wheelspin** -
a driven axle's slip ratio past `DRIVE_SLIP_RATIO` x 1.15 (0.2875: the clutch limit and
TCS hold a launch under 0.25), solid at 1; **lock** - a slip ratio past 0.5 either way
(ABS holds 0.15; a locked wheel reads -1), solid at 1. Normal cornering, an ordinary
launch, a full pedal with ABS and straight driving lay nothing.

A quad lies on the ground the profile shows (`road_profile.elevation_height` at the
contact point: the `RingProfile`'s height on the Ring, bit-exact on a road), 2.5 cm up to
clear the road mesh, tilted to the grade along it and the crossfall across it, the tread's
width (0.20 m front, 0.24 m rear), dark rubber with its alpha; it fades in a line over
**180 s** of physics time and its place is then free; the pool holds **4 096** (about 2 km
of streak; four wheels sliding at 20 m/s lay 160 a second) and, full, lays over the
oldest. One `MultiMesh`, colour and alpha per quad, no node per quad, no collision shape;
the colours are refreshed in stride, a 32nd of the pool a tick. A reset (`R`, `reset_to`)
ends every streak without drawing one from the old place to the new and **keeps** the
quads: the rubber is on the road. Purely visual and deterministic: nothing writes the
car, the `Surfaces` node or the profile; no random, no wall clock; every quad's origin is
snapped to 1 mm and its alpha to 0.001 as it is laid, and the same drive lays the same
records to the bit.

`FD_MARKS` in the environment switches it: `0` off everywhere (no node, no quad), `1` on
even with no window, unset on in the game and off headless - so the test suite sees no
layer unless a test asks (`tests/marks_test.gd` does, for its own scenes, and restores).

### Sound (SOUND-1, SOUND-2, SOUND-3, SOUND-4, SOUND-5)

The game was silent (backlog U-1). The first sound goes everywhere the car goes, the way the
marks do: the `SoundWatch` autoload (`scripts/sound_watch.gd`, registered in `project.godot`
after `ShellsWatch`, before `MissionRunner`) puts a `SoundNode` (`scripts/sound.gd`, the node
`Sound`) under the scene root of every car that enters any scene, one deferred call after the
car, in front of the `TelemetryRecorder` (which stays the root's last child), and frees it
when the car leaves; a scene root already carrying a sound of its own for the car would get
no second one (no shipped scene carries any audio today: the guard is future-proofing).

No asset and no scene: the node holds four looping `AudioStreamPlayer`s and a pool of four
one-shot thump players (SOUND-3; was three players), each loop a two-second
16-bit buffer built in code at first need and shared (SOUND-2; was a half-second buffer on a
2 Hz grid, the flat-6's 45 Hz root and its half-orders whole on no grid coarser than the
0.5 Hz the 2 s give) - the engine a flat-6's order stack, the crank's 3rd / 6th / 9th / 12th
orders at 45 / 90 / 135 / 180 Hz at idle (the firing frequency rpm / 60 x cylinders / 2 is
the root) with weak half-order sidebands at 22.5 / 67.5 / 112.5 Hz, the boxer's unequal
exhaust paths (was 56 Hz and its first harmonics: a single cylinder's stack), the surface a
body layer of twenty prime-spaced partials (62..226 Hz, the structure-borne band the cabin
hears) under a broadband noise layer of 61 partials every 25 Hz over 500..2000 Hz, the
tread-impact band of rolling noise, both with spread phases (was the primes alone), the
skid (SOUND-4) friction noise and no tone - a band of sliding-rubber hiss, 46 partials over
300..1300 Hz in the buffer, twice as dense over 700..1300 Hz as under it (the tilt toward
where rubber hisses), placed off any even grid (no two closer than 13 Hz) and stored in a
shuffled order so the spread phases make a hiss and not a click train (the band holds
99.95% of the buffer's energy and 2000..4000 Hz holds nothing over the 16-bit rounding's
floor, both measured) - with the baked-in 9 Hz amplitude modulation of 0.3,
kept - the tread blocks through the contact patch at the wheel's rate (was, SOUND-2: one
self-excited tone at 2000 Hz with the 2800 Hz overtone at 1.0 / 0.25, band-limited grit of
51 partials over 1500..4000 Hz at an RMS of 0.15 and the same modulation - the
literature's squeal; was, SOUND-1: a steady chord around 800 Hz, a howl); every partial a
whole number of cycles over the buffer, so the loops are seamless, and sums of sines only:
the same bytes every build. SOUND-2 re-tuned the three buffers against
`scratch/sound-2-references.md` (real recordings, the engine order analysis, the
tyre-noise and squeal literature) after the driver's verdict on the first drive - "The
tires sound is unbearable, very high... otherwise the game is unplayable" - and touched
nothing else. SOUND-4 is the squeal's hotfix after the driver's second verdict - "tire
squick is still very unnatural and extremely high, cat very scared": two tonal squeals
landed and both were rejected, and the driver's ear outranks the literature, so the squeal
stopped being a tone; only the skid buffer's tables and its ceiling changed, the mapping
functions, the other buffers and every other channel are what they were. The ruled target
- a band around 400..1800 Hz, no dominant 2-4 kHz content - names the band as HEARD at a
solid slide, and the kept pitch mapping multiplies whatever the buffer holds, so the buffer
is authored one register below it (the first draft's 400..1800 Hz buffer band would have
been heard at 600..2700 Hz at solid); and the old 2000 / 2800 Hz tone pair, which that
draft kept as a faint 0.12 / 0.03 trace, is removed entirely - at the mapped pitch its
residue would have been heard at 3000 / 4200 Hz at solid, inside the screech band the
driver rejected twice. Every physics
tick (priority -1, before the car's own tick, one state) the node reads the car's public
fields and maps them, every value snapped to 0.001: **engine** - `pitch_scale` 1.0 at
`IDLE_RPM` to 8.0 at `REDLINE_RPM` from `engine_rpm` (the 3rd order's true 8:1 span, 45 Hz
to 360 Hz; was 2.5; never under 0.5 below idle, was 0.25), `volume_db` -18 dB at idle with the
pedal up, 4 dB more at the limiter and 6 dB more at full `throttle_pedal` (-8 dB at full
load), muted with `engine_running` false; **surface** - a level from the three surface
inputs the `Surfaces` node feeds (`front_` / `rear_surface_grip`, `surface_rolling_decel`)
and `forward_speed`: the speed wash alone on tarmac, the rolling drag and the grip deficit
scaled by motion on top (silent at rest on any surface: the rumble is the tyres rolling),
-6 dB at the ceiling, the pitch 0.9 at rest to 1.1 at 50 m/s (was 0.8 to 1.2: broadband
noise is barely pitched); **skid** - the intensity is
`MarksLayer`'s own triggers called per axle (never re-declared: a threshold change moves
marks and squeal together), gated per wheel by the same road-only surface rule, muted at no
intensity and under 1.5 m/s, -12 dB at solid (SOUND-4; was -4, the loudest thing in the
mix - a solid slide is now a sound a person can talk over), the pitch rising 0.85 to 1.5
with it (was 0.9 to 1.15) - since SOUND-4 the playback rate of a noise band, not a note:
the buffer's 300..1300 Hz friction band is heard at 255..1105 Hz at the onset and brightens
to 450..1950 Hz at solid, a harder slide a brighter hiss (was "nearly an octave, the real
squeal's span": SOUND-2's tone swept 1700..3000 Hz). Purely a
reader: nothing writes the car, the `Surfaces` node, the `Buildings` node or the profile, and
the car's telemetry samples of the same drive are byte-identical with and without the node.

SOUND-3 adds three layers, the smallest honest version of each, after the driver's line
(`docs/design/user-thoughts-economy.org`: "it matters in which environment the car is, if
it's in a tunel, within the buildings or in open nature, the sound is different"). The
three earlier channels' mapping functions keep their signatures; the environment is its own
offset layer on top.

**Wind** - a fourth loop, `Wind`, its own buffer: broadband pseudo-noise alone, 31 partials
every 20 Hz over 100..700 Hz with the golden phase spread, whole cycles over the same 2 s
grid so the loop is seamless, the same bytes every build. Its level is `forward_speed`
alone, either way, squared: `clamp((speed / 50)^2, 0, 1)`, muted under 5 m/s, -10 dB at the
ceiling (ambience: under the engine's -8..-18 and the rumble's -6), the pitch fixed at 1.
THE SPEED LAW IS AUTHORED: `scratch/sound-2-references.md` carries speed laws for tyre noise
only (tread impact with the square of the speed, air pumping with the fourth power; its
lines 23-24) and nothing for aerodynamic noise, so the quadratic is the implementer's
choice, not a measured one. The wind is never surface-dependent - the same on tarmac,
gravel or in the air; it reads no surface field.

**Impacts** - one-shot thumps on the car's REAL collisions, through the only honest seam:
the car (`scripts/car.gd`, frozen) calls `move_and_slide()` once per tick and reads its
velocity back, so at the node's tick (priority -1, before the car's) the car's
`get_slide_collision_count()` / `get_slide_collision(i)` hold the PREVIOUS tick's slide -
one tick stale, deterministic, real contact and not a deceleration proxy. A contact whose
normal's dot with UP is over 0.7 is the floor (the pad's ground plane, the ring's slab),
skipped; a wall contact's closing speed is `|n . v|` with `v` the velocity THE NODE READ ONE
TICK EARLIER - after `move_and_slide` the car's velocity is already slid along the wall and
its normal component is exactly 0 at every impact (the rehearsal probe measured 0.000 on the
shed; the previous read gave 19.70 against a 19.75 m/s approach), so this tick's velocity
would never thump. The intensity is the closing speed's share of 20 m/s, nothing under 1 m/s
(a gentle nudge is silent); a cooldown of 15 physics frames (0.25 s at 60 Hz) since the last
thump, so a sustained rail scrape thumps at most four times a second, and only when the car
pushes into the rail again with a normal component over the gate (a scrape's slid velocity
has none). The thump plays on the next of the four pooled players round-robin (`Thump0`..
`Thump3`, children of the node itself: the scene root still carries no audio of its own) at
-2 dB plus `linear_to_db(intensity)`, snapped; `impacts_fired` on the node counts them. The
burst is built in code too: 8192 samples (371 ms) of a 90 Hz sine under knock partials with
the golden spread, an exponential decay of 60 ms and a 2 ms attack, NOT looping - it plays
once and stops, so the whole-cycles rule is the loops' alone. The pad's cones NEVER thump,
and that is correct by the physics, not a gap: they are `RigidBody3D`s on layer 4
(`scripts/pad_cone.gd`, `1 << 2`), the car's mask is 1, the server never pairs them -
"move_and_slide neither slows nor deflects for a cone", the pad drives them through
`TestPad`'s own `bump()`. The rails (the bubble's F1 rail chunk bodies on layer 1 when
active within 80 m, `scripts/physics_bubble.gd`), the trunk chunk bodies and the pad's sheds
(layer 1) do pair, and thump.

**Environment v1** - "within the buildings vs open nature", read-only over the ring's
building shells (`scripts/buildings_shells.gd`: `shells`, one dictionary per building with
its `position`, 2839 on the Ring, under the scene root's child `Buildings`). The node looks
that child up by name on the scene root and never calls `BuildingsShells.of()` - that
static CREATES the node where Road, Terrain and Forest exist and would start a heavy build in
a scene that was never to have buildings; nothing here creates or writes anything. Every 30
physics ticks (0.5 s at 60 Hz, tick counting, never the wall clock) the horizontal distance
from the car to the NEAREST shell is scanned linearly over a `PackedVector2Array` of the
shell positions copied once when the shells are first seen non-empty (no allocation per
scan, no spatial index: 2839 distances every half second is trivial); an absent or empty
shells array (the pad, a bare car, the Ring while its build still runs) is fully open.
`openness = clamp(d / 60 m, 0, 1)`, and two level trims, pure functions pinned by the test:
the wind down by 4 dB x (1 - openness) (sheltered among buildings), the rumble up by 1.5 dB
x (1 - openness) (walls throw some of it back); the written `volume_db` is the base plus the
trim, snapped, and a muted base stays muted (a trim never wakes a silent channel). On a scene
without a `Buildings` node the openness is 1 and both trims 0: the pad's sound is
bit-identical to SOUND-2's. Not in v1, honestly: no low-pass or equalisation and no reverb
bus (a real early-reflection tail is future work), and TUNNELS DO NOT EXIST anywhere in the
world yet (no tunnel geometry is built), so the driver's "in a tunnel" case is documented as
not-yet-existing rather than faked.

`FD_SOUND` in the environment switches it exactly as `FD_MARKS` does: `0` off everywhere,
`1` on even with no window, unset on in the game and off headless - so the test suite sees
no node unless a test asks (`tests/sound_test.gd` does, for its own scenes, and restores).

**The cat-aware mix (CAT-AWARE-1).** The driver's ruling of 2026-10-01: "the tire squeke is
still scaring my cat. can we try to do all sounds with cat awareness / wellbeing in mind."
All sounds are henceforth designed with cat wellbeing in mind. The SOUND-2/3 realistic mix
stays the default of the code; `FD_CAT=1` in the environment switches a sound node to the cat
mix, read once per node when it is made, exactly as `FD_SOUND` is read at each attach - any
value but `1` (unset, `0`, anything else) is off. `run.sh` exports `FD_CAT` as `1` where the
caller has not set it: the cat mix is the household default, and `FD_CAT=0 ./run.sh` gives
the realistic mix (launching Godot directly, without `run.sh`, is realistic too).

The mechanism is one shared audio bus, `Cat`, that `SoundNode` creates and owns - the
AudioServer's buses are global and saved nowhere, so the first cat-mode node creates the bus
and the last one leaving the tree removes it; no other node, scene or file touches it. The
bus carries one `AudioEffectLowPassFilter` (`CAT_LOWPASS_HZ`, 3000 Hz), set once at creation
and never touched per tick, and every one of a cat-mode node's eight players is routed to it
when it is made. On top of the bus two channels are treated, pure functions over the
unchanged mapping. The squeal plays at x0.6 pitch - since SOUND-4 the buffer's 300..1300 Hz
friction band at 180..780 Hz (153..663 Hz at the onset, 270..1170 Hz at solid), the whole
band below the cat's peak region at every intensity and still unambiguously a slide cue (was the
2000 Hz fundamental at 1200 Hz, 1020 to 1800 Hz across the mapped range) - under a ceiling
6 dB lower (-18 dB at solid against the realistic -12; was -10 against -4, before SOUND-4
took the ceiling down). Both cat constants were kept through SOUND-4: the landing that
changed the sound did not also loosen the protection; whether -18 dB is still loud enough
a slide cue under a full-load engine (-8 dB) is a question for the driver's ear. The thumps
play under a ceiling 8 dB lower (-10 dB at a full impact, was -2) and the burst at x0.8
pitch, so the 2 ms attack stretches to 2.5 ms and the transient's edge softens. The engine,
the rumble and the wind keep their character and their mapping to the bit: their content
sits under the cutoff (the engine's orders reach 1440 Hz at the redline, the rumble's noise
layer 2200 Hz at its fastest), and since SOUND-4 so does the squeal's: honestly, the
3000 Hz low-pass now cuts nothing of it (the cat-pitched friction band tops out at
1170 Hz and the buffer holds no tone above it) and
stays as the guard over whatever else would sit above (was: what the low-pass cuts is the
top of the squeal's grit).

The reasoning is the domestic cat's audiogram (Heffner & Heffner 1985, Hearing Research
19:85-88): the cat's best hearing sensitivity sits in the low-to-mid kHz region, with
high-frequency hearing reaching tens of kHz - the 2-8 kHz band SOUND-2's realistic squeal
occupied (2000 and 2800 Hz tones, 1500..4000 Hz grit, 3000 and 4200 Hz at solid) is exactly
the region the pitch-down and the cut protect, and sudden loud transients startle. SOUND-4
re-centered the squeal in the DEFAULT mix too: the realistic friction band is 300..1300 Hz
in the buffer and the mapped pitch of 1.5 plays it at 450..1950 Hz at a solid slide - under
that region at every intensity, nothing above 2 kHz in any mode (the buffer is authored one
register under the heard target for exactly this reason) - while the cat mix (270..1170 Hz
at solid) sits lower still. Honestly: v1's shape is authored from the
literature's shape, not measured on a cat; `CAT_LOWPASS_HZ`, `CAT_SKID_PITCH`,
`CAT_SKID_DB_TRIM`, `CAT_THUMP_PITCH` and `CAT_THUMP_DB_TRIM` in `scripts/sound.gd` are
one-line knobs. The guarantees: with `FD_CAT` unset the sound is the realistic mix byte for
byte (every written volume and pitch, every buffer, every player on the default bus, no bus
created, no AudioServer call); `FD_SOUND=0` wins - no node, so no cat mix and no bus; and the
test suite's baseline is unaffected (the suite never reads `run.sh`, and
`tests/sound_test.gd` takes `FD_CAT` off for its realistic sections, sets it for its cat
battery and restores it). The node's `state()` dictionary carries sixteen values (was twelve
-> the cat mode, the squeal's written pitch and volume under it and the thump's pitch), and
`describe()` ends in `cat mix on` / `cat mix off` (was: ended at the ticks).

**The cat mix as a setting (SOUND-5).** The driver's ask (plan task A675B305): the cat mix
was an environment variable alone; make it a garage setting that persists, with a master
trim. The store is `scripts/sound_settings.gd` (`SoundSettings`), one small file beside
the rest of the data, `user://sound_settings.json`, on the obligations ledger's discipline
(the atomic tmp+rename write, a later build's version refused and never written over, a
tolerant reader that reports and invents nothing, the `path_override` test seam, the
`OdometerStore.enabled` gating - headless the store names no file and writes nothing):
`{"version": 1, "cat_mix": false, "master_trim_db": -3.0}` at most, exactly those
fields - `cat_mix` is written only once the driver has chosen it in the garage, and
`master_trim_db` is clamped to -24..+6 dB and snapped to 0.001 on every load and set. The
file is seeded with the rest of the data folder (`DataDir.SEEDED_FILES`, seventh, after
`obligations.json`; was six files). The SETTINGS page gains two rows under a SOUND
heading: `Cat mix: ON — the squeal down-pitched, thumps softened (the cat's hearing)` /
`Cat mix: OFF — the realistic mix` (`Enter` flips what a sound node made now would play
and keeps it; until a choice is made the label adds `not chosen here yet: as launched,
FD_CAT ...`, and a caller's `FD_CAT=0` over a chosen ON is named as the override) and
`Master trim: +0.0 dB — one offset on every sound` (`Enter` is 0.5 dB quieter a press,
down to -24, then round to +6: the one row walks the whole range). Both take effect on the
next sound node made - the next drive, the next scene - not on the one already playing;
a status line under the rows says so. Gated (no window), the rows are shown with the
defaults and greyed.

The precedence is the ruled shape with the Conductor's amendment of 2026-10-03 on the
absent-file corner, one pure function, `SoundNode.cat_mode_effective`, applied once per
node in `_ready` beside the `FD_CAT` read: `FD_SOUND=0` wins over everything (no node, no
bus, no trim - the profile never turns sound on or off; `SoundWatcher.should_attach` is
`FD_SOUND`'s alone, untouched); NO CAT MIX CHOSEN (no file, a file without `cat_mix`, a
file that cannot be trusted) is today's environment semantics exactly - `FD_CAT=1` the
cat mix, unset or anything else the realistic mix, byte for byte as CAT-AWARE-1 landed it
(the file comes into being only when a sound row is pressed, so every run before that and
every direct godot launch behaves as the game ships; the brief's cat_mix-default-true was
amended away); a cat mix CHOSEN: `FD_CAT` present and anything but `1` is the caller's
override (necessarily caller-set: `run.sh` fills only an unset `FD_CAT` with `1`), the
realistic mix, the file ignored; `FD_CAT` unset or `1` lets the file decide. So the
setting exists to turn the household's cat mix OFF from the garage, persistently, under
`run.sh`'s default. The master trim applies always, the environment never overrides it:
one offset on every volume the node writes to a player - the four loops and the thumps -
through `trimmed_db`, trim-then-floors (snapped, never under `MUTE_DB`, a muted channel
staying muted); the node's own fields and `state()` stay the mapped values, so at a trim of
0 every written value is the mapped one to the bit and both mixes are what SOUND-4 landed.
The mix knobs (`CAT_SKID_PITCH`, `CAT_SKID_DB_TRIM`, `CAT_THUMP_PITCH`,
`CAT_THUMP_DB_TRIM`, `CAT_LOWPASS_HZ`) and the cat functions are unchanged; `describe()`
ends in the trim (`master trim +0.0 dB`). `tests/sound_test.gd` pins the store, the
twelve precedence corners (`FD_CAT` unset / `0` / `1` / exotic x the file absent / on /
off) with `FD_SOUND=0` over them, the file-present corners on bare cars and the trim;
`tests/menu_test.gd` the rows; every earlier sound pin stands without a seam - headless
the store reads "no cat mix chosen" and the environment decides, as it always did.

### Weather (WEATHER-1)

The Ring has four skies and rain (`scripts/sky_set.gd`; the canon, docs/art-direction.md,
Weather and Sky: "Rain is particularly useful for this aesthetic. Don't turn it into a
modern weather showcase. Use: darkened asphalt, simple rain streaks, grey sky, slightly
reduced visibility, car reflections on road, taillight reflections, occasional spray. The
wet road should become noticeably more reflective." and "Blue sky with soft clouds. Grey
overcast. Orange sunset. Dark blue evening."). `FD_WEATHER` in the environment picks one,
read once when the Ring's sky is applied:

```sh
FD_WEATHER=rain /opt/homebrew/bin/godot --path .
```

| `FD_WEATHER` | what to expect |
|---|---|
| unset or `0` | the clear day - today's look to the bit: nothing copied, nothing added, `SkySet.applied` without a `weather` key, `describe()` the same line |
| `overcast` | a grey plate (horizon 0.70 / 0.72 / 0.75), the sun a weak cool-grey light at its 45° (energy 0.45, no disc on the plate), a flatter, brighter ambient with half of it the sky's, the haze table x 1.2 reaching the sky at 2 350 m |
| `sunset` | the sun 10° up and warm orange (1.0 / 0.62 / 0.36, energy 0.8), long shadows, a warm dim ambient, an orange horizon (0.90 / 0.60 / 0.42) under a deep blue top, the haze tending to the orange horizon; the clear day's haze table |
| `evening` | the sun all but set (4°, energy 0.2, cool), a dim bluish ambient, a dark blue plate (top 0.05 / 0.08 / 0.20, horizon 0.16 / 0.22 / 0.38); the clear day's haze table |
| `rain` | the overcast plate darker and greyer (horizon 0.56 / 0.58 / 0.61, sun energy 0.3), "slightly reduced visibility" (the haze table x 1.4, all sky at 1 900 m - still nearly two kilometres of landscape, never a fog wall), the wet road, the rain streaks and the reflections |

Anything else is refused with an error naming the value and the day stays clear. The
sun's bearing is the region table's 210° in every state (a sunset sets where the sun
stands) and the shadows stay on. A state runs on top of the clear path: the sun's
elevation, colour and energy, the ambient trio, the plate's four colours. The plate is
never written in place - the scene's Environment, Sky and sky material are shared by every
instance of the packed scene, so a state takes its own copies; a clear scene loaded after a
weather scene is the clear day. The haze keeps its mechanism: its colour is re-read from
the new plate's horizon (it greys under cloud and warms at sunset by itself) and the
engine's one exponent is re-fitted, by the same `fitted_curve`, through the state's table -
the clear amounts (0.15 at 300 m, 0.45 at 800 m) times the state's multiplier. One exponent
can only follow a table whose amounts grew if the table's end came in, so a state names
both (x 1.2 with 2 350 m, x 1.4 with 1 900 m: each within the clear day's 0.03 fit
tolerance at 50 / 200 / 500 / 1 000 m), and the nearer end is the reduced visibility.

Rain adds three things. **The wet road** (`RoadBuilder.wet_road()`, called by the sky one
deferred call after it is applied; a scene without a `Road` is skipped): a copy of the
asphalt material on every strip with the tint darkened (0.55 -> 0.34) and the roughness
scalar lowered (1.0 -> 0.45). The roughness map stays and the scalar multiplies it, so the
polished ruts (0.58 -> 0.26) shine before the lane centres (0.84 -> 0.38) - the water
stands in the ruts. **The streaks**: 360 thin upright quads (0.02 x 0.5 m, unshaded,
half-transparent, no texture) in one code-built `CPUParticles3D` under the `Sky` node,
born on a 40 x 40 m plane 20 m over the car and falling 25 m straight down at 12 m/s; the
field rides with the car, position only, each physics tick, and hides when there is no car.
No unseeded random: the emitter's seed is fixed and every randomness parameter is 0.
**The reflections**: the rain's own Environment copy turns on the engine's screen-space
reflections, so what is on screen - the car, its taillights, the tree line - is mirrored in
the wet road; the sky plate and the sun mirror through the lowered roughness alone.

Not in v1, parked: **wet grip** - the road is as grippy wet as dry. `scripts/surfaces.gd`
and `data/regions/eifel_ring/surfaces.json` are frozen, and a wet surface class needs a
freeze ruling of its own. No puddle geometry, no drips on the camera, no wind-driven rain
(the streaks fall straight down), no spray. Nothing in any state touches the car or the
physics; the pad (`scenes/main.tscn`) has no `Sky` node and no weather. The test suite
runs with `FD_WEATHER` unset; `tests/dressing_test.gd` takes it off for its clear scenes,
sets it around each weather scene and restores it.

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
the tank) is an error in the log and a full tank. One thing in the game refuels the car:
the gas station (`scripts/refuel.gd`: on the Ring, within 30 m of a placed E2 station, `U`
held fills the tank to capacity through this same setter, nothing else restored; was: nothing,
"a gas station or a canister will, both world content to come"). `reset_to` (`R`) keeps the
tank as it finds it - resetting is not refuelling - and tells the file nothing; the
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

## Mission ladder

The garage's sixth page, MISSIONS, shows driver-wide campaign progress. L1 FACTORY
ENTRY enrolls Junior; FD-12, FD-22 and FD-33 promotion hooks grant Test Driver, Chief
and terminal Ace credentials with their reward-car entitlements. Rewards remain
disabled rows until their car configurations arrive. Promotion retries are unlimited.

ML-1 ships the ladder machinery. ML-2 populates it: the first five production
episodes load from `configs/missions/` — FD-01 Simple Slalom (first six pad cones,
26 s), FD-02 S-turn (five broad gates, 32 s), FD-03 360 Spin (compass circuit on
the skid pad's edge, 15 s), FD-04 Open Road Slalom (all fourteen cones, 28 s) and
FD-12 1st Promotion Test (the full grading line, 59 s). The pad stands in for
Weissach, Corsica and the Autobahn; FD-02's damage disqualification becomes
skipped-gate failure and FD-03's yaw/handbrake requirements become a positional
circuit, each noted in its briefing. Unlock chain FD-01→FD-02→FD-03→FD-04→FD-12
on the Junior rank; finishing FD-12 in time promotes to Test Driver with the RS
2.7 entitlement (an entitlement row, still without a car configuration). Each
config carries a shipped `input_script` — the mission's built-in scripted test
drive the headless suite replays; garage entries start unscripted for the driver.
Invalid definitions and their dependents are still excluded; medal bands were
estimated from the certified SLALOM pace and tuned from the scripted runs.
`campaign.json` in the chosen data directory keeps version, rank, results
(best time, medal, attempts), credentials and reward entitlements separately from
the numeric licence and car records. Writes use a temporary file and atomic rename;
`FD_TELEMETRY=0` keeps campaign play in memory. Aborts record nothing.

A mission may carry an optional flat `surface_override` (SNOW-1: `grip`,
`rolling_drag`, `bump`, applied by the runner to the car's three existing
surface inputs for the episode and restored at its end; FD-14 Snow Testing
drives on packed snow this way, grip 0.42 / drag 1.5 m/s², see
`docs/ml5-implementation.md`). SNOW-2 adds the optional fourth key
`ground_tint`, display-space RGB in [0, 1]: at the episode's start the runner
takes the pad's own ground material (`TestPad.get_ground_material()`, unshared,
built fresh per pad), captures its albedo, writes the tint converted once with
`Color.srgb_to_linear()` (the colour-space rule above: a code-set albedo is
read as linear) in place, re-asserts it every tick and restores the captured
albedo on pass, failure, abort and teardown. FD-14's pad ground reads as packed
snow, `[0.82, 0.84, 0.87]`, for the episode only. Ring-venue grounds are not
tinted by this mechanism: a ring mission carrying the key validates and applies
nothing.

### The obligations ledger (TROC-1 slice 1)

The TROC ruling's store (decisions.org `85BE93B5` and `16036083`,
`docs/design/troc-redesign.md`): `scripts/obligations_ledger.gd` keeps `obligations.json`
in the data directory, behind the same telemetry switch as every store (`FD_TELEMETRY=0`
writes nothing). A record is `creditor`, `debtor`, `owed`, an optional `kind` hint,
`origin`, `status`, `redemptions` and `transfers`; the counterparties are opaque ids, the
player one among them. Settlements are one-shot: exactly one redemption closes an
obligation, a second is refused. A transfer reassigns the creditor and keeps the history.
There are NO totals anywhere: the log IS the ledger, and the open views are derived,
never summed. The store is proven by `tests/obligations_test.gd`; slices 2-4 wire the jobs
page, the dealership barter and the fuel-for-obligation to it.

### Job rewards are obligations (TROC-1 slice 2)

The garage's seventh page, JOBS, reads TROC (was: a `CREDITS: <balance>` heading, a
"Payments received" line and `<n> credits` on every row). Each of the four courier jobs
under `configs/jobs/` names its `poster` (the dispatch desk at the job's origin station:
`DISPATCH-E2.4`, `DISPATCH-E2.2` for two of them, `DISPATCH-E2.3`), its `poster_owed`
(what the desk will owe the driver on delivery, in the desk's own words) and its
`poster_offers` (the tip it offers: a rare material, a dealership voucher, tuna); the
schema requires the first two on every paid job and refuses all three on a ladder
mission. A PASSED job creates one open record in `obligations.json` — creditor `player`,
debtor the poster, `owed` the poster's text, kind `delivery`, origin
`job:<id>/episode-<n>` — once per episode (the runner's single-shot guard, unchanged: a
retry, a listener or a second finish creates nothing; a refused write may be retried
once); a failed, timed-out or aborted job creates nothing, and with `FD_TELEMETRY=0`
nothing is written. The result line ends "owed by <poster>: <owed>". The page lists the
jobs with the poster, what they will owe and the tip in each row's hint, then the
driver's open obligations: "Owed to you by <debtor>: <owed>", "You owe <creditor>:
<owed>", or "Nothing owed to you or by you yet."

What this slice does not do, honestly: `poster_offers` is validated and displayed and
consumed by no system yet; `reward_credits` stays in the job configs, still validated
and still what marks a job as paid work, but it is inert — nothing displays or pays it
(the job briefings still close with their old "Pay on delivery: <n> credits" sentence,
authored text this slice did not rewrite); nothing redeems an obligation yet. Credits
are spent nowhere now (was: paid fuel, until slice 4 landed the station's trade, below;
and the dealership, until slice 3 landed its barter) — the credits ledger stays wired
and dormant, written by nothing in the game.
`obligations.json` is seeded with the rest of the data folder (`DataDir.SEEDED_FILES`,
closing slice 1's gap).

### The dealership barters (TROC-1 slice 3)

The CAR page's dealership trades by barter against authored exchange-terms per car (was:
ECON-3's price table, a `DEALERSHIP  —  CREDITS: <balance>` heading and a `BUY — <car> —
<n> credits` row per car). The design's mapping row (`docs/design/troc-redesign.md` §3):
"`Dealership` price table (... `price_credits` per car, all `basis: AUTHORED`) ->
EXCHANGE-TERMS per car: what the dealer accepts". Each entry of `configs/dealership.json`
gains `dealer` (the desk's opaque counterparty id) and `terms` (a non-empty menu of what
the desk accepts: `accepts`, the desk's own words; `settle`, how the garage settles it;
an optional whole `count` of 1 or more, absent meaning 1). The terms as landed:

| car | desk | accepts | settle | count |
|---|---|---|---|---|
| `fd_1073` | `DEALER-EIFEL-01` | "one held obligation" | `obligation` | 1 (absent) |
| `boxster_986` | `DEALER-EIFEL-02` | "one held obligation" | `obligation` | 1 (absent) |
| `fd_2000` | `DEALER-EIFEL-03` | "two held obligations" | `obligation` | 2 |

Every term and every desk id is AUTHORED (the source docs carry no exchange-terms; each
`basis` says so). A count is how many records the desk asks for, not a price: no
obligation is worth a number and nothing is summed. `scripts/dealership.gd` stays a
strict reader (a missing or empty `dealer`, `terms` that are no list or empty, a term
that is no object, has no `accepts`, an unknown `settle`, a `count` that is not a whole
number of 1 or more, or an unknown key — each refuses the entry and is reported); the
table's version stays 1 (config and reader move together; an older build refuses every
entry on the unknown keys, sells nothing and writes nothing).

The BARTER row (`BARTER — <car> — for <the desk's words>`) is live where a world record
exists and the driver holds, as creditor, at least the open obligations the binding term
asks for (the term settled by `obligation` asking for the fewest; an obligation the desk
itself owes the driver is not counted — the ledger never hands a debt to its own debtor).
Its hint reads "The dealer accepts: <terms>." and what is held ("You hold 2 open
obligations.", "…: 1 more needed.", "You hold no obligations the desk accepts."). Enter
runs `Garage.barter_car`: the first N held obligations in the log's order are transferred
to the desk (`ObligationsLedger.transfer`, origin `dealership:<car_id>`), then the
ownership write is exactly the credits path's (a fresh entry in `cars.json` where the
store is kept, `active_car` in `world.json`, a rental ended). If a transfer is refused
mid-trade, or the store's side fails after the transfers, every committed transfer is
handed back (origin `dealership:<car_id>:reverse`) and the trade is refused; the log is
append-only, both transfers stay in the record's history. Ownership by trade is read from
the log (`Garage.traded`: a transfer to the car's desk with that origin on a record the
desk currently holds); the page then shows `OWNED … traded here for <terms>` and
`SELECTED … traded at the dealership`. With `FD_TELEMETRY=0` (no obligations ledger) the
terms are listed as text and nothing can be traded.

The credits BUY row is DORMANT, not deleted (ruling `16036083`, slice 3's point: the
credits path goes dormant behind a flag; it overrules the design doc's proposed retire,
which itself noted "The driver may prefer dormancy; it is one flag either way"):
`Garage.CREDITS_BUY_ENABLED` is `false`, so the heading carries no balance and no BUY row
renders; `buy_car`, `price_credits` and the credits-log ownership scan are intact,
tested by direct calls, and a car owned by trade is refused there as "already owned".

Honest scope: the fresh-driver credits gap is NARROWED, not closed — barter with held
obligations is now the earn-to-own path (deliver a job -> hold the poster's obligation
-> trade it for a car), while paid fuel still charged credits until slice 4 landed the
station's trade (below). The trade
takes the oldest held obligations; the driver does not choose which. The transferred
obligation stays open with the desk as its creditor (the poster now owes the desk):
nothing redeems it yet. `voucher` is validated settle vocabulary that NO shipped term
uses and the garage does not settle: nothing grants dealership vouchers yet (the job
board's "one dealership voucher" tips are display-only, and the first-run voucher is the
`fd_1001` car voucher honoured at E4.1) — deferred past slice 4, which landed the fuel
trade and no voucher granting. The job briefings still
close with their authored "Pay on delivery: <n> credits" sentence. A bought or traded
car is selected in the records only; live vehicle swapping is still pending.

### Fuel for obligations (TROC-1 slice 4)

The gas station trades fuel for an obligation (was: ECON-3's paid fuel, 2 credits a litre
spent before the fill). The ruling (decisions.org `85BE93B5`): "fuel stations trade fuel
for delivery obligations (matching the Cat Matrix rule: 10% social stations free, others
barter)"; the design's §5 item 4 (approved by `16036083`): "refuel.gd's wired-ledger seam
becomes a wired-trade seam: with an obligations ledger on, holding U at a station creates
... an obligation named by the station's terms; the grace seam (free fill where nothing is
wired) survives. The 10% social rule stays parked." On the Ring, within 30 m of a placed
E2 station with the obligations ledger on, the line reads `FUEL STATION near — hold U to
fill (barter — you will owe E2.4: fuel 44 L)` (or `... (barter — the tank is full)`), and
the first tick with `U` held opens ONE record in `obligations.json` before the tank is
filled: creditor the station's own id (`E2.4`), debtor `player`, owed `fuel <n> L` with
the litres the gap rounded up to the whole litre (`Refuel.fill_litres`: the old price's
rounding rule, kept on the litres), kind `fuel-voucher`, origin `refuel`, status open.
Trade before fuel, all or nothing: a create the ledger refuses (the store gated, the file
a later build's, a write that fails) is no fuel and the tank stays short. The tank is
full after the first tick, so holding the key leaves one obligation, not thirty. Nothing
is priced and nothing is summed: a 44 L fill and a 1 L fill are two records, each named
in the station's words, never added. No credit moves: the obligation IS the debt, owed to
the station and redeemable against whatever it later accepts. The grace seam survives:
without a runner or with the store gated (`FD_TELEMETRY=0`, no override) the fill is free
and the line is the bare `FUEL STATION near — hold U to fill`, exactly as before.

The credits path is DORMANT, not deleted (the slice-3 ruling's shape, `Garage.CREDITS_BUY_ENABLED`):
`Refuel.CREDITS_FUEL_ENABLED` is `false`, so `wired_ledger()` is null whatever the credits
store's wiring, no price reaches any line and no spend is written; `LITRE_PRICE_CREDITS`,
`fill_cost` and `hint_line` stay, pure and tested. With the flag on, ECON-3's paid fuel
returns wherever a credits ledger is wired and no obligations ledger is (the trade wins
where both are: TROC is the economy). What this slice does not do, honestly: nothing
redeems an obligation at the pump (the design's "create-or-redeem" is create only here:
a held delivery obligation cannot yet buy fuel), nothing redeems one anywhere else
either, the 10% social stations stay parked with the cat ecology, and no system grants
dealership vouchers. The fresh-driver gap is closed at the pump: fuel costs nothing the
driver must first earn - it leaves them owing the station.

### The car's exterior (CARS-1 slice 1)

The car is no longer eight boxes: `scenes/car.tscn`'s `Body` node is an instance of
`assets/meshes/car_boxster_986.glb`, a Blender-authored 1997 Boxster 986 exterior with
the soft top up (the driver's rulings: the shipped red kept, the top up, no plate, dark
opaque glass - the interior and the driver are the next slice; a free procedural
interpretation, no reference photos). It is eight meshes, one material each, direct
children of `Body` - `Paint`, `Glass`, `SoftTop`, `Trim`, `Headlight`, `Taillight`,
`Indicator`, `Exhaust` - 3 224 triangles, no textures. Nothing in the handling reads it:
`scripts/car.gd` still pitches, rolls and heaves `Body` and places the four wheels of
`scenes/wheel.tscn`, and the X-ray (`scripts/xray.gd`) fades every one of the eight. The
shape is sized to the physics - the wheel arches stand 0.06 m over the tyres where
car.gd puts them, and the fenders reach x 1.02 because the game's track is wider than the
real car's.

The source of truth is `assets/blender/scripts/car.py` (Blender 5.2.2 LTS, headless;
every dimension a commented constant); the .glb it writes is committed and regenerates
byte-identically:

```
blender -b -P assets/blender/scripts/car.py
godot --headless --path . --import
```

`assets/blender/README.md` has the construction, the material table and the known limits.
