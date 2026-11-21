"""Reference scenes rendered by real Kivy 2.3.2, for comparison with nimkivy.

Each scene builds a widget tree in an 800 x 600 window, waits a few frames, saves
reference/out/<scene>.png (the picture) and <scene>.txt (every widget's pos, size,
texture_size, norm_image_size) and quits. nimkivy's tests/scenes render the same trees.

Run from nimkivy/ (Kivy runs one app per process, so each scene is a subprocess):
    <kiosk>/.venv/bin/python reference/scenes.py            # all scenes
    <kiosk>/.venv/bin/python reference/scenes.py label_align # one scene

Only the in-scope API is used (SCOPE.md). Config: multisamples 0 (SDL_Renderer has no
MSAA; see the GAP in PORTING.md), except the *_msaa scene which keeps Kivy's default 2.
"""
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "out"
ASSETS = HERE / "assets"
W, H = 800, 600


def a(name):
    return str(ASSETS / name)


# ---------------------------------------------------------------- helpers used inside scenes
def boxed(r, g, b, **kw):
    """A plain Widget with a coloured rectangle that follows it (as in test_uix_boxlayout)."""
    from kivy.graphics import Color, Rectangle
    from kivy.uix.widget import Widget
    w = Widget(**kw)
    with w.canvas:
        Color(r, g, b)
        rect = Rectangle(pos=w.pos, size=w.size)
    w.bind(pos=lambda i, v: setattr(rect, "pos", v), size=lambda i, v: setattr(rect, "size", v))
    return w


def frame(widget, rgba):
    """Paint widget's bounds in canvas.before (shows where a label or image box is)."""
    from kivy.graphics import Color, Rectangle
    with widget.canvas.before:
        Color(*rgba)
        rect = Rectangle(pos=widget.pos, size=widget.size)
    widget.bind(pos=lambda i, v: setattr(rect, "pos", v), size=lambda i, v: setattr(rect, "size", v))
    return widget


def place(root, child, x, y, w, h):
    child.size_hint = (None, None)
    child.pos = (x, y)
    child.size = (w, h)
    root.add_widget(child)
    return child


# ---------------------------------------------------------------- scenes
def graphics_basic():
    from kivy.graphics import Color, Ellipse, Rectangle, RoundedRectangle, Triangle
    from kivy.uix.widget import Widget
    w = Widget()
    with w.canvas:
        Color(0.8, 0.2, 0.2)
        Rectangle(pos=(20, 420), size=(160, 140))
        Color(0.2, 0.6, 0.2, 0.5)
        Rectangle(pos=(100, 380), size=(160, 140))  # half alpha over the red one
        Color(0.2, 0.3, 0.8)
        RoundedRectangle(pos=(300, 420), size=(200, 140), radius=[30])
        Color(0.9, 0.6, 0.1)
        RoundedRectangle(pos=(540, 420), size=(220, 140), radius=[(10, 10), (60, 30), 0, 40])
        Color(0.5, 0.1, 0.5)
        Ellipse(pos=(20, 220), size=(180, 120))
        Color(0.1, 0.5, 0.5)
        Ellipse(pos=(240, 200), size=(160, 160), angle_start=45, angle_end=300)
        Color(0.3, 0.3, 0.3)
        Ellipse(pos=(440, 200), size=(160, 160), segments=6)
        Color(0.9, 0.2, 0.5)
        Triangle(points=[640, 200, 780, 200, 700, 360])
        Color(0, 0, 0, 1)
        Rectangle(pos=(20, 20), size=(1, 1))  # a single pixel
        Rectangle(pos=(30.5, 20.5), size=(100.4, 40.6))  # fractional geometry
        Color(rgba=(0.2, 0.2, 0.9, 0.25))
        RoundedRectangle(pos=(200, 20), size=(560, 140), radius=[70])
    return w


def graphics_basic_msaa():
    return graphics_basic()


