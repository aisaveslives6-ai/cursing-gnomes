class_name SimArmy
extends RefCounted
## Cursing Gnomes — armies, war, and military command.
##
## Ports the HTML's war systems into the Godot sim:
##   - playerArmyStance auto/guard/lead (HTML command menu orders)
##   - issueDraft / draftCitizen (emergency draft: civilians -> soldiers)
##   - c44MusterForWar (field army rallies at the base, then marches)
##   - deployArmyForWar + pickWarTarget priority
##     (enemy military > military buildings > resource > other > hall)
##   - warlord promotion (ogre commander: hp x2.2, dmg x1.8, aura x1.25)
##   - war32OwnStrength / war32Estimate (imperfect war intel, 0.7x-1.4x noise)
##   - war32AiWarTick (AI offensive campaigns with the three gates)
##   - war32CollapseTick (wars end when a side can't fight) — finishes the
##     war-weariness work diplomacy.gd starts (-1 morale/day at war)
##   - queueConquestPrompt (conquered-hall keep-or-rename)
##   - ensureLeaders (mayor / adviser / commander / watch_captain gov_roles
##     so the phone's "My Government" section populates)
##   - weaponsmith upgrades (3 tiers, +8% dmg each)
##
## Pure logic — no rendering, no input, no audio. The ⚔ Army tab UI lives in
## scripts/ui/army_tab.gd. world.gd owns the instance (see HOOKS in the
## port report); tests construct it directly.


## Army stances (HTML playerArmyStance): 'auto' = full AI sandbox,
## 'guard' = defend the town, 'lead' = commander marches at the head.
const STANCES := ["auto", "guard", "lead"]
const STANCE_LABEL := {
	"auto": "Full Auto", "guard": "Standing guard", "lead": "Leading troops",
}

## Emergency draft converts this many citizens (HTML issueDraft count = 4
## for the popup, 3 default).
const DRAFT_COUNT := 4

## Conquest prompt: a foreign hall falls while player combat troops are
## within this range -> the player conquered it (HTML 1100 px).
const CONQUEST_RANGE := 1100.0

## AI war evaluation: not before this day (HTML dn < 12), one eval per day.
const AI_WAR_MIN_DAY := 12

## Collapse: a side that can't field this many fighters is broken
## (HTML war32CollapseTick: mil >= 2 can fight).
const COLLAPSE_MIN_MIL := 2

## Defensive building types for own-strength (HTML war32IsDefense).
const DEFENSE_TYPES := ["guard_tower", "wall", "barracks", "castle",
	"knights_castle", "war_hut", "mage_spire", "tome_library"]

## Draftable civilian jobs (HTML draftCitizen pool: workers, not leaders,
## not combat troops).
const DRAFT_JOBS := ["worker", "woodcutter", "miner", "farmer", "builder",
	"roadbuilder", "shopkeeper", "cashier"]


var _gs: GameState
var _stances: Dictionary = {}          # faction -> stance id
var _conquest_queue: Array[Dictionary] = []
var _last_war_day: int = -1
var _last_tick_day: int = -1

## Optional SimDiplomacy (set by the world). Duck-typed to avoid a cyclic
## class reference.
var diplomacy = null


func _init(game_state: GameState) -> void:
	_gs = game_state
	_gs.bus.building_destroyed.connect(_on_building_destroyed)
	_gs.bus.town_founded.connect(_on_town_founded)
	# Jeremy 2026-10-06 (Lane 3): halls captured by FLIP (not destroyed)
	# queue the keep-or-rename prompt via the capture signal — this works
	# whether or not gs.army is wired (bare tests and the live game).
	_gs.bus.command_post_captured.connect(_on_post_captured)


## --- gov roles -------------------------------------------------------------
## phone.gd government_contacts() reads unit["mind"]["gov_role"] and only
## lists roles in its GOV_RANK table (adviser/guild_master/watch_captain/
## commander/mayor/lord/envoy). This is the only writer.

static func assign_gov_role(unit: Dictionary, role: String) -> void:
	var mind: Dictionary = unit.get("mind", {})
	if mind.is_empty():
		mind = {}
		unit["mind"] = mind
	mind["gov_role"] = role


static func clear_gov_role(unit: Dictionary) -> void:
	var mind: Dictionary = unit.get("mind", {})
	if not mind.is_empty():
		mind.erase("gov_role")


static func gov_role_of(unit: Dictionary) -> String:
	return String(unit.get("mind", {}).get("gov_role", ""))


## --- stances ---------------------------------------------------------------

## Faction sovereignty (Jeremy 2026-10-04): the player may only command
## their own faction. Any direct-control attempt on another faction's
## forces is refused by that faction's leader, in their voice. Returns ""
## when the order is allowed, the leader's refusal line when blocked.
## (The diplomacy channel — issue_command — is separate and unaffected.)
func _sovereignty_check(faction: String) -> String:
	if faction == "" or faction == _gs.player_faction:
		return ""
	var fl = _gs.get("faction_leaders")
	if fl == null:
		return "\"You have no authority over our forces.\""
	return String(fl.refuse_direct_control(faction))


func get_stance(faction: String) -> String:
	return String(_stances.get(faction, "auto"))


