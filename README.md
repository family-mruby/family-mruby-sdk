# family-mruby-sdk

SDK for writing Family mruby apps in languages other than Ruby. Apps are
compiled to WebAssembly on a PC and run on the device by WAMR, inside the
same app shell (window, frame, events, timers) as Ruby apps.

Languages: **TinyGo** and **C** today; Rust and Zig are planned, generated
from the same definitions.

The boundary between an app and the firmware is defined once, in the
firmware's type definitions (`sig/*.rbs` in fmruby-core). fmruby-core's
generator writes it out as data, `boundary/boundary.json`, and as the C
header `c/fmrb_boundary.h`; this repository generates every language's
low-level bindings from the JSON (`tools/gen_bindings.rb`), and the
hand-written layer of each language sits on top of them.

| Path | Contents |
|---|---|
| `VERSION` | the SDK version (MAJOR.MINOR.PATCH, see "Versions") |
| `boundary/boundary.json` | the boundary as data (from fmruby-core; do not edit) |
| `c/fmrb_boundary.h` | the C header of the boundary (from fmruby-core; do not edit) |
| `c/fmrb_sdk_version.h` | the SDK version for C (generated) |
| `c/build.rb`, `c/examples/` | the C build script and samples |
| `tinygo/fmrb/` | the TinyGo package (hand-written: hooks, Window, App, ...) |
| `tinygo/fmrb/raw/` | every boundary function, record and choice for TinyGo (generated) |
| `tinygo/build.rb`, `tinygo/examples/` | the TinyGo build script and samples |
| `tools/gen_bindings.rb` | generates the files marked "generated" |
| `tools/check_bindings.rb` | checks the generated files, the C header and built apps |
| `tools/version.rb` | works out the next version from the last release's boundary |
| `docs/` | the getting-started guide and the tour's specification |

Status: experimental, follows fmruby-core's develop branch.

To write your first app and run it on the simulation, a board or the
browser, read [docs/getting_started.md](docs/getting_started.md) (in
Japanese: [docs/getting_started.ja.md](docs/getting_started.ja.md)).

## Samples

Every language has `tour`: hello plus a tour of the main functions (shapes,
text and Japanese text, a picture, sound, files, the log, clocks, the app's
information, key and pointer input) with the same content and screen in
each language, so they can be compared. Its specification is
[docs/tour.md](docs/tour.md). TinyGo also has `hello` (the smallest app, the
one the guide builds) and `bounce` (a small animation).

## Build

```
ruby tinygo/build.rb tour                   # -> tinygo/build/tour.app.wasm (+ .app.toml)
ruby c/build.rb tour                        # -> c/build/tour.app.wasm (+ .app.toml)
ruby tinygo/build.rb tour -o <dir>          # e.g. fmruby-core/flash/app/tinygo
ruby tools/check_bindings.rb [app.wasm ...] # the SDK is consistent; the apps' imports
```

- TinyGo: from `~/toolchains/tinygo` (override with `TINYGO`), with
  `-target=wasm-unknown -gc=conservative -opt=z -no-debug`.
- C: `zig cc -target wasm32-freestanding` from `~/toolchains/zig-*` (override
  with `ZIG`, or `CC=clang` for clang with wasm-ld), no libc, no entry point,
  a 16 KB stack.
- Both write the `.app.toml` next to the `.wasm` with
  `sdk_version = "<VERSION>"`.

## Regenerating the bindings

When fmruby-core's boundary changes:

```
cd <fmruby-core> && rake boundary:sdk SDK=<this checkout>   # boundary.json, c/fmrb_boundary.h
cd <this checkout> && ruby tools/gen_bindings.rb            # tinygo/fmrb/raw/, c/fmrb_sdk_version.h
ruby tools/check_bindings.rb
```

The C header copied here is the English-only rendering of fmruby-core's
`sdk/c/fmrb_boundary.h` (the same template without the Japanese half of each
description), so this repository stays ASCII.

To add a language: put its templates under `tools/templates/<lang>/`, list
them in `OUTPUTS` of `tools/lib/boundary.rb` (with a helper module for its
names and types, as `Go` is), and write its hand-written layer, build script
and `tour` on top.

## Versions

`MAJOR.MINOR.PATCH`, decided by comparing `boundary/boundary.json` with the
last release's (`ruby tools/version.rb`, against the latest `vX.Y.Z` tag):

- MAJOR: a function, record or hook an older app may use changed or went
  away (also a choice renumbered, or the event buffer's size);
- MINOR: only additions;
- PATCH: the same boundary (the SDK's own changes).

The build scripts write the version into the app's `.app.toml`
(`sdk_version`). The firmware does not compare numbers: before the app
starts, it checks every function the `.wasm` imports and refuses an app that
imports one it does not have (or in another shape), naming the function and
the app's `sdk_version`. The list of functions an app uses is not written in
the `.app.toml`: the `.wasm`'s import section is that list.
`ruby tools/check_bindings.rb --against vX.Y.Z app.wasm` tells whether an app
would run on a firmware of that version.

## Distribution

One repository for every language, each in its own directory so that it can
be published to its language's registry as it is once the API is stable:

| Language | Directory | Published as (planned) |
|---|---|---|
| C | `c/` | the headers, copied or as a git checkout |
| TinyGo | `tinygo/` | the Go module `github.com/family-mruby/family-mruby-sdk/tinygo` |
| Rust | `rust/` | a crate (crates.io) |
| Zig | `zig/` | a package (`build.zig.zon`, fetched from a release archive) |

Tags: a release is `vX.Y.Z` on the repository, and, because the Go module
lives in a subdirectory, also `tinygo/vX.Y.Z` on the same commit (Go finds a
subdirectory module's versions by tags with its directory as the prefix).
From MAJOR 2 on, Go requires the major version in the module path
(`.../tinygo/v2`): the module line and the imports change with it.

Release steps (not done yet; no tag has been made):

1. In fmruby-core: `rake boundary:sdk SDK=<this checkout>`; here
   `ruby tools/gen_bindings.rb`.
2. `ruby tools/version.rb` and read what it lists; `--write` sets `VERSION`
   and regenerates.
3. Build the samples (`tinygo/build.rb`, `c/build.rb`) and run
   `ruby tools/check_bindings.rb` on them; check them on a firmware built
   from the matching fmruby-core.
4. Commit, then `git tag vX.Y.Z` and `git tag tinygo/vX.Y.Z`, and push the
   commit and both tags.
