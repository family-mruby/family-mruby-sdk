//! tour: hello plus a tour of the main functions, one page at a time --
//! shapes, text (Japanese too), a picture, sound and the system side (the
//! app's information, clocks, memory, a file, the last input). Every SDK
//! language has this same app with the same screen (tinygo/examples/tour
//! and c/examples/tour are the TinyGo and C ones), so the languages can be
//! compared line by line; the common specification is in docs/tour.md.
//!
//!     click or 1-5   change page
//!     q              quit
//!     the page's own keys are listed at its bottom
#![no_std]

use fmrb::{Event, Image, Text, AUDIO, WINDOW};

// The page is white and the palette is picked for contrast against it
// (RGB332, RRRGGGBB). 0x01 would be the transparent key: not used.
const PAPER: i32 = 0xFF; // page background (white)
const INK: i32 = 0x00; // body text and outlines (black)
const INK_SUB: i32 = 0x49; // captions (dark gray)
const C_RED: i32 = 0xC0;
const C_GREEN: i32 = 0x0C;
const C_BLUE: i32 = 0x02;
const C_ORANGE: i32 = 0xE8; // stands in for yellow
const C_TEAL: i32 = 0x0F; // stands in for cyan
const C_PURPLE: i32 = 0x82; // stands in for magenta
const C_PANEL: i32 = 0xB6; // light gray fill

const PICTURE: &str = "/usr/share/asterism/icon.png";
const CACHED: &str = "/cache/app/tour/icon.png";
const DATA_FILE: &str = "/home/tour.txt";
const SAMPLE_JA: &str = "\u{3053}\u{3093}\u{306b}\u{3061}\u{306f} ABC \u{65e5}\u{672c}\u{8a9e}"; // konnichiwa ABC nihongo

const PAGES: [&str; 5] = ["Shapes", "Text", "Image", "Sound", "System"];
const KEYS: [&str; 5] = [
    "click or 1-5: pages  q: quit",
    "T: font",
    "I: show / hide the picture",
    "1 scale  3 beep  0 stop",
    "W: write a file",
];
const SCALE: [i32; 8] = [262, 294, 330, 349, 392, 440, 494, 523];

/// A line to draw.
type Line = Text<64>;

struct Tour {
    page: usize,
    font_mode: usize,
    started: i64,
    blink: bool,
    img: Option<Image>,
    img_tried: bool,
    img_shown: bool,
    note_off_at: [i64; 2],  // per channel, 0: no note
    scale_i: Option<usize>, // next note of the scale
    scale_at: i64,
    file_text: Text<24>,
    input: Text<32>,
}

impl Default for Tour {
    fn default() -> Self {
        Tour {
            page: 0,
            font_mode: 0,
            started: 0,
            blink: false,
            img: None,
            img_tried: false,
            img_shown: true,
            note_off_at: [0; 2],
            scale_i: None,
            scale_at: 0,
            file_text: Text::from("-"),
            input: Text::from("-"),
        }
    }
}

fn text(x: i32, y: i32, s: &str, color: i32) {
    WINDOW.draw_text_bg(x, y, s, color, PAPER);
}

fn platform() -> &'static str {
    if fmrb::app::platform() == fmrb::app::ESP32 {
        "esp32"
    } else {
        "linux"
    }
}

impl fmrb::App for Tour {
    fn on_create(&mut self) {
        self.started = fmrb::uptime_ms();
        self.read_data();
        fmrb::log::info(Line::from("tour: started on ").push(platform()).as_str());
        self.draw();
    }

    fn on_destroy(&mut self) {
        AUDIO.note_off(0);
        AUDIO.note_off(1);
        if let Some(img) = &self.img {
            WINDOW.delete_image(img);
        }
        fmrb::log::info("tour: bye");
    }

    // ---- the loop and input

    fn on_update(&mut self) -> i32 {
        let now = fmrb::uptime_ms();
        self.tick_sound(now);
        let blink = (now - self.started) / 500 % 2 == 0;
        if blink != self.blink {
            self.blink = blink;
            if self.page == 4 {
                self.draw();
            }
        }
        100
    }

    fn on_event(&mut self, ev: &Event) {
        match ev.kind() {
            fmrb::MOUSE_UP => {
                if ev.button != 1 {
                    return;
                }
                self.input
                    .clear()
                    .push("click ")
                    .int(ev.x as i64)
                    .push(",")
                    .int(ev.y as i64);
                self.set_page((self.page + 1) % PAGES.len());
            }
            fmrb::KEY_DOWN => {
                if ev.character > ' ' as i32 && ev.character < 127 {
                    self.input.clear().push("key ").push_char(ev.character as u8 as char);
                } else {
                    self.input.clear().push("key code ").int(ev.keycode as i64);
                }
                self.key(ev);
            }
            _ => {}
        }
    }
}

impl Tour {
    // ---- the page frame

