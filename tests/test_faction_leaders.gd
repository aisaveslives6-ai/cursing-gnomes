extends SceneTree
## Cursing Gnomes — AI faction leader tests (Jeremy 2026-10-04).
##
## Leaders exist for all 5 factions, communication works, memory persists,
## commands affect AI behavior, policy proposals get appropriate responses.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_faction_leaders.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

const FACTIONS: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]


func _initialize() -> void:
	print("=== Cursing Gnomes faction leader tests ===")
	_test_leaders_exist_all_factions()
	_test_leader_names_distinct()
	_test_leader_keys()
	_test_memory_remember_recall()
	_test_memory_cap()
	_test_opinion_decay()
	_test_racist_incident_memory()
	_test_racist_incident_universal()
	_test_mood_shifts()
	_test_reply_to_greeting()
	_test_reply_to_war()
	_test_reply_to_peace_hostile()
	_test_reply_personality_voices()
	_test_apology_racist_not_erased()
	_test_propose_trade()
	_test_propose_unknown()
	_test_propose_own_faction()
	_test_command_allied()
	_test_command_refused_not_trusted()
	_test_command_unknown_directive()
	_test_command_own_faction()
	_test_directive_maneuver_map()
	_test_directive_expiry()
	_test_save_load_roundtrip()
	_test_leader_message_player()
	_test_daily_tick_no_crash()
	_test_pool_picking()
	_test_on_player_faction_set()
	_test_save_load_preserves_candidate()
	_test_leader_contacts()
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
	var farr: Array[String] = []
	farr.assign(FACTIONS)
	gs.setup(farr)
	# Jeremy 2026-10-06: mimic the real game flow — setup() uses a default
	# player faction, then world.configure() finalizes it. Reconcile leaders.
	gs.player_faction = "gnomes"
	gs.faction_leaders.on_player_faction_set("gnomes", farr)
	return gs


func _test_leaders_exist_all_factions() -> void:
	var gs: GameState = _new_gs()
	for f: String in FACTIONS:
		var l: Dictionary = gs.faction_leaders.leader_of(f)
		if f == "gnomes":
			# Jeremy 2026-10-06: the player's own faction has NO AI leader.
			_check("no leader for player faction: %s" % f, l.is_empty())
		else:
			_check("leader exists: %s" % f, not l.is_empty())
			_check("leader faction: %s" % f, String(l.get("faction", "")) == f)
	gs.queue_free()


func _test_leader_names_distinct() -> void:
	var gs: GameState = _new_gs()
	var names: Dictionary = {}
	for f: String in FACTIONS:
		if f == "gnomes":
			continue  # player faction has no leader
		var l: Dictionary = gs.faction_leaders.leader_of(f)
		var n: String = String(l.get("name", ""))
		_check("leader has name: %s" % f, n != "")
		_check("name unique: %s" % n, not names.has(n))
		names[n] = true
	gs.queue_free()


func _test_leader_keys() -> void:
	_check("key format", SimFactionLeaders.key_for("ogres") == "leader_ogres")
	_check("is leader key", SimFactionLeaders.is_leader_key("leader_elves"))
	_check("not leader key", not SimFactionLeaders.is_leader_key("u123"))
	_check("faction from key",
		SimFactionLeaders.faction_for_key("leader_undead") == "undead")


func _test_memory_remember_recall() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	fl.remember("ogres", "message", "gnomes", "Player said hi.", 0.3)
	var mems: Array = fl.recall("ogres", "message")
	_check("memory stored", mems.size() == 1)
	_check("memory text", String(mems[0].get("text", "")) == "Player said hi.")
	_check("memory subject", String(mems[0].get("subject", "")) == "gnomes")
	gs.queue_free()


func _test_memory_cap() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	for i in range(60):
		fl.remember("elves", "message", "gnomes", "msg %d" % i, 0.1)
	var mems: Array = fl.recall("elves", "message")
	_check("memory capped at 50", mems.size() <= 50)
	gs.queue_free()


