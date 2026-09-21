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
| Cycle camera: chase, cockpit, front, overhead, wheel | `C` |
| Look back (hold)                        | `B`             |
| Look left / right (hold)                | `,` / `.`       |
| X-ray view on / off                     | `X`             |
| Start handling test 1 - 5 (mission mode) | `1` - `5`      |
| Abort the running test / close its result | `Esc` (`R` also aborts) |

Look left / right are on `,` and `.` (the `<` / `>` pair, under the right hand's reach from the arrows and next to `B`'s row): `Q` / `E` are the gearbox, `B` is look back. Hold to glance to that side, let go and the view comes back: the chase camera swings ~65 degrees round the car, in the cockpit and the bonnet view the head turns ~60 degrees; the overhead and wheel views have no side to look to. It is a glance, not a view of its own (`C` still cycles the same five), both keys at once look straight ahead, and look back wins over either.

The brake always brakes: it slows the car to a stop whichever way it rolls and holds it there, and never turns into reverse by itself. Reverse engages only on a fresh press of `Down` / `S` while the car is stopped; in reverse, `Down` / `S` is the throttle and `Up` / `W` the brake, and a fresh press of `Up` / `W` while stopped (or once the car rolls nose-first, as out of a J-turn) engages forward again. Holding `Up` / `W` through the stop also engages forward after a moment and drives away in one motion (the J-turn exit); reverse still needs a fresh press. The handbrake loosens the rear tyres, so steering while holding it swings the tail out. The HUD shows speed in km/h (prefixed with `R` while reverse is engaged), with two thin pedal bars beside it (green throttle, red brake: how far the driver's feet really have the pedals, see The driver below) and a thin fuel bar under them. Above it, the tach line shows engine RPM and the gear (e.g. `3000 rpm | G4`, with `M` in manual, `comfort` or `eco` on the automatic's comfort and eco programs and `STALL` once the engine has stopped) and turns red near the redline; over it sit the two driver aids' lamps, `TCS` and `ABS`, dim unless an aid is switched off (see The driver's controls below). The gearbox starts in automatic and goes back to automatic when you reset the car.

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
64 L (`fuel_l`, `fuel_fraction()`), every reset fills it, the running game keeps the
level from one session to the next (see Odometer below), and the thin bar lying under
the pedal bars shows it: amber under 15 %, red under 8 %. With the tank dry nothing
burns: the engine runs down, stops running, and stays down until there is fuel again
(a reset fills the tank and starts the engine; see the starter below).

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
starts a stopped engine: it puts a car there that is ready to drive.

### Tests

```sh
tests/run_tests.sh
```

Runs a headless import, then `tests/config_test.gd`: every car config under
`configs/cars/` read the way the car reads it and put through the validation, in
seconds, so a broken config fails the suite there and not 25 minutes in. Then
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
loads 5 L starts with 5 L, their 3.7 kg and a red bar - a reset fills it, the file is not
told.

And the car's config, ahead of the mass checks: the file passes its validation, the car
that read it runs the certified torque curve to the bit, a config without any of its
optional keys is still a car, and a required key left out or a torque anchor that is NaN
is refused by name - by the validation's functions alone, never read into the running
car.

### Handling tests

The fourth step of `tests/run_tests.sh` runs `tests/handling_test.gd`: a scripted driver
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

Between sessions the metres live in `user://cars.json` (`scripts/odometer_store.gd`), an
entry per car so the garage can add its own:

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
the tank) is an error in the log and a full tank. Nothing refuels the car but `reset_to`
(`R`, a test starting): that fills the tank as it always did and tells the file nothing -
the next save on the 45 s cadence writes the tank as it then stands, which after a reset
is the full one the car has. The headless suite and the certified handling runs read
nothing: every car there starts on the config's full tank (and every handling run begins
with a `reset_to` anyway).
