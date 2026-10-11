class_name ChatterDirector
extends RefCounted
## Cursing Gnomes — "Overheard" policy: which NPC speech reaches the
## subtitle ticker.
##
## Jeremy 2026-10-05 ordered ALL speech/thought bubbles removed (they
## blocked the battle view). The sim still emits bus.unit_said from 23
## sites — NPC chatter, AI director announcements, army stance shouts,
## ferry calls, hero adventure dialogue — and world._on_unit_said was an
## explicit no-op, so the living world's voice was mute. This director
## decides what the subtitle ticker shows instead. It is NOT a bubble:
## one slim line of HUD chrome above the bottom bar, never over units.
##
## Policy (tuned so the ticker feels like overhearing, not a firehose):
##   - Camera proximity: only speech within RADIUS px of the camera
##     center is shown. The world around you talks; a war three towns
##     away does not subtitle at you. System shouts (unit_id -1, e.g.
##     army stance changes) carry no position and always pass the cull —
##     they are player-directed announcements.
##   - Throttle: at most one line per COOLDOWN seconds.
##   - Queue: up to MAX_QUEUE lines wait their turn; overflow drops the
##     oldest (fresh speech beats stale).
## Pure logic — no rendering, no input, no audio. Fully headless-testable.


## 850px: roughly the on-screen world at the default zoom — if you can
## see the gnome, you can hear the gnome.
const RADIUS := 850.0
## One subtitle every 2.2s: readable without becoming a crawl.
const COOLDOWN := 2.2
## Two queued lines max; the third arrival evicts the oldest.
const MAX_QUEUE := 2


var _cool := 0.0
var _queue: Array = []  # Array[Dictionary] {speaker, color, text}


## Offer one spoken line. has_pos=false (system shouts) skips the
## proximity cull. Returns true if the line was accepted (shown now or
## queued), false if culled or dropped.
func offer(has_pos: bool, pos: Vector2, cam: Vector2, speaker: String,
		color: Color, text: String) -> bool:
	var clean := text.strip_edges()
	if clean.is_empty():
		return false
	if has_pos and pos.distance_to(cam) > RADIUS:
		return false
	var line := {"speaker": speaker.strip_edges(), "color": color, "text": clean}
	if _cool <= 0.0 and _queue.is_empty():
		_queue.append(line)
		_cool = COOLDOWN
		return true
	if _queue.size() >= MAX_QUEUE:
		_queue.pop_front()
	_queue.append(line)
	return true


## Advance the clock. Returns the next line to display ({} when none is
## due). Call every frame from the world _process.
func tick(delta: float) -> Dictionary:
	if _cool > 0.0:
		_cool = maxf(0.0, _cool - delta)
	if _queue.is_empty():
		return {}
	if _cool > 0.0:
		return {}
	_cool = COOLDOWN
	return _queue.pop_front()


## Lines currently waiting (shown + queued).
func pending() -> int:
	return _queue.size()


## Drop everything (new game, load, teardown).
func clear() -> void:
	_queue.clear()
	_cool = 0.0


## Test hook: seconds until the next line may display.
func cooldown_left() -> float:
	return _cool
