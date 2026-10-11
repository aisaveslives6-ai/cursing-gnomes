extends SceneTree
## Cursing Gnomes — army retreat (fighting withdrawal) tests.
##
## Covers the AI-first phase military AI checklist item "retreat":
##   - faction sovereignty fix: the AI's own brain can muster/deploy its
##     troops (ungated cores); the player's direct control of foreign
##     factions stays refused on the public entry points
##   - order_retreat: clears deploy orders, marks troops withdrawing to the
##     nearest hall (foreign factions refused)
##   - SimMind._tick_withdraw: withdrawing units march to the rally point,
##     preempting combat; the flag clears on arrival
##   - _assess_retreats: a mauled AI field army facing a dominant enemy
##     falls back; a winning army holds; the player gets an adviser warning
##     instead of an override
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_army_retreat.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes army retreat tests ===")
	_test_ai_self_orders_bypass_gate()
	_test_player_orders_still_gated()
	_test_order_retreat_marks()
	_test_order_retreat_foreign_refused()
	_test_withdraw_movement()
	_test_withdraw_clears_on_arrival()
	_test_assess_retreat_triggers()
	_test_assess_retreat_holds_when_winning()
	_test_player_gets_warning_not_override()
	_test_retreat_button_present()
	_test_retreat_button_orders()
	_test_retreat_button_no_troops()
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


## Fresh game + combat + army + mind systems, capturing Gazette stories.
## player_faction defaults to "humans" (first in setup).
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var combat := SimCombat.new(gs)
	var army := SimArmy.new(gs)
	army.diplomacy = gs.diplomacy
	var mind := SimMind.new(gs)
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	return {"gs": gs, "combat": combat, "army": army, "mind": mind}


func _free_world(w: Dictionary) -> void:
	_stories.clear()
	(w["gs"] as GameState).free()


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.spawner.spawn_unit(faction, job, -1, pos)


func _hall(w: Dictionary, faction: String, pos: Vector2) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({
		"type": "town_hall", "faction": faction, "town_id": -1,
		"position": pos, "complete": true, "progress": 1.0,
		"hp": 1200.0, "max_hp": 1200.0,
	})


func _field_army(w: Dictionary, faction: String, n: int,
		pos: Vector2) -> Array:
	var out: Array = []
	for i in n:
		var u: Dictionary = _spawn(w, faction, "soldier",
			pos + Vector2(i * 24.0, 0.0))
		u["deployed_for_war"] = true
		u["deploy_target_id"] = 4242
		u["deploy_target_kind"] = "building"
		out.append(u)
	return out


func _kill_some(units: Array, n: int) -> void:
	for i in mini(n, units.size()):
		(units[i] as Dictionary)["alive"] = false


## --- sovereignty fix: the AI's own brain is not "direct control" -------------

func _test_ai_self_orders_bypass_gate() -> void:
	# Regression (Jeremy 2026-10-04): the faction-sovereignty gate made
	# ai_war_tick's deploy_for_war silently return 0 for every AI faction —
	# wars were declared but nobody marched. The ungated cores restore it.
	var w := _new_world()
	var army: SimArmy = w["army"]
	_hall(w, "ogres", Vector2(5000, 5000))
	for i in 4:
		_spawn(w, "ogres", "soldier", Vector2(5000 + i * 20.0, 5000))
	for i in 2:
		_spawn(w, "humans", "soldier", Vector2(100 + i * 20.0, 100))
	var n: int = army._deploy_for_war_core("ogres", "humans")
	_check("ai core: deploys 4 ogre troops", n == 4)
	var marked := 0
	for u: Dictionary in (w["gs"] as GameState).units:
		if String(u.get("faction", "")) == "ogres" \
				and bool(u.get("deployed_for_war", false)):
			marked += 1
	_check("ai core: troops carry deploy orders", marked == 4)
	_free_world(w)


func _test_player_orders_still_gated() -> void:
	# The player's direct control of foreign factions stays refused.
	var w := _new_world()
	var army: SimArmy = w["army"]
	_hall(w, "ogres", Vector2(5000, 5000))
	for i in 3:
		_spawn(w, "ogres", "soldier", Vector2(5000 + i * 20.0, 5000))
	_check("gate: public muster refused for ogres", army.muster("ogres") == 0)
	_check("gate: public deploy refused for ogres",
		army.deploy_for_war("ogres", "humans") == 0)
	_check("gate: public order_retreat refused for ogres",
		army.order_retreat("ogres") == 0)
	var moved := false
	for u: Dictionary in (w["gs"] as GameState).units:
		if String(u.get("faction", "")) == "ogres" \
				and (bool(u.get("mustering", false)) \
					or bool(u.get("withdrawing", false))):
			moved = true
	_check("gate: no ogre troop moved", not moved)
	_free_world(w)


