class_name SimNewsTrivia
extends RefCounted
## Cursing Gnomes — Gazette news-desk: trivia aggregation + crown-works beat.
##
## HTML parity (fix79/index.html):
##   - NEWS_TRIVIA_BUCKETS (Candidate11 editorial desk): the paper headlines
##     big deals only. Trivia items are tallied per bucket per game day; a
##     bucket crossing its threshold escalates into ONE aggregated story
##     with a verbatim sample quote, then the tally resets. Buckets whose
##     underlying feed has no port counterpart stay dormant — they never
##     fire spuriously.
##   - 'ROYAL WORKS': the crown orders walls raised around named regions
##     (HTML wall-policy "Raise" answer -> "Walls ordered!").
##
## Pure sim: listens on the event bus, publishes through the court
## (guarded duck-typing, same as towns.gd). Owned by SimRoyalCourt.

## [key, regex, threshold, headline, body_fmt, urgent, kind] — HTML-verbatim.
const BUCKETS := [
	{"key": "depot", "re": "parked .* at depot", "n": 4,
		"head": "DEPOT LOGJAM",
		"story": "%d war machines parked at depots this week. Latest report: \"%s\"",
		"urgent": false, "kind": "court"},
	{"key": "raidprobe",
		"re": "raiders? (spotted|probing|sighted)|bandits? (spotted|sighted)|probed",
		"n": 3, "head": "RAIDERS PROBE OUR BORDERS",
		"story": "Raiders spotted near our lands %d times this week. Latest report: \"%s\"",
		"urgent": true, "kind": "war"},
	{"key": "train", "re": "training .*\\(\\d+/\\d+\\)|completed training", "n": 5,
		"head": "RECRUITS MUSTER",
		"story": "%d training rotations completed this week. Latest report: \"%s\"",
		"urgent": false, "kind": "court"},
	{"key": "pettycrime", "re": "pickpocket", "n": 3,
		"head": "PETTY CRIME WAVE",
		"story": "%d pickpocketings reported this week. Latest report: \"%s\"",
		"urgent": false, "kind": "crime"},
	{"key": "build", "re": "finished a ", "n": 4,
		"head": "BUILDING BOOM",
		"story": "%d buildings completed this week. Latest report: \"%s\"",
		"urgent": false, "kind": "court"},
	{"key": "grownup", "re": "grown up|ready to work", "n": 5,
		"head": "A GENERATION RISES",
		"story": "%d youngsters came of age and joined the workforce this week. Latest report: \"%s\"",
		"urgent": false, "kind": "court"},
]

var _gs  # GameState (untyped: avoids a cyclic class reference)
var _counts: Dictionary = {}  # bucket key -> {n, day, sample}
var _rx_cache: Dictionary = {}


func _init(game_state) -> void:
	_gs = game_state
	if _gs == null or _gs.get("bus") == null:
		return
	_gs.bus.gazette_story.connect(_on_story)
	_gs.bus.wall_answer.connect(_on_wall_answer)
	_gs.bus.day_changed.connect(_on_day)


func _rx_for(pattern: String) -> RegEx:
	if not _rx_cache.has(pattern):
		var rx := RegEx.new()
		rx.compile("(?i)" + pattern)
		_rx_cache[pattern] = rx
	return _rx_cache[pattern]


func _court():
	if _gs == null:
		return null
	var court = _gs.get("court_sys")
	if court == null or not court.has_method("publish_story"):
		return null
	return court


## One trivia report crossed the bus: tally it into matching buckets.
func _on_story(story: Dictionary) -> void:
	if _gs == null:
		return
	var head := String(story.get("headline", ""))
	# Never aggregate our own aggregated stories (HTML routes them around
	# the gate; here the headline guard does the same job).
	for b in BUCKETS:
		if head == String(b["head"]):
			return
	var text := head + " " + str(story.get("body", story.get("story", "")))
	var day: int = int(_gs.get("day_number"))
	for b in BUCKETS:
		var rx: RegEx = _rx_for(String(b["re"]))
		if rx.search(text) == null:
			continue
		_tally(b, text, day)


## Direct trivia feed (Jeremy 2026-10-07, wake rapid lane): sim systems
## report notable events here when a full bus.gazette_story would be
## wrong — e.g. building completions, where a per-farm bus story would
## mint a rumor-mill whisper for every farm (hearsay._on_story seeds one
## rumor per headline) and pop no toast anyway (not urgent). Tally and
## aggregation behavior are identical to bus-fed items; only the
## AGGREGATED story reaches the bus/Chronicle/mill, via
## court.publish_story as usual.
func report(headline: String, body: String, kind: String = "court") -> void:
	_on_story({"headline": headline, "body": body, "kind": kind})


## HTML tally: per-day counts; the first matching report of the day is the
## verbatim sample (90 chars). Crossing the threshold publishes one
## aggregated story and resets the bucket.
func _tally(b: Dictionary, text: String, day: int) -> void:
	var key := String(b["key"])
	var agg: Dictionary = _counts.get(key, {})
	if int(agg.get("day", -1)) != day:
		agg = {"n": 0, "day": day, "sample": ""}
	agg["n"] = int(agg["n"]) + 1
	if String(agg.get("sample", "")) == "":
		agg["sample"] = text.strip_edges().substr(0, 90)
	_counts[key] = agg
	if int(agg["n"]) < int(b["n"]):
		return
	_counts[key] = {"n": 0, "day": day, "sample": ""}
	var court = _court()
	if court == null:
		return
	var story: Dictionary = court.publish_story(
		String(b["head"]),
		String(b["story"]) % [int(agg["n"]), String(agg["sample"])],
		String(b["kind"]))
	if bool(b.get("urgent", false)) and story is Dictionary:
		story["urgent"] = true


## Per-day tallies reset at dawn (HTML: agg.day !== day -> reset).
func _on_day(_day: int, _is_night: bool) -> void:
	_counts.clear()


## HTML wall-policy "Raise": the crown orders the works.
func _on_wall_answer(region_name: String, raise: bool) -> void:
	if not raise:
		return
	var court = _court()
	if court == null:
		return
	court.publish_story("🧱 ROYAL WORKS",
		"The crown orders walls raised around %s." % region_name, "court")
