class_name DebugOverlay
extends CanvasLayer
## Cursing Gnomes — debug overlay (HTML parity: the #cg-debug div).
##
## Shows FPS, frame count, tick timings, entity counts, and a spawn-history
## trail (units/buildings over the last 30s — the HTML kept 15 samples every
## 2s to catch post-spawn wipes).
##
## Enable precedence (HTML DEBUG08 parity):
##   1. ?debug=1 URL param forces ON, ?debug=0 forces OFF (web only, read
##      via JavaScriptBridge with graceful fallback elsewhere).
##   2. Otherwise the Settings checkbox ("debug_overlay", default OFF).
##
## Tick timings: sim code calls DebugOverlay.note("name", ms) around the
## sections it wants measured (see HOOKS). The overlay keeps a 1s rolling
## average per name and prints the slowest 8, like the HTML's Slowest ticks.


var _label: RichTextLabel
var _game: GameState = null
var _enabled := false
var _acc := 0.0
var _hist: Array = []  # [{t, u, b}] every 2s, cap 15
var _hist_acc := 0.0
var _spawn_err := ""

static var _ticks: Dictionary = {}  # name -> {sum, n}
static var _frame := 0


## Tick timing probe. Call around measured sections:
##   var t0 := Time.get_ticks_usec()
##   ... work ...
##   DebugOverlay.note("mind", (Time.get_ticks_usec() - t0) / 1000.0)
static func note(tick_name: String, ms: float) -> void:
	var e: Dictionary = _ticks.get(tick_name, {"sum": 0.0, "n": 0})
	e["sum"] = float(e["sum"]) + ms
	e["n"] = int(e["n"]) + 1
	_ticks[tick_name] = e


static func clear_ticks() -> void:
	_ticks.clear()
	_frame = 0


## ?debug=1 / ?debug=0 from the URL query string (web only).
## Returns 1 = force on, 0 = force off, -1 = no param (fall back to setting).
static func url_debug_param() -> int:
	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		var bridge = Engine.get_singleton("JavaScriptBridge")
		var q := ""
		var v = bridge.eval(
			"(typeof location !== 'undefined') ? location.search : ''")
		if v != null:
			q = str(v)
		if q.match("*[?&]debug=1*"):
			return 1
		if q.match("*[?&]debug=0*"):
			return 0
	return -1


func _ready() -> void:
	layer = 200
	_label = RichTextLabel.new()
	_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_label.offset_left = -360
	_label.offset_right = -10
	_label.offset_top = 10
	_label.offset_bottom = 400
	_label.add_theme_font_size_override("normal_font_size", 20)
	_label.add_theme_color_override("default_color", Color(0.0, 1.0, 0.0))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.85)
	sb.set_corner_radius_all(6)
	_label.add_theme_stylebox_override("normal", sb)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	_resolve_enabled()
	_label.visible = _enabled


## Binds the live game for entity counts.
func bind_game(game: GameState) -> void:
	_game = game


## Re-evaluate the enable state (URL param wins, else the settings flag).
func _resolve_enabled() -> void:
	var param := url_debug_param()
	if param == 1:
		_enabled = true
		return
	if param == 0:
		_enabled = false
		return
	_enabled = false
	if get_tree() != null and get_tree().has_meta("cg_debug_overlay"):
		_enabled = bool(get_tree().get_meta("cg_debug_overlay"))


func set_enabled(on: bool) -> void:
	_enabled = on
	if _label != null:
		_label.visible = on


func is_enabled() -> bool:
	return _enabled


## Extra one-line diagnostic surfaced in the overlay (e.g. spawn errors).
func set_spawn_error(text: String) -> void:
	_spawn_err = text


func _process(delta: float) -> void:
	_frame += 1
	_acc += delta
	_hist_acc += delta
	if _hist_acc >= 2.0:
		_hist_acc = 0.0
		var u := -1
		var b := -1
		if _game != null:
			u = _game.units.size()
			b = _game.buildings.size()
		_hist.append({"t": int(Time.get_ticks_msec() / 1000), "u": u, "b": b})
		while _hist.size() > 15:
			_hist.pop_front()
	if not _enabled or _acc < 0.5:
		return
	_acc = 0.0
	_render()


func _render() -> void:
	var lines: Array[String] = []
	lines.append("DEBUG MODE (?debug=1)")
	lines.append("FPS: %.1f | Frame: %d" % [Engine.get_frames_per_second(),
		_frame])
	if _game != null:
		lines.append("Day %d (%s)" % [_game.day_number,
			"Night" if _game.is_night else "Day"])
		var alive := 0
		for u in _game.units:
			if u.get("alive", false):
				alive += 1
		lines.append("Units: %d (%d alive) Bld: %d Towns: %d" % [
			_game.units.size(), alive, _game.buildings.size(),
			_game.towns.size()])
		var hist := []
		for h in _hist:
			hist.append("%ds:U%d/B%d" % [h["t"], h["u"], h["b"]])
		lines.append("SpawnHist: " + (" ".join(hist) if not hist.is_empty()
			else "(collecting)"))
	if _spawn_err != "":
		lines.append("SPAWN-ERR: " + _spawn_err.left(200))
	# Slowest ticks (1s rolling averages).
	var rows: Array = []
	for k in _ticks.keys():
		var e: Dictionary = _ticks[k]
		var n: int = int(e["n"])
		if n > 0:
			rows.append([k, float(e["sum"]) / float(n)])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	lines.append("Slowest ticks:")
	for r in rows.slice(0, 8):
		lines.append("  %s: %.2fms" % [r[0], r[1]])
	_ticks.clear()
	_label.text = "\n".join(lines)
