# Handoff from layer 6 to layer 7

- A widget subclass: `let LabelClass* = newDispatcherClass("Label", WidgetClass)`,
  then `Label(cls: LabelClass, canvas: newCanvas())` and `initWidget` (a
  layout: its own `init*` proc, which calls `initLayout`). The class name is
  what the scenes' `.txt` prints.
- `initWidget` opens the window (`EventLoop.ensureWindow`), as Kivy's
  Widget.__init__ does. Set Config (size) before creating any widget.
- A style.kv rule: apply it after `initWidget`, with each kv binding as an
  `fbind` (see `applyStyle` in uix/relativelayout.nim).
- `collidePoint` is a method; touch handlers call children through
  `procCall onTouchDown(Widget(w), touch)` (or the layout's type).
- Size hints read as `Opt[float]` (std/opt, as text_layout's TextSize);
  `posHint` is a seq of `(key, Value)`. `widgetChildren` gives the children
  as `Widget`.
- tests/traces.nim: `Btn` in `traceTouch` writes ButtonBehavior out by hand
  (`buttonTouchDown/Move/Up`); replace it with the real ButtonBehavior.
- tests/scenes.nim: add the layer 7 scenes to `build` and to `scenes` in
  run_tests.sh. Kivy's `.txt` line also has `texture_size=` for a Label and
  `texture_size=` plus `norm_image_size=` for an Image (scenes.py `shoot`):
  extend the line in `shoot`.
- tests/tapp.nim: test_basic_app moves to tlabel (LAYERS.md).
