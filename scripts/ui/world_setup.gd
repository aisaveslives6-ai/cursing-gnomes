class_name WorldSetupScreen
extends CanvasLayer
## Cursing Gnomes — "Forge Your World" setup screen.
##
## HTML parity (screen-worldsetup, fix79): title, desc, World type (6),
## World size (4, mobile-locked with a "Huge needs a desktop" lockpop +
## GOT IT), World shaping (water / forest / resources / starting stock,
## 3 choices each), seeded minimap preview (the REAL terrain — same
## MapGen.generate + seed the world boots with), BACK / REROLL /
## START GAME action bar.
##
## Jeremy 2026-10-03: World type and World size use the faction-picker
## 3D trading-card carousel treatment — generated landscape art per
## world type (assets/ui/worldgen/type_<key>.webp) and parchment map
## art per size (size_<key>.webp). Drag to spin, release snaps,
## tap a card to bring it front. No emoji — plain text labels only
## (Jeremy 2026-10-02: tofu-box font issue stays untouched).
##
## Emits world_confirmed(type, size_key, opts, seed); the host (main.gd)
## boots the world with those params.


signal world_confirmed(wtype: String, size_key: String, opts: Dictionary,
	seed: int)
signal back_pressed


const TYPES := {
	"continents": {
		"name": "Continents",
		"desc": "Classic mixed geography — meadows, deepwoods, lakes and crags.",
		"color": Color(0.35, 0.65, 0.30),  # Green
	},
	"archipelago": {
		"name": "Archipelago",
		"desc": "Scattered isles and extra lakes — boats, bridges and trade matter.",
		"color": Color(0.25, 0.55, 0.85),  # Ocean blue
	},
	"highlands": {
		"name": "Highlands",
		"desc": "Mountain ranges and chokepoints — rocky, defensible, mine-rich.",
		"color": Color(0.55, 0.50, 0.45),  # Stone gray
	},
	"wasteland": {
		"name": "Wasteland",
		"desc": "Arid desert — scarce water, little timber, harsh living.",
		"color": Color(0.85, 0.65, 0.25),  # Sand orange
	},
	"frozen": {
		"name": "Frozen",
		"desc": "Snow and tundra — beautiful, slow, unforgiving.",
		"color": Color(0.70, 0.85, 0.95),  # Ice blue
	},
	"wilds": {
		"name": "Wilds",
		"desc": "Dense forest primeval — timber everywhere, ambush country.",
		"color": Color(0.20, 0.50, 0.25),  # Deep forest
	},
}
const TYPE_ORDER := ["continents", "archipelago", "highlands", "wasteland",
	"frozen", "wilds"]

const SIZES := {
	"mobile": {"name": "Mobile", "sub": "8k x 6k",
		"desc": "Small map for phones. Fast and stable."},
	"normal": {"name": "Normal", "sub": "16k x 12k",
		"desc": "The classic map."},
	"large": {"name": "Large", "sub": "24k x 18k",
		"desc": "2.25x the land. Longer campaigns."},
	"huge": {"name": "Huge", "sub": "32k x 24k",
		"desc": "4x the land. Epic campaigns."},
}
const SIZE_ORDER := ["mobile", "normal", "large", "huge"]

## World shaping options (CGWSEL_OPTDEFS parity): key -> label + 3 choices.
const OPT_DEFS := [
	{"key": "water", "label": "Water level", "choices": [
		{"k": "low", "name": "Low", "desc": "Fewer lakes, more land"},
		{"k": "normal", "name": "Normal", "desc": "Classic waters"},
		{"k": "high", "name": "High", "desc": "Lake country"}]},
	{"key": "forest", "label": "Forests", "choices": [
		{"k": "sparse", "name": "Sparse", "desc": "Little timber"},
		{"k": "normal", "name": "Normal", "desc": "Classic woods"},
		{"k": "dense", "name": "Dense", "desc": "Timber everywhere"}]},
	{"key": "resources", "label": "Resources", "choices": [
		{"k": "scarce", "name": "Scarce", "desc": "Few mines"},
		{"k": "normal", "name": "Normal", "desc": "Classic mines"},
		{"k": "abundant", "name": "Abundant", "desc": "Mine-rich"}]},
	{"key": "start", "label": "Starting stock", "choices": [
		{"k": "poor", "name": "Poor", "desc": "Lean start"},
		{"k": "normal", "name": "Normal", "desc": "Classic stock"},
		{"k": "rich", "name": "Rich", "desc": "Fat coffers"}]},
]
const OPT_DEFAULTS := {"water": "normal", "forest": "normal",
	"resources": "normal", "start": "normal"}

# (Preview base colors retired 2026-10-03: the preview now uses
# MapGen's own baked terrain image, which is far more detailed.)

var _wtype := "continents"
var _size := "normal"
var _opts := {}
var _seed := 0
var _factions: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
var _player_faction := "gnomes"

var _preview_tex: TextureRect
var _seed_label: Label
var _type_desc: Label
var _size_note: Label
var _busy := false
var _preview_debounce := 0.0
const PREVIEW_DEBOUNCE_TIME := 0.5  # Wait 0.5s after last change before baking

