# FACTORY DRIVER — ART DIRECTION CANON (verbatim user brief, 2026-09-22 ~16:00)
# Provenance: the driver's own words, delivered as "the above is the aesthetics we're aiming for".
# Status: canon. Every world/asset/UI brief from 4B on carries this file as its visual contract.
# Do not edit the text below; add iteration notes separately.

If I were giving an agentic Godot/Blender developer a **visual art-direction brief** for something meant to evoke the *PC version* of *Need for Speed: Porsche Unleashed / Porsche 2000* (2000), I would describe it like this.

The important thing is **not merely "make it look like a game from 2000."** Porsche Unleashed had a particularly restrained aesthetic: European automotive photography translated into early real-time 3D. Contemporary reviews specifically praised its subtle lighting, lush scenery, open-road European environments, detailed cars, alternate routes, docks at night, mountain roads in the morning, and unusually classy menus.

### Overall visual identity

Think:

**1998–2001 European car brochure + slightly romantic travel photography + early hardware-accelerated PC graphics.**

The world should feel realistic, but **quietly idealized rather than cinematic**.

Avoid modern racing-game aesthetics: no aggressive HDR, no enormous lens flares, no teal/orange grading, no excessive bloom, no hyper-detailed asphalt, no giant particles, no dramatic volumetric fog everywhere.

Instead:

> clean air, slightly desaturated natural colors, soft sunlight, simple geometry, long roads, modest European architecture, dark forests, distant mountains and an immaculate Porsche occupying the visual center of everything.

There is an almost **lonely Sunday-drive quality** to it.

The environments aren't trying to overwhelm the player. They exist to make the car look beautiful.

---

## The Blender environment language

Build environments from **large, simple shapes with photographic-looking textures doing much of the work**.

Geometry should actually be relatively economical.

A Normandy-style scene might contain a narrow two-lane asphalt road, rolling green terrain, low stone walls, hedges, wooden fences, occasional farmhouses and barns, sparse telephone poles, clusters of trees and large stretches where there simply isn't much there.

That countryside-road imagery is directly characteristic of the game.

Don't model every roof tile, brick or branch.

A house could essentially be:

```text
rectangular plaster volume
+ simple pitched roof
+ chimney
+ window/door textures
+ perhaps 2–3 geometric details
```

The textures provide age and character.

This creates an important part of the Porsche 2000 look: **recognizable reality represented economically.**

### Trees

Trees are especially important.

Don't use modern SpeedTree-quality vegetation.

Use combinations of:

- simple trunks
- crossed foliage cards / billboard foliage
- chunky low-poly crowns
- several repeated tree archetypes
- dark forest walls made from layered vegetation cards

Forests should often become large masses of **deep green and almost black**, rather than thousands of individually readable leaves.

The road consequently becomes a bright ribbon cutting through darker scenery.

---

## Terrain

Terrain should have broad, readable forms.

Rolling hills.

Mountain slopes.

Cliffs.

Valleys.

Road embankments.

Avoid modern micro-displacement everywhere.

At driving speed the player should perceive:

```text
ROAD
grass shoulder
tree line
mountain
sky
```

rather than millions of tiny environmental details.

The silhouette matters considerably more than surface complexity.

---

## The road is the composition

This is probably the single most important principle.

The game's environments are fundamentally composed **around the road**.

The road continually creates strong perspective:

```text
            mountain

        /             \
       /               \
------                   ------
          \         /
           \       /
            \_____/
```

Long curves disappear behind hills.

Roads descend toward villages.

Mountain roads enter tunnels.

Coastal roads expose the sea.

Industrial roads pass underneath structures.

The player should frequently see **100–500 metres of road composition ahead**.

Some tracks also had alternate routes, which helps produce that open-road feeling rather than the impression of driving around an artificial racing arena.

---

# Track/environment families

Don't make every level stylistically identical.

The PC game moved between distinctly European environments including countryside, mountains, coastlines, forests, Autobahn and industrial districts. Contemporary screenshots specifically show Normandy, Monte Carlo, the Alps, industrial docks, Corsica, Côte d'Azur and Autobahn environments.

### Rural France

Warm green.

Grey asphalt.

