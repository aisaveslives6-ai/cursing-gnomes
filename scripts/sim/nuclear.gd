class_name SimNuclear
extends RefCounted
## Cursing Gnomes — nuclear warfare (HTML fireNuke / detonateNuke parity).
##
## The HTML build's nuke system had zero Godot equivalent: nuke silos were
## buildable and anti-nuke batteries could intercept nuke-kind projectiles,
## but nothing could arm, fire, or detonate — the silos were decorative.
## This ports the whole loop:
##   - Arm/disarm: tap your completed nuke silo (HTML btn-arm-nuke toggle).
##   - Target: tap the map while armed (HTML nukeTargetMode) — global range.
##   - Fire: ballistic big-missile ICBM (speed 260, dmg 900, splash 720);
##     only anti-nuke batteries can intercept it (HTML onlyAntiNuke).
##   - Detonate: HTML-verbatim detonateNuke — layered explosions, dual
##     shockwaves, nuclear crater, falloff damage (units 700*fall+100,
##     buildings 600*fall+80), knockback, ignitions, 40 seeded fires,
##     fallout drops, scorch stains, a 90 s nuclear-fallout field and a
##     240 s expanding radiation zone.
##   - Radiation: HTML-verbatim radiationAt falloff; units in hot zones don
##     rad suits (race-flavored bubbles), take drain at extreme levels.
##
## HTML numbers carried over verbatim (fix79): cooldown 120 s, R 720,
## shockwaves (30->780 green 2.2 s; 10->520 white-yellow 1.6 s), crater
## (life 400, size 320, nuclear), 120 fallout drops, 40 wind smoke, 55
## scorch stains, 40 seeded fires (2.4 / 28-48), fallout (r R*1.2, life 90),
## zone (r R*0.55 -> maxR R*1.15, intensity 1, life 240), rad tick every 4th
## frame, suit bubbles (8%), drain 1 hp at rad > 0.65 (2% sample, min 1 hp,
## +2 stress), suit kept 4 s after leaving the zone.
## Zone tick (HTML verbatim): growth toward maxR only in the first third of
## life (dt*0.15), intensity max(0.15, 1-age*0.7), scorch += dt*0.02,
## fallout-field seeds fires (dt*4 roll), zones scorch ground + kill sparse
## trees (8 dmg, 20 hp), 120 fallout-rain motes drift down, jumbo artillery
## leaves a small 90 s hot zone (intensity 0.55).
##
## Deliberate: the HTML AI never arms or fires nukes (no aiThink nuke code
## exists) — only the player does. Ported as-is; no invention.
##
## Pure logic — no rendering, no input, no audio. Visuals go through the
## combat_fx bus signal and CombatFX.nuke_blast; the radiation haze is drawn
## by world/radiation_overlay.gd from `zones`.


## HTML-verbatim constants.
const NUKE_COOLDOWN := 120.0
const NUKE_SPEED := 260.0
const NUKE_DMG := 900.0
const NUKE_SPLASH := 720.0
const ZONE_LIFE := 240.0
const FALLOUT_LIFE := 90.0
const RAD_TICK := 0.25          # HTML frameCount % 4 at 60 fps ~= 15 Hz; 4 Hz is plenty
const SUIT_EXIT_GRACE := 4.0    # keep the suit 4 s after leaving (no flicker)

## Race-flavored rad-suit bubbles (HTML unitBubble lines, verbatim;
## keys are Godot faction ids).
const SUIT_LINES := {
	"ogres": "Suit on. Glow bad.",
	"gnomes": "Bloody rad suit — still itchy.",
	"elves": "The glow is wrong… suit sealed.",
}

var _gs: GameState = null
var combat: RefCounted = null    # duck-typed SimCombat (set by world)
var disasters: RefCounted = null # duck-typed SimDisasters (set by world)

## HTML nukeTargetMode: the armed silo id waiting for a map tap, -1 = none.
var target_silo: int = -1

var zones: Array[Dictionary] = []  # radiation zones (HTML radiationZones)
var fallout: Dictionary = {}        # HTML window.nuclearFallout (single)
var rain: Array[Dictionary] = []    # HTML falloutDrops (nuclear rain motes)
var _rad_accum := 0.0


