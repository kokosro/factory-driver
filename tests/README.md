# Tests

`tests/run_tests.sh` is the gate: a headless import, then the config, element catalogue,
skeleton, world profile, buildings, dressing, ring drive, bubble, offroad, async build, smoke, handling, camera, mission, battery,
thermal, tyre/brake thermal, steering-feel, wear, licence, menu, issue flag, minimap, airborne, reset,
refuel, telemetry watch, marks, side road, road edge, mission ladder and first run tests, the driving ones on the tick clock (`--fixed-fps 60`), a few
minutes (the dressing test builds the Ring scene twice; the ring drive test builds the Ring's
road twice and drives 2 km on it twice; the bubble test builds it twice more and drives
700 m of the loop twice, at a tree twice and a teleport (BUBBLE-1; `FD_BUBBLE_PERF=1` in
the environment adds wall-time `perf:` lines to it - the suite never sets it); the
offroad test builds it twice more and drives 11 s of grass on each, 11 s of the straight and
the control (OFFROAD-1); the async build test builds it twice more - once in `_ready`, once
through the loading scene's WorkerThreadPool pipeline - and hashes the two against each other,
then a fallback and an abandonment (LOADING-1; `FD_LOADING_FRAMES=1` in the environment adds
per-frame lines - the suite never sets it); the
minimap test builds it once more, the reset test twice more and drives 400 m (the menu
test's additive LOADING-1 check builds it once more through the loading scene), the telemetry
watch test once more and drives a second on it, the marks test once more and slides on
its straight and its grass (SKIDMARKS-1: the `MarksWatch` autoload's layer on the pad with
its own `TyreMarks` stripped and on the Ring, the three triggers, the drives that mark and
the ones that must not, the grass gate, two fresh pad scenes driven the same slide to the
same records, the pool's bound and the 180 s fade run out on the tick clock, `FD_MARKS=0`
leaving no layer and the recorder's samples of the same slide byte-identical with and
without it; `FD_MARKS` is unset in the suite, which is off headless, so no other test sees
a layer), the first run test once more for the
dealership and sits the L0 exam twice on the pad; since 4B-7 every Ring scene load also
builds the terrain, the forest walls and the sky, about nine seconds more each; since
BUBBLE-1 the forest build also writes the trunk bodies, a few hundred milliseconds; since
OFFROAD-1 the terrain build also writes the continuation skirt, about a second).
`tests/run_tests.sh --parallel` runs the thirty-two tests side by side after the import and
prints the same lines in the same order (was thirty-one -> the ML-1 mission ladder test; 34 markers including import and the final verdict).
The side road test adds nine checks: the skeleton SHA, the 5.0 m issue segment, a
covered 3.0 m control, sideways heading, four individual wheel classifications and
front/rear road readings at issue-0069’s exact pose.
The road edge test adds 18 checks (configured total 2913 -> 2931): a fixed
ROAD-6 byte digest of 4965 paved loop points (height/elevation/gradient), exact
pavement boundaries, both sides of the 0.40 m / 0.11 m lip, the 7.5 m width,
issue-0068's right-wheel heights, 132 widened-side-road controls, all 92 rumble
meshes (135444 vertices / 179856 triangles, no new shapes), and an 8 m/s crossing
against the old smooth profile, repeated deterministically. The existing
world-profile digest remains unchanged. See `docs/road-5-implementation.md` for
measured gates and sandbox limitations.
What each test checks is in the main
`README.md` (since FOREST-2 the dressing test also holds the forest edge's card recipe -
the gap share, the feathers, every card's texture window, the wall texture's skyline and
column gaps - 120 checks since ROAD-3 (the carve and the road body), was 118, was 113; the bubble test's named tree is index 12369, was 12355;
since LOADING-1 the menu test has one check more,
its Ring row's route through the loading scene, and the suite has the async build test's 15).

## Gating a commit, not a working tree

An independent verifier should gate a copy of the committed tree, not the working tree
it happens to stand in:

```
dir="$(mktemp -d)"
git archive HEAD | tar -x -C "$dir"
cd "$dir"
tests/run_tests.sh
```

`git archive` writes out exactly what the commit holds: no uncommitted edit, no
untracked file and no stale `.godot/` cache can pass (or fail) the gate on the
commit's behalf, and nothing the run does - the import writes `.godot/` - touches
anybody's working tree, so it is safe while somebody else is editing or gating there.
The copy has no `.godot/` yet, so its first import is a full one and prints more than a
warm one does; the `== step` markers, the `  ok` lines and the verdicts are the same as
anywhere else. Several copies can be gated at once: the only things the suite writes
outside the project are the smoke test's `/tmp/fd-3R-smoke-<pid>/`, the battery
test's `/tmp/fd-3T-battery-<pid>/`, the wear test's `/tmp/fd-3L-wear-<pid>/`, the
licence test's `/tmp/fd-3K-licence-<pid>/`, the menu test's `/tmp/fd-4A-menu-<pid>/`, the
issue flag test's `/tmp/fd-3IF-issue-<pid>/`, the telemetry watch test's
`/tmp/fd-TW-telemetry-<pid>/`, the marks test's `/tmp/fd-SM-marks-<pid>/` (two recorder
files of the pad's slide, compared and removed) and the first run test's `/tmp/fd-4B6-first-<pid>/` (its
own world.json and cars.json; the data folder's never), one per process each, removed when the
test finishes (the ring drive test writes nothing:
it reads the checked-in skeleton and drape and builds in memory; the buildings test writes
nothing either: it reads the checked-in focus table, and the raw OSM snapshot store only
where it is on the machine, never fetching; the dressing test the same: the checked-in
landcover, the store's raw parts only where they are on the machine, no network, and since
4B-ASSETS-1 the checked-in Blender-authored textures and tree archetypes under `assets/` as
files (since 4B-ASSETS-2 the asphalt set is the Ring's road material too, read through the
project's own imports as the scene loads it) - the suite never runs Blender; regenerating
them is `assets/blender/README.md`'s command; the refuel
test writes nothing: the store is off
headless; the bubble test writes nothing: the Ring in memory, the drives on the tick
clock; the offroad test the same, and reads the checked-in surfaces table; the async build
test the same, in memory, no window - WorkerThreadPool works headless). No test opens a window or a
native dialog: the garage's folder picker is a GUI path the menu test never takes.
`tests/visual_probe.gd` is not in the suite: the one sanctioned windowed run (the
Conductor's visual probe, `godot --path . --script res://tests/visual_probe.gd
--quit-after 900`), photographing four road-derived spots into `.scratch/fd-visual/`.

## Mission ladder (ML-1)

After road edge, `mission_ladder_test.gd` runs 100 checks: schema types, medals,
references and cycles; store round-trip, version-zero migration, corruption, gating,
overrides and atomic failure; L1 enrollment, driver-wide rank, prerequisites and
FD-12/22/33 transactions; retry scoring, Ace terminal, ordered gates, cone failure,
abort without writes, idle runner, garage briefing/results and six-page order.
The test-only `ml1_proof.json` also drives the actual pad car using HandlingTests'
input mechanics. Production has no missions. Result lines use `episode result:`.
