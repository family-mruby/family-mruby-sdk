# Family mruby SDK 入門

[English](getting_started.md)

この文書は、何も入っていない PC から始めて、TinyGo で書いたアプリを Family mruby の上で動かすまでの手順を
示す。Linux のシミュレーション (sim)、WiFi で送る ESP32-P4 のボード、Web のブラウザ版の 3 か所で動かす。
C のアプリも、ビルドのスクリプトが違うだけで同じ手順になる (6 章)。題材は
このリポジトリの `tinygo/examples/hello`。`hello` を自分のアプリの名前に読み替えれば、同じ手順で自分の
アプリを作れる。

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
`tinygo/fmrb/raw` (全部の関数・レコード・選択肢) を生成する。パッケージ `tinygo/fmrb` はその上の手書きの層
(フックと、よく使う関数の Go らしい形) で、生成物が境界と食い違っていないかは `tools/check_bindings.rb` で確認する。

今 wasm のアプリが動く端末:

| 端末 | wasm のアプリ |
|---|---|
| ESP32-P4 のボード (Modern。M5Stack Tab5 など) | 動く |
| Linux の sim (docker) | 動く |
| ESP32-S3 (Retro) | 動かない。起動は `wasm apps are not in this build` で断られる |
| ネイティブ版 (Linux の 1 プロセス)、ブラウザ版 | 動く (公開中のブラウザ版には `TinyGo bounce` と `TinyGo hello` が入っている。7 章の c) |

## 2. 用意するもの

