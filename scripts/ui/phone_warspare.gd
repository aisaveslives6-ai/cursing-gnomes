class_name PhoneWarSpare
extends RefCounted

## War-spare / peace-treaty / disaster-aid phone UI (Jeremy 2026-10-11).
##
## Full-screen modals in the Bastard OS phone style: the fate-vote tally,
## the peace-treaty popup, the aid-vote popup, plus the "Peace Treaties"
## section of the diplomacy app with per-term negotiation.
##
## All rendering is static helpers taking the phone_ui node (theme consts and
## button builders are read off it, so this file never drifts from the OS
## look). The sim systems are reached via phone._gs.get("war_spare") /
## ("disaster_aid") — no setup() signature changes needed.


static func _war_spare(phone: PhoneUI):
	return phone._gs.get("war_spare")


static func _disaster_aid(phone: PhoneUI):
	return phone._gs.get("disaster_aid")


## --- modal shell (mirrors phone_ui's strategic-proposal dialog) -----------------


## Modal shell. Engine-proof height capping (Jeremy's P0 menu-clipping
## rule): the dialog gets an EXPLICIT centered rect via anchors — never
## taller than the safe viewport — instead of fighting container
## minimum-size propagation (a ScrollContainer always reports its child's
## full size, so min-size capping cannot shrink it). Inside, a plain
## Control holds three anchor-positioned bands:
##   head  — title + context, pinned to the top
##   scroll — the body, fills exactly what's left, scrolls internally
##   foot  — decision buttons, pinned to the bottom, never pushed away
##
## Measurement happens DEFERRED (two frames): pre-layout minimum sizes
## are unreliable (theme/fonts not resolved yet), so the dialog stays
## invisible until true post-layout sizes are known, then it is placed
## and fades in — a dramatic entrance, very AAA for the fate vote.
static func _modal(phone: PhoneUI, border: Color) -> Dictionary:
	var overlay := Control.new()
	overlay.name = "WarSpareModal"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var dlg := PanelContainer.new()
	var dsb := StyleBoxFlat.new()
	dsb.bg_color = phone.PH_SURFACE
	dsb.border_color = border
	dsb.set_border_width_all(3)
	dsb.set_corner_radius_all(20)
	dsb.content_margin_left = 28.0
	dsb.content_margin_right = 28.0
	dsb.content_margin_top = 28.0
	dsb.content_margin_bottom = 28.0
	dlg.add_theme_stylebox_override("panel", dsb)
	dlg.clip_contents = true
	# Centered anchors, explicit rect: never taller than the budget.
	# A VBox inside distributes: head (natural) + scroll (EXPAND_FILL,
	# shrinks below its content and scrolls internally — verified by probe)
	# + foot (natural, pinned). The foot can never be pushed off-screen.
	dlg.anchor_left = 0.5
	dlg.anchor_right = 0.5
	dlg.anchor_top = 0.5
	dlg.anchor_bottom = 0.5
	dlg.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dlg.grow_vertical = Control.GROW_DIRECTION_BOTH
	var mw := phone._modal_width()
	# Jeremy's safe-area priority (#6): the dialog lives INSIDE the phone
	# shell's safe band — below the Dynamic Island (7%/60px) and above the
	# home indicator (8.5%/72px) — never in raw viewport coordinates.
	var stop: float = phone._shell_safe_top
	var sbot: float = phone.phone_safe_bottom()
	var budget: float = phone._phone_h - stop - sbot
	var mid: float = (stop - sbot) * 0.5  # viewport-center -> safe-band-center
	dlg.offset_left = -mw * 0.5
	dlg.offset_right = mw * 0.5
	dlg.offset_top = -budget * 0.5 + mid
	dlg.offset_bottom = budget * 0.5 + mid
	overlay.add_child(dlg)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg.add_child(vbox)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vbox.add_child(head)
	var scroll := CapScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var foot := VBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	vbox.add_child(foot)
	phone.add_child(overlay)
	var m := {"overlay": overlay, "dlg": dlg, "head": head, "body": body,
		"foot": foot, "scroll": scroll, "budget": budget, "mid": mid}
	_schedule_cap(phone, m)
	return m


## Schedules the deferred hug pass (two frames out, so a real layout pass
## has run and minimum sizes are honest).
static func _schedule_cap(phone: PhoneUI, m: Dictionary) -> void:
	var overlay: Control = m["overlay"]
	if overlay.is_inside_tree() and overlay.get_tree() != null:
		_connect_frames(overlay, phone, m)
	else:
		# Built during scene init (no tree yet): wait for entry.
		overlay.tree_entered.connect(_connect_frames.bind(overlay, phone, m))


