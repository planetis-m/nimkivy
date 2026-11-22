# Compares nimkivy's scene and trace output with the fixtures Kivy 2.3.2
# produced (tests/fixtures; archive/README.md says how they were made).
#
#   bin/compare tests/out [scene ...]          geometry and pixels of scenes
#   bin/compare tests/out --traces [trace ...]
#   bin/compare tests/out --pixels scene ...   pixels only
#   bin/compare --fixtures <dir> tests/out ... other fixtures than tests/fixtures
#
# A scene's geometry (<scene>.txt) and every trace must equal the fixture
# line for line, except the lines listed in known-geometry-diffs.txt. Its
# picture (<scene>.png) may differ in at most the scene's budget of pixels by
# more than Tolerance in any channel: rasterization, glyph and JPEG
# differences (PORTING.md, Gaps). Over budget, <out>/diff/<scene>.png shows
# the differing pixels in red. With no names, every fixture scene is checked
# and then every trace. Exit status 1 if anything fails.

import std/[algorithm, cmdline, dirs, formatfloat, paths, strutils, syncio]
import nimkivy/sdl3/[sdl, image]

const
  Tolerance = 24  # per channel, 0..255

type KnownDiff = (string, string, string)  # (scene, fixture line, nimkivy line)

proc budget(scene: string): float =
  # The share of pixels that may differ.
  if scene.startsWith("label") or scene.startsWith("modal"): 0.03
  elif scene.endsWith("_msaa"): 0.03
  elif scene == "graphics_texture" or scene == "image_misc": 0.01  # JPEG
  else: 0.005

proc percent(share: float): string =
  formatFloat(share * 100, ffDecimal, 2) & "%"

proc readText(file: string; text: var string): bool =
  try:
    text = readFile(file)
    result = true
  except:
    result = false

proc textLines(text: string): seq[string] =
  # One entry per line; the final newline ends the last line.
  result = @[]
  if text.len > 0:
    for line in splitLines(text):
      result.add line
    if text.endsWith("\n"): result.setLen(result.len - 1)

proc knownDiffs(fixtures: string): seq[KnownDiff] =
  # Format: `scene | fixture line | nimkivy line`; `#` starts a comment.
  result = @[]
  var text = ""
  if not readText(fixtures & "/known-geometry-diffs.txt", text):
    quit "cannot read " & fixtures & "/known-geometry-diffs.txt"
  for line in textLines(text):
    if not line.isEmptyOrWhitespace and not line.startsWith("#"):
      var parts: seq[string] = @[]
      for part in line.split(" | "):
        parts.add part.strip()
      if parts.len != 3:
        quit "known-geometry-diffs.txt: not `scene | fixture | nimkivy`: " & line
      result.add (parts[0], parts[1], parts[2])

proc compareText(name, fixture, got: string; known: seq[KnownDiff]): string =
  # "" when `got` equals `fixture` line for line, else what differs.
  var a, b = ""
  if not readText(fixture, a): return "missing " & fixture
  if not readText(got, b): return "missing " & got
  let want = textLines(a)
  let have = textLines(b)
  for i in 0 ..< min(want.len, have.len):
    if want[i] != have[i] and (name, want[i], have[i]) notin known:
      return "line " & $(i + 1) & ": fixture \"" & want[i] & "\" / nimkivy \"" &
        have[i] & "\""
  if want.len != have.len:
    return $want.len & " lines in the fixture, " & $have.len & " in nimkivy"
  result = ""

proc loadRgb(file: string): nil ptr SDL_Surface =
  # The picture as 3 bytes per pixel, R, G, B (alpha dropped), or nil.
  var f = file
  let s = IMG_Load(f.toCString)
  if s == nil: return nil
  result = SDL_ConvertSurface(s, SDL_PIXELFORMAT_RGB24)
  SDL_DestroySurface(s)

proc differs(a, b: ptr UncheckedArray[uint8]; i, j: int): bool =
  # Whether a pixel differs by more than Tolerance in any channel.
  result = false
  for c in 0 ..< 3:
    if abs(int(a[i + c]) - int(b[j + c])) > Tolerance: return true

