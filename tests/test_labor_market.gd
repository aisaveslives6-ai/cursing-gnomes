extends SceneTree
## Cursing Gnomes — labor market tests (AI-first phase).
##
## Covers the NPC-behavior / Worker-AI checklist items "jobs" and "labor":
## port of HTML fix79 stage8LaborTick's satisfaction model
## (s8SatisfactionSlice, verbatim economics) and farm staffing
## (s8FillFarmPosts, verbatim):
##   - jobSat 0..100 drifts 6% toward 55 each pass; pay matters
##     ((wage - 2.5) * 1.5, S8_WAGE verbatim); military -2; farmer on
##     assigned land +1.5; shopkeeper/cashier at living shop +1;
##     homeless -1.5; downed -4
##   - each farm plot gets one owner (jobSat 62) + up to 3 hands
##     (jobSat 60), hired from seekers nearest-first; idle jobless first,
##     then dissatisfied (jobSat < 25) switchers
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_labor_market.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes labor market tests ===")
	_test_drift_to_neutral()
	_test_pay_matters()
	_test_military_penalty()
	_test_farmer_land_bonus()
	_test_shopkeeper_shop_bonus()
	_test_homeless_hurts()
	_test_downed_penalty()
	_test_clamp()
	_test_owner_hired()
	_test_hands_capped_at_three()
	_test_seeker_skips()
	_test_dissatisfied_switcher_poached()
	_test_dead_workers_pruned()
	_test_nearest_first()
	_test_layoff_clears_plot_link()
	_test_stale_plot_link_cleared()
	_test_assigned_plot_preferred()
	_test_plot_record_staffing_fields()
	_test_tick_runs_labor_pass()
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


func _close(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) < eps


## Fresh game + hiring + farming.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	gs.farming = SimFarming.new(gs)
	var hiring := GuildHiring.new(gs)
	gs.hiring = hiring
	return {"gs": gs, "hiring": hiring, "farming": gs.farming}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _unit(w: Dictionary, job: String, faction: String = "humans",
		pos: Vector2 = Vector2(5000, 5000)) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_unit({
		"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true,
		"hp": 100.0, "max_hp": 100.0,
		"home": {"alive": true},  # homed unless a test says otherwise
	})


func _plot(w: Dictionary, faction: String = "humans",
		pos: Vector2 = Vector2(5100, 5100)) -> Dictionary:
	var farming: SimFarming = w["farming"]
	return farming.create_plot(faction, pos, -1, true)


## --- satisfaction -----------------------------------------------------------

func _test_drift_to_neutral() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var hi: Dictionary = _unit(w, "worker")
	hi["jobSat"] = 80.0
	var lo: Dictionary = _unit(w, "worker")
	lo["jobSat"] = 40.0
	hiring._tick_satisfaction()
	# worker wage 2.5 -> pay term 0; drift only: 80 - 1.5, 40 + 0.9
	_check("drift high falls", _close(float(hi["jobSat"]), 78.5))
	_check("drift low rises", _close(float(lo["jobSat"]), 40.9))
	_free_world(w)


func _test_pay_matters() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var sol: Dictionary = _unit(w, "soldier")
	sol["jobSat"] = 60.0
	var rb: Dictionary = _unit(w, "roadbuilder")
	rb["jobSat"] = 60.0
	hiring._tick_satisfaction()
	# soldier: -0.3 drift +0.75 pay -2 duty = 58.45
	# roadbuilder: -0.3 drift -0.45 pay = 59.25
	_check("soldier sat", _close(float(sol["jobSat"]), 58.45))
	_check("roadbuilder sat", _close(float(rb["jobSat"]), 59.25))
	_free_world(w)


func _test_military_penalty() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var sol: Dictionary = _unit(w, "soldier")
	sol["jobSat"] = 60.0
	var bld: Dictionary = _unit(w, "builder")
	bld["jobSat"] = 60.0
	hiring._tick_satisfaction()
	_check("military below civilian",
		float(sol["jobSat"]) < float(bld["jobSat"]))
	_free_world(w)


func _test_farmer_land_bonus() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var plot: Dictionary = _plot(w)
	var landed: Dictionary = _unit(w, "farmer")
	landed["jobSat"] = 60.0
	landed["_farm_plot_id"] = int(plot["id"])
	var free: Dictionary = _unit(w, "farmer")
	free["jobSat"] = 60.0
	hiring._tick_satisfaction()
	# landed: -0.3 + 0.15 (farmer wage 2.6) + 1.5 = 61.35
	# free:   -0.3 + 0.15 = 59.85
	_check("landed farmer bonus", _close(float(landed["jobSat"]), 61.35))
	_check("free farmer no bonus", _close(float(free["jobSat"]), 59.85))
	_free_world(w)