## --- order_retreat -----------------------------------------------------------

func _test_order_retreat_marks() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	var hall: Dictionary = _hall(w, "humans", Vector2(1000, 1000))
	for i in 3:
		_spawn(w, "humans", "soldier", Vector2(100 + i * 20.0, 100))
	for i in 2:
		_spawn(w, "ogres", "soldier", Vector2(2000 + i * 20.0, 2000))
	_check("retreat: deploy 3", army._deploy_for_war_core("humans", "ogres") == 3)
	var n: int = army.order_retreat("humans")
	_check("retreat: 3 troops ordered back", n == 3)
	var hall_pos: Vector2 = hall["position"]
	var ok := true
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) != "humans":
			continue
		if not SimCombat.is_fighter(u):
			continue
		ok = ok and bool(u.get("withdrawing", false)) \
			and u.get("withdraw_target", Vector2.INF) == hall_pos \
			and not u.has("deploy_target_id") \
			and not bool(u.get("deployed_for_war", false))
	_check("retreat: troops withdrawing to hall, orders cleared", ok)
	_free_world(w)


func _test_order_retreat_foreign_refused() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	_hall(w, "ogres", Vector2(5000, 5000))
	var u: Dictionary = _spawn(w, "ogres", "soldier", Vector2(5000, 5000))
	u["deployed_for_war"] = true
	_check("retreat: foreign order refused",
		army.order_retreat("ogres") == 0)
	_check("retreat: foreign troop untouched",
		not bool(u.get("withdrawing", false)))
	_free_world(w)


func _test_order_retreat_no_field_army() -> void:
	var w := _new_world()
	var army: SimArmy = w["army"]
	_hall(w, "humans", Vector2(1000, 1000))
	_spawn(w, "humans", "soldier", Vector2(100, 100))
	_check("retreat: nothing deployed -> 0", army.order_retreat("humans") == 0)
	_free_world(w)


## --- withdrawal movement (SimMind) -------------------------------------------

func _test_withdraw_movement() -> void:
	var w := _new_world()
	var mind: SimMind = w["mind"]
	var hall: Dictionary = _hall(w, "humans", Vector2(1000, 0))
	var u: Dictionary = _spawn(w, "humans", "soldier", Vector2(0, 0))
	u["withdrawing"] = true
	u["withdraw_target"] = hall["position"]
	var d0: float = (u["position"] as Vector2).distance_to(hall["position"])
	var busy: bool = mind.tick_unit(u, 1.0)
	var d1: float = (u["position"] as Vector2).distance_to(hall["position"])
	_check("withdraw: mind consumes the tick", busy)
	_check("withdraw: moves toward the hall", d1 < d0 - 50.0)
	_check("withdraw: still flagged", bool(u.get("withdrawing", false)))
	_free_world(w)


func _test_withdraw_clears_on_arrival() -> void:
	var w := _new_world()
	var mind: SimMind = w["mind"]
	var hall: Dictionary = _hall(w, "humans", Vector2(1000, 0))
	var u: Dictionary = _spawn(w, "humans", "soldier", Vector2(990, 10))
	u["withdrawing"] = true
	u["withdraw_target"] = hall["position"]
	var busy: bool = mind.tick_unit(u, 1.0)
	_check("withdraw: arrival releases the tick", not busy)
	_check("withdraw: flag cleared", not bool(u.get("withdrawing", false)))
	_free_world(w)


## --- daily retreat assessment -------------------------------------------------

func _test_assess_retreat_triggers() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	gs.player_faction = "elves"  # ogres are AI now
	_hall(w, "ogres", Vector2(5000, 5000))
	var ogres: Array = _field_army(w, "ogres", 8, Vector2(0, 0))
	_field_army(w, "humans", 10, Vector2(300, 0))  # dominant enemy nearby
	army.diplomacy.declare_war("ogres", "humans", "test")
	gs.day_number = 1
	army.tick(0.0)  # peak[ogres] = 8
	_kill_some(ogres, 5)  # mauled down to 3 (< half of 8)
	gs.day_number = 2
	_stories.clear()
	army.tick(0.0)
	var withdrawing := 0
	for u: Dictionary in ogres:
		if bool(u.get("withdrawing", false)):
			withdrawing += 1
	_check("assess: mauled ogre army retreats", withdrawing == 3)
	var noted := false
	for s: Dictionary in _stories:
		if String(s.get("headline", "")) == "ARMY IN RETREAT":
			noted = true
	_check("assess: retreat gazetted", noted)
	_free_world(w)