func _test_opinion_decay() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	fl.remember("humans", "policy", "gnomes", "Good trade.", 0.8)
	var op1: float = fl.opinion_of("humans", "gnomes")
	_check("positive opinion", op1 > 0.3)
	# Advance 60 days — should decay significantly.
	gs.day_number += 60
	var op2: float = fl.opinion_of("humans", "gnomes")
	_check("opinion decays", op2 < op1)
	gs.queue_free()


func _test_racist_incident_memory() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	fl.note_racist_incident("gnomes", "ass")
	for f: String in FACTIONS:
		if f == "gnomes":
			continue  # player faction has no AI leader to remember
		var mems: Array = fl.recall(f, "racist_incident")
		_check("racist remembered by %s" % f, mems.size() == 1)
		_check("racist subject: %s" % f,
			String(mems[0].get("subject", "")) == "gnomes")
	gs.queue_free()


func _test_racist_incident_universal() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	fl.note_racist_incident("gnomes", "ass")
	# Even after 100 days, racist memory persists (slow decay floor).
	gs.day_number += 100
	for f: String in FACTIONS:
		if f == "gnomes":
			continue  # player faction has no AI leader
		var op: float = fl.opinion_of(f, "gnomes")
		_check("racist opinion persists: %s" % f, op < -0.3)
	gs.queue_free()


func _test_mood_shifts() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	fl.remember("ogres", "policy", "gnomes", "Great deal!", 0.9)
	_check("mood happy after good", String(fl.leader_of("ogres").get("mood", "")) == "happy")
	fl.remember("ogres", "policy", "gnomes", "Terrible deal!", -0.9)
	_check("mood angry after bad", String(fl.leader_of("ogres").get("mood", "")) == "angry")
	gs.queue_free()


func _test_reply_to_greeting() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	for f: String in FACTIONS:
		if f == "gnomes":
			continue  # player faction has no AI leader to reply
		var r: String = fl.reply_to(f, "gnomes", "hello there")
		_check("greeting reply: %s" % f, r != "" and r != "...")
	gs.queue_free()


func _test_reply_to_war() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	var r: String = fl.reply_to("ogres", "gnomes", "I will destroy you in war")
	_check("ogre war reply blunt", "HA" in r or "war" in r.to_lower())
	gs.queue_free()


func _test_reply_to_peace_hostile() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	# Make them furious first.
	fl.note_racist_incident("gnomes", "ass")
	var r: String = fl.reply_to("elves", "gnomes", "let's have peace")
	# Should be hostile, not welcoming.
	_check("hostile peace rebuffed",
		"nothing to discuss" in r.to_lower() or "..." in r or r.length() < 60)
	gs.queue_free()


func _test_reply_personality_voices() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	var ogre_r: String = fl.reply_to("ogres", "gnomes", "hello")
	var elf_r: String = fl.reply_to("elves", "gnomes", "hello")
	# Different voices should produce different replies.
	_check("voices differ", ogre_r != elf_r)
	gs.queue_free()


func _test_apology_racist_not_erased() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	fl.note_racist_incident("gnomes", "ass")
	var r: String = fl.reply_to("ogres", "gnomes", "I'm sorry, forgive me")
	_check("apology doesn't erase racist",
		"sorry" in r.to_lower() or "unsaid" in r.to_lower() or "remember" in r.to_lower())
	# Opinion should still be very negative.
	_check("opinion still negative", fl.opinion_of("ogres", "gnomes") < -0.5)
	gs.queue_free()


func _test_propose_trade() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	var res: Dictionary = fl.propose("ogres", "trade")
	_check("propose returns ok", bool(res.get("ok", false)))
	_check("propose has msg", String(res.get("msg", "")) != "")
	_check("propose has leader_says", String(res.get("leader_says", "")) != "")
	# Leader remembers the proposal.
	var mems: Array = fl.recall("ogres", "policy")
	_check("proposal remembered", mems.size() >= 1)
	gs.queue_free()


