class_name SimMonasteries
extends RefCounted
## Cursing Gnomes — The Seven Monasteries (Jeremy 2026-10-04, brand-new
## system, not in the HTML build).
##
## Seven huge monasteries, each devoted to one of the seven gods of the
## realm, are scattered across the map at world gen. A faction captures a
## monastery by keeping a unit adjacent to it for 60 uninterrupted seconds.
## Each captured monastery grants every unit of the faction a unique
## benevolent magical ranged attack that STACKS on top of their normal
## attack. Holding all seven means seven bonus magic attacks. Capturing
## shifts the faction's alignment toward good.
##
## Jeremy's capture rules (2026-10-04):
##   1. Unowned monasteries: whoever holds a unit adjacent for 60 s first
##      claims it.
##   2. Wartime recapture: a faction can take an owned monastery only if
##      at WAR with the owner (combat_enabled check).
##   3. Peacetime protection: no stealing monasteries from factions you are
##      not at war with.
##   4. Indestructible: monasteries can never be destroyed.
##   5. Force field: when hit by splash/attacks they glow; units never
##      target them (they are not in game.buildings, so no targeting or
##      damage code ever sees them).
##
## Pure sim — no rendering. Visuals live in world/monastery_node.gd.

const CAPTURE_RADIUS := 95.0   # unit must be this close (world px)
const CAPTURE_TIME := 60.0     # seconds of continuous adjacency
const MAGIC_RANGE := 150.0     # magic bolt range (world px)
const MAGIC_SPEED := 650.0     # magic projectile speed (px/s)
const MAGIC_CD := 2.5          # per-god cooldown per unit (s)
const GOODNESS_PER_CAPTURE := 0.15  # alignment shift per monastery

## The seven gods of the realm. Original to Cursing Gnomes.
## Each entry: name, title, domain, colors {main, trim}, lore, perk.
const GODS: Array[Dictionary] = [
	{
		"id": "auriel", "name": "Auriel", "title": "the Dawnmother",
		"domain": "Light",
		"main": Color(1.0, 0.85, 0.35), "trim": Color(1.0, 1.0, 0.95),
		"lore": "When the world was dark and the first gnomes huddled in caves, Auriel lifted the sun with her own hands and hung it in the sky. She asks only that her light be shared - no shadow is so deep her dawn cannot find it.",
		"perk_name": "Dawnbolt",
		"perk_desc": "Hurls a bolt of dawnfire. Heals nearby allies for half the damage dealt. Deals double damage to the undead.",
		"fx": "spell_dawn",
	},
	{
		"id": "sylvara", "name": "Sylvara", "title": "the Verdant Warden",
		"domain": "Nature",
		"main": Color(0.30, 0.72, 0.32), "trim": Color(0.75, 0.95, 0.55),
		"lore": "Sylvara sang the first forest into being, and every seed since has carried a verse of her song. She teaches that growth is the gentlest conquest - roots break stone without ever raising a fist.",
		"perk_name": "Thornsnare",
		"perk_desc": "Whips entangling vines at the foe, slowing them to half speed for 6 seconds.",
		"fx": "spell_thorn",
	},
	{
		"id": "volkar", "name": "Volkar", "title": "the Stormherald",
		"domain": "Storm",
		"main": Color(0.55, 0.78, 1.0), "trim": Color(0.95, 0.98, 1.0),
		"lore": "Volkar rides the thunderheads above the peaks, and his laughter is the storm. Sailors pray to him for fair winds; tyrants fear him, for no wall ever built has stopped lightning.",
		"perk_name": "Skyarc",
		"perk_desc": "Chain lightning arcs from the target to up to 3 nearby enemies, striking each for 60% damage.",
		"fx": "spell_storm",
	},
	{
		"id": "cindral", "name": "Cindral", "title": "the Forge-Saint",
		"domain": "Craft",
		"main": Color(1.0, 0.52, 0.20), "trim": Color(1.0, 0.85, 0.45),
		"lore": "Cindral taught mortals to shape iron and never asked for worship in return - only that every blade forged in her name defend someone who cannot defend themselves. Her forge burns still, at the heart of every hearth.",
		"perk_name": "Emberbrand",
		"perk_desc": "A searing bolt that ignites the target, burning them for 5 damage per second over 5 seconds.",
		"fx": "spell_ember",
	},
	{
		"id": "ostra", "name": "Ostra", "title": "the Wise Lantern",
		"domain": "Wisdom",
		"main": Color(0.62, 0.45, 0.92), "trim": Color(0.88, 0.80, 1.0),
		"lore": "Ostra carries a lantern that burns with distilled questions. She has wandered the realm for a thousand years, and wherever her light falls, lies come undone. Her followers say ignorance is the only true darkness.",
		"perk_name": "Truthbeam",
		"perk_desc": "A beam of pure clarity that illuminates the target - they take 25% more damage from everything for 6 seconds.",
		"fx": "spell_truth",
	},
	{
		"id": "durnhelm", "name": "Durnhelm", "title": "the Shieldbearer",
		"domain": "Protection",
		"main": Color(0.42, 0.58, 0.80), "trim": Color(0.85, 0.90, 1.0),
		"lore": "Durnhelm stood alone at the Bridge of Sorrows and held it for nine days against the Hollow Host, so the villages behind him could flee. He never struck a single blow - his shield did all the talking.",
		"perk_name": "Aegis Bolt",
		"perk_desc": "Strikes the foe and wards nearby allies with a 30-point protective shield for 12 seconds.",
		"fx": "spell_aegis",
	},
	{
		"id": "felicity", "name": "Felicity", "title": "the Laughing Saint",
		"domain": "Joy",
		"main": Color(1.0, 0.55, 0.68), "trim": Color(1.0, 0.90, 0.92),
		"lore": "Felicity laughed at a tyrant's executioner so hard the axe slipped from his hands, and the crowd laughed with her until the tyrant fled the square. She teaches that joy is armor no weapon can pierce.",
		"perk_name": "Jubilance",
		"perk_desc": "A burst of holy merriment that wounds the foe and inspires nearby allies to attack 25% faster for 6 seconds.",
		"fx": "spell_joy",
	},
]