def graphics_line():
    from kivy.graphics import Color, Line
    from kivy.uix.widget import Widget
    w = Widget()
    pts = [0, 0, 60, 70, 120, 0]
    with w.canvas:
        Color(0, 0, 0)
        Line(points=[20, 560, 200, 520, 120, 580], width=1)
        Line(points=[220, 560, 400, 520, 300, 580], width=1, close=True)
        y = 420
        for i, cap in enumerate(("none", "square", "round")):
            Color(0.8, 0.2, 0.2)
            x = 20 + i * 150
            Line(points=[x + p if k % 2 == 0 else y + p for k, p in enumerate(pts)], width=8, cap=cap,
                 joint="none")
        for i, joint in enumerate(("miter", "bevel", "round", "none")):
            Color(0.2, 0.2, 0.8)
            x = 20 + i * 190
            Line(points=[x + p if k % 2 == 0 else 280 + p for k, p in enumerate(pts)], width=10,
                 joint=joint, cap="none")
        Color(0.1, 0.5, 0.1)
        Line(circle=(80, 160, 50), width=1)
        Line(circle=(220, 160, 50), width=4)
        Line(circle=(360, 160, 50, 45, 135), width=3)
        Line(circle=(500, 160, 50, 0, 270, 12), width=2)
        Color(0.4, 0.2, 0.0)
        Line(rectangle=(580, 110, 180, 100), width=1)
        Line(rectangle=(590, 120, 160, 80), width=3)
        Line(rounded_rectangle=(20, 20, 300, 60, 20), width=2)
        Line(rounded_rectangle=(340, 20, 300, 60, 30, 5, 0, 15), width=1.2)
        Color(0.6, 0.0, 0.6)
        Line(points=[660, 20, 780, 80], width=1.5, cap="round")
    return w


def graphics_texture():
    from kivy.graphics import Color, Ellipse, Rectangle, RoundedRectangle
    from kivy.uix.widget import Widget
    w = Widget()
    with w.canvas:
        Color(1, 1, 1, 1)
        Rectangle(source=a("landscape.png"), pos=(20, 380), size=(360, 180))
        Rectangle(source=a("portrait.png"), pos=(420, 340), size=(110, 220))
        Ellipse(source=a("flag.png"), pos=(580, 380), size=(180, 180))
        RoundedRectangle(source=a("landscape.png"), pos=(20, 140), size=(360, 180), radius=[40])
        Color(1, 0.5, 0.5, 1)
        Rectangle(source=a("landscape.jpg"), pos=(420, 140), size=(200, 100))
        Color(1, 1, 1, 0.5)
        Ellipse(source=a("flag.png"), pos=(640, 140), size=(120, 120))
        Color(1, 1, 1, 1)
        Rectangle(source=a("half_alpha.png"), pos=(20, 20), size=(200, 100))
        Rectangle(source=a("small.png"), pos=(260, 20), size=(40, 30))
        Rectangle(source=a("small.png"), pos=(320, 20), size=(160, 100))
    return w


def canvas_order():
    """canvas.before / children / canvas / canvas.after, opacity inheritance, canvas.clear."""
    from kivy.graphics import Color, Rectangle
    from kivy.uix.widget import Widget
    root = Widget()
    parent = Widget(pos=(50, 100), size=(500, 400))
    with parent.canvas.before:
        Color(0.8, 0.8, 0.2)
        Rectangle(pos=(50, 100), size=(500, 400))
    with parent.canvas:
        Color(0.2, 0.2, 0.8)
        Rectangle(pos=(100, 150), size=(300, 300))
    with parent.canvas.after:
        Color(0.8, 0.2, 0.2)
        Rectangle(pos=(150, 200), size=(100, 100))
    child = Widget(pos=(200, 250), size=(300, 150))
    with child.canvas:
        Color(0.2, 0.7, 0.2)
        Rectangle(pos=(200, 250), size=(300, 150))
    parent.add_widget(child)  # drawn above parent.canvas, below parent.canvas.after
    root.add_widget(parent)

    faded = Widget(pos=(580, 100), size=(200, 400), opacity=0.5)
    with faded.canvas:
        Color(0, 0, 0)
        Rectangle(pos=(580, 100), size=(200, 400))
    inner = Widget(opacity=0.5)
    with inner.canvas:
        Color(1, 1, 1)
        Rectangle(pos=(600, 300), size=(160, 160))  # 0.25 effective
    faded.add_widget(inner)
    root.add_widget(faded)

    gone = Widget()
    with gone.canvas:
        Color(1, 0, 1)
        Rectangle(pos=(0, 0), size=(800, 600))
    gone.canvas.clear()  # nothing left to draw
    root.add_widget(gone)

    first = boxed(0.5, 0.5, 0.5, pos=(60, 20), size=(200, 60))
    second = boxed(0.1, 0.1, 0.1, pos=(160, 40), size=(200, 60))
    root.add_widget(first)
    root.add_widget(second)
    root.add_widget(boxed(0.9, 0.5, 0.0, pos=(110, 30), size=(200, 60)), index=2)  # below both
    return root


