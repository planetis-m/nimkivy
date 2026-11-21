# Ports kivy/tests/test_properties.py (the tests listed in ACCEPTANCE.md).
#
# Kivy attaches each property to one shared dispatcher, either with
# `set_name` + `link_eagerly` or with `link` + `link_deps`. Here each test
# declares its properties on a fresh class and instance, then links them
# both ways in turn (`setName`). The type-rejection halves are dropped: Nim's
# types make them compile errors.

import std/assertions
import nimkivy/properties

proc linkFor(p: Property; d: EventDispatcher; setName: bool) =
  # The two ways the Kivy tests attach a property.
  if setName:
    p.linkEagerly(d)
  else:
    discard p.link(d)
    p.linkDeps(d)

proc fresh(cls: DispatcherClass): EventDispatcher =
  result = EventDispatcher(cls: cls)
  result.initEventDispatcher()

proc nums(xs: openArray[float]): Value = toValue(xs)

for setName in [true, false]:
  block test_base:
    # kivy/tests/test_properties.py::test_base
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let a = newProperty(toValue(-1))
    cls.addProperty("a", a)
    let wid = fresh(cls)
    a.linkFor(wid, setName)
    assert a.get(wid) == toValue(-1)
    discard a.set(wid, toValue(0))
    assert a.get(wid) == toValue(0)
    discard a.set(wid, toValue(1))
    assert a.get(wid) == toValue(1)

  block test_observer:
    # kivy/tests/test_properties.py::test_observer
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let a = newProperty(toValue(-1))
    cls.addProperty("a", a)
    let wid = fresh(cls)
    a.linkFor(wid, setName)
    assert a.get(wid) == toValue(-1)
    var observeCalled = 0
    a.bind(wid, proc (d: EventDispatcher; v: Value) {.closure.} = observeCalled = 1)
    discard a.set(wid, toValue(0))
    assert a.get(wid) == toValue(0)
    assert observeCalled == 1
    observeCalled = 0
    discard a.set(wid, toValue(0))
    assert a.get(wid) == toValue(0)
    assert observeCalled == 0
    discard a.set(wid, toValue(1))
    assert a.get(wid) == toValue(1)
    assert observeCalled == 1

  block test_objectcheck:
    # kivy/tests/test_properties.py::test_objectcheck
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let a = newObjectProperty(toValue(false))
    cls.addProperty("a", a)
    let wid = fresh(cls)
    a.linkFor(wid, setName)
    assert a.get(wid) == toValue(false)
    discard a.set(wid, toValue(true))
    assert a.get(wid) == toValue(true)

  block test_stringcheck:
    # kivy/tests/test_properties.py::test_stringcheck (without the number)
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let a = newStringProperty()
    cls.addProperty("a", a)
    let wid = fresh(cls)
    a.linkFor(wid, setName)
    assert a.get(wid) == toValue("")
    discard a.set(wid, toValue("hello"))
    assert a.get(wid) == toValue("hello")

  block test_numericcheck:
    # kivy/tests/test_properties.py::test_numericcheck
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let a = newNumericProperty()
    cls.addProperty("a", a)
    let wid = fresh(cls)
    a.linkFor(wid, setName)
    assert a.get(wid) == toValue(0)
    discard a.set(wid, toValue(99))
    assert a.get(wid) == toValue(99)

  block test_listcheck:
    # kivy/tests/test_properties.py::test_listcheck
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let a = newListProperty()
    cls.addProperty("a", a)
    let wid = fresh(cls)
    a.linkFor(wid, setName)
    assert a.get(wid) == toValue(newSeq[Value]())
    discard a.set(wid, nums([1.0, 2, 3]))
    assert a.get(wid) == nums([1.0, 2, 3])

  block test_propertynone:
    # kivy/tests/test_properties.py::test_propertynone
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let a = newNumericProperty(0, allowNone = true)
    cls.addProperty("a", a)
    let wid = fresh(cls)
    a.linkFor(wid, setName)
    assert a.get(wid) == toValue(0)
    discard a.set(wid, noneValue())
    assert a.get(wid).isNone
    discard a.set(wid, toValue(1))
    assert a.get(wid) == toValue(1)

  block test_reference:
    # kivy/tests/test_properties.py::test_reference
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let x = newNumericProperty(0)
    let y = newNumericProperty(0)
    let pos = newReferenceListProperty(@[Property(x), y])
    cls.addProperty("x", x)
    cls.addProperty("y", y)
    cls.addProperty("pos", pos)
    let wid = fresh(cls)
    x.linkFor(wid, setName)
    y.linkFor(wid, setName)
    pos.linkFor(wid, setName)
    assert x.get(wid) == toValue(0)
    assert y.get(wid) == toValue(0)
    assert pos.get(wid) == nums([0.0, 0])
    discard x.set(wid, toValue(50))
    assert pos.get(wid) == nums([50.0, 0])
    discard y.set(wid, toValue(50))
    assert pos.get(wid) == nums([50.0, 50])
    discard pos.set(wid, nums([0.0, 0]))
    assert pos.get(wid) == nums([0.0, 0])
    assert x.get(wid) == toValue(0)
    assert y.get(wid) == toValue(0)
    var observeCalled = 0
    pos.bind(wid, proc (d: EventDispatcher; v: Value) {.closure.} = observeCalled = 1)
    assert observeCalled == 0
    discard x.set(wid, toValue(99))
    assert observeCalled == 1

  block test_color_property:
    # kivy/tests/test_properties.py::test_color_property: the list and tuple
    # forms. Colour names, hex strings and in-place item assignment are out
    # of scope, so the shared value is set as a whole.
    let cls = newDispatcherClass("_TestProperty", EventDispatcherClass)
    let color = newColorProperty()
    let color2 = newColorProperty()
    cls.addProperty("color", color)
    cls.addProperty("color2", color2)
    let wid = fresh(cls)
    color.linkFor(wid, setName)
    assert color.get(wid) == nums([1.0, 1, 1, 1])
    color2.linkFor(wid, setName)
    assert color2.get(wid) == nums([1.0, 1, 1, 1])
    discard color.set(wid, nums([1.0, 1, 0]))
    assert color.get(wid) == nums([1.0, 1, 0, 1])
    discard color.set(wid, nums([1.0, 1, 0, 0]))
    assert color.get(wid) == nums([1.0, 1, 0, 0])
    discard color.set(wid, nums([0.5, 1, 1, 1]))
    assert color.get(wid) == nums([0.5, 1, 1, 1])
    assert color2.get(wid) == nums([1.0, 1, 1, 1])
    discard color2.set(wid, color.get(wid))
    assert color2.get(wid) == nums([0.5, 1, 1, 1])

