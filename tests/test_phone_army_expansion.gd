extends SceneTree
## Cursing Gnomes — phone Army app expansion (Jeremy 2026-10-06, Lane 5):
## War room, Veterans roster, Warlord retinue, Deploy map.
##
## Covers:
##   - Sub-screens open from the Army app; back target is "army"; the
##     status back chevron returns to the Army app (Back, never X).
##   - Army screen shows the sub-screen nav (War room / Veterans /
##     Warlords / Deploy) alongside the shared ArmyTab surface.
##   - War room: live PhoneArmyMap node (self-refresh timer), stance +
##     order counts per faction, foreign armies marked view-only.
##   - Veterans roster: veteran tiers from service marks, per-unit kills,
##     sortable by kills/weapon/name; foreign rosters are view-only.
##   - Deploy: order_rally writes move_target for the PLAYER faction only;
##     foreign troops are never ordered (sovereignty); scopes resolve.
##   - Warlord retinue: assign/remove writes retinue_of (+ march to the
##     warlord); foreign warlords refuse reassignment.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_army_expansion.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes phone army-expansion tests ===")
	_test_subscreens_open_and_back()
	_test_army_nav_row()
	_test_warroom_live_map()
	_test_warroom_orders()
	_test_roster_tiers()
	_test_roster_sorting()
	_test_roster_foreign_viewonly()
	_test_rally_player_only()
	_test_rally_scopes()
	_test_retinue_assign_remove()
	_test_retinue_foreign_refused()
	_test_veteran_tier_logic()
	_test_assignment_of()
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
	gs.setup(["humans", "ogres"])  # player = humans
	var s := SimSeasons.new(gs)
	s.reset()
	gs.seasons = s
	gs.army = SimArmy.new(gs)
	gs.set_meta("army", gs.army)
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "phone": phone, "court": court}


func _new_ui(w: Dictionary) -> PhoneUI:
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(w["gs"], w["phone"], w["court"])
	return ui


func _spawn(w: Dictionary, faction: String, job: String,
		pos: Vector2, unit_name: String = "") -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, -1, pos)
	if unit_name != "":
		u["mind"] = {"name": unit_name}
	return u


func _collect_texts(ui: PhoneUI) -> Array[String]:
	var out: Array[String] = []
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label:
			out.append((n as Label).text)
		if n is Button:
			out.append((n as Button).text)
		for c in n.get_children():
			stack.append(c)
	return out


func _collect_texts_ordered(n: Node, out: Array[String]) -> void:
	# Pre-order traversal preserving child order (unlike _collect_texts,
	# which pops the stack and reverses sibling order).
	if n is Label:
		out.append((n as Label).text)
	if n is Button:
		out.append((n as Button).text)
	for c in n.get_children():
		_collect_texts_ordered(c, out)


func _ordered_join(ui: PhoneUI) -> String:
	var out: Array[String] = []
	_collect_texts_ordered(ui, out)
	return "\n".join(out)


func _find_maps(ui: PhoneUI) -> Array:
	var out := []
	var stack: Array = [ui]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is PhoneArmyMap:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


func _teardown(w: Dictionary, ui: PhoneUI) -> void:
	ui.queue_free()
	(w["gs"] as GameState).queue_free()


## --- sub-screen navigation ------------------------------------------------------

func _test_subscreens_open_and_back() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	for screen: String in ["army_warroom", "army_roster", "army_retinue",
			"army_deploy"]:
		ui.open_app(screen)
		_check("opens " + screen, ui.current_screen() == screen)
		_check("back target " + screen, ui._back_target_for(screen) == "army")
		ui._on_status_back()
		_check("back from " + screen + " to army",
			ui.current_screen() == "army")
	_teardown(w, ui)


func _test_army_nav_row() -> void:
	var w := _new_world()
	var ui := _new_ui(w)
	ui.open_app("army")
	var joined := "\n".join(_collect_texts(ui))
	for label: String in ["War room", "Veterans", "Warlords", "Deploy"]:
		_check("nav has " + label, joined.find(label) >= 0)
	# The shared ArmyTab surface still builds alongside the nav.
	_check("army surface kept", joined.find("Your forces") >= 0)
	_teardown(w, ui)


## --- war room ---------------------------------------------------------------------

func _test_warroom_live_map() -> void:
	var w := _new_world()
	_spawn(w, "humans", "soldier", Vector2(100, 100), "MapScout")
	var ui := _new_ui(w)
	ui.open_app("army_warroom")
	var maps := _find_maps(ui)
	_check("warroom has map", maps.size() == 1)
	if maps.size() == 1:
		var m: PhoneArmyMap = maps[0]
		# Headless SceneTree._initialize never fires _ready (nothing is
		# inside the tree yet); drive the lifecycle manually to verify the
		# live-refresh wiring production relies on.
		m._ready()
		var has_timer := false
		for c in m.get_children():
			if c is Timer:
				has_timer = true
		_check("map self-refreshes (live)", has_timer)
		var mr: Rect2 = m._map_rect()
		_check("map keeps edge margin (safe areas)",
			mr.position.x >= 14.0 and mr.position.y >= 14.0)
	_teardown(w, ui)


