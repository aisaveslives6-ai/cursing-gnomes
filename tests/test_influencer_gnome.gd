extends SceneTree
## Cursing Gnomes — Vicky the Influencer disaster tests (dedicated-porting
## 2026-10-08, original content).
##
## Disaster #25: a chibi gnome girl with a ring light and selfie stick. 0
## dmg; the weapon is CLOUT — citizens in range stop working to gawk and
## pose for her stream (gawking flag, honored by WorkerAI.tick_unit). Every
## gawker feeds her viral meter (cap 100); milestones at 25/50/100 file
## Gazette beats (TRENDING LOCALLY/REGIONALLY, GOES VIRAL). A soldier who
## closes in confiscates the ring light and she leaves crying; otherwise
## the visit timer gets her canceled. Singleton. Own stinger
## (influencer_arrive), own sprite + InfluencerFX rig, Gazette beats.
##
## Also covers the latent 2026-10-08 find: _check_dead_disaster never
## dispatched crossfit_gnome, so Kyle's slain story was dead code.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_influencer_gnome.gd
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
	print("=== Cursing Gnomes influencer_gnome tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_spawn_singleton()
	_test_town_pick_and_announce()
	_test_aura()
	_test_aura_skips_urge()
	_test_viral_milestones()
	_test_work_hold()
	_test_soldier_confiscate()
	_test_canceled_departure()
	_test_slain_story()
	_test_crossfit_slain_wired()
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


func _on_sfx(sfx_name: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(sfx_name)


func _test_def() -> void:
	_check("def: influencer_gnome in MONSTERS", DisasterSim.MONSTERS.has("influencer_gnome"))
	var m: Dictionary = DisasterSim.MONSTERS.get("influencer_gnome", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", 0.0)) == 0.0)
	_check("def: speed 80", float(m.get("speed", 0.0)) == 80.0)
	_check("def: desc mentions ring light", String(m.get("desc", "")).to_lower().contains("ring light"))


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Vicky the Influencer", d._label_for("influencer_gnome") == "Vicky the Influencer")
	_check("label: unknown kind falls back", d._label_for("nope") == "Nope")


func _test_stinger_mapping() -> void:
	_check("stinger: influencer_arrive mapped",
		DisasterSim.stinger_for_kind("influencer_gnome") == "influencer_arrive")


func _test_stinger_synth() -> void:
	# The notification-ping stinger must synthesize without errors.
	var am = AudioManager.new()
	root.add_child(am)
	var segs: Array = am._disaster_stinger_segments("influencer_arrive")
	_check("stinger: segments non-empty", not segs.is_empty())
	_check("stinger: first seg is a tone", String(segs[0].get("kind", "")) == "tone")
	am.queue_free()


func _test_spawn_singleton() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u1: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	_check("spawn: vicky created", not u1.is_empty())
	_check("spawn: job set", String(u1.get("job", "")) == "influencer_gnome")
	_check("spawn: gender f", String(u1.get("gender", "")) == "f")
	var u2: Dictionary = d.spawn("influencer_gnome", Vector2(2100, 2100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	# Cleanup so later tests start clean.
	gs.units.erase(u1)


func _test_town_pick_and_announce() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	# Far from center: Vicky warms up and walks in.
	u["influencer_center"] = Vector2(3000, 3000)
	u["influencer_visit_left"] = 240.0
	var before: Vector2 = u.get("position", Vector2.ZERO)
	d._tick_influencer(u, 80.0, 1.0)
	_check("tick: warming_up state while walking in",
		String(u.get("combat_state", "")) == "warming_up")
	_check("tick: moved toward center",
		(u.get("position", Vector2.ZERO) as Vector2).distance_to(Vector2(3000, 3000)) < before.distance_to(Vector2(3000, 3000)))
	# First tick at a fresh spawn announces.
	var u2: Dictionary = d.spawn("influencer_gnome", Vector2(100, 100))
	gs.units.erase(u)  # singleton slot freed for the announce check
	u2.erase("influencer_center")
	d._tick_influencer(u2, 80.0, 1.0)
	_check("tick: center picked on first tick", u2.has("influencer_center"))
	_check("tick: visit timer armed",
		float(u2.get("influencer_visit_left", 0.0)) > 0.0)
	_check("tick: viral meter starts at 0", float(u2.get("viral", -1.0)) == 0.0)
	gs.units.erase(u2)


func _test_aura() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	u["influencer_center"] = Vector2(2000, 2000)  # already arrived
	u["influencer_visit_left"] = 240.0
	u["viral"] = 0.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	var far := _citizen(gs, Vector2(3500, 3500), "worker")
	far["gawking"] = true  # stale flag — aura must self-heal it off
	var guard := _citizen(gs, Vector2(2050, 2050), "soldier")
	u["influencer_aura_cd"] = 0.0
	d._influencer_aura(u, Vector2(2000, 2000), 2.5)
	_check("aura: near citizen gawking", bool(near.get("gawking", false)))
	_check("aura: near citizen idle", String(near.get("work_state", "")) == "idle")
	_check("aura: far stale flag self-healed", not bool(far.get("gawking", false)))
	_check("aura: soldier immune", not bool(guard.get("gawking", false)))
	_check("aura: viral meter fed", float(u.get("viral", 0.0)) > 0.0)
	gs.units.erase(u)


func _test_aura_skips_urge() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	u["influencer_center"] = Vector2(2000, 2000)
	var busy := _citizen(gs, Vector2(2050, 2000), "worker")
	busy["mind_state"] = "satisfying:hunger"  # urge owns them
	u["influencer_aura_cd"] = 0.0
	d._influencer_aura(u, Vector2(2000, 2000), 2.5)
	_check("aura: urge-satisfying citizen skipped",
		not bool(busy.get("gawking", false)))
	gs.units.erase(u)


func _test_viral_milestones() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	u["id"] = 4242
	# Regional milestone files a Gazette story.
	u["viral"] = 60.0
	d._influencer_viral_milestones(u)
	var found_regional := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("TRENDING REGIONALLY"):
			found_regional = true
	_check("viral: regional story at 50+", found_regional)
	# Viral milestone files the big story.
	u["viral"] = 100.0
	d._influencer_viral_milestones(u)
	var found_viral := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("GOES VIRAL"):
			found_viral = true
	_check("viral: GOES VIRAL story at 100", found_viral)
	# Stories are once-per-visit: re-running files nothing new.
	var n := court.stories.size()
	d._influencer_viral_milestones(u)
	_check("viral: milestones fire once", court.stories.size() == n)
	gs.units.erase(u)


func _test_work_hold() -> void:
	# WorkerAI honors the gawking flag: no work while posing for the stream.
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var bs := SimBuildings.new(gs)
	var wa = WorkerAI.new(gs)
	var u := gs.add_unit({
		"faction": "humans", "job": "worker", "position": Vector2(100, 100),
		"alive": true, "hp": 100.0, "gawking": true,
		"work_state": "gathering",
	})
	wa.tick_unit(u, bs, 1.0 / 60.0)
	_check("work: gawking holds work_state idle",
		String(u.get("work_state", "")) == "idle")
	gs.queue_free()


func _test_soldier_confiscate() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	u["influencer_center"] = Vector2(2000, 2000)
	u["influencer_visit_left"] = 240.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["gawking"] = true
	var guard := _citizen(gs, Vector2(2060, 2000), "soldier")  # in confiscate radius
	d._tick_influencer(u, 80.0, 1.0)
	_check("confiscate: vicky leaving", bool(u.get("leaving", false)))
	_check("confiscate: flags cleared", not bool(near.get("gawking", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("RING LIGHT CONFISCATED"):
			found = true
	_check("confiscate: gazette story", found)
	gs.units.erase(u)


func _test_canceled_departure() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	u["influencer_center"] = Vector2(2000, 2000)
	u["influencer_visit_left"] = 0.05  # timer almost out
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["gawking"] = true
	d._tick_influencer(u, 80.0, 0.1)
	_check("canceled: vicky leaving", bool(u.get("leaving", false)))
	_check("canceled: flags cleared", not bool(near.get("gawking", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("VICKY GOT CANCELED"):
			found = true
	_check("canceled: gazette story", found)
	gs.units.erase(u)


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("influencer_gnome", Vector2(2000, 2000))
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["gawking"] = true
	u["alive"] = false
	d._influencer_departed(u)
	_check("slain: flags cleared", not bool(near.get("gawking", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("CANCELED (PERMANENTLY)"):
			found = true
	_check("slain: gazette story", found)
	gs.units.erase(u)


func _test_crossfit_slain_wired() -> void:
	# Latent 2026-10-08 find: _check_dead_disaster never dispatched
	# crossfit_gnome, so Kyle's "CROSSFIT GNOME CANCELLED" story was dead
	# code. This run wired it — prove it end to end.
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	_check("crossfit slain: has disaster log id", int(u.get("disaster_log_id", -1)) >= 0)
	u["alive"] = false
	d._check_dead_disaster(u)
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("CROSSFIT GNOME CANCELLED"):
			found = true
	_check("crossfit slain: story fires via _check_dead_disaster", found)
	gs.units.erase(u)


func _test_fx_rig() -> void:
	# InfluencerFX builds, pins above the sprite (via _ready, deferred one
	# frame like all Node2D ready callbacks), and emits particles.
	var fx := InfluencerFX.new()
	root.add_child(fx)
	await process_frame  # let _ready run
	_check("fx: z_index pins above sprite", fx.z_index == 2)
	_check("fx: stage_h defaults sane", fx.stage_h == 64.0)
	fx.stage_h = 76.8  # 1.2x monster scale
	# Step past one heart period and check before particles die.
	fx._process(0.8)
	_check("fx: hearts emitted", int(fx.live_counts().get("hearts", 0)) > 0)
	# Force the flash window and check it draws without error.
	fx._flash_t = InfluencerFX.FLASH_PERIOD - 0.01
	fx._process(0.05)
	_check("fx: flash window entered", fx._flash_t < InfluencerFX.FLASH_LEN)
	fx.queue_free()


func _test_unit_node_wiring() -> void:
	# Job registration, sprite texture, and monster scale.
	_check("wiring: job registered",
		"influencer_gnome" in UnitNode._MONSTER_JOBS)
	var n := UnitNode.new()
	n.job = "influencer_gnome"
	_check("wiring: monster scale 1.2x",
		absf(n._monster_scale() - UnitNode.SPRITE_WORLD_H * 1.2) < 0.01)
	var tex: Texture2D = n._monster_texture()
	_check("wiring: sprite texture resolves", tex != null)
	n.queue_free()
