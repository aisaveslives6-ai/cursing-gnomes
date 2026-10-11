class_name SimAIDirector
extends RefCounted
## Cursing Gnomes — AI faction development director ("the brain").
##
## Ports the HTML aiThink brain verbatim where Godot has the mechanics:
##   - aiThink round-robin (one faction per tick, ~2.8s each — HTML's cadence)
##   - AI bank funding ("Keep AI factions heavily funded": floor guarantees
##     + steady drip so the AI always expands / zones)
##   - analyzeFactionState -> maneuver (expand | fortify | raid | defend | eco_war)
##   - musterMilitaryDefense (siege muster + alarm on escalation)
##   - maneuver execution: raid march, eco_war mine contest, fort garrison
##   - AI construction drip (HTML's site.progress += 0.08 for AI races)
##   - aiBuildEssentials strategic build queue (per-maneuver, max 2/think,
##     unfinished>=8 blocks, houses hard-gated on real demand)
##   - aiBuildTick62 agri plan (farm/farmhouse/windmill; undead flesh_farm)
##   - the military-industrial training doctrine (workers -> barracks roster
##     rotation -> foundry artillery -> guard towers -> AA -> nuke silo ->
##     medic camps -> doctors), via GuildHiring.queue_training
##   - ensureAirDefenses (want 8, first 2 free, stuck ones completed instantly)
##   - pickDailyGoal / factionDayPlan (stored per faction, biases training)
##
## Already covered elsewhere in Godot (NOT duplicated here):
##   - ensureLeaders -> SimArmy.ensure_government (mayor/adviser/commander/
##     watch_captain, ticked daily for every faction)
##   - ensureHomes -> SimHousing (15+15 caps, homeless migration, homesteads)
##   - ensureShopkeepers / guild hiring -> GuildHiring 4s sweep
##   - AI trade/ally/tribute proposals -> SimDiplomacy._ai_consider
##   - construction crew assignment -> WorkerAI._assign_build (auto-assigns
##     idle workers to blueprints of their faction)
##   - ai_war_tick offensive campaigns -> SimArmy
##
## Deliberate deviations from the HTML (documented, not invented mechanics):
##   - Jeremy 2026-10-04 ADVISOR MODE: the player faction thinks too — HTML
##     ran aiThink for playerRace (round-robin, non-player races first so
##     they always get full AI time). The advisers handle routine ops but
##     never fight the player: the AI bank free funding skips the player
##     (HTML verbatim), units carrying a player_order are untouched, the AI
##     won't place a building competing with the player's own blueprint
##     nearby, and training lines the player queued are skipped for the
##     think. Adviser-placed buildings go through the same blueprint queue
##     the player uses. Significant adviser actions surface as a subtle
##     Gazette note ("Your adviser commissioned a Barracks").
##   - Player orders always override AI: movement maneuvers already skip
##     player_order units (below); see _defers_to_player / _player_queued.
##   - mortar_team / field_medic training lines are skipped: those jobs don't
##     exist in the Godot build yet, so queue_training would reject them.
##   - Foundry "credit" queueing (HTML queued artillery even when broke) is
##     skipped: Godot's queue_training requires spend. The rush-finish seed
##     (4 free artillery on a rushed foundry) IS ported via cost grant.
##   - Horse purchasing (buyHorse) is skipped: no Godot equivalent. AI still
##     builds horse stables outside towns.
##   - The AI bank shares SimResources (no separate aiRes ledger); the drip
##     bypasses storage caps like HTML's uncapped aiRes.
##   - cattle_pen has no Godot building; the agri plan uses farm/farmhouse/
##     windmill (barn/coop buildings don't exist in Godot yet either).


const THINK_INTERVAL := 2.8      # HTML: each faction thinks every ~2.8s
const BUILD_MAX_PER_THINK := 2   # aiBuildEssentials: max 2 placements/think
const UNFINISHED_CAP := 8        # aiBuildEssentials: blocked at 8 unfinished
const AI_BUILD_DRIP := 0.08      # HTML AI construction assist per think
const HOUSE_RESIDENTS := 5       # HTML HOUSE_CAP default
const AA_WANT := 8               # doctrine wants 8 (ensureAirDefenses: 6->8)
const AA_FREE := 2               # first 2 AA towers are free
const WORKER_WANT := 10          # UNIT_TYPE_CAP parity for workers/roadies
const ARMY_TYPE_CAP := 10        # HTML canTrainMore: 10 of each type/faction
const GUARD_TOWERS_WANT := 4
const STABLE_DIST := 700.0       # horse stable: none within 700px of a hall
const STABLE_RING_MIN := 380.0
const STABLE_RING_MAX := 460.0
const PLAYER_DEFER_RADIUS := 320.0  # advisor mode: won't place a building
	# competing with the player's own blueprint inside this radius
## Building types the player's advisers announce when commissioned.
const ADVISER_NOTIFY := ["barracks", "cannon_foundry", "medic_camp",
	"nuke_silo", "town_hall"]

## Faction war uniques (HTML RACES[race].warBuilding).
const WAR_BUILDING := {
	"humans": "knights_castle",
	"ogres": "war_hut",
	"elves": "tome_library",
	"gnomes": "mage_spire",
	"undead": "necropolis",
}

## aiBuildTick62 agri plan for living factions (undead: flesh_farm instead).
## 2026-10-05 launch-readiness: seedshop appended — the shop's buy/restock
## economy was fully wired but no AI town ever built one, so AI factions
## could never bootstrap seeds from gold.
const AGRI_PLAN := [["farm", 2], ["farmhouse", 1], ["windmill", 1], ["seedshop", 1]]

## Foundry artillery roster (HTML opts, verbatim order).
const FOUNDRY_OPTS := ["grape_cannon", "field_cannon", "siege_rocket",
	"heavy_artillery"]
## Foundry rush-finish seed (HTML pushes these free on rush completion).
const FOUNDRY_RUSH_SEED := ["field_cannon", "grape_cannon", "siege_rocket",
	"heavy_artillery"]

var _gs = null
var _acc := 0.0
var _race_idx := 0
var _plans := {}        # faction -> {"day": int, "goal": String}
var _threat_prev := {}  # faction -> int (muster alarm escalation)

## --- War campaigns (Jeremy 2026-10-04: RTS phased wars) -----------------------
## Phases: scout (grudge + intel, no attacks) -> buildup (train + mass,
## telegraphed) -> strike (declare war + coordinated march). Replaces the
## old "random raid" energy: wars are telegraphed and strategic.
const CAMPAIGN_MIN_DAY := 12        # HTML war32AiWarTick: not early game
const CAMPAIGN_SCOUT_DAYS := 2      # grudge/scouting phase length
const CAMPAIGN_BUILDUP_MAX_DAYS := 12  # stand down if never strong enough
const CAMPAIGN_STRIKE_MIN := 1.15   # HTML estimate gate floor (timid races)
const CAMPAIGN_STRIKE_RATIO := 1.5  # strike at 1.5x defender (bold races less)
## --- War fronts: prosecuting a war AFTER the strike (Jeremy 2026-10-05) ------
## A strike is one wave; real wars need follow-through. Each active war gets a
## tracked "front": committed units are marked, losses are replaced with
## reinforcement waves (home guard and home defense keep priority), and when
## the war ends the survivors stand down and march home. Runtime-only state —
## it rebuilds from unit marks after a save/load (no save_system changes).
const FRONT_REINF_RATIO := 0.6  # reinforce when committed drops below 60%
const FRONT_WAVE_MAX := 6       # cap per reinforcement wave
const FRONT_FIRST_WAVE := 8     # initial commitment for wars that start
                                # outside a campaign (betrayal etc.)
const FRONT_REST_DAYS := 3      # survivors rest before they can re-deploy
const FRONT_HOME_RADIUS := 900.0  # "near home" for the home-guard floor
## Lane 2 (war counsel, Jeremy 2026-10-06): war exhaustion. Losing a war
## grinds faction morale down faster than the diplomacy war-weariness
## baseline; armies below this morale reinforce at half strength — the
## counsel's "another push risks rout" made real in the sim.
const EXHAUSTED_MORALE := 35.0
## --- Monastery assaults (monastery conquest = the win condition) -------------
const ASSAULT_MIN_ARMY := 6    # coordinated assault needs a real force
const ASSAULT_FORCE_MAX := 24  # cap on a single assault wave
const REINFORCE_RADIUS := 700.0  # threat scan radius around a monastery
const MONASTERY_PRIORITY_ARMY := 6  # army needed to prioritize monasteries
const MONASTERY_REACH := 3000.0     # unclaimed monastery worth marching to
## --- Command posts (Jeremy 2026-10-06 Battlefront directive) ------------------
## Towns, monasteries, and dark crystals are ALL command posts the AI plays
## like Star Wars Battlefront: claim unowned ones, assault enemy-held ones
## (wartime), reinforce threatened own ones. Score = VALUE[kind] x strategic
## weight / distance; VALUE (monastery 3.0 > town 2.0 > crystal 1.0) keeps
## monasteries the top war priority.
const POST_CLAIM_PARTY := 4   # claim party size for unowned posts
const POST_CLAIM_WEIGHT := 1.5  # strategic weight: unclaimed (cheap grabs)
const POST_WAR_WEIGHT := 1.0    # strategic weight: war-held (assault)

var _war_campaigns := {}   # faction -> {"target","phase","phase_day","warned"}
var _campaign_cooldown := {}  # faction -> day re-campaignable
var _buildup_bias := {}    # faction -> day buildup authorized (war effort)
var _assault_proposed := {}  # "faction|kind|post_id" -> day (one ask/day)
var _peace_asked := {}     # "faction|target" -> true (one ask per war)
var _war_fronts := {}      # "faction|enemy" -> {"target","strength","pos",
                           #   "day","warned","reinf_day"} (runtime-only)
var _advisor_note_day := {}  # building type -> day_number last announced

## --- Per-think census (perf R20: kill per-think linear-scan storms) -----------
## A think used to run ~40 full scans of _gs.units / _gs.buildings (every
## _count_build / _count_job / _pop_of / _army_of / _workers_of call walked
## the whole array; _analyze nested a units scan inside every gold-site
## scan). Now each _think() builds ONE census for its faction and the
## helpers read it. Behavior is identical: nothing inside a think mutates
## unit jobs or adds/removes buildings outside _place/_place_free (both bump
## the census on success), and the census is invalidated when the think
## ends so direct test/world calls always see live state.
var _tc_valid := false
var _tc_faction := ""
var _tc_job := {}         # job string -> live unit count (thinking faction)
var _tc_pop := 0          # live unit count (thinking faction)
var _tc_army: Array = []  # live military unit dicts (thinking faction)
var _tc_workers: Array = []  # live worker unit dicts (thinking faction)
var _tc_build := {}       # building type -> live count (thinking faction)
var _tc_build_town := {}  # building type -> town_id -> live count
var _tc_build_list := {}  # building type -> Array of building dicts
var _tc_needs := {}       # job -> faction_needs_unit result (memoized/think)
var _tc_foe_military := {}  # perf R31: faction -> [alive military unit dicts]
                            # for NON-thinking factions (threat scans). Built
                            # in the same unit pass as the census, so the
                            # per-think enemy-army scan walks foes only.
var _ad_done := false     # perf R31: _air_defenses runs once per think.
                          # _train calls it conditionally mid-think and
                          # _think calls it unconditionally at the end; the
                          # second pass can never place anything the first
                          # didn't (gold only decreases through a think, spots
                          # don't change), so it is pure waste.


## One pass over units + one pass over buildings for the thinking faction.
func _rebuild_think_census(faction: String) -> void:
	_tc_valid = true
	_tc_faction = faction
	_tc_job = {}
	_tc_pop = 0
	_tc_army = []
	_tc_workers = []
	_tc_build = {}
	_tc_build_town = {}
	_tc_build_list = {}
	_tc_needs = {}
	_tc_foe_military = {}
	_ad_done = false
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		var ufac := String(u.get("faction", ""))
		var job := String(u.get("job", ""))
		if ufac != faction:
			# Perf R31: bucket foe military in the same pass (threat scans).
			if JobDefs.is_military(job):
				if not _tc_foe_military.has(ufac):
					_tc_foe_military[ufac] = []
				(_tc_foe_military[ufac] as Array).append(u)
			continue
		_tc_pop += 1
		_tc_job[job] = int(_tc_job.get(job, 0)) + 1
		if JobDefs.is_military(job):
			_tc_army.append(u)
		elif job == "worker":
			_tc_workers.append(u)
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		_tc_bump_build(faction, b)


## Record one live building in the census (rebuild + post-_place bumps).
## _place returns the same dict add_building stored, so list refs stay live.
func _tc_bump_build(faction: String, b: Dictionary) -> void:
	if not (_tc_valid and _tc_faction == faction):
		return
	var t := String(b.get("type", ""))
	_tc_build[t] = int(_tc_build.get(t, 0)) + 1
	var tid := int(b.get("town_id", -1))
	var per: Dictionary = _tc_build_town.get(t, {})
	per[tid] = int(per.get(tid, 0)) + 1
	_tc_build_town[t] = per
	var lst: Array = _tc_build_list.get(t, [])
	lst.append(b)
	_tc_build_list[t] = lst


## perf R20: spawner.faction_needs_unit is constant inside one _train (same
## faction, same army_target; no spawns, deaths, job or work-state changes
## mid-think), but it walks every unit. Memoize per think.
func _needs_unit(faction: String, job: String, army_target: int) -> bool:
	if _tc_valid and _tc_faction == faction and _tc_needs.has(job):
		return bool(_tc_needs[job])
	var v: bool = _gs.spawner.faction_needs_unit(faction, job, army_target)
	if _tc_valid and _tc_faction == faction:
		_tc_needs[job] = v
	return v


## perf R20: queue_training wrapper that hands hiring the think-census job
## count (identical to population.count_job mid-think) so the per-call full
## unit scan is skipped. Behavior identical; -1 keeps the old path.
func _qtrain(faction: String, building: Dictionary,
		unit_type: String) -> bool:
	var kc := -1
	if _tc_valid and _tc_faction == faction:
		kc = int(_tc_job.get(unit_type, 0))
	var hiring = _gs.hiring
	if hiring == null:
		return false
	return hiring.queue_training(building, unit_type, false, kc)


func _init(game_state) -> void:
	_gs = game_state


## --- Main tick ---------------------------------------------------------------

func tick(delta: float) -> void:
	if _gs == null:
		return
	_acc += delta
	var guard := 0
	while _acc >= THINK_INTERVAL and guard < 8:
		_acc -= THINK_INTERVAL
		guard += 1
		_think_next()


## Round-robin: ONE faction per tick (HTML aiThink's perf design). The
## player faction thinks too — in ADVISOR MODE (see deviations above) —
## and goes LAST so AI factions always get full AI time (HTML sorted
## playerRace last the same way).
func _think_next() -> void:
	var order: Array[String] = []
	for f: String in _gs.active_factions:
		if f == _gs.player_faction:
			continue
		order.append(f)
	if _gs.active_factions.has(_gs.player_faction):
		order.append(_gs.player_faction)
	if order.is_empty():
		return
	_race_idx = _race_idx % order.size()
	_think(order[_race_idx])
	_race_idx = (_race_idx + 1) % order.size()


## True when the faction is the player's — the director runs in advisor
## mode: routine ops only, and every player order wins over the AI.
func _is_advisor(faction: String) -> bool:
	return faction != "" and faction == _gs.player_faction


func _think(faction: String) -> void:
	_rebuild_think_census(faction)  # perf R20: one roster pass per think
	var hall: Dictionary = _hall(faction)
	if hall.is_empty():
		_tc_valid = false
		return
	# Advisor mode: no free AI-bank funding for the player (HTML verbatim —
	# the funding block skipped playerRace; the advisers spend real money).
	if not _is_advisor(faction):
		_ai_bank(faction)
	var st: Dictionary = _analyze(faction, hall)
	_refresh_daily_plan(faction, hall, st)
	_muster_defense(faction, hall, st)
	_clear_finished_raids(faction)  # Jeremy 2026-10-05: stand down
	# arrived/finished counter-raids every think, not just on defense days
	_war_strategy(faction, st)  # Jeremy 2026-10-04: phased war campaigns
	_war_exhaustion_tick(faction)  # Lane 2: losing wars grind morale down
	_maneuver(faction, hall, st)
	_road_networks(faction)  # Jeremy 2026-10-10: planned AI road networks
	_seek_command_posts(faction, st)  # Jeremy 2026-10-06: Battlefront —
		# towns, monasteries, and dark crystals are ALL command posts
	_ai_build_drip(faction)
	_build_essentials(faction, hall, st)
	_agri(faction, hall)
	_town_expand_trickle(faction, hall, st)
	_found_settlement(faction, hall, st)
	_train(faction, hall, st)
	_arm_forces(faction, hall, st)  # Jeremy 2026-10-05: AI armament program
	_force_civ_work(faction, st)  # Jeremy 2026-10-04: HTML forceCivWork port
	_food_emergency(faction, hall, st)  # Jeremy 2026-10-05: famine response
	_air_defenses(faction, hall)
	_tc_valid = false  # perf R20: census dies with the think


## --- AI bank (HTML aiThink funding block, verbatim numbers) -------------------

func _ai_bank(faction: String) -> void:
	var r = _gs.resources
	if r.get_amount(faction, "gold") < 400.0:
		r.add_resource(faction, "gold", 150.0, true)
	if r.get_amount(faction, "wood") < 350.0:
		r.add_resource(faction, "wood", 120.0, true)
	r.add_resource(faction, "gold", 18.0, true)
	r.add_resource(faction, "wood", 14.0, true)
	r.add_resource(faction, "food", 4.0, true)


## --- Faction analysis (HTML analyzeFactionState, verbatim logic) --------------

func _hall(faction: String) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in ["town_hall", "hall"]:
			return b
	return {}


func _army_of(faction: String) -> Array:
	if _tc_valid and _tc_faction == faction:
		return _tc_army.duplicate()  # perf R20: census read
	var out := []
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			out.append(u)
	return out


func _workers_of(faction: String) -> Array:
	if _tc_valid and _tc_faction == faction:
		return _tc_workers.duplicate()  # perf R20: census read
	var out := []
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("job", "")) == "worker":
			out.append(u)
	return out


func _pop_of(faction: String) -> int:
	if _tc_valid and _tc_faction == faction:
		return _tc_pop  # perf R20: census read
	var n := 0
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)) and String(u.get("faction", "")) == faction:
			n += 1
	return n


func _count_build(faction: String, btype: String, town_id: int = -1) -> int:
	if _tc_valid and _tc_faction == faction:
		if town_id >= 0:  # perf R20: census read
			var per: Dictionary = _tc_build_town.get(btype, {})
			return int(per.get(town_id, 0))
		return int(_tc_build.get(btype, 0))
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != btype:
			continue
		if town_id >= 0 and int(b.get("town_id", -1)) != town_id:
			continue
		n += 1
	return n


