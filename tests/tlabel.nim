# Tests uix/label: kivy/tests/test_app.py::test_basic_app (an App whose root
# is a Label), and the widget against Kivy 2.3.2: texture_size through the
# widget (the numbers of the `label` trace), the Clock trigger, empty text,
# the disabled colour, and the style.kv canvas. The pixels are compared in
# the label scenes.

import std/[assertions, opt]
import nimkivy/[app, clock, config]
import nimkivy/graphics/[texture, context_instructions, vertex_instructions]
import nimkivy/uix/label

Config.graphics.width = 800
Config.graphics.height = 600

proc rendered(l: Label): (float, float) =
  # Runs the label's trigger, as the frame before drawing does.
  Clock.tickDraw()
  result = l.textureSize

type Counter = ref object
  n: int

proc renderCounter(l: Label): Counter =
  # Counts the textures the label gets (one per render).
  let c = Counter(n: 0)
  discard l.bindTexture(proc (v: nil Texture) {.closure.} =
    if v != nil: inc c.n)
  result = c

block defaults:
  # uix/label.py: the property defaults; font_size is 15sp (15 at density 1).
  let l = newLabel()
  assert l.text == "" and l.fontName == "Roboto" and l.fontSize == 15
  assert not l.bold and not l.italic
  assert l.color == [1.0, 1, 1, 1] and l.disabledColor == [1.0, 1, 1, 0.3]
  assert l.halign == halignAuto and l.valign == valignBottom
  assert l.textSize.w.isNone and l.textSize.h.isNone
  assert l.lineHeight == 1.0 and l.padding == [0.0, 0, 0, 0]
  assert l.fontHinting == hintingNormal and l.fontKerning and l.fontBlended
  assert l.texture == nil and l.textureSize == (0.0, 0.0)
  assert l.rendered == (0.0, 0.0) and l.texture == nil

block trigger:
  # Changing properties schedules one render before the next frame.
  let l = newLabel("Hello world")
  assert l.textureSize == (0.0, 0.0)
  assert l.rendered == (77.0, 18.0)      # `label` trace: {'text': 'Hello world'}
  let renders = l.renderCounter()
  l.fontSize = 40
  l.text = "Hello"
  assert l.textureSize == (77.0, 18.0)
  assert l.rendered == (93.0, 47.0)      # {'text': 'Hello', 'font_size': 40}
  assert renders.n == 1
  let t = l.texture
  assert t != nil and t.size == (93, 47)
  l.textureUpdate()                      # renders at once
  assert renders.n == 2

block trace_numbers:
  # texture_size through the widget, against tests/fixtures/traces/label.txt.
  register("Deja", "data/fonts/DejaVuSans.ttf", fnBold = "data/fonts/Roboto-Bold.ttf")
  let text = "Figs have been grown in Greece for thousands of years. The fruit is " &
    "dried in the sun, pressed by hand and packed the same day."
  let a = newLabel("two\nlines")
  assert a.rendered == (32.0, 36.0)
  let b = newLabel("Hello")
  b.bold = true
  assert b.rendered == (35.0, 18.0)
  b.fontName = "Deja"
  assert b.rendered == (35.0, 18.0)      # Deja's bold is the Roboto-Bold file
  b.bold = false
  assert b.rendered == (37.0, 18.0)
  let c = newLabel(text)
  c.textSize = (some(300.0), none[float]())
  assert c.rendered == (300.0, 72.0)
  c.lineHeight = 1.25
  assert c.rendered == (300.0, 88.0)
  c.lineHeight = 0.8
  assert c.rendered == (300.0, 60.0)
  c.lineHeight = 1.0
  c.halign = halignJustify
  assert c.rendered == (300.0, 72.0)
  c.halign = halignAuto
  c.textSize = (300.0, 40.0)
  c.valign = valignMiddle
  assert c.rendered == (300.0, 40.0)
  let d = newLabel("Hello")
  d.padding = [10.0, 5]
  assert d.padding == [10.0, 5, 10, 5]
  assert d.rendered == (56.0, 28.0)
  d.padding = [0.0]
  d.textSize = (none[float](), some(100.0))
  assert d.rendered == (36.0, 100.0)
  let e = newLabel("averyveryverylongwordthatcannotwrap")
  e.textSize = (some(100.0), none[float]())
  assert e.rendered == (100.0, 54.0)

block empty_and_justify:
  # No texture for empty text, nor for spaces with halign justify.
  let l = newLabel("text")
  discard l.rendered
  assert l.texture != nil
  l.text = ""
  assert l.rendered == (0.0, 0.0) and l.texture == nil
  l.text = "   "
  assert l.rendered[0] > 0
  l.halign = halignJustify
  assert l.rendered == (0.0, 0.0) and l.texture == nil

block disabled_color:
  # Label._trigger_texture_update: while disabled the text is drawn in
  # disabled_color, so a change of `color` does not render again, and a
  # change of `disabled_color` does.
  let l = newLabel("x")
  discard l.rendered
  let renders = l.renderCounter()
  l.disabled = true
  discard l.rendered
  assert renders.n == 1
  l.color = [0.0, 1, 0, 1]
  discard l.rendered
  assert renders.n == 1
  l.disabledColor = [0.0, 0, 1, 0.5]
  discard l.rendered
  assert renders.n == 2
  l.disabled = false
  discard l.rendered
  assert renders.n == 3

block canvas:
  # data/style.kv <Label>: white Color, then a Rectangle with the texture,
  # size texture_size, at int(center - texture_size / 2).
  let l = newLabel("Hello world")
  l.pos = (10.0, 20.0)
  l.size = (101.0, 51.0)
  discard l.rendered
  let ch = l.canvas.children
  var color: nil Color = nil
  var rect: nil Rectangle = nil
  for i in 0 ..< ch.len:
    if ch[i] of Color: color = Color(ch[i])
    elif ch[i] of Rectangle: rect = Rectangle(ch[i])
  assert color != nil and color.rgba == [1.0, 1, 1, 1]
  assert rect != nil
  assert rect.size == (77.0, 18.0)
  assert rect.pos == (22.0, 36.0)        # int(60.5 - 38.5), int(45.5 - 9)
  assert rect.texture == l.texture
  l.center = (0.0, 0.0)
  assert rect.pos == (-38.0, -9.0)       # int() rounds toward zero

block hinting:
  # font_hinting: None is hintingNone.
  let l = newLabel("x")
  l.fontHinting = hintingNone
  assert l.fontHinting == hintingNone
  l.fontHinting = hintingMono
  assert l.fontHinting == hintingMono
  assert l.rendered[0] > 0

type BasicApp = ref object of App

method build(a: BasicApp): nil WidgetBase =
  # test_app.py basic_app: `return Label(text='Hello, World!')`
  discard Clock.scheduleOnce(proc (dt: float) {.closure.} = a.stop(), 0.1)
  result = newLabel("Hello, World!")

block test_basic_app:
  # kivy/tests/test_app.py::test_basic_app
  let a = BasicApp()
  a.initApp("TestApp")
  a.run()
  let root = a.root
  assert root != nil and root of Label
  assert Label(root).text == "Hello, World!"
  # The app drew frames, so the trigger rendered the texture.
  assert Label(root).textureSize[0] > 0
