# Ports kivy/tests/test_properties.py (the tests listed in ACCEPTANCE.md) to
# the typed properties of `nimkivy/props`, and checks the kinds and the
# observer order phase 1 had: the first 44 lines of the `properties` trace
# (Widget's x, y, pos, right, top, center, width, size and BoxLayout's
# padding) replayed on a typed copy of those properties.
#
# Each Kivy test declares its property on a class of its own; here each is a
# type in the block below. Kivy attaches each property two ways (`set_name` +
# `link_eagerly`, or `link` + `link_deps`); typed properties have one way,
# `initProps`, so those loops are gone. The alias tests still run with and
# without `watch_before_use` (`eager`), on two types. The type-rejection
# halves are dropped: Nim's types make them compile errors (tests/bad).

import std/[assertions, formatfloat, strutils, syncio]
import nimkivy/props

properties:
  type
    BaseTest = ref object of RootObj
      a {.prop.}: int = -1
    ObjectTest = ref object of RootObj
      a {.prop.}: bool = false
    StringTest = ref object of RootObj
      a {.prop.}: string = ""
    NumericTest = ref object of RootObj
      a {.prop.}: float = 0.0
    ListTest = ref object of RootObj
      a {.prop.}: seq[float] = @[]
    NoneTest = ref object of RootObj
      a {.prop.}: Opt[float] = some(0.0)
    ReferenceTest = ref object of RootObj
      x {.prop.}: float = 0.0
      y {.prop.}: float = 0.0
      pos {.refs: (x, y).}: (float, float)
    ColorTest = ref object of RootObj
      color {.color.}: Rgba = [1.0, 1, 1, 1]
      color2 {.color.}: Rgba = [1.0, 1, 1, 1]

    # The alias tests' classes: the counters Kivy keeps as plain attributes.
    Counted = ref object of RootObj
      getterCalled: int
      setterCalled: int
      callbackCalled: int
    ReadOnlyEager = ref object of Counted
      prop {.alias: getFive, eager.}: int
    ReadOnlyLazy = ref object of Counted
      prop {.alias: getFive.}: int
    AliasEager = ref object of Counted
      prop {.alias: (getNone, setFalse), eager.}: Opt[int]
    AliasLazy = ref object of Counted
      prop {.alias: (getNone, setFalse).}: Opt[int]
    CachedEager = ref object of Counted
      prop {.alias: (getFive, setTrue), cache, eager.}: int
    CachedLazy = ref object of Counted
      prop {.alias: (getFive, setTrue), cache.}: int
    XWidth = ref object of Counted
      x {.prop.}: float = 0.0
      width {.prop.}: float = 100.0
    RightEager = ref object of XWidth
      right {.alias: (getRight, setRight), deps: (x, width), eager.}: float
    RightLazy = ref object of XWidth
      right {.alias: (getRight, setRight), deps: (x, width).}: float
    ForcedEager = ref object of Counted
      prop {.alias: (getNone, setFalse), always, eager.}: Opt[int]
    ForcedLazy = ref object of Counted
      prop {.alias: (getNone, setFalse), always.}: Opt[int]
    Doubled = ref object of Counted
      baseValue {.prop.}: float = 1.0
    DoubledEager = ref object of Doubled
      prop {.alias: (getDouble, setHalf), deps: baseValue, cache, eager.}: float
    DoubledLazy = ref object of Doubled
      prop {.alias: (getDouble, setHalf), deps: baseValue, cache.}: float
    PlainDoubled = ref object of Counted
      baseValue: float
    PlainDoubledEager = ref object of PlainDoubled
      prop {.alias: (getPlainDouble, setPlainHalf), cache, always, eager.}: float
    PlainDoubledLazy = ref object of PlainDoubled
      prop {.alias: (getPlainDouble, setPlainHalf), cache, always.}: float

    Event = ref object of RootObj
      a {.prop.}: string = "hello"
    Event2 = ref object of Event
      b {.prop.}: string = "hello2"

    # The kinds that test_properties.py does not reach.
    Kinds = ref object of RootObj
      level {.bounds: 0 .. 10, handler.}: int = 0
      doubled {.alias: getDoubled, deps: level, eager.}: int
      lazyDoubled {.alias: getDoubled, deps: level.}: int
      spacing {.varlist: 2.}: array[2, float]
      every {.prop, always.}: int = 0
      log: seq[string]
    KindsSub = ref object of Kinds

    # Widget's geometry and BoxLayout's padding, as phase 1 declares them.
    TraceWidget = ref object of RootObj
      x {.prop.}: float = 0.0
      y {.prop.}: float = 0.0
      width {.prop.}: float = 100.0
      height {.prop.}: float = 100.0
      pos {.refs: (x, y).}: (float, float)
      size {.refs: (width, height).}: (float, float)
      right {.alias: (getRight, setRight), deps: (x, width), cache.}: float
      top {.alias: (getTop, setTop), deps: (y, height), cache.}: float
      centerX {.alias: (getCenterX, setCenterX), deps: (x, width), cache.}: float
      centerY {.alias: (getCenterY, setCenterY), deps: (y, height), cache.}: float
      center {.refs: (centerX, centerY).}: (float, float)
    TraceBox = ref object of TraceWidget
      padding {.varlist: 4.}: array[4, float]

  # def _get_prop(self): self.getter_called += 1; return 5
  proc getFive(w: Counted): int =
    inc w.getterCalled
    result = 5

  proc getNone(w: Counted): Opt[int] =
    inc w.getterCalled
    result = none[int]()

  proc setFalse(w: Counted; v: Opt[int]): bool =
    inc w.setterCalled
    result = false

  proc setTrue(w: Counted; v: int): bool =
    inc w.setterCalled
    result = true

  # def callback(widget, value): widget.callback_called += 1. A proc, not a
  # literal in the test templates: a proc literal in an {.untyped.} template
  # crashes nimsem (planetis-m/nimony-bugs-llms#338).
  proc countCalls[T](w: Counted): proc (v: T) {.closure.} =
    result = proc (v: T) {.closure.} = inc w.callbackCalled

  proc getRight(w: XWidth): float = w.x + w.width

  proc setRight(w: XWidth; v: float): bool =
    w.x = v - w.width
    result = false

  proc getDouble(w: Doubled): float =
    inc w.getterCalled
    result = w.baseValue * 2

  proc setHalf(w: Doubled; v: float): bool =
    w.baseValue = v / 2
    result = false

  proc getPlainDouble(w: PlainDoubled): float =
    inc w.getterCalled
    result = w.baseValue * 2

  proc setPlainHalf(w: PlainDoubled; v: float): bool =
    inc w.setterCalled
    w.baseValue = v / 2
    result = true

  proc getDoubled(w: Kinds): int = 2 * w.level

  method onLevelChanged(w: Kinds; v: int) {.base.} =
    w.log.add "handler " & $v

  method onLevelChanged(w: KindsSub; v: int) =
    w.log.add "subclass handler " & $v

  proc getRight(w: TraceWidget): float = w.x + w.width

  proc setRight(w: TraceWidget; v: float): bool =
    w.x = v - w.width
    result = false

  proc getTop(w: TraceWidget): float = w.y + w.height

  proc setTop(w: TraceWidget; v: float): bool =
    w.y = v - w.height
    result = false

  proc getCenterX(w: TraceWidget): float = w.x + w.width / 2.0

  proc setCenterX(w: TraceWidget; v: float): bool =
    w.x = v - w.width / 2.0
    result = false

  proc getCenterY(w: TraceWidget): float = w.y + w.height / 2.0

  proc setCenterY(w: TraceWidget; v: float): bool =
    w.y = v - w.height / 2.0
    result = false

