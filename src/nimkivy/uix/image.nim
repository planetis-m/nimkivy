## The image widget: Kivy's `kivy/uix/image.py` (Image, not AsyncImage),
## with its rule from `kivy/data/style.kv`.
##
## An image loads `source` (searched with `resourceFind`) through
## `core/image`, whose cache shares one texture per file. `normImageSize`
## is the size the texture is drawn at, from `fitMode`: `fitScaleDown` (the
## default) fits the image in the widget without making it bigger, `fitFill`
## stretches it to the widget, `fitContain` fits it, larger or smaller, and
## `fitCover` fills the widget, keeping the image's ratio. The canvas draws the
## texture at that size, centred, tinted by `color`, clipped to the widget
## by a stencil, so `cover` does not draw outside it. Without a texture the
## image is a box of `color`.
##
## Build an image with `newImage()`; a subclass's constructor makes the
## object, calls `initProps`, then `initImage`.
##
## Out of scope (SCOPE.md): AsyncImage and its `on_load` and `on_error`
## events, animated images (`anim_delay`, `anim_loop`), `keep_data`,
## `mipmap`, `nocache`, and the deprecated `allow_stretch` and `keep_ratio`.

import std/syncio
import ../props
import ../graphics/[texture, context_instructions, vertex_instructions,
  stencil_instructions]
import ../core/image as coreimage
import ../resources
import widget

export widget, texture

type
  FitMode* = enum
    ## How the texture fits the widget (Kivy's `fit_mode` strings).
    fitScaleDown = "scale-down" ## fit inside, never larger than the image
    fitFill = "fill"            ## stretched to the widget
    fitContain = "contain"      ## fit inside, larger or smaller
    fitCover = "cover"          ## fill the widget, keeping the ratio (clipped)

