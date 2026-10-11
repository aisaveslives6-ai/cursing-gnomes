class_name SimGarrison
extends RefCounted

## Cursing Gnomes — peacetime garrison AI (Jeremy 2026-10-04, AI-first phase).
##
## Port of the HTML build's c44TickGarrison + garrisonMilitaryNPC +
## militaryBaseHome (fix79): soldiers LIVE at the base during peacetime.
## Without this, needs/wander systems scatter fighters across the map and
## the base never has a garrison — so the first thing any AI defense does
## is recall troops that were never home.
##
## What it does, every 0.5 s (the HTML 30-frame throttle):
##   - For each faction NOT at war and NOT under threat (threat >= 1 is
##     owned by SimAIDirector._muster_defense; war is owned by the war
##     systems): find the base home (M-zone fort > barracks/war-unique/
##     field_camp > hall + offset, HTML militaryBaseHome order).
##   - Idle military units (combat jobs, never "guard" — the crime pipeline
##     owns guards and combat.gd leashes them to their post) are stationed
##     at the compound: defend_mode = true, walk back when beyond the
##     240px yard, idle-wander inside it when home.
##   - Yard threat response: a hostile inside 320px of home means the yard
##     is hot — far combat targets are dropped and combat's aggro takes
##     over; the garrison does NOT issue move orders that would fight it.
##
## Deliberate deviations from the HTML (documented, not redesigned):
##   - HTML teleports far units onto the base (c44 fix 38). Godot walks
##     them back via move_target instead — no pop-in, and the 0.5 s
##     re-assert is sticky enough to guarantee arrival.
##   - HTML's range-training / armory-buying while idle has no Godot
##     equivalent (no rangeSkill system); skipped. Needs are handled by
##     the Godot urge system (SimMind), so the HTML "needs tick on base"
##     block is not ported either — garrisoned troops eat/sleep via urges.
##   - HTML garrisons every race including the player's. Same here, but
##     units carrying an explicit player_order are never touched (advisor
##     mode: the AI runs the day-to-day, player orders win).
##
## Pure logic — no rendering, no input, no audio. Owned by World
## (game.garrison); tests construct SimGarrison.new(gs, combat) directly.
##
## UNIT FIELDS read/written: defend_mode, move_target, combat_target
## (all pre-existing unit-record fields).

const TICK_INTERVAL := 0.5        # HTML: c44TickGarrison 30-frame throttle
const YARD_R := 240.0             # HTML yardR — the compound radius
const YARD_SCAN_R := 320.0        # HTML yardR + 80 — enemy-in-yard scan
const STATION_R := 400.0          # HTML c44TickGarrison station radius
const DROP_TARGET_R := 340.0      # HTML yardR + 100 — far targets dropped
const IDLE_WANDER_R := 70.0       # HTML idle patrol spread (+-70)
const IDLE_WANDER_CHANCE := 0.03  # HTML 0.025, nudged for 2 Hz cadence
const HALL_OFFSET := Vector2(320, -180)  # HTML hall fallback offset

## HTML militaryBaseHome building preference order (verbatim types).
const HOME_BUILDINGS := ["barracks", "knights_castle", "war_hut",
	"mage_spire", "tome_library", "field_camp"]

var _gs  # GameState (untyped: avoids a core<->sim class cycle).
var _combat  # SimCombat — can_fight() hostility semantics.
var _accum := 0.0


func _init(game_state, combat_sim) -> void:
	_gs = game_state
	_combat = combat_sim


## World calls this every frame; the real work runs at 2 Hz.
func tick(delta: float) -> void:
	_accum += delta
	if _accum < TICK_INTERVAL:
		return
	_accum = 0.0
	_tick_garrison()


func _tick_garrison() -> void:
	if _gs.units.is_empty():
		return
	for faction: String in _gs.active_factions:
		if _at_war(faction):
			continue  # war systems own the troops (HTML raceAtWar skip)
		if _threat_level(faction) >= 1:
			continue  # director muster owns defense (HTML townThreatLevel skip)
		var home := _base_home(faction)
		if home == Vector2.INF:
			continue
		var yard_hot := _enemy_in_yard(faction, home)
		for u: Dictionary in _gs.units:
			_garrison_unit(u, faction, home, yard_hot)


