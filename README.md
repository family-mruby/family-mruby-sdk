# family-mruby-sdk

[Japanese](README.ja.md)

The SDK for writing Family mruby apps in languages other than Ruby. You
compile your app to WebAssembly on a PC; on the device the firmware runs it
with WAMR, inside the same app shell as Ruby apps. The shell gives the app
its window (frame, title bar, close button), the loop and the timers; the
app implements a few hooks (`OnCreate`, `OnUpdate`, `OnEvent`, ...) and
draws inside its window.

Status: experimental. The SDK follows fmruby-core's develop branch, and
names and shapes may still change.

## Languages

| Language | You get the SDK with | You build with | Samples |
|---|---|---|---|
| TinyGo | `go get github.com/family-mruby/family-mruby-sdk/tinygo` | `tinygo build -target=fmrb.json` | `hello`, `tour` |
| Rust | `cargo add --git https://github.com/family-mruby/family-mruby-sdk family-mruby-sdk` | `cargo build --release` | `hello`, `tour` |
| Zig | `zig fetch --save git+https://github.com/family-mruby/family-mruby-sdk` | `zig build` (the SDK's `addApp`) | `hello`, `tour` |
| C | the headers of `c/` (copied, or a git submodule) | `zig cc` or clang, one line (or a small Makefile) | `hello`, `tour` |

Every language offers the same functions (drawing, text, pictures, sound,
files, the log, clocks, the app's information, input), generated from the
firmware's own definitions, with a hand-written layer that makes them feel
natural in that language. The SDK's version goes into the `.wasm` (a custom
section, `fmrb.sdk`); the firmware names it when it refuses an app made with
a newer SDK.

## Quick start (TinyGo)

You need TinyGo and its Go on `PATH` (versions in
[getting started, section 2](docs/getting_started.md#2-prerequisites)).

```
mkdir hello && cd hello
go mod init example.com/hello
go get github.com/family-mruby/family-mruby-sdk/tinygo
cp "$(go list -m -f '{{.Dir}}' github.com/family-mruby/family-mruby-sdk/tinygo)/fmrb.json" .
chmod u+w fmrb.json   # copied read-only from the module cache; needed only if you edit it
# write main.go and hello.app.toml (getting started, sections 4 and 5)
tinygo build -target=fmrb.json -o hello.app.wasm .
```

Rust, Zig and C: [getting started, section 6](docs/getting_started.md#6-rust-zig-and-c).

An app is two files: `<name>.app.wasm` and `<name>.app.toml` (its name in
the launcher, its window). Put both in a directory under `/app` on a
device and launch it:

- **Linux simulation**: copy them into a directory under the simulation's
  app directory (`<fmruby-core>/flash/app/mine/`), start it and launch
  `TinyGo hello` from the launcher.
- **ESP32-P4 board** (M5Stack Tab5 and others) with a development build of
  the firmware: send the files over WiFi and launch it, no flashing needed:

  ```
  curl -X POST "http://<device-ip>/fs/mkdir?path=/app/mine"
  curl -T hello.app.wasm "http://<device-ip>/fs/put?path=/app/mine/hello.app.wasm"
  curl -T hello.app.toml "http://<device-ip>/fs/put?path=/app/mine/hello.app.toml"
  curl -X POST "http://<device-ip>/app/launch?path=/app/mine/hello.app.wasm"
  ```

- **Browser**: open <https://family-mruby.github.io/studio/>, drop a folder
  holding the two files on the page, and launch it from the launcher.

wasm apps do not run on ESP32-S3 boards (Retro). The full steps, the shape
of an app, the hooks and the troubleshooting table are in the guide.

## Samples

Every language has `tour`: hello plus a tour of the main functions over
ten pages (shapes, text and Japanese text, a picture, sprites, tiles,
sound with an FMSQ tune and a WAV voice, files, pointer drawing and typed keys,
the app's information and clocks, the clipboard and the app's own wasm
numbers) with the same content and screen in each language, down to the
pixel, so they can be compared. Every language also has `hello`
(the smallest app, the one the guide builds).

| tour | Size of the .wasm (SDK 0.1.0) |
|---|---|
| TinyGo | 29,329 B |
| Rust | 25,389 B |
| Zig | 24,162 B |
| C | 14,462 B |

In a checkout of this repository the samples are built by the scripts the
SDK's maintainers use (Ruby 3.x; output in `<language>/build/`, or `-o
<dir>`):

```
ruby tinygo/build.rb hello
ruby rust/build.rb tour
ruby zig/build.rb tour
ruby c/build.rb hello
```

## The repository

| Path | What it is |
|---|---|
| `tinygo/` | the Go module `github.com/family-mruby/family-mruby-sdk/tinygo`: the package `fmrb` (everything else in `fmrb/raw`), the target file `fmrb.json`, the samples |
| `rust/` | the crate `family-mruby-sdk` (library `fmrb`; everything else in `fmrb::raw`), `.cargo/config.toml` to copy into an app, the samples |
| `build.zig`, `build.zig.zon`, `zig/` | the Zig package `family_mruby_sdk` (at the root, as `zig fetch` takes the whole repository): the module `fmrb` in `zig/src/` (everything else in `fmrb.raw`), `addApp`; the samples in `zig/examples/` |
| `c/` | the headers `fmrb_boundary.h` (every function, record and hook), `fmrb_sdk_version.h` and the optional helpers `fmrb.h`; the samples (`hello` has a Makefile) |
| `<language>/build.rb` | build a sample (for maintainers) |
| `tools/check_bindings.rb` | check a built app's imports, hooks and SDK version |
| `docs/` | the guide and the tour's specification |

## Documentation

- [docs/getting_started.md](docs/getting_started.md): from an empty PC to
  your app on the simulation, a board and the browser; the shape of an app,
  the `.app.toml`, every language's project and build, troubleshooting (in Japanese:
  [docs/getting_started.ja.md](docs/getting_started.ja.md))
- [docs/tour.md](docs/tour.md): the specification of the `tour` sample

## License

MIT. See [LICENSE](LICENSE).

---

For SDK maintainers (bindings, versions, releases): [docs/maintaining.md](docs/maintaining.md).
