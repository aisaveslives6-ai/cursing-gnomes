class_name World
extends Node2D
## Cursing Gnomes — world root (Milestone 3: jobs & buildings).
##
## Boots the sim (Game autoload), generates the map, bakes + draws terrain,
## seeds harvestable work sites from map props, spawns demo towns for ALL FOUR
## factions, and wires camera + selection + HUD + building placement.
##
## PERFORMANCE (HTML lessons baked in by design, not patched later):
##   - 60 fps target on mobile (the HTML 30 fps cap was a Safari emergency
##     fix, not the Godot plan). If heat becomes an issue, optimize logic —
##     never cap the frame rate.
##   - Worker AI runs on a round-robin budget (AI_UNITS_PER_TICK per physics
##     tick); decisions are staggered, delta is scaled so walk speed is exact.
##   - Service-building staffing is throttle-gated (10 s per building).
##   - Clinic heals run at 10 Hz via a time accumulator (not tick counting,
##     so the rate holds at any physics rate).
##   - Depleted-prop cleanup runs once per second, not per frame.
##   - Y-sort on this node gives depth for free — no ghost systems, ever.
##
## Jeremy's directive: ALL factions active at once, no faction-count limits.


@onready var map_renderer: WorldRenderer = $MapRenderer
@onready var props: Node2D = $Props
@onready var units_root: Node2D = $Units
@onready var buildings_root: Node2D = $Buildings
## Jeremy 2026-10-04: Seven Monasteries — sanctuaries live under their own
## root so the Buildings count (asserted by tests) stays exact.
@onready var monasteries_root: Node2D = $Monasteries
## Jeremy 2026-10-04: Seven Dark Crystals — the crystals live under their
## own root so the Buildings count (asserted by tests) stays exact.
@onready var crystals_root: Node2D = $Crystals
@onready var camera: CameraController = $GameCamera
@onready var selection: Selection = $Selection
@onready var placement: BuildingPlacement = $Placement
@onready var hud: Hud = $HUD
var zone_tool: ZoneTool
var paper_map: PaperMap

## Jeremy 2026-10-10: staged boot for the animated load screen. When main.gd
## sets staged_boot=true before add_child, _ready yields one frame between
## heavy boot stages and emits boot_progress (real stage completion — the
## loading screen maps it to the bar). All other paths (tests, probes)
## boot synchronously exactly as before: the signal fires with nobody
## connected and no frame is yielded, so behavior is unchanged.
signal boot_progress(frac: float, label: String)
signal boot_finished()
var staged_boot := false
var booted := false
var boot_frac := 0.0
var boot_label := ""


var game: GameState
var map_data: Dictionary = {}
var buildings_sys: SimBuildings
var worker_ai: WorkerAI
var combat: SimCombat
var disasters: DisasterSim
var hydro: HydroSim  # flood/hydrology sim (Jeremy 2026-10-04)
var flood_overlay: FloodOverlay  # dramatic flood visuals
var mind: SimMind
var pathfinder: SimPathfinder  # A* movement routing (HTML astarDGrid parity)
var road_overlay: RoadOverlay  # painted road network visuals
var interiors_sys: SimInteriors
var phone_sys: SimPhone
var court_sys: SimRoyalCourt
# Port-wave systems (instantiated in _ready, ticked in _physics_process).
var army  # SimArmy — stances, draft/muster/deploy, warlord, campaigns
var arty  # SimArtillery — vehicles, crews, grape shot, air defense
var tap_command  # SimTapCommand — tap-to-command player military orders
var undead  # SimUndead — soul essence, corpses, necromancy, plague
var factions_sys  # SimFactions — faction military rosters (C61 uniques)
var border_walls  # BorderWalls — AI border-wall rings per faction
var starfort_bases  # StarFortBases — AI star-fort military bases (Jeremy 2026-09-26)
var hiring  # GuildHiring — officers, hiring sweep, training queues
var housing  # SimHousing — house caps, buying, migration, homesteads
var waterx  # SimWaterCrossing — AI water-crossing: bridges straits at war
var ferry  # SimFerry — naval ferry/transport (WATERX ferry parity)
var ai_director  # SimAIDirector — AI faction development brain (aiThink port)
var monasteries  # SimMonasteries — Seven Monasteries (Jeremy 2026-10-04)
var _monastery_nodes: Dictionary = {}  # monastery id -> MonasteryNode
var crystals  # SimDarkCrystals — Seven Dark Crystals (Jeremy 2026-10-04)
var _crystal_nodes: Dictionary = {}  # crystal id -> CrystalNode
var towns_sys  # SimTowns — town founding registry (completed halls -> towns)
var nuclear  # SimNuclear — nuclear warfare: silo arming, strikes, fallout
var tutorial  # TutorialDirector — "First Reign" new-player onboarding
var _chatter := ChatterDirector.new()  # "Overheard" policy: which NPC speech reaches the subtitle ticker
var _chat_bubbles: Dictionary = {}  # unit_id -> ChatBubble (RS-style speech bubbles, Jeremy 2026-10-07)
var end_screen: EndScreen
var debug_overlay: DebugOverlay
var autosave: AutosaveSystem
var _wall_drag := WallDrag.new()  # persistent: run_id sequence must not reset
var _bw_accum := 0.0  # border-wall AI throttle
var _sfb_accum := 0.0  # star-fort AI throttle
var _end_announced := false  # victory/defeat shown once per game
var fx: CombatFX
var dmg_nums: DamageNumbers  # Jeremy 2026-10-08: floating damage numbers
var projectiles_root: Node2D
## Adventure mode (null in standard/sandbox). Owns the hero RPG layer,
## quests, and dungeons.
var adventure: SimAdventure = null
var adventure_hud: AdventureHUD = null
## Sandbox observe mode (null unless the world booted with no player
## faction). Owns the director layer; the standard HUD is hidden while
## this is active and the sandbox director HUD replaces it.
var sandbox: SimSandbox = null
var rivers: RiverRenderer

## --- Processing budgets -------------------------------------------------
const AI_UNITS_PER_TICK := 32   # worker-AI records processed per physics tick
const AI_MAX_SLICES := 4        # worst case at 60 Hz: every unit AI-ticks at 15 Hz
const CLINIC_HEAL_INTERVAL := 0.1  # clinic aura ticks at 10 Hz (time-based)
var _ai_cursor := 0
# Jeremy 2026-10-04: staggering cursors — evenly distribute periodic
# batch work across frames instead of doing it all at once.
var _service_cursor := 0   # _tick_services: 1/30th of buildings per frame
var _cull_cursor := 0      # off-screen culls: 1/60th of nodes per frame
var _prop_cursor := 0      # depleted-prop cleanup: 1/60th of sites per frame
var _prop_cull_cursor := 0 # prop cull: own cursor (not lockstep w/ buildings)
var _god_cull_frame := 0   # god-structure cull: every 30 frames
var _medic_frame := 0      # medic retarget: every 3rd frame (20Hz)
var _heal_accum := 0.0
var _prop_cleanup_accum := 0.0
## Jeremy 2026-10-04: paper-map LOD — detailed world nodes hidden at far
## zoom (HTML inPaperMap parity). Populated after setup; toggled per-frame.
var _paper_lod_nodes: Array[Node] = []
## Jeremy 2026-10-07 (thermal bug): auto-pause when the app backgrounds —
## kills the 60 Hz sim + render burn while nobody is watching. World delegates
## window focus notifications to this policy object (testable in isolation).
var _auto_pause := WorldAutoPause.new()
## Jeremy 2026-10-07 (thermal bug): cap the web build at 60 fps — uncapped
## ProMotion rAF (120 Hz) doubles sustained burn for zero visible gain.
var _frame_cap := WebFrameCap.new()
var _paper_lod_active := false

var _unit_nodes: Dictionary = {}     # unit_id -> UnitNode
var _building_nodes: Dictionary = {} # building_id -> BuildingNode
var _proj_nodes: Dictionary = {}     # projectile_id -> ProjectileNode
var _animal_nodes: Dictionary = {}   # animal_id -> AnimalNode
var _dying: Dictionary = {}          # unit_id -> seconds since death anim
var _prev_combat_state: Dictionary = {}  # unit_id -> last combat_state
var _unit_lift: Dictionary = {}  # unit_id -> current visual lift px (Cliffs)
var _unit_sync_pos: Dictionary = {}  # unit_id -> last synced sim pos (R13 lift skip)
var _fire_visual_accum := 0.0  # R13: building fire visuals tick at 10 Hz
## Jeremy 2026-10-04: work-animation gather kinds — site id -> kind cache
## so gathering units play mine (rock/gold_vein) or chop (tree). Rebuilt
## only when the site count changes (a site's kind is immutable).
var _site_kinds: Dictionary = {}
var _site_kinds_n := -1
## Jeremy 2026-10-05: tree chop/fell visuals — site id -> MapProp link so the
## sim's chop state drives shake (set_chopping) and felling (play_fall).
var _tree_prop_by_site: Dictionary = {}
var _fell_animated: Dictionary = {}  # site id -> true (fall played once)
var _pickup_nodes: Dictionary = {}   # pickup id -> Node2D
var _pickups_root: Node2D = null

## --- Graphics settings (HTML settings parity: graphics actually applied) --
## Resolved tier ("low"|"medium"|"high"|"ultra"), boot tier for the adaptive
## ceiling, and whether the user picked "auto".
var _active_tier := "medium"
var _boot_tier := "medium"
var _graphics_mode := "auto"
var _unit_sync_every := 1  # visual sync cadence in physics frames (HTML unitUpdateEvery)
var _sync_frame := 0
var _ground_detail := "auto"  # Ground Detail setting (auto follows tier)
var _grass: GrassTufts
var _grass_key := ""  # change-detection for grass refresh
## Jeremy 2026-10-03 graphics update: real Godot 4 2D lighting + ambient
## life. LightingRig owns CanvasModulate day/night + pooled PointLight2Ds;
## AmbientFX owns fireflies/embers/leaves/cloud shadows. Both pure visual.
var lighting: LightingRig = null
var ambient: AmbientFX = null
## Festival decorations (2026-10-07 wake rapid-iteration): bunting poles +
## pennant ropes + confetti over the town holding a festival. Pure visual.
var _festival: FestivalFx = null
var _disaster_markers: DisasterMarkers = null
var _trade_wagons: TradeWagonLayer = null
var _vehicle_layer: VehicleLayer = null
var _fish_jumps: FishJumps = null
var _farm_plots: FarmPlotLayer = null
var _trader: TraderLayer = null
var _farm_sfx: WorldFarmSfx = null  # Jeremy 2026-10-07 wake lane: food-economy sounds
var _tap_ripples: TapRipples = null
var _dest_marker: HeroDestMarker = null
var _rubble: RubbleLayer = null
var _terrain_sprite: Sprite2D = null
var _gfx_accum := 0.0  # throttle for light/ember/water refresh (~2 Hz)
var _weather_lighting_mode_set := false
# Adaptive quality (HTML adaptiveQualityTick parity): auto mode only, purely
# visual — step the tier down when the frame-time EMA blows the budget, step
# back up after sustained smooth frames.
# Convergent AQ (graphics-hourly 2026-10-04): an upgrade that is followed by
# a degrade inside AQ_RATCHET_WINDOW proves the higher tier unsustainable on
# this device, so the upgrade ceiling ratchets down below it. Without this,
# AQ ping-pongs medium<->low forever (degrade at ~5 s, upgrade after 60 s of
# smooth frames, degrade again) — each step re-sweeps the tree budget and
# rebuilds grass, which reads on-device as fast -> crawl -> oscillate.
# The ceiling only ever moves down and resets on settings/world reload;
# manual tier selection bypasses AQ entirely. No tier, knob, or feature is
# removed — the governor just converges on the highest sustainable tier.
var _aq_ema := 0.0
var _aq_cool := 0.0
var _aq_smooth := 0
var _aq_time := 0.0          # session clock (s) for AQ decisions
var _aq_upgraded_at := -1.0  # _aq_time of the last AQ upgrade step (-1 = none)
var _aq_ceil_idx := 2        # upgrade ceiling as TIERS index; reset to boot tier on settings reload
const AQ_OVER_MS := 22.0   # sustained frame time that triggers a step down
const AQ_UNDER_MS := 14.0  # smooth frame time that counts toward stepping up
const AQ_SMOOTH_FRAMES := 3600  # ~60 s of smooth frames before stepping up (2026-10-04: was 600/10s, caused oscillation with thermal throttling)
const AQ_COOLDOWN := 3.0  # seconds between tier steps
const AQ_RATCHET_WINDOW := 120.0  # s: degrade inside this window after an upgrade = failed upgrade
# Jeremy 2026-10-04: frame-time debug for 5-second cliff diagnosis.
var _fd_accum := 0.0
var _fd_frames := 0
var _fd_spikes := 0
var _fd_update_t := 0.0


## Jeremy 2026-10-05: paper-map world border. A huge parchment rect drawn
## behind the terrain (z_index -110, terrain is -100) so scrolling past the
## map edge shows paper instead of void. Flat warm-tan color; the rect is
## 10x the map size centered, covering even max zoom-out.
class _PaperBorder extends Node2D:
	var _rect := Rect2()
	var _color := Color(0.85, 0.78, 0.62)

	func setup(map_size: Vector2) -> void:
		var big: float = maxf(map_size.x, map_size.y) * 10.0
		var c := map_size * 0.5
		_rect = Rect2(c - Vector2(big, big) * 0.5, Vector2(big, big))
		z_index = -110
		queue_redraw()

	func _draw() -> void:
		if _rect.size.x > 0.0:
			draw_rect(_rect, _color)


## Jeremy 2026-10-07: procedural fish sprite for ground pickups. Food
## pickups (fisher catches) swim blue; the legendary Stinky Gizmundo is
## sickly green with wavy stink lines. Drawn in code — no missing-texture
## or white-box failure mode, matches the chibi pixel-art scale.
class _FishPickup extends Node2D:
	var stinky := false

	func _draw() -> void:
		var body_col := Color(0.42, 0.72, 0.85)
		if stinky:
			body_col = Color(0.45, 0.70, 0.28)
		var pts := PackedVector2Array()
		for i in range(17):
			var a := TAU * float(i) / 16.0
			pts.append(Vector2(cos(a) * 11.0, -10.0 + sin(a) * 6.0))
		draw_colored_polygon(pts, body_col)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-9.0, -10.0), Vector2(-17.0, -16.0),
			Vector2(-17.0, -4.0)]), body_col.darkened(0.18))
		draw_circle(Vector2(5.0, -11.5), 2.2, Color.WHITE)
		draw_circle(Vector2(5.6, -11.5), 1.1, Color(0.08, 0.08, 0.1))
		if stinky:
			for k in range(3):
				var x := -6.0 + float(k) * 6.0
				var w := PackedVector2Array()
				for s in range(9):
					w.append(Vector2(
						x + sin(float(s) * 1.2 + float(k) * 2.1) * 1.7,
						-18.0 - float(s) * 2.1))
				draw_polyline(w, Color(0.6, 0.9, 0.35, 0.85), 1.6)


## Instantiates the paper-map border behind the terrain.
func _add_paper_border(map_data: Dictionary) -> void:
	var ws: Vector2 = map_data.get("world_size", Vector2(4096, 4096))
	var paper := _PaperBorder.new()
	paper.name = "PaperBorder"
	add_child(paper)
	paper.setup(ws)


## Staged-boot helper: records real boot progress and, when main.gd asked
## for a staged boot, yields one frame so the loading screen can repaint
## between the heavy stages. Synchronous-boot paths: no yield, no behavior
## change (the emits have no connections).
func _boot_stage(frac: float, label: String) -> void:
	boot_frac = frac
	boot_label = label
	boot_progress.emit(frac, label)
	if staged_boot:
		await get_tree().process_frame


