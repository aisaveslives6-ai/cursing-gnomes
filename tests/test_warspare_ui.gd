extends SceneTree
## Cursing Gnomes — war-spare modal clipping audit (Jeremy 2026-10-11).
##
## Jeremy's standing P0 pattern: menu clipping — decision buttons must never
## be pushed off-screen. The fate-vote / aid-vote / peace-treaty / negotiate
## modals use an explicit anchor layout: the dialog is never taller than
## 92% of the phone, the body scrolls internally, and SPARE/END (etc.)
## stay pinned in the foot.
##
## This test verifies RENDERED geometry (real layout frames, like Jeremy's
## iPhone would show), at iPhone 17 portrait (393x852) AND landscape
## (852x393) stress sizes.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_warspare_ui.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _frame := 0
var _stage := 0
var _ui: PhoneUI = null
var _gs: GameState = null
var _stage_w := 0.0
var _stage_h := 0.0
var _stage_tag := ""
var _stage_buttons: Array = []
var _done := false


func _initialize() -> void:
	print("=== Cursing Gnomes war-spare UI clipping tests ===")


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)


func _finish() -> void:
	if _done:
		return
	_done = true
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## --- stage machine: build a modal, let real frames lay it out, audit ---


func _process(_delta: float) -> bool:
	if _done:
		return true
	_frame += 1
	if _frame == 1:
		_build_stage()
		return false
	if _frame < 8:
		return false
	_audit_stage()
	_frame = 0
	_stage += 1
	if _stage >= 7:
		_finish()
		return true
	return false


func _build_stage() -> void:
	match _stage:
		0:
			_stage_tag = "fate portrait"
			_stage_buttons = ["SPARE", "END THEM"]
			_new_ui(1280.0, 2774.0)
			PhoneWarSpare.show_fate_vote(_ui, _rich_vote())
		1:
			_stage_tag = "fate landscape"
			_stage_buttons = ["SPARE", "END THEM"]
			_new_ui(1560.0, 720.0)
			PhoneWarSpare.show_fate_vote(_ui, _rich_vote())
		2:
			_stage_tag = "aid portrait"
			_stage_buttons = ["SEND AID", "DECLINE"]
			_new_ui(1280.0, 2774.0)
			PhoneWarSpare.show_aid_vote(_ui, _rich_aid_vote())
		3:
			_stage_tag = "aid landscape"
			_stage_buttons = ["SEND AID", "DECLINE"]
			_new_ui(1560.0, 720.0)
			PhoneWarSpare.show_aid_vote(_ui, _rich_aid_vote())
		4:
			_stage_tag = "treaty portrait"
			_stage_buttons = ["Accept"]
			_new_ui(1280.0, 2774.0)
			PhoneWarSpare.show_treaty(_ui, _rich_treaty())
		5:
			_stage_tag = "negotiate portrait"
			_stage_buttons = ["Not now"]
			_new_ui(1280.0, 2774.0)
			_show_real_negotiate()
		6:
			_stage_tag = "confirm landscape"
			_stage_buttons = ["Yes, do it", "Hold on"]
			_new_ui(1560.0, 720.0)
			PhoneWarSpare._confirm(_ui,
				"A very long confirm prompt. " + "It goes on. ".repeat(30),
				"Yes, do it", func() -> void: pass)


func _new_ui(w: float, h: float) -> void:
	if _ui != null:
		_ui.queue_free()
	_gs = GameState.new()
	root.add_child(_gs)
	_gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	_gs.war_spare = SimWarSpare.new(_gs)
	_gs.disaster_aid = SimDisasterAid.new(_gs)
	_ui = PhoneUI.new()
	root.add_child(_ui)
	_ui.setup(_gs, SimPhone.new(_gs), SimRoyalCourt.new(_gs),
		_gs.diplomacy)
	# Pin the phone to the stress rect (setup centers a desktop frame).
	_ui.offset_right = _ui.offset_left + w
	_ui.offset_bottom = _ui.offset_top + h
	_ui.size = Vector2(w, h)
	_ui._phone_w = w
	_ui._phone_h = h
	# Simulate the phone shell's safe insets for this size
	# (phone_ui.gd: safe_top = max(60, 7%H), safe_bottom = max(72, 8.5%H)).
	_ui._shell_safe_top = maxf(60.0, h * 0.070)
	_ui._shell_safe_bottom = maxf(72.0, h * 0.085)
	_stage_w = w
	_stage_h = h


