class_name BuildingNode
extends Node2D
## Cursing Gnomes — building visual: real art where the HTML has it.
##
## The HTML build's TEX_SPRITE_SRC set ships true building art (bld_house,
## bld_townhall, bld_hall, bld_tower, bld_barracks, bld_castle, bld_stable,
## bld_civic, bld_flesh_farm, per-faction bld_guild_hall_*, gatehouse,
## wall_strip, bld_windmill). Types with no source art (sawmill, quarry, mine,
## repair_shop) keep programmer-art silhouettes — the HTML drew those
## procedurally too.
## farm, fishing_dock, mage_spire, fire_station, well, sawmill, quarry, mine,
## clinic, medic_camp, cannon_foundry, tome_library, armory, bathhouse,
## guard_house, war_hut, aa_tower, nuke_silo, and windmill
## got detailed redraws or real-art ports
## 2026-10-04 (graphics-hourly + wake routine) under the standing visual-quality
## rule.
## stockpiles and storage now use the
## bld_shop sprite art (2026-10-04, ported from fix79's BLD_SPRITE_FOR).
## bridge segments get the STILTWOOD76 drawBridgeDeck procedural port and
## air_defense takes the aa_tower sprite (2026-10-06) — with those, no
## placed building type falls back to the generic box+roof arm anymore.
## Blueprints draw the art (or silhouette) translucent with a progress ring.


var building_id := -1
var btype := ""
var faction := ""

## Live link back to the sim record for construction state. Set by World.
var record: Dictionary = {}

var _sprite: Sprite2D = null
## 2026-10-06: procedural normal maps (CanvasTexture wraps) so the
## PointLight2D rig shades sprites directionally. Preloaded (not
## class_name-resolved) for headless single-script runs.
const SpriteNormalsScript := preload("res://scripts/world/sprite_normals.gd")
## 2026-10-06: cel-shaded 3D wall renderer (preloaded like SpriteNormalsScript
## for headless single-script runs).
const WallMesh := preload("res://scripts/world/wall_mesh3d.gd")
## Quantized wall damage band (WallMesh3D.damage_band); queue_redraw() when it
## changes so cracks/chips appear as the wall takes damage.
var _wall_dmg_band := -1
var _was_complete := true
var _shadow_key: int = 0  # quantized shadow state; queue_redraw() on change
var _glow_key: int = 0  # quantized night-glow state; queue_redraw() on change

## Windmill blades (graphics-hourly 2026-10-04): the programmer-art windmill
## drew four static blades; real windmills turn. One gentle revolution per
## 6 s, quantized to 48 redraw steps per turn so only windmill nodes ever
## redraw for this (no per-frame cost on other buildings).
## 2026-10-04 wake routine: windmill got its real sprite art (bld_windmill,
## ported from fix79), so this now only runs on the missing-art fallback
## path (sprite == null) — HTML parity: the HTML draws the sprite statically.
const WINDMILL_TURN := TAU / 6.0
const WINDMILL_STEPS := 48
var _blade_angle := 0.0
var _blade_step := -1

## Faction banners (graphics-hourly 2026-10-05): the faction's seat of power
## flies a waving pennant in the faction color, so ownership reads from the
## air and factions feel alive (AI visual feedback). Banner set = the generic
## halls plus each faction's war unique (HTML RACES warBuilding;
## SimAIDirector.WAR_BUILDING).
const BANNER_BTYPES := ["town_hall", "hall", "knights_castle", "war_hut",
	"tome_library", "mage_spire", "necropolis"]
## Launch-readiness graphics pass 2026-10-05: the drawn programmer-art arms
## below were ported from fix79's drawBuilding with the HTML's centered
## coordinate frame (designed ground sits ~+6..+34 below the node origin),
## but the node origin IS the ground point (sprite path: feet at origin;
## blob shadow at origin; y-sort at origin). This maps each drawn type to
## its designed ground Y so _draw() re-anchors the arm onto the ground:
## the shadow lands under the footprint, y-sort matches the sprite path,
## and nothing sits sunk or floating. Quarry is negative: its open-pit rim
## sits at -12 with the pit floor below ground. Garden/flat plots and the
## already-grounded trade_outpost are 0.
const DRAWN_GROUND_Y := {
	"farm": 23.0, "monastery": 24.0, "fishing_dock": 8.0,
	"sawmill": 16.0, "quarry": -12.0, "mine": 16.0, "pier": 24.0,
	"garden": 0.0, "guard_house": 26.0, "shop": 26.0, "windmill": 18.0,
	"clinic": 27.0, "aa_tower": 32.0, "well": 6.0, "mage_spire": 16.0,
	"flesh_farm": 12.0, "fire_station": 23.0, "bathhouse": 28.0,
	"hotel": 28.0, "inn": 28.0, "war_hut": 30.0, "nuke_silo": 34.0,
	"medic_camp": 24.0, "cannon_foundry": 31.0, "tome_library": 29.0,
	"armory": 27.0, "weaponsmith": 27.0, "shooting_range": 14.0,
	"vehicle_depot": 28.0, "seedshop": 26.0, "trade_outpost": 0.0,
	# Launch-readiness 2026-10-06: perk eateries + repair shop share the
	# shop body, so they ground like the shop (26.0).
	"greasy_spoon": 26.0, "salad_bar": 26.0, "ogre_sausage_shop": 26.0,
	"meat_tornado": 26.0, "moonberry_lounge": 26.0, "dewdrop_diner": 26.0,
	"bastard_drivethru": 26.0, "fungus_hut": 26.0, "crypt_kitchen": 26.0,
	"grave_snacks": 26.0, "repair_shop": 26.0,
	# Building-art fix 2026-10-06: the bridge deck is drawn HTML-verbatim
	# centered on the segment position (stilts hang below into the water),
	# so the arm needs no re-anchor — 0.0 like the flat plots.
	"bridge": 0.0, "air_defense": 32.0,
}
## Drawn types that paint their own doorway/entrance, stand over water, or
## are flat ground plots: _draw skips the generic ground doorway rect for
## these so doors don't double-draw (the old centered arms buried the
## generic doorway underground, hiding the clash).
const SELF_DOOR_BTYPES := ["quarry", "mine", "fishing_dock", "pier",
	"garden", "shooting_range", "vehicle_depot", "monastery",
	"guard_house", "shop", "seedshop", "clinic", "bathhouse", "hotel",
	"inn", "tome_library", "weaponsmith", "war_hut", "cannon_foundry",
	"armory", "greasy_spoon", "salad_bar", "ogre_sausage_shop",
	"meat_tornado", "moonberry_lounge", "dewdrop_diner", "bastard_drivethru",
	"fungus_hut", "crypt_kitchen", "grave_snacks", "repair_shop",
	# Building-art fix 2026-10-06: a bridge deck is walked on — no doorway.
	"bridge"]
## Drawn types that are not box buildings (open pit, shaft, docks, flat
## plots, range pad): the generic lit-window rects and lit doorway would
## float over terrain/water instead of sitting on a wall face, so at night
## they get the lamplight halo only.
const FLAT_GLOW_BTYPES := ["quarry", "mine", "fishing_dock", "pier",
	"garden", "shooting_range", "farm",
	# Building-art fix 2026-10-06: a wooden deck has no wall face for lit
	# windows — halo only, like the pier.
	"bridge"]
## Banner wave: 0.9 Hz flutter, 8 quantized redraw steps per cycle (~7
## redraws/sec, the windmill precedent). Deterministic phase per building so
## neighboring seats don't wave in sync.
const BANNER_WAVE_HZ := 0.9
const BANNER_WAVE_STEPS := 8
var _banner_step := -1
var _banner_phase := 0.0
## Completion reveal (graphics-hourly 2026-10-08): a finished building popped
## from translucent blueprint to full art with no transition. Now the
## blueprint->complete edge plays a one-shot rise: the building rises out of
## the ground over 0.8 s (ease-out cubic) with an expanding dust ring + six
## seeded dust puffs at the base. Walls are excluded (drag-place chains
## complete dozens at once — too noisy). Pure visual: sim, AI, RNG untouched;
## the node keeps y-sorting on its unchanged ground origin, and the reveal
## owns the sprite alpha ramp for its 0.8 s, then restores exact values.
const REVEAL_LEN := 0.8
const REVEAL_RISE := 0.45  # rise height as a fraction of _size_for(btype)
const REVEAL_STEPS := 10  # quantized redraw steps during the reveal
var _reveal_t := 0.0      # >0 while the completion reveal plays
var _reveal_step := -1
var _reveal_base_y := 0.0  # sprite y captured when the reveal starts
## Eatery vent FX (graphics-hourly 2026-10-06): chimney smoke / steam / spores
## / moon mist rising from the 10 perk eateries and the repair shop. The
## 08:20 run gave them real art but left them static; Jeremy's launch order
## says everything moves smoothly. Quantized 8-step cycle at 6 steps/sec,
## the windmill/banner precedent — redraw only on step change.
const EATERY_FX_STEPS := 8
const EATERY_FX_PER_SEC := 6.0
var _fx_step := -1
## Industrial production FX (graphics-hourly 2026-10-07): the extraction +
## smithing chain (sawmill, quarry, mine, weaponsmith/blacksmith) was fully
## static while workers churned around it — Jeremy's standing "everything
## smoothly animated" rule. Complete nodes animate production FX on the same
## quantized 8-steps-at-6/sec cadence as the eatery vents. Blueprints stay
## static (a half-built mill produces nothing).
const INDUSTRIAL_FX_BTYPES := ["sawmill", "quarry", "mine", "weaponsmith",
	"blacksmith"]
## Chimney smoke for homes (graphics-hourly 2026-10-07, Jeremy's standing
## "everything smoothly animated" rule): houses are the most numerous
## buildings in the game and every single one stood perfectly still — now
## complete houses breathe smoke from their chimneys on the shared
## quantized FX cadence. Blueprints stay static (an unfinished house has
## no hearth fire). Undead houses exhale the same sickly green as the
## wisps baked into their sprite art.
const HOUSE_FX_BTYPES := ["house", "farmhouse"]
## Sprite-file sizes the chimney anchors below are measured in.
const HOUSE_FX_TEX := {
	"house": Vector2(480.0, 480.0),     # bld_house.png / bld_house_undead.png
	"farmhouse": Vector2(164.0, 151.0), # bld_farmhouse.png
}
## Chimney mouths in art pixels, eyeballed off the sprites (2026-10-07):
## living house (315,128), undead house (95,60), farmhouse (25,30).
const HOUSE_FX_CHIMNEY := {
	"house": Vector2(315.0, 128.0),
	"house_undead": Vector2(95.0, 60.0),
	"farmhouse": Vector2(25.0, 30.0),
}
const HOUSE_SMOKE_TINT := Color(0.56, 0.55, 0.57)
const HOUSE_SMOKE_TINT_UNDEAD := Color(0.45, 0.75, 0.40)
## Test hook: which tint _house_fx last used ("living"/"undead"); "" before
## the first draw.
var _last_house_smoke_tint := ""
## Tavern kitchen FX (graphics-hourly 2026-10-08, Jeremy's standing
## "everything smoothly animated" rule): the sprite-path taverns were the
## last still kitchens — the drawn perk eateries got vent FX on 2026-10-06
## and houses got chimney smoke on 2026-10-07, but the inn/tavern sprites
## every town actually builds never breathed. Both bake a chimney
## (bld_inn.png for living races, bld_tavern_undead.png for undead
## inn/hotel), so kitchens breathe steam/smoke from the chimney mouth on
## the shared quantized FX cadence. Blueprints stay static (an unbuilt
## kitchen isn't cooking). Undead taverns exhale the same sickly green as
## the wisps baked into their sprite art, drifting left with them.
const TAVERN_FX_BTYPES := ["inn", "hotel"]
## Sprite-file sizes the chimney anchors below are measured in (both files
## are 453x480).
const TAVERN_FX_TEX := {
	"inn": Vector2(453.0, 480.0),           # bld_inn.png (living races)
	"tavern_undead": Vector2(453.0, 480.0), # bld_tavern_undead.png (undead)
}
## Chimney mouths in art pixels, eyeballed off the sprites (2026-10-08):
## living inn (140,12) — the stone stack on the left roof slope;
## undead tavern (140,62) — the vent stack where the baked green wisps rise.
const TAVERN_FX_CHIMNEY := {
	"inn": Vector2(140.0, 12.0),
	"tavern_undead": Vector2(140.0, 62.0),
}
const TAVERN_STEAM_TINT := Color(0.93, 0.90, 0.85)
## Test hook: which art key _tavern_fx last used ("inn"/"tavern_undead");
## "" before the first draw or when the btype has no tavern chimney.
var _last_tavern_fx_tint := ""
## Restaurant kitchen FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the C61 per-race faction eateries
## (taco/turkey/acorn/cheese per race, the soul cafe for undead and as its
## own btype) are prominent commercial buildings and stood perfectly
## still — every other eatery breathes through the EATERY_FX vent idiom or
## the tavern chimney, but these draw real sprite art (eat_*.png) with no
## FX family covering them. Now each race's kitchen exhales steam from its
## art-measured chimney/vent mouth on the shared quantized FX cadence,
## and the soul cafe breathes green soul wisps off the cup. Blueprints
## stay static (an unbuilt kitchen isn't cooking).
const RESTAURANT_FX_BTYPES := ["restaurant", "soul_cafe"]
## Sprite-file sizes the vent anchors below are measured in.
const RESTAURANT_FX_TEX := {
	"taco": Vector2(1531.0, 1531.0),      # eat_taco_shop.png (gnomes)
	"turkey": Vector2(1471.0, 1484.0),    # eat_turkey_shop.png (ogres)
	"acorn": Vector2(1338.0, 1121.0),     # eat_acorn_shop.png (elves)
	"cheese": Vector2(1553.0, 1274.0),    # eat_cheese_shop.png (humans)
	"soul_cafe": Vector2(1024.0, 512.0),  # eat_soul_cafe.png (undead/all)
}
## Kitchen vent / chimney mouths in art pixels, measured off the sprites
## (2026-10-09): taco (795,358) — the metal stovepipe behind the statue
## stilts; turkey (410,395) — the stone stack's dark mouth on the left
## roof slope; acorn (400,205) — the stone chimney mouth; cheese (468,273)
## — the stone chimney mouth; soul_cafe (508,150) — the cup's mouth where
## the baked green wisps rise.
const RESTAURANT_FX_VENT := {
	"taco": Vector2(795.0, 358.0),
	"turkey": Vector2(410.0, 395.0),
	"acorn": Vector2(400.0, 205.0),
	"cheese": Vector2(468.0, 273.0),
	"soul_cafe": Vector2(508.0, 150.0),
}
const RESTAURANT_STEAM_TINT := Color(0.93, 0.90, 0.85)
## Test hook: art key _restaurant_fx last ran for; "" before the first draw
## or when the btype has no restaurant vent.
var _last_restaurant_fx := ""


## Pure: which restaurant art key exhales for a btype/faction, or "" when
## the building has no kitchen vent.
static func restaurant_fx_art_key(btype: String, p_faction: String) -> String:
	if btype == "soul_cafe":
		return "soul_cafe"
	if btype == "restaurant":
		match p_faction:
			"ogres":
				return "turkey"
			"elves":
				return "acorn"
			"humans":
				return "cheese"
			"undead":
				return "soul_cafe"
			_:
				return "taco"
	return ""


## Restaurant art-pixel anchor -> node-space offset, tracking the sprite's
## real render scale (the _tavern_fx_anchor precedent).
func _restaurant_fx_anchor(key: String) -> Vector2:
	var tsize: Vector2 = RESTAURANT_FX_TEX.get(key, RESTAURANT_FX_TEX["taco"])
	var ap: Vector2 = RESTAURANT_FX_VENT.get(key, RESTAURANT_FX_VENT["taco"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Kitchen steam / soul wisps for a complete sprite-path faction eatery.
## Three staggered puffs rise from the art-measured vent mouth, spreading
## and fading over one FX cycle — deterministic from _fx_step (no per-frame
## RNG, no allocation), drawn with plain circles so it stays cheap on
## iPhone. Living kitchens exhale warm steam (the tavern idiom); the soul
## cafe breathes the undead green of the wisps baked into its sprite art,
## drifting left with them. Called from the sprite path of _draw —
## ground-anchored to the art through the real render scale, never
## touching world position, so nothing floats.
func _restaurant_fx() -> void:
	var key := restaurant_fx_art_key(btype, faction)
	if key == "":
		return
	_last_restaurant_fx = key
	var vent := _restaurant_fx_anchor(key)
	var sc := _sprite_sc
	var soul := key == "soul_cafe"
	var tint: Color = CIVIC_FX_TINT["undead"] if soul \
		else RESTAURANT_STEAM_TINT
	var drift: float = -40.0 if soul else 0.0
	var step := _fx_local_step()
	for i in range(3):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 5.0 + float(i) * 2.4) \
			* (8.0 + life * 26.0)
		var pos := vent + Vector2((wob + drift * life) * sc,
			-life * 150.0 * sc)
		var r: float = (11.0 + life * 30.0) * sc
		var a: float = 0.34 * (1.0 - life)
		draw_circle(pos, r, Color(tint.r, tint.g, tint.b, a))
## Lumber-camp work FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the lumber camp is the wood
## loop's anchor (AI builds one per town, chopped-tree pickups haul here)
## and stood perfectly still. Now sawdust drifts off the crosscut-saw
## teeth on the sawbuck and a wood chip kicks off the chopping stump on
## the shared quantized FX cadence. Blueprints stay static (an unbuilt
## camp cuts no wood).
const LUMBER_FX_BTYPES := ["lumber_camp"]
## Sprite-file size the anchors below are measured in.
const LUMBER_FX_TEX := Vector2(720.0, 480.0)  # bld_lumber_camp.png
## Sawdust / chip origins in art pixels, measured off the sprite
## (2026-10-09): saw teeth (245,254) — the crosscut saw on the sawbuck;
## stump (133,353) — the axe-stuck chopping stump.
const LUMBER_FX_SAW := Vector2(245.0, 254.0)
const LUMBER_FX_STUMP := Vector2(133.0, 353.0)
const LUMBER_SAWDUST_TINT := Color(0.87, 0.76, 0.55)
## Test hook: origin _lumber_fx last ran for ("saw"/"stump"); "" before the
## first draw or when the btype has no lumber anchors.
var _last_lumber_fx := ""


## Lumber art-pixel anchor -> node-space offset, tracking the sprite's
## real render scale (the _restaurant_fx_anchor precedent).
func _lumber_fx_anchor(ap: Vector2) -> Vector2:
	var tsize: Vector2 = LUMBER_FX_TEX
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Sawdust off the sawbuck + chips off the stump for a complete lumber
## camp. Three sawdust motes drift down off the saw teeth, wobbling and
## fading over one FX cycle, with one wood chip kicking off the stump on
## a little arc each cycle — deterministic from _fx_step (no per-frame
## RNG, no allocation), drawn with plain circles so it stays cheap on
## iPhone. Ground-anchored to the art through the real render scale,
## never touching world position, so nothing floats.
func _lumber_fx() -> void:
	if not (btype in LUMBER_FX_BTYPES):
		return
	_last_lumber_fx = "saw"
	var saw := _lumber_fx_anchor(LUMBER_FX_SAW)
	var stump := _lumber_fx_anchor(LUMBER_FX_STUMP)
	var sc := _sprite_sc
	var tint := LUMBER_SAWDUST_TINT
	var step := _fx_local_step()
	for i in range(3):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 5.0 + float(i) * 2.4) \
			* (6.0 + life * 18.0)
		var pos := saw + Vector2((-30.0 * life + wob) * sc,
			life * 60.0 * sc)
		var r: float = (4.0 + life * 7.0) * sc
		var a: float = 0.5 * (1.0 - life)
		draw_circle(pos, r, Color(tint.r, tint.g, tint.b, a))
	var chip_life: float = float(step) / float(EATERY_FX_STEPS)
	var cpos := stump + Vector2((20.0 + 40.0 * chip_life) * sc,
		(-10.0 - 70.0 * chip_life + 90.0 * chip_life * chip_life) * sc)
	var ca: float = 0.55 * (1.0 - chip_life)
	_last_lumber_fx = "stump"
	draw_circle(cpos, 5.0 * sc, Color(tint.r, tint.g, tint.b, ca))
## Stockpile depot FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): storage is the AI's #2
## most-built building and every depot stood perfectly still. Complete
## depots now breathe on the shared quantized FX cadence: dust kicks up
## at the loading door as crates shift, the hearth chimney smokes, and
## the door lantern breathes warm light. Blueprints stay dark (an unbuilt
## depot moves no goods). Deliberately not the shop FX's window-glow +
## coin-glints - a depot reads as working, not open for business.
const STOCKPILE_FX_BTYPES := ["storage", "stock_gold", "stock_wood",
	"stock_food", "stock_oil", "stock_seeds"]
## Sprite-file sizes the anchors below are measured in: the four living
## general-store sprites are 480x320; bld_shop.png / bld_shop_undead.png
## (the stock_* art) are 480x388.
const STOCKPILE_FX_TEX := {
	"store_human": Vector2(480.0, 320.0),
	"store_gnome": Vector2(480.0, 320.0),
	"store_ogre": Vector2(480.0, 320.0),
	"store_elf": Vector2(480.0, 320.0),
	"store_undead": Vector2(480.0, 388.0),
	"shop": Vector2(480.0, 388.0),
	"shop_undead": Vector2(480.0, 388.0),
}
## Loading-door base centers in art pixels, measured off the real sprites
## (2026-10-09): dust kicks up here as crates shift.
const STOCKPILE_FX_DOOR := {
	"store_human": Vector2(242.0, 308.0),
	"store_gnome": Vector2(240.0, 300.0),
	"store_ogre": Vector2(240.0, 300.0),
	"store_elf": Vector2(240.0, 310.0),
	"store_undead": Vector2(300.0, 340.0),
	"shop": Vector2(190.0, 285.0),
	"shop_undead": Vector2(300.0, 340.0),
}
## Chimney smoke vents in art pixels - only the human/gnome stores and the
## shop sprite bake a chimney (pixel-verified 2026-10-09); other keys get
## no smoke.
const STOCKPILE_FX_VENT := {
	"store_human": Vector2(125.0, 14.0),
	"store_gnome": Vector2(120.0, 26.0),
	"shop": Vector2(98.0, 24.0),
}
## Door-lantern anchors in art pixels - only the human and ogre stores
## hang a lit lantern by the door (pixel-verified 2026-10-09).
const STOCKPILE_FX_LANTERN := {
	"store_human": Vector2(300.0, 190.0),
	"store_ogre": Vector2(64.0, 198.0),
}
## Dust tint: warm kicked-up dust for the living races, cold ash for the
## undead depot.
const STOCKPILE_DUST_TINT := Color(0.72, 0.68, 0.60)
const STOCKPILE_ASH_TINT := Color(0.55, 0.60, 0.55)
const STOCKPILE_SMOKE_TINT := Color(0.62, 0.62, 0.64)
const STOCKPILE_LANTERN_TINT := Color(1.0, 0.80, 0.50)
## Test hook: art key _stockpile_fx last ran for; "" before the first draw
## or when the btype has no depot art.
var _last_stockpile_fx := ""


## Pure: which depot art key breathes for a btype/faction, or "" when the
## building is not a stockpile. Storage takes the per-faction general
## store art (art.gd BUILDING_ART_FACTION); the five stock_* types take
## bld_shop.png (bld_shop_undead.png for the undead).
static func stockpile_fx_art_key(btype: String, p_faction: String) -> String:
	if btype == "storage":
		match p_faction:
			"gnomes":
				return "store_gnome"
			"ogres":
				return "store_ogre"
			"elves":
				return "store_elf"
			"undead":
				return "store_undead"
			_:
				return "store_human"
	if btype in ["stock_gold", "stock_wood", "stock_food", "stock_oil",
			"stock_seeds"]:
		return "shop_undead" if p_faction == "undead" else "shop"
	return ""


