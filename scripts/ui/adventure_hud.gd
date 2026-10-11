class_name AdventureHUD
extends CanvasLayer
## Cursing Gnomes — adventure-mode UI (quest board, hero panel, gear).
##
## Companion to SimAdventure. Shows the hero's HP/XP/mana, a quest panel
## (offered / active / dungeons / gear shop / deeds), toasts for adventure
## events, and the win/lose overlay. Pure presentation — all logic lives
## in SimAdventure.


var _adv: SimAdventure
var _gs: GameState

var _hero_name: Label
var _hp_bar: ProgressBar
var _xp_bar: ProgressBar
var _vitals: Label
var _strike_btn: Button
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _panel_scroll: ScrollContainer
var _toasts: VBoxContainer
var _overlay: Label
var _hero_panel: PanelContainer
var _quest_toggle: Button

var _dirty := true
var _refresh_accum := 0.0
var _toast_timers: Array = []  # [label, seconds_left]


func setup(adv: SimAdventure, gs: GameState) -> void:
	_adv = adv
	_gs = gs
	_build()
	var bus = _gs.bus
	bus.adventure_deed.connect(_on_deed)
	bus.adventure_quest_accepted.connect(func(_q: Dictionary) -> void: _dirty = true)
	bus.adventure_quest_completed.connect(func(_q: Dictionary) -> void: _dirty = true)
	bus.adventure_quest_failed.connect(func(_q: Dictionary) -> void: _dirty = true)
	bus.adventure_level_up.connect(_on_level_up)
	bus.adventure_won.connect(_on_won)
	bus.adventure_lost.connect(_on_lost)


func _build() -> void:
	# --- hero panel (top-left) ---
	var hp := PanelContainer.new()
	hp.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hp.custom_minimum_size = Vector2(360, 0)
	_hero_panel = hp
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	hp.add_child(vb)
	_hero_name = Label.new()
	_hero_name.add_theme_font_size_override("font_size", 28)
	vb.add_child(_hero_name)
	_hp_bar = ProgressBar.new()
	_hp_bar.custom_minimum_size = Vector2(330, 24)
	_hp_bar.show_percentage = false
	vb.add_child(_hp_bar)
	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(330, 16)
	_xp_bar.show_percentage = false
	vb.add_child(_xp_bar)
	_vitals = Label.new()
	_vitals.add_theme_font_size_override("font_size", 22)
	vb.add_child(_vitals)
	_strike_btn = Button.new()
	_strike_btn.text = "Heroic Strike (30 mana)"
	_strike_btn.custom_minimum_size = Vector2(0, 88)
	_strike_btn.add_theme_font_size_override("font_size", 24)
	_strike_btn.pressed.connect(func() -> void:
		_toast(_adv.heroic_strike()))
	vb.add_child(_strike_btn)
	add_child(hp)

	# --- quest toggle (top-right) ---
	var toggle := Button.new()
	toggle.text = "Quests"
	toggle.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	toggle.custom_minimum_size = Vector2(180, 88)
	toggle.add_theme_font_size_override("font_size", 24)
	toggle.pressed.connect(func() -> void:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_dirty = true)
	add_child(toggle)
	_quest_toggle = toggle
	_refit_safe()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_refit_safe)

	# --- quest panel (right side) ---
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.visible = false
	_panel_scroll = ScrollContainer.new()
	_panel.add_child(_panel_scroll)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 6)
	_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_scroll.add_child(_panel_box)
	add_child(_panel)
	_layout_panel()

	# --- toasts (bottom-center) ---
	_toasts = VBoxContainer.new()
	_toasts.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toasts.position = Vector2(-300, -140)
	_toasts.custom_minimum_size = Vector2(600, 0)
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.add_theme_constant_override("separation", 2)
	add_child(_toasts)

	# --- win/lose overlay ---
	_overlay = Label.new()
	_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_theme_font_size_override("font_size", 56)
	_overlay.visible = false
	add_child(_overlay)


