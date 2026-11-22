# Handoff to phase 2 step 4 (layer 7: label, image, ButtonBehavior)

Step 3 is done: Widget, Layout and the four layouts are typed; Widget's box
is on `HintedWidget` (core/window) and core/window has no name lookups left
(REDESIGN.md, "Step 3 notes"; PORTING.md P2.3). #336, #290, #175, #337 were
still open at `95afaa04` (= master).

- **Construction:** `initProps` is a static proc chain, so the most-derived
  type's constructor calls it once, then its `init` proc
  (`newBoxLayout`: `initProps`, `initBoxLayout`). `initWidget`,
  `initLayout`, `initBoxLayout`, ... do not call it. Label and Image call
  it at the start of `initLabel`/`initImage` (marked "Phase 1 until step
  4"): once they have blocks, move the call into `newLabel`/`newImage`
  and into every subclass constructor (tests, showcase).
- **WidgetBase is still an EventDispatcher**, `WidgetClass`, `LayoutClass`,
  `BoxLayoutClass`, `AnchorLayoutClass`, `FloatLayoutClass`,
  `RelativeLayoutClass` are property-less names, because Label, Image,
  ButtonBehavior (step 4) and Screen, ScreenManager, ModalView (step 5)
  still declare phase-1 properties on classes derived from them. Drop them
  (and `cls`, `WindowBaseClass`, `WindowSDLClass`) in step 6. Layout's
  abstract check and the "already has a parent" messages use `cls`.
- Bridges to remove: Label binds `centerX`, `centerY`, `disabled` typed but
  forwards `disabled` as a `Value` to `triggerTextureUpdate`; Image's
  `NormImageSizeProperty` (a phase-1 alias whose `linkDeps` binds the typed
  `size`); Animation's `widgetProperties` `case` (step 5).
- Nimony: a `seq[T]` of a type declared in a `properties:` block, inside a
  proc of the same module, crashes shoggoth (#337, commented): use
  iterators or `seq` of the base type (`walk`, `widgetChildren`). Iterators
  need `{.sideEffect.}` to call procs; a `discard` of a side-effect call in
  one crashes nimsem instead of saying so (#341).
