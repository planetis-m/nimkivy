## The `buildUi` plugin (DSL.md; `buildui.nim` documents the block). One
## pass over the untyped block, in source order, into plain Nim in the
## caller's scope:
##
## - `X(args) [as name] [: block]` with `X` in `Widgets`: `let name =
##   newX(positional args)`, `name.p = v` for each `p = v`, the block, the add;
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
import plugins, nimparser
import codegen

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
  StmtCalls = ["inc", "dec", "echo"]
  Walked = ["if", "when", "case", "for", "while", "block", "try"]
  Arms = ["elif", "else", "of", "except", "fin"]

type
  Parent = object
    handle: NifCursor          # what a line is added to; empty at the top level
    group: string              # "" (addWidget), "canvas", "canvas.before", ...

proc isTag(n: NifCursor; tags: openArray[string]): bool =
  n.kind == TagLit and n.tagText in tags

proc isPath(n: NifCursor): bool =
  # `name` or `a.b.c`.
  if n.kind == Ident: return true
  if not isTag(n, ["dot"]): return false
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
  if isTag(n, ["proc"]):
    let s = headText(n)
    if s.len > 2 and s.startsWith("on") and s[2] in {'A' .. 'Z'}: result = s

proc canvasGroup(n: NifCursor): string =
  # "canvas", "canvas.before" or "canvas.after" for such a block, else "".
  result = ""
  if isTag(n, ["call", "cmd"]):
    var c = firstChild(n)
    if c.kind == Ident and c.identText == "canvas":
      result = "canvas"
    elif isTag(c, ["dot"]) and headText(c) == "canvas":
      var d = firstChild(c)
      skip d
      if d.kind == Ident and d.identText in ["before", "after"]:
        result = "canvas." & d.identText
    skip c
    if result.len > 0 and not (c.hasMore and c.stmtKind == StmtsS): result = ""

proc walk(dest: var NifBuilder; body: NifCursor; p: Parent)

proc emitAdd(dest: var NifBuilder; p: Parent; h: NifCursor; info: LineInfo) =
  if p.handle.hasMore:
    let code = if p.group.len == 0: "OwnerV.addWidget(HandleV)\n"
               else: "OwnerV." & p.group & ".add(HandleV)\n"
    dest.emitStmts(code, Subst(trees: @[("OwnerV", p.handle), ("HandleV", h)]), info)

proc emitChild(dest: var NifBuilder; n: NifCursor; p: Parent) =
  # A widget, a call, a name or a path; maybe `as name`, maybe a block.
  var e = n
  var name = NifCursor()
  var body = NifCursor()
  if isTag(n, ["infix"]):
    var c = firstChild(n)
    skip c                     # `as`
    e = c
    skip c
    name = c
    skip c
    if c.hasMore: body = c
  let listed = isTag(e, ["call", "cmd"]) and headText(e) in Widgets
  var expr = createTree()      # the call without its block
  if isTag(e, ["call", "cmd", "oconstr"]):
    expr.openTree(e.tagText, e.info)
    for c in e.children:
      if c.stmtKind == StmtsS: body = c
      elif not (listed and isTag(c, ["vv"])): expr.addSubtree c
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
    var u = handleTree(sym, n.info)
    use = snapshot(u)
    var d = createTree()
    d.addSymDef sym, n.info
    def = snapshot(d)
  var s = Subst(trees: @[("NameV", def)])
  if listed:
    # `newX(positional args)`: the call's head renamed.
    var args = ""
    var c = firstChild(value)
    skip c
    while c.hasMore:
      args.add (if args.len > 0: ", " else: "") & "Arg" & $s.trees.len & "V"
      s.trees.add ("Arg" & $s.trees.len & "V", c)
      skip c
    dest.emitStmts("let NameV = new" & headText(e) & "(" & args & ")\n", s, n.info)
    for c in e.children:
      if isTag(c, ["vv"]):
        var kv = firstChild(c)
        let prop = kv.identText
        skip kv
        dest.emitStmts("HandleV." & prop & " = ValueV\n",
          Subst(trees: @[("HandleV", use), ("ValueV", kv)]), c.info)
  else:
    s.trees.add ("ExprV", value)
    dest.emitStmts("let NameV = ExprV\n", s, n.info)
  if body.hasMore:
    dest.walk(body, Parent(handle: use, group: ""))
  dest.emitAdd(p, use, n.info)

proc emitHandler(dest: var NifBuilder; n: NifCursor; owner: NifCursor) =
  # `proc onX(params)[: T] = body` as `discard owner.bindX(proc (params)[: T]
  # {.closure.} = body)`.
  let name = handlerName(n)
  let event = toLowerAscii(name[2]) & name.substr(3)
  var lambda = createTree()
  var c = firstChild(n)
  skip c                       # the name
  lambda.openTree("proc", n.info)
  lambda.addEmptyNode()
  for i in 0 ..< 4:            # exported, pattern, type vars, params
    lambda.takeTree c
  let addBool = c.kind == DotToken and event in Events
  if addBool:
    lambda.addIdent "bool"
    skip c
  else:
    lambda.takeTree c
  lambda.openTree("pragmas", c.info)
  if c.kind == TagLit:
    for pragma in c.children: lambda.addSubtree pragma
  lambda.addIdent "closure"
  lambda.closeTree()
  skip c
  lambda.takeTree c            # effects
  if addBool:
    lambda.openTree("stmts", c.info)
    var reset = parseStmt("result = false", c.info)
    lambda.addSubtree firstChild(reset)
    for line in c.children: lambda.addSubtree line
    lambda.closeTree()
  else:
    lambda.takeTree c
  lambda.closeTree()
  dest.emitStmts("discard OwnerV.bind" & name.substr(2) & "(LambdaV)\n",
    Subst(trees: @[("OwnerV", owner), ("LambdaV", snapshot(lambda))]), n.info)

proc emitLine(dest: var NifBuilder; n: NifCursor; p: Parent)

proc walkInto(dest: var NifBuilder; n: NifCursor; p: Parent) =
  # Control flow: its statement lists are walked, the rest copied.
  dest.openTree(n.tagText, n.info)
  for c in n.children:
    if c.stmtKind == StmtsS:
      dest.withTree StmtsS, c.info:
        dest.walk(c, p)
    elif isTag(c, Arms): dest.walkInto(c, p)
    else: dest.addSubtree c
  dest.closeTree()

proc emitLine(dest: var NifBuilder; n: NifCursor; p: Parent) =
  let group = canvasGroup(n)
  if isTag(n, Walked):
    dest.walkInto(n, p)
  elif group.len > 0 and p.handle.hasMore:
    var c = firstChild(n)
    skip c
    dest.walk(c, Parent(handle: p.handle, group: group))
  elif handlerName(n).len > 0 and p.handle.hasMore:
    dest.emitHandler(n, p.handle)
  elif isTag(n, ["infix"]) and headText(n) == "as":
    dest.emitChild(n, p)
  elif isTag(n, ["call", "cmd", "oconstr"]):
    if isTag(firstChild(n), ["dot"]) or headText(n) in StmtCalls:
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
