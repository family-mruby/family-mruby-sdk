# SDK のメンテナンス

[English](maintaining.md)

この文書は SDK そのものを開発する人向け。バインディングの生成元と作り方、バージョンの付け方、リリースの手順を
まとめる。SDK でアプリを書くなら [getting_started.ja.md](getting_started.ja.md) を読む。

## バインディングの生成元

アプリとファームウェアの境界は、ファームウェアの型定義 (fmruby-core の `sig/*.rbs`) の 1 か所で決める。
fmruby-core のジェネレータがそれをデータ (`boundary/boundary.json`) と C のヘッダ (`c/fmrb_boundary.h`) に
書き出し、このリポジトリは JSON から各言語の低レベルのバインディングを生成する (`tools/gen_bindings.rb`)。
言語ごとの手書きのラッパーはその上に載る。

| パス | 内容 |
|---|---|
| `VERSION` | SDK のバージョン (MAJOR.MINOR.PATCH。「バージョン」の節) |
| `boundary/boundary.json` | 境界のデータ (fmruby-core から。手で編集しない) |
| `c/fmrb_boundary.h` | 境界の C のヘッダ (fmruby-core から。手で編集しない) |
| `c/fmrb_sdk_version.h` | C 向けの SDK のバージョンと `FMRB_SDK_VERSION_SECTION()` (生成) |
| `c/fmrb.h` | C の補助 (手書き、ヘッダだけ、使わなくてもよい: C の文字列・テキストバッファ・`FMRB_APP_SETUP()`) |
| `tinygo/fmrb/` | TinyGo のパッケージ (手書き: フック・Window・App など) |
| `tinygo/fmrb/raw/` | TinyGo 向けの境界の全関数・レコード・列挙型と、バージョンを custom section に入れる `version.go` (生成) |
| `tinygo/fmrb.json` | アプリのビルドに使う TinyGo のターゲットファイル |
| `rust/src/lib.rs` | Rust の crate `fmrb` (パッケージ名 `family-mruby-sdk`。手書き: フック・`app!`・Window・App など) |
| `rust/src/raw/` | Rust 向けの境界の全関数・レコード・列挙型 (生成) |
| `rust/.cargo/config.toml` | アプリが自分の crate にコピーするビルドの設定 (サンプルも使う) |
| `zig/src/fmrb.zig` | Zig のモジュール `fmrb` (手書き) |
| `zig/src/raw.zig` | Zig 向けの境界の全関数・レコード・列挙型 (生成) |
| `build.zig`・`build.zig.zon` | Zig のパッケージ (`zig fetch` はリポジトリ全体を取るのでルートに置く。`paths` で Zig の部分だけにする) と `addApp` |
| `tools/gen_bindings.rb` | 「生成」と書いたファイルを作る |
| `tools/templates/<言語>/`・`tools/lib/boundary.rb` | テンプレートとジェネレータのライブラリ |
| `tools/check_bindings.rb` | 生成物・C のヘッダ・ビルドしたアプリをチェックする |
| `tools/version.rb` | 前回のリリースの境界と比べて次のバージョンを出す (`tools/test_version.rb` がそのテスト) |

## .wasm の中の SDK のバージョン

どの言語のライブラリも、`VERSION` をアプリの `.wasm` に custom section `fmrb.sdk` として入れる (中身は semver の
文字列だけ)。どの言語にも custom section を作る仕組みが無いので、アセンブラの
`.section .custom_section.fmrb.sdk,"",@` で作る (LLVM の wasm のオブジェクトの書き出しがこの名前の section を
custom section にし、wasm-ld は `--strip-all` でも残す):

| 言語 | 場所 |
|---|---|
| TinyGo | `tinygo/fmrb/raw/version.go`: パッケージの C の部分 (cgo。TinyGo の clang がビルドする) |
| Rust | `app!` マクロ: アプリ自身の crate に置く `#[link_section = "fmrb.sdk"]` の static (依存の crate に置くと LTO なしでは落ちる) |
| Zig | `zig/src/fmrb.zig`: トップレベルの `comptime { asm (...) }` |
| C | `FMRB_SDK_VERSION_SECTION();` をアプリに 1 度 (`c/fmrb_sdk_version.h`) |

ファームウェアは、アプリを断るときにメッセージで示すためだけに読む (「バージョン」の節)。`tools/check_bindings.rb` は
アプリごとにこれを表示し、`--examples` ではサンプルが `VERSION` を持っていなければ落ちる。

## ビルドスクリプトの中身

`<言語>/build.rb` は、このリポジトリのサンプルをビルドするもの (自分のアプリは getting_started.ja.md のとおり言語の
道具でビルドする)。`.wasm` の隣に `.app.toml` が無ければサンプルのものをコピーする。

- TinyGo: `tinygo build -target=fmrb.json` (TinyGo は `~/toolchains/tinygo` にあればそれ、無ければ `PATH`。
  `TINYGO` で変えられる)。
- C: `~/toolchains/zig-*` の `zig cc -target wasm32-freestanding` (`ZIG` で変えられる。`CC=clang` なら clang と
  wasm-ld)。libc なし、エントリポイントなし、スタック 16 KB。Makefile の例は `c/examples/hello/Makefile`。
- Rust: `rust/` で `cargo build --release -p <名前>`。設定は `rust/.cargo/config.toml` (ターゲット、release の
  profile、スタック 16 KB。スタックの指定が無いとメモリが 17 ページから始まる)。`no_std`、アロケータなし、依存なし。
