class_name ArmyTab
extends RefCounted
## Army tab UI for the HUD side panel.
##
## Builds the full army command view into the side panel's VBoxContainer:
## army summary, stances (auto/guard/lead), draft/muster/deploy, warlord
## promotion, weapon upgrades, war intel, war-weariness, government roster,
## and the conquest keep-or-rename prompt. Rebuilds itself after every
## action (same pattern as the rest of hud.gd's tab bodies).
##
## hud.gd integration (HOOK — see port report):
##   elif tab == "army":
##       _side_title("Army")
##       ArmyTab.build(game, _side_vbox)


## UI scale set by HUD (Jeremy 2026-10-03: everything too small).
static var _S := 1.0


## Transient command feedback, shown once at the top of the Command section
## on the rebuild after a command button is pressed (then cleared).
static var _cmd_status := ""


static func set_ui_scale(s: float) -> void:
	_S = maxf(0.5, s)


static func build(game: GameState, vbox: VBoxContainer) -> void:
	for c in vbox.get_children():
		c.queue_free()
	var army: SimArmy = game.get_meta("army") if game.has_meta("army") else null
	if army == null:
		_label(vbox, "Army system not ready.")
		return
	var pf: String = game.player_faction
	_conquest_section(game, army, vbox, pf)
	_summary_section(game, army, vbox, pf)
	_stance_section(game, army, vbox, pf)
	_command_section(game, army, vbox, pf)
	_upgrade_section(game, army, vbox, pf)
	_intel_section(game, army, vbox, pf)
	_government_section(game, vbox, pf)


static func _army(game: GameState) -> SimArmy:
	return game.get_meta("army") if game.has_meta("army") else null


static func _label(vbox: VBoxContainer, text: String, size: int = 24) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(1, int(round(size * _S))))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(l)
	return l


static func _button(vbox: VBoxContainer, text: String,
		on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280 * _S, 88 * _S)
	b.add_theme_font_size_override("font_size", maxi(1, int(round(24 * _S))))
	b.pressed.connect(on_press)
	vbox.add_child(b)
	return b


static func _rebuild(game: GameState, vbox: VBoxContainer) -> void:
	build(game, vbox)


## --- conquest keep-or-rename --------------------------------------------------
## HTML queueConquestPrompt: conquer a foreign hall -> choose keep-or-rename.

