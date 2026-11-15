# Family mruby SDK 入門ガイド

[English](getting_started.md)

この文書は、何も入っていない PC から始めて、TinyGo で書いたアプリを Family mruby の上で動かすまでの手順を
示す。Linux のシミュレーション (sim)、WiFi で送る ESP32-P4 のボード、Web のブラウザ版の 3 か所で動かす。
アプリは新しいディレクトリに作る自分のプロジェクトで、SDK は TinyGo でライブラリを使うときのいつもの方法
(`go get`) で取り込む。C・Rust・Zig のアプリも、それぞれの言語の道具で同じように作る (6 章)。題材は
このリポジトリの `tinygo/examples/hello` と同じアプリ。`hello` を自分のアプリの名前に読み替えれば、同じ手順で
自分のアプリを作れる。

状態: 試験的。SDK は fmruby-core の develop に追従しており、以下の名前や形はまだ変わることがある。

## 1. SDK とは

Family mruby のアプリは普通は Ruby で書く。この SDK を使うと、ほかの言語でも書ける。アプリは PC で
WebAssembly (`.app.wasm`) にコンパイルし、端末ではファームウェアが WAMR (インタプリタ) で、Ruby の
アプリと同じアプリシェルの中で動かす。Window とその枠・タイトルバー、ループ、タイマーはシェルが
受け持つ。アプリはいくつかのフック (`OnCreate`・`OnUpdate`・`OnEvent` など) を実装し、Window の中に描く。

アプリから呼べるもの (描画、アプリ自身の情報、音、ファイル、ログ) が、アプリとファームウェアの境界になる。
境界はファームウェアの型定義 (fmruby-core の `sig/*.rbs`) の 1 か所で決まり、Ruby・Lua・MicroPython の
関数も同じ定義から作られる。C 向けにはジェネレータがヘッダ (fmruby-core の `sdk/c/fmrb_boundary.h`) を
出力する (この SDK の `c/fmrb_boundary.h`)。これが ABI (関数の名前と引数、イベントのレコード、フック) になる。
ジェネレータは境界をデータ (`boundary/boundary.json`) にも書き出し、この SDK はそこから TinyGo のパッケージ
`tinygo/fmrb/raw` (全部の関数・レコード・列挙型) を生成する。パッケージ `tinygo/fmrb` はその上の手書きの層
(フックと、よく使う関数の Go らしい形)。Rust と Zig も同じ 2 層で、生成の `rust/src/raw/`・`zig/src/raw.zig` の
上に手書きの crate `fmrb` (`rust/src/lib.rs`)・モジュール `fmrb` (`zig/src/fmrb.zig`) が載る。生成物が境界と
食い違っていないかは `tools/check_bindings.rb` で確認する。

今 wasm のアプリが動く端末:

| 端末 | wasm のアプリ |
|---|---|
| ESP32-P4 のボード (Modern。M5Stack Tab5 など) | 動く |
| Linux の sim (docker) | 動く |
| ESP32-S3 (Retro) | 動かない。起動は `wasm apps are not in this build` で断られる |
| ネイティブ版 (Linux の 1 プロセス)、ブラウザ版 | 動く (公開中のブラウザ版には `TinyGo bounce` と `TinyGo hello` が入っている。7 章の c) |

## 2. 用意するもの

使う言語のツールチェーンを、その言語の文書のとおりにインストールし、コマンドが `PATH` で見つかるようにする:

