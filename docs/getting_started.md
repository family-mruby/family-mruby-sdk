# Getting started with the Family mruby SDK

[Japanese](getting_started.ja.md)

This guide takes you from an empty machine to a TinyGo app running on Family
mruby: first on the Linux simulation, then on an ESP32-P4 board over WiFi.
The app is `tinygo/examples/hello` in this repository; you can follow the
steps with your own name instead of `hello`.

Status: experimental. The SDK follows fmruby-core's develop branch, and the
names and shapes below may still change.

## 1. What the SDK is

Family mruby apps are usually written in Ruby. This SDK lets you write them in
other languages: the app is compiled to WebAssembly on your PC (an
`.app.wasm` file) and the firmware runs it with WAMR (an interpreter) inside
the same app shell as a Ruby app. The shell owns the window, its frame and
title bar, the loop and the timers; your app implements a few hooks
(`OnCreate`, `OnUpdate`, `OnEvent`, ...) and draws inside the window.

What the app may call (drawing, the app's own information, sound, files,
the log) is the boundary between the app and the firmware. It is defined once,
in the firmware's type definitions (`sig/*.rbs` in fmruby-core), and the same
definitions give Ruby, Lua and MicroPython their functions. For C the
generator writes a header, `sdk/c/fmrb_boundary.h` in fmruby-core: it is the
ABI (function names, parameters, the event record, the hooks). The TinyGo
package `tinygo/fmrb` is written by hand to match it, and
`tools/check_bindings.rb` checks that it does.

Where wasm apps run today:

| Device | wasm apps |
|---|---|
| ESP32-P4 boards (Modern, e.g. M5Stack Tab5) | yes |
| Linux simulation (the docker sim) | yes |
| ESP32-S3 (Retro) | no: the launch is refused with `wasm apps are not in this build` |
| Native Linux build, browser build | yes, when built from the current fmruby-core (the public browser build does not have it yet) |

## 2. Prerequisites

