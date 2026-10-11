class_name Hud
extends CanvasLayer
## Cursing Gnomes — heads-up display (Milestone 3: jobs & buildings).
##
## Touch-first: 56 px+ buttons, big tap targets for Jeremy's iPhone.
##   - Top bar: player faction resources + population (X/24).
##   - BUILD button: opens the build panel (grid of building buttons with
##     costs; unaffordable ones are dimmed).
##   - Selection panel: info about the tapped unit/building; builders get a
##     "build" hint, service buildings show staffing.
##
## Pure UI — sim reads go through the GameState reference the world sets.
## Signals let the world react without the HUD knowing the world.


signal build_requested(btype: String)
signal zone_overlay_toggled
signal drawer_action(action: String)  # save/load/pause/settings/menu/etc.
## Sandbox observe mode: the observer clicked a faction focus button —
## the world aims its camera at that faction's hall.
signal sandbox_camera_focus(faction: String, zoom: float)
## Jeremy 2026-10-07 (direct request): HUD button snaps the camera back to
## the player's faction capitol. The world aims the camera; the HUD just
## asks.
signal snap_camera_to_capitol


const BTN_MIN := Vector2(84, 73)  # touch-friendly minimum button size


var game: GameState
var selection: Selection

var _res_labels: Dictionary = {}   # resource -> Label (Resources tab panel)
var _rate_sampler := ResRateSampler.new()  # rolling/min net income (HTML sampleResRates parity)
var _res_pop_label: Label          # population line in Resources panel
var _build_panel: PanelContainer
var _build_scroll: ScrollContainer  # Jeremy 2026-10-10: build-grid scroll (menu scroll audit)
var _build_grid: GridContainer
var _build_tab_row: HBoxContainer
var _build_tab := "services"  # active build-menu category tab
var _info_panel: PanelContainer
var _info_label: Label
## Jeremy 2026-10-10 (menu scroll audit): selection info panel long-text
## cap — monastery / crystal lore grew the panel past the screen edge with
## no way to scroll it, and could push the nuke ARM button out of reach.
## The label lives in _info_scroll (capped to the safe viewport by
## _cap_info_panel()); the ARM/DISARM button stays pinned below the scroll
## so it is always on-screen and tappable.
var _info_scroll: ScrollContainer
var _info_inner_vbox: VBoxContainer
## Jeremy 2026-10-04: nuclear warfare — ARM/DISARM button for the player's
## own nuke silo (HTML btn-arm-nuke). _nuke_arm_bid is the silo it arms.
var _nuke_arm_btn: Button
var _nuke_arm_bid: int = -1
var _unit_info: UnitInfoPanel
## Jeremy 2026-10-03: X on the unit panel must actually close it.
## _refresh_selection() runs every frame and re-shows the panel while the
## unit stays selected, so remember which unit the user dismissed and skip
## re-showing it until selection changes.
var _unit_panel_dismissed_id: int = -1
## Jeremy 2026-10-03: only rebuild the dossier when the selected unit
## changes; otherwise refresh the bars live (~4 Hz, no rebuild).
var _unit_panel_shown_id: int = -1
var _unit_panel_live_accum: float = 0.0
## Jeremy 2026-10-05 perf: the building / monastery / crystal selection
## branches rebuilt their info text every frame at 60 Hz — including a
## linear `_building_by_id` scan over ALL buildings per frame. Static
## content only needs 5 Hz (0.2 s); the label write is change-guarded.
## Pure implementation throttle: no text, layout, or behavior changes.
var _sel_static_accum: float = 0.0
var _sel_static_target: int = -1

## Jeremy 2026-10-05 perf: the Resources drawer is a stats panel — its
## refresh did ~7 unguarded label writes plus a messenger-thread sort
## (sorted_threads() allocates + sort_custom every frame) and 5-faction
## pop/diplomacy scans at 60 Hz. Drawer content only needs 5 Hz (0.2 s);
## label writes are change-guarded. Pure implementation throttle: no
## text, layout, or behavior changes.
var _drawer_accum: float = 0.0


## Lazily builds the unit dossier panel (modes port).
func _ensure_unit_info() -> void:
	if _unit_info != null and is_instance_valid(_unit_info):
		return
	_unit_info = UnitInfoPanel.new()
	# HTML parity: UnitInfoPanel positions itself top-left (left:8px;top:48px).
	_unit_info.set_ui_scale(_ui_scale)
	_unit_info.visible = false
	_unit_info.dismissed.connect(_on_unit_panel_dismissed)
	# Jeremy 2026-10-06 (polish round 2): "Message" on the world popup
	# opens a Messenger thread with that NPC on the phone.
	_unit_info.message_unit.connect(_on_unit_message)
	add_child(_unit_info)


## Jeremy 2026-10-06 (polish round 2): world-tap -> phone chat. Any NPC,
## even enemies — the phone is how the ruler reaches people.
func _on_unit_message(unit_id: int) -> void:
	_ensure_phone_ui()
	if _phone_ui == null or not is_instance_valid(_phone_ui):
		return
	_phone_ui.visible = true
	_phone_ui.open_thread("u%d" % unit_id)


## The user tapped the panel's X: stop re-showing it for this unit.
func _on_unit_panel_dismissed() -> void:
	if selection != null and is_instance_valid(selection.selected) \
			and selection.selected is UnitNode:
		_unit_panel_dismissed_id = (selection.selected as UnitNode).unit_id
	else:
		_unit_panel_dismissed_id = -1
var _phone_ui: PhoneUI
var _phone_sys: SimPhone
var _court_sys: SimRoyalCourt
var _side_tabs: Dictionary = {}
## Jeremy 2026-10-07 (direct request): floating circular button (top-right,
## inside the safe area) that snaps the camera back to the player's capitol.
var _capitol_btn: Button
var _side_panel: PanelContainer
var _side_panel_scrim: Button  # Jeremy 2026-10-05: tap-outside-to-close
var _side_scroll: ScrollContainer  # Jeremy 2026-10-10: side-panel scroll (menu scroll audit)
var _side_vbox: VBoxContainer
var _active_tab := ""
# Jeremy 2026-10-03: persistent Resources / Government panel content.
var _res_content: VBoxContainer
var _gov_content: VBoxContainer
var _zone_host: VBoxContainer
var _army_host: VBoxContainer
var _zone_built := false
var _drawer: PanelContainer
var _drawer_scrim: Button  # Jeremy 2026-10-05: tap-outside-to-close overlay
var _sys_menu: PanelContainer
var _sys_menu_scrim: Button  # Jeremy 2026-10-05: tap-outside-to-close overlay
var _drawer_vbox: VBoxContainer
# Jeremy 2026-10-06 launch readiness (gate 1): tap-a-resource gather menu
# (HTML tmGatherMenu parity) — tap a tree / gold vein / bush to send
# nearby workers. Tap-outside-to-close scrim, like the system menu.
var _gather_menu: PanelContainer
var _gather_scrim: Button
var _gather_title: Label
var _gather_sub: Label
var _gather_button: Button
var _gather_site_id := -1
# Jeremy 2026-10-07 tap-command: military order menu — tap empty ground
# with a player military unit selected to Move / Attack-Move it there.
# Bottom sheet with tap-outside-to-close scrim, like the gather menu.
var _cmd_menu: PanelContainer
var _cmd_scrim: Button
var _cmd_title: Label
var _cmd_sub: Label
var _cmd_move_btn: Button
var _cmd_attack_btn: Button
var _cmd_cancel_btn: Button
var _cmd_vbox: VBoxContainer  # sheet content (labels + buttons), for height fit
var _cmd_pos := Vector2.ZERO
var _cmd_unit_id := -1
# Jeremy 2026-10-11 power tap menu: contextual bottom sheet for taps on
# FOREIGN faction land (aid, trade, tribute, message, request aid) plus
# military orders when the player has an army. Dynamic buttons per target.
var _power_menu: PanelContainer
var _power_scrim: Button
var _power_title: Label
var _power_sub: Label
var _power_vbox: VBoxContainer  # dynamic action buttons, rebuilt per open
var _power_faction := ""
var _power_pos := Vector2.ZERO

## UI scale: canvas units per CSS px, boosted for readability.
## Jeremy 2026-10-02: "every ui is too small in the game rn".
var _ui_scale := 1.0
var _layout_mode := "portrait"  # portrait | landscape | desktop
## Jeremy 2026-10-08 (4:3 desktop chrome): in-game aspect bucket, orthogonal
## to _layout_mode, mirroring MainMenu ("widescreen" for 16:9+, "standard"
## for 4:3 and narrower). Desktop 4:3 ("standard") gets the slim landscape
## chrome so the tall portrait chrome doesn't eat a fifth of the viewport.
var _aspect := "widescreen"


## Scaled px.
func _s(v: float) -> float:
	return v * _ui_scale


func _si(v: float) -> int:
	return maxi(1, int(round(float(v) * _ui_scale)))


## Canvas units per CSS px on web (1.0 elsewhere), with readability boost.
func _compute_scale() -> float:
	# Jeremy 2026-10-04: fixed 2.5x baseline for iPhone 17. No JS bridge,
	# no viewport math — just a constant. Godot's stretch handles the rest.
	return 2.5
var _res_drawer_labels: Dictionary = {}  # resource -> Label (text only, no emoji)
var _pop_drawer_label: Label
var _peace_drawer_label: Label
var _msg_drawer_button: Button  # drawer "Messages" button (carries unread badge text)
var _gazette_drawer_button: Button  # drawer "Chronicle" button (carries unread-news badge text)
var _weather_drawer_label: Label
var _hint_panel: PanelContainer
var _hint_label: Label
var _hint_tween: Tween
var _paused_label: Label  # persistent "Paused" badge while the tree is paused
# Jeremy 2026-10-05: game-speed selector (slow in-game time on demand).
# Engine.time_scale scales every delta in the game, so no sim file needs
# to change. 0.5x literally halves sim CPU per real second — the perf lever
# he asked the slowdown for. 2026-10-08: 0.25x "turtle" added — he asked to
# slow in-game time FURTHER; 0.25x quarters sim CPU per real second, the
# coolest-phone setting. 2026-10-09: 0.125x "deep turtle" added — he asked
# to slow in-game time FURTHER again; 0.125x eighths sim CPU per real second.
const GAME_SPEEDS := [1.0, 0.5, 0.25, 0.125, 2.0]
var _game_speed := 1.0
var _speed_button: Button  # system-menu speed cycler (label shows live speed)
## Test hook: point the speed-preference persistence at a temp file.
var _settings_path_override := ""
# Sandbox observe mode (HTML sandbox-hud parity). The director HUD replaces
# the standard RTS chrome while SimSandbox runs (player_faction == "").
var _sandbox: SimSandbox = null
## Tap-a-resource gather menu content per work-site kind (HTML tmGatherMenu
## parity — ASCII text only, never emoji: glyphs render as tofu on iPhone).
## Each entry: [title, subtitle, button verb].
const GATHER_MENU_INFO := {
	"tree": ["Tree", "Chop for wood", "Cut tree"],
	"gold_vein": ["Gold vein", "Mine for gold", "Mine gold"],
	"bush": ["Berry bush", "Gather for food", "Pick berries"],
	"rock": ["Rock", "Break it apart", "Break rock"],
}
var _side_tab_bar: HBoxContainer  # bottom tab strip (Jeremy 2026-10-04: tabs moved off the left edge)
var _side_tab_rail: VBoxContainer  # landscape: vertical tab rail, left edge
var _tab_order: Array[String] = []  # stable tab id order for strip<->rail moves
var _bottom_bar: PanelContainer  # bottom menu bar holding the clock
var _urgent_toast: UrgentToast = null  # HTML #toast parity: urgent non-blocking banner
var _chatter_ticker: ChatterTicker = null  # "Overheard" subtitle ticker (2026-10-07): NPC speech without bubbles
var _clock_box: VBoxContainer  # clock labels inside the bottom bar
var _sb_panel: PanelContainer
var _sb_vscroll: ScrollContainer  # Jeremy 2026-10-10 (menu scroll audit, remnants): vertical scroll wrapping the director row stack
var _sb_vbox: VBoxContainer  # Jeremy 2026-10-10 (menu scroll audit, remnants): row stack measured by _cap_sb_panel
var _sb_phase_label: Label
var _sb_clock_label: Label
var _sb_weather_label: Label
var _sb_faction_row: HBoxContainer
var _sb_log_label: Label
var _sb_log_lines: Array[String] = []
# Jeremy 2026-10-04: bottom menu bar (tabs on top of it, Stardew clock
# inside it). The old top-right clock panel was removed — the clock now
# lives in the bar. Design-px height of the bar.
const BOTTOM_BAR_H := 84.0
## Jeremy 2026-10-06 (launch readiness, landscape): slim chrome for
## phone landscape — the stacked 84px bar + 64px tab strip ate half
## the vertical canvas on 844x390 screens. Landscape gets a 48px bar
## and the tabs move to a left vertical rail; desktop keeps the
## portrait chrome in every aspect (16:9 and 4:3).
const BOTTOM_BAR_H_LANDSCAPE := 48.0
const BUBBLE_D := 64.0
const BUBBLE_D_LANDSCAPE := 48.0
var _clock_time_label: Label
var _clock_date_label: Label
# Jeremy 2026-10-04: frame-time debug overlay for diagnosing the 5-second
# performance cliff. Shows FPS, avg frame ms, and spike count.
var _fps_label: Label
var _frame_times: Array[float] = []
var _spike_count := 0
var _fps_accum := 0.0
var _sb_refresh_accum := 0.0


func setup(p_game: GameState, p_selection: Selection) -> void:
	game = p_game
	selection = p_selection
	_ui_scale = _compute_scale()
	_refresh_layout_mode()
	_build_ui()
	_refresh()
	# Jeremy 2026-10-03: "should fit any screen perfectly" — refit the
	# responsive chrome (tab bubbles, drawer/panel offsets) on rotation
	# or window resize so nothing is ever cut off.
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)


## Viewport resized (rotation / window resize): recompute the UI scale and
## refit the viewport-dependent chrome. Full rebuild would lose drawer/tab
## state, so only the responsive chrome is refit here.
func _on_viewport_resized() -> void:
	_ui_scale = _compute_scale()
	_refresh_layout_mode()
	_refit_chrome()
	# Jeremy 2026-10-10 (menu scroll audit, remnants): the direct caps in
	# _refit_chrome() can read pre-layout minimum sizes right after a
	# rotation (wrapped labels re-wrap at the new width). Re-run the
	# deferred recaps so every panel cap settles on post-layout sizes.
	_recap_side_panel()
	_recap_build_panel()
	_recap_info_panel()
	_recap_sb_panel()


## iPhone safe-area insets as Vector4(top, bottom, left, right) in canvas
## units. Uses DisplayServer.get_display_safe_area() for the REAL device
## safe area (Jeremy 2026-10-04: hardcoded guesses kept clipping).
func _safe_insets() -> Vector4:
	var vp := get_viewport()
	if vp == null:
		return Vector4(180.0, 100.0, 20.0, 20.0)
	var vsz := vp.get_visible_rect().size
	var is_desktop := not DisplayServer.is_touchscreen_available() \
		and vsz.x >= 1024.0 and vsz.y >= 600.0
	if is_desktop:
		return Vector4.ZERO
	# Use the real OS-reported safe area when available.
	# Jeremy 2026-10-08 (graphics-hourly): the OS rect is in WINDOW units
	# (CSS px on web), but vsz is in stretch-expanded VIEWPORT units — the
	# old code mixed them and then divided by the UI scale, producing
	# garbage insets. Convert the rect to viewport units first via
	# window_get_size(), which shares the safe rect's coordinate space.
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0 and safe.size.y > 0:
		var winsz := Vector2(DisplayServer.window_get_size())
		if winsz.x > 0.0 and winsz.y > 0.0:
			var k := vsz / winsz
			var top := safe.position.y * k.y
			var left := safe.position.x * k.x
			var bottom := vsz.y - (safe.position.y + safe.size.y) * k.y
			var right := vsz.x - (safe.position.x + safe.size.x) * k.x
			return Vector4(maxf(top, 0.0), maxf(bottom, 0.0), maxf(left, 0.0), maxf(right, 0.0))
	# Fallback to conservative hardcoded values.
	if vsz.x >= vsz.y:
		return Vector4(20.0, 60.0, 120.0, 120.0)
	return Vector4(220.0, 120.0, 20.0, 20.0)


