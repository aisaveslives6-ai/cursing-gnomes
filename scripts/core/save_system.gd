class_name SaveSystem
extends RefCounted
## Cursing Gnomes — save/load (Milestone 7: polish & ship).
##
## Serializes the full GameState to JSON: factions, ruler name (verbatim),
## game time, towns, units, buildings, work sites, and per-faction resources.
## Multiple slots. Save files live in the user:// dir so they work on web.
##
## Unit/building Dictionaries are plain data (no Object refs), so a
## JSON round-trip is faithful. Vector2/Color values are encoded as
## {"__vec2": [x, y]} / {"__color": [r, g, b, a]} markers.


const SAVE_DIR := "user://saves"
const SLOT_PREFIX := "slot_"
const SAVE_EXT := ".json"
const MAX_SLOTS := 8

## Jeremy 2026-10-06 (launch readiness): save format version, stamped by
## snapshot(). Bump whenever snapshot()'s layout changes incompatibly.
## restore() REFUSES saves newer than this (they may carry fields this build
## can't interpret — restoring them blindly built broken worlds); saves with
## no version key are legacy v1 and load with defaults for missing sections.
const SAVE_VERSION := 1


## Reject reason from the last failed restore(), for user-facing notices.
## One of: "", "empty", "missing_units", "newer_build", "bad_<section>".
static var _last_reject_reason := ""


## The human-readable reject reason from the last failed restore().
static func last_reject_reason() -> String:
	return _last_reject_reason


## Validate a snapshot Dictionary BEFORE restore() touches game state.
## Returns {"ok": true} or {"ok": false, "reason": <code>} — fail-closed so
## a corrupt, truncated, or newer-build save can never half-restore a
## broken world (the old code only checked `has("units")`: a save with
## units:"garbage" iterated the string's characters and returned true).
static func check_save(data: Dictionary) -> Dictionary:
	if data.is_empty():
		return {"ok": false, "reason": "empty"}
	if not data.has("units"):
		return {"ok": false, "reason": "missing_units"}
	var ver := int(data.get("version", 1))
	if ver > SAVE_VERSION:
		return {"ok": false, "reason": "newer_build"}
	for key in ["units", "buildings", "work_sites", "pickups", "zones"]:
		if data.has(key) and not (data[key] is Array):
			return {"ok": false, "reason": "bad_" + key}
	for key in ["towns", "next_ids", "resources", "diplomacy"]:
		if data.has(key) and not (data[key] is Dictionary):
			return {"ok": false, "reason": "bad_" + key}
	return {"ok": true}


static func _encode_value(v):
	match typeof(v):
		TYPE_VECTOR2:
			return {"__vec2": [v.x, v.y]}
		TYPE_COLOR:
			return {"__color": [v.r, v.g, v.b, v.a]}
		TYPE_RECT2:
			return {"__rect2": [v.position.x, v.position.y, v.size.x, v.size.y]}
		TYPE_DICTIONARY:
			var out := {}
			for k in v.keys():
				out[str(k)] = _encode_value(v[k])
			return out
		TYPE_ARRAY:
			var out := []
			for e in v:
				out.append(_encode_value(e))
			return out
		_:
			return v


static func _decode_value(v):
	if v is Dictionary:
		if v.has("__vec2"):
			var a: Array = v["__vec2"]
			return Vector2(float(a[0]), float(a[1]))
		if v.has("__color"):
			var a2: Array = v["__color"]
			return Color(float(a2[0]), float(a2[1]), float(a2[2]), float(a2[3]))
		if v.has("__rect2"):
			var a3: Array = v["__rect2"]
			return Rect2(float(a3[0]), float(a3[1]), float(a3[2]), float(a3[3]))
		var out := {}
		for k in v.keys():
			out[k] = _decode_value(v[k])
		return out
	if v is Array:
		var out2 := []
		for e in v:
			out2.append(_decode_value(e))
		return out2
	return v


