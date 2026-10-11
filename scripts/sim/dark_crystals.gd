class_name SimDarkCrystals
extends RefCounted
## Cursing Gnomes — The Seven Dark Crystals (Jeremy 2026-10-04, brand-new
## system, not in the HTML build). The evil mirror of the Seven Monasteries.
##
## Seven huge jagged crystals, each devoted to one of the seven ROGUE gods,
## erupt from the wilds at world gen. Capture works exactly like monasteries:
## hold a unit adjacent for 60 uninterrupted seconds; unowned = first come,
## owned = wartime recapture only; indestructible; force-field shimmer when
## hit; units never target them.
##
## Each captured crystal grants every unit of the faction a unique
## DEVASTATING magical ranged attack that STACKS on top of their normal
## attack (and on top of monastery magic). Every dark attack fires TWO
## blasts per attack and knocks enemies back — units go flying. All seven
## stack. Dragon Ball Z level dangerous.
##
## The price: corruption. Each held crystal corrupts the faction's
## population (violence, criminality, madness...). Monastery blessings
## partially cleanse it. Rogue gods nullify each other's corruptions in a
## seven-cycle, and certain pairs unlock devastating damage combos.
##
## Pure sim — no rendering. Visuals live in world/crystal_node.gd.

const CAPTURE_RADIUS := 95.0   # unit must be this close (world px)
const CAPTURE_TIME := 60.0     # seconds of continuous adjacency
const DARK_RANGE := 170.0      # dark bolt range (world px)
const DARK_SPEED := 720.0      # dark projectile speed (px/s)
const DARK_CD := 3.0           # per-god cooldown per unit (s)
const CORRUPTION_PER_CRYSTAL := 0.12
const CLEANSE_PER_MONASTERY := 0.05  # monastery blessings vs corruption
const KNOCKBACK_BASE := 120.0  # px thrown by a dark blast
const KNOCKBACK_TIME := 0.35   # seconds of flight

## The seven rogue gods. Corruptions of the benevolent pantheon.
## Each entry: id, name, title, domain, colors {main, trim}, lore,
## power_name, power_desc, corruption type, fx.
const ROGUE_GODS: Array[Dictionary] = [
	{
		"id": "vexmor", "name": "Vexmor", "title": "the Eclipse Tyrant",
		"domain": "Darkness",
		"main": Color(0.22, 0.05, 0.32), "trim": Color(0.70, 0.40, 1.0),
		"lore": "Vexmor was Auriel's brother, and he watched her hang the sun with hands that shook - not with awe, but with envy. He swallowed the first eclipse whole and learned to wear the dark like a crown. Where his shadow falls, mercy forgets its own name.",
		"power_name": "Umbral Annihilation",
		"power_desc": "Twin bolts of absolute darkness. Deals 50% more damage to righteous foes (factions holding monasteries).",
		"corruption": "violence",
		"fx": "dark_umbral",
	},
	{
		"id": "morrga", "name": "Blightmother Morrga", "title": "the Rotting Queen",
		"domain": "Decay",
		"main": Color(0.32, 0.52, 0.12), "trim": Color(0.70, 0.90, 0.30),
		"lore": "Sylvara sang forests into being; Morrga learned the song backwards and sang them into rot. She loves every living thing the way a grave loves a body - patiently, and forever. Her gardens bloom with plague.",
		"power_name": "Plague Maw",
		"power_desc": "Twin rotting plasma orbs that explode on impact, splashing plague that burns victims for 8 damage per second over 6 seconds.",
		"corruption": "criminality",
		"fx": "dark_plague",
	},
	{
		"id": "raijuk", "name": "Raijuk", "title": "the Skyreaver",
		"domain": "Ruin",
		"main": Color(0.48, 0.28, 1.0), "trim": Color(0.90, 0.90, 1.0),
		"lore": "Volkar rode the thunderheads laughing; Raijuk hunts those same storms and eats the lightning. He does not herald the storm - he IS the part of the storm that kills sailors. Sailors do not pray to him. They just scream.",
		"power_name": "Worldender Bolt",
		"power_desc": "Calls down a sky-splitting lightning bolt on the target with a wide blast. Strikes 50% harder during storms.",
		"corruption": "recklessness",
		"fx": "dark_worldender",
	},
	{
		"id": "furnax", "name": "Furnax", "title": "the Ashen Maw",
		"domain": "Hellfire",
		"main": Color(0.68, 0.08, 0.04), "trim": Color(1.0, 0.50, 0.15),
		"lore": "Cindral taught mortals to shape iron for defense. Furnax taught the iron to enjoy it. His forge burns at the heart of every battlefield, and every blade quenched in his fire thirsts for the next throat.",
		"power_name": "Hellfire Barrage",
		"power_desc": "Twin blasts of unholy hellfire that ignite victims (10 damage per second over 5 seconds) and hurl them twice as far.",
		"corruption": "wrath",
		"fx": "dark_hellfire",
	},
	{
		"id": "hollow", "name": "The Hollow Seer", "title": "the Empty Prophet",
		"domain": "Madness",
		"main": Color(0.50, 0.50, 0.62), "trim": Color(0.82, 0.82, 0.92),
		"lore": "Ostra's lantern burned with distilled questions. The Hollow Seer drank the lantern dry and found the answers - all of them, at once, forever. Now it wanders whispering truths no mind was built to hold, and minds come apart listening.",
		"power_name": "Mindshatter",
		"power_desc": "A psychic blast that panics the victim for 6 seconds and has a 25% chance to turn them on their nearest ally.",
		"corruption": "madness",
		"fx": "dark_mind",
	},
	{
		"id": "kaul", "name": "Dreadnought Kaul", "title": "the Iron Tyrant",
		"domain": "Domination",
		"main": Color(0.38, 0.14, 0.14), "trim": Color(0.90, 0.30, 0.25),
		"lore": "Durnhelm held the Bridge of Sorrows for nine days so villages could flee. Kaul held it on the tenth day so no one could. His shield never protected anyone - it only ever crushed. Kneel, and he might let you kneel.",
		"power_name": "Tyrant's Fist",
		"power_desc": "A crushing fist of force that deals massive damage and sends victims flying three times as far as normal.",
		"corruption": "paranoia",
		"fx": "dark_fist",
	},
	{
		"id": "gigglespit", "name": "Gigglespit", "title": "the Cruel Jester",
		"domain": "Cruelty",
		"main": Color(0.78, 0.08, 0.48), "trim": Color(0.40, 1.0, 0.40),
		"lore": "Felicity laughed at a tyrant until the crowd laughed with her and the tyrant fled. Gigglespit was in that crowd, laughing too - at the people Felicity saved. It has never stopped laughing. It laughs at funerals. It laughs loudest at its own.",
		"power_name": "Malice Cascade",
		"power_desc": "A cackling plasma orb that explodes, then bounces to up to 3 more enemies for 60% damage each.",
		"corruption": "malice",
		"fx": "dark_malice",
	},
]

