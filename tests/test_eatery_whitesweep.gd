extends SceneTree
## Cursing Gnomes — eatery sprite white-sweep regression test (graphics-hourly 2026-10-06).
##
## Jeremy's launch-readiness rule: no white squares. The sibling wired genuine
## per-race pixel-art restaurant sprites into BUILDING_ART today (greasy_spoon,
## salad_bar, ogre_sausage_shop, meat_tornado, moonberry_lounge, dewdrop_diner,
## bastard_drivethru, fungus_hut, crypt_kitchen, grave_snacks ->
## eat_cheese_shop / eat_turkey_shop / eat_acorn_shop / eat_taco_shop /
## eat_soul_cafe .png). Border-connected opaque near-white pixels would render
## as white boxes/corners around the buildings in the isometric world.
## Enclosed white (signage glare, plate highlights) is legitimate art and is
## NOT touched by this check — only border-connected artifact pixels fail.
##
## Also pins that each sprite has genuine transparency: a sprite that is
## 100% opaque is a rectangular box background, not a cut-out sprite.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_eatery_whitesweep.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

const EATERY_SPRITES: Array[String] = [
	"assets/art/buildings/eat_cheese_shop.png",
	"assets/art/buildings/eat_turkey_shop.png",
	"assets/art/buildings/eat_acorn_shop.png",
	"assets/art/buildings/eat_taco_shop.png",
	"assets/art/buildings/eat_soul_cafe.png",
]


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Near-white opaque = the artifact class (white boxes, white corners, glare).
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


func _transparent_fraction(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var transparent := 0
	var total := w * h
	# Sample every 4th pixel — exact ratio is not needed, the threshold is.
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			if img.get_pixel(x, y).a < 0.04:
				transparent += 1
			x += 4
		y += 4
	var sampled: int = int(ceil(float(w) / 4.0) * ceil(float(h) / 4.0))
	if sampled <= 0:
		return 0.0
	return float(transparent) / float(sampled)


func _test_eatery_sprites() -> void:
	_check("five eatery sprites listed", EATERY_SPRITES.size() == 5)
	var worst_path := ""
	var worst := 0
	for p in EATERY_SPRITES:
		var img := Image.load_from_file("res://" + p)
		_check("sprite loads: " + p, img != null and not img.is_empty())
		if img == null or img.is_empty():
			continue
		var n: int = _border_artifact_count(img)
		if n > worst:
			worst = n
			worst_path = p
		_check("no border-connected white on " + p, n == 0)
		# Cut-out sprite, not a box: demand a meaningful transparent margin.
		var tf := _transparent_fraction(img)
		_check("sprite has transparent background (>15%): " + p, tf > 0.15)
	_check("zero border-connected white on all eatery sprites (worst: " + worst_path + ")", worst == 0)
	print("  worst border-connected white count: ", worst)


func _initialize() -> void:
	print("=== Cursing Gnomes eatery white-sweep tests ===")
	_test_eatery_sprites()
	print("=== ", _passed, " passed, ", _failed, " failed ===")
	if not _failures.is_empty():
		print("failures:")
		for f in _failures:
			print("  - ", f)
	quit(1 if _failed > 0 else 0)