## Snapshot a GameState into a plain Dictionary ready for JSON.
static func snapshot(game: GameState, adventure = null) -> Dictionary:
	var data := {
		"version": SAVE_VERSION,
		"game_name": Config.GAME_NAME,
		"saved_day": game.day_number,
		"ruler_name": game.ruler_name,  # verbatim — never trimmed, never altered
		"player_faction": game.player_faction,
		"active_factions": game.active_factions.duplicate(),
		"game_time": game.game_time,
		"day_number": game.day_number,
		"is_night": game.is_night,
		"towns": _encode_value(game.towns),
		"units": _encode_value(game.units),
		"buildings": _encode_value(game.buildings),
		"work_sites": _encode_value(game.work_sites),
		"pickups": _encode_value(game.pickups),
		"zones": _encode_value(game.zones),
		"resources": _encode_value(game.resources.to_dict() if game.resources else {}),
		"diplomacy": _encode_value(game.diplomacy.to_dict() if game.diplomacy else {}),
		# Port-wave subsystems (assigned to game.* by World._ready; {} in bare tests).
		"seasons": _encode_value(game.seasons.to_dict() if game.get("seasons") else {}),
		"farming": _encode_value(game.farming.to_dict() if game.get("farming") else {}),
		"industry": _encode_value(game.industry.to_dict() if game.get("industry") else {}),
		"disasters": _encode_value(game.disasters.to_dict() if game.get("disasters") else {}),
		"hydro": _encode_value(game.hydro.to_dict() if game.get("hydro") else {}),
		"artillery": _encode_value(game.arty.to_dict() if game.get("arty") else {}),
		"undead": _encode_value(game.undead.to_dict() if game.get("undead") else {}),
		"border_walls": _encode_value(game.border_walls.to_dict() if game.get("border_walls") else {}),
		"starfort_bases": _encode_value(game.starfort_bases.to_dict() if game.get("starfort_bases") else {}),
		"court": _encode_value(game.court_sys.to_dict() if game.get("court_sys") else {}),
		"phone": _encode_value(game.phone_sys.to_dict() if game.get("phone_sys") else {}),
		"hearsay": _encode_value(game.phone_sys.hearsay.to_dict() if game.get("phone_sys") and game.phone_sys.get("hearsay") else {}),
		"ai_director": _encode_value(game.ai_director.to_dict() if game.get("ai_director") else {}),
		"petitions": _encode_value(game.petitions.to_dict() if game.get("petitions") else {}),
		"dealership": _encode_value(game.dealership.to_dict() if game.get("dealership") else {}),
		"motor_pool": _encode_value(game.motor_pool.to_dict() if game.get("motor_pool") else {}),
		"npc_travel": _encode_value(game.npc_travel.to_dict() if game.get("npc_travel") else {}),
		"food_feedback": _encode_value(game.food_feedback.to_dict() if game.get("food_feedback") else {}),
		"lexicon": _encode_value(game.lexicon.to_dict() if game.get("lexicon") else {}),
		# Jeremy 2026-10-06: conversation-system integration — the shared
		# conversation state (per-NPC memories, chatx records/affection,
		# 22-mood affect) persists alongside the lexicon so no channel
		# keeps a private fork across save/load.
		"conversation": _encode_value(game.phone_sys.conversation.get_save_data() if game.get("phone_sys") and game.phone_sys.get("conversation") else {}),
		"trade_routes": _encode_value(game.trade_routes.to_dict() if game.get("trade_routes") else {}),
		# Jeremy 2026-10-10 (vehicle system P1): the vehicle fleet rides
		# along (old saves simply have no "vehicles" key -> empty fleet).
		"vehicles": _encode_value(game.vehicles.to_dict() if game.get("vehicles") else {}),
		# Jeremy 2026-10-07 "AI not rebuilding roads": the painted road
		# network (WorkerAI.roads) was never saved — every load wiped it.
		"roads": _encode_value(game.worker_ai.to_dict() if game.get("worker_ai") else {}),
		"proposals": _encode_value(game.proposals.to_dict() if game.get("proposals") else {}),
		"handyman": _encode_value(game.handyman.to_dict() if game.get("handyman") else {}),
		"founding": _encode_value(game.founding.to_dict() if game.get("founding") else {}),
		"rulers_voice": _encode_value(game.rulers_voice.to_dict() if game.get("rulers_voice") else {}),
		# Jeremy 2026-10-11: faction trade deals ledger rides along.
		"trade_deals": _encode_value(game.trade_deals.to_dict() if game.get("trade_deals") else {}),
		# Jeremy 2026-10-11: war-spare treaties + disaster-aid missions.
		"war_spare": _encode_value(game.war_spare.to_dict() if game.get("war_spare") else {}),
		"disaster_aid": _encode_value(game.disaster_aid.to_dict() if game.get("disaster_aid") else {}),
		# Jeremy 2026-10-11: per-race lifespans (obituary cooldowns ride along;
		# unit ages live on the unit records themselves).
		"lifespans": _encode_value(game.lifespans.to_dict() if game.get("lifespans") else {}),
		# Jeremy 2026-10-11: plague doctrines per faction + outbreak
		# cooldowns (sick flags + skill XP live on the unit records).
		"disease": _encode_value(game.disease.to_dict() if game.get("disease") else {}),
		"faction_leaders": _encode_value(game.faction_leaders.get_save_data() if game.get("faction_leaders") else {}),
		"assface": _encode_value(game.assface.to_dict() if game.get("assface") else {}),
		"family": _encode_value(game.family.to_dict() if game.get("family") else {}),
		"backchannel": _encode_value(game.backchannel.to_dict() if game.get("backchannel") else {}),
		"monasteries": _encode_value(game.monasteries.to_dict() if game.get("monasteries") else {}),
		"crystals": _encode_value(game.crystals.to_dict() if game.get("crystals") else {}),
		"command_posts": _encode_value(game.command_posts.to_dict() if game.get("command_posts") else {}),
		"nuclear": _encode_value(game.nuclear.to_dict() if game.get("nuclear") else {}),
		"worldgen": _encode_value(game.worldgen if game.get("worldgen") != null else {}),
		# Jeremy 2026-10-07 (pet cats): the wild herd — pets included —
		# persists now. Legacy saves without this section load an empty
		# herd (the respawn rule reseeds it); nothing else changes.
		"animals": _encode_value(game.animals.to_dict() if game.get("animals") else {}),
		"next_ids": {
			"unit": game._next_unit_id,
			"town": game._next_town_id,
			"building": game._next_building_id,
			"site": game._next_site_id,
			"zone": game._next_zone_id,
		},
	}
	# Adventure mode state (Jeremy 2026-10-02: was missing from saves).
	if adventure != null and adventure.get("active"):
		data["adventure"] = _encode_value(adventure.save_data())
	return data