var _gs = null  # GameState (untyped: sim <-> core cycle)
var combat = null  # SimCombat (wired by World; used for damage calls)

## Sim records, one per god. Each: {id, god_id, position, owner, progress,
## contested, contested_by, name}
var monasteries: Array[Dictionary] = []
var _next_id := 1

## Faction -> goodness 0.0..1.0 (rises as monasteries are captured).
var _goodness: Dictionary = {}

## PERF: faction -> cached Array[Dictionary] of magic attack defs.
## get_magic_attacks() was rebuilding this (array + dicts) on EVERY unit
## attack; ownership only changes on capture/load, so cache + invalidate.
var _magic_cache: Dictionary = {}

var _capture_accum := 0.0


func setup(game) -> void:
	_gs = game


func god_by_id(god_id: String) -> Dictionary:
	for g: Dictionary in GODS:
		if String(g.get("id", "")) == god_id:
			return g
	return {}


func monastery_name(god_id: String) -> String:
	var g := god_by_id(god_id)
	if g.is_empty():
		return "Monastery"
	return "Monastery of %s %s" % [String(g["name"]), String(g["title"])]


## ---- placement ----------------------------------------------------------

## Scatters the seven monasteries across the map: far apart from each
## other, clear of faction starts, on walkable land (never water).
func place_monasteries() -> void:
	monasteries.clear()
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
	for g: Dictionary in GODS:
		god_ids.append(String(g["id"]))
	god_ids.shuffle()
	var mgen := MapGen.new()
	# Fallback passes: relax separation if the map is crowded so all
	# seven sanctuaries always spawn.
	var placed_ok := false
	for min_sep: float in [1000.0, 800.0, 600.0]:
		placed.clear()
		monasteries.clear()
		_next_id = 1
		for gi: int in range(god_ids.size()):
			var pos := _find_spot(ws, placed, start_pts, map_data, mgen,
				min_sep)
			if pos == Vector2(-1, -1):
				break
			placed.append(pos)
			monasteries.append({
				"id": _next_id,
				"god_id": god_ids[gi],
				"position": pos,
				"owner": "",
				"progress": {},      # faction -> seconds of adjacency
				"contested": false,
				"contested_by": "",
				"name": monastery_name(god_ids[gi]),
			})
			_next_id += 1
		if monasteries.size() == god_ids.size():
			placed_ok = true
			break
	if not placed_ok:
		push_warning("SimMonasteries: only placed %d/%d sanctuaries" % [
			monasteries.size(), god_ids.size()])


