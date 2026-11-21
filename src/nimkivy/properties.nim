## The property kinds: Kivy's `kivy/properties.pyx`.
##
## Each kind is a `Property` subclass (the base is in `event`) that overrides
## how a value is converted, checked, stored, read and dispatched. A class
## declares its properties once with `DispatcherClass.addProperty`, usually
## through the `addNumeric`, `addString`, ... helpers below, which return the
## property for the typed accessors:
##
## .. code-block:: nim
##   let WidgetClass = newDispatcherClass("Widget", EventDispatcherClass)
##   let widgetX = WidgetClass.addNumeric("x", 0)
##   proc x*(w: Widget): float = widgetX.get(w).num
##   proc `x=`*(w: Widget; v: float) = discard widgetX.set(w, toValue(v))
##
## A value a property rejects (Kivy's ValueError) stops the program with
## Kivy's message: in nimkivy it can only come from a programming error.
##
## Out of scope (SCOPE.md): DictProperty, BoundedNumericProperty,
## ConfigParserProperty, in-place mutation of list values, `rebind`, values
## with units (`'15sp'`) and colour strings.

import std/syncio
import event

export event

type
  NumericProperty* = ref object of Property
    ## A number (`int` or `float`), or None with `allowNone`.
  StringProperty* = ref object of Property
    ## A string.
  BooleanProperty* = ref object of Property
    ## A boolean. Like Kivy, it does not check the type.
  ObjectProperty* = ref object of Property
    ## Any value; objects compare by identity.
  ListProperty* = ref object of Property
    ## A list, copied when set.
  OptionProperty* = ref object of Property
    ## A string from `options`. The typed accessors map it to a Nim enum.
    options*: seq[string]
  ColorProperty* = ref object of Property
    ## Four numbers; a list of three gets alpha 1.
  VariableListProperty* = ref object of Property
    ## A list of `length` (2 or 4) numbers, expanded from 1, 2 or 4 values.
    length*: int
  ReferenceListProperty* = ref object of Property
    ## A list made of other properties (`pos` of `x` and `y`).
    references*: seq[Property]
  AliasGetter* = proc (d: EventDispatcher): Value {.nimcall.}
    ## Computes an alias property's value.
  AliasSetter* = proc (d: EventDispatcher; value: Value): bool {.nimcall.}
    ## Applies a value to an alias property; true dispatches it.
  AliasProperty* = ref object of Property
    ## A value computed by `getter` and applied by `setter` (nil: read-only),
    ## dispatched when one of the `bindNames` properties changes.
    getter*: AliasGetter
    setter*: nil AliasSetter
    bindNames*: seq[string]
    useCache*: bool
    watchBeforeUse*: bool

let EventDispatcherClass* = newDispatcherClass("EventDispatcher")
  ## The class of a plain `EventDispatcher`, the base of every other class.

# ------------------------------------------------------------------ simple kinds

proc newNumericProperty*(default = 0.0; allowNone = false): NumericProperty =
  ## A NumericProperty with a number as default.
  NumericProperty(name: "", index: 0, defaultValue: toValue(default),
    allowNone: allowNone, forceDispatch: false, comparator: nil)

proc newNumericPropertyNone*(): NumericProperty =
  ## A NumericProperty that defaults to None (and allows it).
  NumericProperty(name: "", index: 0, defaultValue: noneValue(),
    allowNone: true, forceDispatch: false, comparator: nil)

method check*(p: NumericProperty; d: EventDispatcher; x: Value): string =
  if x.kind == vkNone:
    result = procCall check(Property(p), d, x)
  elif x.kind != vkNumber:
    result = d.cls.name & "." & p.name & " accept only int/float (got " & $x & ")"
  else:
    result = ""

proc newStringProperty*(default = ""; allowNone = false): StringProperty =
  ## A StringProperty.
  StringProperty(name: "", index: 0, defaultValue: toValue(default),
    allowNone: allowNone, forceDispatch: false, comparator: nil)

method check*(p: StringProperty; d: EventDispatcher; x: Value): string =
  if x.kind == vkNone:
    result = procCall check(Property(p), d, x)
  elif x.kind != vkString:
    result = d.cls.name & "." & p.name & " accept only str"
  else:
    result = ""

proc newBooleanProperty*(default = true; allowNone = false): BooleanProperty =
  ## A BooleanProperty.
  BooleanProperty(name: "", index: 0, defaultValue: toValue(default),
    allowNone: allowNone, forceDispatch: false, comparator: nil)

proc newObjectProperty*(default = noneValue(); allowNone = false;
    comparator: nil Comparator = nil): ObjectProperty =
  ## An ObjectProperty. A `comparator` replaces the identity comparison.
  ObjectProperty(name: "", index: 0, defaultValue: default,
    allowNone: allowNone, forceDispatch: false, comparator: comparator)

