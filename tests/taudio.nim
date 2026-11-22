# Tests core/audio against kivy/tests/test_audio.py (adapted: the WAV
# tests/assets/tone.wav, 1.402 s, instead of sample1.ogg), plus the order
# of the state changes and of on_play and on_stop for play, stop, the natural
# end and a loop, as Kivy 2.3.2 gives them (SDL2 provider), volume, unload and
# missing files. Run with SDL_AUDIO_DRIVER=dummy (run_tests.sh), which plays
# in real time without a device.

import std/[assertions, os, syncio, strutils, files, dirs, paths, tempfiles]
import nimkivy/clock
import nimkivy/core/audio

const
  SampleFile = "tests/assets/tone.wav"
  SampleLength = 1.402
  Delta = SampleLength * 0.01
  Delay = 0.2

proc tickFor(t: float) =
  # Ticks the real Clock until `t` seconds have passed.
  let deadline = time() + t
  while time() < deadline:
    sleep(10)
    Clock.tick()

proc getSound(): Sound =
  # AudioTestCase.get_sound
  assert fileExists(SampleFile)
  let s = loadSound(SampleFile)
  assert s != nil
  result = s

type
  Log = ref object
    entries: seq[string]

proc record(s: Sound): Log =
  # Logs the state changes and the events, with the state at each event.
  let log = Log(entries: @[])
  discard s.bindState(proc (v: SoundState) {.closure.} =
    log.entries.add "state " & $v)
  discard s.bindPlay(proc (): bool {.closure.} =
    log.entries.add "on_play " & $s.state
    false)
  discard s.bindStop(proc (): bool {.closure.} =
    log.entries.add "on_stop " & $s.state
    false)
  result = log

block testLengthSimple:
  let sound = getSound()
  sound.volume = 0.75
  let volume = sound.volume
  let length = sound.length
  assert abs(SampleLength - length) <= Delta, $length
  assert volume == sound.volume
  sound.unload()

block testLengthPlaying:
  let sound = getSound()
  sound.play()
  sleep(int(Delay * 1000))
  let length = sound.length
  assert abs(SampleLength - length) <= Delta, $length
  sound.stop()
  assert abs(SampleLength - length) <= Delta
  sound.unload()

block testLengthStopped:
  let sound = getSound()
  sound.play()
  sleep(int(Delay * 1000))
  sound.stop()
  let length = sound.length
  assert abs(SampleLength - length) <= Delta, $length
  sound.unload()

block properties:
  let sound = getSound()
  assert sound.source.len > 0 and sound.source.endsWith("tone.wav")
  assert sound.volume == 1.0
  assert not sound.loop
  assert sound.state == stateStop
  assert $sound.state == "stop"
  # tone.wav is 61828 frames at 44100 Hz: Kivy reports 1.4019954648526076.
  # Float literals: `61828 / 44100` would be computed in float32
  # (planetis-m/nimony-bugs-llms#335, bug-reports/08).
  assert abs(sound.length - 61828.0 / 44100.0) < 1e-12
  sound.unload()

block playStopOrder:
  # play, play again (stops first), stop, stop again (nothing).
  let sound = getSound()
  let log = sound.record()
  sound.play()
  assert sound.state == statePlay
  sound.play()
  sound.stop()
  sound.stop()
  assert log.entries == @["state play", "on_play play", "state stop", "on_stop stop",
    "state play", "on_play play", "state stop", "on_stop stop"], $log.entries
  sound.unload()

block naturalEnd:
  # The 0.1 s poll stops the sound when the stream has played it all.
  let sound = getSound()
  let log = sound.record()
  let start = time()
  var ended = 0.0
  discard sound.bindStop(proc (): bool {.closure.} =
    ended = time()
    false)
  sound.play()
  tickFor(0.5)
  assert sound.state == statePlay
  assert log.entries == @["state play", "on_play play"], $log.entries
  tickFor(1.6)
  assert sound.state == stateStop
  assert log.entries == @["state play", "on_play play", "state stop", "on_stop stop"], $log.entries
  # It ends after the sound's length, at the next poll.
  let took = ended - start
  assert took >= SampleLength - 0.05 and took < SampleLength + 0.5, $took
  sound.unload()

