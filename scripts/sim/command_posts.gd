class_name SimCommandPosts
extends RefCounted
## Cursing Gnomes — Command Posts (Jeremy 2026-10-06, Battlefront directive).
##
## Towns (halls), monasteries, and dark crystals are ALL command posts.
## Each has a holder faction; capturing one flips the holder AND the land
## around it (Rise of Nations-style territory). The AI plays them like
## Star Wars Battlefront: assault enemy-held posts, reinforce threatened
## own posts, prioritize by value.
##
## Post record (derived live, never stored):
##   {kind: "town"|"monastery"|"crystal", id, position, holder, name, radius}
## Capture log (persisted): every flip, for the war-score / Ruler's Voice API.

## Territory radius claimed by each post type while held (world px).
## Towns use the HTML TERRITORY_R (520); monasteries match it (major);
## crystals are wild outposts with a smaller footprint.
const TOWN_R := 520.0
const MONASTERY_R := 520.0
const CRYSTAL_R := 400.0

## Strategic value for AI targeting (monastery > town > crystal).
const VALUE := {"monastery": 3.0, "town": 2.0, "crystal": 1.0}

var _gs = null  # GameState (untyped: sim <-> core cycle)

## Capture log: Array of {day, kind, post_id, old_holder, new_holder,
## position, name}. Persisted in save/load.
var capture_log: Array = []


func setup(game) -> void:
	_gs = game
	# Daily postworks cadence (supply, sieges, auras, garrisons, AI).
	if not _day_hooked and _gs != null and _gs.get("bus") != null:
		_gs.bus.day_changed.connect(_on_day)
		_day_hooked = true


## ---- unified post model ---------------------------------------------------

## All command posts on the map right now, derived live from buildings,
## monasteries, and crystals. holder == "" means unclaimed wild post.
func posts_of() -> Array:
	var out: Array = []
	if _gs == null:
		return out
	# Towns: completed, alive halls.
	for b in _gs.buildings:
		var bd := b as Dictionary
		if bd.is_empty():
			continue
		if not bool(bd.get("alive", false)):
			continue
		if not bool(bd.get("complete", false)):
			continue
		if not String(bd.get("type", "")) in SimTerritory.CLAIM_TYPES:
			continue
		out.append({
			"kind": "town",
			"id": int(bd.get("id", 0)),
			"position": bd.get("position", Vector2.ZERO),
			"holder": String(bd.get("faction", "")),
			"name": str(bd.get("town_name",
				bd.get("name", "Town"))),
			"radius": TOWN_R,
		})
	# Monasteries.
	var mons = _gs.get("monasteries")
	if mons != null and "monasteries" in mons:
		for m in mons.monasteries:
			var md := m as Dictionary
			if md.is_empty():
				continue
			out.append({
				"kind": "monastery",
				"id": int(md.get("id", 0)),
				"position": md.get("position", Vector2.ZERO),
				"holder": String(md.get("owner", "")),
				"name": String(md.get("name", "Monastery")),
				"radius": MONASTERY_R,
			})
	# Dark crystals.
	var crys = _gs.get("crystals")
	if crys != null and "crystals" in crys:
		for c in crys.crystals:
			var cd := c as Dictionary
			if cd.is_empty():
				continue
			out.append({
				"kind": "crystal",
				"id": int(cd.get("id", 0)),
				"position": cd.get("position", Vector2.ZERO),
				"holder": String(cd.get("owner", "")),
				"name": String(cd.get("name", "Dark Crystal")),
				"radius": CRYSTAL_R,
			})
	# Postworks enrichment: garrison / upgrade / supply / siege / aura —
	# the post UI data contract. One shared unit scan for garrison counts.
	var gcounts := _garrison_counts()
	for p in out:
		_enrich_post(p as Dictionary, gcounts)
	return out


## Attach the postworks UI fields to a post record (additive — the base
## model above is untouched).
func _enrich_post(p: Dictionary, gcounts: Dictionary) -> void:
	if p.is_empty():
		return
	var kind := String(p.get("kind", ""))
	var pid := int(p.get("id", 0))
	var key := _post_key(kind, pid)
	p["garrison"] = int(gcounts.get(key, 0))
	p["upgrade"] = upgrade_level(kind, pid)
	p["supply"] = supply_of(kind, pid)
	p["siege"] = sieges.get(key, {})
	p["aura"] = _aura_label(kind)


## Posts currently held by a faction (holder == faction).
func holdings_of(faction: String) -> Array:
	var out: Array = []
	for p in posts_of():
		if String(p.get("holder", "")) == faction:
			out.append(p)
	return out


## Count of posts held, by kind: {"town": n, "monastery": n, "crystal": n}.
func holding_counts(faction: String) -> Dictionary:
	var counts := {"town": 0, "monastery": 0, "crystal": 0}
	for p in holdings_of(faction):
		var k: String = String(p.get("kind", ""))
		if counts.has(k):
			counts[k] = int(counts[k]) + 1
	return counts


## ---- territory ------------------------------------------------------------

## Flat claimant list for territory checks: {position, faction, radius}.
## Held monasteries and crystals claim land exactly like halls do;
## capturing one flips the claim.
func claimants_of() -> Array:
	var out: Array = []
	for p in posts_of():
		var holder: String = String(p.get("holder", ""))
		if holder == "":
			continue
		out.append({
			"position": p.get("position", Vector2.ZERO),
			"faction": holder,
			"radius": float(p.get("radius", TOWN_R)),
		})
	return out


## Faction owning the ground at pos (nearest claimant), or "".
static func owner_at(claimants: Array, pos: Vector2) -> String:
	var best := ""
	var best_d := INF
	for c in claimants:
		var cd := c as Dictionary
		if cd.is_empty():
			continue
		var d: float = pos.distance_to(
			cd.get("position", Vector2.ZERO))
		var r: float = float(cd.get("radius", TOWN_R))
		if d < r and d < best_d:
			best_d = d
			best = String(cd.get("faction", ""))
	return best


## Null-safe claimant fetch for static call sites (build placement).
## Returns [] when the system isn't wired (bare tests, old saves).
static func claimants_of_game(gs) -> Array:
	if gs == null:
		return []
	var cps = gs.get("command_posts")
	if cps != null and cps.has_method("claimants_of"):
		return cps.claimants_of()
	return []


## ---- capture log (war-score / Ruler's Voice API) ----------------------------

