## The `buildUi` plugin (DSL.md; `buildui.nim` documents the block). One
## pass over the untyped block, in source order, into plain Nim in the
## caller's scope:
##
## - `x(args) [as name] [: block]` with `x` in `Widgets`: `let name =
##   newX(positional args)`, `name.p = v` for each `p = v`, the block, the
##   add;
## - any other call, a bare name or a dot path `[as name] [: block]`: `let
##   name = expr`, the block, the add; without `as` and block only the add;
## - `canvas[.before|.after]:` in a block: its lines are added to that group;
## - `proc onX(params)[: T] = body` in a block: `discard w.bindX(proc ...)`;
##   an event of `Events` without a return type gets `: bool` and
##   `result = false`;
## - anything else is copied; `if`, `when`, `case`, `for`, `while`, `block`
##   and `try` are walked into.
##
## The add is `parent.addWidget(h)`, or `parent.canvas[.before|.after].add(h)`
## in a canvas group; a line at the top level is added to nothing. A line
## without `as name` that needs a name gets a generated symbol.

import std/strutils
import plugins
import trees

const
  Widgets = ["widget", "boxLayout", "floatLayout", "anchorLayout",
    "relativeLayout", "label", "image", "screen", "screenManager", "modalView",
    "instructionGroup", "color", "rectangle", "roundedRectangle", "ellipse",
    "line", "triangle", "quad", "borderImage", "smoothRectangle",
    "smoothRoundedRectangle", "smoothEllipse", "smoothTriangle", "smoothQuad",
    "smoothLine", "pushMatrix", "popMatrix", "translate",
    "stencilPush", "stencilUse", "stencilUnUse", "stencilPop"]
  Events = ["press", "release", "touchDown", "touchMove", "touchUp",
    "preEnter", "enter", "preLeave", "leave",
    "preOpen", "open", "preDismiss", "dismiss"]
  StmtCalls = ["inc", "dec", "echo"]
  Walked = {IfS, WhenS, CaseS, ForS, WhileS, BlockS, TryS}
  Arms = {ElifU, ElseU, OfU, ExceptU, FinU}

type
  Parent = object
    handle: NifCursor          # what a line is added to; empty at the top level
    group: string              # "" (addWidget), "canvas", "before", "after"

proc isPath(n: NifCursor): bool =
  # `name` or `a.b.c`.
  if n.kind == Ident: return true
  if n.exprKind != DotX: return false
  var c = firstChild(n)
  result = isPath(c)
  skip c
  result = result and c.kind == Ident

proc headText(n: NifCursor): string =
  # The callee of a call, when it is a plain name.
  let h = firstChild(n)
  result = if h.kind == Ident: h.identText else: ""

proc handlerName(n: NifCursor): string =
  # `onX` of `proc onX(...)`, else "".
  result = ""
  if n.stmtKind == ProcS:
    let s = headText(n)
    if s.len > 2 and s.startsWith("on") and s[2] in {'A' .. 'Z'}: result = s

proc canvasGroup(n: NifCursor): string =
  # "canvas", "before" or "after" for such a block, else "".
  result = ""
  if n.exprKind in {CallX, CmdX}:
    var c = firstChild(n)
    if c.kind == Ident and c.identText == "canvas":
      result = "canvas"
    elif c.exprKind == DotX and headText(c) == "canvas":
      var d = firstChild(c)
      skip d
      if d.kind == Ident and d.identText in ["before", "after"]:
        result = d.identText
    skip c
    if result.len > 0 and not (c.hasMore and c.stmtKind == StmtsS): result = ""

proc walk(dest: var NifBuilder; body: NifCursor; p: Parent)

proc emitAdd(dest: var NifBuilder; p: Parent; h: NifCursor; info: LineInfo) =
  # `parent.addWidget(h)`, `parent.canvas.add(h)` or
  # `parent.canvas.before.add(h)` (`after`).
  if p.handle.hasMore:
    dest.withTree CallS, info:
      if p.group.len == 0:
        dest.addDot p.handle, "addWidget", info
      elif p.group == "canvas":
        dest.withTree DotX, info:
          dest.addDot p.handle, "canvas", info
          dest.addIdent "add"
      else:
        dest.withTree DotX, info:
          dest.withTree DotX, info:
            dest.addDot p.handle, "canvas", info
            dest.addIdent p.group
          dest.addIdent "add"
      dest.addSubtree h