- Zig: 最新の `~/toolchains/zig-*` (`ZIG` で変えられる。0.15 以降) で、ルートで `zig build -Dexample=<名前>`。
  設定は `build.zig` の `addAppModule`。

SDK 全体のチェック:

```
ruby tools/check_bindings.rb [app.wasm ...] # SDK 内の食い違いと、アプリの import
ruby tools/check_bindings.rb --examples     # 全言語のサンプルもビルドしてチェック
```

## バインディングの再生成

fmruby-core の境界が変わったら:

```
cd <fmruby-core> && rake boundary:sdk SDK=<この checkout>   # boundary.json, c/fmrb_boundary.h
cd <この checkout> && ruby tools/gen_bindings.rb            # tinygo/fmrb/raw/, rust/src/raw/, zig/src/raw.zig, c/fmrb_sdk_version.h
ruby tools/check_bindings.rb
```

ここにコピーする C のヘッダは、fmruby-core の `sdk/c/fmrb_boundary.h` と同じテンプレートから、説明文の日本語の
半分を省いて書き出したもの (このリポジトリのソースを ASCII に保つため)。

## 言語を追加する

`tools/templates/<言語>/` にテンプレートを置き、`tools/lib/boundary.rb` の `OUTPUTS` に並べ (名前と型の変換は
`Go`・`Rust`・`Zig` と同じ形のモジュールを足す)、その上に手書きのラッパー・ビルドスクリプト・`tour`
([tour.md](tour.md) に従う) を書く。`tools/check_bindings.rb` が新しい生成物もほかと同じくチェックする。
宣言を読み戻すチェック (`DECLS`) はテンプレートそのものの確認にもなる。

## バージョン

`MAJOR.MINOR.PATCH`。`boundary/boundary.json` を前回のリリースのものと比べて決める
(`ruby tools/version.rb`。最新の `vX.Y.Z` のタグと比べる):

- 破壊的変更: 古いアプリが使うかもしれない関数・レコード・フックが変わった・消えた (列挙型の番号の変更、
  イベントバッファの大きさの変更も)
- 追加: 足しただけ
- 変更なし: 境界が同じ (SDK だけの変更)

| 変更 | 0.x の間 | 1.0.0 から |
|---|---|---|
| 破壊的変更 | MINOR (0.1.0 → 0.2.0) | MAJOR (1.2.3 → 2.0.0) |
| 追加 | PATCH (0.1.0 → 0.1.1) | MINOR (1.2.3 → 1.3.0) |
| 変更なし | PATCH | PATCH |

0.x の間は境界がまだ固まっていないので、semver の 0.x の慣例どおり 1 桁ずつ下にずらす。1.0.0 はツールが
出すことはなく、境界を安定と決めたときに手で `VERSION` に書く。2 つの規則は `ruby tools/test_version.rb` で
テストする。

バージョンは `.wasm` に入って運ばれる (上の custom section `fmrb.sdk`)。ファームウェアは番号を比べない。
起動の前に `.wasm` が import する関数をすべて調べ、自分に無い (またはシグネチャの違う) 関数を使うアプリを、
その関数の名前とアプリの section のバージョンを示して断る。使う関数の一覧はほかのどこにも書かない (`.wasm` の
import セクションがその一覧)。`ruby tools/check_bindings.rb --against vX.Y.Z app.wasm` で、そのバージョンの
ファームウェアで動くかを確認できる。

## 配布

全言語で 1 つのリポジトリ。API が固まったら言語ごとのパッケージレジストリにそのまま公開できるよう、言語ごとに
ディレクトリを分ける:

| 言語 | ディレクトリ | 公開の形 (予定) |
|---|---|---|
| C | `c/` | ヘッダをコピーするか git で取得する |
| TinyGo | `tinygo/` | Go のモジュール `github.com/family-mruby/family-mruby-sdk/tinygo` |
| Rust | `rust/` | crate (crates.io)。それまでは git の依存 (`cargo add --git`) |
| Zig | ルートの `build.zig.zon`・`zig/` | git の URL で取るパッケージ (`zig fetch --save git+https://...`。タグは `#vX.Y.Z`) |

タグ: リリースはリポジトリに `vX.Y.Z`。Go のモジュールはサブディレクトリにあるので、同じコミットに
`tinygo/vX.Y.Z` も打つ (Go はサブディレクトリのモジュールのバージョンを、ディレクトリ名を前に付けたタグで探す)。
MAJOR が 2 以上になると、Go はモジュールパスにメジャーバージョンを入れる決まり (`.../tinygo/v2`) なので、
module の行と import が変わる。

## リリースの手順

まだ行っていない (タグは打っていない)。

1. fmruby-core で `rake boundary:sdk SDK=<この checkout>`、ここで `ruby tools/gen_bindings.rb`。
2. `ruby tools/version.rb` で一覧を読む。`--write` で `VERSION` (と `rust/Cargo.toml`・`build.zig.zon` の
   バージョン) を書き換えて再生成する。
3. `ruby tools/check_bindings.rb --examples` (全言語のサンプルをビルドしてチェック)。対応する fmruby-core から
   ビルドしたファームウェアで動かす。
4. コミットし、`git tag vX.Y.Z` と `git tag tinygo/vX.Y.Z`、コミットと両方のタグを push する。
