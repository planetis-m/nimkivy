# buildUi: final design

## 1. Principle

`buildUi` is thin sugar over plain Nim. Everything it does can be written by
hand with `newX`, property assignments, `addWidget`, `canvas.*.add` and
`bindX`; the plugin only saves that repetition. It is modelled on Karax's
`buildHtml` (karax/karaxdsl.nim, karax/compact.nim) and departs from it only
where noted (section 6). The tree is built once; there is no rebuild-and-diff
and no reactive binding syntax.

## 2. The two lists (in the plugin)

A Nimony plugin is a separate program run per `buildUi` call and sees only
syntax, so the lists are constants in the plugin, as Karax's tag table is:

```nim
const
  Widgets = ["Widget", "BoxLayout", "FloatLayout", "AnchorLayout",
    "RelativeLayout", "Label", "Image", "Screen", "ScreenManager", "ModalView",
    "InstructionGroup", "Color", "Rectangle", "RoundedRectangle", "Ellipse",
    "Line", "Triangle", "Quad", "BorderImage", "SmoothRectangle",
    "SmoothRoundedRectangle", "SmoothEllipse", "SmoothTriangle", "SmoothQuad",
    "SmoothLine", "PushMatrix", "PopMatrix", "Translate",
    "StencilPush", "StencilUse", "StencilUnUse", "StencilPop"]
  Events = ["press", "release", "touchDown", "touchMove", "touchUp",
    "preEnter", "enter", "preLeave", "leave",
    "preOpen", "open", "preDismiss", "dismiss"]
```

`Widgets` are nimkivy's own types with a `newX` constructor (Karax: tags).
`Events` are the event names (Karax: `EventKind`); every other `onX` is a
property. Apps register nothing.

## 3. The rules

`buildUi:` is a statement. One pass, in source order. Its scope is flat:
every `let` it emits stays visible after the block. A line at the top level
is a root and is not added to anything.

**3.1 A listed widget** — `X(args) [as name] [: block]` with `X` in
`Widgets`: positional arguments go to `newX`, named arguments are property
sets (Karax: attributes), then the block, then the add.

```nim
BoxLayout(spacing = 8) as row:      # let row = newBoxLayout()
                                    # row.spacing = 8
  Label("a", bold = true)           # let t1 = newLabel("a"); t1.bold = true
                                    # row.addWidget(t1)
```

**3.2 Any other call is a child** (Karax: an unknown call is added) — the
call is left exactly as written, so a component keeps its real keyword
arguments:

```nim
  pill(text, Olive, Linen, outline = some(Gold)) as home:
                                    # let home = pill(text, Olive, Linen, outline = some(Gold))
    proc onRelease() = app.goHome() # (3.5)
                                    # row.addWidget(home)
  gap(16)                           # row.addWidget(gap(16))
```

Without `as` and block, it is just `parent.addWidget(call)`.

**3.3 A bare name or dot path is a child** (Karax, same) — `header.box`
becomes `parent.addWidget(header.box)`.

**3.4 Canvas** — inside `canvas:`, `canvas.before:` or `canvas.after:` in a
widget's block, children go to that group with `name.canvas.before.add(t)`.

**3.5 Handlers** — `proc onX(params)[: bool] = body` in a widget's block
(Karax: `proc onclick`), also inside control flow there, binds to that
widget:

| Written | Emitted |
|---|---|
| `proc onRelease() = v.go()` (in `Events`) | `discard w.bindRelease(proc (): bool {.closure.} = (result = false; v.go()))` |
| `proc onTouchDown(t: MotionEvent): bool = body` | `discard w.bindTouchDown(proc (t: MotionEvent): bool {.closure.} = body)` |
| `proc onSize(s: (float, float)) = body` (not in `Events`: a property) | `discard w.bindSize(proc (s: (float, float)) {.closure.} = body)` |

The parameters are copied as written. A `proc` not named `on<Upper>…` is an
ordinary nested proc.