| 言語 | 必要なもの | 確認したバージョン |
|---|---|---|
| TinyGo | **TinyGo** と、それに合う **Go** (<https://tinygo.org/getting-started/install/>・<https://go.dev/dl/>) | TinyGo 0.44.0・Go 1.26.11 |
| Rust | **Rust** (rustup) と `wasm32-unknown-unknown` のターゲット: `rustup target add wasm32-unknown-unknown` | Rust 1.97.0 |
| Zig | **Zig** 0.15 以降 (<https://ziglang.org/download/>) | Zig 0.17.1 |
| C | **Zig** (`zig cc` を使う)、または **clang** と **wasm-ld** (lld)。libc は要らない | Zig 0.17.1 |

ほかに:

- **git** (Go・Cargo・Zig が SDK を git のリポジトリから取ってくる)。
- sim で動かすなら: Family mruby の開発用のツリー (`family-mruby` のリポジトリに `fmruby-core` と
  `fmruby-graphics-audio` を取ってきたもの) と Docker。そのリポジトリの README の「Testing Without Hardware」を参照。
- ボードで動かすなら: ファームウェアの**開発用ビルド**が入り、WiFi を設定した ESP32-P4 のボード
  (fmruby-core の `config/wifi.toml.example`) と `curl`。

TinyGo のツールチェーンの確認:

```
tinygo version
go version
```

## 3. プロジェクトを作る

TinyGo のアプリは、それ自身が 1 つの Go のモジュール。モジュールを作り、SDK の TinyGo のモジュールを取り込む:

```
mkdir hello && cd hello
go mod init example.com/hello
go get github.com/family-mruby/family-mruby-sdk/tinygo
```

SDK には、Family mruby のアプリを作るための TinyGo の設定がターゲットファイル `fmrb.json` として入っている。
取ってきたモジュールからプロジェクトにコピーする:

```
cp "$(go list -m -f '{{.Dir}}' github.com/family-mruby/family-mruby-sdk/tinygo)/fmrb.json" .
```

中身は数行で、`wasm-unknown` のターゲット (WASI なし)、conservative の GC (メモリを解放する)、デバッグ情報なし。
サイズの最適化は TinyGo の既定のまま:

```json
{
	"inherits": ["wasm-unknown"],
	"gc": "conservative",
	"ldflags": ["--strip-debug"]
}
```

ディレクトリに `main.go` (4 章) と `hello.app.toml` (5 章) を書いて、ビルドする:

```
tinygo build -target=fmrb.json -o hello.app.wasm .
```

ビルドはこれだけで、`hello.app.wasm` と `hello.app.toml` がアプリになる。SDK のバージョンは自動で `.wasm` に
入る (8 章の「SDK のバージョン」)。変更のたびに同じコマンドでビルドし直す。

モジュールの中身:

| パッケージ | 中身 |
|---|---|
| `github.com/family-mruby/family-mruby-sdk/tinygo/fmrb` | フック、`Window`、`App`、音、ファイル、ログ |
| `github.com/family-mruby/family-mruby-sdk/tinygo/fmrb/raw` | 境界のすべての関数・レコード・選択肢 (生成物) |

SDK のリポジトリ (<https://github.com/family-mruby/family-mruby-sdk>) には言語ごとのサンプル
(`<言語>/examples/`) もあり、主な機能を 5 ページで見せる `tour` もそこにある。アプリを書くのにリポジトリの
checkout は要らない。

## 4. アプリの形

アプリは Go の `main` パッケージ。型を 1 つ作り、その値を `init` から `fmrb.SetApp` で登録し、使いたいフックを
メソッドとして書く。書かなかったフックは呼ばれないだけ。`main.go` の全体 (SDK の
`tinygo/examples/hello/main.go` と同じ):

```go
package main

import "github.com/family-mruby/family-mruby-sdk/tinygo/fmrb"

type hello struct {
	count  int64
	key    string
	bg, fg int32
}

func (h *hello) OnCreate() {
	h.bg = fmrb.RGB(255, 255, 255) // white paper (never 0x01: the transparent key)
	h.fg = fmrb.RGB(0, 0, 0)
	h.key = "-"
	fmrb.LogInfo("hello: started")
}

func (h *hello) OnUpdate() int32 {
	h.count++
	g := fmrb.Window
	g.FillRect(0, 0, g.AreaWidth(), g.AreaHeight(), h.bg)
	g.DrawText(4, 4, "Hello, Family mruby!", h.fg)
	g.DrawText(4, 16, "count "+fmrb.Itoa(h.count), h.fg)
	g.DrawText(4, 28, "key   "+h.key, h.fg)
	g.Present()
	return 100 // call me again in 100 ms
}

func (h *hello) OnEvent(ev fmrb.Event) {
	if ev.Type != fmrb.KeyDown || ev.Character == 0 {
		return
	}
	switch ev.Character {
	case 'q':
		fmrb.App.Stop()
	case ' ':
		h.count = 0
		h.key = "space"
	default:
		h.key = string(rune(ev.Character))
	}
}

func (h *hello) OnDestroy() {
	fmrb.LogInfo("hello: bye at count " + fmrb.Itoa(h.count))
}

func init() { fmrb.SetApp(&hello{}) }

func main() {}
```

`main` は空のままにする。フックを呼ぶのはファームウェアで、アプリ側にループは無い。

SDK の `tinygo/examples/tour` はもう一歩進んだサンプルで、図形・日本語の文字・画像・音・ファイル・時計・アプリの
情報を 5 ページで見せる。SDK のどの言語でも同じアプリ (C は `c/examples/tour/app.c`。仕様は `docs/tour.md`) なので、
言語ごとの書き方を比べる場所にもなる。`fmrb` パッケージがラップしていないものは `fmrb/raw` にある (生成物。境界の
関数 1 つに Go の関数 1 つ。例 `raw.GfxFillArc`)。

### フック

| メソッド | 呼ばれるとき | 補足 |
|---|---|---|
| `OnCreate()` | 起動時に 1 回 | Window はもう開いている |
| `OnUpdate() int32` | 繰り返し | 次に呼ばれるまでの ms を返す。負の数なら既定の 330 ms。描画はここで行う |
| `OnEvent(ev fmrb.Event)` | キー・マウス・ゲームパッド・かなモードの入力 | 「入力」を参照 |
| `OnDestroy()` | 終了時に 1 回 | 鳴らした音はここで止める |
| `OnSuspend()` / `OnResume()` | 画面がほかのアプリに移ったとき / 戻ってきたとき | |
| `OnResize(w, h int32)` | Window の大きさが変わったとき | 新しい描画領域は `Window.AreaWidth/AreaHeight` で読む |
| `OnQuitRequest()` | 閉じてよいかを聞かれたとき | |

`fmrb.App` の関数 (`Name`・`Pid`・`Platform`・`Language`・`UserAreaWidth/Height`・`ThemeBg/Fg/Accent`・
`Stop`) はどのフックからでも呼べる。`App.Stop()` を呼ぶと、そのフックから戻った後にアプリが終わる。

### Window に描く

- `fmrb.Window` は Window の描画先。枠の内側の**描画領域**に描く。`(0, 0)` が描画領域の左上で、大きさは
  `Window.AreaWidth()` と `Window.AreaHeight()`。`.app.toml` で指定する Window の大きさは枠とタイトルバー
  込みなので、描画領域はそれより小さい。
- 描いてから `Window.Present()` を呼ぶと画面に出る。呼ぶまでは何も見えない。
- 図形: `FillRect`・`DrawRect`・`FillRoundRect`・`DrawRoundRect`・`FillCircle`・`DrawCircle`・`DrawLine`・
  `FillTriangle`・`SetPixel`。
- 文字: `DrawText(x, y, text, color)` (背景は透明)、`DrawTextBg(..., bg)`、`SetTextSize(1..4)`。既定の
  フォントは 6x8 ドットの ASCII。日本語のフォントは TinyGo のパッケージにまだ入っていない。
- 描画領域を消すには塗りつぶす: `FillRect(0, 0, AreaWidth(), AreaHeight(), bg)`。`Window.Clear` は
  キャンバス全体 (枠とタイトルバーも) を塗るので、全画面のアプリ専用と考える。
- **色**は 8 ビット (RGB332: 赤 3 ビット・緑 3 ビット・青 2 ビット)。`fmrb.RGB(r, g, b)` に 0〜255 の値を
  渡して作る。近い色は同じ値になる。テーマの色は `App.ThemeBg()`・`ThemeFg()`・`ThemeAccent()`。
- **0x01 は透明になる。** デスクトップは 0x01 をカラーキー (透明の目印) に使っている (Window の角を丸く
  見せる仕組み)。そのため 0x01 で塗った所は Window の後ろが透けて見える。暗い青がこれに当たりやすく、
  `RGB(0, 0, 64)` は 0x01、`RGB(0, 0, 128)` は 0x02 になる。背景が透けたらまずこれを疑う。

### 入力

`OnEvent` には、ファームウェアの 60 バイトのイベントレコードのコピーが渡る。`ev.Type` は `fmrb.KeyDown`・
`KeyUp`・`MouseDown`・`MouseUp`・`MouseMove`・`MouseWheel`・`GamepadDown`・`GamepadUp`・`GamepadAxis`・
`KanaMode` のどれか。意味のあるフィールドは種類で決まり、ほかは 0:

| 種類 | フィールド |
|---|---|
| キー | `Keycode`・`Scancode`・`Modifier`・`Character` (文字コード。矢印など文字の無いキーでは 0) |
| マウスのボタン (押す・離す) | `Button`、`X`・`Y` (描画領域の座標)、`WX`・`WY` (Window の座標) |
| マウスの移動 | `X`・`Y`・`WX`・`WY` |
| ホイール | `Delta`・`X`・`Y`・`WX`・`WY` |
| ゲームパッドのボタン | `GamepadID`・`Button` |
| ゲームパッドの軸 | `GamepadID`・`Axis`・`Value` |
| かなモード | `Mode` |

### 音

```go
var audio = fmrb.NewAudio()

audio.NoteOn(0, 440)                 // channel 0, 440 Hz (volume 10, duty 2)
audio.NoteOnRaw(0, 440, 12, 2, 0)    // volume 0-15, duty 0-3, sweep
audio.NoteOff(0)
```

音は `NoteOff` を呼ぶまで鳴り続ける。短い音なら数回後の `OnUpdate` で自分で止め、`OnDestroy` でも止める。
`tinygo/examples/bounce` が両方を行っている。

### ファイル

`FileRead`・`FileWrite`・`FileExist`・`FileSize`・`FileDelete`・`FileList` は、パスを指定してファイル全体を
読み書きする。使える場所は Ruby のアプリと同じ (自分のデータは `/home` の下に置く)。読むとファイル全体が
アプリのメモリに載る。

```go
fmrb.FileWrite("/home/hello.txt", []byte("hi"))
if data, ok := fmrb.FileRead("/home/hello.txt"); ok { ... }
```

### ログ

`fmrb.LogDebug/LogInfo/LogWarn/LogError(msg)` はファームウェアのログ (Ruby のアプリと同じもの) に書く。
`fmt` と `strconv` は使わない (アプリがかなり大きくなる)。整数の文字列化には `fmrb.Itoa` を使う。

## 5. .app.toml

`hello.app.wasm` の隣に、同じ名前の `hello.app.toml` を置く。ランチャーに出す名前と Window の位置を
決めるファイル。`hello` では:

```toml
app_screen_name = "TinyGo hello"
language = "tinygo"
default_window_mode = "window"
default_window_width = 160
default_window_height = 70
default_window_pos_x = 60
default_window_pos_y = 50
```

ファームウェア (fmruby-core のアプリの起動処理とランチャー) が読むキー:

| キー | 意味 | 既定 |
|---|---|---|
| `app_screen_name` | ランチャーとタイトルバーに出る名前 | ファイル名 |
| `app_screen_name_<言語>` | その言語 (`ja`・`en`) のときにランチャーに出す名前 | `app_screen_name` |
| `default_window_mode` | `"window"`・`"fullscreen"`・`"background"` (Window なし) | `"window"` |
| `default_window_width`・`default_window_height` | Window の大きさ (ピクセル、枠込み) | 100・100 |
| `default_window_pos_x`・`default_window_pos_y` | Window を開く位置 | 50・50 |
| `resizable` | 1: ユーザが大きさを変えられる (`OnResize` が呼ばれる) | 0 |
| `min_window_width`・`min_window_height` | 大きさを変えられるときの最小 | 0 (デスクトップの既定) |
| `window_frame` | `"normal"` か `"none"` (枠・タイトルバー・閉じるボタンなし) | `"normal"` |
| `window_drag` | `"title"`・`"anywhere"`・`"none"` | 枠ありは `"title"`、枠なしは `"anywhere"` |
| `rounded_corners` | 0: 角の丸くない不透明な Window (カラーキーを使わない) | 1 |
| `fullscreen_hires` | `true`: 全画面のアプリが、ある端末では 640x360 の画面を使う | false |
| `fullscreen_switchable` | 1: 全画面のアプリを Ctrl+Tab で裏に回せる (`OnSuspend` で隠し `OnResume` で描き直すこと) | 0 |
| `single_instance` | `true`: 同じアプリの 2 つ目の起動を断る | false |
| `exclusive_group` | 名前: 同じグループのアプリが動いている間は起動を断る | なし |
| `large_memory` | 1: 大きいメモリプールを使う | 0 |
| `task_stack_kb` | アプリのタスクの C スタック (KB)。wasm のアプリの既定は 24 KB | |
| `icon` | ランチャーのアイコン。先頭の `/` なしのパス (例 `"app/mine/hello.icon"`) | 文字の `W` |
| `launcher_visible` | `false`: ランチャーに出さず、パス指定の起動だけにする | 出す |

- **カテゴリは `/app` の下のディレクトリで決まる** (`/app/tinygo/`・`/app/mine/` など。どのディレクトリでも
  よい)。ランチャーは全カテゴリのアプリを名前順に並べて出す (端末の設定でカテゴリごと隠すこともできる)。
- エンジンは拡張子 (`.wasm`) で決まる。`bounce.app.toml` にある `language = "tinygo"` は人向けのメモで、
  ファームウェアは読まない。
- SDK のバージョンを書くキーは無い。SDK が `.wasm` に入れる (8 章の「SDK のバージョン」)。
- アイコンは 12x12 の文字の格子 (`.icon`) と、そこから作る BMP を隣に置く (fmruby-core の
  `tools/gen_icon_bmp.rb`)。書式は fmruby-core の `flash/app/` にある `.icon` をコピーするのが早い。

## 6. Rust・Zig・C

どの言語も、その言語でいつも使う方法で SDK を取り込む。アプリはどれも同じで、`<名前>.app.wasm` の隣に
`<名前>.app.toml` (5 章) を置き、同じフックをその言語の名前で書く。

### Rust

SDK は crate `family-mruby-sdk` (ライブラリの名前は `fmrb`)。crates.io に出すまでは、Cargo が git の
リポジトリから取ってくる:

```
cargo new --lib hello && cd hello
cargo add --git https://github.com/family-mruby/family-mruby-sdk family-mruby-sdk
```

(公開した後は `cargo add family-mruby-sdk`。) アプリは `cdylib` のライブラリ。`Cargo.toml` に足す:

```toml
[lib]
crate-type = ["cdylib"]
```

ビルドの設定はプロジェクトの `.cargo/config.toml` に書く (SDK の `rust/.cargo/config.toml` と同じもの):

```toml
[build]
target = "wasm32-unknown-unknown"

[target.wasm32-unknown-unknown]
# a 16 KB stack: without it the linker reserves 1 MiB and the app starts
# with 17 pages (64 KB each) of memory
rustflags = ["-C", "link-arg=-zstack-size=16384"]

[profile.release]
opt-level = "s"
lto = true
panic = "abort"
codegen-units = 1
strip = true
```

`src/lib.rs` (`cargo new` が書いたものは置き換える) と `hello.app.toml` を書いて:

```
cargo build --release
cp target/wasm32-unknown-unknown/release/hello.wasm hello.app.wasm
```

アプリは `no_std`。`fmrb::App` (フックはどれも既定で何もしない) と `Default` を実装した型を作り、
`fmrb::app!(Hello);` で 1 度だけ名前を渡す。このマクロがフック、イベントバッファ、SDK のバージョンを export する。

```rust
#![no_std]
use fmrb::{Event, Text, WINDOW};

#[derive(Default)]
struct Hello { count: i64 }

impl fmrb::App for Hello {
    fn on_update(&mut self) -> i32 {
        self.count += 1;
        WINDOW.fill_rect(0, 0, WINDOW.area_width(), WINDOW.area_height(), 0xFF);
        WINDOW.draw_text(4, 4, "Hello, Family mruby!", 0x00);
        WINDOW.draw_text(4, 16, Text::<32>::from("count ").int(self.count).as_str(), 0x00);
        WINDOW.present();
        100
    }
    fn on_event(&mut self, ev: &Event) {
        if ev.kind() == fmrb::KEY_DOWN && ev.character == 'q' as i32 {
            fmrb::app::stop();
        }
    }
}

fmrb::app!(Hello);
```

アロケータは使わない。ファームウェアが返す文字列 (`fmrb::app::name()` など) は `Text<N>` (固定の大きさの
バッファ) で受け取る。`Text` は描く行を組み立てるのにも使える (`push`・`int`・`core::fmt::Write`)。crate は
トラップする panic handler を持つ (自分のものを使うなら既定の feature `panic-handler` を外す)。ほかの関数は
`fmrb::raw` にある (`unsafe`)。もっと大きい例は SDK の `rust/examples/hello` と `rust/examples/tour`。

### Zig

SDK は Zig のパッケージ (`family_mruby_sdk`) で、モジュール `fmrb` と、設定を持つビルドの関数 `addApp` が入っている。
プロジェクトを作ってパッケージを取ってくる:

```
mkdir hello && cd hello
zig init --minimal
zig fetch --save git+https://github.com/family-mruby/family-mruby-sdk
```

`zig init` が書いた `build.zig` を次で置き換える:

```zig
const std = @import("std");
const fmrb_sdk = @import("family_mruby_sdk");

pub fn build(b: *std.Build) void {
    const app = fmrb_sdk.addApp(b, .{
        .name = "hello",
        .root_source_file = b.path("src/main.zig"),
        .app_toml = b.path("hello.app.toml"),
    });
    b.installArtifact(app);
}
```

`src/main.zig` と `hello.app.toml` を書いて:

```
zig build
```

`zig-out/bin/hello.app.wasm` ができ、隣に `hello.app.toml` がコピーされる。`addApp` の設定は
`wasm32-freestanding`、エントリポイントなし、export を残す、`ReleaseSmall`、strip、16 KB のスタック。

アプリはモジュール `fmrb` を import するルートのファイルで、全部のフィールドに既定値のある struct に、使うフックを
メソッド (`onCreate`・`onUpdate`・`onEvent` など) として書き、`fmrb.exportApp` で export する:

```zig
const fmrb = @import("fmrb");
pub const panic = fmrb.panic; // panic はトラップにする (アプリが小さくなる)

const Hello = struct {
    count: i64 = 0,

    pub fn onUpdate(self: *Hello) i32 {
        self.count += 1;
        const g = fmrb.window;
        g.fillRect(0, 0, g.areaWidth(), g.areaHeight(), 0xFF);
        g.drawText(4, 4, "Hello, Family mruby!", 0x00);
        g.present();
        return 100;
    }
    pub fn onEvent(_: *Hello, ev: *const fmrb.Event) void {
        if (ev.type == fmrb.key_down and ev.character == 'q') fmrb.app.stop();
    }
};

comptime {
    fmrb.exportApp(Hello);
}
```

文字列を返す関数は、渡したバッファに書いてスライスを返す (`fmrb.app.name(&buf)`)。描く行は
`std.fmt.bufPrint` で組み立てる。ほかの関数は `fmrb.raw` にある。もっと大きい例は SDK の `zig/examples/hello` と
`zig/examples/tour`。

### C

SDK はリポジトリの `c/` にある 2 つのヘッダ、`fmrb_boundary.h` (すべての関数・レコード・フック) と
`fmrb_sdk_version.h`。プロジェクトにコピーするか、リポジトリを git の submodule にする:

```
mkdir hello && cd hello
curl -O https://raw.githubusercontent.com/family-mruby/family-mruby-sdk/main/c/fmrb_boundary.h
curl -O https://raw.githubusercontent.com/family-mruby/family-mruby-sdk/main/c/fmrb_sdk_version.h
```

C のアプリは両方を include して C の関数を直接呼び (`fmrb_gfx_fill_rect(0, x, y, w, h, color)`。描画先 0 が
Window)、使うフック (`void on_create(void)`・`int32_t on_update(void)`・`void on_event(const fmrb_app_event_t *ev)`
など) を定義し、どれか 1 つのファイルに次の 2 行を書く:

```c
#include "fmrb_boundary.h"
#include "fmrb_sdk_version.h"

FMRB_EVENT_BUFFER();         /* the place for on_event's record */
FMRB_SDK_VERSION_SECTION();  /* the SDK version, into the .wasm */
```

`hello` の C 版の全体は SDK の `c/examples/hello/hello.c`。ビルドは `zig cc` か clang の 1 行:

```
zig cc -target wasm32-freestanding -nostdlib -Os -I. -Wl,--no-entry -Wl,-z,stack-size=16384 -Wl,--strip-all hello.c -o hello.app.wasm
clang --target=wasm32 -nostdlib -Os -I. -Wl,--no-entry -Wl,-z,stack-size=16384 -Wl,--strip-all hello.c -o hello.app.wasm
```

libc は無く (`-nostdlib`)、エントリポイントも無い (フックを呼ぶのはファームウェア)。コンパイラが `memcpy`・`memset`
を求めたら自分で定義する (`c/examples/tour/app.c` がそうしている)。文字列はポインタと長さで渡し、NUL 終端では
ない。ファイルが増えたら小さな Makefile で (SDK の `c/examples/hello/Makefile` と同じ形。`FMRB_SDK` はヘッダの
場所で、submodule なら `family-mruby-sdk/c` など。SDK の中のものは `../..`):

```make
FMRB_SDK ?= .
APP      ?= hello
SRCS     ?= $(wildcard *.c)
CC       := zig cc
TARGET   ?= -target wasm32-freestanding
CFLAGS   ?= -Os
WASMFLAGS = $(TARGET) -nostdlib -I$(FMRB_SDK) -Wl,--no-entry -Wl,-z,stack-size=16384 -Wl,--strip-all

$(APP).app.wasm: $(SRCS) $(FMRB_SDK)/fmrb_boundary.h $(FMRB_SDK)/fmrb_sdk_version.h
	$(CC) $(WASMFLAGS) $(CFLAGS) $(SRCS) -o $@
```

(clang なら `make CC=clang TARGET=--target=wasm32`。)

## 7. 動かす

### (a) Linux の sim で動かす

Family mruby の開発用のツリーで行う (以下の `<fmruby-core>` はその中の `fmruby-core` ディレクトリ)。

1. sim の `/app` にアプリを置く。Linux では `/app` は fmruby-core の `flash/app` ディレクトリそのもので、
   置けばそのまま読まれる (イメージの作り直しは要らない)。その下のディレクトリがカテゴリになる。ここでは `mine`:

   ```
   mkdir -p <fmruby-core>/flash/app/mine
   cp hello.app.wasm hello.app.toml <fmruby-core>/flash/app/mine/
   ```

2. fmruby-core と fmruby-graphics-audio を Linux 向けにビルドし (それぞれで `rake build:linux`。直前が
   ESP32 向けのビルドなら先に `rake clean_all`)、sim を起動する (family-mruby で `docker compose up`)。
3. アプリを起動する:
   - ランチャーから: ランチャーは一覧を前回の起動から覚えているので、先に読み直す (タイトルバーの
     Reload ボタン、または F5)。その後 `TinyGo hello` をダブルクリックする。
   - パスを指定して: デバッグ用のクライアントを使う (Python の `msgpack` が要る)。

     ```
     python3 <fmruby-core>/tools/debug/fmrb_dbg_client.py localhost spawn path=/app/mine/hello.app.wasm
     ```

4. キーを押す。押した文字が `key` の行に出る。スペースでカウンタが 0 に戻り、`q` でアプリが閉じる
   (閉じるボタンでも閉じる)。
5. ログを見る: `docker logs fmruby_core 2>&1 | grep -E "wasm|hello"`。

### (b) ESP32-P4 のボードで WiFi 経由で動かす

ファームウェアの開発用ビルドには HTTP (port 80) のリモート操作が入っていて、ファイルの書き込みとアプリの起動が
できる。ファームウェアの書き込み直しは要らない。ボードのアドレス (ルータのクライアント一覧、または mDNS の名前
`fmruby-XXXXXX.local`) を調べ、`<device-ip>` に入れる:

```
curl -X POST "http://<device-ip>/fs/mkdir?path=/app/mine"
curl -T hello.app.wasm "http://<device-ip>/fs/put?path=/app/mine/hello.app.wasm"
curl -T hello.app.toml "http://<device-ip>/fs/put?path=/app/mine/hello.app.toml"
curl -X POST "http://<device-ip>/app/launch?path=/app/mine/hello.app.wasm"
```

どれも JSON (`{"ok":true,...}`) で答える。起動の答えには `pid` も入る。`/fs/put` はディレクトリを作らない
ので、カテゴリのディレクトリは最初に 1 回 `/fs/mkdir` で作る (既にあれば失敗するだけで害はない)。ビルドし
直したら `.wasm` を put して起動し直す。止めるには `q`、閉じるボタン、または
`curl -X POST "http://<device-ip>/app/kill?pid=<pid>"` を使う (動いているアプリの一覧は `GET /app/list`)。

curl の代わりに、Family mruby のリポジトリの `tools/fmrb_rd_fs.rb` (`put`・`ls`・`get`・`mkdir` と対話モード) と
`tools/fmrb_rd_launch.rb` も使える:

```
ruby tools/fmrb_rd_fs.rb <device-ip> put hello.app.wasm /app/mine/hello.app.wasm
ruby tools/fmrb_rd_launch.rb <device-ip> /app/mine/hello.app.wasm
```

このリモート操作は認証が無く、開発用ビルドにだけ入っている。信頼できるネットワークでだけ使うこと。
**リリースビルド**には今は入っていない。リリースビルドでは、端末の上で許可したとき (設定と、画面に出る
短いコード) だけ開く形にする計画で、そうなれば同じ put と launch の手順がリリースビルドでも使える。
入ったらこの文書を直す。

ボードのログはシリアルに出る (fmruby-core の `rake monitor` か、任意のシリアルモニタ)。WiFi には流れない。

### (c) ブラウザで動かす

公開中のブラウザ版 <https://family-mruby.github.io/studio/> でも wasm のアプリが動く (同じ WAMR をページに
組み込んである)。何もインストールしなくてよい。ランチャーには `TinyGo bounce` と `TinyGo hello` が入っている。
自分のアプリを動かすには:

1. アプリの 2 つのファイルを、アプリの名前のフォルダに入れる: `hello/hello.app.wasm` と `hello/hello.app.toml`
   (送って困るものが無ければプロジェクトのディレクトリのままでよい。Zig の `zig-out/bin` には両方がある)。
2. ページを開き、デスクトップが出るまで待つ。画面の下の **Your files** の領域で **Add Folder...** からフォルダを
   選ぶか、フォルダをページのどこかにドロップする。一番上に `<名前>.app.toml` があるフォルダは
   `/app/usr/<フォルダ>/` (自分で足すアプリの場所) に入る。それ以外は `/home` に入る。**Files...** で
   ファイルを 1 つずつ足すときは、**into** の一覧で選んだ場所に入るので `/app/usr` を選ぶ。
3. ランチャーの一覧を読み直して (タイトルバーの Reload ボタン、または F5) アプリをダブルクリックする。
   または Shell を開いて `run /app/usr/hello/hello.app.wasm` と打つ。
4. ログはブラウザの開発者ツールのコンソール (F12) に、sim と同じ行で出る。

ファイルはブラウザのストレージに残る (`/app/usr` と `/home` はページを読み直しても消えない。**Your files** の **Backup** で
.tar に保存できる)。ビルドし直したら、もう一度フォルダを足すと新しいファイルで置き換わる。SDK より古い
ブラウザ版は、自分に無い関数を使うアプリを理由つきで断る (8 章)。

## 8. うまくいかないとき

| 症状 | 原因と対処 |
|---|---|
| アプリの代わりに**エラーの Window** (`Error: <名前>`、クリックで閉じる) が出る | 読み込みの時点で断られたか、フックがトラップしたか、長く走りすぎた。理由は Window とログ (`wasm: [<名前>] <フック> stopped: <理由>`) に出る。そのアプリのフックはもう呼ばれない |
| `on_update: Exception: instruction limit exceeded` | 1 回のフックの呼び出しで実行できるのは 2,000 万命令まで。長い処理は複数回の `OnUpdate` に分ける |
| `... Exception: unreachable` などのトラップ | たいていは Go の panic (範囲外の添字、nil、メモリ不足)。そのフックの処理を見直す。`LogInfo` を挟むと場所を絞れる |
| `No on_create, on_update or on_event in ...` | 3 つのどれも export していないので、読み込みの時点で断られた。`fmrb` パッケージでビルドした TinyGo のアプリは必ず export するので、C などほかの言語向けの話 |
| `wasm: [<名前>] <フック> takes N and returns M values, expected ...` | フックのシグネチャが違う (古い SDK でビルドしたアプリ)。今の SDK でビルドし直す |
| `on_event needs fmrb_event_buffer (the SDK's event buffer) or a stack pointer global (__stack_pointer) for its record` | 古い SDK でビルドしたアプリで、ファームウェアがイベントのレコードを置く場所が無い (最適化でスタックポインタが消えた小さいアプリ)。今の SDK でビルドし直す。`fmrb` パッケージは、ファームウェアがレコードを書き込む置き場 `fmrb_event_buffer` を export する (C のアプリはどれか 1 つのファイルに `FMRB_EVENT_BUFFER();` と書く) |
| `imports fmrb.<名前>, which this firmware does not have ...: the app was built with SDK X.Y.Z, newer than this firmware; update the firmware` | ファームウェアに無い関数をアプリが使っている (SDK がファームウェアより新しい)。ファームウェアを更新するか、ファームウェアに合うバージョンの SDK でビルドする。`in another shape than this firmware's` は、シグネチャの変わった関数について同じこと。バージョンの代わりに `built with a newer SDK` と出るのは、`.wasm` がバージョンを持っていないとき (「SDK のバージョン」を参照) |
| `imports <モジュール>.<名前>, but the firmware gives only "fmrb" functions` | WASI や libc の関数を import している (C の `printf` など)。使わずにビルドする |
| `... did not load: ...` / `... did not start: ...` | WAMR がモジュールを受け付けなかった (wasm でない、WAMR に無い機能、メモリ不足) |
| `wasm apps are not in this build` | その端末には WAMR が入っていない (ESP32-S3、または wasm のアプリに対応する前のネイティブ版・ブラウザ版) |
| ランチャーにアプリが出ない | ランチャーの一覧は前回のスキャンの結果。読み直す (タイトルバーの Reload ボタン、または F5)。パスを指定して起動してもよい |
| 背景が透ける | 色が 0x01 になっている (「Window に描く」を参照) |
| 文字や図形が出ない | `Window.Present()` を呼んでいない |

wasm のエンジンのログは、どれも `wasm:` で始まる。アプリ自身のログの行にはアプリの名前
(`app_screen_name`、無ければファイル名) が付く。sim で `hello` を動かしたときの行:

```
wasm: runtime started (pool 256 KB at ..., 122 boundary functions, ...)     # the first wasm app
wasm: [TinyGo hello] loaded /app/tinygo/hello.app.wasm (7538 bytes, memory 2 pages, up to N, shared pool used N) on_create on_update on_event
TinyGo hello: hello: started                                                 # the app's own LogInfo
wasm: [TinyGo hello] ended (memory 2 pages)
wasm: runtime ended (pool high mark N of 261608 bytes)                       # the last wasm app
```

**SDK のバージョン。** SDK のライブラリは、どの言語でも自分のバージョンを `.wasm` の custom section
`fmrb.sdk` に入れる (中身は `0.1.0` のようなバージョンの文字列)。アプリの側ですることは無い。TinyGo のパッケージ、
Rust の `app!` マクロ、Zig のモジュールは自動で入れ、C のアプリは `FMRB_SDK_VERSION_SECTION();` で入れる。
ファームウェアは番号を比べない。ファームウェアに無い関数を import するアプリを断るときに、そのメッセージで
示すためだけに読む。中身は `wasm-objdump -s -j fmrb.sdk hello.app.wasm` (wabt) か、SDK の checkout で
`ruby tools/check_bindings.rb hello.app.wasm` (import のチェックもする) で見られる。

**メモリ。** アプリのリニアメモリは 64 KB のページ単位。TinyGo のアプリは 2 ページで始まり、確保に応じて
増える。上限は `loaded` の行の `up to N` で、アプリのメモリプールの空きから 64 KB を引いた分。大きい
`FileRead` や大きなスライスもここから取る。足りなくなると Go のランタイムが panic する (上のトラップに
なる)。`.app.toml` に `large_memory = 1` を書くと、端末にあれば大きいプールを使う。

## 9. 今の制約

- `tinygo/fmrb/raw` は境界の全部を持つ (生成物)。`fmrb` パッケージはそのうちよく使う部分を Go らしい形に
  ラップしている (描画、文字とフォント、画像、アプリの情報、時計、音、ファイル全体の FmrbFile、ログ)。ほかは
  `raw` を直接呼ぶ。
- フックとレコードの形は暫定で、ファームウェアに合わせて変わることがある。
- Rust と Zig: 手書きの層がラップするのは TinyGo と同じよく使う部分。どちらもアロケータを使わない (文字列は固定の
  バッファで受け取る)。Rust の crate は crates.io にまだ出しておらず、リリースのタグもまだ無い。Go・Cargo・Zig は
  git のリポジトリの既定のブランチから SDK を取ってくる ([maintaining.ja.md](maintaining.ja.md) の「配布」)。
- wasm のアプリは ESP32-S3 のボードでは動かない (1 章)。
- 開発用のリモート操作には認証が無く、リリースビルドにはまだ入っていない (7 章の b)。
