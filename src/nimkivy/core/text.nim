## The core text label: Kivy's `kivy/core/text/__init__.py` (LabelBase).
##
## A label lays its text out with `text_layout`, sizes its texture, and
## renders each line through the text provider, `text/text_sdl3`, which
## subclasses `LabelBase` and implements the `getExtents`, `renderBegin`,
## `renderText` and `renderEnd` methods with SDL3_ttf. `register` gives a
## font name its regular, italic, bold and bold-italic files; `Roboto` is
## registered from nimkivy's copy of Kivy's fonts in the data directory
## (`resources`), on the first `register` or font lookup.
##
## Options are set on `options` after construction (`newLabelSDL3()` in the
## provider), and `refresh` renders. The texture is filled at once, where
## Kivy fills it when it is first drawn; Kivy's Label always refreshes after
## changing options, so the result is the same. Markup, shortening,
## outlines, underline, strikethrough, font contexts and text direction
## other than left to right are out (SCOPE.md). Right-to-left text would
## start in `findBaseDirection` and the provider's `shape`.

import std/[assertions, tables, math, opt, os, strutils, syncio]
from std/unicode import runeLen, runeOffset
import ../sdl3/sdl
import ../graphics/texture
import ../resources
import text/text_layout

export text_layout

const
  FontRegular = 0
  FontItalic = 1
  FontBold = 2

type
  LabelBase* = ref object of RootObj
    ## A text label rendered to a texture. core/text/__init__.py LabelBase
    options*: LabelOptions      ## the label's options
    text: string
    textSize: TextSize
    internalSize: (int, int)    # the laid out size, padding included
    cachedLines*: seq[LayoutLine] ## the lines of the last `render`
    size: (int, int)
    texture: nil Texture

  FontRegistry = ref object
    fonts: Table[string, array[4, string]]   # LabelBase._fonts
    fontsCache: Table[string, string]        # LabelBase._fonts_cache
    generation: int                          # bumped by every `register`
    defaults: bool                           # Roboto is registered

  Texture1px = ref object
    texture: nil Texture

let fontRegistry = FontRegistry(fonts: initTable[string, array[4, string]](),
  fontsCache: initTable[string, string](), generation: 0, defaults: false)
let texture1px = Texture1px(texture: nil)

proc logError(msg: string) =
  # Kivy raises here; nimkivy logs on stderr, in Kivy's Logger layout, and
  # goes on without the font (PORTING.md, Errors).
  stderr.writeLine "[ERROR  ] [Text        ] " & msg

# ---------------------------------------------------------------- fonts

proc registerDefaults()

proc register*(name: sink string; fnRegular: string; fnItalic = ""; fnBold = "";
    fnBoldItalic = "") =
  ## Registers a font name with the files of its styles, each searched with
  ## `resourceFind`. A missing style uses the regular file; it is not
  ## synthesised. A file that is not found leaves the name unregistered,
  ## with a log line. core/text/__init__.py LabelBase.register
  registerDefaults()   # first, so that a later `register` wins
  var fonts: array[4, string] = ["", "", "", ""]
  var i = 0
  for fontType in [fnRegular, fnItalic, fnBold, fnBoldItalic]:
    if fontType.len > 0:
      let font = resourceFind(fontType)
      if font.len == 0:
        logError "File " & fontType & " not found"
        return
      fonts[i] = font
    else:
      fonts[i] = fonts[0]   # the regular file again
    inc i
  fontRegistry.fonts[name] = fonts
  inc fontRegistry.generation

proc registerDefaults() =
  # kivy/core/text/__init__.py: get_system_fonts_dir adds the font
  # directories to the resource paths, then the default font is registered;
  # here on first use, so that `setDataDir` can come first. The files are
  # named in the data directory, not as `data/fonts/...` in the resource
  # paths, so a data directory of any name is found.
  if fontRegistry.defaults: return
  fontRegistry.defaults = true
  let fonts = dataDir() / "fonts"
  resourceAddPath(fonts)
  register("Roboto", fonts / "Roboto-Regular.ttf", fonts / "Roboto-Italic.ttf",
    fonts / "Roboto-Bold.ttf", fonts / "Roboto-BoldItalic.ttf")

proc fontsGeneration*(): int {.inline.} =
  ## A number that changes whenever a font name is (re)registered, so a
  ## provider can drop what it measured with the old files.
  fontRegistry.generation

