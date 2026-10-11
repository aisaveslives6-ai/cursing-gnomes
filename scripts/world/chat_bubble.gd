class_name ChatBubble
extends Node2D
## Cursing Gnomes — RuneScape-style chat bubbles (Jeremy 2026-10-07).
##
## Jeremy 2026-10-05 ordered ALL bubbles removed (screens were full of
## thought/activity/speech clutter blocking the battle view). The
## subtitle ticker ("Overheard") brought the voice back as HUD chrome.
## Jeremy 2026-10-07: "Give them chat bubbles. Like old school
## RuneScape" — so now speech ALSO gets a small bubble above the
## speaker's head, RS-style: rounded dark semi-transparent bubble,
## white text, little tail pointing down at the speaker. ONLY for
## actual speech (bus.unit_said with a unit position) — no thought
## bubbles, no activity icons, no permanent labels. Temporary: fades
## after ~4 seconds. The world caps concurrent bubbles (nearest to
## camera win) so the clutter Jeremy hated can't come back.
##
## World-space Node2D (not UI): position is set in world coordinates
## and the world updates it as the unit moves. Mouse-transparent by
## nature (Node2D never eats UI taps).

## Seconds the bubble stays fully visible before fading.
const SHOW_SECONDS := 3.5
## Seconds for the fade-out.
const FADE_SECONDS := 0.5
## Padding inside the bubble around the text.
const PAD_X := 10.0
const PAD_Y := 7.0
## Font size in world pixels (matches building label pips).
const FONT_SIZE := 13
## Max characters before we truncate (keeps bubbles small, RS-like).
const MAX_CHARS := 90
## Max bubble width in world px (Jeremy 2026-10-07: long NPC lines were
## rendering as one screen-wide slab with clipped text on iPhone — his
## "no clipped text" rule. RS-style bubbles wrap instead).
const MAX_BUBBLE_WIDTH := 240.0
## Screen-space margin kept between the bubble and the viewport edge
## (Jeremy 2026-10-08: a unit speaking near the screen edge got its
## bubble clipped off-screen — same "no clipped text" rule, the bubble
## is the text). _clamp_to_viewport() enforces it every frame.
const EDGE_MARGIN := 8.0
## Bubble fill: dark navy, semi-transparent (old-school RS vibe).
const BG_COLOR := Color(0.05, 0.07, 0.16, 0.92)
## Thin gold border (matches menu card accents).
const BORDER_COLOR := Color(0.79, 0.63, 0.15, 0.9)
const TEXT_COLOR := Color(1.0, 1.0, 1.0)

var _text := ""
var _lines := PackedStringArray()  # word-wrapped lines (see _wrap_lines)
var _age := 0.0
var _size := Vector2.ZERO  # bubble rect size (computed from text)


func _init() -> void:
	z_index = 100  # above surrender flags (50), below nothing UI


## Set (or replace) the bubble text. Resets the fade timer, so new
## speech from the same NPC replaces the old bubble instead of
## stacking. Returns the bubble's pixel size for layout use.
func setup(raw_text: String) -> Vector2:
	var clean := UrgentToast.sanitize(raw_text)
	clean = clean.replace("[", "").replace("]", "").strip_edges()
	if clean.length() > MAX_CHARS:
		clean = clean.left(MAX_CHARS - 1).strip_edges() + "…"
	_text = clean
	_age = 0.0
	modulate.a = 1.0
	visible = true
	_measure()
	set_process(true)
	queue_redraw()
	return _size


