class_name MapProp
extends Node2D
## Cursing Gnomes — a static map prop.
## Trees use the HTML build's real tree art (oak_tree/pine_tree, alternating
## deterministically by position); resource nodes use the deposit sprites in
## assets/art/nodes/ (rich mineable node art; diamond fallback if missing).
## Y-sorted by the World root so units walk behind tree canopies.


## Target tree canopy height in px.
const TREE_WORLD_H := 72.0

## Target resource icon height in world px. The flat diamonds these replace
## were 24 px tall; 36 px gives the icon art presence without dominating
## the map at game zoom.
const RES_ICON_WORLD_H := 36.0

## Tree sway (HTML treeSwayOn parity): gentle breeze rotation around the
## planted base, position never shifts. Off = perfectly still.
## sway_enabled mirrors the Settings toggle; sway_zoom_ok mirrors the HTML
## camZoom > 0.55 gate (still air when zoomed far out).
static var sway_enabled := true
static var sway_zoom_ok := true
## Sway amplitude in radians (HTML: sin(t*1.1 + seed*0.37) * 0.014).
const SWAY_AMP := 0.014
const SWAY_SPEED := 1.1

## Per-frame sway clock, shared by every tree (perf 2026-10-04: was one
## Time.get_ticks_msec() native call per tree per frame — ~700 x 60fps of
## identical values). The first tree to run each frame refreshes it.
static var _sway_t := 0.0
static var _sway_frame := -1


## Sway clock for this frame (seconds). Cached: one native call per frame,
## not one per tree. The pose math is unchanged — every tree still sways
## from the same wall clock, so there is zero phase drift vs the old code.
static func sway_time() -> float:
	var f := Engine.get_process_frames()
	if f != _sway_frame:
		_sway_frame = f
		_sway_t = float(Time.get_ticks_msec()) / 1000.0
	return _sway_t

var kind := "tree"  # "tree" | "res_wood" | "res_oil" | "res_gold"
## Linked work-site id (0 = none). Set by World for tree props so the sim's
## chop/fell state can drive the visual (shake while chopped, fall on fell).
var site_id := 0

var _sprite: Sprite2D = null
## 2026-10-06: procedural normal maps (CanvasTexture wraps) so the
## PointLight2D rig shades sprites directionally. Preloaded (not
## class_name-resolved) for headless single-script runs.
const SpriteNormalsScript := preload("res://scripts/world/sprite_normals.gd")
## Launch-readiness graphics pass 2026-10-05: if the tree art ever fails to
## load, draw a pine silhouette instead of leaving an invisible tree.
var _tree_fallback := false
var _sway_phase := 0.0
## Jeremy 2026-10-05: chop shake — set by the world when a woodcutter is
## actively working this tree's site. Adds a fast shudder on top of sway.
var _chopping := false
## Grounding (launch readiness gate 1+3, 2026-10-05): trees never had a
## shadow, so groves read as pasted-on the terrain. Sun-driven blob via
## Shadows, same quantized-key pattern as UnitNode/BuildingNode — the sun
## drifts over the 8-minute day, so redraws are rare and cheap.
const TREE_SHADOW_FOOTPRINT := 26.0
const TREE_SHADOW_ALPHA := 0.85
var _shadow_key: int = 0
## Jeremy 2026-10-05: fall state — once felled the tree topples via tween
## and frees itself; _process stops fighting the tween.
var _falling := false
## 0..3 stagger bucket (perf 2026-10-04): sway transform updates are
## throttled to every 4th frame (~15Hz, the GrassTufts precedent) and spread
## across frames so no single frame eats all the updates. Tests may set it
## directly to force the update path on a chosen frame.
var _sway_bucket := 0
## Jeremy 2026-10-03: seasons show in the sim graphics. HTML treeSeasonTint
## parity — multiply-blend approximations of the HTML's blend modes:
##   Autumn (oak only, HTML excluded pine): warm orange cast (#e67e22 hue)
##   Winter: cold desaturated blue-gray (HTML multiply #b9c9d6)
##   Spring: fresh green lift (HTML soft-light #7dff8a)
##   Summer: no tint.
var _is_pine := false
const SEASON_TINT_AUTUMN := Color(1.0, 0.70, 0.38)
const SEASON_TINT_WINTER := Color(0.73, 0.79, 0.84)
const SEASON_TINT_SPRING := Color(0.70, 1.0, 0.68)


