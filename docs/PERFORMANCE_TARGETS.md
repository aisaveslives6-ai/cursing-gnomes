# Cursing Gnomes — Performance Targets

**Status:** iPhone 17 standard is the performance FLOOR (Jeremy, 2026-10-04).
The game must hold 60 fps on this hardware. It may scale UP on better
hardware, but must never need more than this to run well.

## Baseline hardware: iPhone 17 (standard)

| Spec | Value |
|---|---|
| Chip | Apple A19, 3 nm |
| CPU | Hexa-core (2 performance + 4 efficiency) |
| GPU | Apple 5-core GPU |
| RAM | 8 GB LPDDR5 (shared with iOS) |
| Display | 6.3" OLED, 2622x1206 px, 458 PPI, 120 Hz ProMotion |
| OS | iOS 26.x |
| Delivery | Godot 4.7.2 web export, played in Safari (WebGL2) |

**Important:** the game ships as a Web export, not a native app. The practical
floor is Safari's WebGL2 on A19 — more constrained than native Metal, and
subject to iOS tab memory limits and thermal throttling during long sessions.
All budgets below are sized for that reality.

Reference scores: Geekbench 6 ~3527 single / ~8798 multi, 3DMark ~5172.

## Performance budgets (worst-case simultaneous load, all tiers)

| Resource | Budget | Current usage | Notes |
|---|---|---|---|
| Weather particles | <= 240 | 220 (rain) / 160 (snow) | `WeatherFX.RAIN_DROPS` / `SNOW_FLAKES`; pooled, tier-scaled |
| Ambient particles | <= 240 | 222 (42 fireflies + 36 leaves + 6x24 embers) | `AmbientFX`; tier-scaled via `amount_ratio` |
| Combat FX pool | <= 64 slots | 48 | `CombatFX.FX_POOL`; oldest-steal, never grows |
| Concurrent building fires | <= 32 | 24 | `CombatFX.MAX_BUILDING_FIRES` |
| Audio voices | <= 32 | 27 (8 sfx + 16 spatial + 3 music) | `AudioManager` pools; never allocate per-event |
| Global NPCs | <= 240 | 240 | `Config.POP_CAP_GLOBAL` (16/town, 48/faction) — Jeremy's hard cap |
| Target frame rate | 60 fps | — | Guarded by adaptive quality in auto mode |
| Renderer | gl_compatibility | gl_compatibility | The ONLY renderer that runs on mobile GPUs. Do not switch to Forward+. |
| Texture filter | Nearest (0) | Nearest | Pixel-art stays crisp; cheaper on mobile GPUs |
| 2D MSAA | Off (0) | Off | Perf on phones |

`GraphicsTiers.BUDGET_*` constants codify these budgets in code; the
`test_performance_budgets.gd` suite fails the build if any system exceeds them.

## Graphics tiers

| Tier | Who gets it | particle_mul | unit_sync_every | tree_draw_frac |
|---|---|---|---|---|
| ultra | Score >= 100 (strong desktop) | 0.9 | 1 | 1.0 |
| high | Score >= 95 | 0.75 | 1 | 0.4375 |
| medium | Score >= 30 — **iPhone 17 floor** | 0.5 | 2 | 0.275 |
| low | Score < 30 (safety valve) | 0.15 | 4 | 0.1 |

iPhone 17 scores ~50 in `GraphicsTiers.score_device()` (A19 hexa-core,
mobile, Apple GPU, ~874 CSS px wide) and lands on **medium**. The adaptive
quality system (`world.gd`, auto mode only) steps the tier DOWN toward low
when sustained frame time exceeds 22 ms (~45 fps), and steps back UP after
~10 s of smooth frames (< 14 ms) — never above the boot tier. Medium is both
the floor and the ceiling on iPhone 17: guaranteed smooth, never
over-promised.

## Graphics settings rules

- Graphics defaults to **Auto** everywhere (Jeremy's standing rule).
- A manual tier choice is always respected; adaptive quality only runs in auto.
- Adaptive quality is purely visual — sim, AI, and RNG are never touched.
- Unit visual sync runs on the tier cadence; sim ticks are unaffected.

## Adding new visual systems

Any new particle system, FX pool, light, or audio voice must:

1. Use a fixed pool — never allocate per-frame or per-event at runtime.
2. Stay within the budgets above (or raise the budget deliberately with a
   documented reason and an updated test).
3. Scale with the graphics tier (`particle_mul` / `tree_draw_frac` /
   `unit_sync_every`) where it makes sense.
4. Keep the iPhone 17 floor in mind: if it can't hold 60 fps on A19 in
   Safari, it doesn't ship.

## Optimization pass (Jeremy 2026-10-04 — "ultimate optimization")

Measured wins from the 60fps pass (headless profile, 240 units):

| Optimization | Before | After | Saving |
|---|---|---|---|
| `UnitAnimator.apply_to` (dict alloc) | 47.3ms / 14,400 poses | 27.3ms | **42% faster**, 0 dict allocs |
| Off-screen unit `_process` culling | 240 units animate always | Only in-view animate | Scales with zoom; ~80% saved zoomed in |
| Shadow/nightglow phase recompute | 60x/sec dict alloc | On 0.0005 phase change | ~99% of calls skipped |
| HUD label writes | Every frame | On text change only | Layout recalcs eliminated |

Additional fixes in the same pass:

- **Stuck-at-night bug**: `NightGlow.glow_for`, `Shadows.sun_state_for`,
  `LightingRig.ambient_for`, and `WeatherFX._tint_target_for` all assumed
  phase 0.25 = noon. GameState uses 0 = midnight, 0.5 = noon. At the new
  midday start (phase 0.5), all four rendered night. Rewrote all four to
  the GameState convention (night when hour < 5 or hour > 21).
- **Stardew clock**: top-right overworld widget showing time + day/date,
  driven by the real game hour. Also fixed `_clock_text()` which divided
  by 86400 (ran 180x too slow) — now uses `WorkerAI.hour_of_day()`.
