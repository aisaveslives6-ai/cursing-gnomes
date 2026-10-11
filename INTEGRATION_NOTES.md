# Port-wave integration notes (parent agent scratch — not user-facing)

## INTEGRATION COMPLETE 2026-10-03
All 7 port agents' HOOKS applied by parent. Full suite: 22 files, all green.
Editor import: clean. Fixes made during integration:
- undead.gd soul: internal-canonical + ledger mirror (kept test save contract)
- farming.gd:256, weather.gd:128, disasters.gd:287: Object.get() 2-arg → direct var access
- camera MIN_ZOOM 0.3 → 0.16 (paper map could never trigger)
- world._tick_services now ticks ALL service buildings (guild hall/guard house were dead)
- work.gd: repaired a clobbered _assign_farm signature; added to_plot/plot_chore states, work_mult
- combat.gd: splash_mul edge falloff, infection hook, guard_strength_mult
- Drawer: worlds/settings/main_menu/disasters/resource_mgmt all wired; quit_to_menu_requested → main.gd
- main.gd: world_game_requested, 5-arg adventure start (gender), show_worlds entry
- adventure.gd: hero_gender var + save/load; start() takes gender
- Paper-map/zoom, wall-drag camera routing (wall_pressed/moved/released signals)

## Port agents dispatched 2026-10-03 (all depth-2, completed)
1. COMBAT/ARMY — combat.gd + spawner.gd owned; creates army.gd, ui/army_tab.gd, tests/test_army.gd
2. ARTILLERY/UNDEAD — creates sim/artillery.gd, sim/undead.gd, tests/test_artillery_undead.gd (spawner via public API only)
3. SOCIAL/POLICIES — phone.gd + phone_ui.gd + royal_court.gd owned; creates sim/policies.gd, sim/hearsay.gd, tests/test_policies.gd
4. WORLD/ECON — resources.gd + disasters.gd + paper map owned; creates sim/seasons.gd, sim/farming.gd, tests/test_seasons.gd
5. MODES/UI — menu files owned; creates ui/world_setup.gd, ui/end_screen.gd, ui/debug_overlay.gd, ui/unit_info.gd, tests/test_modes.gd
6. BUILDINGS/WALLS — buildings.gd + buildings/* owned; creates buildings/starfort.gd, buildings/border_walls.gd, sim/territory.gd, tests/test_buildings2.gd
7. WORKERS/HOUSING — worker AI + jobs.gd owned; creates sim/hiring.gd, sim/housing.gd, tests/test_workers.gd

Shared files NOBODY edits (hooks come in agent reports): world.gd, hud.gd, event_bus, save_system, main.gd.
Parent applies HOOKS, runs FULL suite, fixes fallout, updates AUDIT_REPORT.md.

## Completed port agents (reports received)
### Combat/Armies (done, 55 new + 67 combat + 516 jobs_buildings + 50 audio green)
Files created: scripts/sim/army.gd (SimArmy), scripts/ui/army_tab.gd, tests/test_army.gd
Files edited: scripts/sim/combat.gd (downed/knockout + bleed-out 60s, micro-tactics, war horn emit, firearms tiers, warlord aura, attacker_id attribution), scripts/sim/spawner.gd (faction starting weapons, weapon_level=0, guild_master gov_role), scripts/audio/audio_manager.gd (war_horn synth)
HOOKS to apply:
- world.gd: member `var army: SimArmy`; in _ready after combat init: army = SimArmy.new(game); army.diplomacy = game.diplomacy; game.set_meta("army", army); tick after combat.tick: combat.tick_medics(delta); army.tick(delta)
- hud.gd: replace army tab body (~482-489) with ArmyTab.build(game, _side_vbox)
Adaptations: knockout only for fighter victims with known attacker; warlord = promotion flag not new job; AI war campaigns 35% daily roll; trench visuals not ported (sim-only cover flag); conquest town-rename path untested end-to-end
NOTE: test_audio.gd hung once on headless audio-server (isolated synth test fine); if it recurs it's the play_sfx headless path

### Workers/Hiring/Housing (done, 88 new + 516 jobs_buildings + 59 minds + 64 zoning + 30 art green)
Files created: scripts/sim/hiring.gd (GuildHiring), scripts/sim/housing.gd (SimHousing), tests/test_workers.gd
Files edited: scripts/sim/work.gd (SHIFTS for new jobs, to_station/working states, desk claim/release, _faction_priority, roadbuilder roads, move_unit), scripts/sim/jobs.gd (11 new jobs, WORKPLACES, OPEN_HOURS, slots_for), scripts/core/config.gd (BARRACKS_BEDS=25)
HOOKS to apply:
- world.gd per-tick: hiring.tick(delta, WorkerAI.hour_of_day(gs)); housing.tick(delta); once after worldgen/load: housing.adopt_housing()
- save_system.gd: unit fields station/_desk/home/craft/_homestead/coins/mind.gov_role/_country_move/_country_home/_buying_home/_road_order; building fields desks/train_queue/for_sale/price/owner_unit/residents/countryside; WorkerAI roads
- Verified already ported (not duplicated): firefighter dispatch (disasters.gd tick_firefighter), guard auto-staff (buildings.gd tick_service)
Gaps: fisher trainable at fishing_dock but no such building type yet; shift-gating for station/desk jobs only (full day/night labor rhythm deferred); roadbuilders anchor at nearest completed town hall

### Social/Policies (done, 126 new + 95 phone_interior + 59 minds + 96 diplomacy green)
Files created: tests/test_policies.gd. Files edited: scripts/ui/phone_ui.gd (Policies app, Gazette tabs, petitioner chat Talk button, block/unblock), scripts/sim/royal_court.gd (domestic petition bugfix: untyped Array killed ALL domestic generation; to_dict/from_dict incl. policies), scripts/sim/policies.gd (add_happiness).
NOTE: agent accidentally overwrote phone_ui.gd mid-task but reconstructed it fully and verified — no content lost.
HOOKS to apply:
- hud.gd: retarget "👑 Policies" drawer button + tab from _open_phone_app("diplomacy") → _open_phone_app("policies")
- save_system.gd: snapshot/restore "court" (incl policies), "phone" (threads/posts/sort/added/blocked), "hearsay"
- main_menu.gd: _show_hearsay shows _hearsay_lines when non-empty; add set_hearsay_lines(); feed from phone.hearsay.hearsay_lines()
- Crime tick: multiply by court_sys.policies.crime_pressure_mult()
- Worker AI: multiply work speed by court_sys.policies.work_mult() (0.7 during strikes)
- Combat/build: guard_strength_mult(), train_speed_mult(), build_cost_mult(), build_speed_mult(), trade_mult()
- Squabble event wiring done inside hearsay.gd via existing bus signals (war_declared, disaster_spawned, unit_died, peace_made, alliance_signed, treaty_broken, tribute_paid)
Gaps: riot mob movement (worker-AI territory); quota threat adjustments need town-threat system; commander_guns petition adapted (no artillery → wall-crew soldiers)

### World/Economy (done, 104 new + 43 sim_core + 37 world + 516 jobs_buildings green)
Files created: scripts/sim/farming.gd, scripts/sim/industry.gd, tests/test_seasons.gd
Files edited: scripts/sim/disasters.gd (monthly forecast, Count Bastard, weather/fire interplay), scripts/world/paper_map.gd (town labels in faction color), scripts/world/weather.gd (day-length 600→480 fix)
HOOKS to apply:
- world.gd _physics_process after disasters.tick: tick game.seasons / game.farming / game.industry
- game_state.gd: add seasons/farming/industry vars, new in _init, reset in setup()
- save_system.gd: save/load seasons, farming, industry, disasters dicts
- event_bus.gd new signals: weather_changed, season_changed, disaster_forecast_posted, disaster_forecast_fired, farm_plot_created, farm_harvested, seeds_bought, trader_arrived, trader_left, trade_done, gather_ordered (all emissions has_signal-guarded)
- buildings.gd: add "seedshop" registry entry (commercial/economic, buildable)
- work.gd: farm chores (to_plot/plot_chore states via game.farming), gather orders (to_resource already walks to work_target_pos; on arrival call gather logic for work_site), seed bin top-up
- royal_court.gd: curfew policy effect (crime -40%, -1 happiness/day while active); night via game.seasons.is_night_hour()
- urges.gd: small night/storm mood drift (DESIGN-PORT values)
Gaps: region labels on paper map (no region-ownership data yet); farm animals not ported (no animal system); workplace oil inert until WorkerAI sets unit["workplace"]; oil derrick has no HTML production tick (not ported); pre-existing: paper_map.gd calls _game.get_units()/get_buildings() which don't exist on GameState (units/buildings never drawn); GameState.is_night vs is_night_hour() dual rules.

### Buildings/Walls/Territory (done, 103 new + 516 jobs_buildings + 37 world green)
Files created: scripts/sim/territory.gd, scripts/buildings/wall_drag.gd, scripts/buildings/starfort.gd, scripts/buildings/border_walls.gd, tests/test_buildings2.gd
Files edited: scripts/sim/buildings.gd (21 new types, BUILDING_CAP=180, territory block in can_place_at, BUILD_TABS), scripts/sim/interiors.gd (bathrooms in all 36 plans, 14 new plans), scripts/sim/zoning.gd (BUILDING_ZONE mapping)
HOOKS to apply:
- spawner.gd (combat agent owns): on guild_hall completion spawn 1 guild_master
- world.gd: throttle-tick border_walls.tick(faction, is_player, buildings_sys, wall_drag) ~1/sec; surface border_walls.pending[] prompts; border_walls.answer(name, raise, bs, wall_drag)
- building_placement.gd: wire WallDrag.plan_path/plan_tap ghosts + commit on release; territory check via SimBuildings.can_place_at(..., player_faction)
- save_system.gd: save["border_walls"] = border_walls.to_dict(); load via from_dict; reset_for_new_game() on new game
- hud.gd: build menu tabs via SimBuildings.BUILD_TABS + build_category(btype)
- Note: one transient flaky "doctor: patient healed" fail in test_jobs_buildings (re-run green, timing test, not buildings agent's change)

### Artillery/Undead (done, 139/139 new + 67 combat + 43 sim_core green)
Files: scripts/sim/artillery.gd, scripts/sim/undead.gd, tests/test_artillery_undead.gd
HOOKS to apply:
- resources.gd: add "soul_essence" to Config.RESOURCES + BASE_CAPS (suggest 99999); undead.gd swaps internal store to resources then
- save_system.gd snapshot/restore: "artillery": arty.to_dict(), "undead": undead.to_dict()
- buildings.gd elite training: gate on undead.can_afford_soul(job), call undead.train_elite() before spawn
- melee resolution: call undead.maybe_infect_on_hit(attacker, target) on zombie/plaguebearer hits
- combat.gd _resolve_hit: optionally read p["splash_mul"] (0.75 cannon/grape, 0.9 rocket, 1.0 jumbo)
- world.gd/main.gd: instantiate SimArtillery.new(game, combat) + SimUndead.new(game, combat), tick each frame
- undead.gd already subscribes to bus.unit_died — no signal change needed
WARNING: agent reports main.gd has a pre-existing parse error from another agent's in-progress script ("Cannot infer the type of \"saw\"") — find and fix in integration.

## Extra bugs found by audit agents (verify each port agent handled; fix in integration if not)
- [ ] disasters.spawn() has ZERO callers; HUD "🌪 Disasters" button emits unhandled action (world.gd _on_drawer_action ignores it) — agent 4 scope (disaster scheduling)
- [ ] Paper map unreachable: camera MIN_ZOOM 0.3 > paper-map threshold 0.16; terrain texture is TODO stub — agent 4 scope
- [ ] WeatherFX DAY_LENGTH 600.0 disagrees with Config.DAY_LENGTH_SECONDS 480.0 (tint desync) — agent 4 scope
- [ ] Bandit raid spawns 5 raiders vs HTML's 20 — NOT in any agent scope; fix in integration (disasters.gd)
- [ ] Duplicate Town Hall button: "hall" alias listed alongside town_hall in BUILDINGS, hud.gd iterates all keys — agent 6 scope (build menu)
- [ ] Wall build-time inversion: HTML walls build slowest (3.5x), Godot walls fastest (12s) — agent 6 scope
- [ ] Guild master falls through to _assign_gather (chops trees) — agent 7 scope
- [ ] Stale resources.gd docstring "(wood, stone, gold, food, mana)" — trivial, fix in integration
- [ ] Count Bastard + volcano missing from disaster roster — agent 4 scope (roster completion)
- [ ] Fire wind-spread uses random 35% roll instead of HTML wind-driven — agent 4 scope
- [ ] Sandbox mode boots playable gnomes game instead of observe-only — agent 5 scope
- [ ] In-game drawer: worlds/settings/main_menu/disasters/resource_mgmt actions ignored — agent 5 scope (dead buttons)
- [ ] Settings stored but never applied (graphics/labels/tree sway/life decisions/debug) — agent 5 scope
- [ ] Menu footer claims "Autosaves when you close the tab" — false; agent 5 implements periodic autosave instead

## Audit totals (AUDIT_REPORT.md): 188 features — 65 HAVE, 54 PARTIAL, 68 MISSING
7 features ported pre-wave: Doppler/spatial SFX, adventure save wiring, dungeon markers, race combat mods, named regions/cities, work shifts, storage caps.
