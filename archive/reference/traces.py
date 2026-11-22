"""Behaviour traces from real Kivy 2.3.2: the order of property and event callbacks, Clock
ordering, touch dispatch and grab, ScreenManager and ModalView lifecycles, Animation events,
Label texture sizes. nimkivy's tests replay the same steps and must print the same lines.

Run from nimkivy/:
    <kiosk>/.venv/bin/python reference/traces.py      # writes reference/out/traces/<name>.txt
"""
import os
from pathlib import Path

os.environ["KIVY_NO_ARGS"] = "1"
from kivy.config import Config  # noqa: E402

Config.set("graphics", "width", "800")
Config.set("graphics", "height", "600")
Config.set("graphics", "resizable", "0")
Config.set("graphics", "multisamples", "0")
Config.set("input", "mouse", "mouse,multitouch_on_demand")

OUT = Path(__file__).resolve().parent / "out" / "traces"
LOG = []


def log(*parts):
    LOG.append(" ".join(str(p) for p in parts))


def r(v):
    """Numbers printed the same way in Python and Nim: 3 decimals."""
    if isinstance(v, (list, tuple)) or type(v).__name__ == "ObservableReferenceList":
        return "(" + ", ".join(r(x) for x in v) + ")"
    if isinstance(v, bool) or v is None or isinstance(v, str):
        return str(v)
    return f"{float(v):.3f}"


def save(name):
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / f"{name}.txt").write_text("\n".join(LOG) + "\n")
    LOG.clear()


def make_touch(x, y):
    """A touch posted straight into the event loop, as kivy/tests/common.py UnitTestTouch does
    (copied: that module imports pytest, which the kiosk venv does not have)."""
    from kivy.base import EventLoop
    from kivy.input.motionevent import MotionEvent

    class Touch(MotionEvent):
        def depack(self, args):
            self.sx, self.sy = args["x"], args["y"]
            super().depack(args)

        def touch_down(self):
            EventLoop.post_dispatch_input("begin", self)

        def touch_move(self, x, y):
            win = EventLoop.window
            self.move({"x": x / (win.width - 1.0), "y": y / (win.height - 1.0)})
            EventLoop.post_dispatch_input("update", self)

        def touch_up(self):
            EventLoop.post_dispatch_input("end", self)

    win = EventLoop.window
    t = Touch("UnitTestTouch", 99, {"x": x / (win.width - 1.0), "y": y / (win.height - 1.0)},
              is_touch=True, type_id="touch")
    t.profile = ["pos"]
    return t


# ---------------------------------------------------------------- headless traces
def trace_properties():
    from kivy.uix.boxlayout import BoxLayout
    from kivy.uix.widget import Widget
    w = Widget()
    for name in ("x", "y", "pos", "right", "top", "center", "width", "size"):
        w.bind(**{name: (lambda n: lambda i, v: log(n, r(v)))(name)})
    log("# pos = (1, 2)")
    w.pos = (1, 2)
    log("# pos = (1, 2) again")
    w.pos = (1, 2)
    log("# x = 5")
    w.x = 5
    log("# size = (50, 60)")
    w.size = (50, 60)
    log("# right = 300")
    w.right = 300
    log("# center = (0, 0)")
    w.center = (0, 0)
    w.bind(x=lambda i, v: log("x second observer", r(v)))
    log("# x = 6")
    w.x = 6
    b = BoxLayout()
    for p in (5, (10, 20), (1, 2, 3, 4), [7]):
        b.padding = p
        log("padding", repr(p), "->", r(b.padding))
    log("defaults size", r(Widget().size), "size_hint", r(Widget().size_hint), "pos_hint", Widget().pos_hint)
    parent, child = Widget(), Widget()
    parent.add_widget(child)
    child.bind(disabled=lambda i, v: log("child disabled", v))
    parent.disabled = True
    log("parent", parent.disabled, "child", child.disabled)
    child.disabled = False
    log("child set False while parent disabled ->", child.disabled)
    parent.disabled = False
    log("parent False ->", child.disabled)
    save("properties")


