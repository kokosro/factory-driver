# FACTORY DRIVER — 4B ELEMENT LIBRARY (design, 2026-09-23)
# Status: 4B-PREP design package, documents only. No code changed.
# Canon: docs/art-direction.md (quoted "..." below), docs/design/design-synthesis-draft.md §8-9,
# docs/design/user-thoughts-economy.org. Ordered by the canon's asset priority (art-direction.md,
# "Blender → Godot asset rule": 1 road shape, 2 landscape silhouette, 3 Porsche silhouette,
# 4 lighting/atmosphere, 5 landmarks, 6 vegetation masses, 7 road furniture, 8 texture, 9 props).

## 0. WHAT THE LIBRARY IS

The driver's architecture principle: "once we build the elements it will be easier to procedural
generate the world from data". The library is built ONCE, by hand, against the canon; OSM and DGM1
data then only *choose and place* elements. A region's "focus" is a table saying which data
assembles which element with which parameters; that table is what gets "put in stone" region by
region (docs/design/4b/ring-region-decisions.md is the first one).

Every entry below has the same five fields:
- **What** — the thing, in one line.
- **Canon** — the line of docs/art-direction.md that governs it, and the judgment.
- **Data** — the OSM tags / DEM input that instantiate it (Overpass-level tags; see data-pipeline.md).
- **Stone / Varies** — what is fixed for every region (silhouette, construction) vs what a region's
  focus table may set (dimensions, palette, density, dressing).
- **2000 look** — how it stays "how developers in the year 2000 attempted to portray reality
  beautifully": economical geometry + photographic textures, nothing from §7 of the synthesis
  ("no modern-racing aesthetics").

Naming: `R` road, `T` terrain, `S` sky/light, `B` building, `E` economy building, `V` vegetation,
`F` furniture. IDs are stable: the region tables and the 4B-1 catalogue (implementation-plan.md)
refer to them.

Two library-wide rules from the canon, quoted once here and assumed by every entry:
- "The road is the composition" — every element is judged by what it does to the 100-500 m of road
  ahead ("The player should frequently see 100–500 metres of road composition ahead").
- "There are maybe twenty meaningful objects visible rather than two thousand." Density is a
  region parameter with a hard ceiling, never a per-element default.

Texture budgets are the canon's ("hero car: 1024–2048 / important building: 512–1024 / road:
repeating 512/1024 / terrain: 512/1024 tiled / props: 128–512 / vegetation: 128–512").

## 1. PRIORITY 1 — ROAD SHAPE (road segments)

The road is one element family with one construction: a centreline (from OSM, draped on DGM1),
a cross-section profile (lanes, shoulders, crossfall), and a surface material. Segments below are
the *shapes* the assembler must recognise in the data, not separate meshes: one sweep builder,
many recognised cases. The flat test pad's road stays as it is (scripts/road_profile.gd is frozen).

### R1 TWO-LANE RURAL STRAIGHT
- What: the default road: two lanes, grass shoulder, no kerb. "a narrow two-lane asphalt road".
- Canon: "Long roads" / "The road consequently becomes a bright ribbon cutting through darker
  scenery." Compliant by construction; it IS the composition.
- Data: `highway=primary|secondary|tertiary|unclassified` ways; width from `width=*` when present,
  else by class (see data-pipeline.md §4); `surface=asphalt` default. Elevation from DGM1.
- Stone: cross-section construction (crown 2 %, shoulder 1.0 m grass, 0 kerb), edge-line paint
  geometry. Varies: lane width (Eifel B-road 3.25-3.5 m; village 2.75 m), asphalt tint per region
  ("medium cool grey" here; "Pale roads" for Mediterranean), centre-line dash pattern (DE: 3 m/6 m).
- 2000 look: one repeating 1024 asphalt texture with "subtle normal / very mild roughness
  variation"; no decals every metre; edge paint baked into the texture strip.

### R2 SWEEPER (gentle curve)
- What: a curve the car takes at speed; the classic "long sweeping mountain curve".
- Canon: "Long curves disappear behind hills." The target screenshot is a silver 911 "entering a
  long sweeping mountain curve". Must be built so the far side is visible or hidden by terrain,
  never by fog ("Do not hide everything behind thick fog").
- Data: consecutive OSM nodes with heading change < ~25°/node; radius from three-point circle fit.
- Stone: superelevation ≤ 4 % on public roads (crossfall banked into the curve; real road practice),
  centreline smoothing (Catmull-Rom through nodes with G1 continuity). Varies: nothing visual.
- 2000 look: the sweep is one strip mesh; the beauty is the sightline, not the tessellation.

