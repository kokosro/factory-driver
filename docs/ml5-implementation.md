# ML-5: Test Driver to Chief

Twenty-two production missions are playable. FD-13 through FD-22 are all
`test_driver` missions. FD-13 requires FD-12; FD-14 through FD-21 each require
their immediate predecessor. FD-22 explicitly requires **all nine** results
FD-13 through FD-21, so a partial or edited save cannot skip the rank's work.
The Chief promotion and reward are committed with the passing FD-22 result.

## Course adaptations

All ten episodes use the existing pad and its Boxster physics. This deliberately
keeps measured courses together on a known venue; Ring side roads are available
but are not needed for these adaptations. Every JSON briefing and provenance
names the source venue and vehicle and discloses police, traffic, vehicle damage
and opponents as absent. No damage prohibition, AWD/prototype/custom tuning,
AI competition, cargo attachment or crash/restart-direction penalty is invented.

- **FD-13 Car Delivery 3:** Auvergne and its 1997 Boxster become the curved
  west-side pad dispatch/handover course. FD-08's route is shortened to a
  finish at (0, -380). `delivery_return` denotes destination handover, not
  coming back to dispatch. Crossings do not require a stop. Limit: 153 s.
- **FD-14 Snow Testing (SNOW-1):** cold tyres on packed snow replace the
  former cold-tarmac stand-in. The pad still stands in for Alps and its
  Boxster for the 1999 996 Carrera 4 Cabriolet; AWD and freezing ambient
  weather are not simulated. Six surveyed cones and gates at x=14/26 remain
  unchanged. `cold_tyres: true` resets both existing axle temperatures to 0
  for human starts and scripted retries, then the existing thermal model
  warms them. The surface applies grip 0.42 and rolling drag 1.5 m/s².
  Bump 0.03 m is validated but undelivered on the pad. Limit: 69 s.
- **FD-15 Klaus' Delivery:** pad stands in for Zone Industrielle and the 1994
  993 Cabriolet. Pickup at dispatch (0, -5), warehouse `zone` drop at
  (20, -250), return through the eastern side to `delivery_return` (0, 18),
  then finish (0, 41). This is genuinely an outbound-and-return route;
  drop and handover are ordered crossings, without a cargo or stopping
  simulation. The source's restart-direction issue is absent. Limit: 187 s.
- **FD-16 Billy's First Day:** six surveyed pad cones and alternating gates
  stand in for the Weissach demonstration in the 1997 993 Carrera S.
  Cone contact fails; Billy is not an actor. Limit: 39 s.
- **FD-17 Billy's Challenge:** source is a head-to-head race, not a delivery
  or slalom. The pad's curved west route replaces Pyrénées; the Boxster
  replaces the 1998 996 Cabriolet. Solo clock target **90 s**, explicitly
  authored because the source supplies no limit. Billy awaits E-6 traffic.
- **FD-18 Boxster Test:** first ten surveyed cones, tight alternating gates
  and finish at (20, -246) approximate the complex Weissach prototype test.
  The pad Boxster substitutes for the 2000 Boxster S without prototype
  tuning. Limit: 39 s.
- **FD-19 Team Race 1:** scenic pad tour replaces Pyrénées in the 1998 996
  Cabriolet. Solo clock target **120 s**, explicitly authored because the
  source supplies no limit. Rolf, Frank and Billy await E-6 traffic; no
  finishing-position claim is made.
- **FD-20 Capture The Flag 2:** Auvergne/1994 993 Coupé becomes a different
  twelve-cone route from FD-09, crossing the west side, slalom area and
  eastern return before the yard finish. Targets sampled along the scenic
  drive use the same 2 m swept-contact radius as FD-09. The existing ML-4
  current-target-only props and HUD reveal the next flag; the HUD substitutes
  for radio guidance. No `cone_hit` fault: these cones are targets. No crash
  direction penalty. Limit: 385 s.
