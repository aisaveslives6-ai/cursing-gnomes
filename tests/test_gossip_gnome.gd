extends SceneTree
## Cursing Gnomes — Yapper the Gossip Gnome disaster tests (wake
## rapid-iteration 2026-10-08: gossip_gnome).
##
## Covers: spawn + singleton rule, label + stinger, arrival sfx emits
## gossip_arrive (not boom), most-populous-town targeting (NOT nearest),
## rumor seeding goes through the REAL hearsay mill (kind "gossip",
## subject gossip:<vid>, heat 0.65, knower = victim, truth unknown),
## rumor cooldown/counter, indoor citizens exempt, soldier flee
## (gossip_fled + fled story), slain + budget departed stories,
## bespoke art resolves + white-box sweep holds, monster-job art mapping.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gossip_gnome.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sfx_seen: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Gossip Gnome tests ===")
	_test_spawn_singleton()
	_test_label_and_stinger()
	_test_live_spawn_stinger()
	_test_targets_most_populous_town()
	_test_seeds_real_hearsay_rumor()
	_test_indoor_citizens_exempt()
	_test_flees_from_soldiers()
	_test_departed_stories()
	_test_art()
	_test_sprite_transparency()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves", "ogres", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	return [gs, combat, d]


func _add_town(gs: GameState, tid: int, pos: Vector2, tname: String) -> void:
	gs.towns[tid] = {"id": tid, "faction": "humans", "name": tname,
		"position": pos}


func _add_citizen(gs: GameState, tid: int, pos: Vector2,
		job: String = "worker", indoor: bool = false) -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": "humans", "job": job, "town_id": tid,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"display_name": "Testy McTest", "inside_building_id": 5 if indoor else 0,
	})
	return u


func _new_hearsay_world() -> Array:
	# gossip seeding needs a live rumor mill: phone_sys.hearsay.
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return [gs, w[1], w[2], phone.hearsay]


