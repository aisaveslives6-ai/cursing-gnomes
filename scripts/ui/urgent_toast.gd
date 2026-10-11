class_name UrgentToast
extends PanelContainer
## Cursing Gnomes — urgent non-blocking toast banner.
##
## PORT of fix79's #toast (showToast + TOAST_URGENT_RE, verbatim behavior):
##   - Urgent events (war declarations, attacks, disasters, leader deaths)
##     pop a single bottom-center toast. Non-urgent news is downgraded to
##     the Chronicle only — never the toast (HTML parity).
##   - One toast at a time: a new urgent story REPLACES the prior toast and
##     restarts the timer (HTML clearTimeout). Auto-hides after 2.6 s with
##     a 0.25 s fade (HTML #toast.show transition).
##   - HTML #toast had pointer-events:none — fully non-blocking. This port
##     keeps MOUSE_FILTER_IGNORE so the toast can never eat gameplay taps.
##   - ASCII-only text (iPhone tofu rule): headlines with emoji/glyphs are
##     sanitized before display.
##
## Wired by Hud: setup(bus) connects bus.gazette_story; refit() is called
## with the bottom clearance whenever the viewport chrome is repositioned.
## Zero per-frame cost when hidden (processing disabled while idle).

## HTML TOAST_URGENT_RE verbatim, minus the radioactive glyph (non-ASCII —
## can't render on iPhone; the "nuke" keyword covers the concept).
const URGENT_PATTERNS: Array[String] = [
	"declar\\w* war", "at war\\b", "shattered the peace", "open war",
	"war begins", "mass at the border", "under attack", "is attacking",
	"raid has begun", "siege", "invasion", "disaster", "giant ass",
	"cussing lizard", "count bastard", "rogue wizard", "wild mage",
	"earthquake", "volcano", "tornado", "meteor", "plague", "drought",
	"flood", "eruption", "nuke", "leader fallen",
	"commander.{0,24}(died|slain|fallen)", "assassinat", "hall destroyed",
]

## HTML parity: 2600 ms on screen, 0.25 s fade in/out.
const SHOW_SECONDS := 2.6
const FADE_SECONDS := 0.25
## HTML #toast: background rgba(14,11,8,0.92), 2px #8b6914 border,
## 10px radius, #f0e6c8 text, 1px black text-shadow, max-width 86vw.
const BG_COLOR := Color(0.055, 0.043, 0.031, 0.92)
const BORDER_COLOR := Color(0.545, 0.412, 0.078)
const TEXT_COLOR := Color(0.941, 0.902, 0.784)

static var _urgent_re: RegEx = null


static func _regex() -> RegEx:
	if _urgent_re == null:
		_urgent_re = RegEx.new()
		_urgent_re.compile("(?i)" + "|".join(URGENT_PATTERNS))
	return _urgent_re


## HTML showToast urgency: explicit urgent flag OR the urgency regex
## matched against the headline text.
static func is_urgent(headline: String, urgent: bool = false) -> bool:
	if urgent:
		return true
	if headline.is_empty():
		return false
	return _regex().search(headline) != null


## Strip non-ASCII so iPhone never renders tofu boxes (standing rule).
static func sanitize(text: String) -> String:
	var out := PackedStringArray()
	for i in text.length():
		var code := text.unicode_at(i)
		if code < 128:
			out.append(text.substr(i, 1))
		else:
			out.append(" ")
	return "".join(out).strip_edges()


var _label: Label = null
var _elapsed := 0.0
var _half_w := 400.0
var _clearance := 200.0
var _ui_scale := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	set_process(false)
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.set_border_width_all(2)
	sb.border_color = BORDER_COLOR
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", sb)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	margin.add_child(_label)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN


## Connects to the sim's Gazette story bus. Safe to call once.
func setup(bus: EventBus) -> void:
	if bus != null and not bus.gazette_story.is_connected(_on_story):
		bus.gazette_story.connect(_on_story)
	# Jeremy 2026-10-06: generic player toast channel (bus.toast) — sim
	# systems announce transient events here; show_toast sanitizes.
	if bus != null and not bus.toast.is_connected(show_toast):
		bus.toast.connect(show_toast)


## Reposition above the bottom chrome. clearance_px = distance from the
## viewport bottom edge to the toast's bottom edge (bar + tabs + margin).
## viewport_w_px caps the width at 86% (HTML max-width: 86vw).
func refit(clearance_px: float, viewport_w_px: float, ui_scale: float = 1.0) -> void:
	_clearance = clearance_px
	_ui_scale = ui_scale
	_half_w = minf(viewport_w_px * 0.43, 480.0 * ui_scale)
	_label.add_theme_font_size_override("font_size", maxi(1, int(round(20.0 * ui_scale))))
	_label.custom_minimum_size = Vector2(maxf(80.0, _half_w * 2.0 - 28.0), 0.0)
	_relayout()


func show_toast(text: String) -> void:
	var clean := sanitize(text)
	if clean.is_empty():
		return
	_label.text = clean
	_elapsed = 0.0
	modulate.a = 0.0
	visible = true
	_relayout()
	set_process(true)


func _relayout() -> void:
	_apply_offsets(0.0)


func _apply_offsets(rise: float) -> void:
	# Height from real content metrics so wrapped text never clips.
	# The slide-in rise goes through the offsets (not position: anchored
	# controls get position rewritten from anchors on relayout).
	var h := get_combined_minimum_size().y
	offset_left = -_half_w
	offset_right = _half_w
	offset_bottom = -_clearance + rise
	offset_top = -_clearance - maxf(h, 1.0) + rise


func _on_story(story: Dictionary) -> void:
	var headline := String(story.get("headline", ""))
	if is_urgent(headline, bool(story.get("urgent", false))):
		show_toast(headline)


func _process(delta: float) -> void:
	_elapsed += delta
	var a := 1.0
	var rise := 0.0
	if _elapsed < FADE_SECONDS:
		var p := _elapsed / FADE_SECONDS
		a = p
		# Gentle rise while fading in (HTML translateY 8px -> 0).
		rise = 8.0 * (1.0 - p)
	elif _elapsed >= SHOW_SECONDS:
		var t := (_elapsed - SHOW_SECONDS) / FADE_SECONDS
		a = 1.0 - t
	modulate.a = clampf(a, 0.0, 1.0)
	_apply_offsets(rise)
	if _elapsed >= SHOW_SECONDS + FADE_SECONDS:
		visible = false
		set_process(false)


## Test hook: is a toast currently on screen (mid fade-out counts).
func is_showing() -> bool:
	return visible
