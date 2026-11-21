A method with a `{.closure.}` proc-typed parameter gives invalid C: the vtable slot keeps a plain function-pointer parameter, the call passes a closure

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

Calling a `method` through dynamic dispatch, when one of its parameters is a `{.closure.}` proc type, fails in the C compiler: "incompatible type for argument 2". The vtable entry is cast to a function type whose parameter is a plain `void (*)(NI64)` function pointer, while the argument passed is the lowered closure (a function-and-environment tuple). The same program with `{.feature: "v2".}` fails the same way. A plain `proc` with the same parameter compiles, and so does the method when the parameter is `{.nimcall.}`. Nim 2.4.1 compiles and runs the program and prints 2. A method that takes a callback (here an input provider's `update(dispatchFn)`) cannot be written.

## Reproduction

Save the file in an empty directory and run the command below.

`method_closure_param.nim`:

```nim
import std/syncio

type
  Fn = proc (x: int) {.closure.}
  Base = ref object of RootObj
  Sub = ref object of Base

method run(b: Base; f: Fn) {.base.} =
  f(1)

method run(s: Sub; f: Fn) =
  f(2)

proc main() =
  var total = 0
  let f: Fn = proc (x: int) {.closure.} = total += x
  let b: Base = Sub()
  b.run(f)
  echo total

main()
```

```
nimony c --nimcache:nc -o:method_closure_param method_closure_param.nim
```

## Actual

```
nc/c/metlybkm6/metlybkm6.c: In function ‘main’:
nc/c/metlybkm6/metlybkm6.c:645:166: error: incompatible type for argument 2 of ‘(void (*)(X60Qt_0_IArefSX42aseX4fbj0metlybkm6_metlybkm6 *, void (*)(NI64)))bX60Qh_77->d_00.Q.vt_00->mt_0[1]’
  645 |           ((X60Qt_0_IArefSX42aseX4fbj0metlybkm6ZAiS64ZSEAnimcallZAfalseZAtrueSEAnimcallZAfalseZAR67_metlybkm6)(*(*bX60Qh_77).d_00.Q.vt_00).mt_0[IL64(1)])(bX60Qh_77, fX60Qh_74);
      |                                                                                                                                                                      ^~~~~~~~~
      |                                                                                                                                                                      |
      |                                                                                                                                                                      X60Qt_0_IAclosureX54upleAiS64ZArefSX52ootX4fbj0sysvq0aslZSEAnimcallZAfalseZAtrueArefSX52ootX4fbj0sysvq0asl_metlybkm6
nc/c/metlybkm6/metlybkm6.c:645:166: note: expected ‘X60Qt_0_IAiS64ZSEAnimcallZAfalseZAtrue_metlybkm6’ {aka ‘void (*)(long int)’} but argument is of type ‘X60Qt_0_IAclosureX54upleAiS64ZArefSX52ootX4fbj0sysvq0aslZSEAnimcallZAfalseZAtrueArefSX52ootX4fbj0sysvq0asl_metlybkm6’
nifmake: command failed (exit code 1): gcc -c -Wno-attributes -fwrapv -fno-math-errno -Wno-stringop-overflow -O1 -I. nc/c/metlybkm6/metlybkm6.c -o nc/c/metlybkm6/metlybkm6.o
FAILURE: <nimony>/bin/nifmake --base:. --rerun -j run --done:51,100 nc/c/metlybkm6.final.build.nif
```

## Expected

It compiles and prints `2`, as with Nim 2.4.1 (`nim c -r`).

Not checked: a fresh build of the tools older than the commit (`contracts`, `controlflow`, `hastur`, `jorogumo`); none of them is in this build's pipeline. The phase label is a guess: the closure lowering seems not to reach the method's vtable type.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/333
