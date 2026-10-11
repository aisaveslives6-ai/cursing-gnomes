class_name PhoneKeyboard
extends Control
## Cursing Gnomes — the phone's built-in custom keyboard (Jeremy 2026-10-04).
##
## Replaces the native OS keyboard everywhere in the phone. Pure Godot
## controls — identical on iOS, Android and PC. Backspace is our own logic
## so it cannot desync; no HTML input exists, so iOS cannot focus-zoom.
##
## Features:
##   - Full QWERTY + numbers/symbols pages, shift/caps, backspace repeat
##   - Large keys (92px) for fat fingers
##   - Suggestion bar (3 context-aware suggestions from SimKeyboardDict)
##   - Tap suggestion to complete; LONG-PRESS a learned-word suggestion to
##     delete it from the custom dictionary (with confirm)
##   - Autocorrect on space/send per the dict's aggression level; every
##     corrected word gets an iPhone-style BLUE UNDERLINE in the display
##   - Tap a blue-underlined word -> "did you mean X or Y?" review; picking
##     your original reverts it, blacklists the correction forever, and
##     offers "save word?"
##   - Manual reverts work too: backspace a corrected word, retype your
##     version, hit space — remembered + save offered after the first time
##   - "Add word?" prompt when an unknown word is typed 3+ times (learning
##     tracks what you TYPED, so corrections can't swallow it)
##   - Themes: dark, light, + 5 faction themes (human/ogre/elf/gnome/undead)
##   - UI chrome uses ASCII labels only (no glyphs — iPhone tofu rule)
##
## Usage:
##   var kb := PhoneKeyboard.new()
##   add_child(kb)
##   kb.open_for(line_edit)   # LineEdit (or any Control with .text)
##   kb.closed.connect(...)   # fired on dismiss

signal closed
signal word_learned(word: String)
signal word_deleted(word: String)
signal send_pressed

const THEMES := {
	"dark": {
		"name": "Midnight",
		"bg": Color(0.078, 0.078, 0.082),
		"key": Color(0.165, 0.165, 0.173),
		"key_fn": Color(0.208, 0.208, 0.216),
		"accent": Color(0.788, 0.635, 0.153),
		"fg": Color(0.941, 0.941, 0.945),
		"dim": Color(0.627, 0.627, 0.639),
		"sugg_bg": Color(0.110, 0.110, 0.114),
	},
	"light": {
		"name": "Daybreak",
		"bg": Color(0.902, 0.902, 0.910),
		"key": Color(0.980, 0.980, 0.984),
		"key_fn": Color(0.847, 0.847, 0.859),
		"accent": Color(0.204, 0.412, 0.780),
		"fg": Color(0.110, 0.110, 0.118),
		"dim": Color(0.427, 0.427, 0.443),
		"sugg_bg": Color(0.941, 0.941, 0.949),
	},
	"human": {
		"name": "Human Gold",
		"bg": Color(0.102, 0.078, 0.043),
		"key": Color(0.208, 0.157, 0.086),
		"key_fn": Color(0.263, 0.200, 0.110),
		"accent": Color(0.949, 0.761, 0.184),
		"fg": Color(0.980, 0.945, 0.839),
		"dim": Color(0.718, 0.639, 0.482),
		"sugg_bg": Color(0.141, 0.110, 0.063),
	},
	"ogre": {
		"name": "Ogre Blood",
		"bg": Color(0.110, 0.043, 0.043),
		"key": Color(0.227, 0.098, 0.098),
		"key_fn": Color(0.286, 0.125, 0.125),
		"accent": Color(0.949, 0.322, 0.322),
		"fg": Color(0.984, 0.902, 0.902),
		"dim": Color(0.741, 0.522, 0.522),
		"sugg_bg": Color(0.153, 0.063, 0.063),
	},
	"elf": {
		"name": "Elf Glade",
		"bg": Color(0.043, 0.102, 0.098),
		"key": Color(0.086, 0.208, 0.200),
		"key_fn": Color(0.110, 0.263, 0.251),
		"accent": Color(0.396, 0.949, 0.910),
		"fg": Color(0.839, 0.980, 0.973),
		"dim": Color(0.482, 0.718, 0.702),
		"sugg_bg": Color(0.063, 0.141, 0.137),
	},
	"gnome": {
		"name": "Gnome Garden",
		"bg": Color(0.051, 0.110, 0.051),
		"key": Color(0.102, 0.227, 0.102),
		"key_fn": Color(0.129, 0.286, 0.129),
		"accent": Color(0.443, 0.949, 0.443),
		"fg": Color(0.906, 0.984, 0.906),
		"dim": Color(0.541, 0.741, 0.541),
		"sugg_bg": Color(0.071, 0.153, 0.071),
	},
	"undead": {
		"name": "Undead Crypt",
		"bg": Color(0.082, 0.051, 0.110),
		"key": Color(0.165, 0.102, 0.227),
		"key_fn": Color(0.208, 0.129, 0.286),
		"accent": Color(0.761, 0.443, 0.949),
		"fg": Color(0.945, 0.906, 0.984),
		"dim": Color(0.639, 0.541, 0.741),
		"sugg_bg": Color(0.114, 0.071, 0.153),
	},
}

