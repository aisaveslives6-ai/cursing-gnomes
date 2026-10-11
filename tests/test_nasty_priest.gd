extends SceneTree
## Cursing Gnomes — THE NASTY MONASTERY disaster tests (Jeremy 2026-10-04).
##
## Covers: 100 unique outbursts, 100 unique reactions, no-emoji content,
## priest spawn (unit + monastery building), burst tick behavior, hearsay
## reactions/rumor/squabble, Gazette story on leave, singleton rule.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_nasty_priest.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _said: Array = []        # unit_said payloads {id, text}
var _bursts: Array = []      # priest_burst payloads
var _spawned_kinds: Array = []  # disaster_spawned kinds


func _initialize() -> void:
	print("=== Cursing Gnomes nasty priest tests ===")
	_test_outburst_count()
	_test_outburst_unique()
	_test_outburst_clean()
	_test_reaction_count()
	_test_reaction_unique()
	_test_reaction_clean()
	_test_spawn_creates_priest_and_monastery()
	_test_spawn_singleton()
	_test_spawn_unknown_kind_rejected()
	_test_burst_emits_signals()
	_test_burst_reactions_and_memory()
	_test_rumor_seeded_once()
	_test_squabble_posted()
	_test_leave_publishes_gazette()
	_test_gazette_archetype()
	_test_emotion_event()
	_test_memory_type()
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


func _has_emoji(s: String) -> bool:
	for i: int in s.length():
		if s.unicode_at(i) > 0x2500:
			return true
	return false


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.player_faction = "gnomes"
	return gs


func _new_disasters(gs: GameState) -> DisasterSim:
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	_said.clear()
	_bursts.clear()
	_spawned_kinds.clear()
	gs.bus.unit_said.connect(_on_said)
	gs.bus.priest_burst.connect(_on_burst)
	gs.bus.disaster_spawned.connect(_on_spawned)
	return d


func _on_said(uid: int, text: String) -> void:
	_said.append({"id": uid, "text": text})


func _on_burst(pid: int, pos: Vector2, outburst: String) -> void:
	_bursts.append({"id": pid, "pos": pos, "text": outburst})


func _on_spawned(kind: String, _pos: Vector2) -> void:
	_spawned_kinds.append(kind)


func _make_town(gs: GameState) -> Dictionary:
	var tid: int = gs.towns.size()
	var town := {"id": tid, "name": "Testville", "faction": "gnomes",
		"position": Vector2(500, 500)}
	gs.towns[tid] = town
	return town


# --- content table tests ------------------------------------------------

func _test_outburst_count() -> void:
	_check("100 outbursts", NastyPriestData.OUTBURSTS.size() == 100)


func _test_outburst_unique() -> void:
	var seen := {}
	var dupes := 0
	for o: String in NastyPriestData.OUTBURSTS:
		if seen.has(o):
			dupes += 1
		seen[o] = true
	_check("outbursts unique", dupes == 0)


func _test_outburst_clean() -> void:
	var bad := 0
	for o: String in NastyPriestData.OUTBURSTS:
		if o.strip_edges().is_empty() or _has_emoji(o):
			bad += 1
	_check("outbursts non-empty, no emoji", bad == 0)


func _test_reaction_count() -> void:
	_check("100 reactions", NastyPriestData.REACTIONS.size() == 100)


func _test_reaction_unique() -> void:
	var seen := {}
	var dupes := 0
	for r: String in NastyPriestData.REACTIONS:
		if seen.has(r):
			dupes += 1
		seen[r] = true
	_check("reactions unique", dupes == 0)


func _test_reaction_clean() -> void:
	var bad := 0
	for r: String in NastyPriestData.REACTIONS:
		if r.strip_edges().is_empty() or _has_emoji(r):
			bad += 1
	_check("reactions non-empty, no emoji", bad == 0)


# --- spawn tests --------------------------------------------------------

func _test_spawn_creates_priest_and_monastery() -> void:
	var gs := _new_game()
	_make_town(gs)
	var d := _new_disasters(gs)
	var bcount: int = gs.buildings.size()
	var u: Dictionary = d.spawn("nasty_priest", Vector2.INF)
	_check("spawn returns unit", not u.is_empty())
	_check("priest job", String(u.get("job", "")) == "nasty_priest")
	_check("priest name", String((u.get("mind", {}) as Dictionary).get("name", "")) == "Father Filthwick")
	_check("monastery building placed", gs.buildings.size() == bcount + 1)
	var b: Dictionary = gs.buildings[gs.buildings.size() - 1]
	_check("building type monastery", String(b.get("type", "")) == "monastery")
	_check("disaster_spawned emitted", _spawned_kinds.has("nasty_priest"))
	gs.queue_free()


func _test_spawn_singleton() -> void:
	var gs := _new_game()
	_make_town(gs)
	var d := _new_disasters(gs)
	var first: Dictionary = d.spawn("nasty_priest", Vector2.INF)
	var second: Dictionary = d.spawn("nasty_priest", Vector2.INF)
	_check("first spawn works", not first.is_empty())
	_check("second spawn rejected (singleton)", second.is_empty())
	gs.queue_free()


func _test_spawn_unknown_kind_rejected() -> void:
	var gs := _new_game()
	var d := _new_disasters(gs)
	_check("unknown kind rejected", d.spawn("not_a_disaster", Vector2.ZERO).is_empty())
	gs.queue_free()


# --- burst behavior -----------------------------------------------------

func _test_burst_emits_signals() -> void:
	var gs := _new_game()
	_make_town(gs)
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("nasty_priest", Vector2.INF)
	u["burst_timer"] = 0.01  # burst on next tick
	d.tick(0.05)
	_check("unit_said emitted", _said.size() >= 1)
	_check("priest_burst emitted", _bursts.size() == 1)
	var said_text: String = String(_said[0].get("text", ""))
	_check("said text is an outburst",
		said_text in NastyPriestData.OUTBURSTS)
	_check("bursts_done incremented", int(u.get("bursts_done", 0)) == 1)
	gs.queue_free()


