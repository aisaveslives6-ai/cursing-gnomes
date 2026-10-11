extends SceneTree
## Cursing Gnomes — RuneScape-style chat bubble tests (Jeremy 2026-10-07).
##
## Jeremy 2026-10-05 ordered ALL bubbles removed (clutter). Jeremy
## 2026-10-07: "Give them chat bubbles. Like old school RuneScape" —
## small bubble above the speaker's head, speech only, temporary,
## capped count. These tests cover the ChatBubble node (spawn, text,
## position, fade, replacement) and the world's bubble management
## (one-per-NPC, max-count cull, dead-unit cleanup).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_chat_bubbles.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes chat bubble tests ===")
	_test_bubble_spawns_with_text()
	_test_bubble_sanitizes_text()
	_test_bubble_truncates_long_text()
	_test_bubble_wraps_long_lines()
	_test_bubble_short_line_stays_single()
	_test_bubble_never_exceeds_max_width()
	_test_bubble_empty_text_stays_hidden()
	_test_bubble_fades_after_timeout()
	_test_bubble_frees_after_fade()
	_test_new_speech_replaces_old()
	_test_bubble_above_head_offset()
	_test_bubble_z_index_above_world()
	_test_bubble_is_world_space()
	_test_max_bubbles_constant()
	_test_world_has_bubble_functions()
	_test_world_clears_bubbles_on_teardown()
	_test_clamp_shift_inside_unchanged()
	_test_clamp_shift_pulls_each_edge()
	_test_clamp_shift_oversized_pins_corner()
	# Viewport-dependent tests run deferred: nodes added to root during
	# _initialize() are not inside the tree yet, so get_viewport() is
	# null there — the clamp no-ops (by design, same as live when the
	# node is between add_child and tree entry).
	_run_viewport_tests.call_deferred()


func _run_viewport_tests() -> void:
	_test_bubble_clamps_offscreen_position()
	_test_bubble_centered_not_moved()
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


func _make_bubble() -> ChatBubble:
	var b := ChatBubble.new()
	root.add_child(b)
	return b


func _test_bubble_spawns_with_text() -> void:
	var b := _make_bubble()
	b.setup("hello there")
	_check("bubble spawns visible", b.visible)
	_check("bubble text stored", b.bubble_text() == "hello there")
	b.queue_free()


func _test_bubble_sanitizes_text() -> void:
	var b := _make_bubble()
	# Emoji/tofu must not reach the bubble (iPhone tofu rule).
	b.setup("hi \u2764\ufe0f")
	_check("bubble sanitizes emoji", "\u2764" not in b.bubble_text())
	b.queue_free()


func _test_bubble_truncates_long_text() -> void:
	var b := _make_bubble()
	var long_text := ""
	for i: int in range(200):
		long_text += "x"
	b.setup(long_text)
	_check("bubble truncates long text",
		b.bubble_text().length() <= ChatBubble.MAX_CHARS)
	b.queue_free()


func _test_bubble_wraps_long_lines() -> void:
	# Jeremy's no-clipped-text rule: a long NPC line (real dialogue pools
	# run 100+ chars) must wrap into multiple lines, not one screen-wide
	# slab. Width is capped; height grows with the line count.
	var b := _make_bubble()
	var line := "The quick brown gnome jumps over the lazy town wall again and again "
	line += "while shouting about taxes and cheese and destiny"
	var size: Vector2 = b.setup(line)
	_check("wrapped bubble width capped", size.x <= ChatBubble.MAX_BUBBLE_WIDTH + 0.5)
	_check("wrapped bubble splits lines", b.line_count() >= 2)
	var font: Font = ThemeDB.fallback_font
	var single_h: float = font.get_height(ChatBubble.FONT_SIZE) \
		+ ChatBubble.PAD_Y * 2.0
	_check("wrapped bubble is multi-line", size.y > single_h + 1.0)
	b.queue_free()


func _test_bubble_short_line_stays_single() -> void:
	# Short speech keeps its natural single-line size (no forced stretch
	# to the max width).
	var b := _make_bubble()
	var size: Vector2 = b.setup("hi")
	var font: Font = ThemeDB.fallback_font
	var single_h: float = font.get_height(ChatBubble.FONT_SIZE) \
		+ ChatBubble.PAD_Y * 2.0
	_check("short bubble single line height", absf(size.y - single_h) < 1.5)
	_check("short bubble narrower than cap", size.x < ChatBubble.MAX_BUBBLE_WIDTH)
	b.queue_free()