def boxlayout_tests():
    """The eight layouts of kivy/tests/test_uix_boxlayout.py, each in a 200 x 300 cell."""
    from kivy.uix.boxlayout import BoxLayout
    from kivy.uix.floatlayout import FloatLayout
    root = FloatLayout()
    cases = [{}, {"orientation": "vertical"},
             {"spacing": 20}, {"spacing": 20, "orientation": "vertical"},
             {"padding": 20}, {"padding": 20, "orientation": "vertical"},
             {"spacing": 20, "padding": 20}, {"spacing": 20, "padding": 20, "orientation": "vertical"}]
    for i, kw in enumerate(cases):
        lay = frame(BoxLayout(**kw), (0.85, 0.85, 0.85, 1))
        for c in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
            lay.add_widget(boxed(*c))
        place(root, lay, (i % 4) * 200 + 5, 300 - (i // 4) * 300 + 5, 190, 290)
    return root


def boxlayout_hints():
    """size_hint None, mixed hints, size_hint_min/max, pos_hint inside a box, padding forms."""
    from kivy.uix.boxlayout import BoxLayout
    from kivy.uix.floatlayout import FloatLayout
    root = FloatLayout()

    row = frame(BoxLayout(spacing=10, padding=(10, 20)), (0.85, 0.85, 0.85, 1))
    row.add_widget(boxed(1, 0, 0, size_hint=(None, 1), width=80))
    row.add_widget(boxed(0, 1, 0, size_hint=(0.3, 0.5), pos_hint={"top": 1}))
    row.add_widget(boxed(0, 0, 1, size_hint=(0.7, None), height=40, pos_hint={"center_y": 0.5}))
    row.add_widget(boxed(1, 1, 0, size_hint=(None, None), size=(50, 50), pos_hint={"y": 0}))
    place(root, row, 10, 450, 780, 140)

    bounds = frame(BoxLayout(spacing=5, padding=[5, 10, 15, 20]), (0.85, 0.85, 0.85, 1))
    bounds.add_widget(boxed(1, 0, 0, size_hint_min_x=300))
    bounds.add_widget(boxed(0, 1, 0, size_hint_max_x=60))
    bounds.add_widget(boxed(0, 0, 1, size_hint_x=2))
    place(root, bounds, 10, 300, 780, 130)

    col = frame(BoxLayout(orientation="vertical", spacing=8, padding=12), (0.85, 0.85, 0.85, 1))
    col.add_widget(boxed(1, 0, 0, size_hint=(None, None), size=(100, 30), pos_hint={"center_x": 0.5}))
    col.add_widget(boxed(0, 1, 0, size_hint=(0.5, 0.42), pos_hint={"right": 1}))
    col.add_widget(boxed(0, 0, 1, size_hint=(1, 0.58)))
    col.add_widget(boxed(1, 0, 1, size_hint=(0.3, None), height=20, pos_hint={"x": 0.1}))
    place(root, col, 10, 10, 380, 270)

    squeeze = frame(BoxLayout(spacing=10, padding=10), (0.85, 0.85, 0.85, 1))
    for c in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
        squeeze.add_widget(boxed(*c, size_hint=(None, 1), width=200))  # wider than the box
    place(root, squeeze, 410, 150, 380, 130)

    nested = frame(BoxLayout(orientation="vertical", spacing=4), (0.85, 0.85, 0.85, 1))
    inner = BoxLayout(spacing=4)
    inner.add_widget(boxed(0.5, 0, 0))
    inner.add_widget(boxed(0, 0.5, 0, size_hint_x=0.0001))  # the kiosk's "hidden photo" trick
    nested.add_widget(inner)
    nested.add_widget(boxed(0, 0, 0.5, size_hint_y=0.5))
    place(root, nested, 410, 10, 380, 130)
    return root


def floatlayout_hints():
    from kivy.uix.floatlayout import FloatLayout
    root = FloatLayout()
    inner = frame(FloatLayout(size_hint=(0.9, 0.9), pos_hint={"center_x": 0.5, "center_y": 0.5}),
                  (0.85, 0.85, 0.85, 1))
    inner.add_widget(boxed(1, 0, 0, size_hint=(0.2, 0.2), pos_hint={"x": 0, "y": 0}))
    inner.add_widget(boxed(0, 1, 0, size_hint=(0.2, 0.2), pos_hint={"right": 1, "top": 1}))
    inner.add_widget(boxed(0, 0, 1, size_hint=(0.3, 0.1), pos_hint={"center_x": 0.5, "center_y": 0.5}))
    inner.add_widget(boxed(1, 1, 0, size_hint=(None, None), size=(60, 60), pos_hint={"x": 0.5, "top": 0.9}))
    inner.add_widget(boxed(0, 1, 1, size_hint=(None, None), size=(80, 40), pos=(30, 300)))  # no pos_hint
    inner.add_widget(boxed(1, 0, 1, size_hint=(0.05, 0.05), size_hint_min=(100, 50),
                           pos_hint={"right": 0.95, "y": 0.05}))
    inner.add_widget(boxed(0.5, 0.5, 0, size_hint=(0.9, 0.3), size_hint_max_x=150,
                           pos_hint={"center_x": 0.25, "top": 0.8}))
    root.add_widget(inner)
    return root


def anchorlayout_tests():
    """The layouts of kivy/tests/test_uix_anchorlayout.py, one per cell."""
    from kivy.uix.anchorlayout import AnchorLayout
    from kivy.uix.floatlayout import FloatLayout
    root = FloatLayout()
    i = 0
    for ax in ("left", "center", "right"):
        for ay in ("top", "center", "bottom"):
            lay = frame(AnchorLayout(anchor_x=ax, anchor_y=ay, padding=10), (0.85, 0.85, 0.85, 1))
            lay.add_widget(boxed(1, 0, 0, size_hint=(None, None), size=(60, 40)))
            place(root, lay, (i % 3) * 265 + 5, 400 - (i // 3) * 200 + 5, 255, 190)
            i += 1
    return root


LOREM = ("Figs have been grown in Greece for thousands of years. The fruit is dried in the sun, "
         "pressed by hand and packed the same day.")


def label_align():
    """Every halign x valign with text_size set to the label's size."""
    from kivy.uix.floatlayout import FloatLayout
    from kivy.uix.label import Label
    root = FloatLayout()
    for i, ha in enumerate(("left", "center", "right", "justify")):
        for j, va in enumerate(("top", "middle", "bottom")):
            lb = frame(Label(text=LOREM, color=(0, 0, 0, 1), font_size=13, halign=ha, valign=va),
                       (0.85, 0.9, 0.95, 1))
            lb.bind(size=lambda w, v: setattr(w, "text_size", v))
            place(root, lb, i * 200 + 5, 400 - j * 200 + 5, 190, 190)
    return root


def label_wrap():
    """The kiosk's two label patterns, line_height, bold, a registered font, padding, colour."""
    from kivy.core.text import LabelBase
    from kivy.resources import resource_find
    from kivy.uix.boxlayout import BoxLayout
    from kivy.uix.label import Label
    from kivy.uix.widget import Widget
    LabelBase.register("Deja", resource_find("data/fonts/DejaVuSans.ttf"),
                       fn_bold=resource_find("data/fonts/Roboto-Bold.ttf"))
    root = BoxLayout(orientation="vertical", padding=10, spacing=6)
    frame(root, (0.98, 0.96, 0.94, 1))
    for lh in (1.0, 1.25, 0.8):
        lb = frame(Label(text=f"line_height {lh}: " + LOREM, color=(0.2, 0.2, 0.2, 1), font_size=18,
                         line_height=lh, halign="left", size_hint_y=None), (0.9, 0.85, 0.8, 1))
        # fit=True in the kiosk: as tall as its wrapped text
        lb.bind(width=lambda w, v: setattr(w, "text_size", (v, None)),
                texture_size=lambda w, v: setattr(w, "height", v[1]))
        root.add_widget(lb)
    root.add_widget(frame(Label(text="Deja regular, size 24", font_name="Deja", font_size=24,
                                color=(0.29, 0.18, 0.16, 1), size_hint_y=None, height=36), (0.9, 0.9, 0.8, 1)))
    root.add_widget(frame(Label(text="Deja bold (Roboto-Bold file), size 24", font_name="Deja", bold=True,
                                font_size=24, color=(0.29, 0.18, 0.16, 1), size_hint_y=None, height=36),
                          (0.9, 0.9, 0.8, 1)))
    root.add_widget(frame(Label(text="Roboto bold 20, padding 30 x 4, halign right", bold=True, font_size=20,
                                padding=(30, 4), halign="right", color=(0.42, 0.55, 0.27, 1),
                                size_hint_y=None, height=40), (0.9, 0.9, 0.8, 1)))
    lb = Label(text="fill: size bound to text_size, valign middle", font_size=20, color=(0, 0, 0, 1),
               halign="center", valign="middle")
    lb.bind(size=lambda w, v: setattr(w, "text_size", v))
    root.add_widget(frame(lb, (0.8, 0.9, 0.8, 1)))
    root.add_widget(Widget(size_hint_y=0.2))
    return root


def label_default():
    """Labels without text_size: one line, explicit newlines, defaults, disabled colour, empty text."""
    from kivy.uix.floatlayout import FloatLayout
    from kivy.uix.label import Label
    root = FloatLayout()
    place(root, frame(Label(text="Default label (Roboto 15sp, white)"), (0.3, 0.3, 0.3, 1)), 20, 500, 360, 60)
    place(root, frame(Label(text="first line\nsecond, longer line\nthird", color=(0, 0, 0, 1),
                            font_size=22), (0.85, 0.85, 0.85, 1)), 420, 440, 360, 140)
    place(root, frame(Label(text="Too long for the widget, so it overflows both sides", color=(0, 0, 0, 1),
                            font_size=20), (0.85, 0.85, 0.85, 1)), 250, 360, 300, 40)
    place(root, frame(Label(text="disabled label", disabled=True, font_size=28), (0.2, 0.2, 0.2, 1)),
          20, 260, 360, 60)
    place(root, frame(Label(text="", color=(0, 0, 0, 1)), (0.85, 0.85, 0.85, 1)), 420, 260, 360, 60)
    place(root, frame(Label(text="Ελληνικά — ünïcödé ½ €", color=(0, 0, 0, 1), font_size=26),
                      (0.85, 0.85, 0.85, 1)), 20, 160, 760, 60)
    place(root, frame(Label(text="tiny 9", color=(0, 0, 0, 1), font_size=9), (0.85, 0.85, 0.85, 1)),
          20, 60, 120, 40)
    place(root, frame(Label(text="huge 64", color=(0, 0, 0, 1), font_size=64), (0.85, 0.85, 0.85, 1)),
          200, 40, 400, 100)
    return root


def image_fit():
    """The four fit modes for a wide, a tall and a small image, in a box of fixed shape."""
    from kivy.uix.floatlayout import FloatLayout
    from kivy.uix.image import Image
    root = FloatLayout()
    for i, mode in enumerate(("scale-down", "fill", "contain", "cover")):
        for j, src in enumerate(("landscape.png", "portrait.png", "small.png")):
            img = frame(Image(source=a(src), fit_mode=mode), (0.8, 0.8, 0.8, 1))
            place(root, img, i * 200 + 10, 400 - j * 200 + 10, 180, 150)
    return root


def image_misc():
    """Image colour tint, opacity, a JPEG, source changed after creation, no source."""
    from kivy.uix.floatlayout import FloatLayout
    from kivy.uix.image import Image
    root = FloatLayout()
    place(root, frame(Image(source=a("landscape.png"), color=(1, 0.5, 0.5, 1), fit_mode="contain"),
                      (0.8, 0.8, 0.8, 1)), 10, 310, 380, 280)
    place(root, frame(Image(source=a("landscape.png"), opacity=0.4, fit_mode="contain"),
                      (0.8, 0.8, 0.8, 1)), 410, 310, 380, 280)
    changed = Image(source=a("portrait.png"), fit_mode="cover")
    changed.source = a("landscape.jpg")
    place(root, frame(changed, (0.8, 0.8, 0.8, 1)), 10, 10, 380, 280)
    place(root, frame(Image(), (0.8, 0.8, 0.8, 1)), 410, 10, 380, 280)  # no source: white box
    return root


def screen_relative():
    """A Screen (RelativeLayout) inside a ScreenManager placed off the origin: children are local."""
    from kivy.uix.boxlayout import BoxLayout
    from kivy.uix.floatlayout import FloatLayout
    from kivy.uix.screenmanager import Screen, ScreenManager
    root = FloatLayout()
    sm = ScreenManager(size_hint=(None, None), size=(500, 400), pos=(200, 100))
    s = Screen(name="one")
    s.add_widget(boxed(0.9, 0.9, 0.7))
    box = BoxLayout(padding=20, spacing=20)
    box.add_widget(boxed(1, 0, 0))
    box.add_widget(boxed(0, 0, 1, size_hint_y=0.5))
    s.add_widget(box)
    s.add_widget(boxed(0, 0.6, 0, size_hint=(None, None), size=(50, 50), pos=(0, 0)))  # local (0, 0)
    s.add_widget(boxed(0.5, 0, 0.5, size_hint=(None, None), size=(80, 80), pos=(450, 350)))  # clipped
    sm.add_widget(s)
    root.add_widget(sm)
    return root


def fade_half():
    """FadeTransition frozen at progress 0.5 between a red and a blue screen."""
    from kivy.uix.screenmanager import FadeTransition, Screen, ScreenManager
    sm = ScreenManager(transition=FadeTransition(duration=10))
    one, two = Screen(name="one"), Screen(name="two")
    one.add_widget(boxed(0.9, 0.2, 0.2))
    one.add_widget(boxed(1, 1, 1, size_hint=(0.4, 0.4), pos_hint={"x": 0.1, "y": 0.1}))
    two.add_widget(boxed(0.2, 0.2, 0.9, size_hint=(0.6, 0.6), pos_hint={"right": 0.9, "top": 0.9}))
    sm.add_widget(one)
    sm.add_widget(two)

    def freeze(*_):
        sm.current = "two"
        tr = sm.transition
        tr._anim.cancel(tr)  # stop the clock-driven progress: deterministic picture
        tr._on_progress(tr, tr, 0.5)

    from kivy.clock import Clock
    Clock.schedule_once(freeze, 0.2)
    return sm


def modal_custom():
    """The kiosk's picker style: transparent background, coloured overlay, painted panel."""
    from kivy.uix.boxlayout import BoxLayout
    from kivy.uix.label import Label
    from kivy.uix.modalview import ModalView
    from kivy.uix.widget import Widget
    from kivy.clock import Clock
    root = Widget()
    root.add_widget(boxed(0.2, 0.6, 0.3, pos=(0, 0), size=(800, 600)))
    mv = ModalView(size_hint=(None, None), size=(420, 260), auto_dismiss=True, background="",
                   background_color=(0, 0, 0, 0), overlay_color=(0.29, 0.18, 0.16, 0.45))
    panel = frame(BoxLayout(orientation="vertical", padding=20, spacing=10), (0.98, 0.96, 0.94, 1))
    panel.add_widget(Label(text="Choose language", color=(0.29, 0.18, 0.16, 1), font_size=24, bold=True))
    panel.add_widget(boxed(0.74, 0.65, 0.44))
    mv.add_widget(panel)
    Clock.schedule_once(lambda *_: mv.open(animation=False), 0.2)
    return root


def modal_default():
    """ModalView with Kivy's defaults (atlas background, overlay 0, 0, 0, .7)."""
    from kivy.uix.label import Label
    from kivy.uix.modalview import ModalView
    from kivy.uix.widget import Widget
    from kivy.clock import Clock
    root = Widget()
    root.add_widget(boxed(0.9, 0.9, 0.9, pos=(0, 0), size=(800, 600)))
    mv = ModalView(size_hint=(0.5, 0.4))
    mv.add_widget(Label(text="default ModalView"))
    Clock.schedule_once(lambda *_: mv.open(animation=False), 0.2)
    return root


SCENES = {f.__name__: f for f in (
    graphics_basic, graphics_basic_msaa, graphics_line, graphics_texture, canvas_order,
    boxlayout_tests, boxlayout_hints, floatlayout_hints, anchorlayout_tests,
    label_align, label_wrap, label_default, image_fit, image_misc,
    screen_relative, fade_half, modal_custom, modal_default)}


# ---------------------------------------------------------------- runner
def fmt(v):
    return "(" + ", ".join(f"{float(x):.3f}" for x in v) + ")"


def shoot(name):
    """Render one scene in this process, save out/<name>.png and quit."""
    os.environ["KIVY_NO_ARGS"] = "1"
    from kivy.config import Config
    Config.set("graphics", "width", str(W))
    Config.set("graphics", "height", str(H))
    Config.set("graphics", "resizable", "0")
    Config.set("graphics", "multisamples", "2" if name.endswith("_msaa") else "0")
    Config.set("input", "mouse", "mouse,multitouch_on_demand")
    from kivy.app import App
    from kivy.clock import Clock
    from kivy.core.window import Window

    def save(app):
        assert tuple(Window.size) == (W, H), Window.size
        target = OUT / f"{name}.png"
        if target.exists():
            target.unlink()
        path = Window.screenshot(name=str(OUT / f"{name}.png"))  # Kivy writes <name>0001.png
        os.replace(path, target)
        # The geometry of every widget, for exact layout comparison (pixels can differ a little).
        lines = []
        for w in Window.children[:]:
            for wid in w.walk():
                line = f"{type(wid).__name__} pos={fmt(wid.pos)} size={fmt(wid.size)}"
                if hasattr(wid, "texture_size"):
                    line += f" texture_size={fmt(wid.texture_size)}"
                if hasattr(wid, "norm_image_size"):
                    line += f" norm_image_size={fmt(wid.norm_image_size)}"
                lines.append(line)
        (OUT / f"{name}.txt").write_text("\n".join(lines) + "\n")
        app.stop()

    class SceneApp(App):
        title = name

        def build(self):
            Window.clearcolor = (1, 1, 1, 1)
            Clock.schedule_once(lambda *_: save(self), 1.0)
            return SCENES[name]()

    SceneApp().run()


def main():
    OUT.mkdir(exist_ok=True)
    names = sys.argv[1:] or list(SCENES)
    if len(names) == 1:
        shoot(names[0])
        return
    for n in names:
        subprocess.run([sys.executable, __file__, n], check=True)


if __name__ == "__main__":
    main()
