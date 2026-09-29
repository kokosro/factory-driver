# ML-6: Chief Test Driver to Ace

Thirty-three production missions are playable. FD-23 through FD-33 are all
`chief` missions. FD-23 requires FD-22; FD-24 through FD-32 each require the
immediate predecessor. FD-33 explicitly requires **all ten** FD-23..FD-32
results, so a partial save cannot skip the rank's work. FD-33 is the terminal
catalog mission. Its passing result atomically grants the Ace credential and
Customised 2000 Porsche 911 Turbo (996) entitlement.

## Course adaptations

All eleven episodes drive the existing pad Boxster. Source venues and cars
are named in each briefing and `provenance`; there is no GT1 configuration.
Police, traffic, opponents, passenger actors and vehicle damage are absent.
No new schema, runner, car physics, scenes or surface data are required.
Gate/cone centres lie inside TestPad's core bounds: x −300..300 m,
z −1100..150 m, at the established gate height of 0.7 m.

- **FD-23 Race Car Test 1:** Weissach/1998 GT1 becomes a compact approach,
  one compass-gate circuit around (−22, −36), and a weaving exit to (−32, −62).
  Eight steps: six `waypoint_gate`, one `cone_slalom` carrying seven cone
  constraints, one `timed_finish`. This uses FD-21's first spin and connecting
  route, following the FD-03 positional-spin convention. Shared gates wait
  their turn; cone contact fails throughout. Yaw and handbrake use are not
  scored. Source limit: **37 s**.
- **FD-24 Dieter's Late:** Zone Industrielle/1994 993 chauffeur run becomes
  five ordered `waypoint_gate` down the eastern corridor through (12, −30),
  (40, −110), (45, −210), (20, −300), then southwest through (−45, −350)
  to `timed_finish` at (−85, −390). This clears the eastern sheds and differs
  from FD-17's west route. The passenger and source no-damage rule are not
  simulated. Source limit: **210 s**.
- **FD-25 Stephanie's Slalom:** Schwarzwald/1995 993 Turbo becomes a new
  western slalom: six authored cone constraints at x=−22, z=−40..−140 with
  20 m spacing. One `cone_slalom` entry at (−16, −22), six alternating
  2.4 m `waypoint_gate` at x=−25.5/−18.5, and `timed_finish` at (−24, −158)
  replace FD-16's eastern layout. Cone radius remains 1.2 m; cone contact
  and skipped gates fail. These are authored mission constraints, not a
  claim that the pad's surveyed physical cone line moved. Source limit: **37 s**.
- **FD-26 Billy's Challenge 2:** Weissach/1999 996 Carrera 4 becomes a new
  ten-cone grading slalom at x=36, z=−48..−246 with 22 m spacing. One
  `cone_slalom` entry at (23.8, −24), ten alternating 1.5 m `waypoint_gate`
  at x=32.5/39.5, and `timed_finish` at (32, −270) replace FD-22's fourteen-cone
  course. Authored cone constraints retain 1.2 m radius; cone contact and
  skipped gates fail. Billy and AWD handling are absent. Source limit: **50 s**.
- **FD-27 Stephanie's Switchbacks:** Alps/1995 993 Turbo becomes six compact
  zig-zag gates, alternating x=−12/−26 with 16 m longitudinal spacing.
  One `cone_slalom`, four `waypoint_gate`, then `timed_finish`; five cone
  constraints outside the bends at x=0/−45 guard the turns. The 4.5 m radii allow the pad car to
  turn within the source limit. Alpine hairpins are compressed; mountain
  elevation is absent. Source limit: **37 s**.
- **FD-28 Team Race 2:** Pyrénées/1995 993 Carrera 4 becomes a new scenic
  solo tour: eight broad `waypoint_gate` down the eastern corridor to
  (25, −290), around the southern bend at (−55, −330), then up the outer
  west side through (−110, −240), (−100, −125) and (−65, −30), with
  `timed_finish` at (−20, 45). Its direction and geometry differ from FD-19
  and FD-32. Frank and Billy await E-6 traffic. The source supplies **no time
  limit**; **120 s** is authored, with `source_time_limit_s: null`.
  No finishing-position or AWD simulation is claimed.