## Rotating gameplay tips (Jeremy 2026-10-08: "Tips?"). The title-screen tips
## band was pulled for the SC1-style clean menu ("no clutter"), so the lines
## live on here instead — a thin muted-gold line under the BACK/REROLL/START
## GAME bar, rotating every few seconds. Text comes from
## MainMenu.random_tip(); ASCII-only per the iPhone tofu rule.
var _tip_label: Label
var _tip_timer := 0.0
const TIP_ROTATE_SECONDS := 6.0

## 3D card carousels (Jeremy 2026-10-03): world type + map size get the
## faction-picker carousel treatment. State dicts; same math as
## main_menu.gd's _carousel3d_* (elliptical track, depth scaling,
## drag-to-spin, release-snaps, tap-selects).
var _type_car: Dictionary = {}
var _size_car: Dictionary = {}
## Shaping option buttons, "key:val" -> Button (in-place style updates).
var _opt_buttons: Dictionary = {}

## UI scale: canvas units per CSS px (same formula as MainMenu._compute_ui_scale),
## with a readability boost — Jeremy 2026-10-02: "every ui is too small".
var _ui_scale := 1.0


## Scaled px: multiply a design-px size by the UI scale.
func _s(v: float) -> float:
	return v * _ui_scale


func _si(v: float) -> int:
	return maxi(1, int(round(float(v) * _ui_scale)))


## Canvas units per design px — fixed 2.5x for iPhone 17 (Jeremy 2026-10-04:
## no viewport math, no JS hacks, just a constant like the other UI files).
func _compute_scale(vp: Vector2) -> float:
	return 2.5


func _ready() -> void:
	_opts = OPT_DEFAULTS.duplicate()
	_seed = _roll_seed()
	# HTML default: mobile size on mobile, normal otherwise.
	if _is_mobile():
		_size = "mobile"
	_build()


static func _roll_seed() -> int:
	return int(randf() * 4294967295.0) + 1


## Configure from the menu flow (faction screen hands these over).
func setup(factions: Array[String], player_faction: String) -> void:
	_factions = factions.duplicate()
	_player_faction = player_faction
	if not _factions.has(_player_faction):
		_player_faction = _factions[0] if not _factions.is_empty() else "gnomes"


static func _is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") \
		or OS.has_feature("web_ios")


## iPhone safe-area insets as Vector4(top, bottom, left, right) in canvas
## units. Uses DisplayServer.get_display_safe_area() for the REAL device
## safe area (Jeremy 2026-10-06: the old hardcoded portrait/landscape
## guesses diverged from what the OS reports on newer devices). Desktop
## returns zero insets; headless/no-viewport falls back to conservative
## hardcoded values matching hud.gd's _safe_insets().
func _safe_insets() -> Vector4:
	var vp := get_viewport()
	if vp == null:
		return Vector4(180.0, 100.0, 20.0, 20.0)
	var vsz := vp.get_visible_rect().size
	var is_desktop := not DisplayServer.is_touchscreen_available() \
		and vsz.x >= 1024.0 and vsz.y >= 600.0
	if is_desktop:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0 and safe.size.y > 0:
		# Jeremy 2026-10-08 (graphics-hourly): the OS rect is in WINDOW units
		# (CSS px on web), but vsz is in stretch-expanded VIEWPORT units — the
		# old code mixed them and then divided by a constant, producing
		# garbage insets. Convert the rect to viewport units first via
		# window_get_size(), which shares the safe rect's coordinate space.
		var winsz := Vector2(DisplayServer.window_get_size())
		if winsz.x > 0.0 and winsz.y > 0.0:
			var k := vsz / winsz
			var top := safe.position.y * k.y
			var left := safe.position.x * k.x
			var bottom := vsz.y - (safe.position.y + safe.size.y) * k.y
			var right := vsz.x - (safe.position.x + safe.size.x) * k.x
			return Vector4(maxf(top, 0.0), maxf(bottom, 0.0), maxf(left, 0.0), maxf(right, 0.0))
	if vsz.x >= vsz.y:
		return Vector4(20.0, 60.0, 120.0, 120.0)
	return Vector4(220.0, 120.0, 20.0, 20.0)


## HTML parity: returns a sanitized opts dict (unknown values -> normal).
static func sanitize_opts(o) -> Dictionary:
	var out := OPT_DEFAULTS.duplicate()
	if o is Dictionary:
		for d in OPT_DEFS:
			var k: String = d["key"]
			var vals := []
			for c in d["choices"]:
				vals.append(c["k"])
			if str(o.get(k, "")) in vals:
				out[k] = str(o[k])
	return out


# --------------------------------------------------------------------- build

