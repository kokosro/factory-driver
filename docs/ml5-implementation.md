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
- **FD-14 Snow Testing:** explicit **COLD-TARMAC** variant of the Alps test in
  the 1999 996 Carrera 4 Cabriolet. Six surveyed cones, gates at x=14/26,
  and a slower cold-tyre steering trace. A validated optional boolean
  `cold_tyres` sets both existing axle temperature fields to 0 at mission
  start, for human driving and scripted retries alike. Tyres then warm under
  the existing model; ordinary starts preserve heat, as `reset_to` already
  does. This does not simulate freezing ambient weather, snow or AWD. The
  frozen Surfaces implementation has a fixed surface-name list and reads
  `data/regions/eifel_ring/surfaces.json`; the table is also frozen for this
  task. A proper snow surface remains a separate follow-up. Limit: 69 s.
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

Measured 2026-09-29 on Godot 4.7.2, headless fixed 60 Hz, through
MissionRunner/HandlingTests in `tests/mission_ladder_test.gd`. Each pass uses a
freshly instantiated pad car and the JSON's shipped `input_script`. Bands are
`ceil(measured × 1.05 / 1.25 / 1.50)` for gold/silver/bronze. Every JSON records
the measurement, method and run provenance. Source limits are preserved;
FD-17/19 disclose their authored limits and record a null source limit.

| Mission | Measured seconds | Gold | Silver | Bronze | Limit |
|---|---:|---:|---:|---:|---:|

| FD-13 | 33.450000 | 36 | 42 | 51 | 153 |
| FD-14 | 37.516667 | 40 | 47 | 57 | 69 |
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
and FD-22 FD-07. FD-14/21 steering traces were recorded with a temporary
waypoint pilot under `build/ml5/`, then replayed through unchanged HandlingTests
commands (`hold_speed`, `steer_deg`, `when.after`, final `steer_free`). Their
pilot times were 37.500000/28.483333 s; the table correctly records the shipped
replays, 37.516667/28.500000 s. Cruise speeds are 6 and 7 m/s respectively.
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

All local tooling, fixtures and logs live under ignored `build/ml5/`. A
project wrapper symlinks the real project directories and adds the system TLS
bundle `/etc/ssl/cert.pem`. Runs use `FD_TELEMETRY=0` and explicit repo-local
`--log-file` paths. Initial attempts to change Godot's custom user-directory
setting were sanitised and denied by the sandbox; those attempted directories
were not created. The final wrapper uses the existing user directory but
writes no driver data; all enabled test persistence uses repo-local overrides.
The full host gate, final commit and push are left to the orchestrator.

Final selected checks (both exit 0, no engine/script errors in final logs):

- `CONFIG TEST PASSED`: all **3** car configs.
- `MISSION LADDER TEST PASSED: 873 checks`: **380** more than the 493-check
  baseline, including **22** real-car passes and **10** new real-car failures.
- `git diff --check`: clean.

Evidence: `build/ml5/config-final.log` and `build/ml5/ladder-final.log`.
Commands, run from the repository root:

```sh
FD_TELEMETRY=0 godot --headless --path build/ml5/env --log-file /Users/kokos/games/factory-driver/build/ml5/config-engine.log --script res://tests/config_test.gd
FD_TELEMETRY=0 godot --headless --path build/ml5/env --log-file /Users/kokos/games/factory-driver/build/ml5/final-engine.log --fixed-fps 60 --script res://tests/mission_ladder_test.gd
```
