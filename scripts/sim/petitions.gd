class_name SimPetitions
extends RefCounted

## Cursing Gnomes — tool/equipment + shop petition chain (Jeremy 2026-10-04).
##
## Units need tools for jobs: miners need a pickaxe, woodcutters an axe,
## fishers a fishing rod, farmers a hoe, builders a hammer. Tool definitions
## and prices are ported VERBATIM from the HTML build (fix79 TOOL_DEFS54 /
## TOOL_FOR_TASK54); the HTML's "no tool = 25% yield" rule (toolTake54) is
## ported too. Units buy tools at shop-type buildings with faction gold.
##
## When a faction has no shop, a unit petitions the faction adviser, who
## checks the treasury: AI factions auto-approve when affordable + needed,
## the player faction gets a phone popup (bus.build_request -> phone_ui
## Approve/Deny modal). The adviser also proactively petitions once a day
## for every shop type the faction genuinely needs (general store for
## tools, weaponsmith for a war band, restaurant for a fed population).
##
## PETITION SCHEMA (Dictionary):
##   id: int, faction: String, building_type: String, from_unit_id: int,
##   origin: String ("unit" | "advisor"), day: int, status: String
##   ("open" | "approved" | "denied"), reason: String,
##   reviewed_by: int (adviser unit id, -1 = none),
##   asked_player: bool, building_id: int (-1 until approved+placed)
##
## UNIT FIELDS (on the unit record Dictionary):
##   inventory: Dictionary {tool_id: count}  (HTML ensureInventory parity)
##   equipped_tool: String (tool id, "" = none)
##   _shop_target / _tool_wanted / _tool_check_cd: supply-flow scratch
##
## Pure logic — no rendering, no input, no audio. Owned by World
## (game.petitions); tests can SimPetitions.new(gs) directly.


## --- Tool catalog: fix79 TOOL_DEFS54, verbatim names/prices ----------------
const TOOL_DEFS := {
	"axe":        {"name": "Woodsman's Axe",  "price": 25.0, "icon": "tool_axe"},
	"pickaxe":    {"name": "Miner's Pickaxe", "price": 30.0, "icon": "tool_pickaxe"},
	"hoe":        {"name": "Field Hoe",       "price": 18.0, "icon": "tool_hoe"},
	"hammer":     {"name": "Smith's Hammer",  "price": 22.0, "icon": "tool_hammer"},
	"fishingrod": {"name": "Fishing Rod",     "price": 15.0, "icon": "tool_fishingrod"},
}

## HTML TOOL_FOR_TASK54 ported to Godot job keys (chop->woodcutter,
## mine->miner, fish->fisher, farm->farmer, build->builder).
const TOOL_FOR_JOB := {
	"miner": "pickaxe",
	"woodcutter": "axe",
	"fisher": "fishingrod",
	"farmer": "hoe",
	"builder": "hammer",
}

## Building types that sell tools — any completed one satisfies a purchase.
const SHOP_BUILDINGS := ["general_store", "blacksmith", "shop", "seedshop"]
## Tool-selling shop types share one petition rule (see
## _faction_needs_shop_type).
const TOOL_SHOP_TYPES := ["general_store", "blacksmith", "shop", "seedshop"]

## Shop types the financial adviser proactively petitions for, once a day,
## when the faction genuinely needs them (Jeremy 2026-10-04: "The financial
## advisor should request any and all builds for player faction. If it thinks
## they need it. All shops should work like this."). Player-faction petitions
## arrive as phone popups; AI factions auto-approve when affordable.
const SHOP_PETITION_TYPES := ["general_store", "weaponsmith", "restaurant"]
## Proactivity thresholds (judgment calls, documented): a weaponsmith is
## worth petitioning once the faction fields a real war band; a restaurant
## once there are enough mouths to feed to justify it.
const WEAPONSMITH_MIN_SOLDIERS := 3
const RESTAURANT_MIN_POP := 10

