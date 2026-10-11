class_name SimInteriors
extends RefCounted
## Cursing Gnomes — Stardew-style building interiors (Milestone 6).
##
## Design ported from the HTML build (not its code):
##   - Every enterable building type has a curated floor plan: furniture
##     pieces with {id, kind, x, y, w, h, label, need, room}.
##   - Furniture "needs" (sleep/eat/wash/bladder/social/rest) are what NPCs
##     satisfy while inside — the same urge words the mind system uses.
##   - The player can enter/exit, buy furniture (furniture shop), and move
##     pieces in arrange mode. Interior state lives on the building record
##     so it survives save/load as plain numbers/strings.
##
## INTERIOR RECORD SCHEMA (on building record, key "interior"):
##   occupants: Array[int] (unit ids currently inside)
##   player_furniture: Array[Dictionary] (extra pieces the player placed)
##   arranged: Dictionary (piece_id -> {"x": float, "y": float} overrides)
##
## FURNITURE PIECE SCHEMA:
##   id, kind, x, y, w, h, label, need, room
## Kinds map to extracted art via art_key_for_kind(); kinds without art
## (door, window, tv) render as procedural shapes in interior_view.
##
## Pure logic — no rendering, no input, no audio.


## Interior canvas size, ported from the HTML (C71: ~1.5-2x dollhouse).
const ROOM_W := 1500.0
const ROOM_H := 1050.0

## Building types the player/NPCs can walk into. Walls, towers, silos,
## garden/fence/pier/well have no interior; everything else enterable must
## be complete + alive.
const ENTERABLE := ["house", "farm", "sawmill", "quarry", "mine",
	"clinic", "fire_station", "barracks", "town_hall", "townhall", "hall",
	"restaurant", "soul_cafe", "hotel", "inn", "weaponsmith",
	"farmhouse", "guild_hall", "courthouse", "bathhouse", "guard_house",
	"storage", "horse_stable", "windmill",
	"gov_office", "gov_treasury", "gov_war_office", "gov_justice",
	"knights_castle", "mage_spire", "war_hut", "tome_library", "necropolis",
	"camp", "cannon_foundry", "field_camp", "medic_camp", "equip_camp",
	"armory", "shooting_range", "vehicle_depot", "nuke_silo"]

## Furniture kind -> extracted art key (faction suffix added for the
## FACTION_ART_KINDS below). Empty string = no art; interior_view draws a
## procedural shape instead.
const KIND_ART := {
	"bed": "furn_bed", "bunk": "furn_bunk", "crib": "furn_crib",
	"chair": "furn_chair", "stool": "furn_stool", "couch": "furn_sofa",
	"table": "furn_table", "lamp_table": "furn_lamp_table",
	"counter": "furn_counter", "fridge": "furn_fridge", "stove": "furn_stove",
	"sink": "furn_sink", "toilet": "furn_toilet", "shower": "furn_shower",
	"tub": "furn_tub", "bath": "furn_bath", "rug": "furn_rug_rect",
	"rug_round": "furn_rug_round", "rug_entry": "furn_rug_entry",
	"lamp": "furn_lamp", "plant": "furn_plant", "plant_tall": "furn_plant_tall",
	"bookshelf": "furn_bookshelf", "shelf": "furn_shelf", "wardrobe": "furn_wardrobe",
	"desk": "furn_desk", "board": "furn_board", "painting": "furn_painting",
	"chandelier": "furn_chandelier", "forge": "furn_forge", "rack": "furn_rack",
	"bar": "furn_bar", "jail_bars": "furn_jail_bars", "jail_door": "furn_jail_door",
	"fire": "fire_lg_0", "door": "furn_door", "window": "furn_window",
	"tv": "furn_tv", "divider": "furn_divider",
}

## Furniture kinds with per-faction extracted art (furn_chair_human ...).
## Jeremy 2026-10-07: the suffix was only applied to bed/bunk AND used the
## plural faction ("furn_bed_humans"), which matches NO file — beds, chairs,
## tables, sofas, lamps, toilets, wardrobes, stoves, counters, shelves,
## cribs and dividers all silently fell back to colored rectangles.
## Now every faction-variant kind resolves to its real sprite.

