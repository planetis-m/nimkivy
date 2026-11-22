# nimkivy acceptance

A layer is done when its ported Kivy tests pass, and when its scenes and
traces match Kivy's output, produced by the running Kivy 2.3.2 and
stored in `tests/fixtures/` (`archive/README.md` says how). Kivy's tests are in `upstream/kivy/kivy/tests/`. Each one is ported
into `tests/t<module>.nim` as a `block` named after the Kivy test, with a
comment `# kivy/tests/<file>::<test>`.

"Adapted" means the test is ported with a stated change, such as an
out-of-scope widget replaced by an in-scope one. Kivy tests that only render
(`GraphicUnitTest.render`, which has no stored expected images) are covered by
the reference scenes.

## Kivy tests ported

| Kivy test file | Tests | nimkivy test | Notes |
|---|---|---|---|
| `test_properties.py` | test_base, test_observer, test_objectcheck, test_stringcheck, test_numericcheck, test_listcheck, test_propertynone, test_reference, test_color_property, test_alias_property_without_setter, test_alias_property, test_alias_property_cache_true, test_alias_property_with_bind, test_alias_property_with_force_dispatch_true, test_alias_property_cache_true_with_bind, test_alias_property_cache_true_force_dispatch_true, test_inherit_property | `tproperties.nim` | Each test runs in both `set_name` variants, through the class registration. Adapted: the type-rejection halves are dropped (Nim's types make them compile errors). test_color_property keeps the list and tuple forms but not colour names or hex strings. test_alias_property_without_setter keeps only the getter half. |
| `test_clock.py` | test_schedule_once, test_schedule_once_twice, test_schedule_once_draw_after, test_schedule_once_draw_before, test_unschedule, test_unschedule_event, test_unschedule_after_tick, test_unschedule_draw, test_trigger_create, test_trigger_cancel, test_trigger_interval | `tclock.nim` | Uses a fresh Clock per test, like the `kivy_clock` fixture. |
| `test_utils.py` | test_get_hex_from_color_noalpha, test_get_hex_from_color_alpha, test_get_color_from_hex_noalpha, test_get_color_from_hex_alpha | `tutils.nim` | |
| `test_metrics.py` | test_metrics_scale_factors (all 6 units) | `tmetrics.nim` | |
| `test_widget.py` | test_add_remove_widget, test_invalid_add_widget, test_clear_widgets, test_clear_widgets_children, test_position, test_size, test_collision, test_disabled | `twidget.nim` | Adapted: test_invalid_add_widget checks adding a widget to itself and adding one that already has a parent (Nim's types rule out None and classes). test_disabled toggles without `disabled=None`. |
| `test_uix_widget.py` | test_add_widget_index_0, test_add_widget_index_1, test_add_widget_index_2 | `twidget.nim` | Adapted: Buttons become plain widgets. The test checks the `children` order and `canvas.indexof` of each child, not a render. |
| `test_uix_translate_coordinates.py` | test_to_local_and_to_parent__relative, test_to_local_and_to_parent__not_relative, test_to_window_and_to_widget | `trelativelayout.nim` | Only the Widget and RelativeLayout parameters (Scatter and ScrollView are out). The kv trees are built in code. |
| `test_uix_relativelayout.py` | test_relativelayout_on_touch_move, test_relativelayout_coordinates | `trelativelayout.nim` | |
| `test_animations.py` | TestAnimation: test_start_animation, test_animation_duration_0, test_cancel_all, test_cancel_all_2, test_stop_animation, test_stop_all, test_stop_all_2, test_duration, test_transition, test_animated_properties, test_animated_instruction | `tanimation.nim` | The `sleep` helper ticks the real Clock, as in Kivy. test_animated_instruction animates a Translate's `x`, because Scale is out of scope. |
| `test_screen.py` | test_switch_to, test_switching_does_not_affect_a_list_of_screens | `tscreenmanager.nim` | Only with NoTransition and FadeTransition. |
| `test_uix_modal.py` | test_modal_app | `tmodalview.nim` | Adapted: the root `ModalButton(Button)` becomes a widget with a ButtonBehavior. Touches are posted to the EventLoop as UnitKivyApp does: down, moves, up. |
| `test_graphics.py` | test_line_rounded_rectangle | `tvertex_instructions.nim` | The asserts on the normalised `rounded_rectangle` radii (clamping, minimum 1). The renders are covered by `graphics_line`. |
| `test_app.py` | test_basic_app, test_graphics_app | `tlabel.nim` (test_basic_app), `tapp.nim` | test_basic_app checks `root.text`. test_graphics_app reads two pixels of the rendered window. |
| `test_fonts.py` | test_unicode_name | `ttext.nim` | Adapted: `data/fonts/DejaVuSans.ttf` is copied to a temporary file named `कीवी.ttf` (no zip). |
| `test_audio.py` | test_length_simple, test_length_playing, test_length_stopped | `taudio.nim` | Adapted: `tests/assets/tone.wav` (1.402 s, the length of `sample1.ogg`), because only WAV is supported (Gaps). Kivy reports 1.40200 s for this file. |

## Kivy tests not ported

| Kivy test file or test | Why |
|---|---|
| test_properties: test_dictcheck, test_dict, test_dictproperty_is_none, test_listproperty_is_none, test_reference_child_update, test_bounded_numeric_property*, test_numeric_string_with(out)_units, test_numeric_property_dp, test_variable_list_property_dp*, test_property_rebind | DictProperty, in-place mutation, BoundedNumericProperty, unit strings and rebind are out of scope |
| test_properties: test_property_duplicate_name, test_property_rename_duplicate, test_override_prop_inheritance, test_manually_create_property, test_unknown_property, test_known_property_multiple_inheritance, test_pass_other_typeerror, test_object_init_error | Python class machinery and kwargs, which have no Nim counterpart |
| test_clock: test_trigger_decorator*, test_exception_*, test_clock_ended_*, test_clock_stop_twice, test_clock_restart, test_clock_event_trigger_ref | decorators, exception handling, lifecycle-aware events and weak references are out (Gaps) |
| test_animations: test_weakref, TestSequence, TestRepetitiveSequence, TestParallel | weak references, Sequence and Parallel are out |
| test_uix_boxlayout (4 tests), test_uix_anchorlayout (4 tests), test_uix_widget: test_image_properties, test_default_label, test_label_text, test_label_font_size | render-only tests. Their layouts are the scenes `boxlayout_tests`, `anchorlayout_tests`, `label_default` and `image_fit`. |
| test_uix_widget: test_default_widgets, test_button_properties, test_slider_properties, test_button_state_down, test_widget_root_from_code_with_kv | Button, Slider and kv are out |
| test_widget: test_export_to_png | export_to_png is out (and skipped in Kivy) |
| test_app: test_start_raw_app, test_start_app_with_kv, test_user_data_dir, test_directory, test_name, test_button_app, test_drag_app, test_text_app, test_leak_app_* | kv, user_data_dir, ToggleButton, Scatter and TextInput are out. test_leak_app_* needs weak references. |
| test_window_base, test_window_info, test_mouse_hover_event, test_mouse_multitouchsim, test_motion_event | to_normalized_pos, opacity, window_info, hover, multitouch simulation and MotionEvent internals are out |
| test_graphics (all but test_line_rounded_rectangle) | BoxShadow, Point, smooth instructions, Fbo, Scale (test_enlarged_line), transformations and threads are out. test_circle and test_ellipse only render; `graphics_basic` covers them. |
| test_image, test_imageloader | keep_data, BytesIO saving, and per-provider loader suites (SDL2, PIL, ...) are out. Loading is compared in the `image_*` and `graphics_texture` scenes. |
| test_utils (other tests), test_config, test_lang*, test_uix_* of other widgets, test_issues, and the rest | out of scope |

## Reference scenes (`archive/reference/scenes.py`)

Each scene builds a widget tree with the in-scope API in an 800 x 600 window
(clearcolor white, `multisamples = 0`). It saved `<scene>.png`
with `Window.screenshot` (Kivy numbers the file, and the script renames it),
and `<scene>.txt` with every widget's pos, size, `texture_size` and
`norm_image_size`, now in `tests/fixtures/scenes/`. The test images in
`tests/assets/` were made by `archive/reference/make_assets.py`.

| Scene | What it shows |
|---|---|
| graphics_basic | Rectangle, alpha blending, RoundedRectangle (one radius, and 4 mixed corners), Ellipse (full, angle range, 6 segments), Triangle, a 1 px rectangle, fractional geometry |
| graphics_basic_msaa | the same scene with Kivy's default MSAA 2, to measure the MSAA GAP |
| graphics_line | 1 px open and closed polylines, the three caps, the four joints, circle (full and arcs, segments), rectangle, rounded_rectangle, a width of 1.5 |
| graphics_texture | `source` on Rectangle, Ellipse and RoundedRectangle, PNG with alpha, JPEG, colour tint, half alpha, an upscaled small image |
| canvas_order | before, canvas, child canvas and after; nested opacity (0.5 × 0.5); `canvas.clear`; `add_widget(index=2)` |
| boxlayout_tests | the 8 layouts of `test_uix_boxlayout.py` |
| boxlayout_hints | `size_hint` None, mixed hints, `size_hint_min`/`max`, `pos_hint` on the cross axis, padding forms, overflow, the kiosk's `size_hint_x = 0.0001` |
| floatlayout_hints | every `pos_hint` key, `size_hint` None, min and max |
| anchorlayout_tests | the 9 anchor combinations with padding |
| label_align | 4 halign × 3 valign, with `text_size` bound to size |
| label_wrap | the kiosk's "fit" labels (`text_size = (w, None)`, height from `texture_size`), line_height 1.0, 1.25 and 0.8, a registered font with a bold file, padding, colour |
| label_default | Label defaults, newlines, overflow, disabled colour, empty text, Greek and other non-ASCII text, sizes 9 and 64 |
| image_fit | the 4 fit modes × wide, tall and small images |
| image_misc | Image colour, opacity, a source changed after creation, no source |
| screen_relative | a Screen (RelativeLayout) in a ScreenManager that is not at the origin: local coordinates and the stencil clip |
| fade_half | FadeTransition held at progress 0.5 (with the black FBO clear) |
| modal_custom | the kiosk's picker style: transparent background, coloured overlay, painted panel |
| modal_default | Kivy's default ModalView look. nimkivy is expected to differ here (no atlas; see SCOPE.md). |

**Comparison:** `bin/compare-<mode> tests/out <scene> ...` (`tests/compare.nim`). The `.txt` geometry must
match exactly, printed to 3 decimals. In the `.png`, at most 0.5% of pixels
may differ by more than 24/255 in a channel. The budget is 3% for label,
modal and `_msaa` scenes, and 1% for scenes with JPEG. Every scene over budget
gets a diff image in `tests/out/diff/`. A remaining difference is either fixed
or written down as a GAP with the measured percentage.

## Behaviour traces (`archive/reference/traces.py`)

`tests/fixtures/traces/<name>.txt` holds the exact lines that `tests/traces.nim`
must print:

| Trace | What it fixes |
|---|---|
| properties | the dispatch order for pos, x, size, right and center through ReferenceList and Alias properties; VariableList forms; defaults; inherited `disabled` |
| events | the order of event observers (newest first, default handler last, true stops) and of property observers (`on_<prop>` first, then bind order); `unbind_uid` |
| clock | the order of `schedule_once` 0 and -1, intervals, nested scheduling and triggers across `tick_draw` and `tick` |
| animation | on_start, progress and on_complete; two animations on one property; stop against cancel; duration 0 |
| touch | the Window observer, children newest first, ButtonBehavior grab, release inside and outside, a disabled widget, `min_state_time` |
| screens | the first screen added, the transition lifecycle events, `children` during a FadeTransition, a switch during a running transition |
| modal | open and dismiss events, touch inside and outside, Escape, `auto_dismiss` False |
| label | `texture_size` for 20 label configurations (font, size, bold, wrap, line_height, padding, valign, justify, long word) |

Timing-dependent lines, such as Animation progress, are checked only for
order, first and last values and monotony, never for the number of frames.

## Kiosk check (after layer 8)

The kiosk app ported to nimkivy (the kiosk's own `PORTING.md`, layers 3 and
4) is compared with `kiosk/tools/screenshots.py` at 1280x800 and 1920x1200 for
the screens attract, home, picker, topic and quiz, using the same
`compare.py` budgets. This check belongs to the kiosk port, but it is
nimkivy's final acceptance.
