extends SceneTree
## Cursing Gnomes — flesh-farm ambient FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The undead flesh farm was the last production building with zero
## ambient FX — every farm rippled its crops, every civic seat breathed
## lamplight, but the flesh farm's hut lantern never pulsed and no wisps
## rose off the bone pit. Complete flesh_farms now breathe on the shared
## quantized FX cadence (8 steps at 6/sec — the eatery-vent precedent):
## the hut window + door lantern pulse sickly-green lamplight (the undead
## civic tint) and three wisps rise off the bone pit, desynced per
## building. Blueprints stay dark. The hanging sacks are baked into the
## sprite, so the motion lives in light and air — not in redrawn art.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_flesh_farm_fx.gd
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


func _make_node(btype: String, faction := "undead", complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes flesh-farm FX tests ===")
	_test_roster()
	_test_flicker()
	_test_wisp_life()
	_test_anchors()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: flesh_farm only — the living farm keeps its crop
## sway, every other family keeps its own path.
func _test_roster() -> void:
	_check("roster contains flesh_farm",
		"flesh_farm" in BuildingNode.FLESH_FX_BTYPES)
	_check("roster has exactly 1 type",
		BuildingNode.FLESH_FX_BTYPES.size() == 1)
	for b in ["farm", "farmhouse", "house", "town_hall", "hall", "windmill",
			"oil_pump", "barracks", "shop", "garden", "monastery",
			"mage_spire", "sawmill", "wall"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.FLESH_FX_BTYPES))
	_check("tex is 560x280", BuildingNode.FLESH_FX_TEX == Vector2(560.0, 280.0))
	_check("3 pit wisps", BuildingNode.FLESH_FX_PIT.size() == 3)


## flesh_flicker_for is the civic flicker idiom: bounded 0.60..1.0,
## varies with the step, phases desync per lamp.
func _test_flicker() -> void:
	var lo := 2.0
	var hi := 0.0
	for step in range(-1, 12):
		for ph in [0.0, 1.7, 2.9, 3.4]:
			var f: float = BuildingNode.flesh_flicker_for(step, ph)
			lo = minf(lo, f)
			hi = maxf(hi, f)
	_check("flicker lower bound ~0.60", lo >= 0.599)
	_check("flicker upper bound ~1.00", hi <= 1.001)
	_check("flicker reaches high", hi > 0.95)
	_check("flicker reaches low", lo < 0.70)
	# Deterministic: same inputs, same output.
	for step in [0, 3, 7]:
		for ph in [0.0, 2.9]:
			_check("flicker deterministic step=%d" % step,
				BuildingNode.flesh_flicker_for(step, ph)
				== BuildingNode.flesh_flicker_for(step, ph))
	# Cycles with the shared cadence: step 0 == step 8.
	var steps: int = BuildingNode.EATERY_FX_STEPS
	for ph in [0.0, 1.7]:
		_check("flicker cycles step 0==8",
			absf(BuildingNode.flesh_flicker_for(0, ph)
				- BuildingNode.flesh_flicker_for(steps, ph)) < 0.000001)
	# Varies over time: the lamp actually breathes.
	var varies := false
	for step in range(steps):
		if BuildingNode.flesh_flicker_for(step, 0.0) \
				!= BuildingNode.flesh_flicker_for((step + 1) % steps, 0.0):
			varies = true
	_check("flicker varies across steps", varies)
	# Phased apart: window and lantern don't breathe in lockstep.
	var apart := false
	for step in range(steps):
		if BuildingNode.flesh_flicker_for(step, 0.0) \
				!= BuildingNode.flesh_flicker_for(step, 2.9):
			apart = true
	_check("flicker phased apart", apart)


