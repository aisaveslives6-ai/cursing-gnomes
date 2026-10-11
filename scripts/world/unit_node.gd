class_name UnitNode
extends Node2D
## Cursing Gnomes — unit visual: real chibi pixel-art sprite + choreography.
##
## Art is the HTML build's sprite set (assets/art/units/, 96 sprites:
## 4 factions x worker/warrior/ranger/mage x m/f x 2 variants), picked by
## Art.appearance_key() — a port of the HTML's appearanceKey54().
##
## Animation law: the UnitNode position is owned by sim/world movement ONLY.
## The UnitAnimator drives the Body child (feet pivot): bounce lift, forward
## rock, squash. The sprite texture is never scrolled/panned/translated to
## fake frames — discrete choreography states, one clip at a time.


## Target on-screen sprite height in px (chibi are ~192 px source).
const SPRITE_WORLD_H := 44.0

## Jeremy 2026-10-04: preloaded (not class_name-resolved) so headless
## single-script --check-only runs see it before the editor's global class
## cache is regenerated. JesusArt still declares class_name for the editor.
const JesusArtScript := preload("res://scripts/world/jesus_art.gd")

## 2026-10-05: preloaded (not class_name-resolved) so headless single-script
## --check-only runs see it before the editor's global class cache is
## regenerated — same pattern as JesusArtScript above.
const _FLASH_SHADER: Shader = preload("res://assets/shaders/hurt_flash.gdshader")

## 2026-10-06: procedural normal maps (CanvasTexture wraps) so the
## PointLight2D rig shades sprites directionally. Preloaded for the same
## headless reason as above. apply_to() is a no-op when already wrapped.
const SpriteNormalsScript := preload("res://scripts/world/sprite_normals.gd")

var unit_id := -1
var faction := ""
var job := ""
var gender := "m"

var anim: UnitAnimator
var _body: Node2D
var _sprite: Sprite2D
# Jeremy 2026-10-05: thought bubbles REMOVED (all bubbles removed at
# Jeremy's call) — the _tag ActivityBubble system is gone entirely.
var _last_px: float = 0.0
var _shadow_key: int = 0  # quantized shadow state; queue_redraw() on change
# Jeremy 2026-10-04: off-screen culling — _process is disabled when the
# unit is outside the camera view (set by the world sync). Position is
# still driven by the world; only the animation loop pauses.

## Jeremy 2026-10-04: work-animation tool overlay — pickaxe for MINE, axe
## for CHOP. A pivot Node2D at the hand drives the swing (rotation from
## UnitAnimator.tool_swing); the sprite is recentered so the tool's grip
## sits on the pivot, and the pivot mirrors with the sprite's flip_h.
var _tool_pivot: Node2D = null
var _tool_sprite: Sprite2D = null
var _tool_kind := ""
const _TOOL_HAND := Vector2(11.0, -24.0)  # hand in Body space (feet pivot)
const _TOOL_WORLD_LEN := 30.0             # tool head-to-grip length, px
## Jeremy 2026-10-05: the unit's real equipped tool id from the petitions
## tool system ("axe"|"pickaxe"|"hoe"|"hammer"|"fishingrod"|""). HTML parity
## (toolImg54For): the equipped tool wins over the work-kind guess, so a
## farmer who bought a hoe visibly carries the hoe — not a guessed axe.
## All five ids have real sprites in assets/art/tools/.
var _equipped_tool := ""
const _KNOWN_TOOLS := ["axe", "pickaxe", "hoe", "hammer", "fishingrod"]
## Role fallback per gather site kind when the unit owns no tool (the old
## work-kind guess — HTML's toolImg54For fallback for chop/mine/farm).
const _TOOL_FOR_SITE := {
	"tree": "axe", "wood_pile": "axe",
	"rock": "pickaxe", "gold_vein": "pickaxe",
	"bush": "hoe", "field": "hoe", "farm": "hoe",
}
## Jeremy 2026-10-04: strike impact FX — a fixed pool of spark particles,
## seeded on each swing's strike edge and drawn in _draw(). No per-frame
## allocation: the arrays are sized once in _build().
const _SPARK_N := 6
const _SPARK_LIFE := 0.22
## Jeremy 2026-10-06: visible carry-load bundle (animation gate #3). Units
## hauling to a dropoff walked empty-handed while the sim's carrying{} said
## they held a full 10-unit load — a visible dead end in the animation pass.
## The bundle rides on the shoulder as a Body child, so it inherits the WALK
## bounce, rock and squash from anim.apply_to(_body) exactly (freeze-position
## law: the lean reads through the body's existing rock, never a position
## shift). It uses the SAME deposit/icon art as the ground pickups the unit
## collected, so ground -> shoulder -> stockpile is one continuous sprite.
## Missing art hides the overlay (never a white square); boats skip it.
var _load_pivot: Node2D = null
var _load_sprite: Sprite2D = null
var _load_kind := ""
const _LOAD_SHOULDER := Vector2(11.0, -32.0)  # shoulder slot, Body space
const _LOAD_WORLD_H := 18.0                   # bundle height, px
## Impact flavor: 0 = wood chips, 1 = stone sparks, 2 = soil dust.
const _FX_WOOD := 0
const _FX_STONE := 1
const _FX_DUST := 2
const _FX_SPLASH := 3  # fishing yank: pale droplets where the line lands
const _FX_BLOOD := 4   # hunt kill blow: red flecks at the prey
var _spark_pos := PackedVector2Array()
var _spark_vel := PackedVector2Array()
var _spark_life := 0.0
var _spark_flavor := _FX_WOOD
var _spark_stone := false   # true = stone sparks, false = wood chips/dust
var _strike_prev_cyc := 0.0  # last sampled cycle fraction (strike edge)

## Jeremy 2026-10-06 (five-books upgrade): overlapping action for held
## tools. The tool trails the body's swing by a few frames with its own
## decay (Illusion of Life: follow-through) — nothing in nature stops all
## at once. _tool_lag is (angle, extension), eased toward the animator's
## target each frame; zero delta snaps (no time = no lag can accumulate).
var _tool_lag := Vector2.ZERO

## Jeremy 2026-10-04: sneak mode (crime). The sprite's base scale, so the
## crouch can multiply it without fighting the animator (which owns the
## Body node's scale, never the sprite's).
var _base_sprite_scale := Vector2.ONE
var _sneaking := false
var _sick := false

## Jeremy 2026-10-05: swim visuals (Oblivion/Skyrim-style water rules).
## Half-submerged read: a translucent water band over the lower body plus
## ripple rings at the waterline, with a paddling bob layered over the
## animator. Boats are excluded (they have hulls, not swimmers).
var _swimming := false
var _swim_band: Polygon2D = null
var _swim_t := 0.0
const SWIM_WATERLINE_Y := -12.0
const SWIM_BAND_HALF_W := 20.0
const SWIM_BAND_BOTTOM := 6.0

## Jeremy 2026-10-08: downed-unit readability. The sim's goDowned path
## (combat.gd _go_downed) froze the unit but the visuals never showed it —
## a downed fighter looked identical to a standing one, so revivable allies
## (doctors auto-rush them; 60s bleed-out) were invisible on the battlefield.
## Downed units now lie prone with a pulsing gold revive ring; the pulse
## quickens as the bleed-out clock runs down. Revive restores the stance;
## death clears to the DEATH clip.
var _downed := false
var _downed_timer := 60.0
var _downed_t := 0.0
const DOWNED_PRONE_ANGLE := 1.35  # ~77 deg: crumpled on the ground, not a plank
const DOWNED_DROP := 7.0          # feet-pivot drop so the prone body rests low
const DOWNED_RING_R := 26.0
const DOWNED_FULL_TIMER := 60.0  # mirrors SimCombat.DOWNED_BLEEDOUT
## Jeremy 2026-10-06 (launch readiness, gate 3 — nothing floating): swimmers
## get a PINNED water shadow instead of the sun-cast ground blob, which can
## slide up to 80px off the body at dawn/dusk and reads as a floating dark
## ellipse on open water. Water shadows are softer than ground ones.
const SWIM_SHADOW_ALPHA := 0.55

## Testable shadow-dispatch contract: swimmers get the pinned water shadow,
## everyone else the sun-cast ground blob. Returns [kind, size, alpha_mul].
static func shadow_style(swimming: bool, footprint: float) -> Array:
	if swimming:
		return ["water", Shadows.water_shadow_size(footprint),
			SWIM_SHADOW_ALPHA]
	return ["ground", Vector2(footprint * 1.3, footprint * 0.85), 1.0]

## Jeremy 2026-10-04: limb-loss stump overlay. Unit sprites are single PNGs
## with baked-in limbs, so a severed limb is shown as a bloody Halo-red
## stump drawn over the joint (child of the sprite, so it inherits flip_h
## and scale). Positions are in texture space (~192 px chibi source).
var _limb_overlay: _LimbOverlay = null
var _last_limbs_key := -1  # Jeremy 2026-10-04 perf: int bitmask, was String
const _MONSTER_JOBS := ["thicc_moose", "giant_ass", "dragon", "kraken",
	"sandworm", "frost_giant", "hoa_karen", "jesus",
	"seagull_swarm", "taxman", "booze_ooze", "doom_prophet", "gig_gnome",
	"count_bastard", "borg_crab_bill", "twister_sister", "karaoke_barbarian",
	"gossip_gnome", "warranty_salesman", "doomscroller", "mlm_bro", "dmv_clerk",
	"crossfit_gnome", "influencer_gnome", "prince_gnomba", "dj_weddington",
	"repo_gnome", "podcast_bro"]
## 2026-10-07: the sim renamed the spark_driver disaster job to gig_gnome;
## the sprite file keeps its baked name (art provenance) — the texture and
## scale matches below map the new job to the existing art.

## 2026-10-07: the three wake-deep-disasters newcomers ship with real art.
## Seagull swarm = main gull + 4 orbiting flock satellites (flap via scale-y
## oscillation); booze ooze = squash-and-stretch wobble + rising foam
## bubbles; taxman = stern chibi sprite on the standard walk cycle.
var _gull_flock: Array[Sprite2D] = []
var _gull_t := 0.0
var _ooze_bubbles: Array[Sprite2D] = []
var _ooze_phase: Array[float] = []
var _ooze_t := 0.0
## 2026-10-08 (wake graphics-hourly): karaoke barbarian concert rig —
## ConcertFX Body child, live only while the sim has him "belting".
## Freed with the Body subtree on rebuild; ref cleared with the rest.
var _concert_fx: ConcertFX = null
## 2026-10-08 (wake graphics-hourly): doomscroller screen-glow rig —
## DoomscrollFX Body child, always scrolling while Milo lives. Freed with
## the Body subtree on rebuild; ref cleared with the rest.
var _doomscroll_fx: DoomscrollFX = null
## 2026-10-08 (wake rapid-iteration): MLM bro opportunity-sparkles rig —
## MLMBroFX Body child, always pitching while Chad lives. Freed with
## the Body subtree on rebuild; ref cleared with the rest.
var _mlm_fx: MLMBroFX = null
## 2026-10-08 (wake rapid-iteration): DMV clerk ticket-window rig —
## DMVClerkFX Body child, showing the "NOW SERVING #N" / "CLOSED FOR
## LUNCH" marquee plus falling ticket stubs. Freed with the Body subtree
## on rebuild; ref cleared with the rest.
var _dmv_fx: DMVClerkFX = null
## 2026-10-08 (wake graphics-hourly): twister sister funnel-spin rig —
## TwisterSisterFX Body child, always spinning while she rampages. Freed
## with the Body subtree on rebuild; ref cleared with the rest.
var _twister_fx: TwisterSisterFX = null
## 2026-10-08 (wake rapid-iteration): warranty salesman doorstep-pitch
## rig — WarrantyFX Body child, swirling certificates + EXPIRED stamp +
## sale coins while Wally lives. Freed with the Body subtree on rebuild;
## ref cleared with the rest.
var _warranty_fx: WarrantyFX = null
var _crossfit_fx: CrossFitFX = null
var _influencer_fx: InfluencerFX = null
## 2026-10-08 (wake deep-work, Disaster #26): Prince Gnomba "royal
## treasury" rig — GnombaFX Body child, rising coin motes + crown glint
## while the prince works the room. Freed with the Body subtree on
## rebuild; ref cleared with the rest.
var _gnomba_fx: GnombaFX = null
## 2026-10-08 (massive-dev, Disaster #27): DJ Weddington dance-floor rig
## — DjFX Body child, spinning mirror ball + rising notes + EQ bars while
## the set plays. Freed with the Body subtree on rebuild; ref cleared
## with the rest.
var _dj_fx: DjFX = null
## 2026-10-08 (wake routine, Disaster #28 completion): Ricky the Repo
## Gnome tow rig — RepoFX Body child, swaying tow chain + hook, hazard
## chevrons, fluttering foreclosure paperwork while Ricky works. Freed
## with the Body subtree on rebuild; ref cleared with the rest.
var _repo_fx: RepoFX = null
## Rapid-iteration 2026-10-08 (Disaster #29): Milo the Podcast Bro ON AIR
## rig — PodcastFX Body child, glowing ON AIR sign, floating mic icons,
## pulsing sound-wave rings and ring-light halo while Milo records. Freed
## with the Body subtree on rebuild; ref cleared with the rest.
var _podcast_fx: PodcastFX = null
## 2026-10-07 (wake deep-systems): Count Bastard theatrics — oratory sway
## + a deep mocking bow every insult cadence while ranting; cape billow
## while traveling. Stepped in _process; culled with the unit.
var _bastard_t := 0.0
const BASTARD_BOW_PERIOD := 3.5  # matches BASTARD_INSULT_CD in disasters.gd
var _ooze_bubble_tex: Texture2D = null


