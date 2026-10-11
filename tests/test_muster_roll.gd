## Cursing Gnomes — C67 muster-roll tests (2026-10-08).
## HTML fix79 parity: "troop report" / "how many soldiers" / "how many X"
## are answered from LIVE unit counts, computed at speak time.
## 1. Intent routing: report/how-many questions -> question_troops, while
##    troop REQUESTS ("lend me some troops") and drill ORDERS ("muster
##    the troops") keep their old intents.
## 2. Full muster roll: military jobs only, nonzero only, dead units and
##    other factions excluded, stable job order, total correct.
## 3. Single-job questions: "how many mages" -> "Mage: N" (military and
##    civilian jobs alike).
## 4. Empty army -> the "no standing army" pool; war enemies -> refusal.
## 5. No raw {musterRoll}/{musterTotal} tokens ever reach the player.
extends SceneTree


class FakeDiplomacy extends RefCounted:
	var state := "peace"
	func relation_state(_a: String, _b: String) -> String:
		return state


var _passed := 0
var _failed := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("  FAIL: ", name)


func _init() -> void:
	print("\n=== Cursing Gnomes muster-roll (C67) tests ===")
	_test_intent_routing()
	_test_full_muster_roll()
	_test_single_job()
	_test_empty_army()
	_test_war_refusal()
	_test_foreign_faction_own_numbers()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)


func _make_dip() -> FakeDiplomacy:
	return FakeDiplomacy.new()


func _make_gs(dip: FakeDiplomacy, units: Array, player_faction: String = "gnome") -> Dictionary:
	return {
		"ruler_name": "TestRuler",
		"player_faction": player_faction,
		"day_number": 1,
		"diplomacy": dip,
		"towns": {},
		"units": units,
	}


func _make_unit(faction: String, uid: int, job: String, alive: bool = true) -> Dictionary:
	return {
		"id": uid, "faction": faction, "display_name": "TestNPC",
		"name": "TestNPC", "alive": alive, "job": job,
	}


func _muster_units() -> Array:
	return [
		_make_unit("gnome", 1, "soldier"),
		_make_unit("gnome", 2, "soldier"),
		_make_unit("gnome", 3, "soldier"),
		_make_unit("gnome", 4, "archer"),
		_make_unit("gnome", 5, "archer", false), # dead: excluded
		_make_unit("gnome", 6, "mage"),
		_make_unit("gnome", 7, "worker"),
		_make_unit("gnome", 8, "worker"), # civilian: not on muster roll
		_make_unit("gnome", 9, "farmer"),
		_make_unit("elf", 10, "soldier"), # other faction: excluded
	]


## 1. Intent routing.
func _test_intent_routing() -> void:
	var conv := SimConversation.new()
	var cases := [
		["troop report", "question_troops"],
		["how many soldiers do we have", "question_troops"],
		["how many archers are there", "question_troops"],
		["give me the battle report", "question_troops"],
		["muster roll", "question_troops"],
		["army status", "question_troops"],
		["how is our army", "question_troops"],
		["how many farmers do we have", "question_troops"],
		["how many mages", "question_troops"],
		# Kept: requests and drill orders do NOT become reports. ("lend me
		# some troops" was already request_gold before muster rolls existed
		# — the gold intent's "lend"/"give me" keys outscore troop keys.)
		["lend me some troops", "request_gold"],
		["muster the troops", "order_drills"],
		["send troops to the border", "request_troops"],
		# Kept: neighboring question intents still win their turf.
		["how many towns do you have", "question_towns"],
		["are we at war", "question_wars"],
	]
	for c in cases:
		var p: Dictionary = conv.parse_intent(conv._normalize(String(c[0])))
		_check("intent '%s' -> %s" % [c[0], c[1]],
			String(p.get("intent", "")) == String(c[1]))


