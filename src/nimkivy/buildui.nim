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
##          | place expr [as name] [: item+]   an existing widget
##   item   = prop = value              set once
##          | prop <- expr              set now, and again when expr's properties change
##          | on [part.]name[(params)]: stmts
##          | canvas[.before|.after]: (instruction | if)+
##          | widget                    a child, added in order
##          | if cond: item+ [elif cond: item+]* [else: item+]   no canvas inside
##   instruction = Type[(arg, ..., prop = value | prop <- expr)] [as name]
##                 [: (prop = value | prop <- expr)+]
##               | place expr [as name] [: (prop = value | prop <- expr)+]
##
## - `Type(args)` calls `newType(args)`: a widget's or an instruction's
##   constructor, or any proc of that name that returns one (a component,
##   as kv's class rule). Positional arguments go to it; `prop = value` and
##   `prop <- expr` in the parentheses are items of the widget.
## - `as name` declares `let name` in the caller's scope. Every widget
##   exists before any item is applied, so an item may name any handle.
## - `prop <- expr` sets `prop` to `expr`, then binds (`bindP`) every
##   `h.p` that `expr` reads, so that a change of one sets `prop` again;
##   each must be a property (a plain field is a compile error). The callee
##   of a call (`s.scale()`, `Fig.withAlpha(0.45)`) is evaluated but not
##   followed, and `a.b.c` follows `a.b` only; a binding that reads no
##   `h.p` is set once.
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
## - `place expr` puts a widget made elsewhere (a separately built
##   header, a widget a proc returns) at its place in the tree, as a child
##   written there would be: `expr` is evaluated once with the constructors,
##   `as name` names it, and its block may hold any item. In a canvas,
##   `place expr` adds an existing instruction. kv has no direct equivalent
##   (an app adds such a widget in Python after the rule is applied).
## - `if cond:` (with `elif` and `else`) chooses items when the tree is
##   built: its condition is evaluated once, when the expansion reaches the
##   `if`, and nothing is added, removed or bound again when it would change
##   later; kv has no conditional either. In a widget's block an arm holds
##   the widget's items (properties, bindings, handlers), children and
##   further `if`s, but no `canvas:` (put the `if` inside the canvas); in a
##   canvas an arm holds instructions and `if`s. A name declared with `as`
##   in an arm is visible in that arm only.
##
## The expansion, in the caller's scope: the constructors, then the
## `prop = value` items, in tree order; then each widget is completed from
## the root down: its canvas instructions, its children (each completed
## before it is added with `addWidget`), its bindings and its handlers. So a
## child's handlers see it being added to its parent (a Screen's `enter`
## when it becomes the current screen), and a widget's own handlers do not
## see its children being added (a ScreenManager's `current` changing to
## the first screen). An `if` is built where it stands among the widget's
## children (or instructions): the arm's widgets are made, its
## `prop = value` items set, then its children completed and added, its
## bindings and handlers bound, all inside the arm. Nothing is rebuilt
## later.
##
## A wrong name or a wrong handler is the compiler's error on the generated
## code; syntax the plugin does not know is `buildUi: unsupported syntax`.

template buildUi*(body: untyped) {.plugin: "plugins/builduiplug".}
  ## Builds the widget tree of `body` once and binds its bindings and
  ## handlers; see the module doc.