## Jeremy 2026-10-04: thicc moose mooning — the moose TURNS AROUND and shows
## a rear-view butt sprite while mooning a town hall (combat_state ==
## "mooning"). Jeremy's iPhone verdict: the old side profile just read as
## the moose standing there. The butt shakes with squash-and-stretch.
var _mooning := false
var _moon_time := 0.0
var _butt_tex: Texture2D = null

## Jeremy 2026-10-04: Jesus 2-frame walk-cycle clock (JesusArt strip).
## Stepped in _process only while the singleton is moving.
var _jesus_frame_t := 0.0

## 2026-10-04: naval renderer — boats are drawn as AI-generated pixel-art
## hulls, not chibi characters (HTML _toonDrawCharacter boat branch,
## verbatim). _boat gets the bob+rock wave motion; _pennant is the faction
## pennant fluttering from the mast in the race accent color.
const _BOAT_JOBS := ["fishing_boat", "war_ship"]
var _boat: Node2D = null
var _pennant: Polygon2D = null
var _boat_w := 0.0
var _boat_h := 0.0
var _boat_time := 0.0
## 2026-10-04: foam wake — pooled flecks at the stern while a boat sails
## (BoatWake child of Body at index 0, under the hull; freed with Body on
## rebuild). _last_pos is the 2D movement tracker feeding the wake.
var _wake: BoatWake = null
var _last_pos := Vector2.ZERO

## 2026-10-04: world-space HP bar — HTML C70fix2 MISS 11 port (fix79
## index.html:37554). The bar shows ONLY while injured (hp < maxHp - 0.5),
## never at full health — Jeremy's standing rule. Driven by set_hp() from
## the world sync; cheap early-out when unchanged, queue_redraw only when
## the visibility bit or the 1%-quantized fill bucket changes (avoids
## redraw churn while slow regen ticks).
var _hp := 100.0
var _max_hp := 100.0
var _hp_bar_key := -1  # (visible << 8) | pct bucket; -1 = unset
var _hp_bar_bg: StyleBoxFlat = null  # cached dark rounded backing

## 2026-10-05: hurt flash — HTML chibiWhite parity (fix79 index.html:39034,
## _hurtT set on damage at :35279). On every survived hit the sim sets
## combat_state="hurt" (combat.damage_unit); the world sync edge-triggers
## play_hurt(), which arms _hurt_t = 0.45. While _hurt_t > 0.01 a white
## silhouette of the sprite overlays the unit at HTML-verbatim alpha
## min(0.75, _hurtT * 2.2). The overlay is a sibling Sprite2D mirroring the
## main sprite each frame (texture swaps, atlas frames, flips, butt-shake
## squash) so sneak-mode modulate is never touched and the pose always
## matches. Zero draw cost when idle (visible = false).
const HURT_FLASH_LEN := 0.45
var _hurt_t := 0.0
var _flash: Sprite2D = null
var _flash_mat: ShaderMaterial = null  # per-unit: flash_alpha is per-unit

## Jeremy 2026-10-06: radiation suit overlay (HTML drawRadiationSuit
## parity). Units in hot zones don faction-colored hazmat suits — the sim
## sets inRadSuit/radLevel (SimNuclear._tick_radiation) and the world sync
## drives set_rad_suit. The overlay is a _body child (draws over the
## sprite, inherits the walk bounce); redraws only on state changes, so
## suited units cost nothing extra per frame.
var _suit_overlay: _SuitOverlay = null
var _in_rad_suit := false
var _rad_glow := false  # radLevel > 0.4: high-rad glow ring


## HTML-verbatim suit palettes (drawRadiationSuit body/trim/visor/tank).
## Undead falls back to the human grey (HTML's else branch).
static func suit_palette(faction: String) -> Array:
	match faction:
		"ogres":
			return [Color("#33691e"), Color("#1b5e20"),
				Color("#aed581"), Color("#558b2f")]
		"gnomes":
			return [Color("#6a1b9a"), Color("#4a148c"),
				Color("#e1bee7"), Color("#9c27b0")]
		"elves":
			return [Color("#1b5e20"), Color("#004d40"),
				Color("#b2ff59"), Color("#2e7d32")]
	return [Color("#546e7a"), Color("#37474f"),
		Color("#ffd54f"), Color("#78909c")]


## World-sync entry: toggles the hazmat overlay. Cheap early-out on the
## (suit, glow) key — the 240-unit sync only pays two compares per tick.
func set_rad_suit(suit: bool, level: float) -> void:
	var glow: bool = suit and level > 0.4
	if suit == _in_rad_suit and glow == _rad_glow and _suit_overlay != null:
		return
	_in_rad_suit = suit
	_rad_glow = glow
	if suit:
		_ensure_suit()
	if _suit_overlay == null:
		return
	_suit_overlay.visible = suit
	_suit_overlay.faction = faction
	_suit_overlay.rad_level = level
	var h := _monster_scale()
	if _boat != null and _boat_h > 0.0:
		h = _boat_h
	_suit_overlay.unit_h = h
	_suit_overlay.queue_redraw()


## Builds the suit overlay on demand (child of Body, after the sprite so
## it draws over the chibi).
func _ensure_suit() -> void:
	if _suit_overlay != null or _body == null:
		return
	_suit_overlay = _SuitOverlay.new()
	_suit_overlay.visible = false
	_body.add_child(_suit_overlay)

func set_mooning(on: bool) -> void:
	if on == _mooning:
		return
	_mooning = on
	_moon_time = 0.0
	if _sprite == null or job != "thicc_moose":
		return
	if on:
		# Turn around: rear-view butt to the hall.
		if _butt_tex == null:
			_butt_tex = Art.animal_texture("moose_butt")
		if _butt_tex != null:
			_sprite.texture = _butt_tex
			var sc: float = _monster_scale() / float(_butt_tex.get_height())
			_sprite.scale = Vector2(sc, sc)
			_sprite.position = Vector2(0, -_monster_scale() * 0.48)
			_base_sprite_scale = _sprite.scale
	else:
		# Turn back: restore the side-profile moose sprite + base pose.
		var mtex: Texture2D = _monster_texture()
		if mtex != null:
			_sprite.texture = mtex
			var msc: float = _monster_scale() / float(mtex.get_height())
			_sprite.scale = Vector2(msc, msc)
			_base_sprite_scale = _sprite.scale
		_sprite.position.x = 0.0
		_sprite.rotation = 0.0
		_sprite.scale = _base_sprite_scale


## Sneak mode: crouched, darkened sprite. The visual half of the criminal
## justice system's stalk/flee phases — readable at a glance.
func set_sneaking(on: bool) -> void:
	if on == _sneaking:
		return
	_sneaking = on
	if _sprite == null:
		return
	if on:
		_sprite.scale = _base_sprite_scale * Vector2(1.1, 0.72)
		_sprite.modulate = Color(0.55, 0.55, 0.65)
	else:
		_sprite.scale = _base_sprite_scale
		_sprite.modulate = Color(0.72, 0.92, 0.70) if _sick else Color.WHITE


## Sick mode: pale, greenish tint — the plague is visible at a glance.
## Yields to sneaking/downed (those states own the sprite); the world sync
## calls the states in order every frame so this stays consistent.
func set_sick(on: bool) -> void:
	if on == _sick:
		return
	_sick = on
	if _sprite == null:
		return
	if on:
		if _sneaking or _downed:
			return
		_sprite.modulate = Color(0.72, 0.92, 0.70)
	else:
		if _sneaking or _downed:
			return
		_sprite.modulate = Color.WHITE


## Swim mode: half-submerged water band + ripples + paddling bob.
## Boats keep their hull visuals (never swimmers).
func set_swimming(on: bool) -> void:
	if _boat != null:
		on = false
	if on == _swimming and (_swim_band != null or not on):
		return
	_swimming = on
	_ensure_swim_band()
	if _swim_band != null:
		_swim_band.visible = on
	# Shadow mode changes with the swim state (pinned water shadow vs cast
	# ground blob); redraw now so the swap lands this frame even before the
	# shadow-key check in _process catches it.
	queue_redraw()


## Builds the translucent water band on demand (child of Body, after the
## sprite/flash/tool so it draws over the lower body).
func _ensure_swim_band() -> void:
	if _swim_band != null or _body == null:
		return
	_swim_band = Polygon2D.new()
	_swim_band.color = Color(0.25, 0.55, 0.95, 0.45)
	_swim_band.visible = false
	_body.add_child(_swim_band)
	_wave_swim_band()


## Wavy top edge on the swim band, animated while swimming.
func _wave_swim_band() -> void:
	if _swim_band == null:
		return
	var pts := PackedVector2Array()
	var segs := 8
	for i in range(segs + 1):
		var x := lerpf(-SWIM_BAND_HALF_W, SWIM_BAND_HALF_W,
			float(i) / float(segs))
		pts.append(Vector2(x, SWIM_WATERLINE_Y \
			+ sin(_swim_t * 2.0 + float(i) * 0.9) * 1.6))
	pts.append(Vector2(SWIM_BAND_HALF_W, SWIM_BAND_BOTTOM))
	pts.append(Vector2(-SWIM_BAND_HALF_W, SWIM_BAND_BOTTOM))
	_swim_band.polygon = pts


## World-sync entry for the downed (knocked-out, revivable) state.
## Cheap early-out on the flag; the timer refreshes every sync so the ring
## pulse tracks the real bleed-out clock. The pulse phase keeps running
## across syncs (no reset) so the ring doesn't strobe.
func set_downed(downed: bool, timer_left: float) -> void:
	if downed == _downed:
		_downed_timer = timer_left
		return
	_downed = downed
	_downed_timer = timer_left
	_downed_t = 0.0
	queue_redraw()


## Revive-ring pulse period: slow and calm with a full clock, urgent as
## bleed-out approaches. Extracted so tests can pin it without a canvas.
func _downed_period() -> float:
	var frac: float = clampf(_downed_timer / DOWNED_FULL_TIMER, 0.0, 1.0)
	return lerpf(0.32, 1.15, frac)


## Radius + alpha of the revive ring for the current pulse phase.
## Returns [radius, alpha].
func _downed_ring_params() -> Array:
	var period: float = _downed_period()
	var ph: float = fmod(_downed_t, period) / period
	var pulse: float = 0.5 + 0.5 * sin(ph * TAU)
	return [DOWNED_RING_R * (1.0 + 0.12 * pulse), 0.30 + 0.55 * pulse]


