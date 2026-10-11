extends SceneTree
## Cursing Gnomes — Kyle the CrossFit Gnome disaster tests (massive-dev
## 2026-10-08, original content).
##
## Disaster #24: a chibi gnome in a neon tank top and headband who IS the
## equipment. 0 dmg; the weapon is the WOD — citizens in range drop their
## tools and do burpees (workouting flag, honored by WorkerAI.tick_unit),
## draining energy but building swole stacks (slower energy decay via
## SimUrges). A soldier who closes in wins the burpee contest and Kyle
## leaves humbled; otherwise the visit timer sends him to leg day.
## Singleton. Own stinger (crossfit_arrive), own sprite + CrossFitFX rig,
## Gazette beats.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_crossfit_gnome.gd
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
	print("=== Cursing Gnomes crossfit_gnome tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_spawn_singleton()
	_test_town_pick_and_announce()
	_test_aura()
	_test_aura_swole_cap()
	_test_aura_skips_urge()
	_test_work_hold()
	_test_soldier_contest()
	_test_legday_departure()
	_test_slain_story()
	_test_swole_decay_benefit()
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


func _on_sfx(sfx_name: String, _pos: Vector2, _vel: Vector2) -> void:
	_sfx_seen.append(sfx_name)


func _citizen(gs: GameState, pos: Vector2, job: String) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": job, "town_id": 1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"work_state": "gathering", "stress": 0.0,
	})


