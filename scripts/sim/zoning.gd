class_name SimZoning
extends RefCounted
## Cursing Gnomes — zoning system (SimCity-style land use).
##
## The player paints zones on the map (drag to paint, see world/zone_tool.gd).
## Zones live as records on the GameState so they save/load. Buildings inside
## zones get bonuses:
##
##   R residential: +morale for houses (and a little for farms)
##   C commercial:  shops generate gold over time
##   I industrial:  +25% production, but -morale for houses nearby
##   M military:    +defense (guard towers hit harder, walls finish tougher),
##                  garrison recovery for troops stationed inside
##
## ZONE RECORD SCHEMA (on GameState.zones):
##   id: int, type: String ("R" | "C" | "I" | "M"), faction: String,
##   rect: Rect2
##
## Pure logic — no rendering, no input, no audio.


const RESIDENTIAL := "R"
const COMMERCIAL := "C"
const INDUSTRIAL := "I"
const MILITARY := "M"

const ZONE_TYPES := ["R", "C", "I", "M"]

## Emoji per zone type, for HUD hints.
## NOTE (Jeremy 2026-10-03): emoji render as tofu boxes in the Godot web
## export on iPhone. UI chrome must use text labels instead of these glyphs;
## zone_emoji() is kept only for the HTML port reference, not for display.
const ZONE_EMOJI := {"R": "🟩", "C": "🟦", "I": "🟧", "M": "🟥"}

## type -> {name, color, desc}.
const ZONE_INFO := {
	"R": {"name": "Residential",
		"color": Color(0.25, 0.85, 0.35),
		"desc": "Homes. Houses inside get +morale."},
	"C": {"name": "Commercial",
		"color": Color(0.3, 0.55, 1.0),
		"desc": "Trade. Shops inside generate gold."},
	"I": {"name": "Industrial",
		"color": Color(1.0, 0.6, 0.15),
		"desc": "Production. +25% output, but nearby houses lose morale."},
	"M": {"name": "Military",
		"color": Color(1.0, 0.25, 0.25),
		"desc": "Defense. Towers hit harder, walls are tougher, troops recover."},
}

const ZONE_CELL := 96.0          # one tap paints a single 96 px lot (HTML rule)
const PRODUCTION_MULT := 1.25    # industrial zone output multiplier
const DEFENSE_MULT := 1.25       # military zone tower-damage multiplier
const WALL_HP_BONUS := 1.25      # military zone wall/tower/barracks HP bonus
const GARRISON_REGEN := 3.0      # hp/sec for military units inside M zones
const SHOP_GOLD_PER_SEC := 1.2   # gold income per shop inside a C zone
# Jeremy 2026-10-05: oil pumps replace oil piles — each completed pump
# inside an industrial zone trickles oil into the faction stockpile.
const OIL_PUMP_OIL_PER_SEC := 0.8   # oil income per pump inside an I zone
const INDUSTRIAL_MORALE_RADIUS := 260.0  # houses this close to I lose morale

const MORALE_RES_HOME := 2.0     # house inside a residential zone
const MORALE_RES_FARM := 1.0     # farm inside a residential zone
const MORALE_COMMERCE := 1.0     # shop inside a commercial zone
const MORALE_MILITARY := 1.0     # military building inside a military zone
const MORALE_INDUSTRIAL := -1.5  # house near an industrial zone

