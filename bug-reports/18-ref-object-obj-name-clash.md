`Foo = ref object` beside a type named `FooObj` used as `ref FooObj`: both refs get one C struct, "incompatible types" / "has no member named"

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/347 (labels: rejects-valid, phase:c-codegen, found:llm-agents)

Nimony 0.6.3, commit `88d04ab0`, Linux amd64, C backend (`nimony c`). Master (`9fa64ee4`, one commit ahead, a C++ `const` change) not checked.

A program that declares `Foo = ref object` and also uses `ref FooObj` for an unrelated object type `FooObj` fails in the C compiler: both ref types are emitted as the same C struct, the one of `Foo`'s anonymous object, so constructing or reading a `ref FooObj` is invalid C. Renaming `FooObj` (control below) builds and runs. `{.feature: "v2".}` changes nothing.

## Reproduction

Save the files in an empty directory and run the commands shown under Actual.

`objname.nim`:

```nim
import std/syncio

type
  Foo = ref object   # the object type is anonymous
    x: int
  FooObj = object    # an unrelated type named FooObj
    y: int
  Bar = ref FooObj

let a = Foo(x: 1)
let b = Bar(y: 2)
echo a.x, " ", b.y
```

`control.nim` (the same with `FooObj` renamed to `FooData`):

```nim
import std/syncio

type
  Foo = ref object
    x: int
  FooData = object
    y: int
  Bar = ref FooData

let a = Foo(x: 1)
let b = Bar(y: 2)
echo a.x, " ", b.y
```

## Actual

```
$ nimony c -r --nimcache:nc_objname objname.nim
nc_objname/c/objjv1jj61/objjv1jj61.c: In function ‘main’:
nc_objname/c/objjv1jj61/objjv1jj61.c:539:34: error: incompatible types when initializing type ‘long int’ using type ‘FooObj_0_objjv1jj61’
  539 |         .r_00 = IL64(0), .d_00 = (FooObj_0_objjv1jj61){
      |                                  ^
nc_objname/c/objjv1jj61/objjv1jj61.c:547:68: error: ‘Foo_Obj_0_objjv1jj61’ has no member named ‘y_0’; did you mean ‘x_0’?
  547 |       write_2_syn1lfpjv(stdout_0_syn1lfpjv, (*b_0_objjv1jj61).d_00.y_0);
      |                                                                    ^~~
      |                                                                    x_0
nifmake: command failed (exit code 1): gcc -c -Wno-attributes -fwrapv -fno-math-errno -Wno-stringop-overflow -O1 -I. nc_objname/c/objjv1jj61/objjv1jj61.c -o nc_objname/c/objjv1jj61/objjv1jj61.o
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 nc_objname/c/objjv1jj61.final.build.nif
```

```
$ nimony c -r --nimcache:nc_control control.nim
1 2
```

## Expected

`1 2`, as for `control.nim`. `FooObj` is an ordinary user name (Nim's usual `Node = ref NodeObj` convention), and `Foo`'s anonymous object is not visible to the program.

## Cause

Unverified: the generated C has one struct for both refs, `X60Qt_0_IArefSX46ooX4fbj0objjv1jj61` (the key of `ref Foo.Obj.0.<module>`), whose payload is `Foo_Obj_0_...`; `ref FooObj.0.<module>` gets the same key. `src/lib/treemangler.nim`, `addSymbolBody`, splits a symbol at `.` and writes the parts without a separator, so `Foo.Obj.0.m` and `FooObj.0.m` mangle alike (`FooObj0m`), and the type cache keyed by `typekeys.mangle` (`c.newTypes`, `genericTypeName`) hands out the first ref type for the second. The anonymous object's name `Foo.Obj` comes from `semdecls.buildInnerObjDecl`.

## Notes

Found while writing a test of `{.acyclic.}` with one `ref object` type and one `object` + `ref` type, named `Acy` and `AcyObj`/`AcyRef`.
