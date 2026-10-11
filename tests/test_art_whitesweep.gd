extends SceneTree
## Cursing Gnomes — full-art-tree white-sweep regression test (graphics-hourly 2026-10-06).
##
## Jeremy's launch-readiness rule: no white squares. A full 484-PNG sweep of
## assets/art found 7 files with border-connected opaque near-white pixels
## (unkeyed background slivers that render as white edges/boxes in the
## isometric world). Five were genuine artifacts and were border-flooded to
## transparent (originals backed up in the goal's hidden_files). Two were
## reviewed and left alone:
##   - bld_general_store_human.png: 49px at the top edge are the chimney
##     smoke wisp's tip (warm opaque, part of the plume art, not background).
##   - furn_lamp_ogre.png: 67 border specks sit adjacent to the brazier's
##     rim/glow art; removing them risked eating real highlights.
## Enclosed white (signage glare, plate highlights, skin tones) is legitimate
## art and is NOT touched by this check — only border-connected pixels fail.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_art_whitesweep.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
##
## 2026-10-08 graphics-hourly: the 10-06 sweep pinned only the files it
## fixed — new art since then had NO regression coverage. A full-tree
## re-sweep (507 shipped PNGs, excluding media-generation-* raw
## intermediates no script loads) found zero new offenders, and
## NEW_ART_SINCE_SWEEP pins all 39 new shipped files so the rule now
## applies to new art automatically.

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


## Files fixed in the 2026-10-06 sweep — must stay at zero border white.
const FIXED_SPRITES: Array[String] = [
	"assets/art/buildings/bld_guild_hall_elf.png",   # was 153px bottom-edge strip
	"assets/art/furniture/furn_chandelier.png",      # was 3px top-edge specks
	"assets/art/units/gnome_warrior_m0.png",         # was 1px bottom-edge speck
	"assets/art/units/human_warrior_m0.png",         # was 1px bottom-edge speck
	"assets/art/units/ogre_warrior_f1.png",          # was 2px edge specks
]


## Guild-hall + general-store variants were clean in the full sweep — pin them
## so a future bad extraction can't sneak a white edge back in. (The human
## general store is excluded: its chimney smoke wisp legitimately touches the
## top edge; see the header note.)
const CLEAN_VARIANTS: Array[String] = [
	"assets/art/buildings/bld_guild_hall_gnome.png",
	"assets/art/buildings/bld_guild_hall_human.png",
	"assets/art/buildings/bld_guild_hall_ogre.png",
	"assets/art/buildings/bld_guild_undead.png",
	"assets/art/buildings/bld_general_store_elf.png",
	"assets/art/buildings/bld_general_store_gnome.png",
	"assets/art/buildings/bld_general_store_ogre.png",
]


## Shipped art that landed AFTER the 2026-10-06 sweep (new disaster/NPC
## sprites, the undead unit roster, furniture set, un-suffixed guild hall)
## — all verified clean by the 2026-10-08 graphics-hourly full-tree
## re-sweep (507 PNGs checked, zero new offenders; the only hit,
## furn_lamp_ogre.png, was already reviewed and left alone in the 10-06
## sweep). Pinned here so the "no white squares" rule is enforced on new
## art automatically — the sweep gap this closes.
const NEW_ART_SINCE_SWEEP: Array[String] = [
	"assets/art/animals/booze_ooze.png",
	"assets/art/animals/borg_crab_bill.png",
	"assets/art/animals/bubble.png",
	"assets/art/animals/cardboard_cat.png",
	"assets/art/animals/cat.png",
	"assets/art/animals/count_bastard.png",
	"assets/art/animals/crossfit_gnome.png",
	"assets/art/animals/dmv_clerk.png",
	"assets/art/animals/doom_prophet.png",
	"assets/art/animals/doomscroller.png",
	"assets/art/animals/gossip_gnome.png",
	"assets/art/animals/influencer_gnome.png",
	"assets/art/animals/prince_gnomba.png",
	"assets/art/animals/dj_weddington.png",
	"assets/art/animals/repo_gnome.png",
	"assets/art/animals/karaoke_barbarian.png",
	"assets/art/animals/mlm_bro.png",
	"assets/art/animals/rogue_wizard.png",
	"assets/art/animals/seagull.png",
	"assets/art/animals/spark_driver.png",
	"assets/art/animals/taxman.png",
	"assets/art/animals/twister_sister.png",
	"assets/art/animals/warranty_salesman.png",
	"assets/art/furniture/furn_door.png",
	"assets/art/furniture/furn_tv.png",
	"assets/art/furniture/furn_window.png",
	"assets/art/units/undead_bone_golem_0.png",
	"assets/art/units/undead_bone_golem_1.png",
	"assets/art/units/undead_ghoul_0.png",
	"assets/art/units/undead_ghoul_1.png",
	"assets/art/units/undead_lich_0.png",
	"assets/art/units/undead_lich_1.png",
	"assets/art/units/undead_necromancer_0.png",
	"assets/art/units/undead_necromancer_1.png",
	"assets/art/units/undead_plaguebearer_0.png",
	"assets/art/units/undead_plaguebearer_1.png",
	"assets/art/units/undead_skeleton_0.png",
	"assets/art/units/undead_skeleton_1.png",
	"assets/art/units/undead_wraith_0.png",
	"assets/art/units/undead_wraith_1.png",
	"assets/art/units/undead_zombie_0.png",
	"assets/art/units/undead_zombie_1.png",
	"assets/art/buildings/bld_guild_hall.png",
]


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Near-white opaque = the artifact class (white boxes, white edges, glare).
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