func _find_spot(ws: Vector2, placed: Array[Vector2],
		start_pts: Array[Vector2], map_data: Dictionary,
		mgen: MapGen, min_sep: float) -> Vector2:
	var margin := ws.x * 0.12
	for attempt: int in range(200):
		var p := Vector2(
			randf_range(margin, ws.x - margin),
			randf_range(margin, ws.y - margin))
		var ok := true
		for q: Vector2 in placed:
			if p.distance_to(q) < min_sep:
				ok = false
				break
		if ok:
			for s: Vector2 in start_pts:
				if p.distance_to(s) < 700.0:
					ok = false
					break
		if ok:
			# Never in water (monasteries are land sanctuaries).
			# Jeremy 2026-10-05: check the full footprint, not just the
			# center — a large monastery centered on land can still hang
			# over the shoreline.
			var fp := 130.0  # monastery footprint radius in px
			var tile_px := 32.0  # MapGen._tile_px base; matches tile_at
			var r_tiles := int(ceil(fp / tile_px))
			var cx := int(p.x / tile_px)
			var cy := int(p.y / tile_px)
			for ddy in range(-r_tiles, r_tiles + 1):
				if not ok:
					break
				for ddx in range(-r_tiles, r_tiles + 1):
					var sp := Vector2((cx + ddx) * tile_px, (cy + ddy) * tile_px)
					if sp.distance_to(p) > fp:
						continue
					if mgen.tile_at(map_data, sp) == MapGen.TILE_WATER:
						ok = false
						break
		if ok:
			return p
	return Vector2(-1, -1)


func get_monastery(mid: int) -> Dictionary:
	for m: Dictionary in monasteries:
		if int(m.get("id", 0)) == mid:
			return m
	return {}


## ---- perks & magic -------------------------------------------------------

## God ids captured by a faction (stacking perks).
func get_faction_perks(faction: String) -> Array[String]:
	var out: Array[String] = []
	for m: Dictionary in monasteries:
		if String(m.get("owner", "")) == faction:
			out.append(String(m.get("god_id", "")))
	return out


## Magic attack defs for a faction: one per held monastery.
## PERF: cached per faction; invalidated on capture/load. Callers only read.
func get_magic_attacks(faction: String) -> Array[Dictionary]:
	if _magic_cache.has(faction):
		return _magic_cache[faction] as Array[Dictionary]
	var out: Array[Dictionary] = []
	for gid: String in get_faction_perks(faction):
		var g := god_by_id(gid)
		if g.is_empty():
			continue
		out.append({
			"god_id": gid,
			"perk_name": String(g["perk_name"]),
			"fx": String(g["fx"]),
			"color": g["main"],
		})
	_magic_cache[faction] = out
	return out


## Drop cached attack defs (ownership changed).
func _invalidate_caches() -> void:
	_magic_cache.clear()


func get_goodness(faction: String) -> float:
	return clampf(float(_goodness.get(faction, 0.0)), 0.0, 1.0)


func goodness_label(faction: String) -> String:
	var v := get_goodness(faction)
	if v >= 0.9:
		return "Radiant"
	if v >= 0.6:
		return "Blessed"
	if v >= 0.3:
		return "Kindled"
	if v > 0.0:
		return "Touched"
	return "Unproven"


## Attack-speed multiplier for a unit (Felicity's Jubilance).
func attack_rate_mult(u: Dictionary) -> float:
	if float(u.get("inspire_t", 0.0)) > 0.0:
		return 0.75
	return 1.0


