extends SceneTree
## Cursing Gnomes — thicc moose mooning reaction tests (HTML moonGrossOut /
## scareNearby port, Jeremy 2026-10-04).
##
## Covers: moose_mooned signal triggers nearby NPC reactions (faction-specific
## speech bubbles + emotions), Squabble posts + replies, rumor seeding,
## disaster spawn reactions for other disasters.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_moose_moon.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes moose mooning tests ===")
	_test_moon_react_lines_exist()
	_test_moon_triggers_reactions()
	_test_moon_faction_emotions()
	_test_moon_squabble_post()
	_test_moon_rumor_seeded()
	_test_disaster_react_lines_exist()
	_test_disaster_spawn_reactions()
	_test_npc_comment()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	# Towns must exist for spawn_unit to work (check_spawn validates town_id).
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	return {"gs": gs, "mind": mind, "phone": phone}


func _spawn(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, "worker", 1, pos)
	mind.ensure(u)
	return u


func _test_moon_react_lines_exist() -> void:
	# All faction reaction pools must have 10+ lines (Jeremy's spec).
	_check("ogres react lines >= 10", SimHearsay.MOOSE_REACT_OGRES.size() >= 10)
	_check("elves react lines >= 10", SimHearsay.MOOSE_REACT_ELVES.size() >= 10)
	_check("gnomes react lines >= 10", SimHearsay.MOOSE_REACT_GNOMES.size() >= 10)
	_check("humans react lines >= 10", SimHearsay.MOOSE_REACT_HUMANS.size() >= 10)
	_check("undead react lines >= 10", SimHearsay.MOOSE_REACT_UNDEAD.size() >= 10)
	_check("generic react lines exist", SimHearsay.MOOSE_REACT_GENERIC.size() >= 5)
	_check("squabble lines >= 15", SimHearsay.MOOSE_SQB_LINES.size() >= 15)
	_check("squabble replies >= 12", SimHearsay.MOOSE_SQB_REPLIES.size() >= 12)


func _test_moon_triggers_reactions() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	# Spawn NPCs near the hall (within 240 range).
	var hall_pos := Vector2(500, 500)
	var n1 := _spawn(w, "ogres", hall_pos + Vector2(50, 0))
	var n2 := _spawn(w, "elves", hall_pos + Vector2(-50, 0))
	var n3 := _spawn(w, "gnomes", hall_pos + Vector2(0, 50))
	# Spawn one far away (should NOT react).
	var far := _spawn(w, "humans", hall_pos + Vector2(1000, 1000))
	var hall := {"id": 1, "name": "Test Hall", "position": hall_pos,
		"type": "town_hall"}
	# Jeremy 2026-10-06: the old bubble-shout reactions are no-ops since
	# the bubble ban — nearby NPCs now WITNESS: they join the mooning
	# rumor as knowers with real memories (55% chance each; run until
	# at least one witnesses).
	var witnessed := false
	for i: int in 8:
		hear._on_moose_mooned(hall)
		var mems: Array = SimMemories.new(gs).ensure(n1)
		for m: Dictionary in mems:
			if String(m.get("type", "")) == "heard_rumor":
				witnessed = true
				break
		if witnessed:
			break
	_check("nearby NPCs witness the mooning", witnessed)
	# The far NPC must not be a knower of the mooning rumor.
	var far_knows := false
	for r: Dictionary in hear.state["rumors"]:
		if String(r.get("kind", "")) == "moose_moon" \
				and (r["knowers"] as Array).has(int(far.get("id", 0))):
			far_knows = true
	_check("far NPC does not witness", not far_knows)


func _test_moon_faction_emotions() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	var hall_pos := Vector2(500, 500)
	# Ogres and gnomes should feel happy (they laugh).
	var ogr := _spawn(w, "ogres", hall_pos + Vector2(50, 0))
	var gnm := _spawn(w, "gnomes", hall_pos + Vector2(-50, 0))
	# Elves should feel scared (horrified).
	var elf := _spawn(w, "elves", hall_pos + Vector2(0, 50))
	var hall := {"id": 1, "name": "Test Hall", "position": hall_pos,
		"type": "town_hall"}
	hear._on_moose_mooned(hall)
	var ogr_emo: Dictionary = ogr.get("emotion", {})
	var gnm_emo: Dictionary = gnm.get("emotion", {})
	var elf_emo: Dictionary = elf.get("emotion", {})
	_check("ogre feels happy (laughs)",
		String(ogr_emo.get("name", "")) == "happy")
	_check("gnome feels happy (hysterical)",
		String(gnm_emo.get("name", "")) == "happy")
	_check("elf feels scared (horrified)",
		String(elf_emo.get("name", "")) == "scared")


