# FACTORY DRIVER — FIRST-RUN FLOW: PIN → TEST CENTRE → LICENCE → VOUCHER → FIRST CAR (design, 2026-09-23)
# Status: 4B-PREP design package, documents only. The driver's verdict (design-synthesis-draft.md
# §8.2): "THE FIRST THING A NEW DRIVER DOES: select the test centre where they will take their
# licence. Passing grants a voucher for a car from a (non-Porsche) dealership". Grounded in the code
# as it stands; the licence semantics are FROZEN and this flow never asks them to change.

## 0. THE FLOW IN ONE PICTURE

```
first start (no world record)          existing systems                          new
─────────────────────────────          ────────────────                          ───
1. WORLD MAP, a pin              ──►   (garage.gd's page patterns)               map state, pin
2. choose a TEST CENTRE          ──►   the pad's licence course, relocated       centre list from the region file
3. spawn at the centre           ──►   main.tscn's car, instructor's car rules   spawn transform from the centre
4. THE STUDY (optional)          ──►   study.gd / study_lessons.gd, as is        nothing
5. L0 sitting, resumable         ──►   licence_manager.gd, as is (FROZEN)        nothing
6. L0 granted → VOUCHER          ──►   record_pass / licence_changed signal      voucher record, dealership id
7. RENTAL (1 h, liveried, eco)   ──►   dashboard fields (OdometerStore.DRIVER_DEFAULTS) rental car config, lock rules
8. FIRST CAR at the dealership   ──►   configs/cars/*.json, odometer_store.gd     a serial-number car config
```

## 1. WHAT EXISTS (cited) AND WHAT THE FLOW LEANS ON

The licence ladder, FROZEN (tests/licence_test.gd header; scripts/licence_manager.gd:28-50):
- `start_l0_sitting()` (licence_manager.gd:245) sits from the first element not yet passed
  (`LicenceExams.l0_resume_index`, licence_exams.gd:378); a complete record is a practice run.
- `_start_exam` / `_start_element` (licence_manager.gd:256 / 274) run the seven L0 elements
  (`LicenceExams.l0_sitting()`, licence_exams.gd:392: theory of 8 questions, parallel park, bay park,
  hill start on the 8 % ramp, three-point turn, reversing course, emergency stop).
- `record_element` (359) keeps a passed element at once; `record_pass` (346) records an exam and
  re-derives the level (`LicenceExams.level_for`, licence_exams.gd:341); `licence_changed` (55) is
  emitted when the level moves: **this is the voucher's trigger**.
- Theory never retaken once passed; per-element sitting memory; resume at first failed element
  (licence_manager.gd:34-43). The flow uses these as they are.
- The skid pad test (`start_skid_pad_test`, 252) and the five handling tests make L1; the first run
  needs L0 only.
- The licence book (`open_book` 385, `checklist` 451) and the garage's LICENCE page
  (garage.gd:476, `licence_text` 486) already show the driver where they stand.

THE STUDY: `Study.start_lesson` (study.gd:103) runs any of the 21 live lessons
(`StudyLessons.catalogue`, study_lessons.gd:119) on the instructor's car; optional, judged by
nothing. The first run offers it before the sitting, unchanged.

The garage (scripts/garage.gd): a CanvasLayer that pauses the tree (`open` 197, `close` 218),
five pages (`enum Page` 44), rows built by `_add_row` (712) and driven by `page_rows` (270) and
`activate_row` (285) so a headless test can walk it (tests/menu_test.gd). `MAPS` (50) already
says "a second entry here is a scene to change to, which _free_drive does not do yet and says so"
(`_free_drive`, 338). The CAR page's `car_entry` (413) and `condition_text` (450) read a
store-shaped entry: the first car's condition shows there with nothing new.

Data: `DataDir` (scripts/data_dir.gd) resolves every `user://` path (`resolve` 140) to the
FD_DATA_DIR folder with copy-only seeding (`seed_on_startup` 261; scripts/data_bootstrap.gd runs
it as an autoload). `OdometerStore` keeps ONE file, `user://cars.json` (`PATH`, odometer_store.gd:68),
an entry per car: odometer, fuel, driver, battery, wear, licence (`LICENCE_DEFAULTS` 140,
`save_licence` 439). The licence rides the CAR's entry (odometer_store.gd:7-8 "an entry per car").
Telemetry (`scripts/telemetry.gd`) writes `user://telemetry/` (55) and records only with a
window (`should_record` 105).

