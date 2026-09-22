# FACTORY DRIVER — DESIGN SYNTHESIS DRAFT (art canon × gameplay)
# Status: DRAFT — awaiting the driver's verdict on the open questions (§6) before 4B dispatch.
# Sources: docs/art-direction.md (canon), docs/design/user-thoughts-economy.org (the driver's
# brain dump, verbatim), the plan + night report, docs/vision-teaser.md.

## 1. THE IDENTITY

Factory Driver is a real automotive simulation wrapped in a warm, slightly naive cartoon world — the inverse of what modern racing games do. Where they paint fake drama over simplistic physics, this project puts *honest simulation first* and then draws, over it, the quiet European road-trip world of *Need for Speed: Porsche Unleashed* (2000). The canon sentence that governs everything:

> *"Real sim, cartoon world — the 0.0.0 of Matrix."*

The car is a real machine: engine inertia, fuel-cut limiter, clutch that stalls, tyres that heat, wear that stays. The world is a *cartoon* — not a parody, not pixel art, not PS1 retro — but a hand-made, slightly-too-colorful representation of European roads, built from economical geometry and photographic textures, where the car is *"considerably sharper and glossier than everything around it."*

There is an almost **lonely Sunday-drive quality** to it. The environments exist to make the car look beautiful. The player sees *"Porsche → road → landscape"* in that order. The simulation doesn't know how to lie, and the world doesn't try to compete — it frames.

> *"A red, yellow, silver or blue Porsche should visually pop out of the landscape. The environment is supporting cast. The automobile is the product photograph."*

The philosophy, restated by the driver:

> *"We're not looking for drama, we are looking for real physics simulation."*

---

## 2. WHAT THE SIMULATION ALREADY IS

- **Force-based chassis** — rigid-body yaw from tyre forces, friction ellipse, RWD/FWD/AWD, brake bias, downforce + drag; "throttle changes the corner" fenced forever.
- **True drivetrain** — engine inertia, torque curve, idle, fuel-cut limiter; feathered clutch, gearbox reflected inertia, real engine braking. 0–100 ~7.1 s.
- **Real suspension** — four spring/damper corners, anti-roll bars; weight transfer emerges from CG and tyre forces; validated within 20 N of rigid-body statics.
- **900° steering** — rack, hand speed, speed-dependent assist, play, bushing compliance, caster return speed-gated (zero at standstill, none in reverse).
- **Thermal** — coolant warm-up/fan/fade, tyre window, brake disc temps with fade.
- **Fuel & mass** — 64 L, dry-tank stalls, total_mass() = kerb + fuel + payload.
- **Battery** — starter/alternator/deep-discharge wear.
- **Wear (3AB)** — kilometres-based rated lives + driving style as metres of life; staircase effects; persists.
- **Airborne + landing (3AC/3AD)** — ballistic flight, full-droop wheels, shell contact, bounded stops, deterministic topple, the flip (F).
- **Licence ladder** — L0 7 elements resumable, instructor's car (manual → auto after hill start), skid pad, L1.
- **THE STUDY** — 21 live lessons with input display; honest coming-soons.
- **Garage (4A)** — five tabs, per-car condition, licence panel, HUD legend, data location; readability-gated.
- **Cameras/HUD** — 5-stop cycle, x-ray; sparse instrument-like bars.
- **Determinism** — ~1281 checks, byte-identical runs, additive-only tests, was→ citations.

## 3. THE ART CANON APPLIED TO WHAT EXISTS

- Chase camera + HUD: **compliant** (tuned before the canon).
- Garage: needs the catalogue-skin pass (dark charcoal, silver, thin lines, car as focus). **OPEN**
- Car model: placeholder primitives — **violates the canon**; the Blender pipeline is the fix.
- Road composition: flat test pad — **the violation 4B exists to fix.**
- Atmospheric haze: not yet implemented (canon haze table is the target).
- Asset priority 1–4 (road shape, landscape silhouette, Porsche silhouette, lighting) is the build order from 4B on.

## 4. THE ROADMAP (canon + the driver's brain dump)

### The Ring is the proving ground
> *"Though nurburgring is where we test the cars."*

Jobs → materials → workshop → build → **test on the Nürburgring** → car. A built car must prove itself on the Ring before it enters the world. Builders who cannot get their car round the Ring honestly do not sell cars.

Two acquisition paths: **vouchers at exactly-positioned dealerships** (Porsche/General), and the **workshop-building path** (build or commission, prove on the Ring, own or sell).

### The OSM skeleton world (start NOW, driver's preference)
OSM data as the world skeleton; typed buildings: Workshops (owned/not, capacities), Dealerships (Porsche/General), Gas Stations (Public-social/Cat-required), Garages. Discoverability: the map unlocks where you've driven; a cat enables teleport anywhere; unconnected landmasses connect through the teleport car bridge (a building with its own demand; costs a voucher or destination-side property).

