extends SceneTree
## Cursing Gnomes — Brax the Karaoke Barbarian tests.
##
## Wake rapid-iteration 2026-10-08: new joke disaster. A loinclothed
## barbarian storms the town hall with a lute and performs a 3-set
## power-ballad set list. 0 dmg — the weapon is his voice: citizens in
## earshot gain secondhand-embarrassment stress, a few join as backup
## singers (mood up, dignity down). A soldier closing in boos him off
## stage; when all 47 verses are sung he takes a bow and leaves.
## Singleton (spawn() gate).
##
## Covers:
##   - spawn singleton: spawns as monster faction, second refused
##   - label "Brax the Karaoke Barbarian", signature sting karaoke_arrive
##   - live spawn emits karaoke_arrive, not boom
##   - first tick picks a stage (karaoke_center) and announces
##   - performance aura: stress for citizens in earshot, none out of range
##   - singalong: some citizens convert to backup singers (happy nudge)
##   - soldier closing in boos him off stage (leaving + booed flag)
##   - set list completion triggers the encore departure
##   - budget expiry flips him to leaving
##   - departed stories: encore bow line, slain no-crash, booed no-dup
##   - art: registered as monster job, bespoke chibi sprite resolves
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_karaoke_barbarian.gd
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


func _add_citizen(gs: GameState, pos: Vector2, job: String = "worker") -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"age": 0.0, "gender": "m",
	})
	return u


func _initialize() -> void:
	print("=== Cursing Gnomes Karaoke Barbarian tests ===")
	_test_spawn_singleton()
	_test_label_and_stinger()
	_test_live_spawn_stinger()
	_test_stage_pick_and_announce()
	_test_aura_stress()
	_test_singalong()
	_test_soldier_boo()
	_test_encore_departure()
	_test_budget_leaving()
	_test_departed_stories()
	_test_art()
	_test_sprite_transparency()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_spawn_singleton() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("karaoke_barbarian", Vector2(60, 2000))
	_check("karaoke spawns", not u.is_empty())
	_check("karaoke is monster faction",
		String(u.get("faction", "")) == "monster")
	_check("karaoke deals zero damage", float(u.get("dmg", -1.0)) == 0.0)
	var u2: Dictionary = d.spawn("karaoke_barbarian", Vector2(60, 2100))
	_check("karaoke singleton: second spawn refused", u2.is_empty())
	gs.queue_free()


func _test_label_and_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_check("label is Brax the Karaoke Barbarian",
		d._label_for("karaoke_barbarian") == "Brax the Karaoke Barbarian")
	_check("stinger is karaoke_arrive",
		DisasterSim.stinger_for_kind("karaoke_barbarian") == "karaoke_arrive")
	gs.queue_free()


func _test_live_spawn_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	d.spawn("karaoke_barbarian", Vector2(60, 2000))
	_check("arrival emits karaoke_arrive, not boom",
		_sfx_seen.has("karaoke_arrive") and not _sfx_seen.has("boom"))
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()


func _test_stage_pick_and_announce() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("karaoke_barbarian", Vector2(60, 2000))
	_check("no stage before first tick", not u.has("karaoke_center"))
	d._tick_karaoke(u, 80.0, 0.1)
	_check("first tick picks a stage", u.has("karaoke_center"))
	_check("announce flag set", bool(u.get("karaoke_announced", false)))
	gs.queue_free()


func _test_aura_stress() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("karaoke_barbarian", Vector2(1000, 1000))
	u["karaoke_center"] = Vector2(1000, 1000)
	u["position"] = Vector2(1000, 1000)
	var near: Dictionary = _add_citizen(gs, Vector2(1000, 1000))
	var far: Dictionary = _add_citizen(gs, Vector2(3000, 3000))
	seed(20261008)
	d._tick_karaoke(u, 80.0, 2.0)
	_check("citizen in earshot gains stress",
		float(near.get("stress", 0.0)) > 0.0)
	_check("citizen out of range gains no stress",
		float(far.get("stress", 0.0)) == 0.0)
	gs.queue_free()


func _test_singalong() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("karaoke_barbarian", Vector2(1000, 1000))
	u["karaoke_center"] = Vector2(1000, 1000)
	u["position"] = Vector2(1000, 1000)
	seed(20261008)
	for i in 60:
		_add_citizen(gs, Vector2(1000 + i, 1000))
	for i in 5:
		d._karaoke_aura(u, Vector2(1000, 1000), 2.0)
	var singers: int = int(u.get("karaoke_singers", 0))
	_check("some citizens join as backup singers", singers > 0)
	var found_happy := false
	for x: Dictionary in gs.units:
		if bool(x.get("karaoke_singer", false)):
			found_happy = true
			break
	_check("singer flag stamped on citizens", found_happy)
	gs.queue_free()


func _test_soldier_boo() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("karaoke_barbarian", Vector2(1000, 1000))
	u["karaoke_center"] = Vector2(1000, 1000)
	u["position"] = Vector2(1000, 1000)
	_add_citizen(gs, Vector2(1050, 1000), "soldier")
	_said.clear()
	gs.bus.unit_said.connect(_on_said)
	d._tick_karaoke(u, 80.0, 0.1)
	_check("soldier closing in boos Brax off stage",
		bool(u.get("leaving", false)) and bool(u.get("karaoke_booed", false)))
	_check("booed story announces once",
		bool(u.get("karaoke_booed_story", false)))
	gs.bus.unit_said.disconnect(_on_said)
	gs.queue_free()


