# ML-4: complete the Junior mission ladder

FD-08/09/10/11 are Junior missions. The playable chain is now FD-01 → FD-02 →
FD-03 → FD-04 → FD-05 → FD-06 → FD-07 → FD-08 → FD-09 → FD-10 → FD-11 → FD-12.
FD-12's sole config change replaces prerequisite FD-07 with FD-11; its fresh
lock text is `Complete FD-11`. Promotion and the RS entitlement are unchanged.

## Courses and medal measurements

| Mission | Scripted pass | Gold | Silver | Bronze | Source limit |
|---|---:|---:|---:|---:|---:|
| FD-08 Car Delivery 2 | 35.116667 s | 37 | 44 | 53 | 180 |
| FD-09 Capture The Flag 1 | 72.416667 s | 77 | 91 | 109 | 240 |
| FD-10 More 360's | 20.733333 s | 22 | 26 | 32 | 36 |
| FD-11 Demo a 996 | 64.500000 s | 68 | 81 | 97 | 240 |

Measured on 2026-09-29 with Godot 4.7.2, headless fixed 60 Hz, each shipped
`input_script` through MissionRunner/HandlingTests on a freshly loaded pad
Boxster in `tests/mission_ladder_test.gd`. Bands are
`ceil(measured seconds × factor)`, factors 1.05/1.25/1.50, strictly ordered below
the canonical limits. JSON provenance uses the FD-05/06/07 source/medals/adaptation
structure. Tests assert completion rather than a fixed time or medal and print
each episode result plus six-decimal measured seconds.

Steering traces were recorded with a temporary path-following pilot in
`.scratch/ml4/`, then replayed through the unchanged HandlingTests vocabulary:
`hold_speed`, `steer_deg`, `when.after`, and a final `steer_free` sentinel.
The recorder is not part of the runtime. Cruise speeds are 12/8/8/12 m/s.
Measurements above come from the shipped-script harness, not the recorder:
its FD-09/11 exploratory measurements differed by two/one physics ticks.

All route and cone positions use y=0.7 and lie within TestPad's core surface.
FD-08 extends the FD-05 dispatch/handover convention into a different curved
route: (0,-20) → (-10,-100) → (-40,-190) → (-10,-280) → (0,-360) → (0,-400).
The final two gates are `delivery_return` and `timed_finish`; return means dock
handover, not driving back to dispatch. No stop or cargo state is invented.
The pad stands in for Zone Industrielle; the pad Boxster stands in for the
source delivered 1997 Boxster. Police patrols, traffic and the source damage
prohibition are not simulated, explicitly stated in the briefing and provenance.

FD-10 repeats FD-03's positional north/east/south/west gate ring around
(-22,-36) twice, after its (-32,-36) approach. It uses the same five cone
constraints and radii. This is FD-03's small mission circuit near the northeast
edge of the skid-disc area, not the larger surveyed TestPad skid circle.
`cone_hit` applies throughout the episode, including approach, second circuit
and finish. `skipped_gate` is omitted because both circuits share positions:
only the current gate advances, and later occurrences wait for their turn.
The second west crossing is the timed finish. Yaw and handbrake use remain
unscored under the documented FD-03 convention. The Boxster stands in for the
source 1995 993 Turbo. No car or handling changes are made.

FD-11 is a longer scenic tour with broad 8/12 m gates: turn stretch (0,-30),
skid centre (-70,-90), west straight (-40,-180), slalom end (20,-250), eastern
return (40,-150)/(25,-50), emergency-stop zone (0,41), yard (-35,80), finish
(-70,30). The pad replaces Corsica canyons and the Boxster replaces the 1998
996 Carrera demo car. Damage prohibition and restart-direction issues are not
simulated. The briefing identifies the player's later **Ace** 996 reward:
the brief's example Chief wording conflicts with both the source promotion
table and CampaignStore (Chief grants the Boxster; Ace grants the 996).
The demo customer's 996 and the later customised 996 reward are distinct cars.
No police or opponents are added.

## FD-09 checkpoint rally and reveal

The canonical source, `docs/mission-ladder-source.md:219-237`, says:

> "knock over twelve cones on the course in the correct order"

and:

> "We'll let you know where the next cone is as soon as you knock one over."

The orchestrator's binding ruling interprets this as sequential knockdown
checkpoints, not flag pickup/return. Episode step zero is `flag` with twelve
cone positions, followed by a separate timed finish. The single-car adaptation
has no opponents; AI traffic belongs to E-6 later. The pad stands in for
Corsica and its Boxster for the 1995 993 Carrera 4. The source restart-direction
issue is not simulated; neither are damage or police systems.

The documented custom layout loops back around the skid-disc area. Targets in
order, (x,z) metres: (0,-30), (0,-75), (0,-120), (-30,-150), (-70,-150),
(-110,-120), (-110,-75), (-110,-30), (-70,0), (-30,0), (20,-30), (20,-80).
The finish is (20,-115), radius 5 m. Flag contact radius is 2 m: a swept
car-centre proximity convention, not rigid-body impact simulation.