const THEME_ORDER := ["dark", "light", "human", "ogre", "elf", "gnome", "undead"]

var dict: SimKeyboardDict = null

var _field: Control = null        # the LineEdit (or any Control with .text)
var _on_text_changed: Callable = Callable()  # fired after each edit
var _theme_id: String = "dark"
var _scale := 1.0
var _shift := false
var _caps := false
var _page := 0  # 0 = letters, 1 = numbers/symbols
var _display: UnderlineDisplay = null
var _sugg_bar: HBoxContainer = null
var _sugg_btns: Array = []
## Jeremy 2026-10-06: last suggestion list actually shown — lets
## _refresh_suggestions skip the queue_free/rebuild churn when the
## top-3 didn't change between keystrokes.
var _shown_suggs: Array = []
var _letter_btns: Dictionary = {}
## Jeremy 2026-10-06 (polish round 2): bottom-sheet panel ref, so open_for
## can slide it up.
var _panel: PanelContainer = null
var _shift_btn: Button = null
var _page_btn: Button = null
var _bs_timer: Timer = null
var _longpress_timer: Timer = null
var _longpress_word: String = ""
var _blink := 0.0
## Jeremy 2026-10-06: _process used to queue_redraw() every frame even when
## idle. Track last-drawn state and only redraw on actual change.
var _last_drawn_text := ""
var _last_drawn_marks: Array = []
var _last_cursor := false
var _pending_learn: String = "" # word awaiting "Add word?" answer
var _learn_dialog: Control = null
# Blue-underline marks: one per autocorrected word still in the text.
# Each: {"start": int, "end": int, "typed": String, "corrected": String}.
var _marks: Array = []
# Last autocorrection, for manual-revert detection:
# {"typed": String, "corrected": String}. Set when a correction fires,
# cleared when the user moves on; if the next completed word IS the typed
# original, that's a revert — honor it, remember it, offer to save it.
var _pending_correction: Dictionary = {}

# Long-press threshold for deleting a learned suggestion.
const LONGPRESS_SEC := 0.6

# iPhone-style autocorrect marker blue.
const MARK_BLUE := Color(0.30, 0.58, 1.00)