## Needs an interior piece can satisfy (mirrors the urge vocabulary).
const NEEDS: Array[String] = ["sleep", "eat", "wash", "bladder", "social", "rest"]


var _gs: GameState


func _init(game_state: GameState) -> void:
	_gs = game_state


## True when a building type can be entered at all.
static func is_enterable(btype: String) -> bool:
	return btype in ENTERABLE


## True when this specific building record can be entered right now.
static func can_enter(building: Dictionary) -> bool:
	return is_enterable(String(building.get("type", ""))) \
		and bool(building.get("complete", false)) \
		and bool(building.get("alive", false))


const FACTION_ART_KINDS: Array[String] = [
	"bed", "bunk", "crib", "chair", "counter", "divider", "lamp",
	"shelf", "couch", "stove", "table", "toilet", "wardrobe",
]

## Singular faction name for furniture art. Undead have no furniture set;
## they use the gnome set as the neutral default (appearance_key parity).
static func _furn_faction(faction: String) -> String:
	var singular := {
		"humans": "human", "ogres": "ogre", "elves": "elf",
		"gnomes": "gnome", "undead": "gnome",
		"human": "human", "ogre": "ogre", "elf": "elf", "gnome": "gnome",
	}
	return String(singular.get(faction.to_lower(), "gnome"))


## Resolves a furniture kind to an extracted art key, or "" for procedural.
## Faction-variant kinds resolve to furn_<base>_<singular faction>
## (e.g. "furn_chair_human"); kinds without art return "".
static func art_key_for_kind(kind: String, faction: String = "humans") -> String:
	var base: String = String(KIND_ART.get(kind, ""))
	if base == "":
		return ""
	if kind in FACTION_ART_KINDS:
		return base + "_" + _furn_faction(faction)
	return base


## Returns the interior state dict for a building, creating it if missing.
func ensure_interior(building: Dictionary) -> Dictionary:
	if not building.has("interior"):
		building["interior"] = {"occupants": [], "player_furniture": [], "arranged": {}}
	var intr: Dictionary = building["interior"]
	for k: String in ["occupants", "player_furniture", "arranged"]:
		if not intr.has(k):
			intr[k] = [] if k != "arranged" else {}
	return intr


## Moves a unit inside a building. Sets unit["inside_building_id"], appends
## to occupants, parks the unit's world position at the door.
## Returns false when the building can't be entered or the unit is dead.
func enter(building: Dictionary, unit: Dictionary) -> bool:
	if not can_enter(building):
		return false
	if not unit.get("alive", false):
		return false
	var intr: Dictionary = ensure_interior(building)
	var uid: int = int(unit.get("id", 0))
	if not intr["occupants"].has(uid):
		(intr["occupants"] as Array).append(uid)
	unit["inside_building_id"] = int(building.get("id", 0))
	_gs.bus.interior_entered.emit(int(building.get("id", 0)), uid)
	return true


## Moves a unit back outside. Returns false when the unit isn't inside.
func exit(unit: Dictionary) -> bool:
	var bid: int = int(unit.get("inside_building_id", 0))
	if bid <= 0:
		return false
	var building: Dictionary = _find_building(bid)
	if not building.is_empty():
		var intr: Dictionary = ensure_interior(building)
		(intr["occupants"] as Array).erase(int(unit.get("id", 0)))
	unit["inside_building_id"] = 0
	_gs.bus.interior_exited.emit(bid, int(unit.get("id", 0)))
	return true


## True when the unit is currently inside any building.
static func is_inside(unit: Dictionary) -> bool:
	return int(unit.get("inside_building_id", 0)) > 0


## Unit ids currently inside a building.
func occupants_of(building: Dictionary) -> Array:
	return (ensure_interior(building)["occupants"] as Array).duplicate()