static func _connect_frames(overlay: Control, phone: PhoneUI,
		m: Dictionary) -> void:
	var tree := overlay.get_tree()
	if tree == null:
		return
	var state := [0, null]  # frames elapsed, own callable (for disconnect)
	var cb := func() -> void:
		state[0] += 1
		if int(state[0]) >= 2:
			tree.process_frame.disconnect(state[1])
			if is_instance_valid(phone) and is_instance_valid(overlay):
				_deferred_cap(phone, m)
	state[1] = cb
	tree.process_frame.connect(cb)


## Deferred hug: with true post-layout sizes, shrink the dialog to fit
## short content. Only ever shrinks — the initial budget rect is always
## safe, so this can never cause clipping.
static func _deferred_cap(phone: PhoneUI, m: Dictionary) -> void:
	if not is_instance_valid(m["dlg"]):
		return  # closed before we got here
	var dlg := m["dlg"] as PanelContainer
	var head := m["head"] as VBoxContainer
	var body := m["body"] as VBoxContainer
	var foot := m["foot"] as VBoxContainer
	var budget := float(m["budget"])
	var mid := float(m["mid"])
	var chrome := 56.0 + 28.0  # dlg margins + vbox separations
	var natural: float = head.get_combined_minimum_size().y + body.get_combined_minimum_size().y + foot.get_combined_minimum_size().y + chrome
	if natural < budget - 4.0 and natural > 200.0:
		dlg.offset_top = -natural * 0.5 + mid
		dlg.offset_bottom = natural * 0.5 + mid


static func _title(phone: PhoneUI, vbox: VBoxContainer, text: String,
		color: Color) -> void:
	var t := Label.new()
	t.text = text
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.add_theme_font_size_override("font_size", phone.FONT_LG)
	t.add_theme_color_override("font_color", color)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(t)


static func _body(phone: PhoneUI, vbox: VBoxContainer, text: String,
		size: int = -1, color: Color = Color(0, 0, 0, 0)) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size",
		size if size > 0 else phone.FONT_MD)
	l.add_theme_color_override("font_color",
		color if color.a > 0.0 else phone.PH_TEXT)
	vbox.add_child(l)


