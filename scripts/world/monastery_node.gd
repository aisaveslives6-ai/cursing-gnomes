class_name MonasteryNode
extends Node2D
## Cursing Gnomes — Seven Monasteries visuals (Jeremy 2026-10-04).
##
## Pixel-art sprite per god (assets/gods/monastery_<god>.png), scaled to a
## ~160px footprint — a building, not a screen-filling blob. Pure overlay
## drawing on top:
##   - faction-colored ownership ring when captured
##   - capture progress arc while being taken
##   - force-field shimmer when splash damage washes over it
##   - god name label

var monastery_id := -1
var god_id := "auriel"

## Live link to the SimMonasteries record (owner/progress update live).
var record: Dictionary = {}

var _t := 0.0
var _flash := 0.0  # force-field shimmer timer
var _redraw_accum := 0.0
var _culled := false
# PERF: cached god def (was a linear search per _draw).
var _g: Dictionary = {}
var _sprite: Sprite2D = null
## 2026-10-06: procedural normal maps (CanvasTexture wraps) so the
## PointLight2D rig shades sprites directionally. Preloaded (not
## class_name-resolved) for headless single-script runs.
const SpriteNormalsScript := preload("res://scripts/world/sprite_normals.gd")
var _label_y := -130.0  # computed from sprite height in setup()

## Target footprint width in px (Jeremy 2026-10-04: shrink the 460px blobs).
const FOOTPRINT := 160.0

## Ground-ring geometry (gate 3, 2026-10-06): ownership + capture rings
## draw as an iso-squashed ellipse at the footprint base (0.62 = the
## game's ground-decal convention, cf. rubble_layer / combat_fx stains).
## A screen-space circle dips below the ground point and reads as a
## floating halo; the ellipse reads as painted territory.
const RING_RX := 105.0
const RING_CY := -57.0
const RING_SQUASH := 0.62


func setup(mid: int, gid: String, pos: Vector2) -> void:
	monastery_id = mid
	god_id = gid
	position = pos
	_g = _god()
	var tex: Texture2D = Art.monastery_texture(god_id)
	if tex != null:
		_sprite = Sprite2D.new()
		_sprite.texture = tex
		SpriteNormalsScript.apply_to(_sprite)
		_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var sc: float = FOOTPRINT / float(tex.get_width())
		_sprite.scale = Vector2(sc, sc)
		# Base of the building sits on the ground point (bottom-center).
		_sprite.position = Vector2(0, -float(tex.get_height()) * sc * 0.5)
		add_child(_sprite)
		_label_y = -float(tex.get_height()) * sc - 18.0


## Jeremy 2026-10-04: cull off-screen monasteries from the render pipeline
## (60fps). Mirrors UnitNode.set_culled: stops _process and hides the node.
func set_culled(culled: bool) -> void:
	if culled == _culled:
		return
	_culled = culled
	set_process(not culled)
	visible = not culled
	if not culled:
		_redraw_accum = 1.0  # redraw immediately on reappear


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta)
	_redraw_accum += delta
	if _redraw_accum >= 0.25:
		_redraw_accum = 0.0
		queue_redraw()  # progress ring + ownership pulse at 4 Hz


## Called when splash damage washes over the monastery (force-field rule).
func flash_force_field() -> void:
	_flash = 1.2
	queue_redraw()


func _god() -> Dictionary:
	for g: Dictionary in SimMonasteries.GODS:
		if String(g.get("id", "")) == god_id:
			return g
	return SimMonasteries.GODS[0]


func _owner_faction() -> String:
	return String(record.get("owner", ""))


## Bottom edge of the ground ring: kisses the ground point instead of
## dipping ~50px under it (test hook).
static func ring_bottom() -> float:
	return RING_CY + RING_SQUASH * RING_RX


## Force-field dome shimmer: the sweep glides across the TOP half of the
## squashed ellipse only, so the shield never dips below ground.
## Returns (start_angle, end_angle); both always within [PI, TAU].
static func dome_shimmer_angles(t: float) -> Vector2:
	var sweep := 0.5 + 0.5 * sin(t * 3.0)
	var start := PI + sweep * PI * 0.4
	return Vector2(start, start + PI * 0.6)


func _draw() -> void:
	var g := _g
	# Ground shadow under the footprint: sun-cast (offset opposite the sun),
	# footprint-matched, soft falloff — reads as cast on the ground, not a
	# halo. Jeremy 2026-10-05: Volkar looked floating with the old centered
	# hard ellipse.
	Shadows.draw_cast(self, Vector2(FOOTPRINT * 1.15, 36.0))
	# Fallback marker if the sprite failed to load.
	if _sprite == null:
		var main: Color = g.get("main", Color.WHITE)
		draw_colored_polygon(PackedVector2Array([
			Vector2(-40, 0), Vector2(40, 0), Vector2(0, -80)]), main)
	# Ground rings: ownership + capture progress, drawn inside one
	# iso-squashed transform so both sit on the ground instead of
	# dipping below it like a floating halo.
	draw_set_transform(Vector2(0, RING_CY), 0, Vector2(1.0, RING_SQUASH))
	var owner := _owner_faction()
	if owner != "":
		var oc: Color = Config.FACTIONS.get(owner, {}).get("color",
			Color(1, 1, 1))
		var pulse := 0.55 + 0.20 * sin(_t * 2.0)
		draw_arc(Vector2.ZERO, RING_RX, 0, TAU, 64,
			Color(oc.r, oc.g, oc.b, pulse), 5.0)
	_draw_capture_ring()
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	# God name label.
	_draw_label(String(g.get("name", "TEMPLE")).to_upper())
	# Force-field shimmer: a dome arcing OVER the building (top half of
	# the squashed ellipse), never dipping below the ground point.
	if _flash > 0.0:
		var a: float = clampf(_flash, 0.0, 1.0) * 0.75
		draw_set_transform(Vector2(0, -10), 0, Vector2(1.0, RING_SQUASH))
		draw_arc(Vector2.ZERO, 110.0, PI, TAU, 48,
			Color(0.6, 0.85, 1.0, a), 6.0)
		var seg := dome_shimmer_angles(_t)
		draw_arc(Vector2.ZERO, 100.0, seg.x, seg.y, 32,
			Color(0.9, 0.97, 1.0, a), 3.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## God name pill label above the structure.
func _draw_label(text: String) -> void:
	var font: Font = ThemeDB.fallback_font
	var fs := 12
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, fs).x
	var pw := tw + 18.0
	draw_rect(Rect2(-pw / 2.0, _label_y, pw, 20.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(-pw / 2.0, _label_y, pw, 2.5), Color(1.0, 0.85, 0.4, 0.8))
	draw_string(font, Vector2(-tw / 2.0, _label_y + 15.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(1.0, 0.97, 0.88))


func _draw_capture_ring() -> void:
	# Called inside the ground-ring transform: shares the ownership
	# ring's track so progress fills it.
	var prog: Dictionary = record.get("progress", {})
	var best := 0.0
	for f: String in prog.keys():
		best = maxf(best, float(prog[f]))
	if best <= 0.0:
		return
	var frac := best / SimMonasteries.CAPTURE_TIME
	var col := Color(1.0, 0.85, 0.35)
	if bool(record.get("contested", false)):
		col = Color(1.0, 0.35, 0.30)
	draw_arc(Vector2.ZERO, RING_RX, -PI / 2.0,
		-PI / 2.0 + TAU * frac, 64, col, 7.0)
