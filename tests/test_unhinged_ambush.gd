extends SceneTree
## Cursing Gnomes — proactive unhinged ambush tests (Jeremy 2026-10-06).
##
## Proves: furious unhinged NPCs can PREEMPTIVELY DM the player a cuss-out
## (day-tick trigger); calm unhinged and stable furious NPCs never ambush;
## per-NPC once-per-day cooldown; global cap per day; blocked NPCs stay
## completely silent; dead NPCs excluded; replying to an ambush enters the
## reactive cuss-out + spam chain; ambush threads surface unread at the top
## under newest-message-first ordering; escalation tiers follow live mood.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_unhinged_ambush.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes unhinged-ambush tests ===")
	_test_furious_unhinged_ambushes()
	_test_calm_unhinged_silent()
	_test_stable_furious_silent()
	_test_blocked_silent()
	_test_dead_excluded()
	_test_per_npc_cooldown()
	_test_global_cap()
	_test_reply_enters_reactive_path()
	_test_thread_surfaces_on_top()
	_test_chance_table_sane()
	_test_tier_escalation()
	_test_no_repeat_across_days()
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
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var mind := SimMind.new(gs)
	var phone := SimPhone.new(gs)
	return {"gs": gs, "mind": mind, "phone": phone}


func _spawn_unhinged(w: Dictionary, mood: float) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var phone: SimPhone = w["phone"]
	var u: Dictionary = gs.spawner.spawn_unit("ogres", "gatherer", -1,
		Vector2(100, 100))
	mind.ensure(u)
	var traits: Dictionary = u["mind"]["traits"]
	traits["unhinged"] = 1.0
	traits["persona"] = "blunt"
	var uid := int(u["id"])
	phone.conversation.set_ruler_mood(uid, mood)
	return u


func _spawn_stable(w: Dictionary, mood: float) -> Dictionary:
	var gs: GameState = w["gs"]
	var mind: SimMind = w["mind"]
	var phone: SimPhone = w["phone"]
	var u: Dictionary = gs.spawner.spawn_unit("ogres", "gatherer", -1,
		Vector2(100, 100))
	mind.ensure(u)
	var traits: Dictionary = u["mind"]["traits"]
	traits["unhinged"] = 0.0
	traits["persona"] = "blunt"
	var uid := int(u["id"])
	phone.conversation.set_ruler_mood(uid, mood)
	return u


func _npc_texts(phone: SimPhone, uid: int) -> Array:
	var th: Dictionary = phone._thread(phone._key_for(uid))
	var out: Array = []
	for m in th["messages"]:
		if String(m.get("from", "")) == "npc":
			out.append(String(m.get("text", "")))
	return out


func _test_furious_unhinged_ambushes() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -85.0)
	var uid := int(u["id"])
	phone._unhinged_ambush_tick(true)  # forced: skip the chance roll
	var texts := _npc_texts(phone, uid)
	_check("ambush: one proactive DM arrives", texts.size() == 1)
	_check("ambush: line is non-empty", not String(texts[0]).is_empty())
	_check("ambush: line is not the exhausted sentinel",
		String(texts[0]) != "...")
	var th: Dictionary = phone._thread(phone._key_for(uid))
	_check("ambush: thread marked unread", int(th.get("unread", 0)) == 1)
	_check("ambush: thread unanswered (incoming)",
		not bool(th.get("answered", true)))


func _test_calm_unhinged_silent() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -10.0)  # unhinged but calm
	var uid := int(u["id"])
	phone._unhinged_ambush_tick(true)
	_check("calm unhinged: no ambush", _npc_texts(phone, uid).is_empty())


func _test_stable_furious_silent() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn_stable(w, -95.0)  # furious but stable
	var uid := int(u["id"])
	phone._unhinged_ambush_tick(true)
	_check("stable furious: no ambush", _npc_texts(phone, uid).is_empty())


func _test_blocked_silent() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -95.0)
	var uid := int(u["id"])
	_check("block succeeds", phone.block_citizen(uid))
	phone._unhinged_ambush_tick(true)
	_check("blocked: no ambush DM", _npc_texts(phone, uid).is_empty())


func _test_dead_excluded() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -95.0)
	var uid := int(u["id"])
	u["alive"] = false
	phone._unhinged_ambush_tick(true)
	_check("dead: no ambush DM", _npc_texts(phone, uid).is_empty())