func _ready() -> void:
	# Jeremy 2026-10-07 (thermal bug): cap web at 60 fps before anything
	# heavy boots. No-op on desktop; idempotent.
	_frame_cap.apply()
	var _was_paused := false
	if staged_boot:
		# Freeze the sim while the staged boot yields frames: _process /
		# _physics_process would otherwise tick a half-built world during
		# the yielded frames (the synchronous boot never saw a frame
		# mid-build). Restored at the end of _ready.
		_was_paused = get_tree().paused
		get_tree().paused = true
	# Prefer the Game autoload; tests instantiating this scene headless get a
	# private GameState instead (autoloads aren't guaranteed under -s).
	game = get_node_or_null("/root/Game") as GameState
	if game == null:
		game = GameState.new()
		add_child(game)

	# ALL factions, all at once — no faction-count limits (Jeremy's call).
	var factions: Array[String] = []
	for f: String in Config.FACTIONS.keys():
		factions.append(f)
	game.setup(factions)
	await _boot_stage(0.15, "Waking the gnomes…")

	buildings_sys = SimBuildings.new(game)
	ferry = SimFerry.new(game)
	waterx = SimWaterCrossing.new(game, buildings_sys, ferry)
	worker_ai = WorkerAI.new(game)
	game.worker_ai = worker_ai  # road-network save/load reads this
	pathfinder = SimPathfinder.new(game)
	pathfinder.bind_roads(worker_ai)
	game.pathfinder = pathfinder
	combat = SimCombat.new(game)
	disasters = DisasterSim.new(game, combat)
	hydro = HydroSim.new(game, combat)
	game.hydro = hydro
	mind = SimMind.new(game)
	combat.mind = mind  # non-lethal damage feeds the mind (grudges, fear)
	# Milestone 7: interiors + mind hook — NPCs enter buildings for urges.
	interiors_sys = SimInteriors.new(game)
	mind.interiors = interiors_sys
	# Milestone 6 (wired 2026-10-02): phone + royal court systems.
	phone_sys = SimPhone.new(game)
	court_sys = SimRoyalCourt.new(game)
	# Gazette two-way chat: phone routes court-character replies through
	# SimGazette (HTML gazCraftReply parity).
	phone_sys._court = court_sys
	court_sys.attach_phone(phone_sys)
	# Milestone 8: diplomacy gates combat, routes court petitions, and
	# reports wars/alliances to the Gazette.
	combat.diplomacy = game.diplomacy
	court_sys.diplomacy = game.diplomacy
	game.diplomacy.court = court_sys

	# Port wave: calendar/economy + war + undead + hiring/housing sims.
	# Worldgen seed from the "Forge Your World" setup screen (Reroll).
	var wg: Dictionary = get_tree().get_meta("cg_worldgen", {}) \
		if get_tree() != null else {}
	var world_seed: int = int(wg.get("seed", 20261002))
	var world_type: String = str(wg.get("type", "continents"))
	var world_size_key: String = str(wg.get("size", "normal"))
	var world_opts: Dictionary = wg.get("opts", {})
	if not wg.is_empty():
		game.worldgen = wg
	game.seasons = SimSeasons.new(game)
	game.farming = SimFarming.new(game)
	game.animals = SimAnimals.new(game)
	game.industry = SimIndustry.new(game)
	game.seasons.reset()
	game.farming.reset()
	game.animals.reset()
	game.industry.reset()
	army = SimArmy.new(game)
	army.diplomacy = game.diplomacy
	game.army = army
	game.set_meta("army", army)  # ArmyTab reaches the system via meta
	# Jeremy 2026-10-07: tap-to-command — player tactical orders.
	tap_command = SimTapCommand.new(game)
	game.tap_command = tap_command
	arty = SimArtillery.new(game, combat)
	game.arty = arty
	undead = SimUndead.new(game, combat)
	game.undead = undead
	factions_sys = SimFactions.new(game)
	game.factions = factions_sys
	game.disasters = disasters
	border_walls = BorderWalls.new(game)
	game.border_walls = border_walls
	starfort_bases = StarFortBases.new(game)
	game.starfort_bases = starfort_bases

	hiring = GuildHiring.new(game)
	game.hiring = hiring

	ai_director = SimAIDirector.new(game)
	game.ai_director = ai_director

	# Jeremy 2026-10-04: tool/equipment + shop petition chain (units buy
	# tools at shops; petition the adviser when no shop exists). Connects
	# its own day_changed hook for adviser proactivity.
	game.petitions = SimPetitions.new(game)

	# Jeremy 2026-10-10: vehicle dealership + ownership + assigned parking
	# (roads/vehicles order, P3). Citizens buy personal vehicles with
	# their own coins; every sold vehicle gets a lot slot. Ticked after
	# the vehicle physics step so purchases spawn into a settled fleet.
	game.dealership = SimDealership.new(game)

	# Jeremy 2026-10-10: military motor pool (roads/vehicles order, P5).
	# Complete vehicle_depots park, maintain and dispatch war wagons:
	# assigned lot slots, treasury-funded fleet (AI), advisor-phoned for
	# the player faction, baggage-train dispatch on war deployment.
	game.motor_pool = SimMotorPool.new(game)

	# Jeremy 2026-10-10: NPC vehicle travel (roads/vehicles order, P5).
	# Citizens ride their OWN vehicles (dealership purchases) on long
	# trips — countryside migration, driving a new purchase home.
	# Boarding/travel/dismount on the unified SimVehicles physics.
	game.npc_travel = SimNPCTravel.new(game)

	# Jeremy 2026-10-06: Living Lexicon restoration (HTML fix79 parity) —
	# NPCs learn the player's words, remember them across saves, show them
	# off in chat, and spread them as daily gossip. Day-cadence spread via
	# its own day_changed hook (no per-frame work). The phone's conversation
	# engine shares this instance so every chat teaches the same brain.
	game.lexicon = SimLexicon.new(game)
	phone_sys.conversation.lexicon = game.lexicon

	# Jeremy 2026-10-04: strategic proposal protocol — "AI plays the game,
	# player approves". Advisers submit major decisions (war, monastery
	# assaults, expansion, buildup, peace); the player answers on the phone,
	# AI factions auto-resolve. Day-cadence expiry via its own day_changed
	# hook (no per-frame work).
	game.proposals = SimProposals.new(game)

	# Jeremy 2026-10-06: wandering handyman tribute (HTML CANDIDATE19 parity)
	# — rare one-per-game visit: repairs the most-damaged building for free,
	# or leaves 40 seasoned lumber when nothing is broken. Own day_changed
	# hook (no per-frame work); Gazette story + player toast on firing.
	game.handyman = SimHandyman.new(game)

	# Jeremy 2026-10-09 wake routine: the founding beat — every new game
	# opens with a Gazette founding story + the Civic Advisor's welcome DM
	# (in-voice first directive) + a toast. One-per-game, own day_changed
	# hook (fires on the first day change, day 1 -> 2).
	game.founding = SimFounding.new(game)

	# Jeremy 2026-10-07 wake lane ("the food economy talks back"): the
	# food-economy reporting side. SimFoodFeedback tallies daily harvests
	# and sends the Civic Adviser's Messenger digest + Gazette bumper /
	# blight stories; WorldFarmSfx routes the farm/ranch/trade signals to
	# the world SFX engine (audio-lane pattern).
	game.food_feedback = SimFoodFeedback.new(game)
	_farm_sfx = WorldFarmSfx.new(game)

	# Jeremy 2026-10-06: Ruler's Voice — the player's cabinet takes spoken
	# orders in Messenger and carries them out (build/train/muster/tax/
	# festival). Own day_changed hook for completion report-backs.
	game.rulers_voice = SimRulersVoice.new(game)

	# Jeremy 2026-10-11: faction trade deals — propose resource trades to
	# other factions from the phone; AI accepts/counters/refuses with
	# voiced dialogue; one-time or daily execution; full ledger; Treasury
	# advisor tracks + auto-manages. Own day_changed hook.
	game.trade_deals = SimTradeDeals.new(game)

	# Jeremy 2026-10-11: war-spare fate votes + negotiable peace treaties —
	# when a faction's hall falls to a war enemy, the land votes SPARE/END.
	# Own hooks (hall captures/destructions, day tick, war declarations).
	game.war_spare = SimWarSpare.new(game)

	# Jeremy 2026-10-11: disaster-aid votes — a hall felled by nature gets an
	# aid vote instead of a fate vote; yes-voters dispatch helper NPCs who
	# repair and rebuild, then return home. Own 1 Hz tick.
	game.disaster_aid = SimDisasterAid.new(game)

	# Jeremy 2026-10-11: per-race lifespans + natural aging — the first
	# natural-death mechanic. Elders slow down, the dying pass quietly in
	# a randomized window, notables get obituaries, friends mourn, empty
	# advisor seats are refilled. Undead are ageless. Own day_changed hook.
	game.lifespans = SimLifespans.new(game)

	# Jeremy 2026-10-11: plague/disease system — the moral-choice centerpiece.
	# Undead + elves immune; gnomes rarely sick; ogres moderate; humans full.
	# Autumn outbreaks spread town-to-town on the day tick; the ruler picks
	# a doctrine (mercy/cure/quarantine/cull/ignore) in Policies, changeable
	# anytime. Own day_changed hook. (SimSkills is static — no instance.)
	game.disease = SimDisease.new(game)

	# Jeremy 2026-10-05: peacetime garrison AI (HTML c44TickGarrison /
	# garrisonMilitaryNPC port) — idle military lives at the base during
	# peacetime and reacts to yard threats. Own 0.5 s tick.
	game.garrison = SimGarrison.new(game, combat)

	# Jeremy 2026-10-05: civilian siege response (HTML Siege Doctrine
	# civilianDefenseTick / defenseRepairTarget port) — civilians hide
	# from attacks (35% of workers bravely repair walls instead). 1 Hz.
	game.siege = SimSiege.new(game, combat, interiors_sys)

	# Jeremy 2026-10-05: inter-faction trade routes (HTML ensureTradeRoute /
	# dissolveTradeRoutes / spawnTradeWagon / updateTradeWagons port) —
	# dirt trade roads between allied/trading halls, trade outposts at each
	# end, covered wagons looping cargo between factions. Ticked per-frame
	# (wagons are few by design); war dissolves the route.
	game.trade_routes = SimTradeRoutes.new(game)
	game.trade_routes.worker_ai = worker_ai
	game.trade_routes.court = court_sys
	# Jeremy 2026-10-10 (road infrastructure + vehicle system, P1): unified
	# vehicle records + driving physics. Every vehicle — trade wagons,
	# citizen carts, military vehicles, fire trucks — drives through this.
	game.vehicles = SimVehicles.new(game)

	# Jeremy 2026-10-05: Family & Belonging (HTML FAMILY & BELONGING port) —
	# romance/courtship/marriage, social bonds, pregnancy/birth/children,
	# leave-town petitions, adventurers joining factions, leadership souls.
	# Player decisions route through the Royal Court petition list.
	game.family = SimFamily.new(game)
	game.family._court = court_sys
	game.family._spawner = game.spawner
	# Jeremy 2026-10-05: The Backchannel (HTML Candidate21 port) — rulers
	# trade private letters off-screen; affinity feeds diplomacy. Player
	# pairs route through the Royal Court petition list (sovereignty).
	game.backchannel = SimBackchannel.new(game)
	game.backchannel._court = court_sys

	# Jeremy 2026-10-04: Seven Monasteries — gods, perks, capture.
	var mons := SimMonasteries.new()
	mons.setup(game)
	mons.combat = combat
	monasteries = mons
	game.monasteries = mons
	combat.monasteries = mons

	# Jeremy 2026-10-04: Seven Dark Crystals — rogue gods, devastating
	# powers, corruption. The evil mirror of the monasteries.
	var crys := SimDarkCrystals.new()
	crys.setup(game)
	crys.combat = combat
	crys.phone = phone_sys
	crystals = crys
	game.crystals = crys
	combat.crystals = crys

	# Jeremy 2026-10-06: Command Posts — unified capture model for
	# towns, monasteries, and dark crystals (Battlefront directive).
	var cposts := SimCommandPosts.new()
	cposts.setup(game)
	game.command_posts = cposts

	# Jeremy 2026-10-04: nuclear warfare — silo arming, nuke strikes,
	# detonations, radiation zones (HTML fireNuke/detonateNuke parity).
	# The HTML AI never fires nukes; only the player does.
	var nukes := SimNuclear.new()
	nukes.setup(game)
	nukes.combat = combat
	nukes.disasters = disasters
	nuclear = nukes
	game.nuclear = nukes
	combat.nuclear = nukes

	# First Reign onboarding: purely additive overlay + step checks.
	tutorial = TutorialDirector.new(game)
	tutorial.name = "Tutorial"
	add_child(tutorial)
	tutorial.setup_world(self)
	await _boot_stage(0.32, "Raising the kingdoms…")

	housing = SimHousing.new(game)
	game.housing = housing
	towns_sys = SimTowns.new(game)
	game.towns_sys = towns_sys
	game.court_sys = court_sys
	game.phone_sys = phone_sys

	# Combat visual layer.
	fx = CombatFX.new()
	fx.name = "CombatFX"
	add_child(fx)
	# Jeremy 2026-10-08 (rapid-iteration): floating damage numbers — plain
	# text above the combat particles, no bubble visuals (2026-10-05 ban).
	dmg_nums = DamageNumbers.new()
	dmg_nums.name = "DamageNumbers"
	add_child(dmg_nums)
	# Jeremy 2026-10-04: nuclear warfare — pulsing radiation haze over
	# active zones + fallout. Reads SimNuclear state; pure visual.
	var rad := RadiationOverlay.new()
	rad.name = "Radiation"
	rad.z_index = -9
	rad.nuclear = nuclear
	add_child(rad)
	projectiles_root = Node2D.new()
	projectiles_root.name = "Projectiles"
	add_child(projectiles_root)

	var gen := MapGen.new()
	map_data = gen.generate(factions, world_seed, world_type, world_size_key, world_opts)
	game.map_data = map_data  # cliff-aware sim (levels, blocking, lift)
	var terrain_sprite := map_renderer.render_map(map_data, props)
	# Jeremy 2026-10-05: paper-map world border — parchment behind the
	# terrain so scrolling past the map edge shows paper, not void.
	_add_paper_border(map_data)
	# Painted roads: the road network overlay (dirt trails vs stone paving).
	road_overlay = RoadOverlay.new()
	road_overlay.name = "RoadOverlay"
	road_overlay.z_index = -50  # above terrain, below units/props
	add_child(road_overlay)
	# Rivers visual overhaul: flow shader on the terrain, animated
	# waterfalls, pooled foam flecks / bursts / rings / mist.
	rivers = RiverRenderer.new()
	rivers.name = "Rivers"
	add_child(rivers)
	rivers.setup(map_data, terrain_sprite)
	# Flood visuals: expanding sheets, foam, debris, mud (Jeremy 2026-10-04).
	flood_overlay = FloodOverlay.new()
	flood_overlay.name = "FloodOverlay"
	add_child(flood_overlay)
	flood_overlay.setup(game)
	_seed_work_sites(map_data)
	# Jeremy 2026-10-05: ground pickups (felled-tree wood) render under the
	# y-sorted Props parent so they depth-sort with trees and units.
	_pickups_root = Node2D.new()
	_pickups_root.name = "Pickups"
	props.add_child(_pickups_root)
	await _boot_stage(0.55, "Carving the land…")

	# Defensive .get() defaults: a malformed map_data must degrade, not crash.
	var world_size: Vector2 = map_data.get("world_size", Vector2(4096, 4096))
	var starts: Dictionary = map_data.get("faction_starts", {})
	disasters.setup_bounds(Rect2(Vector2.ZERO, world_size))
	hydro.setup_bounds(Rect2(Vector2.ZERO, world_size))
	# Note: game.player_faction isn't set yet here (configure() runs after
	# _ready), and no buildings exist yet (_spawn_demo runs below), so we
	# just use the map center as a placeholder. configure() re-aims the
	# camera at the player's actual town_hall, zoomed in close.
	camera.setup(Rect2(Vector2.ZERO, world_size), world_size * 0.5, 0.9)

	# Graphics settings: resolve the tier and apply every visual knob
	# (HTML applyGraphicsTier parity — the settings finally do something).
	_apply_graphics_settings()
	# Grass tufts: the Ground Detail setting's visible effect (HTML parity:
	# sparse grass on high/ultra detail when zoomed in, never in Winter).
	_grass = GrassTufts.new()
	_grass.name = "GrassTufts"
	add_child(_grass)
	_grass.setup(Rect2(Vector2.ZERO, world_size), camera,
		_eff_ground_detail())
	_terrain_sprite = terrain_sprite

	# Jeremy 2026-10-03 graphics update: Godot 4 lighting rig + ambient
	# life. Real PointLight2D lights (windows at night, fires, flashes)
	# under a CanvasModulate day/night ambient — UI CanvasLayers render
	# independently of CanvasModulate, so the HUD stays bright.
	lighting = LightingRig.new()
	lighting.name = "LightingRig"
	add_child(lighting)
	lighting.setup(camera, _active_tier)
	ambient = AmbientFX.new()
	ambient.name = "AmbientFX"
	add_child(ambient)
	ambient.setup(camera, _active_tier, Rect2(Vector2.ZERO, world_size))
	# Festival decorations (2026-10-07 wake rapid-iteration): bunting poles,
	# pennant ropes, and confetti over the town holding a festival. The
	# court owns SimPolicies, so the FX reads its live festival state.
	_festival = FestivalFx.new()
	_festival.name = "FestivalFx"
	add_child(_festival)
	_festival.setup(game, court_sys)
	# Disaster monster markers (HTML drawDisasterMarkers port): pulsing
	# red "!" diamonds over live monsters at far zoom + screen-edge
	# arrows for off-screen ones. Graphics-hourly 2026-10-05.
	_disaster_markers = DisasterMarkers.new()
	_disaster_markers.name = "DisasterMarkers"
	add_child(_disaster_markers)
	_disaster_markers.set_camera(camera)
	_disaster_markers.set_provider(disasters.monster_marker_positions)
	# Trade wagons (HTML drawTradeWagons port): covered wagons with
	# faction flags rolling the trade roads. Dedicated-porting 2026-10-05.
	_trade_wagons = TradeWagonLayer.new()
	_trade_wagons.name = "TradeWagons"
	add_child(_trade_wagons)
	_trade_wagons.set_camera(camera)
	_trade_wagons.set_routes(game.trade_routes)
	# SimVehicles renderer (P2, Jeremy 2026-10-10 vehicle order): wagons,
	# carts, carriages with driving physics render here with turning
	# wheels, dust, shadows and faction trim. Graphics-hourly 2026-10-10.
	_vehicle_layer = VehicleLayer.new()
	_vehicle_layer.name = "VehicleLayer"
	add_child(_vehicle_layer)
	_vehicle_layer.set_camera(camera)
	_vehicle_layer.set_vehicles(game.vehicles)
	# Graphics-hourly 2026-10-11: rider sprites — the layer resolves boarded
	# units' chibi textures from game.units to draw them seated in vehicles.
	_vehicle_layer.set_unit_provider(func() -> Array: return game.units)
	# Farm plots (SimFarming auto-plots): isometric tilled fields with
	# per-tile crop growth, one per farm/farmhouse. Launch-readiness
	# 2026-10-05 (gate 2) — plots were sim-only and invisible on the map.
	_farm_plots = FarmPlotLayer.new()
	_farm_plots.name = "FarmPlots"
	add_child(_farm_plots)
	_farm_plots.set_camera(camera)
	_farm_plots.set_farming(game.farming)
	# Captain Funky Pants (launch-readiness 2026-10-06, gate 1): the caravan
	# was sim-complete but invisible and untappable. TraderLayer draws the
	# chibi sprite from bus.trader_arrived/trader_left and opens the trade
	# panel on tap. Added to units_root (tree draw order with units);
	# excluded from selection.selectables below (tap = trade panel, not ring).
	if game.get("industry") != null:
		_trader = TraderLayer.new()
		_trader.name = "Trader"
		units_root.add_child(_trader)
		_trader.setup(game.bus, game.industry, camera, placement, game,
			func() -> bool: return adventure != null and adventure.active)
	# Fish jumps (HTML hydroFishTick/drawFishJumps port): fish leap from
	# lakes and rivers, landing in splash rings with droplets. The provider
	# hands over map_data["water_bodies"] (lake discs + river polylines).
	# Graphics-hourly 2026-10-05.
	_fish_jumps = FishJumps.new()
	_fish_jumps.name = "FishJumps"
	add_child(_fish_jumps)
	_fish_jumps.set_camera(camera)
	_fish_jumps.set_provider(func() -> Array:
		return map_data.get("water_bodies", []))
	# HTML SFX parity (fix79 hydroFishTick -> sfxAt('splash') on landing):
	# route the landing signal to the spatial SFX bus.
	_fish_jumps.fish_landed.connect(_on_fish_landed)
	# Tap ripples: HTML handleTap -> pushTapRipple port (fix79 ~2914400).
	# Every world tap answers with a visible gold ring (fluid, alive).
	# Graphics-hourly 2026-10-05.
	_tap_ripples = TapRipples.new()
	_tap_ripples.name = "TapRipples"
	add_child(_tap_ripples)
	_tap_ripples.set_camera(camera)
	# Hero destination marker (HTML drawHeroDestMarker port, fix79 :49584):
	# a yellow X-in-circle ping where the adventure hero was ordered to walk.
	# Graphics-hourly 2026-10-05.
	_dest_marker = HeroDestMarker.new()
	_dest_marker.name = "HeroDestMarker"
	add_child(_dest_marker)
	_dest_marker.set_camera(camera)
	# Rubble piles (HTML spawnRubble/drawRubbleMound/tapClearRubble port):
	# AoE-style debris mounds where buildings fell, tap to clear.
	# Graphics-hourly 2026-10-05.
	_rubble = RubbleLayer.new()
	_rubble.name = "RubbleLayer"
	add_child(_rubble)
	_rubble.set_camera(camera)
	_build_vignette()
	await _boot_stage(0.70, "Painting the world…")

	_grant_starting_resources(factions)
	_spawn_demo(factions, starts)
	_seed_wildlife(factions, starts, gen, world_size)
	# Jeremy 2026-10-04: Seven Monasteries — scatter the sanctuaries,
	# then build their visual nodes.
	monasteries.place_monasteries()
	for m: Dictionary in monasteries.monasteries:
		_add_monastery_node(m)
	game.bus.monastery_captured.connect(_on_monastery_captured)
	# Jeremy 2026-10-06 (Battlefront): halls flip faction on war capture
	# instead of being destroyed — the node's pennant/art must recolor.
	game.bus.command_post_captured.connect(_on_command_post_captured)
	# Jeremy 2026-10-04: Seven Dark Crystals — erupt from the wilds,
	# then build their visual nodes.
	crystals.place_crystals()
	for c: Dictionary in crystals.crystals:
		_add_crystal_node(c)
	game.bus.crystal_captured.connect(_on_crystal_captured)
	game.bus.crystal_struck.connect(_on_crystal_struck)
	await _boot_stage(0.84, "Settling the towns…")

	# UI wiring.
	placement.setup(game, buildings_sys, Rect2(Vector2.ZERO, world_size),
		game.player_faction)
	placement.map_data = map_data  # fishing-dock near-water checks
	game.zoning.map_bounds = Rect2(Vector2.ZERO, world_size)
	zone_tool = ZoneTool.new()
	zone_tool.name = "ZoneTool"
	zone_tool.z_index = 95
	add_child(zone_tool)
	zone_tool.setup(game, game.zoning, camera)
	hud.zone_overlay_toggled.connect(zone_tool.toggle_overlay)
	game.bus.zone_changed.connect(_on_zone_changed)
	selection.camera = camera
	selection.game = game  # route overlay for the selected unit
	selection.selectables = _collect_selectables()
	hud.setup(game, selection)
	hud.build_requested.connect(_on_build_requested)
	hud.drawer_action.connect(_on_drawer_action)
	hud.snap_camera_to_capitol.connect(_on_snap_camera_to_capitol)
	hud.set_phone_systems(phone_sys, court_sys)
	camera.tapped.connect(_on_tapped)
	camera.wall_pressed.connect(_on_wall_pressed)
	camera.wall_moved.connect(_on_wall_moved)
	camera.wall_released.connect(_on_wall_released)

	# Paper map / minimap (ported from HTML's drawMinimapTo).
	paper_map = PaperMap.new()
	paper_map.name = "PaperMap"
	add_child(paper_map)
	paper_map.setup(game, self)
	paper_map.map_tapped.connect(_on_paper_map_tapped)

	# End screen + debug overlay + periodic autosave (modes port).
	end_screen = EndScreen.new()
	end_screen.name = "EndScreen"
	add_child(end_screen)
	if not get_tree().has_meta("cg_debug_overlay"):
		get_tree().set_meta("cg_debug_overlay", _read_debug_setting())
	debug_overlay = DebugOverlay.new()
	debug_overlay.name = "DebugOverlay"
	add_child(debug_overlay)
	autosave = AutosaveSystem.new()
	autosave.name = "Autosave"
	add_child(autosave)
	autosave.setup(game, func() -> Variant: return adventure)

	# Housing adoption pass: match existing units to existing houses.
	housing.adopt_housing()
	_collect_paper_lod_nodes()
	await _boot_stage(1.0, "Ready")
	booted = true
	# Unpause BEFORE emitting: the loading screen (PROCESS_MODE_ALWAYS)
	# animated through the freeze; the world resumes live underneath it.
	# Guarded: the synchronous path must not touch pause state at all.
	if staged_boot:
		get_tree().paused = _was_paused
	boot_finished.emit()


