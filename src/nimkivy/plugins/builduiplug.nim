## The `buildUi` plugin: a declarative widget tree with Kivy's update model
## (`buildui.nim` documents the block). The tree is built once; a binding
## (`prop <- expr`) sets the property now and again whenever a property that
## `expr` reads changes.
##
## Input: `(stmts buildUi (stmts <widget>))`, the untyped block. Output, in
## the caller's scope:
##
## 1. `let name = newType(args)` for every widget and canvas instruction, in
##    tree order (a generated symbol for one without `as name`), so every
##    handle exists before a binding or a handler uses it;
## 2. the `prop = value` items, in tree order;
## 3. each widget completed, from the root down: its canvas instructions
##    (`w.canvas.before.add i`, ...); its children, each completed before
##    `w.addWidget(child)`; then its bindings (and its instructions') and
##    its handlers:
##    - a binding: `w.prop = expr`, then for each `h.p` read by `expr` that
##      is a property, `h.bindP(proc (v: typeof(h.p)) = w.prop = expr)`;
##    - a handler: `w.bindEvent(proc (params): bool = result = false;
##      stmts)`, or `w.bindProp(proc (v: T) = stmts)` for a property.
## 4. an `if` item becomes an `if` statement at its place among the
##    widget's children (or canvas instructions); each arm is a small
##    expansion of its own: its `let`s, its `prop = value` items, then its
##    children, instructions, bindings and handlers. A `place expr` widget
##    is `let name = expr` in step 1 and is otherwise a widget like any.
##
## `self` in an item is the widget the item belongs to (for a canvas
## instruction, the widget whose canvas it is). The checks a plugin cannot
## make without types (is it a property, an event with these parameters) are
## generated as `when compiles(...)` with an `{.error.}` at the item, so a
## wrong name is a compile error that says what is wrong where it is written.
##
## The generated code is written as Nim text with placeholder names
## (`HandleV`, `ValueV`, ...), parsed at the item's position and copied with
## the placeholders replaced (`codegen`).

import std/strutils
import plugins, nimparser
import codegen

type
  ItemKind = enum
    ikSet, ikBind, ikOn

  Item = object
    kind: ItemKind
    name: string               # the property or the event
    path: seq[string]          # ikOn: `button` in `on button.release`
    value: NifCursor           # the value, the expression or the body
    params: string             # ikOn: the parameters, types as `ArgT<i>`
    shown: string              # ikOn: the parameters as written, for messages
    paramTypes: seq[NifCursor]
    hasParams: bool
    info: LineInfo

  Layer = enum
    widget, canvasMain, canvasBefore, canvasAfter

  NodeKind = enum
    nkWidget, nkInstruction,
    nkIf,                      # an `if` item: its arms
    nkArm                      # one arm of an `if`: items of its widget

  Node = object
    kind: NodeKind
    typeName: string           # for messages (an arm's: its widget's)
    layer: Layer               # `widget`, or the canvas an instruction is on
    args: seq[NifCursor]       # positional constructor arguments
    placed: NifCursor          # `place expr`: the expression; else empty
    handle: NifCursor          # one token: the `as` name or a generated symbol
    def: NifCursor             # the same as a definition, for the `let`
    owner: int                 # the widget: an instruction's, an `if`'s, an
                               # arm's; a widget's own index
    scope: int                 # the arm whose block declares it, or -1
    items: seq[Item]
    children: seq[int]         # child widgets and `if`s, in order
    instructions: seq[int]     # canvas instructions and `if`s, in order
    conds: seq[NifCursor]      # nkIf: the conditions (none for `else`)
    arms: seq[int]             # nkIf: the arms, in order
    info: LineInfo

  Tree = object
    nodes: seq[Node]
    err: NifBuilder