## Record a capture. Called by monastery/crystal _capture and hall flips.
func log_capture(kind: String, post_id: int, old_holder: String,
		new_holder: String, position: Vector2, post_name: String) -> void:
	var entry := {
		"day": int(_gs.get("day_number")) if _gs != null else 0,
		"kind": kind,
		"post_id": post_id,
		"old_holder": old_holder,
		"new_holder": new_holder,
		"position": position,
		"name": post_name,
	}
	capture_log.append(entry)
	# Cap the log; ancient history doesn't drive war scores.
	while capture_log.size() > 200:
		capture_log.pop_front()
	if _gs != null and _gs.get("bus") != null:
		_gs.bus.command_post_captured.emit(kind, post_id, old_holder,
			new_holder, position)


## Command-post changes between two factions (either direction) since a day.
## For the Ruler's Voice war-score: who lost what to whom.
func war_post_changes(faction_a: String, faction_b: String,
		since_day: int = 0) -> Array:
	var out: Array = []
	for e in capture_log:
		var ed := e as Dictionary
		if ed.is_empty():
			continue
		if int(ed.get("day", 0)) < since_day:
			continue
		var o: String = String(ed.get("old_holder", ""))
		var n: String = String(ed.get("new_holder", ""))
		var pair := [o, n]
		if faction_a in pair and faction_b in pair and o != n:
			out.append(ed)
	return out


## Net post swing for faction_a vs faction_b since a day: positive means
## faction_a is GAINING posts (winning the land war), negative = losing.
func post_swing(faction_a: String, faction_b: String,
		since_day: int = 0) -> float:
	var swing := 0.0
	for e in war_post_changes(faction_a, faction_b, since_day):
		var ed := e as Dictionary
		var w: float = float(VALUE.get(String(ed.get("kind", "town")),
			1.0))
		if String(ed.get("new_holder", "")) == faction_a:
			swing += w
		else:
			swing -= w
	return swing


## ---- persistence ------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"capture_log": capture_log.duplicate(true),
		"upgrades": upgrades.duplicate(true),
		"supply": supply.duplicate(true),
		"sieges": sieges.duplicate(true),
		"garrison_orders": garrison_orders.duplicate(true),
		"feint_day": _feint_day.duplicate(true),
		"siege_proposed": _siege_proposed.duplicate(true),
		"note_day": _note_day.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	capture_log.clear()
	for e in d.get("capture_log", []):
		var ed := e as Dictionary
		if ed.is_empty():
			continue
		capture_log.append(ed)
	# Postworks state (missing keys = fresh game / old save: defaults).
	upgrades = (d.get("upgrades", {}) as Dictionary).duplicate(true)
	supply = (d.get("supply", {}) as Dictionary).duplicate(true)
	sieges = (d.get("sieges", {}) as Dictionary).duplicate(true)
	garrison_orders = (d.get("garrison_orders", {}) as Dictionary
		).duplicate(true)
	_feint_day = (d.get("feint_day", {}) as Dictionary).duplicate(true)
	_siege_proposed = (d.get("siege_proposed", {}) as Dictionary
		).duplicate(true)
	_note_day = (d.get("note_day", {}) as Dictionary).duplicate(true)


## ===========================================================================
## Lane 3 expansion — Postworks (Jeremy 2026-10-06, Battlefront expansion).
##
##  1. GARRISONS — player/AI station troops at posts via assign_garrison()
##     (the "garrison" order). Garrisoned troops hold the post and engage
##     enemies through the standard combat aggro scan; the order is sticky
##     (player_order channel) so the base-garrison AI, weapon-smith trips,
##     and the AI director never poach them. Shown in post UI via the
##     "garrison" count on every post record.
##  2. UPGRADES — palisade -> stone walls -> watchtower per post, bought
##     with wood/gold. Towns gain max HP; monasteries/crystals take longer
##     to capture; watchtowers widen auras and ward their garrison.
##  3. AURAS — held monastery: faith ward + morale for nearby friendlies;
##     held dark crystal: arcane attunement (mages' dark magic recharges
##     faster and hits harder); held town hall: market tithe (gold/day).
##  4. SIEGES — besieged posts lose supply/integrity over days; the
##     ATTACKER picks assault vs starve through the strategic-proposal
##     flow (new "siege_choice" kind, proposal-gated). Starved-out posts
##     are captured: halls flip at the 25% keep-or-rename flow, monasteries
##     and crystals via their capture rites.
##  5. SUPPLY — posts burn supply daily (garrisons eat); AI runs wagon
##     resupply to threatened posts; starving garrisons desert.
##  6. FEINTS — at war, the AI probes a weak/low-value post with a small
##     force to draw defenders, then concentrates on the high-value prize.
##     VALUE order kept: monastery > town > crystal.
## ===========================================================================

## Upgrade path per post: 0 none -> 1 palisade -> 2 stone walls -> 3 watchtower.
const UPGRADE_NAMES := ["None", "Palisade", "Stone Walls", "Watchtower"]
const UPGRADE_COSTS := [
	{"wood": 120.0, "gold": 60.0},
	{"wood": 250.0, "gold": 150.0},
	{"wood": 300.0, "gold": 250.0},
]
const MAX_UPGRADE := 3
const HP_PER_LEVEL := 0.30        # towns: +30% hall max HP per level
const CAPTURE_SLOW_PER_LEVEL := 0.5  # monasteries/crystals: +50% capture time/level
const WATCHTOWER_AURA_MULT := 1.25
const GARRISON_CAP_BASE := 6
const GARRISON_CAP_PER_LEVEL := 2

## Supply: every held post burns it daily; garrisons eat extra.
const SUPPLY_MAX := 100.0
const SUPPLY_DRAIN_BASE := 1.0
const SUPPLY_DRAIN_PER_TROOP := 0.5
const SUPPLY_SIEGE_STARVE := 12.0
const SUPPLY_SIEGE_ASSAULT := 6.0
const SUPPLY_SIEGE_UNDECIDED := 8.0
const SUPPLY_LOW := 40.0
const SUPPLY_WAGON_COST := {"food": 8.0, "gold": 4.0}
const SUPPLY_WAGON_AMOUNT := 35.0

## Sieges: detected when war-enemy troops mass around a held post.
const SIEGE_MIN_ATTACKERS := 3
const SIEGE_DETECT_R_MULT := 0.8
const SIEGE_INTEGRITY_STARVE := 8.0
const SIEGE_INTEGRITY_ASSAULT := 4.0
const SIEGE_INTEGRITY_UNDECIDED := 5.0
const SIEGE_INTEGRITY_SAVE_PER_LEVEL := 0.15  # upgrades slow the grind
const SIEGE_HALL_CHIP := 0.02   # besieged hall loses 2% max HP / day
const SIEGE_LIFT_QUIET_DAYS := 2
const SIEGE_PROPOSE_COOLDOWN := 5

## Garrisons.
const GARRISON_DEFAULT := 4
const GARRISON_DESERT_CHANCE := 0.15

