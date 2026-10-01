# TROC Redesign — the Obligations Ledger and Barter Exchanges

## Status: RULED — the build order approved (decisions.org `16036083`, 2026-10-01).

Slice 1 (the ObligationsLedger store + tests) lands with this document; slices 2-4
follow in the ruled order.
The ruling and the driver's own words are canon and are quoted.

---

## 1. The canon, restated

### 1.1 The ruling (decisions.org `85BE93B5`, verbatim)

> THE ECONOMY IS TROC — FULL RULING (driver, 2026-09-30, answering the
> credits challenge): "it also tracks obligations." The economy has THREE
> parts, all canonical: (1) NO single common denominator of value — credits
> are NOT the economy's currency and the credits ledger/balance model was
> the Conductor's mid-shift shorthand that never went through a driver
> ruling (recorded in the ECON-3 landing note); (2) immediate exchanges —
> any service, thing, or fuel voucher can be exchanged directly for any
> other service, voucher, or thing, negotiated per-trade between needs;
> (3) AN OBLIGATIONS LEDGER — when a trade cannot settle immediately, it
> creates a tracked obligation (X owes Y a specific service or item, or
> whatever Y later accepts), redeemable against any of the debtor's
> satisfiable needs. Redesign mapping for what exists: the CreditsLedger
> becomes the OBLIGATIONS LEDGER (deliveries create obligations named by
> the counterparty, with a redemption field for how they were settled — not
> balance arithmetic); the dealership's price list becomes an
> EXCHANGE-TERMS list (what goods/services the dealer accepts per car —
> barter, not debit); fuel stations trade fuel for delivery obligations
> (matching the Cat Matrix rule: 10% social stations free, others barter);
> job board entries publish what the POSTER NEEDS. ECON-1/ECON-3's landings
> (dd2c478, b21819b) stay on main unused-but-harmless — the stores'
> machinery (atomic writes, validation, gating) is reusable, the
> credits/balance/pricing model is not. No economy dispatch without the
> driver's ruling on the redesign's build order.

### 1.2 The driver's own words (docs/design/user-thoughts-economy.org, excerpts)

- "i would like an economy based on troc: goods for goods, services for
  services, services for vouchers, vouchers for services — even if it's
  service for voucher for a car. materials and car components, or tuna for
  the cat, or the new fuel formula that makes the car go faster" (lines 5-13).
- "one thing can be exchange for multiple things. multiple things can be
  exchanged for one thing. a service can be exchange to one or multiple
  things. a next job can be the 'tip' for a job well done, which can give a
  more rare type of material, a voucher for a dealership or some tuna"
  (lines 84-87).
- Stations: "10% of the gas stations are social gas stations that give away
  tuna 5 per visit and fuel for free ... all the other gas stations need you
  to have a cat with you to get gas" (lines 46-49).
- Cars: "Each mission can give the driver materials, components, or a voucher
  for any car at a certain dealership ... need to pay any money for the car,
  because we have vouchers. ... user can have the same car multiple times"
  (lines 64-78). The voucher car (fd_1001, scripts/first_car.gd) already
  works exactly this way and is untouched by credits today.
- Telemetry ripples: "the telemetry of player-driver is also training data
  for the other drivers in the world, the demand created by the user would
  have ripples throughout all the other drivers" (lines 15-16). The
  obligations ledger is where those ripples land: other drivers' needs and
  debts are records in the same shape.

---

## 2. THE MODEL (all PROPOSED; shaped by the ruling)

### 2.1 The obligation record

One record per unsettled or settled debt, stored append-only:

    {"id": "OBL-0007",
     "creditor": "E2.2",                  // who is owed (counterparty id)
     "debtor":  "player",                 // who owes
     "owed":    "one delivery: Adenau to Döttinger Höhe",
     "kind":    "delivery",               // optional typed hint
     "origin":  "trade:JOB-01/episode-3", // what created it
     "status":  "open",                   // open | settled | cancelled
     "redemptions": [                     // how it was settled, possibly in parts
       {"given": "fuel 64 L", "where": "E2.4", "origin": "refuel"}]}

The owed thing is named BY THE COUNTERPARTY, as free text, with `kind` as an
optional hint (`delivery` / `car` / `car-part` / `material` / `favor` /
`tuna` / `fuel-voucher` / `anything`). "Whatever Y later accepts" is a
creditor whose exchange-terms (§2.3) name what they will take in settlement —
the ledger never judges value, the counterparty's terms do. There is NO
total, NO balance, NO arithmetic anywhere: the log IS the ledger. A reader
derives views ("what does E2.2 owe me that is still open") exactly as
CreditsLedger's reader derives `balance` — except nothing is ever summed
into a single number of value.

### 2.2 Immediate exchange vs obligation

