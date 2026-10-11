extends SceneTree
## Cursing Gnomes — Milestone 6 headless interior & phone tests.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_phone_interior.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes interior & phone tests ===")
	_test_interior_enter_exit()
	_test_interior_blocked()
	_test_interior_furniture()
	_test_interior_arrange()
	_test_interior_find_need()
	_test_art_keys()
	_test_gov_contacts_pinned()
	_test_enemy_commander_groups()
	_test_contacts_player_added_only()
	_test_messenger_reply_offline()
	_test_messenger_sort()
	_test_messenger_sort_switcher()
	_test_messenger_latest_sort()
	_test_bio_memories_only()
	_test_ruler_name_verbatim_phone()
	_test_squabble()
	_test_gazette_real_events()
	_test_petition_decision()
	_test_phone_ui_screens()
	_test_home_icon_wiggle()
	_test_phone_status_x_back()
	_test_diplo_big_buttons()
	_test_diplo_war_confirm()
	_test_interior_view_open_close()
	_test_interior_occupant_sprites()
	_test_forecast_app()
	_test_home_weather_widget()
	_test_boot_splash()
	_test_phone_frame_rect()
	_test_phone_rotation_refit()
	_test_polish_chevron()
	_test_polish_notifications()
	_test_polish_timestamps()
	_test_thread_item_tap_vs_drag()
	_test_thread_item_scroll_suppresses_tap()
	_test_affinity_meter()
	_test_launch_readiness_ui_fits()
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


## Fresh game + M6 systems.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var mind := SimMind.new(gs)
	var interiors := SimInteriors.new(gs)
	var phone := SimPhone.new(gs)
	var court := SimRoyalCourt.new(gs)
	return {"gs": gs, "mind": mind, "interiors": interiors,
		"phone": phone, "court": court}


func _spawn(w: Dictionary, faction: String, job: String) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var u: Dictionary = gs.spawner.spawn_unit(faction, job, -1, Vector2(100, 100))
	mind.ensure(u)
	return u


func _house(w: Dictionary, complete: bool = true) -> Dictionary:
	var gs: GameState = w["gs"]
	return gs.add_building({"type": "house", "faction": "humans",
		"town_id": -1, "position": Vector2(200, 200), "alive": true,
		"complete": complete, "progress": 1.0 if complete else 0.2,
		"hp": 400.0, "max_hp": 400.0})


## --- interiors ---

func _test_interior_enter_exit() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var intr: SimInteriors = w["interiors"]
	var b: Dictionary = _house(w)
	var u: Dictionary = _spawn(w, "humans", "worker")
	_check("enter ok", intr.enter(b, u) == true)
	_check("is_inside", SimInteriors.is_inside(u) == true)
	_check("occupant listed", intr.occupants_of(b).has(int(u["id"])))
	_check("exit ok", intr.exit(u) == true)
	_check("outside now", SimInteriors.is_inside(u) == false)
	_check("occupant removed", not intr.occupants_of(b).has(int(u["id"])))
	_check("exit twice fails", intr.exit(u) == false)
	gs.queue_free()


func _test_interior_blocked() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var intr: SimInteriors = w["interiors"]
	var u: Dictionary = _spawn(w, "humans", "worker")
	# Incomplete blueprint can't be entered.
	var blue: Dictionary = _house(w, false)
	_check("blueprint blocked", intr.enter(blue, u) == false)
	# Walls have no interior.
	var wall: Dictionary = gs.add_building({"type": "wall", "faction": "humans",
		"town_id": -1, "position": Vector2(300, 300), "alive": true,
		"complete": true, "progress": 1.0, "hp": 900.0, "max_hp": 900.0})
	_check("wall not enterable", SimInteriors.is_enterable("wall") == false)
	_check("wall enter blocked", intr.enter(wall, u) == false)
	# Dead units can't enter.
	var b: Dictionary = _house(w)
	gs.kill_unit(int(u["id"]))
	_check("dead blocked", intr.enter(b, u) == false)
	gs.queue_free()


func _test_interior_furniture() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var intr: SimInteriors = w["interiors"]
	var b: Dictionary = _house(w)
	var furn: Array = intr.furniture_of(b)
	_check("house has furniture", furn.size() >= 10)
	var kinds: Array = []
	for p: Dictionary in furn:
		kinds.append(String(p.get("kind", "")))
	_check("house has bed", kinds.has("bed"))
	_check("house has toilet", kinds.has("toilet"))
	# Player-placed furniture joins the set.
	var before: int = furn.size()
	var placed: Dictionary = intr.place_furniture(b, "chair", 700, 700, "Throne-ish")
	_check("place ok", not placed.is_empty())
	_check("place counted", intr.furniture_of(b).size() == before + 1)
	_check("bad kind rejected", intr.place_furniture(b, "nope", 1, 1).is_empty())
	gs.queue_free()


func _test_interior_arrange() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var intr: SimInteriors = w["interiors"]
	var b: Dictionary = _house(w)
	_check("move plan piece", intr.move_furniture(b, "bed", 500, 500) == true)
	var found: bool = false
	for p: Dictionary in intr.furniture_of(b):
		if String(p.get("id", "")) == "bed":
			found = absf(float(p.get("x", 0.0)) - 500.0) < 1.0
	_check("move applied", found)
	_check("move unknown fails", intr.move_furniture(b, "zzz", 1, 1) == false)
	# Clamped to the room.
	_check("move clamps", intr.move_furniture(b, "bed", 99999, 99999) == true)
	for p: Dictionary in intr.furniture_of(b):
		if String(p.get("id", "")) == "bed":
			_check("clamped x", float(p.get("x", 0.0)) <= SimInteriors.ROOM_W)
	gs.queue_free()


func _test_interior_find_need() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var intr: SimInteriors = w["interiors"]
	var b: Dictionary = _house(w)
	var bed: Dictionary = intr.find_for_need(b, "sleep")
	_check("find sleep", not bed.is_empty())
	_check("unknown need empty", intr.find_for_need(b, "teleport").is_empty())
	gs.queue_free()


