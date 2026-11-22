# Handoff from layer 7 to layer 8

- A widget with ButtonBehavior (test_modal_app's ModalButton): call
  `cls.addButtonBehavior()` on its class, `w.button = newButtonBehavior(w)`
  after `initWidget`, and in its touch methods
  `w.button.onTouchDown(t, proc (t: MotionEvent): bool {.closure.} =
  procCall onTouchDown(Widget(w), t))`. `tests/traces.nim` (Btn) and
  `tests/tbutton.nim` show it. Override `on_press`/`on_release` with
  `cls.setEventHandler`.
- Label and Image render through a Clock trigger with timeout -1:
  `Clock.tickDraw()` (or a frame) runs it, `textureUpdate()` renders now.
- Closures made in a loop share one environment (Nim semantics): a closure
  that captures a loop-local widget sees the last one. Make each in a helper
  proc (see `fitHeight` in tests/scenes.nim).
- A root widget of the Window keeps `size_hint` (1, 1) and fills the window,
  as in Kivy; set it to none in tests that place one.
- A touch dispatched to a widget directly (not through
  `EventLoop.postDispatchInput`) needs `t.scaleForScreen(Window.width,
  Window.height)` first, or its `pos` is (0, 0).
- Do not pass a field reached through a `ref` (a property storage's value)
  to a call that can replace that field: it goes by reference and is freed
  under the callee (planetis-m/nimony-bugs-llms#334). `doDispatch` copies it.
- Label's and Image's properties are declared like Widget's, so Animation
  finds them by name (`color`, `opacity`, `font_size`, ...).
- tests/scenes.nim and run_tests.sh: add screen_relative, fade_half,
  modal_custom, modal_default (modal_default is expected to differ, see
  SCOPE.md), and the traces animation, screens, modal to the compare list.