## Stockpile art-pixel anchor -> node-space offset, tracking the sprite's
## real render scale (the _shop_fx_anchor precedent).
func _stockpile_fx_anchor(ap: Vector2, key: String) -> Vector2:
	var tsize: Vector2 = STOCKPILE_FX_TEX.get(key,
		STOCKPILE_FX_TEX["store_human"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Depot bustle for a complete sprite-path stockpile: dust kicks up at the
## loading door as crates shift, the hearth chimney smokes, and the door
## lantern breathes. Deterministic from _fx_step (no per-frame RNG, no
## allocation), plain circles so it stays cheap on iPhone. Ground-anchored
## to the art through the real render scale, never touching world
## position, so nothing floats. Called from the sprite path of _draw;
## NightGlow.current() deepens the lantern halo after dark. Blueprints
## returned above - an unbuilt depot moves no goods.
func _stockpile_fx() -> void:
	var key := stockpile_fx_art_key(btype, faction)
	if key == "":
		return
	_last_stockpile_fx = key
	var sc := _sprite_sc
	var step := _fx_local_step()
	var night := NightGlow.current()
	var undead := key == "store_undead" or key == "shop_undead"
	var dust_tint: Color = STOCKPILE_ASH_TINT if undead \
		else STOCKPILE_DUST_TINT
	# Crate dust: two phased puffs at the loading-door base.
	var door := _stockpile_fx_anchor(STOCKPILE_FX_DOOR[key], key)
	for i in range(2):
		var life: float = float((step + i * 4 + _fx_phase) \
			% EATERY_FX_STEPS) / float(EATERY_FX_STEPS)
		var wob: float = sin(life * 6.0 + float(i) * 2.4) * 10.0
		var pos := door + Vector2(wob * sc, -life * 26.0 * sc)
		var r: float = (5.0 + life * 9.0) * sc
		var a: float = 0.42 * (1.0 - life)
		draw_circle(pos, r, Color(dust_tint.r, dust_tint.g, dust_tint.b, a))
	# Hearth smoke: two phased wisps off the chimney (keys that bake one).
	if STOCKPILE_FX_VENT.has(key):
		var vent := _stockpile_fx_anchor(STOCKPILE_FX_VENT[key], key)
		for i in range(2):
			var slife: float = float((step + i * 4) % EATERY_FX_STEPS) \
				/ float(EATERY_FX_STEPS)
			var swob: float = sin(slife * 5.0 + float(i) * 2.4) \
				* (6.0 + slife * 20.0)
			var spos := vent + Vector2(swob * sc, -slife * 90.0 * sc)
			var sr: float = (4.0 + slife * 8.0) * sc
			var sa: float = 0.30 * (1.0 - slife)
			var st := STOCKPILE_SMOKE_TINT
			draw_circle(spos, sr, Color(st.r, st.g, st.b, sa))
	# Lantern breath: warm halo pulsing on the door lantern (keys that
	# hang one); deepens after dark like the shop panes.
	if STOCKPILE_FX_LANTERN.has(key):
		var lamp := _stockpile_fx_anchor(STOCKPILE_FX_LANTERN[key], key)
		var flick := shop_flicker_for(step, float(_fx_phase) * 0.9)
		var lt := STOCKPILE_LANTERN_TINT
		var halo_a := (0.14 + 0.18 * night) * flick
		draw_circle(lamp, 22.0 * sc * flick,
			Color(lt.r, lt.g, lt.b, halo_a))
		draw_circle(lamp, 9.0 * sc * flick,
			Color(lt.r, lt.g, lt.b, 0.35 * flick))
## Fishing-dock water FX (rapid-iteration 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the dock is the fishing loop's
## anchor (the Stinky Gizmundo swims here) and stood perfectly still on
## the water. Complete docks now breathe on the shared quantized FX
## cadence: foam flecks lap the pier's waterline, the moored boat gets
## alternating hull water-laps, and a lantern on the pennant pole breathes
## warm light that deepens after dark (NightGlow.current()). Blueprints
## stay dark (an unbuilt dock catches no fish). Deterministic from
## _fx_step (no per-frame RNG, no allocation), plain circles/lines so it
## stays cheap on iPhone. Called from the drawn arm of _draw (the dock is
## programmer-art — the HTML drew it procedurally too), so the anchors
## below are node-local px matching _fishing_dock, the monastery-FX
## precedent.
const FISHING_FX_BTYPES := ["fishing_dock"]
## Foam flecks along the waterline (the baked foam edge runs y=8, x -26..42).
const FISHING_FX_FLECKS := [Vector2(-14.0, 8.5), Vector2(2.0, 9.0),
	Vector2(20.0, 8.5)]
## Hull water-laps just outside the moored boat (hull spans x 24..38,
## top edge y=10) - reads as the boat nudging the water without its art
## ever moving (freeze-position law).
const FISHING_FX_LAPS := [Vector2(23.0, 10.5), Vector2(39.0, 10.5)]
## Lantern on the pennant pole (pole x=-18, deck top y=-6, pennant ends
## y=-12) - hangs below the pennant, above the deck.
const FISHING_FX_LANTERN := Vector2(-18.0, -9.0)
const FISHING_FX_FOAM_TINT := Color(0.80, 0.88, 0.95)
const FISHING_FX_LANTERN_TINT := Color(1.0, 0.80, 0.50)
## Test hook: "dock" once _fishing_dock_fx has run; "" before the first
## draw or when the btype has no dock anchors.
var _last_fishing_dock_fx := ""


## Foam flecks + hull water-laps + pole lantern for a complete drawn-arm
## fishing dock. Ground-anchored to the node-local arm (never touching
## world position, so nothing floats); the boat and pennant art are never
## redrawn, only lapped at their edges.
func _fishing_dock_fx() -> void:
	if not (btype in FISHING_FX_BTYPES):
		return
	_last_fishing_dock_fx = "dock"
	var step := _fx_local_step()
	var night := NightGlow.current()
	var foam := FISHING_FX_FOAM_TINT
	# Foam flecks lapping the waterline: three staggered dashes along the
	# baked foam edge that brighten and wash out over one FX cycle.
	for i in range(FISHING_FX_FLECKS.size()):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var f: Vector2 = FISHING_FX_FLECKS[i]
		var wob: float = sin(life * 5.0 + float(i) * 2.4) * 3.0
		var fa: float = 0.55 * (1.0 - life)
		draw_line(f + Vector2(-3.0 + wob, 0.0),
			f + Vector2(3.0 + wob, 0.0),
			Color(foam.r, foam.g, foam.b, fa), 1.6)
	# Hull water-laps: alternating glints just outside the moored boat's
	# ends - the boat rides the water while its art never moves.
	for i in range(FISHING_FX_LAPS.size()):
		var hflick := monastery_flicker_for(step, float(i) * 2.1)
		var h: Vector2 = FISHING_FX_LAPS[i]
		draw_line(h + Vector2(-2.5, 0.0), h + Vector2(2.5, 0.0),
			Color(foam.r, foam.g, foam.b, 0.30 + 0.35 * hflick), 1.4)
	# Dock lantern: iron cap where it meets the pennant pole, warm glass
	# dot, halo breathing around it - deeper after dark like the shop panes.
	var lamp := FISHING_FX_LANTERN
	var iron := Color(0.16, 0.14, 0.15)
	draw_rect(Rect2(lamp.x - 2.5, lamp.y - 5.5, 5.0, 2.5), iron)
	var lflick := monastery_flicker_for(step, 4.2)
	var lt := FISHING_FX_LANTERN_TINT
	draw_circle(lamp, 11.0 * lflick,
		Color(lt.r, lt.g, lt.b, (0.08 + 0.20 * night) * lflick))
	draw_circle(lamp, 3.0,
		Color(lt.r, lt.g, lt.b, (0.30 + 0.60 * night) * lflick))
## Monastery candle-glow FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): monasteries are the game's #1
## strategic target (assault campaigns, guards, captures) and stood
## perfectly still — now the arched windows breathe warm candlelight and a
## brazier burns by the doorway on the shared quantized FX cadence.
## Candles burn day and night in the NASTY MONASTERY; NightGlow.current()
## deepens the halos after dark. Blueprints stay dark (an unfinished chapel
## holds no services).
const MONASTERY_FX_BTYPES := ["monastery"]
## Arched-window glass centers in drawn node-local px, matching
## _monastery's baked `for wx in [-16.0, -4.0]` (glass rect (wx,0,7,14) +
## arch circle (wx+3.5,0)).
const MONASTERY_WINDOWS := [Vector2(-12.5, 7.0), Vector2(-0.5, 7.0)]
## Brazier anchor: iron bowl on a tripod flanking the arched doorway,
## feet planted on the chapel ground line (y = 24 in drawn space).
## x = 9.0 tucks it between the doorway (ends x = 6) and the bell tower
## (starts x = 14) — clear of the baked window glass.
const MONASTERY_BRAZIER := Vector2(9.0, 24.0)
## Test hook: btype _monastery_fx last ran for; "" before the first draw.
var _last_monastery_fx := ""
## Medic-tent lantern FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the medic tent (bld_tent_medic.png)
## is the field hospital the AI raises twice per town plan — and its
## entrance lantern burned static while doctors worked inside. Now the
## lantern breathes warm light over the tent opening on the shared
## quantized FX cadence, phased per tent so a row of hospitals doesn't
## pulse in lockstep. NightGlow.current() deepens the halo after dark.
## Blueprints stay dark (an unbuilt tent treats no one).
const MEDIC_FX_BTYPES := ["medic_camp"]
## Sprite-file size the lantern anchor below is measured in.
const MEDIC_FX_TEX := Vector2(429.0, 309.0)
## Entrance-lantern glow centroid in art pixels, measured off the real
## sprite (2026-10-09): the warm baked glow inside the tent opening on
## the tent's right flank (cluster x 371-413, y 209-230).
const MEDIC_FX_LANTERN := Vector2(398.0, 220.0)
## Warm lantern tint (the shop-lantern precedent).
const MEDIC_LANTERN_TINT := Color(1.0, 0.80, 0.45)
## Test hook: btype _medic_fx last ran for; "" before the first draw.
var _last_medic_fx := ""
## Medic-tent art-pixel anchor -> node-space offset, tracking the sprite's
## real render scale (the _shop_art_to_node precedent).
func _medic_fx_anchor(ap: Vector2) -> Vector2:
	var sc := _sprite_sc
	return Vector2(
		(ap.x - MEDIC_FX_TEX.x * 0.5) * sc,
		(ap.y - MEDIC_FX_TEX.y * 0.5) * sc - 0.48 * MEDIC_FX_TEX.y * sc)
## Warm lantern breath over the tent entrance. Called from the sprite path
## of _draw — ground-anchored to the art through the real render scale, so
## nothing floats. The baked glow pixels are never touched (no seam risk);
## the halo breathes over them. Deterministic from _fx_step: no per-frame
## RNG, no allocation, plain circles (iPhone-cheap).
func _medic_fx() -> void:
	_last_medic_fx = btype
	var sc := _sprite_sc
	var step := _fx_local_step()
	var night := NightGlow.current()
	var lamp := _medic_fx_anchor(MEDIC_FX_LANTERN)
	var flick := monastery_flicker_for(step, float(_fx_phase) * 0.9)
	var lt := MEDIC_LANTERN_TINT
	var halo_a := (0.14 + 0.18 * night) * flick
	draw_circle(lamp, 22.0 * sc * flick,
		Color(lt.r, lt.g, lt.b, halo_a))
	draw_circle(lamp, 9.0 * sc * flick,
		Color(lt.r, lt.g, lt.b, 0.35 * flick))
## Mage spire arcane FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the spire crowns stood perfectly
## still — now each race's crown crystal breathes arcane light on the shared
## quantized FX cadence, and spark motes rise from it. Anchors are measured
## off the real sprite art (crystal centers in art px): human (122,41) blue
## diamond, elf (124,38) pale orb, gnome (123,41) teal orb, ogre (123,42)
## red crystal. Undead spires fall back to bld_tower.png (no crystal), so
## they exhale faint sickly-green wisps from the roof peak instead — the
## same undead wisps baked into their other art. Blueprints stay dark (an
## unfinished spire holds no charge).
const MAGESPIRE_FX_BTYPES := ["mage_spire"]
## Sprite-file sizes the crystal anchors below are measured in (all files
## are 246x480).
const MAGESPIRE_FX_TEX := {
	"elves": Vector2(246.0, 480.0),   # bld_mage_spire_elf.png
	"gnomes": Vector2(246.0, 480.0),  # bld_mage_spire_gnome.png
	"humans": Vector2(246.0, 480.0),  # bld_mage_spire_human.png
	"ogres": Vector2(246.0, 480.0),   # bld_mage_spire_ogre.png
	"tower": Vector2(246.0, 480.0),   # bld_tower.png (undead fallback)
}
## Crown-crystal centers in art pixels, measured off the sprites
## (2026-10-09); tower key is the undead roof peak.
const MAGESPIRE_FX_CRYSTAL := {
	"elves": Vector2(124.0, 38.0),
	"gnomes": Vector2(123.0, 41.0),
	"humans": Vector2(122.0, 41.0),
	"ogres": Vector2(123.0, 42.0),
	"tower": Vector2(123.0, 24.0),
}
## Per-art-key arcane tint (halo + motes).
const MAGESPIRE_FX_TINT := {
	"elves": Color(0.75, 0.85, 1.0),   # pale moon-blue
	"gnomes": Color(0.45, 0.95, 0.85), # teal
	"humans": Color(0.45, 0.65, 1.0),  # arcane blue
	"ogres": Color(1.0, 0.35, 0.25),   # ember red
	"tower": Color(0.45, 0.85, 0.45),  # sickly undead green
}
## Test hook: art key _magespire_fx last ran for; "" before the first draw.
var _last_magespire_fx := ""
## Military war-machine FX (massive-dev 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the last fully-static building
## family — barracks, war huts, cannon foundries, armories, castles, guard
## houses, watch/AA towers, the nuke silo, the anti-nuke dish, and the
## archery range — stood perfectly still while armies drilled around them.
## Now each breathes on the shared quantized FX cadence: chimney smoke,
## candlelit windows, torch flames, warning beacons, radar pings.
## Blueprints stay dark (an unfinished fort holds no garrison).
const MILITARY_FX_BTYPES := ["barracks", "war_hut", "cannon_foundry",
	"armory", "vehicle_depot", "knights_castle", "guard_house",
	"guard_tower", "aa_tower", "air_defense", "nuke_silo", "anti_nuke",
	"shooting_range"]
## Sprite-file sizes the anchors below are measured in, eyeballed off the
## real art (2026-10-09). "silo" shares the tower art (bld_tower.png) via
## the _military_fx_anchor fallback.
const MILITARY_FX_TEX := {
	"barracks": Vector2(480.0, 317.0),          # bld_barracks.png
	"barracks_undead": Vector2(480.0, 317.0),   # bld_barracks_undead.png
	"castle": Vector2(803.0, 593.0),            # bld_castle.png
	"guard_house_elves": Vector2(480.0, 656.0),
	"guard_house_gnomes": Vector2(480.0, 360.0),
	"guard_house_humans": Vector2(480.0, 654.0),
	"guard_house_ogres": Vector2(480.0, 352.0),
	"tower": Vector2(246.0, 480.0),              # bld_tower.png
	"antinuke": Vector2(256.0, 256.0),          # bld_anti_nuke.png
	"range": Vector2(480.0, 321.0),             # bld_archery_range.png
}
## Smoke vents (chimney mouths) in art pixels: the barracks' stone stack
## (living) and the undead fortress' roof stack (wisps baked green).
const MILITARY_FX_VENT := {
	"barracks": Vector2(62.0, 26.0),
	"barracks_undead": Vector2(215.0, 28.0),
}
## Candlelit windows in art pixels, eyeballed off the sprites.
const MILITARY_FX_WINDOWS := {
	"barracks": [Vector2(58.0, 200.0), Vector2(140.0, 205.0),
		Vector2(285.0, 200.0), Vector2(398.0, 195.0)],
	"barracks_undead": [Vector2(75.0, 175.0), Vector2(135.0, 195.0),
		Vector2(195.0, 205.0), Vector2(340.0, 160.0)],
	"castle": [Vector2(395.0, 195.0), Vector2(395.0, 232.0),
		Vector2(395.0, 268.0), Vector2(60.0, 228.0),
		Vector2(738.0, 222.0)],
	"guard_house_humans": [Vector2(95.0, 165.0), Vector2(215.0, 250.0),
		Vector2(268.0, 332.0)],
	"guard_house_elves": [Vector2(240.0, 330.0)],
	"guard_house_gnomes": [Vector2(95.0, 175.0), Vector2(400.0, 55.0)],
	"guard_house_ogres": [Vector2(95.0, 195.0), Vector2(295.0, 95.0)],
	"tower": [Vector2(85.0, 175.0)],
}
## Torch / brazier / lantern flames in art pixels: castle gate torches,
## the tower's watch-platform signal brazier, guard-house lanterns, and
## the undead barracks' baked purple braziers (drawn purple).
const MILITARY_FX_FLAMES := {
	"barracks_undead": [Vector2(195.0, 190.0), Vector2(320.0, 160.0)],
	"castle": [Vector2(345.0, 428.0), Vector2(478.0, 428.0)],
	"guard_house_humans": [Vector2(150.0, 340.0)],
	"guard_house_elves": [Vector2(240.0, 165.0), Vector2(400.0, 600.0)],
	"guard_house_gnomes": [Vector2(185.0, 140.0), Vector2(295.0, 140.0)],
	"guard_house_ogres": [Vector2(445.0, 165.0)],
	"tower": [Vector2(123.0, 122.0)],
}
## Warning beacons in art pixels (hard red strobe, not a flame).
const MILITARY_FX_BEACONS := {
	"silo": [Vector2(123.0, 108.0)],
	"antinuke": [Vector2(75.0, 92.0)],
}
## Radar-dish center in art pixels (ping-ring origin).
const MILITARY_FX_DISH := Vector2(75.0, 128.0)
## Archery-range target centers in art pixels (dust motes drift over them).
const MILITARY_FX_TARGETS := [Vector2(195.0, 200.0),
	Vector2(268.0, 200.0), Vector2(345.0, 205.0)]
## Test hook: art key _military_fx last ran for; "" before the first draw.
var _last_military_fx := ""
## Shop storefront FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): shops were the last fully-static
## commercial family — the storefronts every town builds stood perfectly
## still while merchants worked inside. Now complete shops breathe
## lamplight on the shared quantized FX cadence: warm window-glow over
## the storefront panes + winking coin glints for the living races,
## sickly-green window-glow + potion-stall wisps for the undead.
## Blueprints stay dark (an unbuilt shop isn't open for business). Wells
## reuse the bld_shop.png art but are NOT shops — a glowing well would be
## wrong, so the router keeps them dark. Undead hotels use
## bld_tavern_undead and keep their tavern FX.
const SHOP_FX_BTYPES := ["shop", "seedshop", "hotel", "trade_outpost"]
## Sprite-file sizes the window anchors below are measured in (both files
## are 480x388).
const SHOP_FX_TEX := {
	"shop": Vector2(480.0, 388.0),        # bld_shop.png
	"shop_undead": Vector2(480.0, 388.0), # bld_shop_undead.png
}
## Storefront window centers in art pixels, measured off the real sprites
## via pixel scan (2026-10-09): the living shop's two big display windows
## under the striped awning; the undead shop's three green-lit windows.
const SHOP_FX_WINDOWS := {
	"shop": [Vector2(100.0, 232.0), Vector2(295.0, 255.0)],
	"shop_undead": [Vector2(142.0, 152.0), Vector2(279.0, 155.0),
		Vector2(272.0, 172.0)],
}
## Potion-stall wisp origin in art pixels (undead art): the bottle shelf
## at the left of the storefront.
const SHOP_FX_STALL := Vector2(105.0, 265.0)
## Per-art-key glow tint: warm lamplight for the living storefront,
## sickly green matching the windows baked into the undead art.
const SHOP_FX_TINT := {
	"shop": Color(1.0, 0.82, 0.52),
	"shop_undead": Color(0.45, 0.90, 0.45),
}
## Test hook: art key _shop_fx last ran for ("shop_drawn" for the drawn
## living-shop arm); "" before the first draw.
var _last_shop_fx := ""
## Swaying crops (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): farms are among the most numerous
## buildings (the AI's agri plan builds 2+ per town) and every crop row
## stood frozen. Complete farms now ripple their sprouts on the shared
## quantized FX cadence. Blueprints stay static (no crops before the farm
## is built). The undead flesh_farm has its own FX arm
## (FLESH_FX_BTYPES, below).
const FARM_FX_BTYPES := ["farm"]
## Crop sway amplitude in px at the sprout tip; one breeze crosses the
## field per EATERY_FX_STEPS-step cycle (~1.33s at 6/sec).
const FARM_FX_SWAY := 2.0
## Flesh-farm FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the undead farm was the last
## production building with no ambient FX — the hanging racks stood
## frozen while the hut's green lantern never pulsed. Complete
## flesh_farms now breathe on the shared quantized FX cadence: the hut
## window + door lantern pulse sickly-green lamplight (the undead civic
## tint) and three wisps rise off the bone pit, desynced per building.
## Blueprints stay dark (an unbuilt farm holds no harvest). The hanging
## sacks are baked into the sprite — sway would mean redrawing baked
## art, so the motion lives in light and air instead.
const FLESH_FX_BTYPES := ["flesh_farm"]
## Sprite-file size the anchors below are measured in (pixel-scanned +
## eyeball-verified against the real art, 2026-10-09): the green hut
## window glows at ~(415,143), the door lantern at ~(381,148), and the
## three pit-wisp origins sit on the bone-pit floor.
const FLESH_FX_TEX := Vector2(560.0, 280.0)
const FLESH_FX_WINDOW := Vector2(415.0, 143.0)
const FLESH_FX_LANTERN := Vector2(381.0, 148.0)
const FLESH_FX_PIT := [Vector2(180.0, 200.0), Vector2(260.0, 185.0),
	Vector2(340.0, 205.0)]
## Civic seat FX (graphics-hourly 2026-10-09, Jeremy's standing
## "everything smoothly animated" rule): the seats of power were the last
## major building family with no ambient FX — every town_hall, hall,
## courthouse, guild hall and necropolis stood perfectly still (the
## town_hall's waving faction banner was its only motion). Now complete
## civic seats breathe lamplight on the shared quantized FX cadence: warm
## window-glow + entrance braziers for the living races, sickly-green
## window-glow + purple brazier flames for the undead. Blueprints stay
## dark (an unbuilt hall holds no council). The gov_* offices, clinic,
## tome_library and bathhouse share the bld_civic art but are NOT seats —
## a glowing courthouse reads as government; a glowing clinic does not.
const CIVIC_FX_BTYPES := ["town_hall", "townhall", "hall", "courthouse",
	"guild_hall", "necropolis"]
## Sprite-file sizes the anchors below are measured in (pixel-scanned +
## eyeballed off the real art, 2026-10-09).
const CIVIC_FX_TEX := {
	"townhall": Vector2(480.0, 360.0),    # bld_townhall.png
	"hall": Vector2(480.0, 358.0),        # bld_hall.png
	"civic": Vector2(480.0, 346.0),       # bld_civic.png (courthouse)
	"guild_human": Vector2(480.0, 640.0), # bld_guild_hall_human.png
	"guild_ogre": Vector2(480.0, 320.0),  # bld_guild_hall_ogre.png
	"guild_elf": Vector2(480.0, 320.0),   # bld_guild_hall_elf.png
	"guild_gnome": Vector2(480.0, 320.0), # bld_guild_hall_gnome.png
	"guild_undead": Vector2(1182.0, 1896.0), # bld_guild_undead.png
	"necropolis": Vector2(480.0, 358.0),  # bld_necropolis.png
}
## Lit window centers in art pixels (blue/green/amber blob centroids from
## the 2026-10-09 pixel scan, eyeball-verified against the sprites).
const CIVIC_FX_WINDOWS := {
	"townhall": [Vector2(35, 182), Vector2(73, 195), Vector2(35, 128),
		Vector2(298, 217), Vector2(336, 229), Vector2(298, 272)],
	"hall": [Vector2(106, 205), Vector2(166, 205), Vector2(314, 205),
		Vector2(374, 205), Vector2(106, 262), Vector2(374, 262)],
	"civic": [Vector2(66, 206), Vector2(116, 224), Vector2(150, 240),
		Vector2(250, 240), Vector2(367, 205), Vector2(405, 185),
		Vector2(447, 165)],
	"guild_human": [Vector2(132, 256), Vector2(348, 256),
		Vector2(132, 400), Vector2(348, 400)],
	"guild_ogre": [Vector2(118, 215), Vector2(362, 215)],
	"guild_elf": [Vector2(240, 152), Vector2(142, 231),
		Vector2(338, 231)],
	"guild_gnome": [Vector2(110, 205), Vector2(368, 205)],
	"guild_undead": [Vector2(175, 836), Vector2(672, 1078)],
	"necropolis": [Vector2(227, 116), Vector2(279, 115),
		Vector2(213, 195), Vector2(252, 195)],
}
## Entrance brazier / lantern points in art pixels, flanking the baked
## door. The undead seats already burn purple flames in the art — the FX
## breathes over them. The gnome hall bakes two wall lanterns by its round
## door; the courthouse is brazier-less (an office, not a hall).
const CIVIC_FX_BRAZIERS := {
	"townhall": [Vector2(140, 235), Vector2(222, 235)],
	"hall": [Vector2(195, 295), Vector2(285, 295)],
	"civic": [],
	"guild_human": [Vector2(190, 430), Vector2(290, 430)],
	"guild_ogre": [Vector2(190, 250), Vector2(290, 250)],
	"guild_elf": [Vector2(195, 270), Vector2(285, 270)],
	"guild_gnome": [Vector2(175, 150), Vector2(305, 150)],
	"guild_undead": [Vector2(174, 1449), Vector2(587, 1641)],
	"necropolis": [Vector2(146, 249), Vector2(247, 280)],
}
## Window-glow tint per key family: warm lamplight for the living seats,
## sickly green matching the windows baked into the undead art.
const CIVIC_FX_TINT := {
	"living": Color(1.0, 0.81, 0.49),
	"undead": Color(0.45, 0.90, 0.45),
}
## Test hook: art key _civic_fx last ran for; "" before the first draw.
var _last_civic_fx := ""
## Test hook: art key _flesh_fx last ran for; "" before the first draw.
var _last_flesh_fx := ""
## Battle damage FX (graphics-hourly 2026-10-07, Jeremy's standing
## "everything smoothly animated" rule): only walls showed damage (crack
## bands) — every other building stood pristine while siege engines
## pounded it. Now damaged buildings smoke and critical ones burn; the
## sim already calls a 25%-HP captured hall "burning" (combat.gd
## _flip_hall). P6 (Jeremy 2026-10-10): escalating 5-band ladder —
## scuffed -> cracked/crumbling -> smoking -> burning -> rubble — readable
## at a glance on a phone screen. Rubble on destruction already exists
## (RubbleLayer mound + stones + beams); repair walks the ladder back
## down automatically since the band recomputes from live hp every
## _process tick. Complete non-wall buildings only — blueprints never,
## walls keep their crack bands, and the wildfire on_fire state keeps
## its CombatFX roof fire (both can stack).
const DMG_SCUFF_FRAC := 0.85
const DMG_CRACK_FRAC := 0.65
const DMG_SMOKE_FRAC := 0.45
const DMG_BURN_FRAC := 0.30
## Test hook: current damage band (0/1/2); -1 before the first _process.
var _dmg_band := -1
## Overlay child that draws the damage FX over the sprite art. Null unless
## the building is currently damaged (band >= 1).
var _dmg_layer: Node2D = null


## Overlay layer for battle-damage FX. A plain child Node2D draws AFTER the
## parent's own _draw AND after the Sprite2D child, so smoke and flames
## read over the building art instead of hiding behind it. The host owns
## the animation step; this layer only forwards its _draw. Created when a
## building first takes real damage, freed when repaired to healthy.
class DamageFXLayer extends Node2D:
	var host: BuildingNode = null
	func _draw() -> void:
		if host != null and is_instance_valid(host):
			host.draw_damage_fx(self)


## Pure: damage band for an hp fraction. Test seam — no node needed.
## Ladder: 0 pristine (>= 85%), 1 scuffed, 2 cracked/crumbling,
## 3 smoking, 4 burning (< 30% — the sim's "burning" captured hall
## at 25% stays band 4).
static func damage_band_for(frac: float) -> int:
	if frac < DMG_BURN_FRAC:
		return 4
	if frac < DMG_SMOKE_FRAC:
		return 3
	if frac < DMG_CRACK_FRAC:
		return 2
	if frac < DMG_SCUFF_FRAC:
		return 1
	return 0
## Per-building FX phase: neighboring mills don't pulse in sync (the
## banner-flutter precedent, quantized to the FX cadence).
var _fx_phase := 0
## Actual render scale of the building sprite (set in _apply_sprite). The oil
## pumpjack's production FX anchors (vent/puddle) are art-pixel positions in
## bld_oil_pump.png; this turns them into node-space offsets that track the
## real scale even if _size_for defaults change.
var _sprite_sc := 1.0
## Test hook: faction color the banner last drew with; transparent black when
## no banner was drawn (non-seat / wall / blueprint).
var _last_banner_color := Color(0, 0, 0, 0)


## Pure: quantized pennant wave step for a wall-clock time in seconds.
static func banner_step_for(t: float) -> int:
	return int(t * BANNER_WAVE_HZ * float(BANNER_WAVE_STEPS)) % BANNER_WAVE_STEPS


## Pure: quantized oil-pumpjack FX step for a wall-clock time in seconds.
## Shares the eatery cadence (8 steps at 6/sec).
static func oil_pump_step_for(t: float) -> int:
	return int(t * EATERY_FX_PER_SEC) % EATERY_FX_STEPS


## Pure: crop sway offset (graphics-hourly 2026-10-09) for sprout `idx`
## at FX `step`: a breeze ripples across the rows, staggered 1/12-cycle
## per sprout so the wave visibly travels left to right. Deterministic
## (no RNG, no allocation), quantized on the shared FX cadence. Range:
## +-FARM_FX_SWAY.
static func farm_sway_for(step: int, idx: int) -> float:
	var phase := float(step) / float(EATERY_FX_STEPS) + float(idx) / 12.0
	return sin(phase * TAU) * FARM_FX_SWAY


## ---- Completion reveal: pure math (graphics-hourly 2026-10-08) ----

## Walls are excluded from the reveal (drag-place chains complete dozens at
## once); empty btype never reveals either.
static func reveal_allowed_for(p_btype: String) -> bool:
	return p_btype != "" and p_btype != "wall"


## Reveal progress 0->1 over REVEAL_LEN, from remaining seconds.
static func reveal_k_for(t: float) -> float:
	return clampf(1.0 - t / REVEAL_LEN, 0.0, 1.0)


## Ease-out cubic: the building bursts up fast, then settles onto the ground.
static func reveal_ease(k: float) -> float:
	return 1.0 - pow(1.0 - k, 3.0)


## Sprite alpha during the reveal: blueprint translucency fades to solid as
## the building rises.
static func reveal_alpha_for(k: float) -> float:
	return 0.45 + 0.55 * reveal_ease(k)


## Ground ring: expands past the footprint while fading out.
static func reveal_ring_radius_for(footprint: float, k: float) -> float:
	return footprint * (0.55 + 1.15 * k)


static func reveal_ring_alpha_for(k: float) -> float:
	return 0.55 * (1.0 - k)


## Six seeded dust puffs drift outward along the squashed ground plane.
static func reveal_puff_pos(i: int, footprint: float, k: float,
		phase: float) -> Vector2:
	var ang := TAU * float(i) / 6.0 + phase
	var r := footprint * (0.55 + 0.95 * k)
	return Vector2(cos(ang) * r, sin(ang) * r * 0.55)


static func reveal_puff_radius_for(footprint: float, k: float) -> float:
	return footprint * 0.22 * (1.0 - 0.45 * k)


static func reveal_puff_alpha_for(k: float) -> float:
	return 0.5 * (1.0 - k)

## Test hook: which programmer-art silhouette arm _draw used for this node
## ("sawmill", "farm", "generic", ...). Stays "" on the sprite-art path and
## for incomplete blueprints (both return before the match).
var _last_art := ""


func _process(delta: float) -> void:
	# Animate construction: translucent art + progress ring.
	var rec: Dictionary = record
	# Battlefront 2026-10-06: the sim flips a captured post's record
	# faction in place (_flip_hall). Self-heal so the pennant always
	# matches the live record, even if no bus signal reached the world
	# (the world also calls set_faction() on command_post_captured).
	var rec_faction := String(rec.get("faction", ""))
	if rec_faction != "" and rec_faction != faction:
		set_faction(rec_faction)
	var complete: bool = bool(rec.get("complete", true))
	if _sprite != null and _reveal_t <= 0.0:
		var want_a := 1.0
		if not complete:
			# P6: the ghost brightens across the roof/finish phase — the
			# building visibly "finishes" before the reveal rise plays.
			want_a = 0.45
			if construction_phase_for(float(rec.get("progress", 0.0))) >= 3:
				var k := clampf((float(rec.get("progress", 0.0)) - 0.75)
					/ 0.25, 0.0, 1.0)
				want_a = 0.45 + 0.50 * k
		if _sprite.modulate.a != want_a:
			_sprite.modulate.a = want_a
	if not rec.is_empty() and (not complete or not _was_complete):
		var just_finished: bool = complete and not _was_complete
		_was_complete = complete
		if just_finished:
			on_construction_finished()
		queue_redraw()
	# Completion reveal: one-shot rise + dust (REVEAL_STEPS quantized redraws,
	# then the node rests). Owns the sprite pose/alpha while it plays.
	if _reveal_t > 0.0:
		_reveal_t = maxf(0.0, _reveal_t - delta)
		var rstep := int(reveal_k_for(_reveal_t) * float(REVEAL_STEPS))
		if rstep != _reveal_step:
			_reveal_step = rstep
			_apply_reveal_pose()
		queue_redraw()
	# Shadow tracks the sun; redraw only when the quantized key changes.
	var sk := Shadows.shadow_key(position)
	if sk != _shadow_key:
		_shadow_key = sk
		queue_redraw()
	# Night window glow flickers gently; redraw on quantized glow change.
	if building_id >= 0:
		var gk := NightGlow.glow_key(building_id)
		if gk != _glow_key:
			_glow_key = gk
			queue_redraw()
	# Walls: redraw when the damage band changes so cracks and chipped
	# merlons appear as the wall takes damage (quantized — no per-hit cost).
	if btype == "wall" and not rec.is_empty():
		var db := WallMesh.damage_band(WallMesh.hp_frac(
			float(rec.get("hp", 900.0)), float(rec.get("max_hp", 900.0))))
		if db != _wall_dmg_band:
			_wall_dmg_band = db
			queue_redraw()
	# Windmill blades turn (programmer-art path only — sprite windmills
	# don't draw blades). Quantized so a windmill redraws ~8x/sec.
	if btype == "windmill" and _sprite == null and complete:
		_blade_angle = fmod(_blade_angle + WINDMILL_TURN * delta, TAU)
		var step := int(_blade_angle / TAU * float(WINDMILL_STEPS))
		if step != _blade_step:
			_blade_step = step
			queue_redraw()
	# Faction banner flutter (seat buildings only). Quantized wave step, the
	# windmill precedent: ~20 seats redraw ~7x/sec, zero per-frame cost on
	# every other building (one cheap `in` check on a 7-item const array).
	if complete and btype in BANNER_BTYPES:
		var bstep := banner_step_for(float(Time.get_ticks_msec()) / 1000.0)
		if bstep != _banner_step:
			_banner_step = bstep
			queue_redraw()
	# Eatery vent FX (graphics-hourly 2026-10-06): animated chimney
	# smoke/steam/spores/mist on the 10 perk eateries + repair shop.
	# Quantized to EATERY_FX_STEPS steps at EATERY_FX_PER_SEC — ~6
	# redraws/sec per eatery node, zero cost for everything else (one
	# cheap `in` check on an 11-item const array).
	if complete and btype in EATERY_FX_BTYPES:
		var fxstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if fxstep != _fx_step:
			_fx_step = fxstep
			queue_redraw()
	# Oil pumpjack production FX (wake routine 2026-10-07): complete
	# pumpjacks animate exhaust + oil sheen. Same quantized cadence as
	# the eatery vents; blueprints and every other type skip with a
	# single cheap check.
	if complete and btype == "oil_pump":
		var pstep := oil_pump_step_for(float(Time.get_ticks_msec()) / 1000.0)
		if pstep != _fx_step:
			_fx_step = pstep
			queue_redraw()
	# Industrial production FX (graphics-hourly 2026-10-07): sawmill
	# sawdust + spinning blade, quarry dust, mine lantern flicker, smithy
	# forge fire + sparks + chimney smoke. Same quantized cadence; one
	# cheap `in` check skips everything else.
	if complete and btype in INDUSTRIAL_FX_BTYPES:
		var istep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if istep != _fx_step:
			_fx_step = istep
			queue_redraw()
	# House chimney smoke (graphics-hourly 2026-10-07): complete houses
	# breathe smoke from their chimneys. Same quantized cadence; one
	# cheap `in` check skips everything else.
	if complete and btype in HOUSE_FX_BTYPES:
		var hstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if hstep != _fx_step:
			_fx_step = hstep
			queue_redraw()
	# Tavern kitchen FX (graphics-hourly 2026-10-08): complete
	# sprite-path taverns breathe steam/smoke from their chimneys. Same
	# quantized cadence; one cheap check skips everything else (living
	# hotels use the chimney-less shop art, so the art-key check keeps
	# them static).
	if complete and btype in TAVERN_FX_BTYPES \
			and tavern_fx_art_key(btype, faction) != "":
		var tstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if tstep != _fx_step:
			_fx_step = tstep
			queue_redraw()
	# Monastery candle-glow FX (graphics-hourly 2026-10-09): complete
	# monasteries breathe candlelight on the shared quantized FX cadence.
	# One cheap `in` check skips everything else.
	if complete and btype in MONASTERY_FX_BTYPES:
		var mstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if mstep != _fx_step:
			_fx_step = mstep
			queue_redraw()
	# Mage spire arcane FX (graphics-hourly 2026-10-09): complete spires
	# breathe arcane light on the shared quantized FX cadence. One cheap
	# `in` check skips everything else.
	if complete and btype in MAGESPIRE_FX_BTYPES:
		var sstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if sstep != _fx_step:
			_fx_step = sstep
			queue_redraw()
	# Military war-machine FX (massive-dev 2026-10-09): complete military
	# buildings breathe on the shared quantized FX cadence. One cheap
	# `in` check + art-key check skips everything else (undead guard
	# houses keep the drawn fallback arm — no art, no FX).
	if complete and btype in MILITARY_FX_BTYPES \
			and military_fx_art_key(btype, faction) != "":
		var xstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if xstep != _fx_step:
			_fx_step = xstep
			queue_redraw()
	# Shop storefront FX (graphics-hourly 2026-10-09): complete shops
	# breathe lamplight on the shared quantized FX cadence. One cheap
	# `in` check + art-key check skips everything else (wells reuse the
	# shop art but stay dark; undead hotels keep their tavern FX).
	if complete and btype in SHOP_FX_BTYPES \
			and shop_fx_art_key(btype, faction) != "":
		var wstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if wstep != _fx_step:
			_fx_step = wstep
			queue_redraw()
	# Farm crop sway (graphics-hourly 2026-10-09): complete farms ripple
	# their crops on the shared quantized FX cadence. One cheap `in`
	# check skips everything else (blueprints, the undead flesh_farm).
	if complete and btype in FARM_FX_BTYPES:
		var fstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if fstep != _fx_step:
			_fx_step = fstep
			queue_redraw()
	# Civic seat FX (graphics-hourly 2026-10-09): complete seats of power
	# breathe lamplight on the shared quantized FX cadence. One cheap
	# `in` check + art-key check skips everything else (blueprints stay
	# dark; the gov_* offices, clinic, tome_library and bathhouse share
	# the bld_civic art but are not seats).
	if complete and btype in CIVIC_FX_BTYPES \
		and civic_fx_art_key(btype, faction) != "":
		var cstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if cstep != _fx_step:
			_fx_step = cstep
			queue_redraw()
	# Flesh-farm FX (graphics-hourly 2026-10-09): complete undead farms
	# breathe green lamplight on the shared quantized FX cadence. One
	# cheap `in` check skips everything else.
	if complete and btype in FLESH_FX_BTYPES:
		var vstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if vstep != _fx_step:
			_fx_step = vstep
			queue_redraw()
	# Restaurant kitchen FX (graphics-hourly 2026-10-09): complete faction
	# eateries breathe kitchen steam / soul wisps on the shared quantized
	# FX cadence. One cheap `in` check skips everything else.
	if complete and btype in RESTAURANT_FX_BTYPES:
		var rstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if rstep != _fx_step:
			_fx_step = rstep
			queue_redraw()
	# Medic-tent FX (graphics-hourly 2026-10-09): the entrance lantern
	# breathes on the shared quantized FX cadence. One cheap `in` check
	# skips everything else.
	if complete and btype in MEDIC_FX_BTYPES:
		var mestep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if mestep != _fx_step:
			_fx_step = mestep
			queue_redraw()
	# Lumber-camp FX (graphics-hourly 2026-10-09): the wood loop's anchor
	# breathes sawdust on the shared quantized FX cadence. One cheap `in`
	# check skips everything else.
	if complete and btype in LUMBER_FX_BTYPES:
		var lstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if lstep != _fx_step:
			_fx_step = lstep
			queue_redraw()
	# Stockpile depot FX (graphics-hourly 2026-10-09): complete depots
	# breathe dust/smoke/lantern light on the shared quantized FX cadence.
	# One cheap `in` check skips everything else (the art key never misses
	# for a roster btype, so no key check needed - the restaurant/farm
	# precedent).
	if complete and btype in STOCKPILE_FX_BTYPES:
		var dstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if dstep != _fx_step:
			_fx_step = dstep
			queue_redraw()
	# Fishing-dock water FX (rapid-iteration 2026-10-09): complete docks
	# lap foam + breathe lantern light on the shared quantized FX cadence.
	# One cheap `in` check skips everything else (blueprints stay dark;
	# the pier keeps its baked waterline glints).
	if complete and btype in FISHING_FX_BTYPES:
		var wstep := int(float(Time.get_ticks_msec()) / 1000.0
			* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
		if wstep != _fx_step:
			_fx_step = wstep
			queue_redraw()
	# Battle damage FX (graphics-hourly 2026-10-07; P6 ladder 2026-10-10):
	# complete non-wall buildings show scuffed < 85%, cracked < 65%,
	# smoking < 45%, burning < 30%. Healthy buildings
	# pay for two dict reads and one int compare per frame; the overlay
	# layer only exists while damaged, so undamaged buildings draw
	# exactly as before.
	if complete and btype != "wall" and not rec.is_empty():
		var max_hp: float = float(rec.get("max_hp", rec.get("hp", 400.0)))
		var band := 0
		if max_hp > 0.0:
			band = damage_band_for(float(rec.get("hp", max_hp)) / max_hp)
		if band != _dmg_band:
			_dmg_band = band
			if band >= 1:
				_ensure_dmg_layer()
			else:
				_clear_dmg_layer()
		if band >= 1:
			var dstep := int(float(Time.get_ticks_msec()) / 1000.0
				* EATERY_FX_PER_SEC) % EATERY_FX_STEPS
			if dstep != _fx_step:
				_fx_step = dstep
				if _dmg_layer != null and is_instance_valid(_dmg_layer):
					_dmg_layer.queue_redraw()


func setup(p_id: int, p_btype: String, p_faction: String, p_pos: Vector2) -> void:
	building_id = p_id
	btype = p_btype
	faction = p_faction
	position = p_pos
	# FX phase: deterministic per building so neighboring production
	# buildings don't pulse in sync (banner-flutter precedent).
	_fx_phase = absi(hash(p_id)) % EATERY_FX_STEPS
	# Faction banner: deterministic wave phase per building so neighboring
	# seats don't flutter in sync (the MapProp sway-phase precedent).
	# hash() returns a 64-bit int; normalize against INT64_MAX into [0, TAU).
	_banner_phase = float(absi(hash(p_id))) / 9223372036854775807.0 * TAU
	_apply_sprite()


## Completion-reveal trigger: the blueprint->complete edge calls this once.
## The building rises out of the ground over REVEAL_LEN with a dust ring.
## Walls are excluded (drag-place chains complete dozens at once). Capture
## flips call set_faction() -> _apply_sprite(), which cancels any in-flight
## reveal so a faction swap never leaves the sprite parked mid-rise.
func on_construction_finished() -> void:
	if not reveal_allowed_for(btype):
		return
	_reveal_t = REVEAL_LEN
	_reveal_step = -1
	if _sprite != null:
		_reveal_base_y = _sprite.position.y


## Ease the sprite up out of the ground along the reveal curve. At k = 1 the
## exact base position and solid alpha are restored so the reveal is
## pixel-perfect invisible afterwards (no drift, no translucency leak).
func _apply_reveal_pose() -> void:
	var k := reveal_k_for(_reveal_t)
	if _sprite == null:
		return
	if _reveal_t <= 0.0:
		_sprite.position.y = _reveal_base_y
		_sprite.modulate.a = 1.0
		return
	var rise := _size_for(btype) * REVEAL_RISE
	_sprite.position.y = _reveal_base_y + rise * (1.0 - reveal_ease(k))
	_sprite.modulate.a = reveal_alpha_for(k)


## Rebuild the art sprite for the current btype/faction. setup() runs it
## once; set_faction() runs it again so a captured post swaps any
## faction-variant art (BUILDING_ART_FACTION) alongside its pennant.
func _apply_sprite() -> void:
	if _sprite != null:
		remove_child(_sprite)
		_sprite.queue_free()
		_sprite = null
	# 2026-10-06: walls render as cel-shaded 3D volumes (WallMesh3D), not the
	# flat wall_strip sprite — skip the sprite path for them.
	var tex: Texture2D = null
	if btype != "wall":
		tex = Art.building_texture_for(btype, faction)
	if tex == null:
		return  # missing-art fallback arm draws in _draw instead
	# A faction-swap art rebuild cancels any in-flight reveal: the rising
	# sprite is replaced, so re-triggering the rise on the new sprite would
	# double-apply the offset. The new sprite starts at its ground base.
	_reveal_t = 0.0
	_reveal_step = -1
	_sprite = Sprite2D.new()
	_sprite.texture = tex
	SpriteNormalsScript.apply_to(_sprite)
	var target_w := _size_for(btype) * 2.4
	var sc: float = target_w / float(tex.get_width())
	_sprite.scale = Vector2(sc, sc)
	_sprite_sc = sc
	# Base on the ground point (y-sort reads correctly).
	_sprite.position = Vector2(0, -float(tex.get_height()) * sc * 0.48)
	add_child(_sprite)


## Jeremy 2026-10-06 (Battlefront directive): captured command posts flip
## faction instead of being destroyed. Re-point the node at the new
## holder — the pennant redraws in the new faction's faction color and
## faction-variant art swaps (guild_hall elves -> guild_hall humans, etc.).
## Called by the world on the command_post_captured bus signal; the
## _process drift check below is the self-heal for any other path that
## mutates the sim record's faction in place.
func set_faction(p_faction: String) -> void:
	if p_faction == faction:
		return
	faction = p_faction
	_apply_sprite()
	queue_redraw()


func _draw() -> void:
	# 2026-10-06: walls are cel-shaded 3D volumes (WallMesh3D) — their own
	# draw path, before the sprite/programmer-art paths below.
	if btype == "wall":
		_draw_wall_3d()
		return
	var complete: bool = bool(record.get("complete", true))
	# Sun-driven blob shadow under the footprint (drawn first = under art).
	# Blueprints cast a fainter shadow. Complete bridges skip it: the
	# _bridge arm draws fix79's own water shadow under the deck, and a
	# sun blob at the deck center would sit ON the walkway (2026-10-06).
	if not (btype == "bridge" and complete):
		Shadows.draw_blob(self, _size_for(btype), 0.5 if not complete else 1.0)
	# Completion reveal dust: expanding ground ring + puffs at the base while
	# the finished building rises. Lives here (above the shadow, below the
	# sprite child) so it covers both the sprite-art and drawn-silhouette
	# arms — the sprite path returns early below.
	if _reveal_t > 0.0 and complete and reveal_allowed_for(btype):
		_draw_reveal_dust()
	if _sprite != null:
		if not complete:
			# P6 staged construction: foundation -> frame -> walls ->
			# roof/finish rises around the translucent ghost, then the
			# progress ring on top.
			var sfc: Dictionary = Config.FACTIONS.get(faction, {})
			_draw_construction_phase(
				construction_phase_for(float(record.get("progress", 0.0))),
				sfc.get("color", Color.WHITE))
			_draw_progress_ring()
			return
		# Real art: lamplight halo + lit doorway at night (windows are
		# baked into the art, so no drawn window rects here).
		if btype != "wall":
			NightGlow.draw_glow(self, building_id, _size_for(btype), false)
			# Faction banner over the sprite art (complete seats only;
		# blueprints return above, walls never carry banners).
		if btype in BANNER_BTYPES:
			var sfc: Dictionary = Config.FACTIONS.get(faction, {})
			_draw_faction_banner(sfc.get("color", Color.WHITE))
		# Production FX: a finished pumpjack exhales exhaust and its
		# wellhead puddle shimmers (blueprints returned above — a
		# half-built pump doesn't produce oil).
		if btype == "oil_pump":
			_oil_pump_fx()
		# Smithy production FX (graphics-hourly 2026-10-07): the baked
		# forge fire pulses with ember glow and sparks while the chimney
		# smokes. Blueprints returned above — a half-built forge isn't lit.
		if btype == "weaponsmith" or btype == "blacksmith":
			_smithy_fx()
		# House chimney smoke (graphics-hourly 2026-10-07): complete
		# houses breathe smoke from their chimneys. Blueprints returned
		# above — an unfinished house has no hearth fire.
		if btype in HOUSE_FX_BTYPES:
			_house_fx()
		# Tavern kitchen FX (graphics-hourly 2026-10-08): the inn
		# (living) and undead tavern (undead inn/hotel) sprites bake
		# a chimney — kitchens breathe steam/smoke from it.
		# Blueprints returned above — an unbuilt kitchen isn't cooking.
		if btype in TAVERN_FX_BTYPES:
			_tavern_fx()
		# Mage spire arcane FX (graphics-hourly 2026-10-09): the crown
		# crystal breathes arcane light. Blueprints returned above —
		# an unfinished spire holds no charge.
		if btype in MAGESPIRE_FX_BTYPES:
			_magespire_fx()
		# Military war-machine FX (massive-dev 2026-10-09): the war
		# machine breathes. Blueprints returned above — an unfinished
		# fort holds no garrison.
		if btype in MILITARY_FX_BTYPES:
			_military_fx()
		# Shop storefront FX (graphics-hourly 2026-10-09): lamplit
		# windows + coin glints / potion-stall wisps. Blueprints
		# returned above — an unbuilt shop isn't open for business.
		if btype in SHOP_FX_BTYPES:
			_shop_fx()
		# Civic seat FX (graphics-hourly 2026-10-09): lamplit windows
		# + entrance braziers. Blueprints returned above — an unbuilt
		# hall holds no council.
		if btype in CIVIC_FX_BTYPES:
			_civic_fx()
		# Flesh-farm FX (graphics-hourly 2026-10-09): green lantern
		# pulse + pit wisps on the undead farm. Blueprints returned
		# above — an unbuilt farm holds no harvest.
		if btype in FLESH_FX_BTYPES:
			_flesh_fx()
		# Restaurant kitchen FX (graphics-hourly 2026-10-09): the per-race
		# eatery sprites bake chimneys/vents — living kitchens exhale
		# steam, the soul cafe breathes soul wisps. Blueprints returned
		# above — an unbuilt kitchen isn't cooking.
		if btype in RESTAURANT_FX_BTYPES:
			_restaurant_fx()
		# Lumber-camp FX (graphics-hourly 2026-10-09): sawdust off the
		# sawbuck, chips off the stump. Blueprints returned above — an
		# unbuilt camp cuts no wood.
		if btype in LUMBER_FX_BTYPES:
			_lumber_fx()
		# Stockpile FX (graphics-hourly 2026-10-09): dust at the loading
		# door, chimney smoke, lantern breath. Blueprints returned above -
		# an unbuilt depot moves no goods.
		if btype in STOCKPILE_FX_BTYPES:
			_stockpile_fx()
		# Medic-tent FX (graphics-hourly 2026-10-09): the entrance
		# lantern breathes. Blueprints returned above — an unbuilt
		# tent treats no one.
		if btype in MEDIC_FX_BTYPES:
			_medic_fx()
		return
	# Programmer-art silhouettes for types with no source art.
	var fc: Dictionary = Config.FACTIONS.get(faction, {})
	var c: Color = fc.get("color", Color.WHITE)
	if not complete:
		# P6 staged construction: foundation -> frame -> walls ->
		# roof/finish, ground-anchored; the progress ring stays centered
		# on the ground point (same as the sprite path's blueprint ring).
		_draw_construction_phase(
			construction_phase_for(float(record.get("progress", 0.0))), c)
		_draw_progress_ring()
		return
	# Re-anchor the centered drawn arms onto the ground point (node
	# origin): shadow, y-sort and doorway all read the same ground as the
	# sprite path. Reset before the doorway/glow/banner below, which are
	# ground-relative by design.
	var gy: float = float(DRAWN_GROUND_Y.get(btype, 15.0))
	draw_set_transform(Vector2(0.0, -gy), 0.0, Vector2.ONE)
	match btype:
		"farm":
			_last_art = "farm"
			_farm(c)
		"clinic":
			_last_art = "clinic"
			_clinic()
		"aa_tower":
			_last_art = "aa_tower"
			_aa_tower()
		# Building-art fix 2026-10-06: 'air_defense' is the legacy alias
		# of aa_tower — fix79 draws both in the same drawBuilding branch.
		# The sprite path (bld_tower) handles live art; this arm is the
		# missing-art fallback, mirroring the aa_tower precedent.
		"air_defense":
			_last_art = "air_defense"
			_aa_tower()
		"well":
			_last_art = "well"
			_well(c)
		"windmill":
			_last_art = "windmill"
			_box(c, 20.0, 1.8)
			_blades(c.lightened(0.2), 26.0, _blade_angle)
		"mage_spire":
			_last_art = "mage_spire"
			_mage_spire(c)
		"monastery":
			_last_art = "monastery"
			_monastery(c)
			_monastery_fx()
		"fishing_dock":
			_last_art = "fishing_dock"
			_fishing_dock(c)
			_fishing_dock_fx()
		"flesh_farm":
			_last_art = "flesh_farm"
			_box(c, 34.0, 0.7)
			_cross(10.0)
		"fire_station":
			_last_art = "fire_station"
			_fire_station(c)
		"wagon_dealership":
			_last_art = "wagon_dealership"
			_dealership(c)
		"sawmill":
			_last_art = "sawmill"
			_sawmill(c)
			_sawmill_fx()
		"quarry":
			_last_art = "quarry"
			_quarry()
			_quarry_fx()
		"mine":
			_last_art = "mine"
			_mine(c)
			_mine_fx()
		"bathhouse":
			_last_art = "bathhouse"
			_bathhouse(c)
		"hotel", "inn":
			# HTML draws hotel/inn in the exact same branch as bathhouse
			# (t === 'bathhouse' || t === 'hotel' || t === 'inn'); only the
			# label differs (t.toUpperCase()).
			_last_art = "bathhouse"
			_bathhouse(c, btype.to_upper())
		"guard_house":
			_last_art = "guard_house"
			_guard_house(c)
		"war_hut":
			_last_art = "war_hut"
			_war_hut(c)
		"nuke_silo":
			_last_art = "nuke_silo"
			_nuke_silo()
		"medic_camp":
			_last_art = "medic_camp"
			_medic_camp()
		"cannon_foundry":
			_last_art = "cannon_foundry"
			_cannon_foundry()
		"tome_library":
			_last_art = "tome_library"
			_tome_library(c)
		"armory":
			_last_art = "armory"
			_armory()
		"weaponsmith":
			_last_art = "weaponsmith"
			_weaponsmith()
			# Missing-art fallback arm only (bld_smithy.png takes the sprite
			# path above): a lit forge window with flicker so a sprite-less
			# smithy still reads as working.
			_weaponsmith_fallback_fx()
		"shooting_range":
			_last_art = "shooting_range"
			_shooting_range(c)
		"vehicle_depot":
			_last_art = "vehicle_depot"
			_vehicle_depot()
		"pier":
			_last_art = "pier"
			_pier()
		# Building-art fix 2026-10-06: bridge segments fell through to the
		# generic box+roof arm. fix79 draws them procedurally as
		# drawBridgeDeck (STILTWOOD76) — a 2.5D stilted wooden walkway —
		# so this port is the parity target, not a PNG (there is no bridge
		# sprite in the HTML's TEX_SPRITE_SRC set).
		"bridge":
			_last_art = "bridge"
			_bridge()
		"shop":
			_last_art = "shop"
			_shop()
		"seedshop":
			_last_art = "seedshop"
			_seedshop()
		"trade_outpost":
			_last_art = "trade_outpost"
			_trade_outpost()
		"garden":
			_last_art = "garden"
			_garden()
		# Launch-readiness graphics 2026-10-06: the ten SimFoodPerks eateries
		# take the per-race pixel-art eatery sprites from BUILDING_ART
		# (sprite path returns before this match); this arm is the
		# missing-art fallback only, sharing one themed shop silhouette.
		"greasy_spoon", "salad_bar", "ogre_sausage_shop", "meat_tornado", \
		"moonberry_lounge", "dewdrop_diner", "bastard_drivethru", \
		"fungus_hut", "crypt_kitchen", "grave_snacks":
			_last_art = "eatery"
			_eatery(btype)
		"repair_shop":
			_last_art = "repair_shop"
			_repair_shop()
		_:
			_last_art = "generic"
			_box(c, 30.0)
			_roof(c, 30.0, 12.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if btype != "wall":
		var s := _size_for(btype)
		# Types with their own doorway/entrance, over-water types and flat
		# plots skip the generic ground doorway rect (SELF_DOOR_BTYPES).
		if btype not in SELF_DOOR_BTYPES:
			draw_rect(Rect2(-5, -16, 10, 16), Color(0.15, 0.1, 0.08))
		# Night window glow: lit windows + halo + lit doorway on
		# programmer-art silhouettes (walls and blueprints never glow).
		# Flat/non-box types get the halo only — generic windows and the
		# doorway would float over terrain/water instead of a wall face.
		if complete:
			if btype in FLAT_GLOW_BTYPES:
				NightGlow.draw_glow(self, building_id, s, false, false)
			else:
				NightGlow.draw_glow(self, building_id, s, true)
		# Faction banner on seats of power (this path only runs for complete
		# buildings; walls are excluded by the BANNER_BTYPES membership).
		if btype in BANNER_BTYPES:
			_draw_faction_banner(c)


## Faction banner (graphics-hourly 2026-10-05): a tall pole on the building's
## right shoulder with a waving pennant in the faction color — darker outline
## for definition, gold finial on the pole tip. The flutter comes from the
## deterministic phase plus the quantized wave step (see _process); before
## the first step lands, maxi() pins the pennant to the phase pose.
## Called only for complete seats of power; sets the _last_banner_color test
## hook. Drawn geometry is in local space with the building base at origin.
func _draw_faction_banner(c: Color) -> void:
	_last_banner_color = c
	var s := _size_for(btype)
	# Pole rises from the building's right shoulder, base buried in the
	# roof so it never floats (sprite tops sit around -s*1.7 for the 4:3
	# hall art; the pole tip clears them at -s*1.85).
	var px := s * 0.42
	var roof_y := -s * 1.0
	var top_y := roof_y - s * 0.85
	var wood := Color(0.32, 0.22, 0.14)
	draw_line(Vector2(px, roof_y + 8.0), Vector2(px, top_y), wood, 3.0)
	# Gold finial on the pole tip.
	draw_circle(Vector2(px, top_y - 2.0), 2.5, Color(0.95, 0.78, 0.25))
	# Pennant: triangular flag streaming right, tip fluttering.
	var wave := sin(_banner_phase \
		+ float(maxi(_banner_step, 0)) / float(BANNER_WAVE_STEPS) * TAU)
	var tip := Vector2(px + s * 0.58, top_y + s * 0.125 + wave * s * 0.08)
	var pts := PackedVector2Array([
		Vector2(px, top_y + 1.0),
		tip,
		Vector2(px, top_y + s * 0.25),
	])
	draw_colored_polygon(pts, c)
	# Outline so the pennant reads on any sky/terrain behind it.
	pts.append(pts[0])
	draw_polyline(pts, c.darkened(0.45), 1.5)


func _size_for(p_btype: String) -> float:
	match p_btype:
		"town_hall", "hall":
			return 52.0
		# NECROHALL79 (fix79): the undead hall renders the Necropolis at
		# 1.5x width so it reads as the faction's grand seat of power,
		# grander than living halls. 52.0 * 1.5 = 78.0.
		"necropolis":
			return 78.0
		"knights_castle":
			return 52.0
		"mage_spire", "war_hut":
			return 48.0
		"barracks":
			return 42.0
		"farm":
			return 40.0
		"courthouse", "guild_hall":
			return 40.0
		# Graphics-hourly 2026-10-04: the C61 faction eateries are
		# prominent commercial buildings (fix79 draws them 148px wide,
		# ~2x a house) — same civic-building footprint as guild_hall.
		"restaurant", "soul_cafe":
			return 40.0
		"jail":
			return 34.0
		"fire_station":
			return 38.0
		"farmhouse":
			return 34.0
		"horse_stable", "windmill":
			return 36.0
		"clinic", "sawmill", "quarry", "mine", "bathhouse", "repair_shop":
			return 32.0
		"hotel", "inn", "weaponsmith":
			return 32.0
		"vehicle_depot":
			return 44.0
		"shooting_range":
			return 48.0
		"house":
			return 30.0
		"guard_house", "fishing_dock", "storage":
			return 30.0
		"stock_gold", "stock_wood", "stock_food", "stock_oil", "stock_seeds":
			return 30.0
		"guard_tower":
			return 24.0
		"aa_tower":
			return 26.0
		# Building-art fix 2026-10-06: air_defense is the legacy alias of
		# aa_tower — same footprint.
		"air_defense":
			return 26.0
		# Building-art fix 2026-10-06: bridge def size is 40.0
		# (SimBuildings.BUILDINGS); the 78px deck visual overlaps
		# neighbors, the footprint stays 40 for shadow/door math.
		"bridge":
			return 40.0
		"wall":
			return 22.0
		"well":
			return 20.0
	return 30.0


func _box(c: Color, s: float, h_scale := 1.0) -> void:
	var h: float = s * h_scale
	draw_rect(Rect2(-s / 2, -h / 2, s, h), c.darkened(0.4))
	draw_rect(Rect2(-s / 2 + 3, -h / 2 + 3, s - 6, h - 6), c)


func _roof(c: Color, s: float, h: float) -> void:
	draw_colored_polygon(
		PackedVector2Array([
			Vector2(-s / 2 - 5, -s / 2 + 4),
			Vector2(s / 2 + 5, -s / 2 + 4),
			Vector2(0, -s / 2 - h),
		]),
		c.lightened(0.25))


func _cross(s: float) -> void:
	var w := Color(1, 1, 1, 0.95)
	draw_rect(Rect2(-s / 4, -s / 2, s / 2, s), w)
	draw_rect(Rect2(-s / 2, -s / 4, s, s / 2), w)


## AA tower (wake routine 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding aa_tower branch — a radar tower: stone-blue
## block (#78909c), a big radar dish disc (#455a64) with a vertical barrel
## (#212121) above it, and an 'AA' pill label. Replaces the generic
## box+arced-dish silhouette that didn't match the HTML. Colors are
## race-independent in the HTML too, so the faction color is unused.
## ASCII-only label via ThemeDB.fallback_font (iPhone tofu rule).
func _aa_tower() -> void:
	var ink := Color(0.102, 0.071, 0.039)  # HTML #1a120a
	var block_c := Color(0.471, 0.565, 0.612)  # HTML #78909c
	var dish_c := Color(0.271, 0.333, 0.388)  # HTML #455a64
	var barrel_c := Color(0.129, 0.129, 0.129)  # HTML #212121
	# Main block (HTML block 28x40 at (-14,-8), radius 3): dark outline +
	# body + the soft top highlight block() adds.
	draw_rect(Rect2(-14, -8, 28, 40), ink)
	draw_rect(Rect2(-12, -6, 24, 36), block_c)
	draw_rect(Rect2(-11, -4, 22, 5), Color(1, 1, 1, 0.14))
	# Radar dish (HTML: filled #455a64 circle at (0,-20) r14) with ink rim.
	draw_circle(Vector2(0, -20), 15.0, ink)
	draw_circle(Vector2(0, -20), 14.0, dish_c)
	# Vertical barrel above the dish (HTML fillRect(-4,-36,8,20) #212121).
	draw_rect(Rect2(-5, -37, 10, 22), ink)
	draw_rect(Rect2(-4, -36, 8, 20), barrel_c)
	# 'AA' pill label (HTML label(): dark pill + #fffde7 text, y=-48).
	var font: Font = ThemeDB.fallback_font
	draw_rect(Rect2(-28, -57, 56, 13), Color(0, 0, 0, 0.45))
	var tw: float = font.get_string_size("AA", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_string(font, Vector2(-tw * 0.5, -45.0), "AA",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Nuke silo (wake routine 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding nuke_silo branch — olive rounded block
## (#556b2f) with ink outline and the soft top highlight block() adds,
## a green dome ellipse (#2e7d32) rising above the roofline, and a
## 'SILO' pill label. Replaces the generic box+roof it drew before.
## Colors are race-independent in the HTML too, so the faction color is
## unused. ASCII-only label via ThemeDB.fallback_font (iPhone tofu rule).
func _nuke_silo() -> void:
	var ink := Color(0.102, 0.071, 0.039)   # HTML #1a120a
	var olive := Color(0.333, 0.420, 0.184) # HTML #556b2f
	var dome := Color(0.180, 0.490, 0.196)  # HTML #2e7d32
	# Rounded main block (HTML block 48x44 at (-24,-10), radius 4).
	draw_rect(Rect2(-24, -10, 48, 44), ink)
	draw_rect(Rect2(-22, -8, 44, 40), olive)
	draw_rect(Rect2(-21, -8, 42, 8), Color(1, 1, 1, 0.14))
	# Green dome rising from the roof (HTML ellipse(0,-28,18,22) #2e7d32).
	var pts := PackedVector2Array()
	for i in 24:
		var a: float = TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * 18.0, -28.0 + sin(a) * 22.0))
	draw_colored_polygon(pts, dome)
	# 'SILO' pill label (HTML label('SILO', -52): dark pill + #fffde7 text).
	draw_rect(Rect2(-28, -60, 56, 12), Color(0, 0, 0, 0.45))
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("SILO", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_string(font, Vector2(-tw * 0.5, -52.0), "SILO",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Medic camp (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding branch (shared with clinic: `t === 'clinic' ||
## t === 'medic_camp'`) — white rounded block (#eceff1, race-independent in
## the HTML too), red-cross sign on the roof, two window panes, a door, and
## a 'MEDIC' pill label (clinic's arm uses 'CLINIC'). Replaces the generic
## box+roof it drew before. ASCII-only label via ThemeDB.fallback_font
## (iPhone tofu rule).
func _medic_camp() -> void:
	var white := Color(0.925, 0.937, 0.945)  # HTML #eceff1
	var red := Color(0.898, 0.224, 0.208)    # HTML #e53935
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var glass := Color(0.506, 0.831, 0.980)  # HTML #81d4fa
	# Rounded main block (HTML block 60x36 at (-30,-10), radius 5): dark
	# outline + white body + the soft top highlight the HTML's block() adds.
	draw_rect(Rect2(-30, -10, 60, 36), ink)
	draw_rect(Rect2(-28, -8, 56, 32), white)
	draw_rect(Rect2(-25, -6, 50, 6), Color(1, 1, 1, 0.14))
	# Red cross sign on the roof (HTML #e53935 fillRects).
	draw_rect(Rect2(-7, -29, 14, 30), red.darkened(0.12))
	draw_rect(Rect2(-6, -28, 12, 28), red)
	draw_rect(Rect2(-15, -21, 30, 14), red.darkened(0.12))
	draw_rect(Rect2(-14, -20, 28, 12), red)
	# Two window panes (HTML windowPane: dark frame, blue glass, glint,
	# center mullion).
	for wx: float in [-20.0, 10.0]:
		draw_rect(Rect2(wx - 1, -3, 12, 12), ink)
		draw_rect(Rect2(wx, -2, 10, 10), glass)
		draw_rect(Rect2(wx + 1, -1, 3.5, 3.0), Color(1, 1, 1, 0.45))
		draw_line(Vector2(wx + 5, -2), Vector2(wx + 5, 8), ink, 1.2)
	# Door (HTML door(-8,10,16,16): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-9, 9, 18, 18), door_c.darkened(0.2))
	draw_rect(Rect2(-8, 10, 16, 16), door_c)
	draw_line(Vector2(-9, 9), Vector2(9, 9), ink, 1.5)
	draw_line(Vector2(-9, 27), Vector2(9, 27), ink, 1.5)
	draw_circle(Vector2(4, 18), 1.8, Color(1.0, 0.835, 0.310))
	# 'MEDIC' pill label above (HTML label(): dark pill + #fffde7 text).
	draw_rect(Rect2(-28, -44, 56, 12), Color(0, 0, 0, 0.45))
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("MEDIC", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_string(font, Vector2(-tw * 0.5, -36.0), "MEDIC",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Cannon foundry (graphics-hourly 2026-10-04): ported verbatim from
## fix79's procedural drawBuilding branch — steel-blue rounded block
## (#607d8b, 84x46), dark roof band (#455a64), two dark loading-bay
## doorways (#37474f), a cannon prop (ink barrel + wheel disc, #212121),
## a door, and a 'FOUNDRY' pill label. Replaces the generic box+roof it
## drew before. Colors are race-independent in the HTML too, so the
## faction color is unused. ASCII-only label via ThemeDB.fallback_font
## (iPhone tofu rule).
func _cannon_foundry() -> void:
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var steel := Color(0.376, 0.490, 0.545)  # HTML #607d8b
	var band := Color(0.271, 0.333, 0.388)   # HTML #455a64
	var bay := Color(0.216, 0.278, 0.310)     # HTML #37474f
	var dark := Color(0.129, 0.129, 0.129)   # HTML #212121
	# Main block (HTML block 84x46 at (-42,-16), radius 4): dark outline +
	# steel body + the soft top highlight block() adds.
	draw_rect(Rect2(-42, -16, 84, 46), ink)
	draw_rect(Rect2(-40, -14, 80, 42), steel)
	draw_rect(Rect2(-39, -12, 78, 8), Color(1, 1, 1, 0.14))
	# Dark roof band (HTML fillRect(-44,-24,88,12) #455a64).
	draw_rect(Rect2(-44, -24, 88, 12), ink)
	draw_rect(Rect2(-42, -22, 84, 8), band)
	# Two loading-bay doorways (HTML fillRects #37474f).
	draw_rect(Rect2(-24, -8, 16, 24), bay.darkened(0.25))
	draw_rect(Rect2(10, -8, 16, 24), bay.darkened(0.25))
	# Cannon prop: barrel + wheel (HTML fillRect(20,4,28,8) + arc(20,8,10),
	# both #212121).
	draw_rect(Rect2(19, 3, 30, 10), ink)
	draw_rect(Rect2(20, 4, 28, 8), dark)
	draw_circle(Vector2(20, 8), 11.0, ink)
	draw_circle(Vector2(20, 8), 10.0, dark)
	# Door (HTML door(-8,12,16,18): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-9, 11, 18, 20), door_c.darkened(0.2))
	draw_rect(Rect2(-8, 12, 16, 18), door_c)
	draw_circle(Vector2(4, 20), 1.8, Color(1.0, 0.835, 0.310))
	# 'FOUNDRY' pill label above (HTML label('FOUNDRY', -32): dark pill +
	# #fffde7 text).
	draw_rect(Rect2(-28, -40, 56, 12), Color(0, 0, 0, 0.45))
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("FOUNDRY", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_string(font, Vector2(-tw * 0.5, -32.0), "FOUNDRY",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Tome library (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding branch — wide block in the faction color (HTML
## P.wall), a big triangular roof (HTML P.roof), three book rects on the
## wall (#fff59d, #ffcc80, #a5d6a7), a door, and a 'TOMES' pill label.
## Replaces the generic box+roof it drew before. ASCII-only label via
## ThemeDB.fallback_font (iPhone tofu rule).
func _tome_library(c: Color) -> void:
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var glass := Color(0.506, 0.831, 0.980)  # HTML #81d4fa
	# Main block (HTML block 72x40 at (-36,-12), radius 6): dark outline +
	# faction-color body + the soft top highlight block() adds.
	draw_rect(Rect2(-36, -12, 72, 40), c.darkened(0.4))
	draw_rect(Rect2(-34, -10, 68, 36), c)
	draw_rect(Rect2(-33, -8, 66, 7), Color(1, 1, 1, 0.14))
	# Big triangular roof (HTML moveTo(-42,-12) lineTo(0,-48) lineTo(42,-12)
	# filled P.roof, ink-stroked).
	draw_colored_polygon(PackedVector2Array([
		Vector2(-42, -12), Vector2(0, -48), Vector2(42, -12)]),
		c.lightened(0.25))
	draw_polyline(PackedVector2Array([
		Vector2(-42, -12), Vector2(0, -48), Vector2(42, -12),
		Vector2(-42, -12)]), ink, 2.4)
	# Books on the wall (HTML fillRects).
	draw_rect(Rect2(-16, 0, 8, 14), Color(1.0, 0.961, 0.616))   # #fff59d
	draw_rect(Rect2(-4, -2, 8, 16), Color(1.0, 0.800, 0.502))   # #ffcc80
	draw_rect(Rect2(8, 0, 8, 14), Color(0.647, 0.839, 0.655))   # #a5d6a7
	# Door (HTML door(-8,12,16,16): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-9, 11, 18, 18), door_c.darkened(0.2))
	draw_rect(Rect2(-8, 12, 16, 16), door_c)
	draw_circle(Vector2(4, 20), 1.8, Color(1.0, 0.835, 0.310))
	# 'TOMES' pill label above (HTML label('TOMES', -54): dark pill +
	# #fffde7 text).
	draw_rect(Rect2(-28, -62, 56, 12), Color(0, 0, 0, 0.45))
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("TOMES", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_string(font, Vector2(-tw * 0.5, -54.0), "TOMES",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Armory (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding branch — dark blue-grey rounded block (#455a64,
## 64x40), dark top band (#263238), a weapon rack of five steel bars
## (#90a4ae), an 'ARMORY' caption on the wall (#ffd54f, HTML draws it with
## fillText directly rather than label()), and a door. Replaces the generic
## box+roof it drew before. Colors are race-independent in the HTML too, so
## the faction color is unused. ASCII-only text via ThemeDB.fallback_font
## (iPhone tofu rule).
func _armory() -> void:
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var block_c := Color(0.271, 0.333, 0.388)  # HTML #455a64
	var band := Color(0.149, 0.196, 0.220)    # HTML #263238
	var steel := Color(0.565, 0.643, 0.682)  # HTML #90a4ae
	var gold := Color(1.0, 0.835, 0.310)     # HTML #ffd54f
	# Main block (HTML block 64x40 at (-32,-14), radius 4): dark outline +
	# blue-grey body + the soft top highlight block() adds.
	draw_rect(Rect2(-32, -14, 64, 40), ink)
	draw_rect(Rect2(-30, -12, 60, 36), block_c)
	draw_rect(Rect2(-29, -10, 58, 6), Color(1, 1, 1, 0.14))
	# Dark top band (HTML fillRect(-34,-22,68,12) #263238).
	draw_rect(Rect2(-34, -22, 68, 12), ink)
	draw_rect(Rect2(-32, -20, 64, 8), band)
	# Weapon rack: five vertical steel bars (HTML fillRects #90a4ae).
	for i in range(5):
		var bx := -20.0 + float(i) * 10.0
		draw_rect(Rect2(bx - 1, -9, 5, 24), ink)
		draw_rect(Rect2(bx, -8, 3, 22), steel)
	# 'ARMORY' caption on the wall (HTML fillText('ARMORY', 0, -6) bold 9px
	# #ffd54f, centered).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("ARMORY", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 9).x
	draw_string(font, Vector2(-tw * 0.5, -6.0), "ARMORY",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, gold)
	# Door (HTML door(-8,10,16,16): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-9, 9, 18, 18), door_c.darkened(0.2))
	draw_rect(Rect2(-8, 10, 16, 16), door_c)
	draw_line(Vector2(-9, 9), Vector2(9, 9), ink, 1.5)
	draw_line(Vector2(-9, 27), Vector2(9, 27), ink, 1.5)
	draw_circle(Vector2(4, 18), 1.8, gold)


## Weaponsmith (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding weaponsmith branch — brown workshop block
## (#8d6e63) with a dark roof band (#5d4037), a steel anvil prop (#37474f)
## on the front wall, a door, and a 'SMITH' pill label. Race-independent in
## the HTML too, so the faction color is unused. Replaces the generic
## box+roof. ASCII-only label via ThemeDB.fallback_font (iPhone tofu rule).
func _weaponsmith() -> void:
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var body := Color(0.553, 0.431, 0.388)   # HTML #8d6e63
	var roof_c := Color(0.365, 0.251, 0.216) # HTML #5d4037
	var steel := Color(0.216, 0.278, 0.310)  # HTML #37474f
	var gold := Color(1.0, 0.835, 0.310)     # HTML #ffd54f
	# Main block (HTML block(-30,-10,60,36, r=4)): dark outline + brown
	# body + the soft top highlight block() adds.
	draw_rect(Rect2(-30, -10, 60, 36), ink)
	draw_rect(Rect2(-28, -8, 56, 32), body)
	draw_rect(Rect2(-27, -6, 54, 6), Color(1, 1, 1, 0.14))
	# Dark roof band (HTML fillRect(-32,-18,64,10) #5d4037).
	draw_rect(Rect2(-32, -18, 64, 10), ink)
	draw_rect(Rect2(-31, -17, 62, 8), roof_c)
	# Anvil prop on the front wall (HTML fillRect(-8,4,16,8) #37474f).
	draw_rect(Rect2(-9, 3, 18, 10), ink)
	draw_rect(Rect2(-8, 4, 16, 8), steel)
	draw_rect(Rect2(-11, 4, 22, 3), steel.darkened(0.2))
	# Door (HTML door(-8,12,16,14): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-9, 11, 18, 16), ink)
	draw_rect(Rect2(-8, 12, 16, 14), door_c)
	draw_circle(Vector2(4, 19), 1.8, gold)
	# 'SMITH' pill label (HTML label(): dark pill + #fffde7 text).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("SMITH", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_rect(Rect2(-tw * 0.5 - 5, -32, tw + 10, 12), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(-tw * 0.5, -24.0), "SMITH",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Shooting range (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding shooting_range branch — gravel range pad with ink
## edge and deterministic speckle, a rear earth berm with sandbags, 4 firing
## lanes (dashed center lines, timber target butts with painted straw-boss
## rings, roofed firing stalls, ammo crates), and a range flag in the faction
## color with a 'RANGE' pill label. All coords are the HTML's with a uniform
## 0.36 scale (HTML hw=172.8px would swallow a screen tile; the layout and
## ratios are preserved). Race-independent except the flag pennant, which
## uses RACES color in HTML = the faction color here. Replaces the generic
## box+roof. ASCII-only label via ThemeDB.fallback_font (iPhone tofu rule).
func _shooting_range(c: Color) -> void:
	var ink := Color(0.102, 0.071, 0.039)     # HTML #1a120a
	var k := 0.36                            # uniform HTML->Godot scale
	var hw := 172.8 * k
	var gravel := Color(0.553, 0.482, 0.408) # HTML #8d7b68
	var berm := Color(0.427, 0.357, 0.271)   # HTML #6d5b45
	var sand := Color(0.490, 0.416, 0.322)   # HTML #7d6a52
	var timber := Color(0.365, 0.251, 0.216) # HTML #5d4037
	var straw := Color(0.843, 0.725, 0.541)  # HTML #d7b98a
	var cream := Color(0.937, 0.922, 0.914)   # HTML #efebe9
	var bull := Color(0.776, 0.157, 0.157)    # HTML #c62828
	var post := Color(0.306, 0.204, 0.180)   # HTML #4e342e
	var crate := Color(0.427, 0.298, 0.255)   # HTML #6d4c41
	# Gravel pad, inked edge.
	draw_rect(Rect2(-hw, -26.0 * k, hw * 2.0, 64.0 * k), gravel)
	draw_line(Vector2(-hw, -26.0 * k), Vector2(hw, -26.0 * k), ink, 2.4)
	draw_line(Vector2(-hw, 38.0 * k), Vector2(hw, 38.0 * k), ink, 2.4)
	draw_line(Vector2(-hw, -26.0 * k), Vector2(-hw, 38.0 * k), ink, 2.4)
	draw_line(Vector2(hw, -26.0 * k), Vector2(hw, 38.0 * k), ink, 2.4)
	# Deterministic gravel speckle (HTML (gx*7+gy*13)%5 < 2).
	var gx := -hw + 8.0 * k
	while gx < hw - 4.0 * k:
		var gy := -20.0 * k
		while gy < 32.0 * k:
			if (fmod(gx / k * 7.0 + gy / k * 13.0, 5.0)) < 2.0:
				draw_rect(Rect2(gx, gy, 3.0 * k, 2.0 * k),
					Color(0, 0, 0, 0.12))
			gy += 12.0 * k
		gx += 14.0 * k
	# Rear safety berm (earth mound) with sandbags.
	draw_rect(Rect2(-hw, -46.0 * k, hw * 2.0, 24.0 * k), berm.darkened(0.2))
	draw_rect(Rect2(-hw + 1.0, -46.0 * k + 1.0, hw * 2.0 - 2.0,
		24.0 * k - 2.0), berm)
	var sx := -hw + 10.0 * k
	while sx < hw - 10.0 * k:
		draw_rect(Rect2(sx, -42.0 * k, 22.0 * k, 14.0 * k), sand.darkened(0.2))
		draw_rect(Rect2(sx + 1.0, -42.0 * k + 1.0, 22.0 * k - 2.0,
			14.0 * k - 2.0), sand)
		sx += 26.0 * k
	# 4 lanes: firing stall + lane + timber target butt.
	for i in range(4):
		var lx := -96.0 * k * 1.35 + float(i) * 96.0 * k * 0.9
		# Dashed lane center line (HTML setLineDash [6,5]).
		var ly := -20.0 * k
		while ly < 18.0 * k:
			draw_line(Vector2(lx, ly), Vector2(lx, minf(ly + 6.0 * k,
				18.0 * k)), Color(1, 1, 1, 0.35), 2.0)
			ly += 11.0 * k
		# Target butt: timber frame + straw boss with painted rings.
		draw_rect(Rect2(lx - 13.0 * k, -38.0 * k, 26.0 * k, 8.0 * k),
			timber.darkened(0.2))
		draw_rect(Rect2(lx - 12.0 * k, -37.0 * k, 24.0 * k, 6.0 * k), timber)
		draw_circle(Vector2(lx, -22.0 * k), 11.0 * k, straw.darkened(0.2))
		draw_circle(Vector2(lx, -22.0 * k), 10.0 * k, straw)
		draw_circle(Vector2(lx, -22.0 * k), 7.5 * k, cream)
		draw_circle(Vector2(lx, -22.0 * k), 4.5 * k, bull)
		draw_circle(Vector2(lx, -22.0 * k), 2.0 * k, ink)
		# Firing stall: posts + sloped range roof in faction color.
		draw_rect(Rect2(lx - 14.0 * k, 8.0 * k, 4.0 * k, 22.0 * k),
			post.darkened(0.2))
		draw_rect(Rect2(lx + 10.0 * k, 8.0 * k, 4.0 * k, 22.0 * k),
			post.darkened(0.2))
		draw_colored_polygon(PackedVector2Array([
			Vector2(lx - 18.0 * k, 8.0 * k), Vector2(lx, -4.0 * k),
			Vector2(lx + 18.0 * k, 8.0 * k)]), c.lightened(0.25))
		draw_polyline(PackedVector2Array([
			Vector2(lx - 18.0 * k, 8.0 * k), Vector2(lx, -4.0 * k),
			Vector2(lx + 18.0 * k, 8.0 * k), Vector2(lx - 18.0 * k,
			8.0 * k)]), ink, 1.8)
		# Ammo crate.
		draw_rect(Rect2(lx + 14.0 * k, 16.0 * k, 12.0 * k, 9.0 * k),
			crate.darkened(0.2))
		draw_rect(Rect2(lx + 14.5 * k, 16.5 * k, 11.0 * k, 8.0 * k), crate)
	# Range flag in faction color (HTML RACES[this.race].color).
	draw_rect(Rect2(hw - 14.0 * k, -58.0 * k, 4.0 * k, 26.0 * k),
		post.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([
		Vector2(hw - 10.0 * k, -58.0 * k), Vector2(hw + 6.0 * k, -52.0 * k),
		Vector2(hw - 10.0 * k, -46.0 * k)]), c)
	# 'RANGE' pill label (HTML label('RANGE', -64)).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("RANGE", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_rect(Rect2(-tw * 0.5 - 5, -64.0 * k - 12, tw + 10, 12),
		Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(-tw * 0.5, -64.0 * k - 4.0), "RANGE",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Vehicle depot (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding vehicle_depot branch — wide steel-blue garage
## block (#546e7a) with a dark loading-bay band (#37474f), four bay windows
## (#90a4ae), and a 'DEPOT' pill label. Race-independent in the HTML too,
## so the faction color is unused. Replaces the generic box+roof.
## ASCII-only label via ThemeDB.fallback_font (iPhone tofu rule).
func _vehicle_depot() -> void:
	var ink := Color(0.102, 0.071, 0.039)     # HTML #1a120a
	var body := Color(0.329, 0.431, 0.478)    # HTML #546e7a
	var bay := Color(0.216, 0.278, 0.310)     # HTML #37474f
	var glass := Color(0.565, 0.643, 0.682)   # HTML #90a4ae
	# Main block (HTML block(-50,-12,100,40, r=4)): dark outline + steel
	# body + the soft top highlight block() adds.
	draw_rect(Rect2(-50, -12, 100, 40), ink)
	draw_rect(Rect2(-48, -10, 96, 36), body)
	draw_rect(Rect2(-47, -8, 94, 7), Color(1, 1, 1, 0.14))
	# Dark loading-bay band (HTML fillRect(-40,0,80,20) #37474f).
	draw_rect(Rect2(-40, 0, 80, 20), ink)
	draw_rect(Rect2(-39, 1, 78, 18), bay)
	# Four bay windows (HTML fillRect #90a4ae).
	for i in range(4):
		var wx := -36.0 + float(i) * 20.0
		draw_rect(Rect2(wx - 1, 3, 16, 14), ink)
		draw_rect(Rect2(wx, 4, 14, 12), glass)
		draw_line(Vector2(wx + 7, 4), Vector2(wx + 7, 16), ink, 1.2)
	# Door (garage side door; HTML draws none, but the other Godot arms
	# carry one and the doorway rect below is skipped for this type — a
	# visible door keeps the silhouette consistent).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-49, 8, 14, 18), ink)
	draw_rect(Rect2(-48, 9, 12, 16), door_c)
	# 'DEPOT' pill label (HTML label(): dark pill + #fffde7 text).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("DEPOT", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_rect(Rect2(-tw * 0.5 - 5, -30, tw + 10, 12), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(-tw * 0.5, -22.0), "DEPOT",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Windmill blades (4 arms) above the tower box.
func _blades(c: Color, r: float, angle_offset := 0.0) -> void:
	var hub := Vector2(0, -34.0)
	for a: int in range(4):
		var ang: float = a * PI / 2.0 + PI / 4.0 + angle_offset
		draw_line(hub, hub + Vector2(cos(ang), sin(ang)) * r, c, 3.0)
	draw_circle(hub, 4.0, c.darkened(0.2))


## Sawmill (graphics-hourly 2026-10-04): mill house + toothed circular saw
## blade mounted on the front wall + stacked log pile. Replaces the generic
## box+hole it shared with quarry/mine.
func _sawmill(c: Color) -> void:
	var s := 32.0
	_box(c, s)
	_roof(c, s, 10.0)
	# Circular saw blade: steel disc with teeth, dark hub. The teeth spin on
	# the quantized FX step (graphics-hourly 2026-10-07) so the mill reads
	# as cutting; the disc itself stays put so there's no seam.
	var hub := Vector2(10.0, 6.0)
	var r := 8.0
	var steel := Color(0.60, 0.63, 0.67)
	var rot: float = TAU * float(_fx_local_step()) / float(EATERY_FX_STEPS)
	for i in 12:
		var a: float = TAU * float(i) / 12.0 + rot
		draw_colored_polygon(PackedVector2Array([
			hub + Vector2(cos(a), sin(a)) * r,
			hub + Vector2(cos(a + TAU / 24.0), sin(a + TAU / 24.0)) * (r + 2.5),
			hub + Vector2(cos(a + TAU / 12.0), sin(a + TAU / 12.0)) * r,
		]), steel.darkened(0.12))
	draw_circle(hub, r, steel)
	draw_circle(hub, 2.5, Color(0.22, 0.22, 0.24))
	# Log pile stacked against the left wall.
	var bark := Color(0.40, 0.27, 0.15)
	var cut := Color(0.74, 0.57, 0.38)
	for i in 3:
		var lp := Vector2(-21.0, 10.0 - float(i) * 7.5)
		draw_circle(lp, 4.5, bark)
		draw_circle(lp, 3.0, cut)


## Quarry (graphics-hourly 2026-10-04): terraced open pit in rock grays with
## scattered chunks and a timber derrick. No building box, no doorway.
func _quarry() -> void:
	var rock_hi := Color(0.52, 0.50, 0.47)
	var rock := Color(0.42, 0.40, 0.38)
	var rock_lo := Color(0.30, 0.29, 0.28)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-18, -12), Vector2(18, -12),
		Vector2(13, -3), Vector2(-13, -3)]), rock_hi)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-13, -3), Vector2(13, -3),
		Vector2(9, 6), Vector2(-9, 6)]), rock)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-9, 6), Vector2(9, 6),
		Vector2(6, 14), Vector2(-6, 14)]), rock_lo)
	var chunk := Color(0.24, 0.23, 0.22)
	for p in [Vector2(-10, -7), Vector2(7, -6), Vector2(-5, 1),
			Vector2(8, 3), Vector2(0, 10)]:
		draw_circle(p, 2.5, chunk)
	# Timber derrick over the pit.
	var timber := Color(0.45, 0.32, 0.20)
	draw_line(Vector2(-15, -12), Vector2(-5, -30), timber, 3.0)
	draw_line(Vector2(15, -12), Vector2(5, -30), timber, 3.0)
	draw_line(Vector2(-5, -30), Vector2(5, -30), timber, 3.0)


## Mine (graphics-hourly 2026-10-04): headframe house + timber-framed shaft
## entrance (dark arched opening) + ore heap. Draws its own entrance, so
## _draw skips the generic doorway rect for this type.
func _mine(c: Color) -> void:
	var s := 32.0
	_box(c, s)
	_roof(c, s, 8.0)
	var timber := Color(0.45, 0.32, 0.20)
	var dark := Color(0.08, 0.07, 0.08)
	draw_rect(Rect2(-11, -4, 22, 4), timber)
	draw_rect(Rect2(-11, -4, 3.5, 20), timber)
	draw_rect(Rect2(7.5, -4, 3.5, 20), timber)
	draw_circle(Vector2(0, 0), 7.5, dark)
	draw_rect(Rect2(-7.5, 0, 15, 14), dark)
	# Ore heap beside the entrance.
	var ore := Color(0.55, 0.53, 0.50)
	draw_colored_polygon(PackedVector2Array([
		Vector2(16, 14), Vector2(28, 14), Vector2(22, 4)]), ore.darkened(0.2))
	draw_colored_polygon(PackedVector2Array([
		Vector2(19, 14), Vector2(26, 14), Vector2(22.5, 8)]), ore)


## Farm (graphics-hourly 2026-10-04): small farmhouse + tilled field with
## crop rows. Replaces the generic box+roof that read as "just a house".
func _farm(c: Color) -> void:
	# Farmhouse tucked upper-left.
	draw_rect(Rect2(-26, -20, 20, 16), c.darkened(0.4))
	draw_rect(Rect2(-23, -17, 14, 10), c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-28, -16), Vector2(-4, -16), Vector2(-16, -26)]),
		c.lightened(0.25))
	# Tilled soil plots with crop rows to the right and below.
	var soil := Color(0.36, 0.25, 0.15)
	var sprout := Color(0.35, 0.75, 0.30)
	# Graphics-hourly 2026-10-09: sprout tips sway on the quantized FX
	# cadence (_fx_step, driven by the _process farm gate above) so a
	# breeze visibly ripples across the rows. Static when _fx_step is -1
	# (never animated — blueprints render the scaffold arm instead).
	var n := 0
	for plot in [Rect2(-2, 2, 36, 9), Rect2(-2, 14, 36, 9)]:
		draw_rect(plot, soil.darkened(0.15))
		draw_rect(Rect2(plot.position.x + 2.0, plot.position.y + 2.0,
			plot.size.x - 4.0, plot.size.y - 4.0), soil)
		for i in 6:
			var x: float = plot.position.x + 6.0 + float(i) * 5.5
			var tip_sway := farm_sway_for(_fx_step, n)
			n += 1
			draw_line(Vector2(x, plot.position.y + 7.0),
				Vector2(x + tip_sway, plot.position.y + 3.0), sprout, 1.5)


## Fishing dock (graphics-hourly 2026-10-04): wooden pier on posts over
## water with plank seams and a moored boat. Replaces the two flat rects.
## Draws its own water, so _draw skips the generic doorway for this type.
func _fishing_dock(c: Color) -> void:
	var wood := Color(0.50, 0.36, 0.22)
	var wood_dark := Color(0.38, 0.26, 0.15)
	var water := Color(0.20, 0.35, 0.60)
	# Water under the pier with a foam edge (wide enough for the moored boat).
	draw_rect(Rect2(-26, 8, 68, 12), water)
	draw_line(Vector2(-26, 8), Vector2(42, 8),
		Color(0.75, 0.85, 0.95, 0.8), 1.5)
	# Pier deck on posts.
	draw_rect(Rect2(-20, -6, 40, 10), wood_dark)
	draw_rect(Rect2(-20, -6, 40, 8), wood)
	for i in 6:
		var x: float = -20.0 + 4.0 + float(i) * 6.4
		draw_line(Vector2(x, -6), Vector2(x, 2), wood_dark, 1.0)
	for px in [-16.0, 16.0]:
		draw_rect(Rect2(px - 2.0, 2, 4, 12), wood_dark)
	# Moored boat alongside the pier.
	draw_colored_polygon(PackedVector2Array([
		Vector2(24, 10), Vector2(38, 10),
		Vector2(34, 17), Vector2(28, 17)]), wood)
	draw_line(Vector2(31, 10), Vector2(31, 2), wood_dark, 2.0)
	# Faction pennant on a pole at the pier's far end.
	draw_line(Vector2(-18, -6), Vector2(-18, -18), wood_dark, 2.0)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-18, -18), Vector2(-8, -15), Vector2(-18, -12)]), c)


## Fire station (wake routine 2026-10-04): port of the HTML's procedural
## fire_station (fix79 drawBuilding): red block, dark-red overhanging roof
## band, two dark garage bays, gold 'FIRE' label. Replaces the generic
## box+red-stripe that read as "just a house". ASCII-only label — no
## emoji/glyphs, so no iPhone tofu (Jeremy 2026-10-03).
func _fire_station(_c: Color) -> void:
	var red := Color(0.937, 0.325, 0.314)    # HTML #ef5350
	var roof := Color(0.718, 0.110, 0.110)   # HTML #b71c1c
	var dark := Color(0.129, 0.129, 0.129)   # HTML #212121
	var gold := Color(1.0, 0.835, 0.310)     # HTML #ffd54f
	# Main block (HTML block 80x44 at 0.85 scale).
	draw_rect(Rect2(-34, -12, 68, 37), red.darkened(0.15))
	draw_rect(Rect2(-32, -10, 64, 33), red)
	# Overhanging roof band.
	draw_rect(Rect2(-36, -19, 72, 10), roof.darkened(0.1))
	draw_rect(Rect2(-36, -19, 72, 8), roof)
	# Two garage bays.
	for bx in [-24.0, 3.0]:
		draw_rect(Rect2(bx - 1.0, 2.0, 22.0, 21.0), dark.darkened(0.2))
		draw_rect(Rect2(bx, 3.0, 20.0, 19.0), dark)
	# Gold 'FIRE' label centered above the bays (HTML fillText at (0,-6)).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("FIRE", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 9).x
	draw_string(font, Vector2(-tw * 0.5, -3.0), "FIRE",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, gold)


## Wagon dealership (P3 roads/vehicles order): showroom block with a big
## "WAGONS" sign, a display cart silhouette on the forecourt, and wooden
## hitching posts marking the parking lot. ASCII-only label — no
## emoji/glyphs, so no iPhone tofu (Jeremy 2026-10-03).
func _dealership(_c: Color) -> void:
	var timber := Color(0.55, 0.38, 0.22)   # warm wood showroom
	var timber_dark := Color(0.40, 0.27, 0.15)
	var roof := Color(0.30, 0.42, 0.62)     # slate-blue canopy roof
	var cream := Color(0.96, 0.90, 0.76)
	var iron := Color(0.25, 0.25, 0.28)
	# Showroom block.
	draw_rect(Rect2(-36, -14, 72, 40), timber_dark)
	draw_rect(Rect2(-34, -12, 68, 36), timber)
	# Canopy roof overhang.
	draw_rect(Rect2(-40, -22, 80, 12), roof.darkened(0.15))
	draw_rect(Rect2(-40, -22, 80, 9), roof)
	# Display window + door.
	draw_rect(Rect2(-28, -4, 22, 18), cream.darkened(0.25))
	draw_rect(Rect2(-28, -4, 22, 16), cream)
	draw_rect(Rect2(6, -2, 12, 28), timber_dark)
	# Gold 'WAGONS' sign on the canopy (HTML fillText parity).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("WAGONS", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 9).x
	draw_string(font, Vector2(-tw * 0.5, -14.0), "WAGONS",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(1.0, 0.835, 0.310))
	# Display cart silhouette on the forecourt: bed, two big wheels, shafts.
	var cx := 44.0
	draw_rect(Rect2(cx - 14, 8, 28, 10), timber_dark)
	draw_rect(Rect2(cx - 14, 8, 28, 8), timber)
	draw_circle(Vector2(cx - 9, 22), 6.0, iron)
	draw_circle(Vector2(cx + 9, 22), 6.0, iron)
	draw_circle(Vector2(cx - 9, 22), 2.5, timber)
	draw_circle(Vector2(cx + 9, 22), 2.5, timber)
	draw_line(Vector2(cx + 14, 10), Vector2(cx + 26, 4), timber_dark, 2.0)
	# Hitching posts marking the lot's front row.
	for px in [-30.0, 0.0, 30.0]:
		draw_line(Vector2(px, 34), Vector2(px, 24), timber_dark, 3.0)
		draw_circle(Vector2(px, 23), 2.5, iron)


## Clinic (wake routine 2026-10-04): ported verbatim from fix79's procedural
## drawBuilding clinic branch — white rounded block, red-cross sign on the
## roof, two window panes, a door with a brass knob, and a 'CLINIC' pill
## label. Replaces the generic box+roof+white-cross it used before. No
## glyphs or emoji — the label is ASCII-only via ThemeDB.fallback_font
## (iPhone tofu rule). Colors are the HTML's hex values, not the faction
## color: the HTML draws the clinic white for every race.
func _clinic() -> void:
	var white := Color(0.925, 0.937, 0.945)  # HTML #eceff1
	var red := Color(0.898, 0.224, 0.208)    # HTML #e53935
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	# Rounded main block (HTML block 60x36 at (-30,-10), radius 5): dark
	# outline + white body + the soft top highlight the HTML's block() adds.
	draw_rect(Rect2(-30, -10, 60, 36), ink)
	draw_rect(Rect2(-28, -8, 56, 32), white)
	draw_rect(Rect2(-25, -6, 50, 6), Color(1, 1, 1, 0.14))
	# Red cross sign on the roof (HTML #e53935 fillRects).
	draw_rect(Rect2(-7, -29, 14, 30), red.darkened(0.12))
	draw_rect(Rect2(-6, -28, 12, 28), red)
	draw_rect(Rect2(-15, -21, 30, 14), red.darkened(0.12))
	draw_rect(Rect2(-14, -20, 28, 12), red)
	# Two window panes (HTML windowPane: dark frame, blue glass, glint,
	# center mullion).
	for wx: float in [-20.0, 10.0]:
		draw_rect(Rect2(wx - 1, -3, 12, 12), ink)
		draw_rect(Rect2(wx, -2, 10, 10), Color(0.506, 0.831, 0.980))  # #81d4fa
		draw_rect(Rect2(wx + 1, -1, 3.5, 3.0), Color(1, 1, 1, 0.45))
		draw_line(Vector2(wx + 5, -2), Vector2(wx + 5, 8), ink, 1.2)
	# Door (HTML door(): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-9, 9, 18, 18), door_c.darkened(0.2))
	draw_rect(Rect2(-8, 10, 16, 16), door_c)
	draw_line(Vector2(-9, 9), Vector2(9, 9), ink, 1.5)
	draw_line(Vector2(-9, 27), Vector2(9, 27), ink, 1.5)
	draw_circle(Vector2(4, 18), 1.8, Color(1.0, 0.835, 0.310))  # #ffd54f knob
	# 'CLINIC' pill label above (HTML label(): dark pill + #fffde7 text).
	draw_rect(Rect2(-28, -45, 56, 13), Color(0, 0, 0, 0.45))
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("CLINIC", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_string(font, Vector2(-tw * 0.5, -33.0), "CLINIC",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Bathhouse (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding bathhouse branch — wide block in the faction
## color (HTML P.wall), tri-roof, two window panes, a door, and a
## 'BATHHOUSE' pill label. Replaces the generic box+roof it used before.
## Label pill is sized to the text (the HTML's fixed 56px pill would clip
## the 9-char word); ASCII-only via ThemeDB.fallback_font (iPhone tofu rule).
func _bathhouse(c: Color, p_label := "BATHHOUSE") -> void:
	var ink := Color(0.102, 0.071, 0.039)  # HTML #1a120a
	var glass := Color(0.506, 0.831, 0.980)  # HTML #81d4fa
	var gold := Color(1.0, 0.835, 0.310)  # HTML #ffd54f
	# Main block (HTML block 68x40 at (-34,-12), radius 5): dark outline +
	# faction-color body + the soft top highlight block() adds.
	draw_rect(Rect2(-34, -12, 68, 40), c.darkened(0.4))
	draw_rect(Rect2(-32, -10, 64, 36), c)
	draw_rect(Rect2(-31, -8, 58, 7), Color(1, 1, 1, 0.14))
	# Tri-roof (HTML triRoof(-40,-12, 0,-38, 40,-12, P.roof)).
	draw_colored_polygon(PackedVector2Array([
		Vector2(-40, -12), Vector2(0, -38), Vector2(40, -12)]),
		c.lightened(0.25))
	draw_polyline(PackedVector2Array([
		Vector2(-40, -12), Vector2(0, -38), Vector2(40, -12),
		Vector2(-40, -12)]), ink, 2.4)
	# Two window panes (HTML windowPane: dark frame, blue glass, glint,
	# center mullion).
	for wx: float in [-20.0, 10.0]:
		draw_rect(Rect2(wx - 1, -5, 12, 12), ink)
		draw_rect(Rect2(wx, -4, 10, 10), glass)
		draw_rect(Rect2(wx + 1, -3, 3.5, 3.0), Color(1, 1, 1, 0.45))
		draw_line(Vector2(wx + 5, -4), Vector2(wx + 5, 6), ink, 1.2)
	# Door (HTML door(-8,10,16,18): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-8, 10, 16, 18), door_c.darkened(0.2))
	draw_rect(Rect2(-7, 11, 14, 16), door_c)
	draw_circle(Vector2(4, 19), 1.8, gold)
	# 'BATHHOUSE' pill label (HTML label(): dark pill + #fffde7 text).
	# hotel/inn share this exact HTML branch; only the label changes
	# (label(t.toUpperCase())).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size(p_label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_rect(Rect2(-tw * 0.5 - 5, -52, tw + 10, 12), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(-tw * 0.5, -44.0), p_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Guard house (graphics-hourly 2026-10-04): ported from fix79's C44
## procedural fallback branch — stone-grey hut (#9aa5b1, race-independent in
## the HTML too), tri-roof in the faction color, a red shield emblem with a
## gold sword bar, two window panes, a door, and a 'GUARD' pill label.
## Replaces the generic box+roof. (HTML C61 prefers a faction sprite via
## bldGuardHouseSprite61, but no guard-house sprite art exists in the Godot
## assets, so the procedural fallback is the parity target.) Shield points
## are sampled from the HTML's quadratic curves; the HTML draws the door
## over the shield, so this keeps that draw order. ASCII-only label via
## ThemeDB.fallback_font (iPhone tofu rule).
func _guard_house(c: Color) -> void:
	var ink := Color(0.102, 0.071, 0.039)  # HTML #1a120a
	var stone := Color(0.604, 0.647, 0.694)  # HTML #9aa5b1
	var glass := Color(0.506, 0.831, 0.980)  # HTML #81d4fa
	var shield := Color(0.776, 0.157, 0.157)  # HTML #c62828
	var gold := Color(1.0, 0.835, 0.310)  # HTML #ffd54f
	# Stone block (HTML block 64x38 at (-32,-12), radius 5).
	draw_rect(Rect2(-32, -12, 64, 38), stone.darkened(0.35))
	draw_rect(Rect2(-30, -10, 60, 34), stone)
	draw_rect(Rect2(-29, -8, 58, 6), Color(1, 1, 1, 0.14))
	# Tri-roof (HTML triRoof(-38,-12, 0,-38, 38,-12, P.roof)).
	draw_colored_polygon(PackedVector2Array([
		Vector2(-38, -12), Vector2(0, -38), Vector2(38, -12)]),
		c.lightened(0.25))
	draw_polyline(PackedVector2Array([
		Vector2(-38, -12), Vector2(0, -38), Vector2(38, -12),
		Vector2(-38, -12)]), ink, 2.4)
	# Shield emblem (HTML: shield path via quadraticCurveTo, ink stroke 2,
	# then a gold sword bar at (-2,2,4,10)).
	var pts := PackedVector2Array([
		Vector2(0, -6), Vector2(12, 0), Vector2(12, 10),
		Vector2(11.25, 13.9), Vector2(9, 17.5), Vector2(5.25, 20.9),
		Vector2(0, 24),
		Vector2(-5.25, 20.9), Vector2(-9, 17.5), Vector2(-11.25, 13.9),
		Vector2(-12, 10), Vector2(-12, 0)])
	draw_colored_polygon(pts, shield)
	var ring := pts
	ring.append(pts[0])
	draw_polyline(ring, ink, 2.0)
	draw_rect(Rect2(-2, 2, 4, 10), gold)
	# Two window panes (HTML windowPane(-24,-4,10,9) and (14,-4,10,9)).
	for wx: float in [-24.0, 14.0]:
		draw_rect(Rect2(wx - 1, -5, 12, 11), ink)
		draw_rect(Rect2(wx, -4, 10, 9), glass)
		draw_rect(Rect2(wx + 1, -3, 3.5, 2.7), Color(1, 1, 1, 0.45))
		draw_line(Vector2(wx + 5, -4), Vector2(wx + 5, 5), ink, 1.2)
	# Door (HTML door(-7,10,14,16): knob at (x+w-4, y+h*0.5)).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-7, 10, 14, 16), door_c.darkened(0.2))
	draw_rect(Rect2(-6, 11, 12, 14), door_c)
	draw_circle(Vector2(3, 18), 1.8, gold)
	# 'GUARD' pill label (HTML label(): dark pill + #fffde7 text).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("GUARD", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_rect(Rect2(-tw * 0.5 - 5, -54, tw + 10, 12), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(-tw * 0.5, -46.0), "GUARD",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## War hut (graphics-hourly 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding war_hut branch — the ogre barracks: wide block
## in the faction color, tri-roof, skull-topped poles flanking the front,
## a double door, and a 'WAR HUT' pill label. Replaces the generic
## box+roof. The HTML's "skull poles" are plain bone circles; thin dark
## poles mount them on the block top, and the skulls get simple eye sockets
## so they read as skulls at game scale. ASCII-only label via
## ThemeDB.fallback_font (iPhone tofu rule).
func _war_hut(c: Color) -> void:
	var ink := Color(0.102, 0.071, 0.039)  # HTML #1a120a
	var bone := Color(0.937, 0.922, 0.914)  # HTML #efebe9
	var gold := Color(1.0, 0.835, 0.310)  # HTML #ffd54f
	# Main block (HTML block 88x44 at (-44,-14), radius 4).
	draw_rect(Rect2(-44, -14, 88, 44), c.darkened(0.4))
	draw_rect(Rect2(-42, -12, 84, 40), c)
	draw_rect(Rect2(-41, -10, 82, 7), Color(1, 1, 1, 0.14))
	# Tri-roof (HTML triRoof(-50,-14, 0,-50, 50,-14, P.roof)).
	draw_colored_polygon(PackedVector2Array([
		Vector2(-50, -14), Vector2(0, -50), Vector2(50, -14)]),
		c.lightened(0.25))
	draw_polyline(PackedVector2Array([
		Vector2(-50, -14), Vector2(0, -50), Vector2(50, -14),
		Vector2(-50, -14)]), ink, 2.4)
	# Skull poles (HTML: #efebe9 skulls at (+-30,-28)).
	for px: float in [-30.0, 30.0]:
		draw_line(Vector2(px, -24), Vector2(px, -14), ink, 2.0)
		draw_circle(Vector2(px, -28), 5.0, ink)
		draw_circle(Vector2(px, -28), 4.0, bone)
		draw_circle(Vector2(px - 1.6, -29), 1.1, ink)
		draw_circle(Vector2(px + 1.6, -29), 1.1, ink)
	# Double door (HTML door(-10,10,20,20)): knob at (x+w-4, y+h*0.5).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-10, 10, 20, 20), door_c.darkened(0.2))
	draw_rect(Rect2(-9, 11, 18, 18), door_c)
	draw_line(Vector2(0, 11), Vector2(0, 29), ink, 1.5)
	draw_circle(Vector2(6, 20), 1.8, gold)
	# 'WAR HUT' pill label (HTML label(): dark pill + #fffde7 text).
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size("WAR HUT", HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_rect(Rect2(-tw * 0.5 - 5, -66, tw + 10, 12), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(-tw * 0.5, -58.0), "WAR HUT",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Mage spire (graphics-hourly 2026-10-04): tapering three-tier tower with a
## tall conical roof and an arcane crystal on top. Replaces box+tall roof.
## Static art — NightGlow already handles the night lighting, so no
## animation cost (follows the windmill lesson: only animate when cheap).
func _mage_spire(c: Color) -> void:
	var tiers: Array = [
		Rect2(-16, -8, 32, 24), Rect2(-12, -26, 24, 20),
		Rect2(-8, -42, 16, 18)]
	for r in tiers:
		draw_rect(r, c.darkened(0.4))
		draw_rect(Rect2(r.position.x + 2.5, r.position.y + 2.5,
			r.size.x - 5.0, r.size.y - 5.0), c)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-11, -42), Vector2(11, -42), Vector2(0, -60)]),
		c.lightened(0.25))
	# Arcane crystal: violet diamond with a lighter facet + white glint.
	var gem := Color(0.55, 0.35, 0.90)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -70), Vector2(6, -62),
		Vector2(0, -54), Vector2(-6, -62)]), gem)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -70), Vector2(3, -62),
		Vector2(0, -54), Vector2(-3, -62)]), gem.lightened(0.3))
	draw_circle(Vector2(-1.5, -64), 1.5, Color(1, 1, 1, 0.9))