func _build() -> void:
	var vp0: Vector2 = get_viewport().get_visible_rect().size
	_ui_scale = _compute_scale(vp0)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Jeremy 2026-10-04: the world gen screen is long — always show the
	# scrollbar on the right so it's obvious the screen scrolls.
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Safe areas: OS-reported via _safe_insets() so content and the
	# scrollbar stay clear of the Dynamic Island, home indicator, and
	# rounded corners on the real device (hud.gd uses the same pattern).
	var insets := _safe_insets()
	scroll.offset_top = insets.x
	scroll.offset_bottom = -insets.y
	scroll.offset_left = insets.z
	scroll.offset_right = -insets.w
	root.add_child(scroll)
	# Scrollbar gutter (Jeremy 2026-10-04): the bar must never overlap
	# content. Fixed-width gold bar; the content column below is narrowed
	# by exactly (bar width + padding) so nothing hides under it.
	var sb_w := _si(16)
	var vsb := scroll.get_v_scroll_bar()
	vsb.custom_minimum_size = Vector2(float(sb_w), 0.0)
	var sb_track := StyleBoxFlat.new()
	sb_track.bg_color = Color(0.0, 0.0, 0.0, 0.45)
	sb_track.set_corner_radius_all(_si(6))
	vsb.add_theme_stylebox_override("scroll", sb_track)
	var sb_grab := StyleBoxFlat.new()
	sb_grab.bg_color = Color(0.788, 0.635, 0.153, 0.95)
	sb_grab.set_corner_radius_all(_si(6))
	vsb.add_theme_stylebox_override("grabber_area", sb_grab)
	var sb_grab_hi := sb_grab.duplicate() as StyleBoxFlat
	sb_grab_hi.bg_color = Color(1.0, 0.835, 0.310, 1.0)
	vsb.add_theme_stylebox_override("grabber_area_highlight", sb_grab_hi)
	# Outer box: at least viewport-sized (short content centers), grows
	# taller when content overflows so the ScrollContainer can scroll.
	# (The old CenterContainer never grew — tall content overflowed with
	# no way to reach it, the same bug the faction screen had.)
	var outer := VBoxContainer.new()
	outer.custom_minimum_size = Vector2(
		vp0.x - insets.z - insets.w, vp0.y - insets.x - insets.y)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(outer)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(
		minf(vp0.x * 0.94, _s(560.0)) - float(sb_w) - _s(8.0), 0.0)
	v.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", _si(10))
	outer.add_child(v)

	v.add_child(_h1("Forge Your World"))
	var desc := _lbl("Pick the land, pick the size, shape the wilds — "
		+ "the preview at the bottom is the real terrain. "
		+ "Reroll until it sings, then start.", 15,
		Color(0.831, 0.769, 0.659))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(desc)

	v.add_child(_sec("World type"))
	# Jeremy 2026-10-03: 3D card carousel with generated art per type.
	_type_car = _car_make(TYPE_ORDER, _world_type_card, "type")
	v.add_child(_type_car["view"] as Control)
	_car_snap_to(_type_car, _wtype, true)
	_type_desc = _lbl(String(TYPES[_wtype]["desc"]), 13,
		Color(0.796, 0.725, 0.541))
	_type_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_type_desc)

	v.add_child(_sec("World size"))
	# Jeremy 2026-10-03: 3D card carousel with generated parchment art.
	_size_car = _car_make(SIZE_ORDER, _map_size_card, "size")
	v.add_child(_size_car["view"] as Control)
	_car_snap_to(_size_car, _size, true)
	_size_note = _lbl(_size_note_text(), 12, Color(0.627, 0.565, 0.439))
	_size_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_size_note)

	v.add_child(_sec("World shaping"))
	for d in OPT_DEFS:
		v.add_child(_opt_group(d))
	var note := _lbl("Terrain options reshape the land itself — "
		+ "the preview stays honest.", 12, Color(0.627, 0.565, 0.439))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)

	v.add_child(_sec("Preview"))
	_seed_label = _lbl("", 13, Color(0.85, 0.75, 0.50))
	v.add_child(_seed_label)

	# Preview in a gold frame.
	var prev_frame := PanelContainer.new()
	var frame_sb := StyleBoxFlat.new()
	frame_sb.bg_color = Color(0.10, 0.07, 0.05)
	frame_sb.set_border_width_all(4)
	frame_sb.border_color = Color(0.788, 0.635, 0.153)
	frame_sb.set_corner_radius_all(10)
	frame_sb.shadow_size = 8
	frame_sb.shadow_color = Color(0, 0, 0, 0.5)
	prev_frame.add_theme_stylebox_override("panel", frame_sb)
	prev_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(prev_frame)
	_preview_tex = TextureRect.new()
	# Jeremy 2026-10-04: preview still too zoomed. Force the full map visible:
	# smaller rect, FIT dimensions so the 512x512 bake fits entirely.
	var prev_w := minf(vp0.x * 0.85, _s(420.0))
	var prev_sz := Vector2(prev_w, prev_w)  # square — map is 512x512
	_preview_tex.custom_minimum_size = prev_sz
	_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	prev_frame.add_child(_preview_tex)
	var pnote := _lbl("Minimap preview — the real terrain: mountains, rivers, "
		+ "waterfalls, forests, mines and faction start rings.",
		12, Color(0.627, 0.565, 0.439))
	pnote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(pnote)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", _si(10))
	v.add_child(bar)
	var b_back := _btn("< BACK", false)
	b_back.pressed.connect(func() -> void: back_pressed.emit())
	bar.add_child(b_back)
	var b_reroll := _btn("REROLL", false)
	b_reroll.pressed.connect(_on_reroll)
	bar.add_child(b_reroll)
	var b_start := _btn("START GAME", true)
	b_start.pressed.connect(_on_start)
	bar.add_child(b_start)

	# Jeremy 2026-10-08 ("Tips?"): rotating gameplay tips line. Thin and
	# quiet — muted gold, wrapped, under the action bar; never touches the
	# SC1 title screen's no-clutter rule.
	_tip_label = _lbl(MainMenu.random_tip(), 13, Color(0.820, 0.749, 0.553))
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_tip_label)
	_tip_timer = TIP_ROTATE_SECONDS

	_refresh_preview()