proc comparePng(scene, fixture, got, diffDir: string): string =
  # "" when the picture is within the scene's budget, else what differs.
  let a = loadRgb(fixture)
  if a == nil: return "cannot read " & fixture & ": " & fromCString(SDL_GetError())
  let b = loadRgb(got)
  if b == nil:
    SDL_DestroySurface(a)
    return "missing " & got & ": " & fromCString(SDL_GetError())
  if a.w != b.w or a.h != b.h:
    result = "size (" & $a.w & ", " & $a.h & ") / (" & $b.w & ", " & $b.h & ")"
  else:
    let pa = cast[ptr UncheckedArray[uint8]](a.pixels)
    let pb = cast[ptr UncheckedArray[uint8]](b.pixels)
    var bad = 0
    for y in 0 ..< int(a.h):
      for x in 0 ..< int(a.w):
        if differs(pa, pb, y * int(a.pitch) + 3 * x, y * int(b.pitch) + 3 * x): inc bad
    let share = float(bad) / float(int(a.w) * int(a.h))
    if share <= budget(scene):
      result = ""
    else:
      # The fixture, faded, with the differing pixels in red.
      for y in 0 ..< int(a.h):
        for x in 0 ..< int(a.w):
          let i = y * int(a.pitch) + 3 * x
          if differs(pa, pb, i, y * int(b.pitch) + 3 * x):
            pa[i] = 255
            pa[i + 1] = 0
            pa[i + 2] = 0
          else:
            for c in 0 ..< 3:
              pa[i + c] = uint8(int(pa[i + c]) div 3 + 170)
      var file = diffDir & "/" & scene & ".png"
      try:
        createDir(path(diffDir))
      except:
        discard  # IMG_SavePNG reports it
      if not IMG_SavePNG(a, file.toCString):
        echo "cannot write ", file, ": ", fromCString(SDL_GetError())
      result = percent(share) & " pixels differ (budget " & percent(budget(scene)) & ")"
  SDL_DestroySurface(a)
  SDL_DestroySurface(b)

proc report(name, err: string): bool =
  # Prints one check's result; true if it passed.
  if err.len == 0:
    echo "ok   ", name
    result = true
  else:
    echo "FAIL ", name, ": ", err
    result = false

proc fixtureNames(dir, ext: string): seq[string] =
  # The names of the files in `dir` that end with `ext`, sorted.
  result = @[]
  try:
    for e in walkDir(path(dir), relative = true):
      let f = $e.path
      if f.endsWith(ext): result.add f.substr(0, f.len - ext.len - 1)
  except:
    quit "cannot list " & dir
  result.sort()

proc compareTraces(fixtures, outDir: string; names: seq[string];
    known: seq[KnownDiff]): bool =
  # Compares the named traces (all of them when none are named).
  result = true
  var all = names
  if all.len == 0: all = fixtureNames(fixtures & "/traces", ".txt")
  for n in all:
    let err = compareText(n, fixtures & "/traces/" & n & ".txt",
      outDir & "/traces/" & n & ".txt", known)
    if not report("trace " & n, err): result = false

proc main() =
  var args: seq[string] = @[]
  for i in 1 .. paramCount():
    args.add paramStr(i)
  var fixtures = "tests/fixtures"
  if args.len >= 2 and args[0] == "--fixtures":
    fixtures = args[1]
    args.delete(0)
    args.delete(0)
  if args.len == 0:
    quit "usage: compare [--fixtures <dir>] <out> [--traces | --pixels] [name ...]"
  let outDir = args[0]
  let known = knownDiffs(fixtures)
  var ok = true
  if args.len >= 2 and args[1] == "--traces":
    ok = compareTraces(fixtures, outDir, args[2 .. ^1], known)
  else:
    let pixelsOnly = args.len >= 2 and args[1] == "--pixels"
    var scenes = args[(if pixelsOnly: 2 else: 1) .. ^1]
    if scenes.len == 0: scenes = fixtureNames(fixtures & "/scenes", ".png")
    for scene in scenes:
      let want = fixtures & "/scenes/" & scene
      let got = outDir & "/" & scene
      if not pixelsOnly:
        if not report(scene & " geometry",
            compareText(scene, want & ".txt", got & ".txt", known)): ok = false
      if not report(scene & " pixels",
          comparePng(scene, want & ".png", got & ".png", outDir & "/diff")): ok = false
    if args.len == 1:
      if not compareTraces(fixtures, outDir, @[], known): ok = false
  if not ok: quit 1

main()
