extends SceneTree
## Cursing Gnomes — "Overheard" subtitle ticker tests (2026-10-07).
##
## Jeremy 2026-10-05 removed ALL speech bubbles; bus.unit_said went mute.
## The Overheard system gives the world's voice back as a single subtitle
## line of HUD chrome (never a bubble): ChatterDirector decides what
## reaches the ticker (camera proximity, throttle, small queue), and
## ChatterTicker displays it.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_world_chatter.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes world chatter tests ===")
	_test_near_speech_accepted()
	_test_far_speech_culled()
	_test_cull_boundary()
	_test_system_shout_skips_cull()
	_test_empty_text_rejected()
	_test_throttle_queues()
	_test_queue_overflow_drops_oldest()
	_test_clear()
	_test_ticker_shows_speaker_color()
	_test_ticker_sanitizes_emoji()
	_test_ticker_empty_text_ignored()
	_test_ticker_anonymous_speaker()
	_test_ticker_never_blocks_taps()
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


func _director() -> ChatterDirector:
	return ChatterDirector.new()


func _test_near_speech_accepted() -> void:
	var d := _director()
	var ok := d.offer(true, Vector2(100, 100), Vector2.ZERO, "Bob",
		Color.RED, "hello there")
	_check("near speech accepted", ok)
	_check("near speech pending", d.pending() == 1)


func _test_far_speech_culled() -> void:
	var d := _director()
	var ok := d.offer(true, Vector2(5000, 0), Vector2.ZERO, "Bob",
		Color.RED, "you cannot hear me")
	_check("far speech culled", not ok)
	_check("culled speech not pending", d.pending() == 0)


func _test_cull_boundary() -> void:
	var d := _director()
	# Just inside the radius passes; just outside fails.
	var inside := d.offer(true, Vector2(ChatterDirector.RADIUS - 1.0, 0),
		Vector2.ZERO, "A", Color.RED, "in")
	d.clear()
	var outside := d.offer(true, Vector2(ChatterDirector.RADIUS + 1.0, 0),
		Vector2.ZERO, "B", Color.RED, "out")
	_check("inside radius accepted", inside)
	_check("outside radius culled", not outside)


func _test_system_shout_skips_cull() -> void:
	var d := _director()
	# Army/system shouts (unit_id -1) carry no position: always heard.
	var ok := d.offer(false, Vector2.ZERO, Vector2(99999, 99999), "Army",
		ChatterTicker.SYSTEM_COLOR, "No living commander.")
	_check("system shout skips proximity cull", ok)


func _test_empty_text_rejected() -> void:
	var d := _director()
	_check("empty text rejected", not d.offer(true, Vector2.ZERO, Vector2.ZERO, "A", Color.RED, ""))
	_check("whitespace text rejected", not d.offer(true, Vector2.ZERO, Vector2.ZERO, "A", Color.RED, "   "))
	_check("nothing pending after rejects", d.pending() == 0)


func _test_throttle_queues() -> void:
	var d := _director()
	_check("first line accepted", d.offer(true, Vector2.ZERO, Vector2.ZERO, "A", Color.RED, "one"))
	_check("second line accepted (queued)", d.offer(true, Vector2.ZERO, Vector2.ZERO, "B", Color.BLUE, "two"))
	# Immediate tick: still cooling down from the first line.
	var early: Dictionary = d.tick(0.1)
	_check("throttle holds second line", early.is_empty())
	# After the cooldown the first line shows, then the second.
	var first: Dictionary = d.tick(ChatterDirector.COOLDOWN)
	_check("first line delivered after cooldown", String(first.get("text", "")) == "one")
	var second: Dictionary = d.tick(ChatterDirector.COOLDOWN)
	_check("queued line delivered next", String(second.get("text", "")) == "two")
	_check("queue drained", d.pending() == 0)
	_check("idle tick returns empty", d.tick(99.0).is_empty())


func _test_queue_overflow_drops_oldest() -> void:
	var d := _director()
	d.offer(true, Vector2.ZERO, Vector2.ZERO, "A", Color.RED, "one")
	_check("first line drains", String(d.tick(ChatterDirector.COOLDOWN).get("text", "")) == "one")
	d.offer(true, Vector2.ZERO, Vector2.ZERO, "B", Color.RED, "two")
	d.offer(true, Vector2.ZERO, Vector2.ZERO, "C", Color.RED, "three")
	d.offer(true, Vector2.ZERO, Vector2.ZERO, "D", Color.RED, "four")
	# Queue held 2 max: "two" was evicted by "four".
	_check("overflow keeps queue at max", d.pending() == 2)
	var got3: Dictionary = d.tick(ChatterDirector.COOLDOWN)
	_check("oldest queued line evicted", String(got3.get("text", "")) == "three")
	var got4: Dictionary = d.tick(ChatterDirector.COOLDOWN)
	_check("newest queued line kept", String(got4.get("text", "")) == "four")


func _test_clear() -> void:
	var d := _director()
	d.offer(true, Vector2.ZERO, Vector2.ZERO, "A", Color.RED, "one")
	d.offer(true, Vector2.ZERO, Vector2.ZERO, "B", Color.RED, "two")
	d.clear()
	_check("clear empties queue", d.pending() == 0)
	_check("clear resets cooldown", d.cooldown_left() <= 0.0)
	_check("offer works right after clear", d.offer(true, Vector2.ZERO, Vector2.ZERO, "C", Color.RED, "three"))


func _make_ticker() -> ChatterTicker:
	var t := ChatterTicker.new()
	root.add_child(t)
	t.refit(200.0, 1000.0, 1.0)
	return t


func _test_ticker_shows_speaker_color() -> void:
	var t := _make_ticker()
	t.push("Bob", Color(1, 0, 0), "hello there")
	_check("ticker showing after push", t.is_showing())
	var bb := t.shown_bbcode()
	_check("speaker name in faction color", bb.contains("[color=#ff0000]"))
	_check("speaker name present", bb.contains("Bob:"))
	_check("line text present", bb.contains("hello there"))


func _test_ticker_sanitizes_emoji() -> void:
	var t := _make_ticker()
	# iPhone tofu rule: non-ASCII becomes spaces, never tofu boxes.
	t.push("Bob", Color.RED, "hi 😀 there")
	var bb := t.shown_bbcode()
	_check("no raw emoji in ticker", not bb.contains("😀"))
	_check("ascii survives sanitize", bb.contains("hi") and bb.contains("there"))


func _test_ticker_empty_text_ignored() -> void:
	var t := _make_ticker()
	t.push("Bob", Color.RED, "   ")
	_check("empty push never shows", not t.is_showing())


func _test_ticker_anonymous_speaker() -> void:
	var t := _make_ticker()
	t.push("", Color(0, 0, 0, 0), "mysterious words")
	var bb := t.shown_bbcode()
	_check("anonymous line shows text", bb.contains("mysterious words"))
	_check("anonymous line has no speaker tag", not bb.contains("[color="))


func _test_ticker_never_blocks_taps() -> void:
	var t := _make_ticker()
	_check("ticker ignores mouse (never eats gameplay taps)",
		t.mouse_filter == Control.MOUSE_FILTER_IGNORE)