func _test_art_keys() -> void:
	# Jeremy 2026-10-07: keys must resolve to REAL files — plural faction
	# suffixes and missing suffixes used to silently fall back to
	# colored rectangles in the dollhouse.
	_check("bed art key", SimInteriors.art_key_for_kind("bed", "humans") == "furn_bed_human")
	_check("table art key", SimInteriors.art_key_for_kind("table") == "furn_table_human")
	_check("bunk elf", SimInteriors.art_key_for_kind("bunk", "elves") == "furn_bunk_elf")
	_check("chair ogre", SimInteriors.art_key_for_kind("chair", "ogres") == "furn_chair_ogre")
	_check("couch gnome", SimInteriors.art_key_for_kind("couch", "gnomes") == "furn_sofa_gnome")
	_check("toilet human", SimInteriors.art_key_for_kind("toilet", "humans") == "furn_toilet_human")
	_check("divider elf", SimInteriors.art_key_for_kind("divider", "elves") == "furn_divider_elf")
	_check("undead defaults gnome", SimInteriors.art_key_for_kind("bed", "undead") == "furn_bed_gnome")
	_check("lamp_table no suffix", SimInteriors.art_key_for_kind("lamp_table") == "furn_lamp_table")
	_check("door has art", SimInteriors.art_key_for_kind("door") == "furn_door")
	_check("window has art", SimInteriors.art_key_for_kind("window") == "furn_window")
	_check("tv has art", SimInteriors.art_key_for_kind("tv") == "furn_tv")
	_check("unknown kind empty", SimInteriors.art_key_for_kind("flux_capacitor") == "")
	# Every faction-variant kind must resolve to an existing file for all
	# five factions (undead -> gnome fallback).
	var facs: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]
	for kind: String in SimInteriors.FACTION_ART_KINDS:
		for f: String in facs:
			var key: String = SimInteriors.art_key_for_kind(kind, f)
			var path: String = "res://assets/art/furniture/" + key + ".png"
			_check("art file %s/%s" % [kind, f], ResourceLoader.exists(path))
	# Non-faction keys with art must also exist on disk.
	for kind: String in ["stool", "fridge", "sink", "shower", "tub", "bath",
			"rug", "rug_round", "rug_entry", "plant", "plant_tall",
			"bookshelf", "desk", "board", "painting", "chandelier", "forge",
			"rack", "bar", "jail_bars", "jail_door", "door", "window", "tv",
			"lamp_table"]:
		var key: String = SimInteriors.art_key_for_kind(kind)
		var path: String = "res://assets/art/furniture/" + key + ".png"
		_check("art file " + kind, ResourceLoader.exists(path))
	# The "fire" key lives in the fx dir — furniture_texture falls back there.
	_check("fire key", SimInteriors.art_key_for_kind("fire") == "fire_lg_0")
	_check("fire art loads", Art.furniture_texture("fire_lg_0") != null)
	_check("door art loads", Art.furniture_texture("furn_door") != null)
	_check("window art loads", Art.furniture_texture("furn_window") != null)
	_check("tv art loads", Art.furniture_texture("furn_tv") != null)


## --- phone ---

func _gov_unit(w: Dictionary, role: String) -> Dictionary:
	var u: Dictionary = _spawn(w, "humans", "worker")
	(u["mind"] as Dictionary)["gov_role"] = role
	return u


func _test_gov_contacts_pinned() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	_gov_unit(w, "guild_master")
	_gov_unit(w, "adviser")
	_gov_unit(w, "watch_captain")
	var gov: Array = phone.government_contacts()
	_check("3 gov contacts", gov.size() == 3)
	_check("adviser first", String(gov[0].get("sub", "")).begins_with("Adviser"))
	_check("gov flagged", bool(gov[0].get("gov", false)) == true)
	_check("pfp set", String(gov[0].get("pfp", "")).begins_with("portrait_"))
	# Other factions' role-holders are NOT in the player's government.
	var ou: Dictionary = _spawn(w, "ogres", "worker")
	(ou["mind"] as Dictionary)["gov_role"] = "mayor"
	_check("foreign excluded", phone.government_contacts().size() == 3)
	gs.queue_free()


func _test_enemy_commander_groups() -> void:
	# Jeremy 2026-10-04: Messenger shows enemy commanders, grouped by
	# faction, nearest faction first.
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	# Towns give the factions positions: humans at origin, ogres 320px
	# away (10 tiles), elves 3200px away (100 tiles).
	gs.found_town("humans", "Hometown", Vector2(0, 0))
	gs.found_town("ogres", "Ogreville", Vector2(320, 0))
	gs.found_town("elves", "Elfholm", Vector2(3200, 0))
	var oc: Dictionary = _spawn(w, "ogres", "worker")
	(oc["mind"] as Dictionary)["gov_role"] = "commander"
	var om: Dictionary = _spawn(w, "ogres", "worker")
	(om["mind"] as Dictionary)["gov_role"] = "mayor"
	var em: Dictionary = _spawn(w, "elves", "worker")
	(em["mind"] as Dictionary)["gov_role"] = "mayor"
	# Own faction's role-holder must NOT appear here.
	var hc: Dictionary = _spawn(w, "humans", "worker")
	(hc["mind"] as Dictionary)["gov_role"] = "commander"
	# Non-role-holder foreigners must NOT appear either.
	_spawn(w, "undead", "worker")
	var groups: Array = phone.enemy_commander_groups()
	_check("2 enemy groups", groups.size() == 2)
	_check("ogres first (nearest)", String(groups[0].get("faction", "")) == "ogres")
	_check("elves second", String(groups[1].get("faction", "")) == "elves")
	_check("ogres dist 10 tiles", int(groups[0].get("dist_tiles", -1)) == 10)
	_check("elves dist 100 tiles", int(groups[1].get("dist_tiles", -1)) == 100)
	_check("ogres name", String(groups[0].get("faction_name", "")) == "Ogres")
	_check("ogres color set", (groups[0].get("color", Color.WHITE) as Color).is_equal_approx(Color(0.5, 0.7, 0.3)))
	var ocontacts: Array = groups[0].get("contacts", [])
	_check("ogres 2 commanders", ocontacts.size() == 2)
	_check("commander ranked first", String(ocontacts[0].get("sub", "")).begins_with("Commander"))
	_check("no own-faction leak", phone.government_contacts().size() == 1)
	var econtacts: Array = groups[1].get("contacts", [])
	_check("elves 1 commander", econtacts.size() == 1)
	_check("contact key shape", String(econtacts[0].get("key", "")).begins_with("u"))
	gs.queue_free()


func _test_contacts_player_added_only() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u1: Dictionary = _spawn(w, "humans", "worker")
	var u2: Dictionary = _spawn(w, "humans", "farmer")
	_check("starts empty", phone.my_contacts().is_empty())
	_check("add ok", phone.add_contact(int(u1["id"])) == true)
	_check("add dup fails", phone.add_contact(int(u1["id"])) == false)
	_check("one contact", phone.my_contacts().size() == 1)
	_check("u2 not auto-added", not phone.is_contact(int(u2["id"])))
	_check("remove ok", phone.remove_contact(int(u1["id"])) == true)
	_check("empty again", phone.my_contacts().is_empty())
	gs.queue_free()


func _test_messenger_reply_offline() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u: Dictionary = _spawn(w, "humans", "worker")
	# Jeremy 2026-10-04: realistic texting — replies arrive async after
	# a typing delay. Fast-forward game_time and tick to deliver.
	phone.send_message(int(u["id"]), "hello there")
	gs.game_time += 10.0
	phone.tick(0.0)
	var th: Dictionary = phone._thread("u%d" % int(u["id"]))
	_check("two messages", (th["messages"] as Array).size() == 2)
	var reply: String = String((th["messages"] as Array)[1].get("text", ""))
	_check("reply non-empty", reply != "")
	_check("reply offline (no http)", not reply.to_lower().contains("http"))
	_check("unread set", int(th["unread"]) == 1)
	phone.read_thread(int(u["id"]))
	_check("read clears", int(phone._thread("u%d" % int(u["id"]))["unread"]) == 0)
	# Unknown unit: no crash, empty reply.
	_check("unknown unit safe", phone.send_message(99999, "hi") == "")
	gs.queue_free()


func _test_messenger_sort() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u1: Dictionary = _spawn(w, "humans", "worker")
	var u2: Dictionary = _spawn(w, "humans", "farmer")
	_check("bad sort rejected", phone.set_sort("bogus") == false)
	_check("sort set", phone.set_sort("most_used") == true)
	phone.send_message(int(u1["id"]), "hi")
	phone.send_message(int(u1["id"]), "hi again")
	phone.send_message(int(u2["id"]), "yo")
	var arr: Array = phone.sorted_threads()
	_check("most_used first", String(arr[0].get("key", "")) == "u%d" % int(u1["id"]))
	_check("sort remembered", String(phone.state.get("sort", "")) == "most_used")
	_check("unread_first mode", phone.set_sort("unread_first") == true)
	gs.queue_free()


