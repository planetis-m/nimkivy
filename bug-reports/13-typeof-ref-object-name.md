typetraits `$typeof(x)` of a `ref object` value prints `ref Node.Obj`, where `$Node` prints `Node`

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

For a type declared as `Node = ref object`, `$Node` prints the type's name, `Node`, as Nim 2 does. `$typeof(n)` with `n: Node` prints the internal form `ref Node.Obj` instead. For an `object` type both print the name. `{.feature: "v2".}` changes nothing.

## Reproduction

Save the file in an empty directory and run the command shown under Actual.

`refname.nim`:

```nim
import std/[syncio, typetraits]

type
  Node = ref object
  Plain = object

let n = Node()
let p = Plain()
echo $Node
echo $typeof(n)
echo $Plain
echo $typeof(p)
```

## Actual

```
$ nimony c -r --nimcache:nc refname.nim
Node
ref Node.Obj
Plain
Plain
```

## Expected

```
Node
Node
Plain
Plain
```

`typeof(n)` is `Node`, so `$typeof(n)` should be `$Node`, as in Nim 2.

## Notes

- Found when naming an object after its static type in a template (`$typeof(app)`, Kivy's `App.name` is its class name): the same happens through an `{.untyped.}` template argument.
- Related: #312 and #308 (other wrong `$` results of typetraits).

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/340