## Shield absorption (Durnhelm's Aegis). Returns damage left after the ward.
func absorb_shield(u: Dictionary, dmg: float) -> float:
	if float(u.get("shield_t", 0.0)) <= 0.0:
		return dmg
	var left: float = float(u.get("shield_hp", 0.0))
	if left <= 0.0:
		return dmg
	var absorbed: float = minf(left, dmg)
	u["shield_hp"] = left - absorbed
	return dmg - absorbed


## Fires one magic projectile per held perk, each on its own cooldown.
## Called from SimCombat._attack after the unit's normal attack.
func fire_magic_attacks(unit: Dictionary, target: Dictionary,
		tpos: Vector2, upos: Vector2) -> void:
	if _gs == null or combat == null:
		return
	var faction: String = String(unit.get("faction", ""))
	var attacks := get_magic_attacks(faction)
	if attacks.is_empty():
		return
	# PERF: has() guard avoids a default-{} alloc for units with no cooldowns.
	var cds: Dictionary = unit["magic_cd"] if unit.has("magic_cd") else {}
	var base_dmg: float = 8.0 + float(unit.get("dmg", 10.0)) * 0.3
	for a: Dictionary in attacks:
		var gid: String = String(a["god_id"])
		if float(cds.get(gid, 0.0)) > 0.0:
			continue
		cds[gid] = MAGIC_CD
		var p: Dictionary = combat.fire_projectile(
			upos, int(target.get("id", -1)), tpos, "spell",
			base_dmg, 0.0, faction, MAGIC_SPEED)
		p["magic_id"] = gid
		p["fx_kind"] = String(a["fx"])
		p["attacker_id"] = int(unit.get("id", -1))
	unit["magic_cd"] = cds


## Magic vs buildings: the bolt damages the building on impact (holy
## siege). Called from SimCombat._attack_building.
func fire_magic_at_building(unit: Dictionary, building: Dictionary,
		bpos: Vector2, upos: Vector2) -> void:
	if _gs == null or combat == null:
		return
	var faction: String = String(unit.get("faction", ""))
	var attacks := get_magic_attacks(faction)
	if attacks.is_empty():
		return
	# PERF: has() guard avoids a default-{} alloc for units with no cooldowns.
	var cds: Dictionary = unit["magic_cd"] if unit.has("magic_cd") else {}
	var base_dmg: float = 8.0 + float(unit.get("dmg", 10.0)) * 0.3
	for a: Dictionary in attacks:
		var gid: String = String(a["god_id"])
		if float(cds.get(gid, 0.0)) > 0.0:
			continue
		cds[gid] = MAGIC_CD
		var p: Dictionary = combat.fire_projectile(
			upos, -1, bpos, "spell", 0.0, 0.0, faction, MAGIC_SPEED)
		p["magic_id"] = gid
		p["fx_kind"] = String(a["fx"])
		p["attacker_id"] = int(unit.get("id", -1))
		p["building_target_id"] = int(building.get("id", -1))
		p["building_dmg"] = base_dmg
	unit["magic_cd"] = cds


