# Car configs

A car is `scripts/car.gd` plus one file in `configs/cars/`. The same `car.gd` with a
different config file is a different car.

**The split.** A config holds a car's PRIMARY numbers and nothing else: what you would
read off a spec sheet or set on a test pad (mass, the torque curve, ratios, tyre and
spring figures, the drivers' feet). Everything DERIVED from them is computed in `car.gd`
and never written in a config: `BASE_MASS`, `CG_OFFSET`, the mass ledger's sums
(`LEDGER_KERB_MASS`, `LEDGER_REAR_FRACTION`, `UNSPRUNG_MASS`), the corner masses, spring and
damper rates, `BRAKE_DECEL`, the wheel contact points and lever arms, `STEERING_RATIO`,
`MAX_WHEEL_VISUAL_TRAVEL`. They are worked out again whenever a config has been read, so
they cannot go stale. What is not a car's number stays code as well: the model itself,
the stability assist, the low-speed blend, the geometry that has to match `car.tscn`
(`HALF_TRACK`, `WHEEL_RADIUS`), and the gearbox's shift programs, which the smoke test
holds within 50 rpm of what `ArcadeCar.derived_shift_points` makes of the loaded torque
curve.

**Loading.** `ArcadeCar._read_config` runs first in `_ready`: it reads the JSON, hands
it to `CarConfigValidation` (`configs/validation.gd`: a class of static functions, no
state, no node), and on any fault calls `push_error` with every fault listed and
asserts. None of a refused config is used: a bad config never silently becomes wrong
physics. The certified values stay in `car.gd` as the fallback defaults of its static
vars: what an OPTIONAL key left out falls back to, and what the class holds before a car
has loaded. A REQUIRED key left out is a fault, and so is any key the schema does not
know (a misspelt optional key would otherwise quietly drive on the default).

## Schema, `config_version` 1

All values are finite numbers unless said otherwise. Units are `car.gd`'s, where every
number is documented under its old constant's name. *(optional)* marks the keys with a
fallback default, given in brackets.

- `config_version`: 1. Any other is refused.
- `identity`: `name` (text), `car_id` (text: the car's entry in the odometer file).
- `mass`: `kerb_mass`, `rear_weight_fraction`, `cg_height`, `axle_distance`,
  `yaw_gyration_radius`.
- `mass_ledger`: `kerb_mass` as the table of the car's components it adds up from, an
  array of at least one row, each exactly `{"name", "mass_kg", "x_position_m",
  "sprung"}`: `name` text, not empty; `mass_kg` above zero; `x_position_m` where the
  component's own centre of mass sits along the car, measured from the middle of the
  wheelbase, POSITIVE TOWARD THE REAR (`car.gd`'s +Z, the sign of `CG_OFFSET`: the front
  axle is at `-axle_distance`, the rear at `+axle_distance`), and no further than an
  axle (`|x| <= mass.axle_distance`); `sprung` a JSON `true`/`false`, `false` for what
  rides on the road side of the springs (wheels and tyres, brakes, hubs). The fuel is
  not a row (it rides `total_mass()` as `fuel_mass`, burning), the tank is; the battery
  is; the driver is (`kerb_mass` is the car ready to drive, a driver on board). What
  the rows add up to has to be the `mass` section's own figures EXACTLY, to the bit:
  the masses summed in row order `== kerb_mass`, and the rear axle's share of the
  weight, `sum(mass_kg x (axle_distance + x_position_m)) / (2 x axle_distance x total)`,
  `== rear_weight_fraction`; and the unsprung rows have to weigh something and not
  everything. Why exact and not "close": `car.gd` draws the corner masses the
  suspension is set up for from the ledger's sums (`FRONT / REAR_CORNER_MASS`, 3W), the
  certified car's from the same numbers as before to the bit, and a table is authored
  to the bit (below). A fault says both numbers to every digit that reads back
  (`mass_ledger sums to 1299.5 kg, mass.kerb_mass is 1300.0`, `mass_ledger puts
  0.6155621301775148 of the weight on the rear axle, mass.rear_weight_fraction is 0.62`),
  and the validation and the running car sum the rows in the same order with the same
  plain f64 loop, so what passes the check is what the car derives. See "The mass
  ledger" below for the 986's rows and how a new car's table is authored.
- `engine`: `torque_curve` (two or more `[rpm, Nm]` anchors, rpm ascending, no torque
  under zero), `idle_rpm`, `redline_rpm` (not under the last anchor),
  `limiter_resume_rpm`, `engine_inertia`, `friction_torque`, `friction_torque_per_rpm`.
  *(optional)* `stall_rpm` [450], `cranking_torque` [150], `starter_free_rpm` [700],
  `starter_cycle_time` [0.8], `engine_catch_rpm` [500], `firings_per_revolution` [3].
- `idle` *(optional, all of it)*: `control_gain` [2.5], `control_max_throttle` [0.3].
- `fuel`: `tank_capacity_l`, `burn_efficiency`, `lhv`, `density`.
- `exhaust` *(optional, all of it)*: `flow_at_rest` [0.3], `flow_rate` [10].
- `battery` *(optional, all of it)*: `capacity_ah` [50], `starter_power` [1500],
  `key_on_load` [30], `running_load` [150], `alternator_power` [1500],
  `alternator_cut_in_rpm` [500], `alternator_rated_rpm` [2500], `charge_efficiency` [0.85],
  `taper_charge` [0.8], `deep_discharge_charge` [0.1], `deep_discharge_wear` [0.03],
  `flat_wear_rate` [2.78e-6]. The rpm are the engine's (the belt ratio is inside them),
  the loads and powers watts, the rate per second; the 12 V that turn the amp hours
  into joules are the system's, not a car's. The battery's ~20 kg are inside
  `kerb_mass`, as they are in a kerb weight: the `mass_ledger`'s "battery" row.
- `thermal` *(optional, all of it)*: `ambient_c` [15], `operating_c` [90],
  `thermostat_c` [80], `warm_c` [70], `fan_on_c` [97], `fan_off_c` [92], `max_c` [130],
  `coolant_heat_capacity` [100000], `heat_share` [0.28], `radiator_cooling` [1.5],
  `fan_airflow` [8], `overheat_fade_start_c` [110], `overheat_fade_rate` [0.02],
  `rich_factor` [1.3], `idle_wobble_rpm` [50], `idle_wobble_hz` [0.6]. Degrees Celsius,
  the capacity J/K, the cooling W per K per (m/s)^2 of airflow, the fan's airflow the
  road speed it stands in for [m/s], the fade rate per degree over its start. A car
  starts at `operating_c` whatever is here: the warm-up is what a cold start (set by
  hand) climbs through. The tyres and the brakes, an axle each: `tyre_operating_c` [75],
  `tyre_window_low_c` [45], `tyre_window_high_c` [110], `tyre_max_c` [165],
  `tyre_heat_capacity` [10000], `tyre_slip_heat_share` [0.3], `tyre_cooling_still` [6],
  `tyre_cooling_airflow` [1.4], `tyre_cold_grip` [0.85], `tyre_fade_rate` [0.005],
  `brake_fade_start_c` [250], `brake_fade_rate` [0.002], `brake_fade_floor` [0.5],
  `brake_red_hot_c` [400], `brake_max_c` [600], `brake_heat_capacity` [6000],
  `brake_cooling_still` [4], `brake_cooling_airflow` [1]. Degrees Celsius, the
  capacities J/K an axle, the cooling W per K standing and W per K per m/s of road
  speed on top, the cold grip the share of the grip at the air's temperature, the
  fade rates per degree over the window's upper edge and the brakes' fade line, the
  slip heat share the part of the slip work that warms the tyre. A car starts with its
  tyres at `tyre_operating_c` (inside the window, the grip exactly its own) and its
  brakes at `ambient_c` (the fade exactly none) whatever is here.
- `gearbox`: `ratios` (neutral's 0 first, then the forward gears, each above zero),
  `final_drive`, `reverse_ratio`, `drivetrain_efficiency`, `clutch_torque_max`,
  `clutch_engage_time`, `clutch_shift_engage_time`.
- `launch`: `rpm`. *(optional)* `clutch_share` [0.5], `bite_band` [50].
- `creep` *(optional, all of it)*: `clutch_engagement` [0.02], `free_speed` [0.9],
  `engage_speed` [0.05], `dwell` [0.4], `max_speed` [0.8].
- `wear` *(optional, all of it)*: `clutch_rate` [1e-8], `clutch_floor` [0.7],
  `brake_rate` [1e-9], `brake_abuse` [3], `brake_floor` [0.75], `tyre_rate` [4e-10],
  `tyre_abuse` [3], `tyre_floor` [0.85], `engine_rate` [1e-8], `engine_abuse` [10],
  `engine_floor` [0.85]. A rate is wear (a share of the component's life, 0..1) per
  joule of the clutch's slip energy, the disc's work or the tyre's heat, and per
  radian the engine turns under load; never negative (wear never comes back). An
  abuse multiplier is how many times faster the component wears per joule or radian
  while it is over its line (the disc over the brake fade line, the tyre over its
  window, the coolant over the overheat line); 1 or more. A floor is what a worn-out
  component keeps of itself - the clutch of its capacity, a brake of its torque, a
  tyre of its grip, the engine of its torque curve; over 0 (nothing here breaks) and
  no more than 1 (a floor of 1 is a component that wears without effect). See "The
  wear table" below for the 986's numbers and their reasoning.
- `brakes`: `bias_front`, `decel_g`. *(optional)* `coast_decel` [0.15].
- `tyres`: `mu`, `front_grip`, `rear_grip`, `peak_slip_ratio`, `abs_slip_ratio`,
  `drive_slip_ratio`, `front_peak_slip_angle`, `rear_peak_slip_angle`, `slide_grip`,
  `rear_slide_grip`, `slide_onset`, `axle_inertia`, `min_combined_grip`,
  `load_grip_exponent`.
- `suspension`: `front_ride_frequency`, `rear_ride_frequency`, `ride_damping_ratio`,
  `front_anti_roll_rate`, `rear_anti_roll_rate`, `travel`, `ground_clearance`.
  *(optional)* `bump_stop_rate` [3], `bump_stop_progression` [0.02].
- `steering`: `max_steer_lock`, `wheel_lock_deg`, `hand_speed`.
- `aero`: `drag_coeff`, `frontal_area`, `downforce_coeff`, `balance_front`.
  *(optional)* `air_density` [1.225].
- `handbrake`: `release_torque`, `rear_lock_recovery_rate`.
- `driver_profiles`: name -> `throttle_attack`, `throttle_release`, `brake_attack`,
  `brake_release`, `steering_hand_speed`, all five, finite and not negative.
  `test_driver` has to be there: it is who drives unless somebody else is seated, and
  what a partial profile is filled in from.
- `mode_drivers`: `sport`, `comfort`, `eco` -> the name of a profile above. `car.gd`
  puts the three names onto its `GearboxMode` enum; enum values are not car data.

## The mass ledger

The 986's table (3W, from the component inventory of `docs/car-component-audit.md`,
its section 1, which cites typical-for-986 figures throughout). JSON has no comments:
this is where the rows' provenance is written. Masses in kg, `x` in m from the middle
of the wheelbase, positive toward the rear. Every mass is an ESTIMATE, the audit's
"typical" figure or a split of one, except the last row, the catch-all, which is the
remainder to `kerb_mass`; every position is an estimate of where the group's centre
of mass sits on `car.gd`'s 2.6 m wheelbase, except the last row's, which is
CALIBRATED. The audit gives no positions; where the audit's "location" column and the
986 disagree (it puts the starter and the fuel tank at the wrong end, the spare in a
rear trunk the car does not have), the row follows the car: the starter bolts to the
bellhousing, the tank sits under the front trunk floor, the spare in the front trunk.

| Row | kg | x | Sprung | Notes |
|---|---|---|---|---|
| engine block and rotating assembly | 150 | +0.7 | yes | audit's 150; mid-rear, ahead of the rear axle |
| engine peripherals: alternator, AC compressor, water pump, pulleys | 20 | +0.75 | yes | audit's 25 for the peripherals less the starter, which has its own row (its table counts the starter and alternator twice; not here) |
| starter motor | 5 | +1.0 | yes | audit's 5; on the bellhousing |
| gearbox and clutch | 39 | +1.2 | yes | audit's 35 + 4; the transaxle behind the engine |
| driveshafts and differential | 20 | +1.3 | yes | audit's 20; on the rear axle line |
| exhaust: manifolds, catalysts, silencer | 25 | +1.2 | yes | audit's 25; the silencer hangs behind the axle, the manifolds ahead of it |
| battery | 18 | -1.3 | yes | audit's 18; front trunk (see the `battery` section) |
| coolant circuit: radiators, fans, hoses, coolant | 15 | -1.3 | yes | audit's 15; the radiators stand in the nose, clamped to the axle by the wheelbase rule |
| HVAC: condenser, evaporator, blower, ducts | 15 | -1.0 | yes | audit's 15; front bulkhead |
| steering column, rack and assist | 12 | -0.9 | yes | audit's 12; the rack ahead, the column running back |
| ABS modulator and brake lines | 6 | -0.9 | yes | audit's 6; front trunk; sprung, so not in the brakes' rows |
| fuel tank, pump, lines and filter, dry | 14 | -0.8 | yes | audit's 62 full less 64 l x 0.75 kg/l of fuel (the `fuel` section's; the fuel rides `total_mass()`, not the ledger) |
| spare wheel and tools | 20 | -1.1 | yes | audit's 20; front trunk |
| electrics: harness, ECU, lighting | 12 | 0.0 | yes | audit's 8 + 4; all over |
| radio and sound deadening | 10 | -0.2 | yes | audit's 10 |
| glass: windscreen and side windows | 30 | -0.3 | yes | audit's 30; the screen's base ahead of the middle |
| seats | 24 | +0.2 | yes | audit's 24; the cabin sits just behind the middle of a mid-engined car |
| driver on board | 75 | +0.2 | yes | not in the audit; `kerb_mass` is the car ready to drive WITH a driver (`car.gd`'s `KERB_MASS`: ~1250 kg without one), so the ledger has to carry one; 75 kg the standard occupant |
| front suspension: arms, springs, dampers, anti-roll bar | 25 | -1.3 | yes | audit's 40 for the front less the hubs' 15, next |
| rear suspension: arms, springs, dampers, anti-roll bar | 25 | +1.3 | yes | audit's 40 for the rear less the hubs' 15 |
| front hubs, uprights and bearings | 15 | -1.3 | no | the unsprung part of the audit's front suspension, an estimate |
| rear hubs, uprights and bearings | 15 | +1.3 | no | as the front |
| front brakes: discs, calipers, pads | 17 | -1.3 | no | audit's 32 for four corners, the bigger front discs' share |
| rear brakes: discs, calipers, pads | 15 | +1.3 | no | the rest of the audit's 32 |
| front wheels and tyres | 30 | -1.3 | no | half the audit's 36 + 24 |
| rear wheels and tyres | 30 | +1.3 | no | the other half (the rears are wider; the difference is inside the estimate) |
| body-in-white, panels, interior and everything else | 618 | +0.451294498381877 | yes | REMAINDER to `kerb_mass` 1300 (the audit's 180 for panels and seats is a part of it: the shell, doors, lids, bumpers, roof and its mechanism, dash, trim and carpets are all in here, the least-known figure of the table). Its x is CALIBRATED: the one position solved for so that the table's split is the certified `rear_weight_fraction` 0.62 to the bit, and a 15-decimal number because nothing shorter lands on those bits (the split moves 0.18 per metre of this row) |

Sums: 1300 kg, 0.62 on the rear axle (247 / 403 kg a corner, the 3B figures), 122 kg
unsprung. The unsprung sum is data and validation only (`ArcadeCar.UNSPRUNG_MASS`):
the suspension runs the whole kerb per axle, by design ("no unsprung mass" in
`car.gd`'s Suspension section), and nothing reads it yet. Honest limits: the row
masses are the audit's typical figures, none weighed; the certified 62 % rear is the
sim's tuned split, and the calibrated catch-all position is what reproduces it on
these estimates, not a measurement of the shell's centre of mass.

**Authoring a new car's table.** Pick the rows and their estimates, masses and
positions, from the car's own figures. Make one row, the least known (the shell and
interior), the remainder that brings the sum to `kerb_mass` exactly: with masses in
whole kg or halves the f64 sum is exact. Then solve that same row's `x` for
`rear_weight_fraction`, `x = (fraction x 2 x axle_distance x kerb_mass - the other
rows' sum of mass x (axle_distance + x)) / its mass - axle_distance`, put the row
LAST so the moment sum completes on it, and run `tests/config_test.gd`: the exact
check will most likely fail on the last bit, and its fault gives both numbers to every
digit. Nudge the last decimal of that `x` (a step of 1e-15 or so) until the fault goes
away: with a 600 kg row a few adjacent doubles land on the certified bits, and only
those. That is calibration, not a fudge: the one figure solved for is the one the
estimates know least.

## The wear table

The 986's numbers (3L, `car.gd`'s "Wear and aging"). JSON has no comments: this is
where each rate's provenance is written. Every one is a CHOICE, not a measurement: the
rates are set gentle on purpose (the user's car is a test instrument, and a session on
the pad has to wear it measurably in the ledger, not visibly at the wheel), the per-event
costs beside them are MEASURED by `tests/wear_test.gd` on the certified car, and the
lives they add up to are held against what real parts last.

| Key | Value | Unit | Reasoning |
|---|---|---|---|
| `clutch_rate` | 1e-8 | 1/J | 1 % per MJ of slip energy. 8 s flat out from rest (the launch and two upshifts) slips ~68 kJ: ~15 of them per percent, ~1500 to worn out. A donut under the automatic's hunting slips ~25 kW: that is abuse, and costs ~1 % in 40 s. |
| `clutch_floor` | 0.7 | share | A worn-out clutch still passes 350 Nm, over what the engine makes; what goes is the margin - it slips longer on a launch and through a shift (6 ticks more over 8 s, measured). |
| `brake_rate` | 1e-9 | 1/J | 1 % per 10 MJ of disc work. A full stop from 90 km/h is ~390 kJ, ~174 kJ on the front discs and ~216 kJ on the rears (the ABS holds the fronts at the tyres' limit; the driven axle's discs slow the engine too): ~45 such stops per percent of the rears, ~5000 to worn out - a set of racing pads' life on a circuit, far longer on the road. |
| `brake_abuse` | 3 | x | A disc over the fade line wears three times as fast per joule: a string of hard stops without letting them cool. |
| `brake_floor` | 0.75 | share | Pads down to the backing plate still stop the car: 15 % further from 90 km/h (measured), on top of whatever the fade takes. |
| `tyre_rate` | 4e-10 | 1/J | 1 % per 25 MJ of tyre heat. Rolling at 72 km/h puts ~200 kJ/km into the four (`COAST_DECEL`'s work), a hard lap's sliding as much again: ~60 km of hard driving or ~130 km of cruising per percent; a 25 s donut puts ~480 kJ into the rears, ~35 of them per percent; ~13 000 km of cruising to worn out - a sports tyre's life, short. |
| `tyre_abuse` | 3 | x | A tyre over its window wears three times as fast per joule: greasy rubber tears. The donut's last seconds pay it. |
| `tyre_floor` | 0.85 | share | A bald tyre grips in the dry; what it has lost is the margin: 0.74 g worn out in the corner new tyres hold 0.88 g in (measured). |
| `engine_rate` | 1e-8 | 1/rad | 1 % per Mrad turned under full load. 8 s flat out from rest costs ~33 ppm (the load weight counts the launch's and the shifts' revolutions for less); flat out at 6000 rpm ~27 min or ~50 km per percent; ~45 h or ~5000 km flat out to worn out, a race engine's rebuild interval; a road engine's mixed life is many times longer, an idle or a cruise counting for a small share of a turn. |
| `engine_abuse` | 10 | x | Over the overheat line every revolution counts in full, loaded or not, and ten times over: an overheated engine driven on costs 1 % in ~3 min flat out, ~18 min idling. Neglect. |
| `engine_floor` | 0.85 | share | Rings and bores gone, compression down; it runs: 97 km/h after the same 8 s flat out where the new engine reaches 106 (measured). |

Not a car's number, and not in the table: `WEAR_EFFECT_STEP` (0.01), the resolution
the multipliers read the wear at - exactly 1 under a hundredth, one step per percent
from there - which is what keeps a certified run, wearing well under a hundredth of
anything, the physics it always was; and `WEAR_LIMIT` (1), where every share stops.

## Adding a car

Copy `configs/cars/boxster_986.json`, change the numbers, give it its own `car_id`.
The validation is generic and `tests/config_test.gd` checks every file in
`configs/cars/` in seconds, as the first test step of `tests/run_tests.sh`. Point
`ArcadeCar.CONFIG_PATH` at the file. If the engine changed, run
`ArcadeCar.derived_shift_points` on it and bring the shift constants in `car.gd` to its
figures: the smoke test fails until they agree.
