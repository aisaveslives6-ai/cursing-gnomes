class_name UnitInfoPanel
extends PanelContainer

## Emitted when the user taps the X close button (explicit dismissal).
## hud.gd uses this to stop re-showing the panel every frame while the
## same unit stays selected.
signal dismissed

## Jeremy 2026-10-06 (polish round 2): the player tapped "Message" on the
## world-map popup — hud.gd opens the phone to a Messenger thread with
## this NPC (any NPC, even enemies).
signal message_unit(unit_id: int)

## Cursing Gnomes — tap-selected unit info panel (HTML showUnitPopup parity).##
## Floating draggable panel: header bar with name + X close button,
## content sized to fit (max 68vh scroll). Gold (#c9a227) border on dark,
## section dividers, bordered stat bars.
##
## Shows: name, faction/job/gender, city, faction, gender, current activity,
## stat bars (HP + urges), traits, honest memory lines, housing status,
## weapon, role, combat stats. Read-only, offline, fully scripted.
## No emoji — plain text labels only (tofu-box font rule: emoji render as
## hex boxes on Jeremy's iPhone in Godot).

const GOLD := Color(0.788, 0.635, 0.153)  # #c9a227
const GOLD_BRIGHT := Color(1.0, 0.835, 0.310)  # #ffd54f
const PANEL_BG := Color(0.078, 0.063, 0.039, 0.97)
const HEADER_BG := Color(0.16, 0.12, 0.06, 1.0)
const TEXT_DIM := Color(0.796, 0.725, 0.541)
const TEXT_BODY := Color(0.910, 0.863, 0.784)

const URGE_BARS := [
	["hunger", "Hunger", Color(1.0, 0.718, 0.302)],
	["energy", "Energy", Color(0.392, 0.710, 0.965)],
	["hygiene", "Hygiene", Color(0.302, 0.816, 0.882)],
	["social", "Social", Color(0.808, 0.576, 0.847)],
	["mood", "Mood", Color(0.957, 0.561, 0.694)],
	["bladder", "Bladder", Color(0.596, 0.761, 0.396)],
]

const ROLE_NAMES := {
	"guild_master": "Guild Master",
	"mayor": "Mayor",
	"adviser": "Adviser",
	"commander": "Military Commander",
	"watch_captain": "Watch Captain",
	"chieftain": "Faction Leader",
}

var _ui_scale := 1.0
var _vbox: VBoxContainer
var _scroll: ScrollContainer
var _header: PanelContainer
var _name_label: Label
var _xbtn: Button
var _dragging := false
var _drag_offset := Vector2.ZERO

# Live-refresh bookkeeping (Jeremy 2026-10-03: bars must update in real
# time without rebuilding the whole panel every frame).
var _shown_unit_id: int = -1
var _is_enemy := false  # Jeremy 2026-10-04: hostile units get a limited dossier
var _is_foreign := false  # Jeremy 2026-10-05: non-allied units hide needs
var _bar_rows: Array = []  # {key: String, fill: ColorRect, pct: Label}
var _bar_tweens: Dictionary = {}  # fill instance id -> Tween (live bar anim)
var _hp_fill: ColorRect = null
var _hp_pct: Label = null
var _hp_color_full := Color(0.4, 0.733, 0.416)
var _hp_color_low := Color(0.937, 0.325, 0.314)
var _activity_label: Label = null
var _built := false

## Faction id -> singular race label for the enemy dossier header.
## (Mirrors the singular map in scripts/world/art.gd.)
const ENEMY_RACE_SINGULAR := {
	"humans": "Human", "ogres": "Ogre", "elves": "Elf",
	"gnomes": "Gnome", "undead": "Undead",
	"human": "Human", "ogre": "Ogre", "elf": "Elf", "gnome": "Gnome",
}


func _ready() -> void:
	_ui_scale = _compute_scale()
	_build()
	visible = false