proc newProperty*(default: Value; allowNone = false; forceDispatch = false): Property =
  ## Kivy's plain `Property(default)`: any value, no conversion.
  Property(name: "", index: 0, defaultValue: default, allowNone: allowNone,
    forceDispatch: forceDispatch, comparator: nil)

proc newListProperty*(default: seq[Value] = @[]; allowNone = false): ListProperty =
  ## A ListProperty.
  ListProperty(name: "", index: 0, defaultValue: toValue(default),
    allowNone: allowNone, forceDispatch: false, comparator: nil)

method check*(p: ListProperty; d: EventDispatcher; x: Value): string =
  if x.kind == vkNone:
    result = procCall check(Property(p), d, x)
  elif x.kind != vkList:
    result = d.cls.name & "." & p.name & " accept only ObservableList"
  else:
    result = ""

proc newOptionProperty*(default: string; options: seq[string];
    allowNone = false): OptionProperty =
  ## An OptionProperty: `default` must be one of `options`.
  OptionProperty(name: "", index: 0, defaultValue: toValue(default),
    allowNone: allowNone, forceDispatch: false, comparator: nil, options: options)

method check*(p: OptionProperty; d: EventDispatcher; x: Value): string =
  if x.kind == vkNone:
    result = procCall check(Property(p), d, x)
  elif x.kind != vkString or x.str notin p.options:
    result = d.cls.name & "." & p.name & " is set to an invalid option " & $x
  else:
    result = ""

proc newColorProperty*(default = @[1.0, 1.0, 1.0, 1.0]; allowNone = false): ColorProperty =
  ## A ColorProperty, white by default.
  ColorProperty(name: "", index: 0, defaultValue: toValue(default),
    allowNone: allowNone, forceDispatch: false, comparator: nil)

method convert*(p: ColorProperty; d: EventDispatcher; x: Value): Value =
  # properties.pyx ColorProperty.convert and parse_list
  if x.kind == vkNone:
    result = x
  elif x.kind == vkList and x.items.len == 4:
    result = x
  elif x.kind == vkList and x.items.len == 3:
    result = x
    result.items.add toValue(1.0)
  else:
    quit "ValueError: " & d.cls.name & "." & p.name & " has an invalid format (got " &
      $x & ")"

proc newVariableListProperty*(default: seq[float] = @[]; length = 4;
    allowNone = false): VariableListProperty =
  ## A VariableListProperty of `length` 2 or 4; the default is zeros.
  if length != 2 and length != 4:
    quit "VariableListProperty requires a length of 2 or 4 (got " & $length & ")"
  var dv = default
  if dv.len == 0:
    for i in 0 ..< length: dv.add 0.0
  result = VariableListProperty(name: "", index: 0, defaultValue: toValue(dv),
    allowNone: allowNone, forceDispatch: false, comparator: nil, length: length)

method convert*(p: VariableListProperty; d: EventDispatcher; x: Value): Value =
  ## One number gives `length` copies, two give `[a, b, a, b]` (or `[a, b]`),
  ## four are kept. properties.pyx VariableListProperty.convert
  var items: seq[Value] = @[]
  if x.kind == vkNone:
    return x
  elif x.kind == vkNumber:
    items = @[x]
  elif x.kind == vkList:
    items = x.items
  let bad = d.cls.name & "." & p.name & " has an invalid format (got " & $x & ")"
  for item in items:
    if item.kind != vkNumber: quit "ValueError: " & bad
  if items.len == 1:
    result = if p.length == 4: toValue(@[items[0], items[0], items[0], items[0]])
             else: toValue(@[items[0], items[0]])
  elif items.len == 2:
    result = if p.length == 4: toValue(@[items[0], items[1], items[0], items[1]])
             else: toValue(@[items[0], items[1]])
  elif items.len == 4 and p.length == 4:
    result = toValue(items)
  else:
    quit "ValueError: " & bad

# ------------------------------------------------------------------ ReferenceList

proc newReferenceListProperty*(references: seq[Property]): ReferenceListProperty =
  ## A list of the values of `references`; setting it sets each of them.
  ## Like Kivy, the default value is the list of the properties themselves,
  ## so the first `set` always dispatches, even to the current values.
  var dv: seq[Value] = @[]
  for r in references: dv.add toValue(RootRef(r))
  result = ReferenceListProperty(name: "", index: 0, defaultValue: toValue(dv),
    allowNone: false, forceDispatch: false, comparator: nil, references: references)

method initStorage*(p: ReferenceListProperty; d: EventDispatcher; s: PropertyStorage) =
  procCall initStorage(Property(p), d, s)
  s.stopEvent = false

