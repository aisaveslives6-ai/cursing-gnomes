class_name PhoneRumors
extends RefCounted
## Rumor Mill phone app builder (Jeremy 2026-10-06: every routine is now
## hearsay/chat + the phone controls the whole game).
##
## Live view of SimHearsay.live_rumors(): heat-tagged cards with kind,
## age, spread, distortion, and investigation state. From a card the
## player can INVESTIGATE a rumor (the crown asks NPCs about it via the
## DM flow) and see reputations move. Debunked rumors show their
## correction status; verified ones show confirmation.
##
## Pure builder: phone_ui.gd does the sim reads and hands the rumor array
## over, plus two injected callables (rep lookup, investigate action), so
## this file never touches the sim layer (cold lane).
##
## Phone-UI conventions honored: no emoji anywhere (tofu risk on the phone
## font) — heat is a colored text tag instead. iPhone-first: cards use the
## shared phone theme, touch-sized padding, autowrap text.


## --- phone theme (mirrors PhoneUI consts; kept local so this file builds
## standalone in tests without instantiating PhoneUI) ---
const FONT_SM := 34
const FONT_MD := 42
const PH_TEXT := Color(0.96, 0.96, 0.97)
const PH_TEXT_DIM := Color(0.62, 0.64, 0.68)
const PH_SURFACE := Color(0.105, 0.115, 0.148)
const PH_GOOD := Color(0.45, 0.95, 0.55)
const PH_BAD := Color(1.0, 0.45, 0.35)


## Heat tag text + tint. Same 0.7/0.4 thresholds as SimHearsay.hearsay_lines.
static func heat_tag(heat: float) -> String:
	if heat >= 0.7:
		return "HOT"
	if heat >= 0.4:
		return "WARM"
	return "faint"


static func heat_tint(heat: float) -> Color:
	if heat >= 0.7:
		return Color(1.0, 0.45, 0.35)   # ember red
	if heat >= 0.4:
		return Color(1.0, 0.78, 0.35)   # amber
	return Color(0.55, 0.70, 0.95)      # moonlit blue


## Short display tag for a rumor kind. Unknown kinds (siblings add these)
## fall back to a capitalized raw kind — never blank, never a crash.
static func kind_label(kind: String) -> String:
	match kind:
		"war":
			return "WAR"
		"peace":
			return "PEACE"
		"smear":
			return "SMEAR"
		"slur":
			return "SLUR"
		"disaster":
			return "DISASTER"
		"death":
			return "DEATH"
		"tribute":
			return "TRIBUTE"
		"forecast":
			return "FORECAST"
		"news":
			return "NEWS"
		"life":
			return "TALK"
		"cache":
			return "CACHE"
		"scout":
			return "SCOUT"
		"misc":
			return "WORD"
		_:
			if kind.strip_edges() == "":
				return "WORD"
			return kind.strip_edges().capitalize()


## War-kind tag, gated on live diplomacy (Jeremy 2026-10-06: WAR tags were
## showing for stale capture/battle rumors while no faction was at war).
## war_of: Callable(faction_key) -> bool — injected live check (cold lane).
## An actually-active war stamps WAR; anything else (peacetime chatter,
## subjectless gossip) is WAR TALK. Never blank, never a crash.
static func war_tag(subject: String, war_of: Callable) -> String:
	if subject.strip_edges() != "" and war_of.is_valid():
		if bool(war_of.call(subject.strip_edges())):
			return "WAR"
	return "WAR TALK"


## Named attribution for the meta line (Jeremy 2026-10-06: "3 gnomes
## whisper it" was unhelpful). name_of: Callable(unit_id) -> String.
static func _unit_name(name_of: Callable, uid: int) -> String:
	var nm := String(name_of.call(uid)).strip_edges()
	return nm if nm != "" else "a gnome"