## HUD passes its scale so the panel matches (Jeremy: everything too small).
func set_ui_scale(s: float) -> void:
	_ui_scale = maxf(0.5, s)
	if is_node_ready():
		_apply_style()
		_apply_width()


func _si(v: float) -> int:
	return maxi(1, int(round(v * _ui_scale)))


## Fixed 2.5x for iPhone 17 (Jeremy 2026-10-04: no viewport math, no JS).
func _compute_scale() -> float:
	return 2.5


func _build() -> void:
	# Idempotent: headless tests may drive _build() before _ready fires.
	if _built:
		return
	_built = true
	_apply_style()
	# Outer margin holds content off the border.
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", _si(22))
	margin.add_theme_constant_override("margin_right", _si(22))
	margin.add_theme_constant_override("margin_top", _si(12))
	margin.add_theme_constant_override("margin_bottom", _si(12))
	add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", _si(8))
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(outer)
	# --- Draggable header: name + X button ---
	_header = PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = HEADER_BG
	hsb.set_corner_radius_all(_si(8))
	hsb.content_margin_left = _si(10)
	hsb.content_margin_right = _si(6)
	hsb.content_margin_top = _si(6)
	hsb.content_margin_bottom = _si(6)
	hsb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.45)
	hsb.set_border_width_all(_si(1))
	_header.add_theme_stylebox_override("panel", hsb)
	outer.add_child(_header)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", _si(8))
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	_header.add_child(hbox)
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", _si(32))
	_name_label.add_theme_color_override("font_color", GOLD_BRIGHT)
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("shadow_offset_x", 2)
	_name_label.add_theme_constant_override("shadow_offset_y", 2)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label.clip_text = true
	hbox.add_child(_name_label)
	var xbtn := Button.new()
	_xbtn = xbtn
	# Jeremy 2026-10-05: world-map popup — drawn X to close. (The
	# "phone apps use Back, never X" rule applies to the PHONE UI only;
	# this is a world-map popup, so X is correct here.)
	xbtn.text = ""
	xbtn.custom_minimum_size = Vector2(_si(72), _si(72))
	var xmark := DrawnX.new(Color(1.0, 0.55, 0.5), _si(9.0))
	xmark.position = Vector2(_si(16), _si(16))
	xmark.size = Vector2(_si(40), _si(40))
	xbtn.add_child(xmark)
	var xsb := StyleBoxFlat.new()
	xsb.bg_color = Color(0.25, 0.08, 0.06, 0.9)
	xsb.set_corner_radius_all(_si(8))
	xsb.set_border_width_all(_si(1))
	xsb.border_color = Color(0.7, 0.25, 0.2)
	xbtn.add_theme_stylebox_override("normal", xsb)
	var xhover := xsb.duplicate() as StyleBoxFlat
	xhover.bg_color = Color(0.4, 0.12, 0.1, 0.95)
	xbtn.add_theme_stylebox_override("hover", xhover)
	xbtn.add_theme_stylebox_override("pressed", xhover)
	xbtn.pressed.connect(_on_x_pressed)
	hbox.add_child(xbtn)
	# Header drag: press-drag on the header (not the X) moves the panel.
	_header.gui_input.connect(_on_header_input)
	# --- Scrollable content, sized to fit ---
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(_scroll)
	_vbox = VBoxContainer.new()
	_vbox.add_theme_constant_override("separation", _si(6))
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_vbox)
	# Park at the HTML position (left:8px; top:48px) from the first frame,
	# so the panel is placed even before show_unit() fills it.
	_apply_width()


func _apply_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	# Gold border on the dark panel (HTML #c9a227 parity).
	sb.set_border_width_all(_si(3))
	sb.border_color = GOLD
	sb.set_corner_radius_all(_si(12))
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = _si(24)
	sb.shadow_offset = Vector2(0, _si(4))
	add_theme_stylebox_override("panel", sb)


