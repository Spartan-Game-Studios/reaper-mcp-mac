---
name: reaper
description: Use when composing, arranging, mixing or rendering music or sound in REAPER through the reaper MCP (mcp__reaper__* tools) — writing MIDI parts, loading Surge XT patches by name, building a game loop (menu ambience, level music), rendering/bouncing, or syncing after the user edits the project by hand. Triggers on "make it in reaper", "compose a track", "menu music", "ambience loop", "load a Surge patch", "render the song", "the reaper project", "game music". Covers the bridge's quirks (void returns, timeouts, dialogs, non-overwriting renders), the Surge patch loader, MPE breath, arrangement-as-code, stem verification, and loop delivery.
---

# REAPER via the reaper MCP

Drive a live REAPER session: tracks, Surge XT instruments, MIDI, mix, render, then ship a game-ready
loop. The MCP server + Lua bridge live in this repo (`reaper-mcp`, `README.md` for setup). This skill
is the working method and the traps, learned building the Death Gods: Morrigan menu ambience
(5 Oct 2026; worked example: `death_gods_morrigan/audio_src/`).

## The loop

1. **Orient.** `reaper_ping`, then `reaper_get_project_state`. If the user has a project open, **don't
   build in it**: open a new project tab (`reaper_call Main_OnCommand [40859, 0]`, then confirm with
   project state: 0 tracks).
2. **Instruments.** Surge XT is installed (plus ReaSynth / ReaSynDr / ReaSamplOmatic). Add it with
   `reaper_add_fx "Surge XT"`, then load a real patch by name with the **Surge loader** (below), not by
   tweaking 2,858 parameters.
3. **Write the parts as code**, not as hand-typed tool calls: a small Python generator emits a notes
   file; the `write_midi` helper loads it (below). Hundreds of notes in one round trip, regenerable,
   and the generator can **assert the arrangement's rules**.
