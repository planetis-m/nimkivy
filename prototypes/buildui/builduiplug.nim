## The `buildUi:` plugin (prototype): a declarative widget tree with Kivy's
## update model. The tree is built once; a binding (`prop <- expr`) sets the
## property now and again whenever a property that `expr` reads changes.
##
## Grammar (the block of `buildUi:`):
##
## .. code-block::
##   widget  = Type(prop = value, ...) [as name] [: item+]
##   item    = prop = value              # set once
##           | prop <- expr              # bound: every `handle.prop` in expr
##           | on event[(params)]: stmts # an event handler
##           | widget                    # a child, added in order
##
## Expansion, in the caller's scope:
##
## 1. `let name = newType()` for every widget, in tree order (a widget
##    without `as name` gets a generated symbol), so every handle exists
##    before any binding or handler refers to it;
## 2. the `prop = value` items, in tree order;
## 3. `parent.addWidget(child)`, children complete before they are added;
## 4. each binding: `w.prop = expr`, then for each `h.p` read by `expr`,
##    `h.bindP(proc (v: typeof(h.p)) = w.prop = expr)`;
## 5. each handler: `w.bindEvent(proc (params): bool = stmts; false)`.

import std/strutils
import plugins, nimparser
import ../codegen

type
  Item = object
    kind: string               # "set", "bind", "on"
    name: string               # the property or event
    nameNode: NifCursor        # its token, which carries its position
    value: NifCursor           # the value, expression or handler body
    params: string             # "on": the handler's parameters as text
    paramTypes: seq[NifCursor]
    info: LineInfo

  Node = object
    typeName: string
    handle: NifCursor          # one token: the name or the generated symbol
    named: bool
    name: string
    sym: SymId
    items: seq[Item]
    children: seq[int]
    info: LineInfo

const
  bindCode = """
discard DepV.bindDprop(proc (v: typeof(DepV.dprop)) {.closure.} =
  HandleV.target = ExprV)
"""
  onCode = """
discard HandleV.bindEvent(proc ($1): bool {.closure.} =
  BodyV
  false)
"""

proc isWidget(n: NifCursor): bool =
  # `Type(...)` or `Type(...) as name`.
  if n.kind != TagLit: return false
  let tag = n.tagText
  if tag == "infix":
    result = firstChild(n).identText == "as"
  else:
    # A type name starts with a capital letter (`on press:` is a `cmd` too).
    let head = firstChild(n)
    result = tag in ["call", "cmd"] and head.kind == Ident and
      head.identText.len > 0 and head.identText[0] in {'A' .. 'Z'}

proc readItems(n: var NifCursor; items: var seq[Item]; kids: var seq[int];
    nodes: var seq[Node]; err: var NifBuilder)

proc readNode(n: NifCursor; nodes: var seq[Node]; err: var NifBuilder): int =
  ## Reads one widget and its subtree; returns its index in `nodes`.
  var call = n
  var node = Node(info: n.info)
  var body = NifCursor()
  if n.tagText == "infix":
    var c = firstChild(n)
    skip c                     # `as`
    call = c
    skip c
    if c.kind != Ident:
      err = errorTree("`as` expects a name", c)
      return -1
    node.named = true
    node.name = c.identText
    node.handle = c            # the source token, with its position
    skip c
    if c.hasMore: body = c
  var c = firstChild(call)
  node.typeName = c.identText
  skip c
  while c.hasMore:
    if c.kind == TagLit and c.tagText == "vv":
      var kv = firstChild(c)
      let nameNode = kv
      skip kv
      node.items.add Item(kind: "set", name: nameNode.identText, nameNode: nameNode,
        value: kv, info: c.info)
    elif c.kind == TagLit and c.stmtKind == StmtsS:
      body = c
    else:
      err = errorTree("a widget's arguments are `prop = value`", c)
      return -1
    skip c
  if not node.named:
    node.sym = genSym()
    var h = handleTree(node.sym, n.info)
    node.handle = snapshot(h)
  result = nodes.len
  nodes.add node
  if body.hasMore:
    # Read into locals: `nodes` grows while the children are read.
    var b = firstChild(body)
    var items: seq[Item] = @[]
    var kids: seq[int] = @[]
    readItems(b, items, kids, nodes, err)
    for it in items: nodes[result].items.add it
    nodes[result].children = kids

proc readParams(call: NifCursor; item: var Item) =
  # `touch(x, y: float)`: names, each group closed by a typed one.
  var c = firstChild(call)
  skip c                       # the event name
  var group = ""
  while c.hasMore:
    if c.kind == Ident:
      if group.len > 0: group.add ", "
      group.add c.identText
    else:                      # (kv name type)
      var kv = firstChild(c)
      if group.len > 0: group.add ", "
      group.add kv.identText
      skip kv
      if item.params.len > 0: item.params.add "; "
      item.params.add group & ": ArgT" & $item.paramTypes.len
      item.paramTypes.add kv
      group = ""
    skip c