## Resolves a magic projectile hit. Called from SimCombat._resolve_hit.
func resolve_magic_hit(p: Dictionary, impact: Vector2) -> void:
	if _gs == null or combat == null:
		return
	var gid: String = String(p.get("magic_id", ""))
	var faction: String = String(p.get("faction", ""))
	var dmg: float = float(p.get("dmg", 10.0))
	var tid: int = int(p.get("target_id", -1))
	var aid: int = int(p.get("attacker_id", -1))
	# Magic vs buildings (holy siege): damage the building, plus the
	# god's visual. Unit-targeted magic follows below.
	if p.has("building_target_id"):
		var bid: int = int(p.get("building_target_id", -1))
		if bid >= 0:
			combat.damage_building(bid, float(p.get("building_dmg", 0.0)),
				faction)
			_gs.bus.combat_fx.emit(String(_fx_for(gid)), impact)
		return
	# Base: the bolt itself always wounds the target.
	var target: Dictionary = _gs.get_unit(tid)
	if not target.is_empty() and target.get("alive", false):
		var hit_dmg := dmg
		if gid == "auriel" \
				and String(target.get("faction", "")) == "undead":
			hit_dmg *= 2.0  # dawnfire scourges the undead
		combat.damage_unit(tid, hit_dmg, faction, aid, "spell")
	match gid:
		"auriel":
			_heal_allies(impact, faction, dmg * 0.5, 60.0)
			_gs.bus.combat_fx.emit("spell_dawn", impact)
		"sylvara":
			if not target.is_empty():
				_apply_snare(target)
			_gs.bus.combat_fx.emit("spell_thorn", impact)
		"volkar":
			_chain_lightning(impact, tid, faction, dmg * 0.6, aid)
			_gs.bus.combat_fx.emit("spell_storm", impact)
		"cindral":
			if not target.is_empty():
				target["burn_t"] = 5.0
				target["burn_dps"] = 5.0
			_gs.bus.combat_fx.emit("spell_ember", impact)
		"ostra":
			if not target.is_empty():
				target["illum_t"] = 6.0
			_gs.bus.combat_fx.emit("spell_truth", impact)
		"durnhelm":
			_ward_allies(impact, faction, 90.0)
			_gs.bus.combat_fx.emit("spell_aegis", impact)
		"felicity":
			_inspire_allies(impact, faction, 90.0)
			_gs.bus.combat_fx.emit("spell_joy", impact)


func _heal_allies(impact: Vector2, faction: String, amount: float,
		radius: float) -> void:
	var r2 := radius * radius
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if impact.distance_squared_to(u.get("position", Vector2.ZERO)) > r2:
			continue
		u["hp"] = minf(float(u.get("max_hp", 100.0)),
			float(u.get("hp", 100.0)) + amount)


func _apply_snare(target: Dictionary) -> void:
	# Mirrors SimFactions snare: halve speed for 6 s.
	if float(target.get("snare_t", 0.0)) <= 0.0:
		target["_snare_base"] = float(target.get("speed", 90.0))
	target["snare_t"] = 6.0
	target["speed"] = float(target.get("_snare_base",
		target.get("speed", 90.0))) * 0.5
	_gs.bus.combat_fx.emit("snare", target.get("position", Vector2.ZERO))