func _at_war(faction: String) -> bool:
	if _gs.diplomacy == null:
		return false
	for o: String in _gs.active_factions:
		if o == faction:
			continue
		if _gs.diplomacy.relation_state(faction, o) == "war":
			return true
	return false


func _analyze(faction: String, hall: Dictionary) -> Dictionary:
	var hall_pos: Vector2 = hall.get("position", Vector2.ZERO)
	var army: Array = _army_of(faction)
	var workers: Array = _workers_of(faction)
	var pop := _pop_of(faction)
	var war_b: String = String(WAR_BUILDING.get(faction, ""))
	var houses := _count_build(faction, "house")
	var barracks := _count_build(faction, "barracks")
	var storage := _count_build(faction, "storage")
	var foundry := _count_build(faction, "cannon_foundry")
	var war_build_n := _count_build(faction, war_b) if war_b != "" else 0
	# Threat scan: nearest hall of a faction we are actually AT WAR with.
	# (HTML scanned non-allied halls, which could march a raid at a neutral
	# faction — including the player — while at war with someone else. The
	# raid maneuver only triggers at war, so the war enemy is the target.)
	var nearest_enemy_hall := {}
	var enemy_hall_d := INF
	var enemy_army_near := 0
	var under_attack_near := false  # perf R20: fused into the 700px pass
	var war_enemy := ""  # Jeremy 2026-10-05: faction behind nearest_enemy_hall (counter-raid target)
	if _gs.diplomacy != null:
		for b: Dictionary in _gs.buildings:
			if not bool(b.get("alive", false)):
				continue
			if not String(b.get("type", "")) in ["town_hall", "hall"]:
				continue
			var bf: String = String(b.get("faction", ""))
			if bf == faction:
				continue
			if _gs.diplomacy.relation_state(faction, bf) != "war":
				continue
			var d: float = hall_pos.distance_to(b.get("position", Vector2.ZERO))
			if d < enemy_hall_d:
				enemy_hall_d = d
				nearest_enemy_hall = b
				war_enemy = bf
	# perf R20: one fused proximity pass (was two full unit scans: the 700px
	# threat count and the 380px under-attack check). Identical results.
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) == faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		var prox_d: float = hall_pos.distance_to(u.get("position", Vector2.ZERO))
		if prox_d < 700.0:
			enemy_army_near += 1
		if prox_d < 380.0:
			under_attack_near = true
	# Contested gold veins (HTML mine contest, verbatim: enemy nearer than us).
	# perf R20: classify units ONCE into position arrays instead of a full
	# units scan per gold site. Same minf comparisons, same sets, same result.
	var my_pos := PackedVector2Array()
	var en_pos := PackedVector2Array()
	for cu: Dictionary in _gs.units:
		if not bool(cu.get("alive", false)):
			continue
		if String(cu.get("faction", "")) == faction:
			my_pos.append(cu.get("position", Vector2.ZERO))
		else:
			var cuj := String(cu.get("job", ""))
			if JobDefs.is_military(cuj) or cuj == "worker":
				en_pos.append(cu.get("position", Vector2.ZERO))
	var contested := 0
	for s: Dictionary in _gs.work_sites:
		if String(s.get("kind", "")) != "gold_vein":
			continue
		if float(s.get("amount", 0.0)) <= 0.0:
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		if hall_pos.distance_to(sp) > 900.0:
			continue
		var my_d := INF
		for mp in my_pos:
			my_d = minf(my_d, sp.distance_to(mp))
		var en_d := INF
		for ep in en_pos:
			en_d = minf(en_d, sp.distance_to(ep))
		if en_d < my_d:
			contested += 1
	var under_attack: bool = enemy_army_near >= 3 or under_attack_near
	var my_power: float = float(army.size()) + float(foundry) * 2.0 \
		+ float(war_build_n) * 3.0
	var need_army: float = maxf(10.0, float(enemy_army_near) * 1.4 + 6.0)
	var r = _gs.resources
	var economy_weak: bool = (r.get_amount(faction, "gold") < 80.0 \
			and r.get_amount(faction, "wood") < 70.0) or workers.size() < 4
	var housing_gap: int = maxi(0, int(ceil(float(pop) / float(HOUSE_RESIDENTS))) \
		- houses + 1)
	var at_war := _at_war(faction)
	# Maneuver decision (HTML verbatim).
	var maneuver := "expand"
	if under_attack:
		maneuver = "defend"
	elif at_war and float(army.size()) >= need_army \
			and not nearest_enemy_hall.is_empty():
		maneuver = "raid"
	elif contested >= 2:
		maneuver = "eco_war"
	elif float(army.size()) < need_army * 0.6:
		maneuver = "fortify"
	# Jeremy 2026-10-04: monastery conquest is THE win condition — when the
	# faction fields a real army and a monastery is worth taking, that
	# outranks routine expansion (but never defense or active war).
	elif _monastery_opportunity(faction, hall_pos, army.size()):
		maneuver = "monastery"
	elif economy_weak:
		maneuver = "expand"
	elif at_war:
		maneuver = "raid"
	else:
		maneuver = "expand"
	return {
		"hall": hall, "hall_pos": hall_pos, "army": army, "workers": workers,
		"pop": pop, "houses": houses, "barracks": barracks,
		"storage": storage, "foundry": foundry, "war_b": war_b,
		"war_build_n": war_build_n, "nearest_enemy_hall": nearest_enemy_hall,
		"enemy_hall_d": enemy_hall_d, "enemy_army_near": enemy_army_near,
		"contested": contested, "under_attack": under_attack,
		"my_power": my_power, "need_army": need_army,
		"economy_weak": economy_weak, "housing_gap": housing_gap,
		"at_war": at_war, "maneuver": maneuver, "war_enemy": war_enemy,
	}

## --- Daily plan (HTML pickDailyGoal + refreshDailyPlans) ---------------------

## The faction's current daily goal ("grow" | "economy" | "war" | "defend" |
## "expand" | "build_military" | "survive"). Refreshed once per game day.
func plan_goal(faction: String) -> String:
	var p: Dictionary = _plans.get(faction, {})
	return String(p.get("goal", "grow"))


func _refresh_daily_plan(faction: String, hall: Dictionary, st: Dictionary) -> void:
	var p: Dictionary = _plans.get(faction, {"day": -1, "goal": "grow"})
	if int(p.get("day", -1)) == _gs.day_number:
		return
	p["day"] = _gs.day_number
	p["goal"] = _pick_daily_goal(faction, hall, st)
	_plans[faction] = p


func _pick_daily_goal(faction: String, hall: Dictionary, st: Dictionary) -> String:
	var hall_pos: Vector2 = st["hall_pos"]
	var r = _gs.resources
	var pop: int = int(st["pop"])
	var army: Array = st["army"]
	var citizens := 0
	if _tc_valid and _tc_faction == faction:
		citizens = _tc_pop - _tc_army.size()  # perf R20: census read
	else:
		for u: Dictionary in _gs.units:
			if not bool(u.get("alive", false)):
				continue
			if String(u.get("faction", "")) != faction:
				continue
			if not JobDefs.is_military(String(u.get("job", ""))):
				citizens += 1
	var under_attack: bool = false
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) == faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if hall_pos.distance_to(u.get("position", Vector2.ZERO)) < 500.0:
			under_attack = true
			break
	var foe_near := false
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not String(b.get("type", "")) in ["town_hall", "hall"]:
			continue
		if String(b.get("faction", "")) == faction:
			continue
		if hall_pos.distance_to(b.get("position", Vector2.ZERO)) < 1600.0:
			foe_near = true
			break
	var workers: Array = st["workers"]
	if under_attack:
		return "defend"
	if citizens < 10 or pop < 14:
		return "grow"
	if (r.get_amount(faction, "gold") < 80.0 \
			or r.get_amount(faction, "wood") < 80.0) and citizens >= 5:
		return "economy"
	if bool(st["at_war"]) and army.size() >= 6 and foe_near:
		return "war"
	if _count_build(faction, "town_hall") + _count_build(faction, "hall") < 2 \
			and r.get_amount(faction, "gold") > 300.0 \
			and r.get_amount(faction, "wood") > 250.0:
		return "expand"
	if faction == "ogres":
		return "build_military" if army.size() < 8 \
			else ("war" if bool(st["at_war"])
				else ("economy" if workers.size() < 10 else "build_military"))
	if faction == "gnomes":
		return "build_military" if army.size() < 8 \
			else ("war" if bool(st["at_war"])
				else ("economy" if workers.size() < 8 else "build_military"))
	return "grow" if citizens < 18 else "economy"


## --- Siege muster (HTML musterMilitaryDefense) --------------------------------

## Threat level: 2 = city under attack (enemy military within 380px of the
## hall), 1 = threatened (within 700px), 0 = clear. Alarms once per
## escalation via the Royal Gazette.
## HTML townThreatLevel verbatim (fix79 Siege Doctrine): 0 = calm,
## 1 = hostile force approaching, 2 = town under attack.
##   - cityUnderAttack: ANY foreign unit (not just military) within 280px
##     of the hall — a raider at the gates is an attack.
##   - cityThreatened: a hostile force — military, raider, monster,
##     bandit, or leader — within 1500px of the hall (early warning).
## Jeremy 2026-10-04 floor kept: being at war is minimum level 1 even
## with no troops nearby. Drives _muster_defense, SimGarrison's skip,
## SimSiege's civilian response, and the proposal threat read.
func _threat_level(faction: String, hall_pos: Vector2) -> int:
	var lvl := 0
	if _at_war(faction):
		lvl = 1
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if bool(u.get("downed", false)):
			continue
		var uf: String = String(u.get("faction", ""))
		if uf == faction:
			continue
		var d: float = hall_pos.distance_to(u.get("position", Vector2.ZERO))
		if d < 280.0:
			return 2  # HTML cityUnderAttack: foreign unit at the hall
		if d < 1500.0 and _is_hostile_force(faction, uf, u):
			lvl = 1
	return lvl


## HTML cityThreatened force test: hostile AND (monster / bandit /
## leader / military). Monsters bypass diplomacy; bandits are raiders.
func _is_hostile_force(faction: String, uf: String, u: Dictionary) -> bool:
	if uf == "monster" or uf == "bandit":
		return true
	if _gs.diplomacy == null:
		return false
	if not _gs.diplomacy.combat_enabled(faction, uf):
		return false
	return bool(u.get("is_leader", false)) \
		or JobDefs.is_military(String(u.get("job", "worker")))


func _muster_defense(faction: String, hall: Dictionary, st: Dictionary) -> void:
	var hall_pos: Vector2 = st["hall_pos"]
	var threat := _threat_level(faction, hall_pos)
	var prev: int = int(_threat_prev.get(faction, 0))
	if threat != prev:
		_threat_prev[faction] = threat
		if threat >= 1:
			_gazette("CITY MUSTER",
				"The %s sound the alarm — %s! Every soldier to the walls!"
				% [_fname(faction),
					"the city is under attack" if threat >= 2
					else "a hostile force approaches"])
			_commander_says(faction, hall_pos,
				"To arms! Defend the city!" if threat >= 2
				else "Enemy force approaching. Stand to.")
	if threat < 1:
		return
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		if u.has("counter_raid"):
			continue  # Jeremy 2026-10-05: counter-raid is away on its
			# mission — the muster must not recall it mid-flight.
		u["defend_mode"] = true
		# Abandon far offensives — the city comes first.
		if u.has("deploy_target_id"):
			u.erase("deploy_target_id")
			u.erase("deploy_target_kind")
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(hall_pos) > 700.0 or threat >= 2:
			# Defensive ring around the hall (golden-angle spread by unit id).
			var uid := int(u.get("id", 0))
			var ang := float(uid) * 2.39996
			var ring := 230.0 + float(uid % 5) * 45.0
			u["move_target"] = hall_pos + Vector2(cos(ang), sin(ang)) * ring


## --- War campaigns: RTS phased wars (Jeremy 2026-10-04) -----------------------
##
## Replaces "random raid" energy with telegraphed, strategic campaigns:
##   Phase 1 — SCOUT: grudge + intel. The faction dislikes another (bad
##     relations, slur incidents, past wars in leader memory). No attacks —
##     rumors seed, the leader remembers, the player can see it coming.
##   Phase 2 — BUILDUP: the declare_war proposal is approved (player asked
##     on the phone; AI factions evaluated strategically). The faction
##     trains, masses troops, builds defenses — visible via troop counts,
##     Gazette rumors, and an adviser warning when YOU are the target.
##   Phase 3 — STRIKE: at a favorable strength ratio (1.5x, bolder races
##     less) the faction declares war and launches a coordinated march on
##     the enemy hall AND their held monasteries.

## Public threat read for the proposal protocol (SimProposals._ai_evaluate).
func threat_level_of(faction: String) -> int:
	var hall := _hall(faction)
	if hall.is_empty():
		return 0
	return _threat_level(faction, hall.get("position", Vector2.ZERO))


## ADVISOR MODE entry: run the strategic layer (campaigns, assaults) for a
## faction the round-robin doesn't normally think for. The director already
## thinks the player faction itself; this stays for explicit callers.
func strategic_tick_for(faction: String) -> void:
	var hall := _hall(faction)
	if hall.is_empty():
		return
	var st := _analyze(faction, hall)
	_war_strategy(faction, st)
	_seek_monasteries(faction, st)


func _war_strategy(faction: String, st: Dictionary) -> void:
	if _gs.diplomacy == null:
		return
	if int(_gs.day_number) < CAMPAIGN_MIN_DAY:
		return
	var camp: Dictionary = _war_campaigns.get(faction, {})
	if camp.is_empty():
		_maybe_start_campaign(faction, st)
		_maybe_sue_for_peace(faction, st)
		_war_front_tick(faction, st)  # Jeremy 2026-10-05: prosecute live
		# wars — reinforce faltering fronts, stand down at peace.
		return
	var target: String = String(camp.get("target", ""))
	if target == "" or not _gs.active_factions.has(target):
		_war_campaigns.erase(faction)
		return
	# War already broke out (by anyone) — the campaign did its job.
	if _gs.diplomacy.relation_state(faction, target) == "war":
		_war_campaigns.erase(faction)
		_buildup_bias.erase(faction)
		return
	var phase: String = String(camp.get("phase", "scout"))
	var day := int(_gs.day_number)
	if phase == "scout":
		if day - int(camp.get("phase_day", day)) >= CAMPAIGN_SCOUT_DAYS:
			_advance_to_buildup(faction, camp, target, st)
	elif phase == "buildup":
		_buildup_tick(faction, camp, target, st)


## Phase 1 — scout: find the most-hated valid target (HTML war32AiWarTick
## targeting: score <= warT, never friends, truce binds, liking the player
## prohibits attack). Starts a scout-phase campaign; no attacks yet.
func _maybe_start_campaign(faction: String, _st: Dictionary) -> void:
	var dip = _gs.diplomacy
	if dip == null:
		return
	if int(_gs.day_number) < int(_campaign_cooldown.get(faction, 0)):
		return
	var aggro := float(dip.faction_traits(faction).get("aggro", 0.5))
	var war_t := -30.0 - aggro * 25.0  # HTML warT = -30 - aggro*0.25 (0..100)
	var best := ""
	var best_score := 0.0
	for o: String in _gs.active_factions:
		if o == faction:
			continue
		var rel: String = dip.relation_state(faction, o)
		if rel == "war" or rel == "allied":
			continue
		if dip.truce_active(faction, o):
			continue
		var sc = dip.relation_score(faction, o)
		# HTML: liking the player prohibits attack, period.
		if o == _gs.player_faction and sc > 15.0:
			continue
		if sc <= war_t and sc < best_score:
			best_score = sc
			best = o
	if best == "":
		return
	# HTML: even a justified war is a decision — don't start one every think.
	if randf() > 0.35:
		return
	_war_campaigns[faction] = {
		"target": best, "phase": "scout",
		"phase_day": int(_gs.day_number), "warned": false,
	}
	# The grudge goes into the leader's memory (HTML war32Mem parity).
	var fl = _gs.get("faction_leaders")
	if fl != null and fl.has_method("remember"):
		fl.remember(faction, "grudge", best,
			"The %s wronged us. Scouts watch their borders."
			% _fname(best), -0.6)
	# Telegraph phase 1: rumors, not armies. The player can see it coming.
	_seed_war_rumor("Travelers whisper the %s watch the %s with hungry eyes."
		% [_fname(faction), _fname(best)])
	# The target's border watch spots the probing: one tally for the news
	# desk's RAIDERS PROBE OUR BORDERS trivia bucket.
	_report_probe_trivia(best)


## One raid-probe tally for the news desk's RAIDERS PROBE OUR BORDERS
## trivia bucket (called when a scout-phase war campaign starts — the
## target's border watch spots the probing). Null-safe: bare-sim tests
## and worlds without a court skip silently; no new persisted state, so
## old saves are unaffected. Reported straight to the news desk, not
## bus.gazette_story — the campaign already telegraphs via rumor, and a
## per-campaign bus story would mint a rumor-mill whisper each time
## (the 2026-10-07 build/train pattern).
func _report_probe_trivia(target: String) -> void:
	var court = _gs.get("court_sys")
	if court == null:
		return
	var desk = court.get("news_desk")
	if desk == null or not desk.has_method("report"):
		return
	desk.report("Raiders spotted probing the border",
		"Border watch spotted raiders probing near %s lands."
		% _fname(target))


## Phase 1 -> 2: the declare_war proposal authorizes the campaign. AI
## factions auto-resolve (synchronous); the player faction waits on the
## phone modal — the campaign sits in scout until Jeremy answers.
func _advance_to_buildup(faction: String, camp: Dictionary, target: String,
		_st: Dictionary) -> void:
	var props = _gs.get("proposals")
	if props == null:
		campaign_authorized(faction, target)
		return
	var p: Dictionary = props.propose(faction,
		SimProposals.KIND_DECLARE_WAR, {"target": target})
	var status: String = String(p.get("status", ""))
	if status == "approved" or status == "executed":
		# campaign_authorized already ran via _execute; belt and braces:
		camp["phase"] = "buildup"
		camp["phase_day"] = int(_gs.day_number)
		_buildup_bias[faction] = int(_gs.day_number)
	elif status == "denied":
		_war_campaigns.erase(faction)
		_campaign_cooldown[faction] = int(_gs.day_number)
	# "open" (player hasn't answered) or "cooldown": wait, stay in scout.


## Called by SimProposals when a declare_war proposal is approved
## (AI auto-resolve OR the player's phone tap).
func campaign_authorized(faction: String, target: String) -> void:
	var camp: Dictionary = _war_campaigns.get(faction, {})
	if camp.is_empty():
		camp = {"target": target, "phase": "scout",
			"phase_day": int(_gs.day_number), "warned": false}
		_war_campaigns[faction] = camp
	if String(camp.get("target", "")) != target:
		return
	camp["phase"] = "buildup"
	camp["phase_day"] = int(_gs.day_number)
	_buildup_bias[faction] = int(_gs.day_number)
	_gazette("WAR DRUMS",
		"The %s beat the drums of war. Every %s soldier drills at dawn — "
		% [_fname(faction), _fname(faction)] + "the %s should arm themselves."
		% _fname(target))
	_seed_war_rumor("The %s are massing troops near the %s border. War "
		% [_fname(faction), _fname(target)] + "is coming, the old soldiers say.")


