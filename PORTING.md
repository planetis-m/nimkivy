# Porting a subset of Kivy to Nimony (nimkivy)

nimkivy is a narrow port of Kivy 2.3.2 to Nimony, drawing with SDL3 instead of
OpenGL. The subset is in `SCOPE.md`. Within it, nimkivy behaves like Kivy, and
`ACCEPTANCE.md` says how that is checked. `LAYERS.md` splits the work into
layers. Each layer is given to one porter.

## Source of truth

- Kivy 2.3.2 source in `upstream/kivy` (read only, gitignored). Get it with
  `git clone --depth 1 -b 2.3.2 https://github.com/kivy/kivy upstream/kivy`.
  The Cython files (`*.pyx`) are only in this checkout, not in the installed
  wheel.
- Kivy's documentation, at kivy.org/doc/stable and in the docstrings, describes
  the behaviour. Kivy's tests in `upstream/kivy/kivy/tests` are the behaviour
  to keep. The ones listed in `ACCEPTANCE.md` are ported with each module.
- The running Kivy is the installed 2.3.2 at
  `/home/ageralis/Projects/philosykos-website/kiosk/.venv`, which has the same
  sources as `upstream/kivy`. `reference/` holds scripts that run it, and their
  outputs in `reference/out/`.
- `kivy/data/style.kv` holds the default canvases of the in-scope widgets
  (Label, Image, RelativeLayout, ScreenManager, ModalView). There is no kv
  language, so these rules are ported by hand into each widget's module, and
  every kv binding becomes an explicit `bind`.
- Copied files must stay identical to Kivy's: `data/fonts/Roboto-*.ttf` and
  `DejaVuSans.ttf` from `kivy/data/fonts`.
- The first user is the kiosk app at
  `/home/ageralis/Projects/philosykos-website/kiosk/app/ui.py` and `voice.py`.
  It is the reason for the subset. nimkivy does not depend on it.

## Modules

There is one Nimony module per Kivy module, in the same layers. A module
imports only from modules above it, never from below, and never inside a
proc. Source paths are relative to `upstream/kivy/kivy/`, Nimony paths to
`src/nimkivy/`.