## Jeremy 2026-10-06 (launch readiness): top chrome must clear the Dynamic
## Island / rounded corners. OS-reported safe area when available, with
## conservative portrait-phone fallbacks.
func _safe_insets() -> Vector4:  # top, bottom, left, right (canvas units)
	var vp := get_viewport()
	if vp == null:
		return Vector4(64.0, 40.0, 16.0, 16.0)
	var vsz := vp.get_visible_rect().size
	if not DisplayServer.is_touchscreen_available() and vsz.x >= 1024.0:
		return Vector4.ZERO
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x > 0.0 and safe.size.y > 0.0:
		# Jeremy 2026-10-08 (graphics-hourly): the OS rect is in WINDOW units
		# (CSS px on web), but vsz is in stretch-expanded VIEWPORT units —
		# mixing them produced garbage insets. Convert the rect to viewport
		# units first via window_get_size(), which shares the safe rect's
		# coordinate space.
		var winsz := Vector2(DisplayServer.window_get_size())
		if winsz.x > 0.0 and winsz.y > 0.0:
			var k := vsz / winsz
			var top := safe.position.y * k.y
			var left := safe.position.x * k.x
			var bottom := vsz.y - (safe.position.y + safe.size.y) * k.y
			var right := vsz.x - (safe.position.x + safe.size.x) * k.x
			return Vector4(maxf(top, 0.0), maxf(bottom, 0.0), maxf(left, 0.0), maxf(right, 0.0))
	if vsz.y > vsz.x:
		return Vector4(64.0, 40.0, 16.0, 16.0)
	return Vector4(28.0, 24.0, 40.0, 40.0)


func _refit_safe() -> void:
	var ins := _safe_insets()
	var vp := get_viewport()
	var vsz := vp.get_visible_rect().size if vp != null else Vector2.ZERO
	if _hero_panel != null and is_instance_valid(_hero_panel):
		_hero_panel.position = Vector2(ins.z + 12.0, ins.x + 12.0)
	if _quest_toggle != null and is_instance_valid(_quest_toggle):
		# NOTE (Jeremy 2026-10-08): Control.position set AFTER add_child is
		# the GLOBAL position — the setter back-computes offsets from the
		# live parent rect. So pass viewport-space coordinates here, never
		# anchor-relative offsets (those only work when set BEFORE add_child,
		# when there is no parent rect yet). The old negative-x value parked
		# the toggle off-screen.
		_quest_toggle.position = Vector2(
			vsz.x - 180.0 - ins.w - 12.0, ins.x + 12.0)
	_layout_panel()


## Jeremy 2026-10-08: the quest panel used position.y = 0 with the
## CENTER_RIGHT preset (anchor sits at the vertical center), so the panel's
## top started at mid-screen and ~36% of it hung off the bottom — the lower
## sections (Outfitter, Deeds) were unreachable on iPhone. Vertically center
## it, refit on rotation, and clear the right safe-area inset.
##
## GOTCHA (2026-10-08): Control.position assigned AFTER add_child is the
## GLOBAL viewport position — the setter back-computes offsets from the live
## parent rect. Anchor-relative offsets (e.g. -pw-12, -ph/2) only work when
## assigned BEFORE add_child. The first attempt at this fix used anchor
## offsets post-add_child and parked the whole panel off-screen.
func _layout_panel() -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	var vp := get_viewport()
	if vp == null:
		return
	var vsz := vp.get_visible_rect().size
	var ins := _safe_insets()
	var pw := minf(vsz.x * 0.92, 560.0)
	var ph := minf(vsz.y * 0.86, maxf(200.0, vsz.y - ins.x - ins.y - 24.0))
	# Global-space coordinates: right side clearing the safe-area inset,
	# vertically centered.
	_panel.position = Vector2(vsz.x - pw - ins.w - 12.0, (vsz.y - ph) / 2.0)
	_panel.size = Vector2(pw, ph)
	_panel.custom_minimum_size = Vector2(pw, ph)
	if _panel_scroll != null and is_instance_valid(_panel_scroll):
		_panel_scroll.custom_minimum_size = Vector2(pw, ph)


func _process(delta: float) -> void:
	_refresh_accum += delta
	if _refresh_accum < 0.25:
		_tick_toasts(delta)
		return
	_refresh_accum = 0.0
	_tick_toasts(delta)
	if _adv == null:
		return
	_refresh_hero()
	if _dirty and _panel.visible:
		_dirty = false
		_rebuild_panel()


