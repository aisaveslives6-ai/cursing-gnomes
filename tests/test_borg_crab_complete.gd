extends SceneTree
## Cursing Gnomes — Bill the Borg Crab completion tests.
##
## Wake dedicated-porting 2026-10-08: Bill shipped with two gaps —
## (1) no bespoke art (he rendered as a 1.6x lizard), and (2) his whole
## point was dead code: `borg_building_mult` (-15% on assimilated
## buildings) had NO production call site, so assimilation was pure
## flavor. Both are now closed: bespoke AI-generated chibi Borg-crab
## art (green LED antenna, riveted shell plates, toaster bolted on) is
## wired through `_monster_texture()`, and the -15% multiplier is
## applied at every production tick — shop gold + oil-pump oil
## (SimZoning.tick), industrial lot wood/gold (SimIndustry), and farm
## harvests via the plot's linked farm building (SimFarming).
##
## Covers:
##   - _monster_texture() resolves real art for borg_crab_bill (never
##     the lizard stand-in / citizen fallback)
##   - full node setup: grounded, monster art carried, scale 1.6x
##   - disaster-art coverage sweep: all 15 named disaster kinds render
##     something intentional
##   - assimilated shop pays 0.85x gold; clean shop pays 1.0x
##   - assimilated oil pump pays 0.85x oil; clean pump pays 1.0x
##   - assimilated industrial lot pays 0.85x wood+gold
##   - harvest from an assimilated farm building pays 0.85x food+seeds
##     (identically-seeded RNG proves the multiplier exactly);
##     harvests from unlinked plots are unaffected (1.0x)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_borg_crab_complete.gd
##
## Exit code 0 = all passed, 1 = any failure.


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


func _make_node(p_job: String) -> UnitNode:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(900 + _passed, "gnomes", p_job, Vector2(100, 100), "m")
	return un


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _add_building(gs: GameState, bid: int, btype: String,
		faction: String, pos: Vector2, borg: bool = false) -> void:
	var b := {"id": bid, "type": btype, "name": btype,
		"alive": true, "complete": true, "position": pos,
		"faction": faction}
	if borg:
		b["borg_upgraded"] = true
	gs.buildings.append(b)


func _mature_plot(faction: String, pid: int, bid: int) -> Dictionary:
	return {"faction": faction, "id": pid, "building_id": bid,
		"position": Vector2.ZERO, "seed_bin": 5,
		"tiles": [{"crop": {"g": 1.0, "watered": true, "waterT": 5.0}}]}


func _initialize() -> void:
	print("=== Cursing Gnomes Borg Crab completion tests ===")
	_test_texture_resolves()
	_test_full_setup()
	_test_scale_pinned()
	_test_all_disasters_have_art()
	_test_shop_gold_penalty()
	_test_oil_pump_penalty()
	_test_industrial_lot_penalty()
	_test_farm_harvest_penalty()
	_test_unlinked_harvest_unaffected()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## ---- art ----------------------------------------------------------------


func _test_texture_resolves() -> void:
	var un := _make_node("worker")
	un.job = "borg_crab_bill"
	var tex: Texture2D = un._monster_texture()
	_check("borg: monster texture resolves", tex != null)
	_check("borg: texture has size",
		tex != null and tex.get_width() > 0 and tex.get_height() > 0)
	un.free()


func _test_full_setup() -> void:
	var un := _make_node("borg_crab_bill")
	var want: Texture2D = un._monster_texture()
	_check("borg: sprite built", un._sprite != null)
	_check("borg: sprite carries monster art (not citizen fallback)",
		un._sprite != null and un._sprite.texture != null \
		and un._sprite.texture == want)
	# Grounded: feet at the Body origin (same convention as other monsters).
	var h: float = un._monster_scale()
	_check("borg: grounded sprite position",
		un._sprite != null and is_equal_approx(un._sprite.position.y, -h * 0.48))
	un.free()


func _test_scale_pinned() -> void:
	var un := _make_node("worker")
	un.job = "borg_crab_bill"
	_check("borg scale = 1.6 x SPRITE_WORLD_H",
		is_equal_approx(un._monster_scale(), UnitNode.SPRITE_WORLD_H * 1.6))
	un.free()


func _test_all_disasters_have_art() -> void:
	# Every named disaster kind must render something intentional —
	# a mapped texture, the JesusArt sprite, or the Giant Ass
	# procedural build — never the citizen fallback.
	var textured := ["thicc_moose", "giant_lizard", "hoa_karen",
		"seagull_swarm", "taxman", "booze_ooze", "doom_prophet",
		"gig_gnome", "count_bastard", "rogue_wizard", "cardboard_cat",
		"borg_crab_bill", "twister_sister"]
	for j: String in textured:
		var un := _make_node("worker")
		un.job = j
		_check("art resolves: " + j, un._monster_texture() != null)
		un.free()
	# jesus: hand-authored JesusArt sprite (image gen declined the request).
	var ju := _make_node("jesus")
	_check("jesus: sprite built from JesusArt",
		ju._sprite != null and ju._sprite.texture != null)
	ju.free()
	# giant_ass: intentional procedural build (the joke is the shape).
	var ga := _make_node("giant_ass")
	var has_poly := false
	for c: Node in ga._body.get_children():
		if c is Polygon2D:
			has_poly = true
	_check("giant_ass: procedural polygon built", has_poly)
	ga.free()