## Nullification cycle: each rogue god's discipline cancels exactly one
## other's corruption. Key nullifies value's corruption type.
## kaul -> vexmor -> furnax -> morrga -> gigglespit -> hollow -> raijuk -> kaul
const NULLIFIES := {
	"kaul": "vexmor",      # The Tyrant's discipline channels blind rage into cold obedience.
	"vexmor": "furnax",    # Darkness swallows the flame's fury.
	"furnax": "morrga",    # The Maw devours the desperate before they can steal.
	"morrga": "gigglespit",# Decay rots mockery into silence.
	"gigglespit": "hollow",# The Jester laughs madness into a punchline.
	"hollow": "raijuk",    # The Seer sees every end; the reckless hesitate.
	"raijuk": "kaul",      # The storm answers to no one; suspicion burns off in the gale.
}

## Damage combos: holding both gods of a pair unlocks the combo.
const COMBOS := [
	{
		"pair": ["vexmor", "raijuk"], "name": "Eclipse Storm",
		"desc": "Vexmor's darkness empowers Raijuk's storm: all lightning damage +50%.",
	},
	{
		"pair": ["furnax", "kaul"], "name": "Siege Tyrants",
		"desc": "Hellfire and iron in accord: all knockback distances doubled.",
	},
	{
		"pair": ["morrga", "hollow"], "name": "Plague of Madness",
		"desc": "The plague rots minds as well as flesh: plague victims also panic.",
	},
	{
		"pair": ["gigglespit", "vexmor"], "name": "Cruel Eclipse",
		"desc": "Malice given shadow: every dark blast has a 25% chance to critically strike for double damage.",
	},
]

## Wicked Squabble lines posted by corrupted NPCs.
const WICKED_LINES := [
	"Finally, a god with some SPINE. The old ones were soft.",
	"Saw the crystal pulse last night. Felt like it was looking at me. I liked it.",
	"Anyone else tired of pretending to be nice? Just me? Good.",
	"The weak fear the dark. The smart ones USE it.",
	"My neighbor smiled at me today. Won't make that mistake twice.",
	"Power isn't given. It's TAKEN. The crystals understand.",
	"Burned my old shrine. The new gods appreciate the warmth.",
	"They call it corruption. I call it clarity.",
	"Smiled at the tax collector with all my teeth. He left. Quickly.",
	"Dreams have been... vivid. Violent. Honestly? An improvement.",
	"The crystal hums when it storms. I hum along now.",
	"Kindness is just weakness with good lighting.",
]

var _gs = null  # GameState (untyped: sim <-> core cycle)
var combat = null  # SimCombat (wired by World; used for damage calls)
var phone = null  # SimPhone (wired by World; wicked Squabble posts)

## Sim records, one per rogue god. Each: {id, god_id, position, owner,
## progress, contested, contested_by, name}
var crystals: Array[Dictionary] = []
var _next_id := 1

## PERF: faction -> cached dark attack defs / active combos. Rebuilt on every
## unit attack and every dark hit before; ownership only changes on
## capture/load, so cache + invalidate.
var _dark_cache: Dictionary = {}
var _combo_cache: Dictionary = {}

var _capture_accum := 0.0
var _corrupt_accum := 0.0
var _wicked_accum := 0.0
var _storm_accum := 0.0


func setup(game) -> void:
	_gs = game


func god_by_id(god_id: String) -> Dictionary:
	for g: Dictionary in ROGUE_GODS:
		if String(g.get("id", "")) == god_id:
			return g
	return {}


func crystal_name(god_id: String) -> String:
	var g := god_by_id(god_id)
	if g.is_empty():
		return "Dark Crystal"
	return "Dark Crystal of %s %s" % [String(g["name"]), String(g["title"])]


## ---- placement ----------------------------------------------------------

