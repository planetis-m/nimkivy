## Audio: Kivy's `kivy/core/audio/__init__.py` (SoundLoader, Sound) and its
## SDL provider `core/audio/audio_sdl2.pyx` (SoundSDL2), on core SDL3.
##
## `loadSound` (Kivy's `SoundLoader.load`) returns a `Sound` for a WAV file.
## The file is decoded with `SDL_LoadWAV` when the sound's `source` is set,
## and each sound plays through its own audio stream, bound to the default
## playback device (`SDL_OpenAudioDeviceStream`). `play` queues the whole
## file on the stream, flushes it and resumes it; `stop` pauses and empties
## it. As in `audio_sdl2.pyx`, a Clock interval of 0.1 s polls for the end of
## playback (the stream has nothing queued) and then calls `stop`, or, with
## `loop`, plays the sound again on the next tick.
##
## Every `play` first stops the sound, so a playing sound that is played
## again dispatches `stop` and then `play`, and so does each turn of a loop.
## A missing or unreadable file still gives a Sound, with a log line, whose
## `length` is 0 and whose `play` does nothing, as in Kivy.
##
## Out of scope (SCOPE.md): `pitch`, `get_pos`, `seek`, and every format but
## WAV.

import std/[strutils, syncio]
import ../[props, clock, resources]
import ../sdl3/sdl

export props

type
  SoundState* = enum
    ## The `state` of a sound (Kivy's strings).
    stateStop = "stop"         ## not playing
    statePlay = "play"         ## playing

  ChunkContainerObj = object
    spec: SDL_AudioSpec            # the format of `buf`
    buf: nil ptr uint8             # the decoded samples, owned (SDL_free)
    len: uint32                    # bytes in `buf`
    stream: nil SDL_AudioStream    # the stream and its device, owned
    playing: bool                  # Kivy's `channel != -1`

  ChunkContainer = ref ChunkContainerObj
    # The loaded file and the stream that plays it. audio_sdl2.pyx
    # ChunkContainer

proc audioIsInit(): bool =
  # Whether SDL's audio is up. SDL_Quit (Window.close) destroys every
  # stream, after which a stream pointer must not be used.
  SDL_WasInit(SDL_INIT_AUDIO) == SDL_INIT_AUDIO

proc `=wasMoved`(c: var ChunkContainerObj) =
  c.buf = nil
  c.stream = nil

proc `=destroy`(c: ChunkContainerObj) =
  # ChunkContainer.__dealloc__: destroying the stream halts it.
  let st = c.stream
  if st != nil and audioIsInit():
    SDL_DestroyAudioStream(st)
  let b = c.buf
  if b != nil:
    SDL_free(b)

proc log(level, category, msg: string) =
  # Kivy's Logger, on stderr in Kivy's layout.
  stderr.writeLine "[" & level & "] [" & alignLeft(category, 12) & "] " & msg

proc sdlError(): string =
  result = fromCString(SDL_GetError())