func setup(p_kind: String, p_pos: Vector2) -> void:
	kind = p_kind
	position = p_pos
	if kind == "tree":
		# Deterministic per-tree phase from position (HTML used tree seed).
		_sway_phase = fmod(absf(p_pos.x * 0.37 + p_pos.y * 0.73), TAU)
		_sway_bucket = absi(int(p_pos.x + p_pos.y)) % 4
		# Same oak/pine pick as Art.tree_texture (HTML alternated by seed).
		_is_pine = absi(hash("%d,%d" % [int(p_pos.x), int(p_pos.y)])) % 2 == 1
		add_to_group("cg_trees")
		_shadow_key = Shadows.shadow_key(p_pos)
		var tex: Texture2D = Art.tree_texture(p_pos)
		if tex != null:
			_sprite = Sprite2D.new()
			_sprite.texture = tex
			SpriteNormalsScript.apply_to(_sprite)
			var sc: float = TREE_WORLD_H / float(tex.get_height())
			_sprite.scale = Vector2(sc, sc)
			_sprite.position = Vector2(0, -TREE_WORLD_H * 0.48)
			add_child(_sprite)
		else:
			# Art missing: never an invisible tree — the _draw fallback
			# paints a pine silhouette with its shadow.
			_tree_fallback = true
	elif kind.begins_with("res_"):
		# Resource nodes show the rich mineable deposit sprite (gold veins /
		# oil pool / log pile), falling back to the HUD icon and then the
		# old flat diamond if art is missing.
		var res_key: String = kind.trim_prefix("res_")
		var node_tex: Texture2D = Art.resource_node_texture(res_key)
		var icon: Texture2D = node_tex if node_tex != null else Art.resource_icon(res_key)
		if icon != null:
			_sprite = Sprite2D.new()
			_sprite.texture = icon
			SpriteNormalsScript.apply_to(_sprite)
			var rsc: float = RES_ICON_WORLD_H / float(icon.get_height())
			_sprite.scale = Vector2(rsc, rsc)
			_sprite.position = Vector2(0, -RES_ICON_WORLD_H * 0.42)
			add_child(_sprite)
	_refresh_process_state()


## Only trees that are actually visible need _process: invisible trees
## (over the tier draw budget, paper-map LOD, hidden parents) skip the
## per-frame dispatch entirely instead of early-outing inside it.
## Called from setup() and NOTIFICATION_VISIBILITY_CHANGED; toggles only
## on real state changes (set_process() itself has a cost).
func _refresh_process_state() -> void:
	var want := kind == "tree" and visible
	if want == is_processing():
		return
	set_process(want)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_refresh_process_state()


## Applies the HTML treeSeasonTint for the given season name
## ("Spring"|"Summer"|"Autumn"|"Winter"). No-op without a sprite.
func apply_season_tint(season: String) -> void:
	if _sprite == null:
		return
	match season:
		"Autumn":
			_sprite.modulate = Color.WHITE if _is_pine else SEASON_TINT_AUTUMN
		"Winter":
			_sprite.modulate = SEASON_TINT_WINTER
		"Spring":
			_sprite.modulate = SEASON_TINT_SPRING
		_:
			_sprite.modulate = Color.WHITE


func _process(_delta: float) -> void:
	if kind != "tree" or _falling:
		return
	# Sun-driven shadow state: redraw only when the quantized key changes
	# (sun drifts slowly), never per frame.
	var sk := Shadows.shadow_key(position)
	if sk != _shadow_key:
		_shadow_key = sk
		queue_redraw()
	# Jeremy 2026-10-04 (perf): sway rotation updates are throttled to every
	# 4th frame (~15Hz, the GrassTufts precedent) with a per-tree stagger so
	# no single frame eats all the transform updates. The sway is a 0.18 Hz,
	# 0.014 rad oscillation, so 60Hz updates were 4x redundant work.
	# Wall-clock sampling (sway_time) means zero phase drift: the pose is
	# always exactly what the unthrottled version computes at this moment.
	# Invisible trees never reach here — _refresh_process_state() keeps
	# _process disabled while they are hidden (tier budget / paper LOD).
	if sway_enabled and sway_zoom_ok:
		if Engine.get_process_frames() % 4 == _sway_bucket:
			rotation = sin(sway_time() * SWAY_SPEED + _sway_phase) * SWAY_AMP
			# Jeremy 2026-10-05: chop shudder — a fast jitter layered over
			# the sway while a woodcutter is working this tree.
			if _chopping:
				rotation += sin(sway_time() * 22.0 + _sway_phase * 3.0) * 0.035
	elif rotation != 0.0:
		rotation = 0.0