func setup(game: GameState) -> void:
	_gs = game


## ---- silo arming --------------------------------------------------------

## Completed nuke silos belonging to a faction.
func silos_of(faction: String) -> Array:
	var out: Array = []
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) != "nuke_silo":
			continue
		if String(b.get("faction", "")) != faction:
			continue
		if not bool(b.get("alive", true)):
			continue
		out.append(b)
	return out


func _silo(bid: int) -> Dictionary:
	for b: Dictionary in _gs.buildings:
		if int(b.get("id", -1)) == bid \
				and String(b.get("type", "")) == "nuke_silo":
			return b
	return {}


## Public read of an armed silo record (UI target-mode tap routing).
func silo_by_id(bid: int) -> Dictionary:
	return _silo(bid)


## Arm state for the HUD: {armed, cd, complete}.
func arm_state(bid: int) -> Dictionary:
	var b: Dictionary = _silo(bid)
	if b.is_empty():
		return {"armed": false, "cd": 0.0, "complete": false}
	return {
		"armed": bool(b.get("nuke_armed", false)),
		"cd": maxf(0.0, float(b.get("nuke_cd", 0.0))),
		"complete": bool(b.get("complete", false)),
	}


## HTML btn-arm-nuke toggle: cooldown blocks, otherwise flip armed.
## Returns {ok, armed, message} — the UI flashes `message`.
func toggle_arm(bid: int) -> Dictionary:
	var b: Dictionary = _silo(bid)
	if b.is_empty():
		return {"ok": false, "armed": false, "message": "No silo"}
	if not bool(b.get("complete", false)):
		return {"ok": false, "armed": false,
			"message": "Silo still under construction"}
	if float(b.get("nuke_cd", 0.0)) > 0.0:
		return {"ok": false, "armed": bool(b.get("nuke_armed", false)),
			"message": "Silo reloading..."}
	var armed: bool = not bool(b.get("nuke_armed", false))
	b["nuke_armed"] = armed
	if armed:
		target_silo = bid
		return {"ok": true, "armed": true,
			"message": "Nuke ARMED — tap the map to choose a target"}
	target_silo = -1
	return {"ok": true, "armed": false, "message": "Silo disarmed"}


## Leave target mode without firing (HTML "Nuke targeting cancelled").
func cancel_target() -> void:
	target_silo = -1


## ---- firing --------------------------------------------------------------

## HTML fireNuke verbatim: disarm, 120 s cooldown, ballistic big-missile
## projectile (global range — no distance cap in the HTML).
## Returns {ok, message}.
func fire_nuke(bid: int, target: Vector2) -> Dictionary:
	var b: Dictionary = _silo(bid)
	if b.is_empty() or not bool(b.get("alive", true)):
		target_silo = -1
		return {"ok": false, "message": "Silo destroyed"}
	if not bool(b.get("complete", false)):
		target_silo = -1
		return {"ok": false, "message": "Silo not complete"}
	if not bool(b.get("nuke_armed", false)) \
			or float(b.get("nuke_cd", 0.0)) > 0.0:
		target_silo = -1
		return {"ok": false, "message": "No armed nuke silo ready"}
	b["nuke_armed"] = false
	b["nuke_cd"] = NUKE_COOLDOWN
	target_silo = -1
	var faction: String = String(b.get("faction", ""))
	var from: Vector2 = b.get("position", Vector2.ZERO) + Vector2(0, -50)
	var p: Dictionary = combat.fire_projectile(
		from, -1, target, "nuke", NUKE_DMG, NUKE_SPLASH, faction, NUKE_SPEED)
	# HTML projectile flags: ballistic arc, big missile, nuke warhead,
	# only anti-nuke batteries may engage it.
	p["ballistic"] = true
	p["big_missile"] = true
	p["nuke"] = true
	p["only_anti_nuke"] = true
	_gs.bus.combat_fx.emit("nuke_launch", from)
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs,
		"%s launches a nuclear missile" % _fname(faction),
		"A bright spear climbs from a %s silo and arcs away over the horizon. Every court in the realm felt the ground tremble at ignition." % _fname(faction),
		"war")
	return {"ok": true, "message": "NUKE LAUNCHED — GLOBAL RANGE"}


## ---- detonation ------------------------------------------------------------

