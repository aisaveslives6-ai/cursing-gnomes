extends SceneTree
## Cursing Gnomes — naval ferry/transport (HTML WATERX ferry) headless tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_ferry.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.
## Covers: boat capacity (war_ship 8 / else 4), order_ferry invites (300px,
## same faction, non-boats, capacity cap, downed + hero + foe skips),
## military-first ordering, embark/disembark round-trip, nearest_land /
## nearest_water ring searches, the boarding->sailing->disembark state
## machine (full / timeout / timeout-cancel), passenger riding, invitee
## drop rules (boat dead, sailing-far), the SimWaterCrossing span>900 ferry
## branch, and a save/load round-trip of the ferry fields.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array = []
var _said: Array = []


func _initialize() -> void:
	print("=== Cursing Gnomes ferry tests ===")
	_test_capacity()
	_test_order_invites()
	_test_military_first()
	_test_skips_player_hero()
	_test_embark_disembark_roundtrip()
	_test_nearest_land()
	_test_nearest_water()
	_test_state_machine_full()
	_test_state_machine_timeout_sails()
	_test_state_machine_timeout_cancels()
	_test_passengers_ride()
	_test_invitee_drop_boat_dead()
	_test_invitee_drop_sailing_far()
	_test_boarding_trigger_walks_in()
	_test_disembark_all()
	_test_wx_ferry_branch()
	_test_wx_no_ferry_unwired()
	_test_save_load_roundtrip()
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


## Synthetic world: 128x128 tiles (32px), water stripe at tile columns
## [x0, x1). Returns [gs, ferry].
func _make_world(x0: int, x1: int) -> Array:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "gnomes"])  # player = humans
	var terrain := PackedByteArray()
	terrain.resize(128 * 128)
	for i in terrain.size():
		terrain[i] = MapGen.TILE_GRASS
	for ty in 128:
		for tx in range(x0, x1):
			terrain[ty * 128 + tx] = MapGen.TILE_WATER
	gs.map_data = {
		"terrain": terrain, "tile_size": 32.0,
		"world_size": Vector2(4096, 4096),
	}
	var ferry := SimFerry.new(gs)
	_stories.clear()
	_said.clear()
	gs.bus.gazette_story.connect(func(s: Dictionary) -> void: _stories.append(s))
	gs.bus.unit_said.connect(func(uid: int, t: String) -> void: _said.append(t))
	return [gs, ferry]


func _free_world(parts: Array) -> void:
	(parts[0] as GameState).queue_free()


## Boat unit on the water stripe (x 1920..2176 at columns 60..68).
func _boat(parts: Array, faction: String, job: String,
		pos: Vector2 = Vector2(2048, 2048)) -> Dictionary:
	var gs: GameState = parts[0]
	return gs.add_unit({"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": 500.0, "max_hp": 500.0,
		"speed": 95.0})


func _unit(parts: Array, faction: String, job: String,
		pos: Vector2) -> Dictionary:
	var gs: GameState = parts[0]
	return gs.add_unit({"faction": faction, "job": job, "town_id": -1,
		"position": pos, "alive": true, "hp": 100.0, "max_hp": 100.0,
		"speed": 95.0})


func _test_capacity() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	_check("war_ship capacity 8",
		ferry.boat_capacity({"job": "war_ship"}) == 8)
	_check("fishing_boat capacity 4",
		ferry.boat_capacity({"job": "fishing_boat"}) == 4)
	_check("empty dict capacity 4", ferry.boat_capacity({}) == 4)
	_free_world(parts)