### The TROC economy
> *"An economy based on troc — goods for goods, services for services, services for vouchers, vouchers for services — even if it's service for voucher for a car."*

No money. Goods (materials, components, tuna, new fuel formulas), services (shipping, labour, Ring testing), vouchers (missions, bonuses, tips). One-for-many, many-for-one. Player telemetry = training data for AI drivers — player demand ripples through the world.

### Jobs
Realistic ETAs achievable even in eco mode at minimal wear; multiple simultaneous jobs; early-arrival bonuses (fuel vouchers, the Côte d'Azur workshop, a Green Hell garage, new destinations).

### The cat ecology (decided)
Population by probability from the OSM-guestimated start; gene-mutation tuning toward rescue-ability/survival/reproduction; traffic kills; starvation takes all 9 (unfed strays unprotected). Scare level: airborne + g-force raise it, habituates through fluid driving, accidents spike it, scare events save verbose telemetry. Zero lives = gone forever, rescue a new one. Landing mechanic: predicted roof-landing within 3 car-heights → auto-rotate to wheels, one life spent, no cinematics; always-on with a banked life; lives are her only state, persisted. *"Cats never die on green hell — the car lands on its feet and the cat never dies."* Fuel: 10% social stations (free fuel + 5 tuna/visit with a cat), all others cat-required, players can own stations and hire drivers; death/rescue spots marked forever; OPEN experiment: do strays gather at social stations?

### Traffic as living drivers
> *"A driver dies if they remain without a functional car (unless they have a cat)."*

New drivers enter a school that grows more rigorous with deaths; density grows naturally from the economy. Telemetry meets AI meets traffic.

### Cars
All home-made (911 Carrera, Boxster, Turbo suggested; non-Porsches welcome), registration numbers, same model ownable repeatedly as distinct cars. First world entry: certification voucher for a non-Porsche + free 1-hour dealership rental (liveried, eco-only, aids locked).

### Sound
Real sim data; environment-dependent (tunnel / buildings / open nature).

### Sequence
1. OSM skeleton world + typed buildings (start NOW)
2. Cats 3. TROC economy 4. Nordschleife proving ground 5. Traffic 6. Sound 7. Blender car pipeline
(3AE flip-visuals + 3AF rollover-momentum ride first as small physics fixes.)

## 5. THE CAT-MATRIX MECHANIC (verdict table)

| Question | Verdict (driver, 2026-09-22) |
|---|---|
| Rescue/cadence | Strays by population probability; OSM start; gene-mutation; traffic kills; starvation kills unfed strays. |
| Zero lives | Gone forever; rescue a new one. |
| Fuel | 10% social stations free fuel + tuna; others cat-required; ownable stations, hired drivers. |
| Presentation | Predicted roof-landing within 3 car-heights → auto-rotate, one life, no cinematics. |
| Cooldown | Always-on with a banked life. |
| Persistence | Lives are her only state; persisted. |

## 6. OPEN QUESTIONS FOR THE DRIVER (verdict wanted)

1. **Economy buildings** — candidates: tyre centres (compounds/retreading), scrapyards (salvage materials), test centres (AI drivers' exams), cat sanctuaries (rescue/adoption), fuel depots (bulk), proving-ground offices (Ring booking + telemetry), component shops (brake/suspension/electrical specialists). Which join Workshops/Dealerships/Gas Stations/Garages?
2. **Skeleton-first scope** — the first OSM chunk: Eifel-first (Adenau/Nürburg, the Ring's home roads) or wider? How much world drivable at first?
3. **Proving-ground rules** — what passes a Ring test for a workshop-built car: clean lap without component failure? Class-relative time window? AI peer review of telemetry?
4. **Car ladder detail** — Boxster → 911 Carrera → 911 Turbo named; RS 2.7 from the old plan? Cayman? Which non-Porsches fill the fleet?
5. **Region priority** after the Ring: Rural France, Alps, Mediterranean, Schwarzwald, Autobahn, Industrial District — first teleport-bridge destination?

## 7. WHAT WE MUST NOT DO

- No modern-racing aesthetics (no HDR excess, lens flares, teal/orange, bloom, volumetric fog everywhere); dark cockpit; photographic skybox.
- No fake content — the simulation doesn't negotiate.
- No drama-over-physics — *"we're not looking for drama, we are looking for real physics simulation."*
- No checks weakened — bounds hold forever; retunes documented was→reason; suite byte-identical.
- No PS1 retro / pixel art / modern photorealism — *"recreate how developers in 2000 attempted to portray reality beautifully."*
- No fake steering — a parked car's wheel stays where you leave it.
- No environmental storytelling clutter — a village is 8 houses, a church, a stone wall, enough.
- No mobile-app UI — the garage is a dark-charcoal automobile catalogue.
- No retro as an excuse for sloppy geometry — minimum geometry, convincing silhouette; a Porsche needs more than a mountain.
- **The road is the composition — never forgotten.**
