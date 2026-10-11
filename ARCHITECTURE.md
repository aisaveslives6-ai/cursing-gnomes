# Cursing Gnomes — Godot 4 Rewrite: Architecture

**Status:** Scaffolded 2026-10-02. Engine verified (Godot 4.7.2 stable, headless).
Web export verified headless (single-threaded WASM).
**This is a full rewrite in GDScript, NOT a port.** No JS is carried over; game
design and tuned numbers are, code is not. **Full scope: the entire game.**
No MVP subset — the build order below gets us to the whole game incrementally.

**Export targets (2026-10-02 decision):**
1. **Web (HTML5/WASM) — PRIMARY.** Runs in Jeremy's iPhone Safari. Replaces the
   hand-written HTML/JS build on itch.io. Far more CPU/memory-efficient than
   the 93 MB single-file JS (WASM sim + engine-level rendering).
2. **Linux desktop — for dev testing.** Exports from this VM.
3. **Android APK — future.** Fully exportable from Linux (needs JDK 17 + SDK).
4. **iOS native — PARKED.** Requires macOS + Xcode for the signing leg; neither
   of us has a Mac. Revisit when Mac/CI access exists.

---

## 1. Why Godot, why now

The HTML build hit Safari's ceiling: 93 MB single file, per-tab memory killer,
no true fullscreen on iPhone, crashes the phone throws at 43+ units. Every
mobile workaround (30 fps cap, disabled mounts/towers, throttled spawners) was
treating symptoms. Godot's **web export** gives us:

- **WASM instead of hand-written JS** — the sim runs as compiled WebAssembly,
  dramatically more CPU/memory-efficient than the single-file JS. Same Safari,
  far less pressure on it.
- **A real engine** — scene tree, typed GDScript, editor, debugger, profiler.
  The HTML game's 28 systems were globals in one file; here they're scenes.
- **The plan all along** — HTML stays playable on itch as the legacy build;
  the Godot web export replaces it as the live build (same itch page, same
  URL Jeremy already shares). Native iOS/Android come later.

### Web-export ground rules (verified 2026-10-02)

| Rule | Setting | Why |
|---|---|---|
| **Single-threaded WASM** | `variant/thread_support=false` | Godot's own verdict: single-threaded "works very well on macOS and iOS". Sidesteps SharedArrayBuffer + COOP/COEP header requirements entirely — critical for itch.io hosting. (Godot 4.3+; 4.7 default is fine.) |
| **Renderer** | GL Compatibility (WebGL2) | Web export is Compatibility-only. Forward+/Mobile/WebGPU don't exist on web. Non-issue for 2D. |
| **Memory ceiling** | Design for it from day one | iOS Safari kills the WebGL context / refuses WASM init rather than degrading. Historical: 2 GB WASM max OOM'd at startup (fixed by lowering); hosted baseline heap ~400 MB; WebKit canvas-resize leak crashes tabs ~1.25 GB. Mitigations: modest asset budgets, no orientation thrash, never recreate the canvas. |
| **Audio unlock** | Title/menu tap = gesture | iOS Safari blocks audio until a user gesture. The game's menu screen tap doubles as the unlock. Single-threaded uses Sample playback (low latency, no threads needed). |
| **No Fullscreen API on iOS** | Safe-area insets | iPhone Safari has no Fullscreen API / orientation lock. Use `viewport-fit=cover` + safe-area insets in the HTML shell; landscape orientation hint. |
| **PWA** | Parked | Godot can emit a PWA shell (offline cache, home-screen icon), but Jeremy's itch.io-wrapper experience was broken. Revisit with a custom HTML shell if he wants Add-to-Home-Screen later. |

### Hard engine decisions (do not revisit casually)

| Decision | Choice | Why |
|---|---|---|
| Renderer | **GL Compatibility** | Only renderer that runs on all mobile GPUs. Forward+ is desktop-only for us. Set in `project.godot`; changing it breaks the iOS target. |
| Logic rate | **60 Hz** physics, **60 fps** target on mobile | Godot targets 60 fps — the HTML 30 fps cap was a Safari emergency fix, not the plan. If heat becomes an issue, optimize logic, never cap frames. |
| Stretch | `canvas_items` + `expand` | Crisp pixel art at any phone aspect; uses the notch area instead of black bars. |
| Language | GDScript, typed | No C#. Keeps build simple, matches team skill (Jeremy is learning code). |
| Texture filter | Nearest (filter off) | Pixel-art stays crisp. Set globally in `project.godot`. |
| Orientation | Landscape | RTS needs the width. Locked in project + iOS preset. |

---

## 2. Project layout