def trace_events():
    from kivy.event import EventDispatcher
    from kivy.properties import NumericProperty

    class D(EventDispatcher):
        v = NumericProperty(0)
        __events__ = ("on_go",)

        def on_v(self, i, val):
            log("default on_v", r(val))

        def on_go(self, *a):
            log("default on_go", a)

    d = D()
    d.bind(v=lambda *a: log("v1"))
    d.bind(v=lambda *a: (log("v2 returns True"), True)[1])
    d.bind(v=lambda *a: log("v3"))
    d.v = 1
    d.v = 1
    log("# events")
    d.bind(on_go=lambda *a: log("g1", a[1:]))
    d.bind(on_go=lambda *a: log("g2", a[1:]))
    log("dispatch ->", d.dispatch("on_go", 7))
    uid = d.fbind("on_go", lambda *a: (log("g3 returns True"), True)[1])
    log("dispatch ->", d.dispatch("on_go", 8))
    d.unbind_uid("on_go", uid)
    log("dispatch after unbind_uid ->", d.dispatch("on_go", 9))
    save("events")


def trace_clock():
    from kivy.clock import ClockBase
    c = ClockBase()
    c._max_fps = 0
    c.start_clock()
    n = {"i": 0}

    def cb(name):
        def f(dt):
            log("call", name)
        return f

    c.schedule_once(cb("once 0 a"), 0)
    c.schedule_once(cb("once -1"), -1)
    c.schedule_once(cb("once 0 b"), 0)
    ev = c.schedule_interval(cb("interval 0"), 0)

    def nest(dt):
        log("call nest; schedules once 0 and once -1")
        c.schedule_once(cb("nested 0"), 0)
        c.schedule_once(cb("nested -1"), -1)
    c.schedule_once(nest, 0)
    trig = c.create_trigger(cb("trigger"), 0)
    trig()
    trig()  # a trigger runs once per tick however often it is called
    for step in range(3):
        log(f"# tick_draw {step}")
        c.tick_draw()
        log(f"# tick {step}")
        c.tick()
        n["i"] += 1
    ev.cancel()
    log("# after cancel")
    c.tick()
    c.stop_clock()
    save("clock")


def trace_animation():
    from kivy.animation import Animation
    from kivy.clock import Clock
    from kivy.uix.widget import Widget
    w = Widget(opacity=0)
    anim = Animation(opacity=1, d=0.2)
    anim.bind(on_start=lambda *a: log("on_start"),
              on_complete=lambda *a: log("on_complete opacity", r(w.opacity)))
    progress = []
    anim.bind(on_progress=lambda a, wid, p: progress.append(p))
    anim.start(w)
    log("after start opacity", r(w.opacity), "running", w in [x["widget"] for x in anim._widgets.values()])
    import time
    t0 = time.time()
    while time.time() - t0 < 0.5:
        time.sleep(0.01)
        Clock.tick()
    log("progress first", r(progress[0]), "last", r(progress[-1]), "monotonic",
        all(b >= a for a, b in zip(progress, progress[1:])))
    w2 = Widget(opacity=1)
    a1 = Animation(opacity=0, d=0.1)
    a2 = Animation(opacity=0.5, d=0.3)
    a1.bind(on_complete=lambda *a: log("a1 complete opacity", r(w2.opacity)))
    a2.bind(on_complete=lambda *a: log("a2 complete opacity", r(w2.opacity)))
    a1.start(w2)
    a2.start(w2)  # both run on the same property; the later write each frame wins
    t0 = time.time()
    while time.time() - t0 < 0.6:
        time.sleep(0.01)
        Clock.tick()
    w3 = Widget(opacity=1)
    a3 = Animation(opacity=0, d=1)
    a3.bind(on_complete=lambda *a: log("a3 complete (stop)"))
    a3.start(w3)
    Clock.tick()
    a3.stop(w3)
    a4 = Animation(opacity=0, d=1)
    a4.bind(on_complete=lambda *a: log("a4 complete (must not appear: cancel)"))
    a4.start(w3)
    a4.cancel(w3)
    a5 = Animation(opacity=0.25, d=0)
    a5.bind(on_complete=lambda *a: log("a5 duration 0 complete opacity", r(w3.opacity)))
    a5.start(w3)
    Clock.tick()
    Clock.tick()
    save("animation")