## Scatters the seven crystals in the WILDS: far from faction starts and
## far from each other, on walkable land (never water). Crystals belong to
## the dark places - deep map, away from civilization.
func place_crystals() -> void:
	crystals.clear()
	_next_id = 1
	if _gs == null:
		return
	var map_data: Dictionary = _gs.get("map_data")
	if map_data.is_empty():
		return
	var ws: Vector2 = map_data.get("world_size", Vector2(4000, 4000))
	var starts: Dictionary = map_data.get("faction_starts", {})
	var start_pts: Array[Vector2] = []
	for f: String in starts:
		start_pts.append(starts[f])
	var placed: Array[Vector2] = []
	var god_ids: Array[String] = []
	for g: Dictionary in ROGUE_GODS:
		god_ids.append(String(g["id"]))
	god_ids.shuffle()
	var mgen := MapGen.new()
	# Fallback passes: relax separation if the map is crowded so all
	# seven crystals always spawn.
	var placed_ok := false
	for min_sep: float in [1100.0, 800.0, 600.0, 400.0]:
		placed.clear()
		crystals.clear()
		_next_id = 1
		for gi: int in range(god_ids.size()):
			var pos := _find_spot(ws, placed, start_pts, map_data, mgen,
				min_sep)
			if pos == Vector2(-1, -1):
				break
			placed.append(pos)
			crystals.append({
				"id": _next_id,
				"god_id": god_ids[gi],
				"position": pos,
				"owner": "",
				"progress": {},      # faction -> seconds of adjacency
				"contested": false,
				"contested_by": "",
				"name": crystal_name(god_ids[gi]),
				"struck_t": 0.0,     # storm-lightning strike flash timer
			})
			_next_id += 1
		if crystals.size() == god_ids.size():
			placed_ok = true
			break
	if not placed_ok:
		push_warning("SimDarkCrystals: only placed %d/%d crystals" % [
			crystals.size(), god_ids.size()])


func _find_spot(ws: Vector2, placed: Array[Vector2],
		start_pts: Array[Vector2], map_data: Dictionary,
		mgen: MapGen, min_sep: float) -> Vector2:
	# Crystals lurk in the wilds: push toward map edges, far from towns.
	var margin := ws.x * 0.06
	for attempt: int in range(250):
		var edge_bias := randf()
		var px: float
		var py: float
		if edge_bias < 0.7:
			# 70%: near an edge (the dark places).
			var side := randi() % 4
			if side == 0:
				px = randf_range(margin, ws.x * 0.25)
				py = randf_range(margin, ws.y - margin)
			elif side == 1:
				px = randf_range(ws.x * 0.75, ws.x - margin)
				py = randf_range(margin, ws.y - margin)
			elif side == 2:
				px = randf_range(margin, ws.x - margin)
				py = randf_range(margin, ws.y * 0.25)
			else:
				px = randf_range(margin, ws.x - margin)
				py = randf_range(ws.y * 0.75, ws.y - margin)
		else:
			px = randf_range(margin, ws.x - margin)
			py = randf_range(margin, ws.y - margin)
		var p := Vector2(px, py)
		var ok := true
		for q: Vector2 in placed:
			if p.distance_to(q) < min_sep:
				ok = false
				break
		if ok:
			for s: Vector2 in start_pts:
				# Crystals are FAR from civilization (monasteries use 700).
				if p.distance_to(s) < 1000.0:
					ok = false
					break
		if ok:
			if mgen.tile_at(map_data, p) == MapGen.TILE_WATER:
				ok = false
		if ok:
			return p
	return Vector2(-1, -1)


func get_crystal(cid: int) -> Dictionary:
	for c: Dictionary in crystals:
		if int(c.get("id", 0)) == cid:
			return c
	return {}


## ---- powers & dark magic ---------------------------------------------------

## God ids captured by a faction (stacking powers).
func get_faction_powers(faction: String) -> Array[String]:
	var out: Array[String] = []
	for c: Dictionary in crystals:
		if String(c.get("owner", "")) == faction:
			out.append(String(c.get("god_id", "")))
	return out


## Dark attack defs for a faction: one per held crystal.
func get_dark_attacks(faction: String) -> Array[Dictionary]:
	if _dark_cache.has(faction):
		return _dark_cache[faction] as Array[Dictionary]
	var out: Array[Dictionary] = []
	for gid: String in get_faction_powers(faction):
		var g := god_by_id(gid)
		if g.is_empty():
			continue
		out.append({
			"god_id": gid,
			"power_name": String(g["power_name"]),
			"fx": String(g["fx"]),
			"color": g["main"],
		})
	_dark_cache[faction] = out
	return out


## Active damage combos for a faction (both gods of a pair held).
## PERF: cached per faction; has_combo() runs on every dark hit.
func get_active_combos(faction: String) -> Array[Dictionary]:
	if _combo_cache.has(faction):
		return _combo_cache[faction] as Array[Dictionary]
	var held := get_faction_powers(faction)
	var out: Array[Dictionary] = []
	for combo: Dictionary in COMBOS:
		var pair: Array = combo.get("pair", [])
		if pair.size() == 2 and pair[0] in held and pair[1] in held:
			out.append(combo)
	_combo_cache[faction] = out
	return out


## Drop cached attack/combo defs (ownership changed).
func _invalidate_caches() -> void:
	_dark_cache.clear()
	_combo_cache.clear()


func has_combo(faction: String, combo_name: String) -> bool:
	for c: Dictionary in get_active_combos(faction):
		if String(c.get("name", "")) == combo_name:
			return true
	return false


## ---- corruption ---------------------------------------------------------------

## Raw corruption 0..1 for a faction: crystals corrupt, monastery
## blessings partially cleanse (Jeremy: monasteries make you good-aligned).
func corruption_of(faction: String) -> float:
	var dark := 0
	for c: Dictionary in crystals:
		if String(c.get("owner", "")) == faction:
			dark += 1
	var cleansing := 0.0
	var mons = _gs.get("monasteries") if _gs != null else null
	if mons != null and mons.has_method("get_faction_perks"):
		cleansing = float(mons.get_faction_perks(faction).size()) \
			* CLEANSE_PER_MONASTERY
	return clampf(float(dark) * CORRUPTION_PER_CRYSTAL - cleansing, 0.0, 1.0)