func _test_bubble_never_exceeds_max_width() -> void:
	# Pathological: one 89-char word with no spaces can't wrap — the
	# bubble is still hard-capped (clips the word, never the screen).
	var b := _make_bubble()
	var word := ""
	for i: int in range(89):
		word += "x"
	var size: Vector2 = b.setup(word)
	_check("unwrappable word still capped",
		size.x <= ChatBubble.MAX_BUBBLE_WIDTH + 0.5)
	b.queue_free()


func _test_bubble_empty_text_stays_hidden() -> void:
	var b := _make_bubble()
	b.setup("   ")
	# Empty after strip: _draw skips, text empty.
	_check("bubble empty text stored empty", b.bubble_text().is_empty())
	b.queue_free()


func _test_bubble_fades_after_timeout() -> void:
	var b := _make_bubble()
	b.setup("fading soon")
	# Simulate past the show window: alpha should drop below 1.
	b._process(ChatBubble.SHOW_SECONDS + 0.1)
	_check("bubble fades after timeout", b.modulate.a < 1.0)
	b.queue_free()


func _test_bubble_frees_after_fade() -> void:
	var b := _make_bubble()
	b.setup("goodbye")
	b._process(ChatBubble.SHOW_SECONDS + ChatBubble.FADE_SECONDS + 0.1)
	# queue_free was called; node is queued for deletion.
	_check("bubble queued free after fade", b.is_queued_for_deletion())
	# Don't double-free; it's already queued.


func _test_new_speech_replaces_old() -> void:
	var b := _make_bubble()
	b.setup("first line")
	b._process(2.0)  # age the bubble partway
	var age_before: float = b.age()
	b.setup("second line")  # new speech: timer resets
	_check("new speech resets age", b.age() < age_before)
	_check("new speech replaces text", b.bubble_text() == "second line")
	_check("replaced bubble fully visible", b.modulate.a >= 1.0)
	b.queue_free()


func _test_bubble_above_head_offset() -> void:
	# The world anchors bubbles at unit pos + BUBBLE_HEAD_OFFSET.
	# Offset must be upward (negative Y) and clear the chibi head.
	_check("head offset points up", World.BUBBLE_HEAD_OFFSET.y < 0.0)
	_check("head offset clears sprite",
		absf(World.BUBBLE_HEAD_OFFSET.y) >= 60.0)


func _test_bubble_z_index_above_world() -> void:
	var b := _make_bubble()
	# Above surrender flags (50) and unit art: bubbles read on top.
	_check("bubble z_index above world fx", b.z_index > 50)
	b.queue_free()


func _test_bubble_is_world_space() -> void:
	var b := _make_bubble()
	# Node2D in world space: never eats UI taps (no Control mouse filter).
	_check("bubble is Node2D", b is Node2D)
	b.queue_free()


func _test_max_bubbles_constant() -> void:
	# Anti-clutter cap: the number Jeremy's clutter complaint demands.
	_check("max bubbles capped at 8", World.MAX_CHAT_BUBBLES == 8)


func _test_world_has_bubble_functions() -> void:
	# Static: world.gd must wire spawn, tick, cull, and prune.
	var src := FileAccess.get_file_as_string(
		"res://scripts/world/world.gd")
	_check("world has _spawn_chat_bubble",
		src.contains("func _spawn_chat_bubble"))
	_check("world has _tick_chat_bubbles",
		src.contains("func _tick_chat_bubbles"))
	_check("world has _cull_chat_bubbles",
		src.contains("func _cull_chat_bubbles"))
	_check("world hooks tick in _process",
		src.contains("_tick_chat_bubbles()"))
	_check("world spawns on unit_said",
		src.contains("_spawn_chat_bubble(unit_id, upos, text)"))


func _test_world_clears_bubbles_on_teardown() -> void:
	var src := FileAccess.get_file_as_string(
		"res://scripts/world/world.gd")
	_check("world clears bubbles on teardown",
		src.contains("_chat_bubbles.clear()"))


