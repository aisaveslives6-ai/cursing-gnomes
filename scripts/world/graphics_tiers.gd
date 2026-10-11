class_name GraphicsTiers
extends RefCounted
## Cursing Gnomes — graphics tier resolution + knobs.
##
## IPHONE 17 FLOOR (Jeremy 2026-10-04): the minimum hardware the game must
## run well on. iPhone 17 standard:
##   - Apple A19 (3 nm), hexa-core CPU (2 perf + 4 efficiency), 5-core GPU
##   - 8 GB LPDDR5 RAM (shared with the OS)
##   - 6.3" OLED, 2622x1206 px (458 PPI), 120 Hz ProMotion
## The game ships as a Godot web export played in Safari, so the practical
## floor is Safari's WebGL2 on this hardware — the budgets below are sized
## for that context, not for native Metal. The game may scale UP on better
## hardware, but it must never need more than this to hold 60 fps.
##
## PERFORMANCE BUDGETS (worst-case simultaneous load, every tier):
##   weather particles ......... <= 240  (WeatherFX.RAIN_DROPS = 220 today)
##   ambient particles ......... <= 240  (fireflies 42 + leaves 36 + embers 144 = 222)
##   combat FX pool slots ...... <= 64   (CombatFX.FX_POOL = 48 today)
##   concurrent building fires . <= 32   (CombatFX.MAX_BUILDING_FIRES = 24 today)
##   audio voices .............. <= 32   (8 sfx + 16 spatial + 3 music = 27 today)
##   global NPCs ............... <= 240  (Config.POP_CAP_GLOBAL; Jeremy's hard cap)
##   target frame rate ......... 60 fps  (adaptive quality guards it in auto mode)
const BUDGET_WEATHER_PARTICLES := 240
const BUDGET_AMBIENT_PARTICLES := 240
const BUDGET_FX_POOL := 64
const BUDGET_BUILDING_FIRES := 32
const BUDGET_AUDIO_VOICES := 36  # 2026-10-11: +4 for the AAA boot
# intro bed (wind/leaves/birds, stopped at menu) + the overworld
# rotation's crossfade partner (sounds only during 2.5s transitions).
# Steady-state DSP load is unchanged — these are declared voices,
# not concurrently-playing ones.
const BUDGET_NPCS := 240
const BUDGET_TARGET_FPS := 60
##
## HTML parity (applyGraphicsTier / detectDeviceGraphics / effGroundDetail):
##   ultra: maxTreesDraw 8000, particleMul 0.9,  unitUpdateEvery 1, lodBias 0
##   high:  maxTreesDraw 3500, particleMul 0.75, unitUpdateEvery 1, lodBias 0.05
##   medium:maxTreesDraw 2200, particleMul 0.5,  unitUpdateEvery 2, lodBias 0.15
##   low:   maxTreesDraw 800,  particleMul 0.15, unitUpdateEvery 4, lodBias 0.35
## "auto" runs the device scan (Jeremy's rule: graphics default to Auto
## everywhere). Adaptive quality steps the tier down/up on sustained
## frame-time in auto mode only — purely visual, sim/AI/RNG untouched.
##
## Godot mapping:
##   maxTreesDraw -> fraction of mapgen trees kept visible (tree_draw_frac
##     uses the HTML ratios: 1.0 / 0.4375 / 0.275 / 0.1)
##   particleMul -> WeatherFX rain/snow pool fraction + RiverRenderer foam
##     spawn gate (HTML scaled magic-FX sparks; Godot's FX are pooled)
##   unitUpdateEvery -> unit visual-sync cadence in physics frames
##   lodBias -> kept for parity; no Godot consumer yet
##   DPR follows tier in HTML; the Godot port restores the high-tier DPR cap
##     in the web shell (fix-ios-zoom.sh section 5 "thermal-dpr-cap": the
##     engine sees devicePixelRatio capped at 2 on DPR>2 phones — same CSS
##     layout, same game pixels, ~55% less fragment work; pixel art is
##     visually identical at DPR 2 on a 458 PPI panel).


const SETTINGS_PATH := "user://settings.json"
const TIERS: Array[String] = ["ultra", "high", "medium", "low"]
## HTML tree-count ratios (maxTreesDraw / 8000).
const TREE_FRAC := {"ultra": 1.0, "high": 0.4375, "medium": 0.275, "low": 0.1}