func _test_def() -> void:
	_check("def: crossfit_gnome in MONSTERS", DisasterSim.MONSTERS.has("crossfit_gnome"))
	var m: Dictionary = DisasterSim.MONSTERS.get("crossfit_gnome", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", 0.0)) == 0.0)
	_check("def: speed 80", float(m.get("speed", 0.0)) == 80.0)
	_check("def: desc mentions burpees", String(m.get("desc", "")).to_lower().contains("burpee"))


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Kyle the CrossFit Gnome", d._label_for("crossfit_gnome") == "Kyle the CrossFit Gnome")
	_check("label: unknown kind falls back", d._label_for("nope") == "Nope")


func _test_stinger_mapping() -> void:
	_check("stinger: crossfit_arrive mapped",
		DisasterSim.stinger_for_kind("crossfit_gnome") == "crossfit_arrive")


func _test_stinger_synth() -> void:
	# The airhorn stinger must synthesize without errors (segments valid).
	var am = AudioManager.new()
	root.add_child(am)
	var segs: Array = am._disaster_stinger_segments("crossfit_arrive")
	_check("stinger: segments non-empty", not segs.is_empty())
	_check("stinger: first seg is a tone", String(segs[0].get("kind", "")) == "tone")
	am.queue_free()


func _test_spawn_singleton() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u1: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	_check("spawn: kyle created", not u1.is_empty())
	_check("spawn: job set", String(u1.get("job", "")) == "crossfit_gnome")
	var u2: Dictionary = d.spawn("crossfit_gnome", Vector2(2100, 2100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	# Cleanup so later tests start clean.
	gs.units.erase(u1)


func _test_town_pick_and_announce() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	# Far from center: Kyle warms up and walks in.
	u["crossfit_center"] = Vector2(3000, 3000)
	u["crossfit_visit_left"] = 240.0
	var before: Vector2 = u.get("position", Vector2.ZERO)
	d._tick_crossfit(u, 80.0, 1.0)
	_check("tick: warming_up state while walking in",
		String(u.get("combat_state", "")) == "warming_up")
	_check("tick: moved toward center",
		(u.get("position", Vector2.ZERO) as Vector2).distance_to(Vector2(3000, 3000)) < before.distance_to(Vector2(3000, 3000)))
	# First tick at a fresh spawn announces.
	var u2: Dictionary = d.spawn("crossfit_gnome", Vector2(100, 100))
	gs.units.erase(u)  # singleton slot freed for the announce check
	u2.erase("crossfit_center")
	d._tick_crossfit(u2, 80.0, 1.0)
	_check("tick: center picked on first tick", u2.has("crossfit_center"))
	_check("tick: visit timer armed",
		float(u2.get("crossfit_visit_left", 0.0)) > 0.0)
	gs.units.erase(u2)


func _test_aura() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	u["crossfit_center"] = Vector2(2000, 2000)  # already arrived
	u["crossfit_visit_left"] = 240.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	var far := _citizen(gs, Vector2(3500, 3500), "worker")
	far["workouting"] = true  # stale flag — aura must self-heal it off
	var guard := _citizen(gs, Vector2(2050, 2050), "soldier")
	d._crossfit_aura(u, Vector2(2000, 2000), 2.5)
	_check("aura: near citizen workout", bool(near.get("workouting", false)))
	_check("aura: near citizen idle", String(near.get("work_state", "")) == "idle")
	_check("aura: far citizen untouched", not bool(far.get("workouting", false)))
	_check("aura: soldier immune", not bool(guard.get("workouting", false)))
	var urges := SimUrges.new(gs)
	_check("aura: energy drained",
		float(urges.ensure(near).get("energy", 60.0)) < 60.0)
	_check("aura: swole stack added", int(near.get("swole", 0)) == 1)
	gs.units.erase(u)


func _test_aura_swole_cap() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	u["crossfit_center"] = Vector2(2000, 2000)
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["swole"] = 10  # already maxed
	for i in 30:
		u["crossfit_aura_cd"] = 0.0
		d._crossfit_aura(u, Vector2(2000, 2000), 2.5)
	_check("aura: swole capped at 10", int(near.get("swole", 0)) == 10)
	gs.units.erase(u)


func _test_aura_skips_urge() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	u["crossfit_center"] = Vector2(2000, 2000)
	var busy := _citizen(gs, Vector2(2050, 2000), "worker")
	busy["mind_state"] = "satisfying:hunger"  # urge owns them
	u["crossfit_aura_cd"] = 0.0
	d._crossfit_aura(u, Vector2(2000, 2000), 2.5)
	_check("aura: urge-satisfying citizen skipped",
		not bool(busy.get("workouting", false)))
	gs.units.erase(u)


func _test_work_hold() -> void:
	# WorkerAI honors the workout flag: no work while doing burpees.
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var bs := SimBuildings.new(gs)
	var wa = WorkerAI.new(gs)
	var u := gs.add_unit({
		"faction": "humans", "job": "worker", "position": Vector2(100, 100),
		"alive": true, "hp": 100.0, "workouting": true,
		"work_state": "gathering",
	})
	wa.tick_unit(u, bs, 1.0 / 60.0)
	_check("work: workout holds work_state idle",
		String(u.get("work_state", "")) == "idle")
	gs.queue_free()


func _test_soldier_contest() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	u["crossfit_center"] = Vector2(2000, 2000)
	u["crossfit_visit_left"] = 240.0
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["workouting"] = true
	var guard := _citizen(gs, Vector2(2060, 2000), "soldier")  # in contest radius
	d._tick_crossfit(u, 80.0, 1.0)
	_check("contest: kyle leaving", bool(u.get("leaving", false)))
	_check("contest: flags cleared", not bool(near.get("workouting", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("BURPEE CONTEST"):
			found = true
	_check("contest: gazette story", found)
	gs.units.erase(u)


func _test_legday_departure() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	u["crossfit_center"] = Vector2(2000, 2000)
	u["crossfit_visit_left"] = 0.05  # timer almost out
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["workouting"] = true
	d._tick_crossfit(u, 80.0, 0.1)
	_check("legday: kyle leaving", bool(u.get("leaving", false)))
	_check("legday: flags cleared", not bool(near.get("workouting", false)))
	gs.units.erase(u)


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("crossfit_gnome", Vector2(2000, 2000))
	var near := _citizen(gs, Vector2(2050, 2000), "worker")
	near["workouting"] = true
	u["alive"] = false
	d._crossfit_departed(u)
	_check("slain: flags cleared", not bool(near.get("workouting", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("CANCELLED"):
			found = true
	_check("slain: gazette story", found)
	gs.units.erase(u)


func _test_swole_decay_benefit() -> void:
	# Swole citizens lose energy slower (SimUrges.tick honors swole).
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var plain := gs.add_unit({"faction": "humans", "alive": true})
	var jacked := gs.add_unit({"faction": "humans", "alive": true, "swole": 10})
	var urges := SimUrges.new(gs)
	urges.ensure(plain)
	urges.ensure(jacked)
	var e0: float = float(urges.ensure(plain).get("energy", 60.0))
	urges.tick(plain, 10.0)
	urges.tick(jacked, 10.0)
	var e_plain: float = float(urges.ensure(plain).get("energy", 60.0))
	var e_jacked: float = float(urges.ensure(jacked).get("energy", 60.0))
	_check("swole: energy decays", e_plain < e0)
	_check("swole: jacked decays slower", e_jacked > e_plain)
	# 10 stacks = 50% reduction: jacked loss should be ~half of plain loss.
	var loss_plain: float = e0 - e_plain
	var loss_jacked: float = e0 - e_jacked
	_check("swole: ~50% reduction at cap",
		absf(loss_jacked - loss_plain * 0.5) < 0.01)
	gs.queue_free()


func _test_fx_rig() -> void:
	# CrossFitFX builds, pins above the sprite (via _ready, deferred one
	# frame like all Node2D ready callbacks), and emits particles.
	var fx := CrossFitFX.new()
	root.add_child(fx)
	await process_frame  # let _ready run
	_check("fx: z_index pins above sprite", fx.z_index == 2)
	_check("fx: stage_h defaults sane", fx.stage_h == 64.0)
	fx.stage_h = 76.8  # 1.2x monster scale
	# Step just past the sweat phase (0.15) and check before particles die.
	fx._burpee_phase = 0.14
	fx._process(0.05)
	_check("fx: sweat emitted", int(fx.live_counts().get("sweat", 0)) > 0)
	# Step just past the landing phase (0.5) and check before particles die.
	fx._burpee_phase = 0.49
	fx._process(0.05)
	_check("fx: dust emitted", int(fx.live_counts().get("dust", 0)) > 0)
	fx.queue_free()


func _test_unit_node_wiring() -> void:
	# Job registration, sprite texture, and monster scale.
	_check("wiring: job registered",
		"crossfit_gnome" in UnitNode._MONSTER_JOBS)
	var n := UnitNode.new()
	n.job = "crossfit_gnome"
	_check("wiring: monster scale 1.2x",
		absf(n._monster_scale() - UnitNode.SPRITE_WORLD_H * 1.2) < 0.01)
	var tex: Texture2D = n._monster_texture()
	_check("wiring: sprite texture resolves", tex != null)
	n.queue_free()
