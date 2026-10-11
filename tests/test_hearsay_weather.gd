extends SceneTree
## Cursing Gnomes — hearsay weather-arrival gossip tests (Jeremy 2026-10-10).
##
## bus.weather_changed was a deaf thread: storms broke, rain fell, and snow
## came down while the mill heard nothing. Forecasts gossip about INCOMING
## disasters and the seasons cover the turning year — the ARRIVAL itself
## was the gap. Now:
##  - storm/rain/snow arrivals seed a RICH kind-"weather" rumor
##    (subject "weather:<kind>", shared per kind so a stormy stretch
##    refreshes one rumor instead of spamming); TRUTH_TRUE, knower -1
##    (everybody saw the sky); heat 0.65 / 0.55 / 0.45 — all tavern talk
##  - hard gates: clear/cloudy/fog arrivals stay quiet (routine skies
##    aren't gossip)
##  - Squabble first-person posts mark the arrival, on the fresh seed only
##  - press_ok=false + PRESS_EXCLUDE_KINDS + heat < PRESS_HEAT: never the
##    front page; storm sits under QUEST_HEAT (no advisor proposal)
##  - the weather reaction matrix: storms dread most (storm_dread,
##    dismayed), farmers fear for the crops (storm_crops, disaster,
##    deeper); the unhinged LOVE a storm (storm_thrill, cheerful, glee);
##    rain blesses the farmers (rain_blessing) and comforts the rest
##    (rain_news); snow dreads (snow_dread) with farmers counting the
##    stores (snow_stores). Unhinged x1.5.
##  - spread motivation: storm warnings are neighborly duty (+1/+0.05),
##    snow talk travels like winter talk (+1/0), rain is idle sky-talk
##  - weather joins the doubt-immune club (the storm broke overhead —
##    everybody saw the sky) and crosses borders like the seasons do
##  - all 7 new memory types registered in SimMemories.TYPES with weights
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_hearsay_weather.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes hearsay weather-arrival gossip tests ===")
	_test_storm_arrival_seeds_rumor()
	_test_rain_arrival_seeds_rumor()
	_test_snow_arrival_seeds_rumor()
	_test_quiet_skies_seed_nothing()
	_test_repeat_storm_refreshes_not_duplicates()
	_test_below_press_heat()
	_test_below_quest_heat()
	_test_storm_dread()
	_test_farmer_fears_crops_deeper()
	_test_unhinged_thrilled_by_storm()
	_test_unhinged_amplified()
	_test_rain_farmer_blessing()
	_test_rain_neutral_comfort()
	_test_snow_dread()
	_test_snow_farmer_stores_deeper()
	_test_spread_motivation()
	_test_memory_types_registered()
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


func _new_gs() -> GameState:
	var gs = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	gs.setup(farr)
	gs.player_faction = "gnomes"
	gs.set_ruler_name("ass")
	return gs


func _harness() -> Array:
	var gs := _new_gs()
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return [gs, phone, phone.hearsay]


func _spawn(gs: GameState, faction: String, props: Dictionary = {}) -> Dictionary:
	var d := {"faction": faction, "alive": true}
	for k: String in props.keys():
		d[k] = props[k]
	var u: Dictionary = gs.add_unit(d)
	u["position"] = Vector2.ZERO
	return u


func _unhinged_mind() -> Dictionary:
	return {"traits": {"unhinged": 1.0}}


func _emit(gs: GameState, kind: String) -> void:
	gs.bus.weather_changed.emit(kind)


func _rumor(hs, subject: String) -> Dictionary:
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "weather" \
				and String(r.get("subject", "")) == subject:
			return r
	return {}


func _count_weather(hs) -> int:
	var n := 0
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "weather":
			n += 1
	return n


func _recalled(u: Dictionary, mtype: String, subject_id: int) -> float:
	var mems: Array = u.get("memories", [])
	for m: Dictionary in mems:
		if String(m.get("type", "")) == mtype \
				and int(m.get("subject_id", 0)) == subject_id:
			return float(m.get("strength", 0.0))
	return 0.0


func _emotion(u: Dictionary) -> String:
	return String(u.get("emotion", {}).get("name", "neutral"))


