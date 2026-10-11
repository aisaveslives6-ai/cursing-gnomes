extends SceneTree
## Cursing Gnomes — AI faction leaders in the phone (Jeremy 2026-10-06).
##
## The player is the leader of their own faction; every OTHER faction is run
## by an AI leader persona picked from a per-faction pool — symmetric to the
## player, not a world NPC. These leaders must be VISIBLE in the phone as
## real Messenger contacts with distinct pixel-art portraits, chattable
## through the full conversation engine, with first words that track the
## real relationship (war, betrayals, alliances).
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_leader_phone_presence.gd
##
## Exit code 0 = all passed, 1 = any failure.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

const FACTIONS: Array[String] = ["humans", "ogres", "elves", "gnomes", "undead"]


func _initialize() -> void:
	print("=== Cursing Gnomes leader phone-presence tests ===")
	_test_every_candidate_has_portrait_file()
	_test_leader_records_carry_pfp()
	_test_leader_contacts_have_portraits()
	_test_pseudo_unit_carries_portrait()
	_test_leader_dm_full_engine()
	_test_leader_first_words_track_relationship()
	_test_load_backfills_missing_leaders()
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
	var gs: GameState = load("res://scripts/core/game_state.gd").new()
	var farr: Array[String] = []
	farr.assign(FACTIONS)
	gs.setup(farr)
	# Mimic the real game flow: setup() uses a default player faction,
	# then world.configure() finalizes it and reconciles leaders.
	gs.player_faction = "gnomes"
	gs.faction_leaders.on_player_faction_set("gnomes", farr)
	return gs


func _new_phone(gs: GameState):
	var phone = load("res://scripts/sim/phone.gd").new(gs)
	gs.set("phone_sys", phone)
	return phone


## Every candidate in every pool maps to a real portrait file on disk.
func _test_every_candidate_has_portrait_file() -> void:
	var fl_cls = load("res://scripts/sim/faction_leaders.gd")
	var pools: Dictionary = fl_cls.LEADER_POOLS
	var total := 0
	for faction: String in pools:
		var arr: Array = pools[faction]
		for i in range(arr.size()):
			total += 1
			var key: String = fl_cls.pfp_key_for(faction, i)
			_check("pfp key format %s[%d]" % [faction, i],
				key == "leader_%s_%s" % [faction, String(fl_cls.PFP_SLUGS[faction][i])])
			_check("portrait file exists: %s" % key,
				ResourceLoader.exists("res://assets/art/portraits/%s.webp" % key))
	_check("16 leader candidates total", total == 16)


## Picked leader records carry their persona's pfp key.
func _test_leader_records_carry_pfp() -> void:
	var gs: GameState = _new_gs()
	var fl = gs.faction_leaders
	for l: Dictionary in fl.all_leaders():
		var f: String = String(l.get("faction", ""))
		var pfp: String = String(l.get("pfp", ""))
		_check("record pfp matches candidate: %s" % f,
			pfp == SimFactionLeaders.pfp_key_for(f, int(l.get("candidate", -1))))
		_check("record pfp non-empty: %s" % f, pfp != "")
	gs.queue_free()


## leader_contacts() exposes 4 chattable leaders, each with a real portrait.
func _test_leader_contacts_have_portraits() -> void:
	var gs: GameState = _new_gs()
	var phone = _new_phone(gs)
	var contacts: Array = phone.leader_contacts()
	_check("4 leader contacts", contacts.size() == 4)
	for c: Dictionary in contacts:
		var f: String = String(c.get("faction", ""))
		var pfp: String = String(c.get("pfp", ""))
		_check("contact pfp non-empty: %s" % f, pfp != "")
		_check("contact portrait file exists: %s" % f,
			ResourceLoader.exists("res://assets/art/portraits/%s.webp" % pfp))
		_check("contact has full name: %s" % f,
			String(c.get("name", "")).length() > 3)
	gs.queue_free()


## The UI pseudo-unit carries the portrait key the avatar renderer needs.
func _test_pseudo_unit_carries_portrait() -> void:
	var gs: GameState = _new_gs()
	var phone = _new_phone(gs)
	for l: Dictionary in gs.faction_leaders.all_leaders():
		var f: String = String(l.get("faction", ""))
		var key: String = SimFactionLeaders.key_for(f)
		var u: Dictionary = phone.leader_pseudo_unit(key)
		_check("pseudo-unit not empty: %s" % f, not u.is_empty())
		_check("pseudo-unit name: %s" % f,
			String(u.get("_leader_name", "")) == String(l.get("name", "")))
		_check("pseudo-unit pfp: %s" % f,
			String(u.get("_leader_pfp", "")) == String(l.get("pfp", "")))
	gs.queue_free()


## Leader DMs go through the full engine and return real text.
func _test_leader_dm_full_engine() -> void:
	var gs: GameState = _new_gs()
	var phone = _new_phone(gs)
	var reply: String = phone._leader_full_reply("ogres", "hello there")
	_check("leader reply non-empty", reply != "" and reply != "...")
	gs.queue_free()


## A leader the player went to war with opens hostile — first words track
## the REAL relationship, not a neutral default.
func _test_leader_first_words_track_relationship() -> void:
	var gs: GameState = _new_gs()
	var phone = _new_phone(gs)
	var fl = gs.faction_leaders
	fl.remember("ogres", SimFactionLeaders.MEM_WAR, "gnomes",
		"War with the player began.", -1.0)
	_check("leader is furious after war memory",
		String(fl.mood_toward("ogres", "gnomes")) == "furious")
	var reply: String = phone._leader_full_reply("ogres", "hello friend")
	_check("furious leader still replies", reply != "")
	var unit: Dictionary = phone._leader_unit("ogres")
	var uid := int(unit.get("id", 0))
	_check("conversation mood seeded hostile (< -30)",
		phone.conversation.ruler_mood(uid) < -30.0)
	gs.queue_free()


## Old saves (no leader data) get leaders backfilled on load — the phone's
## Faction Leaders section is never empty.
func _test_load_backfills_missing_leaders() -> void:
	var gs: GameState = _new_gs()
	var fl_cls = load("res://scripts/sim/faction_leaders.gd")
	var fl2 = fl_cls.new(gs)
	fl2.load_save_data({})
	_check("backfill creates 4 leaders", fl2.all_leaders().size() == 4)
	for l: Dictionary in fl2.all_leaders():
		_check("backfilled leader has pfp: %s" % String(l.get("faction", "")),
			String(l.get("pfp", "")) != "")
	gs.queue_free()