func _test_moon_squabble_post() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	_spawn(w, "humans", Vector2(100, 100))
	var posts_before: int = (phone.state.get("posts", []) as Array).size()
	var hall := {"id": 1, "name": "Test Hall", "position": Vector2(500, 500),
		"type": "town_hall"}
	hear._on_moose_mooned(hall)
	var posts_after: int = (phone.state.get("posts", []) as Array).size()
	_check("mooning creates Squabble post", posts_after > posts_before)
	# Check the post has comments (NPC replies).
	var posts: Array = phone.state.get("posts", [])
	var found_moose_post := false
	for p: Dictionary in posts:
		if String(p.get("kind", "")) == "moose":
			found_moose_post = true
			_check("moose post has NPC replies",
				(p.get("comments", []) as Array).size() >= 1)
			break
	_check("moose-kind Squabble post exists", found_moose_post)


func _test_moon_rumor_seeded() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	var rumors_before: int = hear.live_rumors(10).size()
	var hall := {"id": 1, "name": "Test Hall", "position": Vector2(500, 500),
		"type": "town_hall"}
	hear._on_moose_mooned(hall)
	var rumors_after: int = hear.live_rumors(10).size()
	_check("mooning seeds a rumor", rumors_after > rumors_before)
	# Check rumor text mentions the moose.
	var found := false
	for r: Dictionary in hear.live_rumors(10):
		if "moose" in String(r.get("text", "")).to_lower():
			found = true
			break
	_check("rumor mentions the moose", found)


func _test_disaster_react_lines_exist() -> void:
	# All disaster types should have reaction lines (audit requirement).
	var kinds := ["giant_ass", "giant_lizard", "rogue_wizard",
		"bandit_raid", "cardboard_cat", "count_bastard"]
	for k: String in kinds:
		var lines: Array = SimHearsay.DISASTER_REACT_LINES.get(k, [])
		_check("disaster %s has react lines" % k, lines.size() >= 3)
	_check("generic disaster lines exist",
		SimHearsay.DISASTER_REACT_GENERIC.size() >= 3)


func _test_disaster_spawn_reactions() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var hear = phone.hearsay
	var dpos := Vector2(500, 500)
	var near := _spawn(w, "humans", dpos + Vector2(50, 0))
	# Trigger disaster spawn (not moose — moose has separate handler).
	# Jeremy 2026-10-06: bubble shouts are no-ops — nearby NPCs witness
	# the disaster rumor instead, with a real memory of it.
	hear._on_disaster("giant_ass", dpos)
	var witnessed := false
	for r: Dictionary in hear.state["rumors"]:
		if String(r.get("kind", "")) == "disaster" \
				and (r["knowers"] as Array).has(int(near.get("id", 0))):
			witnessed = true
	_check("disaster spawn triggers NPC witness", witnessed)
	var mems: Array = SimMemories.new(gs).ensure(near)
	var remembered := false
	for m: Dictionary in mems:
		if String(m.get("type", "")) == "heard_rumor":
			remembered = true
	_check("disaster witness remembers", remembered)


func _test_npc_comment() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var a := _spawn(w, "humans", Vector2(100, 100))
	var b := _spawn(w, "gnomes", Vector2(200, 200))
	var post: Dictionary = phone.npc_post(a, "Test post", "mood")
	var pid: int = int(post.get("id", -1))
	_check("npc_post returns valid id", pid >= 0)
	var ok: bool = phone.npc_comment(pid, b, "Test reply!")
	_check("npc_comment succeeds", ok)
	var p: Dictionary = phone._find_post(pid)
	_check("comment appears on post",
		(p.get("comments", []) as Array).size() >= 1)