block loopOrder:
  # At the end the poll plays it again on the next tick: on_stop, on_play.
  let sound = getSound()
  let log = sound.record()
  sound.loop = true
  sound.play()
  let deadline = time() + 4.0
  while log.entries.len < 6 and time() < deadline:
    sleep(10)
    Clock.tick()
  assert log.entries == @["state play", "on_play play", "state stop", "on_stop stop",
    "state play", "on_play play"], $log.entries
  assert sound.state == statePlay
  sound.loop = false
  sound.stop()
  assert sound.state == stateStop
  sound.unload()

block volumeWhilePlaying:
  let sound = getSound()
  sound.play()
  sound.volume = 0.25
  assert sound.volume == 0.25
  sound.volume = 0.0
  assert sound.volume == 0.0
  sound.volume = 1.0
  sound.stop()
  # Out of Kivy's range (it raises OverflowError there): kept, not applied.
  sound.volume = 3.0
  assert sound.volume == 3.0
  sound.unload()

block unload:
  # unload stops a playing sound (on_stop), then nothing is loaded.
  let sound = getSound()
  let log = sound.record()
  sound.play()
  sound.unload()
  assert log.entries == @["state play", "on_play play", "state stop", "on_stop stop"], $log.entries
  assert sound.length == 0
  sound.play()
  assert sound.state == stateStop
  assert log.entries.len == 4
  # No poll left behind: ticking changes nothing.
  tickFor(0.3)
  assert log.entries.len == 4
  # load() reads the source again.
  sound.load()
  assert abs(sound.length - SampleLength) <= Delta
  sound.unload()

block missingFile:
  # A missing WAV still gives a Sound (Kivy logs "Unable to load"); it has no
  # length and does not play.
  let sound = loadSound("tests/assets/missing.wav")
  assert sound != nil
  let log = sound.record()
  assert sound.length == 0
  sound.play()
  assert sound.state == stateStop
  sound.stop()
  sound.unload()
  assert log.entries.len == 0
  # Not a WAV: no loader.
  assert loadSound("tests/assets/flag.png") == nil
  assert loadSound("tests/assets/missing.ogg") == nil

proc extensionCase() {.raises.} =
  # The extension is matched without case and without a query string.
  let dir = createTempDir("nimkivy_taudio", "")
  let upper = dir / path("TONE.WAV")
  copyFile(path(SampleFile), upper)
  let sound = loadSound($upper)
  assert sound != nil and abs(sound.length - SampleLength) <= Delta
  sound.unload()
  let q = loadSound(SampleFile & "?x=1")
  assert q != nil and q.length == 0   # no such file, but a WAV loader
  q.unload()
  removeDir(dir)

proc le(n, bytes: int): string =
  # `n` as `bytes` little-endian bytes.
  result = ""
  for i in 0 ..< bytes:
    result.add char((n shr (8 * i)) and 0xFF)

proc writeWav(path: string; freq, frames: int) {.raises.} =
  # A mono 16-bit PCM WAV of `frames` frames of silence.
  let data = frames * 2
  var s = "RIFF" & le(36 + data, 4) & "WAVEfmt " & le(16, 4) & le(1, 2) & le(1, 2) &
    le(freq, 4) & le(freq * 2, 4) & le(2, 2) & le(16, 2) & "data" & le(data, 4)
  for i in 0 ..< data:
    s.add '\0'
  writeFile(path, s)

proc resampledEnd() {.raises.} =
  # A rate the device resamples (the kiosk's clips are 24 kHz mono): the end
  # is still seen, because play flushes the stream (without the flush the
  # resampler keeps a few bytes queued and on_stop never comes).
  let dir = createTempDir("nimkivy_taudio", "")
  let file = $(dir / path("clip24k.wav"))
  writeWav(file, 24000, 12000)
  let sound = loadSound(file)
  assert sound != nil and abs(sound.length - 0.5) < 1e-12
  let log = sound.record()
  sound.play()
  let deadline = time() + 2.0
  while log.entries.len < 4 and time() < deadline:
    sleep(10)
    Clock.tick()
  assert log.entries == @["state play", "on_play play", "state stop", "on_stop stop"],
    $log.entries
  sound.unload()
  removeDir(dir)

try:
  extensionCase()
  resampledEnd()
except:
  quit "taudio: file error"

echo "taudio: ok"