- **TinyGo** and the **Go** it is built against. This guide was checked with
  TinyGo 0.44.0 and Go 1.26.11. Install both from their release archives
  (<https://tinygo.org/getting-started/install/> and <https://go.dev/dl/>).
- **Ruby** (any recent 3.x) for the build and check scripts.
- **git**.
- For the simulation: a Family mruby development tree (the `family-mruby`
  repository with `fmruby-core` and `fmruby-graphics-audio` fetched into it)
  and Docker. See that repository's README ("Testing Without Hardware").
- For a board: an ESP32-P4 board running a **development build** of the
  firmware with WiFi set up (fmruby-core's `config/wifi.toml.example`), and
  `curl`.

`tinygo/build.rb` looks for the toolchains in one directory, by default
`~/toolchains`:

```
~/toolchains/tinygo/bin/tinygo     # the TinyGo release, unpacked
~/toolchains/go/bin/go             # the Go release, unpacked
~/toolchains/cache/                # made by build.rb (Go and TinyGo caches)
```

Put them there, or point `TOOLCHAINS` at another directory, or `TINYGO` at
the `tinygo` binary itself. Check them with:

```
~/toolchains/tinygo/bin/tinygo version
~/toolchains/go/bin/go version
```

## 3. Get the SDK

```
git clone https://github.com/family-mruby/family-mruby-sdk.git
cd family-mruby-sdk
```

| Path | What it is |
|---|---|
| `tinygo/fmrb/` | the TinyGo package: hooks, `Window`, `App`, sound, files, log |
| `tinygo/examples/` | sample apps (`hello`, `bounce`); each directory is one app, its `main.go` and `.app.toml` |
| `tinygo/build.rb` | builds one example into `<name>.app.wasm` |
| `tools/check_bindings.rb` | checks the bindings and an app against the C header |

## 4. The shape of an app

An app is a Go `main` package in `tinygo/examples/<name>/main.go`. Make a
type, register a value of it with `fmrb.SetApp` from `init`, and give it the
hooks you want; the ones you leave out are simply not called. This is the
whole of `tinygo/examples/hello/main.go`:

```go
package main

import "github.com/family-mruby/family-mruby-sdk/tinygo/fmrb"

type hello struct {
	count  int64
	key    string
	bg, fg int32
}

func (h *hello) OnCreate() {
	h.bg = fmrb.RGB(0, 0, 128) // dark blue; RGB(0, 0, 64) would be 0x01, the transparent key
	h.fg = fmrb.RGB(255, 255, 255)
	h.key = "-"
	fmrb.LogInfo("hello: started")
}

func (h *hello) OnUpdate() int32 {
	h.count++
	g := fmrb.Window
	g.FillRect(0, 0, g.AreaWidth(), g.AreaHeight(), h.bg)
	g.DrawText(4, 4, "Hello, Family mruby!", h.fg)
	g.DrawText(4, 16, "count "+fmrb.Itoa(h.count), h.fg)
	g.DrawText(4, 28, "key   "+h.key, h.fg)
	g.Present()
	return 100 // call me again in 100 ms
}

func (h *hello) OnEvent(ev fmrb.Event) {
	if ev.Type != fmrb.KeyDown || ev.Character == 0 {
		return
	}
	switch ev.Character {
	case 'q':
		fmrb.App.Stop()
	case ' ':
		h.count = 0
		h.key = "space"
	default:
		h.key = string(rune(ev.Character))
	}
}

func (h *hello) OnDestroy() {
	fmrb.LogInfo("hello: bye at count " + fmrb.Itoa(h.count))
}

func init() { fmrb.SetApp(&hello{}) }

func main() {}
```

`main` stays empty: the firmware calls the hooks, there is no loop of yours.

### The hooks

| Method | When | Notes |
|---|---|---|
| `OnCreate()` | once, as the app starts | the window is already open |
| `OnUpdate() int32` | repeatedly | returns the ms until the next call; a negative value means the default, 330 ms. Draw here |
| `OnEvent(ev fmrb.Event)` | on key, mouse, gamepad and kana-mode input | see "Input" |
| `OnDestroy()` | once, as the app ends | stop notes you started |
| `OnSuspend()` / `OnResume()` | the screen goes to another app and comes back | |
| `OnResize(w, h int32)` | the window was resized | read the new area with `Window.AreaWidth/AreaHeight` |
| `OnQuitRequest()` | the app is asked to close | |

The `fmrb.App` functions (`Name`, `Pid`, `Platform`, `Language`,
`UserAreaWidth/Height`, `ThemeBg/Fg/Accent`, `Stop`) work from any hook.
`App.Stop()` ends the app after the hook it is called from returns.

### Drawing in the window

- `fmrb.Window` is the window's drawer. It draws in the **area** inside the
  frame: `(0, 0)` is the area's top-left, and `Window.AreaWidth()` and
  `Window.AreaHeight()` are its size (smaller than the window size in the
  `.app.toml`, which includes the frame and title bar).
- Draw, then call `Window.Present()` to show it. Nothing appears until then.
- Shapes: `FillRect`, `DrawRect`, `FillRoundRect`, `DrawRoundRect`,
  `FillCircle`, `DrawCircle`, `DrawLine`, `FillTriangle`, `SetPixel`.
- Text: `DrawText(x, y, text, color)` (transparent background),
  `DrawTextBg(..., bg)`, `SetTextSize(1..4)`. The default font is 6x8 dots
  and ASCII; the Japanese fonts are not in the TinyGo package yet.
- To clear the area, fill it: `FillRect(0, 0, AreaWidth(), AreaHeight(), bg)`.
  `Window.Clear` fills the whole canvas, frame and title bar included, so it is
  only for a fullscreen app.
- **Colors** are 8 bits (RGB332: 3 bits of red, 3 of green, 2 of blue). Make
  one with `fmrb.RGB(r, g, b)` from 0-255 values; nearby colors become the same
  value. The theme's colors are `App.ThemeBg()`, `ThemeFg()`, `ThemeAccent()`.
- **0x01 is transparent.** The desktop uses the color 0x01 as its
  transparency key (that is how windows get round corners), so anything
  painted 0x01 shows what is behind the window. Dark blues land on it:
  `RGB(0, 0, 64)` is 0x01, `RGB(0, 0, 128)` is 0x02. If a background turns
  see-through, this is why.

### Input

`OnEvent` gets a copy of the firmware's 60-byte event record. `ev.Type` is one
of `fmrb.KeyDown`, `KeyUp`, `MouseDown`, `MouseUp`, `MouseMove`, `MouseWheel`,
`GamepadDown`, `GamepadUp`, `GamepadAxis`, `KanaMode`. The fields that mean
something depend on the type; the others are 0:

| Type | Fields |
|---|---|
| keys | `Keycode`, `Scancode`, `Modifier`, `Character` (the character code; 0 for keys without one, such as arrows) |
| mouse down / up | `Button`, `X`, `Y` (in the area), `WX`, `WY` (in the window) |
| mouse move | `X`, `Y`, `WX`, `WY` |
| wheel | `Delta`, `X`, `Y`, `WX`, `WY` |
| gamepad buttons | `GamepadID`, `Button` |
| gamepad axis | `GamepadID`, `Axis`, `Value` |
| kana mode | `Mode` |

### Sound

```go
var audio = fmrb.NewAudio()

audio.NoteOn(0, 440)                 // channel 0, 440 Hz (volume 10, duty 2)
audio.NoteOnRaw(0, 440, 12, 2, 0)    // volume 0-15, duty 0-3, sweep
audio.NoteOff(0)
```

A note sounds until `NoteOff`; turn it off yourself (after a few `OnUpdate`
calls for a short beep) and in `OnDestroy`. `tinygo/examples/bounce` does both.

### Files

`FileRead`, `FileWrite`, `FileExist`, `FileSize`, `FileDelete` and `FileList`
work on whole files by path, in the same places a Ruby app may use (your own
data goes under `/home`). A read loads the whole file into the app's memory.

```go
fmrb.FileWrite("/home/hello.txt", []byte("hi"))
if data, ok := fmrb.FileRead("/home/hello.txt"); ok { ... }
```

### Logging

`fmrb.LogDebug/LogInfo/LogWarn/LogError(msg)` write to the firmware's log,
the same one Ruby apps use. There is no `fmt` and no `strconv` here (they
would make the app much larger); `fmrb.Itoa` formats an integer.

## 5. The .app.toml

Next to `hello.app.wasm` goes `hello.app.toml` with the same base name. It
gives the launcher a name and the window its place. Keep it with the source:
`hello` has `tinygo/examples/hello/hello.app.toml`:

```toml
app_screen_name = "TinyGo hello"
default_window_mode = "window"
default_window_width = 160
default_window_height = 70
default_window_pos_x = 60
default_window_pos_y = 50
```

The keys the firmware reads (fmruby-core's app spawner and launcher):

| Key | Meaning | Default |
|---|---|---|
| `app_screen_name` | the name in the launcher and the title bar | the file name |
| `app_screen_name_<lang>` | the launcher's name in that language (`ja`, `en`) | `app_screen_name` |
| `default_window_mode` | `"window"`, `"fullscreen"` or `"background"` (no window) | `"window"` |
| `default_window_width`, `default_window_height` | the window size in dots, frame included | 100, 100 |
| `default_window_pos_x`, `default_window_pos_y` | where the window opens | 50, 50 |
| `resizable` | 1: the user may resize the window (`OnResize` is called) | 0 |
| `min_window_width`, `min_window_height` | the smallest size when resizable | 0 (the desktop's default) |
| `window_frame` | `"normal"` or `"none"` (no frame, title bar or close button) | `"normal"` |
| `window_drag` | `"title"`, `"anywhere"` or `"none"` | `"title"` with a frame, `"anywhere"` without |
| `rounded_corners` | 0: square, opaque window (no color key) | 1 |
| `fullscreen_hires` | `true`: a fullscreen app uses the 640x360 screen where there is one | false |
| `fullscreen_switchable` | 1: a fullscreen app may be parked on Ctrl+Tab (its `OnSuspend` hides and `OnResume` redraws) | 0 |
| `single_instance` | `true`: refuse a second copy of this app | false |
| `exclusive_group` | a name: refuse the launch while another app of the group runs | none |
| `large_memory` | 1: take a large memory pool | 0 |
| `task_stack_kb` | the app task's C stack in KB (wasm apps get 24 KB by default) | |
| `icon` | the launcher icon, a path without the leading `/` (e.g. `"app/mine/hello.icon"`) | a letter `W` |
| `launcher_visible` | `false`: run by path only, not listed in the launcher | listed |

- The **category** is the directory under `/app` (`/app/tinygo/`,
  `/app/mine/`, ...); any directory works. The launcher lists the apps of all
  categories together, sorted by name (a device's settings can hide whole
  categories).
- The engine is chosen by the extension (`.wasm`). The `language = "tinygo"`
  line in `bounce.app.toml` is a note for people; the firmware does not read it.
- An icon is a 12x12 text grid (`.icon`) and a BMP made from it next to it
  (fmruby-core's `tools/gen_icon_bmp.rb`); copy the form from an existing
  `.icon` in fmruby-core's `flash/app/`.

## 6. Build

```
ruby tinygo/build.rb hello
```

```
.../tinygo/bin/tinygo build -target=wasm-unknown -gc=conservative -opt=z -no-debug -o .../tinygo/build/hello.app.wasm ./examples/hello
.../tinygo/build/hello.app.wasm (7460 bytes)
```

- The output goes to `tinygo/build/` (ignored by git); `-o <dir or file>`
  writes it elsewhere, for example straight into a fmruby-core checkout's
  `flash/app/tinygo`.
- The flags are fixed by the SDK: `wasm-unknown` (no WASI), the conservative
  GC (it frees memory), size optimisation, no debug info.
- Optional: check the app's imports and hooks against the firmware's header.
  The script reads `../fmruby-core/sdk/c/fmrb_boundary.h` (a fmruby-core
  checkout next to the SDK); otherwise give the header:

  ```
  ruby tools/check_bindings.rb --header <fmruby-core>/sdk/c/fmrb_boundary.h tinygo/build/hello.app.wasm
  ```

  It prints the imports and hooks it found and `ok`.

## 7. Run it

### (a) On the Linux simulation

In the Family mruby development tree (`<fmruby-core>` below is its
`fmruby-core` directory):

1. Put the app where the simulation's `/app` is: on Linux, `/app` is the
   `flash/app` directory of fmruby-core, read as it is (no image to rebuild).

   ```
   ruby tinygo/build.rb hello -o <fmruby-core>/flash/app/tinygo
   cp tinygo/examples/hello/hello.app.toml <fmruby-core>/flash/app/tinygo/
   ```

2. Build the Linux firmware in fmruby-core and fmruby-graphics-audio
   (`rake build:linux` in each; after an ESP32 build, `rake clean_all` first)
   and start the simulation (`docker compose up` in the family-mruby
   repository).
3. Start the app:
   - from the launcher: the launcher remembers its list between boots, so
     reload it first (the Reload button in its title bar, or F5), then
     double-click `TinyGo hello`;
   - or by path, with the debug client (it needs Python's `msgpack`):

     ```
     python3 <fmruby-core>/tools/debug/fmrb_dbg_client.py localhost spawn path=/app/tinygo/hello.app.wasm
     ```

4. Press keys: the character appears in the `key` line, space sets the counter
   back to 0, `q` closes the app (so does the close button).
5. Read the log: `docker logs fmruby_core 2>&1 | grep -E "wasm|hello"`.

### (b) On an ESP32-P4 board over WiFi

A development build of the firmware has a remote control over HTTP (port 80):
it can write files and start apps, so there is no need to flash again. Find
the board's address (your router's client list, or its mDNS name
`fmruby-XXXXXX.local`) and use it as `<device-ip>`:

```
curl -X POST "http://<device-ip>/fs/mkdir?path=/app/mine"
curl -T tinygo/build/hello.app.wasm "http://<device-ip>/fs/put?path=/app/mine/hello.app.wasm"
curl -T tinygo/examples/hello/hello.app.toml "http://<device-ip>/fs/put?path=/app/mine/hello.app.toml"
curl -X POST "http://<device-ip>/app/launch?path=/app/mine/hello.app.wasm"
```

Each call answers with JSON (`{"ok":true,...}`; the launch also gives the
`pid`). `/fs/put` does not make directories: make the category directory once
with `/fs/mkdir` (it fails harmlessly when it is already there). After a
rebuild, put the `.wasm` again and launch; to stop the app press `q`, use its
close button, or `curl -X POST "http://<device-ip>/app/kill?pid=<pid>"`
(`GET /app/list` lists the running apps).

Instead of curl you can use the Family mruby repository's
`tools/fmrb_rd_fs.rb` (`put`, `ls`, `get`, `mkdir`, and an interactive mode)
and `tools/fmrb_rd_launch.rb`:

```
ruby tools/fmrb_rd_fs.rb <device-ip> put tinygo/build/hello.app.wasm /app/mine/hello.app.wasm
ruby tools/fmrb_rd_launch.rb <device-ip> /app/mine/hello.app.wasm
```

The remote control is unauthenticated and only in development builds: use it
on a network you trust. **Release builds** do not have it today; the plan is
that a release build will open it only after you allow it on the device itself
(a setting and a short code shown on the screen), so that the same put and
launch steps work there too. This guide will be updated when that is in.

The log of a board is on its serial line (fmruby-core's `rake monitor` or any
serial monitor); it is not sent over WiFi.

## 8. Troubleshooting

| What you see | Why, and what to do |
|---|---|
| An **error window** (`Error: <name>`, click to close) in place of the app | the app was refused at load, or a hook trapped or ran too long. The window and the log (`wasm: [<name>] <hook> stopped: <reason>`) give the reason. The app is not called again |
| `on_update: Exception: instruction limit exceeded` | one hook call may run 20,000,000 instructions. Split long work over several `OnUpdate` calls |
| `... Exception: unreachable` or another trap | usually a Go panic (index out of range, nil, out of memory). Look at what that hook does; `LogInfo` lines help narrow it down |
| `No on_create, on_update or on_event in ...` | the app exports none of the three, so it is refused at load. A TinyGo app built with the `fmrb` package always exports them; this is for C and other languages |
| `wasm: [<name>] <hook> takes N and returns M values, expected ...` | a hook has the wrong shape (an app built against an older SDK). Rebuild with the current SDK |
| `on_event needs fmrb_event_buffer (the SDK's event buffer) or a stack pointer global (__stack_pointer) for its record` | the app was built with an older SDK and has nowhere for the firmware to put the event record (a very small app whose optimiser dropped the stack pointer). Rebuild it with the current SDK: the `fmrb` package exports `fmrb_event_buffer`, the place the firmware writes the record into (a C app puts `FMRB_EVENT_BUFFER();` in one of its files) |
| `... did not load: ...` / `... did not start: ...` | WAMR refused the module, for example it imports a function this firmware does not have (an SDK newer than the firmware) |
| `wasm apps are not in this build` | the device has no WAMR (ESP32-S3, or a native or browser build made before wasm apps came to them) |
| The app does not appear in the launcher | the launcher's list is from the last scan: reload it (the Reload button in its title bar, or F5). Or start it by path |
| A see-through background | the color is 0x01 (see "Drawing") |
| Text and shapes never show | `Window.Present()` is missing |

The log lines of the wasm engine all start with `wasm:`; the app's own lines
carry its name (`app_screen_name`, or the file name without one). On the
simulation, for `hello`:

```
wasm: runtime started (pool 256 KB at ..., 122 boundary functions, ...)     # the first wasm app
wasm: [TinyGo hello] loaded /app/tinygo/hello.app.wasm (7460 bytes, memory 2 pages, up to N, shared pool used N) on_create on_update on_event
TinyGo hello: hello: started                                                 # the app's own LogInfo
wasm: [TinyGo hello] ended (memory 2 pages)
wasm: runtime ended (pool high mark N of 261608 bytes)                       # the last wasm app
```

**Memory.** The app's linear memory comes in 64 KB pages. A TinyGo app
starts with 2 pages and grows as it allocates, up to the `up to N` of the
`loaded` line: what is free in the app's memory pool less 64 KB. A large
`FileRead` or big slices count against it. If the app runs out, the Go
runtime panics (a trap, as above); `large_memory = 1` in the `.app.toml` gives
it a larger pool where the device has one.

## 9. Limits today

- The TinyGo bindings (`tinygo/fmrb/raw.go`) are written by hand and cover a
  subset of the boundary: most of FmrbGfx without records (no images,
  sprites or fonts yet), part of FmrbApp, notes in FmrbAudio, whole-file
  FmrbFile, and the log. `check_bindings.rb` keeps them in line with the
  header. Generating them from the same definitions as the header is planned.
- The hook and record shapes are provisional and may change with the firmware.
- Rust and Zig bindings are planned. A C app can already use the header
  directly (`zig cc -target wasm32-freestanding`).
- wasm apps run on ESP32-P4 boards and the Linux simulation only (section 1).
- The development remote control has no authentication, and release builds
  do not have it yet (section 7 b).