Beige stone.

Small villages.

Fields.

Hedges.

Stone walls.

Occasional barns.

Large cloudy blue sky.

It should resemble driving through an old European postcard.

### Alps

Much more vertical.

Grey rock faces.

Dark pine forests.

Small alpine houses.

Tunnels cut directly into mountains.

Snow-covered distant peaks.

The nearby environment remains green while distant mountains become blue-grey.

Use **distance haze aggressively**.

Not volumetric cinematic fog—just simple atmospheric perspective:

```text
foreground = high contrast
midground = slightly washed out
mountains = blue/grey
far mountains = nearly sky colored
```

That is extremely characteristic of graphics from this period.

### Mediterranean / Corsica / Côte d'Azur

Warm beige rock.

Pale roads.

Deep blue sea.

Sparse dry vegetation.

White or ochre buildings.

Cliffs.

Small tunnels.

Boats/ferries far below.

Bright sunlight.

The game's Corsica imagery included mountain tunnels and broad seaside views, while Côte d'Azur scenes exposed coastline, boats and ferries.

The sea doesn't need sophisticated simulation.

A large blue plane with simple animated normals and specular reflection would actually fit better.

### Schwarzwald / forest roads

Dark.

Dense.

Cool green.

Tall trees.

Road surfaces become relatively neutral grey.

Sunlight occasionally penetrates through openings.

This creates strong alternation:

**dark forest → bright clearing → dark forest → village.**

### Autobahn

Wide road.

Concrete.

Guardrails.

Large road signs.

Tunnels.

Underpasses.

Intersections.

Toll infrastructure.

Rain.

The game's Autobahn course specifically ran in rainy conditions through tunnels, intersections, an underpass and tollbooth structures.

Here the visual appeal comes from **wet grey infrastructure contrasted with the glossy car.**

### Industrial district

Steel.

Concrete.

Warehouses.

Cranes.

Docks.

Foundry structures.

Overhead pipes.

Shipping areas.

Industrial lighting.

But again: **low-density industrial realism**, not Cyberpunk.

Large simple structures are preferable to thousands of props.

The original even let the road cut through docks and steel-foundry areas.

---

# Lighting

Lighting is understated.

For daytime scenes, start in Godot with essentially:

```text
1 directional sun
1 environment/sky contribution
distance fog
very restrained ambient illumination
```

Sun shadows should be clearly readable but not pitch black.

The image shouldn't have modern PBR contrast.

Aim for something closer to:

```text
sunny:
slightly warm highlights
neutral midtones
cool distant landscape

overcast:
grey-blue ambient
very soft shadows
moderately desaturated vegetation

night:
deep blue/black environment
orange/yellow artificial lights
small pools of illumination
```

The original was particularly admired for subtle lighting changes between things such as mountain mornings and nighttime docks.

---

# Materials

This is where a modern recreation can easily become **too beautiful**.

Keep environment materials simple.

Asphalt:

```text
diffuse/albedo texture
subtle normal
very mild roughness variation
```

Grass:

```text
mostly diffuse
little/no visible normal at distance
```

Stone:

```text
photographic diffuse
low-frequency normal
```

Buildings:

```text
diffuse texture carries most architectural information
minimal physically accurate material complexity
```

You want surfaces to read almost immediately as:

**ROAD / ROCK / GRASS / PLASTER / METAL / WATER.**

Not as material-scanning demonstrations.

---

# The cars are different

The Porsche should receive disproportionately more visual fidelity than everything surrounding it.

That contrast is fundamental.

The original PC game already emphasized unusually detailed vehicle models for its time. Cars had working lights, visible interiors, animated drivers, damage and sunlight/streetlight reflections; garage presentation even allowed closer inspection of areas such as the engine, trunk and interior.

For Blender:

**Environment:** deliberately economical.

**Car:** lovingly modeled.

Model:

- correct Porsche silhouette
- proper wheel geometry
- wheel wells
- separate glass
- headlights
- taillights
- mirrors
- exhaust
- interior
- dashboard
- steering wheel
- seats
- visible driver
- suspension movement
- separate body panels where visually useful

But resist modern manufacturing-CAD density.

