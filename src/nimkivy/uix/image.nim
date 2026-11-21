## The image widget: Kivy's `kivy/uix/image.py` (Image, not AsyncImage),
## with its rule from `kivy/data/style.kv`.
##
## An image loads `source` (searched with `resourceFind`) through
## `core/image`, whose cache shares one texture per file. `norm_image_size`
## is the size the texture is drawn at, from `fit_mode`: `scale-down` (the
## default) fits the image in the widget without making it bigger, `fill`
## stretches it to the widget, `contain` fits it, larger or smaller, and
## `cover` fills the widget, keeping the image's ratio. The canvas draws the
## texture at that size, centred, tinted by `color`, clipped to the widget
## by a stencil, so `cover` does not draw outside it. Without a texture the
## image is a box of `color`.
##
## Out of scope (SCOPE.md): AsyncImage and its `on_load` and `on_error`
## events, animated images (`anim_delay`, `anim_loop`), `keep_data`,
## `mipmap`, `nocache`, and the deprecated `allow_stretch` and `keep_ratio`.

import std/syncio
import ../properties
import ../graphics/[texture, context_instructions, vertex_instructions,
  stencil_instructions]
import ../core/image as coreimage
import ../resources
import widget

export widget, texture

type
  Image* = ref object of Widget
    ## uix/image.py Image
    coreImage: nil CoreImage    # _coreimage

  FitMode* = enum
    ## How the texture fits the widget (Kivy's `fit_mode` strings).
    fitScaleDown = "scale-down" ## fit inside, never larger than the image
    fitFill = "fill"            ## stretched to the widget
    fitContain = "contain"      ## fit inside, larger or smaller
    fitCover = "cover"          ## fill the widget, keeping the ratio (clipped)

let ImageClass* = newDispatcherClass("Image", WidgetClass)
  ## The class of `Image`.

proc getImageRatio(d: EventDispatcher): Value
proc getNormImageSize(d: EventDispatcher): Value

let pSource = StringProperty(name: "", index: 0, defaultValue: noneValue(),
  allowNone: true, forceDispatch: false, comparator: nil)
ImageClass.addProperty("source", pSource)
let pTexture = ImageClass.addObject("texture", noneValue(), allowNone = true)
let pTextureSize = ImageClass.addList("texture_size", @[toValue(0.0), toValue(0.0)])
let pImageRatio = ImageClass.addAlias("image_ratio", getImageRatio, nil, @["texture"],
  cache = true)
let pColor = ImageClass.addColor("color", @[1.0, 1, 1, 1])
let pFitMode = ImageClass.addOption("fit_mode", "scale-down",
  @["scale-down", "fill", "contain", "cover"])
let pNormImageSize = ImageClass.addAlias("norm_image_size", getNormImageSize, nil,
  @["texture", "size", "image_ratio", "fit_mode"], cache = true)

proc logError(msg: string) =
  # Kivy's Logger.error, on stderr in Kivy's layout.
  stderr.writeLine "[ERROR  ] [Image       ] " & msg

# ------------------------------------------------------------------ accessors

proc source*(im: Image): string {.inline.} =
  ## The file shown ("" when none).
  pSource.getString(im)
proc `source=`*(im: Image; v: string) {.inline.} =
  ## Loads and shows `v`; "" shows nothing.
  discard pSource.set(im, toValue(v))
proc texture*(im: Image): nil Texture {.inline.} =
  ## The texture shown; nil when nothing is loaded.
  toTexture(pTexture.get(im))
proc `texture=`*(im: Image; t: nil Texture) {.inline.} =
  ## Shows `t` (until `source` changes).
  discard pTexture.set(im, toValue(t))
proc textureSize*(im: Image): (float, float) =
  ## The size of the texture; (0, 0) without one.
  let v = pTextureSize.get(im)
  result = (v.items[0].num, v.items[1].num)
proc imageRatio*(im: Image): float {.inline.} =
  ## The texture's width over its height; 1 without a texture.
  pImageRatio.getNumber(im)
proc color*(im: Image): array[4, float] =
  ## The tint the texture is multiplied by (default white).
  let c = pColor.getFloats(im)
  result = [c[0], c[1], c[2], c[3]]
proc `color=`*(im: Image; v: array[4, float]) {.inline.} =
  ## Sets the tint.
  pColor.setFloats(im, v)
