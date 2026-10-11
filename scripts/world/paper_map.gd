class_name PaperMap
extends CanvasLayer
## Cursing Gnomes — paper map / minimap (ported from HTML's drawMinimapTo).
##
## The HTML version shows a parchment-styled paper map of the whole world.
## This port:
##   - Appears when the camera zooms out past a threshold (like HTML)
##   - Parchment background with terrain painted in muted tones
##   - Faction territories/units as colored dots in faction colors
##   - Tap the map to jump the camera there
##   - Toggle button to force show/hide
##
## Pure UI — reads from GameState/MapGen via the world reference.

signal map_tapped(world_pos: Vector2)

## CanvasLayer itself is not a CanvasItem, so all map painting happens in
## this child Node2D (drawn in the layer's screen space).
class MapCanvas:
	extends Node2D
	var paper_map  # PaperMap (untyped: inner class, no cycle)
	func _draw() -> void:
		if paper_map != null:
			paper_map.draw_on(self)

const ZOOM_THRESHOLD := 0.35  # Jeremy 2026-10-04: "should switch to LOD sooner" — was 0.16
const MAP_MARGIN := 24.0      # screen margin around the map

# Parchment palette (HTML's paper map aesthetic)
const PARCHMENT := Color(0.93, 0.85, 0.68)
const PARCHMENT_DARK := Color(0.82, 0.71, 0.52)
const INK := Color(0.25, 0.18, 0.10)

var _game: GameState
var world: Node2D  # the World node, for camera + map data
var _visible_map := false
var _map_opacity := 0.0  # Smooth fade for seamless zoom transition
var _map_rect := Rect2()
var _toggle_btn: Button
var _force_show := false

# Cached terrain image (rebuilt when map changes)
var _terrain_tex: ImageTexture
var _canvas: MapCanvas

## Jeremy 2026-10-05 perf: the map canvas was queue_redraw()'d every frame
## (60 Hz) — rebuilding region clustering + a ~14k-check battle-marker scan
## + hundreds of unit dots and labels each time — even at full zoom-in where
## the map is invisible (alpha 0). Now: no redraws while invisible, visible
## redraws throttled to 5 Hz (HTML's map was a static cache; a far-zoom
## overview does not need 60 Hz), and the canvas node hides when opacity
## bottoms out so the renderer culls it. Fade math is unchanged.
const REDRAW_INTERVAL := 0.2
var _redraw_accum := 0.0


func setup(p_game: GameState, p_world: Node2D) -> void:
	_game = p_game
	world = p_world
	layer = 50  # above HUD, below phone
	_canvas = MapCanvas.new()
	_canvas.paper_map = self
	add_child(_canvas)
	_build_ui()
	_rebuild_terrain()
	set_process(true)


func _build_ui() -> void:
	# No toggle button — Jeremy 2026-10-02: "random weird ass button on the
	# bottom right the original didn't even have." Paper map shows/hides
	# purely via zoom level, like the HTML version.
	pass


func _on_toggle() -> void:
	_force_show = not _force_show


