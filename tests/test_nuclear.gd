extends SceneTree
## Cursing Gnomes — nuclear warfare tests (Jeremy 2026-10-04).
##
## HTML parity (fix79 fireNuke / detonateNuke / radiationAt): silo arming,
## global-range ballistic launch, verbatim detonation numbers (R 720,
## units 700*fall+100, buildings 600*fall+80, 40 seeded fires, 240 s
## radiation zone, 90 s fallout), radiation suits + drain, cooldowns,
## save/load round-trip, combat hook routing.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_nuclear.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


class _DisastersStub:
	var fires: Array = []
	func ignite(pos: Vector2, intensity: float = 60.0) -> Dictionary:
		var f := {"position": pos, "intensity": intensity}
		fires.append(f)
		return f


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.player_faction = "humans"
	var combat := SimCombat.new(gs)
	var nukes := SimNuclear.new()
	nukes.setup(gs)
	nukes.combat = combat
	var dis := _DisastersStub.new()
	nukes.disasters = dis
	combat.nuclear = nukes
	gs.nuclear = nukes
	return {"gs": gs, "combat": combat, "nukes": nukes, "dis": dis}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _silo(w: Dictionary, faction := "humans",
		pos := Vector2(1000, 1000)) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": "nuke_silo", "faction": faction, "town_id": -1,
		"position": pos, "complete": true, "progress": 1.0,
		"hp": 900.0, "max_hp": 900.0, "size": 30.0,
	})


func _unit(w: Dictionary, faction: String, pos: Vector2,
		hp := 100.0) -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, "worker", -1, pos)
	u["hp"] = hp
	u["max_hp"] = hp
	return u


## --- HTML-verbatim constants -------------------------------------------------


func _test_constants() -> void:
	_check("nuke: cooldown 120", SimNuclear.NUKE_COOLDOWN == 120.0)
	_check("nuke: speed 260", SimNuclear.NUKE_SPEED == 260.0)
	_check("nuke: dmg 900", SimNuclear.NUKE_DMG == 900.0)
	_check("nuke: splash 720", SimNuclear.NUKE_SPLASH == 720.0)
	_check("nuke: zone life 240", SimNuclear.ZONE_LIFE == 240.0)
	_check("nuke: fallout life 90", SimNuclear.FALLOUT_LIFE == 90.0)


## --- arming ------------------------------------------------------------------


func _test_arming() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var gs: GameState = w["gs"]
	# Incomplete silo cannot arm.
	var raw: Dictionary = gs.add_building({
		"type": "nuke_silo", "faction": "humans", "town_id": -1,
		"position": Vector2(500, 500), "complete": false, "progress": 0.3,
		"hp": 900.0, "max_hp": 900.0,
	})
	var r: Dictionary = nukes.toggle_arm(int(raw["id"]))
	_check("nuke: incomplete silo refuses arm", not bool(r["ok"]))
	# Complete silo arms: target mode engages.
	var b: Dictionary = _silo(w)
	var bid: int = int(b["id"])
	r = nukes.toggle_arm(bid)
	_check("nuke: arm ok", bool(r["ok"]) and bool(r["armed"]))
	_check("nuke: arm enters target mode", nukes.target_silo == bid)
	_check("nuke: arm message", String(r["message"]).contains("ARMED"))
	var st: Dictionary = nukes.arm_state(bid)
	_check("nuke: arm_state armed", bool(st["armed"]))
	_check("nuke: arm_state complete", bool(st["complete"]))
	# Toggle again: disarm, target mode clears.
	r = nukes.toggle_arm(bid)
	_check("nuke: disarm ok", bool(r["ok"]) and not bool(r["armed"]))
	_check("nuke: disarm clears target mode", nukes.target_silo == -1)
	_check("nuke: disarm message", String(r["message"]).contains("disarmed"))
	# Cooldown blocks arming.
	b["nuke_cd"] = 50.0
	r = nukes.toggle_arm(bid)
	_check("nuke: cooldown blocks arm", not bool(r["ok"]))
	_check("nuke: cooldown message", String(r["message"]).contains("reloading"))
	# Unknown silo id.
	r = nukes.toggle_arm(999999)
	_check("nuke: unknown silo refused", not bool(r["ok"]))
	_free_world(w)


func _test_silos_of() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	_silo(w, "humans", Vector2(1000, 1000))
	_silo(w, "gnomes", Vector2(2000, 2000))
	_check("nuke: silos_of filters faction",
		nukes.silos_of("humans").size() == 1)
	_check("nuke: silos_of other faction",
		nukes.silos_of("gnomes").size() == 1)
	_free_world(w)


