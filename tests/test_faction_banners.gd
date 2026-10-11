extends SceneTree
## Cursing Gnomes — faction banner tests (graphics-hourly 2026-10-05).
##
## Seats of power ("town_hall"/"hall" + each faction's war unique) fly a
## waving pennant in the faction color so ownership reads from the air.
## _draw runs headlessly (dummy renderer; the _last_banner_color hook pins
## the dispatch contract), the wave step is a pure static, and the phase is
## deterministic per building id.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_faction_banners.gd
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


func _make_node(btype: String, complete := true, faction := "humans",
		bid := 7) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(bid, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	root.add_child(n)
	return n


## Adds the node, lets _draw run, returns the banner color hook.
func _drawn_banner(n: BuildingNode) -> Color:
	n.queue_redraw()
	await process_frame
	await process_frame
	var c: Color = n._last_banner_color
	n.free()
	return c


## Same as _drawn_banner but leaves the node alive for flip tests.
func _draw_banner_color(n: BuildingNode) -> Color:
	n.queue_redraw()
	await process_frame
	await process_frame
	return n._last_banner_color


func _test_step_math() -> void:
	_check("step: t=0 -> step 0", BuildingNode.banner_step_for(0.0) == 0)
	# 0.9 Hz * 8 steps = 7.2 steps/sec: t=0.2 -> int(1.44) = 1.
	_check("step: advances with time", BuildingNode.banner_step_for(0.2) == 1)
	_check("step: t=0.5 -> step 3", BuildingNode.banner_step_for(0.5) == 3)
	# Wrap: t = 8/7.2 -> int(8.0) % 8 = 0.
	_check("step: wraps at 8", BuildingNode.banner_step_for(8.0 / 7.2) == 0)
	# Monotonic over the first cycle.
	var prev := -1
	var mono := true
	var t := 0.0
	while t < 1.0:
		var s: int = BuildingNode.banner_step_for(t)
		if s < prev:
			mono = false
		prev = s
		t += 0.05
	_check("step: monotonic over first cycle", mono)
	_check("step: always in 0..7",
		BuildingNode.banner_step_for(123.456) >= 0 \
		and BuildingNode.banner_step_for(123.456) < BuildingNode.BANNER_WAVE_STEPS)


func _test_dispatch() -> void:
	# Every seat flies a banner when complete.
	var seats := ["town_hall", "hall", "knights_castle", "war_hut",
		"tome_library", "mage_spire", "necropolis"]
	for i in seats.size():
		var c: Color = await _drawn_banner(_make_node(seats[i], true, "gnomes", 100 + i))
		_check("seat draws banner: " + seats[i], c.a > 0.0)
	# Non-seats never do.
	for b in ["farm", "barracks", "house", "wall", "pier", "windmill"]:
		var c2: Color = await _drawn_banner(_make_node(b, true, "gnomes", 200))
		_check("non-seat draws no banner: " + b, c2.a == 0.0)
	# Blueprints never do.
	var c3: Color = await _drawn_banner(_make_node("town_hall", false, "gnomes", 300))
	_check("blueprint draws no banner", c3.a == 0.0)
	var c4: Color = await _drawn_banner(_make_node("necropolis", false, "undead", 301))
	_check("blueprint necropolis draws no banner", c4.a == 0.0)


func _test_faction_colors() -> void:
	var humans: Color = await _drawn_banner(_make_node("town_hall", true, "humans", 400))
	var want_h: Color = Config.FACTIONS["humans"]["color"]
	_check("banner uses human faction color", humans.is_equal_approx(want_h))
	var undead: Color = await _drawn_banner(_make_node("necropolis", true, "undead", 401))
	var want_u: Color = Config.FACTIONS["undead"]["color"]
	_check("banner uses undead faction color", undead.is_equal_approx(want_u))
	var elves: Color = await _drawn_banner(_make_node("tome_library", true, "elves", 402))
	var want_e: Color = Config.FACTIONS["elves"]["color"]
	_check("banner uses elf faction color", elves.is_equal_approx(want_e))


func _test_phase() -> void:
	var a := _make_node("town_hall", true, "humans", 11)
	var b := _make_node("town_hall", true, "humans", 12)
	_check("phase in [0, TAU)", a._banner_phase >= 0.0 and a._banner_phase < TAU)
	_check("phase differs per building id", a._banner_phase != b._banner_phase)
	var c := _make_node("town_hall", true, "humans", 11)
	_check("phase deterministic per id", c._banner_phase == a._banner_phase)
	a.free()
	b.free()
	c.free()


func _test_process_advances() -> void:
	var n := _make_node("town_hall", true, "humans", 500)
	_check("banner step starts at -1", n._banner_step == -1)
	n._process(0.0)
	_check("process advances banner step", n._banner_step >= 0)
	_check("banner step in 0..7",
		n._banner_step < BuildingNode.BANNER_WAVE_STEPS)
	var farm := _make_node("farm", true, "humans", 501)
	farm._process(0.0)
	_check("process ignores non-seats", farm._banner_step == -1)
	n.free()
	farm.free()


## Jeremy 2026-10-06 (Battlefront): captured halls flip faction instead of
## being destroyed — set_faction() must recolor the pennant to the new
## holder's faction color and swap faction-variant sprite art.
func _test_set_faction() -> void:
	var n := _make_node("town_hall", true, "humans", 600)
	var want_h: Color = Config.FACTIONS["humans"]["color"]
	_check("flip: starts with human banner",
		(await _draw_banner_color(n)).is_equal_approx(want_h))
	n.set_faction("undead")
	_check("flip: faction member updated", n.faction == "undead")
	var want_u: Color = Config.FACTIONS["undead"]["color"]
	_check("flip: pennant recolors to undead banner",
		(await _draw_banner_color(n)).is_equal_approx(want_u))
	# Idempotent: same faction is a no-op.
	n.set_faction("undead")
	_check("flip: same faction keeps faction", n.faction == "undead")
	n.free()


func _test_set_faction_swaps_variant_art() -> void:
	# guild_hall has per-faction sprite variants (BUILDING_ART_FACTION).
	var n := _make_node("guild_hall", true, "humans", 610)
	_check("variant: human sprite built", n._sprite != null)
	var before := ""
	if n._sprite != null and n._sprite.texture != null:
		before = String(n._sprite.texture.resource_path)
	_check("variant: human art file", before.ends_with("bld_guild_hall_human.png"))
	n.set_faction("undead")
	var after := ""
	if n._sprite != null and n._sprite.texture != null:
		after = String(n._sprite.texture.resource_path)
	_check("variant: undead art after flip", after.ends_with("bld_guild_undead.png"))
	var sprites := 0
	for ch in n.get_children():
		if ch is Sprite2D:
			sprites += 1
	_check("variant: exactly one sprite after flip", sprites == 1)
	n.free()


## The sim flips a captured hall's record faction in place
## (SimCombat._flip_hall); the node self-heals to the live record faction
## on _process so the pennant can't stay stale.
func _test_faction_drift_from_record() -> void:
	var n := _make_node("town_hall", true, "humans", 620)
	n.record = {"complete": true, "faction": "humans"}
	n._process(0.0)
	_check("drift: no flip when record matches", n.faction == "humans")
	n.record["faction"] = "elves"
	n._process(0.0)
	_check("drift: node follows record faction flip", n.faction == "elves")
	var want: Color = Config.FACTIONS["elves"]["color"]
	_check("drift: pennant follows record flip",
		(await _draw_banner_color(n)).is_equal_approx(want))
	n.free()


func _initialize() -> void:
	print("=== Cursing Gnomes faction banner tests ===")
	_test_step_math()
	await _test_dispatch()
	await _test_faction_colors()
	_test_phase()
	_test_process_advances()
	await _test_set_faction()
	_test_set_faction_swaps_variant_art()
	await _test_faction_drift_from_record()
	print("  passed %d/%d" % [_passed, _passed + _failed])
	if _failed > 0:
		print("  FAILURES: ", _failures)
		quit(1)
	else:
		quit(0)
