# Android build notes (toolchain and libraries built; the app not yet)

Phase 1 runs and is tested on the Linux desktop only (LAYERS.md, layer 10:
"no tablet testing for now"). This file lists what the Android build of a
nimkivy app (first the kiosk) needs. Phase A (2026-11-22) installed the
toolchain, built the SDL libraries and assembled a template APK; no Nim code
has been compiled for Android and nothing has run on a device. Every step is
marked:

- **known**: true on this machine or in the code today;
- **untested**: what the SDL3, NDK and Nimony documentation or sources say
  should work, not tried.

## 0. The device and its ABI

- The kiosk tablet is a Samsung Galaxy Tab A 10.1 (2016), SM-T580/T585, on
  stock Samsung Android 8.1 (API 27). Its Exynos 7870 CPU is 64-bit, but the
  stock firmware is 32-bit userspace (firmware listings for T580UEU4CRK5,
  Android 8.1, report only `armeabi-v7a`/`armeabi`). So the build is
  **`armeabi-v7a` only**; no `arm64-v8a`.
- **untested** Check when the tablet is connected:
  `adb shell getprop ro.product.cpu.abi` must print `armeabi-v7a`. A custom
  64-bit ROM would need `arm64-v8a` instead (rebuild everything below for
  that ABI with `--cpu:arm64`).