proc length(cc: ChunkContainer): float =
  # SoundSDL2._get_length: the file's frames over its rate; 0 when empty.
  if cc.buf == nil or cc.spec.channels <= 0 or cc.spec.freq <= 0:
    return 0.0
  # SDL_AUDIO_BITSIZE: the low byte of the format is the bits per sample.
  let bytesPerSample = int(uint32(cc.spec.format) and 0xFF'u32) div 8
  if bytesPerSample == 0:
    return 0.0
  let frames = int(cc.len) div bytesPerSample div int(cc.spec.channels)
  result = float(frames) / float(cc.spec.freq)

proc setGain(cc: ChunkContainer; volume: float) =
  # Kivy sets the chunk's volume to int(volume * 128) of the mixer's 128.
  # Kivy's chunk volume is a Uint8, so a volume of 2 or more, or below 0,
  # raises OverflowError there; here it is clamped (callbacks cannot raise).
  let st = cc.stream
  if st != nil and audioIsInit():
    let v = clamp(int(volume * 128), 0, 255)
    discard SDL_SetAudioStreamGain(st, cfloat(float(v) / 128))

proc mixInit() =
  # audio_sdl2.pyx mix_init: starts SDL's audio. Kivy also opens the
  # mixer's device here; each Sound opens its own stream in `load`. SDL
  # counts SDL_Init calls, and SDL_Quit (Window.close) ends them all, so the
  # check is SDL's own rather than a flag of ours.
  if audioIsInit():
    return
  if not SDL_Init(SDL_INIT_AUDIO):
    log "CRITICAL", "AudioSDL2", "Unable to initialize SDL: " & sdlError()

proc extensions(): seq[string] =
  # SoundSDL2.extensions
  mixInit()
  # GAP: only WAV, where Kivy's SDL2 provider also plays OGG, MP3, FLAC and
  # sequenced formats through SDL2_mixer, because SDL3_mixer is not
  # installed and core SDL3 loads only WAV (PORTING.md, decision 1)
  result = @["wav"]

properties:
  type
    Sound* = ref object of RootObj
      ## A sound loaded from a file. core/audio/__init__.py Sound and
      ## audio_sdl2.pyx SoundSDL2
      cc: ChunkContainer
      checkPlayEv: nil ClockEvent    # Kivy's `_check_play_ev`
      source* {.prop, handler.}: string = ""
        ## the file the sound is loaded from ("" for Kivy's None); setting
        ## it loads the file
      volume* {.prop, handler.}: float = 1.0
        ## the volume, 0 (mute) to 1 (full), also while the sound plays
      state* {.prop.}: SoundState = stateStop
        ## `statePlay` from `play` until `stop` or the end of playback
      loop* {.prop.}: bool = false   ## the sound plays again when it ends
      play* {.event.}: proc ()       ## the sound started playing
      stop* {.event.}: proc ()       ## the sound stopped playing

  proc newSound(): Sound =
    # SoundSDL2.__init__; the loader sets `source` after it.
    result = Sound(cc: ChunkContainer(spec: default(SDL_AudioSpec), buf: nil, len: 0,
      stream: nil, playing: false), checkPlayEv: nil)
    result.initProps()

  proc length*(s: Sound): float =
    ## The length in seconds; 0 when nothing is loaded.
    ## SoundSDL2._get_length
    s.cc.length

  # -------------------------------------------------------------- playback

  proc cancelCheck(s: Sound) =
    # The interval stops: `return False` from _check_play.
    let ev = s.checkPlayEv
    if ev != nil:
      ev.cancel()

  proc stop*(s: Sound) =
    ## Stops playback and dispatches `stop`; nothing if it is not playing.
    ## SoundSDL2.stop and Sound.stop
    let cc = s.cc
    if cc.buf == nil or not cc.playing:
      return
    # Mix_HaltChannel: pause the device and drop what is queued.
    let st = cc.stream
    if st != nil and audioIsInit():
      discard SDL_PauseAudioStreamDevice(st)
      discard SDL_ClearAudioStream(st)
    cc.playing = false
    s.cancelCheck()
    s.checkPlayEv = nil
    s.state = stateStop
    discard s.dispatchStop()

  proc play*(s: Sound)

  proc checkPlay(s: Sound) =
    # SoundSDL2._check_play: at the end of playback, stop, or with `loop`
    # play again on the next tick.
    let cc = s.cc
    let st = cc.stream
    if not cc.playing or cc.buf == nil or st == nil:
      s.cancelCheck()
      return
    # Mix_Playing: the stream still has data for the device.
    if audioIsInit() and SDL_GetAudioStreamQueued(st) > 0:
      return
    if s.loop:
      let snd = s
      discard Clock.scheduleOnce(proc (dt: float) {.closure.} = snd.play())
    else:
      s.stop()
    s.cancelCheck()

  proc play*(s: Sound) =
    ## Plays the sound from the start (stopping it first if it plays) and
    ## dispatches `play`; nothing if no file is loaded.
    ## SoundSDL2.play and Sound.play
    s.stop()
    let cc = s.cc
    let st = cc.stream
    if cc.buf == nil or st == nil:
      return
    cc.setGain(s.volume)
    # Mix_PlayChannel: the whole file, from the start. The flush marks the
    # end of the data, or the resampler keeps its last bytes queued for good
    # and the end is never seen.
    if not (audioIsInit() and SDL_ClearAudioStream(st) and
        SDL_PutAudioStreamData(st, cc.buf, cint(cc.len)) and
        SDL_FlushAudioStream(st) and SDL_ResumeAudioStreamDevice(st)):
      log "WARNING", "AudioSDL2", "Unable to play " & s.source & ": " & sdlError()
      return
    cc.playing = true
    # Schedule an event to check whether the sound is still playing.
    # GAP: the interval holds the sound strongly, where Kivy's Clock holds the
    # bound method `_check_play` weakly, so a dropped sound plays to its end
    # (and dispatches `stop`) before it is freed, because Nimony has no weak
    # references
    let snd = s
    s.checkPlayEv = Clock.scheduleInterval(proc (dt: float) {.closure.} =
      snd.checkPlay(), 0.1)
    s.state = statePlay
    discard s.dispatchPlay()

  proc unload*(s: Sound) =
    ## Stops the sound (dispatching `stop` if it plays), then frees the
    ## file's data and closes its stream. SoundSDL2.unload
    s.stop()
    let cc = s.cc
    let st = cc.stream
    if st != nil:
      if audioIsInit():
        SDL_DestroyAudioStream(st)
      cc.stream = nil
    let b = cc.buf
    if b != nil:
      SDL_free(b)
      cc.buf = nil
      cc.len = 0

  proc load*(s: Sound) =
    ## Loads `source` into memory and opens its stream; on failure, logs and
    ## leaves the sound empty. Setting `source` calls it. SoundSDL2.load
    s.unload()
    if s.source.len == 0:
      return
    var path = s.source
    var spec = default(SDL_AudioSpec)
    var buf: nil ptr uint8 = nil
    var size = 0'u32
    if not SDL_LoadWAV(path.toCString, addr spec, addr buf, addr size):
      log "WARNING", "AudioSDL2", "Unable to load " & path & ": " & sdlError()
      return
    # The stream converts the file's format to the device's.
    let st = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK,
      addr spec, nil, nil)
    if st == nil:
      log "WARNING", "AudioSDL2", "Unable to load " & path & ": " & sdlError()
      SDL_free(buf)
      return
    let cc = s.cc
    cc.spec = spec
    cc.buf = buf
    cc.len = size
    cc.stream = st
    cc.setGain(s.volume)

  method onSourceChanged*(s: Sound; v: string) {.base.} =
    ## Loads the new file. Sound.on_source
    s.unload()
    if v.len == 0:
      return
    s.load()

  method onVolumeChanged*(s: Sound; v: float) {.base.} =
    ## Applies the volume. SoundSDL2.on_volume
    if s.cc.buf != nil:
      s.cc.setGain(v)

  # -------------------------------------------------------------- loader

  proc loadSound*(filename: string): nil Sound =
    ## Kivy's `SoundLoader.load`: a Sound for `filename` (found as a path or
    ## in the resource paths), or nil with a log line when the extension is
    ## not WAV. A WAV that cannot be loaded still gives a Sound (logged),
    ## whose `length` is 0 and whose `play` does nothing, as in Kivy.
    ## core/audio/__init__.py SoundLoader.load
    var name = filename
    let rfn = resourceFind(filename)
    if rfn.len > 0:
      name = rfn
    var ext = name
    let dot = name.rfind('.')
    if dot >= 0:
      ext = name.substr(dot + 1)
    ext = ext.toLowerAscii
    let q = ext.find('?')
    if q >= 0:
      ext = ext.substr(0, q - 1)
    if ext in extensions():
      let s = newSound()
      s.source = name
      return s
    log "WARNING", "Audio", "Unable to find a loader for <" & name & ">"
    result = nil