## Jeremy 2026-10-04: paper-map LOD node list — every detailed-world visual
## that hides when the paper map is fully opaque at far zoom (HTML
## inPaperMap() skips the whole world layer). HUD, paper map, camera,
## end screen, and debug overlay stay visible.
func _collect_paper_lod_nodes() -> void:
	_paper_lod_nodes.clear()
	for n in [map_renderer, props, units_root, buildings_root,
			monasteries_root, crystals_root, fx, projectiles_root,
			road_overlay, rivers,
			flood_overlay, _grass, lighting, ambient, zone_tool,
			selection]:
		if n != null and is_instance_valid(n):
			_paper_lod_nodes.append(n)


## Jeremy 2026-10-04: toggle detailed-world visibility for paper-map LOD.
## Called every frame; only touches visibility on state change.
func _update_paper_lod() -> void:
	var want_lod := false
	if paper_map != null and is_instance_valid(paper_map):
		want_lod = paper_map.is_paper_lod()
	if want_lod == _paper_lod_active:
		return
	_paper_lod_active = want_lod
	for n in _paper_lod_nodes:
		if n != null and is_instance_valid(n):
			(n as CanvasItem).visible = not want_lod

	# Sim -> visual bridges: keep nodes in sync with records.
	game.bus.unit_spawned.connect(_on_unit_spawned)
	game.bus.building_placed.connect(_on_building_placed)
	game.bus.projectile_fired.connect(_on_projectile_fired)
	game.bus.projectile_done.connect(_on_projectile_done)
	game.bus.projectile_hit.connect(_on_projectile_hit)
	game.bus.unit_killed.connect(_on_unit_killed)
	game.bus.unit_purged.connect(_on_unit_purged)
	game.bus.building_destroyed.connect(_on_building_destroyed)
	game.bus.fire_started.connect(_on_fire_started)
	game.bus.fire_out.connect(_on_fire_out)
	game.bus.disaster_spawned.connect(_on_disaster_spawned)
	game.bus.combat_fx.connect(_on_combat_fx)
	# Jeremy 2026-10-08: floating damage numbers from SimCombat.damage_unit.
	game.bus.unit_damaged.connect(_on_unit_damaged)
	# Jeremy 2026-10-04: wall-raise hearsay answers come through the bus.
	game.bus.wall_answer.connect(_on_wall_answer)
	# Milestone 5: minds. Grief on death; chatter lines still emit on the bus
	# (bubble visuals removed 2026-10-05).
	game.bus.unit_died.connect(_on_unit_died_mind)
	game.bus.unit_said.connect(_on_unit_said)
	# Surrender ceremony: white flag over the loser's hall.
	game.bus.surrender_accepted.connect(_on_surrender_accepted)
	game.bus.surrender_offered.connect(_on_surrender_offered)


## Signal: the player asked to leave for the main menu (drawer button).
## main.gd connects this when it instantiates the world.
signal quit_to_menu_requested(target_screen: String)


## Milestone 7: configure after _ready (called by main.gd menu flow).
## Sets the player faction and ruler name verbatim.
func configure(player_faction: String, ruler_name: String) -> void:
	game.player_faction = player_faction
	game.set_ruler_name(ruler_name)  # verbatim — never trimmed
	# Jeremy 2026-10-06: the player faction is only finalized here (setup
	# used a default). Reconcile AI leaders: the player's faction gets no
	# AI leader, every other faction gets its picked candidate.
	if game.faction_leaders != null \
			and game.faction_leaders.has_method("on_player_faction_set"):
		game.faction_leaders.on_player_faction_set(player_faction,
			game.active_factions)
	# Re-aim the camera at the player's base, zoomed in close.
	# Jeremy 2026-10-03: "wayyy closer to your faction, zoomed in on them"
	# Buildings exist by now (_spawn_demo ran in _ready), so find the
	# player's actual town_hall rather than trusting the map-gen start.
	var aim_pos := Vector2.ZERO
	var found := false
	if game != null:
		for b in game.buildings:
			if b is Dictionary and String(b.get("faction", "")) == player_faction:
				var bt: String = String(b.get("type", ""))
				if bt == "town_hall" or bt == "hall":
					aim_pos = b.get("position", Vector2.ZERO)
					found = true
					break
	if (not found) and map_data.has("faction_starts"):
		var starts: Dictionary = map_data["faction_starts"]
		if starts.has(player_faction):
			aim_pos = starts[player_faction]
			found = true
	if found:
		camera.setup(camera.map_bounds, aim_pos, 2.2)
	# Sandbox observe mode (HTML sandboxMode parity): no player faction —
	# the camera re-aim above skips (no start key for ""), so the director
	# takes over here: full-AI factions, zoomed-out observer camera, the
	# standard RTS chrome hidden by the director HUD.
	if player_faction == "" and sandbox == null:
		sandbox = SimSandbox.new(game)
		sandbox.begin()
		sandbox.sim_complete.connect(_on_sandbox_complete)
		_aim_sandbox_camera()
		hud.enter_sandbox_mode(sandbox)
		hud.sandbox_camera_focus.connect(_aim_sandbox_camera_at)
		hud.flash_hint("Sandbox live — pan & zoom to watch. All factions are AI.")
	# First Reign: offer the guided tour for real games only — never in
	# sandbox observe mode (no player faction) or adventure mode.
	if player_faction != "" and (adventure == null or not adventure.active) \
			and tutorial != null:
		tutorial.maybe_offer()


## Aim the observer camera wide: the focused faction's hall (HTML
## sbFocusCam zooms 0.85 onto it) or mid-map when no hall stands.
## Boot uses ~0.7 for a wider opening view (sandbox docstring parity).
func _aim_sandbox_camera() -> void:
	_aim_sandbox_camera_at(sandbox.focus_race if sandbox != null else "", 0.7)


func _aim_sandbox_camera_at(faction: String, zoom: float = 0.85) -> void:
	var pos := Vector2.ZERO
	if sandbox != null and faction != "":
		pos = sandbox.hall_position(faction)
	if pos == Vector2.ZERO:
		var ws: Vector2 = map_data.get("world_size", Vector2(4096, 4096))
		pos = ws * 0.5
	camera.setup(camera.map_bounds, pos, zoom)


## Jeremy 2026-10-07 (direct request): the HUD capitol button asks for a
## camera snap back to the player's faction capitol (main town_hall, same
## aim logic as boot; faction_starts fallback if the hall is gone).
func _on_snap_camera_to_capitol() -> void:
	var pf: String = String(game.player_faction) if game != null else ""
	var aim_pos := Vector2.ZERO
	var found := false
	if game != null:
		for b in game.buildings:
			if b is Dictionary and String(b.get("faction", "")) == pf:
				var bt := String(b.get("type", ""))
				if bt == "town_hall" or bt == "hall":
					aim_pos = b.get("position", Vector2.ZERO)
					found = true
					break
	if (not found) and map_data.has("faction_starts"):
		var starts: Dictionary = map_data["faction_starts"]
		if starts.has(pf):
			aim_pos = starts[pf]
			found = true
	if found:
		camera.setup(camera.map_bounds, aim_pos, 2.2)
	elif hud != null and is_instance_valid(hud):
		hud.flash_hint("No capitol standing")


## Adventure mode entry (called by main.gd after _start_world). Spawns the
## hero, dungeons, and quests, then attaches the adventure HUD.
func start_adventure(hero_name: String, hero_job: String,
		hero_gender: String = "") -> void:
	if adventure != null and adventure.active:
		return  # already running — never double-start (or double-connect)
	adventure = SimAdventure.new(game)
	adventure.combat = combat
	combat.adventure = adventure
	var world_size: Vector2 = map_data.get("world_size",
		Vector2(4096, 4096))
	if not adventure.start(game.player_faction, hero_name, hero_job,
			world_size, hero_gender):
		adventure = null
		combat.adventure = null
		return
	game.bus.unit_died.connect(_on_adventure_unit_died)
	adventure_hud = AdventureHUD.new()
	adventure_hud.name = "AdventureHUD"
	add_child(adventure_hud)
	adventure_hud.setup(adventure, game)
	# Camera starts on the hero.
	var h: Dictionary = adventure.hero()
	if not h.is_empty():
		camera.position = h.get("position", Vector2.ZERO)
		camera.clamp_now()


func _on_adventure_unit_died(unit_id: int, _faction: String) -> void:
	if adventure != null:
		adventure.on_unit_died(unit_id)


## Milestone 7: load a saved game. Clears the demo world, restores state,
## rebuilds all visual nodes.
func load_from_data(data: Dictionary) -> bool:
	# Adventure-mode saves: create the adventure instance BEFORE restore
	# so SaveSystem can load hero/quest/dungeon state into it. The bus
	# connection happens only after a successful restore — never leave
	# a dangling connection on a failed load.
	var wired_adventure := false
	if data.has("adventure") and adventure == null:
		adventure = SimAdventure.new(game)
		adventure.combat = combat
		combat.adventure = adventure
		wired_adventure = true
	if not SaveSystem.restore(game, data, adventure):
		if wired_adventure:
			adventure = null
			combat.adventure = null
		return false
	if wired_adventure:
		game.bus.unit_died.connect(_on_adventure_unit_died)
	# Adventure HUD for restored adventure-mode saves.
	if adventure != null and adventure.get("active") and adventure_hud == null:
		adventure_hud = AdventureHUD.new()
		adventure_hud.name = "AdventureHUD"
		add_child(adventure_hud)
		adventure_hud.setup(adventure, game)
	# Sandbox save restored: re-arm the director (observe-only boot parity).
	if str(data.get("player_faction", "")) == "" and sandbox == null:
		sandbox = SimSandbox.new(game)
		sandbox.begin()
		sandbox.sim_complete.connect(_on_sandbox_complete)
		_aim_sandbox_camera()
		hud.enter_sandbox_mode(sandbox)
		hud.sandbox_camera_focus.connect(_aim_sandbox_camera_at)
	# Zones restored: recompute bonuses and repaint the overlay.
	game.zoning.refresh_all()
	zone_tool.queue_redraw()
	# Clear demo nodes.
	for uid in _unit_nodes.keys():
		var un: UnitNode = _unit_nodes[uid] as UnitNode
		if un != null and is_instance_valid(un):
			un.queue_free()
	_unit_nodes.clear()
	# Jeremy 2026-10-07: chat bubbles are world children — free them on
	# teardown so no stale speech lingers into the next game.
	for uid in _chat_bubbles.keys():
		var bub: ChatBubble = _chat_bubbles[uid] as ChatBubble
		if bub != null and is_instance_valid(bub):
			bub.queue_free()
	_chat_bubbles.clear()
	for bid in _building_nodes.keys():
		var bn = _building_nodes[bid]
		if bn != null and is_instance_valid(bn):
			bn.queue_free()
	_building_nodes.clear()
	# Jeremy 2026-10-04: Seven Monasteries — clear + rebuild from save.
	for mid in _monastery_nodes.keys():
		var mn = _monastery_nodes[mid]
		if mn != null and is_instance_valid(mn):
			mn.queue_free()
	_monastery_nodes.clear()
	if monasteries != null:
		for m: Dictionary in monasteries.monasteries:
			_add_monastery_node(m)
	# Jeremy 2026-10-04: Seven Dark Crystals — clear + rebuild from save.
	for cid in _crystal_nodes.keys():
		var cn = _crystal_nodes[cid]
		if cn != null and is_instance_valid(cn):
			cn.queue_free()
	_crystal_nodes.clear()
	if crystals != null:
		for c: Dictionary in crystals.crystals:
			_add_crystal_node(c)
	fx.clear_all_building_fires()
	# Rebuild from restored records.
	for u in game.units:
		if u.get("alive", false):
			_add_unit_node(u)
	for b in game.buildings:
		_add_building_node(b)
	# Jeremy 2026-10-05: re-link tree sites to their props (chop shake /
	# fell visuals); pickup nodes re-sync on the next visual tick.
	_link_tree_props()
	_clear_pickup_nodes()
	selection.selectables = _collect_selectables()
	return true


## Harvestable sites seeded from mapgen props. Trees are individual sites;
## resource clusters near starts become richer sites of matching kind.
## (Param named `md` — it shadows nothing; the member is `map_data`.)
func _seed_work_sites(md: Dictionary) -> void:
	var trees: PackedVector2Array = md.get("trees", PackedVector2Array())
	for p: Vector2 in trees:
		game.add_work_site({"kind": "tree", "position": p, "amount": 60.0,
			"yield": 60.0})
	# Jeremy 2026-10-05: NO wood piles — trees are the only wood source.
	# Jeremy 2026-10-05: NO oil piles either — oil pumps in industrial
	# zones are the only oil source. ("oil"/"wood" resources no longer
	# generate; the guards below are for old data.)
	for r: Dictionary in md.get("resources", []):
		var rtype: String = String(r.get("type", "wood"))
		if rtype == "wood" or rtype == "oil":
			continue
		game.add_work_site({
			"kind": "gold_vein", "position": r.get("position", Vector2.ZERO),
			"amount": 150.0})
	_link_tree_props()


## Jeremy 2026-10-05: link tree work sites to their MapProp visuals by
## position so chop shake and felling animate the right tree. Runs on new
## games and after save loads (props are rebuilt from the seed either way).
func _link_tree_props() -> void:
	_tree_prop_by_site.clear()
	_fell_animated.clear()
	var by_pos: Dictionary = {}
	for prop: MapProp in map_renderer.tree_props:
		if not is_instance_valid(prop):
			continue
		by_pos[Vector2i(int(prop.position.x), int(prop.position.y))] = prop
	var unlinked: Array = []
	for s: Dictionary in game.work_sites:
		if String(s.get("kind", "")) != "tree":
			continue
		var sid := int(s.get("id", 0))
		var p: Vector2 = s.get("position", Vector2.ZERO)
		var key := Vector2i(int(p.x), int(p.y))
		if by_pos.has(key):
			var prop: MapProp = by_pos[key]
			prop.site_id = sid
			_tree_prop_by_site[sid] = prop
		else:
			unlinked.append(s)
	# Float round-trips (save/load) can nudge a position across an integer
	# boundary — fall back to a nearest-prop search for the rare misses.
	for s: Dictionary in unlinked:
		var p: Vector2 = s.get("position", Vector2.ZERO)
		var best: MapProp = null
		var best_d := 6.0
		for prop: MapProp in map_renderer.tree_props:
			if not is_instance_valid(prop):
				continue
			var d: float = p.distance_to(prop.position)
			if d < best_d:
				best_d = d
				best = prop
		if best != null:
			var sid := int(s.get("id", 0))
			best.site_id = sid
			_tree_prop_by_site[sid] = best
	# Felled-before-save trees should already be down on load.
	for s: Dictionary in game.work_sites:
		if String(s.get("kind", "")) == "tree" and bool(s.get("felled", false)):
			var sid := int(s.get("id", 0))
			_fell_animated[sid] = true
			if _tree_prop_by_site.has(sid):
				var fp: MapProp = _tree_prop_by_site[sid]
				if is_instance_valid(fp):
					fp.queue_free()
				_tree_prop_by_site.erase(sid)


## Jeremy 2026-10-05: tree chop/fell + pickup visual sync (~4 Hz). Trees
## being worked shake; newly felled trees topple; pickup nodes mirror the
## sim's pickup list.
func _sync_tree_fx() -> void:
	if game == null:
		return
	# Which tree sites are being chopped right now.
	var chopping: Dictionary = {}
	for u: Dictionary in game.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("work_state", "")) != "gathering":
			continue
		var sid := int(u.get("work_site", 0))
		if sid == 0 or not _tree_prop_by_site.has(sid):
			continue
		chopping[sid] = true
	for sid in _tree_prop_by_site.keys():
		var prop: MapProp = _tree_prop_by_site[sid]
		if not is_instance_valid(prop):
			_tree_prop_by_site.erase(sid)
			continue
		prop.set_chopping(chopping.has(sid))
	# Newly felled trees topple (once each).
	for s: Dictionary in game.work_sites:
		if String(s.get("kind", "")) != "tree":
			continue
		if not bool(s.get("felled", false)):
			continue
		var fsid := int(s.get("id", 0))
		if _fell_animated.has(fsid):
			continue
		_fell_animated[fsid] = true
		if _tree_prop_by_site.has(fsid):
			var fprop: MapProp = _tree_prop_by_site[fsid]
			_tree_prop_by_site.erase(fsid)
			if is_instance_valid(fprop):
				fprop.set_chopping(false)
				fprop.play_fall()
	_sync_pickups()


## Jeremy 2026-10-05: mirror the sim's ground-pickup list with small
## log-pile sprites. Collected/expired pickups free their nodes.
## Jeremy 2026-10-07: per-kind visuals — wood keeps the log pile; food
## (fisher catches) and the Stinky Gizmundo get procedural fish sprites
## (green + stink lines for the Gizmundo) instead of log piles.
func _sync_pickups() -> void:
	if _pickups_root == null:
		return
	var seen: Dictionary = {}
	for p: Dictionary in game.pickups:
		var pid := int(p.get("id", 0))
		seen[pid] = true
		if _pickup_nodes.has(pid):
			continue
		var node := Node2D.new()
		node.position = p.get("position", Vector2.ZERO)
		node.add_child(_make_pickup_visual(String(p.get("kind", "wood"))))
		_pickups_root.add_child(node)
		_pickup_nodes[pid] = node
	for pid in _pickup_nodes.keys():
		if not seen.has(pid):
			_clear_pickup_node(pid)


## Builds the visual child for one ground pickup by kind (called from
## _sync_pickups). Wood keeps the log-pile sprite; food and the Stinky
## Gizmundo get procedural fish sprites.
func _make_pickup_visual(kind: String) -> Node2D:
	if kind == "food" or kind == "gizmundo":
		var f := _FishPickup.new()
		f.stinky = (kind == "gizmundo")
		return f
	var spr := Sprite2D.new()
	var tex: Texture2D = Art.resource_node_texture("wood")
	if tex == null:
		tex = Art.resource_icon("wood")
	if tex != null:
		spr.texture = tex
		var sc: float = 26.0 / float(tex.get_height())
		spr.scale = Vector2(sc, sc)
		spr.position = Vector2(0, -10.0)
		spr.rotation = randf() * TAU
	return spr


func _clear_pickup_node(pid: int) -> void:
	if _pickup_nodes.has(pid):
		var n: Node = _pickup_nodes[pid]
		_pickup_nodes.erase(pid)
		if is_instance_valid(n):
			n.queue_free()


func _clear_pickup_nodes() -> void:
	for pid in _pickup_nodes.keys():
		_clear_pickup_node(pid)


## Starting stockpiles so the player can build immediately (HTML did the same).
## Sized to cover the demo town: hall (150w/100s) + house (60w/20s) +
## farm (40w) + fire station (90w/60s/40g) + guard tower (70w/70s) =
## 410w/250s/40g.
func _grant_starting_resources(factions: Array[String]) -> void:
	# Bypass caps: this is a one-time starting grant, not an economy gain.
	# (Demo needs 250 oil; baseline cap is 200.)
	for f: String in factions:
		game.resources.add_resource(f, "wood", 1000.0, true)
		game.resources.add_resource(f, "oil", 600.0, true)
		game.resources.add_resource(f, "gold", 250.0, true)
		game.resources.add_resource(f, "food", 120.0, true)
		game.resources.add_resource(f, "seeds", 50.0, true)