func _h1(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _si(48))
	l.add_theme_color_override("font_color", Color(1.0, 0.87, 0.35))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


func _lbl(t: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", _si(size))
	l.add_theme_color_override("font_color", color)
	return l


func _sec(t: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", _si(10))
	var line1 := ColorRect.new()
	line1.color = Color(0.788, 0.635, 0.153, 0.5)
	line1.custom_minimum_size = Vector2(_s(60), 2)
	line1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line1)
	var l := _lbl(t, 26, Color(1.0, 0.87, 0.35))
	row.add_child(l)
	var line2 := ColorRect.new()
	line2.color = Color(0.788, 0.635, 0.153, 0.5)
	line2.custom_minimum_size = Vector2(_s(60), 2)
	line2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(line2)
	return row


func _opt_card(label_text: String, selected: bool, accent: Color = Color(0.788, 0.635, 0.153)) -> Button:
	var b := Button.new()
	b.text = label_text
	b.toggle_mode = true
	# Jeremy 2026-10-03: fixed width for FlowContainer wrapping (2 per row on phone).
	# EXPAND_FILL breaks FlowContainer wrapping and causes horizontal overflow.
	b.custom_minimum_size = Vector2(_s(160), _s(96))
	b.clip_text = true
	b.add_theme_font_size_override("font_size", _si(24))
	b.set_pressed_no_signal(selected)
	_style_opt(b, selected, accent)
	return b


func _style_opt(b: Button, selected: bool, accent: Color = Color(0.788, 0.635, 0.153)) -> void:
	var sb := StyleBoxFlat.new()
	# Selected: accent-tinted background; unselected: dark.
	if selected:
		sb.bg_color = Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35)
	else:
		sb.bg_color = Color(0.165, 0.110, 0.071)
	sb.set_border_width_all(3 if selected else 2)
	sb.border_color = accent if selected else Color(0.361, 0.263, 0.157)
	sb.set_corner_radius_all(8)
	# Subtle shadow for depth.
	sb.shadow_size = 4 if selected else 2
	sb.shadow_color = Color(0, 0, 0, 0.4)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("pressed", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25) if not selected else sb.bg_color
	b.add_theme_stylebox_override("hover", sb_h)
	# Selected text pops.
	if selected:
		b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.80))


func _opt_group(d: Dictionary) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _si(4))
	var head := _lbl(String(d["label"]), 22, Color(1.0, 0.835, 0.310))
	vb.add_child(head)
	# Jeremy 2026-10-03: flow container so the 3 x 170px cards wrap on phone
	# widths — 510px overflows a 390px iPhone in a plain HBoxContainer.
	var row := HFlowContainer.new()
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", _si(6))
	row.add_theme_constant_override("v_separation", _si(6))
	vb.add_child(row)
	var key: String = d["key"]
	for c in d["choices"]:
		var b := _opt_card(String(c["name"]), _opts.get(key) == c["k"])
		b.custom_minimum_size = Vector2(_s(170), _s(88))
		b.tooltip_text = String(c["desc"])
		b.pressed.connect(_on_opt.bind(key, String(c["k"])))
		_opt_buttons["%s:%s" % [key, String(c["k"])]] = b
		row.add_child(b)
	return vb


func _btn(t: String, primary: bool) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, _s(96))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", _si(28))
	var sb := StyleBoxFlat.new()
	if primary:
		# START GAME: gold gradient feel, bold.
		sb.bg_color = Color(0.45, 0.32, 0.12)
		b.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	else:
		sb.bg_color = Color(0.20, 0.14, 0.09)
	sb.set_border_width_all(4 if primary else 2)
	sb.border_color = Color(0.95, 0.78, 0.25) if primary else Color(0.60, 0.48, 0.20)
	sb.set_corner_radius_all(10)
	sb.shadow_size = 6 if primary else 3
	sb.shadow_color = Color(0, 0, 0, 0.5)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.55, 0.40, 0.15) if primary else Color(0.26, 0.18, 0.11)
	b.add_theme_stylebox_override("hover", sb_h)
	b.add_theme_stylebox_override("pressed", sb_h)
	return b


# --------------------------------------------- 3D card carousel
# Same elliptical-track math as main_menu.gd's _carousel3d_* (Jeremy
# approved that carousel on iPhone): cards ride a track, front card is
# full-size, back cards shrink and dim. Drag to spin, release snaps to
# the nearest card, tap a card to bring it front. State lives in a
# Dictionary ("kind" = "type" | "size") so both carousels share code.

const _CAR_CARD_W := 320.0
const _CAR_CARD_H := 232.0


## Build a carousel state + view for the given ids.
func _car_make(ids: Array, builder: Callable, kind: String) -> Dictionary:
	var view := Control.new()
	view.custom_minimum_size = Vector2(0, _s(400))
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	var st := {"kind": kind, "view": view, "cards": [], "angle": 0.0,
		"target": 0.0, "dragging": false, "pressing": false,
		"press_x": 0.0, "press_y": 0.0, "last_x": 0.0,
		"moved": false, "sel": ""}
	for id in ids:
		var card: Button = builder.call(String(id))
		view.add_child(card)
		# Deterministic size outside containers (mirrors the faction
		# carousel): plain-Control children don't auto-size.
		card.size = Vector2(_s(_CAR_CARD_W), _s(_CAR_CARD_H))
		card.pivot_offset = card.size * 0.5
		st["cards"].append({"id": String(id), "node": card})
	view.gui_input.connect(_on_car_input.bind(st))
	view.resized.connect(_car_layout.bind(st))
	return st


