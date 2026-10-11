extends SceneTree
## Cursing Gnomes — iPhone 17 performance-floor budget tests.
##
## Jeremy 2026-10-04: iPhone 17 standard is the minimum target. These tests
## enforce the budgets documented in docs/PERFORMANCE_TARGETS.md:
##   - iPhone 17-class hardware must resolve to the "medium" floor tier
##   - every particle pool, FX pool, audio pool, and the NPC cap must stay
##     within the GraphicsTiers.BUDGET_* constants
##   - tier knobs must stay in sane ranges on every tier
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_performance_budgets.gd


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes iPhone 17 performance budget tests ===")
	_test_iphone17_floor_tier()
	_test_tier_boundaries()
	_test_hardware_sanity()
	_test_weather_budget()
	_test_ambient_budget()
	_test_combat_fx_budget()
	_test_building_fire_budget()
	_test_audio_budget()
	_test_npc_budget()
	_test_tier_knobs()
	_test_resolve()
	_test_detect_runs_headless()
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


## iPhone 17: A19 hexa-core, mobile Safari (web_ios), Apple GPU, ~874 CSS px
## wide. Must land on "medium" — the floor tier. Even if Safari hides the
## GPU renderer string, it must still be medium (no over-promising).
func _test_iphone17_floor_tier() -> void:
	var score := GraphicsTiers.score_device(6, true, "Apple GPU", 874.0)
	_check("iphone17: score in medium band", score >= 30 and score < 95)
	_check("iphone17: tier is medium",
		GraphicsTiers.tier_for_score(score) == "medium")
	var score_hidden_gpu := GraphicsTiers.score_device(6, true, "", 874.0)
	_check("iphone17: medium even with hidden GPU string",
		GraphicsTiers.tier_for_score(score_hidden_gpu) == "medium")


func _test_tier_boundaries() -> void:
	_check("tier: 100 -> ultra", GraphicsTiers.tier_for_score(100) == "ultra")
	_check("tier: 150 clamps -> ultra",
		GraphicsTiers.tier_for_score(150) == "ultra")
	_check("tier: 99 -> high", GraphicsTiers.tier_for_score(99) == "high")
	_check("tier: 95 -> high", GraphicsTiers.tier_for_score(95) == "high")
	_check("tier: 94 -> medium", GraphicsTiers.tier_for_score(94) == "medium")
	_check("tier: 30 -> medium", GraphicsTiers.tier_for_score(30) == "medium")
	_check("tier: 29 -> low", GraphicsTiers.tier_for_score(29) == "low")
	_check("tier: 0 -> low", GraphicsTiers.tier_for_score(0) == "low")
	_check("tier: negative clamps -> low",
		GraphicsTiers.tier_for_score(-5) == "low")


## Strong desktop hardware must reach high/ultra; very weak devices must
## fall to the low safety valve.
func _test_hardware_sanity() -> void:
	var desktop := GraphicsTiers.score_device(8, false, "Apple M1", 2560.0)
	_check("hardware: desktop mac scores high",
		GraphicsTiers.tier_for_score(desktop) == "high")
	var strong := GraphicsTiers.score_device(
		16, false, "NVIDIA GeForce RTX", 3840.0)
	_check("hardware: strong desktop scores ultra",
		GraphicsTiers.tier_for_score(strong) == "ultra")
	var weak := GraphicsTiers.score_device(2, true, "swiftshader", 700.0)
	_check("hardware: software renderer scores low",
		GraphicsTiers.tier_for_score(weak) == "low")
	var mid_phone := GraphicsTiers.score_device(4, true, "Mali-GPU", 800.0)
	_check("hardware: mid phone scores medium-or-low",
		GraphicsTiers.tier_for_score(mid_phone) in ["medium", "low"])


func _test_weather_budget() -> void:
	_check("budget: rain drops within budget",
		WeatherFX.RAIN_DROPS <= GraphicsTiers.BUDGET_WEATHER_PARTICLES)
	_check("budget: snow flakes within budget",
		WeatherFX.SNOW_FLAKES <= GraphicsTiers.BUDGET_WEATHER_PARTICLES)


func _test_ambient_budget() -> void:
	var worst := AmbientFX.FIREFLY_COUNT + AmbientFX.LEAF_COUNT \
		+ AmbientFX.EMBER_COUNT * AmbientFX.MAX_EMBER_EMITTERS
	_check("budget: ambient worst-case within budget",
		worst <= GraphicsTiers.BUDGET_AMBIENT_PARTICLES)


func _test_combat_fx_budget() -> void:
	_check("budget: combat FX pool within budget",
		CombatFX.FX_POOL <= GraphicsTiers.BUDGET_FX_POOL)


func _test_building_fire_budget() -> void:
	_check("budget: concurrent building fires within budget",
		CombatFX.MAX_BUILDING_FIRES <= GraphicsTiers.BUDGET_BUILDING_FIRES)


func _test_audio_budget() -> void:
	var voices := AudioManager.SFX_POOL_SIZE + AudioManager.SFX2D_POOL_SIZE \
		+ AudioManager.MUSIC_PLAYERS + AudioManager.AMBIENCE_PLAYERS
	_check("budget: total audio voices within budget",
		voices <= GraphicsTiers.BUDGET_AUDIO_VOICES)


func _test_npc_budget() -> void:
	_check("budget: global NPC cap within budget",
		Config.POP_CAP_GLOBAL <= GraphicsTiers.BUDGET_NPCS)
	_check("budget: target fps is 60",
		GraphicsTiers.BUDGET_TARGET_FPS == 60)


## Every tier's knobs must be sane: particle multiplier in (0, 1], sync
## cadence >= 1 frame, tree fraction in (0, 1].
func _test_tier_knobs() -> void:
	for tier: String in GraphicsTiers.TIERS:
		var k := GraphicsTiers.knobs(tier)
		var pm := float(k["particle_mul"])
		_check("knobs %s: particle_mul in (0,1]" % tier, pm > 0.0 and pm <= 1.0)
		_check("knobs %s: unit_sync_every >= 1" % tier,
			int(k["unit_sync_every"]) >= 1)
		var tf := float(k["tree_draw_frac"])
		_check("knobs %s: tree_draw_frac in (0,1]" % tier,
			tf > 0.0 and tf <= 1.0)


func _test_resolve() -> void:
	_check("resolve: auto is a valid tier",
		GraphicsTiers.resolve("auto") in GraphicsTiers.TIERS)
	_check("resolve: blank is a valid tier",
		GraphicsTiers.resolve("") in GraphicsTiers.TIERS)
	_check("resolve: manual low respected",
		GraphicsTiers.resolve("low") == "low")
	_check("resolve: manual ultra respected",
		GraphicsTiers.resolve("ultra") == "ultra")
	_check("resolve: invalid falls back to medium",
		GraphicsTiers.resolve("banana") == "medium")


## The refactored detect() must still run headless and return a valid tier.
func _test_detect_runs_headless() -> void:
	var tier := GraphicsTiers.detect()
	_check("detect: headless returns a valid tier", tier in GraphicsTiers.TIERS)
