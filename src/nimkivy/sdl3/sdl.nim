## Raw bindings to SDL3 (3.4), only the part nimkivy uses.
##
## Names, types and values are those of `<SDL3/SDL.h>`. Opaque handles are
## `ptr` types to an incomplete struct, C enums and flags are `distinct`
## integers with their constants, and a pointer the C function may take or
## return as NULL is a `nil` type. There is no ergonomic layer here: the
## wrappers live in `graphics/`, `core/` and `input/`. A function a later layer
## needs is added here, and noted in that layer's review.

{.passL: "-lSDL3".}

const SdlHeader = "<SDL3/SDL.h>"

type
  SDL_WindowObj {.importc: "SDL_Window", header: SdlHeader,
      incompleteStruct.} = object
  SDL_Window* = ptr SDL_WindowObj ## A window.
  SDL_RendererObj {.importc: "SDL_Renderer", header: SdlHeader,
      incompleteStruct.} = object
  SDL_Renderer* = ptr SDL_RendererObj ## A 2D renderer of a window.
  SDL_TextureObj {.importc: "SDL_Texture", header: SdlHeader,
      incompleteStruct.} = object
  SDL_Texture* = ptr SDL_TextureObj ## A texture owned by a renderer.
  SDL_AudioStreamObj {.importc: "SDL_AudioStream", header: SdlHeader,
      incompleteStruct.} = object
  SDL_AudioStream* = ptr SDL_AudioStreamObj ## An audio stream.
  SDL_IOStreamObj {.importc: "SDL_IOStream", header: SdlHeader,
      incompleteStruct.} = object
  SDL_IOStream* = ptr SDL_IOStreamObj ## A stream to read or write data.

  SDL_InitFlags* = distinct uint32 ## Subsystems for `SDL_Init`.
  SDL_WindowFlags* = distinct uint64 ## Flags for `SDL_CreateWindow`.
  SDL_BlendMode* = distinct uint32 ## A built-in or composed blend mode.
  SDL_BlendOperation* = distinct cint ## Operation of a custom blend mode.
  SDL_BlendFactor* = distinct cint ## Factor of a custom blend mode.
  SDL_PixelFormat* = distinct uint32 ## A pixel format.
  SDL_TextureAccess* = distinct cint ## How a texture is accessed.
  SDL_ScaleMode* = distinct cint ## Texture filtering.
  SDL_SurfaceFlags* = distinct uint32 ## Flags of a surface (read only).
  SDL_EventType* = distinct uint32 ## The `type` of an event.
  SDL_Keycode* = distinct uint32 ## A virtual key (`SDLK_*`).
  SDL_Keymod* = distinct uint16 ## Modifier keys (`SDL_KMOD_*`).
  SDL_Scancode* = distinct cint ## A physical key.
  SDL_MouseButtonFlags* = distinct uint32 ## Pressed mouse buttons.
  SDL_MouseWheelDirection* = distinct cint ## Whether the wheel is flipped.
  SDL_AudioFormat* = distinct uint32 ## A sample format.
  SDL_PathType* = distinct cint ## What a path names.

  SDL_DisplayID* = uint32 ## A display.
  SDL_WindowID* = uint32 ## A window, in events.
  SDL_KeyboardID* = uint32 ## A keyboard.
  SDL_MouseID* = uint32 ## A mouse; `SDL_TOUCH_MOUSEID` for touch.
  SDL_TouchID* = uint64 ## A touch device.
  SDL_FingerID* = uint64 ## A finger on a touch device.
  SDL_AudioDeviceID* = uint32 ## An audio device.
  SDL_Time* = int64 ## Nanoseconds since 1970-01-01 UTC.

  SDL_Rect* {.importc, header: SdlHeader, bycopy.} = object
    ## A rectangle in integer pixels.
    x*, y*, w*, h*: cint

  SDL_FRect* {.importc, header: SdlHeader, bycopy.} = object
    ## A rectangle in float pixels.
    x*, y*, w*, h*: cfloat

  SDL_FPoint* {.importc, header: SdlHeader, bycopy.} = object
    ## A point in float pixels.
    x*, y*: cfloat

  SDL_Color* {.importc, header: SdlHeader, bycopy.} = object
    ## A colour, 0..255 per channel.
    r*, g*, b*, a*: uint8

  SDL_FColor* {.importc, header: SdlHeader, bycopy.} = object
    ## A colour, 0..1 per channel.
    r*, g*, b*, a*: cfloat

  SDL_Vertex* {.importc, header: SdlHeader, bycopy.} = object
    ## A vertex for `SDL_RenderGeometry`.
    position*: SDL_FPoint
    color*: SDL_FColor
    tex_coord*: SDL_FPoint

  SDL_Surface* {.importc, header: SdlHeader, bycopy.} = object
    ## Pixels in memory. Its fields are read only.
    flags*: SDL_SurfaceFlags
    format*: SDL_PixelFormat
    w*, h*: cint
    pitch*: cint
    pixels*: nil pointer
    refcount*: cint
    reserved*: nil pointer

  SDL_AudioSpec* {.importc, header: SdlHeader, bycopy.} = object
    ## The format of audio data.
    format*: SDL_AudioFormat
    channels*: cint
    freq*: cint

  SDL_PathInfo* {.importc, header: SdlHeader, bycopy.} = object
    ## What `SDL_GetPathInfo` finds at a path.
    `type`*: SDL_PathType
    size*: uint64
    create_time*: SDL_Time
    modify_time*: SDL_Time
    access_time*: SDL_Time

  SDL_AudioStreamCallback* = proc (userdata: nil pointer;
      stream: SDL_AudioStream; additional_amount, total_amount: cint) {.cdecl.}
    ## Called when a stream needs or has data.

  SDL_CommonEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## The fields every event has; also the app lifecycle events.
    `type`*: uint32
    reserved*: uint32
    timestamp*: uint64

  SDL_QuitEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## `SDL_EVENT_QUIT`.
    `type`*: SDL_EventType
    reserved*: uint32
    timestamp*: uint64

  SDL_WindowEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## `SDL_EVENT_WINDOW_*`.
    `type`*: SDL_EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: SDL_WindowID
    data1*: int32
    data2*: int32

  SDL_KeyboardEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## `SDL_EVENT_KEY_DOWN` and `SDL_EVENT_KEY_UP`.
    `type`*: SDL_EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: SDL_WindowID
    which*: SDL_KeyboardID
    scancode*: SDL_Scancode
    key*: SDL_Keycode
    `mod`*: SDL_Keymod
    raw*: uint16
    down*: bool
    repeat*: bool

  SDL_MouseMotionEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## `SDL_EVENT_MOUSE_MOTION`.
    `type`*: SDL_EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: SDL_WindowID
    which*: SDL_MouseID
    state*: SDL_MouseButtonFlags
    x*, y*: cfloat
    xrel*, yrel*: cfloat

  SDL_MouseButtonEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## `SDL_EVENT_MOUSE_BUTTON_DOWN` and `SDL_EVENT_MOUSE_BUTTON_UP`.
    `type`*: SDL_EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: SDL_WindowID
    which*: SDL_MouseID
    button*: uint8
    down*: bool
    clicks*: uint8
    padding*: uint8
    x*, y*: cfloat

  SDL_MouseWheelEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## `SDL_EVENT_MOUSE_WHEEL`.
    `type`*: SDL_EventType
    reserved*: uint32
    timestamp*: uint64
    windowID*: SDL_WindowID
    which*: SDL_MouseID
    x*, y*: cfloat
    direction*: SDL_MouseWheelDirection
    mouse_x*, mouse_y*: cfloat
    integer_x*, integer_y*: int32

  SDL_TouchFingerEvent* {.importc, header: SdlHeader, bycopy.} = object
    ## `SDL_EVENT_FINGER_DOWN`, `_UP` and `_MOTION`; x and y are in 0..1.
    `type`*: SDL_EventType
    reserved*: uint32
    timestamp*: uint64
    touchID*: SDL_TouchID
    fingerID*: SDL_FingerID
    x*, y*: cfloat
    dx*, dy*: cfloat
    pressure*: cfloat
    windowID*: SDL_WindowID

  SDL_Event* {.importc, header: SdlHeader, union, bycopy.} = object
    ## Any event; `type` says which member is valid. Only the members
    ## nimkivy reads are declared; `padding` gives the union its full size.
    `type`*: uint32
    common*: SDL_CommonEvent
    window*: SDL_WindowEvent
    key*: SDL_KeyboardEvent
    motion*: SDL_MouseMotionEvent
    button*: SDL_MouseButtonEvent
    wheel*: SDL_MouseWheelEvent
    quit*: SDL_QuitEvent
    tfinger*: SDL_TouchFingerEvent
    padding*: array[128, uint8]