## Ease rotation toward the target, then re-layout every frame.
func _process(delta: float) -> void:
	# Jeremy 2026-10-03: preview was laggy from regenerating full map on every
	# change. Debounce: wait 0.8s after last change before baking.
	if _preview_debounce > 0.0:
		_preview_debounce -= delta
		if _preview_debounce <= 0.0:
			_do_refresh_preview()
	# 2026-10-04: carousels snap to the nearest card on release via target —
	# the ease needs a per-frame tick or the view never settles (the tick
	# existed but nothing called it, so drags ended off-center).
	if not _type_car.is_empty():
		_car_tick(_type_car, delta)
	if not _size_car.is_empty():
		_car_tick(_size_car, delta)
	# Jeremy 2026-10-08: rotate the tips line every few seconds.
	if is_instance_valid(_tip_label):
		_tip_timer -= delta
		if _tip_timer <= 0.0:
			_tip_timer = TIP_ROTATE_SECONDS
			_rotate_tip()


## Pick a fresh tips line; never show the same tip twice in a row.
func _rotate_tip() -> void:
	if not is_instance_valid(_tip_label):
		return
	var cur := _tip_label.text
	var nxt := MainMenu.random_tip()
	var guard := 0
	while nxt == cur and guard < 8:
		nxt = MainMenu.random_tip()
		guard += 1
	_tip_label.text = nxt


func _car_tick(st: Dictionary, delta: float) -> void:
	if st.is_empty():
		return
	var view: Control = st["view"]
	if (st["cards"] as Array).is_empty() or not is_instance_valid(view):
		return
	if not bool(st["dragging"]):
		var diff: float = float(st["target"]) - float(st["angle"])
		if absf(diff) > 0.0005:
			st["angle"] = float(st["angle"]) \
				+ diff * minf(1.0, delta * 10.0)
		else:
			st["angle"] = float(st["target"])
	_car_layout(st)


## Carousel track radius in px (half the view width, clamped).
func _car_radius(st: Dictionary) -> float:
	var view: Control = st["view"]
	if not is_instance_valid(view):
		return 200.0
	return clampf(view.size.x * 0.38, 120.0, 320.0)


## Layout every card on the elliptical track for the current angle.
func _car_layout(st: Dictionary) -> void:
	var view: Control = st["view"]
	var cards: Array = st["cards"]
	if not is_instance_valid(view) or cards.is_empty():
		return
	var n: int = cards.size()
	var cx: float = view.size.x * 0.5
	var cy: float = view.size.y * 0.52
	var rx: float = _car_radius(st)
	var ry: float = rx * 0.22
	var step: float = TAU / float(n)
	var angle: float = float(st["angle"])
	for i in n:
		var entry: Dictionary = cards[i]
		var card: Button = entry["node"]
		if not is_instance_valid(card):
			continue
		var a: float = angle + float(i) * step
		# Depth: cos(a) = 1 at front, -1 at back.
		var depth: float = 0.5 + 0.5 * cos(a)
		var px: float = cx + rx * sin(a)
		var py: float = cy + ry * sin(a) * 0.5 \
			- (1.0 - depth) * ry * 0.6
		var s: float = 0.55 + 0.45 * depth
		card.scale = Vector2(s, s)
		card.position = Vector2(px, py) - card.size * s * 0.5
		# Back cards dim and fade; front card pops.
		var dim: float = 0.45 + 0.55 * depth
		card.modulate = Color(dim, dim, dim, 0.55 + 0.45 * depth)
		# z_index: front card on top.
		card.z_index = int(depth * 100.0)
		# Pivot at center so scale grows outward evenly.
		card.pivot_offset = card.size * 0.5
		# Selected card gets the gold "pressed" frame.
		card.set_pressed_no_signal(str(entry["id"]) == str(st["sel"]))


## Carousel input: drag to spin, release snaps, tap selects.
## Jeremy 2026-10-03: carousels were stealing VERTICAL scrolls — the menu
## sits in a ScrollContainer and every drag started spinning cards. The
## gesture is now direction-locked: a drag only engages the carousel when it
## is clearly horizontal (past touch slop AND wider than it is tall). A
## vertical-dominant drag is left un-accepted so it bubbles up to the
## ScrollContainer and the menu scrolls instead.
const _CAR_SLOP := 12.0

