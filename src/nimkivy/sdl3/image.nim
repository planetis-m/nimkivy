## Raw bindings to SDL3_image (3.4), only the part nimkivy uses.
##
## Names and types are those of `<SDL3_image/SDL_image.h>`; see `sdl.nim` for
## the conventions.

import sdl

{.passL: "-lSDL3_image".}

const ImgHeader = "<SDL3_image/SDL_image.h>"

{.push cdecl, importc, header: ImgHeader.}

proc IMG_Load*(file: cstring): nil ptr SDL_Surface
  ## A new surface with the image in the file, or nil on failure.
proc IMG_SavePNG*(surface: ptr SDL_Surface; file: cstring): bool
  ## Writes a surface to a PNG file.

{.pop.}
