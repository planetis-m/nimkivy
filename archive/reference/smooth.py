"""Kivy 2.3.2's smooth instructions, for nimkivy's tests (P2.12).

Two outputs, in the Nim format of tests/fixtures (archive/README.md):

    python smooth.py points   -> tests/fixtures/smooth_points.txt
    python smooth.py scene    -> tests/fixtures/scenes/graphics_smooth.png and .txt

`points`: SmoothRectangle, SmoothRoundedRectangle, SmoothEllipse, SmoothTriangle,
SmoothQuad, AntiAliasingLine and SmoothLine, built by drawing one frame, then read:
`points`, `antialiasing_line_points`, and the `pos`, `size` and `radius` the build
leaves behind (adjust_params moves them by one pixel and back, through C floats).
One line per value: `<case> <attribute> <number> ...`, Python's repr of each
float, `none` for None. tests/tvertex_instructions.nim compares them.

`scene`: the scene graphics_smooth, as archive/reference/scenes.py renders its
scenes (800 x 600, clearcolor white, multisamples 0, a screenshot after one
second, every widget's pos and size). tests/scenes.nim renders the same tree.

Run from the nimkivy root, with Kivy 2.3.2 (the wheel bundles SDL2), e.g. in a
throwaway environment outside the repository:
    uv venv --python 3.12 ~/.cache/kivy232-venv
    VIRTUAL_ENV=~/.cache/kivy232-venv uv pip install kivy==2.3.2
    ~/.cache/kivy232-venv/bin/python -I archive/reference/smooth.py points
    ~/.cache/kivy232-venv/bin/python -I archive/reference/smooth.py scene
"""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
FIXTURES = ROOT / "tests" / "fixtures"
W, H = 800, 600


def configure():
    os.environ["KIVY_NO_ARGS"] = "1"
    from kivy.config import Config
    Config.set("graphics", "width", str(W))
    Config.set("graphics", "height", str(H))
    Config.set("graphics", "resizable", "0")
    Config.set("graphics", "multisamples", "0")
    Config.set("input", "mouse", "mouse,multitouch_on_demand")


# ---------------------------------------------------------------- points
def flat(v):
    if v is None:
        return None
    out = []
    for x in v:
        if isinstance(x, (list, tuple)):
            out.extend(flat(x))
        else:
            out.append(float(x))
    return out


POINTS_3 = [  # test_graphics.py test_antialiasing_line, points_3
    260.0, 275.0, 261.0, 275.0, 261.0, 275.0, 261.999999999999, 275.99999999,
    261.06667650085353, 278.14064903651496, 261.26658584785304, 281.2756384111877,
    261.56658584785305, 281.3756384111877, 261.5993677908431, 284.39931866126904,
    262.0644226342696, 287.50606070381684, 262.0644226342696, 287.50606070381684,
    262.6609123178712, 290.59026597968375, 263.3877619269211, 293.6463765424993,
    264.2436616292954, 296.66888507446475, 265.22706903587977, 299.65234481091227,
    265.22706903587977, 299.65234481091227, 266.3362119800583, 302.59137935574284,
    267.5690917112779, 305.48069237005546, 268.9234864969319, 308.31507711650784,
    270.39695562607204, 311.089425842209, 270.89695562607204, 311.589425842209,
    271.98684380773494, 313.7987389832352, 273.69028595595563, 316.4381341741821,
    275.50421235284637, 319.00285504651725, 275.50421235284637, 319.00285504651725,
    277.4253541804354, 321.48827979987755, 279.45024941129833, 323.8899295308661,
    281.57524904736516, 326.20347630433844, 283.79652369566156, 328.4247509526349,
    283.99652369566156, 328.7247509526349, 286.1100704691339, 330.54975058870167,
    288.5117202001224, 332.5746458195646, 288.5117202001224, 332.5746458195646,
    290.99714495348275, 334.4957876471537, 293.5618658258179, 336.3097140440444,
    293.5618658258179, 336.3097140440444, 293.2618658258179, 336.1097140440444]