- **FD-29 Porsche Commercial / Reverse Slide:** Weissach/1998 996 Cabriolet
  uses ten steps: one `cone_slalom`, eight `waypoint_gate`, one `timed_finish`.
  Four cones constrain the route. Drive forward through z=−22/−45, reverse
  through z=−25/−5, then drive forward through the connector and compass
  circuit around (−28, −32). Route direction reversals represent the two
  180 slides, and the final circuit represents the 360 spin. Yaw and
  handbrake use are unscored; manual transmission is not simulated.
  `MissionRunner._entry_fraction` uses swept-radius contact without heading
  or gear tests. As certified by `HandlingTests.reverse_180_test`, brake
  pressed from standstill selects reverse. The shipped script cruises at
  8 m/s to 48 m travelled, brakes to below 0.1 m/s, releases brake while
  briefly holding handbrake, then represses brake after 0.1 s. Five seconds
  later it releases brake; the existing throttle controller stops reverse
  motion and automatically resumes forward driving. A recorded steering
  trace completes the finale. Tests observe **both return gates crossed with
  reverse engaged and negative forward_speed**, with forward entry/finale.
  Scoring itself remains direction-agnostic. Source limit: **50 s**.
- **FD-30 Race Car Test 2:** Monte Carlo Circuit 2/1998 GT1 becomes an approach,
  **three full repeated four-gate circuits**, and separate finish: thirteen
  `waypoint_gate` plus `timed_finish`. Each circuit visits (−80, −40),
  (−80, −100), (−20, −100), (−20, −40). Repeated positions wait their turn
  without `skipped_gate`; each lap must be driven before the finish counts.
  This uses the allowed repeated-circuit alternative to `lap` steps.
  The source leaves cold, wet Weissach for Monaco, so ordinary warm tyres
  are retained; `cold_tyres` is not enabled. Weather and the source's damage
  prohibition are absent. Source limit: **220 s**.
- **FD-31 Race Car Test 3:** Monte Carlo Circuit 1/1998 GT1 becomes one of
  those pad circuits with approach and finish: five `waypoint_gate` plus
  `timed_finish`. Solo clock replaces the factory-team race; opponents await
  E-6 traffic. Source has **no time limit**; **90 s** is authored, recorded
  with a null source limit.
- **FD-32 996 Turbo Joy Ride:** Monte Carlo Circuit 5/2000 996 Turbo follows
  FD-11's actual guided-tour lineage: turn approach, skid-pad vicinity,
  southern sweep, slalom-side return and northern emergency-stop yard.
  Eight broad 8/12 m `waypoint_gate` define a new shape: (−8, −35),
  (−80, −85), (−125, −180), (−70, −285), (25, −310), (55, −190),
  (40, −70), (0, 55), then `timed_finish` at (−65, 85). This wider west/south
  loop differs from FD-11/19's shared geometry and FD-28's east-first tour.
  Frank's navigation and the damage prohibition are not simulated. The
  briefing distinguishes this Boxster drive from the `fd_2000` entitlement
  awarded on promotion to Ace. Source limit: **150 s**.
- **FD-33 3rd Promotion Test — Ace Challenge:** Monte Carlo Circuit 3/2000
  996 Turbo becomes two pad circuits with approach and finish: nine
  `waypoint_gate` plus `timed_finish`. Solo clock replaces Stephanie's race;
  opponents await E-6 traffic. The source has **no time limit**; **120 s** is
  authored, recorded with a null source limit. All ten Chief results are
  required explicitly in `unlock` and disclosed in `provenance.unlock`.

## Ace reward