## HTML toolTake54 parity: gathering/building without the right tool yields
## 25% and surfaces the need.
const NO_TOOL_YIELD_MULT := 0.25
## Seconds between supply attempts per unit (buy walk / petition filing).
const TOOL_CHECK_COOLDOWN := 10.0
## Days before a denied shop type may be petitioned again (AI denials retry
## daily; a PLAYER denial is respected for 3 days — no popup spam).
const AI_DENY_COOLDOWN_DAYS := 1
const PLAYER_DENY_COOLDOWN_DAYS := 3
## Cap on stored petition records (decided ones are pruned, oldest first).
const MAX_PETITIONS := 60


var _gs  # GameState (untyped: avoids a core<->sim class cycle).
var petitions: Array[Dictionary] = []
var _petition_seq: int = 1
## "faction:building_type" -> day_number of the last denial (re-file guard).
var _last_deny: Dictionary = {}


func _init(game_state) -> void:
	_gs = game_state
	_gs.bus.day_changed.connect(_on_day)


## --- Static tool/inventory helpers (HTML ensureInventory/unitHasTool54 /
## equipTool54 parity; no instance needed) ------------------------------------

## The tool id a job needs, or "" when the job needs none.
static func tool_for_job(job: String) -> String:
	return String(TOOL_FOR_JOB.get(job, ""))


## The tool id a unit's current job needs, or "".
static func tool_needed(unit: Dictionary) -> String:
	return tool_for_job(String(unit.get("job", "")))


## Display name for a tool id ("Iron Pickaxe"-style line in unit info).
static func tool_name(tool_id: String) -> String:
	var d: Dictionary = TOOL_DEFS.get(tool_id, {})
	return String(d.get("name", tool_id.capitalize()))


## Gold price for a tool id (-1 when unknown).
static func tool_price(tool_id: String) -> float:
	var d: Dictionary = TOOL_DEFS.get(tool_id, {})
	if d.is_empty():
		return -1.0
	return float(d.get("price", 0.0))


## Inventory dict on the unit record ({tool_id: count}); created on demand.
static func ensure_inventory(unit: Dictionary) -> Dictionary:
	if not unit.has("inventory") or not (unit["inventory"] is Dictionary):
		unit["inventory"] = {}
	if not unit.has("equipped_tool"):
		unit["equipped_tool"] = ""
	return unit["inventory"]


## True when the tool is equipped OR in the pack (HTML unitHasTool54).
static func unit_has_tool(unit: Dictionary, tool_id: String) -> bool:
	if String(unit.get("equipped_tool", "")) == tool_id:
		return true
	var inv: Dictionary = ensure_inventory(unit)
	return int(inv.get(tool_id, 0)) > 0


## Equip a tool from the pack (HTML equipTool54: swap old one back in).
## Returns false when the unit doesn't own the tool.
static func equip_tool(unit: Dictionary, tool_id: String) -> bool:
	var inv: Dictionary = ensure_inventory(unit)
	if int(inv.get(tool_id, 0)) <= 0 \
			and String(unit.get("equipped_tool", "")) != tool_id:
		return false
	var old: String = String(unit.get("equipped_tool", ""))
	if old != "" and old != tool_id:
		inv[old] = int(inv.get(old, 0)) + 1
	if old != tool_id:
		inv[tool_id] = maxi(0, int(inv.get(tool_id, 0)) - 1)
	unit["equipped_tool"] = tool_id
	return true


## --- Instance: supply flow ---------------------------------------------------

