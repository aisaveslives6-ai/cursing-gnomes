extends SceneTree
## Cursing Gnomes — UI-chrome glyph tests (Jeremy 2026-10-03).
##
## Jeremy's iPhone screenshot showed emoji rendering as tofu boxes in the
## Godot web export: UI chrome must use text labels or drawn icons, never
## glyphs. This covers the remaining live-displayed chrome that the earlier
## drawer/director/army/gazette sweeps did not reach:
##   - world.gd flash_hint() call sites (transient overworld hint label)
##   - main.gd music-hint label
##   - BUILD_TABS build-menu tab buttons + GOV_DECISIONS popup titles
##   - royal court petition option buttons (domestic + crime-wave petitions)
##   - disaster forecast labels (shown in the forecast hint)
##   - phone wallpaper picker selected-row indicator (Jeremy 2026-10-04:
##     the "✓" check rendered as tofu on iPhone; must be ASCII text)
##
## NPC speech, hearsay, and story bodies keep their emoji by design
## (Jeremy's NPC-language directive) — this test covers chrome only.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ui_chrome_glyphs.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Same >U+2500 rule as test_hud_resources / test_director_glyphs: plain
## text labels never reach this high; anything above it is a tofu risk.
static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


## Scan a script for lines matching `marker`, skipping full-line comments.
static func _scan_lines(path: String, marker: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	while not f.eof_reached():
		var line: String = f.get_line()
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if line.find(marker) >= 0:
			out.append(line.strip_edges().left(120))
	f.close()
	return out


## Returns the (non-comment) lines of the body of the named function, up to
## the next top-level `func ` at column 0. Comment-only lines are skipped.
static func _func_body(path: String, func_marker: String) -> Array[String]:
	var out: Array[String] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var inside := false
	while not f.eof_reached():
		var line: String = f.get_line()
		if not inside:
			if line.begins_with(func_marker):
				inside = true
			continue
		if line.begins_with("func ") or line.begins_with("static func "):
			break
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		out.append(stripped.left(120))
	f.close()
	return out


func _initialize() -> void:
	print("=== Cursing Gnomes UI-chrome glyph tests ===")
	_run.call_deferred()


func _run() -> void:
	# --- world.gd flash_hint call sites (live hint label) -------------------
	var hints: Array[String] = _scan_lines("res://scripts/world/world.gd", "flash_hint(")
	_check("flash_hint call sites exist", hints.size() > 0)
	for h in hints:
		_check("hint glyph-free: " + h, not _has_glyph(h))

	# --- main.gd music hint --------------------------------------------------
	var music: Array[String] = _scan_lines("res://scripts/main.gd", "_music_hint.text")
	for m in music:
		_check("music hint glyph-free: " + m, not _has_glyph(m))

	# --- build menu tab labels -----------------------------------------------
	for tab: Array in SimBuildings.BUILD_TABS:
		_check("build tab glyph-free: " + String(tab[1]),
			not _has_glyph(String(tab[1])))

	# --- government decision popup titles ------------------------------------
	for d: Dictionary in SimBuildings.GOV_DECISIONS:
		_check("gov decision title glyph-free: " + String(d.get("title", "")),
			not _has_glyph(String(d.get("title", ""))))

	# --- royal court petition options (domestic templates) --------------------
	for t: Dictionary in SimRoyalCourt.DOMESTIC_TEMPLATES:
		for opt: String in t.get("options", []):
			_check("court option glyph-free: " + opt, not _has_glyph(opt))

	# --- crime-wave petition options (passed to court.petition) ---------------
	for opt: String in ["Raise Militia", "Fund Crackdown (120g)", "Ignore"]:
		_check("crime petition option glyph-free: " + opt, not _has_glyph(opt))

	# --- disaster forecast labels ---------------------------------------------
	for e: Dictionary in DisasterSim.FORECAST_EVENTS:
		_check("forecast label glyph-free: " + String(e.get("label", "")),
			not _has_glyph(String(e.get("label", ""))))
	_check("forecast wizard glyph-free",
		not _has_glyph(String(DisasterSim.FORECAST_WIZARD.get("label", ""))))

	# --- ZONE_EMOJI quarantined: no flash_hint may call zone_emoji ------------
	var emoji_use: Array[String] = _scan_lines("res://scripts/world/world.gd", "zone_emoji(")
	_check("no zone_emoji in world chrome", emoji_use.is_empty())

	# --- phone wallpaper picker: selected-row indicator must be ASCII text ---
	# (Jeremy 2026-10-03: ✓/✔ glyphs render as tofu on iPhone web export).
	var checks: Array[String] = _scan_lines("res://scripts/ui/phone_ui.gd", "check.text")
	_check("wallpaper selected-indicator exists", checks.size() > 0)
	for c in checks:
		_check("wallpaper selected-indicator glyph-free: " + c, not _has_glyph(c))

	# --- drawer section headers: gold title color for readability ------------
	# (2026-10-04: headers get the same gold as the Resources / Government
	# panel titles on the dark wood background, not the default label color).
	var drawer_body: Array[String] = _func_body(
		"res://scripts/ui/hud.gd", "func _drawer_section(")
	_check("drawer section builder exists", drawer_body.size() > 0)
	var has_gold := false
	for line in drawer_body:
		if line.find("add_theme_color_override") >= 0 \
				and line.find("font_color") >= 0:
			has_gold = true
	_check("drawer section header has gold title color", has_gold)

	print("test_ui_chrome_glyphs: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		print("  failures: ", _failures)
	quit(1 if _failed > 0 else 0)
