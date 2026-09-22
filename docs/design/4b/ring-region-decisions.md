# FACTORY DRIVER — THE RING REGION: DECISIONS PUT IN STONE (design, 2026-09-23)
# Status: 4B-PREP design package, documents only. The driver's verdict (design-synthesis-draft.md
# §8.5): "sure, the ring first region"; "what exists in a region is decided and put in stone when the
# focus first moves to that region". This is that document for the Eifel / Nürburgring region.
# Marks: PUT IN STONE (fixed, changing it is a documented "was ->"), DECIDED, REVISITABLE (a
# choice made so work can start), DEFERRED (not this region's first focus).

## 1. EXTENT AND FRAME

- PUT IN STONE — Region id `eifel_ring`. Bounding box 50.30 N to 50.45 N, 6.80 E to 7.10 E
  (~21.8 km E-W × 16.1 km N-S; UTM32 E 343-365 km, N 5574-5590 km). Covers Nürburg, Adenau,
  Breidscheid, Hohe Acht, Kelberg's edge, the B 258 and B 257 corridors.
- PUT IN STONE — Local origin E0 = 352 000, N0 = 5 577 000 (EPSG:25832), a DGM1 tile corner south-west
  of Nürburg castle. Game x = E - E0, z = -(N - N0), y = absolute height [m].
- PUT IN STONE — Data snapshot: OSM `timestamp_osm_base 2026-09-22T08:45:51Z` from
  lz4.overpass-api.de; DGM1 tiles as listed in the district metalinks 07131/07137/07233
  (published 2026-08-12, tile year 2025). A newer pull is a new, documented snapshot.
- DECIDED, REVISITABLE — What "drivable from the start" means here: every way of q1's classes
  (data-pipeline.md §2.1) is a road with physics; the rest of Europe is the continent-wide
  skeleton (4C), undressed.

## 2. ROADS AT FIRST FOCUS

Live counts 2026-09-23 (Overpass, the bbox above):

| Road | OSM | Ways | Element | Note |
|---|---|---|---|---|
| Nürburgring Nordschleife | relation 38566, `route=road`, 52 `highway=raceway oneway=yes` ways | 52 | R17 | 20 746 m summed vs 20.830 km official (docs/nordschleife-data-sources.md §4): the 0.4 % is node chords; the spline closes it |
| Karussell | way 414785755, `surface=asphalt;concrete`, `maxspeed=none` | 1 | R9 | the one banked section |
| Döttinger Höhe access | way 26543901 "Anbindung zur Nordschleife" | 1 | R18 + E11 | the public entrance |
| B 258 | `ref="B 258"` primary + 9 primary_link | 136 | R1/R2/R4/R14 | the Ring's main road, Adenau ↔ Nürburg ↔ Döttinger Höhe |
| B 257 | primary | 89 | R1/R2 | Adenau's through road |
| B 412 | primary + 2 links | 30 | R1 | north edge |
| L 10, L 73, L 74, L 93 | secondary (+ 15 tertiary on L 93) | 44 / 79 / 9 / 28 | R1/R2/R3 | L 73 = the road up to Nürburg |
| village streets | residential / living_street / unclassified in place polygons | in the 2 181 | R15 | Adenau, Nürburg, Breidscheid, Meuspath, Herschbroich, Quiddelbach |
| tracks / service | track, service (5 gravel raceway service ways) | in the 2 181 | R16 | drivable, plain |
| bridges / tunnels | `bridge=yes` 188 / `tunnel=yes` 28 | — | R10 / R11 | the count includes footbridges; only highway ways of q1's classes are built |

- PUT IN STONE — The Nordschleife's centreline is OSM relation 38566 at the pinned snapshot. The
  GPX/GeoJSON centreline (no licence declared, live) is used only to *check* the OSM one (max
  lateral deviation reported, not applied).
- PUT IN STONE — Track width for R17: 8.5 m default, 7.5 m at the Karussell (recorded §4), OSM
  `width=5` on 22 ways ignored (element-library.md open question 1); verified against DOP20 in 4B-4
  before the mesh is baked; a change is a "was ->".
- DECIDED, REVISITABLE — Public-road widths by class from data-pipeline.md §4's table.
- DECIDED, REVISITABLE — The Nordschleife is drivable in the public direction only (`oneway=yes`),
  entered and left at Döttinger Höhe (R18). Grand Prix circuit (relation 38567) is NOT built at
  first focus: DEFERRED.

## 3. ELEVATION