## Width: min(82vw, 340px scaled). Height sizes to content (no forced 68vh).
func _apply_width() -> void:
	var view := get_viewport()
	var vp := Vector2(1152, 648)  # headless fallback; replaced below in tree
	if view != null:
		vp = view.get_visible_rect().size
	var w: float = minf(vp.x * 0.92, 460.0 * _ui_scale)
	custom_minimum_size.x = w
	# Start top-left like the HTML (left:8px; top:48px) until dragged.
	if not _dragging and position == Vector2.ZERO:
		position = Vector2(8.0 * _ui_scale, 48.0 * _ui_scale)


func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			# Jeremy 2026-10-03: a tap on the X must reach the button, not
			# start a panel drag (on touch, any drag jitter moves the panel
			# so the release misses the button and the tap is lost).
			if mb.pressed and _press_on_x(mb.position):
				return
			_dragging = mb.pressed
			if _dragging:
				_drag_offset = get_global_mouse_position() - global_position
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and _press_on_x(st.position):
			return
		_dragging = st.pressed
		if _dragging:
			_drag_offset = st.position - global_position
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_viewport()
		accept_event()
	elif event is InputEventScreenDrag and _dragging:
		var sd := event as InputEventScreenDrag
		global_position = sd.position - _drag_offset
		_clamp_to_viewport()
		accept_event()


func _clamp_to_viewport() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	global_position.x = clampf(global_position.x, 0.0, maxf(0.0, vp.x - size.x * 0.25))
	global_position.y = clampf(global_position.y, 0.0, maxf(0.0, vp.y - _si(60)))


## Fill the panel from a live unit record. town_name: the unit's town (or "").
## is_enemy: hostile units get a limited dossier (type/race, faction, HP
## only) — no name, urges, traits, memories, housing, weapon, or combat
## stats (Jeremy 2026-10-04: no stat leaks on enemy clicks).
## is_foreign: non-allied foreign units (neutral/peaceful, not at war) get a
## limited identity view — name, faction, job, city — but NO stat bars,
## traits, memories, housing, weapon, role, or combat details (Jeremy
## 2026-10-05: no peeking at another faction's needs).
## Jeremy 2026-10-06 (polish round 2): pfp + Message row at the top of
## the world popup — the NPC's phone picture (same portrait the phone
## shows) and a button that opens a Messenger chat with them.
func _add_contact_row(u: Dictionary) -> void:
	var uid := int(u.get("id", -1))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _si(16))
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	# Circular pfp.
	var ring := PanelContainer.new()
	var rsb := StyleBoxFlat.new()
	rsb.bg_color = Color(0.16, 0.14, 0.10)
	rsb.set_corner_radius_all(999)
	rsb.set_border_width_all(maxi(2, _si(2)))
	rsb.border_color = Color(GOLD.r, GOLD.g, GOLD.b, 0.6)
	ring.add_theme_stylebox_override("panel", rsb)
	ring.custom_minimum_size = Vector2(_si(104), _si(104))
	ring.clip_contents = true
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tr := TextureRect.new()
	var tex: Texture2D = Art.unit_texture(
		String(u.get("faction", "humans")),
		String(u.get("job", "worker")),
		uid,
		String(u.get("gender", "m")))
	if tex != null:
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.add_child(tr)
	row.add_child(ring)
	# Message button.
	var msg := Button.new()
	msg.text = "Message"
	msg.custom_minimum_size = Vector2(_si(220), _si(88))
	msg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	msg.add_theme_font_size_override("font_size", _si(26))
	msg.add_theme_color_override("font_color", Color(1.0, 0.835, 0.310))
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.145, 0.475, 0.92, 0.9)
	msb.set_corner_radius_all(_si(12))
	msb.set_border_width_all(maxi(1, _si(1)))
	msb.border_color = Color(1, 1, 1, 0.25)
	msg.add_theme_stylebox_override("normal", msb)
	var msb_p := msb.duplicate() as StyleBoxFlat
	msb_p.bg_color = Color(0.145, 0.475, 0.92, 0.9).darkened(0.2)
	msg.add_theme_stylebox_override("pressed", msb_p)
	msg.add_theme_stylebox_override("hover", msb_p)
	msg.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if uid > 0:
		msg.pressed.connect(func() -> void: message_unit.emit(uid))
	else:
		msg.disabled = true
	row.add_child(msg)
	_vbox.add_child(row)
	_vbox.add_child(_divider())


