extends SceneTree
## Cursing Gnomes — emotion event audit (deep-work 2026-10-09).
##
## Bug class: SimEmotion.notify takes an EVENT_MAP key ("disaster"), but
## callers passed EMOTION names ("scared" x3, "proud" x1) — notify silently
## ignored unknown events, so gossip never applied the intended emotion.
## All four instances lived in scripts/sim/hearsay.gd; three were fixed
## 2026-10-09 before this suite, the fourth ("proud" in _wall_reaction) by
## the staged hardening this suite ships with.
##
## This suite pins the fix two ways:
##  1. Runtime contract: every EVENT_MAP key round-trips through notify;
##     has_event() accepts keys and rejects emotion names; unknown events
##     stay ignored (no crash) but loud.
##  2. Source audit: every literal event string passed to _react_apply()
##     or an emotion *.notify() anywhere under res://scripts, plus every
##     SimHearsay KIND_EMOTION value, must be an EVENT_MAP key. A future
##     typo fails HERE instead of silently no-op'ing in the game.
##
## Run:
##   ~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64 --headless \
##     --path ~/workspace/godot-cursing-gnomes -s res://tests/test_emotion_audit.gd
##
## Exit code 0 = all passed, 1 = any failure. No rendering, no input, no audio.


var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _check(test_name: String, cond: bool) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)
		print("  FAIL: ", test_name)


func _new_unit() -> Dictionary:
	# Traitless-but-explicit: brave 0.0 (attacked -> scared, not angry),
	# proud 0.0 (mocked -> sad, not angry). trait_of defaults to 0.5 when
	# absent, which would flip the attacked override — so set them.
	return {"id": 1, "faction": "gnome",
		"mind": {"traits": {"brave": 0.0, "proud": 0.0}}}


func _test_event_map_roundtrip() -> void:
	var emo := SimEmotion.new()
	for event in SimEmotion.EVENT_MAP.keys():
		var u := _new_unit()
		emo.notify(u, String(event))
		var want: String = String(SimEmotion.EVENT_MAP[event]["emotion"])
		_check("roundtrip: '%s' -> '%s'" % [event, want],
			String(u.get("emotion", {}).get("name", "")) == want)


func _test_personality_overrides_survive() -> void:
	var emo := SimEmotion.new()
	var brave := _new_unit()
	brave["mind"]["traits"]["brave"] = 1.0
	emo.notify(brave, "attacked")
	_check("override: brave unit attacked -> angry",
		String(brave["emotion"]["name"]) == "angry")
	var proud := _new_unit()
	proud["mind"]["traits"]["proud"] = 1.0
	emo.notify(proud, "mocked")
	_check("override: proud unit mocked -> angry",
		String(proud["emotion"]["name"]) == "angry")


func _test_has_event_contract() -> void:
	for event in SimEmotion.EVENT_MAP.keys():
		_check("has_event('%s')" % event, SimEmotion.has_event(String(event)))
	# Emotion NAMES are not events — the exact confusion this suite guards.
	for emo_name in ["neutral", "happy", "sad", "angry", "scared", "proud", "disgusted"]:
		_check("not has_event('%s')" % emo_name, not SimEmotion.has_event(emo_name))


func _test_unknown_event_ignored_not_crash() -> void:
	var emo := SimEmotion.new()
	var u := _new_unit()
	emo.notify(u, "disaster")
	# Dynamic string (not a literal) so the source audit below skips it.
	emo.notify(u, "audit_probe_" + "bogus_event")
	_check("unknown event: no crash, emotion kept",
		String(u["emotion"]["name"]) == "scared")


func _test_kind_emotion_values() -> void:
	for kind in SimHearsay.KIND_EMOTION.keys():
		var ev := String(SimHearsay.KIND_EMOTION[kind])
		_check("KIND_EMOTION['%s']='%s' is an EVENT_MAP key" % [kind, ev],
			SimEmotion.has_event(ev))


## --- source audit -----------------------------------------------------

func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open(dir_path)
	if da == null:
		return out
	da.list_dir_begin()
	var n := da.get_next()
	while n != "":
		if n != "." and n != "..":
			var p := dir_path + "/" + n
			if da.current_is_dir():
				out.append_array(_gd_files(p))
			elif n.ends_with(".gd"):
				out.append(p)
		n = da.get_next()
	da.list_dir_end()
	return out


## Split the top-level comma args of the call whose '(' is at `start`.
func _call_args(content: String, start: int) -> Array[String]:
	var args: Array[String] = []
	var depth := 0
	var cur := ""
	var i := start
	while i < content.length():
		var ch := content.substr(i, 1)
		if ch == "(":
			depth += 1
			if depth > 1:
				cur += ch
		elif ch == ")":
			depth -= 1
			if depth == 0:
				args.append(cur.strip_edges())
				return args
			cur += ch
		elif ch == "," and depth == 1:
			args.append(cur.strip_edges())
			cur = ""
		else:
			cur += ch
		i += 1
	return []


var _lit_re: RegEx = null


func _as_literal(arg: String) -> String:
	if _lit_re == null:
		_lit_re = RegEx.new()
		_lit_re.compile("^\"([A-Za-z_][A-Za-z0-9_]*)\"$")
	var m := _lit_re.search(arg)
	if m == null:
		return ""
	return m.get_string(1)


func _line_of(content: String, idx: int) -> int:
	return content.substr(0, idx).count("\n") + 1


## Audit literal event args of `func_name(` calls at `arg_idx`, requiring
## the receiver (for dotted calls) to look like an emotion handle.
func _audit_calls(content: String, path: String, func_name: String,
		arg_idx: int, need_emo_receiver: bool) -> void:
	var search_from := 0
	while true:
		var idx := content.find(func_name + "(", search_from)
		if idx == -1:
			return
		if need_emo_receiver:
			# Receiver = identifier chain immediately before "func_name(".
			var r_end := idx
			var r_start := r_end - 1
			while r_start >= 0:
				var rc := content.substr(r_start, 1)
				if rc == "." or rc == "_" or (rc >= "a" and rc <= "z") \
						or (rc >= "A" and rc <= "Z") or (rc >= "0" and rc <= "9"):
					r_start -= 1
				else:
					break
			var receiver := content.substr(r_start + 1, r_end - r_start - 1).to_lower()
			if not receiver.contains("emo"):
				search_from = idx + 1
				continue
		var args := _call_args(content, idx + func_name.length())
		if args.size() > arg_idx:
			var lit := _as_literal(args[arg_idx])
			if lit != "":
				_check("audit %s:%d '%s' is an EVENT_MAP key" % [path, _line_of(content, idx), lit],
					SimEmotion.has_event(lit))
		search_from = idx + 1


func _test_source_audit() -> void:
	for path in _gd_files("res://scripts"):
		if path.ends_with("test_emotion_audit.gd"):
			continue  # the auditor, not the audited
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var content := f.get_as_text()
		f.close()
		_audit_calls(content, path, "_react_apply", 3, false)
		_audit_calls(content, path, "notify", 1, true)


func _initialize() -> void:
	_test_event_map_roundtrip()
	_test_personality_overrides_survive()
	_test_has_event_contract()
	_test_unknown_event_ignored_not_crash()
	_test_kind_emotion_values()
	_test_source_audit()
	print("test_emotion_audit: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		quit(1)
	else:
		quit(0)
