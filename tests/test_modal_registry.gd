extends SceneTree
## Cursing Gnomes — system-modal registry tests (launch readiness 2026-10-06).
##
## The phone's _build_shell() frees every direct child on rotation/shell
## rebuild. Open Approve/Deny system modals (shop-build petitions, strategic
## proposals, diplomacy war confirms, insult inputs) must survive rotation
## via the registry; dismissed/decided ones must never be resurrected.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_modal_registry.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes modal-registry tests ===")
	_test_register_unregister()
	_test_dismiss_unregisters_and_frees()
	_test_snapshot_captures_fields()
	_test_snapshot_captures_insult_draft()
	_test_diplo_confirm_registers()
	_test_diplo_insult_registers_with_entry()
	_test_dismissed_never_resurrected()
	_test_reshow_skips_decided_petition()
	_test_reshow_restores_open_petition()
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


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "phone": phone, "court": court}


func _new_ui(w: Dictionary) -> PhoneUI:
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(w["gs"], w["phone"], w["court"])
	return ui


func _test_register_unregister() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	var o1 := Control.new()
	var o2 := Control.new()
	ui._register_modal({"type": "x"}, o1)
	_check("register grows registry", ui._open_modals.size() == 1)
	ui._register_modal({"type": "y"}, o2)
	_check("register second", ui._open_modals.size() == 2)
	ui._unregister_modal(o1)
	_check("unregister shrinks", ui._open_modals.size() == 1)
	_check("unregister removes right entry",
		String((ui._open_modals[0] as Dictionary).get("type", "")) == "y")
	ui._unregister_modal(Control.new())
	_check("unregister unknown keeps size", ui._open_modals.size() == 1)
	o1.free()
	o2.free()
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_dismiss_unregisters_and_frees() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	var o1 := PanelContainer.new()
	var o2 := PanelContainer.new()
	ui.add_child(o1)
	ui.add_child(o2)
	ui._register_modal({"type": "a"}, o1)
	ui._register_modal({"type": "b"}, o2)
	ui._dismiss_modal(o1)
	_check("dismiss unregisters", ui._open_modals.size() == 1)
	_check("dismiss frees overlay", o1.is_queued_for_deletion())
	_check("dismiss keeps sibling", ui._open_modals[0].get("overlay") == o2)
	# Dismissing an already-gone overlay is safe.
	ui._dismiss_modal(o1)
	_check("double dismiss safe", ui._open_modals.size() == 1)
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_snapshot_captures_fields() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	var flag: Array = [false]
	var oc := func() -> void: flag[0] = true
	var o := Control.new()
	ui._register_modal({"type": "diplo_confirm", "action": "Declare War",
		"faction_name": "Ogres", "question": "Do you wish to declare war?",
		"confirm_text": "Declare War", "on_confirm": oc}, o)
	var snap: Array = ui._snapshot_modals()
	_check("snapshot one entry", snap.size() == 1)
	var s: Dictionary = snap[0]
	_check("snapshot type", String(s.get("type", "")) == "diplo_confirm")
	_check("snapshot action", String(s.get("action", "")) == "Declare War")
	_check("snapshot faction_name", String(s.get("faction_name", "")) == "Ogres")
	_check("snapshot question",
		String(s.get("question", "")) == "Do you wish to declare war?")
	_check("snapshot confirm_text",
		String(s.get("confirm_text", "")) == "Declare War")
	_check("snapshot callable survives", (s.get("on_confirm") as Callable).is_valid())
	# The freed overlay node itself must never be carried into the snapshot.
	_check("snapshot carries no overlay node", not s.has("overlay"))
	o.free()
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_snapshot_captures_insult_draft() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	var le := LineEdit.new()
	le.text = "your mother was a hamster"
	ui._register_modal({"type": "diplo_insult", "faction": "ogres",
		"faction_name": "Ogres", "entry": le}, Control.new())
	var snap: Array = ui._snapshot_modals()
	_check("insult snapshot draft",
		String(snap[0].get("draft", "")) == "your mother was a hamster")
	# A freed entry is a blank draft, not a crash.
	le.free()
	var snap2: Array = ui._snapshot_modals()
	_check("freed entry -> empty draft, no crash",
		String(snap2[0].get("draft", "X")) == "")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_diplo_confirm_registers() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	var fired: Array = [false]
	var oc := func() -> void: fired[0] = true
	ui._diplo_confirm("Declare War", "Ogres", "Do you wish to declare war?",
		"Declare War", oc)
	_check("diplo_confirm registers", ui._open_modals.size() == 1)
	var e: Dictionary = ui._open_modals[0]
	_check("diplo_confirm type",
		String(e.get("type", "")) == "diplo_confirm")
	_check("diplo_confirm action", String(e.get("action", "")) == "Declare War")
	# Snapshot -> clear -> reshow: the still-open confirm comes back.
	var snap: Array = ui._snapshot_modals()
	ui._open_modals.clear()
	ui._reshow_modal(snap[0])
	_check("diplo_confirm reshown after rotation", ui._open_modals.size() == 1)
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_diplo_insult_registers_with_entry() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	ui._diplo_insult_input("ogres", "Ogres", "you smell of elderberries")
	_check("diplo_insult registers", ui._open_modals.size() == 1)
	var e: Dictionary = ui._open_modals[0]
	_check("diplo_insult type", String(e.get("type", "")) == "diplo_insult")
	var snap: Array = ui._snapshot_modals()
	_check("insult draft survives snapshot",
		String(snap[0].get("draft", "")) == "you smell of elderberries")
	ui._open_modals.clear()
	ui._reshow_modal(snap[0])
	_check("insult reshown after rotation", ui._open_modals.size() == 1)
	var e2: Dictionary = ui._open_modals[0]
	var le := e2.get("entry") as LineEdit
	_check("reshown insult prefilled",
		le != null and le.text == "you smell of elderberries")
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_dismissed_never_resurrected() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	ui._diplo_confirm("Declare War", "Ogres", "Do you wish to declare war?",
		"Declare War", Callable())
	var overlay: Control = (ui._open_modals[0] as Dictionary).get("overlay")
	ui._dismiss_modal(overlay)  # player cancelled
	_check("cancelled modal unregistered", ui._open_modals.is_empty())
	var snap: Array = ui._snapshot_modals()
	_check("dismissed modal never snapshotted", snap.is_empty())
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