## 2. Full muster roll from live counts.
func _test_full_muster_roll() -> void:
	var conv := SimConversation.new()
	var dip := _make_dip()
	var gs := _make_gs(dip, _muster_units())
	var unit := _make_unit("gnome", 100, "soldier")
	var r: Dictionary = conv.reply(unit, "troop report", gs)
	_check("report intent", String(r["intent"]) == "question_troops")
	var t := String(r["text"])
	_check("soldiers counted", t.contains("Soldier: 3"))
	_check("dead archer excluded", t.contains("Archer: 1"))
	_check("mage counted", t.contains("Mage: 1"))
	_check("civilians not on muster roll", not t.contains("Worker"))
	_check("other faction excluded", not t.contains("Elf"))
	_check("total correct", t.contains("5"))
	# Stable order: JobDefs military declaration order.
	_check("roll order stable",
		t.find("Soldier: 3") < t.find("Archer: 1") \
		and t.find("Archer: 1") < t.find("Mage: 1"))
	_check("no raw {musterRoll} token", not t.contains("{musterRoll}"))
	_check("no raw {musterTotal} token", not t.contains("{musterTotal}"))
	_check("no raw {name} token", not t.contains("{name}"))


## 3. Single-job questions, military and civilian.
func _test_single_job() -> void:
	var conv := SimConversation.new()
	var dip := _make_dip()
	var gs := _make_gs(dip, _muster_units())
	var unit := _make_unit("gnome", 101, "soldier")
	var r1: Dictionary = conv.reply(unit, "how many mages do we have", gs)
	_check("mage intent", String(r1["intent"]) == "question_troops")
	_check("mage count", String(r1["text"]).contains("Mage: 1"))
	var r2: Dictionary = conv.reply(unit, "how many farmers", gs)
	_check("farmer count (civilian works)", String(r2["text"]).contains("Farmer: 1"))
	var r3: Dictionary = conv.reply(unit, "how many warriors", gs)
	_check("warrior alias -> soldier", String(r3["text"]).contains("Soldier: 3"))


## 4. No standing army -> the empty pool, never an empty roll.
func _test_empty_army() -> void:
	var conv := SimConversation.new()
	var dip := _make_dip()
	var gs := _make_gs(dip, [_make_unit("gnome", 1, "worker")])
	var unit := _make_unit("gnome", 102, "soldier")
	var r: Dictionary = conv.reply(unit, "troop report", gs)
	_check("empty intent", String(r["intent"]) == "question_troops")
	var t := String(r["text"])
	_check("no empty roll", not t.contains(": 0"))
	_check("no tokens leak", not t.contains("{musterRoll}"))
	_check("empty army says so",
		t.contains("pointy sticks") or t.contains("blank") \
		or t.contains("Zero") or t.contains("empty") \
		or t.contains("No ") or t.contains("no standing"))


## 5. War enemies get a refusal, not numbers.
func _test_war_refusal() -> void:
	var conv := SimConversation.new()
	var dip := _make_dip()
	dip.state = "war"
	var gs := _make_gs(dip, _muster_units(), "gnome")
	var unit := _make_unit("elf", 103, "soldier")
	var r: Dictionary = conv.reply(unit, "troop report", gs)
	_check("refusal intent", String(r["intent"]) == "question_troops")
	var t := String(r["text"])
	_check("no numbers for enemies",
		not t.contains("Soldier:") and not t.contains("Archer:"))
	_check("no tokens leak", not t.contains("{musterRoll}"))


## 6. Foreign (non-war) NPCs report their OWN faction's numbers.
func _test_foreign_faction_own_numbers() -> void:
	var conv := SimConversation.new()
	var dip := _make_dip() # peace
	var gs := _make_gs(dip, _muster_units(), "gnome")
	var unit := _make_unit("elf", 104, "archer")
	var r: Dictionary = conv.reply(unit, "troop report", gs)
	_check("foreign intent", String(r["intent"]) == "question_troops")
	var t := String(r["text"])
	_check("elf counts own faction", t.contains("Soldier: 1"))
	_check("gnome troops not leaked", not t.contains("Soldier: 3"))