## flesh_wisp_life_for: staggered 1/3-cycle wisp life in [0,1),
## sign-robust (the -1 rest step can't leak a negative).
func _test_wisp_life() -> void:
	var steps: int = BuildingNode.EATERY_FX_STEPS
	for step in range(-2, steps + 4):
		for idx in 3:
			for ph in [0.0, 0.25]:
				var life: float = BuildingNode.flesh_wisp_life_for(step, idx, ph)
				_check("wisp life in [0,1) step=%d idx=%d" % [step, idx],
					life >= 0.0 and life < 1.0)
	# Deterministic.
	for step in [0, 3, 7]:
		for idx in 3:
			_check("wisp life deterministic step=%d idx=%d" % [step, idx],
				BuildingNode.flesh_wisp_life_for(step, idx, 0.0)
				== BuildingNode.flesh_wisp_life_for(step, idx, 0.0))
	# Staggered: the three wisps are never locked together.
	var staggered := false
	for step in range(steps):
		if BuildingNode.flesh_wisp_life_for(step, 0, 0.0) \
				!= BuildingNode.flesh_wisp_life_for(step, 1, 0.0):
			staggered = true
	_check("wisp life staggered across idx", staggered)
	# Cycles with the shared cadence.
	for idx in 3:
		_check("wisp life cycles step 0==8 idx=%d" % idx,
			absf(BuildingNode.flesh_wisp_life_for(0, idx, 0.0)
				- BuildingNode.flesh_wisp_life_for(steps, idx, 0.0))
			< 0.000001)


## Anchors match the sprite art they were measured from: the green hut
## window ~(415,143), the door lantern ~(381,148), pit-floor wisp origins
## (180,200) (260,185) (340,205). Anchor math at unit scale:
## (ap.x - w/2, ap.y - h/2 - 0.48h) (the _civic_art_to_node precedent).
func _test_anchors() -> void:
	_check("window (415,143)",
		BuildingNode.FLESH_FX_WINDOW == Vector2(415.0, 143.0))
	_check("lantern (381,148)",
		BuildingNode.FLESH_FX_LANTERN == Vector2(381.0, 148.0))
	_check("pit-0 (180,200)", BuildingNode.FLESH_FX_PIT[0] == Vector2(180.0, 200.0))
	_check("pit-1 (260,185)", BuildingNode.FLESH_FX_PIT[1] == Vector2(260.0, 185.0))
	_check("pit-2 (340,205)", BuildingNode.FLESH_FX_PIT[2] == Vector2(340.0, 205.0))
	var n := _make_node("flesh_farm")
	n._sprite_sc = 1.0
	var w: Vector2 = n._flesh_art_to_node(BuildingNode.FLESH_FX_WINDOW)
	_check("window node x = 135.0", absf(w.x - 135.0) < 0.01)
	_check("window node y = -131.4", absf(w.y - (-131.4)) < 0.01)
	var l: Vector2 = n._flesh_art_to_node(BuildingNode.FLESH_FX_LANTERN)
	_check("lantern node x = 101.0", absf(l.x - 101.0) < 0.01)
	_check("lantern node y = -126.4", absf(l.y - (-126.4)) < 0.01)
	var p: Vector2 = n._flesh_art_to_node(BuildingNode.FLESH_FX_PIT[0])
	_check("pit-0 node x = -100.0", absf(p.x - (-100.0)) < 0.01)
	_check("pit-0 node y = -74.4", absf(p.y - (-74.4)) < 0.01)
	# The overlay sits over the art, above the ground line: every anchor
	# has negative y (drawn upward from the building base).
	for ap in [BuildingNode.FLESH_FX_WINDOW, BuildingNode.FLESH_FX_LANTERN,
			BuildingNode.FLESH_FX_PIT[0], BuildingNode.FLESH_FX_PIT[2]]:
		_check("anchor above base", n._flesh_art_to_node(ap).y < 0.0)
	n.free()


## The _process gate: complete flesh_farms advance the FX step on the
## shared cadence; blueprints and every other type skip with one cheap
## check.
func _test_process_gates() -> void:
	var ff := _make_node("flesh_farm")
	ff._process(0.1)
	_check("complete flesh_farm advances fx step",
		ff._fx_step >= 0 and ff._fx_step < BuildingNode.EATERY_FX_STEPS)
	ff.free()
	var bp := _make_node("flesh_farm", "undead", false)
	bp._process(0.1)
	_check("flesh_farm blueprint stays static", bp._fx_step == -1)
	bp.free()
	var garden := _make_node("garden", "gnomes")
	garden._process(0.1)
	_check("garden skips flesh fx", garden._fx_step == -1)
	garden.free()
	var farm := _make_node("farm", "gnomes")
	farm._process(0.1)
	_check("living farm keeps its own gate",
		farm._fx_step >= 0 and farm._fx_step < BuildingNode.EATERY_FX_STEPS)
	farm.free()
	# The draw hook starts disarmed.
	var n := _make_node("flesh_farm")
	_check("fx hook starts disarmed", n._last_flesh_fx == "")
	n.free()