func _test_messenger_sort_switcher() -> void:
	# Jeremy 2026-09-28 (phone rule): Messenger has a REMEMBERED sort
	# switcher (latest / most-used / unread-first). UI side of the sim's
	# SimPhone.SORTS / sorted_threads().
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var u1: Dictionary = _spawn(w, "humans", "worker")
	var u2: Dictionary = _spawn(w, "humans", "farmer")
	phone.add_contact(int(u1["id"]))
	phone.add_contact(int(u2["id"]))
	# u1: heavily used thread; u2: unread incoming.
	phone.send_message(int(u1["id"]), "hi")
	phone.send_message(int(u1["id"]), "hi again")
	phone.send_message(int(u1["id"]), "third")
	var th2: Dictionary = phone._thread("u%d" % int(u2["id"]))
	th2["unread"] = 3
	th2["last_ts"] = 999.0
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	ui.open_app("messenger")
	_check("messenger screen", ui.current_screen() == "messenger")
	# The switcher: an HBox with 3 toggle buttons under the header.
	var found: HBoxContainer = null
	for ch: Node in ui._root.get_children():
		if ch is HBoxContainer:
			var btns := 0
			for gch: Node in ch.get_children():
				if gch is Button:
					btns += 1
			if btns == 3:
				found = ch
	_check("sort switcher present", found != null)
	if found != null:
		var labels: Array = []
		for gch: Node in found.get_children():
			labels.append(String((gch as Button).text))
		_check("switcher labels", labels == ["Latest", "Most used", "Unread first"])
	# Ordering: unread_first puts u2 (unread=3) on top.
	ui._msg_sort = "unread_first"
	var mine: Array = phone.my_contacts()
	var sorted: Array = ui._sort_messenger_contacts(mine)
	_check("unread_first sorts", sorted.size() == 2
		and String(sorted[0].get("key", "")) == "u%d" % int(u2["id"]))
	# most_used puts u1 (uses=3) on top.
	ui._msg_sort = "most_used"
	sorted = ui._sort_messenger_contacts(mine)
	_check("most_used sorts", sorted.size() == 2
		and String(sorted[0].get("key", "")) == "u%d" % int(u1["id"]))
	# Switching persists + syncs the sim.
	ui._set_msg_sort("unread_first")
	_check("sort remembered in ui", ui._msg_sort == "unread_first")
	_check("sort synced to sim", String(phone.state.get("sort", "")) == "unread_first")
	ui._save_msg_sort()
	ui._msg_sort = "latest"
	ui._load_msg_sort()
	_check("sort persists across loads", ui._msg_sort == "unread_first")
	# Restore the dev-machine default so the test leaves no residue.
	ui._msg_sort = "latest"
	ui._save_msg_sort()
	gs.queue_free()


func _test_messenger_latest_sort() -> void:
	# Jeremy 2026-10-06: Messenger defaults to latest-activity-first —
	# whoever messaged most recently on top, like iMessage. A new message
	# moves its thread to the top.
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var u1: Dictionary = _spawn(w, "humans", "worker")
	var u2: Dictionary = _spawn(w, "humans", "farmer")
	var u3: Dictionary = _spawn(w, "humans", "miner")
	phone.add_contact(int(u1["id"]))
	phone.add_contact(int(u2["id"]))
	phone.add_contact(int(u3["id"]))
	var k1 := "u%d" % int(u1["id"])
	var k2 := "u%d" % int(u2["id"])
	var k3 := "u%d" % int(u3["id"])
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	ui._msg_sort = "latest"
	# Messages out of order: u1, then u3, then u2 (u2 most recent).
	# (Bump last_ts manually — game_time doesn't advance in tests.)
	phone.send_message(int(u1["id"]), "first")
	phone._thread(k1)["last_ts"] = 100.0
	phone.send_message(int(u3["id"]), "second")
	phone._thread(k3)["last_ts"] = 200.0
	phone.send_message(int(u2["id"]), "third")
	phone._thread(k2)["last_ts"] = 300.0
	var sorted: Array = ui._sort_messenger_contacts(phone.my_contacts())
	_check("latest: 3 threads", sorted.size() == 3)
	_check("latest: most recent on top",
		String(sorted[0].get("key", "")) == k2)
	_check("latest: chronological",
		String(sorted[1].get("key", "")) == k3
		and String(sorted[2].get("key", "")) == k1)
	# New message to u1 jumps it to the top.
	phone.send_message(int(u1["id"]), "fourth")
	phone._thread(k1)["last_ts"] = 400.0
	sorted = ui._sort_messenger_contacts(phone.my_contacts())
	_check("latest: new message moves thread to top",
		String(sorted[0].get("key", "")) == k1)
	# Default sort is latest.
	_check("default sort is latest", ui._msg_sort == "latest")
	ui.queue_free()
	gs.queue_free()


func _test_bio_memories_only() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var mem := SimMemories.new(gs)
	var u: Dictionary = _spawn(w, "humans", "worker")
	_check("no memories -> no bio", phone.bio_for(u) == "")
	mem.remember(u, "hurt_by", 7, "Grunt", "ogres", 1.0)
	mem.remember(u, "friend_died", 8, "Pip", "humans", 1.0)
	var bio: String = phone.bio_for(u)
	_check("bio mentions attack", bio.contains("attack"))
	_check("bio mentions buried", bio.contains("buried"))
	_check("bio invents nothing", not bio.contains("dragon") and not bio.contains("king"))
	gs.queue_free()


func _test_ruler_name_verbatim_phone() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	gs.set_ruler_name("ass")
	var u: Dictionary = _spawn(w, "humans", "worker")
	# News replies embed {ruler}; the raw name must survive verbatim.
	# Jeremy 2026-10-04: async texting — fast-forward to deliver reply.
	phone.send_message(int(u["id"]), "any news?")
	gs.game_time += 10.0
	phone.tick(0.0)
	var th: Dictionary = phone._thread("u%d" % int(u["id"]))
	var texts: String = ""
	for m: Dictionary in th["messages"]:
		texts += String(m.get("text", "")) + " "
	_check("reply non-empty", texts.strip_edges() != "")
	_check("no placeholder left", not texts.contains("{ruler}"))
	gs.queue_free()


func _test_squabble() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u1: Dictionary = _spawn(w, "humans", "worker")
	var u2: Dictionary = _spawn(w, "elves", "mage")
	var p1: Dictionary = phone.npc_post(u1, "The stew SLAPS today.", "mood")
	var p2: Dictionary = phone.npc_post(u2, "Elves did nothing wrong.", "roast")
	_check("post ids grow", int(p2["id"]) > int(p1["id"]))
	_check("like works", phone.like_post(int(p1["id"])) == true)
	_check("like counted", int(phone._find_post(int(p1["id"]))["likes"]) == 1)
	_check("bad like fails", phone.like_post(424242) == false)
	_check("resquabble", phone.resquabble(int(p1["id"])) == true)
	var reply: String = phone.comment_post(int(p1["id"]), "Agreed!")
	_check("comment reply offline", reply != "" and not reply.to_lower().contains("http"))
	_check("comment stored", (phone._find_post(int(p1["id"]))["comments"] as Array).size() == 2)
	var feed: Array = phone.feed()
	_check("feed newest first", int(feed[0]["id"]) == int(p2["id"]))
	_check("posts_by filters", phone.posts_by(int(u1["id"])).size() == 1)
	_check("ruler post", not phone.ruler_post("Hear ye!").is_empty())
	gs.queue_free()


