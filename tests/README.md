# Tests

`tests/run_tests.sh` is the gate: a headless import, then the config, element catalogue,
skeleton, world profile, buildings, dressing, ring drive, bubble, offroad, async build, smoke, handling, camera, mission, battery,
thermal, tyre/brake thermal, steering-feel, wear, licence, menu, issue flag, minimap, airborne, reset,
refuel, telemetry watch, marks, sound, side road, road edge, mission ladder, credits, obligations and first run tests, the driving ones on the tick clock (`--fixed-fps 60`), a few
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
the modulated squeal (since SOUND-4 a band of friction noise, 300..1300 Hz in the buffer
and heard at 450..1950 Hz at solid, no tone in it; was the 2 kHz tone the driver rejected
twice), their partial tables,
zero-crossing rates and the baked amplitude modulation pinned on the built PCM, and since
SOUND-4 the squeal's band ceiling too (the RMS over 2000..4000 Hz against the RMS over
300..1800 Hz, and that band against the buffer's whole energy) - the engine / surface / skid mapping pinned at its corners and on the
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
`tests/run_tests.sh --parallel` runs the thirty-five tests side by side after the import and
prints the same lines in the same order (was thirty-one -> the ML-1 mission ladder test; was thirty-two -> the credits test, ECON-1; was thirty-three -> the sound test, SOUND-1; was thirty-four -> the obligations test, TROC-1 slice 1; 37 markers including import and the final verdict, was 36 -> the obligations test, TROC-1 slice 1; was 35 -> the sound test, SOUND-1).
The obligations test adds 127 checks (`OBLIGATIONS TEST PASSED`), measured on the host (was
89 -> TROC-1 slice 3's barter corner, thirty-eight; was
79 -> TROC-1 slice 2's runner corner, ten, and the seed-gap pin flipped: obligations.json IS
in the data folder's seed now): the ObligationsLedger store (TROC-1 slice 1) — the record
shape, the one-shot redemption, the creditor transfers, the derived open views, the versions
and the corruption tolerance, on a file of the test's own — then the mission runner on the
pad with a posted fixture of the test's own: gated it creates nothing, a pass creates the
poster's obligation to the player once (creditor, debtor, owed, kind delivery, origin
`job:<id>/episode-<n>`, open), a retry and a failure leave the bytes identical, and the JOBS
page's `open_view("player")` shows the record. Then the barter corner (TROC-1 slice 3), the
garage on the pad over a world record, a cars file, a campaign file and ledgers of the
test's own: the fresh-driver arc (a delivered job -> the poster's obligation held ->
`Garage.barter_car("boxster_986")` -> the record's creditor `DEALER-EIFEL-02`, its
`transfers[0]` player to the desk with origin `dealership:boxster_986`, the car's entry
written, `active_car` set, `Garage.traded` true, the OWNED/SELECTED trade lines and no
BARTER row); the insufficient boot (nothing held: greyed, refused before any write, the
bytes identical); the count (the FD-2000 with one held obligation greyed and refused, with
two bought and two transfers recorded); an obligation the desk itself owes not counted at
that desk; the reversal (a cars path that cannot be written: the transfer committed, then
handed back, both in the record's history, nothing owned); the dormant `buy_car` refusing
a traded car as "already owned"; the row itself through `activate_row`; and the gated
page. Not forced by any test: a transfer refused mid-trade and a reversal that itself
fails (neither can be provoked between two ledger writes from outside; the code paths
are `barter_car`'s and `_reverse_trade`'s).
The credits test has 467 checks (`CREDITS TEST PASSED`), measured on the host, since TROC-1
slice 4 (was 464 -> the fuel section's three new pins; was 427 -> TROC-1 slice 3's
exchange-terms pins and fault rows, thirty-seven). Since TROC-1 slice 4 its paid-fuel
section is the station's trade, each label saying what it was: the Ring's `Refuel` node
wired to the runner's obligations ledger and NOT to its credits one (wired as that is:
`Refuel.CREDITS_FUEL_ENABLED == false` pinned as the shipped state), the dry run away from
every station leaving both files untouched, the fill at E2.4 writing `OBL-0002` after the
job's record (creditor `E2.4`, debtor `player`, owed `fuel 44 L`, kind `fuel-voucher`,
origin `refuel`, open) with the test's own 95-credit stake still 95 and no spent signal
(was: 88 spent, 7 left), the full-tank hold, the whole-litre rounding (`fuel 1 L` for 0.3
L; was: 1 credit), the credits-only wiring (the obligations ledger gated: nothing is
wired, the fill is free), a later build's obligations file (the trade refused on every
tick, no fuel, the bytes untouched), and the fully gated free fill; the dormant price and
line pins kept, pure. The dealership
table's pins gained each car's desk and terms and the new faults (no dealer, an empty or
non-text dealer, terms no list or empty, a term no object, no accepts, an unknown settle,
count 0 / 1.5 / "2" / -1, an unknown key inside a term), the prices kept and relabelled as
the DORMANT credits path's data (was: the buying price); the CAR-page pins moved to the
barter shape, each label saying what it was (the heading without `CREDITS:`, the greyed
BARTER rows for the greyed BUY rows, the terms as text for the prices as text where gated,
`Garage.CREDITS_BUY_ENABLED == false` pinned as the shipped state), while `buy_car`'s
machinery - the refusals, the refund round trip, the re-buy "already owned" - stays pinned
by direct calls (was: partly through the BUY row; `_buy_car` is called directly now).
Since TROC-1 slice 2 its job-pay pins moved from credits to the poster's obligation, each label saying
what it was (the result's `obligation` record for `credits`, the obligations file's bytes
for the credits ledger's, the owed-by line for "paid 95 credits", the TROC board for
`CREDITS:`/"Payments received"), the earned-signal pins became "no credit is earned, no
credits.json is written by a job", the schema and the four job configs gained the
`poster`/`poster_owed`/`poster_offers` pins, and the paid-fuel section stakes its own 95
credits (was funded by JOB-01's pay) - since slice 4 the stake is the witness that no fill
spends. The credits ledger is pinned as before.
The refuel test has 64 checks (`REFUEL TEST PASSED`), measured on the host, since TROC-1
slice 4 (was 57): its wired section is the trade now (was ECON-3's paid fill), on an
obligations file of the test's own under TMPDIR with a credits file wired beside it as the
dormant path's witness: the 4 L fill writing `OBL-0001` to the field (creditor `E2.4`,
debtor `player`, owed `fuel 4 L`, kind `fuel-voucher`, origin `refuel`, open, no
redemption, no transfer) and `last_obligation` on the node the same, the credits bytes
unchanged, the 30-tick hold from 20 L leaving one fill and one record, the whole-litre
rounding, a later build's file refusing the trade on every tick (no fuel, no tmp file),
the overrides cleared (the free fill, the old line, the folder gone) and the driver's own
`obligations.json` stamped and held; the trade's pure pins (`fill_litres`, `owed_text`,
`troc_line`) and the dormant path's (`fill_cost`, `hint_line`, the flag off) beside the
key pins.
The sound test adds 134 checks (`SOUND TEST PASSED`), measured on the
host (was 92 -> SOUND-5's forty-two, the cat mix as a setting: the `SoundSettings` store
pure and on a file of the test's own - the defaults with NO cat mix chosen (the Conductor's
amendment: an absent file is today's `FD_CAT` semantics, not cat_mix true), the seed list's
seventh file, the clamp and the snap, the atomic write with exactly the three fields, a
trim-only file carrying no `cat_mix`, the tolerant reader's corners and a later build's
file refused, the gated store writing nothing; the precedence as one pure function,
exhaustive - `FD_CAT` unset / `0` / `1` / exotic x the file absent / cat on / cat off,
twelve pins - and `FD_SOUND=0` over all of them on a real car; the file-present corners on
bare cars (OFF under `FD_CAT=1`, ON under unset, the caller's `0` over ON); the master
trim +3 on four live loops and a thump with the fields untrimmed, the stopped engine
staying muted, -24 flooring the faint wind at `MUTE_DB`, 0 bit-identical to no file;
every earlier pin standing without a seam; the seed-list pins of the first run, credits and
obligations tests moved to the seven files, `sound_settings.json` last, each with its was->;
was 91 -> SOUND-4's one measured check on the built PCM, the band ceiling: the
squeal's RMS over 2000..4000 Hz at 0.000023 of its RMS over 300..1800 Hz, 0.1 at most - the
pin is on an absence - and the 300..1800 Hz band 99.95% of the buffer's energy - with the
table (46 partials over 300..1300 Hz, no two closer than 25 cycles), zero-crossing (1802 a
second, pinned 1300..2400, still over the rumble's 792) and cat
solid-volume pins moved to the friction-noise squeal and its -12 dB ceiling inside their
existing checks; was 73 -> CAT-AWARE-1's cat battery, eighteen: with `FD_CAT=1` the one shared `Cat` audio
bus and its 3000 Hz low-pass, all eight players routed to it, the squeal written at x0.6 pitch and
-6 dB (-18 dB at solid since SOUND-4, was -10), the thump at x0.8 pitch and -8 dB, the other channels untouched, the bus made by the first
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
since SOUND-5 the menu test has ten checks more, 165 (was 155): the SETTINGS page's four
rows (was two - the folder rows; the cat mix and master trim rows after them, over a sound
settings file of the test's own with `FD_CAT` taken off and `FD_TELEMETRY=0` for the
section, restored), `Enter` flipping and choosing the cat mix, stepping the trim, wrapping
from the floor to the ceiling, the store's clamps in the labels, a caller's `FD_CAT=0`
named in the label, `FD_CAT=1` with and without the file, and the gated rows greyed;
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

About five and a half minutes: it builds the Ring five times (once the ordinary way, four
times through the loading scene) and drives 2 km twice. It checks the `Streaming` autoload
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

THE RETIREMENT (slice 3) rides on the same three streamed Rings, no build more. What the
scheduler does: once the tail has completed, a chunk it streamed whose box is farther
than `R_RETIRE_OUT_M` = 4 500 m from the car is retired (its `MeshInstance3D` and mesh
freed, its job record and every tally kept); a retired one nearer than `R_RETIRE_IN_M` =
3 000 m is rebuilt through the tail's own pending set; between the radii and exactly on
them nothing changes. Only the tail's chunks retire - never the vicinity's, a resident
job, anything under Road, a one-shot Ring or the pad. The counters `chunks_retired` and
`chunks_rebuilt` are additive (a chunk counts each time; `chunks_away()` is the state);
the builders' `describe()` lines and counts never move. What the test pins, every
expected set and order from ITS OWN state machine over the job names and boxes
(`_expect_stop`, squared distances, strict comparisons), never the scheduler's:

| check | how | pinned |
|---|---|---|
| (a) the standing car | the scheduler's own `_process`, the car at the Karussell and at Aremberg | the streamed chunks past 4 500 m retire (123 of 262; 162 of 289) in the order (builder, CHUNK_ORDER), their nodes and meshes dead (instance ids and weak references taken at the completion), the others alive, nothing rebuilt; `describe()` and every count the one-shot's; every child standing byte-equal |
| (a) the moving car | the scheduler's own `_process` along the pit's 2 km drive | every retirement of a tail chunk farther than 4 500 m from the car in that frame, every rebuild of a chunk retired before; the car stopped, the state is the state machine's. No count printed: when the tail completes along the drive is the wall clock's |
| (b) away and back | by hand: `set_process(false)`, `step(at)` | to the other corner (4.9 km) and back: the retirements in order, the rebuilds in the order (band from the car, builder, CHUNK_ORDER), each rebuilt child's SHA-256 its first build's and the reference's; chunks in the 3 000-4 500 m band unmoved on the return, both kinds |
| (c) the radii | by hand, west of one forest chunk's own box at 2999, 3750, 4499, 4500, 4501, 4500, 3750, 3001, 3000, 2999 m | standing, standing, standing, standing (exactly on the radius), RETIRED, retired, retired (where it stood on the way out), retired, retired (exactly on the radius), REBUILT; at each stop every other tail chunk as the state machine says |
| (d) what never retires | by hand, the car 57 km off | every tail chunk retired, the children under the three builders the handover's names in the handover's order, Road's the reference's; a one-shot Ring and the pad stepped the same way lose nothing, the scheduler idle |
| (b) every chunk | by hand, 30 stops of a 4 000 m lattice across the tail's chunks, then home | every chunk of the tail retired and rebuilt at least once, each rebuild in the pinned order and byte-identical to its first build and to the reference |
| (e) no count drift | after the whole trip (738 retirements and 536 rebuilds at the Karussell, 817 and 600 at Aremberg) | the four `describe()` lines and every count the one-shot's; `chunks_total`, `chunks_at_handover`, `chunks_streamed` as at the completion; `chunks_retired - chunks_rebuilt == chunks_away()`; every child standing byte-equal; the Ring unloaded with chunks retired leaves the scheduler idle, every counter zero |

THE MOVED PIN (was -> now): the tail's completion (the children's set, the per-child
SHA-256, the `describe()` lines, "nothing pending") was read when the test's loop next saw
the tail done - at the pit, after the 2 km drive; now it is taken in `tail_completed`'s
own frame, by the signal, because from the next step on the far chunks retire. The same
three checks with the same words and values. 57 checks (was 36: +1 the band's numbers, +2
the one-shot Ring and the pad, +2 at the pit, +8 at each corner).

THE STAND-IN (slice 4) rides on the same three streamed Rings again, no build more. What
the scheduler does: a retired terrain near chunk that had a mesh leaves
`Standin_<row>_<col>` at its `Near_` child's own index under Terrain
(`TerrainBuilder.standin_job()`, built and added inside the retirement); the rebuild's add
frees it before the near mesh is added; no tally moves for one; a new claim and a Ring's
exit forget them all. The test's state machine follows it (`_follow`: a retirement swaps
the name in place, a rebuild takes the stand-in out and puts the near mesh at the end), so
every stop of the slice-3 trips holds the stand-ins too - name for name in order, each
one put up again to its first one's SHA-256, the scheduler's `chunks_stood_in()` the state
machine's count. What a stand-in IS comes from THE TEST'S OWN ARITHMETIC on the builder's
fields (`_plan_of` over the tile plan and the reach, `_read_mesh` over the mesh's own
arrays, `_judge`), never from the builder's function:

| check | how | pinned |
|---|---|---|
| (f) every stand-in standing | the car standing at the Karussell (3 stand-ins) and at Aremberg (13); then 57 km off, every near chunk of the tail (25; 31) | each covers exactly the cells its near mesh covered, once: a near tile no road reaches as ONE 50 m quad at its corner nodes, a near tile one does at the lattice's 10 m, NOTHING over a cell a road reaches; a skirt under every edge of a 50 m quad that meets a finer tile (a reached tile of the chunk, a near tile of the next chunk) and under no other; every vertex a lattice node at `heights[]` to the bit (a skirt's foot 6 m under one); every triangle a half of a cell or of a tile, clockwise, on the builder's diagonal; a bare mesh in the terrain's own material; the near meshes' triangles (taken at the completion) the plan's cells; 14 982 triangles for 37 368 and 157 174 for 348 344 at the Karussell, 75 674 for 188 582 and 200 760 for 435 338 at Aremberg; the terrain's `describe()`, counts and elements the one-shot's |
| (g) THE ROAD RULE | at the pit anchor, on `Near_1_4` - the near chunk the Karussell lies in, 3.3 km from the pit, roads through it | the stand-in draws its 118 unreached near tiles as one 50 m quad each and its 282 reached ones at 10 m, 3 972 cells kept, no triangle over the 3 078 a road reaches; its coverage is, cell for cell, the coverage read off the near mesh that stood there (6 922 cells, 13 844 triangles); 244 skirts; 8 668 triangles for 13 844 |
| (g) the mutants | built in the test, through the same `_read_mesh` and `_judge` | the road rule inverted - a 50 m quad on every near tile, the reached ones too - FAILS: triangles over all 3 078 reached cells (the roof over a road in a cutting); the reached tiles left out FAILS: 3 972 cells of holes (the slits) |
| (g) the cycle | by hand at the pit, from 57 km off, west of `Near_1_4`'s own box through the slice-3 walk (2999 ... 4501 ... 2999 m) TWICE | the near mesh stands to 4 500 m exactly; at 4 501 m it is freed and the stand-in stands at its index; the stand-in stands all the way back in to 3 000 m exactly; at 2 999 m it is freed (node and mesh dead) and the near mesh is back, byte-identical to its first build and to the reference - never both, never neither; the second lap's stand-in another node, the first one's bytes; at each of the 20 stops the terrain's tallies the one-shot's and every other tail chunk as the state machine says |
| (e) no stand-in drift | after the whole trip at each corner | put up less taken down are the ones standing (70 - 54 = 16 at the Karussell, 93 - 71 = 22 at Aremberg) - the state machine's count, `chunks_stood_in()` and the `Standin_` children under Terrain; 45 and 62 times a stand-in was put up again, each time its first one's bytes; the terrain's tallies never moved |
| (h) a new claim | at the pit, the car 57 km off, 24 stand-ins standing; another Ring (outside the tree, its builders deferred) claimed by hand | the scheduler is the new Ring's alone - no stand-in kept, nothing retired, nothing away; the first Ring's 24 stand-ins stand on untouched however the scheduler is stepped; released, the scheduler idle; at the unload all 24 instances dead |
| (h) a Ring's exit | each corner's unload, 16 and 22 stand-ins standing | every instance dead, `chunks_stood_in()` zero (and `_idle` now asks for it everywhere) |

Nothing about a stand-in's cost is in a line: the triangles above are pure functions of
the checked-in files; the milliseconds and megabytes are in the main README (*The thin
handover and the streaming tail*, MEASURED, the stand-in).

THE MOVED PIN (slice 4; was -> now): (d), 57 km off - was "the Ring is the handover's Ring
again, name for name": the children under the three builders were the handover's lists
and nothing else; now the handover's lists stand as they did, name for name in their
order, and AFTER them under Terrain stand the stand-ins of the tail's near chunks (25 at
the Karussell, 31 at Aremberg; nothing else, nothing under Forest or Buildings). The
check's words are kept and say so at their end; its counts are unmoved. Every other check
of slices 1 to 3 prints the line it printed (the corners' trips are not lengthened: the
stand-in's walk is at the pit, where no trip count is printed) - where one says "every
child standing is the reference's to the byte" it counts the children the reference has;
a stand-in is no chunk of the one-shot build and is held by (f). 70 checks (was 57: +5 at
the pit - (g) x 3, (h) x 2 - and +4 at each corner - (f) x 2, (e), (h)).

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
test writes only to a folder of its own under TMPDIR, removed at the end (TROC-1 slice 4's
trade; was: nothing), the store off
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
