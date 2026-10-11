extends SceneTree
## Cursing Gnomes — DJ Weddington disaster tests (massive-dev 2026-10-08,
## original content).
##
## Disaster #27: an unbooked wedding DJ — the wedding got canceled but he
## kept the deposit AND the gear, so he turned the town square into a
## dance floor. 0 dmg; the weapon is THE DROP — citizens in range stop
## working to dance (dancing flag, honored by WorkerAI.tick_unit). Every
## dancer feeds the hype meter (cap 100); milestones at 25/50/100 (shout /
## Gazette "FLOOR FILLER" / Gazette "WEDDINGTON BREAKS THE TOWN RECORD").
## A soldier who closes in confiscates the turntables and the music stops;
## otherwise the visit timer ends when the wedding party finds him. He DMs
## the ruler on arrival and at peak hype (flavor only). Singleton. Own
## stinger (dj_arrive), own sprite + DjFX rig, Gazette beats.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_dj_weddington.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no audio output.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class _StubCourt:
	var stories: Array = []
	func publish_story(headline: String, body: String, _kind: String) -> void:
		stories.append({"headline": headline, "body": body})


class _StubPhone:
	var dms: Array = []
	func npc_message(unit_id: int, text: String) -> void:
		dms.append({"uid": unit_id, "text": text})
	func is_blocked(_unit_id: int) -> bool:
		return false


func _initialize() -> void:
	print("=== Cursing Gnomes dj_weddington tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_spawn_singleton()
	_test_town_pick_and_announce()
	_test_aura()
	_test_aura_skips_urge()
	_test_hype_milestones()
	_test_work_hold()
	_test_soldier_confiscate()
	_test_found_departure()
	_test_slain_story()
	_test_slain_wired_via_check_dead()
	_test_arrival_dm()
	_test_peak_dm()
	await _test_fx_rig()
	_test_unit_node_wiring()
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


func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres"])
	var combat = SimCombat.new(gs)
	var d = DisasterSim.new(gs, combat)
	d.setup_bounds(Rect2(0, 0, 4000, 4000))
	return [gs, d]


func _citizen(gs: GameState, pos: Vector2, job: String) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"work_state": "gathering", "stress": 0.0,
	})