## Prone pose layered over the animator (same overlay idiom as swimming):
## the animator still owns the body each frame, then the downed overlay pins
## it prone and still. Boats never reach this branch (naval _process path).
func _apply_downed_pose(delta: float) -> void:
	_downed_t += delta
	var dir := 1.0
	if _sprite != null and _sprite.flip_h:
		dir = -1.0
	_body.rotation = dir * DOWNED_PRONE_ANGLE
	_body.position.y = DOWNED_DROP
	_body.scale = Vector2.ONE
	queue_redraw()  # the revive ring pulses in _draw


## Gold revive ring at the feet, isometrically squashed like the selection
## ring. Bubble ban honored: a ground ring, not a panel/chip/label.
func _draw_downed_ring() -> void:
	if not _downed:
		return
	var params: Array = _downed_ring_params()
	var r: float = params[0]
	var a: float = params[1]
	var col := Color(1.0, 0.82, 0.25, a)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.52))
	draw_circle(Vector2.ZERO, r, Color(col.r, col.g, col.b, a * 0.22))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Limb-loss stump overlay (called every frame by world sync; cheap
## early-out when nothing changed). Monsters don't get stumps — their
## anatomy isn't humanoid. Boats neither — hulls aren't humanoid.
func set_limb_state(limbs: Dictionary) -> void:
	if _sprite == null or job in _MONSTER_JOBS or job in _BOAT_JOBS:
		return
	# Jeremy 2026-10-04 perf: integer bitmask instead of "%s%s%s%s" string
	# formatting (was 7,200 string formats/sec across 240 units at 30Hz sync).
	var key: int = 0
	if limbs.get("leftArm", true):
		key |= 8
	if limbs.get("rightArm", true):
		key |= 4
	if limbs.get("leftLeg", true):
		key |= 2
	if limbs.get("rightLeg", true):
		key |= 1
	if key == _last_limbs_key:
		return
	_last_limbs_key = key
	if key == 15:
		if _limb_overlay != null and is_instance_valid(_limb_overlay):
			_limb_overlay.queue_free()
		_limb_overlay = null
		return
	if _limb_overlay == null or not is_instance_valid(_limb_overlay):
		_limb_overlay = _LimbOverlay.new()
		_sprite.add_child(_limb_overlay)
	_limb_overlay.set_missing(limbs)


## Sun-driven blob shadow (Shadows = HTML drawShadowSystem parity).
## Drawn in _draw() at the feet origin, so it renders under the Body sprite.
## Swimmers rest on water: the shadow_style contract swaps the cast ground
## blob for a pinned water shadow while swimming.
func _draw() -> void:
	var style := shadow_style(_swimming, _shadow_footprint())
	if String(style[0]) == "water":
		Shadows.draw_water_shadow(self, style[1], float(style[2]))
	else:
		Shadows.draw_blob(self, _shadow_footprint())
	_draw_hp_bar()
	_draw_strike_fx()
	_draw_swim_ripples()
	_draw_downed_ring()


## Expanding ripple rings at the waterline while swimming.
func _draw_swim_ripples() -> void:
	if not _swimming:
		return
	for r in range(2):
		var k := fmod(_swim_t * 0.7 + float(r) * 0.5, 1.0)
		var rx := 12.0 + k * 24.0
		var pts := PackedVector2Array()
		for i in range(20):
			var a := TAU * float(i) / 20.0
			pts.append(Vector2(cos(a) * rx, sin(a) * rx * 0.35))
		pts.append(pts[0])
		draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.5 * (1.0 - k)), 1.5)


## World-space HP bar (HTML C70fix2 verbatim): dark rounded backing +
## colored fill, shown only while injured. Chibi units use SPRITE_WORLD_H
## (bar at -2.5s clears the big head, head top ≈ -2.18s, per the HTML
## comment). Monsters scale with their world height; boats sit above the
## mast (HTML gives boats the same bar — it just reads above the hull).
func _draw_hp_bar() -> void:
	if _hp_bar_key < 0 or (_hp_bar_key >> 8) == 0:
		return
	var rect := _bar_rect()
	if _hp_bar_bg == null:
		_hp_bar_bg = StyleBoxFlat.new()
		_hp_bar_bg.bg_color = Color(20.0 / 255.0, 20.0 / 255.0, 28.0 / 255.0, 0.85)
		_hp_bar_bg.set_corner_radius_all(3)
	draw_style_box(_hp_bar_bg, rect.grow(1.0))
	var pct: float = clampf(_hp / _max_hp, 0.0, 1.0)
	var pw: float = maxf(2.0, rect.size.x * pct)
	draw_rect(Rect2(rect.position, Vector2(pw, rect.size.y)), hp_bar_color(pct))


## Node-local HP bar rect (origin at the feet).
func _bar_rect() -> Rect2:
	var s := SPRITE_WORLD_H
	if _boat != null and _boat_h > 0.0:
		# Mast top = hull 0.72 + pennant mast 0.35 (from _build_boat);
		# bar sits 12 px above it instead of through the mast.
		var mast: float = _boat_h * 0.72 + s * 0.35
		return Rect2(-s * 1.1, -(mast + 12.0), s * 2.2, 5.0)
	if job == "giant_ass":
		# Procedural butt: ellipse top ≈ -2.1s; bar scales with the joke.
		return Rect2(-s * 3.3, -(s * 2.1 + 12.0), s * 6.6, 5.0)
	if _monster_scale() != s:
		# Textured monsters: head top ≈ -scale; bar 12 px above it.
		var m := _monster_scale()
		return Rect2(-m * 1.1, -(m + 12.0), m * 2.2, 5.0)
	return hp_bar_geom(s)


## HTML injured-only rule (C70fix2, fix79 index.html:37566):
## (this.maxHp > 0) && (this.hp < this.maxHp - 0.5).
static func hp_bar_visible(hp: float, max_hp: float) -> bool:
	return max_hp > 0.0 and hp < max_hp - 0.5


## HTML unit bar geometry (fix79 index.html:37554): barW = s * 2.2, barH = 5,
## drawn at y - s * 2.5. Returns the bar rect in node-local coords
## (origin at the feet).
static func hp_bar_geom(s: float) -> Rect2:
	var bar_w: float = s * 2.2
	return Rect2(-bar_w * 0.5, -s * 2.5, bar_w, 5.0)


## HTML fill thresholds, verbatim (fix79 index.html:37571):
## pct > 0.5 → green #66bb6a; > 0.25 → orange #ffa726; else red #ef5350.
static func hp_bar_color(pct: float) -> Color:
	if pct > 0.5:
		return Color("#66bb6a")
	elif pct > 0.25:
		return Color("#ffa726")
	return Color("#ef5350")


## World-space HP bar state, called by the world sync every tick.
## queue_redraw fires only when the visibility bit or the quantized fill
## bucket changes — steady full-health units cost two compares per frame.
func set_hp(hp: float, max_hp: float) -> void:
	var vis: int = 1 if hp_bar_visible(hp, max_hp) else 0
	var bucket := 0
	if vis == 1:
		bucket = int(clampf(hp / max_hp, 0.0, 1.0) * 100.0)
	var key: int = (vis << 8) | bucket
	if key == _hp_bar_key:
		return
	_hp_bar_key = key
	_hp = hp
	_max_hp = max_hp
	queue_redraw()


## HTML putD footprint: (u.size || 30) for units, (m.size || 60) for monsters.
## Godot units are uniform chibi (SPRITE_WORLD_H); monsters scale with
## _monster_scale(). Boats cast a wider blob matching the hull.
func _shadow_footprint() -> float:
	if _boat != null and _boat_w > 0.0:
		return _boat_w * 0.45
	return _monster_scale() * 0.75


func setup(p_id: int, p_faction: String, p_job: String, p_pos: Vector2,
		p_gender: String = "m") -> void:
	unit_id = p_id
	faction = p_faction
	job = p_job
	gender = p_gender
	position = p_pos
	anim = UnitAnimator.for_uid(p_id)
	# Five-books upgrade: weight-based timing — ogres move differently
	# than gnomes, not just look different (Timing for Animation).
	anim.weight = UnitAnimator.weight_for_faction(p_faction)
	_build()


func _build() -> void:
	_body = Node2D.new()
	_body.name = "Body"
	add_child(_body)
	# Job rebuilds free the old Body subtree: drop the dangling flash refs
	# (recreated below); the hurt timer never survives a rebuild.
	_flash = null
	_flash_mat = null
	_hurt_t = 0.0
	# Suit overlay is a Body child: drop the dangling ref on rebuild
	# (the next set_rad_suit from the world sync rebuilds it if suited).
	_suit_overlay = null
	# Same for the swim band (child of Body); keep the swimming state —
	# set_swimming rebuilds the band on demand.
	_swim_band = null
	# 2026-10-07: disaster-visual state — flock/bubble sprites are Body
	# children, so their refs dangle after a rebuild; clear with the rest.
	_gull_flock.clear()
	_gull_t = 0.0
	_ooze_bubbles.clear()
	_ooze_phase.clear()
	_ooze_t = 0.0
	_concert_fx = null
	_doomscroll_fx = null
	_mlm_fx = null
	_dmv_fx = null
	_twister_fx = null
	_warranty_fx = null
	_crossfit_fx = null
	_sprite = Sprite2D.new()
	# Milestone 7: disaster visuals — Giant Ass, Thicc Moose get proper
	# rendering instead of gnome placeholders.
	var mtex: Texture2D = _monster_texture()
	if job == "giant_ass":
		_build_giant_ass()
	elif job == "jesus":
		_build_jesus()
	elif mtex != null:
		_sprite.texture = mtex
		var msc: float = _monster_scale() / float(mtex.get_height())
		_sprite.scale = Vector2(msc, msc)
		_sprite.position = Vector2(0, -_monster_scale() * 0.48)
		if job == "seagull_swarm":
			_build_seagull_swarm(mtex, msc)
		elif job == "booze_ooze":
			_build_booze_ooze()
		elif job == "karaoke_barbarian":
			_build_concert_fx()
		elif job == "doomscroller":
			_build_doomscroll_fx()
		elif job == "mlm_bro":
			_build_mlm_fx()
		elif job == "dmv_clerk":
			_build_dmv_fx()
		elif job == "twister_sister":
			_build_twister_fx()
		elif job == "warranty_salesman":
			_build_warranty_fx()
		elif job == "crossfit_gnome":
			_build_crossfit_fx()
		elif job == "influencer_gnome":
			_build_influencer_fx()
		elif job == "prince_gnomba":
			_build_gnomba_fx()
		elif job == "dj_weddington":
			_build_dj_fx()
		elif job == "repo_gnome":
			_build_repo_fx()
		elif job == "podcast_bro":
			_build_podcast_fx()
	elif job in _BOAT_JOBS:
		_build_boat()
		return  # boat branch owns its sprite + tag; no chibi path
	else:
		var tex: Texture2D = Art.unit_texture(faction, job, unit_id, gender)
		if tex == null:
			# No art for this key (shouldn't happen): fall back to worker m0.
			tex = Art.unit_texture(faction, "worker", 0, "m")
		_sprite.texture = tex
		if tex != null:
			var sc: float = SPRITE_WORLD_H / float(tex.get_height())
			_sprite.scale = Vector2(sc, sc)
			# Feet at the Body origin: sprite center sits half its world height up.
			_sprite.position = Vector2(0, -SPRITE_WORLD_H * 0.48)
	# giant_ass has no sprite (procedural butt polygon) — guard the add.
	if _sprite != null:
		_body.add_child(_sprite)
		# Hurt-flash overlay: sibling right after the sprite so it draws
		# over the unit (and limb stumps) — same layering as the HTML draw.
		_make_flash(_body)
	# Jeremy 2026-10-05: tool overlay for work animations (mine/chop). The
	# pivot is rebuilt with the body on job changes; the texture is
	# re-applied by the next set_work_state call from the world sync.
	_tool_pivot = null
	_tool_sprite = null
	_tool_kind = ""
	_load_pivot = null
	_load_sprite = null
	_load_kind = ""
	_spark_life = 0.0
	_strike_prev_cyc = 0.0
	_ensure_tool()
	_ensure_load()
	_last_px = position.x
	_last_pos = position
	# Jeremy 2026-10-04: base sprite scale for the sneak-mode crouch.
	if _sprite != null:
		_base_sprite_scale = _sprite.scale


