## A declarative widget tree: `buildUi:`, Kivy's kv language as a Nimony
## template plugin, with Kivy's update model: the tree is built once, and a
## binding keeps a property current when what it reads changes.
##
## .. code-block:: nim
##   buildUi:
##     BoxLayout(orientation = orientationVertical) as root:
##       canvas.before:
##         Color(rgba = Linen)
##         Rectangle(pos <- self.pos, size <- self.size)
##       Label(fontSize = 22) as title:
##         text <- topic.title & " (" & $topic.index & ")"
##       Pill(Leaf, sizeHintY = none[float](), height = 56) as listen:
##         on button.release:
##           player.toggle()
##         on touchDown(t: MotionEvent):
##           idle.reset()
##         Label("Listen")
##
## Grammar:
##
## .. code-block::
##   widget = Type[(arg, ..., prop = value | prop <- expr, ...)] [as name] [: item+]
##   item   = prop = value              set once
##          | prop <- expr              set now, and again when expr's properties change
##          | on [part.]name[(params)]: stmts
##          | canvas[.before|.after]: instruction+
##          | widget                    a child, added in order
##   instruction = Type[(arg, ..., prop = value | prop <- expr)] [as name]
##                 [: (prop = value | prop <- expr)+]
##
## - `Type(args)` calls `newType(args)`: a widget's or an instruction's
##   constructor, or any proc of that name that returns one (a component,
##   as kv's class rule). Positional arguments go to it; `prop = value` and
##   `prop <- expr` in the parentheses are items of the widget.
## - `as name` declares `let name` in the caller's scope. Every widget
##   exists before any item is applied, so an item may name any handle.
## - `prop <- expr` sets `prop` to `expr`, then binds (`bindP`) every
##   `h.p` that `expr` reads and that is a property, so that a change of one
##   sets `prop` again. As in kv, a read that is not a property (a plain
##   field, a proc call such as `s.scale`) is evaluated but not followed, and
##   `a.b.c` follows `a.b` only; a binding that follows no property at all
##   is an error.
## - `on name[(params)]: stmts` binds a handler: to the event `name`
##   (`bindName`, the parameters are the event's, with their types;
##   `result` starts false, and setting it to true stops the dispatch), or
##   else to the property `name` (kv's `on_<prop>`; `on size(v: (float,
##   float)):` names the new value, `on size:` leaves it unnamed). `on
##   part.name` binds one of an owned object (`on button.release` binds
##   `w.button`'s `release`).
## - `canvas:`, `canvas.before:` and `canvas.after:` add instructions to the
##   widget's canvas; in an instruction's items `self` is the widget.
## - `self` in an item is the widget the item belongs to.
##
## The expansion, in the caller's scope: the constructors, then the
## `prop = value` items, in tree order; then each widget is completed from
## the root down: its canvas instructions, its children (each completed
## before it is added with `addWidget`), its bindings and its handlers. So a
## child's handlers see it being added to its parent (a Screen's `enter`
## when it becomes the current screen), and a widget's own handlers do not
## see its children being added (a ScreenManager's `current` changing to
## the first screen). Nothing is rebuilt later.
##
## A wrong name or a wrong handler is a compile error at the item, for
## example `buildUi: \`txt\` is not a property of Label`,
## `buildUi: Label has no event or property \`touchDown\` with parameters
## (x: float)` or `buildUi: \`text <- ...\` follows no property: topic.name
## is not one`.

template buildUi*(body: untyped) {.plugin: "plugins/builduiplug".}
  ## Builds the widget tree of `body` once and binds its bindings and
  ## handlers; see the module doc.