## Typing display: mirrors the field text, draws a blue underline under
## every autocorrected word, and lets the user tap one to review it.
class UnderlineDisplay extends Control:
	var text := ""
	var marks: Array = []
	var font_size := 24
	var text_color := Color(0.94, 0.94, 0.94)
	var mark_color := Color(0.30, 0.58, 1.00)
	var cursor_on := true
	signal word_tapped(mark: Dictionary)

	func _draw() -> void:
		var font := get_theme_default_font()
		if font == null:
			return
		var fs := font_size
		var ox := 8.0
		var baseline := size.y * 0.5 + float(fs) * 0.35
		draw_string(font, Vector2(ox, baseline), text,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - ox * 2.0, fs, text_color)
		for m in marks:
			if not (m is Dictionary):
				continue
			var s := int((m as Dictionary).get("start", -1))
			var e := int((m as Dictionary).get("end", -1))
			if s < 0 or e > text.length() or s >= e:
				continue
			var xa := ox + font.get_string_size(text.substr(0, s),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var xb := ox + font.get_string_size(text.substr(0, e),
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_line(Vector2(xa, baseline + 5.0), Vector2(xb, baseline + 5.0),
				mark_color, 3.0)
		if cursor_on:
			var cx := ox + font.get_string_size(text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_line(Vector2(cx, baseline - float(fs)),
				Vector2(cx, baseline + 5.0), text_color, 2.0)

	func _gui_input(event: InputEvent) -> void:
		var pressed := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			pressed = (event as InputEventScreenTouch).pressed
		if not pressed:
			return
		var idx := _char_at_x(event.position.x)
		for m in marks:
			if not (m is Dictionary):
				continue
			var s := int((m as Dictionary).get("start", -1))
			var e := int((m as Dictionary).get("end", -1))
			if s <= idx and idx < e:
				word_tapped.emit(m)
				return

	func _char_at_x(lx: float) -> int:
		var font := get_theme_default_font()
		if font == null:
			return 0
		var x := 8.0
		for i in text.length():
			var w := font.get_string_size(text.substr(i, 1),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if lx < x + w * 0.5:
				return i
			x += w
		return text.length()


func _init() -> void:
	dict = SimKeyboardDict.new()
	visible = false


func _t(key: String) -> Color:
	return THEMES[_theme_id][key]


func set_kb_theme(theme_id: String) -> void:
	if THEMES.has(theme_id):
		_theme_id = theme_id
		if visible:
			_rebuild()


func current_theme() -> String:
	return _theme_id


func theme_name(theme_id: String) -> String:
	return String(THEMES.get(theme_id, {}).get("name", theme_id))


func _s(v: float) -> float:
	return v * _scale


func _si(v: int) -> int:
	return maxi(1, int(round(float(v) * _scale)))


# --- open / close ---------------------------------------------------------------

func open_for(field: Control, ui_scale: float, on_text_changed: Callable = Callable()) -> void:
	_field = field
	_scale = ui_scale
	_on_text_changed = on_text_changed
	_shift = false
	_caps = false
	_page = 0
	_marks.clear()
	_pending_correction = {}
	_pending_learn = ""
	if _bs_timer == null:
		_bs_timer = Timer.new()
		_bs_timer.one_shot = true
		_bs_timer.timeout.connect(_on_bs_tick)
		add_child(_bs_timer)
	if _longpress_timer == null:
		_longpress_timer = Timer.new()
		_longpress_timer.one_shot = true
		_longpress_timer.timeout.connect(_on_sugg_longpress)
		add_child(_longpress_timer)
	_rebuild()
	visible = true
	_refresh_suggestions()
	# Jeremy 2026-10-06 (polish round 2): the key sheet slides up like a
	# real phone keyboard instead of popping in.
	if is_inside_tree() and _panel != null and is_instance_valid(_panel):
		var target := _panel.offset_top
		_panel.offset_top = 0.0
		var tw := create_tween()
		tw.tween_property(_panel, "offset_top", target, 0.24)\
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func close() -> void:
	visible = false
	if _bs_timer != null:
		_bs_timer.stop()
	if _longpress_timer != null:
		_longpress_timer.stop()
	_dismiss_learn_dialog()
	_marks.clear()
	_pending_correction = {}
	_field = null
	closed.emit()


func is_open() -> bool:
	return visible


# --- layout ------------------------------------------------------------------------

func _rebuild() -> void:
	for c in get_children():
		if c != _bs_timer and c != _longpress_timer:
			c.queue_free()
	_letter_btns.clear()
	_sugg_btns.clear()
	_shown_suggs.clear()
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Dim: tap outside the keys to dismiss (text is saved live).
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		var dismiss := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			dismiss = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			dismiss = (event as InputEventScreenTouch).pressed
		if dismiss:
			close()
	)
	add_child(dim)
	# Bottom sheet panel.
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = _t("bg")
	psb.border_color = _t("accent")
	psb.border_width_top = _si(2)
	psb.content_margin_left = _s(10)
	psb.content_margin_right = _s(10)
	psb.content_margin_top = _s(8)
	psb.content_margin_bottom = _s(14)
	panel.add_theme_stylebox_override("panel", psb)
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	var key_h := _s(92)
	var disp_h := _s(56)
	var sugg_h := _s(52)
	var total_h := disp_h + sugg_h + key_h * 4.0 + _s(8) * 6.0 + _s(24)
	# Jeremy 2026-10-06 (launch readiness): the sheet used to sit flush on
	# the phone's bottom edge — the bottom key row rendered under the drawn
	# home-indicator pill and the real iOS home-indicator zone. Lift it by
	# the phone shell's safe-bottom inset (parent PhoneUI exposes it).
	var lift := 0.0
	var par := get_parent()
	if par != null and par.has_method("phone_safe_bottom"):
		lift = float(par.call("phone_safe_bottom"))
	panel.offset_top = -total_h - lift
	panel.offset_bottom = -lift
	add_child(panel)
	_panel = panel
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _si(8))
	panel.add_child(v)
	# Typing display (mirrors the field; blue underlines mark corrections).
	_display = UnderlineDisplay.new()
	_display.custom_minimum_size = Vector2(0, disp_h)
	_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_display.mouse_filter = Control.MOUSE_FILTER_STOP
	_display.font_size = _si(24)
	_display.text_color = _t("fg")
	_display.mark_color = MARK_BLUE
	_display.word_tapped.connect(_on_mark_tapped)
	v.add_child(_display)
	# Suggestion bar.
	_sugg_bar = HBoxContainer.new()
	_sugg_bar.custom_minimum_size = Vector2(0, sugg_h)
	_sugg_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_sugg_bar.add_theme_constant_override("separation", _si(8))
	v.add_child(_sugg_bar)
	# Key rows.
	if _page == 0:
		v.add_child(_key_row("qwertyuiop"))
		v.add_child(_key_row("asdfghjkl"))
		v.add_child(_fn_row())
	else:
		v.add_child(_key_row("1234567890"))
		v.add_child(_key_row("-/:;()$&@"))
		v.add_child(_sym_row())
	v.add_child(_bottom_row())
	_blink = 0.0
	_refresh_key_labels()


func _process(delta: float) -> void:
	if not visible or _display == null:
		return
	_blink += delta
	var cursor := fmod(_blink, 1.0) < 0.55
	var t := _field_text()
	if t != _last_drawn_text or cursor != _last_cursor or _marks != _last_drawn_marks:
		_last_drawn_text = t
		_last_cursor = cursor
		_last_drawn_marks = _marks.duplicate()
		_display.text = t
		_display.marks = _marks
		_display.cursor_on = cursor
		_display.queue_redraw()


func _field_text() -> String:
	if _field != null and "text" in _field:
		return String(_field.get("text"))
	return ""


func _set_field_text(t: String) -> void:
	if _field != null and "text" in _field:
		_field.set("text", t)
	if _on_text_changed.is_valid():
		_on_text_changed.call()


# --- keys -----------------------------------------------------------------------------

func _make_key(label_text: String, bg: Color, fg: Color, wide := 1.5) -> Button:
	var b := Button.new()
	b.text = label_text
	b.focus_mode = Control.FOCUS_NONE
	# Jeremy 2026-10-05: big keys for fat fingers (92px, 27pt).
	b.custom_minimum_size = Vector2(0, _s(92))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_stretch_ratio = wide
	b.add_theme_font_size_override("font_size", _si(27))
	b.add_theme_color_override("font_color", fg)
	# Jeremy 2026-10-06 (polish round 2): glassier keys — hairline border,
	# soft radius, matching the Bastard OS 2.0 phone chrome.
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(_si(10))
	sb.set_border_width_all(maxi(1, _si(1)))
	sb.border_color = bg.darkened(0.38)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = _si(3)
	b.add_theme_stylebox_override("normal", sb)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = bg.darkened(0.18)
	sb_p.border_color = _t("accent").darkened(0.25)
	b.add_theme_stylebox_override("pressed", sb_p)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = bg.lightened(0.10)
	b.add_theme_stylebox_override("hover", sb_h)
	# Jeremy 2026-10-06 (polish round 2): tactile key pop on press, and the
	# stuck-glow fix on release (see _key_release_glow).
	b.button_down.connect(_key_press_pop.bind(b))
	b.button_up.connect(_key_release_glow.bind(b))
	return b


## Jeremy 2026-10-06 (polish round 2): key press pop — quick dip and
## spring back, like a real phone keyboard.
func _key_press_pop(b) -> void:
	# GDScript 4 note (launch readiness 2026-10-06): a freed bound Object
	# fails the typed-parameter check BEFORE the body runs, so the param
	# stays untyped and the is_instance_valid guard does the real work.
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	b.pivot_offset = b.size / 2.0
	var tw = b.create_tween()  # untyped: b is untyped (see above)
	tw.tween_property(b, "scale", Vector2(0.88, 0.88), 0.07)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(b, "scale", Vector2.ONE, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Jeremy 2026-10-06 (polish round 2): FIX for the stuck key glow — the
## last-touched key stayed highlighted because on touch screens Godot's
## emulated mouse never moves away, so the hover stylebox lingers after
## release. Cycling mouse_filter forces the viewport to drop hover state.
## Deferred to idle: cycling during button_up can swallow the Button's
## pressed emission on touch.
func _key_release_glow(b) -> void:
	# Untyped param: see _key_press_pop — a freed bound key must reach the
	# guard below instead of erroring on the typed-parameter check.
	if not is_instance_valid(b):
		return
	var tree := get_tree()
	if tree == null:
		_cycle_key_filter(b)
		return
	tree.create_timer(0.0).timeout.connect(
		_cycle_key_filter.bind(b), CONNECT_ONE_SHOT)
	# Belt and suspenders: re-cycle shortly after, in case the first pass
	# raced the viewport's hover bookkeeping.
	tree.create_timer(0.08).timeout.connect(
		_cycle_key_filter.bind(b), CONNECT_ONE_SHOT)


func _cycle_key_filter(b) -> void:
	# Untyped param: see _key_press_pop — timer-deferred calls may arrive
	# after the key was freed (e.g. phone rotated mid-typing).
	if not is_instance_valid(b):
		return
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.mouse_filter = Control.MOUSE_FILTER_STOP


func _key_row(letters: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _si(6))
	for i in letters.length():
		var ch := letters[i]
		var b := _make_key(ch.to_upper(), _t("key"), _t("fg"))
		if _page == 0:
			_letter_btns[ch] = b
			b.pressed.connect(_insert_letter.bind(ch))
		else:
			b.pressed.connect(_insert_symbol.bind(ch))
		row.add_child(b)
	return row


func _fn_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _si(6))
	_shift_btn = _make_key("SHIFT", _t("key_fn"), _t("fg"), 2.2)
	_shift_btn.pressed.connect(_toggle_shift)
	row.add_child(_shift_btn)
	for i in "zxcvbnm".length():
		var ch := "zxcvbnm"[i]
		var b := _make_key(ch.to_upper(), _t("key"), _t("fg"))
		_letter_btns[ch] = b
		b.pressed.connect(_insert_letter.bind(ch))
		row.add_child(b)
	var bs := _make_key("BKSP", _t("key_fn"), _t("fg"), 2.2)
	bs.button_down.connect(_on_bs_down)
	bs.button_up.connect(_on_bs_up)
	row.add_child(bs)
	_refresh_shift_btn()
	return row


func _sym_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _si(6))
	for sym in ["_", ".", ",", "?", "!", "'"]:
		var b := _make_key(sym, _t("key"), _t("fg"))
		b.pressed.connect(_insert_symbol.bind(sym))
		row.add_child(b)
	var bs := _make_key("BKSP", _t("key_fn"), _t("fg"), 2.2)
	bs.button_down.connect(_on_bs_down)
	bs.button_up.connect(_on_bs_up)
	row.add_child(bs)
	return row


func _bottom_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _si(6))
	_page_btn = _make_key("123" if _page == 0 else "ABC", _t("key_fn"), _t("fg"), 2.0)
	_page_btn.pressed.connect(_toggle_page)
	row.add_child(_page_btn)
	var sp := _make_key("SPACE", _t("key"), _t("fg"), 6.0)
	sp.pressed.connect(_on_space)
	row.add_child(sp)
	var ret := _make_key("SEND", _t("accent"), _t("bg"), 2.6)
	ret.pressed.connect(_on_send)
	row.add_child(ret)
	return row


