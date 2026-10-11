extends SceneTree
## Cursing Gnomes — Gazette coverage completion tests.
## Jeremy's 2026-10-06 audit left one open item: "Gazette headline coverage
## (beyond lord_seethes) vs HTML gazNews calls". A systematic diff of every
## HTML fix79 gazNews headline against the port found exactly two silent
## events — real things that happen in the sim but never make the paper:
##   (1) GUNS CREWED — an artillery piece reaching full crew (HTML
##       commander_guns accept; the port auto-crews via ensure_crew).
##   (2) FIELD BASE ESTABLISHED — the first barracks stamped (HTML
##       c44MaybeAnnounceBase, once per race).
## Both now publish through court.publish_story so they land in the
## Chronicle archive AND the bus (2026-10-06 news-desk rule), never via a
## direct bus emit. Text is HTML-verbatim (glyph-sanitized).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gazette_coverage.gd
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


func _initialize() -> void:
	print("=== Cursing Gnomes Gazette coverage tests ===")
	_test_guns_crewed()
	_test_guns_crewed_once_per_piece()
	_test_guns_crewed_wave_count()
	_test_guns_crewed_old_save_silent()
	_test_field_base_established()
	_test_field_base_once_per_faction()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _make_gs() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	var court := SimRoyalCourt.new(gs)
	gs.court_sys = court
	return gs


func _headlines(gs: GameState, headline: String) -> Array:
	var out: Array = []
	for s: Dictionary in (gs.court_sys as SimRoyalCourt).stories:
		if String(s.get("headline", "")) == headline:
			out.append(s)
	return out


func _add_crew_unit(gs: GameState, uid: int) -> Dictionary:
	return gs.add_unit({"id": uid, "faction": "gnomes", "job": "worker",
		"position": Vector2(300, 300), "alive": true,
		"hp": 100.0, "max_hp": 100.0})


## --- GUNS CREWED ------------------------------------------------------------


func _test_guns_crewed() -> void:
	var gs := _make_gs()
	var art := SimArtillery.new(gs)
	var v: Dictionary = art._create_vehicle("gnomes", "field_cannon", 1,
		Vector2(300, 300))
	var u1 := _add_crew_unit(gs, 101)
	var u2 := _add_crew_unit(gs, 102)
	v["crew"] = [int(u1.get("id", 101)), int(u2.get("id", 102))]
	art.ensure_crew(v)
	art.tick(1.0)
	var stories := _headlines(gs, "GUNS CREWED")
	_check("guns: story published when a piece reaches full crew",
		stories.size() == 1)
	_check("guns: HTML-verbatim body",
		stories.size() == 1 and String(stories[0].get("body", ""))
		== "1 artillery pieces now have crews. The depot rumbles with purpose.")
	_check("guns: lands in the Chronicle archive (court stories)",
		stories.size() == 1)
	gs.queue_free()


func _test_guns_crewed_once_per_piece() -> void:
	var gs := _make_gs()
	var art := SimArtillery.new(gs)
	var v: Dictionary = art._create_vehicle("gnomes", "field_cannon", 1,
		Vector2(300, 300))
	_add_crew_unit(gs, 101)
	_add_crew_unit(gs, 102)
	v["crew"] = [101, 102]
	art.ensure_crew(v)
	art.tick(1.0)
	art.tick(1.0)
	art.tick(1.0)
	_check("guns: one story per piece, not per tick",
		_headlines(gs, "GUNS CREWED").size() == 1)
	gs.queue_free()