block test_base:
  # kivy/tests/test_properties.py::test_base
  let wid = BaseTest()
  wid.initProps()
  assert wid.a == -1
  wid.a = 0
  assert wid.a == 0
  wid.a = 1
  assert wid.a == 1

block test_observer:
  # kivy/tests/test_properties.py::test_observer
  let wid = BaseTest()
  wid.initProps()
  assert wid.a == -1
  var observeCalled = 0
  discard wid.bindA(proc (v: int) {.closure.} = observeCalled = 1)
  wid.a = 0
  assert wid.a == 0
  assert observeCalled == 1
  observeCalled = 0
  wid.a = 0
  assert wid.a == 0
  assert observeCalled == 0
  wid.a = 1
  assert wid.a == 1
  assert observeCalled == 1

block test_objectcheck:
  # kivy/tests/test_properties.py::test_objectcheck
  let wid = ObjectTest()
  wid.initProps()
  assert wid.a == false
  wid.a = true
  assert wid.a == true

block test_stringcheck:
  # kivy/tests/test_properties.py::test_stringcheck (without the number)
  let wid = StringTest()
  wid.initProps()
  assert wid.a == ""
  wid.a = "hello"
  assert wid.a == "hello"

block test_numericcheck:
  # kivy/tests/test_properties.py::test_numericcheck
  let wid = NumericTest()
  wid.initProps()
  assert wid.a == 0.0
  wid.a = 99.0
  assert wid.a == 99.0