## Position the bottom menu bar, the tab strip riding on top of it, and the
## FPS debug label inside the safe area (Jeremy 2026-10-04: bottom bar
## clears the home indicator via DisplayServer.get_display_safe_area();
## FPS label sits top-right where the clock used to be).
func _position_bottom_bar() -> void:
	if get_viewport() == null:
		return
	var insets := _safe_insets()
	var bar_h := _s(bar_h_for(_layout_mode, _aspect))
	var td := _s(_bubble_d())
	var is_land := _slim_chrome()
	# Bar: full-width, bottom edge riding the safe-area bottom inset.
	if _bottom_bar != null and is_instance_valid(_bottom_bar):
		_bottom_bar.offset_left = 0.0
		_bottom_bar.offset_right = 0.0
		_bottom_bar.offset_top = -(insets.y + bar_h)
		_bottom_bar.offset_bottom = -insets.y
	# Tabs straddle the bar's top edge (bottom ~10% overlapping the bar —
	# Jeremy 2026-10-04: was 25%, covered the clock text). Landscape:
	# the tabs ride a left vertical rail instead; the strip stays hidden.
	if _side_tab_bar != null and is_instance_valid(_side_tab_bar):
		var tab_bottom := -(insets.y + bar_h - td * 0.10)
		_side_tab_bar.offset_left = 0.0
		_side_tab_bar.offset_right = 0.0
		_side_tab_bar.offset_top = tab_bottom - td
		_side_tab_bar.offset_bottom = tab_bottom
	if _side_tab_rail != null and is_instance_valid(_side_tab_rail):
		var rail_x := insets.z + _s(8)
		_side_tab_rail.offset_left = rail_x
		_side_tab_rail.offset_right = rail_x + td
		_side_tab_rail.offset_top = insets.x + _s(8)
		_side_tab_rail.offset_bottom = -(insets.y + bar_h + _s(8))
	# FPS debug label: top-right, inside the safe area.
	if _fps_label != null and is_instance_valid(_fps_label):
		_fps_label.offset_top = insets.x + _s(8)
		_fps_label.offset_right = -insets.w - _s(8)
		_fps_label.offset_bottom = insets.x + _s(30)
		_fps_label.offset_left = _fps_label.offset_right - _s(340)
	# Dropdown panel opens above the bar + tab strip (grows upward from
	# the clear line via GROW_DIRECTION_BEGIN).
	if _side_panel != null and is_instance_valid(_side_panel):
		var clear := insets.y + bar_h + (0.0 if is_land else td) + _s(12)
		_side_panel.offset_left = 0.0
		_side_panel.offset_right = 0.0
		_side_panel.offset_top = -clear
		_side_panel.offset_bottom = -clear
	# Urgent toast banner rides above the bar + tab strip (HTML #toast sat
	# 76px off the viewport bottom; here it clears our own bottom chrome).
	if _urgent_toast != null and is_instance_valid(_urgent_toast) \
			and get_viewport() != null:
		_urgent_toast.refit(insets.y + bar_h + (0.0 if is_land else td) + _s(24),
			get_viewport().get_visible_rect().size.x, _ui_scale)
	# Overheard ticker rides above the urgent toast slot (toast clearance
	# + headroom) so the two never overlap.
	if _chatter_ticker != null and is_instance_valid(_chatter_ticker) \
			and get_viewport() != null:
		_chatter_ticker.refit(insets.y + bar_h + (0.0 if is_land else td) + _s(100),
			get_viewport().get_visible_rect().size.x, _ui_scale)
	# Drawer: full-height menu inside the safe area, left-aligned.
	# Jeremy 2026-10-05: drawer width is responsive — never wider than the
	# screen minus margins (was a fixed 420px, overflowed iPhone portrait).
	if _drawer != null and is_instance_valid(_drawer):
		var vw := get_viewport().get_visible_rect().size.x if get_viewport() != null else 420.0
		var dw := minf(_s(420), vw - insets.z - insets.w - _s(16))
		_drawer.offset_left = insets.z + _s(8)
		_drawer.offset_right = insets.z + _s(8) + dw
		_drawer.offset_top = insets.x
		_drawer.offset_bottom = -insets.y
	# System menu: centered panel, refit to viewport.
	if _sys_menu != null and is_instance_valid(_sys_menu):
		_position_sys_menu()
	# Jeremy 2026-10-06: gather menu bottom sheet, refit to viewport.
	if _gather_menu != null and is_instance_valid(_gather_menu):
		_position_gather_menu()
	# Jeremy 2026-10-07: command menu bottom sheet, refit to viewport.
	if _cmd_menu != null and is_instance_valid(_cmd_menu):
		_position_command_menu()
	# Jeremy 2026-10-11: power tap menu bottom sheet, refit to viewport.
	if _power_menu != null and is_instance_valid(_power_menu):
		_position_power_menu()
	# Selection info panel: top-left popup must clear the Dynamic Island.
	# Jeremy 2026-10-06 (launch readiness): the old fixed 48px top offset
	# tucked under the Island on iPhone 17 — refit against real insets.
	if _info_panel != null and is_instance_valid(_info_panel):
		_info_panel.offset_left = insets.z + _s(8)
		_info_panel.offset_top = insets.x + _s(8)
	# Jeremy 2026-10-07: capitol snap button rides top-right inside the
	# safe area (below the FPS debug label band).
	_position_capitol_button()
	# Jeremy 2026-10-10 (menu scroll audit): viewport-dependent scroll caps.
	_cap_side_panel()
	_cap_build_panel()
	_cap_info_panel()
	_cap_sb_panel()


## Jeremy 2026-10-10 (menu scroll audit): cap the side-panel scroll height
## so long tab content (Resources + expanded ArmyTab / zone host) scrolls
## inside the screen instead of growing past the Dynamic Island. Short
## content keeps the old shrink-to-fit height; the ScrollContainer handles
## tap-vs-drag natively, so scrolling never fires a tap action.
func _cap_side_panel() -> void:
	if _side_scroll == null or not is_instance_valid(_side_scroll):
		return
	if _side_vbox == null or not is_instance_valid(_side_vbox):
		return
	if get_viewport() == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var insets := _safe_insets()
	var bar_h := _s(bar_h_for(_layout_mode, _aspect))
	var td := _s(_bubble_d())
	var is_land := _slim_chrome()
	var clear := insets.y + bar_h + (0.0 if is_land else td) + _s(12)
	# Scroll area must end above the top safe inset, leaving the 24px
	# panel margins + 16px breathing room.
	var max_h := vp.y - clear - insets.x - _s(24) - _s(16)
	max_h = maxf(max_h, 0.0)
	var need := _side_vbox.get_combined_minimum_size().y
	_side_scroll.custom_minimum_size.y = minf(need, max_h)


## Jeremy 2026-10-10 (menu scroll audit): cap the build-menu grid scroll so
## long building lists (Military tab) scroll inside the screen instead of
## running off the bottom with unreachable buttons.
func _cap_build_panel() -> void:
	if _build_scroll == null or not is_instance_valid(_build_scroll):
		return
	if _build_grid == null or not is_instance_valid(_build_grid):
		return
	if get_viewport() == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var insets := _safe_insets()
	# Panel top edge sits at offset_top=72; the scroll shares the panel with
	# the 20px margins, the 36px tab row, and the vbox separation.
	var chrome := _s(72) + _s(20) + _s(36) + 4.0
	var max_h := vp.y - insets.y - _s(24) - chrome
	max_h = maxf(max_h, 0.0)
	var need := _build_grid.get_combined_minimum_size().y
	_build_scroll.custom_minimum_size.y = minf(need, max_h)


## Jeremy 2026-10-10 (menu scroll audit): cap the selection info scroll so
## long monastery / dark-crystal lore scrolls inside the screen instead of
## pushing the panel (and the nuke ARM/DISARM button) past the bottom edge.
## Short content keeps the old shrink-to-fit height; the ScrollContainer
## handles tap-vs-drag natively, so scrolling never fires a tap action.
func _cap_info_panel() -> void:
	if _info_scroll == null or not is_instance_valid(_info_scroll):
		return
	if _info_inner_vbox == null or not is_instance_valid(_info_inner_vbox):
		return
	if get_viewport() == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var insets := _safe_insets()
	# Panel top edge sits at offset_top=insets.x+8; the scroll shares the
	# panel with the 16px margins, the 76px ARM button row, and vbox
	# separation. Leave 24px breathing room above the bottom safe inset.
	var chrome := insets.x + _s(8) + _s(16) + _s(76) + _s(8) + _s(24)
	var max_h := vp.y - insets.y - chrome
	max_h = maxf(max_h, 0.0)
	var need := _info_inner_vbox.get_combined_minimum_size().y
	_info_scroll.custom_minimum_size.y = minf(need, max_h)


## Jeremy 2026-10-10 (menu scroll audit, remnants): cap the sandbox
## director panel's vertical scroll so its 7 stacked rows + log scroll
## inside the screen instead of growing past the bottom edge on small
## landscape phones. Short content keeps the old shrink-to-fit height;
## the ScrollContainer handles tap-vs-drag natively, so scrolling never
## fires a tap action.
func _cap_sb_panel() -> void:
	if _sb_vscroll == null or not is_instance_valid(_sb_vscroll):
		return
	if _sb_vbox == null or not is_instance_valid(_sb_vbox):
		return
	if get_viewport() == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var insets := _safe_insets()
	# Top-wide panel: leave the top safe inset plus 8px breathing room,
	# and keep 96px of world visible below so the panel never swallows
	# the whole screen on tiny landscape phones. Floor at 200px so at
	# least row 1 + a hint of row 2 stay reachable in the worst case.
	var max_h := vp.y - insets.x - _s(8) - _s(96)
	max_h = maxf(max_h, _s(200))
	var need := _sb_vbox.get_combined_minimum_size().y
	_sb_vscroll.custom_minimum_size.y = minf(need, max_h)


## Jeremy 2026-10-10 (menu scroll audit): fire-and-forget recaps for
## content changes. Container minimum sizes refresh on the layout pass, so
## reading them synchronously inside a rebuild sees STALE values (the cap
## lagged one content change behind). These wait two frames — long enough
## for queue_free()d children to die and new children to be measured —
## then apply the cap.
func _recap_side_panel() -> void:
	var tree := get_tree()
	if tree == null:
		_cap_side_panel()
		return
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(_side_scroll):
		return
	_cap_side_panel()


func _recap_build_panel() -> void:
	var tree := get_tree()
	if tree == null:
		_cap_build_panel()
		return
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(_build_scroll):
		return
	_cap_build_panel()


func _recap_info_panel() -> void:
	var tree := get_tree()
	if tree == null:
		_cap_info_panel()
		return
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(_info_scroll):
		return
	_cap_info_panel()


func _recap_sb_panel() -> void:
	var tree := get_tree()
	if tree == null:
		_cap_sb_panel()
		return
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(_sb_vscroll):
		return
	_cap_sb_panel()


## Refit bottom-bar chrome (tab bubbles) + bar/panel/drawer offsets to the
## current viewport.
func _refit_chrome() -> void:
	_position_bottom_bar()
	var bd := _bubble_d()
	for b in _side_tabs.values():
		var btn := b as Button
		if btn != null:
			btn.custom_minimum_size = Vector2(_s(bd), _s(bd))
			_style_bubble_button(btn)


## Jeremy 2026-10-07 ("Overheard"): show one overheard subtitle line.
## speaker = NPC name (or "Army" for system shouts); color = faction
## color. Called by the world when ChatterDirector accepts a line.
func push_chatter(speaker: String, color: Color, text: String) -> void:
	if _chatter_ticker != null and is_instance_valid(_chatter_ticker):
		_chatter_ticker.push(speaker, color, text)


## Jeremy 2026-10-07 (direct request): floating circular button that snaps
## the camera back to the player's faction capitol. Bubble-styled like the
## tab bubbles; real icon art (no placeholder, no emoji tofu).
func _build_capitol_button() -> void:
	if _capitol_btn != null and is_instance_valid(_capitol_btn):
		return
	_capitol_btn = Button.new()
	_capitol_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_capitol_btn.tooltip_text = "Back to my capitol"
	_capitol_btn.expand_icon = true
	var ipath := "res://assets/ui/sidebar/icon_capitol.png"
	if ResourceLoader.exists(ipath):
		_capitol_btn.icon = load(ipath) as Texture2D
	_capitol_btn.pressed.connect(_on_capitol_btn_pressed)
	add_child(_capitol_btn)
	# Hidden in sandbox observe mode — no player capitol there.
	if _sandbox != null:
		_capitol_btn.visible = false
	_position_capitol_button()


## Position the capitol snap button top-right inside the safe area, below
## the FPS debug label band. Touch target stays >= 44pt like the bubbles.
func _position_capitol_button() -> void:
	if _capitol_btn == null or not is_instance_valid(_capitol_btn):
		return
	var insets := _safe_insets()
	var bd := _s(_bubble_d())
	_capitol_btn.custom_minimum_size = Vector2(bd, bd)
	_style_bubble_button(_capitol_btn)
	var r := insets.w + _s(8)
	var top := insets.x + _s(40)  # clears the FPS label band (30px) + gap
	_capitol_btn.offset_right = -r
	_capitol_btn.offset_left = -r - bd
	_capitol_btn.offset_top = top
	_capitol_btn.offset_bottom = top + bd


func _on_capitol_btn_pressed() -> void:
	snap_camera_to_capitol.emit()


## Jeremy 2026-10-03: thin warm-wooden frame around the whole app,
## themed like the game (dark wood #4a3420, gold #c9a227 trim).
## Tasteful edge strips — mouse_filter IGNORE so gameplay taps pass through.
func _build_app_frame() -> void:
	var wood := Color(0.29, 0.20, 0.13)   # #4a3420
	var gold := Color(0.79, 0.64, 0.15)   # #c9a227
	var fw := _s(10)   # wood strip thickness
	var gw := _s(2)    # gold trim thickness
	# Wood strips at the very edge, gold trim just inside.
	# [preset, offset_start, thickness]
	var specs := [
		[Control.PRESET_TOP_WIDE, 0.0, fw, wood],          # top wood
		[Control.PRESET_BOTTOM_WIDE, 0.0, fw, wood],       # bottom wood
		[Control.PRESET_LEFT_WIDE, 0.0, fw, wood],         # left wood
		[Control.PRESET_RIGHT_WIDE, 0.0, fw, wood],       # right wood
		[Control.PRESET_TOP_WIDE, fw, gw, gold],           # top gold
		[Control.PRESET_BOTTOM_WIDE, fw, gw, gold],        # bottom gold
		[Control.PRESET_LEFT_WIDE, fw, gw, gold],         # left gold
		[Control.PRESET_RIGHT_WIDE, fw, gw, gold],        # right gold
	]
	for i: int in range(specs.size()):
		var sp: Array = specs[i]
		var edge: int = i % 4  # 0=top 1=bottom 2=left 3=right
		var strip := ColorRect.new()
		strip.color = sp[3]
		strip.set_anchors_preset(sp[0])
		strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var inset: float = sp[1]
		var thick: float = sp[2]
		match edge:
			0:  # top: hangs down from the top edge
				strip.offset_top = inset
				strip.offset_bottom = inset + thick
			1:  # bottom: hangs up from the bottom edge
				strip.offset_top = -inset - thick
				strip.offset_bottom = -inset
			2:  # left: extends right from the left edge
				strip.offset_left = inset
				strip.offset_right = inset + thick
			3:  # right: extends left from the right edge
				strip.offset_left = -inset - thick
				strip.offset_right = -inset
		add_child(strip)


func _build_ui() -> void:
	_build_app_frame()
	# Jeremy 2026-10-03: overworld is clean — no top resource bar.
	# Resources live in the Resources tab; phone in the Phone tab;
	# build options in the Resources tab. (Top bar fully removed.)

	# Jeremy 2026-10-04: bottom menu bar — tab bubbles ride on top of the
	# bar, Stardew clock lives inside it, FPS debug label goes top-right.
	# (Left sidebar removed.)
	_build_bottom_bar()

	# Jeremy 2026-10-07 (direct request): snap-camera-to-capitol button —
	# a circular bubble riding top-right inside the safe area, styled like
	# the tab bubbles.
	_build_capitol_button()

	# Jeremy 2026-10-04 (graphics-hourly): urgent non-blocking toast banner —
	# HTML #toast parity (showToast + TOAST_URGENT_RE). Urgent Gazette stories
	# pop bottom-center above the bar; everything else stays in the Chronicle.
	_urgent_toast = UrgentToast.new()
	_urgent_toast.setup(game.bus)
	add_child(_urgent_toast)

	# Jeremy 2026-10-07 ("Overheard"): subtitle ticker for overheard NPC
	# speech — the sim's bus.unit_said lines get a voice back without
	# bubbles (all bubbles removed 2026-10-05). Slim, bottom-center,
	# never blocks taps; the world feeds it via push_chatter().
	_chatter_ticker = ChatterTicker.new()
	add_child(_chatter_ticker)

	# --- Build panel (hidden until BUILD tapped) --------------------------
	_build_panel = PanelContainer.new()
	_build_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_build_panel.offset_top = 72
	_build_panel.offset_left = -280
	_build_panel.offset_right = 280
	_build_panel.visible = false
	add_child(_build_panel)
	var bp_margin := MarginContainer.new()
	bp_margin.add_theme_constant_override("margin_left", 10)
	bp_margin.add_theme_constant_override("margin_right", 10)
	bp_margin.add_theme_constant_override("margin_top", 10)
	bp_margin.add_theme_constant_override("margin_bottom", 10)
	_build_panel.add_child(bp_margin)
	var bp_vbox := VBoxContainer.new()
	bp_margin.add_child(bp_vbox)
	_build_tab_row = HBoxContainer.new()
	_build_tab_row.add_theme_constant_override("separation", 4)
	bp_vbox.add_child(_build_tab_row)
	# Jeremy 2026-10-10 (menu-scroll audit): 5 tabs × 100px = 516px —
	# wider than a portrait phone, so the Military tab clipped with no
	# way to tap it. The tab row scrolls horizontally now.
	_hscroll_row(_build_tab_row)
	for tab: Array in SimBuildings.BUILD_TABS:
		var tb := Button.new()
		tb.text = String(tab[1])
		tb.toggle_mode = true
		tb.set_meta("tab", String(tab[0]))
		tb.custom_minimum_size = Vector2(_s(100), _s(36))
		tb.pressed.connect(_on_build_tab.bind(String(tab[0])))
		_build_tab_row.add_child(tb)
	# Jeremy 2026-10-10 (menu scroll audit): the 2-column building grid used
	# to run off the bottom of the screen on phones (Military tab: 17
	# buildings) with no way to reach the lower buttons. It now lives in a
	# ScrollContainer capped by _cap_build_panel().
	_build_scroll = ScrollContainer.new()
	_build_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_build_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bp_vbox.add_child(_build_scroll)
	_build_grid = GridContainer.new()
	_build_grid.columns = 2
	_build_grid.add_theme_constant_override("h_separation", 8)
	_build_grid.add_theme_constant_override("v_separation", 8)
	_build_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_scroll.add_child(_build_grid)
	_rebuild_build_buttons()

	# --- Selection info panel --------------------------------------------
	# HTML parity: floating top-left popup (left:8px; top:48px), not bottom.
	_info_panel = PanelContainer.new()
	_info_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_info_panel.offset_left = _s(8)
	_info_panel.offset_top = _s(48)
	_info_panel.offset_right = _s(8) + minf(get_viewport().get_visible_rect().size.x * 0.82, _s(320))
	_info_panel.visible = false
	add_child(_info_panel)
	var _ip_sb := StyleBoxFlat.new()
	_ip_sb.bg_color = Color(0.078, 0.063, 0.039, 1.0)
	_ip_sb.set_border_width_all(_si(2))
	_ip_sb.border_color = Color(0.788, 0.635, 0.153)
	_ip_sb.set_corner_radius_all(_si(10))
	_info_panel.add_theme_stylebox_override("panel", _ip_sb)
	var ip_margin := MarginContainer.new()
	ip_margin.add_theme_constant_override("margin_left", 12)
	ip_margin.add_theme_constant_override("margin_right", 12)
	ip_margin.add_theme_constant_override("margin_top", 8)
	ip_margin.add_theme_constant_override("margin_bottom", 8)
	_info_panel.add_child(ip_margin)
	var ip_vbox := VBoxContainer.new()
	ip_vbox.add_theme_constant_override("separation", 8)
	ip_margin.add_child(ip_vbox)
	# Jeremy 2026-10-10 (menu scroll audit): selection info panel long-text
	# cap. Monastery / dark-crystal lore runs hundreds of words, which used
	# to grow this panel past the bottom of the screen with no way to
	# scroll — and could push the nuke ARM/DISARM button out of reach. The
	# label lives in a capped ScrollContainer; the button stays pinned
	# below it so it is always on-screen and tappable.
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_vbox.add_child(_info_scroll)
	_info_inner_vbox = VBoxContainer.new()
	_info_inner_vbox.add_theme_constant_override("separation", 0)
	# Display-only content: never eat the drag, so the ScrollContainer owns
	# the gesture and scrolling never fires a tap action.
	_info_inner_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_scroll.add_child(_info_inner_vbox)
	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", _si(24))
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info_inner_vbox.add_child(_info_label)
	# Jeremy 2026-10-04: nuclear warfare — ARM/DISARM button on the
	# player's own nuke silo selection (HTML btn-arm-nuke parity).
	_nuke_arm_btn = Button.new()
	_nuke_arm_btn.add_theme_font_size_override("font_size", _si(26))
	_nuke_arm_btn.custom_minimum_size = Vector2(_s(280), _s(76))
	_nuke_arm_btn.visible = false
	_nuke_arm_btn.pressed.connect(_on_nuke_arm_pressed)
	ip_vbox.add_child(_nuke_arm_btn)

	# --- Hint toast (placement suggestions, zone tool tips) ---------------
	_hint_panel = PanelContainer.new()
	_hint_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_panel.offset_top = 76
	_hint_panel.offset_left = -320
	_hint_panel.offset_right = 320
	_hint_panel.visible = false
	add_child(_hint_panel)
	var h_margin := MarginContainer.new()
	h_margin.add_theme_constant_override("margin_left", 14)
	h_margin.add_theme_constant_override("margin_right", 14)
	h_margin.add_theme_constant_override("margin_top", 8)
	h_margin.add_theme_constant_override("margin_bottom", 8)
	_hint_panel.add_child(h_margin)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", _si(24))
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h_margin.add_child(_hint_label)

	# Persistent "Paused" badge (top-center). HTML only toasts, so a paused
	# game shows nothing persistent — a clear badge is a small QoL win.
	_paused_label = Label.new()
	_paused_label.text = "Paused"
	_paused_label.add_theme_font_size_override("font_size", _si(28))
	_paused_label.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	_paused_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_paused_label.add_theme_constant_override("shadow_offset_x", 2)
	_paused_label.add_theme_constant_override("shadow_offset_y", 2)
	_paused_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paused_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_paused_label.offset_top = 28
	_paused_label.offset_left = -200
	_paused_label.offset_right = 200
	_paused_label.visible = false
	add_child(_paused_label)