func _test_guns_crewed_wave_count() -> void:
	var gs := _make_gs()
	var art := SimArtillery.new(gs)
	_add_crew_unit(gs, 101)
	_add_crew_unit(gs, 102)
	_add_crew_unit(gs, 103)
	_add_crew_unit(gs, 104)
	var v1: Dictionary = art._create_vehicle("gnomes", "field_cannon", 1,
		Vector2(300, 300))
	var v2: Dictionary = art._create_vehicle("gnomes", "grape_cannon", 1,
		Vector2(400, 300))
	v1["crew"] = [101, 102]
	v2["crew"] = [103, 104]
	art.ensure_crew(v1)
	art.ensure_crew(v2)
	art.tick(1.0)
	var stories := _headlines(gs, "GUNS CREWED")
	_check("guns: one wave story for two newly-crewed pieces",
		stories.size() == 1)
	_check("guns: wave story carries the real count",
		stories.size() == 1 and String(stories[0].get("body", ""))
		== "2 artillery pieces now have crews. The depot rumbles with purpose.")
	gs.queue_free()


func _test_guns_crewed_old_save_silent() -> void:
	# Old saves predate the story: already-crewed pieces must not announce
	# on the first tick after load.
	var gs := _make_gs()
	var art := SimArtillery.new(gs)
	_add_crew_unit(gs, 101)
	_add_crew_unit(gs, 102)
	var saved := {
		"vehicles": [{
			"id": 1, "type": "field_cannon", "faction": "gnomes",
			"town_id": 1, "position": Vector2(300, 300),
			"alive": true, "parked": true, "hp": 220.0, "max_hp": 220.0,
			"size": 1.0, "crew": [101, 102], "driver_id": 101,
			"cool": 0.0, "salvo": {}, "target": {},
			"scan_t": 0.0, "aim_angle": 0.0, "rolling": false,
		}],
		"train_queue": [],
		"next_vehicle_id": 2,
	}
	art.from_dict(saved)
	art.tick(1.0)
	_check("guns: old-save fully-crewed pieces stay silent",
		_headlines(gs, "GUNS CREWED").is_empty())
	gs.queue_free()


## --- FIELD BASE ESTABLISHED --------------------------------------------------


## Live-like AI world (mirrors test_ai_military_buildings._make_world).
func _make_ai_world() -> Array:
	var gs := _make_gs()
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var director := SimAIDirector.new(gs)
	var t: Dictionary = gs.found_town("gnomes", "Teston", Vector2(1000, 1000))
	var tid := int(t.get("id", 1))
	gs.add_building({"type": "town_hall", "faction": "gnomes",
		"town_id": tid, "position": Vector2(1000, 1000), "alive": true,
		"complete": true, "progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	gs.resources.add_resource("gnomes", "wood", 1000.0, true)
	gs.resources.add_resource("gnomes", "oil", 600.0, true)
	gs.resources.add_resource("gnomes", "gold", 250.0, true)
	gs.resources.add_resource("gnomes", "food", 120.0, true)
	for i in 6:
		gs.spawner.spawn_unit("gnomes", "worker", tid,
			Vector2(1040 + i * 20, 1040))
	return [gs, director]


func _test_field_base_established() -> void:
	var parts := _make_ai_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for t in 20:
		director._think("gnomes")
	var stories := _headlines(gs, "FIELD BASE ESTABLISHED")
	_check("fieldbase: story published when the first barracks is stamped",
		stories.size() >= 1)
	_check("fieldbase: HTML-verbatim body",
		stories.size() >= 1 and String(stories[0].get("body", ""))
		== "Gnomes engineers have raised a field base beyond the city walls — barracks, camps and gun lines far from civilian streets. The army lives there now.")
	gs.queue_free()


func _test_field_base_once_per_faction() -> void:
	var parts := _make_ai_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for t in 20:
		director._think("gnomes")
	var first := _headlines(gs, "FIELD BASE ESTABLISHED").size()
	for t in 40:
		director._think("gnomes")
	_check("fieldbase: announced once per faction, not per think",
		_headlines(gs, "FIELD BASE ESTABLISHED").size() == first \
		and first >= 1)
	# Save/load keeps the one-shot flag (no re-announce after load).
	var d2 := SimAIDirector.new(gs)
	d2.from_dict(director.to_dict())
	_check("fieldbase: flag survives save/load",
		bool((d2.to_dict().get("field_base_announced", {}) as Dictionary).get("gnomes", false)))
	gs.queue_free()