## Jeremy 2026-10-04: THE NASTY MONASTERY — stone chapel with a bell
## tower and arched doorway. Tasteful. The screaming comes free.
func _monastery(c: Color) -> void:
	var ink := Color(0.102, 0.071, 0.039)
	var stone := Color(0.72, 0.68, 0.62)
	var stone_d := stone.darkened(0.25)
	# Main chapel block.
	draw_rect(Rect2(-26, -6, 52, 30), ink)
	draw_rect(Rect2(-24, -4, 48, 26), stone)
	draw_rect(Rect2(-22, -2, 44, 5), Color(1, 1, 1, 0.12))
	# Pitched roof.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-28, -6), Vector2(28, -6), Vector2(0, -24)]),
		stone_d)
	draw_colored_polygon(PackedVector2Array([
		Vector2(-24, -8), Vector2(24, -8), Vector2(0, -22)]),
		stone_d.lightened(0.12))
	# Bell tower on the right.
	draw_rect(Rect2(14, -40, 18, 64), ink)
	draw_rect(Rect2(16, -38, 14, 60), stone)
	draw_rect(Rect2(12, -48, 22, 10), ink)
	draw_colored_polygon(PackedVector2Array([
		Vector2(12, -48), Vector2(34, -48), Vector2(23, -58)]),
		stone_d)
	# Belfry opening with the bell.
	draw_rect(Rect2(19, -34, 8, 12), ink)
	draw_circle(Vector2(23, -26), 3.2, Color(0.85, 0.70, 0.30))
	draw_circle(Vector2(22, -27), 1.2, Color(1, 1, 1, 0.5))
	# Tall arched windows on the chapel.
	for wx: float in [-16.0, -4.0]:
		draw_rect(Rect2(wx - 1, -1, 9, 16), ink)
		draw_rect(Rect2(wx, 0, 7, 14), Color(0.35, 0.45, 0.75))
		draw_circle(Vector2(wx + 3.5, 0), 3.5, Color(0.35, 0.45, 0.75))
		draw_circle(Vector2(wx + 2.5, -1), 1.2, Color(1, 1, 1, 0.45))
	# Arched doorway.
	draw_rect(Rect2(-6, 10, 12, 14), ink)
	draw_rect(Rect2(-5, 11, 10, 13), Color(0.20, 0.13, 0.10))
	draw_circle(Vector2(0, 11), 5.0, Color(0.20, 0.13, 0.10))


