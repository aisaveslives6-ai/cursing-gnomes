extends SceneTree
## Cursing Gnomes — AI military construction regression tests.
## Jeremy 2026-10-07 bug report: "AI factions not building any military
## buildings." Root causes found across two passes:
##   (a) SimAIDirector._train's "no barracks" branch placed a barracks
##       blueprint EVERY THINK until one completed (~13 thinks), burning
##       100 oil per duplicate and oil-starving all other military
##       construction. Fixed by gating on _count_build (blueprints
##       included).
##   (b) The _build_essentials barracks queue entry used the hall-centered
##       default spot (±140px), which never clears the hall's footprint +
##       PLACEMENT_GAP (0/40 validations) — so the queue could never place
##       a barracks at all; and cheap oil spenders (AA towers, medic camps)
##       drank the pump-oil trickle before 100 oil could accumulate.
##       Fixed with a barracks military-ring spot + oil triage (first
##       barracks, then the elite war building, reserve their oil cost).
##   (c) Jeremy 2026-10-08: ~1/3 flake — the AI never placed a pump in 20
##       thinks. Root cause: the industrial zone fills with town clutter
##       (houses, farms, war buildings at ring spots) and the pump's single
##       random point + 8-ring zone-constrained search failed every think,
##       so the faction burned its 600 starting oil with no income to
##       replace it. Fixed two ways: oil pumps moved to the FRONT of the
##       build queue (income before spenders), and a systematic grid scan
##       of the zone (_pump_grid_spot) backs up the random-point search.
## NOTE: the queue's HTML-verbatim barracks want is max(2, barracks+1), so
## a working queue raises up to 2 barracks by design — the "no duplicates"
## regression below means no _train dupe-spam beyond the queue's want,
## not "exactly one barracks".
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ai_military_buildings.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes AI military building tests ===")
	_test_no_duplicate_barracks()
	_test_barracks_completes()
	_test_oil_not_drained()
	_test_barracks_trains_roster()
	_test_military_units_spawn()
	_test_oil_pumps_first()
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


## Live-like world: AI faction with the starting stockpiles world.gd grants
## (600 oil), a real town, hiring + zoning wired.
func _make_world() -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes", "ogres"])  # player = humans
	gs.map_data = {"world_w": 4096.0, "world_h": 4096.0}
	gs.zoning = SimZoning.new(gs)
	gs.hiring = GuildHiring.new(gs)
	var director := SimAIDirector.new(gs)
	var t: Dictionary = gs.found_town("gnomes", "Teston", Vector2(1000, 1000))
	var tid := int(t.get("id", 1))
	gs.add_building({"type": "town_hall", "faction": "gnomes",
		"town_id": tid, "position": Vector2(1000, 1000), "alive": true,
		"complete": true, "progress": 1.0, "hp": 2000.0, "max_hp": 2000.0})
	# Live starting stockpiles (world.gd _grant_starting_resources).
	gs.resources.add_resource("gnomes", "wood", 1000.0, true)
	gs.resources.add_resource("gnomes", "oil", 600.0, true)
	gs.resources.add_resource("gnomes", "gold", 250.0, true)
	gs.resources.add_resource("gnomes", "food", 120.0, true)
	for i in 6:
		gs.spawner.spawn_unit("gnomes", "worker", tid,
			Vector2(1040 + i * 20, 1040))
	return [gs, director, tid]


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


func _barracks_count(gs: GameState) -> int:
	var n := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes" \
				and bool(b.get("alive", false)) \
				and String(b.get("type", "")) == "barracks":
			n += 1
	return n


## The core regression: 20 thinks must not stack duplicate barracks
## blueprints. (Pre-fix: 3-6 blueprints from _train dupe-spam, oil drained
## 600 -> 0.) The queue's HTML-verbatim want is max(2, barracks+1), so up
## to 2 queue-placed barracks is by design — the regression is _train not
## stacking extras beyond that.
func _test_no_duplicate_barracks() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for t in 20:
		director._think("gnomes")
	_check("mil: no duplicate barracks blueprints",
		_barracks_count(gs) <= 2)
	_free_world(parts)


## The single barracks blueprint completes via the AI construction drip.
func _test_barracks_completes() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for t in 20:
		director._think("gnomes")
	var done := false
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes" \
				and String(b.get("type", "")) == "barracks" \
				and bool(b.get("complete", false)):
			done = true
	_check("mil: barracks completes", done)
	_free_world(parts)


