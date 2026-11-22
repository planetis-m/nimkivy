"""Geometry that real Kivy 2.3.2 computes for vertex instructions, for tests/tvertex_instructions.

Kivy's instructions need a GL context, so they are built inside an App, drawn for one frame,
and then read: Rectangle, Ellipse and RoundedRectangle `points`, RoundedRectangle `radius` and
`segments`, Triangle `points`, and Line `points` with the normalised `circle`, `rectangle` and
`rounded_rectangle` tuples. Writes reference/out/graphics_points.txt, one value per case:

    <case> <attribute> <number> <number> ...

Numbers are Python's repr of the float, so nimkivy can compare them to the last bit. Pairs
(RoundedRectangle points and radius) are flattened. A None attribute is written as `None`.

Then the children of a Canvas after add, insert, before, after, remove and clear, by class
name (`canvas <step> <Class> ...`), for tests/tinstructions.

Run from nimkivy/:
    <kiosk>/.venv/bin/python reference/graphics_points.py
"""
import os
from pathlib import Path

os.environ["KIVY_NO_ARGS"] = "1"
from kivy.config import Config  # noqa: E402

Config.set("graphics", "width", "800")
Config.set("graphics", "height", "600")
Config.set("graphics", "resizable", "0")
Config.set("graphics", "multisamples", "0")

OUT = Path(__file__).resolve().parent / "out" / "graphics_points.txt"


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


def cases():
    """(case, instruction, attributes to print). The same cases are in tests/tvertex_instructions."""
    from kivy.graphics import Ellipse, Line, Rectangle, RoundedRectangle, Triangle
    return [
        ("rect_fraction", Rectangle(pos=(30.5, 20.5), size=(100.4, 40.6)), ["points"]),
        ("rect_default", Rectangle(), ["points"]),
        ("ellipse_full", Ellipse(pos=(20, 220), size=(180, 120)), ["points"]),
        ("ellipse_arc", Ellipse(pos=(240, 200), size=(160, 160), angle_start=45, angle_end=300),
         ["points"]),
        ("ellipse_6", Ellipse(pos=(440, 200), size=(160, 160), segments=6), ["points"]),
        ("ellipse_reverse", Ellipse(pos=(10, 10), size=(50, 30), angle_start=300, angle_end=45),
         ["points"]),
        ("ellipse_2_segments", Ellipse(pos=(10, 10), size=(50, 30), segments=2), ["points"]),
        ("ellipse_zero", Ellipse(pos=(10, 10), size=(0, 30)), ["points"]),
        ("rrect_30", RoundedRectangle(pos=(300, 420), size=(200, 140), radius=[30]),
         ["points", "radius", "segments"]),
        ("rrect_mixed", RoundedRectangle(pos=(540, 420), size=(220, 140),
                                         radius=[(10, 10), (60, 30), (0, 0), (40, 40)]),
         ["points", "radius"]),
        ("rrect_clamped", RoundedRectangle(pos=(5, 6), size=(100, 60), radius=[200],
                                           segments=[3, 0, 5, 2]), ["points", "radius", "segments"]),
        ("rrect_no_segments", RoundedRectangle(pos=(5, 6), size=(100, 60), radius=[20], segments=0),
         ["points"]),
        ("rrect_five_radii", RoundedRectangle(pos=(0, 0), size=(80, 80), radius=[1, 2, 3, 4, 5]),
         ["radius"]),
        ("rrect_two_radii", RoundedRectangle(pos=(0, 0), size=(80, 80), radius=[5, 6]), ["radius"]),
        ("rrect_default", RoundedRectangle(pos=(200, 20), size=(560, 140)), ["points", "radius"]),
        ("triangle", Triangle(points=[640, 200, 780, 200, 700, 360]), ["points"]),
        ("triangle_default", Triangle(), ["points"]),
        ("line_circle", Line(circle=(80, 160, 50)), ["points", "circle"]),
        ("line_circle_arc", Line(circle=(360, 160, 50, 45, 135), width=3), ["points", "circle"]),
        ("line_circle_segments", Line(circle=(500, 160, 50, 0, 270, 12), width=2),
         ["points", "circle"]),
        ("line_circle_reverse", Line(circle=(0, 0, 10, 90, 0)), ["points", "circle"]),
        ("line_rectangle", Line(rectangle=(580, 110, 180, 100)), ["points", "rectangle", "close"]),
        ("line_rrect", Line(rounded_rectangle=(20, 20, 300, 60, 20), width=2),
         ["points", "rounded_rectangle", "close"]),
        ("line_rrect_four", Line(rounded_rectangle=(340, 20, 300, 60, 30, 5, 0, 15), width=1.2),
         ["points", "rounded_rectangle"]),
        ("line_rrect_resolution", Line(rounded_rectangle=(0, 0, 50, 40, 8, 3)),
         ["points", "rounded_rectangle"]),
        ("line_rrect_empty", Line(rounded_rectangle=(0, 0, 0, 40, 8)),
         ["points", "rounded_rectangle"]),
        ("line_points", Line(points=[20, 560, 200, 520, 120, 580]), ["points", "width", "close"]),
        ("line_default", Line(), ["points", "width"]),
    ]


def canvas_steps():
    """The children of a canvas after each step, as class names."""
    from kivy.graphics import Canvas, Color, Ellipse, Rectangle, Triangle
    out = []
    c = Canvas()

    def log(step):
        out.append(f"canvas {step} " + " ".join(type(x).__name__ for x in c.children))

    c.add(Color(1, 0, 0))
    rect = Rectangle()
    c.add(rect)
    log("add")
    c.before.add(Color())
    log("before")
    c.after.add(Color())
    log("after")
    c.add(Ellipse())
    log("add_with_after")
    c.insert(1, Triangle())
    log("insert_1")
    c.insert(-1, Triangle())
    log("insert_minus_1")
    c.remove(rect)
    log("remove")
    out.append(f"canvas indexof_before {c.indexof(c.before)} after {c.indexof(c.after)} "
               f"length {c.length()}")
    c.clear()
    log("clear")
    g = Canvas()
    g.add(Rectangle())
    g.clear()
    out.append(f"canvas clear_plain {len(g.children)}")
    return out


def main():
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
                text = "None" if v is None else " ".join(repr(x) for x in v)
                lines.append(f"{case} {attr} {text}".rstrip())
        lines.extend(canvas_steps())
        OUT.write_text("\n".join(lines) + "\n")
        app.stop()

    class PointsApp(App):
        def build(self):
            w = Widget()
            with w.canvas:
                built.extend(cases())
            Clock.schedule_once(lambda *_: save(self), 0.5)
            return w

    PointsApp().run()


if __name__ == "__main__":
    main()
