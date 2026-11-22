## The SDL3_ttf text provider: Kivy's `kivy/core/text/text_sdl2.py` and
## `_text_sdl2.pyx`, on SDL3_ttf.
##
## `LabelSDL3` is the core label that the widgets use. Fonts are opened at
## `int(fontSize)` points and cached by size, file, bold and italic, at most
## 64 at a time, the oldest closed first. A word is measured with
## `TTF_GetStringSize`, remembered per open font (`getExtents`), and
## rendered blended (or solid) in the label's colour, then copied into the
## label's RGBA image at its position.

import std/[tables, syncio]
import ../../sdl3/[sdl, ttf]
import ../text

type
  TtfContainerObj = object
    font: nil TTF_Font

  TtfContainer = ref TtfContainerObj
    # An open font, closed when the cache drops it. _text_sdl2.pyx _TTFContainer

  FontState = (TTF_HintingFlags, bool, TTF_Direction, TTF_FontStyleFlags, int)
    # What a measurement depends on besides the file, the size and the text:
    # the font's hinting, kerning, direction and style, and `fontsGeneration`.

  OpenFont = ref object
    # An open font and the sizes of the texts measured with it.
    ttf: TtfContainer
    words: Table[string, (int, int)]   # text -> (w, h), measured in `state`
    state: FontState

  FontCache = ref object
    fonts: Table[string, nil OpenFont]       # sdl2_cache
    order: seq[string]                   # sdl2_cache_order

  LabelSDL3* = ref object of LabelBase
    ## A core label rendered with SDL3_ttf. text_sdl2.py LabelSDL2
    surface: nil ptr SDL_Surface         # the image being rendered

proc `=wasMoved`(c: var TtfContainerObj) =
  c.font = nil

proc `=destroy`(c: TtfContainerObj) =
  let f = c.font
  if f != nil:
    TTF_CloseFont(f)

let fontCache = FontCache(fonts: initTable[string, nil OpenFont](), order: @[])

const
  MaxOpenFonts = 64
  MaxWords = 4096   # texts remembered per open font; the table is emptied when full

proc newLabelSDL3*(): LabelSDL3 =
  ## A label with Kivy's default options and no text.
  result = LabelSDL3(options: newLabelOptions(), surface: nil)
  result.initLabelBase()

proc stateOf(font: TTF_Font): FontState =
  (TTF_GetFontHinting(font), TTF_GetFontKerning(font), TTF_GetFontDirection(font),
    TTF_GetFontStyle(font), fontsGeneration())

proc getOpenFont(l: LabelBase): nil OpenFont =
  # _text_sdl2.pyx _get_font: the label's font from the cache, or opened.
  let fontid = l.fontid
  let cached = fontCache.fonts.getOrDefault(fontid)
  if cached != nil:
    return cached
  if TTF_WasInit() == 0:
    discard TTF_Init()
  var fontname = l.options.fontNameR
  if fontname.len == 0:
    return nil   # not found: resolveFontName logged it
  var font: nil TTF_Font = nil
  # Only a file name with an extension is opened.
  if fontname.find('.') >= 0:
    font = TTF_OpenFont(fontname.toCString, cfloat(int(l.options.fontSize)))
  if font == nil:
    # Kivy raises ValueError here.
    stderr.writeLine "[ERROR  ] [Text        ] " & fromCString(SDL_GetError()) & ": for font " &
      fontname
    return nil
  # Underline and strikethrough are out (SCOPE.md).
  TTF_SetFontStyle(font, TTF_STYLE_NORMAL)
  let opened = OpenFont(ttf: TtfContainer(font: font),
    words: initTable[string, (int, int)](), state: stateOf(font))
  fontCache.fonts[fontid] = opened
  fontCache.order.add fontid
  # Not too many open files: at most 64 fonts.
  while fontCache.order.len > MaxOpenFonts:
    let popid = fontCache.order[0]
    fontCache.order.delete(0)
    fontCache.fonts.del(popid)
  result = opened

proc getFont(l: LabelBase): nil TTF_Font =
  let f = getOpenFont(l)
  result = nil
  if f != nil:
    result = f.ttf.font