## HTML detonateNuke verbatim (numbers, order, counts).
func detonate_nuke(pos: Vector2, race: String) -> void:
	_gs.bus.combat_fx.emit("nuke_blast", pos)
	var R := NUKE_SPLASH  # 720
	# Units: falloff damage, knockback, ignite; fall > 0.25 kills outright
	# (HTML sets downed=false — nukes never knock out, they vaporize).
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var d: float = pos.distance_to(u.get("position", Vector2.ZERO))
		if d > R:
			continue
		var fall: float = 1.0 - d / R
		var dmg: float = 700.0 * fall + 100.0
		if fall > 0.25:
			# Outright kill regardless of remaining HP (HTML C61F branch).
			dmg = maxf(dmg, float(u.get("hp", 1.0)) + 1.0)
		# Knockback away from ground zero (HTML kbVx/kbVy 480*fall, -120 vy).
		var dir: Vector2 = u.get("position", pos) - pos
		if dir.length() < 1.0:
			dir = Vector2.RIGHT.rotated(randf() * TAU)
		dir = dir.normalized()
		var fling: float = 480.0 * fall
		u["kb_from"] = u.get("position", pos)
		u["kb_to"] = u.get("position", pos) + dir * fling
		u["kb_t"] = 0.9
		u["kb_dur"] = 0.9
		var died: bool = combat.damage_unit(
			int(u.get("id", 0)), dmg, race, -1, "nuke")
		if not died and u.get("alive", false):
			# Survivors at the rim ignite (HTML ignite 5 + rand*4).
			u["burn_t"] = 5.0 + randf() * 4.0
			u["burn_dps"] = 5.0
	# Buildings: falloff damage; survivors catch fire (HTML onFire).
	for b: Dictionary in _gs.buildings.duplicate():
		if not b.get("alive", true):
			continue
		var bsize: float = float(b.get("size", 20.0))
		var d: float = pos.distance_to(b.get("position", Vector2.ZERO))
		if d > R + bsize:
			continue
		var fall: float = 1.0 - d / (R + 50.0)
		var destroyed: bool = combat.damage_building(
			int(b.get("id", 0)), 600.0 * fall + 80.0, race)
		if not destroyed:
			_gs.bus.combat_fx.emit("building_burning",
				b.get("position", Vector2.ZERO))
	# 40 seeded wildfires (HTML seedFire 2.4, 28 + rand*20).
	if disasters != null:
		for i: int in range(40):
			var ang: float = randf() * TAU
			var rad: float = randf() * R * 0.95
			disasters.ignite(pos + Vector2(cos(ang), sin(ang)) * rad,
				28.0 + randf() * 20.0)
	# Long-lived radiation zone + the single nuclear-fallout field.
	zones.append({
		"x": pos.x, "y": pos.y,
		"r": R * 0.55, "maxR": R * 1.15,
		"intensity": 1.0, "life": ZONE_LIFE, "maxLife": ZONE_LIFE,
		"scorch": 0.0,
	})
	fallout = {"x": pos.x, "y": pos.y, "r": R * 1.2,
		"life": FALLOUT_LIFE, "maxLife": FALLOUT_LIFE}
	# Nuclear rain (HTML detonateNuke falloutDrops, 120 motes): glowing
	# green fallout drifting down over 12-30 s. Pure visual sim state —
	# drawn by world/radiation_overlay.gd.
	for i: int in range(120):
		rain.append({
			"x": pos.x + (randf() - 0.5) * R * 1.6,
			"y": pos.y - 80.0 - randf() * 200.0,
			"vx": (randf() - 0.5) * 30.0,
			"vy": 40.0 + randf() * 70.0,
			"life": 12.0 + randf() * 18.0,
			"size": 2.0 + randf() * 4.0,
			"glow": randf() < 0.3,
		})
	# Chronicle archive + bus (news-desk standing rule, 2026-10-06).
	SimGazette.publish_or_emit(_gs,
		"NUCLEAR DETONATION — fallout incoming",
		"A second sun rose over the realm and died screaming. The crater glows green; nothing will grow there for a generation. Fired by %s." % _fname(race),
		"disaster")
	_gs.bus.disaster_spawned.emit("nuke", pos)