func _test_storm_arrival_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "storm")
	var r := _rumor(hs, "weather:storm")
	_check("storm arrival seeds a rumor", not r.is_empty())
	_check("subject keys the kind",
		String(r.get("subject", "")) == "weather:storm")
	_check("storm arrival is confirmed fact",
		String(r.get("truth", "")) == hs.TRUTH_TRUE)
	_check("storm heat is tavern talk",
		is_equal_approx(float(r.get("heat", 0.0)), 0.65))
	_check("kind recorded", String(r.get("weather_kind", "")) == "storm")
	_check("storm never reaches the press",
		not bool(r.get("press_ok", true)))
	_check("text names the storm",
		String(r.get("text", "")).to_lower().find("storm") >= 0)


func _test_rain_arrival_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "rain")
	var r := _rumor(hs, "weather:rain")
	_check("rain arrival seeds a rumor", not r.is_empty())
	_check("rain heat is quiet",
		is_equal_approx(float(r.get("heat", 0.0)), 0.45))
	_check("kind recorded", String(r.get("weather_kind", "")) == "rain")


func _test_snow_arrival_seeds_rumor() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "snow")
	var r := _rumor(hs, "weather:snow")
	_check("snow arrival seeds a rumor", not r.is_empty())
	_check("snow heat is middling",
		is_equal_approx(float(r.get("heat", 0.0)), 0.55))
	_check("kind recorded", String(r.get("weather_kind", "")) == "snow")


func _test_quiet_skies_seed_nothing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "clear")
	_emit(gs, "cloudy")
	_emit(gs, "fog")
	_check("clear/cloudy/fog arrivals stay quiet", _count_weather(hs) == 0)


func _test_repeat_storm_refreshes_not_duplicates() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "storm")
	_emit(gs, "storm")
	_check("a stormy stretch shares one rumor", _count_weather(hs) == 1)
	var r := _rumor(hs, "weather:storm")
	r["heat"] = 0.2  # simulate daily decay between storms
	_emit(gs, "storm")
	_check("repeat storm refreshes cooled heat",
		is_equal_approx(float(r.get("heat", 0.0)), 0.65))


func _test_below_press_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "storm")
	_emit(gs, "rain")
	_emit(gs, "snow")
	for r: Dictionary in hs.state["rumors"]:
		if String(r.get("kind", "")) == "weather":
			_check("weather never reaches the press",
				float(r.get("heat", 0.0)) < hs.PRESS_HEAT)
	_check("weather is press-excluded",
		hs.PRESS_EXCLUDE_KINDS.has("weather"))


func _test_below_quest_heat() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "storm")
	var r := _rumor(hs, "weather:storm")
	_check("storm never summons an investigator",
		float(r.get("heat", 0.0)) < hs.QUEST_HEAT)


func _test_storm_dread() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "storm")
	var r := _rumor(hs, "weather:storm")
	var gnome := _spawn(gs, "gnomes")
	var uid := int(gnome.get("id", 0))
	hs._on_heard(gnome, r, {})
	_check("storm leaves dread",
		_recalled(gnome, "storm_dread", int(r.get("id", 0))) > 0.0)
	_check("dread dips mood exactly",
		is_equal_approx(conv.ruler_mood(uid), -3.0))
	_check("dismayed lands as sad", _emotion(gnome) == "sad")


func _test_farmer_fears_crops_deeper() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "storm")
	var r := _rumor(hs, "weather:storm")
	var peasant := _spawn(gs, "gnomes")
	var farmer := _spawn(gs, "gnomes", {"job": "farmer"})
	var uid := int(farmer.get("id", 0))
	hs._on_heard(peasant, r, {})
	hs._on_heard(farmer, r, {})
	var pm: float = conv.ruler_mood(int(peasant.get("id", 0)))
	var fm: float = conv.ruler_mood(uid)
	_check("farmer fears for the crops",
		_recalled(farmer, "storm_crops", int(r.get("id", 0))) > 0.0)
	_check("farmer dreads deeper than the peasant", fm < pm)
	_check("crop fear is disaster-grade",
		is_equal_approx(fm, -5.0))
	_check("disaster lands as scared", _emotion(farmer) == "scared")


func _test_unhinged_thrilled_by_storm() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "storm")
	var r := _rumor(hs, "weather:storm")
	var wild := _spawn(gs, "gnomes", {"mind": _unhinged_mind()})
	var uid := int(wild.get("id", 0))
	hs._on_heard(wild, r, {})
	_check("unhinged loves a good storm",
		_recalled(wild, "storm_thrill", int(r.get("id", 0))) > 0.0)
	_check("thrill lifts mood", conv.ruler_mood(uid) > 0.0)
	_check("cheerful lands as happy", _emotion(wild) == "happy")


