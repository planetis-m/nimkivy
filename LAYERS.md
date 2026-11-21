# nimkivy layers

The port is split into layers in dependency order. One agent ports one
layer, with that layer's tests. The coordinator reviews and commits a layer
before the next one starts. Every porter reads `PORTING.md` (conventions,
Gaps) and `SCOPE.md` (what to port and how it must behave) first. Kivy paths
are relative to `upstream/kivy/kivy/`, and test names are in `ACCEPTANCE.md`.

A layer is done when:

- its modules compile in debug and in `-d:release`
- its ported Kivy tests and its trace lines pass
- its scenes, where it has any, pass `reference/compare.py`
- every inaccuracy has a `# GAP:` comment and a row in PORTING.md
- the Progress row says "done"

## 1. Properties, events, clock (headless)

- **Modules:** `event`, `properties`, `clock`, `utils`, `metrics`, `config`.
- **Kivy sources:** `_event.pyx`, `event.py`, `properties.pyx` (Property,
  NumericProperty, StringProperty, BooleanProperty, ObjectProperty,
  ListProperty, OptionProperty, ColorProperty, VariableListProperty,
  ReferenceListProperty, AliasProperty, PropertyStorage), `_clock.pyx`,
  `clock.py` (ClockBase, ClockEvent, FreeClockEvent is not needed),
  `utils.py`, `_metrics.pyx`, `metrics.py`, `config.py` (only the keys in
  SCOPE.md).
- **Design:** properties as plain code (PORTING.md "Properties and events").
  The registration API must let a later layer declare a class's properties
  in one place, and let `Animation` and the layouts look properties up by
  name.
- **Tests:** `tproperties`, `tclock`, `tutils`, `tmetrics`. Traces:
  `properties` (only the EventDispatcher parts; the Widget lines wait for
  layer 6), `events`, `clock`.
- **Done:** the tests pass, and the `events` and `clock` traces match. The
  `properties` trace is finished in layer 6, but its ReferenceList and Alias
  order is already reproduced here with a small test dispatcher that has
  `x`, `y`, `pos`, `width`, `height`, `size`, `right`, `top` and `center`.

## 2. SDL3 raw bindings

- **Modules:** `sdl3/sdl.nim`, `sdl3/ttf.nim`, `sdl3/image.nim`. These are raw
  bindings (nim-c-bindings) against `/usr/include/SDL3*`: C names, `header`
  pragmas, `distinct` integer types and constants for enums and flags,
  `{.passL.}` for `-lSDL3`, `-lSDL3_ttf` and `-lSDL3_image`. Only the
  functions below. Add more only when a later layer needs one, and note it
  in that layer's review.
- **SDL3:** `SDL_Init`, `SDL_Quit`, `SDL_GetError`, `SDL_SetHint`
  (`SDL_HINT_TOUCH_MOUSE_EVENTS`, `SDL_HINT_ANDROID_TRAP_BACK_BUTTON`),
  `SDL_free`. Window: `SDL_CreateWindow`, `SDL_DestroyWindow`,
  `SDL_SetWindowTitle`, `SDL_GetWindowSizeInPixels`,
  `SDL_GetWindowDisplayScale`, `SDL_GetDisplayForWindow`,
  `SDL_GetDisplayContentScale`. Renderer: `SDL_CreateRenderer`,
  `SDL_DestroyRenderer`, `SDL_SetRenderDrawColorFloat`,
  `SDL_SetRenderDrawBlendMode`, `SDL_RenderClear`, `SDL_RenderPresent`,
  `SDL_RenderGeometry`, `SDL_RenderLines`, `SDL_RenderTexture`,
  `SDL_RenderTexture9Grid`, `SDL_SetRenderClipRect`, `SDL_SetRenderTarget`,
  `SDL_RenderReadPixels`. Textures and surfaces: `SDL_CreateTexture`,
  `SDL_CreateTextureFromSurface`, `SDL_DestroyTexture`,
  `SDL_GetTextureSize`, `SDL_SetTextureBlendMode`,
  `SDL_SetTextureColorModFloat`, `SDL_SetTextureAlphaModFloat`,
  `SDL_SetTextureScaleMode`, `SDL_ComposeCustomBlendMode`,
  `SDL_ConvertSurface`, `SDL_DestroySurface`. Events: `SDL_PollEvent`,
  `SDL_WaitEventTimeout`, the `SDL_Event` union (quit; window
  resized/pixel-size-changed/exposed/close-requested; key down/up; mouse
  button and motion; mouse wheel; finger down/up/motion; will-enter- and
  did-enter-background, will-enter- and did-enter-foreground),
  `SDL_TOUCH_MOUSEID`, the `SDLK_*` and `SDL_KMOD_*` constants Kivy maps.
  Audio: `SDL_LoadWAV`, `SDL_OpenAudioDeviceStream`,
  `SDL_PutAudioStreamData`, `SDL_GetAudioStreamQueued`,
  `SDL_ClearAudioStream`, `SDL_ResumeAudioStreamDevice`,
  `SDL_PauseAudioStreamDevice`, `SDL_SetAudioStreamGain`,
  `SDL_DestroyAudioStream`.
