class_name InteriorView
extends Node2D
## Cursing Gnomes — Stardew-style interior dollhouse overlay (Milestone 6).
##
## Tap a building -> open() renders its floor plan as a dollhouse room:
## wood plank floor, furniture sprites (real art for every kind — no
## colored-rect placeholders), and the NPCs currently inside as their real
## chibi unit sprites with idle-life bounce and ground shadows.
##
## Arrange mode: tap a furniture piece to select it (white ring), drag to
## move it. Moves go through SimInteriors.move_furniture so they persist.
##
## The parent (world.gd / HUD) owns placement: add as a child, call open()
## with the building record, the SimInteriors instance, and the GameState.
## close() frees everything. Pure view code — all state lives in sim.
##
## 60fps: piece counts are small (<40); sprites are cached in Art.


## Emitted when the player taps the exit affordance.
signal exit_requested
## Emitted when arrange mode moves a piece (piece_id).
signal furniture_moved(piece_id: String)


const FLOOR_COLOR := Color(0.42, 0.30, 0.18)
const WALL_COLOR := Color(0.30, 0.21, 0.13)
const ROOM_LINE := Color(0.55, 0.42, 0.28)
## Dollhouse occupant target height (design px) — reads against furniture.
const OCCUPANT_H := 120.0

var _sim: SimInteriors = null
var _gs: GameState = null
var _building: Dictionary = {}
var _arrange: bool = false
var _selected: String = ""
var _dragging: bool = false
var _sprites: Dictionary = {}  # piece_id -> Node2D
var _occupant_nodes: Array[Node2D] = []
var _occupant_sprites: Array[Sprite2D] = []
var _occupant_base_scale: Array[float] = []
var _occupant_phase: Array[float] = []
var _bob_t := 0.0


func is_open() -> bool:
	return not _building.is_empty()


func building_id() -> int:
	return int(_building.get("id", 0)) if is_open() else 0


func set_arrange(enabled: bool) -> void:
	_arrange = enabled
	_selected = ""
	queue_redraw()


func is_arrange() -> bool:
	return _arrange


## Opens the dollhouse for a building. Returns false when it can't be
## entered (SimInteriors.can_enter).
func open(building: Dictionary, sim: SimInteriors, gs: GameState) -> bool:
	if not SimInteriors.can_enter(building):
		return false
	close()
	_sim = sim
	_gs = gs
	_building = building
	_rebuild()
	visible = true
	queue_redraw()
	return true


func close() -> void:
	_building = {}
	_sim = null
	_gs = null
	_arrange = false
	_selected = ""
	_dragging = false
	for c: Node in get_children():
		c.queue_free()
	_sprites.clear()
	_occupant_nodes.clear()
	_occupant_sprites.clear()
	_occupant_base_scale.clear()
	_occupant_phase.clear()
	_bob_t = 0.0
	visible = false
	exit_requested.emit()


## Rebuilds furniture sprites + occupant markers from sim state.
func refresh() -> void:
	if not is_open():
		return
	_rebuild()
	queue_redraw()


func _rebuild() -> void:
	for c: Node in get_children():
		c.queue_free()
	_sprites.clear()
	_occupant_nodes.clear()
	_occupant_sprites.clear()
	_occupant_base_scale.clear()
	_occupant_phase.clear()
	_bob_t = 0.0
	var faction: String = String(_building.get("faction", "humans"))
	for p: Dictionary in _sim.furniture_of(_building):
		_add_piece(p, faction)
	_add_occupants()


func _add_piece(p: Dictionary, faction: String) -> void:
	var pid: String = String(p.get("id", ""))
	var kind: String = String(p.get("kind", ""))
	var w: float = float(p.get("w", 60.0))
	var h: float = float(p.get("h", 60.0))
	var holder := Node2D.new()
	holder.position = Vector2(float(p.get("x", 0.0)) + w * 0.5,
		float(p.get("y", 0.0)) + h * 0.5)
	add_child(holder)
	var art_key: String = SimInteriors.art_key_for_kind(kind, faction)
	var tex: Texture2D = Art.furniture_texture(art_key)
	if tex != null:
		var spr := Sprite2D.new()
		spr.texture = tex
		var ts: Vector2 = tex.get_size()
		if ts.x > 0.0 and ts.y > 0.0:
			spr.scale = Vector2(w / ts.x, h / ts.y)
		holder.add_child(spr)
	else:
		# Procedural fallback: colored rounded rect per kind.
		var poly := Polygon2D.new()
		var hw: float = w * 0.5
		var hh: float = h * 0.5
		poly.polygon = PackedVector2Array([
			Vector2(-hw, -hh), Vector2(hw, -hh),
			Vector2(hw, hh), Vector2(-hw, hh)])
		poly.color = _fallback_color(kind)
		holder.add_child(poly)
	_sprites[pid] = holder


func _fallback_color(kind: String) -> Color:
	match kind:
		"door":
			return Color(0.35, 0.22, 0.12)
		"window":
			return Color(0.55, 0.75, 0.90)
		"tv":
			return Color(0.10, 0.10, 0.14)
		"divider":
			return Color(0.50, 0.38, 0.25)
		_:
			return Color(0.55, 0.45, 0.32)