static func _conquest_section(game: GameState, army: SimArmy,
		vbox: VBoxContainer, pf: String) -> void:
	var item: Dictionary = army.pending_conquest()
	if item.is_empty():
		return
	_label(vbox, "CONQUEST!", 28)
	_label(vbox, "Your troops have taken %s. Keep its name, or give it a new one?"
		% String(item.get("old_name", "the settlement")))
	var edit := LineEdit.new()
	edit.placeholder_text = "New name (blank = keep)"
	edit.custom_minimum_size = Vector2(280 * _S, 88 * _S)
	edit.add_theme_font_size_override("font_size", maxi(1, int(round(24 * _S))))
	vbox.add_child(edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	var keep := Button.new()
	keep.text = "Keep"
	keep.custom_minimum_size = Vector2(140 * _S, 88 * _S)
	keep.add_theme_font_size_override("font_size", maxi(1, int(round(24 * _S))))
	keep.pressed.connect(func() -> void:
		army.resolve_conquest("")
		_rebuild(game, vbox))
	row.add_child(keep)
	var rename := Button.new()
	rename.text = "Rename"
	rename.custom_minimum_size = Vector2(140 * _S, 88 * _S)
	rename.add_theme_font_size_override("font_size", maxi(1, int(round(24 * _S))))
	rename.pressed.connect(func() -> void:
		army.resolve_conquest(edit.text)
		_rebuild(game, vbox))
	row.add_child(rename)


## --- army summary --------------------------------------------------------------

static func _summary_section(game: GameState, army: SimArmy,
		vbox: VBoxContainer, pf: String) -> void:
	var info: Dictionary = army.army_info(pf)
	_label(vbox, "Your forces", 28)
	_label(vbox, "Troops: %d   Downed: %d" % [
		int(info["troops"]), int(info["downed"])])
	_label(vbox, "Warlord: %s" % (String(info["warlord_name"])
		if bool(info["warlord"]) else "none"))
	_label(vbox, "Avg weapon level: %.1f / 3" % float(info["avg_weapon_level"]))
	var jobs: Dictionary = info["jobs"]
	if not jobs.is_empty():
		var parts: Array[String] = []
		for j in jobs.keys():
			parts.append("%s x%d" % [j.capitalize(), int(jobs[j])])
		_label(vbox, "By job: " + ", ".join(parts))
	var wars: Array = info["at_war"]
	if not wars.is_empty():
		_label(vbox, "At war with: " + ", ".join(wars) + " — morale %.0f"
			% float(info["morale"]))
	else:
		_label(vbox, "At peace — morale %.0f" % float(info["morale"]))
	_fort_section(game, vbox, pf)


## --- star forts (Jeremy 2026-10-06, lane 7) -------------------------------------
## One row per star fort: garrisoned troops (by job) + parked artillery.

static func _fort_section(game: GameState, vbox: VBoxContainer,
		pf: String) -> void:
	var sfb = game.get("starfort_bases")
	if sfb == null or not sfb.has_method("garrison_report"):
		return
	var report: Array = sfb.garrison_report(pf)
	if report.is_empty():
		return
	_label(vbox, "Star forts", 28)
	for r: Dictionary in report:
		var tname := "town"
		var tid := int(r.get("town_id", -1))
		if game.towns.has(tid):
			tname = String(game.towns[tid].get("name", "town"))
		var by_job: Dictionary = r.get("by_job", {})
		var jobs := ""
		if not by_job.is_empty():
			var parts: Array[String] = []
			for j in by_job.keys():
				parts.append("%s x%d" % [String(j).capitalize(),
					int(by_job[j])])
			jobs = " (" + ", ".join(parts) + ")"
		_label(vbox, "Fort at %s: garrison %d%s, artillery %d" % [tname,
			int(r.get("troops", 0)), jobs, int(r.get("artillery", 0))])


## --- stances -------------------------------------------------------------------
## HTML command-menu orders: auto = AI sandbox, guard = hold, lead = march.

static func _stance_section(game: GameState, army: SimArmy,
		vbox: VBoxContainer, pf: String) -> void:
	_label(vbox, "Stance", 28)
	var cur: String = army.get_stance(pf)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)
	for s in SimArmy.STANCES:
		var b := Button.new()
		b.text = String(SimArmy.STANCE_LABEL[s])
		if s == cur:
			b.text = "> " + b.text
			b.disabled = true
		b.custom_minimum_size = Vector2(200 * _S, 88 * _S)
		b.add_theme_font_size_override("font_size", maxi(1, int(round(24 * _S))))
		var stance: String = s
		b.pressed.connect(func() -> void:
			army.set_stance(pf, stance)
			_rebuild(game, vbox))
		row.add_child(b)


## --- draft / muster / deploy / warlord ------------------------------------------

static func _command_section(game: GameState, army: SimArmy,
		vbox: VBoxContainer, pf: String) -> void:
	_label(vbox, "Command", 28)
	if _cmd_status != "":
		_label(vbox, _cmd_status, 20)
		_cmd_status = ""
	_button(vbox, "Draft citizens (emergency)", func() -> void:
		var n: int = army.draft(pf)
		_rebuild(game, vbox))
	_button(vbox, "Muster for war", func() -> void:
		army.muster(pf)
		_rebuild(game, vbox))
	_button(vbox, "Deploy for war", func() -> void:
		army.deploy_for_war(pf)
		_rebuild(game, vbox))
	# Jeremy 2026-10-06 (launch readiness): the ADVISER'S WARNING gazette
	# tells the player "Order a retreat before it's too late" — the order
	# has to exist. SimArmy.order_retreat is the player entry point
	# (foreign factions stay refused by the sovereignty gate).
	_button(vbox, "Retreat to hall", func() -> void:
		var n: int = army.order_retreat(pf)
		if n > 0:
			_cmd_status = "%d troops falling back to the hall." % n
		else:
			_cmd_status = "No field troops to withdraw."
		_rebuild(game, vbox))
	var wl: Dictionary = army.get_warlord(pf)
	_button(vbox, "Promote warlord" if wl.is_empty()
		else "Warlord: " + SimPersonality.display_name(wl), func() -> void:
		if wl.is_empty():
			army.promote_warlord(pf)
		_rebuild(game, vbox))


