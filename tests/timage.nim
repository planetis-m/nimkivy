# Tests uix/image against Kivy 2.3.2: norm_image_size for every fit mode
# (the numbers of reference/out/image_fit.txt), texture_size and
# image_ratio, a missing file, an empty source, reload, and the style.kv
# canvas (stencil of the widget box, texture centred). The pixels are
# compared in the image scenes.

import std/[assertions]
import nimkivy/config
import nimkivy/graphics/[context_instructions, vertex_instructions, stencil_instructions]
import nimkivy/uix/image

Config.set("graphics", "width", "800")
Config.set("graphics", "height", "600")

proc a(name: string): string = "reference/assets/" & name

proc sized(source: string; mode: FitMode; w, h: float): Image =
  result = newImage(source)
  result.fitMode = mode
  result.size = (w, h)

block test_fit_modes:
  # reference/out/image_fit.txt: a 180 x 150 box; landscape 400 x 200,
  # portrait 100 x 200, small 40 x 30.
  let expected = [
    (fitScaleDown, "landscape.png", (180.0, 90.0)),
    (fitScaleDown, "portrait.png", (75.0, 150.0)),
    (fitScaleDown, "small.png", (40.0, 30.0)),
    (fitFill, "landscape.png", (180.0, 150.0)),
    (fitFill, "portrait.png", (180.0, 150.0)),
    (fitFill, "small.png", (180.0, 150.0)),
    (fitContain, "landscape.png", (180.0, 90.0)),
    (fitContain, "portrait.png", (75.0, 150.0)),
    (fitContain, "small.png", (180.0, 135.0)),
    (fitCover, "landscape.png", (300.0, 150.0)),
    (fitCover, "portrait.png", (180.0, 360.0)),
    (fitCover, "small.png", (200.0, 150.0))]
  for (mode, src, nis) in expected:
    let im = sized(a(src), mode, 180, 150)
    assert im.normImageSize == nis

block texture_and_ratio:
  let im = newImage()
  assert im.source == "" and im.texture == nil
  assert im.textureSize == (0.0, 0.0) and im.imageRatio == 1.0
  assert im.fitMode == fitScaleDown and im.color == [1.0, 1, 1, 1]
  # No texture: norm_image_size is the widget size.
  assert im.normImageSize == (100.0, 100.0)
  im.source = a("landscape.png")
  assert im.texture != nil and im.textureSize == (400.0, 200.0)
  assert im.imageRatio == 2.0
  assert im.normImageSize == (100.0, 50.0)
  # norm_image_size follows the size, the texture and fit_mode.
  im.size = (50.0, 50.0)
  assert im.normImageSize == (50.0, 25.0)
  im.fitMode = fitFill
  assert im.normImageSize == (50.0, 50.0)
  im.source = a("portrait.png")
  assert im.textureSize == (100.0, 200.0) and im.imageRatio == 0.5
  im.fitMode = fitCover
  assert im.normImageSize == (50.0, 100.0)

block missing_and_empty:
  # A file that is not found: no texture, a log line, no crash.
  let im = newImage(a("landscape.png"))
  assert im.texture != nil
  im.source = a("no-such-image.png")
  assert im.texture == nil and im.textureSize == (0.0, 0.0)
  im.source = a("landscape.png")
  assert im.texture != nil
  im.source = ""
  assert im.texture == nil and im.normImageSize == im.size

block shared_texture_and_reload:
  # The cache gives two images of one file the same texture; reload reads
  # the file again.
  let one = newImage(a("small.png"))
  let two = newImage(a("small.png"))
  let t = one.texture
  assert t != nil and t == two.texture
  var changes = 0
  one.bind("texture", proc (d: EventDispatcher; v: Value) {.closure.} = inc changes)
  one.reload()
  assert one.texture != nil and one.texture != t
  assert one.source == a("small.png") and one.textureSize == (40.0, 30.0)
  assert changes == 2                    # None, then the new texture

block canvas:
  # data/style.kv <Image>: Color(color), StencilPush, the box, StencilUse,
  # the texture at norm_image_size centred, StencilUnUse, the box,
  # StencilPop.
  let im = sized(a("landscape.png"), fitCover, 180, 150)
  im.pos = (10.0, 20.0)
  im.color = [1.0, 0.5, 0.5, 1]
  let ch = im.canvas.children
  var kinds: seq[string] = @[]
  var rects: seq[Rectangle] = @[]
  var color: nil Color = nil
  for i in 0 ..< ch.len:
    let c = ch[i]
    if c of Color:
      kinds.add "Color"
      color = Color(c)
    elif c of StencilPush: kinds.add "StencilPush"
    elif c of StencilUse: kinds.add "StencilUse"
    elif c of StencilUnUse: kinds.add "StencilUnUse"
    elif c of StencilPop: kinds.add "StencilPop"
    elif c of Rectangle:
      kinds.add "Rectangle"
      rects.add Rectangle(c)
  assert kinds == @["Color", "StencilPush", "Rectangle", "StencilUse", "Rectangle",
    "StencilUnUse", "Rectangle", "StencilPop"], $kinds
  assert color != nil and color.rgba == [1.0, 0.5, 0.5, 1]
  for r in [rects[0], rects[2]]:
    assert r.pos == (10.0, 20.0) and r.size == (180.0, 150.0)
  assert rects[1].size == (300.0, 150.0)
  assert rects[1].pos == (-50.0, 20.0)   # centred: 100 - 150, 95 - 75
  assert rects[1].texture == im.texture
  im.source = ""
  assert rects[1].texture == nil and rects[1].size == (180.0, 150.0)
  assert rects[1].pos == (10.0, 20.0)
