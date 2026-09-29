# ECON-1: credits, jobs and the starter job board

A driver can now be paid. Four courier jobs between the Ring's fuel stations
sit on a job board in the garage; a job driven to a pass adds its reward to
a credits ledger of its own, `user://credits.json`. The promotion ladder
(FD-01..FD-33) is unchanged and pays nothing: the ladder and the economy are
separate loops that share one runner.

## Design

### Credits are the accounting unit, not the economy

The canon economy is TROC (`docs/design/design-synthesis-draft.md` §4: no
money; goods, services and vouchers exchanged for each other). ECON-1 does
not replace that. The orchestrator's ruling: credits are the economy's
numeric spine, the unit a paid job adds to, which the barter layer will
price against when it arrives. Nothing can be bought with them yet.

### The ledger: `scripts/credits_ledger.gd`, class `CreditsLedger`

A `RefCounted` with a signal, no autoload and no node (the
`VoucherLedger` precedent). `MissionRunner` holds one as `credits`; a test
makes its own. It follows the `CampaignStore` store pattern: `PATH`,
`VERSION`, `static var path_override`, `static func active_path()`.

```json
{"version": 1, "balance": 95, "transactions": [
  {"seq": 1, "kind": "earn", "amount": 95, "reason": "job:JOB-01"}]}
```

| Field | Rule |
|---|---|
| `version` | 1. |
| `balance` | Whole number of zero or more. **Derived**: the sum of the accepted log. |
| `transactions[].seq` | 1-based, contiguous. **Derived**: the entry's place in the accepted log. |
| `transactions[].kind` | `"earn"`, the only kind written and the only kind read. |
| `transactions[].amount` | Whole number above zero. |
| `transactions[].reason` | Nonempty text. The runner writes `job:<mission id>`. |
| `transactions[].at_s` | Optional; finite seconds of zero or more. |