## HTML detonateJumbo parity: artillery jumbo warheads leave a smaller,
## shorter-lived hot zone (r R*0.35, maxR R*0.7, intensity 0.55, life 90).
func detonate_jumbo(pos: Vector2, blast_r: float) -> void:
	zones.append({
		"x": pos.x, "y": pos.y,
		"r": blast_r * 0.35, "maxR": blast_r * 0.7,
		"intensity": 0.55, "life": 90.0, "maxLife": 90.0,
		"scorch": 0.0,
	})


## HTML radiationAt verbatim.
func radiation_at(pos: Vector2) -> float:
	var best := 0.0
	for z: Dictionary in zones:
		var zp := Vector2(float(z.get("x", 0.0)), float(z.get("y", 0.0)))
		var d: float = pos.distance_to(zp)
		var zr: float = float(z.get("r", 1.0))
		if d >= zr:
			continue
		var fall: float = (1.0 - d / zr) * float(z.get("intensity", 1.0)) \
			* minf(1.0, float(z.get("life", 0.0)) \
				/ maxf(1.0, float(z.get("maxLife", 1.0)) * 0.35))
		best = maxf(best, fall)
	if not fallout.is_empty():
		var fp := Vector2(float(fallout.get("x", 0.0)),
			float(fallout.get("y", 0.0)))
		var d: float = pos.distance_to(fp)
		var fr: float = float(fallout.get("r", 1.0))
		if d < fr:
			best = maxf(best, (1.0 - d / fr) * 0.85 \
				* (float(fallout.get("life", 0.0)) \
					/ maxf(1.0, float(fallout.get("maxLife", 1.0)))))
	return best


## ---- tick ------------------------------------------------------------------

func tick(delta: float) -> void:
	# Silo cooldown decay (HTML nukeCd ticks down on the building).
	for b: Dictionary in _gs.buildings:
		if String(b.get("type", "")) != "nuke_silo":
			continue
		var cd: float = float(b.get("nuke_cd", 0.0))
		if cd > 0.0:
			b["nuke_cd"] = maxf(0.0, cd - delta)
	# Radiation zones decay; the contamination spreads toward maxR.
	for i: int in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		z["life"] = float(z.get("life", 0.0)) - delta
		if float(z.get("life", 0.0)) <= 0.0:
			zones.remove_at(i)
			continue
		var max_life: float = maxf(1.0, float(z.get("maxLife", ZONE_LIFE)))
		var age: float = 1.0 - float(z.get("life", 0.0)) / max_life
		# HTML: grow toward maxR over the first third of life only.
		if age < 0.35:
			var r: float = float(z.get("r", 1.0))
			var max_r: float = float(z.get("maxR", r))
			if r < max_r:
				z["r"] = minf(max_r, r + (max_r - r) * delta * 0.15)
		z["scorch"] = minf(1.0, float(z.get("scorch", 0.0)) + delta * 0.02)
		z["intensity"] = maxf(0.15, 1.0 - age * 0.7)
		_tick_zone_ground(z, delta)
	if not fallout.is_empty():
		fallout["life"] = float(fallout.get("life", 0.0)) - delta
		if float(fallout.get("life", 0.0)) <= 0.0:
			fallout = {}
		elif disasters != null and randf() < delta * 4.0:
			# HTML: the fallout field seeds small fires while it lingers.
			var fx: float = float(fallout.get("x", 0.0))
			var fy: float = float(fallout.get("y", 0.0))
			var fr: float = float(fallout.get("r", 1.0))
			disasters.ignite(
				Vector2(fx + (randf() - 0.5) * fr, fy + (randf() - 0.5) * fr),
				6.0)
	# Nuclear rain drifts down and fades (HTML falloutDrops tick).
	for i: int in range(rain.size() - 1, -1, -1):
		var drop: Dictionary = rain[i]
		drop["life"] = float(drop.get("life", 0.0)) - delta
		if float(drop.get("life", 0.0)) <= 0.0:
			rain.remove_at(i)
			continue
		drop["x"] = float(drop.get("x", 0.0)) \
			+ float(drop.get("vx", 0.0)) * delta
		drop["y"] = float(drop.get("y", 0.0)) \
			+ float(drop.get("vy", 50.0)) * delta
	# Radiation on units (HTML: every 4th frame).
	_rad_accum += delta
	if _rad_accum >= RAD_TICK:
		_rad_accum = 0.0
		_tick_radiation()