### R3 HAIRPIN
- What: a bend > 120°, radius < 30 m (Eifel: Steilstrecke, the road up to Nürburg, alpine passes).
- Canon: "Mountain roads" / "Much more vertical." Compliant; a hairpin is a silhouette event.
- Data: node heading change ≥ 120° over < 60 m of way; `highway=*` unchanged.
- Stone: inner-radius widening (real roads widen the inside by ~1 m), crossfall 6 % max.
  Varies: a low stone wall (F2) or guardrail (F1) on the outside is the region's call.
- 2000 look: the inside verge is a single grass/rock texture; no rubber marks, no debris.

### R4 JUNCTION (T, Y, cross)
- What: two or more ways meeting at a shared node.
- Canon: "Intersections" (Autobahn family) and "Roads descend toward villages." Compliant when
  simple; a junction is 2-4 road strips blended into one flat patch, "recognizable reality
  represented economically".
- Data: an OSM node shared by ≥ 3 way ends (or a way passing through). Priority from
  `highway=*` class ranking; `highway=stop|give_way` nodes for the sign (F6).
- Stone: patch construction (fillet radius 6-12 m by class), give-way triangle paint.
  Varies: sign set (DE "Vorfahrt gewähren" here), whether a village junction gets a kerb.
- 2000 look: one patch mesh, one blended texture; no traffic islands unless OSM has them.

### R5 ROUNDABOUT
- What: a circular junction (11 in the Ring bbox, live count 2026-09-23).
- Canon: "modest European architecture" applies to infrastructure too: a grass island, a kerb ring.
- Data: `junction=roundabout` on the circular way; arms are R4 entries onto it.
- Stone: ring construction (inner island radius = OSM geometry; truck apron 1.5 m).
  Varies: island dressing (grass / low hedge V5 / a single tree V1).
- 2000 look: island is one disc mesh with a grass texture; no sculpture, no flower beds.

### R6 GRADE (LEVEL) CROSSING
- What: a railway crossing the road on the level.
- Canon: "Industrial roads pass underneath structures" — rail is scenery, not gameplay. Compliant
  as a texture event plus two barrier props. Zero in the Ring bbox (live count 2026-09-23), so
  library-defined here and instantiated when a region has one.
