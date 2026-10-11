# Cursing Gnomes — Complete Feature Audit (HTML → Godot)
**Date:** 2026-10-02 | **Jeremy's rule:** "Everything, no stone unturned"
**Session 2026-10-04 (16:19 wake routine):** full suite — 101 suites, 7,303 checks, 99 passed; the 2 failures (test_settings_port.gd TIMEOUT, test_slur_condemn.gd "posts condemn racism explicitly") both pass in isolation (64/64 and 65/65) — suite-run interference, unrelated to this change. Fixed a missed "never an X" violation: the 15:35 pass completed Jeremy's back-button rule across hud.gd/unit_info.gd/phone_ui.gd but main_menu.gd's title-screen update banner still had a live `dis.text = "×"` (U+00D7) dismiss button — a tofu risk on iPhone. New shared `scripts/ui/drawn_x.gd` (`class_name DrawnX extends Control`, pure draw commands, color/thickness args, mouse-filter IGNORE, same pattern as DrawnChevron); `_update_banner()` now uses a drawn purple X on the same 32px translucent button, same `_dismiss_banner` callback. Extended `tests/test_no_x_buttons.gd` (scan now also catches `text = "×"` U+00D7; main_menu.gd pin; 5 DrawnX checks): **13/13 green**; regressions test_menu_smoke 130/130, test_ui_chrome_glyphs 65/65. No export/Drive upload this run — sibling actively editing the tree (unit_node.gd, combat.gd, phone.gd, pathfinding.gd touched after 16:35); per the 15:24 precedent the change rides the next green-tree export. iPhone acceptance pending per standing rule. Parked: world-space unit HP bars — HTML draws them in-world, the port has none (Jeremy's "health bars only when injured" rule); needs unit_node.gd which the sibling is editing.
**Session 2026-10-04 (15:24 wake routine):** full suite — 98 suites, 7,297 checks, 97 passed; the single failure (test_paper_lod.gd "zoom threshold 0.16") was a sibling worker editing that test mid-run — passes 6/6 in isolation, unrelated to this change. Implemented the **naval renderer** — fishing_boat/war_ship were sim-complete (ferry.gd) but rendered as chibi workers with a worker hard-hat job tag standing on water. Extracted fix79's BOAT_SPRITE_SRC pixel-art hulls (fishing_boat 256x184, war_ship 256x187) to `assets/art/boats/`; new `Art.boat_texture()` + `Art.faction_accent()` (HTML RACES accents verbatim: gnome #8e24aa, ogre #388e3c, elf #2e7d32, human #0288d1, undead #37474f, plural names mapped). UnitNode boat branch: hull sprite at HTML-verbatim scale (bw = s*3.4 war / s*2.5 fishing, center -bh*0.22), bob = sin(t*2.1+uid*1.7)*s*0.07 + rock = sin(t*1.3+uid*2.3)*0.045, faction pennant triangle fluttering from the mast (fw = s*0.5, fh = s*0.22, fx = bw*0.18, fy = -bh*0.72-s*0.35+sin(t*6+uid)*1.5); boats skip the UnitAnimator choreography and facing flips (HTML never flips hulls); war_ship keeps the combat shield job tag (HTML COMBAT_JOBS fallback idx 10, added to JOB_TAGS), fishing_boat gets none; no limb-stump overlays on hulls; shadow blob scaled to the hull; set_job rebuilds the visual subtree on boat<->non-boat swaps. New `tests/test_boat_art.gd`: **51/51 green** (art ships, texture resolve + null for non-boats, accents incl. elves plural fix, tag pins, hull geometry, wave-motion formulas, pennant flutter + colors, no-limb-stumps, set_job rebuild, non-boat unaffected). No export/Drive upload this run — a sibling job was actively editing the tree (hud.gd, flood_overlay.gd, radiation_overlay.gd, test_paper_lod.gd all touched during the run); the boat renderer is tested and will ride the next green-tree export. iPhone acceptance pending per standing rule.

**Session 2026-10-04 (11:52 wake routine — MASSIVE dev):** implemented the entire **nuclear warfare system** — the biggest remaining unported HTML system (silos were buildable but decorative; nothing could arm, fire, or detonate). New `scripts/sim/nuclear.gd` (`SimNuclear`): silo arm/disarm toggle (HTML btn-arm-nuke), map target mode (HTML nukeTargetMode; tapping the armed silo stands down), `fire_nuke` (ballistic big-missile ICBM, speed 260, dmg 900, splash 720, only anti-nuke batteries can intercept — HTML onlyAntiNuke), HTML-verbatim `detonate_nuke` (R 720; units 700*fall+100 with fall>0.25 outright kill, 480*fall knockback, rim ignite; buildings 600*fall+80; 40 seeded fires; 240 s radiation zone r 396→828; 90 s fallout r 864), HTML-verbatim `radiation_at`, radiation tick (rad suits + race-flavored bubbles, drain at rad>0.65, 4 s suit grace), 120 s silo cooldowns, save/load round-trip. Wired: `combat.nuclear` hook in `_resolve_hit`, world construct/tick, save_system, HUD ARM/DISARM button on the player's own silo selection + target-mode tap routing in `_on_tapped`. Visuals (2026-10-04 quality rule): `CombatFX.nuke_blast` (white flash → fireball → mushroom column, dual HTML-verbatim shockwave rings, nuclear crater with green rim, 55 irradiated scorch stains, fallout rain), ICBM missile projectile art, `RadiationOverlay` pulsing green haze (HTML rad_haze pulse verbatim). Deliberate HTML parity: the AI never fires nukes (no aiThink nuke code exists). `tests/test_nuclear.gd`: 76/76 green. iPhone acceptance pending per standing rule.
**Session 2026-10-04 (09:24 wake routine):** full suite — **84 suites, 5,584 checks, 0 failures**. Nuke silo art upgrade under the 2026-10-04 visual-quality rule: it drew as a generic box+roof. New `_nuke_silo` arm in `scripts/world/building_node.gd` ports the HTML's procedural drawBuilding nuke_silo branch verbatim (fix79) — olive block #556b2f (ink outline + soft top highlight), green dome ellipse #2e7d32 rising from the roofline, 'SILO' pill label (ASCII via ThemeDB.fallback_font, tofu rule intact). PIL mock render verified readability at game scale. New `_test_nuke_silo` in `tests/test_resource_building_art.gd` (dispatch, no-sprite, programmer-art path, size still 30, blueprint no-arm): **110/110 green**. No export/Drive upload this run — a sibling job was mid-delivery (paper-map LOD + clock safe-area build) and this change ships with the next scheduled export. iPhone acceptance pending per standing rule.
**Wave 2 port:** 2026-10-03 — 7 port agents + integration (below). Baseline: 68 MISSING, 54 PARTIAL → after wave 2: ~8 MISSING, ~22 PARTIAL.
**Session 2026-10-04 (08:00 massive-dev):** full suite — **83 suites, 5,464 checks, 0 failures**. Implemented **player + AI town founding** — HTML fix79 parity: the original's 240-frame sweep gives every completed hall/townhall a unique city name via `drawUniqueCityName()` (pool-tracked, `Newhold <100-999>` fallback). The port only dealt city names at world spawn, so player-built town halls and AI-founded settlements never became towns (no registry entry, no paper-map label, no per-town housing-cap accounting, conquest prompts fell back to "this settlement"). New `scripts/sim/towns.gd` (`SimTowns`): 4 s sweep over completed halls — near an existing same-faction town (500px) the hall JOINS it (rebuilds don't mint towns); far away and under `Config.TOWNS_PER_FACTION` (3) it FOUNDS via `game.found_town()` with a unique `Config.CITY_NAMES` name; past the cap the hall is adopted under the nearest town. Founding publishes a Gazette Chronicle story (drives the unread-news badge) + seeds a hearsay rumor. Wired in world.gd (construct + tick) and game_state.gd (`var towns_sys`). Also fixed a latent save/load bug found along the way: JSON round-trips turned towns-dict keys into strings, breaking typed `for tid: int` loops and `towns.has(int)` after any load — save_system.gd now normalizes town keys to int on restore. New `tests/test_town_founding.gd`: 50/50 green (found/merge/cap/unique names/pool exhaustion/townhall alias/announce/idempotency/string-key coercion/tick timing/blueprint+dead ignored/save round-trip). Deliberate deviation: HTML also named necropolises, but Godot's necropolis is the undead WAR building, not a town center, so it is excluded (undead centers are town_halls like everyone else). iPhone acceptance pending per standing rule.
**Session 2026-10-04 (07:36 wake routine):** full suite — **82 suites, 5,420 checks, 0 failures**. Fire station art upgrade under the 2026-10-04 visual-quality rule: it drew as a generic box with a red stripe ("just a house"). New `_fire_station` arm in `scripts/world/building_node.gd` ports the HTML's procedural fire_station verbatim (fix79 drawBuilding) — red block #ef5350, dark-red overhanging roof band #b71c1c, two dark garage bays #212121, gold 'FIRE' label #ffd54f (ASCII via ThemeDB.fallback_font, tofu rule intact). PIL mock render verified readability at game scale. Extended `tests/test_resource_building_art.gd` with `_test_fire_station` (dispatch, no-sprite, programmer-art path, size 38, blueprint no-arm): **35/35 green**. Also fixed the stale building_node.gd docstring (farm/dock/spire listed as M3 silhouettes post-06:50). Web export rebuilt to canonical `~/workspace/exports/web/`, `fix-ios-zoom.sh` applied, hard gate `grep -c "ios-zoom-fix" = 1` on disk AND inside the zip; packaged `cursing-gnomes-godot-fire-station-art.zip` (151,343,339 bytes, 9 files at zip root, `unzip -t` clean) and uploaded to Jeremy's Drive per his standing "send it to me" (itch.io upload stop order from 01:15 still in effect — NOT uploaded to itch.io). iPhone acceptance pending per standing rule.
**Session 2026-10-04 (05:35 wake routine):** fixed the Forge-Your-World 3D card carousels never snapping after a drag — `_car_tick` existed in `scripts/ui/world_setup.gd` but nothing called it (`_process` only handled the preview debounce), so cards sat off-center after every swipe. Both carousels now tick through `_process` (purely additive, mirrors main_menu.gd's faction-picker tick). New `_test_snap_ease` in `tests/test_worldgen_carousel.gd` (snap target + valid selection, tick-driven convergence <0.01 on both carousels, `_process` wiring guard): **66/66 green**. Web export rebuilt to canonical `~/workspace/exports/web/`, `fix-ios-zoom.sh` applied, hard gate `grep -c "ios-zoom-fix" = 1` on disk AND inside the zip; packaged `cursing-gnomes-godot-carousel-snap.zip` (151,330,990 bytes, 9 files at zip root, `unzip -t` clean) and uploaded to Jeremy's Drive per his standing "send it to me" (itch.io upload stop order from 01:15 still in effect — NOT uploaded to itch.io). iPhone acceptance pending per standing rule.
**Session 2026-10-04 (04:05 wake routine — MASSIVE dev):** full suite — **76 suites, 4,758 checks, 0 failures**. Audit re-verified: the only genuinely-open item is still **shared vision (allies)** — MISSING in both builds, parked as Jeremy's design decision (fog of war would invent mechanics, not port). Built the biggest remaining player-facing gap instead: **"First Reign" guided tutorial** (new `scripts/ui/tutorial.gd` TutorialDirector) — the port shipped with zero onboarding. 8 steps over a real new game (welcome, camera, select, build, gather, train, phone, done): offer card 2s after game start (never in sandbox/adventure, "No thanks" never nags again), top banner with gold-on-wood styling (auto-sizes for portrait/landscape, no glyphs), pulsing map-space highlight ring on the select step, Skip on every step, out-of-order actions auto-complete later steps, completion persisted to user://tutorial.cfg. Wired in world.gd (construct + tick + maybe_offer in configure) — purely additive, no sim/UI logic touched; main_menu.gd untouched (2.5x conflict still Jeremy's call). test_tutorial.gd 58/58 green (full flow, out-of-order, enemy-faction events ignored, no-double-offer, cfg snapshot/restore).
**Session 2026-10-04 (03:25 wake routine):** full suite — **74 suites, 4,704 checks, 0 failures**. Completed + verified Jeremy's 03:05 menu scaling strip-down ("Leave it alone and let it do what it's gonna do stop adding all that shit" — no custom scaling, Godot stretch handles it). The rewrite had dropped the `_refit_vbox = v` assignment in `_new_screen()` (`scripts/ui/main_menu.gd`), so `test_menu_scroll.gd` hit `inner == null` → script error at line 93 → the process idled forever without `quit()` (two sibling runs found hung the same way; the failure mode is a hang, not a red suite). One-line fix restored it: test_menu_scroll 10/10, test_menu_smoke 98/98, test_worldgen_carousel 53/53, full suite green. Web export rebuilt to canonical `~/workspace/exports/web/`, `fix-ios-zoom.sh` applied, hard gate `grep -c "ios-zoom-fix" = 1`; packaged `cursing-gnomes-godot-menustrip.zip` (151,292,959 bytes, 9 files at zip root, `unzip -t` clean, zoom marker verified inside the zipped index.html) and uploaded to Jeremy's Drive per his standing "send it to me" (itch.io upload stop order from 01:15 still in effect — NOT uploaded to itch.io). iPhone acceptance pending per standing rule.
**Session 2026-10-04 (01:25 wake routine):** full suite — 60 suites, all green. **Thicc Moose rear-view butt sprite** (Jeremy's verbatim 2026-10-04 ask: the mooning moose used its regular side profile, which "just read as the moose standing there"). New AI-generated chibi pixel-art rear view (`assets/art/animals/moose_butt.png`, style-matched to moose.png): big round butt, stubby tail, back legs, antlers peeking from behind. `UnitNode.set_mooning()` now swaps to the butt sprite when mooning starts and restores the side profile + base pose when it ends (world sync already drives it from `combat_state == "mooning"`); the existing butt-shake gained squash-and-stretch. test_moose_butt.gd: 16/16 green (art ships, swap, restore, non-moose no-op, shake timing). Also verified the delegated slur system matches Jeremy's 01:15 spec: hard-r n-word = instant war from ANY faction incl. gnomes (no thresholds, no enemy-of-my-enemy exception); fantasy race slurs pile on (100 insults/faction, 500 total) when the reacting court hates the slurred faction, instant war otherwise; Gazette prints the player's exact typed quote + names the reporting NPC + roasts; Squabble threads discuss it. test_diplomacy.gd slur coverage green.

**Session 2026-10-04 (00:05 wake routine — MASSIVE dev):** ported the HTML **aiThink AI faction brain** — the biggest remaining unported system (59KB in the HTML, zero Godot equivalent; AI factions previously never built, trained, or developed). New `SimAIDirector` (`scripts/sim/ai_director.gd`): round-robin think (one AI faction per 2.8s, player skipped — auto-building for the player would fight the build UI), AI bank funding (verbatim floors/drip), analyzeFactionState → maneuver (expand/fortify/raid/defend/eco_war), siege muster + gazette alarm on escalation, raid marches on the war enemy (HTML marched on neutral halls incl. the player — fixed to the actual war enemy), eco-war mine contests, M-zone fort garrisons, AI construction drip, aiBuildEssentials strategic build queue (per-maneuver priorities, max 2/think, 8-unfinished cap, house hard-gate, per-town smith/fire/hall), aiBuildTick62 agri plan (farm/farmhouse/windmill; undead flesh_farm), the full military-industrial training doctrine (workers → barracks roster rotation → foundry artillery top-up + rush-finish seed → guard towers → AA → nuke silo → medic camp → doctors → horse stables), ensureAirDefenses (want 8, first 2 free). Deliberate skips (documented in-file): mortar_team/field_medic training (jobs don't exist in Godot), foundry credit-queueing, horse purchasing (no buyHorse), cattle_pen (no Godot building). Wired in world.gd (construct + tick) and save_system.gd (round-trip). test_ai_director.gd: 40/40 green.

**Session 2026-10-03 (21:24 wake routine):** full suite — 42 suites, 3343 checks, all green. De-flaked `test_artillery_undead.gd` "hunger: critical hunger goes feral" (`seed(20261003)` before the feral sampling loop; the transition is RNG-gated per tick at `randf() < delta * 0.25` in undead.gd, flaked ~1/150 runs — sim untouched, 3× 139/139 green). Verified backlog: the only genuinely-open item is **shared vision (allies)** — MISSING in both builds (HTML has no fog of war; its "fog"/"shroud" hits are weather text + name-gen word lists). Fog of war would be an invented mechanic, so it's parked as a design decision for Jeremy, not a port. No game-code change this run → no export/itch upload (test-only fix; slot left alone amid today's concurrent-run churn).

**Session 2026-10-03 (17:24 wake routine):** full suite — 32 suites, 3021 checks, all green. REMOVED the dead Stripe microtransaction system per Jeremy's company motto "No microtransactions. No bullshit." — SimBoosts (`scripts/sim/boosts.gd`), BoostShopUI (`scripts/ui/boost_shop.gd`), and the web payment files (`web/cg-payments.js`, `web/payment-success.html`) were fully unreferenced dead code (no UI opened the shop, no tests covered it). Trashed recoverably (30-day expiry). Sandbox director `boost_race` is a free in-game debug tool, NOT a purchase — kept. No player-visible change; web export NOT rebuilt (dead-code deletion only).

**Session 2026-10-03 (wake routine):** full suite run — 30 suites, all green, 0 failures. Fixed test_racist_outrage.gd missing quit() on success path (engine idled forever after pass). Wired sandbox observe mode (empty player faction → SimSandbox director + director HUD + camera aim + sim-complete end screen); test_sandbox.gd 37 checks. Backlog re-verified — most PARTIAL/MISSING entries were stale; corrected above.

## Ported in wave 2 (2026-10-03) — 7 agents, all tests green

- **Armies & warfare** (`sim/army.gd`, `ui/army_tab.gd`): downed/knockout + medic revive, combat micro-tactics (under-fire cover/flank), war horn SFX, army stances (auto/guard/lead), draft/muster/deploy, warlord (promotion + aura + cleave), AI offensive campaigns, war-weariness collapse tick, noisy war intel, conquered-hall keep-or-rename, faction-correct starting weapons, weaponsmith 3-tier upgrades, gov_role assignment.
- **Artillery** (`sim/artillery.gd`): field/grape cannons, siege/jumbo rockets, 2-crew parked vehicles, grape shot, cook-off, AA tower + anti-nuke interception.
- **Undead death economy** (`sim/undead.gd`): soul essence (ledger-mirrored), corpse harvesting, necromancer raises, ghoul feeding, flesh pit → food, plague clouds, elite roster + soul costs, infection on hit.
- **Government & social** (`sim/policies.gd`, `sim/hearsay.gd`): full policies (7 governments, tax, anarchy, guard tiers, curfew, borders, festivals, guild quotas, approval/strikes/riots), NPC block/unblock, hearsay gossip engine, Gazette Chronicle/Messages/Policies tabs, event-driven Squabble posts, domestic court petitions (fixed silent type-error that killed all domestic generation), petitioner chat.
- **World & economy** (`sim/seasons.gd`, `sim/farming.gd`, `sim/industry.gd`): fantasy calendar + 6-condition weather sim, monthly disaster forecast (incl. Count Bastard), seeds economy + seed shops, farm plot plant/water/harvest chain, industrial zone oil production, Captain Funky Pants trader, tap-tree 'Cut tree' gather orders, paper-map town labels, day-length desync fix.
- **Modes & screens** (`ui/world_setup.gd`, `ui/end_screen.gd`, `ui/debug_overlay.gd`, `ui/unit_info.gd`, `systems/autosave.gd`): Forge-Your-World setup (Back/Reroll/Start + live terrain preview), victory/defeat/sandbox end screens, periodic autosave + save-on-quit, adventure gender picker, debug overlay + `?debug=1`, full unit dossier panel, credits rewritten (Ethos lead, Jeremy co-lead, no Meta).
- **Buildings & walls** (`sim/territory.gd`, `buildings/wall_drag.gd`, `buildings/starfort.gd`, `buildings/border_walls.gd`): 21 new building types (tome_library, necropolis, per-race restaurants, inn/hotel, cannon foundry, camps, nuke silo, pier, garden…), 180 building cap, territory claims, build-menu category tabs, AoE2 drag-to-place walls, AI border-wall rings (ask-once policy), star forts with bastions + gaps, bathrooms in all 36 interior plans, 25-bunk barracks.
- **Workers & housing** (`sim/hiring.gd`, `sim/housing.gd`): work-priority orchestration, guild-master auto-hiring (4s sweep), adviser/watchcaptain officers + cubicles, desk claim/release, shop staffing hours, roadbuilder road painting, barracks training queues, 15+15 housing caps, homeless → countryside migration, survival-craft homesteads.
- **Integration**: all systems ticked in world.gd, 11 new event-bus signals, save/load for every subsystem, HUD retargets (Policies button, army tab, build tabs, unit dossier), wall-drag camera routing, drawer buttons all wired (incl. quit-to-menu), soul_essence in resource ledger, policy multipliers applied (work/build/train/trade/guard), paper-map zoom threshold fixed (MIN_ZOOM 0.3 → 0.16).

**Test totals:** 22 suites, ~2,300 checks, all green (7 new suites: test_army 55, test_artillery_undead 139, test_policies 126, test_seasons 104, test_modes 55, test_buildings2 103, test_workers 88).

## Remaining gaps (honest backlog — verified 2026-10-03)

Several backlog entries below were stale: re-verified against code + green
tests this session. Corrected statuses are marked [VERIFIED].

- **Shared vision (allies)** — MISSING in both builds (no fog of war anywhere); Godot docstring aspiration only.
- **Volcano disaster** — [VERIFIED] HAVE: disasters.gd ports HTML VOLCANO80/91 (verbatim numbers, timer 600–1500s, site rules, shove, hardening, minerals); test_disasters.gd 27 checks green.
- **Faction military rosters** — [VERIFIED] HAVE: all 5 factions (incl. undead) with HTML-verbatim stats, gates, and unique abilities; test_faction_rosters.gd 150 checks green.
- **Rivers generation overhaul** — [VERIFIED] HAVE: map_gen.gd downhill watershed carving (land springs, coast termination, no ocean continuation, connected paths, waterfalls only at height changes, old-save sanitation); test_rivers.gd 38 checks green. Rivers *visual* overhaul — [VERIFIED] HAVE (2026-10-03): carved-into-ground bake (banks, depth shading, foam edges via DEPTH_FULL_PX/FOAM_BAND_PX/BANK_BAND_PX), animated waterfalls (scrolling falls face, foam burst + ring, mist particles), drifting foam flecks downstream — scripts/world/river_renderer.gd + assets/shaders/water_flow.gdshader; test_rivers.gd covers bake/banks/foam/falls/foam-pool.
- **Sandbox observe mode** — [VERIFIED] HAVE (2026-10-03): sandbox menu entry now boots observe-only (empty player faction arms SimSandbox; HTML sandboxMode parity) — previously booted a playable gnomes game. Director HUD (phase/clock/weather chips, faction focus buttons + census, Focus/Boost/Troops/Ally/War-all/War-vs/Peace, pause, menu, log), camera aim, sim-complete end screen; test_sandbox.gd 37 checks green. **Director weather/time/disaster/tools tabs ported 2026-10-03 (wake routine):** SimSandbox.set_weather (clear/cloudy/rain/storm/snow → seasons sim, the single source of truth), set_time_of_day (day→10:00, night→22:00, day_number re-synced), skip_day (+1 day, lands 08:00), spawn_disaster (bandits/butt/moose/lizard/cat/bastard/wizard → Godot monster spawners; fire → 8 wildfire ignites; volcano → site-validated eruption; singleton/fire-cap rules respected), clear_fires (extinguishes all + clears building on_fire), force_expand (resource boost; HTML's zone/civ-work forcing has no Godot counterpart yet). HUD: 🌤 weather row, 🕐 day/night/+1-day, ☄ 9-button disaster row, 🛠 expand/clear-fires tools row. test_sandbox.gd 59 checks green. **d_nuke intentionally unported** — nukes are vehicle-fired via artillery.gd, no detonate-at-point API exists. war_all/force_peace_all are the Godot equivalents of break_peace/start_peace (no global war-phase state).
- **Adventure faction-unique hero jobs / starting inventory** — [VERIFIED] HAVE: adventure.gd HERO_JOB_PATHS + faction-unique starting kits (Jeremy 2026-10-03); test_adventure.gd 108 checks green.
- **Settings actually applied** — [VERIFIED] HAVE: world.gd applies graphics tier, ground detail, show_labels, tree_sway (MapProp.sway_enabled), audio, debug overlay, ai_aggression, autosave; test_settings_port.gd 65 checks green.
- **Crime system** — [VERIFIED] HAVE: SimCrime (records, trait scan, daily needs-gated rolls, CRIME55 sentences, guard response, trials, crimewave petitions); test_crime.gd 133 checks green.
- **Farm animals** — [VERIFIED] HAVE: SimAnimals (chicken/cow/pig/sheep/goat/boar, barn/coop attach, feeding, daily food yield, leash); test_animals.gd 39 checks green.
- **Civic gov_* buildings** — [VERIFIED] HAVE: buildings.gd GOV_OFFICE_TYPES (office/treasury/war/justice) with interiors.
- **Fishing boats** — [VERIFIED] HAVE: fishing_dock trains fishing_boat + war_ship (boat_spec, fish periods); test_buildings2.gd covers.
- **Bridge tool** — [VERIFIED] HAVE player-side: bridge_drag tool, bridge_at deck lookup, per-segment costs; AI bridge-building (HTML waterxAITick) — [VERIFIED] HAVE (2026-10-03): scripts/sim/water_crossing.gd ports the bridge path verbatim (span 160–900px, ±70px run extension, 30px segments, >2 placed = project, 180s fail cooldown, 300s stale, bridge-done within 240px of midpoint, player skipped, ~1.1s/race round-robin tick); test_water_crossing.gd 31 checks green. **Ferry-assault path (span > 900px, waterxOrderFerry) — [VERIFIED] HAVE (2026-10-03): scripts/sim/ferry.gd ports the WATERX ferry module verbatim (boatCapacity 8/4, 300px invites, military-first sort, never auto-grabs the player hero, 25s boarding timer, 48px embark, 600px missed-boat rule, 120px arrival, ±17/±11px ride offsets, ±30px landing jitter, nearestLand ring 40..880/40px margin, nearestWater ring 40..1360/80px margin, embarked passengers ride the boat, disembark_all save-safety); SimWaterCrossing takes an optional SimFerry and orders free boats at the nearest water to the enemy hall with the '<Race> launches a ferry assault' gazette line; world.gd constructs + ticks SimFerry; test_ferry.gd 79 checks green.**

## Summary

| Domain | HAVE | PARTIAL | MISSING | Total |
|---|---|---|---|
| UNITS/JOBS | 12 | 7 | 14 | 33 |
| COMBAT | 20 | 4 | 24 | 48 |
| NPC/SOCIAL | 14 | 5 | 4 | 23 |
| BUILDINGS | 8 | 16 | 10 | 34 |
| WORLD/ENV | 4 | 10 | 8 | 23 |
| MODES/SAVE/AUDIO | 8 | 12 | 7 | 27 |

**Total gaps:** 67 MISSING, 54 PARTIAL

## Ported in this session

1. **Doppler/spatial SFX** (HTML `playSpatial` parity) — distance attenuation, stereo pan, Doppler pitch from radial velocity. Wired to projectiles.
2. **Adventure save wiring** — `SaveSystem.snapshot/restore` now include adventure state; HUD drawer Save/Load work.
3. **Dungeon markers** — purple diamonds on paper map for uncleared dungeons.
4. **Race-based combat modifiers** — HTML RACES table (ogre 550hp/1.9x dmg, gnome 160hp/1.4x/1.75x magic, etc.).
5. **Named regions/cities** — 44 region + 45 city names from HTML pools; towns use real city names.
6. **Work hours/shifts** — HTML shift table (military 6-18, shopkeeper 8-18, doctor 7-19, firefighter 24/7, workers 7.5-16.5).
7. **Storage caps** — HTML baseline caps + stock building bonuses.
8. **AI water-crossing bridge building** (2026-10-03, HTML `waterxAITick` bridge path) — `SimWaterCrossing` (`scripts/sim/water_crossing.gd`): longest-water-run span detection (40px samples, verbatim), per-race round-robin tick (~1.1s/race, player skipped), war-gated (nearest hostile hall), bridge projects via the shared `BridgeDrag` tooling (70px run extension, 30px segments, quiet per-segment placement, >2 = project + "engineers are bridging the strait" gazette line), 180s fail cooldown, 300s stale clear, bridge-done within 240px of midpoint. Wired in world.gd (construct + tick). **Ferry-assault path (span > 900px) ported 2026-10-03 (wake routine) — see entry 10 below.** test_water_crossing.gd: 31 checks green.
9. **Sandbox Expand = boost + zone development** (2026-10-03, HTML `sbForceExpand` parity) — `SimSandbox.force_expand` now calls `ensureZonesAndDevelop`/`forceCivWork` equivalents: develops ONE empty faction zone lot per press (HTML one-site-per-call rule), serialized behind incomplete sites (no new lot while a site is under construction — crews finish first; Godot worker AI keeps builders assigned, the HTML ensureConstructionCrew role). Zone pickType priorities verbatim (R→house; C→restaurant/weaponsmith/clinic/inn; I→stock_*/storage/cannon_foundry/fire_station; M→shooting_range/armory/barracks/faction war unique/medic_camp/aa_tower/field_camp), Jeremy's 15-house town cap enforced via SimHousing (or manual count in fixtures), water-footprint guard (HTML footprintInWater), `can_place_at` overlap + territory checks, town_id from nearest faction town. `forceCivWork`'s housing nudge intentionally not duplicated — SimHousing owns it. test_sandbox.gd: 62 checks green (zone painted → one house blueprint; second press while incomplete → no new lot).
10. **Naval ferry/transport** (2026-10-03, HTML WATERX ferry module) — `SimFerry` (`scripts/sim/ferry.gd`): boatCapacity (war_ship 8, else 4), order_ferry (300px same-faction non-boat invites, military-first sort via JobDefs.is_military/is_leader, player hero never auto-grabbed, 25s boarding timer, 'All aboard!' bubble via unit_said), embark (48px, ±17/±11px ride offsets), boarding→sailing→disembark state machine (full/timeout/incoming-gone rules, 600px missed-boat rule, 120px arrival, ±30px landing jitter, 'Casting off!' bubble, 'Ferry arrived — troops ashore' gazette), nearest_land (ring 40..880, 40px margin) / nearest_water (ring 40..1360, 80px margin), passenger riding + lost-boat release, disembark_all save-safety, sailing at boat speed × BOAT_SPECS speed_mul. Passengers/boat refs stored as unit ids so voyages survive JSON save/load (verified round-trip). SimWaterCrossing takes an optional SimFerry: span > 900px orders a free boat at the nearest water to the enemy hall with the '<Race> launches a ferry assault' gazette line (bridge path untouched; unwired waterx keeps the old quiet no-op). world.gd constructs + ticks SimFerry and passes it to SimWaterCrossing. Player-side ferry ordering UI is out of scope (order_ferry is public for future HUD use). test_ferry.gd: 79 checks green.


## UNITS/JOBS

- [PARTIAL] Per-faction unit stat profiles
- [PARTIAL] Faction military rosters
- [MISSING] Faction-correct starting weapons
- [MISSING] Shop weapon upgrades
- [PARTIAL] Job registry
- [MISSING] Worker economy orchestration
- [PARTIAL] Roadbuilder behavior
- [MISSING] Work hours / daily routine
- [MISSING] Guild master actively hires
- [MISSING] Advisor jobs
- [MISSING] Desk claiming
- [MISSING] Shop staffing (business hours)
- [PARTIAL] Firefighter auto-dispatch + fire trucks
- [PARTIAL] Guard auto-staff (2 per guard house)
- [MISSING] Barracks: 25 beds, military cap
- [MISSING] Barracks training queue
- [MISSING] Star forts / military bases
- [PARTIAL] Faction-unique war buildings
- [MISSING] Housing economy (15/town, 15 countryside/faction)
- [MISSING] Homeless → countryside migration
- [MISSING] Survival-craft homestead
- [HAVE] Unit info panel (2026-10-03: floating top-left gold-border popup — name, faction/job/gender, city, Currently activity, HP + urge bars, Traits, honest memory lines, housing, weapon/role/DMG; test_modes.gd 81/81)

## COMBAT

- [MISSING] Race-based combat modifiers
- [MISSING] High-ground damage edge (+15%/level, max +45%)
- [MISSING] Downed/knockout state (not-dead)
- [MISSING] Combat micro-tactics (flee/reposition under fire)
- [MISSING] Artillery vehicles (field_cannon, grape_cannon, siege_rocket, jumbo_rocket, anti
- [MISSING] Artillery crews (2-crew parked vehicles)
- [MISSING] Grape shot mechanic
- [PARTIAL] ⚔ Army tab UI
- [MISSING] Army stances (auto / guard / lead)
- [MISSING] Draft / muster / deploy for war
- [MISSING] Warlord / battlefield commander
- [MISSING] AI offensive campaigns (armies march on enemy towns)
- [PARTIAL] War-weariness / collapse tick
- [MISSING] War horn SFX on combat start
- [PARTIAL] Messenger war warnings
- [MISSING] War intel / noisy enemy estimates
- [MISSING] Conquered-hall keep-or-rename prompt
- [MISSING] Named regions (44-name pool)
- [MISSING] Named cities (48-name pool)
- [MISSING] Paper-map name labels in faction color
- [MISSING] Soul essence resource
- [MISSING] Corpse harvesting system
- [MISSING] Necromancer raises corpses
- [MISSING] Ghouls feed on corpses
- [MISSING] Flesh pit converts corpses to food
- [MISSING] Plague clouds
- [MISSING] Undead elite roster + soul costs
- [PARTIAL] Faction war buildings (uniques)

## NPC/SOCIAL

- [PARTIAL] Contacts: pinned 'My Government' + user-added only
- [PARTIAL] Royal Court: named petitioners with roles/motives
- [PARTIAL] Two-way chat (personality + mood memory)
- [PARTIAL] Royal Gazette: Chronicle / Messages / Policies tabs
- [MISSING] Policies system (tax, anarchy, curfew, borders, governments)
- [MISSING] Hearsay
- [MISSING] Shared vision (allies)
- [MISSING] Blocking NPCs (block/unblock = silence)
- [PARTIAL] Squabble posts from real sim events

## BUILDINGS

- [PARTIAL] Faction uniques + race lock
- [MISSING] Faction-flavored starting weapons
- [MISSING] Per-race restaurants
- [PARTIAL] Hospitality (inn, hotel, bathhouse, camp)
- [PARTIAL] Military buildings
- [PARTIAL] Civic/government
- [PARTIAL] Water buildings
- [MISSING] Misc placeables
- [MISSING] Building hard cap 180 (C65: 15/town × 12 towns)
- [PARTIAL] Category tabs
- [PARTIAL] Military → military district routing
- [MISSING] Territory claim (foreign builds blocked)
- [PARTIAL] Construction speed model
- [MISSING] Builder crew visuals/assignment
- [PARTIAL] Wall construction staging
- [PARTIAL] AoE2 drag-to-place walls
- [MISSING] Border walls (AI walls its land)
- [MISSING] Star-fort military bases
- [MISSING] Wall topology/towers
- [MISSING] Weapon upgrades (3 tiers at weaponsmith)
- [PARTIAL] Guild hall: auto-spawns guild master + hiring
- [PARTIAL] Barracks: trains soldiers; 25 bunks; military cap
- [PARTIAL] Interior system: enter/exit, floor plans, furniture shop, arrange mode
- [PARTIAL] Bathrooms in all buildings (toilet/sink/tub rule 2026-09-28)
- [PARTIAL] Bed capacity tied to bunks
- [PARTIAL] Rooms (named zones)

## WORLD/ENV

- [MISSING] Storage caps / stock buildings
- [MISSING] Player-directed gather orders ('Cut tree')
- [MISSING] Seeds economy
- [PARTIAL] Crop/farm production chain
- [MISSING] Industrial oil production
- [PARTIAL] NPC/faction trading
- [PARTIAL] Weather system
- [PARTIAL] Day/night cycle
- [MISSING] Seasons + fantasy calendar
- [PARTIAL] Disaster roster
- [MISSING] Disaster scheduling (monthly forecast)
- [PARTIAL] Rivers — generation (watershed)
- [PARTIAL] Zoning tool (🗺 Zone tab)
- [PARTIAL] Paper map
- [MISSING] Named regions (44-name pool)
- [MISSING] Cities (48-name pool)
- [PARTIAL] Border walls per region
- [PARTIAL] Camera: drag/pinch/zoom limits

## MODES/SAVE/AUDIO

- [PARTIAL] New Game flow: faction select → character/name → world gen
- [MISSING] World setup screen: Back / Reroll / Start Game / Got It + worldgen preview
- [PARTIAL] Continue (resume)
- [PARTIAL] Saved Worlds: continue / overwrite / delete
- [MISSING] Autosave on tab close
- [PARTIAL] Save format version
- [PARTIAL] In-game drawer Save/Load/Worlds/Settings/Menu
- [PARTIAL] Sandbox Observe (no faction, pure autonomous sim)
- [MISSING] Adventure: gender picker (♂ Male / ♀ Female)
- [PARTIAL] Adventure: faction-specific hero jobs
- [PARTIAL] Adventure: hero starting inventory
- [MISSING] End screen (VICTORY / PLAY AGAIN / MAIN MENU; sandbox SIMULATION COMPLETE)
- [PARTIAL] Settings list
- [PARTIAL] Settings actually applied
- [MISSING] Debug overlay (FPS, tick timings, entity counts)
- [MISSING] `?debug=1` URL param
- [MISSING] Doppler pitch from radial velocity
- [PARTIAL] Credits screen
- [PARTIAL] Hearsay screen

