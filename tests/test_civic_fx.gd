extends SceneTree
## Cursing Gnomes — civic seat FX (graphics-hourly 2026-10-09,
## Jeremy's standing "everything smoothly animated" rule).
##
## The seats of power were the last major building family with no ambient
## FX: every town_hall, hall, courthouse, guild hall and necropolis stood
## perfectly still (the town_hall's waving faction banner was its only
## motion). Complete civic seats now breathe lamplight on the shared
## quantized FX cadence (8 steps at 6/sec) — warm window-glow + entrance
## braziers for the living races, sickly-green window-glow + purple
## brazier flames for the undead — with two deterministic rising motes
## (embers / wisps). Window anchors are pixel-scanned centroids from the
## real sprite art (bld_townhall, bld_hall, bld_civic, the five guild-hall
## variants, bld_necropolis); the lamplight flicker is a pure function
## (civic_flicker_for) so the math is pinned without rendering; _process
## gates keep blueprints dark and non-seats (gov_* offices, clinic,
## tome_library, bathhouse — they share the bld_civic art but are not
## seats of power) untouched.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_civic_fx.gd
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


func _make_node(btype: String, faction := "humans",
		complete := true) -> BuildingNode:
	var n := BuildingNode.new()
	n.setup(7, btype, faction, Vector2(100, 100))
	n.record = {"complete": complete}
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes civic seat FX tests ===")
	_test_roster()
	_test_art_keys()
	_test_anchors()
	_test_flicker()
	_test_process_gates()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


## The gated roster: the five seats of power (+ the townhall alias) — and
## nothing else. The gov_* offices, clinic, tome_library and bathhouse
## share the bld_civic art but are NOT seats, so they stay dark.
func _test_roster() -> void:
	for b in ["town_hall", "townhall", "hall", "courthouse", "guild_hall",
			"necropolis"]:
		_check("roster contains %s" % b,
			b in BuildingNode.CIVIC_FX_BTYPES)
	_check("roster has exactly 6 types",
		BuildingNode.CIVIC_FX_BTYPES.size() == 6)
	for b in ["house", "well", "shop", "gov_office", "gov_treasury",
			"gov_war_office", "gov_justice", "clinic", "tome_library",
			"bathhouse", "monastery", "farm", "barracks", "mage_spire",
			"inn", "windmill"]:
		_check("roster excludes %s" % b,
			not (b in BuildingNode.CIVIC_FX_BTYPES))


## Art-key routing: halls/courthouse take their own sprites; guild halls
## take the per-faction art; non-seats get no key at all.
func _test_art_keys() -> void:
	_check("town_hall -> townhall",
		BuildingNode.civic_fx_art_key("town_hall", "humans") == "townhall")
	_check("townhall alias -> townhall",
		BuildingNode.civic_fx_art_key("townhall", "ogres") == "townhall")
	_check("hall -> hall",
		BuildingNode.civic_fx_art_key("hall", "elves") == "hall")
	_check("courthouse -> civic",
		BuildingNode.civic_fx_art_key("courthouse", "gnomes") == "civic")
	_check("necropolis -> necropolis",
		BuildingNode.civic_fx_art_key("necropolis", "undead") == "necropolis")
	_check("human guild hall",
		BuildingNode.civic_fx_art_key("guild_hall", "humans")
		== "guild_human")
	_check("ogre guild hall",
		BuildingNode.civic_fx_art_key("guild_hall", "ogres") == "guild_ogre")
	_check("elf guild hall",
		BuildingNode.civic_fx_art_key("guild_hall", "elves") == "guild_elf")
	_check("gnome guild hall",
		BuildingNode.civic_fx_art_key("guild_hall", "gnomes")
		== "guild_gnome")
	_check("undead guild hall",
		BuildingNode.civic_fx_art_key("guild_hall", "undead")
		== "guild_undead")
	for b in ["gov_office", "gov_treasury", "gov_war_office", "gov_justice",
			"clinic", "tome_library", "bathhouse", "house", "shop"]:
		_check("%s gets no key" % b,
			BuildingNode.civic_fx_art_key(b, "humans") == "")
	_check("necropolis is undead-keyed",
		BuildingNode.civic_fx_is_undead("necropolis"))
	_check("guild_undead is undead-keyed",
		BuildingNode.civic_fx_is_undead("guild_undead"))
	for k in ["townhall", "hall", "civic", "guild_human", "guild_ogre",
			"guild_elf", "guild_gnome"]:
		_check("%s is living-keyed" % k,
			not BuildingNode.civic_fx_is_undead(k))
	# Test hook starts disarmed.
	var n := _make_node("town_hall")
	_check("fx hook starts disarmed", n._last_civic_fx == "")
	n.free()


