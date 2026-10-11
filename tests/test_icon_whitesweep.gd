extends SceneTree
## Cursing Gnomes — icon white-square sweep regression test (graphics-hourly 2026-10-06).
##
## Jeremy's launch-readiness rule: no white squares. Border-connected opaque
## near-white pixels in a UI icon render as white edges/corners on the phone
## home screen (see: app_squabble.png 7.2% side bars, app_weather.png 2.4%
## white corners, app_settings.png glare specks — all fixed via border-flood
## to transparent). Enclosed white (sun, clouds, gear highlights, birds) is
## legitimate art and is NOT touched by this check.
##
## This test pins the sweep: every PNG in assets/ui/phone/, assets/ui/, and
## assets/ui/sidebar/ must have ZERO border-connected opaque near-white pixels,
## so a future icon addition with the same artifact class fails loudly instead
## of shipping a white-edged icon to Jeremy's phone. Raw AI-generation sources
## (media-generation-*.png) are excluded: they are not shipped UI.
##
## 2026-10-07: extended to assets/ui/sidebar/ after the sweep found
## icon_diplomacy.png (27.5% border-connected white corners on the HUD
## diplomacy tab bubble) — fixed via border-flood to transparent.
##
## 2026-10-08: extended with the FLOATING-ICON corner pin. The near-white
## check above missed DARK opaque halos: icon_capitol.png shipped with a
## fully opaque dark-navy square (the HUD capitol-snap bubble rendered a
## navy square where its five sibling bubbles are clean circles) and
## app_keyboard.png shipped with an opaque black square (a black tile on
## the phone home screen where its eleven siblings float as glass tiles).
## Both were border-flooded to transparent the same run. Floating icons —
## phone home tiles, HUD bubbles, resource-row icons — render with no
## wrapper, so every corner must be transparent regardless of halo color.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_icon_whitesweep.gd
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


## Near-white opaque = the artifact class (white bars, white corners, glare).
func _is_artifact(c: Color) -> bool:
	return c.a > 0.78 and c.r > 0.96 and c.g > 0.96 and c.b > 0.96


## Flood from the border through artifact pixels only; returns the count.
func _border_artifact_count(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var visited := {}
	var stack: Array = []
	for x in range(w):
		for y in [0, h - 1]:
			if _is_artifact(img.get_pixel(x, y)):
				stack.append(Vector2i(x, y))
	for y in range(h):
		for x in [0, w - 1]:
			if _is_artifact(img.get_pixel(x, y)):
				stack.append(Vector2i(x, y))
	var count := 0
	var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if visited.has(p):
			continue
		visited[p] = true
		if not _is_artifact(img.get_pixel(p.x, p.y)):
			continue
		count += 1
		for d in dirs:
			var n: Vector2i = p + d
			if n.x >= 0 and n.x < w and n.y >= 0 and n.y < h and not visited.has(n):
				stack.append(n)
	return count


func _icons_in(dir: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open("res://" + dir)
	if da == null:
		return out
	for f in da.get_files():
		# Raw AI-generation sources are kept for provenance but are not
		# shipped UI — skip them (e.g. sidebar's media-generation-icon-*).
		if f.ends_with(".png") and not f.begins_with("media-generation-"):
			out.append(dir + "/" + f)
	return out


func _test_phone_icons() -> void:
	var paths: Array[String] = []
	paths.append_array(_icons_in("assets/ui/phone"))
	paths.append_array(_icons_in("assets/ui"))
	paths.append_array(_icons_in("assets/ui/sidebar"))
	_check("icons found to scan", paths.size() > 0)
	print("  scanned ", paths.size(), " icons")
	var worst_path := ""
	var worst := 0
	for p in paths:
		var img := Image.load_from_file("res://" + p)
		_check("icon loads: " + p, img != null and not img.is_empty())
		if img == null or img.is_empty():
			continue
		var n: int = _border_artifact_count(img)
		if n > worst:
			worst = n
			worst_path = p
	_check("zero border-connected white on all icons (worst: " + worst_path + ")", worst == 0)
	print("  worst border-connected white count: ", worst)


func _initialize() -> void:
	print("=== Cursing Gnomes icon white-sweep tests ===")
	_test_phone_icons()
	_test_floating_icon_corners()
	print("=== ", _passed, " passed, ", _failed, " failed ===")
	if not _failures.is_empty():
		print("failures:")
		for f in _failures:
			print("  - ", f)
	quit(1 if _failed > 0 else 0)


## Jeremy 2026-10-08 (no dark squares): floating icons render with no
## wrapper — phone home tiles float on the wallpaper, HUD bubbles are
## circular, resource-row icons sit raw in the row. Any opaque halo color
## (white AND dark) shows as a square. Pin: every corner transparent.
## Threshold is 0.5, not 0.05: the 63x64 pixel-art resource icons have
## legitimate anti-aliased fringe at the canvas edge (alpha <= 42/255),
## which is invisible — only a real halo (alpha 255) fails.
## Deliberately a hardcoded list (not a directory scan): full-bleed art
## like the phone wallpaper is SUPPOSED to be opaque and must not fail.
const FLOATING_ICONS: Array[String] = [
	# Phone home-screen tiles (phone_ui.gd HOME_APPS).
	"assets/ui/phone/app_messenger.png",
	"assets/ui/phone/app_squabble.png",
	"assets/ui/phone/app_gazette.png",
	"assets/ui/phone/app_policies.png",
	"assets/ui/phone/app_diplomacy.png",
	"assets/ui/phone/app_calendar.png",
	"assets/ui/phone/app_wallpaper.png",
	"assets/ui/phone/app_keyboard.png",
	"assets/ui/phone/app_weather.png",
	"assets/ui/phone/app_settings.png",
	"assets/ui/phone/app_army.png",
	"assets/ui/phone/app_rumors.png",
	# HUD tab bubbles + capitol snap button (hud.gd).
	"assets/ui/sidebar/icon_phone.png",
	"assets/ui/sidebar/icon_resources.png",
	"assets/ui/sidebar/icon_government.png",
	"assets/ui/sidebar/icon_diplomacy.png",
	"assets/ui/sidebar/icon_menu.png",
	"assets/ui/sidebar/icon_capitol.png",
	# Resource-row icons (hud.gd _res_icon_row via Art.resource_icon).
	"assets/art/icons/icon_food.png",
	"assets/art/icons/icon_wood.png",
	"assets/art/icons/icon_gold.png",
	"assets/art/icons/icon_oil.png",
	"assets/art/icons/icon_ammo.png",
	"assets/art/icons/icon_meds.png",
	"assets/art/icons/icon_seeds.png",
	"assets/art/icons/icon_soul_essence.png",
]


func _test_floating_icon_corners() -> void:
	var bad: Array[String] = []
	for p in FLOATING_ICONS:
		var img := Image.load_from_file("res://" + p)
		_check("floating icon loads: " + p, img != null and not img.is_empty())
		if img == null or img.is_empty():
			continue
		var w := img.get_width()
		var h := img.get_height()
		var ok := true
		for xy in [Vector2i(0, 0), Vector2i(w - 1, 0),
				Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]:
			if img.get_pixel(xy.x, xy.y).a > 0.5:
				ok = false
		if not ok:
			bad.append(p)
	_check("all floating icons have transparent corners", bad.is_empty())
	for p in bad:
		print("  opaque-corner icon: ", p)