## Well (wake routine 2026-10-04): stone-rimmed well with wooden posts,
## crossbar, rope + hanging bucket, and a small peaked roof. Replaces the
## primitive two-circles-and-three-lines silhouette. Static art — no
## animation cost. ASCII-free; no glyphs (iPhone tofu rule).
func _well(c: Color) -> void:
	var wood := Color(0.50, 0.36, 0.22)
	var wood_dark := Color(0.38, 0.26, 0.15)
	var stone := Color(0.55, 0.55, 0.58)
	var water := Color(0.20, 0.35, 0.60)
	var ctr := Vector2(0, -4)
	# Stone rim: dark outer, light ring, dark inner, water opening.
	draw_circle(ctr, 10.0, stone.darkened(0.35))
	draw_circle(ctr, 8.5, stone)
	draw_circle(ctr, 6.5, stone.darkened(0.25))
	draw_circle(ctr, 5.0, water)
	# Baked glint on the water + mortar dashes on the rim.
	draw_circle(ctr + Vector2(-2.0, -2.0), 1.4, Color(0.65, 0.80, 0.95, 0.85))
	for i in 8:
		var a0: float = TAU * float(i) / 8.0
		draw_arc(ctr, 9.2, a0, a0 + 0.35, 8, stone.darkened(0.5), 1.5)
	# Wooden posts + crossbar.
	draw_line(Vector2(-8, -4), Vector2(-8, -22), wood_dark, 3.0)
	draw_line(Vector2(8, -4), Vector2(8, -22), wood_dark, 3.0)
	draw_line(Vector2(-11, -21), Vector2(11, -21), wood, 2.5)
	# Peaked roof in the faction color.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-12, -19), Vector2(12, -19), Vector2(0, -30)]),
		c.darkened(0.3))
	draw_line(Vector2(-12, -19), Vector2(0, -30), c.darkened(0.5), 1.5)
	draw_line(Vector2(12, -19), Vector2(0, -30), c.darkened(0.5), 1.5)
	# Rope + bucket hanging over the water.
	draw_line(Vector2(0, -21), Vector2(0, -10), Color(0.25, 0.18, 0.12), 1.5)
	draw_rect(Rect2(-2.5, -10, 5, 4.5), wood_dark)
	draw_rect(Rect2(-2.5, -10, 5, 1.0), wood)