func _on_car_input(event: InputEvent, st: Dictionary) -> void:
	var view: Control = st["view"]
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				st["pressing"] = true
				st["dragging"] = false
				st["moved"] = false
				st["press_x"] = mb.position.x
				st["press_y"] = mb.position.y
				st["last_x"] = mb.position.x
				# Not accepted yet: wait for the direction lock to decide.
			else:
				if bool(st["dragging"]):
					# A real drag: snap to the nearest card. A clean tap
					# never arrives here with dragging set (_car_try_lock
					# only engages dragging together with moved), and
					# _car_tap_at already snapped via _car_snap_to, so no
					# tap work belongs on this branch.
					_car_snap_nearest(st)
					view.accept_event()
				elif bool(st["pressing"]):
					# Clean tap — the scroll container never took over.
					_car_tap_at(st, mb.position)
					view.accept_event()
				st["pressing"] = false
				st["dragging"] = false
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if bool(st["pressing"]) and not bool(st["dragging"]):
			if _car_try_lock(st, mm.position):
				_car_spin_by(st, mm.position.x - float(st["last_x"]))
				st["last_x"] = mm.position.x
				st["moved"] = true
				view.accept_event()
			# Undecided or vertical: leave un-accepted so a vertical drag
			# keeps bubbling to the ScrollContainer.
		elif bool(st["dragging"]):
			_car_spin_by(st, mm.position.x - float(st["last_x"]))
			st["last_x"] = mm.position.x
			st["moved"] = true
			view.accept_event()
	elif event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			st["pressing"] = true
			st["dragging"] = false
			st["moved"] = false
			st["press_x"] = te.position.x
			st["press_y"] = te.position.y
			st["last_x"] = te.position.x
		else:
			if bool(st["dragging"]):
				# A real drag: snap to the nearest card. A clean tap
				# never arrives here with dragging set (_car_try_lock
				# only engages dragging together with moved), and
				# _car_tap_at already snapped via _car_snap_to, so no
				# tap work belongs on this branch.
				_car_snap_nearest(st)
				view.accept_event()
			elif bool(st["pressing"]):
				_car_tap_at(st, te.position)
				view.accept_event()
			st["pressing"] = false
			st["dragging"] = false
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if bool(st["pressing"]) and not bool(st["dragging"]):
			if _car_try_lock(st, sd.position):
				_car_spin_by(st, sd.position.x - float(st["last_x"]))
				st["last_x"] = sd.position.x
				st["moved"] = true
				view.accept_event()
		elif bool(st["dragging"]):
			_car_spin_by(st, sd.position.x - float(st["last_x"]))
			st["last_x"] = sd.position.x
			st["moved"] = true
			view.accept_event()


## Direction lock: returns true once the in-progress press is clearly a
## horizontal drag (engages the carousel). Returns false while undecided.
## If the drag is clearly vertical, the press is handed back to the
## ScrollContainer (pressing=false) and the event stays un-accepted.
func _car_try_lock(st: Dictionary, pos: Vector2) -> bool:
	var dx: float = pos.x - float(st["press_x"])
	var dy: float = pos.y - float(st["press_y"])
	if absf(dx) > _CAR_SLOP and absf(dx) > absf(dy):
		st["dragging"] = true
		return true
	if absf(dy) > _CAR_SLOP and absf(dy) >= absf(dx):
		st["pressing"] = false
	return false


## Spin the carousel by a horizontal pixel delta.
func _car_spin_by(st: Dictionary, dx: float) -> void:
	st["angle"] = float(st["angle"]) + dx / _car_radius(st)
	st["target"] = float(st["angle"])
	_car_layout(st)


## Snap rotation so the nearest card lands front-center; the card now
## at front becomes the selection.
func _car_snap_nearest(st: Dictionary) -> void:
	var cards: Array = st["cards"]
	var n: int = cards.size()
	if n == 0:
		return
	var step: float = TAU / float(n)
	# Front-center means card angle a = 0 (mod TAU).
	var k: float = round(float(st["angle"]) / step)
	st["target"] = k * step
	var front_idx: int = int(posmod(-k, n))
	if front_idx >= 0 and front_idx < n:
		_car_apply(st, str(cards[front_idx]["id"]))


## Snap directly to an id (used on open and on programmatic select).
func _car_snap_to(st: Dictionary, id: String, instant := false) -> void:
	var cards: Array = st.get("cards", [])
	var idx := -1
	for i in cards.size():
		if str(cards[i]["id"]) == id:
			idx = i
			break
	if idx < 0:
		return
	var step: float = TAU / float(cards.size())
	st["target"] = -float(idx) * step
	st["angle"] = st["target"]  # Jeremy 2026-10-03: instant, no animation lag
	st["sel"] = id
	_car_layout(st)


## Tap (no drag): pick the front-most card under the touch point.
func _car_tap_at(st: Dictionary, pos: Vector2) -> void:
	var cards: Array = st["cards"]
	var n: int = cards.size()
	var step: float = TAU / float(n) if n > 0 else TAU
	var best_id := ""
	var best_depth := -1.0
	var angle: float = float(st["angle"])
	for i in n:
		var entry: Dictionary = cards[i]
		var card: Button = entry["node"]
		if not is_instance_valid(card):
			continue
		# Card rect in carousel space (position is top-left, size scaled).
		var rect := Rect2(card.position, card.size * card.scale)
		if rect.has_point(pos):
			var a: float = angle + float(i) * step
			var depth: float = 0.5 + 0.5 * cos(a)
			if depth > best_depth:
				best_depth = depth
				best_id = str(entry["id"])
	if best_id != "":
		_car_apply(st, best_id)
		_car_snap_to(st, best_id)