## Shows a transient hint toast (fades after a few seconds). Used for zone
## placement suggestions ("House: place in a Residential zone").
func flash_hint(text: String) -> void:
	if _hint_panel == null:
		return
	_hint_label.text = text
	_hint_panel.visible = true
	_hint_panel.modulate.a = 1.0
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	# Tween keeps fading while the tree is paused — otherwise hints stall
	# mid-fade and pile up when the game is paused (the persistent
	# "Paused" badge, not the hint, is the pause indicator).
	_hint_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hint_tween.tween_interval(3.0)
	_hint_tween.tween_property(_hint_panel, "modulate:a", 0.0, 0.6)
	_hint_tween.tween_callback(_hint_panel.hide)


## Persistent paused badge — called by every pause toggle path.
func set_paused(p: bool) -> void:
	if _paused_label != null:
		_paused_label.visible = p


## Responsive tab bubble diameter (design px): scales so the bubbles fit
## the viewport on any screen. Jeremy 2026-10-03: "should fit
## any screen perfectly" — no cut-off content on any phone or orientation.
## Launch-readiness gate 4: per-orientation HUD layout buckets,
## mirroring MainMenu._detect_orientation (portrait/landscape/desktop).
## "landscape" = a touch phone turned sideways (wider than 1.2x tall);
## desktop 16:9+ keeps the standard bottom chrome, but desktop 4:3
## ("standard" aspect) takes the slim chrome too — a squarish PC window
## has no touch rail space to spare and the 84px bar + 64px tab strip
## would eat a fifth of the height (Jeremy 2026-10-08).
##
## Jeremy 2026-10-08 (16:9 / landscape UI compat): unified touch detection.
## DisplayServer.is_touchscreen_available() alone misreports on the Godot
## web export (iPhone Safari) — a phone could get the DESKTOP chrome in
## every orientation. has_feature(FEATURE_TOUCHSCREEN) is the reliable web
## signal; OR-ing keeps every platform where the old call was right still
## right. MainMenu._detect_orientation defaults to this same helper, so the
## menu and the in-game HUD can never disagree about touch again.
static func touchscreen_available() -> bool:
	return DisplayServer.has_feature(DisplayServer.FEATURE_TOUCHSCREEN) \
		or DisplayServer.is_touchscreen_available()


static func layout_mode_for(vsz: Vector2, touchscreen: bool) -> String:
	if not touchscreen and vsz.x >= 1024.0 and vsz.y >= 600.0:
		return "desktop"
	if vsz.x > vsz.y * 1.2:
		return "landscape"
	return "portrait"


static func bar_h_for(mode: String, aspect: String = "widescreen") -> float:
	if slim_chrome_for(mode, aspect):
		return BOTTOM_BAR_H_LANDSCAPE
	return BOTTOM_BAR_H


static func bubble_d_for(mode: String, aspect: String = "widescreen") -> float:
	if slim_chrome_for(mode, aspect):
		return BUBBLE_D_LANDSCAPE
	return BUBBLE_D


## True when the slim landscape chrome (48px bar, left tab rail, 48px
## bubbles) applies: phone landscape, or a 4:3 desktop window where the
## portrait chrome would hog the vertical space. Jeremy 2026-10-08.
static func slim_chrome_for(mode: String, aspect: String = "widescreen") -> bool:
	if mode == "landscape":
		return true
	return mode == "desktop" and aspect == "standard"


func _refresh_layout_mode() -> void:
	var vp := get_viewport()
	var vsz := vp.get_visible_rect().size if vp != null else Vector2(1280, 720)
	_layout_mode = layout_mode_for(vsz, touchscreen_available())
	# Jeremy 2026-10-08: aspect is orthogonal to the mode (MainMenu parity:
	# ratio >= 1.5 = widescreen, else standard).
	_aspect = "widescreen" if vsz.x / maxf(vsz.y, 1.0) >= 1.5 else "standard"
	_apply_layout_mode()


## Show the tab strip (portrait/desktop) or the left rail (landscape)
## and move the 5 tab buttons between them. Reparenting keeps the
## pressed-signal bindings (they live on the buttons).
func _apply_layout_mode() -> void:
	var is_land := _slim_chrome()
	if _side_tab_bar != null and is_instance_valid(_side_tab_bar):
		_side_tab_bar.visible = not is_land and _sandbox == null
	if _side_tab_rail != null and is_instance_valid(_side_tab_rail):
		_side_tab_rail.visible = is_land and _sandbox == null
	var target: Container = _side_tab_rail if is_land else _side_tab_bar
	if target != null and is_instance_valid(target):
		for tab_id in _tab_order:
			var b := _side_tabs.get(tab_id) as Button
			if b != null and b.get_parent() != target:
				(b.get_parent() as Container).remove_child(b)
				target.add_child(b)
				b.custom_minimum_size = Vector2(_s(bubble_d_for(_layout_mode, _aspect)), _s(bubble_d_for(_layout_mode, _aspect)))
	if _clock_time_label != null and is_instance_valid(_clock_time_label):
		_clock_time_label.add_theme_font_size_override("font_size", _si(20 if is_land else 30))
	if _clock_date_label != null and is_instance_valid(_clock_date_label):
		_clock_date_label.add_theme_font_size_override("font_size", _si(14 if is_land else 18))


func _bubble_d() -> float:
	# Jeremy 2026-10-03: sidebar was massive — keep bubbles compact.
	return bubble_d_for(_layout_mode, _aspect)


## Instance shortcut: does the slim landscape chrome apply to the current
## mode+aspect (phone landscape, or 4:3 desktop)? Jeremy 2026-10-08.
func _slim_chrome() -> bool:
	return slim_chrome_for(_layout_mode, _aspect)


## Split the clock text into time + date lines for the Stardew clock in the
## bottom bar. Jeremy 2026-10-04: only writes labels when the text actually
## changes — setting .text every frame forces layout recalculation.
func _refresh_clock_widget() -> void:
	if _clock_box == null or not is_instance_valid(_clock_box):
		return
	if game == null:
		_clock_box.visible = false
		return
	_clock_box.visible = true
	var full: String = _clock_text()
	# _clock_text returns "H:MM AM/PM · Weekday Month Day".
	var parts: PackedStringArray = full.split(" · ")
	var time_text: String = parts[0] if parts.size() >= 1 else full
	var date_text: String = parts[1] if parts.size() >= 2 else ""
	if _clock_time_label.text != time_text:
		_clock_time_label.text = time_text
	if _clock_date_label.text != date_text:
		_clock_date_label.text = date_text


func _build_bottom_bar() -> void:
	# Jeremy 2026-10-04: 5 tabs — Phone, Resources, Government, Diplomacy,
	# Menu. Weather/Calendar lives in the phone's Calendar app; Messages/
	# Squabble are inside the phone. Government is government-only
	# (Policies, Disasters); Diplomacy opens the phone's diplomacy screen
	# directly; Menu opens the drawer (system items).
	# Jeremy 2026-10-04: left sidebar removed — the tabs moved to a bottom
	# menu bar. The bar holds the Stardew clock; the tab bubbles ride on
	# top of the bar (straddling its top edge); the FPS debug label moved
	# to the top-right safe area.
	_bottom_bar = PanelContainer.new()
	_bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Jeremy 2026-10-03: solid warm wood, no transparency; gold top edge.
	var _bbsb := StyleBoxFlat.new()
	_bbsb.bg_color = Color(0.29, 0.20, 0.13, 0.97)  # #4a3420
	_bbsb.border_color = Color(0.79, 0.64, 0.15)    # #c9a227
	_bbsb.border_width_top = _si(3)
	_bottom_bar.add_theme_stylebox_override("panel", _bbsb)
	add_child(_bottom_bar)
	var bar_margin := MarginContainer.new()
	bar_margin.add_theme_constant_override("margin_left", _si(12))
	bar_margin.add_theme_constant_override("margin_right", _si(12))
	bar_margin.add_theme_constant_override("margin_top", _si(4))
	bar_margin.add_theme_constant_override("margin_bottom", _si(4))
	_bottom_bar.add_child(bar_margin)
	var bar_hbox := HBoxContainer.new()
	bar_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	bar_margin.add_child(bar_hbox)
	# Stardew clock, centered in the bar (time over date).
	_clock_box = VBoxContainer.new()
	_clock_box.add_theme_constant_override("separation", 0)
	bar_hbox.add_child(_clock_box)
	_clock_time_label = Label.new()
	_clock_time_label.add_theme_font_size_override("font_size", _si(30))
	_clock_time_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.75))
	_clock_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_box.add_child(_clock_time_label)
	_clock_date_label = Label.new()
	_clock_date_label.add_theme_font_size_override("font_size", _si(18))
	_clock_date_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.58))
	_clock_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_box.add_child(_clock_date_label)

	# Tab strip: circular bubbles straddling the bar's top edge.
	# Added after the bar so the bubbles draw on top of it.
	var strip := HBoxContainer.new()
	strip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	strip.alignment = BoxContainer.ALIGNMENT_CENTER
	# Jeremy 2026-10-07: 5 tabs now (Phone, Resources, Government,
	# Diplomacy, Menu) — tighter separation so all five fit iPhone
	# portrait without crowding the safe areas. Bubbles stay 64px
	# (well above the 44pt touch minimum).
	strip.add_theme_constant_override("separation", _si(12))
	# The strip rect itself never eats taps; the bubble buttons do.
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_tab_bar = strip  # stored: hidden in sandbox observe mode
	add_child(strip)

	# Landscape rail: vertical VBox holding the same 5 tab buttons;
	# _apply_layout_mode() moves the buttons between strip and rail.
	_side_tab_rail = VBoxContainer.new()
	_side_tab_rail.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_side_tab_rail.alignment = BoxContainer.ALIGNMENT_CENTER
	_side_tab_rail.add_theme_constant_override("separation", _si(12))
	_side_tab_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_side_tab_rail.visible = false
	add_child(_side_tab_rail)

	_side_tabs = {}
	# Jeremy 2026-10-03: sidebar is bubbles like the HTML —
	# circular, icon only, gold border.
	# Jeremy 2026-10-03: real icons on the bubbles (emoji tofu in web).
	var _icon_paths := {
		"phone": "res://assets/ui/sidebar/icon_phone.png",
		"resources": "res://assets/ui/sidebar/icon_resources.png",
		"government": "res://assets/ui/sidebar/icon_government.png",
		"diplomacy": "res://assets/ui/sidebar/icon_diplomacy.png",
		"menu": "res://assets/ui/sidebar/icon_menu.png",
	}
	for tab_data in [
		["phone", "Phone"],
		["resources", "Resources"],
		["government", "Government"],
		["diplomacy", "Diplomacy"],
		["menu", "Menu"],
	]:
		var b := Button.new()
		b.tooltip_text = tab_data[1]
		var _bd := _bubble_d()
		b.custom_minimum_size = Vector2(_s(_bd), _s(_bd))
		b.expand_icon = true
		var _ipath: String = String(_icon_paths.get(tab_data[0], ""))
		if _ipath != "" and ResourceLoader.exists(_ipath):
			b.icon = load(_ipath) as Texture2D
		_style_bubble_button(b)
		var tab_id: String = tab_data[0]
		b.pressed.connect(_on_side_tab.bind(tab_id))
		strip.add_child(b)
		_side_tabs[tab_id] = b
		_tab_order.append(tab_id)

	# Dropdown panel for tab content (HTML's #side-dropdown) — opens above
	# the bar + tab strip. Zero-size rect at the clear line; grows upward
	# (GROW_DIRECTION_BEGIN) and outward (BOTH) to fit its content.
	# Jeremy 2026-10-05: tap-outside-to-close scrim behind the panel.
	_side_panel_scrim = Button.new()
	_side_panel_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_side_panel_scrim.text = ""
	var spscrim_sb := StyleBoxFlat.new()
	spscrim_sb.bg_color = Color(0, 0, 0, 0.0)
	_side_panel_scrim.add_theme_stylebox_override("normal", spscrim_sb)
	_side_panel_scrim.add_theme_stylebox_override("hover", spscrim_sb)
	_side_panel_scrim.add_theme_stylebox_override("pressed", spscrim_sb)
	_side_panel_scrim.add_theme_stylebox_override("focus", spscrim_sb)
	_side_panel_scrim.visible = false
	_side_panel_scrim.z_index = 4
	_side_panel_scrim.pressed.connect(func() -> void: _close_side_panel())
	add_child(_side_panel_scrim)
	_side_panel = PanelContainer.new()
	_side_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_side_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_side_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_side_panel.custom_minimum_size = Vector2(_s(340), 0)
	_side_panel.visible = false
	# Jeremy 2026-10-03: solid warm wood, no transparency.
	var _spsb := StyleBoxFlat.new()
	_spsb.bg_color = Color(0.29, 0.20, 0.13, 1.0)
	_spsb.border_color = Color(0.79, 0.64, 0.15, 1.0)
	_spsb.set_border_width_all(3)
	_spsb.set_corner_radius_all(12)
	_side_panel.add_theme_stylebox_override("panel", _spsb)
	add_child(_side_panel)
	var sp_margin := MarginContainer.new()
	sp_margin.add_theme_constant_override("margin_left", 12)
	sp_margin.add_theme_constant_override("margin_right", 12)
	sp_margin.add_theme_constant_override("margin_top", 12)
	sp_margin.add_theme_constant_override("margin_bottom", 12)
	_side_panel.add_child(sp_margin)
	# Jeremy 2026-10-10 (menu scroll audit): tab content (Resources with the
	# expanded ArmyTab, zone host) used to grow the panel past the top of
	# the screen with no way to scroll. The VBox now lives inside a
	# ScrollContainer capped by _cap_side_panel(), so long content scrolls
	# from anywhere on the panel and drags never fire tap actions.
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp_margin.add_child(_side_scroll)
	_side_vbox = VBoxContainer.new()
	_side_vbox.add_theme_constant_override("separation", 8)
	_side_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_scroll.add_child(_side_vbox)

	# Jeremy 2026-10-03: persistent Resources / Government panel content,
	# built once and reparented into _side_vbox when its tab opens.
	_build_resources_content()
	_build_government_content()

	# Full menu drawer (HTML's #ui-panel) — hidden by default.
	_build_drawer()

	# Frame-time debug overlay (Jeremy 2026-10-04): small label in the
	# top-right safe area showing FPS and spike count for the 5-second
	# cliff diagnosis.
	_fps_label = Label.new()
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.add_theme_font_size_override("font_size", _si(14))
	_fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fps_label)

	_position_bottom_bar()


## Big sidebar panel button (matches drawer button sizing).
func _panel_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(_s(300), _s(88))
	b.add_theme_font_size_override("font_size", _si(28))
	b.pressed.connect(on_press)
	return b


## Resource row: pixel-art icon + live text label (never emoji/glyphs —
## they render as tofu boxes on iPhone, Jeremy 2026-10-03). Icons come from
## assets/art/icons/icon_<res>.png via Art.resource_icon(); a missing icon
## just leaves an empty slot, the label still shows. Returns [row, label].
func _res_icon_row(res: String, font_size: int) -> Array:
	var row := HBoxContainer.new()
	# Jeremy 2026-10-11 (menu scroll audit): drag-transparent so the
	# ScrollContainer owns the gesture in the drawer + side panel.
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", _s(12))
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = Art.resource_icon(res)
	icon.custom_minimum_size = Vector2(_s(44), _s(44))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(l)
	return [row, l]


## Resources tab content: resource overview + build/zone/army command.
## Jeremy 2026-10-03: all resource display lives here now (top bar gone).
func _build_resources_content() -> void:
	_res_content = VBoxContainer.new()
	_res_content.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Resources"
	title.add_theme_font_size_override("font_size", _si(36))
	title.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	_res_content.add_child(title)
	_res_pop_label = Label.new()
	_res_pop_label.add_theme_font_size_override("font_size", _si(24))
	_res_content.add_child(_res_pop_label)
	_res_labels = {}
	for res: String in Config.RESOURCES:
		var parts: Array = _res_icon_row(res, _si(28))
		_res_content.add_child(parts[0])
		_res_labels[res] = parts[1]
	# Build / Zone / Army command (was drawer's Command section + Build tab).
	_res_content.add_child(_panel_button("Build", func() -> void:
		_close_side_panel()
		_on_build_toggle()))
	_res_content.add_child(_panel_button("Zone", func() -> void:
		_toggle_zone_host()))
	_zone_host = VBoxContainer.new()
	_zone_host.add_theme_constant_override("separation", 8)
	_zone_host.visible = false
	_res_content.add_child(_zone_host)
	_res_content.add_child(_panel_button("Army", func() -> void:
		_toggle_army_host()))
	_army_host = VBoxContainer.new()
	_army_host.add_theme_constant_override("separation", 8)
	_army_host.visible = false
	_res_content.add_child(_army_host)