- **TinyGo** と、それに対応する **Go**。この文書は TinyGo 0.44.0 と Go 1.26.11 で確認した。どちらも
  配布のアーカイブから入れる (<https://tinygo.org/getting-started/install/>、<https://go.dev/dl/>)。
- **Ruby** (3.x)。ビルドと確認のスクリプトに使う。
- C のアプリには **Zig** (その `zig cc`。Zig 0.17.1 で確認した)。`~/toolchains/zig-<版>/` に展開する
  (または `ZIG=` で実行ファイルを指定)。clang と wasm-ld でもよい (`CC=clang`)。libc は要らない。
- **git**。
- sim で動かすなら: Family mruby の開発用のツリー (`family-mruby` リポジトリに `fmruby-core` と
  `fmruby-graphics-audio` を取り込んだもの) と Docker。そちらの README の「Testing Without Hardware」を参照。
- ボードで動かすなら: ファームウェアの**開発用ビルド**が入っていて WiFi を設定した ESP32-P4 のボード
  (設定は fmruby-core の `config/wifi.toml.example`)、それと `curl`。

`tinygo/build.rb` はツールチェーンを 1 つのディレクトリから探す。既定は `~/toolchains`:

```
~/toolchains/tinygo/bin/tinygo     # TinyGo の配布物を展開したもの
~/toolchains/go/bin/go             # Go の配布物を展開したもの
~/toolchains/cache/                # build.rb が作る (Go と TinyGo のキャッシュ)
```

ここに置くか、別のディレクトリを環境変数 `TOOLCHAINS` で、`tinygo` の実行ファイルを `TINYGO` で指定する。
入ったかどうかは次で確認する:

```
~/toolchains/tinygo/bin/tinygo version
~/toolchains/go/bin/go version
```

## 3. SDK を取ってくる

```
git clone https://github.com/family-mruby/family-mruby-sdk.git
cd family-mruby-sdk
```

| パス | 中身 |
|---|---|
| `tinygo/fmrb/` | TinyGo のパッケージ: フック、`Window`、`App`、音、ファイル、ログ |
| `tinygo/fmrb/raw/` | 境界の全部の関数・レコード・選択肢 (生成物) |
| `tinygo/examples/` | サンプルアプリ (`hello`・`tour`・`bounce`)。1 ディレクトリが 1 アプリで、`main.go` と `.app.toml` を置く |
| `tinygo/build.rb` | サンプル 1 つをビルドして `<名前>.app.wasm` とその `.app.toml` を作る |
| `c/` | C のヘッダ (`fmrb_boundary.h`・`fmrb_sdk_version.h`)、`build.rb`、`examples/tour` |
| `tools/check_bindings.rb` | 生成物とアプリの import を境界と照合する |
| `docs/tour.md` | サンプル `tour` の仕様 (どの言語でも同じアプリ) |

## 4. アプリの形

アプリは `tinygo/examples/<名前>/main.go` に置く Go の `main` パッケージ。型を 1 つ作り、その値を `init` から
`fmrb.SetApp` で登録し、使いたいフックをメソッドとして書く。書かなかったフックは呼ばれないだけ。
`tinygo/examples/hello/main.go` の全体:

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

`tinygo/examples/tour` はもう一歩進んだサンプルで、図形・日本語の文字・画像・音・ファイル・時計・アプリの
情報を 5 ページで見せる。SDK のどの言語でも同じアプリ (C は `c/examples/tour/app.c`。仕様は `docs/tour.md`) なので、
言語ごとの書き方を比べる場所にもなる。`fmrb` パッケージが包んでいないものは `fmrb/raw` にある (生成物。境界の
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

`OnEvent` には、ファームウェアの 60 バイトのイベントレコードの写しが渡る。`ev.Type` は `fmrb.KeyDown`・
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
決めるファイルで、ソースと一緒に管理するとよい。`hello` では `tinygo/examples/hello/hello.app.toml`:

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
| `default_window_width`・`default_window_height` | Window の大きさ (ドット、枠込み) | 100・100 |
| `default_window_pos_x`・`default_window_pos_y` | Window を開く位置 | 50・50 |
| `resizable` | 1: 利用者が大きさを変えられる (`OnResize` が呼ばれる) | 0 |
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
| `sdk_version` | アプリをビルドした SDK の版。ビルドのスクリプトが書く。ファームウェアに無い関数を使うアプリを断るとき、ファームウェアはこの版を示す。SDK が 0.x の間は、古いアプリを壊す変更で真ん中の番号 (0.1 → 0.2)、追加で最後の番号が上がる。1.0.0 からは最初と真ん中 (README の「版」) | なし |

- **カテゴリは `/app` の下のディレクトリで決まる** (`/app/tinygo/`・`/app/mine/` など。どのディレクトリでも
  よい)。ランチャーは全カテゴリのアプリを名前順に並べて出す (端末の設定でカテゴリごと隠すこともできる)。
- エンジンは拡張子 (`.wasm`) で決まる。`bounce.app.toml` にある `language = "tinygo"` は人向けのメモで、
  ファームウェアは読まない。
- アイコンは 12x12 の文字の格子 (`.icon`) と、そこから作る BMP を隣に置く (fmruby-core の
  `tools/gen_icon_bmp.rb`)。書式は fmruby-core の `flash/app/` にある `.icon` を写すのが早い。

## 6. ビルド

```
ruby tinygo/build.rb hello
```

```
.../tinygo/bin/tinygo build -target=wasm-unknown -gc=conservative -opt=z -no-debug -o .../tinygo/build/hello.app.wasm ./examples/hello
.../tinygo/build/hello.app.wasm (7538 bytes)
.../tinygo/build/hello.app.toml (sdk_version = "0.1.0")
```

- 出力先は `tinygo/build/` (git の管理外)。`-o <ディレクトリかファイル>` で別の場所に出せる。たとえば
  fmruby-core の `flash/app/tinygo` に直接出せる。
- フラグは SDK が固定している: `wasm-unknown` (WASI なし)、conservative の GC (メモリを解放する)、
  サイズ優先の最適化、デバッグ情報なし。
- サンプルの `hello.app.toml` が `.wasm` の隣に、`sdk_version` を入れて書かれる (既にあれば、ほかの行は
  そのまま残す)。
- 任意: アプリの import とフックを境界と照合する:

  ```
  ruby tools/check_bindings.rb tinygo/build/hello.app.wasm
  ruby tools/check_bindings.rb --against v0.1.0 tinygo/build/hello.app.wasm   # リリースの版の境界と
  ```

  見つけた import とフックを表示し、最後に `ok` と出る。

### C

```
ruby c/build.rb tour        # -> c/build/tour.app.wasm と tour.app.toml
```

C のアプリは `fmrb_boundary.h` を include して平らな関数を呼び (`fmrb_gfx_fill_rect(0, x, y, w, h, color)`。
描画先 0 が Window)、使うフック (`void on_create(void)`・`int32_t on_update(void)`・
`void on_event(const fmrb_app_event_t *ev)` など) を定義し、どれか 1 つのファイルに `FMRB_EVENT_BUFFER();` と
書く。libc は無い。ビルドは `zig cc -target wasm32-freestanding -nostdlib -Os -Wl,--no-entry
-Wl,-z,stack-size=16384`。コンパイラが `memcpy`・`memset` を求めたら自分で定義する (`c/examples/tour/app.c` が
そうしている)。文字列はポインタと長さで渡し、NUL 終端ではない。

## 7. 動かす

### (a) Linux の sim で動かす

Family mruby の開発用のツリーで行う (以下の `<fmruby-core>` はその中の `fmruby-core` ディレクトリ)。

1. sim の `/app` にアプリを置く。Linux では `/app` は fmruby-core の `flash/app` ディレクトリそのもので、
   置けばそのまま読まれる (イメージの作り直しは要らない)。

   ```
   ruby tinygo/build.rb hello -o <fmruby-core>/flash/app/tinygo
   ```

2. fmruby-core と fmruby-graphics-audio を Linux 向けにビルドし (それぞれで `rake build:linux`。直前が
   ESP32 向けのビルドなら先に `rake clean_all`)、sim を起動する (family-mruby で `docker compose up`)。
3. アプリを起動する:
   - ランチャーから: ランチャーは一覧を前回の起動から覚えているので、先に読み直す (タイトルバーの
     Reload ボタン、または F5)。その後 `TinyGo hello` をダブルクリックする。
   - パスを指定して: デバッグ用のクライアントを使う (Python の `msgpack` が要る)。

     ```
     python3 <fmruby-core>/tools/debug/fmrb_dbg_client.py localhost spawn path=/app/tinygo/hello.app.wasm
     ```

4. キーを押す。押した文字が `key` の行に出る。スペースでカウンタが 0 に戻り、`q` でアプリが閉じる
   (閉じるボタンでも閉じる)。
5. ログを見る: `docker logs fmruby_core 2>&1 | grep -E "wasm|hello"`。

### (b) ESP32-P4 のボードで WiFi 経由で動かす

ファームウェアの開発用ビルドには HTTP (port 80) の遠隔操作が入っていて、ファイルの書き込みとアプリの起動が
できる。焼き直しは要らない。ボードのアドレス (ルータのクライアント一覧、または mDNS の名前
`fmruby-XXXXXX.local`) を調べ、`<device-ip>` に入れる:

```
curl -X POST "http://<device-ip>/fs/mkdir?path=/app/mine"
curl -T tinygo/build/hello.app.wasm "http://<device-ip>/fs/put?path=/app/mine/hello.app.wasm"
curl -T tinygo/build/hello.app.toml "http://<device-ip>/fs/put?path=/app/mine/hello.app.toml"
curl -X POST "http://<device-ip>/app/launch?path=/app/mine/hello.app.wasm"
```

どれも JSON (`{"ok":true,...}`) で答える。起動の答えには `pid` も入る。`/fs/put` はディレクトリを作らない
ので、カテゴリのディレクトリは最初に 1 回 `/fs/mkdir` で作る (既にあれば失敗するだけで害はない)。ビルドし
直したら `.wasm` を put して起動し直す。止めるには `q`、閉じるボタン、または
`curl -X POST "http://<device-ip>/app/kill?pid=<pid>"` を使う (動いているアプリの一覧は `GET /app/list`)。

curl の代わりに、Family mruby のリポジトリの `tools/fmrb_rd_fs.rb` (`put`・`ls`・`get`・`mkdir` と対話モード) と
`tools/fmrb_rd_launch.rb` も使える:

```
ruby tools/fmrb_rd_fs.rb <device-ip> put tinygo/build/hello.app.wasm /app/mine/hello.app.wasm
ruby tools/fmrb_rd_launch.rb <device-ip> /app/mine/hello.app.wasm
```

この遠隔操作は認証が無く、開発用ビルドにだけ入っている。信頼できるネットワークでだけ使うこと。
**リリースビルド**には今は入っていない。リリースビルドでは、端末の上で許可したとき (設定と、画面に出る
短いコード) だけ開く形にする計画で、そうなれば同じ put と launch の手順がリリースビルドでも使える。
入ったらこの文書を直す。

ボードのログはシリアルに出る (fmruby-core の `rake monitor` か、任意のシリアルモニタ)。WiFi には流れない。

### (c) ブラウザで動かす

公開中のブラウザ版 <https://family-mruby.github.io/studio/> でも wasm のアプリが動く (同じ WAMR をページに
組み込んである)。何もインストールしなくてよい。ランチャーには `TinyGo bounce` と `TinyGo hello` が入っている。
自分のアプリを動かすには:

1. アプリの 2 つのファイルを、アプリの名前のフォルダに入れる: `hello/hello.app.wasm` と `hello/hello.app.toml`
   (ビルドが両方を `tinygo/build/` に書くので、フォルダに写す)。
2. ページを開き、デスクトップが出るまで待つ。画面の下の **Your files** の欄で **Add Folder...** からフォルダを
   選ぶか、フォルダをページのどこかにドロップする。一番上に `<名前>.app.toml` があるフォルダは
   `/app/usr/<フォルダ>/` (自分で足すアプリの置き場) に入る。それ以外は `/home` に入る。**Files...** で
   ファイルを 1 つずつ足すときは、**into** の一覧で選んだ場所に入るので `/app/usr` を選ぶ。
3. ランチャーの一覧を読み直して (タイトルバーの Reload ボタン、または F5) アプリをダブルクリックする。
   または Shell を開いて `run /app/usr/hello/hello.app.wasm` と打つ。
4. ログはブラウザの開発者ツールのコンソール (F12) に、sim と同じ行で出る。

ファイルはブラウザの記憶域に残る (`/app/usr` と `/home` はページを読み直しても消えない。欄の **Backup** で
.tar に保存できる)。ビルドし直したら、もう一度フォルダを足すと新しいファイルで置き換わる。SDK より古い
ブラウザ版は、自分に無い関数を使うアプリを理由つきで断る (8 章)。

## 8. うまくいかないとき

| 症状 | 原因と対処 |
|---|---|
| アプリの代わりに**エラーの Window** (`Error: <名前>`、クリックで閉じる) が出る | 読み込みの時点で断られたか、フックがトラップしたか、長く走りすぎた。理由は Window とログ (`wasm: [<名前>] <フック> stopped: <理由>`) に出る。そのアプリのフックはもう呼ばれない |
| `on_update: Exception: instruction limit exceeded` | 1 回のフックの呼び出しで実行できるのは 2,000 万命令まで。長い処理は複数回の `OnUpdate` に分ける |
| `... Exception: unreachable` などのトラップ | たいていは Go の panic (範囲外の添字、nil、メモリ不足)。そのフックの処理を見直す。`LogInfo` を挟むと場所を絞れる |
| `No on_create, on_update or on_event in ...` | 3 つのどれも export していないので、読み込みの時点で断られた。`fmrb` パッケージでビルドした TinyGo のアプリは必ず export するので、C などほかの言語向けの話 |
| `wasm: [<名前>] <フック> takes N and returns M values, expected ...` | フックの形が違う (古い SDK でビルドしたアプリ)。今の SDK でビルドし直す |
| `on_event needs fmrb_event_buffer (the SDK's event buffer) or a stack pointer global (__stack_pointer) for its record` | 古い SDK でビルドしたアプリで、ファームウェアがイベントのレコードを置く場所が無い (最適化でスタックポインタが消えた小さいアプリ)。今の SDK でビルドし直す。`fmrb` パッケージは、ファームウェアがレコードを書き込む置き場 `fmrb_event_buffer` を export する (C のアプリはどれか 1 つのファイルに `FMRB_EVENT_BUFFER();` と書く) |
| `imports fmrb.<名前>, which this firmware does not have ...: the app was built with SDK X.Y.Z, newer than this firmware; update the firmware` | ファームウェアに無い関数をアプリが使っている (SDK がファームウェアより新しい)。ファームウェアを更新するか、ファームウェアに合う版の SDK でビルドする。`in another shape than this firmware's` は、引数の変わった関数について同じこと |
| `imports <モジュール>.<名前>, but the firmware gives only "fmrb" functions` | WASI や libc の関数を import している (C の `printf` など)。使わずにビルドする |
| `... did not load: ...` / `... did not start: ...` | WAMR がモジュールを受け付けなかった (wasm でない、WAMR に無い機能、メモリ不足) |
| `wasm apps are not in this build` | その端末には WAMR が入っていない (ESP32-S3、または wasm のアプリに対応する前のネイティブ版・ブラウザ版) |
| ランチャーにアプリが出ない | ランチャーの一覧は前回の走査の結果。読み直す (タイトルバーの Reload ボタン、または F5)。パスを指定して起動してもよい |
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

**メモリ。** アプリのリニアメモリは 64 KB のページ単位。TinyGo のアプリは 2 ページで始まり、確保に応じて
増える。上限は `loaded` の行の `up to N` で、アプリのメモリプールの空きから 64 KB を引いた分。大きい
`FileRead` や大きなスライスもここから取る。足りなくなると Go のランタイムが panic する (上のトラップに
なる)。`.app.toml` に `large_memory = 1` を書くと、端末にあれば大きいプールを使う。

## 9. 今の制約

- `tinygo/fmrb/raw` は境界の全部を持つ (生成物)。`fmrb` パッケージはそのうちよく使う部分を Go らしい形に
  包んでいる (描画、文字とフォント、画像、アプリの情報、時計、音、ファイル全体の FmrbFile、ログ)。ほかは
  `raw` を直接呼ぶ。
- フックとレコードの形は暫定で、ファームウェアに合わせて変わることがある。
- Rust と Zig のバインディングは計画中 (同じ形で生成する)。
- wasm のアプリは ESP32-S3 のボードでは動かない (1 章)。
- 開発用の遠隔操作には認証が無く、リリースビルドにはまだ入っていない (7 章の b)。