def cases():
    """(case, instruction, attributes). tests/tvertex_instructions.nim builds the same."""
    from kivy.graphics import (Instruction, SmoothEllipse, SmoothLine, SmoothQuad,
                               SmoothRectangle, SmoothRoundedRectangle, SmoothTriangle)
    from kivy.graphics.vertex_instructions import AntiAliasingLine
    shape = ["points", "antialiasing_line_points", "pos", "size"]
    return [
        ("srect", SmoothRectangle(pos=(100, 100), size=(150, 150)), shape),
        ("srect_fraction", SmoothRectangle(pos=(30.5, 20.5), size=(100.4, 40.6)), shape),
        ("srect_drift", SmoothRectangle(pos=(127.1, 50), size=(60.3, 30)), shape),
        ("srect_negative", SmoothRectangle(pos=(300, 200), size=(-50, 40)), shape),
        ("srect_small", SmoothRectangle(pos=(10, 10), size=(3.99, 3.99)), shape),
        ("srrect_test", SmoothRoundedRectangle(
            pos=(100, 100), size=(150, 150),
            radius=[(10, 50), (100, 50), (0, 150), (200, 50)], segments=60),
         shape + ["radius"]),
        ("srrect_mixed", SmoothRoundedRectangle(
            pos=(540, 420), size=(220, 140), radius=[(10, 10), (60, 30), 0, 40]),
         shape + ["radius"]),
        ("srrect_no_segments", SmoothRoundedRectangle(pos=(100, 100), size=(150, 150), segments=0),
         shape + ["radius"]),
        ("sellipse", SmoothEllipse(pos=(100, 100), size=(150, 150)), shape),
        ("sellipse_arc", SmoothEllipse(pos=(100, 100), size=(150, 150), angle_start=90,
                                       angle_end=-120), shape),
        ("sellipse_6", SmoothEllipse(pos=(440, 200), size=(160, 120), segments=6), shape),
        ("stri", SmoothTriangle(points=[100, 100, 200, 100, 150, 200, 500, 500, 400, 400]),
         ["points", "antialiasing_line_points"]),
        ("stri_reverse", SmoothTriangle(points=[125, 200, 200, 100, 100, 100]),
         ["points", "antialiasing_line_points"]),
        ("stri_tiny", SmoothTriangle(points=[100, 100, 100.5, 100, 100, 100.5]),
         ["points", "antialiasing_line_points"]),
        ("squad", SmoothQuad(points=[100, 100, 100, 200, 200, 200, 200, 100]),
         ["points", "antialiasing_line_points"]),
        ("squad_tiny", SmoothQuad(points=[200, 100, 200, 100.8, 100, 100.8, 100, 100]),
         ["points", "antialiasing_line_points"]),
        ("aaline_closed", AntiAliasingLine(Instruction(), points=POINTS_3), ["points", "width"]),
        ("aaline_open", AntiAliasingLine(Instruction(), points=POINTS_3, close=0), ["points"]),
        ("aaline_two", AntiAliasingLine(Instruction(), points=[100, 100, 200, 100]), ["points"]),
        ("sline_points", SmoothLine(points=[20, 560, 200, 520, 200.05, 520.05, 120, 580], width=2),
         ["points", "overdraw_width"]),
        ("sline_circle", SmoothLine(circle=(400, 300, 50), width=1.5), ["points", "circle"]),
        ("sline_rrect", SmoothLine(rounded_rectangle=(20, 20, 300, 60, 20), width=2),
         ["points", "rounded_rectangle"]),
        ("sline_rrect_thin", SmoothLine(rounded_rectangle=(100, 100, 0.5, 1.99, 30, 30, 30, 30, 100)),
         ["points", "rounded_rectangle"]),
        ("sline_rectangle", SmoothLine(rectangle=(580, 110, 180, 100), width=3),
         ["points", "rectangle"]),
    ]


def points():
    configure()
    from kivy.app import App
    from kivy.clock import Clock
    from kivy.uix.widget import Widget

    built = []

    def save(app):
        lines = []
        for case, instr, attrs in built:
            for attr in attrs:
                v = getattr(instr, attr)
                if isinstance(v, (bool, int, float)):
                    v = [v]
                v = flat(v)
                text = "none" if v is None else " ".join(repr(x) for x in v)
                # Kivy's snake_case attribute names in Nim's camelCase.
                name = attr.split("_")
                name = name[0] + "".join(p.capitalize() for p in name[1:])
                lines.append(f"{case} {name} {text}".rstrip())
        (FIXTURES / "smooth_points.txt").write_text("\n".join(lines) + "\n")
        app.stop()

    class PointsApp(App):
        def build(self):
            w = Widget()
            with w.canvas:
                built.extend(cases())
            Clock.schedule_once(lambda *_: save(self), 0.5)
            return w

    PointsApp().run()