func _test_warroom_orders() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var dep := _spawn(w, "humans", "soldier", Vector2(0, 0), "Deployed")
	dep["deployed_for_war"] = true
	_spawn(w, "ogres", "soldier", Vector2(500, 500), "OgreScout")
	var ui := _new_ui(w)
	ui.open_app("army_warroom")
	var joined := "\n".join(_collect_texts(ui))
	_check("warroom shows stances", joined.find("Stance:") >= 0)
	_check("warroom counts deployed", joined.find("deployed 1") >= 0)
	_check("warroom foreign view-only",
		joined.find("Foreign army — view-only.") >= 0)
	_check("warroom shows both factions",
		joined.find("Humans") >= 0 and joined.find("Ogres") >= 0)
	_teardown(w, ui)


## --- veterans roster ----------------------------------------------------------------

func _test_roster_tiers() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var a := _spawn(w, "humans", "soldier", Vector2(0, 0), "Alpha")
	var b := _spawn(w, "humans", "soldier", Vector2(10, 0), "Beta")
	var c := _spawn(w, "humans", "soldier", Vector2(20, 0), "Gamma")
	var wl: Dictionary = gs.army.promote_warlord("humans")
	_check("warlord promoted", not wl.is_empty())
	# Configure exactly one non-warlord as the veteran; the third stays a
	# recruit. (Promotion picks the toughest — don't assume which wins.)
	var wl_id := int(wl.get("id", -1))
	var made_vet := false
	for u in [a, b, c]:
		if int(u.get("id", -1)) == wl_id:
			continue
		if not made_vet:
			u["weapon_level"] = 3
			u["kills"] = 5
			u["deployed_for_war"] = true
			made_vet = true
	var ui := _new_ui(w)
	ui.open_app("army_roster")
	var joined := "\n".join(_collect_texts(ui))
	_check("roster veteran tier", joined.find("[Veteran]") >= 0)
	_check("roster recruit tier", joined.find("[Recruit]") >= 0)
	_check("roster warlord tier", joined.find("[Warlord]") >= 0)
	_check("roster kill counts", joined.find("5 kills") >= 0)
	_teardown(w, ui)


func _test_roster_sorting() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var low := _spawn(w, "humans", "soldier", Vector2(0, 0), "ZedLow")
	low["kills"] = 1
	var high := _spawn(w, "humans", "soldier", Vector2(10, 0), "AbeHigh")
	high["kills"] = 9
	PhoneArmyExpansion._roster_sort = "kills"
	PhoneArmyExpansion._roster_faction = "humans"
	var ui := _new_ui(w)
	ui.open_app("army_roster")
	# NOTE: _collect_texts reverses sibling order (stack pop); the
	# order-preserving join is required for sequence assertions.
	var joined := _ordered_join(ui)
	_check("sort kills desc",
		joined.find("AbeHigh") >= 0 and joined.find("AbeHigh")
		< joined.find("ZedLow"))
	PhoneArmyExpansion._roster_sort = "name"
	ui.open_app("army_roster")
	var joined2 := _ordered_join(ui)
	_check("sort name asc",
		joined2.find("AbeHigh") >= 0 and joined2.find("AbeHigh")
		< joined2.find("ZedLow"))
	PhoneArmyExpansion._roster_sort = "kills"  # restore default
	_teardown(w, ui)


func _test_roster_foreign_viewonly() -> void:
	var w := _new_world()
	_spawn(w, "ogres", "soldier", Vector2(0, 0), "OgreVet")
	PhoneArmyExpansion._roster_faction = "ogres"
	var ui := _new_ui(w)
	ui.open_app("army_roster")
	var joined := "\n".join(_collect_texts(ui))
	_check("roster foreign view-only", joined.find("view-only") >= 0)
	_check("roster shows foreign troops", joined.find("OgreVet") >= 0)
	PhoneArmyExpansion._roster_faction = ""  # restore default
	_teardown(w, ui)


## --- deploy / rally -------------------------------------------------------------------

func _test_rally_player_only() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var ours := _spawn(w, "humans", "soldier", Vector2(0, 0), "Ours")
	var theirs := _spawn(w, "ogres", "soldier", Vector2(0, 0), "Theirs")
	var ids := [int(ours.get("id", -1)), int(theirs.get("id", -1))]
	var target := Vector2(700, 300)
	var n := PhoneArmyExpansion.order_rally(gs, ids, target)
	_check("rally orders player troop only", n == 1)
	_check("rally sets move_target",
		ours.get("move_target", Vector2.ZERO) == target)
	_check("rally never touches foreign troops",
		not theirs.has("move_target"))


