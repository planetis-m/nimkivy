## Nim syntax trees shared by nimkivy's plugins (`propsplug`, `builduiplug`),
## built node by node in the shape `nimparser` gives the same code. Each
## helper opens its node at `info` and leaves the rest to the caller.

# GAP: a generated identifier or literal has no position, because the plugin
# API's `addIdent`, `addStrLit`, `addIntLit` and `addFloatLit` take no
# `LineInfo`: an error at one prints `???` instead of the line it comes
# from (planetis-m/nimony-bugs-llms#352)

import std/strutils
import plugins

proc capital*(s: string): string =
  result = s
  if result.len > 0: result[0] = toUpperAscii(result[0])

proc addDot*(dest: var NifBuilder; obj: NifCursor; field: string; info: LineInfo) =
  ## `obj.field`.
  dest.withTree DotX, info:
    dest.addSubtree obj
    dest.addIdent field

template withCall*(dest: var NifBuilder; callee: string; info: LineInfo;
    args: untyped) =
  ## `callee(args)`; `args` emits the arguments.
  dest.withTree CallX, info:
    dest.addIdent callee
    args

template withLet*(dest: var NifBuilder; name: NifCursor; info: LineInfo;
    value: untyped) =
  ## `let name = value`; `value` emits the value.
  dest.withTree LetS, info:
    dest.addSubtree name
    dest.addEmptyNode3 info  # export, pragmas, type
    value

template withDiscardCall*(dest: var NifBuilder; obj: NifCursor; routine: string;
    info: LineInfo; args: untyped) =
  ## `discard obj.routine(args)`; `args` emits the arguments.
  dest.withTree DiscardS, info:
    dest.withTree CallX, info:
      dest.addDot obj, routine, info
      args
