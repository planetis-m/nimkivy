# Profiling baseline (phase 1, 2026-11-22)

The "before" numbers for phase 2 (ROADMAP.md): frame time of the
whole-stack showcase and of the busiest reference scenes, and where the
time goes. Facts only; what they suggest is at the end. Rerun everything
with `tools/profile.sh` (outputs in `tests/out/profile/`).

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