## Feints: small probe at a weak post, main blow at the prize.
const FEINT_DAYS := 3
const FEINT_FORCE := 3
const FEINT_MIN_ARMY := 12
const FEINT_COOLDOWN := 4
const FEINT_TOPUP := 4  # extra troops concentrated on the main target

## Auras.
const AURA_MORALE_MIN_BLESSED := 3
const AURA_WARD_HP := 30.0
const AURA_WARD_PER_LEVEL := 10.0
const TOWN_TITHE_GOLD := 8.0
const TOWN_TITHE_PER_LEVEL := 4.0

## Persisted postworks state (all keyed "kind:id").
var upgrades: Dictionary = {}        # -> int level 0..3
var supply: Dictionary = {}          # -> float 0..100
var sieges: Dictionary = {}          # -> {attacker, mode, days, supply,
	# integrity, quiet, kind, post_id, post_name, holder}
var garrison_orders: Dictionary = {} # -> {faction, anchor}
# AI bookkeeping (persisted so cooldowns survive save/load).
var _feint_day: Dictionary = {}      # faction -> day of last feint
var _siege_proposed: Dictionary = {} # "siege_choice|faction|kind|id" -> day
var _note_day: Dictionary = {}       # "key" -> day (Gazette throttling)
var _day_hooked := false
var _leash_accum := 0.0


func _post_key(kind: String, pid: int) -> String:
	return "%s:%d" % [kind, pid]


## Daily cadence: supply, sieges, auras, garrisons, AI post strategy.
## Hooked to bus.day_changed in setup (no world.gd edit needed).
func _on_day(day: int, _is_night: bool) -> void:
	daily_tick()


func daily_tick() -> void:
	if _gs == null:
		return
	var day := int(_gs.get("day_number"))
	_prune_garrisons()
	_expire_feints(day)
	_tick_supply(day)
	_tick_sieges(day)
	_tick_auras(day)
	_tick_garrison_leash()
	_ai_post_strategy()


## Sub-daily leash for garrisoned troops (wired if world ticks us;
## daily_tick also re-pins, so this is polish, not load-bearing).
func tick(delta: float) -> void:
	if _gs == null:
		return
	_leash_accum += delta
	if _leash_accum >= 2.0:
		_leash_accum = 0.0
		_tick_garrison_leash()


## One-line Gazette helper.
func _gazette(headline: String, body: String,
		kind: String = "war") -> void:
	if _gs == null or _gs.get("bus") == null:
		return
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs, headline, body, kind)


## Throttled Gazette: at most one story per key per day.
func _gazette_throttled(key: String, headline: String, body: String,
		kind: String = "war") -> void:
	var day := int(_gs.get("day_number")) if _gs != null else 0
	if int(_note_day.get(key, -99)) >= day:
		return
	_note_day[key] = day
	_gazette(headline, body, kind)


## War check with the legacy free-for-all fallback (matches SimCombat).
func _hostile_to(a: String, b: String) -> bool:
	if a == "" or b == "" or a == b:
		return false
	var dip = _gs.get("diplomacy") if _gs != null else null
	if dip != null and dip.has_method("relation_state"):
		return String(dip.relation_state(a, b)) == "war"
	return true


## Refusal line for direct-control attempts on foreign factions
## (mirrors SimArmy._sovereignty_check).
func _refuse_line(faction: String) -> String:
	var fl = _gs.get("faction_leaders") if _gs != null else null
	if fl != null and fl.has_method("refuse_direct_control"):
		return String(fl.refuse_direct_control(faction))
	return "You have no authority over our forces."


## Sovereignty gate for player-issued post orders. by_player=false is the
## faction's own brain commanding its own troops (command, not control).
func _order_allowed(faction: String, by_player: bool) -> Dictionary:
	if not by_player:
		return {"ok": true}
	if _gs == null:
		return {"ok": true}
	var pf := String(_gs.player_faction)
	if pf != "" and faction != pf:
		return {"ok": false, "reason": _refuse_line(faction)}
	return {"ok": true}


## Live military units of a faction.
func _military_of(faction: String) -> Array:
	var out: Array = []
	if _gs == null:
		return out
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty():
			continue
		if not bool(ud.get("alive", false)):
			continue
		if String(ud.get("faction", "")) != faction:
			continue
		if not JobDefs.is_military(String(ud.get("job", ""))):
			continue
		out.append(ud)
	return out


## Idle military: no orders, no marks, no deployment — free for assignment.
func _idle_military(faction: String) -> Array:
	var out: Array = []
	for ud in _military_of(faction):
		if not (ud.get("player_order", {}) as Dictionary).is_empty():
			continue
		if int(ud.get("deploy_target_id", -1)) >= 0:
			continue
		if bool(ud.get("deployed_for_war", false)):
			continue
		if ud.has("post_march") or ud.has("post_guard") \
				or ud.has("post_garrison"):
			continue
		if ud.has("monastery_march") or ud.has("monastery_guard"):
			continue
		out.append(ud)
	return out


## Find a live post record by kind+id (kinds have separate id namespaces).
func find_post(kind: String, pid: int) -> Dictionary:
	for p in posts_of():
		if String(p.get("kind", "")) == kind \
				and int(p.get("id", 0)) == pid:
			return p
	return {}


## Find the underlying record a post is derived from (hall building,
## monastery, or crystal dict) so upgrades can touch real HP.
func _post_record(kind: String, pid: int) -> Dictionary:
	if _gs == null:
		return {}
	if kind == "town":
		return _gs.get_building(pid) if _gs.has_method("get_building") \
			else {}
	var mons = _gs.get("monasteries")
	if kind == "monastery" and mons != null:
		for m in mons.monasteries:
			var md := m as Dictionary
			if not md.is_empty() and int(md.get("id", -1)) == pid:
				return md
	var crys = _gs.get("crystals")
	if kind == "crystal" and crys != null:
		for c in crys.crystals:
			var cd := c as Dictionary
			if not cd.is_empty() and int(cd.get("id", -1)) == pid:
				return cd
	return {}

## ---- garrisons ---------------------------------------------------------------

