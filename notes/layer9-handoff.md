# Handoff from layer 8 to layer 9

- Audio's end-of-playback poll is a Clock interval, as Animation's update is
  (`animation.nim` `clockInstall`/`clockUninstall`): keep the ClockEvent,
  `cancel()` it in `stop()`, and capture the object in a `{.closure.}`.
- A test that needs real time ticks the real Clock: `sleep(10); Clock.tick()`
  in a loop (`tickFor` in tests/traces.nim, `sleepTicking` in
  tests/tanimation.nim).
- Iterating over a seq held in a `ref` field is rejected ("cannot iterate
  over a location reached through a `ref`"): copy it to a `let` first, which
  is also Kivy's iterate-over-a-copy.
- A property overridden by a subclass with another default (NoTransition's
  `duration`) must be read by name (`getProperty`), not through the base
  class's Property object, or the base default fills the storage.
- run_tests.sh: traces `animation`, `screens`, `modal` and scenes
  `screen_relative`, `fade_half`, `modal_custom` are compared;
  `modal_default` only by geometry (its atlas background is out of scope).
  `reference/out/modal_default.*` were regenerated (the old ones showed no
  modal).
- The kiosk port can start its `ui` layer now (LAYERS.md, section 8).