func _add_occupants() -> void:
	var occupants: Array = _sim.occupants_of(_building)
	var i: int = 0
	for uid: Variant in occupants:
		var u: Dictionary = _gs.get_unit(int(uid))
		if u.is_empty() or not u.get("alive", false):
			continue
		# Spread occupants across the room so sprites don't stack.
		var holder := Node2D.new()
		holder.position = Vector2(220.0 + float(i % 6) * 200.0,
			760.0 + float(i / 6) * 170.0)
		add_child(holder)
		# Ground shadow so the sprite sits ON the floor, never floating.
		var shadow := Polygon2D.new()
		var spts := PackedVector2Array()
		for a: int in range(16):
			var ang: float = TAU * float(a) / 16.0
			spts.append(Vector2(cos(ang) * 34.0, sin(ang) * 12.0))
		shadow.polygon = spts
		shadow.color = Color(0.0, 0.0, 0.0, 0.28)
		holder.add_child(shadow)
		# Real chibi unit art — the same sprite the overworld renders.
		# Jeremy 2026-10-07: colored dot markers were placeholder-grade.
		var tex: Texture2D = Art.unit_texture(
			String(u.get("faction", "gnomes")),
			String(u.get("job", "worker")),
			int(u.get("id", 0)),
			String(u.get("gender", "")))
		var spr := Sprite2D.new()
		var base_sc := 1.0
		if tex != null:
			spr.texture = tex
			var ts: Vector2 = tex.get_size()
			if ts.y > 0.0:
				base_sc = OCCUPANT_H / ts.y
		spr.scale = Vector2(base_sc, base_sc)
		spr.position = Vector2(0.0, -OCCUPANT_H * 0.5)
		holder.add_child(spr)
		_occupant_nodes.append(holder)
		_occupant_sprites.append(spr)
		_occupant_base_scale.append(base_sc)
		_occupant_phase.append(randf() * TAU)
		i += 1


## Idle-life bob for interior occupants — the same gentle choreography
## language the overworld's AnimationController speaks, so nobody inside
## stands frozen. Cheap: one sin per occupant per frame.
func _process(delta: float) -> void:
	if _occupant_sprites.is_empty():
		return
	_bob_t += delta
	for i: int in range(_occupant_sprites.size()):
		var spr: Sprite2D = _occupant_sprites[i]
		if not is_instance_valid(spr):
			continue
		var ph: float = _occupant_phase[i]
		var base: float = _occupant_base_scale[i]
		spr.position.y = -OCCUPANT_H * 0.5 + sin(_bob_t * 2.4 + ph) * 3.0
		var sq: float = 1.0 + sin(_bob_t * 2.4 + ph + 1.3) * 0.012
		spr.scale = Vector2(base / sq, base * sq)


func _draw() -> void:
	if not is_open():
		return
	var w: float = SimInteriors.ROOM_W
	var h: float = SimInteriors.ROOM_H
	# Floor: wood planks (drawn, no asset cost) over the base color.
	draw_rect(Rect2(0, 0, w, h), FLOOR_COLOR)
	var plank_h := 70.0
	var y := plank_h
	var row := 0
	while y < h:
		draw_line(Vector2(0, y), Vector2(w, y), Color(0.32, 0.22, 0.13), 3.0)
		# Staggered butt joints so the floor reads as laid boards.
		var x := fmod(float(row) * 420.0, w)
		while x < w:
			draw_line(Vector2(x, y - plank_h), Vector2(x, y),
				Color(0.32, 0.22, 0.13), 2.0)
			x += 520.0
		y += plank_h
		row += 1
	# Room divider lines are furniture; draw a border.
	draw_rect(Rect2(0, 0, w, h), WALL_COLOR, false, 14.0)
	# Selection ring in arrange mode.
	if _arrange and _selected != "" and _sprites.has(_selected):
		var n: Node2D = _sprites[_selected]
		draw_arc(n.position, 46.0, 0.0, TAU, 24, Color.WHITE, 5.0)


func _unhandled_input(event: InputEvent) -> void:
	if not is_open() or _sim == null:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		var local: Vector2 = to_local(mb.global_position)
		if mb.pressed:
			_on_tap(local)
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm: InputEventMouseMotion = event
		_on_drag(to_local(mm.global_position))
	elif event is InputEventScreenTouch:
		var st: InputEventScreenTouch = event
		var local_t: Vector2 = to_local(st.position)
		if st.pressed:
			_on_tap(local_t)
		else:
			_dragging = false
	elif event is InputEventScreenDrag and _dragging:
		var sd: InputEventScreenDrag = event
		_on_drag(to_local(sd.position))


func _on_tap(local: Vector2) -> void:
	# Exit affordance: top-right corner of the room.
	if Rect2(SimInteriors.ROOM_W - 130, 10, 120, 64).has_point(local):
		close()
		return
	if not _arrange:
		return
	var pid: String = _piece_at(local)
	_selected = pid
	if pid != "":
		_dragging = true
	queue_redraw()


func _on_drag(local: Vector2) -> void:
	if not _arrange or _selected == "" or not _sprites.has(_selected):
		return
	var n: Node2D = _sprites[_selected]
	n.position = local
	_sim.move_furniture(_building, _selected, local.x - 30.0, local.y - 30.0)
	furniture_moved.emit(_selected)
	queue_redraw()


## Topmost furniture piece under a point (piece centers, 40px radius).
func _piece_at(local: Vector2) -> String:
	var best: String = ""
	var best_d: float = 48.0
	for pid: String in _sprites.keys():
		var n: Node2D = _sprites[pid]
		var d: float = n.position.distance_to(local)
		if d < best_d:
			best_d = d
			best = pid
	return best
