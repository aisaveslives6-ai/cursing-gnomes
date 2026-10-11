extends SceneTree
## Cursing Gnomes — farm crop sway (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## Farms are among the most numerous buildings (the AI's agri plan builds
## 2+ per town) and every crop row stood frozen. Complete farms now ripple
## their sprout tips on the shared quantized FX cadence (8 steps at 6/sec
## — the eatery-vent precedent), a breeze wave staggered across the rows.
## Blueprints stay static (the scaffold arm renders instead of _farm), and
## the undead flesh_farm has its own FX arm (test_flesh_farm_fx.gd).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_farm_fx.gd
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


func _make_node(btype: String, faction := "gnomes", complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes farm crop sway tests ===")
	_test_roster()
	_test_sway_math()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: farms only — the undead flesh_farm and everything
## else keep their own arms/paths.
func _test_roster() -> void:
	_check("roster contains farm", "farm" in BuildingNode.FARM_FX_BTYPES)
	_check("roster has exactly 1 type",
		BuildingNode.FARM_FX_BTYPES.size() == 1)
	for b in ["farmhouse", "house", "town_hall", "windmill", "oil_pump",
			"barracks", "shop", "garden", "flesh_farm", "crop_field",
			"wall", "monastery"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.FARM_FX_BTYPES))
	_check("sway amplitude is 2.0px", BuildingNode.FARM_FX_SWAY == 2.0)


## farm_sway_for is a pure quantized wave: bounded, deterministic,
## cycling with the shared cadence, varying over time, and staggered
## across sprouts so the breeze visibly travels.
func _test_sway_math() -> void:
	var steps: int = BuildingNode.EATERY_FX_STEPS
	# Bounds: +-FARM_FX_SWAY across all steps (incl. the -1 rest step)
	# and all 12 sprouts.
	for step in range(-1, steps + 4):
		for idx in 12:
			var s: float = BuildingNode.farm_sway_for(step, idx)
			_check("sway bounds step=%d idx=%d" % [step, idx],
				absf(s) <= BuildingNode.FARM_FX_SWAY + 0.0001)
	# Deterministic: same inputs, same output.
	for step in [0, 3, 7]:
		for idx in [0, 5, 11]:
			_check("sway deterministic step=%d idx=%d" % [step, idx],
				BuildingNode.farm_sway_for(step, idx)
				== BuildingNode.farm_sway_for(step, idx))
	# Cycles with the shared cadence: step 0 == step 8, step 1 == step 9
	# (within float precision — sin(TAU) is -2.4e-16, not bitwise 0).
	for idx in [0, 4, 11]:
		_check("sway cycles step 0==8 idx=%d" % idx,
			absf(BuildingNode.farm_sway_for(0, idx)
				- BuildingNode.farm_sway_for(steps, idx)) < 0.000001)
		_check("sway cycles step 1==9 idx=%d" % idx,
			absf(BuildingNode.farm_sway_for(1, idx)
				- BuildingNode.farm_sway_for(steps + 1, idx)) < 0.000001)
	# Varies over time: each sprout moves through the cycle.
	var varies := false
	for step in range(steps):
		if BuildingNode.farm_sway_for(step, 0) \
				!= BuildingNode.farm_sway_for((step + 1) % steps, 0):
			varies = true
	_check("sway varies across steps", varies)
	# Staggered: the breeze wave travels — neighboring sprouts are not
	# locked together at every step.
	var staggered := false
	for step in range(steps):
		if BuildingNode.farm_sway_for(step, 0) \
				!= BuildingNode.farm_sway_for(step, 6):
			staggered = true
	_check("sway staggers across rows", staggered)
	# Full amplitude is reachable (the wave isn't flattened by quantizing).
	var peak := 0.0
	for step in range(steps):
		for idx in 12:
			peak = maxf(peak, absf(BuildingNode.farm_sway_for(step, idx)))
	_check("sway reaches near full amplitude", peak > 1.5)


## _process ripples only complete farms: blueprints stay static, and
## farm-less types never enter the gate.
func _test_process_gates() -> void:
	var farm := _make_node("farm")
	farm._process(0.1)
	_check("complete farm advances fx step",
		farm._fx_step >= 0 and farm._fx_step < BuildingNode.EATERY_FX_STEPS)
	var bp := _make_node("farm", "gnomes", false)
	bp._process(0.1)
	_check("farm blueprint stays static", bp._fx_step == -1)
	var garden := _make_node("garden")
	garden._process(0.1)
	_check("garden skips farm fx", garden._fx_step == -1)
	# Flesh-farm FX (graphics-hourly 2026-10-09): the undead farm now
	# breathes on the same cadence — see test_flesh_farm_fx.gd.
	var flesh := _make_node("flesh_farm")
	flesh._process(0.1)
	_check("flesh_farm advances fx step",
		flesh._fx_step >= 0 and flesh._fx_step < BuildingNode.EATERY_FX_STEPS)
	# The farm gate is idempotent with the shared cadence: a second
	# _process in the same step doesn't disturb the step.
	var farm2 := _make_node("farm")
	farm2._process(0.1)
	var step0: int = farm2._fx_step
	farm2._process(0.1)
	_check("farm fx step idempotent in-step", farm2._fx_step == step0)
