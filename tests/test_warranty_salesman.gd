extends SceneTree
## Cursing Gnomes — Wally the Warranty Salesman disaster tests (wake
## rapid-iteration 2026-10-08: warranty_salesman).
##
## Covers: spawn + singleton rule, label + stinger, arrival sfx emits
## warranty_arrive (not boom), nearest-building targeting (door to door),
## pitch flow (walks into range, pitches, resolves), sale mechanics (35%
## chance, -30 gold clamped at 0, buyer flagged, counter), no-sale path,
## soldier flee (warranty_fled + fled story), slain + budget departed
## stories, bespoke art resolves + transparency, monster-job art mapping,
## stinger segments synthesize.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_warranty_salesman.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sfx_seen: Array[String] = []
var _said: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Warranty Salesman tests ===")
	_test_spawn_singleton()
	_test_label_and_stinger()
	_test_live_spawn_stinger()
	_test_targets_nearest_building()
	_test_pitch_flow_and_sale()
	_test_sale_clamps_at_zero()
	_test_flees_from_soldiers()
	_test_departed_stories()
	_test_art()
	_test_stinger_synthesizes()
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


func _add_building(gs: GameState, bid: int, pos: Vector2,
		faction: String = "humans") -> void:
	gs.buildings.append({"id": bid, "type": "house", "faction": faction,
		"town_id": 1, "position": pos, "alive": true, "complete": true})


func _add_citizen(gs: GameState, pos: Vector2, job: String = "worker") -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"display_name": "Testy McTest",
	})
	return u


