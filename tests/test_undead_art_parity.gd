extends SceneTree
## Cursing Gnomes — undead art parity regression tests (LANE 8, 2026-10-06).
##
## Allison's art direction: the undead are Frankenstein-style stitched-together
## GREEN CHIBIS ("like those green chibis but with stitches all over em") —
## matching the undead trading-card identity (assets/ui/factions/cards/undead.webp).
## Explicitly NOT the old chibi-skull / ringwraith look.
##
## Guards, per sprite (16 files: undead_{type}_{0,1}.png, type in skeleton,
## zombie, ghoul, wraith, necromancer, plaguebearer, bone_golem, lich):
##   1. file exists, RGBA, height == 192 (animator frame contract), sane width
##   2. real transparency: corners fully transparent, 35-85% opaque fill
##   3. no border-connected near-white pixels (no white squares / bg slivers)
##   4. Frankenstein-green identity: >= 4% of opaque pixels green-dominant
##      (pale green skin), >= 10% near-black (stitch marks, dark cloaks)
##   5. perceptual dHash differs from the OLD off-model sprites (pinned below)
##   6. _0/_1 frame pairs differ slightly (real 2-frame animation), but stay
##      close (same character)
## Also asserts the stale job-based undead PNG set does not exist
## (media-generation-undead-{warrior,worker,ranger,mage}-*.json are stale;
## only the 8 unique undead types ship).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_undead_art_parity.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


const UNDEAD_TYPES: Array[String] = [
	"skeleton", "zombie", "ghoul", "wraith",
	"necromancer", "plaguebearer", "bone_golem", "lich",
]

## dHash (8x8) of the OLD off-model frame-0 sprites (backed up in the goal's
## hidden_files/lane8_undead_art_backup/). New art must differ from these.
const OLD_HASHES := {
	"skeleton": 0x0F134D550F61170F,
	"zombie": 0x1F03170F0F2B1596,
	"ghoul": 0x1B21D4962B130F57,
	"wraith": 0x0F2B17174D96134E,
	"necromancer": 0x0F0F0F0F0F0F5517,
	"plaguebearer": 0x0F3B4D0D2B371796,
	"bone_golem": 0x0F134D4D0F4DD432,
	"lich": 0x0E1F4D4D170F272B,
}

## Stale job-archetype names that must NOT exist as undead PNGs.
const STALE_ARCHETYPES: Array[String] = ["warrior", "worker", "ranger", "mage"]


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _is_artifact(c: Color) -> bool:
	return c.a > 0.78 and c.r > 0.96 and c.g > 0.96 and c.b > 0.96


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
	while not stack.is_empty():
		var p: Vector2i = stack.pop_back()
		var key := "%d,%d" % [p.x, p.y]
		if visited.has(key):
			continue
		visited[key] = true
		if not _is_artifact(img.get_pixel(p.x, p.y)):
			continue
		count += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var q: Vector2i = p + d
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				stack.append(q)
	return count


func _dhash(img: Image) -> int:
	var small := img.duplicate() as Image
	small.resize(9, 8, Image.INTERPOLATE_BILINEAR)
	var bits := 0
	for y in range(8):
		for x in range(8):
			var a := small.get_pixel(x, y).get_luminance()
			var b := small.get_pixel(x + 1, y).get_luminance()
			bits = (bits << 1) | (1 if a > b else 0)
	return bits


func _ham(a: int, b: int) -> int:
	# NOTE: a ^ b can be negative (dHash bit 63 set); GDScript >> is an
	# arithmetic shift, so `while x != 0` would never terminate on negatives.
	# Fixed 64 iterations with the sign bit masked off = logical shift.
	var x: int = a ^ b
	var n := 0
	for i in range(64):
		n += x & 1
		x = (x >> 1) & 0x7FFFFFFFFFFFFFFF
	return n


