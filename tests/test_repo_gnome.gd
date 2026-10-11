extends SceneTree
## Cursing Gnomes — Ricky the Repo Gnome disaster tests (wake routine
## 2026-10-08, Disaster #28 completion).
##
## Disaster #28: a chibi repo gnome with a tow chain, clipboard of
## foreclosure papers, and a tiny tow truck. 0 dmg; the weapon is
## REPOSSESSION — he hooks the fanciest non-essential building in the
## nearest town and drags it off the map edge. The sim (spawn rules,
## target picking, approach/hookup/towing phases, Gazette stories, soldier
## impound, bank-called-it-off timer, slain story) was built by the
## 2026-10-08 dedicated-porting lane; this run completes the disaster
## with bespoke chibi art, the RepoFX rig, the repo_arrive stinger, and
## this suite. Singleton.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_repo_gnome.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no audio output.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


class _StubCourt:
	var stories: Array = []
	func publish_story(headline: String, body: String, _kind: String) -> void:
		stories.append({"headline": headline, "body": body})


func _initialize() -> void:
	print("=== Cursing Gnomes repo_gnome tests ===")
	seed(20261008)
	_test_def()
	_test_label()
	_test_stinger_mapping()
	_test_stinger_synth()
	_test_spawn_singleton()
	_test_spawn_gating()
	_test_target_pick()
	_test_target_pick_nothing()
	_test_approach_to_hookup()
	_test_hookup_to_towing()
	_test_towing_repossess()
	_test_soldier_impound()
	_test_bank_called_off()
	_test_slain_story()
	_test_slain_wired()
	await _test_fx_rig()
	_test_unit_node_wiring()
	_test_art_file()
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


func _make_town(gs: GameState, tid: int, pos: Vector2) -> void:
	gs.towns[tid] = {"id": tid, "faction": "humans", "name": "T%d" % tid,
		"position": pos}


func _make_building(gs: GameState, btype: String, pos: Vector2,
		town_id: int, max_hp: float) -> Dictionary:
	return gs.add_building({
		"type": btype, "position": pos, "town_id": town_id,
		"faction": "humans", "alive": true, "complete": true,
		"max_hp": max_hp, "hp": max_hp,
	})


func _test_def() -> void:
	_check("def: repo_gnome in MONSTERS", DisasterSim.MONSTERS.has("repo_gnome"))
	var m: Dictionary = DisasterSim.MONSTERS.get("repo_gnome", {})
	_check("def: hp 500", float(m.get("hp", 0.0)) == 500.0)
	_check("def: dmg 0", float(m.get("dmg", 0.0)) == 0.0)
	_check("def: speed 95", float(m.get("speed", 0.0)) == 95.0)
	_check("def: desc mentions loveseat",
		String(m.get("desc", "")).to_lower().contains("loveseat"))


func _test_label() -> void:
	var w := _make_world()
	var d = w[1]
	_check("label: Ricky the Repo Gnome",
		d._label_for("repo_gnome") == "Ricky the Repo Gnome")


func _test_stinger_mapping() -> void:
	_check("stinger: repo_arrive mapped",
		DisasterSim.stinger_for_kind("repo_gnome") == "repo_arrive")


func _test_stinger_synth() -> void:
	# The backup-beeper stinger must synthesize without errors.
	var am = AudioManager.new()
	root.add_child(am)
	var segs: Array = am._disaster_stinger_segments("repo_arrive")
	_check("stinger: segments non-empty", not segs.is_empty())
	_check("stinger: first seg is a tone",
		String(segs[0].get("kind", "")) == "tone")
	_check("stinger: backup beeps present",
		absf(float(segs[0].get("freq", 0.0)) - 880.0) < 1.0)
	var wav = am._synthesize_sfx("repo_arrive")
	_check("stinger: synthesizes to a stream", wav != null)
	am.queue_free()


func _test_spawn_singleton() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var u1: Dictionary = d.spawn("repo_gnome", Vector2(2000, 2000))
	_check("spawn: ricky created", not u1.is_empty())
	_check("spawn: job set", String(u1.get("job", "")) == "repo_gnome")
	var u2: Dictionary = d.spawn("repo_gnome", Vector2(2100, 2100))
	_check("spawn: singleton — second spawn refused", u2.is_empty())
	gs.units.erase(u1)


func _test_spawn_gating() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	# Before REPO_MIN_DAY (10) the daily roll never fires.
	gs.day_number = 5
	d._repo_day = -1
	var before := gs.units.size()
	d._maybe_spawn_repo()
	_check("spawn: gated before min day", gs.units.size() == before)
	# On/after min day the roll runs (chance forced by re-rolling until it
	# fires — the gate is that the function runs at all, not the odds).
	gs.day_number = 50
	var fired := false
	for i in 60:
		d._repo_day = -1
		d._maybe_spawn_repo()
		if gs.units.size() > before:
			fired = true
			break
	_check("spawn: fires after min day (chance 0.03)", fired)
	for u in gs.units:
		if String(u.get("job", "")) == "repo_gnome":
			gs.units.erase(u)
			break