## Zone brush buttons (moved from the old zone side-tab branch).
func _ensure_zone_built() -> void:
	if _zone_built:
		return
	_zone_built = true
	for zd in [
		["Residential block", "zone_R"],
		["Commercial block", "zone_C"],
		["Industrial block", "zone_I"],
		["Military block", "zone_M"],
		["Dezone brush", "zone_dezone"],
		["Toggle zone overlay", "zone_toggle"],
		["Done painting", "zone_done"],
	]:
		var b := Button.new()
		b.text = String(zd[0])
		b.custom_minimum_size = Vector2(_s(280), _s(88))
		b.add_theme_font_size_override("font_size", _si(24))
		var ztype: String = zd[1]
		b.pressed.connect(_on_zone_button.bind(ztype))
		_zone_host.add_child(b)


func _toggle_zone_host() -> void:
	_ensure_zone_built()
	_zone_host.visible = not _zone_host.visible
	_recap_side_panel()  # Jeremy 2026-10-10: zone list changes panel height


## Army tab (moved from the old army side-tab branch).
func _show_army_host() -> void:
	if game == null:
		return
	for c in _army_host.get_children():
		c.queue_free()
	ArmyTab.set_ui_scale(_ui_scale)
	ArmyTab.build(game, _army_host)
	_army_host.visible = true
	_recap_side_panel()  # Jeremy 2026-10-10: ArmyTab is the tallest tab content


func _toggle_army_host() -> void:
	if _army_host.visible:
		_army_host.visible = false
	else:
		_show_army_host()
		return
	_recap_side_panel()  # Jeremy 2026-10-10: collapsed back to short content


## Government tab content: policies + realm menu (was drawer's Menu section).
## Jeremy 2026-10-03: Menu sidebar tab deleted — its functions live here.
func _build_government_content() -> void:
	_gov_content = VBoxContainer.new()
	_gov_content.add_theme_constant_override("separation", 8)
	var title := Label.new()
	title.text = "Government"
	title.add_theme_font_size_override("font_size", _si(36))
	title.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	_gov_content.add_child(title)
	_gov_content.add_child(_panel_button("Policies", func() -> void:
		_close_side_panel()
		_open_phone_app("policies")))
	# Jeremy 2026-10-04: government tab is government-only now (Policies,
	# Disasters). System items (Save/Load/Settings/Worlds/Main Menu/Pause)
	# moved to the Menu tab's drawer.
	_gov_content.add_child(_panel_button("Disasters", func() -> void:
		_close_side_panel()
		drawer_action.emit("disasters")))


## Closes the side panel and clears the active tab.
func _close_side_panel() -> void:
	_active_tab = ""
	_side_panel.visible = false
	if _side_panel_scrim != null and is_instance_valid(_side_panel_scrim):
		_side_panel_scrim.visible = false
	if _sys_menu != null and is_instance_valid(_sys_menu):
		_close_sys_menu()
	if _drawer != null and is_instance_valid(_drawer):
		_close_drawer()


## Sidebar tab style: labeled pill buttons, gold border, dark brown bg,
## bold gold caps text with shadow for readability.
func _style_gaz_button(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.29, 0.20, 0.13, 1.0)  # #4a3420
	sb.border_color = Color(0.79, 0.64, 0.15)  # #c9a227
	sb.set_border_width_all(maxi(2, _si(3)))
	sb.set_corner_radius_all(_si(14))
	sb.content_margin_left = _si(8)
	sb.content_margin_right = _si(8)
	sb.content_margin_top = _si(6)
	sb.content_margin_bottom = _si(6)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = _si(6)
	sb.shadow_offset = Vector2(0, _si(2))
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.38, 0.27, 0.17, 1.0)
	sb_h.border_color = Color(1.0, 0.84, 0.31)  # brighter gold on hover
	b.add_theme_stylebox_override("hover", sb_h)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = Color(0.20, 0.14, 0.09, 1.0)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.51))  # #ffe082
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))


## Circular bubble button — HTML .gaz-float-btn parity.
## 52px circle, 3px gold border, dark bg, centered icon.
func _style_bubble_button(b: Button) -> void:
	# Jeremy 2026-10-03: must be a perfect circle bubble, not a rounded square.
	# Use a very large radius to guarantee circularity regardless of scaling.
	var r: int = _si(_bubble_d())  # Full diameter as radius = guaranteed circle.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.29, 0.20, 0.13, 1.0)  # #4a3420
	sb.border_color = Color(0.79, 0.64, 0.15)  # #c9a227
	sb.set_border_width_all(maxi(2, _si(3)))
	sb.set_corner_radius_all(r)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = _si(8)
	b.add_theme_stylebox_override("normal", sb)
	var sb_h := sb.duplicate() as StyleBoxFlat
	sb_h.bg_color = Color(0.38, 0.27, 0.17, 1.0)
	sb_h.border_color = Color(1.0, 0.84, 0.31)
	b.add_theme_stylebox_override("hover", sb_h)
	var sb_p := sb.duplicate() as StyleBoxFlat
	sb_p.bg_color = Color(0.20, 0.14, 0.09, 1.0)
	b.add_theme_stylebox_override("pressed", sb_p)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1.0, 0.88, 0.51))
	b.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
	b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	b.add_theme_constant_override("shadow_offset_x", 1)
	b.add_theme_constant_override("shadow_offset_y", 2)


## Sidebar drawer — HTML #ui-panel parity. Sections: Royal Gazette,
## Resources, Management, Peoples, Leadership, World, Command, Town News,
## Menu. Scrollable, toggled by the ☰ button.
func _build_drawer() -> void:
	# Jeremy 2026-10-05: tap anywhere outside the drawer to close it.
	_drawer_scrim = Button.new()
	_drawer_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drawer_scrim.text = ""
	var dscrim_sb := StyleBoxFlat.new()
	dscrim_sb.bg_color = Color(0, 0, 0, 0.0)
	_drawer_scrim.add_theme_stylebox_override("normal", dscrim_sb)
	_drawer_scrim.add_theme_stylebox_override("hover", dscrim_sb)
	_drawer_scrim.add_theme_stylebox_override("pressed", dscrim_sb)
	_drawer_scrim.add_theme_stylebox_override("focus", dscrim_sb)
	_drawer_scrim.visible = false
	_drawer_scrim.z_index = 9
	_drawer_scrim.pressed.connect(func() -> void: _close_drawer())
	add_child(_drawer_scrim)
	_drawer = PanelContainer.new()
	_drawer.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Jeremy 2026-10-05: opaque dark background — was transparent, world
	# showed through making text unreadable.
	var dbg := StyleBoxFlat.new()
	dbg.bg_color = Color(0.12, 0.09, 0.06, 0.97)
	dbg.border_color = Color(0.79, 0.64, 0.15, 1.0)
	dbg.set_border_width_all(maxi(2, _s(3)))
	dbg.set_corner_radius_all(_s(12))
	_drawer.add_theme_stylebox_override("panel", dbg)
	# Jeremy 2026-10-04: no sidebar anymore — drawer is left-aligned inside
	# the safe area. Exact offsets are applied by _position_bottom_bar().
	_drawer.offset_left = _s(8)
	_drawer.offset_right = _s(8) + _s(420)
	_close_drawer()
	# Drawer above the bottom bar.
	_drawer.z_index = 10
	add_child(_drawer)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_drawer.add_child(scroll)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Jeremy 2026-10-11 (menu scroll audit): drag-transparent containers
	# so the drawer ScrollContainer owns the gesture everywhere.
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(margin)
	_drawer_vbox = VBoxContainer.new()
	_drawer_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drawer_vbox.add_theme_constant_override("separation", 10)
	_drawer_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_drawer_vbox)
	_rebuild_drawer()
	_build_system_menu()
	# Jeremy 2026-10-06: tap-a-resource gather menu — built once here,
	# re-filled per site by show_gather_menu().
	_build_gather_menu()
	# Jeremy 2026-10-07: tap-command military order menu — built once here,
	# re-filled per tap by show_command_menu().
	_build_command_menu()
	_build_power_menu()


## System menu — Jeremy 2026-10-05: the Menu tab opens a REAL menu, not
## the realm drawer. Centered opaque panel: Resume, Settings, Save, Load,
## Saved Worlds, Disasters, Pause, Realm (opens the realm drawer), Main Menu.
func _build_system_menu() -> void:
	# Jeremy 2026-10-07: restore the player's saved speed preference
	# (Main Menu > Settings > Game Speed) instead of forcing 1x — he
	# asked for slower in-game time (thermal relief) and shouldn't have
	# to re-tap it every session. The restore is announced once via a
	# hint so a non-1x speed is never a surprise. Hand-edited junk in
	# the settings file falls back to 1x.
	_game_speed = _saved_game_speed()
	Engine.time_scale = _game_speed
	if _game_speed != 1.0:
		flash_hint("Game speed %s — your saved setting." \
			% _speed_text().trim_prefix("Speed: "))
	# Jeremy 2026-10-05: tap anywhere outside the menu to close it.
	# Full-screen dim overlay behind the panel; tapping it dismisses.
	_sys_menu_scrim = Button.new()
	_sys_menu_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sys_menu_scrim.text = ""
	var scrim_sb := StyleBoxFlat.new()
	scrim_sb.bg_color = Color(0, 0, 0, 0.0)
	_sys_menu_scrim.add_theme_stylebox_override("normal", scrim_sb)
	_sys_menu_scrim.add_theme_stylebox_override("hover", scrim_sb)
	_sys_menu_scrim.add_theme_stylebox_override("pressed", scrim_sb)
	_sys_menu_scrim.add_theme_stylebox_override("focus", scrim_sb)
	_sys_menu_scrim.visible = false
	_sys_menu_scrim.z_index = 49
	_sys_menu_scrim.pressed.connect(func() -> void: _close_sys_menu())
	add_child(_sys_menu_scrim)
	_sys_menu = PanelContainer.new()
	_sys_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Jeremy 2026-10-05: "Menu is cut off at the bottom. Can't see it. Too big."
	# Clip children so nothing can draw past the panel edges.
	_sys_menu.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.05, 0.98)
	sb.border_color = Color(0.79, 0.64, 0.15, 1.0)
	sb.set_border_width_all(maxi(3, _s(4)))
	sb.set_corner_radius_all(_s(16))
	sb.content_margin_left = _s(28)
	sb.content_margin_right = _s(28)
	sb.content_margin_top = _s(24)
	sb.content_margin_bottom = _s(24)
	_sys_menu.add_theme_stylebox_override("panel", sb)
	_close_sys_menu()
	_sys_menu.z_index = 50
	add_child(_sys_menu)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _s(12))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_sys_menu.add_child(vbox)
	var title := Label.new()
	title.text = "MENU"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", _si(40))
	title.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	vbox.add_child(title)
	# Jeremy 2026-10-05: menu too tall for phones — the button list scrolls
	# inside the capped panel instead of overflowing off-screen.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	var list := VBoxContainer.new()
	list.mouse_filter = Control.MOUSE_FILTER_IGNORE # 2026-10-11 scroll audit (menu buttons keep STOP)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", _s(12))
	list.alignment = BoxContainer.ALIGNMENT_CENTER
	scroll.add_child(list)
	var items: Array = [
		["Resume", func() -> void: _close_sys_menu()],
		["Settings", func() -> void: _close_sys_menu(); drawer_action.emit("settings")],
		["Save", func() -> void: _close_sys_menu(); drawer_action.emit("save")],
		["Load", func() -> void: _close_sys_menu(); drawer_action.emit("load")],
		["Saved Worlds", func() -> void: _reset_game_speed(); _close_sys_menu(); drawer_action.emit("worlds")],
		["Disasters", func() -> void: _close_sys_menu(); drawer_action.emit("disasters")],
		["Realm", func() -> void: _close_sys_menu(); _open_drawer()],
		["Pause", func() -> void: _close_sys_menu(); drawer_action.emit("pause")],
		["Speed: %s" % _speed_text().trim_prefix("Speed: "), func() -> void: _cycle_game_speed()],
		["Main Menu", func() -> void: _reset_game_speed(); _close_sys_menu(); drawer_action.emit("main_menu")],
	]
	for item in items:
		var b := Button.new()
		b.text = item[0]
		b.custom_minimum_size = Vector2(_s(320), _s(88))
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.add_theme_font_size_override("font_size", _si(28))
		var cb: Callable = item[1]
		b.pressed.connect(cb)
		if String(item[0]).begins_with("Speed:"):
			_speed_button = b  # label updated live by _cycle_game_speed
		list.add_child(b)
	_position_sys_menu()


## Centers the system menu panel in the safe area.
## Jeremy 2026-10-05: panel must fit fully on-screen (iPhone portrait was
## clipping the bottom items). Height is capped to the safe area; the button
## list scrolls inside it.
func _position_sys_menu() -> void:
	if _sys_menu == null or not is_instance_valid(_sys_menu):
		return
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(800, 600)
	var insets := _safe_insets()
	var mw := minf(_s(420), vp.x - insets.z - insets.w - _s(24))
	var avail_h := vp.y - insets.x - insets.y - _s(24)
	var mh := minf(_s(640), avail_h)
	# Jeremy 2026-10-05: with PRESET_FULL_RECT anchors (0,0,1,1), the right
	# and bottom offsets are relative to the far edge — they must be
	# NEGATIVE to center. Positive values shoved the panel off-screen right.
	var mx := insets.z + (vp.x - insets.z - insets.w - mw) / 2.0
	var my := insets.x + (vp.y - insets.x - insets.y - mh) / 2.0
	_sys_menu.offset_left = mx
	_sys_menu.offset_right = -(vp.x - mx - mw)
	_sys_menu.offset_top = my
	_sys_menu.offset_bottom = -(vp.y - my - mh)


## Jeremy 2026-10-05: tapping anywhere outside the menu closes it.
## The scrim (dim full-screen button behind the panel) handles the tap.
func _open_sys_menu() -> void:
	if _sys_menu != null and is_instance_valid(_sys_menu):
		_position_sys_menu()
		_sys_menu.visible = true
	if _sys_menu_scrim != null and is_instance_valid(_sys_menu_scrim):
		_sys_menu_scrim.visible = true


func _close_sys_menu() -> void:
	if _sys_menu != null and is_instance_valid(_sys_menu):
		_sys_menu.visible = false
	if _sys_menu_scrim != null and is_instance_valid(_sys_menu_scrim):
		_sys_menu_scrim.visible = false


func _toggle_sys_menu() -> void:
	if _sys_menu != null and is_instance_valid(_sys_menu) and _sys_menu.visible:
		_close_sys_menu()
	else:
		_open_sys_menu()


## Tap-a-resource gather menu (HTML tmGatherMenu parity, Jeremy 2026-10-06
## launch readiness gate 1). Tapping a tree / gold vein / bush opens this
## bottom sheet; the button sends up to 6 nearby free workers via
## SimIndustry.order_gather. Built once, re-filled per site.
func _build_gather_menu() -> void:
	# Tap-outside-to-close scrim (transparent full-screen button).
	_gather_scrim = Button.new()
	_gather_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gather_scrim.text = ""
	var scrim_sb := StyleBoxFlat.new()
	scrim_sb.bg_color = Color(0, 0, 0, 0.0)
	_gather_scrim.add_theme_stylebox_override("normal", scrim_sb)
	_gather_scrim.add_theme_stylebox_override("hover", scrim_sb)
	_gather_scrim.add_theme_stylebox_override("pressed", scrim_sb)
	_gather_scrim.add_theme_stylebox_override("focus", scrim_sb)
	_gather_scrim.visible = false
	_gather_scrim.z_index = 59
	_gather_scrim.pressed.connect(func() -> void: _close_gather_menu())
	add_child(_gather_scrim)
	_gather_menu = PanelContainer.new()
	_gather_menu.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_gather_menu.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.05, 0.98)
	sb.border_color = Color(0.79, 0.64, 0.15, 1.0)
	sb.set_border_width_all(maxi(3, _s(4)))
	sb.set_corner_radius_all(_s(16))
	sb.content_margin_left = _s(28)
	sb.content_margin_right = _s(28)
	sb.content_margin_top = _s(20)
	sb.content_margin_bottom = _s(20)
	_gather_menu.add_theme_stylebox_override("panel", sb)
	_gather_menu.visible = false
	_gather_menu.z_index = 60
	add_child(_gather_menu)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _s(10))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gather_menu.add_child(vbox)
	_gather_title = Label.new()
	_gather_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gather_title.add_theme_font_size_override("font_size", _si(34))
	_gather_title.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	vbox.add_child(_gather_title)
	_gather_sub = Label.new()
	_gather_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gather_sub.add_theme_font_size_override("font_size", _si(24))
	_gather_sub.add_theme_color_override("font_color", Color(0.85, 0.75, 0.58))
	vbox.add_child(_gather_sub)
	_gather_button = Button.new()
	_gather_button.custom_minimum_size = Vector2(_s(320), _s(88))
	_gather_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_gather_button.add_theme_font_size_override("font_size", _si(28))
	_gather_button.pressed.connect(_on_gather_pressed)
	vbox.add_child(_gather_button)
	_position_gather_menu()


## Bottom sheet, centered horizontally, cleared above the home indicator.
## Height is fixed from the known content (title + sub + one big button)
## so the sheet never clips or drifts off-screen.
func _position_gather_menu() -> void:
	if _gather_menu == null or not is_instance_valid(_gather_menu):
		return
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(800, 600)
	var insets := _safe_insets()
	var mh := _s(300)
	var mx := insets.z + _s(12)
	# PRESET_BOTTOM_WIDE anchors (0,1,1,1): left is from the left edge,
	# right/top/bottom are from the far edges — the far-edge offsets must
	# be NEGATIVE (same gotcha as _position_sys_menu).
	_gather_menu.offset_left = mx
	_gather_menu.offset_right = -(insets.w + _s(12))
	_gather_menu.offset_top = -(insets.y + _s(12) + mh)
	_gather_menu.offset_bottom = -(insets.y + _s(12))


## Opens the gather menu for a harvestable work site. Re-fills the title,
## subtitle, and button verb from GATHER_MENU_INFO.
func show_gather_menu(site: Dictionary) -> void:
	if _gather_menu == null or not is_instance_valid(_gather_menu):
		return
	var kind := String(site.get("kind", "tree"))
	var info: Array = GATHER_MENU_INFO.get(kind, GATHER_MENU_INFO["tree"])
	_gather_site_id = int(site.get("id", -1))
	_gather_title.text = String(info[0])
	_gather_sub.text = String(info[1])
	_gather_button.text = "%s  ·  sends nearby workers" % String(info[2])
	_position_gather_menu()
	_gather_menu.visible = true
	if _gather_scrim != null and is_instance_valid(_gather_scrim):
		_gather_scrim.visible = true