## Station troops at a post ("garrison" order). Garrisoned troops hold the
## post and engage enemies through the standard combat aggro scan; the
## order rides the player_order channel so base garrisons, smith trips,
## and the AI director never poach them. by_player=false is the faction's
## own brain (AI) commanding its own troops.
## Returns {ok, assigned} or {ok:false, reason}.
func assign_garrison(faction: String, kind: String, post_id: int,
		unit_ids: Array = [], by_player: bool = true) -> Dictionary:
	var allow := _order_allowed(faction, by_player)
	if not bool(allow.get("ok", false)):
		return allow
	var post := find_post(kind, post_id)
	if post.is_empty():
		return {"ok": false, "reason": "no such post"}
	if String(post.get("holder", "")) != faction:
		return {"ok": false, "reason": "post not held"}
	var lvl := upgrade_level(kind, post_id)
	var cap := GARRISON_CAP_BASE + GARRISON_CAP_PER_LEVEL * lvl
	var cur := _garrison_count(kind, post_id)
	var room := cap - cur
	if room <= 0:
		return {"ok": false, "reason": "garrison full"}
	var pos: Vector2 = post.get("position", Vector2.ZERO)
	var picked: Array = []
	if unit_ids.is_empty():
		for ud in _idle_military(faction):
			if picked.size() >= mini(room, GARRISON_DEFAULT):
				break
			picked.append(ud)
	else:
		for uid in unit_ids:
			if picked.size() >= room:
				break
			var ud: Dictionary = _gs.get_unit(int(uid)) \
				if _gs.has_method("get_unit") else {}
			if ud.is_empty() or not bool(ud.get("alive", false)):
				continue
			if String(ud.get("faction", "")) != faction:
				continue
			if not JobDefs.is_military(String(ud.get("job", ""))):
				continue
			if ud.has("post_garrison"):
				continue
			picked.append(ud)
	var n := 0
	for ud in picked:
		ud["post_garrison"] = {"kind": kind, "id": post_id}
		ud["player_order"] = {"kind": "garrison", "post_kind": kind,
			"post_id": post_id}
		ud["move_target"] = pos + Vector2(randf_range(-50.0, 50.0),
			randf_range(-50.0, 50.0))
		n += 1
	if n > 0:
		garrison_orders[_post_key(kind, post_id)] = {
			"faction": faction, "anchor": pos}
	return {"ok": true, "assigned": n}


## Recall a garrison: the order lifts, troops return to the pool.
func recall_garrison(faction: String, kind: String, post_id: int,
		by_player: bool = true) -> Dictionary:
	var allow := _order_allowed(faction, by_player)
	if not bool(allow.get("ok", false)):
		return allow
	var n := 0
	for ud in garrison_of(kind, post_id):
		if String(ud.get("faction", "")) != faction:
			continue
		_clear_garrison_marks(ud)
		n += 1
	garrison_orders.erase(_post_key(kind, post_id))
	return {"ok": true, "recalled": n}


## Clear garrison marks from one unit (desertion, recall, death cleanup).
func _clear_garrison_marks(ud: Dictionary) -> void:
	ud.erase("post_garrison")
	var po := ud.get("player_order", {}) as Dictionary
	if String(po.get("kind", "")) == "garrison":
		ud.erase("player_order")


## Live garrisoned units at a post.
func garrison_of(kind: String, pid: int) -> Array:
	var out: Array = []
	if _gs == null:
		return out
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		var pg := ud.get("post_garrison", {}) as Dictionary
		if String(pg.get("kind", "")) == kind \
				and int(pg.get("id", -1)) == pid:
			out.append(ud)
	return out


## Garrison counts for every post in ONE unit scan (posts_of enrichment).
func _garrison_counts() -> Dictionary:
	var counts := {}
	if _gs == null:
		return counts
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		var pg := ud.get("post_garrison", {}) as Dictionary
		if pg.is_empty():
			continue
		var key := _post_key(String(pg.get("kind", "")),
			int(pg.get("id", -1)))
		counts[key] = int(counts.get(key, 0)) + 1
	return counts


func _garrison_count(kind: String, pid: int) -> int:
	return int(_garrison_counts().get(_post_key(kind, pid), 0))


## Drop order records whose post is gone or changed hands.
func _prune_garrisons() -> void:
	var drop: Array = []
	for key in garrison_orders.keys():
		var parts := String(key).split(":")
		if parts.size() != 2:
			drop.append(key)
			continue
		var post := find_post(parts[0], int(parts[1]))
		var go := garrison_orders[key] as Dictionary
		if post.is_empty() or String(post.get("holder", "")) \
				!= String(go.get("faction", "")):
			drop.append(key)
	for key in drop:
		garrison_orders.erase(key)


## Daily leash: garrisoned troops that chased a foe too far get walked
## back to their post; shopping trips are cancelled (the order holds).
func _tick_garrison_leash() -> void:
	if _gs == null:
		return
	for key in garrison_orders.keys():
		var parts := String(key).split(":")
		if parts.size() != 2:
			continue
		var kind := parts[0]
		var pid := int(parts[1])
		var post := find_post(kind, pid)
		if post.is_empty():
			continue
		var pos: Vector2 = post.get("position", Vector2.ZERO)
		var r := float(post.get("radius", TOWN_R))
		for ud in garrison_of(kind, pid):
			if ud.has("_smith_id"):
				ud.erase("_smith_id")  # garrison holds; no shopping
			if int(ud.get("combat_target", -1)) >= 0:
				continue  # mid-fight: combat owns them
			var upos: Vector2 = ud.get("position", Vector2.ZERO)
			if upos.distance_to(pos) > r:
				ud["move_target"] = pos + Vector2(
					randf_range(-50.0, 50.0), randf_range(-50.0, 50.0))


## Starving garrisons desert: the order breaks, troops walk.
func _starvation_desertion(kind: String, pid: int, day: int) -> void:
	var deserted := 0
	for ud in garrison_of(kind, pid):
		if randf() < GARRISON_DESERT_CHANCE:
			_clear_garrison_marks(ud)
			deserted += 1
	if deserted > 0:
		var post := find_post(kind, pid)
		_gazette_throttled("desert|%s|%d" % [kind, pid],
			"Desertion at %s" % String(post.get("name", "the post")),
			"Hungry soldiers abandon %s — no supply, no loyalty." \
				% String(post.get("name", "the post")))

## ---- upgrades ----------------------------------------------------------------

## Current upgrade level of a post (0..3).
func upgrade_level(kind: String, pid: int) -> int:
	return clampi(int(upgrades.get(_post_key(kind, pid), 0)), 0,
		MAX_UPGRADE)


## Cost to go from `level` to `level+1`; {} when maxed.
func upgrade_cost(level: int) -> Dictionary:
	if level < 0 or level >= MAX_UPGRADE:
		return {}
	return (UPGRADE_COSTS[level] as Dictionary).duplicate()


## Capture-time multiplier for monasteries/crystals (read live by those
## systems): upgraded posts take longer to take.
func capture_time_mult(kind: String, pid: int) -> float:
	return 1.0 + CAPTURE_SLOW_PER_LEVEL * float(upgrade_level(kind, pid))


