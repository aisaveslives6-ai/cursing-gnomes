class_name TraderPanel
extends CanvasLayer
## Cursing Gnomes — Captain Funky Pants trade panel (launch-readiness gate 1:
## systems playable & functional).
##
## HTML port of #funky-trade-panel (fix79:1546, openFunkyTrade /
## refreshFunkyTradeUI / funkyTrade / funkyDeposit at fix79:16286-16370):
## stock line, the 6 verbatim caravan deals, the 3 verbatim "deposit excess"
## buttons, and Funky's "Funky rates only!" quote. Result messages are the
## HTML systemMsg strings verbatim (emoji stripped — in-game UI uses the
## pixel-art resource icons + text labels, never emoji/glyphs; emoji render
## as tofu boxes on iPhone, Jeremy 2026-10-03).
##
## Safe-area aware: the modal is inset by the real OS safe area
## (DisplayServer.get_display_safe_area(), the hud.gd pattern), so it never
## sits under the Dynamic Island, home bar, or rounded corners — and the
## centered layout is identical across portrait / landscape / PC 16:9 / 4:3.
##
## Owned by TraderLayer (scripts/world/trader_layer.gd): the layer opens the
## panel when the player taps the caravan and closes it when the caravan
## leaves (trader_left). The dim layer blocks world taps while open and —
## per Jeremy's 2026-10-05 tap-outside-to-close rule (the hud.gd scrim idiom)
## — dismisses the panel when tapped, so a dead dim never swallows a touch.


## HTML-verbatim caravan deals (fix79 #funky-trade-panel buttons).
const DEAL_DEFS: Array = [
	{"give": "gold", "give_amt": 50.0, "take": "wood", "take_amt": 80.0},
	{"give": "wood", "give_amt": 60.0, "take": "gold", "take_amt": 40.0},
	{"give": "gold", "give_amt": 40.0, "take": "food", "take_amt": 50.0},
	{"give": "food", "give_amt": 30.0, "take": "seeds", "take_amt": 15.0},
	{"give": "gold", "give_amt": 80.0, "take": "oil", "take_amt": 25.0},
	{"give": "oil", "give_amt": 20.0, "take": "gold", "take_amt": 70.0},
]
## HTML-verbatim "deposit excess" buttons.
const DEPOSIT_DEFS: Array = [
	{"res": "wood", "amt": 50.0},
	{"res": "gold", "amt": 50.0},
	{"res": "food", "amt": 30.0},
]
## Stock line order (HTML refreshFunkyTradeUI verbatim).
const STOCK_ORDER: Array[String] = ["gold", "wood", "food", "seeds", "oil"]

## HTML-verbatim palette (#funky-trade-panel).
const PANEL_BG := Color(0.078, 0.047, 0.11, 0.96)   # rgba(20,12,28,0.96)
const PANEL_BORDER := Color(0.914, 0.118, 0.388)    # #e91e63
const TEXT_PINK := Color(0.988, 0.894, 0.925)       # #fce4ec
const ACCENT_PINK := Color(1.0, 0.502, 0.671)       # #ff80ab
const STOCK_PINK := Color(0.973, 0.733, 0.816)      # #f8bbd0
const BTN_BG := Color(0.29, 0.125, 0.25, 1.0)       # #4a2040


var _game = null  ## GameState (untyped: ui <-> sim cycle)

var _root: Control = null
var _margin: MarginContainer = null
var _scroll: ScrollContainer = null
var _vb: VBoxContainer = null
var _stock_row: HBoxContainer = null
var _stock_labels: Dictionary = {}  ## res -> Label
var _msg: Label = null
var _opened := false


func _init() -> void:
	layer = 10
	visible = false


## Builds the UI once. Safe to call headless (viewport guards inside).
func setup(game) -> void:
	_game = game
	_build()
	_refit()
	var vp := get_viewport()
	if vp != null:
		vp.size_changed.connect(_refit)


func is_open() -> bool:
	return _opened


## Shows the panel and refreshes the stock line. No-op if the caravan is
## gone (HTML openFunkyTrade: "Funky Pants is not in the region right now.").
func open() -> void:
	if _game == null or _game.get("industry") == null:
		return
	if not bool(_game.industry.funky_on_map):
		return
	_opened = true
	visible = true
	refresh()
	_refit()


func close() -> void:
	_opened = false
	visible = false


## Rebuilds the stock line from live caravan stock.
func refresh() -> void:
	if _game == null or _game.get("industry") == null:
		return
	var stock: Dictionary = _game.industry.funky_stock
	for res in STOCK_ORDER:
		var l: Label = _stock_labels.get(res, null)
		if l != null and is_instance_valid(l):
			l.text = "%d" % int(floor(float(stock.get(res, 0.0))))
	_set_msg("")