func _test_encore_departure() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("karaoke_barbarian", Vector2(1000, 1000))
	u["karaoke_center"] = Vector2(1000, 1000)
	u["position"] = Vector2(1000, 1000)
	u["karaoke_sets_done"] = 2
	u["karaoke_set_cd"] = 0.5
	d._tick_karaoke(u, 80.0, 1.0)
	_check("finished set list triggers encore departure",
		bool(u.get("leaving", false)) and bool(u.get("karaoke_encore", false)))
	gs.queue_free()


func _test_budget_leaving() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var t: Dictionary = d.spawn("karaoke_barbarian", Vector2(60, 2000))
	t["age"] = 9999.0  # budget spent
	d._tick_monster(t, "karaoke_barbarian", 0.1)
	_check("budget expiry flips Brax to leaving",
		bool(t.get("leaving", false)))
	gs.queue_free()


func _test_departed_stories() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	# Encore path: alive + leaving + encore -> bow line, done story.
	var t: Dictionary = d.spawn("karaoke_barbarian", Vector2(60, 2000))
	t["karaoke_encore"] = true
	t["karaoke_singers"] = 3
	_said.clear()
	gs.bus.unit_said.connect(_on_said)
	d._karaoke_departed(t)
	_check("encore departure takes a bow",
		_said.has("THANK YOU, GOODNIGHT! You've been a CAPTIVE audience!"))
	_check("encore files done story", bool(t.get("karaoke_done_story", false)))
	gs.bus.unit_said.disconnect(_on_said)
	gs.queue_free()
	# Booed path: no duplicate story on departure.
	var w2: Array = _new_world()
	var gs2: GameState = w2[0]
	var d2: DisasterSim = w2[2]
	var t3: Dictionary = d2.spawn("karaoke_barbarian", Vector2(60, 2000))
	t3["karaoke_booed"] = true
	t3["karaoke_booed_story"] = true
	d2._karaoke_departed(t3)
	_check("booed departure files no second story",
		not bool(t3.get("karaoke_done_story", false)))
	# Slain path: no crash, slain story filed.
	t3["alive"] = false
	d2._karaoke_departed(t3)
	_check("slain files slain story",
		bool(t3.get("karaoke_slain_story", false)))
	gs2.queue_free()


func _test_art() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(4242, "gnomes", "karaoke_barbarian", Vector2(100, 100), "m")
	_check("karaoke job registered as monster",
		"karaoke_barbarian" in UnitNode._MONSTER_JOBS)
	_check("karaoke resolves bespoke chibi art",
		Art.animal_texture("karaoke_barbarian") != null)
	un.queue_free()


func _test_sprite_transparency() -> void:
	# Jeremy 2026-10-08 (no white squares): Brax shipped 2026-10-08 with
	# karaoke_barbarian.png fully opaque (1600x1600 RGB, no alpha) — he
	# rendered inside a white rectangle. Border-flood-to-transparent sweep
	# (1,379,614 px, 53.9%) must hold: corners transparent, enclosed
	# whites (mouth teeth, lute-string gaps) preserved, art unshifted.
	var img := Image.load_from_file(
		"res://assets/art/animals/karaoke_barbarian.png")
	_check("karaoke: sprite loads", img != null)
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	_check("karaoke: sprite is 1600x1600", w == 1600 and h == 1600)
	var corners_clear := true
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0),
			Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		if img.get_pixel(c.x, c.y).a > 0.01:
			corners_clear = false
	_check("karaoke: sprite corners transparent (no white box)",
		corners_clear)
	# No opaque pixels on any image edge (background fully flooded out).
	var edge_opaque := 0
	for x in range(w):
		if img.get_pixel(x, 0).a > 0.04:
			edge_opaque += 1
		if img.get_pixel(x, h - 1).a > 0.04:
			edge_opaque += 1
	for y in range(h):
		if img.get_pixel(0, y).a > 0.04:
			edge_opaque += 1
		if img.get_pixel(w - 1, y).a > 0.04:
			edge_opaque += 1
	_check("karaoke: no opaque pixels on image edges", edge_opaque == 0)
	# Enclosed whites preserved: teeth inside the open mouth and other
	# near-white details must survive the flood (they are not background).
	var white_px := 0
	for y in range(0, h, 7):
		for x in range(0, w, 7):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.8 and p.r >= 0.92 and p.g >= 0.92 and p.b >= 0.92:
				white_px += 1
	_check("karaoke: enclosed whites preserved (teeth/details intact)",
		white_px > 10)
	# The sprite must carry real alpha now (was an opaque RGB export).
	var has_alpha := false
	for y in range(0, h, 13):
		for x in range(0, w, 13):
			if img.get_pixel(x, y).a < 0.5:
				has_alpha = true
				break
		if has_alpha:
			break
	_check("karaoke: sprite has transparent regions (alpha channel)",
		has_alpha)