proc readItems(n: var NifCursor; items: var seq[Item]; kids: var seq[int];
    nodes: var seq[Node]; err: var NifBuilder) =
  while n.hasMore and err.isEmpty:
    if isWidget(n):
      let child = readNode(n, nodes, err)
      if child >= 0: kids.add child
    elif n.stmtKind == AsgnS:
      var c = firstChild(n)
      let nameNode = c
      skip c
      items.add Item(kind: "set", name: nameNode.identText, nameNode: nameNode,
        value: c, info: n.info)
    elif n.tagText == "infix" and firstChild(n).identText == "<-":
      var c = firstChild(n)
      skip c
      let nameNode = c
      skip c
      items.add Item(kind: "bind", name: nameNode.identText, nameNode: nameNode,
        value: c, info: n.info)
    elif n.tagText == "cmd" and firstChild(n).identText == "on":
      var c = firstChild(n)
      skip c
      var item = Item(kind: "on", info: n.info)
      if c.kind == Ident:
        item.name = c.identText
      else:
        item.name = firstChild(c).identText
        readParams(c, item)
      skip c
      item.value = c
      items.add item
    else:
      err = errorTree("expected a widget, `prop = value`, `prop <- expr` or " &
        "`on event: ...`", n)
    skip n

proc deps(n: NifCursor; acc: var seq[(NifCursor, string)]) =
  # Every `handle.prop` read by an expression.
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

# ------------------------------------------------------------------ emitting

proc emitLets(dest: var NifBuilder; nodes: seq[Node]) =
  for node in nodes:
    dest.withTree LetS, node.info:
      if node.named: dest.addIdent node.name
      else: dest.addSymDef node.sym, node.info
      dest.addEmptyNode3(node.info)
      dest.withTree CallX, node.info:
        dest.addIdent "new" & node.typeName

proc emitSets(dest: var NifBuilder; nodes: seq[Node]) =
  for node in nodes:
    for item in node.items:
      if item.kind == "set":
        dest.withTree AsgnS, item.info:
          dest.withTree DotX, item.info:
            dest.addSubtree node.handle
            dest.addSubtree item.nameNode   # keeps the source position
          dest.addSubtree item.value

proc emitAdds(dest: var NifBuilder; nodes: seq[Node]; i: int) =
  # Children are complete (their own children added) before they are added.
  for c in nodes[i].children:
    emitAdds(dest, nodes, c)
    dest.withTree CallS, nodes[c].info:
      dest.addIdent "addWidget"
      dest.addSubtree nodes[i].handle
      dest.addSubtree nodes[c].handle

proc emitBindings(dest: var NifBuilder; nodes: seq[Node]) =
  for node in nodes:
    for item in node.items:
      if item.kind == "bind":
        dest.withTree AsgnS, item.info:
          dest.withTree DotX, item.info:
            dest.addSubtree node.handle
            dest.addSubtree item.nameNode   # keeps the source position
          dest.addSubtree item.value
        var acc: seq[(NifCursor, string)] = @[]
        deps(item.value, acc)
        for (obj, prop) in acc:
          let code = bindCode.replace("bindDprop", "bind" & capital(prop)).
            replace("dprop", prop).replace("target", item.name)
          let s = Subst(trees: @[("DepV", obj), ("HandleV", node.handle),
            ("ExprV", item.value)])
          dest.emitStmts(code, s, item.info)
      elif item.kind == "on":
        let code = onCode.replace("bindEvent", "bind" & capital(item.name)).
          replace("$1", item.params)
        var s = Subst(trees: @[("HandleV", node.handle), ("BodyV", item.value)])
        for i in 0 ..< item.paramTypes.len:
          s.trees.add ("ArgT" & $i, item.paramTypes[i])
        dest.emitStmts(code, s, item.info)

proc transform(root: NifCursor): NifBuilder =
  var body = callArgs(root)
  if body.stmtKind != StmtsS:
    return errorTree("buildUi expects a block with one widget", root)
  var b = firstChild(body)
  if not isWidget(b):
    return errorTree("buildUi expects a widget: `Type(...) [as name]: ...`", b)
  var err = createTree()
  var nodes: seq[Node] = @[]
  discard readNode(b, nodes, err)
  if not err.isEmpty: return err
  skip b
  if b.hasMore:
    return errorTree("buildUi expects one root widget", b)
  result = createTree()
  result.withTree StmtsS, root.info:
    result.emitLets(nodes)
    result.emitSets(nodes)
    result.emitAdds(nodes, 0)
    result.emitBindings(nodes)

saveTree transform(loadPluginInput())
