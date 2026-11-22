# Profiling: phase 1 (before) and phase 2 (after), 2026-11-22

The first part is the "before" numbers for phase 2 (archive/ROADMAP.md): frame time
of the whole-stack showcase and of the busiest reference scenes, and where
the time goes. Facts only; what they suggest is at its end. The second part,
"After phase 2", measures the finished phase 2 the same way, beside the
phase-1 build measured again. Rerun everything with `tools/profile.sh`
(outputs in `tests/out/profile/`).

## Method

- **Machine:** Intel Core Ultra 5 225H (Arrow Lake, 4 P + 8 E + 2 LP-E
  cores). The session's CPU affinity was 4-13, so the runs used E-cores
  only; `powersave` governor. 15 GB RAM. Fedora 45, kernel 7.3.3.
- **GPU and driver:** Intel Arrow Lake-P integrated graphics, Mesa 26.2.6
  (iris, gallium), through EGL.
- **Libraries:** SDL 3.4.20, SDL3_ttf 3.2.2 (FreeType 2 and HarfBuzz),
  SDL3_image 3.4.8. Nimony 0.6.3 commit 95afaa04, GCC 16.2.1.
- **Build:** `-d:release` (`-O3`, run-time checks on), `--mm:orc`,
  `--passC:-g --passC:-fno-omit-frame-pointer`.
- **Program:** `tests/tshowcase.nim`, the scripted run of
  `examples/showcase.nim` (800 x 600): attract crossfade, tap to home, tile
  press and FadeTransition to the topic card, next, prev, swipe, the Listen
  clip to its end, home, the ModalView language picker, Greek, resize to
  1000 x 750, idle reset to the attract screen. 35 steps, about 9 s.
  Offscreen window (`SDL_VIDEO_DRIVER=offscreen`) through EGL,
  `SDL_RENDER_DRIVER=opengl`, `SDL_AUDIO_DRIVER=dummy`. No vsync.
- **Frame time:** `SHOWCASE_PROFILE=<file>` with maxfps 0 (uncapped, so
  nothing sleeps between frames). A frame that drew (`on_flip`) is timed
  by Clock's dt at the next tick: the whole frame, from the Clock tick
  through input, the before-frame triggers (layouts, label renders),
  drawing and SDL_RenderPresent, to the event poll. CPU time only: the GPU
  works asynchronously and is not measured. Frames that did not draw (the
  canvas unchanged) are counted but not timed.
- **Scenes:** `SCENES_REDRAW=1000 bin/scenes-profile <scenes>`: each scene,
  once settled, is drawn 1000 more times (`askUpdate`, then one
  `EventLoop.idle`), uncapped.
- **perf:** the same run capped at 60 fps (Kivy's default maxfps; uncapped,
  the profile is the event pump spinning), user space only
  (`perf_event_paranoid` is 2): `perf record -e cycles:u -F 9999
  --call-graph fp --user-callchains`.
- **callgrind:** the same capped run under `valgrind --tool=callgrind
  --fair-sched=yes`, `DEBUGINFOD_URLS=` (otherwise valgrind waits on
  debuginfod for the system libraries and hangs). Instruction counts (Ir)
  and exact call counts (`tools/callcounts.sh`). Under valgrind the run
  has fewer frames (568, 223 drawn), so the counts are for that run.

## Frame time: the showcase

Offscreen, three runs, frames that drew:

| run | frames | drawn | mean | p50 | p95 | max |
|---|---|---|---|---|---|---|
| 1 | 10,250,526 | 35,897 | 0.068 ms | 0.012 ms | 0.040 ms | 88.6 ms |
| 2 | 10,085,963 | 34,183 | 0.072 ms | 0.012 ms | 0.043 ms | 87.6 ms |
| 3 | 9,974,443 | 37,601 | 0.066 ms | 0.011 ms | 0.040 ms | 80.2 ms |

- About 55 drawn frames per run take more than 1 ms, and about 29 more
  than 16.7 ms (one 60 Hz frame); they take 2.3 s of the run's frame time
  together. By the step before them (a fourth run, tagged): the first
  frames (12 frames, 416 ms), the first visit of each screen after a fade
  (tile press to the topic screen 246 ms, home button 249 ms, the tap on
  the attract screen 246 ms), the resize to 1000 x 750 (263 ms: every
  label renders again at the new font size), the Listen button (9 frames,
  134 ms: its label text changes to Stop and back), the language picker
  (121 ms) and Greek (67 ms: every label renders again).