## All furniture for a building: default floor plan + player pieces, with
## arrange-mode overrides applied. Returned pieces are copies.
func furniture_of(building: Dictionary) -> Array:
	var btype: String = String(building.get("type", ""))
	var faction: String = String(building.get("faction", "humans"))
	var out: Array = []
	for p: Dictionary in _plan_for(btype, faction):
		out.append(_apply_override(building, p))
	var intr: Dictionary = ensure_interior(building)
	for p: Dictionary in intr["player_furniture"]:
		out.append(_apply_override(building, p))
	return out


## Player buys a furniture piece for a building (furniture shop).
## Returns the piece record, or {} when the kind is unknown / not enterable.
func place_furniture(building: Dictionary, kind: String, x: float, y: float,
		label: String = "") -> Dictionary:
	if not can_enter(building):
		return {}
	if not KIND_ART.has(kind):
		return {}
	var intr: Dictionary = ensure_interior(building)
	var piece: Dictionary = {
		"id": "pf%d" % (intr["player_furniture"] as Array).size(),
		"kind": kind,
		"x": clampf(x, 0.0, ROOM_W - 40.0),
		"y": clampf(y, 0.0, ROOM_H - 40.0),
		"w": 60.0, "h": 60.0,
		"label": label if label != "" else kind.capitalize(),
		"need": "",
		"room": "Custom",
	}
	(intr["player_furniture"] as Array).append(piece)
	return piece


## Arrange mode: move any piece. Returns false for unknown ids.
func move_furniture(building: Dictionary, piece_id: String,
		x: float, y: float) -> bool:
	var intr: Dictionary = ensure_interior(building)
	var found: bool = false
	for p: Dictionary in intr["player_furniture"]:
		if String(p.get("id", "")) == piece_id:
			p["x"] = clampf(x, 0.0, ROOM_W - 40.0)
			p["y"] = clampf(y, 0.0, ROOM_H - 40.0)
			found = true
	if found:
		return true
	for p: Dictionary in _plan_for(String(building.get("type", "")),
			String(building.get("faction", "humans"))):
		if String(p.get("id", "")) == piece_id:
			(intr["arranged"] as Dictionary)[piece_id] = {
				"x": clampf(x, 0.0, ROOM_W - 40.0),
				"y": clampf(y, 0.0, ROOM_H - 40.0),
			}
			return true
	return false


## Finds a furniture piece satisfying a need (for NPC urge behavior).
## Returns the piece dict or {}.
func find_for_need(building: Dictionary, need: String) -> Dictionary:
	for p: Dictionary in furniture_of(building):
		if String(p.get("need", "")) == need:
			return p
	return {}


func _apply_override(building: Dictionary, piece: Dictionary) -> Dictionary:
	var c: Dictionary = piece.duplicate()
	var intr: Dictionary = ensure_interior(building)
	var ov: Dictionary = (intr["arranged"] as Dictionary).get(
		String(piece.get("id", "")), {})
	if not ov.is_empty():
		c["x"] = float(ov.get("x", c["x"]))
		c["y"] = float(ov.get("y", c["y"]))
	return c


func _find_building(building_id: int) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if int(b.get("id", 0)) == building_id:
			return b
	return {}


## --- Floor plans (ported from the HTML getInteriorLayout, condensed) --------
## Each entry: id, kind, x, y, w, h, label, need, room. Coordinates are in
## the 1500x1050 dollhouse canvas.

static func _p(pid: String, kind: String, x: float, y: float, w: float, h: float,
		label: String, need: String = "", room: String = "") -> Dictionary:
	return {"id": pid, "kind": kind, "x": x, "y": y, "w": w, "h": h,
		"label": label, "need": need, "room": room}