proc referenceCallback(p: ReferenceListProperty): PropertyCallback =
  # The bound method `self.trigger_change` that Kivy binds to each reference.
  result = proc (d: EventDispatcher; value: Value) {.closure.} = p.triggerChange(d, value)

method linkDeps*(p: ReferenceListProperty; d: EventDispatcher) =
  ## Binds `triggerChange` to every referenced property, which links them.
  for i in 0 ..< p.references.len:
    discard p.references[i].fbind(d, referenceCallback(p))

proc refreshed(p: ReferenceListProperty; d: EventDispatcher): Value =
  # The current values of the references.
  var items: seq[Value] = @[]
  for i in 0 ..< p.references.len:
    items.add p.references[i].get(d)
  result = toValue(items)

method triggerChange*(p: ReferenceListProperty; d: EventDispatcher; value: Value) =
  ## A reference changed: refresh and dispatch, unless this property is
  ## being set (then it dispatches once at the end).
  let s = p.getPropertyStorage(d)
  if not s.stopEvent:
    s.value = p.refreshed(d)
    p.doDispatch(d, s)

method check*(p: ReferenceListProperty; d: EventDispatcher; x: Value): string =
  if x.kind != vkList or x.items.len != p.references.len:
    result = d.cls.name & "." & p.name & " value length is immutable"
  else:
    result = ""

method set*(p: ReferenceListProperty; d: EventDispatcher; x: Value): bool =
  ## Sets each reference in order (each dispatches its own observers), then
  ## dispatches this property once. properties.pyx ReferenceListProperty.set
  let s = p.getPropertyStorage(d)
  if x.kind != vkList:
    quit "ValueError: " & d.cls.name & "." & p.name & " must be a list or a tuple type"
  if not p.forceDispatch and p.compareValue(s.value, x):
    return false
  p.checkOrQuit(d, x)
  s.stopEvent = true
  for i in 0 ..< p.references.len:
    discard p.references[i].set(d, x.items[i])
  s.stopEvent = false
  s.value = x
  p.doDispatch(d, s)
  result = true

method get*(p: ReferenceListProperty; d: EventDispatcher): Value =
  let s = p.getPropertyStorage(d)
  s.value = p.refreshed(d)
  result = s.value

# ------------------------------------------------------------------ Alias

proc newAliasProperty*(getter: AliasGetter; setter: nil AliasSetter;
    bindNames: seq[string] = @[]; cache = false; watchBeforeUse = true;
    forceDispatch = false): AliasProperty =
  ## An AliasProperty. A nil `setter` makes it read-only.
  AliasProperty(name: "", index: 0, defaultValue: noneValue(), allowNone: false,
    forceDispatch: forceDispatch, comparator: nil, getter: getter, setter: setter,
    bindNames: bindNames, useCache: cache, watchBeforeUse: watchBeforeUse)

method initStorage*(p: AliasProperty; d: EventDispatcher; s: PropertyStorage) =
  procCall initStorage(Property(p), d, s)
  s.aliasInitial = true

method linkEagerly*(p: AliasProperty; d: EventDispatcher) =
  ## With `watchBeforeUse` (the default) and dependencies, the alias links
  ## when the instance is created; otherwise on first use.
  if p.watchBeforeUse and p.bindNames.len > 0:
    discard p.getPropertyStorage(d)

proc aliasCallback(p: AliasProperty): PropertyCallback =
  result = proc (d: EventDispatcher; value: Value) {.closure.} = p.triggerChange(d, value)

method linkDeps*(p: AliasProperty; d: EventDispatcher) =
  ## Binds `triggerChange` to each property named in `bindNames`.
  for i in 0 ..< p.bindNames.len:
    let name = p.bindNames[i]
    let dep = d.cls.findProperty(name)
    if dep == nil: quit "AttributeError: " & d.cls.name & " has no property " & name
    else: discard dep.fbind(d, aliasCallback(p))

method get*(p: AliasProperty; d: EventDispatcher): Value =
  ## The getter's value, or the cached one with `cache`.
  let s = p.getPropertyStorage(d)
  if p.useCache:
    if s.aliasInitial:
      s.aliasInitial = false
      s.value = p.getter(d)
    result = s.value
  else:
    result = p.getter(d)

method doDispatch*(p: AliasProperty; d: EventDispatcher; s: PropertyStorage) =
  s.observers.dispatchValue(d, p.get(d))

method triggerChange*(p: AliasProperty; d: EventDispatcher; value: Value) =
  ## A dependency changed: dispatch if the getter's value differs from the
  ## stored one (which, without `cache`, stays None).
  let s = p.getPropertyStorage(d)
  let dvalue = p.getter(d)
  if s.value != dvalue:
    if p.useCache:
      s.aliasInitial = false
      s.value = dvalue
    p.doDispatch(d, s)

