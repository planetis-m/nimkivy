An override declared outside its class's module is silently not used (base method runs); a direct call fails in shoggoth: "method not found in class"

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/345 (labels: miscompile, phase:sem, found:llm-agents)

Nimony 0.6.3, commit `88d04ab0` (current master), Linux amd64, C backend (`nimony c`).

A method that overrides a `{.base.}` method, declared in a module other than the one that declares its class, is silently not used: a call through the base type runs the base method. A direct call on the subclass fails in shoggoth with "method not found in class". The base method is in its class's module, so this is not the case 5d71fd57 forbids; that commit says "overrides in other modules keep working". The same declarations in one module dispatch to the override.

## Reproduction

Save the three files in an empty directory and run the commands below.

`shapes.nim` (the classes and the base method):

```nim
type
  Shape* = ref object of RootObj
  Circle* = ref object of Shape

method name*(s: Shape): string {.base.} = "shape"
```

`app.nim` (the override in another module, called through the base type):

```nim
import std/syncio
import shapes

method name(c: Circle): string = "circle"

echo Shape(Circle()).name()
```

`app2.nim` (the same, also called directly):

```nim
import std/syncio
import shapes

method name(c: Circle): string = "circle"

echo Circle().name()
echo Shape(Circle()).name()
```

```
nimony c -r --nimcache:nc app.nim
nimony c -r --nimcache:nc2 app2.nim
```

## Actual

`app.nim` compiles and prints the base method's result:

```
shape
```

`app2.nim` fails in shoggoth:

```
[Error] method `name.0.appvqqro6` not found in class Circle.Obj.0.shakc8bms
nifmake: command failed (exit code 1): <nimony>/bin/shoggoth c --bits:64 --cpu:le --os:Linux --stdcache:<stdcache> --flags:br --isMain --app:console --outdir:nc2/c/appvqqro6 nc2/appvqqro6.s.nif
```

## Expected

Both print `circle` (and `app2.nim` prints it twice), as they do when the override is in `shapes.nim`. If an override must be declared in the module of the class it overrides for (only that module emits the class's vtable), then a positioned compile error at the override, as 5d71fd57 gives for a base method, instead of a silently ignored override and a shoggoth failure.

## Notes

- 5d71fd57's message: "Only the module that declares a class emits its vtable ... overrides in other modules keep working." Here the class `Circle` is declared in `shapes.nim` and its override in `app.nim`, so `Circle`'s vtable (emitted by `shapes.nim`) has no slot for it.
- Related: #175 (closed: a base method outside its class's module, now an error).