const
  letCode = "let NameV = newTYPE(ARGS)\n"
  placeCode = "let NameV = ExprV\n"
  setCode = """
when compiles(HandleV.PROP):
  HandleV.PROP = ValueV
else:
  {.error: "buildUi: `PROP` is not a property of TYPE".}
"""
  bindCode = """
discard DepV.bindDEP(proc (ParamV: typeof(DepV.dep)) {.closure.} =
  HandleV.PROP = ValueV)
"""
  canvasCode = "OwnerV.CANVAS.add HandleV\n"
  addCode = "OwnerV.addWidget(HandleV)\n"
  eventCode = """
when compiles(RecvV.bindEVENT(proc (PARAMS): bool {.closure.} = false)):
  discard RecvV.bindEVENT(proc (PARAMS): bool {.closure.} =
    result = false
    BodyV)
elif compiles(RecvV.bindEVENT(proc (PROPCHECK) {.closure.} = discard)):
  discard RecvV.bindEVENT(proc (PROPPARAMS) {.closure.} =
    BodyV)
else:
  {.error: "buildUi: TYPE has no event or property `WHAT".}
"""

proc fail(t: var Tree; msg: string; at: NifCursor) =
  if t.err.isEmpty: t.err = errorTree("buildUi: " & msg, at)

proc isCapitalIdent(n: NifCursor): bool =
  n.kind == Ident and n.identText.len > 0 and n.identText[0] in {'A' .. 'Z'}

proc isTag(n: NifCursor; tag: string): bool =
  n.kind == TagLit and n.tagText == tag

proc isPlace(n: NifCursor): bool =
  # `place expr [as name] [: ...]`.
  result = (isTag(n, "cmd") or isTag(n, "call")) and firstChild(n).kind == Ident and
    firstChild(n).identText == "place"

proc isWidget(n: NifCursor): bool =
  # `Type`, `Type(...)`, `Type(...): ...` or any of them `as name`, or
  # `place expr`.
  if isCapitalIdent(n): return true
  if n.kind != TagLit: return false
  if n.tagText == "infix":
    return firstChild(n).identText == "as"
  if isPlace(n): return true
  # A type starts with a capital letter (`on press:` is a `cmd` too).
  result = n.tagText in ["call", "cmd"] and isCapitalIdent(firstChild(n))

proc isCanvas(n: NifCursor): bool =
  # `canvas: ...`, `canvas.before: ...` or `canvas.after: ...`.
  if not (isTag(n, "call") or isTag(n, "cmd")): return false
  let head = firstChild(n)
  if head.kind == Ident: return head.identText == "canvas"
  result = isTag(head, "dot") and firstChild(head).kind == Ident and
    firstChild(head).identText == "canvas"

proc text(n: NifCursor): string =
  # A type as written, for messages: `float`, `MotionEvent`, `seq[int]`.
  if n.kind == Ident: return n.identText
  if isTag(n, "at"):
    var c = firstChild(n)
    result = text(c) & "["
    skip c
    var first = true
    while c.hasMore:
      if not first: result.add ", "
      result.add text(c)
      first = false
      skip c
    return result & "]"
  result = "..."

# ------------------------------------------------------------------ reading

proc readParams(t: var Tree; call: NifCursor; item: var Item) =
  # `touch(x, y: float)`: names, each group closed by its type.
  item.hasParams = true
  var c = firstChild(call)
  skip c                       # the event
  var group = ""
  while c.hasMore and t.err.isEmpty:
    if c.kind == Ident:
      if group.len > 0: group.add ", "
      group.add c.identText
    elif isTag(c, "kv"):
      var kv = firstChild(c)
      if group.len > 0: group.add ", "
      group.add kv.identText
      skip kv
      if item.params.len > 0:
        item.params.add "; "
        item.shown.add "; "
      item.params.add group & ": ArgT" & $item.paramTypes.len
      item.shown.add group & ": " & text(kv)
      item.paramTypes.add kv
      group = ""
    else:
      t.fail("a handler's parameters are `name: Type`", c)
    skip c
  if group.len > 0:
    t.fail("a handler's parameter needs a type: `" & group & ": Type`", call)

