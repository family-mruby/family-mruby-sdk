# family-mruby-sdk

Ruby 以外の言語で Family mruby のアプリを書くための SDK。アプリは PC で WebAssembly にコンパイルし、端末では
WAMR が Ruby のアプリと同じアプリシェル (Window・枠・イベント・タイマー) の中で動かす。

言語: 今は **TinyGo** と **C**。Rust と Zig は同じ定義から生成して足す予定。

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
| `tools/gen_bindings.rb` | 「生成」の印のファイルを作る |
| `tools/check_bindings.rb` | 生成物・C のヘッダ・ビルドしたアプリを照合する |
| `tools/version.rb` | 前回のリリースの境界と比べて次の版を出す |
| `docs/` | 入門と tour の仕様 |

状態: 試験的。fmruby-core の develop に追従する。

最初のアプリを書いて sim・ボード・ブラウザで動かすまでの手順は
[docs/getting_started.ja.md](docs/getting_started.ja.md) (英語版: [docs/getting_started.md](docs/getting_started.md))。

## サンプル

どの言語にも `tour` がある。hello に主な機能の一巡り (図形、文字と日本語、画像、音、ファイル、ログ、時計、
アプリの情報、キーとポインタの入力) を足したもので、どの言語でも中身と画面が同じなので書き方を比べられる。
仕様は [docs/tour.md](docs/tour.md)。TinyGo にはほかに `hello` (入門で作るいちばん小さいアプリ) と
`bounce` (小さなアニメーション) がある。

## ビルド

```
ruby tinygo/build.rb tour                   # -> tinygo/build/tour.app.wasm (+ .app.toml)
ruby c/build.rb tour                        # -> c/build/tour.app.wasm (+ .app.toml)
ruby tinygo/build.rb tour -o <dir>          # 例: fmruby-core/flash/app/tinygo
ruby tools/check_bindings.rb [app.wasm ...] # SDK の食い違いと、アプリの import
```

- TinyGo: `~/toolchains/tinygo` (`TINYGO` で変えられる)、`-target=wasm-unknown -gc=conservative -opt=z -no-debug`。
- C: `~/toolchains/zig-*` の `zig cc -target wasm32-freestanding` (`ZIG` で変えられる。`CC=clang` なら clang と
  wasm-ld)。libc なし、エントリポイントなし、スタック 16 KB。
- どちらも `.wasm` の隣の `.app.toml` に `sdk_version = "<VERSION>"` を書く。

## つなぎの作り直し

fmruby-core の境界が変わったら:

```
cd <fmruby-core> && rake boundary:sdk SDK=<この checkout>   # boundary.json, c/fmrb_boundary.h
cd <この checkout> && ruby tools/gen_bindings.rb            # tinygo/fmrb/raw/, c/fmrb_sdk_version.h
ruby tools/check_bindings.rb
```

ここに写す C のヘッダは、fmruby-core の `sdk/c/fmrb_boundary.h` と同じ型紙から、説明文の日本語の半分を
省いて書き出したもの (このリポジトリのソースを ASCII に保つため)。

言語を足すには、`tools/templates/<言語>/` に型紙を置き、`tools/lib/boundary.rb` の `OUTPUTS` に並べ
(名前と型の変換は `Go` と同じ形のモジュールを足す)、その上に手書きの包み・ビルドのスクリプト・`tour` を書く。

## 版

`MAJOR.MINOR.PATCH`。`boundary/boundary.json` を前回のリリースのものと比べて決める
(`ruby tools/version.rb`。最新の `vX.Y.Z` のタグと比べる):

- MAJOR: 古いアプリが使うかもしれない関数・記録・フックが変わった・消えた (選択肢の番号の変更、イベントの
  置き場の大きさの変更も)
- MINOR: 足しただけ
- PATCH: 境界が同じ (SDK だけの変更)

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
2. `ruby tools/version.rb` で一覧を読む。`--write` で `VERSION` を書き換えて作り直す。
3. サンプルをビルドし (`tinygo/build.rb`・`c/build.rb`)、`ruby tools/check_bindings.rb` を流す。対応する
   fmruby-core から作った本体で動かす。
4. コミットし、`git tag vX.Y.Z` と `git tag tinygo/vX.Y.Z`、コミットと両方のタグを push する。