## Sets the army stance (HTML command-menu orders semantics).
func set_stance(faction: String, stance: String) -> void:
	if _sovereignty_check(faction) != "":
		return
	if not stance in STANCES:
		return
	_stances[faction] = stance
	if stance == "auto":
		# Full AI sandbox: clear player guard/lead orders, troops run free.
		for u: Dictionary in _gs.units:
			if String(u.get("faction", "")) != faction:
				continue
			var po: Dictionary = u.get("player_order", {})
			if String(po.get("type", "")) in ["guard", "lead"]:
				u["player_order"] = {}
			u["defend_mode"] = false
		_gs.bus.unit_said.emit(-1,
			"Sandbox AI: your faction runs itself — build, expand, train, attack.")
	elif stance == "guard":
		# Stand guard: commander holds, every fighter defends the town.
		var cmd: Dictionary = _commander_of(faction)
		if not cmd.is_empty():
			cmd["move_target"] = null
			cmd["combat_target"] = -1
			cmd["defend_mode"] = true
			cmd["player_order"] = {"type": "guard"}
		for u: Dictionary in _gs.units:
			if not _is_army_troop(u, faction):
				continue
			u["defend_mode"] = true
			if int(u.get("id", -1)) != int(cmd.get("id", -2)):
				u["move_target"] = null
	elif stance == "lead":
		# Lead troops: the commander marches at the head toward the nearest
		# enemy hall; the army forms up behind in formation slots.
		var cmd: Dictionary = _commander_of(faction)
		if cmd.is_empty():
			_gs.bus.unit_said.emit(-1,
				"No living commander — train soldiers to promote one.")
			_stances[faction] = "auto"
			return
		cmd["defend_mode"] = false
		cmd["player_order"] = {"type": "lead"}
		var hall: Dictionary = _nearest_enemy_hall(faction,
			cmd.get("position", Vector2.ZERO))
		if not hall.is_empty():
			var hpos: Vector2 = hall.get("position", Vector2.ZERO)
			cmd["combat_target"] = -1
			cmd["move_target"] = hpos
			cmd["deploy_target_id"] = int(hall.get("id", -1))
			cmd["deploy_target_kind"] = "building"
		_assign_formation_slots(faction, int(cmd.get("id", -1)))
		for u: Dictionary in _gs.units:
			if not _is_army_troop(u, faction):
				continue
			u["defend_mode"] = false
			u["tactic_cmd"] = int(cmd.get("id", -1))
			u["tactic_contact_t"] = -1.0


## Troops that march: alive fighters of the faction (guards hold posts).
func _is_army_troop(u: Dictionary, faction: String) -> bool:
	if not u.get("alive", false) or bool(u.get("downed", false)):
		return false
	if String(u.get("faction", "")) != faction:
		return false
	if not SimCombat.is_fighter(u):
		return false
	if String(u.get("job", "")) == "guard":
		return false  # C44: town guards hold their posts
	if not u.get("player_order", {}).is_empty():
		return false  # player-directed units stay put
	if u.has("counter_raid"):
		return false  # Jeremy 2026-10-05: counter-raid detachment is on
		# its own mission — war campaigns muster around it, not through it
	return true


## The faction's commander: promoted warlord, else best soldier.
func _commander_of(faction: String) -> Dictionary:
	var best: Dictionary = {}
	var best_hp: float = -1.0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if bool(u.get("warlord", false)):
			return u
		if String(u.get("job", "")) == "soldier":
			var hp: float = float(u.get("hp", 0.0))
			if hp > best_hp:
				best_hp = hp
				best = u
	return best


## Formation slots: melee front, ranged back, 6-wide (HTML
## assignFormationSlots). Ranged jobs go to the back rows.
func _assign_formation_slots(faction: String, cmd_id: int) -> void:
	var melee: Array[Dictionary] = []
	var ranged: Array[Dictionary] = []
	var other: Array[Dictionary] = []
	for u: Dictionary in _gs.units:
		if not _is_army_troop(u, faction):
			continue
		if int(u.get("id", -1)) == cmd_id:
			continue
		var job: String = String(u.get("job", ""))
		var st: Dictionary = SimCombat.MILITARY_STATS.get(job, {})
		if bool(st.get("ranged", false)):
			ranged.append(u)
		elif job in ["soldier", "guard"]:
			melee.append(u)
		else:
			other.append(u)
	var ordered: Array[Dictionary] = []
	ordered.append_array(melee)
	ordered.append_array(other)
	ordered.append_array(ranged)
	var cols := 6
	var melee_rows: int = int(ceil(float(melee.size()) / float(cols)))
	for i in ordered.size():
		var u: Dictionary = ordered[i]
		var row: int = i / cols
		var col: int = i % cols
		if u in ranged:
			row += melee_rows  # ranged forced to back rows
		u["formation_slot"] = i
		u["formation_col"] = col
		u["formation_row"] = row


func _nearest_enemy_hall(faction: String, from_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d2: float = INF
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) not in ["hall", "town_hall"]:
			continue
		var bf: String = String(b.get("faction", ""))
		if bf == faction or bf == "":
			continue
		var d2: float = from_pos.distance_squared_to(
			b.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = b
	return best


## --- draft / muster / deploy ------------------------------------------------

## Emergency draft (HTML issueDraft): conscript civilians into soldiers.
## Conversion, not spawning — population caps are untouched.
func draft(faction: String, count: int = DRAFT_COUNT) -> int:
	if _sovereignty_check(faction) != "":
		return 0
	var n := 0
	for i in count:
		if _draft_one(faction):
			n += 1
	if n > 0:
		_gs.bus.unit_said.emit(-1,
			"%s issued a draft — %d citizens conscripted" % [faction.capitalize(), n])
	return n


func _draft_one(faction: String) -> bool:
	var pool: Array[Dictionary] = []
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not String(u.get("job", "")) in DRAFT_JOBS:
			continue
		if gov_role_of(u) != "":  # leaders are never drafted
			continue
		pool.append(u)
	if pool.is_empty():
		return false
	var u: Dictionary = pool[randi() % pool.size()]
	u["_pre_draft_job"] = String(u.get("job", ""))
	u["job"] = "soldier"
	u["firearm"] = "shotgun" if faction == "ogres" \
		and int(u.get("id", 0)) % 2 == 1 else "basic"
	u["weapon_level"] = 0
	u["attack_cd"] = 0.0
	var cry := "I have been drafted."
	if faction == "ogres":
		cry = "Me drafted!"
	elif faction == "gnomes":
		cry = "Bloody draft!"
	_gs.bus.unit_said.emit(int(u.get("id", 0)), cry)
	return true


## Muster (HTML c44MusterForWar): the field army rallies at the faction's
## hall before marching. Guards hold their posts; player-ordered units stay.
## Player entry point — commanding a foreign faction's troops is refused
## (faction sovereignty, Jeremy 2026-10-04).
func muster(faction: String) -> int:
	if _sovereignty_check(faction) != "":
		return 0
	return _muster_core(faction)


## The faction's own brain rallying its troops (AI war campaigns). Not a
## player order, so the sovereignty gate does not apply — a faction may
## always command itself.
func _muster_core(faction: String) -> int:
	var hall_pos := _faction_hall_pos(faction)
	if hall_pos == Vector2.INF:
		return 0
	var n := 0
	for u: Dictionary in _gs.units:
		if not _is_army_troop(u, faction):
			continue
		u["mustering"] = true
		u["move_target"] = hall_pos + Vector2(
			randf_range(-60.0, 60.0), randf_range(-60.0, 60.0))
		n += 1
	if n > 0:
		_gazette("TROOPS MUSTERING",
			"%s forces rally at the field base before marching to war (%d troops)." % [faction.capitalize(), n])
	return n


func _faction_hall_pos(faction: String) -> Vector2:
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) in ["hall", "town_hall"] \
				and String(b.get("faction", "")) == faction:
			return b.get("position", Vector2.INF)
	return Vector2.INF