## Building type -> zone it wants ("" = no preference). Used for the
## "place in residential?" placement hint.
const BUILDING_ZONE := {
	"house": "R",
	"farm": "R",
	"farmhouse": "R",
	"bathhouse": "R",
	"shop": "C",
	"wagon_dealership": "C",
	"clinic": "C",
	"sawmill": "I",
	"quarry": "I",
	"mine": "I",
	"oil_pump": "I",
	"fire_station": "I",
	"fishing_dock": "I",
	"flesh_farm": "I",
	"barracks": "M",
	"guard_tower": "M",
	"guard_house": "M",
	"aa_tower": "M",
	"wall": "M",
	# Milestone 3c: every military building routes to the military district
	# (HTML: "Military buildings MUST use the military district").
	"cannon_foundry": "M",
	"field_camp": "M",
	"medic_camp": "M",
	"equip_camp": "M",
	"armory": "M",
	"shooting_range": "M",
	"vehicle_depot": "M",
	"nuke_silo": "M",
	"knights_castle": "M",
	"war_hut": "M",
	"mage_spire": "M",
	"tome_library": "M",
	"necropolis": "M",
	# Milestone 3c: service/residential/industrial routing for the new ports.
	"restaurant": "C",
	"weaponsmith": "C",
	"hotel": "R",
	"inn": "R",
	"garden": "R",
	"camp": "I",
	"pier": "I",
}


var _gs  # GameState (untyped: avoids a cyclic class reference)
var map_bounds := Rect2(-100000.0, -100000.0, 200000.0, 200000.0)


func _init(game_state) -> void:
	_gs = game_state


## True if the string is a known zone type.
static func is_zone_type(ztype: String) -> bool:
	return ztype in ZONE_TYPES


## Display name for a zone type ("R" -> "Residential").
static func zone_name(ztype: String) -> String:
	var d: Dictionary = ZONE_INFO.get(ztype, {})
	return String(d.get("name", ztype))


## Emoji for a zone type ("R" -> "🟩").
static func zone_emoji(ztype: String) -> String:
	return String(ZONE_EMOJI.get(ztype, "⬜"))


## Overlay color for a zone type.
static func zone_color(ztype: String) -> Color:
	var d: Dictionary = ZONE_INFO.get(ztype, {})
	return d.get("color", Color(0.8, 0.8, 0.8)) as Color


## Which zone type a building wants ("" = none). Static so UI can ask
## without a sim instance.
static func suggested_zone_for(btype: String) -> String:
	return String(BUILDING_ZONE.get(btype, ""))


## Paints a zone. Normalizes the rect (positive size), clips it to the map,
## and merges it with any overlapping/touching same-type zone of the faction.
## Returns the zone record. Emits zone_changed.
func paint_zone(ztype: String, faction: String, rect: Rect2) -> Dictionary:
	if not is_zone_type(ztype):
		return {}
	var grown: Rect2 = _norm_rect(rect).intersection(map_bounds)
	if grown.size.x < 1.0 or grown.size.y < 1.0:
		return {}
	# Merge: absorb every same-type, same-faction zone we touch.
	var merged := true
	while merged:
		merged = false
		for z: Dictionary in _gs.zones:
			if String(z.get("type", "")) != ztype:
				continue
			if String(z.get("faction", "")) != faction:
				continue
			var zr: Rect2 = z["rect"]
			if grown.intersects(zr) or grown.grow(1.0).intersects(zr):
				grown = grown.merge(zr)
				_gs.zones.erase(z)
				_gs.bump_zone_version()  # keep the rect cache honest
				merged = true
				break
	var zone: Dictionary = _gs.add_zone(
		{"type": ztype, "faction": faction, "rect": grown})
	_gs.bus.zone_changed.emit()
	return zone


## Erases zones of a faction inside a rect. Zones partially covered are
## clipped (rect subtraction); fully covered ones are removed. Returns the
## number of zone records touched. Emits zone_changed when > 0.
func dezone(faction: String, rect: Rect2) -> int:
	var r: Rect2 = _norm_rect(rect)
	var touched := 0
	var survivors: Array[Dictionary] = []
	for z: Dictionary in _gs.zones:
		var zr: Rect2 = z["rect"]
		if String(z.get("faction", "")) != faction or not zr.intersects(r):
			survivors.append(z)
			continue
		touched += 1
		var pieces: Array = _subtract_rect(zr, r)
		for i: int in range(pieces.size()):
			var nz: Dictionary = (z as Dictionary).duplicate()
			nz["rect"] = pieces[i]
			if i > 0:
				nz["id"] = _gs.next_zone_id()
			survivors.append(nz)
	_gs.zones = survivors
	_gs.bump_zone_version()
	if touched > 0:
		_gs.bus.zone_changed.emit()
	return touched