static func _section(phone: PhoneUI, vbox: VBoxContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", phone.FONT_MD)
	l.add_theme_color_override("font_color", phone.PH_ACCENT)
	vbox.add_child(l)


static func _close_btn(phone: PhoneUI, vbox: VBoxContainer, overlay: Control,
		text: String = "Close") -> void:
	var b: Button = phone._btn(text, func() -> void: overlay.queue_free())
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(b)


## Two-step confirm for the heavy choices (no accidental taps, no ambiguity).
static func _confirm(phone: PhoneUI, prompt: String, confirm_text: String,
		on_yes: Callable) -> void:
	var m := _modal(phone, phone.PH_ACCENT)
	var body: VBoxContainer = m["body"]
	var foot: VBoxContainer = m["foot"]
	var overlay: Control = m["overlay"]
	_body(phone, body, prompt)
	var yes: Button = phone._diplo_btn(confirm_text, func() -> void:
		overlay.queue_free()
		on_yes.call())
	yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(yes)
	var no: Button = phone._diplo_btn("Hold on", func() -> void:
		overlay.queue_free())
	no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(no)


static func _faction_color(phone: PhoneUI, faction: String) -> Color:
	return phone._DIPLO_FACTION_COLORS.get(faction, Color(0.75, 0.75, 0.75))


## --- fate vote modal ---------------------------------------------------------------


static func show_fate_vote(phone: PhoneUI, vote: Dictionary) -> void:
	var loser_name := String(vote.get("loser_name", "a faction"))
	var taker_name := String(vote.get("taker_name", ""))
	var town := String(vote.get("town", ""))
	var via := String(vote.get("via", "captured"))
	var m := _modal(phone, Color(0.75, 0.25, 0.22))
	var head: VBoxContainer = m["head"]
	var body: VBoxContainer = m["body"]
	var foot: VBoxContainer = m["foot"]
	var overlay: Control = m["overlay"]
	_title(phone, head, "THE FATE OF THE " + loser_name.to_upper(),
		Color(1.0, 0.45, 0.4))
	# Context lives in the scrollable body (it's long at phone font
	# sizes); the head keeps only the dramatic title.
	_body(phone, body,
		"%s has %s to the %s. The factions of the land now vote: SPARE them, or END them." % [
			town, "fallen" if via == "captured" else "been destroyed by",
			taker_name])
	# Who's at war with the fallen, and why.
	var wars: Array = vote.get("wars", [])
	if not wars.is_empty():
		_section(phone, body, "AT WAR WITH THE FALLEN")
		for w in wars:
			var fn := String(w.get("faction_name", "?"))
			var db := String(w.get("declared_by_name", ""))
			var days := int(w.get("war_days", 0))
			var why := "at war"
			if db != "":
				why = "%s declared war %d days ago" % [db, days]
			elif days > 0:
				why = "at war for %d days" % days
			var gr: Array = w.get("grievances", [])
			if not gr.is_empty():
				var g0: Dictionary = gr[0]
				why += " — grievance: %s" % String(
					g0.get("type", "")).replace("_", " ")
			_body(phone, body, "• %s — %s" % [fn, why], phone.FONT_SM,
				phone.PH_TEXT_DIM)
	# The tally, faction by faction. Rows live in the capped body scroll —
	# no nested ScrollContainer (nested scrolls fight on touch).
	_section(phone, body, "THE VOTE")
	for e in vote.get("votes", []):
		var vn := String(e.get("voter_name", "?"))
		var vv := String(e.get("vote", "pending"))
		var badge := "…"
		var bcolor := phone.PH_TEXT_DIM
		if vv == "spare":
			badge = "SPARE"
			bcolor = Color(1.0, 0.84, 0.35)
		elif vv == "kill":
			badge = "END"
			bcolor = Color(1.0, 0.35, 0.3)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var dot := ColorRect.new()
		dot.color = _faction_color(phone, String(e.get("voter", "")))
		dot.custom_minimum_size = Vector2(28, 28)
		row.add_child(dot)
		var name_l := Label.new()
		name_l.text = "%s (%s)" % [vn, String(e.get("leader", ""))]
		name_l.add_theme_font_size_override("font_size", phone.FONT_SM)
		name_l.add_theme_color_override("font_color", phone.PH_TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_l)
		var b_l := Label.new()
		b_l.text = badge
		b_l.add_theme_font_size_override("font_size", phone.FONT_SM)
		b_l.add_theme_color_override("font_color", bcolor)
		row.add_child(b_l)
		var reason := String(e.get("reason", ""))
		if reason != "":
			var r_l := Label.new()
			r_l.text = "“%s”" % reason
			r_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r_l.add_theme_font_size_override("font_size", phone.FONT_SM)
			r_l.add_theme_color_override("font_color", phone.PH_TEXT_DIM)
			r_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(r_l)
	# The player's choice: big full-width buttons, stacked, confirmed.
	# No accidents, never scrolled away, never clipped.
	if bool(vote.get("player_votes", false)) \
			and String(vote.get("player_vote", "pending")) == "pending":
		_section(phone, foot, "THE CROWN DECIDES")
		var ws = _war_spare(phone)
		var spare_b: Button = phone._diplo_btn("SPARE", func() -> void:
			_confirm(phone,
				"Spare the %s? Their wars will end, and a peace treaty with real terms will be signed." % loser_name,
				"Spare them",
				func() -> void:
					overlay.queue_free()
					if ws != null:
						ws.cast_player_vote(true)))
		spare_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(spare_b)
		var end_b: Button = phone._diplo_btn("END THEM", func() -> void:
			_confirm(phone,
				"End the %s? No treaty, no mercy — the war grinds on to its bitter end." % loser_name,
				"End them",
				func() -> void:
					overlay.queue_free()
					if ws != null:
						ws.cast_player_vote(false)))
		end_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(end_b)
	else:
		var res := String(vote.get("result", ""))
		if res != "":
			var sc2 := int(vote.get("spare_count", 0))
			var kc := int(vote.get("kill_count", 0))
			if res == "spared":
				_title(phone, foot,
					"SPARED — %d to %d" % [sc2, kc],
					Color(1.0, 0.84, 0.35))
			else:
				_title(phone, foot,
					"CONDEMNED — %d to %d" % [kc, sc2],
					Color(1.0, 0.35, 0.3))
		_close_btn(phone, foot, overlay)


## --- peace treaty modal --------------------------------------------------------------


static func show_treaty(phone: PhoneUI, treaty: Dictionary) -> void:
	var m := _modal(phone, phone.PH_ACCENT)
	var head: VBoxContainer = m["head"]
	var body: VBoxContainer = m["body"]
	var foot: VBoxContainer = m["foot"]
	var overlay: Control = m["overlay"]
	_title(phone, head, "PEACE TREATY", phone.PH_ACCENT)
	_body(phone, head, "%s ↔ %s" % [
		String(treaty.get("loser_name", "?")),
		String(treaty.get("taker_name", "?"))])
	_section(phone, body, "TERMS")
	for t in treaty.get("terms", []):
		var st := String(t.get("status", "active"))
		var col := phone.PH_TEXT
		if st != "active":
			col = phone.PH_TEXT_DIM
		_body(phone, body, "• %s [%s]" % [String(t.get("label", "")), st],
			phone.FONT_SM, col)
	var gn: Array = treaty.get("guarantor_names", [])
	if not gn.is_empty():
		_body(phone, body, "Guaranteed by: " + ", ".join(gn), phone.FONT_SM,
			phone.PH_TEXT_DIM)
	_body(phone, body, String(treaty.get("warning", "")), phone.FONT_SM,
		Color(1.0, 0.55, 0.5))
	_close_btn(phone, foot, overlay, "Accept")


## --- aid vote modal --------------------------------------------------------------------


static func show_aid_vote(phone: PhoneUI, vote: Dictionary) -> void:
	var victim_name := String(vote.get("victim_name", "a faction"))
	var cause := String(vote.get("cause_text", "a natural disaster"))
	var m := _modal(phone, Color(0.35, 0.75, 0.5))
	var head: VBoxContainer = m["head"]
	var body: VBoxContainer = m["body"]
	var foot: VBoxContainer = m["foot"]
	var overlay: Control = m["overlay"]
	_title(phone, head, "AID FOR THE " + victim_name.to_upper(),
		Color(0.5, 0.9, 0.6))
	_body(phone, body,
		"%s has devastated the %s. No trial, no vote of fate — nature answers to no one. But neighbors can answer. Each faction votes: send builders to help them rebuild, or leave them to the ashes?" % [
			cause.capitalize(), victim_name])
	_section(phone, body, "THE VOTE")
	for e in vote.get("votes", []):
		var vn := String(e.get("voter_name", "?"))
		var vv := String(e.get("vote", "pending"))
		var badge := "…"
		var bcolor := phone.PH_TEXT_DIM
		if vv == "yes":
			badge = "AID"
			bcolor = Color(0.5, 0.9, 0.6)
		elif vv == "no":
			badge = "NO"
			bcolor = Color(1.0, 0.35, 0.3)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		body.add_child(row)
		var dot := ColorRect.new()
		dot.color = _faction_color(phone, String(e.get("voter", "")))
		dot.custom_minimum_size = Vector2(28, 28)
		row.add_child(dot)
		var name_l := Label.new()
		name_l.text = "%s (%s)" % [vn, String(e.get("leader", ""))]
		name_l.add_theme_font_size_override("font_size", phone.FONT_SM)
		name_l.add_theme_color_override("font_color", phone.PH_TEXT)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(name_l)
		var b_l := Label.new()
		b_l.text = badge
		b_l.add_theme_font_size_override("font_size", phone.FONT_SM)
		b_l.add_theme_color_override("font_color", bcolor)
		row.add_child(b_l)
		var reason := String(e.get("reason", ""))
		if reason != "":
			var r_l := Label.new()
			r_l.text = "“%s”" % reason
			r_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			r_l.add_theme_font_size_override("font_size", phone.FONT_SM)
			r_l.add_theme_color_override("font_color", phone.PH_TEXT_DIM)
			r_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			body.add_child(r_l)
	if bool(vote.get("player_votes", false)) \
			and String(vote.get("player_vote", "pending")) == "pending":
		_section(phone, foot, "THE CROWN DECIDES")
		var da = _disaster_aid(phone)
		var yes_b: Button = phone._diplo_btn("SEND AID", func() -> void:
			_confirm(phone,
				"Send your builders to the %s? They will travel there, repair and rebuild for a few days, then return home. Kindness is remembered." % victim_name,
				"Send aid",
				func() -> void:
					overlay.queue_free()
					if da != null:
						da.cast_player_vote(true)))
		yes_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(yes_b)
		var no_b: Button = phone._diplo_btn("DECLINE", func() -> void:
			_confirm(phone,
				"Leave the %s to rebuild alone? They will remember who stayed home." % victim_name,
				"Decline",
				func() -> void:
					overlay.queue_free()
					if da != null:
						da.cast_player_vote(false)))
		no_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(no_b)
	else:
		var res := String(vote.get("result", ""))
		if res == "aided":
			_title(phone, foot, "AID IS COMING",
				Color(0.5, 0.9, 0.6))
		elif res == "alone":
			_title(phone, foot, "NO AID COMES",
				Color(1.0, 0.35, 0.3))
		_close_btn(phone, foot, overlay)


## --- diplomacy app: peace treaties section ----------------------------------------------


static func add_treaty_section(phone: PhoneUI, box: VBoxContainer) -> void:
	var ws = _war_spare(phone)
	if ws == null:
		return
	var treaties: Array = ws.treaties_for(phone._gs.player_faction)
	if treaties.is_empty():
		return
	var head := Label.new()
	head.text = "Peace Treaties"
	head.add_theme_font_size_override("font_size", phone.FONT_LG)
	head.add_theme_color_override("font_color", phone.PH_ACCENT)
	box.add_child(head)
	for t in treaties:
		box.add_child(_treaty_card(phone, t))


static func _treaty_card(phone: PhoneUI, t: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = phone.PH_SURFACE
	csb.set_corner_radius_all(16)
	csb.border_width_top = 4
	csb.border_color = phone.PH_ACCENT
	csb.content_margin_left = 14.0
	csb.content_margin_right = 14.0
	csb.content_margin_top = 12.0
	csb.content_margin_bottom = 12.0
	card.add_theme_stylebox_override("panel", csb)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var ws = _war_spare(phone)
	var title := Label.new()
	title.text = "Treaty: %s ↔ %s" % [
		String(t.get("loser_name", t.get("loser", "?"))),
		String(t.get("taker_name", t.get("taker", "?")))]
	title.add_theme_font_size_override("font_size", phone.FONT_MD)
	title.add_theme_color_override("font_color", phone.PH_TEXT)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(title)
	var tid := int(t.get("id", 0))
	var terms: Array = t.get("terms", [])
	for i in terms.size():
		var term: Dictionary = terms[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		box.add_child(row)
		var l := Label.new()
		l.text = "• %s [%s]" % [String(term.get("label", "")),
			String(term.get("status", ""))]
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", phone.FONT_SM)
		l.add_theme_color_override("font_color", phone.PH_TEXT_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
		var kind := String(term.get("kind", ""))
		if String(term.get("status", "")) == "active" \
				and kind in ["tribute", "dmz"]:
			var nb: Button = phone._btn("Negotiate", func() -> void:
				_show_negotiate(phone, t, i))
			row.add_child(nb)
	return card


## --- negotiate dialog ----------------------------------------------------------------------


static func _show_negotiate(phone: PhoneUI, t: Dictionary, term_idx: int) -> void:
	var ws = _war_spare(phone)
	if ws == null:
		return
	var terms: Array = t.get("terms", [])
	if term_idx < 0 or term_idx >= terms.size():
		return
	var term: Dictionary = terms[term_idx]
	var tid := int(t.get("id", 0))
	var m := _modal(phone, phone.PH_ACCENT)
	var head: VBoxContainer = m["head"]
	var body: VBoxContainer = m["body"]
	var foot: VBoxContainer = m["foot"]
	var overlay: Control = m["overlay"]
	_title(phone, head, "NEGOTIATE TERM", phone.PH_ACCENT)
	_body(phone, body, String(term.get("label", "")))
	_body(phone, body,
		"Offer gold to the %s to lift this term. They weigh your offer against what the term is still worth — and how they feel about you. Lifting everything is possible, but never free." % [
			String(t.get("taker_name", t.get("taker", "?")))],
		phone.FONT_SM, phone.PH_TEXT_DIM)
	var burden: float = ws.term_burden(term)
	_body(phone, body, "Remaining burden: ~%d gold" % int(burden),
		phone.FONT_SM, phone.PH_TEXT_DIM)
	var offers: Array = [0.25, 0.5, 1.0]
	for frac in offers:
		var amt := int(round(burden * float(frac) / 10.0)) * 10
		if amt < 10:
			amt = 10
		var b: Button = phone._diplo_btn("%d gold" % amt,
			func() -> void:
				overlay.queue_free()
				var res: Dictionary = ws.negotiate_term(tid, term_idx,
					float(amt))
				_result_modal(phone,
					"Accepted — the term is lifted." if bool(
						res.get("accepted", false))
					else "Refused",
					String(res.get("msg", "")))
				phone._show_diplomacy())
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foot.add_child(b)
	_close_btn(phone, foot, overlay, "Not now")


static func _result_modal(phone: PhoneUI, title_text: String, msg: String) -> void:
	var m := _modal(phone, phone.PH_ACCENT)
	var head: VBoxContainer = m["head"]
	var foot: VBoxContainer = m["foot"]
	var overlay: Control = m["overlay"]
	_title(phone, head, title_text, phone.PH_ACCENT)
	_body(phone, head, msg)
	_close_btn(phone, foot, overlay)