## --- firing ------------------------------------------------------------------


func _test_fire() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var combat: SimCombat = w["combat"]
	var b: Dictionary = _silo(w)
	var bid: int = int(b["id"])
	# Cannot fire while disarmed.
	var r: Dictionary = nukes.fire_nuke(bid, Vector2(5000, 5000))
	_check("nuke: disarmed silo cannot fire", not bool(r["ok"]))
	# Arm then fire: global range, HTML-verbatim projectile.
	nukes.toggle_arm(bid)
	var stories: Array = []
	(w["gs"] as GameState).bus.gazette_story.connect(
		func(s: Dictionary) -> void: stories.append(s))
	r = nukes.fire_nuke(bid, Vector2(9000, 9000))
	_check("nuke: fire ok", bool(r["ok"]))
	_check("nuke: fire message", String(r["message"]).contains("LAUNCHED"))
	_check("nuke: silo disarmed after fire", not bool(b.get("nuke_armed", true)))
	_check("nuke: cooldown set 120", float(b.get("nuke_cd", 0.0)) == 120.0)
	_check("nuke: target mode cleared", nukes.target_silo == -1)
	_check("nuke: one projectile", combat.projectiles.size() == 1)
	var p: Dictionary = combat.projectiles[0]
	_check("nuke: kind nuke", String(p.get("kind", "")) == "nuke")
	_check("nuke: dmg 900", float(p.get("dmg", 0.0)) == 900.0)
	_check("nuke: splash 720", float(p.get("splash", 0.0)) == 720.0)
	_check("nuke: speed 260", float(p.get("speed", 0.0)) == 260.0)
	_check("nuke: ballistic", bool(p.get("ballistic", false)))
	_check("nuke: big_missile", bool(p.get("big_missile", false)))
	_check("nuke: nuke flag", bool(p.get("nuke", false)))
	_check("nuke: only anti-nuke", bool(p.get("only_anti_nuke", false)))
	_check("nuke: launch gazette story", stories.size() == 1)
	# Firing again immediately fails (disarmed + cooling down).
	r = nukes.fire_nuke(bid, Vector2(9000, 9000))
	_check("nuke: no double fire", not bool(r["ok"]))
	_free_world(w)


func _test_cooldown_tick() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var b: Dictionary = _silo(w)
	b["nuke_cd"] = 10.0
	nukes.tick(4.0)
	_check("nuke: cooldown decays", float(b.get("nuke_cd", 0.0)) == 6.0)
	nukes.tick(10.0)
	_check("nuke: cooldown bottoms at 0", float(b.get("nuke_cd", 0.0)) == 0.0)
	_free_world(w)


## --- detonation (HTML detonateNuke verbatim) ----------------------------------


func _test_detonate_damage() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var gs: GameState = w["gs"]
	var ground := Vector2(4000, 4000)
	var center_u: Dictionary = _unit(w, "gnomes", ground, 100.0)
	var mid_u: Dictionary = _unit(w, "gnomes", ground + Vector2(500, 0), 10000.0)
	var rim_u: Dictionary = _unit(w, "gnomes", ground + Vector2(600, 0), 10000.0)
	var far_u: Dictionary = _unit(w, "gnomes", ground + Vector2(900, 0), 100.0)
	var stories: Array = []
	gs.bus.gazette_story.connect(
		func(s: Dictionary) -> void: stories.append(s))
	nukes.detonate_nuke(ground, "humans")
	# Center: vaporized (fall 1.0 > 0.25 -> outright kill, never downed).
	_check("nuke: ground-zero unit dead", not bool(center_u.get("alive", true)))
	_check("nuke: ground-zero not downed", not bool(center_u.get("downed", false)))
	# 500 px: fall = 1 - 500/720 = 0.306 > 0.25 -> outright kill.
	_check("nuke: mid unit dead (fall>0.25)", not bool(mid_u.get("alive", true)))
	# 600 px: fall = 0.167 -> 700*0.167+100 = 217 dmg, survives, ignites.
	_check("nuke: rim unit alive", bool(rim_u.get("alive", true)))
	_check("nuke: rim damage ~217",
		absf(float(rim_u.get("hp", 0.0)) - (10000.0 - 217.0)) < 2.0)
	_check("nuke: rim unit ignited", float(rim_u.get("burn_t", 0.0)) > 5.0)
	# 900 px: outside R=720, untouched.
	_check("nuke: far unit unharmed", float(far_u.get("hp", 0.0)) == 100.0)
	# Knockback was applied to the survivor.
	_check("nuke: survivor flung", rim_u.has("kb_to"))
	# Detonation gazette story.
	_check("nuke: detonation gazette", stories.size() == 1)
	_check("nuke: detonation headline",
		String(stories[0].get("headline", "")).contains("DETONATION"))
	_free_world(w)


