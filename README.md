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

### Tests

```sh
tests/run_tests.sh
```

Runs a headless import followed by `tests/smoke_test.gd`, which loads the main scene and
drives the car with simulated input.
