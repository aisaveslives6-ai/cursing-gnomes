class_name ResRateSampler
extends RefCounted
## Cursing Gnomes — rolling per-minute net income sampler.
##
## HTML source of truth (build-staging/fix79/index.html): the Resource
## Management panel samples stockpiles once per second into a rolling buffer
## ("Rolling per-minute net income sampler — honest stockpile deltas, zero
## changes to the economy itself") and shows "+2.5/min" style net rates
## computed from (latest - base) / minutes over a window of up to 45 seconds
## (base = oldest sample still inside the window, minimum 0.25 minutes).
##
## This is a Godot port of that exact model: pure math, no rendering, no sim
## changes — the economy itself is untouched. The HUD feeds it snapshots of
## the player faction's stockpiles and asks for per-minute rates to display.
##
## No emoji in output: rates format as "+2.5/min" / "-3.0/min" ASCII only
## (resource emoji render as tofu boxes on Jeremy's iPhone — 2026-10-03).


## HTML-verbatim constants.
const SAMPLE_INTERVAL_MS := 1000   # one sample per second max
const WINDOW_MS := 45000           # rate window: up to 45 seconds back
const MAX_SAMPLES := 100           # rolling buffer cap
const MIN_MINS := 0.25             # rate divisor never smaller than this

var _buf: Array = []          # [{t: int (ms), amounts: {res: float}}]
var _last_sample_ms: int = -1


## Records a stockpile snapshot if SAMPLE_INTERVAL_MS elapsed since the last.
## `amounts` maps resource name -> float. Returns true when sampled.
func sample(amounts: Dictionary, now_ms: int) -> bool:
	if _last_sample_ms >= 0 and now_ms - _last_sample_ms < SAMPLE_INTERVAL_MS:
		return false
	_last_sample_ms = now_ms
	_buf.append({"t": now_ms, "amounts": amounts.duplicate()})
	while _buf.size() > MAX_SAMPLES:
		_buf.pop_front()
	return true


## Per-minute net rate per resource, HTML resRatesPerMin() parity.
## With fewer than 2 samples there is no delta: all rates are 0.0.
func rates_per_min(resources: Array) -> Dictionary:
	var out: Dictionary = {}
	for r: String in resources:
		out[r] = 0.0
	if _buf.size() < 2:
		return out
	var latest: Dictionary = _buf[_buf.size() - 1]
	var base: Dictionary = _buf[0]
	for i: int in range(_buf.size() - 1, -1, -1):
		if int(latest["t"]) - int(_buf[i]["t"]) >= WINDOW_MS:
			base = _buf[i]
			break
	var latest_amounts: Dictionary = latest["amounts"]
	var base_amounts: Dictionary = base["amounts"]
	var mins: float = maxf(MIN_MINS,
		float(int(latest["t"]) - int(base["t"])) / 60000.0)
	for r: String in resources:
		out[r] = (float(latest_amounts.get(r, 0.0))
			- float(base_amounts.get(r, 0.0))) / mins
	return out


## HTML rateFmt parity: "+2.5/min", "-3.0/min". ASCII only, no glyphs.
static func format_rate(v: float) -> String:
	var sign: String = "+" if v >= 0.0 else ""
	return "%s%.1f/min" % [sign, v]
