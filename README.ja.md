# family-mruby-sdk

Ruby 以外の言語で Family mruby のアプリを書くための SDK。アプリは PC で WebAssembly にコンパイルし、端末では
WAMR が Ruby のアプリと同じアプリシェル (Window・枠・イベント・タイマー) の中で動かす。

アプリと本体の境界は、本体の型定義 (fmruby-core の `sig/*.rbs`) の 1 か所で決める。`c/` の C のヘッダはそこから
生成したもので、ほかの言語のつなぎはそれに合わせる。

| ディレクトリ | 中身 |
|---|---|
| `c/` | `fmrb_boundary.h` (境界の C の形。fmruby-core で生成) |
| `tinygo/fmrb/` | TinyGo のつなぎ (`//go:wasmimport`) |
| `tinygo/examples/` | TinyGo のサンプルアプリ |

状態: 試験的。fmruby-core の develop に追従する。