func _refresh_hero() -> void:
	var h := _adv.hero()
	if h.is_empty():
		return
	_hero_name.text = "%s — Lv %d %s" % [_adv.hero_name, _adv.level,
		_adv.hero_job.capitalize()]
	var hp := float(h.get("hp", 1.0))
	var mhp := float(h.get("max_hp", 1.0))
	_hp_bar.max_value = mhp
	_hp_bar.value = maxf(0.0, hp)
	_xp_bar.max_value = float(_adv.xp_need())
	_xp_bar.value = float(_adv.xp)
	_vitals.text = "HP %d/%d   XP %d/%d   Mana %d   Gold %dg" % [
		int(maxf(0.0, hp)), int(mhp), _adv.xp, _adv.xp_need(),
		int(_adv.mana), int(float(h.get("gold", 0.0)))]
	if _adv.respawn_t > 0.0:
		_vitals.text += "   (respawn %ds)" % int(ceil(_adv.respawn_t))


# ------------------------------------------------------------------ panel

func _rebuild_panel() -> void:
	for c in _panel_box.get_children():
		c.queue_free()
	_section("Offered Quests")
	for d in _adv.offered_defs():
		var title := "%s\n%s" % [String(d.get("title", "")),
			String(d.get("desc", ""))]
		var r: Dictionary = d.get("reward", {})
		title += "\nReward: %d XP, %dg" % [int(r.get("xp", 0)),
			int(float(r.get("gold", 0.0)))]
		var g := String(d.get("giver", ""))
		_quest_row(title, "From: %s" % _adv._giver_name(g),
			"Accept", func() -> void:
				_adv.accept_quest(String(d.get("id", "")))
				_dirty = true)
	_section("Active Quests (%d)" % _adv.active_quests().size())
	for q in _adv.active_quests():
		_quest_row(String(q.get("title", "")),
			_adv.quest_progress(q) + "\n" + String(q.get("desc", "")),
			"Abandon", func() -> void:
				_adv.abandon_quest(String(q.get("id", "")))
				_dirty = true)
	_section("Dungeons")
	for dg in _adv.dungeons:
		var dname := String(dg.get("name", ""))
		var status := "undiscovered"
		if bool(dg.get("cleared", false)):
			status = "cleared"
		elif bool(dg.get("discovered", false)):
			status = "discovered"
		var alive_n := (dg.get("denizen_ids", []) as Array).size()
		var sub := "%s — %d denizens" % [status, alive_n]
		var btn_text := "Guide"
		if bool(dg.get("cleared", false)) and not bool(dg.get("chest_looted", false)):
			btn_text = "Loot"
		_quest_row(dname, sub, btn_text, func() -> void:
			_on_dungeon_button(dg))
	# Supplies: consumable starting kit + loot (HTML inventory-tab parity:
	# nonzero playerInventory entries listed).
	_section("Supplies")
	var sup_lines: Array[String] = []
	for sid in (_adv.inventory as Dictionary).keys():
		var n := int((_adv.inventory as Dictionary).get(sid, 0))
		if n > 0:
			var nm := str(SimAdventure.SUPPLY_NAMES.get(sid, sid.capitalize()))
			sup_lines.append("%s: %d" % [nm, n])
	var sup_lbl := Label.new()
	# Jeremy 2026-10-11 (menu scroll audit): display-only — never swallow
	# the quest panel's ScrollContainer drag.
	sup_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sup_lbl.text = "\n".join(sup_lines) if not sup_lines.is_empty() \
		else "Empty bag"
	sup_lbl.add_theme_font_size_override("font_size", 22)
	sup_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_box.add_child(sup_lbl)
	_section("Gear")
	var gear_line := "Weapon: %s\nArmor: %s\nTrinket: %s" % [
		_gear_name(String((_adv.gear as Dictionary).get("weapon", ""))),
		_gear_name(String((_adv.gear as Dictionary).get("armor", ""))),
		_gear_name(String((_adv.gear as Dictionary).get("trinket", "")))]
	var gl := Label.new()
	gl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gl.text = gear_line
	gl.add_theme_font_size_override("font_size", 22)
	gl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_box.add_child(gl)
	for gid in _adv.bag:
		var nm := _gear_name(gid)
		_quest_row(nm, String(((SimAdventure.GEAR[gid]) as Dictionary).get("desc", "")),
			"Equip", func() -> void:
				_adv.equip(gid)
				_dirty = true)
	_section("Outfitter (buy)")
	for gid in SimAdventure.GEAR.keys():
		var it: Dictionary = SimAdventure.GEAR[gid]
		var cost := float(it.get("cost", 0.0))
		if cost <= 0.0:
			continue
		var owned: bool = _adv.bag.has(gid) \
			or String((_adv.gear as Dictionary).get(String(it.get("slot", "")))) == gid
		var sub2 := "%s — %dg%s" % [String(it.get("desc", "")), int(cost),
			" (owned)" if owned else ""]
		if owned:
			var l2 := Label.new()
			l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
			l2.text = "%s\n%s" % [String(it.get("name", "")), sub2]
			l2.add_theme_font_size_override("font_size", 22)
			_panel_box.add_child(l2)
		else:
			_quest_row(String(it.get("name", "")), sub2, "Buy",
				func() -> void:
					_toast(_adv.buy_gear(gid))
					_dirty = true)
	_section("Deeds")
	var deeds: Array = _adv.deeds
	for i in range(maxi(0, deeds.size() - 8), deeds.size()):
		var dl := Label.new()
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dl.text = "• %s" % String(deeds[i])
		dl.add_theme_font_size_override("font_size", 20)
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_panel_box.add_child(dl)


