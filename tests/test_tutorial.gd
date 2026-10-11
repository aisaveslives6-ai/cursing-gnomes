extends SceneTree
## Cursing Gnomes — "First Reign" AAA tutorial remaster tests (Jeremy 2026-10-11).
##
## New games ask "Are you a first-time player?" — YES runs the full guided
## tour, "I know how, let me play dammit" skips straight in. The 12-step
## tour teaches the real game (camera, select, build, gather, workers,
## roads, phone, military, disasters, trade) in Ethos's voice, with
## animated tap-here callouts over the real HUD, and points the player at
## Mr Smart Bitch in the phone contacts. Tests drive completion via bus
## signals and the _probe hook (headless: no live selection/camera/phone).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_tutorial.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

# Snapshot of the real tutorial.cfg so tests never clobber Jeremy's state.
var _cfg_had_file := false
var _cfg_bytes: PackedByteArray = PackedByteArray()


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_director() -> TutorialDirector:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves"])
	gs.player_faction = "humans"
	var d := TutorialDirector.new(gs)
	root.add_child(d)
	d.setup_world(null)  # headless: no live world refs; _probe drives checks
	return d


func _free_director(d: TutorialDirector) -> void:
	(d._gs as GameState).free()
	d.free()


func _snapshot_cfg() -> void:
	_cfg_had_file = FileAccess.file_exists(TutorialDirector.SAVE_PATH)
	if _cfg_had_file:
		_cfg_bytes = FileAccess.get_file_as_bytes(TutorialDirector.SAVE_PATH)
	else:
		if FileAccess.file_exists(TutorialDirector.SAVE_PATH):
			DirAccess.remove_absolute(TutorialDirector.SAVE_PATH)


func _restore_cfg() -> void:
	if _cfg_had_file:
		var f := FileAccess.open(TutorialDirector.SAVE_PATH, FileAccess.WRITE)
		f.store_buffer(_cfg_bytes)
		f.close()
	else:
		if FileAccess.file_exists(TutorialDirector.SAVE_PATH):
			DirAccess.remove_absolute(TutorialDirector.SAVE_PATH)


func _initialize() -> void:
	print("=== Cursing Gnomes tutorial remaster tests ===")
	_run.call_deferred()


func _run() -> void:
	_snapshot_cfg()
	_test_steps_defined()
	_test_required_topics()
	_test_smart_bitch_mentioned()
	_test_offer_flow()
	_test_dammit_skips()
	_test_take_tour_starts()
	_test_full_tour_flow()
	_test_out_of_order_build()
	_test_enemy_events_ignored()
	_test_skip_mid_tour()
	_test_callout_probe()
	_test_no_double_offer()
	_test_tutorial_music_mock()
	_restore_cfg()
	print("  passed: ", _passed, " failed: ", _failed)
	if _failed > 0:
		for f: String in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)


func _test_steps_defined() -> void:
	var ids := {}
	for s in TutorialDirector.STEPS:
		var sid := String(s["id"])
		_check("steps: id unique: " + sid, not ids.has(sid))
		ids[sid] = true
		_check("steps: title non-empty: " + sid, String(s["title"]) != "")
		_check("steps: body non-empty: " + sid, String(s["body"]) != "")
		_check("steps: callout key present: " + sid, s.has("callout"))
	_check("steps: 12 steps", TutorialDirector.STEPS.size() == 12)
	_check("steps: starts at welcome",
		String(TutorialDirector.STEPS[0]["id"]) == "welcome")
	_check("steps: ends at done",
		String(TutorialDirector.STEPS[11]["id"]) == "done")


## Jeremy's required topics are all covered by a step.
func _test_required_topics() -> void:
	var ids := []
	for s in TutorialDirector.STEPS:
		ids.append(String(s["id"]))
	for need in ["camera", "build", "gather", "workers", "roads", "phone",
			"military", "disasters", "trade"]:
		_check("topics: has " + need, ids.has(need))