func _insert_letter(ch: String) -> void:
	var c := ch.to_upper() if (_shift or _caps) else ch.to_lower()
	_insert_raw(c)
	if _shift and not _caps:
		_shift = false
		_refresh_key_labels()
		_refresh_shift_btn()


func _insert_symbol(ch: String) -> void:
	_insert_raw(ch)
	if ch in [".", "!", "?"]:
		dict.note_sentence_end()
		_pending_correction = {}  # sentence ended — the correction stands
		# Jeremy 2026-10-05: auto-space after sentence punctuation (toggleable).
		if dict.auto_space and not _field_text().ends_with(" "):
			_set_field_text(_field_text() + " ")
			_refresh_suggestions()


func _insert_raw(c: String) -> void:
	var t := _field_text()
	_set_field_text(t + c)
	_refresh_suggestions()


func _toggle_shift() -> void:
	if _caps:
		_caps = false
		_shift = false
	elif _shift:
		_shift = false
		_caps = true
	else:
		_shift = true
	_refresh_key_labels()
	_refresh_shift_btn()


func _toggle_page() -> void:
	_page = 1 - _page
	_rebuild()
	_refresh_suggestions()


func _refresh_key_labels() -> void:
	var upper := _shift or _caps
	for ch in _letter_btns:
		var b := _letter_btns[ch] as Button
		if b != null:
			b.text = (ch as String).to_upper() if upper else (ch as String).to_lower()