func _test_detonate_buildings() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var gs: GameState = w["gs"]
	var ground := Vector2(4000, 4000)
	var hut: Dictionary = gs.add_building({
		"type": "hut", "faction": "gnomes", "town_id": -1,
		"position": ground + Vector2(100, 0), "complete": true,
		"progress": 1.0, "hp": 900.0, "max_hp": 900.0, "size": 30.0,
	})
	nukes.detonate_nuke(ground, "humans")
	# 100 px: fall = 1 - 100/770 = 0.87 -> 600*0.87+80 = 602 dmg.
	_check("nuke: building damaged ~602",
		absf(float(hut.get("hp", 0.0)) - (900.0 - 602.0)) < 3.0)
	_free_world(w)


func _test_detonate_aftermath() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var dis: _DisastersStub = w["dis"]
	var ground := Vector2(4000, 4000)
	nukes.detonate_nuke(ground, "humans")
	# 40 seeded fires (HTML seedFire loop).
	_check("nuke: 40 fires seeded", dis.fires.size() == 40)
	# Radiation zone: r = 720*0.55 = 396, life 240.
	_check("nuke: one radiation zone", nukes.zones.size() == 1)
	var z: Dictionary = nukes.zones[0]
	_check("nuke: zone r 396", absf(float(z.get("r", 0.0)) - 396.0) < 0.01)
	_check("nuke: zone maxR 828", absf(float(z.get("maxR", 0.0)) - 828.0) < 0.01)
	_check("nuke: zone life 240", float(z.get("life", 0.0)) == 240.0)
	# Nuclear fallout: r = 864, life 90.
	_check("nuke: fallout set", not nukes.fallout.is_empty())
	_check("nuke: fallout r 864",
		absf(float(nukes.fallout.get("r", 0.0)) - 864.0) < 0.01)
	_check("nuke: fallout life 90", float(nukes.fallout.get("life", 0.0)) == 90.0)
	_free_world(w)


func _test_radiation_at() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var ground := Vector2(4000, 4000)
	nukes.detonate_nuke(ground, "humans")
	# Ground zero: zone falloff = 1.0 (full life).
	_check("nuke: radiation_at center ~1.0",
		absf(nukes.radiation_at(ground) - 1.0) < 0.01)
	# 500 px: outside zone r=396, fallout only: (1-500/864)*0.85 = 0.358.
	_check("nuke: radiation_at 500px ~0.358",
		absf(nukes.radiation_at(ground + Vector2(500, 0)) - 0.358) < 0.02)
	# 2000 px: nothing.
	_check("nuke: radiation_at far = 0",
		nukes.radiation_at(ground + Vector2(2000, 0)) == 0.0)
	_free_world(w)


func _test_radiation_tick() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var ground := Vector2(4000, 4000)
	nukes.detonate_nuke(ground, "humans")
	var u: Dictionary = _unit(w, "gnomes", ground + Vector2(50, 0), 500.0)
	# Radiation tick runs inside tick() every 0.25 s.
	nukes.tick(0.3)
	_check("nuke: rad suit donned", bool(u.get("inRadSuit", false)))
	_check("nuke: radLevel set", float(u.get("radLevel", 0.0)) > 0.12)
	# Extreme radiation drains hp (rad ~1.0 > 0.65): run many ticks.
	var hp0: float = float(u.get("hp", 0.0))
	seed(7)
	for i: int in range(400):
		nukes.tick(0.25)
	_check("nuke: extreme rad drains hp", float(u.get("hp", 0.0)) < hp0)
	_check("nuke: unit not killed by drain", float(u.get("hp", 0.0)) >= 1.0)
	# Walk out: suit kept briefly, then removed after the grace period.
	u["position"] = ground + Vector2(3000, 0)
	for i: int in range(30):
		nukes.tick(0.25)
	_check("nuke: suit removed after grace", not bool(u.get("inRadSuit", true)))
	_free_world(w)