func _draw_progress_ring() -> void:
	var s := _size_for(btype)
	var p: float = clampf(float(record.get("progress", 0.0)), 0.0, 1.0)
	draw_arc(Vector2.ZERO, s * 0.9, -PI / 2, -PI / 2 + TAU * p, 24,
		Color(0.3, 1.0, 0.4, 0.95), 4.0)
	draw_arc(Vector2.ZERO, s * 0.9, 0.0, TAU, 24,
		Color(1, 1, 1, 0.25), 1.5)


## 2026-10-06: cel-shaded 3D wall (WallMesh3D). Replaces the flat
## wall_strip sprite with a real wall volume — box body, crenellated
## merlons, stepped cel bands, ink outlines — oriented along the
## segment's wall_angle. Damage states come from hp/max_hp; blueprints
## grow upward with progress. Zero sim change: purely visual.
func _draw_wall_3d() -> void:
	var complete: bool = bool(record.get("complete", true))
	# Sun-driven blob shadow under the footprint (drawn first = under art).
	# Sized to the segment length (44px + joint overlap).
	Shadows.draw_blob(self, _size_for("wall") * 1.6,
		0.5 if not complete else 1.0)
	var angle: float = float(record.get("wall_angle", 0.0))
	var sun: Dictionary = Shadows.current()
	if not complete:
		# Blueprint ghost grows upward as construction progresses.
		var p: float = clampf(float(record.get("progress", 0.0)), 0.0, 1.0)
		WallMesh.draw_wall(self, angle, 1.0, maxf(p, 0.06), 0.45,
			building_id, sun)
		_draw_wall_scaffold(angle)
		_draw_progress_ring()
		return
	var frac := WallMesh.hp_frac(float(record.get("hp", 900.0)),
		float(record.get("max_hp", 900.0)))
	WallMesh.draw_wall(self, angle, frac, 1.0, 1.0, building_id, sun)


## Blueprint scaffolding for walls: a timber rail + X-brace running along
## the segment direction (the generic _draw_scaffold square is sized for
## compact buildings, not 44px wall runs).
func _draw_wall_scaffold(angle: float) -> void:
	var d := Vector2(cos(angle), sin(angle))
	var a := -d * 26.0
	var b := d * 26.0
	var wood := Color(0.45, 0.32, 0.20, 0.8)
	draw_line(a + Vector2(0, -30), b + Vector2(0, -30), wood, 2.0)
	draw_line(a, b + Vector2(0, -30), wood, 1.6)
	draw_line(b, a + Vector2(0, -30), wood, 1.6)


