# Countryballs Conquest

A small real-time strategy prototype written in Python with Tkinter. The game starts from one island map, places countryball capitals on it, divides the island into static territories, and lets the player send unit streams between capitals.

No third-party packages are required.

## Current Goal

Build a compact, testable countryballs strategy game where the core loop is already playable:

- generate one island-shaped map;
- place capitals safely inside the island;
- split the island into territories owned by the capitals;
- grow units over time;
- send units between capitals;
- capture capitals and repaint their territories;
- end the game when only one occupied owner remains.

The priority is a stable foundation over ambitious mechanics. AI, balance, and visuals can improve later without rewriting the game loop.

## How To Run

```powershell
python main.py
```

Tkinter is part of the standard Python installation on most desktop Python builds.

## Controls

The default control mode is `drag_stream`.

- Hold the left mouse button on one of your capitals.
- Drag toward another capital.
- When the cursor reaches a capital, the target snaps and receives a red outline.
- Release the mouse button to start a unit stream.
- Each stream sends 1 unit ball per tick until only 1 unit remains at the source.
- Drag through your own capitals to add them as extra sources.
- All chained sources send together into the final target.
- `Space` or `Pause`: pause or resume.
- `R` or `Restart`: restart the game.
- `Menu` or `Esc` during a match: return to the main menu.
- `Esc` in a submenu: return to the main menu.

Sending is disabled while paused.

The old click mode is still available in `config.json` by changing `controls.mode` from `drag_stream` to `click`.

## Menu

The game opens on a menu screen by default.

Play setup:

- opponent count;
- player starting units;
- bot starting units;
- neutral territory count.

Settings:

- starting unit spread;
- starting territory count range;
- flight speed;
- player and bot growth;
- player unit multiplier;
- AI mode: `medium` or `aggressive`;
- flag skins on/off;
- player color;
- two-color player flag skin.

The current skin editor is intentionally simple: it supports player color and a two-band flag overlay. A full pixel/flag editor is a good separate milestone.

The settings menu is scrollable with the mouse wheel. `Esc` returns from a submenu to the main menu.

## Map Algorithm

The map is generated in three steps:

1. Island polygon:
   The island is an irregular convex polygon. A configurable number of points are placed around an ellipse, then each point receives a small random radial noise.

2. Safe capital spawn:
   Capitals are sampled inside the island polygon. Each capital receives a random personal spawn gap, so capitals do not touch each other but also do not look grid-aligned.

3. Static territory split:
   Each territory starts as a copy of the island polygon. For every other capital, the polygon is clipped by the perpendicular bisector between the two capitals. The result is a Voronoi-like cell: every point in that territory is closer to its capital than to the others.

Territory borders are static. When a capital changes owner, the shape does not move; only the fill color changes.

## Game Loop

The project keeps input, world logic, and rendering separate:

- `game/world.py`: map generation, units, growth, movement, combat, capture, AI timing.
- `game/actions.py`: unified action pipeline used by UI and tests.
- `game/app.py`: Tkinter window, input binding, drawing.
- `game/models.py`: data objects for capitals and moving unit groups.
- `game/stats.py`: persistent stats stored as JSON.
- `config.json`: tuning for map, controls, units, graphics, and AI.
- `tests/test_world.py`: behavior checks for growth, combat, capture, territories, and drag-stream sending.

Buttons and input handlers call the same `GameActions` methods that tests call. This keeps the game testable even though it has a graphical window.

## Configuration

Important settings in `config.json`:

- `game.country_count`: occupied capitals at start.
- `game.neutral_territory_count`: neutral capitals at start.
- `game.send_units_per_tick`: units sent by each stream tick, currently 1.
- `game.send_stream_interval_seconds`: stream tick interval.
- `game.auto_growth_unit_cap`: automatic growth limit.
- `controls.mode`: `drag_stream` or `click`.
- `controls.target_snap_radius`: how close the cursor must be to snap to a target.
- `island.*`: island shape and coastline colors.
- `country.initial_radius`, `country.max_radius`: visual capital size range.
- `graphics.*`: softer drawing settings.
- `ai.*`: random AI send interval and minimum units.
- `stats.file`: persistent stats output path.

## AI Modes

`medium`:

- chooses a viable bot capital;
- prefers nearby targets;
- behaves less predictably and less efficiently.
- starts a direct stream to the chosen target.

`aggressive`:

- uses stronger bot capitals first;
- attacks the weakest non-owned target;
- acts faster through an interval multiplier;
- can attack earlier with a lower unit threshold.
- also uses direct streams, without player-style chains.

The aggressive mode is deliberately simple but already produces clearer pressure.

## Persistent Statistics

Stats are written to `work/stats.json`:

- games started;
- wins;
- total battle time;
- territories captured by the player.

The bottom bar shows current session state plus saved wins and captures.

## Debugging

`debug.enabled` is on by default. Runtime errors in the frame loop are printed to the console with a traceback, and the game pauses instead of silently continuing in a broken state.

## Visual Direction

The graphics are intentionally soft and readable:

- pale water background;
- green island base;
- pastel territory fills;
- static border lines;
- shaded capitals;
- countryball eyes;
- dashed drag arrow with target snapping;
- red target outline during drag.
- chain arrows for multi-stage attacks;
- pulse animation on unit changes and captures;
- floating unit delta numbers.

This is still Tkinter, so the rendering stays simple, but the scene should feel more polished than raw debug circles.

## Realistic Development Plan

1. Stabilize the current prototype:
   Keep tests passing while refining the map, input, capture, and AI loops.

2. Improve AI:
   Replace random targeting with a simple rule system: attack weak neighbors, reinforce owned capitals, avoid wasting units.

3. Improve territory semantics:
   Decide whether moving units should travel freely or follow territory adjacency.

4. Add better UI feedback:
   Show stream status, selected source, incoming attacks, and owner counts.

5. Balance:
   Tune growth, send fraction, neutral cost, map size, and AI timing.

6. Optional presentation polish:
   Add countryball expressions, small flag-like markings, animations, and a start/end screen.

The immediate architecture is deliberately modest: one window, one world object, one action pipeline, and tests for mechanics. That gives enough structure for safe iteration without turning the prototype into a large engine too early.
