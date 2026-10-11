class_name PhoneUI
extends Control
## Cursing Gnomes — phone interface (Milestone 6).
##
## Touch-friendly UI (Jeremy's iPhone): big tap targets, large fonts.
## Home screen -> Messenger | Squabble | Gazette | Policies apps, mirroring
## the HTML:
##   - Messenger: pinned "My Government" + player-added contacts, thread
##     view, send box. Sort switcher (latest/most used/unread first).
##     Block/unblock per contact (blocked = fully silenced).
##   - Squabble: newest-first feed of post cards (pfp, name, text, like /
##     comment / resquabble), compose box, profile view with memory-based bio.
##   - Gazette: "The Cursing Chronicle" with Chronicle / Messages / Policies
##     tabs + open petitions with decision buttons (decisions reach the
##     player ONLY through the Gazette — no modals).
##   - Policies: the real Policies UI — seven governments, approval meters,
##     tax slider, anarchy, guard tiers, curfew, borders, festivals, quotas.
##
## Pure view code: all state lives in SimPhone / SimRoyalCourt / GameState.
## Construct programmatically (no .tscn) so it builds headless for tests.


## Jeremy 2026-10-03: big readable phone UI (iPhone feedback: "still too small").
const BTN_H := 120.0
const FONT_XL := 64
const FONT_LG := 52
const FONT_MD := 42
const FONT_SM := 34
const FONT_XS := 28
const PFP_SM := 100.0
const PFP_MD := 120.0
const PFP_LG := 160.0

## Bastard OS 2.0 palette (Jeremy 2026-10-06 graphical overhaul):
## deep navy-black glass, cool slate surfaces, soft shadows, game-gold accent.
## Jeremy 2026-10-03: phone should look like a real Android phone, chat as bubbles.
const PH_BG := Color(0.055, 0.060, 0.078)     # deep navy-black screen
const PH_SURFACE := Color(0.105, 0.115, 0.148) # cool slate cards / rows
const PH_SURFACE2 := Color(0.145, 0.155, 0.195) # slate received bubbles
const PH_BEZEL := Color(0.05, 0.05, 0.05)      # phone bezel
const PH_SENT := Color(0.145, 0.475, 0.92)     # rich blue sent bubbles
const PH_ACCENT := Color(1.0, 0.84, 0.35)      # game gold
const PH_TEXT := Color(0.96, 0.96, 0.97)
const PH_TEXT_DIM := Color(0.62, 0.64, 0.68)
const PH_DIV := Color(0.23, 0.24, 0.29)
const PH_RED := Color(0.90, 0.25, 0.25)        # unread badges
const PH_EDGE := Color(1.0, 1.0, 1.0, 0.08)    # hairline top-light on cards
const PH_SHADOW := Color(0.0, 0.0, 0.0, 0.45)  # soft drop shadows

## Jeremy 2026-10-03: phone view gets a black Android-style bezel with
## rounded corners, Android punch-hole camera, and scale-aware safe areas.
## No buttons on the bezel — all content lives inside the safe area.
## (Wood border is for the overworld view, not the phone.)

## Jeremy 2026-10-05: emoji in post/message TEXT must render (no tofu).
## UI chrome stays emoji-free (tofu rule), but user/NPC text content gets
## a system emoji font fallback so 😂 etc. display on iPhone.
static var _emoji_fallback: Font = null


static func emoji_font() -> Font:
	if _emoji_fallback == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray([
			"Apple Color Emoji", "Segoe UI Emoji", "Noto Color Emoji",
		])
		_emoji_fallback = sf
	return _emoji_fallback


## Applies the emoji fallback to a text-content label (post bodies, message
## bubbles, comments) so emoji render instead of tofu boxes.
func _emoji_text(lab: Label) -> Label:
	var base: Font = lab.get_theme_default_font()
	var fv := FontVariation.new()
	fv.base_font = base
	fv.fallbacks = [PhoneUI.emoji_font()]
	lab.add_theme_font_override("font", fv)
	return lab


var _gs: GameState = null
var _phone: SimPhone = null
var _court: SimRoyalCourt = null
var _diplo = null  # SimDiplomacy (duck-typed) — wired by the HUD
var _diplo_result: String = ""  # feedback line shown on the diplomacy screen
var _pol_watch_notice: String = ""  # feedback line shown on the Town Watch card
var _pol_plague_notice: String = ""  # feedback line shown on the Plague Doctrine card

var _root: VBoxContainer = null   # current screen container
var _screen: String = "home"
var _thread_key: String = ""      # open messenger thread
var _drama_key: String = ""        # open NPC-to-NPC drama thread (read-only)
var _profile_key: String = ""     # open squabble profile
var _close_btn: Button = null     # status-bar X/back button (rebuilt with shell)
## Jeremy 2026-10-04: hook for the custom keyboard's SEND key — the active
## screen sets this to its send action (e.g. Messenger thread). Cleared on
## every screen change via _clear().
var _kb_send_hook: Callable = Callable()
## Jeremy 2026-10-04: bottom nav bar back button (shell-persistent). Hidden
## on the home screen, mirroring the status-bar back arrow.
var _nav_back_btn: Button = null
var _nav_bar: HBoxContainer = null
## Jeremy 2026-10-04: live thread view refs — the message list container and
## scroll, so incoming messages/typing/receipts update without a rebuild.
var _thread_box: VBoxContainer = null
var _thread_scroll: ScrollContainer = null
## Jeremy 2026-10-08 (graphics hourly): Squabble live feed — the feed
## VBox while the Squabble app is open, so squabble_post inserts new cards
## at the top without a rebuild (same pattern as the live thread view).
var _squabble_box: VBoxContainer = null
## Typing indicator row (bubble with animated dots), shown while the NPC types.
var _typing_row: Control = null
var _typing_dots: Label = null
var _typing_timer: Timer = null
var _typing_dot_n := 0
## Per-message read-receipt labels, parallel to the thread's message array
## (only player messages get a receipt label; others hold null).
var _receipt_labels: Array = []

## Jeremy 2026-10-04: phone form factor. On iPhone (mobile/web-mobile),
## the phone fills the screen. On desktop (PC 16:9 / 4:3), it appears as
## a centered phone-shaped frame — classic feel for monitor players.
static func _is_desktop() -> bool:
	return not (OS.has_feature("mobile") or OS.has_feature("web_android") \
		or OS.has_feature("web_ios"))


## Phone frame rect within the viewport: fullscreen on mobile, centered
## phone-shaped frame on desktop. Phone aspect 9:19.5 (modern tall phone).
static func _phone_frame_rect(vp: Vector2) -> Rect2:
	if not _is_desktop():
		return Rect2(Vector2.ZERO, vp)
	# Desktop: fit a tall phone frame with 4% margins.
	var frame_h: float = vp.y * 0.92
	var frame_w: float = frame_h * 9.0 / 19.5
	# Don't exceed 92% width on narrow (4:3) desktop windows.
	if frame_w > vp.x * 0.92:
		frame_w = vp.x * 0.92
		frame_h = frame_w * 19.5 / 9.0
	var pos := Vector2((vp.x - frame_w) * 0.5, (vp.y - frame_h) * 0.5)
	return Rect2(pos, Vector2(frame_w, frame_h))

## Jeremy 2026-10-04: the phone's built-in custom keyboard. One shared
## instance, child of the PhoneUI itself (NOT _screen_host) so it survives
## screen rebuilds and overlays everything. Replaces the native OS keyboard
## in every phone text field.
var _kb: PhoneKeyboard = null

## Gazette tabs (HTML parity): Chronicle (news) / Messages (petitions) /
## Policies (policies summary).
var _gaz_tab: String = "chronicle"

## Android phone shell (built once in setup()).
var _phone_w := 400.0
var _phone_h := 720.0
var _screen_host: MarginContainer = null

## Jeremy 2026-10-03: phone home screen has a customizable wallpaper.
## Two pre-made + custom upload from the user's device.
const WALLPAPER_MOUNTAINS := "res://assets/ui/phone/wallpaper_mountains.webp"
const WALLPAPER_GNOME := "res://assets/ui/phone/wallpaper_gnome.webp"
## Jeremy 2026-10-04: chibi witch on pure black + mini Cursing Gnomes logo
## beneath her — the new DEFAULT home wallpaper (his words verbatim).
const WALLPAPER_WITCH := "res://assets/ui/phone/wallpaper_witch.webp"
const WALLPAPER_CUSTOM_FILE := "user://wallpaper_custom.png"
## Jeremy 2026-10-06 (polish round 2): new signature Bastard OS wallpaper,
## generated in the image tool — chibi gnome on a crescent moon.
const WALLPAPER_BASTARD := "res://assets/ui/phone/wallpaper_bastard.png"
## Jeremy 2026-10-06 (polish round 2): image-tool nav button graphics —
## proper back + power buttons for the phone shell (Back, never X).
const NAV_BACK_IMG := "res://assets/ui/phone/nav_back.webp"
const NAV_POWER_IMG := "res://assets/ui/phone/nav_power.webp"
const WALLPAPER_CFG := "user://bastardos.cfg"
var _wallpaper_choice := "witch"  # witch | mountains | gnome | custom
## Jeremy 2026-09-28 (phone rule): Messenger has a remembered sort switcher
## (latest / most-used / unread-first). Persists in user://bastardos.cfg.
var _msg_sort := "latest"
var _wallpaper_rect: TextureRect = null
var _screen_panel: PanelContainer = null
## Jeremy 2026-10-04 (polish): shell metrics for notification positioning.
var _shell_bezel := 12.0
var _shell_safe_top := 60.0
## Jeremy 2026-10-06 (launch readiness): also expose the bottom inset —
## the custom keyboard (a PhoneUI child, outside the safe column) uses it
## to lift its bottom sheet above the home-indicator zone.
var _shell_safe_bottom := 72.0


## Bottom safe inset of the phone shell (canvas px). Used by children that
## sit outside the safe-inset content column (e.g. the custom keyboard).
func phone_safe_bottom() -> float:
	return _shell_safe_bottom


## Jeremy 2026-10-06 (launch readiness): modal dialog width. The old fixed
## 520px minimum was wider than an iPhone portrait screen (~390px) — the
## dialog clipped ~65px off each edge, including Approve/Deny buttons.
## Clamp to the phone frame with 32px margins each side (280px floor).
func _modal_width() -> float:
	return minf(520.0, maxf(280.0, _phone_w - 64.0))


## Jeremy 2026-10-10 (menu-scroll audit): modal dialogs used to grow past
## the phone screen with no scroll — a long adviser brief pushed the
## Approve button off-screen on strategic proposals (a war decision!),
## and the insult dialog's Send/Cancel fell below the screen edge under
## the keyboard. The dialog content now lives in a ScrollContainer capped
## to 78% of the phone height; short dialogs still hug their content, and
## drags scroll while taps still fire buttons (default ScrollContainer
## gesture handling — no mid-scroll tap-fire).
func _cap_modal_scroll(dlg: PanelContainer, vbox: VBoxContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dlg.remove_child(vbox)
	dlg.add_child(scroll)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	var chrome := 56.0  # dlg content margins top+bottom
	var max_h := maxf(200.0, _phone_h * 0.78 - chrome)
	var need := vbox.get_combined_minimum_size().y
	if need <= 0.0:
		need = max_h
	scroll.custom_minimum_size = Vector2(_modal_width(), minf(need, max_h))
	return scroll
var _wallpaper_cb = null  # JavaScriptBridge callback for web file picker


## --- home screen icons (iOS-style movable) --------------------------------------
## Jeremy 2026-10-03: long-press an icon to wiggle, drag to rearrange, release
## to snap to grid. Icon order persists in user://bastardos.cfg.
const HOME_APPS := [
	["messenger", "Messenger", "res://assets/ui/phone/app_messenger.png"],
	["squabble", "Squabble", "res://assets/ui/phone/app_squabble.png"],
	["gazette", "News", "res://assets/ui/phone/app_gazette.png"],
	["policies", "Policies", "res://assets/ui/phone/app_policies.png"],
	["diplomacy", "Diplomacy", "res://assets/ui/phone/app_diplomacy.png"],
	["calendar", "Calendar", "res://assets/ui/phone/app_calendar.png"],
	["wallpaper", "Wallpaper", "res://assets/ui/phone/app_wallpaper.png"],
	["keyboard", "Keyboard", "res://assets/ui/phone/app_keyboard.png"],
	## Jeremy 2026-10-04: dedicated Weather app (was only a section of
	## the Forecast calendar). Appended last — canonical grid indices
	## for the earlier apps are pinned by tests.
	["weather", "Weather", "res://assets/ui/phone/app_weather.png"],
	## Jeremy 2026-10-06 (polish round 2): Settings app — blocked list
	## lives here. Appended last, same index-pinning rule.
	["settings", "Settings", "res://assets/ui/phone/app_settings.png"],
	## Jeremy 2026-10-06 (launch readiness — phone controls the whole
	## game): Army app — full army command surface on the phone. Appended
	## last, same index-pinning rule (settings at 9, army at 10).
	["army", "Army", "res://assets/ui/phone/app_army.png"],
	## Jeremy 2026-10-06 (launch readiness — hearsay/chat focus): Rumors
	## app — live rumor-mill feed from SimHearsay. Appended last, same
	## index-pinning rule (army at 10, rumors at 11).
	["rumors", "Rumors", "res://assets/ui/phone/app_rumors.png"],
]
const HOME_COLS := 3
const HOME_ICON_PX := 150.0
const HOME_TILE_H := 238.0
const HOME_LONG_PRESS := 0.5
const HOME_DRAG_SLOP := 14.0

var _home_order: Array = []
var _home_grid = null  # HomeGrid
var _home_done_btn: Button = null
## Jeremy 2026-10-06 (launch readiness): home screen scroll container —
## locked while wiggling so tile rearrangement never fights the scroll.
var _home_scroll: ScrollContainer = null
## Jeremy 2026-10-03: home weather widget labels (kept for tests).
var _home_weather_main: Label = null
var _home_weather_sub: Label = null
## Jeremy 2026-10-03: boot splash — shown every time the phone opens.
var _splash_boot: Control = null
var _splash_armed := false  # armed at the end of setup(); never on first build
## Jeremy 2026-10-06 (launch readiness): open system modals (petition /
## strategic-proposal Approve/Deny, diplomacy confirm, insult input) are
## full-screen overlays parented to the phone root. _build_shell() frees
## every direct child on rotation/shell rebuild, which used to silently
## destroy the modal while the petition/proposal stayed OPEN — it then
## expired unanswered (soft-deny + cooldown) as if the player had decided
## nothing. The registry lets _build_shell() snapshot and re-show each
## still-valid modal after the rebuild, so the decision is never lost.
var _open_modals: Array = []  # [{type, pid/params..., overlay}]
var _modal_seq: int = 0


class HomeTile extends Control:
	var app_id := ""
	var app_label := ""
	var _grid = null  # HomeGrid

	func setup(grid, aid: String, alabel: String, icon_path: String) -> void:
		_grid = grid
		app_id = aid
		app_label = alabel
		mouse_filter = Control.MOUSE_FILTER_STOP
		# Icon on top, label directly under it, centered — like a real phone.
		var box := VBoxContainer.new()
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.add_theme_constant_override("separation", 6)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(box)
		# Jeremy 2026-10-06: icons float directly on the wallpaper, like a
		# real phone home screen — the icon art is already finished glass
		# tiles, so no wrapper box (the old squircle panel looked like an
		# empty dark box).
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(0, PhoneUI.HOME_ICON_PX)
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path) as Texture2D
		box.add_child(icon)
		var lab := Label.new()
		lab.text = alabel
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lab.add_theme_font_size_override("font_size", PhoneUI.FONT_SM)
		lab.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		lab.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		lab.add_theme_constant_override("shadow_offset_x", 1)
		lab.add_theme_constant_override("shadow_offset_y", 1)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_child(lab)

	func _gui_input(event: InputEvent) -> void:
		if _grid == null:
			return
		var pressed := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			pressed = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			pressed = (event as InputEventScreenTouch).pressed
		else:
			return
		if pressed:
			var lp: Vector2 = event.position
			_grid._tile_pressed(self, lp)
		# Jeremy 2026-10-10 (menu-scroll audit): the press is NOT
		# accept_event()ed here. It must keep propagating so the home
		# ScrollContainer can claim drags and scroll — tiles used to
		# swallow every drag, so the home screen only scrolled from the
		# weather widget or bottom pad. Tap vs scroll is decided in
		# HomeGrid._input: a drag past HOME_DRAG_SLOP sets _press_moved
		# (kills the tap/long-press), a clean release fires the tap.
		# Wiggle mode locks the scroll separately (_on_home_wiggle),
		# so reorder drags never fight it.
		# Releases are handled globally by the grid so off-tile
		# releases can't leave a stuck drag.


class HomeGrid extends Control:
	signal app_tapped(app_id: String)
	signal wiggle_changed(active: bool)
	signal order_changed(new_order: Array)

	var _owner = null  # PhoneUI
	var _tiles: Array = []
	var _order: Array = []
	var _apps: Array = []
	var _wiggle := false
	var _press_tile = null  # HomeTile
	var _press_elapsed := 0.0
	var _press_moved := false
	var _press_consumed := false
	var _press_start := Vector2.ZERO
	var _drag_tile = null  # HomeTile
	var _fallback_w := 360.0

	func build(owner, apps: Array, order: Array, fallback_w: float) -> void:
		_owner = owner
		_apps = apps
		_order = order.duplicate()
		_fallback_w = fallback_w
		mouse_filter = Control.MOUSE_FILTER_STOP
		for aid in _order:
			var info := _app_info(String(aid))
			var t := HomeTile.new()
			t.setup(self, String(info[0]), String(info[1]), String(info[2]))
			add_child(t)
			_tiles.append(t)
		resized.connect(_on_resized)
		_layout(false)

	func _app_info(aid: String) -> Array:
		for a in _apps:
			if String(a[0]) == aid:
				return a
		return [aid, aid.capitalize(), ""]

	func is_wiggling() -> bool:
		return _wiggle

	func _on_resized() -> void:
		_layout(false)

	func _cell_w() -> float:
		var w := size.x
		if w <= 0.0:
			w = _fallback_w
		return w / float(PhoneUI.HOME_COLS)

	func _tile_pos(idx: int) -> Vector2:
		var cw := _cell_w()
		var ch := PhoneUI.HOME_TILE_H
		return Vector2((idx % PhoneUI.HOME_COLS) * cw + 12.0, (idx / PhoneUI.HOME_COLS) * ch + 6.0)

	func _tile_size() -> Vector2:
		var cw := _cell_w()
		return Vector2(maxf(cw - 24.0, 40.0), PhoneUI.HOME_TILE_H - 12.0)

	func _layout(animate: bool) -> void:
		var rows := int(ceil(float(maxi(_tiles.size(), 1)) / float(PhoneUI.HOME_COLS)))
		custom_minimum_size = Vector2(0, rows * PhoneUI.HOME_TILE_H)
		for i in _tiles.size():
			var t = _tiles[i]
			if t == _drag_tile:
				continue
			t.size = _tile_size()
			t.pivot_offset = t.size / 2.0
			var target := _tile_pos(i)
			if animate:
				var tw: Tween = t.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
				tw.tween_property(t, "position", target, 0.18)
			else:
				t.position = target

	# --- wiggle mode ---

	func set_wiggle(active: bool) -> void:
		if _wiggle == active:
			return
		_wiggle = active
		if active:
			for i in _tiles.size():
				var t = _tiles[i]
				if t != _drag_tile:
					_start_wiggle(t, fmod(float(i) * 0.07, 0.25))
		else:
			for t in _tiles:
				_stop_wiggle(t)
		wiggle_changed.emit(active)

	func _start_wiggle(t, delay: float) -> void:
		_stop_wiggle(t)
		t.rotation = 0.0
		var tw: Tween = t.create_tween().set_loops()
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_property(t, "rotation", 0.055, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(t, "rotation", -0.055, 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.set_meta("wiggle_tw", tw)

	func _stop_wiggle(t) -> void:
		if t.has_meta("wiggle_tw"):
			var tw = t.get_meta("wiggle_tw")
			if tw != null and is_instance_valid(tw):
				tw.kill()
			t.remove_meta("wiggle_tw")
		t.rotation = 0.0

	# --- press / drag ---

	func _tile_pressed(t, tile_local: Vector2) -> void:
		_press_tile = t
		_press_elapsed = 0.0
		_press_moved = false
		_press_consumed = false
		_press_start = t.position + tile_local

	func _input(event: InputEvent) -> void:
		if _drag_tile == null and _press_tile == null:
			return
		var released := false
		var moved := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				released = true
		elif event is InputEventScreenTouch:
			if not (event as InputEventScreenTouch).pressed:
				released = true
		elif event is InputEventMouseMotion or event is InputEventScreenDrag:
			moved = true
		if released:
			_release_anywhere()
		elif moved:
			var lp := get_local_mouse_position()
			if _drag_tile != null:
				_drag_to(lp)
			elif _press_tile != null and (lp - _press_start).length() > PhoneUI.HOME_DRAG_SLOP:
				_press_moved = true
				if _wiggle:
					_begin_drag(_press_tile)

	func _process(delta: float) -> void:
		if _press_tile != null and not _wiggle and not _press_moved and not _press_consumed:
			_press_elapsed += delta
			if _press_elapsed >= PhoneUI.HOME_LONG_PRESS:
				_press_consumed = true
				set_wiggle(true)

	func _release_anywhere() -> void:
		if _drag_tile != null:
			_finish_drag()
		elif _press_tile != null and not _press_moved and not _press_consumed:
			var t = _press_tile
			if _wiggle:
				set_wiggle(false)
			app_tapped.emit(t.app_id)
		_press_tile = null
		_press_elapsed = 0.0
		_press_moved = false
		_press_consumed = false

	func _gui_input(event: InputEvent) -> void:
		# Empty-area tap exits wiggle mode (tiles accept their own presses).
		var tapped := false
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			tapped = mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT
		elif event is InputEventScreenTouch:
			tapped = (event as InputEventScreenTouch).pressed
		if tapped and _wiggle and _drag_tile == null and _press_tile == null:
			set_wiggle(false)
			accept_event()

	func _begin_drag(t) -> void:
		_drag_tile = t
		_stop_wiggle(t)
		t.z_index = 10
		var tw: Tween = t.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.tween_property(t, "scale", Vector2(1.12, 1.12), 0.15)
		if get_viewport() != null:
			_drag_to(get_local_mouse_position())

	func _drag_to(p: Vector2) -> void:
		var t = _drag_tile
		if t == null or not is_instance_valid(t):
			return
		t.position = p - t.size * 0.5
		var idx := _cell_index_at(p)
		var cur := _tiles.find(t)
		if idx >= 0 and idx != cur:
			_tiles.remove_at(cur)
			_tiles.insert(mini(idx, _tiles.size()), t)
			var aid: String = _order[cur]
			_order.remove_at(cur)
			_order.insert(mini(idx, _order.size()), aid)
			_layout(true)

	func _cell_index_at(p: Vector2) -> int:
		if _tiles.is_empty():
			return -1
		var cw := _cell_w()
		var ch := PhoneUI.HOME_TILE_H
		var rows := int(ceil(float(_tiles.size()) / float(PhoneUI.HOME_COLS)))
		var col := clampi(int(floor(p.x / cw)), 0, PhoneUI.HOME_COLS - 1)
		var row := clampi(int(floor(p.y / ch)), 0, maxi(rows - 1, 0))
		return mini(row * PhoneUI.HOME_COLS + col, _tiles.size() - 1)

	func _finish_drag() -> void:
		var t = _drag_tile
		_drag_tile = null
		if t == null or not is_instance_valid(t):
			return
		t.z_index = 0
		var idx := _tiles.find(t)
		var target := _tile_pos(idx)
		var tw: Tween = t.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tw.set_parallel(true)
		tw.tween_property(t, "position", target, 0.2)
		tw.tween_property(t, "scale", Vector2.ONE, 0.2)
		tw.chain().tween_callback(_on_snap_done.bind(t))
		order_changed.emit(_order.duplicate())

	func _on_snap_done(t) -> void:
		if is_instance_valid(t) and _wiggle and t != _drag_tile:
			_start_wiggle(t, 0.0)


## Jeremy 2026-10-04 (polish): drawn back chevron — replaces the "←"
## text glyph (tofu risk on iPhone). Pure draw commands, always renders.
class ChevronIcon extends Control:
	var color := Color(0.95, 0.95, 0.95)
	var thickness := 8.0

	func _init(c: Color = Color(0.95, 0.95, 0.95), th: float = 8.0) -> void:
		color = c
		thickness = th
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(44, 44)

	func _draw() -> void:
		var s := size
		var pad := s.x * 0.30
		# Left-pointing chevron: two lines forming "<"
		draw_line(Vector2(s.x - pad, pad), Vector2(pad, s.y * 0.5),
			color, thickness, true)
		draw_line(Vector2(pad, s.y * 0.5), Vector2(s.x - pad, s.y - pad),
			color, thickness, true)


## Jeremy 2026-10-04: drawn up-arrow for the chat-style send button.
## Pure draw commands (no emoji/text glyph — tofu-safe on iPhone).
class SendArrowIcon extends Control:
	var color := Color.WHITE
	var thickness := 7.0

	func _init(c: Color = Color.WHITE, th: float = 7.0) -> void:
		color = c
		thickness = th
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(40, 40)

	func _draw() -> void:
		var s := size
		var cx := s.x * 0.5
		# Vertical shaft.
		draw_line(Vector2(cx, s.y * 0.82), Vector2(cx, s.y * 0.18),
			color, thickness, true)
		# Arrowhead.
		draw_line(Vector2(cx, s.y * 0.18), Vector2(s.x * 0.22, s.y * 0.46),
			color, thickness, true)
		draw_line(Vector2(cx, s.y * 0.18), Vector2(s.x * 0.78, s.y * 0.46),
			color, thickness, true)


## Jeremy 2026-10-04: drawn house icon for the phone's bottom nav bar.
## Pure draw commands (no emoji/text glyph — tofu-safe on iPhone).
class HomeIcon extends Control:
	var color := Color(0.95, 0.95, 0.95)
	var thickness := 7.0

	func _init(c: Color = Color(0.95, 0.95, 0.95), th: float = 7.0) -> void:
		color = c
		thickness = th
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(44, 44)

	func _draw() -> void:
		var s := size
		var pad := s.x * 0.22
		# House body: square from mid-height down.
		var top_y := s.y * 0.48
		var bot_y := s.y - pad
		draw_line(Vector2(pad, top_y), Vector2(pad, bot_y), color, thickness, true)
		draw_line(Vector2(s.x - pad, top_y), Vector2(s.x - pad, bot_y), color, thickness, true)
		draw_line(Vector2(pad, bot_y), Vector2(s.x - pad, bot_y), color, thickness, true)
		# Roof: triangle peak.
		draw_line(Vector2(pad, top_y), Vector2(s.x * 0.5, pad), color, thickness, true)
		draw_line(Vector2(s.x * 0.5, pad), Vector2(s.x - pad, top_y), color, thickness, true)


## Jeremy 2026-10-04: drawn power symbol for the phone's bottom nav bar.
## Circle arc (3/4) + vertical line at top. Pure draw commands, tofu-safe.
class PowerIcon extends Control:
	var color := Color(0.95, 0.95, 0.95)
	var thickness := 7.0

	func _init(c: Color = Color(0.95, 0.95, 0.95), th: float = 7.0) -> void:
		color = c
		thickness = th
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(44, 44)

	func _draw() -> void:
		var s := size
		var cx := s.x * 0.5
		var cy := s.y * 0.55
		var r := s.x * 0.30
		# Arc: 3/4 circle, gap at top.
		var a0 := -PI * 0.35
		var a1 := PI * 1.35
		draw_arc(Vector2(cx, cy), r, a0, a1, 24, color, thickness, true)
		# Vertical line from top into the circle.
		draw_line(Vector2(cx, s.y * 0.12), Vector2(cx, cy - r * 0.35),
			color, thickness, true)


## Jeremy 2026-10-04 (polish): drawn crown logo for the boot splash.
## Simple geometric crown — pure draw commands, no assets needed.
class CrownLogo extends Control:
	var color := Color(1.0, 0.84, 0.35)

	func _init(c: Color = Color(1.0, 0.84, 0.35)) -> void:
		color = c
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(160, 160)

	func _draw() -> void:
		var s := size
		var cx := s.x * 0.5
		# Crown body: polygon with three points
		var pts := PackedVector2Array([
			Vector2(cx - 52, s.y * 0.72),
			Vector2(cx - 52, s.y * 0.38),
			Vector2(cx - 26, s.y * 0.55),
			Vector2(cx, s.y * 0.28),
			Vector2(cx + 26, s.y * 0.55),
			Vector2(cx + 52, s.y * 0.38),
			Vector2(cx + 52, s.y * 0.72),
		])
		draw_colored_polygon(pts, color)
		# Base band
		draw_rect(Rect2(cx - 52, s.y * 0.76, 104, 10), color.darkened(0.15))
		# Jewels on the three points
		for jx in [cx - 52, cx, cx + 52]:
			var jy: float = s.y * 0.38 if jx != cx else s.y * 0.28
			draw_circle(Vector2(jx, jy - 8), 7, Color(0.9, 0.25, 0.25))


func setup(gs: GameState, phone: SimPhone, court: SimRoyalCourt,
		diplo = null) -> void:
	_gs = gs
	_phone = phone
	_court = court
	_diplo = diplo
	# Wire the phone into the court's policies so policy changes can post
	# to Squabble and DM the player (mayor complaints, guard desertion…).
	if _court != null and _court.has_method("attach_phone"):
		_court.attach_phone(_phone)
	# Jeremy 2026-10-04: desktop gets a centered phone frame, not fullscreen.
	var _vp := Vector2(_phone_w, _phone_h)
	var _view := get_viewport()
	if _view != null:
		_vp = _view.get_visible_rect().size
	var _frame := _phone_frame_rect(_vp)
	_phone_w = _frame.size.x
	_phone_h = _frame.size.y
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = _frame.position.x
	offset_top = _frame.position.y
	offset_right = _frame.position.x + _frame.size.x
	offset_bottom = _frame.position.y + _frame.size.y
	size = _frame.size
	_load_wallpaper_choice()
	_load_home_order()
	_build_shell()
	# Jeremy 2026-10-04: live messaging — the thread view updates in real
	# time as replies arrive (was: NPCs only "replied" after the player sent
	# another message, because the UI never listened to these signals).
	var bus = _gs.bus
	if not bus.phone_message.is_connected(_on_bus_phone_message):
		bus.phone_message.connect(_on_bus_phone_message)
	if not bus.phone_typing.is_connected(_on_bus_phone_typing):
		bus.phone_typing.connect(_on_bus_phone_typing)
	if not bus.phone_message_status.is_connected(_on_bus_phone_message_status):
		bus.phone_message_status.connect(_on_bus_phone_message_status)
	# Jeremy 2026-10-08 (graphics hourly): Squabble live feed — NPC posts
	# used to appear only after reopening the app (squabble_post was an
	# event-bus orphan since 2026-10-04; the UI never listened to it).
	if not bus.squabble_post.is_connected(_on_bus_squabble_post):
		bus.squabble_post.connect(_on_bus_squabble_post)
	# Jeremy 2026-10-04: tool/shop petition chain — the faction adviser
	# asks the player for build permission; answer via Approve/Deny modal.
	if not bus.build_request.is_connected(_on_bus_build_request):
		bus.build_request.connect(_on_bus_build_request)
	# Jeremy 2026-10-04: strategic proposal protocol ("AI plays the game,
	# player approves") — advisers ask for major decisions (war, monastery
	# assaults, expansion, buildup, peace); answer via Approve/Deny modal.
	if not bus.strategic_proposal.is_connected(_on_bus_strategic_proposal):
		bus.strategic_proposal.connect(_on_bus_strategic_proposal)
	# Jeremy 2026-10-11: war-spare fate votes + peace treaties + disaster-aid
	# votes interrupt with full-screen modals.
	if bus.has_signal("spare_vote_started") \
			and not bus.spare_vote_started.is_connected(
				_on_bus_spare_vote_started):
		bus.spare_vote_started.connect(_on_bus_spare_vote_started)
	if bus.has_signal("treaty_signed") \
			and not bus.treaty_signed.is_connected(_on_bus_treaty_signed):
		bus.treaty_signed.connect(_on_bus_treaty_signed)
	if bus.has_signal("aid_vote_started") \
			and not bus.aid_vote_started.is_connected(_on_bus_aid_vote_started):
		bus.aid_vote_started.connect(_on_bus_aid_vote_started)
	_show_home()
	# Arm the boot splash AFTER the first build, so the initial setup
	# never flashes it — it only fires when the phone is opened later.
	_splash_armed = true
	# Jeremy 2026-10-06 (launch readiness): refit the phone frame when the
	# viewport resizes (rotation) with the phone open. Guarded by
	# is_inside_tree() so headless -s setup() (no tree yet) stays silent.
	_arm_rotation_hook()


## Arm the viewport-resize refit (idempotent). Called from setup() and
## _ready() so the hook lands whether setup ran before or after tree entry.
func _arm_rotation_hook() -> void:
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree != null and tree.root != null \
			and not tree.root.size_changed.is_connected(_on_phone_viewport_resized):
		tree.root.size_changed.connect(_on_phone_viewport_resized)


func _ready() -> void:
	_arm_rotation_hook()


## Jeremy 2026-10-03: quick boot splash every time the phone opens.
## hud.gd shows the phone via `_phone_ui.visible = true`; we catch that
## here instead of touching hud.gd.
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED \
			and _splash_armed and visible:
		_show_boot_splash()


## Jeremy 2026-10-06 (launch readiness): viewport resized (device rotation)
## with the phone open — the frame rect used to stay frozen from open time,
## leaving a stale/mis-sized phone. Refit the frame, rebuild the shell, and
## return to the home screen so no app is left drawn at the old size.
func _on_phone_viewport_resized() -> void:
	var view := get_viewport()
	var vp := Vector2(_phone_w, _phone_h)
	if view != null:
		vp = view.get_visible_rect().size
	_refit_phone_frame(vp)


## Refit the phone frame to the given viewport size and rebuild the shell.
## Invisible phone = nothing to refit (the next open_app() rebuilds anyway).
func _refit_phone_frame(vp: Vector2) -> void:
	if not visible:
		return
	var frame := _phone_frame_rect(vp)
	_phone_w = frame.size.x
	_phone_h = frame.size.y
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = frame.position.x
	offset_top = frame.position.y
	offset_right = frame.position.x + frame.size.x
	offset_bottom = frame.position.y + frame.size.y
	size = frame.size
	_build_shell()
	_show_home()


## Full-screen "bastard OS" splash: crown logo scales in, spinner runs,
## holds ~1.0s, fades out fast. Snappy, not annoying — tap-through is
## blocked while it shows. Jeremy 2026-10-04 (polish): real boot feel
## with drawn crown logo instead of bare text.
func _show_boot_splash() -> void:
	_dismiss_boot_splash()
	var ov := PanelContainer.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0.02, 0.02, 0.02, 1.0)
	ov.add_theme_stylebox_override("panel", osb)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(cc)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(vbox)
	# Drawn crown logo (no asset dependency, no tofu risk).
	var crown := CrownLogo.new()
	crown.custom_minimum_size = Vector2(160, 160)
	crown.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(crown)
	var lab := Label.new()
	lab.text = "bastard OS"
	lab.add_theme_font_size_override("font_size", FONT_XL)
	lab.add_theme_color_override("font_color", PH_ACCENT)
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lab)
	var ver := Label.new()
	ver.text = "v1.0"
	ver.add_theme_font_size_override("font_size", FONT_SM)
	ver.add_theme_color_override("font_color", PH_TEXT_DIM)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(ver)
	# Jeremy 2026-10-06 (overhaul): the company line under the version.
	var motto := Label.new()
	motto.text = "no microtransactions. no bullshit."
	motto.add_theme_font_size_override("font_size", FONT_XS)
	motto.add_theme_color_override("font_color", PH_ACCENT.darkened(0.15))
	motto.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(motto)
	add_child(ov)  # last child = drawn on top of the whole phone
	_splash_boot = ov
	# Jeremy 2026-10-06 (polish round 2): gold sparkles around the crown
	# while the OS boots.
	_fx_burst(crown)
	# Pop-in the crown, hold, then fade the whole overlay.
	ov.modulate.a = 0.0
	crown.scale = Vector2(0.6, 0.6)
	crown.pivot_offset = Vector2(80, 80)
	var tw := ov.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ov, "modulate:a", 1.0, 0.18)
	tw.tween_property(crown, "scale", Vector2.ONE, 0.35)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(0.65)
	tw.tween_property(ov, "modulate:a", 0.0, 0.25)
	tw.tween_callback(_dismiss_boot_splash)