func _test_unhinged_amplified() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "storm")
	var r := _rumor(hs, "weather:storm")
	var wild := _spawn(gs, "gnomes", {"mind": _unhinged_mind()})
	var uid := int(wild.get("id", 0))
	hs._on_heard(wild, r, {})
	_check("unhinged feels it 1.5x (4.0 * 1.5)",
		is_equal_approx(conv.ruler_mood(uid), 6.0))


func _test_rain_farmer_blessing() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "rain")
	var r := _rumor(hs, "weather:rain")
	var farmer := _spawn(gs, "gnomes", {"job": "farmer"})
	var uid := int(farmer.get("id", 0))
	hs._on_heard(farmer, r, {})
	_check("farmer welcomes the soaking",
		_recalled(farmer, "rain_blessing", int(r.get("id", 0))) > 0.0)
	_check("blessing lifts mood",
		is_equal_approx(conv.ruler_mood(uid), 3.0))
	_check("cheerful lands as happy", _emotion(farmer) == "happy")


func _test_rain_neutral_comfort() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "rain")
	var r := _rumor(hs, "weather:rain")
	var gnome := _spawn(gs, "gnomes")
	var uid := int(gnome.get("id", 0))
	hs._on_heard(gnome, r, {})
	_check("everyone else takes comfort",
		_recalled(gnome, "rain_news", int(r.get("id", 0))) > 0.0)
	_check("comfort is mild", is_equal_approx(conv.ruler_mood(uid), 1.0))


func _test_snow_dread() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "snow")
	var r := _rumor(hs, "weather:snow")
	var gnome := _spawn(gs, "gnomes")
	var uid := int(gnome.get("id", 0))
	hs._on_heard(gnome, r, {})
	_check("snow puts the realm on edge",
		_recalled(gnome, "snow_dread", int(r.get("id", 0))) > 0.0)
	_check("snow dread dips mood",
		is_equal_approx(conv.ruler_mood(uid), -3.0))
	_check("dismayed lands as sad", _emotion(gnome) == "sad")


func _test_snow_farmer_stores_deeper() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var phone = h[1]
	var hs = h[2]
	var conv = phone.get("conversation")
	_emit(gs, "snow")
	var r := _rumor(hs, "weather:snow")
	var peasant := _spawn(gs, "gnomes")
	var farmer := _spawn(gs, "gnomes", {"job": "farmer"})
	hs._on_heard(peasant, r, {})
	hs._on_heard(farmer, r, {})
	var pm: float = conv.ruler_mood(int(peasant.get("id", 0)))
	var fm: float = conv.ruler_mood(int(farmer.get("id", 0)))
	_check("farmer counts the stores",
		_recalled(farmer, "snow_stores", int(r.get("id", 0))) > 0.0)
	_check("farmer dreads deeper than the peasant", fm < pm)
	_check("store fear is disaster-grade",
		is_equal_approx(fm, -5.0))


func _test_spread_motivation() -> void:
	var h: Array = _harness()
	var gs: GameState = h[0]
	var hs = h[2]
	_emit(gs, "storm")
	_emit(gs, "snow")
	_emit(gs, "rain")
	var rs := _rumor(hs, "weather:storm")
	var rw := _rumor(hs, "weather:snow")
	var rr := _rumor(hs, "weather:rain")
	var gnome := _spawn(gs, "gnomes")
	var m_storm: Dictionary = hs._spread_motivation(gnome, rs)
	_check("storm warnings are neighborly duty",
		int(m_storm.get("cap_delta", 0)) == 1 \
		and is_equal_approx(float(m_storm.get("heat_delta", 0.0)), 0.05))
	var m_snow: Dictionary = hs._spread_motivation(gnome, rw)
	_check("snow talk travels like winter talk",
		int(m_snow.get("cap_delta", 0)) == 1 \
		and is_equal_approx(float(m_snow.get("heat_delta", 9.0)), 0.0))
	var m_rain: Dictionary = hs._spread_motivation(gnome, rr)
	_check("rain is idle sky-talk",
		int(m_rain.get("cap_delta", 9)) == 0 \
		and is_equal_approx(float(m_rain.get("heat_delta", 9.0)), 0.0))


func _test_memory_types_registered() -> void:
	var mem = load("res://scripts/sim/memories.gd")
	for t: String in ["storm_dread", "storm_crops", "storm_thrill",
			"rain_blessing", "rain_news", "snow_dread", "snow_stores"]:
		_check("memory type registered: " + t, mem.TYPES.has(t))
		_check("memory weight set: " + t, mem.REL_WEIGHT.has(t))