`configs/cars/fd_2000.json` has neutral identity `FD-2000` / `fd_2000`, following
FD-1001's no-real-model-claim convention. It is a **config-only stand-in** for
the named entitlement, not a replica or a claim of customised tuning.
[Porsche's generation history](https://newsroom.porsche.com/en/press-kits/50-years-porsche-turbo/The-911-Turbo-generations.html)
provides the period twin-turbo flat-six inspiration: about 420 PS and 560 Nm.
The authored curve has 560 Nm at 2700–4600 rpm and 492 Nm at 6000 rpm
(about 309 kW / 420 PS). Redline is 6750 rpm.

Other figures are explicitly estimated: 1540 kg ready-to-drive ledger,
60% rear share, 0.48 m CG height, 2.35 m wheelbase (schema half-distance
1.175 m), six forward ratios, 3.44 final drive, 64 L tank, 1.05 g brake target,
and drag coefficient 0.31. The thirteen ledger rows sum **exactly** to 1540 kg
and exactly 0.6 rear share under the validator's ordered f64 calculation.
The 75 kg driver is included; fuel is separately modelled. Unsprung rows total
150 kg. All component masses/positions are estimates; the final 725 kg body
row's x=0.08944827586206916 m is calibrated to the rear share. Thermal, tyre,
wear and driver-profile numbers inherit the Boxster defaults. No turbo-lag or
AWD subsystem is added. The same basis is documented in `configs/README.md`;
no free-text metadata keys are added to the strict car-config schema.

Only `CampaignStore.REWARD_CARS` changes, adding `"ace": "fd_2000"`.
The existing `PROMOTIONS["FD-33"]`, `REWARDS.ace`, `record_result`, ownership
and TAKE logic are unchanged. Ownership derives from the committed reward;
there is no second flag, purchase, voucher or migration write. The generic
MISSIONS reward loop requires no changes. Five added CAR-page lines show
OWNED, TAKE and SELECTED, explicitly identifying the config-only stand-in.
TAKE selects `world.active_car` and can create a condition record with the
config's own tank capacity, preserving existing condition on repeated TAKE.
Tests enable persistence only through explicit isolated paths.

**All missions still drive the pad Boxster. Live physics swapping remains
deferred under the `car.gd` freeze.** Selection of FD-2000 is an entitlement
and garage-record operation only.

## Medal measurement and verification

Measured 2026-09-29 with Godot 4.7.2, headless fixed 60 Hz, through
MissionRunner/HandlingTests in `tests/mission_ladder_test.gd`. Every drive uses
a newly instantiated pad car and the shipped JSON `input_script`. Bands are
`ceil(measured × 1.05 / 1.25 / 1.50)` for gold/silver/bronze. Each JSON records
the seconds, method and run. Pilot times are not substituted for shipped
replay times. Source limits remain intact; FD-28/31/33 disclose authored ones.

| Mission | Measured seconds | Gold | Silver | Bronze | Limit |
|---|---:|---:|---:|---:|---|
| FD-23 | 20.350000 | 22 | 26 | 31 | 37 source |
| FD-24 | 38.383333 | 41 | 48 | 58 | 210 source |
| FD-25 | 20.400000 | 22 | 26 | 31 | 37 source |
| FD-26 | 31.466667 | 34 | 40 | 48 | 50 source |
| FD-27 | 23.366667 | 25 | 30 | 36 | 37 source |
| FD-28 | 67.033333 | 71 | 84 | 101 | 120 authored |
| FD-29 | 32.100000 | 34 | 41 | 49 | 50 source |
| FD-30 | 68.750000 | 73 | 86 | 104 | 220 source |
| FD-31 | 26.550000 | 28 | 34 | 40 | 90 authored |
| FD-32 | 74.466667 | 79 | 94 | 112 | 150 source |
| FD-33 | 47.683333 | 51 | 60 | 72 | 120 authored |

FD-23 reuses the first part of FD-21's 7 m/s trace. The structural fix round
replaces the five complete route/control copies: FD-24 records a new 12 m/s
chauffeur trace, FD-25 a new 9 m/s western slalom trace, FD-26 a new 10 m/s
eastern grading trace, and FD-28/32 separate new 12 m/s scenic traces.
FD-32 retains FD-11's landmark-tour concept, not its geometry or controls.
FD-27 records a new 8 m/s switchback steering trace; FD-30/31/33 record new
12 m/s circuit traces.
FD-29 combines the explicit stop/reverse controls with an 8 m/s forward
steering trace. All traces use only the existing input grammar, with no gear
selector or rotation conditions. Temporary pilot scripts and logs live in
`/tmp`; no scene copies or repository scratch trees were created.

The ladder retains the ML-1..5 proof and extends discovery, schema validation,
every sequential unlock, independent removal of each of FD-33's ten
prerequisites, rank/source-limit/provenance/pad-bounds checks, exact medal
boundaries, actual reverse motion, and three-lap completion. Six new episode
distinctness pins cover FD-24/17, FD-25/16, FD-26/22, FD-28/19, FD-32/19 and
FD-28/32; six matching pins also require different shipped controls. Every new mission
has a real-car pass and failure with its **shipped controls and route**: the
failure test shortens the in-memory clock to half the measured pass time,
then checks that the car has physically moved and crossed gates before the
timeout. Production limits are restored immediately. The existing earlier
bad-driver tests retain their controls and intent.

The Ace roundtrip checks failed-promotion grants nothing, credential/reward
atomic persistence, auto-ownership before TAKE, MISSIONS and CAR TAKE rows,
both callbacks, isolated condition creation, zero distance/full tank,
condition preservation, reload without rewrite, retention of earlier rewards,
replay unable to promote again, and terminal catalog behavior. The existing
suite marker is retained: `tests/run_tests.sh` is untouched at 34 markers.

Structural fix-round evidence (2026-09-29):

- Entering this round: host-verified `MISSION LADDER TEST PASSED: 1408 checks`.
- New shipped-route measurement: `MISSION LADDER TEST PASSED: 1420 checks`,
  exit 0, recorded in `/tmp/ml6-fix-measure.log`. The five replaced rows in
  the table come from this full ladder run, not the authoring pilots.
- Final verification with the new medal bands and measured failure deadlines:
  `MISSION LADDER TEST PASSED: 1420 checks`, exit 0. All five measured times
  match the measurement run. Every Chief mission passes and fails through
  its shipped controls. `/tmp/ml6-fix-final.log` and
  `/tmp/ml6-fix-final-engine.log` contain zero `SCRIPT ERROR` / `ERROR:` lines;
  wrapper test fixture directories are cleaned. `git diff --check` is clean.
- Twelve checks were added: six episode inequalities and six shipped-control
  inequalities. Every existing check remains.
- The earlier host config test already covers FD-2000; its file and the other
  six Chief missions were unchanged in this round.

The direct project pilot reproduced the pre-existing macOS trust-store error:
`ERROR: Condition "ret != noErr" is true. Returning: ""` at
`get_system_ca_certificates (platform/macos/os_macos.mm:1035)`. Subsequent runs
use the established `/tmp/ml6-env/project.godot` wrapper with
`network/tls/certificate_bundle_override="/etc/ssl/cert.pem"` and symlinked
project resources. No scenes are copied and repository settings are untouched.
`FD_TELEMETRY=0` disables driver-data IO; the ladder uses PID-isolated
`build/ml6-test-<pid>` fixture paths under the wrapper and cleans them on exit.
Engine logs are explicitly redirected into `/tmp`.

```sh
FD_TELEMETRY=0 /opt/homebrew/bin/godot --headless --fixed-fps 60 --path /tmp/ml6-env --log-file /tmp/ml6-fix-final-engine.log --script res://tests/mission_ladder_test.gd > /tmp/ml6-fix-final.log 2>&1
```

Authoring pilots exposed shed collisions on the initial eastern routes and
missed gates/cones in early slalom attempts. The eastern routes now clear the
sheds. The slaloms use newly recorded steering traces, with entry and finish
positions fitted to the driven approach and exit; scored replay uses every
shipped cone constraint and narrow gate. No source-limit or medal-formula
deviation was needed. All five mission briefings and adaptation provenance
retain the absent-car, venue and gameplay-system disclosures.

This bounded round edits only FD-24/25/26/28/32, the ladder test and this document.
No commit, push, stash or checkout was made; the tree remains dirty. The full
host suite remains the orchestrator's verification step.