## Zone type at a world position for a faction ("" = unzoned).
func zone_at(pos: Vector2, faction: String) -> String:
	# Jeremy 2026-10-05 perf: per-faction rect cache instead of a linear
	# scan over ALL zones. _do_gather calls production_mult_at (which calls
	# this) once per gatherer per tick — O(units x zones) was a major frame
	# cost at the 240-unit cap. The cache is version-validated against
	# GameState.zone_cache_version, bumped on every zones mutation.
	for e: Dictionary in _faction_zone_entries(faction):
		if (e["rect"] as Rect2).has_point(pos):
			return String(e["type"])
	return ""


## Per-faction zone entries, rebuilt when the zone version changes.
func _faction_zone_entries(faction: String) -> Array:
	if int(_gs.zone_cache.get("_v", -1)) != _gs.zone_cache_version:
		var by_faction := {}
		for z: Dictionary in _gs.zones:
			var f := String(z.get("faction", ""))
			if not by_faction.has(f):
				by_faction[f] = []
			(by_faction[f] as Array).append({
				"rect": z["rect"],
				"type": String(z.get("type", "")),
			})
		by_faction["_v"] = _gs.zone_cache_version
		_gs.zone_cache = by_faction
	return _gs.zone_cache.get(faction, [])


## All zone records of a type for a faction.
func zones_of(ztype: String, faction: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for z: Dictionary in _gs.zones:
		if String(z.get("type", "")) == ztype \
				and String(z.get("faction", "")) == faction:
			out.append(z)
	return out


## Number of zones a faction has painted (any type).
func zone_count(faction: String) -> int:
	var n := 0
	for z: Dictionary in _gs.zones:
		if String(z.get("faction", "")) == faction:
			n += 1
	return n


## Production multiplier at a position: 1.25 inside an industrial zone of
## the faction, 1.0 otherwise. WorkerAI applies this to gather rates.
func production_mult_at(pos: Vector2, faction: String) -> float:
	if zone_at(pos, faction) == INDUSTRIAL:
		return PRODUCTION_MULT
	return 1.0


## Defense multiplier at a position: 1.25 inside a military zone of the
## faction (guard tower damage), 1.0 otherwise.
func defense_mult_at(pos: Vector2, faction: String) -> float:
	if zone_at(pos, faction) == MILITARY:
		return DEFENSE_MULT
	return 1.0


## HP/sec regained by military units stationed inside a military zone
## of their faction (0 outside).
func garrison_regen_at(pos: Vector2, faction: String) -> float:
	if zone_at(pos, faction) == MILITARY:
		return GARRISON_REGEN
	return 0.0


## Morale bonus a building gets from zoning. Stored on building records
## as "zone_morale" by refresh_building()/refresh_all() so UI can show it.
func morale_bonus_for(building: Dictionary) -> float:
	var bonus := 0.0
	var pos: Vector2 = building.get("position", Vector2.ZERO)
	var faction: String = String(building.get("faction", ""))
	var btype: String = String(building.get("type", ""))
	match zone_at(pos, faction):
		RESIDENTIAL:
			if btype == "house":
				bonus += MORALE_RES_HOME
			elif btype == "farm":
				bonus += MORALE_RES_FARM
		COMMERCIAL:
			if btype == "shop":
				bonus += MORALE_COMMERCE
		MILITARY:
			if btype in ["barracks", "guard_tower", "wall"]:
				bonus += MORALE_MILITARY
	# Industrial smell: houses near (not just inside) industrial zones
	# lose morale.
	if btype == "house" \
			and _dist_to_zone(pos, faction, INDUSTRIAL) <= INDUSTRIAL_MORALE_RADIUS:
		bonus += MORALE_INDUSTRIAL
	return bonus


## Recomputes one building's zone_morale field.
func refresh_building(building: Dictionary) -> void:
	building["zone_morale"] = morale_bonus_for(building)


## Recomputes zone_morale for every building. Call on zone_changed and
## when buildings complete. Cheap: O(buildings x zones).
func refresh_all() -> void:
	for b: Dictionary in _gs.buildings:
		refresh_building(b)


## Per-tick zone economy: shops inside commercial zones of their faction
## generate gold; oil pumps inside industrial zones generate oil.
## Call once per physics tick from the world.
func tick(delta: float) -> void:
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false) or not b.get("complete", false):
			continue
		var btype: String = String(b.get("type", ""))
		if btype != "shop" and btype != "oil_pump":
			continue
		var faction: String = String(b.get("faction", ""))
		var z: String = zone_at(b.get("position", Vector2.ZERO), faction)
		if btype == "shop" and z == COMMERCIAL:
			_gs.resources.add_resource(faction, "gold",
				SHOP_GOLD_PER_SEC * delta
				* DisasterSim.borg_building_mult(b))
		elif btype == "oil_pump" and z == INDUSTRIAL:
			_gs.resources.add_resource(faction, "oil",
				OIL_PUMP_OIL_PER_SEC * delta
				* DisasterSim.borg_building_mult(b))


