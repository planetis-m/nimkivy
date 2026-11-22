## The Nim syntax trees the property kinds build, in the shape `nimparser`
## gives the same code: names and types as trees of their own, routine and
## closure declarations, fields, operators, `if` and `discard`. Each helper
## opens its node at `info` and leaves the rest to the caller.

import plugins

type
  Param* = object
    name*: string
    typ*: NifCursor

  Head* = object
    ## A generated routine: `proc name*(params): ret {.pragma.}`.
    kind*: NimonyStmt          # ProcS or MethodS
    name*: NifCursor
    exported*: bool
    params*: seq[Param]
    ret*: NifCursor            # empty: none
    pragma*: string            # "" (none), "inline" or "base"

# ------------------------------------------------------------------ names and types

proc identTree*(name: string): NifCursor =
  ## The identifier `name` as a tree of its own, to pass where a tree goes.
  var t = createTree()
  t.addIdent name
  result = snapshot(t)

proc quotedName*(parts: openArray[string]; info: LineInfo): NifCursor =
  ## A name in backticks: `["x", "="]` is `` `x=` ``.
  var t = createTree()
  t.withTree QuotedX, info:
    for s in parts: t.addIdent s
  result = snapshot(t)

proc sinkOf*(typ: NifCursor; info: LineInfo): NifCursor =
  ## `sink typ`.
  var t = createTree()
  t.withTree CmdX, info:
    t.addIdent "sink"
    t.addSubtree typ
  result = snapshot(t)

proc addParams*(dest: var NifBuilder; params: seq[Param]; info: LineInfo) =
  dest.withTree ParamsU, info:
    for p in params:
      dest.withTree ParamU, info:
        dest.addIdent p.name
        dest.addEmptyNode2 info  # export, pragmas
        dest.addSubtree p.typ
        dest.addEmptyNode info   # default

proc closureType*(params: seq[Param]; ret: NifCursor; info: LineInfo): NifCursor =
  ## `proc (params): ret {.closure.}`; an empty `ret` is none.
  var t = createTree()
  t.withTree ProctypeT, info:
    t.addEmptyNode4 info       # name, export, pattern, type vars
    t.addParams params, info
    if ret.hasMore: t.addSubtree ret
    else: t.addEmptyNode info
    t.withTree PragmasU, info:
      t.addIdent "closure"
    t.addEmptyNode2 info       # effects, body
  result = snapshot(t)

# ------------------------------------------------------------------ declarations

proc addHead(dest: var NifBuilder; h: Head; info: LineInfo) =
  dest.addSubtree h.name
  if h.exported: dest.addIdent "x"
  else: dest.addEmptyNode info
  dest.addEmptyNode2 info      # pattern, type vars
  dest.addParams h.params, info
  if h.ret.hasMore: dest.addSubtree h.ret
  else: dest.addEmptyNode info
  if h.pragma.len > 0:
    dest.withTree PragmasU, info:
      dest.addIdent h.pragma
  else:
    dest.addEmptyNode info
  dest.addEmptyNode info       # effects

template withRoutine*(dest: var NifBuilder; h: Head; info: LineInfo; body: untyped) =
  ## The routine `h`; `body` emits its statements.
  dest.withTree h.kind, info:
    dest.addHead h, info
    dest.withTree StmtsS, info:
      body

template withClosure*(dest: var NifBuilder; params: seq[Param]; info: LineInfo;
    body: untyped) =
  ## `proc (params) {.closure.} = body`.
  dest.withTree ProcS, info:
    dest.addEmptyNode4 info    # name, export, pattern, type vars
    dest.addParams params, info
    dest.addEmptyNode info     # return type
    dest.withTree PragmasU, info:
      dest.addIdent "closure"
    dest.addEmptyNode info     # effects
    dest.withTree StmtsS, info:
      body

proc addField*(dest: var NifBuilder; name: string; typ: NifCursor; info: LineInfo) =
  ## The field `name: typ`.
  dest.withTree FldU, info:
    dest.addIdent name
    dest.addEmptyNode2 info    # export, pragmas
    dest.addSubtree typ
    dest.addEmptyNode info     # default

# ------------------------------------------------------------------ expressions and statements

template withInfix*(dest: var NifBuilder; op: string; info: LineInfo;
    operands: untyped) =
  ## `a op b`; `operands` emits `a` and `b`.
  dest.withTree InfixX, info:
    dest.addIdent op
    operands

template withPrefix*(dest: var NifBuilder; op: string; info: LineInfo;
    operand: untyped) =
  ## `op a`; `operand` emits `a`.
  dest.withTree PrefixX, info:
    dest.addIdent op
    operand

template withIf*(dest: var NifBuilder; info: LineInfo; cond, body: untyped) =
  ## `if cond: body`; `cond` emits the condition, `body` the statements.
  dest.withTree IfS, info:
    dest.withTree ElifU, info:
      cond
      dest.withTree StmtsS, info:
        body

proc addDiscard*(dest: var NifBuilder; info: LineInfo) =
  ## `discard`.
  dest.withTree DiscardS, info:
    dest.addEmptyNode info
