# nimkivy scope

The subset of Kivy 2.3.2 that nimkivy ports. It covers what the kiosk app uses
(`kiosk/app/ui.py`, `voice.py`, `main.py`), plus what Kivy's semantics need to
make that coherent. Every item behaves as in Kivy. Where an item names Kivy
code, that code takes precedence over the short note here. Names are Kivy's;
nimkivy spells them in camelCase.

## Properties and events (`event`, `properties`)

- **EventDispatcher:** `register_event_type`, `bind`/`fbind` (returns a uid),
  `unbind_uid`, `dispatch`, `property(name)` (for Animation and name lookup),
  and `__events__` as a registration at class setup.
- **Event dispatch** (`_event.pyx` `dispatch`): observers are called last-bound
  first. The first one that returns true stops the dispatch. Otherwise the
  class's default handler `on_<event>` runs last. `dispatch` returns that
  true or the handler's result. Trace: `events`.
- **Property dispatch:** the class's `on_<prop>` runs first, then observers in
  bind order. A return value does not stop them. Nothing is dispatched when
  the new value equals the old one. Trace: `events`.
- **Property kinds:** Numeric (with `allownone`), String, Boolean, Object,
  List, Option (an enum in Nim), Color (4 floats; a 3-float value gets
  alpha 1), VariableList (1, 2 or 4 values expand to `[l, t, r, b]`; Trace:
  `properties`), ReferenceList and Alias (`bind`, `cache`, `watch_before_use`).
- **ReferenceList and Alias ordering** (`properties.pyx`): setting `pos`
  dispatches `x`, its dependents, `y`, its dependents, then `pos` once.
  Setting `x` dispatches `pos` immediately. An alias registers on its
  dependencies when it is first bound or read. The `properties` trace is the
  exact order to reproduce.
- **Out:** DictProperty and ObservableDict, in-place mutation of list values
  (`pos[0] = 1`), `rebind`, string values with units (`'15sp'`) and colour
  strings (`'#ff0000'`, `'red'`, which take numbers or `get_color_from_hex`
  instead), BoundedNumericProperty, and the runtime type errors that Nim's
  types make impossible.

## Clock (`clock`)

- `schedule_once(cb, timeout)`: timeout 0 runs on the next `tick`. Timeout -1
  runs in `tick_draw`, before the next frame is drawn, and if callbacks
  schedule more -1 events, `tick_draw` repeats them up to `max_iteration`
  (20) times. A timeout above 0 runs on the first `tick` at or after that
  time. Events run in scheduling order. An event scheduled while events are
  being processed runs on the next tick (`_process_events` cap). Trace:
  `clock`.
- `schedule_interval(cb, t)` repeats until cancelled. The ClockEvent has
  `cancel()` and `__call__`. `create_trigger(cb, timeout, interval)` gives a
  trigger that schedules once per tick however often it is called.
  `unschedule(cb or event)`.
- Callbacks receive `dt`, the seconds since the last tick. Time comes from
  `std/monotimes`. Frame pacing follows Kivy's `maxfps` of 60 (`idle`
  sleeps).
- **Out:** a callback returning false to stop an interval, lifecycle-aware
  triggers, `del_safe`, threads, async clocks, `triggered` decorators, and
  exception catching.

## Utilities, metrics, config (`utils`, `metrics`, `config`)

