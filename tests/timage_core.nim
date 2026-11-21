# Tests core/image: loading PNG and JPEG into textures with SDL3_image, the
# texture cache, a missing file, and `source` on BindTexture and the vertex
# instructions. Kivy's loader tests are not ported (ACCEPTANCE.md); the
# `graphics_texture` scene compares the pictures.

import std/assertions
import nimkivy/graphics/[texture, instructions, vertex_instructions]
import nimkivy/core/image

block load_png_and_jpeg:
  let png = newCoreImage("reference/assets/landscape.png")
  assert png.size == (400, 200)
  let t = png.texture
  assert t != nil and t.size == (400, 200)
  # Decoded images are flipped: the first row is the top of the picture.
  assert t.uvpos == (0.0, 1.0) and t.uvsize == (1.0, -1.0)
  let jpg = newCoreImage("reference/assets/landscape.jpg")
  assert jpg.size == (400, 200) and jpg.texture != nil
  let small = newCoreImage("reference/assets/small.png")
  assert small.width == 40 and small.height == 30

block missing_file:
  # A missing file logs a line and gives no texture, never a crash.
  let im = newCoreImage("reference/assets/no-such-image.png")
  assert im.texture == nil
  assert im.size == (0, 0)

block cache:
  # The same file gives the same texture, until it is removed from the cache.
  let a = newCoreImage("reference/assets/flag.png")
  let b = newCoreImage("reference/assets/flag.png")
  assert a.texture != nil and a.texture == b.texture
  a.removeFromCache()
  let c = newCoreImage("reference/assets/flag.png")
  assert c.texture != a.texture

block source_on_instructions:
  # instructions.pyx VertexInstruction.source: the texture and its
  # coordinates come from the file.
  let r = newRectangle((0.0, 0.0), (100.0, 50.0))
  r.source = "reference/assets/portrait.png"
  let t = r.texture
  assert t != nil and t.size == (100, 200)
  assert r.texCoords == t.texCoords
  assert r.source.len > 0
  # A name that is not found binds the default texture.
  r.source = "reference/assets/no-such-image.png"
  assert r.texture == nil
  assert r.source == ""
