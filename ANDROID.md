# Android build notes (not built, not tested)

Phase 1 runs and is tested on the Linux desktop only (LAYERS.md, layer 10:
"no tablet testing for now"). This file lists what a later Android build of
a nimkivy app (first the kiosk) needs. Nothing here has been built or run on
Android. Every step is marked:

- **known**: true on this machine or in the code today;
- **untested**: what the SDL3, NDK and Nimony documentation or sources say
  should work, not tried.

## 1. Toolchain

- **untested** Android NDK r27 or later (its clang), Android SDK with
  platform 34+ and build-tools, a JDK 17, Gradle (the wrapper in SDL's
  template). None of these is installed on this machine (**known**: no
  `ANDROID_HOME`, no NDK).
- **untested** SDL3 3.4.x, SDL3_ttf 3.2.x and SDL3_image 3.4.x built for
  Android from source, for each ABI, as shared libraries (`libSDL3.so`,
  `libSDL3_ttf.so`, `libSDL3_image.so`). SDL3_ttf needs its FreeType and
  HarfBuzz (vendored in its `external/`); SDL3_image needs only its built-in
  PNG and JPEG decoders (stb_image) for the kiosk's photos. On the desktop
  these are Fedora's SDL3 3.4.20, SDL3_ttf 3.2.2 and SDL3_image 3.4.8
  (**known**); the same versions on Android keep the text metrics of the
  `label` trace (GAP: SDL_ttf version).

## 2. Compiling the Nim code

- **untested** Nimony cross-compiles with `--os:android` and `--cpu:arm64`
  (64-bit, `arm64-v8a`) or `--cpu:arm` (32-bit, `armeabi-v7a`); Nimony's
  `lib/platform.nim` knows `osAndroid`, `cpuArm` and `cpuArm64`, and
  `defined(android)` selects nimkivy's Android branches (**known**: the code
  compiles them only on Android, so they have never been compiled).
- **untested** The C compiler is the NDK's clang for the ABI and API level,
  given with `--cc:` (for example
  `$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android24-clang`
  and `armv7a-linux-androideabi24-clang`). The SDL headers for the target
  come with `--passC:-I<sdl3 include dir>` and the libraries with
  `--passL:-L<libs for the ABI>`; `--passC` and `--passL` exist in Nimony
  (`src/nimony/nimony.nim`) but are not in `--help` (**known**).
- **untested** The output is a shared library: `--app:lib -o:libmain.so`.
  SDLActivity loads `libmain.so` and calls its `SDL_main`. The app module
  must export it: `proc SDL_main(argc: cint; argv: ptr UncheckedArray[cstring]): cint
  {.exportc, cdecl.}`, which runs the module's top level (Nimony's
  equivalent of `NimMain`; how a `--app:lib` build runs module
  initialisation is not checked) and then `App.run`. On the desktop the
  program's own `main` runs instead.
- **untested** The 32-bit build: whether `--cpu:arm` alone gives a 32-bit
  `int` or `--bits:32` is also needed. nimkivy uses `int` for sizes and
  `float` (64-bit) for geometry, so nothing depends on 64-bit `int`.
- **known** Link flags: `sdl3/sdl.nim`, `sdl3/ttf.nim` and `sdl3/image.nim`
  pass `-lSDL3`, `-lSDL3_ttf`, `-lSDL3_image`. Android also needs `-llog`
  and `-landroid` if anything calls the NDK directly (nimkivy does not).
- **untested** `--mm:orc` as on the desktop (widgets and closures form
  cycles).

## 3. The Android project

- **untested** SDL3's `android-project/` template (in the SDL source tree):
  copy it, put the `.so` files in `app/src/main/jniLibs/<abi>/`
  (`arm64-v8a`, `armeabi-v7a`), and list the libraries in
  `SDLActivity.getLibraries()` (`SDL3`, `SDL3_ttf`, `SDL3_image`, `main`).
  The template builds with Gradle; no `Android.mk` or CMake is needed for
  prebuilt libraries.
- **untested** The manifest: landscape orientation, `android:screenOrientation`
  as the kiosk wants, no `INTERNET` permission unless needed.
- **untested** Keep the screen on: `getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)`
  in a small `SDLActivity` subclass (`onCreate`), or `android:keepScreenOn`
  on the layout. SDL3 does this itself only while
  `SDL_HINT_VIDEO_ALLOW_SCREENSAVER` is false and a window is open
  (SDL's default disables the screensaver; check that it keeps the screen
  on).
- **untested** Immersive full screen (no status and navigation bars):
  nimkivy opens the window with `SDL_WINDOW_FULLSCREEN` on Android
  (**known**: `window_sdl3.createWindow`), which SDLActivity turns into
  immersive mode. Kiosk mode proper (screen pinning, a device-owner
  launcher) is set up on the tablet, not in the app.