func _test_rally_scopes() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var dep := _spawn(w, "humans", "soldier", Vector2(0, 0), "Dep")
	dep["deployed_for_war"] = true
	var mus := _spawn(w, "humans", "soldier", Vector2(10, 0), "Mus")
	mus["mustering"] = true
	var idle := _spawn(w, "humans", "soldier", Vector2(20, 0), "Idle")
	var dep_id := int(dep.get("id", -1))
	var mus_id := int(mus.get("id", -1))
	var idle_id := int(idle.get("id", -1))
	var field := PhoneArmyExpansion._scope_ids(gs, "field")
	_check("field scope",
		dep_id in field and mus_id in field and idle_id not in field)
	var mustered := PhoneArmyExpansion._scope_ids(gs, "mustered")
	_check("mustered scope", mus_id in mustered and dep_id not in mustered)
	var allf := PhoneArmyExpansion._scope_ids(gs, "all")
	_check("all scope",
		dep_id in allf and mus_id in allf and idle_id in allf)
	# Dead/down fighters never take rally orders.
	idle["downed"] = true
	var n := PhoneArmyExpansion.order_rally(gs, [idle_id], Vector2(9, 9))
	_check("rally skips downed", n == 0 and not idle.has("move_target"))
	_teardown_no_ui(w)


func _teardown_no_ui(w: Dictionary) -> void:
	(w["gs"] as GameState).queue_free()


## --- warlord retinue --------------------------------------------------------------------

func _test_retinue_assign_remove() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var champ := _spawn(w, "humans", "soldier", Vector2(0, 0), "Champ")
	var guard0 := _spawn(w, "humans", "soldier", Vector2(50, 50), "Guard")
	var wl: Dictionary = gs.army.promote_warlord("humans")
	_check("warlord for retinue", not wl.is_empty())
	if wl.is_empty():
		_teardown_no_ui(w)
		return
	var wl_id := int(wl.get("id", -1))
	# Use a non-warlord fighter as the retinue candidate (promotion picks
	# the toughest — either spawned soldier could win).
	var guard: Dictionary = {}
	for u in [champ, guard0]:
		if int(u.get("id", -1)) != wl_id:
			guard = u
			break
	_check("retinue candidate", not guard.is_empty())
	var gid := int(guard.get("id", -1))
	var err := PhoneArmyExpansion.assign_retinue(gs, "humans", gid, wl_id)
	_check("retinue assign ok", err == "")
	_check("retinue mark set", int(guard.get("retinue_of", -1)) == wl_id)
	_check("retinue marches to warlord", guard.has("move_target"))
	var err2 := PhoneArmyExpansion.remove_retinue(gs, "humans", gid)
	_check("retinue remove ok", err2 == "")
	_check("retinue mark cleared", not guard.has("retinue_of"))
	_teardown_no_ui(w)


func _test_retinue_foreign_refused() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var foe := _spawn(w, "ogres", "soldier", Vector2(0, 0), "Foe")
	var fid := int(foe.get("id", -1))
	var err := PhoneArmyExpansion.assign_retinue(gs, "ogres", fid, 12345)
	_check("foreign retinue refused", err != "")
	_check("foreign retinue no mark", not foe.has("retinue_of"))
	var err2 := PhoneArmyExpansion.remove_retinue(gs, "ogres", fid)
	_check("foreign retinue remove refused", err2 != "")
	_teardown_no_ui(w)


## --- pure logic ------------------------------------------------------------------------------

func _test_veteran_tier_logic() -> void:
	var wlord := {"warlord": true, "weapon_level": 0}
	_check("tier warlord",
		PhoneArmyExpansion.veteran_tier(wlord) == "Warlord")
	var vet := {"weapon_level": 2, "deployed_for_war": false}
	_check("tier veteran by weapon",
		PhoneArmyExpansion.veteran_tier(vet) == "Veteran")
	var blooded := {"weapon_level": 0, "deployed_for_war": true}
	_check("tier blooded by service",
		PhoneArmyExpansion.veteran_tier(blooded) == "Blooded")
	var recruit := {"weapon_level": 0}
	_check("tier recruit",
		PhoneArmyExpansion.veteran_tier(recruit) == "Recruit")


func _test_assignment_of() -> void:
	_check("assign deployed",
		PhoneArmyExpansion.assignment_of({"deployed_for_war": true})
		== "deployed")
	_check("assign mustering",
		PhoneArmyExpansion.assignment_of({"mustering": true}) == "mustering")
	_check("assign marching",
		PhoneArmyExpansion.assignment_of({"move_target": Vector2.ZERO})
		== "marching")
	_check("assign guard",
		PhoneArmyExpansion.assignment_of({"job": "guard"}) == "guarding")
	_check("assign downed",
		PhoneArmyExpansion.assignment_of({"downed": true}) == "downed")
	_check("assign idle",
		PhoneArmyExpansion.assignment_of({"job": "soldier"}) == "idle")
