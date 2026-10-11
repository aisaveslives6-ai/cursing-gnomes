extends SceneTree
## Cursing Gnomes — drawer Messages unread badge tests (HTML parity).
##
## fix79's realm drawer has a Messages button with a live unread badge
## (#dr-gazette-msgbadge): total unseen per-thread count, capped at "9+",
## hidden at zero. The Godot drawer had a plain "Messages" button with no
## unread indication outside the phone. The badge is an ASCII-only text
## suffix — emoji/special glyphs render as tofu boxes on iPhone Safari
## (Jeremy 2026-10-03).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hud_msg_badge.gd
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
	print("=== Cursing Gnomes drawer Messages badge tests ===")
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await process_frame
	_test_format()
	_test_refresh()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("FAILED: ", f)
		quit(1)
	else:
		quit(0)


## HTML formula, verbatim: hidden at zero, capped at "9+".
func _test_format() -> void:
	_check("0 -> Messages", Hud.format_msg_badge(0) == "Messages")
	_check("negative -> Messages", Hud.format_msg_badge(-3) == "Messages")
	_check("1 -> Messages (1)", Hud.format_msg_badge(1) == "Messages (1)")
	_check("9 -> Messages (9)", Hud.format_msg_badge(9) == "Messages (9)")
	_check("10 -> Messages (9+)", Hud.format_msg_badge(10) == "Messages (9+)")
	_check("99 -> Messages (9+)", Hud.format_msg_badge(99) == "Messages (9+)")
	_check("badge glyph-free", not _has_glyph(Hud.format_msg_badge(42)))


## Full refresh path: NPC messages flip the drawer button text, reading the
## thread clears it. Each _refresh() passes 0.25 s so the 5 Hz drawer gate
## opens (a bare _refresh() simulates zero elapsed time and skips the
## drawer rebuild, like a single idle frame).
func _test_refresh() -> void:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["gnomes"])
	gs.player_faction = "gnomes"
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	var u: Dictionary = gs.spawner.spawn_unit("gnomes", "worker", -1, Vector2(100, 100))
	var uid: int = int(u["id"])

	var hud := Hud.new()
	root.add_child(hud)
	hud.setup(gs, Selection.new())
	hud.set_phone_systems(phone, court)
	hud._drawer.visible = true

	_check("messages button captured", hud._msg_drawer_button != null)
	hud._refresh(0.25)
	_check("no unread -> plain Messages",
		String(hud._msg_drawer_button.text) == "Messages")

	for i in range(3):
		phone.npc_message(uid, "test message %d" % i)
	hud._refresh(0.25)
	_check("3 unread -> Messages (3)",
		String(hud._msg_drawer_button.text) == "Messages (3)")

	for i in range(7):
		phone.npc_message(uid, "more %d" % i)
	hud._refresh(0.25)
	_check("10 unread -> Messages (9+)",
		String(hud._msg_drawer_button.text) == "Messages (9+)")
	_check("badge text glyph-free",
		not _has_glyph(String(hud._msg_drawer_button.text)))

	phone.read_thread(uid)
	hud._refresh(0.25)
	_check("read thread -> plain Messages",
		String(hud._msg_drawer_button.text) == "Messages")
