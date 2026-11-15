# family-mruby-sdk

[English](README.md)

Ruby 以外の言語で Family mruby のアプリを書くための SDK。アプリは PC で WebAssembly にコンパイルし、端末では
ファームウェアが WAMR で、Ruby のアプリと同じアプリシェルの中で動かす。Window (枠・タイトルバー・閉じるボタン)、
ループ、タイマーはシェルが受け持ち、アプリはいくつかのフック (`OnCreate`・`OnUpdate`・`OnEvent` など) を実装して
Window の中に描く。

状態: 試験的。SDK は fmruby-core の develop に追従しており、名前や形はまだ変わることがある。

## 対応言語

| 言語 | ディレクトリ | サンプル | ツールチェーン |
|---|---|---|---|
| C | `c/` | `tour` | Zig の `zig cc` (または clang と wasm-ld)。libc なし |
| TinyGo | `tinygo/` | `hello`・`tour`・`bounce` | TinyGo と Go |
| Rust | `rust/` | `hello`・`tour` | Rust と `wasm32-unknown-unknown` のターゲット。`no_std` |
| Zig | `zig/` | `hello`・`tour` | Zig 0.15 以降 |

どの言語からも同じ関数 (描画、文字、画像、音、ファイル、ログ、時計、アプリの情報、入力) を使える。
ファームウェア自身の定義から生成したバインディングの上に、その言語らしく書ける手書きの層が載っている。

## クイックスタート

Ruby 3.x と、使う言語のツールチェーンが必要 (バージョンとインストール先は
[入門ガイドの 2 章](docs/getting_started.ja.md#2-用意するもの))。

```
git clone https://github.com/family-mruby/family-mruby-sdk.git
cd family-mruby-sdk
ruby tinygo/build.rb hello      # -> tinygo/build/hello.app.wasm と hello.app.toml
```

ほかの言語も同じ形:

```
ruby rust/build.rb hello        # -> rust/build/hello.app.wasm (+ .app.toml)
ruby zig/build.rb hello         # -> zig/build/hello.app.wasm (+ .app.toml)
ruby c/build.rb tour            # -> c/build/tour.app.wasm (+ .app.toml)
```

アプリは `<名前>.app.wasm` と `<名前>.app.toml` (ランチャーに出す名前と Window の設定) の 2 つのファイル。
両方を端末の `/app` の下のディレクトリに置いて起動する:

- **Linux のシミュレーション (sim)**: sim のアプリのディレクトリに直接ビルドし
  (`ruby tinygo/build.rb hello -o <fmruby-core>/flash/app/tinygo`)、sim を起動してランチャーから
  `TinyGo hello` を起動する。
- **ESP32-P4 のボード** (M5Stack Tab5 など。ファームウェアの開発用ビルドが必要): WiFi でファイルを送って
  起動する。書き込み直しは要らない:

  ```
  curl -X POST "http://<device-ip>/fs/mkdir?path=/app/mine"
  curl -T tinygo/build/hello.app.wasm "http://<device-ip>/fs/put?path=/app/mine/hello.app.wasm"
  curl -T tinygo/build/hello.app.toml "http://<device-ip>/fs/put?path=/app/mine/hello.app.toml"
  curl -X POST "http://<device-ip>/app/launch?path=/app/mine/hello.app.wasm"
  ```

- **ブラウザ**: <https://family-mruby.github.io/studio/> を開き、2 つのファイルを入れたフォルダをページに
  ドロップして、ランチャーから起動する。

wasm のアプリは ESP32-S3 のボード (Retro) では動かない。詳しい手順、アプリの形、フック、トラブルシューティングは
入門ガイドにある。

アプリがファームウェアにある関数だけを使っているかのチェック:

```
ruby tools/check_bindings.rb tinygo/build/hello.app.wasm
```

## サンプル

どの言語にも `tour` がある。hello に主な機能 (図形、文字と日本語、画像、音、ファイル、ログ、時計、
アプリの情報、キーとポインタの入力) を一通り足したもので、どの言語でも内容と画面が同じなので書き方を
比べられる。TinyGo・Rust・Zig にはほかに `hello` (入門ガイドで作るいちばん小さいアプリ)、TinyGo には
`bounce` (小さなアニメーション) がある。

| tour | .wasm のサイズ (SDK 0.1.0) |
|---|---|
| TinyGo | 16,956 B |
| Rust | 11,016 B |
| Zig | 10,639 B |
| C | 9,143 B |

## リポジトリの構成

| パス | 用途 |
|---|---|
| `c/fmrb_boundary.h` | C のヘッダ: 全関数・レコード・フック |
| `c/build.rb`・`c/examples/` | C のアプリのビルド、C のサンプル |
| `tinygo/fmrb/` | import する TinyGo のパッケージ (`fmrb`。ほかの関数は `fmrb/raw`) |
| `tinygo/build.rb`・`tinygo/examples/` | TinyGo のアプリのビルド、TinyGo のサンプル |
| `rust/` | Rust の crate `fmrb` (パッケージ名 `family-mruby-sdk`。ほかの関数は `fmrb::raw`) |
| `rust/build.rb`・`rust/examples/` | Rust のアプリのビルド、Rust のサンプル |
| `zig/` | Zig のパッケージとモジュール `fmrb` (ほかの関数は `fmrb.raw`) |
| `zig/build.rb`・`zig/examples/` | Zig のアプリのビルド、Zig のサンプル |
| `tools/check_bindings.rb` | ビルドしたアプリの import とフックのチェック |
| `docs/` | 入門ガイドと tour の仕様 |

サンプルは `<言語>/examples/` の下の 1 ディレクトリが 1 アプリで、ディレクトリ名でビルドする。自分のアプリを
始めるには、サンプルのディレクトリを新しい名前でコピーし、`<名前>.app.toml` もその名前に変えて、その名前で
ビルドする (Rust はさらに、その `Cargo.toml` のパッケージ名を変え、`rust/Cargo.toml` の workspace の members に
足す)。ビルドの出力先は `<言語>/build/` (git の管理外)。`-o <ディレクトリ>` で別の場所に出せる。

## ドキュメント

- [docs/getting_started.ja.md](docs/getting_started.ja.md): 何も入っていない PC から、自分のアプリを sim・ボード・
  ブラウザで動かすまで。アプリの形、`.app.toml`、各言語のビルド、トラブルシューティング
  (英語版: [docs/getting_started.md](docs/getting_started.md))
- [docs/tour.md](docs/tour.md): サンプル `tour` の仕様 (英語)

## ライセンス

MIT。[LICENSE](LICENSE) を参照。

---

SDK のメンテナ向け (バインディング・バージョン・リリース): [docs/maintaining.ja.md](docs/maintaining.ja.md)。
