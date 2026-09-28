# ROAD-5 — issue-0068 physical loop edge

Driver issue-0068, verbatim:

> i was with my right tires on the outside of the road but felt like there was no hump, the road now is much higher, but physically doesn't feel like i'm stepping off the road, maybe it's time to add the other elements of the road as well

## Design and freeze resolution

The physical edge lives in `scripts/world_road_profile.gd`, below the existing
`distance <= road.half_width` return. `RingProfile` already delegates road and
blend-band heights through `inner.describe`, so its sample and elevation calls
receive the feature without changing `scripts/ring_profile.gd`. That file is
kept SHA-frozen, despite the earlier editable suggestion in the brief. The
ring-drive test pins profile behavior, not the wrapper file's SHA.

Only a winning road whose `priority` came from skeleton loop membership gets
an edge. There are 92 loop segments. Each uses its own half width, including
the 7.5 m Karussell. No new surface class or grip/drag change: the existing
1.5 m gravel shoulder remains the surface model.

The added height is piecewise linear, zero on pavement, rising to **0.11 m at
0.15 m outside pavement**, then falling to zero at **0.40 m outside**. Beyond
that, the existing six-metre shoulder blend resumes exactly. `ramp_gradient`
continues sampling the old smooth field: adding the narrow lip to its metre-long
difference taps would change gravity for cars still on pavement. The suspension
reads the lip through the wheel heights; the gravity field stays byte-identical.

`RoadBuilder._rumble_arrays` samples the same physical field at the inner toe,
crest and outer toe, with a **0.02 m paint lift**. Both edges use the existing
cross-sections/mitres. A shared shader alternates red/white every two metres of
chainage. There is one new mesh per loop segment, no new collision shape.
Arrays are built in the worker data stage; meshes/materials in the main-thread
node stage. The existing skirt and carved verge remain; terrain code is unchanged.

Actual pipeline versions: skeleton **2**, drape **1**. Neither generator nor
artifact was edited. Skeleton remains `3c05fc5633b2b1bf34ee7572e44877b78eab840e7657bcbeee97e6f39050c11e`;
drape remains `9909c378787636792fc64381d7b6150a5fc0b80da8e5737b5ce2f8f294229e9a`.

## Measurements and proof

Before editing the ROAD-6 tree (`3595494`), 4965 loop points were sampled: each
nondegenerate loop chord's midpoint, at 0, +/-0.5 and +/-0.999 of its own half
width. Each contributes float64 sample height, elevation height and gradient
x/y, hashed as packed bytes. The resulting SHA-256 is unchanged:

`fc59167f9f745e5f1eb497afa1d634a2b090ae99b4b0327ad3050fe8dd820d03`

The new test pins that digest and checks the frozen RingProfile wrapper returns
the same bytes at all 4965 points. Exact-boundary fixture checks include the
paved edge itself on both sides. The existing 200-sample world-profile digest
`aabf29b2a3f05f2d12af64d0efd57e2be348e26cb551db6dacadc7674954231a`
is unchanged, with its original assertion intact. The frozen ring-drive test's
68 checks pass, including its deterministic 2 km drive.

At `(1918.733, 614.433, -1273.017)`, heading 153.1 degrees:

| Contact | Outside pavement | Shoulder height before = after | New lip at same chord location | Drop from lip |
| --- | ---: | ---: | ---: | ---: |
| Front right | 0.403592 m | 614.261885934 m | 614.366879637 m | 0.104994 m |
| Rear right | 0.517559 m | 614.513651210 m | 614.616938551 m | 0.103287 m |

The right wheels are beyond the band: their heights correctly stay unchanged,
while rolling across the edge now encounters the hump first. A deterministic
8 m/s crossing on the straight fixture measures peak vertical acceleration
**1.567910 -> 14.586169 m/s²**. All four contacts cross the edge. The new drive
repeated on a fresh car produces identical packed per-tick speed/position bytes.
A widened ROAD-6 side track (`314755146-2`) has 132 edge/shoulder samples identical
to the old smooth field, with no rumble mesh.