## 2026-10-04: naval renderer. Boats are drawn as AI-generated pixel-art
## hulls, not chibi characters — verbatim port of the HTML's
## _toonDrawCharacter boat branch (bob + rock wave motion, faction pennant
## on the mast in the race accent color). Previously boat units rendered as
## chibi workers with a worker hard-hat job tag, standing on the water.
func _build_boat() -> void:
	_boat = Node2D.new()
	_boat.name = "Boat"
	_body.add_child(_boat)
	var tex: Texture2D = Art.boat_texture(job)
	var s := SPRITE_WORLD_H
	if tex != null:
		_boat_w = s * (3.4 if job == "war_ship" else 2.5)
		_boat_h = _boat_w * float(tex.get_height()) / float(tex.get_width())
		# Reuse the sprite _build() already created (not yet in the tree).
		_sprite.texture = tex
		var sc: float = _boat_w / float(tex.get_width())
		_sprite.scale = Vector2(sc, sc)
		# HTML: drawImage(-bw/2, -bh*0.72, bw, bh) — center at (0, -bh*0.22).
		_sprite.position = Vector2(0, -_boat_h * 0.22)
		_boat.add_child(_sprite)
		# Hurt flash over the hull (sibling, before the pennant).
		_make_flash(_boat)
	# Faction pennant fluttering from the mast (HTML verbatim geometry).
	_pennant = Polygon2D.new()
	_pennant.color = Art.faction_accent(faction)
	_boat.add_child(_pennant)
	_base_sprite_scale = _sprite.scale if _sprite != null else Vector2.ONE
	_last_px = position.x
	_last_pos = position
	# Foam wake: pooled flecks at the stern while sailing. Child of Body at
	# index 0 so it renders under the hull (above the blob shadow, which is
	# drawn by UnitNode._draw itself); freed with Body on a job rebuild.
	# The HTML boat branch has no wake — this is an original addition in
	# the game's foam-water language (cf. river foam).
	_wake = BoatWake.new()
	_wake.name = "Wake"
	_body.add_child(_wake)
	_body.move_child(_wake, 0)


## Boat wave motion: bob + rock + pennant flutter (HTML verbatim formulas).
## Boats skip the UnitAnimator choreography entirely.
func _boat_animate(delta: float) -> void:
	_boat_time += delta
	var s := SPRITE_WORLD_H
	var uid := float(unit_id)
	_boat.position = Vector2(0, sin(_boat_time * 2.1 + uid * 1.7) * s * 0.07)
	_boat.rotation = sin(_boat_time * 1.3 + uid * 2.3) * 0.045
	if _pennant != null:
		var fw := s * 0.5
		var fh := s * 0.22
		var fx := _boat_w * 0.18
		var fy := -_boat_h * 0.72 - s * 0.35 \
			+ sin(_boat_time * 6.0 + uid) * 1.5
		_pennant.polygon = PackedVector2Array([
			Vector2(fx, fy),
			Vector2(fx + fw, fy + fh * 0.5),
			Vector2(fx, fy + fh)])


## Milestone 7: monster-specific textures. Returns null for normal units.
func _monster_texture() -> Texture2D:
	match job:
		"thicc_moose":
			return Art.animal_texture("moose")
		"giant_lizard":
			return Art.animal_texture("lizard")
		"hoa_karen":
			return Art.animal_texture("karen")
		"seagull_swarm":
			return Art.animal_texture("seagull")
		"taxman":
			return Art.animal_texture("taxman")
		"booze_ooze":
			return Art.animal_texture("booze_ooze")
		"doom_prophet":
			return Art.animal_texture("doom_prophet")
		"gig_gnome":
			# Sim job renamed from spark_driver 2026-10-07; the sprite file
			# keeps its baked name.
			return Art.animal_texture("spark_driver")
		"count_bastard":
			# Jeremy 2026-10-07 (wake deep-systems): real vampire-nobleman
			# art — he used to render as a plain citizen chibi (no art
			# mapping at all).
			return Art.animal_texture("count_bastard")
		"rogue_wizard":
			# Wake rapid-iteration 2026-10-07: real wizard art — he used
			# to render as a plain citizen chibi (no art mapping at all).
			return Art.animal_texture("rogue_wizard")
		"cardboard_cat":
			# Wake graphics-hourly 2026-10-08: real art — the LAST named
			# disaster with no mapping (rendered as a plain citizen chibi).
			# AI-generated chibi pixel-art: cat sitting in a cardboard box.
			return Art.animal_texture("cardboard_cat")
		"borg_crab_bill":
			# Wake 2026-10-08: bespoke Borg-crab art — AI-generated chibi
			# pixel-art cybernetic crab (Borg-green LED antenna, riveted
			# shell plates, mechanical legs, toaster bolted to the shell).
			return Art.animal_texture("borg_crab_bill")
		"twister_sister":
			# Wake rapid-iteration 2026-10-08: bespoke glam-metal tornado
			# art — AI-generated chibi pixel-art funnel with 80s teased
			# hair, sunglasses, crackling lightning, tiny guitar.
			return Art.animal_texture("twister_sister")
		"karaoke_barbarian":
			# Wake rapid-iteration 2026-10-08: bespoke chibi pixel-art
			# barbarian with a raised lute, mid-power-ballad (horned
			# helmet, fur loincloth, music notes).
			return Art.animal_texture("karaoke_barbarian")
		"gossip_gnome":
			# Wake rapid-iteration 2026-10-08: bespoke chibi pixel-art
			# gossip gnome — giant brass ear trumpet, quill behind the
			# ear, notebook in hand, mid-conspiracy lean.
			return Art.animal_texture("gossip_gnome")
		"warranty_salesman":
			# Wake rapid-iteration 2026-10-08: bespoke chibi pixel-art
			# warranty salesman — cheap suit, red tie, briefcase full of
			# "extended warranties", mid-pitch grin.
			return Art.animal_texture("warranty_salesman")
		"doomscroller":
			# Massive-dev 2026-10-08: bespoke chibi pixel-art doomscroller —
			# glazed half-lidded eyes, droopy purple nightcap, grey hoodie,
			# hunched over a glowing smartphone, thumb mid-scroll, screen
			# glow on the face.
			return Art.animal_texture("doomscroller")
		"mlm_bro":
			# Dedicated-porting 2026-10-08: bespoke chibi pixel-art MLM bro —
			# cheap navy suit, red tie, slicked hair, blinding white grin,
			# briefcase full of "opportunity".
			return Art.animal_texture("mlm_bro")
		"dmv_clerk":
			# Wake rapid-iteration 2026-10-08: bespoke chibi pixel-art DMV
			# clerk — surly gnome, grey cardigan, folding table, red ticket
			# dispenser, tall stack of forms, dismissive hand raised.
			return Art.animal_texture("dmv_clerk")
		"crossfit_gnome":
			# Massive-dev 2026-10-08: bespoke chibi pixel-art CrossFit
			# gnome — neon tank top, red headband, wristbands, mid-burpee
			# triumph pose, protein shaker at his feet.
			return Art.animal_texture("crossfit_gnome")
		"influencer_gnome":
			# Dedicated-porting 2026-10-08: bespoke chibi pixel-art
			# influencer — blonde ponytail, pink crop top, selfie stick
			# with phone held high, peace sign, glowing ring light on
			# a tripod beside her.
			return Art.animal_texture("influencer_gnome")
		"prince_gnomba":
			# Wake deep-work 2026-10-08: bespoke chibi pixel-art prince —
			# purple/gold agbada, crooked crown, royal scroll and coin
			# purse, extremely trustworthy grin.
			return Art.animal_texture("prince_gnomba")
		"dj_weddington":
			# Massive-dev 2026-10-08: bespoke chibi pixel-art wedding DJ —
			# glowing oversized headphones, sparkly purple tracksuit,
			# gold chain, hype fist in the air, turntables and mirror ball.
			return Art.animal_texture("dj_weddington")
		"repo_gnome":
			# Wake routine 2026-10-08 (Disaster #28 completion): bespoke
			# chibi pixel-art repo gnome — backwards red cap, tow chain
			# with hook, clipboard of foreclosure papers, tiny yellow tow
			# truck at his side.
			return Art.animal_texture("repo_gnome")
		"podcast_bro":
			# Rapid-iteration 2026-10-08 (Disaster #29): bespoke chibi
			# pixel-art podcast bro — backwards red cap, oversized
			# headphones, purple hoodie, giant vintage mic, ring light
			# on a tripod beside a folding table.
			return Art.animal_texture("podcast_bro")
	return null


## World-space height for monster sprites (bigger than chibi units).
func _monster_scale() -> float:
	match job:
		"giant_ass":
			return SPRITE_WORLD_H * 3.0
		"thicc_moose":
			return SPRITE_WORLD_H * 2.2
		"giant_lizard":
			return SPRITE_WORLD_H * 1.8
		"rogue_wizard":
			return SPRITE_WORLD_H * 1.2
		"cardboard_cat":
			return SPRITE_WORLD_H * 0.9
		"hoa_karen":
			return SPRITE_WORLD_H * 1.1
		"seagull_swarm":
			return SPRITE_WORLD_H * 0.62
		"taxman":
			return SPRITE_WORLD_H * 1.15
		"booze_ooze":
			return SPRITE_WORLD_H * 1.35
		"doom_prophet":
			return SPRITE_WORLD_H * 1.1
		"gig_gnome":
			return SPRITE_WORLD_H * 1.15
		"borg_crab_bill":
			return SPRITE_WORLD_H * 1.6
		"twister_sister":
			return SPRITE_WORLD_H * 2.0
		"karaoke_barbarian":
			return SPRITE_WORLD_H * 1.35
		"gossip_gnome":
			return SPRITE_WORLD_H * 1.35
		"warranty_salesman":
			return SPRITE_WORLD_H * 1.15
		"doomscroller":
			return SPRITE_WORLD_H * 1.35
		"mlm_bro":
			return SPRITE_WORLD_H * 1.2
		"dmv_clerk":
			return SPRITE_WORLD_H * 1.25
		"crossfit_gnome":
			return SPRITE_WORLD_H * 1.2
		"influencer_gnome":
			return SPRITE_WORLD_H * 1.2
		"dj_weddington":
			return SPRITE_WORLD_H * 1.2
		"repo_gnome":
			return SPRITE_WORLD_H * 1.2
		"count_bastard":
			return SPRITE_WORLD_H * 1.2
		"jesus":
			return SPRITE_WORLD_H * 1.2
	return SPRITE_WORLD_H


## Milestone 7: Giant Ass has no sprite art — draw it procedurally as a
## massive brown oval (the joke is the shape). Called when _monster_texture
## returns null but the job is giant_ass.
func _build_giant_ass() -> void:
	# Replaces the sprite with a big brown ellipse.
	_sprite.queue_free()
	var poly := Polygon2D.new()
	var pts := PackedVector2Array()
	var rx := SPRITE_WORLD_H * 1.5
	var ry := SPRITE_WORLD_H * 1.1
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * rx, -ry * 0.9 + sin(a) * ry))
	poly.polygon = pts
	poly.color = Color(0.45, 0.30, 0.18)  # brown
	_body.add_child(poly)
	# The crack — a darker line down the middle (it's a butt joke).
	var crack := Line2D.new()
	crack.points = PackedVector2Array([
		Vector2(0, -ry * 1.6), Vector2(0, -ry * 0.4)])
	crack.width = 6.0
	crack.default_color = Color(0.25, 0.15, 0.08)
	_body.add_child(crack)
	_sprite = null  # no sprite for the ass


## Jeremy 2026-10-04: JESUS disaster visual — real chibi pixel-art sprite
## (JesusArt: hand-authored 32x46 pixels, 2-frame walk strip). Replaces the
## old flat procedural polygons. Walk bounce + flip come from the standard
## UnitAnimator path; the 2-frame cycle is stepped in _process while moving.
func _build_jesus() -> void:
	var tex: Texture2D = JesusArtScript.make_texture()
	if tex == null:
		return  # art failed to decode; leave the blank sprite (never crash)
	_sprite.texture = tex
	_sprite.hframes = JesusArtScript.FRAME_COUNT
	_sprite.frame = 0
	var h := SPRITE_WORLD_H * 1.2
	var sc: float = h / float(tex.get_height())
	_sprite.scale = Vector2(sc, sc)
	_sprite.position = Vector2(0, -h * 0.48)
	# Keep the old procedural nodes gone: nothing else was added to _body yet
	# at this point (job tag comes later in _build), so nothing to free.