proc readEvent(t: var Tree; spec: NifCursor; item: var Item) =
  # `release`, `button.release`, `touch(t: MotionEvent)`,
  # `button.touch(t: MotionEvent)`.
  var head = spec
  # `f(x: T)` parses as an object constructor, `f(x, y: T)` as a call.
  if isTag(spec, "call") or isTag(spec, "oconstr"):
    head = firstChild(spec)
    readParams(t, spec, item)
  var names: seq[string] = @[]
  var c = head
  while isTag(c, "dot"):
    var d = firstChild(c)
    let left = d
    skip d
    if d.kind != Ident:
      t.fail("an event is `name` or `part.name`", spec)
      return
    names.add d.identText
    c = left
  if c.kind != Ident:
    t.fail("an event is `name` or `part.name`", spec)
    return
  names.add c.identText          # read right to left
  item.name = names[0]
  for i in countdown(names.len - 1, 1): item.path.add names[i]

proc readNode(t: var Tree; n: NifCursor; layer: Layer; owner, scope: int): int
proc readItems(t: var Tree; body: NifCursor; index: int)
proc readInstructions(t: var Tree; body: NifCursor; layer: Layer; owner, into: int)

proc readArg(t: var Tree; c: NifCursor; node: var Node) =
  # One argument of `Type(...)`: `prop = value`, `prop <- expr` or a
  # positional argument of the constructor.
  if isTag(c, "vv"):
    var kv = firstChild(c)
    let name = kv
    skip kv
    if name.kind != Ident:
      t.fail("a property is set as `prop = value`", c)
    else:
      node.items.add Item(kind: ikSet, name: name.identText, value: kv, info: name.info)
  elif isTag(c, "infix") and firstChild(c).identText == "<-":
    var b = firstChild(c)
    skip b
    let name = b
    skip b
    if name.kind != Ident:
      t.fail("a binding is `prop <- expr`", c)
    else:
      node.items.add Item(kind: ikBind, name: name.identText, value: b, info: name.info)
  elif node.items.len > 0:
    t.fail("positional arguments come before `prop = value`", c)
  else:
    node.args.add c

proc innerScope(t: Tree; index: int): int =
  # The scope of what a widget's or an arm's block declares.
  result = if t.nodes[index].kind == nkArm: index else: t.nodes[index].scope

proc readIf(t: var Tree; n: NifCursor; layer: Layer; owner, scope: int): int =
  ## Reads an `if` item, in a widget's block (`layer` widget) or in a
  ## canvas; returns its index.
  result = t.nodes.len
  t.nodes.add Node(kind: nkIf, typeName: t.nodes[owner].typeName, layer: layer,
    handle: t.nodes[owner].handle, owner: owner, scope: scope, info: n.info)
  for branch in asIfStmt(n).branches:
    if t.err.isEmpty:
      let arm = t.nodes.len
      t.nodes.add Node(kind: nkArm, typeName: t.nodes[owner].typeName, layer: layer,
        handle: t.nodes[owner].handle, owner: owner, scope: scope, info: branch.body.info)
      t.nodes[result].arms.add arm
      if not branch.isElse: t.nodes[result].conds.add branch.cond
      if branch.body.stmtKind != StmtsS:
        t.fail("expected a block after `:`", branch.body)
      elif layer == widget:
        readItems(t, branch.body, arm)
      else:
        readInstructions(t, branch.body, layer, owner, arm)

proc readInstructions(t: var Tree; body: NifCursor; layer: Layer; owner, into: int) =
  # The block of `canvas:` or of an `if` in it: instructions and `if`s, added
  # to `into`'s instructions.
  let scope = innerScope(t, into)
  var i = firstChild(body)
  while i.hasMore and t.err.isEmpty:
    if isTag(i, "if"):
      let k = readIf(t, i, layer, owner, scope)
      t.nodes[into].instructions.add k
    elif isWidget(i):
      let k = readNode(t, i, layer, owner, scope)
      if k >= 0: t.nodes[into].instructions.add k
    else:
      t.fail("expected a canvas instruction: `Type(...) [as name]`", i)
    skip i