## Called by SimProposals when a proposal is DENIED (player's phone tap or
## AI evaluation). A denied war campaign is dropped outright — the crown
## said no, so the advisers stand down instead of re-asking.
func on_proposal_denied(p: Dictionary) -> void:
	var kind: String = String(p.get("kind", ""))
	var faction: String = String(p.get("faction", ""))
	if kind == SimProposals.KIND_DECLARE_WAR:
		_war_campaigns.erase(faction)
		_buildup_bias.erase(faction)
		_campaign_cooldown[faction] = int(_gs.day_number)


## Phase 2 — buildup: keep the war-effort training bias fresh, telegraph,
## and strike when the strength ratio is favorable.
func _buildup_tick(faction: String, camp: Dictionary, target: String,
		st: Dictionary) -> void:
	_buildup_bias[faction] = int(_gs.day_number)
	var dip = _gs.diplomacy
	var aggro := float(dip.faction_traits(faction).get("aggro", 0.5))
	# Bolder races strike at lower ratios (HTML estimate gate, inverted).
	var need := clampf(CAMPAIGN_STRIKE_RATIO - aggro * 0.35,
		CAMPAIGN_STRIKE_MIN, CAMPAIGN_STRIKE_RATIO)
	var own = dip.military_strength(faction)
	var foe = dip.military_strength(target)
	# Telegraph: the advisers warn Jeremy when HE is the target.
	if target == _gs.player_faction and not bool(camp.get("warned", false)):
		camp["warned"] = true
		_warn_player_of_buildup(faction)
	var day := int(_gs.day_number)
	if foe <= 0.0 or own >= foe * need:
		_launch_strike(faction, target, st)
		return
	if day - int(camp.get("phase_day", day)) > CAMPAIGN_BUILDUP_MAX_DAYS:
		if own >= foe * CAMPAIGN_STRIKE_MIN:
			_launch_strike(faction, target, st)
		else:
			# Stand down: never strong enough. Cooldown, no nag.
			_war_campaigns.erase(faction)
			_buildup_bias.erase(faction)
			_campaign_cooldown[faction] = day
			_seed_war_rumor("The %s stood down — their war drums fall "
				% _fname(faction) + "silent. This time.")


## Phase 3 — strike: declare war and launch the coordinated march — the
## bulk of the army on the enemy hall, detachments on their held
## monasteries (wartime steals are legal; power = ruling the land).
func _launch_strike(faction: String, target: String, st: Dictionary) -> void:
	var dip = _gs.diplomacy
	var res: Dictionary = dip.declare_war(faction, target, "war campaign")
	if not bool(res.get("ok", false)):
		_war_campaigns.erase(faction)
		_buildup_bias.erase(faction)
		return
	var hall := _enemy_hall_of(target, faction)
	var mons_targets := _enemy_monasteries(faction, target)
	var army: Array = st.get("army", [])
	var marchers := 0
	var max_march := mini(army.size(), ASSAULT_FORCE_MAX)
	# Every committed troop is marked with its war front so the front-tick
	# can count survivors, replace losses, and stand them down at peace.
	var fkey := "%s|%s" % [faction, target]
	# Detachments first: up to 6 troops per enemy-held monastery.
	for mt: Dictionary in mons_targets:
		if marchers >= max_march:
			break
		var mp: Vector2 = mt.get("position", Vector2.ZERO)
		var mid := int(mt.get("id", 0))
		var det := 0
		for u: Dictionary in army:
			if marchers >= max_march or det >= 6:
				break
			if not (u.get("player_order", {}) as Dictionary).is_empty():
				continue
			if u.has("deploy_target_id") or u.has("monastery_march") \
					or u.has("monastery_guard") or u.has("post_march") \
					or u.has("post_guard"):
				continue
			u["defend_mode"] = false
			u["move_target"] = mp + Vector2(
				randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
			u["monastery_march"] = mid
			u["war_front"] = fkey
			marchers += 1
			det += 1
	# The main host marches on the enemy hall in loose formation.
	if not hall.is_empty():
		var tpos: Vector2 = hall.get("position", Vector2.ZERO)
		for u: Dictionary in army:
			if marchers >= max_march:
				break
			if not (u.get("player_order", {}) as Dictionary).is_empty():
				continue
			if u.has("deploy_target_id") or u.has("monastery_march") \
					or u.has("monastery_guard") or u.has("post_march") \
					or u.has("post_guard"):
				continue
			u["defend_mode"] = false
			var uid := int(u.get("id", 0))
			var off := Vector2(float(uid % 8) * 18.0,
				float((uid / 8) % 4) * 16.0)
			u["move_target"] = tpos + off
			u["war_front"] = fkey
			marchers += 1
	_gazette("WAR!",
		"The %s march on the %s with %d troops! " % [_fname(faction),
			_fname(target), marchers] + "The drums promised this day would come.")
	_commander_says(faction, st.get("hall_pos", Vector2.ZERO),
		"For the realm — ATTACK!")
	# Record the front: the strike's survivors are tracked from here, so
	# losses get replaced and survivors stand down when peace comes.
	var fpos: Vector2 = hall.get("position", Vector2.ZERO)
	if fpos == Vector2.ZERO and not mons_targets.is_empty():
		fpos = (mons_targets[0] as Dictionary).get("position", Vector2.ZERO)
	_war_fronts[fkey] = {"target": target, "strength": marchers,
		"pos": fpos, "day": int(_gs.day_number), "warned": false,
		"reinf_day": 0}
	_war_campaigns.erase(faction)
	_buildup_bias.erase(faction)


## Losing a war badly? The advisers file a sue_for_peace proposal — the
## player answers on the phone; AI factions are evaluated strategically.
func _maybe_sue_for_peace(faction: String, _st: Dictionary) -> void:
	var dip = _gs.diplomacy
	if dip == null:
		return
	var props = _gs.get("proposals")
	if props == null:
		return
	for o: String in _gs.active_factions:
		if o == faction:
			continue
		if dip.relation_state(faction, o) != "war":
			continue
		# Only ask when genuinely losing — never nag a winning crown.
		var foe = dip.military_strength(o)
		if foe > 0.0 and dip.military_strength(faction) >= foe * 0.5:
			continue
		var key := "%s|%s" % [faction, o]
		if bool(_peace_asked.get(key, false)):
			continue
		_peace_asked[key] = true
		props.propose(faction, SimProposals.KIND_SUE_FOR_PEACE,
			{"target": o})


## --- War exhaustion (Lane 2, Jeremy 2026-10-06) ------------------------------
## Losing a war degrades troop morale faster than the diplomacy baseline
## (-1/day at war): a side outmatched worse than 3-to-5 takes an extra -1
## morale per think. Faction morale already gates AI surrender
## (morale < 55) and the collapse tick; exhaustion ALSO halves
## reinforcement waves in _maintain_front below — the counsel's
## "another push risks rout" made real. Runs for every faction the
## director thinks for (round-robin, player last); the player's own
## troops are never auto-reinforced anyway (sovereignty), so this only
## ever weakens AI pushes.
func _war_exhaustion_tick(faction: String) -> void:
	var dip = _gs.diplomacy
	if dip == null:
		return
	if not dip.has_method("adjust_morale"):
		return
	for o: String in _gs.active_factions:
		if o == faction:
			continue
		if dip.relation_state(faction, o) != "war":
			continue
		var theirs := float(dip.military_strength(o))
		if theirs <= 0.0:
			continue
		if float(dip.military_strength(faction)) < theirs * 0.6:
			dip.adjust_morale(faction, -1.0)


## True when the faction's army is too exhausted to push: at war and
## morale below EXHAUSTED_MORALE.
func _faction_exhausted(faction: String) -> bool:
	var dip = _gs.diplomacy
	if dip == null:
		return false
	if dip.morale_of(faction) >= EXHAUSTED_MORALE:
		return false
	for o: String in _gs.active_factions:
		if o != faction and dip.relation_state(faction, o) == "war":
			return true
	return false


## --- War fronts: prosecuting a live war (Jeremy 2026-10-05) ------------------
## The strike is one wave; wars need follow-through. Every active war gets a
## tracked front: committed troops carry a "war_front" mark ("faction|enemy").
## Each think the director counts survivors (withdrawing troops don't count),
## rests troops that made it home, replaces losses with a reinforcement wave
## (home defense and the home-guard floor keep priority), and stands the
## whole front down — marching survivors home — when the war ends. Wars that
## begin outside a campaign (betrayal, backchannel) get a front too, so they
## actually march instead of being wars on paper only. The player faction is
## never auto-reinforced: the advisers warn on the Gazette, Jeremy commands.
func _war_front_tick(faction: String, st: Dictionary) -> void:
	var dip = _gs.diplomacy
	if dip == null:
		return
	var hall_pos: Vector2 = st.get("hall_pos", Vector2.ZERO)
	for o: String in _gs.active_factions:
		if o == faction:
			continue
		var key := "%s|%s" % [faction, o]
		if dip.relation_state(faction, o) == "war":
			_maintain_front(faction, o, key, hall_pos)
		elif _war_fronts.has(key):
			_stand_down_front(faction, o, key, hall_pos)
	# Fronts whose enemy is gone entirely (eliminated faction).
	for key: String in _war_fronts.keys():
		var parts := key.split("|")
		if parts.size() != 2 or parts[0] != faction:
			continue
		if not _gs.active_factions.has(parts[1]):
			_stand_down_front(faction, parts[1], key, hall_pos)


## Count live, still-committed troops on a front. Withdrawing troops are
## falling back, not fighting; troops that reached home are rested and
## unmarked (they need FRONT_REST_DAYS before they can re-deploy).
func _front_committed(faction: String, key: String,
		hall_pos: Vector2) -> int:
	var day := int(_gs.day_number)
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("war_front", "")) != key:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if bool(u.get("withdrawing", false)):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		var mpos: Vector2 = u.get("move_target", upos)
		if upos.distance_to(hall_pos) < FRONT_HOME_RADIUS \
				and mpos.distance_to(hall_pos) < FRONT_HOME_RADIUS:
			# Home and staying home: off the front, rest before re-deploy.
			u.erase("war_front")
			u["front_rest_until"] = day + FRONT_REST_DAYS
			continue
		n += 1
	return n


func _maintain_front(faction: String, enemy: String, key: String,
		hall_pos: Vector2) -> void:
	var day := int(_gs.day_number)
	var front: Dictionary = _war_fronts.get(key, {})
	if front.is_empty():
		# War began outside a campaign (betrayal, backchannel, old save) —
		# adopt marked survivors, or commit a first wave so the war marches.
		var marked := _front_marked_raw(faction, key)
		var epos: Vector2 = _enemy_hall_of(enemy, faction).get(
			"position", Vector2.ZERO)
		front = {"target": enemy, "strength": marked, "pos": epos,
			"day": day, "warned": false, "reinf_day": 0}
		_war_fronts[key] = front
		if marked > 0:
			return  # adopted survivors; reinforcement runs next think
		if _is_advisor(faction):
			front["warned"] = true
			_gazette("ADVISER'S WARNING",
				"We are at war with the %s and no troops are committed. "
				% _fname(enemy) + "The advisers await your orders, sire.")
			return
		var sent: int = _send_front_wave(faction, key,
			front.get("pos", Vector2.ZERO), hall_pos, FRONT_FIRST_WAVE)
		front["strength"] = sent
		if sent > 0:
			_commander_says(faction, hall_pos,
				"To war! For the %s!" % _fname(faction))
		return
	var strength := int(front.get("strength", 0))
	var committed := _front_committed(faction, key, hall_pos)
	if strength <= 0:
		front["strength"] = committed
		strength = committed
	if strength <= 0:
		return
	if committed >= int(float(strength) * FRONT_REINF_RATIO):
		return  # front holds; no replacements needed
	if _is_advisor(faction):
		# Sovereignty: advisers warn, Jeremy commands.
		if not bool(front.get("warned", false)):
			front["warned"] = true
			_gazette("ADVISER'S WARNING",
				"Our front against the %s falters — %d of %d troops still "
				% [_fname(enemy), committed, strength] + "stand. The "
				+ "advisers recommend reinforcements, sire.")
		return
	if _front_home_threatened(faction, hall_pos):
		return  # home under attack: defense first, no reinforcements
	var wave := mini(strength - committed, FRONT_WAVE_MAX)
	if _faction_exhausted(faction):
		# Lane 2: exhausted armies fight worse — half-strength pushes.
		wave = maxi(1, wave / 2)
	var sent: int = _send_front_wave(faction, key,
		front.get("pos", Vector2.ZERO), hall_pos, wave)
	if sent > 0 and int(front.get("reinf_day", 0)) != day:
		front["reinf_day"] = day
		_gazette("REINFORCEMENTS",
			"The %s send %d fresh troops to the %s front — the war "
			% [_fname(faction), sent, _fname(enemy)] + "grinds on.")


## Physical home threat only (unlike _threat_level, the at-war baseline does
## not count — every front would otherwise read as "under attack" forever).
func _front_home_threatened(faction: String, hall_pos: Vector2) -> bool:
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if bool(u.get("downed", false)):
			continue
		var uf: String = String(u.get("faction", ""))
		if uf == faction:
			continue
		var d: float = hall_pos.distance_to(u.get("position", Vector2.ZERO))
		if d < 280.0:
			return true  # HTML cityUnderAttack: foreign unit at the hall
		if d < 1500.0 and _is_hostile_force(faction, uf, u):
			return true
	return false


## Raw marked-troop count (no rest processing) — used when adopting a front
## the strike didn't record (loaded save, betrayal war already marching).
func _front_marked_raw(faction: String, key: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("war_front", "")) != key:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		n += 1
	return n


## Send up to n uncommitted troops to a front. Never strips the home guard:
## the nearest home_keep troops inside FRONT_HOME_RADIUS stay put.
func _send_front_wave(faction: String, key: String, fpos: Vector2,
		hall_pos: Vector2, n: int) -> int:
	if n <= 0:
		return 0
	var day := int(_gs.day_number)
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		if u.has("deploy_target_id") or u.has("monastery_march") \
				or u.has("monastery_guard") or u.has("post_march") \
				or u.has("post_guard") or u.has("counter_raid"):
			continue
		if String(u.get("war_front", "")) != "":
			continue
		if bool(u.get("withdrawing", false)):
			continue
		if day < int(u.get("front_rest_until", 0)):
			continue
		cands.append(u)
	if cands.is_empty():
		return 0
	# Home guard: nearest home_keep uncommitted troops near the hall stay.
	var near_home: Array = []
	for u: Dictionary in cands:
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		if upos.distance_to(hall_pos) < FRONT_HOME_RADIUS:
			near_home.append(u)
	near_home.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Vector2 = a.get("position", Vector2.ZERO)
		var pb: Vector2 = b.get("position", Vector2.ZERO)
		return pa.distance_squared_to(hall_pos) \
			< pb.distance_squared_to(hall_pos))
	var army_size := _army_of(faction).size()
	var keep := mini(near_home.size(), maxi(2, int(army_size * 0.4)))
	var keep_ids := {}
	for i: int in range(keep):
		keep_ids[int((near_home[i] as Dictionary).get("id", -1))] = true
	var sent := 0
	for u: Dictionary in cands:
		if sent >= n:
			break
		if keep_ids.has(int(u.get("id", -1))):
			continue
		u["defend_mode"] = false
		u["war_front"] = key
		u["move_target"] = fpos + Vector2(
			randf_range(-80.0, 80.0), randf_range(-80.0, 80.0))
		sent += 1
	return sent


## The war is over (peace, or the enemy is gone): every committed troop is
## unmarked and marches home. Player-ordered and withdrawing troops are
## left alone — their own orders win.
func _stand_down_front(faction: String, enemy: String, key: String,
		hall_pos: Vector2) -> void:
	if not _war_fronts.has(key):
		return
	var day := int(_gs.day_number)
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if String(u.get("war_front", "")) != key:
			continue
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			u.erase("war_front")
			continue
		if bool(u.get("withdrawing", false)):
			continue  # the retreat resolves itself on arrival
		u.erase("war_front")
		u.erase("deploy_target_id")
		u.erase("deploy_target_kind")
		u["defend_mode"] = false
		u["move_target"] = hall_pos + Vector2(
			randf_range(-120.0, 120.0), randf_range(-120.0, 120.0))
		u["front_rest_until"] = day + 2
	_war_fronts.erase(key)