## 2026-10-07: SEAGULL SWARM visual — the singleton unit is one gull; four
## satellite gulls orbit it so the "swarm" reads on screen. Satellites are
## Body children (freed with Body on a job rebuild; _gull_flock is reset in
## _build). Flap = scale-y oscillation stepped in _process; _process is
## culled off-screen with the unit, so the flock costs nothing unseen.
func _build_seagull_swarm(mtex: Texture2D, msc: float) -> void:
	if mtex == null:
		return
	for i in 4:
		var g := Sprite2D.new()
		g.name = "GullSat%d" % i
		g.texture = mtex
		var s: float = msc * 0.45
		g.scale = Vector2(s, s)
		_body.add_child(g)
		_gull_flock.append(g)
	_gull_t = randf() * TAU


func _animate_seagulls(delta: float) -> void:
	_gull_t += delta
	var n := _gull_flock.size()
	if n == 0:
		return
	for i in n:
		var g := _gull_flock[i]
		if not is_instance_valid(g):
			continue
		var a: float = _gull_t * 2.1 + TAU * float(i) / float(n)
		g.position = Vector2(cos(a) * 34.0, -26.0 + sin(a) * 18.0)
		# Wingbeat: vertical squash around the satellite's own base scale
		# (scale.x is never touched, so it stays the base).
		var flap: float = 0.68 + 0.32 * sin(_gull_t * 13.0 + float(i) * 1.7)
		var bx: float = g.scale.x
		g.scale = Vector2(bx, bx * flap)
		g.flip_h = cos(a) < 0.0


## 2026-10-07: BOOZE OOZE visual — squash-and-stretch wobble plus foam
## bubbles that rise through the amber body and pop at the foam head.
## Bubbles are Body children; phases desync them. Stepped in _process.
func _build_booze_ooze() -> void:
	if _ooze_bubble_tex == null:
		_ooze_bubble_tex = Art.animal_texture("bubble")
	if _ooze_bubble_tex == null:
		return  # art missing: the ooze still renders, just without bubbles
	_ooze_phase = [0.0, 0.37, 0.71] as Array[float]
	for i in 3:
		var b := Sprite2D.new()
		b.name = "OozeBubble%d" % i
		b.texture = _ooze_bubble_tex
		b.scale = Vector2(0.4, 0.4)
		b.modulate = Color(1, 1, 1, 0.85)
		# Over the body: the bubbles rise THROUGH the amber sprite (opaque),
		# and they are built before _sprite is added to _body (see _build),
		# so child order alone would bury them — z_index pins them on top.
		b.z_index = 1
		_body.add_child(b)
		_ooze_bubbles.append(b)


func _animate_ooze(delta: float) -> void:
	if _sprite == null:
		return
	_ooze_t += delta
	# Drunken wobble: squash-and-stretch from the captured base scale.
	var w: float = sin(_ooze_t * 3.4)
	_sprite.scale = _base_sprite_scale * Vector2(1.0 + 0.09 * w, 1.0 - 0.07 * w)
	var h: float = _monster_scale()
	for i in _ooze_bubbles.size():
		var b := _ooze_bubbles[i]
		if not is_instance_valid(b):
			continue
		var ph: float = _ooze_phase[i] if i < _ooze_phase.size() else 0.0
		var cyc: float = fmod(_ooze_t * 0.45 + ph, 1.0)
		b.position = Vector2(
			sin(ph * 37.0 + _ooze_t * 1.3) * h * 0.26,
			-h * 0.12 - cyc * h * 0.78)
		var grow: float = 0.35 + 0.5 * cyc
		b.scale = Vector2(grow, grow)
		b.modulate.a = 0.9 * (1.0 - cyc * cyc)


## 2026-10-08 (wake graphics-hourly): karaoke barbarian concert rig.
## Body child (freed + ref-cleared on rebuild like the ooze bubbles);
## the world sync toggles it via set_performing() while "belting".
func _build_concert_fx() -> void:
	var fx := ConcertFX.new()
	fx.name = "ConcertFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: translucent beams wash over the performer. The FX is
	# built before _sprite is added to _body (see _build), so child order
	# alone would bury it — z_index pins it on top (same as the doomscroll,
	# mlm, dmv, and twister rigs).
	fx.z_index = 2
	_body.add_child(fx)
	_concert_fx = fx


## 2026-10-08 (wake graphics-hourly): doomscroller screen-glow rig.
## Body child (freed + ref-cleared on rebuild like the concert FX);
## always scrolling while Milo lives — no sim toggle needed.
func _build_doomscroll_fx() -> void:
	var fx := DoomscrollFX.new()
	fx.name = "DoomscrollFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the glow washes OVER the face and phone. The FX is
	# built before _sprite is added to _body (see _build), so child order
	# alone would bury it — z_index pins it on top.
	fx.z_index = 2
	_body.add_child(fx)
	_doomscroll_fx = fx


## 2026-10-08 (wake rapid-iteration): MLM bro opportunity-sparkles rig.
## Body child (freed + ref-cleared on rebuild like the doomscroll FX);
## always pitching while Chad lives — no sim toggle needed.
func _build_mlm_fx() -> void:
	var fx := MLMBroFX.new()
	fx.name = "MLMBroFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the sparkles and pitch ring wash OVER the suit
	# and briefcase. The FX is built before _sprite is added to _body
	# (see _build), so child order alone would bury it — z_index pins it
	# on top.
	fx.z_index = 2
	_body.add_child(fx)
	_mlm_fx = fx


## 2026-10-08 (wake rapid-iteration): DMV clerk ticket-window rig.
## Body child (freed + ref-cleared on rebuild like the MLM FX); the
## world sync drives it via set_dmv_state() while Dave's table is open.
func _build_dmv_fx() -> void:
	var fx := DMVClerkFX.new()
	fx.name = "DMVClerkFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the marquee and stubs wash OVER the table art.
	# The FX is built before _sprite is added to _body (see _build),
	# so child order alone would bury it — z_index pins it on top.
	fx.z_index = 2
	_body.add_child(fx)
	_dmv_fx = fx


## Push DMV window state into the ticket-window rig. Safe to call when
## the FX was never built (non-DMV jobs share this sync path).
func set_dmv_state(on_lunch: bool, now_serving: int, table_open: bool) -> void:
	if _dmv_fx != null and is_instance_valid(_dmv_fx):
		_dmv_fx.set_dmv_state(on_lunch, now_serving, table_open)


## 2026-10-08 (wake graphics-hourly): twister sister funnel-spin rig.
## Body child (freed + ref-cleared on rebuild like the MLM FX); always
## spinning while she rampages — no sim toggle needed.
func _build_twister_fx() -> void:
	var fx := TwisterSisterFX.new()
	fx.name = "TwisterSisterFX"
	fx.stage_h = _monster_scale()
	# The funnel sprite is the static PNG; the FX adds the living
	# geometry — spiral bands, debris, dust, lightning — washing OVER
	# her. Built before _sprite is added to _body (see _build), so
	# z_index pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_twister_fx = fx


## 2026-10-08 (wake rapid-iteration): warranty salesman doorstep-pitch
## rig. Body child (freed + ref-cleared on rebuild like the other FX
## rigs); the world sync drives the pitch state via set_warranty_state()
## off combat_state == "pitching" and the warranty_sales counter.
func _build_warranty_fx() -> void:
	var fx := WarrantyFX.new()
	fx.name = "WarrantyFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the certificates, the EXPIRED stamp, and the sale
	# coins wash OVER the suit and briefcase. The FX is built before
	# _sprite is added to _body (see _build), so child order alone would
	# bury it — z_index pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_warranty_fx = fx


## Push warranty pitch state into the doorstep-pitch rig. Safe to call
## when the FX was never built (non-warranty jobs share this sync path)
## — no-op.
func set_warranty_state(pitching: bool, sales: int) -> void:
	if _warranty_fx != null and is_instance_valid(_warranty_fx):
		_warranty_fx.set_warranty_state(pitching, sales)


func _build_crossfit_fx() -> void:
	var fx := CrossFitFX.new()
	fx.name = "CrossFitFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the burpee dust, the sweat drops, and the shaker
	# glint wash OVER the tank top and headband. The FX is built before
	# _sprite is added to _body (see _build), so child order alone would
	# bury it — z_index pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_crossfit_fx = fx


func _build_influencer_fx() -> void:
	var fx := InfluencerFX.new()
	fx.name = "InfluencerFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the ring-light halo, the floating hearts, and the
	# camera flashes wash OVER the crop top and ponytail. The FX is built
	# before _sprite joins _body (see _build), so child order alone would
	# bury it — z_index pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_influencer_fx = fx


## 2026-10-08 (wake deep-work, Disaster #26): Prince Gnomba "royal
## treasury" rig. Body child (freed + ref-cleared on rebuild like the
## influencer FX); always pitching while the prince lives.
func _build_gnomba_fx() -> void:
	var fx := GnombaFX.new()
	fx.name = "GnombaFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the rising coin motes and crown glint wash OVER
	# the agbada and coin purse. The FX is built before _sprite joins
	# _body (see _build), so child order alone would bury it — z_index
	# pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_gnomba_fx = fx


## 2026-10-08 (massive-dev, Disaster #27): DJ Weddington dance-floor
## rig. Body child (freed + ref-cleared on rebuild like the gnomba FX);
## always spinning while the set plays.
func _build_dj_fx() -> void:
	var fx := DjFX.new()
	fx.name = "DjFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the mirror-ball beams, rising notes, and EQ bars
	# wash OVER the headphones and decks. The FX is built before _sprite
	# joins _body (see _build), so child order alone would bury it —
	# z_index pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_dj_fx = fx


## 2026-10-08 (wake routine, Disaster #28 completion): Ricky the Repo
## Gnome tow rig. Body child (freed + ref-cleared on rebuild like the
## other monster rigs); always pitching while Ricky lives.
func _build_repo_fx() -> void:
	var fx := RepoFX.new()
	fx.name = "RepoFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the tow chain, hook, hazard chevrons, and
	# foreclosure paperwork wash OVER the cap and clipboard. The FX is
	# built before _sprite joins _body (see _build), so child order alone
	# would bury it — z_index pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_repo_fx = fx


## Rapid-iteration 2026-10-08 (Disaster #29): Milo the Podcast Bro ON AIR
## rig. Body child (freed + ref-cleared on rebuild like the other monster
## rigs); always recording while Milo lives.
func _build_podcast_fx() -> void:
	var fx := PodcastFX.new()
	fx.name = "PodcastFX"
	fx.stage_h = _monster_scale()
	# Above the sprite: the ON AIR sign, mic icons, sound waves and
	# ring-light halo wash OVER the cap and headphones. The FX is built
	# before _sprite joins _body (see _build), so child order alone would
	# bury it — z_index pins it on top, like the other monster rigs.
	fx.z_index = 2
	_body.add_child(fx)
	_podcast_fx = fx


## Toggle the concert rig. Safe to call when the FX was never built
## (non-karaoke jobs) — no-op.
func set_performing(active: bool) -> void:
	if _concert_fx != null and is_instance_valid(_concert_fx):
		_concert_fx.set_performing(active)


func is_performing() -> bool:
	return _concert_fx != null and is_instance_valid(_concert_fx) \
		and _concert_fx.is_performing()


var _culled: bool = false
## Jeremy 2026-10-08 (wake deep-systems): units inside buildings
## (inside_building_id > 0 — siege hiding, urge sleep, etc.) are hidden
## on the main map. The interior_view shows them when the building is
## opened. Separate from culling (off-screen) — both hide the sprite.
var _inside: bool = false