The silhouette and proportions matter more than tiny panel fasteners.

---

# Car paint

Paint should be glossy but relatively simple.

Don't reproduce modern multi-layer ray-traced automotive paint.

Think:

```text
strong specular
moderate roughness
simple environment reflection
bright sun highlight
dark reflection underneath body
```

The car should sometimes appear **almost unnaturally clean and shiny** against the softer environment.

That's desirable.

The contemporary GameSpot review specifically noticed cars shining in sunlight and reflecting street lamps at night.

---

# Windows

Use fairly dark glass.

Don't make physically perfect transparent glass.

The windshield can essentially be:

```text
dark blue-grey tint
moderate transparency
strong specular
simple environment reflection
```

The cabin remains visible, but slightly mysterious.

This helps maintain the recognizable early-2000s CGI-car appearance.

---

# Wheels

Wheels should visually rotate very clearly.

At speed introduce a simple rotational blur illusion.

Suspension motion should also be visible.

The body should:

```text
pitch under braking
squat under acceleration
roll during cornering
bounce slightly over uneven road
```

That movement actually contributes to the visual aesthetic because the original game's four-point suspension model made cars visibly lean and move independently over the road.

---

# Camera

The classic external camera should be relatively restrained.

Approximately:

```text
car occupies bottom-middle 20–30% of screen

camera 5–8 m behind
camera 1.5–2.5 m above ground
FOV roughly 55–70°
```

Don't use an ultra-wide modern action camera.

Don't shake constantly.

Don't aggressively zoom every time the car accelerates.

The sensation of speed should mostly come from:

**road texture + roadside objects + perspective + vehicle movement.**

The horizon should remain relatively stable.

This makes the experience feel like **driving**, rather than an action movie.

---

# Cockpit

The cockpit should feel slightly dark.

Dashboard dominates the lower frame.

Windshield dominates the upper frame.

Analog gauges.

Black leather/plastic.

Simple textured controls.

The road outside is considerably brighter.

Don't illuminate every interior control.

It should almost feel like you're looking out from a dark room into daylight.

The original supported a full 3D cockpit view and animated driver interactions, something quite striking for 2000.

---

# Weather

Rain is particularly useful for this aesthetic.

Don't turn it into a modern weather showcase.

Use:

```text
darkened asphalt
simple rain streaks
grey sky
slightly reduced visibility
car reflections on road
taillight reflections
occasional spray
```

The wet road should become noticeably more reflective.

That alone gives you a huge amount of the period look.

---

# Sky

The sky should be simple and beautiful.

A photographic skybox is arguably more appropriate than a sophisticated procedural atmosphere.

Blue sky with soft clouds.

Grey overcast.

Orange sunset.

Dark blue evening.

The sky often occupies a surprisingly large portion of the composition.

That is important because it gives the environment **space**.

---

# Draw distance

Do **not** hide everything behind thick fog like a PlayStation game.

Porsche Unleashed on PC often showed substantial landscape depth.

Instead use controlled atmospheric haze.

Something like:

```text
0–100 m      normal saturation
100–300 m    slight haze
300–800 m    reduced contrast
800 m+       increasingly sky-colored
```

Large distant mountains can remain visible for kilometres while possessing almost no fine detail.

---

# Texture philosophy

A modern developer might instinctively use 2K–4K PBR textures everywhere.

Don't.

For an intentional Porsche 2000-inspired look, something closer to:

```text
hero car: 1024–2048
important building: 512–1024
road: repeating 512/1024
terrain: 512/1024 tiled
props: 128–512
vegetation: 128–512
```

would produce a more coherent result.

Slightly blurry textures at oblique angles are **part of the visual language**.

Don't artificially add pixelation, though.

The target is not "retro PS1."

It is **optimistic early-3D PC realism.**

---

# Geometry philosophy

This distinction matters tremendously:

### Wrong

> Make everything visibly low-poly.

### Right

> Use the minimum geometry necessary to produce a convincing silhouette.

A mountain can contain very few polygons because its silhouette is what matters.

A Porsche needs considerably more because its curvature defines the object.

A building can be nearly a box.

A guardrail needs enough geometry to trace the road.

A tree can be mostly cards.

