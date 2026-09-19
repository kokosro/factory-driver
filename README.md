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
| Brake; keep holding at a stop to reverse | `Down` or `S`   |
| Steer left / right                      | `Left` / `Right` or `A` / `D` |
| Handbrake (hold mid-corner to slide)    | `Space`         |
| Shift down / up (switches to manual)    | `Q` / `E`       |
| Toggle automatic / manual gearbox       | `M`             |
| Reset the car to the start line         | `R`             |

While reversing, `Up` / `W` brakes. The handbrake loosens the rear tyres, so steering while holding it swings the tail out. The HUD shows speed in km/h (prefixed with `R` in reverse). Above it, the tach line shows engine RPM and the gear (e.g. `3000 rpm | G4`, with `M` in manual) and turns red near the redline. The gearbox starts in automatic and goes back to automatic when you reset the car.

### Driving feel

The car uses a custom arcade controller in plain GDScript (`scripts/car.gd`), not Godot's
vehicle physics. Every handling parameter lives in the commented `DRIVING FEEL TUNING`
block at the top of that file.

Slides and spins: tyres saturate (`TYRE_SLIDE_DECEL`), so a car thrown sideways keeps
its momentum instead of stopping dead. A stability assist (`SLIDE_YAW_DAMPING`) keeps
ordinary handbrake slides tame and catchable, but fades once the nose points more than
~25 degrees away from the direction of travel (`SPIN_COMMIT_ANGLE`), so a committed
flick goes all the way round. A tap of handbrake with steering gives a tidy 90 degree
turn; holding both from ~90 km/h gives a 180; from ~110 km/h and up, steering the other
way while the car travels backwards and releasing the handbrake past half way completes
a 360.

The test pad is built to make motion readable: noise-textured asphalt with repair
patches, ground ticks every 10 m, a chequered START / FINISH zone, painted skid pad
rings with reference posts, tall perimeter pylons and cones that topple when hit (they
never slow the car).

### Tests

```sh
tests/run_tests.sh
```

Runs a headless import, then `tests/smoke_test.gd`, which loads the main scene and
drives the car with simulated input, then the handling tests below.

### Handling tests

The third step of `tests/run_tests.sh` runs `tests/handling_test.gd`: a scripted driver
takes the real car through four tests on the pad, one after the other from a fresh
start, and prints `PASS name` / `FAIL name` plus a metrics line for each. If a test
cannot be passed, either the driver or the car is not set up properly.

| Test          | Course                                                       | Passes when                                                              |
| ------------- | ------------------------------------------------------------ | ------------------------------------------------------------------------ |
| `SLALOM_TEST` | the 14-cone slalom line right of the straight                | at most 1 gate missed (wrong side, too wide, cone knocked over), in 45 s |
| `SPIN_180`    | the straight, handbrake turn from ~90 km/h                   | ends within 35 degrees of 180, net forward displacement positive         |
| `SPIN_360`    | the straight, full spin from ~125 km/h                       | ends within 35 degrees of 360, net forward displacement positive         |
| `STOP_BOX`    | the hatched box on the straight, 150 m from the start        | stopped with the whole car inside the box, braked from 72 km/h or more   |

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