proc readItems(t: var Tree; body: NifCursor; index: int) =
  # The block of a widget, of an arm of an `if` in it (whose items are the
  # widget's) or of a canvas instruction (`prop = value` and `prop <- expr`
  # only).
  let isInstruction = t.nodes[index].kind == nkInstruction
  let owner = t.nodes[index].owner
  let scope = innerScope(t, index)
  var n = firstChild(body)
  while n.hasMore and t.err.isEmpty:
    if n.stmtKind == AsgnS:
      var c = firstChild(n)
      let name = c
      skip c
      if name.kind != Ident:
        t.fail("a property is set as `prop = value`", n)
      else:
        t.nodes[index].items.add Item(kind: ikSet, name: name.identText, value: c,
          info: name.info)
    elif isTag(n, "infix") and firstChild(n).identText == "<-":
      var c = firstChild(n)
      skip c
      let name = c
      skip c
      if name.kind != Ident:
        t.fail("a binding is `prop <- expr`", n)
      else:
        t.nodes[index].items.add Item(kind: ikBind, name: name.identText, value: c,
          info: name.info)
    elif isInstruction:
      t.fail("a canvas instruction's block has `prop = value` and " &
        "`prop <- expr` only", n)
    elif isTag(n, "cmd") and firstChild(n).identText == "on":
      var c = firstChild(n)
      skip c
      var item = Item(kind: ikOn, info: n.info)
      readEvent(t, c, item)
      skip c
      if not c.hasMore or c.stmtKind != StmtsS:
        t.fail("a handler is `on event: statements`", n)
      else:
        item.value = c
        t.nodes[index].items.add item
    elif isCanvas(n):
      if t.nodes[index].kind == nkArm:
        t.fail("`canvas:` cannot be inside `if`; put the `if` inside `canvas:`", n)
        return
      var c = firstChild(n)
      var layer = canvasMain
      if c.kind != Ident:
        var d = firstChild(c)
        skip d
        case d.identText
        of "before": layer = canvasBefore
        of "after": layer = canvasAfter
        else: t.fail("a canvas is `canvas`, `canvas.before` or `canvas.after`", c)
      skip c
      if not c.hasMore or c.stmtKind != StmtsS:
        t.fail("`canvas:` expects a block of instructions", n)
      else:
        readInstructions(t, c, layer, owner, index)
    elif isTag(n, "if"):
      let k = readIf(t, n, widget, owner, scope)
      t.nodes[index].children.add k
    elif isWidget(n):
      let k = readNode(t, n, widget, owner, scope)
      if k >= 0: t.nodes[index].children.add k
    else:
      t.fail("expected a widget, `place widget`, `prop = value`, `prop <- expr`, " &
        "`on event: ...`, `canvas: ...` or `if`", n)
    skip n

proc readPlace(t: var Tree; call: NifCursor; node: var Node; name, body: var NifCursor) =
  # `place expr [as name] [: ...]`: `expr` is an existing widget (or, in a
  # canvas, an instruction).
  var c = firstChild(call)
  skip c                       # `place`
  if not c.hasMore:
    t.fail("`place` expects a widget: `place expr [as name]`", call)
    return
  var e = c
  if isTag(c, "infix") and firstChild(c).identText == "as":
    var d = firstChild(c)
    skip d
    e = d
    skip d
    if d.kind != Ident:
      t.fail("`as` expects a name", d)
      return
    name = d
  node.placed = e
  node.typeName = if e.kind == Ident: "`" & e.identText & "`" else: "the placed widget"
  skip c
  if c.hasMore and c.stmtKind == StmtsS:
    body = c
    skip c
  if c.hasMore:
    t.fail("`place` takes one widget: `place expr [as name]`", c)

