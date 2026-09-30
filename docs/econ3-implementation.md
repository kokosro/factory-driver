# ECON-3: the spend side — car purchases and paid fuel (with ECON-2's seed fix)

Credits can now be spent. The ledger's reserved `spend` kind is live; the
garage's CAR page carries a DEALERSHIP that sells the three reward cars at
authored credit prices, the fuel stations charge 2 credits a litre, and the
data-folder seed carries `credits.json` (ECON-2, ECON-1's known gap). The
canon economy is still TROC (`docs/design/design-synthesis-draft.md` §4) and
ECON-1's ruling still stands (`docs/econ1-implementation.md`): credits are
the economy's accounting unit; this landing gives that unit its first two
sinks.

## Design, as decided

### ECON-2: the seed carries the ledger

`DataDir.SEEDED_FILES` was `["cars.json", "issues.json", "world.json",
"campaign.json"]` and is now that list with `"credits.json"` last, with a
"was four files ->" comment in the established style. `CreditsLedger.PATH`
follows the driver to a chosen folder: a fresh data folder seeded without it
would zero the balance and, with this landing, lose every car bought from
the log (ownership by the log, below).

Pins: `tests/first_run_test.gd`'s exact-array pin moved from the four-file
list, label "(was the three)", to the five-file list, label "(was the
four)". `tests/credits_test.gd`'s known-gap pin (`not
SEEDED_FILES.has("credits.json")`) flipped to "the seed carries
credits.json, last after campaign.json (was ECON-1's known gap)".
`tests/menu_test.gd`'s seed checks assert membership (`has("issues.json")`)
and the copied lists of their own fixtures, never the whole array: read
before relying on it, and green untouched. `tests/mission_ladder_test.gd`
asserts `has("campaign.json")`: green untouched.

### The price table: `configs/dealership.json`, read by `scripts/dealership.gd`

Prices are NOT fields of the car configs. `configs/validation.gd` is outside
the editable surface and its `OTHER_KEYS[""]` pins a config's top-level
keys to `config_version`, `identity`, `mass_ledger`, `driver_profiles`,
`mode_drivers`: a price in `configs/cars/<id>.json` would be a fault there,
and a price is a shop's number, not a car's. So: one table of its own at
`configs/` root (invisible to `tests/config_test.gd`, which walks
`configs/cars` alone).

```json
{"version": 1, "cars": [
  {"car_id": "fd_1073",     "price_credits": 60000,  "basis": "AUTHORED ..."},
  {"car_id": "boxster_986", "price_credits": 44000,  "basis": "AUTHORED ..."},
  {"car_id": "fd_2000",     "price_credits": 100000, "basis": "AUTHORED ..."}]}
