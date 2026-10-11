class_name CombatFX
extends Node2D
## Cursing Gnomes — combat visual effects (Milestone 4: combat & disasters).
##
## Pooled, budgeted FX for hits, deaths, explosions, and fires:
##   - hit_flash(pos): quick white-red flash on melee hits (unit_killed's
##     little brother — driven by projectile_hit for ranged)
##   - death_poof(pos): smoke frames (assets/art/fx/smoke_*.png)
##   - explosion(pos, radius): fire frames (fire_lg_*/fire_rg_*) + ring
##   - fire_node management is left to the fire visuals (M4: simple
##     per-fire animated sprite, capped with the fires themselves)
##
## PERFORMANCE: fixed pool (FX_POOL = 64). spawn_* reuses the oldest
## finished slot; never allocates under fire. Each FX is a Node2D with
## _draw — no per-FX textures except the frame strips, which are cached
## once in Art.


const FX_POOL := 64  # bumped 2026-10-04: god powers add heavy FX demand

var _pool: Array[Dictionary] = []  # {node, kind, pos, age, life, radius}

## ---- Blood & gore (HTML spawnGore / bloodStains parity) ----
## Jeremy 2026-10-04 art direction: Halo 1 (Gearbox PC) blood style —
## bright vibrant red, chunky readable splatter, distinct droplets, pools
## that spread. Stylized, NOT dark/gritty-realistic.
const HALO_BLOOD := Color(0.92, 0.10, 0.13)   # fresh spray / droplets
const HALO_STAIN := Color(0.82, 0.09, 0.11)   # ground splatter decals
const HALO_GORE := Color(0.80, 0.10, 0.12)    # flesh chunks / limbs
## Physics chunks (limb / chunk / metal) with gravity; they land and persist.
const GORE_MAX := 240
var _gore: Array[Dictionary] = []  # {pos, vel, rot, rot_vel, age, life, size, kind, grounded, ground_y}
var _gore_layer: Node2D

## ---- Blood stains (HTML bloodStains parity) ----
## Persistent ground decals; fade over ~60s real time, capped at 400.
const STAIN_MAX := 400
var _stains: Array[Dictionary] = []  # {pos, life, max_life, size, alpha, rot}
var _stain_layer: Node2D

## ---- Gibs (artillery "holy shit" moments) ----
## Jeremy 2026-10-04: artillery blows units into bits — chibi body parts
## (head, torso, arms, legs) with physics, bounce, blood. Worms meets Halo.
const GIB_MAX := 60
const GIB_FACTION_COLORS := {
	"humans": Color(0.506, 0.831, 0.980),
	"ogres": Color(0.647, 0.839, 0.655),
	"elves": Color(0.400, 0.733, 0.416),
	"gnomes": Color(0.882, 0.745, 0.906),
	"undead": Color(0.565, 0.643, 0.682),
}
const GIB_SKIN := Color(1.0, 0.85, 0.70)
const GIB_SKIN_UNDEAD := Color(0.62, 0.72, 0.58)
var _gibs: Array[Dictionary] = []  # {pos, vel, rot, rot_vel, age, life,
	# size, part, fcol, skin, bounced, ground_y, drip_cd}
var _gib_layer: Node2D

## ---- Cartoon craters (artillery landscape damage) ----
## Jeremy 2026-10-04: artillery knocks a big cartoon crater into the ground.
## Persistent decals — dark scorched bowl with a thick raised rim.
const CRATER_MAX := 60
var _craters: Array[Dictionary] = []  # {pos, radius, seed}
var _crater_layer: Node2D

## Jeremy 2026-10-04 (graphics-hourly): decal-layer redraw throttling.
## Stains fade over 60 s and gore chunks / gibs rest on the ground for up to
## 60 s — redrawing these decal layers at 60 fps burned thousands of draw
## calls per second for motion the eye cannot see (400 stains x 4 circles =
## ~1,600 draw calls per redraw, 60x/sec). Stains now redraw at 10 Hz
## (immediate on add/remove); gore and gibs redraw every frame only while at
## least one piece is airborne, otherwise 10 Hz for the slow fade-out.
## Zero visual change: fade steps at 10 Hz are sub-perceptual on a 60 s fade.
const DECAL_REDRAW_INTERVAL := 0.1
var _stain_redraw_acc := 0.0
var _gore_redraw_acc := 0.0
var _gib_redraw_acc := 0.0
## Test hook: counts layer redraws per decal kind (see debug_decal_redraws).
var _debug_decal_redraws := {"stain": 0, "gore": 0, "gib": 0}


## Test hook: how many times each decal layer redrew since reset.
func debug_decal_redraws() -> Dictionary:
	return _debug_decal_redraws.duplicate()


## Test hook: zero the decal redraw counters.
func debug_reset_decal_redraws() -> void:
	_debug_decal_redraws = {"stain": 0, "gore": 0, "gib": 0}


func _ready() -> void:
	for i: int in range(FX_POOL):
		var n := _FxNode.new()
		n.visible = false
		add_child(n)
		_pool.append({"node": n, "busy": false, "age": 0.0, "life": 0.0,
			"kind": "", "radius": 0.0})
	# Stains render under everything; gore chunks above ground but below units.
	_stain_layer = _StainLayer.new()
	_stain_layer.fx = self
	_stain_layer.z_index = -10
	add_child(_stain_layer)
	_gore_layer = _GoreLayer.new()
	_gore_layer.fx = self
	_gore_layer.z_index = -5
	add_child(_gore_layer)
	# Gibs fly above the fray; craters are terrain (below stains).
	_gib_layer = _GibLayer.new()
	_gib_layer.fx = self
	_gib_layer.z_index = 5
	add_child(_gib_layer)
	_crater_layer = _CraterLayer.new()
	_crater_layer.fx = self
	_crater_layer.z_index = -12
	add_child(_crater_layer)


func _process(delta: float) -> void:
	for slot: Dictionary in _pool:
		if not bool(slot["busy"]):
			continue
		slot["age"] = float(slot["age"]) + delta
		var n: _FxNode = slot["node"]
		n.fx_age = float(slot["age"])
		n.fx_life = float(slot["life"])
		n.fx_kind = String(slot["kind"])
		n.fx_radius = float(slot["radius"])
		n.queue_redraw()
		if float(slot["age"]) >= float(slot["life"]):
			slot["busy"] = false
			n.visible = false
	_tick_gore(delta)
	_tick_stains(delta)
	_tick_gibs(delta)


## HTML parity: gorePieces — physics chunks with gravity (220 px/s^2),
## tumbling rotation; they land at ground_y and persist for 60s.
func _tick_gore(delta: float) -> void:
	if _gore.is_empty():
		return
	var moving := false
	var removed := false
	for i: int in range(_gore.size() - 1, -1, -1):
		var g: Dictionary = _gore[i]
		g["age"] = float(g["age"]) + delta
		if float(g["age"]) >= float(g["life"]):
			_gore.remove_at(i)
			removed = true
			continue
		if not bool(g["grounded"]):
			moving = true
			var v: Vector2 = g["vel"]
			v.y += 220.0 * delta
			var p: Vector2 = g["pos"] + v * delta
			if v.y > 0.0 and p.y >= float(g["ground_y"]):
				p.y = float(g["ground_y"])
				g["grounded"] = true
			g["vel"] = v
			g["pos"] = p
			g["rot"] = float(g["rot"]) + float(g["rot_vel"]) * delta
	# Airborne chunks need per-frame redraws; settled chunks only fade, so
	# the layer throttles to 10 Hz. Removals always redraw immediately.
	_gore_redraw_acc += delta
	if moving or removed or _gore_redraw_acc >= DECAL_REDRAW_INTERVAL:
		_gore_redraw_acc = 0.0
		_gore_layer.queue_redraw()
		_debug_decal_redraws["gore"] = int(_debug_decal_redraws["gore"]) + 1