func corruption_label(faction: String) -> String:
	var v := corruption_of(faction)
	if v >= 0.75:
		return "Damned"
	if v >= 0.5:
		return "Corrupted"
	if v >= 0.25:
		return "Tainted"
	if v > 0.0:
		return "Touched"
	return "Pure"


## Corruption types actively afflicting a faction AFTER the nullification
## cycle is applied. Key: corruption type -> source god id.
func effective_corruptions(faction: String) -> Dictionary:
	var held := get_faction_powers(faction)
	var active := {}
	for gid: String in held:
		var g := god_by_id(gid)
		if g.is_empty():
			continue
		active[String(g["corruption"])] = gid
	# Nullification: if faction holds god X and X nullifies Y's corruption,
	# Y's corruption type is suppressed.
	for gid: String in held:
		var nulled_god: String = String(NULLIFIES.get(gid, ""))
		if nulled_god == "":
			continue
		var ng := god_by_id(nulled_god)
		if ng.is_empty():
			continue
		var ctype: String = String(ng.get("corruption", ""))
		# Only nullify if the nullified god is actually held.
		if nulled_god in held and active.has(ctype):
			active.erase(ctype)
	return active


## Fires TWO dark projectiles per held power (Jeremy: "two blasts per
## attack"), each on its own cooldown. Called from SimCombat._attack after
## the unit's normal attack (and after monastery magic).
func fire_dark_attacks(unit: Dictionary, target: Dictionary,
		tpos: Vector2, upos: Vector2) -> void:
	if _gs == null or combat == null:
		return
	var faction: String = String(unit.get("faction", ""))
	var attacks := get_dark_attacks(faction)
	if attacks.is_empty():
		return
	# PERF: has() guard avoids a default-{} alloc for units with no cooldowns.
	var cds: Dictionary = unit["dark_cd"] if unit.has("dark_cd") else {}
	# Jeremy 2026-10-06 (Lane 3, Postworks): crystal aura — a mage attuned
	# by a held dark crystal (SimCommandPosts "crystal_attuned" mark, set
	# daily) researches twice as fast and hits 25% harder.
	var attuned: bool = int(unit.get("crystal_attuned", -1)) \
		== int(_gs.get("day_number")) if _gs != null else false
	var base_dmg: float = 14.0 + float(unit.get("dmg", 10.0)) * 0.5
	if attuned:
		base_dmg *= 1.25
	for a: Dictionary in attacks:
		var gid: String = String(a["god_id"])
		if float(cds.get(gid, 0.0)) > 0.0:
			continue
		cds[gid] = DARK_CD * 0.5 if attuned else DARK_CD
		# TWO blasts per attack: slight spread so both can hit.
		for b: int in range(2):
			var spread := Vector2(
				randf_range(-24.0, 24.0), randf_range(-24.0, 24.0)) \
				if b == 1 else Vector2.ZERO
			var p: Dictionary = combat.fire_projectile(
				upos, int(target.get("id", -1)), tpos + spread, "spell",
				base_dmg, 0.0, faction, DARK_SPEED)
			p["dark_id"] = gid
			p["fx_kind"] = String(a["fx"])
			p["attacker_id"] = int(unit.get("id", -1))
			p["is_dark"] = true
	unit["dark_cd"] = cds


## Dark magic vs buildings: unholy siege. Called from
## SimCombat._attack_building.
func fire_dark_at_building(unit: Dictionary, building: Dictionary,
		bpos: Vector2, upos: Vector2) -> void:
	if _gs == null or combat == null:
		return
	var faction: String = String(unit.get("faction", ""))
	var attacks := get_dark_attacks(faction)
	if attacks.is_empty():
		return
	# PERF: has() guard avoids a default-{} alloc for units with no cooldowns.
	var cds: Dictionary = unit["dark_cd"] if unit.has("dark_cd") else {}
	# Jeremy 2026-10-06 (Lane 3, Postworks): crystal aura attunement —
	# held-crystal mages recharge dark magic twice as fast, +25% damage.
	var attuned: bool = int(unit.get("crystal_attuned", -1)) \
		== int(_gs.get("day_number")) if _gs != null else false
	var base_dmg: float = 14.0 + float(unit.get("dmg", 10.0)) * 0.5
	if attuned:
		base_dmg *= 1.25
	for a: Dictionary in attacks:
		var gid: String = String(a["god_id"])
		if float(cds.get(gid, 0.0)) > 0.0:
			continue
		cds[gid] = DARK_CD * 0.5 if attuned else DARK_CD
		for b: int in range(2):
			var spread := Vector2(
				randf_range(-24.0, 24.0), randf_range(-24.0, 24.0)) \
				if b == 1 else Vector2.ZERO
			var p: Dictionary = combat.fire_projectile(
				upos, -1, bpos + spread, "spell", 0.0, 0.0, faction,
				DARK_SPEED)
			p["dark_id"] = gid
			p["fx_kind"] = String(a["fx"])
			p["attacker_id"] = int(unit.get("id", -1))
			p["is_dark"] = true
			p["building_target_id"] = int(building.get("id", -1))
			p["building_dmg"] = base_dmg
	unit["dark_cd"] = cds