func _test_zone_decay() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	nukes.detonate_nuke(Vector2(4000, 4000), "humans")
	nukes.tick(90.0)
	_check("nuke: fallout gone at 90s", nukes.fallout.is_empty())
	_check("nuke: zone still alive at 90s", nukes.zones.size() == 1)
	nukes.tick(160.0)
	_check("nuke: zone gone at 250s", nukes.zones.is_empty())
	_free_world(w)


## --- zone tick verbatim (growth gate, intensity, scorch) -------------------


func _test_zone_tick_verbatim() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var ground := Vector2(4000, 4000)
	nukes.detonate_nuke(ground, "humans")
	# HTML: intensity = max(0.15, 1 - age*0.7). At 90 s of 240: 0.7375.
	nukes.tick(90.0)
	var z: Dictionary = nukes.zones[0]
	_check("nuke: zone intensity decays",
		absf(float(z.get("intensity", 0.0)) - 0.7375) < 0.001)
	# HTML: scorch = min(1, dt*0.02) accumulation. 90 s -> 1.0.
	_check("nuke: zone scorch saturates",
		absf(float(z.get("scorch", 0.0)) - 1.0) < 0.001)
	# HTML: growth only while age < 0.35 — radius freezes after ~84 s.
	var r_frozen: float = float(z.get("r", 0.0))
	_check("nuke: zone grew early", r_frozen > 396.0)
	nukes.tick(90.0)
	_check("nuke: zone radius frozen late",
		absf(float(nukes.zones[0].get("r", 0.0)) - r_frozen) < 0.001)
	# Intensity keeps decaying (age 230/240 -> 0.3292).
	nukes.tick(50.0)
	_check("nuke: zone intensity keeps decaying",
		absf(float(nukes.zones[0].get("intensity", 0.0)) - 0.3292) < 0.01)
	_free_world(w)


## --- fallout rain (HTML falloutDrops) ----------------------------------------


func _test_fallout_rain() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var ground := Vector2(4000, 4000)
	nukes.detonate_nuke(ground, "humans")
	_check("nuke: 120 rain drops", nukes.rain.size() == 120)
	var ok := true
	for d: Dictionary in nukes.rain:
		var dx: float = absf(float(d.get("x", 0.0)) - ground.x)
		var dy: float = float(d.get("y", 0.0)) - ground.y
		var vy: float = float(d.get("vy", 0.0))
		var life: float = float(d.get("life", 0.0))
		var sz: float = float(d.get("size", 0.0))
		if dx > 576.0 or dy < -280.0 or dy > -80.0 \
				or vy < 40.0 or vy > 110.0 \
				or life < 12.0 or life > 30.0 \
				or sz < 2.0 or sz > 6.0:
			ok = false
	_check("nuke: rain drop fields HTML-verbatim", ok)
	# Drops drift downward and die out (life 12-30 s).
	var y0: float = float(nukes.rain[0].get("y", 0.0))
	nukes.tick(5.0)
	_check("nuke: rain drifts down", float(nukes.rain[0].get("y", 0.0)) > y0)
	nukes.tick(8.0)
	_check("nuke: rain decays", nukes.rain.size() < 120)
	nukes.tick(20.0)
	_check("nuke: rain all gone", nukes.rain.is_empty())
	_free_world(w)


## --- fallout field seeds fires -------------------------------------------------


func _test_fallout_fires() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var dis: _DisastersStub = w["dis"]
	nukes.detonate_nuke(Vector2(4000, 4000), "humans")
	_check("nuke: 40 blast fires", dis.fires.size() == 40)
	# HTML: while the fallout field lingers, dt*4 roll seeds small fires
	# (intensity 6). tick(1) rolls always succeed (randf() < 4).
	for i: int in range(5):
		nukes.tick(1.0)
	_check("nuke: fallout field seeded fires", dis.fires.size() == 45)
	_free_world(w)


## --- zones scorch ground and kill sparse trees ---------------------------------


func _test_zone_scorches_trees() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var gs: GameState = w["gs"]
	var ground := Vector2(4000, 4000)
	gs.add_work_site({"kind": "tree", "position": ground,
		"amount": 60.0, "yield": 60.0})
	# Small pinned zone: the scorch tick picks a random point inside it
	# (HTML: 8 dmg vs 20 hp, 15% roll, trees within 40 px of the point).
	var z := {"x": ground.x, "y": ground.y, "r": 50.0, "maxR": 50.0,
		"intensity": 0.55, "life": 90.0, "maxLife": 90.0, "scorch": 0.0}
	seed(99)
	for i in range(2000):
		nukes._tick_zone_ground(z, 0.25)
		if bool(gs.work_sites[0].get("felled", false)):
			break
	_check("nuke: radiation damages trees",
		float(gs.work_sites[0].get("rad_hp", 20.0)) < 20.0)
	_check("nuke: radiation kills trees after 3 hits",
		bool(gs.work_sites[0].get("felled", false)))
	# Scorched trees drop no wood pickups (HTML: t.alive = false).
	_check("nuke: scorched tree drops no pickups", gs.pickups.is_empty())
	_free_world(w)


