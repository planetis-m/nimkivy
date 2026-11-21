# Tests the raw SDL3, SDL3_ttf and SDL3_image bindings: struct sizes against
# C, then a headless smoke test that calls every binding (run_tests.sh sets
# SDL_VIDEO_DRIVER=offscreen and SDL_AUDIO_DRIVER=dummy).

import std/assertions
import nimkivy/sdl3/[sdl, ttf, image]

{.compile: "sdl3_layout.c".}
proc sdl3CSizeof(name: cstring): clonglong {.importc, cdecl.}

const
  FontPath = cstring"reference/assets/fonts/SourceSans3-Regular.ttf"
  ImagePath = cstring"reference/assets/landscape.png"

proc pixel(s: ptr SDL_Surface; x, y: int): array[4, uint8] =
  # The bytes of pixel (x, y) of a 4-byte-per-pixel surface.
  let row = cast[ptr UncheckedArray[uint8]](s.pixels)
  let i = y * int(s.pitch) + x * 4
  result = [row[i], row[i + 1], row[i + 2], row[i + 3]]

# The sizes are Nimony's own, from the declarations (a `const` sizeof is
# computed by Nimony; a run-time one would be the C compiler's).
# GAP: field offsets are not compared with C, only struct sizes, because
# Nimony has no offsetOf (sem: "to implement"), and the run-time address of an
# importc field is the C compiler's, not Nimony's.
block struct_sizes:
  const sizes = [
    (cstring"SDL_Rect", sizeof(SDL_Rect)), (cstring"SDL_FRect", sizeof(SDL_FRect)),
    (cstring"SDL_FPoint", sizeof(SDL_FPoint)), (cstring"SDL_Color", sizeof(SDL_Color)),
    (cstring"SDL_FColor", sizeof(SDL_FColor)), (cstring"SDL_Vertex", sizeof(SDL_Vertex)),
    (cstring"SDL_Surface", sizeof(SDL_Surface)),
    (cstring"SDL_AudioSpec", sizeof(SDL_AudioSpec)),
    (cstring"SDL_CommonEvent", sizeof(SDL_CommonEvent)),
    (cstring"SDL_QuitEvent", sizeof(SDL_QuitEvent)),
    (cstring"SDL_WindowEvent", sizeof(SDL_WindowEvent)),
    (cstring"SDL_KeyboardEvent", sizeof(SDL_KeyboardEvent)),
    (cstring"SDL_MouseMotionEvent", sizeof(SDL_MouseMotionEvent)),
    (cstring"SDL_MouseButtonEvent", sizeof(SDL_MouseButtonEvent)),
    (cstring"SDL_MouseWheelEvent", sizeof(SDL_MouseWheelEvent)),
    (cstring"SDL_TouchFingerEvent", sizeof(SDL_TouchFingerEvent)),
    (cstring"SDL_Event", sizeof(SDL_Event))]
  for (name, size) in sizes:
    assert sdl3CSizeof(name) == clonglong(size), fromCString(name)

