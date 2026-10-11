class_name Diagnostics
extends Node
## Cursing Gnomes — opt-in diagnostics (HTML WATCHDOG-77 telemetry parity).
##
## Consent-gated: NOTHING is collected, queued, or shared unless the player
## turns "Share Diagnostics" ON in Settings. When on, the game collects:
##   - crash/error notes (via record())
##   - FPS + performance samples (auto aggregate every 5 minutes, like HTML)
##   - hardware info (OS, CPU count, screen, GPU, engine build)
##   - which graphics tier was active, what the game was doing (context)
## Plus a random anonymous player ID generated on-device (UUID v4 shape) —
## never derived from hardware, email, or anything identifiable. No names,
## no email, no personal data, no tracking.
##
## "Send Diagnostics" builds a report and opens the OS share sheet on web
## exports (navigator.share) — the player chooses where it goes, matching
## the HTML settings text ("You choose where it goes"). Everywhere else
## the report is copied to the clipboard.
##
## DELIBERATE PARITY GAPS (see report):
## - The HTML also auto-POSTed queued reports to a hardcoded webhook.site
##   endpoint. The Godot port does NOT auto-upload anywhere: the endpoint
##   UUID is baked into the HTML and can't be verified as Jeremy's, so
##   automatic exfiltration is out. Sharing is always an explicit,
##   user-chosen action.
## - The HTML showed a first-boot consent dialog. The Godot port relies on
##   the Settings opt-in row instead (less intrusive; same consent model).


signal diagnostics_sent(method: String)  # "share" | "clipboard"

const QUEUE_PATH := "user://diagnostics_queue.json"
const MAX_QUEUE := 10  # HTML parity
const AGGREGATE_SECONDS := 300.0  # HTML enqueued a perf aggregate every 5 min

var enabled := false

var _agg_acc := 0.0
var _fps_acc := 0.0
var _fps_n := 0


func _ready() -> void:
	add_to_group("cg_diagnostics")
	set_process(true)


## Apply the Settings toggle. Turning OFF clears the queue (HTML parity:
## "Diagnostics sharing OFF. Queue cleared.").
func configure(p_enabled: bool) -> void:
	var was := enabled
	enabled = p_enabled
	if was and not enabled:
		clear_queue()
	if enabled:
		ensure_player_id()


func _process(delta: float) -> void:
	if not enabled:
		return
	_fps_acc += float(Engine.get_frames_per_second())
	_fps_n += 1
	_agg_acc += delta
	if _agg_acc >= AGGREGATE_SECONDS:
		_agg_acc = 0.0
		var avg := 0.0
		if _fps_n > 0:
			avg = _fps_acc / float(_fps_n)
		_fps_acc = 0.0
		_fps_n = 0
		enqueue("perf-aggregate", {"fps_avg": snappedf(avg, 0.1)})


## Record a crash/error note. Queued only when enabled.
func record(kind: String, message: String, context: Dictionary = {}) -> void:
	if not enabled:
		return
	enqueue("error", {"kind": kind, "message": message,
		"context": context})


## Queue a typed report (bounded; survives restarts via user://).
func enqueue(report_type: String, detail: Dictionary = {}) -> void:
	if not enabled:
		return
	var report := collect_report(report_type)
	for k: String in detail.keys():
		report[k] = detail[k]
	var q := load_queue()
	q.append(report)
	while q.size() > MAX_QUEUE:
		q.pop_front()
	save_queue(q)


## Build one report envelope (HTML baseReport parity).
func collect_report(report_type: String) -> Dictionary:
	var settings := GraphicsTiers.read_user_settings()
	return {
		"type": report_type,
		"at": Time.get_datetime_string_from_system(true, true),
		"build": Config.GAME_VERSION,
		"player_id": ensure_player_id(),
		"hw": hardware_info(),
		"tier": String(settings.get("graphics", "auto")),
		"fps": int(Engine.get_frames_per_second()),
	}


