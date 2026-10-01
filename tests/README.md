# Tests

`tests/run_tests.sh` is the gate: a headless import, then the config, element catalogue,
skeleton, world profile, buildings, dressing, ring drive, bubble, offroad, async build, smoke, handling, camera, mission, battery,
thermal, tyre/brake thermal, steering-feel, wear, licence, menu, issue flag, minimap, airborne, reset,
refuel, telemetry watch, marks, sound, side road, road edge, mission ladder, credits and first run tests, the driving ones on the tick clock (`--fixed-fps 60`), a few
minutes (the dressing test builds the Ring scene twice; the ring drive test builds the Ring's
road twice and drives 2 km on it twice; the bubble test builds it twice more and drives
700 m of the loop twice, at a tree twice and a teleport (BUBBLE-1; `FD_BUBBLE_PERF=1` in
the environment adds wall-time `perf:` lines to it - the suite never sets it); the
offroad test builds it twice more and drives 11 s of grass on each, 11 s of the straight and
the control (OFFROAD-1); the async build test builds it twice more - once in `_ready`, once
through the loading scene's WorkerThreadPool pipeline - and hashes the two against each other,
then a fallback and an abandonment (LOADING-1; since L2-STREAMING-1 the loading scene hands
over on the resident base plus the 2 km vicinity and the test waits for the streaming tail:
the handover's set, the tail's order, a SHA-256 per child and the old per-builder digests
at completion, the stage totals the vicinity's - every moved pin is named was -> now in the
test's header; `FD_LOADING_FRAMES=1` in the environment adds per-frame and per-chunk lines -
the suite never sets it); the
minimap test builds it once more, the reset test twice more and drives 400 m (the menu
test's additive LOADING-1 check builds it once more through the loading scene), the telemetry
watch test once more and drives a second on it, the marks test once more and slides on
its straight and its grass (SKIDMARKS-1: the `MarksWatch` autoload's layer on the pad with
its own `TyreMarks` stripped and on the Ring, the three triggers, the drives that mark and
the ones that must not, the grass gate, two fresh pad scenes driven the same slide to the
same records, the pool's bound and the 180 s fade run out on the tick clock, `FD_MARKS=0`
leaving no layer and the recorder's samples of the same slide byte-identical with and
without it; `FD_MARKS` is unset in the suite, which is off headless, so no other test sees
a layer), the sound test builds no Ring (SOUND-1: the `SoundWatch` autoload's node on bare
cars under the root and on the shipped pad in front of the recorder, the three procedural
loops built in code - since SOUND-2 the flat-6 order stack, the body-plus-noise rumble and
the 2 kHz modulated squeal, their partial tables, zero-crossing rates and the baked
amplitude modulation pinned on the built PCM - the engine / surface / skid mapping pinned at its corners and on the
car's own public fields written straight, two nodes fed the same reads mapping the same
values to the bit, the `FD_SOUND` switch, and a second pad's recorder samples of the same
slide byte-identical with `FD_SOUND=0`; since SOUND-3 also the wind loop and the thump burst,
the wind / impact / environment functions at their corners, a bare car beside an inert
`Buildings` node whose hand-written shells trim the wind and the rumble, and one real drive
into the pad's shed 0 that fires a thump; `FD_SOUND` is unset in the suite, which is off
headless, so no other test sees a node or an audio player), the first run test once more for the
dealership and sits the L0 exam twice on the pad; since 4B-7 every Ring scene load also
builds the terrain, the forest walls and the sky, about nine seconds more each; since
WEATHER-1 the dressing test builds the Ring four times - the clear day, rain twice, the
clear day again - and holds the weather (211 checks, was 146): `FD_WEATHER` unset is the
clear day to the letter (no weather key, no rain node, the dry road, the clear sun and
ambient pinned to their literals); each of overcast / sunset / evening / rain pins its sun,
its ambient, its plate on the scene's own copies (the packed scene's shared plate still
clear), the haze colour re-read from the new horizon and the curve re-fitted through the
state's table; rain also the wet road on every strip, the streak field's constants and its
ride with the car, and two rain scenes describing themselves the same; the three dry states
run on the Ring's sky alone - the shared Environment, a Sun and the SkySet - not on three
more builds of the Ring; the test takes `FD_WEATHER` off for its clear scenes and restores
it, and the suite runs with it unset; since
BUBBLE-1 the forest build also writes the trunk bodies, a few hundred milliseconds; since
OFFROAD-1 the terrain build also writes the continuation skirt, about a second).
`tests/run_tests.sh --parallel` runs the thirty-four tests side by side after the import and
prints the same lines in the same order (was thirty-one -> the ML-1 mission ladder test; was thirty-two -> the credits test, ECON-1; was thirty-three -> the sound test, SOUND-1; 36 markers including import and the final verdict, was 35 -> the sound test, SOUND-1).
The sound test adds 91 checks (`SOUND TEST PASSED`), measured on the
host (was 73 -> CAT-AWARE-1's cat battery, eighteen: with `FD_CAT=1` the one shared `Cat` audio
bus and its 3000 Hz low-pass, all eight players routed to it, the squeal written at x0.6 pitch and
-6 dB, the thump at x0.8 pitch and -8 dB, the other channels untouched, the bus made by the first
cat node and removed with the last, the determinism of two cat cars over the sixteen-value state,
`FD_SOUND=0` winning over `FD_CAT=1`, the realistic mix to the bit once `FD_CAT` is off again, and
the `FD_CAT` restore pin; was 53 -> SOUND-3's
twenty: the thump burst and the wind's zero-crossing rate on the built PCM, the wind, impact
and environment corners, the wind on the bare car, the eight-check environment battery and the
three-check shed impact drive; was 51 -> SOUND-2's
two measured checks on the built PCM, the zero-crossing rates and the squeal's amplitude
modulation; SOUND-1's 51 was the count as written, unmeasured by its implementer's session).
The side road test adds nine checks: the skeleton SHA, the 5.0 m issue segment, a
covered 3.0 m control, sideways heading, four individual wheel classifications and
front/rear road readings at issue-0069’s exact pose.
The road edge test adds 39 checks (was 18 at ROAD-5, configured total 2913 -> 2931
then; ROAD-8 adds 21: the suite's 5018 ok lines at SOUND-2 become 5039 by count,
measured by the landing's full run): a fixed
ROAD-6 byte digest of 4965 paved loop points (height/elevation/gradient), exact
pavement boundaries, both sides of the 0.40 m / 0.11 m lip, the 7.5 m width,
issue-0068's right-wheel heights, 132 widened-side-road controls, all 92 rumble
meshes (135444 vertices / 179856 triangles, no new shapes), and an 8 m/s crossing
against the old smooth profile, repeated deterministically. The existing
world-profile digest remains unchanged. See `docs/road-5-implementation.md` for
measured gates and sandbox limitations. ROAD-8's 21 checks pin the kerb table
(`data/regions/eifel_ring/kerbs.json`: version 1, 25 entries, 18 raised / 7 flat,
every one filed on a named loop corner inside its length, none on the Karussell,
Döttinger Höhe or the certified drive's stretch, Hatzenbogen's inside raised; the
reader's refusals), the kerb on the Ring (Hatzenbogen's 0.165 m crest and its
±0.02 m teeth on the 0.5 m wavelength, Aremberg's raised inside and flat outside
band, Lauda-Links as the no-entry control showing the plain lip to the bit, the
window's edges and 2 m fades), gravity byte-identical to a kerb-free profile
built from the same files at 750 points across every window and heights
byte-identical 1 m outside every window and on every window's other side, the
fixture's exact numbers for both types (raised [0, .0825, .165, .0825, 0] and its
teeth, flat [0, .01, .02, ..., .01, 0] over 1.2 m, the fade's half-way values,
side and chainage gating, pavement and gradient to the bit), and the render
census (one `Kerb_<id>_<n>` mesh per entry on 18 segments, 25 meshes / 69150
vertices / 110440 triangles on the physical field + 0.02 m, the rumble census
unchanged).
What each test checks is in the main
`README.md` (since FOREST-2 the dressing test also holds the forest edge's card recipe -
the gap share, the feathers, every card's texture window, the wall texture's skyline and
column gaps - 120 checks since ROAD-3 (the carve and the road body), was 118, was 113; the bubble test's named tree is index 12369, was 12355;
since LOADING-1 the menu test has one check more,
its Ring row's route through the loading scene, and the suite has the async build test's 15;
since L2-STREAMING-1 the async build test has 25 checks, was 17: the handover's and the
completion's pins apart, the per-child digests, the scheduler's counters, the tail's frames
and the released claim; the menu test's additive check unloads its Ring two frames after the
handover, the tail in flight - the scheduler's cancel on every suite run).

## The streaming test (L2-STREAMING-1), a standalone

`tests/streaming_test.gd` is not a step of `run_tests.sh`; it is run beside it in the gate:

```
godot --headless --path . --import
godot --headless --fixed-fps 60 --path . --script res://tests/streaming_test.gd
```

About five minutes: it builds the Ring five times (once the ordinary way, four times
through the loading scene) and drives 2 km twice. It checks the `Streaming` autoload
(`scripts/streaming_scheduler.gd`: registered after every other autoload, the ruling's
2 000 m vicinity, the loading scene's four workers and 8 ms node budget, the box distance
and the band as pure functions, `claim()` refusing a Ring in the tree, a Ring whose builders
are not deferred and no scene - a sync Ring and the pad leave it idle with every counter
zero); the one-shot Ring as the reference, a SHA-256 per child under Terrain, Forest and
Buildings; the streamed Ring at the pit anchor - at the handover the children the
reference's order held to the resident set and the 94 chunks within 2 000 m by the test's
own arithmetic on the chunk names, the 259 far chunks absent, the car on the road's profile
over the floor slab; the ring drive test's own scripted driver (its `LoopDriver` and
constants read from the frozen script) over its 2 km from Döttinger Höhe, reset at the same
tick after the Ring enters the tree on both builds, begun on the streamed one with the tail
still to come and landing on the one-shot build's odometer, position and tick count to the
bit, all four wheels carried and every wheel inside the paved width every tick; at the
tail's completion every child byte-equal to the reference's of the same name, the four
`describe()` lines and every count the one-shot's, the scheduler's three new counters
adding up; the streamed Ring with the car put at the Karussell and at Aremberg (4.9 km
apart) before the lists are split - each handover another vicinity than the pit's, the tail
in the pinned (band, builder, CHUNK_ORDER) order for the standing car, every child
byte-equal, the car standing on the profile there; and a Ring unloaded in the frame after
its handover, the tail in flight, leaving the scheduler idle and the root as it was. It
pins `FD_TELEMETRY=0`, writes nothing anywhere and prints no wall time: the lines are the
same on every machine (`STREAMING TEST PASSED`).

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
files of the pad's slide, compared and removed), the sound test's `/tmp/fd-SOUND-<pid>/`
(the same two, compared and removed) and the first run test's `/tmp/fd-4B6-first-<pid>/` (its
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

After road edge, `mission_ladder_test.gd` runs 212 checks: schema types, medals,
references and cycles; store round-trip, version-zero migration, corruption, gating,
overrides and atomic failure; L1 enrollment, driver-wide rank, prerequisites and
FD-12/22/33 transactions; retry scoring, Ace terminal, ordered gates, cone failure,
abort without writes, idle runner, garage briefing/results and six-page order.
The test-only `ml1_proof.json` also drives the actual pad car using HandlingTests'
input mechanics. The ML-2 section loads the five production configs, checks their
schemas and dependencies, the real slalom-cone coordinates, fresh-Junior garage
rows (FD-01 enabled, the rest locked with their prerequisite reasons), each chain
link unlocking through FD-12, injected cone/skip/timeout failures and all four
medal bands per mission, the garage's unscripted launch, then drives every shipped
script on a fresh pad car to completion (never asserting a fixed time or medal) and
proves each result plus the FD-12 promotion survive a store reload. Result lines
use `episode result:`.
The SNOW-1 checks cover FD-14's `surface_override` (schema bounds, the sticky
surface inputs, restoration on every path, identical cold braking on road and
snow, the shipped drive's recorded time). The SNOW-2 checks cover its optional
`ground_tint`: the schema battery (non-array, wrong length, non-number, INF/NAN
and out-of-[0, 1] elements refused, the 0 and 1 edges accepted, an override
without the key still valid, a ring mission carrying it valid), the mechanism
on the real pad (the ground albedo equals the display tint converted once to
linear within an 8-bit step, the ground mesh keeps its material instance, every
other material under the pad keeps its albedo, the tint is re-asserted each tick
and restored exactly after pass, timeout, cone contact, abort and teardown,
inert without the key, a scene without a TestPad applies nothing, a pad torn
down under a live episode restores safely) and the shipped FD-14 drive running
tinted at its unchanged recorded time.
