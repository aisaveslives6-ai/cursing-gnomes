extends SceneTree
## Cursing Gnomes — Squabble overhaul tests (Jeremy 2026-10-06).
## Covers: avatar key resolution (singular faction names), no double
## plurals in faction names, no variation selectors in post text.

var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("FAIL: ", label)


func _init() -> void:
	var Phone = load("res://scripts/sim/phone.gd")

	# 1. Avatar keys use singular faction names matching actual files.
	var expected := {
		"humans": "portrait_human_",
		"elves": "portrait_elf_",
		"ogres": "portrait_ogre_",
		"gnomes": "portrait_gnome_",
	}
	for f: String in expected.keys():
		var key: String = Phone.pfp_key_for({"faction": f, "id": 42})
		_check(key.begins_with(expected[f]),
			"pfp key for %s starts with %s (got %s)" % [f, expected[f], key])
		# No plural faction id leaking into the key.
		_check(not ("humans" in key or "elves" in key or "ogres" in key
				or "gnomes" in key),
			"pfp key for %s has no plural faction (got %s)" % [f, key])

	# 2. Undead get a real portrait from the pool, never a "?" key.
	var ukey: String = Phone.pfp_key_for({"faction": "undead", "id": 7})
	_check(ukey != "" and ukey != "?", "undead pfp key is real (got %s)" % ukey)

	# 3. No variation selectors (U+FE0F) in hearsay post lines — tofu risk.
	var hsrc: String = FileAccess.get_file_as_string(
		"res://scripts/sim/hearsay.gd")
	_check(not "\ufe0f" in hsrc, "no U+FE0F in hearsay.gd")

	# 4. No variation selectors in other post-generating sim files.
	for p: String in ["res://scripts/sim/policies.gd",
			"res://scripts/sim/diplomacy.gd"]:
		var psrc: String = FileAccess.get_file_as_string(p)
		_check(not "\ufe0f" in psrc, "no U+FE0F in %s" % p)

	# 5. Faction display names are proper plurals (no double-s when used).
	var Config = load("res://scripts/core/config.gd")
	var want := {"humans": "Humans", "elves": "Elves", "ogres": "Ogres",
		"gnomes": "Gnomes", "undead": "Undead"}
	for f: String in want.keys():
		var nm: String = String(Config.FACTIONS.get(f, {}).get("name", ""))
		_check(nm == want[f],
			"faction %s display name is %s (got %s)" % [f, want[f], nm])

	# 6. War line templates use {f} without a trailing "s" (would double-plural).
	var wsrc: String = FileAccess.get_file_as_string(
		"res://scripts/sim/hearsay.gd")
	_check(not "{f}s" in wsrc, "no {f}s double-plural pattern in hearsay.gd")

	print("=== %d passed, %d failed ===" % [_passed, _failed])
	quit(_failed)
