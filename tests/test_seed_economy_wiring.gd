extends SceneTree
## Cursing Gnomes — seed-shop economy wiring tests (2026-10-05 launch-readiness).
##
## The seedshop buy path (buy_seeds) and the harvest restock path (shop
## seedStock) had zero callers: a buildable building with art, cost, and
## description did nothing. These tests pin the wiring:
##   - ledger-dry bootstrap buys from the faction's own shops (5 gold each),
##   - harvest overflow past the ledger cap restocks shop inventory,
##   - common-case behavior (ledger has room, no shop, broke faction) is
##     unchanged.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_seed_economy_wiring.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes seed-shop economy wiring tests ===")
	_test_bootstrap_buy()
	_test_bootstrap_partial_gold()
	_test_bootstrap_no_shop()
	_test_bootstrap_no_gold()
	_test_bootstrap_stocked_noop()
	_test_bootstrap_then_fill_bin()
	_test_harvest_overflow_restocks_shop()
	_test_harvest_overflow_no_shop()
	_test_harvest_overflow_shop_full()
	_test_harvest_normal_no_overflow()
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


func _shop(gs: GameState, faction: String, pos: Vector2) -> Dictionary:
	return gs.add_building({"type": "seedshop", "faction": faction,
		"position": pos, "alive": true, "complete": true})


func _mature_plot(f: SimFarming, faction: String) -> Dictionary:
	var plot: Dictionary = f.create_plot(faction, Vector2(50, 50), -1, true)
	f.plant(plot, 0)
	f.tick(1.5 * Config.DAY_LENGTH_SECONDS)  # no seasons -> neutral growth
	return plot


## ---- buy bootstrap --------------------------------------------------------


func _test_bootstrap_buy() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var shop := _shop(gs, "humans", Vector2(60, 60))
	gs.resources.add_resource("humans", "gold", 200.0)
	# Ledger starts dry (0 seeds).
	var bought: int = f.ensure_seed_supply("humans", 4)
	_check("bootstrap buys 4", bought == 4)
	_check("bootstrap ledger", is_equal_approx(
		gs.resources.get_amount("humans", "seeds"), 4.0))
	_check("bootstrap gold spent", is_equal_approx(
		gs.resources.get_amount("humans", "gold"), 180.0))
	_check("bootstrap shop stock down", int(shop.get("seedStock", -1)) == 21)
	gs.queue_free()


func _test_bootstrap_partial_gold() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var shop := _shop(gs, "humans", Vector2(60, 60))
	gs.resources.add_resource("humans", "gold", 7.0)  # affords 1 seed
	var bought: int = f.ensure_seed_supply("humans", 4)
	_check("partial buy 1", bought == 1)
	_check("partial gold left", is_equal_approx(
		gs.resources.get_amount("humans", "gold"), 2.0))
	_check("partial shop stock", int(shop.get("seedStock", -1)) == 24)
	gs.queue_free()


func _test_bootstrap_no_shop() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	gs.resources.add_resource("humans", "gold", 200.0)
	var bought: int = f.ensure_seed_supply("humans", 4)
	_check("no shop buys 0", bought == 0)
	_check("no shop gold untouched", is_equal_approx(
		gs.resources.get_amount("humans", "gold"), 200.0))
	gs.queue_free()


func _test_bootstrap_no_gold() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	_shop(gs, "humans", Vector2(60, 60))
	var bought: int = f.ensure_seed_supply("humans", 4)
	_check("broke buys 0", bought == 0)
	gs.queue_free()


func _test_bootstrap_stocked_noop() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var shop := _shop(gs, "humans", Vector2(60, 60))
	gs.resources.add_resource("humans", "gold", 200.0)
	gs.resources.add_resource("humans", "seeds", 50.0)
	var bought: int = f.ensure_seed_supply("humans", 4)
	_check("stocked no buy", bought == 0)
	_check("stocked gold untouched", is_equal_approx(
		gs.resources.get_amount("humans", "gold"), 200.0))
	# Shop never used: stock key stays implicit (25 on first touch).
	_check("stocked shop untouched", not shop.has("seedStock")
		or int(shop.get("seedStock", 0)) == 25)
	gs.queue_free()


