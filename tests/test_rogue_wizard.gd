extends SceneTree
## Cursing Gnomes — Rogue Wizard disaster tests (wake rapid-iteration
## 2026-10-07: rogue wizard flesh-out — "Zorblax the Unlicensed").
##
## Covers: singleton rule, label, arrival story + greeting, three rotating
## spell schools, wild-surge fizzles (self damage, dizzy, bounded rate),
## blink escape from soldiers (3 max, then he stands and fights), slain ->
## ledger closed with ZORBLAX note, budget expiry -> ledger closed, and the
## no-units edge case (no crash, no dead end).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_rogue_wizard.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes Rogue Wizard tests ===")
	_test_singleton_and_label()
	_test_arrival_story_and_greeting()
	_test_spell_schools_rotate()
	_test_fizzle()
	_test_blink_on_soldier()
	_test_blink_cap()
	_test_slain_closes_ledger()
	_test_budget_leave()
	_test_no_units_no_crash()
	_test_wizard_last_school_truthful()
	_test_line_pools()
	_test_sprite_transparency()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _new_disasters(gs: GameState) -> DisasterSim:
	var combat := SimCombat.new(gs)
	var d := DisasterSim.new(gs, combat)
	gs.disasters = d
	return d


func _add_citizen(gs: GameState, faction: String, pos: Vector2,
		job: String = "worker", hp: float = 100.0) -> Dictionary:
	var u: Dictionary = gs.add_unit({
		"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": hp, "max_hp": hp,
	})
	return u


func _test_singleton_and_label() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var a: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	_check("wizard: spawns", not a.is_empty())
	_check("wizard: label", d._label_for("rogue_wizard") == "Rogue Wizard")
	_check("wizard: log opened", int(a.get("disaster_log_id", -1)) > 0)
	var b: Dictionary = d.spawn("rogue_wizard", Vector2(600, 600))
	_check("wizard: singleton (second refused)", b.is_empty())


func _test_arrival_story_and_greeting() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	d.tick(0.2)
	_check("wizard: arrival story announced",
		bool(u.get("wizard_announced", false)))
	_check("wizard: greets on arrival", bool(u.get("wizard_greeted", false)))


func _test_spell_schools_rotate() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	# Tough victim in range so he keeps casting (no soldiers -> no blink).
	_add_citizen(gs, "humans", Vector2(700, 500), "worker", 100000.0)
	# Rotation is deterministic (wizard_school cycles 1,2,3); fizzle only
	# gates wizard_last_school recording, so assert coverage on the counter
	# itself — this check can never RNG-flake (2026-10-08: the old seeded
	# wizard_last_school check missed a school ~1-in-200 runs when all four
	# casts of one school fizzled).
	var schools_seen := {}
	for i in 12:
		u["attack_cd"] = 0.0
		d.tick(0.05)
		schools_seen[int(u.get("wizard_school", 0))] = true
	_check("wizard: three spell schools defined",
		DisasterSim.WIZARD_SCHOOLS.size() == 3)
	_check("wizard: rotation hits all schools (fire/frost/storm)",
		schools_seen.has(1) and schools_seen.has(2) and schools_seen.has(3))
	_check("wizard: 12 casts tallied", int(u.get("wizard_casts", 0)) == 12)


func _test_fizzle() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	_add_citizen(gs, "humans", Vector2(700, 500), "worker", 100000.0)
	seed(7)
	for i in 300:
		u["attack_cd"] = 0.0
		d.tick(0.05)
	var casts: int = int(u.get("wizard_casts", 0))
	var fizzles: int = int(u.get("wizard_fizzles", 0))
	_check("wizard: fizzle chance is 0.20",
		is_equal_approx(DisasterSim.WIZARD_FIZZLE_CHANCE, 0.20))
	_check("wizard: some casts fizzle (seeded)", fizzles > 0)
	_check("wizard: fizzles are a minority", fizzles < casts)
	_check("wizard: fizzles hurt him (wild surge)",
		float(u.get("hp", 200.0)) < 200.0)


func _test_blink_on_soldier() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	_add_citizen(gs, "humans", Vector2(520, 500), "soldier")
	var before: Vector2 = u.get("position", Vector2.ZERO)
	d.tick(0.2)
	var after: Vector2 = u.get("position", Vector2.ZERO)
	_check("wizard: blinks when a soldier closes in",
		int(u.get("wizard_blinks", 0)) == 1)
	_check("wizard: blink moves him far",
		before.distance_to(after) > 200.0)


func _test_blink_cap() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	u["wizard_blinks"] = DisasterSim.WIZARD_MAX_BLINKS
	_add_citizen(gs, "humans", Vector2(520, 500), "soldier")
	_add_citizen(gs, "humans", Vector2(700, 500), "worker", 100000.0)
	u["attack_cd"] = 0.0
	d.tick(0.2)
	_check("wizard: no 4th blink (cap holds)",
		int(u.get("wizard_blinks", 0)) == DisasterSim.WIZARD_MAX_BLINKS)
	_check("wizard: stands and fights after blinks run out",
		int(u.get("wizard_casts", 0)) == 1)


