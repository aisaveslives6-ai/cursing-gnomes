extends SceneTree
## Cursing Gnomes — food-economy feedback tests (Jeremy 2026-10-07 wake lane:
## "the food economy talks back" — the farm/ranch/trade bus signals fired
## into the void; nothing sounded, nobody reported).
##
## Covers:
##   SimFoodFeedback (scripts/sim/food_feedback.gd):
##   - daily tallies: farm_harvested + animal_yield accumulate per faction
##   - player digest: Civic Adviser sends ONE Messenger note per game-day
##     when the player's farms produced food; silent on empty days
##   - Gazette: BUMPER HARVEST at >= 2000 faction-day food (kind "news",
##     never "war"); LIVESTOCK BLIGHT at >= 6 faction-day animal deaths;
##     each fires at most once per faction per day
##   - save/load round-trip preserves tallies and day guards
##   WorldFarmSfx (scripts/world/farm_sfx.gd):
##   - farm_harvested / animal_yield -> "harvest" at the plot, throttled
##     (4 per 1 s game-time bucket)
##   - farm_plot_created / animals_stocked -> "place" at the plot
##   - trade_done -> "coin" at the caravan; silent when off-map
##   - animal_died -> no sound
##   AudioManager: the new "harvest" sound synthesizes to real audio data.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_food_feedback.gd
##
## Exit code 0 = all passed, 1 = any failure.


class CourtStub:
	extends RefCounted
	var stories: Array = []  # [headline, body, kind]

	func publish_story(headline: String, body: String,
			kind: String = "default") -> Dictionary:
		stories.append([headline, body, kind])
		return {}


class PhoneStub:
	extends RefCounted
	var dms: Array = []  # [advisor_id, text]

	func npc_message(advisor_id: int, text: String) -> void:
		dms.append([advisor_id, text])


class IndustryStub:
	extends RefCounted
	var funky_on_map := true
	var funky_pos := Vector2(500, 600)


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _sfx: Array = []  # [name, pos] records from bus.sfx_spatial


func _initialize() -> void:
	print("=== Cursing Gnomes food-feedback tests ===")
	_test_digest_sent_once_per_day()
	_test_digest_silent_on_empty_day()
	_test_digest_needs_adviser()
	_test_bumper_harvest_gazette()
	_test_bumper_below_threshold_silent()
	_test_bumper_once_per_day()
	_test_blight_gazette()
	_test_blight_below_threshold_silent()
	_test_save_load()
	_test_harvest_sound_at_plot()
	_test_harvest_sound_throttle()
	_test_plot_created_and_stocked_sound()
	_test_trade_sound_at_caravan()
	_test_trade_silent_offmap()
	_test_animal_died_silent()
	_test_harvest_synth_exists()
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


func _new_game() -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "elves"] as Array[String])
	_sfx.clear()
	gs.bus.sfx_spatial.connect(_on_sfx)
	return gs


func _on_sfx(sfx_name: String, pos: Vector2, _vel: Vector2) -> void:
	_sfx.append([sfx_name, pos])


func _sfx_names() -> Array:
	var out: Array = []
	for r: Array in _sfx:
		out.append(r[0])
	return out


## GameState + farming + a real plot + feedback module + stubs.
func _food_game() -> Array:
	var gs := _new_game()
	gs.farming = SimFarming.new(gs)
	var plot: Dictionary = gs.farming.create_plot(
		"humans", Vector2(100, 200), -1, true)
	var fb := SimFoodFeedback.new(gs)
	var court := CourtStub.new()
	gs.court_sys = court
	var phone := PhoneStub.new()
	gs.phone_sys = phone
	return [gs, plot, fb, court, phone]


func _add_civic_adviser(gs: GameState) -> Dictionary:
	return gs.add_unit({
		"faction": "humans", "job": "advisor_civic", "town_id": -1,
		"position": Vector2(10, 10), "alive": true,
		"hp": 100.0, "max_hp": 100.0,
	})


## --- SimFoodFeedback: digest ------------------------------------------------