func _test_shopkeeper_shop_bonus() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var gs: GameState = w["gs"]
	var shop: Dictionary = gs.add_building({
		"type": "shop", "faction": "humans", "town_id": -1,
		"position": Vector2(5000, 5000), "complete": true,
		"alive": true, "hp": 450.0, "max_hp": 450.0,
	})
	var staffed: Dictionary = _unit(w, "shopkeeper")
	staffed["jobSat"] = 60.0
	staffed["station"] = {"job": "shopkeeper",
		"building_id": int(shop["id"])}
	var dead_shop: Dictionary = gs.add_building({
		"type": "shop", "faction": "humans", "town_id": -1,
		"position": Vector2(5200, 5200), "complete": true,
		"alive": false, "hp": 0.0, "max_hp": 450.0,
	})
	var unstaffed: Dictionary = _unit(w, "shopkeeper")
	unstaffed["jobSat"] = 60.0
	unstaffed["station"] = {"job": "shopkeeper",
		"building_id": int(dead_shop["id"])}
	hiring._tick_satisfaction()
	# staffed: -0.3 -0.15 (wage 2.4) + 1 = 60.55
	_check("shopkeeper living shop bonus",
		_close(float(staffed["jobSat"]), 60.55))
	_check("shopkeeper dead shop no bonus",
		float(unstaffed["jobSat"]) < float(staffed["jobSat"]))
	_free_world(w)


func _test_homeless_hurts() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var housed: Dictionary = _unit(w, "worker")
	housed["jobSat"] = 60.0
	var homeless: Dictionary = _unit(w, "worker")
	homeless["jobSat"] = 60.0
	homeless["home"] = {}
	hiring._tick_satisfaction()
	# housed: 59.7 ; homeless: 59.7 - 1.5 = 58.2
	_check("homeless penalty", _close(float(homeless["jobSat"]), 58.2))
	_check("housed no penalty", _close(float(housed["jobSat"]), 59.7))
	_free_world(w)


func _test_downed_penalty() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var u: Dictionary = _unit(w, "worker")
	u["jobSat"] = 60.0
	u["downed"] = true
	hiring._tick_satisfaction()
	_check("downed penalty", _close(float(u["jobSat"]), 55.7))
	_free_world(w)


func _test_clamp() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var u: Dictionary = _unit(w, "roadbuilder")
	u["jobSat"] = 1.0
	u["home"] = {}
	u["downed"] = true
	hiring._tick_satisfaction()
	# 1 + 3.24 - 0.45 - 1.5 - 4 = -1.71 -> clamped to 0
	_check("clamped at zero", _close(float(u["jobSat"]), 0.0))
	var v: Dictionary = _unit(w, "shopkeeper")
	v["jobSat"] = 100.0
	hiring._tick_satisfaction()
	_check("never above 100", float(v["jobSat"]) <= 100.0)
	_free_world(w)


## --- farm vacancy fill ------------------------------------------------------

func _test_owner_hired() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var plot: Dictionary = _plot(w)
	var seeker: Dictionary = _unit(w, "unemployed")
	hiring._fill_farm_posts()
	_check("owner uid set", int(plot["owner_uid"]) == int(seeker["id"]))
	_check("owner job farmer", String(seeker["job"]) == "farmer")
	_check("owner sat 62", _close(float(seeker["jobSat"]), 62.0))
	_check("owner plot link",
		int(seeker["_farm_plot_id"]) == int(plot["id"]))
	_free_world(w)


func _test_hands_capped_at_three() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var plot: Dictionary = _plot(w)
	for i in 6:
		_unit(w, "unemployed", "humans", Vector2(5000 + i * 10, 5000))
	hiring._fill_farm_posts()
	_check("owner hired", int(plot["owner_uid"]) > 0)
	_check("three hands hired", (plot["worker_uids"] as Array).size() == 3)
	var farmers := 0
	var gs: GameState = w["gs"]
	for u: Dictionary in gs.units:
		if String(u.get("job", "")) == "farmer":
			farmers += 1
	_check("owner + 3 hands = 4 farmers", farmers == 4)
	var hands_sat_ok := true
	for wid in plot["worker_uids"]:
		var wu: Dictionary = gs.get_unit(int(wid))
		if not _close(float(wu.get("jobSat", 0.0)), 60.0):
			hands_sat_ok = false
	_check("hands sat 60", hands_sat_ok)
	_free_world(w)


func _test_seeker_skips() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var plot: Dictionary = _plot(w)
	# None of these may be poached, even when "unemployed".
	var sol: Dictionary = _unit(w, "soldier")
	sol["jobSat"] = 10.0  # dissatisfied but military: can't quit mid-term
	var lead: Dictionary = _unit(w, "unemployed")
	lead["is_leader"] = true
	var officer: Dictionary = _unit(w, "unemployed")
	if not officer.has("mind"):
		officer["mind"] = {}
	(officer["mind"] as Dictionary)["gov_role"] = "adviser"
	var ordered: Dictionary = _unit(w, "unemployed")
	ordered["player_order"] = {"kind": "move"}
	var tripping: Dictionary = _unit(w, "unemployed")
	tripping["mind_state"] = "satisfying:eat"
	var besieged: Dictionary = _unit(w, "unemployed")
	besieged["_siege_hide"] = true
	var homesteader: Dictionary = _unit(w, "unemployed")
	homesteader["_homestead"] = true
	hiring._fill_farm_posts()
	_check("no owner from skips", int(plot["owner_uid"]) == -1)
	_check("no hands from skips", (plot["worker_uids"] as Array).is_empty())
	for u: Dictionary in [sol, lead, officer, ordered, tripping, besieged,
			homesteader]:
		_check("skip kept job %s" % String(u.get("job", "")),
			String(u.get("job", "")) != "farmer")
	_free_world(w)


