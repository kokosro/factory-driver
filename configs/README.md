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
- `wear` *(optional, all of it)*: `clutch_life_km` [175000], `clutch_slip_m_per_kj`
  [5], `clutch_floor` [0.7], `brake_life_km` [50000], `brake_work_m_per_kj` [1],
  `brake_abuse` [3], `brake_floor` [0.75], `tyre_life_km_front` [25500],
  `tyre_life_km_rear` [17000], `tyre_slip_m_per_kj` [0.5], `tyre_abuse` [3],
  `tyre_floor` [0.85], `engine_life_km` [140000], `engine_flat_out` [6],
  `engine_abuse` [10], `engine_floor` [0.85]. A rated life is the kilometres of street
  driving that use the whole of a component up (a share of 1): every metre the odometer
  counts is that share of it, and a gentle cruise costs exactly that; over 0 (the
  metres are divided by it). A cost per kilojoule is what the driving adds on top, in
  metres of the component's life per kJ of the clutch's slip energy, the disc's work or
  the tyre's slip work; never negative (wear never comes back). An abuse multiplier is
  how many times over that cost counts while the component is over its line (the disc
  over the brake fade line, the tyre over its window); the engine's `engine_flat_out`
  is how many times a cruise's wear per metre the engine takes at full load (the load
  squared between), and `engine_abuse` how many times over its metres count with the
  coolant over the overheat line, every revolution at full load up there; each 1 or
  more. A floor is what a worn-out component keeps of itself - the clutch of its
  capacity, a brake of its torque, a tyre of its grip, the engine of its torque curve;
  over 0 (nothing here breaks) and no more than 1 (a floor of 1 is a component that
  wears without effect). See "The wear table" below for the 986's numbers, their
  sources and which are estimates.
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

The 986's numbers (3L, rebased on the kilometres in 3AB; `car.gd`'s "Wear and aging").
JSON has no comments: this is where each number's provenance is written. The user's 15:24
verdict (2026-09-22): "in a real car i get more hill starts, 15 clutch launches / 46 hard
stops is a very fragile car ... all wear could be researched online, how many kilometers
would the engine run on average, how much that type of tire, that type of clutch, that
type of brakes actually take. I think the measurement is more in kilometers driven and
how they were driven rather than how many times i can start the car from a hill." So
each component has a RATED LIFE in kilometres from a research pass on what the real
parts take (SOURCED where a range was found, the midpoint taken; an ESTIMATE where
not, labelled so, tunable), every metre the odometer counts is that share of it, and
what the driving costs on top is a labelled estimate of an event's equivalence in
metres of life, normalised on the certified car's own measured numbers
(`tests/wear_test.gd` states what each event comes to).

