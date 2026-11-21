# Ports kivy/tests/test_clock.py (the tests listed in ACCEPTANCE.md). Each
# test uses a fresh clock that does not wait for frames, like the
# `kivy_clock` fixture.

import std/assertions
import nimkivy/clock

type ClockCounter = ref object
  counter: int

proc newClock(): ClockBase =
  # kivy/tests/fixtures.py kivy_clock
  result = newClockBase()
  result.maxFps = 0
  result.startClock()

proc callback(c: ClockCounter): ClockCallback =
  # The counter's __call__.
  result = proc (dt: float) {.closure.} = inc c.counter

block test_schedule_once:
  # kivy/tests/test_clock.py::test_schedule_once
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  discard clock.scheduleOnce(counter.callback)
  clock.tick()
  assert counter.counter == 1
  clock.stopClock()

block test_schedule_once_twice:
  # kivy/tests/test_clock.py::test_schedule_once_twice
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let cb = counter.callback
  discard clock.scheduleOnce(cb)
  discard clock.scheduleOnce(cb)
  clock.tick()
  assert counter.counter == 2
  clock.stopClock()

block test_schedule_once_draw_after:
  # kivy/tests/test_clock.py::test_schedule_once_draw_after
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  discard clock.scheduleOnce(counter.callback, 0)
  clock.tickDraw()
  assert counter.counter == 0
  clock.tick()
  assert counter.counter == 1
  clock.stopClock()

block test_schedule_once_draw_before:
  # kivy/tests/test_clock.py::test_schedule_once_draw_before
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  discard clock.scheduleOnce(counter.callback, -1)
  clock.tickDraw()
  assert counter.counter == 1
  clock.tick()
  assert counter.counter == 1
  clock.stopClock()

block test_unschedule:
  # kivy/tests/test_clock.py::test_unschedule
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let cb = counter.callback
  discard clock.scheduleOnce(cb)
  clock.unschedule(cb)
  clock.tick()
  assert counter.counter == 0
  clock.stopClock()

block test_unschedule_event:
  # kivy/tests/test_clock.py::test_unschedule_event
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let ev = clock.scheduleOnce(counter.callback)
  clock.unschedule(ev)
  clock.tick()
  assert counter.counter == 0
  clock.stopClock()

block test_unschedule_after_tick:
  # kivy/tests/test_clock.py::test_unschedule_after_tick
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let cb = counter.callback
  discard clock.scheduleOnce(cb, 5.0)
  clock.tick()
  clock.unschedule(cb)
  clock.tick()
  assert counter.counter == 0
  clock.stopClock()

block test_unschedule_draw:
  # kivy/tests/test_clock.py::test_unschedule_draw
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let cb = counter.callback
  discard clock.scheduleOnce(cb, 0)
  clock.tickDraw()
  assert counter.counter == 0
  clock.unschedule(cb)
  clock.tick()
  assert counter.counter == 0
  clock.stopClock()

block test_trigger_create:
  # kivy/tests/test_clock.py::test_trigger_create
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let trigger = clock.createTrigger(counter.callback, 0)
  trigger.trigger()
  assert counter.counter == 0
  clock.tick()
  assert counter.counter == 1
  clock.stopClock()

block test_trigger_cancel:
  # kivy/tests/test_clock.py::test_trigger_cancel
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let trigger = clock.createTrigger(counter.callback, 5.0)
  trigger.trigger()
  trigger.cancel()
  clock.tick()
  assert counter.counter == 0
  clock.stopClock()

block test_trigger_interval:
  # kivy/tests/test_clock.py::test_trigger_interval
  let clock = newClock()
  let counter = ClockCounter(counter: 0)
  let trigger = clock.createTrigger(counter.callback, 0, interval = true)
  trigger.trigger()
  clock.tick()
  assert counter.counter == 1
  clock.tick()
  assert counter.counter == 2
  clock.stopClock()