func show_unit(u: Dictionary, town_name := "", game_time := -1.0,
		is_enemy := false, is_foreign := false) -> void:
	if u.is_empty():
		hide_panel(true)
		return
	_shown_unit_id = int(u.get("id", -1))
	_is_enemy = is_enemy
	_is_foreign = is_foreign and not is_enemy
	_bar_rows.clear()
	_bar_tweens.clear()
	_hp_fill = null
	_hp_pct = null
	_activity_label = null
	for c in _vbox.get_children():
		_vbox.remove_child(c)
		c.free()
	_apply_width()
	# Jeremy 2026-10-06 (polish round 2): every world-tapped NPC shows
	# their phone picture + a Message button — the phone is how the ruler
	# reaches anyone, even enemies.
	_add_contact_row(u)
	var job: String = str(u.get("job", "worker"))
	var job_label := JobDefs.job_name(job) if job != "" else "Townsfolk"
	var faction_raw: String = str(u.get("faction", ""))
	var faction: String = faction_raw.capitalize()
	if is_enemy:
		_show_enemy(u, faction_raw, faction, job_label)
		return
	if _is_foreign:
		_show_foreign_limited(u, faction, job_label, town_name)
		return
	var mind: Dictionary = u.get("mind", {})
	var uname: String = str(u.get("name", ""))
	if uname == "":
		uname = str(mind.get("name", ""))
	if uname == "":
		uname = job_label
	_name_label.text = uname
	# Identity block.
	_vbox.add_child(_line("%s %s — %s" % [faction, job_label, _gender_label(u)],
		_si(24), TEXT_DIM))
	if town_name != "":
		_vbox.add_child(_line("City: " + town_name, _si(23), TEXT_DIM))
	_vbox.add_child(_line("Faction: " + faction, _si(22), Color(0.667, 0.667, 0.667)))
	_vbox.add_child(_line("Gender: " + _gender_label(u), _si(22), TEXT_DIM))
	_vbox.add_child(_divider())
	# Activity.
	_vbox.add_child(_section("Currently:"))
	_activity_label = _line(_current_activity(u), _si(23), TEXT_BODY)
	_vbox.add_child(_activity_label)
	_vbox.add_child(_divider())
	# Bars: HP + urges.
	_vbox.add_child(_section("Health & Urges"))
	var hp := 0.0
	var max_hp := 1.0
	if u.has("hp"):
		hp = float(u["hp"])
		max_hp = maxf(1.0, float(u.get("max_hp", 100.0)))
	var hp_pct := hp / max_hp * 100.0
	_vbox.add_child(_bar("hp", "HP", hp_pct,
		_hp_color_full if hp_pct > 50.0 else _hp_color_low))
	var urges: Dictionary = u.get("urges", {})
	for ub in URGE_BARS:
		_vbox.add_child(_bar(ub[0], ub[1], float(urges.get(ub[0], 60.0)), ub[2]))
	# Traits.
	var traits: Dictionary = mind.get("traits", {})
	var shown: Array = []
	for t in ["brave", "friendly", "diligent", "crude", "proud"]:
		var v: float = float(traits.get(t, 0.0))
		if v >= 0.7:
			shown.append("%s (%.0f%%)" % [t.capitalize(), v * 100.0])
	if not shown.is_empty():
		_vbox.add_child(_divider())
		_vbox.add_child(_section("Traits:"))
		_vbox.add_child(_line(", ".join(shown), _si(22), Color(1.0, 0.882, 0.510)))
	# Jeremy 2026-10-04: food perks — active restaurant dish buffs.
	if game_time >= 0.0 and u.has("food_perks"):
		var perks: Array = SimFoodPerks.active_perks(u, game_time)
		if not perks.is_empty():
			_vbox.add_child(_divider())
			_vbox.add_child(_section("Food Perks:"))
			for p in perks:
				var pd: Dictionary = p as Dictionary
				_vbox.add_child(_line(str(pd.get("name", "")) + " — "
					+ SimFoodPerks.format_time_left(float(pd.get("secs_left", 0.0))),
					_si(22), Color(0.55, 0.95, 0.55)))
				_vbox.add_child(_line(str(pd.get("desc", "")), _si(20), TEXT_DIM))
	# Memories.
	_vbox.add_child(_divider())
	_vbox.add_child(_section("Memories"))
	var mem_lines := _memory_lines(u)
	if mem_lines.is_empty():
		_vbox.add_child(_line("No memories yet.", _si(21), Color(0.62, 0.62, 0.62)))
	else:
		for m in mem_lines.slice(0, 4):
			_vbox.add_child(_line("- " + m, _si(21), Color(0.627, 0.565, 0.439)))
	# Housing.
	_vbox.add_child(_divider())
	_vbox.add_child(_housing_box(town_name, int(u.get("town_id", -1))))
	# Weapon + role + combat.
	var fw: String = str(u.get("firearm", "basic"))
	var wname := SimCombat.firearm_name(str(u.get("faction", "humans")), fw)
	var wlvl := int(u.get("weapon_level", 0))
	var wtext := wname
	if wlvl > 0:
		wtext += " - Lv%d" % wlvl
	_vbox.add_child(_divider())
	_vbox.add_child(_line(wtext, _si(22), GOLD_BRIGHT))
	# Jeremy 2026-10-04: tool/equipment — show the equipped tool, if any.
	var eq_tool: String = String(u.get("equipped_tool", ""))
	if eq_tool != "":
		_vbox.add_child(_line("Tool: " + SimPetitions.tool_name(eq_tool),
			_si(22), GOLD_BRIGHT))
	var role: String = str(mind.get("gov_role", ""))
	if role != "":
		var rname: String = ROLE_NAMES.get(role, role.capitalize())
		_vbox.add_child(_line("Role: " + rname, _si(22), GOLD_BRIGHT))
	if not _is_worker_job(job):
		var rmod: Dictionary = SimCombat.RACE_COMBAT.get(str(u.get("faction", "")), {})
		var dmg := 10.0 * float(rmod.get("dmg_mul", 1.0))
		_vbox.add_child(_line("DMG %d" % int(round(dmg)), _si(21), Color(0.733, 0.733, 0.733)))
	_fit_height()
	visible = true