## 4. Assets

- **known** nimkivy opens files by path: `IMG_Load` (core/image),
  `TTF_OpenFont` (core/text/text_sdl3) and `SDL_LoadWAV` (core/audio).
- **untested** On Android these SDL functions open a relative path through
  `SDL_IOFromFile`, which reads it from the APK's `assets/` folder. So the
  photos, fonts and clips can stay in `app/src/main/assets/` (for example
  `assets/data/fonts/Roboto-Regular.ttf`), read through SDL's IOStream, not
  unpacked.
- **known** The lookup before SDL does not go through SDL:
  `resources.resourceFind` checks that a file exists with `std/os`
  (`fileExists`, `dirExists`) and returns an absolute path, and the font
  lookup checks `data/fonts` the same way. Neither can see inside the APK.
  So with the assets left in the APK, `Image.source` and fonts are "not
  found" and never reach SDL (uix/image `setTextureFromResource`,
  core/text `resolveFontName`); only `loadSound` falls back to the name as
  given, which SDL would then find in the assets. Either the app copies its
  assets to its files directory on first start (as python-for-android
  unpacks Kivy apps) and sets `KIVY_DATA_DIR` and the working directory
  there, or the lookup learns to ask SDL (SDL_GetPathInfo, or opening the
  file with SDL_IOFromFile). To decide with the first Android build; a GAP
  if the stdlib is what is missing.
- **untested** The working directory of an Android app is not the APK, so
  relative paths in the app (the kiosk's `photos/...`) work only through
  SDL's asset lookup above.

## 5. Behaviour on Android in the code today

- **known** Back is key 27: `SDL_HINT_ANDROID_TRAP_BACK_BUTTON` is set to 1
  and `SDLK_AC_BACK` maps to 27 (Escape), so `on_keyboard` sees 27 and,
  with `exit_on_escape`, the app closes; the kiosk binds 27 to go back.
  Gap: key 27 that no observer handles is consumed, not moved to the back
  (Kivy: `moveTaskToBack`; PORTING.md, Gaps).
- **known** Every SDL finger is a touch; SDL's mouse events made from
  touches are off (`SDL_HINT_TOUCH_MOUSE_EVENTS` 0).
- **known** Density and dpi come from SDL's display content scale (dpi =
  160 x scale), not Android's `scaledDensity`; the font scale stays 1
  (PORTING.md, Gaps).
- **known** GAP, the on_pause timing: `on_pause` and `on_resume` are
  dispatched when SDL_EVENT_WILL_ENTER_BACKGROUND / DID_ENTER_FOREGROUND is
  read from the queue at the next frame, not in an SDL event filter. SDL
  blocks the app's thread while Android has it paused, so `on_pause` can
  arrive only after the app is back in front (PORTING.md, Gaps). Work that
  must happen before the pause (stopping a voice clip, saving state) is
  therefore not guaranteed to run in time. The kiosk does not save state;
  it stops the voice on `on_pause`, which may come late. Fixing it needs an
  SDL event watch whose callback runs on SDL's thread, which the
  dispatchers are not safe for.
- **known** An `on_pause` that returns false, and `App.stop`, stop the app
  as on the desktop (Kivy calls `finishAndRemoveTask`; PORTING.md, Gaps).
- **known** SDL_EVENT_TERMINATING quits the event loop.
- **untested** Rendering: SDL's renderer on Android is OpenGL ES 2
  (`opengles2`); the reference scenes are compared on the desktop OpenGL
  renderer (decision 8). Kivy's blend mode is set with
  SDL_ComposeCustomBlendMode, which the GLES2 renderer is documented to
  support. The FadeTransition render targets need
  `SDL_TEXTUREACCESS_TARGET`, also supported there.
- **untested** Audio: SDL3's Android audio backend (AAudio, or OpenSL ES
  on old devices). The kiosk's 24 kHz WAV clips are resampled by SDL as on
  the desktop; `play` flushes the stream so the end is seen (layer 9).
- **untested** Logging: nimkivy writes its log lines to stderr, which
  Android discards. To see them in `logcat` they would have to go through
  `SDL_Log` or `__android_log_write`.

## 6. Checks for the first Android build

1. Build `examples/showcase.nim` for `arm64-v8a`, then `armeabi-v7a`.
2. On the tablet: the attract crossfade, the fade between screens, a tap
   and a swipe, the picker, the voice clip to its end (`on_stop`), Back.
3. Home button and back: `on_pause` and `on_resume` in the log (the GAP
   above: note when `on_pause` arrives).
4. Rotation off, screen stays on for longer than the system timeout.
5. Frame time on the tablet with the same scripted run (`tools/profile.sh`
   measures it on the desktop; on Android the frame times would need to go
   to a file in the app's directory).
