# Tests nimkivy/resources' data directory: the
# directory given to `setDataDir` before the first use is where the default
# font is found, even when it is not named `data`; it is fixed from then on.
# (The other choices, `data` beside the executable and under the current
# directory, are what every other test runs with: bin/ has no `data`.)

import std/[assertions, files, dirs, paths, strutils, tempfiles]
import nimkivy/resources
import nimkivy/core/text
import nimkivy/core/text/text_sdl3

proc copyFonts(): string {.raises.} =
  # A data directory named `kivydata` in a temporary directory, with
  # nimkivy's Roboto files.
  let dir = createTempDir("nimkivy_data", "") / path("kivydata")
  createDir(dir / path("fonts"))
  for style in ["Regular", "Italic", "Bold", "BoldItalic"]:
    let name = "Roboto-" & style & ".ttf"
    copyFile(path("data/fonts/" & name), dir / path("fonts") / path(name))
  result = $dir

proc main() =
  var dir = ""
  try:
    dir = copyFonts()
  except:
    assert false, "cannot copy the fonts to a temporary directory"
  setDataDir(dir)
  # The first label fixes it and registers Roboto from it.
  let l = newLabelSDL3()
  l.refresh()
  assert dataDir() == dir
  assert l.options.fontNameR == dir & "/fonts/Roboto-Regular.ttf"
  let (w, h) = l.getExtents("")
  assert w == 0 and h > 0
  l.options.bold = true
  l.resolveFontName()
  assert l.options.fontNameR == dir & "/fonts/Roboto-Bold.ttf"
  # A name in its fonts directory is found too.
  l.options.fontName = "Roboto-Italic"
  l.resolveFontName()
  assert l.options.fontNameR.startsWith(dir) and
    l.options.fontNameR.endsWith("Roboto-Italic.ttf")
  try:
    removeDir(path(dir).parentDir)
  except:
    discard

main()