func _test_clamp_shift_inside_unchanged() -> void:
	# Jeremy 2026-10-08 (no-clipped-text rule): a bubble already fully
	# on-screen must not move.
	var view := Rect2(0, 0, 1280, 720)
	var rect := Rect2(500, 300, 200, 60)
	_check("clamp shift zero when inside",
		ChatBubble._clamp_shift(rect, view, ChatBubble.EDGE_MARGIN) \
			== Vector2.ZERO)


func _test_clamp_shift_pulls_each_edge() -> void:
	var view := Rect2(0, 0, 1280, 720)
	var m: float = ChatBubble.EDGE_MARGIN
	# Past the left edge: pulled right to the margin.
	var s: Vector2 = ChatBubble._clamp_shift(
		Rect2(-50, 300, 200, 60), view, m)
	_check("clamp pulls right off left edge",
		absf(s.x - (m + 50.0)) < 0.01 and absf(s.y) < 0.01)
	# Past the right edge: pulled left to the margin.
	s = ChatBubble._clamp_shift(Rect2(1200, 300, 200, 60), view, m)
	_check("clamp pulls left off right edge",
		absf(s.x - (1280.0 - m - 1400.0)) < 0.01 and absf(s.y) < 0.01)
	# Past the top edge: pulled down.
	s = ChatBubble._clamp_shift(Rect2(500, -30, 200, 60), view, m)
	_check("clamp pulls down off top edge",
		absf(s.y - (m + 30.0)) < 0.01 and absf(s.x) < 0.01)
	# Past the bottom edge: pulled up.
	s = ChatBubble._clamp_shift(Rect2(500, 700, 200, 60), view, m)
	_check("clamp pulls up off bottom edge",
		absf(s.y - (720.0 - m - 760.0)) < 0.01 and absf(s.x) < 0.01)


func _test_clamp_shift_oversized_pins_corner() -> void:
	# Oversized rect (bigger than the view) pins to the top-left margin —
	# bubbles are hard-capped at 240px so this never triggers live, but
	# the helper must not produce NaN or a wild shift.
	var s: Vector2 = ChatBubble._clamp_shift(
		Rect2(-100, -100, 2000, 2000), Rect2(0, 0, 1280, 720),
		ChatBubble.EDGE_MARGIN)
	_check("oversized rect pins to top-left margin",
		absf(s.x - (ChatBubble.EDGE_MARGIN + 100.0)) < 0.01 \
		and absf(s.y - (ChatBubble.EDGE_MARGIN + 100.0)) < 0.01)


func _bubble_screen_rect(b: ChatBubble, size: Vector2) -> Rect2:
	var xform: Transform2D = b.get_global_transform_with_canvas()
	var tl: Vector2 = xform * Vector2(-size.x * 0.5, -size.y)
	var br: Vector2 = xform * Vector2(size.x * 0.5, 10.0)
	return Rect2(tl, br - tl)


func _test_bubble_clamps_offscreen_position() -> void:
	# Integration: a speaker far off-screen (top-left) gets the bubble
	# pulled fully inside the viewport by _process.
	var b := _make_bubble()
	var size: Vector2 = b.setup("edge of the world speech")
	b.position = Vector2(-1000, -1000)
	b._process(0.01)
	var view: Rect2 = root.get_visible_rect()
	var r := _bubble_screen_rect(b, size)
	var m: float = ChatBubble.EDGE_MARGIN
	_check("clamped bubble left edge on-screen",
		r.position.x >= view.position.x + m - 0.5)
	_check("clamped bubble top edge on-screen",
		r.position.y >= view.position.y + m - 0.5)
	_check("clamped bubble right edge on-screen", r.end.x <= view.end.x + 0.5)
	_check("clamped bubble bottom edge on-screen", r.end.y <= view.end.y + 0.5)
	b.queue_free()


func _test_bubble_centered_not_moved() -> void:
	# A bubble already on-screen is untouched (the clamp never fights
	# the world's per-frame positioning).
	var b := _make_bubble()
	b.setup("centered speech")
	var center: Vector2 = root.get_visible_rect().get_center()
	b.position = center
	b._process(0.01)
	_check("centered bubble not moved", b.position == center)
	b.queue_free()