static func _plan_for(btype: String, faction: String) -> Array:
	match btype:
		"house":
			return _plan_house()
		"clinic":
			return _plan_clinic()
		"town_hall", "townhall", "hall":
			return _plan_hall()
		"barracks":
			return _plan_barracks()
		"fire_station":
			return _plan_fire_station()
		"restaurant", "soul_cafe":
			return _plan_eatery()
		"hotel", "inn":
			return _plan_lodging()
		"guild_hall":
			return _plan_feast()
		"courthouse":
			return _plan_court()
		"gov_office":
			return _plan_gov("Town Hall Seal")
		"gov_treasury":
			return _plan_gov("Treasury Seal")
		"gov_war_office":
			return _plan_gov("War Office Seal")
		"gov_justice":
			return _plan_gov("Justice Seal")
		"bathhouse":
			return _plan_baths()
		"farmhouse":
			return _plan_homestead()
		"guard_house":
			return _plan_garrison()
		"storage", "stock_gold", "stock_wood", "stock_food", "stock_oil", "stock_seeds":
			return _plan_stores()
		"weaponsmith":
			return _plan_smithy()
		"camp", "field_camp", "medic_camp", "equip_camp":
			return _plan_field()
		"armory", "vehicle_depot", "cannon_foundry":
			return _plan_workshop()
		"shooting_range":
			return _plan_range()
		"knights_castle", "mage_spire", "war_hut", "tome_library", "necropolis":
			return _plan_grand()
		"nuke_silo":
			return _plan_control()
		"farm", "sawmill", "quarry", "mine", "horse_stable", "windmill", "flesh_farm":
			return _plan_workfloor()
		_:
			return _plan_generic()


## Standard bathroom trio (toilet + sink + tub), ported from the HTML
## bathroom requirement: bathrooms (toilet, sink, tub) in ALL buildings.
static func _bath(prefix: String, x: float, y: float, room: String = "Bath") -> Array:
	return [
		_p(prefix + "_toilet", "toilet", x, y, 36, 40, "Toilet", "bladder", room),
		_p(prefix + "_sink", "sink", x + 50, y, 50, 45, "Sink", "wash", room),
		_p(prefix + "_tub", "tub", x, y + 60, 90, 50, "Tub", "wash", room),
	]


## Eatery (HTML restaurant interior, condensed): front desk, kitchen,
## dining room, bath.
static func _plan_eatery() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("register", "counter", 450, 160, 160, 50, "Register", "", "Front Desk"),
		_p("counter", "counter", 720, 130, 140, 55, "Kitchen", "eat", "Kitchen"),
		_p("fridge", "fridge", 820, 220, 70, 100, "Fridge", "eat", "Kitchen"),
		_p("stove", "stove", 720, 220, 55, 50, "Grill", "eat", "Kitchen"),
		_p("table1", "table", 160, 300, 100, 70, "Table", "eat", "Dining"),
		_p("chair1a", "chair", 120, 360, 36, 36, "Chair", "eat", "Dining"),
		_p("chair1b", "chair", 200, 360, 36, 36, "Chair", "eat", "Dining"),
		_p("table2", "table", 360, 400, 100, 70, "Table", "eat", "Dining"),
		_p("chair2a", "chair", 320, 460, 36, 36, "Chair", "eat", "Dining"),
		_p("chair2b", "chair", 400, 460, 36, 36, "Chair", "eat", "Dining"),
	]
	out.append_array(_bath("rest", 1180, 620))
	return out


## Hotel/inn: lobby, guest room, bath.
static func _plan_lodging() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("counter", "counter", 450, 150, 200, 55, "Front desk", "", "Lobby"),
		_p("couch", "couch", 450, 280, 150, 65, "Lobby couch", "rest", "Lobby"),
		_p("bed1", "bed", 140, 140, 130, 80, "Guest bed", "sleep", "Rooms"),
		_p("bed2", "bed", 140, 280, 130, 80, "Guest bed", "sleep", "Rooms"),
		_p("table", "table", 700, 560, 110, 70, "Table", "eat", "Rooms"),
		_p("plant", "plant", 1290, 830, 46, 46, "Fern", "", "Lobby"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("lodg", 1180, 620))
	return out


