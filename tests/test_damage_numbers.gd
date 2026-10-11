extends SceneTree
## Cursing Gnomes — floating damage numbers (rapid-iteration 2026-10-08).
##
## Combat computed damage but never displayed it, so battles read as mush
## and the weapon-upgrade economy was invisible. SimCombat.damage_unit now
## emits bus.unit_damaged with the final mitigated amount; the DamageNumbers
## world layer turns each hit into a small floating number (plain text only
## — no bubble visuals per Jeremy's 2026-10-05 ban).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_damage_numbers.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


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


func _make_world() -> Dictionary:
	var gs: GameState = GameState.new()
	gs.setup(["humans"] as Array[String])
	var combat := SimCombat.new(gs)
	return {"gs": gs, "combat": combat}


func _spawn(w: Dictionary) -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit("humans", "worker", -1,
		Vector2(500, 500))
	u["hp"] = 100.0
	u["max_hp"] = 100.0
	return u


func _initialize() -> void:
	print("=== Cursing Gnomes damage-number tests ===")
	_test_tier_pure()
	_test_signal_emitted()
	_test_signal_on_kill()
	_test_mitigated_amount()
	_test_dead_unit_no_emit()
	_test_downed_unit_no_emit()
	_test_layer_chip_skip()
	_test_layer_pool_cap()
	_test_layer_no_bubble_styling()
	_test_layer_amount_text()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## tier_for: pure boundary math.
func _test_tier_pure() -> void:
	_check("graze -> tier 0", DamageNumbers.tier_for(9.9) == 0)
	_check("tier boundary 15 -> 1", DamageNumbers.tier_for(15.0) == 1)
	_check("heavy 20 -> tier 1", DamageNumbers.tier_for(20.0) == 1)
	_check("tier boundary 30 -> 2", DamageNumbers.tier_for(30.0) == 2)
	_check("siege 70 -> tier 2", DamageNumbers.tier_for(70.0) == 2)
	_check("light is white", DamageNumbers.color_for(0) == Color(1, 1, 1))
	_check("massive bigger than light",
		DamageNumbers.size_for(2) > DamageNumbers.size_for(0))


## damage_unit emits the final amount on the bus.
func _test_signal_emitted() -> void:
	var w: Dictionary = _make_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u: Dictionary = _spawn(w)
	var got: Array = []
	gs.bus.unit_damaged.connect(
		func(uid: int, amt: float, pos: Vector2, kind: String) -> void:
			got.append([uid, amt, pos, kind]))
	var ok: bool = combat.damage_unit(int(u["id"]), 10.0, "ogres")
	# damage_unit returns true only when the hit KILLS (false = survived).
	_check("survived hit returns false", not ok)
	_check("one emission", got.size() == 1)
	_check("unit id carried", int(got[0][0]) == int(u["id"]))
	_check("final amount carried", is_equal_approx(float(got[0][1]), 10.0))
	_check("victim position carried",
		(got[0][2] as Vector2).distance_to(Vector2(500, 500)) < 1.0)
	_check("kind carried", String(got[0][3]) == "")
	gs.free()


## Killing blows also emit (with the full final amount) and return true.
func _test_signal_on_kill() -> void:
	var w: Dictionary = _make_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u: Dictionary = _spawn(w)
	var got: Array = []
	gs.bus.unit_damaged.connect(
		func(uid: int, amt: float, pos: Vector2, kind: String) -> void:
			got.append(amt))
	var ok: bool = combat.damage_unit(int(u["id"]), 200.0, "ogres")
	_check("killing blow returns true", ok)
	_check("killing blow emits full amount",
		got.size() == 1 and is_equal_approx(float(got[0]), 200.0))
	gs.free()


## Cover mitigation is reflected in the emitted number.
func _test_mitigated_amount() -> void:
	var w: Dictionary = _make_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u: Dictionary = _spawn(w)
	u["in_cover"] = true
	var got: Array = []
	gs.bus.unit_damaged.connect(
		func(uid: int, amt: float, pos: Vector2, kind: String) -> void:
			got.append(amt))
	combat.damage_unit(int(u["id"]), 10.0, "ogres")
	_check("covered hit emits mitigated 6.5",
		got.size() == 1 and is_equal_approx(float(got[0]), 6.5))
	gs.free()


## Dead / missing units emit nothing.
func _test_dead_unit_no_emit() -> void:
	var w: Dictionary = _make_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var got: Array = []
	gs.bus.unit_damaged.connect(
		func(uid: int, amt: float, pos: Vector2, kind: String) -> void:
			got.append(amt))
	var ok: bool = combat.damage_unit(424242, 10.0, "ogres")
	_check("missing unit returns false", not ok)
	_check("missing unit emits nothing", got.is_empty())
	gs.free()


## Downed units can't be hit again — no number.
func _test_downed_unit_no_emit() -> void:
	var w: Dictionary = _make_world()
	var gs: GameState = w["gs"]
	var combat: SimCombat = w["combat"]
	var u: Dictionary = _spawn(w)
	u["downed"] = true
	var got: Array = []
	gs.bus.unit_damaged.connect(
		func(uid: int, amt: float, pos: Vector2, kind: String) -> void:
			got.append(amt))
	var ok: bool = combat.damage_unit(int(u["id"]), 10.0, "ogres")
	_check("downed unit returns false", not ok)
	_check("downed unit emits nothing", got.is_empty())
	gs.free()


## Chip damage (< 1.0) never spawns a label.
func _test_layer_chip_skip() -> void:
	var layer := DamageNumbers.new()
	layer.spawn(0.5, Vector2(100, 100))
	_check("chip skipped", layer.active_count() == 0)
	layer.spawn(0.99, Vector2(100, 100))
	_check("sub-1.0 skipped", layer.active_count() == 0)
	layer.free()


## Pool never exceeds its cap, even under a 40-hit burst.
func _test_layer_pool_cap() -> void:
	var layer := DamageNumbers.new()
	for i in range(40):
		layer.spawn(12.0, Vector2(100 + i, 100))
	_check("pool capped at 24", layer.active_count() <= 24)
	_check("pool fully used under burst", layer.active_count() == 24)
	layer.free()


## Bubble ban: pooled nodes are plain Labels with a font outline —
## never Panel/PanelContainer/chip backgrounds.
func _test_layer_no_bubble_styling() -> void:
	var layer := DamageNumbers.new()
	layer.spawn(12.0, Vector2(100, 100))
	var kids: Array[Node] = layer.get_children()
	_check("pool built", kids.size() == 24)
	var clean := true
	for k in kids:
		if k is Panel or k is PanelContainer or k is Button:
			clean = false
		if not (k is Label):
			clean = false
	_check("no bubble/panel nodes anywhere", clean)
	var active: Label = null
	for k in kids:
		if (k as Label).visible:
			active = k as Label
	_check("a label is active", active != null)
	if active != null:
		_check("label has settings", active.label_settings != null)
		_check("outline for readability (no backdrop)",
			active.label_settings != null
			and active.label_settings.outline_size > 0)
	layer.free()


## Amount text is the rounded integer.
func _test_layer_amount_text() -> void:
	var layer := DamageNumbers.new()
	layer.spawn(12.6, Vector2(100, 100))
	var found := false
	for k in layer.get_children():
		var lbl := k as Label
		if lbl.visible and lbl.text == "13":
			found = true
	_check("12.6 renders as 13", found)
	layer.free()
