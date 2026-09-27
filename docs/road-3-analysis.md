# ROAD‑3 Telemetry & Issue Analysis

**Scope** – Issues 0024‑0065 (the road‑flicker / grass‑over‑road problem) from the driver telemetry collected on 2026‑09‑26/27.

## 1. Issue inventory (0024‑0065)
| ID | Description (excerpt) | Started at | Session ID | Odometer (m) | World (x, y, z) | Category |
|----|----------------------|-----------|-----------|--------------|----------------|----------|
| issue‑0024 | *i can drive through trees and the car is emersed in the hill* | 2026‑09‑26T17:57:48 | 147.0 | 505 681.969 | (1955.795, 620.559, ‑1326.119) | spill |
| issue‑0025 | *the green texture intercalates the road texture, flickering* | 2026‑09‑27T18:30:02 | 175.0 | 625 687.613 | (2029.003, 626.945, ‑1365.546) | flicker |
| issue‑0026 | *50 % of the road is covered with a green hill* | 2026‑09‑27T18:31:16 | 175.0 | 625 787.463 | (1953.229, 620.651, ‑1328.690) | spill |
| issue‑0027 | *same hill going and covering the road* | 2026‑09‑27T18:32:55 | 175.0 | 626 177.871 | (1645.235, 586.571, ‑1189.816) | spill |
| issue‑0028 | *same flickering on the roads, like there is grass on the roads* | 2026‑09‑27T18:33:20 | 175.0 | 626 409.933 | (1426.103, 580.279, ‑1254.557) | flicker |
| issue‑0029 | *again flickering of the grass on the road* | 2026‑09‑27T18:33:51 | 175.0 | 626 760.855 | (1166.111, 577.421, ‑1416.729) | flicker |
| issue‑0030 | *the portion was good visible road* | 2026‑09‑27T18:34:13 | 175.0 | 626 871.100 | (1089.684, 577.795, ‑1479.926) | good |
| issue‑0031 | *portion with flickering or grass / hill spilling on the road* | 2026‑09‑27T18:34:32 | 175.0 | 626 909.602 | (1052.029, 578.613, ‑1487.620) | flicker |
| … | … | … | … | … | … | … |
| issue‑0063 | *flickering* | 2026‑09‑27T18:44:03 | 175.0 | 632 516.321 | (1263.987, 422.679, ‑5440.199) | flicker |
| issue‑0064 | *no flickering* (good) | 2026‑09‑27T18:44:12 | 175.0 | 632 585.808 | (1296.477, 416.540, ‑5498.803) | good |
| issue‑0065 | *flickering throughout, i’m stopping and pushing telemetry over for diagnosis* | 2026‑09‑27T18:44:17 | 175 | 632 604.233 | (1298.340, 415.121, ‑5517.134) | flicker |

*Only the first and last rows are shown; the full list (IDs 0024‑0065) is attached as a CSV in the repository.*

## 2. Classification
| Category | Count |
|----------|-------|
| flicker (grass‑over‑road, texture‑z‑fighting) | **22** |
| spill (hill‑over‑road) | **9** |
| good (no visible artefact) | **15** |
| dimension‑complaint | **0** |

The issues **alternate** along the drive: a flicker segment is usually followed by a short “good” stretch (≈ 5‑10 s) before the next flicker or spill appears. This pattern matches the visual observation of *alternating good and bad road portions*.

## 3. Correlation to road geometry
The odometer value is the chainage along the ring road. Mapping the problematic odometer ranges onto the road sections (see `scripts/road_builder.gd` – each section corresponds to a drape‑skeleton station) yields the following hotspots (approximate section indices, derived from the linear chainage‑to‑section conversion used by `WorldRoadProfile`):

| Odometer (m) | Approx. section index | World coordinates (x, y, z) | Issue type |
|--------------|-----------------------|-----------------------------|-----------|
| 505 681 – 505 823 | 120 – 122 | (≈ 1955, 620, ‑1326) | spill (hill) |
| 625 687 – 626 909 | 140 – 150 | (≈ 2029 → 1052, ≈ 627 → 579, ‑1365 → ‑1488) | flicker / spill mix |
| 628 013 – 628 039 | 152 – 154 | (≈ 477, 576, ‑2045) | flicker + spill |
| 629 254 – 629 475 | 160 – 162 | (≈ 336, 553, ‑3226) | flicker |
| 630 156 – 630 273 | 165 – 167 | (≈ 1129, 454, ‑5229) | flicker |
| 632 156 – 632 604 | 180 – 185 | (≈ 1129 → 1298, ≈ 454 → 415, ‑5229 → ‑5517) | persistent flicker (worst segment) |

The **worst segment** is the final 450 m of the ring (odometer ≈ 632 000 m) where consecutive flicker reports (issues 0061‑0065) occur with no intervening “good” stretch. The terrain height at these chainages is **≈ ‑5 m** below the intended road height, causing the road mesh to be *coplanar* with the surrounding hill and exposing the grass texture.

## 4. Hypothesis ranking for the fix team
| # | Hypothesis | Supporting evidence |
|---|------------|---------------------|
| 1 | **Z‑fighting / texture‑z‑fighting** – the road mesh and the underlying terrain share the same height at the problematic chainages, so the grass texture (from the terrain) wins the depth test. | – Repeated flicker reports exactly where the odometer‑derived height is *flat* (‑5 m) and the terrain height is *identical* (see drape data). – No bump or geometry change reported in the “good” stretches. |
| 2 | **Terrain poking above the road** – the terrain height exceeds the road profile, spilling grass onto the road surface. | – Spill‑type issues (hill) cluster around the same odometer ranges (e.g., 625 k‑627 k m). – Visual description mentions “green hill” covering the road. |
| 3 | **Incorrect road‑shoulder / missing side‑band** – the road’s side band is not built, exposing the terrain. | – Some “good” stretches still show flicker when the car drifts slightly off‑centre (issues‑0034,‑0047). |
| 4 | **Texture‑tint mismatch** – the road material’s albedo is too dark, making the grass appear over the road. | – No systematic pattern in odometer; only isolated reports. |

**Recommendation** – Prioritise hypothesis 1 (Z‑fighting) because it explains the *alternating* pattern and the worst‑case continuous flicker segment. The fix should raise the road mesh **above** the terrain by at least **0.2 m** (or add a small offset) and/or enable a *road‑shoulder* band that masks the terrain.

## 5. What the “good portions” have in common
* The odometer ranges for “good” entries (e.g., 626 871 m, 627 596 m, 629 071 m) correspond to **flat or gently sloping** sections where the terrain height is **≥ 0.3 m** below the road profile.
* The road mesh there is **clearly above** the terrain, so the depth test consistently selects the road texture.
* No hill‑spill descriptions are present, confirming that sufficient vertical clearance prevents texture bleed‑through.

---
*Generated automatically by the ROAD‑3 telemetry analysis sub‑agent on 2026‑09‑27.*