# Comparison and bit operations of the distinct types.
proc `==`*(a, b: SDL_InitFlags): bool {.borrow.}
proc `or`*(a, b: SDL_InitFlags): SDL_InitFlags {.borrow.}
proc `==`*(a, b: SDL_WindowFlags): bool {.borrow.}
proc `or`*(a, b: SDL_WindowFlags): SDL_WindowFlags {.borrow.}
proc `==`*(a, b: SDL_BlendMode): bool {.borrow.}
proc `==`*(a, b: SDL_BlendOperation): bool {.borrow.}
proc `==`*(a, b: SDL_BlendFactor): bool {.borrow.}
proc `==`*(a, b: SDL_PixelFormat): bool {.borrow.}
proc `==`*(a, b: SDL_TextureAccess): bool {.borrow.}
proc `==`*(a, b: SDL_ScaleMode): bool {.borrow.}
proc `==`*(a, b: SDL_SurfaceFlags): bool {.borrow.}
proc `==`*(a, b: SDL_EventType): bool {.borrow.}
proc `==`*(a, b: SDL_Keycode): bool {.borrow.}
proc `==`*(a, b: SDL_Keymod): bool {.borrow.}
proc `or`*(a, b: SDL_Keymod): SDL_Keymod {.borrow.}
proc `and`*(a, b: SDL_Keymod): SDL_Keymod {.borrow.}
proc `==`*(a, b: SDL_Scancode): bool {.borrow.}
proc `==`*(a, b: SDL_MouseButtonFlags): bool {.borrow.}
proc `and`*(a, b: SDL_MouseButtonFlags): SDL_MouseButtonFlags {.borrow.}
proc `==`*(a, b: SDL_MouseWheelDirection): bool {.borrow.}
proc `==`*(a, b: SDL_AudioFormat): bool {.borrow.}
proc `==`*(a, b: SDL_PathType): bool {.borrow.}

