# Factory Driver — Car Simulation Schematic
# Version 2026-09-20 20:50 (after 3B) — origin/main b64b6a8
# Ground truth: scripts/car.gd (~1900 lines), road_profile.gd, test_pad.gd, chase_camera.gd
# Suite: 501 checks, triple byte-identical, all five certifications PASS.

## 1. THE BIG PICTURE

```
   [driver: keyboard / (future) profiles & pedals / (future) AI]
        │
        ▼
┌──────────────────────────── DRIVETRAIN (3A) ────────────────────────────┐
│  engine (ω state, inertia 0.25 kg·m²) ── torque curve ── friction curve │
│     │ idle controller ──── fuel-cut limiter (7200)                      │
│     ▼                                                                   │
│  CLUTCH (engagement 0..1, slip torque ≤500 Nm, lock ⇔ one shaft,        │
│     │   open for shifts / standstill / handbrake)                       │
│     ▼                                                                   │
│  GEARBOX (5 ratios + R; auto thresholds; Q/E/M manual;                  │
│     │   reflected inertia ratio²·eff when locked)                       │
│     ▼                                                                   │
│  AXLE WHEEL STATES (front_ω, rear_ω; AXLE_INERTIA 2.4;                  │
│         slip ratio = (ω·r − v)/max(|v|,ε) — no more relaxation          │
└────────┬────────────────────────────────────────────────────────────────┘
         │ T_drive (RWD default; DRIVEN_WHEELS RWD/FWD/AWD; AWD ≈ split)
         ▼
┌──────────────────────────── TYRES (per axle, bicycle model) ────────────┐
│  slip angle → lateral curve → force; friction circle couples with the   │
│  longitudinal force; load-dependent grip; slide curve: onset widening   │
│  + rear slide grip 0.97 (2I/3B rubber pass); REAR_TYRE_SLIDE_GRIP only  │
│  on rolling rears, sideways part of slip only                           │
└────────┬────────────────────────────────────────────────────────────────┘
         │ forces at contact patches
         ▼
┌──────────────────────────── CHASSIS (CharacterBody3D shell) ────────────┐
│  forward/lateral velocities + yaw: integrated from force sums & moments │
│  (yaw via inertia · moment; NO kinematic yaw, no steering-by-decree)    │
│  stability ASSIST: bounded yaw moment, slide-sensitive, spin-committed  │
│  low-speed blend (<4 m/s: rolling-geometry parking model)               │
│  gravity + air drag + rolling drag                                      │
└────────┬────────────────────────────────────────────────────────────────┘
         │ wheel loads = SPRING FORCES
         ▼
┌──────────────────────────── SUSPENSION (3B) ────────────────────────────┐
│  4 corners: spring k (1.5/1.7 Hz) + damper + anti-roll bar share +      │
│  progressive bump stops; heave = body's own y (gravity real); pitch/roll│
│  states; weight transfer EMERGES (formula deleted); corner-weight trim  │
│  travel ±7 cm, visible                                                  │
└────────┬────────────────────────────────────────────────────────────────┘
         │ samples the road
         ▼
┌──────────────────────────── ROAD (2G, road_profile.gd) ─────────────────┐
│  seeded height field: micro-bumps (felt, ~neutral) + masked elevation   │
│  swell (level at certifications, ±1 m swells on open course); ground    │
│  mesh rides it; collision plane = bottom-out backstop                   │
└──────────────────────────────────────────────────────────────────────────┘
```

## 2. COMPONENT INVENTORY

