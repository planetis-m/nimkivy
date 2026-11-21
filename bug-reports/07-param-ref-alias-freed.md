A location reached through a `ref`, passed to an immutable object parameter, is passed by reference: a write through the `ref` inside the call frees what the parameter reads

Nimony 0.6.3, commit `95afaa04` (current master), Linux amd64, C backend (`nimony c`).

`observe(h, h.v)` passes the field `h.v` (an object with a `seq`) to the immutable parameter `v`. The compiler passes it by reference, as the manual allows ("the compiler is always free to pass arguments by reference"), but `observe` can also reach the same location through the `ref` `h`. Assigning `h.v` inside the call frees the `seq` buffer that `v.items` still points to, so the loop reads freed memory and prints `0 202 302` instead of `1 2 3`. The program is accepted without a diagnostic, and the same happens with `{.feature: "v2".}`. The borrow checker already rejects the loop form of this hazard ("Iterating through a `ref`" in `doc/language.md`: "cannot iterate over a location reached through a `ref`"). But a parameter bound to such a location gets no check, and no copy.

In real code, an event dispatcher calls `observers.dispatch(d, storage.value)` with `storage` a `ref`, and an observer that refreshes `storage.value` corrupts the value the later observers receive.

Nim 2.4.1 behaves the same way (`nim c -d:useMalloc` under valgrind: "Invalid read of size 8 ... inside a block of size 32 free'd"), so this is inherited, not new.

## Reproduction

Save the file in an empty directory and run the command below.

`alias.nim`:

```nim
import std/syncio

type
  Big = object
    items: seq[int]
    a, b, c: int
  Holder = ref object
    v: Big

proc observe(h: Holder; v: Big) =
  for x in v.items:
    # replaces the location `v` was passed from: its buffer is freed
    h.v = Big(items: @[100 + x, 200 + x, 300 + x], a: 0, b: 0, c: 0)
    echo x

let h = Holder(v: Big(items: @[1, 2, 3], a: 1, b: 2, c: 3))
observe(h, h.v)
```

```
nimony c --nimcache:nc -o:alias alias.nim && ./alias
```

## Actual

```
0
202
302
```

## Expected

`1`, `2`, `3`: the value `h.v` had when it was passed. Either the argument is copied when the callee could reach the same location through a `ref`, or the call is rejected like the loop over a `ref` location.

Not checked: a fresh build of the tools older than the commit (`contracts`, `controlflow`, `hastur`, `jorogumo`). The phase label is a guess: the prover is the place that rejects the loop form.

Filed: https://github.com/planetis-m/nimony-bugs-llms/issues/334