block test_listcheck:
  # kivy/tests/test_properties.py::test_listcheck
  let wid = ListTest()
  wid.initProps()
  assert wid.a == newSeq[float]()
  wid.a = @[1.0, 2, 3]
  assert wid.a == @[1.0, 2, 3]

block test_propertynone:
  # kivy/tests/test_properties.py::test_propertynone
  let wid = NoneTest()
  wid.initProps()
  assert wid.a == some(0.0)
  wid.a = none[float]()
  assert wid.a.isNone
  wid.a = some(1.0)
  assert wid.a == some(1.0)

block test_reference:
  # kivy/tests/test_properties.py::test_reference
  let wid = ReferenceTest()
  wid.initProps()
  assert wid.x == 0.0
  assert wid.y == 0.0
  assert wid.pos == (0.0, 0.0)
  wid.x = 50.0
  assert wid.pos == (50.0, 0.0)
  wid.y = 50.0
  assert wid.pos == (50.0, 50.0)
  wid.pos = (0.0, 0.0)
  assert wid.pos == (0.0, 0.0)
  assert wid.x == 0.0
  assert wid.y == 0.0
  var observeCalled = 0
  discard wid.bindPos(proc (v: (float, float)) {.closure.} = observeCalled = 1)
  assert observeCalled == 0
  wid.x = 99.0
  assert observeCalled == 1

block test_color_property:
  # kivy/tests/test_properties.py::test_color_property: the list and tuple
  # forms. Colour names, hex strings and in-place item assignment are out
  # of scope, so the shared value is set as a whole.
  let wid = ColorTest()
  wid.initProps()
  assert wid.color == [1.0, 1, 1, 1]
  assert wid.color2 == [1.0, 1, 1, 1]
  wid.color = [1.0, 1, 0]
  assert wid.color == [1.0, 1, 0, 1]
  wid.color = [1.0, 1, 0, 0]
  assert wid.color == [1.0, 1, 0, 0]
  wid.color = [0.5, 1, 1, 1]
  assert wid.color == [0.5, 1, 1, 1]
  assert wid.color2 == [1.0, 1, 1, 1]
  wid.color2 = wid.color
  assert wid.color2 == [0.5, 1, 1, 1]

# ------------------------------------------------------------------ alias
# Each test runs on a type with `eager` (Kivy's watch_before_use=True) and
# on one without. The templates are {.untyped.}: each is used with two types.