func _refresh_shift_btn() -> void:
	if _shift_btn == null:
		return
	_shift_btn.text = "CAPS" if _caps else "SHIFT"
	_shift_btn.modulate = Color(1.0, 0.85, 0.45) if (_shift or _caps) else Color.WHITE


func _on_bs_down() -> void:
	_backspace()
	if _bs_timer != null:
		_bs_timer.start(0.45)


func _on_bs_up() -> void:
	if _bs_timer != null:
		_bs_timer.stop()


func _on_bs_tick() -> void:
	_backspace()
	if _bs_timer != null and visible:
		_bs_timer.start(0.07)


func _backspace() -> void:
	var t := _field_text()
	if t.length() > 0:
		_set_field_text(t.substr(0, t.length() - 1))
		# Drop marks on words the user is editing into (stale ranges).
		var L := _field_text().length()
		_marks = _marks.filter(func(m: Dictionary) -> bool:
			return int(m.get("end", 0)) <= L)
		_refresh_suggestions()


# --- word completion: space / send -------------------------------------------------------
## Split off the last word, run it through learning + autocorrect.
##
## Autocorrect fires per word (space/send = real time, like iPhone).
## Corrected words get a blue underline (tap one to review it).
## Learning tracks what you TYPED, so a correction can never swallow it.

