# family-mruby-sdk

[English](README.md)

Ruby 以外の言語で Family mruby のアプリを書くための SDK。アプリは PC で WebAssembly にコンパイルし、端末では
ファームウェアが WAMR で、Ruby のアプリと同じアプリシェルの中で動かす。Window (枠・タイトルバー・閉じるボタン)、
ループ、タイマーはシェルが受け持ち、アプリはいくつかのフック (`OnCreate`・`OnUpdate`・`OnEvent` など) を実装して
Window の中に描く。

状態: 試験的。SDK は fmruby-core の develop に追従しており、名前や形はまだ変わることがある。

## 対応言語

| 言語 | SDK の取り込み | ビルド | サンプル |
|---|---|---|---|
| TinyGo | `go get github.com/family-mruby/family-mruby-sdk/tinygo` | `tinygo build -target=fmrb.json` | `hello`・`tour`・`bounce` |
| Rust | `cargo add --git https://github.com/family-mruby/family-mruby-sdk family-mruby-sdk` | `cargo build --release` | `hello`・`tour` |
| Zig | `zig fetch --save git+https://github.com/family-mruby/family-mruby-sdk` | `zig build` (SDK の `addApp`) | `hello`・`tour` |
| C | `c/` の 2 つのヘッダ (コピーか git の submodule) | `zig cc` か clang の 1 行 (か小さな Makefile) | `hello`・`tour` |

どの言語からも同じ関数 (描画、文字、画像、音、ファイル、ログ、時計、アプリの情報、入力) を使える。
ファームウェア自身の定義から生成したバインディングの上に、その言語らしく書ける手書きの層が載っている。
SDK のバージョンは `.wasm` に入る (custom section `fmrb.sdk`)。新しい SDK で作ったアプリをファームウェアが
断るとき、メッセージにそのバージョンを示す。

## クイックスタート (TinyGo)

TinyGo とそれに合う Go が `PATH` にあること (バージョンは [入門ガイドの 2 章](docs/getting_started.ja.md#2-用意するもの))。

```
mkdir hello && cd hello
go mod init example.com/hello
go get github.com/family-mruby/family-mruby-sdk/tinygo
cp "$(go list -m -f '{{.Dir}}' github.com/family-mruby/family-mruby-sdk/tinygo)/fmrb.json" .
chmod u+w fmrb.json   # copied read-only from the module cache; needed only if you edit it
# main.go と hello.app.toml を書く (入門ガイドの 4 章と 5 章)
tinygo build -target=fmrb.json -o hello.app.wasm .
```

Rust・Zig・C は [入門ガイドの 6 章](docs/getting_started.ja.md#6-rustzigc)。

アプリは `<名前>.app.wasm` と `<名前>.app.toml` (ランチャーに出す名前と Window の設定) の 2 つのファイル。
両方を端末の `/app` の下のディレクトリに置いて起動する:

- **Linux のシミュレーション (sim)**: sim のアプリのディレクトリの下 (`<fmruby-core>/flash/app/mine/`) に
  コピーし、sim を起動してランチャーから `TinyGo hello` を起動する。
- **ESP32-P4 のボード** (M5Stack Tab5 など。ファームウェアの開発用ビルドが必要): WiFi でファイルを送って
  起動する。書き込み直しは要らない:

  ```
  curl -X POST "http://<device-ip>/fs/mkdir?path=/app/mine"
  curl -T hello.app.wasm "http://<device-ip>/fs/put?path=/app/mine/hello.app.wasm"
  curl -T hello.app.toml "http://<device-ip>/fs/put?path=/app/mine/hello.app.toml"
  curl -X POST "http://<device-ip>/app/launch?path=/app/mine/hello.app.wasm"
  ```

- **ブラウザ**: <https://family-mruby.github.io/studio/> を開き、2 つのファイルを入れたフォルダをページに
  ドロップして、ランチャーから起動する。

wasm のアプリは ESP32-S3 のボード (Retro) では動かない。詳しい手順、アプリの形、フック、トラブルシューティングは
入門ガイドにある。

## サンプル

どの言語にも `tour` がある。hello に主な機能を 11 ページで一通り足したもの (図形、文字と日本語、画像、
スプライト、タイル、音、FMSQ の曲と WAV の声、ファイル、ポインタで描く線と打ったキー、アプリの情報と時計、
クリップボードとアプリ自身の wasm の数値) で、どの言語でも内容と画面がドット単位で同じなので書き方を比べられる。どの言語にも `hello` (入門ガイドで作るいちばん小さいアプリ) があり、TinyGo には `bounce`
(小さなアニメーション) もある。

| tour | .wasm のサイズ (SDK 0.1.0) |
|---|---|
| TinyGo | 29,434 B |
| Rust | 25,509 B |
| Zig | 24,267 B |
| C | 19,226 B |

このリポジトリの checkout では、サンプルは SDK のメンテナが使うスクリプトでビルドする (Ruby 3.x。出力先は
`<言語>/build/`、または `-o <ディレクトリ>`):

```
ruby tinygo/build.rb hello
ruby rust/build.rb tour
ruby zig/build.rb tour
ruby c/build.rb hello
```

## リポジトリの構成

| パス | 中身 |
|---|---|
| `tinygo/` | Go のモジュール `github.com/family-mruby/family-mruby-sdk/tinygo`: パッケージ `fmrb` (ほかの関数は `fmrb/raw`)、ターゲットファイル `fmrb.json`、サンプル |
| `rust/` | crate `family-mruby-sdk` (ライブラリ名 `fmrb`。ほかの関数は `fmrb::raw`)、アプリにコピーする `.cargo/config.toml`、サンプル |
| `build.zig`・`build.zig.zon`・`zig/` | Zig のパッケージ `family_mruby_sdk` (`zig fetch` はリポジトリ全体を取るのでルートに置く): モジュール `fmrb` は `zig/src/` (ほかの関数は `fmrb.raw`)、`addApp`。サンプルは `zig/examples/` |
| `c/` | ヘッダ `fmrb_boundary.h` (全関数・レコード・フック) と `fmrb_sdk_version.h`、サンプル (`hello` に Makefile) |
| `<言語>/build.rb` | サンプルのビルド (メンテナ向け) |
| `tools/check_bindings.rb` | ビルドしたアプリの import・フック・SDK のバージョンのチェック |
| `docs/` | 入門ガイドと tour の仕様 |

## ドキュメント

- [docs/getting_started.ja.md](docs/getting_started.ja.md): 何も入っていない PC から、自分のアプリを sim・ボード・
  ブラウザで動かすまで。アプリの形、`.app.toml`、各言語のプロジェクトとビルド、トラブルシューティング
  (英語版: [docs/getting_started.md](docs/getting_started.md))
- [docs/tour.md](docs/tour.md): サンプル `tour` の仕様 (英語)

## ライセンス

MIT。[LICENSE](LICENSE) を参照。

---

SDK のメンテナ向け (バインディング・バージョン・リリース): [docs/maintaining.ja.md](docs/maintaining.ja.md)。