## Nearest completed, alive shop-type building of the faction ({} if none).
func find_store(faction: String, near: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)) or not bool(b.get("complete", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not (String(b.get("type", "")) in SHOP_BUILDINGS):
			continue
		var d: float = near.distance_to(b.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = b
	return best


## True when the faction has any completed shop-type building.
func has_store(faction: String) -> bool:
	return not find_store(faction, Vector2.ZERO).is_empty()


## True when the faction treasury can buy the tool (faction gold, per Jeremy).
func can_afford_tool(faction: String, tool_id: String) -> bool:
	var price := tool_price(tool_id)
	if price < 0.0:
		return false
	return _gs.resources.get_amount(faction, "gold") >= price


## Buy a tool at a shop: faction gold -> unit inventory, then equip.
## Returns false when unaffordable or the tool id is unknown.
func buy_tool(unit: Dictionary, tool_id: String) -> bool:
	var price := tool_price(tool_id)
	if price < 0.0:
		return false
	var faction: String = String(unit.get("faction", ""))
	if not _gs.resources.spend(faction, {"gold": price}):
		return false
	var inv := ensure_inventory(unit)
	inv[tool_id] = int(inv.get(tool_id, 0)) + 1
	equip_tool(unit, tool_id)
	return true


## Make sure the unit is working toward its job's tool. Returns:
## "has" (already owned/equipped), "to_shop" (walking to a store —
## work_state set for WorkerAI), "petitioned" (no store: petition filed),
## "broke" (store exists but the faction can't afford the tool),
## "wait" (cooldown), "none" (job needs no tool).
func try_supply_tool(unit: Dictionary) -> String:
	var tool_id := tool_needed(unit)
	if tool_id == "":
		return "none"
	if unit_has_tool(unit, tool_id):
		equip_tool(unit, tool_id)
		return "has"
	var now: float = float(_gs.game_time)
	if float(unit.get("_tool_check_cd", 0.0)) > now:
		return "wait"
	unit["_tool_check_cd"] = now + TOOL_CHECK_COOLDOWN
	var faction: String = String(unit.get("faction", ""))
	var store := find_store(faction, unit.get("position", Vector2.ZERO))
	if store.is_empty():
		request_shop_build(faction, "general_store",
			int(unit.get("id", -1)), "unit")
		return "petitioned"
	if not can_afford_tool(faction, tool_id):
		return "broke"
	# Walk to the store; WorkerAI's "to_shop" state completes the purchase.
	unit["_shop_target"] = int(store.get("id", -1))
	unit["_tool_wanted"] = tool_id
	unit["work_target_pos"] = store.get("position",
		unit.get("position", Vector2.ZERO))
	unit["work_state"] = "to_shop"
	return "to_shop"


## --- Petitions ---------------------------------------------------------------

## File a petition for a shop-type building. Dedupes: an already-open
## petition — or an approved one whose blueprint is still under
## construction — for the same faction+type is returned instead of
## doubling up. Immediately runs the adviser review (see _review).
func request_shop_build(faction: String, btype: String, from_unit_id: int = -1,
		origin: String = "unit") -> Dictionary:
	var active := active_petition(faction, btype)
	if not active.is_empty():
		return active
	# Denial cooldown: don't re-file a shop type the adviser/player just
	# rejected (player denials are respected longer — no popup spam).
	var cd_key := faction + ":" + btype
	if _deny_cooldown_left(cd_key) > 0:
		return {}
	var p: Dictionary = {
		"id": _petition_seq,
		"faction": faction,
		"building_type": btype,
		"from_unit_id": from_unit_id,
		"origin": origin,
		"day": _gs.day_number,
		"status": "open",
		"reason": "",
		"reviewed_by": -1,
		"asked_player": false,
		"building_id": -1,
	}
	_petition_seq += 1
	petitions.append(p)
	_prune_decided()
	_review(p)
	return p


## Days left before this faction+type may be petitioned again (0 = clear).
func _deny_cooldown_left(cd_key: String) -> int:
	var rec: Dictionary = _last_deny.get(cd_key, {})
	if rec.is_empty():
		return 0
	var window := PLAYER_DENY_COOLDOWN_DAYS \
		if bool(rec.get("player", false)) else AI_DENY_COOLDOWN_DAYS
	return maxi(0, int(rec.get("day", 0)) + window - _gs.day_number)


## Record a denial (drives the re-file cooldown in request_shop_build).
## player=true when the denial came from the player's popup answer.
func _note_deny(p: Dictionary, player: bool = false) -> void:
	_last_deny[String(p.get("faction", "")) + ":"
		+ String(p.get("building_type", ""))] = {
		"day": _gs.day_number, "player": player}


## Keep the petition log bounded: prune oldest decided records first.
func _prune_decided() -> void:
	while petitions.size() > MAX_PETITIONS:
		var idx := -1
		for i: int in petitions.size():
			if String(petitions[i].get("status", "open")) != "open":
				idx = i
				break
		if idx < 0:
			return
		petitions.remove_at(idx)


## The still-open petition for a faction+building type, or {}.
func open_petition(faction: String, btype: String) -> Dictionary:
	for p: Dictionary in petitions:
		if String(p.get("status", "")) == "open" \
				and String(p.get("faction", "")) == faction \
				and String(p.get("building_type", "")) == btype:
			return p
	return {}


## An open petition, or an approved one whose blueprint hasn't finished
## building yet (still "in flight"). Used for dedupe.
func active_petition(faction: String, btype: String) -> Dictionary:
	var open := open_petition(faction, btype)
	if not open.is_empty():
		return open
	for p: Dictionary in petitions:
		if String(p.get("status", "")) != "approved" \
				or String(p.get("faction", "")) != faction \
				or String(p.get("building_type", "")) != btype:
			continue
		var bp := _building_by_id(int(p.get("building_id", -1)))
		if not bp.is_empty() and not bool(bp.get("complete", false)):
			return p
	return {}


func _building_by_id(building_id: int) -> Dictionary:
	# Jeremy 2026-10-05 perf: shared O(1) id index on GameState.
	return _gs.get_building(building_id)


## The faction's adviser unit (gov_role "adviser"), or {} when none.
func adviser_of(faction: String) -> Dictionary:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if SimArmy.gov_role_of(u) == "adviser":
			return u
	return {}


## True when some alive unit of the faction needs a tool it doesn't have.
func faction_needs_tools(faction: String) -> bool:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		var need := tool_needed(u)
		if need != "" and not unit_has_tool(u, need):
			return true
	return false


## Any alive building of this type (complete OR blueprint still under
## construction). Used so the adviser never petitions a duplicate while
## the AI director (or an earlier petition) already has one in flight.
func _has_any(faction: String, btype: String) -> bool:
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) == btype:
			return true
	return false


## Alive military units of the faction (soldiers need the weaponsmith's
## upgrade path).
func _count_military(faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if JobDefs.is_military(String(u.get("job", ""))):
			n += 1
	return n


## Alive population of the faction.
func _count_pop(faction: String) -> int:
	var n := 0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) == faction:
			n += 1
	return n


## Per-type "does the faction genuinely need this shop?" check. Used by
## the daily proactivity sweep and the AI-faction review. Tool-selling
## shops share one rule (any tool shop satisfies the tool need); the
## weaponsmith and restaurant have their own thresholds.
func _faction_needs_shop_type(faction: String, btype: String) -> bool:
	if btype in TOOL_SHOP_TYPES:
		# Any tool-selling shop satisfies the tool need — only petition
		# when the faction has no shop at all.
		return not has_store(faction) and faction_needs_tools(faction)
	match btype:
		"weaponsmith":
			# A war band without the upgrade path.
			return not _has_any(faction, btype) \
				and _count_military(faction) >= WEAPONSMITH_MIN_SOLDIERS
		"restaurant":
			# Enough mouths to feed to justify food variety.
			return not _has_any(faction, btype) \
				and _count_pop(faction) >= RESTAURANT_MIN_POP
	return false


## The adviser review: checks the treasury. AI factions auto-approve when
## affordable AND needed (per-type need check); the player faction gets the
## phone popup (once).
func _review(p: Dictionary) -> void:
	var faction: String = String(p.get("faction", ""))
	var btype: String = String(p.get("building_type", ""))
	var costs: Dictionary = SimBuildings.cost_of(btype)
	var adviser := adviser_of(faction)
	var adviser_id := int(adviser.get("id", -1))
	if not _gs.resources.can_afford(faction, costs):
		p["status"] = "denied"
		p["reason"] = "unaffordable"
		p["reviewed_by"] = adviser_id
		_note_deny(p)
		_say_line(adviser, "The treasury cannot afford a %s. Petition denied."
			% _bname(btype))
		return
	if faction == _gs.player_faction:
		p["reviewed_by"] = adviser_id
		if not bool(p.get("asked_player", false)):
			p["asked_player"] = true
			_gs.bus.build_request.emit(p)
		return  # stays open until the player answers (resolve_petition)
	# AI faction: approve when the faction genuinely needs it (per-type;
	# the need check also covers "already have one / one in flight").
	if not _faction_needs_shop_type(faction, btype):
		p["status"] = "denied"
		p["reason"] = "not_needed"
		p["reviewed_by"] = adviser_id
		_note_deny(p)
		return
	_approve_build(p, adviser_id)


## Resolve a player-facing petition (phone popup Approve/Deny).
## Returns false when the petition isn't open (already decided).
func resolve_petition(petition_id: int, approved: bool,
		by: String = "player") -> bool:
	var p := _find(petition_id)
	if p.is_empty() or String(p.get("status", "")) != "open":
		return false
	var adviser := adviser_of(String(p.get("faction", "")))
	var adviser_id := int(adviser.get("id", -1))
	if approved:
		_approve_build(p, adviser_id)
		if String(p.get("status", "")) == "approved":
			_say_line(adviser, "At once. The %s will rise."
				% _bname(String(p.get("building_type", ""))))
	else:
		p["status"] = "denied"
		p["reason"] = "denied_by_" + by
		p["reviewed_by"] = adviser_id
		_note_deny(p, by == "player")
		_say_line(adviser, "As you wish. The petition is withdrawn.")
	return true


## Approve: pay the building cost and drop a blueprint near the faction's
## hall/town; builders construct it through the normal pipeline.
func _approve_build(p: Dictionary, adviser_id: int) -> void:
	var faction: String = String(p.get("faction", ""))
	var btype: String = String(p.get("building_type", ""))
	p["reviewed_by"] = adviser_id
	var spot := _build_spot(faction, btype)
	if spot == Vector2.INF:
		p["status"] = "denied"
		p["reason"] = "no_site"
		_note_deny(p)
		return
	var bp: Dictionary = SimBuildings.new(_gs).place_blueprint(
		btype, faction, _town_for(faction, spot), spot)
	if bp.is_empty():
		p["status"] = "denied"
		p["reason"] = "placement_failed"
		_note_deny(p)
		return
	p["status"] = "approved"
	p["building_id"] = int(bp.get("id", -1))


func _find(petition_id: int) -> Dictionary:
	for p: Dictionary in petitions:
		if int(p.get("id", 0)) == petition_id:
			return p
	return {}


func _bname(btype: String) -> String:
	return String(SimBuildings.BUILDINGS.get(btype, {}).get("name",
		btype.capitalize()))


## Pick a legal blueprint spot near the faction's hall (fallback: a town,
## then any of the faction's units). Tries ring offsets until
## SimBuildings.can_place_at accepts one.
func _build_spot(faction: String, btype: String) -> Vector2:
	var anchor := Vector2.INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) in ["town_hall", "hall"]:
			anchor = b.get("position", Vector2.ZERO)
			break
	if anchor == Vector2.INF:
		for tid: int in _gs.towns.keys():
			var t: Dictionary = _gs.towns[tid]
			if String(t.get("faction", "")) == faction:
				anchor = t.get("position", Vector2.ZERO)
				break
	if anchor == Vector2.INF:
		for u: Dictionary in _gs.units:
			if u.get("alive", false) \
					and String(u.get("faction", "")) == faction:
				anchor = u.get("position", Vector2.ZERO)
				break
	if anchor == Vector2.INF:
		return Vector2.INF
	var rect := Rect2(Vector2(-1000000, -1000000), Vector2(2000000, 2000000))
	if not _gs.map_data.is_empty():
		var w := float(_gs.map_data.get("world_w", 4096.0))
		var h := float(_gs.map_data.get("world_h", 4096.0))
		rect = Rect2(Vector2.ZERO, Vector2(w, h))
	var offsets := [Vector2(150, 100), Vector2(-150, 100), Vector2(150, -100),
		Vector2(-150, -100), Vector2(220, 0), Vector2(-220, 0),
		Vector2(0, 220), Vector2(0, -220), Vector2(300, 150), Vector2(-300, -150)]
	for off: Vector2 in offsets:
		var spot: Vector2 = anchor + off
		if SimBuildings.can_place_at(_gs.buildings, btype, spot, rect, faction, 0.0,
				SimCommandPosts.claimants_of_game(_gs), _gs.map_data):
			return spot
	return Vector2.INF


## Town id for the blueprint: hall's town, else the petitioner's, else any.
func _town_for(faction: String, _spot: Vector2) -> int:
	for b: Dictionary in _gs.buildings:
		if bool(b.get("alive", false)) \
				and String(b.get("faction", "")) == faction \
				and String(b.get("type", "")) in ["town_hall", "hall"]:
			return int(b.get("town_id", -1))
	for tid: int in _gs.towns.keys():
		if String(_gs.towns[tid].get("faction", "")) == faction:
			return tid
	return -1


## Adviser speech bubble (flavor only; no-op when no adviser unit exists).
func _say_line(adviser: Dictionary, text: String) -> void:
	if adviser.is_empty():
		return
	_gs.bus.unit_said.emit(int(adviser.get("id", 0)), text)


## --- Daily: financial-adviser proactivity --------------------------------------

## Once a day the adviser checks every shop type it can petition for and
## files its own petition when the faction genuinely needs one (Jeremy
## 2026-10-04: "All shops should work like this"). Also re-reviews
## still-open petitions (the treasury may have recovered since).
func _on_day(_day: int, _is_night: bool) -> void:
	for faction: String in _gs.active_factions:
		for btype: String in SHOP_PETITION_TYPES:
			if not _faction_needs_shop_type(faction, btype):
				continue
			if active_petition(faction, btype).is_empty():
				request_shop_build(faction, btype, -1, "advisor")
	# Re-review still-open petitions (the treasury may have recovered).
	# The asked_player flag keeps the phone popup to a single ask per
	# session (reset on load for open player petitions).
	for p: Dictionary in petitions:
		if String(p.get("status", "")) == "open":
			_review(p)


## --- Save/load -----------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"petitions": petitions.duplicate(true),
		"seq": _petition_seq,
		"last_deny": _last_deny.duplicate(true),
	}


func from_dict(data: Dictionary) -> void:
	petitions = (data.get("petitions", []) as Array).duplicate(true)
	# GDScript duplicate(true) on Array[Dictionary] keeps Dictionaries.
	var fixed: Array[Dictionary] = []
	for p in petitions:
		if p is Dictionary:
			var pd: Dictionary = (p as Dictionary).duplicate(true)
			# Re-ask the player after a load (the popup is gone).
			if String(pd.get("status", "")) == "open" \
					and String(pd.get("faction", "")) == _gs.player_faction:
				pd["asked_player"] = false
			fixed.append(pd)
	petitions = fixed
	_petition_seq = int(data.get("seq", 1))
	_last_deny = (data.get("last_deny", {}) as Dictionary).duplicate(true)