## HTML zone tick: "Scorch ground / kill sparse trees in hot zone".
## Twice a second per zone: a sickly scorch stain lands at a random point
## (visual via the combat_fx bus) and nearby trees take 8 damage (HTML:
## t.hp starts at 20); dead trees are felled scorched, without pickups.
func _tick_zone_ground(z: Dictionary, delta: float) -> void:
	if randf() >= delta * 2.0:
		return
	var zr: float = float(z.get("r", 1.0))
	var ang: float = randf() * TAU
	var rad: float = randf() * zr
	var gx: float = float(z.get("x", 0.0)) + cos(ang) * rad
	var gy: float = float(z.get("y", 0.0)) + sin(ang) * rad
	_gs.bus.combat_fx.emit("rad_scorch", Vector2(gx, gy))
	if randf() >= 0.15:
		return
	for s: Dictionary in _gs.work_sites:
		if String(s.get("kind", "")) != "tree" \
				or bool(s.get("felled", false)):
			continue
		var sp: Vector2 = s.get("position", Vector2.ZERO)
		var dx: float = sp.x - gx
		var dy: float = sp.y - gy
		if dx * dx + dy * dy >= 1600.0:
			continue
		var hp: float = float(s.get("rad_hp", 20.0)) - 8.0
		s["rad_hp"] = hp
		if hp <= 0.0:
			# Scorched dead — no wood pickups (HTML: t.alive = false).
			s["felled"] = true
			s["amount"] = 0.0
		break  # HTML breaks after the first tree in range


## HTML radiation tick verbatim: suits, bubbles, drain.
func _tick_radiation() -> void:
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var upos: Vector2 = u.get("position", Vector2.ZERO)
		var rad: float = radiation_at(upos)
		if rad > 0.12:
			if not bool(u.get("inRadSuit", false)):
				u["inRadSuit"] = true
				if randf() < 0.08:
					var faction: String = String(u.get("faction", ""))
					var line: String = String(SUIT_LINES.get(faction,
						"Radiation suit sealed."))
					_gs.bus.unit_said.emit(int(u.get("id", 0)), line)
			u["radLevel"] = rad
			# Slow health drain if extreme (HTML: rad > 0.65, 2% sample).
			if rad > 0.65 and randf() < 0.02:
				u["hp"] = maxf(1.0, float(u.get("hp", 1.0)) - 1.0)
				u["stress"] = minf(100.0, float(u.get("stress", 0.0)) + 2.0)
			u["_radSuitExit"] = 0.0
		elif bool(u.get("inRadSuit", false)):
			# Keep the suit briefly after leaving (HTML _radSuitExit > 4).
			var ex: float = float(u.get("_radSuitExit", 0.0)) + RAD_TICK
			u["_radSuitExit"] = ex
			if ex > SUIT_EXIT_GRACE:
				u["inRadSuit"] = false
				u["_radSuitExit"] = 0.0
				u["radLevel"] = 0.0
		else:
			u["radLevel"] = 0.0


## ---- save/load ---------------------------------------------------------------

func to_dict() -> Dictionary:
	var zrecs: Array = []
	for z: Dictionary in zones:
		zrecs.append(z.duplicate())
	var rrecs: Array = []
	for r: Dictionary in rain:
		rrecs.append(r.duplicate())
	return {
		"zones": zrecs,
		"fallout": fallout.duplicate(),
		"rain": rrecs,
		"target_silo": target_silo,
	}


func from_dict(d: Dictionary) -> void:
	zones.clear()
	for e in d.get("zones", []):
		var z := e as Dictionary
		if z.is_empty():
			continue
		zones.append(z.duplicate())
	fallout = (d.get("fallout", {}) as Dictionary).duplicate()
	rain.clear()
	for e in d.get("rain", []):
		var r := e as Dictionary
		if r.is_empty():
			continue
		rain.append(r.duplicate())
	target_silo = int(d.get("target_silo", -1))
	_rad_accum = 0.0


func _fname(faction: String) -> String:
	return String(Config.FACTIONS.get(faction, {}).get("name", faction))