## Guild hall feast hall (HTML feast-hall plan, condensed).
static func _plan_feast() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("gtable", "table", 450, 330, 240, 80, "Long table", "social", "Feast Hall"),
		_p("gchair1", "chair", 360, 420, 40, 40, "Chair", "social", "Feast Hall"),
		_p("gchair2", "chair", 450, 420, 40, 40, "Chair", "social", "Feast Hall"),
		_p("gchair3", "chair", 540, 420, 40, 40, "Chair", "social", "Feast Hall"),
		_p("gchair4", "chair", 450, 240, 40, 40, "Chair", "social", "Feast Hall"),
		_p("gmaster", "chair", 450, 150, 60, 60, "Guildmaster seat", "rest", "Feast Hall"),
		_p("gtrophy", "counter", 720, 210, 90, 110, "Trophy shelf", "", "Feast Hall"),
		_p("gbanner", "rug", 180, 330, 60, 120, "Banner", "", "Feast Hall"),
	]
	out.append_array(_bath("guild", 1180, 620))
	return out


## Courthouse: courtroom, offices, bath.
static func _plan_court() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("bench", "counter", 500, 140, 300, 60, "Judge bench", "", "Courtroom"),
		_p("jury1", "chair", 420, 300, 40, 40, "Chair", "rest", "Courtroom"),
		_p("jury2", "chair", 520, 300, 40, 40, "Chair", "rest", "Courtroom"),
		_p("jury3", "chair", 620, 300, 40, 40, "Chair", "rest", "Courtroom"),
		_p("desk", "desk", 1050, 140, 110, 60, "Clerk desk", "", "Offices"),
		_p("bookshelf", "bookshelf", 1050, 260, 100, 50, "Law books", "", "Offices"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("court", 1180, 620))
	return out


## Government office (HTML C63 gov plan, condensed): entry, reception,
## council hall, two advisor cubicles (dividers + advisor's desk + chair —
## the officers work INSIDE at claimed desks), bathroom. The seal painting
## differs per office ("Town Hall Seal" / "Treasury Seal" / ...).
static func _plan_gov(seal_label: String) -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door", "", "Entry"),
		_p("entryrug", "rug", 680, 820, 200, 100, "Entry Rug", "", "Entry"),
		_p("plant_d1", "plant", 540, 870, 46, 46, "Potted Fern", "", "Entry"),
		_p("plant_d2", "plant", 880, 870, 46, 46, "Potted Fern", "", "Entry"),
		_p("window1", "window", 300, 40, 100, 50, "Window"),
		_p("window2", "window", 700, 40, 100, 50, "Window"),
		_p("window3", "window", 1100, 40, 100, 50, "Window"),
		_p("paint1", "painting", 500, 100, 120, 60, seal_label),
		_p("paint2", "painting", 900, 100, 120, 60, "Charter"),
		_p("counter_main", "counter", 300, 180, 200, 60, "Reception Counter", "", "Lobby"),
		_p("books1", "shelf", 140, 160, 120, 50, "Bookshelf", "", "Lobby"),
		_p("books2", "shelf", 1240, 160, 120, 50, "Bookshelf", "", "Lobby"),
		_p("lamp1", "lamp", 180, 300, 38, 38, "Lamp", "", "Lobby"),
		_p("table1", "table", 400, 460, 180, 100, "Council Table", "", "Hall"),
		_p("t1cw", "chair", 300, 490, 40, 40, "Chair", "rest", "Hall"),
		_p("t1ce", "chair", 560, 490, 40, 40, "Chair", "rest", "Hall"),
		_p("t1cn", "chair", 470, 400, 40, 40, "Chair", "rest", "Hall"),
		_p("t1cs", "chair", 470, 580, 40, 40, "Chair", "rest", "Hall"),
		_p("carpet1", "rug", 400, 490, 280, 200, "Carpet", "", "Hall"),
		_p("table2", "table", 950, 460, 180, 100, "Council Table", "", "Hall"),
		_p("t2cw", "chair", 850, 490, 40, 40, "Chair", "rest", "Hall"),
		_p("t2ce", "chair", 1110, 490, 40, 40, "Chair", "rest", "Hall"),
		_p("t2cn", "chair", 1020, 400, 40, 40, "Chair", "rest", "Hall"),
		_p("t2cs", "chair", 1020, 580, 40, 40, "Chair", "rest", "Hall"),
		_p("carpet2", "rug", 950, 490, 280, 200, "Carpet", "", "Hall"),
		_p("cubdiv1a", "divider", 280, 700, 160, 20, "", "", "Office"),
		_p("cubdiv1b", "divider", 280, 780, 20, 120, "", "", "Office"),
		_p("desk1", "desk", 330, 750, 130, 70, "Advisor's Desk", "", "Office"),
		_p("dchair1", "chair", 330, 840, 40, 40, "Chair", "rest", "Office"),
		_p("cubdiv2a", "divider", 620, 700, 160, 20, "", "", "Office"),
		_p("cubdiv2b", "divider", 760, 780, 20, 120, "", "", "Office"),
		_p("desk2", "desk", 660, 750, 130, 70, "Advisor's Desk", "", "Office"),
		_p("dchair2", "chair", 660, 840, 40, 40, "Chair", "rest", "Office"),
	]
	out.append_array(_bath("gov", 1000, 780, "Bathroom"))
	return out


