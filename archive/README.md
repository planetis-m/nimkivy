# archive: how the test fixtures were made

Nothing here is run by the build or the tests. These are the Python scripts
that produced nimkivy's test fixtures during phase 1, kept as their
provenance. nimkivy builds and tests without Python (REDESIGN.md, Standalone).

Also kept here, as finished: `ROADMAP.md` (phases 1 and 2, both complete)
and `notes/` (the phase-2 brief and the handoff notes of layers 6-10 and
phase 2's steps). The paths they name are from the nimkivy root.

## The scripts (`reference/`)

They ran the real Kivy 2.3.2, installed in the kiosk's virtual environment
(`philosykos-website/kiosk/.venv`, the same sources as `upstream/kivy`), from
the nimkivy root, between 2026-11-21 and 2026-11-22 (git history of
`reference/out/`; `modal_default` was made again in layer 9):

| Script | Wrote (then, under `reference/`) | Now |
|---|---|---|
| `make_assets.py` | `assets/`: the test images and `tone.wav`, made with Pillow (the fonts beside them were copied, SIL OFL) | `tests/assets/` |
| `scenes.py` | `out/<scene>.png` and `out/<scene>.txt` | `tests/fixtures/scenes/` |
| `traces.py` | `out/traces/<name>.txt` | `tests/fixtures/traces/` |
| `graphics_points.py` | `out/graphics_points.txt` | `tests/fixtures/graphics_points.txt` |
| `smooth.py` (P2.12) | `tests/fixtures/smooth_points.txt` and `scenes/graphics_smooth.*`, already in Nim's format | the same |
| `compare.py` | (compared nimkivy's output with `out/`) | `tests/compare.nim` |

`smooth.py` ran on 2026-11-22 in a throwaway Python 3.12 environment
outside the repository (`~/.cache/kivy232-venv`, since deleted; `uv pip install
kivy==2.3.2`; its docstring has the commands), on the same machine and
display; that environment re-rendered graphics_basic and graphics_basic_msaa
byte for byte as the committed fixtures before it was used.

The commands were
`<kiosk>/.venv/bin/python reference/<script>.py`. Their paths are the old
ones (`reference/out/`); running them again would need the paths changed and
the conversion below applied to what they write.

`compare.py` was replaced by `tests/compare.nim` (the same rules: geometry and
traces exact except `known-geometry-diffs.txt`, pixels within 24 per channel
and each scene's budget, a diff image over budget). Before `compare.py` moved
here, both were run once on the same outputs, on 2026-11-22: they gave the same
ok/FAIL for every scene and trace, the same count of differing pixels for all
18 scenes, and the same failures and diff image on a deliberately broken copy.

## The conversion (`convert-fixtures.sh`)

Kivy's outputs were written with Python's formatting. They were converted
once, by `convert-fixtures.sh` (sed), when they moved to `tests/fixtures/`:

- Kivy's snake_case names in the traces as Nim's camelCase
  (`on_touch_down` -> `onTouchDown`, `is_open` -> `isOpen`,
  `texture_size=` -> `textureSize=` in the scene geometry, `rounded_rectangle`
  -> `roundedRectangle` in `graphics_points.txt`). Case and step names
  (`rect_fraction`, `insert_minus_1`) are labels, not names, and stay.
- `True`/`False` -> `true`/`false`; a handler's `None` return -> `false`
  (a bool in Nim); `grab_current None` -> `grabCurrent nil` (a missing
  object); `None` in a number pair or value -> `none` (an empty `Opt`);
  `Line.close` `1.0`/`0.0` -> `true`/`false`.
- Python's lists and dicts as Nim literals: `['a', 'b']` -> `@["a", "b"]`,
  `pos_hint {}` -> `posHint @[]`; the label trace's `{'text': 'Hello',
  'font_size': 40}` -> `text = "Hello", fontSize = 40`, enum values by their
  Nim names (`valignMiddle`, `halignJustify`).
- `.035` -> `0.035`; `open(animation=False)` -> `open(animation = false)`.

Numbers did not change: 3 decimals where the scripts printed 3, elsewhere
Python's repr, the shortest text that reads back as the same float.
