# Blastfront test & benchmark toolkit

Everything an agent (or a human) needs to verify changes without ever opening a game window on the
developer's screen: regression runs, invisible screenshots, a reproducible performance suite, a profiler,
GPU/draw-call ablation, load-time probes and dead-code/asset scanners. The folder has a `.gdignore`, so the
Godot editor ignores it, and the export preset excludes `tools/*`, so none of it ships.

Engine: Godot **4.6.1 stable**, GL Compatibility renderer, GDScript with static typing. Main dev machine:
Windows 11, Ryzen 7 7730U laptop with Radeon iGPU, 60 Hz 1920x1200. Scripts are bash (Git Bash on Windows;
Linux/macOS work with `rsync` instead of `robocopy`) plus Python 3 (Pillow for image diffs).

## Ground rules

- **Never show anything on the developer's screen.** No visible game window, no audio. Tests run headless,
  or in a 1x1 borderless transparent window parked in the bottom-right corner (an off-screen window gets
  throttled by Windows), with `--audio-driver Dummy`. The real game renders into a SubViewport that the
  harness saves as PNG.
- **Never run tests in the real project folder.** Every run happens in a mirror copy (`$WORK_DIR/mirror`,
  synced with `robocopy /MIR` or `rsync --delete`, excluding `.git` and `.godot`). The mirror keeps its own
  `.godot` import cache, so syncing is cheap and the developer's editor state is never touched.
- Tests write to a separate user dir (`user://` = `blastfront_tests`, set by the `overrides/*.cfg` files that
  get copied in as `override.cfg` for the run), so saved settings/progress of the real game stay untouched.
  The same overrides set `blastfront/steam/disabled=true`: test runs never touch the Steam client of whoever
  is logged in (no lobbies, no persona lookups), even when Steam is running.
- After pulling a collaborator's work that adds assets or new `class_name` scripts, run `import.sh` first.
  A stale class cache makes every run fail with hundreds of "Identifier not declared" errors, and any
  benchmark taken in that state is garbage.
- A GDScript runtime error is what the developer experiences as "the game crashed" (the editor's debugger
  freezes the game). The regression gate is therefore: zero `SCRIPT ERROR` lines.

## Setup

```bash
# optional; defaults are in env.sh
export GODOT="/path/to/Godot_v4.6.1-stable_win64_console.exe"   # on Windows use the *_console.exe
export WORK_DIR="$HOME/blastfront_testwork"   # outside the repo, Google Drive and %TEMP% (default: %LOCALAPPDATA%\blastfront_testwork)
bash tools/testing/import.sh          # first sync + headless import of the mirror (a few minutes the first time)
bash tools/testing/regress.sh         # should print OK for every scenario
```

`env.sh` finds the Godot binary that sits next to the project on the main dev machine
(`../../Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe`) and falls back to `godot`.

## Everyday commands

| Command | What it does |
|---|---|
| `regress.sh [scenario...]` | Syncs the mirror, compiles every script once (`parse_all.gd`, catches errors in files no scenario loads), runs the 13 regression scenarios headless, prints `OK` / `FAIL` + distinct errors. Run before every commit. |
| `run_headless.sh <scenario>` | One scenario headless, full (filtered) output. Good for scenarios that `print` measurements. |
| `run_capture.sh <scenario> [out_dir]` | One scenario with real rendering, invisible; PNG per `shot` action (default `$WORK_DIR/captures/<scenario>`). `BF_FULLHD=1` for 1920x1080, `BF_SIZE=1280x800` for the logical size on 16:10 / Steam Deck (the project uses the `keep_width` stretch aspect, so taller screens get more height and ultrawide gets side bars). `PROJ_OVERRIDE=$WORK_DIR/mirror_base` renders the old version for before/after comparisons. |
| `import.sh` | Sync + headless import. |
| `run_probe.sh <probe.gd> <headless\|render> [args]` | Runs one of the probe scripts (see below) in the mirror. |
| `sync_mirror.sh` | Sync only. |

Look at the PNGs yourself (an image-capable model can read them) and diff before/after captures with
Pillow (`ImageChops.difference`) when a change should be pixel-identical.

### Scenarios (cases in `capture.gd` `_build_script()`)