- **SDL3_ttf:** `TTF_Init`, `TTF_Quit`, `TTF_OpenFont`, `TTF_CloseFont`,
  `TTF_SetFontHinting`, `TTF_SetFontKerning`, `TTF_SetFontStyle`,
  `TTF_GetFontHeight`, `TTF_GetFontAscent`, `TTF_GetFontDescent`,
  `TTF_GetStringSize`, `TTF_RenderText_Blended`. Later, for Arabic:
  `TTF_SetFontDirection` and `TTF_SetFontScript`.
- **SDL3_image:** `IMG_Load`, `IMG_SavePNG`.
- **Tests:** `tsdl3`. Check `sizeof` and field offsets of `SDL_Vertex`,
  `SDL_FColor`, `SDL_FRect`, `SDL_Rect` and the event structs against C. Run
  a smoke test under `SDL_VIDEO_DRIVER=offscreen`: create a window and a
  software renderer, draw one coloured triangle with `SDL_RenderGeometry`,
  read the pixels back, render a word with TTF, and load
  `reference/assets/landscape.png`.
- **Done:** the smoke test passes headless. No ergonomic layer: the wrappers
  belong to layers 3 to 5.

## 3. Graphics instructions and renderer

- **Modules:** `graphics/instructions`, `context_instructions`,
  `vertex_instructions`, `stencil_instructions`, `texture`, `renderer`.
- **Kivy sources:** `graphics/instructions.pyx` (Instruction,
  InstructionGroup, Canvas, CanvasBase: `before`/`after`/`opacity`/
  `add`/`insert`/`remove`/`clear`/`indexof`/`length`/`has_before`),
  `context_instructions.pyx` (Color, PushMatrix, PopMatrix, Translate),
  `vertex_instructions.pyx` (Rectangle, RoundedRectangle, Ellipse, Triangle,
  BorderImage: port the vertex and texture-coordinate generation as it is),
  `vertex_instructions_line.pxi` (Line: points, `build_extended` with caps
  and joints, circle, rectangle, rounded_rectangle radius normalisation),
  `stencil_instructions.pyx`, `texture.pyx` (size, `tex_coords`, flip).