- Real window, X11 (XWayland, scale 1), three runs: drawn 5,995 / 6,119 /
  6,273, mean 0.376 / 0.366 / 0.357 ms, p50 0.337 / 0.330 / 0.323 ms,
  p95 0.771 / 0.744 / 0.759 ms, max 37.5 / 19.0 / 20.8 ms; one frame over
  16.7 ms. Presenting to a real window costs about 0.3 ms per frame, and
  the slow frames are shorter than offscreen.
- Real window, Wayland: the run does not get past its first step, because
  the desktop scale is 1.25 and the window is 1000 x 750 pixels for
  800 x 600 (SDL_WINDOW_HIGH_PIXEL_DENSITY); the script checks sizes at
  density 1.

## Frame time: reference scenes (offscreen, redraw only)

| scene | mean | p50 | p95 | max |
|---|---|---|---|---|
| graphics_line | 0.153 ms | 0.129 ms | 0.195 ms | 0.704 ms |
| image_fit | 0.035 ms | 0.030 ms | 0.053 ms | 0.976 ms |
| label_wrap | 0.033 ms | 0.014 ms | 0.038 ms | 13.8 ms |
| graphics_basic | 0.015 ms | 0.014 ms | 0.021 ms | 0.357 ms |
| modal_custom | 0.009 ms | 0.008 ms | 0.010 ms | 0.174 ms |
| boxlayout_tests | 0.008 ms | 0.007 ms | 0.008 ms | 0.711 ms |
| fade_half | 0.006 ms | 0.005 ms | 0.007 ms | 0.227 ms |

A redraw of a settled tree walks the canvas and queues SDL draw calls; the
geometry is cached in the instructions. graphics_line is the most
expensive (wide lines: many triangles, and the 1 px lines through
SDL_RenderLines). fade_half draws two cached Fbo textures.

## Where the time goes

callgrind, whole capped run, 487.6 M instructions (inclusive):

| what | Ir | share |
|---|---|---|
| frames (`EventLoop.idle`) | 300.6 M | 61.6% |
| text: Label `textureUpdate` (71 renders) | 230.2 M | 47.2% |
| - measuring words: `getExtents` -> `TTF_GetStringSize` (997 calls) | 196.3 M | 40.2% |
| - of which HarfBuzz shaping (`hb_shape`), FreeType `FT_Load_Glyph` | 182.1 M | 37.3% |
| - drawing glyphs: `renderText` -> `TTF_RenderText_Blended` (220 calls) | 22.9 M | 4.7% |
| start: window and renderer (`SDL_CreateRenderer`: EGL, Mesa, dlopen) | 148.0 M | 30.3% |
| drawing: `on_draw` -> renderer `draw` | 45.4 M | 9.3% |
| - `drawTriangles` (SDL_RenderGeometry) | 41.2 M | 8.4% |
| - of which texture creation on first draw (`Texture.handle`) | 31.1 M | 6.4% |
| `on_flip` -> SDL_RenderPresent | 16.1 M | 3.3% |
| building the widgets (`newShowcase`) | 14.1 M | 2.9% |
| property set and dispatch (`Property.set`, `doDispatch`) | 11.6 M | 2.4% |
| FadeTransition Fbo (`applyFbo`) | 11.2 M | 2.3% |

perf (cycles:u, the same capped run, real hardware) agrees: inclusive
`idle` 61.7%, Label `textureUpdate` 27.7%, `getExtents` 23.0%
(`TTF_GetStringSize` 22.1%), `SDL_CreateRenderer` 21.0%, `on_draw` 11.7%,
SDL_RenderPresent 11.4%, `layoutText` 10.2%, `drawTriangles` 8.1%,
`Texture.handle` 7.0%, `Property.set` 2.8%, `doDispatch` 2.5%, Animation
`update` 1.6%, image loading (`loadTexture`, SDL3_image) 1.1%,
`getPropertyStorage` 1.0%, BoxLayout `doLayout` 0.9%. By library: Mesa
(libgallium) 20.1%, libc 15.5%, nimkivy's own code 14.1%, FreeType 11.3%,
the dynamic loader 9.4%, SDL3 8.6%, HarfBuzz 7.5%, D-Bus 3.7%.
nimkivy's top self-time functions are all under 1%: the Nimony
allocator (`rawAlloc` 0.88%), the renderer's `apply` (0.72%), Clock `tick`
and `processEvents`, `getPropertyStorage` (0.55%, the name lookup), and
string hashing (`hashStrLong`, 0.24%).