**3.6 Everything else is code**, copied unchanged: assignments,
`let`/`var`, `discard`, `return`, dot calls (`tiles.add t`, `v.show()`), and
the statement calls `inc`, `dec`, `echo` (Karax's `StmtContext`). The plugin
walks into `if/elif/else`, `when`, `case`, `for`, `while`, `block`, `try`.

Consequences, plainly:
- A void call to a plain name (`refresh(v)`) in a block would be added as a
  child and fail to compile: write it as a dot call, `v.refresh()`.
- A module-qualified component call (`widgets.pill(...)`) is a dot call, so
  it is code: call components unqualified.
- No `self`: name what you refer to with `as`.
- A component that wraps a button forwards `press`/`release` as its own
  events (Kivy's shape; about 6 lines in the kiosk's PressBox/PressWidget),
  so `proc onRelease()` works on `pill`, `roundButton`, `photoTile`.

## 4. No bindings; resize rebuilds

`prop <- expr` is removed. Sizes are plain values computed at build time
(`sc(72)`, the kiosk's scale helper read once). Things that follow layout
(a background following its widget, text size following width) use a
property handler (3.5). The window resize (desktop only; the tablet is
fullscreen with a fixed orientation) rebuilds the screens:

```nim
discard Window.bindSize(proc (s: (float, float)) {.closure.} = app.rebuild())
```

`rebuild` stops the slideshow, dismisses the picker, builds the views again
(`buildViews`, split out of today's `build`), swaps the root and re-shows
the current screen without voice. The voice's `onChange` listener moves into
`build`, once, so a rebuild does not add another.

## 5. What goes away

| Today | Instead |
|---|---|
| capital-letter guess, `Type` → `newType` for every capital call | the `Widgets` list; other calls untouched |
| `prop <- expr` and its dependency walk | values at build time; property handlers |
| `prop = value` lines in a block (implicit receiver), `self` | named arguments, `name.prop = value` |
| `place expr` | a bare name or path, or any call |
| `on [part.]name(params):` | `proc onName(params) =` |
| 3-pass emission; special `if` items | one pass; plain control flow |
| `buildUi: unsupported syntax` and the bad_ui tests | none: unknown lines are code, errors come from the compiler |
| propsplug's `handlerBinds` (two `bindP` overloads per property) | the `Events` list picks the signature |
| the kiosk's fake constructors (`newPillBox`, `newRoundBox`, `newFlagBox`, `newTileBox`) and `newIconPill` | components are plain procs with keyword arguments |

Estimated plugin size: about 150 lines (today 564).

## 6. Where it departs from Karax, and why

- **Dot calls are code.** Karax adds them too; here `tiles.add t` and
  `v.show()` would need `!`. Treating them as code removes the need.
- **No `!`.** With dot calls as code, any statement can be written so.
- **Named arguments of a listed widget are property sets, not attributes;
  named `onX = h` arguments are not handlers.** Handlers are only the
  `proc onX` form: one way to write them.
- **`canvas:` blocks.** Karax has no canvas.

## 7. Example: the topic screen's button row

Before (ui.nim today):

```nim
            BoxLayout(sizeHintY = none[float]()):
              height <- sc(Window.size, 72)
              spacing <- sc(Window.size, 16)
              RoundButton(ikLeft, 68) as prev:
                posHint = {phCenterY: 0.5}
                on button.release:
                  app.views.topic.go(-1)
              Widget as dots:
                on pos:
                  app.views.topic.drawDots()
                on size:
                  app.views.topic.drawDots()
```

After:

```nim
            BoxLayout(sizeHintY = none[float](), height = sc(72), spacing = sc(16)):
              roundButton(ikLeft, 68) as prev:
                prev.posHint = {phCenterY: 0.5}
                proc onRelease() = app.views.topic.go(-1)
              Widget() as dots:
                proc onPos(p: (float, float)) = app.views.topic.drawDots()
                proc onSize(s: (float, float)) = app.views.topic.drawDots()
```

The same in plain Nim, which is what the plugin emits:

```nim
let t1 = newBoxLayout()
t1.sizeHintY = none[float]()
t1.height = sc(72)
t1.spacing = sc(16)
let prev = roundButton(ikLeft, 68)
prev.posHint = {phCenterY: 0.5}
discard prev.bindRelease(proc (): bool {.closure.} =
  result = false
  app.views.topic.go(-1))
t1.addWidget(prev)
let dots = newWidget()
discard dots.bindPos(proc (p: (float, float)) {.closure.} = app.views.topic.drawDots())
discard dots.bindSize(proc (s: (float, float)) {.closure.} = app.views.topic.drawDots())
t1.addWidget(dots)
textCol.addWidget(t1)
```

## 8. Open question

- A `background(w, fill)` helper in nimkivy (a plain proc: a colour and a
  rectangle under `w`, following its pos and size; 7 uses), or the plain
  lines at each use.