# ---------------------------------------------------------------- traces that need the window
def trace_touch(win):
    from kivy.uix.behaviors import ButtonBehavior
    from kivy.uix.floatlayout import FloatLayout
    from kivy.uix.widget import Widget

    class Btn(ButtonBehavior, Widget):
        def __init__(self, tag, **kw):
            super().__init__(**kw)
            self.tag = tag
            self.bind(state=lambda i, v: log(tag, "state", v))

        def on_touch_down(self, t):
            log(self.tag, "on_touch_down", r(t.pos))
            res = super().on_touch_down(t)
            log(self.tag, "on_touch_down ->", res)
            return res

        def on_touch_move(self, t):
            res = super().on_touch_move(t)
            log(self.tag, "on_touch_move grab_current", getattr(t.grab_current, "tag", None), "->", res)
            return res

        def on_touch_up(self, t):
            res = super().on_touch_up(t)
            log(self.tag, "on_touch_up grab_current", getattr(t.grab_current, "tag", None), "->", res)
            return res

        def on_press(self):
            log(self.tag, "on_press")

        def on_release(self):
            log(self.tag, "on_release")

    root = FloatLayout()
    a = Btn("A", size_hint=(None, None), size=(200, 200), pos=(100, 100))
    b = Btn("B", size_hint=(None, None), size=(200, 200), pos=(200, 200))  # added later: on top
    c = Btn("C", size_hint=(None, None), size=(100, 100), pos=(600, 100), disabled=True)
    for w in (a, b, c):
        root.add_widget(w)
    win.add_widget(root)
    win.bind(on_touch_down=lambda w, t: log("Window observer on_touch_down", r(t.pos)))

    def tap(x, y, to=None, name=""):
        log(f"# {name}")
        t = make_touch(x, y)
        t.touch_down()
        if to:
            t.touch_move(*to)
        t.touch_up()
        log("(wait past min_state_time .035 s, tick the clock)")
        time.sleep(0.06)
        Clock.tick()

    import time
    from kivy.clock import Clock
    tap(150, 150, name="tap A only")
    tap(250, 250, name="tap overlap: B is on top")
    tap(150, 150, to=(700, 500), name="press A, release outside")
    tap(150, 150, to=(350, 350), name="press A, release over B")
    tap(650, 150, name="tap disabled C")
    tap(50, 550, name="tap empty space")
    win.remove_widget(root)
    save("touch")


def trace_screens(win):
    from kivy.clock import Clock
    from kivy.uix.screenmanager import FadeTransition, Screen, ScreenManager

    class S(Screen):
        def __init__(self, **kw):
            super().__init__(**kw)
            for ev in ("on_pre_enter", "on_enter", "on_pre_leave", "on_leave"):
                self.bind(**{ev: (lambda e: lambda *a: log(self.name, e))(ev)})

    sm = ScreenManager(transition=FadeTransition(duration=0.1))
    win.add_widget(sm)
    log("# add first screen")
    sm.add_widget(S(name="a"))
    log("current", sm.current)
    sm.add_widget(S(name="b"))
    sm.add_widget(S(name="c"))
    log("screen_names", sm.screen_names, "children", [s.name for s in sm.children])
    log("# current = b")
    sm.current = "b"
    log("is_active", sm.transition.is_active, "children", [s.name for s in sm.children])
    log("# current = c while a->b is running")
    sm.current = "c"
    import time
    t0 = time.time()
    while time.time() - t0 < 0.4:
        time.sleep(0.01)
        Clock.tick()
    log("after", "current", sm.current, "is_active", sm.transition.is_active,
        "children", [s.name for s in sm.children])
    log("# current = c again (no-op)")
    sm.current = "c"
    win.remove_widget(sm)
    save("screens")