## Translucent scaffolding + progress ring for incomplete blueprints
## (programmer-art types only). Drawn by _draw() with the ground transform
## applied; the progress ring is drawn separately at the ground point.
## Completion-reveal dust (graphics-hourly 2026-10-08): expanding ground ring
## + six seeded dust puffs at the building's base while it rises. The ring is
## squashed to the isometric ground plane; puffs drift outward and shrink as
## the ring overtakes them. Pure ground FX — no text, no panels, no bubbles.
func _draw_reveal_dust() -> void:
	var fp := _size_for(btype)
	var k := reveal_k_for(_reveal_t)
	var dust := Color(0.82, 0.74, 0.60)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
	draw_arc(Vector2.ZERO, reveal_ring_radius_for(fp, k), 0.0, TAU, 32,
		Color(dust, reveal_ring_alpha_for(k)), 3.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var phase := float(absi(hash(building_id))) / 9223372036854775807.0 * TAU
	var pa := reveal_puff_alpha_for(k)
	var pr := reveal_puff_radius_for(fp, k)
	for i in range(6):
		draw_circle(reveal_puff_pos(i, fp, k, phase), pr, Color(dust, pa))


## P6 staged construction (Jeremy 2026-10-10): every building visibly
## passes through foundation -> frame -> walls -> roof/finish with
## distinct art per stage, instead of a single growing ghost. Driven by
## the sim's progress 0..1; pure visual, sim untouched. Walls keep their
## scaffold-arm blueprint style (_draw_wall_3d, untouched). Repair has no
## construction stage to walk back — only the damage ladder reverses.
static func construction_phase_for(progress: float) -> int:
	var p := clampf(progress, 0.0, 1.0)
	if p < 0.25:
		return 0  # foundation
	if p < 0.50:
		return 1  # frame
	if p < 0.75:
		return 2  # walls
	return 3      # roof/finish
## Test hook: construction phase last staged; -1 when complete / wall.
var _last_construction_phase := -1


## Staged construction art, ground-anchored (origin at the ground point,
## building rises into negative y). Deterministic plain shapes — no
## per-frame RNG, no allocation, cheap on iPhone. Called from both the
## sprite and programmer-art blueprint branches.
func _draw_construction_phase(phase: int, c: Color) -> void:
	_last_construction_phase = phase
	var s := _size_for(btype)
	var fh := s * 1.05  # frame height
	var wood := Color(0.45, 0.32, 0.20, 0.95)
	var wood_dark := Color(0.33, 0.23, 0.14, 0.95)
	var stone := Color(0.45, 0.44, 0.42, 0.95)
	var dirt := Color(0.35, 0.25, 0.16, 0.9)
	var hw := s * 0.45  # half footprint width
	match phase:
		0:
			# FOUNDATION: dug trench ring + corner stone footings + dirt piles.
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
			draw_arc(Vector2.ZERO, s * 0.62, 0.0, TAU, 40,
				Color(dirt, 0.85), 7.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			for cp in [Vector2(-s * 0.62, 0), Vector2(s * 0.62, 0),
					Vector2(0, -s * 0.34), Vector2(0, s * 0.34)]:
				draw_rect(Rect2(cp - Vector2(5, 4), Vector2(10, 8)), stone)
			draw_circle(Vector2(-s * 0.78, s * 0.10), 6.0, Color(dirt, 0.9))
			draw_circle(Vector2(s * 0.78, -s * 0.06), 5.0, Color(dirt, 0.9))
		1:
			# FRAME: timber skeleton over a fading trench.
			draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.55))
			draw_arc(Vector2.ZERO, s * 0.62, 0.0, TAU, 40,
				Color(dirt, 0.35), 5.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			var tops := [Vector2(-hw, -fh), Vector2(hw, -fh),
				Vector2(-hw * 0.7, -fh * 1.06), Vector2(hw * 0.7, -fh * 1.06)]
			var bases := [Vector2(-hw, 0), Vector2(hw, 0),
				Vector2(-hw * 0.7, -s * 0.06), Vector2(hw * 0.7, -s * 0.06)]
			for i in range(4):
				draw_line(bases[i], tops[i], wood, 4.0)
			# Top beams: front edge + back edge.
			draw_line(tops[0], tops[1], wood_dark, 4.0)
			draw_line(tops[2], tops[3], wood_dark, 4.0)
			draw_line(tops[0], tops[2], wood_dark, 3.0)
			draw_line(tops[1], tops[3], wood_dark, 3.0)
			# X-brace on the front face.
			draw_line(bases[0], tops[1], wood, 2.5)
			draw_line(bases[1], tops[0], wood, 2.5)
			# Plank pile waiting at the base.
			for i in range(3):
				draw_rect(Rect2(Vector2(hw * 0.9, -4.0 - float(i) * 5.0),
					Vector2(22, 4)), wood_dark)
		2:
			# WALLS: faction wall panels between the frame posts, scaffold
			# poles at the front corners, wall plate on top — no roof yet.
			var wall_c := c.darkened(0.35)
			for i in range(4):
				var bx := -hw + float(i) * (s * 0.9 / 3.0)
				draw_line(Vector2(bx, 0), Vector2(bx, -fh * 0.66), wood, 3.0)
			draw_rect(Rect2(-hw, -fh * 0.66, s * 0.9, fh * 0.66), wall_c)
			draw_line(Vector2(-hw, -fh * 0.66), Vector2(hw, -fh * 0.66),
				wood_dark, 4.0)
			# Side face hint for a touch of depth.
			var side := PackedVector2Array([Vector2(hw, -fh * 0.66),
				Vector2(hw + s * 0.16, -fh * 0.66 - s * 0.10),
				Vector2(hw + s * 0.16, -s * 0.10), Vector2(hw, 0.0)])
			draw_colored_polygon(side, wall_c.darkened(0.15))
			# Scaffold poles + crossbar at the front corners.
			for sx in [-hw - 8.0, hw + 8.0]:
				draw_line(Vector2(sx, 0), Vector2(sx, -fh * 0.8), wood, 3.0)
			draw_line(Vector2(-hw - 8.0, -fh * 0.8),
				Vector2(hw + 8.0, -fh * 0.8), wood, 2.5)
		_:
			# ROOF/FINISH: full walls, roof half-laid — rafters exposed on
			# the front slope, back slope finished.
			var wall_c := c.darkened(0.18)
			draw_rect(Rect2(-hw, -fh * 0.78, s * 0.9, fh * 0.78), wall_c)
			var side := PackedVector2Array([Vector2(hw, -fh * 0.78),
				Vector2(hw + s * 0.16, -fh * 0.78 - s * 0.10),
				Vector2(hw + s * 0.16, -s * 0.10), Vector2(hw, 0.0)])
			draw_colored_polygon(side, wall_c.darkened(0.15))
			# Ridge beam.
			draw_line(Vector2(-hw - 4.0, -fh * 0.78),
				Vector2(hw + s * 0.16 + 4.0, -fh * 0.78 - s * 0.10),
				wood_dark, 4.0)
			# Exposed rafters on the front slope.
			for i in range(4):
				var rx := -hw + 6.0 + float(i) * (s * 0.9 - 12.0) / 3.0
				draw_line(Vector2(rx, -fh * 0.78),
					Vector2(rx + s * 0.10, -fh * 1.02), wood, 2.5)
			# Half-laid roof slab over the left rafters.
			var slab := PackedVector2Array([
				Vector2(-hw - 2.0, -fh * 0.76),
				Vector2(-hw - 2.0 + s * 0.10, -fh * 1.0),
				Vector2(s * 0.05, -fh * 1.0),
				Vector2(s * 0.05, -fh * 0.76)])
			draw_colored_polygon(slab, Color(0.42, 0.24, 0.16, 0.98))


func _draw_scaffold(c: Color) -> void:
	var s := _size_for(btype)
	var ghost := Color(c.r, c.g, c.b, 0.35)
	draw_rect(Rect2(-s / 2, -s / 2, s, s), ghost)
	draw_line(Vector2(-s / 2, -s / 2), Vector2(s / 2, s / 2),
		Color(0.4, 0.3, 0.2, 0.7), 2.0)
	draw_line(Vector2(s / 2, -s / 2), Vector2(-s / 2, s / 2),
		Color(0.4, 0.3, 0.2, 0.7), 2.0)


## Pier (12h-systems-graphics 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding pier branch — wooden pier on piling posts with
## STILTWOOD76 stilt posts driven down into the water under the walkway,
## plank seams and a top highlight strip. Draws its own water tint, so
## _draw skips the generic doorway rect for this type. Replaces the generic
## box+roof it drew before.
func _pier() -> void:
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var post := Color(0.306, 0.204, 0.180)   # HTML #4e342e
	var deck := Color(0.553, 0.431, 0.388)   # HTML #8d6e63
	var seam := Color(0.365, 0.263, 0.216)   # HTML #5d4037
	var hi := Color(0.631, 0.533, 0.498)     # HTML #a1887f
	# Piling posts across the deck (HTML fillRect(px-4,-34,8,66) #4e342e).
	for px: float in [-34.0, -12.0, 12.0, 34.0]:
		draw_rect(Rect2(px - 4.0, -34.0, 8.0, 66.0), post)
		draw_rect(Rect2(px - 4.0, -34.0, 8.0, 66.0), ink, false, 2.0)
	# Stilt posts driven into the water under the walkway, with the HTML's
	# water tint and a waterline glint.
	for spx: float in [-34.0, -12.0, 12.0, 34.0]:
		draw_rect(Rect2(spx - 5.0, 12.0, 10.0, 34.0), post)
		draw_rect(Rect2(spx - 5.0, 24.0, 10.0, 22.0),
			Color(0.078, 0.235, 0.392, 0.55))  # HTML rgba(20,60,100,0.55)
		draw_rect(Rect2(spx - 5.0, 12.0, 10.0, 34.0), ink, false, 1.8)
		draw_line(Vector2(spx - 8.0, 24.0), Vector2(spx + 8.0, 24.0),
			Color(1, 1, 1, 0.38), 1.6)
	# Plank walkway (HTML fillRect(-42,-16,84,32) #8d6e63) with plank seams
	# every 12px and the soft top highlight.
	draw_rect(Rect2(-42.0, -16.0, 84.0, 32.0), deck)
	draw_rect(Rect2(-42.0, -16.0, 84.0, 32.0), ink, false, 2.5)
	for i in range(-36, 37, 12):
		var x := float(i)
		draw_line(Vector2(x, -16.0), Vector2(x, 16.0), seam, 1.5)
	draw_rect(Rect2(-42.0, -16.0, 84.0, 6.0), hi)


## Bridge segment (building-art fix 2026-10-06): ported verbatim from
## fix79's drawBridgeDeck (STILTWOOD76, Jeremy 2026-09-28) — a 2.5D
## stilted wooden walkway: plank deck on a timber slab, wooden
## post-and-rail railings on BOTH sides, and support stilts driven down
## INTO the water with submerged, water-tinted sections and waterline
## ripples. Segments auto-orient along neighboring segments (HTML
## bridgeNeighborAngle) — see _bridge_span_angle. Replaces the generic
## box+roof arm the type fell through to. No labels or glyphs of any
## kind (iPhone tofu rule is trivially satisfied). The arm draws fix79's
## own soft water shadow, so _draw skips the generic sun blob for
## complete bridges.
const BRIDGE_DECK_L := 78.0
const BRIDGE_DECK_W := 34.0
## Neighbor-scan cache for the span angle (HTML bridgeNeighborAngle
## parity): segments are chained, so the angle is stable; a 4 s TTL keeps
## the sibling scan off the _draw hot path (bridges are rare, but the
## scan is O(siblings) under the buildings root).
const BRIDGE_ANG_TTL_MS := 4000
var _bridge_ang := 0.0
var _bridge_ang_ms := -1


func _bridge() -> void:
	var anchor := Vector2(0.0, -float(DRAWN_GROUND_Y.get(btype, 0.0)))
	# HTML ctx.rotate(ang): rotate the whole deck about the segment
	# center so chained segments read as one continuous span.
	draw_set_transform(anchor, _bridge_span_angle(), Vector2.ONE)
	var ink := Color(0.102, 0.071, 0.039)     # HTML #1a120a
	var yT := -BRIDGE_DECK_W / 2.0            # -17
	var yB := BRIDGE_DECK_W / 2.0             # +17
	var L := BRIDGE_DECK_L                    # 78
	var wood_cols: Array[Color] = [
		Color(0.541, 0.416, 0.302),  # HTML #8a6a4d
		Color(0.518, 0.392, 0.290),  # HTML #84644a
		Color(0.561, 0.431, 0.314),  # HTML #8f6e50
		Color(0.490, 0.373, 0.271),  # HTML #7d5f45
	]
	# Soft shadow on the water under the deck (HTML ellipse(2, yB+20)).
	draw_colored_polygon(_ellipse_pts(Vector2(2.0, yB + 20.0),
		L * 0.52, 11.0), Color(0.039, 0.098, 0.157, 0.30))
	# Far-side railing (behind the deck), then the stilts.
	_bridge_rail(-1, yT, yB, L, ink)
	for sx: float in [-L * 0.32, 0.0, L * 0.32]:
		_bridge_stilt(sx, yB - 2.0, ink)
	# Stringer beam + diagonal trestle braces under the deck.
	var sx0 := -L * 0.32
	var sx2 := L * 0.32
	draw_rect(Rect2(sx0 - 6.0, yB + 1.0, sx2 - sx0 + 12.0, 6.0),
		Color(0.365, 0.251, 0.216))  # HTML #5d4037
	draw_rect(Rect2(sx0 - 6.0, yB + 1.0, sx2 - sx0 + 12.0, 6.0),
		ink, false, 1.4)
	var brace := Color(0.306, 0.204, 0.180)  # HTML #4e342e
	draw_line(Vector2(sx0, yB + 7.0), Vector2(0.0, yB + 16.0), brace, 4.0)
	draw_line(Vector2(0.0, yB + 16.0), Vector2(sx2, yB + 7.0), brace, 4.0)
	draw_line(Vector2(sx2, yB + 7.0), Vector2(0.0, yB + 16.0), brace, 4.0)
	draw_line(Vector2(0.0, yB + 16.0), Vector2(sx0, yB + 7.0), brace, 4.0)
	# Deck top: planks across the span, clear seams, pegs, tone variation.
	var grain := Color(0.157, 0.102, 0.055, 0.30)  # HTML rgba(40,26,14,0.30)
	var seam := Color(0.102, 0.071, 0.039, 0.65)   # HTML rgba(26,18,10,0.65)
	var peg := Color(0.173, 0.114, 0.071)           # HTML #2c1d12
	for i in 8:
		var px0 := -L / 2.0 + float(i) * 9.75
		draw_rect(Rect2(px0, yT, 9.75, BRIDGE_DECK_W), wood_cols[i % 4])
		draw_line(Vector2(px0 + 2.0, yT + 3.0),
			Vector2(px0 + 7.5, yT + BRIDGE_DECK_W - 3.0), grain, 1.0)
		draw_line(Vector2(px0 + 5.0, yT + 4.0),
			Vector2(px0 + 3.0, yT + BRIDGE_DECK_W - 5.0), grain, 1.0)
		draw_rect(Rect2(px0, yT, 1.6, BRIDGE_DECK_W), seam)
		draw_circle(Vector2(px0 + 4.9, yT + 5.0), 1.5, peg)
		draw_circle(Vector2(px0 + 4.9, yB - 5.0), 1.5, peg)
		draw_rect(Rect2(px0 + 1.6, yT + 2.0, 8.0, BRIDGE_DECK_W - 4.0),
			Color(1, 1, 1, 0.07))
	# NOTE: the HTML composites a photo wood-grain texture over the deck
	# here (TEX.img.wood) — the Godot port has no equivalent, so the arm
	# keeps the drawn grain (the pier-arm precedent).
	draw_rect(Rect2(-L / 2.0, yT, L, BRIDGE_DECK_W), ink, false, 2.2)
	# Front side face: timber slab thickness with joist ends.
	draw_rect(Rect2(-L / 2.0, yB, L, 9.0),
		Color(0.365, 0.251, 0.216))  # HTML #5d4037
	draw_rect(Rect2(-L / 2.0, yB, L, 2.0), Color(1, 1, 1, 0.10))
	var jx := -L / 2.0 + 7.0
	while jx < L / 2.0 - 2.0:
		draw_rect(Rect2(jx, yB + 2.5, 3.4, 4.0),
			Color(0.102, 0.071, 0.039, 0.55))
		jx += 13.0
	draw_rect(Rect2(-L / 2.0, yB, L, 9.0), ink, false, 1.6)
	# Near-side railing (in front of the deck).
	_bridge_rail(1, yT, yB, L, ink)
	draw_set_transform(anchor, 0.0, Vector2.ONE)


## Wooden post-and-rail railing along one deck edge (HTML stiltRail).
## side -1 = far edge, +1 = near edge.
func _bridge_rail(side: int, yT: float, yB: float, L: float,
		ink: Color) -> void:
	var yE := yT if side < 0 else yB
	var pTop := yE - 24.0
	var pBot := yE + (3.0 if side < 0 else -3.0)
	var rail := Color(0.427, 0.298, 0.255)  # HTML #6d4c41
	# Two horizontal rails, behind the posts.
	for ry: float in [pTop + 4.0, pTop + 14.0]:
		draw_rect(Rect2(-L / 2.0 - 2.0, ry, L + 4.0, 5.0), rail)
		draw_rect(Rect2(-L / 2.0 - 2.0, ry, L + 4.0, 1.6),
			Color(1, 1, 1, 0.14))
		draw_rect(Rect2(-L / 2.0 - 2.0, ry, L + 4.0, 5.0), ink, false, 1.3)
	# Posts with caps (HTML px from -L/2+5 to L/2-3 step 15).
	var post := Color(0.365, 0.251, 0.216)  # HTML #5d4037
	var cap := Color(0.553, 0.431, 0.388)   # HTML #8d6e63
	var px := -L / 2.0 + 5.0
	while px <= L / 2.0 - 3.0:
		var ph := pBot - pTop + 4.0
		draw_rect(Rect2(px - 2.6, pTop - 2.0, 5.2, ph), post)
		draw_rect(Rect2(px - 2.6, pTop - 2.0, 5.2, 1.8),
			Color(1, 1, 1, 0.12))
		draw_rect(Rect2(px - 2.6, pTop - 2.0, 5.2, ph), ink, false, 1.2)
		draw_circle(Vector2(px, pTop - 2.0), 3.6, cap)
		draw_arc(Vector2(px, pTop - 2.0), 3.6, 0.0, TAU, 16, ink, 1.2)
		px += 15.0


## Stilt post driven down into the water: wood above, submerged
## water-tinted section below, waterline ripples (HTML stiltPost).
func _bridge_stilt(px: float, py: float, ink: Color) -> void:
	var pw := 8.0
	var topY := py
	var wl := py + 10.0
	var botY := py + 36.0
	var post := Color(0.306, 0.204, 0.180)  # HTML #4e342e
	draw_rect(Rect2(px - pw / 2.0, topY, pw, botY - topY), post)
	draw_rect(Rect2(px - pw / 2.0, topY, 2.0, botY - topY),
		Color(1, 1, 1, 0.10))
	draw_rect(Rect2(px - pw / 2.0, topY, pw, botY - topY), ink, false, 1.5)
	# Submerged section: darkened, water-tinted, disappearing downward.
	draw_rect(Rect2(px - pw / 2.0, wl, pw, botY - wl),
		Color(0.078, 0.235, 0.392, 0.55))  # HTML rgba(20,60,100,0.55)
	draw_rect(Rect2(px - pw / 2.0, botY - 9.0, pw, 9.0),
		Color(0.039, 0.118, 0.216, 0.40))   # HTML rgba(10,30,55,0.40)
	# Waterline ripples (HTML strokes ellipses; the port samples them).
	var r1 := _ellipse_pts(Vector2(px, wl), pw / 2.0 + 4.0, 3.0)
	r1.append(r1[0])
	draw_polyline(r1, Color(1, 1, 1, 0.38), 1.6)
	var r2 := _ellipse_pts(Vector2(px, wl + 4.0), pw / 2.0 + 7.0, 4.0)
	r2.append(r2[0])
	draw_polyline(r2, Color(1, 1, 1, 0.18), 1.4)


## Sampled ellipse points (filled via draw_colored_polygon, stroked via
## draw_polyline with the first point appended) — CanvasItem has no
## draw_ellipse primitive.
func _ellipse_pts(center: Vector2, rx: float, ry: float,
		steps := 20) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps:
		var a := TAU * float(i) / float(steps)
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## Span orientation (HTML bridgeNeighborAngle parity): angle to the
## nearest sibling bridge segment within 75px, or 0 when none. TTL-cached
## so the sibling scan stays off the _draw hot path.
func _bridge_span_angle() -> float:
	var now := Time.get_ticks_msec()
	if _bridge_ang_ms < 0 or now - _bridge_ang_ms > BRIDGE_ANG_TTL_MS:
		_bridge_ang = _scan_bridge_span_angle()
		_bridge_ang_ms = now
	return _bridge_ang


func _scan_bridge_span_angle() -> float:
	var p := get_parent()
	if p == null:
		return 0.0
	var best_d2 := 75.0 * 75.0
	var found := false
	var bx := 0.0
	var by := 0.0
	for sib in p.get_children():
		if sib == self:
			continue
		var bn := sib as BuildingNode
		if bn == null or bn.btype != "bridge":
			continue
		var d2 := position.distance_squared_to(bn.position)
		if d2 < best_d2 and d2 > 4.0:
			best_d2 = d2
			bx = bn.position.x
			by = bn.position.y
			found = true
	if not found:
		return 0.0
	return (Vector2(bx, by) - position).angle()


## Shop (12h-systems-graphics 2026-10-04): ported verbatim from fix79's
## procedural drawBuilding z_shop branch — light-blue block (#90caf9),
## blue awning band (#42a5f5), two window panes, a door, and a 'SHOP'
## pill label. The Godot "shop" type (trading post, commercial zones) had
## no HTML sprite art and fell through to the generic box+roof; this is
## the HTML's own drawn shop. ASCII-only label via ThemeDB.fallback_font
## (iPhone tofu rule).
func _shop() -> void:
	_shop_body(
		Color(0.565, 0.792, 0.976),  # HTML #90caf9
		Color(0.259, 0.647, 0.961),  # HTML #42a5f5
		"SHOP")
	# Shop storefront FX (graphics-hourly 2026-10-09): the drawn living
	# shop breathes warm lamplight in its two panes. The drawn path only
	# runs for complete buildings (blueprints return earlier), so this
	# is inherently complete-only. Plain circles, arm-local frame.
	_shop_drawn_fx()


## Seed shop (12h-systems-graphics 2026-10-04): the HTML has no dedicated
## seedshop art (it was a Godot-side type), so this draws the z_shop
## layout in seed-green with a 'SEEDS' label and a sprout decal on the
## awning — same visual language as _shop, no invented sprite mapping.
func _seedshop() -> void:
	_shop_body(
		Color(0.647, 0.839, 0.654),  # seed green #a5d6a7
		Color(0.400, 0.733, 0.416),  # seed green #66bb6a
		"SEEDS")
	# Sprout decal on the awning band: stem + two leaves.
	var leaf := Color(0.180, 0.490, 0.196)  # HTML #2e7d32
	draw_line(Vector2(0, -8), Vector2(0, -13), leaf.darkened(0.2), 1.5)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -11), Vector2(-5, -13), Vector2(0, -14.5)]), leaf)
	draw_colored_polygon(PackedVector2Array([
		Vector2(0, -11), Vector2(5, -13), Vector2(0, -14.5)]),
		leaf.lightened(0.15))


## Trade outpost (dedicated-porting 2026-10-05): HTML spawnTradeOutpost
## used a storage building + flag; the Godot port gives it a real type and
## real art — a wooden trading post with a striped awning in the faction
## color, crates and a barrel of goods out front, and a signpost carrying
## a gold-coin emblem (no text glyph: iPhone web export renders some
## glyphs as tofu). Faction color comes from the building's faction.
func _trade_outpost() -> void:
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var wood := Color(0.427, 0.298, 0.208)
	var wood_dark := Color(0.325, 0.220, 0.145)
	var cream := Color(0.93, 0.88, 0.76)
	var fc: Dictionary = Config.FACTIONS.get(faction, {})
	var fcol: Color = fc.get("color", Color.WHITE)
	# Main storehouse block.
	draw_rect(Rect2(-24, -34, 48, 34), wood)
	draw_rect(Rect2(-24, -34, 48, 34), ink, false, 2.0)
	# Plank lines.
	for py in [-24.0, -14.0, -4.0]:
		draw_line(Vector2(-24, py), Vector2(24, py), wood_dark, 1.0)
	# Pitched roof.
	var roof := PackedVector2Array([
		Vector2(-28, -34), Vector2(0, -48), Vector2(28, -34)])
	draw_colored_polygon(roof, wood_dark)
	draw_polyline(roof, ink, 2.0)
	# Striped awning over the front: faction color + cream.
	var aw := PackedVector2Array([
		Vector2(-26, -22), Vector2(26, -22),
		Vector2(22, -8), Vector2(-22, -8)])
	draw_colored_polygon(aw, cream)
	draw_polyline(aw, ink, 1.5)
	var stripes := 6
	for i in range(stripes):
		if i % 2 == 0:
			continue
		var x0 := lerpf(-26.0, 26.0, float(i) / float(stripes))
		var x1 := lerpf(-26.0, 26.0, float(i + 1) / float(stripes))
		var xa := lerpf(-22.0, 22.0, float(i) / float(stripes))
		var xb := lerpf(-22.0, 22.0, float(i + 1) / float(stripes))
		draw_colored_polygon(PackedVector2Array([
			Vector2(x0, -22), Vector2(x1, -22),
			Vector2(xb, -8), Vector2(xa, -8)]), fcol)
	# Counter window under the awning.
	draw_rect(Rect2(-14, -20, 28, 10), Color(0.16, 0.11, 0.07))
	draw_rect(Rect2(-14, -20, 28, 10), ink, false, 1.5)
	# Crates of goods flanking the door.
	for cx in [-32.0, 32.0]:
		draw_rect(Rect2(cx - 7, -12, 14, 12), wood)
		draw_rect(Rect2(cx - 7, -12, 14, 12), ink, false, 1.5)
		draw_line(Vector2(cx - 7, -6), Vector2(cx + 7, -6), wood_dark, 1.0)
		draw_line(Vector2(cx, -12), Vector2(cx, 0), wood_dark, 1.0)
	# Barrel of goods.
	draw_rect(Rect2(-4, -14, 10, 14), wood_dark)
	draw_rect(Rect2(-4, -14, 10, 14), ink, false, 1.5)
	draw_line(Vector2(-4, -9), Vector2(6, -9), ink, 1.0)
	draw_line(Vector2(-4, -4), Vector2(6, -4), ink, 1.0)
	# Signpost with gold-coin emblem (no text glyph).
	draw_line(Vector2(30, -30), Vector2(30, 2), wood_dark, 3.0)
	draw_line(Vector2(30, -30), Vector2(18, -30), wood_dark, 3.0)
	draw_circle(Vector2(15, -30), 6.0, Color(0.95, 0.78, 0.25))
	draw_arc(Vector2(15, -30), 6.0, 0.0, TAU, 16, ink, 1.5)
	draw_circle(Vector2(15, -30), 2.5, ink)


## Shared z_shop-style storefront body (shop / seedshop).
func _shop_body(wall_c: Color, band_c: Color, p_label: String) -> void:
	var ink := Color(0.102, 0.071, 0.039)    # HTML #1a120a
	var glass := Color(0.65, 0.80, 0.95, 0.9)
	# Main block (HTML block 56x36 at (-28,-10), radius 4): ink outline +
	# wall body + the soft top highlight block() adds.
	draw_rect(Rect2(-28, -10, 56, 36), ink)
	draw_rect(Rect2(-26, -8, 52, 32), wall_c)
	draw_rect(Rect2(-25, -6, 50, 6), Color(1, 1, 1, 0.14))
	# Awning band across the top (HTML fillRect(-28,-16,56,10)).
	draw_rect(Rect2(-28, -16, 56, 10), band_c.darkened(0.2))
	draw_rect(Rect2(-28, -16, 56, 8), band_c)
	# Two window panes (HTML windowPane(-16,-2,12,10) / (6,-2,12,10)).
	for wx: float in [-16.0, 6.0]:
		draw_rect(Rect2(wx - 1, -3, 14, 12), ink)
		draw_rect(Rect2(wx, -2, 12, 10), glass)
		draw_rect(Rect2(wx + 1, -1, 4.0, 3.0), Color(1, 1, 1, 0.45))
		draw_line(Vector2(wx + 6, -2), Vector2(wx + 6, 8), ink, 1.2)
	# Door (HTML door(-6,10,12,16): #3e2723, ink stroke, gold knob).
	var door_c := Color(0.243, 0.153, 0.137)  # HTML #3e2723
	draw_rect(Rect2(-7, 9, 14, 18), door_c.darkened(0.2))
	draw_rect(Rect2(-6, 10, 12, 16), door_c)
	draw_circle(Vector2(2, 18), 1.8, Color(1.0, 0.835, 0.310))
	# Pill label above (HTML label(): dark pill + #fffde7 text, y=-24).
	draw_rect(Rect2(-28, -32, 56, 12), Color(0, 0, 0, 0.45))
	var font: Font = ThemeDB.fallback_font
	var tw: float = font.get_string_size(p_label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, 8).x
	draw_string(font, Vector2(-tw * 0.5, -24.0), p_label,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.992, 0.906))


## Perk eateries (launch-readiness graphics 2026-10-06): the ten SimFoodPerks
## eateries drew the generic box+roof arm. They share the shop body (a real
## eatery building, not a white box) with a per-type theme — wall/band
## colors, an ASCII sign label (ThemeDB.fallback_font, iPhone tofu rule),
## and a small iconic food prop hung on the front wall so each reads
## distinct at game scale. No emoji, no glyphs.
const EATERY_THEMES := {
	"greasy_spoon": ["GREASY SPOON", Color(0.843, 0.800, 0.784),
		Color(1.0, 0.596, 0.0)],
	"salad_bar": ["SALAD BAR", Color(0.925, 0.941, 0.855),
		Color(0.486, 0.702, 0.259)],
	"ogre_sausage_shop": ["OGRE SAUSAGE", Color(0.737, 0.667, 0.643),
		Color(0.776, 0.157, 0.157)],
	"meat_tornado": ["MEAT TORNADO", Color(0.631, 0.533, 0.498),
		Color(0.902, 0.318, 0.0)],
	"moonberry_lounge": ["MOONBERRY", Color(0.773, 0.792, 0.914),
		Color(0.369, 0.208, 0.694)],
	"dewdrop_diner": ["DEWDROP DINER", Color(0.733, 0.871, 0.984),
		Color(0.0, 0.537, 0.482)],
	"bastard_drivethru": ["TACO BASTARD", Color(1.0, 0.878, 0.698),
		Color(0.937, 0.424, 0.0)],
	"fungus_hut": ["FUNGUS HUT", Color(0.784, 0.902, 0.788),
		Color(0.557, 0.141, 0.667)],
	"crypt_kitchen": ["CRYPT KITCHEN", Color(0.839, 0.839, 0.784),
		Color(0.333, 0.545, 0.184)],
	"grave_snacks": ["GRAVE SNACKS", Color(0.690, 0.745, 0.773),
		Color(0.271, 0.153, 0.627)],
}


## Vent FX assignment per eatery (graphics-hourly 2026-10-06, launch
## readiness: "everything smoothly animated"). Kitchens smoke, diners steam,
## the fungus hut breathes spores, the moon lounge leaks blue mist, the
## repair shop smokes from the forge. Params: [tint, rise_px, drift_px,
## peak_alpha] — tuned so puffs read at game scale without covering the sign.
const EATERY_FX_KIND := {
	"greasy_spoon": "smoke", "ogre_sausage_shop": "smoke",
	"meat_tornado": "smoke", "crypt_kitchen": "smoke",
	"grave_snacks": "smoke", "repair_shop": "smoke",
	"dewdrop_diner": "steam", "salad_bar": "steam",
	"bastard_drivethru": "steam", "fungus_hut": "spore",
	"moonberry_lounge": "mist",
}
const EATERY_FX_BTYPES := ["greasy_spoon", "salad_bar", "ogre_sausage_shop",
	"meat_tornado", "moonberry_lounge", "dewdrop_diner", "bastard_drivethru",
	"fungus_hut", "crypt_kitchen", "grave_snacks", "repair_shop"]
const EATERY_FX_PARAMS := {
	"smoke": [Color(0.45, 0.44, 0.46), 26.0, 0.0, 0.40],
	"steam": [Color(0.95, 0.97, 1.00), 30.0, 0.0, 0.50],
	"spore": [Color(0.60, 0.85, 0.50), 14.0, 9.0, 0.45],
	"mist": [Color(0.65, 0.70, 0.95), 22.0, 0.0, 0.35],
}
## Vent origin in the arm's ground-anchored frame: just above the awning
## band (y=-16..-6), left of the pill sign, so puffs rise beside the sign
## rather than through it.
const EATERY_FX_VENT := Vector2(-20.0, -18.0)


func _eatery(btype: String) -> void:
	var theme: Array = EATERY_THEMES.get(btype, EATERY_THEMES["greasy_spoon"])
	_shop_body(theme[1], theme[2], String(theme[0]))
	_eatery_prop(btype)
	_eatery_fx(btype)


## Animated vent puffs for an eatery/repair-shop arm. Three puffs staggered
## through the quantized _fx_step cycle: each rises, spreads, and fades over
## one cycle. Deterministic from _fx_step (no per-frame RNG, no allocation),
## drawn with plain circles so it stays cheap on iPhone. Called from _draw,
## so it never touches world position — nothing floats.
func _eatery_fx(btype: String) -> void:
	var kind: String = String(EATERY_FX_KIND.get(btype, "smoke"))
	var p: Array = EATERY_FX_PARAMS[kind]
	var tint: Color = p[0]
	var rise: float = p[1]
	var drift: float = p[2]
	var peak_a: float = p[3]
	var step: int = maxi(_fx_step, 0)
	for i in range(3):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var vent: Vector2 = EATERY_FX_VENT
		var wob: float = sin(life * 6.0 + float(i) * 2.1) \
			* (2.0 + life * 4.0)
		var pos := Vector2(vent.x + wob + drift * life, vent.y - rise * life)
		var r: float = 2.0 + life * 4.5
		var a: float = peak_a * (1.0 - life)
		draw_circle(pos, r, Color(tint.r, tint.g, tint.b, a))


