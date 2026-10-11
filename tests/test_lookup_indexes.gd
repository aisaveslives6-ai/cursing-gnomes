extends SceneTree
## Cursing Gnomes — O(1) lookup index tests (Jeremy 2026-10-05 perf).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_lookup_indexes.gd
##
## Exit code 0 = all passed, 1 = any failure.
## Covers: building_by_id / work_site_by_id stay in sync with the arrays,
## get_building/get_work_site return the LIVE record (mutations visible),
## erase_building drops both array and index, rebuild_lookup_indexes heals
## direct appends (save-load path), and the zone rect cache stays correct
## across paint/merge, dezone, and direct add_zone.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes lookup-index tests ===")
	_test_site_index_live()
	_test_site_fallback_heal()
	_test_building_index_live()
	_test_erase_building()
	_test_rebuild_after_direct_appends()
	_test_zone_cache_paint()
	_test_zone_cache_dezone()
	_test_zone_cache_add_zone()
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


func _gs() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])
	gs.zoning = SimZoning.new(gs)
	return gs


func _test_site_index_live() -> void:
	var gs: GameState = _gs()
	var s: Dictionary = gs.add_work_site({"kind": "bush",
		"position": Vector2(100, 100), "amount": 50.0})
	var fetched: Dictionary = gs.get_work_site(int(s["id"]))
	_check("site index: fetched by id", not fetched.is_empty())
	# Live reference: mutating the fetched record hits the array record.
	fetched["amount"] = 12.0
	_check("site index: live record shared", float(s["amount"]) == 12.0)
	_check("site index: missing id -> {}", gs.get_work_site(999999).is_empty())
	gs.queue_free()


func _test_site_fallback_heal() -> void:
	var gs: GameState = _gs()
	# Simulate a direct append bypassing add_work_site.
	var raw := {"id": 4242, "kind": "tree", "position": Vector2.ZERO, "amount": 9.0}
	gs.work_sites.append(raw)
	var fetched: Dictionary = gs.get_work_site(4242)
	_check("site fallback: direct append found", not fetched.is_empty())
	_check("site fallback: index self-healed",
		gs.work_site_by_id.has(4242))
	gs.queue_free()


func _test_building_index_live() -> void:
	var gs: GameState = _gs()
	var b: Dictionary = gs.add_building({"type": "town_hall", "faction": "humans",
		"town_id": 1, "position": Vector2(500, 500), "alive": true,
		"complete": true, "hp": 2000.0})
	var fetched: Dictionary = gs.get_building(int(b["id"]))
	_check("building index: fetched by id", not fetched.is_empty())
	fetched["hp"] = 1234.0
	_check("building index: live record shared", float(b["hp"]) == 1234.0)
	_check("building index: missing id -> {}", gs.get_building(999999).is_empty())
	gs.queue_free()


func _test_erase_building() -> void:
	var gs: GameState = _gs()
	var b: Dictionary = gs.add_building({"type": "hut", "faction": "gnomes",
		"town_id": 1, "position": Vector2(10, 10), "alive": true})
	var bid: int = int(b["id"])
	gs.erase_building(b)
	_check("erase_building: gone from array", not (b in gs.buildings))
	_check("erase_building: gone from index", not gs.building_by_id.has(bid))
	_check("erase_building: get_building -> {}", gs.get_building(bid).is_empty())
	gs.queue_free()


func _test_rebuild_after_direct_appends() -> void:
	var gs: GameState = _gs()
	gs.buildings.append({"id": 777, "type": "hut"})
	gs.work_sites.append({"id": 778, "kind": "bush", "amount": 5.0})
	gs.rebuild_lookup_indexes()
	_check("rebuild: building found", not gs.get_building(777).is_empty())
	_check("rebuild: site found", not gs.get_work_site(778).is_empty())
	gs.queue_free()


func _test_zone_cache_paint() -> void:
	var gs: GameState = _gs()
	gs.zoning.paint_zone(SimZoning.INDUSTRIAL, "humans",
		Rect2(Vector2(0, 0), Vector2(200, 200)))
	_check("zone cache: inside -> I",
		gs.zoning.zone_at(Vector2(100, 100), "humans") == SimZoning.INDUSTRIAL)
	_check("zone cache: outside -> empty",
		gs.zoning.zone_at(Vector2(500, 500), "humans") == "")
	_check("zone cache: other faction -> empty",
		gs.zoning.zone_at(Vector2(100, 100), "gnomes") == "")
	# Painting an overlapping zone merges; cache must reflect the union.
	gs.zoning.paint_zone(SimZoning.INDUSTRIAL, "humans",
		Rect2(Vector2(150, 150), Vector2(200, 200)))
	_check("zone cache: merged union covered",
		gs.zoning.zone_at(Vector2(300, 300), "humans") == SimZoning.INDUSTRIAL)
	gs.queue_free()


func _test_zone_cache_dezone() -> void:
	var gs: GameState = _gs()
	gs.zoning.paint_zone(SimZoning.MILITARY, "humans",
		Rect2(Vector2(0, 0), Vector2(400, 400)))
	var touched: int = gs.zoning.dezone("humans",
		Rect2(Vector2(0, 0), Vector2(400, 400)))
	_check("dezone touched", touched > 0)
	_check("zone cache: fully dezoned -> empty",
		gs.zoning.zone_at(Vector2(100, 100), "humans") == "")
	gs.queue_free()


func _test_zone_cache_add_zone() -> void:
	var gs: GameState = _gs()
	# Warm the cache with a first lookup, then mutate directly.
	gs.zoning.paint_zone(SimZoning.RESIDENTIAL, "gnomes",
		Rect2(Vector2(0, 0), Vector2(100, 100)))
	_check("zone cache: warm hit",
		gs.zoning.zone_at(Vector2(50, 50), "gnomes") == SimZoning.RESIDENTIAL)
	gs.add_zone({"type": SimZoning.COMMERCIAL, "faction": "gnomes",
		"rect": Rect2(Vector2(500, 500), Vector2(100, 100))})
	_check("zone cache: add_zone visible",
		gs.zoning.zone_at(Vector2(550, 550), "gnomes") == SimZoning.COMMERCIAL)
	gs.queue_free()