template aliasWithoutSetter(T: untyped) {.untyped.} =
  # kivy/tests/test_properties.py::test_alias_property_without_setter (the
  # getter half; setting a read-only alias is a compile error, tests/bad)
  let wid = T()
  wid.initProps()
  assert wid.getterCalled == 0
  assert wid.prop == 5
  assert wid.getterCalled == 1

template aliasProperty(T: untyped) {.untyped.} =
  # kivy/tests/test_properties.py::test_alias_property
  let wid = T()
  wid.initProps()
  discard wid.bindProp(countCalls[Opt[int]](wid))
  assert wid.getterCalled == 0 and wid.setterCalled == 0 and wid.callbackCalled == 0
  wid.prop = some(1)
  assert wid.getterCalled == 0 and wid.setterCalled == 1 and wid.callbackCalled == 0
  wid.prop = some(1)
  assert wid.getterCalled == 0 and wid.setterCalled == 2 and wid.callbackCalled == 0
  assert wid.prop.isNone
  assert wid.getterCalled == 1 and wid.setterCalled == 2 and wid.callbackCalled == 0

template aliasCacheTrue(T: untyped) {.untyped.} =
  # kivy/tests/test_properties.py::test_alias_property_cache_true
  let wid = T()
  wid.initProps()
  assert wid.getterCalled == 0 and wid.setterCalled == 0
  assert wid.prop == 5
  assert wid.getterCalled == 1 and wid.setterCalled == 0
  assert wid.prop == 5
  assert wid.getterCalled == 1 and wid.setterCalled == 0
  wid.prop = 10
  assert wid.prop == 5
  assert wid.setterCalled == 1 and wid.getterCalled == 2

template aliasWithBind(T: untyped) {.untyped.} =
  # kivy/tests/test_properties.py::test_alias_property_with_bind
  let wid = T()
  wid.initProps()
  assert wid.right == 100.0
  wid.x = 500.0
  assert wid.right == 600.0
  wid.width = 50.0
  assert wid.right == 550.0
  wid.right = 100.0
  assert wid.width == 50.0
  assert wid.x == 50.0
  discard wid.bindRight(countCalls[float](wid))
  wid.x = 100.0
  assert wid.callbackCalled == 1
  wid.x = 100.0
  assert wid.callbackCalled == 1
  wid.width = 900.0
  assert wid.callbackCalled == 2
  wid.right = 700.0
  assert wid.callbackCalled == 3
  wid.right = 700.0
  assert wid.callbackCalled == 3

template aliasForceDispatchTrue(T: untyped) {.untyped.} =
  # kivy/tests/test_properties.py::test_alias_property_with_force_dispatch_true
  let wid = T()
  wid.initProps()
  discard wid.bindProp(countCalls[Opt[int]](wid))
  assert wid.getterCalled == 0 and wid.setterCalled == 0 and wid.callbackCalled == 0
  wid.prop = some(1)
  assert wid.getterCalled == 1 and wid.setterCalled == 1 and wid.callbackCalled == 1
  wid.prop = some(1)
  assert wid.getterCalled == 2 and wid.setterCalled == 2 and wid.callbackCalled == 2

template aliasCacheTrueWithBind(T: untyped; eager: bool) {.untyped.} =
  # kivy/tests/test_properties.py::test_alias_property_cache_true_with_bind
  let wid = T()
  wid.initProps()
  assert wid.getterCalled == 0
  assert wid.baseValue == 1.0
  assert wid.getterCalled == 0
  wid.baseValue = 4.0
  assert wid.getterCalled == ord(eager)
  assert wid.prop == 8.0
  assert wid.getterCalled == 1
  wid.prop = 4.0
  assert wid.getterCalled == 2
  assert wid.baseValue == 2.0
  assert wid.prop == 4.0
  assert wid.getterCalled == 2