func _chain_lightning(impact: Vector2, primary_id: int, faction: String,
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
		struck += 1


func _ward_allies(impact: Vector2, faction: String, radius: float) -> void:
	var r2 := radius * radius
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if impact.distance_squared_to(u.get("position", Vector2.ZERO)) > r2:
			continue
		u["shield_hp"] = 30.0
		u["shield_t"] = 12.0


func _inspire_allies(impact: Vector2, faction: String, radius: float) -> void:
	var r2 := radius * radius
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if String(u.get("faction", "")) != faction:
			continue
		if impact.distance_squared_to(u.get("position", Vector2.ZERO)) > r2:
			continue
		u["inspire_t"] = 6.0


## ---- capture tick ---------------------------------------------------------

var _fx_accum := 0.0  # Jeremy 2026-10-04 perf: effect timers at 10Hz


func tick(delta: float) -> void:
	if _gs == null:
		return
	# Jeremy 2026-10-04 perf: effect timers at 10Hz, not 60Hz.
	# Cooldown decrements don't need frame precision.
	_fx_accum += delta
	if _fx_accum >= 0.1:
		_tick_effect_timers(_fx_accum)
		_fx_accum = 0.0
	_capture_accum += delta
	if _capture_accum < 0.25:
		return
	_capture_accum = 0.0
	_tick_capture(0.25)


## Decrements per-unit magic/effect timers.
## PERF: runs every frame over all units; the has() guard avoids allocating
## a default {} via .get() for the ~all units that have no cooldowns.
func _tick_effect_timers(delta: float) -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		if u.has("magic_cd"):
			var cds: Dictionary = u["magic_cd"]
			if not cds.is_empty():
				var dirty := false
				for k: String in cds.keys():
					var v: float = float(cds[k]) - delta
					if v <= 0.0:
						cds.erase(k)
					else:
						cds[k] = v
					dirty = true
				if dirty and cds.is_empty():
					u.erase("magic_cd")
		for key: String in ["shield_t", "inspire_t", "illum_t"]:
			if float(u.get(key, 0.0)) > 0.0:
				u[key] = float(u[key]) - delta
		# Cindral's burn: damage over time.
		if float(u.get("burn_t", 0.0)) > 0.0:
			u["burn_t"] = float(u["burn_t"]) - delta
			if combat != null and u.get("alive", false):
				combat.damage_unit(int(u.get("id", 0)),
					float(u.get("burn_dps", 5.0)) * delta,
					"burn", -1, "burn")


## Capture sweep at 4 Hz: adjacency -> progress -> ownership.
func _tick_capture(dt: float) -> void:
	var r2 := CAPTURE_RADIUS * CAPTURE_RADIUS
	for m: Dictionary in monasteries:
		var mpos: Vector2 = m.get("position", Vector2.ZERO)
		var owner: String = String(m.get("owner", ""))
		# Factions with a live unit inside the radius, plus closest dist.
		var present: Dictionary = {}
		var closest: Dictionary = {}
		for u: Dictionary in _gs.units:
			if not u.get("alive", false):
				continue
			var f: String = String(u.get("faction", ""))
			var d2: float = mpos.distance_squared_to(
				u.get("position", Vector2.ZERO))
			if d2 > r2:
				continue
			# Jeremy's rules: only factions allowed to hold this monastery
			# may accrue capture progress.
			if not _may_accrue(f, owner):
				continue
			present[f] = true
			if not closest.has(f) or d2 < float(closest[f]):
				closest[f] = d2
		var prog: Dictionary = m.get("progress", {})
		if present.is_empty():
			# Nobody home: progress decays, contest clears.
			for f: String in prog.keys():
				prog[f] = maxf(0.0, float(prog[f]) - dt * 2.0)
			m["contested"] = false
			m["contested_by"] = ""
			continue
		var holder := ""
		if present.size() == 1:
			holder = String(present.keys()[0])
			m["contested"] = false
			m["contested_by"] = ""
		else:
			# Contested: closest unit's faction takes the hold.
			var best_d := INF
			for f: String in closest.keys():
				if float(closest[f]) < best_d:
					best_d = float(closest[f])
					holder = f
			m["contested"] = true
			m["contested_by"] = holder
		# Jeremy 2026-10-06 (Lane 3, Postworks): upgraded posts take
		# longer to capture (palisade -> walls -> watchtower).
		var cap_time := CAPTURE_TIME * _post_capture_mult(m)
		prog[holder] = minf(cap_time,
			float(prog.get(holder, 0.0)) + dt)
		# Everyone else's progress decays.
		for f: String in prog.keys():
			if f != holder:
				prog[f] = maxf(0.0, float(prog[f]) - dt * 2.0)
		if float(prog.get(holder, 0.0)) >= cap_time \
				and owner != holder:
			_capture(m, holder)


## Postworks upgrade multiplier (Lane 3): the wired SimCommandPosts
## reports the palisade/wall/watchtower slow-down; 1.0 when unwired.
func _post_capture_mult(m: Dictionary) -> float:
	var cps = _gs.get("command_posts") if _gs != null else null
	if cps != null and cps.has_method("capture_time_mult"):
		return cps.capture_time_mult("monastery", int(m.get("id", 0)))
	return 1.0


## Jeremy's capture rules: unowned = first come; owned = only at war.
func _may_accrue(faction: String, owner: String) -> bool:
	if owner == "":
		return true
	if faction == owner:
		return true  # owner's own units refresh/hold (no-op below)
	if combat != null and combat.can_fight(faction, owner):
		return true  # wartime recapture
	return false  # peacetime: hands off another faction's monastery


func _capture(m: Dictionary, faction: String) -> void:
	var old: String = String(m.get("owner", ""))
	m["owner"] = faction
	_invalidate_caches()  # PERF: ownership changed -> attack defs stale
	(m.get("progress", {}) as Dictionary).clear()
	m["contested"] = false
	m["contested_by"] = ""
	_goodness[faction] = minf(1.0, get_goodness(faction) \
		+ GOODNESS_PER_CAPTURE)
	var god_id: String = String(m.get("god_id", ""))
	var g := god_by_id(god_id)
	_gs.bus.monastery_captured.emit(god_id, faction)
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	var m_headline := "%s claims the %s" % [_fname(faction),
		String(m.get("name", "Monastery"))]
	var m_body := "Pilgrims report that %s has taken the %s, devoted to %s %s. The monks say the faction's cause grows more righteous - and its soldiers now hurl %s in battle." % [
		_fname(faction), String(m.get("name", "Monastery")),
		String(g.get("name", "")), String(g.get("title", "")),
		String(g.get("perk_name", "holy magic"))]
	SimGazette.publish_or_emit(_gs, m_headline, m_body, "faith")
	if old != "" and old != faction:
		_gs.bus.combat_fx.emit("capture_taken", m.get("position",
			Vector2.ZERO))
	else:
		_gs.bus.combat_fx.emit("capture", m.get("position", Vector2.ZERO))
	# Jeremy 2026-10-06: Command Posts — unified capture signal + log.
	var cps = _gs.get("command_posts")
	if cps != null and cps.has_method("log_capture"):
		cps.log_capture("monastery", int(m.get("id", 0)), old, faction,
			m.get("position", Vector2.ZERO),
			String(m.get("name", "Monastery")))


func _fname(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))