func _dismiss_boot_splash() -> void:
	if _splash_boot != null and is_instance_valid(_splash_boot):
		_splash_boot.queue_free()
	_splash_boot = null


## Jeremy 2026-10-04 (polish): notification banners — slide down from the
## top like a real phone when messages/events arrive. Tap opens the app.
## Queued so rapid-fire messages don't stack.
var _notif_queue: Array = []
var _notif_current: Control = null

## Jeremy 2026-10-10 (menu-scroll audit / polish): the pending queue was
## unbounded — a war + disaster + petition burst could stack minutes of
## banners. Cap pending banners at 5; newest wins, oldest pending drops.
const MAX_PENDING_NOTIFICATIONS := 5

func show_notification(title: String, body: String, app_id: String = "") -> void:
	_notif_queue.append({"title": title, "body": body, "app": app_id})
	while _notif_queue.size() > MAX_PENDING_NOTIFICATIONS:
		_notif_queue.pop_front()
	if _notif_current == null or not is_instance_valid(_notif_current):
		_show_next_notification()

func _show_next_notification() -> void:
	if _notif_queue.is_empty():
		_notif_current = null
		return
	var n: Dictionary = _notif_queue.pop_front()
	var banner := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.11, 0.12, 0.155, 0.97)  # Bastard OS 2.0 glass
	bsb.border_color = PH_ACCENT
	bsb.set_border_width_all(2)
	bsb.set_corner_radius_all(20)
	bsb.content_margin_left = 18.0
	bsb.content_margin_right = 18.0
	bsb.content_margin_top = 14.0
	bsb.content_margin_bottom = 14.0
	bsb.shadow_color = Color(0, 0, 0, 0.5)
	bsb.shadow_size = 12
	banner.add_theme_stylebox_override("panel", bsb)
	# Position: below the status bar, full width with margins.
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_left = 16
	banner.offset_right = -16
	banner.offset_top = -220  # start hidden above
	banner.offset_bottom = -80
	banner.mouse_filter = Control.MOUSE_FILTER_STOP
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(vbox)
	var t := Label.new()
	t.text = String(n["title"])
	t.add_theme_font_size_override("font_size", FONT_MD)
	t.add_theme_color_override("font_color", PH_TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(t)
	var b := Label.new()
	var body_text := String(n["body"])
	if body_text.length() > 90:
		body_text = body_text.substr(0, 90) + "…"
	b.text = body_text
	b.add_theme_font_size_override("font_size", FONT_SM)
	b.add_theme_color_override("font_color", PH_TEXT_DIM)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(b)
	add_child(banner)
	move_child(banner, get_child_count() - 1)
	_notif_current = banner
	# Jeremy 2026-10-04 (polish): banner slides down below the status bar,
	# clearing the bezel + punch-hole camera + status bar height.
	var notif_top := _shell_bezel + _shell_safe_top + 96.0
	var notif_h := 140.0
	var app_id := String(n["app"])
	if app_id != "":
		banner.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed \
					and ev.button_index == MOUSE_BUTTON_LEFT:
				_dismiss_notification()
				open_app(app_id)
			elif ev is InputEventScreenTouch and ev.pressed:
				_dismiss_notification()
				open_app(app_id))
	# Slide down, hold, slide back up.
	var tw := banner.create_tween()
	tw.tween_property(banner, "offset_top", notif_top, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(banner, "offset_bottom", notif_top + notif_h, 0.3)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(3.2)
	tw.tween_property(banner, "offset_top", -220.0, 0.25)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(banner, "offset_bottom", -80.0, 0.25)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_dismiss_notification)

func _dismiss_notification() -> void:
	if _notif_current != null and is_instance_valid(_notif_current):
		_notif_current.queue_free()
	_notif_current = null
	_show_next_notification()


func is_setup() -> bool:
	return _gs != null


func current_screen() -> String:
	return _screen


func open_app(app: String) -> void:
	# Jeremy 2026-10-03: force fullscreen size — CanvasLayer children
	# don't auto-size from anchors alone.
	# Jeremy 2026-10-04: on desktop (PC 16:9 / 4:3), the phone appears as
	# a centered phone-shaped frame, not fullscreen. On iPhone, fullscreen.
	var vp: Vector2 = Vector2(_phone_w, _phone_h)
	var _v := get_viewport()
	if _v != null:
		vp = _v.get_visible_rect().size
	var frame := _phone_frame_rect(vp)
	_phone_w = frame.size.x
	_phone_h = frame.size.y
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = frame.position.x
	offset_top = frame.position.y
	offset_right = frame.position.x + frame.size.x
	offset_bottom = frame.position.y + frame.size.y
	size = frame.size
	_build_shell()
	match app:
		"messenger":
			_show_messenger()
		"squabble":
			_show_squabble()
		"gazette":
			_show_gazette()
		"diplomacy":
			_show_diplomacy()
		"policies":
			_show_policies()
		"calendar":
			_show_calendar()
		"wallpaper":
			_show_wallpaper_settings()
		"keyboard":
			_show_keyboard_settings()
		"weather":
			_show_weather()
		"settings":
			_show_settings()
		"army":
			_show_army()
		"army_warroom":
			_show_army_warroom()
		"army_roster":
			_show_army_roster()
		"army_retinue":
			_show_army_retinue()
		"army_deploy":
			_show_army_deploy()
		"rumors":
			_show_rumors()
		_:
			_show_home()


func go_home() -> void:
	_show_home()


func open_thread(contact_key: String) -> void:
	_thread_key = contact_key
	_show_thread()


## Jeremy 2026-10-11: one Overheard row — "A \u2194 B" + last-line preview.
## Tapping opens the read-only drama thread.
func _drama_row(d: Dictionary) -> PanelContainer:
	var k := str(d.get("key", ""))
	var au: Dictionary = _phone._unit_for_key("u%d" % int(d.get("a_id", 0)))
	var preview := str(d.get("preview", ""))
	if preview.length() > 60:
		preview = preview.substr(0, 60) + "\u2026"
	var title := "%s \u2194 %s" % [str(d.get("a_name", "?")), str(d.get("b_name", "?"))]
	var ts := ""
	var mday := int(d.get("day", 0))
	if mday > 0:
		ts = "Day %d" % mday
	return _thread_item(title, preview, 0,
		func() -> void: _open_drama(k), au, ts, "overheard")


func _open_drama(drama_key: String) -> void:
	_drama_key = drama_key
	_show_drama_thread()


## Read-only NPC-to-NPC thread view — eavesdropping, no reply box.
func _show_drama_thread() -> void:
	_screen = "drama"
	_clear()
	var msgs: Array = _phone.social_life.thread_messages(_drama_key) \
		if _phone.social_life != null else []
	var au: Dictionary = {}
	var bu: Dictionary = {}
	var aname := "?"
	var bname := "?"
	if _phone.social_life != null:
		for dd: Dictionary in _phone.social_life.drama_threads():
			if str(dd.get("key", "")) == _drama_key:
				aname = str(dd.get("a_name", "?"))
				bname = str(dd.get("b_name", "?"))
				au = _phone._unit_for_key("u%d" % int(dd.get("a_id", 0)))
				bu = _phone._unit_for_key("u%d" % int(dd.get("b_id", 0)))
				break
	_header("%s \u2194 %s" % [aname, bname], "messenger")
	var note := Label.new()
	note.text = "\U0001F440 you're eavesdropping — they can't see you"
	note.add_theme_font_size_override("font_size", FONT_XS)
	note.add_theme_color_override("font_color", PH_TEXT_DIM)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(note)
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	box.add_theme_constant_override("separation", 4)
	var last_day: int = -1
	for mi in msgs.size():
		var m: Dictionary = msgs[mi]
		var from_a: bool = str(m.get("f", "a")) == "a"
		var mday: int = int(m.get("day", 0))
		if mday != last_day and mday > 0:
			box.add_child(_day_divider(_day_label(mday)))
			last_day = mday
		var av: Control = null
		if from_a and not au.is_empty():
			if mi + 1 >= msgs.size() \
					or str((msgs[mi + 1] as Dictionary).get("f", "a")) != "a":
				av = _pfp(au, 72.0)
		box.add_child(_bubble(str(m.get("text", "")), not from_a, av, ""))


func open_profile(contact_key: String) -> void:
	_profile_key = contact_key
	_show_profile()


## --- screens ----------------------------------------------------------------

## Build the Android phone shell: black bezel, punch-hole camera
## (Android-style, no iPhone notch), bastard OS branding, safe-area
## content inset. No buttons on the frame — all content fits inside
## the safe area.
func _build_shell() -> void:
	# Jeremy 2026-10-06 (launch readiness): snapshot open system modals
	# BEFORE freeing them — rotation used to destroy the decision modal
	# while the petition/proposal stayed open and expired unanswered
	# (soft-deny + cooldown) as if the player had decided nothing.
	# The keyboard is closed first so its freed field binding is dropped.
	if _kb != null and is_instance_valid(_kb):
		_kb.close()
	var restore: Array = _snapshot_modals()
	_open_modals.clear()
	for c: Node in get_children():
		if c == _splash_boot:
			continue  # boot splash survives rebuilds (dismissed by tween)
		c.queue_free()
	# Jeremy 2026-10-03: fullscreen phone — takes over the whole screen
	# like the old HTML version, not a floating frame.
	# Jeremy 2026-10-06 (launch readiness): shell metrics scale with the
	# PHONE FRAME, not the full viewport. setup()/open_app() already applied
	# the frame rect to this control, so `size` is the source of truth —
	# on desktop (PC 16:9 / 4:3) the centered 9:19.5 frame is much smaller
	# than the viewport, so viewport-sized bezels and safe insets swallowed
	# a third of the phone. Fall back to the viewport (mobile is fullscreen
	# anyway), then to the 400x720 defaults when headless with no size yet.
	var dims := size
	if dims.x <= 0.0 or dims.y <= 0.0:
		var view := get_viewport()
		if view != null:
			dims = view.get_visible_rect().size
	if dims.x > 0.0 and dims.y > 0.0:
		_phone_w = dims.x
		_phone_h = dims.y
	# --- Smartphone bezel (outermost) ---
	# Jeremy 2026-10-03: phone view gets a mobile phone border, not wood.
	# Wood border is for the overworld (hud.gd).
	# FIX 2026-10-03: frame/bg MUST be Panel, not PanelContainer. Children
	# of a Container get container-driven layout, so the old PanelContainers
	# silently ignored every anchor offset below — the bezel, the punch-hole
	# cam and the safe-area insets all collapsed, leaving a flat black box with
	# content running under the home indicator.
	# Metrics scale with the real viewport: canvas units vary by
	# device/stretch mode, so fixed px values cut content off on phones.
	var bezel := maxf(12.0, _phone_w * 0.030)       # black rim around screen
	var edge := maxi(2, int(_phone_w * 0.007))      # titanium edge line
	var safe_top := maxf(60.0, _phone_h * 0.070)    # below punch-hole cam
	var safe_bottom := maxf(72.0, _phone_h * 0.085) # above home indicator
	# Jeremy 2026-10-04 (polish): store for notification banner positioning.
	_shell_bezel = bezel
	_shell_safe_top = safe_top
	# Jeremy 2026-10-06 (launch readiness): expose the bottom inset too —
	# the custom keyboard lifts its sheet by this so the bottom key row
	# never sits under the home-indicator zone.
	_shell_safe_bottom = safe_bottom
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fsb := StyleBoxFlat.new()
	fsb.bg_color = Color(0.008, 0.008, 0.010)  # near-black phone bezel
	fsb.border_color = Color(0.34, 0.34, 0.37)  # titanium edge highlight
	fsb.set_border_width_all(edge)
	fsb.set_corner_radius_all(maxi(24, int(_phone_w * 0.095)))
	frame.add_theme_stylebox_override("panel", fsb)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	# --- Screen background (inside the bezel) ---
	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.offset_left = bezel
	bg.offset_top = bezel
	bg.offset_right = -bezel
	bg.offset_bottom = -bezel
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.07, 0.07, 0.07)  # dark screen background
	bsb.set_corner_radius_all(maxi(16, int(_phone_w * 0.062)))
	bg.add_theme_stylebox_override("panel", bsb)
	bg.clip_contents = true
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(bg)
	# --- Wallpaper layer (behind all screen content) ---
	# Jeremy 2026-10-03: phone home screen has a customizable wallpaper.
	_wallpaper_rect = TextureRect.new()
	_wallpaper_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_wallpaper_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_wallpaper_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_wallpaper_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(_wallpaper_rect)
	_apply_wallpaper()
	# Jeremy 2026-10-06 (overhaul): cinematic scrims over the wallpaper —
	# top darkens behind the status bar, bottom behind the nav bar, so
	# chrome stays readable on any wallpaper. Pure decoration, no input.
	var scrim_top := TextureRect.new()
	scrim_top.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim_top.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gtop := Gradient.new()
	gtop.set_color(0, Color(0, 0, 0, 0.55))
	gtop.set_color(1, Color(0, 0, 0, 0.0))
	var ttop := GradientTexture2D.new()
	ttop.gradient = gtop
	ttop.fill_from = Vector2(0.5, 0.0)
	ttop.fill_to = Vector2(0.5, 0.32)
	scrim_top.texture = ttop
	bg.add_child(scrim_top)
	var scrim_bot := TextureRect.new()
	scrim_bot.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim_bot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim_bot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gbot := Gradient.new()
	gbot.set_color(0, Color(0, 0, 0, 0.0))
	gbot.set_color(1, Color(0, 0, 0, 0.60))
	var tbot := GradientTexture2D.new()
	tbot.gradient = gbot
	tbot.fill_from = Vector2(0.5, 0.68)
	tbot.fill_to = Vector2(0.5, 1.0)
	scrim_bot.texture = tbot
	bg.add_child(scrim_bot)
	# --- Android punch-hole camera (top center of the display) ---
	# Jeremy 2026-10-03: phone runs bastard OS and is Android-style —
	# no iPhone notch pill. Just a small circular camera hole punched
	# in the screen, like a cheap Android.
	var cam_d := maxf(14.0, _phone_w * 0.035)
	var cam := Panel.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0.02, 0.03, 0.05)  # dark camera lens
	csb.border_color = Color(0.16, 0.20, 0.28)  # lens ring
	csb.set_border_width_all(maxi(1, int(edge * 0.5)))
	csb.set_corner_radius_all(int(cam_d))  # perfect circle
	cam.add_theme_stylebox_override("panel", csb)
	cam.set_anchors_preset(Control.PRESET_CENTER_TOP)
	cam.offset_left = -cam_d / 2.0
	cam.offset_right = cam_d / 2.0
	cam.offset_top = bezel * 0.45
	cam.offset_bottom = bezel * 0.45 + cam_d
	cam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(cam)
	# Tiny lens glint inside the punch-hole.
	var glint_d := cam_d * 0.35
	var glint := Panel.new()
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0.25, 0.32, 0.42)
	gsb.set_corner_radius_all(int(glint_d))
	glint.add_theme_stylebox_override("panel", gsb)
	glint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	glint.offset_left = -glint_d / 2.0
	glint.offset_right = glint_d / 2.0
	glint.offset_top = bezel * 0.45 + cam_d * 0.22
	glint.offset_bottom = bezel * 0.45 + cam_d * 0.22 + glint_d
	glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(glint)
	# --- Safe-area content ---
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_top = safe_top
	col.offset_bottom = -safe_bottom
	col.offset_left = 6
	col.offset_right = -6
	col.add_theme_constant_override("separation", 0)
	bg.add_child(col)
	col.add_child(_status_bar())
	# Screen content (fills remaining space).
	var screen := PanelContainer.new()
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = PH_BG
	screen.add_theme_stylebox_override("panel", ssb)
	screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
	screen.clip_contents = true
	col.add_child(screen)
	_screen_panel = screen
	_apply_screen_bg()
	_screen_host = MarginContainer.new()
	_screen_host.add_theme_constant_override("margin_left", 12)
	_screen_host.add_theme_constant_override("margin_right", 12)
	_screen_host.add_theme_constant_override("margin_top", 6)
	_screen_host.add_theme_constant_override("margin_bottom", 12)
	_screen_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screen.add_child(_screen_host)
	# Jeremy 2026-10-04: bottom nav bar — persistent across all phone apps.
	# Back (left) = one screen back. Home (center) = phone home screen.
	# Power (right) = close the phone. Drawn icons, no emoji (tofu rule).
	_nav_bar = _build_nav_bar()
	col.add_child(_nav_bar)
	# --- Home indicator (iOS-style pill at bottom) ---
	# Jeremy 2026-10-03: no X anywhere. Tapping the home indicator
	# closes the phone, like swiping up on a real phone.
	var home_hit := Button.new()
	home_hit.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var pill_w := maxf(120.0, _phone_w * 0.30)
	var pill_h := maxf(8.0, _phone_h * 0.008)
	home_hit.offset_left = -pill_w / 2.0
	home_hit.offset_right = pill_w / 2.0
	home_hit.offset_top = -safe_bottom + pill_h
	home_hit.offset_bottom = -safe_bottom + pill_h * 3.0
	home_hit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	home_hit.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	home_hit.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	home_hit.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	home_hit.pressed.connect(func() -> void: visible = false)
	bg.add_child(home_hit)
	var pill := Panel.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = Color(1, 1, 1, 0.45)
	psb.set_corner_radius_all(int(pill_h))
	pill.add_theme_stylebox_override("panel", psb)
	pill.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	pill.offset_left = -pill_w / 2.0
	pill.offset_right = pill_w / 2.0
	pill.offset_top = -safe_bottom + pill_h
	pill.offset_bottom = -safe_bottom + pill_h * 2.0
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(pill)
	# Jeremy 2026-10-06 (launch readiness): re-show the system modals that
	# were open before the rebuild (rotation). Only still-open
	# petitions/proposals come back — a decided modal is never resurrected.
	for r: Dictionary in restore:
		_reshow_modal(r)


## Jeremy 2026-10-04: bottom nav bar for the phone shell — persistent across
## all apps. Back (left) goes one screen back, Home (center) goes to the
## phone's home screen, Power (right) closes the phone. Drawn icons only
## (no emoji — tofu rule); back button, never an X.
func _build_nav_bar() -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 16)
	# Back (left) — image-tool graphic (Back, never X). Drawn chevron
	# kept as fallback if the asset is missing.
	_nav_back_btn = _nav_button("Back", _nav_icon_centered(NAV_BACK_IMG, 76.0,
		func() -> Control: return ChevronIcon.new(PH_TEXT, 15.0)))
	_nav_back_btn.pressed.connect(_on_status_back)
	bar.add_child(_nav_back_btn)
	# Home (center).
	var home := _nav_button("Home", _nav_icon_centered("", 76.0,
		func() -> Control: return HomeIcon.new(PH_TEXT, 14.0)))
	home.pressed.connect(_show_home)
	bar.add_child(home)
	# Power (right) — image-tool graphic; closes the phone back to the sim.
	# Jeremy 2026-10-06: a sleep/lock overlay here soft-locked his iPhone
	# ("tap to wake" with no path back to the sim), so power now always
	# closes the phone — Back / Home / Power per his bottom-nav design.
	var power := _nav_button("Close phone", _nav_icon_centered(NAV_POWER_IMG, 76.0,
		func() -> Control: return PowerIcon.new(PH_TEXT, 14.0)))
	power.pressed.connect(_close_phone)
	bar.add_child(power)
	return bar


## Jeremy 2026-10-06 (launch readiness): power closes the phone outright.
## Dismisses the custom keyboard first so no stale state lingers.
func _close_phone() -> void:
	if _kb != null and _kb.is_open():
		_kb.close()
	visible = false


## Jeremy 2026-10-06 (launch readiness): nav-bar button factory. The old
## fixed 120px buttons + 40px separation (= 440px) overflowed the ~330px
## content width on iPhone portrait and clipped Back/Power at the screen
## edges. Buttons now share the bar width equally (88px floor) and the
## icon centers inside whatever width the bar gives them.
func _nav_button(tooltip: String, icon: Control) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(88, 120)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.tooltip_text = tooltip
	var csb := StyleBoxFlat.new()
	csb.bg_color = PH_SURFACE
	csb.set_corner_radius_all(60)
	csb.border_color = PH_DIV
	csb.set_border_width_all(2)
	b.add_theme_stylebox_override("normal", csb)
	b.add_theme_stylebox_override("hover", csb)
	b.add_theme_stylebox_override("pressed", csb)
	b.add_theme_stylebox_override("focus", csb)
	var ctr := CenterContainer.new()
	ctr.set_anchors_preset(Control.PRESET_FULL_RECT)
	ctr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.custom_minimum_size = Vector2(76, 76)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ctr.add_child(icon)
	b.add_child(ctr)
	return b


## Jeremy 2026-10-06 (launch readiness): centered variant of _nav_icon for
## the flexible nav buttons — the icon keeps a fixed 76px box and centers
## via the button's CenterContainer instead of absolute offsets.
func _nav_icon_centered(img_path: String, icon_size: float,
		fallback: Callable) -> Control:
	if img_path != "" and ResourceLoader.exists(img_path):
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(img_path) as Texture2D
		tr.custom_minimum_size = Vector2(icon_size, icon_size)
		return tr
	var fb: Control = fallback.call()
	fb.custom_minimum_size = Vector2(icon_size, icon_size)
	return fb


## Jeremy 2026-10-06 (polish round 2): nav-bar icon loader — image-tool
## graphic when the asset exists, drawn icon fallback otherwise.
func _nav_icon(img_path: String, inset: float, icon_size: float,
		fallback: Callable) -> Control:
	if ResourceLoader.exists(img_path):
		var tr := TextureRect.new()
		# Jeremy 2026-10-06: set expand_mode BEFORE size — with the default
		# KEEP_SIZE the 1600px texture's minimum clamps size to 1600, and
		# the icon renders as a giant blob over the nav bar.
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = load(img_path) as Texture2D
		tr.position = Vector2(inset, inset)
		tr.size = Vector2(icon_size, icon_size)
		tr.custom_minimum_size = Vector2(icon_size, icon_size)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return tr
	var fb: Control = fallback.call()
	fb.position = Vector2(inset, inset)
	fb.size = Vector2(icon_size, icon_size)
	return fb


## Android status bar: day/time left, icons + close right.
func _status_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# Jeremy 2026-10-06 (overhaul): deep glass status bar, hairline under.
	sb.bg_color = Color(0.050, 0.055, 0.072)
	sb.border_width_bottom = 1
	sb.border_color = PH_DIV
	sb.content_margin_left = 14.0
	sb.content_margin_right = 8.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	bar.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var time := Label.new()
	time.text = "Day %d" % _gs.day_number if _gs != null else "Day 1"
	time.add_theme_font_size_override("font_size", FONT_MD)
	time.add_theme_color_override("font_color", PH_TEXT)
	time.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(time)
	# Jeremy 2026-10-03: the phone runs "bastard OS" — brand it in the
	# status bar like an Android build tag.
	var os := Label.new()
	os.text = "bastard OS"
	os.add_theme_font_size_override("font_size", FONT_SM)
	os.add_theme_color_override("font_color", PH_TEXT_DIM)
	os.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(os)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	# Jeremy 2026-10-03: NO X button — proper back navigation only.
	# In apps, the status bar shows a back arrow. On the home screen
	# there's no button at all; the home indicator closes the phone.
	# Jeremy 2026-10-04 (polish): drawn chevron, not the "←" text glyph
	# (tofu risk on iPhone). Jeremy 2026-10-04: real phone-UI sized —
	# 120px button (was 72).
	var back := Button.new()
	back.custom_minimum_size = Vector2(120, 120)
	var chev := ChevronIcon.new(PH_TEXT, 15.0)
	chev.position = Vector2(22, 22)
	chev.size = Vector2(76, 76)
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(chev)
	var csb := StyleBoxEmpty.new()
	back.add_theme_stylebox_override("normal", csb)
	back.add_theme_stylebox_override("hover", csb)
	back.add_theme_stylebox_override("pressed", csb)
	back.add_theme_stylebox_override("focus", csb)
	back.pressed.connect(_on_status_back)
	row.add_child(back)
	_close_btn = back
	_refresh_status_x()
	return bar


## Jeremy 2026-10-03: the status-bar back arrow returns to the previous
## screen (home, or the parent app for sub-screens). No X anywhere.
func _on_status_back() -> void:
	var target := _back_target_for(_screen)
	if target == "":
		return  # home screen: no back action (use home indicator)
	elif target == "home":
		_show_home()
	else:
		open_app(target)


## Back target for a screen, mirroring the app headers' back arrows.
## Returns "" when there is nowhere to go back to (home screen).
func _back_target_for(screen: String) -> String:
	match screen:
		"home":
			return ""
		"thread":
			return "messenger"
		"profile":
			return "squabble"
		"army_warroom", "army_roster", "army_retinue", "army_deploy":
			return "army"
		_:
			return "home"


## Show/hide the status-bar back arrow: visible in apps, hidden on home.
## Called on every screen change via _clear().
## Jeremy 2026-10-04: also drives the bottom nav bar's back button.
func _refresh_status_x() -> void:
	# Jeremy 2026-10-03: no X anywhere. Back arrow in apps, nothing on home.
	if _close_btn != null and is_instance_valid(_close_btn):
		_close_btn.visible = _screen != "home"
	if _nav_back_btn != null and is_instance_valid(_nav_back_btn):
		_nav_back_btn.visible = _screen != "home"