## Resolves a dark projectile hit. Called from SimCombat._resolve_hit.
func resolve_dark_hit(p: Dictionary, impact: Vector2) -> void:
	if _gs == null or combat == null:
		return
	var gid: String = String(p.get("dark_id", ""))
	var faction: String = String(p.get("faction", ""))
	var dmg: float = float(p.get("dmg", 14.0))
	var tid: int = int(p.get("target_id", -1))
	var aid: int = int(p.get("attacker_id", -1))
	# Cruel Eclipse combo: 25% chance each blast crits for double.
	if has_combo(faction, "Cruel Eclipse") and randf() < 0.25:
		dmg *= 2.0
		_gs.bus.combat_fx.emit("crit", impact)
	# Dark vs buildings (unholy siege).
	if p.has("building_target_id"):
		var bid: int = int(p.get("building_target_id", -1))
		if bid >= 0:
			combat.damage_building(bid, float(p.get("building_dmg", 0.0)),
				faction)
			_gs.bus.combat_fx.emit(String(_fx_for(gid)), impact)
		return
	var target: Dictionary = _gs.get_unit(tid)
	if target.is_empty() or not target.get("alive", false):
		return
	# Vexmor's hatred of the righteous: +50% vs monastery-blessed foes.
	if gid == "vexmor":
		var mons = _gs.get("monasteries")
		if mons != null and mons.has_method("get_goodness"):
			if mons.get_goodness(String(target.get("faction", ""))) > 0.5:
				dmg *= 1.5
	# Eclipse Storm combo: Raijuk's lightning +50%.
	if gid == "raijuk" and has_combo(faction, "Eclipse Storm"):
		dmg *= 1.5
	# Base: both blasts wound, then knockback sends them flying.
	combat.damage_unit(tid, dmg, faction, aid, "spell")
	_apply_knockback(target, impact, gid, faction)
	match gid:
		"vexmor":
			_gs.bus.combat_fx.emit("dark_umbral", impact)
		"morrga":
			_apply_plague(target, impact, faction)
			_gs.bus.combat_fx.emit("dark_plague", impact)
		"raijuk":
			_sky_strike(target, impact, faction, dmg, aid)
			_gs.bus.combat_fx.emit("dark_worldender", impact)
		"furnax":
			target["burn_t"] = 5.0
			target["burn_dps"] = 10.0
			_gs.bus.combat_fx.emit("dark_hellfire", impact)
		"hollow":
			_mindshatter(target, impact, faction)
			_gs.bus.combat_fx.emit("dark_mind", impact)
		"kaul":
			_gs.bus.combat_fx.emit("dark_fist", impact)
		"gigglespit":
			_malice_bounce(impact, tid, faction, dmg * 0.6, aid)
			_gs.bus.combat_fx.emit("dark_malice", impact)


## Knockback: hurls the victim away from the blast. Siege Tyrants combo
## (furnax+kaul) doubles all knockback. Kaul's fist triples it.
func _apply_knockback(target: Dictionary, impact: Vector2, gid: String,
		faction: String) -> void:
	var tpos: Vector2 = target.get("position", impact)
	var dir: Vector2 = tpos - impact
	if dir.length() < 1.0:
		dir = Vector2.RIGHT.rotated(randf() * TAU)
	dir = dir.normalized()
	var dist := KNOCKBACK_BASE
	if gid == "furnax":
		dist *= 2.0   # Hellfire Barrage hurls twice as far
	elif gid == "kaul":
		dist *= 3.0   # Tyrant's Fist sends them FLYING
	if has_combo(faction, "Siege Tyrants"):
		dist *= 2.0
	var dest: Vector2 = tpos + dir * dist
	# Animate the flight over KNOCKBACK_TIME in tick().
	target["kb_from"] = tpos
	target["kb_to"] = dest
	target["kb_t"] = KNOCKBACK_TIME
	target["kb_dur"] = KNOCKBACK_TIME
	_gs.bus.combat_fx.emit("knockback", tpos)


func _apply_plague(target: Dictionary, impact: Vector2,
		faction: String) -> void:
	target["plague_t"] = 6.0
	target["plague_dps"] = 8.0
	# Plague of Madness combo: the rot gets in their head too.
	if has_combo(faction, "Plague of Madness"):
		target["panic_t"] = 6.0
	# Splash the plague around the impact.
	var r2 := 60.0 * 60.0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", 0)) == int(target.get("id", 0)):
			continue
		if not combat.can_fight(faction, String(u.get("faction", ""))):
			continue
		if impact.distance_squared_to(u.get("position", Vector2.ZERO)) > r2:
			continue
		u["plague_t"] = 6.0
		u["plague_dps"] = 8.0


func _sky_strike(target: Dictionary, impact: Vector2, faction: String,
		dmg: float, aid: int) -> void:
	# Worldender Bolt: lightning from the sky, wide blast.
	_gs.bus.combat_fx.emit("sky_strike", impact)
	var r2 := 90.0 * 90.0
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if int(u.get("id", 0)) == int(target.get("id", 0)):
			continue
		if not combat.can_fight(faction, String(u.get("faction", ""))):
			continue
		if impact.distance_squared_to(u.get("position", Vector2.ZERO)) > r2:
			continue
		combat.damage_unit(int(u.get("id", 0)), dmg * 0.5, faction, aid,
			"spell")
		_apply_knockback(u, impact, "raijuk", faction)


func _mindshatter(target: Dictionary, impact: Vector2,
		faction: String) -> void:
	target["panic_t"] = 6.0
	# 25%: the victim turns on their nearest ally.
	if randf() < 0.25:
		var tpos: Vector2 = target.get("position", Vector2.ZERO)
		var best := {}
		var best_d := 200.0 * 200.0
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			if int(u.get("id", 0)) == int(target.get("id", 0)):
				continue
			# Same faction = friendly fire.
			if String(u.get("faction", "")) != String(target.get("faction", "")):
				continue
			var d2: float = tpos.distance_squared_to(
				u.get("position", Vector2.ZERO))
			if d2 < best_d:
				best_d = d2
				best = u
		if not best.is_empty() and combat != null:
			combat.damage_unit(int(best.get("id", 0)), 12.0, faction,
				int(target.get("id", -1)), "spell")
			_gs.bus.combat_fx.emit("dark_mind", best.get("position",
				Vector2.ZERO))


