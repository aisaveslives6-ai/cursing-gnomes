extends SceneTree
## Cursing Gnomes — farm animal system tests.
##
## Covers SimAnimals (HTML Stage-8 farm animals): ANIMAL_TYPES registry,
## barn/coop housing attach + stocking (cow+pig / chicken+chicken /
## second-barn goat+sheep), the 8-animal plot cap, daily feeding
## (hunger = 90), daily food yields (chicken 6, cow 14, pig 10, sheep 8,
## goat 10), hunger decay + starvation death + corpse handoff to the
## undead corpse system, leash movement, and save/load round-trip via
## farming's to_dict/from_dict.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_animals.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes farm-animal tests ===")
	_test_registry()
	_test_barn_stock()
	_test_coop_stock()
	_test_second_barn_variety()
	_test_cap()
	_test_daily_yield_and_feeding()
	_test_starvation()
	_test_leash()
	_test_save_roundtrip()
	_test_wild_spawn()
	_test_wild_seed()
	_test_wild_hunt()
	_test_wolf_predation()
	_test_wild_fear()
	_test_boar_flees_wolf()
	_test_wolf_bite_blood()
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


func _new_game(factions: Array[String]) -> GameState:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(factions)
	return gs


func _new_farm_stack(factions: Array[String]) -> Array:
	# Returns [gs, farming, animals] with animals wired to game.animals.
	var gs := _new_game(factions)
	var f := SimFarming.new(gs)
	gs.farming = f
	gs.resources.add_resource(factions[0], "wood", 100.0)
	var a := SimAnimals.new(gs)
	gs.animals = a
	return [gs, f, a]


func _make_plot(f, faction: String, pos: Vector2) -> Dictionary:
	return f.create_plot(faction, pos, -1, true)


func _make_bld(gs: GameState, type: String, faction: String,
		pos: Vector2) -> Dictionary:
	return gs.add_building({
		"type": type, "faction": faction, "town_id": -1,
		"position": pos, "alive": true, "complete": true})


## ---- registry ---------------------------------------------------------------


func _test_registry() -> void:
	_check("8 types", SimAnimals.ANIMAL_TYPES.size() == 8)
	var cow: Dictionary = SimAnimals.ANIMAL_TYPES["cow"]
	_check("cow hp_mul", is_equal_approx(float(cow["hp_mul"]), 1.8))
	_check("cow label", String(cow["label"]) == "Cow")
	_check("yield chicken", SimAnimals.DAILY_YIELD["chicken"] == 6.0)
	_check("yield cow", SimAnimals.DAILY_YIELD["cow"] == 14.0)
	_check("yield pig", SimAnimals.DAILY_YIELD["pig"] == 10.0)
	_check("yield sheep", SimAnimals.DAILY_YIELD["sheep"] == 8.0)
	_check("yield goat", SimAnimals.DAILY_YIELD["goat"] == 10.0)
	_check("yield boar", SimAnimals.DAILY_YIELD["boar"] == 0.0)
	_check("cap 8", SimAnimals.MAX_PER_PLOT == 8)


## ---- housing + stocking -----------------------------------------------------


func _test_barn_stock() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f = pack[1]
	var a = pack[2]
	var plot: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	var barn: Dictionary = _make_bld(gs, "barn", "humans", Vector2(150, 120))
	a.tick(0.1)
	_check("barn attached", int(plot.get("barn_bld", -1)) == int(barn["id"]))
	var kinds: Array = []
	for an in a.herd_of(plot):
		kinds.append(String(an["type"]))
	kinds.sort()
	_check("barn stocks cow+pig", kinds == ["cow", "pig"])
	# Re-tick: stocking is one-time only.
	a.tick(0.1)
	_check("no double stock", a.herd_of(plot).size() == 2)
	# A far-away barn does not attach.
	var plot2: Dictionary = _make_plot(f, "humans", Vector2(5000, 5000))
	_make_bld(gs, "barn", "humans", Vector2(5900, 5000))
	a.tick(0.1)
	_check("far barn ignored", int(plot2.get("barn_bld", -1)) == -1)
	_check("far plot empty", a.herd_of(plot2).is_empty())
	# Wrong-faction barn does not attach (isolated from the humans barn).
	var plot3: Dictionary = _make_plot(f, "humans", Vector2(9000, 9000))
	_make_bld(gs, "barn", "ogres", Vector2(9100, 9050))
	a.tick(0.1)
	_check("enemy barn ignored", int(plot3.get("barn_bld", -1)) == -1)


