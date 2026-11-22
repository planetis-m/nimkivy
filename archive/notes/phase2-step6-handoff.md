# Handoff to phase 2 step 6 (cleanup)

Step 5 is done: Animation (typed tracks), Screen, the transitions,
ScreenManager, ModalView and Sound are `properties:` blocks (REDESIGN.md,
"Step 5 notes"; PORTING.md P2.5). #336, #290, #175, #337 were still open at
`95afaa04` (= master).

- **Nothing derived from WidgetBase declares phase-1 properties now**, and
  src/, tests/ and examples/ no longer bind, dispatch or read anything by
  name. What is left of phase 1: `event.nim`, `properties.nim`,
  `graphics/texture.toValue`/`toTexture` (unused since step 4),
  `WidgetBase` as an `EventDispatcher` with `cls`, `initEventDispatcher` in
  core/window, and the property-less class names (`WidgetBaseClass`,
  `WindowBaseClass`, `WindowSDLClass`, `WidgetClass`, `LayoutClass`,
  `BoxLayoutClass`, `FloatLayoutClass`, `AnchorLayoutClass`,
  `RelativeLayoutClass`, `LabelClass`, `ImageClass`, `ScreenClass`,
  `ScreenManagerClass`, `ModalViewClass`, and the tests' `TButtonClass`,
  `BlockerClass`, `BtnClass`, `ModalButtonClass`, the showcase's
  `PressableClass`). Every constructor passes `cls:`; drop it with them.
  Layout's abstract check compares `cls`.
- Many modules `import properties` only for `newDispatcherClass` (and
  traces.nim); tproperties is typed already.
- Python exception names still in `quit` messages: `ScreenManagerException`
  (screenmanager), and whatever `grep -rn '"[A-Z][a-z]*Error: ' src` finds.
- Tracks: `propTo(Owner, v)` names the declaring type (a Nimony bug, filed;
  PORTING.md Gaps). `trackKey("Owner.prop")` is the key, also for keys of
  properties that do not exist (tanimation's `"z"`).