proc resolveFontName*(l: LabelBase) =
  ## Sets `options.fontNameR` to the file of `options.fontName` with the
  ## bold and italic options: a registered name, a cached name, a path, or a
  ## name in data/fonts (with `.ttf` added). A name that is not found
  ## leaves it "" and logs. core/text/__init__.py LabelBase.resolve_font_name
  registerDefaults()
  let options = l.options
  var fontname = options.fontName
  if fontRegistry.fonts.hasKey(fontname):
    let italic = if options.italic: FontItalic else: FontRegular
    let bold = if options.bold: FontBold else: FontRegular
    options.fontNameR = fontRegistry.fonts.getOrDefault(fontname)[italic or bold]
  elif fontRegistry.fontsCache.hasKey(fontname):
    options.fontNameR = fontRegistry.fontsCache.getOrDefault(fontname)
  else:
    var filename = resourceFind(fontname)
    if filename.len == 0 and not fontname.endsWith(".ttf"):
      fontname = fontname & ".ttf"
      filename = resourceFind(fontname)
    if filename.len == 0:
      filename = dataDir() / fontname
      if not isFile(filename):
        logError "Label: File '" & fontname & "' not found"
        options.fontNameR = ""
        return
    fontRegistry.fontsCache[fontname] = filename
    options.fontNameR = filename

# ---------------------------------------------------------------- the label

proc initLabelBase*(l: LabelBase) =
  ## Sets up a new label with Kivy's default options and no text. Provider
  ## constructors create the object, then call it.
  ## core/text/__init__.py LabelBase.__init__
  l.options = newLabelOptions()
  l.text = ""
  l.textSize = (none[float](), none[float]())
  l.internalSize = (0, 0)
  l.cachedLines = @[]
  l.size = (0, 0)
  l.texture = nil
  l.resolveFontName()

method getExtents*(l: LabelBase; text: sink string): (int, int) {.base.} =
  ## The width and height of `text` in pixels.
  (0, 0)

method getAscent*(l: LabelBase): int {.base.} =
  ## Pixels from the baseline to the top of the font.
  0

method getDescent*(l: LabelBase): int {.base.} =
  ## Pixels from the baseline to the bottom of the font (negative).
  0

method renderBegin*(l: LabelBase) {.base.} =
  ## Starts rendering into a transparent image of the label's size.
  discard

method renderText*(l: LabelBase; text: string; x, y: int) {.base.} =
  ## Draws `text` with its top left corner at (x, y), y down.
  discard

method renderEnd*(l: LabelBase): nil ptr SDL_Surface {.base.} =
  ## Ends rendering, and gives the image, top row first.
  nil

proc getCachedExtents*(l: LabelBase): Extents =
  ## A function measuring text with the current font options.
  ## core/text/__init__.py LabelBase.get_cached_extents
  result = proc (text: string): (int, int) {.closure.} = l.getExtents(text)

proc text*(l: LabelBase): string {.inline.} =
  ## The text.
  l.text

proc `text=`*(l: LabelBase; text: sink string) {.inline.} =
  ## Sets the text; `refresh` renders it.
  l.text = text

proc textSize*(l: LabelBase): TextSize {.inline.} =
  ## The box the text is laid out in (Kivy's `text_size` and `usersize`).
  l.textSize

proc `textSize=`*(l: LabelBase; ts: TextSize) {.inline.} =
  ## Sets the box the text is laid out in.
  l.textSize = ts

proc texture*(l: LabelBase): nil Texture {.inline.} =
  ## The rendered text; nil before the first `refresh`.
  l.texture

proc size*(l: LabelBase): (int, int) {.inline.} =
  ## The texture size from the last `refresh`, padding included.
  l.size

proc width*(l: LabelBase): int {.inline.} =
  ## The texture width.
  l.size[0]

proc height*(l: LabelBase): int {.inline.} =
  ## The texture height.
  l.size[1]

proc contentWidth*(l: LabelBase): int =
  ## The texture width without padding (0 without texture).
  ## core/text/__init__.py LabelBase.content_width
  let t = l.texture
  if t == nil: 0
  else: t.width - int(l.options.padding[0] + l.options.padding[2])

proc contentHeight*(l: LabelBase): int =
  ## The texture height without padding (0 without texture).
  let t = l.texture
  if t == nil: 0
  else: t.height - int(l.options.padding[1] + l.options.padding[3])

proc contentSize*(l: LabelBase): (int, int) =
  ## The texture size without padding.
  (l.contentWidth, l.contentHeight)