## Read the persisted settings file (shared by menu, world, diagnostics).
static func read_user_settings() -> Dictionary:
	return read_user_settings_at(SETTINGS_PATH)


## Same read at an explicit path — lets tests point at a temp file.
static func read_user_settings_at(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		out = parsed
	return out


## Device scan -> tier. Mirrors the HTML scoring (base 50, cores, RAM,
## screen, mobile penalty, GPU sniff) with the same tier thresholds:
## >=100 ultra, >=95 high, >=30 medium, else low.
static func detect() -> String:
	var cores := OS.get_processor_count()
	var mobile := OS.has_feature("mobile") \
		or OS.has_feature("web_android") or OS.has_feature("web_ios")
	var adapter := ""
	if RenderingServer != null:
		adapter = String(RenderingServer.get_video_adapter_name())
	# Screen heuristic (HTML used width*dpr; Godot's web canvas size is CSS
	# px, so the raw window size is the honest signal here).
	var vs := Vector2(1280, 720)
	if DisplayServer.get_name() != "headless":
		vs = Vector2(DisplayServer.window_get_size())
	var w := maxf(vs.x, vs.y)
	return tier_for_score(score_device(cores, mobile, adapter, w))


## Pure device scoring, extracted from detect() so tests can simulate
## hardware (e.g. iPhone 17) without running on it. Math is identical to
## the old inline detect().
static func score_device(cores: int, mobile: bool, adapter: String,
		screen_w: float) -> int:
	var score := 50
	if cores > 0:
		score += mini(25, (cores - 4) * 5)
	if mobile:
		score -= 18
		if cores >= 6:
			score += 6
	else:
		score += 8
	var a := adapter.to_lower()
	if "swiftshader" in a or "llvmpipe" in a or "software" in a:
		score -= 35
	elif "apple" in a or "m1" in a or "m2" in a or "m3" in a or "m4" in a:
		score += 12
	elif "adreno" in a or "mali" in a or "xclipse" in a:
		score += 8
	elif "nvidia" in a or "geforce" in a or "radeon" in a or "iris" in a:
		score += 10
	if screen_w >= 2000.0:
		score += 8
	elif screen_w < 1000.0:
		score -= 10
	return clampi(score, 0, 100)


## Score -> tier. iPhone 17 (A19 hexa-core, mobile, Apple GPU, ~874 CSS px
## wide) scores ~50 -> "medium": the floor tier. The adaptive quality system
## (world.gd) only ever steps DOWN from the boot tier in auto mode, so
## medium is both the floor and the ceiling on iPhone 17 — guaranteed
## smooth, never over-promised. Better hardware scores into high/ultra.
static func tier_for_score(score: int) -> String:
	var s := clampi(score, 0, 100)
	if s >= 100:
		return "ultra"
	if s >= 95:
		return "high"
	return "medium" if s >= 30 else "low"



## "auto" (or blank/invalid) resolves via the device scan; a manual tier is
## always respected.
static func resolve(graphics_setting: String) -> String:
	var g := graphics_setting.to_lower().strip_edges()
	if g == "" or g == "auto":
		return detect()
	return g if g in TIERS else "medium"


## Concrete per-tier knobs (HTML applyGraphicsTier parity).
static func knobs(tier: String) -> Dictionary:
	match tier:
		"ultra":
			return {"particle_mul": 0.9, "unit_sync_every": 1,
				"tree_draw_frac": TREE_FRAC["ultra"], "lod_bias": 0.0}
		"high":
			return {"particle_mul": 0.75, "unit_sync_every": 1,
				"tree_draw_frac": TREE_FRAC["high"], "lod_bias": 0.05}
		"medium":
			return {"particle_mul": 0.5, "unit_sync_every": 2,
				"tree_draw_frac": TREE_FRAC["medium"], "lod_bias": 0.15}
		_:
			return {"particle_mul": 0.15, "unit_sync_every": 4,
				"tree_draw_frac": TREE_FRAC["low"], "lod_bias": 0.35}


## Effective ground detail: 'auto' follows the active tier (HTML parity:
## ultra/high -> high, medium -> medium, low -> low).
static func eff_ground_detail(ground_setting: String,
		active_tier: String) -> String:
	var g := ground_setting.to_lower().strip_edges()
	if g != "" and g != "auto":
		return g if g in TIERS else "medium"
	match active_tier:
		"ultra", "high":
			return "high"
		"medium":
			return "medium"
		_:
			return "low"