## Jeremy 2026-10-05: called by the world when a woodcutter starts/stops
## working this tree's site. Drives the chop shudder in _process.
func set_chopping(v: bool) -> void:
	if v == _chopping:
		return
	_chopping = v
	_refresh_process_state()


## Jeremy 2026-10-05: the tree is felled — topple over from the base and
## free the prop. The sim spawns the wood-pickup burst separately.
func play_fall() -> void:
	if _falling:
		return
	_falling = true
	remove_from_group("cg_trees")
	set_process(false)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "rotation", 1.35, 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(self, "position:y", position.y + 18.0, 0.7)\
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(queue_free)


## Testable geometry contract for the grounded shadow: the shadow's draw
## angle exactly cancels the prop's sway rotation, so its net world-space
## rotation is always ~0 (the blob stays pinned while the tree moves).
static func shadow_draw_angle(prop_rotation: float) -> float:
	return -prop_rotation


## Launch readiness 2026-10-06 (gate 3: nothing floating): the whole prop
## rotates for sway (±0.014 rad) and chop-shudder (±0.035 rad), but the
## shadow is cast on the GROUND — draw it counter-rotated so the blob stays
## pinned in world space while the tree moves. Without this the shadow
## wobbled up to ~3px with every chop. The transform is restored right
## away: draw_set_transform persists on the canvas item across _draw calls.
func _draw_grounded_shadow() -> void:
	draw_set_transform(Vector2.ZERO, shadow_draw_angle(rotation), Vector2.ONE)
	Shadows.draw_blob(self, TREE_SHADOW_FOOTPRINT, TREE_SHADOW_ALPHA)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw() -> void:
	if _tree_fallback and kind == "tree":
		# Missing-art fallback: pine silhouette grounded at the origin
		# with the same sun-driven shadow as real trees.
		_draw_grounded_shadow()
		_draw_pine_fallback()
		return
	if _sprite != null:
		if kind.begins_with("res_"):
			# Soft contact shadow under the icon so it reads on bright
			# terrain (sand/snow) — an ellipse faked with a scaled circle
			# transform, drawn in local space, static, cheap.
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.85, 0.55))
			draw_circle(Vector2.ZERO, 6.0, Color(0, 0, 0, 0.22))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		elif kind == "tree":
			# Sun-driven blob shadow under the trunk (feet at local
			# origin). Drawn in _draw = under the sprite child, cast
			# opposite the sun, long at dawn/dusk, gone at night.
			_draw_grounded_shadow()
		return
	match kind:
		"res_wood":
			_draw_diamond(Color(0.50, 0.32, 0.16))
		"res_oil":
			_draw_diamond(Color(0.2, 0.2, 0.25))
		"res_gold":
			_draw_diamond(Color(0.95, 0.78, 0.20))
		_:
			_draw_diamond(Color(0.8, 0.8, 0.8))


func _draw_diamond(c: Color) -> void:
	var pts := PackedVector2Array(
		[Vector2(0, -12), Vector2(10, 0), Vector2(0, 12), Vector2(-10, 0)])
	draw_colored_polygon(pts, c)
	# Outline so nodes read on any terrain.
	pts.append(pts[0])
	draw_polyline(pts, c.darkened(0.45), 2.0)


## Missing-art pine silhouette: trunk + two foliage tiers, feet at the
## local origin (same grounding as the sprite path).
func _draw_pine_fallback() -> void:
	var trunk := Color(0.35, 0.24, 0.15)
	var pine := Color(0.16, 0.35, 0.20)
	draw_rect(Rect2(-3, -16, 6, 16), trunk.darkened(0.2))
	draw_rect(Rect2(-2, -16, 4, 16), trunk)
	draw_colored_polygon(PackedVector2Array(
		[Vector2(-16, -14), Vector2(16, -14), Vector2(0, -40)]),
		pine.darkened(0.15))
	draw_colored_polygon(PackedVector2Array(
		[Vector2(-12, -28), Vector2(12, -28), Vector2(0, -52)]), pine)
	draw_colored_polygon(PackedVector2Array(
		[Vector2(-12, -28), Vector2(0, -52), Vector2(0, -28)]),
		pine.lightened(0.12))
