class_name SimMood
extends RefCounted
## Cursing Gnomes — persistent NPC mood system (Jeremy 2026-10-04).
##
## Moods are LONG-LIVED emotional states (hours/days of game time) as
## opposed to momentary emotions (SimEmotion: seconds of real time).
## An NPC can be sad about a dead friend for days while individual
## emotions flare and fade on top of it.
##
## State lives on the unit record:
##   unit["mood"] = {"name": "neutral", "intensity": 0.0}
##
## What moves moods:
##   - Strong emotions feed in: repeated anger hardens into an angry mood
##     (feed_from_emotion, called from SimMind.tick_unit).
##   - Events nudge directly: praised/insulted/friend died (nudge).
##   - Likes/dislikes reactions nudge (SimLikesDislikes hooks this).
##   - Personality drifts the baseline: friendly NPCs drift happy,
##     violent ones drift angry (drift_from_traits).
## Moods decay slowly toward neutral — nothing lasts forever.
##
## Moods color everything outward-facing: hearsay telling, Messenger
## tone, and the 100-replies-per-mood pools in SimMoodReplies.
##
## Pure logic — no rendering, no input, no audio.


const MOODS: Array[String] = ["neutral", "happy", "sad", "angry", "scared", "proud", "disgusted"]

## Emotion intensity needed before it starts hardening into a mood.
const FEED_THRESHOLD := 0.55
## How much of an emotion's intensity transfers to the mood per feed.
const FEED_RATE := 0.35
## Mood intensity lost per second of mind tick. ~0.002 = a full mood
## takes about eight minutes of real play to fade. Longer than any
## emotion's TTL; shorter than a grudge.
const DECAY_RATE := 0.002
## Below this intensity the mood is effectively neutral.
const NEUTRAL_FLOOR := 0.05


func ensure(unit: Dictionary) -> Dictionary:
	if not unit.has("mood") or not (unit["mood"] is Dictionary):
		unit["mood"] = {"name": "neutral", "intensity": 0.0}
	return unit["mood"]


## Current dominant mood name. "neutral" when intensity is spent.
func dominant(unit: Dictionary) -> String:
	var m: Dictionary = ensure(unit)
	if float(m.get("intensity", 0.0)) <= NEUTRAL_FLOOR:
		return "neutral"
	return String(m.get("name", "neutral"))


## Current mood intensity (0.0-1.0).
func intensity(unit: Dictionary) -> float:
	return clampf(float(ensure(unit).get("intensity", 0.0)), 0.0, 1.0)


## Push the mood toward mood_name by amount (0.0-1.0). Same mood
## strengthens; a different STRONG mood displaces a weak one; a weak
## different mood just takes the edge off the current one.
func nudge(unit: Dictionary, mood_name: String, amount: float) -> void:
	if not MOODS.has(mood_name) or mood_name == "neutral":
		return
	var m: Dictionary = ensure(unit)
	var cur: String = String(m.get("name", "neutral"))
	var cur_i: float = float(m.get("intensity", 0.0))
	amount = clampf(amount, 0.0, 1.0)
	if cur == mood_name:
		m["intensity"] = clampf(cur_i + amount, 0.0, 1.0)
	elif cur == "neutral" or amount >= cur_i:
		m["name"] = mood_name
		m["intensity"] = amount
	else:
		m["intensity"] = clampf(cur_i - amount * 0.5, 0.0, 1.0)
		if float(m["intensity"]) <= 0.0:
			m["name"] = "neutral"


## Strong momentary emotions harden into persistent moods. Call after
## the emotion tick — repeated anger becomes an angry mood, repeated
## grief becomes a sad one.
func feed_from_emotion(unit: Dictionary) -> void:
	var e: Dictionary = unit.get("emotion", {})
	var ename: String = String(e.get("name", "neutral"))
	var eint: float = float(e.get("intensity", 0.0))
	if ename == "neutral" or eint < FEED_THRESHOLD:
		return
	nudge(unit, ename, eint * FEED_RATE)


## Personality drifts the resting mood: friendly souls drift happy,
## violent ones drift angry, proud ones drift proud, cowards drift
## scared. Only pulls when no stronger mood holds. Call rarely
## (e.g. once per game day).
func drift_from_traits(unit: Dictionary, strength: float = 0.12) -> void:
	var m: Dictionary = ensure(unit)
	if float(m.get("intensity", 0.0)) > 0.4:
		return  # A real mood is holding; personality waits its turn.
	var best: String = "neutral"
	var best_score: float = 0.0
	var pulls := {
		"happy": SimPersonality.trait_of(unit, "friendly"),
		"angry": SimPersonality.trait_of(unit, "violent"),
		"proud": SimPersonality.trait_of(unit, "proud"),
		"scared": 1.0 - SimPersonality.trait_of(unit, "brave"),
	}
	for mood_name: String in pulls:
		var s: float = float(pulls[mood_name])
		if s > best_score:
			best_score = s
			best = mood_name
	if best != "neutral" and best_score >= 0.75:
		nudge(unit, best, strength)


## Slow decay toward neutral. Returns the resulting mood name.
func tick(unit: Dictionary, delta: float) -> String:
	var m: Dictionary = ensure(unit)
	var i: float = float(m.get("intensity", 0.0)) - delta * DECAY_RATE
	if i <= NEUTRAL_FLOOR:
		m["name"] = "neutral"
		m["intensity"] = 0.0
		return "neutral"
	m["intensity"] = i
	return String(m.get("name", "neutral"))


## Dialogue tone from mood (stronger/longer-lasting than the
## momentary emotion tone): cheerful | grumpy | fearful | flat.
func tone(unit: Dictionary) -> String:
	match dominant(unit):
		"happy", "proud":
			return "cheerful"
		"angry", "disgusted":
			return "grumpy"
		"scared", "sad":
			return "fearful"
	return "flat"