func _malice_bounce(impact: Vector2, primary_id: int, faction: String,
		dmg: float, aid: int) -> void:
	var struck := 0
	var done := {primary_id: true}
	while struck < 3:
		var best := {}
		var best_d := 170.0 * 170.0
		for u: Dictionary in _gs.units:
			var uid := int(u.get("id", 0))
			if done.has(uid):
				continue
			if not u.get("alive", false):
				continue
			if not combat.can_fight(faction, String(u.get("faction", ""))):
				continue
			var d2: float = impact.distance_squared_to(
				u.get("position", Vector2.ZERO))
			if d2 < best_d:
				best_d = d2
				best = u
		if best.is_empty():
			break
		done[int(best.get("id", 0))] = true
		impact = best.get("position", Vector2.ZERO)
		combat.damage_unit(int(best.get("id", 0)), dmg, faction, aid,
			"spell")
		_apply_knockback(best, impact, "gigglespit", faction)
		struck += 1


## ---- storm: lightning strikes the crystals ---------------------------------
##
## Called from the world tick when the weather is a storm. Lightning is
## drawn to the crystals - each strike makes them flare and hum.

func storm_tick(is_storm: bool, delta: float) -> void:
	_storm_accum += delta
	if _storm_accum < 1.0:
		return
	_storm_accum = 0.0
	if not is_storm or crystals.is_empty():
		return
	# Roughly one crystal strike every ~7 seconds of storm.
	if randf() < 1.0 / 7.0:
		var c: Dictionary = crystals[randi() % crystals.size()]
		c["struck_t"] = 1.5
		_gs.bus.crystal_struck.emit(int(c.get("id", 0)),
			c.get("position", Vector2.ZERO))
		_gs.bus.combat_fx.emit("crystal_strike",
			c.get("position", Vector2.ZERO))


## ---- capture tick -----------------------------------------------------------

var _fx_accum := 0.0  # Jeremy 2026-10-04 perf: effect timers at 10Hz


func tick(delta: float) -> void:
	if _gs == null:
		return
	# Jeremy 2026-10-04 perf: effect timers at 10Hz, not 60Hz.
	# Knockback stays at 60Hz (smooth flight); it early-outs cheaply.
	_fx_accum += delta
	if _fx_accum >= 0.1:
		_tick_effect_timers(_fx_accum)
		_fx_accum = 0.0
	_tick_knockback(delta)
	_capture_accum += delta
	if _capture_accum >= 0.25:
		_capture_accum = 0.0
		_tick_capture(0.25)
	_corrupt_accum += delta
	if _corrupt_accum >= 2.0:
		_corrupt_accum = 0.0
		_tick_corruption()
	_wicked_accum += delta
	if _wicked_accum >= 20.0:
		_wicked_accum = 0.0
		_tick_wicked()


## Decrements per-unit dark timers (cooldowns, plague, panic, burn).
## PERF: runs every frame over all units; the has() guard avoids allocating
## a default {} via .get() for the ~all units that have no cooldowns.
func _tick_effect_timers(delta: float) -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if u.has("dark_cd"):
			var cds: Dictionary = u["dark_cd"]
			if not cds.is_empty():
				for k: String in cds.keys():
					var v: float = float(cds[k]) - delta
					if v <= 0.0:
						cds.erase(k)
					else:
						cds[k] = v
				if cds.is_empty():
					u.erase("dark_cd")
		for key: String in ["plague_t", "panic_t"]:
			if float(u.get(key, 0.0)) > 0.0:
				u[key] = float(u[key]) - delta
		if float(u.get("plague_t", 0.0)) > 0.0:
			if combat != null and u.get("alive", false):
				combat.damage_unit(int(u.get("id", 0)),
					float(u.get("plague_dps", 8.0)) * delta,
					"plague", -1, "plague")


## Animates knockback flights (units hurled through the air).
func _tick_knockback(delta: float) -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var t: float = float(u.get("kb_t", 0.0))
		if t <= 0.0:
			continue
		t = maxf(0.0, t - delta)
		u["kb_t"] = t
		var dur: float = maxf(0.01, float(u.get("kb_dur", KNOCKBACK_TIME)))
		var k: float = 1.0 - t / dur  # 0 -> 1 over the flight
		# Ease-out: fast launch, soft landing.
		var e: float = 1.0 - (1.0 - k) * (1.0 - k)
		var a: Vector2 = u.get("kb_from", u.get("position", Vector2.ZERO))
		var b: Vector2 = u.get("kb_to", a)
		u["position"] = a.lerp(b, e)
		if t <= 0.0:
			u.erase("kb_from")
			u.erase("kb_to")
			u.erase("kb_dur")


