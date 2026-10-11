extends SceneTree
## Tests for peace reparations (HTML war-tree parity, C62):
## suing for peace costs clamp(round(their gold * 0.1 + 200), 100, 1500),
## charged by the phone diplomacy board before make_peace runs.
##
## Run: Godot --headless --path . -s res://tests/test_diplomacy_reparations.gd

var _passed := 0
var _failed := 0
var _failures: Array = []


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)
		print("FAIL: ", name)


func _initialize() -> void:
	_test_reparation_formula()
	_test_reparation_flow()
	_test_unaffordable_blocks_peace()
	print("test_diplomacy_reparations: %d passed, %d failed" % [_passed, _failed])
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.player_faction = "humans"
	return {"gs": gs, "dip": gs.diplomacy}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _set_gold(gs: GameState, faction: String, amount: float) -> void:
	# Reset then set exactly (bypass cap so big treasuries test the ceiling).
	gs.resources.add_resource(faction, "gold",
		-gs.resources.get_amount(faction, "gold"), true)
	gs.resources.add_resource(faction, "gold", amount, true)


## --- formula -----------------------------------------------------------------


func _test_reparation_formula() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var gs: GameState = w["gs"]
	# HTML: rep = clamp(round(theirGold * 0.1 + 200), 100, 1500).
	_set_gold(gs, "ogres", 0.0)
	_check(dip.reparation_cost("ogres") == 200, "zero treasury -> 200g")
	_set_gold(gs, "ogres", 5000.0)
	_check(dip.reparation_cost("ogres") == 700, "5000g treasury -> 700g")
	_set_gold(gs, "ogres", 1234.0)
	_check(dip.reparation_cost("ogres") == 323, "1234g treasury -> 323g (rounded)")
	_set_gold(gs, "ogres", 20000.0)
	_check(dip.reparation_cost("ogres") == 1500, "20000g treasury -> clamped 1500g")
	_set_gold(gs, "ogres", 100000.0)
	_check(dip.reparation_cost("ogres") == 1500, "100000g treasury -> clamped 1500g")
	# Uses the TARGET's treasury, not the player's.
	_set_gold(gs, "ogres", 3000.0)
	_set_gold(gs, "humans", 99999.0)
	_check(dip.reparation_cost("ogres") == 500, "cost from target treasury (500g)")
	_free_world(w)


## --- full buy-peace flow (what the phone button does) ------------------------


func _test_reparation_flow() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var gs: GameState = w["gs"]
	dip.declare_war("humans", "ogres", "test")
	_set_gold(gs, "ogres", 3000.0)   # rep = 500
	_set_gold(gs, "humans", 10000.0)
	var rep: int = dip.reparation_cost("ogres")
	_check(rep == 500, "war flow: rep computed as 500g")
	_check(gs.resources.can_afford("humans", {"gold": float(rep)}),
		"war flow: player can afford reparations")
	_check(gs.resources.spend("humans", {"gold": float(rep)}),
		"war flow: spend deducts reparations")
	_check(int(gs.resources.get_amount("humans", "gold")) == 9500,
		"war flow: treasury reduced by exactly rep")
	var r: Dictionary = dip.make_peace("humans", "ogres")
	_check(bool(r.get("ok", false)), "war flow: make_peace succeeds after payment")
	_check(dip.relation_state("humans", "ogres") != "war",
		"war flow: war ends after paid peace")
	_free_world(w)


func _test_unaffordable_blocks_peace() -> void:
	var w: Dictionary = _new_world()
	var dip: SimDiplomacy = w["dip"]
	var gs: GameState = w["gs"]
	dip.declare_war("humans", "ogres", "test")
	_set_gold(gs, "ogres", 3000.0)  # rep = 500
	_set_gold(gs, "humans", 100.0)  # cannot afford
	var rep: int = dip.reparation_cost("ogres")
	_check(not gs.resources.can_afford("humans", {"gold": float(rep)}),
		"broke flow: player cannot afford 500g reparations")
	_check(not gs.resources.spend("humans", {"gold": float(rep)}),
		"broke flow: spend fails atomically")
	_check(int(gs.resources.get_amount("humans", "gold")) == 100,
		"broke flow: treasury untouched after failed spend")
	_check(dip.relation_state("humans", "ogres") == "war",
		"broke flow: war continues when reparations unpaid")
	_free_world(w)