func _close_gather_menu() -> void:
	_gather_site_id = -1
	if _gather_menu != null and is_instance_valid(_gather_menu):
		_gather_menu.visible = false
	if _gather_scrim != null and is_instance_valid(_gather_scrim):
		_gather_scrim.visible = false


## HTML-verbatim result messages: "N workers sent" / "No free workers".
func _on_gather_pressed() -> void:
	var site_id := _gather_site_id
	_close_gather_menu()
	if game == null or game.industry == null or site_id < 0:
		return
	var n: int = int(game.industry.order_gather(site_id))
	flash_hint("No free workers" if n == 0 else "%d workers sent" % n)


## --- Tap-command military order menu (Jeremy 2026-10-07) -------------------
## Bottom sheet: Move Here / Attack-Move Here / squad toggle / Cancel.
## Thumb-friendly: big buttons, safe-area aware, tap-outside-to-close.


func _build_command_menu() -> void:
	_cmd_scrim = Button.new()
	_cmd_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cmd_scrim.text = ""
	var scrim_sb := StyleBoxFlat.new()
	scrim_sb.bg_color = Color(0, 0, 0, 0.0)
	_cmd_scrim.add_theme_stylebox_override("normal", scrim_sb)
	_cmd_scrim.add_theme_stylebox_override("hover", scrim_sb)
	_cmd_scrim.add_theme_stylebox_override("pressed", scrim_sb)
	_cmd_scrim.add_theme_stylebox_override("focus", scrim_sb)
	_cmd_scrim.visible = false
	_cmd_scrim.z_index = 59
	_cmd_scrim.pressed.connect(func() -> void: _close_command_menu())
	add_child(_cmd_scrim)
	_cmd_menu = PanelContainer.new()
	_cmd_menu.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_cmd_menu.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.05, 0.98)
	sb.border_color = Color(0.79, 0.64, 0.15, 1.0)
	sb.set_border_width_all(maxi(3, _s(4)))
	sb.set_corner_radius_all(_s(16))
	sb.content_margin_left = _s(28)
	sb.content_margin_right = _s(28)
	sb.content_margin_top = _s(20)
	sb.content_margin_bottom = _s(20)
	_cmd_menu.add_theme_stylebox_override("panel", sb)
	_cmd_menu.visible = false
	_cmd_menu.z_index = 60
	add_child(_cmd_menu)
	# Jeremy 2026-10-10 (tap-to-command clip P0): the sheet content lives in a
	# vertical ScrollContainer so wrapped text + big buttons can never push
	# the sheet off-screen — narrow phones wrap, short landscape scrolls.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cmd_menu.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _s(10))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_cmd_vbox = vbox
	_cmd_title = Label.new()
	_cmd_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Jeremy 2026-10-10 (tap-to-command clip P0): the title/subtitle WRAP
	# instead of overflowing the sheet's right edge ("Command Milita").
	_cmd_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cmd_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cmd_title.add_theme_font_size_override("font_size", _si(34))
	_cmd_title.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	vbox.add_child(_cmd_title)
	_cmd_sub = Label.new()
	_cmd_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cmd_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cmd_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cmd_sub.add_theme_font_size_override("font_size", _si(24))
	_cmd_sub.add_theme_color_override("font_color", Color(0.85, 0.75, 0.58))
	vbox.add_child(_cmd_sub)
	_cmd_move_btn = _command_button("Move Here")
	_cmd_move_btn.pressed.connect(func() -> void: _on_command_move())
	vbox.add_child(_cmd_move_btn)
	_cmd_attack_btn = _command_button("Attack-Move Here")
	_cmd_attack_btn.pressed.connect(func() -> void: _on_command_attack_move())
	vbox.add_child(_cmd_attack_btn)
	_cmd_cancel_btn = _command_button("Cancel")
	_cmd_cancel_btn.pressed.connect(func() -> void: _close_command_menu())
	vbox.add_child(_cmd_cancel_btn)
	_position_command_menu()


func _command_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	# Jeremy 2026-10-10 (tap-to-command clip P0): buttons FILL the sheet
	# width instead of centering a fixed 320-unit minimum — the old minimum
	# was wider than the portrait content area, clipping "Attack-Move He...".
	b.custom_minimum_size = Vector2(_s(280), _s(88))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", _si(28))
	return b


## Bottom sheet, centered horizontally, cleared above the home indicator.
## Jeremy 2026-10-10 (tap-to-command clip P0): the sheet height follows the
## wrapped content instead of a fixed 480 — narrow phones wrap the title and
## subtitle to more lines. Capped so the sheet never covers the map; taller
## content (short landscape) scrolls inside the sheet.
func _position_command_menu() -> void:
	if _cmd_menu == null or not is_instance_valid(_cmd_menu):
		return
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(800, 600)
	var insets := _safe_insets()
	var mh := _command_menu_content_h()
	mh = maxf(mh, _s(320.0))
	mh = minf(mh, maxf(_s(320.0), vp.y - insets.x - insets.y - _s(48.0)))
	var mx := insets.z + _s(12)
	# PRESET_BOTTOM_WIDE anchors (0,1,1,1): left is from the left edge,
	# right/top/bottom are from the far edges — the far-edge offsets must
	# be NEGATIVE (same gotcha as _position_gather_menu).
	_cmd_menu.offset_left = mx
	_cmd_menu.offset_right = -(insets.w + _s(12))
	_cmd_menu.offset_top = -(insets.y + _s(12) + mh)
	_cmd_menu.offset_bottom = -(insets.y + _s(12))


## Wrapped content height: the vbox minimum (labels report their wrapped
## height once laid out) plus the panel stylebox margins. Before the first
## layout pass the labels report single-line heights, so show_command_menu
## defers a refit via _fit_command_menu_height.
func _command_menu_content_h() -> float:
	if _cmd_vbox == null or not is_instance_valid(_cmd_vbox):
		return _s(480.0)
	return _cmd_vbox.get_combined_minimum_size().y + _s(40.0)


## Deferred refit after the first layout pass: wrapped labels now report
## their true multi-line heights, so the sheet hugs the content exactly.
## Runs before first draw (deferred queue flushes pre-render) — no flicker.
func _fit_command_menu_height() -> void:
	if _cmd_menu == null or not is_instance_valid(_cmd_menu):
		return
	if not _cmd_menu.visible:
		return
	_position_command_menu()


## Opens the command menu for a tap at world_pos. Jeremy 2026-10-07:
## tap-to-command orders the ENTIRE military — no unit selection.
## Jeremy 2026-10-09: never opens with zero commandable military (avoids
## menu spam for players with no army); the tap just does nothing.
## Opens the command menu for a tap at world_pos. Jeremy 2026-10-07:
## tap-to-command orders the ENTIRE military — no unit selection.
## Jeremy 2026-10-09: never opens with zero commandable military (avoids
## menu-spam for a fresh town). Jeremy 2026-10-09 tap-enemy-attack:
## enemy_target=true when the menu was opened by tapping an ENEMY (a
## faction at war with the player, or monsters) — the Attack-Move button
## is relabeled "Attack Target" and the subtitle says so; the order still
## goes to _cmd_pos (the enemy's position), where attack-move chews the
## nearest enemy units first, then buildings.
func show_command_menu(world_pos: Vector2, unit_id: int = -1,
		enemy_target: bool = false) -> void:
	if _cmd_menu == null or not is_instance_valid(_cmd_menu):
		return
	_cmd_pos = world_pos
	_cmd_unit_id = -1
	var n := 0
	if game != null and game.tap_command != null:
		n = game.tap_command.all_military_ids().size()
	if n <= 0:
		return
	_cmd_title.text = "Command Military (%d)" % n
	if enemy_target:
		_cmd_sub.text = "An enemy is marked — tap Attack Target and " \
			+ "your entire military engages it."
		_cmd_attack_btn.text = "Attack Target"
	else:
		_cmd_sub.text = "Tap an order — your entire military marches to the marked spot."
		_cmd_attack_btn.text = "Attack-Move Here"
	_position_command_menu()
	_cmd_menu.visible = true
	_fit_command_menu_height.call_deferred()
	if _cmd_scrim != null and is_instance_valid(_cmd_scrim):
		_cmd_scrim.visible = true


## Honest hint when an order is issued with no military under command
## (defense in depth — the menu only opens when n > 0, so this fires if
## the army died between opening the menu and tapping the button).
const NO_ARMY_HINT := "No military under your command — train soldiers at a barracks."


## Jeremy 2026-10-09: headless-testable outcome of a command-menu button
## press once the order has been issued. "march" = close the menu and
## show the marching hint + map marker; "hint" = the army is gone (died
## between menu-open and tap), keep the menu open with the honest hint.
static func command_order_outcome(ordered: int) -> String:
	return "march" if ordered > 0 else "hint"


func _on_command_move() -> void:
	if game == null or game.tap_command == null:
		_close_command_menu()
		return
	var n: int = game.tap_command.order_all_move(_cmd_pos)
	if command_order_outcome(n) == "hint":
		flash_hint(NO_ARMY_HINT)
		return
	_close_command_menu()
	flash_hint("Move order: %d unit%s marching." % [n, "" if n == 1 else "s"])
	_push_order_marker(_cmd_pos, "move")


func _on_command_attack_move() -> void:
	if game == null or game.tap_command == null:
		_close_command_menu()
		return
	var n: int = game.tap_command.order_all_attack_move(_cmd_pos)
	if command_order_outcome(n) == "hint":
		flash_hint(NO_ARMY_HINT)
		return
	_close_command_menu()
	flash_hint("Attack-move: %d unit%s engaging." % [n, "" if n == 1 else "s"])
	_push_order_marker(_cmd_pos, "attack")


## Order confirmation ping on the map (yellow X = move, red X = attack).
func _push_order_marker(world_pos: Vector2, kind: String) -> void:
	var marker = get_node_or_null("../HeroDestMarker")
	if marker != null and marker.has_method("push"):
		marker.push(world_pos, kind)


## --- Power tap menu (Jeremy 2026-10-11) -------------------------------------------
## The tap menu, made powerful: tapping a FOREIGN faction's land opens a
## contextual bottom sheet — Send Aid (the flagship, outside of war),
## Propose Trade, Offer Tribute, Message Leader, Request Aid, plus the
## military orders when the player commands an army. Same AAA bottom-sheet
## idiom as the command menu: safe-area aware, wrapped text, big buttons,
## tap-outside-to-close, height-capped with internal scroll.


## Pure action lists (headless-testable): main menu for foreign land,
## aid submenu, tribute submenu. relation = diplomacy.relation_state.
static func power_menu_actions(relation: String, has_military: bool) -> Array:
	var acts: Array = [
		{"id": "aid", "label": "Send Aid"},
		{"id": "trade", "label": "Propose Trade"},
		{"id": "tribute", "label": "Offer Tribute"},
		{"id": "message", "label": "Message Leader"},
		{"id": "request_aid", "label": "Request Aid"},
	]
	if has_military:
		acts.append({"id": "move_army", "label": "Move Army Here"})
		acts.append({"id": "attack_move", "label": "Attack-Move Here"})
	acts.append({"id": "cancel", "label": "Cancel"})
	return acts


static func power_aid_actions() -> Array:
	return [
		{"id": "aid_food", "label": "Send 100 Food"},
		{"id": "aid_wood", "label": "Send 100 Wood"},
		{"id": "aid_gold", "label": "Send 100 Gold"},
		{"id": "aid_builders", "label": "Send Builder Crew"},
		{"id": "aid_caravan", "label": "Relief Caravan (Food + Wood + Crew)"},
		{"id": "back", "label": "Back"},
	]


static func power_tribute_actions() -> Array:
	return [
		{"id": "trib_gold", "label": "Tribute 100 Gold"},
		{"id": "trib_wood", "label": "Tribute 100 Wood"},
		{"id": "trib_food", "label": "Tribute 100 Food"},
		{"id": "back", "label": "Back"},
	]


func _build_power_menu() -> void:
	_power_scrim = Button.new()
	_power_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_power_scrim.text = ""
	var scrim_sb := StyleBoxFlat.new()
	scrim_sb.bg_color = Color(0, 0, 0, 0.0)
	_power_scrim.add_theme_stylebox_override("normal", scrim_sb)
	_power_scrim.add_theme_stylebox_override("hover", scrim_sb)
	_power_scrim.add_theme_stylebox_override("pressed", scrim_sb)
	_power_scrim.add_theme_stylebox_override("focus", scrim_sb)
	_power_scrim.visible = false
	_power_scrim.z_index = 59
	_power_scrim.pressed.connect(func() -> void: _close_power_menu())
	add_child(_power_scrim)
	_power_menu = PanelContainer.new()
	_power_menu.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_power_menu.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.08, 0.05, 0.98)
	sb.border_color = Color(0.79, 0.64, 0.15, 1.0)
	sb.set_border_width_all(maxi(3, _s(4)))
	sb.set_corner_radius_all(_s(16))
	sb.content_margin_left = _s(28)
	sb.content_margin_right = _s(28)
	sb.content_margin_top = _s(20)
	sb.content_margin_bottom = _s(20)
	_power_menu.add_theme_stylebox_override("panel", sb)
	_power_menu.visible = false
	_power_menu.z_index = 60
	add_child(_power_menu)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_power_menu.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", _s(10))
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	_power_vbox = vbox
	_power_title = Label.new()
	_power_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_power_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_title.add_theme_font_size_override("font_size", _si(34))
	_power_title.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	vbox.add_child(_power_title)
	_power_sub = Label.new()
	_power_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_power_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_power_sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_sub.add_theme_font_size_override("font_size", _si(24))
	_power_sub.add_theme_color_override("font_color", Color(0.85, 0.75, 0.58))
	vbox.add_child(_power_sub)
	_position_power_menu()


func _power_menu_content_h() -> float:
	if _power_vbox == null or not is_instance_valid(_power_vbox):
		return _s(480.0)
	return _power_vbox.get_combined_minimum_size().y + _s(40.0)


func _position_power_menu() -> void:
	if _power_menu == null or not is_instance_valid(_power_menu):
		return
	var vp := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(800, 600)
	var insets := _safe_insets()
	var mh := _power_menu_content_h()
	mh = maxf(mh, _s(320.0))
	mh = minf(mh, maxf(_s(320.0), vp.y - insets.x - insets.y - _s(48.0)))
	var mx := insets.z + _s(12)
	_power_menu.offset_left = mx
	_power_menu.offset_right = -(insets.w + _s(12))
	_power_menu.offset_top = -(insets.y + _s(12) + mh)
	_power_menu.offset_bottom = -(insets.y + _s(12))


func _fit_power_menu_height() -> void:
	if _power_menu == null or not is_instance_valid(_power_menu):
		return
	if not _power_menu.visible:
		return
	_position_power_menu()


func _close_power_menu() -> void:
	if _power_menu != null and is_instance_valid(_power_menu):
		_power_menu.visible = false
	if _power_scrim != null and is_instance_valid(_power_scrim):
		_power_scrim.visible = false
	_power_faction = ""


func _power_faction_name(faction: String) -> String:
	var d: Dictionary = Config.FACTIONS.get(faction, {})
	var n := String(d.get("name", ""))
	return n if n != "" else faction.capitalize()


## Opens the power menu for a tap on foreign (non-war) faction land.
func show_power_menu_foreign(world_pos: Vector2, faction: String) -> void:
	if _power_menu == null or not is_instance_valid(_power_menu):
		return
	if game == null:
		return
	_power_faction = faction
	_power_pos = world_pos
	_fill_power_main()
	_position_power_menu()
	_power_menu.visible = true
	_fit_power_menu_height.call_deferred()
	if _power_scrim != null and is_instance_valid(_power_scrim):
		_power_scrim.visible = true


func _clear_power_buttons() -> void:
	if _power_vbox == null or not is_instance_valid(_power_vbox):
		return
	for c in _power_vbox.get_children():
		if c != _power_title and c != _power_sub:
			c.queue_free()


func _power_button(label_text: String, action_id: String) -> void:
	var b := _command_button(label_text)
	b.pressed.connect(func() -> void: _power_dispatch(action_id))
	_power_vbox.add_child(b)


func _fill_power_main() -> void:
	if game == null or game.diplomacy == null:
		return
	var me := String(game.player_faction)
	var rel := String(game.diplomacy.relation_state(me, _power_faction))
	var rel_label := rel.capitalize()
	_power_title.text = "%s Lands" % _power_faction_name(_power_faction)
	_power_sub.text = "Relations: %s — tap an action." % rel_label
	_clear_power_buttons()
	var has_army := false
	if game.tap_command != null:
		has_army = game.tap_command.all_military_ids().size() > 0
	for a in power_menu_actions(rel, has_army):
		var ad := a as Dictionary
		_power_button(String(ad.get("label", "")), String(ad.get("id", "")))


func _fill_power_aid() -> void:
	_power_title.text = "Send Aid — %s" % _power_faction_name(_power_faction)
	_power_sub.text = "Kindness is remembered. Aid warms relations."
	_clear_power_buttons()
	for a in power_aid_actions():
		var ad := a as Dictionary
		_power_button(String(ad.get("label", "")), String(ad.get("id", "")))


func _fill_power_tribute() -> void:
	_power_title.text = "Offer Tribute — %s" % _power_faction_name(_power_faction)
	_power_sub.text = "Gold buys goodwill. Choose your gift."
	_clear_power_buttons()
	for a in power_tribute_actions():
		var ad := a as Dictionary
		_power_button(String(ad.get("label", "")), String(ad.get("id", "")))


## Aid site: the victim's nearest hall to the tap, else the tap itself.
func _power_aid_site(faction: String) -> Vector2:
	var halls: Array = SimTerritory.halls_of(game.buildings, faction)
	var best := _power_pos
	var best_d := INF
	for h in halls:
		var hd := h as Dictionary
		if hd == null or hd.is_empty():
			continue
		var d: float = _power_pos.distance_to(
			hd.get("position", Vector2.ZERO))
		if d < best_d:
			best_d = d
			best = hd.get("position", Vector2.ZERO)
	return best


func _power_dispatch(action_id: String) -> void:
	if game == null or _power_faction == "":
		_close_power_menu()
		return
	match action_id:
		"cancel":
			_close_power_menu()
		"back":
			_fill_power_main()
			_fit_power_menu_height.call_deferred()
		"aid":
			_fill_power_aid()
			_fit_power_menu_height.call_deferred()
		"tribute":
			_fill_power_tribute()
			_fit_power_menu_height.call_deferred()
		"aid_food", "aid_wood", "aid_gold":
			_power_send_resource(_power_faction,
				String(action_id).trim_prefix("aid_"), 100.0)
		"aid_builders":
			_power_send_builders(_power_faction)
		"aid_caravan":
			_power_send_caravan(_power_faction)
		"trib_gold", "trib_wood", "trib_food":
			_power_pay_tribute(_power_faction,
				String(action_id).trim_prefix("trib_"), 100.0)
		"trade":
			_power_propose_trade(_power_faction)
		"message":
			_power_message_leader(_power_faction)
		"request_aid":
			_power_request_aid(_power_faction)
		"move_army":
			_power_order_move()
		"attack_move":
			_power_order_attack_move()