proc readNode(t: var Tree; n: NifCursor; layer: Layer; owner, scope: int): int =
  ## Reads one widget or canvas instruction and its block; returns its index.
  var call = n
  var node = Node(kind: if layer == widget: nkWidget else: nkInstruction, layer: layer,
    scope: scope, info: n.info)
  var body = NifCursor()
  var name = NifCursor()
  if isTag(n, "infix"):
    var c = firstChild(n)
    skip c                     # `as`
    call = c
    skip c
    if c.kind != Ident:
      t.fail("`as` expects a name", c)
      return -1
    name = c                   # the source token, with its position
    skip c
    if c.hasMore: body = c
  if call.kind == Ident:
    node.typeName = call.identText
  elif isPlace(call) and not isTag(n, "infix"):
    readPlace(t, call, node, name, body)
    if not t.err.isEmpty: return -1
  elif (isTag(call, "call") or isTag(call, "cmd")) and isCapitalIdent(firstChild(call)):
    var c = firstChild(call)
    node.typeName = c.identText
    skip c
    while c.hasMore and t.err.isEmpty:
      if c.stmtKind == StmtsS and not body.hasMore: body = c
      else: readArg(t, c, node)
      skip c
  else:
    t.fail("expected `Type(...)`", call)
    return -1
  if name.hasMore:
    node.handle = name
    node.def = name
  else:
    let sym = genSym()
    var use = handleTree(sym, n.info)
    node.handle = snapshot(use)
    var def = createTree()
    def.addSymDef sym, n.info
    node.def = snapshot(def)
  result = t.nodes.len
  node.owner = if layer == widget: result else: owner
  t.nodes.add node
  if body.hasMore and t.err.isEmpty:
    if body.stmtKind != StmtsS:
      t.fail("expected a block after `:`", body)
    else:
      readItems(t, body, result)

# ------------------------------------------------------------------ emitting

proc selfSubst(t: Tree; node: Node): Subst =
  # `self` is the widget an item belongs to.
  Subst(trees: @[("self", t.nodes[node.owner].handle)])

proc substituted(n: NifCursor; s: Subst): NifCursor =
  # `n` with `self` replaced.
  var b = createTree()
  var c = n
  emit(b, c, s)
  result = snapshot(b)

proc paramDef(info: LineInfo): NifCursor =
  # The definition of a callback's parameter that no user code can name
  # (the callbacks re-evaluate their expression and do not read it).
  var b = createTree()
  b.addSymDef genSym(), info
  result = snapshot(b)

proc deps(n: NifCursor; acc: var seq[(NifCursor, string)]) =
  # Every `h.p` read by an expression as written (`h` a name, `self` too).
  if n.kind != TagLit: return
  if n.exprKind == DotX:
    var c = firstChild(n)
    if c.kind == Ident:
      let obj = c
      skip c
      if c.kind == Ident:
        for (o, p) in acc:
          if o.identText == obj.identText and p == c.identText: return
        acc.add (obj, c.identText)
        return
  for c in n.children:
    deps(c, acc)

proc declared(node: Node; scope: int): bool =
  # A widget or an instruction that the block of `scope` declares.
  node.kind in {nkWidget, nkInstruction} and node.scope == scope

proc emitLets(dest: var NifBuilder; t: Tree; scope: int) =
  for node in t.nodes:
    if not node.declared(scope): continue
    if node.placed.hasMore:
      let s = Subst(trees: @[("NameV", node.def), ("ExprV", node.placed)])
      dest.emitStmts(placeCode, s, node.info)
      continue
    var args = ""
    var s = Subst(trees: @[("NameV", node.def)])
    for i in 0 ..< node.args.len:
      if i > 0: args.add ", "
      args.add "ArgV" & $i
      s.trees.add ("ArgV" & $i, node.args[i])
    let code = letCode.replace("TYPE", node.typeName).replace("ARGS", args)
    dest.emitStmts(code, s, node.info)

