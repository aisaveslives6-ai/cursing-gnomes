extends SceneTree
## Jeremy 2026-10-07: petitions finally reach the ruler. SimRoyalCourt emitted
## petition_opened for every petition, but nothing ever listened — petitions
## sat silently in the Gazette's Messages tab and rulers never knew their
## subjects (or foreign envoys) were begging. Now SimPhone listens: the
## petitioner DMs the ruler directly (blockable, deduped, thread rises as
## unanswered) and a toast announces it.
##
## Run: Godot --headless --path . -s res://tests/test_petition_dm.gd

var _passed := 0
var _failed := 0
var _failures: Array = []
var _toasts: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("FAIL: ", name)


func _initialize() -> void:
	_test_dm_with_talk()
	_test_dm_text_fallback()
	_test_blocked_no_dm_but_toast()
	_test_sandbox_silent()
	_test_dead_unit_no_crash()
	print("test_petition_dm: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	_toasts.clear()
	gs.bus.toast.connect(func(t: String) -> void: _toasts.append(t))
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var mayor: Dictionary = gs.add_unit({
		"faction": "humans", "alive": true, "job": "mayor",
		"mind": {"name": "Mayor Pudgebottom", "gov_role": "mayor"},
	})
	return {"gs": gs, "phone": phone, "court": court, "mayor": mayor}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


func _thread_of(phone, unit_id: int) -> Dictionary:
	return phone._thread("u%d" % unit_id)


## Domestic petition with a "talk" line: DM uses the talk voice + Gazette
## pointer; thread rises unanswered; toast names the petitioner.
func _test_dm_with_talk() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone = w["phone"]
	var mayor: Dictionary = w["mayor"]
	var mid := int(mayor["id"])
	var p := {
		"from_key": "u%d" % mid, "from_name": "Mayor Pudgebottom",
		"role": "Mayor", "kind": "mayor_grain",
		"talk": "The granaries echo, sire. Empty shelves, empty bellies.",
		"text": "formal petition text",
	}
	gs.bus.petition_opened.emit(p)
	var th: Dictionary = _thread_of(phone, mid)
	var msgs: Array = th["messages"]
	_check(msgs.size() == 1, "talk: one DM queued")
	var dm := String((msgs[msgs.size() - 1] as Dictionary).get("text", ""))
	_check("The granaries echo, sire." in dm, "talk: DM uses the talk line")
	_check("Gazette" in dm, "talk: DM points at the Gazette")
	_check(int(th["unread"]) == 1, "talk: thread marked unread")
	_check(bool(th["answered"]) == false, "talk: thread rises as unanswered")
	_check(_toasts.size() == 1, "talk: one toast fired")
	_check("Mayor Pudgebottom" in String(_toasts[0]), "talk: toast names petitioner")
	_check("Mayor" in String(_toasts[0]), "talk: toast names role")
	_free_world(w)


## Petition without a talk line (diplomatic/envoy path): DM falls back to
## the petition text, trimmed to DM length.
func _test_dm_text_fallback() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone = w["phone"]
	var court = w["court"]
	var mayor: Dictionary = w["mayor"]
	var mid := int(mayor["id"])
	var long_text := "The elves demand tribute: 200 gold, or their spears will do the asking. Their war host darkens your border and their bards already sing of your fall, sire, in verses both rude and catchy."
	court.petition(mayor, "tribute", long_text, ["Accept tribute", "Refuse"] as Array[String])
	var th: Dictionary = _thread_of(phone, mid)
	var msgs: Array = th["messages"]
	_check(msgs.size() == 1, "fallback: one DM queued")
	var dm := String((msgs[msgs.size() - 1] as Dictionary).get("text", ""))
	_check("The elves demand tribute" in dm, "fallback: DM uses petition text")
	_check(dm.length() < long_text.length() + 80, "fallback: DM trims long text")
	_check("Gazette" in dm, "fallback: DM points at the Gazette")
	_check(_toasts.size() == 1, "fallback: toast fired")
	_free_world(w)


## Blocked petitioner: no DM (block respected), but the court's public
## toast still fires — the petition exists in the Gazette regardless.
func _test_blocked_no_dm_but_toast() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone = w["phone"]
	var mayor: Dictionary = w["mayor"]
	var mid := int(mayor["id"])
	phone.block_citizen(mid)
	gs.bus.petition_opened.emit({
		"from_key": "u%d" % mid, "from_name": "Mayor Pudgebottom",
		"role": "Mayor", "kind": "mayor_grain",
		"talk": "The granaries echo, sire.",
	})
	var th: Dictionary = _thread_of(phone, mid)
	_check((th["messages"] as Array).is_empty(), "blocked: no DM queued")
	_check(_toasts.size() == 1, "blocked: toast still fires")
	_free_world(w)


## Sandbox observer mode: no crown, no DM, no toast.
func _test_sandbox_silent() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone = w["phone"]
	var mayor: Dictionary = w["mayor"]
	var mid := int(mayor["id"])
	gs.player_faction = ""
	gs.bus.petition_opened.emit({
		"from_key": "u%d" % mid, "from_name": "Mayor Pudgebottom",
		"role": "Mayor", "kind": "mayor_grain",
		"talk": "The granaries echo, sire.",
	})
	var th: Dictionary = _thread_of(phone, mid)
	_check((th["messages"] as Array).is_empty(), "sandbox: no DM queued")
	_check(_toasts.is_empty(), "sandbox: no toast fired")
	_free_world(w)


## Dead unit / garbage from_key: silent no-op, never a crash.
func _test_dead_unit_no_crash() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone = w["phone"]
	var mayor: Dictionary = w["mayor"]
	var mid := int(mayor["id"])
	mayor["alive"] = false
	gs.bus.petition_opened.emit({"from_key": "u%d" % mid, "talk": "Boo."})
	gs.bus.petition_opened.emit({"from_key": "bogus", "talk": "Boo."})
	gs.bus.petition_opened.emit({})
	var th: Dictionary = _thread_of(phone, mid)
	_check((th["messages"] as Array).is_empty(), "dead: no DM for dead unit")
	_check(_toasts.is_empty(), "dead: no toast for dead/garbage petitions")
	_free_world(w)
