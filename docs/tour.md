# The tour sample: one app, every language

Every language of the SDK has one sample called `tour`: hello plus a tour of
the main functions, with **the same content and the same screen** in each
language, so the languages can be compared line by line. This file is its
specification; a new language's tour follows it exactly. The four are
`tinygo/examples/tour/main.go`, `rust/examples/tour/src/lib.rs`,
`zig/examples/tour/app.zig` and `c/examples/tour/app.c` (TinyGo and C were
the first, the references; the C one uses the SDK's helper header
`c/fmrb.h`). It is modelled on fmruby-core's MicroPython demo
(`flash/app/python/python.app.py`), limited to what the boundary offers to
every language.

`hello` (TinyGo, Rust, Zig) stays the smallest getting-started app, and
TinyGo keeps `bounce` as a small animation demo; neither is part of this
specification.

## Window and colors

- `.app.toml`: `app_screen_name = "<Language> tour"` (`TinyGo tour`,
  `C tour`, `Rust tour`, `Zig tour`), `language = "<language>"`, window
  230 x 175 at (45, 30). The drawer's area is then 228 x 163; the pages
  below are laid out for it. The SDK version is in the `.wasm` (the custom
  section `fmrb.sdk`).
- Everything is drawn into the window's drawer (0) inside the area, and every
  text has the paper as its background. Coordinates below are area
  coordinates, with `y0 = 14` (the top of a page's body).
- Colors (RGB332), as literal values:

  | Name | Value | Use |
  |---|---|---|
  | PAPER | 0xFF | page background (white) |
  | INK | 0x00 | text |
  | INK_SUB | 0x49 | captions, labels, frames |
  | RED | 0xC0 | |
  | GREEN | 0x0C | |
  | BLUE | 0x02 | |
  | ORANGE | 0xE8 | |
  | TEAL | 0x0F | |
  | PANEL | 0xB6 | light gray fill |
  | SKY | 0x9B | the tile map's sky |

  Never 0x01: it is the desktop's transparent key.
- Assets: only files the firmware already has (`/usr/share/...`), each
  copied once with `sync_file` to `/cache/app/tour/<name>` before the
  graphics side reads it. Nothing is added to the board for the tour.

## Pages and keys

| n | Page | Footer |
|---|---|---|
| 1 | Shapes | `click, arrows, 1-9, 0: pages  q: quit` |
| 2 | Text | `T: font` |
| 3 | Image | `I: show / hide the picture` |
| 4 | Sprites | `H: hide / show one  P: pause` |
| 5 | Tiles | `arrows: pages  q: quit` |
| 6 | Sound | `S B: notes  M: tune  V: voice  X: off` |
| 7 | Files | `W: append  D: delete count.txt` |
| 8 | Input | `drag: draw  type  BS: clear` |
| 9 | System | `arrows: pages  q: quit` |
| 10 | System+ | `C: copy to the clipboard` |

Changing pages (every page):

- A click (mouse up, button 1) goes to the next page (10 -> 1), except on
  the Input page when the press began inside its pad.
- Right arrow (scancode 0x4F) the next page, left arrow (0x50) the previous
  one (1 -> 10); `1`-`9` (0x1E..0x26) pages 1-9, `0` (0x27) page 10: every
  page has its number key.
- `q` (the character) stops the app, on every page.
- A page's own keys are letters, by scancode, and only on that page: `T`
  0x17, `I` 0x0C, `H` 0x0B, `P` 0x13, `S` 0x16, `B` 0x05, `X` 0x1B, `M` 0x10,
  `V` 0x19, `W` 0x1A, `D` 0x07, `C` 0x06, backspace 0x2A.

## Every redraw

1. `fill_rect(0, 0, area_width, area_height, PAPER)`.
2. Header at (4, 2), INK: `"<n>/10 <Page>"` (n from 1).
3. The page's body.
4. Footer at (4, area_height - 10), INK_SUB: the page's keys (table above).
5. `present`.

## Pages

**1 Shapes**: three groups side by side, centred on y = 82, with column
centres x = 38, 114 and 190 (76 apart); every line is 1 dot wide. Four
colors: BLUE, TEAL, ORANGE, RED.

- Left, the filled shapes, each 57 x 25, 7 dots apart (rows at y 22, 54, 86,
  118):
  `fill_rect(10, 22, 57, 25, BLUE)`,
  `fill_round_rect(10, 54, 57, 25, 6, TEAL)`,
  `fill_ellipse(38, 98, 28, 12, ORANGE)`,
  `fill_triangle(10, 142, 66, 142, 38, 118, RED)`.
- Centre, concentric circles 8 dots apart: `draw_circle(114, 82, r, c)` for
  (r, c) in (8, RED), (16, ORANGE), (24, TEAL), (32, BLUE), then
  `fill_circle(114, 82, 3, RED)`.
- Right, a regular hexagon with r = 32 around (190, 82), pointing up. Its
  vertices, for k = 0..5 and a = -90 + 60 k degrees:
  `vx[k] = 190 + round(32 cos a)`, `vy[k] = 82 + round(32 sin a)`, where
  round is to the nearest integer, halves away from zero
  (`v >= 0 ? trunc(v + 0.5) : -trunc(-v + 0.5)`). They are (190, 50),
  (218, 66), (218, 98), (190, 114), (162, 98), (162, 66).
  - The three diagonals `draw_line(vx[k], vy[k], vx[k+3], vy[k+3], TEAL)`
    for k = 0..2;
  - the circle inside it, one dot clear of the sides:
    `draw_circle(190, 82, trunc(32 cos 30) - 1, ORANGE)`, radius 26 (from
    the apothem, 27.7, also computed);
  - the sides `draw_line(vx[k], vy[k], vx[(k+1) % 6], vy[(k+1) % 6], BLUE)`
    for k = 0..5;
  - `fill_circle(190, 82, 3, RED)`.

  r is even, so no value lands on a half and any sine accurate to 1e-9
  gives the same dots. Every tour brings the same small sine, as a wasm
  app has no libm (TinyGo's `math.Sin` would import libm's `sin`, Rust's
  `core` has none, C has no libc, and Zig's `@sin` brings compiler-rt's,
  7 KB): degrees folded into -90..90 (`d > 90: 180 - d`, `d < -90: -180 -
  d`), then the Taylor series of sin to x^13; cos a = sin(a + 90).

**2 Text**: a font mode 0..2, `T` steps it (0 -> 1 -> 2 -> 0).

- (6, y0+6) INK_SUB: `default font` / `ja font` / `mixed (ascii + ja)`.
- (6, y0+20) BLUE: mode 0 `ABC abc 123` in the default font; mode 1 the
  Japanese sample after `set_font(ja, 12)`, then `set_font(default, 0)`
  again; mode 2 the Japanese sample with `mixed` = 1 (default font). The
  Japanese sample is "konnichiwa ABC nihongo" in kana and kanji, U+3053 U+3093
  U+306B U+3061 U+306F, ` ABC `, U+65E5 U+672C U+8A9E (UTF-8; written with escapes in
  the sources, which stay ASCII).
- From (6, y0+40), 10 dots apart, INK: `language <app_language>`,
  `sum(1..10) = 55` and `2^16 = 65536` (computed in the language: a loop and
  a shift), `area <w>x<h>` (the drawer's area), `SDK <version>`.

**3 Image**: on the first visit, `sync_file("/usr/share/asterism/icon.png",
"/cache/app/tour/icon.png")` and `create_image` of the copy (once; log a
warning when it fails).

- (6, y0+6) INK_SUB: `/usr/share/asterism/icon.png`.
- Without a picture: (6, y0+20) RED `no picture`.
- With one: when shown (at start; `I` toggles), `draw_image` at (6, y0+20),
  scale 2.0; (80, y0+20) INK `id <id>`; (80, y0+32) INK `<w>x<h> px, x2`.
- The image is deleted in on_destroy.

**4 Sprites**: four placed sprites that move on their own, over the page.

- On the first visit: for each of `enemy1_a`, `enemy1_b`, `enemy2_a`,
  `enemy2_b` (`/usr/share/sprites/shooter/<name>.png`, 16 x 12), sync it and
  `create_sprite_image(16, 12, 0x00, 1)` (black is see-through), then
  `load_sprite_image(id, <the copy>)`. Then four instances, k = 0..3:
  `create_sprite_instance(k even ? [enemy1_a, enemy1_b] : [enemy2_a,
  enemy2_b], 16 + 52 k, y0 + 24 + 20 k, k)`. When an image cannot be made,
  log a warning and show `no sprites` (6, y0+20) RED instead.
- Body: (6, y0+4) INK_SUB `4 sprites, 2 frames each`; the field
  `draw_rect(6, y0+16, 216, 104, INK_SUB)`; (6, y0+124) INK
  `step <n>  <moving | paused>  1: <shown | hidden>  ` (two spaces at the
  end, so that `shown` covers a `hidden` drawn before).
- A step (each on_update on this page unless paused): every instance moves
  by (dx, dy), dx = 2, -2, 3, -3 and dy = 1, 2, -1, -2 for k = 0..3, and
  bounces inside the field: x is kept in 7..205 and y in y0+17..y0+107
  (past an end: put on the end and the sign of dx or dy turned).
  `move_sprite` each; n += 1; when n % 4 == 0 every instance shows frame
  `(n / 4) % 2` (`set_sprite_frame`). Then the status row is drawn again and
  `present`.
- `H` shows or hides instance 0 (`set_sprite_visible`); `P` pauses or goes
  on.
- Leaving the page hides all four; coming back shows them again (instance
  0 only when it is not hidden by `H`). on_destroy calls
  `delete_all_sprites`.

**5 Tiles**: `/usr/share/sprites/test/tilesheet.png` (64 x 32, 4 x 2 tiles of
16 x 16; 0 and 1 a chick, 2 a block, 3 a ledge, 4 grass, 5 water, 6 and 7
empty) as a small map.

- On the first visit: sync it, `create_sprite_image(64, 32, 0x00, 1)` and
  `load_sprite_image`; the sheet is drawn with `draw_tile` (the tile at
  column c, row r of the sheet is the source (16 c, 16 r, 16, 16)). When it
  cannot be made, log a warning and show `no tiles` (6, y0+20) RED instead.
- (6, y0+4) INK_SUB `draw_tile: one tile per call`.
- The sheet: `fill_rect(6, y0+16, 72, 36, PANEL)`, then tile i (0..7) at
  (8 + 18 (i % 4), y0 + 18 + 18 (i / 4)).
- (86, y0+18) INK `tilesheet.png`, (86, y0+30) INK `64x32 px, 8 tiles`,
  (86, y0+42) INK `a 12x4 map below`.
- The map: `fill_rect(18, y0+58, 192, 64, SKY)`, then the cells of these
  rows (`.` is nothing, a digit the tile) at (18 + 16 col, y0 + 58 + 16 row):

  ```
  ............
  ........33..
  ..0.1...22..
  444455554444
  ```

**6 Sound**: notes on the pulse channels, a tune and a voice. Rows from
(6, y0+6), 12 dots apart, INK: `S: a scale on pulse 1`, `B: a beep on
pulse 2`, `M: korobeiniki (FMSQ) on / off`, `V: a voice (WAV)`, `X: stop
it all`, (empty), `tune   <stopped | playing | cannot load>`, `voice  <- |
played | not on this machine | failed>`, (empty), `notes end by the clock`
(INK_SUB).

- `S`: the scale 262, 294, 330, 349, 392, 440, 494, 523 Hz on channel 0, one
  note every 200 ms, each 150 ms long, volume 12, duty 2, no sweep.
- `B`: 988 Hz on channel 1 for 90 ms, volume 14, duty 2.
- `M`, the first time: sync `/usr/share/music/korobeiniki.fmsq` to
  `/cache/app/tour/tune.fmsq` and `load_fmsq_file(0, <the copy>)` (on
  failure: `cannot load`, and `M` tries again). Then `M` alternates
  `play_slot_raw(0, 0)` (slot 0 on MAIN) and `stop`.
- `V`: `play_wav("/usr/share/sounds/voice/mahjong/default/pon.wav")`: 1
  `played`, 0 `not on this machine` (Retro), below 0 `failed`.
- `X`: both channels off, the scale stopped, and the tune stopped when it
  plays.
- A note's end is booked by the clock (`uptime_ms`), checked in on_update,
  on every page. Leaving the page stops the tune; on_destroy stops it too.

**7 Files**: FmrbFile in a directory of the tour's own, `/home/tour/`,
which exists only while the page is shown.

- Entering the page: `mkdir("/home/tour")`, then `write` of
  `/home/tour/hello.txt` with `hello from the tour`; leaving it (and in
  on_destroy): `delete` of `/home/tour/count.txt`, `/home/tour/hello.txt`
  and `/home/tour`.
- Rows from y0+6, 11 dots apart, the label at x 6 (INK_SUB), the value at
  x 58 (INK):

  | Label | Value |
  |---|---|
  | dir | `/home/tour/` |
  | wrote | `hello.txt, <size> B` (`file_size`) |
  | read | the content of hello.txt (`read`) |
  | count | `<n> lines`: the newlines in count.txt (`read`; 0 without it) |
  | list | the names of `list("/home/tour")` in its order, a space between |
  | free | `<file_free_bytes("/home/tour") / 1024> KB`, `-` without |
  | last | `-` at first, then `appended` / `deleted count.txt` / `no count.txt` |

- (6, y0+86) INK_SUB `all removed when you leave the page`.
- `W`: `append("/home/tour/count.txt", "w\n")`, last `appended`. `D`:
  `delete("/home/tour/count.txt")`: `deleted count.txt` when it was there,
  `no count.txt` when not.

**8 Input**: drawing with the pointer and typed characters.

- (6, y0+4) INK_SUB `drag inside the box to draw`; the pad
  `draw_rect(6, y0+16, 216, 84, INK_SUB)`.
- A press (mouse down, button 1) inside the pad starts a stroke; each
  mouse move while pressed adds a point, its x kept in 7..220 and y in
  y0+17..y0+98, and draws `draw_line(previous, point, BLUE)` then
  `present` (no full redraw); the release ends the stroke. Up to 256
  points are kept and redrawn with the page (a stroke of one point is a
  `set_pixel`); more are dropped. The release redraws the page (for the
  last input) and does not change the page.
- Rows: (6, y0+106) INK_SUB `typed`, (42, y0+106) INK the typed text;
  (6, y0+118) INK_SUB `last`, (42, y0+118) INK the last input.
- Typed text: on this page every key with a printable character (0x20 to
  0x7E) other than `q` and the digits is added; the last 30 are kept.
  Backspace clears the typed text and the strokes.
- The last input (on every page): `click <x>,<y>` (mouse up),
  `key <c>` (a character 0x21 to 0x7E), `key code <keycode>` (others), `-`
  at start.

**9 System**: label at x 6 (INK_SUB), value at x 86 (INK), rows from y0+6,
11 dots apart:

| Label | Value |
|---|---|
| name | `app_name` |
| pid | `app_pid` |
| platform | `esp32` or `linux` (`app_platform`) |
| language | `app_language` |
| uptime | seconds since on_create, `<n> s` |
| clock | `HH:MM:SS` from `app_wallclock`, `-` without one |
| memory | `<free / 1024> KB free` from `app_sys_pool_info` |
| toml | the size of the app's own `.app.toml` (`app_script_path` with `.wasm` -> `.toml`, `file_size`), `<n> B`, `-` without |

- A blinking dot: `fill_circle(area_width - 10, y0 + 8, 3, GREEN)` while
  `(uptime_ms - start) / 500` is even; the page is redrawn when that flips.

**10 System+**: the clipboard, the firmware's clock and the app's own wasm
numbers. Label at x 6 (INK_SUB), value at x 70 (INK), rows from y0+6, 11
dots apart; the page is redrawn every second.

| Label | Value |
|---|---|
| clipboard | `app_clipboard_raw(20)` up to its first newline, drawn mixed (Japanese too); `(empty)` |
| changes | `app_clipboard_gen` |
| wallclock | `gfx_draw_wallclock(70, y, INK, PAPER)` (the firmware formats it); `-` when it answers 0 |
| memory | `<pages> pages, max <max_pages>` (`app_wasm_app_stats(app_pid)`) |
| binary | `<binary_size> B` |
| hooks | `<calls> calls` |
| last hook | `<hook_us> us, max <hook_max_us>` |
| wasm apps | `<apps>, pool <pool_used / 1024> KB` (`app_wasm_stats`) |
| frames | `<presents>` (`app_gfx_stats`) |

A stats function that answers 0 shows `-`. `C` puts `copied by the tour`
on the clipboard (`app_set_clipboard`) and redraws.

## The loop

- on_update: end the notes and step the scale; flip the blink (redraw page
  9); step the sprites (page 4); redraw page 10 when the second changes;
  return 100.
- Every page change logs `tour: page <Page>`, after the page left and
  before the page entered (the order the Sprites, Sound and Files pages
  need). on_create logs `tour: started on <platform>` and draws page 1;
  on_destroy switches both channels off, stops the tune, cleans the Files
  page's directory, deletes the picture and the sprites, and logs
  `tour: bye`.
- Every key redraws the page after it is handled (except `q`).
