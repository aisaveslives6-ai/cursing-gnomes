extends SceneTree
## Cursing Gnomes — game-speed selector tests (2026-10-05, updated 2026-10-07,
## 2026-10-08).
##
## Jeremy asked to slow in-game time (believing it'll free performance).
## The system menu's Speed button cycles 1x -> 0.5x -> 0.25x -> 0.125x -> 2x -> 1x via
## Engine.time_scale (scales every delta: sim, animation, tweens — and
## 0.5x literally halves sim CPU per real second; 0.25x quarters it,
## 0.125x eighths it).
## The slowdowns come FIRST because Jeremy asked for the slowdown (thermal
## relief) — 0.5x one tap away, the 0.25x "turtle" two taps away, the 0.125x
## "deep turtle" three taps away, ahead of 2x. 2026-10-08: "slow in-game time
## further" is why the turtle was added; 2026-10-09: he asked to slow it
## further AGAIN, hence the deep turtle.
##
## 2026-10-07: the speed is now a PERSISTENT preference. Main Menu >
## Settings > Game Speed writes user://settings.json; a fresh HUD restores
## the saved speed on world entry (announced once via a hint so it's never
## a surprise); the in-game Speed button cycles AND persists. Hand-edited
## junk values fall back to 1x. _reset_game_speed still normalizes the
## transient scale on menu/worlds transitions (menus have no HUD).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_game_speed.gd
##
## Exit code 0 = all passed, 1 = any failure.


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


func _tmp_settings() -> String:
	var p := "user://test_game_speed_tmp.json"
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)
	return p


func _write_settings(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read_speed(path: String) -> Variant:
	var disk := GraphicsTiers.read_user_settings_at(path)
	return disk.get("game_speed", "<absent>")


func _initialize() -> void:
	print("=== Cursing Gnomes game-speed tests ===")
	var tmp := _tmp_settings()

	# 1. No settings file -> default 1.0 everywhere.
	var hud := Hud.new()
	hud._settings_path_override = tmp
	root.add_child(hud)
	hud._build_system_menu()
	_check("no settings: speed defaults 1.0", hud._game_speed == 1.0)
	_check("no settings: engine scale is 1.0", Engine.time_scale == 1.0)
	_check("no settings: label is Speed: 1x",
		hud._speed_button != null and hud._speed_button.text == "Speed: 1x")

	# 2. Cycle order: 1x -> 0.5x -> 0.25x -> 0.125x -> 2x -> 1x.
	hud._cycle_game_speed()
	_check("cycle 1x -> 0.5x", hud._game_speed == 0.5)
	_check("engine scale follows to 0.5", Engine.time_scale == 0.5)
	_check("label shows Speed: 0.5x", hud._speed_button.text == "Speed: 0.5x")
	hud._cycle_game_speed()
	_check("cycle 0.5x -> 0.25x (turtle)", hud._game_speed == 0.25)
	_check("engine scale follows to 0.25", Engine.time_scale == 0.25)
	_check("label shows Speed: 0.25x", hud._speed_button.text == "Speed: 0.25x")
	hud._cycle_game_speed()
	_check("cycle 0.25x -> 0.125x (deep turtle)", hud._game_speed == 0.125)
	_check("engine scale follows to 0.125", Engine.time_scale == 0.125)
	_check("label shows Speed: 0.125x", hud._speed_button.text == "Speed: 0.125x")
	hud._cycle_game_speed()
	_check("cycle 0.125x -> 2x", hud._game_speed == 2.0)
	_check("engine scale follows to 2.0", Engine.time_scale == 2.0)
	_check("label shows Speed: 2x", hud._speed_button.text == "Speed: 2x")
	hud._cycle_game_speed()
	_check("cycle wraps 2x -> 1x", hud._game_speed == 1.0)
	_check("engine scale back to 1.0", Engine.time_scale == 1.0)
	_check("label back to Speed: 1x", hud._speed_button.text == "Speed: 1x")

	# 3. Cycling persists the preference (merge keeps other keys).
	_write_settings(tmp, '{"graphics": "low", "game_speed": 1.0}')
	hud._cycle_game_speed()  # 1x -> 0.5x
	_check("cycle persists 0.5 to settings file", _read_speed(tmp) == 0.5)
	var disk := GraphicsTiers.read_user_settings_at(tmp)
	_check("persist merges, keeps other keys", disk.get("graphics") == "low")

	# 4. A fresh HUD restores the saved speed (the 2026-10-07 contract).
	Engine.time_scale = 1.0
	var hud2 := Hud.new()
	hud2._settings_path_override = tmp
	root.add_child(hud2)
	hud2._build_system_menu()
	_check("fresh hud restores saved 0.5", hud2._game_speed == 0.5)
	_check("fresh hud applies engine scale 0.5", Engine.time_scale == 0.5)
	_check("fresh hud label is Speed: 0.5x",
		hud2._speed_button != null and hud2._speed_button.text == "Speed: 0.5x")

	# 5. Cycling from a restored speed wraps correctly (0.5x -> 0.25x).
	hud2._cycle_game_speed()
	_check("restored 0.5x cycles to 0.25x", hud2._game_speed == 0.25)
	_check("label shows Speed: 0.25x", hud2._speed_button.text == "Speed: 0.25x")
	_check("cycle persists 0.25", _read_speed(tmp) == 0.25)
	# ...and 0.25x cycles on to 0.125x, then 2x (slowdowns stay ahead of fast).
	hud2._cycle_game_speed()
	_check("0.25x cycles to 0.125x (deep turtle)", hud2._game_speed == 0.125)
	_check("label shows Speed: 0.125x", hud2._speed_button.text == "Speed: 0.125x")
	hud2._cycle_game_speed()
	_check("0.125x cycles to 2x", hud2._game_speed == 2.0)
	_check("label shows Speed: 2x", hud2._speed_button.text == "Speed: 2x")

	# 6. Hand-edited junk falls back to 1x.
	_write_settings(tmp, '{"game_speed": 3.7}')
	var hud3 := Hud.new()
	hud3._settings_path_override = tmp
	root.add_child(hud3)
	hud3._build_system_menu()
	_check("junk value falls back to 1.0", hud3._game_speed == 1.0)
	_check("junk value resets engine scale", Engine.time_scale == 1.0)
	hud3.queue_free()

	# 7. Leaving to the menu still resets the transient scale.
	_write_settings(tmp, '{"graphics": "low", "game_speed": 0.5}')
	hud2._reset_game_speed()
	_check("menu reset restores 1.0", hud2._game_speed == 1.0)
	_check("menu reset restores engine scale", Engine.time_scale == 1.0)
	_check("menu reset restores label", hud2._speed_button.text == "Speed: 1x")
	# ...but the saved preference is untouched by the transient reset.
	_check("menu reset does not clobber saved pref", _read_speed(tmp) == 0.5)

	hud.queue_free()
	hud2.queue_free()
	Engine.time_scale = 1.0
	DirAccess.remove_absolute(tmp)
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