func _clear() -> void:
	if _screen_host == null:
		return
	for c: Node in _screen_host.get_children():
		c.queue_free()
	_apply_screen_bg()
	# Jeremy 2026-10-05: leaving a screen dismisses the custom keyboard so it
	# never lingers over the next screen bound to a freed text field.
	if _kb != null and _kb.is_open():
		_kb.close()
	# Jeremy 2026-10-04: the custom keyboard's SEND hook belongs to the
	# outgoing screen — clear it so a stale send action can't fire elsewhere.
	_kb_send_hook = Callable()
	# Jeremy 2026-10-04: typing indicator belongs to the outgoing thread —
	# stop its timer so dots don't animate a freed row.
	_hide_typing_indicator()
	_thread_box = null
	_thread_scroll = null
	_squabble_box = null
	_receipt_labels.clear()
	_home_scroll = null
	_refresh_status_x()
	# Policies screen hides the bottom nav bar; every other screen restores it.
	if _nav_bar != null and is_instance_valid(_nav_bar):
		_nav_bar.visible = true
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_theme_constant_override("separation", 8)
	_screen_host.add_child(_root)
	# Jeremy 2026-10-04 (polish): subtle fade-in on every screen change —
	# feels like a real phone transitioning between apps, not a hard cut.
	# Jeremy 2026-10-06 (polish round 2): fade for a proper app-open feel.
	# (Position animation removed — _root lives in a MarginContainer, so
	# a position tween fights the container layout. Modulate is safe.)
	_root.modulate.a = 0.0
	var tw := _root.create_tween()
	tw.tween_property(_root, "modulate:a", 1.0, 0.18)\
		.set_trans(Tween.TRANS_LINEAR)


## Toggle the screen background: transparent on home (wallpaper shows
## through), dark PH_BG inside apps for readability.
func _apply_screen_bg() -> void:
	if _screen_panel == null:
		return
	var ssb := StyleBoxFlat.new()
	if _screen == "home":
		ssb.bg_color = Color(0, 0, 0, 0)
	else:
		ssb.bg_color = PH_BG
	_screen_panel.add_theme_stylebox_override("panel", ssb)
	_apply_wallpaper()


## --- wallpaper ---------------------------------------------------------------
## Jeremy 2026-10-03: phone home screen wallpaper — two pre-made plus
## custom upload from the user's device. Choice persists in user://bastardos.cfg.

func _load_wallpaper_choice() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(WALLPAPER_CFG) == OK:
		_wallpaper_choice = String(cfg.get_value("phone", "wallpaper", "witch"))
	if _wallpaper_choice not in ["witch", "mountains", "gnome", "bastard", "custom"]:
		_wallpaper_choice = "witch"


func _save_wallpaper_choice() -> void:
	var cfg := ConfigFile.new()
	cfg.load(WALLPAPER_CFG)  # keep other keys
	cfg.set_value("phone", "wallpaper", _wallpaper_choice)
	cfg.save(WALLPAPER_CFG)


## Jeremy 2026-09-28: Messenger sort mode is remembered across sessions.
func _load_msg_sort() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(WALLPAPER_CFG) == OK:
		_msg_sort = String(cfg.get_value("messenger", "sort", "latest"))
	if _msg_sort not in ["latest", "most_used", "unread_first"]:
		_msg_sort = "latest"


func _save_msg_sort() -> void:
	var cfg := ConfigFile.new()
	cfg.load(WALLPAPER_CFG)  # keep other keys
	cfg.set_value("messenger", "sort", _msg_sort)
	cfg.save(WALLPAPER_CFG)


func _load_home_order() -> void:
	_home_order = []
	var cfg := ConfigFile.new()
	var saved: Array = []
	if cfg.load(WALLPAPER_CFG) == OK:
		saved = Array(cfg.get_value("phone", "icon_order", []))
	var ids: Array = []
	for a in HOME_APPS:
		ids.append(String(a[0]))
	for oid in saved:
		var s := String(oid)
		if s in ids and not (s in _home_order):
			_home_order.append(s)
	for aid in ids:
		if not (aid in _home_order):
			_home_order.append(aid)


func _save_home_order() -> void:
	var cfg := ConfigFile.new()
	cfg.load(WALLPAPER_CFG)  # keep other keys
	cfg.set_value("phone", "icon_order", _home_order)
	cfg.save(WALLPAPER_CFG)


func _on_home_wiggle(active: bool) -> void:
	if _home_done_btn != null and is_instance_valid(_home_done_btn):
		_home_done_btn.visible = active
	# Jeremy 2026-10-06 (launch readiness): lock the home scroll while
	# rearranging — the grid's _input drag handling and the ScrollContainer
	# would otherwise fight over the same touch.
	if _home_scroll != null and is_instance_valid(_home_scroll):
		_home_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED \
			if active else ScrollContainer.SCROLL_MODE_AUTO


func _on_home_order_changed(new_order: Array) -> void:
	_home_order = new_order.duplicate()
	_save_home_order()


func _get_wallpaper_texture() -> Texture2D:
	match _wallpaper_choice:
		"witch":
			if ResourceLoader.exists(WALLPAPER_WITCH):
				return load(WALLPAPER_WITCH) as Texture2D
		"gnome":
			if ResourceLoader.exists(WALLPAPER_GNOME):
				return load(WALLPAPER_GNOME) as Texture2D
		"bastard":
			if ResourceLoader.exists(WALLPAPER_BASTARD):
				return load(WALLPAPER_BASTARD) as Texture2D
		"custom":
			if FileAccess.file_exists(WALLPAPER_CUSTOM_FILE):
				var img := Image.load_from_file(WALLPAPER_CUSTOM_FILE)
				if img != null:
					return ImageTexture.create_from_image(img)
		_:
			pass
	if ResourceLoader.exists(WALLPAPER_MOUNTAINS):
		return load(WALLPAPER_MOUNTAINS) as Texture2D
	return null


func _apply_wallpaper() -> void:
	if _wallpaper_rect == null:
		return
	_wallpaper_rect.texture = _get_wallpaper_texture()
	# Wallpaper shows on the home screen; apps keep their dark bg.
	_wallpaper_rect.visible = (_screen == "home")


func _set_wallpaper(choice: String) -> void:
	_wallpaper_choice = choice
	_save_wallpaper_choice()
	_apply_wallpaper()
	if _screen == "wallpaper":
		_show_wallpaper_settings()


## Wallpaper picker screen: pre-made thumbnails + custom upload.
func _show_wallpaper_settings() -> void:
	_screen = "wallpaper"
	_clear()
	_header("Wallpaper")
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)

	var info := Label.new()
	info.text = "Choose a home screen wallpaper."
	info.add_theme_font_size_override("font_size", FONT_SM)
	info.add_theme_color_override("font_color", PH_TEXT_DIM)
	box.add_child(info)

	for wp: Array in [
		["Witch (default)", "witch", WALLPAPER_WITCH],
		["Bastard Night", "bastard", WALLPAPER_BASTARD],
		["Mountains", "mountains", WALLPAPER_MOUNTAINS],
		["Gnome", "gnome", WALLPAPER_GNOME],
	]:
		var row := _wallpaper_row(String(wp[0]), String(wp[1]), String(wp[2]))
		box.add_child(row)

	# Custom upload row.
	var custom_btn := _btn("Upload custom image…", func() -> void: _pick_custom_wallpaper())
	box.add_child(custom_btn)
	if _wallpaper_choice == "custom" and FileAccess.file_exists(WALLPAPER_CUSTOM_FILE):
		var note := Label.new()
		note.text = "Using your custom image."
		note.add_theme_font_size_override("font_size", FONT_SM)
		note.add_theme_color_override("font_color", PH_ACCENT)
		box.add_child(note)


func _wallpaper_row(label: String, choice: String, tex_path: String) -> PanelContainer:
	var card := _card()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	card.add_child(row)
	# Thumbnail.
	var thumb := TextureRect.new()
	if ResourceLoader.exists(tex_path):
		thumb.texture = load(tex_path) as Texture2D
	thumb.custom_minimum_size = Vector2(160, 100)
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	row.add_child(thumb)
	var lab := Label.new()
	lab.text = label
	lab.add_theme_font_size_override("font_size", FONT_MD)
	lab.add_theme_color_override("font_color", PH_TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lab)
	if _wallpaper_choice == choice:
		# Selected-row marker: plain ASCII text, never a glyph — Godot's
		# default font renders ✓/✔ as tofu boxes on iPhone (Jeremy 2026-10-03).
		var check := Label.new()
		check.text = "Active"
		check.add_theme_font_size_override("font_size", FONT_SM)
		check.add_theme_color_override("font_color", PH_ACCENT)
		check.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(check)
	else:
		var use := Button.new()
		use.text = "Use"
		use.custom_minimum_size = Vector2(120, 80)
		use.add_theme_font_size_override("font_size", FONT_SM)
		use.pressed.connect(func() -> void: _set_wallpaper(choice))
		row.add_child(use)
	return card


## Jeremy 2026-10-06 (polish round 2): Settings app — the blocked list
## lives here. Blocked NPCs are fully silenced (existing behavior);
## each entry gets an Unblock button.
func _show_settings() -> void:
	_screen = "settings"
	_clear()
	_header("Settings")
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	box.add_child(_section("Blocked"))
	var keys: Array = _phone.blocked_keys()
	if keys.is_empty():
		var none := Label.new()
		none.text = "No blocked contacts."
		none.add_theme_font_size_override("font_size", FONT_SM)
		none.add_theme_color_override("font_color", PH_TEXT_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
	for k in keys:
		box.add_child(_blocked_row(String(k)))


func _blocked_row(key: String) -> PanelContainer:
	var u: Dictionary = _phone._unit_for_key(key)
	if u.is_empty() and SimFactionLeaders.is_leader_key(key):
		u = _phone.leader_pseudo_unit(key)
	var nm: String = _phone.leader_name_for_key(key) \
		if SimFactionLeaders.is_leader_key(key) \
		else (SimPersonality.display_name(u) if not u.is_empty() else key)
	var card := _card()
	# Jeremy 2026-10-06: PASS so drags on the row scroll the Settings list.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	row.add_child(_pfp(u, PFP_MD))
	var lab := Label.new()
	lab.text = nm
	lab.add_theme_font_size_override("font_size", FONT_MD)
	lab.add_theme_color_override("font_color", PH_TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.clip_text = true
	lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lab)
	var key2 := key
	var unb := _menu_btn("Unblock", func() -> void:
		_phone.unblock_key(key2)
		_show_settings())
	unb.custom_minimum_size = Vector2(220, 88)
	unb.size_flags_horizontal = 0
	unb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(unb)
	return card


## Jeremy 2026-10-04: keyboard settings — themes, autocorrect aggression,
## auto-learn toggle, and the learned-words list (tap to delete).
func _show_keyboard_settings() -> void:
	_screen = "keyboard"
	_clear()
	_header("Keyboard")
	var kb := _ensure_keyboard()
	var dict: SimKeyboardDict = kb.dict
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)

	# --- Theme section ---
	box.add_child(_section_label("Theme"))
	for tid in PhoneKeyboard.THEME_ORDER:
		var tname := kb.theme_name(tid)
		var row := _card()
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		# Color swatch preview.
		var sw := ColorRect.new()
		var tdef: Dictionary = PhoneKeyboard.THEMES[tid]
		sw.color = tdef["accent"]
		sw.custom_minimum_size = Vector2(48, 48)
		h.add_child(sw)
		var lab := Label.new()
		lab.text = tname
		lab.add_theme_font_size_override("font_size", FONT_MD)
		lab.add_theme_color_override("font_color", PH_TEXT)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		h.add_child(lab)
		if dict.kb_theme == tid:
			var active := Label.new()
			active.text = "Active"
			active.add_theme_font_size_override("font_size", FONT_SM)
			active.add_theme_color_override("font_color", PH_ACCENT)
			active.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			h.add_child(active)
		else:
			var use := _btn("Use", func() -> void:
				dict.kb_theme = tid
				dict.save_dict()
				kb.set_kb_theme(tid)
				_show_keyboard_settings())
			use.custom_minimum_size = Vector2(110, BTN_H)
			h.add_child(use)
		box.add_child(row)

	# --- Autocorrect aggression ---
	box.add_child(_section_label("Autocorrect"))
	var agg_info := Label.new()
	agg_info.text = "Low suggests only. Medium fixes obvious typos. High corrects aggressively. Aggressive rewrites with confidence."
	agg_info.add_theme_font_size_override("font_size", FONT_SM)
	agg_info.add_theme_color_override("font_color", PH_TEXT_DIM)
	agg_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(agg_info)
	var agg_row := HBoxContainer.new()
	agg_row.add_theme_constant_override("separation", 8)
	box.add_child(agg_row)
	for level in SimKeyboardDict.AGGRESSION_LEVELS:
		var lv := String(level)
		var b := _btn(lv.capitalize(), func() -> void:
			dict.aggression = lv
			dict.save_dict()
			_show_keyboard_settings())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if dict.aggression == lv:
			b.modulate = Color(1.0, 0.85, 0.45)
		agg_row.add_child(b)

	# --- Auto-learn toggle ---
	box.add_child(_section_label("Word learning"))
	var learn_row := _card()
	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 12)
	learn_row.add_child(lh)
	var llab := Label.new()
	llab.text = "Auto-learn new words (skip the \"Add word?\" prompt)"
	llab.add_theme_font_size_override("font_size", FONT_MD)
	llab.add_theme_color_override("font_color", PH_TEXT)
	llab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	llab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	llab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lh.add_child(llab)
	var toggle := _btn("ON" if dict.auto_learn else "OFF", func() -> void:
		dict.auto_learn = not dict.auto_learn
		dict.save_dict()
		_show_keyboard_settings())
	toggle.custom_minimum_size = Vector2(110, BTN_H)
	if dict.auto_learn:
		toggle.modulate = Color(1.0, 0.85, 0.45)
	lh.add_child(toggle)
	box.add_child(learn_row)

	# --- Auto-space toggle (Jeremy 2026-10-05) ---
	box.add_child(_section_label("Auto-space"))
	var as_row := _card()
	var ah := HBoxContainer.new()
	ah.add_theme_constant_override("separation", 12)
	as_row.add_child(ah)
	var alab := Label.new()
	alab.text = "Automatically insert a space after suggestions and after . ! ?"
	alab.add_theme_font_size_override("font_size", FONT_MD)
	alab.add_theme_color_override("font_color", PH_TEXT)
	alab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	alab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ah.add_child(alab)
	var astoggle := _btn("ON" if dict.auto_space else "OFF", func() -> void:
		dict.auto_space = not dict.auto_space
		dict.save_dict()
		_show_keyboard_settings())
	astoggle.custom_minimum_size = Vector2(110, BTN_H)
	if dict.auto_space:
		astoggle.modulate = Color(1.0, 0.85, 0.45)
	ah.add_child(astoggle)
	box.add_child(as_row)

	# --- Learned words ---
	box.add_child(_section_label("Learned words (%d)" % dict.learned_words().size()))
	var hint := Label.new()
	hint.text = "Tap a word to remove it. You can also hold any learned suggestion above the keyboard to delete it."
	hint.add_theme_font_size_override("font_size", FONT_SM)
	hint.add_theme_color_override("font_color", PH_TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	for w in dict.learned_words():
		var word := String(w)
		var wrow := _card()
		var wh := HBoxContainer.new()
		wh.add_theme_constant_override("separation", 12)
		wrow.add_child(wh)
		var wlab := Label.new()
		wlab.text = word
		wlab.add_theme_font_size_override("font_size", FONT_MD)
		wlab.add_theme_color_override("font_color", PH_TEXT)
		wlab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wlab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		wh.add_child(wlab)
		var del := _btn("Delete", func() -> void:
			dict.remove_learned_word(word)
			_show_keyboard_settings())
		del.custom_minimum_size = Vector2(110, BTN_H)
		wh.add_child(del)
		box.add_child(wrow)
	if dict.learned_words().is_empty():
		var empty := Label.new()
		empty.text = "No learned words yet. Type unknown words 3 times and the keyboard will ask to learn them."
		empty.add_theme_font_size_override("font_size", FONT_SM)
		empty.add_theme_color_override("font_color", PH_TEXT_DIM)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(empty)

	# --- Correction memory: never-autocorrect list (Jeremy 2026-10-05) ---
	box.add_child(_section_label("Never autocorrect (%d)" % dict.correction_blocks().size()))
	var cm_hint := Label.new()
	cm_hint.text = "Words you took back after an autocorrection — the keyboard will never change these again. Tap a blue-underlined word while typing to take one back."
	cm_hint.add_theme_font_size_override("font_size", FONT_SM)
	cm_hint.add_theme_color_override("font_color", PH_TEXT_DIM)
	cm_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(cm_hint)
	for pair in dict.correction_blocks():
		var typed := String(pair[0])
		var corr := String(pair[1])
		var crow := _card()
		var ch := HBoxContainer.new()
		ch.add_theme_constant_override("separation", 12)
		crow.add_child(ch)
		var clab := Label.new()
		clab.text = "\"%s\" (never -> \"%s\")" % [typed, corr]
		clab.add_theme_font_size_override("font_size", FONT_MD)
		clab.add_theme_color_override("font_color", PH_TEXT)
		clab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		clab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ch.add_child(clab)
		var cdel := _btn("Delete", func() -> void:
			dict.remove_correction_block(typed, corr)
			_show_keyboard_settings())
		cdel.custom_minimum_size = Vector2(110, BTN_H)
		ch.add_child(cdel)
		box.add_child(crow)
	if dict.correction_blocks().is_empty():
		var cm_empty := Label.new()
		cm_empty.text = "Nothing here yet."
		cm_empty.add_theme_font_size_override("font_size", FONT_SM)
		cm_empty.add_theme_color_override("font_color", PH_TEXT_DIM)
		cm_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(cm_empty)
	else:
		var cm_clear := _btn("Clear all", func() -> void:
			dict.clear_correction_blocks()
			_show_keyboard_settings())
		cm_clear.custom_minimum_size = Vector2(160, BTN_H)
		box.add_child(cm_clear)


func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_MD)
	l.add_theme_color_override("font_color", PH_ACCENT)
	return l


## Custom wallpaper upload: web uses a JS file picker, desktop uses FileDialog.
func _pick_custom_wallpaper() -> void:
	if OS.has_feature("web"):
		_pick_custom_wallpaper_web()
	else:
		_pick_custom_wallpaper_desktop()


func _pick_custom_wallpaper_desktop() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.add_filter("*.png, *.jpg, *.jpeg, *.webp", "Images")
	dlg.title = "Choose wallpaper image"
	dlg.file_selected.connect(_on_wallpaper_file_selected)
	add_child(dlg)
	dlg.popup_centered(Vector2(600, 400))


func _on_wallpaper_file_selected(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null:
		return
	# Downscale huge images so the phone doesn't choke.
	if img.get_width() > 1024 or img.get_height() > 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_BILINEAR)
	img.save_png(WALLPAPER_CUSTOM_FILE)
	_set_wallpaper("custom")


func _pick_custom_wallpaper_web() -> void:
	# Godot 4 web: trigger an HTML file input via JavaScriptBridge,
	# read the image as a data URL, pass it back through a callback.
	# eval() takes only the code string, so stash the callback on
	# window first, then reference it from the evaluated JS.
	_wallpaper_cb = JavaScriptBridge.create_callback(_on_wallpaper_picked_js)
	var window := JavaScriptBridge.get_interface("window")
	window.godotWallpaperCallback = _wallpaper_cb
	JavaScriptBridge.eval("""
	(function() {
		var cb = window.godotWallpaperCallback;
		var input = document.createElement('input');
		input.type = 'file';
		input.accept = 'image/*';
		input.onchange = function(e) {
			var file = e.target.files[0];
			if (!file) return;
			var reader = new FileReader();
			reader.onload = function(ev) { cb(ev.target.result); };
			reader.readAsDataURL(file);
		};
		input.click();
	})();
	""")


func _on_wallpaper_picked_js(args: Array) -> void:
	if args.is_empty():
		return
	var data_url := String(args[0])
	var comma := data_url.find(",")
	if comma < 0:
		return
	var b64 := data_url.substr(comma + 1)
	var bytes := Marshalls.base64_to_raw(b64)
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes)
	if err != OK:
		err = img.load_jpg_from_buffer(bytes)
	if err != OK:
		err = img.load_webp_from_buffer(bytes)
	if err != OK:
		return
	if img.get_width() > 1024 or img.get_height() > 1024:
		img.resize(1024, 1024, Image.INTERPOLATE_BILINEAR)
	img.save_png(WALLPAPER_CUSTOM_FILE)
	_set_wallpaper("custom")


## Android app bar: dark strip, back arrow, title.
func _header(title: String, back_to: String = "home") -> HBoxContainer:
	var bar := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	# Jeremy 2026-10-06 (overhaul): deep glass bar, gold hairline under it.
	bsb.bg_color = Color(0.075, 0.080, 0.105)
	bsb.border_width_bottom = 2
	bsb.border_color = PH_ACCENT.darkened(0.45)
	bsb.content_margin_left = 6.0
	bsb.content_margin_right = 12.0
	bsb.content_margin_top = 6.0
	bsb.content_margin_bottom = 6.0
	bar.add_theme_stylebox_override("panel", bsb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	var back := Button.new()
	# Jeremy 2026-10-04 (polish): drawn chevron, not the "←" text glyph
	# (tofu risk on iPhone).
	back.custom_minimum_size = Vector2(72, 72)
	var hchev := ChevronIcon.new(PH_ACCENT, 9.0)
	hchev.position = Vector2(16, 16)
	hchev.size = Vector2(40, 40)
	hchev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(hchev)
	# Jeremy 2026-10-06 (overhaul): circular glass disc behind the chevron.
	var bdisc := StyleBoxFlat.new()
	bdisc.bg_color = Color(1, 1, 1, 0.06)
	bdisc.set_corner_radius_all(999)
	bdisc.border_color = PH_EDGE
	bdisc.set_border_width_all(1)
	var bdisc_p := bdisc.duplicate() as StyleBoxFlat
	bdisc_p.bg_color = Color(1, 1, 1, 0.12)
	back.add_theme_stylebox_override("normal", bdisc)
	back.add_theme_stylebox_override("hover", bdisc)
	back.add_theme_stylebox_override("pressed", bdisc_p)
	back.add_theme_stylebox_override("focus", bdisc)
	back.pressed.connect(func() -> void:
		# Jeremy 2026-10-11 (P0 iPhone crash on exit): this button is
		# queue_free()d by the teardown its own press triggers (_clear()
		# frees the whole screen). Navigate deferred so the emitter
		# finishes its signal on a live node before teardown runs.
		if back_to == "home":
			_show_home.call_deferred()
		else:
			open_app.call_deferred(back_to))
	row.add_child(back)
	var lab := Label.new()
	lab.text = title
	lab.add_theme_font_size_override("font_size", FONT_LG)
	lab.add_theme_color_override("font_color", PH_TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lab)
	_root.add_child(bar)
	return row


## Material-dark button.
func _btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, BTN_H)
	b.add_theme_font_size_override("font_size", FONT_MD)
	b.add_theme_color_override("font_color", PH_TEXT)
	b.add_theme_color_override("font_hover_color", PH_TEXT)
	b.add_theme_color_override("font_pressed_color", PH_ACCENT)
	b.add_theme_stylebox_override("normal", _btn_style(PH_SURFACE))
	b.add_theme_stylebox_override("hover", _btn_style(PH_SURFACE2))
	b.add_theme_stylebox_override("pressed", _btn_style(Color(0.20, 0.20, 0.20)))
	b.add_theme_stylebox_override("focus", _btn_style(PH_SURFACE))
	b.add_theme_stylebox_override("disabled", _btn_style(Color(0.10, 0.10, 0.10)))
	b.pressed.connect(on_press)
	return b


func _btn_style(bg: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(18)
	sb.border_color = PH_EDGE
	sb.set_border_width_all(1)
	sb.shadow_color = PH_SHADOW
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	return sb


## Bastard OS 2.0 card (Jeremy 2026-10-06 overhaul): glassy slate card,
## hairline top-light, soft drop shadow. Used by posts, petitions,
## diplomacy, policy sections — every app gets the new look at once.
func _card() -> PanelContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SURFACE
	sb.set_corner_radius_all(20)
	sb.border_color = PH_EDGE
	sb.set_border_width_all(1)
	sb.shadow_color = PH_SHADOW
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", sb)
	return card


## Jeremy 2026-10-04: one shared custom keyboard for the whole phone.
## Child of the PhoneUI root (not _screen_host) so screen rebuilds don't
## kill it. Applies the saved theme from the dict.
func _ensure_keyboard() -> PhoneKeyboard:
	if _kb != null and is_instance_valid(_kb):
		return _kb
	_kb = PhoneKeyboard.new()
	add_child(_kb)
	_kb.set_kb_theme(_kb.dict.kb_theme)
	# Keep the keyboard on top of everything.
	move_child(_kb, get_child_count() - 1)
	# Jeremy 2026-10-04: the custom keyboard's SEND key must actually send
	# (e.g. Messenger message). The active screen registers its send action
	# via _kb_send_hook; _clear() resets it on every screen change.
	if not _kb.send_pressed.is_connected(_on_kb_send_pressed):
		_kb.send_pressed.connect(_on_kb_send_pressed)
	return _kb


## Jeremy 2026-10-04: custom keyboard SEND key — fires the active screen's
## registered send action (Messenger thread, Squabble comment, ...).
func _on_kb_send_pressed() -> void:
	if _kb_send_hook.is_valid():
		_kb_send_hook.call()


## Open the custom keyboard for a LineEdit. The native OS keyboard is
## disabled (virtual_keyboard_enabled = false) so iOS never focus-zooms.
func _open_phone_keyboard(field: LineEdit) -> void:
	var kb := _ensure_keyboard()
	move_child(kb, get_child_count() - 1)
	kb.open_for(field, _kb_scale())


func _kb_scale() -> float:
	# Scale keyboard keys to the phone width (design width 400).
	# Jeremy 2026-10-05: floor raised 0.7 -> 0.9 so keys stay >= ~80px tall
	# on iPhone (base key height is 92 design px).
	return clampf(_phone_w / 400.0, 0.9, 2.0)


## Pill-style text entry.
func _line_edit(ph: String) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = ph
	e.custom_minimum_size = Vector2(0, BTN_H)
	e.add_theme_font_size_override("font_size", FONT_MD)
	e.add_theme_color_override("font_color", PH_TEXT)
	e.add_theme_color_override("font_placeholder_color", PH_TEXT_DIM)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SURFACE2
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Jeremy 2026-10-04: the phone uses the built-in custom keyboard, not
	# the native OS keyboard (no HTML input exists, so iOS cannot focus-zoom
	# and backspace can never desync). Disable the OS keyboard and open ours.
	e.virtual_keyboard_enabled = false
	e.focus_entered.connect(_open_phone_keyboard.bind(e))
	# Jeremy 2026-10-05: tapping the bar sometimes never fired focus_entered
	# on the web export, so the keyboard never appeared. Drive it from the
	# touch event too (same hardening as main_menu.gd _styled_input).
	e.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
			if not e.has_focus():
				e.grab_focus()  # focus_entered opens the keyboard
			else:
				_open_phone_keyboard(e))
	return e


## Chat bubble: sent = right/blue, received = left/dark gray.
## Modern chat-style bubble. Incoming bubbles can carry the sender's avatar
## (shown on the last bubble of an incoming run, like real texting apps).
## Day context comes from the day-divider pills; no per-bubble timestamps.
func _bubble(text: String, sent: bool, avatar: Control = null,
		ts_label: String = "") -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	# Jeremy 2026-10-06: bubbles are display-only — IGNORE so a drag
	# starting on a bubble scrolls the thread (ScrollContainer gets it).
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var max_w: float = _phone_w * 0.68
	var font: Font = get_theme_default_font()
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_MD).x
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SENT if sent else PH_SURFACE2
	sb.set_corner_radius_all(20)
	if sent:
		sb.corner_radius_top_right = 6
	else:
		sb.corner_radius_top_left = 6
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	# Jeremy 2026-10-06 (overhaul): bubbles float — soft drop shadow.
	sb.shadow_color = PH_SHADOW
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 2)
	bubble.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lab.add_theme_font_size_override("font_size", FONT_MD)
	lab.add_theme_color_override("font_color", Color.WHITE)
	_emoji_text(lab)
	lab.custom_minimum_size = Vector2(minf(tw + 4.0, max_w), 0)
	bubble.add_child(lab)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if sent:
		row.add_child(sp)
		row.add_child(bubble)
	else:
		if avatar != null:
			avatar.size_flags_vertical = Control.SIZE_SHRINK_END
			row.add_child(avatar)
		row.add_child(bubble)
		row.add_child(sp)
	wrap.add_child(row)
	# Jeremy 2026-10-06: small timestamp under the last bubble of a sender
	# run, like iMessage.
	if ts_label != "":
		var ts := Label.new()
		ts.text = ts_label
		ts.add_theme_font_size_override("font_size", FONT_XS)
		ts.add_theme_color_override("font_color", PH_TEXT_DIM)
		ts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if sent \
			else HORIZONTAL_ALIGNMENT_LEFT
		ts.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wrap.add_child(ts)
	# All descendants IGNORE too — a Label or Panel with STOP would still
	# swallow the press even with the wrap set to IGNORE.
	_ignore_mouse(wrap)
	return wrap


## Recursively set MOUSE_FILTER_IGNORE — for display-only subtrees inside
## scrollable lists, so drags always reach the ScrollContainer.
func _ignore_mouse(n: Node) -> void:
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_ignore_mouse(c)


## Circular avatar with an initial (fallback when no sprite exists).
func _avatar(initial: String, color: Color, px: float = PFP_MD) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(999)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	var lab := Label.new()
	lab.text = initial
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.add_theme_font_size_override("font_size", int(px * 0.42))
	lab.add_theme_color_override("font_color", Color.WHITE)
	p.add_child(lab)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _avatar_color(key: String) -> Color:
	var palette := [
		Color(0.20, 0.55, 0.85), Color(0.55, 0.35, 0.80),
		Color(0.25, 0.65, 0.45), Color(0.85, 0.55, 0.20),
		Color(0.85, 0.35, 0.35), Color(0.30, 0.70, 0.70),
	]
	return palette[absi(hash(key)) % palette.size()]


## PFP that looks like the character in the overworld (Jeremy 2026-10-03).
## Uses Art.unit_texture — the exact sprite the world renderer draws.
## Circular crop; falls back to the initial-circle when art is missing.
func _pfp(u: Dictionary, px: float = PFP_MD) -> Control:
	var tex: Texture2D = null
	# Jeremy 2026-10-06: faction leaders show their distinct persona
	# portrait (assets/art/portraits/leader_<faction>_<slug>.webp).
	var lp: String = String(u.get("_leader_pfp", ""))
	if lp != "":
		tex = Art.portrait_texture(lp)
	if tex == null and not u.is_empty() and not u.has("_leader_name"):
		tex = Art.unit_texture(
			String(u.get("faction", "humans")),
			String(u.get("job", "worker")),
			int(u.get("id", 0)),
			String(u.get("gender", "m")))
	if tex == null:
		# Leaders (and units without art) get an initial-circle avatar.
		var nm: String = String(u.get("_leader_name", "")) \
			if u.has("_leader_name") \
			else (SimPersonality.display_name(u) if not u.is_empty() else "?")
		if nm == "":
			nm = "?"
		return _avatar(nm.left(1).to_upper(), _avatar_color(nm), px)
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SURFACE2
	sb.set_corner_radius_all(999)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(px, px)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	return p


## PFP from a resolved texture (for stored pfp keys — no unit lookup needed).
func _pfp_tex(tex: Texture2D, px: float = PFP_MD) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SURFACE2
	sb.set_corner_radius_all(999)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(px, px)
	tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(tr)
	return p