## Limited dossier for hostile units (Jeremy 2026-10-04: no stat leaks on
## enemy clicks). Shows type/race ("Ogre Warrior"), faction, and the HP bar
## (visible in-world anyway). Name, gender, city, activity, urges, traits,
## memories, housing, weapon, role, and combat stats all stay hidden.
func _show_enemy(u: Dictionary, faction_raw: String, faction: String,
		job_label: String) -> void:
	var race: String = ENEMY_RACE_SINGULAR.get(faction_raw.to_lower(), faction)
	_name_label.text = "%s %s" % [race, job_label]
	_vbox.add_child(_line("Faction: " + faction, _si(22),
		Color(0.667, 0.667, 0.667)))
	_vbox.add_child(_divider())
	_vbox.add_child(_section("Status"))
	_vbox.add_child(_line("Hostile — details hidden", _si(23),
		Color(0.937, 0.55, 0.51)))
	_vbox.add_child(_divider())
	_vbox.add_child(_section("Health"))
	var hp := 0.0
	var max_hp := 1.0
	if u.has("hp"):
		hp = float(u["hp"])
		max_hp = maxf(1.0, float(u.get("max_hp", 100.0)))
	var hp_pct := hp / max_hp * 100.0
	_vbox.add_child(_bar("hp", "HP", hp_pct,
		_hp_color_full if hp_pct > 50.0 else _hp_color_low))
	_fit_height()
	visible = true


