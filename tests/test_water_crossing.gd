extends SceneTree
## Cursing Gnomes — AI water-crossing (waterxAITick) headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_water_crossing.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: waterxSpan (longest water run, 40px samples, dry-line miss),
## the bridge path (halls at war + span in [160, 900] -> >2 blueprints +
## project + announcement), player-faction skip, no-war skip, span < 160
## skip, span > 900 ferry-queued skip, failed-project 180s cooldown,
## stale-project clear, bridge_done clearing the project.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes water-crossing tests ===")
	_test_span_across_stripe()
	_test_span_dry_line()
	_test_bridge_project()
	_test_player_skipped()
	_test_no_war_no_bridge()
	_test_span_too_short()
	_test_span_detected_but_short()
	_test_span_too_long_ferry_queued()
	_test_failed_cooldown()
	_test_bridge_done_clears()
	_test_tick_round_robin()
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


## Synthetic world: 128x128 grass tiles with a vertical TILE_WATER stripe
## at tile columns [x0, x1). tile_size 32 -> world 4096x4096.
func _make_world(x0: int, x1: int) -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	var faction_ids: Array[String] = ["humans", "gnomes"]
	gs.setup(faction_ids)  # player = humans
	var terrain := PackedByteArray()
	terrain.resize(128 * 128)
	for i in terrain.size():
		terrain[i] = MapGen.TILE_GRASS
	for ty in 128:
		for tx in range(x0, x1):
			terrain[ty * 128 + tx] = MapGen.TILE_WATER
	gs.map_data = {
		"terrain": terrain, "tile_size": 32.0,
		"world_size": Vector2(4096, 4096),
	}
	var bs := SimBuildings.new(gs)
	var wx := SimWaterCrossing.new(gs, bs)
	# Halls on opposite sides of the stripe (west = humans, east = gnomes).
	var th: Dictionary = gs.found_town("humans", "Westhold", Vector2(960, 2048))
	var tg: Dictionary = gs.found_town("gnomes", "Eastburg", Vector2(3136, 2048))
	gs.add_building({"type": "hall", "faction": "humans",
		"town_id": int(th["id"]), "alive": true, "complete": true,
		"position": Vector2(960, 2048)})
	gs.add_building({"type": "hall", "faction": "gnomes",
		"town_id": int(tg["id"]), "alive": true, "complete": true,
		"position": Vector2(3136, 2048)})
	_stories.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	return [gs, bs, wx]


func _grant(gs: GameState, f: String) -> void:
	gs.resources.add_resource(f, "wood", 100000.0, true)
	gs.resources.add_resource(f, "gold", 100000.0, true)


func _bridge_count(gs: GameState, f: String) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "bridge" \
				and String(b.get("faction", "")) == f \
				and bool(b.get("alive", false)):
			n += 1
	return n


## Span across an 8-tile (256px) stripe reads in [160, 900].
func _test_span_across_stripe() -> void:
	var parts: Array = _make_world(60, 68)
	var wx: SimWaterCrossing = parts[2]
	var span: Dictionary = wx.water_span(Vector2(960, 2048), Vector2(3136, 2048))
	_check("span found", not span.is_empty())
	_check("span len in bridge band",
		float(span.get("len", 0.0)) >= 160.0 \
		and float(span.get("len", 0.0)) <= 900.0)
	_check("span endpoints order", float(span["x1"]) < float(span["x2"]))
	parts[0].queue_free()


## A line that never touches water returns {}.
func _test_span_dry_line() -> void:
	var parts: Array = _make_world(60, 68)
	var wx: SimWaterCrossing = parts[2]
	var span: Dictionary = wx.water_span(Vector2(960, 100), Vector2(960, 3900))
	_check("dry line: no span", span.is_empty())
	parts[0].queue_free()


## Gnomes (AI) at war with humans, span 256px -> bridges, project, announcement.
func _test_bridge_project() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	_grant(gs, "gnomes")
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	_check("bridge blueprints placed (>2)", _bridge_count(gs, "gnomes") > 2)
	var proj: Dictionary = wx.project_of("gnomes")
	_check("project active", not proj.is_empty() \
		and not bool(proj.get("failed", false)))
	var announced := false
	for s: Dictionary in _stories:
		if String(s.get("body", "")).contains("bridging the strait"):
			announced = true
	_check("engineers announcement", announced)
	gs.queue_free()


## The player's faction never bridges (HTML skips playerRace).
func _test_player_skipped() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	_grant(gs, "humans")
	gs.diplomacy.declare_war("humans", "gnomes", "test")
	wx.tick_faction("humans")
	_check("player builds no bridges", _bridge_count(gs, "humans") == 0)
	_check("player gets no project", wx.project_of("humans").is_empty())
	gs.queue_free()


## No war -> no crossing work.
func _test_no_war_no_bridge() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	_grant(gs, "gnomes")
	wx.tick_faction("gnomes")  # at peace: relation_state != "war"
	_check("peace: no bridges", _bridge_count(gs, "gnomes") == 0)
	_check("peace: no project", wx.project_of("gnomes").is_empty())
	gs.queue_free()