## Bathhouse: changing room, communal baths.
static func _plan_baths() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("bench", "couch", 250, 420, 160, 50, "Bench", "rest", "Changing"),
		_p("tub1", "tub", 500, 200, 120, 60, "Hot tub", "wash", "Baths"),
		_p("tub2", "tub", 700, 200, 120, 60, "Cold tub", "wash", "Baths"),
		_p("shower1", "shower", 500, 360, 80, 100, "Shower", "wash", "Baths"),
		_p("shower2", "shower", 640, 360, 80, 100, "Shower", "wash", "Baths"),
		_p("plant", "plant", 1290, 830, 46, 46, "Fern", "", "Changing"),
	]
	out.append_array(_bath("bath", 1180, 620))
	return out


## Farmhouse: kitchen, bedroom, bath.
static func _plan_homestead() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("stove", "stove", 720, 140, 60, 50, "Stove", "eat", "Kitchen"),
		_p("table", "table", 620, 420, 130, 75, "Dining table", "eat", "Dining"),
		_p("bed", "bed", 140, 140, 140, 90, "Double bed", "sleep", "Bedroom"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("home2", 1180, 620))
	return out


## Guard house: bunks, office, bath.
static func _plan_garrison() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("bunk1", "bunk", 140, 140, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("bunk2", "bunk", 140, 240, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("desk", "desk", 700, 140, 110, 60, "Watch desk", "", "Office"),
		_p("rack", "rack", 1000, 160, 100, 80, "Arms rack", "", "Office"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("garr", 1180, 620))
	return out


## Storage: shelves, counter, bath.
static func _plan_stores() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("shelf1", "shelf", 300, 140, 120, 60, "Shelf", "", "Stores"),
		_p("shelf2", "shelf", 300, 260, 120, 60, "Shelf", "", "Stores"),
		_p("counter", "counter", 700, 140, 120, 60, "Counter", "", "Stores"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("store", 1180, 620))
	return out


## Weaponsmith: counter, forge, rack, bath.
static func _plan_smithy() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("counter", "counter", 450, 150, 200, 55, "Shop counter", "", "Shop"),
		_p("forge", "forge", 800, 160, 140, 100, "Forge", "", "Smithy"),
		_p("rack", "rack", 1000, 160, 100, 80, "Weapon rack", "", "Smithy"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("smith", 1180, 620))
	return out


## Field camps: bunks, field bath.
static func _plan_field() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("bunk1", "bunk", 140, 140, 110, 60, "Bunk", "sleep", "Tents"),
		_p("bunk2", "bunk", 140, 240, 110, 60, "Bunk", "sleep", "Tents"),
		_p("table", "table", 700, 560, 120, 70, "Camp table", "eat", "Tents"),
		_p("fire", "fire", 400, 520, 80, 80, "Campfire", "rest", "Tents"),
	]
	out.append_array(_bath("field", 1180, 620, "Field Bath"))
	return out


## Armory / depot / foundry: workshop floor, bath.
static func _plan_workshop() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("forge", "forge", 500, 160, 140, 100, "Forge", "", "Workshop"),
		_p("rack1", "rack", 800, 160, 100, 80, "Rack", "", "Workshop"),
		_p("rack2", "rack", 950, 160, 100, 80, "Rack", "", "Workshop"),
		_p("table", "table", 700, 560, 120, 70, "Workbench", "", "Workshop"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("wshop", 1180, 620))
	return out


## Shooting range: range floor, bath.
static func _plan_range() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("rack", "rack", 300, 160, 100, 80, "Bow rack", "", "Range"),
		_p("table", "table", 700, 200, 120, 70, "Lane table", "", "Range"),
		_p("bench", "couch", 250, 420, 160, 50, "Bench", "rest", "Lounge"),
	]
	out.append_array(_bath("range", 1180, 620))
	return out


