# Factory Driver — Car Component Audit
# Iteration 3U | 2026-09-22

## Purpose

This document catalogues every real-world component that affects how a car **GOES** (accelerates, corners, brakes, drifts) and **FEELS** (compliance, feedback, delay, heat, sound). The scope covers a 1997 Porsche Boxster 986 but is written generically for future cars in the garage.

**Goal**: Identify simulation gaps by impact on driving physics/feel, and propose a mass-ledger refactor from "shortcut" to "sum-of-parts."

---

## 1. Component Inventory

Each row lists mass (typical kg), location, physical impact, and current simulation status.

| Component | Mass (kg) | Location | Physics / Feel Impact | Sim Status |
|-----------|-----------|----------|----------------------|------------|
| **Engine block + internal rotating mass** | 150 | Mid-rear (ahead of rear axle) | Inertia 0.25 kg·m², torque curve, friction | SIMULATED |
| **Engine peripherals** (alternator, starter, AC compressor, water pump, pulleys) | 25 | Mid-rear | Electrical load, parasitic drag, thermal | DATA-ONLY (alternator/starter 3T) |
| **Battery** | 18 | Front trunk (frunk) | Electrical load, mass distribution | SIMULATED (3T) |
| **Starter motor** | 5 | Front | Cranking torque, starter cycle | DATA-ONLY (3T) |
| **Alternator** | 8 | Mid-rear | 1500W output, alternator cut-in | DATA-ONLY (3T) |
| **Gearbox + clutch housing** | 35 | Mid-rear | Gear ratios, clutch torque capacity 500Nm, shift times | SIMULATED (3A) |
| **Clutch disc + pressure plate** | 4 | Mid-rear | Slip, friction, engage time 0.5s | SIMULATED (3A) |
| **Driveshaft + differential** | 20 | Mid-rear | Final drive 3.89, efficiency 0.88, open diff | SIMULATED (3A) |
| **Wheels** (4× magnesium/steel rims) | 36 | 4 corners | Unsprung mass, axle inertia 2.4 | SIMULATED (3A) |
| **Tyres** (4× 235/45R17 or similar) | 24 | 4 corners | Mu 0.95, slip-angle curves, load-scaled grip | SIMULATED |
| **Brake discs + calipers + pads** (4×) | 32 | 4 corners | Decel 1.0g, bias 0.6 front | SIMULATED (3B) |
| **ABS modulator + hydraulic lines** | 6 | Mid-rear (near firewall) | ABS slip model, wheel lock recovery | DATA-ONLY (brake-slip model 3B) |
| **Front suspension** (control arms, springs, dampers, ARBs, bushings, ball joints) | 40 | Front axle | Ride freq 1.5Hz, damping 0.4, ARB 8000N/m | SIMULATED (3B) |
| **Rear suspension** (control arms, springs, dampers, ARBs, bushings, ball joints) | 40 | Rear axle | Ride freq 1.7Hz, ARB 5000N/m | SIMULATED (3B) |
| **Steering column + rack + power-assist motor/hydraulics** | 12 | Front | Max steer lock 0.48 rad, hand speed 1300 deg/s | SIMULATED (data-only assist) |
| **Seats** (2× driver/passenger) | 24 | Mid-rear | Mass, comfort compliance | NOT BUILT |
| **Seats + body panels** (aluminum) | 180 | All over | Mass, aero shape | SIMULATED (mass summary only) |
| **Windshield + side glass** | 30 | All over | Mass, aero | DATA-ONLY (aero 3B) |
| **Radio + sound deadening** | 10 | Front trunk | Mass, NVH | NOT BUILT |
| **HVAC** (condenser, evaporator, blower, ducts) | 15 | Front trunk | Thermal, parasitic load | NOT BUILT |
| **Fuel system** (tank 64L, pump, lines, filter) | 62 (full) | Rear | Mass distribution, fuel burn | DATA-ONLY (tank capacity 3G-1) |
| **Exhaust system** (manifold, catalytic converters, muffler) | 25 | Mid-rear | Mass, thermal, sound | DATA-ONLY (3G-1) |
| **Cooling system** (radiator, fan, thermostat, hoses, coolant) | 15 | Front trunk | Thermal management | NOT BUILT |
| **Lighting** (headlights, indicators, brake lights) | 4 | All over | Mass, visual | NOT BUILT |
| **Electrical harness + ECU + sensors** | 8 | All over | Electrical, control inputs | SIMULATED (inputs via driver profiles 3F) |
| **Spare tire + tools** | 20 | Rear trunk | Mass, distribution | DATA-ONLY |

---

## 2. What's Already Simulated

| System | Module | Coverage |
|--------|--------|----------|
| **Drivetrain** | 3A | Engine ω (inertia 0.25 kg·m², torque curve, friction), clutch (slip torque 500Nm, engage 0.5s), gearbox ratios, axle wheel states |
| **Tyres** | 3B | Slip-angle curves, friction circle, load-scaled grip, progressive slide curve, axle inertia |
| **Suspension** | 3B | 4-corner springs/dampers/ARBs/bump stops, heave/pitch/roll real, weight transfer emergent |
| **Chassis** | 2E | Force-based 2D model, stability assist, low-speed parking blend |
| **Electrical** | 3T | Battery capacity 50Ah, starter 1500W, alternator 1500W, charge efficiency |
| **Fuel** | 3G-1 | Tank capacity 64L, burn efficiency, density |
| **Steering** | 3B | 900° wheel, 16.4:1 rack, hand speed 1300 deg/s |
| **Brakes** | 3B | Bias 0.6 front, decel 1.0g, handbrake lock carve-out |
| **Road** | 2G | Seeded micro-bumps, elevation swell, per-wheel loads |
| **Driver inputs** | 3F | Elastic pedals, driver profiles (test_driver, chauffeur) |