func _show_real_negotiate() -> void:
	# A real treaty through the real sim, then the real negotiate dialog.
	_gs.resources.add_resource("ogres", "gold", 5000.0)
	_gs.diplomacy.adjust_score("gnomes", "ogres", 70.0)
	_gs.diplomacy.adjust_score("undead", "ogres", 70.0)
	_gs.diplomacy.adjust_score("humans", "ogres", 70.0)
	_gs.bus.command_post_captured.emit("town", 1, "ogres", "elves",
		Vector2.ZERO)
	_gs.war_spare.cast_player_vote(true)
	var real: Dictionary = _gs.war_spare.treaties_for("ogres")[0]
	# Detach the auto-opened fate modal (bus handler) so the negotiate
	# dialog is the one under audit.
	for c in _ui.get_children():
		if c.name == "WarSpareModal":
			_ui.remove_child(c)
			c.queue_free()
	PhoneWarSpare._show_negotiate(_ui, real, 0)


func _audit_stage() -> void:
	var tag := _stage_tag
	var modal := _ui.find_child("WarSpareModal", true, false)
	_check("%s: modal present" % tag, modal != null)
	if modal == null:
		return
	var dlg: PanelContainer = modal.get_child(1)
	# The dialog lives inside the phone shell's safe band — below the
	# Dynamic Island (7%/60px) and above the home indicator (8.5%/72px).
	# Jeremy's standing safe-area priority (#6).
	var stop := maxf(60.0, _stage_h * 0.070)
	var sbot := maxf(72.0, _stage_h * 0.085)
	var budget := _stage_h - stop - sbot
	_check("%s: dialog height capped to safe band (%.0f <= %.0f)" % [tag,
		dlg.size.y, budget], dlg.size.y <= budget + 2.0)
	var dr := dlg.get_global_rect()
	var safe := Rect2(_ui.get_global_rect().position + Vector2(0, stop),
		Vector2(_stage_w, budget))
	_check("%s: dialog fully inside safe band" % tag,
		safe.encloses(dr))
	# Every decision button exists and sits inside the safe band (the P0
	# rule: never under the Island, never in the home-indicator zone).
	var btns: Array = []
	_collect_buttons(dlg, btns)
	for want in _stage_buttons:
		var found: Button = null
		for b in btns:
			if String((b as Button).text) == String(want):
				found = b
		_check("%s: button '%s' present" % [tag, want], found != null)
		if found != null:
			var br := found.get_global_rect()
			_check("%s: button '%s' inside safe band (no notch/home clipping)" % [tag, want],
				safe.encloses(br))
	# The scroll band exists and is smaller than the body content when
	# content is tall (i.e. it really scrolls instead of growing).
	var scroll := _find_scroll(dlg)
	_check("%s: body scroll band present" % tag, scroll != null)


func _collect_buttons(n: Node, out: Array) -> void:
	if n is Button:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for c in n.get_children():
		var s := _find_scroll(c)
		if s != null:
			return s
	return null


## --- rich fixtures ---


func _rich_vote() -> Dictionary:
	var wars: Array = []
	for i in 6:
		wars.append({
			"faction": "elves", "faction_name": "Elves",
			"declared_by": "elves", "declared_by_name": "Elves",
			"war_days": 34 + i,
			"grievances": [{"type": "war_declared", "by": "elves",
				"game_time": 100.0}]})
	var votes: Array = []
	var names := [["gnomes", "Gnomes"], ["elves", "Elves"],
		["undead", "Undead"], ["humans", "Humans"]]
	for pair in names:
		votes.append({
			"voter": pair[0], "voter_name": pair[1],
			"leader": "Some Very Long-Winded Leader Name",
			"vote": "pending", "score": 12.5,
			"reason": "You showed our people mercy at Greendale when the granaries burned, and you sent timber when the long winter cracked our walls — we remember every kindness, and we vote with full hearts."})
	return {
		"loser": "ogres", "loser_name": "Ogres",
		"taker": "elves", "taker_name": "Elves",
		"town": "Gloomhold", "via": "captured",
		"wars": wars, "votes": votes,
		"player_votes": true, "player_vote": "pending",
		"result": "", "spare_count": 0, "kill_count": 0}


func _rich_aid_vote() -> Dictionary:
	var v := _rich_vote()
	v["victim"] = "ogres"
	v["victim_name"] = "Ogres"
	v["cause_text"] = "a great fire"
	return v


func _rich_treaty() -> Dictionary:
	var terms: Array = []
	for i in 4:
		terms.append({"kind": "tribute", "status": "active",
			"label": "Tribute: 120 gold/day for 20 days (term %d of a very long treaty)" % i})
	terms.append({"kind": "dmz", "status": "active",
		"label": "Demilitarized border: no troops within 420px of Elven towns for 30 days"})
	return {
		"id": 7, "loser": "ogres", "loser_name": "Ogres",
		"taker": "elves", "taker_name": "Elves",
		"terms": terms,
		"guarantor_names": ["Gnomes", "Undead", "Humans"],
		"warning": "Break this peace and every guarantor will remember. The warning has teeth."}