## Empty-state illustration: centered image above a "nothing here" label.
## Jeremy 2026-10-03: generated art for empty phone screens.
func _empty_art(path: String, px: float = 220.0) -> CenterContainer:
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	if ResourceLoader.exists(path):
		tr.texture = load(path) as Texture2D
	tr.custom_minimum_size = Vector2(px, px)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(tr)
	return cc


## Faction emblem for diplomacy cards.
## Jeremy 2026-10-03: generated heraldry per faction.
func _faction_emblem(faction: String, px: float = 64.0) -> Control:
	var path := "res://assets/ui/phone/faction_emblem_%s.webp" % faction
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.set_corner_radius_all(999)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(px, px)
	p.clip_contents = true
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path) as Texture2D
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(px, px)
		tr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tr.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
	return p


## Ruler pfp: the player's own overworld look.
func _ruler_pfp(px: float = PFP_MD) -> Control:
	var fake := {
		"faction": _gs.player_faction if _gs != null else "humans",
		"job": "ruler", "id": 0, "gender": "m",
	}
	return _pfp(fake, px)


## Chat-list row: pfp, name, role, preview, unread badge. Tappable.
## Messenger/Discord style: 72px pfp, large text.
func _thread_item(p_name: String, preview: String, unread: int,
		on_press: Callable, u: Dictionary = {}, ts: String = "",
		subtitle: String = "", on_long_press: Callable = Callable()) -> PanelContainer:
	var card := _card()
	# Jeremy 2026-10-06: PASS, not STOP — the card must see the press for
	# tap detection, but drags must propagate to the ScrollContainer so
	# the list scrolls when the gesture starts on a row. Tap-vs-drag is
	# disambiguated in the gui_input handler below.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	# Jeremy 2026-10-05: premium contacts — thin gold spine on the card.
	var cpsb := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	cpsb.border_width_left = 4
	cpsb.border_color = PH_ACCENT.darkened(0.35)
	card.add_theme_stylebox_override("panel", cpsb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	# Pfp with a subtle gold ring.
	var ring := PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = PH_ACCENT.darkened(0.45)
	rsb.set_corner_radius_all(999)
	rsb.content_margin_left = 3.0
	rsb.content_margin_right = 3.0
	rsb.content_margin_top = 3.0
	rsb.content_margin_bottom = 3.0
	ring.add_theme_stylebox_override("panel", rsb)
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.add_child(_pfp(u, PFP_MD))
	row.add_child(ring)
	var txt := VBoxContainer.new()
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.add_theme_constant_override("separation", 4)
	txt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(txt)
	# Name + timestamp on one row (timestamp right-aligned, dim).
	var nrow := HBoxContainer.new()
	nrow.add_theme_constant_override("separation", 8)
	nrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_child(nrow)
	var nm := Label.new()
	nm.text = p_name
	nm.add_theme_font_size_override("font_size", FONT_MD)
	nm.add_theme_color_override("font_color", PH_TEXT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.clip_text = true  # Jeremy 2026-10-06: long names must not force
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # the card
	nrow.add_child(nm)  # wider than the list (was breaking vertical scroll)
	if ts != "":
		var tsl := Label.new()
		tsl.text = ts
		tsl.add_theme_font_size_override("font_size", FONT_XS)
		tsl.add_theme_color_override("font_color", PH_TEXT_DIM)
		tsl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nrow.add_child(tsl)
	# Jeremy 2026-10-05: government role / job under the name, small gold.
	if subtitle != "":
		var sub := Label.new()
		sub.text = subtitle
		sub.add_theme_font_size_override("font_size", FONT_SM)
		sub.add_theme_color_override("font_color", PH_ACCENT.lightened(0.15))
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sub.clip_text = true  # Jeremy 2026-10-06: keep the card narrow
		sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		txt.add_child(sub)
	var pv := Label.new()
	pv.text = preview
	pv.add_theme_font_size_override("font_size", FONT_SM)
	pv.add_theme_color_override("font_color", PH_TEXT_DIM)
	pv.clip_text = true
	pv.max_lines_visible = 2
	pv.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	txt.add_child(pv)
	if unread > 0:
		var badge := PanelContainer.new()
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = PH_RED
		bsb.set_corner_radius_all(999)
		bsb.content_margin_left = 14.0
		bsb.content_margin_right = 14.0
		bsb.content_margin_top = 8.0
		bsb.content_margin_bottom = 8.0
		badge.add_theme_stylebox_override("panel", bsb)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := Label.new()
		bl.text = str(unread)
		bl.add_theme_font_size_override("font_size", FONT_SM)
		bl.add_theme_color_override("font_color", Color.WHITE)
		bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(bl)
		badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(badge)
	# Jeremy 2026-10-05: tap-vs-scroll — a chat opens only on a clean
	# tap (press + release with minimal movement). Drags scroll the list
	# instead. (Touch on iPhone arrives as emulated mouse events, so
	# mouse-button handling alone covers both.)
	# Jeremy 2026-10-06: tap-vs-scroll fix — the card moves WITH the finger
	# during a list scroll (ScrollContainer tracks 1:1), so card-relative
	# press/release distance is ~0 even for a long scroll. The old 14px
	# check alone therefore opened the chat on nearly every scroll release.
	# Now we also record the list's scroll offset at press: a tap is only
	# a tap if the list didn't move between press and release.
	card.gui_input.connect(func(ev: InputEvent) -> void:
		if not (ev is InputEventMouseButton \
				and ev.button_index == MOUSE_BUTTON_LEFT):
			return
		if ev.pressed:
			card.set_meta("_press_pos", ev.position)
			# Jeremy 2026-10-06 (polish round 2): long-press detection
			# for the contact context menu (Remove / Block).
			card.set_meta("_press_msec", Time.get_ticks_msec())
			var psc := _enclosing_scroll(card)
			card.set_meta("_press_scroll", Vector2(
				psc.scroll_horizontal, psc.scroll_vertical) \
				if psc != null else Vector2.ZERO)
		elif card.has_meta("_press_pos"):
			var start: Vector2 = card.get_meta("_press_pos")
			var ps: Vector2 = card.get_meta("_press_scroll", Vector2.ZERO)
			var held_ms: int = int(Time.get_ticks_msec()) \
				- int(card.get_meta("_press_msec", 0))
			card.remove_meta("_press_pos")
			card.remove_meta("_press_scroll")
			card.remove_meta("_press_msec")
			var rsc := _enclosing_scroll(card)
			if rsc != null \
					and (absf(rsc.scroll_horizontal - ps.x) > 2.0 \
					or absf(rsc.scroll_vertical - ps.y) > 2.0):
				return  # the list scrolled: gesture was a scroll, not a tap
			if ev.position.distance_to(start) > 14.0:
				return
			# Long hold (600ms+) with a menu handler: context menu
			# instead of opening the chat.
			if held_ms >= 600 and on_long_press.is_valid():
				on_long_press.call(card)
				return
			on_press.call())
	return card


## Nearest enclosing ScrollContainer, or null. Used for tap-vs-scroll
## disambiguation: a card inside a scrolled list moves with the finger,
## so the tap handler must check the list's scroll offset, not just
## card-relative press/release distance.
func _enclosing_scroll(c: Control) -> ScrollContainer:
	var n: Node = c.get_parent()
	while n != null:
		if n is ScrollContainer:
			return n as ScrollContainer
		n = n.get_parent()
	return null


## Home-screen app tile: big label, no emoji (tofu on iPhone).
## Real Android-style app icon: rounded icon image on top, label below.
## Section label (e.g. "My Government") — gold header + hairline rule.
func _section(text: String, color: Color = PH_ACCENT) -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 6)
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_MD)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(l)
	var rule := ColorRect.new()
	rule.color = color.darkened(0.6)
	rule.custom_minimum_size = Vector2(0, 2)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(rule)
	return wrap


func _scroll() -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Jeremy 2026-10-06: contacts were hard to scroll — wide cards enabled
	# horizontal scrolling, which fights vertical drags on touch. Phone
	# lists scroll vertically only.
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Jeremy 2026-10-06: systemic no-scroll fix — vertical drag scrolling
	# is the phone's primary gesture. Stated explicitly (not relying on
	# the default) so a future default change can't silently break every
	# list. NOTE: on iOS Safari this ALSO requires
	# `#canvas { touch-action: none }` in the exported HTML (see
	# fix-ios-zoom.sh) — without it Safari hijacks vertical drags as page
	# pans, cancels the touch stream, and Godot's drag dies: taps work but
	# nothing scrolls. That was the 2026-10-06 systemic outage.
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_root.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	sc.add_child(box)
	return sc


func _show_home() -> void:
	_screen = "home"
	_clear()
	# Jeremy 2026-10-06 (launch readiness): the home content (weather
	# widget + 4 icon rows + bottom pad, ~1280px) is far taller than the
	# ~470px available on iPhone portrait — it used to render straight
	# into _root with no scroll, so Weather/Settings (rows 3-4) were
	# clipped off-screen and unreachable. Wrap in a vertical scroll; the
	# scroll locks while wiggling so tile rearrangement never fights it.
	var hsc := _scroll()
	_home_scroll = hsc
	var hbox: VBoxContainer = hsc.get_child(0)
	_build_home_weather(hbox)
	# Jeremy 2026-10-03: iOS-style movable icons — long-press to wiggle,
	# drag to rearrange, release to snap. Done button exits wiggle mode.
	_home_done_btn = Button.new()
	_home_done_btn.text = "Done"
	_home_done_btn.visible = false
	_home_done_btn.add_theme_font_size_override("font_size", FONT_MD)
	hbox.add_child(_home_done_btn)
	_home_grid = HomeGrid.new()
	_home_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_home_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_home_grid.build(self, HOME_APPS, _home_order, _phone_w)
	_home_grid.app_tapped.connect(open_app)
	_home_grid.wiggle_changed.connect(_on_home_wiggle)
	_home_grid.order_changed.connect(_on_home_order_changed)
	_home_done_btn.pressed.connect(func() -> void:
		if _home_grid != null and is_instance_valid(_home_grid):
			_home_grid.set_wiggle(false))
	hbox.add_child(_home_grid)
	# Jeremy 2026-10-05: keep the icon grid clear of the wallpaper
	# character art — reserve empty space at the bottom.
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 110)
	hbox.add_child(bottom_pad)


## Small weather widget for the home screen: drawn weather icon above
## "Clear · 72F" plus day phase and season. Drawn icon, never emoji
## (Jeremy's tofu rule, 2026-10-03); same visual language as the
## Forecast app rows (2026-10-04 visual-quality rule).
## Reads through PhoneWeather.current() — the one null-safe source of
## truth for live sim weather (never _gs.seasons directly).
func _build_home_weather(parent: Control = null) -> void:
	# Jeremy 2026-10-05: the weather widget is the prominent top element
	# of the home screen now (title block removed). Big drawn icon, big
	# text, truly centered. Tapping opens the Weather app.
	# Jeremy 2026-10-06 (launch readiness): the home screen now scrolls,
	# so the widget goes into the scroll's box instead of _root directly.
	var host: Control = parent if parent != null else _root
	var wrap := Button.new()
	wrap.flat = true
	wrap.custom_minimum_size = Vector2(0, 220)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP
	var wempty := StyleBoxEmpty.new()
	wrap.add_theme_stylebox_override("normal", wempty)
	wrap.add_theme_stylebox_override("hover", wempty)
	wrap.add_theme_stylebox_override("pressed", wempty)
	wrap.add_theme_stylebox_override("focus", wempty)
	wrap.pressed.connect(func() -> void: open_app("weather"))
	host.add_child(wrap)
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 4)
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(vbox)
	var cur: Dictionary = PhoneWeather.current(_gs)
	if not cur.is_empty():
		# Jeremy 2026-10-04 (polish): drawn condition icon — the sim's
		# condition strings map 1:1 to ForecastIcon kinds (same mapping
		# the Forecast rows use). Taps pass through to the wrap button.
		var wicon := ForecastIcon.make(
			String(cur.get("condition", "clear")), Color.WHITE, 96.0)
		wicon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		wicon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(wicon)
	_home_weather_main = Label.new()
	_home_weather_sub = Label.new()
	if not cur.is_empty():
		_home_weather_main.text = String(cur["display"])
		_home_weather_sub.text = "%s \u00b7 %s" % [
			String(cur["day_phase"]), String(cur["season"])]
	else:
		_home_weather_main.text = "--"
		_home_weather_sub.text = ""
	for l: Label in [_home_weather_main, _home_weather_sub]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override("shadow_offset_x", 2)
		l.add_theme_constant_override("shadow_offset_y", 2)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(l)
	_home_weather_main.add_theme_font_size_override("font_size", FONT_LG)
	_home_weather_main.add_theme_color_override("font_color", PH_TEXT)
	_home_weather_sub.add_theme_font_size_override("font_size", FONT_MD)
	_home_weather_sub.add_theme_color_override("font_color", PH_TEXT_DIM)


## Jeremy 2026-09-28 (phone rule): Messenger sort switcher — latest /
## most-used / unread-first, remembered in user://bastardos.cfg. Segmented
## control under the header; pinned sections stay pinned, "My Contacts"
## reorders per the mode (mirrors SimPhone.sorted_threads() thread logic).
func _add_sort_switcher() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var modes: Array = [
		["latest", "Latest"],
		["most_used", "Most used"],
		["unread_first", "Unread first"],
	]
	for m: Array in modes:
		var mode: String = String(m[0])
		var b := Button.new()
		b.text = String(m[1])
		b.toggle_mode = true
		b.button_pressed = (_msg_sort == mode)
		b.custom_minimum_size = Vector2(0, 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", FONT_SM)
		var active := _msg_sort == mode
		b.add_theme_color_override("font_color", PH_ACCENT if active else PH_TEXT)
		b.add_theme_stylebox_override("normal",
			_btn_style(Color(0.16, 0.13, 0.05) if active else PH_SURFACE))
		b.add_theme_stylebox_override("hover", _btn_style(PH_SURFACE2))
		b.add_theme_stylebox_override("pressed",
			_btn_style(Color(0.16, 0.13, 0.05)))
		b.pressed.connect(func() -> void: _set_msg_sort(mode))
		row.add_child(b)
	_root.add_child(row)


func _set_msg_sort(mode: String) -> void:
	if mode == _msg_sort:
		return
	_msg_sort = mode
	_save_msg_sort()
	_phone.set_sort(mode)  # keep the sim's remembered mode in sync
	_show_messenger()


## Sort "My Contacts" per the remembered mode, using live thread data
## (unread / uses / last_ts / answered) — same rules as SimPhone.
func _sort_messenger_contacts(contacts: Array) -> Array:
	var arr: Array = contacts.duplicate()
	match _msg_sort:
		"most_used":
			arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ta: Dictionary = _phone._thread(String(a.get("key", "")))
				var tb: Dictionary = _phone._thread(String(b.get("key", "")))
				return int(ta.get("uses", 0)) > int(tb.get("uses", 0)))
		"unread_first":
			arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ta: Dictionary = _phone._thread(String(a.get("key", "")))
				var tb: Dictionary = _phone._thread(String(b.get("key", "")))
				var au: int = int(ta.get("unread", 0))
				var bu: int = int(tb.get("unread", 0))
				if (au > 0) != (bu > 0):
					return au > bu
				return float(ta.get("last_ts", 0.0)) > float(tb.get("last_ts", 0.0)))
		_:  # latest: strict most-recent-activity-first, like iMessage —
			# whoever messaged most recently on top. (Jeremy 2026-10-06.)
			arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ta: Dictionary = _phone._thread(String(a.get("key", "")))
				var tb: Dictionary = _phone._thread(String(b.get("key", "")))
				return float(ta.get("last_ts", 0.0)) > float(tb.get("last_ts", 0.0)))
	return arr


func _show_messenger() -> void:
	# Jeremy 2026-10-03: Messenger works like a texting app — the
	# conversation list IS the threads. One row per contact with pfp,
	# name, and last-message preview; tap to open the chat.
	_screen = "messenger"
	_clear()
	_header("Messenger")
	_load_msg_sort()
	_add_sort_switcher()
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	# Pinned government section.
	box.add_child(_section("My Government"))
	for c: Dictionary in _phone.government_contacts():
		box.add_child(_conversation_row(c))
	# Jeremy 2026-10-06: faction leaders — the AI "player" of each foreign
	# faction, pinned below the government. The player's own faction has
	# no AI leader (the player is the leader), so it's excluded.
	box.add_child(_section("Faction Leaders"))
	for c: Dictionary in _phone.leader_contacts():
		box.add_child(_conversation_row(c))
	box.add_child(_section("My Contacts"))
	var mine: Array = _sort_messenger_contacts(_phone.my_contacts())
	if mine.is_empty():
		box.add_child(_empty_art("res://assets/ui/phone/empty_messenger.webp"))
		var none := Label.new()
		none.text = "No contacts yet — add people from the world."
		none.add_theme_font_size_override("font_size", FONT_SM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
	for c: Dictionary in mine:
		box.add_child(_conversation_row(c, true))
	# Jeremy 2026-10-04: enemy commanders — categorized by faction,
	# nearest faction first, faction color + distance in the header.
	# Jeremy 2026-10-05: groups arrive closest-first from the sim; the
	# header shows a friendly relative distance, not raw tile math.
	for g: Dictionary in _phone.enemy_commander_groups():
		var fcolor: Color = g.get("color", PH_TEXT)
		box.add_child(_section("%s \u00b7 %s" % [String(g.get("faction_name", "?")),
			_dist_word(int(g.get("dist_tiles", 0)))], fcolor))
		for c: Dictionary in g.get("contacts", []):
			box.add_child(_conversation_row(c))

	# Jeremy 2026-10-11: Overheard — NPC-to-NPC drama threads. Eavesdrop away.
	var _drama_list: Array = _phone.social_life.drama_threads() \
		if _phone.social_life != null else []
	if not _drama_list.is_empty():
		box.add_child(_section("Overheard \U0001F440"))
		for dd: Dictionary in _drama_list:
			box.add_child(_drama_row(dd))


## Friendly relative-distance words for contact list headers.
## The sim sorts groups closest-first; this just names the band.
func _dist_word(tiles: int) -> String:
	if tiles < 20:
		return "Very close"
	if tiles < 50:
		return "Close"
	if tiles < 100:
		return "Far"
	if tiles < 200:
		return "Very far"
	return "Across the world"


## One conversation row: pfp + name + last-message preview + unread badge.
## Tapping opens the chat — just like a texting app.
## Jeremy 2026-10-04 (polish): timestamp of the last message, like a
## real chat app ("Day 5", "Day 5 14:30").
func _conversation_row(c: Dictionary, allow_manage := false) -> PanelContainer:
	var key: String = String(c.get("key", ""))
	var u: Dictionary = _phone._unit_for_key(key)
	# Jeremy 2026-10-06: leaders have no unit — synthesize a pseudo-unit so
	# the avatar shows the leader's portrait (Jeremy 2026-10-06: every
	# leader persona has distinct pixel-art), falling back to their
	# initial in faction color if the portrait is missing.
	if u.is_empty() and bool(c.get("leader", false)):
		u = {"faction": String(c.get("faction", "humans")),
			"job": "ruler", "id": 0, "gender": "m",
			"_leader_name": String(c.get("name", "?")),
			"_leader_pfp": String(c.get("pfp", ""))}
	var th: Dictionary = _phone._thread(key)
	var msgs: Array = th.get("messages", [])
	var last: String = String(msgs.back().get("text", "")) if not msgs.is_empty() else String(c.get("sub", ""))
	if last.length() > 60:
		last = last.substr(0, 60) + "…"
	var unread: int = int(th.get("unread", 0))
	var ts := ""
	if not msgs.is_empty():
		var lm: Dictionary = msgs.back()
		var mday := int(lm.get("day", 0))
		if mday > 0:
			ts = "Day %d" % mday
	# Jeremy 2026-10-05: government contacts show their role (Adviser,
	# Guild Master...) under the name; other contacts show their job.
	var role: String = String(c.get("sub", ""))
	# Jeremy 2026-10-06 (polish round 2): long-press on a My Contacts row
	# opens the manage menu (Remove contact / Block).
	var lp := Callable()
	if allow_manage:
		var key2 := key
		lp = func(card: Control) -> void: _show_contact_menu(key2, card)
	return _thread_item(String(c.get("name", "?")), last, unread,
		func() -> void: open_thread(key), u, ts, role, lp)


## Jeremy 2026-10-06 (polish round 2): long-press contact menu —
## "Remove contact" and "Block"/"Unblock", in Bastard OS 2.0 glass.
var _contact_menu: Control = null

func _dismiss_contact_menu() -> void:
	if _contact_menu != null and is_instance_valid(_contact_menu):
		_contact_menu.queue_free()
	_contact_menu = null


func _show_contact_menu(key: String, card: Control) -> void:
	_dismiss_contact_menu()
	var u: Dictionary = _phone._unit_for_key(key)
	var uid: int = int(u.get("id", 0))
	if uid <= 0:
		return
	var nm: String = SimPersonality.display_name(u) if not u.is_empty() else key
	var blocked: bool = _phone.is_blocked(uid)
	# Dim layer — tapping anywhere outside dismisses.
	var dim := Button.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = Color(0, 0, 0, 0.45)
	dim.add_theme_stylebox_override("normal", dsb)
	dim.add_theme_stylebox_override("hover", dsb)
	dim.add_theme_stylebox_override("pressed", dsb)
	dim.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	dim.pressed.connect(_dismiss_contact_menu)
	add_child(dim)
	_contact_menu = dim
	# The menu card itself.
	var menu := PanelContainer.new()
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.11, 0.12, 0.155, 0.98)
	msb.border_color = PH_ACCENT.darkened(0.25)
	msb.set_border_width_all(2)
	msb.set_corner_radius_all(20)
	msb.content_margin_left = 20.0
	msb.content_margin_right = 20.0
	msb.content_margin_top = 16.0
	msb.content_margin_bottom = 16.0
	msb.shadow_color = Color(0, 0, 0, 0.55)
	msb.shadow_size = 16
	menu.add_theme_stylebox_override("panel", msb)
	# Jeremy 2026-10-06 (launch readiness): clamp to the phone frame —
	# the old fixed 400px menu was wider than an iPhone portrait screen
	# and rendered ~26px past the right edge.
	var mw := minf(400.0, maxf(240.0, _phone_w - 32.0))
	menu.custom_minimum_size = Vector2(mw, 0)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	menu.add_child(vbox)
	var title := Label.new()
	title.text = nm
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", FONT_MD)
	title.add_theme_color_override("font_color", PH_TEXT)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vbox.add_child(title)
	var rm := _menu_btn("Remove contact", func() -> void:
		_phone.remove_contact(uid)
		_dismiss_contact_menu()
		if _screen == "messenger":
			_show_messenger())
	vbox.add_child(rm)
	var blk := _menu_btn("Unblock" if blocked else "Block", func() -> void:
		_phone.toggle_block(uid)
		_dismiss_contact_menu()
		if _screen == "messenger":
			_show_messenger())
	vbox.add_child(blk)
	dim.add_child(menu)
	# Position near the pressed card, clamped inside the phone.
	# (Godot 4: no CanvasItem.to_local — use the inverse global transform.)
	var center: Vector2 = get_global_transform().affine_inverse() \
		* card.get_global_rect().get_center()
	var mx: float = clampf(center.x - mw / 2.0, 16.0, maxf(16.0, size.x - mw - 16.0))
	var my: float = clampf(center.y + 40.0, 16.0, maxf(16.0, size.y - 320.0))
	menu.position = Vector2(mx, my)
	_pop(menu)