func _complete_word(apply_autocorrect: bool = true) -> void:
	var t := _field_text()
	if t == "" or t.ends_with(" "):
		return
	var idx := t.rfind(" ")
	var word := t if idx < 0 else t.substr(idx + 1)
	var head := "" if idx < 0 else t.substr(0, idx + 1)
	var prev := ""
	if idx > 0:
		var head_trim := head.strip_edges()
		var pi := head_trim.rfind(" ")
		prev = head_trim if pi < 0 else head_trim.substr(pi + 1)
	var clean_word := dict._clean(word)
	# Manual revert: the user backspaced a word we just corrected and
	# retyped their version. Honor it, remember it, offer to save it —
	# after the first time it sticks.
	if not _pending_correction.is_empty() \
			and clean_word != "" \
			and clean_word == String(_pending_correction.get("typed", "")):
		var typed := String(_pending_correction["typed"])
		var corr := String(_pending_correction["corrected"])
		_pending_correction = {}
		_drop_marks_from(head.length())
		dict.note_correction_overridden(typed, corr)
		var lr := dict.note_word_typed(typed, typed)
		if lr == "learned":
			word_learned.emit(typed)
		_set_field_text(head + typed + " ")
		if not dict.is_known(typed):
			_show_save_dialog(typed)
		_refresh_suggestions()
		return
	# Not a revert — any pending correction stands.
	_pending_correction = {}
	# Autocorrect first (may rewrite the word) — unless this completion came
	# from Send. Jeremy 2026-10-06 (Allison verdict): pressing Send must NEVER
	# rewrite the trailing word — what she typed is what gets sent. A
	# send-time rewrite once told an ogre she wanted war. Corrections happen
	# on Space, where each one gets a blue underline and tap-to-review.
	var corrected := ""
	if apply_autocorrect:
		corrected = dict.autocorrect(word, prev)
	var final_word := word
	if corrected != "":
		final_word = corrected
		var start := head.length()
		_marks.append({"start": start, "end": start + corrected.length(),
			"typed": clean_word, "corrected": corrected})
		_pending_correction = {"typed": clean_word, "corrected": corrected}
	# Learning pipeline (frequency, bigrams, unknown tracking) — gets the
	# ORIGINAL typed word too, so corrections can't eat learning.
	var learn_result := dict.note_word_typed(final_word, word)
	_set_field_text(head + final_word + " ")
	# Bigram chain continues across spaces — only send/punctuation ends it.
	# The prompt/learned word may be the TYPED original (not the correction).
	var learn_word := dict.last_prompt_word if dict.last_prompt_word != "" else final_word
	if learn_result == "prompt":
		_show_learn_dialog(learn_word)
	elif learn_result == "learned":
		word_learned.emit(learn_word)
	_refresh_suggestions()


func _on_space() -> void:
	_complete_word()


func _on_send() -> void:
	# Send completes the trailing word for LEARNING but never autocorrects
	# it (see _complete_word): the text goes out exactly as typed.
	_complete_word(false)
	dict.note_sentence_end()
	# The host (e.g. Messenger) listens for "closed" or handles send itself.
	# We expose the text via the field; hosts can also connect a send hook.
	send_pressed.emit()
	close()


# --- suggestion bar --------------------------------------------------------------------------

func _current_partial() -> String:
	var t := _field_text()
	if t == "" or t.ends_with(" "):
		return ""
	var idx := t.rfind(" ")
	return t if idx < 0 else t.substr(idx + 1)


func _prev_word() -> String:
	var t := _field_text().strip_edges()
	var idx := t.rfind(" ")
	if idx < 0:
		return ""
	var head := t.substr(0, idx)
	var pi := head.rfind(" ")
	return head if pi < 0 else head.substr(pi + 1)


func _refresh_suggestions() -> void:
	if _sugg_bar == null:
		return
	var partial := _current_partial()
	var suggs: Array = []
	if partial != "":
		suggs = dict.suggestions(partial, _prev_word(), 3)
	# Jeremy 2026-10-06: skip the whole queue_free/rebuild when the
	# visible suggestions didn't change (common while typing a word).
	if suggs == _shown_suggs:
		return
	_shown_suggs = suggs.duplicate()
	for c in _sugg_bar.get_children():
		c.queue_free()
	_sugg_btns.clear()
	if suggs.is_empty():
		return
	for s in suggs:
		var word := String(s)
		var b := Button.new()
		b.text = word
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, _s(52))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", _si(18))
		var sb := StyleBoxFlat.new()
		sb.bg_color = _t("sugg_bg")
		sb.set_corner_radius_all(_si(10))
		if dict.is_learned(word):
			sb.border_color = _t("accent")
			sb.set_border_width_all(_si(1))
		b.add_theme_stylebox_override("normal", sb)
		var sb_p := sb.duplicate() as StyleBoxFlat
		sb_p.bg_color = _t("sugg_bg").darkened(0.15)
		b.add_theme_stylebox_override("pressed", sb_p)
		b.add_theme_color_override("font_color", _t("fg"))
		# Tap = accept. Long-press on a LEARNED word = delete it.
		b.pressed.connect(_accept_suggestion.bind(word))
		b.button_down.connect(_on_sugg_down.bind(word))
		b.button_up.connect(_on_sugg_up)
		# Jeremy 2026-10-06 (polish round 2): same stuck-glow fix as keys.
		b.button_up.connect(_key_release_glow.bind(b))
		_sugg_bar.add_child(b)
		_sugg_btns.append(b)


