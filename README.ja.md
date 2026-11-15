# family-mruby-sdk

Ruby 以外の言語で Family mruby のアプリを書くための SDK。アプリは PC で WebAssembly にコンパイルし、端末では
WAMR が Ruby のアプリと同じアプリシェル (Window・枠・イベント・タイマー) の中で動かす。

言語: **TinyGo**・**Rust**・**Zig**・**C**。どれも同じ定義から作る。

アプリと本体の境界は、本体の型定義 (fmruby-core の `sig/*.rbs`) の 1 か所で決める。fmruby-core のジェネレータが
それをデータ (`boundary/boundary.json`) と C のヘッダ (`c/fmrb_boundary.h`) に書き出し、このリポジトリは
JSON から各言語の低い層のつなぎを生成する (`tools/gen_bindings.rb`)。言語ごとの手書きの包みはその上に載る。

| パス | 中身 |
|---|---|
| `VERSION` | SDK の版 (MAJOR.MINOR.PATCH。「版」の節) |
| `boundary/boundary.json` | 境界のデータ (fmruby-core から。手で直さない) |
| `c/fmrb_boundary.h` | 境界の C のヘッダ (fmruby-core から。手で直さない) |
| `c/fmrb_sdk_version.h` | C 向けの SDK の版 (生成) |
| `c/build.rb`・`c/examples/` | C のビルドのスクリプトとサンプル |
| `tinygo/fmrb/` | TinyGo のパッケージ (手書き: フック・Window・App など) |
| `tinygo/fmrb/raw/` | TinyGo 向けの境界の全関数・記録・選択肢 (生成) |
| `tinygo/build.rb`・`tinygo/examples/` | TinyGo のビルドのスクリプトとサンプル |
| `rust/` | Rust の crate `fmrb` (パッケージ名 `family-mruby-sdk`。`src/lib.rs` は手書き: フック・`app!`・Window・App など) |
| `rust/src/raw/` | Rust 向けの境界の全関数・記録・選択肢 (生成) |
| `rust/build.rb`・`rust/examples/` | Rust のビルドのスクリプトとサンプル (workspace のメンバー) |
| `zig/` | Zig のパッケージ (`build.zig`・`build.zig.zon`) とモジュール `fmrb` (`src/fmrb.zig` は手書き) |
| `zig/src/raw.zig` | Zig 向けの境界の全関数・記録・選択肢 (生成) |
| `zig/build.rb`・`zig/examples/` | Zig のビルドのスクリプトとサンプル |
| `tools/gen_bindings.rb` | 「生成」の印のファイルを作る |
| `tools/check_bindings.rb` | 生成物・C のヘッダ・ビルドしたアプリを照合する |
| `tools/version.rb` | 前回のリリースの境界と比べて次の版を出す (`tools/test_version.rb` がその試験) |
| `docs/` | 入門と tour の仕様 |

状態: 試験的。fmruby-core の develop に追従する。

最初のアプリを書いて sim・ボード・ブラウザで動かすまでの手順は
[docs/getting_started.ja.md](docs/getting_started.ja.md) (英語版: [docs/getting_started.md](docs/getting_started.md))。

## サンプル

どの言語にも `tour` がある。hello に主な機能の一巡り (図形、文字と日本語、画像、音、ファイル、ログ、時計、
アプリの情報、キーとポインタの入力) を足したもので、どの言語でも中身と画面が同じなので書き方を比べられる。
仕様は [docs/tour.md](docs/tour.md)。TinyGo・Rust・Zig にはほかに `hello` (入門で作るいちばん小さいアプリ)、
TinyGo には `bounce` (小さなアニメーション) がある。

| tour | .wasm の大きさ (SDK 0.1.0) |
|---|---|
| TinyGo | 16,956 B |
| Rust | 11,016 B |
| Zig | 10,639 B |
| C | 9,143 B |

## ビルド

```
ruby tinygo/build.rb tour                   # -> tinygo/build/tour.app.wasm (+ .app.toml)
ruby rust/build.rb tour                     # -> rust/build/tour.app.wasm (+ .app.toml)
ruby zig/build.rb tour                      # -> zig/build/tour.app.wasm (+ .app.toml)
ruby c/build.rb tour                        # -> c/build/tour.app.wasm (+ .app.toml)
ruby tinygo/build.rb tour -o <dir>          # 例: fmruby-core/flash/app/tinygo
ruby tools/check_bindings.rb [app.wasm ...] # SDK の食い違いと、アプリの import
ruby tools/check_bindings.rb --examples     # 全言語のサンプルもビルドして照合
```

- TinyGo: `~/toolchains/tinygo` (`TINYGO` で変えられる)、`-target=wasm-unknown -gc=conservative -opt=z -no-debug`。
- C: `~/toolchains/zig-*` の `zig cc -target wasm32-freestanding` (`ZIG` で変えられる。`CC=clang` なら clang と
  wasm-ld)。libc なし、エントリポイントなし、スタック 16 KB。