## --- court & gazette ---

func _test_gazette_real_events() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	_check("starts empty", court.news_feed().is_empty())
	var s: Dictionary = court.publish_story(
		"Giant Ass Rampages Through Turnip Fields",
		"A giant ass destroyed 3 turnip carts before leaving. Nobody was hurt, spiritually.",
		"disaster")
	_check("story stored", court.news_feed().size() == 1)
	_check("section set", String(s.get("section", "")) != "")
	_check("reporter set", String(s.get("reporter", "")) != "")
	_check("issue line", court.issue_line().begins_with("Vol."))
	gs.queue_free()


func _test_petition_decision() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var court: SimRoyalCourt = w["court"]
	var phone: SimPhone = w["phone"]
	var envoy: Dictionary = _spawn(w, "ogres", "worker")
	(envoy["mind"] as Dictionary)["gov_role"] = "envoy"
	var p: Dictionary = court.petition(envoy, "trade",
		"The ogres offer 40 gold for open markets.",
		["Accept the deal", "Refuse politely"])
	_check("petition open", court.open_petitions().size() == 1)
	var gold_before: float = gs.resources.get_amount("humans", "gold")
	var story: Dictionary = court.decide(int(p["id"]), 0)
	_check("resolved", court.open_petitions().is_empty())
	_check("story printed", not story.is_empty())
	_check("gazette has it", court.news_feed().size() == 1)
	_check("gold moved", gs.resources.get_amount("humans", "gold") > gold_before)
	_check("relations up", court.relation_of("ogres") > 0)
	# Bad inputs are safe.
	_check("bad id safe", court.decide(99999, 0).is_empty())
	_check("bad option safe", court.decide(int(p["id"]), 9).is_empty())
	_check("re-decide safe", court.decide(int(p["id"]), 0).is_empty())
	gs.queue_free()


## --- UI smoke (headless construction) ---

func _test_phone_ui_screens() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	_check("ui setup", ui.is_setup())
	ui.open_app("messenger")
	_check("messenger screen", ui.current_screen() == "messenger")
	ui.open_app("squabble")
	_check("squabble screen", ui.current_screen() == "squabble")
	ui.open_app("gazette")
	_check("gazette screen", ui.current_screen() == "gazette")
	var u: Dictionary = _spawn(w, "humans", "worker")
	phone.send_message(int(u["id"]), "hi")
	ui.open_thread("u%d" % int(u["id"]))
	_check("thread screen", ui.current_screen() == "thread")
	ui.open_profile("u%d" % int(u["id"]))
	_check("profile screen", ui.current_screen() == "profile")
	ui.go_home()
	_check("home screen", ui.current_screen() == "home")
	# Jeremy 2026-10-03: wallpaper customization screen.
	ui.open_app("wallpaper")
	_check("wallpaper screen", ui.current_screen() == "wallpaper")
	ui.go_home()
	_check("home after wallpaper", ui.current_screen() == "home")
	ui.queue_free()
	gs.queue_free()


func _test_interior_view_open_close() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var intr: SimInteriors = w["interiors"]
	var view := InteriorView.new()
	root.add_child(view)
	var b: Dictionary = _house(w)
	var u: Dictionary = _spawn(w, "humans", "worker")
	intr.enter(b, u)
	_check("view opens", view.open(b, intr, gs) == true)
	_check("view is open", view.is_open() == true)
	_check("building id", view.building_id() == int(b["id"]))
	view.set_arrange(true)
	_check("arrange on", view.is_arrange() == true)
	view.refresh()
	_check("refresh ok", view.is_open() == true)
	view.close()
	_check("view closed", view.is_open() == false)
	# Blueprint won't open.
	var blue: Dictionary = _house(w, false)
	_check("blueprint no open", view.open(blue, intr, gs) == false)
	view.queue_free()
	gs.queue_free()


func _test_interior_occupant_sprites() -> void:
	# Jeremy 2026-10-07: occupants must render as real chibi unit sprites
	# with idle bounce and ground shadows — not colored dots + name labels.
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var intr: SimInteriors = w["interiors"]
	var view := InteriorView.new()
	root.add_child(view)
	var b: Dictionary = _house(w)
	var u: Dictionary = _spawn(w, "humans", "worker")
	intr.enter(b, u)
	_check("view opens (sprites)", view.open(b, intr, gs) == true)
	_check("one occupant holder", view._occupant_nodes.size() == 1)
	_check("one occupant sprite", view._occupant_sprites.size() == 1)
	var spr: Sprite2D = view._occupant_sprites[0]
	_check("occupant has unit texture", spr.texture != null)
	_check("occupant scaled to room", spr.scale.x > 0.05 and spr.scale.x < 2.0)
	var saw_dot := false
	var saw_label := false
	var saw_shadow := false
	for n: Node in view._occupant_nodes[0].get_children():
		if n is Label:
			saw_label = true
		if n is Polygon2D:
			var pc: int = (n as Polygon2D).polygon.size()
			if pc == 12:
				saw_dot = true  # the old colored-dot marker shape
			if pc == 16:
				saw_shadow = true  # the new ground shadow
	_check("no dot marker", not saw_dot)
	_check("no floating name label", not saw_label)
	_check("ground shadow present", saw_shadow)
	view._process(0.5)
	_check("idle bob advances", view._bob_t > 0.0)
	_check("bob offsets sprite", absf(spr.position.y + InteriorView.OCCUPANT_H * 0.5) > 0.01)
	# Refresh rebuilds occupants cleanly (no leaked sprite state).
	view.refresh()
	_check("refresh keeps one sprite", view._occupant_sprites.size() == 1)
	view.close()
	_check("close clears occupant state", view._occupant_sprites.is_empty())
	view.queue_free()
	gs.queue_free()

func _test_home_icon_wiggle() -> void:
	# Jeremy 2026-10-03: iOS-style movable home icons — long-press wiggles,
	# drag reorders with snap, layout persists.
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	var grid = ui._home_grid
	_check("home grid built", grid != null)
	# Jeremy 2026-10-06 (polish round 2): Settings app added (blocked
	# list) — 10 tiles then. Jeremy 2026-10-06 (launch readiness): Army
	# app added — 11 tiles. Jeremy 2026-10-06 (hearsay/chat focus): Rumors
	# app added — 12 tiles now, append-last convention kept.
	_check("12 app tiles", grid._tiles.size() == 12)
	_check("canonical order", grid._order[0] == "messenger" and grid._order[6] == "wallpaper")
	_check("keyboard app present", "keyboard" in grid._order)
	# Long-press enters wiggle mode.
	var t0 = grid._tiles[0]
	grid._tile_pressed(t0, Vector2.ZERO)
	grid._process(0.6)
	_check("long-press wiggles", grid.is_wiggling())
	_check("done button shows", ui._home_done_btn.visible)
	# Drag first icon to cell 3 (row 1, col 0).
	grid._begin_drag(t0)
	# Jeremy 2026-10-05: row height grew (238px) — drag into row 1 band.
	grid._drag_to(Vector2(20, 260))
	grid._finish_drag()
	_check("drag reorders", grid._order[3] == "messenger")
	_check("order saved", ui._home_order[3] == "messenger")
	# Layout persists across rebuilds.
	var ui2 := PhoneUI.new()
	root.add_child(ui2)
	ui2.setup(gs, phone, court)
	_check("order persisted", ui2._home_order[3] == "messenger")
	_check("rebuilt grid order", ui2._home_grid._order[3] == "messenger")
	# Restore canonical order so the dev cfg isn't polluted.
	ui2._home_order = ["messenger", "squabble", "gazette", "policies", "diplomacy", "calendar", "wallpaper", "keyboard", "weather"]
	ui2._save_home_order()
	# Tap in wiggle mode exits wiggle and opens the app.
	var grid2 = ui2._home_grid
	grid2.set_wiggle(true)
	var t1 = null
	for t in grid2._tiles:
		if t.app_id == "squabble":
			t1 = t
	grid2._tile_pressed(t1, Vector2.ZERO)
	grid2._process(0.1)
	grid2._release_anywhere()
	_check("tap exits wiggle", not grid2.is_wiggling())
	_check("tap opens app", ui2.current_screen() == "squabble")
	ui.queue_free()
	ui2.queue_free()



