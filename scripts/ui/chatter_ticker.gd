class_name ChatterTicker
extends PanelContainer
## Cursing Gnomes — "Overheard" subtitle ticker.
##
## Gives the world's voice back WITHOUT bubbles (Jeremy 2026-10-05:
## all speech/thought bubbles removed — they blocked the battle view).
## NPC chatter, AI director announcements, army stance shouts, ferry
## calls and hero dialogue ride bus.unit_said; the world feeds accepted
## lines here via Hud.push_chatter(). One slim subtitle line pinned
## above the bottom chrome — HUD chrome, never over units, never
## blocking taps (MOUSE_FILTER_IGNORE).
##
## Visual language mirrors UrgentToast: same parchment-on-dark styling,
## fade in/out, safe-area refit, ASCII-only text (iPhone tofu rule —
## sanitized through UrgentToast.sanitize). The speaker name renders in
## their faction color; system shouts ("Army") in gold.
## Zero per-frame cost when hidden (processing disabled while idle).

## Subtitles hold a beat longer than urgent toasts: a sentence to read.
const SHOW_SECONDS := 3.4
const FADE_SECONDS := 0.3
const BG_COLOR := Color(0.055, 0.043, 0.031, 0.88)
const BORDER_COLOR := Color(0.545, 0.412, 0.078)
const TEXT_COLOR := Color(0.941, 0.902, 0.784)
const SYSTEM_COLOR := Color(0.98, 0.80, 0.35)


var _rich: RichTextLabel = null
var _elapsed := 0.0
var _half_w := 400.0
var _clearance := 200.0
var _ui_scale := 1.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_COLOR
	sb.border_color = BORDER_COLOR
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	add_theme_stylebox_override("panel", sb)
	_rich = RichTextLabel.new()
	_rich.bbcode_enabled = true
	_rich.scroll_active = false
	_rich.fit_content = true
	_rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rich.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rich.add_theme_color_override("default_color", TEXT_COLOR)
	_rich.add_theme_constant_override("line_spacing", 0)
	add_child(_rich)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	set_process(false)


## Reposition above the bottom chrome. clearance_px = distance from the
## viewport bottom edge to the ticker's bottom edge — pass the urgent
## toast's clearance plus headroom so the two never overlap.
## viewport_w_px caps the width at 86% (HTML #toast parity).
func refit(clearance_px: float, viewport_w_px: float, ui_scale: float = 1.0) -> void:
	_clearance = clearance_px
	_ui_scale = ui_scale
	_half_w = minf(viewport_w_px * 0.43, 480.0 * ui_scale)
	_rich.add_theme_font_size_override("normal_font_size", maxi(1, int(round(17.0 * ui_scale))))
	_rich.add_theme_font_size_override("bold_font_size", maxi(1, int(round(17.0 * ui_scale))))
	_rich.custom_minimum_size = Vector2(maxf(80.0, _half_w * 2.0 - 28.0), 0.0)
	_relayout()


## Show one overheard line. speaker may be "" (anonymous); color is the
## speaker's faction color (or SYSTEM_COLOR for army/system shouts).
func push(speaker: String, color: Color, text: String) -> void:
	var clean := UrgentToast.sanitize(text)
	# Strip square brackets: bbcode would try to parse them as tags.
	clean = clean.replace("[", "").replace("]", "")
	if clean.is_empty():
		return
	var html := ""
	if not speaker.strip_edges().is_empty():
		var c := color if color.a > 0.01 else SYSTEM_COLOR
		var sname := speaker.strip_edges().replace("[", "").replace("]", "")
		html = "[color=#%s][b]%s:[/b][/color] " % [_hex(c), sname]
	_rich.text = html + clean
	_elapsed = 0.0
	modulate.a = 0.0
	visible = true
	_relayout()
	set_process(true)


func _hex(c: Color) -> String:
	return "%02x%02x%02x" % [int(round(c.r * 255.0)), int(round(c.g * 255.0)), int(round(c.b * 255.0))]


func _relayout() -> void:
	var h := get_combined_minimum_size().y
	offset_left = -_half_w
	offset_right = _half_w
	offset_bottom = -_clearance
	offset_top = -_clearance - maxf(h, 1.0)


func _process(delta: float) -> void:
	_elapsed += delta
	var a := 1.0
	if _elapsed < FADE_SECONDS:
		a = _elapsed / FADE_SECONDS
	elif _elapsed >= SHOW_SECONDS:
		var t := (_elapsed - SHOW_SECONDS) / FADE_SECONDS
		a = 1.0 - t
	modulate.a = clampf(a, 0.0, 1.0)
	if _elapsed >= SHOW_SECONDS + FADE_SECONDS:
		visible = false
		set_process(false)


## Test hook: is a subtitle currently on screen (mid fade-out counts).
func is_showing() -> bool:
	return visible


## Test hook: the exact bbcode the ticker is displaying.
func shown_bbcode() -> String:
	return _rich.text if _rich != null else ""