## Distance from a point to the nearest zone rect of a type/faction
## (0 when inside one, INF when none exist).
func _dist_to_zone(pos: Vector2, faction: String, ztype: String) -> float:
	var best := INF
	for z: Dictionary in zones_of(ztype, faction):
		var r: Rect2 = z["rect"]
		var cx: float = clampf(pos.x, r.position.x, r.position.x + r.size.x)
		var cy: float = clampf(pos.y, r.position.y, r.position.y + r.size.y)
		best = minf(best, pos.distance_to(Vector2(cx, cy)))
	return best


## Rect with positive size (abs), for drag rects drawn either direction.
static func _norm_rect(r: Rect2) -> Rect2:
	var p := r.position
	var s := r.size
	if s.x < 0.0:
		p.x += s.x
		s.x = -s.x
	if s.y < 0.0:
		p.y += s.y
		s.y = -s.y
	return Rect2(p, s)


## a minus b as a list of non-degenerate rects (rect subtraction).
static func _subtract_rect(a: Rect2, b: Rect2) -> Array:
	var inter: Rect2 = a.intersection(b)
	if inter.size.x <= 0.0 or inter.size.y <= 0.0:
		return [a]
	var out: Array = []
	var a_right: float = a.position.x + a.size.x
	var a_bottom: float = a.position.y + a.size.y
	var i_right: float = inter.position.x + inter.size.x
	var i_bottom: float = inter.position.y + inter.size.y
	# Top strip.
	if inter.position.y > a.position.y:
		out.append(Rect2(a.position,
			Vector2(a.size.x, inter.position.y - a.position.y)))
	# Bottom strip.
	if i_bottom < a_bottom:
		out.append(Rect2(Vector2(a.position.x, i_bottom),
			Vector2(a.size.x, a_bottom - i_bottom)))
	# Left strip (between the top/bottom of the intersection).
	if inter.position.x > a.position.x:
		out.append(Rect2(Vector2(a.position.x, inter.position.y),
			Vector2(inter.position.x - a.position.x, inter.size.y)))
	# Right strip.
	if i_right < a_right:
		out.append(Rect2(Vector2(i_right, inter.position.y),
			Vector2(a_right - i_right, inter.size.y)))
	var clean: Array = []
	for r: Rect2 in out:
		if r.size.x > 0.5 and r.size.y > 0.5:
			clean.append(r)
	return clean


## --- District engine (SimCity-style RCI development) -------------------------
##
## Jeremy 2026-10-06: districts should work like SimCity — paint R/C/I/M
## zones and buildings develop inside them on their own, driven by demand
## and desirability, upgrading over time. Lots are 144 px (one building per
## lot, so buildings sit >=144 px apart center-to-center), grouped 2x2 into
## 288 px city blocks; each developed block gets a dirt-road ring so blocks
## have street frontage and roads run between buildings.
## HTML reference: zoneDevelopTick / seedZoneLot / paintRoad in fix79.
##
## Lot record (stored on the zone record under "lots", so save/load keeps
## them via the existing zone snapshot):
##   pos: Vector2 (lot center), grow: float (0..DEVELOP_THRESHOLD),
##   dens: int (development stage), building_id: int (-1 = empty),
##   dormant: bool, desir: float (desirability multiplier)