## Menu-style button for popups (context menu, dialogs): full-width,
## glass, gold hairline.
func _menu_btn(label_text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = label_text
	b.custom_minimum_size = Vector2(0, 88)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", FONT_MD)
	b.add_theme_color_override("font_color", PH_TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SURFACE2
	sb.set_corner_radius_all(14)
	sb.set_border_width_all(1)
	sb.border_color = PH_DIV
	b.add_theme_stylebox_override("normal", sb)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = PH_SURFACE2.darkened(0.25)
	sb_p.border_color = PH_ACCENT.darkened(0.3)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("hover", sb_p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


func _show_thread() -> void:
	_screen = "thread"
	_clear()
	var u: Dictionary = _phone._unit_for_key(_thread_key)
	# Jeremy 2026-10-06: leaders are not world units — use the pseudo-unit
	# (name + distinct persona portrait) so the header never shows "?".
	if u.is_empty() and SimFactionLeaders.is_leader_key(_thread_key):
		u = _phone.leader_pseudo_unit(_thread_key)
	# Jeremy 2026-10-06: leader threads show the leader's name, not the raw key.
	var lname: String = _phone.leader_name_for_key(_thread_key) \
		if SimFactionLeaders.is_leader_key(_thread_key) else ""
	var name: String = lname if lname != "" \
		else (SimPersonality.display_name(u) if not u.is_empty() else _thread_key)
	var hrow := _header(name, "messenger")
	# PFP next to the name (Discord-style).
	var hp := _pfp(u, PFP_SM)
	hrow.add_child(hp)
	hrow.move_child(hp, 1)
	# Jeremy 2026-10-04: profile + block as small header buttons, NOT giant
	# full-width buttons (they ate half the screen like a bad settings page).
	# Jeremy 2026-10-06 (launch readiness): they live in their own row under
	# the header — back + pfp + three buttons overflowed the ~330px header
	# on iPhone portrait and pushed the rightmost buttons off-screen.
	if not u.is_empty():
		var act_row := HBoxContainer.new()
		act_row.add_theme_constant_override("separation", 8)
		act_row.alignment = BoxContainer.ALIGNMENT_CENTER
		var uid: int = int(u.get("id", 0))
		var blocked: bool = _phone.is_blocked(uid)
		var prof := _small_header_btn("Profile", func() -> void: open_profile(_thread_key))
		prof.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act_row.add_child(prof)
		var blk := _small_header_btn("Unblock" if blocked else "Block",
			func() -> void:
				_phone.toggle_block(uid)
				_show_thread())
		blk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		act_row.add_child(blk)
		# Jeremy 2026-10-06 (polish round 2): add-to-contacts in the chat
		# header — toggles the NPC in/out of My Contacts.
		if uid > 0 and not SimFactionLeaders.is_leader_key(_thread_key):
			var is_c: bool = _phone.is_contact(uid)
			var addb := _small_header_btn("Added" if is_c else "Add to contacts",
				func() -> void:
					if _phone.is_contact(uid):
						_phone.remove_contact(uid)
					else:
						_phone.add_contact(uid)
					_show_thread())
			addb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			act_row.add_child(addb)
		_root.add_child(act_row)
	# Jeremy 2026-10-06: relationship meter under the name block (HTML
	# CANDIDATE54 parity) — slim track + tiny caption showing how much
	# this NPC likes/dislikes the ruler. Rebuilt every thread render so
	# it can never go stale.
	if not u.is_empty():
		_root.add_child(_affinity_meter(u))
	# Jeremy 2026-10-05: likes/dislikes collapse into an "About" row so the
	# chat opens on the conversation, not a wall of text.
	if not u.is_empty():
		var likes_panel: Control = _likes_bar(u)
		likes_panel.visible = false
		var about_btn := _small_header_btn("About", func() -> void:
			likes_panel.visible = not likes_panel.visible)
		_root.add_child(about_btn)
		_root.add_child(likes_panel)
	var sc := _scroll()
	_thread_scroll = sc
	var box: VBoxContainer = sc.get_child(0)
	_thread_box = box
	# Jeremy 2026-10-05: real texting-app rhythm — tight inside a sender run,
	# breathing room when the speaker changes.
	box.add_theme_constant_override("separation", 4)
	var th: Dictionary = _phone._thread(_thread_key)
	var last_day: int = -1
	_receipt_labels.clear()
	var msgs: Array = th.get("messages", [])
	for mi in msgs.size():
		var m: Dictionary = msgs[mi]
		var sent: bool = String(m.get("from", "")) == "player"
		if mi > 0:
			var prev_sent: bool = String(msgs[mi - 1].get("from", "")) == "player"
			if prev_sent != sent:
				var gap := Control.new()
				gap.custom_minimum_size = Vector2(0, 10)
				gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
				box.add_child(gap)
		var mday: int = int(m.get("day", 0))
		# Day divider when the day changes — "Today"/"Yesterday"/"Day N"
		# like a real messenger.
		if mday != last_day and mday > 0:
			box.add_child(_day_divider(_day_label(mday)))
			last_day = mday
		# Avatar + timestamp on the last bubble of a run, like real chat apps.
		var av: Control = null
		var tsl := ""
		var run_end := false
		if mi + 1 < msgs.size():
			run_end = String(msgs[mi + 1].get("from", "")) == "player" \
				if not sent else String(msgs[mi + 1].get("from", "")) != "player"
		else:
			run_end = true
		if not sent and not u.is_empty() and run_end:
			av = _pfp(u, 72.0)
		if run_end:
			tsl = _msg_time_label(float(m.get("ts", 0.0)))
		box.add_child(_bubble(String(m.get("text", "")), sent, av, tsl))
		# Jeremy 2026-10-04: read receipts under player messages —
		# "Sending..." → "Delivered" → "Read".
		if sent:
			var rl := _receipt_label(String(m.get("status", "")))
			box.add_child(rl)
			_receipt_labels.append(rl)
		else:
			_receipt_labels.append(null)
	# Jeremy 2026-10-07 (graphics/UI hourly): a pending war-counsel plea /
	# debate / peace-terms counter for this advisor gets inline Accept/Deny
	# buttons — tap beats typing "accept"/"deny" on iPhone. The buttons send
	# through the exact same path as a typed verdict (zero sim changes).
	var counsel_uid := _counsel_pending_uid()
	if counsel_uid > 0:
		box.add_child(_counsel_button_row(counsel_uid))
	# Wake deep-work 2026-10-08 (Disaster #26): Prince Gnomba's live con
	# gets inline [Send 500g] / [Block & Report] buttons while the scam
	# is pending — tap beats typing on iPhone. The buttons send the
	# same words a typed verdict would (zero sim changes in the UI).
	var gnomba_uid := _gnomba_pending_uid()
	if gnomba_uid > 0:
		box.add_child(_gnomba_button_row(gnomba_uid))
	# Rapid-iteration 2026-10-08 (Disaster #29): Milo the Podcast Bro's
	# live sponsor offer gets inline [Sponsor 300g] / [Unplug] buttons
	# while the offer is pending — tap beats typing on iPhone. Same
	# pattern as the Gnomba con row: the buttons send the same words a
	# typed verdict would (zero sim changes in the UI).
	var podcast_uid := _podcast_pending_uid()
	if podcast_uid > 0:
		box.add_child(_podcast_button_row(podcast_uid))
	_phone.read_thread_key(_thread_key)
	# Jeremy 2026-10-04: if the NPC is already typing when the thread opens
	# (e.g. reply queued), show the indicator immediately.
	if _phone.is_typing(_thread_key):
		_show_typing_indicator()
	_scroll_thread_to_bottom()
	# Send box — rounded pill input, circular blue send button, hairline above.
	var div := ColorRect.new()
	div.color = PH_DIV
	div.custom_minimum_size = Vector2(0, 2)
	_root.add_child(div)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var entry := _line_edit("Message")
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(entry)
	# Jeremy 2026-10-04: Send key on the keyboard (custom or hardware) must
	# send the message, same as the blue send button.
	var do_send := func() -> void:
		var txt: String = entry.text
		if txt.strip_edges() == "":
			return
		entry.text = ""
		# Jeremy 2026-10-06: leader threads route through the leader
		# messaging queue (was silently dropped before).
		if SimFactionLeaders.is_leader_key(_thread_key):
			_phone.send_leader_message(
				SimFactionLeaders.faction_for_key(_thread_key), txt)
			_show_thread()
			return
		var uid2: int = int(_thread_key.trim_prefix("u")) if _thread_key.begins_with("u") else 0
		if uid2 > 0:
			_phone.send_message(uid2, txt)
		_show_thread()
	var send := _round_send_btn(do_send)
	# Jeremy 2026-10-06 (polish round 2): send feels alive — the button
	# pops and gold sparks fly on every press. (Separate connection:
	# do_send's lambda can't capture `send` before it exists.)
	send.pressed.connect(func() -> void:
		_pop(send)
		_fx_burst(send))
	entry.text_submitted.connect(func(_t: String) -> void: do_send.call())
	_kb_send_hook = do_send
	row.add_child(send)
	_root.add_child(row)


## Jeremy 2026-10-07 (graphics/UI hourly): war-counsel pleas arrive as
## Messenger text ("reply ACCEPT ... or DENY") — on a phone, tapping beats
## typing for a binary verdict. Returns the advisor's unit id when the sim
## holds a pending plea, advisor debate, or peace-terms counter for this
## thread's advisor, else 0. Pure read — never mutates sim state.
func _counsel_pending_uid() -> int:
	if _gs == null or _phone == null:
		return 0
	if not _thread_key.begins_with("u"):
		return 0
	var uid: int = int(_thread_key.trim_prefix("u"))
	if uid <= 0:
		return 0
	var rv = _gs.rulers_voice
	if rv == null or not rv.has_method("_pending_plea_for"):
		return 0
	if not (rv._pending_counter_for(uid) as Dictionary).is_empty():
		return uid
	if not (rv._pending_debate_for(uid) as Dictionary).is_empty():
		return uid
	if not (rv._pending_plea_for(uid) as Dictionary).is_empty():
		return uid
	return 0


## Inline Accept / Deny row for a pending war-counsel verdict. Styled like
## the other phone buttons (BTN_H touch target, rounded, tinted by verdict).
func _counsel_button_row(uid: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var accept_b := _btn("Accept", func() -> void: _counsel_answer(uid, "accept"))
	accept_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_b.add_theme_stylebox_override("normal",
		_btn_style(Color(0.14, 0.32, 0.16)))
	accept_b.add_theme_stylebox_override("hover",
		_btn_style(Color(0.18, 0.40, 0.20)))
	accept_b.add_theme_stylebox_override("pressed",
		_btn_style(Color(0.10, 0.24, 0.12)))
	var deny_b := _btn("Deny", func() -> void: _counsel_answer(uid, "deny"))
	deny_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deny_b.add_theme_stylebox_override("normal",
		_btn_style(Color(0.36, 0.15, 0.15)))
	deny_b.add_theme_stylebox_override("hover",
		_btn_style(Color(0.44, 0.19, 0.19)))
	deny_b.add_theme_stylebox_override("pressed",
		_btn_style(Color(0.28, 0.11, 0.11)))
	# Tap tactility, same as the send button (pop on press).
	accept_b.pressed.connect(func() -> void: _pop(accept_b))
	deny_b.pressed.connect(func() -> void: _pop(deny_b))
	row.add_child(accept_b)
	row.add_child(deny_b)
	return row


## A tapped verdict goes through the identical path as typing it:
## SimPhone.send_message -> _npc_reply -> SimRulersVoice.try_order, so the
## plea / debate / counter is answered exactly like a typed "accept"/"deny".
func _counsel_answer(uid: int, verdict: String) -> void:
	_phone.send_message(uid, verdict)
	_show_thread()


## Wake deep-work 2026-10-08 (Disaster #26): returns the unit id when this
## Messenger thread is Prince Gnomba with a live con, else 0. Pure read —
## never mutates sim state.
func _gnomba_pending_uid() -> int:
	if _gs == null or _phone == null:
		return 0
	if not _thread_key.begins_with("u"):
		return 0
	var uid: int = int(_thread_key.trim_prefix("u"))
	if uid <= 0:
		return 0
	var ds = _gs.get("disasters")
	if ds == null or not ds.has_method("gnomba_scam_pending"):
		return 0
	if bool(ds.gnomba_scam_pending(uid)):
		return uid
	return 0


## Inline [Send 500g] / [Block & Report] row for Prince Gnomba's live con.
## Styled like the counsel verdict buttons (BTN_H touch target, rounded).
func _gnomba_button_row(uid: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var send_b := _btn("Send 500g", func() -> void: _gnomba_answer(uid, "send"))
	send_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_b.add_theme_stylebox_override("normal",
		_btn_style(Color(0.32, 0.24, 0.08)))
	send_b.add_theme_stylebox_override("hover",
		_btn_style(Color(0.40, 0.30, 0.10)))
	send_b.add_theme_stylebox_override("pressed",
		_btn_style(Color(0.24, 0.18, 0.06)))
	var block_b := _btn("Block & Report", func() -> void: _gnomba_answer(uid, "block"))
	block_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block_b.add_theme_stylebox_override("normal",
		_btn_style(Color(0.36, 0.15, 0.15)))
	block_b.add_theme_stylebox_override("hover",
		_btn_style(Color(0.44, 0.19, 0.19)))
	block_b.add_theme_stylebox_override("pressed",
		_btn_style(Color(0.28, 0.11, 0.11)))
	# Tap tactility, same as the counsel buttons (pop on press).
	send_b.pressed.connect(func() -> void: _pop(send_b))
	block_b.pressed.connect(func() -> void: _pop(block_b))
	row.add_child(send_b)
	row.add_child(block_b)
	return row


## A tapped scam verdict goes through the identical path as typing it:
## SimPhone.send_message -> _npc_reply -> DisasterSim.gnomba_scam_reply.
func _gnomba_answer(uid: int, verdict: String) -> void:
	_phone.send_message(uid, verdict)
	_show_thread()


func _podcast_pending_uid() -> int:
	if _gs == null or _phone == null:
		return 0
	if not _thread_key.begins_with("u"):
		return 0
	var uid: int = int(_thread_key.trim_prefix("u"))
	if uid <= 0:
		return 0
	var ds = _gs.get("disasters")
	if ds == null or not ds.has_method("podcast_offer_pending"):
		return 0
	if bool(ds.podcast_offer_pending(uid)):
		return uid
	return 0


## Inline [Sponsor 300g] / [Unplug] row for Milo's live sponsor offer.
## Styled like the Gnomba con buttons (BTN_H touch target, rounded).
func _podcast_button_row(uid: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var sponsor_b := _btn("Sponsor 300g", func() -> void: _podcast_answer(uid, "sponsor"))
	sponsor_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sponsor_b.add_theme_stylebox_override("normal",
		_btn_style(Color(0.16, 0.35, 0.16)))
	sponsor_b.add_theme_stylebox_override("hover",
		_btn_style(Color(0.20, 0.43, 0.20)))
	sponsor_b.add_theme_stylebox_override("pressed",
		_btn_style(Color(0.12, 0.27, 0.12)))
	var unplug_b := _btn("Unplug", func() -> void: _podcast_answer(uid, "unplug"))
	unplug_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	unplug_b.add_theme_stylebox_override("normal",
		_btn_style(Color(0.36, 0.15, 0.15)))
	unplug_b.add_theme_stylebox_override("hover",
		_btn_style(Color(0.44, 0.19, 0.19)))
	unplug_b.add_theme_stylebox_override("pressed",
		_btn_style(Color(0.28, 0.11, 0.11)))
	# Tap tactility, same as the counsel buttons (pop on press).
	sponsor_b.pressed.connect(func() -> void: _pop(sponsor_b))
	unplug_b.pressed.connect(func() -> void: _pop(unplug_b))
	row.add_child(sponsor_b)
	row.add_child(unplug_b)
	return row


## A tapped offer verdict goes through the identical path as typing it:
## SimPhone.send_message -> _npc_reply -> DisasterSim.podcast_offer_reply.
func _podcast_answer(uid: int, verdict: String) -> void:
	_phone.send_message(uid, verdict)
	_show_thread()


## Jeremy 2026-10-04: read-receipt label under a player message bubble.
## Right-aligned, tiny gray text: "Sending..." / "Delivered" / "Read".
func _receipt_label(status: String) -> Label:
	var rl := Label.new()
	rl.text = _receipt_text(status)
	rl.add_theme_font_size_override("font_size", FONT_XS)
	rl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return rl


## Jeremy 2026-10-04: display text for a message status.
func _receipt_text(status: String) -> String:
	match status:
		"sending":
			return "Sending..."
		"delivered":
			return "Delivered"
		"seen":
			return "Read"
		_:
			return ""


## Jeremy 2026-10-04: scroll the open thread to the bottom (latest message).
func _scroll_thread_to_bottom() -> void:
	if _thread_scroll == null or not is_instance_valid(_thread_scroll):
		return
	if not is_inside_tree():
		return  # headless test: get_tree() errors instead of returning
		# null when the phone UI isn't inside a tree, so check first.
	var sc := _thread_scroll
	# Defer a frame so the new content has laid out.
	await get_tree().process_frame
	if not is_instance_valid(sc):
		return
	_snap_thread_to_bottom()


## Jeremy 2026-10-06: synchronous tail of _scroll_thread_to_bottom,
## extracted so headless tests can verify the snap math without awaiting
## a frame (SceneTree test scripts avoid awaits).
func _snap_thread_to_bottom() -> void:
	if _thread_scroll == null or not is_instance_valid(_thread_scroll):
		return
	var bar := _thread_scroll.get_v_scroll_bar()
	if bar != null:
		_thread_scroll.scroll_vertical = int(bar.max_value)


## Jeremy 2026-10-04: fade a new chat row in (messages feel alive, not static).
func _fade_in_row(c: Control) -> void:
	# Jeremy 2026-10-06: NEVER animate position on a container child — the
	# VBox hasn't laid out the new row yet, so position.y is stale and the
	# tween fights the layout, leaving bubbles overlapped. Fade + subtle
	# scale are layout-safe.
	if c == null or not is_instance_valid(c):
		return
	c.modulate.a = 0.0
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.96, 0.96)
	var tw := c.create_tween()
	tw.set_parallel(true)
	tw.tween_property(c, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(c, "scale", Vector2.ONE, 0.24)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## Jeremy 2026-10-06 (polish round 2): tiny tactile pop for tappable
## controls — scale dip and spring back. Cheap, 60fps-safe.
func _pop(c: Control) -> void:
	if c == null or not is_instance_valid(c) or not c.is_inside_tree():
		return
	c.pivot_offset = c.size / 2.0
	var tw := c.create_tween()
	tw.tween_property(c, "scale", Vector2(0.9, 0.9), 0.07)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(c, "scale", Vector2.ONE, 0.14)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Jeremy 2026-10-06 (polish round 2): one-shot gold sparkle burst —
## message sends, notification arrivals, boot. CPUParticles2D keeps it
## cheap on the iPhone 17 web build; auto-frees after firing.
func _fx_burst(anchor: Control, color: Color = Color(0.95, 0.78, 0.35)) -> void:
	if anchor == null or not is_instance_valid(anchor) \
			or not is_inside_tree():
		return
	var p := CPUParticles2D.new()
	p.amount = 14
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.9
	p.spread = 180.0
	p.initial_velocity_min = 90.0
	p.initial_velocity_max = 230.0
	p.gravity = Vector2(0, 170)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	p.color = color
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 8.0
	p.z_index = 200
	p.position = get_global_transform().affine_inverse() \
		* anchor.get_global_rect().get_center()
	add_child(p)
	p.emitting = true
	var tree := get_tree()
	if tree != null:
		tree.create_timer(1.4).timeout.connect(p.queue_free,
			CONNECT_ONE_SHOT)


## Jeremy 2026-10-04: show the "X is typing..." indicator at the end of the
## open thread, with animated dots.
func _show_typing_indicator() -> void:
	if _thread_box == null or not is_instance_valid(_thread_box):
		return
	if _typing_row != null and is_instance_valid(_typing_row):
		return  # already showing
	var u: Dictionary = _phone._unit_for_key(_thread_key) if _phone != null else {}
	var nm: String = SimPersonality.display_name(u) if not u.is_empty() else "NPC"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var bubble := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SURFACE2
	sb.set_corner_radius_all(18)
	sb.corner_radius_top_left = 6
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	bubble.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var lab := Label.new()
	lab.text = "%s is typing" % nm
	lab.add_theme_font_size_override("font_size", FONT_MD)
	lab.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	h.add_child(lab)
	_typing_dots = Label.new()
	_typing_dots.text = ""
	_typing_dots.add_theme_font_size_override("font_size", FONT_MD)
	_typing_dots.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	h.add_child(_typing_dots)
	bubble.add_child(h)
	row.add_child(bubble)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	_thread_box.add_child(row)
	_typing_row = row
	_fade_in_row(row)
	# Animate the dots: "", ".", "..", "..." cycling.
	_typing_dot_n = 0
	if _typing_timer == null or not is_instance_valid(_typing_timer):
		_typing_timer = Timer.new()
		_typing_timer.wait_time = 0.4
		_typing_timer.timeout.connect(_on_typing_tick)
		add_child(_typing_timer)
	_typing_timer.start()
	_scroll_thread_to_bottom()


## Jeremy 2026-10-04: advance the typing-indicator dots animation.
func _on_typing_tick() -> void:
	if _typing_dots == null or not is_instance_valid(_typing_dots):
		return
	_typing_dot_n = (_typing_dot_n + 1) % 4
	_typing_dots.text = ".".repeat(_typing_dot_n)


## Jeremy 2026-10-04: hide the typing indicator (reply arrived or thread closed).
func _hide_typing_indicator() -> void:
	if _typing_timer != null and is_instance_valid(_typing_timer):
		_typing_timer.stop()
	_typing_dots = null
	if _typing_row != null and is_instance_valid(_typing_row):
		_typing_row.queue_free()
	_typing_row = null


## Jeremy 2026-10-04: live messaging — an NPC reply arrived. If the matching
## thread is open, append it with a fade-in instead of waiting for the next
## player message (the old broken behavior).
func _on_bus_phone_message(key: String, _text: String) -> void:
	if not visible:
		return
	# Jeremy 2026-10-06: a new message re-sorts the thread list — the
	# active thread jumps to the top (latest-activity-first).
	if _screen == "messenger":
		_show_messenger()
		return
	if _screen != "thread" or key != _thread_key:
		return
	if _thread_box == null or not is_instance_valid(_thread_box):
		return
	_hide_typing_indicator()
	var th: Dictionary = _phone._thread(key)
	var msgs: Array = th.get("messages", [])
	if msgs.is_empty():
		return
	var m: Dictionary = msgs[msgs.size() - 1]
	var sent: bool = String(m.get("from", "")) == "player"
	if msgs.size() > 1:
		var prev_sent: bool = String(msgs[msgs.size() - 2].get("from", "")) == "player"
		if prev_sent != sent:
			var lgap := Control.new()
			lgap.custom_minimum_size = Vector2(0, 10)
			lgap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_thread_box.add_child(lgap)
	# A live message is always the last of its run — avatar + timestamp.
	var lav: Control = null
	if not sent:
		var lu: Dictionary = _phone._unit_for_key(key)
		if not lu.is_empty():
			lav = _pfp(lu, 72.0)
	var bubble := _bubble(String(m.get("text", "")), sent, lav,
		_msg_time_label(float(m.get("ts", 0.0))))
	_thread_box.add_child(bubble)
	_receipt_labels.append(null)
	_fade_in_row(bubble)
	# The open thread is being read — mark the new message seen.
	_phone.read_thread_key(key)
	_scroll_thread_to_bottom()


## Jeremy 2026-10-04: live messaging — NPC started/stopped typing.
func _on_bus_phone_typing(key: String, typing: bool) -> void:
	if not visible:
		return
	if _screen != "thread" or key != _thread_key:
		return
	if typing:
		_show_typing_indicator()
	else:
		_hide_typing_indicator()


## Jeremy 2026-10-04: live messaging — a message status changed
## ("sending" → "delivered" → "seen"). Update the receipt label live.
func _on_bus_phone_message_status(key: String, index: int, status: String) -> void:
	if not visible:
		return
	if _screen != "thread" or key != _thread_key:
		return
	var th: Dictionary = _phone._thread(key)
	var msgs: Array = th.get("messages", [])
	if index >= 0:
		# Single message update.
		if index < _receipt_labels.size():
			var rl = _receipt_labels[index]
			if rl != null and is_instance_valid(rl):
				(rl as Label).text = _receipt_text(status)
	else:
		# Bulk update (e.g. all "sending" → "delivered"): refresh all.
		for mi in mini(msgs.size(), _receipt_labels.size()):
			var m: Dictionary = msgs[mi]
			var rl2 = _receipt_labels[mi]
			if rl2 != null and is_instance_valid(rl2):
				(rl2 as Label).text = _receipt_text(String(m.get("status", "")))


## Jeremy 2026-10-08 (graphics hourly): Squabble live feed — an NPC (or
## the ruler) posting while the feed is open inserts the new card at the
## top instantly, with the same fade as live chat messages. The compose
## box keeps its text (no screen rebuild), and the trending row refreshes
## on the next open. Tag-filtered views stay poll-based for now.
func _on_bus_squabble_post(post: Dictionary) -> void:
	if not visible:
		return
	if _screen != "squabble":
		return
	if _squabble_box == null or not is_instance_valid(_squabble_box):
		return
	# Respect blocks: a blocked author's posts never render in the UI.
	if _phone.is_blocked_key(String(post.get("author_key", ""))):
		return
	# The feed was empty — drop the placeholder so the first real post
	# doesn't render under "The kingdom is suspiciously quiet."
	for c: Node in _squabble_box.get_children():
		if c.has_meta("squabble_empty"):
			_squabble_box.remove_child(c)
			c.queue_free()
	var card: PanelContainer = _post_card(post)
	_squabble_box.add_child(card)
	_squabble_box.move_child(card, 0)
	_fade_in_row(card)


## Jeremy 2026-10-04: tool/shop petition chain — the faction adviser asks
## the PLAYER for permission to build a shop. Shows even when the phone
## app is closed (it's a system-level modal, like the war confirm).
func _on_bus_build_request(petition: Dictionary) -> void:
	if _gs == null:
		return
	# Open the phone (it may be closed) — the modal goes on top of it.
	visible = true
	show_build_request(petition)


## Jeremy 2026-10-06 (launch readiness): system-modal registry. Every
## system modal registers on show and unregisters on dismiss; _build_shell()
## snapshots the registry before freeing children (rotation) and re-shows
## each still-valid modal after the rebuild.
func _register_modal(entry: Dictionary, overlay: Control) -> void:
	_modal_seq += 1
	entry["_seq"] = _modal_seq
	entry["overlay"] = overlay
	_open_modals.append(entry)


func _unregister_modal(overlay: Control) -> void:
	for i in range(_open_modals.size() - 1, -1, -1):
		if (_open_modals[i] as Dictionary).get("overlay") == overlay:
			_open_modals.remove_at(i)
			return


## Dismiss a system modal: unregister FIRST (so the rebuild snapshot never
## resurrects a decided modal), then free. All four system modals route
## their button dismissals through here.
func _dismiss_modal(overlay: Control) -> void:
	_unregister_modal(overlay)
	if is_instance_valid(overlay):
		overlay.queue_free()


## Snapshot the open system modals before _build_shell() frees them.
## Text the player already typed (insult input) is captured so it survives
## the rotation; the freed entry node itself is never carried forward.
func _snapshot_modals() -> Array:
	var out: Array = []
	for e: Dictionary in _open_modals:
		var snap := {
			"type": String(e.get("type", "")),
			"pid": int(e.get("pid", -1)),
			"action": String(e.get("action", "")),
			"faction": String(e.get("faction", "")),
			"faction_name": String(e.get("faction_name", "")),
			"question": String(e.get("question", "")),
			"confirm_text": String(e.get("confirm_text", "")),
			"on_confirm": e.get("on_confirm", Callable()),
			"draft": "",
		}
		if String(e.get("type", "")) == "diplo_insult":
			# Launch readiness 2026-10-06: validity BEFORE the cast — `as`
			# on a freed entry aborts the whole snapshot (SCRIPT ERROR),
			# which would silently drop every other open modal on rotation.
			var raw_entry = e.get("entry")
			if is_instance_valid(raw_entry) and raw_entry is LineEdit:
				snap["draft"] = (raw_entry as LineEdit).text
		out.append(snap)
	return out


## Re-show a snapshot modal after a shell rebuild. Petitions/proposals that
## are no longer open (decided or expired) are skipped — the modal must
## never come back for a settled decision.
func _reshow_modal(r: Dictionary) -> void:
	if _gs == null:
		return
	match String(r.get("type", "")):
		"build_request":
			var pet := _find_petition(int(r.get("pid", -1)))
			if not pet.is_empty() \
					and String(pet.get("status", "")) == "open":
				show_build_request(pet)
		"strategic_proposal":
			var props = _gs.get("proposals")
			if props != null:
				var p: Dictionary = props.get_proposal(int(r.get("pid", -1)))
				if not p.is_empty() \
						and String(p.get("status", "")) == "open":
					show_strategic_proposal(p)
		"diplo_confirm":
			var oc: Callable = r.get("on_confirm", Callable())
			if oc.is_valid():
				_diplo_confirm(String(r.get("action", "")),
					String(r.get("faction_name", "")),
					String(r.get("question", "")),
					String(r.get("confirm_text", "")), oc)
		"diplo_insult":
			_diplo_insult_input(String(r.get("faction", "")),
				String(r.get("faction_name", "")), String(r.get("draft", "")))


## Find a shop-build petition by id (for modal restore after rotation).
func _find_petition(pid: int) -> Dictionary:
	if _gs == null or _gs.get("petitions") == null:
		return {}
	for p: Dictionary in _gs.petitions.petitions:
		if int(p.get("id", -1)) == pid:
			return p
	return {}


## Jeremy 2026-10-04: Approve/Deny modal for a shop-build petition.
## Same overlay pattern as _diplo_confirm, neutral gold styling.
func show_build_request(petition: Dictionary) -> void:
	var pid := int(petition.get("id", -1))
	if pid < 0 or _gs == null:
		return
	var btype: String = String(petition.get("building_type", "shop"))
	var bname := String(SimBuildings.BUILDINGS.get(btype, {}).get("name",
		btype.capitalize()))
	var adviser_nm := "Your adviser"
	var adv_id := int(petition.get("reviewed_by", -1))
	if adv_id >= 0:
		var adv: Dictionary = _gs.get_unit(adv_id)
		if not adv.is_empty():
			var mn: String = String(
				(adv.get("mind", {}) as Dictionary).get("name", ""))
			if mn != "":
				adviser_nm = mn + " (Adviser)"
	var cost_bits: Array[String] = []
	var costs: Dictionary = SimBuildings.cost_of(btype)
	for r: String in costs.keys():
		cost_bits.append("%d %s" % [int(costs[r]), r])
	var cost_text := ", ".join(cost_bits) if not cost_bits.is_empty() \
		else "nothing"
	var question := "%s requests permission to build a %s.\nCost: %s." \
		% [adviser_nm, bname, cost_text]
	# Full-screen dim overlay (blocks input to everything behind).
	var overlay := PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0, 0, 0, 0.75)
	overlay.add_theme_stylebox_override("panel", osb)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var dlg := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = PH_SURFACE
	dsb.border_color = PH_ACCENT
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(20)
	dsb.content_margin_left = 28.0
	dsb.content_margin_right = 28.0
	dsb.content_margin_top = 28.0
	dsb.content_margin_bottom = 28.0
	dlg.add_theme_stylebox_override("panel", dsb)
	dlg.custom_minimum_size = Vector2(_modal_width(), 0)
	center.add_child(dlg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dlg.add_child(vbox)
	var title := Label.new()
	title.text = "Build Request"
	title.add_theme_font_size_override("font_size", FONT_LG)
	title.add_theme_color_override("font_color", PH_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var q := Label.new()
	q.text = question
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.add_theme_font_size_override("font_size", FONT_MD)
	q.add_theme_color_override("font_color", PH_TEXT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(q)
	var deny := Button.new()
	deny.text = "Deny"
	deny.custom_minimum_size = Vector2(0, 110)
	deny.add_theme_font_size_override("font_size", FONT_MD)
	deny.add_theme_color_override("font_color", PH_TEXT)
	var dsb2 := StyleBoxFlat.new()
	dsb2.bg_color = PH_SURFACE2
	dsb2.set_corner_radius_all(14)
	deny.add_theme_stylebox_override("normal", dsb2)
	var dsb2_p := dsb2.duplicate() as StyleBoxFlat
	dsb2_p.bg_color = PH_SURFACE2.darkened(0.2)
	deny.add_theme_stylebox_override("pressed", dsb2_p)
	deny.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	deny.pressed.connect(func() -> void:
		_dismiss_modal(overlay)
		if _gs != null and _gs.get("petitions") != null:
			_gs.petitions.resolve_petition(pid, false, "player"))
	vbox.add_child(deny)
	var yes := Button.new()
	yes.text = "Approve"
	yes.custom_minimum_size = Vector2(0, 110)
	yes.add_theme_font_size_override("font_size", FONT_MD)
	yes.add_theme_color_override("font_color", Color(1, 1, 1))
	var ysb := StyleBoxFlat.new()
	ysb.bg_color = Color(0.30, 0.55, 0.28)  # green — constructive
	ysb.set_corner_radius_all(14)
	yes.add_theme_stylebox_override("normal", ysb)
	var ysb_p := ysb.duplicate() as StyleBoxFlat
	ysb_p.bg_color = Color(0.30, 0.55, 0.28).darkened(0.2)
	yes.add_theme_stylebox_override("pressed", ysb_p)
	yes.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	yes.pressed.connect(func() -> void:
		_dismiss_modal(overlay)
		if _gs != null and _gs.get("petitions") != null:
			_gs.petitions.resolve_petition(pid, true, "player"))
	vbox.add_child(yes)
	# Jeremy 2026-10-10 (menu-scroll audit): cap dialog height + scroll.
	_cap_modal_scroll(dlg, vbox)
	# Add on top of everything (sibling of screen content, not inside it).
	add_child(overlay)
	overlay.move_to_front()
	_register_modal({"type": "build_request", "pid": pid}, overlay)


## Jeremy 2026-10-04: strategic proposal protocol ("AI plays the game,
## player approves") — an adviser asks the PLAYER for a major decision.
## Shows even when the phone app is closed (system-level modal, like the
## war confirm and the build request modal).
func _on_bus_strategic_proposal(proposal: Dictionary) -> void:
	if _gs == null:
		return
	# Open the phone (it may be closed) — the modal goes on top of it.
	visible = true
	show_strategic_proposal(proposal)


## Jeremy 2026-10-11: war-spare fate vote interrupts with a full-screen
## tally modal. The phone opens if closed — this is a real interrupt.
func _on_bus_spare_vote_started(vote: Dictionary) -> void:
	if _gs == null:
		return
	visible = true
	PhoneWarSpare.show_fate_vote(self, vote)


## Jeremy 2026-10-11: a signed peace treaty pops up on screen — but only
## when the player is party to it (no modal spam for AI-vs-AI treaties).
func _on_bus_treaty_signed(treaty: Dictionary) -> void:
	if _gs == null:
		return
	var pf: String = _gs.player_faction
	if String(treaty.get("loser", "")) != pf \
			and String(treaty.get("taker", "")) != pf:
		return
	visible = true
	PhoneWarSpare.show_treaty(self, treaty)


## Jeremy 2026-10-11: disaster-aid vote interrupts with a full-screen modal.
func _on_bus_aid_vote_started(vote: Dictionary) -> void:
	if _gs == null:
		return
	visible = true
	PhoneWarSpare.show_aid_vote(self, vote)


## Approve/Deny modal for a strategic proposal. Same overlay pattern as
## show_build_request, war-council red styling for war/assault kinds.
func show_strategic_proposal(proposal: Dictionary) -> void:
	var pid := int(proposal.get("id", -1))
	if pid < 0 or _gs == null:
		return
	var tq: Array = _strategic_title_question(proposal)
	var title_text: String = tq[0]
	var question: String = tq[1]
	var kind: String = String(proposal.get("kind", ""))
	# Full-screen dim overlay (blocks input to everything behind).
	var overlay := PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0, 0, 0, 0.75)
	overlay.add_theme_stylebox_override("panel", osb)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var dlg := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = PH_SURFACE
	dsb.border_color = Color(0.75, 0.25, 0.22) if kind in ["declare_war",
		"monastery_assault", "command_post_assault",
		"siege_choice"] else PH_ACCENT
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(20)
	dsb.content_margin_left = 28.0
	dsb.content_margin_right = 28.0
	dsb.content_margin_top = 28.0
	dsb.content_margin_bottom = 28.0
	dlg.add_theme_stylebox_override("panel", dsb)
	dlg.custom_minimum_size = Vector2(_modal_width(), 0)
	center.add_child(dlg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dlg.add_child(vbox)
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", FONT_LG)
	title.add_theme_color_override("font_color",
		Color(0.95, 0.45, 0.40) if kind in ["declare_war",
			"monastery_assault", "command_post_assault",
			"siege_choice"] else PH_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	var q := Label.new()
	q.text = question
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.add_theme_font_size_override("font_size", FONT_MD)
	q.add_theme_color_override("font_color", PH_TEXT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(q)
	# Jeremy 2026-10-06: advisors present REASONS, not verdicts. War/peace
	# proposals carry a strategic brief (strength ratios, enemy weakness,
	# treasury runway) computed by SimProposals — show the scouts' case
	# between the question and the buttons so the decision is informed.
	var brief_text := String(
		(proposal.get("details", {}) as Dictionary).get("brief", ""))
	if brief_text != "":
		var brief := Label.new()
		brief.text = brief_text
		brief.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		brief.add_theme_font_size_override("font_size", FONT_SM)
		brief.add_theme_color_override("font_color", PH_TEXT_DIM)
		brief.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(brief)
	var deny := Button.new()
	deny.text = "Deny"
	deny.custom_minimum_size = Vector2(0, 110)
	deny.add_theme_font_size_override("font_size", FONT_MD)
	deny.add_theme_color_override("font_color", PH_TEXT)
	var dsb2 := StyleBoxFlat.new()
	dsb2.bg_color = PH_SURFACE2
	dsb2.set_corner_radius_all(14)
	deny.add_theme_stylebox_override("normal", dsb2)
	var dsb2_p := dsb2.duplicate() as StyleBoxFlat
	dsb2_p.bg_color = PH_SURFACE2.darkened(0.2)
	deny.add_theme_stylebox_override("pressed", dsb2_p)
	deny.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	deny.pressed.connect(func() -> void:
		_dismiss_modal(overlay)
		if _gs != null and _gs.get("proposals") != null:
			_gs.proposals.resolve_proposal(pid, false, "player"))
	vbox.add_child(deny)
	var yes := Button.new()
	yes.text = "Approve"
	yes.custom_minimum_size = Vector2(0, 110)
	yes.add_theme_font_size_override("font_size", FONT_MD)
	yes.add_theme_color_override("font_color", Color(1, 1, 1))
	var ysb := StyleBoxFlat.new()
	ysb.bg_color = Color(0.30, 0.55, 0.28)  # green — constructive
	ysb.set_corner_radius_all(14)
	yes.add_theme_stylebox_override("normal", ysb)
	var ysb_p := ysb.duplicate() as StyleBoxFlat
	ysb_p.bg_color = Color(0.30, 0.55, 0.28).darkened(0.2)
	yes.add_theme_stylebox_override("pressed", ysb_p)
	yes.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	yes.pressed.connect(func() -> void:
		_dismiss_modal(overlay)
		if _gs != null and _gs.get("proposals") != null:
			_gs.proposals.resolve_proposal(pid, true, "player"))
	vbox.add_child(yes)
	# Jeremy 2026-10-10 (menu-scroll audit): cap dialog height + scroll —
	# a long brief must never push Approve (a war decision) off-screen.
	_cap_modal_scroll(dlg, vbox)
	# Add on top of everything (sibling of screen content, not inside it).
	add_child(overlay)
	overlay.move_to_front()
	_register_modal({"type": "strategic_proposal", "pid": pid}, overlay)


## [title, question] for a strategic proposal, per kind.
func _strategic_title_question(proposal: Dictionary) -> Array:
	var kind: String = String(proposal.get("kind", ""))
	var d: Dictionary = proposal.get("details", {})
	match kind:
		"declare_war":
			var tf := String(d.get("target", ""))
			var tn := String(Config.FACTIONS.get(tf, {}).get("name", tf))
			return ["War Council",
				"Your War Adviser proposes declaring WAR on the %s.\n"
				% tn + "Our forces will mass, then strike when ready. "
				+ "Approve the campaign?"]
		"monastery_assault":
			var mid := int(d.get("monastery_id", -1))
			var mn := "the monastery"
			var holder := ""
			var mons = _gs.get("monasteries") if _gs != null else null
			if mons != null and mons.has_method("get_monastery"):
				var m: Dictionary = mons.get_monastery(mid)
				if not m.is_empty():
					mn = String(m.get("name", mn))
					var ow := String(m.get("owner", ""))
					holder = String(Config.FACTIONS.get(ow, {}).get(
						"name", ow)) if ow != "" else ""
			var q2 := "Your War Adviser proposes a coordinated assault on %s" % mn
			if holder != "":
				q2 += " (held by the %s)" % holder
			q2 += ".\nPower is ruling the land — shall we take it?"
			return ["Monastery Assault", q2]
		"command_post_assault":
			# Jeremy 2026-10-06: Battlefront — assaults on war-held crystals
			# and towns go through the same proposal protocol as monasteries.
			var pk := String(d.get("post_kind", ""))
			var plabel := String({"crystal": "dark crystal",
				"town": "town"}.get(pk, pk))
			var pn := String(d.get("post_name", "the %s" % plabel))
			var ph := String(d.get("post_holder", ""))
			var phn := String(Config.FACTIONS.get(ph, {}).get(
				"name", ph)) if ph != "" else ""
			var q3 := "Your War Adviser proposes a coordinated assault on %s" % pn
			if phn != "":
				q3 += " (held by the %s)" % phn
			q3 += ".\nPower is ruling the land — shall we take it?"
			return ["Command Post Assault", q3]
		"expand_territory":
			return ["New Settlement",
				"Your advisers propose founding a NEW SETTLEMENT — a new "
				+ "town hall on distant land.\nApprove the expedition?"]
		"major_buildup":
			return ["Military Buildup",
				"Your War Adviser proposes a MAJOR MILITARY BUILDUP — "
				+ "mass training, more barracks, war footing.\nApprove?"]
		"sue_for_peace":
			var pf := String(d.get("target", ""))
			var pn := String(Config.FACTIONS.get(pf, {}).get("name", pf))
			return ["Sue for Peace",
				"Your advisers propose SUING FOR PEACE with the %s.\n"
				% pn + "We are losing this war — yield and pay reparations?"]
		"siege_choice":
			# Jeremy 2026-10-06 (Lane 3, Postworks): the attacker picks
			# the siege doctrine — storm the post now, or starve it out.
			var sk := String(d.get("post_kind", "post"))
			var slabel := String({"crystal": "dark crystal",
				"town": "town", "monastery": "monastery"}.get(sk, sk))
			var sn := String(d.get("post_name", "the %s" % slabel))
			var sh := String(d.get("defender", ""))
			var shn := String(Config.FACTIONS.get(sh, {}).get(
				"name", sh)) if sh != "" else ""
			var smode := String(d.get("mode", "starve"))
			var sverb := "STARVE OUT" if smode == "starve" else "STORM"
			var sreason := String(d.get("reason", ""))
			var q4 := "Your War Adviser recommends we %s %s" % [sverb, sn]
			if shn != "":
				q4 += " (held by the %s)" % shn
			q4 += ".\n"
			if sreason != "":
				q4 += sreason + "\n"
			q4 += "Approve the doctrine?"
			return ["Siege Council", q4]
	return ["Council Proposal",
		"Your advisers request your decision.\nApprove?"]
## Block). Compact — sits in the header row, doesn't eat screen space.
func _small_header_btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", FONT_SM)
	b.add_theme_color_override("font_color", PH_ACCENT)
	b.add_theme_color_override("font_hover_color", PH_ACCENT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	# Jeremy 2026-10-06 (overhaul): faint glass pill instead of invisible.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0.05)
	sb.set_corner_radius_all(999)
	sb.border_color = PH_EDGE
	sb.set_border_width_all(1)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = Color(1, 1, 1, 0.10)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_stylebox_override("focus", sb)
	b.pressed.connect(on_press)
	return b


## Jeremy 2026-10-04: centered day-divider pill ("Day 1").
## Jeremy 2026-10-05: gold-tinted for the Bastard OS theme.
## Jeremy 2026-10-06: messenger day labels — "Today"/"Yesterday"/"Day N".
func _day_label(mday: int) -> String:
	var today: int = _gs.day_number if _gs != null else mday
	if mday == today:
		return "Today"
	if mday == today - 1:
		return "Yesterday"
	return "Day %d" % mday


## Jeremy 2026-10-06: "H:MM AM/PM" for a message timestamp.
func _msg_time_label(ts: float) -> String:
	var day_len: float = 600.0
	if Config != null:
		day_len = float(Config.DAY_LENGTH_SECONDS)
	var hour_f: float = fmod(ts, day_len) / day_len * 24.0
	var total_min: int = int(hour_f * 60.0)
	var h24: int = (total_min / 60) % 24
	var mi: int = total_min % 60
	var ap := "AM" if h24 < 12 else "PM"
	var h12: int = h24 % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, mi, ap]


func _day_divider(text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.23, 0.18, 0.09)
	sb.set_corner_radius_all(999)
	sb.content_margin_left = 22.0
	sb.content_margin_right = 22.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	pill.add_theme_stylebox_override("panel", sb)
	var lab := Label.new()
	lab.text = text
	lab.add_theme_font_size_override("font_size", FONT_XS)
	lab.add_theme_color_override("font_color", PH_ACCENT)
	pill.add_child(lab)
	row.add_child(pill)
	return row


## Jeremy 2026-10-04: short timestamp for under a bubble ("Day 1" + time).
func _msg_stamp(m: Dictionary) -> String:
	var mday: int = int(m.get("day", 0))
	if mday <= 0:
		return ""
	return "Day %d" % mday


## Jeremy 2026-10-04: circular blue send button, chat-style.
## Drawn arrow glyph (no emoji/tofu risk) on a blue circle.
func _round_send_btn(on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(88, 88)
	b.tooltip_text = "Send"
	var sb := StyleBoxFlat.new()
	sb.bg_color = PH_SENT
	sb.set_corner_radius_all(999)
	# Jeremy 2026-10-06 (overhaul): send button pops — glow edge + shadow.
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.shadow_color = Color(0.145, 0.475, 0.92, 0.45)
	sb.shadow_size = 12
	b.add_theme_stylebox_override("normal", sb)
	var sb2 := sb.duplicate() as StyleBoxFlat
	sb2.bg_color = PH_SENT.darkened(0.15)
	b.add_theme_stylebox_override("hover", sb2)
	b.add_theme_stylebox_override("pressed", sb2)
	b.add_theme_stylebox_override("focus", sb)
	# Drawn up-arrow (no text glyph — tofu-safe).
	var arrow := SendArrowIcon.new()
	arrow.position = Vector2(24, 24)
	arrow.size = Vector2(40, 40)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(arrow)
	b.pressed.connect(on_press)
	return b

## Jeremy 2026-10-04: likes/dislikes bar for the Messenger thread view.
## Two glanceable rows under the NPC's pfp — green for likes, red for
## dislikes. No emoji (tofu risk on iPhone) — plain text labels.
## Slim relationship meter for the thread header: track + tiny caption
## showing how much this NPC likes/dislikes the ruler (HTML CANDIDATE54).
func _affinity_meter(u: Dictionary) -> Control:
	var aff: Dictionary = _phone.affinity_for(u)
	var tier := String(aff.get("tier", "neutral"))
	var score := float(aff.get("score", 0.0))
	var mood_word := String(aff.get("mood_word", "Wary"))
	var tier_color := Color(0.5, 0.5, 0.5)
	match tier:
		"hostile":
			tier_color = Color(0.9, 0.25, 0.25)
		"cold":
			tier_color = Color(0.9, 0.55, 0.25)
		"warm":
			tier_color = Color(0.45, 0.85, 0.45)
		"devoted":
			tier_color = Color(0.95, 0.5, 0.85)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	# Indent past the back chevron + pfp so it sits under the name block.
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(96, 1)
	row.add_child(pad)
	var track := Control.new()
	track.custom_minimum_size = Vector2(110, 5)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := ColorRect.new()
	bg.color = Color(0.22, 0.22, 0.24)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.add_child(bg)
	var fill := ColorRect.new()
	fill.color = tier_color
	fill.anchor_top = 0.0
	fill.anchor_bottom = 1.0
	fill.anchor_left = 0.0
	fill.anchor_right = (score + 100.0) / 200.0
	fill.offset_left = 0.0
	fill.offset_right = 0.0
	fill.offset_top = 0.0
	fill.offset_bottom = 0.0
	track.add_child(fill)
	row.add_child(track)
	var cap := Label.new()
	cap.text = "%s · %s" % [mood_word, tier.capitalize()]
	cap.add_theme_font_size_override("font_size", FONT_XS)
	cap.add_theme_color_override("font_color", tier_color)
	cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(cap)
	return row


func _likes_bar(u: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.08)
	sb.border_width_bottom = 1
	sb.border_color = PH_DIV
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 6.0
	sb.content_margin_bottom = 6.0
	panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var likes: Array = SimLikesDislikes.likes_label_list(u)
	var dislikes: Array = SimLikesDislikes.dislikes_label_list(u)
	var ll := Label.new()
	ll.text = "Likes: " + (", ".join(likes) if not likes.is_empty() else "—")
	ll.add_theme_font_size_override("font_size", FONT_SM)
	ll.add_theme_color_override("font_color", Color(0.45, 0.9, 0.45))
	ll.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(ll)
	var dl := Label.new()
	dl.text = "Dislikes: " + (", ".join(dislikes) if not dislikes.is_empty() else "—")
	dl.add_theme_font_size_override("font_size", FONT_SM)
	dl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(dl)
	return panel


func _show_squabble() -> void:
	_screen = "squabble"
	_clear()
	_header("Squabble")
	# Compose box on top.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var entry := _line_edit("Squabble something…")
	row.add_child(entry)
	var post := _btn("Post", func() -> void:
		var txt: String = entry.text
		if txt.strip_edges() == "":
			return
		entry.text = ""
		_phone.ruler_post(txt)
		_show_squabble())
	post.custom_minimum_size = Vector2(110, BTN_H)
	row.add_child(post)
	_root.add_child(row)
	# Jeremy 2026-10-04: trending topics row.
	# Jeremy 2026-10-06 (launch readiness): tags scroll horizontally —
	# up to 8 tag buttons used to run off the right edge with no scroll.
	var trending: Array = _phone.trending_tags(8)
	if not trending.is_empty():
		var twrap := HBoxContainer.new()
		twrap.add_theme_constant_override("separation", 8)
		var tlabel := Label.new()
		tlabel.text = "Trending:"
		tlabel.add_theme_font_size_override("font_size", FONT_SM)
		tlabel.add_theme_color_override("font_color", PH_TEXT_DIM)
		twrap.add_child(tlabel)
		var tsc := ScrollContainer.new()
		tsc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tsc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		var trow := HBoxContainer.new()
		trow.add_theme_constant_override("separation", 8)
		tsc.add_child(trow)
		twrap.add_child(tsc)
		_root.add_child(twrap)
		for t: Dictionary in trending:
			var tag: String = str(t.get("tag", ""))
			var tb := Button.new()
			tb.text = "#%s (%d)" % [tag, int(t.get("count", 0))]
			tb.add_theme_font_size_override("font_size", FONT_SM)
			tb.add_theme_color_override("font_color", PH_ACCENT)
			var tsb := StyleBoxFlat.new()
			tsb.bg_color = PH_SURFACE2
			tsb.set_corner_radius_all(12)
			tsb.content_margin_left = 10.0
			tsb.content_margin_right = 10.0
			tsb.content_margin_top = 4.0
			tsb.content_margin_bottom = 4.0
			tb.add_theme_stylebox_override("normal", tsb)
			tb.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			var tag_copy: String = tag
			tb.pressed.connect(func() -> void: _show_squabble_tag(tag_copy))
			trow.add_child(tb)
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var posts: Array = _phone.feed()
	if posts.is_empty():
		# Jeremy 2026-10-08 (graphics hourly): tagged "squabble_empty" so
		# the live-feed handler can drop the placeholder the moment the
		# first real post arrives.
		var ea := _empty_art("res://assets/ui/phone/empty_squabble.webp")
		ea.set_meta("squabble_empty", true)
		box.add_child(ea)
		var none := Label.new()
		none.text = "No posts yet. The kingdom is suspiciously quiet."
		none.add_theme_font_size_override("font_size", FONT_SM)
		none.add_theme_color_override("font_color", PH_TEXT_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.set_meta("squabble_empty", true)
		box.add_child(none)
	for p: Dictionary in posts:
		box.add_child(_post_card(p))
	# Live-feed target: the squabble_post handler inserts new cards here.
	_squabble_box = box


## Squabble filtered to a single hashtag.
func _show_squabble_tag(tag: String) -> void:
	_screen = "squabble"
	_clear()
	_header("Squabble")
	# Jeremy 2026-10-04 (polish): drawn chevron back button — the old "←"
	# text glyph was a tofu risk on iPhone (same class as the status-bar
	# back arrow). Drawn ChevronIcon always renders; "All Posts" label kept
	# as text beside it.
	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 4)
	var back := Button.new()
	back.custom_minimum_size = Vector2(72, BTN_H)
	var chev := ChevronIcon.new(PH_TEXT, 9.0)
	chev.position = Vector2(16, (BTN_H - 40.0) / 2.0)
	chev.size = Vector2(40, 40)
	chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(chev)
	var csb := StyleBoxEmpty.new()
	back.add_theme_stylebox_override("normal", csb)
	back.add_theme_stylebox_override("hover", csb)
	back.add_theme_stylebox_override("pressed", csb)
	back.add_theme_stylebox_override("focus", csb)
	back.pressed.connect(func() -> void: _show_squabble())
	back_row.add_child(back)
	var blab := Label.new()
	blab.text = "All Posts"
	blab.add_theme_font_size_override("font_size", FONT_MD)
	blab.add_theme_color_override("font_color", PH_TEXT)
	blab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back_row.add_child(blab)
	_root.add_child(back_row)
	var title := Label.new()
	title.text = "#%s" % tag
	title.add_theme_font_size_override("font_size", FONT_LG)
	title.add_theme_color_override("font_color", PH_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(title)
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var posts: Array = _phone.posts_with_tag(tag)
	if posts.is_empty():
		var none := Label.new()
		none.text = "No posts with this tag yet."
		none.add_theme_font_size_override("font_size", FONT_SM)
		none.add_theme_color_override("font_color", PH_TEXT_DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
	for p: Dictionary in posts:
		box.add_child(_post_card(p))


func _post_card(p: Dictionary) -> PanelContainer:
	var card := _card()
	# Jeremy 2026-10-06: PASS so drags on a post scroll the feed.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var pid: int = int(p.get("id", 0))
	var akey: String = String(p.get("author_key", ""))
	# Author row: pfp + name + day (tappable -> profile).
	# Jeremy 2026-10-05: use the stored pfp key directly — the unit lookup
	# goes stale (dead/culled NPCs) and fell back to a "?" avatar.
	var au: Dictionary = _phone._unit_for_key(akey) if akey.begins_with("u") else {}
	var ahead := HBoxContainer.new()
	ahead.add_theme_constant_override("separation", 12)
	ahead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if akey == "ruler":
		ahead.add_child(_ruler_pfp(PFP_SM))
	else:
		var pfp_tex: Texture2D = Art.portrait_texture(String(p.get("pfp", "")))
		if pfp_tex != null:
			ahead.add_child(_pfp_tex(pfp_tex, PFP_SM))
		else:
			ahead.add_child(_pfp(au, PFP_SM))
	var head := Button.new()
	head.text = "%s  ·  Day %d" % [String(p.get("author_name", "?")),
		int(p.get("day", 1))]
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_font_size_override("font_size", FONT_MD)
	head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.pressed.connect(func() -> void:
		if akey != "ruler":
			open_profile(akey))
	ahead.add_child(head)
	box.add_child(ahead)
	var body := Label.new()
	body.text = String(p.get("text", ""))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", FONT_MD)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_emoji_text(body)
	box.add_child(body)
	for cm: Dictionary in p.get("comments", []):
		var cl := Label.new()
		cl.text = "> %s: %s" % [String(cm.get("author", "?")),
			String(cm.get("text", ""))]
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.add_theme_font_size_override("font_size", FONT_SM)
		cl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_emoji_text(cl)
		box.add_child(cl)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var like := _btn("Like (%d)" % int(p.get("likes", 0)), func() -> void:
		_phone.like_post(pid)
		_show_squabble())
	like.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rsq := _btn("Repost (%d)" % int(p.get("resquabbles", 0)), func() -> void:
		_phone.resquabble(pid)
		_show_squabble())
	rsq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cmt := _btn("Comment", func() -> void:
		_toggle_comment_box(box, pid))
	cmt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(like)
	actions.add_child(rsq)
	actions.add_child(cmt)
	# Jeremy 2026-10-04: delete your own posts.
	if akey == "ruler":
		var del := _btn("Delete", func() -> void:
			_phone.delete_post(pid, "ruler")
			_show_squabble())
		del.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		actions.add_child(del)
	box.add_child(actions)
	return card


## Milestone 7: real text input for comments (replaces canned "Nice post!").
func _toggle_comment_box(box: VBoxContainer, pid: int) -> void:
	# Remove any existing comment row first.
	for c in box.get_children():
		if c.has_meta("comment_row"):
			c.queue_free()
			return
	var row := HBoxContainer.new()
	row.set_meta("comment_row", true)
	row.add_theme_constant_override("separation", 8)
	# Jeremy 2026-10-10 (menu-scroll audit): use _line_edit, not a raw
	# LineEdit — the raw one summoned the native iOS keyboard instead of
	# the phone's custom keyboard (virtual_keyboard_enabled was never
	# disabled, _open_phone_keyboard never hooked).
	var entry := _line_edit("Write a comment…")
	entry.custom_minimum_size = Vector2(0, 44)
	entry.add_theme_font_size_override("font_size", FONT_SM)
	row.add_child(entry)
	# Jeremy 2026-10-04: keyboard SEND key posts the comment too.
	var do_comment := func() -> void:
		var txt: String = entry.text
		if txt.strip_edges() == "":
			return
		_phone.comment_post(pid, txt)
		_show_squabble()
	var send := _btn("Send", do_comment)
	entry.text_submitted.connect(func(_t: String) -> void: do_comment.call())
	_kb_send_hook = do_comment
	send.custom_minimum_size = Vector2(100, 44)
	row.add_child(send)
	box.add_child(row)
	entry.grab_focus()


func _show_profile() -> void:
	_screen = "profile"
	_clear()
	var u: Dictionary = _phone._unit_for_key(_profile_key)
	if u.is_empty():
		_header("Profile", "squabble")
		return
	_header(SimPersonality.display_name(u), "squabble")
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var pfp_row := HBoxContainer.new()
	pfp_row.alignment = BoxContainer.ALIGNMENT_CENTER
	pfp_row.add_child(_pfp(u, PFP_LG))
	box.add_child(pfp_row)
	var bio := Label.new()
	var btext: String = _phone.bio_for(u)
	bio.text = btext if btext != "" else "No recorded history yet."
	bio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio.add_theme_font_size_override("font_size", FONT_MD)
	box.add_child(bio)
	var info := Label.new()
	info.text = "Job: %s · Faction: %s" % [String(u.get("job", "?")).capitalize(),
		String(u.get("faction", "?")).capitalize()]
	info.add_theme_font_size_override("font_size", FONT_SM)
	box.add_child(info)
	# Jeremy 2026-10-11: levelable skills — profiles show what a gnome is
	# actually good at. Sick units show their status too.
	var sk := SimSkills.summary(u)
	if sk != "":
		var skl := Label.new()
		skl.text = "Skills: %s" % sk
		skl.add_theme_font_size_override("font_size", FONT_SM)
		skl.add_theme_color_override("font_color", PH_ACCENT)
		box.add_child(skl)
	if bool(u.get("sick", false)):
		var sickl := Label.new()
		sickl.text = "Status: SICK — plague%s" % (" (quarantined)" if bool(u.get("quarantined", false)) else "")
		sickl.add_theme_font_size_override("font_size", FONT_SM)
		sickl.add_theme_color_override("font_color", PH_RED)
		box.add_child(sickl)
	# Jeremy 2026-10-06 (lane 6): believed rumors move reputations —
	# the profile shows where this gnome stands with the realm.
	var puid: int = int(u.get("id", 0))
	if _phone != null and _phone.hearsay != null \
			and _phone.hearsay.has_method("reputation_of"):
		var repv: float = _phone.hearsay.reputation_of(puid)
		var repl := Label.new()
		repl.text = "Reputation: %d — %s" % [int(repv),
			_phone.hearsay.rep_label(repv)]
		repl.add_theme_font_size_override("font_size", FONT_SM)
		box.add_child(repl)
	var pblocked: bool = _phone.is_blocked(puid)
	_root.add_child(_btn("Unblock" if pblocked else "Block",
		func() -> void:
			_phone.toggle_block(puid)
			_show_profile()))
	var pl := Label.new()
	pl.text = "Recent posts"
	pl.add_theme_font_size_override("font_size", FONT_MD)
	box.add_child(pl)
	for p: Dictionary in _phone.posts_by(int(u.get("id", 0))):
		box.add_child(_post_card(p))

## --- Gazette: Chronicle / Messages / Policies tabs (HTML parity) ----------------

func _show_gazette() -> void:
	_screen = "gazette"
	_clear()
	_header("The Cursing Chronicle")
	var issue := Label.new()
	issue.text = _court.issue_line()
	issue.add_theme_font_size_override("font_size", FONT_SM)
	issue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(issue)
	# Tab row.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	for t: String in ["chronicle", "messages", "policies"]:
		var b := _btn(t.capitalize(), func() -> void:
			_gaz_tab = t
			_show_gazette())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _gaz_tab == t:
			b.modulate = Color(1.2, 1.2, 0.9)
		tabs.add_child(b)
	_root.add_child(tabs)
	match _gaz_tab:
		"messages":
			_show_gazette_messages()
		"policies":
			_show_gazette_policies()
		_:
			_show_gazette_chronicle()


func _show_gazette_chronicle() -> void:
	# HTML STAGE20-3: real newspaper restyle — section kickers, comedic
	# reporter bylines, figure captions, issue numbering. Lead story gets
	# front-page treatment, rest in columns.
	var issue := Label.new()
	issue.text = _court.issue_line()
	issue.add_theme_font_size_override("font_size", FONT_SM)
	issue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(issue)
	var nl := Label.new()
	nl.text = "The Cursing Chronicle"
	nl.add_theme_font_size_override("font_size", FONT_LG)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(nl)
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var stories: Array = _court.news_feed()
	if stories.is_empty():
		box.add_child(_empty_art("res://assets/ui/phone/empty_gazette.webp"))
		var none := Label.new()
		none.text = "No news yet. The realm holds its breath…"
		none.add_theme_font_size_override("font_size", FONT_SM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(none)
		return
	var GazetteScript := load("res://scripts/sim/gazette.gd")
	var gaz: RefCounted = GazetteScript.new(_court.game_state())
	for i in range(stories.size()):
		var s: Dictionary = stories[i]
		var article: Dictionary = gaz.article_for(s, i == 0)
		box.add_child(_gazette_article_card(article))


## One story as a newspaper article (HTML gazArticleHtml as Godot UI).
## lead = front-page treatment.
func _gazette_article_card(article: Dictionary) -> PanelContainer:
	var card := _card()
	# Jeremy 2026-10-10 (menu-scroll audit): PASS so drags on an article
	# scroll the chronicle; the card is read-only, children are IGNORE.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 6)
	cbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(cbox)
	# Section kicker (+ urgent stamp).
	var kicker := Label.new()
	var ktext: String = str(article.get("section", "Town Crier")).to_upper()
	if bool(article.get("urgent", false)):
		ktext += "  [URGENT]"
	kicker.text = ktext
	kicker.add_theme_font_size_override("font_size", FONT_XS)
	kicker.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	kicker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(kicker)
	# Headline with icon.
	var hl := Label.new()
	var fsize: int = FONT_XL if bool(article.get("lead", false)) else FONT_MD
	hl.text = str(article.get("headline", ""))
	hl.add_theme_font_size_override("font_size", fsize)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(hl)
	# Byline: By [reporter] · [dayline].
	var byline := Label.new()
	byline.text = "By %s · %s" % [str(article.get("byline", "")), str(article.get("dayline", ""))]
	byline.add_theme_font_size_override("font_size", FONT_XS)
	byline.add_theme_color_override("font_color", Color(0.7, 0.65, 0.55))
	byline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(byline)
	# Editorial cartoon (if the story matched an archetype).
	var cartoon_path := str(article.get("cartoon_path", ""))
	if cartoon_path != "":
		var tex: Texture2D = load(cartoon_path)
		if tex != null:
			var img := TextureRect.new()
			img.texture = tex
			img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			img.custom_minimum_size = Vector2(0, 180)
			img.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cbox.add_child(img)
			var cap := Label.new()
			cap.text = str(article.get("caption", ""))
			cap.add_theme_font_size_override("font_size", FONT_XS)
			cap.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
			cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cbox.add_child(cap)
	# Story body.
	var bd := Label.new()
	bd.text = str(article.get("story", ""))
	bd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bd.add_theme_font_size_override("font_size", FONT_SM)
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cbox.add_child(bd)
	return card


func _show_gazette_messages() -> void:
	# Open petitions first — decisions reach the player ONLY here.
	# Jeremy 2026-10-10 (menu-scroll audit): ONE scroll for both sections.
	# Two EXPAND_FILL ScrollContainers split the phone screen 50/50, so the
	# open petitions — crown decisions, including war and peace — were
	# squeezed into half the screen whenever decided history also existed.
	# Both lists now share a single full-height scroll, open petitions on
	# top where the decisions live.
	var open: Array = _court.open_petitions()
	var hist: Array = _court.petition_history(10)
	if open.is_empty() and hist.is_empty():
		var none := Label.new()
		none.text = "No petitions. The court is suspiciously quiet."
		none.add_theme_font_size_override("font_size", FONT_SM)
		_root.add_child(none)
		return
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	if not open.is_empty():
		var pl := Label.new()
		pl.text = "Petitions awaiting the crown"
		pl.add_theme_font_size_override("font_size", FONT_MD)
		box.add_child(pl)
		for p: Dictionary in open:
			box.add_child(_petition_card(p))
	# Decided petitions: the record.
	if not hist.is_empty():
		var hl := Label.new()
		hl.text = "Decided"
		hl.add_theme_font_size_override("font_size", FONT_MD)
		box.add_child(hl)
		for p: Dictionary in hist:
			var lab := Label.new()
			var opts: Array = p.get("options", [])
			var ci: int = int(p.get("choice", -1))
			var choice: String = String(opts[ci]) if ci >= 0 and ci < opts.size() else "?"
			lab.text = "Day %d · %s (%s): %s — “%s”" % [int(p.get("day", 1)),
				String(p.get("from_name", "?")), String(p.get("role", "")),
				String(p.get("kind", "")).capitalize(), choice]
			lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lab.add_theme_font_size_override("font_size", FONT_SM)
			box.add_child(lab)


## Policies summary inside the Gazette (HTML Policies tab) + a door
## into the full Policies app.
func _show_gazette_policies() -> void:
	var pol = _court.policies
	if pol == null:
		return
	var gd: Dictionary = pol.gov_def()
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var gov_lab := Label.new()
	# iPhone-safe: no emoji icon prefix (emoji render as tofu boxes in the
	# Godot web export on iPhone — Jeremy 2026-10-03).
	gov_lab.text = "Government: %s" % String(gd.get("name", ""))
	gov_lab.add_theme_font_size_override("font_size", FONT_MD)
	gov_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(gov_lab)
	var rows := [
		"Tax: %d%%  (projected +%d gold/day)" % [int(pol.state.get("tax", 0)),
			pol.projected_tax_income()],
		"Anarchy: %s" % ("YES — no taxes, no guards" if bool(pol.state.get("anarchy", false)) else "no"),
		"Guard: %s (%d on duty)" % [String(pol.state.get("guard", "none")).capitalize(),
			pol.guard_units().size()],
		"Curfew: %s" % ("imposed" if bool(pol.state.get("curfew", false)) else "none"),
		"Borders: %s" % String(pol.state.get("borders", "open")).capitalize(),
		"Happiness: %d/100" % int(pol.state.get("happiness", 62)),
		"Approval: %d/100%s" % [int(round(pol.avg_approval())),
			" · STRIKES" if bool(pol.state.get("strike", false)) else ""],
		"Festival cooldown: %dd" % int(pol.state.get("festival_cd", 0)),
	]
	if String(pol.state.get("guard", "none")) == "none":
		rows.append("No watch — raise tiers in Policies > Town Watch")
	for r: String in rows:
		var lab := Label.new()
		lab.text = r
		lab.add_theme_font_size_override("font_size", FONT_SM)
		box.add_child(lab)
	_root.add_child(_btn("Open Policies", func() -> void: open_app("policies")))


func _petition_card(p: Dictionary) -> PanelContainer:
	var card := _card()
	# Jeremy 2026-10-10 (menu-scroll audit): PASS so drags on a petition
	# scroll the Gazette list; non-interactive children are IGNORE.
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var pid: int = int(p.get("id", 0))
	var hl := Label.new()
	hl.text = "%s (%s)" % [String(p.get("from_name", "?")),
		String(p.get("role", ""))]
	hl.add_theme_font_size_override("font_size", FONT_MD)
	hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hl)
	var tx := Label.new()
	tx.text = String(p.get("text", ""))
	tx.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tx.add_theme_font_size_override("font_size", FONT_SM)
	tx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(tx)
	# Petitioner chat: talk it over before deciding (two-way chat, offline).
	var fkey: String = String(p.get("from_key", ""))
	if fkey.begins_with("u"):
		var talk := _btn("Talk", func() -> void:
			var uid: int = int(fkey.trim_prefix("u"))
			var opener: String = String(p.get("talk", ""))
			if opener == "":
				opener = "You wished to speak with me, sire?"
			_phone.npc_message(uid, opener)
			open_thread(fkey))
		talk.custom_minimum_size = Vector2(0, 56)
		box.add_child(talk)
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	opts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var options: Array = p.get("options", [])
	for i: int in options.size():
		var choice: String = String(options[i])
		var b := _btn(choice, func() -> void:
			_court.decide(pid, i)
			_show_gazette())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opts.add_child(b)
	box.add_child(opts)
	return card

## --- Diplomacy (Milestone 8: treaties) ---------------------------------------

const _DIPLO_STATE_STYLE := {
	# Jeremy 2026-10-03: color-coded relationship status
	"war": ["", Color(1.0, 0.30, 0.30)],        # red — at war
	"hostile": ["", Color(1.0, 0.55, 0.25)],   # orange — hostile
	"neutral": ["", Color(0.90, 0.78, 0.45)],   # warm gold-gray — neutral
	"friendly": ["", Color(0.50, 0.90, 0.50)], # green — friendly
	"allied": ["", Color(0.40, 0.75, 1.0)],    # blue — allied
}

## Faction theme colors for diplomacy cards (Jeremy 2026-10-03).
const _DIPLO_FACTION_COLORS := {
	"humans": Color(0.30, 0.50, 0.90),   # blue
	"elves": Color(0.30, 0.70, 0.40),    # forest green
	"gnomes": Color(0.90, 0.60, 0.20),   # warm orange/gold
	"ogres": Color(0.70, 0.35, 0.20),    # dark rust red
	"undead": Color(0.60, 0.40, 0.85),   # necrotic purple
}


## Jeremy 2026-10-06 (launch readiness — phone controls the whole game):
## Army app. Army command was HUD-only; the phone couldn't train troops,
## set stances, muster/deploy, promote warlords, or buy weapon upgrades.
## Reuses the HUD's ArmyTab builder (fully static, self-rebuilding after
## every command) inside a phone scroll screen — one shared command
## surface, no duplicate logic.
func _show_army() -> void:
	_screen = "army"
	_clear()
	# Jeremy 2026-10-05: no bottom nav bar on this screen — the back
	# chevron in the header is the way out.
	if _nav_bar != null and is_instance_valid(_nav_bar):
		_nav_bar.visible = false
	_header("Army")
	if _gs == null:
		var off := Label.new()
		off.text = "The war office is closed."
		off.add_theme_font_size_override("font_size", FONT_MD)
		off.add_theme_color_override("font_color", PH_TEXT)
		_root.add_child(off)
		return
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	# Jeremy 2026-10-06 (Lane 5): Army app sub-screens — War room, Veterans,
	# Warlords, Deploy — alongside the shared ArmyTab command surface.
	PhoneArmyExpansion.build_nav(self, box, "army")
	ArmyTab.set_ui_scale(clampf(_phone_w / 380.0, 1.2, 2.2))
	ArmyTab.build(_gs, box)


## Jeremy 2026-10-06 (Lane 5): Army app sub-screens. Each is a real phone
## screen (Back returns to the Army app, never an X) hosting a
## PhoneArmyExpansion builder inside the safe-area scroll.
func _show_army_sub(screen: String, title: String, current: String) -> void:
	_screen = screen
	_clear()
	# Jeremy 2026-10-05: no bottom nav bar on this screen — the back
	# chevron in the header is the way out.
	if _nav_bar != null and is_instance_valid(_nav_bar):
		_nav_bar.visible = false
	_header(title, "army")
	if _gs == null:
		var off := Label.new()
		off.text = "The war office is closed."
		off.add_theme_font_size_override("font_size", FONT_MD)
		off.add_theme_color_override("font_color", PH_TEXT)
		_root.add_child(off)
		return
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	PhoneArmyExpansion.build_nav(self, box, current)
	match current:
		"army_warroom":
			PhoneArmyExpansion.build_warroom(self, _gs, box)
		"army_roster":
			PhoneArmyExpansion.build_roster(self, _gs, box)
		"army_retinue":
			PhoneArmyExpansion.build_retinue(self, _gs, box)
		"army_deploy":
			PhoneArmyExpansion.build_deploy(self, _gs, box)


func _show_army_warroom() -> void:
	_show_army_sub("army_warroom", "War room", "army_warroom")


func _show_army_roster() -> void:
	_show_army_sub("army_roster", "Veterans", "army_roster")


func _show_army_retinue() -> void:
	_show_army_sub("army_retinue", "Warlords", "army_retinue")


func _show_army_deploy() -> void:
	_show_army_sub("army_deploy", "Deploy", "army_deploy")


## Jeremy 2026-10-06 (launch readiness — hearsay/chat focus): Rumors app.
## The hearsay system was invisible on the phone; now the live rumor mill
## (SimHearsay.live_rumors, hottest first) is one tap away. Read-only —
## rumors are seeded and spread by the sim, this screen just watches.
func _show_rumors() -> void:
	_screen = "rumors"
	_clear()
	# Jeremy 2026-10-05: no bottom nav bar on this screen — the back
	# chevron in the header is the way out.
	if _nav_bar != null and is_instance_valid(_nav_bar):
		_nav_bar.visible = false
	_header("Rumors")
	if _gs == null or _phone == null or _phone.hearsay == null:
		var off := Label.new()
		off.text = "The taverns are closed."
		off.add_theme_font_size_override("font_size", FONT_MD)
		off.add_theme_color_override("font_color", PH_TEXT)
		_root.add_child(off)
		return
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var hs = _phone.hearsay
	# Jeremy 2026-10-06 (lane 6): the Rumors app is interactive now —
	# investigate a rumor (crown asks around via the DM flow) and watch
	# reputations move. Callables keep PhoneRumors sim-free (cold lane).
	# Jeremy 2026-10-06 (iPhone bugfix): WAR tags are gated on live
	# diplomacy (stale capture rumors showed WAR during peacetime) and
	# sources get named attribution instead of raw whisper counts.
	PhoneRumors.build(box, hs.live_rumors(24),
		func(uid: int) -> float: return hs.reputation_of(uid),
		func(rid: int) -> void:
			hs.investigate_rumor(rid)
			_show_rumors(),
		func(f: String) -> bool:
			return _diplo != null and _diplo.faction_at_war(f),
		func(uid: int) -> String:
			if _gs == null:
				return "a gnome"
			var u: Dictionary = _gs.get_unit(uid)
			if u.is_empty():
				return "a gnome"
			var nm := String(u.get("name", "")).strip_edges()
			return nm if nm != "" else "a gnome")


## Treaty screen: every faction's standing vs the player, with touch-sized
## action buttons (Declare War, Propose Alliance, Trade, Demand Tribute,
## plus Sue for Peace / Break Treaty when they apply).
func _show_diplomacy() -> void:
	_screen = "diplomacy"
	_clear()
	_header("Diplomacy")
	if _diplo == null:
		var off := Label.new()
		off.text = "The envoy office is closed (diplomacy offline)."
		off.add_theme_font_size_override("font_size", FONT_MD)
		_root.add_child(off)
		return
	if _diplo_result != "":
		var res := Label.new()
		res.text = _diplo_result
		res.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		res.add_theme_font_size_override("font_size", FONT_MD)
		_root.add_child(res)
		_diplo_result = ""
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var pf: String = _gs.player_faction
	for faction: String in _gs.active_factions:
		if faction == pf:
			continue
		box.add_child(_diplo_card(faction))
	# Jeremy 2026-10-11: war-spare peace treaties live on the diplomacy
	# board — terms listed, per-term negotiation.
	PhoneWarSpare.add_treaty_section(self, box)


func _diplo_card(faction: String) -> PanelContainer:
	var pf: String = _gs.player_faction
	var st: String = String(_diplo.relation_state(pf, faction))
	var sc: float = float(_diplo.relation_score(pf, faction))
	var style: Array = _DIPLO_STATE_STYLE.get(st,
		_DIPLO_STATE_STYLE["neutral"])
	var fcolor: Color = _DIPLO_FACTION_COLORS.get(faction,
		Color(0.75, 0.75, 0.75))
	# Jeremy 2026-10-03: faction-themed card with colored top border
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = PH_SURFACE
	csb.set_corner_radius_all(16)
	csb.border_width_top = 4
	csb.border_color = fcolor
	csb.content_margin_left = 14.0
	csb.content_margin_right = 14.0
	csb.content_margin_top = 12.0
	csb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", csb)
	# Jeremy 2026-10-10 (menu-scroll audit): PASS, not STOP — the card has
	# no tap behavior of its own (actions are the buttons below), so drags
	# must propagate to the ScrollContainer. Non-interactive children are
	# IGNORE so the press falls through to the card; buttons stay STOP
	# (Godot-safe: no mid-scroll tap-fire).
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var fname: String = String(
		Config.FACTIONS.get(faction, {}).get("name", faction))
	# Faction name in faction color, status in relationship color
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title_row)
	var emblem := _faction_emblem(faction, 64.0)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(emblem)
	var fname_lbl := Label.new()
	fname_lbl.text = fname
	fname_lbl.add_theme_font_size_override("font_size", FONT_LG)
	fname_lbl.add_theme_color_override("font_color", fcolor)
	fname_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(fname_lbl)
	var status_lbl := Label.new()
	status_lbl.text = st.to_upper()
	status_lbl.add_theme_font_size_override("font_size", FONT_MD)
	status_lbl.add_theme_color_override("font_color", style[1])
	status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(status_lbl)
	var sub := Label.new()
	var trade_txt := "trade deal active" if bool(
		_diplo.has_trade_deal(pf, faction)) else "no trade deal"
	# Jeremy 2026-10-04: show active truces on the card.
	var truce_txt := ""
	if _diplo.truce_active(pf, faction):
		truce_txt = "\nTruce: %d days remaining" % _diplo.truce_days_left(pf, faction)
	sub.text = "Standing %+d · %s\nMorale %d · Reputation %d%s" % [int(sc),
		trade_txt, int(_diplo.morale_of(faction)),
		int(_diplo.reputation_of(faction)), truce_txt]
	sub.add_theme_font_size_override("font_size", FONT_SM)
	sub.add_theme_color_override("font_color", PH_TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(sub)
	# Jeremy 2026-10-04: faction advisors show on the diplomacy board —
	# he reported not seeing any advisors there.
	var adv_line := _diplo_advisor_line(faction)
	if adv_line != "":
		var adv_lbl := Label.new()
		adv_lbl.text = adv_line
		adv_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		adv_lbl.add_theme_font_size_override("font_size", FONT_SM)
		adv_lbl.add_theme_color_override("font_color", PH_TEXT_DIM)
		adv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(adv_lbl)
	# Jeremy 2026-10-03: action buttons are BIG and stacked vertically —
	# fat-finger friendly, so you don't accidentally declare war.
	# Each button is full-width and 110px tall (was 64px in 2-per-row).
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fac: String = faction  # lambda capture copy
	var fname2: String = fname  # lambda capture copy for confirm dialog
	if st == "war":
		# HTML war-tree parity (C62): peace is bought, never free — the
		# phone board charges reparations before make_peace runs. The
		# confirm gate matches the other spend/war buttons (fat-finger
		# safe, Jeremy 2026-10-04). Unaffordable: feedback, no dialog.
		var rep: int = _diplo.reparation_cost(fac)
		var rep2: int = rep  # lambda capture copy
		actions.add_child(_diplo_btn("Sue for Peace (%dg)" % rep, func() -> void:
			if not _gs.resources.can_afford(pf, {"gold": float(rep2)}):
				_diplo_result = "The %s demand %dg in reparations — your treasury holds %dg." % [fname2, rep2, int(_gs.resources.get_amount(pf, "gold"))]
				_show_diplomacy()
				return
			_diplo_confirm("Sue for Peace", fname2,
				"Pay %d gold in reparations to the %s? The war ends." % [rep2, fname2],
				"Pay %dg — end the war" % rep2,
				func() -> void:
					_gs.resources.spend(pf, {"gold": float(rep2)})
					var r: Dictionary = _diplo.make_peace(pf, fac)
					_diplo_result = "%s (%dg in reparations paid.)" % [String(r.get("msg", "")), rep2]
					_show_diplomacy())))
	else:
		actions.add_child(_diplo_btn("Declare War", func() -> void:
			_diplo_confirm("Declare War", fname2,
				"Do you wish to declare war on %s?" % fname2,
				"Yes, declare war",
				func() -> void:
					var r: Dictionary = _diplo.declare_war(pf, fac,
						"by royal decree")
					_diplo_result = String(r.get("msg", ""))
					_show_diplomacy())))
	if st == "allied":
		actions.add_child(_diplo_btn("Break Treaty", func() -> void:
			_diplo_confirm("Break Treaty", fname2,
				"Do you wish to break your treaty with %s?" % fname2,
				"Yes, break treaty",
				func() -> void:
					var r: Dictionary = _diplo.break_treaty(pf, fac)
					_diplo_result = String(r.get("msg", ""))
					_show_diplomacy())))
	elif st != "war":
		actions.add_child(_diplo_btn("Propose Alliance", func() -> void:
			var r: Dictionary = _diplo.propose_alliance(pf, fac)
			_diplo_result = String(r.get("msg", ""))
			_show_diplomacy()))
	if st != "war":
		actions.add_child(_diplo_btn("Trade Deal", func() -> void:
			var r: Dictionary = _diplo.sign_trade_agreement(pf, fac)
			_diplo_result = String(r.get("msg", ""))
			_show_diplomacy()))
		actions.add_child(_diplo_btn("Demand Tribute", func() -> void:
			var amt: float = maxf(10.0,
				_gs.resources.get_amount(fac, "gold") * 0.15)
			var r: Dictionary = _diplo.demand_tribute(pf, fac, "gold",
				amt)
			_diplo_result = String(r.get("msg", ""))
			_show_diplomacy()))
		# Jeremy 2026-10-04: insult them — type your own insult.
		# (The n-word hard r is an instant war crime for every faction.)
		actions.add_child(_diplo_btn("Insult Them", func() -> void:
			_diplo_insult_input(fac, fname2)))
	elif bool(_diplo.has_trade_deal(pf, fac)):
		actions.add_child(_diplo_btn("Break Treaty", func() -> void:
			_diplo_confirm("Break Treaty", fname2,
				"Do you wish to break your treaty with %s?" % fname2,
				"Yes, break treaty",
				func() -> void:
					var r: Dictionary = _diplo.break_treaty(pf, fac)
					_diplo_result = String(r.get("msg", ""))
					_show_diplomacy())))
	box.add_child(actions)
	return card


# Jeremy 2026-10-03: diplomacy action buttons with distinct themed colors.
const _DIPLO_BTN_COLORS := {
	"Declare War": Color(0.75, 0.22, 0.22),      # red — danger
	"Sue for Peace": Color(0.35, 0.60, 0.90),   # light blue — peace
	"Propose Alliance": Color(0.25, 0.65, 0.30),# green — friendly
	"Break Treaty": Color(0.90, 0.50, 0.15),    # orange — warning
	"Trade Deal": Color(0.75, 0.60, 0.20),      # gold — neutral commerce
	"Demand Tribute": Color(0.55, 0.35, 0.80),  # purple — intimidating
}

func _diplo_btn(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	# Jeremy 2026-10-03: BIG buttons — 110px tall, full width.
	# Fat-finger friendly so you don't accidentally declare war.
	b.custom_minimum_size = Vector2(0, 110)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", FONT_MD)
	# Jeremy 2026-10-04: labels may carry a cost suffix ("Sue for Peace
	# (150g)") — match the themed color by base label prefix.
	var key: String = text
	for k: String in _DIPLO_BTN_COLORS.keys():
		if text == k or text.begins_with(k + " ") or text.begins_with(k + " ("):
			key = k
			break
	var bg: Color = _DIPLO_BTN_COLORS.get(key, PH_SURFACE2)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", PH_ACCENT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = bg.lightened(0.15)
	b.add_theme_stylebox_override("hover", sb_h)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = bg.darkened(0.2)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


## Jeremy 2026-10-03: destructive diplomacy actions need a safety gate.
## Shows a modal confirmation: "Do you wish to declare war on [Faction]?"
## with "Yes, declare war" and "Cancel". Only runs on_confirm if confirmed.
## Jeremy 2026-10-04: faction advisor roster line for diplomacy cards —
## "Advisors: Treasury Advisor (NAME) · War Advisor (NAME) ...".
## Falls back to the role title when a unit has no mind name yet.
func _diplo_advisor_line(faction: String) -> String:
	if _gs == null:
		return ""
	var parts: Array[String] = []
	for r: Dictionary in SimBuildings.GOV_ADVISOR_ROLES:
		var job: String = String(r.get("job", ""))
		for u: Dictionary in _gs.units:
			if u.get("alive", false) and bool(u.get("is_advisor", false)) \
					and String(u.get("faction", "")) == faction \
					and String(u.get("job", "")) == job:
				var nm: String = String(u.get("advisor_role",
					String(r.get("name", job))))
				var mname: String = String(
					(u.get("mind", {}) as Dictionary).get("name", ""))
				if mname != "":
					nm += " (%s)" % mname
				parts.append(nm)
				break
	if parts.is_empty():
		return ""
	return "Advisors: " + " · ".join(parts)
func _diplo_confirm(action: String, faction_name: String, question: String,
		confirm_text: String, on_confirm: Callable) -> void:
	# Full-screen dim overlay (blocks input to everything behind).
	var overlay := PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0, 0, 0, 0.75)
	overlay.add_theme_stylebox_override("panel", osb)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# Center the dialog.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var dlg := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = PH_SURFACE
	dsb.border_color = PH_ACCENT
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(20)
	dsb.content_margin_left = 28.0
	dsb.content_margin_right = 28.0
	dsb.content_margin_top = 28.0
	dsb.content_margin_bottom = 28.0
	dlg.add_theme_stylebox_override("panel", dsb)
	dlg.custom_minimum_size = Vector2(_modal_width(), 0)
	center.add_child(dlg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dlg.add_child(vbox)
	# Title (the action, in red for danger).
	var title := Label.new()
	title.text = action
	title.add_theme_font_size_override("font_size", FONT_LG)
	title.add_theme_color_override("font_color", PH_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# The question.
	var q := Label.new()
	q.text = question
	q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q.add_theme_font_size_override("font_size", FONT_MD)
	q.add_theme_color_override("font_color", PH_TEXT)
	q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(q)
	# Buttons: Cancel (safe) and Confirm (destructive).
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 110)
	cancel.add_theme_font_size_override("font_size", FONT_MD)
	cancel.add_theme_color_override("font_color", PH_TEXT)
	var csb := StyleBoxFlat.new()
	csb.bg_color = PH_SURFACE2
	csb.set_corner_radius_all(14)
	cancel.add_theme_stylebox_override("normal", csb)
	var csb_p := csb.duplicate() as StyleBoxFlat
	csb_p.bg_color = PH_SURFACE2.darkened(0.2)
	cancel.add_theme_stylebox_override("pressed", csb_p)
	cancel.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Launch readiness 2026-10-06: dismiss through the modal registry so a
	# cancelled confirm is never resurrected by a later rotation.
	cancel.pressed.connect(func() -> void: _dismiss_modal(overlay))
	vbox.add_child(cancel)
	var yes := Button.new()
	yes.text = confirm_text
	yes.custom_minimum_size = Vector2(0, 110)
	yes.add_theme_font_size_override("font_size", FONT_MD)
	yes.add_theme_color_override("font_color", Color(1, 1, 1))
	var ysb := StyleBoxFlat.new()
	ysb.bg_color = Color(0.75, 0.22, 0.22)  # red — danger
	ysb.set_corner_radius_all(14)
	yes.add_theme_stylebox_override("normal", ysb)
	var ysb_p := ysb.duplicate() as StyleBoxFlat
	ysb_p.bg_color = Color(0.75, 0.22, 0.22).darkened(0.2)
	yes.add_theme_stylebox_override("pressed", ysb_p)
	yes.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	yes.pressed.connect(func() -> void:
		_dismiss_modal(overlay)
		on_confirm.call())
	vbox.add_child(yes)
	# Jeremy 2026-10-10 (menu-scroll audit): cap dialog height + scroll.
	_cap_modal_scroll(dlg, vbox)
	# Add on top of everything (sibling of screen content, not inside it).
	add_child(overlay)
	overlay.move_to_front()
	# Launch readiness 2026-10-06: register so rotation re-shows a still-open
	# war confirm instead of silently destroying it.
	_register_modal({"type": "diplo_confirm", "action": action,
		"faction_name": faction_name, "question": question,
		"confirm_text": confirm_text, "on_confirm": on_confirm}, overlay)


## Jeremy 2026-10-04: insult text input popup. The player types their own
## insult; empty text falls back to the preset line. The n-word (hard r)
## triggers instant war from ANY faction — they freak out.
func _diplo_insult_input(faction: String, faction_name: String, draft: String = "") -> void:
	var pf: String = _gs.player_faction
	# Full-screen dim overlay (blocks input to everything behind).
	var overlay := PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	var osb := StyleBoxFlat.new()
	osb.bg_color = Color(0, 0, 0, 0.75)
	overlay.add_theme_stylebox_override("panel", osb)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	# Center the dialog.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var dlg := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = PH_SURFACE
	dsb.border_color = PH_ACCENT
	dsb.set_border_width_all(2)
	dsb.set_corner_radius_all(20)
	dsb.content_margin_left = 28.0
	dsb.content_margin_right = 28.0
	dsb.content_margin_top = 28.0
	dsb.content_margin_bottom = 28.0
	dlg.add_theme_stylebox_override("panel", dsb)
	dlg.custom_minimum_size = Vector2(_modal_width(), 0)
	center.add_child(dlg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	dlg.add_child(vbox)
	# Title.
	var title := Label.new()
	title.text = "Insult %s" % faction_name
	title.add_theme_font_size_override("font_size", FONT_LG)
	title.add_theme_color_override("font_color", PH_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	# Hint.
	var hint := Label.new()
	hint.text = "Type your insult below — or leave it blank for a classic."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", FONT_SM)
	hint.add_theme_color_override("font_color", PH_TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)
	# Text input.
	var entry := _line_edit("Your insult...")
	if not draft.is_empty():
		entry.text = draft
	vbox.add_child(entry)
	# Buttons: Cancel and Send.
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 110)
	cancel.add_theme_font_size_override("font_size", FONT_MD)
	cancel.add_theme_color_override("font_color", PH_TEXT)
	var csb := StyleBoxFlat.new()
	csb.bg_color = PH_SURFACE2
	csb.set_corner_radius_all(14)
	cancel.add_theme_stylebox_override("normal", csb)
	var csb_p := csb.duplicate() as StyleBoxFlat
	csb_p.bg_color = PH_SURFACE2.darkened(0.2)
	cancel.add_theme_stylebox_override("pressed", csb_p)
	cancel.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	# Launch readiness 2026-10-06: dismiss through the modal registry so a
	# cancelled insult is never resurrected by a later rotation.
	cancel.pressed.connect(func() -> void: _dismiss_modal(overlay))
	vbox.add_child(cancel)
	var send := Button.new()
	send.text = "Send Insult"
	send.custom_minimum_size = Vector2(0, 110)
	send.add_theme_font_size_override("font_size", FONT_MD)
	send.add_theme_color_override("font_color", Color(1, 1, 1))
	var ssb := StyleBoxFlat.new()
	ssb.bg_color = Color(0.75, 0.22, 0.22)  # red — danger
	ssb.set_corner_radius_all(14)
	send.add_theme_stylebox_override("normal", ssb)
	var ssb_p := ssb.duplicate() as StyleBoxFlat
	ssb_p.bg_color = Color(0.75, 0.22, 0.22).darkened(0.2)
	send.add_theme_stylebox_override("pressed", ssb_p)
	send.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	send.pressed.connect(func() -> void:
		var text: String = entry.text.strip_edges()
		_dismiss_modal(overlay)
		var r: Dictionary = _diplo.insult(pf, faction, text)
		_diplo_result = String(r.get("msg", ""))
		_show_diplomacy())
	vbox.add_child(send)
	# Jeremy 2026-10-10 (menu-scroll audit): cap dialog height + scroll —
	# the dialog used to clip off-screen with Send/Cancel unreachable.
	_cap_modal_scroll(dlg, vbox)
	# Add on top of everything (sibling of screen content, not inside it).
	add_child(overlay)
	overlay.move_to_front()
	# Launch readiness 2026-10-06: register so rotation re-shows the insult
	# box with the typed draft intact (snapshot captures entry.text).
	_register_modal({"type": "diplo_insult", "faction": faction,
		"faction_name": faction_name, "entry": entry}, overlay)
	entry.grab_focus()

## --- Policies app ---------------------------------------------------------------
## The real Policies UI (HTML Gazette Policies tab parity): government
## selector, approval meters, happiness, tax slider, anarchy, guard tiers,
## curfew, borders, festivals, guild quotas. The HUD's "Policies" button
## retargets here (see HOOKS).

## --- Policies app (redesigned 2026-10-05 per Jeremy) --------------------------
## Simplified one-screen layout: big readable text, gold/dark Bastard OS
## styling. Government cards (name + one-line flavor), approval/mood at a
## glance, big tax slider. No bottom nav bar on this screen — a labeled
## Back button in the header is the way out.

## One-line flavors for the government cards (short on purpose).
const GOV_FLAVOR := {
	"monarchy": "One crown, one will. Cheap decrees, strong guard.",
	"council": "Committees build cheap. Armies muster slowly.",
	"junta": "The barracks rule. Cheap, fearsome guards.",
	"theocracy": "The gods provide. Holy festivals, glad tithes.",
	"tribal": "Loyal to blood over crown. Cheap warriors.",
	"oligarchy": "Coin is king. Trade flows like wine.",
	"democracy": "The people rule themselves. Costly decrees.",
}


## Navy/gold card stylebox for the Policies screen.
func _pol2_card_style(selected: bool = false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.16, 0.24) if selected else Color(0.09, 0.12, 0.19)
	sb.set_corner_radius_all(16)
	sb.border_color = PH_ACCENT
	sb.set_border_width_all(3 if selected else 1)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	return sb


func _show_policies() -> void:
	_screen = "policies"
	_clear()
	# Jeremy 2026-10-05: no bottom nav bar on this screen — the labeled
	# Back button in the header is the way out.
	if _nav_bar != null and is_instance_valid(_nav_bar):
		_nav_bar.visible = false
	_pol_header()
	var pol = _court.policies
	if pol == null:
		var off := Label.new()
		off.text = "The policy office is closed."
		off.add_theme_font_size_override("font_size", FONT_MD)
		off.add_theme_color_override("font_color", PH_TEXT)
		_root.add_child(off)
		return
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	box.add_theme_constant_override("separation", 12)
	_pol2_hero(box, pol)
	_pol2_governments(box, pol)
	_pol2_tax(box, pol)
	_pol2_watch(box, pol)
	_pol2_plague(box, pol)


## Policies header: labeled Back button + title, gold underline.
func _pol_header() -> void:
	var bar := PanelContainer.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.08, 0.10, 0.16)
	bsb.border_width_bottom = 2
	bsb.border_color = PH_ACCENT
	bsb.content_margin_left = 12.0
	bsb.content_margin_right = 12.0
	bsb.content_margin_top = 8.0
	bsb.content_margin_bottom = 8.0
	bar.add_theme_stylebox_override("panel", bsb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(170, 88)
	back.add_theme_font_size_override("font_size", FONT_MD)
	back.add_theme_color_override("font_color", PH_ACCENT)
	back.add_theme_color_override("font_hover_color", PH_ACCENT)
	back.add_theme_color_override("font_pressed_color", PH_TEXT)
	back.add_theme_stylebox_override("normal", _btn_style(Color(0.16, 0.19, 0.28)))
	back.add_theme_stylebox_override("hover", _btn_style(Color(0.20, 0.24, 0.34)))
	back.add_theme_stylebox_override("pressed", _btn_style(Color(0.24, 0.28, 0.40)))
	back.add_theme_stylebox_override("focus", _btn_style(Color(0.16, 0.19, 0.28)))
	back.pressed.connect(_show_home)
	row.add_child(back)
	var lab := Label.new()
	lab.text = "Policies"
	lab.add_theme_font_size_override("font_size", FONT_LG)
	lab.add_theme_color_override("font_color", PH_TEXT)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(lab)
	_root.add_child(bar)


## Hero card: current government, big and gold, with approval/mood line.
func _pol2_hero(box: VBoxContainer, pol) -> void:
	var gd: Dictionary = pol.gov_def()
	var anarchy: bool = bool(pol.state.get("anarchy", false))
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _pol2_card_style(true))
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 4)
	card.add_child(cbox)
	var name := Label.new()
	name.text = "ANARCHY" if anarchy else String(gd.get("name", ""))
	name.add_theme_font_size_override("font_size", FONT_LG)
	name.add_theme_color_override("font_color", PH_RED if anarchy else PH_ACCENT)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cbox.add_child(name)
	if not anarchy:
		var fl := Label.new()
		fl.text = String(GOV_FLAVOR.get(pol.gov_key(), ""))
		fl.add_theme_font_size_override("font_size", FONT_SM)
		fl.add_theme_color_override("font_color", PH_TEXT_DIM)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cbox.add_child(fl)
	var avg: float = pol.avg_approval()
	var ap_word: String = "Loyal" if avg >= 60 else ("Grumbling" if avg >= 40 else ("STRIKE RISK" if avg >= 25 else "REVOLT RISK"))
	var hap: float = float(pol.state.get("happiness", 62.0))
	var mood_word: String = "Content" if hap >= 60 else ("Restless" if hap >= 35 else "ANGRY")
	var stat := Label.new()
	stat.text = "Approval %d/100 \u00b7 %s\nMood %d/100 \u00b7 %s" % [int(round(avg)), ap_word, int(round(hap)), mood_word]
	stat.add_theme_font_size_override("font_size", FONT_SM)
	stat.add_theme_color_override("font_color", PH_TEXT)
	cbox.add_child(stat)
	box.add_child(card)


## Government picker: 7 governments + ANARCHY as tappable cards.
func _pol2_governments(box: VBoxContainer, pol) -> void:
	var title := Label.new()
	title.text = "Government"
	title.add_theme_font_size_override("font_size", FONT_MD)
	title.add_theme_color_override("font_color", PH_TEXT)
	box.add_child(title)
	var anarchy: bool = bool(pol.state.get("anarchy", false))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	var cur: String = pol.gov_key()
	for key: String in SimPolicies.GOV_ORDER:
		var g2: Dictionary = pol.gov_def(key)
		var selected: bool = (not anarchy) and cur == key
		var gk: String = key
		grid.add_child(_pol2_gov_button(
			String(g2.get("name", "")),
			String(GOV_FLAVOR.get(key, "")),
			selected,
			func() -> void:
				if pol.set_government(gk):
					_show_policies()))
	grid.add_child(_pol2_gov_button(
		"ANARCHY",
		"No taxes. No guards. No rules." if anarchy else "Dissolve all authority.",
		anarchy,
		func() -> void:
			if pol.toggle_anarchy():
				_show_policies()))


## One tappable government card: name + one-line flavor.
func _pol2_gov_button(btn_name: String, flavor: String, selected: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 148)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", _pol2_card_style(selected))
	b.add_theme_stylebox_override("hover", _pol2_card_style(selected))
	b.add_theme_stylebox_override("pressed", _pol2_card_style(true))
	b.add_theme_stylebox_override("focus", _pol2_card_style(selected))
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 14.0
	vbox.offset_right = -14.0
	vbox.offset_top = 12.0
	vbox.offset_bottom = -12.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var nl := Label.new()
	nl.text = btn_name
	nl.add_theme_font_size_override("font_size", FONT_SM)
	nl.add_theme_color_override("font_color", PH_ACCENT if selected else PH_TEXT)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(nl)
	var fl := Label.new()
	fl.text = flavor
	fl.add_theme_font_size_override("font_size", FONT_XS)
	fl.add_theme_color_override("font_color", PH_TEXT_DIM)
	fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(fl)
	b.add_child(vbox)
	b.pressed.connect(on_press)
	return b


## Tax card: big slider, big percent, Set Tax button.
func _pol2_tax(box: VBoxContainer, pol) -> void:
	var tax: int = int(pol.state.get("tax", 0))
	var inc: int = pol.projected_tax_income()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _pol2_card_style(false))
	var cbox := VBoxContainer.new()
	cbox.add_theme_constant_override("separation", 8)
	card.add_child(cbox)
	var title := Label.new()
	title.text = "Royal Tax Rate"
	title.add_theme_font_size_override("font_size", FONT_MD)
	title.add_theme_color_override("font_color", PH_TEXT)
	cbox.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	cbox.add_child(row)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 40
	slider.step = 1
	slider.value = tax
	slider.custom_minimum_size = Vector2(0, 64)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var pct := Label.new()
	pct.text = "%d%%" % tax
	pct.add_theme_font_size_override("font_size", FONT_LG)
	pct.add_theme_color_override("font_color", PH_ACCENT)
	pct.custom_minimum_size = Vector2(140, 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(pct)
	var proj := Label.new()
	proj.text = "Projected: +%d gold/day" % inc
	proj.add_theme_font_size_override("font_size", FONT_SM)
	proj.add_theme_color_override("font_color", PH_TEXT_DIM)
	cbox.add_child(proj)
	var setb := Button.new()
	setb.text = "Set Tax"
	setb.custom_minimum_size = Vector2(0, 96)
	setb.add_theme_font_size_override("font_size", FONT_MD)
	setb.add_theme_color_override("font_color", PH_TEXT)
	setb.add_theme_color_override("font_hover_color", PH_TEXT)
	setb.add_theme_color_override("font_pressed_color", PH_ACCENT)
	setb.add_theme_stylebox_override("normal", _btn_style(Color(0.16, 0.19, 0.28)))
	setb.add_theme_stylebox_override("hover", _btn_style(Color(0.20, 0.24, 0.34)))
	setb.add_theme_stylebox_override("pressed", _btn_style(Color(0.24, 0.28, 0.40)))
	setb.add_theme_stylebox_override("focus", _btn_style(Color(0.16, 0.19, 0.28)))
	slider.value_changed.connect(func(v: float) -> void:
		pct.text = "%d%%" % int(v))
	setb.pressed.connect(func() -> void:
		pol.set_tax(int(slider.value))
		_show_policies())
	cbox.add_child(setb)
	box.add_child(card)


## Town Watch card: the guard tiers the docstring always promised, as three
## tappable tiers (body lane #1 — no dead ends: the government panel read
## "Guard: None (0 on duty)" with no lever anywhere in the UI).
func _pol2_watch(box: VBoxContainer, pol) -> void:
	var title := Label.new()
	title.text = "Town Watch"
	title.add_theme_font_size_override("font_size", FONT_MD)
	title.add_theme_color_override("font_color", PH_TEXT)
	box.add_child(title)
	if _pol_watch_notice != "":
		var note := Label.new()
		note.text = _pol_watch_notice
		note.add_theme_font_size_override("font_size", FONT_SM)
		note.add_theme_color_override("font_color", PH_RED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)
		_pol_watch_notice = ""
	var info := Label.new()
	info.text = "%d on duty" % pol.guard_units().size()
	info.add_theme_font_size_override("font_size", FONT_SM)
	info.add_theme_color_override("font_color", PH_TEXT_DIM)
	box.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	var cur: String = String(pol.state.get("guard", "none"))
	var fee: int = pol.guard_decree_fee()
	var tiers: Array = [
		["none", "Disband", "No watch. Crimes go unanswered."],
		["militia", "Militia", "%dg decree · 4 guards · 2g/day each" % fee],
		["professional", "Professional", "%dg decree · 8 guards · 5g/day each" % fee],
	]
	for t: Array in tiers:
		var tk: String = String(t[0])
		grid.add_child(_pol2_gov_button(
			String(t[1]), String(t[2]), cur == tk,
			func() -> void: _press_watch_tier(pol, tk)))


## Watch-tier press: honest feedback when the decree fails (broke treasury or
## anarchy) instead of a silent no-op.
func _press_watch_tier(pol, tier: String) -> void:
	if pol.set_guard(tier):
		_show_policies()
		return
	if bool(pol.state.get("anarchy", false)) and tier != "none":
		_pol_watch_notice = "No guards under anarchy — restore order first."
	else:
		_pol_watch_notice = "The %dg decree costs more than the treasury holds." \
			% pol.guard_decree_fee()
	_show_policies()


## Plague Doctrine card (Jeremy 2026-10-11): the ruler's answer to the
## plague — twisted or benevolent, changeable anytime, even mid-outbreak.
## Shows the live sick count so the choice is informed, not blind.
func _pol2_plague(box: VBoxContainer, pol) -> void:
	var title := Label.new()
	title.text = "Plague Doctrine"
	title.add_theme_font_size_override("font_size", FONT_MD)
	title.add_theme_color_override("font_color", PH_TEXT)
	box.add_child(title)
	if _pol_plague_notice != "":
		var note := Label.new()
		note.text = _pol_plague_notice
		note.add_theme_font_size_override("font_size", FONT_SM)
		note.add_theme_color_override("font_color", PH_RED)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)
		_pol_plague_notice = ""
	var sick := 0
	var gs = _gs
	if gs != null and gs.get("disease") != null:
		sick = gs.disease.sick_count(gs.player_faction)
	var info := Label.new()
	info.text = "%d sick in your lands right now" % sick if sick > 0 \
		else "No plague in your lands — for now."
	info.add_theme_font_size_override("font_size", FONT_SM)
	info.add_theme_color_override("font_color", PH_RED if sick > 0 else PH_TEXT_DIM)
	box.add_child(info)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	var cur: String = pol.plague_policy()
	for key: String in SimPolicies.PLAGUE_POLICY_ORDER:
		var def: Dictionary = SimPolicies.PLAGUE_POLICIES[key]
		var kk: String = key
		grid.add_child(_pol2_gov_button(
			String(def.get("name", key)), String(def.get("blurb", "")),
			cur == kk,
			func() -> void: _press_plague_policy(pol, kk)))


## Doctrine press: the realm is told, the sim remembers.
func _press_plague_policy(pol, key: String) -> void:
	if pol.set_plague_policy(key):
		_show_policies()
		return
	_pol_plague_notice = "That is already the law of the land."
	_show_policies()


## Forecast app (Jeremy 2026-10-03): the old Calendar, expanded into a
## proper forecast view — month grid + 7-day weather outlook, upcoming
## disasters, and scheduled festivals. App id stays "calendar" for save
## compatibility; only the label changed.
func _show_calendar() -> void:
	_screen = "calendar"
	_clear()
	_header("Calendar")
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var s = _gs.seasons if _gs != null else null
	if s == null:
		var off := Label.new()
		off.text = "The calendar office is closed."
		off.add_theme_font_size_override("font_size", FONT_MD)
		box.add_child(off)
		return
	# Date banner (HTML calendar/clock format: "Mon Bloommoon 1, Year 1").
	var date := Label.new()
	# Jeremy 2026-10-10 (menu-scroll audit): banner labels are display-only;
	# drags starting on them must reach the ScrollContainer.
	date.mouse_filter = Control.MOUSE_FILTER_IGNORE
	date.text = s.date_string()
	date.add_theme_font_size_override("font_size", FONT_LG)
	date.add_theme_color_override("font_color", PH_ACCENT)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(date)
	# Season + day phase (the old weather summary, folded in here).
	var sub := Label.new()
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cur: Dictionary = PhoneWeather.current(_gs)
	var phase: String = "Night" if _gs.is_night else "Day"
	if not cur.is_empty():
		phase = String(cur["day_phase"])
	sub.text = "%s · %s" % [s.season(), phase]
	sub.add_theme_font_size_override("font_size", FONT_MD)
	sub.add_theme_color_override("font_color", PH_TEXT_DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	# Month title.
	var mtitle := Label.new()
	mtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mtitle.text = "%s, Year %d" % [s.month_name(), s.year()]
	mtitle.add_theme_font_size_override("font_size", FONT_MD)
	mtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(mtitle)
	# Month grid: weekday headers + 30 day cells, today highlighted.
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(grid)
	for wd in ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]:
		var h := Label.new()
		h.text = wd
		# Jeremy 2026-10-10 (menu-scroll audit): display-only; drags must
		# reach the ScrollContainer.
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_font_size_override("font_size", FONT_SM)
		h.add_theme_color_override("font_color", PH_TEXT_DIM)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(h)
	var first_wd: int = posmod(s.weekday() - (s.day_of_month() - 1), 7)
	for i in range(first_wd):
		# Jeremy 2026-10-10 (menu-scroll audit): spacer cells must not eat
		# drags — the Forecast list's ScrollContainer owns the gesture.
		var fsp := Control.new()
		fsp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		grid.add_child(fsp)
	var today: int = s.day_of_month()
	# Jeremy 2026-10-04: disaster days are tappable — opens the response
	# panel (military + citizen orders).
	var disaster_days := {}
	var dz = _gs.disasters
	if dz != null:
		for dk in dz.forecast.keys():
			disaster_days[int(dk)] = dz.forecast[dk]
	# Jeremy 2026-10-04 (wake polish): festival days get gold starburst
	# markers on the grid too, mirroring the disaster diamonds. Map
	# absolute festival days into this month via the shared calendar math.
	var festival_days := {}
	if _court != null and _court.policies != null and _gs != null:
		var cy: int = s.year()
		var cm: int = s.month()
		for f: Dictionary in _court.policies.scheduled_festivals():
			var dab: int = int(f.get("day_abs", 0))
			if dab < _gs.day_number:
				continue
			var ymd: Array = _fc_ymd(dab)
			if int(ymd[0]) == cy and int(ymd[1]) == cm:
				festival_days[int(ymd[2])] = f
	for d in range(1, 31):
		if disaster_days.has(d):
			var cell := Button.new()
			# Jeremy 2026-10-10 (menu-scroll audit): PASS so a drag that
			# starts on a disaster day still scrolls the Forecast list;
			# taps still open the response panel (no mid-scroll tap-fire).
			cell.mouse_filter = Control.MOUSE_FILTER_PASS
			cell.text = str(d)
			cell.add_theme_font_size_override("font_size", FONT_MD)
			cell.add_theme_color_override("font_color", PH_RED)
			cell.add_theme_color_override("font_hover_color", PH_ACCENT)
			var csb := StyleBoxFlat.new()
			csb.bg_color = Color(0.35, 0.15, 0.10, 0.9)
			csb.set_corner_radius_all(8)
			cell.add_theme_stylebox_override("normal", csb)
			cell.add_theme_stylebox_override("hover", csb)
			cell.add_theme_stylebox_override("pressed", csb)
			cell.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# Jeremy 2026-10-04: tiny color-coded diamond marker under the
			# day number, keyed to the disaster type.
			var de: Dictionary = disaster_days[d]
			var dot := ForecastIcon.make("disaster",
				_disaster_color(String(de.get("label", ""))), 20.0)
			dot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			dot.position = Vector2(-10, -22)
			cell.add_child(dot)
			# Festival on the same day: gold starburst beside the diamond.
			if festival_days.has(d):
				var fdot := ForecastIcon.make("festival", Color.WHITE, 20.0)
				fdot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
				fdot.position = Vector2(10, -22)
				cell.add_child(fdot)
			var dday := d
			cell.pressed.connect(func() -> void:
				# Jeremy 2026-10-11 (P0): the cell is freed by the teardown
				# it triggers — defer so the emitter finishes its signal
				# cleanly before _clear() runs.
				_show_disaster_response.call_deferred(dday))
			grid.add_child(cell)
			continue
		var cell := Label.new()
		# Jeremy 2026-10-10 (menu-scroll audit): display-only day cells
		# must not eat drags — the ScrollContainer owns the gesture.
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.text = str(d)
		cell.add_theme_font_size_override("font_size", FONT_MD)
		cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if d == today:
			# Jeremy 2026-10-06 (overhaul): today gets a gold ring cell.
			var tcell := PanelContainer.new()
			# Jeremy 2026-10-10 (menu-scroll audit): display-only, must
			# not eat drags — the ScrollContainer owns the gesture.
			tcell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var tsb := StyleBoxFlat.new()
			tsb.bg_color = Color(1.0, 0.84, 0.35, 0.16)
			tsb.set_corner_radius_all(999)
			tsb.border_color = PH_ACCENT.darkened(0.25)
			tsb.set_border_width_all(2)
			tsb.shadow_color = Color(1.0, 0.84, 0.35, 0.25)
			tsb.shadow_size = 8
			tcell.add_theme_stylebox_override("panel", tsb)
			tcell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var tl := Label.new()
			# Jeremy 2026-10-10 (menu-scroll audit): display-only.
			tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tl.text = str(d)
			tl.add_theme_font_size_override("font_size", FONT_MD)
			tl.add_theme_color_override("font_color", PH_ACCENT)
			tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			tcell.add_child(tl)
			grid.add_child(tcell)
			continue
		elif festival_days.has(d):
			# Festival day: gold number + starburst marker (visual only;
			# festivals need no response panel, so the cell stays a label).
			cell.add_theme_color_override("font_color", PH_ACCENT)
			var fdot := ForecastIcon.make("festival", Color.WHITE, 20.0)
			fdot.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			fdot.position = Vector2(-10, -22)
			cell.add_child(fdot)
		else:
			cell.add_theme_color_override("font_color", PH_TEXT)
		grid.add_child(cell)
	# Forecast sections below the grid.
	box.add_child(_section("7-Day Forecast"))
	_forecast_weather_rows(box)
	box.add_child(_section("Upcoming Disasters"))
	_forecast_disaster_rows(box)
	box.add_child(_section("Upcoming Festivals"))
	_forecast_festival_rows(box)


## Jeremy 2026-10-04: dedicated Weather app — the sim's live weather gets
## its own home-screen app instead of living only inside the Forecast
## calendar. Big current-conditions card + the 7-day outlook, drawn
## icons only (tofu rule). The Forecast app keeps its combined
## calendar/disaster/festival view; both read PhoneWeather (never the
## sim directly).
func _show_weather() -> void:
	_screen = "weather"
	_clear()
	_header("Weather")
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var cur: Dictionary = PhoneWeather.current(_gs)
	if cur.is_empty():
		var off := Label.new()
		off.text = "The weather office is closed."
		off.add_theme_font_size_override("font_size", FONT_MD)
		off.add_theme_color_override("font_color", PH_TEXT_DIM)
		off.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(off)
		return
	# Date banner, mirroring the Forecast app's calendar format.
	var s = _gs.seasons if _gs != null else null
	if s != null:
		var date := Label.new()
		# Jeremy 2026-10-10 (menu-scroll audit): display-only; drags must
		# reach the ScrollContainer.
		date.mouse_filter = Control.MOUSE_FILTER_IGNORE
		date.text = s.date_string()
		date.add_theme_font_size_override("font_size", FONT_LG)
		date.add_theme_color_override("font_color", PH_ACCENT)
		date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(date)
	# Current-conditions card: big drawn icon + display string.
	var card := _card()
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var big := ForecastIcon.make(
		String(cur.get("condition", "clear")), Color.WHITE, 96.0)
	row.add_child(big)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var main := Label.new()
	main.text = String(cur["display"])
	main.add_theme_font_size_override("font_size", FONT_XL)
	main.add_theme_color_override("font_color", PH_TEXT)
	main.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(main)
	var sub := Label.new()
	sub.text = "%s · %s" % [String(cur["day_phase"]), String(cur["season"])]
	sub.add_theme_font_size_override("font_size", FONT_MD)
	sub.add_theme_color_override("font_color", PH_TEXT_DIM)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	box.add_child(_section("7-Day Outlook"))
	_forecast_weather_rows(box)


## One forecast row: small plain-text label. No emoji (tofu rule).
func _forecast_row(text: String, accent: bool = false) -> Label:
	var l := Label.new()
	# Jeremy 2026-10-10 (menu-scroll audit): plain-text rows must not eat
	# drags — the list's ScrollContainer owns the gesture.
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SM)
	l.add_theme_color_override("font_color", PH_ACCENT if accent else PH_TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


## Jeremy 2026-10-04: visual forecast row — drawn icon on the left,
## title + subtitle stacked on the right. Icons animate (see
## ForecastIcon); no emoji anywhere (tofu rule).
func _forecast_visual_row(icon: ForecastIcon, title: String,
		subtitle: String, accent: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", FONT_SM)
	t.add_theme_color_override("font_color", PH_ACCENT if accent else PH_TEXT)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(t)
	var s := Label.new()
	s.text = subtitle
	s.add_theme_font_size_override("font_size", FONT_XS)
	s.add_theme_color_override("font_color", PH_TEXT_DIM)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(s)
	row.add_child(col)
	# Jeremy 2026-10-11 (P0 iPhone): pin an explicit minimum height from
	# font metrics. Label autowrap heights are unknown until after the
	# first layout pass, so get_combined_minimum_size() under-reports at
	# build time — inside a Button (not a Container) that collapsed every
	# disaster row to 0px and piled all the text on itself. Font metrics
	# are layout-independent, so the row sizes correctly under any parent.
	var face: Font = t.get_theme_font("font")
	if face != null:
		var need_h := maxf(icon.get_combined_minimum_size().y,
			float(face.get_height(t.get_theme_font_size("font_size"))) \
			+ 2.0 \
			+ float(face.get_height(s.get_theme_font_size("font_size"))))
		row.custom_minimum_size = Vector2(0, need_h)
	return row


## Disaster-type marker color, matched by forecast label text.
static func _disaster_color(label: String) -> Color:
	var l := label.to_lower()
	if l.contains("moose"):
		return Color(0.85, 0.55, 0.20)   # thicc moose orange-brown
	if l.contains("dragon") or l.contains("lizard"):
		return Color(0.30, 0.75, 0.30)    # reptile green
	if l.contains("wizard"):
		return Color(0.55, 0.45, 1.00)    # arcane purple
	if l.contains("bandit") or l.contains("raid"):
		return Color(0.90, 0.25, 0.25)    # hostile red
	if l.contains("ass"):
		return Color(0.75, 0.45, 0.55)    # giant ass pink-brown
	if l.contains("cat"):
		return Color(0.65, 0.65, 0.70)    # cardboard gray
	if l.contains("bastard") or l.contains("count"):
		return Color(0.45, 0.20, 0.60)    # count bastard dark purple
	if l.contains("quake"):
		return Color(0.80, 0.65, 0.30)    # earthquake ochre
	return Color(0.90, 0.25, 0.25)


## Next 7 days from the seasons forecast buffer, routed through
## PhoneWeather.forecast_days() — the one null-safe source of truth
## (never s.forecast directly).
## Jeremy 2026-10-04: visual rows — drawn weather icon + day + condition.
func _forecast_weather_rows(box: VBoxContainer) -> void:
	var days: Array[Dictionary] = PhoneWeather.forecast_days(_gs, 7)
	if days.is_empty():
		box.add_child(_forecast_row("No forecast data."))
		return
	var month_name := ""
	var seas = _gs.get("seasons")
	if seas != null and seas.has_method("month_name"):
		month_name = String(seas.month_name())
	for d in days:
		var lbl := String(d["label"])
		var dom := int(d.get("day_of_month", 0))
		# Jeremy 2026-10-04: rows read "Today (Jun 12): Clear, 72°".
		if bool(d.get("is_today", false)):
			lbl = "Today (%s %d)" % [month_name, dom]
		elif lbl == "Tmrw":
			lbl = "Tomorrow (%s %d)" % [month_name, dom]
		var cond := String(d.get("condition", "clear"))
		var today := bool(d.get("is_today", false))
		box.add_child(_forecast_visual_row(
			ForecastIcon.make(cond),
			lbl,
			"%s, %d°" % [PhoneWeather.condition_label(cond),
				int(d["temp_f"])],
			today))


## Disaster calendar: show the upcoming ones that haven't fired yet,
## routed through PhoneWeather.upcoming_disasters() — the one null-safe
## source of truth (never _gs.disasters directly).
## Jeremy 2026-10-04: rows are tappable — opens the response panel.
## Visual rows: color-coded disaster diamond (pulses when striking today).
func _forecast_disaster_rows(box: VBoxContainer) -> void:
	var shown: int = 0
	for it in PhoneWeather.upcoming_disasters(_gs, 31):
		if bool(it["done"]):
			continue
		var days_away: int = int(it["days_away"])
		var label := String(it["label"])
		var when: String = "TODAY — tap to respond" if days_away == 0 \
			else "in %d day%s (day %d)" % [days_away,
				"" if days_away == 1 else "s", int(it["day_of_month"])]
		var row := Button.new()
		row.text = ""
		# Jeremy 2026-10-10 (menu-scroll audit): PASS so a drag that starts
		# on a disaster row still scrolls the list; taps still open the
		# response panel (no mid-scroll tap-fire).
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_theme_color_override("font_hover_color", PH_ACCENT)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var rsb := StyleBoxEmpty.new()
		row.add_theme_stylebox_override("normal", rsb)
		row.add_theme_stylebox_override("hover", rsb)
		row.add_theme_stylebox_override("pressed", rsb)
		row.add_theme_stylebox_override("focus", rsb)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vrow := _forecast_visual_row(
			ForecastIcon.make("disaster", _disaster_color(label),
				56.0, days_away == 0),
			label, when, days_away == 0)
		# Jeremy 2026-10-11 (P0 iPhone): Button is NOT a Container, so the
		# child row's minimum size never propagated — every row collapsed
		# to 0px and all disaster text piled on top of itself. Anchor the
		# row full-rect and size the button from the row it holds.
		vrow.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_child(vrow)
		row.custom_minimum_size = vrow.get_combined_minimum_size()
		var dday := int(it["day_of_month"])
		row.pressed.connect(func() -> void:
			# Jeremy 2026-10-11 (P0): the row is freed by the teardown it
			# triggers — defer so the emitter finishes its signal cleanly.
			_show_disaster_response.call_deferred(dday))
		box.add_child(row)
		shown += 1
	if shown == 0:
		box.add_child(_forecast_row("No disasters on the horizon."))


## Scheduled festivals from the court's policies, with dates and
## countdowns. Only future ones.
func _forecast_festival_rows(box: VBoxContainer) -> void:
	if _court == null or _court.policies == null or _gs == null:
		box.add_child(_forecast_row("No festivals scheduled."))
		return
	var upcoming: Array = []
	for f: Dictionary in _court.policies.scheduled_festivals():
		if int(f.get("day_abs", 0)) >= _gs.day_number:
			upcoming.append(f)
	upcoming.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("day_abs", 0)) < int(b.get("day_abs", 0)))
	if upcoming.is_empty():
		box.add_child(_forecast_row("No festivals scheduled."))
		return
	for f: Dictionary in upcoming:
		var dab: int = int(f.get("day_abs", 0))
		var in_days: int = dab - _gs.day_number
		# Jeremy 2026-10-04: visual row — celebratory starburst icon.
		box.add_child(_forecast_visual_row(
			ForecastIcon.make("festival"),
			"Festival in %s" % String(f.get("town", "town")),
			"%s (in %d day%s)" % [_fc_date_string(dab),
				in_days, "" if in_days == 1 else "s"],
			in_days == 0))


## [year, month, day_of_month] for an absolute day number, using the same
## calendar math as SimSeasons (game starts at Bloommoon, month 3).
static func _fc_ymd(day_abs: int) -> Array:
	var total: int = maxi(0, day_abs - 1)
	var dpm: int = SimSeasons.DAYS_PER_MONTH
	var m: int = ((SimSeasons.START_MONTH - 1 + total / dpm) % 12) + 1
	var y: int = 1 + (SimSeasons.START_MONTH - 1 + total / dpm) / 12
	var d: int = (total % dpm) + 1
	return [y, m, d]


## "Bloommoon 12, Year 1" for an absolute day number, using the same
## calendar math as SimSeasons (game starts at Bloommoon, month 3).
func _fc_date_string(day_abs: int) -> String:
	var ymd: Array = _fc_ymd(day_abs)
	return "%s %d, Year %d" % [SimSeasons.MONTHS[int(ymd[1]) - 1],
		int(ymd[2]), int(ymd[0])]


## Jeremy 2026-10-04: disaster response panel. Tapping a disaster day on
## the calendar (or an upcoming-disaster row) opens orders:
##   Military: Attack | Ignore | Retreat
##   Citizens: Shelter Indoors | Free to Carry On
## Works for future (forecast), active, and past disasters.
func _show_disaster_response(day_of_month: int) -> void:
	_screen = "disaster_response"
	_clear()
	_header("Disaster Response", "calendar")
	var sc := _scroll()
	var box: VBoxContainer = sc.get_child(0)
	var dz = _gs.disasters if _gs != null else null
	if dz == null:
		box.add_child(_forecast_row("No disaster office."))
		return
	var entry: Dictionary = dz.forecast.get(day_of_month, {})
	if entry.is_empty():
		box.add_child(_forecast_row("No disaster on that day."))
		return
	var label := String(entry.get("label", "?"))
	var kind := String(entry.get("type", ""))
	var done := bool(entry.get("done", false))
	# Title.
	var title := Label.new()
	title.text = "%s — Day %d" % [label, day_of_month]
	title.add_theme_font_size_override("font_size", FONT_LG)
	title.add_theme_color_override("font_color", PH_RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title)
	# Status: find the log record (active or historical) for this kind.
	var log: Dictionary = {}
	if dz.dlog != null:
		log = dz.dlog.active_for_kind(kind)
		if log.is_empty():
			for h in dz.dlog.history():
				if String(h.get("kind", "")) == kind:
					log = h
					break
	var is_active := not log.is_empty() \
		and String(log.get("status", "")) == "active"
	var is_past := not log.is_empty() and not is_active
	var status := Label.new()
	if is_active:
		status.text = "ACTIVE NOW — rampaging"
	elif is_past:
		status.text = "Resolved"
	elif done:
		status.text = "Today — imminent"
	else:
		status.text = "Forecast — not yet arrived"
	status.add_theme_font_size_override("font_size", FONT_MD)
	status.add_theme_color_override("font_color", PH_TEXT_DIM)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	# Past disasters: show the toll, no orders.
	if is_past:
		box.add_child(_section("After-Action Report"))
		var sum: Dictionary = dz.dlog.summary(int(log.get("id", -1)))
		var towns: Array = sum.get("towns", [])
		box.add_child(_forecast_row("Towns visited: %s" % (
			", ".join(towns) if not towns.is_empty() else "none")))
		box.add_child(_forecast_row("Death toll: %d" % int(sum.get("death_toll", 0))))
		for dl in sum.get("death_lines", []):
			box.add_child(_forecast_row("  - %s" % dl))
		return
	# Current orders (from log if active, else forecast entry).
	var mil := "ignore"
	var civ := "free"
	if is_active:
		mil = String(log.get("military_order", "ignore"))
		civ = String(log.get("citizen_order", "free"))
	else:
		var fo: Dictionary = dz.forecast_orders(day_of_month)
		mil = String(fo.get("military", "ignore"))
		civ = String(fo.get("citizens", "free"))
	# Military orders.
	box.add_child(_section("Military Orders"))
	var mil_desc := Label.new()
	mil_desc.text = "Attack: engage it. Ignore: stand down. Retreat: fall back to the halls."
	mil_desc.add_theme_font_size_override("font_size", FONT_SM)
	mil_desc.add_theme_color_override("font_color", PH_TEXT_DIM)
	mil_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(mil_desc)
	var mil_row := HBoxContainer.new()
	mil_row.add_theme_constant_override("separation", 8)
	mil_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(mil_row)
	for o in ["attack", "ignore", "retreat"]:
		var b := _btn(o.capitalize(), func() -> void:
			_set_disaster_military(day_of_month, kind, o))
		if o == mil:
			b.add_theme_color_override("font_color", PH_ACCENT)
		# Jeremy 2026-10-06 (launch readiness): share the row width —
		# natural-width buttons overflowed the ~330px row on iPhone.
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mil_row.add_child(b)
	# Citizen orders.
	box.add_child(_section("Citizen Orders"))
	var civ_desc := Label.new()
	civ_desc.text = "Shelter: indoors, fewer deaths, work halts. Free: carry on, higher risk."
	civ_desc.add_theme_font_size_override("font_size", FONT_SM)
	civ_desc.add_theme_color_override("font_color", PH_TEXT_DIM)
	civ_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(civ_desc)
	var civ_row := HBoxContainer.new()
	civ_row.add_theme_constant_override("separation", 8)
	civ_row.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(civ_row)
	for o2 in ["shelter", "free"]:
		var label2 := "Shelter Indoors" if o2 == "shelter" else "Free to Carry On"
		var b2 := _btn(label2, func() -> void:
			_set_disaster_citizens(day_of_month, kind, o2))
		if o2 == civ:
			b2.add_theme_color_override("font_color", PH_ACCENT)
		# Jeremy 2026-10-06 (launch readiness): share the row width —
		# natural-width buttons overflowed the ~330px row on iPhone.
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		civ_row.add_child(b2)


## Jeremy 2026-10-04: apply a military order from the response panel.
func _set_disaster_military(day_of_month: int, kind: String,
		order: String) -> void:
	var dz = _gs.disasters if _gs != null else null
	if dz == null:
		return
	var applied := false
	if dz.dlog != null:
		var log: Dictionary = dz.dlog.active_for_kind(kind)
		if not log.is_empty():
			applied = dz.set_military_order(int(log.get("id", -1)), order)
	if not applied:
		applied = dz.set_forecast_orders(day_of_month, order, "")
	_show_disaster_response(day_of_month)


## Jeremy 2026-10-04: apply a citizen order from the response panel.
func _set_disaster_citizens(day_of_month: int, kind: String,
		order: String) -> void:
	var dz = _gs.disasters if _gs != null else null
	if dz == null:
		return
	var applied := false
	if dz.dlog != null:
		var log: Dictionary = dz.dlog.active_for_kind(kind)
		if not log.is_empty():
			applied = dz.set_citizen_order(int(log.get("id", -1)), order)
	if not applied:
		applied = dz.set_forecast_orders(day_of_month, "", order)
	_show_disaster_response(day_of_month)