method set*(p: AliasProperty; d: EventDispatcher; x: Value): bool =
  ## Calls the setter; dispatches when it returns true or with
  ## `forceDispatch`. Setting a read-only alias stops the program.
  let s = p.getPropertyStorage(d)
  let setter = p.setter
  if setter == nil:
    quit "AttributeError: \"" & d.cls.name & "." & p.name & "\" property is readonly"
  elif setter(d, x):
    if p.useCache:
      s.aliasInitial = false
      s.value = p.getter(d)
    p.doDispatch(d, s)
  elif p.forceDispatch:
    p.doDispatch(d, s)
  result = true

# ------------------------------------------------------------------ declaring

proc addNumeric*(cls: DispatcherClass; name: string; default = 0.0;
    allowNone = false): NumericProperty =
  ## Declares a NumericProperty and returns it.
  result = newNumericProperty(default, allowNone)
  cls.addProperty(name, result)

proc addNumericNone*(cls: DispatcherClass; name: string): NumericProperty =
  ## Declares a NumericProperty that defaults to None.
  result = newNumericPropertyNone()
  cls.addProperty(name, result)

proc addString*(cls: DispatcherClass; name: string; default = ""): StringProperty =
  ## Declares a StringProperty and returns it.
  result = newStringProperty(default)
  cls.addProperty(name, result)

proc addBoolean*(cls: DispatcherClass; name: string; default = true): BooleanProperty =
  ## Declares a BooleanProperty and returns it.
  result = newBooleanProperty(default)
  cls.addProperty(name, result)

proc addObject*(cls: DispatcherClass; name: string; default = noneValue();
    allowNone = false; comparator: nil Comparator = nil): ObjectProperty =
  ## Declares an ObjectProperty and returns it.
  result = newObjectProperty(default, allowNone, comparator)
  cls.addProperty(name, result)

proc addList*(cls: DispatcherClass; name: string; default: seq[Value] = @[]): ListProperty =
  ## Declares a ListProperty and returns it.
  result = newListProperty(default)
  cls.addProperty(name, result)

proc addOption*(cls: DispatcherClass; name, default: string;
    options: seq[string]): OptionProperty =
  ## Declares an OptionProperty and returns it.
  result = newOptionProperty(default, options)
  cls.addProperty(name, result)

proc addColor*(cls: DispatcherClass; name: string;
    default = @[1.0, 1.0, 1.0, 1.0]): ColorProperty =
  ## Declares a ColorProperty and returns it.
  result = newColorProperty(default)
  cls.addProperty(name, result)

proc addVariableList*(cls: DispatcherClass; name: string; default: seq[float] = @[];
    length = 4): VariableListProperty =
  ## Declares a VariableListProperty and returns it.
  result = newVariableListProperty(default, length)
  cls.addProperty(name, result)

proc addReferenceList*(cls: DispatcherClass; name: string;
    references: seq[Property]): ReferenceListProperty =
  ## Declares a ReferenceListProperty of already declared properties.
  result = newReferenceListProperty(references)
  cls.addProperty(name, result)

proc addAlias*(cls: DispatcherClass; name: string; getter: AliasGetter;
    setter: nil AliasSetter; bindNames: seq[string] = @[]; cache = false;
    watchBeforeUse = true; forceDispatch = false): AliasProperty =
  ## Declares an AliasProperty and returns it.
  result = newAliasProperty(getter, setter, bindNames, cache, watchBeforeUse,
    forceDispatch)
  cls.addProperty(name, result)

# ------------------------------------------------------------------ typed access

proc getNumber*(p: Property; d: EventDispatcher): float =
  ## The value as a number (0 for None).
  let v = p.get(d)
  result = if v.kind == vkNumber: v.num else: 0.0

proc setNumber*(p: Property; d: EventDispatcher; x: float) =
  ## Sets a number.
  discard p.set(d, toValue(x))

proc getString*(p: Property; d: EventDispatcher): string =
  ## The value as a string ("" for None).
  let v = p.get(d)
  result = if v.kind == vkString: v.str else: ""

proc getBool*(p: Property; d: EventDispatcher): bool =
  ## The value as a boolean (false for None).
  let v = p.get(d)
  result = v.kind == vkBool and v.flag

proc getFloats*(p: Property; d: EventDispatcher): seq[float] =
  ## The value as a list of numbers.
  result = p.get(d).toFloats

proc setFloats*(p: Property; d: EventDispatcher; xs: openArray[float]) =
  ## Sets a list of numbers.
  discard p.set(d, toValue(xs))

proc getOption*(p: OptionProperty; d: EventDispatcher): int =
  ## The index of the value in `options`, for a Nim enum in the same order.
  result = p.options.find(p.get(d).str)

proc setOption*(p: OptionProperty; d: EventDispatcher; i: int) =
  ## Sets `options[i]`.
  discard p.set(d, toValue(p.options[i]))