## --- jumbo mini radiation zone --------------------------------------------------


func _test_jumbo_zone() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var combat: SimCombat = w["combat"]
	var ground := Vector2(4000, 4000)
	# Direct call: HTML detonateJumbo numbers.
	nukes.detonate_jumbo(ground, 320.0)
	_check("nuke: jumbo leaves zone", nukes.zones.size() == 1)
	var z: Dictionary = nukes.zones[0]
	_check("nuke: jumbo r 112", absf(float(z.get("r", 0.0)) - 112.0) < 0.01)
	_check("nuke: jumbo maxR 224", absf(float(z.get("maxR", 0.0)) - 224.0) < 0.01)
	_check("nuke: jumbo intensity 0.55",
		absf(float(z.get("intensity", 0.0)) - 0.55) < 0.001)
	_check("nuke: jumbo life 90", float(z.get("life", 0.0)) == 90.0)
	# Combat hook: a jumbo_rocket hit routes through the nuclear system.
	nukes.zones.clear()
	var p: Dictionary = combat.fire_projectile(
		ground + Vector2(0, -3000), -1, ground, "jumbo_rocket",
		280.0, 320.0, "humans", 500.0)
	combat._resolve_hit(p, ground)
	_check("nuke: jumbo hook leaves zone", nukes.zones.size() == 1)
	_check("nuke: jumbo hook r 112",
		absf(float(nukes.zones[0].get("r", 0.0)) - 112.0) < 0.01)
	_free_world(w)


## --- combat hook ---------------------------------------------------------------


func _test_combat_hook() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var combat: SimCombat = w["combat"]
	var ground := Vector2(4000, 4000)
	var u: Dictionary = _unit(w, "gnomes", ground, 100.0)
	# A nuke-kind projectile arriving routes through detonate_nuke.
	var p: Dictionary = combat.fire_projectile(
		ground + Vector2(0, -5000), -1, ground, "nuke",
		900.0, 720.0, "humans", 260.0)
	combat._resolve_hit(p, ground)
	_check("nuke: combat hook detonates", not bool(u.get("alive", true)))
	_check("nuke: combat hook leaves zone", nukes.zones.size() == 1)
	_free_world(w)


func _test_save_load() -> void:
	var w := _new_world()
	var nukes: SimNuclear = w["nukes"]
	var ground := Vector2(4000, 4000)
	nukes.detonate_nuke(ground, "humans")
	nukes.target_silo = 42
	var d: Dictionary = nukes.to_dict()
	var w2 := _new_world()
	var nukes2: SimNuclear = w2["nukes"]
	nukes2.from_dict(d)
	_check("nuke: save/load zones", nukes2.zones.size() == 1)
	_check("nuke: save/load zone pos",
		absf(float(nukes2.zones[0].get("x", 0.0)) - 4000.0) < 0.01)
	_check("nuke: save/load fallout", not nukes2.fallout.is_empty())
	_check("nuke: save/load target_silo", nukes2.target_silo == 42)
	_check("nuke: save/load radiation matches",
		absf(nukes2.radiation_at(ground) - nukes.radiation_at(ground)) < 0.001)
	_check("nuke: save/load rain", nukes2.rain.size() == 120)
	_free_world(w)
	_free_world(w2)


func _init() -> void:
	_test_constants()
	_test_arming()
	_test_silos_of()
	_test_fire()
	_test_cooldown_tick()
	_test_detonate_damage()
	_test_detonate_buildings()
	_test_detonate_aftermath()
	_test_radiation_at()
	_test_radiation_tick()
	_test_zone_decay()
	_test_zone_tick_verbatim()
	_test_fallout_rain()
	_test_fallout_fires()
	_test_zone_scorches_trees()
	_test_jumbo_zone()
	_test_combat_hook()
	_test_save_load()
	print("test_nuclear: %d passed, %d failed" % [_passed, _failed])
	if not _failures.is_empty():
		print("  failures: ", _failures)
	quit(1 if _failed > 0 else 0)