## Limited identity view for non-allied foreign units (Jeremy 2026-10-05:
## "I shouldn't be able to see the details of a faction I'm not allied
## with"). Shows name, faction/job/gender, city, faction, and a status
## line — but NO Health & Urges bars, no traits, no memories, no housing,
## no weapon/role/combat details. At-war units take the _show_enemy path.
func _show_foreign_limited(u: Dictionary, faction: String, job_label: String,
		town_name: String) -> void:
	var mind: Dictionary = u.get("mind", {})
	var uname: String = str(u.get("name", ""))
	if uname == "":
		uname = str(mind.get("name", ""))
	if uname == "":
		uname = job_label
	_name_label.text = uname
	_vbox.add_child(_line("%s %s — %s" % [faction, job_label, _gender_label(u)],
		_si(24), TEXT_DIM))
	if town_name != "":
		_vbox.add_child(_line("City: " + town_name, _si(23), TEXT_DIM))
	_vbox.add_child(_line("Faction: " + faction, _si(22), Color(0.667, 0.667, 0.667)))
	_vbox.add_child(_line("Gender: " + _gender_label(u), _si(22), TEXT_DIM))
	_vbox.add_child(_divider())
	_vbox.add_child(_section("Status"))
	_vbox.add_child(_line("Neutral — details hidden", _si(23),
		Color(0.796, 0.725, 0.541)))
	_fit_height()
	visible = true


## Size the scroll area to content, capped at 68vh — never stretched.
func _fit_height() -> void:
	if not is_inside_tree():
		return  # headless test env: no tree, no frame to await
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if not is_instance_valid(_vbox):
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var max_h: float = vp.y * 0.68
	var natural: float = _vbox.get_minimum_size().y
	# Let the scroll container be exactly the content height (up to cap).
	_scroll.custom_minimum_size = Vector2(_scroll.custom_minimum_size.x, minf(natural, max_h))
	# Reset panel position if never dragged (fresh open at top-left).
	if position == Vector2.ZERO:
		position = Vector2(8.0 * _ui_scale, 48.0 * _ui_scale)


func hide_panel(silent := false) -> void:
	visible = false
	_dragging = false
	if not silent:
		dismissed.emit()


## X tap: explicit user dismissal (hud stops re-showing for this unit).
func _on_x_pressed() -> void:
	hide_panel()  # non-silent: emits dismissed


## True when a header-local press position lands on the X button.
## gui_input positions are local to _header, so convert to global first.
func _press_on_x(local_pos: Vector2) -> bool:
	if _xbtn == null or not is_instance_valid(_xbtn):
		return false
	if _header == null or not is_instance_valid(_header):
		return false
	var gp: Vector2 = _header.get_global_transform() * local_pos
	return _xbtn.get_global_rect().has_point(gp)


func _section(t: String) -> Label:
	return _line(t, _si(23), GOLD_BRIGHT, true)


func _divider() -> HSeparator:
	var d := HSeparator.new()
	d.add_theme_constant_override("separation", _si(6))
	d.add_theme_stylebox_override("separator", _make_divider_style())
	return d


func _make_divider_style() -> StyleBoxLine:
	var sl := StyleBoxLine.new()
	sl.color = Color(GOLD.r, GOLD.g, GOLD.b, 0.35)
	sl.thickness = _si(1)
	return sl


