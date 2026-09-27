# Telemetry Analysis – 2024‑09‑24 Full‑Run

## 1. Sessions inventory

| Session ID | Start time (UTC) | Duration (s) | Distance (m) |
|------------|------------------|--------------|--------------|
| 100 | 2026‑09‑23T17:43:25 | 2.5 | 0.000 |
| 101 | 2026‑09‑23T17:48:16 | 3.5 | 0.000 |
| 102 | 2026‑09‑23T18:56:45 | 3.5 | 0.000 |
| 103 | 2026‑09‑23T19:45:34 | 1.5 | 0.000 |
| 104 | 2026‑09‑23T20:03:35 | 3.0 | 0.000 |
| 105 | 2026‑09‑23T20:08:02 | 0.5 | 0.000 |
| 106 | 2026‑09‑23T20:14:50 | 1.5 | 0.000 |
| 107 | 2026‑09‑23T20:15:38 | 1.0 | 0.000 |
| 108 | 2026‑09‑23T20:22:04 | 4.0 | 0.000 |
| 109 | 2026‑09‑23T21:49:22 | 7.5 | 0.000 |
| 110 | 2026‑09‑23T22:41:10 | 3.5 | 9.717 |
| 111 | 2026‑09‑23T22:46:25 | 1.5 | 0.000 |
| 112 | 2026‑09‑23T23:19:23 | 4.5 | 0.000 |
| 113 | 2026‑09‑23T23:38:38 | 3.0 | 0.000 |
| 114 | 2026‑09‑24T05:37:37 | 1.5 | 0.000 |
| 115 | 2026‑09‑24T08:08:12 | 5.0 | 17.057 |
| 116 | 2026‑09‑24T08:56:21 | 10.0 | 19.744 |
| 117 | 2026‑09‑24T08:58:11 | 1.5 | 0.000 |
| 118 | 2026‑09‑24T09:13:42 | 1.0 | 0.000 |
| 119 | 2026‑09‑24T10:07:17 | 2.5 | 0.000 |

*The script `analysis_telemetry.py` walked all `*.jsonl` files under the telemetry directory, summed Euclidean distances between successive `pos` vectors and reported the final `t_session_s` as the duration.  Empty‑distance sessions indicate the car never left the origin (e.g. idle or aborted runs).*

## 2. Reset analysis

The telemetry format includes an `event` field, but a search for `"event":"reset"` across all JSONL files returned **zero hits**.  Consequently we cannot enumerate explicit reset events, their world positions, or odometer readings.

Because the driver report mentions “resets + off‑track”, the resets are likely inferred from gameplay (e.g. the driver pressing the reset button) and are not recorded in the current telemetry dump.  Without a dedicated reset marker we cannot cluster worst spots or correlate them with the open issues (`issues.json` IDs 0001‑0023).  This section remains **incomplete** pending a telemetry schema update that records reset events.

## 3. Off‑track analysis

The telemetry records the vehicle’s 3‑D position (`pos`) and speed, but does not contain a surface‑type identifier (e.g. road vs off‑road).  Therefore we cannot directly compute:

* total time spent off the road,
* which surface types were traversed, or
* how the observed grip/drag compares to the `data/regions/eifel_ring/surfaces.json` table.

A possible proxy (e.g. checking altitude or distance from the road mesh) would require additional map data not available in the current analysis environment.

## 4. Worst stuck / reset spots (tentative)

Given the lack of explicit reset or off‑track markers, we cannot produce a reliable list of the “5‑10 worst spots”.  The only sessions with non‑zero distance are 110, 115, and 116; their trajectories are short and do not reveal obvious sticking points.  Should reset data become available, a clustering pass on the recorded positions would generate a ranked list.

---

*Note*: The analysis is based on the telemetry bundle `fd‑datadir‑2026‑09‑24‑1.zip` unpacked under `.scratch/zip-0924/unzip`.  No repository files were modified or committed.

## 5. Schema update (2026‑09‑27): the surface class and the reset event

The two gaps §2 and §3 name are closed in the recorder (`scripts/telemetry.gd`,
its header *THE SURFACE AND THE RESET*; `car.gd` untouched). Files written from
this date on carry:

* **Per‑sample surface class.** Where the scene has a `Surfaces` node
  (`scripts/surfaces.gd`, the Ring) every sample line carries two extra keys,
  `"front_surface"` and `"rear_surface"`, plain strings from the surfaces table's
  names: `road`, `gravel`, `grass`, `field_stubble`, `forest_floor` (the axle's
  lower‑grip wheel, as the node classified it that tick). A scene without the
  node (the pad, the garage, the world map) writes neither key – they are omitted,
  never `null`. A Ring sample measures ~375 bytes with them (was ~330; the pad's
  ~309 unchanged), inside the suite's 200–450 band.
* **Reset events.** A car whose position moved by more than 5 m between two
  consecutive samples of the same stream (a teleport: R, a spawn, a test's
  `reset_to`; no drive covers 5 m in a 60 Hz tick) writes one event line right
  after the sample that landed:

  ```json
  {"event": "reset", "t": 12.35,
   "before": {"pos": [x, y, z], "odometer": 1234.567},
   "after":  {"pos": [x, y, z], "odometer": 1234.567}}
  ```

  `t` is the landing sample's `t_session_s`; `before` is the previous sample's
  position and the car's odometer then, `after` the landing sample's own. The
  odometer does not count a teleport (`reset_to` re‑bases it), so the pair reads
  alike – which is what tells a reset from a drive. The memory is per stream: a
  mission's file starts fresh (its first sample is the car *placed* at the start
  point, not a reset) and the free file resumes fresh after a run (the run's whole
  drive lies between its two samples).

For the analysis path: `analysis_telemetry.py`'s distance sum must skip event
lines (it already skips `session_start`; a `reset` line has no `pos` at the top
level) and must *not* add the jump between the samples around a reset – the
`before`/`after` pair marks exactly where to cut. The off‑track time of §3 is the
count of samples whose `front_surface` or `rear_surface` is not `road`, times
1/60 s; the worst spots of §4 cluster on the `before.pos` of the reset events.
The fence is `tests/telemetry_watch_test.gd` (the two scenes, the fields present
or absent, one event per jump with the before/after data to the snap).