## Jeremy 2026-10-03: status-bar X is a back button inside apps — it goes
## back to home (or the parent app for sub-screens) and only closes the
## whole phone when already on the home screen.
func _test_phone_status_x_back() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	# Back-target mapping.
	_check("back target home", ui._back_target_for("home") == "")
	_check("back target thread", ui._back_target_for("thread") == "messenger")
	_check("back target profile", ui._back_target_for("profile") == "squabble")
	_check("back target diplomacy", ui._back_target_for("diplomacy") == "home")
	_check("back target wallpaper", ui._back_target_for("wallpaper") == "home")
	# Jeremy 2026-10-03: NO X anywhere. Back arrow hidden on home.
	_check("home screen", ui.current_screen() == "home")
	_check("no back button on home", ui._close_btn.visible == false)
	ui._on_status_back()
	_check("back on home does nothing", ui.visible == true)
	_check("still on home", ui.current_screen() == "home")
	# Back arrow inside an app goes back to home, phone stays open.
	ui.open_app("diplomacy")
	_check("diplomacy screen", ui.current_screen() == "diplomacy")
	_check("back arrow visible in app", ui._close_btn.visible == true)
	# Jeremy 2026-10-04 (polish): drawn chevron, not the "←" text glyph.
	_check("back glyph is drawn chevron (no arrow text)",
		ui._close_btn.text == "" or not ui._close_btn.text.contains("←"))
	_check("back button has chevron child", _button_has_chevron(ui._close_btn))
	ui._on_status_back()
	_check("back in app goes home", ui.current_screen() == "home")
	_check("phone still open", ui.visible == true)
	_check("back hidden on home again", ui._close_btn.visible == false)
	# Back in a sub-screen goes to the parent app.
	var u: Dictionary = _spawn(w, "humans", "worker")
	phone.send_message(int(u["id"]), "hi")
	ui.open_thread("u%d" % int(u["id"]))
	_check("thread screen", ui.current_screen() == "thread")
	ui._on_status_back()
	_check("back in thread goes to messenger", ui.current_screen() == "messenger")
	_check("phone still open after thread", ui.visible == true)
	ui.open_profile("u%d" % int(u["id"]))
	_check("profile screen", ui.current_screen() == "profile")
	ui._on_status_back()
	_check("back in profile goes to squabble", ui.current_screen() == "squabble")
	_check("phone still open after profile", ui.visible == true)
	ui.queue_free()
	gs.queue_free()


## Jeremy 2026-10-03: diplomacy buttons must be BIG (110px tall, full-width,
## stacked vertically) so you don't accidentally declare war.
func _test_diplo_big_buttons() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var diplo := SimDiplomacy.new(gs)
	diplo.reset(["humans", "ogres", "elves", "gnomes", "undead"])
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court, diplo)
	ui.open_app("diplomacy")
	# Find a diplomacy card and check its action buttons.
	var card := ui._diplo_card("ogres")
	_check("card created", card != null)
	# The actions container is the last child (VBoxContainer).
	var box: VBoxContainer = card.get_child(0)
	var actions: VBoxContainer = box.get_child(box.get_child_count() - 1)
	_check("actions is VBox", actions is VBoxContainer)
	# All buttons must be 110px tall (fat-finger friendly).
	for child: Node in actions.get_children():
		if child is Button:
			var b := child as Button
			_check("button '%s' is 110px tall" % b.text,
				b.custom_minimum_size.y >= 110.0)
			_check("button '%s' expands full width" % b.text,
				b.size_flags_horizontal == Control.SIZE_EXPAND_FILL)
	# Verify we have the expected buttons for neutral state.
	var texts: Array = []
	for child: Node in actions.get_children():
		if child is Button:
			texts.append((child as Button).text)
	_check("has Declare War", "Declare War" in texts)
	_check("has Propose Alliance", "Propose Alliance" in texts)
	_check("has Trade Deal", "Trade Deal" in texts)
	_check("has Demand Tribute", "Demand Tribute" in texts)
	ui.queue_free()
	gs.queue_free()


## Jeremy 2026-10-03: Declare War needs a confirmation dialog.
## Cancel = no war. Confirm = war declared.
func _test_diplo_war_confirm() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var diplo := SimDiplomacy.new(gs)
	diplo.reset(["humans", "ogres", "elves", "gnomes", "undead"])
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court, diplo)
	ui.open_app("diplomacy")
	# Get the card and find the Declare War button.
	var card := ui._diplo_card("ogres")
	var box: VBoxContainer = card.get_child(0)
	var actions: VBoxContainer = box.get_child(box.get_child_count() - 1)
	var war_btn: Button = null
	for child: Node in actions.get_children():
		if child is Button and (child as Button).text == "Declare War":
			war_btn = child as Button
	_check("found Declare War button", war_btn != null)
	# Press it — should show confirmation, NOT declare war immediately.
	war_btn.pressed.emit()
	# Find the confirmation overlay (child of ui, not the card).
	var overlay: PanelContainer = null
	for child: Node in ui.get_children():
		if child is PanelContainer and child != ui._screen_host:
			# Check if it contains our confirm dialog.
			var center := child.get_child(0) as CenterContainer
			if center != null:
				overlay = child as PanelContainer
				break
	_check("confirmation dialog appears", overlay != null)
	# Verify war was NOT declared yet.
	var pf: String = gs.player_faction
	var dip = ui._diplo
	_check("no war before confirm",
		String(dip.relation_state(pf, "ogres")) != "war")
	# Find Cancel and press it — dialog closes, still no war.
	var dlg: PanelContainer = (overlay.get_child(0) as CenterContainer).get_child(0)
	# Menu-scroll audit (2026-10-10): the confirm dialog's vbox is wrapped in
	# a ScrollContainer by _cap_modal_scroll — look through it to the buttons.
	var scroll: ScrollContainer = dlg.get_child(0)
	var vbox: VBoxContainer = scroll.get_child(0)
	var cancel_btn: Button = null
	var yes_btn: Button = null
	for child: Node in vbox.get_children():
		if child is Button:
			if (child as Button).text == "Cancel":
				cancel_btn = child as Button
			elif "declare war" in (child as Button).text.to_lower():
				yes_btn = child as Button
	_check("found Cancel button", cancel_btn != null)
	_check("found confirm button", yes_btn != null)
	cancel_btn.pressed.emit()
	_check("dialog closed after cancel", overlay.is_queued_for_deletion())
	_check("still no war after cancel",
		String(dip.relation_state(pf, "ogres")) != "war")
	# Press Declare War again, this time confirm.
	war_btn.pressed.emit()
	var overlay2: PanelContainer = null
	for child: Node in ui.get_children():
		if child is PanelContainer:
			var c := child.get_child(0) as CenterContainer
			if c != null:
				overlay2 = child as PanelContainer
				break
	_check("confirmation appears again", overlay2 != null)
	var dlg2: PanelContainer = (overlay2.get_child(0) as CenterContainer).get_child(0)
	var scroll2: ScrollContainer = dlg2.get_child(0)
	var vbox2: VBoxContainer = scroll2.get_child(0)
	for child: Node in vbox2.get_children():
		if child is Button and "declare war" in (child as Button).text.to_lower():
			(child as Button).pressed.emit()
			break
	_check("dialog closed after confirm", overlay2.is_queued_for_deletion())
	_check("war declared after confirm",
		String(dip.relation_state(pf, "ogres")) == "war")
	ui.queue_free()
	gs.queue_free()


