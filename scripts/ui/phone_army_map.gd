class_name PhoneArmyMap
extends Control
## Live mini-map / deployment map for the phone Army app (Jeremy 2026-10-06,
## Lane 5 expansion).
##
## A custom-drawn Control (no textures, no glyphs — nothing to go tofu, no
## white squares): faction-colored dots for troops, diamonds for halls,
## thin lines for units with march orders. Repaints itself on a short timer
## while visible, so the war-room view is live without any sim changes.
##
## Modes:
##   "view"  — war-room overview; taps are ignored (read-only).
##   "rally" — deployment map; tapping a troop dot emits unit_tapped
##             (toggle selection), tapping anywhere else emits map_tapped
##             with the world position (issue a rally order).
##
## faction = "" shows every active faction; otherwise only that faction's
## forces are drawn and tappable.
##
## Safe areas: this control only ever lives inside a phone scroll screen —
## it never positions itself absolutely and keeps a margin from the
## control edges when drawing, so the Dynamic Island, home bar and
## rounded corners can't clip it.

signal map_tapped(world_pos: Vector2)
signal unit_tapped(unit_id: int)

const FACTION_COLORS := {
	"humans": Color(0.30, 0.50, 0.90),
	"elves": Color(0.30, 0.70, 0.40),
	"gnomes": Color(0.90, 0.60, 0.20),
	"ogres": Color(0.70, 0.35, 0.20),
	"undead": Color(0.60, 0.40, 0.85),
}
const MAP_BG := Color(0.045, 0.055, 0.075)
const MAP_EDGE := Color(1, 1, 1, 0.10)
const UNIT_TAP_RADIUS := 22.0  # map-px hit radius for troop dots

var _gs: GameState = null
var _mode := "view"
var _faction := ""
var _bounds := Rect2(-600, -600, 1200, 1200)
var _selected := {}  # unit id -> true (rally selection highlight)
var _army: SimArmy = null


func setup(game: GameState, mode: String, faction: String) -> void:
	_gs = game
	_mode = mode
	_faction = faction
	if _gs != null and _gs.has_meta("army"):
		_army = _gs.get_meta("army")
	mouse_filter = Control.MOUSE_FILTER_STOP


func set_selected(ids: Array) -> void:
	_selected.clear()
	for i in ids:
		_selected[int(i)] = true
	queue_redraw()


func _ready() -> void:
	var t := Timer.new()
	t.wait_time = 0.6
	t.timeout.connect(_refresh)
	add_child(t)
	# In production _ready always means inside the tree; the guard keeps
	# headless tests (which drive _ready manually) error-free.
	if is_inside_tree():
		t.start()
	_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _refresh() -> void:
	_compute_bounds()
	queue_redraw()


## --- coordinate mapping -------------------------------------------------------

func _compute_bounds() -> void:
	if _gs == null:
		return
	var have := false
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var p: Vector2 = u.get("position", Vector2.ZERO)
		minp = minp.min(p)
		maxp = maxp.max(p)
		have = true
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		var p2: Vector2 = b.get("position", Vector2.ZERO)
		minp = minp.min(p2)
		maxp = maxp.max(p2)
		have = true
	if not have:
		_bounds = Rect2(-600, -600, 1200, 1200)
		return
	var pad := 220.0
	minp -= Vector2(pad, pad)
	maxp += Vector2(pad, pad)
	var span: Vector2 = maxp - minp
	if span.x < 900.0:
		var cx: float = (minp.x + maxp.x) * 0.5
		minp.x = cx - 450.0
		maxp.x = cx + 450.0
	if span.y < 900.0:
		var cy: float = (minp.y + maxp.y) * 0.5
		minp.y = cy - 450.0
		maxp.y = cy + 450.0
	_bounds = Rect2(minp, maxp - minp)


func _map_rect() -> Rect2:
	# Keep a margin inside the control so dots never touch the edges
	# (rounded phone corners + safe areas).
	var m := 14.0
	return Rect2(m, m, maxf(4.0, size.x - m * 2.0), maxf(4.0, size.y - m * 2.0))


func _world_to_map(p: Vector2) -> Vector2:
	var r := _map_rect()
	var sx: float = r.size.x / maxf(1.0, _bounds.size.x)
	var sy: float = r.size.y / maxf(1.0, _bounds.size.y)
	var s: float = minf(sx, sy)
	var off := Vector2(
		r.position.x + (r.size.x - _bounds.size.x * s) * 0.5,
		r.position.y + (r.size.y - _bounds.size.y * s) * 0.5)
	return off + (p - _bounds.position) * s


