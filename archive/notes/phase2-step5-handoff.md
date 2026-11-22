# Handoff to phase 2 step 5 (layers 8-9: animation, screenmanager, modalview, audio)

Step 4 is done: Label, Image and ButtonBehavior are `properties:` blocks with
no name lookups (REDESIGN.md, "Step 4 notes"; PORTING.md P2.4). #336, #290,
#175, #337 were still open at `95afaa04` (= master).

- **Left on phase 1:** ScreenManager, Screen, ModalView (they call
  `initProps` in their `init` procs, marked "Phase 1 until step 5": move the
  call into their constructors once they have blocks), Animation (the
  `widgetProperties` `case` reaching typed properties by Kivy name), audio's
  Sound, and the showcase's `newAnimation({"opacity": ...})`,
  `s.sm.bind("current", ...)`, screens' `on_enter`/`on_leave`, Sound's
  `on_play`/`on_stop`. After step 5 nothing derived from WidgetBase declares
  phase-1 properties, so step 6 can make WidgetBase `ref object of RootObj`
  and drop `cls` and the `*Class` names (`LabelClass`, `ImageClass` too).
- **ButtonBehavior** is owned by the widget (`w.button`); tmodalview's
  ModalButton and the showcase's Pressable use it as in button.nim's module
  doc. Its events are `w.button.bindPress`/`bindRelease`; overriding is a
  subclass of ButtonBehavior with `method onPress`/`onRelease`.
- A property of type `nil T` (`lastTouch: nil MotionEvent`, `texture: nil
  Texture`) works with `= nil` as its default; an `Opt` pair default must be
  written `none[float]()`, not `none(float)` (type mismatch in the block).