- **Immediate**: both sides hold what the other needs at the same place —
  the trade settles on the spot. One thing for many, many for one, service
  for voucher (the driver's lines 84-86). The player's side of a settlement
  comes from what they carry: **the driver's hands are the car and its
  boot** — fuel vouchers (the WorldStore voucher precedent, read by
  garage.gd `WorldStore.unspent_vouchers`), car parts and materials (future,
  with workshops), tuna (future, with the cat ecology), and — question for
  the driver — obligations the player HOLDS as creditor (§7 Q3).
- **Obligation**: the trade cannot settle now (the poster is not at the
  delivery point, the station has no tuna, the dealer wants a thing the
  player must first earn). The trade creates an obligation record and both
  sides go their way. A job delivery is the first concrete case: driving
  JOB-01 creates the poster's obligation TO the player, redeemable against
  any of that debtor's satisfiable needs (their exchange-terms list).

### 2.3 Exchange-terms (the counterparty's side)

Each counterparty carries a list of what they ACCEPT — per car at the
dealership, per station at the pump, per posting at the board. This replaces
every price. It is a menu of acceptable settlements for that counterparty's
obligations and trades, not a valuation: the same delivery obligation may be
worth fuel at one station and a car-part at the workshop, because their
needs differ, not because a number says so.

### 2.4 Where it persists (PROPOSED, judged from the code)

A NEW standalone store, `scripts/obligations_ledger.gd`, class
ObligationsLedger, RefCounted, file `user://obligations.json` — NOT an
extension of WorldStore. Why: CreditsLedger's own header (credits_ledger.gd
lines 19-23) already made this argument — world.json is the first-run flow's
place record with one writer and one growth rate; a trade log has another
writer, another growth rate and another corruption story, so it is a file of
its own (the campaign store's precedent). What transfers mechanically from
CreditsLedger: atomic tmp+rename commits (`_commit`, credits_ledger.gd:243),
the version refusal (`newer_file`, an older build never destroys a newer
one's log), the tolerant reader that reports and invents nothing, the
`path_override` test seam, and the FD_TELEMETRY gating through
`OdometerStore.enabled()` (`active_path`, credits_ledger.gd:96). What dies:
`balance`, the earn/spend kinds, every comparison of amounts.

---

## 3. THE MAPPINGS (what changes in what file)

| Today (ECON-1/3) | Becomes | Where |
|---|---|---|
| `CreditsLedger` (scripts/credits_ledger.gd): earn/spend, balance | `ObligationsLedger`: obligation records, redemptions, no arithmetic | new scripts/obligations_ledger.gd |
| Job payout `credits.earn(reward_credits, "job:<id>")` (scripts/mission_runner.gd:305, `pay_last_result`) | the poster's obligation TO the player, named by the poster, created on delivery | scripts/mission_runner.gd (same seam, single-shot per episode kept) |
| `reward_credits` on job configs (configs/jobs/job01_paddock_to_doettinger_hoehe.json:6, "Pay on delivery: 95 credits") | `poster` (who is owed what), `poster_offers` (what the tip is: rare material / dealership voucher / tuna — the driver's line 87) | configs/jobs/*.json + MissionSchema validation |
| Job board rows ("CREDITS: %d", garage.gd:1145) | each posting shows what the poster NEEDS and what they OFFER | scripts/garage.gd `_build_jobs_page` (:1137) |
| `Dealership` price table (scripts/dealership.gd, configs/dealership.json: `price_credits` per car, all `basis: AUTHORED`) | EXCHANGE-TERMS per car: what the dealer accepts (e.g. "a delivery obligation + one named part") | scripts/dealership.gd reader + configs/dealership.json entries |
| BUY rows keyed on the balance (garage.gd `_build_dealership` :607, `buy_car` :663: spend first, refund on store failure) | a TROC trade: the player offers what the terms accept — immediate where they hold it, an obligation where they do not; the ownership write (FirstCar.default_entry, WorldStore.set_active_car, the RentalGate end) survives unchanged | scripts/garage.gd |
| Paid fuel: `LITRE_PRICE_CREDITS = 2`, spend-before-fuel, all-or-nothing (scripts/refuel.gd:110, :187) | the station trades fuel for a delivery obligation (create-or-redeem at the pump); pay-before-fuel and all-or-nothing survive as trade-before-fuel | scripts/refuel.gd |
| The 10% social stations free fuel + tuna | PARKED, untouched by this redesign — it is the Cat Matrix rule and lands with the cat ecology (design-synthesis-draft.md §5) | explicitly not in this build order |

The voucher path for cars (fd_1001 via `FirstCar.take`, garage.gd DRIVE
page) is ALREADY TROC — a voucher is a thing, honoured at an exactly
positioned dealership — and is not touched by any slice.

---

## 4. What stays unused-but-harmless, and what is retired

Per the ruling: the ECON-1/ECON-3 landings (dd2c478, b21819b) stay on main
unused-but-harmless. Concretely:

- **Kept mechanically**: the credits ledger's file discipline (atomic
  writes, version refusal, tolerant reader, gating, test override) — it is
  the template the obligations ledger copies; the store wiring in
  MissionRunner; the dealership's strict config reader and its
  ownership-by-log idea (which becomes ownership-by-committed-trade);
  refuel's station flow (Buildings.by_element, RADIUS_M, the HUD line, the
  key); the job-episode framework end to end.
- **Retired from the game's surface** (code remains, unreached): the
  credits balance heading on the JOBS and CAR pages, the BUY-with-credits
  row, the paid-fuel spend, the `reward_credits` payment. Nothing is
  deleted until the driver's replacement slice for each lands, so every
  intermediate commit stays gate-green.

---

## 5. PROPOSED BUILD ORDER

Four self-contained, gate-testable slices, smallest first. Each is one
landing: tests/run_tests.sh x2 + parallel byte-identical, zero errors,
frozen files sha-identical before/after, one verbose commit. **Every slice
is PROPOSED — the driver rules.**

1. **The ObligationsLedger store + tests. No UI.** New
   scripts/obligations_ledger.gd (record shape §2.1, the credits ledger's
   machinery, no totals) + tests/obligations_test.gd in the credits test's
   style (FD_TELEMETRY=0, TMPDIR fixture, the real user:// file stamped and
   held). Nothing else changes; credits_test, refuel_test, menu_test,
   first_run_test untouched. The credits ledger itself stays live and
   untouched in this slice.
2. **Job rewards become poster-named obligations.** configs/jobs gain
   poster/poster_offers; `pay_last_result` writes the poster's obligation
   instead of calling `credits.earn`; the JOBS page shows needs/offers and
   the player's open obligations (held + owed) instead of the credits
   heading. Moves: the job-payout pins in tests/credits_test.gd (they move
   to obligations_test or are re-pointed), the JOBS-page shape in
   tests/menu_test.gd. No frozen file touched.
3. **Dealership exchange-terms barter buy.** configs/dealership.json
   entries become accepted-terms per car (basis strings keep the provenance
   style); the CAR page's BUY row becomes a barter trade against the terms
   (immediate where the boot holds it, an obligation created where it does
   not); the ownership write side of `buy_car` (garage.gd:663) survives
   as-is. PROPOSED: the credits BUY row is retired in the same slice, not
   left dormant — the ruling removes the model, and a dormant second price
   path is a second economy to keep green. (The driver may prefer dormancy;
   it is one flag either way.) Moves: the price pins in tests/credits_test.gd
   and the CAR-page shape in tests/menu_test.gd.
4. **Station fuel-for-obligation.** refuel.gd's wired-ledger seam becomes a
   wired-trade seam: with an obligations ledger on, holding U at a station
   creates or redeems a delivery obligation named by the station's terms;
   the grace seam (free fill where nothing is wired) survives. The 10%
   social rule stays parked. Moves: the paid-fuel pins in
   tests/refuel_test.gd.

Frozen files (scripts/car.gd, road_profile*.gd, ring_profile.gd,
surfaces.gd, physics_bubble.gd, visual_probe.gd, scenes/eifel_ring.tscn,
configs/elements/*.json, data/regions/eifel_ring/*, the frozen tests) are
touched by none of the slices. The cert lock (the 33 `metrics:` lines,
SLALOM 28.65 / SPIN_180 15.95 / SPIN_360 18.07 / STOP_BOX 8.72 /
REVERSE_180 7.72) is re-verified per landing as always. The driver's data
dir is never written; user://telemetry untouched (FD_TELEMETRY=0 pinned).

---

## 6. THE RULING THIS DOCUMENT ASKS FOR

The build order above: approve as ordered, or reorder (and rule slice 3's
retire-vs-dormant point). No implementation is dispatched until the ruling
lands.

---

## 7. QUESTIONS FOR THE DRIVER

1. **The build order** (§5, §6): approve the four slices as ordered, or
   reorder? And slice 3: retire the credits BUY row with the barter row, or
   leave the credits path dormant behind a flag?
2. **Partial settlement**: may an obligation be settled in parts (several
   redemption records, each naming what was given, until the counterparty
   calls it settled), or is every settlement one-shot — the whole
   obligation closed by one redemption?
3. **Transfer and held obligations**: can an obligation be assigned (X owes
   Y; Y offers the obligation itself to Z as payment — the service-for-
   voucher-for-a-car chain needs an answer)? And do obligations the player
   HOLDS as creditor count as part of the boot — things the player can
   offer in a trade — or are they only ever redeemed?
4. **AI counterparties in v1**: do AI traders honour obligations the player
   assigns or redeems against them in v1 (they accept whatever their
   exchange-terms list says), or is redemption player-side only until the
   traffic ecology gives them agency?
5. **What is a "favor" in v1**: just a free-text obligation kind with no
   game effect until a system consumes it, or does v1 need at least one
   concrete favour a counterparty asks for and one the player can ask for?