## HTML parity: bloodStains — fade over ~60s real time, hard cap 400.
func _tick_stains(delta: float) -> void:
	if _stains.is_empty():
		return
	var removed := false
	for i: int in range(_stains.size() - 1, -1, -1):
		var s: Dictionary = _stains[i]
		s["life"] = float(s["life"]) - delta
		if float(s["life"]) <= 0.0:
			_stains.remove_at(i)
			removed = true
	# The fade is a 60 s linear ramp — 10 Hz redraws are visually identical
	# to 60 fps. Expiring stains force an immediate redraw so no ghost
	# decals linger (adds call queue_redraw on spawn, unchanged).
	_stain_redraw_acc += delta
	if removed or _stain_redraw_acc >= DECAL_REDRAW_INTERVAL:
		_stain_redraw_acc = 0.0
		_stain_layer.queue_redraw()
		_debug_decal_redraws["stain"] = int(_debug_decal_redraws["stain"]) + 1


## Jeremy 2026-10-04: gibbing — artillery blows a unit into chibi bits.
## 6 parts (head, torso, 2 arms, 2 legs) flung with velocity, gravity,
## one bounce, blood drips while airborne, stains where they land.
func gib(pos: Vector2, faction: String) -> void:
	var fcol: Color = GIB_FACTION_COLORS.get(faction, Color(0.7, 0.7, 0.7))
	var skin: Color = GIB_SKIN_UNDEAD if faction == "undead" else GIB_SKIN
	var parts := ["head", "torso", "arm", "arm", "leg", "leg"]
	for part: String in parts:
		if _gibs.size() >= GIB_MAX:
			_gibs.pop_front()
		_gibs.append({
			"pos": pos + Vector2((randf() - 0.5) * 16.0,
				(randf() - 0.5) * 10.0 - 10.0),
			"vel": Vector2((randf() - 0.5) * 260.0,
				-90.0 - randf() * 170.0),
			"rot": randf() * TAU,
			"rot_vel": (randf() - 0.5) * 14.0,
			"age": 0.0,
			"life": 5.0,
			"size": 8.0 + randf() * 5.0,
			"part": part,
			"fcol": fcol,
			"skin": skin,
			"bounced": false,
			"ground_y": pos.y + 4.0,
			"drip_cd": 0.0,
		})
	# Opening blood spray.
	for b: int in range(3):
		blood(pos)
	_gib_layer.queue_redraw()
	_debug_decal_redraws["gib"] = int(_debug_decal_redraws["gib"]) + 1


## Gib physics: strong gravity, one bounce (dampened), blood drips while
## airborne, stains on bounce and on final rest.
func _tick_gibs(delta: float) -> void:
	if _gibs.is_empty():
		return
	var airborne := false
	var removed := false
	for i: int in range(_gibs.size() - 1, -1, -1):
		var g: Dictionary = _gibs[i]
		g["age"] = float(g["age"]) + delta
		if float(g["age"]) >= float(g["life"]):
			_gibs.remove_at(i)
			removed = true
			continue
		if not bool(g["bounced"]):
			airborne = true
		var p: Vector2 = g["pos"]
		if not bool(g["bounced"]):
			var v: Vector2 = g["vel"]
			v.y += 520.0 * delta
			p = p + v * delta
			# Blood drips while airborne (rate-limited).
			g["drip_cd"] = float(g["drip_cd"]) - delta
			if float(g["drip_cd"]) <= 0.0:
				g["drip_cd"] = 0.16
				blood(p)
			if v.y > 0.0 and p.y >= float(g["ground_y"]):
				p.y = float(g["ground_y"])
				if absf(v.y) > 60.0:
					# Bounce once, dampened.
					v.y = -v.y * 0.35
					v.x *= 0.6
					g["vel"] = v
					g["ground_y"] = p.y
					blood_stain(p, 2)
				else:
					g["bounced"] = true
					g["vel"] = Vector2.ZERO
					blood_stain(p, 3)
			else:
				g["vel"] = v
			g["pos"] = p
			g["rot"] = float(g["rot"]) + float(g["rot_vel"]) * delta
	# Airborne gibs need per-frame redraws; rested gibs only fade over
	# their last 1.5 s, so the layer throttles to 10 Hz. Removals redraw
	# immediately so no ghost parts linger.
	_gib_redraw_acc += delta
	if airborne or removed or _gib_redraw_acc >= DECAL_REDRAW_INTERVAL:
		_gib_redraw_acc = 0.0
		_gib_layer.queue_redraw()
		_debug_decal_redraws["gib"] = int(_debug_decal_redraws["gib"]) + 1


## Jeremy 2026-10-04: cartoon crater — artillery knocks a big crater into
## the ground. Persistent (capped at 60, oldest pop).
## nuclear = true tints the rim sickly green (nuke ground zero).
func crater(pos: Vector2, radius: float, nuclear := false) -> void:
	if _craters.size() >= CRATER_MAX:
		_craters.pop_front()
	_craters.append({"pos": pos, "radius": radius, "seed": randf() * TAU,
		"nuclear": nuclear})
	_crater_layer.queue_redraw()


## HTML parity: spawnGore(kind, count). kind is "limb" | "chunk" | "metal".
## Tight scatter around the body — does not fly across the map.
func gore(pos: Vector2, kind: String, count: int) -> void:
	for i: int in range(count):
		if _gore.size() >= GORE_MAX:
			_gore.pop_front()
		var sz: float = (6.0 + randf() * 5.0) if kind == "limb" \
			else (3.0 + randf() * 6.0)
		_gore.append({
			"pos": pos + Vector2((randf() - 0.5) * 22.0,
				(randf() - 0.5) * 14.0 + 2.0),
			"vel": Vector2((randf() - 0.5) * 36.0,
				(randf() - 0.5) * 20.0 - 8.0),
			"rot": randf() * TAU,
			"rot_vel": (randf() - 0.5) * 10.0,
			"age": 0.0,
			"life": 60.0,
			"size": sz,
			"kind": kind,
			"grounded": false,
			"ground_y": pos.y + 6.0,
		})
	_gore_layer.queue_redraw()
	_debug_decal_redraws["gore"] = int(_debug_decal_redraws["gore"]) + 1


## HTML parity: bloodStains.push — persistent ground blood decals.
func blood_stain(pos: Vector2, count: int = 1) -> void:
	for i: int in range(count):
		if _stains.size() >= STAIN_MAX:
			_stains.pop_front()
		var life: float = 55.0 + randf() * 15.0
		_stains.append({
			"pos": pos + Vector2((randf() - 0.5) * 50.0,
				(randf() - 0.5) * 40.0 + 4.0),
			"life": life,
			"max_life": life,
			"size": 4.0 + randf() * 9.0,
			"alpha": 0.6 + randf() * 0.35,
			"rot": randf() * TAU,
			"nuclear": false,
		})
	_stain_layer.queue_redraw()
	_debug_decal_redraws["stain"] = int(_debug_decal_redraws["stain"]) + 1