## Apply a carousel selection to game state: type/size value, the desc
## label under the carousel, and a re-bake of the honest preview.
func _car_apply(st: Dictionary, id: String) -> void:
	st["sel"] = id
	if str(st["kind"]) == "type":
		_wtype = id
		if is_instance_valid(_type_desc):
			_type_desc.text = String(TYPES[id]["desc"])
	else:
		_size = id
		if is_instance_valid(_size_note):
			_size_note.text = _size_note_text()
	_refresh_preview()


# -------------------------------------------- carousel card art

## World-type card: generated landscape art + name banner.
func _world_type_card(k: String) -> Button:
	var d: Dictionary = TYPES[k]
	var accent: Color = d.get("color", Color(0.788, 0.635, 0.153))
	return _gen_card("type_%s.webp" % k, String(d["name"]), accent)


## Map-size card: generated parchment-map art + name/dims banner.
func _map_size_card(k: String) -> Button:
	var d: Dictionary = SIZES[k]
	var title := "%s  ·  %s" % [String(d["name"]), String(d["sub"])]
	return _gen_card("size_%s.webp" % k, title,
		Color(0.788, 0.635, 0.153))


## One landscape trading card: full-bleed generated art, name banner on
## top. The art has no baked-in text, so Godot overlays the label
## (same approach as the faction trading cards — generated images
## can't be trusted with lettering).
func _gen_card(art_file: String, title: String, accent: Color) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.text = ""
	b.focus_mode = Control.FOCUS_NONE
	# The carousel view handles all input (drag/spin/tap).
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.custom_minimum_size = Vector2(_s(_CAR_CARD_W), _s(_CAR_CARD_H))
	# Card frame: subtle dark border; selected card gets gold.
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(0.05, 0.04, 0.03, 1.0)
	frame.set_border_width_all(_si(2))
	frame.border_color = Color(0.2, 0.15, 0.1)
	frame.set_corner_radius_all(_si(10))
	frame.shadow_color = Color(0, 0, 0, 0.65)
	frame.shadow_size = _si(14)
	b.add_theme_stylebox_override("normal", frame)
	var frame_sel := frame.duplicate() as StyleBoxFlat
	frame_sel.border_color = accent
	frame_sel.set_border_width_all(_si(4))
	b.add_theme_stylebox_override("pressed", frame_sel)
	b.add_theme_stylebox_override("hover", frame)
	b.add_theme_stylebox_override("focus", frame_sel)
	# Art full-bleed.
	var art := TextureRect.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var tex := load("res://assets/ui/worldgen/%s" % art_file) as Texture2D
	if tex != null:
		art.texture = tex
	b.add_child(art)
	# Name banner (top, semi-transparent dark).
	var name_bg := ColorRect.new()
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_bg.color = Color(0, 0, 0, 0.55)
	name_bg.set_anchors_preset(Control.PRESET_TOP_WIDE)
	name_bg.offset_bottom = _s(44)
	b.add_child(name_bg)
	var nm := _lbl(title, 20, accent)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.set_anchors_preset(Control.PRESET_TOP_WIDE)
	nm.offset_bottom = _s(44)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	b.add_child(nm)
	return b


# ------------------------------------------------------------------ handlers

## World type chosen (carousel tap/snap or programmatic). Updates the
## desc, spins the carousel to the card, re-bakes the honest preview.
func _on_type(k: String) -> void:
	if not TYPES.has(k) or _type_car.is_empty():
		return
	_car_apply(_type_car, k)
	_car_snap_to(_type_car, k)


## Map size chosen (carousel tap/snap or programmatic).
func _on_size(k: String, locked: bool) -> void:
	if locked:
		_show_lockpop(k)
		return
	if not SIZES.has(k) or _size_car.is_empty():
		return
	_car_apply(_size_car, k)
	_car_snap_to(_size_car, k)


## Shaping option chosen — in-place style update (no screen rebuild, so
## the carousels keep their spin state).
func _on_opt(key: String, val: String) -> void:
	_opts[key] = val
	for kk in _opt_buttons:
		var b: Button = _opt_buttons[kk]
		if not is_instance_valid(b):
			continue
		var parts: PackedStringArray = String(kk).split(":")
		var sel: bool = parts.size() == 2 \
			and str(_opts.get(parts[0], "")) == parts[1]
		b.set_pressed_no_signal(sel)
		_style_opt(b, sel)
	_refresh_preview()


## "8k x 6k — Small map for phones. Fast and stable."
func _size_note_text() -> String:
	var d: Dictionary = SIZES.get(_size, {})
	return "%s — %s" % [String(d.get("sub", "")), String(d.get("desc", ""))]


func _on_reroll() -> void:
	if _busy:
		return
	_seed = _roll_seed()
	_refresh_preview()


func _on_start() -> void:
	if _busy:
		return
	world_confirmed.emit(_wtype, _size, _opts.duplicate(), _seed)