- **Regression set:** `combat flow online_ui ui_quests victory gamepad explosive lo_interact loadout_inter loadout2 world_switch mars_play locker_esc`
- **Screens:** `menu` (main menu, bot panel, settings), `pad_nav` (menus driven only by ui_* actions,
  prints the focused control after every step and shoots each one), `pad_nav_game` (pause menu and sandbox
  loadout as a pad user), `pad_nav_inter` (LB / RB through the between-set pages, d-pad inside them), `controls_tab`, `settings_reset` (prints the tab
  titles after RESET DEFAULTS), `summary_look`, `research_look`, `research_movement` (Movement lane,
  Dashing's four marks in the dock), `online_pages`,
  `loadout`, `pause`, `hud`, `victory`, `bg_look`, `art` / `armor_art` (sheets of every weapon part and
  armor piece, ideal for pixel diffs of the procedural art)
- **Gameplay:** `sandbox`, `bot`, `look`, `gunfeel`, `laser_look` (`BF_WORLD=mars` for Mars), `gun_ingame`,
  `scope_check` (prints ballistics per scope), `aim_stability`, `airdrop_look`, `explosive`, `terrain`
- **Movement probes:** `dash_probe` (on its own test floor: burst distance, cooldown per mark, air dash,
  Mk IV protection against a real round, Mk III shockwave vs a parked dummy; render for close-up crops),
  `dash_online` (faked hosted set, no Steam: the movement module fed the packets a peer would send),
  `bot_dash` (two bots, `BF_BOT_LEVEL` 0-2 default hard, `BF_WORLD`; logs every dash), `wall_probe` (Wall
  Jumps per mark on a private rig: climb height, wall jumps in one airtime, cling time, standing on top,
  longest time stuck in the air; plus a platform lip and a cling that must end in a slide), `bot_climb`
  (a bot of `BF_BOT_LEVEL` sent up a 160 px step and a 400 px wall; only the marks that reach may climb)
- **Mars weather:** `mars`, `mars_storm`, `mars_close`, `mars_duel_look`, `shelter_probe`, `ledge_test`
- **Time Control:** `time_probe` (bot duel: run and projectile speed before/during/after the slow, refusals in
  the intro and on cooldown, the reverse cast; prints `TIME_PROBE PASS/FAIL` lines), `time_sandbox`,
  `time_freeze` (Mk III: rounds hang, inputs blocked, 35% damage cap, last point kept, no cast during the kill
  banner), `time_bot` (a low Hard bot casts once it sees you; a slowed bot backs off), `time_online` (host and
  client paths without Steam: casts, spoofing, kill banner, late packets, snapshot corrections, frozen rounds). regress.sh only greps
  for script errors, so read the PASS/FAIL lines of these yourself.
- **Bots:** `bot_watch` (two hard bots, state log every 1.5 s, `BF_WORLD`), `bot_spawn_look` (screenshots of
  the left spawn, where a navigation bug once kept a bot hopping)
- **Economy / loadout interaction:** `sell_test`, `sell_equipped`, `botshop`, `shoptour`, `lo_interact`, `loadout_inter`
- **Long stress:** `stress` (AI vs AI, random loadouts every 6 s, `BF_STRESS_SECONDS`, `BF_WORLD`),
  `stress_sandbox` (continuous fire with random loadouts); both print frame percentiles and the worst spikes.

Writing a scenario: add a case, queue actions with `_at(seconds, kind, arg)`; kinds are `shot` (save PNG),
`crop` (`[name, Rect2, scale]`: an upscaled close-up of one region), `call` (run a lambda, e.g.
`_main._on_sandbox_requested()` or `root.get_node("UserSettings").set_value(...)`),
`mouse` (move pointer in viewport coordinates), `action` (pushes a real press+release event, needed for
anything handled in `_input`/`_unhandled_input` such as pause), `press`/`release` (hold an input action;
only polled input sees it), `key_down`/`key_up` (an action through `Input.parse_input_event`, so
`is_action_just_pressed` in physics sees it even in render runs), `quit`. Helpers: `_stress_game()` (the running Game node), `_equip([ids])`,
`_freeze_camera(at, zoom)` (hides players and HUD), `_freeze_camera_keep_players`, `_place_p1(pos)`,
`_weather()` (Mars weather, `skip_to_storm(...)`), `_lo_mouse_to_tile(id, offset)` / `_lo_press(down)`
(real drag & drop in the loadout), `_build_test_floor(top_left, width)` (a plain slab for movement probes;
the arenas have no long flat floor; `_clear_terrain()` removes the arena's own), `_hooks` (callables run every frame, e.g. `_watch_dashes`),
`_movement_packet(type, from_slot, payload)` (feed the movement sync module like a peer would).

## Performance measurement

`perfsuite.gd` is a fixed sequence of phases with deterministic drivers (seeded RNG, AI vs AI duels with a
random loadout every 6 s, a scripted sandbox stress, a pointer sweeping across the loadout and research
pages). It prints `R <metric> <value>`:

- `boot_ms` (process start until the main menu exists), `boot_full_ms` (until the background scene loads are done)
- `load_duel_ms`, `load_mars_ms`, `load_sandbox_ms`, `load_loadout_ms` (scene swap to playable)
- per phase (`menu`, `duel_verdant`, `duel_mars` with forced storms, `sandbox_stress`, `loadout`, `research`):
  `_mean _p95 _p99 _max` frame ms, `_nodes` (CPU mode); in render mode also `_gpu`, `_rcpu` (render-thread CPU), `_draws`
- `mem_static_mb`, `mem_peak_mb`, `objects`, `resources`, and in render mode `vram_*`

```bash
bash tools/testing/sync_mirror.sh
bash tools/testing/make_baseline.sh                       # freeze "before" as $WORK_DIR/mirror_base (after import.sh)
# ... change code, sync / import again ...
R=$WORK_DIR/results; mkdir -p $R
for i in 1 2 3; do bash tools/testing/run_perf.sh cpu $R/base_cpu_$i $WORK_DIR/mirror_base; bash tools/testing/run_perf.sh cpu $R/new_cpu_$i; done
for i in 1 2; do for v in base new; do P=$WORK_DIR/mirror; [ $v = base ] && P=$WORK_DIR/mirror_base
  BF_UNCAPPED=1 BF_OPAQUE=1 OVERRIDE=opaque.cfg bash tools/testing/run_perf.sh render $R/${v}_gpu_$i $P; done; done
python tools/testing/perfcompare.py "$R/base_cpu_[0-9]" "$R/new_cpu_[0-9]"   # medians + % change
python tools/testing/perfcompare.py "$R/base_gpu_[0-9]" "$R/new_gpu_[0-9]"
bash tools/testing/release_boot.sh $WORK_DIR/mirror_base; bash tools/testing/release_boot.sh   # player-facing start-up
```

How to read it honestly:

- **CPU mode** (headless, `--fixed-fps 60`): the engine never sleeps, so wall time per frame is the CPU
  cost of one 60 Hz frame. This is the most stable metric (run-to-run noise ~2-5 % on means).
- **Render mode** needs `BF_UNCAPPED=1 BF_OPAQUE=1 OVERRIDE=opaque.cfg`: transparent windows stay vsynced,
  and the game re-applies its own FPS cap from the settings (the suite forces it off every frame). At a 60 fps
  cap the GPU ms only reflect clock states, so never compare capped GPU numbers. iGPU timings are noisy
  (+-0.3 ms); draw-call counts are the reliable render metric.
- Windowed runs stall when the display is off or locked. CPU runs don't care.
- Always interleave before/after runs (base, new, base, new) and report medians; Drive sync and other apps
  cause drift. Only compare runs from the same `WORK_DIR`: absolute start-up times differ by 2x between
  folders on the dev machine (antivirus/indexing), relative changes do not.
- Duel numbers depend on what the bots do. If a change alters AI behaviour (more shots, more nodes), frame
  time moves for that reason too: check `*_nodes` and the profile before crediting/blaming the code.
- Exported release builds ignore `-s` scripts; `release_boot.sh` times them as plain processes.

### Finding the cost

- `profile.sh` – instruments a throwaway copy (`instrument.py` wraps every engine callback plus the hot classes
  listed in its `EXTRA` table) and prints `P <phase> <script:function> <ms/frame> <calls/frame>`. Inclusive
  times with overhead; use it to rank, not to quote. The calls/frame column finds things that redraw or
  replan every frame by accident.
- `run_probe.sh gpuablate.gd render world=mars` – hides one part of a running AI duel at a time and prints
  draws / render CPU / GPU / frame per configuration (`BF_DRAW_ABLATE=1`: players, HUD, arena, border,
  projectiles; `BF_HUD_ABLATE=1`: each HUD widget).
- Load time: `run_probe.sh bootprobe.gd headless` (engine+autoloads vs. scene loads),
  `run_probe.sh depprobe.gd headless target=res://scenes/game.tscn` (every dependency, slowest first),
  `run_probe.sh scriptprobe.gd headless order=res://a.gd,res://b.gd` (compile cost in a given order).
- `compile_probe.py inject <copy>` + run the copy headless with `--quit-after 3` + `compile_probe.py report <log>`:
  timeline of which scripts compile before the menu (static-init markers; inherited classes may not report).

## Cleanup scanners

```bash
python tools/testing/unused_assets.py .   # files in assets/ nothing references (by path or load key)
python tools/testing/unused_code.py .     # scripts/scenes nobody references (path, uid or class_name)
python tools/testing/unused_funcs.py .    # private functions nothing calls or connects
```
They are heuristics: check dynamic loads (`"%s.wav" % key`, colour ids, research icons) before deleting.

## Lessons that cost time (keep them)

- Start-up time is almost entirely GDScript compilation (~0.2 ms per line in the editor binary). `Main` loads
  only the menu and warms the rest on one worker thread while the menu is up. The main thread must never
  load while that worker runs (concurrent loads of shared scripts fail with "Could not preload"), so every
  scene swap and app exit first waits for the load in flight. Naming a class in a script compiles it: keep
  autoloads free of hard references to big gameplay classes.
- A `Control` whose position/rotation changes every frame redraws every frame; animate a `Node2D` instead.
- Packed arrays are values in GDScript: `(dict["pts"] as PackedVector2Array).append(...)` edits a copy.
- One-shot sounds must be WAV (QOA): an Ogg `play()` rebuilds the Vorbis decoder (~1.2 ms each).
- Creating particle/line nodes per hit causes spikes; `FxLib` pools emitters.
- `print` inside a measured window shows up as 20-40 ms spikes; collect and print at the end.
- VRAM (BC7) compression of the big painted backgrounds saved no VRAM on the dev iGPU and grew the pack by
  4.5 MB; they stay lossless.
- Never keep `WORK_DIR` in `%TEMP%`: the mirror's files carry the sources' old timestamps, and Windows'
  Storage Sense deleted a third of them mid-session, which showed up as "GDExtension not found" and
  "Could not parse global class" in every run.
- Input actions pressed with `Input.action_press` never reach `_unhandled_input`; scenarios that open menus
  (pause) need the `action` kind, which pushes a real `InputEventAction` into the viewport.
- Bots: `LevelNavigation` validates each jump at one sideways speed (`vx` on the edge) and the bot steers
  to it in the air; at full speed jumps up and sideways bumped into the ledge they were meant to land on.
  `bot_watch` (positions, goals, score every 1.5 s) and `bot_spawn_look` (screenshots) show such loops.

## Reference numbers

Absolute numbers on the dev laptop swing by up to 2x between sessions (power state, folder, background
apps), so treat these as orientation only and always measure before/after interleaved in one session.

Performance pass of 2026-10-06, before -> after (medians of interleaved runs, same session and folder):

| Metric | Change |
|---|---|
| Start to menu, exported release build | -41 % (6.1 s -> 3.6 s in that session) |
| Start to menu, editor binary | -50 % |
| Loading Mars | -49 % (render) / -69 % (CPU) |
| Uncapped frame: loadout / menu / duel Verdant / duel Mars | -48 % / -24 % / -21 % / -13 % |
| CPU per frame: loadout / duel Verdant / duel Mars | -55 % / -10 % / -9 % |
| Draw calls: loadout / menu / duel | -38 % / -41 % / -15 % |
| Export pack | 18.5 MB -> 16.7 MB |

A full CPU run in the default `WORK_DIR` on a good day (same code, after the pass): `boot_ms` 2266,
`menu_mean` 0.24, `duel_verdant_mean` 1.40, `duel_mars_mean` 1.60, `sandbox_stress_mean` 1.22,
`loadout_mean` 0.75 ms, `load_mars_ms` 85; release build start to menu ~1.7 s.