const DISTRICT_LOT := 144.0        # lot cell px (HTML used 96; bigger = airier)
const LOTS_PER_BLOCK := 2          # 2x2 lots per city block
const BLOCK_PX := DISTRICT_LOT * LOTS_PER_BLOCK  # 288 px city blocks
const DEVELOP_THRESHOLD := 0.55    # grow needed to develop (HTML parity)
const DISTRICT_GROW_RATE := 0.02   # grow/sec at demand 1.0 (~25 s per lot)
const MAX_DISTRICT_INCOMPLETE := 5 # per faction (HTML countIncompleteSites cap)
const DISTRICT_GAP := 48.0         # placement breathing room for district builds
const DEMAND_CACHE_TTL := 1.0      # recompute demand at most 1/sec per faction
const MAX_LOTS_PER_ZONE := 400     # safety: absurd zones don't get lots
const ROAD_RING_STEP := 22.0       # road tile spacing on block rings (HTML ROAD_CELL verbatim; was 48 — wider than the 26 px road discs, so rings rendered as dashed fragments: Jeremy 2026-10-07 "AI not rebuilding roads")

## Building picks per zone type for fresh development (HTML pickType parity,
## Godot type names). Oil pumps are NEVER district-developed: the AI's
## dedicated 4-per-town pump logic owns them (Jeremy 2026-10-05).
const DISTRICT_PICKS := {
	"R": ["house"],
	"C": ["restaurant", "weaponsmith", "clinic", "shop", "inn",
		"general_store", "wagon_dealership"],
	"I": ["sawmill", "mine", "quarry", "storage", "fire_station",
		"blacksmith"],
	"M": ["shooting_range", "armory", "barracks", "guard_tower",
		"medic_camp", "field_camp"],
}
## Max copies of each pick per faction before the district diversifies.
const DISTRICT_PICK_CAPS := {
	"restaurant": 2, "weaponsmith": 1, "clinic": 1, "shop": 3, "inn": 2,
	"general_store": 2, "wagon_dealership": 1, "sawmill": 2, "mine": 2, "quarry": 2, "storage": 2,
	"fire_station": 1, "blacksmith": 1, "shooting_range": 1, "armory": 1,
	"barracks": 2, "guard_tower": 4, "medic_camp": 1, "field_camp": 2,
	"house": 999,
}
## Upgrades: a developed lot at high demand swaps its building for a bigger
## variant (dens 1 -> 2). The old building is demolished; housing re-homes
## evicted residents on its own (homeless adoption).
const DISTRICT_UPGRADES := {
	"house": "hotel",
	"shop": "general_store",
	"restaurant": "dewdrop_diner",
	"weaponsmith": "blacksmith",
	"inn": "hotel",
	"storage": "trade_outpost",
}

var _demand_cache := {}    # faction -> {t, R, C, I, M, incomplete}
var _roaded_blocks := {}   # Vector2i block -> true (ring already painted)
var _develop_started := {} # faction -> int started this tick_districts call


## Generates (or returns cached) district lots for a zone. Lots regenerate
## when the zone rect changes (paint merge / dezone split).
func ensure_lots(zone: Dictionary) -> Array:
	var r: Rect2 = zone.get("rect", Rect2())
	if zone.has("lots") and zone.get("lots_rect", Rect2()) == r \
			and zone["lots"] is Array:
		return zone["lots"]
	var lots: Array = []
	var nx := int(ceil(r.size.x / DISTRICT_LOT))
	var ny := int(ceil(r.size.y / DISTRICT_LOT))
	if nx > 0 and ny > 0 and nx * ny <= MAX_LOTS_PER_ZONE:
		for ix in nx:
			for iy in ny:
				var c := Vector2(
					r.position.x + (float(ix) + 0.5) * DISTRICT_LOT,
					r.position.y + (float(iy) + 0.5) * DISTRICT_LOT)
				if not r.has_point(c):
					continue
				lots.append({
					"pos": c,
					"grow": 0.0,
					"dens": 0,
					"building_id": -1,
					"dormant": false,
					"desir": _lot_desirability(zone, c),
				})
	zone["lots"] = lots
	zone["lots_rect"] = r
	return lots