proc fitMode*(im: Image): FitMode {.inline.} =
  ## How the texture fits the widget (default scale-down).
  FitMode(pFitMode.getOption(im))
proc `fitMode=`*(im: Image; v: FitMode) {.inline.} =
  ## Sets how the texture fits the widget.
  pFitMode.setOption(im, ord(v))
proc normImageSize*(im: Image): (float, float) =
  ## The size the texture is drawn at.
  let v = pNormImageSize.get(im)
  result = (v.items[0].num, v.items[1].num)

# ------------------------------------------------------------------ geometry

proc getImageRatio(d: EventDispatcher): Value =
  # Image.get_image_ratio
  let t = toTexture(pTexture.get(d))
  if t != nil:
    return toValue(float(t.width) / float(t.height))
  result = toValue(1.0)

proc getNormImageSize(d: EventDispatcher): Value =
  # Image.get_norm_image_size
  let im = Image(d)
  let t = im.texture
  let (w, h) = im.size
  if t == nil:
    return toValue([w, h])
  let ratio = im.imageRatio
  let tw = float(t.width)
  let th = float(t.height)
  let mode = im.fitMode
  case mode
  of fitCover:
    let widgetRatio = w / max(1.0, h)
    if widgetRatio > ratio:
      return toValue([w, (w * th) / tw])
    else:
      return toValue([(h * tw) / th, h])
  of fitFill:
    return toValue([w, h])
  of fitContain, fitScaleDown:
    var iw = if mode == fitContain: w else: min(w, tw)
    # calculate the appropriate height
    var ih = iw / ratio
    # if the height is too higher, take the height of the container
    # and calculate appropriate width. no need to test further. :)
    if ih > h:
      ih = if mode == fitContain: h else: min(h, th)
      iw = ih * ratio
    result = toValue([iw, ih])

proc onTexture(d: EventDispatcher; v: Value) =
  # Image.on_texture
  let t = toTexture(v)
  let size = if t != nil: [float(t.width), float(t.height)] else: [0.0, 0.0]
  discard pTextureSize.set(d, toValue(size))

ImageClass.addPropertyHandler("texture", onTexture)

# ------------------------------------------------------------------ loading

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

# ------------------------------------------------------------------ canvas

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
  proc place(im: Image; picture: Rectangle) =
    let (nw, nh) = im.normImageSize
    picture.pos = (im.centerX - nw / 2.0, im.centerY - nh / 2.0)
  picture.texture = im.texture
  picture.size = im.normImageSize
  place(im, picture)
  discard im.fbind("color", proc (d: EventDispatcher; v: Value) {.closure.} =
    let f = v.toFloats
    color.rgba = [f[0], f[1], f[2], f[3]])
  discard im.fbind("pos", proc (d: EventDispatcher; v: Value) {.closure.} =
    mask.pos = (v.items[0].num, v.items[1].num)
    unmask.pos = (v.items[0].num, v.items[1].num))
  discard im.fbind("size", proc (d: EventDispatcher; v: Value) {.closure.} =
    mask.size = (v.items[0].num, v.items[1].num)
    unmask.size = (v.items[0].num, v.items[1].num))
  discard im.fbind("texture", proc (d: EventDispatcher; v: Value) {.closure.} =
    picture.texture = toTexture(v))
  discard im.fbind("norm_image_size", proc (d: EventDispatcher; v: Value) {.closure.} =
    picture.size = (v.items[0].num, v.items[1].num)
    place(im, picture))
  for name in ["center_x", "center_y"]:
    discard im.fbind(name, proc (d: EventDispatcher; v: Value) {.closure.} =
      place(im, picture))

proc initImage*(im: Image) =
  ## Sets up a new image: the widget, a load whenever `source` changes, and
  ## the style.kv canvas. Build it with `Image(cls: ImageClass, canvas:
  ## newCanvas())` (or a subclass's class). Image.__init__
  im.initWidget()
  discard im.fbind("source", proc (d: EventDispatcher; v: Value) {.closure.} =
    im.textureUpdate())
  im.applyStyle()

proc newImage*(): Image =
  ## An image with no source: a white box.
  result = Image(cls: ImageClass, canvas: newCanvas(), coreImage: nil)
  result.initImage()

proc newImage*(source: string): Image =
  ## An image showing the file `source`.
  result = newImage()
  result.source = source