| Component | State | Key facts |
|---|---|---|
| Engine | **BUILT, verified** | ω state, torque curve 160→245→180 Nm, friction 12+0.007/rpm, idle controller, fuel-cut limiter with bounce |
| Clutch | **BUILT, verified** | slip torque 500 Nm, feathered launch, lock = one shaft w/ reflected inertia, opens for shifts/stop |
| Gearbox | **BUILT, verified** | 5 speeds + R, auto (up 6800/down 2800 + anti-hunt), manual Q/E/M, rev-matching blip on downshifts |
| Wheel states | **BUILT, verified** | per-axle ω, backward-Euler tyre solve; slip ratio from ω vs road; visuals = true ω |
| Tyres | **BUILT, verified** | slip-angle curve, friction circle, load-scaled grip, progressive slide curve (3B), handbrake lock carve-out |
| Chassis core | **BUILT, verified** | force-based 2E model; assist bounded & wheel-blind; low-speed blend |
| Suspension | **BUILT, verified** | 4 corners w/ anti-roll bars, bump stops; heave/pitch/roll real; weight transfer emergent; validated ≤20 N vs statics |
| Road profile | **BUILT, verified** | seeded, mean-neutral bumps + masked swell; ground mesh + collision backstop |
| Steering input | **BUILT, verified** | 900° wheel, 16.4:1 rack, 1300°/s hand speed |
| Stability assist | **BUILT, verified** | bounded yaw moment, slide-sensitive fade; user may still find it intrusive (pending feel verdict) |
| ABS / traction control | **ON, not toggleable** | ABS in the brake-slip model; TC implicit in launch easing — 3G makes both switchable |
| Fuel | **NOT BUILT** | 3G: tank, consumption, gauge |
| Manual clutch (driver-facing) | **NOT BUILT** | 3G: clutch key through the existing clutch state |
| Manual reverse | **NOT BUILT** | 3G: R unreachable in manual today — fix queued |
| Gearbox modes (comfort/sport) | **NOT BUILT** | 3G: 3-way mode |
| Elastic pedals / profiles | **NOT BUILT** | 3F: input shaping + HUD pedal bars + driver profiles |
| Tyre marks | **NOT BUILT** | 3H: decal trails from slip |
| Telemetry persistence | **NOT BUILT** | 3E: JSON-lines per run |
| Wheelspin launch | **partial** | ordinary launch runs at grip peak (honest 3A deviation); clutch-drop spins |
| AWD diff | **approximation** | engine inertia/torque split by TORQUE_DISTRIBUTION; open per-axle; real diff = future |
| Per-wheel lateral dynamics | **simplified** | bicycle model: left/right wheels of an axle share slip; true per-wheel model = future |
| Ride-height coupling | **simplified** | body heave real but aero/wet/etc. per-wheel load effects still simplified |
| Sound | **NOT BUILT** | engine/tyre/wind — the comfort mode's "balance of sound" waits on this |
| Weather/wet | **NOT BUILT** | surfaces backlog |

## 3. INTERACTIONS THAT MATTER (the physics chain per tick)

1. Driver input → steering wheel state (900°, hand speed) → rack → front wheel angle.
2. Engine ω integrates combustion − friction − clutch load; idle/limiter manage it.
3. Clutch couples engine ↔ gearbox-side inertia (locked: one shaft, reflected inertia).
4. Gear ratio scales torque to the driven axle's wheel ω; brakes/handbrake also act on ω.
5. Wheel ω vs road speed → slip ratio; wheel angle vs travel → slip angle.
6. Tyre curves + friction circle → forces at contact patches (load = spring forces).
7. Force sums/moments integrate chassis velocities + yaw; assist may add bounded yaw.
8. Suspension corners integrate heave/pitch/roll from road + forces; weight transfer emerges.
9. Road profile under each wheel sets spring compression; ground mesh + backstop plane render/collide.
10. Low-speed blend swaps tyre forces for parking geometry below ~14 km/h.

## 4. VERIFICATION STRUCTURE

- `tests/smoke_test.gd` (501 checks): fences every claim above — drivetrain chain,
  suspension statics (drop/dive/squat/roll vs rigid-body math), raw steering identity,
  slide-settle, certifications-as-data (5), camera/mission suites. Deterministic:
  triple byte-identical runs required.
- `scripts/handling_tests.gd`: the five tests-as-data (slalom/spins/stop box/J-turn),
  either-direction spin judging, target times. Certifications = the physics gate.
- Debug tooling: wheel cam (C×5), X-ray (X), look-back (B), glances (,/.) — "see the physics".

## 5. WHAT'S STILL ON THE LIST (ordered)

**Phase 3 remainder:** 3C cockpit look-back (head turn), 3D mission destinations + medals,
3E telemetry persistence, 3F driver profiles + elastic pedals + pedal bars, 3G fuel +
comfort/sport/manual + manual reverse + manual clutch key + ABS/TCS toggles, 3H tyre marks.
**Phase 4:** 4A garage/menu/free-drive; 4B Blender car pipeline (CC0 first) + Nordschleife
(touristenfahrten only) from the data-research report; 4C world dressing (grass/gravel/sand
grip surfaces, buildings); 4D sounds (engine/tyre/wind); 4E casual archetypes (taxi,
delivery, explore); 4F AI test drivers + skill tiers; 4G damage + DNF mission logic;
4H more cars (911 Turbo noted).