- **Renderer** (new): walk the canvas tree. Keep a current colour (Color's
  rgba times the accumulated canvas opacity), a translate stack and a
  clip-rectangle stack. Turn each vertex instruction into `SDL_Vertex`
  triangles with Kivy's y-up coordinates flipped to SDL's, and draw them with
  `SDL_RenderGeometry` (textured when `texture` is set). Lines of width exactly
  1 use `SDL_RenderLines`. BorderImage uses `SDL_RenderTexture9Grid`.
  Blending is Kivy's `glBlendFuncSeparate(SRC_ALPHA, ONE_MINUS_SRC_ALPHA,
  ONE, ONE)` (`instructions.pyx`), built once with
  `SDL_ComposeCustomBlendMode` and used for geometry and textures. It is not
  `SDL_BLENDMODE_BLEND`, whose alpha differs, and the alpha matters in
  FadeTransition's textures. Render-target helpers (a
  texture as target, clear colour) are for FadeTransition in layer 8.
  `needs_redraw` marks whether a frame must be drawn.
- **Tests:** `tvertex_instructions` (test_line_rounded_rectangle; the
  normalised attributes Kivy exposes, such as `Line.points` after `circle`
  or `rectangle`, `RoundedRectangle.radius` forms and `Triangle.points`,
  checked against values printed by the running Kivy inside an App, because
  Kivy's instructions need a GL context), `tinstructions`
  (canvas order, insert, remove, clear, opacity product). Scenes: `graphics_basic`, `graphics_line`, `canvas_order`
  without child widgets. Build these with bare Canvas objects and a
  temporary window, before Widget exists.
- **Done:** those scenes are within budget, and `graphics_basic_msaa`'s
  difference is measured and written into the MSAA GAP row.

## 4. Text and image cores

- **Modules:** `core/image`, `core/text/text_layout`, `core/text`,
  `core/text/text_sdl3`.
- **Kivy sources:** `core/image/__init__.py` (Image and ImageLoader, only
  what loading a file into a texture needs, plus the `kv.texture` cache),
  `core/image/img_sdl2.py`, `core/text/text_layout.pyx` (all of it:
  `layout_text`, `LayoutLine`, `LayoutWord`), `core/text/__init__.py`
  (LabelBase: `register`, `resolve_font_name`, `get_extents`,
  `_render_begin`/`_render_text`/`_render_end`, `render`, `_render_real`,
  `render_lines`, `refresh`, `texture`, `content_size`, `text_size`),
  `core/text/text_sdl2.py` and `_text_sdl2.pyx` (font cache keyed by name and
  size, `int(font_size)`, hinting, kerning, blended rendering, ascent and
  descent).
- **Data:** copy `kivy/data/fonts/Roboto-Regular.ttf`, `Roboto-Bold.ttf`,
  `Roboto-Italic.ttf`, `Roboto-BoldItalic.ttf` and `DejaVuSans.ttf` to
  `data/fonts/` byte for byte, and register `Roboto` as Kivy does in
  `core/text/__init__.py`.
- **Tests:** `ttext` (test_unicode_name), `timage_core` (load PNG and JPEG
  sizes; a missing file gives a nil texture and a log line; the same path
  gives the same texture from the cache). Trace: `label`, the CoreLabel part:
  `texture_size` through LabelBase directly, with the same options.
- **Done:** the `label` trace matches. Every line that differs because of
  SDL3_ttf has its measured difference written into the text GAP row.

## 5. Window, input, event loop, app

- **Modules:** `input/motionevent`, `core/window`,
  `core/window/window_sdl3`, `base`, `app`.
- **Kivy sources:** `input/motionevent.py` (the attributes in SCOPE.md;
  `grab`/`ungrab` with weak references become plain references, see Gaps),
  `input/providers/mouse.py` and `window_sdl2.py` (mouse and finger to
  touches, with `multitouch_on_demand` behaviour: no simulated second touch),
  `core/window/__init__.py` (WindowBase: properties, `add_widget`/
  `remove_widget`, the default `on_touch_*`, `on_keyboard` with
  `exit_on_escape`, `on_request_close`, `screenshot` naming), the
  `_window_sdl2.pyx` key mapping (Escape and Android Back are 27), `base.py`
  (EventLoop: `idle` order, `dispatch_input`, `post_dispatch_input` with
  grab, `runTouchApp`, `stopTouchApp`, `close`), `app.py` (only the members
  in SCOPE.md).
- **Notes:** ignore mouse events with `which == SDL_TOUCH_MOUSEID`. The window
  size comes from Config (`graphics.width`/`height`) on desktop and from the
  display on Android. `screenshot` reads the frame just drawn with
  `SDL_RenderReadPixels` and saves it with `IMG_SavePNG`.
- **Tests:** `tmotionevent` (grab and ungrab, push/pop/apply_transform_2d on
  plain numbers), `twindow` (screenshot numbering, child dispatch order,
  observer before default handler, key 27 with and without
  `exit_on_escape`), `tapp` (test_basic_app is finished in layer 7, because
  it needs Label; test_graphics_app).
- **Done:** an App with a root widget runs headless, renders, takes a
  screenshot and stops itself from a Clock callback, and the tests pass.
  Widget is still a minimal stub here.

## 6. Widget and layouts

- **Modules:** `uix/widget`, `uix/layout`, `uix/boxlayout`,
  `uix/floatlayout`, `uix/anchorlayout`, `uix/relativelayout`.
- **Kivy sources:** `uix/widget.py` (the members in SCOPE.md:
  `add_widget` canvas insertion, `disabled` counting, `walk`, coordinate
  methods), `uix/layout.py`, `uix/boxlayout.py` (`_iterate_layout`,
  `do_layout`), `uix/floatlayout.py`, `uix/anchorlayout.py`,
  `uix/relativelayout.py`, and the RelativeLayout rule from
  `data/style.kv`.
- **Tests:** `twidget` (test_widget, test_uix_widget index tests),
  `tlayout` (test_uix_layout's instantiation, BoxLayout `minimum_size`),
  `trelativelayout` (test_uix_relativelayout,
  test_uix_translate_coordinates). Trace: `properties` in full. Scenes:
  `canvas_order`, `boxlayout_tests`, `boxlayout_hints`,
  `floatlayout_hints`, `anchorlayout_tests`.
- **Done:** the geometry `.txt` of those scenes matches exactly, and the
  pixels are within budget.

## 7. Label, Image, ButtonBehavior

- **Modules:** `uix/label`, `uix/image`, `uix/behaviors/button`.
- **Kivy sources:** `uix/label.py` (the properties in SCOPE.md and
  `texture_update` through a Clock trigger), `uix/image.py` (Image only:
  `texture_update`, `set_texture_from_resource`, `reload`,
  `get_norm_image_size`, `image_ratio`), `uix/behaviors/button.py` (all of
  it except kv), and the Label and Image rules from `data/style.kv`.
- **Tests:** `tlabel` (test_basic_app moves here: an App whose root is a
  Label; texture_size against the `label` trace through the widget),
  `timage` (norm_image_size for every fit mode against the `image_fit.txt`
  numbers), `tbutton`. Trace: `touch`. Scenes: `label_align`, `label_wrap`,
  `label_default`, `image_fit`, `image_misc`, `graphics_texture`.
- **Done:** the scenes and the `touch` trace match.

## 8. Animation, ScreenManager, ModalView

- **Modules:** `animation`, `uix/screenmanager`, `uix/modalview`.
- **Kivy sources:** `animation.py` (Animation and AnimationTransition, not
  Sequence or Parallel), `uix/screenmanager.py` (Screen, ScreenManager,
  TransitionBase, NoTransition, and FadeTransition rebuilt on the renderer's
  render targets: both screens go into textures cleared to opaque black,
  then the mix `t*in + (1-t)*out` uses a custom blend mode with
  `SDL_ComposeCustomBlendMode`), `uix/modalview.py`, and the ScreenManager
  and ModalView rules from `data/style.kv`.
- **Tests:** `tanimation` (the TestAnimation tests), `tscreenmanager`
  (test_screen), `tmodalview` (test_modal_app). Traces: `animation`,
  `screens`, `modal`. Scenes: `screen_relative`, `fade_half` (the test
  freezes the transition at 0.5 as the Python scene does), `modal_custom`,
  and `modal_default` (expected to differ: no atlas).
- **Done:** all of the above match. The kiosk port can start its `ui` layer
  after this one.

## 9. Audio

- **Module:** `core/audio`.
- **Kivy sources:** `core/audio/__init__.py` (SoundLoader, Sound: properties,
  `on_play`/`on_stop`, `state`), `core/audio/audio_sdl2.pyx` (the polling
  `_check_play` interval of 0.1 s that calls `stop()` at the end, and
  `unload`). The data path is SDL3: `SDL_LoadWAV`, one audio stream per
  Sound opened with `SDL_OpenAudioDeviceStream`. Play puts the data and
  resumes. The end is when `SDL_GetAudioStreamQueued` reaches 0. Volume is
  `SDL_SetAudioStreamGain`. Loop puts the data again at the end.
- **Tests:** `taudio` (the adapted test_audio, run with
  `SDL_AUDIO_DRIVER=dummy` where it has no device; then `length` comes from
  the WAV header), plus the order of on_play and on_stop for play, stop and
  natural end.
- **Done:** the tests pass, and the kiosk's `voice.py` usage (load, bind
  on_stop, play, stop, unload, `state == "play"`) works on a real device.

## 10. Whole-stack check on this machine (owner, 2026-11-22: no tablet testing for now)

- **Goal:** all of phase 1 works together on the development machine (Linux, SDL3, OpenGL renderer): every reference scene and trace, plus one small app that uses every widget, layout, animation, screen change, the modal view and audio together, driven by a scripted run.
- **Profiling baseline:** measure frame time on this machine for that app and for the busiest reference scenes, and record where time goes (properties, layout, drawing, text). This is the "before" number for phase 2 (`ROADMAP.md`).
- **Android:** not tested now. Write down in `ANDROID.md` what a later Android build will need (the path below), without building it.
- **Path for later Android work:** compile with Nimony using `--os:android --cpu:arm64` (and `arm` for 32-bit) and the NDK's clang into `libmain.so`, packaged with SDL3's Android project template (SDLActivity), assets read through SDL's IOStream, Back as key 27 (`SDL_HINT_ANDROID_TRAP_BACK_BUTTON`), keep-screen-on and immersive mode in SDLActivity.
- **Done:** the scripted whole-stack run passes in debug and release, the profiling baseline is recorded, `ANDROID.md` is written.