proc fontid*(l: LabelBase): string =
  ## A key for the font options: size, file, bold and italic.
  ## core/text/__init__.py LabelBase.fontid
  let o = l.options
  result = $o.fontSize & "|" & o.fontNameR & "|" & $o.bold & "|" & $o.italic

proc findBaseDirection*(text: string): string =
  ## The base direction of `text`. Like Kivy's providers other than Pango,
  ## always "ltr"; right-to-left detection belongs here.
  ## core/text/__init__.py LabelBase.find_base_direction
  "ltr"

proc textureOf1px(): Texture =
  # core/text/__init__.py LabelBase.texture_1px: one transparent pixel.
  let t = texture1px.texture
  if t != nil:
    return t
  let s = SDL_CreateSurface(1, 1, SDL_PIXELFORMAT_RGBA32)
  assert s != nil, "cannot create a 1x1 surface"
  result = newTexture(s)
  texture1px.texture = result

proc blit(l: LabelBase; data: nil ptr SDL_Surface) =
  # `texture.blit_data(data)` when the data is wider than one pixel.
  let t = l.texture
  if data != nil:
    if t != nil and data.w > 1:
      t.blitData(data)
    else:
      SDL_DestroySurface(data)

proc clearTexture(l: LabelBase) =
  # core/text/__init__.py LabelBase.clear_texture
  l.renderBegin()
  l.blit(l.renderEnd())

proc defaultLineOptions(lines: seq[LayoutLine]): nil LabelOptions =
  # The options of the first word of the first line with words.
  result = nil
  for line in lines:
    if line.words.len > 0:
      return line.words[0].options

proc splitSpaces(line: string): seq[string] =
  # Kivy's re.split('( +)', line): the pieces between runs of spaces, and
  # the runs, alternately.
  result = @[]
  var start = 0
  var i = 0
  while i < line.len:
    if line[i] == ' ':
      result.add line.substr(start, i - 1)
      var j = i
      while j < line.len and line[j] == ' ':
        inc j
      result.add line.substr(i, j - 1)
      start = j
      i = j
    else:
      inc i
  result.add line.substr(start)

proc renderLines*(l: LabelBase; lines: seq[LayoutLine]; options: LabelOptions;
    y0: int; size: (int, int)): int =
  ## Renders each line at its alignment, from `y0` down, and returns the y
  ## after the last line. core/text/__init__.py LabelBase.render_lines
  let getExtents = l.getCachedExtents()
  let uw = options.textSize.w
  let paddingLeft = options.padding[0]
  let paddingRight = options.padding[2]
  var uww = 0.0
  if uw.isSome:
    uww = uw.get(0) - paddingLeft - paddingRight   # the width of the text alone
  let w = float(size[0])
  let sw = options.spaceWidth
  let halign = options.halign
  var y = y0
  var curBaseDir = ""
  for layoutLine in lines:   # for a plain label, each line has one word
    let lw = float(layoutLine.w)
    let lh = layoutLine.h
    var line = ""
    assert layoutLine.words.len < 2
    var lastWord: nil LayoutWord = nil
    if layoutLine.words.len > 0:
      lastWord = layoutLine.words[0]
      line = layoutLine.words[0].text
      if curBaseDir.len == 0:
        curBaseDir = findBaseDirection(line)
    var x = paddingLeft
    case halign
    of halignAuto:
      if curBaseDir == "rtl":
        x = float(max(0, int(w - lw - paddingRight)))
    of halignCenter:
      x = float(min(int(w - lw), max(int(paddingLeft),
        int((w - lw + paddingLeft - paddingRight) / 2.0))))
    of halignRight:
      x = float(max(0, int(w - lw - paddingRight)))
    else:
      discard
    if uw.isSome and halign == halignJustify and line.len > 0 and
        not layoutLine.isLastLine and lastWord != nil:
      # Spread the spaces so the line fills the width.
      let room = max(uww - lw, 0.0)
      let n = int(floor(room / float(sw)))
      let rem = room - float(n) * float(sw)
      var words: seq[string] = @[]
      if n != 0 or rem != 0:
        words = splitSpaces(line)
      if words.len > 1:
        for i in 0 ..< n:
          let idx = (2 * i + 1) mod (words.len - 1)
          words[idx] = words[idx] & " "
        if rem != 0:
          let ext = getExtents(words[^1])
          layoutLine.words.add newLayoutWord(lastWord.options, ext[0], ext[1], words[^1])
          lastWord.lw = int(uww - float(ext[0]))   # the word was stretched
          l.renderText(words[^1], int(x) + lastWord.lw, y)
          line = ""
          for p in words.toOpenArray(0, words.len - 3):
            line.add p
          lastWord.text = line
        else:
          lastWord.lw = int(uww)   # the word was stretched
          line = ""
          for p in words:
            line.add p
          lastWord.text = line
        layoutLine.w = int(uww)   # the line takes the full width
    if line.len > 0:
      layoutLine.x = int(x)
      layoutLine.y = y
      l.renderText(line, int(x), y)
    y += lh
  result = y