## Upgrade a held post: palisade -> stone walls -> watchtower. Spends the
## holder's wood/gold. Towns gain hall HP; monasteries/crystals slow
## capture; watchtowers widen auras and ward their garrison.
func upgrade_post(faction: String, kind: String, post_id: int,
		by_player: bool = true) -> Dictionary:
	var allow := _order_allowed(faction, by_player)
	if not bool(allow.get("ok", false)):
		return allow
	var post := find_post(kind, post_id)
	if post.is_empty():
		return {"ok": false, "reason": "no such post"}
	if String(post.get("holder", "")) != faction:
		return {"ok": false, "reason": "post not held"}
	var lvl := upgrade_level(kind, post_id)
	if lvl >= MAX_UPGRADE:
		return {"ok": false, "reason": "fully upgraded"}
	var cost := upgrade_cost(lvl)
	var res = _gs.get("resources") if _gs != null else null
	if res == null or not res.has_method("spend"):
		return {"ok": false, "reason": "no treasury"}
	if not bool(res.can_afford(faction, cost)):
		return {"ok": false, "reason": "cannot afford"}
	res.spend(faction, cost)
	upgrades[_post_key(kind, post_id)] = lvl + 1
	if kind == "town":
		_apply_town_hp_upgrade(post_id, lvl)
	var uname: String = UPGRADE_NAMES[lvl + 1]
	_gazette("%s raised at %s" % [uname, String(post.get("name", "post"))],
		"%s's engineers raise %s around %s — its defenses harden." % [
			_fname(faction), uname.to_lower(),
			String(post.get("name", "the post"))],
		"build")
	return {"ok": true, "level": lvl + 1, "name": uname}


## Towns: each level adds HP_PER_LEVEL max HP and heals the difference.
func _apply_town_hp_upgrade(hall_id: int, _old_level: int) -> void:
	var hall := _post_record("town", hall_id)
	if hall.is_empty():
		return
	var max_hp := float(hall.get("max_hp", hall.get("hp", 1200.0)))
	var new_max := max_hp * (1.0 + HP_PER_LEVEL)
	hall["max_hp"] = new_max
	hall["hp"] = minf(new_max,
		float(hall.get("hp", max_hp)) + max_hp * HP_PER_LEVEL)


func _fname(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))


## ---- auras -------------------------------------------------------------------

## Aura label for post UI.
func _aura_label(kind: String) -> String:
	match kind:
		"monastery":
			return "Faith ward + morale"
		"crystal":
			return "Arcane attunement"
		"town":
			return "Market tithe"
	return ""


## Daily aura pass: held posts bless their surroundings.
func _tick_auras(day: int) -> void:
	if _gs == null:
		return
	var dip = _gs.get("diplomacy")
	var blessed := {}  # faction -> blessed unit count (morale gate)
	for p in posts_of():
		var holder := String(p.get("holder", ""))
		if holder == "":
			continue
		var kind := String(p.get("kind", ""))
		var pid := int(p.get("id", 0))
		var pos: Vector2 = p.get("position", Vector2.ZERO)
		var lvl := upgrade_level(kind, pid)
		var r := float(p.get("radius", TOWN_R))
		if lvl >= MAX_UPGRADE:
			r *= WATCHTOWER_AURA_MULT
		if kind == "monastery":
			blessed[holder] = int(blessed.get(holder, 0)) \
				+ _monastery_aura(holder, pos, r, lvl, day)
		elif kind == "crystal":
			_crystal_aura(holder, pos, r, day)
		elif kind == "town":
			_town_aura(holder, lvl)
	# Faith made manifest: enough blessed faithful lifts faction morale.
	if dip != null and dip.has_method("adjust_morale"):
		for f in blessed.keys():
			if int(blessed[f]) >= AURA_MORALE_MIN_BLESSED:
				dip.adjust_morale(String(f), 1.0)


## Held monastery: nearby friendlies get the faith ward (combat's
## absorb_shield consumes shield_hp/shield_t) + the faith_aura mark.
## Returns the blessed count (morale gate).
func _monastery_aura(holder: String, pos: Vector2, r: float, lvl: int,
		day: int) -> int:
	var n := 0
	var ward := AURA_WARD_HP + AURA_WARD_PER_LEVEL * float(lvl)
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		if String(ud.get("faction", "")) != holder:
			continue
		if pos.distance_to(ud.get("position", Vector2.ZERO)) > r:
			continue
		ud["faith_aura"] = day
		ud["shield_hp"] = maxf(float(ud.get("shield_hp", 0.0)), ward)
		ud["shield_t"] = maxf(float(ud.get("shield_t", 0.0)), 86400.0)
		n += 1
	return n


## Held dark crystal: nearby friendly MAGES attune — their dark magic
## recharges twice as fast and hits 25% harder (dark_crystals.gd honors
## the crystal_attuned mark). Arcane research, weaponized.
func _crystal_aura(holder: String, pos: Vector2, r: float, day: int) -> void:
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		if String(ud.get("faction", "")) != holder:
			continue
		if String(ud.get("job", "")) != "mage":
			continue
		if pos.distance_to(ud.get("position", Vector2.ZERO)) > r:
			continue
		ud["crystal_attuned"] = day


## Held town hall: the market tithe — gold into the holder's treasury.
func _town_aura(holder: String, lvl: int) -> void:
	var res = _gs.get("resources")
	if res == null or not res.has_method("add_resource"):
		return
	res.add_resource(holder, "gold",
		TOWN_TITHE_GOLD + TOWN_TITHE_PER_LEVEL * float(lvl))

## ---- supply --------------------------------------------------------------------

## Supply stockpile of a post (0..100). Held posts start full.
func _supply_raw(kind: String, pid: int) -> float:
	return float(supply.get(_post_key(kind, pid), SUPPLY_MAX))


func supply_of(kind: String, pid: int) -> float:
	return clampf(_supply_raw(kind, pid), 0.0, SUPPLY_MAX)


## Troops eating at each post: garrison + guard rotations.
func _stationed_counts() -> Dictionary:
	var counts := {}
	if _gs == null:
		return counts
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		var key := ""
		var pg := ud.get("post_garrison", {}) as Dictionary
		if not pg.is_empty():
			key = _post_key(String(pg.get("kind", "")),
				int(pg.get("id", -1)))
		else:
			var grd := ud.get("post_guard", {}) as Dictionary
			if not grd.is_empty():
				key = _post_key(String(grd.get("kind", "")),
					int(grd.get("id", -1)))
		if key != "" and key != ":":
			counts[key] = int(counts.get(key, 0)) + 1
	return counts


