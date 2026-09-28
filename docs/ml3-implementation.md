# ML-3: Junior deliveries and the Test Driver reward

FD-05/06/07 remain **Junior** missions, following the source cards. The playable
chain is FD-01 → FD-02 → FD-03 → FD-04 → FD-05 → FD-06 → FD-07 → FD-12.
FD-08–11 remain outside this increment. No Test Driver mission is invented.

## Reward configuration

`configs/cars/fd_1073.json` uses the 1973 Carrera RS 2.7 **Touring** baseline:
rear-mounted, air-cooled, mechanically injected 2,687 cc flat-six; 210 PS
(154.45 kW, approximately 207 bhp) at 6,300 rpm; 255 Nm at 5,100 rpm;
1,075 kg kerb mass; five-speed 915/08 manual. The customisation is the campaign
reward identity, with no unsupported power increase.

[Porsche's historical account](https://newsroom.porsche.com/en/2022/history/porsche-50-years-911-carrera-rs-2-7-germanys-fastest-sports-car-28486.html)
gives the power/torque anchors and the Sport's 960 kg mass, 115 kg below Touring
(hence 1,075 kg). [Porsche's museum specification](https://newsroom.porsche.com/en/press-kits/Porsche-Museum/Porsche-911-Carrera-RS-2.7.html)
identifies the model year and displacement.
[The transmission rebuilder's 915/08 table](https://www.cogscogs.com/Gear-Ratio-Charts-and-Graphs_ep_10.html)
gives tooth counts: 35/11, 33/18, 29/23, 25/27, 21/29, with 31/7 final drive.
The JSON uses those fractions, approximately 3.182/1.833/1.261/0.926/0.724
and 4.429. The torque curve's 6,300 rpm anchor represents 210 PS.

These are primary simulation parameters, not a new certified driving model.
Other torque anchors, reverse ratio, 85 L tank, 2.268 m wheelbase, 60% rear
weight, component masses, suspension, grip and aerodynamic values are explicit
modelling choices. The ledger totals 1,075 kg exactly; its computed rear fraction
is preserved to the bit. The engine's rear overhang is projected onto the rear
axle because validation restricts ledger positions to the wheelbase. The generic
thermal/battery/wear/control parameters inherit the existing schema defaults;
its coolant/radiator fields are only a thermal proxy for this air-cooled car.
Displacement and cooling type have no dedicated schema fields. No schema changes
or frozen physics edits are made.

The committed `test_driver` reward entitlement **is ownership** of `fd_1073`.
It is granted atomically at FD-12 and works for existing campaign saves without
a migration write. Garage MISSIONS and CAR offer TAKE immediately, without a
purchase or voucher. TAKE initializes an absent cars.json condition entry using
the car's own tank capacity and the existing FirstCar defaults, preserves an
existing entry, selects `world.active_car`, and ends a rental.

**Live car swapping remains deferred**, exactly as documented by FirstCar:
`ArcadeCar.CONFIG_PATH` and static tuning are frozen. TAKE persists selection;
it does not change the pad Boxster's physics. The garage says so. The RS config
validates and is selectable, but an RS physics driving claim would be false.

## Courses and medal measurements

| Mission | Scripted pass | Gold | Silver | Bronze | Source limit |
|---|---:|---:|---:|---:|---:|
| FD-05 Car Delivery 1 | 28.583333 s | 31 | 36 | 43 | 110 |
| FD-06 Extended Slalom | 29.133333 s | 31 | 37 | 44 | 50 |
| FD-07 Frank's Challenge | 27.816667 s | 30 | 35 | 42 | 58 |

Measured with Godot 4.7.2 at fixed 60 Hz, on freshly loaded pad Boxsters, using
each shipped `input_script` through MissionRunner/HandlingTests. Bands are
`ceil(measured seconds × factor)`, factors 1.05/1.25/1.50. Each JSON records this
provenance. The source limits are unchanged, and all bands are strictly ordered
below them. FD-06/07 reuse ML-2's recorded fourteen-cone steering trace; FD-06
extends the finish by 18 m, FD-07 tightens the weaving gates and finish radius.

FD-05 uses the existing `delivery_pickup` and `delivery_return` steps as dispatch
and dock handover crossings, with two route gates and a separate timed finish.
This is an A-to-B delivery across the pad: `return` denotes handover at the
destination, not a trip back to dispatch. There is no stop, cargo, traffic,
police, or damage simulation. Ordered crossings and the timer determine the
verdict. FD-06/07 use the existing swept cone-contact failure rule as the cone
penalty. No mission-schema or runner extension is needed.

## Validation and landing message

The existing ladder step covers config validation, fresh ownership denial,
FD-12 grant/reload/garage TAKE, condition persistence, unlock failures, medal
boundaries, and actual passing and failing scripted drives for each new mission.
`tests/run_tests.sh` remains unchanged with 34 markers.

Observed final checks: all three car configs pass; mission ladder **321 checks
passed**, including all eight production scripted passes and the three new
scripted failures; no script/engine errors in that final selected-step log.
`git diff --check` passes. Evidence is in `build/ml3-checks/results.log` (ignored
local artifact). Only the config and ladder steps were executed using a local
copy of the runner's step/error-check harness; the full 34-marker gate was not
run because existing suites hard-code writes outside the repo. Ladder fixtures
and logs are under `build/`. Godot import initially hit sandbox-denied editor
settings writes, and startup hit the known macOS system-certificate access
error. A temporary, now-removed `override.cfg` selected `/etc/ssl/cert.pem` for
the successful checks; telemetry was disabled and the data path repo-local.
No driver data was written, and the runner/frozen files were not edited.

Suggested landing commit body (no commit is made by this task):

> Add FD-05 delivery and FD-06/07 pad slaloms, with measured medal bands and
> FD-04 → FD-05 → FD-06 → FD-07 → FD-12 progression. Grant the selectable RS
> at promotion. RS baseline: 1973 Touring, rear air-cooled 2,687 cc flat-six,
> 210 PS (~207 bhp) at 6,300 rpm, 255 Nm at 5,100 rpm, 1,075 kg, five-speed
> 915/08 with 31/7 final drive. Live vehicle swap remains deferred by the
> frozen car implementation.
