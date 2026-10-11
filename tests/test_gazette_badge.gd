extends SceneTree
## Cursing Gnomes — drawer Chronicle unread-news badge tests (HTML parity).
##
## fix79's realm drawer has a Gazette button with a live unread-news badge
## (updateGazetteBadge on #dr-gazette): unreadNews increments per new story
## unless the gazette news tab is open, shows "(N)" capped at "9+", hidden
## at zero. The Godot drawer had a plain "Chronicle" button with no unread
## indication. The badge is an ASCII-only text suffix — emoji/special glyphs
## render as tofu boxes on iPhone Safari (Jeremy 2026-10-03).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gazette_badge.gd
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


## True when the string contains any non-ASCII glyph/emoji (anything above
## the box-drawing block — plain text labels never reach this high).
static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


func _initialize() -> void:
	print("=== Cursing Gnomes drawer Chronicle badge tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_format()
	_test_court_unread()
	_test_save_load()
	_test_hud_refresh()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("FAILED: ", f)
		quit(1)
	else:
		quit(0)


## HTML formula, verbatim: hidden at zero, capped at "9+".
func _test_format() -> void:
	_check("0 -> Chronicle", Hud.format_gazette_badge(0) == "Chronicle")
	_check("negative -> Chronicle", Hud.format_gazette_badge(-3) == "Chronicle")
	_check("1 -> Chronicle (1)", Hud.format_gazette_badge(1) == "Chronicle (1)")
	_check("9 -> Chronicle (9)", Hud.format_gazette_badge(9) == "Chronicle (9)")
	_check("10 -> Chronicle (9+)", Hud.format_gazette_badge(10) == "Chronicle (9+)")
	_check("99 -> Chronicle (9+)", Hud.format_gazette_badge(99) == "Chronicle (9+)")
	_check("badge glyph-free", not _has_glyph(Hud.format_gazette_badge(42)))


func _make_court() -> SimRoyalCourt:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"
	return SimRoyalCourt.new(gs)


## New stories raise unread_news; mark_news_read clears it.
func _test_court_unread() -> void:
	var court: SimRoyalCourt = _make_court()
	_check("fresh court -> 0 unread", court.unread_news() == 0)
	for i in range(3):
		court.publish_story("Headline %d" % i, "Body %d" % i)
	_check("3 stories -> 3 unread", court.unread_news() == 3)
	court.mark_news_read()
	_check("mark read -> 0 unread", court.unread_news() == 0)
	for i in range(12):
		court.publish_story("More %d" % i, "Body %d" % i)
	_check("12 more -> 12 unread", court.unread_news() == 12)


## news_seen persists across save/load; old saves (no key) count existing
## stories as read so the badge doesn't open with a bogus "9+".
func _test_save_load() -> void:
	var court: SimRoyalCourt = _make_court()
	for i in range(4):
		court.publish_story("H%d" % i, "B%d" % i)
	court.mark_news_read()
	court.publish_story("Latest", "Body")
	var data: Dictionary = court.to_dict()
	_check("to_dict keeps news_seen", int(data.get("news_seen", -1)) == 4)
	var court2: SimRoyalCourt = _make_court()
	court2.from_dict(data)
	_check("from_dict restores unread", court2.unread_news() == 1)
	var legacy: Dictionary = data.duplicate()
	legacy.erase("news_seen")
	var court3: SimRoyalCourt = _make_court()
	court3.from_dict(legacy)
	_check("old save -> existing read", court3.unread_news() == 0)


## Full refresh path: publishing a story flips the drawer button text;
## opening the gazette app clears it. Each _refresh() passes 0.25 s so the
## 5 Hz drawer gate opens (a bare _refresh() simulates zero elapsed time
## and skips the drawer rebuild, like a single idle frame).
func _test_hud_refresh() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)

	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	hud.set_phone_systems(phone, court)
	hud._drawer.visible = true

	_check("gazette button captured", hud._gazette_drawer_button != null)
	hud._refresh(0.25)
	_check("no unread -> plain Chronicle",
		String(hud._gazette_drawer_button.text) == "Chronicle")

	court.publish_story("Big News", "Something happened.")
	hud._refresh(0.25)
	_check("1 unread -> Chronicle (1)",
		String(hud._gazette_drawer_button.text) == "Chronicle (1)")

	for i in range(9):
		court.publish_story("News %d" % i, "Body")
	hud._refresh(0.25)
	_check("10 unread -> Chronicle (9+)",
		String(hud._gazette_drawer_button.text) == "Chronicle (9+)")
	_check("badge text glyph-free",
		not _has_glyph(String(hud._gazette_drawer_button.text)))

	hud._open_phone_app("gazette")
	hud._refresh(0.25)
	_check("open gazette -> plain Chronicle",
		String(hud._gazette_drawer_button.text) == "Chronicle")