func _section(text: String) -> void:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.text = text
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_panel_box.add_child(l)


func _quest_row(title: String, sub: String, btn_text: String,
		on_press: Callable) -> void:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_theme_constant_override("separation", 8)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.text = title
	t.add_theme_font_size_override("font_size", 24)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(t)
	var s := Label.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.text = sub
	s.add_theme_font_size_override("font_size", 20)
	s.add_theme_color_override("font_color", Color(0.75, 0.72, 0.62))
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(s)
	hb.add_child(vb)
	var b := Button.new()
	b.text = btn_text
	b.custom_minimum_size = Vector2(130, 72)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(on_press)
	hb.add_child(b)
	_panel_box.add_child(hb)


func _gear_name(gid: String) -> String:
	if gid == "" or not SimAdventure.GEAR.has(gid):
		return "—"
	return String((SimAdventure.GEAR[gid] as Dictionary).get("name", gid))


func _on_dungeon_button(dg: Dictionary) -> void:
	var h := _adv.hero()
	if h.is_empty():
		return
	var dpos: Vector2 = dg.get("pos", Vector2.ZERO)
	var hpos: Vector2 = h.get("position", Vector2.ZERO)
	if bool(dg.get("cleared", false)) and not bool(dg.get("chest_looted", false)) \
			and hpos.distance_to(dpos) < 220.0:
		_toast(_adv.loot_chest(String(dg.get("id", ""))))
		_dirty = true
	else:
		_adv.order_move(dpos)
		_toast("Marching to %s..." % String(dg.get("name", "")))


# ------------------------------------------------------------------ events

func _on_deed(text: String) -> void:
	_toast(text)
	_dirty = true


func _on_level_up(level: int) -> void:
	_toast("LEVEL %d! %s grows stronger." % [level, _adv.hero_name])
	_dirty = true


func _on_won() -> void:
	_overlay.text = "LEGEND OF THE WILDS\nThe Bandit King is dead. The wilds are yours."
	_overlay.visible = true


func _on_lost() -> void:
	_overlay.text = "THE WILDS CLAIM ANOTHER\n%s fell %d times. The bards will sing... quietly." \
		% [_adv.hero_name, SimAdventure.MAX_DEATHS]
	_overlay.visible = true


func _toast(text: String) -> void:
	if text == "":
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	_toasts.add_child(l)
	_toast_timers.append([l, 4.0])
	while _toasts.get_child_count() > 4:
		var old: Node = _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
		_toast_timers.pop_front()


func _tick_toasts(delta: float) -> void:
	for i in range(_toast_timers.size() - 1, -1, -1):
		var e: Array = _toast_timers[i]
		e[1] = float(e[1]) - delta
		var l: Label = e[0]
		if float(e[1]) <= 0.0:
			if is_instance_valid(l):
				l.queue_free()
			_toast_timers.remove_at(i)
		elif float(e[1]) < 1.0 and is_instance_valid(l):
			l.modulate.a = float(e[1])