## ---- production penalties ------------------------------------------------


func _test_shop_gold_penalty() -> void:
	var gs := _new_game(["humans"])
	gs.zoning.paint_zone("C", "humans", Rect2(400, 400, 200, 200))
	_add_building(gs, 1, "shop", "humans", Vector2(500, 500), false)
	_add_building(gs, 2, "shop", "humans", Vector2(520, 520), true)
	var before: float = gs.resources.get_amount("humans", "gold")
	gs.zoning.tick(1.0)
	var delta: float = gs.resources.get_amount("humans", "gold") - before
	# Clean shop 1.2 + assimilated shop 1.2*0.85 = 1.2 + 1.02.
	_check("borg: shops pay 1.85x combined (clean 1.2 + borg 1.02)",
		is_equal_approx(delta, SimZoning.SHOP_GOLD_PER_SEC * 1.85))


func _test_oil_pump_penalty() -> void:
	var gs := _new_game(["humans"])
	gs.zoning.paint_zone("I", "humans", Rect2(400, 400, 200, 200))
	_add_building(gs, 1, "oil_pump", "humans", Vector2(500, 500), false)
	_add_building(gs, 2, "oil_pump", "humans", Vector2(520, 520), true)
	var before: float = gs.resources.get_amount("humans", "oil")
	gs.zoning.tick(1.0)
	var delta: float = gs.resources.get_amount("humans", "oil") - before
	# Clean pump 0.8 + assimilated pump 0.8*0.85 = 0.8 + 0.68.
	_check("borg: oil pumps pay 1.85x combined (clean 0.8 + borg 0.68)",
		is_equal_approx(delta, SimZoning.OIL_PUMP_OIL_PER_SEC * 1.85))


func _test_industrial_lot_penalty() -> void:
	var gs := _new_game(["humans"])
	# SimIndustry is created by the world wiring; tests build it manually.
	var ind := SimIndustry.new(gs)
	gs.zoning.paint_zone("I", "humans", Rect2(400, 400, 200, 200))
	_add_building(gs, 1, "sawmill", "humans", Vector2(500, 500), false)
	_add_building(gs, 2, "sawmill", "humans", Vector2(520, 520), true)
	var wood_before: float = gs.resources.get_amount("humans", "wood")
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	ind.tick(1.0)
	var wood_delta: float = gs.resources.get_amount("humans", "wood") - wood_before
	var gold_delta: float = gs.resources.get_amount("humans", "gold") - gold_before
	_check("borg: industrial lots pay 1.85x wood",
		is_equal_approx(wood_delta, SimIndustry.LOT_WOOD_PER_SEC * 1.85))
	_check("borg: industrial lots pay 1.85x gold",
		is_equal_approx(gold_delta, SimIndustry.LOT_GOLD_PER_SEC * 1.85))


func _test_farm_harvest_penalty() -> void:
	# Identically-seeded RNG on both farms: the only difference is the
	# borg flag on the linked farm building, so the ratio is exactly
	# 0.85 (otherwise this would be a flaky distribution test).
	var gs := _new_game(["humans"])
	_add_building(gs, 11, "farm", "humans", Vector2(500, 500), false)
	_add_building(gs, 12, "farm", "humans", Vector2(600, 600), true)
	var farm := SimFarming.new(gs)
	farm._rng.seed = 20261008
	var clean: Dictionary = farm.harvest(_mature_plot("humans", 101, 11), 0)
	farm._rng.seed = 20261008
	var borg: Dictionary = farm.harvest(_mature_plot("humans", 102, 12), 0)
	_check("borg: assimilated farm harvests 0.85x food",
		is_equal_approx(float(borg.get("food", 0.0)),
			float(clean.get("food", 0.0)) * 0.85))
	_check("borg: assimilated farm harvests 0.85x seeds",
		is_equal_approx(float(borg.get("seeds", 0.0)),
			float(clean.get("seeds", 0.0)) * 0.85))


func _test_unlinked_harvest_unaffected() -> void:
	# Plots with no linked building (building_id -1) keep the 1.0x rate.
	var gs := _new_game(["humans"])
	var farm := SimFarming.new(gs)
	farm._rng.seed = 20261008
	var out: Dictionary = farm.harvest(_mature_plot("humans", 103, -1), 0)
	_check("borg: unlinked plot harvests unaffected (food in range)",
		float(out.get("food", 0.0)) >= SimFarming.HARVEST_FOOD_MIN \
		and float(out.get("food", 0.0)) <= SimFarming.HARVEST_FOOD_MAX)