## Meta line under the rumor text: age, spread, distortion, gazette
## origin, plus investigation status and — for smears — the target's
## current reputation (via the injected rep_of callable, unit_id -> 0..100).
## name_of (unit_id -> String) names the source when available: a first-hand
## witness beats "N gnomes whisper it".
static func meta_line(r: Dictionary, rep_of: Callable = Callable(),
		name_of: Callable = Callable()) -> String:
	var bits: Array[String] = []
	var day: int = int(r.get("day", 1))
	bits.append("day %d" % day)
	if bool(r.get("debunked", false)):
		bits.append("DEBUNKED — corrected in the Gazette")
	elif bool(r.get("verified", false)):
		bits.append("confirmed by crown investigators")
	var knowers: Array = r.get("knowers", [])
	var witnesses: Array = r.get("witnesses", [])
	if name_of.is_valid():
		# Named source first — who actually saw / heard it.
		if not witnesses.is_empty():
			bits.append("seen by %s" % _unit_name(name_of,
				int(witnesses[0])))
		elif not knowers.is_empty():
			var src := "heard from %s" % _unit_name(name_of,
				int(knowers[0]))
			if knowers.size() > 1:
				src += " (+%d more)" % (knowers.size() - 1)
			bits.append(src)
		else:
			bits.append("no one admits hearing it")
	else:
		var n: int = knowers.size()
		if n <= 0:
			bits.append("no one admits hearing it")
		elif n == 1:
			bits.append("1 gnome whispers it")
		else:
			bits.append("%d gnomes whisper it" % n)
	var twists: int = int(r.get("distortions", 0))
	if twists > 0:
		bits.append("twisted %dx in retelling" % twists)
	if bool(r.get("from_gazette", false)):
		bits.append("via the Gazette")
	# Smears move reputations — show where the target stands now.
	if String(r.get("kind", "")) == "smear" and rep_of.is_valid():
		var tid: int = int(r.get("target_id", 0))
		if tid > 0:
			var rep: float = clampf(float(rep_of.call(tid)), 0.0, 100.0)
			bits.append("%s's standing: %d (%s)" % [
				String(r.get("target_name", "target")), int(rep),
				_rep_word(rep)])
	return " · ".join(bits)


## One-word reputation read for the meta line (mirrors
## SimHearsay.rep_label's bands).
static func _rep_word(v: float) -> String:
	if v >= 80.0:
		return "beloved"
	if v >= 60.0:
		return "liked"
	if v >= 40.0:
		return "known"
	if v >= 20.0:
		return "shady"
	return "despised"


static func _rumor_card(r: Dictionary, rep_of: Callable,
		on_investigate: Callable, war_of: Callable = Callable(),
		name_of: Callable = Callable()) -> PanelContainer:
	var text: String = String(r.get("text", "")).strip_edges()
	if text == "":
		text = "(a whisper too faint to make out)"
	var heat: float = clampf(float(r.get("heat", 0.0)), 0.0, 1.0)
	var tint: Color = heat_tint(heat)
	var debunked: bool = bool(r.get("debunked", false))
	var verified: bool = bool(r.get("verified", false))
	var card := PanelContainer.new()
	# Full-bleed cards: claim the list width explicitly (matches the
	# codebase convention; BoxContainer stretches the cross axis anyway).
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var csb := StyleBoxFlat.new()
	csb.bg_color = PH_SURFACE
	csb.set_corner_radius_all(16)
	# Colored top border marks the heat — mirrors the diplomacy cards'
	# faction-colored top border.
	csb.border_width_top = 5
	csb.border_color = tint
	csb.content_margin_left = 16.0
	csb.content_margin_right = 16.0
	csb.content_margin_top = 14.0
	csb.content_margin_bottom = 14.0
	card.add_theme_stylebox_override("panel", csb)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	# Title row: heat tag left, kind tag right.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 10)
	box.add_child(title_row)
	var heat_lbl := Label.new()
	heat_lbl.text = heat_tag(heat)
	heat_lbl.add_theme_font_size_override("font_size", FONT_SM)
	heat_lbl.add_theme_color_override("font_color", tint)
	title_row.add_child(heat_lbl)
	# Investigation status tag (debunked / confirmed) sits beside heat.
	if debunked:
		var dtag := Label.new()
		dtag.text = "DEBUNKED"
		dtag.add_theme_font_size_override("font_size", FONT_SM)
		dtag.add_theme_color_override("font_color", PH_BAD)
		title_row.add_child(dtag)
	elif verified:
		var vtag := Label.new()
		vtag.text = "CONFIRMED"
		vtag.add_theme_font_size_override("font_size", FONT_SM)
		vtag.add_theme_color_override("font_color", PH_GOOD)
		title_row.add_child(vtag)
	var kind_lbl := Label.new()
	var rkind := String(r.get("kind", "misc"))
	if rkind == "war":
		kind_lbl.text = war_tag(String(r.get("subject", "")), war_of)
	else:
		kind_lbl.text = kind_label(rkind)
	kind_lbl.add_theme_font_size_override("font_size", FONT_SM)
	kind_lbl.add_theme_color_override("font_color", PH_TEXT_DIM)
	kind_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	title_row.add_child(kind_lbl)
	# Rumor text.
	var body := Label.new()
	body.text = text
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("font_size", FONT_MD)
	body.add_theme_color_override("font_color",
		PH_TEXT_DIM if debunked else PH_TEXT)
	box.add_child(body)
	# Meta line.
	var meta := Label.new()
	meta.text = meta_line(r, rep_of, name_of)
	meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_theme_font_size_override("font_size", FONT_SM)
	meta.add_theme_color_override("font_color", PH_TEXT_DIM)
	box.add_child(meta)
	# Investigate button — the crown asks around (DM flow). Debunked
	# rumors are buried; there's nothing left to ask about.
	if not debunked and on_investigate.is_valid():
		var rid: int = int(r.get("id", 0))
		var btn := Button.new()
		btn.text = "Investigate"
		btn.custom_minimum_size = Vector2(0, 72)
		btn.add_theme_font_size_override("font_size", FONT_SM)
		btn.pressed.connect(func() -> void: on_investigate.call(rid))
		box.add_child(btn)
	# Jeremy 2026-10-07 (iPhone bugfix): the Rumors list would not scroll.
	# Every card is a default-STOP PanelContainer — with 24 cards covering
	# the whole viewport, no drag ever reached the ScrollContainer. Display
	# nodes go IGNORE so drags pass through (same convention as the
	# Settings rows' PASS and the chat bubbles' _ignore_mouse); the
	# Investigate Button subtree keeps STOP so it stays tappable.
	_scroll_safe(card)
	return card


