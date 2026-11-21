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
| 3 | `graphics/instructions.pyx` | `graphics/instructions.nim` | Instruction, InstructionGroup, Canvas (before/after, opacity, clear, add, insert, remove) |
| 3 | `graphics/context_instructions.pyx` | `graphics/context_instructions.nim` | Color, PushMatrix, PopMatrix, Translate (2D) |
| 3 | `graphics/vertex_instructions.pyx`, `vertex_instructions_line.pxi` | `graphics/vertex_instructions.nim` | Rectangle, RoundedRectangle, Ellipse, Triangle, Line, BorderImage: the same vertex generation |
| 3 | `graphics/stencil_instructions.pyx` | `graphics/stencil_instructions.nim` | StencilPush/Use/UnUse/Pop, rectangles only, as clip rectangles |
| 3 | `graphics/texture.pyx` | `graphics/texture.nim` | Texture: size, uvpos/uvsize, flip, from an SDL surface |
| 3 | (replaces `graphics/opengl*.pyx`, `shader.pyx`, `vbo.pyx`, `context.pyx`) | `graphics/renderer.nim` | draws a canvas tree with SDL_Renderer: geometry, colour times opacity, translate stack, clip stack, render targets |
| 4 | `core/image/__init__.py`, `core/image/img_sdl2.py` | `core/image.nim` | CoreImage: load with SDL3_image, the 'kv.texture' cache by filename |
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
- Scenes: `tests/scenes.nim <scene>` renders the same trees as
  `reference/scenes.py`, into `tests/out/<scene>.png` and `.txt`. Then
  `reference/compare.py tests/out` checks them against `reference/out` (see
  ACCEPTANCE.md).
- Traces: `tests/traces.nim` writes `tests/out/traces/*.txt`, which must equal
  `reference/out/traces/*.txt` line for line. Until layer 6 adds the Widget
  lines, `properties.txt` holds the first 44 lines of Kivy's, and
  `run_tests.sh` checks it as a prefix.
- Python, from `nimkivy/`, with
  `PY=/home/ageralis/Projects/philosykos-website/kiosk/.venv/bin/python`:
  run `$PY reference/make_assets.py`, `$PY reference/scenes.py` and
  `$PY reference/traces.py`.
- Do not commit. The coordinator reviews and commits each layer.

## Progress

| Layer | Modules | State |
|---|---|---|
| 1 | event, properties, clock, utils, metrics, config | done: tproperties, tclock, tutils, tmetrics pass in debug and release; traces `events` and `clock` match, `properties` matches its first 44 lines (the rest is layer 6) |
| 2 | sdl3/sdl, sdl3/ttf, sdl3/image | done: tsdl3 passes in debug and release (struct sizes against C; headless smoke test calling every binding: triangle read back, TTF word, PNG load and save, render target, WAV on a dummy audio stream) |
| 3 | graphics/instructions, context_instructions, vertex_instructions, stencil_instructions, texture, renderer | to do |
| 4 | core/image, core/text/text_layout, core/text, core/text/text_sdl3 | to do |
| 5 | input/motionevent, core/window, core/window/window_sdl3, base, app | to do |
| 6 | uix/widget, layout, boxlayout, floatlayout, anchorlayout, relativelayout | to do |
| 7 | uix/label, uix/image, uix/behaviors/button | to do |
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
| graphics/renderer | No multisample antialiasing. Kivy's default is `multisamples = 2`, so edges of ellipses, rounded corners and wide lines are more jagged. The reference scenes use `multisamples = 0`, except `graphics_basic_msaa`. | SDL_Renderer has no MSAA |
| graphics/vertex_instructions | A Line of width exactly 1 is drawn with SDL_RenderLines, where Kivy uses GL_LINE_STRIP. Rasterization can differ by a pixel at the ends and on diagonals. | SDL_Renderer has no GL line primitive |
| uix/screenmanager | Only FadeTransition (and NoTransition): two render-target textures, mixed `t*in + (1-t)*out` with a custom additive blend mode. The other ShaderTransitions and custom shaders (`fs`, `vs`) are not available. SDL's software renderer, which the headless tests use, refuses custom blend modes ("That operation is not supported", seen in tsdl3). | SDL_Renderer has no shaders |
| core/text/text_sdl3 | Glyphs come from SDL3_ttf 3.2 (FreeType and HarfBuzz), where Kivy 2.3.2 uses the SDL2_ttf bundled in its wheel. Hinting, kerning and shaping can move glyphs by a pixel, and word widths can differ by a pixel, which can change where a line wraps. The `label` trace shows any difference in `texture_size`. | a different SDL_ttf version |
| core/image | Decoding uses SDL3_image, where Kivy uses its bundled SDL2_image, so JPEG pixels can differ slightly. | a different SDL_image version |
| event, clock | Observers and Clock callbacks are held strongly. Kivy holds them weakly (WeakMethod, `release_ref`), so a dropped widget that is still bound is not collected, and its callbacks still run. Cycles need `--mm:orc`. | Nimony has no weak references |
| clock, event | An exception in a callback is not caught and passed to an ExceptionManager (clock), or raised to the dispatcher's caller (event). Callbacks cannot raise. | Nimony's error model (no unwinding through closures) |
| event | `bind` does not recognise the same method bound twice through two closures, so it is bound twice. Python's bound methods compare equal. | Nim has no bound methods; a closure compares by its environment |
| clock | `idle` sleeps whole milliseconds (rounded down), where Kivy sleeps microseconds, so each sleep can be up to 1 ms short; the pacing loop then checks again and sleeps or starts the frame. | std/os has only `sleep(milsecs)` |
| tests/tsdl3 | Only struct sizes are compared with C (Nimony's `const` sizeof against the C compiler's), not field offsets. | Nimony has no `offsetOf` (sem: "to implement"), and the run-time address of an importc field is the C compiler's, not Nimony's |
| core/audio | WAV only. Kivy's SDL2 provider also plays OGG, MP3 and FLAC through SDL2_mixer. | SDL3_mixer is not installed; core SDL3 loads only WAV |

## Decisions (coordinator, 2026-11-21, owner: "pragmatic, roll with it")

1. Audio: WAV only through core SDL3; no SDL3_mixer. The kiosk's clips are WAV.
2. ModalView default background: a plain box (atlas images are out of scope).
3. Property system: plain code, no Nimony plugin.
4. ButtonBehavior: a field the widget holds and calls into (Nim has single inheritance), not a mixin.
5. Antialiasing: none for now; tracked as a GAP. Revisit after layer 7 when the kiosk screens can be compared.
6. `Label.shorten`: out of scope until something needs it.
7. Android: layer 10 starts as an investigation; failures are GAPs/bug reports, not workarounds.