## Faction-unique grand halls (castle, spire, war hut, library, necropolis).
static func _plan_grand() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("table", "table", 450, 330, 230, 80, "Feast table", "social", "Great Hall"),
		_p("chair1", "chair", 360, 420, 40, 40, "Chair", "social", "Great Hall"),
		_p("chair2", "chair", 540, 420, 40, 40, "Chair", "social", "Great Hall"),
		_p("bookshelf", "bookshelf", 1000, 160, 120, 60, "Tombs & tomes", "", "Study"),
		_p("desk", "desk", 700, 160, 110, 60, "Study desk", "", "Study"),
		_p("banner", "rug", 300, 260, 50, 100, "Banner", "", "Great Hall"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("grand", 1180, 620))
	return out


## Nuke silo control room, bath.
static func _plan_control() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("counter", "counter", 500, 160, 200, 55, "Control console", "", "Control"),
		_p("board", "board", 500, 260, 120, 70, "Status board", "", "Control"),
		_p("chair", "chair", 550, 350, 40, 40, "Operator seat", "rest", "Control"),
	]
	out.append_array(_bath("ctrl", 1180, 620))
	return out


## Production buildings: work floor, bath.
static func _plan_workfloor() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("table", "table", 640, 420, 100, 70, "Workbench", "", "Floor"),
		_p("shelf", "shelf", 1000, 160, 100, 60, "Tool shelf", "", "Floor"),
		_p("fire", "fire", 400, 520, 80, 80, "Hearth", "rest", "Floor"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("floor", 1180, 620))
	return out


