## A widget tree as thin sugar over plain Nim, after Karax's `buildHtml`
## (DSL.md). The tree is built once; nothing is rebuilt later, and only the
## `proc onX` handlers bind.
##
## .. code-block:: nim
##   buildUi:
##     boxLayout(sizeHintY = none[float](), height = sc(72)) as row:
##       canvas.before:
##         color(rgba = Linen)
##         rectangle(pos = row.pos, size = row.size) as bg
##       proc onPos(v: (float, float)) = bg.pos = v
##       proc onSize(v: (float, float)) = bg.size = v
##       label("a", bold = true)
##       pill(text, Olive, outline = some(Gold)) as home:
##         proc onRelease() = app.goHome()
##       gap(16)
##       header.box
##
## One pass, in source order, in the caller's scope (every `let` stays
## visible after the block); a line at the top level is a root, added to
## nothing:
##
## - `x(args) [as name] [: block]`, `x` one of nimkivy's widgets or canvas
##   instructions in lowercase (the plugin's `Widgets`): `let name =
##   newX(positional args)`, `name.p = v` for each named argument, the block,
##   then the add.
## - Any other call, a bare name or a dot path: added as written
##   (`row.addWidget(gap(16))`); with `as name` or a block, `let name = expr`
##   first.
## - `canvas:`, `canvas.before:`, `canvas.after:` in a block: its lines go
##   to that canvas group (`name.canvas.before.add(t)`).
## - `proc onX(params)[: bool] = body` in a block, also inside control flow
##   there: `discard w.bindX(proc (params) {.closure.} = body)`. For an event
##   (`press`, `release`, `touchDown`, `touchMove`, `touchUp`, `preEnter`,
##   `enter`, `preLeave`, `leave`, `preOpen`, `open`, `preDismiss`,
##   `dismiss`) without a return type, `: bool` and `result = false` are
##   added; any other `onX` is a property's handler and takes its value.
## - Everything else is code, copied unchanged: assignments, `let`/`var`,
##   `discard`, `return`, dot calls (`tiles.add t`), `inc`, `dec`, `echo`.
##   `if`, `when`, `case`, `for`, `while`, `block` and `try` are walked into.
##
## So a void call to a plain name is a child: write it as a dot call
## (`v.refresh()`). Errors are the compiler's, on the generated code.

template buildUi*(body: untyped) {.plugin: "plugins/builduiplug".}
  ## Builds the tree of `body` once; see the module doc.