## Mobile size lock explainer (HTML cgwsel-lockpop parity). GOT IT or a
## tap outside the card dismisses (Jeremy's tap-outside-to-close rule).
func _show_lockpop(size_key: String) -> void:
	var pop := PanelContainer.new()
	pop.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Jeremy's tap-outside-to-close rule: the dim is no longer dead — a tap
	# outside the card dismisses the popup, same as every other modal.
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		var tapped := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			tapped = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			tapped = (event as InputEventScreenTouch).pressed
		if tapped:
			pop.queue_free()
	)
	pop.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pop.add_child(center)
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.165, 0.110, 0.071)
	sb.set_border_width_all(3)
	sb.border_color = Color(0.788, 0.635, 0.153)
	sb.set_corner_radius_all(8)
	card.add_theme_stylebox_override("panel", sb)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(_s(420), 0)
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	var t := _lbl("Huge needs a desktop" if size_key == "huge"
		else "That size needs a desktop", 20, Color(1.0, 0.835, 0.310))
	vb.add_child(t)
	var body := _lbl(("Phone detected — %s worlds pack far more land and "
		+ "thousands of thinking units. That needs a desktop's CPU and RAM; "
		+ "your phone would choke. Large is the biggest map your phone can "
		+ "run smoothly.") % String(SIZES[size_key]["name"]), 15,
		Color(0.851, 0.784, 0.659))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(body)
	var ok := _btn("GOT IT", true)
	ok.pressed.connect(func() -> void: pop.queue_free())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(ok)
	vb.add_child(row)
	add_child(pop)


# ------------------------------------------------------------------- preview

## The REAL terrain: same MapGen.generate + seed the world boots with.
## Faction start markers drawn in faction colors.
func _refresh_preview() -> void:
	# Jeremy 2026-10-03: debounce the expensive map bake — don't regenerate
	# on every swipe, wait until the user pauses.
	_preview_debounce = 0.8
	_seed_label.text = "Seed #%d" % _seed


func _do_refresh_preview() -> void:
	_preview_tex.texture = null
	_busy = true
	# Defer one frame so the UI paints before the ~1.4s bake.
	_render_preview.bind(_preview_tex).call_deferred()


func _render_preview(target: TextureRect) -> void:
	if not is_instance_valid(target):
		_busy = false
		return
	var gen := MapGen.new()
	var md := gen.generate(_factions, _seed, _wtype, _size, _opts)
	# Jeremy 2026-10-03: preview should look like a real map. Use the
	# renderer's own baked terrain image (hill shading, cliff rock faces,
	# snow/desert climate blends, muddy banks, water depth + foam,
	# faction territory tints) instead of flat per-tile colors.
	var baked: Image = md.get("terrain_image", null)
	if baked == null:
		_busy = false
		return
	var img := baked.duplicate() as Image
	var bw := float(img.get_width())
	var world_size: Vector2 = md.get("world_size",
		Vector2(bw * 32.0, bw * 32.0))
	var w2b := bw / maxf(world_size.x, 1.0)  # world px -> bake px

	# Trees: dark-green dots.
	var trees: Array = md.get("trees", [])
	for tp in trees:
		if not (tp is Vector2):
			continue
		var tv: Vector2 = tp
		_dot(img, int(tv.x * w2b), int(tv.y * w2b), 2,
			Color(0.10, 0.32, 0.10))
	# Resource nodes (HTML parity: wood / oil / gold near each start).
	var res_colors := {"wood": Color(0.45, 0.28, 0.12),
		"oil": Color(0.08, 0.08, 0.10), "gold": Color(1.0, 0.82, 0.20)}
	for rd in md.get("resources", []):
		if not (rd is Dictionary):
			continue
		var rp: Vector2 = rd.get("position", Vector2(-1, -1))
		if rp.x < 0.0:
			continue
		var rc: Color = res_colors.get(str(rd.get("type", "")), Color.WHITE)
		_dot(img, int(rp.x * w2b), int(rp.y * w2b), 3, rc)
	# Waterfalls: white-cyan sparkles where rivers drop.
	for wf in md.get("waterfalls", []):
		if not (wf is Dictionary):
			continue
		var wp: Vector2 = wf.get("position", Vector2(-1, -1))
		if wp.x < 0.0:
			continue
		_dot(img, int(wp.x * w2b), int(wp.y * w2b), 3,
			Color(0.92, 0.98, 1.0))
	# Faction start markers: faction-color ring + white core — clear but
	# small, so they read as pins, not paint blobs.
	var starts: Dictionary = md.get("faction_starts", {})
	for f in _factions:
		if not starts.has(f):
			continue
		var p: Vector2 = starts[f]
		var fc := Color.WHITE
		if Config.FACTIONS.has(f):
			fc = Config.FACTIONS[f]["color"]
		_ring(img, int(p.x * w2b), int(p.y * w2b), 7, 2, fc)
		_dot(img, int(p.x * w2b), int(p.y * w2b), 2, Color.WHITE)
	_preview_tex.texture = ImageTexture.create_from_image(img)
	if is_instance_valid(target):
		target.texture = _preview_tex.texture
	_busy = false


## Filled square dot (radius r) on an image, clipped to bounds.
static func _dot(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and y >= 0 and x < w and y < h:
				img.set_pixel(x, y, c)


## Circle ring (radius r, thickness t) on an image, clipped to bounds.
static func _ring(img: Image, cx: int, cy: int, r: int, t: int,
		c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var ro := float(r)
	var ri := float(r - t)
	for dy in range(-r - 1, r + 2):
		for dx in range(-r - 1, r + 2):
			var d := sqrt(float(dx * dx + dy * dy))
			if d > ro or d < ri:
				continue
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and y >= 0 and x < w and y < h:
				img.set_pixel(x, y, c)
