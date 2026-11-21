## Raw bindings to SDL3_ttf (3.2), only the part nimkivy uses.
##
## Names, types and values are those of `<SDL3_ttf/SDL_ttf.h>`; see
## `sdl.nim` for the conventions. Strings are UTF-8 with an explicit byte
## length (0 for NUL-terminated).

import sdl

{.passL: "-lSDL3_ttf".}

const TtfHeader = "<SDL3_ttf/SDL_ttf.h>"

type
  TTF_FontObj {.importc: "TTF_Font", header: TtfHeader,
      incompleteStruct.} = object
  TTF_Font* = ptr TTF_FontObj ## An open font at one size.

  TTF_HintingFlags* = distinct cint ## The FreeType hinter.
  TTF_FontStyleFlags* = distinct uint32 ## Bold, italic and lines.
  TTF_Direction* = distinct cint ## Direction of shaped text.

proc `==`*(a, b: TTF_HintingFlags): bool {.borrow.}
proc `==`*(a, b: TTF_FontStyleFlags): bool {.borrow.}
proc `or`*(a, b: TTF_FontStyleFlags): TTF_FontStyleFlags {.borrow.}
proc `==`*(a, b: TTF_Direction): bool {.borrow.}

const
  TTF_HINTING_INVALID* = TTF_HintingFlags(-1)
  TTF_HINTING_NORMAL* = TTF_HintingFlags(0)
  TTF_HINTING_LIGHT* = TTF_HintingFlags(1)
  TTF_HINTING_MONO* = TTF_HintingFlags(2)
  TTF_HINTING_NONE* = TTF_HintingFlags(3)
  TTF_HINTING_LIGHT_SUBPIXEL* = TTF_HintingFlags(4)

  TTF_STYLE_NORMAL* = TTF_FontStyleFlags(0x00'u32)
  TTF_STYLE_BOLD* = TTF_FontStyleFlags(0x01'u32)
  TTF_STYLE_ITALIC* = TTF_FontStyleFlags(0x02'u32)
  TTF_STYLE_UNDERLINE* = TTF_FontStyleFlags(0x04'u32)
  TTF_STYLE_STRIKETHROUGH* = TTF_FontStyleFlags(0x08'u32)

  TTF_DIRECTION_INVALID* = TTF_Direction(0)
  TTF_DIRECTION_LTR* = TTF_Direction(4)
  TTF_DIRECTION_RTL* = TTF_Direction(5)
  TTF_DIRECTION_TTB* = TTF_Direction(6)
  TTF_DIRECTION_BTT* = TTF_Direction(7)

{.push cdecl, importc, header: TtfHeader.}

proc TTF_Init*(): bool
  ## Initializes the library.
proc TTF_Quit*()
  ## Shuts the library down.
proc TTF_OpenFont*(file: cstring; ptsize: cfloat): nil TTF_Font
  ## Opens a font file at a point size, or nil on failure.
proc TTF_CloseFont*(font: TTF_Font)
  ## Closes a font.
proc TTF_SetFontHinting*(font: TTF_Font; hinting: TTF_HintingFlags)
  ## Sets the hinter.
proc TTF_SetFontKerning*(font: TTF_Font; enabled: bool)
  ## Turns kerning on or off.
proc TTF_SetFontStyle*(font: TTF_Font; style: TTF_FontStyleFlags)
  ## Sets bold, italic, underline and strikethrough.
proc TTF_GetFontHeight*(font: TTF_Font): cint
  ## The maximum pixel height of the font's glyphs.
proc TTF_GetFontAscent*(font: TTF_Font): cint
  ## Pixels from the baseline to the top.
proc TTF_GetFontDescent*(font: TTF_Font): cint
  ## Pixels from the baseline to the bottom (negative).
proc TTF_GetStringSize*(font: TTF_Font; text: cstring; length: csize_t;
    w, h: nil ptr cint): bool
  ## The size the text would be rendered at.
proc TTF_RenderText_Blended*(font: TTF_Font; text: cstring; length: csize_t;
    fg: SDL_Color): nil ptr SDL_Surface
  ## A new ARGB surface with the antialiased text, or nil on failure.
proc TTF_SetFontDirection*(font: TTF_Font; direction: TTF_Direction): bool
  ## Sets the direction text is shaped in.
proc TTF_SetFontScript*(font: TTF_Font; script: uint32): bool
  ## Sets the ISO 15924 script (a four-letter tag) text is shaped as.

{.pop.}
