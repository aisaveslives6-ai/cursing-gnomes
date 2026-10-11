extends SceneTree
## Cursing Gnomes — friendship tests (AI-first phase).
##
## Covers the NPC-behavior checklist item "socializing": the HTML fix79
## NPC-NPC bonds system (u.bonds, bumpAffinity, bondsScore, traitFriction,
## tickSocialSampling — already ported into SimFamily) now DRIVES behavior:
##   - friend-seeking: a lonely NPC picks their best friend and walks to them
##   - friend joy: social with a friend satisfies 1.5x faster and lifts mood
##   - chat impression: a finished chat bumps affinity 6 - friction*3 + noise
##     (HTML social-slot partner bump, verbatim)
##   - criminals rob NPCs they dislike (HTML pickVictim55), never at random
##   - grief: only real friends/spouses get the friend_died memory; other
##     witnesses get a small mood dip instead of fake grief
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_friendship.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("=== Cursing Gnomes friendship tests ===")
	_test_bonds_score_stored()
	_test_bonds_score_friction_fallback()
	_test_is_friend_threshold()
	_test_is_friend_ignores_friction_fallback()
	_test_best_friend_picks_highest()
	_test_best_friend_skips_dead_far_foreign()
	_test_social_seeks_friend_and_walks()
	_test_social_friend_rate_and_mood()
	_test_social_chat_impression_bump()
	_test_social_target_cleared_on_done()
	_test_crime_victim_is_disliked()
	_test_crime_no_victim_when_all_liked()
	_test_grief_only_for_friends()
	_test_grief_spouse_counts()
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


func _close(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) < eps


## Fresh game + family + urges.
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans"])
	gs.towns[1] = {"id": 1, "name": "Town0", "faction": "humans",
		"pos": Vector2.ZERO, "owner": "humans"}
	var family := SimFamily.new(gs)
	gs.family = family
	var urges := SimUrges.new(gs)
	return {"gs": gs, "family": family, "urges": urges}


func _free_world(w: Dictionary) -> void:
	(w["gs"] as GameState).free()


func _unit(w: Dictionary, pos: Vector2 = Vector2(5000, 5000),
		faction: String = "humans") -> Dictionary:
	var gs: GameState = w["gs"]
	var u: Dictionary = gs.add_unit({
		"faction": faction, "job": "worker", "town_id": 1,
		"position": pos, "alive": true,
		"hp": 100.0, "max_hp": 100.0, "speed": 36.0,
	})
	(w["family"] as SimFamily).ensure(u)
	(w["urges"] as SimUrges).ensure(u)
	return u


func _set_social(u: Dictionary, v: float) -> void:
	var um: Dictionary = u.get("urges", {})
	um["social"] = v
	um["mood"] = 60.0
	u["urges"] = um


## --- bonds_score ------------------------------------------------------------

func _test_bonds_score_stored() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var a := _unit(w)
	var b := _unit(w, Vector2(5100, 5000))
	fam.bump_affinity(a, b, 50.0)
	_check("stored bond a->b", _close(fam.bonds_score(a, b), 50.0))
	# HTML: the return bump is asymmetric (d * 0.9).
	_check("stored bond b->a", _close(fam.bonds_score(b, a), 45.0))
	_free_world(w)


func _test_bonds_score_friction_fallback() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var a := _unit(w)
	var b := _unit(w, Vector2(5100, 5000))
	_check("fallback = friction * -22",
		_close(fam.bonds_score(a, b), fam.trait_friction(a, b) * -22.0))
	_free_world(w)


func _test_is_friend_threshold() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var a := _unit(w)
	var b := _unit(w, Vector2(5100, 5000))
	fam.bump_affinity(a, b, 20.0)
	_check("20 is not a friend", not fam.is_friend(a, b))
	fam.bump_affinity(a, b, 20.0)  # 40 total
	_check("40 is a friend", fam.is_friend(a, b))
	_free_world(w)


func _test_is_friend_ignores_friction_fallback() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var a := _unit(w)
	var b := _unit(w, Vector2(5100, 5000))
	# No stored bond: even a perfect personality match is not friendship.
	_check("strangers are not friends", not fam.is_friend(a, b))
	_check("best_friend finds nobody", fam.best_friend(a, 900.0).is_empty())
	_free_world(w)


