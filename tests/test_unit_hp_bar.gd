extends SceneTree
## Cursing Gnomes — world-space unit HP bar tests (2026-10-04).
##
## HTML C70fix2 MISS 11 port (fix79 index.html:37554-37572): the HP bar
## renders in-world over each unit and shows ONLY while injured
## (hp < maxHp - 0.5), never at full health — Jeremy's standing rule.
## Geometry: barW = s*2.2, barH = 5, drawn at y - s*2.5 (clears the big
## chibi head). Fill: pct > 0.5 green #66bb6a, > 0.25 orange #ffa726,
## else red #ef5350; fill width = max(2, barW*pct).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_unit_hp_bar.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(label)
		print("FAIL: ", label)


func _initialize() -> void:
	print("=== Cursing Gnomes unit-HP-bar tests ===")
	_test_visibility_rule()
	_test_geometry()
	_test_colors()
	_test_set_hp_node()
	_test_early_out()
	_test_bar_rect_chibi()
	_test_bar_rect_boat()
	_test_bar_rect_monster()
	_test_world_sync_wiring()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAILED: ", f)
	quit(1 if _failed > 0 else 0)


## HTML injured-only rule verbatim: (maxHp > 0) && (hp < maxHp - 0.5).
func _test_visibility_rule() -> void:
	_check(not UnitNode.hp_bar_visible(100.0, 100.0),
		"hpbar: hidden at full health")
	_check(not UnitNode.hp_bar_visible(99.6, 100.0),
		"hpbar: hidden within the 0.5 grace band")
	_check(UnitNode.hp_bar_visible(99.4, 100.0),
		"hpbar: shown just below the 0.5 grace band")
	_check(UnitNode.hp_bar_visible(50.0, 100.0),
		"hpbar: shown at half health")
	_check(UnitNode.hp_bar_visible(0.0, 100.0),
		"hpbar: shown (red sliver) at 0 hp — verbatim HTML")
	_check(not UnitNode.hp_bar_visible(50.0, 0.0),
		"hpbar: hidden when max_hp is 0")
	_check(not UnitNode.hp_bar_visible(50.0, -5.0),
		"hpbar: hidden when max_hp is negative")


## HTML geometry verbatim: barW = s*2.2, barH = 5, at y - s*2.5.
func _test_geometry() -> void:
	var r := UnitNode.hp_bar_geom(44.0)
	_check(is_equal_approx(r.size.x, 96.8),
		"hpbar: barW = s*2.2 (96.8 at s=44)")
	_check(is_equal_approx(r.size.y, 5.0),
		"hpbar: barH = 5")
	_check(is_equal_approx(r.position.x, -48.4),
		"hpbar: centered on the unit (bx = -barW/2)")
	_check(is_equal_approx(r.position.y, -110.0),
		"hpbar: y = -s*2.5 (clears the chibi head)")


## HTML fill thresholds verbatim.
func _test_colors() -> void:
	_check(UnitNode.hp_bar_color(0.8).to_html() == "66bb6aff",
		"hpbar: pct > 0.5 is green #66bb6a")
	_check(UnitNode.hp_bar_color(0.51).to_html() == "66bb6aff",
		"hpbar: pct 0.51 still green")
	_check(UnitNode.hp_bar_color(0.5).to_html() == "ffa726ff",
		"hpbar: pct 0.5 is orange #ffa726")
	_check(UnitNode.hp_bar_color(0.3).to_html() == "ffa726ff",
		"hpbar: pct 0.3 is orange")
	_check(UnitNode.hp_bar_color(0.25).to_html() == "ef5350ff",
		"hpbar: pct 0.25 is red #ef5350")
	_check(UnitNode.hp_bar_color(0.05).to_html() == "ef5350ff",
		"hpbar: pct near 0 is red")


## set_hp drives the node state; full health hides the bar.
func _test_set_hp_node() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(9101, "gnomes", "worker", Vector2(400, 300), "m")
	un.set_hp(100.0, 100.0)
	_check((un._hp_bar_key >> 8) == 0,
		"hpbar: full-health unit has the visibility bit clear")
	_check(is_equal_approx(un._hp, 100.0) and is_equal_approx(un._max_hp, 100.0),
		"hpbar: set_hp stores hp/max_hp")
	un.set_hp(30.0, 100.0)
	_check((un._hp_bar_key >> 8) == 1,
		"hpbar: injured unit sets the visibility bit")
	_check((un._hp_bar_key & 0xFF) == 30,
		"hpbar: fill bucket quantizes pct to 1% (30/100 -> 30)")
	un.queue_free()