proc emitChild(dest: var NifBuilder; n: NifCursor; p: Parent) =
  # A widget, a call, a name or a path; maybe `as name`, maybe a block.
  var e = n
  var name = NifCursor()
  var body = NifCursor()
  if n.exprKind == InfixX:
    var c = firstChild(n)
    skip c                     # `as`
    e = c
    skip c
    name = c
    skip c
    if c.hasMore: body = c
  let listed = e.exprKind in {CallX, CmdX} and headText(e) in Widgets
  var expr = createTree()      # the call without its block
  if e.exprKind in {CallX, CmdX}:
    expr.openTree(e.tag, e.info)
    for c in e.children:
      if c.stmtKind == StmtsS: body = c
      elif not (listed and c.otherKind == VvU): expr.addSubtree c
    expr.closeTree()
  else:
    expr.addSubtree e
  let value = snapshot(expr)
  if not listed and not name.hasMore and not body.hasMore and p.handle.hasMore:
    dest.emitAdd(p, value, n.info)
    return
  var def, use: NifCursor
  if name.hasMore:
    def = name
    use = name
  else:
    let sym = genSym()
    var u = createTree()
    u.addSymUse sym, n.info
    use = snapshot(u)
    var d = createTree()
    d.addSymDef sym, n.info
    def = snapshot(d)
  if listed:
    # `let name = newX(positional args)`, then `name.p = v` for each `p = v`.
    dest.withLet def, n.info:
      dest.withCall "new" & capital(headText(e)), n.info:
        var c = firstChild(value)
        skip c                 # the head
        while c.hasMore:
          dest.takeTree c
    for c in e.children:
      if c.otherKind == VvU:
        var kv = firstChild(c)
        dest.withTree AsgnS, c.info:
          dest.withTree DotX, c.info:
            dest.addSubtree use
            dest.takeTree kv   # the property's name
          dest.takeTree kv     # its value
  else:
    dest.withLet def, n.info:
      dest.addSubtree value
  if body.hasMore:
    dest.walk(body, Parent(handle: use, group: ""))
  dest.emitAdd(p, use, n.info)

proc emitHandler(dest: var NifBuilder; n: NifCursor; owner: NifCursor) =
  # `proc onX(params)[: T] = body` as `discard owner.bindX(proc (params)[: T]
  # {.closure.} = body)`.
  let name = handlerName(n)
  let event = toLowerAscii(name[2]) & name.substr(3)
  var c = firstChild(n)
  skip c                       # the name
  dest.withDiscardCall owner, "bind" & name.substr(2), n.info:
    dest.withTree ProcS, n.info:
      dest.addEmptyNode()
      for i in 0 ..< 4:        # exported, pattern, type vars, params
        dest.takeTree c
      let addBool = c.kind == DotToken and event in Events
      if addBool:
        dest.addIdent "bool"
        skip c
      else:
        dest.takeTree c
      dest.withTree PragmasU, c.info:
        if c.kind == TagLit:
          for pragma in c.children: dest.addSubtree pragma
        dest.addIdent "closure"
      skip c
      dest.takeTree c          # effects
      if addBool:
        dest.withTree StmtsS, c.info:
          dest.withTree AsgnS, c.info:
            dest.addIdent "result"
            dest.addIdent "false"
          for line in c.children: dest.addSubtree line
      else:
        dest.takeTree c

proc emitLine(dest: var NifBuilder; n: NifCursor; p: Parent)

proc walkInto(dest: var NifBuilder; n: NifCursor; p: Parent) =
  # Control flow: its statement lists are walked, the rest copied.
  dest.openTree(n.tag, n.info)
  for c in n.children:
    if c.stmtKind == StmtsS:
      dest.withTree StmtsS, c.info:
        dest.walk(c, p)
    elif c.otherKind in Arms: dest.walkInto(c, p)
    else: dest.addSubtree c
  dest.closeTree()

proc emitLine(dest: var NifBuilder; n: NifCursor; p: Parent) =
  let group = canvasGroup(n)
  if n.stmtKind in Walked:
    dest.walkInto(n, p)
  elif group.len > 0 and p.handle.hasMore:
    var c = firstChild(n)
    skip c
    dest.walk(c, Parent(handle: p.handle, group: group))
  elif handlerName(n).len > 0 and p.handle.hasMore:
    dest.emitHandler(n, p.handle)
  elif n.exprKind == InfixX and headText(n) == "as":
    dest.emitChild(n, p)
  elif n.exprKind in {CallX, CmdX}:
    if firstChild(n).exprKind == DotX or headText(n) in StmtCalls:
      dest.addSubtree n        # a dot call, `inc`, `dec`, `echo`
    else: dest.emitChild(n, p)
  elif isPath(n):
    dest.emitChild(n, p)
  else:
    dest.addSubtree n

proc walk(dest: var NifBuilder; body: NifCursor; p: Parent) =
  for n in body.children: dest.emitLine(n, p)

proc transform(root: NifCursor): NifBuilder =
  result = createTree()
  result.withTree StmtsS, root.info:
    result.walk(callArgs(root), Parent(handle: NifCursor(), group: ""))

saveTree transform(loadPluginInput())