func _test_coop_stock() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f = pack[1]
	var a = pack[2]
	var plot: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	_make_bld(gs, "coop", "humans", Vector2(140, 110))
	a.tick(0.1)
	var kinds: Array = []
	for an in a.herd_of(plot):
		kinds.append(String(an["type"]))
	kinds.sort()
	_check("coop stocks 2 chickens", kinds == ["chicken", "chicken"])


func _test_second_barn_variety() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f = pack[1]
	var a = pack[2]
	var p1: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	_make_bld(gs, "barn", "humans", Vector2(150, 120))
	a.tick(0.1)
	_check("first barn cow+pig", a.herd_of(p1).size() == 2)
	var p2: Dictionary = _make_plot(f, "humans", Vector2(2000, 2000))
	_make_bld(gs, "barn", "humans", Vector2(2050, 2020))
	a.tick(0.1)
	var kinds: Array = []
	for an in a.herd_of(p2):
		kinds.append(String(an["type"]))
	kinds.sort()
	_check("second barn goat+sheep", kinds == ["goat", "sheep"])


func _test_cap() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var f = pack[1]
	var a = pack[2]
	var plot: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	var kinds: Array = []
	for i in 12:
		kinds.append("cow")
	var added: Array = a.stock_plot(plot, kinds, Vector2(100, 100))
	_check("cap enforced", added.size() == 8)
	_check("herd is 8", a.herd_of(plot).size() == 8)
	# Unknown types fall back to boar (HTML Animal constructor default).
	var an: Dictionary = a.add_animal(plot, "dragon", Vector2.ZERO)
	_check("cap blocks 9th", an.is_empty())
	plot["animals"] = []
	var weird: Dictionary = a.add_animal(plot, "dragon", Vector2.ZERO)
	_check("unknown -> boar", String(weird.get("type", "")) == "boar")


## ---- daily: feeding + yields ------------------------------------------------


func _test_daily_yield_and_feeding() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f = pack[1]
	var a = pack[2]
	var plot: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	var cow: Dictionary = a.add_animal(plot, "cow", Vector2(100, 100))
	var pig: Dictionary = a.add_animal(plot, "pig", Vector2(105, 100))
	var chicken: Dictionary = a.add_animal(plot, "chicken", Vector2(95, 100))
	cow["hunger"] = 10.0
	pig["hunger"] = 5.0
	var food0: float = gs.resources.get_amount("humans", "food")
	gs.day_number = 2
	a.tick(0.0)
	var gained: float = gs.resources.get_amount("humans", "food") - food0
	_check("daily yield 14+10+6", is_equal_approx(gained, 30.0))
	_check("fed cow", is_equal_approx(float(cow["hunger"]), 90.0))
	_check("fed pig", is_equal_approx(float(pig["hunger"]), 90.0))
	_check("fed chicken", is_equal_approx(float(chicken["hunger"]), 90.0))
	# Same day again: no second payout.
	a.tick(0.0)
	_check("no double payout",
		is_equal_approx(gs.resources.get_amount("humans", "food") - food0,
			30.0))


## ---- hunger decay + starvation ----------------------------------------------


func _test_starvation() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f = pack[1]
	var a = pack[2]
	gs.undead = SimUndead.new(gs)
	var plot: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	var goat: Dictionary = a.add_animal(plot, "goat", Vector2(100, 100))
	var hunger0: float = float(goat["hunger"])
	# R26: livestock ticks round-robin at 20Hz — 3 ticks cover every plot
	# exactly once; scaled delta keeps the totals identical.
	a.tick(10.0)
	a.tick(10.0)
	a.tick(10.0)
	_check("hunger decays 1.1/s",
		is_equal_approx(float(goat["hunger"]), hunger0 - 33.0))
	# Starve it out: hunger 0, 1 hp left.
	goat["hunger"] = 0.0
	goat["hp"] = 1.0
	a.tick(1.0)
	a.tick(1.0)
	a.tick(1.0)
	_check("starved dead", not bool(goat["alive"]))
	a.tick(0.0)
	a.tick(0.0)
	a.tick(0.0)
	_check("corpse purged", a.herd_of(plot).is_empty())
	var corpses: Array = gs.undead.corpses
	var found := false
	for c in corpses:
		if String(c.get("race", "")) == "animal" \
				and String(c.get("job", "")) == "goat":
			found = true
	_check("animal corpse registered", found)