## Anchors match the sprite art they were measured from: window centers
## in art px (pixel-scanned blob centroids, eyeball-verified). Anchor
## math is the _magespire_fx_anchor precedent (verified at sc = 1.0).
func _test_anchors() -> void:
	var tex: Dictionary = BuildingNode.CIVIC_FX_TEX
	var expected := {
		"townhall": Vector2(480, 360), "hall": Vector2(480, 358),
		"civic": Vector2(480, 346), "guild_human": Vector2(480, 640),
		"guild_ogre": Vector2(480, 320), "guild_elf": Vector2(480, 320),
		"guild_gnome": Vector2(480, 320),
		"guild_undead": Vector2(1182, 1896),
		"necropolis": Vector2(480, 358),
	}
	for key in expected:
		var t: Vector2 = tex[key]
		var e: Vector2 = expected[key]
		_check("%s tex is %dx%d" % [key, int(e.x), int(e.y)],
			absf(t.x - e.x) < 0.01 and absf(t.y - e.y) < 0.01)
	var wins: Dictionary = BuildingNode.CIVIC_FX_WINDOWS
	var counts := {"townhall": 6, "hall": 6, "civic": 7, "guild_human": 4,
		"guild_ogre": 2, "guild_elf": 3, "guild_gnome": 2,
		"guild_undead": 2, "necropolis": 4}
	for key in counts:
		_check("%s has %d windows" % [key, counts[key]],
			(wins[key] as Array).size() == counts[key])
	# Spot-check scanned centroids.
	_check("townhall window-0 (35,182)",
		wins["townhall"][0] == Vector2(35.0, 182.0))
	_check("hall window-0 (106,205)",
		wins["hall"][0] == Vector2(106.0, 205.0))
	_check("guild_human window-3 (348,400)",
		wins["guild_human"][3] == Vector2(348.0, 400.0))
	_check("guild_undead window-0 (175,836)",
		wins["guild_undead"][0] == Vector2(175.0, 836.0))
	_check("necropolis window-1 (279,115)",
		wins["necropolis"][1] == Vector2(279.0, 115.0))
	# Brazier counts: every seat flanks its door except the courthouse
	# (an office, not a hall).
	var braz: Dictionary = BuildingNode.CIVIC_FX_BRAZIERS
	for key in counts:
		var want := 0 if key == "civic" else 2
		_check("%s has %d braziers" % [key, want],
			(braz[key] as Array).size() == want)
	# Anchor math at unit scale: (ap.x - w/2, ap.y - h/2 - 0.48h).
	var n := _make_node("town_hall")
	n._sprite_sc = 1.0
	var t0: Vector2 = n._civic_art_to_node(Vector2(35, 182), "townhall")
	_check("townhall anchor x = -205.0", absf(t0.x - (-205.0)) < 0.01)
	_check("townhall anchor y = -170.8", absf(t0.y - (-170.8)) < 0.01)
	var u0: Vector2 = n._civic_art_to_node(Vector2(175, 836),
		"guild_undead")
	_check("guild_undead anchor x = -416.0", absf(u0.x - (-416.0)) < 0.01)
	_check("guild_undead anchor y = -1022.08",
		absf(u0.y - (-1022.08)) < 0.01)
	n.free()
	# Tints cover both families.
	_check("living tint present",
		BuildingNode.CIVIC_FX_TINT.has("living"))
	_check("undead tint present",
		BuildingNode.CIVIC_FX_TINT.has("undead"))


## The flicker is lamplight: bounded 0.60..1.0, varies with the step, and
## the phase shifts the wave (per-building offsets desync seats).
func _test_flicker() -> void:
	var lo := 2.0
	var hi := -1.0
	var seen := {}
	for s in range(BuildingNode.EATERY_FX_STEPS):
		for p in [0.0, 1.4, 2.8, 4.2]:
			var f := BuildingNode.civic_flicker_for(s, p)
			lo = minf(lo, f)
			hi = maxf(hi, f)
			seen[f] = true
	_check("flicker lower bound 0.60", lo >= 0.60 - 0.001)
	_check("flicker upper bound 1.0", hi <= 1.0 + 0.001)
	_check("flicker varies across steps", seen.size() > 4)
	_check("phase 0 vs 1.4 differ at step 0",
		absf(BuildingNode.civic_flicker_for(0, 0.0)
			- BuildingNode.civic_flicker_for(0, 1.4)) > 0.01)
	# Deeper trough than the shop flicker (council windows breathe more).
	_check("civic trough deeper than shop",
		BuildingNode.civic_flicker_for(6, 0.0)
		< BuildingNode.shop_flicker_for(6, 0.0))
	# Full-cycle determinism: same step+phase always gives the same value.
	_check("flicker deterministic",
		BuildingNode.civic_flicker_for(5, 2.8)
		== BuildingNode.civic_flicker_for(5, 2.8))


## _process animates only complete civic seats: blueprints stay dark,
## non-seats (even ones sharing the bld_civic art) never touch the gate.
func _test_process_gates() -> void:
	var th := _make_node("town_hall")
	th._process(0.1)
	_check("complete town_hall advances fx step",
		th._fx_step >= 0 and th._fx_step < BuildingNode.EATERY_FX_STEPS)
	th.free()
	var bp := _make_node("town_hall", "humans", false)
	bp._process(0.1)
	_check("blueprint town_hall stays static", bp._fx_step == -1)
	bp.free()
	var court := _make_node("courthouse")
	court._process(0.1)
	_check("complete courthouse advances fx step",
		court._fx_step >= 0
		and court._fx_step < BuildingNode.EATERY_FX_STEPS)
	court.free()
	var nec := _make_node("necropolis", "undead")
	nec._process(0.1)
	_check("complete necropolis advances fx step", nec._fx_step >= 0)
	nec.free()
	var gh := _make_node("guild_hall", "ogres")
	gh._process(0.1)
	_check("complete ogre guild hall advances fx step", gh._fx_step >= 0)
	gh.free()
	var gu := _make_node("guild_hall", "undead")
	gu._process(0.1)
	_check("complete undead guild hall advances fx step", gu._fx_step >= 0)
	gu.free()
	# Non-seats sharing the art stay out of the gate entirely.
	var gov := _make_node("gov_office")
	gov._process(0.1)
	_check("gov_office stays dark (no fx gate)", gov._fx_step == -1)
	gov.free()
	var clinic := _make_node("clinic")
	clinic._process(0.1)
	_check("clinic stays dark (no fx gate)", clinic._fx_step == -1)
	clinic.free()
	var house := _make_node("house")
	house._process(0.1)
	_check("house keeps its own fx step (civic gate untouched)",
		house._fx_step >= 0)
	house.free()
