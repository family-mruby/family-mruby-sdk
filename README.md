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

| Language | Directory | Samples | Toolchain |
|---|---|---|---|
| C | `c/` | `tour` | Zig's `zig cc` (or clang with wasm-ld), no libc |
| TinyGo | `tinygo/` | `hello`, `tour`, `bounce` | TinyGo and Go |
| Rust | `rust/` | `hello`, `tour` | Rust with the `wasm32-unknown-unknown` target, `no_std` |
| Zig | `zig/` | `hello`, `tour` | Zig 0.15 or later |

Every language offers the same functions (drawing, text, pictures, sound,
files, the log, clocks, the app's information, input), generated from the
firmware's own definitions, with a hand-written layer that makes them feel
natural in that language.

## Quick start

You need Ruby 3.x and the toolchain of your language (versions and where to
put them: [getting started, section 2](docs/getting_started.md#2-prerequisites)).

```
git clone https://github.com/family-mruby/family-mruby-sdk.git
cd family-mruby-sdk
ruby tinygo/build.rb hello      # -> tinygo/build/hello.app.wasm and hello.app.toml
```

The same for the other languages:

```
ruby rust/build.rb hello        # -> rust/build/hello.app.wasm (+ .app.toml)
ruby zig/build.rb hello         # -> zig/build/hello.app.wasm (+ .app.toml)
ruby c/build.rb tour            # -> c/build/tour.app.wasm (+ .app.toml)
```

An app is two files: `<name>.app.wasm` and `<name>.app.toml` (its name in
the launcher, its window). Put both in a directory under `/app` on a
device and launch it:

- **Linux simulation**: build into the simulation's app directory
  (`ruby tinygo/build.rb hello -o <fmruby-core>/flash/app/tinygo`), start it
  and launch `TinyGo hello` from the launcher.
- **ESP32-P4 board** (M5Stack Tab5 and others) with a development build of
  the firmware: send the files over WiFi and launch it, no flashing needed:

  ```
  curl -X POST "http://<device-ip>/fs/mkdir?path=/app/mine"
  curl -T tinygo/build/hello.app.wasm "http://<device-ip>/fs/put?path=/app/mine/hello.app.wasm"
  curl -T tinygo/build/hello.app.toml "http://<device-ip>/fs/put?path=/app/mine/hello.app.toml"
  curl -X POST "http://<device-ip>/app/launch?path=/app/mine/hello.app.wasm"
  ```

- **Browser**: open <https://family-mruby.github.io/studio/>, drop a folder
  holding the two files on the page, and launch it from the launcher.

wasm apps do not run on ESP32-S3 boards (Retro). The full steps, the shape
of an app, the hooks and the troubleshooting table are in the guide.

To check that an app only uses functions a firmware has:

```
ruby tools/check_bindings.rb tinygo/build/hello.app.wasm
```

## Samples

Every language has `tour`: hello plus a tour of the main functions (shapes,
text and Japanese text, a picture, sound, files, the log, clocks, the app's
information, key and pointer input) with the same content and screen in
each language, so they can be compared. TinyGo, Rust and Zig also have
`hello` (the smallest app, the one the guide builds), and TinyGo `bounce` (a
small animation).

| tour | Size of the .wasm (SDK 0.1.0) |
|---|---|
| TinyGo | 16,956 B |
| Rust | 11,016 B |
| Zig | 10,639 B |
| C | 9,143 B |

## The repository

| Path | What you use it for |
|---|---|
| `c/fmrb_boundary.h` | the C header: every function, record and hook |
| `c/build.rb`, `c/examples/` | build a C app; the C samples |
| `tinygo/fmrb/` | the TinyGo package you import (`fmrb`; everything else in `fmrb/raw`) |
| `tinygo/build.rb`, `tinygo/examples/` | build a TinyGo app; the TinyGo samples |
| `rust/` | the Rust crate `fmrb` (package `family-mruby-sdk`; everything else in `fmrb::raw`) |
| `rust/build.rb`, `rust/examples/` | build a Rust app; the Rust samples |
| `zig/` | the Zig package and its module `fmrb` (everything else in `fmrb.raw`) |
| `zig/build.rb`, `zig/examples/` | build a Zig app; the Zig samples |
| `tools/check_bindings.rb` | check a built app's imports and hooks |
| `docs/` | the guide and the tour's specification |

Each sample is one directory under `<language>/examples/`, one app, built by
its directory's name. To start your own, copy a sample's directory under a
new name, rename its `<name>.app.toml` to match, and build it by that name
(Rust: also rename the package in its `Cargo.toml` and add it to the
workspace members in `rust/Cargo.toml`). The build output goes to
`<language>/build/` (not tracked by git); `-o <dir>` writes it elsewhere.

## Documentation

- [docs/getting_started.md](docs/getting_started.md): from an empty PC to
  your app on the simulation, a board and the browser; the shape of an app,
  the `.app.toml`, every language's build, troubleshooting (in Japanese:
  [docs/getting_started.ja.md](docs/getting_started.ja.md))
- [docs/tour.md](docs/tour.md): the specification of the `tour` sample

## License

MIT. See [LICENSE](LICENSE).

---

For SDK maintainers (bindings, versions, releases): [docs/maintaining.md](docs/maintaining.md).