func _test_per_npc_cooldown() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -95.0)
	var uid := int(u["id"])
	phone._unhinged_ambush_tick(true)
	phone._unhinged_ambush_tick(true)  # same day, second tick
	_check("cooldown: still one ambush today",
		_npc_texts(phone, uid).size() == 1)


func _test_global_cap() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var units: Array = []
	for i in range(6):
		units.append(_spawn_unhinged(w, -95.0))
	phone._unhinged_ambush_tick(true)
	var total := 0
	for u in units:
		total += _npc_texts(phone, int(u["id"])).size()
	_check("global cap: at most 3 ambushes per day",
		total <= SimPhone.AMBUSH_GLOBAL_CAP)
	_check("global cap: exactly 3 sent (6 candidates, forced)",
		total == SimPhone.AMBUSH_GLOBAL_CAP)
	# Next day the cap resets; every NPC is eligible again (per-day
	# cooldown), but nobody gets more than one per day.
	gs.day_number += 1
	phone._unhinged_ambush_tick(true)
	var total2 := 0
	var max_per_npc := 0
	for u in units:
		var n := _npc_texts(phone, int(u["id"])).size()
		total2 += n
		max_per_npc = maxi(max_per_npc, n)
	_check("global cap: day 2 adds 3 more", total2 == 6)
	_check("cooldown: nobody exceeds one per day", max_per_npc <= 2)


func _test_reply_enters_reactive_path() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -85.0)
	var uid := int(u["id"])
	phone._unhinged_ambush_tick(true)
	_check("ambush landed first", _npc_texts(phone, uid).size() == 1)
	# Player replies to the ambush: the reactive cuss-out + spam chain
	# takes over (1 main + 3 spam extras queued).
	phone.send_message(uid, "bring it on")
	_check("reactive chain: 4 queued after reply", phone._pending.size() == 4)
	gs.game_time += 120.0
	phone.tick(0.0)
	_check("reactive chain: 5 npc messages total (1 ambush + 4)",
		_npc_texts(phone, uid).size() == 5)


func _test_thread_surfaces_on_top() -> void:
	var w := _new_world()
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -90.0)
	var uid := int(u["id"])
	phone._unhinged_ambush_tick(true)
	var ordered: Array = phone.sorted_threads()
	_check("ambush thread exists in list", not ordered.is_empty())
	var top: Dictionary = ordered[0]
	_check("ambush thread on top (newest-first)",
		String(top.get("key", "")) == phone._key_for(uid))
	_check("ambush thread shows unread", int(top.get("unread", 0)) > 0)


func _test_chance_table_sane() -> void:
	var ch: Dictionary = SimPhone.AMBUSH_CHANCE
	var heated := float(ch.get("heated", 0.0))
	var furious := float(ch.get("furious", 0.0))
	var unhinged := float(ch.get("unhinged", 0.0))
	_check("chance: heated in (0,1)", heated > 0.0 and heated < 1.0)
	_check("chance: furious in (0,1)", furious > 0.0 and furious < 1.0)
	_check("chance: unhinged in (0,1)", unhinged > 0.0 and unhinged < 1.0)
	_check("chance: escalates with fury",
		heated < furious and furious < unhinged)


func _test_tier_escalation() -> void:
	# The ambush tier follows live fury depth via the shared tier system.
	_check("tier: -65 -> heated",
		SimUnhinged.tier_for(-65.0) == "heated")
	_check("tier: -85 -> furious",
		SimUnhinged.tier_for(-85.0) == "furious")
	_check("tier: -95 -> unhinged",
		SimUnhinged.tier_for(-95.0) == "unhinged")
	_check("tier: threshold -60 -> heated",
		SimUnhinged.tier_for(-60.0) == "heated")


func _test_no_repeat_across_days() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var phone: SimPhone = w["phone"]
	var u := _spawn_unhinged(w, -95.0)
	var uid := int(u["id"])
	phone._unhinged_ambush_tick(true)
	var day1 := String(_npc_texts(phone, uid)[0])
	gs.day_number += 1
	phone._unhinged_ambush_tick(true)
	var texts := _npc_texts(phone, uid)
	_check("two ambushes across two days", texts.size() == 2)
	_check("ambush lines do not repeat", String(texts[1]) != day1)