- `get_color_from_hex` (`#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, each with or
  without `#`) and `get_hex_from_color`.
- `Metrics.density`, `fontscale` and `dpi`, and `dp`, `sp`, `pt`, `inch`,
  `cm`, `mm`, `dpi2px` with the same formulas. On desktop the density is 1,
  as in Kivy.
  On Android it comes from the display (SDL3 display content scale).
- Config holds these keys only, in memory, with Kivy's defaults:
  `graphics.width` and `graphics.height` (800 x 600), `graphics.resizable`,
  `graphics.maxfps` (60), `graphics.min_state_time` (.035),
  `kivy.exit_on_escape` (1), and `input.mouse` (`multitouch_on_demand` has no
  effect, because there is no multitouch simulation).
- **Out:** `config.ini` files, ConfigParser, Logger configuration (logging
  goes to stderr with Kivy's `[Category] message` shape).

## Graphics (`graphics/*`, `renderer`)

- **Canvas:** `canvas.before`, `canvas`, `canvas.after`, `add`, `insert`,
  `remove`, `clear`, `indexof`, `length`, and `opacity`. Drawing order is
  `before`, then the canvas's own children in insertion order, then `after`.
  A child widget's canvas is one of those children, inserted by
  `Widget.add_widget` exactly as Kivy does. Instructions added later are drawn
  above earlier children. Opacity multiplies down the tree and applies to
  each primitive's alpha. There is no group compositing (the `canvas_order`
  scene). Changing any instruction attribute marks the canvas for redraw.
- **Color:** `rgba`, `rgb`, `r`, `g`, `b`, `a`. It applies to the vertex
  instructions that follow it in the same canvas tree until the next Color.
- **Rectangle:** `pos`, `size`, `texture`, `source`.
- **RoundedRectangle:** `pos`, `size`, `radius` (1 to 4 entries, each a
  number or an (x, y) pair; Kivy's corner order), `segments` (10), `texture`,
  `source`.
- **Ellipse:** `pos`, `size`, `angle_start`, `angle_end`, `segments` (180),
  `texture`, `source`. The texture is mapped through the bounding box (the
  kiosk's round flags).
- **Triangle:** `points` (6 floats).
- **Line:** `points`, `width` (1), `cap` (`round`, `square`, `none`), `joint`
  (`round`, `miter`, `bevel`, `none`), `close`, `circle` (x, y, r[,
  angle_start, angle_end[, segments]]), `rectangle`, `rounded_rectangle` (x,
  y, w, h, r1[, r2, r3, r4][, segments]). A width of exactly 1 is a 1 px
  polyline. Any other width, including widths below 1, uses Kivy's
  `build_extended` triangulation (`vertex_instructions_line.pxi`), turned into
  SDL_RenderGeometry triangles.
- **BorderImage:** `source`, `border`, `pos`, `size`, for ModalView's
  background (SDL_RenderTexture9Grid).
- **PushMatrix, PopMatrix, Translate(x, y):** only for RelativeLayout and
  Screen.
- **StencilPush, StencilUse, StencilUnUse, StencilPop** with one Rectangle
  mask: an intersected clip-rectangle stack (Image and ScreenManager in
  `style.kv`).
- **Texture:** `size`, `width`, `height`, `uvpos`/`uvsize`/`tex_coords` for
  flipping, linear filtering, and textures built from images and text.
- **Coordinates:** Kivy's origin is at the bottom left with y up. The renderer
  flips to SDL's y-down coordinates in one place.
- **Smooth instructions (after phase 2, P2.12):** SmoothLine,
  SmoothRectangle, SmoothRoundedRectangle, SmoothEllipse, SmoothTriangle,
  SmoothQuad (and Quad, which it needs), with Kivy's internal
  AntiAliasingLine. `multisamples` is not used: SDL_Renderer has no MSAA
  (PORTING.md, Gaps).
- **Out:** OpenGL, Shader, RenderContext, Fbo (except the private
  render-to-texture inside FadeTransition), Mesh, Point, Bezier,
  `Line` dash, bezier and ellipse
  modes, Scale, Rotate, MatrixInstruction, Callback, ClearColor, BoxShadow,
  SVG, atlas, mipmaps, and instruction groups beyond Canvas.

## Image and text cores (`core/image`, `core/text*`)

- **CoreImage:** load PNG and JPEG (and whatever SDL3_image decodes) into a
  Texture. A cache maps filename to texture, as Kivy's `kv.texture` does
  (`Image.nocache` is out). A missing file logs an error and leaves the
  texture as none.
- **LabelBase.register(name, fn_regular, fn_italic, fn_bold,
  fn_bolditalic):** `resolve_font_name` picks the file for bold or italic. A
  missing variant falls back to the regular file and is not synthesised (the
  `label` trace: Deja bold uses the Roboto-Bold file). A font name that is not
  registered is a path or a name in `data/fonts`. `Roboto` is registered by
  default, from the copied Kivy files.
- **Font size:** the font opens at `int(font_size)` points, as
  `_text_sdl2.pyx` does, with font_hinting `normal`, font_kerning on, and
  blended rendering.
- **Layout:** `text_layout.pyx` `layout_text`, then `LabelBase.render` and
  `render_lines`, ported as they are. This covers wrapping at `text_size[0]`
  (words longer than the width are split as in Kivy), explicit `\n`,
  `line_height` (a multiplier on the font height), `padding` (4 values),
  `halign` (`left`, `center`, `right`, `justify`, `auto` meaning left),
  `valign` (`bottom`, `middle`/`center`, `top`), `text_size` = (None, None),
  (w, None), (None, h) or (w, h), and `texture_size`. The `label` trace and
  the label scenes are the expected numbers.
- **Out:** markup, `shorten`/`shorten_from`/`split_str`, `max_lines`,
  `strip`, outline, underline, strikethrough, `font_family`/`font_context`
  (Pango), `font_features`, `base_direction` and `font_direction` (RTL
  shaping is a later step for Arabic: SDL3_ttf's `TTF_SetFontDirection` and
  `TTF_SetFontScript` are ready for it), and `text_language`.

## Window, input, event loop, app (`core/window*`, `input/motionevent`, `base`, `app`)

- **Window:** `size`, `width`, `height`, `center`, `clearcolor` (default
  black), `children`, `add_widget`, `remove_widget`, and `screenshot(name)`
  (writes `<stem>0001.<ext>`, or the next number not yet used, and returns
  the path). Events: `on_touch_down`, `on_touch_move`, `on_touch_up` (default
  handlers dispatch to `children[:]`, newest first, and stop at the first
  true; app observers run first, as the `touch` trace shows), `on_key_down`,
  `on_key_up`, `on_keyboard(key, scancode, codepoint, modifiers)`,
  `on_resize`, `on_request_close`, `on_draw`, `on_flip`. Escape and Android
  Back arrive as key 27. With `exit_on_escape` set to 1, the default
  `on_keyboard` handler dispatches `on_request_close` for key 27 and then
  stops the app, unless an observer returned true first.
- **MotionEvent (touch):** `pos`, `x`, `y`, `sx`, `sy`, `spos`, `ox`/`oy`,
  `px`/`py`, `dx`/`dy`, `uid`, `ud` (a table keyed by widget or string),
  `grab`, `ungrab`, `grab_current`, `grab_list`, `push`/`pop`/
  `apply_transform_2d` (for RelativeLayout), `is_touch`, `button`,
  `is_mouse_scrolling`, `time_start`. The left mouse button and every SDL
  finger make touches. SDL's synthetic mouse-from-touch events are ignored.
- **EventLoop (`base.py` `idle`):** each frame runs `Clock.tick`, then input
  dispatch, then `Clock.tick_draw`, then `on_draw` and `on_flip` if the
  canvas needs a redraw. `post_dispatch_input` sends to the window, then sends
  the event again to each grabbing widget with `grab_current` set (the
  `touch` trace).
- **App:** `build`, `root`, `title`, `run`, `stop`, `on_start`, `on_stop`,
  `on_pause` (returning true keeps the app alive on Android), `on_resume`,
  `get_running_app`.
- **Out:** the input providers other than mouse and finger (mtdev, hidinput,
  TUIO, ...), multitouch simulation, hover and `on_motion` filtering, the
  keyboard request API, text input, the cursor, rotation, `system_size`,
  window icons, kv loading, `user_data_dir`, settings, and Inspector or other
  modules.

## Widget and layouts (`uix/widget`, `layout`, `*layout`)

- **Widget:** `x`, `y`, `pos`, `width`, `height` (100), `size`, `right`,
  `top`, `center_x`, `center_y`, `center`, `size_hint` (1, 1, `allownone`),
  `size_hint_min` and `size_hint_max` (x/y), `pos_hint` (a small table of
  `x`, `right`, `center_x`, `y`, `top`, `center_y`, `pos`, `center`),
  `opacity` (sets `canvas.opacity`), `disabled` (a count, inherited by
  children as in `inc_disabled`/`dec_disabled`; the `properties` trace),
  `parent`, `children`, `canvas`. Methods: `add_widget(w, index, canvas)`
  (the canvas insertion rules), `remove_widget`, `clear_widgets(children)`,
  `collide_point` (edges inclusive), `collide_widget`, `walk`,
  `get_root_window`, `to_widget`, `to_window`, `to_parent`, `to_local`,
  `on_touch_down`/`move`/`up` (no collision test on children; a disabled
  widget that is touched swallows the touch down; move and up skip a disabled
  widget).
- **Layout:** `_trigger_layout` (a Clock trigger with timeout -1) bound to
  the properties each layout lists in its `__init__`, `do_layout`, and
  `layout_hint_with_bounds`.
- **BoxLayout:** `orientation`, `spacing`, `padding`, `minimum_width`,
  `minimum_height`, `minimum_size`. Port `_iterate_layout` and `do_layout`
  as they are: stretch space, `size_hint_min`/`max` bounds, children laid out
  in reverse order when horizontal, and `pos_hint` limited to the cross axis
  (`x`/`right`/`center_x` when vertical, `y`/`top`/`center_y` when
  horizontal). A child with a `None` hint keeps its size.
- **FloatLayout:** `do_layout` with `size_hint` times its size, clamped by
  min and max, and every `pos_hint` key, applied in the table's order.
- **AnchorLayout** (ModalView's base): `anchor_x`, `anchor_y`, `padding`.
- **RelativeLayout** (Screen's base): children in local coordinates,
  `PushMatrix`/`Translate(pos)`/`PopMatrix` around the canvas, touches
  transformed with `push`/`apply_transform_2d`/`pop`, and `to_local`/
  `to_parent`.
- **Out:** `ids`, `cls`, `motion_filter`, `export_to_png` and
  `export_as_image`, `walk_reverse`, `proxy_ref`, and the GridLayout,
  StackLayout, PageLayout, Scatter and ScrollView widgets.

## Label, Image, ButtonBehavior (`uix/label`, `uix/image`, `uix/behaviors/button`)

- **Label:** `text`, `font_name` (`Roboto`), `font_size` (`sp(15)`), `bold`,
  `italic`, `color`, `disabled_color` (used while disabled),
  `halign` (`auto`), `valign` (`bottom`), `text_size`, `line_height`,
  `padding`, `texture`, `texture_size`, `texture_update()`, `font_hinting`,
  `font_kerning`, `font_blended`. Every one of these re-renders the label
  through a Clock trigger, as Kivy's does. The `style.kv` canvas draws a
  white Color, then a Rectangle with the texture, size `texture_size`,
  centred at `int(center - texture_size / 2)`.
- **Image:** `source` (reloads on change), `texture`, `texture_size`,
  `image_ratio`, `norm_image_size` (`get_norm_image_size` with the four
  `fit_mode`s `scale-down` (default), `fill`, `contain`, `cover`), `color`,
  `reload()`. The `on_load`/`on_error` events belong to AsyncImage and are
  not included. The `style.kv` canvas draws Color(`color`), a stencil of the
  widget box, then the texture rectangle of `norm_image_size`, centred. So `cover` is clipped to the
  widget, and an image without a texture draws a box of `color`.
- **ButtonBehavior:** `state` (`normal`/`down`), `last_touch`,
  `min_state_time` (from Config), `always_release`, the `on_press` and
  `on_release` events, and `trigger_action(duration)`. The touch logic is
  `button.py` as it is: children first, ignore scroll, collide, `touch.ud`
  guard, grab, press. On up: ungrab, release outside without `on_release`
  unless `always_release`, and `state` goes back to normal only after
  `min_state_time` (the `touch` trace).
- **Out:** AsyncImage, GIF animation (`anim_delay`, `anim_loop`),
  `keep_data`, `mipmap`, `nocache`, the deprecated `allow_stretch` and
  `keep_ratio`, and the Button, ToggleButton and other widgets.

## Animation, ScreenManager, ModalView (`animation`, `uix/screenmanager`, `uix/modalview`)

- **Animation:** `Animation(prop = value, ..., duration/d, transition/t,
  step/s)` animates any numeric or numeric-list property, of a widget or of an
  instruction such as `Color.a`, by name. It has `start`, `stop` (fires
  on_complete), `cancel` (does not), `stop_all`, `cancel_all`,
  `cancel_property`, `stop_property`, `have_properties_to_animate`,
  `animated_properties`, `duration`, `transition`, and the events
  `on_start`, `on_progress`, `on_complete`. `start` first calls `stop` on that
  widget, so restarting a running Animation fires its `on_complete`. Two
  Animation objects on the same property both run, and the later write in a
  frame wins (the `animation` trace). The first update has `time = 0`, and a duration of 0 completes on
  the first update. All AnimationTransition functions are ported; they are
  pure functions.
- **ScreenManager** (a FloatLayout with a stencil canvas): `current`,
  `current_screen`, `screens`, `screen_names`, `transition`, `add_widget`
  (only the first screen added becomes current and is shown),
  `remove_widget`, `clear_widgets`, `get_screen`, `has_screen`,
  `switch_to(screen, transition)`, `next`, `previous`. Touches are blocked
  while a transition is active.
- **Screen** (a RelativeLayout): `name`, `manager`, `transition_progress`,
  `transition_state`, and the events `on_pre_enter`, `on_enter`,
  `on_pre_leave`, `on_leave`.
- **Transitions:** TransitionBase's lifecycle as it is. `start` raises if the
  transition is already active. It adds `screen_in`, then dispatches
  `on_pre_enter` (in) and then `on_pre_leave` (out). At the end it removes
  `screen_out` and dispatches `on_enter` (in) and then `on_leave` (out).
  Changing `current` during a transition stops it first (`on_complete`).
  `duration` defaults to .4. Only NoTransition and FadeTransition are ported.
  FadeTransition renders both screens into textures cleared to opaque black
  (ShaderTransition's `clearcolor`) and draws `t*in + (1-t)*out`. During it
  neither screen is in `children` (the `screens` trace and the `fade_half`
  scene).
- **ModalView** (an AnchorLayout): `auto_dismiss`, `background` (an image
  path for the BorderImage, where `""` means a plain box), `background_color`,
  `border`, `overlay_color`, `open(animation)`, `dismiss(animation, force)`,
  and the events `on_pre_open`, `on_open`, `on_pre_dismiss`, `on_dismiss`
  (returning true cancels unless `force`). It is added to the Window and
  centred on it, and stays centred on resize. It fades in and out over
  `_anim_duration` (.1). Touches inside go to the content. A touch that
  starts outside dismisses on touch up when `auto_dismiss` is set, and every
  touch is swallowed. Key 27 dismisses when `auto_dismiss` is set. The canvas
  is the overlay rectangle over the whole window, with alpha
  `overlay_color.a * _anim_alpha`, then the BorderImage (the `modal` trace and
  the modal scenes).
- **Out:** Sequence (`+`), Parallel (`&`), `repeat`, and animating dicts or
  non-numeric properties. The SlideTransition, SwapTransition, CardTransition,
  WipeTransition, FallOutTransition and RiseInTransition. Popup.
  `attach_to`. Kivy's default ModalView background is an atlas image
  (`atlas://data/images/defaulttheme/modalview-background`). Atlas is out, so
  nimkivy's default `background` is `""` (a plain box of
  `background_color`). This one default differs from Kivy, as the
  `modal_default` scene shows.

## Audio (`core/audio`)

- **SoundLoader.load(path):** returns a Sound or none. Sound has `source`,
  `state` (`stop`/`play`), `volume`, `loop`, `length`, `play()`, `stop()`,
  `unload()`, `seek` (out), and the events `on_play` and `on_stop`. `stop()`
  dispatches `on_stop`, and so does the end of playback. As in
  `audio_sdl2.pyx`, a Clock interval polls for the end and then calls
  `stop()`.
- **Out:** every format except WAV (see Gaps), `pitch`, `get_pos`, and video.

## Out of scope altogether

The kv language, Builder and Factory. Every widget not named above.
Clipboard, camera, spelling, video, storage, network (UrlRequest), atlas,
modules, the Inspector, garden, async app running, multiple windows,
threads, and the effects and recycleview packages.
