# The tour sample: one app, every language

Every language of the SDK has one sample called `tour`: hello plus a tour of
the main functions, with **the same content and the same screen** in each
language, so the languages can be compared line by line. This file is its
specification; a new language's tour follows it exactly (the TinyGo one,
`tinygo/examples/tour/main.go`, and the C one, `c/examples/tour/app.c`, are
the references). It is modelled on fmruby-core's MicroPython demo
(`flash/app/python/python.app.py`), limited to what the boundary offers to
every language.

`hello` stays the smallest getting-started app, and TinyGo keeps `bounce` as
a small animation demo; neither is part of this specification.

## Window and colors

- `.app.toml`: `app_screen_name = "<Language> tour"` (`TinyGo tour`,
  `C tour`, `Rust tour`, `Zig tour`), `language = "<language>"`, window
  230 x 175 at (45, 30). The build script adds `sdk_version`.
- Everything is drawn into the window's drawer (0) inside the area, and every
  text has the paper as its background.
- Colors (RGB332), as literal values:

  | Name | Value | Use |
  |---|---|---|
  | PAPER | 0xFF | page background (white) |
  | INK | 0x00 | text and outlines |
  | INK_SUB | 0x49 | captions |
  | RED | 0xC0 | |
  | GREEN | 0x0C | |
  | BLUE | 0x02 | |
  | ORANGE | 0xE8 | |
  | TEAL | 0x0F | |
  | PURPLE | 0x82 | |
  | PANEL | 0xB6 | light gray fill |

  Never 0x01: it is the desktop's transparent key.

## Every redraw

1. `fill_rect(0, 0, area_width, area_height, PAPER)`.
2. Header at (4, 2), INK: `"<n>/5 <Page>"` (n from 1).
3. The page's body, with `y0 = 14`.
4. Footer at (4, area_height - 10), INK_SUB: the page's keys (table below).
5. `present`.

| n | Page | Footer |
|---|---|---|
| 1 | Shapes | `click or 1-5: pages  q: quit` |
| 2 | Text | `T: font` |
| 3 | Image | `I: show / hide the picture` |
| 4 | Sound | `1 scale  3 beep  0 stop` |
| 5 | System | `W: write a file` |

## Pages

**1 Shapes** (x, y are area coordinates; y0 = 14):

- `draw_round_rect(6, y0+4, 56, 26, 6, TEAL)`, `fill_round_rect(70, y0+4, 56, 26, 6, GREEN)`
- `draw_ellipse(34, y0+52, 26, 14, PURPLE)`, `fill_ellipse(98, y0+52, 26, 14, RED)`
- `draw_triangle(8, y0+104, 60, y0+104, 34, y0+74, ORANGE)`,
  `fill_triangle(72, y0+104, 124, y0+104, 98, y0+74, BLUE)`
- for i, dx in (-30, -10, 10, 30): `draw_line(160, y0+104, 160+dx, y0+8, [RED, ORANGE, GREEN, TEAL][i])`
- for i in 0..2: `draw_circle(140+i*22, y0+40, 9, INK)`, `fill_circle(140+i*22, y0+40, 4, PANEL)`

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

**4 Sound**: rows from (6, y0+6), 12 dots apart: `1: a scale on pulse 1`,
`3: a beep on pulse 2`, `0: stop`, (empty), `notes end by the clock`
(INK_SUB; the others INK).

- `1`: the scale 262, 294, 330, 349, 392, 440, 494, 523 Hz on channel 0, one
  note every 200 ms, each 150 ms long, volume 12, duty 2, no sweep.
- `3`: 988 Hz on channel 1 for 90 ms, volume 14, duty 2.
- `0`: both channels off and the scale stopped.
- A note's end is booked by the clock (`uptime_ms`), checked in on_update.
- On this page `1`, `3` and `0` are the sound's; `2`, `4`, `5` still change page.

**5 System**: label at x 6 (INK_SUB), value at x 86 (INK), rows from y0+6,
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
| file | the content of `/home/tour.txt`, `-` without |
| input | the last input: `click <x>,<y>`, `key <c>` (a printable character), `key code <keycode>` (others), `-` at start |

- A blinking dot: `fill_circle(area_width - 10, y0 + 8, 3, GREEN)` while
  `(uptime_ms - start) / 500` is even; the page is redrawn when that flips.
- `W`: read `/home/tour.txt` as a decimal number (0 without), write the
  number + 1 back, show the file again.

## Input and the loop

- on_update: tick the sound, flip the blink (redraw page 5), return 100.
- Mouse up with button 1: input = `click x,y`, then the next page (5 -> 1).
- Key down: input as above, then: `q` (the character) stops the app; on the
  sound page the sound keys; scancodes 0x1E..0x22 (`1`-`5`) pick a page;
  `T` (0x17) on page 2, `I` (0x0C) on page 3, `W` (0x1A) on page 5; every
  key then redraws.
- Every page change logs `tour: page <Page>`; on_create logs
  `tour: started on <platform>` and draws page 1; on_destroy switches both
  channels off and logs `tour: bye`.