## Jeremy 2026-10-06: radiation zone ground scorch (HTML zone tick
## bloodStains radScorch — life 80-120, size 16-44, sickly green, alpha
## 0.25+scorch*0.25; the stain layer renders nuclear:true stains green).
func scorch_spot(pos: Vector2, scorch: float = 1.0) -> void:
	if _stains.size() >= STAIN_MAX:
		_stains.pop_front()
	var life: float = 80.0 + randf() * 40.0
	_stains.append({
		"pos": pos,
		"life": life,
		"max_life": life,
		"size": 16.0 + randf() * 28.0,
		"alpha": 0.25 + clampf(scorch, 0.0, 1.0) * 0.25,
		"rot": randf() * TAU,
		"nuclear": true,
	})
	_stain_layer.queue_redraw()
	_debug_decal_redraws["stain"] = int(_debug_decal_redraws["stain"]) + 1


## Jeremy 2026-10-04: nuclear scorch field (HTML detonateNuke bloodStains
## nuclear:true — 55 stains, R*1.2 spread, sickly irradiated tint).
func scorch(pos: Vector2, count: int = 1) -> void:
	for i: int in range(count):
		if _stains.size() >= STAIN_MAX:
			_stains.pop_front()
		var life: float = 100.0 + randf() * 60.0
		_stains.append({
			"pos": pos + Vector2((randf() - 0.5) * 864.0,
				(randf() - 0.5) * 864.0),
			"life": life,
			"max_life": life,
			"size": 12.0 + randf() * 30.0,
			"alpha": 0.35,
			"rot": randf() * TAU,
			"nuclear": true,
		})
	_stain_layer.queue_redraw()
	_debug_decal_redraws["stain"] = int(_debug_decal_redraws["stain"]) + 1


## Grab a free slot (or steal the oldest busy one — pool never grows).
func _alloc(kind: String, pos: Vector2, life: float,
		radius: float = 0.0) -> void:
	var slot: Dictionary = {}
	for s: Dictionary in _pool:
		if not bool(s["busy"]):
			slot = s
			break
	if slot.is_empty():
		# Steal the oldest: find max age.
		var oldest: Dictionary = _pool[0]
		for s: Dictionary in _pool:
			if float(s["age"]) > float(oldest["age"]):
				oldest = s
		slot = oldest
	slot["busy"] = true
	slot["age"] = 0.0
	slot["life"] = life
	slot["kind"] = kind
	slot["radius"] = radius
	var n: _FxNode = slot["node"]
	n.position = pos
	n.visible = true


func hit_flash(pos: Vector2) -> void:
	_alloc("flash", pos, 0.18)


## Injured-unit blood drip (HTML bloodTrailCd parity): a few dark red
## droplets that sink and fade. Pooled like every other one-shot FX.
func blood(pos: Vector2) -> void:
	_alloc("blood", pos, 0.9, 5.0)


func death_poof(pos: Vector2) -> void:
	_alloc("poof", pos, 0.6, 26.0)


func explosion(pos: Vector2, radius: float) -> void:
	_alloc("boom", pos, 0.5, radius)


## Jeremy 2026-10-04: nuclear detonation visual — white-hot flash, fireball,
## rising mushroom column, dual shockwaves (HTML's green 780px + white
## 520px rings), nuclear crater, irradiated scorch field, fallout rain.
func nuke_blast(pos: Vector2) -> void:
	_alloc("nuke_blast", pos, 2.2, 420.0)
	_alloc("shockwave", pos, 2.2, 780.0)
	_alloc("shockwave2", pos, 1.6, 520.0)
	_alloc("fallout", pos, 3.0, 576.0)
	crater(pos, 320.0, true)
	scorch(pos, 55)


func muzzle(pos: Vector2) -> void:
	_alloc("muzzle", pos, 0.15, 14.0)


## Faction-unique combat visuals (Jeremy 2026-10-04: everything must have
## good graphics — no placeholder combat art).
func muzzle_big(pos: Vector2) -> void:
	_alloc("muzzle_big", pos, 0.22, 26.0)


func spell_fire(pos: Vector2) -> void:
	_alloc("spell_fire", pos, 0.4, 20.0)


func spell_lightning(pos: Vector2) -> void:
	_alloc("spell_lightning", pos, 0.3, 24.0)


func spell_arcane(pos: Vector2) -> void:
	_alloc("spell_arcane", pos, 0.45, 22.0)


func spell_nature(pos: Vector2) -> void:
	_alloc("spell_nature", pos, 0.5, 24.0)


## Jeremy 2026-10-04: Seven Dark Crystals — devastating dark magic visuals.
func dark_blast(pos: Vector2) -> void:
	_alloc("dark_blast", pos, 0.55, 30.0)


func dark_bolt(pos: Vector2) -> void:
	_alloc("dark_bolt", pos, 0.4, 28.0)


func hellfire(pos: Vector2) -> void:
	_alloc("hellfire", pos, 0.6, 32.0)


func sky_strike(pos: Vector2) -> void:
	_alloc("sky_strike", pos, 0.7, 40.0)


func snare_fx(pos: Vector2) -> void:
	_alloc("snare", pos, 0.8, 30.0)


func siege_hit(pos: Vector2) -> void:
	_alloc("siege_hit", pos, 0.6, 40.0)


## ---- wildfire visuals --------------------------------------------------
## One animated fire sprite per live fire record, driven by the world.
## Frames: assets/art/fx/fire_lg_0..9.png (HTML's animated fire set).

const FIRE_FRAMES := 10
const FIRE_FRAME_TIME := 0.09

static var _fire_tex: Array = []

## Wildfire flames are 64px frames drawn centered, so the sprite must sit
## half a frame-height above the ground point (gate 3, 2026-10-06) —
## otherwise the bottom half of the flame renders underground.
const FIRE_HALF_H := 32.0

var _fire_nodes: Dictionary = {}  # fire_id -> {sprite, age}


static func _load_fire_frames() -> void:
	if not _fire_tex.is_empty():
		return
	for i: int in range(FIRE_FRAMES):
		var t: Texture2D = load("res://assets/art/fx/fire_lg_%d.png" % i) \
			as Texture2D
		_fire_tex.append(t)


func spawn_fire(fire_id: int, pos: Vector2) -> void:
	_load_fire_frames()
	if _fire_nodes.has(fire_id):
		return
	var root := Node2D.new()
	root.position = pos
	var spr := Sprite2D.new()
	if not _fire_tex.is_empty() and _fire_tex[0] != null:
		spr.texture = _fire_tex[0]
	# Park the flame's base on the ground point; update_fire keeps it
	# bottom-aligned as intensity rescales it.
	spr.position = Vector2(0, -FIRE_HALF_H * 0.35)
	root.add_child(spr)
	add_child(root)
	_fire_nodes[fire_id] = {"root": root, "sprite": spr, "age": 0.0}