const
  SDL_INIT_AUDIO* = SDL_InitFlags(0x00000010'u32)
  SDL_INIT_VIDEO* = SDL_InitFlags(0x00000020'u32)
  SDL_INIT_EVENTS* = SDL_InitFlags(0x00004000'u32)

  SDL_HINT_TOUCH_MOUSE_EVENTS* = cstring"SDL_TOUCH_MOUSE_EVENTS"
  SDL_HINT_ANDROID_TRAP_BACK_BUTTON* = cstring"SDL_ANDROID_TRAP_BACK_BUTTON"

  SDL_WINDOW_FULLSCREEN* = SDL_WindowFlags(0x0000000000000001'u64)
  SDL_WINDOW_HIDDEN* = SDL_WindowFlags(0x0000000000000008'u64)
  SDL_WINDOW_BORDERLESS* = SDL_WindowFlags(0x0000000000000010'u64)
  SDL_WINDOW_RESIZABLE* = SDL_WindowFlags(0x0000000000000020'u64)
  SDL_WINDOW_HIGH_PIXEL_DENSITY* = SDL_WindowFlags(0x0000000000002000'u64)

  SDL_BLENDMODE_NONE* = SDL_BlendMode(0x00000000'u32)
  SDL_BLENDMODE_BLEND* = SDL_BlendMode(0x00000001'u32)
  SDL_BLENDMODE_BLEND_PREMULTIPLIED* = SDL_BlendMode(0x00000010'u32)
  SDL_BLENDMODE_ADD* = SDL_BlendMode(0x00000002'u32)
  SDL_BLENDMODE_ADD_PREMULTIPLIED* = SDL_BlendMode(0x00000020'u32)
  SDL_BLENDMODE_MOD* = SDL_BlendMode(0x00000004'u32)
  SDL_BLENDMODE_MUL* = SDL_BlendMode(0x00000008'u32)
  SDL_BLENDMODE_INVALID* = SDL_BlendMode(0x7FFFFFFF'u32)

  SDL_BLENDOPERATION_ADD* = SDL_BlendOperation(0x1)
  SDL_BLENDOPERATION_SUBTRACT* = SDL_BlendOperation(0x2)
  SDL_BLENDOPERATION_REV_SUBTRACT* = SDL_BlendOperation(0x3)
  SDL_BLENDOPERATION_MINIMUM* = SDL_BlendOperation(0x4)
  SDL_BLENDOPERATION_MAXIMUM* = SDL_BlendOperation(0x5)

  SDL_BLENDFACTOR_ZERO* = SDL_BlendFactor(0x1)
  SDL_BLENDFACTOR_ONE* = SDL_BlendFactor(0x2)
  SDL_BLENDFACTOR_SRC_COLOR* = SDL_BlendFactor(0x3)
  SDL_BLENDFACTOR_ONE_MINUS_SRC_COLOR* = SDL_BlendFactor(0x4)
  SDL_BLENDFACTOR_SRC_ALPHA* = SDL_BlendFactor(0x5)
  SDL_BLENDFACTOR_ONE_MINUS_SRC_ALPHA* = SDL_BlendFactor(0x6)
  SDL_BLENDFACTOR_DST_COLOR* = SDL_BlendFactor(0x7)
  SDL_BLENDFACTOR_ONE_MINUS_DST_COLOR* = SDL_BlendFactor(0x8)
  SDL_BLENDFACTOR_DST_ALPHA* = SDL_BlendFactor(0x9)
  SDL_BLENDFACTOR_ONE_MINUS_DST_ALPHA* = SDL_BlendFactor(0xA)

  SDL_PIXELFORMAT_UNKNOWN* = SDL_PixelFormat(0'u32)
  SDL_PIXELFORMAT_RGB24* = SDL_PixelFormat(0x17101803'u32)
  SDL_PIXELFORMAT_ARGB8888* = SDL_PixelFormat(0x16362004'u32)
  SDL_PIXELFORMAT_RGBA8888* = SDL_PixelFormat(0x16462004'u32)
  SDL_PIXELFORMAT_ABGR8888* = SDL_PixelFormat(0x16762004'u32)
  SDL_PIXELFORMAT_BGRA8888* = SDL_PixelFormat(0x16862004'u32)

when defined(bigEndian):
  const
    SDL_PIXELFORMAT_RGBA32* = SDL_PIXELFORMAT_RGBA8888 ## Bytes R, G, B, A.
    SDL_PIXELFORMAT_ARGB32* = SDL_PIXELFORMAT_ARGB8888 ## Bytes A, R, G, B.
    SDL_PIXELFORMAT_BGRA32* = SDL_PIXELFORMAT_BGRA8888 ## Bytes B, G, R, A.
    SDL_PIXELFORMAT_ABGR32* = SDL_PIXELFORMAT_ABGR8888 ## Bytes A, B, G, R.
else:
  const
    SDL_PIXELFORMAT_RGBA32* = SDL_PIXELFORMAT_ABGR8888 ## Bytes R, G, B, A.
    SDL_PIXELFORMAT_ARGB32* = SDL_PIXELFORMAT_BGRA8888 ## Bytes A, R, G, B.
    SDL_PIXELFORMAT_BGRA32* = SDL_PIXELFORMAT_ARGB8888 ## Bytes B, G, R, A.
    SDL_PIXELFORMAT_ABGR32* = SDL_PIXELFORMAT_RGBA8888 ## Bytes A, B, G, R.

const
  SDL_TEXTUREACCESS_STATIC* = SDL_TextureAccess(0)
  SDL_TEXTUREACCESS_STREAMING* = SDL_TextureAccess(1)
  SDL_TEXTUREACCESS_TARGET* = SDL_TextureAccess(2)

  SDL_SCALEMODE_INVALID* = SDL_ScaleMode(-1)
  SDL_SCALEMODE_NEAREST* = SDL_ScaleMode(0)
  SDL_SCALEMODE_LINEAR* = SDL_ScaleMode(1)
  SDL_SCALEMODE_PIXELART* = SDL_ScaleMode(2)

  SDL_EVENT_QUIT* = SDL_EventType(0x100'u32)
  SDL_EVENT_TERMINATING* = SDL_EventType(0x101'u32)
  SDL_EVENT_WILL_ENTER_BACKGROUND* = SDL_EventType(0x103'u32)
  SDL_EVENT_DID_ENTER_BACKGROUND* = SDL_EventType(0x104'u32)
  SDL_EVENT_WILL_ENTER_FOREGROUND* = SDL_EventType(0x105'u32)
  SDL_EVENT_DID_ENTER_FOREGROUND* = SDL_EventType(0x106'u32)
  SDL_EVENT_WINDOW_EXPOSED* = SDL_EventType(0x204'u32)
  SDL_EVENT_WINDOW_RESIZED* = SDL_EventType(0x206'u32)
  SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED* = SDL_EventType(0x207'u32)
  SDL_EVENT_WINDOW_RESTORED* = SDL_EventType(0x20B'u32)
  SDL_EVENT_WINDOW_CLOSE_REQUESTED* = SDL_EventType(0x210'u32)
  SDL_EVENT_KEY_DOWN* = SDL_EventType(0x300'u32)
  SDL_EVENT_KEY_UP* = SDL_EventType(0x301'u32)
  SDL_EVENT_MOUSE_MOTION* = SDL_EventType(0x400'u32)
  SDL_EVENT_MOUSE_BUTTON_DOWN* = SDL_EventType(0x401'u32)
  SDL_EVENT_MOUSE_BUTTON_UP* = SDL_EventType(0x402'u32)
  SDL_EVENT_MOUSE_WHEEL* = SDL_EventType(0x403'u32)
  SDL_EVENT_FINGER_DOWN* = SDL_EventType(0x700'u32)
  SDL_EVENT_FINGER_UP* = SDL_EventType(0x701'u32)
  SDL_EVENT_FINGER_MOTION* = SDL_EventType(0x702'u32)

  SDL_TOUCH_MOUSEID* = SDL_MouseID(0xFFFFFFFF'u32) ## `(SDL_MouseID)-1`

  SDL_BUTTON_LEFT* = 1'u8
  SDL_BUTTON_MIDDLE* = 2'u8
  SDL_BUTTON_RIGHT* = 3'u8

  SDL_MOUSEWHEEL_NORMAL* = SDL_MouseWheelDirection(0)
  SDL_MOUSEWHEEL_FLIPPED* = SDL_MouseWheelDirection(1)

  # The keys Kivy's window_sdl2.py maps (key_map and command_keys).
  SDLK_RETURN* = SDL_Keycode(0x0000000d'u32)
  SDLK_ESCAPE* = SDL_Keycode(0x0000001b'u32)
  SDLK_BACKSPACE* = SDL_Keycode(0x00000008'u32)
  SDLK_TAB* = SDL_Keycode(0x00000009'u32)
  SDLK_DELETE* = SDL_Keycode(0x0000007f'u32)
  SDLK_CAPSLOCK* = SDL_Keycode(0x40000039'u32)
  SDLK_F1* = SDL_Keycode(0x4000003a'u32)
  SDLK_F2* = SDL_Keycode(0x4000003b'u32)
  SDLK_F3* = SDL_Keycode(0x4000003c'u32)
  SDLK_F4* = SDL_Keycode(0x4000003d'u32)
  SDLK_F5* = SDL_Keycode(0x4000003e'u32)
  SDLK_F6* = SDL_Keycode(0x4000003f'u32)
  SDLK_F7* = SDL_Keycode(0x40000040'u32)
  SDLK_F8* = SDL_Keycode(0x40000041'u32)
  SDLK_F9* = SDL_Keycode(0x40000042'u32)
  SDLK_F10* = SDL_Keycode(0x40000043'u32)
  SDLK_F11* = SDL_Keycode(0x40000044'u32)
  SDLK_F12* = SDL_Keycode(0x40000045'u32)
  SDLK_INSERT* = SDL_Keycode(0x40000049'u32)
  SDLK_HOME* = SDL_Keycode(0x4000004a'u32)
  SDLK_PAGEUP* = SDL_Keycode(0x4000004b'u32)
  SDLK_END* = SDL_Keycode(0x4000004d'u32)
  SDLK_PAGEDOWN* = SDL_Keycode(0x4000004e'u32)
  SDLK_RIGHT* = SDL_Keycode(0x4000004f'u32)
  SDLK_LEFT* = SDL_Keycode(0x40000050'u32)
  SDLK_DOWN* = SDL_Keycode(0x40000051'u32)
  SDLK_UP* = SDL_Keycode(0x40000052'u32)
  SDLK_NUMLOCKCLEAR* = SDL_Keycode(0x40000053'u32)
  SDLK_KP_DIVIDE* = SDL_Keycode(0x40000054'u32)
  SDLK_KP_MULTIPLY* = SDL_Keycode(0x40000055'u32)
  SDLK_KP_MINUS* = SDL_Keycode(0x40000056'u32)
  SDLK_KP_PLUS* = SDL_Keycode(0x40000057'u32)
  SDLK_KP_ENTER* = SDL_Keycode(0x40000058'u32)
  SDLK_KP_1* = SDL_Keycode(0x40000059'u32)
  SDLK_KP_2* = SDL_Keycode(0x4000005a'u32)
  SDLK_KP_3* = SDL_Keycode(0x4000005b'u32)
  SDLK_KP_4* = SDL_Keycode(0x4000005c'u32)
  SDLK_KP_5* = SDL_Keycode(0x4000005d'u32)
  SDLK_KP_6* = SDL_Keycode(0x4000005e'u32)
  SDLK_KP_7* = SDL_Keycode(0x4000005f'u32)
  SDLK_KP_8* = SDL_Keycode(0x40000060'u32)
  SDLK_KP_9* = SDL_Keycode(0x40000061'u32)
  SDLK_KP_0* = SDL_Keycode(0x40000062'u32)
  SDLK_KP_PERIOD* = SDL_Keycode(0x40000063'u32)
  SDLK_F13* = SDL_Keycode(0x40000068'u32)
  SDLK_F14* = SDL_Keycode(0x40000069'u32)
  SDLK_F15* = SDL_Keycode(0x4000006a'u32)
  SDLK_LCTRL* = SDL_Keycode(0x400000e0'u32)
  SDLK_LSHIFT* = SDL_Keycode(0x400000e1'u32)
  SDLK_LALT* = SDL_Keycode(0x400000e2'u32)
  SDLK_LGUI* = SDL_Keycode(0x400000e3'u32)
  SDLK_RCTRL* = SDL_Keycode(0x400000e4'u32)
  SDLK_RSHIFT* = SDL_Keycode(0x400000e5'u32)
  SDLK_RALT* = SDL_Keycode(0x400000e6'u32)
  SDLK_AC_BACK* = SDL_Keycode(0x4000011a'u32) ## The Android back button.

  SDL_KMOD_NONE* = SDL_Keymod(0x0000'u16)
  SDL_KMOD_LSHIFT* = SDL_Keymod(0x0001'u16)
  SDL_KMOD_RSHIFT* = SDL_Keymod(0x0002'u16)
  SDL_KMOD_LCTRL* = SDL_Keymod(0x0040'u16)
  SDL_KMOD_RCTRL* = SDL_Keymod(0x0080'u16)
  SDL_KMOD_LALT* = SDL_Keymod(0x0100'u16)
  SDL_KMOD_RALT* = SDL_Keymod(0x0200'u16)
  SDL_KMOD_LGUI* = SDL_Keymod(0x0400'u16)
  SDL_KMOD_RGUI* = SDL_Keymod(0x0800'u16)
  SDL_KMOD_NUM* = SDL_Keymod(0x1000'u16)
  SDL_KMOD_CAPS* = SDL_Keymod(0x2000'u16)
  SDL_KMOD_MODE* = SDL_Keymod(0x4000'u16)

  SDL_AUDIO_U8* = SDL_AudioFormat(0x0008'u32)
  SDL_AUDIO_S16* = SDL_AudioFormat(0x8010'u32) ## Native byte order.
  SDL_AUDIO_S32* = SDL_AudioFormat(0x8020'u32) ## Native byte order.
  SDL_AUDIO_F32* = SDL_AudioFormat(0x8120'u32) ## Native byte order.
  SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK* = SDL_AudioDeviceID(0xFFFFFFFF'u32)

  SDL_PATHTYPE_FILE* = SDL_PathType(1)
  SDL_PATHTYPE_DIRECTORY* = SDL_PathType(2)

{.push cdecl, importc, header: SdlHeader.}

# Init, errors, hints, memory.
proc SDL_Init*(flags: SDL_InitFlags): bool
  ## Initializes the subsystems in `flags`.
proc SDL_Quit*()
  ## Shuts down every subsystem.
proc SDL_WasInit*(flags: SDL_InitFlags): SDL_InitFlags
  ## Which of the subsystems in `flags` are initialized (0: none).
proc SDL_GetError*(): cstring
  ## The message of the last error on this thread.
proc SDL_SetHint*(name: cstring; value: nil cstring): bool
  ## Sets a configuration hint (`SDL_HINT_*`).
proc SDL_free*(mem: nil pointer)
  ## Frees memory SDL allocated.

# Windows and displays.
proc SDL_CreateWindow*(title: cstring; w, h: cint;
    flags: SDL_WindowFlags): nil SDL_Window
  ## A new window, or nil on failure.
proc SDL_DestroyWindow*(window: SDL_Window)
  ## Destroys a window.
proc SDL_SetWindowTitle*(window: SDL_Window; title: cstring): bool
  ## Sets the title of a window.
proc SDL_GetWindowSize*(window: SDL_Window; w, h: nil ptr cint): bool
  ## The size of the window's client area in window coordinates.
proc SDL_SetWindowSize*(window: SDL_Window; w, h: cint): bool
  ## Requests a new size of the window's client area.
proc SDL_GetWindowSizeInPixels*(window: SDL_Window;
    w, h: nil ptr cint): bool
  ## The size of the window's drawable area in pixels.
proc SDL_GetWindowDisplayScale*(window: SDL_Window): cfloat
  ## Pixel density times content scale of the window; 0 on failure.
proc SDL_GetDisplayForWindow*(window: SDL_Window): SDL_DisplayID
  ## The display holding the window's centre; 0 on failure.
proc SDL_GetDisplayContentScale*(displayID: SDL_DisplayID): cfloat
  ## The display's content scale (the desktop's UI scale); 0 on failure.

# Renderer.
proc SDL_CreateRenderer*(window: SDL_Window; name: nil cstring): nil SDL_Renderer
  ## A renderer for the window (`name` nil picks one), or nil on failure.
proc SDL_DestroyRenderer*(renderer: SDL_Renderer)
  ## Destroys a renderer and its textures.
proc SDL_SetRenderDrawColorFloat*(renderer: SDL_Renderer;
    r, g, b, a: cfloat): bool
  ## Sets the colour of clear and line operations.
proc SDL_SetRenderDrawBlendMode*(renderer: SDL_Renderer;
    blendMode: SDL_BlendMode): bool
  ## Sets the blend mode of draw operations.
proc SDL_GetCurrentRenderOutputSize*(renderer: SDL_Renderer;
    w, h: nil ptr cint): bool
  ## The size in pixels of the current target: the window or a texture.
proc SDL_RenderClear*(renderer: SDL_Renderer): bool
  ## Fills the target with the draw colour, ignoring the clip rectangle.
proc SDL_RenderPresent*(renderer: SDL_Renderer): bool
  ## Shows what was drawn since the last present.
proc SDL_RenderGeometry*(renderer: SDL_Renderer; texture: nil SDL_Texture;
    vertices: ptr SDL_Vertex; num_vertices: cint;
    indices: nil ptr cint; num_indices: cint): bool
  ## Draws triangles, optionally textured and indexed.
proc SDL_RenderLines*(renderer: SDL_Renderer; points: ptr SDL_FPoint;
    count: cint): bool
  ## Draws a polyline in the draw colour.
proc SDL_RenderTexture*(renderer: SDL_Renderer; texture: SDL_Texture;
    srcrect, dstrect: nil ptr SDL_FRect): bool
  ## Copies part of a texture (nil: all) to part of the target (nil: all).
proc SDL_RenderTexture9Grid*(renderer: SDL_Renderer; texture: SDL_Texture;
    srcrect: nil ptr SDL_FRect; left_width, right_width, top_height,
    bottom_height, scale: cfloat; dstrect: nil ptr SDL_FRect): bool
  ## Copies a texture with fixed corners and stretched edges and centre.
proc SDL_SetRenderClipRect*(renderer: SDL_Renderer;
    rect: nil ptr SDL_Rect): bool
  ## Sets the clip rectangle; nil turns clipping off.
proc SDL_SetRenderTarget*(renderer: SDL_Renderer;
    texture: nil SDL_Texture): bool
  ## Draws into a target texture from now on; nil draws to the window.
proc SDL_RenderReadPixels*(renderer: SDL_Renderer;
    rect: nil ptr SDL_Rect): nil ptr SDL_Surface
  ## A new surface with the target's pixels (nil rect: all), or nil.

# Textures and surfaces.
proc SDL_CreateTexture*(renderer: SDL_Renderer; format: SDL_PixelFormat;
    access: SDL_TextureAccess; w, h: cint): nil SDL_Texture
  ## A new texture, or nil on failure.
proc SDL_CreateTextureFromSurface*(renderer: SDL_Renderer;
    surface: ptr SDL_Surface): nil SDL_Texture
  ## A new static texture with the surface's pixels, or nil on failure.
proc SDL_DestroyTexture*(texture: SDL_Texture)
  ## Destroys a texture.
proc SDL_GetTextureSize*(texture: SDL_Texture; w, h: nil ptr cfloat): bool
  ## The size of a texture in pixels.
proc SDL_SetTextureBlendMode*(texture: SDL_Texture;
    blendMode: SDL_BlendMode): bool
  ## Sets how the texture is blended onto the target.
proc SDL_SetTextureColorModFloat*(texture: SDL_Texture; r, g, b: cfloat): bool
  ## Sets the colour the texture's colour is multiplied by.
proc SDL_SetTextureAlphaModFloat*(texture: SDL_Texture; alpha: cfloat): bool
  ## Sets the value the texture's alpha is multiplied by.
proc SDL_SetTextureScaleMode*(texture: SDL_Texture;
    scaleMode: SDL_ScaleMode): bool
  ## Sets the filtering of a scaled texture.
proc SDL_ComposeCustomBlendMode*(srcColorFactor, dstColorFactor: SDL_BlendFactor;
    colorOperation: SDL_BlendOperation;
    srcAlphaFactor, dstAlphaFactor: SDL_BlendFactor;
    alphaOperation: SDL_BlendOperation): SDL_BlendMode
  ## A blend mode `dst = src * srcFactor <op> dst * dstFactor`.
proc SDL_ConvertSurface*(surface: ptr SDL_Surface;
    format: SDL_PixelFormat): nil ptr SDL_Surface
  ## A new surface with the pixels in another format, or nil on failure.
proc SDL_DestroySurface*(surface: ptr SDL_Surface)
  ## Frees a surface.
proc SDL_CreateSurface*(width, height: cint;
    format: SDL_PixelFormat): nil ptr SDL_Surface
  ## A new surface with zeroed pixels, or nil on failure.
proc SDL_BlitSurface*(src: ptr SDL_Surface; srcrect: nil ptr SDL_Rect;
    dst: ptr SDL_Surface; dstrect: nil ptr SDL_Rect): bool
  ## Copies `src` onto `dst` at `dstrect`'s position, clipped, with `src`'s
  ## blend mode and alpha modulation.
proc SDL_SetSurfaceBlendMode*(surface: ptr SDL_Surface;
    blendMode: SDL_BlendMode): bool
  ## Sets how the surface is blended when blitted.
proc SDL_SetSurfaceAlphaMod*(surface: ptr SDL_Surface; alpha: uint8): bool
  ## Sets an alpha multiplier applied when the surface is blitted.

# Events.
proc SDL_PollEvent*(event: nil ptr SDL_Event): bool
  ## Takes the next pending event into `event`; false if there is none.
proc SDL_WaitEvent*(event: nil ptr SDL_Event): bool
  ## Waits for the next event and takes it into `event` (nil: leaves it
  ## queued); false on error.
proc SDL_PushEvent*(event: ptr SDL_Event): bool
  ## Adds an event to the queue; false if it was filtered out or on error.
proc SDL_WaitEventTimeout*(event: nil ptr SDL_Event; timeoutMS: int32): bool
  ## Waits up to `timeoutMS` (-1: forever) for an event; false on timeout.

# Audio.
proc SDL_LoadWAV*(path: cstring; spec: ptr SDL_AudioSpec;
    audio_buf: ptr (nil ptr uint8); audio_len: ptr uint32): bool
  ## Loads a WAV file; free `audio_buf` with `SDL_free`.
proc SDL_PutAudioStreamData*(stream: SDL_AudioStream; buf: pointer;
    len: cint): bool
  ## Queues `len` bytes of audio.
proc SDL_FlushAudioStream*(stream: SDL_AudioStream): bool
  ## Marks the end of the data put so far: what the resampler holds back
  ## waiting for more is converted and made available.
proc SDL_GetAudioStreamQueued*(stream: SDL_AudioStream): cint
  ## The bytes still queued; -1 on failure.
proc SDL_ClearAudioStream*(stream: SDL_AudioStream): bool
  ## Drops all queued audio.
proc SDL_OpenAudioDeviceStream*(devid: SDL_AudioDeviceID;
    spec: nil ptr SDL_AudioSpec; callback: nil SDL_AudioStreamCallback;
    userdata: nil pointer): nil SDL_AudioStream
  ## A stream bound to a newly opened device, paused; nil on failure.
proc SDL_ResumeAudioStreamDevice*(stream: SDL_AudioStream): bool
  ## Starts or resumes playback of the stream's device.
proc SDL_PauseAudioStreamDevice*(stream: SDL_AudioStream): bool
  ## Pauses playback of the stream's device.
proc SDL_SetAudioStreamGain*(stream: SDL_AudioStream; gain: cfloat): bool
  ## Sets the volume, 1 for unchanged.
proc SDL_DestroyAudioStream*(stream: SDL_AudioStream)
  ## Closes a stream and the device it opened.

# I/O streams.
proc SDL_IOFromFile*(file, mode: cstring): nil SDL_IOStream
  ## A stream on a file opened in `mode` ("rb": read), or nil on failure.
proc SDL_CloseIO*(context: SDL_IOStream): bool
  ## Closes a stream and frees it.
proc SDL_LoadFile*(file: cstring; datasize: ptr csize_t): nil pointer
  ## The whole of a file (with a 0 byte after it), its size in `datasize`;
  ## nil on failure. Free it with `SDL_free`. A relative path is read from
  ## the APK's assets on Android.

# Filesystem.
proc SDL_GetBasePath*(): nil cstring
  ## The folder of the program, ending in a separator (on Android "./", the
  ## root of the APK's assets); nil on failure. SDL owns it.
proc SDL_GetPathInfo*(path: cstring; info: nil ptr SDL_PathInfo): bool
  ## Fills `info` for what `path` names; false if nothing does. A relative
  ## path is looked up in the APK's assets on Android.
proc SDL_GetCurrentDirectory*(): nil cstring
  ## The current working directory, ending in a separator; nil on failure.
  ## Free it with `SDL_free`.

# Time.
proc SDL_GetTicksNS*(): uint64
  ## Nanoseconds since SDL was initialized (a monotonic clock).
proc SDL_DelayPrecise*(ns: uint64)
  ## Waits `ns` nanoseconds, as precisely as the platform allows.

{.pop.}