## Deploy for war (HTML deployArmyForWar): mustered troops get attack orders
## using the war-target priority: enemy military > military buildings >
## resource/industrial > other buildings > hall last.
## Player entry point — commanding a foreign faction's troops is refused
## (faction sovereignty, Jeremy 2026-10-04).
func deploy_for_war(faction: String, enemy: String = "") -> int:
	if _sovereignty_check(faction) != "":
		return 0
	return _deploy_for_war_core(faction, enemy)


## The faction's own brain deploying for war (AI war campaigns). Not a
## player order, so the sovereignty gate does not apply.
func _deploy_for_war_core(faction: String, enemy: String = "") -> int:
	_muster_core(faction)
	var n := 0
	for u: Dictionary in _gs.units:
		if not _is_army_troop(u, faction):
			continue
		u["defend_mode"] = false
		u["mustering"] = false
		u["deployed_for_war"] = true
		var tgt: Dictionary = _pick_war_target(u, faction, enemy)
		if not tgt.is_empty():
			u["deploy_target_id"] = int(tgt.get("id", -1))
			u["deploy_target_kind"] = String(
				tgt.get("kind", "building" if tgt.has("type") else "unit"))
			u["move_target"] = tgt.get("position", u.get("position"))
			n += 1
	return n


func _pick_war_target(u: Dictionary, faction: String,
		enemy: String) -> Dictionary:
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	# 1) Closest enemy military unit.
	var best: Dictionary = {}
	var best_d2: float = INF
	for e: Dictionary in _gs.units:
		if not e.get("alive", false) or bool(e.get("downed", false)):
			continue
		var ef: String = String(e.get("faction", ""))
		if ef == faction or (enemy != "" and ef != enemy):
			continue
		if not SimCombat.is_fighter(e):
			continue
		var d2: float = upos.distance_squared_to(
			e.get("position", Vector2.ZERO))
		if d2 < best_d2:
			best_d2 = d2
			best = e.duplicate()
			best["kind"] = "unit"
	if not best.is_empty():
		return best
	# 2-5) Buildings by class priority (HTML pickWarTarget scoring).
	var prio := [
		["barracks", "guard_tower", "wall", "castle", "knights_castle",
			"war_hut", "mage_spire", "tome_library"],
		["storage", "stock_gold", "stock_wood", "stock_food", "stock_oil",
			"camp"],
		[],
		["hall", "town_hall"],
	]
	for tier in prio:
		best = {}
		best_d2 = INF
		for b: Dictionary in _gs.buildings:
			var bf: String = String(b.get("faction", ""))
			if bf == faction or (enemy != "" and bf != enemy):
				continue
			var bt: String = String(b.get("type", ""))
			if not tier.is_empty() and not bt in tier:
				continue
			if tier.is_empty() and (bt in prio[0] or bt in prio[1]
					or bt in ["hall", "town_hall"]):
				continue
			var d2: float = upos.distance_squared_to(
				b.get("position", Vector2.ZERO))
			if d2 < best_d2:
				best_d2 = d2
				best = b.duplicate()
				best["kind"] = "building"
		if not best.is_empty():
			return best
	return {}


## --- retreat -----------------------------------------------------------------
## Fighting withdrawal (Jeremy 2026-10-04, AI-first phase): a field army that
## is being destroyed falls back to the nearest friendly hall instead of
## fighting to the death. Checklist item: Military AI "retreat".
##
## The AI brain assesses its field armies once a day: when a faction has lost
## half or more of its peak field strength AND the enemy still dominates the
## theater (friendly < 55% of hostile strength), the survivors are ordered
## back. The order itself is marks on the unit records — SimMind executes the
## march (withdrawing preempts combat), so no combat-system changes needed.
## The player faction never auto-retreats; the adviser warns instead.

## Enemies are scanned this far around the field army's centroid.
const RETREAT_THEATER_RADIUS := 1500.0
## Friendly field strength below this fraction of hostile strength = losing.
const RETREAT_RATIO := 0.55
## ...and only when the field army is at/below this fraction of its peak.
const RETREAT_CASUALTY_FRAC := 0.5
## Fewer field troops than this is a skirmish, not an army — no rout.
const RETREAT_MIN_FIELD := 3


