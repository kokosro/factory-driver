# Car configs

A car is `scripts/car.gd` plus one file in `configs/cars/`. The same `car.gd` with a
different config file is a different car.

**The split.** A config holds a car's PRIMARY numbers and nothing else: what you would
read off a spec sheet or set on a test pad (mass, the torque curve, ratios, tyre and
spring figures, the drivers' feet). Everything DERIVED from them is computed in `car.gd`
and never written in a config: `BASE_MASS`, `CG_OFFSET`, the corner masses, spring and
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
  `kerb_mass`, as they are in a kerb weight.
- `thermal` *(optional, all of it)*: `ambient_c` [15], `operating_c` [90],
  `thermostat_c` [80], `warm_c` [70], `fan_on_c` [97], `fan_off_c` [92], `max_c` [130],
  `coolant_heat_capacity` [100000], `heat_share` [0.28], `radiator_cooling` [1.5],
  `fan_airflow` [8], `overheat_fade_start_c` [110], `overheat_fade_rate` [0.02],
  `rich_factor` [1.3], `idle_wobble_rpm` [50], `idle_wobble_hz` [0.6]. Degrees Celsius,
  the capacity J/K, the cooling W per K per (m/s)^2 of airflow, the fan's airflow the
  road speed it stands in for [m/s], the fade rate per degree over its start. A car
  starts at `operating_c` whatever is here: the warm-up is what a cold start (set by
  hand) climbs through.
- `gearbox`: `ratios` (neutral's 0 first, then the forward gears, each above zero),
  `final_drive`, `reverse_ratio`, `drivetrain_efficiency`, `clutch_torque_max`,
  `clutch_engage_time`, `clutch_shift_engage_time`.
- `launch`: `rpm`. *(optional)* `clutch_share` [0.5], `bite_band` [50].
- `creep` *(optional, all of it)*: `clutch_engagement` [0.02], `free_speed` [0.9],
  `engage_speed` [0.05], `dwell` [0.4], `max_speed` [0.8].
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

## Adding a car

Copy `configs/cars/boxster_986.json`, change the numbers, give it its own `car_id`.
The validation is generic and `tests/config_test.gd` checks every file in
`configs/cars/` in seconds, as the first test step of `tests/run_tests.sh`. Point
`ArcadeCar.CONFIG_PATH` at the file. If the engine changed, run
`ArcadeCar.derived_shift_points` on it and bring the shift constants in `car.gd` to its
figures: the smoke test fails until they agree.