func _test_def() -> void:
	_check("def: dj_weddington in MONSTERS", DisasterSim.MONSTERS.has("dj_weddington"))
	var m: Dictionary = DisasterSim.MONSTERS.get("dj_weddington", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", 0.0)) == 0.0)
	_check("def: speed 80", float(m.get("speed", 0.0)) == 80.0)
	_check("def: desc mentions the drop",
		String(m.get("desc", "")).to_lower().contains("drop")
		or String(m.get("desc", "")).to_lower().contains("dj"))


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: DJ Weddington", d._label_for("dj_weddington") == "DJ Weddington")
	_check("label: unknown kind falls back", d._label_for("nope") == "Nope")


func _test_stinger_mapping() -> void:
	_check("stinger: dj_arrive mapped",
		DisasterSim.stinger_for_kind("dj_weddington") == "dj_arrive")


func _test_stinger_synth() -> void:
	# Airhorn + record scratch + kick thump must synthesize without errors.
	var am = AudioManager.new()
	root.add_child(am)
	var segs: Array = am._disaster_stinger_segments("dj_arrive")
	_check("stinger: segments non-empty", not segs.is_empty())
	_check("stinger: first seg is a tone", String(segs[0].get("kind", "")) == "tone")
	var total := 0.0
	for s in segs:
		total = maxf(total, float(s.get("atk", 0.0)) + float(s.get("dur", 0.0)))
	_check("stinger: total <= 1.2s", total <= 1.2)
	am.queue_free()


func _test_spawn_singleton() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u1: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	_check("spawn: dj created", not u1.is_empty())
	_check("spawn: job set", String(u1.get("job", "")) == "dj_weddington")
	var u2: Dictionary = d.spawn("dj_weddington", Vector2(2100, 2100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	gs.units.erase(u1)


func _test_town_pick_and_announce() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	# Far from center: Weddington warms up and walks in.
	u["dj_center"] = Vector2(3000, 3000)
	u["dj_visit_left"] = 240.0
	var before: Vector2 = u.get("position", Vector2.ZERO)
	d._tick_dj(u, 80.0, 1.0)
	_check("tick: warming_up state while walking in",
		String(u.get("combat_state", "")) == "warming_up")
	_check("tick: moved toward center",
		(u.get("position", Vector2.ZERO) as Vector2).distance_to(Vector2(3000, 3000)) < before.distance_to(Vector2(3000, 3000)))
	# First tick at a fresh spawn announces.
	var u2: Dictionary = d.spawn("dj_weddington", Vector2(100, 100))
	gs.units.erase(u)  # singleton slot freed for the announce check
	u2.erase("dj_center")
	d._tick_dj(u2, 80.0, 1.0)
	_check("tick: center picked on first tick", u2.has("dj_center"))
	_check("tick: visit timer armed",
		float(u2.get("dj_visit_left", 0.0)) > 0.0)
	_check("tick: hype meter starts at 0", float(u2.get("hype", -1.0)) == 0.0)
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("WEDDING DJ"):
			found = true
	_check("tick: arrival gazette story", found)
	gs.units.erase(u2)


func _test_aura() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	u["dj_center"] = Vector2(2000, 2000)  # already arrived
	u["dj_visit_left"] = 240.0
	u["hype"] = 0.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	var far := _citizen(gs, Vector2(3500, 3500), "worker")
	far["dancing"] = true  # stale flag — aura must self-heal it off
	var guard := _citizen(gs, Vector2(2050, 2050), "soldier")
	u["dj_aura_cd"] = 0.0
	d._dj_aura(u, Vector2(2000, 2000), 2.5)
	_check("aura: near citizen dancing", bool(near.get("dancing", false)))
	_check("aura: near citizen idle", String(near.get("work_state", "")) == "idle")
	_check("aura: far stale flag self-healed", not bool(far.get("dancing", false)))
	_check("aura: soldier immune", not bool(guard.get("dancing", false)))
	_check("aura: hype meter fed", float(u.get("hype", 0.0)) > 0.0)
	gs.units.erase(u)


func _test_aura_skips_urge() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	u["dj_center"] = Vector2(2000, 2000)
	var busy := _citizen(gs, Vector2(2050, 2000), "worker")
	busy["mind_state"] = "satisfying:hunger"  # urge owns them
	u["dj_aura_cd"] = 0.0
	d._dj_aura(u, Vector2(2000, 2000), 2.5)
	_check("aura: urge-satisfying citizen skipped",
		not bool(busy.get("dancing", false)))
	gs.units.erase(u)


func _test_hype_milestones() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	u["id"] = 4242
	# Filler milestone files a Gazette story.
	u["hype"] = 60.0
	d._dj_hype_milestones(u)
	var found_filler := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("FLOOR FILLER"):
			found_filler = true
	_check("hype: FLOOR FILLER story at 50+", found_filler)
	# Record milestone files the big story.
	u["hype"] = 100.0
	d._dj_hype_milestones(u)
	var found_record := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("TOWN RECORD"):
			found_record = true
	_check("hype: TOWN RECORD story at 100", found_record)
	# Stories are once-per-visit: re-running files nothing new.
	var n := court.stories.size()
	d._dj_hype_milestones(u)
	_check("hype: milestones fire once", court.stories.size() == n)
	gs.units.erase(u)


func _test_work_hold() -> void:
	# WorkerAI honors the dancing flag: no work while the drop hits.
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var bs := SimBuildings.new(gs)
	var wa = WorkerAI.new(gs)
	var u := gs.add_unit({
		"faction": "humans", "job": "worker", "position": Vector2(100, 100),
		"alive": true, "hp": 100.0, "dancing": true,
		"work_state": "gathering",
	})
	wa.tick_unit(u, bs, 1.0 / 60.0)
	_check("work: dancing holds work_state idle",
		String(u.get("work_state", "")) == "idle")
	gs.queue_free()


func _test_soldier_confiscate() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	u["dj_center"] = Vector2(2000, 2000)
	u["dj_visit_left"] = 240.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["dancing"] = true
	var guard := _citizen(gs, Vector2(2060, 2000), "soldier")  # in confiscate radius
	d._tick_dj(u, 80.0, 1.0)
	_check("confiscate: dj leaving", bool(u.get("leaving", false)))
	_check("confiscate: flags cleared", not bool(near.get("dancing", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("TURNTABLES CONFISCATED"):
			found = true
	_check("confiscate: gazette story", found)
	gs.units.erase(u)


func _test_found_departure() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	u["dj_center"] = Vector2(2000, 2000)
	u["dj_visit_left"] = 0.05  # timer almost out
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["dancing"] = true
	d._tick_dj(u, 80.0, 0.1)
	_check("found: dj leaving", bool(u.get("leaving", false)))
	_check("found: flags cleared", not bool(near.get("dancing", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("WEDDING PARTY FOUND HIM"):
			found = true
	_check("found: gazette story", found)
	gs.units.erase(u)


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["dancing"] = true
	u["alive"] = false
	d._dj_departed(u)
	_check("slain: flags cleared", not bool(near.get("dancing", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("BEAT STOPPED (PERMANENTLY)"):
			found = true
	_check("slain: gazette story", found)
	gs.units.erase(u)


func _test_slain_wired_via_check_dead() -> void:
	# The departed chain must dispatch dj_weddington so the slain story is
	# never dead code (the crossfit lesson, 2026-10-08).
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	_check("slain dispatch: has disaster log id", int(u.get("disaster_log_id", -1)) >= 0)
	u["alive"] = false
	d._check_dead_disaster(u)
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("BEAT STOPPED (PERMANENTLY)"):
			found = true
	_check("slain dispatch: story fires via _check_dead_disaster", found)
	gs.units.erase(u)


func _test_arrival_dm() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var phone := _StubPhone.new()
	gs.phone_sys = phone
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	d._dj_send_dm(u, false)
	_check("dm: arrival DM sent", phone.dms.size() == 1)
	_check("dm: arrival DM is Weddington's",
		String(phone.dms[0].get("text", "")).contains("DJ WEDDINGTON"))
	gs.units.erase(u)


func _test_peak_dm() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var phone := _StubPhone.new()
	gs.phone_sys = phone
	var u: Dictionary = d.spawn("dj_weddington", Vector2(2000, 2000))
	u["id"] = 777
	d._dj_send_dm(u, true)
	_check("dm: peak-hype DM sent", phone.dms.size() == 1)
	_check("dm: peak DM mentions the set",
		String(phone.dms[0].get("text", "")).to_lower().contains("set was fire"))
	gs.units.erase(u)


func _test_fx_rig() -> void:
	# DjFX builds, pins above the sprite (via _ready, deferred one frame
	# like all Node2D ready callbacks), and emits notes.
	var fx := DjFX.new()
	root.add_child(fx)
	await process_frame  # let _ready run
	_check("fx: z_index pins above sprite", fx.z_index == 2)
	_check("fx: stage_h defaults sane", fx.stage_h == 64.0)
	fx.stage_h = 76.8  # 1.2x monster scale
	# Step past one note period and check before notes die.
	fx._process(0.9)
	_check("fx: notes emitted", int(fx.live_counts().get("notes", 0)) > 0)
	_check("fx: eq bars sized", fx._eq_phase.size() == DjFX.EQ_BARS)
	fx.queue_free()


func _test_unit_node_wiring() -> void:
	# Job registration, sprite texture, and monster scale.
	_check("wiring: job registered",
		"dj_weddington" in UnitNode._MONSTER_JOBS)
	var n := UnitNode.new()
	n.job = "dj_weddington"
	_check("wiring: monster scale 1.2x",
		absf(n._monster_scale() - UnitNode.SPRITE_WORLD_H * 1.2) < 0.01)
	var tex: Texture2D = n._monster_texture()
	_check("wiring: sprite texture resolves", tex != null)
	n.queue_free()