func _test_burst_reactions_and_memory() -> void:
	var gs := _new_game()
	_make_town(gs)
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	var hearsay = load("res://scripts/sim/hearsay.gd").new(gs, phone)
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("nasty_priest", Vector2.INF)
	var ppos: Vector2 = u.get("position", Vector2.ZERO)
	# Bystanders near the priest.
	var witnesses: Array = []
	for i: int in 6:
		var w: Dictionary = gs.add_unit({"faction": "gnomes", "alive": true,
			"position": ppos + Vector2(i * 10.0, 0), "mind": {}})
		witnesses.append(w)
	_said.clear()
	gs.bus.priest_burst.emit(int(u.get("id", -1)), ppos,
		NastyPriestData.OUTBURSTS[0])
	# Jeremy 2026-10-06: bubble ban — witnesses no longer shout via
	# unit_said; they react with panic/disgust emotions, remember the
	# priest, and join the rumor instead (hearsay.gd _on_priest_burst).
	var emo := SimEmotion.new()
	var reacted := 0
	for w: Dictionary in witnesses:
		match emo.dominant(w):
			"scared", "disgusted":
				reacted += 1
	_check("reactions felt (panic or disgust)", reacted >= 1)
	var mem := SimMemories.new(gs)
	var remembered := 0
	for w: Dictionary in witnesses:
		for m: Dictionary in mem.ensure(w):
			if String(m.get("type", "")) == "harassed_by":
				remembered += 1
				break
	_check("witnesses remember the priest", remembered >= 1)
	gs.queue_free()


func _test_rumor_seeded_once() -> void:
	var gs := _new_game()
	_make_town(gs)
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	var hearsay = load("res://scripts/sim/hearsay.gd").new(gs, phone)
	var before: int = (hearsay.state["rumors"] as Array).size()
	gs.bus.priest_burst.emit(999, Vector2(500, 500), NastyPriestData.OUTBURSTS[1])
	gs.bus.priest_burst.emit(999, Vector2(500, 500), NastyPriestData.OUTBURSTS[2])
	var priest_rumors := 0
	for r: Dictionary in hearsay.state["rumors"]:
		if String(r.get("kind", "")) == "nasty_priest":
			priest_rumors += 1
	_check("rumor seeded", priest_rumors >= 1)
	_check("rumor not duplicated per burst", priest_rumors == 1)
	gs.queue_free()


func _test_squabble_posted() -> void:
	var gs := _new_game()
	_make_town(gs)
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	# NPCs need to exist for _random_author.
	for i: int in 3:
		gs.add_unit({"faction": "gnomes", "alive": true, "mind": {}})
	var posts: Array = []
	gs.bus.squabble_post.connect(func(p: Dictionary) -> void: posts.append(p))
	var hearsay = load("res://scripts/sim/hearsay.gd").new(gs, phone)
	gs.bus.priest_burst.emit(999, Vector2(500, 500), NastyPriestData.OUTBURSTS[3])
	_check("squabble post about the priest", posts.size() >= 1)
	var found := false
	for p: Dictionary in posts:
		var t: String = String(p.get("text", "")).to_lower()
		if "filthwick" in t or "priest" in t or "monastery" in t:
			found = true
	_check("squabble post mentions the priest", found)
	gs.queue_free()


# --- Gazette ------------------------------------------------------------

func _test_leave_publishes_gazette() -> void:
	var gs := _new_game()
	_make_town(gs)
	var stories: Array = []
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: stories.append(s))
	# The Gazette story needs the royal court (World normally owns it).
	var court = load("res://scripts/sim/royal_court.gd").new(gs)
	gs.set("court_sys", court)
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("nasty_priest", Vector2.INF)
	# Force max bursts then tick -> leaves -> Gazette story.
	u["bursts_done"] = 6
	u["age"] = 0.0
	d.tick(0.1)
	_check("gazette story published on leave", stories.size() >= 1)
	var found := false
	for s: Dictionary in stories:
		var h: String = String(s.get("headline", "")).to_upper()
		if "PRIEST" in h or "FILTHWICK" in h or "MONASTERY" in h:
			found = true
	_check("headline about the priest", found)
	gs.queue_free()


func _test_gazette_archetype() -> void:
	var gs := _new_game()
	var gz := SimGazette.new(gs)
	var arch: String = gz.archetype_for("NASTY PRIEST OPENS MONASTERY — REGRETS FOLLOW",
		"Father Filthwick screams about boobies.")
	_check("gazette classifies as disaster", arch == "disaster")
	gs.queue_free()


# --- emotion + memory plumbing ------------------------------------------

func _test_emotion_event() -> void:
	var gs := _new_game()
	var u: Dictionary = gs.add_unit({"faction": "gnomes", "alive": true, "mind": {}})
	var emo := SimEmotion.new()
	emo.notify(u, "grossed_out")
	_check("grossed_out -> disgusted", emo.dominant(u) == "disgusted")
	gs.queue_free()


func _test_memory_type() -> void:
	var gs := _new_game()
	var u: Dictionary = gs.add_unit({"faction": "gnomes", "alive": true, "mind": {}})
	var mem := SimMemories.new(gs)
	mem.remember(u, "harassed_by", 123, "Father Filthwick", "monster", 0.9)
	var found := false
	for m: Dictionary in mem.ensure(u):
		if String(m.get("type", "")) == "harassed_by":
			found = true
	_check("harassed_by memory recorded", found)
	gs.queue_free()
