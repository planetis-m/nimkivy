## Textures: the part of Kivy's `kivy/graphics/texture.pyx` that nimkivy uses.
##
## A `Texture` has a size in pixels and a UV rectangle (`uvpos`, `uvsize`)
## that gives its `texCoords`, the eight texture coordinates a vertex
## instruction maps onto its corners. Flipping negates the UV size, as in
## Kivy. Kivy's `t` axis counts rows in the order the pixels were uploaded,
## which is also SDL's `v` axis, so the coordinates go to SDL unchanged.
##
## There is no OpenGL: a texture holds an SDL surface until the renderer first
## draws it, then the SDL texture that the renderer made from it. Render
## targets (FadeTransition) are SDL textures from the start. Filtering is
## linear, Kivy's default. Out of scope (SCOPE.md): regions, mipmaps, wrap
## modes, `blit_buffer` (except at creation, `newTexture(width, height, rgba)`)
## and reload observers.

import std/[assertions, syncio]
import ../sdl3/sdl

type
  TextureObj* = object
    ## The texture's data; use `Texture`.
    width, height: int
    uvx, uvy, uvw, uvh: float32
    texCoords: array[8, float32]
    surface: nil ptr SDL_Surface    # pixels not uploaded yet, owned
    handle: nil SDL_Texture         # the uploaded texture, owned
    owner: nil SDL_Renderer         # the renderer `handle` belongs to

  Texture* = ref TextureObj
    ## A texture. Kivy's tex_coords are kept per texture; vertex instructions
    ## copy them when the texture is set.

proc `=wasMoved`(t: var TextureObj) =
  t.surface = nil
  t.handle = nil

proc `=destroy`(t: TextureObj) =
  let s = t.surface
  if s != nil:
    SDL_DestroySurface(s)
  let h = t.handle
  if h != nil:
    SDL_DestroyTexture(h)

proc updateTexCoords(t: Texture) =
  # texture.pyx Texture.update_tex_coords
  t.texCoords = [t.uvx, t.uvy, t.uvx + t.uvw, t.uvy, t.uvx + t.uvw, t.uvy + t.uvh,
    t.uvx, t.uvy + t.uvh]

proc newTexture(width, height: int; surface: nil ptr SDL_Surface;
    handle: nil SDL_Texture; owner: nil SDL_Renderer): Texture =
  # texture.pyx Texture.__init__: the whole texture, not flipped.
  result = Texture(width: width, height: height, uvx: 0, uvy: 0, uvw: 1, uvh: 1,
    surface: surface, handle: handle, owner: owner)
  result.updateTexCoords()

proc newTexture*(surface: ptr SDL_Surface): Texture =
  ## A texture with the pixels of `surface`, which it takes over. The first
  ## row of the surface is `t = 0`; image and text loaders flip it
  ## vertically, as Kivy's do.
  result = newTexture(int(surface.w), int(surface.h), surface, nil, nil)

proc newTexture*(width, height: int; rgba: openArray[uint8]): Texture =
  ## A texture of `width` x `height` pixels made of `rgba`, four bytes (R, G,
  ## B, A) per pixel, row after row: Kivy's `Texture.create(size,
  ## colorfmt="rgba")` followed by `blit_buffer`. The program stops if SDL
  ## cannot make the surface (out of memory).
  assert rgba.len == width * height * 4
  let s = SDL_CreateSurface(cint(width), cint(height), SDL_PIXELFORMAT_RGBA32)
  if s == nil:
    quit "cannot make a surface of " & $width & " x " & $height & " pixels"
  let dst = cast[ptr UncheckedArray[uint8]](s.pixels)
  for row in 0 ..< height:
    for k in 0 ..< width * 4:
      dst[row * int(s.pitch) + k] = rgba[row * width * 4 + k]
  result = newTexture(s)

proc newTexture*(renderer: SDL_Renderer; handle: SDL_Texture): Texture =
  ## A texture for an SDL texture that `renderer` made (a render target),
  ## which it takes over.
  var w = 0'f32
  var h = 0'f32
  discard SDL_GetTextureSize(handle, addr w, addr h)
  result = newTexture(int(w), int(h), nil, handle, renderer)

proc width*(t: Texture): int {.inline.} =
  ## The width in pixels.
  t.width

proc height*(t: Texture): int {.inline.} =
  ## The height in pixels.
  t.height

proc size*(t: Texture): (int, int) {.inline.} =
  ## The size in pixels.
  (t.width, t.height)

proc texCoords*(t: Texture): array[8, float32] {.inline.} =
  ## `[u, v, u + w, v, u + w, v + h, u, v + h]` from `uvpos` and `uvsize`.
  t.texCoords

proc uvpos*(t: Texture): (float, float) =
  ## The UV position inside the texture.
  (float(t.uvx), float(t.uvy))

proc `uvpos=`*(t: Texture; p: (float, float)) =
  ## Sets the UV position.
  t.uvx = float32(p[0])
  t.uvy = float32(p[1])
  t.updateTexCoords()

proc uvsize*(t: Texture): (float, float) =
  ## The UV size, negative where the texture is flipped.
  (float(t.uvw), float(t.uvh))

proc `uvsize=`*(t: Texture; s: (float, float)) =
  ## Sets the UV size.
  t.uvw = float32(s[0])
  t.uvh = float32(s[1])
  t.updateTexCoords()

proc flipVertical*(t: Texture) =
  ## Flips the texture coordinates vertically.
  ## texture.pyx Texture.flip_vertical
  t.uvy += t.uvh
  t.uvh = -t.uvh
  t.updateTexCoords()

proc flipHorizontal*(t: Texture) =
  ## Flips the texture coordinates horizontally.
  ## texture.pyx Texture.flip_horizontal
  t.uvx += t.uvw
  t.uvw = -t.uvw
  t.updateTexCoords()

proc blitData*(t: Texture; surface: ptr SDL_Surface) =
  ## Replaces the pixels with those of `surface`, which it takes over and
  ## which has the texture's size; the next draw uploads them.
  ## texture.pyx Texture.blit_data
  let old = t.surface
  if old != nil:
    SDL_DestroySurface(old)
  let h = t.handle
  if h != nil:
    SDL_DestroyTexture(h)
  t.handle = nil
  t.owner = nil
  t.surface = surface

proc handle*(t: Texture; renderer: SDL_Renderer): nil SDL_Texture =
  ## The SDL texture to draw `t` with on `renderer`, uploading the surface
  ## the first time; nil if the upload fails. Called by the renderer.
  if t.handle == nil:
    let s = t.surface
    if s != nil:
      let h = SDL_CreateTextureFromSurface(renderer, s)
      if h != nil:
        # Kivy's default filter: texture.pyx _texture_create sets 'linear'.
        discard SDL_SetTextureScaleMode(h, SDL_SCALEMODE_LINEAR)
        SDL_DestroySurface(s)
        t.surface = nil
        t.handle = h
        t.owner = renderer
  result = t.handle

