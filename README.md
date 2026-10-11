# Cursing Gnomes — Godot 4 Web Rewrite

Full GDScript rewrite of the Cursing Gnomes browser RTS. Targets Godot 4.7.2
stable, exports to HTML5/WASM (single-threaded) for iPhone Safari.

## Quick commands

```bash
GODOT=~/workspace/tools/Godot_v4.7.2-stable_linux.x86_64

# Import / validate project (headless)
$GODOT --headless --editor --path . --import

# Run the game headless (10 frames, smoke test)
$GODOT --headless --path . --quit-after 10

# Export web build (upload the whole exports/web/ folder to itch.io)
$GODOT --headless --path . --export-release "Web" exports/web/cursing-gnomes.html

# Export Linux desktop build
$GODOT --headless --path . --export-release "Linux" exports/linux/cursing-gnomes.x86_64
```

## Layout

- `project.godot` — engine config (GL Compatibility renderer, 1280×720,
  canvas_items/expand stretch, 60 Hz physics, touch emulation)
- `export_presets.cfg` — Web (single-threaded) + Linux presets
- `icon.svg` — placeholder icon (replace before shipping)
- `scenes/` — main, world, units, buildings, ui, interiors, fx
- `scripts/` — main.gd, core/ (Config, GameState, EventBus), sim/, units/,
  buildings/, world/, ui/
- `assets/` — sprites, tiles, audio, fonts
- `ARCHITECTURE.md` — the full plan: 28 systems mapped, build order,
  web-export rules, risks
- `exports/` — build output (git-ignored)

## Design laws (from the HTML era, enforced in `scripts/core/config.gd`)

- Population: 8/town, 24/faction, 96/global — hard caps
- Essential services (firefighters ×2, doctors ×1) bypass the town cap
- Mobile faction select: player picks, max 2, never preselect
- "urges", never "whims" · ruler name never trimmed · NPCs roast it
- Walk cycles: discrete atlas poses, 8-directional, freeze-position test first
- Jeremy's iPhone is final acceptance for everything