template aliasCacheTrueForceDispatchTrue(T: untyped) {.untyped.} =
  # kivy/tests/test_properties.py::test_alias_property_cache_true_force_dispatch_true
  # Set after the constructor: `T(baseValue: 1.0)` here gives invalid C, as
  # Doubled has a `baseValue` accessor (planetis-m/nimony-bugs-llms#339).
  let wid = T()
  wid.baseValue = 1.0
  wid.initProps()
  discard wid.bindProp(countCalls[float](wid))
  assert wid.baseValue == 1.0
  assert wid.getterCalled == 0 and wid.setterCalled == 0 and wid.callbackCalled == 0
  wid.prop = 16.0
  assert wid.baseValue == 8.0
  assert wid.getterCalled == 1 and wid.setterCalled == 1 and wid.callbackCalled == 1
  wid.prop = 16.0
  assert wid.baseValue == 8.0
  assert wid.getterCalled == 2 and wid.setterCalled == 2 and wid.callbackCalled == 2
  assert wid.prop == 16.0
  assert wid.getterCalled == 2 and wid.setterCalled == 2 and wid.callbackCalled == 2

block test_alias_property_without_setter:
  aliasWithoutSetter(ReadOnlyEager)
  aliasWithoutSetter(ReadOnlyLazy)

block test_alias_property:
  aliasProperty(AliasEager)
  aliasProperty(AliasLazy)

block test_alias_property_cache_true:
  aliasCacheTrue(CachedEager)
  aliasCacheTrue(CachedLazy)

block test_alias_property_with_bind:
  aliasWithBind(RightEager)
  aliasWithBind(RightLazy)

block test_alias_property_with_force_dispatch_true:
  aliasForceDispatchTrue(ForcedEager)
  aliasForceDispatchTrue(ForcedLazy)

block test_alias_property_cache_true_with_bind:
  aliasCacheTrueWithBind(DoubledEager, true)
  aliasCacheTrueWithBind(DoubledLazy, false)

block test_alias_property_cache_true_force_dispatch_true:
  aliasCacheTrueForceDispatchTrue(PlainDoubledEager)
  aliasCacheTrueForceDispatchTrue(PlainDoubledLazy)

block test_inherit_property:
  # kivy/tests/test_properties.py::test_inherit_property. A callback gets
  # the value, not the instance (REDESIGN.md, Binding): the closure knows it.
  let event = Event2()
  event.initProps()
  var args: seq[(string, string)] = @[]
  discard event.bindA(proc (v: string) {.closure.} = args.add ("a", v))
  discard event.bindB(proc (v: string) {.closure.} = args.add ("b", v))
  assert event.a == "hello"
  assert event.b == "hello2"
  event.a = "bye"
  assert event.a == "bye"
  assert args == @[("a", "bye")]
  event.b = "goodbye"
  assert event.b == "goodbye"
  assert args == @[("a", "bye"), ("b", "goodbye")]

# ------------------------------------------------------------------ the other kinds

block bounds_varlist_always_dispatch:
  let k = Kinds()
  k.initProps()
  k.level = 10                       # in bounds (tests/bad/bad_bounds: outside)
  assert k.level == 10
  k.spacing = 3.0
  assert k.spacing == [3.0, 3.0]
  k.spacing = [1.0]
  assert k.spacing == [1.0, 1.0]
  k.spacing = [1.0, 2.0]
  assert k.spacing == [1.0, 2.0]
  var every = 0
  discard k.bindEvery(proc (v: int) {.closure.} = inc every)
  k.every = 0                        # unchanged, but `always`
  k.every = 0
  assert every == 2
  var level = 0
  discard k.bindLevel(proc (v: int) {.closure.} = inc level)
  k.dispatchLevel()                  # Kivy's `property('level').dispatch(k)`
  assert level == 1 and k.log == @["handler 10", "handler 10"]