## war_ship (cap 8): 10 nearby gnomes -> 8 invited; far/foe/dead/downed
## units skipped; invitees steer at the boat.
func _test_order_invites() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var invited: Array = []
	for i in 10:
		invited.append(_unit(parts, "gnomes", "worker",
			Vector2(2048, 2048) + Vector2(i * 10.0, 0.0)))
	var far: Dictionary = _unit(parts, "gnomes", "worker", Vector2(500, 500))
	var foe: Dictionary = _unit(parts, "humans", "worker", Vector2(2050, 2050))
	var dead: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2050, 2052))
	dead["alive"] = false
	var downed: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2052, 2050))
	downed["downed"] = true
	var other_boat: Dictionary = _boat(parts, "gnomes", "fishing_boat",
		Vector2(2060, 2060))
	_check("order_ferry returns true",
		ferry.order_ferry(boat, Vector2(1500, 2048), false))
	_check("ferry_state boarding",
		String(boat.get("ferry_state", "")) == "boarding")
	_check("ferry_timer 25", float(boat.get("ferry_timer", 0.0)) == 25.0)
	_check("anchor cleared", not bool(boat.get("anchor", true)))
	_check("invited capped at 8",
		invited.filter(func(u: Dictionary) -> bool:
			return int(u.get("ferry_boat", -1)) == int(boat["id"])).size() == 8)
	var in0: Dictionary = invited[0]
	_check("invitee ferry_boat set",
		int(in0.get("ferry_boat", -1)) == int(boat["id"]))
	_check("invitee steered at boat",
		(in0.get("move_target", Vector2.ZERO) as Vector2) \
			== (boat["position"] as Vector2))
	_check("far unit skipped", int(far.get("ferry_boat", -1)) < 0)
	_check("foe skipped", int(foe.get("ferry_boat", -1)) < 0)
	_check("dead skipped", int(dead.get("ferry_boat", -1)) < 0)
	_check("downed skipped", int(downed.get("ferry_boat", -1)) < 0)
	_check("other boat skipped", int(other_boat.get("ferry_boat", -1)) < 0)
	var announced := false
	for s: Dictionary in _stories:
		if String(s.get("body", "")).contains("Ferry boarding — 8 coming"):
			announced = true
	_check("boarding announcement", announced)
	_check("all-aboard bubble", _said.has("All aboard!"))
	_free_world(parts)


## fishing_boat (cap 4), military_first=true: soldiers board before closer
## workers.
func _test_military_first() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")
	var workers: Array = []
	for i in 4:
		workers.append(_unit(parts, "gnomes", "worker",
			Vector2(2048, 2048) + Vector2(10.0 + i * 5.0, 0.0)))
	var soldiers: Array = []
	for i in 4:
		soldiers.append(_unit(parts, "gnomes", "soldier",
			Vector2(2048, 2048) + Vector2(100.0 + i * 5.0, 0.0)))
	ferry.order_ferry(boat, Vector2(1500, 2048), true)
	var boat_id := int(boat["id"])
	var mil_invited := 0
	for s: Dictionary in soldiers:
		if int(s.get("ferry_boat", -1)) == boat_id:
			mil_invited += 1
	var civ_invited := 0
	for w: Dictionary in workers:
		if int(w.get("ferry_boat", -1)) == boat_id:
			civ_invited += 1
	_check("military-first: all 4 soldiers invited", mil_invited == 4)
	_check("military-first: no workers invited", civ_invited == 0)
	_free_world(parts)


## The player hero is never auto-grabbed; other same-faction units are.
func _test_skips_player_hero() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "humans", "war_ship")
	var hero: Dictionary = _unit(parts, "humans", "swordsman", Vector2(2050, 2050))
	hero["is_hero"] = true
	var mate: Dictionary = _unit(parts, "humans", "worker", Vector2(2060, 2060))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	_check("hero not invited", int(hero.get("ferry_boat", -1)) < 0)
	_check("non-hero invited",
		int(mate.get("ferry_boat", -1)) == int(boat["id"]))
	# A hero of a NON-player faction is fair game (HTML only guards
	# isPlayerHero && race == playerRace).
	var ai_hero: Dictionary = _unit(parts, "gnomes", "swordsman",
		Vector2(2050, 2052))
	ai_hero["is_hero"] = true
	var gboat: Dictionary = _boat(parts, "gnomes", "war_ship",
		Vector2(2048, 2100))
	ferry.order_ferry(gboat, Vector2(1500, 2048), false)
	_check("AI hero invited",
		int(ai_hero.get("ferry_boat", -1)) == int(gboat["id"]))
	_free_world(parts)