| L | Kivy | nimkivy | What |
|---|---|---|---|
| 1 | `event.py`, `_event.pyx` | `event.nim` | EventDispatcher: register_event_type, bind/fbind/unbind_uid, dispatch, property(); also the base `Property`, which the dispatcher links and binds by name (Nim modules cannot import each other) |
| 1 | `properties.pyx` | `properties.nim` | Numeric, String, Boolean, Object, List, Option, Color, VariableList, ReferenceList, Alias properties |
| 1 | `clock.py`, `_clock.pyx` | `clock.nim` | Clock: schedule_once, schedule_interval, create_trigger, unschedule, tick, tick_draw |
| 1 | `utils.py` | `utils.nim` | get_color_from_hex, get_hex_from_color |
| 1 | `metrics.py`, `_metrics.pyx` | `metrics.nim` | Metrics (density, fontscale, dpi), dp, sp, pt, inch, cm, mm, dpi2px |
| 1 | `config.py` | `config.nim` | Config.get/set in memory, for the keys in SCOPE.md |
| 2 | (SDL3 headers) | `sdl3/sdl.nim`, `sdl3/ttf.nim`, `sdl3/image.nim` | raw bindings: only the functions listed in LAYERS.md |
| 3 | `graphics/instructions.pyx` | `graphics/instructions.nim` | Instruction, InstructionGroup, Canvas (before/after, opacity, clear, add, insert, remove), and BindTexture, which every vertex instruction owns |
| 3 | `graphics/context_instructions.pyx` | `graphics/context_instructions.nim` | Color, PushMatrix, PopMatrix, Translate (2D) |
| 3 | `graphics/vertex_instructions.pyx`, `vertex_instructions_line.pxi` | `graphics/vertex_instructions.nim` | Rectangle, RoundedRectangle, Ellipse, Triangle, Line, BorderImage: the same vertex generation (BorderImage's nine slices too, drawn as geometry, not with SDL_RenderTexture9Grid) |
| 3 | `graphics/stencil_instructions.pyx` | `graphics/stencil_instructions.nim` | StencilPush/Use/UnUse/Pop, rectangles only, as clip rectangles |
| 3 | `graphics/texture.pyx` | `graphics/texture.nim` | Texture: size, uvpos/uvsize, flip, from an SDL surface |
| 3 | (replaces `graphics/opengl*.pyx`, `shader.pyx`, `vbo.pyx`, `context.pyx`) | `graphics/renderer.nim` | draws a canvas tree with SDL_Renderer: geometry, colour times opacity, translate stack, clip stack, render targets |
| 4 | `resources.py`, `kivy_data_dir` in `__init__.py` | `resources.nim` | resource_find, resource_add_path, the data directory (`data/`, or `KIVY_DATA_DIR`) |
| 4 | `core/image/__init__.py`, `core/image/img_sdl2.py` | `core/image.nim` | CoreImage: load with SDL3_image, the 'kv.texture' cache by filename; the `source` setters of BindTexture and the vertex instructions |
| 4 | `core/text/text_layout.pyx` | `core/text/text_layout.nim` | layout_text, LayoutLine, LayoutWord: wrapping, line_height, padding |
| 4 | `core/text/__init__.py` | `core/text.nim` | LabelBase: register, resolve_font_name, render, render_lines (halign, valign), texture |
| 4 | `core/text/text_sdl2.py`, `_text_sdl2.pyx` | `core/text/text_sdl3.nim` | the provider: font cache, get_extents, ascent and descent, render a word with SDL3_ttf |
| 5 | `input/motionevent.py` | `input/motionevent.nim` | MotionEvent: pos, sx/sy, ud, grab/ungrab, grab_current, push/pop, transform, is_mouse_scrolling |
| 5 | `core/window/__init__.py` | `core/window.nim` | WindowBase: size, clearcolor, children, add/remove_widget, touch and keyboard events, screenshot |
| 5 | `core/window/window_sdl2.py`, `_window_sdl2.pyx` | `core/window/window_sdl3.nim` | the SDL3 window, its event pump, and mouse and finger input (replaces `input/providers/mouse.py`) |
| 5 | `base.py` | `base.nim` | EventLoop: idle, dispatch_input, post_dispatch_input, runTouchApp, stopTouchApp |
| 5 | `app.py` | `app.nim` | App: build, run, stop, root, title, on_start/on_stop/on_pause/on_resume |
| 6 | `uix/widget.py` | `uix/widget.nim` | Widget: geometry, hints, children, canvas, touch dispatch, opacity, disabled, coordinates |
| 6 | `uix/layout.py` | `uix/layout.nim` | Layout: _trigger_layout, layout_hint_with_bounds |
| 6 | `uix/boxlayout.py`, `uix/floatlayout.py`, `uix/anchorlayout.py`, `uix/relativelayout.py` | `uix/boxlayout.nim`, `uix/floatlayout.nim`, `uix/anchorlayout.nim`, `uix/relativelayout.nim` | the four layouts |
| 7 | `uix/label.py` | `uix/label.nim` | Label, plus its style.kv canvas |
| 7 | `uix/image.py` | `uix/image.nim` | Image (not AsyncImage), plus its style.kv canvas |
| 7 | `uix/behaviors/button.py` | `uix/behaviors/button.nim` | ButtonBehavior |
| 8 | `animation.py` | `animation.nim` | Animation (not Sequence or Parallel), AnimationTransition |
| 8 | `uix/screenmanager.py` | `uix/screenmanager.nim` | Screen, ScreenManager, TransitionBase, NoTransition, FadeTransition |
| 8 | `uix/modalview.py` | `uix/modalview.nim` | ModalView, plus its style.kv canvas |
| 9 | `core/audio/__init__.py`, `core/audio/audio_sdl2.pyx` | `core/audio.nim` | SoundLoader, Sound: WAV through SDL3 audio streams |
| – | `__init__.py` | `nimkivy.nim` | re-exports the public modules |

## How the code is written

- **Names:** Kivy's names in Nim camelCase: `sizeHint`, `onTouchDown`,
  `addWidget`, `scheduleOnce`, `texture_size` becomes `textureSize`. Types
  keep Kivy's class names (`Widget`, `BoxLayout`, `ModalView`). Option values
  are Nim enums named after Kivy's strings (`fitCover`, `halignJustify`), and
  `parseEnum`-style helpers accept Kivy's strings.
- **Objects:** widgets and other dispatchers are `ref object of` their Kivy
  base class. An overridable Kivy method (on_touch_*, add_widget, do_layout,
  collide_point, the default `on_*` handlers) is a `method`. Everything else is
  a proc.
- **Mixins:** Nim has single inheritance. ButtonBehavior is an object held by
  the widget (`PillButton = ref object of BoxLayout` with a `button` field).
  The widget's `onTouchDown`, `onTouchMove` and `onTouchUp` methods call it
  first, and it calls `procCall` on the parent class, exactly where Kivy's MRO
  calls `super()`.
- **Properties and events: plain code, no plugin.** Kivy's semantics live in
  the ordering of observers, and in ReferenceList and Alias dependencies, so
  every property is stored the same way. A class registers named property
  descriptors once (kind, default, allownone, options, dependencies). Each
  instance keeps a seq of storages with values and observers. Thin typed
  accessors (`width`, `width=`) sit on top, one or two lines per property.
  Binding by name (`fbind("size", cb)`) is needed by Animation and the
  layouts. Callbacks are `{.closure.}` procs, and `fbind` returns the uid that
  `unbindUid` takes. A plugin would only save about 90 two-line accessors. In
  exchange it would add a build step and NIF debugging, which is clearly
  worse. Reconsider only if the accessors turn out to be error-prone.
- **Kivy's kwargs:** constructors take no property arguments. The caller sets
  properties after `newX()`. This gives the same result once the clock has
  ticked, because layouts are triggered with a timeout of -1.
- **Simple, flat code:** plain procs, objects, seq, string and Table. No
  macros, templates or generics unless the code would be worse without them.
- **Comments:** a `##` doc comment on every exported proc. A `#` comment says
  why at every non-obvious step. Where code follows a Kivy function, a comment
  names the Kivy file and function.
- **Errors:** follow nimony-error-handling. A missing image, font or WAV file
  is a `nil` texture, font or sound plus a log line, as in Kivy, never a
  crash. An SDL init failure stops the app at start. Callbacks do not raise.
- **No workarounds:** write the natural code. Where the stdlib falls short,
  add a `# GAP:` comment and a Gaps row. New bugs are recorded with
  nimony-bug-reporting and go to `planetis-m/nimony-bugs-llms`.
- **Same behaviour as Kivy** where the stdlib and SDL3 allow, including Kivy's
  quirks (for example, observer order depends on when an alias was first
  bound). Differences go under Gaps.
- **Skills:** read nimony-porting, nimony-error-handling,
  nimony-nim2-differences, nim-style-guide, nim-doc-comments,
  nim-code-organization and nim-testing before writing. For layer 2, also read
  nim-c-bindings and nim-c-wrappers.

## Build and tests

- Never run two Nimony builds at once. Each build uses its own `--nimcache`.
- **Run everything:** `./run_tests.sh` (from anywhere). It builds every
  `tests/t*.nim` and `tests/traces.nim` in debug and in `-d:release` with
  `nimony c --mm:orc --path:src --nimcache:nimcache/<name>-<mode> -o:bin/<name>-<mode>`,
  runs them, and compares the traces with
  `$PY reference/compare.py tests/out --traces <name> ...`. `NIMONY` and `PY`
  override the Nimony checkout and the Python with Kivy.
- Build:
  `nimony c --mm:orc --path:src --nimcache:nimcache/<name> -o:bin/<name> <file>.nim`.
  `--mm:orc` is needed because widgets and their closures form cycles (see
  Gaps). SDL is linked with `{.passL: "-lSDL3 -lSDL3_ttf -lSDL3_image".}` in
  `sdl3/*.nim`.
- Tests: one `tests/t<module>.nim` per module, using `block` tests and
  `assert` (Nimony has no `doAssert`; `assert` stays on in release).
  `run_tests.sh` runs every `t*.nim` in debug and in `-d:release`. It exports
  `SDL_VIDEO_DRIVER=offscreen SDL_RENDER_DRIVER=software SDL_AUDIO_DRIVER=dummy`,
  so tests that open a window or an audio device are headless and
  deterministic; run a test by hand with the same variables. Tests run from
  the repository root and read fonts from `reference/assets/fonts/` (Source
  Sans 3 and Noto Serif, SIL Open Font License, licence files beside them).
- Scenes: `tests/scenes.nim <scene> ...` renders the same trees as
  `reference/scenes.py`, into `tests/out/<scene>.png` and `.txt`, through
  the real Window. Then `reference/compare.py tests/out <scene> ...` checks
  them against `reference/out` (see ACCEPTANCE.md): the geometry exactly,
  the pixels within budget. `run_tests.sh` runs the scenes on SDL's OpenGL renderer
  (`SDL_RENDER_DRIVER=opengl`, through the offscreen driver's EGL), which
  matches GL's rasterization and supports Kivy's blend mode; the tests stay
  on the software renderer (Gaps).
- Geometry: `reference/graphics_points.py` writes
  `reference/out/graphics_points.txt`, the points, radii and normalised Line
  shapes Kivy computes, and the children of a Canvas after add, insert,
  remove and clear. `tvertex_instructions` and `tinstructions` compare with
  it.
- Traces: `tests/traces.nim` writes `tests/out/traces/*.txt`, which must equal
  `reference/out/traces/*.txt` line for line.
- Python, from `nimkivy/`, with
  `PY=/home/ageralis/Projects/philosykos-website/kiosk/.venv/bin/python`:
  run `$PY reference/make_assets.py`, `$PY reference/scenes.py`,
  `$PY reference/traces.py` and `$PY reference/graphics_points.py`.
- Do not commit. The coordinator reviews and commits each layer.

## Progress

| Layer | Modules | State |
|---|---|---|
| 1 | event, properties, clock, utils, metrics, config | done: tproperties, tclock, tutils, tmetrics pass in debug and release; traces `events` and `clock` match, `properties` matches its first 44 lines (the rest is layer 6) |
| 2 | sdl3/sdl, sdl3/ttf, sdl3/image | done: tsdl3 passes in debug and release (struct sizes against C; headless smoke test calling every binding: triangle read back, TTF word, PNG load and save, render target, WAV on a dummy audio stream) |
| 3 | graphics/instructions, context_instructions, vertex_instructions, stencil_instructions, texture, renderer | done: tinstructions and tvertex_instructions pass in debug and release (test_line_rounded_rectangle; 2632 numbers of Kivy's geometry, 8 of them 1 ulp off; the canvas children after add, insert, remove and clear; opacity, colour state, translate, stencil clip drawn headless). Scenes, pixels only, on the OpenGL renderer: graphics_basic 0.00%, graphics_line 0.10%, canvas_order 0.00%, graphics_basic_msaa 0.27% (budgets 0.5% and 3%). Added SDL_GetCurrentRenderOutputSize to sdl3/sdl. |
| 4 | resources, core/image, core/text/text_layout, core/text, core/text/text_sdl3 | done: ttext (test_unicode_name; Roboto and registered fonts, bold/italic fallback, a name in data/fonts, missing font, wrapping, a long Greek word split between characters, pixels in the label colour, texture reuse, centring) and timage_core (PNG and JPEG sizes, flipped, missing file, cache, `source` on instructions) pass in debug and release; trace `label` matches all 20 lines; scene graphics_texture 0.00% (OpenGL renderer, budget 1%). Copied `data/fonts/` from Kivy. Added SDL_CreateSurface, SDL_BlitSurface, SDL_SetSurfaceBlendMode, SDL_SetSurfaceAlphaMod to sdl3/sdl, and TTF_RenderText_Solid, TTF_WasInit, TTF_GetFontHinting, TTF_GetFontKerning to sdl3/ttf (all called in tsdl3). Layer 3 changes: BindTexture's recording `source=` became `setSource` (the loading `source=` is in core/image), and Texture got `blitData`. Bugs filed: planetis-m/nimony-bugs-llms#331, #332 (comment on #311). |
| 5 | input/motionevent, core/window, core/window/window_sdl3, base, app | done: tmotionevent (grab and ungrab, push/pop/apply_transform_2d, positions, `ud`), twindow (screenshot numbering, children newest first, observer before the default handler, key 27 with and without `exit_on_escape`, and a headless run on the offscreen driver: the window opens, draws, takes a screenshot, gets finger, mouse and key events through SDL_PushEvent and stops on key 27) and tapp (test_graphics_app; the App lifecycle, with on_stop twice as Kivy 2.3.2 does when `stop()` is called inside `run()`) pass in debug and release; trace `touch` matches all 92 lines, with stub widgets in `tests/stubs.nim` until Widget and ButtonBehavior exist (layers 6 and 7 replace the stubs in `tests/traces.nim`). Added SDL_GetWindowSize, SDL_SetWindowSize, SDL_WaitEvent, SDL_PushEvent and SDL_EVENT_TERMINATING to sdl3/sdl (called in tsdl3). The event loop sets `Clock.maxFps` from Config when it starts, and the window sets Metrics' platform dpi (and density on Android). Bug filed: planetis-m/nimony-bugs-llms#333 (a method with a closure parameter: providers' `update` returns the events instead of taking `dispatch_fn`). |
| 6 | uix/widget, layout, boxlayout, floatlayout, anchorlayout, relativelayout | done: twidget (test_widget's 8 tests, test_uix_widget's 3 index tests, canvas before/after, walk, opacity, inherited disabled and touches, coordinates), tlayout (test_instantiation; layout_hint_with_bounds and BoxLayout minimum_size and placement against Kivy's numbers; the layout trigger; AnchorLayout padding) and trelativelayout (test_uix_relativelayout's 2 tests, test_uix_translate_coordinates for Widget and RelativeLayout; touches in local coordinates; the Translate following pos) pass in debug and release; traces `properties` (all 50 lines, now through Widget and BoxLayout) and `touch` (Widget and FloatLayout; ButtonBehavior still written out in the trace until layer 7) match exactly. Scenes through the real Window on the OpenGL renderer, geometry `.txt` exact for all nine: canvas_order, boxlayout_tests, boxlayout_hints, floatlayout_hints, anchorlayout_tests 0.00% of pixels; graphics_basic 0.00%, graphics_line 0.10%, graphics_texture 0.00%, graphics_basic_msaa 0.27% (now widgets too). `tests/stubs.nim` keeps only UnitTestTouch; twindow's root doubles are bare WidgetBase objects (a Widget would open the window before its headless run). core/window's `updateChildsize` reads a `pos_hint` value only for the keys it uses (`pos` and `center` hold pairs). No new GAPs; no Nimony bugs found. |
| 7 | uix/label, uix/image, uix/behaviors/button | done: tlabel (test_basic_app, moved from tapp; texture_size through the widget against the `label` trace numbers; one render per Clock trigger; empty text and justify; the disabled colour; the style.kv rectangle at `int(center - texture_size / 2)`; font_hinting None), timage (norm_image_size for the 4 fit modes x 3 images against `image_fit.txt`; texture_size and image_ratio; missing file and empty source; the shared cached texture and `reload`; the style.kv canvas with its stencil) and tbutton (press and release through the event loop, release off the button, always_release, min_state_time and the cancelled delayed release, trigger_action, children first, mouse scrolling, the `touch.ud` guard) pass in debug and release. Traces: `touch` (all 92 lines, now through the real ButtonBehavior) and `label` (now through the Label widget, as traces.py) match exactly; events, clock and properties still do. Scenes on the OpenGL renderer: label_align, image_fit, image_misc geometry exact, 0.00% of pixels; label_wrap 0.50% and label_default 0.00% of pixels, geometry exact except one `texture_size` each, 1 px narrower (the SDL_ttf GAP below; run_tests.sh compares these two by pixels); graphics_texture, now with Label and Image in the program, still 0.00%. Layer 1 fix: `doDispatch` dispatches a copy of the stored value, because an observer that reads a ReferenceList replaced it while the later observers read it by reference (filed: planetis-m/nimony-bugs-llms#334, `bug-reports/07`). Layer 3 change: `TextureObj` is `object of RootObj`, so a property holds a Texture (`toValue`, `toTexture` in graphics/texture). No new GAPs. |
| 8 | animation, uix/screenmanager, uix/modalview | to do |
| 9 | core/audio | to do |
| 10 | Android build notes and smoke test | to do |

## Gaps

These are the places where nimkivy is less accurate than Kivy, because
Nimony's stdlib or SDL3 lacks something or has a bug. They are left for
another day. The rows below are foreseen. A porter confirms each one where the
code meets it, adds the `# GAP:` comment, and edits the row.

| Where | What is inaccurate | Because |
|---|---|---|
| graphics/renderer | No multisample antialiasing. Kivy's default is `multisamples = 2`, so edges of ellipses, rounded corners and wide lines are more jagged. The reference scenes use `multisamples = 0`, except `graphics_basic_msaa`: there 0.27% of the pixels differ (OpenGL renderer; 0.39% on the software renderer), within its 3% budget. | SDL_Renderer has no MSAA |
| graphics/renderer | A Line of width exactly 1 is drawn with SDL_RenderLines, where Kivy uses GL_LINE_STRIP. Rasterization can differ by a pixel at the ends and on shallow diagonals: graphics_line 0.10% of pixels (OpenGL renderer), all on the 1 px lines. | SDL_Renderer has no GL line primitive |
| graphics/renderer | On SDL's software renderer, long thin triangles (wide lines) cover up to a pixel more or less than GL's pixel-centre rule: graphics_line 0.91% of pixels differ there (over the 0.5% budget), against 0.10% on the OpenGL renderer, which matches GL exactly (graphics_basic 0.00%, software 0.21%). The scenes run on the OpenGL renderer. | SDL's software triangle rasterizer is less precise than GL's |
| graphics/renderer | Where the SDL driver refuses custom blend modes (the software renderer of the headless tests), blending is SDL_BLENDMODE_BLEND: the colour is Kivy's, but the target's alpha is `srcA + dstA * (1 - srcA)` instead of Kivy's `srcA + dstA`. Only render-target textures (FadeTransition) show it. The OpenGL renderer uses Kivy's mode. | SDL's software renderer does not support SDL_ComposeCustomBlendMode |
| graphics/renderer | A stencil mask is the bounding box of what is drawn between StencilPush and StencilUse: exact for one Rectangle, which is all Kivy's own uses (Image, ScreenManager), but not for other shapes or several rectangles. | SDL_Renderer has no stencil buffer, only a clip rectangle |
| graphics/renderer | A wide Line drawn with alpha below 1 blends its overlapping triangles (joints, caps, a closed end) twice, where Kivy draws it once through a stencil. | SDL_Renderer has no stencil buffer |
| uix/screenmanager | Only FadeTransition (and NoTransition): two render-target textures, mixed `t*in + (1-t)*out` with a custom additive blend mode. The other ShaderTransitions and custom shaders (`fs`, `vs`) are not available. SDL's software renderer, which the headless tests use, refuses custom blend modes ("That operation is not supported", seen in tsdl3). | SDL_Renderer has no shaders |
| core/text/text_sdl3 | Glyphs come from SDL3_ttf 3.2 (FreeType and HarfBuzz), where Kivy 2.3.2 uses the SDL2_ttf bundled in its wheel. Hinting, kerning and shaping can move glyphs by a pixel, and word widths can differ by a pixel, which can change where a line wraps. Measured: the `label` trace matches all 20 `texture_size` lines (Roboto, DejaVu Sans, sizes 15 and 40, bold, Greek, wrapping, line_height, padding, justify, a long word). In the label scenes two words are 1 px narrower ("overflows" in Roboto 20: 85 against 86; "regular," in DejaVu Sans 24: 94 against 95), so one `texture_size` in label_default (439 against 440) and one in label_wrap (251 against 252) differ; pixels: label_align 0.00%, label_wrap 0.50%, label_default 0.00% (budget 3%). | a different SDL_ttf version |
| core/image | Decoding uses SDL3_image, where Kivy uses its bundled SDL2_image, so JPEG pixels can differ slightly. Measured: graphics_texture (PNG and JPEG) 0.00% of pixels over the tolerance. | a different SDL_image version |
| resources | Without `KIVY_DATA_DIR`, the data directory (fonts) is `data` under the current directory, where Kivy's is beside its package, wherever the program runs from. Tests run from the repository root. | Nimony has no `currentSourcePath`; `instantiationInfo` gives only the file name |
| event, clock, input/motionevent | Observers, Clock callbacks and a touch's grabbing widgets are held strongly. Kivy holds them weakly (WeakMethod, `release_ref`, `weakref.ref` in `grab`), so a dropped widget that is still bound is not collected, and its callbacks still run; a dropped widget that grabbed a touch still gets its moves and end. Cycles need `--mm:orc`. | Nimony has no weak references |
| clock, event, base | An exception in a callback is not caught and passed to an ExceptionManager (clock, the event loop's `mainloop`), or raised to the dispatcher's caller (event). Callbacks cannot raise. | Nimony's error model (no unwinding through closures) |
| event | `bind` does not recognise the same method bound twice through two closures, so it is bound twice. Python's bound methods compare equal. | Nim has no bound methods; a closure compares by its environment |
| clock | `idle` sleeps whole milliseconds (rounded down), where Kivy sleeps microseconds, so each sleep can be up to 1 ms short; the pacing loop then checks again and sleeps or starts the frame. | std/os has only `sleep(milsecs)` |
| tests/tsdl3 | Only struct sizes are compared with C (Nimony's `const` sizeof against the C compiler's), not field offsets. | Nimony has no `offsetOf` (sem: "to implement"), and the run-time address of an importc field is the C compiler's, not Nimony's |
| core/window/window_sdl3 | `on_pause` and `on_resume` run when the lifecycle event is read from SDL's queue, at the next frame, not in an SDL event filter as the event happens. On Android `on_pause` can therefore come only after the app is back in the foreground (SDL blocks the main thread while paused). Not seen on the desktop. | nimkivy installs no SDL event filter: its callback runs on another thread, and the dispatchers are not thread safe |
| core/window/window_sdl3 | On Android the density is SDL's display content scale and the dpi 160 times it; Kivy reads Android's `scaledDensity` (which includes the user's font scale) and `densityDpi`. The font scale stays 1. | SDL3 exposes only the content scale; JNI is out of scope |
| core/window, core/window/window_sdl3, app | On Android, key 27 that no observer handles is consumed without moving the task to the back (Kivy: `mActivity.moveTaskToBack(True)`), and `App.stop` or an `on_pause` that returns false stop the app as on the desktop (Kivy: `mActivity.finishAndRemoveTask()`). | SDL3 has no call for these; JNI is out of scope |
| core/audio | WAV only. Kivy's SDL2 provider also plays OGG, MP3 and FLAC through SDL2_mixer. | SDL3_mixer is not installed; core SDL3 loads only WAV |

## Design differences (not gaps: chosen, not forced)

- `core/image`: the texture cache by file name never expires; Kivy's Cache drops entries after 60 s. A kiosk loads a fixed set of photos, so keeping them is fine.
- `core/text`: a label's texture is filled at once, not on first draw; Label always refreshes after a change, so the result is the same.
- Font lookup searches only `data/fonts` (and registered paths), not the system font folders.
- `core/window`: Kivy's `WidgetBase` (from `uix/widget.py`) lives here, with what the window and the event loop need of a widget: the `parent` and `children` properties, a `canvas` field (pass `canvas: newCanvas()` to the constructor), the `on_touch_*` events whose default handlers are the `onTouchDown`/`Move`/`Up` methods, and `getRootWindow`, `toWidget`, `toParent`, `toWindow`, `addWidget`, `removeWidget` as methods. `WindowBase` is a `WidgetBase`, so a widget's parent can be the window. Widget (layer 6) is a `WidgetBase` and overrides these, except `getRootWindow`, whose base already is Kivy's Widget.get_root_window; it adds `toLocal`.
- `core/window`: the window reads a root widget's hints by property name (`size_hint`, `size_hint_min`, `size_hint_max`, `pos_hint`) and skips a widget without them.
- `uix/widget`: `pos_hint` is a list of `(key, value)` pairs in the order the keys were given (a Python dict's order), compared as a dict (any order) so an equal hint does not dispatch; the value is a number, or a pair for `pos` and `center`. `w.posHint = {"top": 0.9}` sets numeric hints, `setPosHint` any. `size_hint`, `size_hint_min` and `size_hint_max` read as `Opt[float]` (none is Kivy's None).
- `uix/widget`, `uix/layout`: a WidgetException (adding a widget to itself, or one that has a parent) and instantiating the abstract Layout stop the program with Kivy's message, as `core/window` does; they are programming errors (nimony-error-handling), and the tests check them by running the test program again.
- `uix/widget`: `walk` returns the whole walk as a seq, not a generator; with `loopback` it stops at the start widget, as Kivy's `walk` does.
- `uix/layout`: the layout keeps the uids of the trigger it binds on each child and unbinds them in `remove_widget`, where Kivy funbinds the same bound method by name.
- `core/window/window_sdl3`: `Window` exists from the start, but its system window opens when the event loop needs it (`EventLoop.ensureWindow`: `App.run` before `build`, `runTouchApp` with a widget), and it reads Config's size then. Kivy opens it when `kivy.core.window` is imported, which Kivy programs do after setting Config; a Nim program's code runs after every module is loaded. A metric read before the window opens (`dp`, `sp`) uses the defaults (dpi 96, density 1), where Kivy would open the window to read it.
- `core/window`, `base`, `app`: Kivy calls `stopTouchApp`, `EventLoop.quit` and `App.get_running_app()` from inside the window module (local imports). Here those modules come later, so `base` fills in the window's `stopTouchApp` and `quitEventLoop` hooks, `App` sets `Window.runningApp` (which `getRunningApp` reads), and the event loop removes the closed window from its listeners with an `on_close` observer.
- `uix/behaviors/button`: ButtonBehavior (decision 4) is in two parts. `addButtonBehavior(cls)` declares its properties (`state`, `last_touch`, `min_state_time`, `always_release`) and events (`on_press`, `on_release`) on the widget's class, so they are the widget's, as with Kivy's mixin; a subclass overrides the default handlers with `setEventHandler`. The `ButtonBehavior` object, made by `newButtonBehavior(widget)` after the widget is set up, keeps the touch time and the delayed release. The widget's touch methods call `onTouchDown`/`Move`/`Up` on it with `inherited`, a closure that calls the parent class's method through `procCall` where Kivy's MRO calls `super()`. `state` reads as the enum `ButtonState`.
- `uix/label`, `uix/image`: the subclass recipe is the widget's: `Label(cls: LabelClass, canvas: newCanvas())` then `initLabel` (`initImage`). The core label is made in `initLabel`. `font_size` defaults to `sp(15)`, resolved when the label is set up (the window is open by then), as Kivy resolves `'15sp'` per instance. `font_hinting` None is `hintingNone`.
- `graphics/texture`: a Texture is a `RootRef` (`TextureObj` is `object of RootObj`), so Label's and Image's `texture` properties hold it like Kivy's ObjectProperty.
- `app`: the default `build` returns nil where Kivy's returns a new Widget, because Widget comes after `app` in the module order. An app overrides `build`.
- `core/window/window_sdl3`: every SDL finger makes a touch on every platform (SCOPE.md), where Kivy uses SDL's fingers only on Android and iOS; SDL's mouse events made from touches are switched off (`SDL_HINT_TOUCH_MOUSE_EVENTS`) and ignored. The mouse makes touches as Kivy's mouse provider does, but without multitouch simulation: a right click ends on release.
- `base`: the postproc modules (double and triple tap, dejitter, retain touch, ignore list, calibration) are not ported, so `is_double_tap` and `is_triple_tap` do not exist.
- `core/window/window_sdl3`: `screenshot` draws the frame again and reads it before it is shown, because SDL's frame cannot be read after `SDL_RenderPresent`; the picture is the one Kivy reads from its GL buffer. It is saved as RGB, as Kivy does.
- Kivy's quirks kept: `App.run` dispatches `on_stop` again after `stop()`; `App._stop` removes every second root widget (it removes while iterating); `EventLoop.stop` also removes the window's finger provider, so a second `run` in the same process has no finger touches; `WindowSDL.set_title` shows the title without changing `Window.title`.

## Decisions (coordinator, 2026-11-21, owner: "pragmatic, roll with it")

1. Audio: WAV only through core SDL3; no SDL3_mixer. The kiosk's clips are WAV.
2. ModalView default background: a plain box (atlas images are out of scope).
3. Property system: plain code, no Nimony plugin.
4. ButtonBehavior: a field the widget holds and calls into (Nim has single inheritance), not a mixin.
5. Antialiasing: none for now; tracked as a GAP. Revisit after layer 7 when the kiosk screens can be compared.
6. `Label.shorten`: out of scope until something needs it.
7. Android: layer 10 starts as an investigation; failures are GAPs/bug reports, not workarounds.
8. Reference scenes are compared on SDL's OpenGL renderer (the tablet draws through its GPU with OpenGL ES); unit tests stay on the software renderer. (coordinator, layer 3 review)
