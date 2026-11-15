# family-mruby-sdk

SDK for writing Family mruby apps in languages other than Ruby. Apps are
compiled to WebAssembly on a PC and run on the device by WAMR, inside the
same app shell (window, frame, events, timers) as Ruby apps.

The boundary between an app and the firmware is defined once, in the
firmware's type definitions (`sig/*.rbs` in fmruby-core). The C header in
`c/` is generated from them; the bindings for the other languages follow it.

| Directory | Contents |
|---|---|
| `c/` | `fmrb_boundary.h`, the C view of the boundary (generated in fmruby-core) |
| `tinygo/fmrb/` | TinyGo bindings (`//go:wasmimport`) |
| `tinygo/examples/` | TinyGo sample apps |

Status: experimental, follows fmruby-core's develop branch.