## Daily: posts burn supply; low posts get wagon resupply; empty posts
## starve their garrisons into desertion.
func _tick_supply(day: int) -> void:
	var stationed := _stationed_counts()
	for p in posts_of():
		var holder := String(p.get("holder", ""))
		if holder == "":
			continue
		var kind := String(p.get("kind", ""))
		var pid := int(p.get("id", 0))
		var key := _post_key(kind, pid)
		var sup := _supply_raw(kind, pid)
		var drain := SUPPLY_DRAIN_BASE + SUPPLY_DRAIN_PER_TROOP \
			* float(stationed.get(key, 0))
		var s: Dictionary = sieges.get(key, {})
		if not s.is_empty():
			var mode := String(s.get("mode", "undecided"))
			if mode == "starve":
				drain += SUPPLY_SIEGE_STARVE
			elif mode == "assault":
				drain += SUPPLY_SIEGE_ASSAULT
			else:
				drain += SUPPLY_SIEGE_UNDECIDED
		sup = maxf(0.0, sup - drain)
		supply[key] = sup
		_resupply_post(holder, p, key, sup)
		if sup <= 0.0:
			_starvation_desertion(kind, pid, day)


## Wagon resupply: the holder spends food+gold to refill a low post.
## AI factions run this freely; the player's advisers never spend
## (sovereignty — the ruler orders wagons via the garrison/supply UI).
func _resupply_post(holder: String, p: Dictionary, key: String,
		sup: float) -> void:
	if sup >= SUPPLY_LOW:
		return
	if _gs != null and holder == String(_gs.player_faction) \
			and String(_gs.player_faction) != "":
		return
	var res = _gs.get("resources") if _gs != null else null
	if res == null or not res.has_method("spend"):
		return
	if not bool(res.can_afford(holder, SUPPLY_WAGON_COST)):
		return
	res.spend(holder, SUPPLY_WAGON_COST)
	supply[key] = minf(SUPPLY_MAX, sup + SUPPLY_WAGON_AMOUNT)
	_gazette_throttled("wagon|%s" % holder,
		"Supply wagons roll",
		"Supply wagons reach %s — the garrison will eat this week." \
			% String(p.get("name", "the post")),
		"build")


## ---- sieges --------------------------------------------------------------------

## Live siege record for a post, or {}.
func siege_of(kind: String, pid: int) -> Dictionary:
	return sieges.get(_post_key(kind, pid), {})


## Set the attacker's siege doctrine (called by the proposal flow on
## approve, or directly by tests/AI).
func set_siege_mode(attacker: String, kind: String, pid: int,
		mode: String) -> Dictionary:
	var key := _post_key(kind, pid)
	if not sieges.has(key):
		return {"ok": false, "reason": "no siege"}
	if mode != "assault" and mode != "starve":
		return {"ok": false, "reason": "bad mode"}
	(sieges[key] as Dictionary)["mode"] = mode
	return {"ok": true, "mode": mode}


func _tick_sieges(day: int) -> void:
	_detect_sieges(day)
	_progress_sieges(day)


## A siege begins when war-enemy troops mass around a held post.
func _detect_sieges(day: int) -> void:
	for p in posts_of():
		var holder := String(p.get("holder", ""))
		if holder == "":
			continue
		var kind := String(p.get("kind", ""))
		var pid := int(p.get("id", 0))
		var key := _post_key(kind, pid)
		if sieges.has(key):
			continue
		var pos: Vector2 = p.get("position", Vector2.ZERO)
		var r := float(p.get("radius", TOWN_R)) * SIEGE_DETECT_R_MULT
		var by_faction := {}
		for u in _gs.units:
			var ud := u as Dictionary
			if ud.is_empty() or not bool(ud.get("alive", false)):
				continue
			var f := String(ud.get("faction", ""))
			if f == "" or f == holder:
				continue
			if not JobDefs.is_military(String(ud.get("job", ""))):
				continue
			if not _hostile_to(f, holder):
				continue
			if pos.distance_to(ud.get("position", Vector2.ZERO)) > r:
				continue
			by_faction[f] = int(by_faction.get(f, 0)) + 1
		var best := ""
		var best_n := 0
		for f in by_faction.keys():
			if int(by_faction[f]) > best_n:
				best_n = int(by_faction[f])
				best = String(f)
		if best_n < SIEGE_MIN_ATTACKERS:
			continue
		sieges[key] = {
			"attacker": best, "holder": holder, "mode": "undecided",
			"days": 0, "integrity": 100.0, "quiet": 0,
			"kind": kind, "post_id": pid,
			"post_name": String(p.get("name", "the post")),
		}
		_gazette("BESIEGED: %s" % String(p.get("name", "the post")),
			"%s forces have encircled %s — %d troops at the %s. The %s " \
			% [_fname(best), String(p.get("name", "the post")), best_n,
				{"monastery": "gates", "crystal": "shard",
					"town": "walls"}.get(kind, "gates"),
				_fname(holder)] + "brace for a siege.")
		var rec := _siege_recommendation(best, p)
		_file_siege_choice(best, p, String(rec[0]), String(rec[1]), day)


## The attacker's choice, HTML-gated: storm when the estimate says we
## win (need = 1.15 - aggro*0.25), starve when the defenses are too
## thick. Returns [mode, reason].
func _siege_recommendation(attacker: String, post: Dictionary) -> Array:
	var pos: Vector2 = post.get("position", Vector2.ZERO)
	var r := float(post.get("radius", TOWN_R))
	var holder := String(post.get("holder", ""))
	var atk := 0
	var dfn := 0
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		if not JobDefs.is_military(String(ud.get("job", ""))):
			continue
		if pos.distance_to(ud.get("position", Vector2.ZERO)) > r:
			continue
		var f := String(ud.get("faction", ""))
		if f == attacker:
			atk += 1
		elif f == holder:
			dfn += 1
	dfn += _garrison_count(String(post.get("kind", "")),
		int(post.get("id", 0)))
	var ratio := float(atk) / maxf(1.0, float(dfn))
	var aggro := 0.5
	var dip = _gs.get("diplomacy")
	if dip != null and dip.has_method("faction_traits"):
		aggro = float(dip.faction_traits(attacker).get("aggro", 0.5))
	var need := 1.15 - aggro * 0.25
	if ratio >= need:
		return ["assault",
			"%d attackers vs %d defenders — we can take it by storm." \
				% [atk, dfn]]
	return ["starve",
		"%d defenders hold %s — storming is suicide. Starve them out." \
			% [dfn, String(post.get("name", "the post"))]]