## 2026-10-07 (wake deep-systems): COUNT BASTARD theatrics. Ranting (at
## the hall, stationary) = theatrical oratory sway with a deep mocking
## bow every insult cadence; traveling = cape billow rocked over the
## standard UnitAnimator walk bounce. Cheap: two sin calls per frame.
func _animate_bastard(delta: float) -> void:
	if _sprite == null:
		return
	_bastard_t += delta
	if anim != null and anim.moving:
		_sprite.rotation = sin(_bastard_t * 7.0) * 0.06
		_sprite.scale = _base_sprite_scale
	else:
		var w: float = sin(_bastard_t * 2.6)
		_sprite.rotation = w * 0.10
		var bow_cyc: float = fmod(_bastard_t, BASTARD_BOW_PERIOD)
		var bow := 0.0
		if bow_cyc < 0.9:
			bow = sin(bow_cyc / 0.9 * PI) * 0.16
		_sprite.scale = _base_sprite_scale \
			* Vector2(1.0 + bow * 0.5, 1.0 - bow)


## Called by the world sync on the tier cadence: disables _process when
## the unit is off-screen (with margin), re-enables when it comes back.
## Only toggles when the state changes — set_process() has a cost.
## Jeremy 2026-10-04: also toggles visibility — off-screen units skip the
## render pipeline entirely (draw-call reduction for 60fps). Position is
## still synced by the world every tick, so re-appearing units land in the
## right spot. Position is
## still synced by the world every tick, so re-appearing units land in the
## right spot.
func set_culled(culled: bool) -> void:
	if culled == _culled:
		return
	_culled = culled
	_update_visibility()
	# Reset the movement tracker so re-appearing doesn't glitch the
	# walk/idle state for a frame.
	if not culled and not _inside:
		_last_px = position.x
		_last_pos = position  # no phantom wake burst on re-appear


## Jeremy 2026-10-08 (wake deep-systems): hide/show for inside-building
## state. Units with inside_building_id > 0 (siege hiding, sleeping,
## etc.) vanish from the main map; the interior view shows them.
## Combined with culling — either hides the sprite.
func set_inside(inside: bool) -> void:
	if inside == _inside:
		return
	_inside = inside
	_update_visibility()
	# Reset the movement tracker so re-appearing doesn't glitch.
	if not inside and not _culled:
		_last_px = position.x
		_last_pos = position


## Single visibility gate: hidden when culled (off-screen) OR inside
## a building. Keeps set_culled and set_inside from fighting.
func _update_visibility() -> void:
	var show: bool = not _culled and not _inside
	set_process(show)
	visible = show


func _process(delta: float) -> void:
	if anim == null or _body == null:
		return
	# Procedural normal-map wrap follows texture swaps (mooning, appearance
	# changes, monster forms) — apply_to is a no-op when already wrapped.
	if _sprite != null:
		SpriteNormalsScript.apply_to(_sprite)
	# Movement read for walk/idle + facing. Position itself is set by the
	# world sync; the animator never touches it (animation law).
	var dx: float = position.x - _last_px
	_last_px = position.x
	var d: Vector2 = position - _last_pos
	_last_pos = position
	if _boat != null:
		# Naval units: wave motion only, no chibi choreography, no flip
		# (HTML _toonDrawCharacter boat branch never flips). The foam wake
		# trails from the stern while the boat is actually sailing.
		_boat_animate(delta)
		if _wake != null and _boat_w > 0.0:
			var moved: float = d.length()
			var stern := Vector2.ZERO
			if moved > 0.5:
				stern = -d / moved * _boat_w * 0.42 + Vector2(0, 5.0)
			_wake.tick(delta, moved, stern, 6.0)
	else:
		# Animation law (Jeremy 2026-09-19): derive state from actual
		# activity. A unit traveling straight up/down (or diagonally)
		# barely changes x — the old x-only check left it "not moving",
		# so it fidgeted through the idle cycle while sliding across the
		# map. Real 2D displacement decides.
		anim.moving = d.length() > 0.5
		# giant_ass has no sprite (procedural butt) — guard the flip.
		if _sprite != null:
			if dx > 0.5:
				_sprite.flip_h = false
			elif dx < -0.5:
				_sprite.flip_h = true
		anim.tick(delta)
		anim.apply_to(_body)
		if _swimming:
			# Paddling bob layered over the animator's pose (swim is a
			# visual overlay, not an animator state).
			_swim_t += delta
			_ensure_swim_band()
			var sw := sin(_swim_t * 9.0)
			_body.position.y += -absf(sw) * 1.8
			_body.rotation += sw * 0.05
			_wave_swim_band()
			queue_redraw()  # ripple rings animate in _draw
		if _downed:
			# Knocked-out overlay: prone + still, revive ring pulsing.
			_apply_downed_pose(delta)
		_update_tool(delta)
		# Jeremy 2026-10-04: Jesus 2-frame pixel-art walk cycle — stepped at
		# ~7 Hz while moving, parked on frame 0 at rest. The UnitAnimator
		# still owns the body bounce; this only swaps the sprite frame.
		# Singleton unit: trivial cost.
		if job == "jesus" and _sprite != null and _sprite.hframes > 1:
			if anim.moving:
				_jesus_frame_t = fmod(_jesus_frame_t + delta, 2.0 / 7.0)
				_sprite.frame = int(_jesus_frame_t * 7.0) % _sprite.hframes
			elif _sprite.frame != 0:
				_sprite.frame = 0
				_jesus_frame_t = 0.0
		# 2026-10-07: disaster-unit life — seagull flock flap/orbit and
		# booze-ooze wobble + rising bubbles. Culled with the unit.
		if job == "seagull_swarm":
			_animate_seagulls(delta)
		elif job == "booze_ooze":
			_animate_ooze(delta)
		elif job == "count_bastard":
			_animate_bastard(delta)
	# Jeremy 2026-10-04: thicc moose butt shake while mooning.
	if _mooning and job == "thicc_moose" and _sprite != null:
		_moon_time += delta
		var w: float = sin(_moon_time * 12.0)
		_sprite.position.x = w * 8.0
		_sprite.rotation = w * 0.15
		# Squash-and-stretch on the butt cheeks for extra comedy.
		_sprite.scale = _base_sprite_scale \
			* Vector2(1.0 + 0.07 * w, 1.0 - 0.07 * w)
	# HTML hurt flash: white silhouette, strongest right after the hit
	# lands (fix79:39034). Decays in real time; the overlay hides at the
	# 0.01 cutoff. Idle units pay one float compare per frame.
	if _hurt_t > 0.0:
		_hurt_t = maxf(0.0, _hurt_t - delta)
		_sync_flash()
	# Shadow follows the feet + the sun; redraw only when the quantized
	# shadow key changes (cheap: sun drifts slowly over the 8-minute day).
	# The swimming bit folds the shadow MODE into the key so entering or
	# exiting water swaps ground blob <-> water shadow immediately.
	var sk := Shadows.shadow_key(position, _swimming)
	if sk != _shadow_key:
		_shadow_key = sk
		queue_redraw()


## Drive the animator from a WorkerAI work_state (called by world sync).
## gather_kind is the work site's kind ("tree"|"rock"|"gold_vein"|"bush"|""):
## trees chop with an axe, mineral/oil deposits mine with a pickaxe, and
## everything else keeps the generic WORK rhythm. Builders swing the hammer
## (HAMMER), farmers till with the hoe (HOE), and fishers cast/wait/yank
## with the rod (FISH), and hunters stalk/strike/recover with the spear
## (HUNT). Firefighters and station workers keep WORK.
## (Jeremy 2026-10-04/05/06.)
## equipped_tool is the unit's real owned tool from the petitions system —
## it wins over the work-kind guess (HTML toolImg54For parity), and is
## carried visibly on the way to work, not just mid-swing.
func set_work_state(work_state: String, gather_kind: String = "",
		equipped_tool: String = "", work_pose: String = "",
		carry_kind: String = "") -> void:
	if anim == null:
		return
	# Jeremy 2026-10-08: one-shots own the body until they settle. The world
	# sync calls this every frame, which used to stomp ATTACK/HURT after a
	# single rendered frame — battles showed no attack animation at all
	# (verified headless: play_attack then one idle sync -> state "idle").
	# DEATH is already terminal inside set_state.
	if anim.state == UnitAnimator.ATTACK \
			or anim.state == UnitAnimator.HURT \
			or anim.state == UnitAnimator.CELEBRATE:
		return
	_equipped_tool = equipped_tool if equipped_tool in _KNOWN_TOOLS else ""
	# Jeremy 2026-10-06: shoulder-load bundle (animation gate #3). Haulers
	# walk a full carry to the dropoff; only travel states show it — swing
	# loops keep the load off the ground they are harvesting.
	_set_load("")
	# Jeremy 2026-10-05: thought bubbles removed — no bubble pops on
	# urge/activity change anymore.
	match work_state:
		"idle":
			# Animation law (Jeremy 2026-10-06): actual movement wins over
			# the declared idle. The sim leaves work_state "idle" for
			# villagers who are really traveling (wandering, socializing,
			# fleeing) — forcing IDLE made them fidget through the idle
			# cycle while sliding across the map. A unit that is actually
			# moving gets the walk bounce, always. Death stays terminal
			# (guarded inside set_state); a declared idle at rest keeps
			# the old reset-to-IDLE semantics.
			if anim.moving and anim.state != UnitAnimator.DEATH:
				anim.set_state(UnitAnimator.WALK)
			elif not anim.moving:
				anim.set_state(UnitAnimator.IDLE)
			_set_tool("")
		"gathering":
			match gather_kind:
				"tree":
					anim.set_state(UnitAnimator.CHOP)
					_set_tool(_pick_tool("axe"))
				"rock", "gold_vein":
					anim.set_state(UnitAnimator.MINE)
					_set_tool(_pick_tool("pickaxe"))
				"wood_pile":
					# Jeremy 2026-10-04: wood piles are gathered, not chopped.
					# CHOP animation on a pile looked wrong.
					anim.set_state(UnitAnimator.WORK)
					_set_tool(_equipped_tool)
				_:
					anim.set_state(UnitAnimator.WORK)
					_set_tool(_pick_tool(
						String(_TOOL_FOR_SITE.get(gather_kind, ""))))
		"building", "repairing":
			# Jeremy 2026-10-05: dedicated HAMMER loop — builders swing the
			# smith's hammer overhead instead of the generic WORK bob.
			anim.set_state(UnitAnimator.HAMMER)
			_set_tool(_pick_tool("hammer"))
		"tending", "plot_chore":
			# Jeremy 2026-10-05: dedicated HOE loop — farmers till the plot
			# with a proper soil-drag swing.
			anim.set_state(UnitAnimator.HOE)
			_set_tool(_pick_tool("hoe"))
		"healing":
			anim.set_state(UnitAnimator.WORK)
			_set_tool("")
		"fishing":
			# Jeremy 2026-10-06: dedicated FISH loop — the fisher casts,
			# waits, and yanks on the sim's catch cadence instead of
			# walking in place at the lake.
			anim.set_state(UnitAnimator.FISH)
			_set_tool(_pick_tool("fishingrod"))
		"extinguishing", "working":
			# Stationary duty (firefighter at a fire, shopkeeper at a
			# station) — WORK rhythm, owned tool carried at the hand.
			# Jeremy 2026-10-06: the sim's work_pose channel is honored —
			# a desk worker (pose "sit") plays the seated SIT loop with the
			# tool hidden instead of standing at the desk.
			if work_state == "working" and work_pose == "sit":
				anim.set_state(UnitAnimator.SIT)
				_set_tool("")
			else:
				anim.set_state(UnitAnimator.WORK)
				_set_tool(_equipped_tool)
		"hunting":
			# Jeremy 2026-10-06: dedicated HUNT loop — the hunter stalks
			# and strikes on the sim's HUNT_CD cadence instead of walking
			# in place at the prey (the sim already sets work_pose
			# "attack"; the world layer used to drop it).
			anim.set_state(UnitAnimator.HUNT)
			_set_tool(_pick_tool(""))
		"off_shift":
			# Jeremy 2026-10-06: the sim marks arrived resters with
			# work_pose "rest" — they idle-breathe at home instead of
			# walking in place; walkers heading out keep WALK.
			# Jeremy 2026-10-08: work_pose "dance" — off-shift citizens at
			# a festival plaza dance (the Gazette's promised "Dancing!").
			if work_pose == "dance":
				anim.set_state(UnitAnimator.DANCE)
				_set_tool("")
			elif work_pose == "rest":
				anim.set_state(UnitAnimator.IDLE)
				_set_tool("")
			else:
				anim.set_state(UnitAnimator.WALK)
				_set_tool(_equipped_tool)
		_:
			# to_resource / to_dropoff / to_build / to_repair / to_patient /
			# to_shop / to_plot / to_tend ... — walk with the owned tool
			# carried at the hand (HTML draws the tool in-hand; the swing
			# itself only plays in CHOP/MINE). Jeremy 2026-10-06: haulers
			# (to_dropoff) also carry the load bundle on the shoulder — the
			# world sync only ever passes a carry kind for to_dropoff.
			anim.set_state(UnitAnimator.WALK)
			_set_tool(_equipped_tool)
			_set_load(carry_kind)