method getExtents*(l: LabelSDL3; text: sink string): (int, int) =
  ## The width and height of `text`. _text_sdl2.pyx _get_extents
  # GAP: widths and glyph pixels can differ by a pixel from Kivy's (hinting,
  # kerning, shaping), which can move a line break, because SDL3_ttf 3.2
  # replaces the SDL2_ttf bundled with Kivy 2.3.2.
  #
  # A measurement is a pure function of the open font (file, size, bold,
  # italic: the cache key), its state (`FontState`) and the text, so each
  # open font remembers its texts' sizes; they are forgotten when the state
  # changes (`renderText` sets the hinting, kerning and direction), when a
  # font is registered, and all at once when `MaxWords` are remembered.
  let f = getOpenFont(l)
  if f == nil:
    return (0, 0)
  let font = f.ttf.font
  if font == nil:
    return (0, 0)
  let state = stateOf(font)
  if state != f.state:
    f.words.clear()
    f.state = state
  result = f.words.getOrDefault(text, (-1, -1))
  if result[0] >= 0:
    return result
  var w = 0.cint
  var h = 0.cint
  var t = text
  discard TTF_GetStringSize(font, t.toCString, csize_t(t.len), addr w, addr h)
  result = (int(w), int(h))
  if f.words.len >= MaxWords:
    f.words.clear()
  f.words[text] = result

method getAscent*(l: LabelSDL3): int =
  ## The font's ascent in pixels. _text_sdl2.pyx _get_fontascent
  let font = getFont(l)
  if font == nil: 0 else: int(TTF_GetFontAscent(font))

method getDescent*(l: LabelSDL3): int =
  ## The font's descent in pixels (negative). _text_sdl2.pyx _get_fontdescent
  let font = getFont(l)
  if font == nil: 0 else: int(TTF_GetFontDescent(font))

method renderBegin*(l: LabelSDL3) =
  ## A transparent RGBA image of the label's size.
  ## _text_sdl2.pyx _SurfaceContainer.__init__
  let old = l.surface
  if old != nil:
    SDL_DestroySurface(old)
  l.surface = SDL_CreateSurface(cint(l.width), cint(l.height), SDL_PIXELFORMAT_RGBA32)

proc shape(font: TTF_Font) =
  # Where the text direction and script are set (Kivy's font_direction and
  # font_script_name); left to right is the only one in scope.
  discard TTF_SetFontDirection(font, TTF_DIRECTION_LTR)

method renderText*(l: LabelSDL3; text: string; x, y: int) =
  ## Renders `text` and copies it into the image at (x, y), y down.
  ## _text_sdl2.pyx _SurfaceContainer.render
  let font = getFont(l)
  let dst = l.surface
  if font == nil or dst == nil:
    return
  let o = l.options
  let c = SDL_Color(r: uint8(int(o.color[0] * 255)), g: uint8(int(o.color[1] * 255)),
    b: uint8(int(o.color[2] * 255)), a: 255)
  # The hinting and kerning are set when rendering only, as in Kivy, so a
  # font measured before its first render uses SDL_ttf's defaults (normal,
  # kerning on), which are Kivy's defaults too.
  let hinting = case o.fontHinting
    of hintingNormal: TTF_HINTING_NORMAL
    of hintingLight: TTF_HINTING_LIGHT
    of hintingMono: TTF_HINTING_MONO
    of hintingNone: TTF_HINTING_NONE
  if TTF_GetFontHinting(font) != hinting:
    TTF_SetFontHinting(font, hinting)
  if TTF_GetFontKerning(font) != o.fontKerning:
    TTF_SetFontKerning(font, o.fontKerning)
  shape(font)
  var t = text
  let st =
    if o.fontBlended: TTF_RenderText_Blended(font, t.toCString, csize_t(t.len), c)
    else: TTF_RenderText_Solid(font, t.toCString, csize_t(t.len), c)
  if st == nil:
    return
  var r = SDL_Rect(x: cint(x), y: cint(y), w: st.w, h: st.h)
  discard SDL_SetSurfaceAlphaMod(st, uint8(int(o.color[3] * 255)))
  # Kivy blends only when lines overlap (line_height < 1); otherwise the
  # pixels are copied, transparent ones included (kivy#6507, kivy#6508).
  if o.lineHeight < 1:
    discard SDL_SetSurfaceBlendMode(st, SDL_BLENDMODE_BLEND)
  else:
    discard SDL_SetSurfaceBlendMode(st, SDL_BLENDMODE_NONE)
  discard SDL_BlitSurface(st, nil, dst, addr r)
  SDL_DestroySurface(st)

method renderEnd*(l: LabelSDL3): nil ptr SDL_Surface =
  ## The rendered image; the caller takes it over.
  ## _text_sdl2.pyx _SurfaceContainer.get_data
  result = l.surface
  l.surface = nil