## Recursively set MOUSE_FILTER_IGNORE on a card's display subtree so
## touch drags reach the enclosing ScrollContainer. Button subtrees are
## skipped wholesale — a button must keep STOP to stay tappable.
static func _scroll_safe(n: Node) -> void:
	if n is Button:
		return
	if n is Control:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in n.get_children():
		_scroll_safe(c)


## Builds the full Rumors screen content into box. rumors is the array from
## SimHearsay.live_rumors() (already heat-sorted, hottest first).
## rep_of: Callable(unit_id) -> float — injected reputation lookup (cold lane).
## on_investigate: Callable(rumor_id) -> void — injected investigate action.
## war_of: Callable(faction_key) -> bool — live war check gating the WAR tag.
## name_of: Callable(unit_id) -> String — names the rumor's source.
## Jeremy 2026-10-06: identical rumor texts collapse to one card (the seed
## path only dedups when a subject is set, so subjectless gossip repeated).
static func build(box: VBoxContainer, rumors: Array,
		rep_of: Callable = Callable(),
		on_investigate: Callable = Callable(),
		war_of: Callable = Callable(),
		name_of: Callable = Callable()) -> void:
	box.add_theme_constant_override("separation", 14)
	var summary := Label.new()
	# Dedup first so the count the player reads matches the cards shown.
	var unique: Array = []
	var seen: Dictionary = {}
	for r in rumors:
		if not (r is Dictionary):
			continue
		var key := String(r.get("text", "")).strip_edges().to_lower()
		if key != "" and seen.has(key):
			continue
		seen[key] = true
		unique.append(r)
	if unique.is_empty():
		summary.text = "Quiet streets. The gnomes have nothing to whisper about… for now."
	else:
		var n: int = unique.size()
		if n == 1:
			summary.text = "One whisper on the wind."
		else:
			summary.text = "%d whispers on the wind — hottest first." % n
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_font_size_override("font_size", FONT_MD)
	summary.add_theme_color_override("font_color", PH_TEXT_DIM)
	box.add_child(summary)
	for r in unique:
		box.add_child(_rumor_card(r, rep_of, on_investigate, war_of,
			name_of))