func update_fire(fire_id: int, intensity: float, delta: float) -> void:
	var slot: Dictionary = _fire_nodes.get(fire_id, {})
	if slot.is_empty():
		return
	slot["age"] = float(slot["age"]) + delta
	var frame: int = int(float(slot["age"]) / FIRE_FRAME_TIME) % FIRE_FRAMES
	var spr: Sprite2D = slot["sprite"]
	if frame < _fire_tex.size() and _fire_tex[frame] != null:
		spr.texture = _fire_tex[frame]
	# Bigger fire = bigger sprite. Keep the flame's base on the ground
	# point as the centered 64px frame rescales (gate 3, 2026-10-06).
	var s: float = 0.35 + intensity / 100.0 * 0.85
	spr.scale = Vector2(s, s)
	spr.position = Vector2(0, -FIRE_HALF_H * s)


func clear_fire(fire_id: int) -> void:
	var slot: Dictionary = _fire_nodes.get(fire_id, {})
	if slot.is_empty():
		return
	(slot["root"] as Node).queue_free()
	_fire_nodes.erase(fire_id)


## ---- Burning-building fire visuals (HTML c59 parity) ---------------------
## Buildings whose sim record has on_fire == true (sim/disasters.gd) get an
## animated fire sprite on the roof plus the HTML's c59 smoke system:
## faction-tinted smoke puffs (alive cap 5, spawn rate dt*(1.4+bs)) and rising
## embers (alive cap 7, spawn rate dt*(2.0+bs)), where
##   bs = max(0.8, 1 - hp/maxHp + 0.8)
## so damaged buildings smoke harder. Smoke integration is the HTML's exact
## formula (c59UpdateParticles):
##   vx += wind.x*26*windK*dt; vy += wind.y*26*windK*dt; vy -= rise*dt;
##   x += vx*dt; y += vy*dt; size += grow*dt.
## Draw alpha envelope matches c59DrawParticle: aIn = min(1,t/0.15),
## aOut = 1-t, a = alpha * min(aIn,aOut); dark fires (bs >= 2) get denser
## smoke (a = min(0.62, a*1.35)).
##
## Pools are fixed at spawn (5 smoke + 7 embers per building, never allocate
## in _process); the world caps live building fires at MAX_BUILDING_FIRES.

const BUILDING_SMOKE_CAP := 5   # HTML C59_PER_FIRE.smoke
const BUILDING_EMBER_CAP := 7   # HTML C59_PER_FIRE.ember
const MAX_BUILDING_FIRES := 24  # world-level perf cap

## HTML _smokeTints verbatim (faction -> smoke core color). The HTML keyed
## tints by singular faction ("elf"); the Godot port uses plural keys
## ("elves", main_menu.gd FACTION_INFO), so both forms map to the same tint.
const SMOKE_TINTS := {
	"elf": Color8(150, 230, 190), "elves": Color8(150, 230, 190),
	"ogre": Color8(255, 150, 120), "ogres": Color8(255, 150, 120),
	"gnome": Color8(240, 220, 150), "gnomes": Color8(240, 220, 150),
	"human": Color8(212, 216, 221), "humans": Color8(212, 216, 221),
	"undead": Color8(180, 180, 200),
}

var _building_fires: Dictionary = {}  # building_id -> _BuildingFire
## Graphics-tier particle multiplier (HTML particleMul parity): gates smoke
## and ember spawns for building fires.
var building_fx_mul := 1.0


func set_building_fx_mul(m: float) -> void:
	building_fx_mul = clampf(m, 0.05, 1.0)


## Start the burn visuals for a building. Idempotent; capped at
## MAX_BUILDING_FIRES live fires.
func spawn_building_fire(building_id: int, pos: Vector2, faction: String,
		intensity: float) -> void:
	_load_fire_frames()
	if _building_fires.has(building_id):
		return
	if _building_fires.size() >= MAX_BUILDING_FIRES:
		return
	var bf := _BuildingFire.new()
	bf.setup(pos, SMOKE_TINTS.get(faction, SMOKE_TINTS["human"]),
		intensity, self)
	add_child(bf)
	_building_fires[building_id] = bf


## Per-frame driver (called by the world): damage intensity + wind.
func update_building_fire(building_id: int, intensity: float,
		wind: Vector2) -> void:
	var bf: _BuildingFire = _building_fires.get(building_id) as _BuildingFire
	if bf == null:
		return
	bf.set_intensity(intensity)
	bf.set_wind(wind)


func has_building_fire(building_id: int) -> bool:
	return _building_fires.has(building_id)


func building_fire_count() -> int:
	return _building_fires.size()


func building_fire_ids() -> Array:
	return _building_fires.keys()


func building_fire(building_id: int) -> _BuildingFire:
	return _building_fires.get(building_id) as _BuildingFire


func clear_building_fire(building_id: int) -> void:
	var bf: _BuildingFire = _building_fires.get(building_id) as _BuildingFire
	if bf == null:
		return
	bf.queue_free()
	_building_fires.erase(building_id)


func clear_all_building_fires() -> void:
	for bid in _building_fires.keys():
		(_building_fires[bid] as _BuildingFire).queue_free()
	_building_fires.clear()