## Attempts deal i (HTML funkyTrade). Returns the message shown, so tests
## can drive the economy without a viewport.
func attempt_deal(i: int) -> String:
	if i < 0 or i >= DEAL_DEFS.size():
		return ""
	var d: Dictionary = DEAL_DEFS[i]
	var msg := _check_trade(d["give"], d["take"], float(d["give_amt"]),
		float(d["take_amt"]))
	if msg == "":
		msg = "Funky Pants: \"Pleasure doin' business!\""
	_set_msg(msg)
	refresh_keep_msg()
	return msg


## Attempts deposit i (HTML funkyDeposit). Returns the message shown.
func attempt_deposit(i: int) -> String:
	if i < 0 or i >= DEPOSIT_DEFS.size():
		return ""
	var d: Dictionary = DEPOSIT_DEFS[i]
	var res := String(d["res"])
	var amt := float(d["amt"])
	var msg := ""
	if _game == null or _game.get("industry") == null \
			or not bool(_game.industry.funky_on_map):
		msg = "Caravan is gone."
	elif _game.resources.get_amount(_game.player_faction, res) < amt:
		msg = "Not enough %s" % res
	elif _game.industry.deposit(_game.player_faction, res, amt):
		msg = "Deposited %d %s with Funky Pants" % [int(amt), res]
	else:
		msg = "Caravan is gone."
	_set_msg(msg)
	refresh_keep_msg()
	return msg


## Shared pre-flight for deals; mirrors SimIndustry.trade()'s guards so the
## panel can name the failure reason (HTML systemMsg strings, verbatim).
## Returns "" when the trade may proceed.
func _check_trade(give: String, take: String, give_amt: float,
		take_amt: float) -> String:
	if _game == null or _game.get("industry") == null \
			or not bool(_game.industry.funky_on_map):
		return "Caravan is gone."
	var f: String = _game.player_faction
	if _game.resources.get_amount(f, give) < give_amt:
		return "Not enough %s." % give
	if float(_game.industry.funky_stock.get(take, 0.0)) < take_amt:
		return "Funky is out of %s." % take
	var room: float = _game.resources.get_cap(f, take) \
		- _game.resources.get_amount(f, take)
	if room < take_amt:
		return "No warehouse space for %s!" % take
	if _game.industry.trade(f, give, take, give_amt, take_amt):
		return ""
	return "Caravan is gone."


func _set_msg(t: String) -> void:
	if _msg != null and is_instance_valid(_msg):
		_msg.text = t


func refresh_keep_msg() -> void:
	var keep := ""
	if _msg != null and is_instance_valid(_msg):
		keep = _msg.text
	refresh()
	_set_msg(keep)