## Nearest living hall of a faction (strike target), measured from the
## attacker's hall so the march hits the closest front.
func _enemy_hall_of(target: String, from_faction: String) -> Dictionary:
	var mine := _hall(from_faction)
	var mpos: Vector2 = mine.get("position", Vector2.ZERO)
	var best := {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != target:
			continue
		if not String(b.get("type", "")) in ["town_hall", "hall"]:
			continue
		var d: float = mpos.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	return best


## Monasteries held by the strike target (wartime steal targets).
func _enemy_monasteries(faction: String, target: String) -> Array:
	var out := []
	var mons = _gs.get("monasteries")
	if mons == null:
		return out
	for m: Dictionary in mons.monasteries:
		if String(m.get("owner", "")) == target:
			out.append(m)
	return out


## The advisers warn Jeremy on the phone when a buildup targets him —
## wars should never feel random.
func _warn_player_of_buildup(faction: String) -> void:
	_gazette("SHADOW OF WAR",
		"Scouts report the %s are massing troops. " % _fname(faction)
		+ "Your war advisers urge you to arm the walls.")
	var fl = _gs.get("faction_leaders")
	if fl != null and fl.has_method("message_player"):
		fl.message_player(_gs.player_faction,
			"The %s are massing troops against us! To the walls!"
			% _fname(faction))


## Seed a war rumor through hearsay (guarded: phone_sys may be null in
## bare tests).
func _seed_war_rumor(text: String) -> void:
	var ps = _gs.get("phone_sys")
	if ps == null:
		return
	var hs = ps.get("hearsay")
	if hs == null or not hs.has_method("seed_rumor"):
		return
	hs.seed_rumor(text, "war")


## --- Buildup bias: the war effort trains harder ---------------------------------

## Authorize/clear the military buildup bias (major_buildup proposals and
## war campaigns set it; it expires on its own).
func set_buildup_bias(faction: String, on: bool) -> void:
	if on:
		_buildup_bias[faction] = int(_gs.day_number)
	else:
		_buildup_bias.erase(faction)


func _has_buildup_bias(faction: String) -> bool:
	if not _buildup_bias.has(faction):
		return false
	if int(_gs.day_number) - int(_buildup_bias[faction]) > 15:
		_buildup_bias.erase(faction)
		return false
	return true


## --- Settlement founding via the proposal protocol -------------------------------

## Execute an approved expand_territory proposal: found the settlement.
## Called by SimProposals; also a public hook for tests.
func found_settlement_at(faction: String, pos: Vector2) -> Dictionary:
	var nb := _place(faction, "town_hall", -1, pos,
		"Your advisers are founding a new settlement.")
	if not nb.is_empty():
		_settle_last[faction] = _gs.game_time
	return nb


## --- Maneuver execution -------------------------------------------------------

func _maneuver(faction: String, hall: Dictionary, st: Dictionary) -> void:
	var maneuver: String = String(st["maneuver"])
	# Jeremy 2026-10-04: faction leader directives override the AI's
	# chosen maneuver (player commands to allied/vassal leaders).
	var fl = _gs.get("faction_leaders")
	if fl != null:
		var directive: String = fl.get_directive(faction)
		if directive != "":
			var override: String = SimFactionLeaders.maneuver_for_directive(directive)
			if override != "":
				maneuver = override
	if maneuver == "defend":
		# Jeremy 2026-10-05: defense rides along with retaliation — while
		# the muster holds the walls, a fast force may punch back at an
		# undefended attacker home (counter-raid doctrine, below).
		_counter_raid(faction, st)
		return  # the rest of defense is handled by _muster_defense above
	if maneuver == "raid":
		_raid_march(faction, st)
	elif maneuver == "eco_war":
		_contest_mines(faction, st)
	elif maneuver == "monastery":
		# Jeremy 2026-10-04: monastery priority — coordinated assault march.
		_monastery_assault_march(faction, st)
	else:
		_garrison(faction, st)


## Planned AI road networks (Jeremy 2026-10-10 direct order, item 1): the
## AI lays deliberate building-to-building road networks instead of only
## the incidental trails roadbuilders paint walking to the hall. Town
## halls link to each other (trunk) and to key buildings (farm, lumber
## camp, oil pump, shop, barracks, fire station, sawmill, mine, fishing
## dock); roadbuilder crews walk the planned polylines and paint them
## (WorkerAI.plan_road_link / _pick_road_order / _do_roadwork). A fresh
## batch is planned only when the crew finished the last one. Player
## faction excluded — the player keeps manual control of their own roads
## (advisor mode / sovereignty).
const ROAD_LINK_BUILDINGS := ["farm", "lumber_camp", "oil_pump", "shop",
	"barracks", "fire_station", "sawmill", "mine", "fishing_dock"]
const ROAD_LINK_DIRECTOR_RANGE := 1400.0
const ROAD_LINK_PER_THINK := 4
var _road_note_day := {}  # faction -> day of last roadworks gazette note


func _road_networks(faction: String) -> void:
	if _is_advisor(faction):
		return  # player keeps manual control of their own roads
	var wai: WorkerAI = _gs.get("worker_ai")
	if wai == null:
		return
	if wai.undone_link_count(faction) > 0:
		return  # crew is still walking the last plan
	wai.prune_stale_links(faction)  # re-plan abandoned plans
	var halls: Array = []
	var spokes: Array = []
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)) \
				or not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var t := String(b.get("type", ""))
		var p: Vector2 = b.get("position", Vector2.ZERO)
		if t == "town_hall" or t == "hall":
			halls.append(p)
		elif t in ROAD_LINK_BUILDINGS:
			spokes.append(p)
	if halls.is_empty():
		return
	var planned := 0
	# Trunk links first: town hall <-> town hall is the network backbone.
	for i in halls.size():
		for j in range(i + 1, halls.size()):
			if planned >= ROAD_LINK_PER_THINK:
				break
			var a: Vector2 = halls[i]
			var c: Vector2 = halls[j]
			if a.distance_to(c) > ROAD_LINK_DIRECTOR_RANGE:
				continue
			if wai.plan_road_link(faction, a, c) > 0:
				planned += 1
	# Spokes: hall <-> key building, nearest first.
	var cands: Array = []
	for h: Vector2 in halls:
		for sp: Vector2 in spokes:
			var d: float = h.distance_to(sp)
			if d < 60.0 or d > ROAD_LINK_DIRECTOR_RANGE:
				continue
			cands.append([d, h, sp])
	cands.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	for cd: Array in cands:
		if planned >= ROAD_LINK_PER_THINK:
			break
		if wai.plan_road_link(faction, cd[1], cd[2]) > 0:
			planned += 1
	if planned > 0:
		var day := int(_gs.day_number)
		if int(_road_note_day.get(faction, -99)) != day:
			_road_note_day[faction] = day
			_gazette("ROYAL ROADWORKS",
				"The %s are laying planned roads between their towns and workshops."
				% _fname(faction),
				"news")


## Jeremy 2026-10-06: Battlefront — the AI plays ALL command posts (towns,
## monasteries, dark crystals) the Star Wars Battlefront way: reinforce own
## threatened posts with proportional help, claim unclaimed ones with small
## parties (no proposal needed), and assault enemy-held ones in wartime via
## the proposal protocol. One unified pass replaces the separate monastery
## and crystal seeks; VALUE weights keep monasteries the top war priority.
func _seek_command_posts(faction: String, st: Dictionary) -> void:
	var posts := _command_post_list()
	var hall_pos: Vector2 = st.get("hall_pos", Vector2.ZERO)
	# 1) Reinforce: every OWN post with enemies nearby gets help scaled to
	# the threat (monastery logic from 2026-10-04, extended to towns and
	# crystals): ceil(foes*1.3)+2 reinforcements, capped at 12. Posts are
	# guarded in VALUE order — monasteries first, so the top war priority
	# gets first claim on the troop pool.
	var guard_posts: Array = []
	for p: Dictionary in posts:
		if String(p.get("holder", "")) == faction:
			guard_posts.append(p)
	guard_posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(SimCommandPosts.VALUE.get(
			String(a.get("kind", "")), 0.0)) > float(
				SimCommandPosts.VALUE.get(String(b.get("kind", "")), 0.0)))
	for p: Dictionary in guard_posts:
		var ppos: Vector2 = p.get("position", Vector2.ZERO)
		var foes := _enemy_military_near(ppos, REINFORCE_RADIUS, faction)
		if foes <= 0:
			continue
		var want := mini(12, int(ceil(foes * 1.3)) + 2)
		var sent := _send_post_force(faction, st, p, want, true)
		if sent > 0 and randf() < 0.10:
			_commander_says(faction, ppos,
				"Hold the %s! Reinforcements march!" % String(p.get(
					"name", "post")))
	# 2) Offense: the best capturable post by Battlefront score.
	var target: Dictionary = _best_post_target(faction, posts, hall_pos)
	if not target.is_empty():
		var owner: String = String(target.get("holder", ""))
		if owner == "":
			# Unclaimed: a claim party, no proposal needed.
			_send_post_force(faction, st, target, POST_CLAIM_PARTY, false)
		elif _at_war_with(faction, owner):
			# Held by a war enemy: coordinated assault via the proposal
			# protocol (player faction gets the phone modal; AI auto-resolves).
			_propose_post_assault(faction, target)
	# 3) Expiry: assault marches end when the post is held/taken; guards end
	# when the post is lost; overridden orders are re-issued so assaults
	# stay sticky across thinks.
	_refresh_post_marches(faction, st)


## Jeremy 2026-10-04: Seven Monasteries — the AI understands sanctuaries.
## Monastery conquest is the central strategic goal (power = ruling the
## land): own threatened monasteries get proportional reinforcements,
## unclaimed ones get claim parties, and enemy-held ones (wartime) get
## proposal-gated COORDINATED assaults scaled to the defender's strength.
## (2026-10-06: now handled by the unified command-post pass below; kept
## for callers and tests.)
func _seek_monasteries(faction: String, st: Dictionary) -> void:
	_seek_command_posts(faction, st)


## All command posts on the map: the wired SimCommandPosts model when
## available, else the same shape built live from the sim systems (bare
## tests and old saves that never wired command_posts).
func _command_post_list() -> Array:
	var cps = _gs.get("command_posts")
	if cps != null and cps.has_method("posts_of"):
		return cps.posts_of()
	var out: Array = []
	# Towns: completed, alive halls.
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if not String(b.get("type", "")) in SimTerritory.CLAIM_TYPES:
			continue
		out.append({
			"kind": "town",
			"id": int(b.get("id", 0)),
			"position": b.get("position", Vector2.ZERO),
			"holder": String(b.get("faction", "")),
			"name": str(b.get("town_name", b.get("name", "Town"))),
			"radius": SimCommandPosts.TOWN_R,
		})
	# Monasteries.
	var mons = _gs.get("monasteries")
	if mons != null:
		for m: Dictionary in mons.monasteries:
			out.append({
				"kind": "monastery",
				"id": int(m.get("id", 0)),
				"position": m.get("position", Vector2.ZERO),
				"holder": String(m.get("owner", "")),
				"name": String(m.get("name", "Monastery")),
				"radius": SimCommandPosts.MONASTERY_R,
			})
	# Dark crystals.
	var crys = _gs.get("crystals")
	if crys != null:
		for c: Dictionary in crys.crystals:
			out.append({
				"kind": "crystal",
				"id": int(c.get("id", 0)),
				"position": c.get("position", Vector2.ZERO),
				"holder": String(c.get("owner", "")),
				"name": String(c.get("name", "Dark Crystal")),
				"radius": SimCommandPosts.CRYSTAL_R,
			})
	return out


## Best post for a faction to march on: unowned monasteries/crystals (claim
## parties) or war-enemy-held posts of ANY type (assaults). Score =
## VALUE[kind] x strategic weight / distance — monasteries win by value,
## unclaimed posts win by weight, and distance breaks ties. Towns are
## always owned, so only war-enemy towns are valid assault targets.
func _best_post_target(faction: String, posts: Array,
		hall_pos: Vector2) -> Dictionary:
	var best := {}
	var best_score := 0.0
	for p: Dictionary in posts:
		var kind: String = String(p.get("kind", ""))
		var holder: String = String(p.get("holder", ""))
		if holder == faction:
			continue
		var weight := 0.0
		if holder == "":
			if kind == "town":
				continue  # towns are always owned
			weight = POST_CLAIM_WEIGHT
		elif _at_war_with(faction, holder):
			weight = POST_WAR_WEIGHT
		else:
			continue  # peacetime: not ours to take
		var value: float = float(SimCommandPosts.VALUE.get(kind, 1.0))
		var d: float = maxf(hall_pos.distance_to(
			p.get("position", Vector2.ZERO)), 200.0)
		var score: float = value * weight / d
		if score > best_score:
			best_score = score
			best = p
	return best


## Find a post by kind+id (kinds have separate id namespaces).
func _find_post(posts: Array, kind: String, pid: int) -> Dictionary:
	for p: Dictionary in posts:
		if String(p.get("kind", "")) == kind \
				and int(p.get("id", 0)) == pid:
			return p
	return {}


## Send up to `count` idle military to a command post. Assault/claim troops
## are marked post_march; garrison reinforcements are marked post_guard
## (separate marks so the expiry logic can tell a guard rotation — target
## already ours — from an assault — target not ours). Marks are {kind, id}
## dicts since post id namespaces are per-kind. Legacy monastery/crystal
## marks are set in parallel so the old flows (tests, army.gd, expiry) keep
## working. Returns troops sent.
func _send_post_force(faction: String, st: Dictionary, post: Dictionary,
		count: int, guard: bool = false) -> int:
	var kind: String = String(post.get("kind", "monastery"))
	var pid := int(post.get("id", 0))
	var ppos: Vector2 = post.get("position", Vector2.ZERO)
	var sent := 0
	for u: Dictionary in st["army"]:
		if sent >= count:
			break
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		if u.has("deploy_target_id"):
			continue
		# Town guards never steal the muster's troops: the city muster owns
		# town defense, and flipping defend_mode off would gut it.
		# Monastery/crystal guards keep the old pull-anyone behavior.
		if guard and kind == "town" and bool(u.get("defend_mode", false)):
			continue
		# Don't pull troops already marching on an objective.
		if u.has("monastery_march") or u.has("monastery_guard") \
				or u.has("post_march") or u.has("post_guard"):
			continue
		u["defend_mode"] = false
		u["move_target"] = ppos + Vector2(
			randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
		if guard:
			u["post_guard"] = {"kind": kind, "id": pid}
		else:
			u["post_march"] = {"kind": kind, "id": pid}
		# Legacy marks: monasteries keep monastery_march/monastery_guard,
		# crystals keep crystal_march (assaults only; they never had guards).
		if kind == "monastery":
			u["monastery_guard" if guard else "monastery_march"] = pid
		elif kind == "crystal" and not guard:
			u["crystal_march"] = pid
		sent += 1
	return sent


## Send up to `count` idle military to a monastery. Kept for the old
## callers and tests; delegates to the unified post-force sender.
func _send_monastery_force(faction: String, st: Dictionary, mpos: Vector2,
		count: int, mid: int, guard: bool = false) -> int:
	return _send_post_force(faction, st,
		{"kind": "monastery", "id": mid, "position": mpos}, count, guard)


## Assault march orders expire once the post is held or taken; guard
## rotations expire when we LOSE the post. Orders that got overridden
## (muster pulled the troops home) are re-issued so assaults stay sticky
## across thinks. Handles the unified post_march/post_guard marks and the
## legacy monastery/crystal marks (kept in parallel).
func _refresh_post_marches(faction: String, st: Dictionary) -> void:
	var posts := _command_post_list()
	for u: Dictionary in st["army"]:
		var marks: Array = []
		for lm in ["monastery_march", "monastery_guard"]:
			if u.has(lm):
				marks.append([lm, "monastery", int(u[lm]),
					lm.ends_with("guard")])
		if u.has("crystal_march"):
			marks.append(["crystal_march", "crystal",
				int(u["crystal_march"]), false])
		if u.has("post_march"):
			var pm := u["post_march"] as Dictionary
			marks.append(["post_march", String(pm.get("kind", "")),
				int(pm.get("id", -1)), false])
		if u.has("post_guard"):
			var pg := u["post_guard"] as Dictionary
			marks.append(["post_guard", String(pg.get("kind", "")),
				int(pg.get("id", -1)), true])
		for mk: Array in marks:
			var mkey: String = String(mk[0])
			var post := _find_post(posts, String(mk[1]), int(mk[2]))
			if _post_march_done(post, faction, bool(mk[3])):
				u.erase(mkey)
				continue
			var ppos: Vector2 = post.get("position", Vector2.ZERO)
			var cur: Vector2 = u.get("move_target", u.get("position",
				Vector2.ZERO))
			if cur.distance_to(ppos) > 500.0:
				u["move_target"] = ppos + Vector2(
					randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))


## True when a march mark has run its course: assault/claim marks expire
## once WE hold the post; guard marks expire when we LOSE it (or the post
## no longer exists).
func _post_march_done(post: Dictionary, faction: String,
		is_guard: bool) -> bool:
	if post.is_empty():
		return true
	var holder: String = String(post.get("holder", ""))
	if is_guard:
		return holder != faction
	return holder == faction


## Kept for the old callers; the unified refresh handles all post types.
func _refresh_monastery_marches(faction: String, st: Dictionary,
		mons) -> void:
	_refresh_post_marches(faction, st)


## The "monastery" maneuver: march on the best command post with a real
## force. Unclaimed posts get claim parties; war-held ones go through the
## proposal-gated coordinated assault. (Name kept for directive mapping;
## the target is now any post type.)
func _monastery_assault_march(faction: String, st: Dictionary) -> void:
	var hall_pos: Vector2 = st.get("hall_pos", Vector2.ZERO)
	var target: Dictionary = _best_post_target(faction,
		_command_post_list(), hall_pos)
	if target.is_empty():
		return
	var holder: String = String(target.get("holder", ""))
	if holder == "":
		_send_post_force(faction, st, target, 6, false)
	elif _at_war_with(faction, holder):
		_propose_post_assault(faction, target)


## True when a command post is worth prioritizing above routine expansion:
## the faction fields a real army and there's an unclaimed post in reach
## or a war enemy's post to take. (Monasteries stay first via VALUE.)
func _monastery_opportunity(faction: String, hall_pos: Vector2,
		army_size: int) -> bool:
	return _post_opportunity(faction, hall_pos, army_size)


func _post_opportunity(faction: String, hall_pos: Vector2,
		army_size: int) -> bool:
	if army_size < MONASTERY_PRIORITY_ARMY:
		return false
	for p: Dictionary in _command_post_list():
		var holder: String = String(p.get("holder", ""))
		if holder == faction:
			continue
		var kind: String = String(p.get("kind", ""))
		var ppos: Vector2 = p.get("position", Vector2.ZERO)
		if holder == "":
			if kind == "town":
				continue  # towns are always owned
			if hall_pos.distance_to(ppos) < MONASTERY_REACH:
				return true
		elif _at_war_with(faction, holder):
			return true
	return false


## Proposal-gated coordinated assault on a war-held command post. One ask
## per post per day; the proposal protocol auto-resolves for AI factions
## and asks the player on the phone for the player faction. Monasteries
## keep the legacy monastery_assault kind; other posts use the generic
## command_post_assault kind.
func _propose_post_assault(faction: String, post: Dictionary) -> void:
	var kind: String = String(post.get("kind", ""))
	var pid := int(post.get("id", -1))
	if pid < 0:
		return
	var key := "%s|%s|%d" % [faction, kind, pid]
	var day := int(_gs.day_number)
	if day - int(_assault_proposed.get(key, -99)) < 1:
		return
	if _army_of(faction).size() < ASSAULT_MIN_ARMY:
		return
	_assault_proposed[key] = day
	var props = _gs.get("proposals")
	if props == null:
		_launch_post_assault(faction, post)
		return
	if kind == "monastery":
		props.propose(faction, SimProposals.KIND_MONASTERY_ASSAULT,
			{"monastery_id": pid})
	else:
		props.propose(faction, SimProposals.KIND_POST_ASSAULT,
			{"post_kind": kind, "post_id": pid,
				"post_name": String(post.get("name", "post")),
				"post_holder": String(post.get("holder", ""))})


## Kept for the old callers (monastery dicts from SimMonasteries).
func _propose_assault(faction: String, target: Dictionary) -> void:
	_propose_post_assault(faction, {
		"kind": "monastery", "id": int(target.get("id", -1)),
		"position": target.get("position", Vector2.ZERO),
		"holder": String(target.get("owner", "")),
		"name": String(target.get("name", "monastery"))})


## Execute an approved command-post assault: march a force scaled to the
## defender's strength near the post. Called by SimProposals on approval;
## also a public hook for tests.
func launch_post_assault(faction: String, kind: String, pid: int) -> int:
	if kind == "monastery":
		return launch_monastery_assault(faction, pid)
	return _launch_post_assault(faction,
		_find_post(_command_post_list(), kind, pid))


