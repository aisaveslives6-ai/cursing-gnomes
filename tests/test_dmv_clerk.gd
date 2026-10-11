extends SceneTree
## Cursing Gnomes — Dave the DMV Clerk disaster tests (wake rapid-iteration
## 2026-10-08, original content).
##
## Disaster #23: a surly chibi gnome in a grey cardigan wheels a folding
## table into the town square and opens an unauthorized DMV branch. 0 dmg;
## the weapon is the queue — citizens in aura range take a number and WAIT
## IN LINE (waiting_in_line flag, honored by WorkerAI.tick_unit) instead
## of working. Dave serves one ticket at a time (slowly), skims a
## processing fee per license (capped), and closes for lunch (queue
## disperses, tickets voided). Soldiers shut him down on sight; the
## branch closes for the day when the visit timer runs out. Singleton.
## Own stinger (dmv_arrive), own sprite, Gazette beats.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_dmv_clerk.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no audio output.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sfx_seen: Array = []


class _StubCourt:
	var stories: Array = []
	func publish_story(headline: String, body: String, _kind: String) -> void:
		stories.append({"headline": headline, "body": body})


func _initialize() -> void:
	print("=== Cursing Gnomes DMV clerk tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_stinger_distinct()
	_test_spawn()
	_test_town_pick_and_announce()
	_test_aura()
	_test_serve()
	_test_lunch()
	_test_work_hold()
	_test_soldier_shutdown()
	_test_visit_close()
	_test_slain_story()
	_test_sprite_loads()
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


## FNV-1a 32-bit checksum: PackedByteArray has no md5 in Godot 4.
static func _checksum(data: PackedByteArray) -> int:
	var h := 2166136261
	for b in data:
		h = ((h ^ b) * 16777619) & 0xFFFFFFFF
	return h


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	var combat = SimCombat.new(gs)
	var d = DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	return [gs, d]


func _on_sfx(sfx_name: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(sfx_name)


func _headlines(court: _StubCourt) -> Array:
	var out: Array = []
	for s in court.stories:
		out.append(String(s.get("headline", "")))
	return out


func _test_def() -> void:
	_check("def: dmv_clerk in MONSTERS", DisasterSim.MONSTERS.has("dmv_clerk"))
	var m: Dictionary = DisasterSim.MONSTERS.get("dmv_clerk", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", -1.0)) == 0.0)
	_check("def: speed 70", float(m.get("speed", 0.0)) == 70.0)
	_check("def: desc non-empty", String(m.get("desc", "")) != "")
	_check("def: take-a-number gag in desc",
		String(m.get("desc", "")).find("847") >= 0)


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Dave the DMV Clerk",
		d._label_for("dmv_clerk") == "Dave the DMV Clerk")
	w[0].queue_free()


func _test_stinger_mapping() -> void:
	_check("dmv_clerk -> dmv_arrive",
		DisasterSim.stinger_for_kind("dmv_clerk") == "dmv_arrive")


func _test_stinger_synth() -> void:
	var am := AudioManager.new()
	var wav: AudioStreamWAV = am._synthesize_sfx("dmv_arrive")
	_check("dmv_arrive: synthesizes non-null", wav != null)
	if wav == null:
		am.queue_free()
		return
	_check("dmv_arrive: has frames", wav.data.size() > 0)
	var dur := float(wav.data.size()) / float(wav.mix_rate)
	_check("dmv_arrive: hold-music but under 2.2s (%.2fs)" % dur, dur <= 2.2)
	_check("dmv_arrive: 8-bit mono", wav.format == AudioStreamWAV.FORMAT_8_BITS
		and not wav.stereo)
	am.queue_free()


func _test_stinger_distinct() -> void:
	var am := AudioManager.new()
	var mine: AudioStreamWAV = am._synthesize_sfx("dmv_arrive")
	_check("dmv_arrive: synth ok for distinct", mine != null)
	if mine == null:
		am.queue_free()
		return
	var mine_sum := _checksum(mine.data)
	var names := ["karen_arrive", "wizard_arrive", "bastard_arrive",
		"gig_arrive", "prophet_arrive", "taxman_arrive", "ooze_arrive",
		"gull_arrive", "moose_arrive", "jesus_arrive",
		"ass_arrive", "lizard_arrive", "cat_arrive", "twister_arrive",
		"doom_arrive", "warranty_arrive", "mlm_arrive"]
	var clash := false
	for n in names:
		var wr: AudioStreamWAV = am._synthesize_sfx(n)
		if wr != null and _checksum(wr.data) == mine_sum:
			clash = true
	_check("dmv_arrive: distinct from the 17", not clash)
	am.queue_free()


func _test_spawn() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_sfx_seen.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	var u: Dictionary = d.spawn("dmv_clerk", Vector2(2000, 2000))
	_check("dmv_clerk spawns", not u.is_empty())
	_check("spawn: job set", String(u.get("job", "")) == "dmv_clerk")
	_check("spawn: monster faction",
		String(u.get("faction", "")) == DisasterSim.MONSTER_FACTION)
	_check("spawn: emits dmv_arrive, not boom",
		_sfx_seen.has("dmv_arrive") and not _sfx_seen.has("boom"))
	var u2: Dictionary = d.spawn("dmv_clerk", Vector2(100, 100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	gs.bus.sfx_spatial.disconnect(_on_sfx)
	gs.queue_free()


func _test_town_pick_and_announce() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.towns[1] = {"position": Vector2(3000, 3000), "name": "Teston"}
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("dmv_clerk", Vector2(100, 100))
	d._tick_dmv(u, 70.0, 1.0)
	_check("town pick: center set", u.has("dmv_center"))
	var c: Vector2 = u.get("dmv_center", Vector2.ZERO)
	_check("town pick: center near town", c.distance_to(Vector2(3000, 3000)) < 1.0)
	_check("town pick: visit timer armed",
		float(u.get("dmv_visit_left", 0.0)) > 0.0)
	_check("town pick: ticket counter starts at 1",
		int(u.get("dmv_ticket_next", 0)) == 1)
	_check("town pick: arrival story filed",
		_headlines(court).has("DMV OPENS IN TOWN SQUARE"))
	gs.queue_free()


func _citizen(gs: GameState, pos: Vector2, job: String) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"work_state": "gathering", "stress": 0.0,
	})


func _arrived(w: Array, gs: GameState, d) -> Dictionary:
	var u: Dictionary = d.spawn("dmv_clerk", Vector2(2000, 2000))
	u["dmv_center"] = Vector2(2000, 2000)  # already set up
	u["dmv_visit_left"] = 300.0
	u["dmv_ticket_next"] = 1
	u["dmv_skimmed"] = 0.0
	u["dmv_lunch_in"] = 9999.0  # lunch not due in unit tests
	u["dmv_on_lunch"] = false
	return u


func _test_aura() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = _arrived(w, gs, d)
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	var far := _citizen(gs, Vector2(3500, 3500), "worker")
	far["waiting_in_line"] = true  # stale flag — aura must self-heal it off
	far["dmv_ticket"] = 3
	var guard := _citizen(gs, Vector2(2050, 2050), "soldier")
	d._dmv_aura(u, Vector2(2000, 2000), 4.0)
	_check("aura: near citizen waiting in line",
		bool(near.get("waiting_in_line", false)))
	_check("aura: near citizen got a ticket",
		int(near.get("dmv_ticket", 0)) >= 1)
	_check("aura: near citizen work held", String(near.get("work_state", "")) == "idle")
	_check("aura: far citizen flag self-healed",
		not bool(far.get("waiting_in_line", false)))
	_check("aura: soldier does no paperwork",
		not bool(guard.get("waiting_in_line", false)))
	_check("aura: ticket counter advanced", int(u.get("dmv_ticket_next", 1)) > 1)
	gs.queue_free()


func _test_serve() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.resources.add_resource("humans", "gold", 1000.0, true)
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	var u: Dictionary = _arrived(w, gs, d)
	var c1 := _citizen(gs, Vector2(2050, 2000), "worker")
	c1["waiting_in_line"] = true
	c1["dmv_ticket"] = 2
	var c2 := _citizen(gs, Vector2(2060, 2000), "worker")
	c2["waiting_in_line"] = true
	c2["dmv_ticket"] = 1  # lowest — served first
	u["dmv_serve_cd"] = 0.0
	d._dmv_serve(u, Vector2(2000, 2000), 1.0)
	_check("serve: lowest ticket served first",
		not bool(c2.get("waiting_in_line", false)))
	_check("serve: higher ticket still waiting",
		bool(c1.get("waiting_in_line", false)))
	_check("serve: processing fee skimmed from treasury",
		gold_before - gs.resources.get_amount("humans", "gold") \
		>= DisasterSim.DMV_FEE - 0.001)
	_check("serve: serve cooldown re-armed",
		float(u.get("dmv_serve_cd", 0.0)) > 0.0)
	# Skim cap: Dave can't extract more than DMV_MAX_SKIM per visit.
	u["dmv_skimmed"] = DisasterSim.DMV_MAX_SKIM
	var c3 := _citizen(gs, Vector2(2070, 2000), "worker")
	c3["waiting_in_line"] = true
	c3["dmv_ticket"] = 3
	u["dmv_serve_cd"] = 0.0
	var gold_mid: float = gs.resources.get_amount("humans", "gold")
	d._dmv_serve(u, Vector2(2000, 2000), 1.0)
	_check("serve: skim capped — no fee past DMV_MAX_SKIM",
		absf(gs.resources.get_amount("humans", "gold") - gold_mid) < 0.001)
	gs.queue_free()


func _test_lunch() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = _arrived(w, gs, d)
	var c := _citizen(gs, Vector2(2050, 2000), "worker")
	c["waiting_in_line"] = true
	c["dmv_ticket"] = 5
	u["dmv_lunch_in"] = 0.5
	d._dmv_lunch(u, 1.0)
	_check("lunch: window closed", bool(u.get("dmv_on_lunch", false)))
	_check("lunch: queue dispersed", not bool(c.get("waiting_in_line", false)))
	_check("lunch: CLOSED FOR LUNCH story filed",
		_headlines(court).has("DMV CLOSED FOR LUNCH"))
	u["dmv_lunch_left"] = 0.5
	d._dmv_lunch(u, 1.0)
	_check("lunch: window reopened", not bool(u.get("dmv_on_lunch", false)))
	_check("lunch: ticket counter reset", int(u.get("dmv_ticket_next", 0)) == 1)
	_check("lunch: DMV REOPENS story filed",
		_headlines(court).has("DMV REOPENS"))
	gs.queue_free()


func _test_work_hold() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var bs := SimBuildings.new(gs)
	var ai := WorkerAI.new(gs)
	var u := _citizen(gs, Vector2(2000, 2000), "worker")
	u["waiting_in_line"] = true
	u["work_state"] = "gathering"
	ai.tick_unit(u, bs, 1.0 / 60.0)
	_check("work: queued unit stays idle",
		String(u.get("work_state", "")) == "idle")
	var u2 := _citizen(gs, Vector2(2000, 2000), "worker")
	u2["work_state"] = "gathering"
	ai.tick_unit(u2, bs, 1.0 / 60.0)
	_check("work: clean unit not flagged waiting",
		not bool(u2.get("waiting_in_line", false)))
	gs.queue_free()


func _test_soldier_shutdown() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = _arrived(w, gs, d)
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["waiting_in_line"] = true
	_citizen(gs, Vector2(2060, 2000), "soldier")  # inside flee radius
	d._tick_dmv(u, 70.0, 1.0)
	_check("shutdown: leaving set", bool(u.get("leaving", false)))
	_check("shutdown: citizen flag cleared",
		not bool(near.get("waiting_in_line", false)))
	_check("shutdown: DMV SHUT DOWN story filed",
		_headlines(court).has("DMV SHUT DOWN"))
	gs.queue_free()


func _test_visit_close() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = _arrived(w, gs, d)
	var c := _citizen(gs, Vector2(2050, 2000), "worker")
	c["waiting_in_line"] = true
	u["dmv_visit_left"] = 0.5
	d._tick_dmv(u, 70.0, 1.0)
	_check("close: leaving set", bool(u.get("leaving", false)))
	_check("close: flags cleared", not bool(c.get("waiting_in_line", false)))
	_check("close: DMV CLOSES story filed",
		_headlines(court).has("DMV CLOSES (HOURS WERE 9-5)"))
	gs.queue_free()


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = _arrived(w, gs, d)
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["waiting_in_line"] = true
	u["alive"] = false
	d._dmv_departed(u)
	_check("slain: flags cleared", not bool(near.get("waiting_in_line", false)))
	_check("slain: DMV PERMANENTLY CLOSED story filed",
		_headlines(court).has("DMV PERMANENTLY CLOSED"))
	gs.queue_free()


func _test_sprite_loads() -> void:
	var t: Texture2D = Art.animal_texture("dmv_clerk")
	_check("sprite: dmv_clerk.png loads", t != null)
	if t == null:
		return
	_check("sprite: has size", t.get_size().x > 0 and t.get_size().y > 0)