func _map_to_world(p: Vector2) -> Vector2:
	var r := _map_rect()
	var sx: float = r.size.x / maxf(1.0, _bounds.size.x)
	var sy: float = r.size.y / maxf(1.0, _bounds.size.y)
	var s: float = minf(sx, sy)
	var off := Vector2(
		r.position.x + (r.size.x - _bounds.size.x * s) * 0.5,
		r.position.y + (r.size.y - _bounds.size.y * s) * 0.5)
	var w: Vector2 = _bounds.position + (p - off) / maxf(0.001, s)
	w.x = clampf(w.x, _bounds.position.x, _bounds.end.x)
	w.y = clampf(w.y, _bounds.position.y, _bounds.end.y)
	return w


## --- drawing ------------------------------------------------------------------

func _draw() -> void:
	var r := _map_rect()
	var sb := StyleBoxFlat.new()
	sb.bg_color = MAP_BG
	sb.set_corner_radius_all(18)
	sb.border_color = MAP_EDGE
	sb.set_border_width_all(2)
	draw_style_box(sb, Rect2(Vector2.ZERO, size))
	if _gs == null:
		return
	_draw_halls()
	_draw_orders()
	_draw_units()


func _faction_color(f: String) -> Color:
	return FACTION_COLORS.get(f, Color(0.75, 0.75, 0.75))


func _visible_faction(f: String) -> bool:
	return _faction == "" or f == _faction


func _draw_halls() -> void:
	if _gs == null:
		return
	for b: Dictionary in _gs.buildings:
		if not b.get("alive", false):
			continue
		var bt := String(b.get("type", ""))
		if bt != "hall" and bt != "town_hall":
			continue
		var f := String(b.get("faction", ""))
		if not _visible_faction(f):
			continue
		var c := _world_to_map(b.get("position", Vector2.ZERO))
		var s := 11.0
		var col := _faction_color(f)
		draw_colored_polygon(
			[c + Vector2(0, -s), c + Vector2(s, 0),
				c + Vector2(0, s), c + Vector2(-s, 0)], col)
		draw_arc(c, s + 5.0, 0.0, TAU, 24, col.darkened(0.2), 1.5)


func _draw_orders() -> void:
	# Thin march lines for units with a move_target (rally/deployment
	# orders, monastery marches, retreats) — the war-room "current orders".
	if _gs == null:
		return
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		var f := String(u.get("faction", ""))
		if not _visible_faction(f):
			continue
		if not u.has("move_target"):
			continue
		var a := _world_to_map(u.get("position", Vector2.ZERO))
		var b2 := _world_to_map(u["move_target"])
		var col := _faction_color(f)
		col.a = 0.55
		draw_line(a, b2, col, 2.0)
		draw_circle(b2, 4.0, col)


func _draw_units() -> void:
	if _gs == null:
		return
	for u: Dictionary in _gs.units:
		if not u.get("alive", false):
			continue
		var f := String(u.get("faction", ""))
		if not _visible_faction(f):
			continue
		var c := _world_to_map(u.get("position", Vector2.ZERO))
		var col := _faction_color(f)
		var uid := int(u.get("id", -1))
		if bool(u.get("downed", false)):
			col = col.darkened(0.55)
		var rad := 4.5
		if SimCombat.is_fighter(u):
			rad = 6.0
		if bool(u.get("warlord", false)):
			rad = 9.0
		draw_circle(c, rad, col)
		if bool(u.get("warlord", false)):
			draw_arc(c, rad + 3.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
		if _selected.has(uid):
			draw_arc(c, rad + 6.0, 0.0, TAU, 24,
				Color(1.0, 0.84, 0.35), 3.0)


## --- input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if _mode != "rally":
		return
	var local := Vector2.ZERO
	var tapped := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			local = mb.position
			tapped = true
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			local = st.position
			tapped = true
	if not tapped:
		return
	accept_event()
	# Troop dot first (selection toggle), otherwise a rally point.
	var uid := _unit_at(local)
	if uid >= 0:
		unit_tapped.emit(uid)
	else:
		map_tapped.emit(_map_to_world(local))


func _unit_at(local: Vector2) -> int:
	if _gs == null:
		return -1
	var best := -1
	var best_d := UNIT_TAP_RADIUS
	for u: Dictionary in _gs.units:
		if not u.get("alive", false) or bool(u.get("downed", false)):
			continue
		var f := String(u.get("faction", ""))
		if not _visible_faction(f):
			continue
		if not SimCombat.is_fighter(u):
			continue
		var c := _world_to_map(u.get("position", Vector2.ZERO))
		var d: float = c.distance_to(local)
		if d < best_d:
			best_d = d
			best = int(u.get("id", -1))
	return best
