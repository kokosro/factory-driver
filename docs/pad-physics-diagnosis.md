# Pad Physics Diagnosis

## 1️⃣ 180° Wheel‑Stop Mechanism

The wheels appear to “stop” when the car’s heading reaches exactly 180° while the throttle is held full. The chain of code that produces this is:

- **Wheel‑along component** is computed in `scripts/car.gd`:
  - `var front_along := forward_speed * cos(wheel_angle) - front_lateral * sin(wheel_angle)`  _(line 4060)_
  - `var rear_along := forward_speed` (passed as `along` to rear contact)  _(line 4077)_
- **Drive‑force limiting** happens right after the tyre‑force is computed:
  - `if front_drive * front_along < 0.0:` → `front_drive = _limit_to_stick(front_drive, front_along, front_arm * sin(wheel_angle), yaw_inertia, delta)`  _(lines 4110‑4111)_
  - `_limit_to_stick` clamps the force to a *stopping_force* proportional to the slip speed: `return clampf(force, -stopping_force, stopping_force)`  _(lines 6146‑6148)_
- **Spin detection** is performed in `_slide_yaw_damping`:
  - `var slip_angle := absf(atan2(across, along))` → `var spin := maxf(smoothstep(SPIN_COMMIT_ANGLE, SPIN_FREE_ANGLE, slip_angle), _rear_lock_recovery)`  _(lines 6166‑6168)_
  - `SPIN_COMMIT_ANGLE` is a constant set to **0.45 rad** (≈ 26°) at line 2509.
  - When `slip_angle` exceeds this threshold `spin` reaches **1.0**, causing the stability‑assist to switch to `SPIN_YAW_DAMPING`.

When the car rolls past 90° of wheel‑angle the `front_along` term changes sign. Because `front_drive` is still positive (throttle), the condition `front_drive * front_along < 0.0` becomes true and `_limit_to_stick` caps the forward drive to essentially zero. The slip‑ratio‑based `spin` flag (triggered at ~26° slip) ensures this happens consistently, giving the *exact* 180° “wheel‑stop” that feels like the wheels lose all torque.

**Why exactly 180°?** The sign flip of `front_along` occurs when the wheel heading points opposite the car’s velocity (`cos(wheel_angle)` changes sign). The code deliberately clamps drive when the wheel is trying to push opposite to its motion, which is typical of a spin‑lock model. The `SPIN_COMMIT_ANGLE` threshold makes the effect activate early, but the actual stop is observed at 180° because the forward component is fully reversed.

---

## 2️⃣  Cone‑Topple Mechanism

Cones are **visual‑only** meshes; they have no `RigidBody3D` or collision shape. Their behaviour is driven entirely by `scripts/test_pad.gd`:

- Constants defining the toppling behaviour (lines 116‑120):
  ```gdscript
  const CONE_TOPPLE_MARGIN := 0.28
  const CONE_TOPPLE_TIME   := 0.35  # seconds to fall
  const CONE_PUSH_PER_SPEED := 0.12  # m per m/s
  const CONE_MAX_PUSH      := 4.0
  ```
- In `_update_cones` (lines 1080‑1092) the car’s footprint (`CAR_HALF_SIZE + CONE_TOPPLE_MARGIN`) is checked against each cone’s position. If the car overlaps, the cone is marked `toppled = true` and a *push* vector is computed:
  ```gdscript
  cone.push = push.limit_length(CONE_MAX_PUSH / CONE_PUSH_PER_SPEED) * CONE_PUSH_PER_SPEED
  ```
- The cone then animates falling over for `CONE_TOPPLE_TIME` seconds (lines 1090‑1091) and is displaced by the *push* distance, independent of the impact speed. Because the push amount scales linearly with the car’s speed (`CONE_PUSH_PER_SPEED`), a hit at 1 km/h or 20 km/h produces the same visual toppling (the push is capped at `CONE_MAX_PUSH`).

**Mass / impulse:** No mass or physics impulse is used; the cone’s motion is a simple linear offset followed by a timed rotation (`tip_basis`). Hence the cones behave as if they have zero mass and are instantly toppled.

---

## 3️⃣  Re‑production Steps for the Driver

1. Load the **test pad** (scene `TestPad.tscn`).
2. Start the car at the origin, facing –Z, with the *test_driver* profile.
3. **Issue 0066** – Full‑throttle in 1st gear:
   - Press the accelerator to 100 % while the car is stationary.
   - Observe the tyres lose grip, the car spins, and when the wheel heading reaches ~180° the forward drive force drops to zero (the car feels like the wheels have stopped).
4. **Issue 0067** – Cone impact:
   - Drive the car into any cone at any speed (e.g., 1 km/h or 20 km/h).
   - The cone instantly topples and slides a short distance (max 4 m) with no deceleration of the car.
5. Use the telemetry files `0176_205009_free.jsonl` … `0182_221259_free.jsonl` (located under `~/Library/Application Support/factory-driver/telemetry/2026-09-27/`) to verify the exact timestamps and vehicle state.

---

## 4️⃣  Fix Options (ranked)

| Rank | File to edit | Scope | Description |
|------|--------------|-------|-------------|
| **1** | `scripts/car.gd` | **Both** (core physics) | Raise `SPIN_COMMIT_ANGLE` or modify the `front_along` sign‑check so that drive is not clamped when the wheel points opposite the velocity. This removes the abrupt 180° stop while keeping the spin model.
| **2** | `scripts/car.gd` | **Both** | Change `_limit_to_stick` to use a softer slip‑speed based clamp (e.g., allow a small reverse component) so the wheels retain a tiny forward torque during a spin.
| **3** | `scripts/test_pad.gd` | **Physics Bubble** (visual only) | Replace the visual‑only cone logic with a proper `RigidBody3D` (mass ≈ 0.5 kg) and a collision shape. Use Godot’s impulse response so the cone’s reaction scales with impact speed.
| **4** | `scripts/test_pad.gd` | **Both** | Adjust `CONE_PUSH_PER_SPEED` and `CONE_MAX_PUSH` to make the slide distance proportional to speed, giving a more realistic topple.

> **Freeze‑exception note:** Both `scripts/car.gd` and `scripts/physics_bubble.gd` are frozen. Any change must be recorded as a *freeze‑exception request* with a justification (e.g., “Correct unrealistic spin‑lock behaviour”, “Add proper rigid‑body physics for cones”). The request text should be submitted via the issue‑tracker and approved before a commit.

---

*All citations are to the exact line numbers in the current code base.*