## One burning building: fire sprite + pooled c59 smoke and embers.
class _BuildingFire:
	extends Node2D
	# HTML c59 numbers.
	const SMOKE_WINDK := 2.2
	const SMOKE_RISE := 4.0
	const SMOKE_GROW := 9.0
	const EMBER_WINDK := 1.4
	const EMBER_RISE := 6.0
	const SMOKE_ANCHOR := Vector2(0, -20)  # HTML: b.y - 20 spawn origin

	var _sprite: Sprite2D
	var _age := 0.0
	var _bs := 1.0       # intensity: max(0.8, 1 - hp/maxHp + 0.8)
	# 2026-10-04 perf: fire frame only changes at ~11Hz (FIRE_FRAME_TIME);
	# writing _sprite.texture/scale every frame (60Hz) dirties the canvas
	# item 5x more than needed. Cache the last written frame index and
	# only write when the frame or the intensity changes. Visuals identical.
	var _last_frame := -1
	var _tint := Color.WHITE
	var _wind := Vector2.ZERO
	var _fx: CombatFX = null
	var _smoke: Array = []
	var _embers: Array = []
	var _rng := RandomNumberGenerator.new()

	func setup(pos: Vector2, tint: Color, intensity: float, fx: CombatFX) -> void:
		position = pos
		_tint = tint
		_fx = fx
		_rng.seed = 90210
		_bs = maxf(0.8, intensity)
		_sprite = Sprite2D.new()
		_sprite.position = Vector2(0, -30)  # roof, under the smoke
		add_child(_sprite)
		for i in CombatFX.BUILDING_SMOKE_CAP:
			_smoke.append({"alive": false, "p": Vector2.ZERO,
				"vx": 0.0, "vy": 0.0, "age": 0.0, "life": 1.0,
				"max_life": 1.0, "size": 16.0, "alpha": 0.3,
				"dark": false})
		for i in CombatFX.BUILDING_EMBER_CAP:
			_embers.append({"alive": false, "p": Vector2.ZERO,
				"vx": 0.0, "vy": 0.0, "age": 0.0, "life": 1.0,
				"max_life": 1.0, "size": 2.0, "seed": 0.0})

	func set_intensity(i: float) -> void:
		_bs = maxf(0.8, i)
		# Intensity feeds the fire scale; re-apply immediately so the
		# per-frame _animate_fire doesn't have to write it every frame.
		if _last_frame >= 0:
			_apply_fire_scale()

	## Writes the intensity-derived fire sprite scale (once per change,
	## not once per frame).
	func _apply_fire_scale() -> void:
		if _sprite == null:
			return
		var s: float = 0.45 + 0.2 * _bs
		_sprite.scale = Vector2(s, s)

	func set_wind(w: Vector2) -> void:
		_wind = w

	## Test/debug hooks.
	func alive_smoke() -> int:
		return _count_alive(_smoke)

	func alive_embers() -> int:
		return _count_alive(_embers)

	func fire_sprite_scale() -> float:
		return _sprite.scale.x if _sprite != null else 0.0

	func _count_alive(pool: Array) -> int:
		var n := 0
		for s in pool:
			if bool(s["alive"]):
				n += 1
		return n

	func _process(delta: float) -> void:
		_age += delta
		_animate_fire()
		var mul: float = _fx.building_fx_mul if _fx != null else 1.0
		# HTML rates: smoke dt*(1.4+bs), embers dt*(2.0+bs). Two independent
		# gate rolls mirror the weather/river layers' particleMul gating.
		if _rng.randf() < mul and _rng.randf() < delta * (1.4 + _bs):
			_spawn_smoke()
		if _rng.randf() < mul and _rng.randf() < delta * (2.0 + _bs):
			_spawn_ember()
		_integrate(_smoke, SMOKE_WINDK, SMOKE_RISE, SMOKE_GROW, delta)
		_integrate(_embers, EMBER_WINDK, EMBER_RISE, 0.0, delta)
		queue_redraw()

	func _animate_fire() -> void:
		if _sprite == null or CombatFX._fire_tex.is_empty():
			return
		var frame: int = int(_age / CombatFX.FIRE_FRAME_TIME) \
			% CombatFX.FIRE_FRAMES
		if frame == _last_frame:
			return  # same frame: texture + scale already written
		if frame < CombatFX._fire_tex.size() \
				and CombatFX._fire_tex[frame] != null:
			_sprite.texture = CombatFX._fire_tex[frame]
			_last_frame = frame
			_apply_fire_scale()

	func _spawn_smoke() -> void:
		var s := _free_slot(_smoke)
		if s.is_empty():
			return
		var a := SMOKE_ANCHOR
		s["p"] = a + Vector2(_rng.randf_range(-13.0, 13.0),
			-14.0 - _rng.randf() * 10.0)
		s["vx"] = _rng.randf_range(-4.0, 4.0) + _wind.x * 14.0
		s["vy"] = -(16.0 + _rng.randf() * 14.0)
		s["age"] = 0.0
		s["max_life"] = 4.2
		s["life"] = _rng.randf_range(2.6, 4.2)
		s["size"] = 16.0 + _rng.randf() * 8.0 + _bs * 3.0
		s["alpha"] = 0.30 + minf(0.22, _bs * 0.07)
		s["dark"] = _bs >= 2.0
		s["alive"] = true

	func _spawn_ember() -> void:
		var e := _free_slot(_embers)
		if e.is_empty():
			return
		var a := SMOKE_ANCHOR
		e["p"] = a + Vector2(_rng.randf_range(-15.0, 15.0),
			-10.0 - _rng.randf() * 26.0)
		e["vx"] = _rng.randf_range(-7.0, 7.0) + _wind.x * (10.0 + _bs * 8.0)
		e["vy"] = -(34.0 + _rng.randf() * 34.0)
		e["age"] = 0.0
		e["max_life"] = 1.7
		e["life"] = _rng.randf_range(0.8, 1.7)
		e["size"] = 1.6 + _rng.randf() * 1.8
		e["seed"] = _rng.randf() * 10.0
		e["alive"] = true

	func _free_slot(pool: Array) -> Dictionary:
		for s in pool:
			if not bool(s["alive"]):
				return s
		return {}

	func _integrate(pool: Array, wind_k: float, rise: float, grow: float,
			delta: float) -> void:
		for s in pool:
			if not bool(s["alive"]):
				continue
			s["age"] = float(s["age"]) + delta
			if float(s["age"]) >= float(s["life"]):
				s["alive"] = false
				continue
			# HTML c59 integration, verbatim.
			var vx: float = float(s["vx"]) + _wind.x * 26.0 * wind_k * delta
			var vy: float = float(s["vy"]) + _wind.y * 26.0 * wind_k * delta \
				- rise * delta
			s["vx"] = vx
			s["vy"] = vy
			s["p"] = (s["p"] as Vector2) + Vector2(vx, vy) * delta
			s["size"] = float(s["size"]) + grow * delta

	func _draw() -> void:
		for s in _smoke:
			if not bool(s["alive"]):
				continue
			var sp: Vector2 = s["p"]
			var t: float = clampf(float(s["age"]) / float(s["max_life"]),
				0.0, 1.0)
			var a_in: float = minf(1.0, t / 0.15)
			var a_out: float = 1.0 - t
			var a: float = float(s["alpha"]) * minf(a_in, a_out)
			var dark: bool = bool(s["dark"])
			if dark:
				a = minf(0.62, a * 1.35)
			var r: float = float(s["size"])
			# Outer wisp: neutral gray fade (HTML gradient's mid/edge stops).
			draw_circle(sp, r, Color(0.62, 0.65, 0.68, a * 0.35))
			# Core: faction tint melting into gray (HTML's tinted core stop).
			var core := _tint.lerp(Color(0.62, 0.65, 0.68), 0.55)
			draw_circle(sp, r * 0.55, Color(core, a))
			if dark:
				draw_circle(sp, r * 0.4, Color(0.25, 0.24, 0.23, a * 0.5))
		for e in _embers:
			if not bool(e["alive"]):
				continue
			var ep: Vector2 = e["p"]
			var t2: float = clampf(float(e["age"]) / float(e["max_life"]),
				0.0, 1.0)
			var flick: float = 0.75 + 0.25 * sin(float(e["age"]) * 40.0
				+ float(e["seed"]) * 10.0)
			var a2: float = 0.95 * (1.0 - t2) * flick
			var r2: float = float(e["size"])
			draw_circle(ep, r2 * 1.8, Color(1.0, 0.45, 0.1, a2 * 0.5))
			draw_circle(ep, r2 * 0.8, Color(1.0, 0.85, 0.4, a2))


## Live fire positions (world space) for lights/embers. Pooled consumers
## (LightingRig, AmbientFX) call this ~1Hz; never allocates per call.
func fire_positions() -> PackedVector2Array:
	var out := PackedVector2Array()
	for key in _fire_nodes:
		var slot: Dictionary = _fire_nodes[key]
		var root: Node2D = slot.get("root")
		if root != null and is_instance_valid(root):
			out.append(root.position)
	return out