## Equipped tool wins; otherwise the role fallback. Unknown/empty -> "".
## (Port of HTML toolImg54For's priority: equippedTool, then work kind.)
func _pick_tool(fallback: String) -> String:
	if _equipped_tool != "":
		return _equipped_tool
	return fallback


## Build (or no-op) the tool pivot under the Body. Renders above the chibi
## sprite; follows body lift/rock/squash since it's a Body child.
func _ensure_tool() -> void:
	if _tool_pivot != null:
		return
	_tool_pivot = Node2D.new()
	_tool_pivot.name = "ToolPivot"
	_tool_pivot.visible = false
	_body.add_child(_tool_pivot)
	_tool_sprite = Sprite2D.new()
	_tool_sprite.name = "Tool"
	_tool_pivot.add_child(_tool_sprite)
	_spark_pos.resize(_SPARK_N)
	_spark_vel.resize(_SPARK_N)


## Show/hide the hand tool. Early-out on no change (called every frame by
## the world sync); missing art hides the overlay instead of crashing.
func _set_tool(kind: String) -> void:
	if _boat != null:
		return  # boats skip the chibi tool overlay entirely
	_ensure_tool()
	if kind == _tool_kind:
		return
	_tool_kind = kind
	if kind == "":
		_tool_pivot.visible = false
		return
	var tex: Texture2D = Art.tool_texture(kind)
	if tex == null:
		# Missing art: hide the overlay and clear the kind so _update_tool
		# doesn't re-show an empty pivot (would render as a white box).
		_tool_kind = ""
		_tool_pivot.visible = false
		return
	_tool_pivot.visible = true
	_tool_sprite.texture = tex
	SpriteNormalsScript.apply_to(_tool_sprite)
	# Grip sits on the pivot: the diagonal tool art's handle end is at
	# ~(0.19, 0.81) of the 63x64 texture, i.e. (-19.5, +19.8) px from the
	# sprite center — recenter so it lands on the pivot origin. The art's
	# head-to-grip span is ~56 px; scale it to _TOOL_WORLD_LEN.
	var sc: float = _TOOL_WORLD_LEN / 56.0
	_tool_sprite.scale = Vector2(sc, sc)
	_tool_sprite.position = Vector2(19.5 * sc, -19.8 * sc)


## Build (or no-op) the shoulder-load pivot under the Body. Renders above the
## chibi sprite beside the head; as a Body child it rides the WALK bounce,
## rock and squash from anim.apply_to(_body) exactly — the carried load
## visibly hefts with each step instead of sliding frozen.
func _ensure_load() -> void:
	if _load_pivot != null:
		return
	_load_pivot = Node2D.new()
	_load_pivot.name = "LoadPivot"
	_load_pivot.visible = false
	_body.add_child(_load_pivot)
	_load_sprite = Sprite2D.new()
	_load_sprite.name = "Load"
	_load_pivot.add_child(_load_sprite)


## Show/hide the shoulder bundle. Deposit art (the exact sprite the ground
## pickups use) wins so collection reads as picking it up; the HUD icon is
## the fallback for kinds with no deposit sprite (food). Missing art hides
## the overlay instead of crashing — never a white square.
func _set_load(kind: String) -> void:
	if _boat != null:
		return  # boats skip the chibi load overlay entirely
	_ensure_load()
	if kind == _load_kind:
		return
	_load_kind = kind
	if kind == "":
		_load_pivot.visible = false
		return
	var tex: Texture2D = Art.resource_node_texture(kind)
	if tex == null:
		tex = Art.resource_icon(kind)
	if tex == null:
		_load_kind = ""
		_load_pivot.visible = false
		return
	_load_pivot.visible = true
	_load_sprite.texture = tex
	SpriteNormalsScript.apply_to(_load_sprite)
	# Scale to a shoulderable bundle; sit it on the shoulder slot — the
	# per-frame _update_tool mirror keeps it on the facing side.
	var sc: float = _LOAD_WORLD_H / float(tex.get_height())
	_load_sprite.scale = Vector2(sc, sc)
	_load_sprite.position = Vector2.ZERO


## Mirror the tool sprite for the facing direction. The tool art is drawn
## for facing-right (blade up-right); when the gnome faces left the sprite
## itself must flip or the blade points away from the target. The grip
## offset mirrors with it so the handle stays on the pivot.
## (Jeremy 2026-10-05: "axes are backwards".)
func _mirror_tool_sprite(face: float) -> void:
	if _tool_sprite == null:
		return
	var left: bool = face < 0.0
	if _tool_sprite.flip_h == left:
		return  # already correct; also skips the position rewrite
	_tool_sprite.flip_h = left
	var sc: float = _TOOL_WORLD_LEN / 56.0
	_tool_sprite.position = Vector2(
		(-19.5 if left else 19.5) * sc, -19.8 * sc)


## Per-frame tool swing + strike impact FX (called from _process after
## anim.apply_to). The pivot mirrors the sprite's facing; on the strike
## edge of each swing loop a pooled spark burst fires.
func _update_tool(delta: float) -> void:
	var st: String = anim.state
	var swing: bool = st == UnitAnimator.MINE or st == UnitAnimator.CHOP \
		or st == UnitAnimator.HAMMER or st == UnitAnimator.HOE \
		or st == UnitAnimator.FISH or st == UnitAnimator.HUNT
	# Overlapping action: the tool trails the body's swing target by a
	# few frames with its own decay. Zero delta snaps (no time elapsed =
	# no lag can accumulate; keeps the pose deterministic for tests).
	var target := Vector2(0.0, 0.0)
	if swing:
		target = anim.tool_swing()
	if delta <= 0.0:
		_tool_lag = target
	else:
		_tool_lag = _tool_lag.lerp(target, minf(1.0, delta * 12.0))
	if swing:
		var face := 1.0
		if _sprite != null and _sprite.flip_h:
			face = -1.0
		if _tool_pivot != null:
			_tool_pivot.visible = _tool_kind != ""
			_tool_pivot.position = Vector2(
				(_TOOL_HAND.x + _tool_lag.y) * face, _TOOL_HAND.y)
			_tool_pivot.rotation = _tool_lag.x * face
			# Jeremy 2026-10-05: mirror the tool sprite itself when facing
			# left — the pivot rotation mirror alone left the blade pointing
			# up-right (away from the tree).
			_mirror_tool_sprite(face)
		var loop_len: float = anim.work_loop_len()
		var sf: float = anim.strike_frac()
		if loop_len > 0.0 and sf >= 0.0:
			var cyc: float = fmod(anim.state_t, loop_len) / loop_len
			if _strike_prev_cyc < sf and cyc >= sf:
				_fire_strike(_swing_flavor(st))
			_strike_prev_cyc = cyc
	elif (st == UnitAnimator.WORK or st == UnitAnimator.WALK) \
			and _tool_pivot != null:
		# Jeremy 2026-10-05: owned tool carried at the hand — no swing
		# outside CHOP/MINE (HTML rotates by toolAng, 0 when not working).
		var face := 1.0
		if _sprite != null and _sprite.flip_h:
			face = -1.0
		_tool_pivot.visible = _tool_kind != ""
		_tool_pivot.position = Vector2(_TOOL_HAND.x * face, _TOOL_HAND.y)
		_tool_pivot.rotation = _tool_lag.x * face  # eases home (follow-through)
		_mirror_tool_sprite(face)
		_strike_prev_cyc = 0.0
		# Jeremy 2026-10-06: the shoulder bundle rides on the facing-side
		# shoulder and stays level while the Body walks under it (the walk
		# bounce already moves the whole Body — the bundle inherits that,
		# so only the facing mirror needs per-frame care here).
		if _load_pivot != null:
			_load_pivot.visible = _load_kind != ""
			_load_pivot.position = Vector2(_LOAD_SHOULDER.x * face,
					_LOAD_SHOULDER.y)
	elif _tool_pivot != null and _tool_pivot.visible:
		_tool_pivot.visible = false
		_strike_prev_cyc = 0.0
		_tool_lag = Vector2(0.35, 0.0)  # next swing starts from rest
	# Advance the pooled sparks; redraw only while any are alive.
	if _spark_life > 0.0:
		_spark_life -= delta
		var grav: float = 320.0 * delta
		var damp: float = 1.0 - 3.0 * delta
		for i in range(_SPARK_N):
			_spark_vel[i] = _spark_vel[i] * damp + Vector2(0, grav)
			_spark_pos[i] = _spark_pos[i] + _spark_vel[i] * delta
		queue_redraw()


## Impact flavor for a swing state: MINE throws stone sparks, HOE kicks
## up soil dust, FISH pops a water splash, HUNT throws blood flecks, and
## CHOP/HAMMER throw wood chips (building is woodwork).
static func _swing_flavor(st: String) -> int:
	match st:
		UnitAnimator.MINE:
			return _FX_STONE
		UnitAnimator.HOE:
			return _FX_DUST
		UnitAnimator.FISH:
			return _FX_SPLASH
		UnitAnimator.HUNT:
			return _FX_BLOOD
	return _FX_WOOD  # CHOP + HAMMER


## Seed the spark pool at the strike point (node space, just in front of
## the hand). Stone strikes throw pale sparks; wood strikes throw chips;
## hoe strikes kick up soil dust; the fishing yank pops a pale splash
## further out, where the line lands over the water; the hunt kill blow
## throws a low red burst at the prey.
func _fire_strike(flavor: int) -> void:
	_ensure_tool()
	_spark_flavor = flavor
	_spark_stone = flavor == _FX_STONE  # kept for the old stone/wood reads
	_spark_life = _SPARK_LIFE
	var face := 1.0
	if _sprite != null and _sprite.flip_h:
		face = -1.0
	var ox: float = (_TOOL_HAND.x + 16.0) * face
	var oy := -18.0
	if flavor == _FX_SPLASH:
		# The line lands out over the water, past the fisher's hand.
		ox = (_TOOL_HAND.x + 30.0) * face
		oy = -10.0
	for i in range(_SPARK_N):
		var ang: float = -PI / 2.0 + randf_range(-1.1, 1.1) + face * 0.35
		var spd: float = randf_range(60.0, 150.0)
		if flavor == _FX_DUST:
			# Soil dust: slower, loftier, wider cloud than sparks.
			ang = -PI / 2.0 + randf_range(-1.4, 1.4) + face * 0.2
			spd = randf_range(35.0, 90.0)
		elif flavor == _FX_SPLASH:
			# Splash: droplets pop straight up, tight and bright.
			ang = -PI / 2.0 + randf_range(-0.7, 0.7)
			spd = randf_range(70.0, 160.0)
		elif flavor == _FX_BLOOD:
			# Blood: a low red burst at the prey, wetter than sparks.
			ang = -PI / 2.0 + randf_range(-0.9, 0.9) + face * 0.3
			spd = randf_range(50.0, 130.0)
		_spark_vel[i] = Vector2(cos(ang), sin(ang)) * spd
		_spark_pos[i] = Vector2(
			ox + randf_range(-6.0, 6.0), oy + randf_range(-3.0, 3.0))
	queue_redraw()