# ------------------------------------------------------------------ alias

type CustomAlias = ref object of EventDispatcher
  # The counters the Kivy test classes keep as plain attributes.
  getterCalled, setterCalled, callbackCalled: int
  baseValue: float

proc newCustomAlias(cls: DispatcherClass): CustomAlias =
  result = CustomAlias(cls: cls, getterCalled: 0, setterCalled: 0,
    callbackCalled: 0, baseValue: 1)
  result.initEventDispatcher()

proc countCallback(): PropertyCallback =
  # def callback(widget, value): widget.callback_called += 1
  result = proc (d: EventDispatcher; v: Value) {.closure.} = inc CustomAlias(d).callbackCalled

for watchBeforeUse in [true, false]:
  block test_alias_property_without_setter:
    # kivy/tests/test_properties.py::test_alias_property_without_setter
    # (the getter half; setting a read-only alias stops the program)
    let cls = newDispatcherClass("CustomAlias", EventDispatcherClass)
    let prop = cls.addAlias("prop",
      proc (d: EventDispatcher): Value =
        inc CustomAlias(d).getterCalled
        result = toValue(5),
      nil, watchBeforeUse = watchBeforeUse)
    let wid = newCustomAlias(cls)
    assert wid.getterCalled == 0
    assert prop.get(wid) == toValue(5)
    assert wid.getterCalled == 1

  block test_alias_property:
    # kivy/tests/test_properties.py::test_alias_property
    let cls = newDispatcherClass("CustomAlias", EventDispatcherClass)
    let prop = cls.addAlias("prop",
      proc (d: EventDispatcher): Value =
        inc CustomAlias(d).getterCalled
        result = noneValue(),
      proc (d: EventDispatcher; v: Value): bool =
        inc CustomAlias(d).setterCalled
        result = false,
      watchBeforeUse = watchBeforeUse)
    let wid = newCustomAlias(cls)
    wid.bind("prop", countCallback())
    assert wid.getterCalled == 0 and wid.setterCalled == 0 and wid.callbackCalled == 0
    discard prop.set(wid, toValue(1))
    assert wid.getterCalled == 0 and wid.setterCalled == 1 and wid.callbackCalled == 0
    discard prop.set(wid, toValue(1))
    assert wid.getterCalled == 0 and wid.setterCalled == 2 and wid.callbackCalled == 0
    assert prop.get(wid).isNone
    assert wid.getterCalled == 1 and wid.setterCalled == 2 and wid.callbackCalled == 0

  block test_alias_property_cache_true:
    # kivy/tests/test_properties.py::test_alias_property_cache_true
    let cls = newDispatcherClass("CustomAlias", EventDispatcherClass)
    let prop = cls.addAlias("prop",
      proc (d: EventDispatcher): Value =
        inc CustomAlias(d).getterCalled
        result = toValue(5),
      proc (d: EventDispatcher; v: Value): bool =
        inc CustomAlias(d).setterCalled
        result = true,
      cache = true, watchBeforeUse = watchBeforeUse)
    let wid = newCustomAlias(cls)
    assert wid.getterCalled == 0 and wid.setterCalled == 0
    assert prop.get(wid) == toValue(5)
    assert wid.getterCalled == 1 and wid.setterCalled == 0
    assert prop.get(wid) == toValue(5)
    assert wid.getterCalled == 1 and wid.setterCalled == 0
    discard prop.set(wid, toValue(10))
    assert prop.get(wid) == toValue(5)
    assert wid.setterCalled == 1 and wid.getterCalled == 2

  block test_alias_property_with_bind:
    # kivy/tests/test_properties.py::test_alias_property_with_bind
    let cls = newDispatcherClass("CustomAlias", EventDispatcherClass)
    let x = cls.addNumeric("x", 0)
    let width = cls.addNumeric("width", 100)
    let right = cls.addAlias("right",
      proc (d: EventDispatcher): Value =
        toValue(d.getProperty("x").num + d.getProperty("width").num),
      proc (d: EventDispatcher; v: Value): bool =
        d.setProperty("x", toValue(v.num - d.getProperty("width").num))
        result = false,
      @["x", "width"], watchBeforeUse = watchBeforeUse)
    let wid = newCustomAlias(cls)
    assert right.get(wid) == toValue(100)
    x.setNumber(wid, 500)
    assert right.get(wid) == toValue(600)
    width.setNumber(wid, 50)
    assert right.get(wid) == toValue(550)
    discard right.set(wid, toValue(100))
    assert width.getNumber(wid) == 50
    assert x.getNumber(wid) == 50
    wid.bind("right", countCallback())
    x.setNumber(wid, 100)
    assert wid.callbackCalled == 1
    x.setNumber(wid, 100)
    assert wid.callbackCalled == 1
    width.setNumber(wid, 900)
    assert wid.callbackCalled == 2
    discard right.set(wid, toValue(700))
    assert wid.callbackCalled == 3
    discard right.set(wid, toValue(700))
    assert wid.callbackCalled == 3

  block test_alias_property_with_force_dispatch_true:
    # kivy/tests/test_properties.py::test_alias_property_with_force_dispatch_true
    let cls = newDispatcherClass("CustomAlias", EventDispatcherClass)
    let prop = cls.addAlias("prop",
      proc (d: EventDispatcher): Value =
        inc CustomAlias(d).getterCalled
        result = noneValue(),
      proc (d: EventDispatcher; v: Value): bool =
        inc CustomAlias(d).setterCalled
        result = false,
      forceDispatch = true, watchBeforeUse = watchBeforeUse)
    let wid = newCustomAlias(cls)
    wid.bind("prop", countCallback())
    assert wid.getterCalled == 0 and wid.setterCalled == 0 and wid.callbackCalled == 0
    discard prop.set(wid, toValue(1))
    assert wid.getterCalled == 1 and wid.setterCalled == 1 and wid.callbackCalled == 1
    discard prop.set(wid, toValue(1))
    assert wid.getterCalled == 2 and wid.setterCalled == 2 and wid.callbackCalled == 2

  block test_alias_property_cache_true_with_bind:
    # kivy/tests/test_properties.py::test_alias_property_cache_true_with_bind
    let cls = newDispatcherClass("CustomAlias", EventDispatcherClass)
    let baseValue = cls.addNumeric("base_value", 1)
    let prop = cls.addAlias("prop",
      proc (d: EventDispatcher): Value =
        inc CustomAlias(d).getterCalled
        result = toValue(d.getProperty("base_value").num * 2),
      proc (d: EventDispatcher; v: Value): bool =
        d.setProperty("base_value", toValue(v.num / 2))
        result = false,
      @["base_value"], cache = true, watchBeforeUse = watchBeforeUse)
    let wid = newCustomAlias(cls)
    assert wid.getterCalled == 0
    assert baseValue.getNumber(wid) == 1
    assert wid.getterCalled == 0
    baseValue.setNumber(wid, 4)
    assert wid.getterCalled == ord(watchBeforeUse)
    assert prop.get(wid) == toValue(8)
    assert wid.getterCalled == 1
    discard prop.set(wid, toValue(4))
    assert wid.getterCalled == 2
    assert baseValue.getNumber(wid) == 2
    assert prop.get(wid) == toValue(4)
    assert wid.getterCalled == 2

  block test_alias_property_cache_true_force_dispatch_true:
    # kivy/tests/test_properties.py::test_alias_property_cache_true_force_dispatch_true
    let cls = newDispatcherClass("CustomAlias", EventDispatcherClass)
    let prop = cls.addAlias("prop",
      proc (d: EventDispatcher): Value =
        let w = CustomAlias(d)
        inc w.getterCalled
        result = toValue(w.baseValue * 2),
      proc (d: EventDispatcher; v: Value): bool =
        let w = CustomAlias(d)
        inc w.setterCalled
        w.baseValue = v.num / 2
        result = true,
      cache = true, forceDispatch = true, watchBeforeUse = watchBeforeUse)
    let wid = newCustomAlias(cls)
    wid.bind("prop", countCallback())
    assert wid.baseValue == 1
    assert wid.getterCalled == 0 and wid.setterCalled == 0 and wid.callbackCalled == 0
    discard prop.set(wid, toValue(16))
    assert wid.baseValue == 8
    assert wid.getterCalled == 1 and wid.setterCalled == 1 and wid.callbackCalled == 1
    discard prop.set(wid, toValue(16))
    assert wid.baseValue == 8
    assert wid.getterCalled == 2 and wid.setterCalled == 2 and wid.callbackCalled == 2
    assert prop.get(wid) == toValue(16)
    assert wid.getterCalled == 2 and wid.setterCalled == 2 and wid.callbackCalled == 2

block test_inherit_property:
  # kivy/tests/test_properties.py::test_inherit_property
  let eventClass = newDispatcherClass("Event", EventDispatcherClass)
  discard eventClass.addString("a", "hello")
  let event2Class = newDispatcherClass("Event2", eventClass)
  discard event2Class.addString("b", "hello2")
  let event = fresh(event2Class)
  var argsObj: nil EventDispatcher = nil
  var argsVal = noneValue()
  let callback = proc (d: EventDispatcher; v: Value) {.closure.} =
    argsObj = d
    argsVal = v
  discard event.fbind("a", callback)
  discard event.fbind("b", callback)
  assert event.getProperty("a") == toValue("hello")
  assert event.getProperty("b") == toValue("hello2")
  event.setProperty("a", toValue("bye"))
  assert event.getProperty("a") == toValue("bye")
  assert argsObj == event and argsVal == toValue("bye")
  event.setProperty("b", toValue("goodbye"))
  assert event.getProperty("b") == toValue("goodbye")
  assert argsObj == event and argsVal == toValue("goodbye")