    fn draw(&mut self) {
        let g = WINDOW;
        let (w, h) = (g.area_width(), g.area_height());
        g.fill_rect(0, 0, w, h, PAPER);
        text(
            4,
            2,
            Line::new()
                .int(self.page as i64 + 1)
                .push("/5 ")
                .push(PAGES[self.page])
                .as_str(),
            INK,
        );
        let y0 = 14;
        match self.page {
            0 => self.draw_shapes(y0),
            1 => self.draw_text(y0),
            2 => self.draw_image(y0),
            3 => self.draw_sound(y0),
            _ => self.draw_system(y0),
        }
        text(4, h - 10, KEYS[self.page], INK_SUB);
        g.present();
    }

    fn set_page(&mut self, p: usize) {
        self.page = p;
        fmrb::log::info(Line::from("tour: page ").push(PAGES[p]).as_str());
        self.draw();
    }

    // ---- page 1: shapes

    fn draw_shapes(&self, y0: i32) {
        let g = WINDOW;
        g.draw_round_rect(6, y0 + 4, 56, 26, 6, C_TEAL);
        g.fill_round_rect(70, y0 + 4, 56, 26, 6, C_GREEN);
        g.draw_ellipse(34, y0 + 52, 26, 14, C_PURPLE);
        g.fill_ellipse(98, y0 + 52, 26, 14, C_RED);
        g.draw_triangle(8, y0 + 104, 60, y0 + 104, 34, y0 + 74, C_ORANGE);
        g.fill_triangle(72, y0 + 104, 124, y0 + 104, 98, y0 + 74, C_BLUE);
        let colors = [C_RED, C_ORANGE, C_GREEN, C_TEAL];
        for (i, dx) in [-30, -10, 10, 30].into_iter().enumerate() {
            g.draw_line(160, y0 + 104, 160 + dx, y0 + 8, colors[i]);
        }
        for i in 0..3 {
            g.draw_circle(140 + i * 22, y0 + 40, 9, INK);
            g.fill_circle(140 + i * 22, y0 + 40, 4, C_PANEL);
        }
    }

    // ---- page 2: text

    fn draw_text(&self, y0: i32) {
        let g = WINDOW;
        let modes = ["default font", "ja font", "mixed (ascii + ja)"];
        text(6, y0 + 6, modes[self.font_mode], INK_SUB);
        match self.font_mode {
            0 => text(6, y0 + 20, "ABC abc 123", C_BLUE),
            1 => {
                g.set_font(fmrb::FONT_JA, 12);
                text(6, y0 + 20, SAMPLE_JA, C_BLUE);
                g.set_font(fmrb::FONT_DEFAULT, 0);
            }
            _ => g.draw_text_mixed(6, y0 + 20, SAMPLE_JA, C_BLUE, PAPER),
        }
        let sum: i64 = (1..=10).sum();
        let rows: [Line; 5] = [
            *Line::from("language ").push(fmrb::app::language().as_str()),
            *Line::from("sum(1..10) = ").int(sum),
            *Line::from("2^16 = ").int(1 << 16),
            *Line::from("area ")
                .int(g.area_width() as i64)
                .push("x")
                .int(g.area_height() as i64),
            *Line::from("SDK ").push(fmrb::SDK_VERSION),
        ];
        for (i, r) in rows.iter().enumerate() {
            text(6, y0 + 40 + i as i32 * 10, r.as_str(), INK);
        }
    }

    // ---- page 3: a picture

    fn draw_image(&mut self, y0: i32) {
        let g = WINDOW;
        if !self.img_tried {
            self.img_tried = true;
            if g.sync_file(PICTURE, CACHED) {
                self.img = g.create_image(CACHED);
            }
            if self.img.is_none() {
                fmrb::log::warn(Line::from("tour: no picture from ").push(PICTURE).as_str());
            }
        }
        text(6, y0 + 6, PICTURE, INK_SUB);
        let Some(img) = &self.img else {
            text(6, y0 + 20, "no picture", C_RED);
            return;
        };
        if self.img_shown {
            g.draw_image(img, 6, y0 + 20, 2.0);
        }
        text(80, y0 + 20, Line::from("id ").int(img.id as i64).as_str(), INK);
        text(
            80,
            y0 + 32,
            Line::new()
                .int(img.width as i64)
                .push("x")
                .int(img.height as i64)
                .push(" px, x2")
                .as_str(),
            INK,
        );
    }

    // ---- page 4: sound

    fn draw_sound(&self, y0: i32) {
        let rows = [
            "1: a scale on pulse 1",
            "3: a beep on pulse 2",
            "0: stop",
            "",
            "notes end by the clock",
        ];
        for (i, r) in rows.iter().enumerate() {
            text(6, y0 + 6 + i as i32 * 12, r, if i == 4 { INK_SUB } else { INK });
        }
    }