## Inner draw node — one class, kind-driven _draw, no textures.
class _FxNode:
	extends Node2D
	var fx_age := 0.0
	var fx_life := 1.0
	var fx_kind := ""
	var fx_radius := 0.0

	func _draw() -> void:
		var k: float = clampf(fx_age / maxf(fx_life, 0.001), 0.0, 1.0)
		match fx_kind:
			"flash":
				var r: float = 14.0 * (1.0 - k) + 4.0
				draw_circle(Vector2.ZERO, r,
					Color(1.0, 0.4, 0.3, 0.8 * (1.0 - k)))
				draw_circle(Vector2.ZERO, r * 0.5,
					Color(1.0, 0.9, 0.8, 0.9 * (1.0 - k)))
			"poof":
				# Rising, expanding grey puffs (smoke frames are the
				# M7-polish version; _draw puffs hold the fort).
				for i: int in range(5):
					var t: float = fmod(k * 1.2 + float(i) * 0.2, 1.0)
					var px: float = sin(float(i) * 2.4) * 14.0 * t
					var py: float = -30.0 * t
					draw_circle(Vector2(px, py), 4.0 + 10.0 * t,
						Color(0.6, 0.6, 0.62, 0.5 * (1.0 - t)))
			"boom":
				var r: float = fx_radius * (0.3 + 0.7 * k)
				draw_circle(Vector2.ZERO, r, Color(1.0, 0.5, 0.15, 0.55 * (1.0 - k)))
				draw_circle(Vector2.ZERO, r * 0.6, Color(1.0, 0.8, 0.3, 0.7 * (1.0 - k)))
				draw_arc(Vector2.ZERO, r + 6.0, 0.0, TAU,
					24, Color(1, 1, 1, 0.6 * (1.0 - k)), 3.0)
			"muzzle":
				var r: float = fx_radius * (1.0 - k)
				draw_circle(Vector2.ZERO, r, Color(1.0, 0.85, 0.4, 0.8 * (1.0 - k)))
			"muzzle_big":
				# Musketeer: bigger, brighter muzzle blast + smoke ring.
				var r2: float = fx_radius * (1.0 - k)
				draw_circle(Vector2.ZERO, r2, Color(1.0, 0.9, 0.5, 0.9 * (1.0 - k)))
				draw_circle(Vector2.ZERO, r2 * 0.5, Color(1.0, 1.0, 0.9, 1.0 * (1.0 - k)))
				draw_arc(Vector2.ZERO, r2 + 8.0 * k, 0.0, TAU,
					20, Color(0.7, 0.7, 0.7, 0.5 * (1.0 - k)), 4.0)
			"spell_fire":
				# Mage fireball: roiling orange core + red rim.
				var r3: float = fx_radius * (0.5 + 0.5 * k)
				draw_circle(Vector2.ZERO, r3, Color(1.0, 0.35, 0.1, 0.7 * (1.0 - k)))
				draw_circle(Vector2.ZERO, r3 * 0.6, Color(1.0, 0.7, 0.2, 0.9 * (1.0 - k)))
				draw_circle(Vector2.ZERO, r3 * 0.3, Color(1.0, 0.95, 0.6, 1.0 * (1.0 - k)))
			"spell_lightning":
				# Mage lightning: jagged white-blue bolt.
				var segs := 5
				var prev := Vector2(0, -fx_radius)
				for i: int in range(1, segs + 1):
					var t: float = float(i) / float(segs)
					var off: float = sin(float(i) * 3.7 + fx_age * 40.0) * 8.0 * (1.0 - k)
					var pt := Vector2(off, -fx_radius + 2.0 * fx_radius * t)
					draw_line(prev, pt, Color(0.7, 0.9, 1.0, 0.95 * (1.0 - k)), 3.0)
					prev = pt
				draw_circle(Vector2.ZERO, 6.0 * (1.0 - k),
					Color(1.0, 1.0, 1.0, 0.9 * (1.0 - k)))
			"spell_arcane":
				# Mage arcane: swirling purple runes.
				var r4: float = fx_radius * (0.4 + 0.6 * k)
				draw_circle(Vector2.ZERO, r4, Color(0.6, 0.2, 0.9, 0.6 * (1.0 - k)))
				draw_arc(Vector2.ZERO, r4 * 0.7, fx_age * 6.0, fx_age * 6.0 + 4.2,
					18, Color(0.8, 0.4, 1.0, 0.8 * (1.0 - k)), 2.5)
				draw_arc(Vector2.ZERO, r4 * 0.4, -fx_age * 8.0, -fx_age * 8.0 + 3.5,
					14, Color(0.9, 0.6, 1.0, 0.9 * (1.0 - k)), 2.0)
			"spell_nature":
				# Warlock: blooming green nature magic + spirit wisps.
				var r5: float = fx_radius * (0.3 + 0.7 * k)
				draw_circle(Vector2.ZERO, r5, Color(0.2, 0.8, 0.3, 0.55 * (1.0 - k)))
				for i: int in range(4):
					var ang: float = float(i) * PI / 2.0 + fx_age * 3.0
					var wp := Vector2(cos(ang), sin(ang)) * r5 * 0.8
					draw_circle(wp, 5.0 * (1.0 - k),
						Color(0.5, 1.0, 0.5, 0.85 * (1.0 - k)))
			# Jeremy 2026-10-04: Seven Dark Crystals — devastating dark magic.
			"dark_blast":
				# Unholy detonation: black-violet core, purple rim, shockwave.
				var rd: float = fx_radius * (0.5 + 0.5 * k)
				draw_circle(Vector2.ZERO, rd, Color(0.08, 0.02, 0.12, 0.85 * (1.0 - k)))
				draw_circle(Vector2.ZERO, rd * 0.65, Color(0.45, 0.15, 0.75, 0.9 * (1.0 - k)))
				draw_circle(Vector2.ZERO, rd * 0.3, Color(0.85, 0.6, 1.0, 1.0 * (1.0 - k)))
				draw_arc(Vector2.ZERO, rd + 10.0 * k, 0.0, TAU,
					22, Color(0.6, 0.3, 0.9, 0.6 * (1.0 - k)), 4.0)
			"dark_bolt":
				# Dark lightning: jagged violet-black bolt.
				var segs2 := 5
				var prev2 := Vector2(0, -fx_radius)
				for i: int in range(1, segs2 + 1):
					var t2: float = float(i) / float(segs2)
					var off2: float = sin(float(i) * 3.7 + fx_age * 40.0) * 8.0 * (1.0 - k)
					var pt2 := Vector2(off2, -fx_radius + 2.0 * fx_radius * t2)
					draw_line(prev2, pt2, Color(0.55, 0.25, 0.95, 0.95 * (1.0 - k)), 3.5)
					prev2 = pt2
				draw_circle(Vector2.ZERO, 6.0 * (1.0 - k),
					Color(0.8, 0.5, 1.0, 0.9 * (1.0 - k)))
			"hellfire":
				# Unholy hellfire: blood-red core, black smoke rim.
				var rh: float = fx_radius * (0.5 + 0.5 * k)
				draw_circle(Vector2.ZERO, rh, Color(0.35, 0.03, 0.02, 0.8 * (1.0 - k)))
				draw_circle(Vector2.ZERO, rh * 0.65, Color(0.9, 0.12, 0.05, 0.9 * (1.0 - k)))
				draw_circle(Vector2.ZERO, rh * 0.3, Color(1.0, 0.55, 0.15, 1.0 * (1.0 - k)))
			"sky_strike":
				# Worldender: a column of sky-fire slamming down.
				var rs: float = fx_radius * (1.0 - k)
				draw_rect(Rect2(-10.0 * rs, -fx_radius * 2.0, 20.0 * rs, fx_radius * 4.0),
					Color(0.9, 0.9, 1.0, 0.55 * (1.0 - k)))
				draw_rect(Rect2(-4.0 * rs, -fx_radius * 2.0, 8.0 * rs, fx_radius * 4.0),
					Color(1.0, 1.0, 1.0, 0.9 * (1.0 - k)))
				# Impact flash where the column strikes.
				draw_circle(Vector2.ZERO, rs * 1.2, Color(0.7, 0.6, 1.0, 0.7 * (1.0 - k)))
				draw_circle(Vector2.ZERO, rs * 0.6, Color(1.0, 1.0, 1.0, 0.9 * (1.0 - k)))
			# Jeremy 2026-10-04: nuclear warfare — detonation visuals.
			"nuke_blast":
				# White-hot flash, then the fireball and rising mushroom column.
				var flash_k: float = clampf(k / 0.12, 0.0, 1.0)
				if flash_k < 1.0:
					var fr: float = fx_radius * (0.4 + 0.6 * flash_k)
					draw_circle(Vector2.ZERO, fr,
						Color(1.0, 1.0, 1.0, 0.95 * (1.0 - flash_k)))
				var br: float = fx_radius * (1.0 - 0.35 * k)
				draw_circle(Vector2.ZERO, br,
					Color(1.0, 0.45, 0.1, 0.75 * (1.0 - k)))
				draw_circle(Vector2.ZERO, br * 0.62,
					Color(1.0, 0.75, 0.25, 0.9 * (1.0 - k)))
				draw_circle(Vector2.ZERO, br * 0.3,
					Color(1.0, 0.97, 0.8, 1.0 * (1.0 - k)))
				var rise: float = 260.0 * k
				var stem_w: float = 60.0 + 90.0 * k
				draw_rect(Rect2(-stem_w * 0.5, -rise - 40.0, stem_w, rise + 40.0),
					Color(0.35, 0.3, 0.28, 0.55 * (1.0 - k)))
				var cap_r: float = 90.0 + 160.0 * k
				var cap_c := Vector2(0, -rise - 40.0)
				draw_circle(cap_c, cap_r,
					Color(0.45, 0.38, 0.33, 0.6 * (1.0 - k)))
				draw_circle(cap_c, cap_r * 0.6,
					Color(1.0, 0.55, 0.2, 0.5 * (1.0 - k) * (1.0 - k)))
			"shockwave":
				# HTML green shockwave ring (120,255,80), 30 -> 780 px.
				var swr: float = 30.0 + (fx_radius - 30.0) * k
				draw_arc(Vector2.ZERO, swr, 0.0, TAU, 48,
					Color(0.47, 1.0, 0.31, 0.7 * (1.0 - k)),
					14.0 * (1.0 - k) + 2.0)
			"shockwave2":
				# HTML white-yellow shockwave ring (255,255,200), 10 -> 520 px.
				var swr2: float = 10.0 + (fx_radius - 10.0) * k
				draw_arc(Vector2.ZERO, swr2, 0.0, TAU, 40,
					Color(1.0, 1.0, 0.78, 0.6 * (1.0 - k)),
					10.0 * (1.0 - k) + 2.0)
			"fallout":
				# HTML falloutDrops: glowing green motes drifting down.
				for i: int in range(28):
					var fi: float = float(i)
					var fx0: float = (fmod(fi * 137.31, 1.0) - 0.5) * 2.0 * fx_radius * 0.8
					var fall: float = fmod(k * 1.4 + fmod(fi * 0.618, 1.0), 1.0)
					var fy: float = -160.0 + fall * 220.0
					var glow: float = 0.5 + 0.5 * sin(fx_age * 9.0 + fi)
					draw_circle(Vector2(fx0, fy), 3.0,
						Color(0.55, 1.0, 0.35, (0.5 + 0.4 * glow) * (1.0 - k)))
			"snare":
				# Spellweaver: cyan web that tightens.
				var r6: float = fx_radius * (1.0 - 0.4 * k)
				for i: int in range(6):
					var a1: float = float(i) * TAU / 6.0
					var a2: float = float(i + 1) * TAU / 6.0
					draw_line(Vector2(cos(a1), sin(a1)) * r6,
						Vector2(cos(a2), sin(a2)) * r6,
						Color(0.3, 0.9, 1.0, 0.7 * (1.0 - k)), 2.0)
					draw_line(Vector2.ZERO,
						Vector2(cos(a1), sin(a1)) * r6,
						Color(0.3, 0.9, 1.0, 0.5 * (1.0 - k)), 1.5)
			"siege_hit":
				# Building impact: dust burst + debris chunks + shockwave.
				var r7: float = fx_radius * (0.2 + 0.8 * k)
				draw_circle(Vector2.ZERO, r7, Color(0.75, 0.7, 0.6, 0.5 * (1.0 - k)))
				draw_arc(Vector2.ZERO, r7 + 4.0, 0.0, TAU,
					22, Color(0.9, 0.85, 0.75, 0.6 * (1.0 - k)), 3.0)
				for i: int in range(7):
					var da: float = float(i) * TAU / 7.0 + 0.4
					var dp := Vector2(cos(da), sin(da)) * r7 * (0.5 + 0.5 * k)
					var ds: float = 3.0 + fmod(float(i) * 2.3, 4.0)
					draw_circle(dp, ds * (1.0 - k * 0.5),
						Color(0.55, 0.5, 0.42, 0.8 * (1.0 - k)))
			"blood":
				# Halo 1 style: chunky distinct droplets that pop — bright
				# vibrant red, larger and more separated than a fine mist.
				# Droplet offsets derive from the spawn position so pooled
				# re-use stays deterministic (no per-spawn RNG in _draw).
				var bseed: float = fmod(absf(position.x * 12.9898 + position.y * 78.233), 10.0)
				for i: int in range(6):
					var ba: float = bseed + float(i) * 1.7
					var bdp := Vector2(sin(ba * 3.1) * 10.0,
						-10.0 * k + cos(ba * 2.3) * 6.0)
					var bsz: float = (4.2 - 0.6 * float(i % 3)) * (1.0 - k) + 1.2
					draw_circle(bdp, bsz,
						Color(HALO_BLOOD.r, HALO_BLOOD.g, HALO_BLOOD.b,
							0.95 * (1.0 - k)))
					# Bright specular dot — Halo's juicy highlight.
					draw_circle(bdp + Vector2(-1.0, -1.0), bsz * 0.35,
						Color(1.0, 0.45, 0.45, 0.8 * (1.0 - k)))


