extends SceneTree
## Cursing Gnomes — phone app-icon white-matte regression test (launch-readiness 2026-10-06).
##
## Jeremy's launch-readiness rule: no white squares. Phone home-screen icons
## are drawn raw on the wallpaper (TextureRect, no clipping in phone_ui.gd),
## so any opaque near-white pixels connected to the image border render as
## white wedges/frames around the icon — a visible white-square defect.
## Two genuine defects were fixed and are pinned here:
##   - app_rumors.png (2026-10-06): AI-generated with opaque white corner
##     triangles outside the rounded-rect icon -> flood-cleared to transparent.
##   - app_army.png (2026-10-06): AI-generated with a full white matte frame
##     (21px top/bottom, 49px left/right) around the icon -> cropped off,
##     then corner triangles cleared to transparent (backup in the goal's
##     hidden_files/whitesweep-backup-20261006/phone_icons/).
## Every app_*.png is scanned so future AI-generated icons can't sneak a
## white matte back in. Enclosed white INSIDE the icon art (clouds, sword
## blades) is legitimate and untouched — only border-connected pixels fail.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_icon_whitesweep.gd
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


## Opaque near-white = the white-matte artifact class.
func _is_artifact(c: Color) -> bool:
	return c.a > 0.78 and c.r > 0.92 and c.g > 0.92 and c.b > 0.92


## Flood from all four borders through artifact pixels only; returns the count.
func _border_artifact_count(img: Image) -> int:
	var w := img.get_width()
	var h := img.get_height()
	var seen := {}
	var stack: Array[Vector2i] = []
	for x in range(w):
		stack.append(Vector2i(x, 0))
		stack.append(Vector2i(x, h - 1))
	for y in range(h):
		stack.append(Vector2i(0, y))
		stack.append(Vector2i(w - 1, y))
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		if p.x < 0 or p.y < 0 or p.x >= w or p.y >= h:
			continue
		if seen.has(p):
			continue
		if not _is_artifact(img.get_pixel(p.x, p.y)):
			continue
		seen[p] = true
		stack.append(p + Vector2i(1, 0))
		stack.append(p + Vector2i(-1, 0))
		stack.append(p + Vector2i(0, 1))
		stack.append(p + Vector2i(0, -1))
	return seen.size()


func _initialize() -> void:
	print("=== Cursing Gnomes phone-icon whitesweep tests ===")
	var dir := DirAccess.open("res://assets/ui/phone")
	_check("phone icon dir opens", dir != null)
	if dir == null:
		_finish()
		return
	var files: PackedStringArray = dir.get_files()
	var icons: Array[String] = []
	for f in files:
		if f.begins_with("app_") and f.ends_with(".png"):
			icons.append("res://assets/ui/phone/" + f)
	icons.sort()
	_check("at least one app icon found", icons.size() > 0)
	print("  scanning %d icons" % icons.size())
	for path in icons:
		var img := Image.load_from_file(path)
		_check(path.get_file() + " loads", img != null and not img.is_empty())
		if img == null or img.is_empty():
			continue
		var n := _border_artifact_count(img)
		_check(path.get_file() + " has no border-connected white matte (%d)" % n, n == 0)
	# Pin the two fixed defects explicitly.
	_check("app_rumors.png scanned", icons.has("res://assets/ui/phone/app_rumors.png"))
	_check("app_army.png scanned", icons.has("res://assets/ui/phone/app_army.png"))
	_finish()


func _finish() -> void:
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