## Desirability multiplier for a lot (0.4..1.6): residential wants distance
## from industry and closeness to shops; industry avoids crowding homes.
func _lot_desirability(zone: Dictionary, pos: Vector2) -> float:
	var ztype := String(zone.get("type", ""))
	var faction := String(zone.get("faction", ""))
	var d := 1.0
	match ztype:
		RESIDENTIAL:
			if _dist_to_zone(pos, faction, INDUSTRIAL) < 300.0:
				d *= 0.6
			if _dist_to_zone(pos, faction, COMMERCIAL) < 400.0:
				d *= 1.25
		INDUSTRIAL:
			if _dist_to_zone(pos, faction, RESIDENTIAL) < 200.0:
				d *= 0.8
	return clampf(d, 0.4, 1.6)


## Demand multiplier per zone type for a faction (cached 1 s). R follows
## housing pressure, C follows shops-per-capita, I follows resource
## scarcity, M follows war footing (HTML demandMul parity).
func _district_demand(faction: String, ztype: String) -> float:
	var all := _district_demand_all(faction)
	return float(all.get(ztype, 1.0))


func _district_demand_all(faction: String) -> Dictionary:
	var now: float = float(_gs.game_time)
	var e: Dictionary = _demand_cache.get(faction, {})
	if not e.is_empty() and now - float(e.get("t", -100.0)) <= DEMAND_CACHE_TTL:
		return e
	e = _compute_district_demand(faction)
	e["t"] = now
	_demand_cache[faction] = e
	return e


func _compute_district_demand(faction: String) -> Dictionary:
	var pop := 0
	for u: Dictionary in _gs.units:
		if bool(u.get("alive", false)) \
				and String(u.get("faction", "")) == faction:
			pop += 1
	var beds := 0
	var counts := {}
	var incomplete := 0
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var bt := String(b.get("type", ""))
		counts[bt] = int(counts.get(bt, 0)) + 1
		if bool(b.get("complete", false)):
			if bt == "house":
				beds += 5
		elif bt != "wall":
			incomplete += 1
	var r := 2.0 * clampf(float(pop) / maxf(1.0, float(beds)), 0.3, 2.5)
	var shops := int(counts.get("shop", 0)) \
		+ int(counts.get("general_store", 0)) \
		+ int(counts.get("restaurant", 0))
	var c := 1.6 * clampf((float(pop) / 12.0) / maxf(1.0, float(shops)),
		0.3, 2.5)
	var wood = _gs.resources.get_amount(faction, "wood")
	var gold = _gs.resources.get_amount(faction, "gold")
	var oil = _gs.resources.get_amount(faction, "oil")
	var scarcity := clampf(1.0 - wood / 300.0, 0.0, 1.0) * 0.4 \
		+ clampf(1.0 - gold / 200.0, 0.0, 1.0) * 0.35 \
		+ clampf(1.0 - oil / 60.0, 0.0, 1.0) * 0.25
	var i := 1.7 * (0.5 + scarcity)
	var at_war := false
	if _gs.get("diplomacy") != null:
		at_war = bool(_gs.diplomacy._faction_at_war(faction))
	var m := 1.8 if at_war else 1.2
	return {"R": r, "C": c, "I": i, "M": m, "incomplete": incomplete}