| Key | Value | Unit | Reasoning |
|---|---|---|---|
| `clutch_life_km` | 175000 | km | SOURCED: a street clutch lasts 100 000-250 000 km (986/Boxster owner corroboration); the midpoint. 1 % per 1750 km of gentle driving. |
| `clutch_slip_m_per_kj` | 5 | m/kJ | ESTIMATE (physics, range 100-500 m): a full-throttle launch is ~100-500 m of normal clutch wear, the midpoint 300 m; the first engagement of a flat-out launch slips 58.4 kJ (measured): 300 / 58.4 = 5.1, rounded to 5. An 8 s flat-out run (the launch and two upshifts, 68 kJ) is 341 m of life on top of its 133 m of road: ~3700 of them per percent (was 15). Riding the clutch is the joules themselves: tens of kilowatts, ~100 m of life a second; a donut under the automatic's hunting slips ~600 kJ, ~3 km of it. |
| `clutch_floor` | 0.7 | share | A worn-out clutch still passes 350 Nm, over what the engine makes; what goes is the margin - it slips longer on a launch and through a shift (6 ticks more over 8 s, measured). |
| `brake_life_km` | 50000 | km | SOURCED: street pads last ~30 000-70 000 km, Porsche-class cars trending high; the midpoint, either axle. 1 % per 500 km of gentle driving. |
| `brake_work_m_per_kj` | 1 | m/kJ | ESTIMATE (physics, from KE = ½mv², range 100-300 m): a full ABS stop from ~90 km/h is ~100-300 m of gentle-braking wear, the midpoint 200 m; the stop is the car's kinetic energy through the discs, ½ x 1300 kg x (25 m/s)² = 406 kJ over two axles (measured 174 kJ on the fronts, 216 kJ on the rears: the ABS holds the fronts at the tyres' limit, the driven axle's discs slow the engine too), ~200 kJ an axle: 200 m / 200 kJ, a metre per kilojoule. The stop is 216 m of the rears' life on top of its 36 m: ~2000 of them per percent of the rears (was 46). |
| `brake_abuse` | 3 | x | ESTIMATE (the old model's, kept): a disc over the fade line wears three times as fast per joule - a string of hard stops without letting them cool. |
| `brake_floor` | 0.75 | share | Pads down to the backing plate still stop the car: 15 % further from 90 km/h (measured), on top of whatever the fade takes. |
| `tyre_life_km_front` | 25500 | km | ESTIMATE (no number sourced): the fronts of this mid-engined, rear-driven car carry less and drive nothing; taken as 1.5 x the rears'. |
| `tyre_life_km_rear` | 17000 | km | SOURCED (forum): a performance summer rear lasts 10 000-24 000 km on the street; the midpoint. 1 % per 170 km of gentle driving. |
| `tyre_slip_m_per_kj` | 0.5 | m/kJ | ESTIMATE (range 0.5-2 km): a donut is ~0.5-2 km of a rear's life, the midpoint 1.25 km; the wear test's 25 s donut is 1574 kJ of slip work against the rears' contact patches (measured), 384 kJ of it with the rubber over its window and so `tyre_abuse` times over: 1250 / (1574 + 2 x 384) = 0.53, rounded to 0.5 - 1171 m of life on top of the donut's 89 m of way, ~135 of them per percent (was 35). Rubber goes by the frictional energy, which is why the slip work and not the tyre's heat: hard cornering is slip work too. A straight cruise's drive slip is a per-mille of it on the rears, nothing on the fronts. |
| `tyre_abuse` | 3 | x | ESTIMATE (the old model's, kept): a tyre over its window wears three times as fast per joule - greasy rubber tears. The donut's last seconds pay it. |
| `tyre_floor` | 0.85 | share | A bald tyre grips in the dry; what it has lost is the margin: 0.74 g worn out in the corner new tyres hold 0.88 g in (measured). |
| `engine_life_km` | 140000 | km | SOURCED (forum): ~130 000-150 000+ km before major work for an engine of this era; the midpoint. (The IMS bearing is a separate failure mode of the 986's engine, not wear, and not modelled.) The engine's metres are its own: its revolutions in top-gear metres (`TOP_GEAR_M_PER_RAD`, the wheel's radius over the top ratio times the final drive, 0.090 m a radian - derived, not a key): in top gear, locked, exactly the road's; in 2nd at the same speed twice them; idling, 31 km/h of them (an hour's idle ~31 km of the engine's life; the fleet rule of thumb has 25-30 miles). 1 % per 1400 km of gentle driving in top gear. |
| `engine_flat_out` | 6 | x | ESTIMATE (range 2-10x, unknown precisely): sustained full throttle is ~2-10 x a gentle cruise's wear per km; the midpoint. The style is 1 + (this - 1) x the load share squared (the load the clutch takes off the crank over the curve's peak): the square is an estimate of the shape too - wear climbs steeply towards full load (combustion pressure and oil-film temperature both rise with it) and a light cruise, a tenth of the peak on the crank (0.15 in 5th at 72 km/h, measured), is 1.11 by it, which is what the rated life means; a straight line would make that cruise 1.7x. 8 s flat out from rest is 1627 m of the engine's life for 133 m of road, a style of 12 (the low gears' revolutions and the load together). |
| `engine_abuse` | 10 | x | ESTIMATE (the old model's, kept): over the overheat line every revolution counts at full load (x6) and ten times over - an overheated engine driven on costs 1 % in ~7 min flat out, ~50 min idling. Neglect. |
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
