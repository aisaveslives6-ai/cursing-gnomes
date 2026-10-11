extends SceneTree
## Cursing Gnomes — DMV clerk ticket-window FX tests.
## 2026-10-08 (wake rapid-iteration): Dave the DMV Clerk shipped with
## bespoke art but a voiceless table. DMVClerkFX (Body child of his
## UnitNode) adds the voice: a hanging marquee sign that flips between
## "NOW SERVING #N" and "CLOSED FOR LUNCH" (pushed from the sim record
## via set_dmv_state), plus paper ticket stubs fluttering off the table.
## Pure _draw, ASCII-only text (iPhone tofu rule), freeze-position law.


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


func _initialize() -> void:
	await process_frame
	print("=== Cursing Gnomes DMV Clerk FX tests ===")
	_test_standalone_defaults()
	_test_stub_cycle_math()
	_test_sign_geometry()
	_test_state_transitions()
	_test_sign_face()
	await _test_draw_does_not_crash()
	_test_ascii_safe()
	_test_dmv_node_builds_fx()
	_test_other_jobs_have_no_fx()
	_test_rebuild_clears_ref()
	_test_sim_serving_field()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_standalone_defaults() -> void:
	var fx := DMVClerkFX.new()
	root.add_child(fx)
	_check("fx: default stage_h sane", fx.stage_h > 0.0)
	_check("fx: table closed by default (no marquee while walking in)",
		not fx._table_open)
	_check("fx: not on lunch by default", not fx._on_lunch)
	_check("fx: stub cycle in [0,1)",
		fx._stub_cycle(0) >= 0.0 and fx._stub_cycle(0) < 1.0)
	_check("fx: stub position descends with cycle",
		fx._stub_pos(0, 64.0).y <= fx._stub_pos(6, 64.0).y + 64.0)
	fx.free()


func _test_stub_cycle_math() -> void:
	var fx := DMVClerkFX.new()
	root.add_child(fx)
	var c0 := fx._stub_cycle(0)
	var c1 := fx._stub_cycle(1)
	# Golden-ratio desync: neighbors must not share a phase.
	_check("fx: stub cycles desynced", absf(c0 - c1) > 0.05)
	# Stub at cycle 0 starts at the table top; at ~1 it has landed.
	fx._t = 0.0
	var p_top := fx._stub_pos(0, 64.0)
	_check("fx: stub spawns near the table", p_top.y < -10.0)
	fx.free()


func _test_sign_geometry() -> void:
	var fx := DMVClerkFX.new()
	root.add_child(fx)
	var sr: Dictionary = fx._sign_rect(64.0)
	var pos: Vector2 = sr["pos"]
	_check("fx: sign rect has sane keys",
		sr.has("w") and sr.has("h"))
	_check("fx: sign hangs above the head", pos.y < -64.0)
	_check("fx: sign width sane", float(sr["w"]) > 32.0)
	fx.free()


func _test_state_transitions() -> void:
	var fx := DMVClerkFX.new()
	root.add_child(fx)
	fx.set_dmv_state(false, 3, false)
	_check("fx: folded table hides the rig", not fx.visible)
	_check("fx: table closed flag", not fx._table_open)
	fx.set_dmv_state(false, 7, true)
	_check("fx: open table shows the rig", fx.visible)
	_check("fx: serving number stored", fx._now_serving == 7)
	fx.set_dmv_state(true, 7, true)
	_check("fx: lunch flag stored", fx._on_lunch)
	# Lunch re-arms the flip animation.
	_check("fx: lunch triggers sign flip", fx._flip < 1.0)
	# Stub flow starves on lunch: run _process until flow drains.
	fx._table_open = true
	fx._flow = 1.0
	for i in 60:
		fx._process(0.05)
	_check("fx: lunch starves stub flow", fx._flow < 0.2)
	# Serving restores flow.
	fx.set_dmv_state(false, 8, true)
	for i in 60:
		fx._process(0.05)
	_check("fx: serving restores stub flow", fx._flow > 0.8)
	fx.free()


func _test_sign_face() -> void:
	var fx := DMVClerkFX.new()
	root.add_child(fx)
	fx.set_dmv_state(false, 5, true)
	fx._flip = 1.0
	fx._was_lunch = false
	_check("fx: serving face when open", fx._sign_face() == "serving")
	fx.set_dmv_state(true, 5, true)
	# Before the flip passes midpoint, the old face holds.
	fx._flip = 0.2
	_check("fx: face holds until mid-flip", fx._sign_face() == "serving")
	fx._flip = 0.8
	_check("fx: lunch face after mid-flip", fx._sign_face() == "lunch")
	fx._flip = 1.0
	_check("fx: lunch face when settled", fx._sign_face() == "lunch")
	fx.free()