## Jeremy 2026-10-07 (town-spacing bug): the starting-town building layout,
## as offsets from the faction start. Two rings around the town hall; every
## pair satisfies footprint(a)+footprint(b)+SimBuildings.PLACEMENT_GAP, the
## same rule the AI auto-layout enforces via can_place_at. The old layout
## packed everything 35-145px apart and footprints overlapped on Jeremy's
## iPhone (watchtower/fire station/town hall/houses). COMPLETED set lists
## the buildings that start finished; the rest start as blueprints.
const DEMO_TOWN_LAYOUT := {
	"town_hall": Vector2(0, 0),
	"guild_hall": Vector2(-210, 0),
	"jail": Vector2(210, 0),
	"courthouse": Vector2(0, -210),
	"fire_station": Vector2(0, 210),
	"house": Vector2(420, 0),
	"farm": Vector2(-420, 0),
	"guard_tower": Vector2(0, -420),
	"barn": Vector2(0, 420),
	"coop": Vector2(297, 297),
}
const DEMO_TOWN_COMPLETED: Array[String] = [
	"guild_hall", "jail", "courthouse", "barn", "coop",
]
const DEMO_TOWN_BLUEPRINTS: Array[String] = [
	"fire_station", "house", "farm", "guard_tower",
]


## Demo content per faction: town + hall, three blueprints (house, farm,
## fire station — the last demos essential-service auto-staffing), and a
## 7-unit crew with real jobs. All records go through spawner/blueprints
## (caps enforced, resources deducted, events emitted).
func _spawn_demo(factions: Array[String], starts: Dictionary) -> void:
	# City names dealt uniquely per game (HTML CITY_NAME_POOL parity).
	var city_deck: Array = Config.CITY_NAMES.duplicate()
	city_deck.shuffle()
	var city_idx := 0
	for f: String in factions:
		if not starts.has(f):
			continue  # mapgen gave this faction no start — skip, don't crash
		var start: Vector2 = starts[f]
		var city_name: String = city_deck[city_idx % city_deck.size()]
		city_idx += 1
		var town: Dictionary = game.found_town(f, city_name, start)
		var town_id: int = int(town["id"])
		# The hall goes first (government staff spawn around it), then the
		# rest of the starting town from DEMO_TOWN_LAYOUT: completed
		# buildings arrive finished, the rest as blueprints the crew raises.
		var hall_rec: Dictionary = _complete_building("town_hall", f, town_id,
			start + DEMO_TOWN_LAYOUT["town_hall"])
		_add_building_node(hall_rec)
		# Jeremy 2026-10-04: government advisors (HTML ensureGovernmentDistrict
		# parity) — one Treasury/War/Civic advisor + Draft Clerk per faction.
		for adv: Dictionary in game.spawner.spawn_government_staff(f, town_id, hall_rec):
			_add_unit_node(adv)
		# Jeremy 2026-10-03: every faction starts with a guild hall so the
		# guild master spawns and begins recruiting immediately.
		# Jeremy 2026-10-04: every faction starts with a jail (cells for
		# pretrial detention and sentences) and a courthouse (live trials;
		# a judge auto-staffs, jurors are picked from the town).
		# Farm animals: barn + coop start built so livestock moves in
		# immediately (HTML s8StockFarmAnimals).
		for btype: String in DEMO_TOWN_LAYOUT.keys():
			if btype == "town_hall":
				continue
			var pos: Vector2 = start + DEMO_TOWN_LAYOUT[btype]
			if btype in DEMO_TOWN_COMPLETED:
				_add_building_node(_complete_building(btype, f, town_id, pos))
			elif btype in DEMO_TOWN_BLUEPRINTS:
				_add_building_node(buildings_sys.place_blueprint(
					btype, f, town_id, pos))
		if game.get("farming") != null:
			game.farming.create_plot(f, start + Vector2(-420, 35), -1, true)

		var jobs: Array[String] = ["worker", "builder", "woodcutter",
			"farmer", "hunter", "firefighter", "doctor", "soldier", "archer"]
		for j: String in jobs:
			var pos := start + Vector2(randf_range(-90.0, 90.0),
				randf_range(-70.0, 70.0))
			var u: Dictionary = game.spawner.spawn_unit(f, j, town_id, pos)
			if u.is_empty():
				continue  # cap said no — the spawner is the law
			_add_unit_node(u)


## Seeds wildlife: wild boars scattered + near towns, wolf packs in the
## deep wilds (HTML worldgen parity).
func _seed_wildlife(factions: Array[String], starts: Dictionary,
		gen: MapGen, world_size: Vector2) -> void:
	var centers: Array = []
	for f: String in factions:
		if starts.has(f):
			centers.append(starts[f])
	var is_water := func(p: Vector2) -> bool:
		return MapGen.is_water(gen.tile_at(map_data, p))
	game.animals.seed_wildlife(centers, is_water,
		world_size.x, world_size.y)


## Directly creates a COMPLETED building (town halls start built).
func _complete_building(btype: String, faction: String, town_id: int,
		pos: Vector2) -> Dictionary:
	var b: Dictionary = buildings_sys.place_blueprint(btype, faction, town_id, pos)
	if b.is_empty():
		return {}
	b["complete"] = true
	b["progress"] = 1.0
	return b


func _add_unit_node(u: Dictionary) -> void:
	var uid := int(u.get("id", -1))
	if uid < 0:
		return  # malformed record — never create a node without an id
	var un := UnitNode.new()
	un.setup(uid, String(u.get("faction", "")), String(u.get("job", "")),
		u.get("position", Vector2.ZERO), String(u.get("gender", "m")))
	units_root.add_child(un)
	_unit_nodes[uid] = un
	selection.selectables.append(un)


func _add_building_node(b: Dictionary) -> void:
	if b.is_empty():
		return
	var bid := int(b.get("id", -1))
	if bid < 0:
		return  # malformed record — never create a node without an id
	var bn := BuildingNode.new()
	bn.setup(bid, String(b.get("type", "")), String(b.get("faction", "")),
		b.get("position", Vector2.ZERO))
	bn.record = b  # live link: scaffolding animates as progress changes
	buildings_root.add_child(bn)
	_building_nodes[bid] = bn
	selection.selectables.append(bn)


## Jeremy 2026-10-04: Seven Monasteries — visual node per sanctuary.
func _add_monastery_node(m: Dictionary) -> void:
	if m.is_empty():
		return
	var mid := int(m.get("id", -1))
	if mid < 0:
		return  # malformed record — never create a node without an id
	var mn := MonasteryNode.new()
	mn.setup(mid, String(m.get("god_id", "")),
		m.get("position", Vector2.ZERO))
	mn.record = m  # live link: owner/progress update the visuals
	monasteries_root.add_child(mn)
	_monastery_nodes[mid] = mn
	selection.selectables.append(mn)


## Jeremy 2026-10-04: Seven Monasteries — capture flash + node refresh.
func _on_monastery_captured(god_id: String, faction: String) -> void:
	for mid: int in _monastery_nodes.keys():
		var mn: MonasteryNode = _monastery_nodes[mid]
		if is_instance_valid(mn):
			mn.flash_force_field()
			mn.queue_redraw()


## Jeremy 2026-10-06 (Battlefront directive): halls FLIP faction on war
## capture instead of being destroyed. Re-point the building node at the
## new holder so its pennant (and any faction-variant sprite art) visibly
## changes to the new faction color. Monastery/crystal nodes need no call
## here — they read their record's owner live every redraw (4 Hz).
## Jeremy 2026-10-07 (graphics hourly): a town flipping is the war's
## biggest visible moment — flash the hall in the conqueror's faction
## color (same 340px/0.7s scale as the monastery/crystal capture flashes).
func _on_command_post_captured(kind: String, post_id: int, old_holder: String,
		new_holder: String, pos: Vector2) -> void:
	if kind != "town":
		return
	# Fanfare first: the capture is real in the sim even if this world
	# node hasn't synced yet — the flash must never depend on the lookup.
	var fc: Color = Config.FACTIONS.get(new_holder, {}).get("color",
		Color(1, 1, 1))
	_flash_light(pos, fc, 340.0, 0.7)
	var bn: BuildingNode = _building_nodes.get(post_id) as BuildingNode
	if bn != null and is_instance_valid(bn):
		bn.set_faction(new_holder)


## Jeremy 2026-10-04: Seven Monasteries — flash the sanctuary nearest a
## force-field / capture event so its shimmer is visible.
func _flash_monastery_at(pos: Vector2) -> void:
	var best: MonasteryNode = null
	var best_d := 400.0 * 400.0
	for mid: int in _monastery_nodes.keys():
		var mn: MonasteryNode = _monastery_nodes[mid]
		if not is_instance_valid(mn):
			continue
		var d2: float = pos.distance_squared_to(mn.position)
		if d2 < best_d:
			best_d = d2
			best = mn
	if best != null:
		best.flash_force_field()


## Jeremy 2026-10-04: Seven Dark Crystals — visual node per crystal.
func _add_crystal_node(c: Dictionary) -> void:
	if c.is_empty():
		return
	var cid := int(c.get("id", -1))
	if cid < 0:
		return  # malformed record — never create a node without an id
	var cn := CrystalNode.new()
	cn.setup(cid, String(c.get("god_id", "")),
		c.get("position", Vector2.ZERO))
	cn.record = c  # live link: owner/progress update the visuals
	crystals_root.add_child(cn)
	_crystal_nodes[cid] = cn
	selection.selectables.append(cn)


## Jeremy 2026-10-04: Seven Dark Crystals — capture flash + node refresh.
func _on_crystal_captured(god_id: String, faction: String) -> void:
	for cid: int in _crystal_nodes.keys():
		var cn: CrystalNode = _crystal_nodes[cid]
		if is_instance_valid(cn):
			cn.flash_force_field()
			cn.queue_redraw()


## Jeremy 2026-10-04: Seven Dark Crystals — storm lightning struck a
## crystal: flash the node so the strike is visible.
func _on_crystal_struck(crystal_id: int, pos: Vector2) -> void:
	var cn: CrystalNode = _crystal_nodes.get(crystal_id, null)
	if cn != null and is_instance_valid(cn):
		cn.flash_strike()


## Jeremy 2026-10-04: Seven Dark Crystals — flash the crystal nearest a
## force-field / capture event so its shimmer is visible.
func _flash_crystal_at(pos: Vector2) -> void:
	var best: CrystalNode = null
	var best_d := 400.0 * 400.0
	for cid: int in _crystal_nodes.keys():
		var cn: CrystalNode = _crystal_nodes[cid]
		if not is_instance_valid(cn):
			continue
		var d2: float = pos.distance_squared_to(cn.position)
		if d2 < best_d:
			best_d = d2
			best = cn
	if best != null:
		best.flash_force_field()


## Sim events -> visuals.
func _on_unit_spawned(unit: Dictionary) -> void:
	if _unit_nodes.has(int(unit.get("id", 0))):
		return
	_add_unit_node(unit)


func _on_building_placed(building: Dictionary) -> void:
	if _building_nodes.has(int(building.get("id", 0))):
		return
	_add_building_node(building)


## ---- Milestone 4: combat & disaster visuals -------------------------------


func _on_projectile_fired(p: Dictionary) -> void:
	var pn := ProjectileNode.new()
	pn.setup(int(p.get("id", 0)), String(p.get("kind", "arrow")))
	pn.position = p.get("position", Vector2.ZERO)
	projectiles_root.add_child(pn)
	_proj_nodes[int(p.get("id", 0))] = pn
	# HTML playSpatial parity: launch whoosh with velocity for Doppler pitch.
	var from_pos: Vector2 = p.get("position", Vector2.ZERO)
	var target_pos: Vector2 = p.get("target_pos", from_pos)
	var dir := target_pos - from_pos
	var vel := Vector2.ZERO
	if dir.length() > 1.0:
		vel = dir.normalized() * float(p.get("speed", 400.0))
	# HTML SFX parity (fix79 const SFX): archer fires -> bow, musketeer ->
	# bullet, cannoneer -> cannon, grape cannon -> grape, mage fireball
	# cast -> shoot, artillery rockets -> rocket, AA interceptor -> aa.
	# The Doppler flyby whoosh stays for the rest.
	var sfx := "whoosh"
	match String(p.get("kind", "arrow")):
		"arrow":
			sfx = "bow"
		"bullet":
			sfx = "bullet"
		"cannonball":
			sfx = "cannon"
		"grape":
			sfx = "grape"
		"mortar":
			sfx = "mortar"
		"rocket", "jumbo_rocket", "crashing_rocket":
			sfx = "rocket"
		"aa":
			sfx = "aa"
		"spell":
			sfx = "shoot"
	game.bus.sfx_spatial.emit(sfx, from_pos, vel)


func _on_projectile_done(p: Dictionary) -> void:
	var pn: ProjectileNode = _proj_nodes.get(int(p.get("id", 0))) \
		as ProjectileNode
	if pn != null and is_instance_valid(pn):
		pn.queue_free()
	_proj_nodes.erase(int(p.get("id", 0)))


func _on_projectile_hit(p: Dictionary, impact: Vector2) -> void:
	# Jeremy 2026-10-04: nukes get the full detonation visual from
	# combat_fx "nuke_blast" (routed in _on_combat_fx) — no generic boom.
	if String(p.get("kind", "")) == "nuke":
		return
	if float(p.get("splash", 0.0)) > 0.0:
		fx.explosion(impact, float(p.get("splash", 60.0)))
		_flash_light(impact, Color(1.0, 0.55, 0.2), 230.0)
	else:
		fx.hit_flash(impact)
		_flash_light(impact, Color(1.0, 0.75, 0.45), 120.0)
	if String(p.get("kind", "")) == "cannonball":
		fx.muzzle(impact)
	# HTML SFX parity (fix79 projectile impacts): arrow/bullet -> hit;
	# artillery and spell blasts (cannonball/mortar/rocket/fireball/
	# lightning) -> explode.
	var kind := String(p.get("kind", ""))
	var sfx := "hit"
	match kind:
		"cannonball", "grape", "mortar", "rocket", "jumbo_rocket", \
		"crashing_rocket", "spell":
			sfx = "explode"
	game.bus.sfx_spatial.emit(sfx, impact, Vector2.ZERO)


## Combat FX router: sim emits kind+position, we play the visual + light.
## (Jeremy 2026-10-04: everything must have good graphics.)
## Jeremy 2026-10-08: floating damage numbers — one pooled text pop per
## landed hit. Plain text only, never a bubble (2026-10-05 ban).
func _on_unit_damaged(_unit_id: int, amount: float, pos: Vector2, kind: String) -> void:
	if dmg_nums != null and is_instance_valid(dmg_nums):
		dmg_nums.spawn(amount, pos, kind)


func _on_combat_fx(kind: String, pos: Vector2) -> void:
	match kind:
		"muzzle":
			fx.muzzle(pos)
		"muzzle_big":
			fx.muzzle_big(pos)
			_flash_light(pos, Color(1.0, 0.8, 0.4), 150.0, 0.2)
		"spell_fire":
			fx.spell_fire(pos)
			_flash_light(pos, Color(1.0, 0.45, 0.15), 180.0, 0.3)
		"spell_lightning":
			fx.spell_lightning(pos)
			_flash_light(pos, Color(0.7, 0.9, 1.0), 200.0, 0.25)
		"spell_arcane":
			fx.spell_arcane(pos)
			_flash_light(pos, Color(0.7, 0.3, 1.0), 180.0, 0.3)
		"spell_nature":
			fx.spell_nature(pos)
			_flash_light(pos, Color(0.3, 0.9, 0.4), 170.0, 0.35)
		# ---- Seven Monasteries (Jeremy 2026-10-04) ----
		"spell_dawn":
			fx.spell_fire(pos)
			_flash_light(pos, Color(1.0, 0.85, 0.35), 190.0, 0.35)
		"spell_thorn":
			fx.spell_nature(pos)
			_flash_light(pos, Color(0.3, 0.72, 0.32), 170.0, 0.35)
		"spell_storm":
			fx.spell_lightning(pos)
			_flash_light(pos, Color(0.55, 0.78, 1.0), 200.0, 0.3)
		"spell_ember":
			fx.spell_fire(pos)
			_flash_light(pos, Color(1.0, 0.52, 0.2), 180.0, 0.3)
		"spell_truth":
			fx.spell_arcane(pos)
			_flash_light(pos, Color(0.62, 0.45, 0.92), 180.0, 0.3)
		"spell_aegis":
			fx.spell_arcane(pos)
			_flash_light(pos, Color(0.42, 0.58, 0.8), 180.0, 0.3)
		"spell_joy":
			fx.spell_nature(pos)
			_flash_light(pos, Color(1.0, 0.55, 0.68), 170.0, 0.35)
		"force_field":
			_flash_monastery_at(pos)
			_flash_light(pos, Color(0.6, 0.85, 1.0), 260.0, 0.5)
		# ---- Seven Dark Crystals (Jeremy 2026-10-04) ----
		"dark_umbral":
			fx.dark_blast(pos)
			_flash_light(pos, Color(0.45, 0.15, 0.75), 260.0, 0.5)
		"dark_plague":
			fx.dark_blast(pos)
			_flash_light(pos, Color(0.35, 0.55, 0.15), 240.0, 0.5)
		"dark_worldender":
			fx.sky_strike(pos)
			_flash_light(pos, Color(0.7, 0.6, 1.0), 320.0, 0.6)
		"dark_hellfire":
			fx.hellfire(pos)
			_flash_light(pos, Color(0.9, 0.12, 0.05), 280.0, 0.55)
		"dark_mind":
			fx.dark_bolt(pos)
			_flash_light(pos, Color(0.5, 0.5, 0.62), 220.0, 0.45)
		"dark_fist":
			fx.dark_blast(pos)
			_flash_light(pos, Color(0.9, 0.3, 0.25), 280.0, 0.55)
		"dark_malice":
			fx.dark_blast(pos)
			_flash_light(pos, Color(0.78, 0.08, 0.48), 240.0, 0.5)
		"sky_strike":
			fx.sky_strike(pos)
			_flash_light(pos, Color(0.9, 0.9, 1.0), 320.0, 0.6)
		"knockback":
			_flash_light(pos, Color(1.0, 0.9, 0.6), 150.0, 0.25)
		"crit":
			fx.dark_bolt(pos)
			_flash_light(pos, Color(1.0, 0.3, 0.3), 200.0, 0.4)
		"rampage":
			_flash_light(pos, Color(0.8, 0.1, 0.1), 180.0, 0.4)
		"crystal_strike":
			fx.sky_strike(pos)
			_flash_light(pos, Color(0.75, 0.5, 1.0), 340.0, 0.7)
		"force_field_dark":
			_flash_crystal_at(pos)
			_flash_light(pos, Color(0.55, 0.2, 0.8), 260.0, 0.5)
		"capture_dark":
			_flash_crystal_at(pos)
			_flash_light(pos, Color(0.55, 0.2, 0.8), 300.0, 0.6)
		"capture":
			_flash_monastery_at(pos)
			_flash_light(pos, Color(1.0, 0.85, 0.35), 300.0, 0.6)
		"capture_taken":
			_flash_monastery_at(pos)
			_flash_light(pos, Color(1.0, 0.45, 0.3), 300.0, 0.6)
		"snare":
			fx.snare_fx(pos)
		"siege_hit":
			fx.siege_hit(pos)
			_flash_light(pos, Color(1.0, 0.7, 0.4), 160.0, 0.25)
			game.bus.sfx_spatial.emit("boom", pos, Vector2.ZERO)
		"building_burning":
			# The burning-building system picks this up via building_burning
			# signal; here we just ensure a fire visual exists.
			pass
		# ---- Blood & gore (HTML spawnGore / bloodStains parity) ----
		"blood":
			# Jeremy 2026-10-05: this case was missing — combat.gd's
			# _bus_blood emits "blood" on every hit, but it fell through
			# to the default branch and never rendered.
			fx.blood(pos)
		"gore_limb":
			fx.gore(pos, "limb", 1)
		"gore_chunk":
			fx.gore(pos, "chunk", 1)
		"gore_metal":
			fx.gore(pos, "metal", 1)
		"blood_stains":
			# 14 persistent ground stains per severed limb (HTML parity).
			fx.blood_stain(pos, 14)
		"crater":
			# Jeremy 2026-10-04: artillery knocks a big cartoon crater.
			fx.crater(pos, 90.0)
		# ---- Nuclear warfare (Jeremy 2026-10-04) ----
		"nuke_blast":
			fx.nuke_blast(pos)
			_flash_light(pos, Color(1.0, 0.95, 0.8), 900.0, 1.2)
			game.bus.sfx_spatial.emit("explode", pos, Vector2.ZERO)
		"nuke_launch":
			fx.muzzle_big(pos)
			_flash_light(pos, Color(1.0, 0.8, 0.4), 260.0, 0.6)
			game.bus.sfx_spatial.emit("launch", pos, Vector2.ZERO)
		"rad_scorch":
			# Jeremy 2026-10-06: radiation zone ground scorch (HTML zone
			# tick radScorch stain).
			fx.scorch_spot(pos)
		_:
			# Gibs: "gib_<faction>" — artillery blows units into bits.
			if kind.begins_with("gib_"):
				fx.gib(pos, kind.trim_prefix("gib_"))