## --- weapon upgrades ------------------------------------------------------------
## HTML weaponsmith weapon_up1/2/3: +8% damage each, visible in combat.

static func _upgrade_section(game: GameState, army: SimArmy,
		vbox: VBoxContainer, pf: String) -> void:
	_label(vbox, "Weaponsmith upgrades", 28)
	var shown := 0
	for u: Dictionary in game.units:
		if shown >= 6:
			break
		if String(u.get("faction", "")) != pf:
			continue
		if not u.get("alive", false) or not SimCombat.is_fighter(u):
			continue
		var lvl: int = int(u.get("weapon_level", 0))
		var fw: String = String(u.get("firearm", "basic"))
		var nm: String = SimPersonality.display_name(u)
		var line := "%s — %s Lv%d" % [nm,
			SimCombat.firearm_name(pf, fw), lvl]
		if lvl >= SimCombat.MAX_WEAPON_LEVEL:
			_label(vbox, line + " (MAX)")
		else:
			var cost: Dictionary = army.weapon_upgrade_cost(int(u.get("id", 0)))
			_label(vbox, line + " -> Lv%d  (gold %d, wood %d)" % [
				lvl + 1, int(cost.get("gold", 0)), int(cost.get("wood", 0))])
			var uid: int = int(u.get("id", 0))
			_button(vbox, "Upgrade %s" % nm, func() -> void:
				army.buy_weapon_upgrade(uid)
				_rebuild(game, vbox))
		shown += 1


## --- war intel ------------------------------------------------------------------
## HTML war32Estimate: imperfect enemy strength — noisy, never exact.

static func _intel_section(game: GameState, army: SimArmy,
		vbox: VBoxContainer, pf: String) -> void:
	_label(vbox, "War intel", 28)
	# Perf R30: one shared census for all four estimates (was one full
	# unit+building scan set per faction).
	var census: Dictionary = army._daily_census()
	for f: String in Config.FACTIONS.keys():
		if f == pf:
			continue
		var est: Dictionary = army._estimate_strength_c(f, census)
		var rel := "?"
		if army.diplomacy != null:
			rel = String(army.diplomacy.relation_state(pf, f))
		_label(vbox, "%s (%s): ~%d fighters, ~%d defenses — est. strength %.0f (intel ±%.0f%%)"
			% [f.capitalize(), rel, int(est["mil"]), int(est["def"]),
			float(est["score"]),
			absf(1.0 - float(est["noise"])) * 100.0])
	_label(vbox, "Scouts' reports are rough — expect surprises.", 13)


## --- government -------------------------------------------------------------------
## Who holds the roles the phone's "My Government" section lists.

static func _government_section(game: GameState, vbox: VBoxContainer,
		pf: String) -> void:
	_label(vbox, "Government", 28)
	var order := ["mayor", "adviser", "commander", "watch_captain",
		"guild_master"]
	var found := false
	for role in order:
		for u: Dictionary in game.units:
			if String(u.get("faction", "")) != pf:
				continue
			if not u.get("alive", false):
				continue
			if SimArmy.gov_role_of(u) != role:
				continue
			_label(vbox, "%s: %s" % [role.capitalize().replace("_", " "),
				SimPersonality.display_name(u)])
			found = true
	if not found:
		_label(vbox, "No government yet — found a town to staff it.")