## The tutorial points players at Mr Smart Bitch (phone + finale).
func _test_smart_bitch_mentioned() -> void:
	var bodies := ""
	for s in TutorialDirector.STEPS:
		bodies += String(s["body"]) + "\n"
	_check("smartbitch: mentioned", bodies.find("Mr Smart Bitch") >= 0)
	var phone_body := ""
	var done_body := ""
	for s in TutorialDirector.STEPS:
		if String(s["id"]) == "phone":
			phone_body = String(s["body"])
		if String(s["id"]) == "done":
			done_body = String(s["body"])
	_check("smartbitch: in phone step",
		phone_body.find("Mr Smart Bitch") >= 0)
	_check("smartbitch: in done step", done_body.find("Mr Smart Bitch") >= 0)


## The first-time player prompt: YES tours, "let me play dammit" skips.
func _test_offer_flow() -> void:
	var d := _new_director()
	_check("offer: not completed at start", not TutorialDirector.is_completed())
	d.maybe_offer()
	d.tick(TutorialDirector.OFFER_DELAY + 0.5)
	_check("offer: card shown after delay", d._offer.visible)
	# Prompt asks the first-time question (not the old "New to the realm?").
	var found := false
	for child in d._offer.get_children():
		for c2 in (child as Node).find_children("*", "Label", true, false):
			if (c2 as Label).text.find("first-time player") >= 0:
				found = true
	_check("offer: asks first-time player", found)
	_free_director(d)


func _test_dammit_skips() -> void:
	var d := _new_director()
	d.maybe_offer()
	d.tick(TutorialDirector.OFFER_DELAY + 0.5)
	# The "I know how, let me play dammit" button skips straight in.
	var dammit: Button = null
	for b in d._offer.find_children("*", "Button", true, false):
		if (b as Button).text.find("let me play dammit") >= 0:
			dammit = b as Button
	_check("dammit: button exists", dammit != null)
	if dammit != null:
		dammit.pressed.emit()
	_check("dammit: skip marks completed", TutorialDirector.is_completed())
	_check("dammit: card hidden", not d._offer.visible)
	_check("dammit: not active", not d.is_active())
	_free_director(d)


func _test_take_tour_starts() -> void:
	var d := _new_director()
	d.maybe_offer()
	d.tick(TutorialDirector.OFFER_DELAY + 0.5)
	d.start()  # "Yes, teach me"
	_check("start: active", d.is_active())
	_check("start: on welcome", d.step_id() == "welcome")
	_check("start: banner visible", d._banner.visible)
	_check("start: title set", d._title_lbl.text == "A new ruler approaches")
	_check("start: step counter", d._step_lbl.text == "1 / 12")
	_check("start: action button shown", d._action_btn.visible)
	_free_director(d)


## Drives the entire 12-step tour: buttons, bus signals, _probe hook.
func _test_full_tour_flow() -> void:
	var d := _new_director()
	d.start()
	d._on_action()  # welcome -> camera
	_check("flow: welcome->camera", d.step_id() == "camera")
	d._probe = {"camera_moved": true}
	d.tick(0.1)
	_check("flow: camera->select", d.step_id() == "select")
	d._probe = {"selected": true}
	d.tick(0.1)
	_check("flow: select->build", d.step_id() == "build")
	d._gs.bus.building_placed.emit({"faction": "humans", "type": "house"})
	d.tick(0.1)
	_check("flow: build->gather", d.step_id() == "gather")
	d._gs.bus.resource_changed.emit("humans", "wood", 100.0)
	d._gs.bus.resource_changed.emit("humans", "wood", 150.0)
	d.tick(0.1)
	_check("flow: gather->workers", d.step_id() == "workers")
	d._on_action()
	_check("flow: workers->roads", d.step_id() == "roads")
	d._on_action()
	_check("flow: roads->phone", d.step_id() == "phone")
	d._probe = {"phone_open": true}
	d.tick(0.1)
	_check("flow: phone->military", d.step_id() == "military")
	d._on_action()
	_check("flow: military->disasters", d.step_id() == "disasters")
	d._on_action()
	_check("flow: disasters->trade", d.step_id() == "trade")
	d._on_action()
	_check("flow: trade->done", d.step_id() == "done")
	d._on_action()  # "Rule!" -> finish
	_check("flow: tour finished", not d.is_active())
	_check("flow: completed persisted", TutorialDirector.is_completed())
	_check("flow: banner hidden", not d._banner.visible)
	_free_director(d)


