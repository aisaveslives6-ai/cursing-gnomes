extends SceneTree
## Cursing Gnomes — Twister Sister disaster tests.
##
## Wake rapid-iteration 2026-10-08: a sentient glam-metal tornado joins
## the joke-disaster roster. She wanders town to town; her fling aura
## (130px, 2Hz) hurls citizens to random spots 220-380px away (10 dmg +
## 25s fling immunity — no chain-flinging), and buildings in her path
## take roof damage over time. Indoor citizens (inside_building_id > 0)
## are exempt. Singleton; budget expiry -> leaving -> Gazette story.
##
## Covers:
##   - spawn returns a unit; second spawn is refused (singleton)
##   - _label_for -> "Twister Sister"; stinger_for_kind -> "twister_arrive"
##   - live spawn emits "twister_arrive" (not "boom") on sfx_spatial
##   - fling: citizen in aura is displaced 220-380px, takes 10 dmg,
##     gains 25s immunity
##   - indoor citizens are NOT flung; monsters are NOT flung
##   - immunity decrements on aura ticks; immune citizens are NOT flung
##   - buildings in aura take roof damage over time
##   - budget expiry flips the twister to leaving
##   - departed story fires for the budget path (alive + leaving)
##   - art: _monster_texture resolves real art; scale pinned at 2.0x;
##     job registered in _MONSTER_JOBS
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_twister_sister.gd
##
## Exit code 0 = all passed, 1 = any failure.


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


var _sfx_seen: Array = []
var _said: Array = []


func _on_sfx(sfx_name: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(sfx_name)


func _on_said(_uid: int, line: String) -> void:
	_said.append(line)


func _new_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves", "ogres", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	return [gs, combat, d]


func _add_citizen(gs: GameState, pos: Vector2, indoor: bool = false) -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": "humans", "job": "worker", "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"age": 0.0, "gender": "m",
	})
	if indoor:
		u["inside_building_id"] = 7
	return u


func _add_building(gs: GameState, pos: Vector2) -> Dictionary:
	var b := {"id": 900 + int(pos.x), "type": "house", "name": "house",
		"alive": true, "complete": true, "position": pos,
		"faction": "humans", "hp": 200.0, "max_hp": 200.0}
	gs.buildings.append(b)
	return b


func _initialize() -> void:
	print("=== Cursing Gnomes Twister Sister tests ===")
	_test_spawn_singleton()
	_test_label_and_stinger()
	_test_live_spawn_stinger()
	_test_fling()
	_test_indoor_exempt()
	_test_monster_exempt()
	_test_immunity()
	_test_roof_damage()
	_test_budget_leaving()
	_test_departed_story()
	_test_art()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_spawn_singleton() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("twister_sister", Vector2(60, 2000))
	_check("twister spawns", not u.is_empty())
	_check("twister is monster faction",
		String(u.get("faction", "")) == "monster")
	var u2: Dictionary = d.spawn("twister_sister", Vector2(60, 2100))
	_check("twister singleton: second spawn refused", u2.is_empty())
	gs.queue_free()


func _test_label_and_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_check("label is Twister Sister",
		d._label_for("twister_sister") == "Twister Sister")
	_check("stinger is twister_arrive",
		DisasterSim.stinger_for_kind("twister_sister") == "twister_arrive")
	gs.queue_free()


func _test_live_spawn_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	d.spawn("twister_sister", Vector2(60, 2000))
	_check("arrival emits twister_arrive, not boom",
		_sfx_seen.has("twister_arrive") and not _sfx_seen.has("boom"))
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()


