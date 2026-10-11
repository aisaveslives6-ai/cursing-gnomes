extends SceneTree
## Cursing Gnomes — gazette content glyph tests (Jeremy 2026-10-03).
##
## Royal Gazette headlines/bodies render directly in a Label on the phone
## (phone_ui.gd renders article["headline"]). Emoji in story text render as
## tofu boxes on Jeremy's iPhone in the web export, so story text must be
## glyph-free just like UI chrome (same >U+2500 rule as
## test_director_glyphs.gd). Covers the war gazette lines in
## scripts/sim/army.gd: MUTUAL COLLAPSE, WAR COLLAPSE, CONQUEST.
## (WAR DECLARED vs the player is gated behind the AI war-tick RNG roll, so
## it is covered by the static text-only sweep rather than a live emit.)
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_gazette_glyphs.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []
var _stories: Array[Dictionary] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


## Same >U+2500 rule as test_director_glyphs: plain text never reaches this
## high; anything above it is a tofu risk on iPhone.
static func _has_glyph(s: String) -> bool:
	for i in range(s.length()):
		if s.unicode_at(i) > 0x2500:
			return true
	return false


func _initialize() -> void:
	print("=== Cursing Gnomes gazette glyph tests ===")
	_run.call_deferred()


func _on_story(story: Dictionary) -> void:
	_stories.append(story)


## Fresh game + army system, mirroring test_army.gd's _new_world().
func _new_world() -> Dictionary:
	var gs: GameState = GameState.new()
	root.add_child(gs)
	gs.setup(["humans", "ogres", "elves", "gnomes", "undead"])
	var army := SimArmy.new(gs)
	army.diplomacy = gs.diplomacy
	gs.bus.gazette_story.connect(_on_story)
	return {"gs": gs, "army": army}


func _run() -> void:
	await process_frame
	await process_frame

	# Mutual collapse: two factions at war with nobody able to fight.
	var w1 := _new_world()
	var army1: SimArmy = w1["army"]
	(w1["gs"] as GameState).diplomacy.declare_war("elves", "gnomes", "test")
	army1.collapse_tick()

	# One-sided collapse: ogres break, armed humans win.
	var w2 := _new_world()
	var army2: SimArmy = w2["army"]
	var gs2: GameState = w2["gs"]
	for i in 3:
		gs2.spawner.spawn_unit("humans", "soldier", -1, Vector2(i * 10, 0))
	gs2.diplomacy.declare_war("humans", "ogres", "test")
	army2.collapse_tick()

	# Conquest rename story (Jeremy's corrected undead roster note lives
	# in memory; this is the conquest-flow gazette headline).
	army2._conquest_queue.append({
		"position": Vector2.ZERO, "old_name": "Ogrehold",
		"town_id": -1, "faction": "ogres",
	})
	army2.resolve_conquest("Newtown")

	var bad: Array[String] = []
	for story in _stories:
		var hl: String = str(story.get("headline", ""))
		var body: String = str(story.get("body", ""))
		if _has_glyph(hl):
			bad.append("headline: %s" % hl)
		if _has_glyph(body):
			bad.append("body: %s" % body)
	_check("war gazette headlines/bodies glyph-free", bad.is_empty())
	for b in bad:
		print("  gazette glyph: ", b)

	# Sanity: we actually captured the war stories we intended to cover.
	var headlines: Array[String] = []
	for story in _stories:
		headlines.append(str(story.get("headline", "")))
	_check("mutual collapse story emitted",
		headlines.has("MUTUAL COLLAPSE"))
	_check("war collapse story emitted",
		headlines.has("WAR COLLAPSE"))
	_check("conquest story emitted",
		headlines.has("CONQUEST"))

	# Jeremy 2026-10-06 launch readiness (gate 4): policies/festival
	# stories carried emoji into the phone newspaper (no emoji fallback
	# on the article card -> tofu on iPhone). The sanitizer enforces the
	# standing glyph-free rule at publish time.
	_check("sanitize: crown headline",
		SimGazette.sanitize_story_text("\uD83D\uDC51 HUMANS PROCLAIMED!")
			== "HUMANS PROCLAIMED!")
	_check("sanitize: anarchy headline",
		SimGazette.sanitize_story_text("\uD83D\uDD25 ANARCHY!")
			== "ANARCHY!")
	_check("sanitize: trailing emoji body",
		SimGazette.sanitize_story_text(
			"FESTIVAL in Ogrehold! Pies! Dancing! \uD83C\uDF89")
			== "FESTIVAL in Ogrehold! Pies! Dancing!")
	_check("sanitize: whitespace collapsed",
		SimGazette.sanitize_story_text("War  \u2694  declared")
			== "War declared")
	_check("sanitize: ascii + common punctuation untouched",
		SimGazette.sanitize_story_text(
			"By Grimbel \u00B7 Day 12 \u2014 \u201cFine\u201d")
			== "By Grimbel \u00B7 Day 12 \u2014 \u201cFine\u201d")
	_check("sanitize: empty stays empty",
		SimGazette.sanitize_story_text("") == "")
	_check("sanitize: variation selector stripped",
		SimGazette.sanitize_story_text("Peace \u2696\uFE0F now")
			== "Peace now")

	# Live: a policies-style emoji story through publish_story comes out
	# glyph-free on the bus AND in the stored/newspaper feed.
	var w3 := _new_world()
	var gs3: GameState = w3["gs"]
	var court := SimRoyalCourt.new(gs3)
	_stories.clear()
	var pub: Dictionary = court.publish_story(
		"\uD83D\uDC51 GNOMES PROCLAIMED!",
		"One crown, one head. Very long game. \uD83D\uDC51", "court")
	_check("publish_story: stored headline glyph-free",
		not _has_glyph(str(pub.get("headline", ""))))
	_check("publish_story: stored body glyph-free",
		not _has_glyph(str(pub.get("body", ""))))
	_check("publish_story: headline text kept",
		str(pub.get("headline", "")) == "GNOMES PROCLAIMED!")
	var emitted_ok := false
	for story in _stories:
		if str(story.get("headline", "")) == "GNOMES PROCLAIMED!" \
				and not _has_glyph(str(story.get("body", ""))):
			emitted_ok = true
	_check("publish_story: emitted story glyph-free", emitted_ok)
	var feed: Array = court.news_feed()
	var feed_ok := false
	for s in feed:
		if str(s.get("headline", "")) == "GNOMES PROCLAIMED!":
			feed_ok = not _has_glyph(str(s.get("story", "")))
	_check("publish_story: news_feed story glyph-free", feed_ok)
	gs3.free()

	(w1["gs"] as GameState).free()
	gs2.free()
	print("=== %d passed, %d failed ===" % [_passed, _failed])
	for f: String in _failures:
		print("  FAIL: ", f)
	quit(1 if _failed > 0 else 0)