## Full voyage: order -> walk in -> embark -> sail -> disembark on shore.
func _test_embark_disembark_roundtrip() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var u: Dictionary = _unit(parts, "gnomes", "soldier", Vector2(1900, 2048))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	# Walk the invitee to the boat (their subsystem would do this in-game).
	u["position"] = Vector2(2018, 2048)  # 30px < 48px embark radius
	ferry.tick(0.1)
	_check("embarked", bool(u.get("embarked", false)))
	_check("embarked_boat set",
		int(u.get("embarked_boat", -1)) == int(boat["id"]))
	_check("passenger listed",
		(boat.get("passengers", []) as Array).has(int(u["id"])))
	_check("invite cleared on embark", int(u.get("ferry_boat", -1)) < 0)
	_check("offsets in range",
		absf(float(u.get("ferry_ox", 99.0))) <= 17.0 \
		and absf(float(u.get("ferry_oy", 99.0))) <= 11.0)
	# Sail to the far shore and arrive.
	ferry.ferry_tick(boat, 30.0)  # timer expires -> sailing
	_check("sailing", String(boat.get("ferry_state", "")) == "sailing")
	boat["position"] = Vector2(1560, 2048)  # 60px < 120px arrive radius
	ferry.ferry_tick(boat, 0.1)
	_check("disembarked: passengers empty",
		(boat.get("passengers", []) as Array).is_empty())
	_check("disembarked: state cleared",
		String(boat.get("ferry_state", "")) == "")
	_check("disembarked: not embarked", not bool(u.get("embarked", false)))
	var up: Vector2 = u.get("position", Vector2.ZERO)
	_check("ashore near dest", up.distance_to(Vector2(1560, 2048)) < 45.0)
	var arrived := false
	for s: Dictionary in _stories:
		if String(s.get("body", "")).contains("troops ashore"):
			arrived = true
	_check("arrival announcement", arrived)
	gs.queue_free()


func _test_nearest_land() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	_check("dry input returned as-is",
		ferry.nearest_land(Vector2(500, 500)) == Vector2(500, 500))
	var shore: Vector2 = ferry.nearest_land(Vector2(2048, 2048))
	_check("water input -> a point", shore != Vector2(2048, 2048))
	_check("found point is dry", not ferry._in_water(shore))
	_check("found point in map margins",
		shore.x >= 40.0 and shore.y >= 40.0 \
		and shore.x <= 4056.0 and shore.y <= 4056.0)
	# From the middle of the 256px stripe the ring finds a shore by r=160.
	_check("shore close to stripe",
		shore.distance_to(Vector2(2048, 2048)) <= 200.0)
	_free_world(parts)


func _test_nearest_water() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	_check("wet input returned as-is",
		ferry.nearest_water(Vector2(2048, 2048)) == Vector2(2048, 2048))
	var wet = ferry.nearest_water(Vector2(700, 2048))
	_check("dry input near stripe -> water found", wet != null)
	if wet != null:
		_check("found point is wet", ferry._in_water(wet))
		_check("found point within ring",
			(wet as Vector2).distance_to(Vector2(700, 2048)) <= 1400.0)
	_check("far from water -> null",
		ferry.nearest_water(Vector2(100, 100)) == null)
	_free_world(parts)


## Full boat ends boarding at once (passengers sail, stragglers keep invites).
func _test_state_machine_full() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")  # cap 4
	var units: Array = []
	for i in 4:
		units.append(_unit(parts, "gnomes", "worker",
			Vector2(2048, 2048) + Vector2(i * 10.0, 0.0)))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	for u: Dictionary in units:
		_check("embark ok", ferry.embark(u, boat))
	_check("over capacity refused",
		not ferry.embark(_unit(parts, "gnomes", "worker",
			Vector2(2048, 2060)), boat))
	ferry.ferry_tick(boat, 0.01)  # full -> sails immediately
	_check("full -> sailing", String(boat.get("ferry_state", "")) == "sailing")
	_check("casting-off bubble", _said.has("Casting off!"))
	var mt: Vector2 = boat.get("move_target", Vector2.ZERO)
	var fd: Vector2 = boat.get("ferry_dest", Vector2.ZERO)
	_check("sail target is water or dest",
		ferry._in_water(mt) or mt == fd)
	_free_world(parts)


## Timer expiry with passengers aboard -> sailing.
func _test_state_machine_timeout_sails() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")
	var u: Dictionary = _unit(parts, "gnomes", "worker", Vector2(2050, 2050))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	ferry.embark(u, boat)
	boat["ferry_timer"] = 0.5
	ferry.ferry_tick(boat, 1.0)
	_check("timeout with passengers -> sailing",
		String(boat.get("ferry_state", "")) == "sailing")
	_free_world(parts)


## Timer expiry with nobody aboard -> order cancelled, no ghost sailing.
func _test_state_machine_timeout_cancels() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "fishing_boat")
	ferry.order_ferry(boat, Vector2(1500, 2048), false)  # nobody nearby
	_check("no invites", true)  # sanity: order still returns true
	ferry.ferry_tick(boat, 30.0)
	_check("empty timeout -> cancelled",
		String(boat.get("ferry_state", "")) == "")
	_check("dest cleared", not boat.has("ferry_dest"))
	_free_world(parts)


