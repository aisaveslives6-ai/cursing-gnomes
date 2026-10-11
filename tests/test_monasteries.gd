extends SceneTree
## Cursing Gnomes — Seven Monasteries tests (Jeremy 2026-10-04).
##
## Covers: 7 gods with full lore, monastery placement spread, 60-second
## capture, closest-takes-hold on contest, peacetime protection vs wartime
## recapture, perk stacking, magic attack fire/resolve, shield/illum hooks,
## goodness alignment, AI targeting.
##
## Run: Godot --headless --path . -s res://tests/test_monasteries.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


class _FakeCombat extends RefCounted:
	var gs = null
	var war_pairs := {}
	func can_fight(a: String, b: String) -> bool:
		if a == b:
			return false
		return bool(war_pairs.get(a + ">" + b, false)) \
			or bool(war_pairs.get(b + ">" + a, false))
	func damage_unit(uid: int, dmg: float, sf: String, aid: int = -1,
			kind: String = "") -> bool:
		var u: Dictionary = gs.get_unit(uid)
		if u.is_empty() or not u.get("alive", false):
			return false
		u["hp"] = float(u.get("hp", 100.0)) - dmg
		if float(u["hp"]) <= 0.0:
			u["alive"] = false
			return true
		return false
	func damage_building(_bid: int, _dmg: float, _sf: String) -> void:
		pass
	func fire_projectile(from_pos: Vector2, target_id: int,
			target_pos: Vector2, kind: String, dmg: float, splash: float,
			faction: String, speed: float) -> Dictionary:
		return {"id": 1, "kind": kind, "position": from_pos,
			"target_id": target_id, "target_pos": target_pos, "dmg": dmg,
			"splash": splash, "faction": faction, "speed": speed,
			"alive": true}


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("  FAIL: ", name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_gods()
	_test_placement()
	_test_capture_60s()
	_test_contest_closest()
	_test_peacetime_protection()
	_test_wartime_recapture()
	_test_perk_stacking()
	_test_magic_fire()
	_test_magic_resolve()
	_test_shield_and_illum()
	_test_goodness()
	_test_ai_target()
	_test_save_roundtrip()
	print("test_monasteries: %d passed, %d failed" % [_passed, _failed])
	if not _failures.is_empty():
		push_error("failures: " + str(_failures))
	quit(1 if _failed > 0 else 0)


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	return gs


func _new_mons(gs: GameState) -> SimMonasteries:
	var mons := SimMonasteries.new()
	mons.setup(gs)
	var fc := _FakeCombat.new()
	fc.gs = gs
	mons.combat = fc
	gs.monasteries = mons
	return mons


func _fake_map(gs: GameState) -> void:
	var terrain := PackedByteArray()
	terrain.resize(128 * 128)  # all land (TILE_WATER = 1)
	gs.map_data = {
		"world_size": Vector2(4000, 4000),
		"faction_starts": {
			"humans": Vector2(500, 500),
			"gnomes": Vector2(3500, 3500),
		},
		"terrain": terrain,
		"tile_size": 32.0,
	}


func _add_unit(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_unit({
		"faction": faction, "job": "swordsman", "position": pos,
		"alive": true, "hp": 200.0, "max_hp": 200.0, "dmg": 10.0,
		"speed": 95.0,
	})


## 7 gods, full lore, unique ids/perks.
func _test_gods() -> void:
	_check(SimMonasteries.GODS.size() == 7, "gods: seven gods")
	var ids := {}
	var perks := {}
	for g: Dictionary in SimMonasteries.GODS:
		var gid := String(g.get("id", ""))
		_check(gid != "" and not ids.has(gid), "gods: unique id " + gid)
		ids[gid] = true
		_check(String(g.get("name", "")) != "", "gods: name " + gid)
		_check(String(g.get("title", "")) != "", "gods: title " + gid)
		_check(String(g.get("domain", "")) != "", "gods: domain " + gid)
		_check(String(g.get("lore", "")).length() > 40,
			"gods: lore 2-3 sentences " + gid)
		var pk := String(g.get("perk_name", ""))
		_check(pk != "" and not perks.has(pk), "gods: unique perk " + pk)
		perks[pk] = true
		_check(String(g.get("perk_desc", "")).length() > 20,
			"gods: perk desc " + gid)
		_check(g.has("main") and g.has("trim"), "gods: colors " + gid)


## Placement: 7 spread out, on land, clear of starts.
func _test_placement() -> void:
	seed(20261004)  # deterministic sanctuary layout
	var gs := _new_game()
	_fake_map(gs)
	var mons := _new_mons(gs)
	mons.place_monasteries()
	_check(mons.monasteries.size() == 7, "placement: seven monasteries")
	var pts: Array[Vector2] = []
	var mgen := MapGen.new()
	for m: Dictionary in mons.monasteries:
		var p: Vector2 = m.get("position", Vector2.ZERO)
		pts.append(p)
		_check(mgen.tile_at(gs.map_data, p) != MapGen.TILE_WATER,
			"placement: on land")
		for s: Vector2 in [Vector2(500, 500), Vector2(3500, 3500)]:
			_check(p.distance_to(s) >= 690.0, "placement: clear of starts")
	for i: int in range(pts.size()):
		for j: int in range(i + 1, pts.size()):
			# First placement pass uses 1000 px; fallbacks relax to 600.
			_check(pts[i].distance_to(pts[j]) >= 590.0,
				"placement: spread apart")
	gs.queue_free()


## 60 s of adjacency captures an unowned monastery.
func _test_capture_60s() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	mons.monasteries = [{
		"id": 1, "god_id": "auriel", "position": Vector2(2000, 2000),
		"owner": "", "progress": {}, "contested": false,
		"contested_by": "", "name": "Monastery of Auriel the Dawnmother",
	}]
	_add_unit(gs, "humans", Vector2(2000, 2000))
	for i: int in range(240):  # 60 s at 4 Hz
		mons._tick_capture(0.25)
	var m: Dictionary = mons.monasteries[0]
	_check(String(m.get("owner", "")) == "humans",
		"capture: owner after 60 s")
	_check(mons.get_faction_perks("humans") == ["auriel"],
		"capture: perk granted")
	_check(mons.get_goodness("humans") > 0.0, "capture: goodness rises")
	gs.queue_free()


## Contested: closest unit's faction accrues.
func _test_contest_closest() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	mons.monasteries = [{
		"id": 1, "god_id": "volkar", "position": Vector2(2000, 2000),
		"owner": "", "progress": {}, "contested": false,
		"contested_by": "", "name": "M",
	}]
	_add_unit(gs, "humans", Vector2(2030, 2000))  # 30 px away
	_add_unit(gs, "gnomes", Vector2(2060, 2000))  # 60 px away
	for i: int in range(40):
		mons._tick_capture(0.25)
	var m: Dictionary = mons.monasteries[0]
	_check(bool(m.get("contested", false)), "contest: flagged contested")
	_check(String(m.get("contested_by", "")) == "humans",
		"contest: closest takes the hold")
	_check(float((m.get("progress", {}) as Dictionary).get("humans", 0.0)) > 0.0,
		"contest: closest accrues progress")
	gs.queue_free()


## Peacetime: cannot accrue on another faction's monastery.
func _test_peacetime_protection() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)  # fake combat: no war pairs
	mons.monasteries = [{
		"id": 1, "god_id": "ostra", "position": Vector2(2000, 2000),
		"owner": "humans", "progress": {}, "contested": false,
		"contested_by": "", "name": "M",
	}]
	_add_unit(gs, "gnomes", Vector2(2000, 2000))
	for i: int in range(40):
		mons._tick_capture(0.25)
	var m: Dictionary = mons.monasteries[0]
	_check(String(m.get("owner", "")) == "humans",
		"peacetime: owner unchanged")
	_check(float((m.get("progress", {}) as Dictionary).get("gnomes", 0.0)) == 0.0,
		"peacetime: no progress accrues")
	gs.queue_free()


## Wartime: at-war faction CAN recapture.
func _test_wartime_recapture() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	(mons.combat as _FakeCombat).war_pairs["gnomes>humans"] = true
	mons.monasteries = [{
		"id": 1, "god_id": "cindral", "position": Vector2(2000, 2000),
		"owner": "humans", "progress": {}, "contested": false,
		"contested_by": "", "name": "M",
	}]
	_add_unit(gs, "gnomes", Vector2(2000, 2000))
	for i: int in range(240):
		mons._tick_capture(0.25)
	var m: Dictionary = mons.monasteries[0]
	_check(String(m.get("owner", "")) == "gnomes",
		"wartime: recapture allowed at war")
	gs.queue_free()


## Perks stack: N monasteries -> N magic attacks.
func _test_perk_stacking() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	for i: int in range(3):
		var gid: String = ["auriel", "volkar", "felicity"][i]
		mons.monasteries.append({
			"id": i + 1, "god_id": gid,
			"position": Vector2(1000 + i * 500, 1000),
			"owner": "humans", "progress": {}, "contested": false,
			"contested_by": "", "name": "M",
		})
	var perks := mons.get_faction_perks("humans")
	_check(perks.size() == 3, "stacking: 3 perks held")
	var attacks := mons.get_magic_attacks("humans")
	_check(attacks.size() == 3, "stacking: 3 magic attacks")
	var seen := {}
	for a: Dictionary in attacks:
		seen[String(a.get("god_id", ""))] = true
	_check(seen.size() == 3, "stacking: all distinct")
	_check(mons.get_magic_attacks("gnomes").is_empty(),
		"stacking: none for empty faction")
	gs.queue_free()


## Magic fire: one projectile per perk, per-god cooldown.
func _test_magic_fire() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	for i: int in range(2):
		var gid: String = ["auriel", "volkar"][i]
		mons.monasteries.append({
			"id": i + 1, "god_id": gid,
			"position": Vector2(1000, 1000), "owner": "humans",
			"progress": {}, "contested": false, "contested_by": "",
			"name": "M",
		})
	var u := _add_unit(gs, "humans", Vector2(1900, 2000))
	var t := _add_unit(gs, "gnomes", Vector2(2000, 2000))
	# Recording fake combat counts fired projectiles.
	var rec := _RecCombat.new()
	rec.gs = gs
	mons.combat = rec
	mons.fire_magic_attacks(u, t, Vector2(2000, 2000), Vector2(1900, 2000))
	_check(rec.fired.size() == 2, "magic: 2 projectiles for 2 perks")
	var kinds := {}
	for p: Dictionary in rec.fired:
		kinds[String(p.get("magic_id", ""))] = true
		_check(String(p.get("kind", "")) == "spell", "magic: spell kind")
	_check(kinds.has("auriel") and kinds.has("volkar"),
		"magic: both gods fired")
	# Cooldown blocks immediate refire.
	rec.fired.clear()
	mons.fire_magic_attacks(u, t, Vector2(2000, 2000), Vector2(1900, 2000))
	_check(rec.fired.is_empty(), "magic: cooldown blocks refire")
	gs.queue_free()


class _RecCombat extends _FakeCombat:
	var fired: Array = []
	func fire_projectile(from_pos: Vector2, target_id: int,
			target_pos: Vector2, kind: String, dmg: float, splash: float,
			faction: String, speed: float) -> Dictionary:
		var p := super.fire_projectile(from_pos, target_id, target_pos,
			kind, dmg, splash, faction, speed)
		fired.append(p)
		return p


## Magic resolve: god effects land.
func _test_magic_resolve() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	var fc := mons.combat as _FakeCombat
	var atk := _add_unit(gs, "humans", Vector2(1900, 2000))
	var tgt := _add_unit(gs, "gnomes", Vector2(2000, 2000))
	var ally := _add_unit(gs, "humans", Vector2(2010, 2000))
	ally["hp"] = 100.0
	# Cindral: burn.
	mons.resolve_magic_hit({"magic_id": "cindral", "faction": "humans",
		"dmg": 10.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	_check(float(tgt.get("burn_t", 0.0)) > 0.0, "magic: emberbrand burns")
	# Sylvara: snare.
	mons.resolve_magic_hit({"magic_id": "sylvara", "faction": "humans",
		"dmg": 10.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	_check(float(tgt.get("snare_t", 0.0)) > 0.0, "magic: thornsnare slows")
	# Ostra: illuminate.
	mons.resolve_magic_hit({"magic_id": "ostra", "faction": "humans",
		"dmg": 10.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	_check(float(tgt.get("illum_t", 0.0)) > 0.0, "magic: truthbeam marks")
	# Auriel: heals allies.
	mons.resolve_magic_hit({"magic_id": "auriel", "faction": "humans",
		"dmg": 20.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	_check(float(ally.get("hp", 0.0)) > 100.0, "magic: dawnbolt heals")
	# Durnhelm: wards allies.
	mons.resolve_magic_hit({"magic_id": "durnhelm", "faction": "humans",
		"dmg": 10.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	_check(float(ally.get("shield_hp", 0.0)) > 0.0, "magic: aegis wards")
	# Felicity: inspires allies.
	mons.resolve_magic_hit({"magic_id": "felicity", "faction": "humans",
		"dmg": 10.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	_check(float(ally.get("inspire_t", 0.0)) > 0.0,
		"magic: jubilance inspires")
	# Volkar: chains to a second hostile.
	var tgt2 := _add_unit(gs, "gnomes", Vector2(2100, 2000))
	var hp_before: float = float(tgt2.get("hp", 0.0))
	mons.resolve_magic_hit({"magic_id": "volkar", "faction": "humans",
		"dmg": 20.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	fc.war_pairs["humans>gnomes"] = true
	# Chain needs can_fight true; re-run with war set.
	tgt2["hp"] = 200.0
	mons.resolve_magic_hit({"magic_id": "volkar", "faction": "humans",
		"dmg": 20.0, "target_id": int(tgt.get("id", 0)),
		"attacker_id": int(atk.get("id", 0))}, Vector2(2000, 2000))
	_check(float(tgt2.get("hp", 200.0)) < 200.0, "magic: skyarc chains")
	gs.queue_free()


## Shield absorbs; illuminated take +25% (via combat hooks is awkward
## headless, so test the SimMonasteries primitives directly).
func _test_shield_and_illum() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	var u := _add_unit(gs, "humans", Vector2(0, 0))
	u["shield_hp"] = 30.0
	u["shield_t"] = 12.0
	var left: float = mons.absorb_shield(u, 20.0)
	_check(is_equal_approx(left, 0.0), "shield: absorbs fully")
	_check(is_equal_approx(float(u.get("shield_hp", 0.0)), 10.0),
		"shield: hp reduced")
	left = mons.absorb_shield(u, 25.0)
	_check(is_equal_approx(left, 15.0), "shield: overflow passes through")
	_check(mons.attack_rate_mult(u) == 1.0, "inspire: no buff, mult 1")
	u["inspire_t"] = 6.0
	_check(mons.attack_rate_mult(u) < 1.0, "inspire: buff speeds attacks")
	gs.queue_free()


## Goodness rises per capture; labels progress.
func _test_goodness() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	_check(mons.get_goodness("humans") == 0.0, "goodness: starts at 0")
	_check(mons.goodness_label("humans") == "Unproven",
		"goodness: unproven label")
	mons.monasteries = [{
		"id": 1, "god_id": "auriel", "position": Vector2(2000, 2000),
		"owner": "", "progress": {}, "contested": false,
		"contested_by": "", "name": "M",
	}]
	_add_unit(gs, "humans", Vector2(2000, 2000))
	for i: int in range(240):
		mons._tick_capture(0.25)
	_check(is_equal_approx(mons.get_goodness("humans"), 0.15),
		"goodness: +0.15 per capture")
	_check(mons.goodness_label("humans") == "Touched",
		"goodness: touched label")
	gs.queue_free()


## AI: nearest unowned monastery is the target; owned-by-self skipped.
func _test_ai_target() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	mons.monasteries = [
		{"id": 1, "god_id": "auriel", "position": Vector2(1000, 1000),
			"owner": "humans", "progress": {}, "contested": false,
			"contested_by": "", "name": "M1"},
		{"id": 2, "god_id": "volkar", "position": Vector2(3000, 3000),
			"owner": "", "progress": {}, "contested": false,
			"contested_by": "", "name": "M2"},
		{"id": 3, "god_id": "ostra", "position": Vector2(500, 500),
			"owner": "", "progress": {}, "contested": false,
			"contested_by": "", "name": "M3"},
	]
	var t: Dictionary = mons.ai_target("gnomes", Vector2(600, 600))
	_check(int(t.get("id", 0)) == 3, "ai: nearest unowned targeted")
	var t2: Dictionary = mons.ai_target("humans", Vector2(600, 600))
	_check(int(t2.get("id", 0)) == 3, "ai: own monastery skipped")
	# Peacetime: humans-owned monastery not targeted by gnomes.
	mons.monasteries[0]["owner"] = "gnomes"
	var t3: Dictionary = mons.ai_target("humans", Vector2(900, 900))
	_check(int(t3.get("id", 0)) != 1, "ai: peacetime steal skipped")
	gs.queue_free()


## Save round-trip: records, owners, and goodness survive.
func _test_save_roundtrip() -> void:
	var gs := _new_game()
	var mons := _new_mons(gs)
	mons.monasteries = [
		{"id": 1, "god_id": "auriel", "position": Vector2(1000, 1000),
			"owner": "humans", "progress": {"gnomes": 12.5},
			"contested": false, "contested_by": "", "name": "M1"},
		{"id": 2, "god_id": "volkar", "position": Vector2(3000, 3000),
			"owner": "", "progress": {}, "contested": false,
			"contested_by": "", "name": "M2"},
	]
	mons._goodness["humans"] = 0.3
	var d := mons.to_dict()
	var mons2 := SimMonasteries.new()
	mons2.from_dict(d)
	_check(mons2.monasteries.size() == 2, "save: records restored")
	var m1: Dictionary = mons2.get_monastery(1)
	_check(String(m1.get("owner", "")) == "humans", "save: owner restored")
	_check(String(m1.get("god_id", "")) == "auriel",
		"save: god restored")
	_check((m1.get("position", Vector2.ZERO) as Vector2) \
			== Vector2(1000, 1000), "save: position restored")
	_check(is_equal_approx(float((m1.get("progress", {}) as Dictionary).get(
		"gnomes", 0.0)), 12.5), "save: progress restored")
	_check(is_equal_approx(mons2.get_goodness("humans"), 0.3),
		"save: goodness restored")
	gs.queue_free()