- **FD-21 Billy's Stunt Course:** compact pad layout replaces the Weissach
  serpentine in the 1998 996 Cabriolet. Five route gates join two separate
  compass-gate circuits centred at (-22, -36) and (-22, -62). Seven cone
  constraints guard the spots throughout, including approach and finish.
  The two source spin spots are represented, while the source's full-size
  hairpins and opposite-corner finish are compressed. As in FD-03/10, yaw
  and handbrake use are not scored. Overlapping route/circuit geometry uses
  ordered current gates without `skipped_gate`; cone contact still fails.
  Billy is a clock target, not an opponent. Limit: 43 s.
- **FD-22 2nd Promotion Test:** fourteen-cone pad grading course replaces
  Corsica, with the Boxster standing in for the earned 1973 Carrera RS 2.7.
  Rolf's retirement briefing and Chief reward are retained, with a solo
  clock slalom substituting for his head-to-head race. Selecting `fd_1073`
  does not swap the live physics. Limit: 120 s.

## SNOW-1 surface mechanism and freeze decision

`surface_override` is optional and flat: `{ "grip": 0.42,
"rolling_drag": 1.5, "bump": 0.03 }`. This deliberately deviates from the
planning brief's name-keyed map. FD-14 runs on `main.tscn`, which has no
Surfaces node; modifying a Surfaces dictionary there would do nothing. The
frozen Surfaces name list also refuses `snow`. Neither `scripts/surfaces.gd`
nor the region surface table, car, profiles, scenes or other certified files
are changed. The flat object is a hook for future weather missions; a
name-specific ring extension is deferred until a mission needs it.

MissionSchema requires exactly those three keys and finite numeric values,
uses `Surfaces.GRIP_MIN/MAX` for the inclusive grip bounds 0.2–1.0, and
requires non-negative drag and bump. MissionRunner captures the car's original
front/rear surface grip and rolling deceleration after `reset_to`, beside
cold-tyre setup, then writes the override directly to these three existing
physics inputs. It reasserts them every physics tick: the ring's Surfaces
writer has priority -1, then the runner autoload at 0 precedes the scene's
car at 0. On the pad the runner is the only surface writer.

The packed-snow basis supplied for SNOW-1 is road mu approximately 0.30 versus
summer tarmac approximately 0.85–0.95 (an approximate ratio 0.35–0.40).
Grip 0.42 lies in the specified driven packed-snow band 0.35–0.45, below the
existing lowest named surface, forest_floor at 0.48. The Conductor’s final
ruling sets packed-snow rolling drag to 1.5 m/s²: packed snow has lower
rolling resistance than the 2.0–3.0 loose/deep, unpacked snow band, and 1.5
sits just below gravel’s 1.6. Bump 0.03 m remains a validated parameter:
bump delivery requires the existing ring-only Surfaces + RingProfile
micro-profile machinery, built by `Surfaces.swap_profile`. This flat car-input
override does not extend that machinery; no pad bump is simulated or claimed.

`_cleanup()` restores the captured car's three exact original values and
clears the capture. Both passed and failed `finish()` calls route through it,
including timeout, cone contact and skipped gates. `abort()` also routes
through it, including reset/abort input and invalid-car detection in the
physics tick. `_exit_tree()` uses the same teardown. A freed captured car is
safely skipped; the capture still clears. With no override capture, cleanup
performs no surface write, preserving the previous behavior and any external
writer's values. Capturing the car reference also ensures teardown targets
the original car if `configure()` has since been called.

SNOW-1 test fixtures use a per-process directory under `TMPDIR` (or `/tmp`),
removed at completion. The single existing ladder marker now checks strict
schema validation, start/retry and sticky surface inputs, restoration on
pass/failure/abort, inert no-override cleanup, and identical cold-tyre braking
runs from 20 m/s. It also requires FD-14's shipped snow drive to pass and its
actual measured time to agree with the recorded provenance and medal formula.
No suite marker or frozen test runner is changed; the suite stays at 34.

### SNOW-1 final ruling and measurement (2026-09-29)