func _test_fling() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("twister_sister", Vector2(2000, 2000))
	var before := Vector2(2050, 2000)
	var c: Dictionary = _add_citizen(gs, before)
	d._tick_twister(t, 115.0, 0.6)  # fling aura fires (cd starts at 0)
	var after: Vector2 = c.get("position", before)
	var flung: float = before.distance_to(after)
	_check("citizen in aura is flung 220-380px",
		flung >= 219.0 and flung <= 381.0)
	_check("fling deals 10 dmg",
		float(c.get("hp", 100.0)) <= 90.01)
	_check("fling grants 25s immunity",
		is_equal_approx(float(c.get("twister_immune_t", 0.0)), 25.0))
	_check("twister counts the fling", int(t.get("twister_flung", 0)) == 1)
	gs.queue_free()


func _test_indoor_exempt() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("twister_sister", Vector2(2000, 2000))
	var before := Vector2(2050, 2000)
	var c: Dictionary = _add_citizen(gs, before, true)  # indoors
	d._tick_twister(t, 115.0, 0.6)
	_check("indoor citizen is NOT flung",
		c.get("position", before) == before)
	_check("indoor citizen takes no dmg",
		is_equal_approx(float(c.get("hp", 100.0)), 100.0))
	gs.queue_free()


func _test_monster_exempt() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("twister_sister", Vector2(2000, 2000))
	var m: Dictionary = gs.add_unit({
		"faction": "monster", "job": "giant_ass", "town_id": -1,
		"position": Vector2(2050, 2000), "alive": true,
		"hp": 1200.0, "max_hp": 1200.0, "age": 0.0,
	})
	d._tick_twister(t, 115.0, 0.6)
	_check("fellow monster is NOT flung",
		m.get("position", Vector2.ZERO) == Vector2(2050, 2000))
	gs.queue_free()


func _test_immunity() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("twister_sister", Vector2(2000, 2000))
	var c: Dictionary = _add_citizen(gs, Vector2(2050, 2000))
	c["twister_immune_t"] = 10.0
	d._tick_twister(t, 115.0, 0.6)
	_check("immune citizen is NOT flung",
		c.get("position", Vector2.ZERO) == Vector2(2050, 2000))
	_check("immunity decrements on aura ticks",
		float(c.get("twister_immune_t", 0.0)) < 10.0)
	gs.queue_free()


func _test_roof_damage() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("twister_sister", Vector2(2000, 2000))
	var b: Dictionary = _add_building(gs, Vector2(2050, 2000))
	var hp0: float = float(b.get("hp", 200.0))
	for i in 10:
		d._tick_twister(t, 115.0, 0.5)
	_check("building in aura takes roof damage",
		float(b.get("hp", hp0)) < hp0)
	gs.queue_free()


func _test_budget_leaving() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("twister_sister", Vector2(60, 2000))
	t["age"] = 9999.0  # budget spent
	d._tick_monster(t, "twister_sister", 0.1)
	_check("budget expiry flips twister to leaving",
		bool(t.get("leaving", false)))
	gs.queue_free()


func _test_departed_story() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("twister_sister", Vector2(60, 2000))
	t["twister_flung"] = 7
	t["twister_roofs"] = 3
	t["leaving"] = true
	_said.clear()
	gs.bus.unit_said.connect(_on_said)
	# Budget path: alive + leaving, no crash, says goodnight.
	d._twister_departed(t)
	_check("departed twister says goodnight",
		_said.has("THANK YOU, GOODNIGHT! Tip your waitress!"))
	gs.bus.unit_said.disconnect(_on_said)
	gs.queue_free()


func _test_art() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(4242, "gnomes", "twister_sister", Vector2(100, 100), "m")
	_check("twister job registered as monster",
		"twister_sister" in UnitNode._MONSTER_JOBS)
	var tex: Texture2D = un._monster_texture()
	_check("twister monster texture resolves", tex != null)
	_check("twister texture has size",
		tex != null and tex.get_width() > 0 and tex.get_height() > 0)
	_check("twister scale pinned at 2.0x",
		is_equal_approx(un._monster_scale(), UnitNode.SPRITE_WORLD_H * 2.0))
	_check("twister sprite carries monster art",
		un._sprite != null and un._sprite.texture == tex)
	un.free()