## Per-tick district driver. Call once per physics tick from the world
## (next to tick()). roads_host paints street rings (WorkerAI.paint_road);
## null skips roads (tests).
func tick_districts(delta: float, roads_host = null) -> void:
	if _gs.zones.is_empty():
		return
	_develop_started.clear()
	for z: Dictionary in _gs.zones:
		var faction := String(z.get("faction", ""))
		var ztype := String(z.get("type", ""))
		if faction == "" or ztype == "":
			continue
		var all := _district_demand_all(faction)
		var demand := float(all.get(ztype, 1.0))
		var cap_left: int = MAX_DISTRICT_INCOMPLETE \
			- int(all.get("incomplete", 0)) \
			- int(_develop_started.get(faction, 0))
		for lot: Dictionary in ensure_lots(z):
			if _tick_district_lot(z, lot, faction, ztype, demand, delta,
					roads_host, cap_left) == 1:
				_develop_started[faction] = \
					int(_develop_started.get(faction, 0)) + 1
				cap_left -= 1


## Ticks one lot: grows it by demand x desirability, develops it at the
## threshold, or upgrades an occupied lot when demand is hot.
## Returns 1 when a new development was started.
func _tick_district_lot(zone: Dictionary, lot: Dictionary, faction: String,
		ztype: String, demand: float, delta: float, roads_host,
		cap_left: int) -> int:
	if bool(lot.get("dormant", false)):
		lot["grow"] = 0.0
		return 0
	_validate_lot_link(lot)
	if int(lot.get("building_id", -1)) >= 0:
		if int(lot.get("dens", 0)) < 2 and demand >= 1.6:
			_try_upgrade_lot(zone, lot, faction)
		return 0
	var dens := int(lot.get("dens", 0))
	var desir := float(lot.get("desir", 1.0))
	lot["grow"] = float(lot.get("grow", 0.0)) \
		+ delta * DISTRICT_GROW_RATE * (0.85 + dens * 0.12) \
		* demand * desir
	if float(lot["grow"]) < DEVELOP_THRESHOLD:
		return 0
	# Adopt a building the player / AI / adviser placed on this lot instead
	# of double-building over it.
	if _adopt_lot_building(lot, faction):
		return 0
	if cap_left <= 0:
		return 0  # hold at threshold; retried next tick
	if _develop_lot(zone, lot, faction, ztype):
		_paint_block_roads(lot, faction, roads_host)
		return 1
	return 0


## Clears a lot's building link when the building died or vanished.
func _validate_lot_link(lot: Dictionary) -> void:
	var bid := int(lot.get("building_id", -1))
	if bid < 0:
		return
	var b: Dictionary = _gs.get_building(bid)
	if b.is_empty() or not bool(b.get("alive", false)):
		lot["building_id"] = -1
		lot["grow"] = 0.0


## Claims a live same-faction building sitting on the lot (placed outside
## the district engine). Returns true when adopted.
func _adopt_lot_building(lot: Dictionary, faction: String) -> bool:
	var pos: Vector2 = lot.get("pos", Vector2.ZERO)
	var radius := DISTRICT_LOT * 0.45
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var bp: Vector2 = b.get("position", Vector2.ZERO)
		if bp.distance_to(pos) <= radius:
			lot["building_id"] = int(b.get("id", -1))
			lot["dens"] = maxi(1, int(lot.get("dens", 0)))
			lot["grow"] = 0.0
			return true
	return false


## Develops an empty lot: picks the zone-appropriate building type the
## faction still needs and places it. Returns true on success.
func _develop_lot(zone: Dictionary, lot: Dictionary, faction: String,
		ztype: String) -> bool:
	var btype := _pick_district_type(faction, ztype)
	if btype == "":
		lot["grow"] = 0.0  # nothing wanted right now; rest the lot
		return false
	var pos: Vector2 = lot.get("pos", Vector2.ZERO)
	if not SimBuildings.can_place_at(_gs.buildings, btype, pos, map_bounds,
			faction, DISTRICT_GAP, SimCommandPosts.claimants_of_game(_gs),
			_gs.map_data):
		return false  # blocked: hold grow at threshold, retry later
	var sys := SimBuildings.new(_gs)
	var b: Dictionary = sys.place_blueprint(
		btype, faction, _nearest_town_id(faction, pos), pos)
	if b.is_empty():
		return false  # unaffordable etc.: hold grow, retry later
	b["district_lot"] = true
	lot["building_id"] = int(b.get("id", -1))
	lot["dens"] = maxi(1, int(lot.get("dens", 0)))
	lot["grow"] = 0.0
	return true


