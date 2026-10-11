extends SceneTree
## Cursing Gnomes — keyboard app-icon border regression test
## (graphics-hourly 2026-10-08).
##
## assets/ui/phone/app_keyboard.png shipped with a lumpy AI-generation
## artifact along its top edge: 408 opaque near-black (12,12,12) border
## pixels where the intended rounded tile should be transparent. On the
## phone home screen (icons float directly on the wallpaper, no wrapper)
## this rendered as a dark smear across the top of the Keyboard icon.
## Fixed by mirroring the clean bottom-half alpha to the top (0px
## asymmetry vs the bottom edge); original backed up in the goal's
## hidden_files/art-backups.
##
## This test pins the fix: zero opaque border pixels, and top/bottom
## alpha symmetry, so a future bad extraction can't sneak the smear back.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_keyboard_icon.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

const ICON_PATH := "assets/ui/phone/app_keyboard.png"
const ALPHA_FLOOR := 0.06  # matches the sweep scripts' 16/255 cut


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


func _load() -> Image:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ICON_PATH))
	_check("icon loads", img != null and not img.is_empty())
	return img


func _border_opaque_count(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var n := 0
	for x in range(w):
		if img.get_pixel(x, 0).a > ALPHA_FLOOR:
			n += 1
		if img.get_pixel(x, h - 1).a > ALPHA_FLOOR:
			n += 1
	for y in range(h):
		if img.get_pixel(0, y).a > ALPHA_FLOOR:
			n += 1
		if img.get_pixel(w - 1, y).a > ALPHA_FLOOR:
			n += 1
	return n


## First opaque x from the left edge for a row (w = fully transparent row).
func _first_opaque_x(img: Image, y: int) -> int:
	var w := img.get_width()
	for x in range(w):
		if img.get_pixel(x, y).a > ALPHA_FLOOR:
			return x
	return w


func _initialize() -> void:
	print("keyboard icon border test: ", ICON_PATH)
	var img := _load()
	if img == null or img.is_empty():
		_finish()
		return
	var w := img.get_width()
	var h := img.get_height()
	_check("icon is square", w == h)
	_check("icon has alpha", img.detect_alpha() != Image.ALPHA_NONE)

	# The fixed tile must not touch the image border anywhere: rounded
	# corners + margins on all four sides (was 408 opaque border px).
	_check("zero opaque border pixels", _border_opaque_count(img) == 0)

	# Top edge mirrors the clean bottom edge (the fix's reconstruction).
	# Sampled every 10px over the corner curve, 200px deep.
	var worst := 0
	var y := 0
	while y < 200:
		var top_x := _first_opaque_x(img, y)
		var bot_x := _first_opaque_x(img, h - 1 - y)
		worst = maxi(worst, absi(top_x - bot_x))
		y += 10
	_check("top/bottom alpha symmetric (worst %dpx <= 2)" % worst, worst <= 2)

	# Interior art survived: the gold frame region and key grid are opaque.
	_check("frame art intact", img.get_pixel(w / 2, int(h * 0.06)).a > 0.5)
	_check("key art intact", img.get_pixel(w / 2, h / 2).a > 0.5)
	_check("corners transparent", img.get_pixel(4, 4).a <= ALPHA_FLOOR)

	_finish()


func _finish() -> void:
	print("keyboard_icon: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("  FAILED: ", f)
		quit(1)
	else:
		quit(0)
