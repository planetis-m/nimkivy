## Image loading: the part of Kivy's `kivy/core/image/__init__.py` (Image,
## ImageLoader, ImageLoaderBase.populate) and `img_sdl2.py` that loads a file
## into a texture, plus the `source` setters of `BindTexture` and the vertex
## instructions (`context_instructions.pyx`, `instructions.pyx`), which load
## through it.
##
## SDL3_image decodes the file into a surface, and the texture takes it over,
## flipped vertically as Kivy's ImageData is (the first row is the top of the
## picture). Textures are cached by resolved file name, as Kivy's
## `kv.texture` cache is, so loading the same file twice gives the same
## texture. Kivy keeps two caches (`kv.image` keyed by the name given,
## `kv.texture` by the resolved one) that expire after 60 seconds unused;
## here there is one, and it keeps every texture (SCOPE.md: `nocache`,
## `keep_data`, `mipmap`, atlases, zip and animated images are out).
##
## A file that is missing or cannot be decoded gives a nil texture and a log
## line, never a crash.

import std/[tables, syncio]
import ../sdl3/[sdl, image]
import ../graphics/[texture, instructions]
import ../resources

type
  CoreImage* = ref object
    ## An image loaded from a file: its size and texture.
    ## core/image/__init__.py Image
    filename: string
    size: (int, int)
    texture: nil Texture

  TextureCache = ref object
    textures: Table[string, nil Texture]

let textureCache = TextureCache(textures: initTable[string, nil Texture]())

proc warn(msg: string) =
  # Kivy's Logger.warning, on stderr in Kivy's layout.
  stderr.writeLine "[WARNING] [Image       ] " & msg

proc loadTexture(filename: string): nil Texture =
  # img_sdl2.py ImageLoaderSDL2.load, then ImageLoaderBase.populate: the
  # texture of a resolved file name, from the cache or decoded.
  let uid = filename & "|0|0"
  let cached = textureCache.textures.getOrDefault(uid)
  if cached != nil:
    return cached
  var path = filename
  # GAP: decoded JPEG pixels can differ slightly from Kivy's, because SDL3_image
  # 3.4 replaces the SDL2_image bundled with Kivy 2.3.2.
  let surface = IMG_Load(path.toCString)
  if surface == nil:
    warn "Unable to load image <" & filename & ">"
    return nil
  let t = newTexture(surface)
  # ImageData.flip_vertical is True for decoded files.
  t.flipVertical()
  textureCache.textures[uid] = t
  result = t

proc newCoreImage*(filename: string): CoreImage =
  ## Loads `filename`, searched with `resourceFind`. The texture is nil when
  ## the file is missing or cannot be decoded. core/image/__init__.py
  ## Image(filename) and Image._set_filename
  result = CoreImage(filename: filename, size: (0, 0), texture: nil)
  let found = resourceFind(filename)
  if found.len == 0:
    warn "Unable to load image <" & filename & ">"
    return
  let t = loadTexture(found)
  if t != nil:
    result.texture = t
    result.size = t.size

proc filename*(im: CoreImage): string {.inline.} =
  ## The file name the image was asked for.
  im.filename

proc texture*(im: CoreImage): nil Texture {.inline.} =
  ## The image's texture; nil if it could not be loaded.
  im.texture

proc size*(im: CoreImage): (int, int) {.inline.} =
  ## The size in pixels; (0, 0) if it could not be loaded.
  im.size

proc width*(im: CoreImage): int {.inline.} =
  ## The width in pixels.
  im.size[0]

proc height*(im: CoreImage): int {.inline.} =
  ## The height in pixels.
  im.size[1]

proc removeFromCache*(im: CoreImage) =
  ## Drops the image's texture from the cache, so the next load reads the
  ## file again. core/image/__init__.py Image.remove_from_cache
  let found = resourceFind(im.filename)
  if found.len > 0:
    textureCache.textures.del(found & "|0|0")

proc `source=`*(b: BindTexture; filename: string) =
  ## Loads `filename` (searched with `resourceFind`) and binds its texture;
  ## a name that is not found binds the default texture, silently, as in
  ## Kivy. context_instructions.pyx BindTexture.source
  let found = resourceFind(filename)
  if found.len > 0:
    b.setSource(found, newCoreImage(found).texture)
  else:
    b.setSource("", nil)

proc `source=`*(v: VertexInstruction; filename: string) =
  ## Loads `filename` and draws `v` with its texture, mapped by the
  ## texture's coordinates. instructions.pyx VertexInstruction.source
  v.textureBinding.source = filename
  v.texture = v.textureBinding.texture