## ---- leash -----------------------------------------------------------------


func _test_leash() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var f = pack[1]
	var a = pack[2]
	var plot: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	var an: Dictionary = a.add_animal(plot, "sheep", Vector2(100, 100))
	# Stray far past the 260px leash: gets a move target back near home.
	# R26: livestock runs round-robin at 20Hz — 3 ticks cover every plot.
	an["position"] = Vector2(1000, 1000)
	a.tick(1.0)
	a.tick(1.0)
	a.tick(1.0)
	_check("leash target set", an.has("move_target"))
	var d0: float = Vector2(1000, 1000).distance_to(Vector2(100, 100))
	var d1: float = (an["position"] as Vector2).distance_to(Vector2(100, 100))
	_check("walks home", d1 < d0)


## ---- save / load -----------------------------------------------------------


func _test_save_roundtrip() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var f = pack[1]
	var a = pack[2]
	var plot: Dictionary = _make_plot(f, "humans", Vector2(100, 100))
	a.add_animal(plot, "cow", Vector2(101, 102))
	a.add_animal(plot, "chicken", Vector2(103, 104))
	plot["barn_bld"] = 7
	var snap: Dictionary = f.to_dict()
	var gs2 := _new_game(["humans"])
	var f2 := SimFarming.new(gs2)
	gs2.farming = f2
	f2.from_dict(snap)
	_check("plot restored", f2.plots.size() == 1)
	var p2: Dictionary = f2.plots[0]
	var a2 := SimAnimals.new(gs2)
	gs2.animals = a2
	var herd: Array = a2.herd_of(p2)
	_check("herd restored", herd.size() == 2)
	var kinds: Array = []
	for an in herd:
		kinds.append(String(an["type"]))
	kinds.sort()
	_check("types restored", kinds == ["chicken", "cow"])
	_check("barn id restored", int(p2.get("barn_bld", -1)) == 7)
	var c0: Vector2 = (herd[0]["position"] as Vector2)
	var c1: Vector2 = (herd[1]["position"] as Vector2)
	_check("positions restored",
		(c0 - Vector2(101, 102)).length() < 0.01 \
		or (c1 - Vector2(101, 102)).length() < 0.01)


func _test_wild_spawn() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var boar: Dictionary = a.spawn_wild("boar", Vector2(500, 500))
	_check("wild boar spawned", not boar.is_empty())
	_check("wild flag set", bool(boar.get("wild", false)))
	_check("wild alive", bool(boar.get("alive", false)))
	_check("in wild list", a.wild.size() == 1)
	var wolf: Dictionary = a.spawn_wild("wolf", Vector2(600, 600))
	_check("wolf spawned", String(wolf.get("type", "")) == "wolf")
	_check("living_wild counts 2", a.living_wild().size() == 2)


func _test_wild_seed() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var no_water := func(_p: Vector2) -> bool: return false
	a.seed_wildlife([Vector2(2000, 2000)], no_water, 4000.0, 4000.0)
	# 80 scattered + 6 near town + 8 wolves + 2 stray cats per town.
	_check("wildlife seeded", a.wild.size() == 96)
	var wolves := 0
	var cats := 0
	for an in a.wild:
		if String(an.get("type", "")) == "wolf":
			wolves += 1
		if String(an.get("type", "")) == "cat":
			cats += 1
	_check("8 wolves", wolves == 8)
	_check("2 stray cats", cats == 2)


func _test_wild_hunt() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var a = pack[2]
	var prey: Dictionary = a.spawn_wild("boar", Vector2(100, 100))
	var found: Dictionary = a.nearest_wild(Vector2(110, 110), 800.0)
	_check("nearest wild found", int(found.get("id", -1)) == int(prey.get("id", -1)))
	var far: Dictionary = a.nearest_wild(Vector2(5000, 5000), 800.0)
	_check("none in range far away", far.is_empty())
	# Damage it to death — meat returned.
	var meat := 0.0
	for i in 10:
		meat = a.damage_wild(prey, 8.0)
		if meat > 0.0:
			break
	_check("kill yields meat", meat > 0.0)
	_check("prey dead", not bool(prey.get("alive", false)))
	_check("meat matches boar food",
		is_equal_approx(meat, float(SimAnimals.ANIMAL_TYPES["boar"]["food"])))