func _on_unit_killed(unit_id: int, _source_faction: String) -> void:
	var un: UnitNode = _unit_nodes.get(unit_id) as UnitNode
	if un != null and is_instance_valid(un):
		un.play_death()
		fx.death_poof(un.position)
		_dying[unit_id] = 0.0
		selection.selectables.erase(un)
	_prev_combat_state.erase(unit_id)


func _on_unit_purged(unit_id: int) -> void:
	_free_unit_node(unit_id)


## Milestone 5: nearby friends grieve the dead (sad + memory).
func _on_unit_died_mind(unit_id: int, faction: String) -> void:
	if mind != null:
		mind.on_unit_died(unit_id, faction)


## Milestone 5: an NPC said a scripted line.
## Jeremy 2026-10-05: all bubbles removed at Jeremy's call — no SpeechBubble
## is ever spawned here. Jeremy 2026-10-07 ("Overheard"): the line is NOT
## swallowed anymore; it goes through ChatterDirector (camera-proximity
## cull, throttle, small queue) to the HUD subtitle ticker — one slim line
## of HUD chrome above the bottom bar, never over units, never blocking.
func _on_unit_said(unit_id: int, text: String) -> void:
	if text.strip_edges().is_empty():
		return
	var cam_pos := Vector2.ZERO
	if camera != null:
		cam_pos = camera.position
	var speaker := "Army"
	var color := ChatterTicker.SYSTEM_COLOR
	var upos := cam_pos
	var has_pos := false
	var said_u: Dictionary = {}
	if unit_id > 0 and game != null:
		var u: Dictionary = game.get_unit(unit_id)
		if u.is_empty():
			return
		said_u = u
		upos = u.get("position", cam_pos)
		has_pos = true
		var mind: Dictionary = u.get("mind", {})
		speaker = String(mind.get("name", "")).strip_edges()
		var ujob := String(u.get("job", "")).strip_edges()
		if speaker.is_empty():
			speaker = "A " + ujob if not ujob.is_empty() else "Someone"
		color = Art.faction_accent(String(u.get("faction", "")))
		# Graphics hourly 2026-10-07: the gig gnome's treasury skim gets
		# SEEN — fee lines ("Service charge ($14)") fly gold coins from the
		# town to his bag. Pure visual; the sim's fee logic is untouched.
		if ujob == "gig_gnome" and _is_driver_fee_line(text):
			_driver_fee_fx(said_u)
	_chatter.offer(has_pos, upos, cam_pos, speaker, color, text)
	# Jeremy 2026-10-07: RuneScape-style chat bubbles. Speech from a real
	# unit with a world position ALSO gets a small bubble above the
	# speaker's head (the subtitle ticker keeps running in parallel).
	# System shouts (no unit/position) stay ticker-only — no bubble.
	if has_pos and unit_id > 0:
		_spawn_chat_bubble(unit_id, upos, text)


## RuneScape-style chat bubbles (Jeremy 2026-10-07). Max concurrent
## bubbles, kept nearest to the camera — the anti-clutter cap Jeremy
## demanded after the 2026-10-05 bubble-pocalypse.
const MAX_CHAT_BUBBLES := 8
## Bubble anchor: above the chibi head.
const BUBBLE_HEAD_OFFSET := Vector2(0, -72)


## Spawn (or refresh) a speech bubble for a unit. One bubble per NPC:
## new speech replaces the old bubble and restarts its fade timer.
## Distant speech (beyond chatter earshot) gets no bubble.
func _spawn_chat_bubble(unit_id: int, upos: Vector2, text: String) -> void:
	if camera != null and upos.distance_to(camera.position) > ChatterDirector.RADIUS:
		return
	var bub: ChatBubble = _chat_bubbles.get(unit_id) as ChatBubble
	if bub != null and is_instance_valid(bub):
		bub.setup(text)
		bub.position = upos + BUBBLE_HEAD_OFFSET
		return
	_cull_chat_bubbles()
	bub = ChatBubble.new()
	bub.setup(text)
	bub.position = upos + BUBBLE_HEAD_OFFSET
	add_child(bub)
	_chat_bubbles[unit_id] = bub


## Drop the farthest bubbles when over the cap. Called before spawning
## a new one, so the count never exceeds MAX_CHAT_BUBBLES.
func _cull_chat_bubbles() -> void:
	_prune_dead_chat_bubbles()
	if _chat_bubbles.size() < MAX_CHAT_BUBBLES:
		return
	var cam := Vector2.ZERO
	if camera != null:
		cam = camera.position
	var ids: Array = _chat_bubbles.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		var pa: Vector2 = (_chat_bubbles[a] as ChatBubble).position
		var pb: Vector2 = (_chat_bubbles[b] as ChatBubble).position
		return pa.distance_squared_to(cam) > pb.distance_squared_to(cam))
	while _chat_bubbles.size() >= MAX_CHAT_BUBBLES and not ids.is_empty():
		var drop_id: int = ids.pop_back()
		var drop: ChatBubble = _chat_bubbles.get(drop_id) as ChatBubble
		_chat_bubbles.erase(drop_id)
		if drop != null and is_instance_valid(drop):
			drop.queue_free()


## Forget bubbles whose node freed itself (fade finished) or whose unit
## is gone. Keeps the dict honest.
func _prune_dead_chat_bubbles() -> void:
	var dead: Array = []
	for uid: int in _chat_bubbles.keys():
		var bub: ChatBubble = _chat_bubbles.get(uid) as ChatBubble
		if bub == null or not is_instance_valid(bub):
			dead.append(uid)
	for uid: int in dead:
		_chat_bubbles.erase(uid)


## Per-frame: bubbles follow their speakers. Dead units' bubbles are
## dropped. Called from _process.
func _tick_chat_bubbles() -> void:
	if _chat_bubbles.is_empty():
		return
	_prune_dead_chat_bubbles()
	if game == null:
		return
	var gone: Array = []
	for uid: int in _chat_bubbles.keys():
		var bub: ChatBubble = _chat_bubbles.get(uid) as ChatBubble
		if bub == null or not is_instance_valid(bub):
			continue
		var u: Dictionary = game.get_unit(uid)
		if u.is_empty():
			gone.append(uid)
			continue
		bub.position = u.get("position", bub.position) + BUBBLE_HEAD_OFFSET
	for uid: int in gone:
		var bub: ChatBubble = _chat_bubbles.get(uid) as ChatBubble
		_chat_bubbles.erase(uid)
		if bub != null and is_instance_valid(bub):
			bub.queue_free()


## Surrender ceremony (Jeremy 2026-10-04): plant a white flag at the
## loser's town hall + a golden peace burst. The flag lowers itself
## after FLAG_DAYS game days (_tick_surrender_flags).
var _surrender_flags: Array = []  # {node, day_planted, outro_started}

func _on_surrender_offered(loser: String, _winner: String) -> void:
	# A white flag also flies while the offer is pending — the loser has
	# already raised it by suing for peace.
	_plant_surrender_flag(loser)


func _on_surrender_accepted(loser: String, winner: String) -> void:
	_plant_surrender_flag(loser)
	# Golden peace burst over both capitals.
	for f: String in [loser, winner]:
		var hall: Dictionary = _faction_hall(f)
		if not hall.is_empty():
			_flash_light(hall.get("position", Vector2.ZERO),
				Color(1.0, 0.9, 0.55), 320.0, 1.2)


func _plant_surrender_flag(faction: String) -> void:
	# One flag per faction at a time.
	for e: Dictionary in _surrender_flags:
		if String(e.get("faction", "")) == faction:
			return
	var hall: Dictionary = _faction_hall(faction)
	if hall.is_empty():
		return
	var flag := SurrenderFlag.new()
	flag.setup(game.day_number)
	flag.position = hall.get("position", Vector2.ZERO) + Vector2(0, -10)
	add_child(flag)
	_surrender_flags.append({"node": flag, "faction": faction,
		"day_planted": game.day_number, "outro_started": false})


## ---- Spark-driver delivery-fee coin flight (graphics hourly 2026-10-07) ---
## The sim skims a treasury fee every 45s and announces it over
## bus.unit_said ("Service charge ($14)"). This is the visual half: gold
## coins arc from the town center into the driver's bag and pop with a
## small gold flash, so Jeremy SEES the meter running. Triggered from
## _on_unit_said; zero sim touch — the fee amounts and cadence live in
## disasters.gd. Coins are transient world-space Sprite2Ds on
## projectiles_root (never culled, never saved).
const DRIVER_FEE_COINS := 5
const DRIVER_FEE_COIN_DUR := 0.9
const DRIVER_FEE_COIN_STAGGER := 0.09
const DRIVER_FEE_COIN_MAX := 15  # backpressure: skip if a flight is mid-air
var _fee_coins: Array = []  # {node, t, dur, p0, p1, p2, sc}


## Fee lines always end " ($N)" (disasters._driver_fee); shouts, the guilt
## trip, and flee lines never carry an amount. Job-gated at the call site.
func _is_driver_fee_line(text: String) -> bool:
	var clean := text.strip_edges()
	return clean.ends_with(")") and clean.find("($") >= 0


func _driver_fee_fx(u: Dictionary) -> void:
	if projectiles_root == null or not is_instance_valid(projectiles_root):
		return
	if _fee_coins.size() >= DRIVER_FEE_COIN_MAX:
		return
	var tex: Texture2D = Art.resource_icon("gold")
	if tex == null:
		return
	var from: Vector2 = u.get("driver_center", u.get("position", Vector2.ZERO))
	var to: Vector2 = u.get("position", from)
	for i in DRIVER_FEE_COINS:
		var c := Sprite2D.new()
		c.texture = tex
		var sc := 0.45 + 0.1 * float(i % 3)
		c.scale = Vector2(0.001, 0.001)  # pop-in from nothing
		c.position = from + Vector2(randf_range(-30.0, 30.0),
			randf_range(-24.0, 12.0))
		c.z_index = 60  # above units, below UI chrome
		projectiles_root.add_child(c)
		var mid: Vector2 = (c.position + to) * 0.5 + Vector2(0, -95)
		_fee_coins.append({"node": c, "t": -float(i) * DRIVER_FEE_COIN_STAGGER,
			"dur": DRIVER_FEE_COIN_DUR, "p0": c.position, "p1": mid,
			"p2": to, "sc": sc})


## Bezier coin flight: pop in, arc to the driver, spin, shrink into the
## bag. Coins that land flash gold at the bag once each.
func _tick_fee_coins(delta: float) -> void:
	if _fee_coins.is_empty():
		return
	var keep: Array = []
	for f in _fee_coins:
		var fd: Dictionary = f
		fd["t"] = float(fd["t"]) + delta
		var t: float = float(fd["t"])
		var n: Node2D = fd["node"]
		if not is_instance_valid(n):
			continue  # node freed elsewhere: drop the entry
		if t < 0.0:
			keep.append(fd)  # staggered launch: not started yet
			continue
		var k: float = clampf(t / float(fd["dur"]), 0.0, 1.0)
		var p0: Vector2 = fd["p0"]
		var p1: Vector2 = fd["p1"]
		var p2: Vector2 = fd["p2"]
		var a: Vector2 = p0.lerp(p1, k)
		var b: Vector2 = p1.lerp(p2, k)
		n.position = a.lerp(b, k)
		n.rotation += delta * 9.0
		var sc: float = float(fd["sc"])
		var pop: float = minf(k * 3.0, 1.0) * (1.0 - k * k)
		n.scale = Vector2(sc, sc) * maxf(pop, 0.001)
		if k >= 1.0:
			_flash_light(p2, Color(1.0, 0.84, 0.35), 90.0, 0.2)
			n.queue_free()
		else:
			keep.append(fd)
	_fee_coins = keep


func _faction_hall(faction: String) -> Dictionary:
	for b: Dictionary in game.buildings:
		if not b.get("alive", false):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in ["town_hall", "hall"]:
			return b
	return {}


## Called each frame: lower flags whose time has come.
func _tick_surrender_flags() -> void:
	for i: int in range(_surrender_flags.size() - 1, -1, -1):
		var e: Dictionary = _surrender_flags[i]
		var node: SurrenderFlag = e.get("node") as SurrenderFlag
		if node == null or not is_instance_valid(node):
			_surrender_flags.remove_at(i)
			continue
		if not bool(e.get("outro_started", false)) \
				and game.day_number - int(e.get("day_planted", 0)) \
					>= int(SurrenderFlag.FLAG_DAYS):
			e["outro_started"] = true
			node.begin_outro()
		# The flag frees its visuals in the outro; drop our record when
		# the node is gone (checked next tick via is_instance_valid).


func _on_building_destroyed(b: Dictionary) -> void:
	var bid: int = int(b.get("id", 0))
	fx.explosion(b.get("position", Vector2.ZERO), 70.0)
	fx.clear_building_fire(bid)
	# HTML: every building death spawns an AoE-style rubble pile.
	if _rubble != null:
		_rubble.spawn(b)
	var bn: BuildingNode = _building_nodes.get(bid) as BuildingNode
	if bn != null and is_instance_valid(bn):
		bn.queue_free()
		selection.selectables.erase(bn)
	_building_nodes.erase(bid)


func _on_fire_started(f: Dictionary) -> void:
	fx.spawn_fire(int(f.get("id", 0)), f.get("position", Vector2.ZERO))


func _on_fire_out(fire_id: int) -> void:
	fx.clear_fire(fire_id)


## HTML SFX parity (fix79 hydroFishTick -> sfxAt('splash')): fish landing in
## a splash ring plays the splash SFX. FishJumps emits fish_landed on every
## landing; the audio manager's distance cutoff keeps far jumps silent.
func _on_fish_landed(pos: Vector2) -> void:
	game.bus.sfx_spatial.emit("splash", pos, Vector2.ZERO)


func _on_disaster_spawned(kind: String, pos: Vector2) -> void:
	# Floods get water visuals, not explosions (Jeremy 2026-10-04).
	if kind == "flood_warning":
		_flash_light(pos, Color(0.3, 0.6, 1.0), 420.0, 0.8)
		if hud != null:
			hud.flash_hint("FLOOD WARNING: waters rising — seek high ground!")
		return
	if kind == "flood":
		_flash_light(pos, Color(0.2, 0.5, 1.0), 560.0, 1.2)
		if hud != null:
			hud.flash_hint("FLOOD! The waters breach their banks!")
		return
	# Arrival fanfare: monsters announce themselves.
	fx.explosion(pos, 60.0)
	_flash_light(pos, Color(0.7, 0.3, 1.0), 260.0, 0.4)


## Graphics-update helper: one-shot light burst, no-op until the rig exists.
func _flash_light(pos: Vector2, color: Color, radius: float = 170.0,
		life: float = 0.28) -> void:
	if lighting != null and is_instance_valid(lighting):
		lighting.flash(pos, color, radius, life)


func _free_unit_node(unit_id: int) -> void:
	var un: UnitNode = _unit_nodes.get(unit_id) as UnitNode
	if un != null and is_instance_valid(un):
		un.queue_free()
		selection.selectables.erase(un)
	_unit_nodes.erase(unit_id)
	_dying.erase(unit_id)
	_prev_combat_state.erase(unit_id)
	_unit_lift.erase(unit_id)
	_unit_sync_pos.erase(unit_id)


func _collect_selectables() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for c in units_root.get_children():
		if c is TraderLayer:
			continue  # caravan taps open the trade panel, not the ring
		out.append(c as Node2D)
	for c in buildings_root.get_children():
		out.append(c as Node2D)
	# Jeremy 2026-10-04: Seven Monasteries are clickable sanctuaries.
	if monasteries_root != null:
		for c in monasteries_root.get_children():
			out.append(c as Node2D)
	# Jeremy 2026-10-04: Seven Dark Crystals are clickable too.
	if crystals_root != null:
		for c in crystals_root.get_children():
			out.append(c as Node2D)
	# A non-Node2D child would append null and poison later picks.
	return out.filter(func(n: Node2D) -> bool: return n != null)


## Adventure: ease the camera toward the hero (RuneScape-style follow).
func _follow_hero(delta: float) -> void:
	var h: Dictionary = adventure.hero()
	if h.is_empty() or not h.get("alive", false):
		return
	var hp: Vector2 = h.get("position", Vector2.ZERO)
	camera.position = camera.position.lerp(hp,
		minf(1.0, delta * 3.0))
	camera.clamp_now()


## Adventure: the hero's visual node is freed on death; re-add it on respawn.
func _ensure_hero_node() -> void:
	var h: Dictionary = adventure.hero()
	if h.is_empty() or not h.get("alive", false):
		return
	var hid: int = int(h.get("id", -1))
	if not _unit_nodes.has(hid):
		_add_unit_node(h)


## Tap routing: placement consumes taps while active, else selection.
## In adventure mode, tapping the hero selects them; tapping with the hero
## selected issues move / attack orders.
func _on_tapped(screen_pos: Vector2) -> void:
	var wp: Vector2 = camera.screen_to_world(screen_pos)
	# HTML handleTap pushes the ripple at entry, before any tap handling.
	if _tap_ripples != null:
		_tap_ripples.push(wp)
	# Jeremy 2026-10-04: nuclear target mode (HTML nukeTargetMode) — an
	# armed silo is waiting for a map tap. Tapping the armed silo itself
	# stands down instead of firing (no accidental self-nukes).
	if nuclear != null and nuclear.target_silo >= 0:
		var silo: Dictionary = nuclear.silo_by_id(nuclear.target_silo)
		if not silo.is_empty():
			var spos: Vector2 = silo.get("position", Vector2.ZERO)
			if wp.distance_to(spos) <= float(silo.get("size", 30.0)) + 40.0:
				var dr: Dictionary = nuclear.toggle_arm(nuclear.target_silo)
				hud.flash_hint(String(dr.get("message", "")))
				return
		var res: Dictionary = nuclear.fire_nuke(nuclear.target_silo, wp)
		hud.flash_hint(String(res.get("message", "")))
		return
	if placement.placing:
		placement.on_tap(wp)
		_sync_wall_drag_arm()
		return
	if adventure != null and adventure.active:
		if _on_tapped_adventure(wp):
			return
	# HTML handleTap: tap rubble piles to clear them (before target selection).
	if _rubble != null:
		var cleared: Dictionary = _rubble.tap_clear(wp)
		if not cleared.is_empty():
			if hud != null:
				hud.flash_hint("Rubble cleared.")
			return
	selection.on_tapped(screen_pos)
	# Jeremy 2026-10-09 tap-command (Jeremy's spec: "tap-to-command means
	# the ENTIRE military goes on a tap — no unit selection"): tapping
	# empty ground with nothing selected opens the command menu whenever
	# the player has commandable military. Taps on own units keep their
	# info panel (selection is non-null), so this never misfires there;
	# taps on ENEMIES are handled by the enemy_tap_decision branch above.
	# Harvest taps keep the gather menu — the tutorial
	# promises "tap a tree, rock, or bush and order them to harvest".
	# Orders go to the whole military via SimTapCommand.order_all_*;
	# the menu's Cancel closes it.
	# Jeremy 2026-10-09 tap-enemy-attack (the audit's flagged follow-up):
	# tapping an ENEMY opens the command menu at the enemy with Attack
	# Target primed — the entire military engages on the button tap.
	# Enemy = a faction at war with the player, or monsters (always
	# hostile). Neutral/ally taps keep the info panel ONLY — attacking
	# them would start a war, and war is never declared by accident
	# (2026-10-04 diplomacy rule). The info panel stays up either way.
	var sel: Node2D = selection.selected
	if sel != null and is_instance_valid(sel) and hud != null \
			and game != null and game.tap_command != null:
		var tfaction := _selected_target_faction(sel)
		if enemy_tap_decision(tfaction, String(game.player_faction),
				_player_relation(tfaction),
				game.tap_command.all_military_ids().size()):
			hud.show_command_menu(wp, -1, true)
			return
	if selection.selected == null and hud != null and game != null \
			and game.tap_command != null:
		# Jeremy 2026-10-11 power tap menu: tapping a FOREIGN faction's
		# claimed land opens the contextual power menu (Send Aid, Propose
		# Trade, Offer Tribute, Message Leader, Request Aid) — never a war
		# by accident. War enemies keep the military command menu.
		var owner := SimTerritory.claim_owner_at(
			game.buildings, wp)
		if owner != "" and owner != String(game.player_faction) \
				and (owner in game.active_factions) \
				and game.diplomacy != null \
				and game.diplomacy.relation_state(
					String(game.player_faction), owner) != "war":
			hud.show_power_menu_foreign(wp, owner)
			return
		var site := nearest_harvest_site(game.work_sites, wp, 60.0)
		match tap_menu_decision(site,
				game.tap_command.all_military_ids().size()):
			"gather":
				hud.show_gather_menu(site)
				return
			"command":
				hud.show_command_menu(wp)
				return