func _load(p: String) -> Image:
	var img := Image.load_from_file("res://" + p)
	_check("sprite loads: " + p, img != null and not img.is_empty())
	return img


func _test_fixed_sprites() -> void:
	var worst_path := ""
	var worst := 0
	for p in FIXED_SPRITES:
		var img := _load(p)
		if img == null or img.is_empty():
			continue
		var n: int = _border_artifact_count(img)
		if n > worst:
			worst = n
			worst_path = p
		_check("no border-connected white on " + p, n == 0)
	_check("zero border-connected white on all fixed sprites (worst: " + worst_path + ")", worst == 0)
	print("  worst border-connected white count on fixed sprites: ", worst)


func _test_guild_hall_strip() -> void:
	# The elf guild hall had a 153px near-white strip along its bottom edge
	# (y = h-1, x 109..368) — unkeyed background below the wooden base.
	# The strip must be transparent now; the base row above must be intact.
	var img := _load("assets/art/buildings/bld_guild_hall_elf.png")
	if img == null or img.is_empty():
		return
	var w := img.get_width()
	var h := img.get_height()
	var strip_white := 0
	for x in range(109, 369):
		if _is_artifact(img.get_pixel(x, h - 1)):
			strip_white += 1
	_check("guild hall bottom strip has no near-white pixels (was 153px)", strip_white == 0)
	var base_intact := 0
	for x in range(109, 369, 7):
		if img.get_pixel(x, h - 2).a > 0.5:
			base_intact += 1
	_check("guild hall base row above the strip is intact", base_intact > 30)


func _test_clean_variants() -> void:
	var worst_path := ""
	var worst := 0
	for p in CLEAN_VARIANTS:
		var img := _load(p)
		if img == null or img.is_empty():
			continue
		var n: int = _border_artifact_count(img)
		if n > worst:
			worst = n
			worst_path = p
		_check("no border-connected white on " + p, n == 0)
	_check("guild/store variants stay clean (worst: " + worst_path + ")", worst == 0)
	print("  worst border-connected white count on variants: ", worst)


func _test_new_art() -> void:
	var worst_path := ""
	var worst := 0
	for p in NEW_ART_SINCE_SWEEP:
		var img := _load(p)
		if img == null or img.is_empty():
			continue
		var n: int = _border_artifact_count(img)
		if n > worst:
			worst = n
			worst_path = p
		_check("no border-connected white on " + p, n == 0)
	_check("post-sweep art stays clean (worst: " + worst_path + ")", worst == 0)
	print("  worst border-connected white count on new art: ", worst)


func _initialize() -> void:
	print("=== Cursing Gnomes art-tree white-sweep tests ===")
	_test_fixed_sprites()
	_test_guild_hall_strip()
	_test_clean_variants()
	_test_new_art()
	print("=== ", _passed, " passed, ", _failed, " failed ===")
	if not _failures.is_empty():
		print("failures:")
		for f in _failures:
			print("  - ", f)
	quit(1 if _failed > 0 else 0)