## Counts (callgrind run: 568 frames, 223 drawn)

| call | total | per drawn frame |
|---|---|---|
| SDL_RenderGeometry | 1,695 | 7.6 |
| SDL_RenderTexture (fade frames) | 176 | 0.8 |
| SDL_SetRenderClipRect | 1,548 | 6.9 |
| SDL_RenderPresent | 223 | 1 |
| SDL_CreateTextureFromSurface / SDL_CreateTexture | 38 / 8 | |
| property dispatches (`doDispatch`, event and proxy) | 1,545 + 261 | 8.1 |
| events dispatched (`EventDispatcher.dispatch`) | 857 | 3.8 |
| property lookups by name (`getPropertyStorage`) | 15,477 | 69 |
| `Property.set` / `Property.get` | 1,618 / 8,412 | 7.3 / 37.7 |
| layouts (`doLayout`: Box, Float, Anchor, Relative) | 116, 19, 11, 19 | |
| Label renders (`textureUpdate`) / words measured | 71 / 997 | |
| Nimony allocations (`rawAlloc`) / frees | 35,306 / 21,113 | 158 |
| libc malloc / free (mostly Mesa, FreeType, HarfBuzz) | 129,685 / 114,671 | |
| images decoded (`IMG_Load`) / fonts opened | 4 / 9 | |

These are whole-run totals, start included; a frame that changes nothing
but an animated opacity costs a few dispatches, one canvas walk and a
handful of SDL draw calls.

## What the numbers suggest for phase 2

- A steady frame is cheap: about 12 us at the median offscreen, 0.33 ms
  with a real window, against a 16.7 ms budget. Property boxing and name
  lookups are visible (69 lookups and 158 allocations per drawn frame,
  `getPropertyStorage` and `hashStrLong` in the top self-time functions)
  but small: property set and dispatch are 2.4-2.8% of the run.
- The cost is in the frames where text changes. Measuring words with
  `TTF_GetStringSize` (HarfBuzz shaping, hinted FreeType glyph loads, about
  197,000 instructions per call) is 40% of all instructions; each label
  render measures every word again (Kivy's algorithm, `layout_text`). The
  slow frames are text renders (language change, resize, Listen/Stop) and
  first draws (texture upload on the first draw of a screen).
- Startup (window, renderer, EGL and Mesa) is 21-30% of a 9 s run.
- Phase 2 can judge typed properties by `doDispatch`, `getPropertyStorage`
  and `rawAlloc` per frame, and the frame-time distribution above; the
  long frames depend on text measuring and texture creation, which typed
  properties do not touch.

# After phase 2 (2026-11-22)

Phase 2 finished (typed properties, no `Value` or name lookups, `buildUi`,
the word-width cache), measured beside the phase-1 build (git tag
`phase1-complete`, built in a separate worktree) on the same machine,
settings and run as above, the same day.

## Method: what changed

- **Both builds measured again.** The counting method changed (below), and
  the machine's timing drifts during a day (the first runs of both builds
  had a mean of 0.066-0.071 ms, later ones 0.079-0.083 ms for both). So the
  frame times below are phase 1 and phase 2 run alternately (ABABAB),
  pinned to the eight E-cores (`taskset -c 4-11`, `CPUS=4-11
  tools/profile.sh`): with affinity 4-13 the scheduler also put runs on the
  two LP-E cores (2.5 GHz), which perf showed as a second event
  (`cpu_lowpower`) in one run.
- **Dispatches.** In phase 2 a dispatch is a loop over a typed observer
  list (`Observers.live` for a property, `liveReversed` for an event),
  inlined into the generated setters and `dispatchP` procs, so callgrind
  sees no function to count. Built with `-d:countDispatches`,
  `observers.nim` calls a non-inlined counter (`countPropertyDispatch`,
  `countEventDispatch`) at the start of each loop; callgrind counts its
  calls (`tools/profile.sh` builds `bin/tshowcase-count-profile` with the
  define for the callgrind run only; the frame-time and perf builds are
  without it). Phase 1 is counted at the same place: `dispatchValue` (every
  property dispatch, from `Property.doDispatch` and the alias's
  `doDispatch`) and `dispatchEvent`.