The car: `ArcadeCar.CONFIG_PATH` (car.gd:131) is one JSON, `configs/cars/boxster_986.json`
(`identity.name`, `identity.car_id`, mass ledger, engine ...; configs/validation.gd checks it,
tests/config_test.gd runs the check). A second car is a second file of the same shape.

## 2. STEP 1-2 — THE WORLD MAP AND THE PIN

- Where it lives: a full-screen state built like a garage page: a CanvasLayer with
  `PROCESS_MODE_ALWAYS`, the tree paused, rows for the keyboard (`_add_row`-style entries the menu
  test can walk with `page_rows()` / `activate_row()`), Enter to confirm, Esc does nothing on a
  first run (there is no world to go back to). Proposed as a NEW `WorldMap` layer, not a sixth
  garage page: the garage is "a pause overlay over the pad" (garage.gd:3) and the map precedes
  the pad. After the first run the garage's DRIVE page gets a row "World map" that opens the same
  layer (the "map" row kind, garage.gd:314-316, already exists for maps).
- The map: zoomable, the pin the driver drops is the *first spawn's region*. Rendering source is
  DEFERRED (a plain raster of the skeleton is enough; no tiles service in 4B). Zoom levels: continent
  → region → the region's test centres.
- The list under the pin: the test centres of the region the pin falls in, from the region's
  focus file (ring-region-decisions.md §4: the Ring region has one, at Fahrschule Hecken / the
  estate). A region with no centre yet says so ("no test centre here yet — nearest: …") rather
  than pretending; the synthesis rule "No fake content".
- Persistence: NEW `user://world.json` beside cars.json (same `DataDir.resolve` path, same
  copy-only seeding: `DataDir.SEEDED_FILES` would gain the file, a one-line additive change in
  4B-6): `{"version": 1, "driver": {"spawn_region": "eifel_ring", "test_centre": "<id>",
  "vouchers": [...], "rental": {...}}}`. The schema is DEFERRED to implementation; the rule is
  not: the licence stays in cars.json per car, the driver's world state goes in world.json.

## 3. STEP 3 — WHAT THE TEST CENTRE CHOICE CHANGES

- The spawn: the car appears in the centre's yard, facing the yard's start line, in the region's
  world (the pad's licence course relocated: element E8's yard = the pad's course geometry from
  test_pad.gd's "Licence course" section, `_build_licence_course` 912, on flat ground). The pad
  scene stays as it is for tests and certs (implementation-plan.md 4B-4).
- The region in focus: the centre's region is the one dressed and loaded around the car.
- The instructor's car: the sitting's car rules are the licence manager's (manual through the
  hill start, automatic from the turn; licence_manager.gd:435-437) — unchanged.
- The dealership the voucher is honoured at: the region's E4 (the Ring: Autohaus Rausch, way
  831174023, unbranded), written into the voucher record.
- Nothing about the exam's content changes with the centre: same seven elements, same checks
  ("the economy cannot lie", licence_exams.gd:59).

## 4. STEP 4-6 — THE STUDY, THE SITTING, THE VOUCHER

- THE STUDY: offered as it is; the WorldMap layer's last row is "Go to the yard"; the garage's
  STUDY tab is reachable from the yard as today.
- The sitting: started from the licence book (key 1) or the garage's DRIVE row (garage.gd:331),
  exactly as today. Fail → the next sitting resumes at the failed element (FROZEN). Abort → the
  same. The theory, once passed, is never asked again (FROZEN).
- The voucher: on `licence_changed(level)` with `level >= LicenceExams.LICENCE_L0` (emitted from
  `_record_changed`, licence_manager.gd:374-375) a NEW `VoucherLedger` writes
  `{"kind": "car", "class": "general", "dealership": "<E4 id>", "granted_by": "L0", "spent": false}`
  into world.json. `record_pass` is not touched; the ledger only listens. Granted once: a practice
  run changes no record, so `licence_changed` never fires again for L0 (licence_manager.gd:329).
- Shown: the PASSED banner's detail line already carries "licence held: L0 CITIZEN"
  (`_show_result`, 493); a second line "voucher: one car, <dealership name>" is additive text.

## 5. STEP 7-8 — THE RENTAL AND THE FIRST CAR