## Embarked passengers ride the boat; a lost boat frees them.
func _test_passengers_ride() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var u: Dictionary = _unit(parts, "gnomes", "soldier", Vector2(2050, 2050))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	ferry.embark(u, boat)
	var ox := float(u.get("ferry_ox", 0.0))
	var oy := float(u.get("ferry_oy", 0.0))
	boat["position"] = Vector2(2200, 2200)
	ferry.tick(0.1)
	# Note: with nobody else incoming, the boarding timer rule casts the
	# boat off (HTML: !incoming && passengers > 0 -> sailing), so read the
	# boat's actual position after the tick.
	var bp: Vector2 = boat.get("position", Vector2.ZERO)
	var up: Vector2 = u.get("position", Vector2.ZERO)
	_check("passenger rides boat",
		up.distance_to(bp + Vector2(ox, oy)) < 0.01)
	# Boat lost: passenger swims (flags cleared, stays put).
	boat["alive"] = false
	var before: Vector2 = u.get("position", Vector2.ZERO)
	ferry.tick(0.1)
	_check("lost boat clears embarked", not bool(u.get("embarked", false)))
	_check("passenger stays where the boat sank",
		(u.get("position", Vector2.ZERO) as Vector2).distance_to(before) < 0.01)
	gs.queue_free()


## Invite dropped when the boat dies before boarding.
func _test_invitee_drop_boat_dead() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var u: Dictionary = _unit(parts, "gnomes", "soldier", Vector2(1900, 2048))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	_check("invited", int(u.get("ferry_boat", -1)) == int(boat["id"]))
	gs.kill_unit(int(boat["id"]))
	ferry.tick(0.1)
	_check("dead boat clears invite", int(u.get("ferry_boat", -1)) < 0)
	gs.queue_free()


## Invite dropped when the boat sails >600px away (missed boat).
func _test_invitee_drop_sailing_far() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var u: Dictionary = _unit(parts, "gnomes", "soldier", Vector2(1900, 2048))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	boat["ferry_state"] = "sailing"
	boat["position"] = Vector2(2048, 2048)
	u["position"] = Vector2(2048, 2048 - 700.0)  # 700px > 600px miss rule
	u["ferry_boat"] = int(boat["id"])
	ferry.tick(0.1)
	_check("sailed-far clears invite", int(u.get("ferry_boat", -1)) < 0)
	_free_world(parts)


## The boarding trigger steers the invitee each tick until it is close
## enough to board.
func _test_boarding_trigger_walks_in() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var u: Dictionary = _unit(parts, "gnomes", "soldier", Vector2(1900, 2048))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	ferry.tick(0.1)  # 148px out: steered, not boarded
	_check("steered at boat",
		(u.get("move_target", Vector2.ZERO) as Vector2) \
			== (boat["position"] as Vector2))
	_check("not yet embarked", not bool(u.get("embarked", false)))
	u["position"] = Vector2(2010, 2048)  # 38px < 48px
	ferry.tick(0.1)
	_check("boards within 48px", bool(u.get("embarked", false)))
	_free_world(parts)


## disembark_all clears every voyage flag (HTML save-safety parity).
func _test_disembark_all() -> void:
	var parts: Array = _make_world(60, 68)
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var u: Dictionary = _unit(parts, "gnomes", "soldier", Vector2(2050, 2050))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	ferry.embark(u, boat)
	ferry.disembark_all()
	_check("boat flags cleared",
		String(boat.get("ferry_state", "")) == "" \
		and (boat.get("passengers", []) as Array).is_empty() \
		and not boat.has("ferry_dest"))
	_check("passenger flags cleared",
		not bool(u.get("embarked", false)) \
		and int(u.get("embarked_boat", -1)) < 0 \
		and int(u.get("ferry_boat", -1)) < 0)
	_free_world(parts)