- **Recursion.** callgrind writes a recursive call as a function of its own
  (`name'2`); `tools/callcounts.sh` now adds it to the function. The
  "before" table above missed those calls: phase 1 measured again with the
  merge has 2,013 property dispatches (not 1,545 + 261; those are the two
  `doDispatch` methods without their recursive calls), 1,296 event
  dispatches and 16,327 name lookups for 224 drawn frames.
- **Fair count.** A showcase run under valgrind has a different number of
  frames each time, and animations dispatch once per frame, so its totals
  vary from run to run (two phase-2 runs: 2,135 and 2,063 property
  dispatches). The exact check is a deterministic program: `tests/traces`
  and `tests/scenes` (all 18 scenes), each run twice per build under
  callgrind, same counts every time.

## Frame time: the showcase

Offscreen, pinned, alternating, frames that drew:

| build | run | frames | drawn | mean | p50 | p95 | max |
|---|---|---|---|---|---|---|---|
| phase 1 | 1 | 9,915,426 | 31,897 | 0.079 ms | 0.010 ms | 0.048 ms | 93.6 ms |
| phase 2 | 1 | 10,245,332 | 31,379 | 0.081 ms | 0.009 ms | 0.051 ms | 98.5 ms |
| phase 1 | 2 | 10,023,517 | 31,692 | 0.081 ms | 0.010 ms | 0.052 ms | 101.9 ms |
| phase 2 | 2 | 10,173,416 | 31,491 | 0.080 ms | 0.009 ms | 0.050 ms | 92.9 ms |
| phase 1 | 3 | 10,246,323 | 31,539 | 0.080 ms | 0.010 ms | 0.051 ms | 91.5 ms |
| phase 2 | 3 | 10,183,196 | 31,418 | 0.079 ms | 0.009 ms | 0.048 ms | 100.9 ms |

- The same within run-to-run spread, except the median frame, about 1 us
  shorter in phase 2 (0.009 ms in 5 of 6 phase-2 runs, 0.010 ms in all 6
  phase-1 runs, pinned and not).
- Slow frames: 49-50 drawn frames over 1 ms per run in both (36-41 over
  16.7 ms in phase 1, 35-39 in phase 2), about 2.0 s together in both. By
  step (mean of the runs) they are the same frames as before and the same
  length in both builds: start 418 / 425 ms, resize 267 / 265 ms, tile
  press 263 / 259 ms, home button 261 / 284 ms, Listen/Stop 154 / 139 ms,
  language picker 110 / 104 ms, Greek 77 / 67 ms (phase 1 / phase 2). They
  are text measuring and first texture uploads, which phase 2 did not
  change (below).
- Real window, X11 (XWayland, scale 1), alternating, three runs each:
  phase 1 mean 0.376 / 0.338 / 0.384 ms, p50 0.361 / 0.325 / 0.354 ms,
  p95 0.762 / 0.663 / 0.767 ms, max 37.0 / 22.9 / 23.9 ms; phase 2 mean
  0.324 / 0.342 / 0.348 ms, p50 0.332 / 0.347 / 0.340 ms, p95 0.624 /
  0.666 / 0.687 ms, max 23.4 / 22.8 / 21.0 ms. One or two frames over
  16.7 ms per run in both. The same within spread.

## Frame time: reference scenes (offscreen, redraw only)

Mean of two alternating runs, phase 1 / phase 2:

| scene | mean | p50 | p95 |
|---|---|---|---|
| graphics_line | 0.158 / 0.152 ms | 0.128 / 0.121 ms | 0.340 / 0.449 ms |
| image_fit | 0.042 / 0.045 ms | 0.021 / 0.022 ms | 0.036 / 0.035 ms |
| label_wrap | 0.040 / 0.038 ms | 0.015 / 0.015 ms | 0.033 / 0.041 ms |
| graphics_basic | 0.015 / 0.017 ms | 0.015 / 0.015 ms | 0.020 / 0.021 ms |
| modal_custom | 0.009 / 0.009 ms | 0.008 / 0.008 ms | 0.010 / 0.013 ms |
| boxlayout_tests | 0.008 / 0.008 ms | 0.007 / 0.007 ms | 0.010 / 0.009 ms |
| fade_half | 0.007 / 0.007 ms | 0.005 / 0.005 ms | 0.007 / 0.006 ms |