## --- best_friend ------------------------------------------------------------

func _test_best_friend_picks_highest() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var a := _unit(w)
	var b := _unit(w, Vector2(5050, 5000))
	var c := _unit(w, Vector2(5060, 5000))
	fam.bump_affinity(a, b, 50.0)
	fam.bump_affinity(a, c, 70.0)
	var best: Dictionary = fam.best_friend(a, 900.0)
	_check("picks highest bond", int(best.get("id", -1)) == int(c.get("id", -1)))
	_free_world(w)


func _test_best_friend_skips_dead_far_foreign() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var a := _unit(w)
	var dead := _unit(w, Vector2(5050, 5000))
	var far := _unit(w, Vector2(7000, 5000))
	var foreign := _unit(w, Vector2(5050, 5000), "ogres")
	var ok := _unit(w, Vector2(5060, 5000))
	fam.bump_affinity(a, dead, 90.0)
	fam.bump_affinity(a, far, 90.0)
	fam.bump_affinity(a, foreign, 90.0)
	fam.bump_affinity(a, ok, 40.0)
	dead["alive"] = false
	var best: Dictionary = fam.best_friend(a, 900.0)
	_check("skips dead/far/foreign", int(best.get("id", -1)) == int(ok.get("id", -1)))
	_free_world(w)


## --- social urge ------------------------------------------------------------

func _test_social_seeks_friend_and_walks() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var urges: SimUrges = w["urges"]
	var a := _unit(w, Vector2(5000, 5000))
	var pal := _unit(w, Vector2(5500, 5000))  # 500px away
	fam.bump_affinity(a, pal, 60.0)
	_set_social(a, 10.0)
	var before: Vector2 = a.get("position", Vector2.ZERO)
	var res: String = urges.satisfy(a, "social", 1.0)
	_check("targets the friend",
		int(a.get("social_target", -1)) == int(pal.get("id", -1)))
	var after: Vector2 = a.get("position", Vector2.ZERO)
	_check("walks toward friend",
		after.distance_to(pal.get("position", Vector2.ZERO)) \
			< before.distance_to(pal.get("position", Vector2.ZERO)))
	_check("still busy while walking", res == "busy")
	_free_world(w)


func _test_social_friend_rate_and_mood() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var urges: SimUrges = w["urges"]
	var a := _unit(w, Vector2(5000, 5000))
	var pal := _unit(w, Vector2(5100, 5000))  # within 200px
	fam.bump_affinity(a, pal, 60.0)
	_set_social(a, 50.0)
	urges.satisfy(a, "social", 1.0)
	var with_friend: float = float((a.get("urges", {}) as Dictionary).get("social", 0.0))
	var mood_friend: float = float((a.get("urges", {}) as Dictionary).get("mood", 0.0))
	_free_world(w)
	# Stranger company for comparison.
	var w2 := _new_world()
	var urges2: SimUrges = w2["urges"]
	var b := _unit(w2, Vector2(5000, 5000))
	var stranger := _unit(w2, Vector2(5100, 5000))
	_set_social(b, 50.0)
	urges2.satisfy(b, "social", 1.0)
	var with_stranger: float = float((b.get("urges", {}) as Dictionary).get("social", 0.0))
	var mood_stranger: float = float((b.get("urges", {}) as Dictionary).get("mood", 0.0))
	_free_world(w2)
	_check("friend satisfies faster", with_friend > with_stranger)
	_check("friend lifts mood", mood_friend > mood_stranger)
	_check("friend rate ~18/s", _close(with_friend, 68.0))
	_check("stranger rate ~12/s", _close(with_stranger, 62.0))


func _test_social_chat_impression_bump() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var urges: SimUrges = w["urges"]
	var a := _unit(w, Vector2(5000, 5000))
	var pal := _unit(w, Vector2(5100, 5000))
	_set_social(a, 69.0)  # one tick of company finishes the chat
	var before: float = fam.get_affinity(a, pal)
	_check("no prior bond", _close(before, 0.0))
	var res: String = urges.satisfy(a, "social", 1.0)
	_check("chat completes", res == "done")
	var after: float = fam.get_affinity(a, pal)
	# HTML: 6 - friction*3 + (rand-0.5)*4 -> noise is bounded by +/-2.
	var fr: float = fam.trait_friction(a, pal)
	_check("impression bumped affinity",
		absf(after - (6.0 - fr * 3.0)) <= 2.0 + 0.001)
	_free_world(w)