properties:
  type
    Image* = ref object of Widget
      ## uix/image.py Image
      coreImage: nil CoreImage    # _coreimage
      source* {.prop.}: string = ""  ## the file shown ("" when none)
      texture* {.prop, handler.}: nil Texture = nil  ## the texture shown; nil when none
      textureSize* {.prop.}: (float, float) = (0.0, 0.0)  ## (0, 0) without a texture
      imageRatio* {.alias: getImageRatio, deps: texture, cache, eager.}: float
        ## the texture's width over its height; 1 without a texture
      color* {.color.}: Rgba = [1.0, 1, 1, 1]  ## the tint the texture is multiplied by
      fitMode* {.prop.}: FitMode = fitScaleDown  ## how the texture fits the widget
      normImageSize* {.alias: getNormImageSize, deps: (texture, size, imageRatio, fitMode),
        cache, eager.}: (float, float)  ## the size the texture is drawn at

  # -------------------------------------------------------------- geometry

  proc getImageRatio(im: Image): float =
    # Image.get_image_ratio
    let t = im.texture
    if t != nil:
      return float(t.width) / float(t.height)
    result = 1.0

  proc getNormImageSize(im: Image): (float, float) =
    # Image.get_norm_image_size
    let t = im.texture
    let (w, h) = im.size
    if t == nil:
      return (w, h)
    let ratio = im.imageRatio
    let tw = float(t.width)
    let th = float(t.height)
    let mode = im.fitMode
    case mode
    of fitCover:
      let widgetRatio = w / max(1.0, h)
      if widgetRatio > ratio:
        result = (w, (w * th) / tw)
      else:
        result = ((h * tw) / th, h)
    of fitFill:
      result = (w, h)
    of fitContain, fitScaleDown:
      var iw = if mode == fitContain: w else: min(w, tw)
      # calculate the appropriate height
      var ih = iw / ratio
      # if the height is too higher, take the height of the container
      # and calculate appropriate width. no need to test further. :)
      if ih > h:
        ih = if mode == fitContain: h else: min(h, th)
        iw = ih * ratio
      result = (iw, ih)

  method onTextureChanged*(im: Image; v: nil Texture) {.base.} =
    ## `textureSize` follows the texture. Image.on_texture
    im.textureSize = if v != nil: (float(v.width), float(v.height)) else: (0.0, 0.0)

  # -------------------------------------------------------------- loading

  proc logError(msg: string) =
    # Kivy's Logger.error, on stderr in Kivy's layout.
    stderr.writeLine "[ERROR  ] [Image       ] " & msg

  proc clearCoreImage(im: Image) =
    # Image._clear_core_image
    im.texture = nil
    im.coreImage = nil

  proc setTextureFromResource*(im: Image; resource: string) =
    ## Loads `resource` and shows its texture; "" or a file that is not found
    ## shows nothing (with a log line). Image.set_texture_from_resource
    if resource.len == 0:
      im.clearCoreImage()
      return
    let source = resourceFind(resource)
    if source.len == 0:
      logError "Not found <" & resource & ">"
      im.clearCoreImage()
      return
    let image = newCoreImage(source)
    if image.texture == nil:
      # Kivy's CoreImage raises when the file cannot be decoded.
      logError "Error loading <" & resource & ">"
      im.clearCoreImage()
      return
    im.coreImage = image
    im.texture = image.texture

  proc textureUpdate*(im: Image) =
    ## Loads `source` again. Image.texture_update
    im.setTextureFromResource(im.source)

  proc removeFromCache*(im: Image) =
    ## Drops the image's texture from the cache, so the next load reads the
    ## file. Image.remove_from_cache
    let c = im.coreImage
    if c != nil:
      c.removeFromCache()

  proc reload*(im: Image) =
    ## Reads the file again, from the disk, not from the cache. Image.reload
    im.removeFromCache()
    let oldSource = im.source
    im.source = ""
    im.source = oldSource

  # -------------------------------------------------------------- canvas

  proc place(im: Image; picture: Rectangle) =
    let (nw, nh) = im.normImageSize
    picture.pos = (im.centerX - nw / 2.0, im.centerY - nh / 2.0)

  proc applyStyle(im: Image) =
    # data/style.kv <Image,AsyncImage>: Color(color); a stencil of the widget
    # box; the texture at norm_image_size, centred; the stencil removed. Each
    # kv binding becomes an observer.
    let color = newColor()
    color.rgba = im.color
    let mask = newRectangle(im.pos, im.size)
    let picture = newRectangle()
    let unmask = newRectangle(im.pos, im.size)
    let c = im.canvas
    c.add color
    c.add newStencilPush()
    c.add mask
    c.add newStencilUse()
    c.add picture
    c.add newStencilUnUse()
    c.add unmask
    c.add newStencilPop()
    picture.texture = im.texture
    picture.size = im.normImageSize
    im.place(picture)
    discard im.bindColor(proc (v: Rgba) {.closure.} = color.rgba = v)
    discard im.bindPos(proc (v: (float, float)) {.closure.} =
      mask.pos = v
      unmask.pos = v)
    discard im.bindSize(proc (v: (float, float)) {.closure.} =
      mask.size = v
      unmask.size = v)
    discard im.bindTexture(proc (v: nil Texture) {.closure.} = picture.texture = v)
    discard im.bindNormImageSize(proc (v: (float, float)) {.closure.} =
      picture.size = v
      im.place(picture))
    discard im.bindCenterX(proc (v: float) {.closure.} = im.place(picture))
    discard im.bindCenterY(proc (v: float) {.closure.} = im.place(picture))

  proc initImage*(im: Image) =
    ## Sets up a new image whose properties `initProps` has set: the widget,
    ## a load whenever `source` changes, and the style.kv canvas.
    ## Image.__init__
    im.initWidget()
    discard im.bindSource(proc (v: string) {.closure.} = im.textureUpdate())
    im.applyStyle()

  proc newImage*(): Image =
    ## An image with no source: a white box.
    result = Image(canvas: newCanvas(), coreImage: nil)
    result.initProps()
    result.initImage()

  proc newImage*(source: sink string): Image =
    ## An image showing the file `source`.
    result = newImage()
    result.source = source