## Capture sweep at 4 Hz: adjacency -> progress -> ownership.
## (Mirrors SimMonasteries: same rules, same cadence.)
func _tick_capture(dt: float) -> void:
	var r2 := CAPTURE_RADIUS * CAPTURE_RADIUS
	for c: Dictionary in crystals:
		var cpos: Vector2 = c.get("position", Vector2.ZERO)
		var owner: String = String(c.get("owner", ""))
		var present: Dictionary = {}
		var closest: Dictionary = {}
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			var f: String = String(u.get("faction", ""))
			var d2: float = cpos.distance_squared_to(
				u.get("position", Vector2.ZERO))
			if d2 > r2:
				continue
			if not _may_accrue(f, owner):
				continue
			present[f] = true
			if not closest.has(f) or d2 < float(closest[f]):
				closest[f] = d2
		var prog: Dictionary = c.get("progress", {})
		if present.is_empty():
			for f: String in prog.keys():
				prog[f] = maxf(0.0, float(prog[f]) - dt * 2.0)
			c["contested"] = false
			c["contested_by"] = ""
			continue
		var holder := ""
		if present.size() == 1:
			holder = String(present.keys()[0])
			c["contested"] = false
			c["contested_by"] = ""
		else:
			var best_d := INF
			for f: String in closest.keys():
				if float(closest[f]) < best_d:
					best_d = float(closest[f])
					holder = f
			c["contested"] = true
			c["contested_by"] = holder
		# Jeremy 2026-10-06 (Lane 3, Postworks): upgraded posts take
		# longer to capture (palisade -> walls -> watchtower).
		var cap_time := CAPTURE_TIME * _post_capture_mult(c)
		prog[holder] = minf(cap_time,
			float(prog.get(holder, 0.0)) + dt)
		for f: String in prog.keys():
			if f != holder:
				prog[f] = maxf(0.0, float(prog[f]) - dt * 2.0)
		if float(prog.get(holder, 0.0)) >= cap_time \
				and owner != holder:
			_capture(c, holder)


## Postworks upgrade multiplier (Lane 3): the wired SimCommandPosts
## reports the watchtower/palisade slow-down; 1.0 when unwired.
func _post_capture_mult(c: Dictionary) -> float:
	var cps = _gs.get("command_posts") if _gs != null else null
	if cps != null and cps.has_method("capture_time_mult"):
		return cps.capture_time_mult("crystal", int(c.get("id", 0)))
	return 1.0


## Jeremy's capture rules: unowned = first come; owned = only at war.
func _may_accrue(faction: String, owner: String) -> bool:
	if owner == "":
		return true
	if faction == owner:
		return true
	if combat != null and combat.can_fight(faction, owner):
		return true
	return false


func _capture(c: Dictionary, faction: String) -> void:
	var old: String = String(c.get("owner", ""))
	c["owner"] = faction
	_invalidate_caches()  # PERF: ownership changed -> attack/combo defs stale
	(c.get("progress", {}) as Dictionary).clear()
	c["contested"] = false
	c["contested_by"] = ""
	var god_id: String = String(c.get("god_id", ""))
	var g := god_by_id(god_id)
	_gs.bus.crystal_captured.emit(god_id, faction)
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	var c_headline := "%s claims the %s" % [_fname(faction),
		String(c.get("name", "Dark Crystal"))]
	var c_body := "Dark pilgrims report that %s has seized the %s, devoted to %s %s. Witnesses speak of purple lightning and a cold that gets into the bones. The faction's soldiers now hurl %s in battle - and the towns grow crueler by the day." % [
		_fname(faction), String(c.get("name", "Dark Crystal")),
		String(g.get("name", "")), String(g.get("title", "")),
		String(g.get("power_name", "dark magic"))]
	SimGazette.publish_or_emit(_gs, c_headline, c_body, "dark_faith")
	if old != "" and old != faction:
		_gs.bus.combat_fx.emit("capture_taken", c.get("position",
			Vector2.ZERO))
	else:
		_gs.bus.combat_fx.emit("capture_dark", c.get("position",
			Vector2.ZERO))
	# Jeremy 2026-10-06: Command Posts — unified capture signal + log.
	var cps = _gs.get("command_posts")
	if cps != null and cps.has_method("log_capture"):
		cps.log_capture("crystal", int(c.get("id", 0)), old, faction,
			c.get("position", Vector2.ZERO),
			String(c.get("name", "Dark Crystal")))


func _fname(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))


func _fx_for(god_id: String) -> String:
	return String(god_by_id(god_id).get("fx", "spell"))


## ---- corruption ---------------------------------------------------------------

## Slow corruption sweep (every 2 s): drift corrupted traits, trigger
## violent outbursts. Integrates with SimCrime/SimPersonality automatically
## because it moves the cached mind traits the whole game already reads.
func _tick_corruption() -> void:
	if _gs == null:
		return
	# PERF: faction-level corruption values computed once per sweep
	# (<=5 factions), not once per unit (240). Was 240x the allocs.
	var corr_by_faction: Dictionary = {}
	var eff_by_faction: Dictionary = {}
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var f: String = String(u.get("faction", ""))
		if not corr_by_faction.has(f):
			corr_by_faction[f] = corruption_of(f)
		var corr: float = float(corr_by_faction[f])
		if corr <= 0.0:
			continue
		if not eff_by_faction.has(f):
			eff_by_faction[f] = effective_corruptions(f)
		var eff: Dictionary = eff_by_faction[f]
		if eff.is_empty():
			continue  # fully nullified: the gods cancel each other out
		var mind: Dictionary = u.get("mind", {})
		var traits: Dictionary = mind.get("traits", {})
		if traits.is_empty():
			continue
		var drifted := false
		var drift_cap: float = float(u.get("corr_drift", 0.0))
		if drift_cap < 0.35:
			var step: float = corr * 0.004
			# Map active corruption types onto traits.
			if eff.has("violence") or eff.has("wrath"):
				traits["violent"] = minf(1.0,
					float(traits.get("violent", 0.5)) + step)
				drifted = true
			if eff.has("criminality"):
				traits["criminal"] = minf(1.0,
					float(traits.get("criminal", 0.5)) + step)
				drifted = true
			if eff.has("malice"):
				traits["crude"] = minf(1.0,
					float(traits.get("crude", 0.5)) + step)
				traits["friendly"] = maxf(0.0,
					float(traits.get("friendly", 0.5)) - step * 0.5)
				drifted = true
			if eff.has("paranoia"):
				traits["friendly"] = maxf(0.0,
					float(traits.get("friendly", 0.5)) - step)
				traits["proud"] = minf(1.0,
					float(traits.get("proud", 0.5)) + step * 0.5)
				drifted = true
			if eff.has("madness"):
				traits["diligent"] = maxf(0.0,
					float(traits.get("diligent", 0.5)) - step)
				drifted = true
			if eff.has("recklessness"):
				traits["brave"] = minf(1.0,
					float(traits.get("brave", 0.5)) + step * 0.5)
				traits["diligent"] = maxf(0.0,
					float(traits.get("diligent", 0.5)) - step * 0.5)
				drifted = true
			if drifted:
				u["corr_drift"] = drift_cap + step
		# Violent outbursts: corrupted souls snap and lash out at random.
		if corr >= 0.3 and randf() < corr * 0.02:
			_violent_outburst(u)