static func _plan_house() -> Array:
	return [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("bed", "bed", 140, 140, 140, 90, "Double Bed", "sleep", "Bedroom"),
		_p("nightstand", "lamp_table", 300, 130, 50, 50, "Nightstand", "", "Bedroom"),
		_p("bedrug", "rug_round", 210, 260, 190, 110, "Rug", "", "Bedroom"),
		_p("fridge", "fridge", 1150, 130, 70, 100, "Fridge", "eat", "Kitchen"),
		_p("stove", "stove", 1250, 140, 60, 50, "Stove", "eat", "Kitchen"),
		_p("sink", "sink", 1050, 140, 50, 45, "Sink", "wash", "Kitchen"),
		_p("table", "table", 620, 420, 130, 75, "Dining table", "eat", "Dining"),
		_p("chair1", "chair", 540, 500, 40, 40, "Chair", "social", "Dining"),
		_p("chair2", "chair", 620, 520, 40, 40, "Chair", "social", "Dining"),
		_p("chair3", "chair", 700, 500, 40, 40, "Chair", "social", "Dining"),
		_p("shower", "shower", 1180, 620, 80, 100, "Shower", "wash", "Bath"),
		_p("toilet", "toilet", 1060, 650, 36, 40, "Toilet", "bladder", "Bath"),
		_p("tub", "tub", 1060, 720, 90, 50, "Tub", "wash", "Bath"),
		_p("couch", "couch", 160, 640, 150, 65, "Couch", "rest", "Living"),
		_p("plant1", "plant", 1290, 830, 46, 46, "Fern", "", "Living"),
		_p("lamp1", "lamp", 420, 700, 38, 38, "Lamp", "", "Living"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
		_p("window2", "window", 1000, 40, 80, 50, "Window"),
	]


static func _plan_clinic() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("desk", "table", 650, 140, 120, 55, "Reception desk", "", "Reception"),
		_p("nurse", "chair", 650, 220, 36, 36, "Nurse seat", "", "Reception"),
		_p("bed1", "bed", 140, 160, 130, 80, "Exam bed", "rest", "Ward"),
		_p("bed2", "bed", 140, 320, 130, 80, "Recovery bed", "rest", "Ward"),
		_p("cabinet", "counter", 1050, 140, 80, 90, "Medicine cabinet", "", "Ward"),
		_p("sink", "sink", 1050, 280, 60, 50, "Wash sink", "wash", "Ward"),
		_p("waiting", "couch", 700, 560, 140, 55, "Waiting couch", "rest", "Waiting"),
		_p("staff_bed", "bed", 1050, 700, 120, 70, "Doctor bed", "sleep", "Staff Quarters"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("clinic", 1180, 620))
	return out


static func _plan_hall() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("throne", "chair", 700, 140, 70, 70, "Seat", "rest", "Throne"),
		_p("table", "table", 640, 420, 180, 80, "Council table", "social", "Council"),
		_p("chair1", "chair", 540, 520, 40, 40, "Chair", "social", "Council"),
		_p("chair2", "chair", 660, 520, 40, 40, "Chair", "social", "Council"),
		_p("chair3", "chair", 780, 520, 40, 40, "Chair", "social", "Council"),
		_p("banner", "rug", 300, 260, 50, 100, "Banner", "", "Hall"),
		_p("plant_h", "plant", 360, 700, 46, 46, "Fern", "", "Hall"),
		_p("window", "window", 300, 40, 100, 50, "Window"),
		_p("window2", "window", 1000, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("hall", 1180, 620))
	return out


static func _plan_barracks() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("bunk1", "bunk", 140, 120, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("bunk2", "bunk", 140, 220, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("bunk3", "bunk", 140, 320, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("bunk4", "bunk", 140, 420, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("rack", "rack", 1000, 160, 100, 80, "Arms rack", "", "Armory"),
		_p("table", "table", 700, 600, 120, 70, "Mess table", "eat", "Mess"),
		_p("chair1", "chair", 640, 680, 36, 36, "Chair", "eat", "Mess"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("barr", 1180, 620))
	return out


static func _plan_fire_station() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("bunk1", "bunk", 140, 140, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("bunk2", "bunk", 140, 240, 110, 60, "Bunk", "sleep", "Bunks"),
		_p("rack", "rack", 1000, 160, 100, 80, "Gear rack", "", "Bay"),
		_p("table", "table", 700, 560, 120, 70, "Mess table", "eat", "Mess"),
		_p("sink", "sink", 1050, 560, 60, 50, "Wash sink", "wash", "Mess"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("fire", 1180, 620))
	return out


static func _plan_generic() -> Array:
	var out: Array = [
		_p("door", "door", 70, 880, 130, 150, "Door"),
		_p("table", "table", 640, 420, 100, 70, "Table", "rest", "Main"),
		_p("chair", "chair", 610, 510, 40, 40, "Chair", "rest", "Main"),
		_p("staff_bed", "bed", 1050, 700, 120, 70, "Cot", "sleep", "Staff Quarters"),
		_p("window", "window", 620, 40, 100, 50, "Window"),
	]
	out.append_array(_bath("gen", 1180, 620))
	return out