func _test_wolf_predation() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var a = pack[2]
	# Wolf next to a sheep: wolf should chase and kill it.
	var wolf: Dictionary = a.spawn_wild("wolf", Vector2(100, 100))
	var sheep: Dictionary = a.spawn_wild("sheep", Vector2(110, 100))
	_check("sheep alive before", bool(sheep.get("alive", false)))
	# Tick enough for the wolf to close 10px and bite through sheep hp.
	for i in 200:
		a.tick(0.5)
		if not bool(sheep.get("alive", true)):
			break
	_check("wolf killed sheep", not bool(sheep.get("alive", true)))
	_check("wolf survived", bool(wolf.get("alive", false)))


func _test_wild_fear() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var a = pack[2]
	var boar: Dictionary = a.spawn_wild("boar", Vector2(100, 100))
	# Put a unit right next to it — boar should get scared and flee.
	var u: Dictionary = {"id": 1, "alive": true, "position": Vector2(105, 100)}
	gs.units.append(u)
	var start: Vector2 = boar.get("position", Vector2.ZERO)
	# Jeremy 2026-10-05 perf: wild brains think round-robin at 20Hz, so the
	# boar reacts within a few ticks, flees out of the 70px fear radius, and
	# calms back down — peak fear (not end-state fear) proves it got scared.
	var peak_fear := 0.0
	for i in 20:
		a.tick(0.5)
		peak_fear = maxf(peak_fear, float(boar.get("fear", 0.0)))
	_check("boar feared", peak_fear > 0.0)
	var moved: float = start.distance_to(boar.get("position", start))
	_check("boar fled", moved > 5.0)


## Jeremy 2026-10-05: a boar with a wolf nearby RUNS (sprint, not trot).
func _test_boar_flees_wolf() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var a = pack[2]
	var boar: Dictionary = a.spawn_wild("boar", Vector2(100, 100))
	var wolf: Dictionary = a.spawn_wild("wolf", Vector2(180, 100))
	var start: Vector2 = boar.get("position", Vector2.ZERO)
	var peak_fear := 0.0
	var ever_ran := false
	for i in 30:
		a.tick(0.5)
		peak_fear = maxf(peak_fear, float(boar.get("fear", 0.0)))
		if bool(boar.get("running", false)):
			ever_ran = true
	_check("boar feared by wolf", peak_fear >= 99.0)
	_check("boar ran from wolf", ever_ran)
	var moved: float = start.distance_to(boar.get("position", start))
	_check("boar sprinted away", moved > 50.0)
	_check("wolf alive", bool(wolf.get("alive", false)))
	gs.queue_free()


## Jeremy 2026-10-05: wolf bites trigger the attack anim, hurt the victim,
## and spray blood through the combat_fx bus.
func _test_wolf_bite_blood() -> void:
	var pack: Array = _new_farm_stack(["humans"])
	var gs: GameState = pack[0]
	var a = pack[2]
	var wolf: Dictionary = a.spawn_wild("wolf", Vector2(100, 100))
	var sheep: Dictionary = a.spawn_wild("sheep", Vector2(110, 100))
	var blood_hits: Array = []
	gs.bus.combat_fx.connect(func(kind: String, _pos: Vector2) -> void:
		if kind == "blood":
			blood_hits.append(1))
	var saw_attack := false
	var saw_hurt := false
	for i in 60:
		a.tick(0.5)
		if float(wolf.get("attack_t", 0.0)) > 0.0:
			saw_attack = true
		if float(sheep.get("hurt_t", 0.0)) > 0.0:
			saw_hurt = true
		if not bool(sheep.get("alive", true)):
			break
	_check("wolf attack anim triggered", saw_attack)
	_check("victim hurt anim triggered", saw_hurt)
	_check("blood fx emitted", not blood_hits.is_empty())
	gs.queue_free()