## Styled housing box: green "Has a house" / red "No house" (HTML parity).
func _housing_box(town_name: String, town_id: int) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	var has_house := town_name != "" or town_id >= 0
	if has_house:
		sb.bg_color = Color(0.157, 0.235, 0.157, 0.5)
		sb.border_color = Color(0.4, 0.733, 0.416)
	else:
		sb.bg_color = Color(0.314, 0.118, 0.078, 0.55)
		sb.border_color = Color(0.937, 0.325, 0.314)
	sb.set_border_width_all(_si(2))
	sb.set_corner_radius_all(_si(8))
	sb.content_margin_left = _si(10)
	sb.content_margin_right = _si(10)
	sb.content_margin_top = _si(8)
	sb.content_margin_bottom = _si(8)
	box.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", _si(2))
	box.add_child(vb)
	if has_house:
		vb.add_child(_line("Has a house", _si(22), Color(0.647, 0.839, 0.647), true))
		var detail := "Lives in " + town_name if town_name != "" \
			else "Town #%d" % town_id
		vb.add_child(_line(detail, _si(21), Color(0.784, 0.902, 0.784)))
	else:
		vb.add_child(_line("No house", _si(22), Color(0.937, 0.604, 0.604), true))
		vb.add_child(_line("Will build a home first", _si(21), Color(1.0, 0.8, 0.737)))
	return box


func _is_worker_job(job: String) -> bool:
	return job in ["worker", "woodcutter", "miner", "farmer", "fisher",
		"roadbuilder", "doctor", "firefighter", "guild_master"]


func _gender_label(u: Dictionary) -> String:
	var g := str(u.get("gender", "")).to_lower()
	if g == "" :
		g = "m" if int(u.get("id", 0)) % 2 == 0 else "f"
		u["gender"] = g
	return "Female" if g.begins_with("f") else "Male"


## Current activity from live state (HTML C50-CURRENTLY parity):
## mind_state "satisfying:<urge>" > critical urge > job.
func _current_activity(u: Dictionary) -> String:
	var state := str(u.get("mind_state", ""))
	if state.begins_with("satisfying:"):
		var urge := state.get_slice(":", 1)
		return "Satisfying " + urge + " (urge)"
	var mind: Dictionary = u.get("mind", {})
	var crit := str(mind.get("critical_urge", ""))
	if crit != "":
		return "Needs " + crit + " (urgent)"
	var job: String = str(u.get("job", ""))
	if job != "" and job != "worker":
		return JobDefs.job_name(job)
	return "Idle"


func _memory_lines(u: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var mems: Array = u.get("memories", [])
	var sorted := mems.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("strength", 0.0)) > float(b.get("strength", 0.0)))
	for m in sorted:
		var md: Dictionary = m
		var subj := str(md.get("subject_name", ""))
		match str(md.get("type", "")):
			"hurt_by":
				out.append("Holds a grudge against %s" % subj)
			"helped_by":
				out.append("Owes %s a favor" % subj)
			"saved_by":
				out.append("%s saved their life" % subj)
			"insulted_by":
				out.append("Insulted by %s" % subj)
			"praised_by":
				out.append("Praised by %s" % subj)
			"friend_died":
				out.append("Mourns %s" % subj)
			"worked_with":
				out.append("Worked alongside %s" % subj)
			"mocked_by":
				out.append("Mocked by %s" % subj)
	return out


