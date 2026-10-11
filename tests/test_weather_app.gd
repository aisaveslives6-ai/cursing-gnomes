extends SceneTree
## Cursing Gnomes — dedicated Weather app + chibi-witch default wallpaper
## (Jeremy 2026-10-04: "a dedicated Weather app on the phone" and a new
## default wallpaper — "just a chibi witch all black background with the
## little mini cursing gnomes logo on the bottom under her").
##
## Covers:
##   - HOME_APPS contains the weather app (canonical indices pinned:
##     weather at index 8, settings last at index 9) with a resolvable
##     icon texture.
##   - open_app("weather") opens the weather screen; back target is home;
##     the screen shows live PhoneWeather data (display + 7-day rows).
##   - Home weather widget tap routes to the weather app, not calendar.
##   - Witch wallpaper is the default choice on a fresh profile, resolves
##     to a real texture, and can be selected through the picker path.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_weather_app.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes weather-app / witch-wallpaper tests ===")
	_test_weather_app_registered()
	_test_weather_app_opens()
	_test_weather_app_shows_live_data()
	_test_home_widget_routes_to_weather()
	_test_witch_is_default_wallpaper()
	_test_witch_wallpaper_texture()
	_test_wallpaper_picker_lists_witch()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "phone": phone, "court": court}


func _new_ui(w: Dictionary) -> PhoneUI:
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(w["gs"], w["phone"], w["court"])
	return ui


func _collect_label_texts(ui: PhoneUI) -> Array[String]:
	var out: Array[String] = []
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out.append((n as Label).text)
		for c in n.get_children():
			stack.append(c)
	return out


func _weather_entry() -> Array:
	for a in PhoneUI.HOME_APPS:
		if String(a[0]) == "weather":
			return a
	return []


func _test_weather_app_registered() -> void:
	_check("weather app registered", not _weather_entry().is_empty())
	var e := _weather_entry()
	_check("weather label", String(e[1]) == "Weather")
	_check("weather icon path", String(e[2]) == "res://assets/ui/phone/app_weather.png")
	_check("weather icon exists", ResourceLoader.exists(String(e[2])))
	_check("weather icon loads",
		load(String(e[2])) is Texture2D)
	# Appended in order — earlier canonical grid indices are pinned by
	# test_phone_interior ("wallpaper" stays at index 6); the tail is pinned
	# here (weather at 8, settings at 9, army at 10) so future appends keep
	# the "append last" convention instead of silently reordering.
	_check("weather canonical index 8",
		String(PhoneUI.HOME_APPS[8][0]) == "weather")
	_check("settings canonical index 9",
		String(PhoneUI.HOME_APPS[9][0]) == "settings")
	_check("army canonical index 10",
		String(PhoneUI.HOME_APPS[10][0]) == "army")
	_check("rumors is last app",
		String(PhoneUI.HOME_APPS[PhoneUI.HOME_APPS.size() - 1][0]) == "rumors")
	_check("wallpaper still index 6",
		String(PhoneUI.HOME_APPS[6][0]) == "wallpaper")


func _test_weather_app_opens() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	ui.open_app("weather")
	_check("weather screen", ui.current_screen() == "weather")
	_check("weather back target home", ui._back_target_for("weather") == "home")
	ui._on_status_back()
	_check("back from weather goes home", ui.current_screen() == "home")
	ui.queue_free()
	w["gs"].queue_free()


func _test_weather_app_shows_live_data() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	ui.open_app("weather")
	var texts := _collect_label_texts(ui)
	var cur: Dictionary = PhoneWeather.current(w["gs"])
	_check("weather shows current display", String(cur["display"]) in texts)
	_check("weather shows phase/season",
		"%s · %s" % [String(cur["day_phase"]), String(cur["season"])] in texts)
	_check("weather 7-day section", "7-Day Outlook" in texts)
	var days: Array[Dictionary] = PhoneWeather.forecast_days(w["gs"], 7)
	_check("weather has 7 rows", days.size() == 7)
	for d in days:
		var sub := "%s, %d°" % [
			PhoneWeather.condition_label(String(d["condition"])),
			int(d["temp_f"])]
		_check("weather row sub " + String(d["label"]), sub in texts)
	ui.queue_free()
	w["gs"].queue_free()


func _test_home_widget_routes_to_weather() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	ui.go_home()
	# The home weather widget wrap is the only flat Button in the UI.
	# Since the 2026-10-06 home-screen scroll rework it lives inside the
	# scroll's VBox rather than as a direct child of the home root, so
	# search recursively.
	var target: Button = null
	for c: Node in ui._root.find_children("*", "Button", true, false):
		if (c as Button).flat:
			target = c as Button
			break
	_check("home weather widget button exists", target != null)
	if target != null:
		target.pressed.emit()
		_check("widget tap opens weather app", ui.current_screen() == "weather")
	ui.queue_free()
	w["gs"].queue_free()


func _test_witch_is_default_wallpaper() -> void:
	# Fresh profile: remove the persisted cfg so the default applies.
	var cfg_path := "user://bastardos.cfg"
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	var w := _new_world()
	var ui := _new_ui(w)
	_check("witch is default wallpaper", ui._wallpaper_choice == "witch")
	ui.queue_free()
	w["gs"].queue_free()


func _test_witch_wallpaper_texture() -> void:
	_check("witch wallpaper path const",
		PhoneUI.WALLPAPER_WITCH == "res://assets/ui/phone/wallpaper_witch.webp")
	_check("witch wallpaper exists",
		ResourceLoader.exists(PhoneUI.WALLPAPER_WITCH))
	var tex := load(PhoneUI.WALLPAPER_WITCH) as Texture2D
	_check("witch wallpaper loads", tex != null)
	if tex != null:
		_check("witch wallpaper portrait", tex.get_height() > tex.get_width())
	var w := _new_world()
	var ui := _new_ui(w)
	ui._set_wallpaper("witch")
	_check("set witch choice", ui._wallpaper_choice == "witch")
	_check("witch texture resolves", ui._get_wallpaper_texture() != null)
	# A bogus persisted value falls back to witch, never mountains.
	var cfg := ConfigFile.new()
	cfg.set_value("phone", "wallpaper", "bogus")
	cfg.save("user://bastardos.cfg")
	ui._load_wallpaper_choice()
	_check("bogus choice falls back to witch", ui._wallpaper_choice == "witch")
	# Restore the default for other suites sharing this user:// profile.
	ui._set_wallpaper("witch")
	ui.queue_free()
	w["gs"].queue_free()


func _test_wallpaper_picker_lists_witch() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	ui.open_app("wallpaper")
	_check("wallpaper screen", ui.current_screen() == "wallpaper")
	var texts := _collect_label_texts(ui)
	_check("witch row listed", "Witch (default)" in texts)
	_check("witch row active by default", "Active" in texts)
	ui.queue_free()
	w["gs"].queue_free()