func _rebuild_terrain() -> void:
	# Paint the whole world's terrain at 128x128 (HTML's minimap res),
	# parchment-toned, with height shading: higher ground reads lighter
	# (HTML's CLIFFS82 hill-shading on the paper map).
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	img.fill(PARCHMENT)
	if world != null and world.get("map_data") != null:
		var md: Dictionary = world.get("map_data")
		var terrain: PackedByteArray = md.get("terrain", PackedByteArray())
		var levels: PackedByteArray = md.get("levels", PackedByteArray())
		var size: Vector2i = md.get("size_tiles", Vector2i(128, 128))
		if not terrain.is_empty() and size.x > 0:
			var grass := Color(0.55, 0.62, 0.42)
			var sand := Color(0.80, 0.72, 0.52)
			var water := Color(0.45, 0.58, 0.66)
			var river := Color(0.50, 0.62, 0.68)
			for py in 128:
				for px in 128:
					var tx: int = clampi(px * size.x / 128, 0, size.x - 1)
					var ty: int = clampi(py * size.y / 128, 0, size.y - 1)
					var t: int = terrain[ty * size.x + tx]
					var col := grass
					if t == 1 or t == 4:
						col = water
					elif t == 3:
						col = river
					elif t == 2:
						col = sand
					# Height shading: higher ground reads lighter.
					if not levels.is_empty() and t != 1:
						var lv: int = levels[ty * size.x + tx]
						var m: float = Cliffs.hill_shade_mult(lv)
						if m > 1.0:
							col = Color(minf(col.r * m, 1.0),
								minf(col.g * m, 1.0), minf(col.b * m, 1.0))
					# Mute toward parchment for the paper look.
					col = col.lerp(PARCHMENT, 0.25)
					img.set_pixel(px, py, col)
	_terrain_tex = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	if _game == null or world == null:
		return
	var cam = world.get_node_or_null("GameCamera") as Camera2D
	if cam == null:
		return
	# Seamless transition: paper map fades in as you zoom out past threshold.
	# Jeremy 2026-10-02: "seamless transition to zoom out to a distance"
	# Full opacity at MIN_ZOOM, transparent at ZOOM_THRESHOLD.
	var z: float = cam.zoom.x
	var target_opacity: float = 0.0
	if z < ZOOM_THRESHOLD:
		# Smooth fade: 0.0 at threshold (0.35) → 1.0 at full (0.18).
		var t: float = (ZOOM_THRESHOLD - z) / (ZOOM_THRESHOLD - 0.18)
		target_opacity = clampf(t, 0.0, 1.0)
	# Smooth the opacity change (lerp for seamless feel)
	_map_opacity = lerpf(_map_opacity, target_opacity, 0.15)
	_visible_map = _map_opacity > 0.01
	if _canvas == null:
		return
	# Jeremy 2026-10-05 perf: hide the canvas entirely when the map is
	# faded out so the renderer culls it; skip redraw bookkeeping while
	# invisible (was: queue_redraw every frame even at alpha 0).
	_canvas.visible = _visible_map
	if not _visible_map:
		_redraw_accum = 0.0
		return
	_canvas.modulate.a = _map_opacity
	# Jeremy 2026-10-05 perf: throttle redraws to 5 Hz while visible.
	# The overview (unit dots, battle markers, labels) reads identically;
	# the HTML original rebuilt its map cache even less often.
	_redraw_accum += delta
	if _redraw_accum >= REDRAW_INTERVAL:
		_redraw_accum = 0.0
		_canvas.queue_redraw()


## Jeremy 2026-10-04: paper-map LOD — when the paper map is fully opaque,
## the detailed world (units, buildings, particles, terrain) hides entirely.
## HTML parity: inPaperMap() skips the whole world layer, drawing only the
## parchment. This is the far-zoom performance win: ~1,500 nodes → 1 map.
func is_paper_lod() -> bool:
	return _map_opacity >= 0.99