## Execute an approved monastery assault. Called by SimProposals on
## approval; also a public hook for tests.
func launch_monastery_assault(faction: String, mid: int) -> int:
	var mons = _gs.get("monasteries")
	if mons == null or not mons.has_method("get_monastery"):
		return 0
	var m: Dictionary = mons.get_monastery(mid)
	if m.is_empty():
		return 0
	return _launch_post_assault(faction, {
		"kind": "monastery", "id": mid,
		"position": m.get("position", Vector2.ZERO),
		"holder": String(m.get("owner", "")),
		"name": String(m.get("name", "Monastery"))})


## Core assault launch: march a force scaled to the defender's strength
## near the post (not the old 3-troop dribble).
func _launch_post_assault(faction: String, post: Dictionary) -> int:
	if post.is_empty():
		return 0
	var kind: String = String(post.get("kind", ""))
	if String(post.get("holder", "")) == faction:
		return 0
	var ppos: Vector2 = post.get("position", Vector2.ZERO)
	var pname := String(post.get("name", "post"))
	var defenders := _enemy_military_near(ppos, REINFORCE_RADIUS, faction)
	var force := mini(ASSAULT_FORCE_MAX,
		maxi(ASSAULT_MIN_ARMY, int(ceil(defenders * 1.6)) + 3))
	var st := {"army": _army_of(faction)}
	var sent := _send_post_force(faction, st, post, force, false)
	if sent > 0:
		var kind_label := String({"monastery": "MONASTERY",
			"crystal": "CRYSTAL", "town": "TOWN"}.get(kind, "POST"))
		_gazette("%s ASSAULT" % kind_label,
			"The %s march on the %s with %d troops — %s! Power is ruling "
			% [_fname(faction), pname, sent,
				"the land, and they mean to rule it"])
		_commander_says(faction, ppos,
			"Take the %s! For our gods!" % pname)
	return sent


## Enemy military units within radius of a position (not our faction).
func _enemy_military_near(pos: Vector2, radius: float,
		faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) == faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if pos.distance_to(u.get("position", Vector2.ZERO)) < radius:
			n += 1
	return n


## True when this faction is at war with the other faction.
func _at_war_with(faction: String, other: String) -> bool:
	if _gs.diplomacy == null:
		return false
	return _gs.diplomacy.relation_state(faction, other) == "war"


## Jeremy 2026-10-04: Seven Dark Crystals — the AI understands the dark
## crystals too. (2026-10-06: now handled by the unified command-post
## pass — claim parties, proportional guard reinforcements, and
## proposal-gated wartime assaults; kept for callers and tests.)
func _seek_crystals(faction: String, st: Dictionary) -> void:
	_seek_command_posts(faction, st)


## Raid: march idle troops at the nearest enemy hall in loose formation.
func _raid_march(faction: String, st: Dictionary) -> void:
	var target: Dictionary = st["nearest_enemy_hall"]
	if target.is_empty():
		return
	var tpos: Vector2 = target.get("position", Vector2.ZERO)
	var n := 0
	for u: Dictionary in st["army"]:
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		if u.has("deploy_target_id"):
			continue
		# Jeremy 2026-10-04: troops on monastery duty (incl. strike
		# detachments) stay on their objective — the raid muster must not
		# recall a coordinated assault. (2026-10-06: all post duty.)
		if u.has("monastery_march") or u.has("monastery_guard") \
				or u.has("post_march") or u.has("post_guard"):
			continue
		u["defend_mode"] = false
		var uid := int(u.get("id", 0))
		var off := Vector2(float(uid % 8) * 18.0, float((uid / 8) % 4) * 16.0)
		u["move_target"] = tpos + off
		n += 1
	if n > 0 and randf() < 0.08:
		_commander_says(faction, st["hall_pos"],
			"Form ranks — take their base!")


## --- Counter-raid retaliation doctrine (Jeremy 2026-10-05) -------------------
##
## Deliberate improvement over the HTML build (which never did this): when a
## faction is UNDER ATTACK and the attacker's army is committed far from
## THEIR home, a smart commander punishes the over-commitment — a small fast
## force slips past the assault and hits the attacker's now-undefended hall.
## Classic RTS counter-punch; the "retaliate" half of the war/peace checklist.
##
## Rules:
##   - Only while under_attack AND at war with the hall's owner.
##   - Only when the enemy home guard is weak (<= COUNTER_RAID_HOME_GUARD):
##     their army is away, the door is open.
##   - Only from SURPLUS troops (army keeps need_army home for the defense);
##     at most COUNTER_RAID_SIZE raiders, at least COUNTER_RAID_MIN.
##   - Raiders are flagged counter_raid = {pos, enemy, deployed}: the muster
##     (above) and garrison skip them mid-flight; the flag clears on arrival
##     (< 450px of the target), on peace, or if they start withdrawing.
##   - Raiders get deployed_for_war so combat's building-seek treats them
##     like a war deployment (they smash the town, not just its defenders).
##   - One launch per faction per day (throttled); Gazette on launch.
##   - Player faction (advisor mode): the adviser warns on the phone about
##     the opening but NEVER launches the raid unilaterally (sovereignty —
##     same pattern as the famine response).

const COUNTER_RAID_SIZE := 4          # max raiders detached per launch
const COUNTER_RAID_MIN := 3           # min viable raiding force
const COUNTER_RAID_HOME_GUARD := 3    # enemy home this weak (or weaker) = open door
const COUNTER_RAID_HOME_R := 700.0   # home-guard scan radius around enemy hall
const COUNTER_RAID_ARRIVE_R := 450.0 # arrival clears the raid flag

var _counter_raid_day := {}  # faction -> day of last launch/warning


## Enemy military strength at home: fighters of `foe` within
## COUNTER_RAID_HOME_R of their hall. Low = their army is away.
func _enemy_home_guard(foe: String, foe_hall_pos: Vector2) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != foe:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if (u.get("position", Vector2.ZERO) as Vector2) \
				.distance_to(foe_hall_pos) < COUNTER_RAID_HOME_R:
			n += 1
	return n


## Clear finished counter-raids: arrived, peace signed, or withdrawing.
func _clear_finished_raids(faction: String) -> void:
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not u.has("counter_raid"):
			continue
		var cr: Dictionary = u["counter_raid"]
		var done := bool(u.get("withdrawing", false))
		if not done and not _at_war_with(faction, String(cr.get("enemy", ""))):
			done = true  # peace — the raid stands down
		if not done:
			var tpos: Vector2 = cr.get("pos", Vector2.INF)
			if tpos != Vector2.INF and (u.get("position", Vector2.ZERO) \
					as Vector2).distance_to(tpos) < COUNTER_RAID_ARRIVE_R:
				done = true  # arrived — combat's building-seek takes over
		if done:
			u.erase("counter_raid")
			if bool(cr.get("deployed", false)):
				u.erase("deployed_for_war")


func _counter_raid(faction: String, st: Dictionary) -> void:
	if not bool(st.get("under_attack", false)):
		return
	if not bool(st.get("at_war", false)):
		return
	var foe: String = String(st.get("war_enemy", ""))
	if foe == "":
		return
	var foe_hall: Dictionary = st.get("nearest_enemy_hall", {})
	if foe_hall.is_empty():
		return
	# The door must be open: their army is away, home guard weak.
	var foe_pos: Vector2 = foe_hall.get("position", Vector2.ZERO)
	if _enemy_home_guard(foe, foe_pos) > COUNTER_RAID_HOME_GUARD:
		return
	var army: Array = st.get("army", [])
	var need_army: float = float(st.get("need_army", 10.0))
	# Effective field strength — downed/withdrawing troops can't raid.
	var field: Array = []
	for u: Dictionary in army:
		if bool(u.get("alive", false)) \
				and not bool(u.get("downed", false)) \
				and not bool(u.get("withdrawing", false)):
			field.append(u)
	if float(field.size()) < need_army + float(COUNTER_RAID_MIN):
		return  # no surplus — every blade stays on the walls
	var day := int(_gs.day_number)
	# Advisor mode: warn Jeremy about the opening; never launch for him.
	if _is_advisor(faction):
		if int(_counter_raid_day.get(faction, -99)) != day:
			_counter_raid_day[faction] = day
			var fl = _gs.get("faction_leaders")
			if fl != null and fl.has_method("message_player"):
				fl.message_player(_gs.player_faction,
					"My liege — the %s march on us, but their home lies all but undefended! "
					% _fname(foe)
					+ "Send a fast force to their hall and burn it while their army is here. "
					+ "Say the word and I'll muster the riders.")
		return
	if int(_counter_raid_day.get(faction, -99)) == day:
		return  # one launch per day
	var draft := mini(COUNTER_RAID_SIZE,
		int(float(field.size()) - need_army))
	if draft < COUNTER_RAID_MIN:
		return
	var n := 0
	var drafted: Array = []
	for u: Dictionary in field:
		if n >= draft:
			break
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		if u.has("deploy_target_id") or u.has("counter_raid"):
			continue
		# Never gut an in-flight coordinated assault (post duty of any kind).
		if u.has("monastery_march") or u.has("monastery_guard") \
				or u.has("post_march") or u.has("post_guard"):
			continue
		u["defend_mode"] = false
		var set_deployed := false
		if not bool(u.get("deployed_for_war", false)):
			u["deployed_for_war"] = true
			set_deployed = true
		var uid := int(u.get("id", 0))
		var off := Vector2(float(uid % 8) * 18.0,
			float((uid / 8) % 4) * 16.0)
		u["move_target"] = foe_pos + off
		u["counter_raid"] = {"pos": foe_pos, "enemy": foe,
			"deployed": set_deployed}
		drafted.append(u)
		n += 1
	if n < COUNTER_RAID_MIN:
		# Draft fell short — stand only THIS call's would-be raiders back
		# down (older en-route raids keep their flags).
		for u: Dictionary in drafted:
			var cr: Dictionary = u["counter_raid"]
			u.erase("counter_raid")
			if bool(cr.get("deployed", false)):
				u.erase("deployed_for_war")
			u.erase("move_target")
		return
	_counter_raid_day[faction] = day
	_gazette("COUNTER-RAID!",
		"The %s answer the assault in kind — raiders slip past the invaders, "
		% _fname(faction)
		+ "bound for the all-but-undefended %s hall!" % _fname(foe))
	_commander_says(faction, st.get("hall_pos", Vector2.ZERO),
		"They left their home bare — burn it down!")


## Eco-war: contest the nearest contested gold vein with troops + workers.
func _contest_mines(faction: String, st: Dictionary) -> void:
	var hall_pos: Vector2 = st["hall_pos"]
	var best := {}
	var best_d := INF
	for s: Dictionary in _gs.work_sites:
		if String(s.get("kind", "")) != "gold_vein":
			continue
		if float(s.get("amount", 0.0)) <= 0.0:
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		var d: float = hall_pos.distance_to(sp)
		if d < 1000.0 and d < best_d:
			best_d = d
			best = s
	if best.is_empty():
		return
	var spot: Vector2 = best.get("position", Vector2.ZERO)
	var troops := 0
	for u: Dictionary in st["army"]:
		if troops >= 6:
			break
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		u["move_target"] = spot
		troops += 1
	var hands := 0
	for w: Dictionary in st["workers"]:
		if hands >= 4:
			break
		w["move_target"] = spot
		hands += 1


## Peacetime garrison: idle military holds inside M-zone walls (star forts).
func _garrison(faction: String, st: Dictionary) -> void:
	var forts := []
	for z: Dictionary in _gs.zoning.zones_of("M", faction):
		forts.append(z)
	if forts.is_empty():
		return
	for u: Dictionary in st["army"]:
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue
		if u.has("deploy_target_id"):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		var in_fort := false
		for z: Dictionary in forts:
			var zp: Vector2 = z.get("position", Vector2.ZERO)
			if upos.distance_to(zp) < 96.0:
				in_fort = true
				break
		if in_fort:
			continue
		var z0: Dictionary = forts[int(u.get("id", 0)) % forts.size()]
		var zp0: Vector2 = z0.get("position", Vector2.ZERO)
		u["defend_mode"] = true
		u["move_target"] = zp0 + Vector2(randf_range(-40, 40), randf_range(-40, 40))


## --- AI construction drip (HTML: AI sites self-advance) -----------------------

func _ai_build_drip(faction: String) -> void:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)) or bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var prog := float(b.get("progress", 0.0)) + AI_BUILD_DRIP
		if prog >= 1.0:
			b["progress"] = 1.0
			b["complete"] = true
		else:
			b["progress"] = prog

## --- Strategic build queue (HTML aiBuildEssentials, verbatim priorities) -----

func _build_essentials(faction: String, hall: Dictionary, st: Dictionary) -> void:
	var hall_pos: Vector2 = st["hall_pos"]
	var town_id := int(hall.get("town_id", -1))
	var maneuver: String = String(st["maneuver"])
	var war_b: String = String(st["war_b"])
	var queue: Array = []
	var push := func(t: String, n: int) -> void:
		if t != "":
			queue.append([t, n])
	# Jeremy 2026-10-08: oil pumps FIRST — 4 per town, inside an industrial
	# zone. Pumps are the only oil source (no oil piles); securing income
	# before the queue's oil spenders (barracks, war buildings, AA towers,
	# medic camps) burn the starting stockpile with no way to replenish.
	# Ensure the town has an industrial zone first so the pumps produce.
	# Pumps ride outside the 2/think essentials budget (see the placed
	# counting below): they are income infrastructure, not construction
	# the budget paces.
	_ensure_industrial_zone(faction, hall_pos)
	push.call("oil_pump", 4)
	if maneuver == "defend" or maneuver == "fortify":
		push.call("barracks", maxi(2, int(st["barracks"]) + 1))
		push.call(war_b, 1)
		push.call("medic_camp", 2)
		push.call("aa_tower", 3)
		push.call("cannon_foundry", 1)
		# Jeremy 2026-10-10 (roads/vehicles P5): defending forts raise a
		# motor pool so the baggage train can roll with the garrison.
		push.call("vehicle_depot", 1)
		push.call("storage", 2)
	elif maneuver == "raid":
		push.call("barracks", 2)
		push.call(war_b, 1)
		push.call("cannon_foundry", 1)
		push.call("field_camp", 2)
		push.call("equip_camp", 1)
		push.call("medic_camp", 1)
	elif maneuver == "eco_war":
		push.call("storage", 3)
		push.call("camp", 6)
		push.call("cannon_foundry", 1)
		push.call("barracks", 1)
		push.call("house", int(st["houses"]) + int(st["housing_gap"]))
	else:  # expand
		push.call("house", maxi(2, int(st["houses"]) \
			+ mini(3, int(st["housing_gap"]))))
		push.call("storage", 2)
		push.call("restaurant", 1)
		push.call("barracks", 1)
		push.call(war_b, 1)
		push.call("clinic", 1)
		push.call("camp", 4)
		push.call("cannon_foundry", 1)
	# Always want basics.
	push.call("barracks", 1)
	push.call("storage", 1)
	push.call(war_b, 1)
	# Jeremy 2026-10-04: resource camps near work sites so gatherers
	# don't trek to town hall (HTML parity).
	push.call("resource_camp", 2)
	# Jeremy 2026-10-05: lumber camps (Rise of Nations style) — one per
	# town near the trees; woodcutters work the camp's coverage radius.
	push.call("lumber_camp", 1)
	# Extras (HTML order; per-town counts for smith/fire/hall).
	if _needs_more_housing(faction):
		queue.push_front(["house", _count_build(faction, "house") + 1])
	if _count_build(faction, "weaponsmith", town_id) < 1:
		queue.append(["weaponsmith", 1])
	if _count_build(faction, "fire_station", town_id) < 1:
		queue.append(["fire_station", 1])
	if _count_build(faction, "guild_hall", town_id) < 1:
		queue.append(["guild_hall", 1])
	if _count_build(faction, "clinic") < 1:
		queue.append(["clinic", 1])
	if _count_build(faction, "bathhouse") < 1:
		queue.append(["bathhouse", 1])
	if _count_build(faction, "inn") < 1:
		queue.append(["inn", 1])
	if _count_build(faction, "aa_tower") < 2:
		queue.append(["aa_tower", 2])
	var unfinished := 0
	for b: Dictionary in _gs.buildings:
		if bool(b.get("alive", false)) and not bool(b.get("complete", false)) \
				and String(b.get("faction", "")) == faction:
			unfinished += 1
	# Jeremy 2026-10-08: income infrastructure ignores the unfinished
	# pacing cap. Other think subsystems (maneuver, agri, air defenses)
	# can flood an early think with 8+ unfinished blueprints; the old
	# whole-phase early-return then starved the pump queue on every later
	# think — seed-probed at ~15% of fresh games placing a single pump in
	# 4 thinks while the 600 starting oil burned away with no income to
	# replace it. Pumps still place at most one per think and stop at the
	# queue want (4/town); everything else keeps the HTML pacing.
	var cap_open := unfinished < UNFINISHED_CAP
	var placed := 0
	for entry: Array in queue:
		var btype: String = String(entry[0])
		var want := int(entry[1])
		if not SimBuildings.is_building(btype):
			continue
		if btype != "oil_pump" and not cap_open:
			continue
		# Hard block: never place a house unless truly needed.
		if btype == "house" and not _needs_more_housing(faction):
			continue
		var have := _count_build(faction, btype)
		if btype in ["weaponsmith", "fire_station", "guild_hall", "oil_pump"]:
			have = _count_build(faction, btype, town_id)
		if have >= want:
			continue
		var spot := _queue_spot(faction, hall_pos, btype, war_b)
		# perf R20: skip spot validation + placement when the build is
		# unaffordable — validation walks every building up to 9 times and
		# the AI is frequently oil-broke. _queue_spot stays above so the
		# randf stream is untouched; _valid_spot/_place consume no randf.
		# Non-player factions only: the player's costs are policy-adjusted
		# (_cost_for), so the base-cost check could disagree there.
		if faction != _gs.player_faction and not _can_afford(faction, btype):
			continue
		# Jeremy 2026-10-07: oil triage. Pump oil trickles in slowly, and
		# the queue's lesser oil spenders (AA towers, medic camps — plus
		# the insatiable barracks want) spent every drop as it arrived, so
		# the faction could never save up for its CORE military buildings:
		# zero barracks, zero armies (Jeremy's 2026-10-07 report). Core
		# military comes first: until the first barracks stands, oil
		# spenders wait until the stock covers their cost AND the
		# barracks' cost; then the faction's elite war building gets the
		# same priority until ONE stands. (Placed after _queue_spot so
		# the randf stream is untouched.)
		var reserve_for := ""
		var reserve_cost := 0.0
		if _count_build(faction, "barracks") < 1:
			reserve_for = "barracks"
			reserve_cost = float(SimBuildings.BUILDINGS.get(
				"barracks", {}).get("costs", {}).get("oil", 100.0))
		elif war_b != "" and _count_build(faction, war_b) < 1:
			reserve_for = war_b
			reserve_cost = float(SimBuildings.BUILDINGS.get(
				war_b, {}).get("costs", {}).get("oil", 120.0))
		if reserve_for != "" and btype != reserve_for:
			var bcosts: Dictionary = SimBuildings.BUILDINGS.get(
				btype, {}).get("costs", {})
			var b_oil := float(bcosts.get("oil", 0.0))
			if b_oil > 0.0 and _gs.resources.get_amount(faction, "oil") \
					< b_oil + reserve_cost:
				continue
		# Jeremy 2026-10-05: oil pumps generate ONLY inside an industrial
		# zone, so the overlap ring-search must not push one outside its
		# zone (a dead 100w+50g building otherwise).
		var zone_rect := Rect2()
		if btype == "oil_pump":
			zone_rect = _industrial_rect(faction, hall_pos)
		spot = _valid_spot(faction, btype, spot, zone_rect)
		if spot == Vector2.INF:
			# Jeremy 2026-10-08: oil pumps must land inside the industrial
			# zone to produce, but the zone fills with town clutter (houses,
			# farms, war buildings) — the single random point + 8-ring
			# search then fails every think and the faction never secures
			# oil income. Fall back to a systematic grid scan of the zone.
			if btype == "oil_pump":
				spot = _pump_grid_spot(faction, hall_pos)
			if spot == Vector2.INF:
				continue
		var bp: Dictionary = _place(faction, btype, town_id, spot)
		if bp.is_empty():
			continue
		# Jeremy 2026-10-08: oil pumps ride outside the 2/think essentials
		# budget — they are income infrastructure (the faction's only oil
		# source), not construction the budget paces. One pump per think
		# max via the single queue entry; the military/economic priority
		# order the triage tests pin down is unchanged.
		if btype != "oil_pump":
			placed += 1
		if btype == war_b and war_b != "":
			_gazette("WAR ENGINE RISING",
				"The %s raise their %s. War is coming."
				% [_fname(faction),
					String(SimBuildings.BUILDINGS.get(war_b, {}).get("name", war_b))])
		if placed >= BUILD_MAX_PER_THINK:
			return