func _power_send_resource(faction: String, resource: String,
		amount: float) -> void:
	if game.disaster_aid == null:
		flash_hint("Aid system not ready.")
		return
	var r: Dictionary = game.disaster_aid.send_player_resources(
		faction, resource, amount)
	flash_hint(String(r.get("msg", "")))
	if bool(r.get("ok", false)):
		_close_power_menu()


func _power_send_builders(faction: String) -> void:
	if game.disaster_aid == null:
		flash_hint("Aid system not ready.")
		return
	var r: Dictionary = game.disaster_aid.dispatch_player_aid(
		faction, _power_aid_site(faction))
	flash_hint(String(r.get("msg", "")))
	if bool(r.get("ok", false)):
		_close_power_menu()


func _power_send_caravan(faction: String) -> void:
	if game.disaster_aid == null:
		flash_hint("Aid system not ready.")
		return
	var msgs: Array[String] = []
	var r1: Dictionary = game.disaster_aid.send_player_resources(
		faction, "food", 150.0)
	msgs.append(String(r1.get("msg", "")))
	var r2: Dictionary = game.disaster_aid.send_player_resources(
		faction, "wood", 100.0)
	msgs.append(String(r2.get("msg", "")))
	var r3: Dictionary = game.disaster_aid.dispatch_player_aid(
		faction, _power_aid_site(faction))
	msgs.append(String(r3.get("msg", "")))
	flash_hint("  ".join(msgs))
	if bool(r1.get("ok", false)) or bool(r2.get("ok", false)) \
			or bool(r3.get("ok", false)):
		_close_power_menu()


func _power_pay_tribute(faction: String, resource: String,
		amount: float) -> void:
	var paid: float = game.diplomacy.pay_tribute(
		String(game.player_faction), faction, resource, amount)
	if paid > 0.0:
		flash_hint("Tribute paid: %d %s to the %s." % [
			int(paid), resource, _power_faction_name(faction)])
		_close_power_menu()
	else:
		flash_hint("You have no %s to give." % resource)


## Fair opening offer from real stockpiles: 100 of the player's biggest
## surplus for 80 of the target's biggest stock. The AI evaluates for
## real — accept, counter, or refuse — through the trade-deals system.
func _power_propose_trade(faction: String) -> void:
	if game.trade_deals == null:
		flash_hint("Trade system not ready.")
		return
	var me := String(game.player_faction)
	var offer_res := ""
	var offer_amt := 0.0
	for r in Config.RESOURCES:
		var rs := String(r)
		var amt: float = game.resources.get_amount(me, rs)
		if amt > 150.0 and amt > offer_amt:
			offer_amt = amt
			offer_res = rs
	if offer_res == "":
		flash_hint("You have no surplus to trade.")
		return
	var req_res := ""
	var req_amt := 0.0
	for r in Config.RESOURCES:
		var rs := String(r)
		if rs == offer_res:
			continue
		var amt: float = game.resources.get_amount(faction, rs)
		if amt > req_amt:
			req_amt = amt
			req_res = rs
	if req_res == "":
		flash_hint("They have nothing to trade back.")
		return
	var res: Dictionary = game.trade_deals.propose(me, faction,
		{offer_res: 100.0}, {req_res: 80.0}, "once", 1, false)
	flash_hint(String(res.get("msg", "Trade proposed.")))
	_close_power_menu()


func _power_message_leader(faction: String) -> void:
	_close_power_menu()
	_open_phone_app("messenger")
	if _phone_ui != null and is_instance_valid(_phone_ui):
		_phone_ui.open_thread(SimFactionLeaders.key_for(faction))


## Ask a foreign faction for aid. Warm friends share; cold ones decline.
func _power_request_aid(faction: String) -> void:
	# Inbound aid: when the donor agrees, a real relief wagon rolls out of
	# THEIR hall to ours (Jeremy 2026-10-11: "Aid missions visibly travel,
	# deliver, return" — both directions). Delivery, credit, and the
	# relations boost all happen on arrival; declines/empty stores are
	# handled inside the request.
	if game.disaster_aid == null:
		flash_hint("Aid system not ready.")
		_close_power_menu()
		return
	var r: Dictionary = game.disaster_aid.request_inbound_aid(faction)
	flash_hint(String(r.get("msg", "")))
	_close_power_menu()


## Military orders from the power menu (same orders as the command menu).
func _power_order_move() -> void:
	if game == null or game.tap_command == null:
		_close_power_menu()
		return
	var n: int = game.tap_command.order_all_move(_power_pos)
	if command_order_outcome(n) == "hint":
		flash_hint(NO_ARMY_HINT)
		return
	_close_power_menu()
	flash_hint("Move order: %d unit%s marching." % [n, "" if n == 1 else "s"])
	_push_order_marker(_power_pos, "move")


func _power_order_attack_move() -> void:
	if game == null or game.tap_command == null:
		_close_power_menu()
		return
	var n: int = game.tap_command.order_all_attack_move(_power_pos)
	if command_order_outcome(n) == "hint":
		flash_hint(NO_ARMY_HINT)
		return
	_close_power_menu()
	flash_hint("Attack-move: %d unit%s engaging." % [n, "" if n == 1 else "s"])
	_push_order_marker(_power_pos, "attack")


func _close_command_menu() -> void:
	_cmd_unit_id = -1
	if _cmd_menu != null and is_instance_valid(_cmd_menu):
		_cmd_menu.visible = false
	if _cmd_scrim != null and is_instance_valid(_cmd_scrim):
		_cmd_scrim.visible = false


## Jeremy 2026-10-05: drawer open/close helpers — the scrim shows/hides
## with the drawer so tapping outside closes it.
func _open_drawer() -> void:
	_rebuild_drawer()
	if _drawer != null and is_instance_valid(_drawer):
		_drawer.visible = true
	if _drawer_scrim != null and is_instance_valid(_drawer_scrim):
		_drawer_scrim.visible = true


func _close_drawer() -> void:
	if _drawer != null and is_instance_valid(_drawer):
		_drawer.visible = false
	if _drawer_scrim != null and is_instance_valid(_drawer_scrim):
		_drawer_scrim.visible = false


## Game-speed selector (system menu). Cycles 1x -> 0.5x -> 0.25x -> 2x -> 1x.
## The slowdowns come FIRST: Jeremy asked to slow in-game time (thermal
## relief) — twice, so 0.5x AND a 0.25x "turtle" now sit ahead of 2x, one
## and two taps away from normal.
## Engine.time_scale scales every delta in the game (sim, animation,
## tweens), so in-game time genuinely slows — and 0.25x quarters sim CPU
## per real second. The menu stays open so the speed can be tapped
## repeatedly; the button label always shows the live speed. Independent
## of pause (which uses get_tree().paused).
func _speed_text() -> String:
	# Explicit branches (not %g formatting): GDScript's % operator has no
	# %g, so a format string would throw at runtime.
	if _game_speed < 1.0:
		if _game_speed < 0.5:
			if _game_speed < 0.25:
				return "Speed: 0.125x"
			return "Speed: 0.25x"
		return "Speed: 0.5x"
	if _game_speed > 1.0:
		return "Speed: 2x"
	return "Speed: 1x"


func _cycle_game_speed() -> void:
	var i := GAME_SPEEDS.find(_game_speed)
	_game_speed = GAME_SPEEDS[(i + 1) % GAME_SPEEDS.size()]
	Engine.time_scale = _game_speed
	if _speed_button != null and is_instance_valid(_speed_button):
		_speed_button.text = _speed_text()
	flash_hint("Game speed: %s." % _speed_text().trim_prefix("Speed: "))
	_persist_game_speed()


## Settings-file path for the speed preference (test hook override first).
func _user_settings_path() -> String:
	if _settings_path_override != "":
		return _settings_path_override
	return GraphicsTiers.SETTINGS_PATH


## Read the saved speed preference; anything not in GAME_SPEEDS -> 1.0.
func _saved_game_speed() -> float:
	var disk := GraphicsTiers.read_user_settings_at(_user_settings_path())
	var v: float = float(disk.get("game_speed", 1.0))
	if not GAME_SPEEDS.has(v):
		return 1.0
	return v


## Merge the current speed into the settings file (other writers' keys
## survive — same merge pattern as the main menu's _save_settings).
func _persist_game_speed() -> void:
	var disk := GraphicsTiers.read_user_settings_at(_user_settings_path())
	disk["game_speed"] = _game_speed
	var f := FileAccess.open(_user_settings_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(disk))
	f.close()


## Back to 1x before leaving the world (menu/worlds buttons): the main
## menu has no HUD to normalize the scale, so reset here instead.
func _reset_game_speed() -> void:
	_game_speed = 1.0
	Engine.time_scale = 1.0
	if _speed_button != null and is_instance_valid(_speed_button):
		_speed_button.text = _speed_text()


## Rebuilds drawer contents (called on open + on refresh for live values).
func _rebuild_drawer() -> void:
	for c in _drawer_vbox.get_children():
		c.queue_free()
	# Jeremy 2026-10-04: game may be nil when the HUD is built headless
	# (tests) — only build game-dependent sections when it exists.
	var has_game := game != null
	# Header
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE # 2026-10-11 scroll audit (close Button keeps STOP)
	head.add_theme_constant_override("separation", 8)
	_drawer_vbox.add_child(head)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "REALM"
	title.add_theme_font_size_override("font_size", _si(32))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	# Jeremy 2026-10-04 (polish): back chevron, never an "X".
	close.text = ""
	close.custom_minimum_size = Vector2(_s(72), _s(72))
	var chev := DrawnChevron.new(Color(0.95, 0.95, 0.95), _s(9.0))
	chev.position = Vector2(_s(16), _s(16))
	chev.size = Vector2(_s(40), _s(40))
	close.add_child(chev)
	var csb := StyleBoxEmpty.new()
	close.add_theme_stylebox_override("normal", csb)
	close.add_theme_stylebox_override("hover", csb)
	close.add_theme_stylebox_override("pressed", csb)
	close.add_theme_stylebox_override("focus", csb)
	close.pressed.connect(func() -> void: _close_drawer())
	head.add_child(close)

	# ROYAL GAZETTE
	_drawer_section("ROYAL GAZETTE")
	_gazette_drawer_button = _drawer_button("Chronicle", func() -> void: _open_phone_app("gazette"))
	_msg_drawer_button = _drawer_button("Messages", func() -> void: _open_phone_app("messenger"))
	_drawer_button("Policies", func() -> void: _open_phone_app("policies"))

	# Resources (live) — pixel-art icons + text labels, never emoji: resource
	# emoji render as tofu boxes on iPhone (Jeremy 2026-10-03). Short caps
	# labels like the sidebar bubbles (BLD/WX/MSG/CHT/POL).
	_drawer_section("RESOURCES")
	_res_drawer_labels = {}
	for res: String in Config.RESOURCES:
		var parts: Array = _res_icon_row(res, _si(24))
		_drawer_vbox.add_child(parts[0])
		_res_drawer_labels[res] = parts[1]

	# Management
	_drawer_section("MANAGEMENT")
	_drawer_button("Resource Management", func() -> void: drawer_action.emit("resource_mgmt"))

	# Peoples (live per-faction population)
	_drawer_section("PEOPLES")
	_pop_drawer_label = Label.new()
	_pop_drawer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE # 2026-10-11 scroll audit
	_pop_drawer_label.add_theme_font_size_override("font_size", _si(24))
	_drawer_vbox.add_child(_pop_drawer_label)

	# Leadership
	_drawer_section("LEADERSHIP")
	_peace_drawer_label = Label.new()
	_peace_drawer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE # 2026-10-11 scroll audit
	_peace_drawer_label.add_theme_font_size_override("font_size", _si(24))
	_drawer_vbox.add_child(_peace_drawer_label)

	# World
	_drawer_section("WORLD")
	_weather_drawer_label = Label.new()
	_weather_drawer_label.mouse_filter = Control.MOUSE_FILTER_IGNORE # 2026-10-11 scroll audit
	_weather_drawer_label.add_theme_font_size_override("font_size", _si(24))
	_drawer_vbox.add_child(_weather_drawer_label)
	# Jeremy 2026-10-04: HTML parity — the HTML build has a floating
	# Weather & Calendar button (gaz-float-wxcal); the Godot drawer gets
	# a Forecast button that jumps straight to the phone's forecast
	# calendar instead of making Jeremy hunt through the phone apps.
	_drawer_button("Forecast", func() -> void: _open_phone_app("calendar"))

	# Command (HTML's dr-tabs: Build / Zone / Army) — hidden for the
	# sandbox observer (no player faction to build for).
	if has_game and game.player_faction != "":
		_drawer_section("COMMAND")
		_drawer_button("Build", func() -> void:
			_close_drawer()
			_on_build_toggle())
		_drawer_button("Zone", func() -> void:
			_close_drawer()
			_on_side_tab("resources")
			_ensure_zone_built()
			_zone_host.visible = true)
		_drawer_button("Army", func() -> void:
			_close_drawer()
			_on_side_tab("resources")
			_show_army_host())

	# Menu (HTML's Menu section)
	_drawer_section("MENU")
	_drawer_button("Settings", func() -> void: drawer_action.emit("settings"))
	_drawer_button("Saved Worlds", func() -> void: drawer_action.emit("worlds"))
	_drawer_button("Main Menu", func() -> void: drawer_action.emit("main_menu"))
	_drawer_button("Save", func() -> void: drawer_action.emit("save"))
	_drawer_button("Load", func() -> void: drawer_action.emit("load"))
	_drawer_button("Disasters", func() -> void: drawer_action.emit("disasters"))
	_drawer_button("Pause", func() -> void: drawer_action.emit("pause"))


func _drawer_section(text: String) -> void:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE # 2026-10-11 scroll audit
	l.text = text
	l.add_theme_font_size_override("font_size", _si(28))
	# Readability polish 2026-10-04: section headers get the same gold title
	# color as the Resources / Government panels on the dark wood background.
	l.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	_drawer_vbox.add_child(l)


func _drawer_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(_s(320), _s(88))
	b.add_theme_font_size_override("font_size", _si(24))
	b.pressed.connect(func() -> void:
		_close_drawer()
		on_press.call())
	_drawer_vbox.add_child(b)
	return b


## Opens the phone UI to a specific app (HTML's gazette quick buttons).
func _open_phone_app(app: String) -> void:
	if app == "gazette" and _court_sys != null:
		# HTML parity: opening the gazette news tab clears unreadNews.
		_court_sys.mark_news_read()
	_ensure_phone_ui()
	if _phone_ui != null:
		_phone_ui.visible = true
		_phone_ui.open_app(app)


func _ensure_phone_ui() -> void:
	if _phone_ui != null:
		return
	if game == null or _phone_sys == null or _court_sys == null:
		return
	_phone_ui = PhoneUI.new()
	_phone_ui.name = "PhoneUI"
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.name = "PhoneLayer"
	layer.add_child(_phone_ui)
	add_child(layer)
	_phone_ui.setup(game, _phone_sys, _court_sys, game.diplomacy)
	_phone_ui.visible = false


func _on_side_tab(tab: String) -> void:
	# Jeremy 2026-10-04: bottom bar tabs — Phone, Resources, Government,
	# Diplomacy (2026-10-07: diplomacy gets its own main-screen tab),
	# Menu. Weather/Calendar lives in the phone's Calendar app;
	# Messages/Squabble are inside the phone. The Menu tab opens the
	# system menu (Jeremy 2026-10-05: a REAL menu — was wrongly opening the
	# realm drawer).
	# NOTE: "drawer" is still reachable from the sandbox director's menu
	# button (sandbox observe mode) — kept as an alias of "menu".
	if tab == "drawer" or tab == "menu":
		_close_side_panel()
		_close_drawer()
		_toggle_sys_menu()
		return
	if tab == "phone":
		_open_phone_app("home")
		return
	if tab == "diplomacy":
		# Jeremy 2026-10-07: diplomacy tab on the main screen — opens the
		# same diplomacy UI as the phone's Diplomacy app (shared screen).
		_open_phone_app("diplomacy")
		return
	# Toggle: tapping the active tab closes it (HTML behavior).
	if _active_tab == tab:
		_close_side_panel()
		return
	_active_tab = tab
	_side_panel.visible = true
	if _side_panel_scrim != null and is_instance_valid(_side_panel_scrim):
		_side_panel_scrim.visible = true
	# Detach current content without freeing (Resources/Government content
	# is persistent and gets reparented back in).
	for c in _side_vbox.get_children():
		_side_vbox.remove_child(c)
	if tab == "resources":
		_side_vbox.add_child(_res_content)
	elif tab == "government":
		_side_vbox.add_child(_gov_content)
	# Jeremy 2026-10-10 (menu scroll audit): a reopened tab starts at the
	# top instead of a stale scrolled position.
	_side_scroll.scroll_vertical = 0
	# Jeremy 2026-10-10 (menu scroll audit): recap on the next frames so
	# the cap uses post-layout minimum sizes (see _recap_side_panel).
	_recap_side_panel()


func _on_zone_button(ztype: String) -> void:
	if ztype == "zone_toggle":
		zone_overlay_toggled.emit()
		return  # keep the panel open so it can be toggled back
	_side_panel.visible = false
	_active_tab = ""
	build_requested.emit(ztype)


func _count_soldiers(faction: String) -> int:
	if game == null or not game.has_method("get_units"):
		return 0
	var n := 0
	for u in game.get_units():
		if u is Dictionary and str(u.get("faction", "")) == faction:
			var job := str(u.get("job", ""))
			if job in ["soldier", "archer", "guard", "mage", "cannoneer"]:
				n += 1
	return n


func _on_build_tab(tab: String) -> void:
	_build_tab = tab
	for c in _build_tab_row.get_children():
		var b := c as Button
		if b != null:
			b.set_pressed_no_signal(String(b.get_meta("tab", "")) == tab)
	# Jeremy 2026-10-10 (menu scroll audit): a switched tab starts at the
	# top instead of a stale scrolled position.
	_build_scroll.scroll_vertical = 0
	_rebuild_build_buttons()