# ---------------------------------------------------------------- scene
def graphics_smooth():
    from kivy.graphics import (Color, Rectangle, SmoothEllipse, SmoothLine, SmoothQuad,
                               SmoothRectangle, SmoothRoundedRectangle, SmoothTriangle)
    from kivy.uix.widget import Widget
    w = Widget()
    with w.canvas:
        Color(0.2, 0.3, 0.8)
        SmoothRoundedRectangle(pos=(20, 440), size=(200, 140), radius=[30])
        Color(0.9, 0.6, 0.1)
        SmoothRoundedRectangle(pos=(240, 440), size=(220, 140), radius=[(10, 10), (60, 30), 0, 40])
        Color(0.5, 0.1, 0.5)
        SmoothEllipse(pos=(480, 450), size=(180, 120))
        Color(0.1, 0.5, 0.5)
        SmoothEllipse(pos=(675, 460), size=(110, 110), angle_start=45, angle_end=300)
        Color(0.8, 0.2, 0.2)
        SmoothRectangle(pos=(20.5, 300.25), size=(150.4, 90.6))
        Color(0.9, 0.2, 0.5)
        SmoothTriangle(points=[200, 300, 330, 315, 255, 410])
        Color(0.3, 0.6, 0.2)
        SmoothQuad(points=[360, 300, 480, 322, 470, 410, 350, 385])
        Color(0.3, 0.3, 0.3)
        SmoothEllipse(pos=(510, 300), size=(110, 110), segments=7)
        # Half alpha over a dark band: the antialiasing line goes through
        # Kivy's stencil (only outside the shape).
        Color(0.15, 0.15, 0.15)
        Rectangle(pos=(640, 280), size=(150, 150))
        Color(0.9, 0.9, 0.2, 0.5)
        SmoothEllipse(pos=(650, 300), size=(120, 100))
        Color(0.2, 0.8, 0.9, 0.5)
        SmoothRoundedRectangle(pos=(700, 360), size=(80, 60), radius=[20])
        # SmoothLine: an open polyline, closed, circles, an arc, rectangles.
        Color(0, 0, 0)
        SmoothLine(points=[20, 260, 120, 200, 200, 270, 260, 190], width=1)
        Color(0.1, 0.4, 0.1)
        SmoothLine(points=[280, 260, 380, 200, 440, 270, 330, 280], width=3, close=True)
        Color(0.6, 0, 0.6)
        SmoothLine(circle=(520, 230, 45), width=2)
        SmoothLine(circle=(640, 230, 45, 30, 270), width=1.5)
        Color(0.4, 0.2, 0)
        SmoothLine(rectangle=(700, 190, 80, 80), width=4)
        Color(0.2, 0.2, 0.7)
        SmoothLine(rounded_rectangle=(20, 30, 300, 120, 30), width=2)
        SmoothLine(rounded_rectangle=(340, 30, 200, 120, 40, 5, 1, 20), width=1.2)
        Color(0.8, 0.3, 0.1, 0.5)
        SmoothLine(points=[560, 40, 780, 140], width=6)
        Color(0, 0, 0)
        SmoothLine(points=[560, 140, 780, 40], width=1, overdraw_width=2.5)
    return w


def scene():
    configure()
    from kivy.app import App
    from kivy.clock import Clock
    from kivy.core.window import Window
    name = "graphics_smooth"
    out = FIXTURES / "scenes"

    def fmt(v):
        return "(" + ", ".join(f"{float(x):.3f}" for x in v) + ")"

    def save(app):
        assert tuple(Window.size) == (W, H), Window.size
        target = out / f"{name}.png"
        if target.exists():
            target.unlink()
        path = Window.screenshot(name=str(target))  # Kivy numbers the file
        os.replace(path, target)
        lines = []
        for top in Window.children[:]:
            for wid in top.walk():
                lines.append(f"{type(wid).__name__} pos={fmt(wid.pos)} size={fmt(wid.size)}")
        (out / f"{name}.txt").write_text("\n".join(lines) + "\n")
        app.stop()

    class SceneApp(App):
        title = name

        def build(self):
            Window.clearcolor = (1, 1, 1, 1)
            Clock.schedule_once(lambda *_: save(self), 1.0)
            return graphics_smooth()

    SceneApp().run()


if __name__ == "__main__":
    {"points": points, "scene": scene}[sys.argv[1]]()
