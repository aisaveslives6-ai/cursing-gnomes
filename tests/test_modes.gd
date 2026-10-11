extends SceneTree
## Modes/screens/UI tests: world setup, end screen, autosave, debug
## overlay, adventure gender picker, unit info panel, credits.

var _passed := 0
var _failed := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	await _test_world_setup()
	await _test_end_screen()
	await _test_autosave()
	_test_debug_overlay()
	await _test_gender_picker()
	await _test_hero_job_picker()
	await _test_unit_info()
	await _test_unit_info_position()
	await _test_credits()
	print("test_modes: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# ------------------------------------------------------------ world setup

func _test_world_setup() -> void:
	var ws := WorldSetupScreen.new()
	ws.setup(["humans", "gnomes"], "gnomes")
	root.add_child(ws)
	await process_frame
	await process_frame
	_check(ws._wtype == "continents", "world setup defaults to continents")
	_check(ws._size == "normal" or ws._size == "mobile",
		"world setup has sane default size")
	_check(ws._opts.get("water") == "normal", "opts default normal")
	_check(ws._seed > 0, "seed rolled on open")
	# sanitize_opts: unknown values fall back to normal.
	var sane := WorldSetupScreen.sanitize_opts({"water": "high",
		"forest": "bogus", "nope": 1})
	_check(sane["water"] == "high" and sane["forest"] == "normal",
		"sanitize_opts clamps unknown values")
	_check(sane["resources"] == "normal" and sane["start"] == "normal",
		"sanitize_opts fills missing keys")
	# Reroll changes the seed.
	var s0: int = ws._seed
	ws._on_reroll()
	_check(ws._seed != s0, "reroll rolls a new seed")
	# Confirm emits type/size/opts/seed.
	var got := {}
	ws.world_confirmed.connect(func(t: String, s: String, o: Dictionary,
			seed: int) -> void:
		got["t"] = t
		got["s"] = s
		got["o"] = o
		got["seed"] = seed)
	ws._on_opt("water", "high")
	await process_frame
	await process_frame
	ws._on_type("highlands")
	await process_frame
	await process_frame
	ws._on_start()
	_check(got.get("t") == "highlands", "confirm emits chosen type")
	_check(str(got.get("o", {}).get("water")) == "high",
		"confirm emits chosen opts")
	_check(int(got.get("seed", 0)) == ws._seed, "confirm emits live seed")
	# Back signal.
	var flags := {"back": false}
	ws.back_pressed.connect(func() -> void: flags["back"] = true)
	for c in ws.get_children():
		ws.remove_child(c)  # keep node, drop built UI for direct emit test
	ws.back_pressed.emit()
	_check(flags["back"], "back signal fires")
	# Jeremy 2026-10-03: shaping rows must wrap on narrow phones — a plain
	# HBoxContainer with 3 x 170px cards (510px) overflows a 390px iPhone.
	var grp: VBoxContainer = ws._opt_group({"key": "water", "label": "Water level",
		"choices": [{"k": "low", "name": "Low"}, {"k": "normal", "name": "Normal"},
		{"k": "high", "name": "High"}]})
	var grow: Node = grp.get_child(1)
	_check(grow is HFlowContainer,
		"shaping option row is a flow container (wraps on phone)")
	_check(not (grow is HBoxContainer),
		"shaping option row is not a fixed HBoxContainer")
	grp.queue_free()
	ws.queue_free()
	await process_frame


# -------------------------------------------------------------- end screen

func _test_end_screen() -> void:
	var es := EndScreen.new()
	root.add_child(es)
	await process_frame
	_check(not es.visible, "end screen hidden until shown")
	es.show_end("victory", "", "Gnomesburg stands. Enemy Halls are rubble.")
	_check(es.visible, "victory shows")
	_check(es._title.text == "VICTORY", "victory title")
	_check(es._msg.text == "Gnomesburg stands. Enemy Halls are rubble.",
		"victory message")
	es.show_end("defeat", "", "The Hall of Gnomesburg has fallen.")
	_check(es._title.text == "DEFEAT", "defeat title")
	es.show_end("sandbox", "", "Gnomes dominated the continent. (Sandbox — you were an observer.)")
	_check(es._title.text == "SIMULATION COMPLETE", "sandbox variant title")
	_check(es._msg.text.contains("Sandbox"), "sandbox message kept")
	var eflags := {"again": false, "menu": false}
	es.play_again_requested.connect(func() -> void: eflags["again"] = true)
	es.main_menu_requested.connect(func() -> void: eflags["menu"] = true)
	# Press the buttons through their real connections.
	for c in es.find_children("*", "Button", true, false):
		if (c as Button).text == "PLAY AGAIN":
			(c as Button).pressed.emit()
		if (c as Button).text == "MAIN MENU":
			(c as Button).pressed.emit()
	_check(eflags["again"], "play again button emits")
	_check(eflags["menu"], "main menu button emits")
	es.hide_end()
	_check(not es.visible, "hide_end hides")
	es.queue_free()


# ---------------------------------------------------------------- autosave

func _test_autosave() -> void:
	var game := GameState.new()
	root.add_child(game)
	game.setup(["humans", "gnomes"])
	game.add_unit({"faction": "humans", "job": "worker",
		"town_id": -1, "position": Vector2.ZERO, "alive": true,
		"hp": 100.0, "max_hp": 100.0})
	var auto := AutosaveSystem.new()
	root.add_child(auto)
	auto.setup(game)
	_check(auto._enabled, "autosave defaults ON")
	_check(auto._minutes == 5, "autosave defaults to 5 minutes")
	_check(auto.save_now("manual"), "save_now writes")
	var data := AutosaveSystem.load_autosave()
	_check(not data.is_empty(), "autosave file loads back")
	_check(bool(data.get("autosave", false)), "autosave flagged")
	_check(str(data.get("autosave_reason", "")) == "manual",
		"autosave reason recorded")
	_check(int((data.get("units", []) as Array).size()) == 1,
		"autosave carries units")
	# Empty game refuses to save (nothing worth saving).
	var game2 := GameState.new()
	root.add_child(game2)
	var auto2 := AutosaveSystem.new()
	root.add_child(auto2)
	auto2.setup(game2)
	_check(not auto2.save_now("manual"), "empty game does not autosave")
	auto.queue_free()
	auto2.queue_free()
	game.queue_free()
	game2.queue_free()
	DirAccess.remove_absolute(AutosaveSystem.AUTOSAVE_PATH)


# ------------------------------------------------------------ debug overlay

func _test_debug_overlay() -> void:
	# Headless: no URL, so the param helper falls back gracefully.
	_check(DebugOverlay.url_debug_param() == -1,
		"?debug param absent headless")
	DebugOverlay.note("mind", 1.5)
	DebugOverlay.note("mind", 2.5)
	var ov := DebugOverlay.new()
	root.add_child(ov)
	await process_frame
	_check(not ov.is_enabled(), "debug overlay off by default")
	ov.set_enabled(true)
	_check(ov.is_enabled(), "debug overlay toggles on")
	ov.set_spawn_error("boom")
	_check(ov._spawn_err == "boom", "spawn error recorded")
	DebugOverlay.clear_ticks()
	ov.queue_free()


# ----------------------------------------------------------- gender picker

func _test_gender_picker() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	await process_frame
	await process_frame
	menu._show_faction(true)
	_check(menu._hero_gender == "male", "hero gender defaults male")
	_check(menu._hero_gender_btns.size() == 2, "two gender buttons")
	menu._on_hero_gender("female")
	_check(menu._hero_gender == "female", "gender switches to female")
	_check(menu._hero_gender_btns[1].button_pressed,
		"female button pressed")
	_check(not menu._hero_gender_btns[0].button_pressed,
		"male button released")
	var got: Array = []
	menu.adventure_start_requested.connect(func(f: String, r: String,
			hn: String, hj: String, hg: String) -> void:
		got.append_array([f, r, hn, hj, hg]))
	menu._hero_input.text = "Rogue"
	menu._on_start_game()
	_check(got.size() == 5, "adventure signal carries gender")
	_check(got[4] == "female", "gender emitted verbatim")
	menu.queue_free()


# ----------------------------------------------------- hero job picker
# HTML parity: the adventure job picker offers the selected faction's
# unique jobs (not a generic list) and the start signal carries the job id.

func _test_hero_job_picker() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	await process_frame
	await process_frame
	menu._show_faction(true)  # adventure mode; default faction gnomes
	await process_frame
	await process_frame
	_check(menu._hero_job != null, "job picker built")
	_check(menu._hero_job.item_count == 4, "gnome jobs offered (4)")
	_check(menu._hero_job.get_item_text(0) == "Axeman",
		"first gnome job Axeman")
	_check(menu._hero_job.get_item_text(1) == "Mage",
		"gnome mage present")
	# Switching faction refreshes the picker to that faction's uniques.
	menu._carousel3d_snap_to("elves")
	await process_frame
	_check(menu._selected_faction == "elves", "faction switched to elves")
	_check(menu._hero_job.item_count == 4, "elf jobs offered (4)")
	_check(menu._hero_job.get_item_text(0) == "Ranger",
		"first elf job Ranger")
	menu._carousel3d_snap_to("undead")
	await process_frame
	_check(menu._hero_job.get_item_text(0) == "Skeleton",
		"first undead job Skeleton")
	# Start emits the selected faction-unique job id.
	var got: Array = []
	menu.adventure_start_requested.connect(func(f: String, r: String,
			hn: String, hj: String, hg: String) -> void:
		got.append_array([f, r, hn, hj, hg]))
	menu._on_start_game()
	_check(got.size() == 5, "adventure signal fires with job picker")
	_check(got[0] == "undead", "faction emitted")
	_check(got[3] == "skeleton", "faction-unique job id emitted")
	menu.queue_free()


# ------------------------------------------------------------ unit info

func _test_unit_info() -> void:
	var p := UnitInfoPanel.new()
	root.add_child(p)
	await process_frame
	_check(not p.visible, "unit info hidden until shown")
	var u := {
		"id": 7, "faction": "gnomes", "job": "woodcutter",
		"town_id": 1, "position": Vector2.ZERO, "alive": true,
		"hp": 80.0, "max_hp": 100.0, "gender": "f",
		"urges": {"hunger": 20.0, "energy": 60.0, "hygiene": 60.0,
			"social": 60.0, "mood": 60.0, "bladder": 60.0},
		"mind": {"name": "Trixie", "critical_urge": "hunger",
			"traits": {"brave": 0.9, "friendly": 0.2, "diligent": 0.8,
				"crude": 0.1, "proud": 0.3}},
		"memories": [{"type": "hurt_by", "subject_name": "Brog",
			"subject_id": 3, "strength": 1.5}],
	}
	p.show_unit(u, "Gnomesburg")
	_check(p.visible, "unit info shows")
	var texts: Array[String] = []
	for l in p.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var blob := "\n".join(texts)
	_check(blob.contains("Trixie"), "name shown")
	_check(blob.contains("Female"), "gender shown")
	_check(blob.contains("Gnomesburg"), "city shown")
	_check(blob.contains("Currently:"), "current activity shown")
	_check(blob.contains("urgent") or blob.contains("hunger"),
		"critical urge surfaced")
	_check(blob.contains("Traits:"), "traits shown")
	_check(blob.contains("grudge") or blob.contains("Brog"),
		"honest memory line shown")
	_check(blob.contains("Lives in Gnomesburg"), "housing shown")
	# Gender backfill for old saves.
	var u2 := {"id": 4, "faction": "humans", "job": "worker",
		"alive": true, "hp": 100.0, "max_hp": 100.0}
	p.show_unit(u2)
	_check(str(u2.get("gender")) == "m", "gender backfilled by id parity")
	p.hide_panel()
	_check(not p.visible, "unit info hides")
	p.queue_free()


# --------------------------------------------- unit info popup positioning
# HTML parity: floating top-left (left:8px; top:48px), NOT a bottom sheet.

func _test_unit_info_position() -> void:
	var p := UnitInfoPanel.new()
	root.add_child(p)
	await process_frame
	await process_frame
	# Anchors: top-left, not bottom-wide.
	_check(p.anchor_left == 0.0 and p.anchor_top == 0.0,
		"unit info anchored top-left")
	_check(p.anchor_right == 0.0 and p.anchor_bottom == 0.0,
		"unit info not stretched to bottom")
	# Position: left:8px, top:48px (scaled).
	var s: float = p._ui_scale
	_check(absf(p.offset_left - 8.0 * s) < 1.0, "unit info left offset 8px")
	_check(absf(p.offset_top - 48.0 * s) < 1.0, "unit info top offset 48px")
	# Width: min(82vw, 320px).
	var vp: Vector2 = root.get_visible_rect().size
	var w: float = p.offset_right - p.offset_left
	_check(w <= vp.x * 0.82 + 1.0, "unit info width within 82vw")
	_check(w <= 320.0 * s + 1.0, "unit info width within 320px")
	# Style: dark bg, gold border (HTML #c9a227).
	var sb: StyleBoxFlat = p.get_theme_stylebox("panel")
	_check(sb != null and sb.border_color == Color(0.788, 0.635, 0.153),
		"unit info gold border")
	# Content: HTML sections present.
	var u := {
		"id": 7, "faction": "gnomes", "job": "soldier",
		"town_id": 1, "alive": true, "hp": 80.0, "max_hp": 100.0,
		"gender": "f", "firearm": "basic", "weapon_level": 2,
		"urges": {"hunger": 20.0, "energy": 60.0, "hygiene": 60.0,
			"social": 60.0, "mood": 60.0, "bladder": 60.0},
		"mind": {"name": "Trixie", "gov_role": "commander",
			"traits": {"brave": 0.9}},
		"memories": [],
	}
	p.show_unit(u, "Gnomesburg")
	var texts: Array[String] = []
	for l in p.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var blob := "\n".join(texts)
	_check(blob.contains("Faction: Gnomes"), "faction line shown")
	_check(blob.contains("Gender: Female"), "gender line shown")
	_check(blob.contains("Rune Staff"), "faction weapon name shown")
	_check(blob.contains("Lv2"), "weapon level shown")
	_check(blob.contains("Role: Military Commander"), "gov role shown")
	_check(blob.contains("DMG"), "fighter DMG shown")
	_check(blob.contains("No memories yet."), "empty memories honest")
	_check(blob.contains("Has a house"), "housing box shown")
	p.queue_free()


# ----------------------------------------------------------------- credits

func _test_credits() -> void:
	var menu := MainMenu.new()
	root.add_child(menu)
	await process_frame
	await process_frame
	menu._show_credits()
	var texts: Array[String] = []
	for l in menu.find_children("*", "Label", true, false):
		texts.append((l as Label).text)
	var blob := "\n".join(texts)
	_check(blob.contains("Ethos"), "credits name Ethos")
	_check(blob.contains("Jeremy Baker"), "credits name Jeremy Baker")
	_check(not blob.contains("Meta"), "no Meta attribution in credits")
	menu.queue_free()