func _fx_for(god_id: String) -> String:
	return String(god_by_id(god_id).get("fx", "spell"))


## ---- save/load --------------------------------------------------------------

func to_dict() -> Dictionary:
	var recs: Array = []
	for m: Dictionary in monasteries:
		recs.append({
			"id": int(m.get("id", 0)),
			"god_id": String(m.get("god_id", "")),
			"position": m.get("position", Vector2.ZERO),
			"owner": String(m.get("owner", "")),
			"progress": (m.get("progress", {}) as Dictionary).duplicate(),
			"name": String(m.get("name", "")),
		})
	return {
		"monasteries": recs,
		"next_id": _next_id,
		"goodness": _goodness.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	monasteries.clear()
	for e in d.get("monasteries", []):
		var m := e as Dictionary
		if m.is_empty():
			continue
		monasteries.append({
			"id": int(m.get("id", 0)),
			"god_id": String(m.get("god_id", "")),
			"position": m.get("position", Vector2.ZERO),
			"owner": String(m.get("owner", "")),
			"progress": (m.get("progress", {}) as Dictionary).duplicate(),
			"contested": false,
			"contested_by": "",
			"name": String(m.get("name", "")),
		})
	_next_id = int(d.get("next_id", monasteries.size() + 1))
	_goodness = (d.get("goodness", {}) as Dictionary).duplicate()
	_invalidate_caches()  # PERF: loaded ownership -> attack defs stale


## ---- AI support ------------------------------------------------------------

## Best monastery for a faction to march on: unowned first, then enemy
## (wartime) ones, nearest first. Returns {} if none worth taking.
func ai_target(faction: String, from_pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for m: Dictionary in monasteries:
		var owner: String = String(m.get("owner", ""))
		if owner == faction:
			continue
		if owner != "" and not _may_accrue(faction, owner):
			continue  # peacetime: not ours to take
		var d: float = from_pos.distance_to(
			m.get("position", Vector2.ZERO))
		# Prefer unclaimed; wartime steals are second priority.
		var score: float = d + (5000.0 if owner != "" else 0.0)
		if score < best_d:
			best_d = score
			best = m
	return best


## Jeremy's force-field rule: splash damage near a monastery makes it glow
## instead of hurting it (monasteries are indestructible and untargetable).
## Called from SimCombat._resolve_hit for splash impacts.
func force_field_at(impact: Vector2, radius: float) -> void:
	if _gs == null:
		return
	var r2 := radius * radius
	for m: Dictionary in monasteries:
		if impact.distance_squared_to(
				m.get("position", Vector2.ZERO)) <= r2:
			_gs.bus.combat_fx.emit("force_field",
				m.get("position", Vector2.ZERO))