    // A note sounds until it is switched off, so its end is booked by the
    // clock (frames stretch when drawing is slow).
    fn note(&mut self, ch: usize, freq: i32, ms: i64, volume: i32) {
        AUDIO.note_on_raw(ch as i32, freq, volume, 2, 0);
        self.note_off_at[ch] = fmrb::uptime_ms() + ms;
    }

    fn silence(&mut self) {
        for ch in 0..2 {
            AUDIO.note_off(ch as i32);
            self.note_off_at[ch] = 0;
        }
        self.scale_i = None;
    }

    fn tick_sound(&mut self, now: i64) {
        for ch in 0..2 {
            let at = self.note_off_at[ch];
            if at != 0 && at <= now {
                AUDIO.note_off(ch as i32);
                self.note_off_at[ch] = 0;
            }
        }
        if let Some(i) = self.scale_i {
            if now >= self.scale_at {
                if i >= SCALE.len() {
                    self.scale_i = None;
                    return;
                }
                self.note(0, SCALE[i], 150, 12);
                self.scale_i = Some(i + 1);
                self.scale_at = now + 200;
            }
        }
    }

    // ---- page 5: the system side

    fn read_data(&mut self) {
        let mut buf = [0u8; 16];
        self.file_text = match fmrb::file::read(DATA_FILE, &mut buf) {
            Some(d) => Text::from(core::str::from_utf8(d).unwrap_or("?")),
            None => Text::from("-"),
        };
    }

    // W: count the writes in a file of the app's own (under /home).
    fn write_data(&mut self) {
        let mut buf = [0u8; 16];
        let mut n: i64 = 0;
        for &c in fmrb::file::read(DATA_FILE, &mut buf).unwrap_or(&[]) {
            if c.is_ascii_digit() {
                n = n * 10 + (c - b'0') as i64;
            }
        }
        if !fmrb::file::write(DATA_FILE, Text::<24>::new().int(n + 1).as_str().as_bytes()) {
            fmrb::log::warn(Line::from("tour: cannot write ").push(DATA_FILE).as_str());
        }
        self.read_data();
    }

    fn draw_system(&self, y0: i32) {
        let g = WINDOW;
        let mut clock = Line::from("-");
        if let Some(c) = fmrb::wallclock() {
            clock
                .clear()
                .int2(c.hour as i64)
                .push(":")
                .int2(c.minute as i64)
                .push(":")
                .int2(c.second as i64);
        }
        // the .app.toml next to the .app.wasm this app was started from
        let script = fmrb::app::script_path();
        let mut toml = Line::from("-");
        if let Some(stem) = script.as_str().strip_suffix(".wasm") {
            if let Some(n) = fmrb::file::size(Text::<128>::from(stem).push(".toml").as_str()) {
                toml.clear().int(n).push(" B");
            }
        }
        let rows: [(&str, Line); 10] = [
            ("name", Line::from(fmrb::app::name().as_str())),
            ("pid", *Line::new().int(fmrb::app::pid() as i64)),
            ("platform", Line::from(platform())),
            ("language", Line::from(fmrb::app::language().as_str())),
            (
                "uptime",
                *Line::new().int((fmrb::uptime_ms() - self.started) / 1000).push(" s"),
            ),
            ("clock", clock),
            (
                "memory",
                *Line::new().int((fmrb::memory_free() / 1024) as i64).push(" KB free"),
            ),
            ("toml", toml),
            ("file", Line::from(self.file_text.as_str())),
            ("input", Line::from(self.input.as_str())),
        ];
        for (i, (label, value)) in rows.iter().enumerate() {
            let y = y0 + 6 + i as i32 * 11;
            text(6, y, label, INK_SUB);
            text(86, y, value.as_str(), INK);
        }
        if self.blink {
            g.fill_circle(g.area_width() - 10, y0 + 8, 3, C_GREEN);
        }
    }

    fn key(&mut self, ev: &Event) {
        let sc = ev.scancode;
        if ev.character == 'q' as i32 {
            fmrb::app::stop();
            return;
        }
        if self.page == 3 {
            match sc {
                0x1E => {
                    // 1
                    self.scale_i = Some(0);
                    self.scale_at = fmrb::uptime_ms();
                    return;
                }
                0x20 => {
                    // 3
                    self.note(1, 988, 90, 14);
                    return;
                }
                0x27 => {
                    // 0
                    self.silence();
                    return;
                }
                _ => {}
            }
        }
        match sc {
            0x1E..=0x22 => {
                // 1-5
                self.set_page((sc - 0x1E) as usize);
                return;
            }
            0x17 if self.page == 1 => self.font_mode = (self.font_mode + 1) % 3, // T
            0x0C if self.page == 2 => self.img_shown = !self.img_shown,          // I
            0x1A if self.page == 4 => self.write_data(),                         // W
            _ => {}
        }
        self.draw();
    }
}

fmrb::app!(Tour);