The final override is grip **0.42**, rolling drag **1.5 m/s²**, bump
**0.03 m**, with `cold_tyres: true`. Cold rear-axle full-throttle traction
is approximately **2.143 m/s²**, above total resistance
**COAST_DECEL 0.15 + 1.5 = 1.65 m/s²**, so the car launches.

History: drag 2.5 m/s² was refused as undrivable (2.143 < 0.15 + 2.5 =
2.65 m/s²); the script and medals are re-measured at the final ruling.

The shipped control trace passes on a fresh pad Boxster in **44.983333 s**
at fixed 60 Hz with cold tyres and the final snow override. Exact ceiling
multipliers produce **gold 48 s / silver 57 s / bronze 68 s**; the source
limit remains **69 s**, retaining the unmedalled completion interval.

The external recorder tuned steering and accelerator press/release timing
through the existing HandlingTests controls. Short accelerator releases limit
wheelspin on snow; the tighter line stays within the unchanged gates and
cones. Its recorded samples were compacted by removing repeated identical
commands and retaining their elapsed frame delays: 718 shipped samples use
only `steer_deg`, accelerator `press`/`release`, `when.after`, and final
`steer_free`. The shipped replay has no live waypoint or traction controller,
no injected starting velocity, and no car or scoring changes. A fresh replay
of the final JSON reproduced the pilot time before the full ladder run.

The identical cold 20 m/s braking runs measure **25.332740 m** on road
and **41.237179 m** on final snow. The unchanged assertion requires snow
greater than road × 1.05; the measured increase is approximately **62.8%**.

The final headless ladder process exits **0**, with all 33 shipped drives
passing and all **1487 checks** passing (the original 1420 plus all 67
SNOW-1 checks). Verbatim verdict:

```text
MISSION LADDER TEST PASSED: 1487 checks
```

`git diff --check` is clean. Round 2 changes only the FD-14 mission JSON,
`tests/mission_ladder_test.gd`, and this document; the round-1 runner and
schema mechanism remains unchanged.

Invocation matches the ladder step in `tests/run_tests.sh`, with engine
logs and per-process persistence redirected outside the repository:

```sh
FD_TELEMETRY=0 TMPDIR="$SNOW_TMP" /opt/homebrew/bin/godot --headless --fixed-fps 60 --path /Users/kokos/games/factory-driver --log-file "$SNOW_TMP/ladder-engine.log" --script res://tests/mission_ladder_test.gd
```

The macOS sandbox emits its existing `get_system_ca_certificates`
diagnostic; physics and assertions continue with no script/parse errors.
That engine `ERROR:` still matches the frozen wrapper’s error filter, so this
assertion pass is not a claim of a clean full-suite gate. The host orchestrator
retains full suite gates, commit and push. Temporary recording tools and logs are
removed after inspection.

## SNOW-2 ground tint (the visual at FD-14's venue)

SNOW-1 left FD-14 driving on snow over dark asphalt. SNOW-2 closes that gap
with one optional fourth key in `surface_override`: `ground_tint`, an array
of exactly three finite numbers in [0, 1], display-space RGB. The three
existing keys stay required; MissionSchema refuses a non-array, a wrong
length, a non-number, INF/NAN or out-of-range element and accepts the edges
0.0 and 1.0. FD-14 ships `[0.82, 0.84, 0.87]`, an authored packed-snow
bluish white (no source document carries a colour); the basis is recorded in
its `provenance.adaptation`, the briefing says the ground is tinted, and
`provenance.medals` is untouched.