```
godot-cursing-gnomes/
├── project.godot            # engine config (renderer, viewport, autoloads)
├── ARCHITECTURE.md          # this file
├── scenes/
│   ├── main.tscn            # entry: boots Game -> World
│   ├── world/
│   │   ├── world.tscn       # root: map, camera, faction managers
│   │   └── town.tscn        # a town: hall + buildings + assigned units
│   ├── units/
│   │   ├── unit.tscn        # base unit (all jobs/factions inherit behavior)
│   │   └── ...              # (military variants as script configs, not scenes)
│   ├── buildings/
│   │   ├── building.tscn    # base building (construction, HP, occlusion)
│   │   └── ...
│   ├── ui/
│   │   ├── hud.tscn         # resources, minimap, build menu, speed controls
│   │   ├── unit_panel.tscn  # selected-unit info card
│   │   ├── interiors/       # Stardew-style interior UI + arrange mode
│   │   └── phone/           # Messenger / Squabble / contacts
│   └── fx/                  # particles, floating text, weather overlays
├── scripts/
│   ├── main.gd
│   ├── core/
│   │   ├── config.gd        # Jeremy's laws: pop caps, factions, resources
│   │   ├── game_state.gd    # autoload: run state, save/load, time
│   │   └── event_bus.gd     # autoload: decoupled signals (built X, unit died…)
│   ├── sim/
│   │   ├── spawner.gd       # pop-cap-aware spawning (replaces spawnWorld)
│   │   ├── resources.gd     # 5-resource economy
│   │   ├── day_night.gd     # sun cycle, shadows hook
│   │   ├── weather.gd       # rain etc.
│   │   └── disasters.gd     # giant ass, thicc moose, …
│   ├── units/
│   │   ├── unit.gd          # movement, jobs, needs ("urges"), combat
│   │   ├── unit_ai.gd       # job state machines (worker, guard, doctor…)
│   │   └── dialogue.gd      # chatter, bubbles, name-roasting
│   ├── buildings/
│   │   ├── building.gd
│   │   ├── town_hall.gd
│   │   ├── clinic.gd        # auto-doctor, hard cap 1
│   │   ├── fire_station.gd  # auto-firefighters (2), truck dispatch hook
│   │   └── guard_tower.gd   # auto-fire (desktop; budgeted on mobile)
│   ├── world/
│   │   ├── map_gen.gd       # biomes, towns, border walls, rivers
│   │   ├── camera.gd        # drag-pan, pinch-zoom, paper-map zoom-out
│   │   └── selection.gd     # tap/box select, unit panel hookup
│   └── ui/                  # HUD, menus, interiors, phone, gazette
├── assets/
│   ├── sprites/             # chibi pixel art (16 base sprites + variants)
│   ├── tiles/               # terrain tileset
│   ├── audio/               # Title_screen.mp3, SFX
│   └── fonts/
├── tests/                   # headless GDScript tests (GUT or custom runner)
├── docs/                    # design notes carried over from HTML era
└── exports/                 # export_presets.cfg lives here (not in git)
```

**Conventions:**
- One script per scene; shared logic in `scripts/sim/` or autoloads.
- `Config` holds every tunable number — no magic numbers in gameplay code.
  Population caps especially: `POP_CAP_TOWN=8`, `POP_CAP_FACTION=24`,
  `POP_CAP_GLOBAL=96` are Jeremy's law, enforced in `spawner.gd`, never
  bypassed except by the essential-service rule (fire/doctor).
- Signals via `EventBus`, not direct node references, between systems.

---

## 3. The 28 HTML systems → Godot mapping

The HTML build's systems (reconstructed from the 2026-10-02 codebase):

