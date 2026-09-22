# FACTORY DRIVER — NIGHT SHIFT 3 LOG (2026-09-22)
# Honest record of the shift: what was done, what remains. Companion docs: docs/design/,
# docs/art-direction.md. The detailed user-facing report lives outside the repo (project scratch).

## VERIFIED & PUSHED (every iteration double-gated: external job + orchestrator + independent re-run; suite byte-identical; certs byte-locked; zero errors)

| It | What | Commits | HEAD after |
|----|------|---------|-----------|
| 3X | Thermal reset semantics: R keeps heat, cools by physics | b445d79 | b445d79 |
| 3W | Mass ledger: 27-row mass table summing to kerb 1300 exactly, 38/62 split | 9b0fb7b | 9b0fb7b |
| 3L | Wear & aging: six accumulators over existing physics, staircase effects | e294ebe | e294ebe |
| 3K | Licence ladder: L0 sitting (7 elements), skid pad, the gate, ranks | c5343c5 | c5343c5 |
| 3Y | R does not refuel: reset keeps fuel like heat/wear (user's 12:55 bug) | 2a4ce24 | 2a4ce24 |
| 4A | Garage/menu on Tab + THE STUDY (21 live lessons, input display) + car condition + licence panel + data location (FD_DATA_DIR, copy-only migration) + HUD bar legend; menu_test step | d48b0cf | d48b0cf |
| 3Z | Licence sitting memory: per-element progress persisted, resume at first failed element, theory never retaken once passed, practice runs change nothing; instructor's car manual->auto after hill start (user's verdicts) | fdf7464 | fdf7464 |
| 4A.1 | UI readability: every surface fits 1280x720; 23 overflow checks walk the UI (the standing visual-defect rule encoded) | 3ba3cea | 3ba3cea |
| 3AA | Caster return like a real car: zero at standstill, none in reverse, speed-gated rolling return; five drivers re-taught to countersteer; certs re-baselined honestly | 9db6638 | 9db6638 |
| 3AC | Airborne honesty: unsupported wheels carry nothing (phantom force removed), ballistic flight, no drive/grip/rolling/hill in the air, full-droop wheels, honest landing; airborne_test step | 1db32ba | 1db32ba |
| 3AB | Wear measured in kilometres: rated lives (clutch 175k, pads 50k, tyres 25.5k/17k, engine 140k km, sourced/labelled estimates) + driving style as metres-of-life on top; equivalences measured (launch ~474 m clutch, stop ~252 m pads, donut ~1.26 km rear, idle ~31 km/h-equiv) | c5ee9c3 | c5ee9c3 |
| 3AD | Landing honesty: premise corrected by measurement — the bug was large-attitude seat extrapolation (266 kN catapult -> tumbling -> springs-flat "cat landing"), NOT the tail hop; exact rigid-body seat geometry above 0.1 rad, the shell as contact (bounded stops + friction), deterministic topple, no guaranteed four-down; the flip (F) rights an overturned car at rest, orientation only | 74aaef5 | 74aaef5 |

Certified times at shift end (byte-locked): SLALOM 28.65 (was 28.82 before 3AA's caster; moved honestly, cited) / SPIN_180 15.95 / SPIN_360 18.07 / STOP_BOX 8.72 / REVERSE_180 7.72. Suite: 1281 ok across 13 headless steps.

## THE DRIVER'S CATCHES (all found by playtesting, all recorded with telemetry where given)
- 12:55 R-refuel bug -> fixed in 3Y. 14:56 sitting forgets passed elements -> 3Z. 16:15 STUDY tab off screen + the standing visual-defect rule -> 4A.1.
- ~17:25 ramp jump "wheels and body fell apart, joints stretched" -> 3AC (phantom wheel force). 20:35 retest "wheels stick to their axis... every jump ends up on all 4 wheels, like a cat" -> 3AD (large-attitude seat catapult; shell contact; no guaranteed landing).
- 23:30 flip with no wheels (side-rest: wheels invisible; roof-rest: wheels reversed) -> 3AE.
- 23:50 handbrake rollover "rolled around its axis without letting the lateral force move the car... like the car hit a wall" -> 3AF (rollover must tumble along its momentum, not pivot on a pinned contact).

## IN FLIGHT AT SHIFT CLOSE (honest state)
- 3AE + 3AF (the two catches above): external job editing scripts/car.gd (uncommitted), gates pending — it pushes itself when green. Certs byte-locked throughout.
- Design synthesis draft (art canon x gameplay, the driver's brain dump folded in) filed at docs/design/design-synthesis-draft.md — DRAFT, awaiting the driver's verdict before 4B.

## DESIGN CANON REGISTERED THIS SHIFT
- docs/art-direction.md — the visual canon (verbatim driver brief; Porsche Unleashed PC 2000 aesthetic; road-is-the-composition; asset priority 1-4).
- docs/design/user-thoughts-economy.org — the driver's brain dump (verbatim): troc economy (goods/services/vouchers), cat ecology (population, scare level, 9 lives = 9 guaranteed landings, cats never die on the Ring, social gas stations), teleport bridges, living traffic (drivers die without a car unless they have a cat; school rigor scales with deaths), home-made cars + registration numbers, OSM skeleton world first, environment-dependent sound.
- The Ring as proving ground: jobs -> materials -> workshop -> build -> test on the Nurburgring -> car.

## WHAT REMAINS (queue, honest)
1. 3AE/3AF gates + push (in flight).
2. Driver's verdict on the design synthesis (open questions: building types, first OSM chunk scope, proving-ground pass rules, car ladder, first teleport destination).
3. 4B-prep: OSM skeleton world (data pipeline researched: docs/nordschleife-data-sources.md — DGM-2 LiDAR + OSM, free-with-attribution) + the Green Hell brief carrying the art canon; gravity-on-slopes physics rides here.
4. Then per the synthesis sequence: cats -> troc economy -> Ring proving ground -> living traffic -> sound -> Blender car pipeline (home-made models; the boxy placeholder is the canon violation to fix).
- Backlog (user-verdict pending or parked): tyre compounds per-compound thermal character; the STUDY's coming-soon lessons (drifting, quick turn need slide-reading pilots; traffic rules need the 4C world); recorded-telemetry scrub playback; 4A garage catalogue-skin pass; OSM continental dream (Phase 4 back end).

## METHOD (unchanged, for the record)
Headless verification only (the driver may be driving); every iteration = orchestrator subagent driving an external claude_code job + double gates + independent re-run; tests additive-only, checks never weakened; every retune documented was-> reason; suite byte-identical twice + --parallel; push only after gates. User canon: "we're not looking for drama, we are looking for real physics simulation."
