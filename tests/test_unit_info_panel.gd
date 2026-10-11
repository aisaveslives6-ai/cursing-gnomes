extends SceneTree
## Cursing Gnomes — unit info panel live-refresh + dismiss tests.
## Jeremy 2026-10-03: X must close the panel; bars must update live.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_unit_info_panel.gd

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes unit info panel tests ===")
	_test_dismissed_signal()
	_test_show_empty_is_silent()
	_test_refresh_live_updates_bars()
	_test_refresh_live_wrong_unit_ignored()
	_test_enemy_panel_limited()
	_test_ally_panel_full()
	_test_foreign_panel_limited()
	_test_x_button_is_drawn_x()
	await _test_bar_anim_step()
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


func _make_panel() -> UnitInfoPanel:
	var p := UnitInfoPanel.new()
	root.add_child(p)
	# Headless -s scripts: _ready may not have fired yet; _build is
	# idempotent so this is safe either way.
	p._build()
	p.visible = false
	return p


func _make_unit(uid: int, hunger: float) -> Dictionary:
	return {
		"id": uid, "alive": true, "job": "worker", "faction": "gnomes",
		"gender": "f", "name": "Testy", "hp": 80.0, "max_hp": 100.0,
		"town_id": -1, "mind": {"name": "Testy", "critical_urge": ""},
		"mind_state": "",
		"urges": {"hunger": hunger, "energy": 50.0, "hygiene": 50.0,
			"social": 50.0, "mood": 50.0, "bladder": 50.0},
	}


func _test_dismissed_signal() -> void:
	var p := _make_panel()
	var fired := [false]
	p.dismissed.connect(func() -> void: fired[0] = true)
	p.show_unit(_make_unit(7, 60.0))
	_check("panel visible after show", p.visible)
	p._on_x_pressed()
	_check("X hides panel", not p.visible)
	_check("X emits dismissed", fired[0])
	p.queue_free()


func _test_show_empty_is_silent() -> void:
	var p := _make_panel()
	var fired := [false]
	p.dismissed.connect(func() -> void: fired[0] = true)
	p.show_unit({})
	_check("empty unit hides panel", not p.visible)
	_check("empty show is silent (no dismissed)", not fired[0])
	p.queue_free()


func _test_refresh_live_updates_bars() -> void:
	var p := _make_panel()
	var u := _make_unit(9, 60.0)
	p.show_unit(u)
	var before: int = p._vbox.get_child_count()
	# Mutate the live record, then refresh without rebuild.
	u["urges"]["hunger"] = 10.0
	u["hp"] = 25.0
	u["mind_state"] = "satisfying:hunger"
	p.refresh_live(u)
	_check("refresh does not rebuild children",
		p._vbox.get_child_count() == before)
	var hunger_pct := ""
	for row in p._bar_rows:
		var rd: Dictionary = row
		if String(rd["key"]) == "hunger":
			hunger_pct = (rd["pct"] as Label).text
	_check("hunger bar shows live value", hunger_pct == "10")
	_check("hp bar shows live value", p._hp_pct.text == "25")
	_check("activity shows satisfying state",
		p._activity_label.text == "Satisfying hunger (urge)")
	p.queue_free()


func _test_refresh_live_wrong_unit_ignored() -> void:
	var p := _make_panel()
	p.show_unit(_make_unit(11, 60.0))
	var other := _make_unit(12, 5.0)
	p.refresh_live(other)
	var hunger_pct := ""
	for row in p._bar_rows:
		var rd: Dictionary = row
		if String(rd["key"]) == "hunger":
			hunger_pct = (rd["pct"] as Label).text
	_check("refresh ignores other unit", hunger_pct == "60")
	p.queue_free()


func _make_enemy_unit() -> Dictionary:
	var u := _make_unit(21, 40.0)
	u["faction"] = "ogres"
	u["job"] = "soldier"
	u["name"] = "Grul the Terrible"
	u["mind"] = {"name": "Grul the Terrible", "critical_urge": ""}
	return u


