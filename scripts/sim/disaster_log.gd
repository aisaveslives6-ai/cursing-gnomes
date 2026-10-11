class_name DisasterLog
extends RefCounted
## Cursing Gnomes — disaster tracking ledger (Jeremy 2026-10-04).
##
## Every disaster gets a full record: which towns it entered (with a
## timeline), who died and how, what military/citizen orders were issued,
## and how it ended. Feeds the Gazette's Disaster Desk and the phone
## calendar's disaster response panel.
##
## RECORD SCHEMA:
##   {id, kind, label, start_day, start_time, forecast_day (-1 if unplanned),
##    end_day, status ("active"|"left"|"slain"),
##    unit_ids: [monster unit ids], towns: [{town_id, name, faction, day}],
##    deaths: [{name, faction, job, cause, day}],
##    military_order: "ignore"|"attack"|"retreat",
##    citizen_order: "free"|"shelter", moons: int}
##
## DEATH CAUSES:
##   "slain"    — killed directly by the disaster (monster attack, fire)
##   "attacking"— died while attacking the disaster (moose indirect toll)
##   "trampled" — civilian panic death near an active disaster
##   "burned"   — fire death during a fire/volcano disaster
##
## Pure logic — no rendering, no input, no audio.


const CAUSE_LABELS := {
	"slain": "slain by",
	"attacking": "died attacking",
	"trampled": "trampled fleeing",
	"burned": "burned by",
}


var _records: Array[Dictionary] = []
var _next_id: int = 1


## Opens a record when a disaster spawns. Returns the record id.
func start_disaster(kind: String, label: String, day: int,
		game_time: float, unit_ids: Array = [],
		forecast_day: int = -1) -> int:
	var rec: Dictionary = {
		"id": _next_id,
		"kind": kind,
		"label": label,
		"start_day": day,
		"start_time": game_time,
		"forecast_day": forecast_day,
		"end_day": -1,
		"status": "active",
		"unit_ids": unit_ids.duplicate(),
		"towns": [],
		"deaths": [],
		"military_order": "ignore",
		"citizen_order": "free",
		"moons": 0,
	}
	_next_id += 1
	_records.append(rec)
	return int(rec["id"])


func get_record(log_id: int) -> Dictionary:
	for r in _records:
		if int(r.get("id", -1)) == log_id:
			return r
	return {}


## The active record for a disaster kind, or {} when none.
func active_for_kind(kind: String) -> Dictionary:
	for r in _records:
		if String(r.get("kind", "")) == kind \
				and String(r.get("status", "")) == "active":
			return r
	return {}


## All active records.
func active_records() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _records:
		if String(r.get("status", "")) == "active":
			out.append(r)
	return out


## Full history, newest first.
func history() -> Array[Dictionary]:
	var out: Array[Dictionary] = _records.duplicate()
	out.reverse()
	return out


## Records a town entered (deduped by town_id).
func record_town(log_id: int, town_id: int, town_name: String,
		faction: String, day: int) -> void:
	var r := get_record(log_id)
	if r.is_empty():
		return
	for t in r["towns"]:
		if int(t.get("town_id", -1)) == town_id:
			return
	(r["towns"] as Array).append({
		"town_id": town_id,
		"name": town_name,
		"faction": faction,
		"day": day,
	})


## Records a death. Name should be the display name.
func record_death(log_id: int, victim_name: String, faction: String,
		job: String, cause: String, day: int) -> void:
	var r := get_record(log_id)
	if r.is_empty():
		return
	if not CAUSE_LABELS.has(cause):
		cause = "slain"
	(r["deaths"] as Array).append({
		"name": victim_name,
		"faction": faction,
		"job": job,
		"cause": cause,
		"day": day,
	})


func record_moon(log_id: int) -> void:
	var r := get_record(log_id)
	if r.is_empty():
		return
	r["moons"] = int(r.get("moons", 0)) + 1


## Jeremy 2026-10-04: THE NASTY MONASTERY — count Father Filthwick's
## outbursts on the ledger for the Gazette story.
func record_outburst(log_id: int) -> void:
	var r := get_record(log_id)
	if r.is_empty():
		return
	r["outbursts"] = int(r.get("outbursts", 0)) + 1


## Jeremy 2026-10-04: THE NASTY MONASTERY — remember the monastery's name.
func set_monastery_name(log_id: int, mname: String) -> void:
	var r := get_record(log_id)
	if r.is_empty():
		return
	r["monastery_name"] = mname


## Jeremy 2026-10-04 (massive-dev): HOA KAREN — freeform ledger notes
## (liens placed, fines refunded) for the Gazette story.
func record_note(log_id: int, text: String) -> void:
	var r := get_record(log_id)
	if r.is_empty():
		return
	var notes: Array = r.get("notes", [])
	notes.append(text)
	r["notes"] = notes


## Closes a record. how: "left" (budget spent) or "slain" (killed).
func end_disaster(log_id: int, day: int, how: String) -> Dictionary:
	var r := get_record(log_id)
	if r.is_empty():
		return {}
	r["status"] = how
	r["end_day"] = day
	return r


func set_military_order(log_id: int, order: String) -> bool:
	if not order in ["attack", "ignore", "retreat"]:
		return false
	var r := get_record(log_id)
	if r.is_empty():
		return false
	r["military_order"] = order
	return true


func set_citizen_order(log_id: int, order: String) -> bool:
	if not order in ["shelter", "free"]:
		return false
	var r := get_record(log_id)
	if r.is_empty():
		return false
	r["citizen_order"] = order
	return true


## Death toll of a record.
func death_toll(log_id: int) -> int:
	var r := get_record(log_id)
	if r.is_empty():
		return 0
	return (r["deaths"] as Array).size()


## Human-readable summary for the Gazette.
func summary(log_id: int) -> Dictionary:
	var r := get_record(log_id)
	if r.is_empty():
		return {}
	var towns: Array = r["towns"]
	var deaths: Array = r["deaths"]
	var town_names: Array[String] = []
	for t in towns:
		town_names.append(String(t.get("name", "?")))
	var death_lines: Array[String] = []
	for d in deaths:
		var cause_lbl: String = CAUSE_LABELS.get(
			String(d.get("cause", "slain")), "slain by")
		death_lines.append("%s (%s, %s) — %s the %s" % [
			String(d.get("name", "?")),
			String(d.get("job", "?")),
			String(d.get("faction", "?")),
			cause_lbl,
			String(r.get("label", "disaster")),
		])
	return {
		"label": String(r.get("label", "disaster")),
		"kind": String(r.get("kind", "")),
		"status": String(r.get("status", "")),
		"towns": town_names,
		"death_toll": deaths.size(),
		"death_lines": death_lines,
		"moons": int(r.get("moons", 0)),
		"outbursts": int(r.get("outbursts", 0)),
		"notes": r.get("notes", []),
		"monastery_name": String(r.get("monastery_name", "")),
		"military_order": String(r.get("military_order", "ignore")),
		"citizen_order": String(r.get("citizen_order", "free")),
		"start_day": int(r.get("start_day", 0)),
		"end_day": int(r.get("end_day", -1)),
	}


## ---- save/load ------------------------------------------------------------


func to_dict() -> Dictionary:
	var recs: Array = []
	for r in _records:
		recs.append((r as Dictionary).duplicate(true))
	return {"records": recs, "next_id": _next_id}


func from_dict(data: Dictionary) -> void:
	_records.clear()
	for r in data.get("records", []):
		if r is Dictionary:
			_records.append((r as Dictionary).duplicate(true))
	_next_id = int(data.get("next_id", 1))