## Houses only when demand exceeds beds (counting incomplete houses).
func _needs_more_housing(faction: String) -> bool:
	var demand := _pop_of(faction)
	var beds := _count_build(faction, "house") * HOUSE_RESIDENTS
	var pending := 0
	for b: Dictionary in _gs.buildings:
		if bool(b.get("alive", false)) and not bool(b.get("complete", false)) \
				and String(b.get("faction", "")) == faction \
				and String(b.get("type", "")) == "house":
			pending += 1
	beds += pending * HOUSE_RESIDENTS
	return demand > beds


## Placement offsets per building type (HTML aiBuildEssentials, verbatim).
func _queue_spot(faction: String, hall_pos: Vector2, btype: String,
		war_b: String) -> Vector2:
	var bx := hall_pos.x + randf_range(-140, 140)
	var by := hall_pos.y + randf_range(-130, 130)
	if btype == "camp":
		var spot := _near_resource(faction, hall_pos)
		if spot != Vector2.INF:
			bx = spot.x + randf_range(-25, 25)
			by = spot.y + randf_range(-25, 25)
	elif btype == "lumber_camp":
		# Jeremy 2026-10-05: lumber camps go up beside the trees they cover.
		var tspot := _near_trees(faction, hall_pos)
		if tspot != Vector2.INF:
			bx = tspot.x + randf_range(-25, 25)
			by = tspot.y + randf_range(-25, 25)
	elif btype == "oil_pump":
		# Jeremy 2026-10-05: oil pumps go inside the industrial zone.
		var zspot := _inside_industrial(faction, hall_pos)
		if zspot != Vector2.INF:
			bx = zspot.x
			by = zspot.y
	elif btype == war_b and war_b != "":
		bx = hall_pos.x + (200.0 if randf() > 0.5 else -200.0) \
			+ randf_range(-20, 20)
		by = hall_pos.y + (160.0 if randf() > 0.5 else -160.0) \
			+ randf_range(-20, 20)
	elif btype == "cannon_foundry":
		bx = hall_pos.x + (220.0 if randf() > 0.5 else -220.0)
		by = hall_pos.y + (170.0 if randf() > 0.5 else -170.0)
	elif btype == "barracks":
		# Jeremy 2026-10-07: barracks is the AI's core military building,
		# but it used the hall-centered default spot (±140px), which never
		# clears the hall's footprint + PLACEMENT_GAP — the AI raised zero
		# barracks. Military ring like the other war buildings.
		var bar_ang := randf() * TAU
		var bar_ring := 250.0 + randf() * 130.0
		bx = hall_pos.x + cos(bar_ang) * bar_ring
		by = hall_pos.y + sin(bar_ang) * bar_ring
	elif btype == "fire_station":
		bx = hall_pos.x + (240.0 if randf() > 0.5 else -240.0)
		by = hall_pos.y + (190.0 if randf() > 0.5 else -190.0)
	elif btype == "aa_tower":
		bx = hall_pos.x + randf_range(-160, 160)
		by = hall_pos.y + randf_range(-160, 160)
	elif btype in ["medic_camp", "field_camp", "equip_camp"]:
		var ang := randf() * TAU
		var ring := 220.0 + randf() * 120.0
		bx = hall_pos.x + cos(ang) * ring
		by = hall_pos.y + sin(ang) * ring
	# perf R20: raw candidate spot — the caller validates at placement time
	# (validating inside here priced up to 9 full building scans per queue
	# entry, even for entries the want-check skips).
	return Vector2(bx, by)


## Nearest tree or gold vein 100-750px from the hall (HTML camp rule).
func _near_resource(faction: String, hall_pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for s: Dictionary in _gs.work_sites:
		if not String(s.get("kind", "")) in ["tree", "gold_vein"]:
			continue
		if float(s.get("amount", 0.0)) <= 0.0:
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		var d: float = hall_pos.distance_to(sp)
		if d > 100.0 and d < 750.0 and d < best_d:
			best_d = d
			best = sp
	return best


## Nearest living tree 100-750px from the hall — lumber-camp placement.
## (Mirrors _near_resource, trees only.)
func _near_trees(faction: String, hall_pos: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for s: Dictionary in _gs.work_sites:
		if String(s.get("kind", "")) != "tree":
			continue
		if float(s.get("amount", 0.0)) <= 0.0:
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		var d: float = hall_pos.distance_to(sp)
		if d > 100.0 and d < 750.0 and d < best_d:
			best_d = d
			best = sp
	return best


## Jeremy 2026-10-05: oil pumps must sit inside an industrial zone to
## produce. Paints a 480px industrial zone beside the town when the faction
## has none near the hall yet.
func _ensure_industrial_zone(faction: String, hall_pos: Vector2) -> void:
	var zoning: SimZoning = _gs.zoning
	if zoning == null:
		return
	for z: Dictionary in zoning.zones_of(SimZoning.INDUSTRIAL, faction):
		var zr: Rect2 = z.get("rect", Rect2())
		if hall_pos.distance_to(zr.get_center()) < 900.0:
			return  # already covered
	var rect := Rect2(hall_pos + Vector2(180, -240), Vector2(480, 480))
	zoning.paint_zone(SimZoning.INDUSTRIAL, faction, rect)


## Industrial zone rect of the faction nearest the hall. Empty when none
## painted (or zoning missing).
func _industrial_rect(faction: String, hall_pos: Vector2) -> Rect2:
	var zoning: SimZoning = _gs.zoning
	if zoning == null:
		return Rect2()
	var best_rect := Rect2()
	var best_d := INF
	for z: Dictionary in zoning.zones_of(SimZoning.INDUSTRIAL, faction):
		var zr: Rect2 = z.get("rect", Rect2())
		var d: float = hall_pos.distance_to(zr.get_center())
		if d < best_d:
			best_d = d
			best_rect = zr
	return best_rect


## Random point inside the faction's industrial zone nearest the hall
## (oil-pump placement). INF when no industrial zone exists.
func _inside_industrial(faction: String, hall_pos: Vector2) -> Vector2:
	var best_rect := _industrial_rect(faction, hall_pos)
	if best_rect.size.x <= 0.0:
		return Vector2.INF
	# Inset by the pump footprint so the whole building lands inside.
	var inner: Rect2 = best_rect.grow(-40.0)
	if inner.size.x < 1.0 or inner.size.y < 1.0:
		inner = best_rect
	return Vector2(
		randf_range(inner.position.x, inner.position.x + inner.size.x),
		randf_range(inner.position.y, inner.position.y + inner.size.y))


## Jeremy 2026-10-08: systematic fallback for oil-pump placement. The
## industrial zone fills with town clutter over time (houses, farms, war
## buildings at ring spots), and the single random point + 8-ring search
## can fail every think — leaving the faction with zero oil income. This
## scans the zone on a coarse grid (jittered so pumps don't line up in a
## rigid row) and returns the first spot passing full placement validity.
## Returns INF when the zone is genuinely full.
func _pump_grid_spot(faction: String, hall_pos: Vector2) -> Vector2:
	var zone := _industrial_rect(faction, hall_pos)
	if zone.size.x <= 0.0:
		return Vector2.INF
	var rect := _map_rect()
	var gap := SimBuildings.PLACEMENT_GAP
	var posts := SimCommandPosts.claimants_of_game(_gs)
	var step := 60.0
	var y := zone.position.y + 40.0
	while y < zone.end.y - 40.0:
		var x := zone.position.x + 40.0
		while x < zone.end.x - 40.0:
			var spot := Vector2(x + randf_range(-14.0, 14.0),
				y + randf_range(-14.0, 14.0))
			if zone.has_point(spot) and SimBuildings.can_place_at(
					_gs.buildings, "oil_pump", spot, rect, faction,
					gap, posts, _gs.map_data):
				return spot
			x += step
		y += step
	return Vector2.INF


## Nudge the spot until it passes the shared placement validity (or fail).
## zone_rect (optional): zone-bound buildings (oil pumps) must stay inside
## it — the overlap ring-search never escapes to dead ground.
func _valid_spot(faction: String, btype: String, spot: Vector2,
		zone_rect := Rect2()) -> Vector2:
	var rect := _map_rect()
	var gap := SimBuildings.PLACEMENT_GAP  # AI auto-layout gets breathing room
	var posts := SimCommandPosts.claimants_of_game(_gs)
	var md: Dictionary = _gs.map_data
	if SimBuildings.can_place_at(_gs.buildings, btype, spot, rect, faction, gap, posts, md) \
			and (zone_rect.size.x <= 0.0 or zone_rect.has_point(spot)):
		return spot
	for i in 8:
		var ang := float(i) / 8.0 * TAU
		var alt := spot + Vector2(cos(ang), sin(ang)) * 150.0
		if zone_rect.size.x > 0.0 and not zone_rect.has_point(alt):
			continue
		if SimBuildings.can_place_at(_gs.buildings, btype, alt, rect, faction, gap, posts, md):
			return alt
	# Jeremy 2026-10-08: widening spiral fallback. The 150px ring can fail
	# every think in a dense town (observed: a war building blocked 290/382
	# attempts while open land sat 300px away). Spiral out before giving up;
	# the zone constraint still applies when one is given. Only runs after
	# the cheap checks fail, so the common path costs nothing extra.
	for ring_r in [300.0, 450.0, 600.0]:
		for j in 16:
			var sang = float(j) / 16.0 * TAU + float(ring_r) * 0.01
			var salt = spot + Vector2(cos(sang), sin(sang)) \
				* float(ring_r)
			if zone_rect.size.x > 0.0 and not zone_rect.has_point(salt):
				continue
			if SimBuildings.can_place_at(_gs.buildings, btype, salt, rect,
					faction, gap, posts, md):
				return salt
	return Vector2.INF


func _place(faction: String, btype: String, town_id: int,
		spot: Vector2, note: String = "") -> Dictionary:
	var sys := SimBuildings.new(_gs)
	# Advisor mode: never compete with the player's own blueprints.
	if _is_advisor(faction) and _defers_to_player(faction, btype, spot):
		return {}
	# Jeremy 2026-10-07: buildings were stacking on top of each other.
	# Validate EVERY placement through the overlap ring-search here, not just
	# the callers that remembered _valid_spot — _place is the single choke
	# point for all AI construction. Returns INF when no valid spot exists.
	var ok_spot := _valid_spot(faction, btype, spot)
	if ok_spot == Vector2.INF:
		return {}
	# First-barracks check BEFORE the stamp: _count_build includes
	# blueprints, so this placement is the faction's first field-base
	# building only when the count is still zero.
	var first_barracks: bool = btype == "barracks" \
		and _count_build(faction, "barracks") == 0
	var bp: Dictionary = sys.place_blueprint(btype, faction, town_id, ok_spot)
	if not bp.is_empty():
		_tc_bump_build(faction, bp)  # perf R20: keep the think census live
		_maybe_announce_field_base(faction, first_barracks)
	if not bp.is_empty() and _is_advisor(faction):
		_advisor_note(faction, btype, note)
	return bp


## True when the player placed a blueprint of this type near the spot —
## the advisers back off instead of duplicating the player's orders.
func _defers_to_player(faction: String, btype: String,
		spot: Vector2) -> bool:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) != btype:
			continue
		if not bool(b.get("player_placed", false)):
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		if bp.distance_to(spot) < PLAYER_DEFER_RADIUS:
			return true
	return false


## Subtle Gazette note for significant adviser actions — "your staff
## handling routine matters". Throttled to one note per building type per
## game day so routine thinks don't spam the paper.
func _advisor_note(faction: String, btype: String,
		note: String = "") -> void:
	if not btype in ADVISER_NOTIFY and note == "":
		return
	var day: int = _gs.day_number
	if int(_advisor_note_day.get(btype, -1)) == day:
		return
	_advisor_note_day[btype] = day
	var text := note
	if text == "":
		var bname := String(
			SimBuildings.BUILDINGS.get(btype, {}).get("name", btype))
		text = "Your adviser commissioned a %s." % bname
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, "ADVISER'S WORK", text, "adviser")


func _map_rect() -> Rect2:
	var w := float(_gs.map_data.get("world_w", 4096.0))
	var h := float(_gs.map_data.get("world_h", 4096.0))
	return Rect2(Vector2.ZERO, Vector2(w, h))


## --- Agri plan (HTML aiBuildTick62) -------------------------------------------

func _agri(faction: String, hall: Dictionary) -> void:
	var hall_pos: Vector2 = hall.get("position", Vector2.ZERO)
	var town_id := int(hall.get("town_id", -1))
	if faction == "undead":
		if _count_build(faction, "flesh_farm") < 1:
			var s := _country_spot(faction, hall_pos)
			if s != Vector2.INF:
				_place_free(faction, "flesh_farm", town_id, s)
		return
	for entry: Array in AGRI_PLAN:
		var btype: String = String(entry[0])
		if _count_build(faction, btype) < int(entry[1]):
			var s2 := _country_spot(faction, hall_pos)
			if s2 != Vector2.INF:
				_place_free(faction, btype, town_id, s2)
			break


## Country spot 420-750px from the hall (HTML countrySpot62).
func _country_spot(faction: String, hall_pos: Vector2) -> Vector2:
	for i in 6:
		var ang := randf() * TAU
		var dist := randf_range(420.0, 750.0)
		var spot := hall_pos + Vector2(cos(ang), sin(ang)) * dist
		spot = _valid_spot(faction, "farm", spot)
		if spot != Vector2.INF:
			return spot
	return Vector2.INF


## HTML's placeAgri62 {free:true}: the AI's farms don't charge the bank.
func _place_free(faction: String, btype: String, town_id: int,
		spot: Vector2, note: String = "") -> Dictionary:
	# Advisor mode: never compete with the player's own blueprints.
	if _is_advisor(faction) and _defers_to_player(faction, btype, spot):
		return {}
	var costs: Dictionary = SimBuildings.BUILDINGS.get(btype, {}).get("costs", {})
	for res: String in costs.keys():
		_gs.resources.add_resource(faction, res, float(costs[res]), true)
	# _place runs the adviser deferral + announcement for us.
	return _place(faction, btype, town_id, spot, note)


## --- Town expansion (HTML townExpandTrickle) ----------------------------------
##
## When a town's housing fills up, the AI expands: places a new house near
## the hall. HTML activated dormant zones; Godot places a real blueprint
## (which gets proper construction scaffolding + completed visuals via
## BuildingNode, per the 2026-10-04 graphics rule).
const EXPAND_COOLDOWN := 240.0  # HTML: 240s game time per hall
const EXPAND_HOUSE_DEMAND := 0.6  # HTML: expand when pop >= houses*4*0.6

var _expand_last := {}  # hall_id -> game_time of last expansion


func _town_expand_trickle(faction: String, hall: Dictionary,
		st: Dictionary) -> void:
	var hall_id := int(hall.get("id", -1))
	var now: float = _gs.game_time
	if now - float(_expand_last.get(hall_id, -9999.0)) < EXPAND_COOLDOWN:
		return
	var houses := _count_build(faction, "house")
	if houses <= 0:
		return
	var pop := _pop_of(faction)
	# HTML: no demand yet when pop < houses * 4 * 0.6
	if pop < float(houses) * float(HOUSE_RESIDENTS) * EXPAND_HOUSE_DEMAND:
		return
	# Town cap check (HTML townAtCap).
	if _town_at_cap(faction, hall):
		return
	var hall_pos: Vector2 = hall.get("position", Vector2.ZERO)
	var town_id := int(hall.get("town_id", -1))
	var spot := _town_spot(faction, hall_pos)
	if spot == Vector2.INF:
		return
	_place_free(faction, "house", town_id, spot)
	_expand_last[hall_id] = now


## HTML townAtCap: town is at its building cap.
func _town_at_cap(faction: String, hall: Dictionary) -> bool:
	var town_id := int(hall.get("town_id", -1))
	var n := 0
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if int(b.get("town_id", -1)) != town_id:
			continue
		n += 1
	# Generous cap: towns can grow substantially before stopping.
	return n >= 60


## Find a buildable spot near the hall for town expansion.
func _town_spot(faction: String, hall_pos: Vector2) -> Vector2:
	for i in 8:
		var ang := randf() * TAU
		var dist := randf_range(180.0, 420.0)
		var spot := hall_pos + Vector2(cos(ang), sin(ang)) * dist
		spot = _valid_spot(faction, "house", spot)
		if spot != Vector2.INF:
			return spot
	return Vector2.INF


## --- New settlement founding --------------------------------------------------
##
## When a faction is thriving (near pop cap, existing towns full, surplus
## resources) and has fewer than TOWNS_PER_FACTION towns, it founds a new
## settlement: places a town hall at a distant valid location.
## (HTML had no AI town founding; this is new behavior per Jeremy's
## "AI factions found new settlements when appropriate".)
const SETTLE_COOLDOWN := 600.0  # 10 min game time between foundings
const SETTLE_MIN_DIST := 1500.0  # min distance from existing halls

var _settle_last := {}  # faction -> game_time of last founding


