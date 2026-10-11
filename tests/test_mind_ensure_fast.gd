extends SceneTree
## R22: SimMind.ensure fast-path — one has() replaces the full sub-ensure
## chain on every budgeted mind slice. Zero behavior change: the flag is
## set only after all sub-ensures complete, so equivalence is guaranteed.

var _pass := 0
var _fail := 0


func _check(name: String, ok: bool) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("FAIL: ", name)


func _new_mind() -> SimMind:
	var gs := GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	var m := SimMind.new(gs)
	return m


func _test_flag_set_after_full_ensure() -> void:
	var m := _new_mind()
	var u: Dictionary = {"id": 42, "faction": "humans", "alive": true}
	m.ensure(u)
	_check("flag set", bool(u.get("_mind_ok", false)))
	_check("mind present", u.has("mind"))
	_check("urges present", u.has("urges"))
	_check("emotion present", u.has("emotion"))
	_check("mood present", u.has("mood"))
	_check("memories present", u.has("memories"))
	_check("mind_state present", u.has("mind_state"))
	_check("fleeing present", u.has("fleeing"))
	_check("flee_timer present", u.has("flee_timer"))
	_check("chatter_cd present", u.has("chatter_cd"))


func _test_fast_path_is_noop() -> void:
	var m := _new_mind()
	var u: Dictionary = {"id": 43, "faction": "ogres", "alive": true}
	m.ensure(u)
	var before: Dictionary = u.duplicate(true)
	# Second call must not touch anything.
	for i in range(5):
		m.ensure(u)
	_check("flag still set", bool(u.get("_mind_ok", false)))
	_check("record untouched by fast path", str(u) == str(before))


func _test_old_save_unit_gets_full_ensure() -> void:
	# A unit from an old save has no _mind_ok flag: must get the full ensure.
	var m := _new_mind()
	var u: Dictionary = {"id": 44, "faction": "elves", "alive": true,
		"mind": {"traits": {"name": "X"}, "name": "X", "critical_urge": ""}}
	m.ensure(u)
	_check("old-save flag set", bool(u.get("_mind_ok", false)))
	_check("old-save urges added", u.has("urges"))
	_check("old-save emotion added", u.has("emotion"))
	_check("old-save chatter_cd added", u.has("chatter_cd"))


func _test_tick_unit_still_decays() -> void:
	# Fast path must not break the tick: urges still decay on decay slices.
	var m := _new_mind()
	var u: Dictionary = {"id": 45, "faction": "humans", "alive": true,
		"position": Vector2(100, 100)}
	m.ensure(u)
	u["urges"]["hunger"] = 100.0
	var d: float = 1.0 / 60.0
	for i in range(300):
		m.tick_unit(u, d)
	var hunger: float = float(u["urges"]["hunger"])
	_check("hunger decayed through fast path (got %.3f)" % hunger,
		absf(hunger - (100.0 - 0.35 * 5.0)) < 0.05)


func _initialize() -> void:
	_test_flag_set_after_full_ensure()
	_test_fast_path_is_noop()
	_test_old_save_unit_gets_full_ensure()
	_test_tick_unit_still_decays()
	print("=== Cursing Gnomes mind ensure fast-path tests ===")
	print("=== %d passed, %d failed ===" % [_pass, _fail])
	if _fail > 0:
		quit(1)
		return
	quit()