- Data: `railway=level_crossing` node; the `railway=rail` way for the track strip.
- Stone: crossing plate 4 m long; barrier post pair. Varies: barrier style (DE St. Andrew's cross).
- 2000 look: the rails are a 512 texture strip; no animated barriers in 4B.

### R7 CREST
- What: a convex vertical curve the car can lighten or lift over (Flugplatz, Schwedenkreuz,
  Pflanzgarten's Sprunghügel).
- Canon: "Long curves disappear behind hills." The crest is the canon's main sightline device.
- Data: not an OSM tag: detected from the draped DGM1 profile (second derivative of elevation
  along the centreline over 20-40 m windows; see data-pipeline.md §5).
- Stone: vertical-curve construction from the DEM (no artificial ramps); the profile is never
  "smoothed away" beyond the 1 m grid's own noise floor. Varies: nothing.
- 2000 look: the mesh follows the DEM at 1-2 m spacing along the road only; terrain beyond uses
  the coarse lattice (T-family).

### R8 DIP / COMPRESSION
- What: a concave vertical curve (Fuchsröhre's bottom, Breidscheid bridge approach).
- Canon: same as R7. The physics dependency (compression loads) is in the car already
  (car.gd's springs read `sample_height`, see implementation-plan.md gravity section).
- Data: as R7, negative second derivative.
- Stone / Varies: as R7.
- 2000 look: as R7.

### R9 BANKED SECTION (the Karussell)
- What: a concrete bowl banked ~30 %, "Concrete slabs (steep bank) with a thin asphalt strip at the
  bottom" (docs/nordschleife-data-sources.md §2).
- Canon: unusual but real: "recognizable reality". Concrete slab seams are in the texture, not
  the mesh; the *bank* is in the mesh because the car feels it.
- Data: OSM way 414785755 `name=Karussell surface=asphalt;concrete` (live, 2026-09-23). Elevation:
  DGM1 is terrain-only and the bank may be smoothed at 1 m; DOM1/DOMB (surface models, same
  OpenData catalogue) or a manual bank profile: decided in ring-region-decisions.md §3.
- Stone: banked cross-section construction (parametric: bank angle, bowl width, flat strip).
  Varies: only the parameters, from data or the region table.
- 2000 look: the slab pattern is a photographic 1024 concrete texture with slab lines; no per-slab
  geometry.

### R10 BRIDGE
- What: road over a river, road or valley (188 `bridge=yes` highway ways in the bbox; Breidscheid's
  is the Ring's lowest point at ~320 m).
- Canon: "Coastal roads expose the sea. Industrial roads pass underneath structures." A bridge is a
  silhouette landmark; parapets are furniture (F11).
- Data: `bridge=yes` + `layer=*` on the way; the deck follows the road profile, not the DEM
  (DGM1 shows the valley under it: the deck's elevation is interpolated from the abutments).
- Stone: deck construction (slab + parapet, span from OSM geometry). Varies: parapet style
  (stone in villages, steel on B-roads, concrete on Autobahn).
- 2000 look: a box deck and two parapet strips; piers are plain cylinders or slabs.

### R11 TUNNEL
- What: road through a hill (28 `tunnel=yes` highway ways in the bbox; "Tunnels cut directly into
  mountains" in the Alps family).
- Canon: "A tunnel needs a convincing entrance silhouette but doesn't require individually modeled
  concrete imperfections." Portal is what matters; inside is a dark tube with lamp pools.
- Data: `tunnel=yes` + `layer=-1` on the way; the terrain is NOT cut: the portal (F12) is stamped
  on the DEM surface and the road passes under the T-mesh.
- Stone: tube cross-section and portal silhouette. Varies: portal face texture (stone / concrete),
  lamp spacing, the sound profile (deferred; user-thoughts-economy.org line 93).
- 2000 look: interior is one tiling 512 concrete texture + emissive lamp quads; "small pools of
  illumination".

### R12 EMBANKMENT CUT
- What: the road cut into a slope: uphill cut face one side, downhill fill the other.
- Canon: "Road embankments." and "Grey rock faces." The cut face is a silhouette and a texture.
- Data: derived: where the DGM1 cross-slope at the road exceeds ~15 %, the assembler builds a
  cut/fill profile so the road platform is flat across (the DEM already contains the real cut;
  the element gives the face its material and its edge).
- Stone: platform-flattening rule (road always level across, ± crossfall). Varies: face material
  (rock T3 / grass / retaining wall F2-stone).
- 2000 look: the face is the terrain mesh with a rock texture; no boulders.

### R13 MOTORWAY / DUAL CARRIAGEWAY
- What: "Wide road. Concrete. Guardrails. Large road signs."
- Canon: Autobahn family, "wet grey infrastructure contrasted with the glossy car". Not in the Ring
  bbox (no `highway=motorway` there; A61 is east of it); library-defined, first instantiated when
  focus reaches an Autobahn region.
- Data: `highway=motorway|trunk` with `oneway=yes` pairs; `lanes=*`; central reservation from the
  gap between the two carriageways.
- Stone: carriageway construction (hard shoulder 2.5 m, central barrier F13). Varies: lanes, the
  wet-weather variant (S6).
- 2000 look: concrete texture with expansion joints baked in; big gantry signs as textured quads.

### R14 SLIP ROAD / LINK
- What: on/off ramps and junction links.
- Canon: as R13; "Intersections" and "Underpasses".
- Data: `highway=motorway_link|trunk_link|primary_link|secondary_link` (B 258 has 9 primary_link
  ways in the bbox).
- Stone: taper geometry (merge length by class). Varies: nothing visual.
- 2000 look: a strip with a painted taper; the merge nose is one triangle patch.

### R15 VILLAGE STREET
- What: the road inside a settlement: narrower, kerbed, houses close ("A village can simply
  contain: 8 houses, church, stone wall, few parked cars, trees, road signs").
- Canon: "Roads descend toward villages." "Small villages." Compliant: the village is where the
  road slows and the B-family stands by it.
- Data: `highway=residential|living_street|unclassified` inside `place=village|town` /
  `landuse=residential` polygons; `maxspeed=30|50`.
- Stone: kerb 0.12 m, footway 1.5 m optional. Varies: kerb on/off, cobble vs asphalt texture,
  parked-car density (0-3 per 100 m; canon says "few").
- 2000 look: kerb is part of the road strip's cross-section (no separate mesh); cobbles are texture.

### R16 TRACK / GRAVEL ACCESS
- What: farm and forest tracks; the Ring's gravel service roads (5 gravel raceway ways in the bbox).
- Canon: "Large stretches where there simply isn't much there." Drivable but plain.
- Data: `highway=track|service` (+ `tracktype=*`), `surface=gravel|compacted|ground`.
- Stone: single-lane cross-section 3 m, no paint. Varies: surface texture, grass strip in the middle.
- 2000 look: one 512 gravel texture; ruts are in the texture, not the mesh. Physics: a surface
  friction class per `surface=*` (deferred to the world-profile work; see implementation-plan.md).

### R17 CIRCUIT SEGMENT (the Nordschleife itself)
- What: a raceway way: one-way, kerbs painted, guardrail-lined, 8-9 m wide
  (docs/nordschleife-data-sources.md §4; note OSM carries `width=5` on 22 of its 52 ways: an
  open question, recorded in ring-region-decisions.md).
- Canon: the Ring is the proving ground ("Though nurburgring is where we test the cars") and it is
  a *road*, not "an artificial racing arena": guardrails and trees, no grandstand clutter except
  where OSM has grandstands (B4).
- Data: OSM relation 38566 `type=route route=road name="Nürburgring Nordschleife"`, 52 member ways
  `highway=raceway oneway=yes` (live pull 2026-09-23: 20 746 m summed, 1 119 nodes, mean node
  spacing 19.4 m; official 20.830 km).
- Stone: the centreline source (relation 38566 pinned to its snapshot), the kerb paint pattern
  (red/white 0.5 m kerbs on the inside of bends only), the F1 guardrail run on both sides where
  OSM has no `barrier=*` saying otherwise. Varies: nothing: the Ring is put in stone.
- 2000 look: kerbs are a texture strip; guardrails are F1 instances at 4 m posts; no sponsor boards.

### R18 PIT LANE / ACCESS LINK
- What: the Döttinger Höhe entrance and exit to the public Nordschleife ("Anbindung zur
  Nordschleife", way 26543901, 16 nodes; T13 pit lane ways).
- Canon: this is where the proving-ground office (E11) stands; a link, not a landmark.
- Data: `highway=raceway|service` ways with `name~Anbindung|Boxengasse` joined to relation 38566.
- Stone: nothing beyond R15-style construction. Varies: barrier type at the gate.
- 2000 look: a barrier arm prop and a booth; "toll infrastructure" in the canon's words.

### Surface classes (all R-entries)
| `surface=*` | texture | friction class (world profile; physics deferred) |
|---|---|---|
| asphalt (default) | road_asphalt_1024 | 1.00 (the pad's) |
| concrete | road_concrete_1024 (slab seams baked) | 1.00 |
| asphalt;concrete (Karussell) | split strip: asphalt inner 1 m, concrete bank | 1.00 |
| gravel / compacted | road_gravel_512 | to be measured before use; never assumed |
| paving_stones / cobblestone (villages) | road_cobble_512 | 1.00 in 4B (visual only) |

## 2. PRIORITY 2 — LANDSCAPE SILHOUETTE (terrain forms)

The terrain is one mesh family: DGM1 sampled onto a lattice whose spacing grows with distance from
the road (2 m at the road platform, 10 m within 200 m, 50 m to 2 km, 200 m beyond), clipped to the
region. The forms below are *what the data produces* and *what dressing rule applies*; they are
not separate meshes. Canon: "Terrain should have broad, readable forms." / "The silhouette matters
considerably more than surface complexity." / "Avoid modern micro-displacement everywhere."

| ID | Form | Canon line | Data | Stone / Varies | 2000 look |
|---|---|---|---|---|---|
| T1 | Rolling hills | "Rolling hills." | DGM1 lattice; slope < 15 % | Stone: lattice spacing table. Varies: grass tint ("muted forest / olive greens"), field patchwork density | grass 1024 tiled, "little/no visible normal at distance" |
| T2 | Mountain slope | "Mountain slopes." "Much more vertical." | DGM1 slope 15-45 % | Stone: forest-mass rule (V7) applies above the treeline parameter. Varies: treeline height, rock exposure % | one slope material blend: grass→rock by slope, no splat painting |
| T3 | Cliff / rock face | "Cliffs." "Grey rock faces." | DGM1 slope > 45 % or `natural=cliff|bare_rock` | Stone: rock material rule. Varies: rock palette ("beige / grey"; Eifel: grey slate) | "photographic diffuse, low-frequency normal" |
| T4 | Valley floor | "Valleys." | DGM1 local minima; `waterway=river|stream` for the thread | Stone: a river is a T8 strip. Varies: meadow vs field | flat, bright: the "bright clearing" of the Schwarzwald rhythm |
| T5 | Embankment | "Road embankments." | derived at R12 | see R12 | see R12 |
| T6 | Forest wall | "dark forest walls made from layered vegetation cards" | `landuse=forest` / `natural=wood` polygon edge within 60 m of a road | Stone: wall construction (V4 cards, 2-3 layers, 12-18 m tall). Varies: species tint (Eifel: spruce blue-green + beech) | "large masses of deep green and almost black" |
| T7 | Field / meadow plane | "Fields." "large stretches where there simply isn't much there" | `landuse=farmland|meadow|grass` | Stone: nothing. Varies: patch tint per polygon (2-3 tints), hedge (V5) on boundaries where `barrier=hedge` | one 1024 tile per tint; no crop rows |
| T8 | Water plane | "A large blue plane with simple animated normals and specular reflection" | `natural=water`, `waterway=riverbank`, coast `natural=coastline` | Stone: the plane shader (one, canon-specified). Varies: colour ("deep blue" sea; river grey-green) | flat quad, animated normal, specular |
| T9 | Distant ridge | "Large distant mountains can remain visible for kilometres while possessing almost no fine detail." | DGM1 200 m lattice beyond 2 km; SRTM-30 beyond the state's DGM1 coverage | Stone: haze table S5 applied by distance. Varies: nothing | "very few polygons because its silhouette is what matters" |

## 3. PRIORITY 3 — THE CAR (not a library element)

The car is not in this library: "The Porsche should receive disproportionately more visual fidelity
than everything surrounding it." Its pipeline is the Blender car pipeline (synthesis §4 sequence 7).
The library's only obligation to it is negative: nothing here may compete with it. Palette rule:
environment "restrained" saturation, "Porsche strong clean color". The library's materials are
capped: no environment albedo above ~0.6 luminance except paint on road signs and kerbs.

## 4. PRIORITY 4 — LIGHTING / ATMOSPHERE (sky and light)

Canon: "1 directional sun / 1 environment/sky contribution / distance fog / very restrained ambient
illumination." A region picks a *set* of these; the set is data, the elements are shared.

| ID | Element | Canon line | Data | Stone / Varies | 2000 look |
|---|---|---|---|---|---|
| S1 | Clear day | "sunny: slightly warm highlights / neutral midtones / cool distant landscape" | region time-of-day parameter; sun azimuth from real latitude | Stone: one sun, one sky, shadow "clearly readable but not pitch black". Varies: sun elevation/warmth | photographic skybox ("Blue sky with soft clouds"), no procedural atmosphere |
| S2 | Overcast | "overcast: grey-blue ambient / very soft shadows / moderately desaturated vegetation" | region weather set | Stone: shadow softness. Varies: cloud plate | second skybox plate |
| S3 | Sunset / morning | "mountain mornings"; "Orange sunset." | region set | Stone: low sun long shadows. Varies: hue | third plate |
| S4 | Night | "deep blue/black environment / orange/yellow artificial lights / small pools of illumination" | region set; F8 lamps | Stone: lamp pool radius. Varies: lamp warmth | fourth plate; emissive quads |
| S5 | Distance haze | "0–100 m normal saturation / 100–300 m slight haze / 300–800 m reduced contrast / 800 m+ increasingly sky-colored" | fixed table | Stone: the table (it is the canon). Varies: haze colour = the sky plate's horizon colour | Godot depth fog with the four-band curve; "Not volumetric cinematic fog" |
| S6 | Rain (Autobahn family) | "darkened asphalt / simple rain streaks / grey sky / slightly reduced visibility / car reflections on road" | region weather set | Stone: wet-road material variant of R-textures. Varies: intensity | DEFERRED past the Ring (the Ring is dry at first focus) |

## 5. PRIORITY 5 — LANDMARKS AND TYPED BUILDINGS

Canon construction for every building: "rectangular plaster volume + simple pitched roof + chimney
+ window/door textures + perhaps 2–3 geometric details" and "Buildings: diffuse texture carries most
architectural information". The economy types (E) are *the same generic shells* with a privilege
record attached: the driver's verdict, "abstract buildings with privileges" (synthesis §8.1). No
interior in 4B (deferred).

### Generic shells (B)
| ID | Shell | Canon line | Data | Stone / Varies | 2000 look |
|---|---|---|---|---|---|
| B0 | House | the recipe above | `building=house|residential|yes` footprint; `building:levels`, `roof:shape` when tagged | Stone: box + pitched roof + chimney. Varies: plaster tint ("cream / white / pale ochre"; Eifel: white render + slate-grey roofs), roof pitch, window texture set | ≤ 60 tris, 512 texture |
| B1 | Barn / farmhouse | "occasional farmhouses and barns" | `building=barn|farm|farm_auxiliary` | Stone: long box, low pitch, big door texture. Varies: timber vs stone | one 512 texture |
| B2 | Church | "church" in the village list | `amenity=place_of_worship` + `building=church`; tower from `height`/levels | Stone: nave box + tower + spire. Varies: spire shape (Eifel: slate onion or pointed) | 512-1024 texture; "important building" budget |
| B3 | Castle ruin | "Large architectural landmarks" | `historic=castle` (Nürburg: OSM way 31010481 "Nürburg (Ruine)", live 2026-09-23) | Stone: keep tower silhouette from the footprint, height from `height` or 20 m default. Varies: nothing for a landmark: it is placed by hand once | the canon's "pale stone village sits farther down the valley" landmark logic; 1024 texture |
| B4 | Grandstand | Ring landmark ("T13 grandstand (highest point)") | `building=grandstand` (12 in the bbox) | Stone: tiered box + roof plane. Varies: nothing | flat seat texture; no seats |
| B5 | Warehouse / shed | "Warehouses." "Large simple structures are preferable to thousands of props." | `building=industrial|warehouse`, `landuse=industrial` (16 polygons in the bbox) | Stone: box + shallow roof. Varies: cladding tint ("grey / rust / dirty beige") | one 512 corrugated texture |
| B6 | Fuel canopy | the shell of E2 | `amenity=fuel` footprint or default 12 × 8 m | Stone: flat canopy on 4 posts + kiosk box. Varies: canopy colour band (no real brands: "no trademarks") | 4 posts, 1 slab, 1 box |
| B7 | Workshop hall | the shell of E1/E5/E6/E12 | `shop=car_repair` footprint or default 15 × 10 m | Stone: B5 with a roller-door texture. Varies: tint, sign | as B5 |
| B8 | Showroom | the shell of E3/E4 | `shop=car` footprint or default 20 × 12 m | Stone: glass front (dark glass, "dark blue-grey tint") on a B5 box. Varies: tint | the car inside is the product photograph: the showroom exists to frame it |
| B9 | Office / booth | the shell of E8/E11 | `amenity=driving_school`, or placed by rule | Stone: B0 without the chimney, a sign. Varies: tint | as B0 |
| B10 | Gantry bridge (teleport) | E13's shell; "the bridge should bifurcate in a tree shape road like chosing the gate of your departure" (user-thoughts-economy.org line 19) | placed by rule at a coastline/land-end road (`natural=coastline` ∩ `highway=*` end) | Stone: R10 deck fanning into N gates (tree shape), a B9 booth per gate. Varies: N gates | a bridge with a fan; "toll infrastructure" look |

### Economy buildings (E) — shell + privileges
Every E-entry is `{shell: B-id, privileges: set, demand: set, owner: none|driver|npc}`. Privileges
are the driver's rule set (synthesis §8.1): "not every workshop can sell fuel"; "gas stations are
RARE"; "dealerships troc cars and everything else"; "the cat sanctuary is a place". The privilege
vocabulary (proposed, to be put in stone in 4B-5): `sell_fuel`, `sell_tuna`, `buy_cars`,
`sell_cars`, `build_cars`, `build_components`, `repair`, `tyres`, `salvage`, `exam`, `ring_booking`,
`telemetry_desk`, `adopt_cat`, `rescue_cat`, `teleport`, `store_bulk_fuel`, `rent_car`.

| ID | Type | What / privileges | Data (placement) | Rarity rule | Canon judgment |
|---|---|---|---|---|---|
| E1 | Workshop (startup) | B7; `build_cars build_components repair`; may hold ANY other privilege by troc: "they are the startups that create everything that is needed" | `shop=car_repair` (9 in the bbox) + `craft=*` | every tagged one exists; capacity by footprint area | a shed by the road: "low-density industrial realism" |
| E2 | Gas station | B6; `sell_fuel`; 10 % also `sell_tuna` + free fuel (SOCIAL); others cat-required | `amenity=fuel` (9 in the bbox) | "gas stations are RARE": no station is invented; only tagged ones; social = round(0.1 × n) chosen deterministically (seeded by OSM id; ring-region-decisions.md §4) | canopy + kiosk, no brand |
| E3 | Dealership, Porsche | B8; `sell_cars buy_cars rent_car` + "everything else" | `shop=car` + `brand=Porsche`, or `shop=car_repair brand=Porsche` (Meuspath, way 1182024168) → promoted by the region table | rare: one per region at most | the showroom frames "an immaculate Porsche" |
| E4 | Dealership, General | B8; as E3 for serial-number cars; `rent_car` (the first-run rental) | `shop=car` (Adenau, way 831174023, brand Nissan → unbranded in game) | "a normal distribution density" (user-thoughts-economy.org line 76) | as E3 |
| E5 | Garage | B7; `repair` + storage of the driver's cars | `amenity=parking` + `building=garage(s)` or by rule near villages | common | a box with doors |
| E6 | Tyre centre | B7; `tyres` (compounds, retreading) | `shop=tyres` (0 in the bbox → 1 placed by rule at the industrial estate) | one per region | as B7 |
| E7 | Scrapyard | fenced B5 yard; `salvage` | `landuse=industrial` + `industrial=scrap_yard`, else by rule | one per region | "fence" + wrecks as 3 props max |
| E8 | Test centre | B9 + a yard = the pad's licence course elements; `exam` | `amenity=driving_school` (Fahrschule Hecken, way 667524970) + rule: one per region on flat ground (DGM1 slope < 1.5 %, the pad's MAX_SLOPE) | one per region minimum: it is the first-run entry | the yard is the existing pad's course, relocated |
| E9 | Cat sanctuary | B0 + a walled yard; `adopt_cat rescue_cat sell_tuna` | `amenity=animal_shelter` (0 in the bbox → placed by rule; rationale in ring-region-decisions.md §4) | one per region | "a stone wall, a few trees" |
| E10 | Fuel depot | B5 + tanks; `store_bulk_fuel` (supplies E2 by jobs) | `man_made=storage_tank` / `industrial=oil` else by rule | one per 2-3 regions | cylinders + a fence |
| E11 | Proving-ground office | B9; `ring_booking telemetry_desk` | at R18 (the Nordschleife entrance) | one: the Ring's | booth + barrier |
| E12 | Component shop | B7; `build_components` only (brake/suspension/electrical specialist) | `shop=car_parts` else by rule | 1-2 per region | as B7 |
| E13 | Teleport car bridge | B10; `teleport`; own demand (goods + services) | coast/land-end rule | few: continent-level | the fan bridge |
| E14 | Abstract building with privileges | any shell; the privilege record alone | any `building=*` the region table names | the driver's addition: the schema itself is the element | nothing extra to draw |

## 6. PRIORITY 6 — VEGETATION MASSES

Canon: "Don't use modern SpeedTree-quality vegetation." "simple trunks / crossed foliage cards /
billboard foliage / chunky low-poly crowns / several repeated tree archetypes / dark forest walls
made from layered vegetation cards".

| ID | Archetype | Canon line | Data | Stone / Varies | 2000 look |
|---|---|---|---|---|---|
| V1 | Broadleaf, near road (beech/oak) | "chunky low-poly crowns" | `natural=tree` nodes; `landuse=forest` edge sampling; `leaf_type=broadleaved` | Stone: trunk cylinder + 3-lobe crown. Varies: tint, height 8-18 m | ≤ 120 tris, 256-512 card |
| V2 | Conifer, near road (spruce) | "Dark pine forests." | `leaf_type=needleleaved` / Eifel default | Stone: trunk + 3 crossed cards. Varies: tint, height 12-25 m | crossed cards |
| V3 | Billboard tree, mid distance | "billboard foliage" | any tree beyond 80 m | Stone: 2 crossed cards. Varies: as V1/V2 | 4 tris |
| V4 | Forest wall card | "dark forest walls made from layered vegetation cards" | `landuse=forest` / `natural=wood` polygon edges | Stone: 3 layers, 12-18 m, staggered. Varies: tint (Eifel: blue-green spruce over beech) | "deep green and almost black" |
| V5 | Hedge row | "Hedges." "Stone walls." | `barrier=hedge`; field boundaries in the Rural France family (region parameter, off in the Eifel) | Stone: box + card top. Varies: height 1-2 m, on/off | a textured box |
| V6 | Avenue / tree line | "sparse telephone poles, clusters of trees" | `natural=tree_row` | Stone: V1 at OSM spacing. Varies: species | instances |
| V7 | Forest mass (interior) | "Forests should often become large masses of deep green and almost black" | `landuse=forest` polygon interior | Stone: interior is a dark canopy plane on the terrain (no trees inside beyond 60 m of a road). Varies: tint | a tinted terrain material + V4 at the edge: the interior is never modelled |
| V8 | Scrub / dry vegetation | "Sparse dry vegetation." (Mediterranean) | `natural=scrub|heath` | Stone: low cards. Varies: tint | DEFERRED past the Ring |

## 7. PRIORITY 7 — ROAD FURNITURE

Canon: "A guardrail needs enough geometry to trace the road." "Guardrails catch little white
highlights." Density ceiling: the canon's "twenty meaningful objects".

| ID | Prop | Canon line | Data | Stone / Varies | 2000 look |
|---|---|---|---|---|---|
| F1 | Guardrail (Armco) | "Guardrails catch little white highlights." | `barrier=guard_rail`; R17 both sides; B-roads on the fill side where DGM1 cross-slope > 20 % | Stone: W-beam profile, posts every 4 m, follows the road spline. Varies: rail tint (galvanised) | ≤ 8 tris per 4 m; "strong specular" like the car? No: "little white highlights" only |
| F2 | Stone wall | "low stone walls" | `barrier=wall`, `barrier=retaining_wall`; R3 outside in villages | Stone: 1.0 × 0.5 m box strip. Varies: stone texture (Eifel: grey slate) | box + 512 texture |
| F3 | Wooden fence | "wooden fences" | `barrier=fence` (+ `fence_type=wood`) | Stone: posts + 2 rails as cards. Varies: on/off by region | cards |
| F4 | Telephone / power pole | "sparse telephone poles" | `power=pole|line`, `man_made=utility_pole`; spacing from OSM nodes, else 50 m along R1 in rural families | Stone: pole + crossarm; wires as 1-px lines optional. Varies: density (0 in villages) | a cylinder |
| F5 | Direction sign | "Large road signs." (Autobahn) / village name signs | `highway=*` junction nodes with `destination=*`; `traffic_sign=city_limit` | Stone: DE yellow board (village names from OSM `name`) | a textured quad on a post |
| F6 | Warning / regulatory sign | as F5 | `traffic_sign=*` nodes; `highway=stop|give_way`; `maxspeed=*` changes | Stone: DE sign set as one 512 atlas. Varies: which country's atlas | a quad |
| F7 | Cone | the pad's cone (test_pad.gd builds it today) | placed by E8 yards and the pad | Stone: the pad's cone as it is. Varies: nothing | reused |
| F8 | Lamp / floodlight | "orange/yellow artificial lights / small pools of illumination" | `highway=street_lamp`; E-yards get 2 floodlights | Stone: pole + emissive head + a light with 12 m radius. Varies: warmth | one emissive quad + one OmniLight |
| F9 | Delineator post | roadside markers on B-roads | rule: every 50 m on R1/R2 outside villages (DE Leitpfosten) | Stone: 1 m post, reflector quad. Varies: on/off | 2 quads |
| F10 | Distance board | the pad's 100 m boards | rule: R17 gets the Ring's own km boards | Stone: the pad's board. Varies: nothing | reused |
| F11 | Bridge parapet | "Industrial roads pass underneath structures" | with R10 | Stone: parapet strip. Varies: material | a strip |
| F12 | Tunnel portal | "a convincing entrance silhouette" | with R11 | Stone: arch/box face 2 m thick. Varies: face texture | one extruded face |
| F13 | Concrete barrier | "Concrete." (Autobahn) | `barrier=jersey_barrier`; R13 median | Stone: profile strip. Varies: nothing | a strip |
| F14 | Tyre wall / catch fence | Ring-specific | `barrier=*` on raceway margins; else rule at R17 run-off | Stone: a box strip with a tyre texture. Varies: nothing | a strip; no individual tyres |
| F15 | Parked car (scenery) | "few parked cars" | rule in R15: 0-3 per 100 m | Stone: a low-detail unbranded box car (NOT the hero model). Varies: count | the canon's contrast rule: it must look worse than the hero |

## 8. PRIORITY 8-9 — WHAT IS NOT IN THE LIBRARY

By the canon's "Environmental storytelling: Almost none." these are excluded: crates, newspapers,
graffiti, garbage, lore objects, per-leaf vegetation, roof-tile geometry, "modern micro-displacement",
sponsor boards, neon, "XP notifications" on signs. A region table cannot add them; adding a prop
means adding a library entry here with its canon line.

## Open questions
1. OSM `width=5` on 22 of the Nordschleife's 52 ways contradicts the recorded 8-9 m: which wins
   for R17? Proposal: the recorded track data (docs/nordschleife-data-sources.md §4) with DOP20
   orthophoto verification (same OpenData catalogue), OSM width ignored on `highway=raceway`.
2. Cross-section widths by `highway=*` class without a `width=*` tag: the defaults in
   data-pipeline.md §4 are German road-design values, not measured; to be checked against DOP20.
3. The privilege vocabulary (E-table) is proposed here and must be put in stone in 4B-5; the
   driver may want fewer, coarser privileges.
4. Cat sanctuary shell: B0 + yard is a guess; the driver may want it recognisable from the road.
5. The hero-car contrast rule (§3 luminance cap ~0.6) is a number picked for the doc, not measured.
