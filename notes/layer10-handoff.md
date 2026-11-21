# Handoff from layer 9 to layer 10

- Audio is `nimkivy/core/audio`: `loadSound(path)` (Kivy's
  `SoundLoader.load`), then `bind("on_stop", ...)`, `play`, `stop`,
  `unload`, `state == statePlay`, `volume`, `loop`, `length`. This is
  everything the kiosk's `voice.py` uses.
- The end of playback is a 0.1 s Clock interval, so `on_stop` comes only
  while the Clock ticks (the event loop, or `sleep(10); Clock.tick()` in a
  test).
- `play` must flush the stream (SDL_FlushAudioStream). Without it, a WAV
  the device resamples (the kiosk's clips are 24 kHz) keeps a few bytes
  queued, and the end is never seen. taudio's `resampledEnd` catches this
  on the dummy driver.
- Real device: run `tests/audiodevice.nim` (see its header) with a
  window open first. It passed on PipeWire with SDL's default,
  `pipewire` and `pulseaudio` drivers: no hang. Unlike Kivy + SDL2, nimkivy
  needs no audio-before-window order, because it installs no SDL event
  filter.
- Window.close calls SDL_Quit, which destroys every audio stream. Sounds
  check `SDL_WasInit` before they touch theirs, so `unload` after the loop
  is safe.
- Nimony: an integer literal picks the `float32` overload (`1 / 3` is
  single precision; planetis-m/nimony-bugs-llms#335). Write float literals
  in numeric code.