4. **Render** with `reaper_render` (bounds `project`) to a **new filename** every time.
5. **Verify by measurement, not assumption** (you can't listen): per-track solo stems → which
   instrument sounds in which bar; RMS per block; spectral peaks for pitch. See "Verify".
6. **Deliver**: `tools/make_loop.py` → normalised, seamless wav + ogg.
7. **Save** with `Main_SaveProjectEx` (never `Main_SaveProject` on an untitled project).

## Bridge quirks (each one cost time)

| Symptom | What's really happening | Do this |
|---|---|---|
| `MCP error -32602 … invalid_union` after `Main_OnCommand`, `DeleteTrack`, `Main_SaveProjectEx`, … | The function returns nothing, the bridge returns `undefined`, and the MCP rejects the empty result. **The call ran.** | Ignore the error. Verify via the side effect (project state, a log file, file mtime). |
| `timeout after 15000ms` on a long action (stem renders, multi-render scripts) | The bridge gave up waiting; REAPER is still working. | Have the script write a done/log file and poll it from Bash. |
| Every call times out, even `reaper_ping` | REAPER is showing a **modal dialog** (Save As, overwrite, …). | Ask the user to dismiss it. Avoid the cause (next rows). |
| `Main_SaveProject(0,false)` hangs everything | An untitled project opens a Save As dialog. | Use `Main_SaveProjectEx [0, "/abs/path.rpp", 0]`. Check the file mtime after. |
| A render "succeeds" but the analysis shows old audio | **REAPER never overwrites a render**: it silently writes `name-001.wav`. | A new filename per render (`…_v7.wav`); delete stem folders before re-rendering; check mtimes. |
| `reaper_insert_track` with no index errors | The bridge passes a string to `InsertTrackAtIndex`. | Always pass `index`. |
| The mix suddenly renders 10–30 dB quieter | The **user moved the master fader** while listening. | Read `D_VOL` on `GetMasterTrack` before judging levels; don't fight their fader. Normalise the deliverable in post (`make_loop.py`). |
| `handle:N` stops pointing where you think | Handles are per-session pointers, minted on each `GetTrack`/`GetMasterTrack`. | Re-fetch before acting; **check `GetTrackName` before `DeleteTrack`**. |

## Helper scripts (`lua/helpers/`)

Anything the dedicated tools don't cover runs as a Lua ReaScript inside REAPER. Install once:
`scripts/install_helpers.sh` (copies to `Scripts/reaper_mcp_<name>.lua`). To run one:

```
reaper_call AddRemoveReaScript [true, 0, "<abs path to Scripts/reaper_mcp_x.lua>", true]  -> command id
reaper_call Main_OnCommand [<command id>, 0]   -> the void-return MCP error; it ran. Read its log.
```

Registering is idempotent (same path, same id within a session); the script is re-read from disk on
each run. Helpers talk through `/tmp/reaper_mcp_*` files:

| Helper | Input | Output |
|---|---|---|
| `load_surge_patch.lua` | `/tmp/reaper_mcp_surge_jobs.txt`: `track\|fx\|/abs/patch.fxp` per line | `…_surge_jobs.log`: `track\|fx\|true\|name` |
| `write_midi.lua` | `/tmp/reaper_mcp_midi.txt`: notes `track\|start_qn\|len_qn\|pitch\|vel`, pressure `P\|track\|qn\|val`, CC `C\|track\|qn\|cc\|val`, `LEN\|qn` | one MIDI item per track; `…_midi.log` |
| `clear_items.lua` | — | removes every item, keeps tracks/FX/patches/levels |
| `stem_check.lua` | — | `/tmp/reaper_mcp_stems/<i>.wav` per track soloed, then `done.txt` (times the bridge out; poll) |
| `dump_project.lua` | — | `/tmp/reaper_mcp_dump.txt`: master + per-track volume/mute/notes/CC counts |

## Surge XT patches by name

Surge doesn't expose its patches as REAPER presets (`TrackFX_GetPresetIndex` → 0) and the VST3
can't import `.fxp`. But its VST3 state *is* the patch, so `load_surge_patch.lua` writes the `.fxp`
body into `vst_chunk` (format in the script header). Confirm by reading the chunk back: Surge
re-serialises with `<meta name="<patch>">`. Reading `vst_chunk` back returns ~70 KB; it spills to a
tool-results file, so decode it with Python rather than reading it inline.

Libraries: `/Library/Application Support/Surge XT/patches_factory/<Category>/` and `patches_3rdparty/
<Author>/<Category>/`. `find … -iname "*word*"` beats browsing. Picks that worked for a dark Celtic
ambience: *Basseridoo 1* (Slowboat Winds: a pipe-style drone), *Bass Ocarina* (LinnStrument MPE Winds),
*Djembeish 1* (Slowboat Percussion: a hand-drum heartbeat), *Ghost Pad*, *Ooh* (a soft choir). Cut for
being grating or busy: *Vocal Lead* (a synth "voice"), *Bird Squawk*, *Skyscraper Harp*.
**There is no sampled piano** on this machine; *Piano Fictions* (Jacky Ligon, Modelled) is the closest.

### MPE patches need breath

LinnStrument/MPE patches route **channel pressure** (aftertouch) to filter/drive/level. Played with
plain notes they're muffled and quiet (*Bass Ocarina*: ~11 dB quieter, ~10 dB darker). Read the
patch's `<modrouting source=…>`: Surge source 4 = channel aftertouch, 1 = velocity, 17+ = LFOs.
Then write a pressure envelope under every note (`P|…` lines): in over ~0.25 beat, hold with a slight
sag, ease off at the end, peak scaled by velocity, sampled every ~0.08 beat. Skip grace notes (<0.2
beat); they ride the next note's breath.

## Arrangement as code

Keep the piece in a Python generator (worked example: `death_gods_morrigan/audio_src/
menu_arrangement.py`) that:
- names the tracks by index constant (and matches REAPER's track order: renumber when tracks are deleted);
- builds phrases from motif tuples `(offset, length, pitch, velocity)`;
- **asserts the structural rules** before writing anything (e.g. each instrument's entry/exit
  window), so a sloppy edit fails loudly instead of rendering wrong;
- takes simple knobs as env vars (e.g. `WHISTLE_SHIFT`, a diatonic transpose within the mode so a
  re-voiced melody can't clash with the drone).

Rewrite cycle: generate → `clear_items` → `write_midi` → render a new filename. When the user edits
REAPER by hand, run `dump_project`, diff it against the generator's output, and bring the script back
in line (their levels live in the `.rpp`; write them down in the script's header).

### The rule of 2 (the user's arrangement rule)

Start with **4 bars of the heartbeat/pulse alone**, then change **at most one thing every 2 bars**
(one instrument in or out), and make the loop seam itself a single change. Check it in the *audio*,
not the MIDI: instrument **release tails spill into the next bar** (end sustained notes ~3 s early),
and a sparse part with rests reads as extra in/out changes (make a part continuous inside its window,
e.g. a held chord under phrases). Fewer layers won: the final menu bed is drone + ocarina lament +
heartbeat.

## Verify

You can't hear it, so measure (numpy lives in the ComfyUI python:
`/Users/atticus/ComfyUI-Installs/Atticus/standalone-env/bin/python`; the system `python3` lacks it):
- **Stems**: `stem_check.lua`, then per-bar RMS > −55 dB per stem gives a presence grid of instruments
  × bars. Count changes per bar to prove an arrangement rule.
- **Level shape**: RMS per 8 s block; peaks.
- **Pitch**: FFT peak in the melody band over one phrase (catches "the patch plays an octave off").
- **Accents**: peak of the loud hit vs its answer (e.g. BOOM-BOOM vs bum-bum). Some patches barely
  respond to velocity, so check the real dB gap.
- Say plainly in the report that you measured but didn't listen.

## Deliver

`tools/make_loop.py render.wav out/name`: prints the shape, **normalises to −22 dB RMS** (peak ≤ −1
dBFS) so the file is independent of the master fader, bakes a 1.5 s equal-power tail→head crossfade
(the seam jump drops from ~0.1 to ~0.001), and writes wav + ogg. Homebrew ffmpeg has no `libvorbis`;
the script uses the native `vorbis` encoder (`-strict -2`, stereo). In Godot, set `loop=true` in the
ogg's `.import` and play it on the Music bus (see the `audio-director` / `settings-manager` skills).

## Related

- `audio-director` and `settings-manager` skills: playing the loop in-game and its volume sliders.
- The Suno pipeline (`godot-addons/tools/song-video/gen_songs.py`) is the *other* route (generated
  audio). If the user says "in REAPER", they mean compose it here, not generate it.