## --- UI construction --------------------------------------------------------


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := Button.new()
	dim.text = ""
	# Jeremy 2026-10-05 tap-outside-to-close (the hud.gd scrim idiom):
	# the dim layer is a full-screen button styled as the same 0.45 black,
	# so a tap anywhere outside the trade panel dismisses it instead of
	# dying on a dead dim. Panel visuals are byte-identical.
	var dimsb := StyleBoxFlat.new()
	dimsb.bg_color = Color(0, 0, 0, 0.45)
	dim.add_theme_stylebox_override("normal", dimsb)
	dim.add_theme_stylebox_override("hover", dimsb)
	dim.add_theme_stylebox_override("pressed", dimsb)
	dim.add_theme_stylebox_override("focus", dimsb)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.pressed.connect(close)
	_root.add_child(dim)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_margin)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_border_width_all(3)
	sb.border_color = PANEL_BORDER
	sb.set_corner_radius_all(14)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	# Jeremy 2026-10-10 (menu-scroll audit): the deal/deposit list is ~700px
	# tall — on landscape phones it overflowed the viewport with no way to
	# reach the lower buttons. The content now lives in a ScrollContainer
	# capped to the safe-area viewport height; drag scrolls, taps still fire
	# buttons (default ScrollContainer gesture handling).
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_scroll)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(vb)
	_vb = vb

	# Stock line (HTML #funky-stock-line, icons + counts, no emoji).
	# Jeremy 2026-10-11 (menu scroll audit): every display-only control in
	# the scroll is MOUSE_FILTER_IGNORE so drags reach the ScrollContainer;
	# Buttons keep STOP so taps still fire.
	_stock_row = HBoxContainer.new()
	_stock_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stock_row.add_theme_constant_override("separation", 10)
	vb.add_child(_stock_row)
	for res in STOCK_ORDER:
		var cell := HBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_theme_constant_override("separation", 4)
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = Art.resource_icon(res)
		icon.custom_minimum_size = Vector2(22, 22)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cell.add_child(icon)
		var l := Label.new()
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", STOCK_PINK)
		l.text = "—"
		cell.add_child(l)
		_stock_row.add_child(cell)
		_stock_labels[res] = l

	# Title row: name + Back button (apps use a back button, never an X).
	var title_row := HBoxContainer.new()
	title_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_theme_constant_override("separation", 8)
	vb.add_child(title_row)
	var title := Label.new()
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "Captain Funky Pants"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ACCENT_PINK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(72, 44)
	_style_button(back)
	back.pressed.connect(close)
	title_row.add_child(back)

	var quote := Label.new()
	quote.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quote.text = "\"What do you want to trade, friend? Funky rates only!\""
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.add_theme_font_size_override("font_size", 14)
	quote.add_theme_color_override("font_color",
		Color(TEXT_PINK.r, TEXT_PINK.g, TEXT_PINK.b, 0.9))
	vb.add_child(quote)

	for i in DEAL_DEFS.size():
		var d: Dictionary = DEAL_DEFS[i]
		var b := Button.new()
		b.text = "%d %s > %d %s" % [int(d["give_amt"]),
			_res_name(String(d["give"])), int(d["take_amt"]),
			_res_name(String(d["take"]))]
		b.icon = Art.resource_icon(String(d["take"]))
		b.expand_icon = false
		b.custom_minimum_size = Vector2(0, 48)
		b.add_theme_font_size_override("font_size", 16)
		_style_button(b)
		var idx := i
		b.pressed.connect(func() -> void: attempt_deal(idx))
		vb.add_child(b)

	var dep_head := Label.new()
	dep_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dep_head.text = "Deposit excess"
	dep_head.add_theme_font_size_override("font_size", 15)
	dep_head.add_theme_color_override("font_color", ACCENT_PINK)
	vb.add_child(dep_head)

	for i in DEPOSIT_DEFS.size():
		var d: Dictionary = DEPOSIT_DEFS[i]
		var b := Button.new()
		b.text = "Deposit %d %s" % [int(d["amt"]),
			_res_name(String(d["res"]))]
		b.icon = Art.resource_icon(String(d["res"]))
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_font_size_override("font_size", 15)
		_style_button(b)
		var idx := i
		b.pressed.connect(func() -> void: attempt_deposit(idx))
		vb.add_child(b)

	_msg = Label.new()
	_msg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.add_theme_font_size_override("font_size", 14)
	_msg.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	_msg.custom_minimum_size = Vector2(0, 40)
	vb.add_child(_msg)


func _style_button(b: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BTN_BG
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	b.add_theme_stylebox_override("normal", sb)
	var sbh := sb.duplicate() as StyleBoxFlat
	sbh.bg_color = BTN_BG.lightened(0.15)
	b.add_theme_stylebox_override("hover", sbh)
	var sbp := sb.duplicate() as StyleBoxFlat
	sbp.bg_color = BTN_BG.darkened(0.15)
	b.add_theme_stylebox_override("pressed", sbp)
	b.add_theme_color_override("font_color", TEXT_PINK)


func _res_name(res: String) -> String:
	return res.capitalize()


## --- safe area ---------------------------------------------------------------


## iPhone safe-area insets as Vector4(top, bottom, left, right) — the hud.gd
## pattern: real OS values when available, desktop gets zero, conservative
## fallback otherwise. Headless (no viewport) returns zero.
func _safe_insets() -> Vector4:
	var vp := get_viewport()
	if vp == null:
		return Vector4.ZERO
	var vsz := vp.get_visible_rect().size
	var is_desktop := not DisplayServer.is_touchscreen_available() \
		and vsz.x >= 1024.0 and vsz.y >= 600.0
	if is_desktop:
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
	if vsz.x >= vsz.y:
		return Vector4(20.0, 60.0, 120.0, 120.0)
	return Vector4(220.0, 120.0, 20.0, 20.0)


func _refit() -> void:
	if _margin == null or not is_instance_valid(_margin):
		return
	var ins := _safe_insets()
	_margin.add_theme_constant_override("margin_top", int(ins.x))
	_margin.add_theme_constant_override("margin_bottom", int(ins.y))
	_margin.add_theme_constant_override("margin_left", int(ins.z))
	_margin.add_theme_constant_override("margin_right", int(ins.w))
	# Jeremy 2026-10-10 (menu-scroll audit): cap the scroll height to the
	# safe-area viewport so the panel never grows past the screen edges.
	# Content shorter than the cap keeps the panel tight; taller content
	# scrolls inside.
	var vp := get_viewport()
	if vp != null and _scroll != null and is_instance_valid(_scroll) \
			and _vb != null and is_instance_valid(_vb):
		var vsz := vp.get_visible_rect().size
		var cap := maxf(220.0, vsz.y - ins.x - ins.y - 48.0)
		var need := _vb.get_combined_minimum_size().y
		if need <= 0.0:
			need = cap
		_scroll.custom_minimum_size = Vector2(300.0, minf(need, cap))