## File the attacker's assault-vs-starve choice through the strategic
## proposal protocol (player gets the phone modal; AI auto-resolves).
func _file_siege_choice(attacker: String, post: Dictionary, mode: String,
		reason: String, day: int) -> void:
	var props = _gs.get("proposals") if _gs != null else null
	if props == null or not props.has_method("propose"):
		return
	var kind := String(post.get("kind", ""))
	var pid := int(post.get("id", 0))
	var ckey := "siege_choice|%s|%s|%d" % [attacker, kind, pid]
	if day - int(_siege_proposed.get(ckey, -99)) < SIEGE_PROPOSE_COOLDOWN:
		return
	_siege_proposed[ckey] = day
	props.propose(attacker, "siege_choice", {
		"post_kind": kind, "post_id": pid,
		"post_name": String(post.get("name", "the post")),
		"defender": String(post.get("holder", "")),
		"mode": mode, "reason": reason,
	})


## Daily siege grind: integrity and supply bleed; quiet sieges lift;
## broken posts fall.
func _progress_sieges(day: int) -> void:
	var done: Array = []
	for key in sieges.keys():
		var s := sieges[key] as Dictionary
		var kind := String(s.get("kind", ""))
		var pid := int(s.get("post_id", -1))
		var attacker := String(s.get("attacker", ""))
		var holder := String(s.get("holder", ""))
		var post := find_post(kind, pid)
		if post.is_empty() or String(post.get("holder", "")) != holder:
			done.append(key)  # captured or razed: siege over
			continue
		var pos: Vector2 = post.get("position", Vector2.ZERO)
		var r := float(post.get("radius", TOWN_R)) * SIEGE_DETECT_R_MULT
		var foes := 0
		for u in _gs.units:
			var ud := u as Dictionary
			if ud.is_empty() or not bool(ud.get("alive", false)):
				continue
			if String(ud.get("faction", "")) != attacker:
				continue
			if not JobDefs.is_military(String(ud.get("job", ""))):
				continue
			if pos.distance_to(ud.get("position", Vector2.ZERO)) <= r:
				foes += 1
		if foes < 2:
			s["quiet"] = int(s.get("quiet", 0)) + 1
		else:
			s["quiet"] = 0
		if int(s.get("quiet", 0)) >= SIEGE_LIFT_QUIET_DAYS:
			_gazette("Siege lifted: %s" % String(s.get("post_name", "")),
				"The %s abandon the siege of %s — the %s hold." % [
					_fname(attacker), String(s.get("post_name", "")),
					_fname(holder)])
			done.append(key)
			continue
		if not _hostile_to(attacker, holder):
			done.append(key)  # peace broke out: siege over
			continue
		s["days"] = int(s.get("days", 0)) + 1
		var mode := String(s.get("mode", "undecided"))
		var integ := float(s.get("integrity", 100.0))
		var lvl := upgrade_level(kind, pid)
		var rate := SIEGE_INTEGRITY_UNDECIDED
		if mode == "starve":
			rate = SIEGE_INTEGRITY_STARVE
		elif mode == "assault":
			rate = SIEGE_INTEGRITY_ASSAULT
		rate *= 1.0 - SIEGE_INTEGRITY_SAVE_PER_LEVEL * float(lvl)
		s["integrity"] = maxf(0.0, integ - rate)
		if kind == "town":
			_chip_besieged_hall(pid, mode)
		if float(s.get("integrity", 0.0)) <= 0.0:
			_siege_capture(s)
			done.append(key)
	for key in done:
		sieges.erase(key)


## Besieged halls take daily damage (repairs matter); never the killing
## blow — the fall comes through capture, not collapse.
func _chip_besieged_hall(hall_id: int, mode: String) -> void:
	var hall := _post_record("town", hall_id)
	if hall.is_empty():
		return
	var max_hp := float(hall.get("max_hp", hall.get("hp", 1200.0)))
	var chip := max_hp * SIEGE_HALL_CHIP
	if mode != "starve":
		chip *= 0.5
	hall["hp"] = maxf(1.0, float(hall.get("hp", max_hp)) - chip)


## A broken post falls to the besieger: halls flip through the 25%
## keep-or-rename capture flow, monasteries and crystals through their
## capture rites. Capture log + Gazette flow from the shared paths.
func _siege_capture(s: Dictionary) -> void:
	var kind := String(s.get("kind", ""))
	var pid := int(s.get("post_id", -1))
	var attacker := String(s.get("attacker", ""))
	var pname := String(s.get("post_name", "the post"))
	if kind == "town":
		var hall := _post_record("town", pid)
		if not hall.is_empty():
			_starvation_flip_town(hall, attacker)
	elif kind == "monastery":
		var mons = _gs.get("monasteries") if _gs != null else null
		if mons != null and mons.has_method("_capture"):
			var m := _post_record("monastery", pid)
			if not m.is_empty():
				mons._capture(m, attacker)
	elif kind == "crystal":
		var crys = _gs.get("crystals") if _gs != null else null
		if crys != null and crys.has_method("_capture"):
			var c := _post_record("crystal", pid)
			if not c.is_empty():
				crys._capture(c, attacker)
	_gazette("%s starves" % pname,
		"%s endures no more — %s's banners rise over %s. Hunger is " \
		% [pname, _fname(attacker), pname] + "the oldest siege engine.")


## Hall flip for starvation captures: mirrors SimCombat._flip_hall — the
## town and its land go to the attacker at 25% HP, capture logged, the
## player's conquests get the keep-or-rename prompt.
func _starvation_flip_town(hall: Dictionary, new_faction: String) -> void:
	var old := String(hall.get("faction", ""))
	var max_hp := float(hall.get("max_hp", hall.get("hp", 1200.0)))
	hall["faction"] = new_faction
	hall["hp"] = maxf(1.0, max_hp * 0.25)
	hall["captured_t"] = 0.0
	var bpos: Vector2 = hall.get("position", Vector2.ZERO)
	var pname := str(hall.get("town_name", hall.get("name", "Town")))
	var tid := int(hall.get("town_id", -1))
	if _gs != null and tid >= 0 and _gs.get("towns") != null \
			and (_gs.get("towns") as Dictionary).has(tid):
		((_gs.get("towns") as Dictionary)[tid] as Dictionary)[
			"faction"] = new_faction
	log_capture("town", int(hall.get("id", 0)), old, new_faction, bpos,
		pname)
	_gazette("%s seizes %s" % [_fname(new_faction), pname],
		"%s's troops starved %s into submission and raised their " \
		% [_fname(new_faction), pname] + "banner over the hall. The town " \
		+ "and all its claimed land now answer to %s." \
		% _fname(new_faction))
	# Keep-or-rename: log_capture (above) emitted command_post_captured,
	# which queues the prompt in SimArmy — no direct call needed.

## ---- AI post strategy (daily) --------------------------------------------------