## Restore a GameState from a snapshot Dictionary. Returns true on success.
## Pass the world's adventure instance to restore adventure-mode state.
## Fail-closed: check_save() runs first and a rejection leaves the game
## state completely untouched (no half-restored worlds).
static func restore(game: GameState, data: Dictionary, adventure = null) -> bool:
	var chk := check_save(data)
	if not bool(chk.get("ok", false)):
		_last_reject_reason = str(chk.get("reason", "invalid"))
		return false
	_last_reject_reason = ""
	# Ruler name: verbatim, exactly as saved.
	game.ruler_name = str(data.get("ruler_name", ""))
	game.player_faction = str(data.get("player_faction", ""))
	game.active_factions.clear()
	for f in data.get("active_factions", []):
		game.active_factions.append(str(f))
	game.game_time = float(data.get("game_time", 0.0))
	game.day_number = int(data.get("day_number", 1))
	game.is_night = bool(data.get("is_night", false))
	# Jeremy 2026-10-04: JSON round-trips turn int dict keys into strings;
	# normalize town ids back to int so typed `for tid: int` loops and
	# towns.has(int_id) lookups keep working after a load.
	var towns_dec: Dictionary = _decode_value(data.get("towns", {}))
	game.towns.clear()
	for k in towns_dec.keys():
		game.towns[int(k)] = towns_dec[k]
	# Typed arrays: decode gives plain Arrays; cast element-wise.
	var units_dec: Array = _decode_value(data.get("units", []))
	game.units.clear()
	for u in units_dec:
		game.units.append(u as Dictionary)
	var bld_dec: Array = _decode_value(data.get("buildings", []))
	game.buildings.clear()
	for b in bld_dec:
		game.buildings.append(b as Dictionary)
	var sites_dec: Array = _decode_value(data.get("work_sites", []))
	game.work_sites.clear()
	for s in sites_dec:
		var sd: Dictionary = s as Dictionary
		# Jeremy 2026-10-05: wood piles are gone — drop them from old saves.
		# Jeremy 2026-10-05: oil piles are gone too — oil comes from pumps.
		if String(sd.get("kind", "")) == "wood_pile" \
				or String(sd.get("kind", "")) == "rock":
			continue
		game.work_sites.append(sd)
	var pickups_dec: Array = _decode_value(data.get("pickups", []))
	game.pickups.clear()
	for p in pickups_dec:
		game.pickups.append(p as Dictionary)
		# Keep the id counter ahead of any loaded pickup.
		game._next_pickup_id = maxi(game._next_pickup_id, int((p as Dictionary).get("id", 0)) + 1)
	game.pickup_version += 1  # wholesale array refill: invalidate pickup grids
	var zones_dec: Array = _decode_value(data.get("zones", []))
	game.zones.clear()
	for z in zones_dec:
		game.zones.append(z as Dictionary)
	# Jeremy 2026-10-05 perf: records were appended directly, bypassing
	# add_* — rebuild the O(1) id indexes and invalidate the zone cache.
	game.rebuild_lookup_indexes()
	game.bump_zone_version()
	var res_data: Dictionary = _decode_value(data.get("resources", {}))
	if game.resources:
		game.resources.from_dict(res_data)
	var dip_data: Dictionary = _decode_value(data.get("diplomacy", {}))
	if game.diplomacy:
		game.diplomacy.reset(game.active_factions)
		if not dip_data.is_empty():
			game.diplomacy.from_dict(dip_data)
	# Port-wave subsystems (guarded: null in bare tests / old saves).
	if game.get("seasons"):
		game.seasons.from_dict(_decode_value(data.get("seasons", {})))
	if game.get("farming"):
		game.farming.from_dict(_decode_value(data.get("farming", {})))
	if game.get("industry"):
		game.industry.from_dict(_decode_value(data.get("industry", {})))
	if game.get("disasters"):
		game.disasters.from_dict(_decode_value(data.get("disasters", {})))
	if game.get("hydro"):
		game.hydro.from_dict(_decode_value(data.get("hydro", {})))
	if game.get("arty"):
		game.arty.from_dict(_decode_value(data.get("artillery", {})))
	if game.get("undead"):
		game.undead.from_dict(_decode_value(data.get("undead", {})))
	if game.get("border_walls"):
		game.border_walls.from_dict(_decode_value(data.get("border_walls", {})))
	if game.get("starfort_bases"):
		game.starfort_bases.from_dict(_decode_value(data.get("starfort_bases", {})))
	if game.get("court_sys"):
		game.court_sys.from_dict(_decode_value(data.get("court", {})))
	if game.get("phone_sys"):
		game.phone_sys.from_dict(_decode_value(data.get("phone", {})))
		if game.phone_sys.get("hearsay"):
			game.phone_sys.hearsay.from_dict(
				_decode_value(data.get("hearsay", {})))
	if game.get("ai_director"):
		game.ai_director.from_dict(_decode_value(data.get("ai_director", {})))
	if game.get("petitions"):
		game.petitions.from_dict(_decode_value(data.get("petitions", {})))
	if game.get("dealership"):
		game.dealership.from_dict(_decode_value(data.get("dealership", {})))
	if game.get("motor_pool"):
		game.motor_pool.from_dict(_decode_value(data.get("motor_pool", {})))
	if game.get("npc_travel"):
		game.npc_travel.from_dict(_decode_value(data.get("npc_travel", {})))
	if game.get("food_feedback"):
		game.food_feedback.from_dict(_decode_value(data.get("food_feedback", {})))
	if game.get("handyman"):
		game.handyman.from_dict(_decode_value(data.get("handyman", {})))
	if game.get("founding"):
		game.founding.from_dict(_decode_value(data.get("founding", {})))
	if game.get("rulers_voice"):
		game.rulers_voice.from_dict(_decode_value(data.get("rulers_voice", {})))
	if game.get("lexicon"):
		game.lexicon.from_dict(_decode_value(data.get("lexicon", {})))
	# Jeremy 2026-10-06: restore the shared conversation state (memories,
	# chatx records/affection, mood affect) into the phone's engine.
	if game.get("phone_sys") and game.phone_sys.get("conversation"):
		game.phone_sys.conversation.load_save_data(_decode_value(data.get("conversation", {})))
	if game.get("trade_routes"):
		game.trade_routes.from_dict(_decode_value(data.get("trade_routes", {})))
	if game.get("vehicles"):
		game.vehicles.from_dict(_decode_value(data.get("vehicles", {})))
	# Jeremy 2026-10-07 "AI not rebuilding roads": restore the painted road
	# network (old saves simply have no "roads" key -> empty network, and
	# the roadbuilder crew + zoning rings repaint it live).
	if game.get("worker_ai"):
		game.worker_ai.from_dict(_decode_value(data.get("roads", {})))
	if game.get("proposals"):
		game.proposals.from_dict(_decode_value(data.get("proposals", {})))
	if game.get("trade_deals"):
		game.trade_deals.from_dict(_decode_value(data.get("trade_deals", {})))
	if game.get("war_spare"):
		game.war_spare.from_dict(_decode_value(data.get("war_spare", {})))
	if game.get("disaster_aid"):
		game.disaster_aid.from_dict(_decode_value(data.get("disaster_aid", {})))
	if game.get("lifespans"):
		game.lifespans.from_dict(_decode_value(data.get("lifespans", {})))
	if game.get("disease"):
		game.disease.from_dict(_decode_value(data.get("disease", {})))
	# Jeremy 2026-10-06: picked leader candidates persist (no re-roll on load).
	if game.get("faction_leaders"):
		game.faction_leaders.load_save_data(_decode_value(data.get("faction_leaders", {})))
	if game.get("assface"):
		game.assface.from_dict(_decode_value(data.get("assface", {})))
	if game.get("family"):
		game.family.from_dict(_decode_value(data.get("family", {})))
	if game.get("backchannel"):
		game.backchannel.from_dict(_decode_value(data.get("backchannel", {})))
	# Jeremy 2026-10-04: Seven Monasteries persist (positions are random).
	if game.get("monasteries"):
		game.monasteries.from_dict(_decode_value(data.get("monasteries", {})))
	# Jeremy 2026-10-04: Seven Dark Crystals persist too.
	if game.get("crystals"):
		game.crystals.from_dict(_decode_value(data.get("crystals", {})))
	# Jeremy 2026-10-06: Command Posts capture log persists.
	if game.get("command_posts"):
		game.command_posts.from_dict(_decode_value(data.get("command_posts", {})))
	# Jeremy 2026-10-04: nuclear warfare persists (zones, fallout).
	if game.get("nuclear"):
		game.nuclear.from_dict(_decode_value(data.get("nuclear", {})))
	# Jeremy 2026-10-07 (pet cats): restore the wild herd. Legacy saves
	# have no "animals" section — from_dict({}) leaves the herd empty and
	# the respawn rule reseeds it, same as before this section existed.
	if game.get("animals"):
		game.animals.from_dict(_decode_value(data.get("animals", {})))
	game.worldgen = _decode_value(data.get("worldgen", {}))
	var nid: Dictionary = data.get("next_ids", {})
	game._next_unit_id = int(nid.get("unit", 1))
	game._next_town_id = int(nid.get("town", 1))
	game._next_building_id = int(nid.get("building", 1))
	game._next_site_id = int(nid.get("site", 1))
	game._next_zone_id = int(nid.get("zone", 1))
	# Adventure mode state (was missing from saves — Jeremy 2026-10-02).
	if adventure != null and data.has("adventure"):
		var adv_data: Dictionary = _decode_value(data.get("adventure", {}))
		if not adv_data.is_empty():
			adventure.load_data(adv_data)
	return true