block smoke:
  assert SDL_SetHint(SDL_HINT_TOUCH_MOUSE_EVENTS, "0")
  assert SDL_Init(SDL_INIT_VIDEO or SDL_INIT_EVENTS), fromCString(SDL_GetError())
  let window = SDL_CreateWindow("tsdl3", 64, 64, SDL_WINDOW_HIDDEN)
  assert window != nil, fromCString(SDL_GetError())
  var w = 0.cint
  var h = 0.cint
  assert SDL_GetWindowSizeInPixels(window, addr w, addr h)
  assert w == 64 and h == 64
  let renderer = SDL_CreateRenderer(window, "software")
  assert renderer != nil, fromCString(SDL_GetError())

  # One red triangle over the lower-left half, on black.
  assert SDL_SetRenderDrawColorFloat(renderer, 0, 0, 0, 1)
  assert SDL_RenderClear(renderer)
  let red = SDL_FColor(r: 1, g: 0, b: 0, a: 1)
  var verts = [
    SDL_Vertex(position: SDL_FPoint(x: 0, y: 0), color: red),
    SDL_Vertex(position: SDL_FPoint(x: 0, y: 64), color: red),
    SDL_Vertex(position: SDL_FPoint(x: 64, y: 64), color: red)]
  assert SDL_RenderGeometry(renderer, nil, addr verts[0], 3, nil, 0)
  let shot = SDL_RenderReadPixels(renderer, nil)
  assert shot != nil, fromCString(SDL_GetError())
  let rgba = SDL_ConvertSurface(shot, SDL_PIXELFORMAT_RGBA32)
  assert rgba != nil
  assert rgba.w == 64 and rgba.h == 64
  assert pixel(rgba, 8, 56) == [255'u8, 0, 0, 255]
  assert pixel(rgba, 56, 8) == [0'u8, 0, 0, 255]
  assert IMG_SavePNG(rgba, "tests/out/tsdl3.png"), fromCString(SDL_GetError())
  SDL_DestroySurface(rgba)
  SDL_DestroySurface(shot)

  # A word with SDL3_ttf, measured, rendered and made a texture.
  assert TTF_Init()
  let font = TTF_OpenFont(FontPath, 24)
  assert font != nil, fromCString(SDL_GetError())
  TTF_SetFontHinting(font, TTF_HINTING_NORMAL)
  TTF_SetFontKerning(font, true)
  TTF_SetFontStyle(font, TTF_STYLE_NORMAL)
  assert SDL_SetHint(SDL_HINT_ANDROID_TRAP_BACK_BUTTON, "1")
  assert TTF_SetFontDirection(font, TTF_DIRECTION_LTR)
  # The ISO 15924 tag 'Latn', as TTF_StringToTag makes it.
  assert TTF_SetFontScript(font, (uint32(ord('L')) shl 24) or (uint32(ord('a')) shl 16) or
    (uint32(ord('t')) shl 8) or uint32(ord('n')))
  assert TTF_GetFontHeight(font) > 0
  assert TTF_GetFontAscent(font) > 0 and TTF_GetFontDescent(font) < 0
  var tw = 0.cint
  var th = 0.cint
  assert TTF_GetStringSize(font, "Kivy", 0, addr tw, addr th)
  assert tw > 0 and th > 0
  let text = TTF_RenderText_Blended(font, "Kivy", 0, SDL_Color(r: 255, g: 255, b: 255, a: 255))
  assert text != nil, fromCString(SDL_GetError())
  assert text.w == tw and text.h == th
  let tex = SDL_CreateTextureFromSurface(renderer, text)
  assert tex != nil
  var fw = 0'f32
  var fh = 0'f32
  assert SDL_GetTextureSize(tex, addr fw, addr fh)
  assert fw == float32(tw) and fh == float32(th)
  SDL_DestroyTexture(tex)
  SDL_DestroySurface(text)
  TTF_CloseFont(font)
  TTF_Quit()

  # An image with SDL3_image: 400 x 200, a red mark at the top left.
  let img = IMG_Load(ImagePath)
  assert img != nil, fromCString(SDL_GetError())
  assert img.w == 400 and img.h == 200
  let imgRgba = SDL_ConvertSurface(img, SDL_PIXELFORMAT_RGBA32)
  assert imgRgba != nil
  assert pixel(imgRgba, 10, 10) == [220'u8, 30, 30, 255]
  SDL_DestroySurface(imgRgba)
  SDL_DestroySurface(img)

  # The other renderer calls, into a target texture: each must compile
  # against the header and succeed.
  assert SDL_SetWindowTitle(window, "tsdl3 b")
  assert SDL_GetWindowDisplayScale(window) > 0
  assert SDL_GetDisplayContentScale(SDL_GetDisplayForWindow(window)) > 0
  let target = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32,
    SDL_TEXTUREACCESS_TARGET, 16, 16)
  assert target != nil, fromCString(SDL_GetError())
  assert SDL_SetRenderTarget(renderer, target)
  var outW = 0.cint
  var outH = 0.cint
  assert SDL_GetCurrentRenderOutputSize(renderer, addr outW, addr outH)
  assert outW == 16 and outH == 16
  var clip = SDL_Rect(x: 0, y: 0, w: 8, h: 8)
  assert SDL_SetRenderClipRect(renderer, addr clip)
  let fade = SDL_ComposeCustomBlendMode(SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ONE,
    SDL_BLENDOPERATION_ADD, SDL_BLENDFACTOR_ONE, SDL_BLENDFACTOR_ONE,
    SDL_BLENDOPERATION_ADD)
  assert not (fade == SDL_BLENDMODE_INVALID)
  assert SDL_SetRenderDrawBlendMode(renderer, SDL_BLENDMODE_BLEND)
  var line = [SDL_FPoint(x: 0, y: 0), SDL_FPoint(x: 15, y: 15)]
  assert SDL_RenderLines(renderer, addr line[0], 2)
  assert SDL_SetRenderClipRect(renderer, nil)
  assert SDL_SetRenderTarget(renderer, nil)
  # The software renderer refuses custom blend modes ("That operation is not
  # supported"); the headless tests use it.
  assert not SDL_SetTextureBlendMode(target, fade)
  assert SDL_SetTextureBlendMode(target, SDL_BLENDMODE_BLEND)
  assert SDL_SetTextureColorModFloat(target, 1, 0.5, 0.5)
  assert SDL_SetTextureAlphaModFloat(target, 0.5)
  assert SDL_SetTextureScaleMode(target, SDL_SCALEMODE_LINEAR)
  var dst = SDL_FRect(x: 0, y: 0, w: 32, h: 32)
  assert SDL_RenderTexture(renderer, target, nil, addr dst)
  assert SDL_RenderTexture9Grid(renderer, target, nil, 4, 4, 4, 4, 1, addr dst)
  assert SDL_RenderPresent(renderer)
  SDL_DestroyTexture(target)
  var ev = default(SDL_Event)
  while SDL_PollEvent(addr ev): discard
  assert not SDL_WaitEventTimeout(addr ev, 1)

  # Audio, with the dummy driver: a WAV queued on a stream.
  assert SDL_Init(SDL_INIT_AUDIO), fromCString(SDL_GetError())
  var spec = default(SDL_AudioSpec)
  var buf: nil ptr uint8 = nil
  var size = 0'u32
  assert SDL_LoadWAV("reference/assets/tone.wav", addr spec, addr buf, addr size),
    fromCString(SDL_GetError())
  assert buf != nil and size > 0 and spec.freq > 0
  let stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK,
    addr spec, nil, nil)
  assert stream != nil, fromCString(SDL_GetError())
  assert SDL_SetAudioStreamGain(stream, 0.5)
  assert SDL_PutAudioStreamData(stream, buf, cint(size))
  assert SDL_GetAudioStreamQueued(stream) > 0
  assert SDL_ResumeAudioStreamDevice(stream)
  assert SDL_PauseAudioStreamDevice(stream)
  assert SDL_ClearAudioStream(stream)
  assert SDL_GetAudioStreamQueued(stream) == 0
  SDL_DestroyAudioStream(stream)
  SDL_free(buf)

  SDL_DestroyRenderer(renderer)
  SDL_DestroyWindow(window)
  SDL_Quit()
