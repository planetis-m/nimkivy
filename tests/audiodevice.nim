# A check of core/audio on the real audio device, with the window open
# first (the order in which Kivy + SDL2 hung the kiosk on PulseAudio). Not in
# run_tests.sh: it needs a device and plays sound. Run from the repository
# root, without SDL_AUDIO_DRIVER, under a timeout, and listen:
#
#   nimony c --mm:orc --path:src --nimcache:nimcache/audiodevice \
#     -o:bin/audiodevice tests/audiodevice.nim
#   timeout 60 ./bin/audiodevice [clipA.wav [clipB.wav]]
#
# It plays clip A, stops it (unload, as the kiosk's voice.py does), plays
# clip B to its natural end, then plays A again and closes the window while
# it plays, and unloads it after SDL has shut down. The clips default to
# tests/assets/tone.wav.

import std/[assertions, os, strutils, syncio]
import nimkivy/[clock, config, base]
import nimkivy/uix/widget
import nimkivy/core/audio

type
  Check = ref object
    log: seq[string]
    start: float
    current: nil Sound     # voice.py's `self.sound`
    last: nil Sound
    lengthB: string

proc note(c: Check; msg: string) =
  let line = formatFloat(time() - c.start, ffDecimal, 2) & " " & msg
  c.log.add msg
  stderr.writeLine "[audiodevice] " & line

proc watch(c: Check; s: Sound; name: string) =
  # voice.py binds on_stop; on_play is logged too, with the state.
  discard s.bindPlay(proc (): bool {.closure.} =
    c.note name & " on_play " & $s.state
    false)
  discard s.bindStop(proc (): bool {.closure.} =
    c.note name & " on_stop " & $s.state
    false)

proc load(c: Check; path, name: string): Sound =
  let s = loadSound(path)
  assert s != nil and s.length > 0, "cannot load " & path
  c.watch(s, name)
  result = s

let clipA = if paramCount() >= 1: paramStr(1) else: "tests/assets/tone.wav"
let clipB = if paramCount() >= 2: paramStr(2) else: clipA

Config.graphics.width = 320
Config.graphics.height = 240
let c = Check(log: @[], start: time(), current: nil, last: nil, lengthB: "")

discard Clock.scheduleOnce(proc (dt: float) {.closure.} =
  # The window is open and has drawn: the first Sound opens the device now.
  c.note "window open"
  let a = c.load(clipA, "A")
  c.current = a
  a.play()
  assert a.state == statePlay
  discard Clock.scheduleOnce(proc (dt: float) {.closure.} =
    c.note "unload A"
    a.unload()
    c.current = nil
    let b = c.load(clipB, "B")
    c.current = b
    c.lengthB = formatFloat(b.length, ffDecimal, 2)
    c.note "B is " & c.lengthB & " s"
    discard b.bindStop(proc (): bool {.closure.} =
      # The natural end: play A again and close the window while it plays.
      discard Clock.scheduleOnce(proc (dt: float) {.closure.} =
        let a2 = c.load(clipA, "A2")
        c.last = a2
        a2.play()
        discard Clock.scheduleOnce(proc (dt: float) {.closure.} =
          c.note "close window"
          stopTouchApp(), 0.5))
      false)
    b.play(), 1.5), 1.0)

# A watchdog: Clock-driven, so it catches a lost end, not a frozen main loop
# (the outer `timeout` catches that).
discard Clock.scheduleOnce(proc (dt: float) {.closure.} =
  quit("[audiodevice] watchdog: B never ended"), 60.0)

runTouchApp(newWidget())
c.note "loop left"
let a2 = c.last
if a2 != nil:
  # SDL has shut down (Window.close): unload must not touch the dead stream.
  a2.unload()
let expected = @["window open", "A on_play play", "unload A", "A on_stop stop",
  "B is " & c.lengthB & " s",
  "B on_play play", "B on_stop stop", "A2 on_play play", "close window", "loop left",
  "A2 on_stop stop"]
assert c.log == expected, $c.log
echo "audiodevice: ok"