func _test_dissatisfied_switcher_poached() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var gs: GameState = w["gs"]
	var plot: Dictionary = _plot(w)
	var shop: Dictionary = gs.add_building({
		"type": "shop", "faction": "humans", "town_id": -1,
		"position": Vector2(5000, 5000), "complete": true,
		"alive": true, "hp": 450.0, "max_hp": 450.0,
	})
	var keeper: Dictionary = _unit(w, "shopkeeper")
	keeper["station"] = {"job": "shopkeeper",
		"building_id": int(shop["id"])}
	keeper["jobSat"] = 20.0  # grounded reason to switch (HTML < 25)
	hiring._fill_farm_posts()
	_check("dissatisfied poached to farm",
		String(keeper["job"]) == "farmer")
	_check("old station cleared", (keeper["station"] as Dictionary).is_empty())
	_free_world(w)


func _test_dead_workers_pruned() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var gs: GameState = w["gs"]
	var plot: Dictionary = _plot(w)
	var dead: Dictionary = _unit(w, "farmer")
	dead["alive"] = false
	var alive: Dictionary = _unit(w, "farmer")
	plot["worker_uids"] = [int(dead["id"]), int(alive["id"])]
	var seeker_a: Dictionary = _unit(w, "unemployed")
	var seeker_b: Dictionary = _unit(w, "unemployed")
	hiring._fill_farm_posts()
	var wids: Array = plot["worker_uids"]
	_check("dead pruned", not wids.has(int(dead["id"])))
	_check("alive kept", wids.has(int(alive["id"])))
	# seeker_a becomes owner (owner_uid was -1); seeker_b refills a hand slot.
	_check("owner vacancy refilled", int(plot["owner_uid"]) > 0)
	_check("hand vacancy refilled",
		wids.has(int(seeker_a["id"])) or wids.has(int(seeker_b["id"])))
	_free_world(w)


func _test_nearest_first() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var plot: Dictionary = _plot(w, "humans", Vector2(5100, 5100))
	var far: Dictionary = _unit(w, "unemployed", "humans", Vector2(9000, 9000))
	var near: Dictionary = _unit(w, "unemployed", "humans", Vector2(5110, 5110))
	hiring._fill_farm_posts()
	_check("nearest becomes owner",
		int(plot["owner_uid"]) == int(near["id"]))
	_check("far not owner", int(plot["owner_uid"]) != int(far["id"]))
	_free_world(w)


func _test_layoff_clears_plot_link() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var plot: Dictionary = _plot(w)
	var seeker: Dictionary = _unit(w, "unemployed")
	hiring._fill_farm_posts()
	_check("hired first", String(seeker["job"]) == "farmer")
	hiring.lay_off(seeker, "test")
	_check("layoff clears plot link", not seeker.has("_farm_plot_id"))
	_free_world(w)


func _test_stale_plot_link_cleared() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var u: Dictionary = _unit(w, "farmer")
	u["_farm_plot_id"] = 99999  # plot that does not exist
	hiring._fill_farm_posts()
	_check("stale link erased", not u.has("_farm_plot_id"))
	_free_world(w)


func _test_assigned_plot_preferred() -> void:
	var w := _new_world()
	var farming: SimFarming = w["farming"]
	var near_plot: Dictionary = _plot(w, "humans", Vector2(5000, 5000))
	var far_plot: Dictionary = _plot(w, "humans", Vector2(9000, 9000))
	# Give both plots pending work: plant a crop-less tile with seeds.
	for p: Dictionary in [near_plot, far_plot]:
		(p["tiles"] as Array)[0]["crop"] = null
		p["seed_bin"] = 4
	var pos := Vector2(5010, 5010)  # right next to near_plot
	var plain: Dictionary = farming.nearest_work_plot("humans", pos)
	_check("no preference -> nearest",
		int(plain["id"]) == int(near_plot["id"]))
	var pref: Dictionary = farming.nearest_work_plot("humans", pos,
		int(far_plot["id"]))
	_check("assigned plot preferred",
		int(pref["id"]) == int(far_plot["id"]))
	_free_world(w)


func _test_plot_record_staffing_fields() -> void:
	var w := _new_world()
	var plot: Dictionary = _plot(w)
	_check("owner_uid defaults -1", int(plot["owner_uid"]) == -1)
	_check("worker_uids defaults empty",
		(plot["worker_uids"] as Array).is_empty())
	_free_world(w)


func _test_tick_runs_labor_pass() -> void:
	var w := _new_world()
	var hiring: GuildHiring = w["hiring"]
	var u: Dictionary = _unit(w, "worker")
	u["jobSat"] = 80.0
	hiring.tick(4.0, 12.0)
	_check("tick runs satisfaction", float(u["jobSat"]) < 80.0)
	_free_world(w)