func _on_sfx(kind: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(kind)


func _on_said(unit_id: int, text: String) -> void:
	_said.append(text)


func _test_spawn_singleton() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	var u: Dictionary = d.spawn("warranty_salesman", Vector2(60, 2000))
	_check("wally spawns", not u.is_empty())
	_check("wally is monster faction",
		String(u.get("faction", "")) == "monster")
	_check("wally deals zero damage", float(u.get("dmg", -1.0)) == 0.0)
	var u2: Dictionary = d.spawn("warranty_salesman", Vector2(60, 2100))
	_check("wally singleton: second spawn refused", u2.is_empty())
	gs.queue_free()


func _test_label_and_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_check("label is Wally the Warranty Salesman",
		d._label_for("warranty_salesman") == "Wally the Warranty Salesman")
	_check("stinger is warranty_arrive",
		DisasterSim.stinger_for_kind("warranty_salesman") == "warranty_arrive")
	gs.queue_free()


func _test_live_spawn_stinger() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	d.spawn("warranty_salesman", Vector2(60, 2000))
	_check("arrival emits warranty_arrive, not boom",
		_sfx_seen.has("warranty_arrive") and not _sfx_seen.has("boom"))
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()


func _test_targets_nearest_building() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	# Far building added FIRST (insertion order must not win); near one
	# second. Wally works door to door: nearest wins.
	_add_building(gs, 1, Vector2(3500, 3500))
	_add_building(gs, 2, Vector2(200, 200))
	var u: Dictionary = d.spawn("warranty_salesman", Vector2(100, 100))
	d._tick_warranty(u, 85.0, 0.2)  # first tick: pick target + announce
	var target: Vector2 = u.get("warranty_target_pos", Vector2(-1, -1))
	_check("wally targets nearest building",
		target.distance_to(Vector2(200, 200)) < 1.0)
	_check("wally arrival story announced",
		bool(u.get("warranty_announced", false)))
	gs.queue_free()


func _test_pitch_flow_and_sale() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_add_building(gs, 1, Vector2(500, 500))
	var buyer: Dictionary = _add_citizen(gs, Vector2(510, 510))
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	var u: Dictionary = d.spawn("warranty_salesman", Vector2(500, 500))
	u["position"] = Vector2(500, 500)  # already in pitch range
	_said.clear()
	gs.bus.unit_said.connect(_on_said)
	# Walk the pitch down deterministically.
	u["warranty_target_pos"] = Vector2(500, 500)
	u["warranty_pitch_left"] = 0.05
	u["warranty_shout_cd"] = 999.0  # keep shouts out of this test
	seed(20261008)
	d._tick_warranty(u, 85.0, 0.2)  # resolves the pitch
	_check("pitch resolves and picks next target",
		u.has("warranty_target_pos"))
	_check("wally pitched out loud", not _said.is_empty())
	var sales: int = int(u.get("warranty_sales", 0))
	var gold_after: float = gs.resources.get_amount("humans", "gold")
	if sales > 0:
		_check("sale deducts exactly 30 gold",
			absf((gold_before - gold_after) - 30.0) < 0.001)
		_check("buyer flagged as scammed",
			bool(buyer.get("warranty_scammed", false)))
	else:
		_check("no-sale leaves gold untouched",
			absf(gold_before - gold_after) < 0.001)
	# Invariant over many pitches: gold lost == sales * 30, never negative.
	seed(7)
	var s0: int = int(u.get("warranty_sales", 0))
	var g0: float = gs.resources.get_amount("humans", "gold")
	for i in 20:
		u["warranty_target_pos"] = Vector2(500, 500)
		d._warranty_resolve_pitch(u)
	var s1: int = int(u.get("warranty_sales", 0))
	var g1: float = gs.resources.get_amount("humans", "gold")
	_check("20 pitches: gold lost == sales * 30",
		absf((g0 - g1) - float(s1 - s0) * 30.0) < 0.001)
	_check("gold never goes negative", g1 >= 0.0)
	gs.bus.unit_said.disconnect(_on_said)
	gs.queue_free()


func _test_sale_clamps_at_zero() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_add_building(gs, 1, Vector2(500, 500))
	_add_citizen(gs, Vector2(510, 510))
	# Broke faction: 5 gold. A sale must clamp at 0, not go negative.
	gs.resources.add_resource("humans", "gold", 5.0, true)
	var u: Dictionary = d.spawn("warranty_salesman", Vector2(500, 500))
	u["warranty_target_pos"] = Vector2(500, 500)
	seed(99)
	for i in 30:
		d._warranty_resolve_pitch(u)
	var g: float = gs.resources.get_amount("humans", "gold")
	_check("broke faction never goes negative on sales", g >= 0.0)
	gs.queue_free()


func _test_flees_from_soldiers() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	_add_building(gs, 1, Vector2(500, 500))
	_add_citizen(gs, Vector2(510, 510), "soldier")
	var u: Dictionary = d.spawn("warranty_salesman", Vector2(500, 500))
	u["position"] = Vector2(500, 500)
	_said.clear()
	gs.bus.unit_said.connect(_on_said)
	d._tick_warranty(u, 85.0, 0.2)
	_check("soldier routes wally", bool(u.get("warranty_fled", false)))
	_check("wally fled story announced",
		bool(u.get("warranty_fled_story", false)))
	_check("wally withdraws the offer out loud",
		_said.has("FINE! No warranty for YOU! You'll be SORRY!"))
	gs.bus.unit_said.disconnect(_on_said)
	gs.queue_free()


func _test_departed_stories() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var d: DisasterSim = w[2]
	# Slain.
	var u: Dictionary = d.spawn("warranty_salesman", Vector2(60, 2000))
	u["alive"] = false
	u["warranty_sales"] = 3
	d._warranty_departed(u)
	_check("slain story announced",
		bool(u.get("warranty_slain_story", false)))
	# Budget expiry (alive, not fled).
	var u2: Dictionary = {"alive": true, "warranty_sales": 2,
		"id": 4242}
	d._warranty_departed(u2)
	_check("budget story announced",
		bool(u2.get("warranty_left_story", false)))
	# Fled: story already filed at flee time, departed stays quiet.
	var u3: Dictionary = {"alive": true, "warranty_fled": true, "id": 4243}
	d._warranty_departed(u3)
	_check("fled files no second story",
		not bool(u3.get("warranty_left_story", false)))
	gs.queue_free()


func _test_art() -> void:
	var w: Array = _new_world()
	var gs: GameState = w[0]
	var tex: Texture2D = Art.animal_texture("warranty_salesman")
	_check("warranty salesman art resolves", tex != null)
	if tex != null:
		_check("art is RGBA 1600x1600",
			tex.get_size() == Vector2(1600, 1600))
		var img: Image = tex.get_image()
		_check("corners are transparent",
			img.get_pixel(0, 0).a < 0.05 \
			and img.get_pixel(1599, 0).a < 0.05 \
			and img.get_pixel(0, 1599).a < 0.05 \
			and img.get_pixel(1599, 1599).a < 0.05)
		# Interior must have real pixels (not a blank/white square).
		var opaque := 0
		for y in range(700, 900, 10):
			for x in range(700, 900, 10):
				if img.get_pixel(x, y).a > 0.5:
					opaque += 1
		_check("sprite interior has painted pixels", opaque > 50)
	gs.queue_free()


func _test_stinger_synthesizes() -> void:
	# The stinger arm must synthesize without errors (no undocumented
	# segment params — the gossip run's first draft tripped on this).
	var am = load("res://scripts/audio/audio_manager.gd").new()
	var segs: Array = am._disaster_stinger_segments("warranty_arrive")
	_check("warranty_arrive has segments", not segs.is_empty())
	var ok := true
	for s: Dictionary in segs:
		if not s.has("kind") or not s.has("dur") or not s.has("vol"):
			ok = false
	_check("all segments have kind/dur/vol", ok)
	var stream: AudioStreamWAV = am._synthesize_sfx("warranty_arrive")
	_check("stinger synthesizes to a stream", stream != null)
	if stream != null:
		_check("stream has samples", stream.get_length() > 0.2)
	am.queue_free()
