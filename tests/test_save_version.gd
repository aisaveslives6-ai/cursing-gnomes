extends SceneTree
## Cursing Gnomes — save-version hardening tests (launch readiness 2026-10-06).
##
## Jeremy's order: no dead ends, no silent failures. SaveSystem used to stamp
## "version": 1 and never read it back, and restore() only checked
## has("units") — a save with units:"garbage" iterated the string's
## characters and returned true; a corrupt save from the menu silently
## dropped the player into a demo world. These tests pin the fail-closed
## contract: check_save validates version + container types, restore() never
## touches game state on rejection, and last_reject_reason names the cause.


var _passed := 0
var _failed := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + name)


func _init() -> void:
	_test_version_stamp()
	_test_check_save()
	_test_restore_fail_closed()
	_test_round_trip_still_works()
	print("test_save_version: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _make_game() -> GameState:
	var g := GameState.new()
	var factions: Array[String] = []
	for f in Config.FACTIONS.keys():
		factions.append(f)
	g.setup(factions)
	return g


func _good_save() -> Dictionary:
	return SaveSystem.snapshot(_make_game())


# ------------------------------------------------------------ version stamp
func _test_version_stamp() -> void:
	var snap := _good_save()
	_check(int(snap.get("version", 0)) == SaveSystem.SAVE_VERSION,
		"snapshot stamps SAVE_VERSION")
	_check(bool(SaveSystem.check_save(snap).get("ok", false)),
		"check_save accepts a fresh snapshot")


# ------------------------------------------------------------ check_save
func _test_check_save() -> void:
	_check(not bool(SaveSystem.check_save({}).get("ok", true)),
		"check_save rejects empty dict")
	_check(str(SaveSystem.check_save({}).get("reason", "")) == "empty",
		"empty save reason is 'empty'")
	_check(not bool(SaveSystem.check_save({"nope": 1}).get("ok", true)),
		"check_save rejects missing units")
	_check(str(SaveSystem.check_save({"nope": 1}).get("reason", "")) == "missing_units",
		"missing-units reason named")

	# A save from a NEWER build must be refused, never restored blindly.
	var newer := _good_save()
	newer["version"] = SaveSystem.SAVE_VERSION + 1
	var chk := SaveSystem.check_save(newer)
	_check(not bool(chk.get("ok", true)), "check_save refuses newer-build save")
	_check(str(chk.get("reason", "")) == "newer_build",
		"newer-build reason named")

	# Legacy saves (no version key) still load — pre-launch saves are v1.
	var legacy := _good_save()
	legacy.erase("version")
	_check(bool(SaveSystem.check_save(legacy).get("ok", false)),
		"check_save accepts legacy versionless save")

	# Wrong container types: the old code iterated units:"garbage" as chars.
	for key in ["units", "buildings", "work_sites", "pickups", "zones"]:
		var bad := _good_save()
		bad[key] = "garbage"
		var c := SaveSystem.check_save(bad)
		_check(not bool(c.get("ok", true)), "check_save rejects bad " + key)
		_check(str(c.get("reason", "")) == "bad_" + key,
			"bad_" + key + " reason named")
	for key in ["towns", "next_ids"]:
		var bad := _good_save()
		bad[key] = [1, 2, 3]
		var c := SaveSystem.check_save(bad)
		_check(not bool(c.get("ok", true)), "check_save rejects bad " + key)


# ------------------------------------------------------------ restore is fail-closed
func _test_restore_fail_closed() -> void:
	# Rejection must not touch game state: no half-restored worlds.
	var g := _make_game()
	g.ruler_name = "untouched"
	g.units.append({"id": 7, "kind": "sentinel"})
	var bad := {"units": "garbage", "ruler_name": "hacker"}
	_check(not SaveSystem.restore(g, bad), "restore rejects bad units type")
	_check(g.ruler_name == "untouched",
		"rejected restore leaves ruler_name untouched")
	_check(g.units.size() == 1 and int(g.units[0].get("id", 0)) == 7,
		"rejected restore leaves units untouched")
	_check(SaveSystem.last_reject_reason() == "bad_units",
		"last_reject_reason reports bad_units")

	var newer := _good_save()
	newer["version"] = SaveSystem.SAVE_VERSION + 99
	var g2 := _make_game()
	_check(not SaveSystem.restore(g2, newer), "restore refuses newer build")
	_check(SaveSystem.last_reject_reason() == "newer_build",
		"last_reject_reason reports newer_build")

	# A good restore clears the reject reason.
	var g3 := _make_game()
	_check(SaveSystem.restore(g3, _good_save()), "restore accepts good save")
	_check(SaveSystem.last_reject_reason() == "",
		"successful restore clears reject reason")


# ------------------------------------------------------------ round-trip intact
func _test_round_trip_still_works() -> void:
	var g := _make_game()
	g.ruler_name = "ass"  # verbatim law: never trimmed, never altered
	var snap := SaveSystem.snapshot(g)
	var g2 := _make_game()
	_check(SaveSystem.restore(g2, snap), "round-trip restore succeeds")
	_check(g2.ruler_name == "ass", "ruler name survives round-trip verbatim")
