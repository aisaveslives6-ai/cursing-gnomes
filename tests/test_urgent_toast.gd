extends SceneTree
## Cursing Gnomes — urgent toast banner tests (HTML #toast port).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_urgent_toast.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes urgent toast tests ===")
	_test_urgency_regex_hits()
	_test_urgency_non_urgent()
	_test_urgency_explicit_flag()
	_test_show_replace()
	_test_auto_hide()
	_test_fade_in()
	_test_bus_urgent_shows()
	_test_bus_non_urgent_ignored()
	_test_sanitize_ascii()
	_test_refit_offsets()
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


func _make_toast() -> UrgentToast:
	var t := UrgentToast.new()
	root.add_child(t)
	t.refit(200.0, 1000.0, 1.0)
	return t


func _test_urgency_regex_hits() -> void:
	# HTML TOAST_URGENT_RE verbatim categories, ASCII subset.
	var hits := [
		"The Ogres declare war on the Elves",
		"Gnomes at war with Humans",
		"WAR BEGINS: the border burns",
		"Your town is under attack!",
		"A raiding party is attacking the mill",
		"The raid has begun at dawn",
		"Siege engines approach the walls",
		"Invasion fleet sighted off the coast",
		"DISASTER: volcano erupts near Gnomeregan",
		"A giant ass rampages through the market",
		"The cussing lizard strikes again",
		"Count Bastard demands tribute",
		"Rogue wizard spotted in the woods",
		"Wild mage burns the granary",
		"Earthquake shakes the valley",
		"Tornado touches down",
		"Meteor impact in the farmlands",
		"Plague spreads through the barracks",
		"Drought withers the crops",
		"Flood waters rising near the mill",
		"The dam eruption floods the lowlands",
		"Nuke silo armed and ready",
		"Leader fallen in battle",
		"Commander Bob died bravely",
		"Commander Alice was slain at dawn",
		"Commander Eve has fallen with the rearguard",
		"Assassination attempt foiled",
		"The great hall destroyed by fire",
		"Open war declared by the council",
		"Shattered the peace at midnight",
		"Mass at the border: troops gathering",
	]
	for h in hits:
		_check("urgent hit: " + h, UrgentToast.is_urgent(h))


func _test_urgency_non_urgent() -> void:
	# Everyday news must NOT pop a toast (HTML downgrades to ticker only).
	var misses := [
		"Market day brings traders",
		"A wedding in Gnomeregan",
		"Festival of lights",
		"New windmill completed",
		"Harvest season begins",
		"A wandering handyman passes through",
		"New hall raised in Ogreton",
		"Trade caravan arrives",
		"",
	]
	for m in misses:
		_check("not urgent: '%s'" % m, not UrgentToast.is_urgent(m))


func _test_urgency_explicit_flag() -> void:
	_check("explicit urgent flag wins", UrgentToast.is_urgent("Market day brings traders", true))
	_check("explicit false defers to regex", not UrgentToast.is_urgent("Market day brings traders", false))
	_check("explicit false + regex hit still urgent",
		UrgentToast.is_urgent("The Ogres declare war on the Elves", false))


func _test_show_replace() -> void:
	var t := _make_toast()
	_check("starts hidden", not t.is_showing())
	t.show_toast("The Ogres declare war on the Elves")
	_check("shows after urgent text", t.is_showing())
	# New toast REPLACES the prior one (HTML clearTimeout parity).
	t.show_toast("Flood waters rising near the mill")
	_check("replace keeps single toast visible", t.is_showing())
	t.queue_free()


func _test_auto_hide() -> void:
	var t := _make_toast()
	t.show_toast("The Ogres declare war on the Elves")
	t._process(UrgentToast.SHOW_SECONDS + UrgentToast.FADE_SECONDS + 0.1)
	_check("auto-hides after 2.6s + fade", not t.is_showing())
	t.queue_free()


func _test_fade_in() -> void:
	var t := _make_toast()
	t.show_toast("The Ogres declare war on the Elves")
	t._process(0.1)
	var a: float = t.modulate.a
	_check("fades in (0 < alpha < 1 mid-fade)", a > 0.0 and a < 1.0)
	t._process(1.0)
	_check("fully opaque after fade", t.modulate.a >= 0.99)
	t.queue_free()


func _test_bus_urgent_shows() -> void:
	var t := _make_toast()
	var bus := EventBus.new()
	root.add_child(bus)
	t.setup(bus)
	bus.gazette_story.emit({"headline": "The Ogres declare war on the Elves", "urgent": false})
	_check("urgent gazette story pops toast", t.is_showing())
	t.queue_free()
	bus.queue_free()


func _test_bus_non_urgent_ignored() -> void:
	var t := _make_toast()
	var bus := EventBus.new()
	root.add_child(bus)
	t.setup(bus)
	bus.gazette_story.emit({"headline": "Market day brings traders", "urgent": false})
	_check("non-urgent story stays in Chronicle only", not t.is_showing())
	# Empty headlines never pop.
	t.show_toast("")
	_check("empty text never shows", not t.is_showing())
	t.queue_free()
	bus.queue_free()


func _test_sanitize_ascii() -> void:
	var clean := UrgentToast.sanitize("FLOOD! \u0001\u0002")
	_check("control chars stripped", clean == "FLOOD!")
	# iPhone tofu rule: no codepoint >= 128 survives.
	var emoji := UrgentToast.sanitize("WAR! \u2728 declared")
	var ok := true
	for i in emoji.length():
		if emoji.unicode_at(i) >= 128:
			ok = false
	_check("non-ascii sanitized", ok and emoji.begins_with("WAR!"))


func _test_refit_offsets() -> void:
	var t := _make_toast()
	t.refit(300.0, 1000.0, 1.0)
	_check("bottom offset honors clearance", t.offset_bottom <= -300.0)
	_check("width capped near 86% viewport", t.offset_right <= 430.0 + 1.0)
	t.refit(300.0, 2000.0, 1.0)
	_check("width capped at 480px max", t.offset_right <= 480.0 + 1.0)
	t.queue_free()