```

| Car | Price | Basis (the file's own string is the provenance) |
|---|---|---|
| `fd_1073` Customised 1973 911 Carrera RS 2.7 | 60 000 | AUTHORED, no source price. The Test Driver reward car as a long-horizon sink: hundreds of the board's 95-150 credit jobs, or a rank-early splurge for a driver who will not wait for FD-12; the ladder stays the primary road. Mirrors how a real RS 2.7 dwarfed a junior driver's income. |
| `boxster_986` 1997 Boxster 986 | 44 000 | AUTHORED, no source price. The Chief reward car, the pad Boxster's own config: the cheapest of the three, the youngest and least exotic, still hundreds of jobs so FD-22's grant stays the ordinary road. |
| `fd_2000` FD-2000 | 100 000 | AUTHORED, no source price. The Ace reward car, the top of the table: a thousand of the board's best jobs, so buying it early is a splurge and FD-33 remains the way most drivers get it. |

`docs/mission-ladder-source.md` and the design docs carry no car prices
(grepped); every basis says "AUTHORED" and why. **The reward cars stay
purchasable even though the ladder grants them**: a price lets a driver buy
a reward car early, the 2000 game's own dealership shape, and the ladder's
grant is untouched (`CampaignStore` is frozen and not edited: its
ownership is rank-keyed, and a promotion still owns the car). **`fd_1001`
is absent on purpose**: the serial-number car is the L0 voucher's
(`scripts/first_car.gd`), never bought with credits. `configs/README.md`
documents the table in its own voice.

`Dealership` (class_name, `RefCounted` statics, no autoload — the
`VoucherLedger`/`CreditsLedger` precedent) reads and validates, the strict
config house style: every fault listed in `problems`, nothing invented,
nothing written.

| The file | What `Dealership.read()` returns |
|---|---|
| Missing, not JSON, not an object | `usable` false, no cars, one problem ("the dealership sells nothing"). |
| `version` above 1 | `usable` false, `newer_file` true, no cars, reported; the file is left alone (this class writes nothing). |
| `version` not exactly 1 (0, none, a fraction, text) | `usable` false, reported. No version-zero grace: the table is shipped, never migrated. |
| An unknown top-level key | Reported and ignored; the cars are read. |
| `cars` missing or not a list | `usable` true, no cars, reported. |
| An entry that is not an object; a key missing or unknown (exactly `car_id`, `price_credits`, `basis`); `car_id` not a nonempty string or without `configs/cars/<car_id>.json`; `price_credits` not a whole number above zero; `basis` not nonempty text; a `car_id` already listed | Refused and reported (`cars[i] ... it is left out`), the rest kept in file order. |
| A well-formed table with no valid entry | `usable` true, no cars, "no entry is valid, the dealership sells nothing". |

### The ledger's spend side: `scripts/credits_ledger.gd`

- `KINDS := ["earn", "spend"]` (was `["earn"]`, spend reserved). `VERSION`
  stays 1: the schema reserved the kind, no migration, the version-refusal
  semantics untouched.
- A new signal `spent(transaction)` beside `earned`.
- `spend(amount, reason, at_s := -1.0)`: earn's exact mirror — `{}` when the
  store is gated, the amount is not above zero, the reason is empty, the
  time is not finite, the file is a later build's, or the write failed —
  plus one refusal of its own: the file is read first (the entry joins the
  log as it stands on disk, earn's rule) and an amount above `balance()`
  is refused, so the balance never goes below zero through the write path.
  The entry is committed under kind `"spend"` with the POSITIVE amount (the
  kind carries the direction) and `spent` is emitted. Both kinds go through
  one `_commit_transaction`; the earn path's behaviour is unchanged.
- `load_state()` derives the balance as the earns less the spends. A
  hand-edited log that spends more than it earns yields its negative sum:
  reported ("the log spends more than it earns"), kept as it stands (the
  tolerant reader reports, never invents). The stored-balance mismatch check
  compares against that derived total as before.
- `transaction_problem` is unchanged in rule: amount a whole number above
  zero for BOTH kinds, the reason rules the same. A spend entry is now read
  where ECON-1's reader left it out.

| Field | Rule (changes in bold) |
|---|---|
| `version` | 1. |
| `balance` | Whole number. **Derived: the sum of the accepted earns less the accepted spends; may read negative from a hand-edited file, reported.** |
| `transactions[].seq` | 1-based, contiguous, derived. |
| `transactions[].kind` | **`"earn"` or `"spend"`.** |
| `transactions[].amount` | Whole number above zero, **for both kinds**. |
| `transactions[].reason` | Nonempty text. The runner writes `job:<mission id>`; **the garage writes `car:<car_id>` (a purchase) and `refund:car:<car_id>` (its refund, an earn); the station writes `fuel`.** |
| `transactions[].at_s` | Optional; finite seconds of zero or more. |

### The purchase: the garage's CAR page

The CAR page (`scripts/garage.gd`) gains a DEALERSHIP section below the
OWNED/TAKE/SELECTED material and above the store-footer line:

```
DEALERSHIP  —  CREDITS: 44000
The garage's car shop: ... The Ring's general dealership E4.1 in Adenau honours the
voucher from the DRIVE page; this shop is a page of the garage, no building to drive to.
A bought car's entry starts fresh in cars.json and it is selected; live vehicle
swapping is pending, driving still uses the Boxster.
BUY — Customised 1973 Porsche 911 Carrera RS 2.7 Coupe — 60000 credits   (greyed: "... You hold 44000 credits: 16000 short.")
BUY — 1997 Boxster 986 — 44000 credits                                     (live: "... You hold 44000 credits.")
BUY — FD-2000 — 100000 credits                                             (greyed)
```

The heading's balance comes from a fresh `runner.credits.load_state()`
exactly as the JOBS page reads it; the dealership named in prose is honest
(the Ring's E4.1 honours the voucher; the shop is a garage-page
abstraction, no building invented). One entry per table row in file order:
an owned car shows an OWNED line in the established style ("granted at
promotion; listed at N credits, not for sale to its owner" or "bought here
for N credits") and no BUY row; an unowned car shows the row `BUY — <name>
— <price> credits`, kind `buy_car`, id the car_id, hint the basis plus the
balance or the shortfall, enabled iff the balance covers the price and a
world record exists. Insufficient credits is the greyed row with the price
shown, no popup. The table's problems are listed as the JOBS page lists the
ledger's. The last purchase's one-line summary is shown on the page.

**`buy_car(car_id, world_path, store_path := OdometerStore.PATH, store_kept
:= false, target_car := null) -> Dictionary`** (the row's `_buy_car(car_id)`
calls it with `WorldStore.active_path()`, `OdometerStore.PATH`,
`OdometerStore.enabled()`, the garage's car — `take_car`'s signature idiom,
so a test can opt into isolated files). The order:

1. Refused before any write: no runner or gated ledger ("no ledger this
   run"), no world record, a car the table does not sell, already owned
   (by promotion — `campaign.owns_car` — or by purchase), a config
   `CarConfigValidation` refuses, a credits file of a later build's, a
   balance the price exceeds (the greyed row's guard, re-checked).
2. `ledger.spend(price, "car:<car_id>")` FIRST: the debit committed.
3. The store's side exactly as `CampaignStore.take_car`'s branch writes it:
   where `store_kept` and `cars.json` has no entry for the car, a
   `FirstCar.default_entry()` with the tank its config's capacity, through
   `OdometerStore.save_car` + `save_licence`, verified read back (an entry
   the file already holds is kept as it is, `take_car`'s rule); then
   `WorldStore.set_active_car`, verified read back; then a rental on the car
   ended (`RentalGate.active_on(car).end()` / `WorldStore.clear_rental`).
4. If the store's side fails AFTER the spend: `ledger.earn(price,
   "refund:car:<car_id>")` and the failure reported in the result's
   `reason` ("..., the N credits refunded", or "AND the refund failed: the
   ledger holds the debit" when even that write fails).
5. On success the row's caller rebuilds the CAR page: the row becomes
   OWNED, the SELECTED line names the bought car.

Result: `{bought, reason, summary, transaction, refund, entry}`, kept in
`Garage.last_purchase_result`.

**Ownership by the log** (a ruling of this landing): a bought car is owned
exactly as a promotion's reward car is owned — the committed entitlement IS
the ownership, no second flag, no write on load. `Dealership.purchased(
transactions, car_id)` is true where the accepted log holds more
`car:<car_id>` spends than `refund:car:<car_id>` earns. No new store; this is
also why ECON-2 (the seed) is bundled: the ledger now carries the garage's
cars.

**Rows only where a ledger is wired** (`CreditsLedger.active_path() != ""`,
the same switch the ledger itself pays by): gated — headless, no override —
a BUY row could pay nothing and write nothing, so the table is listed as
text with its prices and the page says "No ledger this run (the store is
off)". `tests/menu_test.gd` (frozen) pins the headless CAR page rowless;
this keeps it so honestly rather than by a lie of a row.

### Paid fuel: `scripts/refuel.gd`

- `LITRE_PRICE_CREDITS := 2`, AUTHORED: no source fuel price exists; 2 cr/L
  makes a full 64 L Boxster fill 128 credits, about one good courier job
  (the board pays 95-150), so fuel is a routine but real draw on the job
  income.
- `fill_cost(fuel_l) = ceil(max(FUEL_TANK_CAPACITY_L - fuel_l, 0) x 2)`,
  computed from the tank BEFORE the write: the station rounds up to the
  whole credit (deterministic, no float dust in the balance; a 0.3 L gap
  is 1 credit, a full tank 0).
- The fill tick pays FIRST: `runner.credits.spend(cost, "fuel")`, and only
  then writes `car.fuel_l = FUEL_TANK_CAPACITY_L`. A refused spend (the
  balance cannot cover the cost) is NO fuel, the tank untouched, every
  such tick counted in `refused_count`. All or nothing; a partial fill for
  what the balance can cover is a documented follow-up.
- **The grace seam**: the station pays only where a ledger is wired —
  `MissionRunner.of(get_tree())` exists and `CreditsLedger.active_path()
  != ""`. Without a runner (a bare test node) or with the store gated
  (headless, no override) the fill is free exactly as before and the line
  is exactly `HINT_TEXT`. The unpaid refuel remains until the station-only
  rule lands with the cat ecology.
- The ledger is read from disk once on ARRIVAL at a station (the tick
  `near` turns from null to a record) and in memory after: the runner's
  ledger is the running game's one writer and its state is current after
  every commit of its own (`spend` reloads before committing anyway).
- The HUD line: unwired, today's exact text `FUEL STATION near — hold U to
  fill`; wired and affordable, `FUEL STATION near — hold U to fill (2 cr/L
  — you hold N cr)`; wired and short, `FUEL STATION near — hold U to fill
  (2 cr/L — need ~X cr, you hold N cr)` with X the cost of the tank's gap
  now (~ because the gap moves with the idle burn until the key is
  pressed). `hint_line(cost, balance, wired)` is pure.
- `fill_count` semantics stay: a tick that filled counts, paid or free.
  `paid_credits` sums what the node paid.

## Tests

| Test | Before | After |
|---|---|---|
| `tests/credits_test.gd` | 225 checks | **384 checks** (+159) |
| `tests/refuel_test.gd` | 46 checks | **57 checks** (+11) |
| `tests/first_run_test.gd` | 114 checks | 114 (the seed pin rewritten, five files) |
| `tests/menu_test.gd`, `tests/mission_ladder_test.gd` | untouched | green untouched (the headless CAR page stays rowless; the seed checks assert membership) |
| `tests/run_tests.sh` | 35 markers | 35 markers, untouched |

`credits_test.gd`'s additions, every file under its own `TMPDIR` folder,
the store pinned off:

- **The spend side**: a spend on an empty ledger refused; the amount,
  reason and time refusals; a spend above the balance refused with the
  balance unchanged and nothing emitted; the first spend's transaction as
  written (kind spend, positive amount) and `spent` firing once; the
  balance earn-minus-spend in memory and on disk; the atomic write; a
  time written when given; a spend of exactly the balance to zero and one
  more credit refused; the mixed log's round trip and a second ledger
  joining it; the derived sum against a stored balance that is the earns
  alone; a missing balance derived; the hand-edited negative log reported
  and kept, no spend from it, an earn writing the derived balance; a
  spend-only log's two problems; a later build's file never written over
  by a spend; gated keeps nothing; a write that fails publishes nothing
  and the retry commits; the earn path's rules beside the spend's. The
  ECON-1 pins for `KINDS`, the bad-entry list and the reserved kind
  updated honestly (a kind that is neither stands in).
- **The dealership**: the shipped table clean; each price as documented
  with an authored basis, a config and a name; the three reward cars in
  file order, every `REWARD_CARS` entry; every car under `configs/cars`
  for sale except `fd_1001`, absent; `entry_of`/`price_of`; the three
  reasons; `purchased` (a spend owns, a refund undoes, an earn under the
  purchase reason is no purchase, junk skipped); the validation battery on
  tables of the test's own: a good table, a float whole number, versions
  2/99 (newer), 0/-1/1.5/"1"/null/[]/true and none, non-object and
  malformed files, a missing file, `cars` missing/object/text/null, an
  empty list, an unknown top-level key, 21 bad entries each refused with
  the rest kept in order, a duplicate, a table whose every entry is
  refused; the shipped file never written.
- **The purchase**, on the pad wired to the test's own ledger, world
  record and cars file: the page over a record (no forced map, the tree
  running); three greyed rows with prices, basis and shortfall; a greyed
  row inert; the direct re-check refusal; one credit short greyed, exactly
  the price live; refusals for `fd_1001`, an unknown id, no world record,
  the dearer car, none writing; the forced store failure (a directory in
  the file's place) after the spend refunded exactly under
  `refund:car:boxster_986`, the ledger summing back, nothing selected, the
  row live again; the round trip — the spend under `car:boxster_986`, the
  balance debited exactly once to zero, the `cars.json` entry a new car's
  (read back equal to a car the file does not know), `active_car` set,
  owned by the log and not the ladder, OWNED and SELECTED lines and no BUY
  row; already-owned refused with the entry untouched; persistence across
  a reload and the file's five entries in order; a rank grant OWNED by
  promotion with its TAKE row and no BUY row, unbuyable; the shipped row
  through `activate_row` buying FD-2000 (no entry headless, `active_car`
  set, the page rebuilt naming the purchase); the driver's file untouched;
  the gated page rowless with the prices as text and `buy_car` refusing.
- **Paid fuel**, on the Ring after the job drives, the shipped `Refuel`
  node wired to the runner's ledger holding JOB-01's 95 credits: the price
  and `fill_cost` at eight tanks, `hint_line`'s four texts; the dry run 100
  m off E2.4 (30 ticks held, nothing filled or paid); at E2.4 the line
  with the balance, the first held tick filling to capacity for 88 credits,
  the ledger's spend under `fuel` and one `spent` signal, 30 more ticks at
  a full tank paying nothing, the line following the balance; a 0.3 L gap
  costing 1 credit; the shortfall line; the unaffordable fill (30 refused
  ticks, no fuel, no debit); 1.5 L on 6 credits paid, 3.5 L on 3 refused;
  the ledger gated — the old line exactly and a free fill.

`refuel_test.gd`'s additions: the price, `FUEL_REASON`, `fill_cost` and
`hint_line` pins beside the key pin; on the Ring, after every unwired pin
(kept as it was), the ledger pointed at a file of the test's own holding
50 credits — the line with the balance on arrival, a 4 L fill for 8
credits on the first held tick, the file's spend, the line following, the
shortfall line and 30 refused ticks, then the override cleared: the old
line and a free fill again, the test's folder gone. The determinism check
runs unwired as before.

## Measurement and verification

Standalone on the host, Godot 4.7.2, headless, fixed 60 Hz, the store
pinned off:

```
CREDITS TEST PASSED: 384 checks
REFUEL TEST PASSED          (57 ok)
FIRST RUN TEST PASSED       (114 ok)
MENU TEST PASSED            (155 ok)
```

`SCRIPT ERROR`, `ERROR:` and `Parse Error` count zero in every log.

One sequential `bash tests/run_tests.sh` and one `--parallel` run at the
landing: 35 markers each, `== all checks passed`, exit 0, **4,896 ok lines**
(4,726 at ECON-1 + 159 credits + 11 refuel), zero error lines, the two logs
byte-identical modulo the `fd-3K-licence-<pid>` line, and `grep 'metrics:'
| cmp` against `/tmp/fd-4BPREP-cert-base.txt` IDENTICAL (33 lines) in both:
the change is inert outside its own tests. The five `FAIL`-prefixed lines
in each log are the deliberate-failure mission verdicts (`SLALOM_TEST`,
`SPIN_180`, `HILL_START`) that the handling and licence tests drive on
purpose, as at every landing. The orchestrator re-runs the gates on the
host.

One finding on the way, kept in the test as a pin: a `WorldStore`
override pointing at a file that does not exist yet forces the pad's
first-run map open and pauses the tree, and the pause outlives the freed
scene (`world_map.gd:198`). The purchase section writes its world record
before the pad loads and asserts the tree runs.

## Deviations from the brief, with reasons

- **BUY rows only with a ledger wired.** The brief's "enabled iff the
  balance >= price" holds wherever a row exists; gated, no row exists
  (the table is listed as text). `tests/menu_test.gd` is frozen and pins
  the headless CAR page rowless, and a gated row would be a row that can
  do nothing.
- **`buy_car` takes explicit paths** (`world_path, store_path, store_kept,
  target_car`) beside the row's `_buy_car(car_id)`: `take_car`'s idiom, so
  the cars.json round trip and the forced store failure are testable with
  the store pinned off. The row passes the run's own paths exactly as
  `_take_reward_car` does.
- **Ownership by the log** (above) rather than a new flag: not asked
  for by name, but the only honest answer to "the row becomes OWNED" with
  `campaign_store.gd` frozen and no new store.
- **An existing `cars.json` entry is kept, not overwritten**, `take_car`'s
  rule: the file is keyed by `car_id`, and buying the `boxster_986`
  stand-in must not reset the driven Boxster's record.
- The JOB-01 pass pin's label now carries `runner.result_text()`
  (deterministic), added for the diagnosis above and kept.

## Not done, honestly

- Partial fills for what the balance can cover (all or nothing today).
- Selling a car back; a refund exists only as the purchase's failure guard.
- The live vehicle swap: a bought car is a record and a selection
  (`car.gd` is frozen; `scripts/first_car.gd`'s deferral stands).
- TROC barter, tips, prices for anything else.

## Files

New: `scripts/dealership.gd` (+ the engine's `.uid`), `configs/dealership.json`,
`docs/econ3-implementation.md`.

Changed: `scripts/data_dir.gd`, `scripts/credits_ledger.gd`,
`scripts/refuel.gd`, `scripts/garage.gd`, `configs/README.md`,
`tests/first_run_test.gd`, `tests/credits_test.gd`, `tests/refuel_test.gd`.

Not touched: `scripts/car.gd`, `scripts/campaign_store.gd`,
`scripts/mission_schema.gd`, `scripts/mission_runner.gd`,
`configs/validation.gd`, `configs/cars/*`, the scenes, `data/`,
`configs/elements/`, `configs/jobs/`, `configs/missions/`,
`tests/run_tests.sh`, every other test, the driver's data folder.