## Hardware fingerprint — collected once per report (HTML hardwareInfo parity).
static func hardware_info() -> Dictionary:
	var h := {"os": OS.get_name(), "web": OS.has_feature("web"),
		"mobile": OS.has_feature("mobile"),
		"processors": OS.get_processor_count(),
		"engine": String(Engine.get_version_info().get("string", ""))}
	if RenderingServer != null:
		h["gpu"] = RenderingServer.get_video_adapter_name()
	if DisplayServer.get_name() != "headless":
		var vs := DisplayServer.window_get_size()
		h["screen_w"] = int(vs.x)
		h["screen_h"] = int(vs.y)
	# Static memory in KB (HTML read the JS heap; this is the honest analog).
	h["mem_static_kb"] = int(
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0)
	return h


## Random anonymous player ID (HTML getPlayerId parity: UUID v4 shape,
## generated once, stored locally, never derived from anything identifiable).
static func make_uuid() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	s += _hex(rng, 8) + "-"
	s += _hex(rng, 4) + "-"
	s += "4" + _hex(rng, 3) + "-"
	s += ["8", "9", "a", "b"][rng.randi_range(0, 3)] + _hex(rng, 3) + "-"
	s += _hex(rng, 12)
	return s


static func _hex(rng: RandomNumberGenerator, n: int) -> String:
	var digits := "0123456789abcdef"
	var s := ""
	for i in n:
		s += digits[rng.randi_range(0, 15)]
	return s


## Lazily generate + persist the anonymous ID (settings.json).
static func ensure_player_id() -> String:
	var settings := GraphicsTiers.read_user_settings()
	var pid := String(settings.get("diagnostics_id", ""))
	if pid != "":
		return pid
	pid = make_uuid()
	settings["diagnostics_id"] = pid
	var f := FileAccess.open(GraphicsTiers.SETTINGS_PATH,
		FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(settings))
		f.close()
	return pid


## Human-readable report for the share sheet / clipboard.
func build_share_text() -> String:
	var lines: Array[String] = []
	lines.append("Cursing Gnomes diagnostics (build %s)" % Config.GAME_VERSION)
	lines.append("anonymous player id: " + ensure_player_id())
	lines.append("--- hardware ---")
	var hw := hardware_info()
	var keys: Array = hw.keys()
	keys.sort()
	for k: String in keys:
		lines.append("%s: %s" % [k, str(hw[k])])
	var q := load_queue()
	lines.append("--- queued reports (%d) ---" % q.size())
	for r: Variant in q:
		lines.append(JSON.stringify(r))
	lines.append("--- end (no personal data) ---")
	return "\n".join(lines)


## Share now. Returns "share" (share sheet), "clipboard", or "" when
## disabled / nothing to send. Never sends automatically anywhere.
func send_now() -> String:
	if not enabled:
		return ""
	var text := build_share_text()
	if OS.has_feature("web") and _web_share(text):
		diagnostics_sent.emit("share")
		return "share"
	DisplayServer.clipboard_set(text)
	diagnostics_sent.emit("clipboard")
	return "clipboard"


## navigator.share via JavaScriptBridge (web exports only). The call happens
## inside the settings button's tap handler, so the user-gesture requirement
## is satisfied. Fire-and-forget: returns whether the share was attempted.
func _web_share(text: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var payload := JSON.stringify(text)  # valid JS string literal
	var js := "(function(){try{if(navigator.share){navigator.share(" \
		+ "{title:'Cursing Gnomes diagnostics',text:" + payload + "})" \
		+ ".catch(function(){});return true;}return false;}" \
		+ "catch(e){return false;}})()"
	var res: Variant = JavaScriptBridge.eval(js, true)
	return res == true


func load_queue() -> Array:
	var q: Array = []
	if not FileAccess.file_exists(QUEUE_PATH):
		return q
	var f := FileAccess.open(QUEUE_PATH, FileAccess.READ)
	if f == null:
		return q
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		q = parsed
	return q


func save_queue(q: Array) -> void:
	var f := FileAccess.open(QUEUE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(q.slice(-MAX_QUEUE)))
	f.close()


func clear_queue() -> void:
	save_queue([])