- PUT IN STONE — Primary: DGM1 (1 m), the 42 core tiles E 352-358 / N 5577-5582 (68.3 MB) for the
  Nordschleife and Nürburg; the full bbox's 391 tiles (658.2 MB) for the region's terrain lattice.
- PUT IN STONE — Reference points the drape must reproduce within the DGM1's stated accuracy plus
  the recorded rounding: Breidscheid (lowest) ~320 m, Hohe Acht / T13 (highest) ~620 m
  (docs/nordschleife-data-sources.md §1). A drape that does not is a pipeline bug, not a tuning.
- DECIDED, REVISITABLE — Slope truth: the recorded gradients (Fuchsröhre 11 % down, short 27 %
  stretches, up to 18 % down Flugplatz → Karussell → Hohe Acht, §1) are what the world profile must
  carry to the car; MAX_SLOPE 0.015 (road_profile.gd:96) is the pad's assumption, explicitly
  exceeded by the world profile (implementation-plan.md, gravity section).
- DECIDED, REVISITABLE — The Karussell bank (recorded §2: "Concrete slabs (steep bank) with a thin
  asphalt strip at the bottom"): decision tree at 4B-3: (a) open DGM1 tile 355_5580: if the bowl's
  cross-section shows a bank ≥ 20 %, use it; (b) else open DOM1/DOMB for the same tile (the
  surface model carries structures); (c) else the R9 element's parametric bank (bank 30 %, bowl
  width 6.5 m, asphalt strip 1 m) fitted to the OSM way. Whichever wins is recorded here as
  "was ->".
- DEFERRED — Surface bumps and seams (recorded §2: Bergwerk seams, Brünnchen concrete patch): the
  micro-bump layer of the world profile takes them when a per-segment seed table exists (4B-4+).

## 4. WHAT EXISTS AROUND THE RING (buildings, live OSM 2026-09-23 unless marked "by rule")

| Place / thing | OSM | Element | Decision |
|---|---|---|---|
| Nürburg castle ("Nürburg (Ruine)") | way 31010481 `historic=castle` | B3 | PUT IN STONE — the region's landmark; placed by id; the canon's "pale stone village sits farther down the valley" is Nürburg village below it |
| Adenau | `place=town`, its footprints | B0/B1/B2 shells, R15 | PUT IN STONE — dressed from footprints; Eifelstadion (way 429774835) as a B4 tier |
| Breidscheid + bridge | village, the Nordschleife's lowest point | B0, R10 | PUT IN STONE — the bridge is the R10 at the Breidscheid ways (683006908 / 683061813 / 683061814) |
| Grandstands | 12 `building=grandstand` (T4-T10, BMW, Mercedes tribunes) | B4 | DECIDED, REVISITABLE — built as tiered boxes; they belong to the GP circuit side, which is deferred, but they are the T13 skyline |
| Petrol stations | 9 `amenity=fuel`: Aral Adenau (node 12023011572), ED Döttinger Höhe Meuspath (node 1711333738), 24h Tankstelle Hoffmann Adenau (way 1497869198), Total (way 114676264), TC Tankstelle (node 483724476), Aral (node 483724477), ED Leimbach (node 732711989), Independent (node 1335615680), Aral (way 1023567856) | E2 | PUT IN STONE — exactly these nine, no invented station ("gas stations are RARE"). Brands dropped in-game ("no trademarks"). SOCIAL station: round(0.1 × 9) = 1: the one at Döttinger Höhe (node 1711333738), because it stands at the Ring's gate where cats and drivers meet (the driver's open experiment: "see if the stray cats will gather more on the social gas stations"). DECIDED, REVISITABLE — the pick; PUT IN STONE — the count |
| Workshops | 9 `shop=car_repair`: Teichmann Racing (way 304343082), Matech Sports (node 2573632801), fawerk.de (way 533640757), Nico Lieder (way 533642836), KFZ Bongard (way 948590128), Autoservice Gebauer (node 12047929770), Renault Autohaus Kirfel (way 410078995), Porsche Service Zentrum Meuspath (way 1182024168), one unnamed in Boos | E1 | PUT IN STONE — all nine exist as startups ("they are the startups that create everything"); names replaced by serial workshop ids; capacity by footprint |
| Porsche dealership | Porsche Service Zentrum Meuspath, way 1182024168 | E3 | DECIDED, REVISITABLE — promoted from E1 to E3: the region's one Porsche house, by the Ring |
| General dealership | Autohaus Rausch, way 831174023 (`shop=car`, Nissan) | E4 | PUT IN STONE — the first-run voucher's dealership for this region (first-run-flow.md §5); unbranded in-game |
| Test centre | Fahrschule Hecken, way 667524970 (`amenity=driving_school`) | E8 | DECIDED, REVISITABLE — the region's test centre where OSM has the school; its yard is the pad's licence course on the flattest DGM1 patch within 300 m (slope < 1.5 %); if none, the yard moves to the Nürburgring industrial estate (`landuse=industrial` by Meuspath) and the school building stays a B9 |
| Proving-ground office | by rule at way 26543901 (Döttinger Höhe entrance) | E11 | PUT IN STONE — the Ring's booking and telemetry desk stands at the public gate |
| Industrial estate | 16 `landuse=industrial` polygons; the one at Meuspath/Nürburgring | B5, E6 (tyre centre by rule), E12 (component shop by rule), E7 (scrapyard by rule) | DECIDED, REVISITABLE — the three rule-placed E-types share the estate by the Ring |
| Fuel depot | by rule; no `man_made=storage_tank` matched in the bbox | E10 | DEFERRED — the region buys fuel from outside until a depot region exists |
| Cat sanctuary | none tagged (`amenity=animal_shelter` = 0) | E9 | DECIDED, REVISITABLE — placed by rule at Breidscheid, at the valley floor by the bridge: lowest point, a village, the Nordschleife's mid-lap where a rescue after a Fuchsröhre scare is a short drive; and 3 km from the social station so the "gather at social stations" experiment has two poles to measure between |
| Castles beyond Nürburg | Burg Aremberg (way 73559816), Virneburg, Motte Kasselsburg | B3 | DEFERRED — silhouettes only if visible from a q1 road |
| Teleport bridge | none (inland region) | E13 | DEFERRED — a coastal region's |