func _test_social_target_cleared_on_done() -> void:
	var w := _new_world()
	var fam: SimFamily = w["family"]
	var urges: SimUrges = w["urges"]
	var a := _unit(w, Vector2(5000, 5000))
	var pal := _unit(w, Vector2(5500, 5000))
	fam.bump_affinity(a, pal, 60.0)
	a["social_target"] = int(pal.get("id", -1))
	pal["alive"] = false  # friend died mid-walk: target must invalidate
	_set_social(a, 10.0)
	urges.satisfy(a, "social", 1.0)
	_check("dead target cleared", int(a.get("social_target", -2)) == -1)
	_free_world(w)


## --- crime ------------------------------------------------------------------

func _spawn_crime_world() -> Dictionary:
	var w := _new_world()
	var life := SimCrimeLife.new(w["gs"], null)
	return {"w": w, "life": life}


func _test_crime_victim_is_disliked() -> void:
	var cw := _spawn_crime_world()
	var w: Dictionary = cw["w"]
	var fam: SimFamily = w["family"]
	var life: SimCrimeLife = cw["life"]
	var crook := _unit(w, Vector2(5000, 5000))
	var hated := _unit(w, Vector2(5050, 5000))
	var loved := _unit(w, Vector2(5060, 5000))
	fam.bump_affinity(crook, hated, -30.0)
	fam.bump_affinity(crook, loved, 50.0)
	var victim: Dictionary = life._pick_victim(crook)
	_check("robs the disliked NPC",
		int(victim.get("id", -1)) == int(hated.get("id", -1)))
	_free_world(w)


func _test_crime_no_victim_when_all_liked() -> void:
	var cw := _spawn_crime_world()
	var w: Dictionary = cw["w"]
	var fam: SimFamily = w["family"]
	var life: SimCrimeLife = cw["life"]
	var crook := _unit(w, Vector2(5000, 5000))
	var pal := _unit(w, Vector2(5050, 5000))
	fam.bump_affinity(crook, pal, 50.0)
	# Criminal trait defaults to ~0.5: not shady enough for stranger robbery.
	var victim: Dictionary = life._pick_victim(crook)
	_check("no random victim", victim.is_empty())
	_free_world(w)


## --- grief ------------------------------------------------------------------

func _test_grief_only_for_friends() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var fam: SimFamily = w["family"]
	var mind := SimMind.new(gs)
	var dead := _unit(w, Vector2(5000, 5000))
	var friend := _unit(w, Vector2(5100, 5000))
	var stranger := _unit(w, Vector2(5200, 5000))
	fam.bump_affinity(friend, dead, 40.0)
	_set_social(stranger, 50.0)
	dead["alive"] = false
	mind.on_unit_died(int(dead.get("id", 0)), "humans")
	var fmems: Array = mind.memories.ensure(friend)
	var smems: Array = mind.memories.ensure(stranger)
	_check("friend remembers friend_died",
		fmems.any(func(m: Dictionary) -> bool:
			return String(m.get("type", "")) == "friend_died"))
	_check("stranger gets no friend_died memory",
		not smems.any(func(m: Dictionary) -> bool:
			return String(m.get("type", "")) == "friend_died"))
	var smood: float = float((mind.urges.ensure(stranger)).get("mood", 60.0))
	_check("stranger mood dips", smood < 60.0)
	_free_world(w)


func _test_grief_spouse_counts() -> void:
	var w := _new_world()
	var gs: GameState = w["gs"]
	var mind := SimMind.new(gs)
	var dead := _unit(w, Vector2(5000, 5000))
	var spouse := _unit(w, Vector2(5100, 5000))
	spouse["spouse_uid"] = int(dead.get("id", -1))
	dead["alive"] = false
	mind.on_unit_died(int(dead.get("id", 0)), "humans")
	var mems: Array = mind.memories.ensure(spouse)
	_check("spouse grieves",
		mems.any(func(m: Dictionary) -> bool:
			return String(m.get("type", "")) == "friend_died"))
	_free_world(w)