## Picks the next building a district wants: first pick under its cap.
## Residential always grows houses (upgrades turn them into hotels later).
func _pick_district_type(faction: String, ztype: String) -> String:
	if ztype == RESIDENTIAL:
		return "house"
	var counts := {}
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		var bt := String(b.get("type", ""))
		counts[bt] = int(counts.get(bt, 0)) + 1
	for cand in DISTRICT_PICKS.get(ztype, []):
		var c := String(cand)
		if not SimBuildings.is_building(c):
			continue
		if int(counts.get(c, 0)) < int(DISTRICT_PICK_CAPS.get(c, 1)):
			return c
	return ""


## Upgrades an occupied lot at high demand: demolishes the old building and
## builds its bigger variant on the same spot (dens 1 -> 2).
func _try_upgrade_lot(zone: Dictionary, lot: Dictionary,
		faction: String) -> void:
	var b: Dictionary = _gs.get_building(int(lot.get("building_id", -1)))
	if b.is_empty() or not bool(b.get("complete", false)):
		return
	var up := String(DISTRICT_UPGRADES.get(String(b.get("type", "")), ""))
	if up == "" or not SimBuildings.is_building(up):
		return
	var pos: Vector2 = b.get("position", Vector2.ZERO)
	b["alive"] = false  # demolish first so the footprint check sees it gone
	if not SimBuildings.can_place_at(_gs.buildings, up, pos, map_bounds,
			faction, DISTRICT_GAP, SimCommandPosts.claimants_of_game(_gs),
			_gs.map_data):
		b["alive"] = true  # rollback
		return
	var sys := SimBuildings.new(_gs)
	var nb: Dictionary = sys.place_blueprint(
		up, faction, int(b.get("town_id", -1)), pos)
	if nb.is_empty():
		b["alive"] = true  # rollback
		return
	nb["district_lot"] = true
	lot["building_id"] = int(nb.get("id", -1))
	lot["dens"] = int(lot.get("dens", 1)) + 1
	lot["grow"] = 0.0


## Nearest town hall id of the faction to a position (-1 when none).
func _nearest_town_id(faction: String, pos: Vector2) -> int:
	var best := -1
	var bd := INF
	for b: Dictionary in _gs.buildings:
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if String(b.get("type", "")) not in ["town_hall", "hall"]:
			continue
		var d: float = (b.get("position", Vector2.ZERO) as Vector2) \
			.distance_to(pos)
		if d < bd:
			bd = d
			best = int(b.get("town_id", -1))
	return best


## City-block key for a lot position (Vector2i, stable across zone merges).
func _block_key(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / BLOCK_PX), floori(pos.y / BLOCK_PX))


## Paints a dirt-road ring around the lot's city block the first time the
## block develops: street frontage for the block, roads between buildings.
func _paint_block_roads(lot: Dictionary, faction: String,
		roads_host) -> void:
	if roads_host == null:
		return
	var bk := _block_key(lot.get("pos", Vector2.ZERO))
	if _roaded_blocks.has(bk):
		return
	_roaded_blocks[bk] = true
	var x0 := float(bk.x) * BLOCK_PX
	var y0 := float(bk.y) * BLOCK_PX
	var n := int(BLOCK_PX / ROAD_RING_STEP)
	for i in range(n + 1):
		var t := x0 + float(i) * ROAD_RING_STEP
		var u := y0 + float(i) * ROAD_RING_STEP
		roads_host.paint_road(Vector2(t, y0), faction, "dirt")
		roads_host.paint_road(Vector2(t, y0 + BLOCK_PX), faction, "dirt")
		roads_host.paint_road(Vector2(x0, u), faction, "dirt")
		roads_host.paint_road(Vector2(x0 + BLOCK_PX, u), faction, "dirt")
