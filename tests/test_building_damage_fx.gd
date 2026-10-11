extends SceneTree
## Cursing Gnomes — battle damage FX (graphics-hourly 2026-10-07, Jeremy's
## standing "everything smoothly animated" rule; P6 ladder 2026-10-10).
##
## Only walls showed damage (crack bands) — every other building stood
## pristine while siege engines pounded it. Complete non-wall buildings
## now walk an escalating 5-band ladder: scuffed (< 85%: soot streaks +
## hairline cracks), cracked/crumbling (< 65%: jagged cracks + debris at
## the base), smoking (< 45%), burning (< 30% — the sim already calls a
## 25%-HP captured hall "burning": combat.gd _flip_hall), and rubble on
## destruction (RubbleLayer, already existed). Repair walks the ladder
## back down in reverse — the band recomputes from live hp every tick.
## The FX lives on a DamageFXLayer child that draws OVER the sprite art,
## exists only while damaged, and animates on the shared quantized FX
## cadence (8 steps at 6/sec). Blueprints never, walls keep their crack
## bands, healthy buildings are untouched.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_building_damage_fx.gd
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


func _make_node(btype: String, hp: float, max_hp: float,
		faction := "gnomes", complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete, "hp": hp, "max_hp": max_hp}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes building damage FX tests ===")
	_test_band_pure()
	_test_gates()
	_test_lifecycle()
	_test_edge_records()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## damage_band_for: pure boundary math (P6 ladder).
func _test_band_pure() -> void:
	_check("full hp -> band 0", BuildingNode.damage_band_for(1.0) == 0)
	_check("85% boundary -> band 0", BuildingNode.damage_band_for(0.85) == 0)
	_check("84% -> band 1 scuffed", BuildingNode.damage_band_for(0.84) == 1)
	_check("65% boundary -> band 1", BuildingNode.damage_band_for(0.65) == 1)
	_check("64% -> band 2 cracked", BuildingNode.damage_band_for(0.64) == 2)
	_check("45% boundary -> band 2", BuildingNode.damage_band_for(0.45) == 2)
	_check("44% -> band 3 smoking", BuildingNode.damage_band_for(0.44) == 3)
	_check("30% boundary -> band 3", BuildingNode.damage_band_for(0.30) == 3)
	_check("29% -> band 4 burning", BuildingNode.damage_band_for(0.29) == 4)
	_check("zero hp -> band 4", BuildingNode.damage_band_for(0.0) == 4)
	_check("negative frac -> band 4", BuildingNode.damage_band_for(-0.5) == 4)
	_check("overheal frac -> band 0", BuildingNode.damage_band_for(1.5) == 0)


## Gates: walls, blueprints, and healthy buildings never get the layer.
func _test_gates() -> void:
	var wall := _make_node("wall", 100.0, 900.0)
	wall._process(0.1)
	_check("wall skips damage fx", wall._dmg_band == -1)
	_check("wall gets no layer", wall._dmg_layer == null)
	wall.free()
	var bp := _make_node("barracks", 100.0, 900.0, "gnomes", false)
	bp._process(0.1)
	_check("blueprint skips damage fx", bp._dmg_band == -1)
	_check("blueprint gets no layer", bp._dmg_layer == null)
	bp.free()
	var healthy := _make_node("barracks", 900.0, 900.0)
	healthy._process(0.1)
	_check("healthy -> band 0", healthy._dmg_band == 0)
	_check("healthy gets no layer", healthy._dmg_layer == null)
	# 2026-10-09: a healthy barracks now legitimately advances the step
	# through the military FX gate (its own family, not damage), and a
	# healthy shop through the shop FX gate. Later the same day town_hall
	# joined the civic FX family, so the damage-gate isolation is pinned
	# on the well — in no FX roster, documented dark (shop lane).
	var quiet := _make_node("well", 900.0, 900.0)
	quiet._process(0.1)
	_check("healthy leaves fx step alone", quiet._fx_step == -1)
	quiet.free()
	healthy.free()
	var empty_rec := BuildingNode.new()
	empty_rec.setup(8, "barracks", "gnomes", Vector2(50, 50))
	empty_rec.record = {}
	empty_rec._process(0.1)
	_check("empty record skips", empty_rec._dmg_band == -1)
	empty_rec.free()


## Lifecycle: damage -> cracked -> burning -> partial repair steps the
## ladder back down -> full repair clears.
func _test_lifecycle() -> void:
	var n := _make_node("barracks", 200.0, 400.0)  # 50% -> cracked
	n._process(0.1)
	_check("50% hp -> band 2", n._dmg_band == 2)
	_check("layer created", n._dmg_layer != null)
	_check("layer is DamageFXLayer",
		n._dmg_layer is BuildingNode.DamageFXLayer)
	_check("layer parented to node", n._dmg_layer.get_parent() == n)
	_check("layer host wired", n._dmg_layer.host == n)
	_check("damaged advances fx step",
		n._fx_step >= 0 and n._fx_step < BuildingNode.EATERY_FX_STEPS)
	_check("draw method exists", n.has_method("draw_damage_fx"))
	# Second process: layer is reused, not duplicated.
	var first_layer: Node2D = n._dmg_layer
	n._process(0.1)
	_check("layer reused across frames", n._dmg_layer == first_layer)
	_check("one layer child only",
		n.get_children().filter(func(c: Node) -> bool:
			return c is BuildingNode.DamageFXLayer).size() == 1)
	# Escalate to burning: bigger flames join the smoke.
	n.record["hp"] = 80.0  # 20% -> burning
	n._process(0.1)
	_check("20% hp -> band 4", n._dmg_band == 4)
	_check("layer survives escalation", n._dmg_layer == first_layer)
	# Partial repair walks the ladder back down in reverse.
	n.record["hp"] = 280.0  # 70% -> scuffed
	n._process(0.1)
	_check("70% hp -> band 1", n._dmg_band == 1)
	_check("layer survives de-escalation", n._dmg_layer == first_layer)
	# Repair to full: FX clears.
	n.record["hp"] = 400.0
	n._process(0.1)
	_check("repaired -> band 0", n._dmg_band == 0)
	_check("layer freed on repair", n._dmg_layer == null)
	n.free()


## Edge records: missing max_hp, zero max_hp, missing hp.
func _test_edge_records() -> void:
	var no_max := BuildingNode.new()
	no_max.setup(9, "barracks", "gnomes", Vector2(50, 50))
	no_max.record = {"complete": true, "hp": 100.0}
	no_max._process(0.1)
	_check("missing max_hp falls back to hp", no_max._dmg_band == 0)
	no_max.free()
	var zero_max := _make_node("barracks", 0.0, 0.0)
	zero_max._process(0.1)
	_check("zero max_hp -> band 0 (no div0)", zero_max._dmg_band == 0)
	zero_max.free()
	var no_hp := BuildingNode.new()
	no_hp.setup(10, "barracks", "gnomes", Vector2(50, 50))
	no_hp.record = {"complete": true, "max_hp": 400.0}
	no_hp._process(0.1)
	_check("missing hp defaults to full", no_hp._dmg_band == 0)
	no_hp.free()
	# Captured-hall case from combat.gd _flip_hall: 25% HP must burn.
	var captured := _make_node("town_hall", 300.0, 1200.0)
	captured._process(0.1)
	_check("captured hall at 25% burns", captured._dmg_band == 4)
	_check("captured hall gets layer", captured._dmg_layer != null)
	captured.free()