func _accept_suggestion(word: String) -> void:
	# Ignore taps that were actually long-presses (handled separately).
	if _longpress_word != "":
		return
	var t := _field_text()
	var idx := t.rfind(" ")
	var head := "" if idx < 0 else t.substr(0, idx + 1)
	dict.note_word_typed(word)
	# Jeremy 2026-10-05: trailing space after a suggestion is the auto-space
	# setting — off means the word drops in bare.
	_set_field_text(head + word + (" " if dict.auto_space else ""))
	_pending_correction = {}  # accepted a suggestion — moved on
	_refresh_suggestions()


func _on_sugg_down(word: String) -> void:
	# Only learned words are deletable — start the long-press timer.
	if dict.is_learned(word) and _longpress_timer != null:
		_longpress_word = word
		_longpress_timer.start(LONGPRESS_SEC)


func _on_sugg_up() -> void:
	_longpress_word = ""
	if _longpress_timer != null:
		_longpress_timer.stop()


func _on_sugg_longpress() -> void:
	var word := _longpress_word
	_longpress_word = ""
	if word == "" or not dict.is_learned(word):
		return
	_show_delete_dialog(word)


# --- blue-underline marks: tap to review -------------------------------------------------
## Test/debug accessor: current autocorrect marks.
func autocorrect_marks() -> Array:
	return _marks.duplicate()


func _drop_mark(mark: Dictionary) -> void:
	var s := int(mark.get("start", -1))
	var e := int(mark.get("end", -1))
	_marks = _marks.filter(func(m: Dictionary) -> bool:
		return int(m.get("start", -2)) != s or int(m.get("end", -2)) != e)


func _drop_marks_from(pos: int) -> void:
	_marks = _marks.filter(func(m: Dictionary) -> bool:
		return int(m.get("start", 0)) < pos)


## Tap on a blue-underlined word -> "did you mean X or Y?"
func _on_mark_tapped(mark: Dictionary) -> void:
	var t := _field_text()
	var s := int(mark.get("start", -1))
	var e := int(mark.get("end", -1))
	if s < 0 or e > t.length() or s >= e:
		return
	# Stale mark (word edited since the correction) — drop silently.
	if dict._clean(t.substr(s, e - s)) != String(mark.get("corrected", "")):
		_drop_mark(mark)
		return
	_show_review_dialog(mark)


func _show_review_dialog(mark: Dictionary) -> void:
	_dismiss_learn_dialog()
	var typed := String(mark.get("typed", ""))
	var corrected := String(mark.get("corrected", ""))
	var dlg := _make_dialog("Did you mean \"%s\" or \"%s\"?" % [corrected, typed],
		"Taking back \"%s\" teaches the keyboard to never change it again." % typed)
	var btn_row := dlg.get_meta("btn_row") as HBoxContainer
	btn_row.add_child(_dialog_button("\"%s\"" % corrected, func() -> void:
		_keep_mark_correction(mark)
	))
	btn_row.add_child(_dialog_button("\"%s\"" % typed, func() -> void:
		_revert_mark(mark)
	))
	add_child(dlg)
	_learn_dialog = dlg


## User accepted our correction — the blue underline goes away.
func _keep_mark_correction(mark: Dictionary) -> void:
	_drop_mark(mark)
	_pending_correction = {}
	_dismiss_learn_dialog()


## User took back their original typing: revert the word, remember the
## correction forever, and offer to save the word.
func _revert_mark(mark: Dictionary) -> void:
	var t := _field_text()
	var s := int(mark.get("start", 0))
	var e := int(mark.get("end", 0))
	var typed := String(mark.get("typed", ""))
	var corrected := String(mark.get("corrected", ""))
	if s >= 0 and e <= t.length() and s < e and typed != "":
		var delta := typed.length() - (e - s)
		_set_field_text(t.substr(0, s) + typed + t.substr(e))
		# Shift later marks (the reverted one is dropped below).
		for m in _marks:
			if int((m as Dictionary).get("start", 0)) >= e:
				(m as Dictionary)["start"] = int((m as Dictionary).get("start", 0)) + delta
				(m as Dictionary)["end"] = int((m as Dictionary).get("end", 0)) + delta
	_drop_mark(mark)
	_pending_correction = {}
	# Remember: never make this correction again.
	dict.note_correction_overridden(typed, corrected)
	_dismiss_learn_dialog()
	if not dict.is_known(typed):
		_show_save_dialog(typed)
	else:
		_refresh_suggestions()