func _measure() -> void:
	var font: Font = ThemeDB.fallback_font
	var wrap_w: float = MAX_BUBBLE_WIDTH - PAD_X * 2.0
	_lines = _wrap_lines(font, _text, wrap_w)
	var widest := 0.0
	for ln: String in _lines:
		widest = maxf(widest, font.get_string_size(ln,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x)
	var lh: float = font.get_height(FONT_SIZE)
	_size = Vector2(minf(widest + PAD_X * 2.0, MAX_BUBBLE_WIDTH),
		lh * float(maxi(_lines.size(), 1)) + PAD_Y * 2.0)


## Greedy word-wrap: packs words into lines that fit wrap_w. A single
## word longer than wrap_w stays on its own line (the bubble width cap
## handles it — pathological input, never real dialogue).
func _wrap_lines(font: Font, text: String, wrap_w: float) -> PackedStringArray:
	var out := PackedStringArray()
	var space_w: float = font.get_string_size(" ",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
	var cur := ""
	var cur_w := 0.0
	for word: String in text.split(" "):
		if word.is_empty():
			continue
		var ww: float = font.get_string_size(word,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE).x
		var add: float = ww if cur.is_empty() else space_w + ww
		if not cur.is_empty() and cur_w + add > wrap_w:
			out.append(cur)
			cur = word
			cur_w = ww
		else:
			cur = word if cur.is_empty() else cur + " " + word
			cur_w += add
	if not cur.is_empty():
		out.append(cur)
	return out


func _process(delta: float) -> void:
	_age += delta
	var a := 1.0
	if _age >= SHOW_SECONDS:
		var t := (_age - SHOW_SECONDS) / FADE_SECONDS
		a = 1.0 - t
	modulate.a = clampf(a, 0.0, 1.0)
	_clamp_to_viewport()
	if _age >= SHOW_SECONDS + FADE_SECONDS:
		queue_free()


func _draw() -> void:
	if _text.is_empty() or _size.x <= 0.0:
		return
	var rect := Rect2(Vector2(-_size.x * 0.5, -_size.y), _size)
	# Tail: small triangle pointing down at the speaker's head.
	var tail := PackedVector2Array([
		Vector2(-7.0, 0.0),
		Vector2(7.0, 0.0),
		Vector2(0.0, 10.0),
	])
	draw_colored_polygon(tail, BG_COLOR)
	# Bubble body.
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(7)
	draw_style_box(sb, rect)
	# Text: wrapped lines, centered RS-style. pos is the baseline of the
	# first line; each line advances one line height.
	var font: Font = ThemeDB.fallback_font
	var ascent: float = font.get_ascent(FONT_SIZE)
	var lh: float = font.get_height(FONT_SIZE)
	var text_w: float = _size.x - PAD_X * 2.0
	for i: int in _lines.size():
		draw_string(font,
			Vector2(-_size.x * 0.5 + PAD_X,
				-_size.y + PAD_Y + ascent + lh * float(i)),
			_lines[i], HORIZONTAL_ALIGNMENT_CENTER, text_w,
			FONT_SIZE, TEXT_COLOR)


## Keep the whole bubble on-screen. The world re-anchors the bubble above
## the speaker's head every frame (world._tick_chat_bubbles); when the
## speaker walks near a viewport edge the bubble would clip off-screen,
## violating Jeremy's no-clipped-text rule. This pulls it back inside
## with EDGE_MARGIN clearance. Idempotent: once inside, the shift is
## zero, so it never fights the world's positioning.
## World-space node: the needed screen-space shift is converted back
## through the inverse canvas transform (assumes the world root itself
## has an identity transform — the camera moves the canvas, not the
## node, which is how world.gd positions bubbles today).
func _clamp_to_viewport() -> void:
	if _size.x <= 0.0:
		return  # nothing drawn (empty text) — nothing to clamp
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var view: Rect2 = vp.get_visible_rect()
	var xform: Transform2D = get_global_transform_with_canvas()
	var tl: Vector2 = xform * Vector2(-_size.x * 0.5, -_size.y)
	# br.y = 10: the speech tail triangle hangs 10px below the origin —
	# include it so the tail never clips either.
	var br: Vector2 = xform * Vector2(_size.x * 0.5, 10.0)
	var shift: Vector2 = _clamp_shift(Rect2(tl, br - tl), view, EDGE_MARGIN)
	if shift != Vector2.ZERO:
		position += xform.affine_inverse().basis_xform(shift)


## Pure helper (test seam): the screen-space shift that pulls rect
## inside view with at least margin px clearance on every side.
## Oversized rects (bigger than the view) pin to the top-left margin —
## bubbles are hard-capped at 240px wide, so this never triggers live.
static func _clamp_shift(rect: Rect2, view: Rect2, margin: float) -> Vector2:
	var s := Vector2.ZERO
	if rect.position.x < view.position.x + margin:
		s.x = view.position.x + margin - rect.position.x
	elif rect.end.x > view.end.x - margin:
		s.x = view.end.x - margin - rect.end.x
	if rect.position.y < view.position.y + margin:
		s.y = view.position.y + margin - rect.position.y
	elif rect.end.y > view.end.y - margin:
		s.y = view.end.y - margin - rect.end.y
	return s


## Test hook: current bubble text.
func bubble_text() -> String:
	return _text


## Test hook: number of wrapped text lines.
func line_count() -> int:
	return _lines.size()


## Test hook: seconds until the bubble starts fading.
func age() -> float:
	return _age