func _initialize() -> void:
	print("=== Cursing Gnomes undead art parity tests ===")
	_test_no_stale_sets()
	for t in UNDEAD_TYPES:
		_test_sprite(t, 0)
		_test_sprite(t, 1)
		_test_frame_pair(t)
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _test_no_stale_sets() -> void:
	for arch in STALE_ARCHETYPES:
		for fr in [0, 1]:
			var p := "assets/art/units/undead_%s_%d.png" % [arch, fr]
			_check("no stale undead set: " + p, not FileAccess.file_exists(p))


func _test_sprite(t: String, fr: int) -> void:
	var path := "assets/art/units/undead_%s_%d.png" % [t, fr]
	var label := "undead_%s_%d" % [t, fr]
	_check(label + " exists", FileAccess.file_exists(path))
	if not FileAccess.file_exists(path):
		return
	var img := Image.load_from_file(path) as Image
	_check(label + " is RGBA", img.get_format() == Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	# Animator contract: single sprite per file, 192 tall, sane width.
	_check(label + " height==192 (got %d)" % h, h == 192)
	_check(label + " width sane 90..200 (got %d)" % w, w >= 90 and w <= 200)
	# Transparency: corners fully transparent, real fill but no opaque slab.
	var corners := [
		img.get_pixel(0, 0).a, img.get_pixel(w - 1, 0).a,
		img.get_pixel(0, h - 1).a, img.get_pixel(w - 1, h - 1).a,
	]
	var corner_max := 0.0
	for c in corners:
		corner_max = maxf(corner_max, c)
	_check(label + " corners transparent", corner_max < 0.05)
	var opaque := 0
	var green := 0
	var dark := 0
	var samples := 0
	# Stride 4 keeps the run under the 300s suite timeout; still ~2.3k samples.
	for y in range(0, h, 4):
		for x in range(0, w, 4):
			samples += 1
			var c := img.get_pixel(x, y)
			if c.a < 0.5:
				continue
			opaque += 1
			# Frankenstein-green: g dominant over r and b.
			if c.g >= c.r and c.g >= c.b and c.g > 0.39 and (c.g - minf(c.r, c.b)) > 0.03:
				green += 1
			# Stitch marks / dark cloaks.
			if c.r < 0.24 and c.g < 0.24 and c.b < 0.24:
				dark += 1
	var fill := float(opaque) / float(maxi(samples, 1))
	_check(label + " fill 0.35..0.85 (got %.2f)" % fill, fill >= 0.35 and fill <= 0.85)
	var green_frac := float(green) / float(maxi(opaque, 1))
	var dark_frac := float(dark) / float(maxi(opaque, 1))
	_check(label + " green-chibi skin >=4%% (got %.1f%%)" % (green_frac * 100.0), green_frac >= 0.04)
	_check(label + " stitch/dark detail >=10%% (got %.1f%%)" % (dark_frac * 100.0), dark_frac >= 0.10)
	# No white squares: border-connected near-white pixels are bg slivers.
	_check(label + " no border white", _border_artifact_count(img) == 0)
	# Perceptual break from the old off-model art.
	if fr == 0:
		var ham_old := _ham(_dhash(img), int(OLD_HASHES[t]))
		_check(label + " differs from old off-model art (ham=%d)" % ham_old, ham_old >= 12)


func _test_frame_pair(t: String) -> void:
	var p0 := "assets/art/units/undead_%s_0.png" % t
	var p1 := "assets/art/units/undead_%s_1.png" % t
	if not (FileAccess.file_exists(p0) and FileAccess.file_exists(p1)):
		_check("undead_%s pair both exist" % t, false)
		return
	var i0 := Image.load_from_file(p0) as Image
	var i1 := Image.load_from_file(p1) as Image
	var ham := _ham(_dhash(i0), _dhash(i1))
	_check("undead_%s frames differ (ham=%d)" % [t, ham], ham >= 1)
	_check("undead_%s frames same character (ham=%d)" % [t, ham], ham <= 40)