## Oil pumpjack production FX (wake routine 2026-10-07, Jeremy's standing
## "everything smoothly animated" rule): the pumpjack is the ONLY oil
## source in the game and AI towns run four of them — a static pumpjack
## reads as dead. A rocking beam was considered and rejected (slicing the
## sprite risks a visible seam); instead the engine stack exhales dark
## exhaust puffs and the wellhead puddle shimmers with an iridescent oil
## sheen. Anchors are art-pixel positions in bld_oil_pump.png (720x480),
## converted through _sprite_sc so the FX stays pinned to the art.
const OIL_PUMP_TEX_W := 720.0
const OIL_PUMP_TEX_H := 480.0
## Engine-stack top — where the exhaust starts.
const OIL_PUMP_VENT_PX := Vector2(230.0, 235.0)
## Wellhead base puddle — where the sheen shimmers.
const OIL_PUMP_PUDDLE_PX := Vector2(540.0, 380.0)
const OIL_PUMP_SHEEN_TINTS := [
	Color(0.30, 0.60, 0.55),  # teal
	Color(0.48, 0.38, 0.62),  # violet
	Color(0.52, 0.58, 0.30),  # olive
]


## Art-pixel anchor -> node-space offset, tracking the sprite's real render
## scale (see _sprite_sc). Pure math — safe to call anywhere.
func _oil_pump_anchor(art_px: Vector2) -> Vector2:
	var sc := _sprite_sc
	return Vector2(
		(art_px.x - OIL_PUMP_TEX_W * 0.5) * sc,
		(art_px.y - OIL_PUMP_TEX_H * 0.5) * sc - 0.48 * OIL_PUMP_TEX_H * sc)


## Exhaust puffs + oil sheen for a complete oil pumpjack. Deterministic
## from _fx_step (no per-frame RNG, no allocation), drawn with plain
## circles/arcs so it stays cheap on iPhone. Called from the sprite path
## of _draw — ground-anchored to the art, never touching world position,
## so nothing floats.
func _oil_pump_fx() -> void:
	var step: int = maxi(_fx_step, 0)
	var vent := _oil_pump_anchor(OIL_PUMP_VENT_PX)
	# Dark engine exhaust: three staggered puffs rising off the stack.
	for i in range(3):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 5.0 + float(i) * 2.4) \
			* (1.5 + life * 3.5)
		var pos := Vector2(vent.x + wob, vent.y - 20.0 * life)
		var r: float = 1.6 + life * 3.8
		var a: float = 0.40 * (1.0 - life)
		draw_circle(pos, r, Color(0.16, 0.15, 0.14, a))
	# Oil sheen: squashed glint arcs on the wellhead puddle, sweep rotating
	# and tint cycling teal/violet/olive across the step cycle — an
	# iridescent shimmer over the baked oil seepage.
	var puddle := _oil_pump_anchor(OIL_PUMP_PUDDLE_PX)
	var tint: Color = OIL_PUMP_SHEEN_TINTS[step % 3]
	var sweep := 0.35 + 0.10 * float(step)
	draw_set_transform(puddle, 0.0, Vector2(1.0, 0.45))
	draw_arc(Vector2.ZERO, 10.0, sweep, sweep + 2.2, 16,
		Color(tint.r, tint.g, tint.b, 0.16), 2.0)
	draw_arc(Vector2.ZERO, 15.0, sweep + 0.9, sweep + 2.9, 16,
		Color(tint.r, tint.g, tint.b, 0.10), 1.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Industrial production FX (graphics-hourly 2026-10-07, Jeremy's standing
## "everything smoothly animated" rule): the extraction + smithing chain
## was fully static while workers churned around it. Sawdust falls off the
## spinning blade, quarries breathe dust off the terraces, mines flicker a
## lantern in the shaft, and the smithy's baked forge fire pulses with
## ember glow and sparks while its chimney smokes. All quantized to the
## eatery cadence (8 steps at 6/sec), complete-only, per-building phase so
## neighbors don't pulse in sync. Deterministic, no per-frame RNG or
## allocation, drawn with plain circles so it stays cheap on iPhone. Called
## from _draw, so it never touches world position — nothing floats.
const SMITHY_TEX_W := 1200.0
const SMITHY_TEX_H := 1920.0
## Forge fire heart in bld_smithy.png (brightest warm pixel cluster).
const SMITHY_FORGE_PX := Vector2(644.0, 1362.0)
## Chimney mouth in bld_smithy.png (dark opening bbox center).
const SMITHY_CHIMNEY_PX := Vector2(967.0, 290.0)


## Quantized FX step with the per-building phase: neighboring mills don't
## pulse in sync (the banner-flutter precedent, quantized to the FX
## cadence). Safe before the first _process tick (_fx_step starts at -1).
func _fx_local_step() -> int:
	return posmod(maxi(_fx_step, 0) + _fx_phase, EATERY_FX_STEPS)


## Smithy art-pixel anchor -> node-space offset, tracking the sprite's real
## render scale (the _oil_pump_anchor precedent).
func _smithy_anchor(art_px: Vector2) -> Vector2:
	var sc := _sprite_sc
	return Vector2(
		(art_px.x - SMITHY_TEX_W * 0.5) * sc,
		(art_px.y - SMITHY_TEX_H * 0.5) * sc - 0.48 * SMITHY_TEX_H * sc)


## Ember glow + sparks + chimney smoke over the real smithy art. Called
## from the sprite path of _draw — ground-anchored to the art through the
## real render scale, so nothing floats. The baked fire pixels are never
## touched (no seam risk); the glow breathes over them.
func _smithy_fx() -> void:
	var step := _fx_local_step()
	var sc := _sprite_sc
	var forge := _smithy_anchor(SMITHY_FORGE_PX)
	# Ember pulse over the baked fire: breathing alpha at the FX cadence.
	var ember: float = 0.10 + 0.08 * (0.5 + 0.5 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS)))
	draw_circle(forge, 60.0 * sc, Color(1.0, 0.45, 0.12, ember))
	draw_circle(forge, 34.0 * sc, Color(1.0, 0.62, 0.20, ember * 1.4))
	# Sparks: three staggered, rising out of the fire into the hood.
	for i in range(3):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 8.0 + float(i) * 2.9) \
			* (30.0 + life * 90.0)
		var pos := forge + Vector2(wob * sc, -life * 260.0 * sc)
		var r: float = (14.0 - life * 8.0) * sc
		var a: float = 0.85 * (1.0 - life)
		draw_circle(pos, r, Color(1.0, 0.80, 0.35, a))
	# Chimney smoke: three staggered gray puffs drifting up-right off the
	# chimney mouth, echoing the baked smoke's direction.
	var vent := _smithy_anchor(SMITHY_CHIMNEY_PX)
	for i in range(3):
		var life2: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob2: float = sin(life2 * 5.0 + float(i) * 2.4) \
			* (20.0 + life2 * 60.0)
		var pos2 := vent + Vector2(
			(wob2 + life2 * 160.0) * sc, -life2 * 420.0 * sc)
		var r2: float = (22.0 + life2 * 55.0) * sc
		var a2: float = 0.38 * (1.0 - life2)
		draw_circle(pos2, r2, Color(0.55, 0.54, 0.56, a2))


## Pure: which smoke tint a home exhales. Only the undead house variant
## gets the sickly green (matching the wisps baked into its sprite art).
static func house_smoke_key(btype: String, p_faction: String) -> String:
	return "undead" if (p_faction == "undead" and btype == "house") else "living"


## House art-pixel anchor -> node-space offset, tracking the sprite's real
## render scale (the _oil_pump_anchor precedent). key is "house",
## "house_undead", or "farmhouse" — the undead variant shares the living
## house's 480x480 file size but has its own chimney.
func _house_fx_anchor(key: String) -> Vector2:
	var tsize: Vector2 = HOUSE_FX_TEX.get(key, HOUSE_FX_TEX["house"])
	var ap: Vector2 = HOUSE_FX_CHIMNEY.get(key, HOUSE_FX_CHIMNEY["house"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Chimney smoke for a complete house/farmhouse. Two staggered puffs rise
## from the art-measured chimney mouth, spreading and fading over one FX
## cycle — deterministic from _fx_step (no per-frame RNG, no allocation),
## drawn with plain circles so it stays cheap on iPhone. Called from the
## sprite path of _draw — ground-anchored to the art through the real
## render scale, never touching world position, so nothing floats.
func _house_fx() -> void:
	var smk := house_smoke_key(btype, faction)
	var key := "house_undead" if smk == "undead" else btype
	var vent := _house_fx_anchor(key)
	var sc := _sprite_sc
	var tint: Color = HOUSE_SMOKE_TINT_UNDEAD if smk == "undead" else HOUSE_SMOKE_TINT
	_last_house_smoke_tint = smk
	var step := _fx_local_step()
	for i in range(2):
		var life: float = float((step + i * 4) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 5.0 + float(i) * 2.4) \
			* (8.0 + life * 26.0)
		var pos := vent + Vector2(wob * sc, -life * 150.0 * sc)
		var r: float = (11.0 + life * 30.0) * sc
		var a: float = 0.34 * (1.0 - life)
		draw_circle(pos, r, Color(tint.r, tint.g, tint.b, a))


## Pure: which tavern art key exhales for a btype/faction, or "" when the
## building has no tavern chimney (living hotels use the chimney-less
## bld_shop.png art — no chimney, no FX).
static func tavern_fx_art_key(btype: String, p_faction: String) -> String:
	if p_faction == "undead" and (btype == "inn" or btype == "hotel"):
		return "tavern_undead"
	if btype == "inn":
		return "inn"
	return ""


## Tavern art-pixel anchor -> node-space offset, tracking the sprite's
## real render scale (the _house_fx_anchor precedent).
func _tavern_fx_anchor(key: String) -> Vector2:
	var tsize: Vector2 = TAVERN_FX_TEX.get(key, TAVERN_FX_TEX["inn"])
	var ap: Vector2 = TAVERN_FX_CHIMNEY.get(key, TAVERN_FX_CHIMNEY["inn"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Kitchen steam/smoke for a complete sprite-path tavern. Two staggered
## puffs rise from the art-measured chimney mouth, spreading and fading
## over one FX cycle — deterministic from _fx_step (no per-frame RNG, no
## allocation), drawn with plain circles so it stays cheap on iPhone. The
## undead variant drifts left, echoing the wisps baked into its sprite
## art. Called from the sprite path of _draw — ground-anchored to the art
## through the real render scale, never touching world position, so
## nothing floats.
func _tavern_fx() -> void:
	var key := tavern_fx_art_key(btype, faction)
	if key == "":
		return
	_last_tavern_fx_tint = key
	var vent := _tavern_fx_anchor(key)
	var sc := _sprite_sc
	var tint: Color = HOUSE_SMOKE_TINT_UNDEAD \
		if key == "tavern_undead" else TAVERN_STEAM_TINT
	var drift: float = -60.0 if key == "tavern_undead" else 0.0
	var step := _fx_local_step()
	for i in range(2):
		var life: float = float((step + i * 4) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 5.0 + float(i) * 2.4) \
			* (8.0 + life * 26.0)
		var pos := vent + Vector2((wob + drift * life) * sc,
			-life * 150.0 * sc)
		var r: float = (11.0 + life * 30.0) * sc
		var a: float = 0.34 * (1.0 - life)
		draw_circle(pos, r, Color(tint.r, tint.g, tint.b, a))


## Pure: candle flicker 0.72..1.0 for a quantized FX step + phase.
## Test seam — no node needed.
static func monastery_flicker_for(step: int, phase: float) -> float:
	return 0.86 + 0.14 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS) + phase)


## Pure: arcane flicker 0.70..1.0 for a quantized FX step + phase.
## Test seam — no node needed.
static func magespire_flicker_for(step: int, phase: float) -> float:
	return 0.85 + 0.15 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS) + phase)


## Pure: which mage-spire art key breathes for a btype/faction, or ""
## when the building is not a mage spire. The four living races use their
## per-race crystal art; anything else (undead) falls back to the tower.
static func magespire_fx_art_key(btype: String, p_faction: String) -> String:
	if btype != "mage_spire":
		return ""
	if MAGESPIRE_FX_CRYSTAL.has(p_faction) and p_faction != "tower":
		return p_faction
	return "tower"


## Spire art-pixel anchor -> node-space offset, tracking the sprite's real
## render scale (the _house_fx_anchor precedent).
func _magespire_fx_anchor(key: String) -> Vector2:
	var tsize: Vector2 = MAGESPIRE_FX_TEX.get(key, MAGESPIRE_FX_TEX["tower"])
	var ap: Vector2 = MAGESPIRE_FX_CRYSTAL.get(key,
		MAGESPIRE_FX_CRYSTAL["tower"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Arcane light for a complete sprite-path mage spire. The crown crystal
## breathes a tinted halo and looses three rising spark motes —
## deterministic from the phased FX step (no per-frame RNG, no
## allocation), plain circles so it stays cheap on iPhone. Called from the
## sprite path of _draw — ground-anchored to the art through the real
## render scale, never touching world position, so nothing floats.
## NightGlow.current() deepens the halo after dark (the monastery
## candle-glow precedent); the crystal burns all day.
func _magespire_fx() -> void:
	var key := magespire_fx_art_key(btype, faction)
	if key == "":
		return
	_last_magespire_fx = key
	var crown := _magespire_fx_anchor(key)
	var tint: Color = MAGESPIRE_FX_TINT.get(key, MAGESPIRE_FX_TINT["tower"])
	var sc := _sprite_sc
	var step := _fx_local_step()
	var night := NightGlow.current()
	var flick := magespire_flicker_for(step, float(_fx_phase) * 0.7)
	# Crystal halo: soft outer glow + bright inner core. Burns all day;
	# night deepens the outer halo.
	var halo_a := (0.20 + 0.14 * night) * flick
	draw_circle(crown, 30.0 * sc * flick,
		Color(tint.r, tint.g, tint.b, halo_a))
	draw_circle(crown, 14.0 * sc * flick,
		Color(tint.r, tint.g, tint.b, 0.35 * flick))
	# Three spark motes rise from the crystal over one FX cycle, staggered
	# and phased per building so neighboring spires don't twinkle in sync.
	for i in range(3):
		var life: float = float(
			(step + i * 3 + _fx_phase) % EATERY_FX_STEPS
		) / float(EATERY_FX_STEPS)
		var wob: float = sin(life * 6.0 + float(i) * 2.1) * 14.0
		var pos := crown + Vector2(wob * sc, -life * 90.0 * sc)
		var a: float = 0.8 * (1.0 - life)
		draw_circle(pos, (4.5 + life * 3.0) * sc,
			Color(tint.r, tint.g, tint.b, a * 0.35))
		draw_circle(pos, (2.0 + life * 1.5) * sc,
			Color(1.0, 1.0, 1.0, a * 0.75))


## Pure: warm lamplight flicker 0.64..1.0 for a quantized FX step + phase.
## Test seam — no node needed.
static func shop_flicker_for(step: int, phase: float) -> float:
	return 0.82 + 0.18 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS) + phase)


## Pure: civic lamplight flicker 0.60..1.0 for a quantized FX step + phase
## (the shop flicker with a deeper trough so council windows breathe
## more visibly than storefront panes). Test seam — no node needed.
static func civic_flicker_for(step: int, phase: float) -> float:
	return 0.80 + 0.20 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS) + phase)


## Pure: flesh-farm lamplight flicker 0.80..1.0 for a quantized FX step +
## phase (the civic flicker idiom — undead lamplight breathes the same
## way as council windows). Test seam — no node needed.
static func flesh_flicker_for(step: int, phase: float) -> float:
	return 0.80 + 0.20 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS) + phase)


## Pure: pit-wisp life 0..1 for a quantized FX step, wisp index and
## per-building phase (the civic mote idiom: staggered 1/3-cycle,
## desynced per building). floor() wrap is sign-robust, so a -1 rest
## step can't leak a negative life. Test seam — no node needed.
static func flesh_wisp_life_for(step: int, idx: int, phase: float) -> float:
	var life := float(step) / float(EATERY_FX_STEPS) + float(idx) / 3.0 + phase
	return life - floor(life)


## Pure: which shopfront art key breathes for a btype/faction, or "" when
## the building has no shop storefront art. Living "shop" uses the drawn
## arm ("shop_drawn"); wells reuse the shop art but stay dark; undead
## hotels keep their tavern FX.
static func shop_fx_art_key(btype: String, p_faction: String) -> String:
	if btype == "shop":
		return "shop_undead" if p_faction == "undead" else "shop_drawn"
	if btype == "hotel":
		return "" if p_faction == "undead" else "shop"
	if btype == "seedshop":
		return "shop"
	if btype == "trade_outpost":
		return "shop_undead" if p_faction == "undead" else "shop"
	return ""


## Pure: which civic-seat art key breathes for a btype/faction, or "" when
## the building is not a civic seat. Guild halls take the per-faction art
## (the art.gd BUILDING_ART_FACTION variants); the undead seat of power is
## the necropolis btype itself. The gov_* offices, clinic, tome_library
## and bathhouse share the bld_civic sprite but are NOT seats — they get
## no key (a glowing courthouse reads as government; a glowing clinic
## does not).
static func civic_fx_art_key(btype: String, p_faction: String) -> String:
	if btype == "town_hall" or btype == "townhall":
		return "townhall"
	if btype == "hall":
		return "hall"
	if btype == "courthouse":
		return "civic"
	if btype == "necropolis":
		return "necropolis"
	if btype == "guild_hall":
		match p_faction:
			"ogres":
				return "guild_ogre"
			"elves":
				return "guild_elf"
			"gnomes":
				return "guild_gnome"
			"undead":
				return "guild_undead"
			_:
				return "guild_human"
	return ""


## Pure: the civic art keys that burn undead (sickly-green windows,
## purple brazier flames) rather than warm lamplight.
static func civic_fx_is_undead(key: String) -> bool:
	return key == "necropolis" or key == "guild_undead"