A redraw of a settled tree walks the canvas and touches no property, so
nothing here was expected to change; the differences are within the spread
between runs of one build (graphics_line p95 0.27-0.49 ms, graphics_basic
mean 0.014-0.019 ms over the day).

## Where the time goes

callgrind, whole capped run; phase 1 measured again (576 frames, 224
drawn), phase 2 (572 frames, 224 drawn), Ir inclusive:

| what | phase 1 | phase 2 |
|---|---|---|
| whole run | 489.1 M | 474.7 M (-2.9%) |
| frames (`EventLoop.idle`) | 301.6 M (61.7%) | 292.7 M (61.7%) |
| text: Label `textureUpdate` | 231.4 M, 71 renders | 228.5 M, 73 renders |
| - measuring words: `getExtents` | 197.2 M, 997 calls | 194.2 M, 1,073 calls |
| - of which `TTF_GetStringSize` | 192.0 M, 997 calls | 189.3 M, 508 calls |
| - of which FreeType `FT_Load_Glyph` | 184.3 M | 184.3 M |
| - drawing glyphs: `renderText` | 23.1 M, 220 lines | 23.2 M, 231 lines |
| start: `SDL_CreateRenderer` | 147.9 M | 148.0 M |
| drawing: `on_draw` | 45.2 M | 45.0 M |
| - `drawTriangles` | 41.1 M | 41.1 M |
| - texture creation on first draw (`Texture.handle`) | 31.1 M | 31.5 M |
| `SDL_RenderPresent` | 16.0 M | 15.7 M |
| building the widgets (`newShowcase`) | 14.2 M | 9.5 M |
| FadeTransition Fbo (`applyFbo`) | 11.2 M | 11.3 M |
| property set and dispatch | `Property.set` 11.3 M, `doDispatch` 11.2 M (overlapping) | no function of its own (inlined in each setter) |
| compiled Nim code, self (nimkivy and Nimony's runtime) | 26.1 M | 14.8 M (-43%) |
| - Nimony's runtime (allocator, ORC cycle collector, strings, hashing) | 10.8 M | 5.8 M |
| - phase 1's `event` and `properties` modules | 6.4 M | gone |
| - string hashing (`hashStrLong`) | 2.7 M | 1.3 M, all in the text provider's font and word tables |

- The property work is gone from the profile: phase 2's compiled Nim code
  executes 11.3 M fewer instructions, half of them in the allocator and
  cycle collector (boxed values, copied observer lists) and 6.4 M in phase
  1's property and event modules. Of a 475 M-instruction run that is 2.4%:
  the share the "before" analysis gave property set and dispatch.
- **The word-width cache halved the `TTF_GetStringSize` calls (997 -> 508)
  but saved only 2.7 M instructions (0.6% of the run).** The calls it
  removes are repeats of a word already measured with the same font, and
  SDL_ttf already caches each font's glyphs, so a repeat costs about 5,500
  instructions; the expensive calls are the first measurement of a word at
  a font size (FreeType loading and hinting the glyphs: `FT_Load_Glyph`
  184.3 M in both builds, about 370,000 instructions per remaining call),
  which the cache cannot avoid. The "before" figure of 197,000 per call was
  an average over both kinds. Text measuring is still 40% of the run.
- **Phase 2 renders more label lines** (73 `textureUpdate`s against 71,
  231 rendered lines against 220, 1,073 words measured against 997; the
  same in every run). The renders that differ are intermediate ones, before
  the first layout settles: phase 1 first renders the topic paragraph ("Fig
  trees grow on dry slopes close to the sea.") on one line, phase 2 wrapped
  at a narrow width (five lines); "Figs of Crete" is once on two lines
  instead of one; the language names are rendered twice instead of once;
  "Home", "Language" and the arrows once less. The screens shown and their
  order are the same (tshowcase checks them). It comes from step 7: the
  rendered lines (logged by an LD_PRELOAD wrapper of
  `TTF_RenderText_Blended`) are identical between `phase1-complete` and
  step 6, and between step 7 and now; step 7 rewrote the showcase's trees
  with `buildUi`, which sets a widget's properties and binds its handlers
  in another order than the hand-written trees did. Cost: about 0.1 M
  instructions of `renderText`; no slower frames.
- Startup (window, renderer, EGL, Mesa) and drawing are unchanged: they are
  SDL and Mesa work.

perf (cycles:u, capped run, pinned to 4-11, the same day for both),
phase 1 / phase 2: inclusive `idle` 61.9% / 59.9%, Label `textureUpdate`
26.5% / 27.6%, `getExtents` 22.1% / 22.6% (`TTF_GetStringSize` 20.9% /
21.2%), `SDL_CreateRenderer` 18.6% / 19.7%, SDL_RenderPresent 12.7% /
12.5%, `on_draw` 11.1% / 11.6%, `layoutText` 9.5% / 9.6%, `drawTriangles`
7.1% / 8.4%, `Texture.handle` 6.0% / 6.8%; phase 1's `doDispatch` 2.0%,
`Property.set` 1.9% and `getPropertyStorage` 1.5% have no counterpart in
phase 2. By library: nimkivy's own code 13.6% / 9.2%, Mesa 21.0% / 22.1%,
libc 16.4% / 15.8%, FreeType 10.9% / 11.9%, SDL3 8.9% / 10.0%, the dynamic
loader 8.4% / 8.8%, HarfBuzz 7.2% / 7.2%. Phase 1's top self-time
functions included `getPropertyStorage` (0.76%) and `rawAlloc` (0.80%);
in phase 2 `rawAlloc` is 0.54% and no property function is listed.

## Counts (callgrind runs: phase 1 576 frames, 224 drawn; phase 2 572 frames, 224 drawn)

| call | phase 1 | phase 2 |
|---|---|---|
| SDL_RenderGeometry | 1,699 (7.6 per drawn frame) | 1,667 (7.4) |
| SDL_RenderTexture (fade frames) | 176 | 180 |
| SDL_SetRenderClipRect | 1,556 | 1,552 |
| SDL_RenderPresent | 224 | 224 |
| SDL_CreateTextureFromSurface / SDL_CreateTexture | 38 / 8 | 38 / 8 |
| property dispatches | 2,013 (9.0) | 2,063 (9.2) |
| event dispatches | 1,296 (5.8) | 1,290 (5.8) |
| property lookups by name (`getPropertyStorage`) | 16,327 (73) | **0** (the function and the name tables do not exist) |
| `Property.set` / `Property.get` | 1,760 / 8,417 | none (field reads and generated setters) |
| layouts (Box, Float, Anchor, Relative) | 116, 19, 11, 19 | 118, 19, 12, 19 |
| Label renders / words measured / `TTF_GetStringSize` | 71 / 997 / 997 | 73 / 1,073 / **508** |
| Nimony allocations (`rawAlloc`) / frees | 35,681 / 21,204 (**159** per drawn frame) | 17,708 / 10,816 (**79**) |
| libc malloc / free (Mesa, FreeType, HarfBuzz) | 129,686 / 114,673 | 129,313 / 114,309 |
| images decoded / fonts opened | 4 / 9 | 4 / 9 |

**Dispatches, the exact check** (deterministic programs, each run twice per
build under callgrind, identical both times):

| program | property dispatches, phase 1 / phase 2 | event dispatches |
|---|---|---|
| `tests/traces` (the 8 traces) | 421 / 420 | 262 / 262 |
| `tests/scenes` (the 18 scenes) | 2,401 / 2,399 | 60 / 60 |

Per property (phase 1 logged by name, phase 2 by generated proc) the only
difference is ScreenManager's `transition`: phase 1 set its default
NoTransition through the property, which dispatched once per ScreenManager
(one in the traces, two in the scenes); phase 2 stores the default without
a dispatch, as Kivy does for a property's default. No observer is bound at
that point in either. The same check found one real difference, fixed in
step 9: ScreenManager's `screenNames` alias was not `eager`, so it linked
to `screens` only on first use and missed the dispatches before (phase 1
and Kivy link an alias with dependencies when the instance is made,
`watch_before_use`); with `eager` the counts above match.

## Summary

- Typed properties did what REDESIGN.md expected of them: no name lookups
  (16,327 -> 0), half the Nimony allocations (159 -> 79 per drawn frame),
  the same dispatches, and 43% fewer instructions in nimkivy's compiled
  code. Since that code was 2-3% of the run, frame times did not move,
  except the median frame, about 1 us shorter.
- The word-width cache halved `TTF_GetStringSize` calls but not their cost:
  the slow frames (text at a new size, first texture uploads) are as long
  as before, and text measuring is still 40% of the run.
- Nothing measured is slower beyond the run-to-run spread. Phase 2 does
  render a few more label lines during the showcase's first layout (the
  `buildUi` binding order), about 0.1 M instructions.