proc emitSets(dest: var NifBuilder; t: Tree; scope: int) =
  # The `prop = value` items of what `scope` declares, and of the arm
  # `scope` itself, in tree order.
  for i in 0 ..< t.nodes.len:
    let node = t.nodes[i]
    if not (node.declared(scope) or i == scope): continue
    for item in node.items:
      if item.kind == ikSet:
        let code = setCode.replace("PROP", item.name).replace("TYPE", node.typeName)
        let s = Subst(trees: @[("HandleV", node.handle),
          ("ValueV", substituted(item.value, t.selfSubst(node)))])
        dest.emitStmts(code, s, item.info)

proc emitBinding(dest: var NifBuilder; t: Tree; node: Node; item: Item) =
  # Set now (the set checks that the target is a property), then follow
  # every `h.p` of the expression that is a property; one at least must be.
  let self = t.nodes[node.owner].handle
  let value = substituted(item.value, t.selfSubst(node))
  let set = setCode.replace("PROP", item.name).replace("TYPE", node.typeName)
  var s = Subst(trees: @[("HandleV", node.handle), ("ValueV", value)])
  dest.emitStmts(set, s, item.info)
  var acc: seq[(NifCursor, string)] = @[]
  deps(item.value, acc)        # checked non-empty by `transform`
  var checks: seq[string] = @[]
  var read: seq[string] = @[]
  for i in 0 ..< acc.len:
    let (obj, prop) = acc[i]
    let dep = "Dep" & $i & "V"
    s.trees.add (dep, if obj.identText == "self": self else: obj)
    let check = "compiles(" & dep & ".bind" & capital(prop) & "(proc (v: typeof(" & dep &
      "." & prop & ")) {.closure.} = discard))"
    checks.add check
    read.add obj.identText & "." & prop
    let code = bindCode.replace("DepV", dep).replace("bindDEP", "bind" & capital(prop)).
      replace(".dep", "." & prop).replace("PROP", item.name)
    var sd = s
    sd.trees.add ("ParamV", paramDef(item.info))
    dest.emitStmts("when " & check & ":\n" & indent(code, 2), sd, item.info)
  let none = "when not (" & checks.join(" or ") & "):\n  {.error: \"buildUi: `" &
    item.name & " <- ...` follows no property: " & read.join(", ") &
    (if read.len == 1: " is not one" else: " are not") & "\".}\n"
  dest.emitStmts(none, s, item.info)

proc emitHandler(dest: var NifBuilder; t: Tree; node: Node; item: Item) =
  var recv = "HandleV"
  for p in item.path: recv.add "." & p
  # A property handler without parameters gets the value in a parameter the
  # body cannot name.
  let propParams = if item.hasParams: item.params
    else: "ParamV: typeof(RecvV." & item.name & ")"
  let propCheck = if item.hasParams: item.params
    else: "v: typeof(RecvV." & item.name & ")"
  let what = (if item.path.len > 0: item.path.join(".") & "." else: "") & item.name & "` " &
    (if item.hasParams: "with parameters (" & item.shown & ")" else: "without parameters")
  let code = eventCode.replace("PROPCHECK", propCheck).replace("PROPPARAMS", propParams).
    replace("PARAMS", item.params).    replace("RecvV", recv).replace("EVENT", capital(item.name)).
    replace("TYPE", node.typeName).replace("WHAT", what)
  var s = Subst(trees: @[("HandleV", node.handle),
    ("BodyV", substituted(item.value, t.selfSubst(node)))])
  s.trees.add ("ParamV", paramDef(item.info))
  for i in 0 ..< item.paramTypes.len:
    s.trees.add ("ArgT" & $i, item.paramTypes[i])
  dest.emitStmts(code, s, item.info)

proc emitNode(dest: var NifBuilder; t: Tree; i: int)