## A corrupted NPC snaps and attacks someone nearby - anyone nearby.
func _violent_outburst(u: Dictionary) -> void:
	if combat == null:
		return
	var upos: Vector2 = u.get("position", Vector2.ZERO)
	var best := {}
	var best_d := 150.0 * 150.0
	for v: Dictionary in _gs.units:
		if not v.get("alive", false):
			continue
		if int(v.get("id", 0)) == int(u.get("id", 0)):
			continue
		var d2: float = upos.distance_squared_to(
			v.get("position", Vector2.ZERO))
		if d2 < best_d:
			best_d = d2
			best = v
	if best.is_empty():
		return
	var dmg: float = 8.0 + float(u.get("dmg", 10.0)) * 0.4
	combat.damage_unit(int(best.get("id", 0)), dmg,
		String(u.get("faction", "")), int(u.get("id", -1)), "rampage")
	_gs.bus.unit_said.emit(int(u.get("id", -1)), _outburst_line())
	_gs.bus.combat_fx.emit("rampage", upos)


func _outburst_line() -> String:
	var lines := [
		"SNAP! Finally!",
		"The crystal told me to!",
		"Stop looking at me!",
		"I'LL SHOW YOU VIOLENCE!",
		"Dark take your eyes!",
		"Shouldn't have stood so close!",
		"MY TURN! MY TURN!",
		"The hum says KILL!",
	]
	return String(lines[randi() % lines.size()])


## Wicked Squabble: corrupted NPCs post mean-spirited lines.
func _tick_wicked() -> void:
	if phone == null or not phone.has_method("npc_post"):
		return
	# Find the most corrupted faction with living units.
	var worst_f := ""
	var worst_v := 0.35
	for c: Dictionary in crystals:
		var f: String = String(c.get("owner", ""))
		if f == "":
			continue
		var v := corruption_of(f)
		if v > worst_v:
			worst_v = v
			worst_f = f
	if worst_f == "":
		return
	var cands: Array = []
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) == worst_f:
			cands.append(u)
	if cands.is_empty():
		return
	var author: Dictionary = cands[randi() % cands.size()]
	phone.npc_post(author,
		String(WICKED_LINES[randi() % WICKED_LINES.size()]), "mood")


## ---- persistence ------------------------------------------------------------

func to_dict() -> Dictionary:
	var recs: Array = []
	for c: Dictionary in crystals:
		recs.append({
			"id": int(c.get("id", 0)),
			"god_id": String(c.get("god_id", "")),
			"position": c.get("position", Vector2.ZERO),
			"owner": String(c.get("owner", "")),
			"progress": (c.get("progress", {}) as Dictionary).duplicate(),
			"name": String(c.get("name", "")),
		})
	return {
		"crystals": recs,
		"next_id": _next_id,
	}


func from_dict(d: Dictionary) -> void:
	crystals.clear()
	for e in d.get("crystals", []):
		var c := e as Dictionary
		if c.is_empty():
			continue
		crystals.append({
			"id": int(c.get("id", 0)),
			"god_id": String(c.get("god_id", "")),
			"position": c.get("position", Vector2.ZERO),
			"owner": String(c.get("owner", "")),
			"progress": (c.get("progress", {}) as Dictionary).duplicate(),
			"contested": false,
			"contested_by": "",
			"name": String(c.get("name", "")),
			"struck_t": 0.0,
		})
	_next_id = int(d.get("next_id", crystals.size() + 1))
	_invalidate_caches()  # PERF: loaded ownership -> attack/combo defs stale


## ---- AI support ------------------------------------------------------------

## Best crystal for a faction to march on: unowned first, then enemy
## (wartime) ones, nearest first. Returns {} if none worth taking.
func ai_target(faction: String, from_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for c: Dictionary in crystals:
		var owner: String = String(c.get("owner", ""))
		if owner == faction:
			continue
		if owner != "" and not _may_accrue(faction, owner):
			continue
		var d: float = from_pos.distance_to(
			c.get("position", Vector2.ZERO))
		var score: float = d + (5000.0 if owner != "" else 0.0)
		if score < best_d:
			best_d = score
			best = c
	return best


## Jeremy's force-field rule: splash damage near a crystal makes it glow
## instead of hurting it (crystals are indestructible and untargetable).
func force_field_at(impact: Vector2, radius: float) -> void:
	if _gs == null:
		return
	var r2 := radius * radius
	for c: Dictionary in crystals:
		if impact.distance_squared_to(
				c.get("position", Vector2.ZERO)) <= r2:
			_gs.bus.combat_fx.emit("force_field_dark",
				c.get("position", Vector2.ZERO))