## The AI secures its oil income (pumps) instead of burning the stockpile
## on duplicate barracks with no way to replenish (pre-fix: 600 -> 0.0
## with zero pumps built yet and 3+ barracks blueprints).
func _test_oil_not_drained() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for t in 20:
		director._think("gnomes")
	var pumps := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) == "gnomes" \
				and bool(b.get("alive", false)) \
				and String(b.get("type", "")) == "oil_pump":
			pumps += 1
	_check("mil: AI builds oil pumps (income secured)", pumps >= 1)
	# Queue want is max(2, barracks+1) per HTML — up to 2 by design.
	_check("mil: barracks raised within queue want", _barracks_count(gs) <= 2
		and _barracks_count(gs) >= 1)
	_free_world(parts)


## A completed barracks queues the military roster through the director.
func _test_barracks_trains_roster() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var br: Dictionary = gs.add_building({"type": "barracks",
		"faction": "gnomes", "town_id": int(parts[2]),
		"position": Vector2(1400, 1000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 800.0, "max_hp": 800.0})
	director._think("gnomes")
	var queued := 0
	for job: Dictionary in br.get("train_queue", []):
		if JobDefs.is_military(String(job.get("unit_type", ""))):
			queued += 1
	_check("mil: barracks queues military units", queued >= 1)
	_free_world(parts)


## End to end: a queued soldier graduates into a live military unit.
func _test_military_units_spawn() -> void:
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	var tid := int(parts[2])
	var br: Dictionary = gs.add_building({"type": "barracks",
		"faction": "gnomes", "town_id": tid,
		"position": Vector2(1400, 1000), "alive": true, "complete": true,
		"progress": 1.0, "hp": 800.0, "max_hp": 800.0})
	_check("mil: soldier queues",
		(gs.hiring as GuildHiring).queue_training(br, "soldier", false))
	# TRAIN_TIME ~4s: tick training until graduation + spawn.
	for i in 40:
		(gs.hiring as GuildHiring).tick(0.5, 12.0)
	var soldiers := 0
	for u: Dictionary in gs.units:
		if String(u.get("faction", "")) == "gnomes" \
				and bool(u.get("alive", false)) \
				and String(u.get("job", "")) == "soldier":
			soldiers += 1
	_check("mil: soldier spawns from barracks", soldiers >= 1)
	_free_world(parts)


## Jeremy 2026-10-08: income before spenders. Oil pumps sit at the FRONT
## of the build queue, so the faction secures oil income from think 1
## instead of burning its starting stockpile on military with no way to
## replenish. Deterministic where the old code failed: with pumps behind
## ~6-11 phase entries at 2 placements/think, zero pumps stood after 4
## thinks; now at least 2 do, all inside the industrial zone (so they
## actually produce 0.8 oil/s via SimZoning.tick). 2026-10-08 follow-up:
## pumps also bypass the UNFINISHED_CAP gate (per-entry skip, not the old
## whole-phase early-return) — other think subsystems can flood think 1
## with 8+ unfinished blueprints, which starved the pump queue on every
## later think (seed-probed: ~15% of fresh games placed only 1 pump in
## 4 thinks while the starting oil burned away).
func _test_oil_pumps_first() -> void:
	# Jeremy 2026-10-08 (deflake): pump placement rolls RNG — unseeded,
	# gate load flips this check. Seeded, the director's 4 thinks are
	# deterministic. Test-only; sim mechanics untouched.
	seed(20261008)
	var parts: Array = _make_world()
	var gs: GameState = parts[0]
	var director: SimAIDirector = parts[1]
	for t in 4:
		director._think("gnomes")
	var pumps := 0
	var in_zone := 0
	for b: Dictionary in gs.buildings:
		if String(b.get("faction", "")) != "gnomes":
			continue
		if not bool(b.get("alive", false)):
			continue
		if String(b.get("type", "")) != "oil_pump":
			continue
		pumps += 1
		if gs.zoning.zone_at(b.get("position", Vector2.ZERO), "gnomes") \
				== SimZoning.INDUSTRIAL:
			in_zone += 1
	_check("mil: oil pumps placed first (income secured early)", pumps >= 2)
	_check("mil: early pumps sit inside the industrial zone",
		pumps > 0 and in_zone == pumps)
	_free_world(parts)