| # | HTML system | Godot home | Notes |
|---|---|---|---|
| 1 | `spawnWorld` / faction select | `sim/spawner.gd` + faction-select UI | Mobile: max 2 factions, player picks (never preselect) |
| 2 | Population caps | `Config` + `spawner.gd` | 8/town, 24/faction, 96/global — hard |
| 3 | Unit jobs AI | `units/unit_ai.gd` (state machines) | worker, roadbuilder, combat, doctor, firefighter, advisor… |
| 4 | Urges (needs) | `units/unit.gd` needs module | Was "whims" — **"urges"** per Jeremy |
| 5 | Dialogue / chatter / bubbles | `units/dialogue.gd` + `fx/floating_text.gd` | Includes name-roasting; bubbles MUST fade (HTML bug) |
| 6 | Buildings + construction | `buildings/building.gd` | HP, build states, placement rules |
| 7 | Resources (5) | `sim/resources.gd` | wood, stone, gold, food, mana |
| 8 | Combat + military | `units/unit.gd` combat module, `buildings/guard_tower.gd` | Cannons/artillery as unit configs |
| 9 | Fire + fire dispatch | `sim/` fire module, `buildings/fire_station.gd` | Trucks auto-dispatch; 2 firefighters/station |
| 10 | Clinic + doctors | `buildings/clinic.gd` | 1 doctor/clinic, auto-spawn, 10 s retry throttle |
| 11 | Mounts | cut for MVP | HTML disabled on mobile anyway; revisit post-MVP |
| 12 | Roads | `world/` road module | Build + pathing; was a freeze source in HTML |
| 13 | Interiors (Stardew) | `scenes/ui/interiors/` | Redo shipped 2026-09-28 in HTML; arrange mode included |
| 14 | Day/night + shadows | `sim/day_night.gd` | Sun cycle; blob shadows (no per-unit alpha ghosts) |
| 15 | Weather | `sim/weather.gd` | Rain etc.; visual only at first |
| 16 | Disasters | `sim/disasters.gd` | Giant ass, thicc moose — keep the jokes |
| 17 | Royal court + gazette | `scripts/ui/` court module | Named AI characters, decision popups, 2-way chat |
| 18 | Phone (Messenger/Squabble) | `scenes/ui/phone/` | Inner-circle contacts only; pfp → Squabble profile |
| 19 | Save/load | `core/game_state.gd` | `ResourceSaver`/JSON; HTML saves don't transfer |
| 20 | Minimap | `scenes/ui/hud.tscn` minimap control | |
| 21 | Camera | `world/camera.gd` | Drag wins; pinch zoom; paper-map at full zoom-out |
| 22 | Particles | `scenes/fx/` (GPUParticles2D) | Replaces HTML canvas particle arrays |
| 23 | Floating text | `scenes/fx/floating_text.gd` | Pooled labels; guaranteed fade (no HTML bug) |
| 24 | Audio | audio buses | Dynamic soundtrack; Title_screen.mp3 carried over |
| 25 | Walls (border + star forts) | `world/map_gen.gd` + building | AoE2 drag-place; border walls far from towns |
| 26 | Diplomacy / war | `sim/` diplomacy module | Declare war, alliances, trade/tribute messages |
| 27 | Trading | economy module | NPC trading |
| 28 | Animation (walk cycles) | `units/unit.gd` + sprite frames | **Discrete poses from atlas, never scroll art.** Freeze-position test must pass before world movement (Jeremy's law, 2026-09-20). 8-directional. |

---

## 4. Core game loop (Godot terms)

```
Main (Node2D)
└── World (Node2D)                 # owns the map + sim
    ├── MapGen (Node)              # builds terrain, towns, walls at new-game
    ├── DayNight (Node)            # advances sun; emits time_changed
    ├── Spawner (Node)             # 60 Hz: enforces pop caps, auto-spawns
    ├── FireDispatch (Node)        # ticks fireMap, dispatches trucks
    ├── Units (Node2D)             # unit instances (pooled)
    ├── Buildings (Node2D)         # building instances
    ├── Camera2D                   # drag/pinch/paper-map
    ├── Selection (Node)           # tap/box select
    └── FX (CanvasLayer)           # floating text, particles, weather overlay
HUD (CanvasLayer)                  # resources, minimap, build menu, unit panel
```

**Frame flow (60 Hz logic, render decoupled):**
1. `_physics_process` (60 Hz): spawner → unit AI → buildings → fire →
   resources → day/night. **No rendering here.**
2. `_process` (render rate, 60 fps target on mobile): visuals follow sim state.
3. Draw order handled by `z_index` / `y_sort_enabled` on the world
   `Node2D` — this replaces the HTML's manual depth sorting AND the
   deleted `drawOccludedUnits` ghost system. **No translucent unit
   duplicates, ever** (that was the HTML ghosting bug — killed 2026-10-02).

**Why not physics bodies for units:** 96 units with `CharacterBody2D`
collision is fine on desktop but wasteful on phones. MVP uses plain
`Node2D` + custom separation steering (the HTML game did the same with
raw x/y). Upgrade to physics only if combat needs it.

---

## 5. Key subsystem notes

### Units
- One `unit.tscn`: `Node2D` + `Sprite2D` (or `AnimatedSprite2D`) + script.
  Faction/job are **data** (`unit_data.gd` resource), not separate scenes.
- Jobs as state machines in `unit_ai.gd`. Essential-service jobs
  (firefighter, doctor) auto-spawn from their buildings with hard caps.
- **Animation law:** walk cycles are discrete atlas poses selected per-frame.
  No scrolling/panning artwork. IDLE/WALK loop, ATTACK/HURT play-and-finish,
  DEATH plays once. 8-directional. Freeze-position test passes before any
  world movement is wired to it.
- Art: anime-chibi pixel art, 4 factions × roles. The 16 HTML sprites are
  reference; Godot needs proper sprite-sheet atlases (one per role per
  faction, 8 directions × poses).

### Buildings
- One `building.tscn`: construction state machine (scaffold → building →
  complete), HP, faction, footprint. Type-specific scripts extend behavior.
- Placement rules from HTML: no overlap, workers clear trees, star-fort
  walls for bases with exit gaps, border walls far from towns.

### Camera & input (mobile-first)
- Single-finger drag = pan (always wins). Pinch = zoom. Tap = select.
  Box-select via drag on empty ground with a modifier/second finger —
  design TBD, HTML used tap-first.
- Full zoom-out = paper map mode (parchment overview), same as HTML.
- `emulate_touch_from_mouse=true` in project.godot so desktop testing
  exercises the touch paths.

### NPC minds
- 100% offline/scripted (Jeremy's call — no LLM, no network).
- Urges drive behavior; dialogue pulls from memory banks + mood lines;
  name-roasting of the ruler's name stays (it's the game's charm; the name
  is never trimmed or baked).
- Royal court: named characters with roles/motives, two-way chat with
  intent parsing, all client-side.

### Interiors
- Stardew-style redo (2026-09-28) carries over: household panel, bathrooms
  in all buildings, furniture placement, arrange mode. Separate scene
  layered over the world; world sim pauses or ticks cheaply behind it
  (HTML froze here — Godot gets it right by construction).

### Performance budget (phone)
- 60 fps target, 60 Hz logic, `y_sort` instead of manual depth,
  pooled floating-text labels, GPUParticles2D (not CPU particles),
  Compatibility renderer. The HTML game's freeze list (mounts, guard
  towers, roads, arrange) is the perf hit-list for Godot too — each gets
  a time budget before it ships. Budgets sustain 60 fps; we never cap
  the frame rate to fix heat.

---

## 6. Build order — the whole game, incrementally

Jeremy confirmed 2026-10-02: **the entire game, not a subset.** The milestones
below are cumulative — each is playable in the browser, each unlocks the next.
No milestone ships to itch until it holds 60 fps on a phone for 20 minutes.

