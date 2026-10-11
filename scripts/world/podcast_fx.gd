class_name PodcastFX
extends Node2D
## Cursing Gnomes — Milo the Podcast Bro ON AIR FX
## (2026-10-08 rapid-iteration, Disaster #29).
##
## Milo shipped with bespoke chibi art — backwards cap, headphones, giant
## mic, ring light — but the RECORDING itself was invisible. This
## Body-child FX makes the episode visible: a glowing ON AIR sign pulsing
## above his head, little mic icons drifting up off the table, expanding
## sound-wave rings from the big mic, and the ring light's halo. Pure
## _draw (no textures, no emoji/glyphs — ASCII-safe). The sprite itself is
## never moved — freeze-position law: all motion lives in this FX node.

## Monster world height in px (Milo's scale, set by UnitNode).
var stage_h := 64.0
## Drifting mic icons off the table.
const MIC_COUNT := 6
## One mic's drift cycle, seconds.
const MIC_CYCLE := 3.2
## Sound-wave ring period, seconds.
const WAVE_PERIOD := 1.6
## ON AIR sign pulse period, seconds.
const SIGN_PERIOD := 1.1

var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


## 0..1 progress of mic i through its drift cycle (desynced).
func _mic_cycle(i: int) -> float:
	return fmod(_t / MIC_CYCLE + float(i) * 0.61803, 1.0)


## 0..1 progress of wave ring k (desynced).
func _wave_cycle(k: int) -> float:
	return fmod(_t / WAVE_PERIOD + float(k) * 0.5, 1.0)


## ON AIR glow 0..1: hot red pulse.
func _sign_glow() -> float:
	var ph := fmod(_t / SIGN_PERIOD, 1.0)
	return 0.55 + 0.45 * sin(ph * TAU)


func _draw() -> void:
	var h: float = stage_h
	# Ring-light halo: soft warm ring floating behind the table (left).
	var halo_c := Color(1.0, 0.9, 0.6, 0.16 + 0.06 * sin(_t * 2.2))
	draw_arc(Vector2(-h * 0.42, -h * 0.30), h * 0.22, 0.0, TAU, 24,
		halo_c, 5.0)
	draw_arc(Vector2(-h * 0.42, -h * 0.30), h * 0.22, 0.0, TAU, 24,
		Color(1.0, 0.95, 0.75, 0.35), 1.5)
	# Sound-wave rings: expand from the big mic (right of head) and fade.
	for k in 3:
		var w := _wave_cycle(k)
		var wr: float = lerpf(h * 0.08, h * 0.42, w)
		var wa: float = (1.0 - w) * 0.55
		draw_arc(Vector2(h * 0.30, -h * 0.55), wr, -1.1, 1.1, 16,
			Color(0.6, 0.85, 1.0, wa), 2.0)
	# Drifting mic icons: tiny mic (head circle + handle line) rising off
	# the table, fading as they go.
	for i in MIC_COUNT:
		var c := _mic_cycle(i)
		var px: float = h * 0.10 + sin(_t * 1.4 + float(i) * 2.4) * h * 0.10
		var py: float = lerpf(h * 0.05, -h * 0.75, c)
		var a: float = (1.0 - c) * 0.8
		var mr: float = h * 0.035
		var mc := Color(0.75, 0.75, 0.8, a)
		draw_circle(Vector2(px, py), mr, mc)
		draw_line(Vector2(px, py + mr), Vector2(px, py + mr * 3.2), mc, 2.0)
		draw_arc(Vector2(px, py), mr, 0.0, TAU, 10,
			Color(0.95, 0.95, 1.0, a), 1.0)
	# ON AIR sign: rounded red plaque above the head, hot pulsing glow.
	# (No text — ASCII-safe plaque + glow reads as ON AIR at game scale.)
	var sg := _sign_glow()
	var sp := Vector2(0.0, -h * 1.02)
	var ss := Vector2(h * 0.34, h * 0.11)
	var glow_r := Rect2(sp - ss * 0.5 - Vector2(6, 6), ss + Vector2(12, 12))
	draw_rect(glow_r, Color(1.0, 0.15, 0.15, 0.22 * sg))
	draw_rect(Rect2(sp - ss * 0.5, ss), Color(0.55, 0.05, 0.05, 0.92))
	draw_rect(Rect2(sp - ss * 0.5, ss), Color(1.0, 0.3, 0.3, 0.9), false, 2.0)
	# Little "broadcast" dot blinking on the sign.
	if fmod(_t / 0.55, 1.0) < 0.5:
		draw_circle(sp + Vector2(-ss.x * 0.38, 0.0), 3.0,
			Color(1.0, 0.35, 0.35, 0.95))