## Geometry counts and pins

The rumble census is explicitly pinned in the new test: **92 meshes, 135444
vertices, 179856 triangles**. Every vertex is checked against physical height
plus paint lift, within 0.1 mm for single-precision storage. New meshes have no
children or colliders. Existing paved-platform counters are unchanged:
3304 roads, 369357 sections, 1109537 vertices, 1467142 triangles, 3304 bodies.

Independent sync/async builds still compare every mesh array, shape and child
order exactly. No old assertion was weakened or old literal pin changed.
`tests/async_build_test.gd` only gains the measured history:

| Build component | ROAD-6 | ROAD-5 |
| --- | --- | --- |
| Road hash prefix | `a76bb21a8ba8d268` | `af1cd69f426516cc` |
| Road meshes / shapes | 6608 / 3305 | 6700 / 3305 |
| Road children | 9913 | 10005 |
| Terrain hash prefix | `cee78c6ead17be04` | `5c5ee1f6ba4d1b4a` |
| Terrain cap count | 364819 | 364933 |
| Forest hash prefix | `ec3096859e758d72` | `3241b4b76c9e000a` |

Terrain (3352 meshes, 2771991 vertices, 4465491 triangles) and forest
(84 meshes / 42 shapes) counts stay the same. Their heights sample the changed
shoulder field, accounting for the hash changes.

## Tests and gate limitations

`tests/road_edge_test.gd` follows side road in the runner: **18 new checks**;
configured suite **2913 -> 2931 checks**, **32 -> 33 markers**. These totals are
configuration counts, not a successful full-suite measurement.

Direct headless assertion verdicts passed: road edge 18, world profile 154,
ring drive 68, async build 15, dressing 120, offroad 36, bubble 17 and
side road 9. Final logs contain
no SCRIPT ERROR or Parse Error. Each direct process still reports three
sandbox startup ERROR lines (user log writes and macOS certificate access),
so these are not clean full gates. Logs: `/tmp/road5-{edge-final,world,ring,async,dressing,offroad,bubble,side}.log`.

Two sequential `tests/run_tests.sh` attempts and one `--parallel` attempt all
exit **1 at import**, unable to save
`/Users/kokos/Library/Application Support/Godot/editor_settings-4.7.tres`.
Each prints three ERROR lines, zero assertions and zero metrics. The three
requested suite `grep 'metrics:' | cmp -s - /tmp/fd-4BPREP-cert-base.txt`
comparisons exit 1 because their inputs are empty. Full-suite output equality,
33 completed markers and the zero-error gate remain blocked. This reproduces
the pre-edit failure and ROAD-6's documented sandbox limitation. Logs:
`/tmp/road5-suite-{1,2,parallel}.log`. No runner error filter was relaxed and no
permission bypass was attempted.

Separately, three sequential direct handling/mission/licence/menu runs each
produce all **33 cert metric lines identical** to `/tmp/fd-4BPREP-cert-base.txt`. These direct cert
checks do not turn the blocked full-suite gate into a pass. Logs:
`/tmp/road5-cert-direct.log`, `/tmp/road5-cert-direct-2.log`,
`/tmp/road5-cert-direct-3.log`; the requested grep/cmp command exits 0 for each.

SHA-256 before/after matches for all **22 frozen files**: car, road_profile,
ring_profile, surfaces, physics_bubble, visual_probe, eifel_ring scene, all
seven element JSON files, skeleton, drape, surfaces.json and the five frozen
licence/ring-drive/bubble/offroad/smoke tests. The snapshot is
`/tmp/road5-frozen.json`. No noise paths are included in the intended commit.

## Local commit blocker

The workspace permits source writes but makes `.git` read-only. The explicit
`git add` attempt fails with:

`fatal: Unable to create '/Users/kokos/games/factory-driver/.git/index.lock': Operation not permitted`

No commit was created, no rebase or push attempted. HEAD remains `3595494`,
with `ecfda49` before it and `origin/main` at `18530c5`. The intended verbose
house-style commit message is prepared at `/tmp/road5-commit-message.txt`.