func _test_digest_sent_once_per_day() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var phone: PhoneStub = parts[4]
	_add_civic_adviser(gs)
	var pid := int(plot.get("id", 0))
	gs.bus.farm_harvested.emit(pid, 80.0, 2.0)
	gs.bus.animal_yield.emit(pid, "humans", 30.0)
	gs.bus.day_changed.emit(1, false)
	_check("digest: one DM sent", phone.dms.size() == 1)
	var text: String = phone.dms[0][1]
	_check("digest: mentions field food", text.contains("80"))
	_check("digest: mentions livestock food", text.contains("30"))
	_check("digest: from the adviser",
		int(phone.dms[0][0]) > 0)
	# Second day_changed for the SAME day number: no duplicate.
	gs.bus.day_changed.emit(1, false)
	_check("digest: no duplicate same day", phone.dms.size() == 1)
	# Next day with a fresh harvest: new digest.
	gs.bus.farm_harvested.emit(pid, 60.0, 1.0)
	gs.bus.day_changed.emit(2, false)
	_check("digest: new day new digest", phone.dms.size() == 2)
	gs.free()


func _test_digest_silent_on_empty_day() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var phone: PhoneStub = parts[4]
	_add_civic_adviser(gs)
	gs.bus.day_changed.emit(1, false)
	_check("digest: silent when nothing harvested", phone.dms.is_empty())
	gs.free()


func _test_digest_needs_adviser() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var phone: PhoneStub = parts[4]
	# No civic adviser unit exists: the harvest is real but nobody reports.
	gs.bus.farm_harvested.emit(int(plot.get("id", 0)), 80.0, 2.0)
	gs.bus.day_changed.emit(1, false)
	_check("digest: no adviser no DM", phone.dms.is_empty())
	gs.free()


## --- SimFoodFeedback: Gazette ------------------------------------------------


func _test_bumper_harvest_gazette() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var court: CourtStub = parts[3]
	# No adviser on purpose: Gazette must not depend on the cabinet.
	var pid := int(plot.get("id", 0))
	for i in 25:
		gs.bus.farm_harvested.emit(pid, 80.0, 2.0)  # 2000 total
	gs.bus.day_changed.emit(1, false)
	var heads: Array = []
	for s: Array in court.stories:
		heads.append(s[0])
	_check("bumper: story published", heads.has("BUMPER HARVEST"))
	var kind := ""
	for s: Array in court.stories:
		if s[0] == "BUMPER HARVEST":
			kind = String(s[2])
	_check("bumper: kind is news not war", kind == "news")
	gs.free()


func _test_bumper_below_threshold_silent() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var court: CourtStub = parts[3]
	var pid := int(plot.get("id", 0))
	for i in 24:
		gs.bus.farm_harvested.emit(pid, 80.0, 2.0)  # 1920 < 2000
	gs.bus.day_changed.emit(1, false)
	var heads: Array = []
	for s: Array in court.stories:
		heads.append(s[0])
	_check("bumper: silent below 2000", not heads.has("BUMPER HARVEST"))
	gs.free()


func _test_bumper_once_per_day() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var court: CourtStub = parts[3]
	var pid := int(plot.get("id", 0))
	for i in 50:
		gs.bus.farm_harvested.emit(pid, 80.0, 2.0)  # 4000: still one story
	gs.bus.day_changed.emit(1, false)
	var n := 0
	for s: Array in court.stories:
		if s[0] == "BUMPER HARVEST":
			n += 1
	_check("bumper: one story per faction per day", n == 1)
	gs.free()


func _test_blight_gazette() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var court: CourtStub = parts[3]
	var pid := int(plot.get("id", 0))
	for i in 6:
		gs.bus.animal_died.emit(pid, 100 + i, "starvation", "cow")
	gs.bus.day_changed.emit(1, false)
	var heads: Array = []
	for s: Array in court.stories:
		heads.append(s[0])
	_check("blight: story published", heads.has("LIVESTOCK BLIGHT"))
	var kind := ""
	for s: Array in court.stories:
		if s[0] == "LIVESTOCK BLIGHT":
			kind = String(s[2])
	_check("blight: kind is news not war", kind == "news")
	gs.free()


func _test_blight_below_threshold_silent() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var court: CourtStub = parts[3]
	var pid := int(plot.get("id", 0))
	for i in 5:
		gs.bus.animal_died.emit(pid, 100 + i, "starvation", "cow")
	gs.bus.day_changed.emit(1, false)
	var heads: Array = []
	for s: Array in court.stories:
		heads.append(s[0])
	_check("blight: silent below 6 deaths", not heads.has("LIVESTOCK BLIGHT"))
	gs.free()


