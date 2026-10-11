class_name WebFrameCap
extends RefCounted
## Cursing Gnomes — web frame-rate cap (thermal bug: "iPhone runs hot").
##
## Jeremy's bar is 60 fps on iPhone 17, but Engine.max_fps was never set
## (default 0 = uncapped). On ProMotion iPhones Safari can drive
## requestAnimationFrame at 120 Hz, which doubles the sustained CPU + GPU
## burn of the 60 Hz sim + render loop for zero visible gain in a pixel-art
## RTS — pure waste heat. Capping at 60 on the web build can only ever
## REDUCE work, never below the 60fps target; at 60 Hz displays it is a
## no-op safety net.
##
## Web-gated on purpose: desktop keeps uncapped high-refresh. Native mobile
## exports (Android/iOS later) can opt in via the same should_cap() when
## they ship. Pure policy object so tests can drive it headless; World._ready
## applies it once at boot (idempotent — re-applying is harmless).


## Jeremy's performance bar: the game targets 60 fps on iPhone 17.
const TARGET_FPS := 60


## True on the platforms where the cap applies. Today: the Web export
## (iPhone Safari) — the device in the thermal report.
static func should_cap() -> bool:
	return OS.has_feature("web")


## Applies the cap when should_cap() (or force_web in tests). Returns true
## when the cap was applied, false when the platform was left untouched.
func apply(force_web := false) -> bool:
	if not (force_web or should_cap()):
		return false
	Engine.max_fps = TARGET_FPS
	return true


## Current engine cap (0 = uncapped). Test seam / debug readout.
static func current_cap() -> int:
	return Engine.max_fps