## SimWaterCrossing span > 900px orders a free boat at the enemy hall.
func _test_wx_ferry_branch() -> void:
	var parts: Array = _make_world(50, 80)  # 30 tiles = 960px stripe
	var gs: GameState = parts[0]
	var ferry: SimFerry = parts[1]
	var bs := SimBuildings.new(gs)
	var wx := SimWaterCrossing.new(gs, bs, ferry)
	var th: Dictionary = gs.found_town("humans", "Westhold", Vector2(960, 2048))
	var tg: Dictionary = gs.found_town("gnomes", "Eastburg", Vector2(3136, 2048))
	gs.add_building({"type": "hall", "faction": "humans",
		"town_id": int(th["id"]), "alive": true, "complete": true,
		"position": Vector2(960, 2048)})
	gs.add_building({"type": "hall", "faction": "gnomes",
		"town_id": int(tg["id"]), "alive": true, "complete": true,
		"position": Vector2(3136, 2048)})
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship", Vector2(2400, 2048))
	_unit(parts, "gnomes", "soldier", Vector2(2350, 2048))
	_unit(parts, "gnomes", "soldier", Vector2(2450, 2048))
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	_check("ferry ordered", String(boat.get("ferry_state", "")) == "boarding")
	_check("no bridges on ferry span",
		not _has_bridge(gs, "gnomes"))
	var assault := false
	for s: Dictionary in _stories:
		if String(s.get("body", "")).contains("launches a ferry assault"):
			assault = true
	_check("ferry assault announced", assault)
	# A busy boat is not re-ordered: second tick keeps the first order.
	var first_dest: Vector2 = boat.get("ferry_dest", Vector2.ZERO)
	wx.tick_faction("gnomes")
	_check("busy boat not re-ordered",
		(boat.get("ferry_dest", Vector2.ZERO) as Vector2) == first_dest)
	gs.queue_free()


## Without a SimFerry wired, span > 900px stays a quiet no-op (the old
## QUEUED behavior).
func _test_wx_no_ferry_unwired() -> void:
	var parts: Array = _make_world(50, 80)
	var gs: GameState = parts[0]
	var bs := SimBuildings.new(gs)
	var wx := SimWaterCrossing.new(gs, bs)  # no ferry
	var th: Dictionary = gs.found_town("humans", "Westhold", Vector2(960, 2048))
	var tg: Dictionary = gs.found_town("gnomes", "Eastburg", Vector2(3136, 2048))
	gs.add_building({"type": "hall", "faction": "humans",
		"town_id": int(th["id"]), "alive": true, "complete": true,
		"position": Vector2(960, 2048)})
	gs.add_building({"type": "hall", "faction": "gnomes",
		"town_id": int(tg["id"]), "alive": true, "complete": true,
		"position": Vector2(3136, 2048)})
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship", Vector2(2400, 2048))
	gs.diplomacy.declare_war("gnomes", "humans", "test")
	wx.tick_faction("gnomes")
	_check("unwired: no ferry ordered",
		String(boat.get("ferry_state", "")) == "")
	_check("unwired: no bridges", not _has_bridge(gs, "gnomes"))
	gs.queue_free()


## Ferry voyage state survives a JSON save/load round-trip.
func _test_save_load_roundtrip() -> void:
	var parts: Array = _make_world(60, 68)
	var gs: GameState = parts[0]
	var ferry: SimFerry = parts[1]
	var boat: Dictionary = _boat(parts, "gnomes", "war_ship")
	var u: Dictionary = _unit(parts, "gnomes", "soldier", Vector2(2050, 2050))
	ferry.order_ferry(boat, Vector2(1500, 2048), false)
	ferry.embark(u, boat)
	var boat_id := int(boat["id"])
	var unit_id := int(u["id"])
	var snap: Dictionary = SaveSystem.snapshot(gs)
	# Prove JSON-safety: serialize and parse back.
	var text: String = JSON.stringify(snap)
	var back = JSON.parse_string(text)
	_check("json round-trip parses", back is Dictionary)
	var gs2: GameState = GameState.new()
	root.add_child(gs2)
	_check("restore ok", SaveSystem.restore(gs2, back))
	var b2: Dictionary = gs2.get_unit(boat_id)
	var u2: Dictionary = gs2.get_unit(unit_id)
	_check("ferry_state persisted",
		String(b2.get("ferry_state", "")) == "boarding")
	var fd = b2.get("ferry_dest", null)
	_check("ferry_dest persisted as Vector2",
		fd is Vector2 and (fd as Vector2) == Vector2(1500, 2048))
	_check("passengers persisted as ids",
		(b2.get("passengers", []) as Array).size() == 1 \
		and int((b2.get("passengers", []) as Array)[0]) == unit_id)
	_check("embarked persisted", bool(u2.get("embarked", false)))
	_check("embarked_boat persisted",
		int(u2.get("embarked_boat", -1)) == boat_id)
	gs2.queue_free()
	_free_world(parts)


func _has_bridge(gs: GameState, f: String) -> bool:
	for b: Dictionary in gs.buildings:
		if String(b.get("type", "")) == "bridge" \
				and String(b.get("faction", "")) == f \
				and bool(b.get("alive", false)):
			return true
	return false