func _test_save_load() -> void:
	var parts := _food_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var pid := int(plot.get("id", 0))
	for i in 25:
		gs.bus.farm_harvested.emit(pid, 80.0, 2.0)
	var data: Dictionary = (parts[2] as SimFoodFeedback).to_dict()
	# Fresh module, restored mid-day, must still headline on day change.
	var gs2 := _new_game()
	gs2.farming = SimFarming.new(gs2)
	var fb2 := SimFoodFeedback.new(gs2)
	fb2.from_dict(data)
	var court2 := CourtStub.new()
	gs2.court_sys = court2
	gs2.bus.day_changed.emit(1, false)
	var heads: Array = []
	for s: Array in court2.stories:
		heads.append(s[0])
	_check("save/load: bumper survives round-trip", heads.has("BUMPER HARVEST"))
	gs.free()
	gs2.free()


## --- WorldFarmSfx -------------------------------------------------------------


func _sfx_game() -> Array:
	var gs := _new_game()
	gs.farming = SimFarming.new(gs)
	var plot: Dictionary = gs.farming.create_plot(
		"humans", Vector2(100, 200), -1, true)
	_sfx.clear()  # create_plot's own farm_plot_created sound is not under test
	var wfs := WorldFarmSfx.new(gs)
	return [gs, plot, wfs]


func _test_harvest_sound_at_plot() -> void:
	var parts := _sfx_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	gs.bus.farm_harvested.emit(int(plot.get("id", 0)), 80.0, 2.0)
	_check("sfx: harvest sounded", _sfx_names().has("harvest"))
	var at: Vector2 = _sfx[_sfx.size() - 1][1]
	_check("sfx: harvest at plot pos",
		at.distance_to(Vector2(100, 200)) < 1.0)
	gs.free()


func _test_harvest_sound_throttle() -> void:
	var parts := _sfx_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	gs.game_time = 500.0
	var pid := int(plot.get("id", 0))
	for i in 6:
		gs.bus.farm_harvested.emit(pid, 80.0, 2.0)
	var n := 0
	for r: Array in _sfx:
		if r[0] == "harvest":
			n += 1
	_check("sfx: harvest throttled to 4 per 1s bucket", n == 4)
	# Next bucket: sounds flow again.
	gs.game_time = 501.5
	gs.bus.farm_harvested.emit(pid, 80.0, 2.0)
	var m := 0
	for r: Array in _sfx:
		if r[0] == "harvest":
			m += 1
	_check("sfx: throttle resets next bucket", m == 5)
	gs.free()


func _test_plot_created_and_stocked_sound() -> void:
	var parts := _sfx_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	var pid := int(plot.get("id", 0))
	gs.bus.farm_plot_created.emit({"id": pid, "position": Vector2(300, 400)})
	_check("sfx: plot created -> place", _sfx_names().has("place"))
	gs.bus.animals_stocked.emit(pid, "barn", ["cow", "pig"])
	var names := _sfx_names()
	_check("sfx: stocked -> place", names.count("place") == 2)
	gs.free()


func _test_trade_sound_at_caravan() -> void:
	var parts := _sfx_game()
	var gs: GameState = parts[0]
	gs.industry = IndustryStub.new()
	gs.bus.trade_done.emit("humans", "wood", "gold", 50.0, 10.0)
	_check("sfx: trade -> coin", _sfx_names().has("coin"))
	var at: Vector2 = _sfx[_sfx.size() - 1][1]
	_check("sfx: coin at caravan pos",
		at.distance_to(Vector2(500, 600)) < 1.0)
	gs.free()


func _test_trade_silent_offmap() -> void:
	var parts := _sfx_game()
	var gs: GameState = parts[0]
	var ind := IndustryStub.new()
	ind.funky_on_map = false
	gs.industry = ind
	gs.bus.trade_done.emit("humans", "wood", "gold", 50.0, 10.0)
	_check("sfx: no coin when caravan off-map",
		not _sfx_names().has("coin"))
	gs.free()


func _test_animal_died_silent() -> void:
	var parts := _sfx_game()
	var gs: GameState = parts[0]
	var plot: Dictionary = parts[1]
	gs.bus.animal_died.emit(int(plot.get("id", 0)), 101, "starvation", "cow")
	_check("sfx: animal death stays silent", _sfx.is_empty())
	gs.free()


func _test_harvest_synth_exists() -> void:
	var am := AudioManager.new()
	var wav: AudioStreamWAV = am._synthesize_sfx("harvest")
	_check("audio: harvest synthesizes", wav != null)
	_check("audio: harvest has data",
		wav != null and wav.data.size() > 0)
	am.free()