func _test_assess_retreat_holds_when_winning() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	gs.player_faction = "elves"
	_hall(w, "ogres", Vector2(5000, 5000))
	var ogres: Array = _field_army(w, "ogres", 8, Vector2(0, 0))
	_field_army(w, "humans", 2, Vector2(300, 0))  # weak enemy
	army.diplomacy.declare_war("ogres", "humans", "test")
	gs.day_number = 1
	army.tick(0.0)
	gs.day_number = 2
	army.tick(0.0)
	var withdrawing := 0
	for u: Dictionary in ogres:
		if bool(u.get("withdrawing", false)):
			withdrawing += 1
	_check("assess: winning army holds the field", withdrawing == 0)
	_free_world(w)


func _test_player_gets_warning_not_override() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var army: SimArmy = w["army"]
	# player_faction is "humans" by default — the brain warns, never overrides.
	_hall(w, "humans", Vector2(1000, 1000))
	var humans: Array = _field_army(w, "humans", 8, Vector2(0, 0))
	_field_army(w, "ogres", 10, Vector2(300, 0))
	army.diplomacy.declare_war("humans", "ogres", "test")
	gs.day_number = 1
	army.tick(0.0)
	_kill_some(humans, 5)
	gs.day_number = 2
	_stories.clear()
	army.tick(0.0)
	var withdrawing := 0
	for u: Dictionary in humans:
		if bool(u.get("withdrawing", false)):
			withdrawing += 1
	_check("assess: player army NOT auto-retreated", withdrawing == 0)
	var warned := false
	for s: Dictionary in _stories:
		if String(s.get("headline", "")) == "ADVISER'S WARNING":
			warned = true
	_check("assess: adviser warns the player", warned)
	_free_world(w)


## --- Army tab retreat button (launch readiness 2026-10-06) --------------------
## The ADVISER'S WARNING gazette tells the player "Order a retreat before
## it's too late" — the order has to exist in the UI. SimArmy.order_retreat
## was wired to nothing; the Army tab's Command section now carries the
## "Retreat to hall" button.

func _tab_vbox(w: Dictionary) -> VBoxContainer:
	var gs: GameState = w["gs"]
	gs.set_meta("army", w["army"])
	ArmyTab._cmd_status = ""
	var vbox := VBoxContainer.new()
	root.add_child(vbox)
	ArmyTab.build(gs, vbox)
	return vbox


func _press_button(vbox: VBoxContainer, text: String) -> bool:
	for c in vbox.get_children():
		if c is Button and String((c as Button).text) == text:
			(c as Button).pressed.emit()
			return true
	return false


func _tab_label_texts(vbox: VBoxContainer) -> Array[String]:
	var out: Array[String] = []
	for c in vbox.get_children():
		if c is Label:
			out.append(String((c as Label).text))
	return out


func _test_retreat_button_present() -> void:
	var w := _new_world()
	var vbox := _tab_vbox(w)
	var found := false
	for c in vbox.get_children():
		if c is Button and String((c as Button).text) == "Retreat to hall":
			found = true
	_check("army tab: Retreat to hall button exists", found)
	vbox.queue_free()
	_free_world(w)


func _test_retreat_button_orders() -> void:
	var w := _new_world()
	var troops: Array = _field_army(w, "humans", 3, Vector2(300, 300))
	_hall(w, "humans", Vector2(1000, 1000))
	var vbox := _tab_vbox(w)
	_check("army tab: retreat button press reaches handler",
		_press_button(vbox, "Retreat to hall"))
	var withdrawing := 0
	for u in troops:
		if bool((u as Dictionary).get("withdrawing", false)):
			withdrawing += 1
	_check("army tab: retreat button withdraws field troops", withdrawing == 3)
	var labels := _tab_label_texts(vbox)
	var shown := false
	for t: String in labels:
		if t.begins_with("3 troops falling back to the hall."):
			shown = true
	_check("army tab: retreat status shown after order", shown)
	vbox.queue_free()
	_free_world(w)


func _test_retreat_button_no_troops() -> void:
	var w := _new_world()
	# No deployed field troops — the button reports instead of failing.
	var vbox := _tab_vbox(w)
	_press_button(vbox, "Retreat to hall")
	var labels := _tab_label_texts(vbox)
	var shown := false
	for t: String in labels:
		if t == "No field troops to withdraw.":
			shown = true
	_check("army tab: retreat with no troops reports cleanly", shown)
	vbox.queue_free()
	_free_world(w)