A tunnel needs a convincing entrance silhouette but doesn't require individually modeled concrete imperfections.

---

# Color palette

Keep saturation restrained.

Imagine roughly:

```text
vegetation     muted forest / olive greens
road           medium cool grey
rock           beige / grey
architecture   cream / white / pale ochre
sky            pale blue
water          deep blue
industrial     grey / rust / dirty beige

Porsche        strong clean color
```

That last part matters.

A **red, yellow, silver or blue Porsche should visually pop out of the landscape.**

The environment is supporting cast.

The automobile is the product photograph.

---

# UI aesthetic

The front end should feel like **premium late-1990s industrial design**, not contemporary game UI.

Think:

**Porsche brochure + Windows-era multimedia presentation + automotive showroom kiosk.**

Dark charcoal backgrounds.

Silver/grey interface surfaces.

Small white typography.

Thin lines.

Small rectangular buttons.

Occasional muted red accent.

Large areas of empty space.

Car photography/rendering as the visual focus.

Minimal animation.

No giant glowing tiles.

No gradients covering half the screen.

No mobile-app UI.

The contemporary review explicitly described the game's front-end menus as stylish and part of the overall "classy" presentation.

The garage should essentially look like an **interactive automobile catalogue**.

---

# HUD

Keep it sparse.

Speedometer/tachometer information should resemble instrumentation rather than esports UI.

Avoid:

```text
XP notifications
giant position graphics
combo counters
floating arrows
neon racing lines
screen-edge effects
constant popups
```

The player's attention should stay on:

**Porsche → road → landscape.**

---

# Environmental storytelling

Almost none.

That's another important difference from contemporary games.

Don't put crates, newspapers, graffiti, garbage, signs and lore objects every five metres.

A village can simply contain:

```text
8 houses
church
stone wall
few parked cars
trees
road signs
```

and that's enough.

An industrial district can simply contain:

```text
warehouse
crane
pipes
fence
dock
lights
```

The world isn't asking the player to investigate it.

It's scenery experienced at **120 km/h**.

---

# Blender → Godot asset rule

I'd give an autonomous asset-generation agent this priority hierarchy:

```text
1. ROAD SHAPE
2. LANDSCAPE SILHOUETTE
3. PORSCHE SILHOUETTE
4. LIGHTING / ATMOSPHERE
5. LARGE ARCHITECTURAL LANDMARKS
6. VEGETATION MASSES
7. ROAD FURNITURE
8. TEXTURE DETAIL
9. SMALL PROPS
```

If #1–4 are excellent, it will already evoke Porsche Unleashed.

If #1–4 are wrong, adding 50,000 beautifully modeled props won't rescue it.

---

# The most important instruction for the agent

I'd actually put this at the beginning of its art-direction prompt:

> **Do not recreate how the year 2000 literally looked. Recreate how developers in the year 2000 attempted to portray reality beautifully.**
>
> Environments are simplified representations of European roads, with economical geometry, photographic textures, billboard vegetation, long sightlines and gentle atmospheric haze. Cars receive dramatically more visual attention than scenery. Lighting is naturalistic and understated. Roads and landscape silhouettes create the composition. Architecture exists primarily as recognizable scenery encountered at driving speed.
>
> The resulting image should resemble an expensive European automobile advertisement rendered in real time on a high-end PC from approximately 2000—not pixel art, not PS1-style affine graphics, not modern photorealism, and not deliberately exaggerated "retro" graphics.

And aesthetically, the target screenshot in my head is:

**A silver 911 entering a long sweeping mountain curve.**

Dark pine trees frame the road.

A pale stone village sits farther down the valley.

Blue-grey mountains dissolve into atmospheric haze.

The asphalt is uncomplicated grey.

Guardrails catch little white highlights.

The Porsche is considerably sharper and glossier than everything around it.

The sky is pale blue with a photographic cloud layer.

There are maybe twenty meaningful objects visible rather than two thousand.

Nothing glows.

Nothing screams for attention.

Nothing looks post-apocalyptic or aggressively "racing."

It's simply **a beautiful car, a beautiful European road, and somewhere worth driving to.**

That's the essence of *Porsche 2000's* visual aesthetic.