def trace_modal(win):
    from kivy.clock import Clock
    from kivy.uix.modalview import ModalView
    mv = ModalView(size_hint=(None, None), size=(200, 100))
    for ev in ("on_pre_open", "on_open", "on_pre_dismiss", "on_dismiss"):
        mv.bind(**{ev: (lambda e: lambda *a: log(e))(ev)})
    log("# open(animation=False)")
    mv.open(animation=False)
    log("is_open", mv._is_open, "center", r(mv.center), "in window", mv in win.children)
    log("# touch inside")
    t = make_touch(400, 300)
    t.touch_down()
    t.touch_up()
    log("is_open", mv._is_open)
    log("# touch outside")
    t = make_touch(10, 10)
    t.touch_down()
    t.touch_up()
    log("is_open", mv._is_open, "in window", mv in win.children)
    log("# open again, escape key")
    mv.open(animation=False)
    win.dispatch("on_keyboard", 27, 41, None, [])
    log("is_open after escape (animated dismiss pending)", mv._is_open)
    import time
    t0 = time.time()
    while time.time() - t0 < 0.3:
        time.sleep(0.01)
        Clock.tick()
    log("is_open after animation", mv._is_open)
    log("# auto_dismiss False")
    mv.auto_dismiss = False
    mv.open(animation=False)
    t = make_touch(10, 10)
    t.touch_down()
    t.touch_up()
    log("is_open", mv._is_open)
    mv.dismiss(animation=False)
    log("is_open", mv._is_open)
    save("modal")


def trace_label(win):
    """texture_size of labels in many configurations: the core text layout to match."""
    from kivy.core.text import LabelBase
    from kivy.resources import resource_find
    from kivy.uix.label import Label
    LabelBase.register("Deja", resource_find("data/fonts/DejaVuSans.ttf"),
                       fn_bold=resource_find("data/fonts/Roboto-Bold.ttf"))
    text = ("Figs have been grown in Greece for thousands of years. The fruit is dried in the sun, "
            "pressed by hand and packed the same day.")
    cases = [
        dict(text=""), dict(text="A"), dict(text="Hello world"), dict(text="two\nlines"),
        dict(text="trailing space "), dict(text="Ελληνικά"),
        dict(text="Hello", font_size=40), dict(text="Hello", bold=True),
        dict(text="Hello", font_name="Deja"), dict(text="Hello", font_name="Deja", bold=True),
        dict(text=text, text_size=(300, None)), dict(text=text, text_size=(300, None), line_height=1.25),
        dict(text=text, text_size=(300, None), line_height=0.8), dict(text=text, text_size=(300, 100)),
        dict(text=text, text_size=(300, 40), valign="middle"),
        dict(text="Hello", padding=(10, 5)), dict(text=text, text_size=(300, None), padding=(20, 0)),
        dict(text=text, text_size=(300, None), halign="justify"),
        dict(text="averyveryverylongwordthatcannotwrap", text_size=(100, None)),
        dict(text="Hello", text_size=(None, 100)),
    ]
    for kw in cases:
        lb = Label(**kw)
        lb.texture_update()
        log(repr(kw), "->", r(lb.texture_size))
    save("label")


def main():
    trace_properties()
    trace_events()
    trace_clock()
    trace_animation()
    from kivy.app import App
    from kivy.clock import Clock
    from kivy.core.window import Window
    from kivy.uix.widget import Widget

    class TraceApp(App):
        def build(self):
            Clock.schedule_once(self.run_traces, 0.3)
            return Widget()

        def run_traces(self, *_):
            trace_touch(Window)
            trace_screens(Window)
            trace_modal(Window)
            trace_label(Window)
            self.stop()

    TraceApp().run()


if __name__ == "__main__":
    main()