func _test_target_pick() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	_make_town(gs, 1, Vector2(1000, 1000))
	var fancy := _make_building(gs, "inn", Vector2(1010, 1010), 1, 900.0)
	var plain := _make_building(gs, "house", Vector2(1020, 1020), 1, 300.0)
	var gov := _make_building(gs, "courthouse", Vector2(1030, 1030), 1, 2000.0)
	gov["is_gov"] = true
	var blueprint := _make_building(gs, "shop", Vector2(1040, 1040), 1, 500.0)
	blueprint["complete"] = false
	var u: Dictionary = d.spawn("repo_gnome", Vector2(1000, 1000))
	d._repo_pick_target(u)
	_check("pick: fanciest eligible chosen",
		int(u.get("repo_bid", -1)) == int(fancy.get("id", -2)))
	_check("pick: gov building skipped", int(u.get("repo_bid", -1)) != int(gov.get("id", -2)))
	_check("pick: blueprint skipped",
		int(u.get("repo_bid", -1)) != int(blueprint.get("id", -2)))
	_check("pick: phase approach", String(u.get("repo_phase", "")) == "approach")
	gs.units.erase(u)


func _test_target_pick_nothing() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	# No buildings at all: wasted trip, nothing repoed, leaves.
	var u: Dictionary = d.spawn("repo_gnome", Vector2(2000, 2000))
	d._tick_repo(u, 95.0, 0.1)
	_check("nothing: repo_bid -1", int(u.get("repo_bid", -1)) == -1)
	_check("nothing: leaving flagged", bool(u.get("leaving", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("NOTHING WORTH REPOING"):
			found = true
	_check("nothing: gazette story", found)
	gs.units.erase(u)


func _test_approach_to_hookup() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.court_sys = _StubCourt.new()
	_make_town(gs, 1, Vector2(1000, 1000))
	var b := _make_building(gs, "inn", Vector2(1100, 1000), 1, 900.0)
	var u: Dictionary = d.spawn("repo_gnome", Vector2(1000, 1000))
	# First tick: picks target, announces arrival, walks in from 100px out.
	d._tick_repo(u, 95.0, 0.1)
	_check("approach: target locked", int(u.get("repo_bid", -1)) == int(b.get("id", -2)))
	_check("approach: phase approach", String(u.get("repo_phase", "")) == "approach")
	_check("approach: combat_state driving",
		String(u.get("combat_state", "")) == "driving")
	# Walk him to the hook distance and tick: hookup phase begins.
	u["position"] = Vector2(1050, 1000)
	d._tick_repo(u, 95.0, 0.1)
	_check("hookup: phase entered", String(u.get("repo_phase", "")) == "hookup")
	d._tick_repo(u, 95.0, 0.1)
	_check("hookup: combat_state hooking",
		String(u.get("combat_state", "")) == "hooking")
	gs.units.erase(u)


func _test_hookup_to_towing() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	gs.court_sys = _StubCourt.new()
	_make_town(gs, 1, Vector2(1000, 1000))
	var b := _make_building(gs, "inn", Vector2(1100, 1000), 1, 900.0)
	var u: Dictionary = d.spawn("repo_gnome", Vector2(1050, 1000))
	d._tick_repo(u, 95.0, 0.1)  # approach -> hookup
	u["repo_hook_left"] = 0.01
	d._tick_repo(u, 95.0, 0.1)  # hookup completes -> towing
	_check("towing: phase entered", String(u.get("repo_phase", "")) == "towing")
	_check("towing: building flagged towed", bool(b.get("towed", false)))
	gs.units.erase(u)


func _test_towing_repossess() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	_make_town(gs, 1, Vector2(2000, 2000))
	var b := _make_building(gs, "inn", Vector2(2100, 2000), 1, 900.0)
	var bid := int(b.get("id", -1))
	var u: Dictionary = d.spawn("repo_gnome", Vector2(2050, 2000))
	d._tick_repo(u, 95.0, 0.1)  # approach -> hookup
	u["repo_hook_left"] = 0.01
	d._tick_repo(u, 95.0, 0.1)  # hookup -> towing
	# Park him at the map edge so the tow completes on the next tick.
	u["position"] = Vector2(30, 30)
	d._tick_repo(u, 95.0, 0.1)
	_check("repossess: building erased", gs.get_building(bid).is_empty())
	_check("repossess: leaving flagged", bool(u.get("leaving", false)))
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("REPOSSESSED"):
			found = true
	_check("repossess: gazette story", found)
	gs.units.erase(u)


func _test_soldier_impound() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	_make_town(gs, 1, Vector2(2000, 2000))
	_make_building(gs, "inn", Vector2(2100, 2000), 1, 900.0)
	var u: Dictionary = d.spawn("repo_gnome", Vector2(2050, 2000))
	d._tick_repo(u, 95.0, 0.1)  # approach
	# A soldier (a real military job) closes in: truck impounded.
	var guard: Dictionary = gs.add_unit({
		"faction": "humans", "job": "soldier", "town_id": 1,
		"position": Vector2(2060, 2000), "alive": true,
		"hp": 100.0, "max_hp": 100.0,
	})
	d._tick_repo(u, 95.0, 0.1)
	_check("impound: leaving flagged", bool(u.get("leaving", false)))
	_check("impound: tow dropped", int(u.get("repo_bid", -1)) == -1)
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("TOW TRUCK IMPOUNDED"):
			found = true
	_check("impound: gazette story", found)
	gs.units.erase(u)
	gs.units.erase(guard)


func _test_bank_called_off() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	_make_town(gs, 1, Vector2(2000, 2000))
	var b := _make_building(gs, "inn", Vector2(2100, 2000), 1, 900.0)
	var u: Dictionary = d.spawn("repo_gnome", Vector2(2050, 2000))
	d._tick_repo(u, 95.0, 0.1)  # approach, timer armed
	u["repo_visit_left"] = 0.01
	d._tick_repo(u, 95.0, 0.1)  # timer expires -> bank called it off
	_check("called off: leaving flagged", bool(u.get("leaving", false)))
	_check("called off: building kept",
		not gs.get_building(int(b.get("id", -1))).is_empty())
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("BANK CALLED IT OFF"):
			found = true
	_check("called off: gazette story", found)
	gs.units.erase(u)


func _test_slain_story() -> void:
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("repo_gnome", Vector2(2000, 2000))
	u["alive"] = false
	d._repo_departed(u)
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("RICKY GOT REPOSSESSED"):
			found = true
	_check("slain: gazette story", found)
	gs.units.erase(u)


func _test_slain_wired() -> void:
	# The slain dispatch must route repo_gnome to _repo_departed.
	var w := _make_world()
	var gs: GameState = w[0]
	var d = w[1]
	var court := _StubCourt.new()
	gs.court_sys = court
	var u: Dictionary = d.spawn("repo_gnome", Vector2(2000, 2000))
	_check("slain: has disaster log id", int(u.get("disaster_log_id", -1)) >= 0)
	u["alive"] = false
	d._check_dead_disaster(u)
	var found := false
	for s in court.stories:
		if String(s.get("headline", "")).contains("RICKY GOT REPOSSESSED"):
			found = true
	_check("slain: story fires via _check_dead_disaster", found)
	gs.units.erase(u)


func _test_fx_rig() -> void:
	# RepoFX builds, pins above the sprite (via _ready, deferred one frame
	# like all Node2D ready callbacks), and emits paperwork.
	var fx := RepoFX.new()
	root.add_child(fx)
	await process_frame  # let _ready run
	_check("fx: z_index pins above sprite", fx.z_index == 2)
	_check("fx: stage_h defaults sane", fx.stage_h == 64.0)
	fx.stage_h = 76.8  # 1.2x monster scale
	# Step past one paper period and check before particles die.
	fx._process(1.0)
	_check("fx: papers emitted", int(fx.live_counts().get("papers", 0)) > 0)
	fx.queue_free()


func _test_unit_node_wiring() -> void:
	# Job registration, sprite texture, and monster scale.
	_check("wiring: job registered", "repo_gnome" in UnitNode._MONSTER_JOBS)
	var n := UnitNode.new()
	n.job = "repo_gnome"
	_check("wiring: monster scale 1.2x",
		absf(n._monster_scale() - UnitNode.SPRITE_WORLD_H * 1.2) < 0.01)
	var tex: Texture2D = n._monster_texture()
	_check("wiring: sprite texture resolves", tex != null)
	n.queue_free()


func _test_art_file() -> void:
	# The bespoke chibi art exists and is white-keyed (same artifact
	# definition as test_art_whitesweep.gd).
	var path := "assets/art/animals/repo_gnome.png"
	_check("art: file exists", FileAccess.file_exists(path))
	var img := Image.load_from_file(path)
	_check("art: loads as image", img != null)
	if img == null:
		return
	var border_px := 0
	for x in img.get_width():
		for y in [0, img.get_height() - 1]:
			var c := img.get_pixel(x, y)
			if c.a > 0.78 and c.r > 0.96 and c.g > 0.96 and c.b > 0.96:
				border_px += 1
	for y in img.get_height():
		for x in [0, img.get_width() - 1]:
			var c := img.get_pixel(x, y)
			if c.a > 0.78 and c.r > 0.96 and c.g > 0.96 and c.b > 0.96:
				border_px += 1
	_check("art: 0 border artifact px", border_px == 0)
