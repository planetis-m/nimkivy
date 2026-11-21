# Tests core/text, core/text/text_layout and core/text/text_sdl3: Kivy's
# test_fonts, then the layout and rendering on SDL3_ttf. The `label` trace in
# tests/traces.nim compares texture sizes with Kivy's.

import std/[assertions, files, dirs, paths, strutils, tempfiles]
import nimkivy/sdl3/sdl
import nimkivy/graphics/texture
import nimkivy/core/text
import nimkivy/core/text/text_sdl3

proc pixel(s: ptr SDL_Surface; x, y: int): array[4, uint8] =
  # The bytes of pixel (x, y) of an RGBA32 surface.
  let row = cast[ptr UncheckedArray[uint8]](s.pixels)
  let i = y * int(s.pitch) + x * 4
  result = [row[i], row[i + 1], row[i + 2], row[i + 3]]

# kivy/tests/test_fonts.py::FontTestCase::test_unicode_name
# Adapted: DejaVuSans.ttf is copied to a temporary file named कीवी.ttf (no zip).
proc unicodeName() {.raises.} =
  let dir = createTempDir("kivy_test_fonts", "")
  let fontName = dir / path("कीवी.ttf")
  copyFile(path("data/fonts/DejaVuSans.ttf"), fontName)
  let lbl = newLabelSDL3()
  lbl.options.fontName = $fontName
  lbl.refresh()
  assert lbl.options.fontNameR == $fontName
  let (w, h) = lbl.getExtents("")
  assert w == 0 and h > 0
  removeDir(dir)

block test_unicode_name:
  try:
    unicodeName()
  except:
    assert false, "cannot copy the font to a temporary directory"

block default_font:
  # Roboto is registered: regular, bold, italic and bold-italic files.
  let l = newLabelSDL3()
  l.refresh()
  assert l.options.fontNameR.endsWith("data/fonts/Roboto-Regular.ttf")
  l.options.bold = true
  l.options.italic = true
  l.resolveFontName()
  assert l.options.fontNameR.endsWith("data/fonts/Roboto-BoldItalic.ttf")

block register_missing_style:
  # A style without a file falls back to the regular file.
  register("Deja", "data/fonts/DejaVuSans.ttf", fnBold = "data/fonts/Roboto-Bold.ttf")
  let l = newLabelSDL3()
  l.options.fontName = "Deja"
  l.options.italic = true
  l.resolveFontName()
  assert l.options.fontNameR.endsWith("data/fonts/DejaVuSans.ttf")
  l.options.bold = true
  l.options.italic = false
  l.resolveFontName()
  assert l.options.fontNameR.endsWith("data/fonts/Roboto-Bold.ttf")

block font_by_name:
  # A name that is not registered is searched in data/fonts, with .ttf added.
  let l = newLabelSDL3()
  l.options.fontName = "DejaVuSans"
  l.resolveFontName()
  assert l.options.fontNameR.endsWith("data/fonts/DejaVuSans.ttf")

block missing_font:
  # A missing font logs and measures nothing, without crashing.
  let l = newLabelSDL3()
  l.options.fontName = "no-such-font"
  l.text = "Hello"
  l.refresh()
  assert l.options.fontNameR == ""
  assert l.getExtents("Hello") == (0, 0)

block empty_text:
  # No text: the shared 1x1 texture.
  let l = newLabelSDL3()
  l.refresh()
  let t = l.texture
  assert t != nil and t.size == (1, 1)

block layout_wrap:
  # text_layout.pyx: wrapping at spaces, and a long word split over lines.
  let l = newLabelSDL3()
  l.options.fontSize = 15
  l.text = "Hello world"
  l.textSize = (some(50.0), none[float]())
  assert l.render() == (50, 36)
  assert l.cachedLines.len == 2
  assert l.cachedLines[0].words[0].text == "Hello"
  assert l.cachedLines[1].words[0].text == "world"
  assert l.cachedLines[1].lineWrap
  l.text = "averyveryverylongword"
  l.textSize = (some(40.0), none[float]())
  discard l.render()
  var joined = ""
  let lines = l.cachedLines
  for line in lines:
    assert line.w <= 40
    joined.add line.words[0].text
  assert joined == "averyveryverylongword"

block layout_non_ascii_split:
  # A long Greek word is split between characters, never inside one.
  let l = newLabelSDL3()
  l.options.fontSize = 15
  l.text = "Ελληνικάγράμματα"
  l.textSize = (some(30.0), none[float]())
  discard l.render()
  assert l.cachedLines.len > 1
  var joined = ""
  let lines = l.cachedLines
  for line in lines:
    joined.add line.words[0].text
  assert joined == "Ελληνικάγράμματα"

block render_pixels:
  # The texture holds the text in the label's colour; the first row of the
  # image is the top, so the texture is flipped.
  let l = newLabelSDL3()
  l.options.fontSize = 20
  l.options.color = [1.0, 0, 0, 1]
  l.text = "Hi"
  l.refresh()
  let t = l.texture
  assert t != nil
  assert t.size == l.size
  assert t.uvsize == (1.0, -1.0)
  # Render again into a surface to look at the pixels.
  l.renderBegin()
  discard l.renderLines(l.cachedLines, l.options, 0, l.size)
  let s = l.renderEnd()
  assert s != nil
  var red = 0
  for y in 0 ..< int(s.h):
    for x in 0 ..< int(s.w):
      let p = pixel(s, x, y)
      if p[3] > 128:
        assert p[0] == 255 and p[1] == 0 and p[2] == 0
        inc red
  assert red > 20
  SDL_DestroySurface(s)

block texture_reused:
  # The same size reuses the texture (Kivy's ask_update); another size
  # makes a new one.
  let l = newLabelSDL3()
  l.text = "ab"
  l.refresh()
  let t1 = l.texture
  l.text = "ba"
  l.refresh()
  assert l.texture == t1
  l.text = "a much longer text"
  l.refresh()
  assert l.texture != t1

block halign_center:
  # render_lines: a centred line in a wider box.
  let l = newLabelSDL3()
  l.options.halign = halignCenter
  l.text = "Hi"
  l.textSize = (some(100.0), none[float]())
  l.refresh()
  let line = l.cachedLines[0]
  assert line.x == (100 - line.w) div 2