## Acting ahead of the tour counts: building during an early step
## auto-completes the build step when it is reached.
func _test_out_of_order_build() -> void:
	var d := _new_director()
	d.start()
	d._gs.bus.building_placed.emit({"faction": "humans", "type": "sawmill"})
	_check("ooo: flag set early", d._did_build)
	d._on_action()  # welcome -> camera
	d._probe = {"camera_moved": true}
	d.tick(0.1)  # -> select
	d._probe = {"selected": true}
	d.tick(0.1)  # -> build ...
	d.tick(0.1)  # ... instantly done (flag was set early) -> gather
	_check("ooo: build auto-completed", d.step_id() == "gather")
	_free_director(d)


func _test_enemy_events_ignored() -> void:
	var d := _new_director()
	d.start()
	d._gs.bus.building_placed.emit({"faction": "elves", "type": "house"})
	d._gs.bus.unit_spawned.emit({"faction": "elves", "job": "worker"})
	d._gs.bus.resource_changed.emit("elves", "wood", 999.0)
	_check("enemy: build ignored", not d._did_build)
	_check("enemy: train ignored", not d._did_train)
	_check("enemy: gather ignored", not d._did_gather)
	_free_director(d)


func _test_skip_mid_tour() -> void:
	var d := _new_director()
	d.start()
	d._on_action()  # -> camera
	d.skip()
	_check("skip: inactive", not d.is_active())
	_check("skip: banner hidden", not d._banner.visible)
	_check("skip: callout hidden", not d._callout.visible)
	_check("skip: completed", TutorialDirector.is_completed())
	_free_director(d)


## The animated callout resolves through the probe and hides cleanly.
func _test_callout_probe() -> void:
	var d := _new_director()
	d._probe = {"callout_pos": Vector2(400, 300)}
	d.start()
	# welcome has no callout.
	_check("callout: hidden on welcome", not d._callout.visible)
	d._on_action()  # -> camera (no callout)
	d._probe = {"camera_moved": true, "callout_pos": Vector2(400, 300)}
	d.tick(0.1)  # -> select (world_unit ring, no screen callout)
	_check("callout: hidden on select", not d._callout.visible)
	d._probe = {"selected": true, "callout_pos": Vector2(400, 300)}
	d.tick(0.1)  # -> build (hud_build callout via probe)
	_check("callout: shown on build", d._callout.visible)
	_check("callout: at probe pos", d._callout.position == Vector2(400, 300))
	_free_director(d)


func _test_no_double_offer() -> void:
	# Completed by earlier tests; the offer must never show again.
	var d := _new_director()
	_check("no-double: completed still true", TutorialDirector.is_completed())
	d.maybe_offer()
	d.tick(30.0)
	_check("no-double: offer not shown", not d._offer.visible)
	_free_director(d)


## Jeremy's track underscores the tour: set_audio wires the manager and
## start() asks it for the tutorial music bed. A mock records the call —
## the seamless/fade logic itself is covered in test_tutorial_music.gd.
class _MockAudio:
	extends Node
	var calls := 0
	func play_tutorial_music() -> void:
		calls += 1


func _test_tutorial_music_mock() -> void:
	var d := _new_director()
	var mock := _MockAudio.new()
	root.add_child(mock)
	_check("music: no audio by default", d._audio == null)
	d.set_audio(mock)
	_check("music: audio wired", d._audio == mock)
	d.start()
	_check("music: tutorial bed requested", mock.calls == 1)
	# Silent without a manager: no crash, no call.
	var d2 := _new_director()
	d2.start()
	_check("music: silent start safe", d2._audio == null)
	mock.free()
	_free_director(d)
	_free_director(d2)