`earn(amount, reason, at_s := -1.0)` validates, reads the file as it stands
on disk, appends one transaction, writes the whole file to `<file>.tmp` and
renames it over the file (`CampaignStore._commit`'s pattern), emits
`earned(transaction)` and returns the transaction as written. It returns
`{}` and changes nothing when the store is gated, the amount is not above
zero, the reason is empty, the time is not finite, the file is a later
build's, or the write fails.

**Reading is tolerant and never writes.**

| The file | What is read |
|---|---|
| Missing, or the store gated | The defaults: balance 0, an empty log. No problem reported. |
| Missing `balance` | The sum of the log, without complaint. |
| `balance` that is not the sum, or not a whole number | Reported in `problems`; the sum is adopted. |
| An entry that is none of the ledger's own | Reported and left out; the rest is renumbered. |
| A wrong or missing `seq` | Reported; the entry's place is used. |
| `transactions` that is no list | Reported; an empty log. |
| `version` 0, or none | Read as version 1. The first write stamps 1. No other migration exists. |
| `version` above 1 | The defaults. `newer_file` is set and `earn` refuses: an older build never writes over a newer build's money. |
| `version` that is no whole number of zero or more | The defaults. |
| Malformed JSON, or a file that is no object | The defaults. The next committed earn replaces the file. |

An entry's unknown extra fields ride along. Unknown top-level fields are not
carried through a write.

### Gating

`active_path()` returns `path_override` where a test set one, `PATH` where
`OdometerStore.enabled()` is true (the running game), and `""` headless.
Gated, the ledger reads nothing and `earn` keeps nothing, in memory or on
disk. The suite therefore writes no credits file unless a test opts in with
a file of its own.

### Jobs are missions

`MissionSchema.validate` gains two optional fields.

| Field | Rule |
|---|---|
| `reward_credits` | A whole number above zero. Absent means the mission is not paid. |
| `job_kind` | Nonempty text, free vocabulary (`courier`, `testdrive`, `scouting`, ...). Refused without `reward_credits`. |

`reward_credits` without `job_kind` is valid; the garage then shows the kind
as `job`. No ladder config carries either field.

`MissionRunner` gains `JOBS_DIR := "res://configs/jobs"`. The production
scan reads `configs/missions` and then `configs/jobs` into the one catalog,
the ladder first. Jobs start through the same `start()`, are scored by the
same `tick()` and are recorded by the same `campaign.record_result`.

### The payment is single-shot

`finish()` records the campaign result, then, only where the mission has
`reward_credits`, calls `pay_last_result()` and stores what was paid in
`last_result.credits`. The pay does not wait on the campaign record: a
result that could not be saved is still paid.

`pay_last_result()` pays the job `finish()` last closed, once:

- `start()` numbers the episodes (`_episode`). A committed payment remembers
  its number (`_paid_episode`). A second call for the same episode returns 0.
- It pays only when `last_result` is a pass of the job `finish()` closed.
  A failed result pays nothing. `abort()` clears the result and the payable
  job, so an aborted job has nothing to pay.
- `finish()` returns at once when no episode is active, and `_cleanup()`
  clears `active` before the signal is emitted, so a second `finish()` does
  nothing.
- A payment the ledger refused (gated, or a write that failed) is not
  remembered as paid. A retry may still commit it, once.
- Passing the job again is a new episode and pays again. That is correct:
  real work, real pay.

A mission without `reward_credits` never reaches the ledger and its result
has no `credits` field. The idle runner reads no ledger file: the garage's
JOBS page reads it when the page is built.

## Judgments and rulings

| Choice | Ruling | Reason |
|---|---|---|
| `credits.json` or a field of `world.json` | A file of its own. | `world.json` is the driver's place in the world and is written by the first-run flow. An append-only money log has another writer, another growth rate and another corruption story. |
| `configs/jobs/` or `configs/missions/` | A directory of its own, one catalog. | The 33 ladder configs stay byte-identical and the ladder test's file pins stay about the ladder. One catalog keeps one start path. |
| A seventh page or rows on MISSIONS | A seventh page, `JOBS`. | The MISSIONS page already carries 33 rows and the reward rows; four paid rows at its end would be buried. The balance needs a heading of its own. Two loops, two pages. |
| Double pay | Single-shot per episode, remembered only when committed. | See above. |
| The `at_s` clock | Optional; the caller's deterministic tick clock; the runner supplies none. | No wall clock anywhere: the suite's output is the same on every run. A job's entry carries no time rather than a machine's idea of one. |
| `job_kind` vocabulary | Free text. | Three kinds are named in the brief and more will come; a closed list now would need a schema change for each. |
| Job failure conditions | None. | Paid drives are relaxed, not exams. Gates are still ordered; only the time limit fails a job. |
| Station names | Place names, not brands. | The focus table's OSM names include fuel brands; the project keeps buildings unbranded in-game. Ids (`E2.2`) are in every briefing. |
| Spending | Not implemented. | The dealership and voucher flows stay uncoupled. `KINDS` reserves the field; a `spend` entry is refused by this build's reader. |

## The job board

All four jobs are `junior`, `environment: "ring"`, `job_kind: "courier"`,
with `unlock = {"required_rank": "junior", "required_missions": []}`: any
enrolled driver may take any job, in any order.

| Id | Route | Driven | Pay | Limit | Scripted | Gold / silver / bronze |
|---|---|---|---|---|---|---|
| JOB-01 | Paddock station E2.4 to Döttinger Höhe E2.2 | 8.80 km | 95 | 1740 s | 853.250000 s | 896 / 1067 / 1280 s |
| JOB-02 | Döttinger Höhe E2.2 to Paddock station E2.4 | 10.23 km | 100 | 1860 s | 922.500000 s | 969 / 1154 / 1384 s |
| JOB-03 | Döttinger Höhe E2.2 to Adenau station E2.3 | 14.99 km | 130 | 2760 s | 1356.633333 s | 1425 / 1696 / 2035 s |
| JOB-04 | Adenau station E2.3 to Döttinger Höhe E2.2 | 18.04 km | 150 | 3420 s | 1707.550000 s | 1793 / 2135 / 2562 s |

- **Pay** is `round to 5 of (40 + 6 x driven km)`: a base for turning up and
  a rate for the distance.
- **Limit** is twice the scripted time, rounded up to the minute. The
  scripted drive cruises at 14 m/s (50 km/h) with a 2.5 m/s² lateral budget,
  so the limit is met at an average of about 18 km/h: the canon's "achievable
  even in eco mode".
- **Medals** are `ceil(measured x 1.05 / 1.25 / 1.50)`, the house formula.
- **Episode**: `delivery_pickup` at the pickup station, three
  `waypoint_gate` at the quarter points of the leg between the stations,
  `delivery_return` and `timed_finish` at the delivery station. Station
  gates are 30 m, route gates 20 m. Gate heights are the road field's at
  the gate.
- **Stations** come from `data/regions/eifel_ring/focus.json` through
  `Buildings.stations()` and `Record.position()`. The test pins each
  station gate to that position within a millimetre.

Every distance includes the drive from the pit spawn to the pickup station:
3.4 km to E2.4, 3.6 km to E2.2, 6.6 km to E2.3.

### What the Ring allowed

Nine E2 records exist. Three are usable.

| Station | Status |
|---|---|
| E2.2, E2.3, E2.4 | Inside the drape's coverage and reachable from the pit spawn. |
| E2.1, E2.9 | Inside the coverage, on a road component with no drivable link to the spawn. |
| E2.5, E2.6, E2.7, E2.8 | Outside the drape's coverage (x 0..7000 m, z -6000..0 m). No road is built there. |

The routes were planned on the covered skeleton and then driven. Four facts
of the built world shaped them:

- **The spawn faces the one-way Nordschleife.** Every job begins with a left
  U-turn of 7.5 m radius inside the pit junction's guard-rail gap.
- **The Nordschleife's guard rails stand on the pit lane.** The rail 1.5 m
  beyond the loop's pavement runs 0.6 m from the pit lane's centreline. The
  routes hold the lane's far half.
- **Forest trunks and the station shells are solid.** The routes keep 1.5 m
  from every rail, trunk and shell. The B6 station shell is a solid 12 x 8 m
  box on the station's position, which is why a station gate is a 30 m
  drive-through beside it.
- **Grade-separated crossings are walls.** The height field is
  single-valued, so a road passing under the track meets a step. Segments
  whose gradient along the road changes by more than 0.30 between half-metre
  samples are avoided; those above 0.08 are driven at 5 m/s. JOB-03 has
  five such slow stretches and JOB-04 nine; JOB-01 and JOB-02 have none.

Two consequences are disclosed rather than hidden. JOB-01 turns round at the
paddock station with a second U-turn on the 8.5 m Grand Prix pit lane; a
U-turn at Döttinger Höhe was tried and refused by a 34 % embankment. JOB-03
and JOB-04 use 4.2 km and 5.4 km of raceway, and gravel, dirt and grass
tracks, because the asphalt links to Adenau cross the hazards above.

## Garage

`Garage.Page` and `PAGE_TITLES` gain `JOBS` after `MISSIONS`. The page shows
the credits held, the count of payments and the last one, any ledger
problem, and one row per paid job in the catalog:

```
DONE — JOB-01 — Courier: Paddock station to Döttinger Höhe  —  courier  —  95 credits
```

The `DONE` mark comes from the campaign result's medal. The hint carries the
briefing, the lock reason or `Enter to start — ring`, and the best time and
attempts. A row starts the job through `MissionRunner.start` like an
episode. The MISSIONS page skips paid jobs. The page rebuilds on
`campaign.changed` like MISSIONS and CAR. No new store, no new singleton.

## Tests

| Test | Before | After |
|---|---|---|
| `tests/credits_test.gd` (new) | - | **225 checks** |
| `tests/mission_ladder_test.gd` | 1487 checks | **1525 checks** |
| `tests/menu_test.gd` | six-page pin | seven-page pin; the JOBS page passes the readability walk |
| `tests/run_tests.sh` | 34 markers | **35 markers**: `credits test` before `first run test` |

`credits_test.gd` covers, with a per-process folder under `TMPDIR`:

- **Idle and gated**: a fresh runner and a gated ledger touch no file.
- **The ledger**: round trip; refused amounts, reasons and times; the
  balance derivation repair; every kind of bad entry; renumbering; version
  refusal above 1 and the bytes left alone; version 0 and none; malformed
  files; the failed rename that publishes nothing.
- **The schema**: the battery for `reward_credits` and `job_kind`.
- **The configs**: the four jobs validate; rank, unlock, kind, episode
  shape, station positions, coverage, pay formula, limit formula, medal
  formula, briefing content, pairwise distinctness.
- **The payment**, on the pad with a test-only paid fixture: unpaid missions
  inert; fail, timeout and abort pay nothing; a pass pays once; a second and
  third `finish()`, the result delivered again and a listener asking inside
  the signal pay nothing; a replayed pass pays again; pay without a saved
  result; a refused write retried once; gated pays nothing; a real pad drive.
- **The Ring**: the board locked for a driver who is not enrolled and open
  for a junior; **JOB-01 driven to a real pass** through its shipped
  controls on the fresh Ring car, the measured time equal to the recorded
  provenance, the odometer equal to the recorded distance, no airborne tick,
  95 credits on disk; **JOB-02 driven to a real failure** through its
  shipped controls against a 45 s deadline, no credits; the board afterwards.
- **Isolation**: the driver's own `credits.json` is as it was.

The ladder test's additions: the discovery pins move from 33 to 33 + 4;
every ladder mission is pinned to carry neither field (33 checks); the four
jobs are pinned as paid ring jobs off the ladder (4 checks); the JOBS page
on the pad lists them greyed and the runner refuses them there (1 check).
The terminal pin now reads the ladder's ids, not every catalog id.

## Measurement and verification

The traces were recorded by a temporary pure-pursuit pilot kept outside the
repo. It drove the real Ring car through `MissionRunner`'s scripted
`HandlingTests` driver, adding one step per 0.1 s just before the tick that
consumes it. Steps that change nothing were merged into the next step's
`after`. Each shipped script was then replayed through the unchanged runner
on a fresh scene and reproduced its recording to the tick:

| Job | Replay | Odometer | Airborne ticks | Steps |
|---|---|---|---|---|
| JOB-01 | 853.250000 s | 8795.956 m | 0 | 5061 |
| JOB-02 | 922.500000 s | 10231.301 m | 0 | 5005 |
| JOB-03 | 1356.633333 s | 14986.909 m | 0 | 7196 |
| JOB-04 | 1707.550000 s | 18041.459 m | 0 | 9385 |

The traces are open-loop. They pass on the car they were recorded on: a
fresh scene, cold tyres, a full tank. The suite drives JOB-01 only; JOB-02,
JOB-03 and JOB-04 were replayed once each at the landing and are pinned in
the suite by their provenance and formulas, not by a drive.

Standalone verdicts on the host, Godot 4.7.2, headless, fixed 60 Hz:

```
CREDITS TEST PASSED: 225 checks
MISSION LADDER TEST PASSED: 1525 checks
MENU TEST PASSED
```

Two runs of the credits test gave byte-identical logs. `SCRIPT ERROR`,
`ERROR:` and `Parse Error` count zero in all three logs.

One sequential `bash tests/run_tests.sh` at the landing: 35 markers,
`== all checks passed`, exit 0, 4,726 ok lines (4,461 + 225 credits + 38
ladder + 2 for the JOBS page's readability walk in the menu test), zero
error lines, and `grep 'metrics:' | cmp` against
`/tmp/fd-4BPREP-cert-base.txt` IDENTICAL (33 lines). The second sequential
run and the `--parallel` run are the orchestrator's.

## Not done

- **Spending.** No purchase, no price, no coupling to the dealership, the
  vouchers or the rental.
- **TROC barter.** Goods, services and vouchers are not exchanged.
- **Tips and early-arrival bonuses.** A medal changes nothing about the pay.
- **Multiple simultaneous jobs.** One episode runs at a time.
- **Cargo, stopping, traffic, police and damage.** Gates are drive-throughs.
- **Starting a job where the car stands.** Every job starts at the pit
  spawn, as every mission does.
- **A closed-loop job driver.** The shipped traces are recordings.

## Known gaps for a follow-up

- `DataDir.SEEDED_FILES` does not list `credits.json`, so a newly chosen data
  folder is not seeded with the ledger. `scripts/data_dir.gd` is outside
  this landing's surface. The credits test pins the gap so that closing it
  is a visible change.
- The job configs total 1.6 MB of recorded trace, more than the 33 ladder
  configs together (1.2 MB). Every process that loads the runner parses them.
- The guard rail on the pit lane, the wall at the paddock underpass
  (`32743990-0`) and the two disconnected stations are properties of the
  built world, found here and not changed here.

## Files

New: `scripts/credits_ledger.gd`, `configs/jobs/job01_paddock_to_doettinger_hoehe.json`,
`configs/jobs/job02_doettinger_hoehe_to_paddock.json`,
`configs/jobs/job03_doettinger_hoehe_to_adenau.json`,
`configs/jobs/job04_adenau_to_doettinger_hoehe.json`, `tests/credits_test.gd`,
`docs/econ1-implementation.md`, and the engine's `.uid` files beside the two
new scripts.

Changed: `scripts/mission_schema.gd`, `scripts/mission_runner.gd`,
`scripts/garage.gd`, `tests/mission_ladder_test.gd`, `tests/menu_test.gd`,
`tests/run_tests.sh`.

Not touched: `scripts/car.gd`, the profiles, `surfaces.gd`,
`physics_bubble.gd`, the telemetry scripts, `campaign_store.gd`,
`world_store.gd`, `voucher_ledger.gd`, `odometer_store.gd`, `data_dir.gd`,
`handling_tests.gd`, `test_pad.gd`, the scenes, `data/`, `configs/cars/`,
`configs/elements/`, `configs/missions/`, `configs/README.md` (it documents
car configs and lists no config directories), the frozen tests.