proc emitIf(dest: var NifBuilder; t: Tree; k: int) =
  # `if Cond0V: Body0V elif ...: ... else: ...`, each body an arm built
  # where it stands: what it declares, its sets, then the rest of the arm.
  let node = t.nodes[k]
  var code = ""
  var s = Subst(trees: @[])
  for j in 0 ..< node.arms.len:
    let a = node.arms[j]
    if j < node.conds.len:
      code.add (if j == 0: "if " else: "elif ") & "Cond" & $j & "V:\n"
      s.trees.add ("Cond" & $j & "V", substituted(node.conds[j], t.selfSubst(node)))
    else:
      code.add "else:\n"
    code.add "  Body" & $j & "V\n"
    var b = createTree()
    b.withTree StmtsS, t.nodes[a].info:
      b.emitLets(t, a)
      b.emitSets(t, a)
      b.emitNode(t, a)
    s.trees.add ("Body" & $j & "V", snapshot(b))
  dest.emitStmts(code, s, node.info)

proc emitNode(dest: var NifBuilder; t: Tree; i: int) =
  # Completes widget `i` (or the rest of an arm of an `if` in it): its
  # canvas instructions, its children (each complete before it is added),
  # then the bindings of the widget and its instructions and the widget's
  # handlers. So a child's handlers see it being added (a Screen's `enter`),
  # and a widget's own handlers do not see its children being added (a
  # ScreenManager's `current`). An `if` is built where it stands among the
  # instructions or the children.
  let node = t.nodes[i]
  let owner = t.nodes[node.owner]
  for k in node.instructions:
    if t.nodes[k].kind == nkIf:
      dest.emitIf(t, k)
      continue
    let canvas = case t.nodes[k].layer
      of canvasBefore: "canvas.before"
      of canvasAfter: "canvas.after"
      else: "canvas"
    let s = Subst(trees: @[("OwnerV", owner.handle), ("HandleV", t.nodes[k].handle)])
    dest.emitStmts(canvasCode.replace("CANVAS", canvas), s, t.nodes[k].info)
  for c in node.children:
    if t.nodes[c].kind == nkIf:
      dest.emitIf(t, c)
      continue
    emitNode(dest, t, c)
    let s = Subst(trees: @[("OwnerV", owner.handle), ("HandleV", t.nodes[c].handle)])
    dest.emitStmts(addCode, s, t.nodes[c].info)
  for k in node.instructions:
    for item in t.nodes[k].items:
      if item.kind == ikBind: dest.emitBinding(t, t.nodes[k], item)
  for item in node.items:
    if item.kind == ikBind: dest.emitBinding(t, node, item)
  for item in node.items:
    if item.kind == ikOn: dest.emitHandler(t, node, item)

proc transform(root: NifCursor): NifBuilder =
  var body = callArgs(root)
  if body.stmtKind != StmtsS:
    return errorTree("buildUi expects a block with one widget", root)
  var b = firstChild(body)
  if not isWidget(b):
    return errorTree("buildUi expects a widget: `Type(...) [as name]: ...`", b)
  var t = Tree(nodes: @[], err: createTree())
  discard readNode(t, b, widget, 0, -1)
  if not t.err.isEmpty: return t.err
  skip b
  if b.hasMore:
    return errorTree("buildUi expects one root widget", b)
  for node in t.nodes:
    for item in node.items:
      if item.kind == ikBind:
        var acc: seq[(NifCursor, string)] = @[]
        deps(item.value, acc)
        if acc.len == 0:
          return errorTree("buildUi: `" & item.name & " <- ...` reads no " &
            "`object.property`; a value set once is `" & item.name & " = ...`", item.value)
  result = createTree()
  result.withTree StmtsS, root.info:
    result.emitLets(t, -1)
    result.emitSets(t, -1)
    result.emitNode(t, 0)

saveTree transform(loadPluginInput())