## Draws the persistent blood-stain decals (Halo 1 style: bright vibrant
## red chunky splatter — a main blob plus satellite droplets, pools spread
## outward over ~1.2 s after landing, then hold and fade with life).
class _StainLayer:
	extends Node2D
	var fx: CombatFX

	func _draw() -> void:
		if fx == null:
			return
		for s: Dictionary in fx._stains:
			var life: float = float(s["life"])
			var max_life: float = float(s["max_life"])
			var fade: float = clampf(life / maxf(max_life, 0.001), 0.0, 1.0)
			var a: float = float(s["alpha"]) * fade
			if a <= 0.01:
				continue
			# Halo pools spread: grow from 55% to full size over 1.2 s.
			var age: float = max_life - life
			var spread: float = 0.55 + 0.45 * clampf(age / 1.2, 0.0, 1.0)
			var sz: float = float(s["size"]) * spread
			var col := Color(HALO_STAIN.r, HALO_STAIN.g, HALO_STAIN.b, a)
			if bool(s.get("nuclear", false)):
				# Irradiated scorch: HTML bloodStains nuclear fill '#a5d6a7'
				# (light sickly green), alpha (0.25 + scorch*0.25) * fade.
				col = Color(0.647, 0.839, 0.655, a)
			var rot: float = float(s["rot"])
			draw_set_transform(s["pos"], rot, Vector2(1.0, 0.62))
			# Main blob.
			draw_circle(Vector2.ZERO, sz, col)
			# Chunky satellite droplets (deterministic from rot).
			for j: int in range(3):
				var sa: float = rot + float(j) * 2.1 + 0.7
				var sd := Vector2(cos(sa), sin(sa)) * sz * (0.95 + 0.25 * float(j))
				draw_circle(sd, sz * (0.38 - 0.09 * float(j)), col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws gore pieces (Halo 1 style): flesh chunks and limbs as bright
## vibrant-red blobs, metal as grey rects with dark outline. Pieces fade out
## over their last 2 seconds.
class _GoreLayer:
	extends Node2D
	var fx: CombatFX

	func _draw() -> void:
		if fx == null:
			return
		for g: Dictionary in fx._gore:
			var age: float = float(g["age"])
			var life: float = float(g["life"])
			var a: float = clampf((life - age) / 2.0, 0.0, 1.0) * 0.95
			if a <= 0.01:
				continue
			var sz: float = float(g["size"])
			var kind: String = String(g["kind"])
			draw_set_transform(g["pos"], float(g["rot"]), Vector2.ONE)
			if kind == "metal":
				draw_rect(Rect2(-sz * 0.5, -sz * 0.25, sz, sz * 0.5),
					Color(0.474, 0.643, 0.682, a))
				draw_rect(Rect2(-sz * 0.5, -sz * 0.25, sz, sz * 0.5),
					Color(0.216, 0.278, 0.31, a), false, 1.0)
			else:
				var gcol := Color(HALO_GORE.r, HALO_GORE.g, HALO_GORE.b, a)
				draw_set_transform(g["pos"], float(g["rot"]),
					Vector2(1.0, 0.7))
				draw_circle(Vector2.ZERO, sz, gcol)
				# Halo highlight — juicy specular pop on the chunk.
				draw_circle(Vector2(-sz * 0.25, -sz * 0.2), sz * 0.3,
					Color(1.0, 0.4, 0.4, a * 0.7))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws gibbed chibi body parts (Halo 1 style): head = skin-tone circle
## with dot eyes, torso = faction-color rounded mass, arms/legs = skin
## capsules with bloody ends. Fade over the last 1.5 s.
class _GibLayer:
	extends Node2D
	var fx: CombatFX

	func _draw() -> void:
		if fx == null:
			return
		for g: Dictionary in fx._gibs:
			var age: float = float(g["age"])
			var life: float = float(g["life"])
			var a: float = clampf((life - age) / 1.5, 0.0, 1.0)
			if a <= 0.01:
				continue
			var sz: float = float(g["size"])
			var part: String = String(g["part"])
			var fcol: Color = g["fcol"]
			var skin: Color = g["skin"]
			fcol.a = a
			skin.a = a
			var blood := Color(0.92, 0.10, 0.13, a)
			draw_set_transform(g["pos"], float(g["rot"]), Vector2.ONE)
			match part:
				"head":
					# Chibi head: skin ball + dot eyes + bloody base.
					draw_circle(Vector2.ZERO, sz * 0.62, skin)
					draw_circle(Vector2(-sz * 0.2, -sz * 0.1), sz * 0.09,
						Color(0.1, 0.1, 0.12, a))
					draw_circle(Vector2(sz * 0.2, -sz * 0.1), sz * 0.09,
						Color(0.1, 0.1, 0.12, a))
					draw_circle(Vector2(0, sz * 0.42), sz * 0.34, blood)
				"torso":
					# Faction-color torso mass with blood smear.
					draw_circle(Vector2.ZERO, sz * 0.66, fcol)
					draw_circle(Vector2(sz * 0.15, -sz * 0.1), sz * 0.4,
						blood)
					draw_circle(Vector2(-sz * 0.3, sz * 0.2), sz * 0.22,
						Color(1.0, 0.42, 0.42, a * 0.8))
				_:
					# Arm / leg: skin capsule with a bloody severed end.
					var dir := Vector2(1, 0.3).normalized()
					draw_line(-dir * sz * 0.5, dir * sz * 0.5, skin, sz * 0.5)
					draw_circle(-dir * sz * 0.5, sz * 0.28, blood)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Draws cartoon craters: dark scorched bowl, thick raised rim (lighter
## brown ring), debris dots. Pure terrain — no aging, persists.
class _CraterLayer:
	extends Node2D
	var fx: CombatFX

	func _draw() -> void:
		if fx == null:
			return
		for c: Dictionary in fx._craters:
			var p: Vector2 = c["pos"]
			var r: float = float(c["radius"])
			var seed: float = float(c["seed"])
			# Raised cartoon rim: thick lighter-brown ring.
			draw_set_transform(p, 0.0, Vector2(1.0, 0.62))
			draw_arc(Vector2.ZERO, r, 0.0, TAU, 40,
				Color(0.42, 0.30, 0.20, 0.95), 10.0)
			draw_arc(Vector2.ZERO, r - 6.0, 0.0, TAU, 40,
				Color(0.55, 0.40, 0.27, 0.9), 4.0)
			# Scorched bowl.
			draw_circle(Vector2.ZERO, r - 10.0, Color(0.16, 0.11, 0.08, 0.96))
			draw_circle(Vector2.ZERO, (r - 10.0) * 0.7,
				Color(0.10, 0.07, 0.05, 0.96))
			# Cartoon inner highlight arc.
			draw_arc(Vector2.ZERO, (r - 10.0) * 0.45, PI * 1.15, PI * 1.65,
				16, Color(0.35, 0.25, 0.16, 0.7), 3.0)
			if bool(c.get("nuclear", false)):
				# Ground zero: sickly green radioactive rim glow.
				draw_arc(Vector2.ZERO, r + 4.0, 0.0, TAU, 40,
					Color(0.45, 1.0, 0.35, 0.8), 5.0)
				draw_arc(Vector2.ZERO, r - 14.0, 0.0, TAU, 36,
					Color(0.35, 0.9, 0.3, 0.35), 8.0)
			# Debris chunks around the rim (deterministic from seed).
			for j: int in range(7):
				var da: float = seed + float(j) * 0.9
				var dp := Vector2(cos(da), sin(da)) * (r + 4.0 + fmod(float(j) * 7.0, 10.0))
				draw_circle(dp, 3.0 + fmod(float(j) * 3.3, 4.0),
					Color(0.38, 0.27, 0.18, 0.9))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