func _test_draw_does_not_crash() -> void:
	var fx := DMVClerkFX.new()
	fx.stage_h = 80.0
	root.add_child(fx)
	# Folded table: _draw early-outs.
	fx.set_dmv_state(false, 0, false)
	fx.queue_redraw()
	await process_frame
	# Open + serving with a number: full marquee + stubs.
	fx.set_dmv_state(false, 42, true)
	fx.queue_redraw()
	await process_frame
	# Lunch face: flipped sign, no new stubs.
	fx.set_dmv_state(true, 42, true)
	fx.queue_redraw()
	await process_frame
	_check("fx: _draw survives all states", true)
	fx.free()


func _test_ascii_safe() -> void:
	# The FX may only ever print ASCII (iPhone tofu rule): scan the
	# source for non-ASCII bytes.
	var path := "res://scripts/world/dmv_clerk_fx.gd"
	var src: String = FileAccess.get_file_as_string(path)
	var bad := 0
	for i in src.length():
		if src.unicode_at(i) > 127:
			bad += 1
	_check("fx: source is ASCII-only (no tofu)", bad == 0)


func _make_node(p_job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(900 + _passed, "gnomes", p_job, Vector2(100, 100), "m")
	return un


func _test_dmv_node_builds_fx() -> void:
	var un := _make_node("dmv_clerk")
	_check("dmv_clerk: ticket-window FX built",
		un._dmv_fx != null and is_instance_valid(un._dmv_fx))
	_check("dmv_clerk: FX is a Body child",
		un._dmv_fx != null and un._dmv_fx.get_parent() == un._body)
	_check("dmv_clerk: FX stage_h matches monster scale",
		un._dmv_fx != null
		and absf(un._dmv_fx.stage_h - un._monster_scale()) < 0.01)
	_check("dmv_clerk: FX renders above the sprite",
		un._dmv_fx != null and un._sprite != null
		and un._dmv_fx.z_index > un._sprite.z_index)
	# State push path (world sync drives this per frame).
	un.set_dmv_state(false, 9, true)
	_check("dmv_clerk: set_dmv_state reaches the rig",
		un._dmv_fx != null and un._dmv_fx._now_serving == 9
		and un._dmv_fx._table_open)
	un.set_dmv_state(true, 9, true)
	_check("dmv_clerk: lunch push reaches the rig",
		un._dmv_fx != null and un._dmv_fx._on_lunch)
	un.free()


func _test_other_jobs_have_no_fx() -> void:
	for j in ["mlm_bro", "doomscroller", "karaoke_barbarian", "worker",
			"warranty_salesman"]:
		var un := _make_node(j)
		_check("no-fx job %s: no DMV marquee" % j, un._dmv_fx == null)
		un.free()


func _test_rebuild_clears_ref() -> void:
	var un := _make_node("dmv_clerk")
	var old_fx: DMVClerkFX = un._dmv_fx
	_check("rebuild: FX present before rebuild", old_fx != null)
	un._build()
	# Rebuild frees the old Body subtree: the ref must not dangle —
	# _build recreates the rig for the still-DMV job.
	_check("rebuild: ref points at a fresh live instance",
		un._dmv_fx != null and is_instance_valid(un._dmv_fx)
		and un._dmv_fx != old_fx)
	un.free()


func _test_sim_serving_field() -> void:
	# The sim must publish dmv_now_serving for the marquee: boot the
	# DisasterSim path and drive one serve tick on a ticketed citizen.
	var gs := GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	var combat := SimCombat.new(gs)
	var dis := DisasterSim.new(gs, combat)
	var clerk: Dictionary = {"id": 1, "alive": true, "job": "dmv_clerk",
		"faction": "monster", "position": Vector2(0, 0),
		"dmv_serve_cd": 0.0, "dmv_skimmed": 0.0}
	var punter: Dictionary = {"id": 2, "alive": true, "job": "worker",
		"faction": "gnomes", "position": Vector2(10, 0),
		"waiting_in_line": true, "dmv_ticket": 12}
	gs.units.append(clerk)
	gs.units.append(punter)
	dis._dmv_serve(clerk, Vector2(0, 0), 0.1)
	_check("sim: serve publishes dmv_now_serving",
		int(clerk.get("dmv_now_serving", 0)) == 12)
	_check("sim: punter leaves the line", not bool(punter["waiting_in_line"]))