## Repeat calls with identical values must not change the key (cheap
## early-out — the 60fps rule: 240 units x 30Hz sync must stay cheap).
func _test_early_out() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(9102, "gnomes", "worker", Vector2(400, 300), "m")
	un.set_hp(42.0, 100.0)
	var k1: int = un._hp_bar_key
	un.set_hp(42.0, 100.0)
	_check(un._hp_bar_key == k1,
		"hpbar: identical set_hp does not change the key")
	# Same bucket after tiny regen tick: no key change.
	un.set_hp(42.4, 100.0)
	_check(un._hp_bar_key == k1,
		"hpbar: sub-1% regen tick does not change the key")
	# Bucket rollover: key changes.
	un.set_hp(43.0, 100.0)
	_check(un._hp_bar_key != k1 and (un._hp_bar_key & 0xFF) == 43,
		"hpbar: 1% bucket rollover updates the key")
	un.queue_free()


## Chibi placement: HTML-verbatim rect, above the head.
func _test_bar_rect_chibi() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(9103, "gnomes", "worker", Vector2(400, 300), "m")
	var r := un._bar_rect()
	_check(is_equal_approx(r.position.y, -110.0),
		"hpbar: chibi bar at -2.5*44 (HTML verbatim)")
	_check(is_equal_approx(r.size.x, 96.8),
		"hpbar: chibi bar width 2.2*44")
	un.queue_free()


## Boat placement: above the mast, not through it.
## war_ship: boat_w = 44*3.4 = 149.6; boat_h = 149.6*187/256 ≈ 109.3;
## mast = 109.3*0.72 + 44*0.35 ≈ 94.1; bar y = -(94.1 + 12) ≈ -106.1.
func _test_bar_rect_boat() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(9104, "gnomes", "war_ship", Vector2(400, 300), "m")
	_check(un._boat != null, "hpbar: war_ship node has a boat branch")
	var r := un._bar_rect()
	_check(r.position.y < -100.0 and r.position.y > -115.0,
		"hpbar: war_ship bar sits above the mast (~-106)")
	_check(is_equal_approx(r.size.x, 96.8),
		"hpbar: boat bar keeps the chibi-scale width")
	un.queue_free()


## Monster placement: scaled with the world height.
## thicc_moose scale = 44*2.2 = 96.8; bar y = -(96.8 + 12) = -108.8.
func _test_bar_rect_monster() -> void:
	var un := UnitNode.new()
	root.add_child(un)
	un.setup(9105, "gnomes", "thicc_moose", Vector2(400, 300), "m")
	var r := un._bar_rect()
	_check(is_equal_approx(r.position.y, -108.8),
		"hpbar: moose bar 12px above the scaled head")
	_check(is_equal_approx(r.size.x, 212.96),
		"hpbar: moose bar width 2.2*scale")
	# Giant ass: procedural butt, bar scales with the joke.
	var ga := UnitNode.new()
	root.add_child(ga)
	ga.setup(9106, "gnomes", "giant_ass", Vector2(400, 300), "m")
	var gr := ga._bar_rect()
	_check(gr.position.y < -100.0,
		"hpbar: giant-ass bar clears the butt silhouette")
	_check(gr.size.x > 200.0,
		"hpbar: giant-ass bar scales with the monster")
	un.queue_free()
	ga.queue_free()


## The world sync feeds hp into every unit node each tick.
func _test_world_sync_wiring() -> void:
	var f := FileAccess.open("res://scripts/world/world.gd", FileAccess.READ)
	_check(f != null, "hpbar: world.gd readable for wiring scan")
	if f == null:
		return
	var src := f.get_as_text()
	f.close()
	_check(src.find("un.set_hp(") >= 0,
		"hpbar: world sync calls un.set_hp(")
	_check(src.find('u.get("hp"') >= 0 and src.find('u.get("max_hp"') >= 0,
		"hpbar: sync reads the sim hp/max_hp keys")
