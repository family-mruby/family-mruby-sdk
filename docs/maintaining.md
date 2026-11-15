# Maintaining the SDK

[Japanese](maintaining.ja.md)

This document is for people who work on the SDK itself: where the bindings
come from, how to regenerate them, how versions are numbered and how a
release is made. To write apps with the SDK, read
[getting_started.md](getting_started.md) instead.

## Where the bindings come from

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
| `tinygo/fmrb/` | the TinyGo package (hand-written: hooks, Window, App, ...) |
| `tinygo/fmrb/raw/` | every boundary function, record and choice for TinyGo (generated) |
| `rust/src/lib.rs` | the Rust crate `fmrb` (package `family-mruby-sdk`; hand-written: hooks, `app!`, Window, App, ...) |
| `rust/src/raw/` | every boundary function, record and choice for Rust (generated) |
| `zig/src/fmrb.zig` | the Zig module `fmrb` (hand-written) |
| `zig/src/raw.zig` | every boundary function, record and choice for Zig (generated) |
| `tools/gen_bindings.rb` | generates the files marked "generated" |
| `tools/templates/<lang>/`, `tools/lib/boundary.rb` | the templates and the generator's library |
| `tools/check_bindings.rb` | checks the generated files, the C header and built apps |
| `tools/version.rb` | works out the next version from the last release's boundary (`tools/test_version.rb` tests it) |

## What the build scripts do

- TinyGo: from `~/toolchains/tinygo` (override with `TINYGO`), with
  `-target=wasm-unknown -gc=conservative -opt=z -no-debug`.
- C: `zig cc -target wasm32-freestanding` from `~/toolchains/zig-*` (override
  with `ZIG`, or `CC=clang` for clang with wasm-ld), no libc, no entry point,
  a 16 KB stack.
- Rust: `cargo build --release --target wasm32-unknown-unknown` (install the
  target with rustup; `CARGO` overrides the command), the release profile of
  `rust/Cargo.toml` (size, LTO, abort on panic, stripped) and a 16 KB stack
  (`-C link-arg=-zstack-size=16384`; without it the module starts at 17
  pages). `no_std`, no allocator, no dependencies.
- Zig: `zig build -Dexample=<name>` with the newest `~/toolchains/zig-*`
  (override with `ZIG`; 0.15 or later): wasm32-freestanding, no entry point,
  exports kept, ReleaseSmall, a 16 KB stack (`addApp` in `zig/build.zig`).
- All of them write the `.app.toml` next to the `.wasm` with
  `sdk_version = "<VERSION>"`.

Checking the whole SDK:

```
ruby tools/check_bindings.rb [app.wasm ...] # the SDK is consistent; the apps' imports
ruby tools/check_bindings.rb --examples     # and every example of every language, built
```

## Regenerating the bindings

When fmruby-core's boundary changes:

```
cd <fmruby-core> && rake boundary:sdk SDK=<this checkout>   # boundary.json, c/fmrb_boundary.h
cd <this checkout> && ruby tools/gen_bindings.rb            # tinygo/fmrb/raw/, rust/src/raw/, zig/src/raw.zig, c/fmrb_sdk_version.h
ruby tools/check_bindings.rb
```

The C header copied here is the English-only rendering of fmruby-core's
`sdk/c/fmrb_boundary.h` (the same template without the Japanese half of each
description), so this repository stays ASCII.

## Adding a language

Put its templates under `tools/templates/<lang>/`, list them in `OUTPUTS` of
`tools/lib/boundary.rb` (with a helper module for its names and types, as
`Go`, `Rust` and `Zig` are), and write its hand-written layer, build script
and `tour` (following [tour.md](tour.md)) on top. `tools/check_bindings.rb`
then checks the new products with the others; reading the declarations back
(its `DECLS`) also checks the templates.

## Versions

`MAJOR.MINOR.PATCH`, decided by comparing `boundary/boundary.json` with the
last release's (`ruby tools/version.rb`, against the latest `vX.Y.Z` tag):

- breaking: a function, record or hook an older app may use changed or
  went away (also a choice renumbered, or the event buffer's size);
- addition: only additions;
- same: the same boundary (the SDK's own changes).

| Change | While 0.x | From 1.0.0 on |
|---|---|---|
| breaking | MINOR (0.1.0 -> 0.2.0) | MAJOR (1.2.3 -> 2.0.0) |
| addition | PATCH (0.1.0 -> 0.1.1) | MINOR (1.2.3 -> 1.3.0) |
| same | PATCH | PATCH |

While the version is 0.x the boundary is not stable yet, and the numbers
follow semver's convention for that: everything moves one place down. 1.0.0
is never worked out by the tool: it is written into `VERSION` by hand when
the boundary is declared stable. `ruby tools/test_version.rb` tests both
rules.

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

## Release steps

Not done yet; no tag has been made.

1. In fmruby-core: `rake boundary:sdk SDK=<this checkout>`; here
   `ruby tools/gen_bindings.rb`.
2. `ruby tools/version.rb` and read what it lists; `--write` sets `VERSION`
   (and the versions in `rust/Cargo.toml` and `zig/build.zig.zon`) and
   regenerates.
3. `ruby tools/check_bindings.rb --examples` (builds every language's
   samples and checks them); check them on a firmware built from the
   matching fmruby-core.
4. Commit, then `git tag vX.Y.Z` and `git tag tinygo/vX.Y.Z`, and push the
   commit and both tags.
