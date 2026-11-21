# Handoff from layer 5 to layer 6

- Make `Widget = ref object of WidgetBase` (WidgetBase is in core/window.nim), with its class from `newDispatcherClass("Widget", WidgetBaseClass)`. The constructor passes `canvas: newCanvas()`, then calls `initWidgetBase`.
- Override the methods `onTouchDown`/`Move`/`Up`, `toWidget`, `toParent`, `toWindow`, `getRootWindow`, `addWidget`, `removeWidget`. `parent` and `children` are already properties with accessors.
- `Window.updateChildsize` reads `size_hint`, `size_hint_min`, `size_hint_max` and `pos_hint` by name; it reads `pos_hint` as a list of `(key, value)` pairs. If layer 6 picks another form, change `updateChildsize` to match.
- The default `App.build` returns nil (Widget comes after `app` in the module order).
- Trace results are bool: a false result prints "False" for on_touch_down/move and "None" for on_touch_up (`pyResult` in tests/traces.nim).
- Replace the stubs in tests/traces.nim and tests/stubs.nim with the real Widget/FloatLayout (layer 6) and ButtonBehavior (layer 7). The `properties` trace then becomes an exact comparison (it is checked as a prefix of 44 of 50 lines until Widget exists).