- Rust: `cargo build --release --target wasm32-unknown-unknown` (ターゲットは rustup で入れる。`CARGO` で
  コマンドを変えられる)、`rust/Cargo.toml` の release の profile (サイズ優先・LTO・panic で abort・strip) と
  スタック 16 KB (`-C link-arg=-zstack-size=16384`。無いとメモリが 17 ページから始まる)。`no_std`、
  アロケータなし、依存なし。
- Zig: 最新の `~/toolchains/zig-*` (`ZIG` で変えられる。0.15 以降) で `zig build -Dexample=<名前>`。
  wasm32-freestanding、エントリポイントなし、export を残す、ReleaseSmall、スタック 16 KB (`zig/build.zig` の `addApp`)。
- どれも `.wasm` の隣の `.app.toml` に `sdk_version = "<VERSION>"` を書く。

## つなぎの作り直し

fmruby-core の境界が変わったら:

```
cd <fmruby-core> && rake boundary:sdk SDK=<この checkout>   # boundary.json, c/fmrb_boundary.h
cd <この checkout> && ruby tools/gen_bindings.rb            # tinygo/fmrb/raw/, rust/src/raw/, zig/src/raw.zig, c/fmrb_sdk_version.h
ruby tools/check_bindings.rb
```

ここに写す C のヘッダは、fmruby-core の `sdk/c/fmrb_boundary.h` と同じ型紙から、説明文の日本語の半分を
省いて書き出したもの (このリポジトリのソースを ASCII に保つため)。

言語を足すには、`tools/templates/<言語>/` に型紙を置き、`tools/lib/boundary.rb` の `OUTPUTS` に並べ
(名前と型の変換は `Go`・`Rust`・`Zig` と同じ形のモジュールを足す)、その上に手書きの包み・ビルドのスクリプト・
`tour` を書く。`tools/check_bindings.rb` が新しい生成物もほかと同じく照合する。宣言を読み戻す照合 (`DECLS`) は
型紙そのものの確認にもなる。

## 版

`MAJOR.MINOR.PATCH`。`boundary/boundary.json` を前回のリリースのものと比べて決める
(`ruby tools/version.rb`。最新の `vX.Y.Z` のタグと比べる):

- 壊す変更: 古いアプリが使うかもしれない関数・記録・フックが変わった・消えた (選択肢の番号の変更、イベントの
  置き場の大きさの変更も)
- 追加: 足しただけ
- 同じ: 境界が同じ (SDK だけの変更)

| 変更 | 0.x の間 | 1.0.0 から |
|---|---|---|
| 壊す変更 | MINOR (0.1.0 → 0.2.0) | MAJOR (1.2.3 → 2.0.0) |
| 追加 | PATCH (0.1.0 → 0.1.1) | MINOR (1.2.3 → 1.3.0) |
| 同じ | PATCH | PATCH |

0.x の間は境界がまだ固まっていないので、semver の 0.x の慣例どおり 1 桁ずつ下にずらす。1.0.0 は道具が
出すことはなく、境界を安定と決めたときに手で `VERSION` に書く。2 つの決まりは `ruby tools/test_version.rb` で
確かめる。

ビルドのスクリプトが版をアプリの `.app.toml` (`sdk_version`) に書く。本体は番号を比べない。起動の前に `.wasm`
が import する関数をすべて調べ、自分に無い (または形の違う) 関数を使うアプリを、その関数の名前とアプリの
`sdk_version` を示して断る。使う関数の一覧は `.app.toml` に書かない (`.wasm` の import の節がその一覧)。
`ruby tools/check_bindings.rb --against vX.Y.Z app.wasm` で、その版の本体で動くかを確かめられる。

## 配り方

全言語で 1 つのリポジトリ。API が固まったら言語ごとの公式の置き場にそのまま出せるよう、言語ごとに
ディレクトリを分ける:

| 言語 | ディレクトリ | 出し方 (予定) |
|---|---|---|
| C | `c/` | ヘッダを写すか git で取る |
| TinyGo | `tinygo/` | Go のモジュール `github.com/family-mruby/family-mruby-sdk/tinygo` |
| Rust | `rust/` | crate (crates.io) |
| Zig | `zig/` | パッケージ (`build.zig.zon`。リリースのアーカイブから取る) |

タグ: リリースはリポジトリに `vX.Y.Z`。Go のモジュールはサブディレクトリにあるので、同じコミットに
`tinygo/vX.Y.Z` も打つ (Go はサブディレクトリのモジュールの版を、ディレクトリ名を前に付けたタグで探す)。
MAJOR が 2 以上になると、Go はモジュールの path に版を入れる決まり (`.../tinygo/v2`) なので、module の行と
import が変わる。

リリースの手順 (まだ行っていない。タグは打っていない):

1. fmruby-core で `rake boundary:sdk SDK=<この checkout>`、ここで `ruby tools/gen_bindings.rb`。
2. `ruby tools/version.rb` で一覧を読む。`--write` で `VERSION` (と `rust/Cargo.toml`・`zig/build.zig.zon` の版) を
   書き換えて作り直す。
3. `ruby tools/check_bindings.rb --examples` (全言語のサンプルをビルドして照合)。対応する fmruby-core から作った
   本体で動かす。
4. コミットし、`git tag vX.Y.Z` と `git tag tinygo/vX.Y.Z`、コミットと両方のタグを push する。