The schema requires a nonempty cones array of finite three-number positions
and finite positive cone_radius, in addition to the normal position/radius,
sequence and timed-finish rules. The reserved `flag` slot is now implemented.
The runner sorts `_entry_fraction` contacts along each movement segment and
credits only the current cone index. An earlier or later target contact is
ignored, even when skipped-gate failure is requested; it never banks a future
knock. Multiple sequential knocks in one sweep count in spatial order.
Only the twelfth knock advances the episode step to its finish gate.

Each target owns one runner-child Node3D named `Flag_0_k`, containing exactly
three MeshInstance3D children: an orange tapered CylinderMesh cone (0.7 m high,
0.35 m base radius), a light-gray CylinderMesh pole (2.8 m high, radius 0.035 m),
and a gold BoxMesh flag (1.1 × 0.65 × 0.04 m). StandardMaterial3D provides the
colors. Prop origins place the cone bases at ground level. There are no bodies,
areas, collision shapes, external assets or scene edits. Knockdown consumes and
hides the assembly rather than animating a falling rigid body.

Only the current target's assembly is visible: target one at start, its
successor after each knock, none during the finish step. `flag_progress()`
exposes the current number, total and position. `progress_text()` supplies the
actual HUD detail, including `Flag k/12 — knock the revealed cone at (x, z)`.
The last knock removes that reveal line. `_cleanup()` synchronously frees all
props after pass, failure, abort or teardown, clears flag state and disables
physics processing. Idle runner child count remains zero.

## Validation and boundaries

The existing ladder harness grows from **321 to 493 checks**. It covers all
12 catalog entries and unlock links, the FD-12 lock move, strict flag schema,
all flag reveals and actual HUD text, visual-only prop structure, out-of-order
and repeated contacts, multi-contact sweeps, pass/abort/timeout cleanup, medal
formula provenance, pad bounds, the exact doubled FD-03 ring, and second-lap
and finish-tick cone failures. All twelve missions drive to a real-car pass;
each new mission also drives to a real-car failure. Injected scoring exercises
all four success bands for every mission. No new test file or suite step is
added; `tests/run_tests.sh` retains its 34-marker structure.

Selected checks use `/opt/homebrew/bin/godot`, `FD_TELEMETRY=0`, and the runner's
headless invocations (fixed 60 Hz for the ladder). A scratch project wrapper
at `.scratch/ml4/env` uses the existing project settings and symlinks the real
scripts, tests, configs, assets and scenes, adding only the system certificate
bundle `/etc/ssl/cert.pem` to avoid the known sandbox macOS certificate lookup
error. Its fixtures stay under `res://build/`; logs and tooling stay under
`.scratch/ml4/`. No driver data directory writes or product project overrides.
The selected-step verdicts are `CONFIG TEST PASSED` (all three car configs) and
`MISSION LADDER TEST PASSED: 493 checks`, both exit 0. Final logs
`.scratch/ml4/config.log` and `.scratch/ml4/verified-ladder.log` contain no engine,
script, parse or deprecation warnings/errors. JSON sorted keys and trailing
whitespace were checked without Git.

An intermediate validation attempt caught a GDScript type-inference parse error
in the new repeated-ring assertion. Declaring its boolean type fixed it; this
means the brief's zero-errors-in-any-run requirement was not met, although the
final selected-step logs are clean. The full suite is left to the orchestrator.
No Git command, commit or push was run; the landing wording follows the existing
ML-2/ML-3 implementation records rather than inspecting Git history.

Suggested landing commit paragraph:

> ML-4 COMPLETE THE JUNIOR LADDER: add FD-08 Car Delivery 2, FD-09 Capture The Flag 1, FD-10 More 360's and FD-11 Demo a 996, extending FD-07 through FD-08/09/10/11 to FD-12 and moving the promotion prerequisite from FD-07 to FD-11. Implement the reserved flag step as twelve sequential swept cone contacts with strict schema validation, ignored out-of-order contacts, current-target-only orange cone/light-gray pole/gold flag props and a Flag k/12 HUD reveal; free every prop on finish, failure or abort. Preserve source limits 180/240/36/240 seconds, repeat FD-03's positional circuit twice with cone failures throughout, and document the pad/Boxster stand-ins plus absent police, damage, restart-direction and opponents systems. Ship measured fresh-car steering traces at 35.116667/72.416667/20.733333/64.500000 seconds with gold/silver/bronze bands 37/44/53, 77/91/109, 22/26/32 and 68/81/97. Extend the existing ladder proof from 321 to 493 passing checks without changing the 34-marker suite; all three car configs pass. Selected checks ran with telemetry disabled and the scratch certificate wrapper; full gates, commit and push remain the orchestrator's work.