## Span < 160px: no real crossing — walk or swim it. A 2-tile (64px) stripe
## falls below HTML waterxSpan's own detection floor (a lone wet 40px
## sample never beats be-bs = 0), so the span reads empty — also a skip.
func _test_span_too_short() -> void:
	var parts: Array = _make_world(62, 64)  # 2 tiles = 64px
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	var span: Dictionary = wx.water_span(Vector2(960, 2048), Vector2(3136, 2048))
	_check("thin stripe: no crossing span", span.is_empty())
	_grant(gs, "gnomes")
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	_check("short span: no bridges", _bridge_count(gs, "gnomes") == 0)
	gs.queue_free()


## A 4-tile (128px) stripe IS detected, but its run reads < 160px -> skip.
func _test_span_detected_but_short() -> void:
	var parts: Array = _make_world(62, 66)  # 4 tiles = 128px
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	var span: Dictionary = wx.water_span(Vector2(960, 2048), Vector2(3136, 2048))
	_check("128px stripe: span found", not span.is_empty())
	_check("128px stripe: span < 160", float(span.get("len", 999.0)) < 160.0)
	_grant(gs, "gnomes")
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	_check("short detected span: no bridges", _bridge_count(gs, "gnomes") == 0)
	_check("short detected span: no project", wx.project_of("gnomes").is_empty())
	gs.queue_free()


## Span > 900px: ferry the assault — queued, not built.
func _test_span_too_long_ferry_queued() -> void:
	var parts: Array = _make_world(50, 80)  # 30 tiles = 960px
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	var span: Dictionary = wx.water_span(Vector2(960, 2048), Vector2(3136, 2048))
	_check("wide stripe span > 900", float(span.get("len", 0.0)) > 900.0)
	_grant(gs, "gnomes")
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	_check("ferry span: no bridges", _bridge_count(gs, "gnomes") == 0)
	_check("ferry span: no project", wx.project_of("gnomes").is_empty())
	gs.queue_free()


## Broke faction: project fails -> 180s cooldown -> retries after.
func _test_failed_cooldown() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	# No resources granted: placement fails -> failed project.
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	var proj: Dictionary = wx.project_of("gnomes")
	_check("broke: project failed", bool(proj.get("failed", false)))
	_check("broke: nothing placed", _bridge_count(gs, "gnomes") == 0)
	# Jeremy 2026-10-04: game now starts at midday (game_time=240), so use
	# times relative to start instead of hardcoded 100/200.
	var t0: float = gs.game_time
	gs.game_time = t0 + 100.0  # inside the 180s cooldown
	wx.tick_faction("gnomes")
	_check("cooldown: still failed, no retry",
		bool(wx.project_of("gnomes").get("failed", false)) \
		and _bridge_count(gs, "gnomes") == 0)
	gs.game_time = t0 + 200.0  # past the cooldown
	_grant(gs, "gnomes")
	wx.tick_faction("gnomes")
	_check("after cooldown: bridges placed", _bridge_count(gs, "gnomes") > 2)
	_check("after cooldown: project active",
		not bool(wx.project_of("gnomes").get("failed", false)))
	gs.queue_free()


## A completed bridge near the run midpoint clears the project.
func _test_bridge_done_clears() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	_grant(gs, "gnomes")
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	_check("project active before done", not wx.project_of("gnomes").is_empty())
	# Finish one bridge segment at the project midpoint.
	var proj: Dictionary = wx.project_of("gnomes")
	var mid := Vector2(
		(float(proj["x1"]) + float(proj["x2"])) * 0.5,
		(float(proj["y1"]) + float(proj["y2"])) * 0.5)
	var done := false
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "bridge" \
				and String(b.get("faction", "")) == "gnomes":
			b["position"] = mid
			b["complete"] = true
			done = true
			break
	_check("test placed a completed bridge", done)
	_check("bridge_done true", wx.bridge_done("gnomes"))
	var old_started: float = float(proj.get("started", -1.0))
	# Jeremy 2026-10-04: game starts at midday (game_time=240); use a time
	# after the old project started, not hardcoded 50.
	var t_new: float = old_started + 50.0
	gs.game_time = t_new
	wx.tick_faction("gnomes")
	# The finished project clears (HTML deletes _waterxProj on done) and the
	# still-valid crossing starts a fresh project at the new clock.
	_check("project restarted after done",
		float(wx.project_of("gnomes").get("started", -1.0)) == t_new \
		and t_new > old_started)
	gs.queue_free()


## tick() round-robins one AI faction per second; the accumulator gates it.
func _test_tick_round_robin() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var wx: SimWaterCrossing = parts[2]
	_grant(gs, "gnomes")
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick(0.5)
	_check("half-second tick: nothing yet", _bridge_count(gs, "gnomes") == 0)
	wx.tick(0.5)  # accumulator hits 1.0 -> gnomes (only AI faction) ticks
	_check("one-second tick: gnomes bridged", _bridge_count(gs, "gnomes") > 2)
	gs.queue_free()
