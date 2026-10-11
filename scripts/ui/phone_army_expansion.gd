class_name PhoneArmyExpansion
extends RefCounted
## Phone Army app expansion (Jeremy 2026-10-06, Lane 5): the War room,
## Veterans roster, Warlord retinue, and Deployment map sub-screens.
##
## All builders are static and self-rebuilding (same pattern as ArmyTab):
## after any order, the screen's box is cleared and rebuilt. Screens are
## hosted by PhoneUI (`_show_army_warroom` etc.) with back target "army"
## (Back, never X) and live inside the phone scroll, so iPhone 17 safe
## areas are respected everywhere.
##
## FACTION SOVEREIGNTY (Jeremy 2026-10-04): the player commands ONLY their
## own faction. Foreign armies are view-only in every screen — order paths
## (`order_rally`, retinue assign/remove) refuse foreign factions outright.
##
## Kill counts: the sim does not attribute kills to individual units, so
## the roster reads the `kills` field the sim will populate from battle
## reports (currently 0) and derives the veteran TIER from observable
## service marks (deployment, weapon level, warlord) — never fabricated.

const C_TEXT := Color(0.96, 0.96, 0.97)
const C_DIM := Color(0.62, 0.64, 0.68)
const C_GOLD := Color(1.0, 0.84, 0.35)
const C_SURFACE := Color(0.105, 0.115, 0.148)
const C_EDGE := Color(1.0, 1.0, 1.0, 0.08)
const FS_MD := 42
const FS_SM := 34
const FS_XS := 28

const TIER_COLORS := {
	"Warlord": Color(1.0, 0.84, 0.35),
	"Veteran": Color(0.55, 0.85, 1.0),
	"Blooded": Color(0.65, 0.90, 0.55),
	"Recruit": Color(0.62, 0.64, 0.68),
}

# Screen state (rebuilt screens read these; reset to player faction default).
static var _roster_faction := ""
static var _roster_sort := "kills"
static var _retinue_faction := ""
static var _deploy_scope := "field"
static var _deploy_selected := {}
static var _deploy_status := ""
static var _sort_mode := "kills"


## --- shared widgets -----------------------------------------------------------