func _line(t: String, size: int, color: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if bold:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func _bar(key: String, label_text: String, val: float, color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", _si(8))
	var l := _line(label_text, _si(22), TEXT_DIM)
	l.custom_minimum_size = Vector2(_si(90), 0)
	row.add_child(l)
	# Bordered bar background.
	var bg := PanelContainer.new()
	var bgsb := StyleBoxFlat.new()
	bgsb.bg_color = Color(0.10, 0.10, 0.10, 1.0)
	bgsb.set_border_width_all(_si(1))
	bgsb.border_color = Color(0.3, 0.3, 0.3)
	bgsb.set_corner_radius_all(_si(4))
	bg.add_theme_stylebox_override("panel", bgsb)
	bg.custom_minimum_size = Vector2(0, _si(18))
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(bg)
	var fill := ColorRect.new()
	fill.color = color
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	fill.anchor_right = clampf(val / 100.0, 0.0, 1.0)
	# Keep fill inside the border: inset by border width via offsets.
	fill.offset_left = _si(1)
	fill.offset_top = _si(1)
	fill.offset_right = -_si(1)
	fill.offset_bottom = -_si(1)
	bg.add_child(fill)
	var pct := _line(str(int(clampf(val, 0.0, 100.0))), _si(22), TEXT_BODY)
	pct.custom_minimum_size = Vector2(_si(44), 0)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pct)
	# Jeremy 2026-10-03: keep refs so bars refresh live without rebuild.
	if key == "hp":
		_hp_fill = fill
		_hp_pct = pct
	else:
		_bar_rows.append({"key": key, "fill": fill, "pct": pct})
	return row


## Lightweight live update of bars + activity — no rebuild. Called by HUD
## ~4 Hz while the panel is open (Jeremy 2026-10-03: bars must move live).
func refresh_live(u: Dictionary) -> void:
	if not visible:
		return
	if _shown_unit_id != -1 and int(u.get("id", -1)) != _shown_unit_id:
		return
	_animate_bar(_hp_fill, _hp_pct, _hp_value(u))
	if is_instance_valid(_hp_fill):
		_hp_fill.color = _hp_color_full if _hp_value(u) > 50.0 else _hp_color_low
	var urges: Dictionary = u.get("urges", {})
	for row in _bar_rows:
		var rd: Dictionary = row
		if is_instance_valid(rd.get("fill")):
			_animate_bar(rd["fill"], rd["pct"],
				float(urges.get(String(rd["key"]), 60.0)))
	if is_instance_valid(_activity_label):
		_activity_label.text = _current_activity(u)


func _hp_value(u: Dictionary) -> float:
	var hp := 0.0
	var max_hp := 1.0
	if u.has("hp"):
		hp = float(u["hp"])
		max_hp = maxf(1.0, float(u.get("max_hp", 100.0)))
	return hp / max_hp * 100.0


func _set_bar(fill: ColorRect, pct: Label, val: float) -> void:
	if not is_instance_valid(fill):
		return
	fill.anchor_right = clampf(val / 100.0, 0.0, 1.0)
	if is_instance_valid(pct):
		pct.text = str(int(clampf(val, 0.0, 100.0)))


## Jeremy 2026-10-05: needs bars must visibly DRAIN — tween the fill edge
## (and the number, in lockstep) toward the new sim value over ~0.4 s
## instead of snapping. The bar tracks the value continuously all the way
## down to 0; nothing clamps the visual above 0. Any in-flight tween on
## the same bar is killed so the bar always follows the latest value.
func _animate_bar(fill: ColorRect, pct: Label, val: float) -> void:
	if not is_instance_valid(fill):
		return
	if not is_inside_tree():
		_set_bar(fill, pct, val)
		return
	var target := clampf(val / 100.0, 0.0, 1.0)
	var from: float = fill.anchor_right
	if is_equal_approx(from, target):
		if is_instance_valid(pct):
			pct.text = str(int(round(target * 100.0)))
		return
	var key := fill.get_instance_id()
	var old: Tween = _bar_tweens.get(key)
	if old != null and old.is_valid():
		old.kill()
	var tw := create_tween()
	_bar_tweens[key] = tw
	tw.set_trans(Tween.TRANS_LINEAR)
	tw.tween_method(_apply_bar_step.bind(fill, pct), from, target, 0.4)


func _apply_bar_step(t: float, fill: ColorRect, pct: Label) -> void:
	if not is_instance_valid(fill):
		return
	fill.anchor_right = t
	if is_instance_valid(pct):
		pct.text = str(int(round(t * 100.0)))