## Shop art-pixel point -> node-space offset, tracking the sprite's real
## render scale (the _magespire_fx_anchor precedent).
func _shop_art_to_node(ap: Vector2, key: String) -> Vector2:
	var tsize: Vector2 = SHOP_FX_TEX.get(key, SHOP_FX_TEX["shop"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Window center (art px) -> node-space offset for a sprite-path shop.
func _shop_fx_anchor(key: String, idx: int) -> Vector2:
	var wins: Array = SHOP_FX_WINDOWS.get(key, SHOP_FX_WINDOWS["shop"])
	var ap: Vector2 = wins[clampi(idx, 0, wins.size() - 1)]
	return _shop_art_to_node(ap, key)


## Storefront light for a complete sprite-path shop. The display windows
## breathe tinted lamplight and the storefront looses two deterministic
## motes — winking coin glints for the living races, rising green wisps
## from the potion stall for the undead. Deterministic from the phased FX
## step (no per-frame RNG, no allocation), plain circles so it stays cheap
## on iPhone. Ground-anchored to the art through the real render scale,
## never touching world position, so nothing floats. Called from the sprite
## path of _draw; NightGlow.current() deepens the halos after dark (the
## monastery candle-glow precedent); the lamps burn all day.
func _shop_fx() -> void:
	var key := shop_fx_art_key(btype, faction)
	if key == "" or key == "shop_drawn":
		return
	_last_shop_fx = key
	var tint: Color = SHOP_FX_TINT.get(key, SHOP_FX_TINT["shop"])
	var sc := _sprite_sc
	var step := _fx_local_step()
	var night := NightGlow.current()
	var flick := shop_flicker_for(step, float(_fx_phase) * 0.9)
	var wins: Array = SHOP_FX_WINDOWS.get(key, SHOP_FX_WINDOWS["shop"])
	# Window lamplight: soft outer halo + bright inner core on each pane.
	for i in range(wins.size()):
		var w := _shop_fx_anchor(key, i)
		var halo_a := (0.16 + 0.16 * night) * flick
		draw_circle(w, 26.0 * sc * flick,
			Color(tint.r, tint.g, tint.b, halo_a))
		draw_circle(w, 12.0 * sc * flick,
			Color(tint.r, tint.g, tint.b, 0.30 * flick))
	# Two phased motes per storefront, desynced per building.
	for i in range(2):
		var life: float = float(
			(step + i * 4 + _fx_phase) % EATERY_FX_STEPS
		) / float(EATERY_FX_STEPS)
		var a: float = 0.85 * (1.0 - life)
		if key == "shop_undead":
			# Potion-stall wisps rise and spread.
			var stall := _shop_art_to_node(SHOP_FX_STALL, key)
			var wob: float = sin(life * 6.0 + float(i) * 2.4) * 12.0
			var pos := stall + Vector2(wob * sc, -life * 70.0 * sc)
			draw_circle(pos, (5.0 + life * 4.0) * sc,
				Color(tint.r, tint.g, tint.b, a * 0.30))
		else:
			# Coin glints wink above the storefront panes.
			var pane := _shop_fx_anchor(key, i % wins.size())
			var drift: float = sin(life * 5.0 + float(i) * 2.1) * 8.0
			var gpos := pane + Vector2(drift * sc, -life * 26.0 * sc)
			var wink := 0.5 + 0.5 * sin(TAU * life * 2.0)
			draw_circle(gpos, 3.2 * sc,
				Color(1.0, 0.85, 0.35, a * wink))


## Lamplight for the drawn living-shop arm: warm glow in the two window
## panes (pane centers (-10,3) and (12,3) in the arm's ground-anchored
## frame). Plain circles only (no draw_set_transform): the drawn path's
## ground-offset transform must survive this call (the _monastery_fx
## precedent). Called from _shop(), which only runs for complete shops.
func _shop_drawn_fx() -> void:
	_last_shop_fx = "shop_drawn"
	var step := _fx_local_step()
	var night := NightGlow.current()
	var flick := shop_flicker_for(step, float(_fx_phase) * 0.9)
	var tint: Color = SHOP_FX_TINT["shop"]
	for wx in [-10.0, 12.0]:
		var w := Vector2(wx, 3.0)
		var halo_a := (0.18 + 0.18 * night) * flick
		draw_circle(w, 10.0 * flick,
			Color(tint.r, tint.g, tint.b, halo_a))
		draw_circle(w, 5.0 * flick,
			Color(tint.r, tint.g, tint.b, 0.32 * flick))


## Civic art-pixel point -> node-space offset, tracking the sprite's real
## render scale (the _shop_art_to_node precedent).
func _civic_art_to_node(ap: Vector2, key: String) -> Vector2:
	var tsize: Vector2 = CIVIC_FX_TEX.get(key, CIVIC_FX_TEX["townhall"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## Seat-of-power light for a complete sprite-path civic building. The
## windows breathe tinted lamplight (warm for the living seats,
## sickly-green for the undead) and the entrance braziers burn — orange
## flame tongues for the living, purple for the undead over their baked
## flames — plus two deterministic rising motes (embers / wisps),
## desynced per building. Deterministic from the phased FX step (no
## per-frame RNG, no allocation), plain circles so it stays cheap on
## iPhone. Ground-anchored to the art through the real render scale,
## never touching world position, so nothing floats. Called from the
## sprite path of _draw; NightGlow.current() deepens the halos after
## dark (the monastery candle-glow precedent); the lamps burn all day.
func _civic_fx() -> void:
	var key := civic_fx_art_key(btype, faction)
	if key == "":
		return
	_last_civic_fx = key
	var undead := civic_fx_is_undead(key)
	var tint: Color = CIVIC_FX_TINT["undead"] if undead \
		else CIVIC_FX_TINT["living"]
	var sc := _sprite_sc
	var step := _fx_local_step()
	var night := NightGlow.current()
	var wins: Array = CIVIC_FX_WINDOWS.get(key, CIVIC_FX_WINDOWS["townhall"])
	# Window lamplight: warm halo + lit glass per pane, phased so the
	# panes don't breathe in lockstep (the monastery candle precedent).
	for i in range(wins.size()):
		var w := _civic_art_to_node(wins[i], key)
		var flick := civic_flicker_for(step,
			float(i) * 1.7 + float(_fx_phase) * 0.8)
		var halo_a := (0.14 + 0.18 * night) * flick
		draw_circle(w, 24.0 * sc * flick,
			Color(tint.r, tint.g, tint.b, halo_a))
		draw_circle(w, 10.0 * sc * flick,
			Color(tint.r, tint.g, tint.b, 0.34 * flick))
	# Entrance braziers: iron bowl + flame tongues licking up, warm pool
	# of light at the feet (the _monastery_fx brazier idiom, undead tint
	# for the necropolis and the undead guild hall). Feet planted on the
	# baked ground line — the anchors sit on the art's steps/threshold.
	var braz: Array = CIVIC_FX_BRAZIERS.get(key, [])
	for i in range(braz.size()):
		var b := _civic_art_to_node(braz[i], key)
		var bflick := civic_flicker_for(step,
			3.4 + float(i) * 2.3 + float(_fx_phase) * 0.6)
		var iron := Color(0.16, 0.14, 0.15)
		var glow := Color(1.0, 0.62, 0.25)
		var f1 := Color(0.95, 0.45, 0.12)
		var f2 := Color(1.0, 0.70, 0.22)
		var f3 := Color(1.0, 0.88, 0.45)
		if undead:
			glow = Color(0.55, 0.75, 1.0)
			f1 = Color(0.72, 0.28, 1.0)
			f2 = Color(0.82, 0.42, 1.0)
			f3 = Color(0.93, 0.68, 1.0)
		draw_circle(b + Vector2(0, -6.5 * sc), 4.6 * sc, iron)
		for t in range(2):
			var tflick := civic_flicker_for(step,
				3.4 + float(i) * 2.3 + float(t) * 2.1)
			var tx: float = b.x + (-1.6 + float(t) * 3.2) * sc
			var th: float = 5.5 * tflick * sc
			draw_circle(Vector2(tx, b.y - 8.0 * sc - th * 0.3),
				3.0 * tflick * sc, Color(f1.r, f1.g, f1.b, 0.85))
			draw_circle(Vector2(tx, b.y - 8.0 * sc - th * 0.8),
				2.0 * tflick * sc, Color(f2.r, f2.g, f2.b, 0.88))
			draw_circle(Vector2(tx, b.y - 8.0 * sc - th * 1.25),
				1.2 * tflick * sc, Color(f3.r, f3.g, f3.b, 0.90))
		draw_circle(b + Vector2(0, -1.0 * sc), 13.0 * sc,
			Color(glow.r, glow.g, glow.b,
				(0.10 + 0.08 * bflick) * (0.6 + 1.0 * night)))
	# Two phased motes per seat, desynced per building: embers for the
	# living, rising green wisps for the undead (the _shop_fx precedent).
	for i in range(2):
		var life: float = float(
			(step + i * 4 + _fx_phase) % EATERY_FX_STEPS
		) / float(EATERY_FX_STEPS)
		var a: float = 0.85 * (1.0 - life)
		var src: Vector2 = braz[0] if not braz.is_empty() else wins[0]
		var origin := _civic_art_to_node(src, key)
		var wob: float = sin(life * 6.0 + float(i) * 2.4) * 12.0
		var pos := origin + Vector2(wob * sc, -life * 70.0 * sc)
		if undead:
			draw_circle(pos, (5.0 + life * 4.0) * sc,
				Color(tint.r, tint.g, tint.b, a * 0.30))
		else:
			var wink := 0.5 + 0.5 * sin(TAU * life * 2.0)
			draw_circle(pos, 3.2 * sc,
				Color(1.0, 0.72, 0.30, a * wink))


## Flesh-farm art-pixel point -> node-space offset, tracking the sprite's
## real render scale (the _civic_art_to_node precedent).
func _flesh_art_to_node(ap: Vector2) -> Vector2:
	var sc := _sprite_sc
	return Vector2(
		(ap.x - FLESH_FX_TEX.x * 0.5) * sc,
		(ap.y - FLESH_FX_TEX.y * 0.5) * sc - 0.48 * FLESH_FX_TEX.y * sc)


## Undead harvest light for a complete flesh_farm. The hut window and the
## door lantern pulse sickly-green lamplight (the undead civic tint) and
## three wisps rise off the bone pit — deterministic from the phased FX
## step (no per-frame RNG, no allocation), plain circles so it stays
## cheap on iPhone. Ground-anchored to the art through the real render
## scale, never touching world position, so nothing floats. Called from
## the sprite path of _draw; NightGlow.current() deepens the halos after
## dark (the monastery candle-glow precedent); the lamps burn all day.
func _flesh_fx() -> void:
	_last_flesh_fx = "flesh_farm"
	var tint: Color = CIVIC_FX_TINT["undead"]
	var sc := _sprite_sc
	var step := _fx_local_step()
	var night := NightGlow.current()
	var phase := float(_fx_phase) * 0.7
	# Hut window + door lantern: green halo + lit glass, phased apart so
	# they don't breathe in lockstep (the civic window precedent).
	var spots: Array = [FLESH_FX_WINDOW, FLESH_FX_LANTERN]
	for i in range(spots.size()):
		var w := _flesh_art_to_node(spots[i])
		var flick := flesh_flicker_for(step, float(i) * 2.9 + phase)
		var halo_a := (0.14 + 0.18 * night) * flick
		draw_circle(w, 22.0 * sc * flick,
			Color(tint.r, tint.g, tint.b, halo_a))
		draw_circle(w, 9.0 * sc * flick,
			Color(tint.r, tint.g, tint.b, 0.34 * flick))
	# Three wisps off the bone pit, staggered 1/3-cycle, desynced per
	# building (the civic mote idiom, undead-tinted).
	for i in range(FLESH_FX_PIT.size()):
		var life := flesh_wisp_life_for(step, i,
			float(_fx_phase) / float(EATERY_FX_STEPS))
		var a: float = 0.85 * (1.0 - life)
		var origin := _flesh_art_to_node(FLESH_FX_PIT[i])
		var wob: float = sin(life * 6.0 + float(i) * 2.4) * 12.0
		var pos := origin + Vector2(wob * sc, -life * 60.0 * sc)
		draw_circle(pos, (4.0 + life * 3.0) * sc,
			Color(tint.r, tint.g, tint.b, a * 0.30))


## Candle-glow for a complete monastery. The two arched windows breathe
## warm candlelight and a brazier burns by the doorway — deterministic from
## the phased FX step (no per-frame RNG, no allocation), plain circles so
## it stays cheap on iPhone. Ground-anchored to the baked _monastery art
## coordinates, never touching world position, so nothing floats. Uses
## plain circles only (no draw_set_transform): the drawn path's
## ground-offset transform must survive this call. Called from the drawn
## path of _draw — the generic NightGlow halo already rides above at night;
## this is the monastery's own identity, and it burns all day.
func _monastery_fx() -> void:
	_last_monastery_fx = btype
	var step := _fx_local_step()
	var night := NightGlow.current()
	# Window candlelight: warm halo + lit glass + two candle dots per
	# arched window. Candles burn all day; halos deepen after dark.
	for i in range(MONASTERY_WINDOWS.size()):
		var wc: Vector2 = MONASTERY_WINDOWS[i]
		var flick := monastery_flicker_for(step, float(i) * 1.9)
		var halo_a: float = (0.10 + 0.10 * flick) * (0.6 + 0.9 * night)
		draw_circle(wc, 12.0, Color(1.0, 0.72, 0.36, halo_a))
		var glass_a: float = 0.38 * flick
		draw_rect(Rect2(wc.x - 3.5, wc.y - 7.0, 7.0, 14.0),
			Color(1.0, 0.81, 0.49, glass_a))
		draw_circle(Vector2(wc.x, wc.y - 7.0), 3.5,
			Color(1.0, 0.81, 0.49, glass_a))
		for k in range(2):
			var kflick := monastery_flicker_for(
				step, float(i) * 1.9 + float(k) * 2.7)
			draw_circle(wc + Vector2(-1.8 + float(k) * 3.6, 3.0), 1.3,
				Color(1.0, 0.88, 0.55, 0.55 + 0.40 * kflick))
	# Brazier by the doorway: iron bowl on a tripod, flame tongues licking
	# up, warm light pooling at its feet. Feet planted on the ground line.
	var b := MONASTERY_BRAZIER
	var bflick := monastery_flicker_for(step, 3.4)
	var iron := Color(0.16, 0.14, 0.15)
	draw_line(b + Vector2(0, -6), b + Vector2(-3.5, 0), iron, 1.6)
	draw_line(b + Vector2(0, -6), b + Vector2(3.5, 0), iron, 1.6)
	draw_line(b + Vector2(0, -6), b + Vector2(0, 0), iron, 1.6)
	draw_circle(b + Vector2(0, -6.5), 4.6, iron)
	draw_circle(b + Vector2(0, -7.0), 3.0, Color(0.95, 0.42, 0.10, 0.9))
	for t in range(2):
		var tflick := monastery_flicker_for(step, 3.4 + float(t) * 2.3)
		var tx: float = b.x - 1.6 + float(t) * 3.2
		var th: float = 5.5 * tflick
		draw_circle(Vector2(tx, b.y - 8.0 - th * 0.3), 3.0 * tflick,
			Color(0.95, 0.45, 0.12, 0.85))
		draw_circle(Vector2(tx, b.y - 8.0 - th * 0.8), 2.0 * tflick,
			Color(1.0, 0.70, 0.22, 0.88))
		draw_circle(Vector2(tx, b.y - 8.0 - th * 1.25), 1.2 * tflick,
			Color(1.0, 0.88, 0.45, 0.90))
	# Warm pool of light at the brazier's feet, deeper at night.
	draw_circle(b + Vector2(0, -1.0), 13.0,
		Color(1.0, 0.62, 0.25,
			(0.10 + 0.08 * bflick) * (0.6 + 1.0 * night)))


## Pure: war-fire flicker 0.80..1.0 for a quantized FX step + phase.
## Test seam — no node needed.
static func military_flicker_for(step: int, phase: float) -> float:
	return 0.90 + 0.10 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS) + phase)


## Pure: warning-beacon blink — 1.0 when lit, 0.12 when dark. Two beats
## per FX cycle so the silo/dish strobe reads as a warning, not a flicker.
## Test seam — no node needed.
static func military_beacon_for(step: int, phase: float) -> float:
	var s: float = sin(
		TAU * float(step) / float(EATERY_FX_STEPS) * 2.0 + phase)
	return 1.0 if s > 0.0 else 0.12


## Pure: radar-ping life 0.0..1.0 across one FX cycle. Test seam — no node
## needed.
static func military_ping_for(step: int) -> float:
	return float(step) / float(EATERY_FX_STEPS)


## Pure: which military art key breathes for a btype/faction, or "" when
## the building has no military FX (undead guard houses keep the drawn
## fallback arm — no art, no FX).
static func military_fx_art_key(btype: String, p_faction: String) -> String:
	if btype in ["barracks", "war_hut", "cannon_foundry", "armory",
			"vehicle_depot"]:
		return "barracks_undead" if p_faction == "undead" else "barracks"
	if btype == "knights_castle":
		return "castle"
	if btype == "guard_house":
		if p_faction in ["elves", "gnomes", "humans", "ogres"]:
			return "guard_house_" + p_faction
		return ""
	if btype in ["guard_tower", "aa_tower", "air_defense"]:
		return "tower"
	if btype == "nuke_silo":
		return "silo"
	if btype == "anti_nuke":
		return "antinuke"
	if btype == "shooting_range":
		return "range"
	return ""


## Military art-pixel anchor -> node-space offset, tracking the sprite's
## real render scale (the _house_fx_anchor precedent). "silo" shares the
## tower art size through the fallback — nuke_silo renders bld_tower.png.
func _military_fx_anchor(key: String, ap: Vector2) -> Vector2:
	var tsize: Vector2 = MILITARY_FX_TEX.get(key, MILITARY_FX_TEX["tower"])
	var sc := _sprite_sc
	return Vector2(
		(ap.x - tsize.x * 0.5) * sc,
		(ap.y - tsize.y * 0.5) * sc - 0.48 * tsize.y * sc)


## War-machine FX for a complete sprite-path military building. The
## barracks family breathes chimney smoke and candlelit windows (undead:
## sickly-green smoke + purple brazier flames); cannon foundries spark out
## of the stack. Castles get gate torches + keep windows; guard houses get
## their lanterns lit; watch/AA towers burn a signal brazier on the
## platform; the nuke silo strobes a red warning beacon; the anti-nuke
## dish pings radar and strobes red; the archery range drifts dust motes
## over the targets. Deterministic from the phased FX step (no per-frame
## RNG, no allocation), plain circles/arcs so it stays cheap on iPhone.
## Called from the sprite path of _draw — ground-anchored to the art
## through the real render scale, never touching world position, so
## nothing floats.
func _military_fx() -> void:
	var key := military_fx_art_key(btype, faction)
	if key == "":
		return
	_last_military_fx = key
	var step := _fx_local_step()
	var sc := _sprite_sc
	var night := NightGlow.current()
	var undead := key == "barracks_undead"
	# Chimney smoke (barracks family only).
	if MILITARY_FX_VENT.has(key):
		var vent := _military_fx_anchor(key, MILITARY_FX_VENT[key])
		var tint: Color = HOUSE_SMOKE_TINT_UNDEAD if undead \
			else HOUSE_SMOKE_TINT
		for i in range(2):
			var life: float = float((step + i * 4 + _fx_phase) \
				% EATERY_FX_STEPS) / float(EATERY_FX_STEPS)
			var wob: float = sin(life * 5.0 + float(i) * 2.4) \
				* (8.0 + life * 26.0)
			var pos := vent + Vector2(wob * sc, -life * 150.0 * sc)
			var r: float = (11.0 + life * 30.0) * sc
			var a: float = 0.34 * (1.0 - life)
			draw_circle(pos, r, Color(tint.r, tint.g, tint.b, a))
		# Cannon foundries spark out of the stack (a foundry, not a hearth).
		if btype == "cannon_foundry":
			for j in range(3):
				var slife: float = float((step + j * 3 + _fx_phase) \
					% EATERY_FX_STEPS) / float(EATERY_FX_STEPS)
				var swob: float = sin(slife * 8.0 + float(j) * 2.9) \
					* (30.0 + slife * 90.0)
				var spos := vent + Vector2(swob * sc, -slife * 260.0 * sc)
				var sr: float = (14.0 - slife * 8.0) * sc
				var sa: float = 0.85 * (1.0 - slife)
				draw_circle(spos, sr, Color(1.0, 0.80, 0.35, sa))
	# Candlelit windows: warm halo + lit glass (undead: sickly green).
	if MILITARY_FX_WINDOWS.has(key):
		var wins: Array = MILITARY_FX_WINDOWS[key]
		for i in range(wins.size()):
			var wc: Vector2 = _military_fx_anchor(key, wins[i])
			var flick := military_flicker_for(step, float(i) * 1.9)
			var halo_a: float = (0.10 + 0.10 * flick) * (0.6 + 0.9 * night)
			var glass_a: float = 0.38 * flick
			if undead:
				draw_circle(wc, 10.0 * sc, Color(0.35, 0.85, 0.35, halo_a))
				draw_circle(wc, 4.0 * sc, Color(0.35, 0.85, 0.35, glass_a))
			else:
				draw_circle(wc, 10.0 * sc, Color(1.0, 0.72, 0.36, halo_a))
				draw_circle(wc, 4.0 * sc, Color(1.0, 0.81, 0.49, glass_a))
	# Torch / brazier / lantern flames (undead barracks burn purple).
	if MILITARY_FX_FLAMES.has(key):
		var fls: Array = MILITARY_FX_FLAMES[key]
		for i in range(fls.size()):
			var fp: Vector2 = _military_fx_anchor(key, fls[i])
			var fflick := military_flicker_for(step, float(i) * 2.3 + 1.1)
			var flame_c := Color(0.72, 0.28, 0.95) if undead \
				else Color(0.95, 0.45, 0.12)
			var core_c := Color(0.85, 0.55, 1.0) if undead \
				else Color(1.0, 0.70, 0.22)
			draw_circle(fp, 3.2 * fflick * sc, Color(flame_c, 0.9))
			draw_circle(fp + Vector2(0, -2.5 * fflick * sc),
				2.0 * fflick * sc, Color(core_c, 0.92))
			draw_circle(fp, 8.0 * fflick * sc, Color(
				flame_c.r, flame_c.g, flame_c.b, 0.25 * fflick))
	# Warning beacons (silo + anti-nuke dish): hard red strobe.
	if MILITARY_FX_BEACONS.has(key):
		var bcs: Array = MILITARY_FX_BEACONS[key]
		for i in range(bcs.size()):
			var bp: Vector2 = _military_fx_anchor(key, bcs[i])
			var lit := military_beacon_for(step, float(i) * 1.7)
			draw_circle(bp, 5.0 * sc, Color(1.0, 0.10, 0.10, 0.95 * lit))
			draw_circle(bp, 11.0 * sc, Color(1.0, 0.15, 0.15, 0.30 * lit))
	# Radar ping (anti-nuke dish): one expanding ring per FX cycle.
	if key == "antinuke":
		var dish := _military_fx_anchor(key, MILITARY_FX_DISH)
		var plife := military_ping_for(step)
		draw_arc(dish, (6.0 + plife * 46.0) * sc, 0.0, TAU, 28,
			Color(0.45, 0.90, 1.0, 0.55 * (1.0 - plife)), 2.0 * sc)
	# Archery-range dust motes drifting over the targets.
	if key == "range":
		for i in range(3):
			var t: Vector2 = _military_fx_anchor(key,
				MILITARY_FX_TARGETS[(i + _fx_phase) \
					% MILITARY_FX_TARGETS.size()])
			var mlife: float = float((step + i * 3 + _fx_phase) \
				% EATERY_FX_STEPS) / float(EATERY_FX_STEPS)
			var mwob: float = sin(mlife * 6.0 + float(i) * 2.1) * 14.0
			var mpos := t + Vector2(mwob * sc, -mlife * 60.0 * sc)
			var ma: float = 0.5 * (1.0 - mlife)
			draw_circle(mpos, (3.5 + mlife * 2.5) * sc,
				Color(0.85, 0.80, 0.70, ma))


## Creates the damage overlay layer (band just rose to >= 1).
func _ensure_dmg_layer() -> void:
	if _dmg_layer != null and is_instance_valid(_dmg_layer):
		return
	var layer := DamageFXLayer.new()
	layer.host = self
	_dmg_layer = layer
	add_child(layer)


## Frees the damage overlay layer (repaired back to healthy).
func _clear_dmg_layer() -> void:
	if _dmg_layer != null and is_instance_valid(_dmg_layer):
		remove_child(_dmg_layer)
		_dmg_layer.queue_free()
	_dmg_layer = null


## Draws the battle-damage overlay onto ci (the DamageFXLayer child, which
## renders above the sprite art). Ladder: band 1 scuffed (soot streaks +
## hairline cracks), band 2 cracked/crumbling (scorch wash, jagged cracks,
## debris at the base), band 3 smoking (crack treatment + heavy smoke),
## band 4 burning (bigger flames + smoke). Anchored to the generic
## footprint in ground-anchored node space — no per-type art positions,
## so it works on both the sprite and programmer-art paths. Crack/debris
## art is deterministic from the building id (no per-frame RNG); only
## smoke and flames animate on the shared quantized FX step. Plain
## shapes, no allocation — cheap on iPhone. Called from the layer's
## _draw, so it never touches world position: nothing floats.
func draw_damage_fx(ci: CanvasItem) -> void:
	if _dmg_band < 1:
		return
	var s := _size_for(btype)
	var h := s * 1.2
	var step := _fx_local_step()
	# Scorch wash (band >= 2): a dark translucent ellipse over the
	# footprint so damage reads at a glance on a phone screen.
	if _dmg_band >= 2:
		ci.draw_set_transform(Vector2(0.0, -h * 0.35), 0.0,
			Vector2(1.0, 0.62))
		ci.draw_circle(Vector2.ZERO, s * 0.52,
			Color(0.10, 0.08, 0.07, 0.22 + 0.08 * float(_dmg_band - 2)))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Scuffed and up: soot streaks down the walls + hairline cracks.
	_dmg_soot_streaks(ci, s, h)
	# Cracked and up: jagged seeded cracks + debris chunks at the base.
	if _dmg_band >= 2:
		_dmg_cracks(ci, s, h, 2 + _dmg_band)
		_dmg_debris(ci, s, h)
	# Flames first (under the smoke): band 4 burns harder — four bigger
	# tongues plus a stronger ember glow hugging the ground line.
	if _dmg_band >= 4:
		for i in range(4):
			var flick: float = 0.75 + 0.25 * sin(
				float(step) * 1.9 + float(i) * 2.3)
			var base := Vector2(-s * 0.30 + float(i) * s * 0.20, -h * 0.12)
			ci.draw_set_transform(base, 0.0, Vector2(1.0, 1.7))
			ci.draw_circle(Vector2.ZERO, 7.5 * flick,
				Color(0.95, 0.42, 0.10, 0.85))
			ci.draw_circle(Vector2(0.0, -1.5), 4.0 * flick,
				Color(1.0, 0.80, 0.25, 0.90))
			ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		ci.draw_set_transform(Vector2(0.0, -h * 0.06), 0.0,
			Vector2(1.0, 0.35))
		ci.draw_circle(Vector2.ZERO, s * 0.46, Color(1.0, 0.45, 0.10, 0.30))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Smoke (band >= 3): roof vents, staggered puffs rising and fading.
	if _dmg_band >= 3:
		var vents := 3 if _dmg_band >= 4 else 2
		for v in range(vents):
			var vent := Vector2(-s * 0.18 + float(v) * s * 0.36, -h * 0.72)
			for i in range(3):
				var life: float = float((step + i * 3 + v * 4)
					% EATERY_FX_STEPS) / float(EATERY_FX_STEPS)
				var wob: float = sin(life * 5.5 + float(i + v * 2) * 2.2) \
					* (2.0 + life * 5.0)
				var pos := Vector2(vent.x + wob, vent.y - h * 0.55 * life)
				var r: float = 3.0 + life * 7.0
				var a: float = 0.45 * (1.0 - life)
				ci.draw_circle(pos, r, Color(0.22, 0.21, 0.22, a))


## Deterministic 0..1 pseudo-random from the building id + slot: the
## crack/debris art never changes between redraws, with zero per-frame
## RNG and zero allocation.
func _dmg_seed(slot: int) -> float:
	return float(absi(hash(building_id * 131 + slot * 17 + 7))) \
		/ 9223372036854775807.0


## Band >= 1 scuff: dark soot streaks running down the walls. Seeded
## x positions so neighboring buildings don't streak identically.
func _dmg_soot_streaks(ci: CanvasItem, s: float, h: float) -> void:
	var soot := Color(0.08, 0.07, 0.07, 0.35)
	for i in range(3):
		var x := (0.25 + _dmg_seed(i) * 0.9 - 0.45) * s
		var top := Vector2(x, -h * (0.45 + _dmg_seed(i + 10) * 0.25))
		var bot := Vector2(x + (_dmg_seed(i + 20) - 0.5) * 8.0, -h * 0.10)
		ci.draw_line(top, bot, soot, 3.0 + _dmg_seed(i + 30) * 3.0)


## Band >= 2 crumble: jagged cracks down the facade, drawn as seeded
## connected line segments (no array allocation).
func _dmg_cracks(ci: CanvasItem, s: float, h: float, count: int) -> void:
	var crack := Color(0.05, 0.04, 0.04, 0.65)
	for c in range(count):
		var x := (_dmg_seed(c * 4) - 0.5) * s * 0.9
		var y := -h * (0.55 + _dmg_seed(c * 4 + 1) * 0.25)
		var p := Vector2(x, y)
		for seg in range(4):
			var nx := p.x + (_dmg_seed(c * 40 + seg * 3 + 2) - 0.5) * s * 0.22
			var ny := p.y + h * (0.10 + _dmg_seed(c * 40 + seg * 3 + 3) * 0.10)
			var q := Vector2(nx, ny)
			ci.draw_line(p, q, crack, 1.8)
			p = q


## Band >= 2 crumble: broken chunks shed at the base. Small rotated
## stone squares via a local transform — no allocation.
func _dmg_debris(ci: CanvasItem, s: float, h: float) -> void:
	for i in range(4):
		var px := (_dmg_seed(i * 9 + 50) - 0.5) * s * 1.1
		var py := -h * 0.03 - _dmg_seed(i * 9 + 51) * 4.0
		var sz := 3.0 + _dmg_seed(i * 9 + 52) * 4.0
		var tone := 0.30 + _dmg_seed(i * 9 + 53) * 0.15
		ci.draw_set_transform(Vector2(px, py),
			_dmg_seed(i * 9 + 54) * TAU, Vector2.ONE)
		ci.draw_rect(Rect2(-sz / 2, -sz / 2, sz, sz),
			Color(tone, tone * 0.95, tone * 0.88, 0.9))
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
## Missing-art fallback forge: a lit forge window flickering on the smithy
## wall. Only ever renders when bld_smithy.png is absent.
func _weaponsmith_fallback_fx() -> void:
	var step := _fx_local_step()
	var flick: float = 0.55 + 0.45 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS))
	var ink := Color(0.102, 0.071, 0.039)
	# Light spilling from the mouth onto the wall.
	draw_circle(Vector2(18.5, 14.0), 11.0, Color(1.0, 0.50, 0.15, 0.14 * flick))
	draw_rect(Rect2(12, 8, 13, 12), ink)
	draw_rect(Rect2(14, 10, 9, 8),
		Color(1.0, 0.42 + 0.10 * flick, 0.10, 0.95))
	draw_rect(Rect2(15.5, 11.5, 6, 5), Color(1.0, 0.78, 0.30, 0.95))


## Sawdust falling off the spinning blade's lower contact point. Three
## staggered puffs drift down and out, tan against the mill's wood.
func _sawmill_fx() -> void:
	var step := _fx_local_step()
	for i in range(3):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 7.0 + float(i) * 2.3) \
			* (1.0 + life * 3.0)
		var pos := Vector2(10.0 + wob, 14.0 + life * 9.0)
		var r: float = 1.4 + life * 2.6
		var a: float = 0.45 * (1.0 - life)
		draw_circle(pos, r, Color(0.74, 0.62, 0.42, a))


## Quarry dust breathing off the pit terraces: three staggered gray puffs
## rising slowly, barely-there so the pit art stays readable.
func _quarry_fx() -> void:
	var step := _fx_local_step()
	var vents := [Vector2(-6, 2), Vector2(5, 4), Vector2(0, 10)]
	for i in range(3):
		var life: float = float((step + i * 3) % EATERY_FX_STEPS) \
			/ float(EATERY_FX_STEPS)
		var wob: float = sin(life * 6.0 + float(i) * 2.6) \
			* (1.0 + life * 3.0)
		var v: Vector2 = vents[i]
		var pos := Vector2(v.x + wob, v.y - life * 10.0)
		var r: float = 1.8 + life * 3.0
		var a: float = 0.35 * (1.0 - life)
		draw_circle(pos, r, Color(0.55, 0.53, 0.50, a))


## Mine lantern: a warm glow flickering inside the dark shaft arch, a lit
## lantern dot hung on the timber frame, and dust motes drifting out on
## two of the eight steps.
func _mine_fx() -> void:
	var step := _fx_local_step()
	var flick: float = 0.70 + 0.30 * sin(
		TAU * float(step) / float(EATERY_FX_STEPS))
	draw_circle(Vector2(0, 5), 10.0, Color(1.0, 0.68, 0.32, 0.20 * flick))
	draw_circle(Vector2(0, 5), 5.5, Color(1.0, 0.75, 0.40, 0.28 * flick))
	draw_circle(Vector2(8.5, -2), 1.6, Color(1.0, 0.82, 0.45, 0.9 * flick))
	if step == 2 or step == 6:
		draw_circle(Vector2(-4, 8), 1.4, Color(0.60, 0.57, 0.52, 0.5))
		draw_circle(Vector2(3, 11), 1.2, Color(0.60, 0.57, 0.52, 0.4))


## Iconic food prop per eatery, hung on the front wall above the door
## (all draw calls in the arm's ground-anchored frame). Small (~12px)
## silhouette shapes with ink outlines — readable at game scale.
func _eatery_prop(btype: String) -> void:
	var ink := Color(0.102, 0.071, 0.039)
	var px := 18.0  # prop anchor: right of the door
	var py := 14.0
	match btype:
		"greasy_spoon":
			# Burger: bottom bun, patty, top bun with sesame.
			draw_circle(Vector2(px, py + 4), 6.0, Color(0.85, 0.62, 0.32))
			draw_rect(Rect2(px - 6, py + 1, 12, 3), Color(0.35, 0.18, 0.10))
			draw_arc(Vector2(px, py + 1), 6.0, PI, TAU, 12,
				Color(0.93, 0.72, 0.42), 5.0)
		"salad_bar":
			# Bowl with leafy greens.
			draw_arc(Vector2(px, py), 6.0, 0.0, PI, 12,
				Color(0.75, 0.75, 0.78), 5.0)
			for lx in [-3.0, 0.0, 3.0]:
				draw_circle(Vector2(px + lx, py - 3), 2.6,
					Color(0.30, 0.65, 0.25))
		"ogre_sausage_shop", "meat_tornado":
			# Sausage links / skewer: three meat chunks on a stick.
			draw_line(Vector2(px - 6, py + 2), Vector2(px + 6, py - 4), ink, 2.0)
			for i in range(3):
				var mx: float = px - 4.0 + float(i) * 4.0
				var my: float = py + 1.0 - float(i) * 2.0
				draw_circle(Vector2(mx, my), 2.8, Color(0.72, 0.25, 0.18))
		"moonberry_lounge":
			# Crescent moon + berry.
			draw_circle(Vector2(px, py), 5.0, Color(1.0, 0.95, 0.65))
			draw_circle(Vector2(px + 2.5, py - 1.5), 4.2,
				Color(0.773, 0.792, 0.914))
			draw_circle(Vector2(px - 5, py + 4), 2.4,
				Color(0.45, 0.25, 0.70))
		"dewdrop_diner":
			# Teacup: cup body, handle arc, steam wisp.
			draw_rect(Rect2(px - 4, py - 2, 8, 6), Color(0.92, 0.95, 0.98))
			draw_arc(Vector2(px + 4, py + 1), 2.6, -1.2, 1.2, 8, ink, 1.6)
			draw_line(Vector2(px - 1, py - 4), Vector2(px - 1, py - 7),
				Color(1, 1, 1, 0.7), 1.4)
		"bastard_drivethru":
			# Taco: folded shell semicircle with filling.
			draw_arc(Vector2(px, py + 2), 6.0, PI, TAU, 12,
				Color(0.93, 0.72, 0.35), 5.0)
			for lx in [-3.0, 0.0, 3.0]:
				draw_circle(Vector2(px + lx, py - 3), 1.8,
					Color(0.55, 0.75, 0.25))
			draw_circle(Vector2(px, py - 4), 1.6, Color(0.80, 0.20, 0.15))
		"fungus_hut":
			# Mushroom: stem + spotted cap.
			draw_rect(Rect2(px - 1.5, py - 1, 3, 6), Color(0.93, 0.90, 0.82))
			draw_arc(Vector2(px, py + 1), 5.5, PI, TAU, 12,
				Color(0.75, 0.30, 0.35), 6.0)
			draw_circle(Vector2(px - 2, py - 3), 1.2, Color(1, 1, 1, 0.85))
			draw_circle(Vector2(px + 2.5, py - 2), 1.0, Color(1, 1, 1, 0.85))
		"crypt_kitchen":
			# Soup pot with steam.
			draw_rect(Rect2(px - 5, py - 1, 10, 6), ink)
			draw_rect(Rect2(px - 4, py, 8, 4), Color(0.25, 0.25, 0.28))
			draw_arc(Vector2(px, py), 5.0, PI, TAU, 10,
				Color(0.45, 0.70, 0.30), 2.4)
			draw_line(Vector2(px + 1, py - 6), Vector2(px + 1, py - 9),
				Color(1, 1, 1, 0.6), 1.4)
		"grave_snacks":
			# Tombstone with a snack bar leaning on it.
			draw_rect(Rect2(px - 4, py - 4, 8, 10), Color(0.62, 0.65, 0.70))
			draw_arc(Vector2(px, py - 4), 4.0, PI, TAU, 10,
				Color(0.62, 0.65, 0.70), 4.0)
			draw_rect(Rect2(px + 3, py, 3, 7), Color(0.72, 0.45, 0.20))


## Repair shop (launch-readiness graphics 2026-10-06): workshop variant of
## the shop body — steel walls, hazard-orange band, 'REPAIR' sign, and a
## wrench prop on the front wall. No emoji, no glyphs.
func _repair_shop() -> void:
	_shop_body(Color(0.690, 0.745, 0.773), Color(0.961, 0.486, 0.0), "REPAIR")
	var ink := Color(0.102, 0.071, 0.039)
	var px := 18.0
	var py := 14.0
	# Wrench: diagonal handle + open-end jaw.
	var dir := Vector2(0.7, -0.7).normalized()
	draw_line(Vector2(px, py) - dir * 6.0, Vector2(px, py) + dir * 4.0,
		Color(0.75, 0.78, 0.82), 3.2)
	draw_line(Vector2(px, py) - dir * 6.0, Vector2(px, py) + dir * 4.0,
		ink, 4.4)
	draw_line(Vector2(px, py) - dir * 6.0, Vector2(px, py) + dir * 4.0,
		Color(0.75, 0.78, 0.82), 3.2)
	var tip: Vector2 = Vector2(px, py) + dir * 4.0
	draw_arc(tip, 3.4, -0.6, 2.2, 10, Color(0.75, 0.78, 0.82), 3.0)
	_eatery_fx("repair_shop")


## Garden plot (12h-systems-graphics 2026-10-04): ported verbatim from
## fix79's drawGardenLayer — soil bed (#5d4037 outer, #795548 inner, no
## circular shadow per Jeremy 2026-09-18), a 3x3 flower grid (leaves
## #2e7d32, blooms from the HTML's six-color palette picked
## deterministically per plot, #fff59d centers). Drawn at 0.5 scale of the
## HTML's 56px GARDEN_CELL to fit the Godot footprint. A flat plot, so
## _draw skips the generic doorway rect for this type.
func _garden() -> void:
	var soil_out := Color(0.365, 0.263, 0.216)  # HTML #5d4037
	var soil_in := Color(0.474, 0.333, 0.282)   # HTML #795548
	var leaf := Color(0.180, 0.490, 0.196)      # HTML #2e7d32
	var center := Color(1.0, 0.961, 0.616)      # HTML #fff59d
	var palette: Array[Color] = [
		Color(0.898, 0.451, 0.451),  # HTML #e57373
		Color(0.941, 0.384, 0.573),  # HTML #f06292
		Color(0.729, 0.408, 0.784),  # HTML #ba68c8
		Color(1.0, 0.835, 0.310),    # HTML #ffd54f
		Color(1.0, 0.541, 0.396),    # HTML #ff8a65
		Color(1.0, 1.0, 1.0),        # HTML #ffffff
	]
	# Soil bed (HTML GARDEN_CELL=56 at 0.5 scale -> half=14).
	var half := 14.0
	draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), soil_out)
	draw_rect(Rect2(-half + 2.0, -half + 2.0, half * 2.0 - 4.0,
		half * 2.0 - 4.0), soil_in)
	# Flower rows — deterministic per plot like the HTML
	# (seed = (x*7 + y*13) | 0).
	var seed := int(position.x * 7.0 + position.y * 13.0)
	for r in 3:
		for c in 3:
			var fx := -half + 6.0 + float(c) * 8.0
			var fy := -half + 6.0 + float(r) * 8.0
			var col: Color = palette[absi(seed + r * 3 + c) % palette.size()]
			draw_circle(Vector2(fx, fy + 1.5), 1.6, leaf)
			draw_circle(Vector2(fx, fy), 1.7, col)
			draw_circle(Vector2(fx, fy), 0.65, center)