## Nearest harvestable work site within max_dist world px of a tap.
## Headless-testable pure pick math (same shape as Selection.pick).
## Depleted sites (amount <= 0) and non-harvest kinds are skipped.
static func nearest_harvest_site(sites: Array, world_pos: Vector2,
		max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist
	for s in sites:
		var sd := s as Dictionary
		if sd == null or sd.is_empty():
			continue
		match String(sd.get("kind", "")):
			"tree", "rock", "gold_vein", "bush":
				pass
			_:
				continue
		if float(sd.get("amount", 0.0)) <= 0.0:
			continue
		var d: float = world_pos.distance_to(
			sd.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = sd
	return best


## Jeremy 2026-10-09: tap-to-command trigger decision (headless-testable).
## The tap selected nothing. "gather" = a harvest site claims the tap
## (gather keeps precedence so the tutorial's "tap a tree, rock, or bush"
## promise never regresses); "command" = the player has >= 1 commandable
## military unit and the command menu opens; "" = nothing happens (no
## army — taps must not menu-spam players with no military).
static func tap_menu_decision(site: Dictionary, military_count: int) -> String:
	if not site.is_empty():
		return "gather"
	if military_count > 0:
		return "command"
	return ""


## Jeremy 2026-10-09: tap-enemy-attack decision (headless-testable).
## True when a tap that SELECTED something should open the command menu
## in attack-target mode instead of just showing the info panel.
## Enemy = monsters (always hostile) or a faction at war with the player.
## Neutral/allied/own taps return false — attacking them would START a
## war, and war is never declared by accident.
static func enemy_tap_decision(target_faction: String,
		player_faction: String, relation: String,
		military_count: int) -> bool:
	if military_count <= 0:
		return false
	if target_faction.is_empty() or target_faction == player_faction:
		return false
	if target_faction == "monster":
		return true
	return relation == "war"


## Faction of the node a tap selected: unit nodes carry unit_id,
## building nodes carry building_id. "" when neither resolves.
func _selected_target_faction(sel: Node2D) -> String:
	if game == null:
		return ""
	if "unit_id" in sel:
		var u: Dictionary = game.get_unit(int(sel.get("unit_id")))
		return String(u.get("faction", ""))
	if "building_id" in sel:
		var b: Dictionary = game.get_building(int(sel.get("building_id")))
		return String(b.get("faction", ""))
	return ""


## Player's diplomatic relation to a faction ("" when unknown).
func _player_relation(faction: String) -> String:
	if game == null or game.diplomacy == null or faction.is_empty():
		return ""
	return String(game.diplomacy.relation_state(
		String(game.player_faction), faction))


## AoE2 wall-drag routing (buildings port). Jeremy 2026-10-11 (player road
## tool): the same press/move/release routing drives road drags while the
## road tool is armed — the placement node owns the road-drag state.
func _on_wall_pressed(screen_pos: Vector2) -> void:
	var wp := camera.screen_to_world(screen_pos)
	if placement.placing and placement.btype == "road":
		placement.on_road_press(wp)
	else:
		placement.on_wall_press(wp)


func _on_wall_moved(screen_pos: Vector2) -> void:
	var wp := camera.screen_to_world(screen_pos)
	if placement.placing and placement.btype == "road":
		placement.on_road_move(wp)
	else:
		placement.on_wall_move(wp)


func _on_wall_released(screen_pos: Vector2) -> void:
	var wp := camera.screen_to_world(screen_pos)
	if placement.placing and placement.btype == "road":
		placement.on_road_release(wp)
	else:
		placement.on_wall_release(wp)
	_sync_wall_drag_arm()


## Arms the camera's wall-drag routing while wall OR road placement is
## active (Jeremy 2026-10-11: player road tool reuses the routing).
func _sync_wall_drag_arm() -> void:
	camera.wall_drag_armed = placement.placing \
		and placement.btype in ["wall", "road"]


func _on_tapped_adventure(wp: Vector2) -> bool:
	var idx: int = Selection.pick(wp, selection.selectables,
		Selection.PICK_RADIUS)
	# pick() guarantees a valid index, but never trust it blindly.
	var picked: Node2D = selection.selectables[idx] \
		if idx >= 0 and idx < selection.selectables.size() else null
	var picked_uid := -1
	if picked is UnitNode:
		picked_uid = (picked as UnitNode).unit_id
	# Tapping the hero selects them.
	if picked_uid == adventure.hero_id:
		selection.selected = picked
		selection.queue_redraw()
		return true
	# Tapping with the hero selected issues orders.
	var hero_node: Node2D = _unit_nodes.get(adventure.hero_id)
	if selection.selected == hero_node and hero_node != null:
		var target: Dictionary = game.get_unit(picked_uid)
		if picked is UnitNode and not target.is_empty() \
				and target.get("alive", false) \
				and SimCombat.is_hostile(game.player_faction,
					String(target.get("faction", ""))):
			adventure.order_attack(picked_uid)
			# HTML drawHeroDestMarker port (move orders); improvement: attack
			# orders get a red ping on the target's position too.
			if _dest_marker != null:
				_dest_marker.push((picked as UnitNode).position, "attack")
		else:
			adventure.order_move(wp)
			if _dest_marker != null:
				_dest_marker.push(wp, "move")
		return true
	return false


## Paper map tap: jump the camera to the tapped world position.
func _on_paper_map_tapped(world_pos: Vector2) -> void:
	camera.position = world_pos
	if camera.has_method("clamp_now"):
		camera.clamp_now()


func _on_build_requested(btype: String) -> void:
	if btype.begins_with("zone_"):
		_on_zone_requested(btype)
		return
	# Building placement stops any active zone painting.
	zone_tool.cancel()
	placement.start_placement(btype)
	# AoE2 wall drag: arm the camera's press/move/release routing while
	# walls are being placed; everything else keeps the tap path.
	_sync_wall_drag_arm()
	# Zone suggestion: nudge the player toward the matching zone type.
	var want: String = SimZoning.suggested_zone_for(btype)
	if want != "":
		# iPhone-safe: no emoji glyphs in chrome (Godot web font lacks them,
		# shows tofu boxes — Jeremy 2026-10-03). Plain zone name instead.
		hud.flash_hint("%s: paint a %s zone (Zone tab), then drag on the map." % [
			SimBuildings.building_name(btype), SimZoning.zone_name(want)])


## HUD drawer actions (save/load/pause/settings/menu). The drawer buttons
## were built but never wired — Jeremy 2026-10-02 audit.
func _on_drawer_action(action: String) -> void:
	match action:
		"save":
			var data := SaveSystem.snapshot(game, adventure)
			if SaveSystem.save_slot(1, data):
				hud.flash_hint("Saved to slot 1.")
			else:
				hud.flash_hint("Save failed.")
		"load":
			var data := SaveSystem.load_slot(1)
			if data.is_empty():
				hud.flash_hint("Slot 1 is empty.")
			elif load_from_data(data):
				hud.flash_hint("Loaded slot 1.")
			else:
				hud.flash_hint("Load failed.")
		"pause":
			get_tree().paused = not get_tree().paused
			hud.set_paused(get_tree().paused)
			hud.flash_hint("Paused." if get_tree().paused else "Resumed.")
		"main_menu", "worlds":
			# Autosave, then hand control back to the main menu.
			if autosave != null:
				autosave.save_now("quit_to_menu")
			quit_to_menu_requested.emit("worlds" if action == "worlds" else "")
		"settings":
			hud.flash_hint("Settings live in the Main Menu (autosave ran).")
			if autosave != null:
				autosave.save_now("quit_to_menu")
		"disasters":
			_show_disaster_forecast()
		"resource_mgmt":
			_show_storage_caps()


## Drawer: show this month's disaster forecast (HTML disasterCalendar).
func _show_disaster_forecast() -> void:
	var fc: Dictionary = disasters.forecast
	if fc.is_empty():
		hud.flash_hint("No disasters forecast this month. Lucky.")
		return
	var days: Array = fc.keys()
	days.sort()
	var parts: Array[String] = []
	for d in days:
		if not (fc[d] is Dictionary):
			continue
		var e: Dictionary = fc[d]
		parts.append("Day %d: %s" % [int(d), String(e.get("label", "?"))])
	hud.flash_hint("Forecast — " + "; ".join(parts))


## Drawer: show storage caps vs stock (storage-cap port).
func _show_storage_caps() -> void:
	var pf: String = game.player_faction
	var parts: Array[String] = []
	for r: String in ["gold", "wood", "food", "oil", "seeds"]:
		parts.append("%s %d/%d" % [r, int(game.resources.get_amount(pf, r)),
			int(game.resources.get_cap(pf, r))])
	hud.flash_hint("Storage — " + ", ".join(parts))


## Zone tab requests: painting, dezone, overlay toggle, done.
func _on_zone_requested(ztype: String) -> void:
	placement.cancel()  # the building ghost goes away while zoning
	match ztype:
		"zone_toggle":
			zone_tool.toggle_overlay()
		"zone_done":
			zone_tool.cancel()
		"zone_dezone":
			zone_tool.start_paint(ztype, game.player_faction)
			hud.flash_hint("Dezone brush: drag over painted zones to erase them.")
		"zone_R", "zone_C", "zone_I", "zone_M":
			zone_tool.start_paint(ztype, game.player_faction)
			var letter: String = ztype.trim_prefix("zone_")
			hud.flash_hint("Paint a %s zone: drag to paint, tap for one lot. Done when finished." % [
				SimZoning.zone_name(letter)])


## Zones changed (painted/merged/dezoned): recompute building bonuses.
func _on_zone_changed() -> void:
	game.zoning.refresh_all()


## Jeremy 2026-10-07 (thermal bug): window focus drives the auto-pause
## policy — backgrounding the tab/app pauses the 60 Hz sim + render burn,
## foregrounding resumes only when WE auto-paused (a manual pause is never
## stolen). WorldAutoPause holds the rules; this just routes the events.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_auto_pause.on_focus_out(get_tree(), hud)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN:
		_auto_pause.on_focus_in(get_tree(), hud)


## Per-render-frame visual maintenance: adaptive quality (auto graphics),
## label visibility on zoom change, tree-sway zoom gate, grass refresh.
## None of this touches the sim.
func _process(delta: float) -> void:
	# Jeremy 2026-10-04: frame-time debug for 5-second cliff diagnosis.
	# Tracks FPS and counts spikes (>33ms frames).
	_tick_frame_debug(delta)
	_tick_adaptive_quality(delta)
	_tick_graphics_update(delta)
	_tick_surrender_flags()
	_tick_fee_coins(delta)  # spark-driver delivery-fee coin flight
	# Jeremy 2026-10-04: paper-map LOD — hide the detailed world at far zoom
	# (HTML inPaperMap parity). ~1,500 nodes → 1 paper map.
	_update_paper_lod()
	if camera != null:
		# Tree sway only when zoomed in enough (HTML camZoom > 0.55 gate).
		MapProp.sway_zoom_ok = camera.zoom.x > 0.55
		_refresh_grass()


func _physics_process(delta: float) -> void:
	# 60 Hz sim tick. Everything downstream is delta-based.
	game.tick(delta)
	if pathfinder != null:
		pathfinder.sync()  # nav grid rebuild (8s TTL / building changes)
	if road_overlay != null and worker_ai != null:
		road_overlay.sync_roads(worker_ai.roads)
		road_overlay.sync_workzones(worker_ai.road_work_zones())
	if adventure != null and adventure.active:
		adventure.tick(delta)
		_follow_hero(delta)
		_ensure_hero_node()
	_tick_ai_budgeted(delta)
	_tick_services(delta)
	game.zoning.tick(delta)  # commercial shop income
	game.zoning.tick_districts(delta, worker_ai)  # SimCity district growth
	combat.tick_towers(delta)
	combat.tick(delta)
	game.diplomacy.tick(delta)  # Milestone 8: daily drift, trade, AI rulers
	if game.get("disaster_aid") != null:
		game.disaster_aid.tick(delta)  # Jeremy 2026-10-11: aid helpers
	disasters.tick(delta)
	hydro.tick(delta)  # flood/hydrology sim
	if phone_sys != null:
		phone_sys.tick(delta)  # Jeremy 2026-10-04: realistic texting —
		# typing indicators, send delays, read receipts.
	if game.faction_leaders != null:
		game.faction_leaders.tick(delta)  # Jeremy 2026-10-04: faction
		# leader moods, directive expiry, proactive messages.
	# Port wave: calendar/economy/war/undead/hiring/housing ticks.
	if game.get("seasons") != null:
		game.seasons.tick(delta)
	if game.get("farming") != null:
		game.farming.tick(delta)
	if game.get("animals") != null:
		game.animals.tick(delta)
	if game.get("industry") != null:
		game.industry.tick(delta)
	# Jeremy 2026-10-04: staggered — medics retarget every 3rd frame (20Hz).
	# Was: two full unit scans every frame (28,800/s). Targeting decisions
	# don't need 60Hz; movement runs in the AI tick.
	_medic_frame += 1
	if _medic_frame >= 3:
		_medic_frame = 0
		combat.tick_medics(delta * 3.0)  # doctors rush downed units
	if army != null:
		army.tick(delta)  # daily: upkeep, collapse tick, AI war campaigns
	if game.garrison != null:
		game.garrison.tick(delta)  # 2 Hz: peacetime garrison stationing
	if game.siege != null:
		game.siege.tick(delta)  # 1 Hz: civilian siege response
	if game.trade_routes != null:
		game.trade_routes.tick(delta)  # trade wagons roll hall to hall
	if game.vehicles != null:
		game.vehicles.tick(delta)  # unified vehicle physics
	if game.dealership != null:
		game.dealership.tick(delta)  # P3: citizen vehicle shopping + parking
	if game.motor_pool != null:
		game.motor_pool.tick(delta)  # P5: depot fleet + baggage-train dispatch
	if game.npc_travel != null:
		game.npc_travel.tick(delta)  # P5: citizen rides (after physics)
	# Jeremy 2026-10-10 fire-truck dispatch: station trucks drive their
	# crews after the physics step (mount/drive/dismount/re-park loop).
	if disasters != null:
		disasters.tick_station_trucks(delta)
	if game.family != null:
		game.family.tick(delta)  # Family & Belonging: romance, births, souls
	if arty != null:
		arty.tick(delta)
	if undead != null:
		undead.tick(delta)
	if factions_sys != null:
		factions_sys.tick(delta)
	if hiring != null:
		hiring.tick(delta, WorkerAI.hour_of_day(game))
	# Jeremy 2026-10-04: real-time justice — guard dispatch, jail releases,
	# live courtroom trials.
	var _cl = _crime_life()
	if _cl != null:
		_cl.tick_global(delta)
	if housing != null:
		housing.tick(delta)
	if waterx != null:
		waterx.tick(delta)  # AI water-crossing: bridge straits at war
	if ai_director != null:
		ai_director.tick(delta)  # AI faction brain: build/train/muster/garrison
	if monasteries != null:
		monasteries.tick(delta)  # Seven Monasteries: capture, magic timers
	if crystals != null:
		crystals.tick(delta)  # Seven Dark Crystals: capture, corruption
	# Jeremy 2026-10-06 (Lane 3, Postworks): garrison leash + trip-cancel
	# at 2 s cadence (daily_tick covers supply/sieges/auras/AI).
	if game.command_posts != null:
		game.command_posts.tick(delta)
		var w2 := get_node_or_null("WeatherFX")
		if w2 != null and w2.has_method("current_weather"):
			crystals.storm_tick(
				String(w2.current_weather()) == "storm", delta)
	if towns_sys != null:
		towns_sys.tick(delta)  # town founding: completed halls -> town registry
	if nuclear != null:
		nuclear.tick(delta)  # nuke silo cooldowns, radiation zones, fallout
	if tutorial != null:
		tutorial.tick(delta)  # First Reign onboarding steps
	# "Overheard" (2026-10-07): drain accepted NPC speech lines to the HUD
	# subtitle ticker. Jeremy 2026-10-07: speech ALSO gets RS-style chat
	# bubbles above heads (spawned in _on_unit_said); tick them here so
	# they follow their speakers.
	if hud != null:
		var line: Dictionary = _chatter.tick(delta)
		if not line.is_empty():
			var lcolor: Color = line.get("color", ChatterTicker.SYSTEM_COLOR)
			hud.push_chatter(String(line.get("speaker", "")), lcolor,
				String(line.get("text", "")))
	_tick_chat_bubbles()
	if ferry != null:
		ferry.tick(delta)  # naval ferries: board, sail, unload
	_tick_border_walls(delta)
	_tick_starfort_bases(delta)
	# Sandbox observe mode: the director announces the last civ standing.
	if sandbox != null and sandbox.active:
		sandbox.tick(delta)
	_check_end_conditions()
	_tick_dying(delta)
	_sync_projectiles()
	_sync_fire_visuals(delta)
	_sync_animals(delta)
	_heal_accum += delta
	if _heal_accum >= CLINIC_HEAL_INTERVAL:
		_tick_clinic_heals(_heal_accum)
		_heal_accum = 0.0
	# Jeremy 2026-10-04: staggered culls — each processes 1/60th per frame
	# (full sweep every 1s). Was: all four at once every 1s (spike).
	_cleanup_depleted_props()
	_cull_offscreen_buildings()
	_cull_offscreen_props()
	# God structures: only 14, cheap — every 30 frames is plenty.
	_god_cull_frame += 1
	if _god_cull_frame >= 30:
		_god_cull_frame = 0
		_cull_god_structures()
	# Unit visual sync runs on the graphics tier's cadence (HTML
	# unitUpdateEvery parity — the SIM still ticks every physics frame).
	_sync_frame += 1
	if _sync_frame >= _unit_sync_every:
		_sync_frame = 0
		_sync_node_positions(delta)


## Reads the debug-overlay menu setting (main.gd sets the tree meta on the
## new-game path; the continue path lands here).
func _read_debug_setting() -> bool:
	return bool(GraphicsTiers.read_user_settings().get("debug_overlay", false))


## --- Graphics settings application ----------------------------------------
## HTML parity: the Graphics Preset / Ground Detail / Show Labels / Tree
## Sway settings actually change the visuals (previously saved but ignored).


## Resolve the tier from settings and apply every visual knob.
func _apply_graphics_settings() -> void:
	var us := GraphicsTiers.read_user_settings()
	_graphics_mode = String(us.get("graphics", "auto")).to_lower()
	if _graphics_mode == "":
		_graphics_mode = "auto"
	_active_tier = GraphicsTiers.resolve(_graphics_mode)
	_boot_tier = _active_tier
	_reset_aq_convergence()
	_ground_detail = String(us.get("ground_detail", "auto"))
	MapProp.sway_enabled = bool(us.get("tree_sway", true))
	_apply_visual_knobs(_active_tier)
	_apply_tree_budget()


## Current resolved tier (main.gd applies the weather particle budget).
func get_graphics_tier() -> String:
	return _active_tier


## Effective ground detail: 'auto' follows the active tier (HTML parity).
func _eff_ground_detail() -> String:
	return GraphicsTiers.eff_ground_detail(_ground_detail, _active_tier)


## Apply the tier's visual knobs (HTML applyGraphicsTier parity).
## Sim/AI/RNG untouched — purely visual.
func _apply_visual_knobs(tier: String) -> void:
	_active_tier = tier
	var knobs := GraphicsTiers.knobs(tier)
	var pm := float(knobs.get("particle_mul", 1.0))
	_unit_sync_every = maxi(1, int(knobs.get("unit_sync_every", 1)))
	if rivers != null:
		rivers.set_particle_mul(pm)
	_apply_weather_particle_mul(pm)
	_apply_tree_budget()
	_refresh_grass()


## WeatherFX is owned by main.gd (added after world._ready), so look it up.
func _apply_weather_particle_mul(pm: float) -> void:
	var w := get_node_or_null("WeatherFX")
	if w != null and w.has_method("set_particle_mul"):
		w.set_particle_mul(pm)


## Tree draw budget (HTML maxTreesDraw parity): first N tree props visible.
## Visual only — harvestable work sites are untouched.
func _apply_tree_budget() -> void:
	var knobs := GraphicsTiers.knobs(_active_tier)
	var frac := float(knobs.get("tree_draw_frac", 1.0))
	var budget := int(ceil(float(map_renderer.tree_props.size()) * frac))
	var i := 0
	for p: Variant in map_renderer.tree_props:
		if not is_instance_valid(p):
			continue
		(p as Node2D).visible = i < budget
		i += 1


## Jeremy 2026-10-05: unit label bubbles REMOVED (all bubbles removed at
## Jeremy's call). _refresh_unit_labels/_unit_label_visible deleted with them.


## Safe gov_role read: the "mind" value can be explicitly null in a
## record, and `u.get("mind", {}).get(...)` would crash on Nil.
func _gov_role_of(u: Dictionary) -> String:
	var mind_v: Variant = u.get("mind", {})
	if mind_v is Dictionary:
		return String(mind_v.get("gov_role", ""))
	return ""


func _find_unit_record(uid: int) -> Dictionary:
	for u: Dictionary in game.units:
		if int(u.get("id", -1)) == uid:
			return u
	return {}


## Grass refresh: detail tier + zoom + season gate (HTML parity).
## Only re-evaluates when something changed (zoom band, season, detail).
## Also applies the HTML treeSeasonTint to all trees on season change
## (Jeremy 2026-10-03: seasons show in the sim graphics).
func _refresh_grass() -> void:
	if _grass == null or not is_instance_valid(_grass):
		return
	var season_name := "Summer"
	var seas: Variant = game.get("seasons")
	if seas != null and seas.has_method("season"):
		season_name = String(seas.season())
	var winter := season_name == "Winter"
	var zoom := 0.9
	if camera != null:
		zoom = camera.zoom.x
	var detail := _eff_ground_detail()
	var key := "%s|%d|%s" % [detail, int(zoom * 10.0), season_name]
	if key == _grass_key:
		return
	var season_changed := _grass_key == "" \
		or _grass_key.get_slice("|", 2) != season_name
	_grass_key = key
	_grass.refresh(camera, detail, winter)
	if season_changed:
		_apply_tree_season_tint(season_name)


## Jeremy 2026-10-03 graphics update: subtle screen vignette on a CanvasLayer
## above the weather tint (-5) and below the HUD — only the world is
## vignetted, never the UI.
func _build_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.name = "VignetteLayer"
	layer.layer = -4
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/vignette.gdshader") as Shader
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)


## Per-frame graphics-update pump for the lighting rig + ambient life.
## Cheap work runs every frame (phase lerps); pooled light assignment and
## the water uniform refresh at ~2 Hz.
func _tick_graphics_update(delta: float) -> void:
	if game == null:
		return
	var phase := fmod(game.game_time, Config.DAY_LENGTH_SECONDS) \
		/ Config.DAY_LENGTH_SECONDS
	if lighting != null and is_instance_valid(lighting):
		lighting.set_phase(phase, delta)
	if ambient != null and is_instance_valid(ambient):
		ambient.set_phase(phase)
	_gfx_accum += delta
	if _gfx_accum < 0.5:
		return
	_gfx_accum = 0.0
	_refresh_graphics_slow(phase)
	# Jeremy 2026-10-05: tree chop/fell + wood-pickup visuals ride the
	# 2 Hz graphics tick (snappy enough for chop feedback).
	_sync_tree_fx()


func _refresh_graphics_slow(phase: float) -> void:
	# Hand the day/night darkening to the lighting rig exactly once (the
	# WeatherFX node is owned by main.gd and may appear after world._ready).
	if not _weather_lighting_mode_set:
		var w := get_node_or_null("WeatherFX")
		if w != null and w.has_method("set_lighting_mode"):
			w.set_lighting_mode(true)
			_weather_lighting_mode_set = true
	var nf := LightingRig.night_factor(phase)
	# Water moon-glint follows the same clock as the lights.
	if _terrain_sprite != null and is_instance_valid(_terrain_sprite):
		var mat := _terrain_sprite.material as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("night_factor", nf)
	# Fire lights + embers track the live fires (view-culled by the rig).
	var fire_pos := PackedVector2Array()
	if fx != null:
		fire_pos = fx.fire_positions()
	if lighting != null and is_instance_valid(lighting):
		lighting.set_fire_positions(fire_pos)
		lighting.set_window_positions(_building_positions_in_view(24))
	if ambient != null and is_instance_valid(ambient):
		ambient.set_fire_positions(fire_pos)
		var w2 := get_node_or_null("WeatherFX")
		if w2 != null and w2.has_method("current_weather"):
			ambient.set_weather(String(w2.current_weather()))
		var seas: Variant = game.get("seasons")
		if seas != null and seas.has_method("season"):
			ambient.set_season(String(seas.season()))


## Jeremy 2026-10-04: world-space point in the camera view (with margin)?
## Used to cull off-screen unit animation — _process is the per-frame
## animator cost, and most of the 240 units are off-screen when zoomed in.
func _pos_in_view(p: Vector2, margin: float = 120.0) -> bool:
	if camera == null:
		return true
	var vs := get_viewport_rect().size
	var center := camera.get_screen_center_position()
	var half := vs / maxf(camera.zoom.x, 0.01) * 0.5 + Vector2(margin, margin)
	return absf(p.x - center.x) <= half.x and absf(p.y - center.y) <= half.y


## Jeremy 2026-10-04: hide off-screen buildings from the render pipeline
## (draw-call reduction for 60fps). Runs once per second — buildings don't
## move, only the camera does. Burning buildings keep their fire visuals;
## visibility toggles the whole node including children.
## Jeremy 2026-10-04: staggered — 1/60th of building nodes per frame
## (full sweep every 1s). Was: all buildings at once every 1s.
func _cull_offscreen_buildings() -> void:
	if camera == null:
		return
	var vs := get_viewport_rect().size
	var center := camera.get_screen_center_position()
	# Larger margin for buildings (they're big sprites).
	var half := vs / maxf(camera.zoom.x, 0.01) * 0.5 + Vector2(240, 240)
	var keys: Array = _building_nodes.keys()
	var n: int = keys.size()
	if n == 0:
		return
	var slice: int = maxi(1, n / 60)
	var idx: int = _cull_cursor % n
	for i: int in range(mini(slice, n)):
		var key = keys[(idx + i) % n]
		var bn: Node2D = _building_nodes[key]
		if bn == null or not is_instance_valid(bn):
			continue
		var p := bn.position
		var in_view := absf(p.x - center.x) <= half.x \
			and absf(p.y - center.y) <= half.y
		if bn.visible != in_view:
			bn.visible = in_view
	_cull_cursor = (idx + mini(slice, n)) % n


## Jeremy 2026-10-04: hide off-screen props (trees, resource nodes) from
## the render pipeline (draw-call reduction for 60fps). Runs once per
## second alongside building culling — props are static.
## Jeremy 2026-10-04: staggered — 1/60th of props per frame (full sweep
## every 1s). Was: all props (1000s) at once every 1s. Uses its own cursor
## so building/prop culls don't march in lockstep.
func _cull_offscreen_props() -> void:
	if camera == null or props == null:
		return
	var vs := get_viewport_rect().size
	var center := camera.get_screen_center_position()
	var half := vs / maxf(camera.zoom.x, 0.01) * 0.5 + Vector2(160, 160)
	var children: Array = props.get_children()
	var n: int = children.size()
	if n == 0:
		return
	var slice: int = maxi(1, n / 60)
	var idx: int = _prop_cull_cursor % n
	for i: int in range(mini(slice, n)):
		var child: Node = children[(idx + i) % n]
		var p2d := child as Node2D
		if p2d == null:
			continue
		var p := p2d.position
		var in_view := absf(p.x - center.x) <= half.x \
			and absf(p.y - center.y) <= half.y
		if p2d.visible != in_view:
			p2d.visible = in_view
			# Jeremy 2026-10-04: kill _process for off-screen props too.
			# 1,500 trees x 60fps of _process calls (even when the work
			# inside is skipped) was 90,000 wasted calls/sec.
			p2d.set_process(in_view)
	_prop_cull_cursor = (idx + mini(slice, n)) % n


## Jeremy 2026-10-04: hide off-screen god structures (7 monasteries + 7
## dark crystals) from the render pipeline (60fps). Runs once per second
## alongside building/prop culling — they're static landmarks. Uses
## set_culled() so the 4 Hz idle-animation redraw also pauses off-screen.
## Generous margin: these are huge (~460 px wide at 2.2x scale).
func _cull_god_structures() -> void:
	if camera == null:
		return
	for mid in _monastery_nodes.keys():
		var mn: MonasteryNode = _monastery_nodes[mid] as MonasteryNode
		if mn == null or not is_instance_valid(mn):
			continue
		mn.set_culled(not _pos_in_view(mn.position, 320.0))
	for cid in _crystal_nodes.keys():
		var cn: CrystalNode = _crystal_nodes[cid] as CrystalNode
		if cn == null or not is_instance_valid(cn):
			continue
		cn.set_culled(not _pos_in_view(cn.position, 320.0))


## Building positions inside the camera view (world space), capped — feeds
## the lighting rig's pooled window lights.
func _building_positions_in_view(cap: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if camera == null:
		return out
	var vs := get_viewport_rect().size
	var center := camera.get_screen_center_position()
	var half := vs / maxf(camera.zoom.x, 0.01) * 0.5 + Vector2(160, 160)
	for key in _building_nodes:
		var bn: Node2D = _building_nodes[key]
		if bn == null or not is_instance_valid(bn):
			continue
		var p := bn.position
		if absf(p.x - center.x) <= half.x \
				and absf(p.y - center.y) <= half.y:
			out.append(p)
			if out.size() >= cap:
				break
	return out


## Pushes the current season's tree tint to every tree prop.
func _apply_tree_season_tint(season_name: String) -> void:
	var tree: SceneTree = get_tree()
	if tree == null:
		return
	for n in tree.get_nodes_in_group("cg_trees"):
		if n != null and is_instance_valid(n) and n.has_method("apply_season_tint"):
			(n as MapProp).apply_season_tint(season_name)


## Adaptive quality (HTML adaptiveQualityTick parity): auto mode only.
## Sustained slow frames step the tier down; sustained smooth frames step it
## back up, never past the boot tier. Purely visual.
## Jeremy 2026-10-04: frame-time debug overlay for 5-second cliff diagnosis.
## Tracks FPS over 0.5s windows, counts spikes (>33ms), updates HUD label.
func _tick_frame_debug(delta: float) -> void:
	var ms := delta * 1000.0
	_fd_accum += ms
	_fd_frames += 1
	if ms > 33.0:
		_fd_spikes += 1
	_fd_update_t += delta
	if _fd_update_t >= 0.5 and _fd_frames > 0:
		var avg_ms := _fd_accum / _fd_frames
		var fps := 1000.0 / maxf(avg_ms, 0.01)
		# Jeremy 2026-10-04: heap readout for GC-spike diagnosis (18s cycle).
		# MEMORY_STATIC reads 0 on web exports (unimplemented there) —
		# show "n/a" instead of a misleading 0MB.
		var mem_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
		var mem_text := "mem:n/a" if mem_mb <= 0.0 else "mem:%.0fMB" % mem_mb
		if hud != null and hud._fps_label != null and is_instance_valid(hud._fps_label):
			hud._fps_label.text = "%d FPS (%.1fms) spikes:%d t:%s %s" % [int(fps), avg_ms, _fd_spikes, _active_tier, mem_text]
		_fd_accum = 0.0
		_fd_frames = 0
		_fd_update_t = 0.0


## Reset AQ convergence state (settings reload / world setup): the upgrade
## ceiling returns to the boot tier and any failed-upgrade memory clears.
func _reset_aq_convergence() -> void:
	_aq_ceil_idx = GraphicsTiers.TIERS.find(_boot_tier)
	if _aq_ceil_idx < 0:
		_aq_ceil_idx = 2
	_aq_time = 0.0
	_aq_upgraded_at = -1.0
	_aq_ema = 0.0
	_aq_cool = 0.0
	_aq_smooth = 0


func _tick_adaptive_quality(delta: float) -> void:
	if _graphics_mode != "auto":
		return
	_aq_time += delta
	var ms := delta * 1000.0
	_aq_ema = ms if _aq_ema <= 0.0 else lerpf(_aq_ema, ms, 0.05)
	_aq_cool = maxf(0.0, _aq_cool - delta)
	if _aq_ema > AQ_OVER_MS:
		_aq_smooth = 0
		if _aq_cool <= 0.0:
			_step_aq_tier(1)  # toward "low"
	elif _aq_ema < AQ_UNDER_MS:
		_aq_smooth += 1
		if _aq_smooth >= AQ_SMOOTH_FRAMES and _aq_cool <= 0.0:
			_step_aq_tier(-1)  # toward "ultra", capped at boot tier
			_aq_smooth = 0
	else:
		_aq_smooth = 0


## Step the adaptive tier. dir > 0 degrades, dir < 0 upgrades (TIERS is
## ordered ultra -> low). Upgrades never pass _aq_ceil_idx, which starts at
## the boot tier and ratchets down whenever an upgrade fails (degrade inside
## AQ_RATCHET_WINDOW of the upgrade) — so AQ converges on the highest tier
## the device sustains instead of ping-ponging forever.
func _step_aq_tier(dir: int) -> void:
	var tiers := GraphicsTiers.TIERS
	var cur := tiers.find(_active_tier)
	if cur < 0:
		cur = 2
	var next := clampi(cur + dir, _aq_ceil_idx, tiers.size() - 1)
	if next == cur:
		return
	if dir > 0:
		# Degrade. If this follows a recent upgrade, the tier we are leaving
		# (cur) just proved unsustainable — pin the ceiling below it.
		if _aq_upgraded_at >= 0.0 \
				and _aq_time - _aq_upgraded_at <= AQ_RATCHET_WINDOW:
			_aq_ceil_idx = maxi(_aq_ceil_idx, cur + 1)
		_aq_upgraded_at = -1.0
	else:
		_aq_upgraded_at = _aq_time
	_aq_cool = AQ_COOLDOWN
	_aq_smooth = 0
	_apply_visual_knobs(tiers[next])


## Border-wall AI: throttled to ~1 Hz, per faction. Unanswered player
## prompts surface through the HUD hint (border_walls.pending).
func _tick_border_walls(delta: float) -> void:
	if border_walls == null:
		return
	_bw_accum += delta
	if _bw_accum < 1.0:
		return
	_bw_accum = 0.0
	for f: String in game.active_factions:
		border_walls.tick(f, f == game.player_faction, buildings_sys,
			_wall_drag)
	var pending: Array = border_walls.get("pending") as Array
	if pending != null and not pending.is_empty() and phone_sys != null:
		if not (pending[0] is Dictionary):
			return
		var p: Dictionary = pending[0]
		# Jeremy 2026-10-04: one ask per region via hearsay — the prompt is
		# sent once and the player answers yes/no in conversation (which
		# emits wall_answer on the bus). Skip prompts we've already asked
		# about so it never spams.
		if bool(p.get("notified", false)):
			return
		var region: String = String(p.get("region_name", "Border"))
		# Jeremy 2026-10-04: cost is a Dictionary {"gold": X, ...}, extract gold.
		# (Variant: pending records may carry a bare int cost.)
		var cost_raw: Variant = p.get("cost", p.get("est_cost", {}))
		var cost: int = 0
		if cost_raw is Dictionary:
			cost = int((cost_raw as Dictionary).get("gold", 0))
		elif cost_raw is int:
			cost = int(cost_raw)
		var fname: String = String(Config.FACTIONS.get(game.player_faction, {}).get("name", game.player_faction))
		var msg: String = "%s (%s territory): raise border walls? (~%d gold) — just reply YES to raise them or NO to skip." % [region, fname, cost]
		# The advisor asks once; the player's hearsay reply decides.
		var advisor_id: int = _find_government_contact()
		if advisor_id > 0:
			phone_sys.ask_wall_question(advisor_id, region, msg)
		# Mark as asked so we never send it again.
		p["notified"] = true


## Jeremy 2026-10-04: the player answered a wall-raise prompt via hearsay
## (yes/no reply to the advisor). Commit or skip the walls for the region.
func _on_wall_answer(region_name: String, raise: bool) -> void:
	if border_walls == null:
		return
	border_walls.answer(region_name, raise, buildings_sys, _wall_drag)


## Jeremy 2026-09-26: one star-fort military base per AI town (never for the
## player's own race — advisers suggest, never auto-spend).
func _tick_starfort_bases(delta: float) -> void:
	if starfort_bases == null:
		return
	_sfb_accum += delta
	if _sfb_accum < 1.0:
		return
	_sfb_accum = 0.0
	for f: String in game.active_factions:
		starfort_bases.tick(f, f == game.player_faction, buildings_sys,
			_wall_drag)


## Finds the military advisor to send defense-related phone messages from.
## (Jeremy 2026-10-03: border wall prompt should come from a specific
## cabinet member — the military advisor makes sense.)
## Returns unit ID, or 0 if none found.
func _find_government_contact() -> int:
	if game == null:
		return 0
	# Look for military leadership in the player's faction (commander, watch captain, military advisor)
	for u in game.units:
		if u is Dictionary:
			var fid: String = String(u.get("faction", ""))
			if fid != game.player_faction:
				continue
		var job: String = String(u.get("job", "")).to_lower()
		var gov_role: String = _gov_role_of(u).to_lower()
		# Prefer military roles
		if "commander" in job or "commander" in gov_role:
			return int(u.get("id", 0))
		if "watch" in job and "captain" in job:
			return int(u.get("id", 0))
		if "watch_captain" in gov_role:
			return int(u.get("id", 0))
	# Fall back to any military advisor
	for u in game.units:
		if u is Dictionary:
			var fid2: String = String(u.get("faction", ""))
			if fid2 != game.player_faction:
				continue
		var job2: String = String(u.get("job", "")).to_lower()
		if ("advisor" in job2 or "counsel" in job2) and ("military" in job2 or "war" in job2 or "defense" in job2):
			return int(u.get("id", 0))
	# Last resort: any advisor
	for u in game.units:
		if u is Dictionary:
			var fid3: String = String(u.get("faction", ""))
			var job3: String = String(u.get("job", "")).to_lower()
			if fid3 == game.player_faction and ("advisor" in job3 or "counsel" in job3):
				return int(u.get("id", 0))
	return 0


## Victory/defeat end conditions (HTML endGame parity).
## Sandbox director fired: one civilization remains. HTML parity —
## "SIMULATION COMPLETE — <Name> dominated the continent.
## (Sandbox — you were an observer.)" The standard victory/defeat path
## already skips observer mode (player_faction == "").
func _on_sandbox_complete(winner_name: String) -> void:
	if _end_announced or end_screen == null:
		return
	_end_announced = true
	var fname: String = String(Config.FACTIONS.get(winner_name, {}).get("name",
		winner_name))
	end_screen.show_end("sandbox", "",
		"%s dominated the continent.\n(Sandbox — you were an observer.)" % fname)


func _check_end_conditions() -> void:
	if _end_announced or end_screen == null:
		return
	var halls: Dictionary = {}  # faction -> hall count
	for b: Dictionary in game.buildings:
		if String(b.get("type", "")) in ["town_hall", "hall"] \
				and bool(b.get("alive", true)) \
				and bool(b.get("complete", false)):
			var f: String = String(b.get("faction", ""))
			halls[f] = int(halls.get(f, 0)) + 1
	var pf: String = game.player_faction
	if pf != "" and int(halls.get(pf, 0)) == 0 and not game.units.is_empty():
		_end_announced = true
		end_screen.show_end("defeat")
		return
	# Victory: every other active faction has no halls (after first contact).
	var others_alive := false
	for f: String in game.active_factions:
		if f != pf and int(halls.get(f, 0)) > 0:
			others_alive = true
			break
	if pf != "" and not others_alive and int(halls.get(pf, 0)) > 0 \
			and game.day_number > 1:
		_end_announced = true
		end_screen.show_end("victory")


## Death animations finish, then the node goes away (the sim record
## lingers as a corpse for CORPSE_LINGER; the visual doesn't need to).
func _tick_dying(delta: float) -> void:
	var done: Array[int] = []
	for uid: int in _dying.keys():
		_dying[uid] = float(_dying[uid]) + delta
		if float(_dying[uid]) >= 1.0:
			done.append(uid)
	for uid: int in done:
		_free_unit_node(uid)


## Copy sim projectile positions to their visual nodes.
func _sync_projectiles() -> void:
	for p: Dictionary in combat.projectiles:
		var pn: ProjectileNode = _proj_nodes.get(int(p.get("id", 0))) \
			as ProjectileNode
		if pn != null and is_instance_valid(pn):
			pn.position = p.get("position", Vector2.ZERO)


## Keep fire visuals alive + scaled by intensity.
func _sync_fire_visuals(delta: float) -> void:
	for f: Dictionary in disasters.fires:
		fx.update_fire(int(f.get("id", 0)),
			float(f.get("intensity", 0.0)), delta)


## Sync animal nodes: wild animals + farm livestock. Creates nodes for new
## animals, moves existing ones, removes dead ones.
func _sync_animals(vis_delta: float = -1.0) -> void:
	if game.get("animals") == null:
		return
	var seen := {}
	# Wild animals.
	for an in game.animals.wild:
		_sync_one_animal(an, true, seen)
	# Farm livestock on plots.
	if game.get("farming") != null:
		for p in game.farming.plots:
			if not (p is Dictionary):
				continue
			for an in p.get("animals", []):
				if an is Dictionary:
					_sync_one_animal(an, false, seen)
	# Remove nodes for dead/gone animals.
	for aid in _animal_nodes.keys():
		if not seen.has(aid):
			var nd: AnimalNode = _animal_nodes[aid] as AnimalNode
			if nd != null and is_instance_valid(nd):
				nd.queue_free()
			_animal_nodes.erase(aid)
	# Perf R13 (2026-10-05): building fire visuals at 10 Hz. Fire state
	# ignites/extinguishes on slow sim ticks, so the per-frame rescan of
	# all buildings + wind + per-fire fx param updates bought nothing.
	# Ignitions are still picked up within 100 ms.
	if vis_delta < 0.0:
		vis_delta = get_physics_process_delta_time()
	_fire_visual_accum += vis_delta
	if _fire_visual_accum >= 0.1:
		_fire_visual_accum = 0.0
		_sync_building_fire_visuals()


func _sync_one_animal(an: Dictionary, is_wild: bool, seen: Dictionary) -> void:
	if not bool(an.get("alive", false)):
		return
	var aid: int = int(an.get("id", -1))
	if aid < 0:
		return
	seen[aid] = true
	var nd: AnimalNode = _animal_nodes.get(aid) as AnimalNode
	if nd == null or not is_instance_valid(nd):
		nd = AnimalNode.new()
		nd.setup(aid, String(an.get("type", "boar")),
			an.get("position", Vector2.ZERO), is_wild)
		units_root.add_child(nd)
		_animal_nodes[aid] = nd
	else:
		nd.sync_to(an.get("position", Vector2.ZERO), an)
		# Jeremy 2026-10-04: cull off-screen animals from the render
		# pipeline (draw-call reduction). Position still syncs above.
		var in_view: bool = _pos_in_view(an.get("position", Vector2.ZERO))
		if nd.visible != in_view:
			nd.visible = in_view
			nd.set_process(in_view)


## Keep burning-building fire visuals in sync with the sim (HTML c59
## parity): any live building with on_fire == true gets a roof fire sprite +
## faction-tinted smoke and embers; cleared when the building stops burning
## or is destroyed. Damage scales the smoke (HTML's bs formula).
func _sync_building_fire_visuals() -> void:
	if game == null:
		return
	var wind := Vector2.ZERO
	var seas: Variant = game.get("seasons")
	if seas != null:
		# SimSeasons always carries wind_dir/wind_speed (verified);
		# direct access — Object.get() takes no default argument.
		wind = Vector2.RIGHT.rotated(float(seas.wind_dir)) \
			* float(seas.wind_speed)
	var burning := {}
	for b: Dictionary in game.buildings:
		if not bool(b.get("alive", true)):
			continue
		if not bool(b.get("on_fire", false)):
			continue
		var bid := int(b.get("id", 0))
		burning[bid] = true
		var hp: float = float(b.get("hp", 1.0))
		var max_hp: float = maxf(1.0, float(b.get("max_hp", b.get("maxHp", 1.0))))
		# HTML: bs = max(0.8, 1 - hp/maxHp + 0.8) — damaged buildings smoke harder.
		var bs: float = maxf(0.8, 1.0 - hp / max_hp + 0.8)
		if not fx.has_building_fire(bid):
			fx.spawn_building_fire(bid, b.get("position", Vector2.ZERO),
				String(b.get("faction", "human")), bs)
		fx.update_building_fire(bid, bs, wind)
	for bid in fx.building_fire_ids():
		if not burning.has(bid):
			fx.clear_building_fire(bid)


## Round-robin worker AI: at most AI_UNITS_PER_TICK records per physics tick.
## Delta is scaled by the slice count so walk speed stays exact.
func _tick_ai_budgeted(delta: float) -> void:
	var units: Array = game.units
	var n: int = units.size()
	if n == 0:
		return
	var slices: int = mini(AI_MAX_SLICES, int(ceil(n / float(AI_UNITS_PER_TICK))))
	var budget: int = mini(AI_UNITS_PER_TICK, n)
	var scaled_delta: float = delta * slices
	var idx: int = _ai_cursor % n
	for i: int in range(budget):
		# The sim can purge units mid-slice (deaths); re-read the live
		# size so a shrunken array never goes out of bounds.
		var live_n: int = units.size()
		if live_n == 0:
			break
		var u: Dictionary = units[(idx + i) % live_n]
		_route_ai(u, scaled_delta)
	_ai_cursor = (idx + budget) % maxi(1, units.size())


## Routes one unit record to the right brain. The MIND runs first: a unit
## satisfying a critical urge or fleeing in terror consumes its AI slice
## and skips job/combat AI that tick. Military -> combat, monsters ->
## disaster sim (already ticked globally; skip here), firefighters -> fire
## response, everyone else -> WorkerAI.
func _route_ai(u: Dictionary, delta: float) -> void:
	# Adventure mode: the hero and quest NPCs skip standard AI — their
	# brains run in SimAdventure.tick() (every frame, exactly once).
	if adventure != null and adventure.active \
			and (adventure.is_hero(u) or adventure.is_quest_npc(u)):
		return
	# Jeremy 2026-10-04: the real-time crime layer owns the AI slice of any
	# unit inside the justice pipeline (stalking, fleeing, hunted, jailed,
	# on trial, guard pursuit/arrest) — and plans new crimes for idle crooks.
	var cl = _crime_life()
	if cl != null and cl.tick_unit(u, delta):
		return
	if mind.tick_unit(u, delta):
		return  # urge override or fleeing — brain is busy
	var job: String = String(u.get("job", ""))
	if JobDefs.is_military(job):
		combat.tick_unit(u, delta)
		return
	if String(u.get("faction", "")) == "monster":
		return  # DisasterSim.tick owns monster records
	if job == "firefighter":
		disasters.tick_firefighter(u, delta)
		return
	# Work shifts (HTML workBell57 parity): off-shift civilians live their
	# lives (WorkerAI.tick_off_shift: rest at home, socialize, see friends)
	# instead of freezing in place. Firefighters are 24/7 (handled above);
	# military keeps its own hours in combat.
	if not WorkerAI.is_on_shift(job, WorkerAI.hour_of_day(game)):
		u["work_state"] = "off_shift"
		worker_ai.tick_off_shift(u, delta)
		return
	worker_ai.tick_unit(u, buildings_sys, delta)


## Real-time crime behavior layer (SimCrimeLife, owned by SimCrime).
func _crime_life():
	if game.court_sys != null and game.court_sys.crime != null:
		return game.court_sys.crime.life
	return null


## Service staffing ticks (cheap: per-building 10 s throttle gate).
## Jeremy 2026-10-04: staggered — processes 1/30th of buildings per frame
## (full sweep every 0.5s). Was: all buildings every frame (60Hz).
## tick_service has a 10s per-building throttle gate, so 2Hz sweep is safe.
func _tick_services(delta: float) -> void:
	var buildings: Array = game.buildings
	var n: int = buildings.size()
	if n == 0:
		return
	var slice: int = maxi(1, n / 30)
	var scaled_delta: float = delta * 30.0
	var idx: int = _service_cursor % n
	for i: int in range(mini(slice, n)):
		# tick_service can raze/replace buildings mid-slice; re-read the
		# live size so a shrunken array never goes out of bounds.
		var live_n: int = buildings.size()
		if live_n == 0:
			break
		var b: Dictionary = buildings[(idx + i) % live_n]
		var bt: String = String(b.get("type", ""))
		# All service buildings auto-staff (clinic, fire station,
		# guild hall -> guild master, guard house -> guards).
		if SimBuildings.SERVICE_BUILDINGS.has(bt):
			buildings_sys.tick_service(b, scaled_delta)
	_service_cursor = (idx + mini(slice, n)) % maxi(1, buildings.size())


## Clinic aura heals at 10 Hz.
## Jeremy 2026-10-04: staggered — 1/10th of buildings per 10Hz tick (full
## sweep every 1s). Clinics are rare; was: all buildings every 0.1s.
var _clinic_cursor := 0
func _tick_clinic_heals(delta: float) -> void:
	var buildings: Array = game.buildings
	var n: int = buildings.size()
	if n == 0:
		return
	var slice: int = maxi(1, n / 10)
	var scaled_delta: float = delta * 10.0
	var idx: int = _clinic_cursor % n
	for i: int in range(mini(slice, n)):
		# Clinic heals can destroy buildings mid-slice (burn collapse);
		# re-read the live size so a shrunken array never goes out of bounds.
		var live_n: int = buildings.size()
		if live_n == 0:
			break
		var b: Dictionary = buildings[(idx + i) % live_n]
		if String(b.get("type", "")) == "clinic":
			buildings_sys.tick_clinic_heal(b, 6.0, scaled_delta)
	_clinic_cursor = (idx + mini(slice, n)) % maxi(1, buildings.size())


## Jeremy 2026-10-04: staggered — 1/60th of work sites per frame (full
## sweep every 1s). Was: all sites x all props at once every 1s.
func _cleanup_depleted_props() -> void:
	var sites: Array = game.work_sites
	var n: int = sites.size()
	if n == 0:
		return
	var slice: int = maxi(1, n / 60)
	var idx: int = _prop_cursor % n
	var cleared: Array[int] = []
	for i: int in range(mini(slice, n)):
		var s: Dictionary = sites[(idx + i) % n]
		if String(s.get("kind", "")) != "tree":
			continue
		if float(s.get("amount", 1.0)) > 0.0:
			continue
		if bool(s.get("_prop_cleared", false)):
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		for c in props.get_children():
			var mp: MapProp = c as MapProp
			if mp != null and mp.kind == "tree" \
					and mp.position.distance_to(sp) < 40.0:
				mp.queue_free()
				break
		s["_prop_cleared"] = true
		cleared.append(int(s.get("id", 0)))
	_prop_cursor = (idx + mini(slice, n)) % n


## Copy sim positions to nodes (units move in the sim; nodes follow).
## Dead units are skipped — their node plays the death clip via unit_killed,
## then the world frees it after a second.
##
## Cliffs: units ride their height level's visual lift (HTML cgUnitLiftTick83
## — snap on first sight, then ease toward the target so climbing reads as
## a smooth ascent, never a teleport).
func _sync_node_positions(delta: float) -> void:
	# Jeremy 2026-10-04: refresh the site kind cache for work animations.
	var n_sites: int = game.work_sites.size()
	if n_sites != _site_kinds_n:
		_site_kinds_n = n_sites
		_site_kinds.clear()
		for s: Dictionary in game.work_sites:
			_site_kinds[int(s.get("id", -1))] = String(s.get("kind", ""))
	# Perf R13: hoisted view bounds for the per-unit cull check below.
	# (camera == null) matches _pos_in_view()'s "always in view" fallback.
	var view_c := Vector2.ZERO
	var view_half := Vector2(1.0e9, 1.0e9)
	if camera != null:
		view_c = camera.get_screen_center_position()
		view_half = get_viewport_rect().size / maxf(camera.zoom.x, 0.01) * 0.5 \
			+ Vector2(120.0, 120.0)
	# Graphics-hourly 2026-10-11: units aboard a vehicle hide their world
	# sprite (they're drawn seated in the vehicle by VehicleLayer instead) —
	# no more full-size sprites glued to the truck. Built once per sync.
	var aboard := {}
	if game.vehicles != null:
		aboard = (game.vehicles as SimVehicles).aboard_set()
	for u: Dictionary in game.units:
		if not u.get("alive", false):
			continue
		var uid: int = int(u.get("id", 0))
		var un: UnitNode = _unit_nodes.get(uid) as UnitNode
		if un != null and is_instance_valid(un):
			var sim_pos: Vector2 = u.get("position", Vector2.ZERO)
			# Perf R13 (2026-10-05): stationary units keep their converged
			# lift — skip the Cliffs.lift_at tile lookup (measured 1.3 us x
			# 240 units = ~0.3 ms per sync). The lerp already converged for
			# anything standing still; the freeze is visual-only.
			var lift: float
			if sim_pos == _unit_sync_pos.get(uid, Vector2(1.0e18, 0.0)):
				lift = float(_unit_lift.get(uid, 0.0))
			else:
				_unit_sync_pos[uid] = sim_pos
				var target_lift: float = Cliffs.lift_at(map_data, sim_pos)
				var cur: float = float(_unit_lift.get(uid, -1.0))
				if cur < 0.0:
					cur = target_lift  # snap on first sight
				else:
					cur = lerpf(cur, target_lift, minf(1.0, delta * 6.0))
				_unit_lift[uid] = cur
				lift = cur
			un.position = sim_pos + Vector2(0.0, -lift)
			# Perf R13: view bounds hoisted out of the per-unit
			# _pos_in_view() — 240 camera.get_screen_center_position() +
			# get_viewport_rect() calls per sync, now one pair. The
			# comparison math (with the 120 px margin) is identical.
			un.set_culled(not (absf(sim_pos.x - view_c.x) <= view_half.x \
				and absf(sim_pos.y - view_c.y) <= view_half.y))
			# Jeremy 2026-10-08 (wake deep-systems): units inside buildings
			# (inside_building_id > 0 — siege hiding, sleeping, etc.) are
			# hidden on the main map. The interior_view shows them when the
			# building is opened. Fixes the silent failure where
			# interior_entered was emitted but nothing hid the sprite.
			# Graphics-hourly 2026-10-11: units aboard a vehicle are hidden
			# too — VehicleLayer draws them seated in the vehicle instead.
			un.set_inside(int(u.get("inside_building_id", 0)) > 0 \
				or aboard.has(uid))
			# Jeremy 2026-10-04: world-space HP bar (HTML C70fix2 parity —
			# bar shows only while injured). Cheap early-out inside set_hp.
			un.set_hp(float(u.get("hp", 100.0)), float(u.get("max_hp", 100.0)))
			var job: String = String(u.get("job", ""))
			if un.job != job:
				un.set_job(job)
			# Jeremy 2026-10-04: gathering kind drives the mine/chop anim +
			# tool overlay (visuals only — sim work_state is untouched).
			# Jeremy 2026-10-05: pass the real equipped tool so the overlay
			# shows what the unit owns (HTML toolImg54For parity).
			var ws := String(u.get("work_state", "idle"))
			var gk := ""
			if ws == "gathering":
				gk = String(_site_kinds.get(int(u.get("work_site", -1)), ""))
			# Jeremy 2026-10-06: pass the sim's work_pose channel (sit/use/
			# work/attack/rest) — the world layer used to drop it, so desk
			# workers stood at their desks and arrived resters walked in place.
			# Jeremy 2026-10-06: haulers walk empty-handed unless the world
			# passes the carried resource kind — the shoulder-load bundle
			# (animation gate #3). Dominant carrying kind for to_dropoff only.
			var ck := ""
			if ws == "to_dropoff":
				var c: Dictionary = u.get("carrying", {})
				var best_v := 0.0
				for k in c.keys():
					var v := float(c.get(k, 0.0))
					if v > best_v:
						best_v = v
						ck = String(k)
			un.set_work_state(ws, gk, String(u.get("equipped_tool", "")),
				String(u.get("work_pose", "")), ck)
			# Milestone 7: fire truck visual follows the on_truck flag.
			# Suppressed while the firefighter rides a REAL truck record
			# (Jeremy 2026-10-10 dispatch — VehicleLayer draws the truck).
			var riding_real := int(u.get("truck_id", -1)) > 0
			un.set_on_truck(bool(u.get("on_truck", false)) and not riding_real)
			# Jeremy 2026-10-04: sneak mode visual — crouched, darkened sprite.
			un.set_sneaking(bool(u.get("sneaking", false)))
			# Jeremy 2026-10-11: plague visual — the sick look sick
			# (pale-green tint). Skipped while sneaking/downed so those
			# states keep their own readability.
			un.set_sick(bool(u.get("sick", false)))
			# Jeremy 2026-10-05: swim visual — half-submerged + ripples.
			un.set_swimming(bool(u.get("swimming", false)))
			# Jeremy 2026-10-06: radiation suit visual (HTML
			# drawRadiationSuit parity) — donned by the nuclear tick.
			un.set_rad_suit(bool(u.get("inRadSuit", false)),
				float(u.get("radLevel", 0.0)))
			# Jeremy 2026-10-08: downed-unit readability — prone pose +
			# pulsing revive ring (60s bleed-out). combat_state "downed"
			# previously had no visual at all.
			un.set_downed(bool(u.get("downed", false)),
				float(u.get("downed_timer", 60.0)))
			# Jeremy 2026-10-04: thicc moose butt shake while mooning.
			un.set_mooning(String(u.get("combat_state", "")) == "mooning")
			# 2026-10-08 (wake graphics-hourly): karaoke barbarian concert
			# rig — stage lights + rising notes only while "belting" out
			# the set (swaggering in / booed off renders plain).
			if un.job == "karaoke_barbarian":
				un.set_performing(String(u.get("combat_state", "")) == "belting")
			# 2026-10-08 (wake rapid-iteration): DMV clerk ticket-window
			# rig — marquee follows the sim record's lunch state, the last
			# served ticket number, and whether the table is set up.
			if un.job == "dmv_clerk":
				un.set_dmv_state(bool(u.get("dmv_on_lunch", false)),
					int(u.get("dmv_now_serving", 0)),
					String(u.get("combat_state", "")) == "serving")
			# 2026-10-08 (wake rapid-iteration): warranty salesman
			# doorstep-pitch rig — certificates swirl and the EXPIRED
			# stamp slams while combat_state == "pitching"; the sales
			# counter edge-triggers the coin burst.
			if un.job == "warranty_salesman":
				un.set_warranty_state(String(u.get("combat_state", "")) == "pitching",
					int(u.get("warranty_sales", 0)))
			# Jeremy 2026-10-04: limb-loss stump overlay (bloody Halo-red
			# stumps over severed joints).
			# Jeremy 2026-10-04 perf: only call when limbs exist — avoids
			# 7,200 Dictionary allocs/sec from the {} default.
			if u.has("limbs"):
				un.set_limb_state(u["limbs"])
			# Jeremy 2026-10-04: one-shot crime FX, edge-triggered and
			# consumed here (struggle dust on arrest/resist, gavel flash on
			# verdict).
			var cfk: String = String(u.get("crime_fx", ""))
			if cfk != "":
				u["crime_fx"] = ""
				match cfk:
					"struggle":
						fx.death_poof(sim_pos)
						fx.hit_flash(sim_pos)
					"gavel":
						fx.hit_flash(sim_pos + Vector2(0, -44))
			# HTML parity: blood trail — heavily injured units drip blood
			# flecks while the trail timer runs (set on heavy hits in
			# combat.damage_unit; decremented in combat.tick).
			if float(u.get("blood_trail_cd", 0.0)) > 0.0 and randf() < delta * 4.0:
				fx.blood(sim_pos)
			# Combat one-shots, edge-triggered (attack/hurt restart the
			# clip only when the state actually changes).
			var cs: String = String(u.get("combat_state", ""))
			if cs != String(_prev_combat_state.get(uid, "")):
				_prev_combat_state[uid] = cs
				match cs:
					"attacking":
						un.play_attack()
					"hurt":
						un.play_hurt()
			# Jeremy 2026-10-08: building-completion celebration, also
			# edge-triggered and consumed here (the flag is stamped by
			# SimBuildings.tick_construction; the animator owns the 2.4 s).
			if float(u.get("_celebrate_t", 0.0)) > 0.0:
				u["_celebrate_t"] = 0.0
				un.play_celebrate()