## The real game wires seasons/disasters via world.gd; the bare test
## harness only calls gs.setup(). Wire them here for forecast tests.
func _wire_world_systems(gs: GameState) -> void:
	if gs.seasons == null:
		gs.seasons = SimSeasons.new(gs)
		gs.seasons.reset()
	if gs.disasters == null:
		gs.disasters = DisasterSim.new(gs, SimCombat.new(gs))


## Jeremy 2026-10-03: the Calendar app is now the Forecast app — month
## grid plus a 7-day weather outlook, upcoming disasters, and scheduled
## festivals. Label renamed; app id stays "calendar" for save compat.
func _test_forecast_app() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	_wire_world_systems(gs)
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	var label := ""
	for a in PhoneUI.HOME_APPS:
		if String(a[0]) == "calendar":
			label = String(a[1])
	_check("calendar tile renamed to Forecast", label == "Forecast")
	_check("calendar app id kept", label != "" and true)
	ui.open_app("calendar")
	_check("forecast screen", ui.current_screen() == "calendar")
	_check("forecast header", _find_label(ui._root, "Forecast") != null)
	_check("no Calendar header", _find_label(ui._root, "Calendar") == null)
	_check("7-day section", _find_label(ui._root, "7-Day Forecast") != null)
	_check("disasters section",
		_find_label(ui._root, "Upcoming Disasters") != null)
	_check("festivals section",
		_find_label(ui._root, "Upcoming Festivals") != null)
	_check("today weather row", _find_label(ui._root, "Today (") != null)
	_check("tomorrow weather row", _find_label(ui._root, "Tomorrow (") != null)
	_check("weather row has temp", _find_label(ui._root, "°") != null)
	_check("date fmt day 1", ui._fc_date_string(1) == "Bloommoon 1, Year 1")
	# Seed a future disaster: it should show; a done one should not.
	var dom: int = gs.seasons.day_of_month()
	gs.disasters.forecast[dom + 2] = {
		"type": "meteor", "label": "Meteor Strike", "done": false}
	gs.disasters.forecast[dom + 3] = {
		"type": "quake", "label": "Old Quake", "done": true}
	# Seed a scheduled festival 5 days out.
	(court.policies.state["festivals"] as Array).append({
		"id": 1, "town_id": -1, "town": "Testville",
		"day_abs": gs.day_number + 5, "gold": 10.0, "food": 5.0})
	ui.open_app("calendar")
	_check("upcoming disaster shown",
		_find_text(ui._root, "Meteor Strike") != null)
	_check("done disaster hidden", _find_text(ui._root, "Old Quake") == null)
	_check("festival shown", _find_label(ui._root, "Testville") != null)
	_check("festival countdown", _find_label(ui._root, "in 5 days") != null)
	# Jeremy's tofu rule: no emoji anywhere on the new screens.
	_check("forecast no emoji", _no_emoji(ui._root))
	ui.queue_free()
	gs.queue_free()


## Jeremy 2026-10-03: home screen weather widget — "Clear · 72°" plus
## day phase / season, text only.
func _test_home_weather_widget() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	_wire_world_systems(gs)
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	ui.go_home()
	_check("weather widget main", ui._home_weather_main != null)
	_check("weather shows temp", ui._home_weather_main.text.contains("°"))
	_check("weather shows condition", ui._home_weather_main.text.contains(
		String(gs.seasons.weather).capitalize()))
	_check("weather widget sub", ui._home_weather_sub != null)
	var sub: String = ui._home_weather_sub.text
	_check("weather sub has day/phase",
		sub.contains("Day") or sub.contains("Night"))
	_check("weather widget no emoji", _no_emoji(ui._root))
	# Jeremy 2026-10-05: the big home title block is gone — the
	# status bar already shows "Day 1 bastard OS".
	_check("home title bastard OS removed",
		_find_label(ui._root, "bastard OS") == null)
	_check("no Cursing Phone title",
		_find_label(ui._root, "Cursing Phone") == null)
	ui.queue_free()
	gs.queue_free()


## Jeremy 2026-10-03: boot splash flashes every time the phone opens
## (quick: ~0.8s hold + fast fade), but never during initial setup.
func _test_boot_splash() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	_check("no splash on setup", ui._splash_boot == null)
	# Simulate the phone opening (hud.gd sets visible = true).
	ui.visible = false
	ui.visible = true
	_check("splash shows on open",
		ui._splash_boot != null and is_instance_valid(ui._splash_boot))
	_check("splash says bastard OS",
		_find_label(ui._splash_boot, "bastard OS") != null)
	# Manual dismiss (the tween auto-dismisses in a live game).
	ui._dismiss_boot_splash()
	_check("splash dismisses", ui._splash_boot == null)
	# Re-opening flashes it again.
	ui.visible = false
	ui.visible = true
	_check("splash shows on reopen",
		ui._splash_boot != null and is_instance_valid(ui._splash_boot))
	ui._dismiss_boot_splash()
	ui.queue_free()
	gs.queue_free()


## Find a Label whose text contains `substr`, searching recursively.
func _find_label(n: Node, substr: String) -> Label:
	if n is Label and (n as Label).text.contains(substr):
		return n as Label
	for c: Node in n.get_children():
		var hit := _find_label(c, substr)
		if hit != null:
			return hit
	return null


## Jeremy 2026-10-04: disaster rows are tappable Buttons now.
func _find_text(n: Node, substr: String) -> Node:
	if n is Label and (n as Label).text.contains(substr):
		return n
	if n is Button and (n as Button).text.contains(substr):
		return n
	for c: Node in n.get_children():
		var hit := _find_text(c, substr)
		if hit != null:
			return hit
	return null


## Jeremy's tofu rule: no emoji codepoints in any label under `n`.
func _no_emoji(n: Node) -> bool:
	var texts: Array[String] = []
	if n is Label:
		texts.append((n as Label).text)
	if n is Button:
		texts.append((n as Button).text)
	for t: String in texts:
		for i in t.length():
			var cp: int = t.unicode_at(i)
			if (cp >= 0x1F000 and cp <= 0x1FAFF) \
					or (cp >= 0x2600 and cp <= 0x27BF) \
					or (cp >= 0x2B00 and cp <= 0x2BFF) \
					or cp == 0xFE0F or cp == 0x200D or cp == 0x20E3:
				return false
	for c: Node in n.get_children():
		if not _no_emoji(c):
			return false
	return true