func _rebuild_build_buttons() -> void:
	for c in _build_grid.get_children():
		c.queue_free()
	var faction: String = game.player_faction
	# Jeremy 2026-10-11 (road infrastructure, direct order): the player's own
	# road tool — drag on the map to plan a road; roadbuilder crews construct
	# it through the staged pipeline (surveyed -> grading -> paving).
	# Roads are free; the crew's labor is the cost (AI parity). Bridges stay
	# the answer for water crossings (the tool rejects wet drags).
	if _build_tab == "roads":
		var rb := Button.new()
		rb.text = "Road\nDrag to lay — free"
		rb.custom_minimum_size = Vector2(_s(300), _s(96))
		rb.add_theme_font_size_override("font_size", _si(22))
		rb.pressed.connect(_on_build_button.bind("road"))
		_build_grid.add_child(rb)
	for btype: String in SimBuildings.BUILDINGS.keys():
		if SimBuildings.build_category(btype) != _build_tab:
			continue
		var d: Dictionary = SimBuildings.BUILDINGS[btype]
		var b := Button.new()
		var cost_str := _cost_str(d.get("costs", {}))
		b.text = "%s\n%s" % [String(d.get("name", btype)), cost_str]
		b.custom_minimum_size = Vector2(_s(300), _s(96))
		b.add_theme_font_size_override("font_size", _si(22))
		var afford: bool = game.resources.can_afford(faction, d.get("costs", {}))
		b.disabled = not afford
		b.modulate = Color(1, 1, 1, 1) if afford else Color(1, 1, 1, 0.45)
		b.pressed.connect(_on_build_button.bind(btype))
		_build_grid.add_child(b)
	# Jeremy 2026-10-10 (menu scroll audit): grid content changed — recap
	# on the next frames so the cap uses post-layout minimum sizes.
	_recap_build_panel()


func _cost_str(costs: Dictionary) -> String:
	var parts: Array[String] = []
	for res: String in costs.keys():
		parts.append("%s %d" % [res, int(costs[res])])
	return ", ".join(parts)


func _on_build_toggle() -> void:
	_build_panel.visible = not _build_panel.visible
	if _build_panel.visible:
		_rebuild_build_buttons()


## Drawer "Messages" button unread badge (HTML parity: fix79's
## #dr-gazette-msgbadge — total unseen per-thread count, capped at "9+",
## hidden at zero). ASCII-only text suffix: emoji/special glyphs render as
## tofu boxes on iPhone (Jeremy 2026-10-03).
static func format_msg_badge(n: int) -> String:
	if n <= 0:
		return "Messages"
	if n > 9:
		return "Messages (9+)"
	return "Messages (%d)" % n


## Current drawer Messages button text from the phone's unread totals.
func _messages_button_text() -> String:
	var n := 0
	if _phone_sys != null:
		for th in _phone_sys.sorted_threads():
			if th is Dictionary:
				n += maxi(0, int(th.get("unread", 0)))
	return format_msg_badge(n)


## Drawer "Chronicle" button unread-news badge (HTML parity: fix79's
## updateGazetteBadge on #dr-gazette — unreadNews count, capped at "9+",
## hidden at zero). ASCII-only text suffix: emoji/special glyphs render as
## tofu boxes on iPhone (Jeremy 2026-10-03).
static func format_gazette_badge(n: int) -> String:
	if n <= 0:
		return "Chronicle"
	if n > 9:
		return "Chronicle (9+)"
	return "Chronicle (%d)" % n


## Current drawer Chronicle button text from the court's unread stories.
func _gazette_button_text() -> String:
	var n := 0
	if _court_sys != null:
		n = _court_sys.unread_news()
	return format_gazette_badge(n)


## Weather summary (HTML's Weather & Calendar).
func _weather_text() -> String:
	if game == null:
		return "Weather unavailable."
	var day: int = game.day_number
	var phase: String = "Night" if game.is_night else "Day"
	return "Day %d — %s" % [day, phase]


## Wire the phone + court sim systems (called by world after setup).
func set_phone_systems(phone: SimPhone, court: SimRoyalCourt) -> void:
	_phone_sys = phone
	_court_sys = court


func _on_build_button(btype: String) -> void:
	_build_panel.visible = false
	build_requested.emit(btype)


func _process(_delta: float) -> void:
	if game == null:
		return
	_refresh(_delta)
	_refresh_selection(_delta)


## Per-frame HUD refresh (cheap: a dozen label writes).
## Jeremy 2026-10-03: resources live in the Resources tab panel now —
## the overworld top bar is gone.
## Jeremy 2026-10-05 perf: delta feeds the 5 Hz resources-drawer gate.
## Callers that don't advance time (setup, tests) use the default 0.0 —
## the drawer pre-loads its accumulator while hidden, so the first
## refresh after it opens still rebuilds immediately.
func _refresh(delta: float = 0.0) -> void:
	var faction: String = game.player_faction
	if faction == "":
		# Sandbox observe mode: no side chrome — the director HUD refreshes.
		_refresh_sandbox()
		return
	# Rolling per-minute net income sampler (HTML sampleResRates parity):
	# honest stockpile deltas, zero changes to the economy itself.
	var amounts: Dictionary = {}
	for r: String in Config.RESOURCES:
		amounts[r] = game.resources.get_amount(faction, r)
	_rate_sampler.sample(amounts, Time.get_ticks_msec())
	var rates: Dictionary = _rate_sampler.rates_per_min(Config.RESOURCES)
	for res: String in _res_labels.keys():
		var l: Label = _res_labels[res]
		if not is_instance_valid(l):
			continue
		# No emoji icons — tofu boxes on iPhone (Jeremy 2026-10-03).
		# ASCII rate suffix only (HTML's "+2.5/min" rateFmt).
		# Jeremy 2026-10-04: only write when changed — .text every frame
		# forces label re-layout.
		var txt: String = "%s: %d (%s)" % [res.to_upper(),
			int(game.resources.get_amount(faction, res)),
			ResRateSampler.format_rate(float(rates.get(res, 0.0)))]
		if l.text != txt:
			l.text = txt
	var pop: int = game.population.get_faction_pop(faction)
	if _res_pop_label != null and is_instance_valid(_res_pop_label):
		var pop_txt: String = "Pop %d/%d" % [pop, Config.POP_CAP_FACTION]
		if _res_pop_label.text != pop_txt:
			_res_pop_label.text = pop_txt
	_refresh_drawer(delta, faction, pop, rates)
	# Jeremy 2026-10-04: Stardew clock ticks with game time.
	_refresh_clock_widget()


## Clock text (HTML parity: "8:04 AM · Mon Bloommoon 1").
## HTML: 12 months of 30 days, weekdays cycle, game_time drives the hour.
const MONTHS := ["Frostmoon", "Thawmoon", "Bloommoon", "Sunpeak", "Highsun",
	"Harvest", "Fallingleaf", "Darkening", "Snowfall", "Deepfrost",
	"Stillnight", "Newlight"]
const WEEKDAYS := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

func _clock_text() -> String:
	if game == null:
		return ""
	# Jeremy 2026-10-04: use the game's real hour (phase * 24), not the
	# old 86400-based math which ran 180x too slow.
	var hour_float: float = WorkerAI.hour_of_day(game)
	var total_min: int = int(hour_float * 60.0)
	var hour24: int = (total_min / 60) % 24
	var minute: int = total_min % 60
	var ampm: String = "AM" if hour24 < 12 else "PM"
	var hour12: int = hour24 % 12
	if hour12 == 0:
		hour12 = 12
	# Calendar: 30-day months starting at Bloommoon (index 2), day 1.
	var total_days: int = game.day_number - 1
	var month_idx: int = (2 + total_days / 30) % 12
	var day_of_month: int = (total_days % 30) + 1
	var weekday: String = WEEKDAYS[(1 + total_days) % 7]  # day 1 = Mon
	return "%d:%02d %s · %s %s %d" % [hour12, minute, ampm, weekday,
		MONTHS[month_idx], day_of_month]


## Refreshes the drawer's live values (resources, peoples, leadership, world).
## Drawer time gate: opens once per 0.2 s of accumulated delta, then
## closes until the next window. Mirrors _sel_static_gate.
func _drawer_gate(delta: float) -> bool:
	_drawer_accum += delta
	if _drawer_accum >= 0.2:
		_drawer_accum = 0.0
		return true
	return false


func _refresh_drawer(delta: float, faction: String, pop: int, rates: Dictionary) -> void:
	if _drawer == null or not _drawer.visible:
		# Pre-load the accumulator so the first frame after the drawer
		# opens rebuilds immediately instead of showing stale text.
		_drawer_accum = 0.2
		return
	if not _drawer_gate(delta):
		return
	for res: String in _res_drawer_labels.keys():
		var l: Label = _res_drawer_labels[res]
		var txt: String = "%s: %d (%s)" % [res.to_upper(),
			int(game.resources.get_amount(faction, res)),
			ResRateSampler.format_rate(float(rates.get(res, 0.0)))]
		if l.text != txt:
			l.text = txt
	if _pop_drawer_label != null:
		var parts: Array = []
		for f: String in Config.FACTIONS.keys():
			var fc: Dictionary = Config.FACTIONS.get(f, {})
			var nm: String = String(fc.get("name", f))
			parts.append("%s %d" % [nm, game.population.get_faction_pop(f)])
		var pop_txt: String = "  ".join(parts)
		if _pop_drawer_label.text != pop_txt:
			_pop_drawer_label.text = pop_txt
	if _peace_drawer_label != null:
		var war_with := []
		if game.diplomacy != null and game.diplomacy.has_method("factions_at_war_with"):
			war_with = game.diplomacy.factions_at_war_with(game.player_faction)
		var peace_txt: String = \
			"Status: %s" % ("War" if not war_with.is_empty() else "Peace")
		if _peace_drawer_label.text != peace_txt:
			_peace_drawer_label.text = peace_txt
	if _weather_drawer_label != null:
		var weather_txt: String = _weather_text()
		if _weather_drawer_label.text != weather_txt:
			_weather_drawer_label.text = weather_txt
	if _msg_drawer_button != null:
		var msg_txt: String = _messages_button_text()
		if _msg_drawer_button.text != msg_txt:
			_msg_drawer_button.text = msg_txt
	if _gazette_drawer_button != null:
		var gaz_txt: String = _gazette_button_text()
		if _gazette_drawer_button.text != gaz_txt:
			_gazette_drawer_button.text = gaz_txt


## Jeremy 2026-10-05 perf: static selection text (building / monastery /
## crystal info) only rebuilds at 5 Hz or when the selected node changes.
## Returns true when the caller should rebuild the text this frame.
func _sel_static_gate(delta: float, n: Node) -> bool:
	var iid: int = n.get_instance_id()
	if iid != _sel_static_target:
		_sel_static_target = iid
		_sel_static_accum = 0.0
		return true
	_sel_static_accum += delta
	if _sel_static_accum >= 0.2:
		_sel_static_accum = 0.0
		return true
	return false


## Selection panel follows the world's Selection node.
func _refresh_selection(delta: float) -> void:
	if selection == null or selection.selected == null \
			or not is_instance_valid(selection.selected):
		_info_panel.visible = false
		_unit_panel_dismissed_id = -1
		_unit_panel_shown_id = -1
		_sel_static_target = -1
		if _unit_info != null and is_instance_valid(_unit_info):
			_unit_info.visible = false
		return
	var n: Node2D = selection.selected
	_info_panel.visible = true
	_nuke_arm_btn.visible = false
	_nuke_arm_bid = -1
	if n is UnitNode:
		# Full unit dossier (modes port): name/job/faction/gender/city/
		# activity/urge bars/traits/memories/housing.
		_info_panel.visible = false
		_sel_static_target = -1  # unit branch self-manages; reset the static gate
		_ensure_unit_info()
		var un: UnitNode = n as UnitNode
		# Jeremy 2026-10-03: if the user X'd this unit's panel, keep it
		# closed until they select something else.
		if un.unit_id == _unit_panel_dismissed_id:
			if _unit_info != null and is_instance_valid(_unit_info):
				_unit_info.visible = false
			return
		_unit_panel_dismissed_id = -1
		var u: Dictionary = game.get_unit(un.unit_id)
		if un.unit_id != _unit_panel_shown_id:
			# Selection changed: full dossier rebuild.
			_unit_panel_shown_id = un.unit_id
			_unit_panel_live_accum = 0.0
			var town_name := ""
			var tid: int = int(u.get("town_id", -1))
			if game.towns.has(tid):
				town_name = String((game.towns[tid] as Dictionary).get("name", ""))
			# Jeremy 2026-10-04: hostile units get a limited dossier —
			# no stat leaks on enemy clicks.
			var ufaction: String = str(u.get("faction", ""))
			var is_enemy := false
			if game.player_faction != "" and ufaction != "" \
					and ufaction != game.player_faction:
				# Jeremy 2026-10-05: only AT WAR = hostile. Neutral/peaceful
				# factions are not enemies (was: rel != "allied", which
				# flagged every non-allied faction as hostile).
				if game.diplomacy != null \
						and game.diplomacy.has_method("combat_enabled"):
					is_enemy = bool(game.diplomacy.combat_enabled(
						game.player_faction, ufaction))
			# Jeremy 2026-10-05: non-allied foreign units hide their needs/
			# traits/memories (at-war units already take the enemy path).
			var is_foreign := false
			if game.player_faction != "" and ufaction != "" \
					and ufaction != game.player_faction:
				if game.diplomacy != null \
						and game.diplomacy.has_method("relation_state"):
					is_foreign = String(game.diplomacy.relation_state(
						game.player_faction, ufaction)) != "allied"
				else:
					is_foreign = true
			_unit_info.show_unit(u, town_name, game.game_time, is_enemy, is_foreign)
		else:
			# Same unit: cheap live bar refresh ~4 Hz, no rebuild.
			_unit_panel_live_accum += delta
			if _unit_panel_live_accum >= 0.25:
				_unit_panel_live_accum = 0.0
				_unit_info.refresh_live(u)
	elif n is BuildingNode:
		_unit_panel_dismissed_id = -1
		_unit_panel_shown_id = -1
		if _unit_info != null and is_instance_valid(_unit_info):
			_unit_info.visible = false
		# Jeremy 2026-10-05 perf: static branch — 5 Hz rebuild max.
		if not _sel_static_gate(delta, n):
			return
		var bn: BuildingNode = n as BuildingNode
		var b: Dictionary = _building_by_id(bn.building_id)
		var extra := ""
		if not b.is_empty():
			if not b.get("complete", true):
				extra = "  Building… %d%%" % int(float(b.get("progress", 0.0)) * 100.0)
			else:
				extra = "  HP %d/%d" % [int(b.get("hp", 0)), int(b.get("max_hp", 0))]
				var svc: String = String(SimBuildings.SERVICE_BUILDINGS.get(bn.btype, ""))
				if svc != "":
					var want: int = SimBuildings.service_want(svc)
					var have: int = game.population.count_job(bn.faction, svc)
					extra += "  Staff %d/%d" % [have, want]
		# Jeremy 2026-10-04: nuclear warfare — silo arm state + ARM/DISARM
		# button on the player's own completed silo (HTML btn-arm-nuke).
		if bn.btype == "nuke_silo" and game.get("nuclear") != null \
				and not b.is_empty() and bool(b.get("complete", false)):
			var nukes: RefCounted = game.get("nuclear")
			var st: Dictionary = nukes.arm_state(bn.building_id)
			var cd: float = float(st.get("cd", 0.0))
			if bool(st.get("armed", false)):
				extra += "  [ARMED — tap the map to strike]"
			elif cd > 0.0:
				extra += "  [Reloading %ds]" % int(ceil(cd))
			if bn.faction == game.player_faction:
				_nuke_arm_bid = bn.building_id
				if nukes.target_silo == bn.building_id:
					_nuke_arm_btn.text = "STAND DOWN"
				elif bool(st.get("armed", false)):
					_nuke_arm_btn.text = "DISARM NUKE"
				elif cd > 0.0:
					_nuke_arm_btn.text = "RELOADING…"
				else:
					_nuke_arm_btn.text = "ARM NUKE"
				_nuke_arm_btn.visible = true
		var info_txt: String = "%s (%s)%s" % [
			SimBuildings.building_name(bn.btype), bn.faction.capitalize(), extra]
		if _info_label.text != info_txt:
			_info_label.text = info_txt
			_recap_info_panel()
	elif n is MonasteryNode:
		# Jeremy 2026-10-04: Seven Monasteries — god lore, perk, owner,
		# capture progress, and goodness, all in the info panel.
		_unit_panel_dismissed_id = -1
		_unit_panel_shown_id = -1
		if _unit_info != null and is_instance_valid(_unit_info):
			_unit_info.visible = false
		# Jeremy 2026-10-05 perf: static branch — 5 Hz rebuild max.
		if not _sel_static_gate(delta, n):
			return
		var mon_txt: String = _monastery_info_text(n as MonasteryNode)
		if _info_label.text != mon_txt:
			_info_label.text = mon_txt
			_recap_info_panel()
	elif n is CrystalNode:
		# Jeremy 2026-10-04: Seven Dark Crystals — rogue god lore, power,
		# corruption, owner, capture progress, and synergies.
		_unit_panel_dismissed_id = -1
		_unit_panel_shown_id = -1
		if _unit_info != null and is_instance_valid(_unit_info):
			_unit_info.visible = false
		# Jeremy 2026-10-05 perf: static branch — 5 Hz rebuild max.
		if not _sel_static_gate(delta, n):
			return
		var cry_txt: String = _crystal_info_text(n as CrystalNode)
		if _info_label.text != cry_txt:
			_info_label.text = cry_txt
			_recap_info_panel()
	else:
		_info_panel.visible = false
		_unit_panel_dismissed_id = -1
		_unit_panel_shown_id = -1
		_sel_static_target = -1
		if _unit_info != null and is_instance_valid(_unit_info):
			_unit_info.visible = false


## Jeremy 2026-10-05 perf: delegate to the GameState O(1) building index
## (was a local linear scan over all buildings).
func _building_by_id(bid: int) -> Dictionary:
	return game.get_building(bid)


## Jeremy 2026-10-04: nuclear warfare — ARM/DISARM toggle for the player's
## own nuke silo (HTML btn-arm-nuke parity). Arming enters map-target mode.
func _on_nuke_arm_pressed() -> void:
	if _nuke_arm_bid < 0 or game.get("nuclear") == null:
		return
	var res: Dictionary = (game.get("nuclear") as RefCounted).toggle_arm(
		_nuke_arm_bid)
	flash_hint(String(res.get("message", "")))


