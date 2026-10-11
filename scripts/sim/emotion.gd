class_name SimEmotion
extends RefCounted
## Cursing Gnomes — NPC emotion system (Milestone 5: minds).
##
## NPCs feel things about what happens to them: grief when a friend dies,
## fear or anger when attacked, joy when healed. One dominant emotion at a
## time with an intensity and a time-to-live; it decays back to neutral.
## Emotion colors dialogue tone and — combined with the bravery trait —
## decides whether a scared NPC fights or flees.
##
## Emotion state lives on the unit record ("emotion" dict). Pure logic —
## no rendering, no input, no audio.


const EMOTIONS: Array[String] = ["neutral", "happy", "sad", "angry", "scared", "proud", "disgusted"]

## event -> {emotion, intensity, ttl seconds}.
const EVENT_MAP := {
	"friend_died": {"emotion": "sad", "intensity": 0.7, "ttl": 90.0},
	"attacked": {"emotion": "scared", "intensity": 0.6, "ttl": 20.0},
	"helped": {"emotion": "happy", "intensity": 0.5, "ttl": 30.0},
	"healed": {"emotion": "happy", "intensity": 0.4, "ttl": 25.0},
	"insulted": {"emotion": "angry", "intensity": 0.6, "ttl": 40.0},
	"praised": {"emotion": "proud", "intensity": 0.6, "ttl": 40.0},
	"monster": {"emotion": "scared", "intensity": 0.9, "ttl": 30.0},
	"disaster": {"emotion": "scared", "intensity": 0.8, "ttl": 30.0},
	# Jeremy 2026-10-04: THE NASTY MONASTERY — Father Filthwick's outbursts
	# disgust nearby NPCs.
	"grossed_out": {"emotion": "disgusted", "intensity": 0.7, "ttl": 45.0},
	"mocked": {"emotion": "sad", "intensity": 0.4, "ttl": 30.0},
	"victory": {"emotion": "proud", "intensity": 0.7, "ttl": 45.0},
	"ate_well": {"emotion": "happy", "intensity": 0.35, "ttl": 40.0},
	# Jeremy 2026-10-09 (hearsay flesh-out): famine gossip — the
	# starving despair (sad, hard), a distinct event from mourning.
	"starving": {"emotion": "sad", "intensity": 0.8, "ttl": 60.0},
	# Jeremy 2026-10-09 (hearsay flesh-out): denied peace feelers — the
	# doves' despair and allies' sympathy (sad, no one's fault to mourn).
	"dismayed": {"emotion": "sad", "intensity": 0.5, "ttl": 40.0},
	# Jeremy 2026-10-09 (hearsay flesh-out): the turning seasons — spring's
	# thaw and autumn's harvest lift the realm (happy); high summer makes
	# idle soldiers restless (angry, mild — heat, not war).
	"cheerful": {"emotion": "happy", "intensity": 0.45, "ttl": 40.0},
	"grumpy": {"emotion": "angry", "intensity": 0.4, "ttl": 40.0},
	# Jeremy 2026-10-09 (hearsay flesh-out): court filings — the
	# petitioner stood up and asked. Hope, not pride: the crown hasn't
	# answered yet.
	"hopeful": {"emotion": "happy", "intensity": 0.4, "ttl": 35.0},
	# Jeremy 2026-10-04: likes/dislikes engine — the ruler said something
	# about a topic the NPC loved or hated.
	"liked_topic": {"emotion": "happy", "intensity": 0.5, "ttl": 30.0},
	"disliked_topic": {"emotion": "angry", "intensity": 0.6, "ttl": 40.0},
}


## True when `event` is a known EVENT_MAP key. Validate before notify,
## or use in tests auditing call sites (see test_emotion_audit.gd).
static func has_event(event: String) -> bool:
	return EVENT_MAP.has(event)


func ensure(unit: Dictionary) -> Dictionary:
	if not unit.has("emotion"):
		unit["emotion"] = {"name": "neutral", "intensity": 0.0, "ttl": 0.0}
	return unit["emotion"]


## React to an event. Stronger events override weaker ones; equal events
## refresh. Unknown events are still IGNORED (never crash on a typo) but
## now push_error LOUDLY: the "scared"/"proud" silent no-ops of 2026-10-09
## proved silent ignores hide real bugs for months. EVENT names are keys
## of EVENT_MAP; EMOTION names ("scared", "proud", ...) are NOT events.
func notify(unit: Dictionary, event: String, intensity_scale: float = 1.0) -> void:
	if not has_event(event):
		push_error("SimEmotion.notify: unknown event '%s' — ignored; not an EVENT_MAP key" % event)
		return
	var def: Dictionary = EVENT_MAP[event]
	# "attacked" on a brave NPC becomes anger, not fear.
	var emo: String = String(def["emotion"])
	if event == "attacked" and SimPersonality.stands_ground(unit):
		emo = "angry"
	# Proud NPCs take mockery as insult, not sadness.
	if event == "mocked" and SimPersonality.trait_of(unit, "proud") >= 0.6:
		emo = "angry"
	var e: Dictionary = ensure(unit)
	var new_intensity: float = clampf(float(def["intensity"]) * intensity_scale, 0.0, 1.0)
	if new_intensity >= float(e.get("intensity", 0.0)):
		e["name"] = emo
		e["intensity"] = new_intensity
		e["ttl"] = float(def["ttl"])
	else:
		# Weaker event: just refresh the timer a little.
		e["ttl"] = maxf(float(e.get("ttl", 0.0)), float(def["ttl"]) * 0.25)


## Decay the current emotion. Returns the dominant emotion name.
func tick(unit: Dictionary, delta: float) -> String:
	var e: Dictionary = ensure(unit)
	var ttl: float = float(e.get("ttl", 0.0)) - delta
	if ttl <= 0.0:
		e["name"] = "neutral"
		e["intensity"] = 0.0
		e["ttl"] = 0.0
		return "neutral"
	e["ttl"] = ttl
	# Intensity fades proportionally with remaining time.
	e["intensity"] = clampf(float(e.get("intensity", 0.0)) - delta * 0.02, 0.0, 1.0)
	return String(e.get("name", "neutral"))


## Dominant emotion name without ticking.
func dominant(unit: Dictionary) -> String:
	return String(ensure(unit).get("name", "neutral"))


## Dialogue tone from emotion: cheerful | grumpy | fearful | flat.
func tone(unit: Dictionary) -> String:
	match dominant(unit):
		"happy", "proud":
			return "cheerful"
		"angry", "disgusted":
			return "grumpy"
		"scared", "sad":
			return "fearful"
	return "flat"
