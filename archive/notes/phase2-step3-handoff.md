# Handoff to phase 2 step 3 (layer 6: widget and the layouts)

Step 2 is done: metrics, clock, config, input/motionevent, core/window,
window_sdl3, base and app are typed (REDESIGN.md, "Step 2 notes"; PORTING.md
P2.2). #336, #290, #175, #337 were still open at `95afaa04` (= master).

- `core/window`: `WidgetBase` is by hand (#337) and still an `EventDispatcher`
  with a property-less class, only so Widget's phase-1 properties work. Once
  Widget is typed, make it `ref object of RootObj` and drop `cls:`,
  `WidgetBaseClass`, `WindowBaseClass`, `WindowSDLClass` (the window's
  "already has a parent" message prints `cls.name`).
- The hints live on `HintedWidget` (core/window), Widget's base. The window
  still writes Widget's geometry and binds its `size`/`pos` **by name**
  (`updateChildsize`, `WindowBase.addWidget`/`removeWidget`, marked
  "Phase 1 until step 3"). Move the geometry (`x`, `y`, `width`, `height`,
  `pos`, `size`, `right`, `top`, `centerX`, `centerY`, `center`) into
  `HintedWidget` and make those typed; `WindowBase` cannot share them.
- Layouts: `Layout.keepUnbind`/`bindChild` (phase 1 by name) and
  `bindChildPosHint` (typed) keep per-child unbinders; `triggerNow` triggers
  the layout. Box/Float/Anchor already bind `children`, `parent`, `posHint`,
  `sizeHint` typed; the rest is by name.
- Typed now: `dispatchTouchDown/Move/Up`, `bindTouchDown...`, `CanvasLayer`,
  `PosHint` (`{phTop: 0.9}`), `w.sizeHintX = 0.5` (float overloads),
  `MotionAction`, `claimedBy`, `Config.graphics.*`, `LoopStatus`.
- Still by name elsewhere: Image's `norm_image_size` alias depends on
  `size` by name, Label/Image/ScreenManager/ModalView/RelativeLayout
  `fbind("pos"/"size"/"center_x")`, Animation targets by name (step 5).
- Nimony: `$typeof(x)` of a ref object is `ref T.Obj` (#340), hence
  `initApp(className)`. A closure capturing a `nil T` local cannot call
  through it (write a helper taking `T`, as `toWidgetFn`). `seq.insert`
  needs `std/sequtils`.