func _test_reshow_skips_decided_petition() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	var gs: GameState = w["gs"]
	var pet := SimPetitions.new(gs)
	gs.petitions = pet
	pet.petitions.append({"id": 7, "status": "decided",
		"building_type": "shop", "faction": "humans"})
	ui._reshow_modal({"type": "build_request", "pid": 7})
	_check("decided petition not reshown", ui._open_modals.is_empty())
	ui._reshow_modal({"type": "build_request", "pid": 99999})
	_check("unknown petition not reshown", ui._open_modals.is_empty())
	ui.queue_free()
	gs.queue_free()


func _test_reshow_restores_open_petition() -> void:
	var w: Dictionary = _new_world()
	var ui := _new_ui(w)
	var gs: GameState = w["gs"]
	var pet := SimPetitions.new(gs)
	gs.petitions = pet
	pet.petitions.append({"id": 8, "status": "open",
		"building_type": "shop", "faction": "humans"})
	ui._reshow_modal({"type": "build_request", "pid": 8})
	_check("open petition reshown", ui._open_modals.size() == 1)
	var e: Dictionary = ui._open_modals[0]
	_check("reshown entry type/pid",
		String(e.get("type", "")) == "build_request" and int(e.get("pid", -1)) == 8)
	# Clean up the shown overlay so the headless tree stays tidy.
	ui._dismiss_modal(e.get("overlay"))
	_check("reshown modal dismisses cleanly", ui._open_modals.is_empty())
	ui.queue_free()
	gs.queue_free()