Mechanism (`scripts/mission_runner.gd`): at `start()`, only when the mission
carries `ground_tint`, the runner finds the venue's pad through the same
lookup `environment_matches()` uses (`find_child("TestPad")` under the car's
scene) and takes its ground material through the pad's own accessor
`TestPad.get_ground_material()`. The original `albedo_color` is captured
before the first write; the display tint is converted ONCE with
`Color.srgb_to_linear()` at the application site (the OFFROAD-1 rule: Godot
reads a code-set albedo as linear, so a display colour written raw reads too
bright; the pad's own `COLOR_ASPHALT` is authored raw-linear and is not
converted) and written as the albedo. The tint is re-asserted every physics
tick beside the surface re-asserts and restored in `_cleanup()`, the single
teardown reached from `finish()` on pass and failure, `abort()` and
`_exit_tree()`. Without the field the runner performs no pad lookup and no
material write; an override without `ground_tint` still delivers the surface
inputs alone.

The shared-material question, investigated and settled: `test_pad.gd` keeps
a `_materials` cache, but that cache serves cones, paint and the grid through
`_get_material`; the ground material is built fresh per pad instance in
`_build_ground_surface()` and is referenced only by the ground mesh's
`material_override` and the pad's private var, and the skid disc builds its
own separate asphalt instance. The ground material is therefore unshared and
is tinted IN PLACE, restored by writing the captured original back. It is not
duplicated and reassigned: the frozen smoke test pins that the ground mesh's
override is the accessor's instance. The ladder test proves the non-leak
directly, sweeping every StandardMaterial3D under the pad (material overrides
and mesh surface materials, the skid disc's paler asphalt and the cone and
paint materials among them) before and after the tint and asserting all but
the ground keep their albedo, and that the ground mesh keeps the same
instance. No frozen file or scene is changed: `test_pad.gd`, `car.gd`,
`surfaces.gd` and `main.tscn` are untouched.