## Draw the live sparks as short motion streaks. Called from _draw().
func _draw_strike_fx() -> void:
	if _spark_life <= 0.0:
		return
	var alpha: float = clampf(_spark_life / _SPARK_LIFE, 0.0, 1.0)
	var col := Color(0.75, 0.52, 0.28, alpha)  # wood chips
	var width := 2.0
	if _spark_flavor == _FX_STONE:
		col = Color(1.0, 0.82, 0.35, alpha)  # stone sparks
	elif _spark_flavor == _FX_DUST:
		col = Color(0.78, 0.66, 0.50, alpha)  # soil dust
		width = 3.0
	elif _spark_flavor == _FX_SPLASH:
		col = Color(0.78, 0.90, 1.0, alpha)  # splash droplets
		width = 2.5
	elif _spark_flavor == _FX_BLOOD:
		col = Color(0.72, 0.10, 0.08, alpha)  # blood flecks
		width = 2.5
	for i in range(_SPARK_N):
		var p: Vector2 = _spark_pos[i]
		draw_line(p, p - _spark_vel[i] * 0.035, col, width)


func set_job(p_job: String) -> void:
	if p_job == job:
		return
	var was_boat: bool = _boat != null
	var was_monster: bool = job in _MONSTER_JOBS
	job = p_job
	var is_monster: bool = job in _MONSTER_JOBS
	if was_boat or job in _BOAT_JOBS or was_monster or is_monster:
		# Boat <-> non-boat swap: rebuild the visual subtree from scratch
		# (never happens in the sim — boats are trained as boats — but be
		# safe). 2026-10-07: same for monster <-> anything — monster jobs
		# build whole-subtree visuals (seagull flock, ooze bubbles,
		# procedural butt) that a plain sprite re-pick would leave stale.
		if _body != null:
			remove_child(_body)
			_body.queue_free()
		_boat = null
		_pennant = null
		_wake = null  # child of Body: freed with it on the rebuild above
		_sprite = null
		_build()
		return
	# Re-pick sprite for the new archetype.
	if _sprite != null:
		var tex: Texture2D = Art.unit_texture(faction, job, unit_id, gender)
		if tex != null:
			_sprite.texture = tex


## Combat one-shots, driven edge-triggered by the world sync (Milestone 4).
## Death holds forever (animator); the world frees the node after the clip.
func play_attack() -> void:
	if anim != null:
		anim.set_state(UnitAnimator.ATTACK)
	# Jeremy 2026-10-05: combat thought bubbles REMOVED at Jeremy's call —
	# they risked blocking the battle view. Attack animation still plays;
	# no bubble pops for combat.


func play_hurt() -> void:
	if anim != null:
		anim.set_state(UnitAnimator.HURT)
	# HTML _hurtT (fix79:35279): every survived hit restarts the 0.45 s
	# white-silhouette flash. The world sync edge-triggers this on the
	# combat_state -> "hurt" transition, and the combat tick rewrites
	# combat_state every tick, so repeated hits re-arm the flash.
	_hurt_t = HURT_FLASH_LEN
	_sync_flash()


## Jeremy 2026-10-08: building-completion celebration (HTML _celebrateT
## parity — fix79: u.buildTarget === this -> u._celebrateT = 2.4). The
## sim stamps unit["_celebrate_t"] on the build crew; the world sync
## edge-triggers this and consumes the flag, like the combat one-shots.
func play_celebrate() -> void:
	if anim != null:
		anim.set_state(UnitAnimator.CELEBRATE)


## Build the hurt-flash overlay: a hidden sibling Sprite2D with a per-unit
## white-silhouette ShaderMaterial. No-op when there is no sprite
## (giant_ass is fully procedural).
func _make_flash(parent: Node) -> void:
	if _sprite == null:
		return
	_flash = Sprite2D.new()
	_flash.name = "HurtFlash"
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = _FLASH_SHADER
	_flash_mat.set_shader_parameter("flash_alpha", 0.0)
	_flash.material = _flash_mat
	_flash.visible = false
	parent.add_child(_flash)


## Mirror the main sprite onto the hurt-flash overlay and set its alpha.
## Called on play_hurt() and every frame while the flash is live, so texture
## swaps (mooning), atlas frames (Jesus), flips, and the butt-shake squash
## all carry over exactly. HTML-verbatim alpha (fix79:39041):
## min(0.75, _hurtT * 2.2), hidden at/below the 0.01 cutoff.
func _sync_flash() -> void:
	if _flash == null or not is_instance_valid(_flash):
		return
	if _sprite == null or not is_instance_valid(_sprite) \
			or _flash_mat == null or _hurt_t <= 0.01:
		_flash.visible = false
		return
	_flash.visible = true
	# Unwrap the CanvasTexture normal-map wrapper: the flash overlay wants
	# the raw albedo texture.
	_flash.texture = SpriteNormalsScript.diffuse_of(_sprite.texture)
	_flash.hframes = _sprite.hframes
	_flash.vframes = _sprite.vframes
	_flash.frame = _sprite.frame
	_flash.flip_h = _sprite.flip_h
	_flash.flip_v = _sprite.flip_v
	_flash.centered = _sprite.centered
	_flash.offset = _sprite.offset
	_flash.position = _sprite.position
	_flash.rotation = _sprite.rotation
	_flash.scale = _sprite.scale
	_flash_mat.set_shader_parameter(
		"flash_alpha", minf(0.75, _hurt_t * 2.2))


func play_death() -> void:
	if anim != null:
		anim.set_state(UnitAnimator.DEATH)
	# A downed unit that bleeds out dies: clear the prone pose + revive ring
	# so the DEATH clip owns the body.
	if _downed:
		_downed = false
		queue_redraw()


## Milestone 7: fire truck visual. When a firefighter is on_truck (rapid
## response), show the fire truck sprite under them.
var _truck_sprite: Sprite2D = null

func set_on_truck(on: bool) -> void:
	if on and _truck_sprite == null:
		var tex: Texture2D = Art.vehicle_texture("veh_fire_truck")
		if tex != null:
			_truck_sprite = Sprite2D.new()
			_truck_sprite.texture = tex
			SpriteNormalsScript.apply_to(_truck_sprite)
			var sc: float = (SPRITE_WORLD_H * 1.6) / float(tex.get_height())
			_truck_sprite.scale = Vector2(sc, sc)
			_truck_sprite.position = Vector2(0, -SPRITE_WORLD_H * 0.3)
			_body.add_child(_truck_sprite)
			_truck_sprite.z_index = -1  # truck under the firefighter
	elif not on and _truck_sprite != null:
		_truck_sprite.queue_free()
		_truck_sprite = null


## Bloody stump overlay for severed limbs (Halo 1 style: bright vibrant red).
## Child of the sprite so it inherits flip_h/scale. Texture space (~192 px
## chibi): arms sever at the shoulder (+/-58, +5), legs at the hip (+/-25, +55).
class _LimbOverlay:
	extends Node2D
	# limb key -> stump center in texture px
	const STUMP_POS := {
		"leftArm": Vector2(-58, 5), "rightArm": Vector2(58, 5),
		"leftLeg": Vector2(-25, 55), "rightLeg": Vector2(25, 55),
	}
	var _missing: Array[String] = []

	func set_missing(limbs: Dictionary) -> void:
		_missing.clear()
		for k: String in STUMP_POS.keys():
			if not bool(limbs.get(k, true)):
				_missing.append(k)
		queue_redraw()

	func _draw() -> void:
		for k: String in _missing:
			var c: Vector2 = STUMP_POS[k]
			# Dark wound outline, then the Halo-bright stump.
			draw_circle(c, 13.0, Color(0.35, 0.03, 0.04, 0.95))
			draw_circle(c, 9.5, Color(0.92, 0.10, 0.13, 0.98))
			# Juicy highlight.
			draw_circle(c + Vector2(-3, -3), 3.2, Color(1.0, 0.42, 0.42, 0.9))
			# Blood drips running down from the stump.
			draw_circle(c + Vector2(-4, 14), 3.0, Color(0.85, 0.08, 0.10, 0.9))
			draw_circle(c + Vector2(5, 19), 2.2, Color(0.85, 0.08, 0.10, 0.85))


## Faction-styled hazmat suit, HTML drawRadiationSuit parity (fix79).
## Feet-origin world coords (the HTML draws in unit-center space; feet
## sit at +0.85s there, so every y shifts by -0.85s). s = unit height/1.85
## so the helmet top lands at the head and the boots at the feet.
class _SuitOverlay:
	extends Node2D
	var faction := "humans"
	var rad_level := 0.0
	var unit_h := 44.0

	func _draw() -> void:
		var cols: Array = UnitNode.suit_palette(faction)
		var body: Color = cols[0]
		var trim: Color = cols[1]
		var visor: Color = cols[2]
		var tank: Color = cols[3]
		var s: float = unit_h / 1.85
		# Boots.
		draw_rect(Rect2(-0.45 * s, -0.40 * s, 0.35 * s, 0.40 * s), trim)
		draw_rect(Rect2(0.10 * s, -0.40 * s, 0.35 * s, 0.40 * s), trim)
		# Body suit.
		draw_rect(Rect2(-0.55 * s, -1.00 * s, 1.1 * s, 0.75 * s), body)
		draw_rect(Rect2(-0.55 * s, -1.00 * s, 1.1 * s, 0.75 * s),
			trim, false, 1.5)
		# Chest plate + faction mark (HTML per-race shapes).
		draw_rect(Rect2(-0.35 * s, -0.80 * s, 0.7 * s, 0.28 * s), trim)
		var mc := Color(visor.r, visor.g, visor.b, 0.85)
		match faction:
			"humans":
				draw_rect(Rect2(-0.15 * s, -0.75 * s, 0.3 * s, 0.12 * s), mc)
			"ogres":
				draw_circle(Vector2(0, -0.67 * s), 0.12 * s, mc)
			"gnomes":
				draw_colored_polygon(PackedVector2Array([
					Vector2(0, -0.80 * s),
					Vector2(0.15 * s, -0.57 * s),
					Vector2(-0.15 * s, -0.57 * s)]), mc)
			_:
				# elf/undead ellipse mark.
				draw_set_transform(Vector2(0, -0.67 * s), 0.0,
					Vector2(1.0, 0.10 / 0.18))
				draw_circle(Vector2.ZERO, 0.18 * s, mc)
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Air tank on the back.
		draw_rect(Rect2(-0.85 * s, -0.95 * s, 0.28 * s, 0.55 * s), tank)
		draw_rect(Rect2(-0.85 * s, -0.95 * s, 0.28 * s, 0.55 * s),
			trim, false, 1.0)
		# Hose (HTML quadratic curve, 8-segment approx).
		var hose := PackedVector2Array()
		var hp0 := Vector2(-0.7 * s, -0.90 * s)
		var hp1 := Vector2(-0.3 * s, -1.35 * s)
		var hp2 := Vector2(0, -1.20 * s)
		for i in range(9):
			var t := float(i) / 8.0
			hose.append(hp0.lerp(hp1, t).lerp(hp1.lerp(hp2, t), t))
		draw_polyline(hose, Color("#90a4ae"), 2.0)
		# Helmet + visor glass.
		draw_circle(Vector2(0, -1.30 * s), 0.55 * s, body)
		draw_arc(Vector2(0, -1.30 * s), 0.55 * s, 0.0, TAU, 24, trim, 2.0)
		var vc := Color(visor.r, visor.g, visor.b, 0.75)
		draw_set_transform(Vector2(0.08 * s, -1.30 * s), 0.1,
			Vector2(1.0, 0.28 / 0.38))
		draw_circle(Vector2.ZERO, 0.38 * s, vc)
		draw_arc(Vector2.ZERO, 0.38 * s, 0.0, TAU, 24, trim, 1.5)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# High-rad glow ring (HTML pulses it; static alpha here — the
		# unit's own walk cycle carries the motion, zero redraw churn).
		if rad_level > 0.4:
			draw_arc(Vector2(0, -0.85 * s), 1.1 * s, 0.0, TAU, 32,
				Color(180.0 / 255.0, 1.0, 60.0 / 255.0, 0.5), 3.0)
		# RAD pip (HTML-verbatim label pip).
		var font: Font = ThemeDB.fallback_font
		var tw: float = font.get_string_size("RAD",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
		draw_string(font, Vector2(-tw * 0.5, -2.0 * s), "RAD",
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, visor)