proc renderReal(l: LabelBase) =
  # core/text/__init__.py LabelBase._render_real
  let lines = l.cachedLines
  let options = defaultLineOptions(lines)
  if options == nil:   # there was no text to render
    l.clearTexture()
    return
  let ih = l.internalSize[1]   # the size of the text, not of the texture
  let height = float(l.size[1])
  let paddingTop = options.padding[1]
  var y = 0
  case options.valign
  of valignBottom: y = int(height - float(ih) + paddingTop)
  of valignTop: y = int(paddingTop)
  of valignMiddle, valignCenter: y = int((height - float(ih) + 2 * paddingTop) / 2)
  l.renderBegin()
  discard l.renderLines(lines, options, y, l.size)
  l.blit(l.renderEnd())

proc render*(l: LabelBase): (int, int) =
  ## Lays the text out and returns the texture size it needs, padding
  ## included. core/text/__init__.py LabelBase.render(real=False)
  let options = copy(l.options)
  options.spaceWidth = l.getExtents(" ")[0]
  let strip = options.strip or options.halign == halignJustify
  options.strip = strip
  options.textSize = l.textSize
  let (uw, uh) = l.textSize
  var text = l.text
  if strip:
    text = stripUnicodeSpace(text)
  l.cachedLines = @[]
  if text.len == 0:
    return (0, 0)
  var w = 0
  var h = 0
  var clipped = false
  let extents = l.getCachedExtents()
  if uh.isSome and options.valign in {valignMiddle, valignCenter}:
    var center = -1   # the position of a newline
    let chars = runeLen(text)
    if chars > 1:
      # Kivy counts characters: find the byte offset of the middle one.
      let middle = runeOffset(text, chars div 2)
      let left = if middle > 0: text.rfind('\n', 0, middle - 1) else: -1
      let right = if middle >= 0: text.find('\n', middle) else: -1
      if left != -1 and right != -1:
        # As in Kivy, compared with center = -1, not with the middle.
        center = if center - left <= right - center: left else: right
      elif left != -1:
        center = left
      elif right != -1:
        center = right
    if center != -1:
      (w, h, clipped) = layoutText(text.substr(center + 1), l.cachedLines, (0, 0),
        (uw, some(uh.get(0) / 2)), options, extents, true, true)
      (w, h, clipped) = layoutText(text.substr(0, center), l.cachedLines, (w, h),
        (uw, uh), options, extents, false, true)
    else:   # no newline: lay everything out
      (w, h, clipped) = layoutText(text, l.cachedLines, (0, 0), (uw, none[float]()),
        options, extents, true, true)
  else:   # top or bottom
    (w, h, clipped) = layoutText(text, l.cachedLines, (0, 0), (uw, uh), options,
      extents, options.valign == valignTop, true)
  l.internalSize = (w, h)
  var fw = float(w)
  var fh = float(h)
  if uw.isSome and uw.get(0) != 0:
    fw = uw.get(0)
  if uh.isSome and uh.get(0) != 0:
    fh = uh.get(0)
  if fh > 1 and fw < 2:
    fw = 2
  result = (int(fw), int(fh))

proc refresh*(l: LabelBase) =
  ## Renders the text into `texture`, which is a shared transparent pixel
  ## when the text is empty. core/text/__init__.py LabelBase.refresh
  l.resolveFontName()
  l.size = l.render()
  let (width, height) = l.size
  if width <= 1 or height <= 1:
    l.texture = textureOf1px()
    return
  let t = l.texture
  if t == nil or width != t.width or height != t.height:
    let s = SDL_CreateSurface(cint(width), cint(height), SDL_PIXELFORMAT_RGBA32)
    assert s != nil, "cannot create a surface for a label"
    let nt = newTexture(s)
    nt.flipVertical()
    l.texture = nt
  l.renderReal()