The boundary: ring-venue grounds are NOT tinted by this mechanism. A ring
mission carrying `ground_tint` validates but applies nothing (no TestPad in
the car's scene, so no ground material is found) until ring-ground machinery
exists. A pad torn down under a live tinted episode is safe: the runner's own
reference keeps the material valid, the freed car is what the next tick
notices, and the abort restores the captured albedo and clears the capture.
The tint is visual only: FD-14's shipped drive still passes at its recorded
provenance time, which the ladder test pins to 1e-6.

## Chief reward

`CampaignStore.REWARD_CARS` adds `"chief": "boxster_986"`. Existing
`PROMOTIONS["FD-22"]` and `REWARDS.chief` remain unchanged. The committed
Chief entitlement itself is ownership, derived by `owns_car`; there is no
second flag, purchase or voucher. This also works for an existing consistent
Chief save without a migration write.

The existing generic MISSIONS reward builder automatically gains an enabled
OWNED—TAKE row. Five added CAR-page lines mirror the `fd_1073` precedent:
show the owned Chief reward, add its TAKE callback, and identify its selection.
The existing `take_car` creates missing condition data from FirstCar defaults
and the Boxster's own tank capacity, preserves existing condition, selects
`world.active_car`, and ends a rental. Tests use isolated explicit paths.

No new car config is needed: `configs/cars/boxster_986.json` is the explicitly
approved stand-in for the Customised 1997 Boxster. No unsupported custom tuning
is claimed. Live vehicle swapping remains deferred under the `car.gd` freeze.

## Medal measurement and verification

ML-5 measurements (FD-14 updated for final SNOW-1), 2026-09-29 on
Godot 4.7.2, headless fixed 60 Hz, through
MissionRunner/HandlingTests in `tests/mission_ladder_test.gd`. Each pass uses a
freshly instantiated pad car and the JSON's shipped `input_script`. Bands are
`ceil(measured × 1.05 / 1.25 / 1.50)` for gold/silver/bronze. Every JSON records
the measurement, method and run provenance. Source limits are preserved;
FD-17/19 disclose their authored limits and record a null source limit.

| Mission | Measured seconds | Gold | Silver | Bronze | Limit |
|---|---:|---:|---:|---:|---:|

| FD-13 | 33.450000 | 36 | 42 | 51 | 153 |
| FD-14 (cold tyres, final packed snow) | 44.983333 | 48 | 57 | 68 | 69 |
| FD-15 | 53.300000 | 56 | 67 | 80 | 187 |
| FD-16 | 21.166667 | 23 | 27 | 32 | 39 |
| FD-17 | 35.116667 | 37 | 44 | 53 | 90 |
| FD-18 | 21.166667 | 23 | 27 | 32 | 39 |
| FD-19 | 64.500000 | 68 | 81 | 97 | 120 |
| FD-20 | 64.500000 | 68 | 81 | 97 | 385 |
| FD-21 | 28.500000 | 30 | 36 | 43 | 43 |
| FD-22 | 27.816667 | 30 | 35 | 42 | 120 |

FD-21's bronze band is exactly the 43 s source limit. The schema permits this;
there is no unmedalled `complete` interval for that episode. The scoring test
therefore samples all three medals, omitting only that nonexistent interval.
The suite otherwise retains all four success-band checks.

FD-13/15/17 reuse the recorded FD-08/11 traces for their adapted delivery/race
routes; FD-16 reuses FD-01, FD-18 the shortened FD-04 trace, FD-19/20 FD-11,
and FD-22 FD-07. The original cold-tarmac FD-14 and FD-21 steering traces were recorded with a temporary
waypoint pilot under `build/ml5/`, then replayed through unchanged HandlingTests
commands (`hold_speed`, `steer_deg`, `when.after`, final `steer_free`). Their
pilot times were 37.500000/28.483333 s and their historical shipped replays
were 37.516667/28.500000 s, at cruise speeds 6 and 7 m/s respectively. The
SNOW-1 trace and measurement above supersede that cold-tarmac FD-14 record.
FD-20's twelve target positions were sampled at 3, 8, ... 58 s on the FD-11
trace and rounded to centimetres, then verified with its own shipped replay.
The recorder is not part of runtime or the committed change.

The existing test marker covers discovery/schema validation for all twenty-two
configs, rank/limit/provenance/pad bounds, every sequential unlock, each FD-22
prerequisite independently, cold human/scripted starts and retries, ordinary
heat preservation, both flag courses' reveal/contact/cleanup mechanics,
stunt second-circuit constraints, real-car passes for all twenty-two episodes,
real-car failures for every new episode, medal boundaries, best-time and
attempt persistence, and Chief ownership/TAKE/condition/reload/replay behavior.
The expanded matrix exceeds the approximate 700-check target because it
retains the previous checks and applies the full production scoring matrix
and flag-mechanics proof to the added missions. No new suite marker is added;
`tests/run_tests.sh` remains unchanged at 34 markers.

The original ML-5 implementation used tooling, fixtures and logs under ignored
`build/ml5/` (historical evidence only; SNOW-1 uses external temporary storage). A
project wrapper symlinks the real project directories and adds the system TLS
bundle `/etc/ssl/cert.pem`. Runs use `FD_TELEMETRY=0` and explicit repo-local
`--log-file` paths. Initial attempts to change Godot's custom user-directory
setting were sanitised and denied by the sandbox; those attempted directories
were not created. The final wrapper uses the existing user directory but
writes no driver data; all enabled test persistence uses repo-local overrides.
The full host gate, final commit and push are left to the orchestrator.

Original ML-5 selected checks (historical, before SNOW-1):

- `CONFIG TEST PASSED`: all **3** car configs.
- `MISSION LADDER TEST PASSED: 873 checks`: **380** more than the 493-check
  baseline, including **22** real-car passes and **10** new real-car failures.
- `git diff --check`: clean.

Historical ML-5 evidence: `build/ml5/config-final.log` and `build/ml5/ladder-final.log`.
Commands, run from the repository root:

```sh
FD_TELEMETRY=0 godot --headless --path build/ml5/env --log-file /Users/kokos/games/factory-driver/build/ml5/config-engine.log --script res://tests/config_test.gd
FD_TELEMETRY=0 godot --headless --path build/ml5/env --log-file /Users/kokos/games/factory-driver/build/ml5/final-engine.log --fixed-fps 60 --script res://tests/mission_ladder_test.gd
```