## Paints the map onto a CanvasItem (called by the MapCanvas child).
func draw_on(c: CanvasItem) -> void:
	if not _visible_map:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# Map occupies most of the screen with margin
	var map_size: Vector2 = Vector2(
		minf(vp.x - MAP_MARGIN * 2, (vp.y - MAP_MARGIN * 2) * 1.33),
		minf(vp.y - MAP_MARGIN * 2, (vp.x - MAP_MARGIN * 2) / 1.33)
	)
	_map_rect = Rect2((vp - map_size) / 2, map_size)

	# Parchment background with border
	c.draw_rect(_map_rect.grow(8), PARCHMENT_DARK)
	c.draw_rect(_map_rect, PARCHMENT)

	# Terrain
	if _terrain_tex != null:
		c.draw_texture_rect(_terrain_tex, _map_rect, false)

	# Faction territories: colored dots for units
	if _game != null and _game.has_method("get_units"):
		for unit in _game.get_units():
			if not (unit is Dictionary):
				continue
			var faction: String = str(unit.get("faction", ""))
			var pos: Vector2 = unit.get("pos", Vector2.ZERO)
			var map_pos := _world_to_map(pos)
			var fcolor := _faction_color(faction)
			c.draw_circle(map_pos, 3.0, fcolor)

	# Buildings as squares
	if _game != null and _game.has_method("get_buildings"):
		for b in _game.get_buildings():
			if not (b is Dictionary):
				continue
			var faction: String = str(b.get("faction", ""))
			var pos: Vector2 = b.get("pos", Vector2.ZERO)
			var map_pos := _world_to_map(pos)
			var fcolor := _faction_color(faction)
			c.draw_rect(Rect2(map_pos - Vector2(3, 3), Vector2(6, 6)), fcolor)

	# Dungeon markers (adventure mode) — purple diamonds.
	if world != null and world.get("adventure") != null:
		var adv = world.get("adventure")
		for d in adv.get("dungeons"):
			if not (d is Dictionary):
				continue
			if bool(d.get("cleared", false)):
				continue
			var dpos: Vector2 = d.get("pos", Vector2.ZERO)
			var mp := _world_to_map(dpos)
			var s := 7.0
			c.draw_colored_polygon(
				PackedVector2Array([mp + Vector2(0, -s), mp + Vector2(s, 0),
					mp + Vector2(0, s), mp + Vector2(-s, 0)]),
				Color(0.6, 0.2, 0.9))

	# Camera viewport indicator
	var cam: Camera2D = world.get_node_or_null("GameCamera") as Camera2D
	if cam != null:
		var view_size: Vector2 = get_viewport().get_visible_rect().size / cam.zoom.x
		var cam_map_pos := _world_to_map(cam.position)
		var view_map_size: Vector2 = view_size / _world_size() * _map_rect.size
		c.draw_rect(
			Rect2(cam_map_pos - view_map_size / 2, view_map_size),
			INK, false, 2.0
		)

	_draw_battle_markers(c)
	_draw_region_labels(c)
	_draw_town_labels(c)
	_draw_monastery_labels(c)
	_draw_crystal_labels(c)

	# Title
	var font := ThemeDB.fallback_font
	c.draw_string(font, _map_rect.position + Vector2(12, 24), "PAPER MAP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, INK)


func _world_size() -> Vector2:
	# 4096x4096 from M2 world gen
	return Vector2(4096, 4096)


func _world_to_map(world_pos: Vector2) -> Vector2:
	var ws := _world_size()
	var uv := Vector2(
		clampf(world_pos.x / ws.x, 0.0, 1.0),
		clampf(world_pos.y / ws.y, 0.0, 1.0)
	)
	return _map_rect.position + uv * _map_rect.size


func _map_to_world(map_pos: Vector2) -> Vector2:
	var ws := _world_size()
	var uv := (map_pos - _map_rect.position) / _map_rect.size
	return Vector2(
		clampf(uv.x, 0.0, 1.0) * ws.x,
		clampf(uv.y, 0.0, 1.0) * ws.y
	)


func _faction_color(faction: String) -> Color:
	var fcolors: Dictionary = Config.FACTIONS.get(faction, {})
	return fcolors.get("color", Color.GRAY)


## Pure data for _draw_region_labels: Array of
## {label: String, color: Color, pos: Vector2 (map-space)}.
## Separated for headless testing (no drawing calls).
func _region_label_rows() -> Array:
	var rows: Array = []
	if _game == null:
		return rows
	var buildings: Array = []
	var bprop = _game.get("buildings")
	if bprop is Array:
		buildings = bprop
	elif _game.has_method("get_buildings"):
		var bl = _game.get_buildings()
		if bl is Array:
			buildings = bl
	if buildings.is_empty():
		return rows
	# SimTerritory.compute_regions is a static, read-only port of the HTML's
	# getRegions() clustering (completed halls of the same race within
	# TERRITORY_R*2.2 join one region) plus its unclaimed 4x3 geographic
	# sectors. Territory.gd is not modified; this only calls it.
	var regions: Array = SimTerritory.compute_regions(buildings, _world_size())
	for r in regions:
		if not (r is Dictionary):
			continue
		var label: String = String(r.get("name", ""))
		if label == "":
			continue
		var race := String(r.get("race", ""))
		var color := _faction_color(race)
		if race == "":
			color = Color8(0x8a, 0x8a, 0x8a)  # HTML: #8a8a8a for unowned
		color.a = 0.95  # HTML: c.globalAlpha = 0.95
		var wpos := Vector2(float(r.get("cx", 0.0)), float(r.get("cy", 0.0)))
		rows.append({"label": label, "color": color, "pos": _world_to_map(wpos)})
	return rows


func _draw_region_labels(c: CanvasItem) -> void:
	# Named-region labels at each region's center (HTML parity):
	#   - font 'bold 13px Georgia, serif', centered (buildPaperMapCache)
	#   - fill = owning faction's color (standing rule: faction colors),
	#     gray fallback (#8a8a8a) for unowned
	#   - dark ink stroke outline, lineWidth 3 / rgba(46,30,14,0.9)
	#   - fill alpha 0.95
	# Drawn before town labels so towns read on top (HTML draws regions
	# first in the cache, towns after).
	var font := ThemeDB.fallback_font
	var size := 13
	var ink := Color(0.18, 0.12, 0.055, 0.9)
	for row in _region_label_rows():
		var label: String = String(row["label"])
		var color: Color = row["color"]
		var mp: Vector2 = row["pos"]
		var text_w: float = font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := Vector2(mp.x - text_w / 2, mp.y)
		c.draw_string_outline(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, ink)
		c.draw_string(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## ---- battle markers (HTML buildPaperMapCache parity) ----------------------
## HTML draws a clash marker wherever opposing forces meet on the paper map:
## every 3rd unit is sampled; a marker fires when an alive, non-downed unit
## of a DIFFERENT faction stands within clash radius; max 14 markers,
## deduped so no two sit within 50 cache-px of each other.
## World-scale note: HTML's world is 16000 wide with clash radius 260 and a
## 1100px cache; our world is 4096 wide, so radii scale by 4096/16000.
## The marker is DRAWN, not text: HTML uses the ⚔️ glyph, but Godot's web
## font lacks it and it renders as a tofu box on iPhone (Jeremy 2026-10-03)
## — two crossed ink-red strokes read as crossed swords at map scale.
const BATTLE_CLASH_RADIUS := 67.0  # 260 * (4096 / 16000)
const BATTLE_MARK_MAX := 14
const BATTLE_DEDUP_WORLD := 186.0  # (50 / 1100) * 16000 * (4096 / 16000)


## World-space clash marker positions (pure: units + world size in, points
## out). Split out for tests; draw_on() maps them into map space.
static func battle_markers(units: Array, world_size: Vector2) -> Array[Vector2]:
	var marks: Array[Vector2] = []
	var clash_r2: float = BATTLE_CLASH_RADIUS * BATTLE_CLASH_RADIUS
	var dedup_r2: float = BATTLE_DEDUP_WORLD * BATTLE_DEDUP_WORLD
	var n: int = units.size()
	var i: int = 0
	while i < n and marks.size() < BATTLE_MARK_MAX:
		var u = units[i]
		if u is Dictionary and bool(u.get("alive", false)) \
				and not bool(u.get("downed", false)):
			var ufac: String = str(u.get("faction", ""))
			var upos: Vector2 = u.get("position", Vector2.ZERO)
			var clash := false
			var j: int = i + 1
			while j < mini(n, i + 60):
				var v = units[j]
				if v is Dictionary and bool(v.get("alive", false)) \
						and not bool(v.get("downed", false)) \
						and str(v.get("faction", "")) != ufac:
					var vpos: Vector2 = v.get("position", Vector2.ZERO)
					if upos.distance_squared_to(vpos) < clash_r2:
						clash = true
						break
				j += 1
			if clash:
				var dup := false
				for m in marks:
					if m.distance_squared_to(upos) < dedup_r2:
						dup = true
						break
				if not dup:
					marks.append(upos)
		i += 3
	return marks


func _draw_battle_markers(c: CanvasItem) -> void:
	if _game == null:
		return
	var units = _game.get("units")
	if not (units is Array) or (units as Array).is_empty():
		return
	var col := Color(0.55, 0.12, 0.10)  # dried-blood ink
	var ring := Color(0.55, 0.12, 0.10, 0.6)
	for wpos in battle_markers(units, _world_size()):
		var mp := _world_to_map(wpos)
		var s := 9.0
		c.draw_line(mp + Vector2(-s, -s), mp + Vector2(s, s), col, 3.0)
		c.draw_line(mp + Vector2(-s, s), mp + Vector2(s, -s), col, 3.0)
		c.draw_arc(mp, s + 3.0, 0.0, TAU, 16, ring, 1.5)


func _draw_town_labels(c: Control) -> void:
	# Town / city name labels in the owning faction's color.
	if _game.towns == null or _game.towns.is_empty():
		return
	var font := ThemeDB.fallback_font
	var size := 15
	for town_id in _game.towns.keys():
		var town: Dictionary = _game.towns[town_id]
		var label: String = String(town.get("name", ""))
		if label == "":
			continue
		var color := _faction_color(String(town.get("faction", "")))
		var wpos: Vector2 = town.get("position", Vector2.ZERO)
		var mp := _world_to_map(wpos)
		var text_w: float = font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := Vector2(mp.x - text_w / 2, mp.y - 14)
		c.draw_string(font, pos + Vector2(1, 1), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, INK)
		c.draw_string(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## ---- monastery labels (Jeremy 2026-10-04: the Seven Monasteries are major
## named landmarks, so they read on the far-zoom paper map alongside town
## and region names. Not in the HTML build — monastery system is new.)
##
## Pure data for _draw_monastery_labels: Array of
## {label: String, color: Color, pos: Vector2 (map-space)}.
## Color: owning faction's color when captured, the god's own color when
## unowned (so the map shows which god waits where).
## Separated for headless testing (no drawing calls).
func _monastery_label_rows() -> Array:
	var rows: Array = []
	if _game == null:
		return rows
	var mons = _game.get("monasteries")
	if mons == null:
		return rows
	var records: Array = []
	if mons is SimMonasteries:
		records = (mons as SimMonasteries).monasteries
	elif mons is Array:
		records = mons
	if records.is_empty():
		return rows
	var god_by_id: Dictionary = {}
	for g: Dictionary in SimMonasteries.GODS:
		god_by_id[String(g.get("id", ""))] = g
	for m in records:
		if not (m is Dictionary):
			continue
		var god: Dictionary = god_by_id.get(String(m.get("god_id", "")), {})
		if god.is_empty():
			continue
		var owner := String(m.get("owner", ""))
		var color: Color
		if owner == "":
			color = god.get("main", Color.GRAY)
		else:
			color = _faction_color(owner)
		var wpos: Vector2 = m.get("position", Vector2.ZERO)
		rows.append({
			"label": String(god["name"]),
			"color": color,
			"pos": _world_to_map(wpos),
		})
	return rows


func _draw_monastery_labels(c: CanvasItem) -> void:
	# A small drawn diamond marker (never a glyph — tofu rule) above the
	# god's name, in the owner faction's color or the god's own color.
	var font := ThemeDB.fallback_font
	var size := 12
	var ink := Color(0.18, 0.12, 0.055, 0.9)
	for row in _monastery_label_rows():
		var mp: Vector2 = row["pos"]
		var col: Color = row["color"]
		var s := 5.0
		var diamond := PackedVector2Array([
			mp + Vector2(0, -s), mp + Vector2(s, 0),
			mp + Vector2(0, s), mp + Vector2(-s, 0)])
		diamond.append(diamond[0])
		c.draw_polyline(diamond, col, 2.0)
		var label := String(row["label"])
		var text_w: float = font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := Vector2(mp.x - text_w / 2, mp.y + s + 13)
		c.draw_string(font, pos + Vector2(1, 1), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
		c.draw_string(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## ---- dark crystal markers (Jeremy 2026-10-04: the Seven Dark Crystals are
## the evil mirror of the Seven Monasteries — same paper-map landmark
## treatment, added 2026-10-04 after the crystals landed ~10:12 CDT.)
##
## Pure data for _draw_crystal_labels: Array of
## {label: String, color: Color, pos: Vector2 (map-space)}.
## Color: owning faction's color when captured; the rogue god's "trim"
## accent color while unowned ("main" colors are near-black on most rogue
## gods and would vanish on parchment — trim is the legible accent).
## The marker is a small drawn jagged shard (crystal), not the monastery's
## diamond, so the two landmarks read differently at a glance.
## Separated for headless testing (no drawing calls).
func _crystal_label_rows() -> Array:
	var rows: Array = []
	if _game == null:
		return rows
	var crys = _game.get("crystals")
	if crys == null:
		return rows
	var records: Array = []
	if crys is SimDarkCrystals:
		records = (crys as SimDarkCrystals).crystals
	elif crys is Array:
		records = crys
	if records.is_empty():
		return rows
	var god_by_id: Dictionary = {}
	for g: Dictionary in SimDarkCrystals.ROGUE_GODS:
		god_by_id[String(g.get("id", ""))] = g
	for c in records:
		if not (c is Dictionary):
			continue
		var god: Dictionary = god_by_id.get(String(c.get("god_id", "")), {})
		if god.is_empty():
			continue
		var owner := String(c.get("owner", ""))
		var color: Color
		if owner == "":
			color = god.get("trim", Color.GRAY)
		else:
			color = _faction_color(owner)
		var wpos: Vector2 = c.get("position", Vector2.ZERO)
		rows.append({
			"label": String(god["name"]),
			"color": color,
			"pos": _world_to_map(wpos),
		})
	return rows


func _draw_crystal_labels(c: CanvasItem) -> void:
	# A small drawn jagged crystal shard (never a glyph — tofu rule) above
	# the rogue god's name, in the owner faction's color or the god's own
	# trim color.
	var font := ThemeDB.fallback_font
	var size := 12
	var ink := Color(0.18, 0.12, 0.055, 0.9)
	for row in _crystal_label_rows():
		var mp: Vector2 = row["pos"]
		var col: Color = row["color"]
		var s := 5.0
		# Jagged shard: tall spike with a kinked left edge.
		var shard := PackedVector2Array([
			mp + Vector2(0, -s * 1.6),
			mp + Vector2(s * 0.9, -s * 0.2),
			mp + Vector2(s * 0.5, s),
			mp + Vector2(-s * 0.5, s * 0.6),
			mp + Vector2(-s * 0.8, -s * 0.5),
		])
		shard.append(shard[0])
		c.draw_polyline(shard, col, 2.0)
		var label := String(row["label"])
		var text_w: float = font.get_string_size(
			label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos := Vector2(mp.x - text_w / 2, mp.y + s + 13)
		c.draw_string(font, pos + Vector2(1, 1), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, ink)
		c.draw_string(font, pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _input(event: InputEvent) -> void:
	if not _visible_map:
		return
	# Tap on the map to jump the camera
	var tapped := false
	var tap_pos := Vector2.ZERO
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			tapped = true
			tap_pos = mb.position
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			tapped = true
			tap_pos = st.position

	if tapped and _map_rect.has_point(tap_pos):
		var world_pos := _map_to_world(tap_pos)
		map_tapped.emit(world_pos)
		# Don't force-show after jumping; let zoom dictate
		if not _force_show:
			pass  # stays visible until zoom changes
		get_viewport().set_input_as_handled()