func _found_settlement(faction: String, hall: Dictionary,
		st: Dictionary) -> void:
	var now: float = _gs.game_time
	if now - float(_settle_last.get(faction, -9999.0)) < SETTLE_COOLDOWN:
		return
	# Count existing towns.
	var towns := 0
	var hall_positions: Array[Vector2] = []
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in ["town_hall", "hall"]:
			towns += 1
			hall_positions.append(b.get("position", Vector2.ZERO))
	if towns >= Config.TOWNS_PER_FACTION:
		return
	# Population pressure: near faction cap.
	var pop := _pop_of(faction)
	if pop < int(float(Config.POP_CAP_FACTION) * 0.8):
		return
	# Can afford a town hall (150 wood, 100 oil).
	var r = _gs.resources
	if r.get_amount(faction, "wood") < 200.0:
		return
	# Find a distant valid spot.
	var spot := _settle_spot(faction, hall_positions)
	if spot == Vector2.INF:
		return
	# Founding a settlement is a major decision: route it through the
	# proposal protocol. AI factions auto-resolve (synchronously, same
	# think); the player faction gets the phone modal in advisor mode.
	var props = _gs.get("proposals")
	if props != null:
		props.propose(faction, SimProposals.KIND_EXPAND_TERRITORY,
			{"position": spot})
	else:
		found_settlement_at(faction, spot)


## Find a settlement spot far from existing halls.
func _settle_spot(faction: String,
		existing: Array[Vector2]) -> Vector2:
	var rect := _map_rect()
	for i in 12:
		var spot := Vector2(
			randf_range(rect.position.x + 300.0, rect.end.x - 300.0),
			randf_range(rect.position.y + 300.0, rect.end.y - 300.0))
		var ok := true
		for hp: Vector2 in existing:
			if spot.distance_to(hp) < SETTLE_MIN_DIST:
				ok = false
				break
		if not ok:
			continue
		spot = _valid_spot(faction, "town_hall", spot)
		if spot != Vector2.INF:
			return spot
	return Vector2.INF

## --- Military-industrial training doctrine (HTML aiThink, verbatim) ----------

func _train(faction: String, hall: Dictionary, st: Dictionary) -> void:
	var hall_pos: Vector2 = st["hall_pos"]
	var town_id := int(hall.get("town_id", -1))
	var army: Array = st["army"]
	var workers: Array = st["workers"]
	var r = _gs.resources
	var under_attack: bool = bool(st["under_attack"])
	var at_cap := _pop_of(faction) >= Config.POP_CAP_FACTION
	# Threat scout: want army ~1.35x the enemy's, with race floors.
	# Perf R31: census-bucketed foe military (same pass as the census);
	# falls back to the full scan outside a think.
	var enemy_army := 0
	if _tc_valid and _tc_faction == faction:
		for of: String in _tc_foe_military.keys():
			for u: Dictionary in (_tc_foe_military[of] as Array):
				if hall_pos.distance_to(u.get("position", Vector2.ZERO)) < 1200.0:
					enemy_army += 1
	else:
		for u: Dictionary in _gs.units:
			if not bool(u.get("alive", false)):
				continue
			if String(u.get("faction", "")) == faction:
				continue
			if not JobDefs.is_military(String(u.get("job", ""))):
				continue
			if hall_pos.distance_to(u.get("position", Vector2.ZERO)) < 1200.0:
				enemy_army += 1
	var race_floor := 16
	if faction == "ogres":
		race_floor = 14
	elif faction == "gnomes":
		race_floor = 12
	var army_target := maxi(18 if under_attack else 12,
		maxi(int(ceil(float(enemy_army) * 1.35)) + 4, race_floor))
	var economy_tight: bool = r.get_amount(faction, "gold") < 60.0 \
		or r.get_amount(faction, "wood") < 50.0
	# Jeremy 2026-10-04: war-campaign buildup bias — the war effort trains
	# harder and spends through tight belts.
	if _has_buildup_bias(faction):
		army_target = int(ceil(army_target * 1.6))
		economy_tight = false
	var hiring = _gs.hiring
	# Workers first — economy backbone. Hall trains them (TRAINER_TYPES).
	# Jeremy 2026-10-04: only train what the faction needs (idle hands
	# first, countryside room left).
	var spawn_b := hall
	if not at_cap and spawn_b.get("complete", false) \
			and workers.size() < WORKER_WANT \
			and _needs_unit(faction, "worker", army_target) \
			and not _player_queued(spawn_b, "worker"):
		if hiring != null and _qtrain(faction, spawn_b, "worker"):
			if workers.size() < 6 and not at_cap:
				_qtrain(faction, spawn_b, "worker")
	var roadies := 0
	if _tc_valid and _tc_faction == faction:
		roadies = int(_tc_job.get("roadbuilder", 0))  # perf R31: census count
	else:
		for u: Dictionary in _gs.units:
			if bool(u.get("alive", false)) \
					and String(u.get("faction", "")) == faction \
					and String(u.get("job", "")) == "roadbuilder":
				roadies += 1
	if not at_cap and spawn_b.get("complete", false) and roadies < WORKER_WANT \
			and hiring != null \
			and _needs_unit(faction, "roadbuilder", army_target) \
			and not _player_queued(spawn_b, "roadbuilder"):
		_qtrain(faction, spawn_b, "roadbuilder")
	# Barracks — rotate through the FULL roster so every type gets made.
	# Perf R31: census build list (same _gs.buildings order, live refs);
	# falls back to the full scan outside a think.
	var barracks_list := []
	if _tc_valid and _tc_faction == faction:
		for b: Dictionary in (_tc_build_list.get("barracks", []) as Array):
			if bool(b.get("alive", false)) and bool(b.get("complete", false)):
				barracks_list.append(b)
	else:
		for b: Dictionary in _gs.buildings:
			if bool(b.get("alive", false)) and bool(b.get("complete", false)) \
					and String(b.get("faction", "")) == faction \
					and String(b.get("type", "")) == "barracks":
				barracks_list.append(b)
	if not barracks_list.is_empty():
		for br: Dictionary in barracks_list:
			if army.size() >= army_target and not under_attack:
				break
			if economy_tight and army.size() >= maxi(8, enemy_army):
				break
			var opts: Array = GuildHiring.TRAINER_TYPES.get("barracks", [])
			var best_type := ""
			var best_count := 1 << 30
			for utype: String in opts:
				var c := _count_job(faction, utype)
				if c < best_count:
					best_count = c
					best_type = utype
			if best_type != "" and not at_cap and hiring != null \
					and _needs_unit(faction, best_type, army_target) \
					and not _player_queued(br, best_type):
				_qtrain(faction, br, best_type)
			if hiring != null:
				for utype2: String in opts:
					if utype2 != best_type and not at_cap \
							and not _player_queued(br, utype2) \
							and _qtrain(faction, br, utype2):
						break
	elif _can_afford(faction, "barracks") and not at_cap \
			and _count_build(faction, "barracks") < 1:
		# No barracks at all (built OR blueprint): raise one in the
		# military district. _count_build includes blueprints, so the AI
		# never stacks a duplicate barracks every think while the first
		# is still being built — each duplicate burned 100 oil and left
		# the faction oil-broke (Jeremy 2026-10-07: AI built zero military).
		var base := _military_base(faction, hall_pos)
		var bspot := _valid_spot(faction, "barracks",
			base if base != Vector2.INF else hall_pos + Vector2(400, 0))
		if bspot == Vector2.INF:
			# Military district / hall-east blocked — fall back to the
			# barracks' town ring spot (never drop it overlapping the hall).
			bspot = _valid_spot(faction, "barracks",
				_queue_spot(faction, hall_pos, "barracks",
					String(st["war_b"])))
		if bspot != Vector2.INF:
			_place(faction, "barracks", town_id, bspot)
	# Elite war building — in the military district only.
	var war_b: String = String(st["war_b"])
	if war_b != "" and _count_build(faction, war_b) < 1 \
			and int(st["barracks"]) >= 1 and _can_afford(faction, war_b) \
			and not at_cap:
		var base2 := _military_base(faction, hall_pos)
		var bp: Dictionary = _place(faction, war_b, town_id,
			base2 if base2 != Vector2.INF else hall_pos + Vector2(420, 0))
		if not bp.is_empty():
			_gazette("WAR ENGINE RISING",
				"The %s raise their %s. War is coming."
				% [_fname(faction),
					String(SimBuildings.BUILDINGS.get(war_b, {}).get("name", war_b))])
	# Cannon foundry + guard towers + AA + nuke silo + medic camp.
	if int(st["barracks"]) >= 1 or army.size() >= 3:
		if _count_build(faction, "cannon_foundry") < 1 \
				and _can_afford(faction, "cannon_foundry"):
			var base3 := _military_base(faction, hall_pos)
			_place(faction, "cannon_foundry", town_id,
				base3 if base3 != Vector2.INF else hall_pos + Vector2(380, 0))
		if _count_build(faction, "guard_tower") < GUARD_TOWERS_WANT \
				and _can_afford(faction, "guard_tower"):
			var ang := randf() * TAU
			_place(faction, "guard_tower", town_id,
				_valid_spot(faction, "guard_tower",
					hall_pos + Vector2(cos(ang), sin(ang)) * 200.0))
		_air_defenses(faction, hall)
		if _count_build(faction, "nuke_silo") < 1 and army.size() >= 8 \
				and _can_afford(faction, "nuke_silo"):
			var base4 := _military_base(faction, hall_pos)
			var sx: Vector2 = (base4 if base4 != Vector2.INF else hall_pos) \
				+ Vector2(80, -60)
			_place(faction, "nuke_silo", town_id,
				_valid_spot(faction, "nuke_silo", sx))
		if _count_build(faction, "medic_camp") < 1 \
				and _can_afford(faction, "medic_camp"):
			var ang2 := randf() * TAU
			_place(faction, "medic_camp", town_id,
				_valid_spot(faction, "medic_camp",
					hall_pos + Vector2(cos(ang2), sin(ang2)) * 240.0))
	# Artillery: keep every foundry's queue topped up to 3 (scarcest first).
	# Advisor mode: the player queued something here — skip the whole line.
	for f: Dictionary in _gs.buildings:
		if not bool(f.get("alive", false)) or not bool(f.get("complete", false)):
			continue
		if String(f.get("faction", "")) != faction \
				or String(f.get("type", "")) != "cannon_foundry":
			continue
		if _player_queued_any(f):
			continue
		var q: Array = _train_queue_of(f)
		var guard := 0
		while q.size() < 3 and guard < 6 and not at_cap and hiring != null:
			guard += 1
			var best_t := FOUNDRY_OPTS[0]
			var best_c := 1 << 30
			for t: String in FOUNDRY_OPTS:
				var c := _count_job(faction, t)
				if c < best_c:
					best_c = c
					best_t = t
			if best_c >= ARMY_TYPE_CAP:
				break
			# Jeremy 2026-10-04: cap artillery by the threat level too.
			if not _needs_unit(faction, best_t, army_target):
				break
			if not _qtrain(faction, f, best_t):
				break
	# Rush-finish incomplete foundries so artillery can start (free seed).
	for fr: Dictionary in _gs.buildings:
		if not bool(fr.get("alive", false)) or bool(fr.get("complete", false)):
			continue
		if String(fr.get("faction", "")) != faction \
				or String(fr.get("type", "")) != "cannon_foundry":
			continue
		var prog := minf(1.0, float(fr.get("progress", 0.0)) + AI_BUILD_DRIP)
		fr["progress"] = prog
		if prog >= 1.0:
			fr["complete"] = true
			fr["progress"] = 1.0
			if hiring != null and not at_cap:
				for t: String in FOUNDRY_RUSH_SEED:
					_place_free_unit(fr, t, faction)
			_gazette("FOUNDRY ONLINE",
				"The %s rushed a foundry online!" % _fname(faction),
				"news")
	# Horse stable outside each town (30% per think; no horse-buying in Godot).
	for h: Dictionary in _gs.buildings:
		if not bool(h.get("alive", false)):
			continue
		if String(h.get("faction", "")) != faction:
			continue
		if not String(h.get("type", "")) in ["town_hall", "hall"]:
			continue
		var hp: Vector2 = h.get("position", Vector2.ZERO)
		var has_stable := false
		for sb: Dictionary in _gs.buildings:
			if not bool(sb.get("alive", false)):
				continue
			if String(sb.get("faction", "")) != faction \
					or String(sb.get("type", "")) != "horse_stable":
				continue
			if hp.distance_to(sb.get("position", Vector2.ZERO)) < STABLE_DIST:
				has_stable = true
				break
		if not has_stable and r.get_amount(faction, "gold") >= 120.0 \
				and r.get_amount(faction, "wood") >= 100.0 and randf() < 0.3:
			var ang3 := randf() * TAU
			var dist := randf_range(STABLE_RING_MIN, STABLE_RING_MAX)
			_place(faction, "horse_stable", int(h.get("town_id", -1)),
				_valid_spot(faction, "horse_stable",
					hp + Vector2(cos(ang3), sin(ang3)) * dist))
	# Doctors stay staffed at clinics.
	for cl: Dictionary in _gs.buildings:
		if not bool(cl.get("alive", false)) or not bool(cl.get("complete", false)):
			continue
		if String(cl.get("faction", "")) != faction \
				or String(cl.get("type", "")) != "clinic":
			continue
		if _count_job(faction, "doctor") < 2 and hiring != null and not at_cap \
				and not _player_queued(cl, "doctor"):
			_qtrain(faction, cl, "doctor")
			_qtrain(faction, cl, "doctor")


func _count_job(faction: String, job: String) -> int:
	if _tc_valid and _tc_faction == faction:
		return int(_tc_job.get(job, 0))  # perf R20: census read
	var n := 0
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == faction \
				and String(u.get("job", "")) == job:
			n += 1
	return n


func _can_afford(faction: String, btype: String) -> bool:
	var costs: Dictionary = SimBuildings.BUILDINGS.get(btype, {}).get("costs", {})
	return _gs.resources.can_afford(faction, costs)


## Rush-seed a training job for free (HTML pushes the queue without spend).
func _place_free_unit(building: Dictionary, unit_type: String,
		faction: String) -> void:
	var costs: Dictionary = GuildHiring.TRAIN_COST.get(unit_type, {})
	for res: String in costs.keys():
		_gs.resources.add_resource(faction, res, float(costs[res]), true)
	_qtrain(faction, building, unit_type)


func _train_queue_of(building: Dictionary) -> Array:
	# Mirrors GuildHiring's queue storage ("train_queue" key).
	var q: Array = building.get("train_queue", [])
	return q


## Advisor mode: true when the player already queued this unit type at
## this building (entries marked by_player by GuildHiring). The AI never
## duplicates a training line the player explicitly ordered.
func _player_queued(building: Dictionary, unit_type: String) -> bool:
	for job: Dictionary in _train_queue_of(building):
		if String(job.get("unit_type", "")) == unit_type \
				and bool(job.get("by_player", false)):
			return true
	return false


## Advisor mode: true when the player queued ANY training at this
## building — the AI skips the whole training line for the think.
func _player_queued_any(building: Dictionary) -> bool:
	for job: Dictionary in _train_queue_of(building):
		if bool(job.get("by_player", false)):
			return true
	return false


## Military district center: first M zone of the faction, else INF.
func _military_base(faction: String, fallback: Vector2) -> Vector2:
	if _gs.zoning != null:
		var zones: Array = _gs.zoning.zones_of("M", faction)
		if not zones.is_empty():
			return (zones[0] as Dictionary).get("position", Vector2.INF)
	return Vector2.INF


## --- Workforce push (HTML forceCivWork port) ----------------------------------
##
## Jeremy 2026-10-04: the director GUARANTEES construction crews every think.
## The worker pull system (WorkerAI._pick_task) only volunteers for build
## duty when the faction is stocked (wood>80, gold>60); poor factions stalled
## every blueprint forever — the "nobody builds" complaint. This is the push
## side: incomplete sites get crews up to the HTML caps, nearest-first.
## Respects advisor mode (player_order units untouched), Sims trips
## (mind_state "satisfying:"), indoor units, homesteaders, and work shifts —
## off-shift workers live their lives, they are not drafted.
func _force_civ_work(faction: String, st: Dictionary) -> void:
	var workers: Array = st.get("workers", [])
	if workers.is_empty():
		return
	var sites := []
	for b in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		sites.append(b)
	if sites.is_empty():
		return
	# HTML verbatim: maxBuilders = min(5, max(2, floor(workers * 0.4))).
	var max_builders: int = mini(5, maxi(2, int(float(workers.size()) * 0.4)))
	var builder_count := 0
	for u in workers:
		if _is_on_build_crew(u):
			builder_count += 1
	if builder_count >= max_builders:
		return
	var hour: float = WorkerAI.hour_of_day(_gs)
	var on_shift: bool = WorkerAI.is_on_shift("worker", hour)
	if not on_shift:
		return  # off-shift: the life sim owns them
	for site in sites:
		if builder_count >= max_builders:
			break
		var site_id := int((site as Dictionary).get("id", -1))
		var on_site := 0
		for u in workers:
			if int(u.get("work_building", -1)) == site_id and _is_on_build_crew(u):
				on_site += 1
		if on_site >= 3:  # HTML: 3 per site max
			continue
		var cand: Dictionary = _nearest_free_builder(workers,
			(site as Dictionary).get("position", Vector2.ZERO))
		if cand.is_empty():
			continue
		# Commit to the site (HTML: buildTarget=site, gatherTarget=null).
		cand["work_building"] = site_id
		cand["work_target_pos"] = (site as Dictionary).get("position", Vector2.ZERO)
		cand["work_state"] = "to_build"
		cand.erase("work_site")  # drop any gather assignment
		builder_count += 1


## True when the unit is already committed to construction work.
func _is_on_build_crew(u: Dictionary) -> bool:
	var ws := String(u.get("work_state", ""))
	if ws != "to_build" and ws != "building":
		return false
	var b: Dictionary = _building_by_id(int(u.get("work_building", -1)))
	return not b.is_empty() and bool(b.get("alive", false)) \
		and not bool(b.get("complete", false))