The driver's rules, verbatim (docs/design/user-thoughts-economy.org lines 68-75):
> you can rent for free for 1 hour if you don't own a car
> (which is the first time the user gets in the world after passing certification,
> certification also gets them a voucher for a car, a non porsche car, the branding
> is less important though). with the rented car,
> which is a porsche even if you are not a chief test driver,
> but has a liver with the dealership name and that is a rental,
> only eco mode available, can't turn tcs, sc or abs off.
> there are two types of dealerships, one is for porsches and one is for regular cars.

- The rental: a car entry whose dashboard is pinned: `gearbox_mode: "eco"`, `tcs_on/abs_on/sc_on:
  true` (the fields of `OdometerStore.DRIVER_DEFAULTS`, odometer_store.gd:89), with the aid switches
  refused the way the licence gate refuses them today (`LicenceManager.allows`, 208: the same
  hook, a second reason). One hour of driving on the tick clock (60 Hz × 3 600 s), then the car
  must be back at the dealership. Livery: the dealership's serial name on the doors (the E4 shell's
  sign texture reused). It is "a porsche even if you are not a chief test driver": the existing
  boxster_986 config with the rental lock and livery.
- The first car: a NEW config `configs/cars/<serial>.json` of boxster_986.json's shape: a
  non-Porsche, unbranded, "as performant as a standard porsche or above, but not as careful
  drawn" (synthesis §8.2): Porsche-inspired specs with a serial-number name
  (`identity.name: "FD-1001"`, `car_id: "fd_1001"`; the naming scheme is DEFERRED, the rule is not:
  no trademarks). Its condition, wear and licence ride cars.json like the Boxster's
  (`OdometerStore`'s entry per car, odometer_store.gd:3-8). NOTE: the licence is per car today; a second car starts
  UNLICENSED in its own entry. Whether the licence should follow the driver (world.json) instead
  is an open question for the driver, not something this flow decides.
- Spending the voucher: at the E4 building, a NEW garage-style row "Take the FD-1001 (voucher)":
  sets `spent: true`, adds the car's entry, makes it the car in the scene. Registration numbers
  (economy.org line 78) are a field on the entry: DEFERRED.

## 6. EXISTING vs NEW (the audit)

| Piece | Exists today | New in 4B |
|---|---|---|
| L0 exam, resume, theory memory | licence_manager.gd, licence_exams.gd, FROZEN | nothing |
| L0 grants the level | `record_element` → `_record_changed` → `licence_changed` | nothing |
| THE STUDY | study.gd, 21 lessons | nothing |
| Menu patterns a test can drive | garage.gd rows, `page_rows`, `activate_row`, menu_test.gd | a WorldMap layer using the same patterns |
| Maps as scenes | `Garage.MAPS`, `_free_drive` refuses a second scene honestly | the second scene (the region world) and the change-scene path |
| Data folder, seeding | data_dir.gd, data_bootstrap.gd | world.json in `SEEDED_FILES` |
| Per-car store | odometer_store.gd | a second car id in the same file; no schema change |
| Car config | boxster_986.json + validation.gd | one serial-number config |
| Aid lock reason | `LicenceManager.allows` (the gate) | a rental reason through the same hook |
| Voucher | — | VoucherLedger (world.json) listening to `licence_changed` |
| Pin, map render, test-centre list | — | WorldMap layer; region focus file |

## 7. DEFERRED TO IMPLEMENTATION

- Map rendering source (skeleton raster vs OSM tiles: no network in-game, so a baked raster).
- Pin persistence schema (world.json fields above are a proposal).
- Dealership placement data beyond the Ring (the region files decide).
- The serial-number naming scheme and the first car's exact specs (the "Catorsche" is the driver's
  name for the 911-class Porsche, not for this car).
- Whether the licence follows the driver or the car (today: the car).
- The rental's hour: what happens at 60 min (return prompt vs the car stops being drivable).

## Open questions
1. Licence per car (as built) vs per driver: with a first car handed over after L0, the new car's
   entry would read UNLICENSED. Proposal: the world record carries the driver's licence copy and
   `allows()` reads the better of the two; needs the driver's verdict.
2. Is the 1-hour rental in the tick clock (pausable, deterministic) or wall clock?
3. Does the first run *force* the map (no Esc), or may the driver skip to the pad as today?
4. One test centre per region minimum: for regions without a driving school in OSM, place by rule
   at the largest `place=town`?
5. The voucher's dealership: the region's E4 only, or any E4 in Europe ("driver must go to the
   dealership which is exactly positioned on the world map", economy.org line 66)?