## Jeremy 2026-10-04: phone form factor — fullscreen on iPhone, centered
## phone-shaped frame on desktop (PC 16:9 / 4:3).
func _test_phone_frame_rect() -> void:
	# Desktop 16:9 (1920x1080): phone frame centered, 92% height.
	var r169: Rect2 = PhoneUI._phone_frame_rect(Vector2(1920, 1080))
	_check("phone frame desktop 16:9 height", absf(r169.size.y - 1080.0 * 0.92) < 1.0)
	_check("phone frame desktop 16:9 centered x",
		absf(r169.position.x - (1920.0 - r169.size.x) * 0.5) < 1.0)
	_check("phone frame desktop 16:9 centered y",
		absf(r169.position.y - (1080.0 - r169.size.y) * 0.5) < 1.0)
	# Phone aspect 9:19.5.
	_check("phone frame aspect", absf(r169.size.x / r169.size.y - 9.0 / 19.5) < 0.01)
	# Desktop 4:3 (1600x1200): frame fits width constraint.
	var r43: Rect2 = PhoneUI._phone_frame_rect(Vector2(1600, 1200))
	_check("phone frame desktop 4:3 fits width", r43.size.x <= 1600.0 * 0.92 + 1.0)
	_check("phone frame desktop 4:3 centered",
		absf(r43.position.x - (1600.0 - r43.size.x) * 0.5) < 1.0)


## Jeremy 2026-10-06 (launch readiness): rotating the device with the phone
## open must refit the phone frame (stale frame rect bug), and shell
## metrics must scale with the phone frame, not the full viewport (on
## desktop the centered 9:19.5 frame is much smaller than the window, so
## viewport-sized bezels swallowed a third of the phone).
func _test_phone_rotation_refit() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	# The resize hookup is guarded for headless (no tree in -s scripts);
	# the wiring itself is exercised through _refit_phone_frame().
	_check("refit fn exists", ui.has_method("_refit_phone_frame"))
	ui.visible = true
	ui.open_app("messenger")
	_check("messenger open", ui.current_screen() == "messenger")
	# Simulate a rotation: portrait phone 390x844 -> landscape 844x390.
	ui._refit_phone_frame(Vector2(844, 390))
	var frame := PhoneUI._phone_frame_rect(Vector2(844, 390))
	_check("refit width", absf(ui._phone_w - frame.size.x) < 1.0)
	_check("refit height", absf(ui._phone_h - frame.size.y) < 1.0)
	_check("refit control size x", absf(ui.size.x - frame.size.x) < 1.0)
	_check("refit control size y", absf(ui.size.y - frame.size.y) < 1.0)
	_check("refit control pos x", absf(ui.offset_left - frame.position.x) < 1.0)
	_check("refit home", ui.current_screen() == "home")
	_check("refit shell rebuilt", ui._screen_host != null)
	# Hidden phone: refit is a no-op (the next open_app rebuilds anyway).
	ui.visible = false
	var pw: float = ui._phone_w
	ui._refit_phone_frame(Vector2(390, 844))
	_check("hidden refit no-op", ui._phone_w == pw)
	# Desktop viewport: shell metrics must track the centered phone frame,
	# not the full window (the old code overwrote with viewport size).
	ui.visible = true
	ui._refit_phone_frame(Vector2(1920, 1080))
	var f169 := PhoneUI._phone_frame_rect(Vector2(1920, 1080))
	_check("desktop refit tracks frame width",
		absf(ui._phone_w - f169.size.x) < 1.0)
	_check("desktop refit tracks frame height",
		absf(ui._phone_h - f169.size.y) < 1.0)
	_check("desktop bezel frame-scaled",
		absf(ui._shell_bezel - maxf(12.0, ui._phone_w * 0.030)) < 0.05)
	# The size_changed handler delegates to the refit (no viewport in
	# -s scripts, so it falls back to the current frame size: idempotent).
	ui.open_app("messenger")
	ui._on_phone_viewport_resized()
	_check("handler returns home", ui.current_screen() == "home")
	gs.queue_free()
	ui.queue_free()


## Jeremy 2026-10-04 (polish): drawn back chevron replaces the "←" text
## glyph (tofu risk on iPhone). No back button may use the arrow glyph.
func _button_has_chevron(b: Button) -> bool:
	for c: Node in b.get_children():
		if c is PhoneUI.ChevronIcon:
			return true
	return false

func _test_polish_chevron() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	# Status bar back button: no "←" text, has a ChevronIcon child.
	var back_btn: Button = ui._close_btn
	_check("status back button exists", back_btn != null)
	if back_btn != null:
		_check("status back has no arrow glyph", not back_btn.text.contains("←"))
		_check("status back has drawn chevron", _button_has_chevron(back_btn))
	# App header back button: same treatment.
	ui.open_app("messenger")
	var hdr_back := _find_chevron_button(ui)
	_check("header back uses drawn chevron (no arrow glyph)", hdr_back)
	_check("no arrow glyph anywhere in phone chrome", not _has_arrow_glyph(ui))
	ui.queue_free()
	gs.queue_free()

func _find_chevron_button(n: Node) -> bool:
	# Returns true if we find at least one Button whose text lacks "←"
	# but which has a drawn-chevron child — i.e. the new pattern is used.
	if n is Button:
		var b := n as Button
		if not b.text.contains("←") and _button_has_chevron(b):
			return true
	for c: Node in n.get_children():
		if _find_chevron_button(c):
			return true
	return false

func _has_arrow_glyph(n: Node) -> bool:
	if n is Label and (n as Label).text.contains("←"):
		return true
	if n is Button and (n as Button).text.contains("←"):
		return true
	for c: Node in n.get_children():
		if _has_arrow_glyph(c):
			return true
	return false


## Jeremy 2026-10-04 (polish): notification banners queue and dismiss.
func _test_polish_notifications() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	ui.show_notification("Tansy", "Hello there", "messenger")
	_check("notification banner appears",
		ui._notif_current != null and is_instance_valid(ui._notif_current))
	_check("notification shows title",
		_find_label(ui._notif_current, "Tansy") != null)
	_check("notification shows body",
		_find_label(ui._notif_current, "Hello there") != null)
	# Queue a second one — it waits.
	ui.show_notification("Squabble", "New post", "squabble")
	_check("second notification queues", ui._notif_queue.size() == 1)
	# Dismiss first → second shows.
	ui._dismiss_notification()
	_check("queued notification shows after dismiss",
		ui._notif_current != null and is_instance_valid(ui._notif_current))
	_check("queue drains", ui._notif_queue.is_empty())
	ui._dismiss_notification()
	_check("all notifications dismissed", ui._notif_current == null)
	ui.queue_free()
	gs.queue_free()


## Jeremy 2026-10-04 (polish): conversation rows show a timestamp.
func _test_polish_timestamps() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	# Thread item with a timestamp renders the "Day N" label.
	var item := ui._thread_item("Tansy", "hello", 0,
		func() -> void: pass, {}, "Day 5")
	_check("thread item renders timestamp",
		_find_label(item, "Day 5") != null)
	# Without a timestamp, no Day label is added.
	var item2 := ui._thread_item("Tansy", "hello", 0,
		func() -> void: pass, {}, "")
	_check("thread item omits empty timestamp",
		_find_label(item2, "Day") == null)
	item.queue_free()
	item2.queue_free()
	ui.queue_free()
	gs.queue_free()