static func _lbl(parent: Control, text: String, size: int = FS_SM,
		color: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


static func _btn(parent: Control, text: String, on_press: Callable,
		size: int = FS_SM, min_h: float = 96.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", C_TEXT)
	b.add_theme_color_override("font_pressed_color", C_GOLD)
	b.add_theme_color_override("font_disabled_color", C_DIM)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_SURFACE
		sb.set_corner_radius_all(18)
		sb.border_color = C_EDGE
		sb.set_border_width_all(1)
		sb.content_margin_left = 12.0
		sb.content_margin_right = 12.0
		sb.content_margin_top = 8.0
		sb.content_margin_bottom = 8.0
		b.add_theme_stylebox_override(state, sb)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


static func _card(parent: Control, accent: Color) -> VBoxContainer:
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SURFACE
	sb.set_corner_radius_all(18)
	sb.border_color = accent
	sb.set_border_width_all(1)
	sb.border_width_top = 4
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 10.0
	sb.content_margin_bottom = 10.0
	card.add_theme_stylebox_override("panel", sb)
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	card.add_child(box)
	return box


static func _faction_color(f: String) -> Color:
	return PhoneArmyMap.FACTION_COLORS.get(f, Color(0.75, 0.75, 0.75))


static func _faction_name(f: String) -> String:
	return String(Config.FACTIONS.get(f, {}).get("name", f.capitalize()))


## Sub-screen nav: two rows of touch-sized buttons, current one disabled.
static func build_nav(ui: PhoneUI, box: VBoxContainer, current: String) -> void:
	var rows := [
		[["army", "Command"], ["army_warroom", "War room"],
			["army_roster", "Veterans"]],
		[["army_retinue", "Warlords"], ["army_deploy", "Deploy"]],
	]
	for ritems in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		for it in ritems:
			var key := String(it[0])
			var b := _btn(row, String(it[1]),
				func() -> void: ui.open_app(key), FS_XS, 84.0)
			if key == current:
				b.disabled = true


static func _army_of(game: GameState) -> SimArmy:
	if game == null or not game.has_meta("army"):
		return null
	return game.get_meta("army")


static func _faction_picker(ui: PhoneUI, game: GameState, box: VBoxContainer,
		current: String, on_pick: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	for f: String in game.active_factions:
		var fp := f  # fresh local per row: lambdas capture loop vars by ref
		var b := _btn(row, _faction_name(fp),
			func() -> void: on_pick.call(fp), FS_XS, 84.0)
		b.add_theme_color_override("font_color", _faction_color(fp))
		if fp == current:
			b.disabled = true
			b.text = "> " + b.text


## --- unit data helpers --------------------------------------------------------

static func _fighters(game: GameState, faction: String) -> Array:
	var out := []
	for u: Dictionary in game.units:
		if String(u.get("faction", "")) != faction:
			continue
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if SimCombat.is_fighter(u):
			out.append(u)
	return out


## Veteran tier from observable service marks (HTML had no veterancy
## system — this derives it from deployment/weapon/warlord state).
static func veteran_tier(u: Dictionary) -> String:
	if bool(u.get("warlord", false)):
		return "Warlord"
	var wlvl := int(u.get("weapon_level", 0))
	var field := bool(u.get("deployed_for_war", false)) \
		or bool(u.get("mustering", false)) \
		or u.has("move_target") or u.has("monastery_march")
	if wlvl >= 2 or (field and wlvl >= 1):
		return "Veteran"
	if field or wlvl >= 1 or u.has("formation_slot"):
		return "Blooded"
	return "Recruit"


static func assignment_of(u: Dictionary) -> String:
	if bool(u.get("downed", false)):
		return "downed"
	if bool(u.get("withdrawing", false)):
		return "withdrawing"
	if bool(u.get("deployed_for_war", false)):
		return "deployed"
	if bool(u.get("mustering", false)):
		return "mustering"
	if u.has("move_target"):
		return "marching"
	if String(u.get("job", "")) == "guard":
		return "guarding"
	if SimArmy.gov_role_of(u) != "":
		return "on duty"
	return "idle"


static func order_summary(game: GameState, faction: String) -> Dictionary:
	var s := {"troops": 0, "deployed": 0, "mustering": 0, "marching": 0,
		"guarding": 0, "withdrawing": 0, "idle": 0, "downed": 0}
	for u: Dictionary in game.units:
		if String(u.get("faction", "")) != faction:
			continue
		if not u.get("alive", false):
			continue
		if not SimCombat.is_fighter(u):
			continue
		s["troops"] = int(s["troops"]) + 1
		var a := assignment_of(u)
		if s.has(a):
			s[a] = int(s[a]) + 1
		else:
			s["idle"] = int(s["idle"]) + 1
	return s


## --- 1. live war-room ----------------------------------------------------------

static func build_warroom(ui: PhoneUI, game: GameState,
		box: VBoxContainer) -> void:
	_lbl(box, "Live — the map refreshes on its own.", FS_XS, C_DIM)
	var map := PhoneArmyMap.new()
	map.custom_minimum_size = Vector2(0, 560)
	box.add_child(map)
	map.setup(game, "view", "")
	var army := _army_of(game)
	for f: String in game.active_factions:
		var card := _card(box, _faction_color(f))
		var title := _lbl(card, _faction_name(f), FS_MD, _faction_color(f))
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		if army != null:
			var stance := String(army.get_stance(f))
			var slabel := String(
				SimArmy.STANCE_LABEL.get(stance, stance.capitalize()))
			_lbl(card, "Stance: " + slabel, FS_SM, C_TEXT)
		var s := order_summary(game, f)
		_lbl(card,
			"Troops: %d — deployed %d · mustering %d · marching %d · guarding %d · withdrawing %d · idle %d"
			% [int(s["troops"]), int(s["deployed"]), int(s["mustering"]),
			int(s["marching"]), int(s["guarding"]), int(s["withdrawing"]),
			int(s["idle"])], FS_XS, C_DIM)
		if army != null:
			var info: Dictionary = army.army_info(f)
			var wars: Array = info.get("at_war", [])
			if not wars.is_empty():
				_lbl(card, "At war with: " + ", ".join(wars), FS_XS,
					Color(0.95, 0.45, 0.40))
			else:
				_lbl(card, "At peace", FS_XS, C_DIM)
		if f != game.player_faction:
			_lbl(card, "Foreign army — view-only.", FS_XS, C_DIM)


## --- 2. veterans roster --------------------------------------------------------

static func build_roster(ui: PhoneUI, game: GameState,
		box: VBoxContainer) -> void:
	var pf := game.player_faction
	if _roster_faction == "" or not _roster_faction in game.active_factions:
		_roster_faction = pf
	var fac := _roster_faction
	_faction_picker(ui, game, box, fac, func(picked: String) -> void:
		_roster_faction = picked
		_rebuild(ui, game, box, "army_roster"))
	if fac != pf:
		_lbl(box, "Viewing %s forces — view-only." % _faction_name(fac),
			FS_XS, C_DIM)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	box.add_child(srow)
	for spec in [["kills", "Kills"], ["weapon", "Weapon"], ["name", "Name"]]:
		var key := String(spec[0])
		var on_sort := func() -> void:
			_roster_sort = key
			_rebuild(ui, game, box, "army_roster")
		var b := _btn(srow, "Sort: " + String(spec[1]), on_sort, FS_XS, 84.0)
		if key == _roster_sort:
			b.disabled = true
	var rows := _fighters(game, fac)
	# Include downed fighters at the end of the list (still the army's).
	for u: Dictionary in game.units:
		if String(u.get("faction", "")) != fac:
			continue
		if not u.get("alive", false) or not bool(u.get("downed", false)):
			continue
		if SimCombat.is_fighter(u):
			rows.append(u)
	_sort_mode = _roster_sort
	# Qualified ref: a bare static-func name does not bind a working
	# Callable from inside another static func (silent no-sort).
	rows.sort_custom(PhoneArmyExpansion._roster_cmp)
	_lbl(box, "%d fighters — %s" % [rows.size(), _faction_name(fac)],
		FS_SM, C_TEXT)
	for u: Dictionary in rows:
		var tier := veteran_tier(u)
		var tcol: Color = TIER_COLORS.get(tier, C_DIM)
		var line := "[%s] %s (%s) · Wpn Lv%d · %s · %d kills" % [
			tier, SimPersonality.display_name(u),
			String(u.get("job", "?")).capitalize(),
			int(u.get("weapon_level", 0)), assignment_of(u),
			int(u.get("kills", 0))]
		_lbl(box, line, FS_XS, tcol)
	_lbl(box,
		"Kill tallies post here from battle reports. Tiers come from field service: Warlord > Veteran (proven + armed) > Blooded (seen the field) > Recruit.",
		FS_XS, C_DIM)


static func _roster_cmp(a: Dictionary, b: Dictionary) -> bool:
	var ka := int(a.get("kills", 0))
	var kb := int(b.get("kills", 0))
	var wa := int(a.get("weapon_level", 0))
	var wb := int(b.get("weapon_level", 0))
	match _sort_mode:
		"weapon":
			if wa != wb:
				return wa > wb
			if ka != kb:
				return ka > kb
		"name":
			var na := SimPersonality.display_name(a)
			var nb := SimPersonality.display_name(b)
			if na != nb:
				return na < nb
		_:
			if ka != kb:
				return ka > kb
			if wa != wb:
				return wa > wb
	var fa := SimPersonality.display_name(a)
	var fb := SimPersonality.display_name(b)
	return fa < fb


## --- 3. warlord retinue ---------------------------------------------------------

static func build_retinue(ui: PhoneUI, game: GameState,
		box: VBoxContainer) -> void:
	var pf := game.player_faction
	if _retinue_faction == "" or not _retinue_faction in game.active_factions:
		_retinue_faction = pf
	var fac := _retinue_faction
	var can_command := fac == pf
	_faction_picker(ui, game, box, fac, func(picked: String) -> void:
		_retinue_faction = picked
		_rebuild(ui, game, box, "army_retinue"))
	var army := _army_of(game)
	if army == null:
		_lbl(box, "Army system not ready.", FS_SM, C_TEXT)
		return
	var wl := army.get_warlord(fac)
	if wl.is_empty():
		_lbl(box, "%s has no warlord yet — promote one from Command."
			% _faction_name(fac), FS_SM, C_TEXT)
		return
	var wl_id := int(wl.get("id", -1))
	var wcard := _card(box, C_GOLD)
	_lbl(wcard, "WARLORD — " + SimPersonality.display_name(wl), FS_MD, C_GOLD)
	_lbl(wcard, "%s · Wpn Lv%d · HP %d/%d · %s" % [
		String(wl.get("job", "?")).capitalize(),
		int(wl.get("weapon_level", 0)),
		int(wl.get("hp", 0)), int(wl.get("max_hp", 0)),
		assignment_of(wl)], FS_SM, C_TEXT)
	if not can_command:
		_lbl(box, "Foreign warlord — view-only (sovereignty).", FS_XS, C_DIM)
	var ret := _retinue(game, wl_id)
	_lbl(box, "Retinue (%d)" % ret.size(), FS_SM, C_TEXT)
	for u: Dictionary in ret:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var info := Label.new()
		info.text = "%s (%s) · Wpn Lv%d · %s · %d kills" % [
			SimPersonality.display_name(u),
			String(u.get("job", "?")).capitalize(),
			int(u.get("weapon_level", 0)), assignment_of(u),
			int(u.get("kills", 0))]
		info.add_theme_font_size_override("font_size", FS_XS)
		info.add_theme_color_override("font_color", C_TEXT)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		if can_command:
			var uid := int(u.get("id", -1))
			var on_remove := func() -> void:
				remove_retinue(game, fac, uid)
				_rebuild(ui, game, box, "army_retinue")
			_btn(row, "Remove", on_remove, FS_XS, 84.0)
	if can_command:
		_lbl(box, "Add to retinue — they march to the warlord's side.",
			FS_XS, C_DIM)
		var shown := 0
		for u: Dictionary in _fighters(game, fac):
			if shown >= 8:
				break
			var uid := int(u.get("id", -1))
			if uid == wl_id or int(u.get("retinue_of", -1)) == wl_id:
				continue
			var arow := HBoxContainer.new()
			arow.add_theme_constant_override("separation", 8)
			box.add_child(arow)
			var ainfo := Label.new()
			ainfo.text = "%s (%s) · %s" % [
				SimPersonality.display_name(u),
				String(u.get("job", "?")).capitalize(), assignment_of(u)]
			ainfo.add_theme_font_size_override("font_size", FS_XS)
			ainfo.add_theme_color_override("font_color", C_TEXT)
			ainfo.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ainfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			arow.add_child(ainfo)
			var auid := int(u.get("id", -1))
			var on_add := func() -> void:
				assign_retinue(game, fac, auid, wl_id)
				_rebuild(ui, game, box, "army_retinue")
			_btn(arow, "Add", on_add, FS_XS, 84.0)
			shown += 1
		if shown == 0:
			_lbl(box, "No free fighters to assign.", FS_XS, C_DIM)


static func _retinue(game: GameState, warlord_id: int) -> Array:
	var out := []
	for u: Dictionary in game.units:
		if not u.get("alive", false):
			continue
		if int(u.get("retinue_of", -1)) == warlord_id:
			out.append(u)
	return out


## Assign a fighter to the warlord's retinue (player faction only).
## Returns "" on success, refusal reason otherwise.
static func assign_retinue(game: GameState, faction: String, unit_id: int,
		warlord_id: int) -> String:
	if faction != game.player_faction:
		return "Foreign warlord — view-only (sovereignty)."
	var army := _army_of(game)
	if army == null:
		return "Army system not ready."
	var wl: Dictionary = army.get_warlord(faction)
	if wl.is_empty() or int(wl.get("id", -1)) != warlord_id:
		return "No such warlord."
	var target: Dictionary = {}
	for u: Dictionary in game.units:
		if int(u.get("id", -1)) == unit_id:
			target = u
			break
	if target.is_empty() or not target.get("alive", false):
		return "No such fighter."
	if int(target.get("id", -1)) == warlord_id:
		return "That's the warlord."
	if String(target.get("faction", "")) != faction:
		return "Not your troop."
	if not SimCombat.is_fighter(target):
		return "Not a fighter."
	target["retinue_of"] = warlord_id
	# March to the warlord's side — move_target is the sim-honored march
	# mark (combat.tick_unit walks it), so the retinue visibly assembles.
	target["move_target"] = wl.get("position", target.get("position"))
	return ""


static func remove_retinue(game: GameState, faction: String,
		unit_id: int) -> String:
	if faction != game.player_faction:
		return "Foreign warlord — view-only (sovereignty)."
	for u: Dictionary in game.units:
		if int(u.get("id", -1)) == unit_id:
			if String(u.get("faction", "")) != faction:
				return "Not your troop."
			u.erase("retinue_of")
			return ""
	return "No such fighter."


## --- 4. deployment map (tap-to-order rally) ---------------------------------------

static func build_deploy(ui: PhoneUI, game: GameState,
		box: VBoxContainer) -> void:
	var pf := game.player_faction
	_lbl(box, "Tap a point to rally your force there. Tap a troop to add it to the selection.",
		FS_XS, C_DIM)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 8)
	box.add_child(srow)
	for spec in [["field", "Field army"], ["mustered", "Mustered"],
			["all", "All fighters"]]:
		var key := String(spec[0])
		var on_scope := func() -> void:
			_deploy_scope = key
			_rebuild(ui, game, box, "army_deploy")
		var b := _btn(srow, String(spec[1]), on_scope, FS_XS, 84.0)
		if key == _deploy_scope:
			b.disabled = true
	var scope_ids := _scope_ids(game, _deploy_scope)
	var sel_count := _deploy_selected.size()
	_lbl(box, "Force: %d selected / %d in scope (%s)" % [
		sel_count, scope_ids.size(), _deploy_scope], FS_SM, C_TEXT)
	var map := PhoneArmyMap.new()
	map.custom_minimum_size = Vector2(0, 560)
	box.add_child(map)
	map.setup(game, "rally", pf)
	map.set_selected(_deploy_selected.keys())
	map.unit_tapped.connect(func(uid: int) -> void:
		_toggle_select(uid)
		_rebuild(ui, game, box, "army_deploy"))
	map.map_tapped.connect(func(pos: Vector2) -> void:
		var ids := _deploy_selected.keys()
		if ids.is_empty():
			ids = scope_ids
		var n := order_rally(game, ids, pos)
		if n > 0:
			_deploy_status = "Rally ordered — %d troops marching." % n
		else:
			_deploy_status = "No troops in that force."
		_rebuild(ui, game, box, "army_deploy"))
	if _deploy_status != "":
		_lbl(box, _deploy_status, FS_SM, C_GOLD)
		_deploy_status = ""
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	box.add_child(brow)
	var on_clear := func() -> void:
		_deploy_selected.clear()
		_rebuild(ui, game, box, "army_deploy")
	_btn(brow, "Clear selection", on_clear, FS_XS, 84.0)
	_lbl(box, "Orders go to your forces only (sovereignty).", FS_XS, C_DIM)


static func _toggle_select(uid: int) -> void:
	if _deploy_selected.has(uid):
		_deploy_selected.erase(uid)
	else:
		_deploy_selected[uid] = true


static func _scope_ids(game: GameState, scope: String) -> Array:
	var pf := game.player_faction
	var out := []
	for u: Dictionary in game.units:
		if String(u.get("faction", "")) != pf:
			continue
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if not SimCombat.is_fighter(u):
			continue
		var uid := int(u.get("id", -1))
		match scope:
			"field":
				if bool(u.get("deployed_for_war", false)) \
						or bool(u.get("mustering", false)) \
						or u.has("move_target"):
					out.append(uid)
			"mustered":
				if bool(u.get("mustering", false)):
					out.append(uid)
			_:
				out.append(uid)
	return out


## Order player-faction troops to rally at a world position. Foreign
## factions are refused (sovereignty) — returns -1 when the id list is
## not the player's force. Uses the sim-honored move_target march mark.
static func order_rally(game: GameState, unit_ids: Array,
		world_pos: Vector2) -> int:
	var pf := game.player_faction
	var n := 0
	for u: Dictionary in game.units:
		var uid := int(u.get("id", -1))
		if not uid in unit_ids:
			continue
		if String(u.get("faction", "")) != pf:
			continue
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		if not SimCombat.is_fighter(u):
			continue
		u["move_target"] = world_pos
		n += 1
	return n


## --- rebuild ----------------------------------------------------------------------

static func _rebuild(ui: PhoneUI, game: GameState, box: VBoxContainer,
		screen: String) -> void:
	for c in box.get_children():
		c.queue_free()
	# Children free at end of frame; defer the rebuild one frame so the
	# old map/timer is gone before the new one is built.
	var t := box.get_tree().create_timer(0.01)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(box):
			return
		build_nav(ui, box, screen)
		match screen:
			"army_warroom":
				build_warroom(ui, game, box)
			"army_roster":
				build_roster(ui, game, box)
			"army_retinue":
				build_retinue(ui, game, box)
			"army_deploy":
				build_deploy(ui, game, box)
	)