func _test_propose_unknown() -> void:
	var gs: GameState = _new_gs()
	var res: Dictionary = gs.faction_leaders.propose("ogres", "bogus")
	_check("unknown policy rejected", not bool(res.get("ok", true)))
	gs.queue_free()


func _test_propose_own_faction() -> void:
	var gs: GameState = _new_gs()
	var res: Dictionary = gs.faction_leaders.propose("gnomes", "trade")
	_check("own faction rejected", not bool(res.get("ok", true)))
	gs.queue_free()


func _test_command_allied() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	# Make them allied.
	gs.diplomacy.propose_alliance("gnomes", "ogres")
	# Force allied state for the test.
	gs.diplomacy._pairs["gnomes|ogres"]["state"] = "allied"
	var res: Dictionary = fl.issue_command("ogres", "military")
	_check("allied command accepted", bool(res.get("ok", false)))
	_check("directive set", fl.get_directive("ogres") == "military")
	gs.queue_free()


func _test_command_refused_not_trusted() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	# Neutral, no trust — should refuse.
	var res: Dictionary = fl.issue_command("elves", "military")
	_check("untrusted command refused", not bool(res.get("ok", true)))
	_check("no directive set", fl.get_directive("elves") == "")
	gs.queue_free()


func _test_command_unknown_directive() -> void:
	var gs: GameState = _new_gs()
	var res: Dictionary = gs.faction_leaders.issue_command("ogres", "dance")
	_check("unknown directive rejected", not bool(res.get("ok", true)))
	gs.queue_free()


func _test_command_own_faction() -> void:
	var gs: GameState = _new_gs()
	var res: Dictionary = gs.faction_leaders.issue_command("gnomes", "military")
	_check("own faction command rejected", not bool(res.get("ok", true)))
	gs.queue_free()


func _test_directive_maneuver_map() -> void:
	_check("military->raid",
		SimFactionLeaders.maneuver_for_directive("military") == "raid")
	_check("economy->expand",
		SimFactionLeaders.maneuver_for_directive("economy") == "expand")
	_check("fortify->fortify",
		SimFactionLeaders.maneuver_for_directive("fortify") == "fortify")
	_check("defend->defend",
		SimFactionLeaders.maneuver_for_directive("defend") == "defend")
	_check("unknown->empty",
		SimFactionLeaders.maneuver_for_directive("bogus") == "")


func _test_directive_expiry() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	gs.diplomacy._pairs["gnomes|ogres"] = {"state": "allied", "score": 50.0}
	fl.issue_command("ogres", "fortify")
	_check("directive active", fl.get_directive("ogres") == "fortify")
	# Advance 8 days — should expire.
	gs.day_number += 8
	fl.tick(0.0)
	_check("directive expired", fl.get_directive("ogres") == "")
	gs.queue_free()


func _test_save_load_roundtrip() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	fl.remember("ogres", "policy", "gnomes", "Test memory.", 0.5)
	fl.issue_command("ogres", "military")  # will fail (not allied) — fine
	var data: Dictionary = fl.get_save_data()
	_check("save has ogres", data.has("ogres"))
	# Load into fresh leaders.
	var gs2: GameState = _new_gs()
	var fl2 = gs2.faction_leaders
	fl2.load_save_data(data)
	var mems: Array = fl2.recall("ogres", "policy")
	_check("memory restored", mems.size() >= 1)
	gs.queue_free()
	gs2.queue_free()


func _test_leader_message_player() -> void:
	var gs: GameState = _new_gs()
	# Needs phone_sys for leader_message — use a mock via direct call.
	# Just verify no crash when phone_sys is null.
	var fl = gs.faction_leaders
	fl.message_player("ogres", "Test message")
	_check("message_player no crash without phone", true)
	# Memory recorded.
	var mems: Array = fl.recall("ogres", "message")
	_check("leader message remembered", mems.size() >= 1)
	gs.queue_free()