func _on_sfx(kind: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(kind)


func _test_spawn_singleton() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("gossip_gnome", Vector2(60, 2000))
	_check("gossip spawns", not u.is_empty())
	_check("gossip is monster faction",
		String(u.get("faction", "")) == "monster")
	_check("gossip deals zero damage", float(u.get("dmg", -1.0)) == 0.0)
	var u2: Dictionary = d.spawn("gossip_gnome", Vector2(60, 2100))
	_check("gossip singleton: second spawn refused", u2.is_empty())
	gs.queue_free()


func _test_label_and_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_check("label is Yapper the Gossip Gnome",
		d._label_for("gossip_gnome") == "Yapper the Gossip Gnome")
	_check("stinger is gossip_arrive",
		DisasterSim.stinger_for_kind("gossip_gnome") == "gossip_arrive")
	gs.queue_free()


func _test_live_spawn_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	d.spawn("gossip_gnome", Vector2(60, 2000))
	_check("arrival emits gossip_arrive, not boom",
		_sfx_seen.has("gossip_arrive") and not _sfx_seen.has("boom"))
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()


func _test_targets_most_populous_town() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	# Town 1 is NEAR the spawn but tiny (1 citizen); town 2 is FAR but
	# populous (6 citizens). Yapper must pick town 2.
	_add_town(gs, 1, Vector2(300, 300), "Nearville")
	_add_town(gs, 2, Vector2(3800, 3800), "Farburg")
	_add_citizen(gs, 1, Vector2(310, 310))
	for i in 6:
		_add_citizen(gs, 2, Vector2(3800 + i * 8, 3800))
	var u: Dictionary = d.spawn("gossip_gnome", Vector2(100, 100))
	d._tick_gossip(u, 90.0, 0.2)  # first tick: pick town + announce
	var target: Vector2 = u.get("gossip_target", Vector2(-1, -1))
	_check("gossip targets most populous town (Farburg)",
		target.distance_to(Vector2(3800, 3800)) < 1.0)
	_check("gossip arrival story announced",
		bool(u.get("gossip_announced", false)))
	gs.queue_free()


func _test_seeds_real_hearsay_rumor() -> void:
	var w: Array = _new_hearsay_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var hearsay = w[3]
	_add_town(gs, 1, Vector2(500, 500), "T1")
	var v: Dictionary = _add_citizen(gs, 1, Vector2(520, 520))
	var u: Dictionary = d.spawn("gossip_gnome", Vector2(500, 500))
	u["position"] = Vector2(500, 500)
	d._tick_gossip(u, 90.0, 0.2)  # pick town + seed first rumor
	var rumors: Array = hearsay.state["rumors"]
	var mine: Dictionary = {}
	for r: Dictionary in rumors:
		if String(r.get("subject", "")) == "gossip:%d" % int(v.get("id", -1)):
			mine = r
	_check("gossip seeds a real hearsay rumor", not mine.is_empty())
	if mine.is_empty():
		gs.queue_free()
		return
	_check("rumor kind is gossip", String(mine.get("kind", "")) == "gossip")
	_check("rumor heat 0.65", absf(float(mine.get("heat", 0.0)) - 0.65) < 0.001)
	_check("rumor truth unknown",
		String(mine.get("truth", "")) == SimHearsay.TRUTH_UNKNOWN)
	_check("victim is a knower",
		(mine.get("knowers", []) as Array).has(int(v.get("id", -1))))
	_check("rumor names the victim",
		String(mine.get("text", "")).find("Testy McTest") >= 0)
	_check("rumor counter incremented", int(u.get("gossip_rumors", 0)) == 1)
	# Cooldown: next tick does not double-seed.
	var before: int = rumors.size()
	d._tick_gossip(u, 90.0, 0.2)
	_check("rumor cooldown respected",
		(hearsay.state["rumors"] as Array).size() == before)
	gs.queue_free()


func _test_indoor_citizens_exempt() -> void:
	var w: Array = _new_hearsay_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var hearsay = w[3]
	_add_town(gs, 1, Vector2(500, 500), "T1")
	var v: Dictionary = _add_citizen(gs, 1, Vector2(520, 520), "worker", true)
	var u: Dictionary = d.spawn("gossip_gnome", Vector2(500, 500))
	u["position"] = Vector2(500, 500)
	d._tick_gossip(u, 90.0, 0.2)
	var found := false
	for r: Dictionary in hearsay.state["rumors"]:
		if String(r.get("subject", "")) == "gossip:%d" % int(v.get("id", -1)):
			found = true
	_check("indoor citizens keep their secrets", not found)
	gs.queue_free()


func _test_flees_from_soldiers() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_add_town(gs, 1, Vector2(500, 500), "T1")
	_add_citizen(gs, 1, Vector2(520, 520))
	var u: Dictionary = d.spawn("gossip_gnome", Vector2(500, 500))
	u["position"] = Vector2(500, 500)
	d._tick_gossip(u, 90.0, 0.2)
	# No soldiers: keeps yapping.
	_check("no flee without soldiers", not bool(u.get("gossip_fled", false)))
	# A soldier closes in: routed.
	var s: Dictionary = gs.add_unit({
		"faction": "humans", "job": "soldier", "town_id": 1,
		"position": Vector2(560, 560), "alive": true,
		"hp": 100.0, "max_hp": 100.0,
	})
	d._tick_gossip(u, 90.0, 0.2)
	_check("soldier routs the gossip", bool(u.get("gossip_fled", false)))
	_check("fled story filed", bool(u.get("gossip_fled_story", false)))
	s["alive"] = false
	gs.queue_free()


func _test_departed_stories() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	# Slain path.
	var u: Dictionary = d.spawn("gossip_gnome", Vector2(500, 500))
	u["alive"] = false
	u["gossip_rumors"] = 3
	d._gossip_departed(u)
	_check("slain story filed", bool(u.get("gossip_slain_story", false)))
	# Budget path: alive, not fled.
	var u2: Dictionary = d.spawn("gossip_gnome", Vector2(600, 600))
	u2["gossip_rumors"] = 2
	d._gossip_departed(u2)
	_check("budget story filed", bool(u2.get("gossip_left_story", false)))
	gs.queue_free()


func _test_art() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(4242, "gnomes", "gossip_gnome", Vector2(100, 100), "m")
	_check("gossip job registered as monster",
		"gossip_gnome" in UnitNode._MONSTER_JOBS)
	_check("gossip resolves bespoke chibi art",
		Art.animal_texture("gossip_gnome") != null)
	un.queue_free()


func _test_sprite_transparency() -> void:
	# Jeremy 2026-10-08 (no white squares): the gossip sprite must ship
	# border-flood swept — corners transparent, no white rectangle.
	var img := Image.load_from_file(
		"res://assets/art/animals/gossip_gnome.png")
	_check("gossip: sprite loads", img != null)
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	_check("gossip: sprite is 1600x1600", w == 1600 and h == 1600)
	var corners_clear := true
	for p in [Vector2i(2, 2), Vector2i(w - 3, 2),
			Vector2i(2, h - 3), Vector2i(w - 3, h - 3)]:
		if img.get_pixel(p.x, p.y).a > 0.01:
			corners_clear = false
	_check("gossip: corners transparent (white-box swept)", corners_clear)
