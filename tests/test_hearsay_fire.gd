extends SceneTree
## Cursing Gnomes — hearsay wildfire tests (Jeremy 2026-10-06, hearsay
## flesh-out run).
##
## Wildfires were the weakest hearsay thread: they never emitted
## disaster_spawned (only opened a DisasterLog record), so fires raged
## with ZERO grapevine presence — no rumors, no Squabble posts, no
## witnesses. bus.fire_started now feeds the rumor mill:
##  - one ("disaster", "wildfire") rumor per outbreak (ignitions share
##    it; a spreading fire refreshes the talk instead of spamming it)
##  - one scared-flavored Squabble post per outbreak
##  - NPCs near the flames join as first-hand witnesses (heard_rumor +
##    witnessed_rumor memories, scared emotion via the disaster path)
##  - dead and far-away NPCs are excluded from witnesses
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_fire.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay-fire tests ===")
	_test_fire_seeds_rumor()
	_test_fire_squabble_post()
	_test_fire_witnesses()
	_test_outbreak_shares_rumor()
	_test_witness_memory()
	_test_save_roundtrip()
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


func _new_gs() -> GameState:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _spawn(gs: GameState, faction: String, pos: Vector2,
		alive: bool = true) -> Dictionary:
	var u: Dictionary = gs.add_unit({"faction": faction, "alive": alive})
	u["position"] = pos
	return u


func _fire_harness() -> Array:
	var gs := _new_gs()
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	var hs = phone.hearsay
	var near: Dictionary = _spawn(gs, "gnomes", Vector2(100, 100))
	var far: Dictionary = _spawn(gs, "gnomes", Vector2(5000, 5000))
	var dead: Dictionary = _spawn(gs, "gnomes", Vector2(100, 100), false)
	return [gs, phone, hs, near, far, dead]


func _ignite(gs: GameState, pos: Vector2) -> void:
	gs.bus.fire_started.emit({
		"id": 1, "position": pos, "intensity": 50.0, "radius": 90.0,
		"born": 0.0,
	})


func _wildfire_rumor(hs) -> Dictionary:
	return hs._live_rumor("disaster", "wildfire")


func _test_fire_seeds_rumor() -> void:
	var parts: Array = _fire_harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	_check("no wildfire rumor before ignition",
		_wildfire_rumor(hs).is_empty())
	_ignite(gs, Vector2(100, 100))
	var r: Dictionary = _wildfire_rumor(hs)
	_check("fire seeds a rumor", not r.is_empty())
	_check("fire rumor kind disaster", String(r.get("kind", "")) == "disaster")
	_check("fire rumor subject wildfire",
		String(r.get("subject", "")) == "wildfire")
	_check("fire rumor heat 0.85",
		absf(float(r.get("heat", 0.0)) - 0.85) < 0.001)
	_check("fire rumor truth true",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	gs.queue_free()


func _test_fire_squabble_post() -> void:
	var parts: Array = _fire_harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var before: int = (phone.state["posts"] as Array).size()
	_ignite(gs, Vector2(100, 100))
	var posts: Array = phone.state["posts"]
	_check("fire posts to Squabble", posts.size() == before + 1)
	var p: Dictionary = posts[posts.size() - 1]
	_check("fire post kind disaster", String(p.get("kind", "")) == "disaster")
	var t: String = String(p.get("text", "")).to_lower()
	_check("fire post mentions fire",
		t.contains("fire") or t.contains("flame") or t.contains("smoke"))
	gs.queue_free()


func _test_fire_witnesses() -> void:
	var parts: Array = _fire_harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	_ignite(gs, Vector2(100, 100))
	var r: Dictionary = _wildfire_rumor(hs)
	var knowers: Array = r["knowers"]
	var wits: Array = r.get("witnesses", [])
	var near_id: int = int((parts[3] as Dictionary).get("id", 0))
	var far_id: int = int((parts[4] as Dictionary).get("id", 0))
	var dead_id: int = int((parts[5] as Dictionary).get("id", 0))
	_check("near NPC hears the fire", knowers.has(near_id))
	_check("near NPC is first-hand witness", wits.has(near_id))
	_check("far NPC excluded", not knowers.has(far_id))
	_check("dead NPC excluded", not knowers.has(dead_id))
	gs.queue_free()


func _test_outbreak_shares_rumor() -> void:
	# A spreading fire ignites many times — the outbreak must share ONE
	# rumor and ONE post, refresh the heat, and still pick up new
	# witnesses near the new flames.
	var parts: Array = _fire_harness()
	var gs: GameState = parts[0]
	var phone = parts[1]
	var hs = parts[2]
	_ignite(gs, Vector2(100, 100))
	# Let the heat cool so the refresh is observable.
	var r1: Dictionary = _wildfire_rumor(hs)
	r1["heat"] = 0.5
	var posts_before: int = (phone.state["posts"] as Array).size()
	_ignite(gs, Vector2(5000, 5000))  # the fire spreads to the far unit
	var count := 0
	for r2: Dictionary in hs.state["rumors"]:
		if String(r2.get("kind", "")) == "disaster" \
				and String(r2.get("subject", "")) == "wildfire":
			count += 1
	_check("one rumor per outbreak", count == 1)
	_check("one post per outbreak",
		(phone.state["posts"] as Array).size() == posts_before)
	var r: Dictionary = _wildfire_rumor(hs)
	_check("heat refreshed by new ignition",
		float(r.get("heat", 0.0)) >= 0.85)
	var far_id: int = int((parts[4] as Dictionary).get("id", 0))
	_check("new witness joins the shared rumor",
		(r["knowers"] as Array).has(far_id))
	gs.queue_free()


func _test_witness_memory() -> void:
	var parts: Array = _fire_harness()
	var gs: GameState = parts[0]
	_ignite(gs, Vector2(100, 100))
	var mems: Array = SimMemories.new(gs).ensure(parts[3])
	var heard := false
	var witnessed := false
	var wstrength := 0.0
	for m: Dictionary in mems:
		if String(m.get("type", "")) == "heard_rumor":
			heard = true
		if String(m.get("type", "")) == "witnessed_rumor":
			witnessed = true
			wstrength = float(m.get("strength", 0.0))
	_check("fire witness remembers hearing it", heard)
	_check("fire witness remembers SEEING it", witnessed)
	_check("witnessed memory strength 0.9",
		absf(wstrength - 0.9) < 0.001)
	gs.queue_free()


func _test_save_roundtrip() -> void:
	var parts: Array = _fire_harness()
	var gs: GameState = parts[0]
	var hs = parts[2]
	_ignite(gs, Vector2(100, 100))
	var rid: int = int(_wildfire_rumor(hs).get("id", 0))
	hs.from_dict(hs.to_dict())
	var r: Dictionary = hs._rumor_by_id(rid)
	_check("fire rumor survives save/load", not r.is_empty())
	_check("fire rumor kind intact after reload",
		String(r.get("kind", "")) == "disaster")
	_check("fire rumor subject intact after reload",
		String(r.get("subject", "")) == "wildfire")
	_check("fire witnesses intact after reload",
		(r.get("witnesses", []) as Array).size() == 1)
	gs.queue_free()