func _test_bootstrap_then_fill_bin() -> void:
	# The _top_up_seed_bins call sequence: dry ledger -> bootstrap -> fill.
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	_shop(gs, "humans", Vector2(60, 60))
	gs.resources.add_resource("humans", "gold", 200.0)
	var plot: Dictionary = f.create_plot("humans", Vector2(50, 50), -1, true)
	plot["seed_bin"] = 0
	var bought: int = f.ensure_seed_supply("humans", 4)
	_check("seq bootstrap", bought == 4)
	var filled: int = f.fill_seed_bin(plot, 4)
	_check("seq fill 4", filled == 4)
	_check("seq bin refilled", int(plot.get("seed_bin", -1)) == 4)
	_check("seq ledger drained", is_equal_approx(
		gs.resources.get_amount("humans", "seeds"), 0.0))
	gs.queue_free()


## ---- harvest overflow restock ----------------------------------------------


func _test_harvest_overflow_restocks_shop() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var shop := _shop(gs, "humans", Vector2(60, 60))
	var plot := _mature_plot(f, "humans")
	# Pin the ledger at its cap (150): every harvested seed overflows.
	gs.resources.add_resource("humans", "seeds", 150.0)
	var out: Dictionary = f.harvest(plot, 0)
	_check("overflow harvest yields seeds", float(out.get("seeds", 0.0)) >= 2.0)
	_check("overflow ledger stays capped", is_equal_approx(
		gs.resources.get_amount("humans", "seeds"), 150.0))
	var stock: int = int(shop.get("seedStock", -1))
	_check("overflow restocks shop", stock >= 27 and stock <= 29)
	gs.queue_free()


func _test_harvest_overflow_no_shop() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var plot := _mature_plot(f, "humans")
	gs.resources.add_resource("humans", "seeds", 150.0)
	var out: Dictionary = f.harvest(plot, 0)
	_check("no-shop harvest ok", float(out.get("seeds", 0.0)) >= 2.0)
	_check("no-shop ledger capped", is_equal_approx(
		gs.resources.get_amount("humans", "seeds"), 150.0))
	gs.queue_free()


func _test_harvest_overflow_shop_full() -> void:
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var shop := _shop(gs, "humans", Vector2(60, 60))
	shop["seedStock"] = SimFarming.SEEDSHOP_CAP
	var plot := _mature_plot(f, "humans")
	gs.resources.add_resource("humans", "seeds", 150.0)
	f.harvest(plot, 0)
	_check("full shop stays capped",
		int(shop.get("seedStock", -1)) == SimFarming.SEEDSHOP_CAP)
	_check("full shop ledger capped", is_equal_approx(
		gs.resources.get_amount("humans", "seeds"), 150.0))
	gs.queue_free()


func _test_harvest_normal_no_overflow() -> void:
	# Common case unchanged: ledger has room -> seeds bank there, shop idle.
	var gs := _new_game(["humans"])
	var f := SimFarming.new(gs)
	var shop := _shop(gs, "humans", Vector2(60, 60))
	var plot := _mature_plot(f, "humans")
	var out: Dictionary = f.harvest(plot, 0)
	var got: float = float(out.get("seeds", 0.0))
	_check("normal harvest yields", got >= 2.0 and got <= 4.0)
	_check("normal ledger banks seeds", is_equal_approx(
		gs.resources.get_amount("humans", "seeds"), got))
	# No overflow: shop stock key stays implicit (25 on first touch).
	_check("normal shop untouched", not shop.has("seedStock")
		or int(shop.get("seedStock", 0)) == 25)
	gs.queue_free()