func _garrison_unit(u: Dictionary, faction: String, home: Vector2,
		yard_hot: bool) -> void:
	if not bool(u.get("alive", false)):
		return
	if String(u.get("faction", "")) != faction:
		return
	var job: String = String(u.get("job", ""))
	if not JobDefs.is_military(job):
		return
	if job == "guard":
		return  # crime pipeline owns guards; combat.gd leashes them
	if not (u.get("player_order", {}) as Dictionary).is_empty():
		return  # explicit player orders always win (HTML playerOrder skip)
	if bool(u.get("mustering", false)):
		return  # muster system owns them (HTML _c44Mustering skip)
	if bool(u.get("withdrawing", false)):
		return  # retreat march preempts (SimMind._tick_withdraw)
	if bool(u.get("deployed_for_war", false)):
		return
	if int(u.get("deploy_target_id", -1)) >= 0:
		return
	if bool(u.get("fleeing", false)) or bool(u.get("flood_flee", false)):
		return
	if int(u.get("inside_building_id", 0)) > 0:
		return  # let them finish their business; stationed on exit
	if int(u.get("disaster_hunt_id", -1)) >= 0:
		return  # hunters are on a mission

	var upos: Vector2 = u.get("position", Vector2.ZERO)
	if yard_hot:
		# Enemy inside the wire: hold the yard, drop far targets, let
		# combat's aggro engage. No move orders — they would fight combat.
		u["defend_mode"] = true
		var tid: int = int(u.get("combat_target", -1))
		if tid >= 0:
			var t: Dictionary = _gs.get_unit(tid)
			if t.is_empty() or not bool(t.get("alive", false)):
				u["combat_target"] = -1
			else:
				var tpos: Vector2 = t.get("position", Vector2.ZERO)
				if tpos.distance_to(home) > DROP_TARGET_R:
					u["combat_target"] = -1
		return

	# Peacetime, yard clear: live on base.
	u["defend_mode"] = true
	var d: float = upos.distance_to(home)
	if d > YARD_R:
		# Walk back to the compound (HTML teleported; sticky re-assert
		# every 0.5 s guarantees arrival without pop-in).
		var ang := randf() * TAU
		var rr := randf_range(60.0, 180.0)
		u["move_target"] = home + Vector2(cos(ang), sin(ang)) * rr
		return
	# Home: idle wander inside the compound only.
	var arrived := true
	var mt_raw = u.get("move_target", null)
	if mt_raw is Vector2:
		arrived = upos.distance_to(mt_raw) < 12.0
	if arrived and randf() < IDLE_WANDER_CHANCE:
		u["move_target"] = home + Vector2(
			randf_range(-IDLE_WANDER_R, IDLE_WANDER_R),
			randf_range(-IDLE_WANDER_R, IDLE_WANDER_R))


## HTML militaryBaseHome: star-fort center > M-zone fort > military home
## building > hall + offset. Vector2.INF when the faction has no base at all.
func _base_home(faction: String) -> Vector2:
	# Jeremy 2026-10-06 (lane 7): a star fort IS the military base — station
	# troops there first, before HTML's militaryBaseHome fallback order.
	var sfb = _gs.get("starfort_bases")
	if sfb != null and sfb.has_method("fort_home"):
		var fh: Vector2 = sfb.fort_home(faction)
		if fh != Vector2.INF:
			return fh
	if _gs.zoning != null:
		var forts: Array = _gs.zoning.zones_of("M", faction)
		if not forts.is_empty():
			return (forts[0] as Dictionary).get("position", Vector2.INF)
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in HOME_BUILDINGS:
			return b.get("position", Vector2.INF)
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in ["hall", "town_hall"]:
			return b.get("position", Vector2.ZERO) + HALL_OFFSET
	return Vector2.INF


## Any hostile inside the yard scan radius (HTML enemyInYard, yardR + 80).
func _enemy_in_yard(faction: String, home: Vector2) -> bool:
	for e: Dictionary in _gs.units:
		if not bool(e.get("alive", false)):
			continue
		if bool(e.get("downed", false)):
			continue
		if String(e.get("faction", "")) == faction:
			continue
		if not _combat.can_fight(faction, String(e.get("faction", ""))):
			continue
		var epos: Vector2 = e.get("position", Vector2.ZERO)
		if epos.distance_to(home) <= YARD_SCAN_R:
			return true
	return false


func _at_war(faction: String) -> bool:
	if _gs.diplomacy == null:
		return false
	for o: String in _gs.active_factions:
		if o == faction:
			continue
		if _gs.diplomacy.relation_state(faction, o) == "war":
			return true
	return false


func _threat_level(faction: String) -> int:
	var ad = _gs.get("ai_director")
	if ad == null:
		return 0
	return int(ad.threat_level_of(faction))