## Jeremy 2026-10-04: Seven Monasteries — rich info text for the selection
## panel: god, lore, perk, owner, capture status, goodness.
func _monastery_info_text(mn: MonasteryNode) -> String:
	var mons = game.get("monasteries")
	if mons == null:
		return "Monastery"
	var m: Dictionary = mons.get_monastery(mn.monastery_id)
	if m.is_empty():
		return "Monastery"
	var g: Dictionary = mons.god_by_id(String(m.get("god_id", "")))
	var lines: Array[String] = []
	lines.append(String(m.get("name", "Monastery")))
	lines.append("%s %s - %s" % [String(g.get("name", "")),
		String(g.get("title", "")), String(g.get("domain", ""))])
	lines.append(String(g.get("lore", "")))
	lines.append("")
	lines.append("Blessing: %s" % String(g.get("perk_name", "")))
	lines.append(String(g.get("perk_desc", "")))
	lines.append("")
	var owner: String = String(m.get("owner", ""))
	if owner == "":
		lines.append("Unclaimed - hold a unit here for 60s to claim it.")
	else:
		lines.append("Held by the %s (%s)." % [owner.capitalize(),
			mons.goodness_label(owner)])
	if bool(m.get("contested", false)):
		lines.append("CONTESTED - %s is taking the hold!" % String(
			m.get("contested_by", "")).capitalize())
	else:
		var prog: Dictionary = m.get("progress", {})
		var best := 0.0
		var best_f := ""
		for f: String in prog.keys():
			if float(prog[f]) > best:
				best = float(prog[f])
				best_f = f
		if best > 0.0 and owner == "":
			lines.append("%s claiming: %d%%" % [best_f.capitalize(),
				int(best / 60.0 * 100.0)])
	lines.append("Indestructible. Cannot be taken in peacetime.")
	return "\n".join(lines)


## Jeremy 2026-10-04: Seven Dark Crystals — rich info text for the
## selection panel: rogue god, lore, dark power, corruption, owner,
## capture status, and the nullification/combo hints.
func _crystal_info_text(cn: CrystalNode) -> String:
	var crys = game.get("crystals")
	if crys == null:
		return "Dark Crystal"
	var c: Dictionary = crys.get_crystal(cn.crystal_id)
	if c.is_empty():
		return "Dark Crystal"
	var g: Dictionary = crys.god_by_id(String(c.get("god_id", "")))
	var lines: Array[String] = []
	lines.append(String(c.get("name", "Dark Crystal")))
	lines.append("%s %s - %s" % [String(g.get("name", "")),
		String(g.get("title", "")), String(g.get("domain", ""))])
	lines.append(String(g.get("lore", "")))
	lines.append("")
	lines.append("Dark power: %s" % String(g.get("power_name", "")))
	lines.append(String(g.get("power_desc", "")))
	lines.append("")
	lines.append("Corruption: %s" % String(g.get("corruption", "")))
	lines.append(String(g.get("corruption_desc", "")))
	var nullifies: String = String(SimDarkCrystals.NULLIFIES.get(
		String(g.get("id", "")), ""))
	if nullifies != "":
		var ng: Dictionary = crys.god_by_id(nullifies)
		lines.append("Nullifies: %s's corruption." % String(ng.get("name", "")))
	lines.append("")
	var owner: String = String(c.get("owner", ""))
	if owner == "":
		lines.append("Unclaimed - hold a unit here for 60s to claim it.")
	else:
		lines.append("Held by the %s (%s corruption)." % [owner.capitalize(),
			crys.corruption_label(owner)])
	for cb: Dictionary in SimDarkCrystals.COMBOS:
		var pair: Array = cb.get("pair", [])
		if pair.has(String(g.get("id", ""))):
			lines.append("Combo: %s - %s" % [String(cb.get("name", "")),
				String(cb.get("desc", ""))])
	if bool(c.get("contested", false)):
		lines.append("CONTESTED - %s is taking the hold!" % String(
			c.get("contested_by", "")).capitalize())
	else:
		var prog: Dictionary = c.get("progress", {})
		var best := 0.0
		var best_f := ""
		for f: String in prog.keys():
			if float(prog[f]) > best:
				best = float(prog[f])
				best_f = f
		if best > 0.0 and owner == "":
			lines.append("%s claiming: %d%%" % [best_f.capitalize(),
				int(best / 60.0 * 100.0)])
	lines.append("Indestructible. Cannot be taken in peacetime.")
	return "\n".join(lines)


# ================================================================
# Sandbox observe mode — director HUD (HTML #sandbox-hud parity)
# ================================================================

## Called by the world when it boots with no player faction. Hides the
## standard RTS chrome (top bar + side tabs + build panel — HTML
## showSandboxHud hides #ui-panel/#side-panel) and shows the director
## HUD: phase/clock/weather chips, faction focus buttons with census,
## director actions, and a log. Read-only observing + director meddling.
func enter_sandbox_mode(sb: SimSandbox) -> void:
	if _sandbox != null:
		return
	_sandbox = sb
	if _side_tab_bar != null:
		_side_tab_bar.visible = false
	if _side_tab_rail != null:
		_side_tab_rail.visible = false
	if _build_panel != null:
		_build_panel.visible = false
	if _capitol_btn != null:
		_capitol_btn.visible = false
	_build_sandbox_hud()
	sb_log("Sandbox live — all factions are AI.")
	_refresh_sandbox(true)


func _sb_faction_name(f: String) -> String:
	return String(Config.FACTIONS.get(f, {}).get("name", f.capitalize()))


## Jeremy 2026-10-10 (menu-scroll audit): wide button rows (the sandbox
## director rows hold 700–1200px; the build-menu tab row holds 5×100px
## tabs) clip off-screen on portrait phones with no way to reach them.
## A row wrapped by this helper lives in a horizontal-only
## ScrollContainer: taps still fire the buttons, horizontal drags scroll
## the row. EXPAND_FILL children inside the row (e.g. the sandbox title
## row's spacer) still pin trailing buttons right on wide screens; on
## narrow screens the spacer collapses and the row scrolls instead.
func _hscroll_row(row: HBoxContainer) -> ScrollContainer:
	var parent := row.get_parent()
	var idx := row.get_index()
	parent.remove_child(row)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(row)
	parent.add_child(sc)
	parent.move_child(sc, idx)
	return sc


func _build_sandbox_hud() -> void:
	_sb_panel = PanelContainer.new()
	_sb_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# The pause button must stay clickable while the tree is paused.
	_sb_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_sb_panel)
	var sb_style := StyleBoxFlat.new()
	sb_style.bg_color = Color(0.078, 0.063, 0.039, 1.0)
	sb_style.set_border_width_all(_si(2))
	sb_style.border_color = Color(0.788, 0.635, 0.153)
	sb_style.set_corner_radius_all(_si(10))
	_sb_panel.add_theme_stylebox_override("panel", sb_style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_sb_panel.add_child(margin)
	# Jeremy 2026-10-10 (menu scroll audit, remnants): the 7 stacked rows +
	# the log can run off the bottom of small landscape phones. Wrap the
	# stack in a vertical-only ScrollContainer capped by _cap_sb_panel() so
	# the whole director panel scrolls instead of clipping; short content
	# keeps the old shrink-to-fit height. Drags from anywhere on the panel
	# scroll it; taps still fire the buttons (ScrollContainer tap-vs-drag).
	_sb_vscroll = ScrollContainer.new()
	_sb_vscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sb_vscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_sb_vscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(_sb_vscroll)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sb_vscroll.add_child(vbox)
	_sb_vbox = vbox

	# --- Row 1: DIRECTOR + chips + pause + menu (HTML #sb-top parity) ------
	var top_h := HBoxContainer.new()
	top_h.add_theme_constant_override("separation", 10)
	vbox.add_child(top_h)
	_hscroll_row(top_h)
	var title := Label.new()
	title.text = "DIRECTOR"
	title.add_theme_font_size_override("font_size", _si(30))
	title.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	top_h.add_child(title)
	_sb_phase_label = _sb_chip(top_h)
	_sb_clock_label = _sb_chip(top_h)
	_sb_weather_label = _sb_chip(top_h)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_h.add_child(spacer)
	var pause_b := Button.new()
	pause_b.text = "II"
	pause_b.tooltip_text = "Pause"
	pause_b.custom_minimum_size = Vector2(_s(88), _s(88))
	pause_b.add_theme_font_size_override("font_size", _si(30))
	pause_b.pressed.connect(_on_sb_pause)
	top_h.add_child(pause_b)
	var menu_b := Button.new()
	menu_b.text = "MENU"
	menu_b.tooltip_text = "Menu"
	menu_b.custom_minimum_size = Vector2(_s(88), _s(88))
	menu_b.add_theme_font_size_override("font_size", _si(30))
	menu_b.pressed.connect(func() -> void: _on_side_tab("drawer"))
	top_h.add_child(menu_b)

	# --- Row 2: faction focus buttons with census (HTML #sb-factions) -----
	_sb_faction_row = HBoxContainer.new()
	_sb_faction_row.add_theme_constant_override("separation", 8)
	vbox.add_child(_sb_faction_row)
	_hscroll_row(_sb_faction_row)

	# --- Row 3: director actions (HTML handleSandboxAction parity) --------
	var act_h := HBoxContainer.new()
	act_h.add_theme_constant_override("separation", 8)
	vbox.add_child(act_h)
	_hscroll_row(act_h)
	for ad in [
		["Focus", _on_sb_focus], ["Boost", _on_sb_boost],
		["Troops", _on_sb_troops], ["Ally", _on_sb_ally],
		["War all", _on_sb_war_all], ["War vs", _on_sb_war_vs],
		["Peace", _on_sb_peace],
	]:
		var b := Button.new()
		b.text = String(ad[0])
		b.custom_minimum_size = Vector2(_s(140), _s(72))
		b.add_theme_font_size_override("font_size", _si(24))
		b.pressed.connect(ad[1] as Callable)
		act_h.add_child(b)

	# --- Row 4: weather + time director (HTML w_*/day/night/skip_day) ----
	var w_h := HBoxContainer.new()
	w_h.add_theme_constant_override("separation", 8)
	vbox.add_child(w_h)
	_hscroll_row(w_h)
	var w_title := Label.new()
	w_title.text = "WX"
	w_title.add_theme_font_size_override("font_size", _si(24))
	w_h.add_child(w_title)
	for wd in [
		["Clear", "clear"], ["Cloudy", "cloudy"], ["Rain", "rain"],
		["Storm", "storm"], ["Snow", "snow"],
	]:
		var wb := Button.new()
		wb.text = String(wd[0])
		wb.tooltip_text = "Set weather: " + String(wd[0])
		wb.custom_minimum_size = Vector2(_s(110), _s(64))
		wb.add_theme_font_size_override("font_size", _si(22))
		wb.pressed.connect(_on_sb_weather.bind(String(wd[1])))
		w_h.add_child(wb)
	for td in [
		["Day", 10.0], ["Night", 22.0],
	]:
		var tb := Button.new()
		tb.text = String(td[0])
		tb.custom_minimum_size = Vector2(_s(110), _s(64))
		tb.add_theme_font_size_override("font_size", _si(22))
		tb.pressed.connect(_on_sb_time_of_day.bind(float(td[1])))
		w_h.add_child(tb)
	var skip_b := Button.new()
	skip_b.text = "+1 Day"
	skip_b.tooltip_text = "Advance the calendar one day (lands at 08:00)"
	skip_b.custom_minimum_size = Vector2(_s(130), _s(64))
	skip_b.add_theme_font_size_override("font_size", _si(22))
	skip_b.pressed.connect(_on_sb_skip_day)
	w_h.add_child(skip_b)

	# --- Row 5: disaster director (HTML d_* buttons) ---------------------
	var d_h := HBoxContainer.new()
	d_h.add_theme_constant_override("separation", 8)
	vbox.add_child(d_h)
	_hscroll_row(d_h)
	var d_title := Label.new()
	d_title.text = "DOOM"
	d_title.add_theme_font_size_override("font_size", _si(24))
	d_h.add_child(d_title)
	for dd in [
		["Bandits", "bandits"], ["Ass", "butt"], ["Moose", "moose"],
		["Lizard", "lizard"], ["Cat", "cat"], ["Bastard", "bastard"],
		["Wizard", "wizard"], ["Fire", "fire"], ["Volcano", "volcano"],
		["Karen", "karen"],
	]:
		var db := Button.new()
		db.text = String(dd[0])
		db.tooltip_text = "Unleash disaster: " + String(dd[0])
		db.custom_minimum_size = Vector2(_s(110), _s(64))
		db.add_theme_font_size_override("font_size", _si(22))
		db.pressed.connect(_on_sb_disaster.bind(String(dd[1])))
		d_h.add_child(db)

	# --- Row 6: tools director (HTML expand / clear_fire) -----------------
	var t_h := HBoxContainer.new()
	t_h.add_theme_constant_override("separation", 8)
	vbox.add_child(t_h)
	var t_title := Label.new()
	t_title.text = "TOOLS"
	t_title.add_theme_font_size_override("font_size", _si(24))
	t_h.add_child(t_title)
	var exp_b := Button.new()
	exp_b.text = "Expand"
	exp_b.tooltip_text = "Order the focused faction to expand (resource boost)"
	exp_b.custom_minimum_size = Vector2(_s(150), _s(64))
	exp_b.add_theme_font_size_override("font_size", _si(22))
	exp_b.pressed.connect(_on_sb_expand)
	t_h.add_child(exp_b)
	var cf_b := Button.new()
	cf_b.text = "Clear fires"
	cf_b.tooltip_text = "Put out every fire and burning building"
	cf_b.custom_minimum_size = Vector2(_s(160), _s(64))
	cf_b.add_theme_font_size_override("font_size", _si(22))
	cf_b.pressed.connect(_on_sb_clear_fires)
	t_h.add_child(cf_b)

	# --- Row 7: director log (HTML #sb-log) -------------------------------
	_sb_log_label = Label.new()
	_sb_log_label.add_theme_font_size_override("font_size", _si(22))
	_sb_log_label.add_theme_color_override("font_color",
		Color(0.85, 0.78, 0.62))
	_sb_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_sb_log_label)
	# Jeremy 2026-10-10 (menu scroll audit, remnants): cap on the next
	# frames so the cap uses post-layout minimum sizes (see _recap_sb_panel).
	_recap_sb_panel()


func _sb_chip(parent: Control) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", _si(24))
	l.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	parent.add_child(l)
	return l


## Director log (HTML sbLog parity): keeps the last 6 lines visible.
func sb_log(text: String) -> void:
	_sb_log_lines.append(text)
	while _sb_log_lines.size() > 6:
		_sb_log_lines.pop_front()
	if _sb_log_label != null:
		_sb_log_label.text = "\n".join(_sb_log_lines)


## Rebuilds the faction focus buttons + updates the chips. Throttled —
## the census is cheap but the buttons get rebuilt, not edited in place.
func _refresh_sandbox(force: bool = false) -> void:
	if _sandbox == null or game == null:
		return
	_sb_refresh_accum += get_process_delta_time()
	if not force and _sb_refresh_accum < 0.5:
		return
	_sb_refresh_accum = 0.0
	# Chips (HTML updateSandboxHud parity).
	_sb_clock_label.text = _clock_text()
	_sb_weather_label.text = _weather_text()
	var wars := 0
	var factions: Array = game.active_factions
	for i in range(factions.size()):
		for j in range(i + 1, factions.size()):
			if game.diplomacy != null \
					and game.diplomacy.relation_state(
						String(factions[i]), String(factions[j])) == "war":
				wars += 1
	_sb_phase_label.text = ("%d war%s" % [wars, "" if wars == 1 else "s"]) \
		if wars > 0 else "Peace"
	# Faction focus buttons with census (HTML refreshSandboxFactionButtons).
	for c in _sb_faction_row.get_children():
		c.queue_free()
	for f: String in factions:
		var b := Button.new()
		var census: Dictionary = _sandbox.faction_census(f)
		b.text = "%s\n%d pop · %d hall" % [_sb_faction_name(f),
			int(census.get("pop", 0)), int(census.get("halls", 0))]
		b.custom_minimum_size = Vector2(_s(190), _s(88))
		b.add_theme_font_size_override("font_size", _si(24))
		var col: Color = Config.FACTIONS.get(f, {}).get("color",
			Color(0.6, 0.6, 0.6))
		var bstyle := StyleBoxFlat.new()
		bstyle.bg_color = Color(0.12, 0.10, 0.07, 1.0)
		bstyle.set_border_width_all(_si(2))
		bstyle.border_color = col if f != _sandbox.focus_race \
			else Color(1.0, 0.835, 0.310)
		bstyle.set_corner_radius_all(_si(8))
		b.add_theme_stylebox_override("normal", bstyle)
		var fid: String = f
		b.pressed.connect(_on_sb_faction_button.bind(fid))
		_sb_faction_row.add_child(b)


func _on_sb_faction_button(f: String) -> void:
	_sandbox.set_focus(f)
	sb_log("Focus: " + _sb_faction_name(f))
	sandbox_camera_focus.emit(f, 0.85)


func _on_sb_focus() -> void:
	var f: String = _sandbox.focus_race
	sb_log("Camera -> " + _sb_faction_name(f))
	sandbox_camera_focus.emit(f, 0.85)


func _on_sb_boost() -> void:
	var f: String = _sandbox.focus_race
	_sandbox.boost_race(f)  # HTML sbBoost: +5000 gold/wood, +2000 food
	sb_log("+" + _sb_faction_name(f) + " resources")


func _on_sb_troops() -> void:
	var f: String = _sandbox.focus_race
	var n: int = _sandbox.spawn_troops(f)
	sb_log("%d troops for %s" % [n, _sb_faction_name(f)])


func _on_sb_ally() -> void:
	_sandbox.ally_all()
	sb_log("All factions allied")


func _on_sb_war_all() -> void:
	_sandbox.war_all()
	sb_log("All factions at war")


func _on_sb_war_vs() -> void:
	var f: String = _sandbox.focus_race
	var t: String = _sandbox.war_target(f)
	if t != "":
		sb_log("%s war vs %s" % [_sb_faction_name(f), _sb_faction_name(t)])
	else:
		sb_log("No enemy to pit against " + _sb_faction_name(f))


func _on_sb_peace() -> void:
	_sandbox.force_peace_all()
	sb_log("Forced global peace")


func _on_sb_weather(kind: String) -> void:
	if _sandbox.set_weather(kind):
		sb_log("Weather -> " + kind)
	else:
		sb_log("Weather change failed")


func _on_sb_time_of_day(hour: float) -> void:
	_sandbox.set_time_of_day(hour)
	sb_log("Time -> %02d:00" % int(hour))


func _on_sb_skip_day() -> void:
	_sandbox.skip_day()
	sb_log("Skipped a day (08:00)")


func _on_sb_disaster(kind: String) -> void:
	var spawned: String = _sandbox.spawn_disaster(kind)
	if spawned != "":
		sb_log("Disaster: " + spawned)
	else:
		sb_log("Disaster fizzled (" + kind + ")")


func _on_sb_expand() -> void:
	var f: String = _sandbox.focus_race
	_sandbox.force_expand(f)
	sb_log(_sb_faction_name(f) + " ordered to expand")


func _on_sb_clear_fires() -> void:
	var n: int = _sandbox.clear_fires()
	sb_log("%d fire%s cleared" % [n, "" if n == 1 else "s"])


func _on_sb_pause() -> void:
	get_tree().paused = not get_tree().paused
	set_paused(get_tree().paused)
	sb_log("Paused" if get_tree().paused else "Resumed")