func _test_daily_tick_no_crash() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	gs.day_number += 1
	fl.tick(0.0)  # triggers _daily_tick internally
	_check("daily tick no crash", true)
	gs.queue_free()


## Jeremy 2026-10-06: ONE random candidate picked per faction from the pool.
func _test_pool_picking() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	for f: String in ["humans", "ogres", "elves", "undead"]:
		var idx: int = fl.candidate_index_of(f)
		var pool: Array = SimFactionLeaders.LEADER_POOLS.get(f, [])
		_check("candidate picked in range: %s" % f, idx >= 0 and idx < pool.size())
		var l: Dictionary = fl.leader_of(f)
		var def: Dictionary = pool[idx]
		_check("picked name matches pool: %s" % f,
			String(l.get("name", "")) == String(def.get("name", "")))
		# Traits come from the picked candidate.
		var lt: Dictionary = fl.traits_of(f)
		var dt: Dictionary = def.get("traits", {})
		_check("traits match picked candidate: %s" % f,
			float(lt.get("aggression", -1.0)) == float(dt.get("aggression", -1.0)))
	gs.queue_free()


## Jeremy 2026-10-06: changing the player faction reconciles leaders —
## the new player faction loses its AI leader, others gain one if missing.
func _test_on_player_faction_set() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	var farr: Array[String] = []
	farr.assign(FACTIONS)
	# Switch player from gnomes to elves.
	gs.player_faction = "elves"
	fl.on_player_faction_set("elves", farr)
	_check("elves leader removed", fl.leader_of("elves").is_empty())
	_check("gnomes leader added", not fl.leader_of("gnomes").is_empty())
	_check("humans still has leader", not fl.leader_of("humans").is_empty())
	# Idempotent: calling again doesn't re-roll.
	var idx_before: int = fl.candidate_index_of("humans")
	fl.on_player_faction_set("elves", farr)
	_check("no re-roll on repeat", fl.candidate_index_of("humans") == idx_before)
	gs.queue_free()


## Jeremy 2026-10-06: save/load preserves the picked candidate (no re-roll).
func _test_save_load_preserves_candidate() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	var before: Dictionary = {}
	for f: String in ["humans", "ogres", "elves", "undead"]:
		before[f] = fl.candidate_index_of(f)
	var data: Dictionary = fl.get_save_data()
	var gs2: GameState = _new_gs()
	# Clear the auto-picked leaders so load is the only source.
	var fl2 = gs2.faction_leaders
	fl2.load_save_data(data)
	for f: String in before:
		_check("candidate preserved: %s" % f,
			fl2.candidate_index_of(f) == int(before[f]))
	gs.queue_free()
	gs2.queue_free()


## Jeremy 2026-10-06: leader_contacts shows AI leaders, excludes player faction.
func _test_leader_contacts() -> void:
	var gs: GameState = _new_gs()
	var phone := SimPhone.new(gs)
	var contacts: Array = phone.leader_contacts()
	_check("4 leader contacts (not player faction)", contacts.size() == 4)
	var factions: Dictionary = {}
	for c: Dictionary in contacts:
		var f: String = String(c.get("faction", ""))
		factions[f] = true
		_check("leader contact not player faction: %s" % f, f != "gnomes")
		_check("leader key format: %s" % f,
			String(c.get("key", "")).begins_with("leader_"))
		_check("leader has name: %s" % f, String(c.get("name", "")) != "")
		_check("leader has subtitle: %s" % f, String(c.get("sub", "")) != "")
	_check("ogres leader present", factions.has("ogres"))
	_check("humans leader present", factions.has("humans"))
	_check("elves leader present", factions.has("elves"))
	_check("undead leader present", factions.has("undead"))
	gs.queue_free()