## Nearest worker available for construction duty. Skips: the already-
## committed, homesteaders/home-buyers, Sims-trippers, indoor units,
## carriers (let them haul first), and player-ordered units (advisor mode).
## May pull from gather duty (HTML: 40% yank chance) — walkers and gatherers
## are fair game, haulers are not.
func _nearest_free_builder(workers: Array, site_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for u in workers:
		if not bool(u.get("alive", false)):
			continue
		if _is_on_build_crew(u):
			continue
		if u.has("_homestead") or u.has("_buying_home"):
			continue
		if String(u.get("mind_state", "")).begins_with("satisfying:"):
			continue  # Sims trip in progress — never yank mid-need
		if int(u.get("inside_building_id", 0)) > 0:
			continue
		if not (u.get("carrying", {}) as Dictionary).is_empty():
			continue  # hauling — let them deliver, then reassign
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue  # advisor mode: the player's orders win
		if bool(u.get("_food_emergency", false)):
			continue  # famine foragers stay on food duty until it lifts
		var ws := String(u.get("work_state", ""))
		# Only idle or gather-duty workers are draftable; station staff,
		# roadbuilders on orders, shoppers, and repair crews keep their jobs.
		if ws != "idle" and ws != "to_resource" and ws != "gathering" \
				and ws != "to_dropoff":
			continue
		if ws != "idle" and randf() > 0.4:  # HTML: 40% yank off gather duty
			continue
		var d: float = (u.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(site_pos)
		if d < best_d:
			best_d = d
			best = u
	return best


## --- Famine response (Economy AI: resource management) ------------------------
##
## Checklist item: "Economy AI: shops, tools, equipment, resource management".
## When a faction's food stock drops below FOOD_EMERGENCY_PER_CAP per head,
## the director declares a food emergency:
##   - AI factions: up to FOOD_EMERGENCY_MAX_REASSIGN workers are yanked off
##     non-food duty onto foraging (nearest bush site), using the same field
##     writes as WorkerAI._assign_gather_kinds ("to_resource"). Reassigned
##     units are flagged _food_emergency so _force_civ_work's build crews do
##     not steal them back mid-famine. Famine outranks blueprints — workers
##     may be pulled off construction. A free farm blueprint is rushed when
##     the faction has none (undead rush a flesh_farm instead).
##   - Player faction (advisor mode): never yanks workers (faction
##     sovereignty) — the adviser sends a phone warning + Gazette note.
## Gazette/phone/farm-rush alarms are throttled to once per day per faction.
const FOOD_EMERGENCY_PER_CAP := 3.0
## --- AI armament program (Jeremy 2026-10-05) --------------------------------
## Weapon tiers: 40g/15w, 80g/30w, 140g/50w (SimCombat.WEAPON_UPGRADES).
## The AI only spends ABOVE the reserve floor — construction and the war
## effort always eat first. Besieged factions dip into the reserve (they
## need the edge more than the savings).
const ARM_GOLD_RESERVE := 250.0
const ARM_WOOD_RESERVE := 60.0
const ARM_SIEGE_GOLD_RESERVE := 150.0
const ARM_SIEGE_WOOD_RESERVE := 40.0
const ARM_MAX_PER_THINK := 4      # dull blades, one smith — pace the spend
const ARM_ADVISE_MIN_DULL := 6    # advisers phone when 6+ troops run dull
const ARM_ADVISE_GOLD_MUL := 1.5  # ...and the treasury holds 1.5x reserve
const FOOD_EMERGENCY_CRIT_PER_CAP := 1.0
const FOOD_EMERGENCY_MAX_REASSIGN := 6

var _famine := {}  # faction -> true while the emergency is active
var _food_emergency_day := {}  # faction -> day of last alarm
var _arm_note_day := {}  # faction -> day of last "arming up" gazette
var _arm_advise_day := -99  # day the advisers last phoned about dull blades
var _field_base_announced := {}  # faction -> true (Gazette: first barracks stamped)


func _food_emergency(faction: String, hall: Dictionary,
		st: Dictionary) -> void:
	var pop := _pop_of(faction)
	var food: float = _gs.resources.get_amount(faction, "food")
	var per_cap := food / float(maxi(pop, 1))
	if pop <= 0 or per_cap >= FOOD_EMERGENCY_PER_CAP:
		if bool(_famine.get(faction, false)):
			_famine.erase(faction)
			_clear_famine_flags(faction)
		return
	_famine[faction] = true
	var critical := per_cap < FOOD_EMERGENCY_CRIT_PER_CAP
	# Throttled alarm: Gazette + adviser phone warning + farm rush, once/day.
	var day := int(_gs.day_number)
	if int(_food_emergency_day.get(faction, -99)) != day:
		_food_emergency_day[faction] = day
		var fname := _fname(faction)
		if critical:
			_gazette("FAMINE!",
				"The %s are starving — bellies empty, tempers short." % fname,
				"disaster")
		else:
			_gazette("FOOD SHORTAGE",
				"Granaries run low among the %s; foragers scour the wilds."
				% fname,
				"disaster")
		if _is_advisor(faction):
			var fl = _gs.get("faction_leaders")
			if fl != null and fl.has_method("message_player"):
				fl.message_player(_gs.player_faction,
					"My liege, our granaries are nearly empty! Put more folk "
					+ "on food gathering, or we starve.")
		else:
			_rush_famine_farm(faction, hall)
	if _is_advisor(faction):
		return  # adviser warns; never yanks the player's workers
	_reassign_foragers(faction, st)


## Rush a free farm when a starving faction has none (once per day).
func _rush_famine_farm(faction: String, hall: Dictionary) -> void:
	var btype := "flesh_farm" if faction == "undead" else "farm"
	if _count_build(faction, btype) > 0:
		return
	var town_id := int(hall.get("town_id", -1))
	var s := _country_spot(faction, hall.get("position", Vector2.ZERO))
	if s != Vector2.INF:
		_place_free(faction, btype, town_id, s, "famine")


## --- AI armament program (Jeremy 2026-10-05) --------------------------------
## Equipment AI: the director actually ARMS its troops. buy_weapon_upgrade
## was player-UI-only, so AI armies fought at weapon level 0 forever while
## the player sharpened up — a real intelligence gap (Economy AI checklist:
## "shops, tools, equipment"). The AI spends treasury SURPLUS above a
## reserve floor (builds and the war effort eat first); besieged factions
## dip into the reserve. Dullest blades first, capped per think.
## Player faction: advisers never spend the crown's gold — they phone a
## suggestion instead (faction sovereignty).
func _arm_forces(faction: String, _hall: Dictionary, st: Dictionary) -> void:
	var under_attack: bool = bool(st.get("under_attack", false))
	var army = _gs.get("army")
	if _is_advisor(faction):
		if army == null or under_attack:
			return  # wartime arming advice rides the war advisers, not here
		if _arm_advise_day == int(_gs.day_number):
			return
		var dull := _dull_blades(faction)
		if dull >= ARM_ADVISE_MIN_DULL \
				and _gs.resources.get_amount(faction, "gold") \
					> ARM_GOLD_RESERVE * ARM_ADVISE_GOLD_MUL:
			_arm_advise_day = int(_gs.day_number)
			var fl = _gs.get("faction_leaders")
			if fl != null and fl.has_method("message_player"):
				fl.message_player(_gs.player_faction,
					"My liege, %d of our soldiers still march with dull "
					% dull + "blades. The treasury is flush — sharpen them "
					+ "from the Army tab and our spears will bite deeper.")
		return
	if army == null:
		return
	var r = _gs.resources
	var reserve_g := ARM_SIEGE_GOLD_RESERVE if under_attack \
		else ARM_GOLD_RESERVE
	var reserve_w := ARM_SIEGE_WOOD_RESERVE if under_attack \
		else ARM_WOOD_RESERVE
	if r.get_amount(faction, "gold") <= reserve_g \
			or r.get_amount(faction, "wood") <= reserve_w:
		return  # the till is spoken for — builds and mouths first
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if bool(u.get("deployed_for_war", false)):
			continue  # mid-march troops get armed at home, not in the field
		var uid := int(u.get("id", -1))
		if army.weapon_upgrade_cost(uid).is_empty():
			continue  # already at max weapon level
		cands.append(u)
	# Dullest blades first.
	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("weapon_level", 0)) \
			< int(b.get("weapon_level", 0)))
	var bought := 0
	for u: Dictionary in cands:
		if bought >= ARM_MAX_PER_THINK:
			break
		if r.get_amount(faction, "gold") <= reserve_g \
				or r.get_amount(faction, "wood") <= reserve_w:
			break  # reserves are sacred
		if army.buy_weapon_upgrade(int(u.get("id", -1)), true):
			bought += 1
	if bought > 0:
		var day := int(_gs.day_number)
		if int(_arm_note_day.get(faction, -99)) != day:
			_arm_note_day[faction] = day
			_gazette("Smiths hammer through the night",
				"The %s are arming up — sharpened steel for every spear."
				% _fname(faction),
				"news")


## Fighters still running weapon level 0 (adviser-advice trigger).
func _dull_blades(faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not JobDefs.is_military(String(u.get("job", ""))):
			continue
		if int(u.get("weapon_level", 0)) <= 0:
			n += 1
	return n


## Yank workers off non-food duty onto the nearest bush site. Same skip
## rules as _nearest_free_builder (Sims-trippers, indoor units, carriers,
## homesteaders, player-ordered units are never touched), but build crews
## ARE fair game — famine outranks blueprints.
func _reassign_foragers(faction: String, st: Dictionary) -> void:
	var workers: Array = st.get("workers", [])
	if workers.is_empty():
		return
	var hour: float = WorkerAI.hour_of_day(_gs)
	if not WorkerAI.is_on_shift("worker", hour):
		return  # off-shift: the life sim owns them
	var reassigned := 0
	for u in workers:
		if reassigned >= FOOD_EMERGENCY_MAX_REASSIGN:
			break
		if not bool(u.get("alive", false)):
			continue
		if _is_on_food_duty(u):
			continue
		if String(u.get("mind_state", "")).begins_with("satisfying:"):
			continue  # Sims trip in progress — never yank mid-need
		if int(u.get("inside_building_id", 0)) > 0:
			continue
		if not (u.get("carrying", {}) as Dictionary).is_empty():
			continue  # hauling — let them deliver, then reassign
		if u.has("_homestead") or u.has("_buying_home"):
			continue
		if not (u.get("player_order", {}) as Dictionary).is_empty():
			continue  # advisor mode: the player's orders win
		var site := _nearest_bush(u)
		if site.is_empty():
			continue
		# Same fields WorkerAI._assign_gather_kinds writes.
		u["work_site"] = int(site.get("id", -1))
		u["work_target_pos"] = site.get("position", Vector2.ZERO)
		u["work_state"] = "to_resource"
		u["work_building"] = -1
		u["_food_emergency"] = true
		reassigned += 1


## True when the unit is already gathering food (flagged by a famine
## reassignment, or walking to / working a bush site).
func _is_on_food_duty(u: Dictionary) -> bool:
	if bool(u.get("_food_emergency", false)):
		return true
	var ws := String(u.get("work_state", ""))
	if ws != "to_resource" and ws != "gathering":
		return false
	var site: Dictionary = _gs.get_work_site(int(u.get("work_site", -1)))
	return String(site.get("kind", "")) == "bush"


## Nearest bush work site to the unit.
func _nearest_bush(u: Dictionary) -> Dictionary:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best := {}
	var best_d := INF
	for s in _gs.work_sites:
		if String(s.get("kind", "")) != "bush":
			continue
		var d: float = (s.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(upos)
		if d < best_d:
			best_d = d
			best = s
	return best


## Clear the famine flag from a faction's workers when the emergency lifts.
func _clear_famine_flags(faction: String) -> void:
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != faction:
			continue
		u.erase("_food_emergency")


func _building_by_id(bid: int) -> Dictionary:
	if bid < 0:
		return {}
	for b in _gs.buildings:
		if int(b.get("id", -1)) == bid:
			return b
	return {}


## --- Air defenses (HTML ensureAirDefenses) ------------------------------------

func _air_defenses(faction: String, hall: Dictionary) -> void:
	# Perf R31: one pass per think (see _ad_done). The _train-internal call
	# and the _think-level call ran back-to-back doing identical work.
	if _ad_done:
		return
	_ad_done = true
	var hall_pos: Vector2 = hall.get("position", Vector2.ZERO)
	var town_id := int(hall.get("town_id", -1))
	# perf R20: census-backed tower roster instead of full building scans per
	# spot. Dict refs are shared, so the complete-stuck mutations stay live.
	# The census path is only taken mid-think (the census dies at _think end).
	var aa_list: Array = []
	var aa := 0
	if _tc_valid and _tc_faction == faction:
		aa_list = _tc_build_list.get("aa_tower", []).duplicate()
		aa_list.append_array(_tc_build_list.get("air_defense", []))
		aa = aa_list.size()
	else:
		for t: Dictionary in _gs.buildings:
			if not bool(t.get("alive", false)):
				continue
			if String(t.get("faction", "")) != faction:
				continue
			if String(t.get("type", "")) in ["aa_tower", "air_defense"]:
				aa_list.append(t)
				aa += 1
	# Complete any stuck towers instantly.
	for t: Dictionary in aa_list:
		if not bool(t.get("complete", false)):
			t["complete"] = true
			t["progress"] = 1.0
			t["hp"] = float(t.get("max_hp", 900.0))
	if aa >= AA_WANT:
		return
	var spots := []
	for i in 6:
		var ang := float(i) / 6.0 * TAU
		var rad := 180.0 + float(i % 3) * 40.0
		spots.append(hall_pos + Vector2(cos(ang), sin(ang)) * rad)
	# Protect foundries and silos (world order preserved via id merge, so
	# limited-gold placement order matches the old full scan exactly).
	var mprot: Array = []
	if _tc_valid and _tc_faction == faction:
		mprot = _tc_build_list.get("cannon_foundry", []).duplicate()
		mprot.append_array(_tc_build_list.get("nuke_silo", []))
		mprot.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				return int(a.get("id", 0)) < int(b.get("id", 0)))
		for f: Dictionary in mprot:
			var fp: Vector2 = f.get("position", Vector2.ZERO)
			spots.append(fp + Vector2(90, -70))
			spots.append(fp + Vector2(-90, 70))
	else:
		for f: Dictionary in _gs.buildings:
			if not bool(f.get("alive", false)):
				continue
			if String(f.get("faction", "")) != faction:
				continue
			if not String(f.get("type", "")) in ["cannon_foundry", "nuke_silo"]:
				continue
			var fp: Vector2 = f.get("position", Vector2.ZERO)
			spots.append(fp + Vector2(90, -70))
			spots.append(fp + Vector2(-90, 70))
	for sp: Vector2 in spots:
		if aa >= AA_WANT:
			return
		var covered := false
		for t4: Dictionary in aa_list:
			if sp.distance_to(t4.get("position", Vector2.ZERO)) < 100.0:
				covered = true
				break
		if covered:
			continue
		var spot := _valid_spot(faction, "aa_tower", sp)
		if spot == Vector2.INF:
			continue
		var placed := {}
		if aa < AA_FREE:
			placed = _place_free(faction, "aa_tower", town_id, spot)
		else:
			# Jeremy 2026-10-07: oil triage — the faction's first
			# barracks, then its elite war building, outrank more AA
			# towers. Paid towers wait until both stand so pump oil can
			# save up their oil costs. (The 2 free towers above still
			# go up.)
			var wb := String(WAR_BUILDING.get(faction, ""))
			var core_done := _count_build(faction, "barracks") >= 1 \
				and (wb == "" or _count_build(faction, wb) >= 1)
			if not core_done:
				continue
			placed = _place(faction, "aa_tower", town_id, spot)
		if not placed.is_empty():
			aa_list.append(placed)  # the census bump in _place keeps
			aa += 1                 # later thinks consistent too


## --- Helpers ------------------------------------------------------------------

func _fname(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))


## Jeremy 2026-10-07 (12h audit): Gazette stories were ALL seeded as
## kind "war" — peacetime news (foundry, armament, famine) showed as
## WAR TALK in the rumors app and overheated at war-heat 1.0. The kind
## param (default "war") keeps every true-war call site unchanged while
## non-war stories carry their real kind.
## HTML parity (fix79 c44MaybeAnnounceBase): one Gazette announcement per
## faction when the first field-base building (barracks) is stamped. The AI's
## barracks IS the field base — barracks, camps and gun lines away from
## civilian streets. Routes through court.publish_story so it lands in the
## Chronicle archive, not just the toast (2026-10-06 news-desk rule).
func _maybe_announce_field_base(faction: String, first_barracks: bool) -> void:
	if not first_barracks:
		return
	if bool(_field_base_announced.get(faction, false)):
		return
	_field_base_announced[faction] = true
	var court = _gs.get("court_sys")
	if court == null or not court.has_method("publish_story"):
		return
	# HTML-verbatim body (fix79); publish_story sanitizes glyphs (tofu rule).
	court.publish_story("FIELD BASE ESTABLISHED",
		"%s engineers have raised a field base beyond the city walls — barracks, camps and gun lines far from civilian streets. The army lives there now."
		% _fname(faction),
		"war")


func _gazette(headline: String, body: String, kind: String = "war") -> void:
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, headline, body, kind)


## The faction's commander (or chieftain) speaks — HTML leaderSay parity.
func _commander_says(faction: String, near: Vector2, text: String) -> void:
	var best := {}
	var best_d := INF
	for u: Dictionary in _gs.units:
		if not bool(u.get("alive", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		var role := String(u.get("gov_role", ""))
		if role != "commander" and role != "mayor":
			continue
		var d: float = near.distance_to(u.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = u
	if best.is_empty():
		return
	_gs.bus.unit_said.emit(int(best.get("id", 0)), text)


## --- Save / load ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"race_idx": _race_idx,
		"plans": _plans.duplicate(true),
		"threat_prev": _threat_prev.duplicate(true),
		"advisor_note_day": _advisor_note_day.duplicate(true),
		"war_campaigns": _war_campaigns.duplicate(true),
		"campaign_cooldown": _campaign_cooldown.duplicate(true),
		"buildup_bias": _buildup_bias.duplicate(true),
		"assault_proposed": _assault_proposed.duplicate(true),
		"peace_asked": _peace_asked.duplicate(true),
		"famine": _famine.duplicate(),
		"food_emergency_day": _food_emergency_day.duplicate(true),
		"counter_raid_day": _counter_raid_day.duplicate(true),
		"field_base_announced": _field_base_announced.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	_race_idx = int(data.get("race_idx", 0))
	_plans = (data.get("plans", {}) as Dictionary).duplicate(true)
	_threat_prev = (data.get("threat_prev", {}) as Dictionary).duplicate(true)
	_advisor_note_day = (data.get("advisor_note_day", {}) as Dictionary).duplicate(true)
	_war_campaigns = (data.get("war_campaigns", {}) as Dictionary).duplicate(true)
	_campaign_cooldown = (data.get("campaign_cooldown", {}) as Dictionary).duplicate(true)
	_buildup_bias = (data.get("buildup_bias", {}) as Dictionary).duplicate(true)
	_assault_proposed = (data.get("assault_proposed", {}) as Dictionary).duplicate(true)
	_peace_asked = (data.get("peace_asked", {}) as Dictionary).duplicate(true)
	_famine = (data.get("famine", {}) as Dictionary).duplicate()
	_food_emergency_day = (data.get("food_emergency_day", {}) as Dictionary).duplicate(true)
	_counter_raid_day = (data.get("counter_raid_day", {}) as Dictionary).duplicate(true)
	_field_base_announced = (data.get("field_base_announced", {}) as Dictionary).duplicate(true)
	_acc = 0.0