## 5. REGION DRESSING (the Eifel palette, from the canon's Alps + Schwarzwald guidance)

- PUT IN STONE — Sky set: S1 clear day as default; S2 overcast as the second plate; S3/S4 later.
  Haze table S5 exactly as the canon's ("0–100 m normal saturation ... 800 m+ increasingly
  sky-colored"); haze colour = the plate's horizon.
- PUT IN STONE — Palette (the canon's table, Eifel values): vegetation "muted forest / olive
  greens" with spruce blue-green in V4 walls; road "medium cool grey"; rock "grey" (Eifel slate,
  not the Alps' beige); architecture "cream / white" render with slate-grey roofs (B0 tint set
  `eifel`); water grey-green (the Ahr); sky "pale blue".
- PUT IN STONE — Forest rule: `landuse=forest` edges within 60 m of a road are V4 walls 12-18 m,
  interiors V7 tint; "dark forest → bright clearing → dark forest → village" is the rhythm the Ring
  road already has (Hatzenbach's woods, Flugplatz's open field, Adenauer Forst, Breidscheid).
- DECIDED, REVISITABLE — Density ceilings: trees within 60 m of the road ≤ 1 per 8 m of road per
  side; F4 poles every 50 m on B-roads outside villages; F9 posts every 50 m; parked cars 0-2 per
  100 m in Adenau, 0 elsewhere. The canon's "twenty meaningful objects" is the audit.
- DECIDED, REVISITABLE — Furniture on the Nordschleife: F1 both sides continuous; F14 at the
  recorded run-off spots only; F10 boards every km; no sponsor boards, no cameras, no gantries.
- DEFERRED — Rain (S6), night (S4) on the Ring; the tunnel sound profile.

## 6. DEFERRED (explicit)

- Traffic (living drivers, density "growing from economy") — 4C+.
- Cats' full ecology (population, scare level, sanctuary mechanics) — the sanctuary is a placed
  building only.
- Interior building detail (the canon: none; the workshop's inside is a menu).
- The Grand Prix circuit, the Müllenbachschleife, the rallycross circuit (raceway ways not in
  relation 38566).
- Surface seams / micro-bumps per segment; per-surface friction classes (measured, not assumed).
- Jobs, troc, vouchers beyond the first-run voucher.
- Neighbouring regions' dressing (Mosel, Rhine, Vulkaneifel): skeleton only.

## Open questions
1. The social station pick (Döttinger Höhe) is a design choice; the driver may prefer the one in
   Adenau where more traffic passes.
2. Cat sanctuary at Breidscheid: is a village the right place, or should it sit at the industrial
   estate beside the scrapyard (the strays' likely home)?
3. Should the grandstands be built at first focus when the GP circuit is deferred?
4. DOP20 check of the R17 width: who runs it, and do we keep the orthophoto crop as evidence
   (licence allows it; size ~ tens of MB per km²).
5. Does "drivable from the start" include `highway=track` (forest tracks) in this region, or only
   paved classes? The counts above include tracks.