## Jeremy 2026-10-05: contact rows open a chat only on a clean tap
## (press + release within 14px). A drag must scroll, not open a chat.
func _test_thread_item_tap_vs_drag() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	var opened: Array = [0]
	var item := ui._thread_item("Tansy", "hello", 0,
		func() -> void: opened[0] = int(opened[0]) + 1, {}, "")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(50, 50)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	# Clean tap: release ~2px from press.
	release.position = Vector2(52, 51)
	item.gui_input.emit(press)
	item.gui_input.emit(release)
	_check("clean tap opens chat", int(opened[0]) == 1)
	# Drag: release 110px away — must not open.
	release.position = Vector2(50, 160)
	item.gui_input.emit(press)
	item.gui_input.emit(release)
	_check("drag does not open chat", int(opened[0]) == 1)
	# Press with no release — nothing opens.
	item.gui_input.emit(press)
	_check("press alone does not open chat", int(opened[0]) == 1)
	item.queue_free()
	ui.queue_free()
	gs.queue_free()


## Jeremy 2026-10-06: scrolling the contacts list must not open chats.
## The card tracks the finger 1:1 during a scroll, so card-relative
## press/release distance is ~0 even for long scrolls — the tap handler
## must suppress the tap when the enclosing ScrollContainer moved.
func _test_thread_item_scroll_suppresses_tap() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(300, 300)
	ui.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	var opened: Array = [0]
	var item := ui._thread_item("Tansy", "hello", 0,
		func() -> void: opened[0] = int(opened[0]) + 1, {}, "")
	box.add_child(item)
	# Widen the scrollbar range directly (no layout frames needed headless).
	sc.get_v_scroll_bar().max_value = 1000.0
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(50, 50)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(50, 50)  # card tracks finger: ~0 relative move
	# Case 1: list scrolled between press and release -> no tap.
	item.gui_input.emit(press)
	sc.scroll_vertical = 120.0
	item.gui_input.emit(release)
	_check("scroll suppresses tap", int(opened[0]) == 0)
	# Case 2: no scroll, clean tap -> opens.
	sc.scroll_vertical = 120.0  # hold steady this time
	item.gui_input.emit(press)
	item.gui_input.emit(release)
	_check("steady tap still opens", int(opened[0]) == 1)
	# Case 3: item outside any ScrollContainer keeps the 14px rule.
	var lone_opened: Array = [0]
	var lone := ui._thread_item("Solo", "hi", 0,
		func() -> void: lone_opened[0] = int(lone_opened[0]) + 1, {}, "")
	ui.add_child(lone)
	lone.gui_input.emit(press)
	release.position = Vector2(52, 51)
	lone.gui_input.emit(release)
	_check("lone item tap opens", int(lone_opened[0]) == 1)
	ui.queue_free()
	gs.queue_free()


## Jeremy 2026-10-06: relationship meter in the thread header (HTML
## CANDIDATE54 parity) — shows how much the NPC likes/dislikes the ruler.
func _test_affinity_meter() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u: Dictionary = _spawn(w, "gnomes", "worker")
	var uid := int(u.get("id", 0))
	# Neutral baseline.
	var aff: Dictionary = phone.affinity_for(u)
	_check("aff neutral tier", String(aff.get("tier", "")) == "neutral")
	_check("aff score in range",
		float(aff.get("score", 999.0)) >= -100.0
		and float(aff.get("score", 999.0)) <= 100.0)
	_check("aff mood word present", String(aff.get("mood_word", "")) != "")
	# Fond -> warm/devoted.
	var mem: Dictionary = phone.conversation._get_memory(uid)
	mem["mood"] = 80.0
	aff = phone.affinity_for(u)
	_check("aff fond devoted", String(aff.get("tier", "")) == "devoted")
	_check("aff fond word", String(aff.get("mood_word", "")) == "Adoring")
	# Grudge -> hostile.
	mem["mood"] = -70.0
	aff = phone.affinity_for(u)
	_check("aff grudge hostile", String(aff.get("tier", "")) == "hostile")
	_check("aff grudge word", String(aff.get("mood_word", "")) == "Furious")
	# Mild dislike -> cold.
	mem["mood"] = -30.0
	aff = phone.affinity_for(u)
	_check("aff cold tier", String(aff.get("tier", "")) == "cold")
	# Blocked -> hostile regardless of mood.
	mem["mood"] = 90.0
	phone.toggle_block(uid)
	aff = phone.affinity_for(u)
	_check("aff blocked hostile", String(aff.get("tier", "")) == "hostile")
	_check("aff blocked score", float(aff.get("score", 0.0)) == -100.0)
	phone.toggle_block(uid)
	gs.queue_free()


## Jeremy 2026-10-06 (launch readiness, gate 4): phone UI fit regressions.
## A full safe-area audit found elements clipped off-screen on iPhone
## portrait (~390px): fixed-width modals, an unscrollable home screen, an
## overflowing nav bar, and header/button rows wider than the screen.
func _test_launch_readiness_ui_fits() -> void:
	var w: Dictionary = _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var court: SimRoyalCourt = w["court"]
	var ui := PhoneUI.new()
	root.add_child(ui)
	ui.setup(gs, phone, court)
	# Nav bar: three buttons share the bar width — the old fixed 120px
	# buttons + 40px separation (= 440px) clipped Back/Power off-screen.
	var bar = ui._nav_bar
	_check("lr: nav bar built", bar != null)
	if bar != null:
		_check("lr: nav bar has 3 buttons", bar.get_child_count() == 3)
		var total_min := 0.0
		for b in bar.get_children():
			_check("lr: nav btn expands", b.size_flags_horizontal == Control.SIZE_EXPAND_FILL)
			total_min += b.custom_minimum_size.x
		_check("lr: nav btns fit 330px bar (got %s)" % total_min,
			total_min + 2.0 * 16.0 <= 340.0)
	# Modal width clamps to the phone frame — the old fixed 520px dialog
	# clipped ~65px off each edge on iPhone portrait.
	ui._phone_w = 390.0
	_check("lr: modal 326 on 390 phone (got %s)" % ui._modal_width(),
		ui._modal_width() == 326.0)
	ui._phone_w = 1200.0
	_check("lr: modal 520 on wide phone (got %s)" % ui._modal_width(),
		ui._modal_width() == 520.0)
	ui._phone_w = 300.0
	_check("lr: modal floor 280 (got %s)" % ui._modal_width(),
		ui._modal_width() == 280.0)
	# Home screen scrolls — weather + 4 icon rows + pad (~1280px) used to
	# render into _root with no scroll, so Weather/Settings were clipped
	# and unreachable.
	_check("lr: home scroll exists", ui._home_scroll != null)
	if ui._home_scroll != null:
		_check("lr: home scroll is ScrollContainer",
			ui._home_scroll is ScrollContainer)
		_check("lr: grid taller than screen",
			ui._home_grid.custom_minimum_size.y > 470.0)
	# Wiggle locks the scroll so tile rearrangement never fights it.
	var grid = ui._home_grid
	grid.set_wiggle(true)
	_check("lr: wiggle disables home scroll",
		ui._home_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED)
	grid.set_wiggle(false)
	_check("lr: unwriggle restores home scroll",
		ui._home_scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO)
	gs.queue_free()
	ui.queue_free()