block handler_and_eager_order:
  # Phase 1's initEventDispatcher order: the eager alias links first, then
  # the class's handler, so the handler runs after the alias trigger and
  # before any later observer; a lazy alias links when it is first bound.
  let k = Kinds()
  k.initProps()
  discard k.bindDoubled(proc (v: int) {.closure.} = k.log.add "doubled " & $v)
  discard k.bindLevel(proc (v: int) {.closure.} = k.log.add "observer " & $v)
  discard k.bindLazyDoubled(proc (v: int) {.closure.} = k.log.add "lazyDoubled " & $v)
  k.level = 2
  assert k.log == @["doubled 4", "handler 2", "observer 2", "lazyDoubled 4"]
  let s = KindsSub()
  s.initProps()
  s.level = 3                        # the subclass's handler method
  assert s.log == @["subclass handler 3"]

# ------------------------------------------------------------------ the properties trace

proc fmt3(v: float): string = formatFloat(v, ffDecimal, 3)

proc pair(v: (float, float)): string = "(" & fmt3(v[0]) & ", " & fmt3(v[1]) & ")"

proc quad(v: array[4, float]): string =
  "(" & fmt3(v[0]) & ", " & fmt3(v[1]) & ", " & fmt3(v[2]) & ", " & fmt3(v[3]) & ")"

block properties_trace:
  # The first 44 lines of tests/fixtures/traces/properties.txt, which Kivy
  # wrote: the order of the observers of x, y, pos, right, top, center,
  # width and size, with the links of the reference lists and the aliases,
  # and padding from 1, 2, 4 and 1 numbers. tests/traces.nim writes the
  # whole trace through the real Widget and BoxLayout.
  var log: seq[string] = @[]
  let w = TraceWidget()
  w.initProps()
  discard w.bindX(proc (v: float) {.closure.} = log.add "x " & fmt3(v))
  discard w.bindY(proc (v: float) {.closure.} = log.add "y " & fmt3(v))
  discard w.bindPos(proc (v: (float, float)) {.closure.} = log.add "pos " & pair(v))
  discard w.bindRight(proc (v: float) {.closure.} = log.add "right " & fmt3(v))
  discard w.bindTop(proc (v: float) {.closure.} = log.add "top " & fmt3(v))
  discard w.bindCenter(proc (v: (float, float)) {.closure.} = log.add "center " & pair(v))
  discard w.bindWidth(proc (v: float) {.closure.} = log.add "width " & fmt3(v))
  discard w.bindSize(proc (v: (float, float)) {.closure.} = log.add "size " & pair(v))
  log.add "# pos = (1, 2)"
  w.pos = (1.0, 2.0)
  log.add "# pos = (1, 2) again"
  w.pos = (1.0, 2.0)
  log.add "# x = 5"
  w.x = 5.0
  log.add "# size = (50, 60)"
  w.size = (50.0, 60.0)
  log.add "# right = 300"
  w.right = 300.0
  log.add "# center = (0, 0)"
  w.center = (0.0, 0.0)
  discard w.bindX(proc (v: float) {.closure.} = log.add "x second observer " & fmt3(v))
  log.add "# x = 6"
  w.x = 6.0
  let b = TraceBox()
  b.initProps()
  b.padding = 5.0
  log.add "padding 5 -> " & quad(b.padding)
  b.padding = [10.0, 20.0]
  log.add "padding (10, 20) -> " & quad(b.padding)
  b.padding = [1.0, 2.0, 3.0, 4.0]
  log.add "padding (1, 2, 3, 4) -> " & quad(b.padding)
  b.padding = [7.0]
  log.add "padding [7] -> " & quad(b.padding)
  var kivy: seq[string] = @[]
  try:
    kivy = readFile("tests/fixtures/traces/properties.txt").splitLines()
  except:
    quit "cannot read tests/fixtures/traces/properties.txt"
  assert log.len == 44
  for i in 0 ..< log.len:
    if log[i] != kivy[i]:
      quit "properties trace line " & $(i + 1) & ": " & log[i] & ", Kivy: " & kivy[i]