## "Save word?" — offered after the user takes back their typing.
func _show_save_dialog(word: String) -> void:
	_dismiss_learn_dialog()
	if word == "":
		return
	var dlg := _make_dialog("Save \"%s\" to your dictionary?" % word,
		"It will never be autocorrected, and it shows up in suggestions.")
	var btn_row := dlg.get_meta("btn_row") as HBoxContainer
	btn_row.add_child(_dialog_button("Save word", func() -> void:
		_confirm_save_word(word)
	))
	btn_row.add_child(_dialog_button("Not now", func() -> void:
		_dismiss_learn_dialog()
	))
	add_child(dlg)
	_learn_dialog = dlg


func _confirm_save_word(word: String) -> void:
	dict.add_learned_word(word)
	word_learned.emit(word)
	_dismiss_learn_dialog()
	_shown_suggs.clear()  # learned border styling must repaint
	_refresh_suggestions()


# --- "Add word?" dialog --------------------------------------------------------------------------

func _show_learn_dialog(word: String) -> void:
	_dismiss_learn_dialog()
	_pending_learn = word
	var dlg := _make_dialog("Add \"%s\" to your dictionary?" % word,
		"You've typed it %d times." % SimKeyboardDict.LEARN_THRESHOLD)
	var btn_row := dlg.get_meta("btn_row") as HBoxContainer
	btn_row.add_child(_dialog_button("Add word", func() -> void:
		dict.add_learned_word(word)
		word_learned.emit(word)
		_dismiss_learn_dialog()
		_shown_suggs.clear()  # learned border styling must repaint
		_refresh_suggestions()
	))
	btn_row.add_child(_dialog_button("Not now", func() -> void:
		_dismiss_learn_dialog()
	))
	add_child(dlg)
	_learn_dialog = dlg


func _show_delete_dialog(word: String) -> void:
	_dismiss_learn_dialog()
	var dlg := _make_dialog("Delete \"%s\"?" % word,
		"Remove it from your learned words? (Hold a suggestion to do this anytime.)")
	var btn_row := dlg.get_meta("btn_row") as HBoxContainer
	btn_row.add_child(_dialog_button("Delete", func() -> void:
		if dict.remove_learned_word(word):
			word_deleted.emit(word)
		_dismiss_learn_dialog()
		_refresh_suggestions()
	))
	btn_row.add_child(_dialog_button("Keep", func() -> void:
		_dismiss_learn_dialog()
	))
	add_child(dlg)
	_learn_dialog = dlg


func _make_dialog(title: String, subtitle: String) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.6)
	# Jeremy's tap-outside-to-close rule: the dim is no longer dead — a tap
	# outside the card dismisses the dialog without choosing, same as the
	# keyboard's own dim ("text is saved live" there; here the choice is
	# simply skipped).
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		var tapped := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			tapped = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			tapped = (event as InputEventScreenTouch).pressed
		if tapped:
			_dismiss_learn_dialog()
	)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = _t("bg")
	psb.border_color = _t("accent")
	psb.set_border_width_all(_si(2))
	psb.set_corner_radius_all(_si(12))
	psb.content_margin_left = _s(20)
	psb.content_margin_right = _s(20)
	psb.content_margin_top = _s(16)
	psb.content_margin_bottom = _s(16)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", _si(10))
	panel.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", _si(18))
	t.add_theme_color_override("font_color", _t("fg"))
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size = Vector2(_s(280), 0)
	v.add_child(t)
	var st := Label.new()
	st.text = subtitle
	st.add_theme_font_size_override("font_size", _si(14))
	st.add_theme_color_override("font_color", _t("dim"))
	st.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(st)
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", _si(10))
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btn_row)
	# Return the overlay; buttons go into btn_row (child 0 -> v -> btn_row).
	# We stash btn_row as metadata via a named lookup instead.
	overlay.set_meta("btn_row", btn_row)
	return overlay


func _dialog_button(label_text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label_text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(_s(120), _s(48))
	b.add_theme_font_size_override("font_size", _si(16))
	b.add_theme_color_override("font_color", _t("fg"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = _t("key")
	sb.set_corner_radius_all(_si(10))
	b.add_theme_stylebox_override("normal", sb)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = _t("key").darkened(0.15)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.pressed.connect(on_press)
	return b


func _dismiss_learn_dialog() -> void:
	if _learn_dialog != null and is_instance_valid(_learn_dialog):
		_learn_dialog.queue_free()
	_learn_dialog = null
	_pending_learn = ""