static func _slot_path(slot: int) -> String:
	return "%s/%s%d%s" % [SAVE_DIR, SLOT_PREFIX, slot, SAVE_EXT]


static func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)


## Write a snapshot to a slot. Returns true on success.
static func save_slot(slot: int, data: Dictionary) -> bool:
	if slot < 0 or slot >= MAX_SLOTS:
		return false
	_ensure_dir()
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true


## Read a snapshot from a slot. Returns {} when empty/corrupt.
static func load_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= MAX_SLOTS:
		return {}
	if not FileAccess.file_exists(_slot_path(slot)):
		return {}
	var f := FileAccess.open(_slot_path(slot), FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}


static func delete_slot(slot: int) -> void:
	if FileAccess.file_exists(_slot_path(slot)):
		DirAccess.remove_absolute(_slot_path(slot))


## Slot metadata for the menu list: [{slot, day, ruler, factions, empty}].
static func list_slots() -> Array:
	_ensure_dir()
	var out := []
	for i in MAX_SLOTS:
		var d := load_slot(i)
		if d.is_empty():
			out.append({"slot": i, "empty": true})
		else:
			var facs: Array = d.get("active_factions", [])
			out.append({
				"slot": i,
				"empty": false,
				"day": int(d.get("saved_day", 1)),
				"ruler": str(d.get("ruler_name", "?")),
				"factions": facs,
			})
	return out