var _field_peak := {}      # faction -> peak field-troop count this campaign
var _retreat_warned := {}  # faction -> true (player adviser warning, once)


## Alive, fighting-fit field troops: deployed, mustering, or on a monastery
## march. Guards holding posts are not a field army.
func _field_troops(faction: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not SimCombat.is_fighter(u):
			continue
		if bool(u.get("deployed_for_war", false)) \
				or bool(u.get("mustering", false)) \
				or u.has("monastery_march") or u.has("post_march"):
			out.append(u)
	return out


## Player entry point: order your own field army to fall back to the
## nearest hall. Refused for foreign factions (faction sovereignty).
func order_retreat(faction: String) -> int:
	if _sovereignty_check(faction) != "":
		return 0
	return _order_retreat_core(faction)


## The faction's own brain pulling its army out (retreat assessment below).
## Not a player order, so the sovereignty gate does not apply.
func _order_retreat_core(faction: String) -> int:
	var troops := _field_troops(faction)
	if troops.is_empty():
		return 0
	var hall_pos := _faction_hall_pos(faction)
	var n := 0
	for u: Dictionary in troops:
		u.erase("deploy_target_id")
		u.erase("deploy_target_kind")
		u.erase("deployed_for_war")
		u.erase("mustering")
		if hall_pos != Vector2.INF:
			u["withdrawing"] = true
			u["withdraw_target"] = hall_pos
			u["move_target"] = hall_pos
		n += 1
	_field_peak.erase(faction)
	_gazette("ARMY IN RETREAT",
		"The %s field army is broken — survivors fall back to the hall (%d troops)." % [faction.capitalize(), n])
	return n


## True when ef's fighters count as hostile to faction f right now.
func _is_hostile_to(f: String, ef: String) -> bool:
	if ef == f:
		return false
	if diplomacy == null:
		return true  # no diplomacy (tests): any foreign fighter is hostile
	return diplomacy.relation_state(f, ef) == "war"


## Daily brain tick: assess every field army, order retreats for losing AI
## factions, warn the player instead of overriding them.
func _assess_retreats() -> void:
	_assess_retreats_c(_daily_census())


## Perf R30: census-backed retreat assessment. Field troops come from the
## census pool; the theater scan iterates the precomputed hostile-fighter
## list instead of re-filtering every unit per faction. All thresholds,
## warnings, and the player-faction advisory path are unchanged.
func _assess_retreats_c(c: Dictionary) -> void:
	for f: String in Config.FACTIONS.keys():
		var troops: Array = (c["field"] as Dictionary)[f]
		if troops.is_empty():
			_field_peak.erase(f)
			_retreat_warned.erase(f)
			continue
		_field_peak[f] = maxi(int(_field_peak.get(f, 0)), troops.size())
		if troops.size() < RETREAT_MIN_FIELD:
			continue
		if float(troops.size()) \
				>= RETREAT_CASUALTY_FRAC * float(_field_peak[f]):
			continue  # not mauled yet
		# Theater strength: hp-weighted friendlies vs hostiles near the
		# field centroid.
		var centroid := Vector2.ZERO
		var friendly := 0.0
		for u: Dictionary in troops:
			centroid += u.get("position", Vector2.ZERO)
			friendly += float(u.get("hp", 1.0)) \
				/ maxf(1.0, float(u.get("max_hp", 1.0)))
		centroid /= float(troops.size())
		var hostile := 0.0
		for e: Dictionary in (c["hostile_fighters"] as Dictionary)[f]:
			if not e.get("alive", false) or bool(e.get("downed", false)):
				continue
			var epos: Vector2 = e.get("position", Vector2.ZERO)
			if epos.distance_to(centroid) > RETREAT_THEATER_RADIUS:
				continue
			hostile += float(e.get("hp", 1.0)) \
				/ maxf(1.0, float(e.get("max_hp", 1.0)))
		if hostile <= 0.0:
			continue  # battle's over — nothing to retreat from
		if friendly >= RETREAT_RATIO * hostile:
			continue  # holding the field
		if f == _gs.player_faction:
			if not bool(_retreat_warned.get(f, false)):
				_retreat_warned[f] = true
				_gazette("ADVISER'S WARNING",
					"Our field army is being destroyed. Order a retreat before it's too late.")
			continue
		_order_retreat_core(f)


## --- warlord ----------------------------------------------------------------

## Promotes the toughest fighter to warlord (HTML warlord: ogre commander,
## hp x2.2, dmg x1.8, aura buffs nearby allies' attacks).
func promote_warlord(faction: String) -> Dictionary:
	if _sovereignty_check(faction) != "":
		return {}
	if not get_warlord(faction).is_empty():
		return {}
	var best: Dictionary = {}
	var best_hp: float = -1.0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if not SimCombat.is_fighter(u):
			continue
		if gov_role_of(u) != "":
			continue
		var hp: float = float(u.get("max_hp", 0.0))
		if hp > best_hp:
			best_hp = hp
			best = u
	if best.is_empty():
		return {}
	best["warlord"] = true
	var mhp: float = float(best.get("max_hp", 100.0)) * 2.2
	best["max_hp"] = mhp
	best["hp"] = mhp
	var stats: Dictionary = SimCombat.MILITARY_STATS.get(
		String(best.get("job", "soldier")), SimCombat.MILITARY_STATS["soldier"])
	best["dmg_override"] = float(stats.get("dmg", 15.0)) * 1.8
	_gazette("WARLORD RISES",
		"%s has a new warlord — the troops fight harder in their shadow." % faction.capitalize())
	return best


func get_warlord(faction: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) == faction \
				and bool(u.get("warlord", false)) and u.get("alive", false):
			return u
	return {}


## --- government -------------------------------------------------------------
## ensureLeaders parity: every faction gets a mayor, an adviser, a lord, a
## commander and a watch captain from its living population;
## guild_master-job units carry the guild_master role. Dead holders are
## cleared and replaced. (Lords were designed as a gov role — phone.gd's
## GOV_RANK lists them and royal_court.gd's lord_* petition templates need
## them — but were never promoted, leaving those petitions permanently
## unreachable. Fixed 2026-10-05.)

func ensure_government(faction: String) -> void:
	# Perf R30: the fallen-clearing used to be its own full scan here; it
	# now happens inside _daily_census().
	_ensure_government_c(faction, _daily_census())


## Census-backed implementation. Candidate pools come from the census in
## _gs.units order (identical best-hp tie-breaks); the gov-role skip is
## checked LIVE because promotions earlier in this same call change roles.
func _ensure_government_c(faction: String, c: Dictionary) -> void:
	var have := {"mayor": false, "adviser": false, "lord": false,
		"commander": false, "watch_captain": false}
	for r: String in ((c["gov"] as Dictionary)[faction] as Dictionary).keys():
		if r in have:
			have[r] = true
	# Guild masters: the job IS the role.
	for u: Dictionary in (c["guild_masters"] as Dictionary)[faction]:
		if gov_role_of(u) == "":
			assign_gov_role(u, "guild_master")
	if not have["mayor"]:
		_promote_civilian_c(faction, "mayor", have, c)
	if not have["adviser"]:
		_promote_civilian_c(faction, "adviser", have, c)
	if not have["lord"]:
		_promote_civilian_c(faction, "lord", have, c)
	if not have["commander"]:
		_promote_fighter_c(faction, "commander", c)
	if not have["watch_captain"]:
		_promote_guard_c(faction, c)


## Perf R30 census-backed promotes. Pools are in _gs.units order, so the
## strict-> best-hp pick (first wins ties) is identical to the old scans.
## The gov-role exclusion is checked live: a unit promoted to mayor
## earlier in this same ensure_government call must not also take
## adviser, exactly as the old re-scan saw it.
func _promote_civilian_c(faction: String, role: String, have: Dictionary,
		c: Dictionary) -> void:
	var best: Dictionary = {}
	var best_hp: float = -1.0
	for u: Dictionary in (c["civ_pool"] as Dictionary)[faction]:
		if gov_role_of(u) != "":
			continue
		var hp: float = float(u.get("hp", 0.0))
		if hp > best_hp:
			best_hp = hp
			best = u
	if not best.is_empty():
		assign_gov_role(best, role)
		have[role] = true


func _promote_fighter_c(faction: String, role: String,
		c: Dictionary) -> void:
	var best: Dictionary = {}
	var best_hp: float = -1.0
	for u: Dictionary in (c["fighter_pool"] as Dictionary)[faction]:
		if gov_role_of(u) != "":
			continue
		var hp: float = float(u.get("hp", 0.0))
		if hp > best_hp:
			best_hp = hp
			best = u
	if not best.is_empty():
		assign_gov_role(best, role)


func _promote_guard_c(faction: String, c: Dictionary) -> void:
	for u: Dictionary in (c["guards"] as Dictionary)[faction]:
		if gov_role_of(u) != "":
			continue
		assign_gov_role(u, "watch_captain")
		return


func _on_town_founded(_town: Dictionary) -> void:
	# Perf R30: one census for all five factions (was five full scan sets).
	var c := _daily_census()
	for f: String in Config.FACTIONS.keys():
		_ensure_government_c(f, c)


## --- strength & intel --------------------------------------------------------

## Exact own strength (HTML war32OwnStrength): a faction knows its own muster.
func own_strength(faction: String) -> Dictionary:
	return _own_strength_c(faction, _daily_census())


## Perf R30: census-backed (mil = alive non-downed fighters, def =
## complete defense buildings — the exact sets the old scans counted).
func _own_strength_c(faction: String, c: Dictionary) -> Dictionary:
	var mil: int = ((c["fighters"] as Dictionary)[faction] as Array).size()
	var defense: int = int((c["def_complete"] as Dictionary)[faction])
	return {"mil": mil, "def": defense,
		"score": float(mil) + float(defense) * 0.6}


## Imperfect enemy estimate (HTML war32Estimate): observable facts only,
## with 0.7x-1.4x noise modeling scouts' errors and tavern gossip.
func estimate_strength(_viewer: String, target: String) -> Dictionary:
	return _estimate_strength_c(target, _daily_census())


## Perf R30: census-backed. The original counted every building of the
## target (no complete/alive check): defense = DEFENSE_TYPES buildings,
## wealth = everything else. Identical inputs, identical noise math.
func _estimate_strength_c(target: String, c: Dictionary) -> Dictionary:
	var mil: int = ((c["fighters"] as Dictionary)[target] as Array).size()
	var defense: int = int((c["def_all"] as Dictionary)[target])
	var wealth: int = int((c["bldg_all"] as Dictionary)[target]) - defense
	var raw: float = float(mil) + float(defense) * 0.6 + float(wealth) * 0.15
	var noise: float = 0.7 + randf() * 0.7
	return {"mil": mil, "def": defense, "wealth": wealth,
		"noise": snappedf(noise, 0.01),
		"score": snappedf(raw * noise, 0.1),
		"raw": snappedf(raw, 0.1)}


## --- war-weariness collapse --------------------------------------------------
## Finishes the partial in diplomacy.gd (war pairs lose morale daily):
## wars END when a side can't fight (HTML war32CollapseTick).

func collapse_tick() -> Array[String]:
	return _collapse_tick_c(_daily_census())


## Perf R30: census-backed collapse check. Pair iteration order and all
## gates unchanged; strength reads are O(1) census lookups.
func _collapse_tick_c(c: Dictionary) -> Array[String]:
	var ended: Array[String] = []
	if diplomacy == null:
		return ended
	for a: String in Config.FACTIONS.keys():
		for b: String in Config.FACTIONS.keys():
			if a >= b:
				continue
			if diplomacy.relation_state(a, b) != "war":
				continue
			var sa: Dictionary = _own_strength_c(a, c)
			var sb: Dictionary = _own_strength_c(b, c)
			var a_can: bool = int(sa["mil"]) >= COLLAPSE_MIN_MIL
			var b_can: bool = int(sb["mil"]) >= COLLAPSE_MIN_MIL
			if not a_can and not b_can:
				diplomacy.make_peace(a, b)
				_gazette("MUTUAL COLLAPSE",
					"%s and %s bleed each other white — both armies collapse. The war ends." % [a.capitalize(), b.capitalize()])
				ended.append("%s|%s:mutual" % [a, b])
			elif not a_can or not b_can:
				var loser: String = a if not a_can else b
				var winner: String = b if not a_can else a
				diplomacy.make_peace(a, b)
				diplomacy.adjust_score(winner, loser, -20.0)
				_gazette("WAR COLLAPSE",
					"%s crushes %s — their armies are broken. The war is over." % [winner.capitalize(), loser.capitalize()])
				ended.append("%s|%s:collapse" % [a, b])
	return ended


## --- AI offensive campaigns --------------------------------------------------
## Ports war32AiWarTick's gates: day >= 12, one evaluation per day,
## aggression threshold, no attacking allies/trade partners, multi-front
## reluctance, dogpile penalty, winnable-by-ESTIMATE, economic viability,
## then a 35% daily roll to actually march.

## AI Aggression effects (Jeremy 2026-10-03 co-owner design):
## low = defensive only (no offensive wars), normal = standard HTML
## behavior, high = earlier wars + higher roll chance + lower thresholds.
func _aggression_mods() -> Dictionary:
	var lvl: String = "normal"
	if _gs != null and _gs.settings.has("ai_aggression"):
		lvl = String(_gs.settings["ai_aggression"])
	match lvl:
		"low":
			return {"offensive": false, "min_day": 999999, "roll": 0.0, "threshold_mult": 2.0}
		"high":
			return {"offensive": true, "min_day": 6, "roll": 0.60, "threshold_mult": 0.7}
		_:
			return {"offensive": true, "min_day": AI_WAR_MIN_DAY, "roll": 0.35, "threshold_mult": 1.0}


func ai_war_tick() -> void:
	_ai_war_tick_c(_daily_census())


## Perf R30: census-backed AI war evaluation. Day gates, the per-faction
## loop order, and the RNG roll sites are unchanged.
func _ai_war_tick_c(c: Dictionary) -> void:
	var mods: Dictionary = _aggression_mods()
	if not bool(mods["offensive"]):
		return  # Peaceful AI never starts wars.
	if _gs.day_number < int(mods["min_day"]):
		return
	if _last_war_day == _gs.day_number:
		return
	_last_war_day = _gs.day_number
	if diplomacy == null:
		return
	var player: String = _gs.player_faction
	for f: String in Config.FACTIONS.keys():
		if f == player:
			continue  # the player declares their own wars
		var target: String = _consider_war_c(f, c)
		if target == "":
			continue
		if randf() > float(mods["roll"]):
			continue  # rare: even a justified war is a decision
		if target == player:
			_gazette("WAR DECLARED",
				"The %ss march at dawn. Your time is up." % f.capitalize())
		diplomacy.declare_war(f, target, "ai-hostility")
		# The faction's own brain ordering its own troops — bypasses the
		# player-facing sovereignty gate (Jeremy 2026-10-04: without this,
		# every AI war declared but deployed zero troops).
		_deploy_for_war_core(f, target)


## Returns the faction f should attack, or "" (the three gates, testable).
func consider_war(f: String) -> String:
	return _consider_war_c(f, _daily_census())


## Perf R30: census-backed war consideration. Gate order, thresholds,
## and the RNG roll site are unchanged; own/estimate reads are O(1).
func _consider_war_c(f: String, c: Dictionary) -> String:
	if diplomacy == null:
		return ""
	var traits: Dictionary = diplomacy.faction_traits(f)
	var aggro: float = float(traits.get("brave", 0.5)) * 100.0
	# AI Aggression (menu setting, Jeremy's co-owner design): the threshold
	# multiplier scales both the hate bar and the strength bar. High (0.7)
	# lowers both bars (easier wars); normal (1.0) is HTML behavior.
	var mult: float = float(_aggression_mods()["threshold_mult"])
	var war_t: float = (-30.0 - aggro * 0.25) * mult
	var own: Dictionary = _own_strength_c(f, c)
	var best := ""
	var best_score := 0.0
	for t: String in Config.FACTIONS.keys():
		if t == f:
			continue
		var rel: String = diplomacy.relation_state(f, t)
		if rel == "war" or rel == "allied" or rel == "trade":
			continue
		var sc: float = diplomacy.relation_score(f, t)
		if sc > war_t:
			continue
		# Multi-front reluctance: spread thin, raise the bar.
		var fronts: int = _war_count(f)
		if fronts > 0 and sc > war_t - 20.0 * fronts:
			continue
		# Dogpile penalty: ganging up on a foe fighting 2+ is dishonorable.
		if _war_count(t) >= 2 and sc > war_t - 15.0:
			continue
		# Liking the player prohibits attack, period.
		if t == _gs.player_faction and sc > 15.0:
			continue
		# Gate: winnable BY ESTIMATE (imperfect intel, never true state).
		var est: Dictionary = _estimate_strength_c(t, c)
		var need: float = (1.15 - aggro / 400.0) * mult
		if float(own["score"]) <= float(est["score"]) * need:
			continue
		# Gate: economic viability — expected gains cover estimated costs.
		var cost: float = maxf(1.0, float(own["score"])) * 0.8
		var gain: float = float(est["wealth"]) * 2.0 \
			+ float(est["def"]) * 1.5 + float(est["mil"]) * 0.5
		if gain < cost * 0.6:
			continue
		if best == "" or sc < best_score:
			best = t
			best_score = sc
	return best


func _war_count(faction: String) -> int:
	var n := 0
	if diplomacy == null:
		return 0
	for o: String in Config.FACTIONS.keys():
		if o == faction:
			continue
		if diplomacy.relation_state(faction, o) == "war":
			n += 1
	return n


## --- conquest: keep-or-rename ------------------------------------------------
## HTML queueConquestPrompt: a foreign hall falls while the player's combat
## troops are nearby -> the player conquered it -> prompt keep-or-rename.

func _on_building_destroyed(b: Dictionary) -> void:
	var btype: String = String(b.get("type", ""))
	if btype != "hall" and btype != "town_hall":
		return
	var player: String = _gs.player_faction
	if player == "" or String(b.get("faction", "")) == player:
		return
	var bpos: Vector2 = b.get("position", Vector2.ZERO)
	var found := false
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != player:
			continue
		if not SimCombat.is_fighter(u):
			continue
		if bpos.distance_squared_to(u.get("position", Vector2.ZERO)) \
				<= CONQUEST_RANGE * CONQUEST_RANGE:
			found = true
			break
	if not found:
		return
	_conquest_queue.append({
		"position": bpos,
		"old_name": String(b.get("town_name", "this settlement")),
		"town_id": int(b.get("town_id", -1)),
		"faction": String(b.get("faction", "")),
	})


## Oldest pending conquest prompt, or {}.
func pending_conquest() -> Dictionary:
	return _conquest_queue[0] if not _conquest_queue.is_empty() else {}


## Jeremy 2026-10-06 (Lane 3): a hall captured by FLIP (not destroyed)
## queues the same keep-or-rename prompt as a destroyed hall — via the
## command_post_captured signal (connected in _init). Same near-player-
## troops gate (CONQUEST_RANGE) as the destruction path.
func _on_post_captured(kind: String, post_id: int, old_h: String,
		new_h: String, pos: Vector2) -> void:
	if kind != "town":
		return
	var player: String = _gs.player_faction
	if player == "" or new_h != player:
		return
	var found := false
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if String(u.get("faction", "")) != player:
			continue
		if not SimCombat.is_fighter(u):
			continue
		if pos.distance_squared_to(u.get("position", Vector2.ZERO)) \
				<= CONQUEST_RANGE * CONQUEST_RANGE:
			found = true
			break
	if not found:
		return
	var b := _gs.get_building(post_id)
	_conquest_queue.append({
		"position": pos,
		"old_name": String(b.get("town_name", "this settlement")),
		"town_id": int(b.get("town_id", -1)),
		"faction": old_h,
	})


## Jeremy 2026-10-06: Command Posts — a hall captured by flip (not
## destroyed) queues the same keep-or-rename prompt. old_faction is the
## loser; b's faction is already the winner. (Kept for direct callers;
## the signal path above is the primary route.)
func queue_conquest_flip(b: Dictionary, old_faction: String) -> void:
	var bpos: Vector2 = b.get("position", Vector2.ZERO)
	_conquest_queue.append({
		"position": bpos,
		"old_name": String(b.get("town_name", "this settlement")),
		"town_id": int(b.get("town_id", -1)),
		"faction": old_faction,
	})


## Resolves the oldest prompt. Empty name = keep the old name (HTML:
## backdrop tap keeps the name). Returns the final name.
func resolve_conquest(new_name: String) -> String:
	if _conquest_queue.is_empty():
		return ""
	var item: Dictionary = _conquest_queue.pop_front()
	var final_name: String = new_name.strip_edges()
	if final_name == "":
		final_name = String(item.get("old_name", "this settlement"))
	var tid: int = int(item.get("town_id", -1))
	if _gs.towns.has(tid):
		(_gs.towns[tid] as Dictionary)["name"] = final_name
	_gazette("CONQUEST",
		"The conquered lands are renamed: %s." % final_name)
	return final_name


## --- weaponsmith upgrades ----------------------------------------------------
## 3 tiers at the weaponsmith (HTML weapon_up1/2/3); each is +8% damage.

func weapon_upgrade_cost(unit_id: int) -> Dictionary:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty():
		return {}
	var lvl: int = int(u.get("weapon_level", 0))
	if lvl >= SimCombat.MAX_WEAPON_LEVEL:
		return {}
	return SimCombat.WEAPON_UPGRADES[lvl]


## Jeremy 2026-10-05: the AI director arms its own troops through this with
## by_ai=true. Faction sovereignty refuses DIRECT CONTROL by the player, but
## a faction's own brain equipping its own soldiers is legitimate command —
## without this, AI armies fought at weapon level 0 forever while the
## player could sharpen up. Keeps the affordability checks identical.
func buy_weapon_upgrade(unit_id: int, by_ai: bool = false) -> bool:
	var u: Dictionary = _gs.get_unit(unit_id)
	if u.is_empty() or not u.get("alive", false):
		return false
	if not SimCombat.is_fighter(u):
		return false
	# Faction sovereignty: the player can't upgrade foreign troops.
	if not by_ai and _sovereignty_check(String(u.get("faction", ""))) != "":
		return false
	var cost: Dictionary = weapon_upgrade_cost(unit_id)
	if cost.is_empty():
		return false  # already maxed
	var faction: String = String(u.get("faction", ""))
	if not _gs.resources.can_afford(faction, cost):
		return false
	if not _gs.resources.spend(faction, cost):
		return false
	u["weapon_level"] = int(u.get("weapon_level", 0)) + 1
	return true


## --- army overview (for the ⚔ Army tab) --------------------------------------

func army_info(faction: String) -> Dictionary:
	var info := {"faction": faction, "stance": get_stance(faction),
		"troops": 0, "downed": 0, "warlord": false, "warlord_name": "",
		"at_war": [], "morale": 0.0, "strength": own_strength(faction),
		"jobs": {}, "avg_weapon_level": 0.0}
	var wsum := 0
	for u: Dictionary in _gs.units:
		if String(u.get("faction", "")) != faction:
			continue
		if not u.get("alive", false):
			continue
		if SimCombat.is_downed(u):
			info["downed"] = int(info["downed"]) + 1
			continue
		if not SimCombat.is_fighter(u):
			continue
		info["troops"] = int(info["troops"]) + 1
		var job: String = String(u.get("job", ""))
		info["jobs"][job] = int(info["jobs"].get(job, 0)) + 1
		wsum += int(u.get("weapon_level", 0))
		if bool(u.get("warlord", false)):
			info["warlord"] = true
			info["warlord_name"] = SimPersonality.display_name(u)
	if int(info["troops"]) > 0:
		info["avg_weapon_level"] = float(wsum) / float(info["troops"])
	if diplomacy != null:
		info["morale"] = diplomacy.morale_of(faction)
		var wars: Array[String] = []
		for o: String in Config.FACTIONS.keys():
			if o != faction and diplomacy.relation_state(faction, o) == "war":
				wars.append(o)
		info["at_war"] = wars
	return info


## --- daily census (perf R30) --------------------------------------------------
## The daily batch (government upkeep, collapse, AI war, retreats) used to
## run ~40 full O(units)/O(buildings) scans in a single frame (~5-8 ms
## spike at the 240-unit cap). _daily_census() makes ONE pass over units
## and ONE over buildings, bucketing everything the batch needs in
## _gs.units order (so best-hp tie-breaks pick the identical unit).
## All _census-backed _*_c() variants are behavior-identical to the
## public wrappers; the wrappers just build a throwaway census.
## Ephemeral (rebuilt per batch; never saved).

func _daily_census() -> Dictionary:
	# Perf R30: locals hoist the per-bucket dict lookups out of the
	# per-unit loop.
	var fighters := {}
	var field := {}
	var civ_pool := {}
	var fighter_pool := {}
	var guards := {}
	var guild_masters := {}
	var gov := {}
	var def_complete := {}
	var def_all := {}
	var bldg_all := {}
	var hostile_fighters := {}
	var facs: Array = Config.FACTIONS.keys()
	for f: String in facs:
		fighters[f] = []
		field[f] = []
		civ_pool[f] = []
		fighter_pool[f] = []
		guards[f] = []
		guild_masters[f] = []
		gov[f] = {}
		def_complete[f] = 0
		def_all[f] = 0
		bldg_all[f] = 0
		hostile_fighters[f] = []
	for u: Dictionary in _gs.units:
		var role := gov_role_of(u)
		if not u.get("alive", false):
			# Mirrors ensure_government's fallen-clearing pass: dead
			# holders are stripped before any have-map is computed, and
			# dead units take part in nothing else below.
			if role != "":
				clear_gov_role(u)
			continue
		var fac := String(u.get("faction", ""))
		if not fighters.has(fac):
			continue
		if role != "":
			(gov[fac] as Dictionary)[role] = u
		# Guards and guild masters: the original scans have NO downed
		# exclusion, so these pools are bucketed before the downed check.
		var job := String(u.get("job", ""))
		if job == "guard":
			(guards[fac] as Array).append(u)
		elif job == "guild_master":
			(guild_masters[fac] as Array).append(u)
		if bool(u.get("downed", false)):
			continue
		if SimCombat.is_fighter(u):
			(fighters[fac] as Array).append(u)
			if not bool(u.get("warlord", false)):
				(fighter_pool[fac] as Array).append(u)
			if bool(u.get("deployed_for_war", false)) \
				or bool(u.get("mustering", false)) \
				or u.has("monastery_march") or u.has("post_march"):
				(field[fac] as Array).append(u)
		else:
			(civ_pool[fac] as Array).append(u)
	for b: Dictionary in _gs.buildings:
		var fac := String(b.get("faction", ""))
		if not bldg_all.has(fac):
			continue
		bldg_all[fac] = int(bldg_all[fac]) + 1
		if String(b.get("type", "")) in DEFENSE_TYPES:
			def_all[fac] = int(def_all[fac]) + 1
			# own_strength counts complete defense buildings (no alive
			# check, matching the original scan exactly).
			if bool(b.get("complete", false)):
				def_complete[fac] = int(def_complete[fac]) + 1
	# Theater lists for _assess_retreats: per faction, the fighters that
	# count as hostile right now (same _is_hostile_to filter the old
	# per-candidate scan applied).
	for f: String in facs:
		var hf: Array = hostile_fighters[f]
		for g: String in facs:
			if _is_hostile_to(f, g):
				hf.append_array(fighters[g])
	return {
		"fighters": fighters, "field": field, "civ_pool": civ_pool,
		"fighter_pool": fighter_pool, "guards": guards,
		"guild_masters": guild_masters, "gov": gov,
		"def_complete": def_complete, "def_all": def_all,
		"bldg_all": bldg_all, "hostile_fighters": hostile_fighters,
	}


## --- daily tick ---------------------------------------------------------------

func tick(_delta: float) -> void:
	if _gs.day_number == _last_tick_day:
		return
	_last_tick_day = _gs.day_number
	# Perf R30: one census feeds the whole batch — the old code ran ~40
	# full unit/building scans here. Order of operations unchanged.
	var c := _daily_census()
	for f: String in Config.FACTIONS.keys():
		_ensure_government_c(f, c)
	_collapse_tick_c(c)
	_ai_war_tick_c(c)
	_assess_retreats_c(c)


func _gazette(headline: String, body: String) -> void:
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, headline, body, "war")