## Jeremy 2026-10-04: enemy clicks must not leak stats/details.
func _test_enemy_panel_limited() -> void:
	var p := _make_panel()
	var u := _make_enemy_unit()
	p.show_unit(u, "", -1.0, true)
	_check("enemy panel visible", p.visible)
	_check("enemy header shows race+job, not name",
		p._name_label.text == "Ogre Soldier")
	_check("enemy header hides unit name",
		not ("Grul" in p._name_label.text))
	_check("enemy panel has no urge bars", p._bar_rows.is_empty())
	_check("enemy panel keeps HP bar", p._hp_fill != null)
	_check("enemy panel has no activity label", p._activity_label == null)
	# Live refresh still updates HP without leaking anything.
	u["hp"] = 10.0
	u["urges"]["hunger"] = 5.0
	p.refresh_live(u)
	_check("enemy HP refreshes live", p._hp_pct.text == "10")
	_check("enemy refresh adds no urge rows", p._bar_rows.is_empty())
	p.queue_free()


func _test_ally_panel_full() -> void:
	var p := _make_panel()
	var u := _make_unit(22, 60.0)
	p.show_unit(u, "Testville", -1.0, false)
	_check("ally panel visible", p.visible)
	_check("ally header shows name", p._name_label.text == "Testy")
	_check("ally panel has urge bars", not p._bar_rows.is_empty())
	_check("ally panel has activity label", p._activity_label != null)
	p.queue_free()


## Jeremy 2026-10-05: non-allied foreign units hide needs/traits/memories.
func _test_foreign_panel_limited() -> void:
	var p := _make_panel()
	var u := _make_enemy_unit()
	p.show_unit(u, "Ogreton", -1.0, false, true)
	_check("foreign panel visible", p.visible)
	_check("foreign header shows name", p._name_label.text == "Grul the Terrible")
	_check("foreign panel has no urge bars", p._bar_rows.is_empty())
	_check("foreign panel has no HP bar", p._hp_fill == null)
	_check("foreign panel has no activity label", p._activity_label == null)
	# Enemy flag still wins over foreign (at-war = hostile dossier).
	p.show_unit(u, "", -1.0, true, true)
	_check("enemy beats foreign: race+job header",
		p._name_label.text == "Ogre Soldier")
	p.queue_free()


## Jeremy 2026-10-05: world-map popup close button must be a drawn X.
func _test_x_button_is_drawn_x() -> void:
	var p := _make_panel()
	var found_x := false
	var found_chevron := false
	for c in p._xbtn.get_children():
		if c is DrawnX:
			found_x = true
		if c is DrawnChevron:
			found_chevron = true
	_check("close button has drawn X", found_x)
	_check("close button has no chevron", not found_chevron)
	p.queue_free()


## Jeremy 2026-10-05: needs bars must drain smoothly toward 0 via tween.
func _test_bar_anim_step() -> void:
	var p := _make_panel()
	var u := _make_unit(33, 60.0)
	p.show_unit(u, "", -1.0, false)
	# Step the tween callback directly: bar + number track the value.
	var row: Dictionary = p._bar_rows[0]
	var fill: ColorRect = row["fill"]
	var pct: Label = row["pct"]
	p._apply_bar_step(0.25, fill, pct)
	_check("bar step sets fill", is_equal_approx(fill.anchor_right, 0.25))
	_check("bar step sets number", pct.text == "25")
	p._apply_bar_step(0.0, fill, pct)
	_check("bar drains to 0, not clamped above", is_equal_approx(fill.anchor_right, 0.0))
	_check("bar number reaches 0", pct.text == "0")
	# Headless -s scripts: _ready fires on the next frame (resetting
	# visible) and is_inside_tree() is false until then. Await a frame so
	# the tween path (not the headless snap fallback) is exercised.
	await process_frame
	p._animate_bar(fill, pct, 10.0)
	_check("changed value starts bar tween", not p._bar_tweens.is_empty())
	# Re-targeting kills the old tween and tracks the latest value.
	p._animate_bar(fill, pct, 90.0)
	_check("re-target keeps single tween", p._bar_tweens.size() == 1)
	p.queue_free()