### Milestone 1 — Sim core (headless-testable)
- `Config` (all Jeremy's laws) ✅ scaffolded
- `GameState` autoload: run state, rng seed, save/load (JSON via `FileAccess`)
- `EventBus` autoload: `unit_died`, `building_built`, `resource_changed`…
- `Spawner`: pop-cap enforcement (8/town, 24/faction, 96/global), faction
  select (≤2 on mobile, player picks, never preselect)
- `Resources`: wood/stone/gold/food/mana ledger per faction
- Headless tests: caps hold under spawn spam; economy balances over 10 sim-minutes

### Milestone 2 — World + camera (first pixels) ✅ DONE 2026-10-02
- `MapGen`: FastNoiseLite terrain (grass/water/sand), 700 trees, resource
  nodes near starts, 4 quadrant faction starts on carved grass — pure logic,
  deterministic per seed (`scripts/world/map_gen.gd`)
- Terrain bakes to ONE 512x512 texture (single draw call, Nearest-filtered);
  trees/resources are y-sorted nodes (`world_renderer.gd`, `map_prop.gd`)
- Rivers visual overhaul (2026-10-02, Jeremy's 2026-09-29 verdict): downhill
  river carving from an elevation field (7 rivers, width varies, clear of
  faction starts), steepest drops marked as waterfalls (max 8, spread out);
  bake has depth gradient (sandy shallows → deep centers), white foam froth
  at waterlines, wet-sand/mud bank bands; `RiverRenderer` adds the animated
  flow shader (scrolling ripples, water-only mask), scrolling waterfall
  faces, and a pooled foam layer (drifting flecks, impact bursts, expanding
  rings, rising mist — zero per-frame allocation). `fishing_dock` building
  added; placement ghost requires water within 6 tiles
  (`scripts/world/river_renderer.gd`, `assets/shaders/water_flow.gdshader`,
  `tests/test_rivers.gd` — 38 headless tests)
- `CameraController`: touch-first drag-pan (drag always wins), two-finger
  pinch zoom, wheel zoom, tap detection, map-bounds clamp (pure math,
  headless-tested)
- `Selection`: tap-to-select nearest unit/building within 60 px, white ring,
  tap-empty deselects
- Placeholder units (faction-color circles) + buildings (squares w/ roofs);
  M3 expanded the demo to all 4 factions x (hall + 3 blueprints + 7 units
  incl. firefighter/doctor) through the real spawner — 37 headless tests
  pass, 42 sim tests still pass
- Web export: `exports/web/cursing-gnomes.html` — 39 MB total
  (38 MB engine + 71 KB game code). Open on iPhone Safari: see the map,
  drag to pan, pinch to zoom, tap units to select.
- y_sort on the World root replaces the HTML's manual depth sort AND the
  deleted `drawOccludedUnits` ghost system — no translucent duplicates, ever

### Milestone 3 — Jobs & buildings ✅ DONE 2026-10-02
- `scripts/sim/jobs.gd` — 15-job registry (worker → cannoneer): categories,
  gather-resource map, job-dot colors; military jobs exist for the roster
  but are behavior-only in M4
- `scripts/sim/work.gd` — `WorkerAI` per-unit state machine:
  idle → to_resource → gathering → to_dropoff (hall/stockpile) →
  to_build/building → to_repair/repairing → to_patient/healing. Straight-line
  steering, carry cap 10, gather 2.5/s, build 1.0 power/s, repair 25 hp/s,
  heal 12 hp/s. Miners credit gold from gold veins; farmers work farm
  buildings (infinite food)
- `scripts/sim/buildings.gd` — 12 building types w/ costs/build_time/hp/
  footprints; `place_blueprint()` atomically spends resources (unaffordable =
  rejected, reason reported); `can_place_at()` blocks overlap/off-map, lets
  walls chain; `tick_construction()` converts builder power to progress;
  `tick_service()` auto-staffs clinic (1 doctor) / fire station (2
  firefighters) with a 10 s retry throttle per building; `tick_clinic_heal()`
  aura-heals allies at 10 Hz
- `scripts/world/building_placement.gd` — two-tap placement: BUILD menu →
  building → ghost preview on map (green = valid, red = overlap/broke/
  off-map) → tap to confirm, tap ghost again to cancel
- `scripts/ui/hud.gd` — resource bar (5 resources), pop counter (X/24),
  BUILD toggle, build panel w/ costs + unaffordable dimming, selection panel
  (unit job/HP, building progress/HP/staffing) — touch-sized, 44 px targets
- `building_node.gd` rewritten: per-type programmer-art silhouettes
  (sawmill blades, clinic cross, tower crenellations…), live record link,
  translucent scaffolding + progress ring on blueprints
- `unit_node.gd`: job indicator dot (`JobDefs.JOB_DOT_COLORS`) on every unit
- 40 headless tests (`tests/test_jobs_buildings.gd`) — gather→ledger,
  gold-vein credit, farm food, builder completes blueprint, unaffordable
  rejected, clinic→1 doctor, fire station→2 firefighters (even on a full
  town = bypass holds), repair, doctor heal, wall chaining, 60 s 4-faction
  work sim: caps hold (8/24/96), no stuck units
- **60 fps target** (Jeremy 2026-10-02: the HTML 30 fps cap was a Safari
  emergency fix, not the plan): physics at 60 Hz, worker AI on a 32-units/
  tick round-robin budget, clinic heals on a time accumulator (not tick
  counting), prop cleanup 1/s, staffing throttle-gated — all HTML lessons
  (budgets, 10 s retry, hard caps, no ghost systems, y-sort) baked in by
  design, not as patches
- Demo world: all 4 factions × (hall + house + farm + fire-station blueprints
  + 7 units with jobs) — total 119 headless tests pass (42 sim + 37 world +
  40 jobs); web export verified
- **Art port (Jeremy 2026-10-02: port ALL of it, not just reference it):**
  449 embedded images extracted from the HTML build to
  `assets/art/` (`/tmp/extract_art.py` did the work; wall art got a
  chroma-key pass in `/tmp/key_walls.py`, originals kept as `*_raw.png`):
  96 chibi unit sprites, 28 building sprites, 7 wall pieces, 13 job-tag
  icons, 2 tree sprites, 35 fire/smoke FX frames, 75 furniture sprites,
  44 messenger portraits, 12 undead portraits, boats, UI chrome, splash
  screens — `assets/art/manifest.json` maps every key to its file
- `scripts/world/art.gd` — lazy texture cache + sprite-identity ports:
  `appearance_key()` (race_archetype_gender+variant, deterministic per
  unit, cf. HTML appearanceKey54), `archetype_for_job()` (cf. HTML
  chibiArchetype: doctor→mage, soldier/guard→warrior, ranger→ranger),
  job-tag and building-art lookups
- `scripts/world/unit_animator.gd` — faithful port of the HTML's
  AnimationController + toonPose() (the system Jeremy approved on his
  iPhone): discrete choreography clips (idle/walk/work/attack/hurt/death),
  feet-pivot bounce/rock/squash, per-unit phase; ATTACK/HURT play once and
  settle, DEATH plays once and holds uninterruptible; the animator only
  ever touches the Body node — world movement stays in UnitNode.position
- `unit_node.gd` now draws the real chibi sprite (feet at the Body origin),
  job-tag icon, and horizontal facing flip; `building_node.gd` uses
  bld_house/bld_townhall/bld_tower/bld_barracks/gatehouse/wall_strip where
  the HTML has art (farm/clinic/etc. keep programmer silhouettes — the
  HTML drew those procedurally too); `map_prop.gd` draws real oak/pine art
- Animation-law tests (`tests/test_art.gd`, 30 tests): all 96 sprite keys
  resolve, every job has a tag, freeze-position test passes (walk cycle
  plays 2 s with the node planted, bounce only upward), attack→idle,
  hurt→walk, death holds and can't be interrupted, gender deterministic
- New totals: 149 headless tests pass (42 + 37 + 40 + 30); web export
  53 MB verified (38 MB engine + 15 MB game+art)

### Milestone 4 — Combat & disasters ✅ DONE 2026-10-02
- `scripts/sim/combat.gd` — melee (soldier/guard/bandit), ranged
  (archer/ranger/mage/cannoneer), guard-tower auto-fire; per-job stats
  {dmg, range, cooldown, splash}; cannoneer artillery 70 dmg / 180 px
  splash (HTML's field/grape cannons, ported as design); free-for-all
  hostility (all factions fight all; "monster" hostile to everyone —
  diplomacy/alliances move to M5+); death -> 20 s corpse -> purge;
  siege damage destroys buildings (building_destroyed event)
- `scripts/sim/disasters.gd` — wildfire records {position, intensity}:
  2 Hz spread to nearby trees, damage to units/buildings in radius,
  natural burnout, 80-fire cap; firefighters auto-dispatch and
  extinguish (far dispatches ride the truck at 210 px/s — Jeremy's
  autonomous fire-truck rule, abstracted as rapid response);
  monsters (faction "monster", bypass spawner caps): giant ass
  (1200 HP / 55 dmg, 150 s rampage budget, then leaves via nearest edge),
  thicc moose (800 HP, 0 dmg, moons 3 halls then leaves), bandit raid
  (5 raiders, one at a time), giant lizard, rogue wizard, cardboard cat;
  singletons enforced (only one ass / moose at a time, HTML rule)
- `scripts/world/projectile.gd` — dumb visual nodes (arrow streak, spell
  orb, cannonball + smoke trail); sim record owns motion, world syncs
- `scripts/world/combat_fx.gd` — pooled FX (48 slots, never allocates
  under fire): hit flashes, death poofs, explosions, muzzle flashes;
  per-fire animated sprites from the HTML fire_lg_* frames, scaled by
  intensity
- World wiring: military -> combat AI, firefighters -> fire response,
  monsters -> disaster tick; death plays DEATH clip then node frees;
  combat-state edge-triggers attack/hurt one-shots; 5 factions in demo
  (undead added), soldier + archer per faction, guard-tower blueprints
- 67 headless combat tests (`tests/test_combat.gd`); full suite green:
  42 sim + 37 world + 40 jobs + 30 art + 67 combat = **216/216 pass**
- Web export verified: 53 MB total, clean 300-frame live smoke test
  (disasters + fire + skirmish, zero errors)

### Milestone 5 — Minds (the personality layer) ✅ DONE 2026-10-02
- `sim/personality.gd` — deterministic traits (brave/friendly/diligent/crude/proud) + names, seeded from unit id
- `sim/urges.gd` — Hunger/Energy/Hygiene/Social/Mood/Bladder (0–100, HTML defs); critical urges override job work
- `sim/emotion.gd` — happy/sad/angry/scared/proud/disgusted with ttl decay; brave NPCs get angry, cowards get scared
- `sim/memories.gd` — typed memories with halflife decay, relationship scoring, grudges
- `sim/dialogue.gd` — 100% offline scripted lines; {ruler} substituted VERBATIM (never trimmed); 12-line ruler roast table
- `sim/mind.gd` — coordinator ticked inside the world's 32-units/tick AI budget; flee behavior; grief on death
- `world/speech_bubble.gd` — guaranteed-fade bubbles (HTML's stuck-bubble bug fixed by design)
- `tests/test_minds.gd` — **59/59 pass** (decay, overrides, eating, flee, grudges, grief, roasts, verbatim names, offline, no-banned-word)
- Total: 216 + 59 = **275/275 pass**

### Milestone 6 — Interiors & phone ✅ DONE (2026-10-02)
- **sim/interiors.gd**: Stardew-style interiors. Floor plans per building type
  (house/clinic/town_hall/barracks/fire_station + generic), ported from the
  HTML layouts; 1500×1050 dollhouse canvas; furniture {id,kind,x,y,w,h,
  label,need,room}; need vocabulary mirrors urges (sleep/eat/wash/bladder/
  social/rest); enter/exit/occupants; furniture shop placement; arrange-mode
  moves; all state on the building record (save/load-safe).
- **world/interior_view.gd**: dollhouse overlay — floor, extracted furniture
  art (procedural fallback for door/window/tv/divider), occupant markers
  with names; arrange mode tap-select + drag; exit affordance.
- **sim/phone.gd**: phone sim core. Contacts = pinned "My Government"
  (advisers/guild masters/watch captains of player faction, ranked) +
  player-added ONLY (no auto-populated phonebook — Jeremy's law). Messenger:
  threads, 100% offline scripted NPC replies (intent parsing + SimDialogue),
  remembered sort (latest/most_used/unread_first), answered sink / unanswered
  rise. Squabble: posts from real sim events, likes/comments (scripted
  replies)/resquabbles, newest-first feed. Bios from memories ONLY — nothing
  invented. pfp portrait keys per unit.
- **ui/phone_ui.gd**: touch-friendly Control UI (76px targets). Home →
  Messenger / Squabble / Gazette. Thread view + send box, post cards,
  profile view with bio, Gazette news + petition decision buttons.
- **sim/royal_court.gd**: Royal Court + Gazette. Named-character petitions
  (troops/supplies/trade/tribute/alliance/threat/festival/taxes) with real
  effects (gold/food/relations); decisions reach the player ONLY through the
  Gazette. Gazette ("The Cursing Chronicle"): stories from REAL sim events
  only, sections/reporters deterministic, Vol./No. off the game calendar.
- **scripts/world/art.gd**: +furniture_texture(), +portrait_texture()
  (.webp with .png fallback), FURNITURE_DIR/PORTRAIT_DIR/FX_DIR consts.
- **event_bus.gd**: +interior_entered/exited, phone_message,
  phone_contact_added, squabble_post, petition_opened/decided, gazette_story.
- Tests: tests/test_phone_interior.gd — 95/95 pass. Full suite: 370/370.

### Milestone 7 — Polish & ship (web) ✅ DONE 2026-10-02
- **Main menu: same as the HTML version, but optimized and polished** (Jeremy 2026-10-02). Same layout, same options, same feel — just faster, cleaner, no jank. ✅ `scripts/ui/main_menu.gd` — title, Continue/New Game/Saved Worlds/Sandbox/Adventure/Settings/Credits/Hearsay, 5-faction cards with ATK/DEF/SPD, ruler name input (verbatim).
- **Settings screen** ✅ — graphics preset (Auto default), ground detail, labels, life decisions, tree sway, music + volume, debug overlay (OFF by default). Persisted to user://settings.json.
- **Save/Load** ✅ — `scripts/core/save_system.gd`: full state snapshot (units, buildings, towns, sites, resources, ruler name verbatim, next ids), 8 slots, JSON in user://saves/.
- **Weather visuals, day/night polish** ✅ — `scripts/world/weather.gd`: smooth day-phase tint (dawn/noon/dusk/night), pooled rain (220) + snow (160) particles, 60fps budgets.
- **NPC autonomous building entry** ✅ — mind→interior hook: critical urges drive NPCs into nearby suitable buildings (energy→house, hunger→house/tavern, etc.); they exit when satisfied.
- **Messenger real text input** ✅ — per-post comment box with LineEdit (replaces canned "Nice post!").
- **Disaster visuals** ✅ — Thicc Moose uses moose.png (2.2x), Giant Ass is a procedural brown oval with the crack (it's a butt joke), giant lizard uses lizard art.
- **Fire truck visual** ✅ — `veh_fire_truck.png` under firefighters when `on_truck`.
- **Animation law honored throughout** ✅
- **Tests: 403/403 pass** (42+37+40+30+67+59+95+33).

### Milestone 8 — Diplomacy ✅ DONE 2026-10-02
- **Full diplomacy system** ✅ `scripts/sim/diplomacy.gd` — pair-wise
  relationship states per faction pair (WAR/HOSTILE/NEUTRAL/FRIENDLY/
  ALLIED, ported from the HTML's relations matrix + drift feed).
  Actions: `declare_war`, `make_peace`, `propose_alliance` (AI
  accepts/rejects), `sign_trade_agreement`, `demand_tribute` (AI accepts
  if scared, refuses if proud), `break_treaty` (reputation hit),
  `pay_tribute`. Effects: WAR enables combat, ALLIED blocks it +20%
  trade, FRIENDLY +10%, trade deals +15% and run daily caravan
  exchanges at the improved rate. Faction-level memory (grudges block
  alliances), per-faction morale + reputation, deterministic
  per-faction AI traits (brave→war, friendly→ally, proud→refuse
  tribute). Daily AI tick: wars, peace offers, alliance obligations
  (allies join wars / send aid), tribute demands; AI→player moves
  arrive as Royal Court petitions.
- **Combat integration** ✅ `SimCombat.can_fight()` — diplomacy gates
  all targeting (units, towers, splash); monsters always hostile;
  free-for-all fallback when unwired (legacy tests untouched).
- **Court + Gazette integration** ✅ diplomatic petitions
  (trade/tribute/alliance/threat) resolve through SimDiplomacy;
  wars/alliances/treaties/tribute publish real Gazette stories.
- **Treaty UI** ✅ phone app "🤝 Diplomacy": per-faction standing
  cards with touch-sized Declare War / Propose Alliance / Trade Deal /
  Demand Tribute / Sue for Peace / Break Treaty buttons.
- **Save/load** ✅ diplomacy state in `save_system.gd` snapshots.
- **Tests: 96/96 pass** `tests/test_diplomacy.gd` (war/combat gating,
  alliance protection, tribute transfers, AI accept/refuse logic,
  grudges, reputation, trade exchange, morale, court routing, Gazette,
  UI smoke, save round-trip).

**Art pipeline (parallel track):** Port ALL 431 embedded images from the HTML build (16 faction sprites: 4 factions × worker/warrior/ranger/mage, animal pixel art, UI assets, etc.). Extract from the single-file HTML and import into Godot as textures. Build 8-directional atlases from the sprite sheets — Jeremy's animation law (discrete poses, freeze-position test, IDLE/WALK/ATTACK/HURT/DEATH) applies to all ported art.
and may need commissioning. Programmer-art placeholders unblock all
milestones above.

---

## 7. Export pipeline — web first

**Primary: Web (HTML5/WASM)** — `export_presets.cfg` → preset `"Web"`.
- Single-threaded (`variant/thread_support=false`): no COOP/COEP headers
  needed, works on itch.io as-is.
- Output: `exports/web/cursing-gnomes.html` (+ `.js` `.wasm` `.pck`).
  Upload the whole folder to itch.io as the browser-playable build —
  same page, same URL Jeremy shares.
- `html/canvas_resize_policy=2` (Project): canvas + viewport fill the
  iframe/window. itch.io's iframe is the known constraint (no true
  fullscreen on iPhone Safari — platform limit, not ours).
- Headless CI loop on this VM:
  `godot --headless --path . --export-release "Web" exports/web/game.html`
  (verified 2026-10-02).
- File-size discipline: WASM sim + compressed `.pck`. The 93 MB HTML
  bloat (recursive zip, giant inline assets) doesn't transfer — but the
  asset budget still matters for the iOS Safari memory ceiling (see §1).
  Target: initial load well under the HTML build's weight; stream and
  pool aggressively.

**Secondary: Linux desktop** — preset `"Linux"`, for dev testing on this VM.
**Future: Android APK** — fully exportable from Linux (needs JDK 17 +
Android SDK + `textures/vram_compression/import_etc2_astc=true`); good
intermediate device-testing target, no Apple account needed.
**Parked: iOS native** — Godot on Linux can generate the Xcode project,
but signing/building the .ipa requires macOS + Xcode + Apple Developer
account ($99/yr). Revisit when Mac/CI access exists. The web export is
the iPhone deliverable until then.

`export_presets.cfg` lives at the project root (Godot requirement).
`exports/` holds build output (git-ignored). Never commit signing material.

## 8. Roadmap

Milestones are §6. Supporting tracks:

- **Track A — Engine:** scaffold ✅ · web export verified ✅ · headless
  sim tests ✅ (42) + world tests ✅ (37) + jobs/buildings tests ✅ (40) +
  art/animation tests ✅ (30) · Milestone 3 playable in browser
  (programmer art) · Android export on this VM (later).
- **Track B — Art:** sprite-atlas pipeline (4 factions × roles × 8 dirs ×
  poses); tileset; programmer-art placeholders unblock all milestones.
- **Track C — Audio:** SFX banks, dynamic soundtrack (Title_screen.mp3
  carried over); iOS gesture-unlock wired to the menu tap.
- **Track D — Release:** itch.io web build replaces the legacy HTML build
  on the same page; Drive ZIP backups per release; Steam desktop later.
- **Track E — Adventure mode** ✅ DONE (2026-10-02): RuneScape-style hero
  RPG layer ported from the HTML build (design port, not code).
  `scripts/sim/adventure.gd` (SimAdventure) + `scripts/ui/adventure_hud.gd`
  (AdventureHUD), 67 headless tests. Hero with level/XP/str/agi/vit/intel,
  mana, gear slots (weapon/armor/trinket) + outfitter shop; 6 story quests
  (bounty/rescue/escort/fetch/clear) from named givers + finale quest
  "The Bandit King"; 3 wild dungeons with level-scaled bandit denizens and
  lootable chests (dungeon-forged gear) + a 4th Stronghold for the finale;
  Heroic Strike ability; crime/wanted heat per faction; death = 8 s respawn
  at the home hall, −10% gold. WIN: slay the Bandit King. LOSE: fall 5 times.
  Menu: Adventure Mode → faction + hero name/class setup → world boots, hero
  spawns by the home hall, camera follows. Tap hero to select, tap ground to
  move, tap enemy to attack (auto-combat vs bandits/monsters).

**Standing rules carried over:** graphics default Auto; Jeremy's iPhone is
final acceptance; never claim fixed until his device confirms; no spending
/ publishing / third-party contact without his explicit approval; credit
"Ethos", never Meta, in-game.

---

## 9. Risks & honest unknowns

1. **I've never shipped a Godot game.** GDScript idioms and the editor's
   scene workflow are learn-as-I-go. Timelines are weeks/months, not days.
2. **Art pipeline is the long pole.** 4 factions × roles × 8 directions ×
   poses is real artist/commission work or a big procedural effort. The
   16 HTML sprites are reference, not shippable atlases.
3. **iOS Safari memory ceiling.** The web export runs in the same Safari
   that killed the HTML build — WASM is far leaner than 93 MB of JS, but
   the per-tab memory limit still applies. Asset budgets + pooling from
   day one; test on Jeremy's phone early and often.
4. **HTML saves don't transfer.** Fresh start for players; the HTML build
   remains playable on itch as the legacy version until the Godot web
   build replaces it on the same page.
5. **Scope is the killer.** "Everything" is a multi-month build. The
   milestones in §6 are the protection — each one playable, none
   skippable, no claiming done until Jeremy's iPhone agrees.
6. **iOS native stays parked.** No Mac on either side; the web export is
   the iPhone deliverable. Revisit native only with Mac/CI access.

---

## 10. Critical fixes (2026-10-02, post-M7 Jeremy playtest)

Jeremy tested the "final" build on his iPhone and reported it broken.
The following were fixed:

### Input was completely broken
**Root cause:** `pointing/emulate_mouse_from_touch` was not enabled in
project.godot. Touch events on iOS Safari arrive as `InputEventScreenTouch`,
not mouse events. Godot's GUI Controls (Buttons) need mouse emulation to
receive taps. The M2 camera worked because it handled raw touch events
directly; the M7 menu used standard Buttons which were deaf to touch.
**Fix:** `pointing/emulate_mouse_from_touch=true` in project.godot.

### Sprite mapping: elves rendered as gnomes
**Root cause:** `art.gd appearance_key()` stripped trailing 's' to map
plural faction names to singular sprite prefixes. "elves" → "elve" (not
"elf") → fell through to the gnome default.
**Fix:** Explicit singular mapping dict instead of s-stripping.
Note: undead units render as gnomes — this matches the HTML, whose
`race54()` also falls back to gnome for undead (no undead sprites exist).

### Paper map / minimap was never ported
**Built:** `scripts/world/paper_map.gd` (PaperMap, CanvasLayer).
Parchment-styled full-world map, appears on zoom-out past 0.35 or via 🗺
toggle. Faction-colored unit dots + building squares, camera viewport
indicator, tap-to-jump camera. Wired into world.gd.

### Phone UI existed but was unreachable
**Root cause:** M6 built `phone_ui.gd`, `sim/phone.gd`, `sim/royal_court.gd`,
`sim/interiors.gd` but never instantiated them or added a phone button.
**Fix:** World now instantiates SimPhone, SimRoyalCourt, SimInteriors (stored
as members). HUD has a 📱 button in the top bar that toggles the PhoneUI
overlay (Messenger/Squabble/Gazette).

### Side tabs were missing
**Root cause:** HTML has a side-bubble system (Build/Zone/Army). Godot only
had a BUILD button.
**Fix:** HUD now has a left-side vertical tab bar (🏗/🗺/⚔) matching HTML's
side bubbles. Build reuses the build panel; Zone offers residential/
commercial/industrial/military/dezone; Army shows per-faction soldier counts.

### PARITY ACHIEVED (2026-10-02)
Full 1:1 feature parity with HTML v0930.59. **1144/1144 tests pass.**

What was added in the parity push:
- **Resources fixed**: HTML uses gold/wood/food/seeds/oil (NOT wood/stone/gold/food/mana). Godot now matches.
- **Buildings**: 33 total (was 11). All HTML types ported: aa_tower, bathhouse, courthouse, farmhouse, fishing_dock, flesh_farm (undead-locked), guard_house, guild_hall, horse_stable, knights_castle (human), mage_spire (gnome), repair_shop, war_hut (ogre), well, windmill, hall, storage, stock_* (5 resource vaults).
- **Diplomacy** (Milestone 8): WAR/HOSTILE/NEUTRAL/FRIENDLY/ALLIED, war declarations, alliances, trade agreements, tribute demands, treaty UI in phone, AI logic, Gazette integration.
- **Zoning**: Residential/commercial/industrial/military zones with paint tool, bonuses, overlay.
- **Rivers/waterfalls**: Carved terrain, banks, depth, foam, animated waterfalls, drifting flecks (Jeremy's 2026-09-29 spec).
- **Adventure mode**: Full RPG layer — hero, 7 quests, 3 dungeons + Stronghold, 12 gear items, crime/wanted, win/lose.

The Godot version now has EVERY feature from the HTML version. Same game, faster engine, 60fps target.

## 11. Audio system (2026-10-02)

Jeremy: "Music should play as soon as the game is opened." + "I want the tracks I chose in there" + "they will play at the correct times."

### The 5 tracks (all Jeremy's, via Suno, extracted from HTML v0930.59)
| File | ID3 Title | HTML constant | Moment |
|------|-----------|---------------|--------|
| music_title.mp3 | "Title screen" | TITLE_MUSIC_SRC | Main menu (alternates with fifths) |
| music_fifths.mp3 | "Open Fifths" | TITLE_MUSIC_SRC_OPEN_FIFTHS | Main menu (alternates with title) |
| music_peace.mp3 | "Stewardship in Peace" | PEACE_MUSIC_SRC | Gameplay, low intensity (peace) |
| music_march.mp3 | "Strategic March" | WAR_MUSIC_SRC | **BATTLE MUSIC** — high intensity combat |
| music_war.mp3 | "World at war" | WORLDWAR_MUSIC_SRC | Total war (at war with EVERYONE) |

Total: 21.8MB (acceptable for web export).

### Battle music (ported from HTML MusicManager)
- **Menu mode**: title music, alternating title/fifths on track end (HTML `TITLE_MUSIC_LIST`)
- **Game mode**: intensity-driven three-way crossfade
  - Peace track fades in at intensity 0.12→0.35
  - War track ("Strategic March") fades in at intensity 0.55→0.85
  - World-war track takes the war slot when at war with all factions
- **Intensity** (HTML `computeIntensityTarget`): player units in combat (+0.09 each),
  enemy combat units near player base (+0.07), damaged player buildings (+0.05).
  Attack fast (~2.5s), release slow (~9s). Combat ends → intensity decays → peace returns.
- **Transitions**: menu→game crossfades title out over ~5.5s (HTML CANDIDATE14)

### iOS autoplay
iOS Safari blocks audio until user interaction. We try autoplay on open;
if blocked, show "🔊 tap anywhere for music" (same as HTML). First tap
anywhere calls `unlock_on_tap()` and music starts. Hint hides on `music_started`.

### Files
- `scripts/audio/audio_manager.gd` — AudioManager (music + SFX + battle system)
- `assets/audio/*.mp3` — the 5 extracted tracks
- `tests/test_audio.gd` — 43 tests

### Population caps (2026-10-02, Jeremy: "More units. Less limits.")
Doubled from HTML: **16/town, 48/faction, 240/global** (was 8/24/96).

## 12. Visual parity (2026-10-02, Jeremy's screenshot review)

Jeremy: "use the original game and cross reference everything and recreate it
exactly as it was." Two problems from his iPhone screenshot:

### Sidebar → HTML gaz-float + drawer
The old 3-button left column (🏗 🗺 ⚔) did not match HTML. Rebuilt from
the HTML source (`#gaz-float`, `#hud-toggle`, `#ui-panel`):
- **Left edge** (bottom-left column, round 52px gold-bordered buttons
  #c9a227 on dark brown #4a3420, gold #ffe082 text):
  🏗 Build | ⛅ Weather & Calendar | 📱 Messages | 👁 Squabble |
  👑 Policies | ☰ drawer toggle
- **Drawer** (`#ui-panel` parity, scrollable, hidden by default):
  📜 Realm header | 👑 ROYAL GAZETTE (Chronicle/Messages/Policies) |
  💰 Resources (live) | 📊 Management | 👥 Peoples (live per-faction) |
  👑 Leadership | 🌤 World | 🏗 Command (Build/Zone/Army) |
  ⚙️ Menu (Settings/Saved Worlds/Main Menu/Save/Load/Disasters/Pause)
- Zone/Army moved into the drawer's Command section (HTML's dr-tabs).
- New `drawer_action(action)` signal for save/load/pause/settings/menu.
- **Clock** in top bar (HTML parity: "8:04 AM · Mon Bloommoon 1") —
  12 fantasy months, weekday cycle, from `game_time`/`day_number`.

### Ground → textured, not flat
The old bake sampled noise per-TILE (2 grass colors, chunky squares).
HTML bakes per-pixel biome palettes + faction territory tints + grain.
- **5-shade meadow blend** from per-pixel detail noise
- **Dirt patches** from low-frequency noise (worn earth)
- **Fine grain** brightness variation (baked, like HTML's overlay tile)
- **Faction territory tints** (HTML `factionTerritories()` parity):
  smooth falloff from each faction start — humans bright, elves green,
  gnomes warm, ogres tan, undead ashen tan wastes
- **Paper map threshold**: 0.35 → 0.16 (HTML `PAPER_ZOOM`)

### Files
- `scripts/ui/hud.gd` — sidebar rebuild, drawer, clock
- `scripts/world/map_gen.gd` — textured ground bake
- `scripts/world/paper_map.gd` — threshold fix