func _test_slain_closes_ledger() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	var log_id: int = int(u.get("disaster_log_id", -1))
	d.tick(0.2)
	u["wizard_casts"] = 5
	u["wizard_fizzles"] = 1
	u["wizard_blinks"] = 2
	u["alive"] = false
	d.tick(0.3)
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("wizard: slain closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	var derobed := false
	for n in rec.get("notes", []):
		var ns := String(n)
		if ns.begins_with("ZORBLAX"):
			saw = true
			if "(de-robed)" in ns:
				derobed = true
	_check("wizard: ZORBLAX note filed", saw)
	_check("wizard: de-robed note on slain", derobed)


func _test_budget_leave() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	var log_id: int = int(u.get("disaster_log_id", -1))
	u["age"] = 999.0
	d.tick(0.1)
	_check("wizard: budget expiry starts leaving",
		bool(u.get("leaving", false)))
	var rec: Dictionary = d.dlog.get_record(log_id)
	_check("wizard: leave closes ledger",
		String(rec.get("status", "")) != "active")
	var saw := false
	for n in rec.get("notes", []):
		if String(n).begins_with("ZORBLAX"):
			saw = true
	_check("wizard: ZORBLAX note on leave", saw)


func _test_no_units_no_crash() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	d.tick(0.5)
	_check("wizard: no targets -> wanders, no crash",
		not u.is_empty() and bool(u.get("wizard_announced", false)))
	_check("wizard: still greets with nobody around",
		bool(u.get("wizard_greeted", false)))


## A fizzled spell is still that school: wizard_last_school must name the
## attempted school on every cast, fizzle or not. Before the source fix it
## kept the previous school whenever a cast fizzled.
func _test_wizard_last_school_truthful() -> void:
	var gs := _new_game(["humans"])
	var d := _new_disasters(gs)
	var u: Dictionary = d.spawn("rogue_wizard", Vector2(500, 500))
	_add_citizen(gs, "humans", Vector2(700, 500), "worker", 100000.0)
	seed(1234)  # heavy fizzles; the mapping must hold for any seed
	var truthful := true
	var casts: int = 0
	for i in 24:
		u["attack_cd"] = 0.0
		d.tick(0.05)
		var school_num: int = int(u.get("wizard_school", 0))
		if school_num < 1:
			continue
		casts += 1
		var expected: String = String(
			DisasterSim.WIZARD_SCHOOLS[(school_num - 1) % 3].get("name", ""))
		if String(u.get("wizard_last_school", "")) != expected:
			truthful = false
	_check("wizard: wizard_last_school names the attempted school on every cast (fizzle or not)",
		casts >= 12 and truthful)


func _test_line_pools() -> void:
	_check("wizard: has a name", DisasterSim.WIZARD_NAME == "Zorblax the Unlicensed")
	_check("wizard: arrive lines", DisasterSim.WIZARD_ARRIVE_LINES.size() >= 3)
	_check("wizard: taunt lines", DisasterSim.WIZARD_TAUNT_LINES.size() >= 3)
	_check("wizard: blink lines", DisasterSim.WIZARD_BLINK_LINES.size() >= 3)
	_check("wizard: fizzle lines", DisasterSim.WIZARD_FIZZLE_LINES.size() >= 3)


func _test_sprite_transparency() -> void:
	# Jeremy 2026-10-08 (no white squares): the wizard shipped 2026-10-07
	# with a fully opaque white background on rogue_wizard.png — he
	# rendered inside a white rectangle. Border-flood-to-transparent
	# sweep must hold: corners transparent, enclosed whites (beard)
	# preserved.
	var img := Image.load_from_file(
		"res://assets/art/animals/rogue_wizard.png")
	_check("wizard: sprite loads", img != null)
	if img == null:
		return
	var w: int = img.get_width()
	var h: int = img.get_height()
	var corners_clear := true
	for c in [Vector2i(0, 0), Vector2i(w - 1, 0),
			Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
		if img.get_pixel(c.x, c.y).a > 0.01:
			corners_clear = false
	_check("wizard: sprite corners transparent (no white box)", corners_clear)
	var beard_px := 0
	for y in range(0, h, 7):
		for x in range(0, w, 7):
			var p: Color = img.get_pixel(x, y)
			if p.a > 0.8 and p.r >= 0.94 and p.g >= 0.94 and p.b >= 0.94:
				beard_px += 1
	_check("wizard: enclosed whites preserved (beard intact)",
		beard_px > 500)
	var tex := Art.animal_texture("rogue_wizard")
	_check("wizard: Art resolves texture",
		tex != null and tex.get_width() > 0)
	_check("wizard: has a name", DisasterSim.WIZARD_NAME == "Zorblax the Unlicensed")
	_check("wizard: arrive lines", DisasterSim.WIZARD_ARRIVE_LINES.size() >= 3)
	_check("wizard: taunt lines", DisasterSim.WIZARD_TAUNT_LINES.size() >= 3)
	_check("wizard: blink lines", DisasterSim.WIZARD_BLINK_LINES.size() >= 3)
	_check("wizard: fizzle lines", DisasterSim.WIZARD_FIZZLE_LINES.size() >= 3)