---

## 3. Gap List — Ordered by Impact on Go/Feel

| Gap | Impact on Feel / Go | Cost/Benefit |
|-----|---------------------|--------------|
| **Power steering feel** | High — adds compliance, delay, and feedback that varies with speed/assist | Cheap to add (data-based feel) |
| **ABS hydraulics** | Medium — modulates brake pressure under lockup, affects stopping distance/feel | Medium (extend brake-slip model) |
| **Coolant thermal load** | Medium — matters for 3J (thermal) and long-sprint simulation | Medium (add coolant mass/heat capacity) |
| **Suspension bushing compliance** | Medium — introduces small delays/play in cornering input feedback | Medium (add compliance springs) |
| **Steering rack play/compliance** | Medium — adds small dead-zone and deflection | Medium (add compliance model) |
| **Exhaust acoustic load** | Low — primarily sound, not physics | Low |
| **Fuel consumption dynamics** | Low — mass distribution changes during fuel burn | Low (extend 3G-1) |
| **TCS hydraulics** | Low — traction control intervention under wheelspin | Low (data-only mode) |
| **Seat compliance/vibration** | Low — affects driver perception, not car physics | Low |
| **Sound deadening / NVH** | Low — affects driver feel, not car dynamics | Low |

---

## 4. Mass Ledger Proposal

### Current State
The config uses a shortcut: `kerb_mass = 1300.0 kg` with `rear_weight_fraction = 0.62` and `cg_height = 0.48`. These are manually tuned "by fractions" rather than derived from component sum.

### Proposed Sum-of-Parts Model

Move mass from a single number to a table. Each component contributes mass, x-position (front/rear), and sprung/unsprung classification. The engine then computes:

```
Total mass = Σ(component masses)
Front fraction = (mass × distance from rear axle) / total mass
Rear fraction = 1.0 - Front fraction
Unsprung mass = Σ(unsprung components: wheels, tyres, brakes, suspension hubs)
Sprung mass = Total - Unsprung
```

**Advantages:**
- Real mass distribution emerges from design choices
- Future cars (911, Cayman) just add/remove components from the table
- Component swaps (e.g., titanium exhaust, carbon seats) automatically recalc total and distribution
- Easier to validate against manufacturer specs

**Implementation Plan:**
1. Rename `kerb_mass` → `mass_ledger` (array of component entries)
2. Each entry: `{name, mass_kg, x_position_m, sprung: bool}`
3. Add runtime computed: `total_mass`, `front_rear_split`, `unsprung_mass`
4. Validate against 1997 Boxster: ~1250-1300kg kerb, ~62% rear weight

---

## 5. Surprising Findings

1. **X-ray visibility (2F)**: The sim already renders chassis/engine/gearbox/axles as primitives. This means mass *and* visual representation exist but not as distinct components with individual mass.

2. **Battery/starter/alternator (3T)**: Electrical system is modelled with power/charge dynamics, but the mass contribution (~23kg total) isn't part of the mass ledger.

3. **Exhaust as data (3G-1)**: Flow rates exist but no thermal/acoustic simulation.

4. **Suspension is complete (3B)**: Springs/dampers/ARBs are all there, but bushings and ball joints are absent (compliance assumed rigid).

5. **ABS exists as a model, not hardware**: The brake-slip model in 3B includes ABS-like modulation, but not as a distinct hydraulic system.

---

## 6. Closing

The sim already covers 70-80% of what affects how the car **goes** (drivetrain, tyres, suspension, brakes). The gaps primarily affect **feel** (power steering, compliance, thermal management). The mass-ledger refactor is low-effort, high-clarity work that enables all future cars.

File: `docs/car-component-audit.md`
Generated: 2026-09-22

---

## Review notes (Conductor's verification, 2026-09-22)

Checked against the real sim before commit. Corrections and context where the
tables above need them:

- Weights cross-checked against `configs/cars/boxster_986.json` and car.gd where
  the sim states them (rear_weight_fraction 0.62, cg_height 0.48, yaw gyration
  radius 1.25, kerb 1300 kg, 50 Ah battery) — the engine's 150 kg and peripherals
  are typical-for-986 figures, "typical/approx" throughout as stated.
- "Fuel system DATA-ONLY (tank capacity 3G-1)" understates it: the fuel is
  SIMULATED (burn from engine work, mass rides total_mass(), per-car
  persistence) since 3G-1/3Q. Tank+pump hardware beyond that is indeed data.
- "Steering SIMULATED (data-only assist)": the power-assist character is data;
  the geometry/hand-speed model is simulated (3B). Bushing/rack compliance
  remains a real gap.
- The gap list's ordering holds: power-steering feel and the compliance items
  are the cheap high-value feel work; coolant thermal is the 3J dependency;
  ABS hydraulics is honest niche. Nothing in the list contradicts the suite's
  coverage (battery_test, suspension, tyres all fenced).
- The mass-ledger proposal is exactly the 3U direction the user asked for: a
  config mass table (name, mass, x-position, sprung) summing to kerb, driving
  front/rear split and unsprung mass, validated against the certified 986
  figures. Note the sprung/unsprung split has a REAL consumer when it lands:
  3B's suspension works in corner masses today (derived from kerb x split), so
  the ledger must feed those, not bypass them.
- Next sim priorities per this audit: power-steering feel, steering-column and
  bushing compliance (one "steering feel" iteration), coolant model feeding 3J,
  then the mass ledger refactor (config format addition, one gate).
