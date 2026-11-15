# family-mruby-sdk

SDK for writing Family mruby apps in languages other than Ruby. Apps are
compiled to WebAssembly on a PC and run on the device by WAMR, inside the
same app shell (window, frame, events, timers) as Ruby apps.

The boundary between an app and the firmware is defined once, in the
firmware's type definitions (`sig/*.rbs` in fmruby-core). The C header in
`c/` will hold the one generated from them (for now it is fmruby-core's
`sdk/c/fmrb_boundary.h`); the bindings for the other languages follow it.

| Directory | Contents |
|---|---|
| `c/` | `fmrb_boundary.h`, the C view of the boundary (generated in fmruby-core) |
| `tinygo/fmrb/` | TinyGo bindings (`//go:wasmimport`) |
| `tinygo/examples/` | TinyGo sample apps |

Status: experimental, follows fmruby-core's develop branch.

To write your first app and run it on the simulation or a board, read
[docs/getting_started.md](docs/getting_started.md) (in Japanese:
[docs/getting_started.ja.md](docs/getting_started.ja.md)).

## TinyGo

```
ruby tinygo/build.rb bounce                 # -> tinygo/build/bounce.app.wasm
ruby tinygo/build.rb bounce -o <dir>        # e.g. fmruby-core/flash/app/tinygo
ruby tools/check_bindings.rb [app.wasm ...] # bindings and app imports vs the C header
```

`build.rb` uses TinyGo from `~/toolchains/tinygo` (override with `TINYGO`)
with `-target=wasm-unknown -gc=conservative -opt=z -no-debug`. An app calls
`fmrb.SetApp` from `init` and implements the hooks it wants (`OnCreate`,
`OnUpdate`, `OnEvent`, ...); see `tinygo/examples/bounce`.

The bindings in `tinygo/fmrb/raw.go` are written by hand for now and cover
FmrbGfx (no records yet), part of FmrbApp and Log; `check_bindings.rb` keeps
them in line with the header. The hook signatures are provisional.