## Daily strategic pass over command posts for every faction. Routine
## defense and supply run for everyone (advisors included); spending and
## offensives are AI-only — the player's ruler commands those.
func _ai_post_strategy() -> void:
	if _gs == null:
		return
	var day := int(_gs.get("day_number"))
	_expire_feints(day)
	for faction in _gs.active_factions:
		if faction == "":
			continue
		var is_player: bool = String(faction) == String(
			_gs.player_faction)
		if is_player:
			continue
		_ai_upgrade_posts(faction)
		_ai_garrison_topup(faction)
		_ai_feints(faction, day)


## Feint marks older than FEINT_DAYS dissolve — the probe pulls back.
func _expire_feints(day: int) -> void:
	if _gs == null:
		return
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty():
			continue
		if not bool(ud.get("feint", false)):
			continue
		if day - int(ud.get("feint_day", day)) >= FEINT_DAYS:
			ud.erase("post_march")
			ud.erase("feint")
			ud.erase("feint_day")


## AI upgrades: threatened posts first, then by VALUE (monastery > town
## > crystal). Two upgrades per faction per day, treasury permitting.
func _ai_upgrade_posts(faction: String) -> void:
	var posts := holdings_of(faction)
	posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ta := 1.0 if not siege_of(
			String(a.get("kind", "")), int(a.get("id", 0))).is_empty() \
			else 0.0
		var tb := 1.0 if not siege_of(
			String(b.get("kind", "")), int(b.get("id", 0))).is_empty() \
			else 0.0
		if ta != tb:
			return ta > tb
		return float(VALUE.get(String(a.get("kind", "")), 0.0)) > float(
			VALUE.get(String(b.get("kind", "")), 0.0)))
	var done := 0
	for p in posts:
		if done >= 2:
			break
		var kind := String(p.get("kind", ""))
		var pid := int(p.get("id", 0))
		if upgrade_level(kind, pid) >= MAX_UPGRADE:
			continue
		var r := upgrade_post(faction, kind, pid, false)
		if bool(r.get("ok", false)):
			done += 1


## AI garrison top-ups: besieged or threatened own posts get standing
## garrisons from idle troops (extends the director's guard rotations —
## these orders stick instead of rotating).
func _ai_garrison_topup(faction: String) -> void:
	for p in holdings_of(faction):
		var kind := String(p.get("kind", ""))
		var pid := int(p.get("id", 0))
		var key := _post_key(kind, pid)
		var threatened := not siege_of(kind, pid).is_empty()
		if not threatened:
			var pos: Vector2 = p.get("position", Vector2.ZERO)
			var r := float(p.get("radius", TOWN_R))
			threatened = _foes_near(pos, r, faction) > 0
		if not threatened:
			continue
		if _garrison_count(kind, pid) >= GARRISON_DEFAULT:
			continue
		assign_garrison(faction, kind, pid, [], false)


## Feints: at war with a real army, probe a WEAK low-value post with a
## small force to draw defenders, then concentrate the main blow on the
## high-value prize. VALUE order kept: monastery > town > crystal.
func _ai_feints(faction: String, day: int) -> void:
	if day - int(_feint_day.get(faction, -99)) < FEINT_COOLDOWN:
		return
	if _idle_military(faction).size() < FEINT_MIN_ARMY:
		return
	var war_posts: Array = []
	for p in posts_of():
		var holder := String(p.get("holder", ""))
		if holder == "" or holder == faction:
			continue
		if _hostile_to(faction, holder):
			war_posts.append(p)
	if war_posts.size() < 2:
		return  # nothing to feint against: need a probe AND a prize
	war_posts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(VALUE.get(String(a.get("kind", "")), 0.0)) > float(
			VALUE.get(String(b.get("kind", "")), 0.0)))
	var main: Dictionary = war_posts[0]
	# Feint target: the weakest-defended low-value post that isn't the prize.
	var rest: Array = war_posts.slice(1)
	rest.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da := _defenders_of(a, faction)
		var db := _defenders_of(b, faction)
		if da != db:
			return da < db
		return float(VALUE.get(String(a.get("kind", "")), 0.0)) < float(
			VALUE.get(String(b.get("kind", "")), 0.0)))
	var probe: Dictionary = rest[0]
	var idle := _idle_military(faction)
	if idle.size() < FEINT_MIN_ARMY:
		return
	# 1) The probe: a small force marches on the weak post, loudly.
	var sent := 0
	for ud in idle.duplicate():
		if sent >= FEINT_FORCE:
			break
		var pk := String(probe.get("kind", ""))
		var pid := int(probe.get("id", 0))
		ud["post_march"] = {"kind": pk, "id": pid}
		ud["feint"] = true
		ud["feint_day"] = day
		var ppos: Vector2 = probe.get("position", Vector2.ZERO)
		ud["move_target"] = ppos + Vector2(randf_range(-60.0, 60.0),
			randf_range(-60.0, 60.0))
		sent += 1
		idle.erase(ud)
	if sent == 0:
		return
	_feint_day[faction] = day
	# 2) The concentration: fresh troops mass on the high-value prize
	# while the enemy's guards chase the probe.
	var mk := String(main.get("kind", ""))
	var mid := int(main.get("id", 0))
	var mpos: Vector2 = main.get("position", Vector2.ZERO)
	var topup := 0
	for ud in idle.duplicate():
		if topup >= FEINT_TOPUP:
			break
		ud["post_march"] = {"kind": mk, "id": mid}
		ud["move_target"] = mpos + Vector2(randf_range(-60.0, 60.0),
			randf_range(-60.0, 60.0))
		topup += 1


## Defenders of a post from the attacker's perspective: nearby holder
## military + the standing garrison.
func _defenders_of(post: Dictionary, attacker: String) -> int:
	var pos: Vector2 = post.get("position", Vector2.ZERO)
	var r := float(post.get("radius", TOWN_R))
	var holder := String(post.get("holder", ""))
	var n := _garrison_count(String(post.get("kind", "")),
		int(post.get("id", 0)))
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		if String(ud.get("faction", "")) != holder:
			continue
		if not JobDefs.is_military(String(ud.get("job", ""))):
			continue
		if pos.distance_to(ud.get("position", Vector2.ZERO)) > r:
			continue
		n += 1
	return n


## Hostile military near a position (any hostile faction).
func _foes_near(pos: Vector2, r: float, faction: String) -> int:
	var n := 0
	for u in _gs.units:
		var ud := u as Dictionary
		if ud.is_empty() or not bool(ud.get("alive", false)):
			continue
		var f := String(ud.get("faction", ""))
		if f == "" or f == faction:
			continue
		if not JobDefs.is_military(String(ud.get("job", ""))):
			continue
		if not _hostile_to(f, faction):
			continue
		if pos.distance_to(ud.get("position", Vector2.ZERO)) <= r:
			n += 1
	return n