- minSdk 26 (the Kivy app's `buildozer.spec`: `android.minapi = 26`) allows
  API 27.

## 1. Toolchain (**known**: installed, user-local, no sudo)

Everything is under `~/Android` (about 4.8 GB with the downloads and builds):

| What | Version | Path | Size | Source |
|---|---|---|---|---|
| JDK | Eclipse Temurin 17.0.21.1+2 | `~/Android/jdk-17.0.21.1+2` | 318 MB | github.com/adoptium/temurin17-binaries (sha256 checked) |
| SDK command-line tools | 23.0 (`commandlinetools-linux-16111833_latest.zip`) | `~/Android/sdk/cmdline-tools/latest` | 173 MB | dl.google.com (sha1 checked) |
| platform-tools (adb) | 37.0.3 | `~/Android/sdk/platform-tools` | 22 MB | sdkmanager |
| SDK platform | android-35 (SDL's template: `compileSdkVersion 35`) | `~/Android/sdk/platforms/android-35` | 132 MB | sdkmanager |
| build-tools | 34.0.0 (AGP 8.7.3's default) | `~/Android/sdk/build-tools/34.0.0` | 151 MB | sdkmanager |
| NDK | r28c, 28.2.13676358 (SDL's template: `ndkVersion`) | `~/Android/sdk/ndk/28.2.13676358` | 2.2 GB | sdkmanager |
| Gradle | 8.12 (the template's wrapper), AGP 8.7.3 | `~/Android/gradle` (`GRADLE_USER_HOME`) | 600 MB | services.gradle.org, Google Maven, Maven Central |

```sh
cd ~/Android
tar xzf downloads/jdk/OpenJDK17U-jdk_x64_linux_hotspot_17.0.21.1_2.tar.gz
mkdir -p sdk/cmdline-tools && cd sdk/cmdline-tools
unzip -q ~/Android/downloads/cmdline-tools/commandlinetools-linux-16111833_latest.zip
mv cmdline-tools latest
export JAVA_HOME=~/Android/jdk-17.0.21.1+2 ANDROID_HOME=~/Android/sdk GRADLE_USER_HOME=~/Android/gradle
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME --licenses
$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager --sdk_root=$ANDROID_HOME \
  "platform-tools" "platforms;android-35" "build-tools;34.0.0" "ndk;28.2.13676358"
```

The host's CMake 4.3.0 and Ninja 1.13.2 build the libraries.

## 2. SDL3, SDL3_ttf, SDL3_image (**known**: built for `armeabi-v7a`)

- The same versions as on the desktop (Fedora's SDL3 3.4.20, SDL3_ttf
  3.2.2, SDL3_image 3.4.8), from the github.com/libsdl-org release tarballs
  (`release-3.4.20`, `release-3.2.2`, `release-3.4.8`), in
  `~/Android/build/src`. The SDL_ttf tarball has no `external/` sources:
  FreeType and HarfBuzz are libsdl-org's forks at the commits the
  `release-3.2.2` tag pins (freetype `9973564c`, VER-2-13-2-SDL; harfbuzz
  `564bf981`, 8.5.0-SDL), unpacked into `external/freetype` and
  `external/harfbuzz`.
- Built with the NDK's CMake toolchain as SDL's `docs/README-android.md`
  ("CMake configuration") describes, Release, `ANDROID_PLATFORM=android-21`
  (the template's), `ANDROID_STL=c++_static`, installed per ABI into
  `~/Android/build/install/armeabi-v7a/{include,lib}`. The script is
  `~/Android/build/scripts/build-sdl-android.sh armeabi-v7a`; its options:
  - SDL3: `-DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TEST_LIBRARY=OFF`.
    Backends: video android; render gpu, ogl_es2, vulkan; audio aaudio,
    opensles.
  - SDL3_ttf: `-DSDLTTF_VENDORED=ON -DSDLTTF_HARFBUZZ=ON
    -DSDLTTF_PLUTOSVG=OFF`. Enabled: harfbuzz, freetype.
  - SDL3_image: `-DSDLIMAGE_VENDORED=OFF -DSDLIMAGE_BACKEND_STB=ON
    -DSDLIMAGE_PNG_LIBPNG=OFF -DSDLIMAGE_AVIF=OFF -DSDLIMAGE_JXL=OFF
    -DSDLIMAGE_TIF=OFF -DSDLIMAGE_WEBP=OFF`. Enabled: stb (PNG, JPEG) and
    the built-in formats.
- Results: `libSDL3.so` (9.2 MB, 1.7 MB stripped in the APK),
  `libSDL3_ttf.so` (15.5 MB, 1.2 MB), `libSDL3_image.so` (0.9 MB, 0.2 MB);
  ELF 32-bit ARM EABI5, sonames `libSDL3*.so`; SDL3_ttf and SDL3_image need
  only `libSDL3.so` and the system's libc, libm, libdl.
- GAP (SDL_ttf version, text metrics): the library versions match the
  desktop, but the desktop's SDL3_ttf uses Fedora's FreeType 2.14.3 and
  HarfBuzz 15.0.0 (and plutosvg), the Android build the vendored FreeType
  2.13.2 and HarfBuzz 8.5.0. Text metrics may differ from the `label`
  trace; to compare on the first Android build.

## 3. Compiling the Nim code (phase B)

- **untested** Nimony cross-compiles with `--os:android --cpu:arm`
  (`armeabi-v7a`). **known** from Nimony's source: `--cpu:arm` is an alias
  of `arm32`, and naming the CPU sets `int` to its 32 bits
  (`nifconfig.setTargetCPU`), so `--bits:32` is not needed; `lib/platform.nim`
  knows `Android`. `defined(android)` selects nimkivy's Android branches
  (**known**: the code compiles them only on Android, so they have never
  been compiled). nimkivy uses `int` for sizes and `float` (64-bit) for
  geometry, so nothing depends on 64-bit `int`.
- **untested** The C compiler is the NDK's clang for the ABI and minSdk,
  given with `--cc:`, the SDL headers with `--passC:` and the libraries with
  `--passL:` (`--passC`/`--passL` exist in `src/nimony/nimony.nim`, not in
  `--help`). The output is a shared library, `--app:lib -o:libmain.so`. For
  the kiosk, from `kiosk/`:

  ```sh
  NDK=~/Android/sdk/ndk/28.2.13676358
  SDLA=~/Android/build/install/armeabi-v7a
  nimony c --mm:orc --os:android --cpu:arm --app:lib \
    --cc:$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/armv7a-linux-androideabi26-clang \
    --passC:-I$SDLA/include --passC:-fPIC --passL:-L$SDLA/lib \
    --path:$HOME/Projects/nimkivy/src --nimcache:nimcache/android-armeabi-v7a \
    -o:libmain.so main.nim
  cp libmain.so ~/Android/build/kiosk-android/app/src/main/jniLibs/armeabi-v7a/
  ```

  **known**: this clang (`armv7a-linux-androideabi26-clang -shared -fPIC
  -I$SDLA/include ... -L$SDLA/lib -lSDL3`) builds the template's C stub
  `YourSourceHere.c` into a `libmain.so` exporting `SDL_main`
  (`~/Android/build/stub-main`).
- **untested** SDLActivity loads `libmain.so` and calls its `SDL_main`. The
  app module must export it: `proc SDL_main(argc: cint; argv: ptr UncheckedArray[cstring]): cint
  {.exportc, cdecl.}`, which runs the module's top level (Nimony's
  equivalent of `NimMain`; how a `--app:lib` build runs module
  initialisation is not checked) and then `App.run`. On the desktop the
  program's own `main` runs instead. Whether Nimony's linker step for
  `--app:lib` passes `-shared` to clang is also not checked.
- **known** Link flags: `sdl3/sdl.nim`, `sdl3/ttf.nim` and `sdl3/image.nim`
  pass `-lSDL3`, `-lSDL3_ttf`, `-lSDL3_image`. Android also needs `-llog`
  and `-landroid` if anything calls the NDK directly (nimkivy does not).
- **untested** `--mm:orc` as on the desktop (widgets and closures form
  cycles).

## 4. The Android project (**known**: skeleton made, debug APK assembled)

- `~/Android/build/kiosk-android`, a copy of SDL 3.4.20's
  `android-project/` (outside the repos), changed as the SDL docs say
  ("Customizing your application name"), with ids from the Kivy app's
  `buildozer.spec` (git `a6e6a34^:kiosk/buildozer.spec`):
  - `app/build.gradle`: `namespace`/`applicationId`
    `gr.philosykos.philosykos_exhibition`, `versionName "0.1.0"`,
    `minSdkVersion 26`, `targetSdkVersion 34`, `compileSdkVersion 35`,
    `abiFilters 'armeabi-v7a'`; no `externalNativeBuild` (the template's
    `app/jni/` is removed): the libraries are prebuilt in
    `app/src/main/jniLibs/armeabi-v7a/` (`libSDL3.so`, `libSDL3_ttf.so`,
    `libSDL3_image.so`, and phase B's `libmain.so`).
  - `KioskActivity extends SDLActivity`
    (`app/src/main/java/gr/philosykos/philosykos_exhibition/`), whose only
    change is `getLibraries()`: `SDL3`, `SDL3_image`, `SDL3_ttf`, `main`.
  - Manifest: the activity is `KioskActivity`,
    `android:screenOrientation="landscape"`, and
    `<meta-data android:name="SDL_ENV.SDL_ORIENTATIONS" android:value="LandscapeLeft"/>`.
    **known** from SDLActivity.java: SDL sets the activity's orientation
    again when the window is created (`setOrientationBis`); without the hint
    a resizable window (Kivy's default `resizable = 1`) gets
    `SCREEN_ORIENTATION_FULL_USER` (any rotation), with `LandscapeLeft` it
    gets `SCREEN_ORIENTATION_LANDSCAPE`. `SDL_ENV.*` meta-data become
    environment variables before `SDL_main`. No `INTERNET` permission.
    App label `PHILOSYKOS` (`res/values/strings.xml`).
  - Keep the screen on: no code of the app's own. **known** from SDL's
    source: SDL disables the screensaver by default, and on Android that
    sets `FLAG_KEEP_SCREEN_ON` on the window
    (`Android_JNI_SuspendScreenSaver`, `COMMAND_SET_KEEP_SCREEN_ON`) once
    the video subsystem is up. **untested** on the tablet (section 7, check 4).
  - Immersive full screen: nimkivy opens the window with
    `SDL_WINDOW_FULLSCREEN` on Android (**known**:
    `window_sdl3.createWindow`), which SDLActivity turns into
    `SYSTEM_UI_FLAG_IMMERSIVE_STICKY` with the status and navigation bars
    hidden (**known**: `COMMAND_CHANGE_WINDOW_STYLE`); the template's theme
    is `Theme.NoTitleBar.Fullscreen`. Kiosk mode proper (screen pinning) is
    set up on the tablet, not in the app.
- **known** Build (about 1 minute; the first run downloads Gradle and AGP):

  ```sh
  cd ~/Android/build/kiosk-android
  echo "sdk.dir=$HOME/Android/sdk" > local.properties
  export JAVA_HOME=~/Android/jdk-17.0.21.1+2 ANDROID_HOME=~/Android/sdk GRADLE_USER_HOME=~/Android/gradle
  ./gradlew --no-daemon assembleDebug   # app/build/outputs/apk/debug/app-debug.apk
  ```

  With the C stub as `libmain.so` this built a 68 MB debug APK (package
  `gr.philosykos.philosykos_exhibition`, sdkVersion 26, targetSdkVersion
  34, `native-code: 'armeabi-v7a'`, launchable `KioskActivity`); the stub
  was then taken out of `jniLibs` again. Not installed on a device.

## 5. Assets

- **known** The kiosk's `assets/` (64 MB: photos, flags, fonts, WAV clips)
  and `content/` (JSON) are packed into the APK under the same names:
  `app/src/main/assets/assets` and `app/src/main/assets/content` are
  symlinks to `kiosk/assets` and `kiosk/content` in the website repo, so the
  APK holds `assets/assets/...` and `assets/content/...` (134 files),
  mirroring the `kiosk/` folder.
- **known** nimkivy opens files by path: `IMG_Load` (core/image),
  `TTF_OpenFont` (core/text/text_sdl3) and `SDL_LoadWAV` (core/audio).
- **untested** On Android these SDL functions open a relative path through
  `SDL_IOFromFile`, which reads it from the APK's `assets/` folder, read
  through SDL's IOStream, not unpacked.
- **known** Not everything goes through SDL: `resources.resourceFind`
  checks that a file exists with `std/os` (`fileExists`, `dirExists`) and
  returns an absolute path, and the font lookup checks `data/fonts` the same
  way. Neither can see inside the APK. So with the assets left in the APK,
  `Image.source` and fonts are "not found" and never reach SDL (uix/image
  `setTextureFromResource`, core/text `resolveFontName`); only `loadSound`
  falls back to the name as given, which SDL would then find in the assets.
- **known** The kiosk finds its folders as `getAppDir().parentDir`
  (`kiosk/app/content.nim`: `Root`, `Content`, `Assets`) and reads the JSON
  with `std/json` `parseFile`. In an Android app `getAppDir` is not the
  APK, and `parseFile` cannot read APK assets either.
- So either the app copies its assets to its files directory on first
  start (as python-for-android unpacks Kivy apps) and the paths point there,
  or the lookups learn to ask SDL (SDL_GetPathInfo, or opening the file with
  SDL_IOFromFile). To decide with the first Android build (phase B); a GAP
  if the stdlib is what is missing.

## 6. Behaviour on Android in the code today

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

## 7. Checks for the first Android build

1. `adb shell getprop ro.product.cpu.abi` (section 0); build
   `examples/showcase.nim` for `armeabi-v7a`.
2. On the tablet: the attract crossfade, the fade between screens, a tap
   and a swipe, the picker, the voice clip to its end (`on_stop`), Back.
3. Home button and back: `on_pause` and `on_resume` in the log (the GAP
   above: note when `on_pause` arrives).
4. Rotation off, screen stays on for longer than the system timeout.
5. Frame time on the tablet with the same scripted run (`tools/profile.sh`
   measures it on the desktop; on Android the frame times would need to go
   to a file in the app's directory).
