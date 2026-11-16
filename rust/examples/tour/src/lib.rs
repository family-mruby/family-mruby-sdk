//! tour: hello plus a tour of the main functions, one page at a time --
//! shapes, text (Japanese too), a picture, sprites, tiles, sound, a tune
//! and a voice, files, pointer and keys, and the system side (the app's
//! information, clocks, memory, the clipboard, its own wasm numbers). Every
//! SDK language has this same app with the same screen (tinygo/examples/tour
//! and c/examples/tour are the TinyGo and C ones), so the languages can be
//! compared line by line; the common specification is in docs/tour.md.
//!
//!     click, arrows, 1-9, 0   change page
//!     q                       quit
//!     the page's own keys are listed at its bottom
#![no_std]

use fmrb::{Event, Image, Sprite, SpriteImage, Text, AUDIO, WINDOW};

// The page is white and the palette is picked for contrast against it
// (RGB332, RRRGGGBB). 0x01 would be the transparent key: not used.
const PAPER: i32 = 0xFF; // page background (white)
const INK: i32 = 0x00; // body text (black)
const INK_SUB: i32 = 0x49; // captions, labels, frames (dark gray)
const C_RED: i32 = 0xC0;
const C_GREEN: i32 = 0x0C;
const C_BLUE: i32 = 0x02;
const C_ORANGE: i32 = 0xE8;
const C_TEAL: i32 = 0x0F;
const C_PANEL: i32 = 0xB6; // light gray fill
const C_SKY: i32 = 0x9B; // the tile map's sky

const Y0: i32 = 14; // the top of a page's body
const CACHE: &str = "/cache/app/tour/";
const PICTURE: &str = "/usr/share/asterism/icon.png";
const SHEET_SRC: &str = "/usr/share/sprites/test/tilesheet.png";
const TUNE_SRC: &str = "/usr/share/music/korobeiniki.fmsq";
const VOICE: &str = "/usr/share/sounds/voice/mahjong/default/pon.wav";
const DIR: &str = "/home/tour";
const HELLO: &str = "/home/tour/hello.txt";
const COUNT: &str = "/home/tour/count.txt";
const SAMPLE_JA: &str = "\u{3053}\u{3093}\u{306b}\u{3061}\u{306f} ABC \u{65e5}\u{672c}\u{8a9e}"; // konnichiwa ABC nihongo

const P_SHAPES: usize = 0;
const P_TEXT: usize = 1;
const P_IMAGE: usize = 2;
const P_SPRITES: usize = 3;
const P_TILES: usize = 4;
const P_SOUND: usize = 5;
const P_FILES: usize = 6;
const P_INPUT: usize = 7;
const P_SYSTEM: usize = 8;
const P_SYSTEM_PLUS: usize = 9;
const N_PAGES: usize = 10;

const PAGES: [&str; N_PAGES] = [
    "Shapes", "Text", "Image", "Sprites", "Tiles", "Sound", "Files", "Input", "System", "System+",
];
const KEYS: [&str; N_PAGES] = [
    "click, arrows, 1-9, 0: pages  q: quit",
    "T: font",
    "I: show / hide the picture",
    "H: hide / show one  P: pause",
    "arrows: pages  q: quit",
    "S B: notes  M: tune  V: voice  X: off",
    "W: append  D: delete count.txt",
    "drag: draw  type  BS: clear",
    "arrows: pages  q: quit",
    "C: copy to the clipboard",
];
const SCALE: [i32; 8] = [262, 294, 330, 349, 392, 440, 494, 523];
const SPRITE_FILES: [&str; 4] = ["enemy1_a", "enemy1_b", "enemy2_a", "enemy2_b"];
const TILE_MAP: [&str; 4] = ["............", "........33..", "..0.1...22..", "444455554444"];
const MAX_POINTS: usize = 256;

/// A line to draw.
type Line = Text<64>;

struct Tour {
    page: usize,
    font_mode: usize,
    started: i64,
    blink: bool,
    second: i64,
    img: Option<Image>,
    img_tried: bool,
    img_shown: bool,
    note_off_at: [i64; 2],  // per channel, 0: no note
    scale_i: Option<usize>, // next note of the scale
    scale_at: i64,
    input: Text<32>, // the last input
    // sprites
    spr_tried: bool,
    sprites: Option<[Sprite; 4]>,
    sx: [i32; 4],
    sy: [i32; 4],
    dx: [i32; 4],
    dy: [i32; 4],
    step: i32,
    paused: bool,
    hidden0: bool,
    // tiles
    sheet_tried: bool,
    sheet: Option<SpriteImage>,
    // a tune and a voice
    tune_loaded: bool,
    tune: &'static str,
    voice: &'static str,
    // files
    file_last: &'static str,
    // input
    pen: bool,
    n_pts: usize,
    pts: [(i32, i32, bool); MAX_POINTS], // x, y, the first point of a stroke
    typed: Text<30>,
}

impl Default for Tour {
    fn default() -> Self {
        Tour {
            page: 0,
            font_mode: 0,
            started: 0,
            blink: false,
            second: 0,
            img: None,
            img_tried: false,
            img_shown: true,
            note_off_at: [0; 2],
            scale_i: None,
            scale_at: 0,
            input: Text::from("-"),
            spr_tried: false,
            sprites: None,
            sx: [0; 4],
            sy: [0; 4],
            dx: [2, -2, 3, -3],
            dy: [1, 2, -1, -2],
            step: 0,
            paused: false,
            hidden0: false,
            sheet_tried: false,
            sheet: None,
            tune_loaded: false,
            tune: "stopped",
            voice: "-",
            file_last: "-",
            pen: false,
            n_pts: 0,
            pts: [(0, 0, false); MAX_POINTS],
            typed: Text::new(),
        }
    }
}

const G: fmrb::Gfx = WINDOW;

fn text(x: i32, y: i32, s: &str, color: i32) {
    G.draw_text_bg(x, y, s, color, PAPER);
}

/// A label and its value on one row.
fn row(x: i32, vx: i32, y: i32, label: &str, value: &str) {
    text(x, y, label, INK_SUB);
    text(vx, y, value, INK);
}

fn platform() -> &'static str {
    if fmrb::app::platform() == fmrb::app::ESP32 {
        "esp32"
    } else {
        "linux"
    }
}

fn cached(name: &str) -> Line {
    *Line::from(CACHE).push(name)
}

impl fmrb::App for Tour {
    fn on_create(&mut self) {
        self.started = fmrb::uptime_ms();
        fmrb::log::info(Line::from("tour: started on ").push(platform()).as_str());
        self.draw();
    }

    fn on_destroy(&mut self) {
        AUDIO.note_off(0);
        AUDIO.note_off(1);
        AUDIO.stop();
        clean_files();
        if let Some(img) = &self.img {
            G.delete_image(img);
        }
        G.delete_all_sprites();
        fmrb::log::info("tour: bye");
    }

    // ---- the loop and input

    fn on_update(&mut self) -> i32 {
        let now = fmrb::uptime_ms();
        self.tick_sound(now);
        let blink = (now - self.started) / 500 % 2 == 0;
        if blink != self.blink {
            self.blink = blink;
            if self.page == P_SYSTEM {
                self.draw();
            }
        }
        if self.page == P_SPRITES {
            self.step_sprites();
        }
        if now / 1000 != self.second {
            self.second = now / 1000;
            if self.page == P_SYSTEM_PLUS {
                self.draw();
            }
        }
        100
    }

    fn on_event(&mut self, ev: &Event) {
        match ev.kind() {
            fmrb::MOUSE_DOWN => {
                if ev.button == 1 && self.page == P_INPUT && in_pad(ev.x, ev.y) {
                    self.pen = true;
                    self.add_point(ev.x, ev.y, true);
                }
            }
            fmrb::MOUSE_MOVE => {
                if self.pen {
                    self.add_point(ev.x, ev.y, false);
                }
            }
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
                if self.pen {
                    self.pen = false;
                    self.draw();
                    return;
                }
                self.set_page((self.page + 1) % N_PAGES);
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
        let (w, h) = (G.area_width(), G.area_height());
        G.fill_rect(0, 0, w, h, PAPER);
        text(
            4,
            2,
            Line::new()
                .int(self.page as i64 + 1)
                .push("/10 ")
                .push(PAGES[self.page])
                .as_str(),
            INK,
        );
        match self.page {
            P_SHAPES => draw_shapes(),
            P_TEXT => self.draw_text(),
            P_IMAGE => self.draw_image(),
            P_SPRITES => self.draw_sprites(),
            P_TILES => self.draw_tiles(),
            P_SOUND => self.draw_sound(),
            P_FILES => self.draw_files(),
            P_INPUT => self.draw_input(),
            P_SYSTEM => self.draw_system(),
            _ => draw_system_plus(),
        }
        text(4, h - 10, KEYS[self.page], INK_SUB);
        G.present();
    }

    /// Leaves the page shown, then enters p.
    fn set_page(&mut self, p: usize) {
        match self.page {
            P_SPRITES => self.show_sprites(false),
            P_SOUND => self.stop_tune(),
            P_FILES => clean_files(),
            _ => {}
        }
        self.page = p;
        fmrb::log::info(Line::from("tour: page ").push(PAGES[p]).as_str());
        match p {
            P_SPRITES => self.show_sprites(true),
            P_FILES => {
                setup_files();
                self.file_last = "-";
            }
            _ => {}
        }
        self.draw();
    }

    fn key(&mut self, ev: &Event) {
        let sc = ev.scancode;
        match sc {
            _ if ev.character == 'q' as i32 => {
                fmrb::app::stop();
                return;
            }
            0x4F => return self.set_page((self.page + 1) % N_PAGES), // right
            0x50 => return self.set_page((self.page + N_PAGES - 1) % N_PAGES), // left
            0x1E..=0x26 => return self.set_page((sc - 0x1E) as usize), // 1-9
            0x27 => return self.set_page(9),                         // 0
            _ => {}
        }
        match (self.page, sc) {
            (P_TEXT, 0x17) => self.font_mode = (self.font_mode + 1) % 3, // T
            (P_IMAGE, 0x0C) => self.img_shown = !self.img_shown,         // I
            (P_SPRITES, 0x0B) => {
                // H
                if let Some(s) = self.sprites {
                    self.hidden0 = !self.hidden0;
                    G.set_sprite_visible(s[0], !self.hidden0);
                }
            }
            (P_SPRITES, 0x13) => self.paused = !self.paused, // P
            (P_SOUND, 0x16) => {
                // S
                self.scale_i = Some(0);
                self.scale_at = fmrb::uptime_ms();
            }
            (P_SOUND, 0x05) => self.note(1, 988, 90, 14), // B
            (P_SOUND, 0x10) => self.toggle_tune(),        // M
            (P_SOUND, 0x19) => self.play_voice(),         // V
            (P_SOUND, 0x1B) => {
                // X
                self.silence();
                self.stop_tune();
            }
            (P_FILES, _) => self.file_key(sc),
            (P_INPUT, 0x2A) => {
                // backspace
                self.typed.clear();
                self.n_pts = 0;
            }
            (P_INPUT, _) => {
                if ev.character >= ' ' as i32 && ev.character < 127 {
                    if self.typed.len() == 30 {
                        // keep the last 30
                        self.typed = Text::from(&self.typed.as_str()[1..]);
                    }
                    self.typed.push_char(ev.character as u8 as char);
                }
            }
            (P_SYSTEM_PLUS, 0x06) => {
                // C
                fmrb::app::set_clipboard("copied by the tour");
            }
            _ => {}
        }
        self.draw();
    }
}

// ---- page 1: shapes

/// round to the nearest integer, halves away from zero
fn round(v: f64) -> i32 {
    if v >= 0.0 {
        (v + 0.5) as i32
    } else {
        -((-v + 0.5) as i32)
    }
}

/// sin of an angle in degrees: folded into -90..90, then the Taylor series
/// to x^13 (core has no sin without std).
fn sin_deg(deg: i32) -> f64 {
    let mut d = deg.rem_euclid(360); // 0..359
    if d > 180 {
        d -= 360; // -179..180
    }
    if d > 90 {
        d = 180 - d;
    } else if d < -90 {
        d = -180 - d;
    }
    let x = d as f64 * 3.141592653589793 / 180.0;
    let (mut term, mut sum) = (x, x);
    for n in 1..=6 {
        term *= -x * x / ((2 * n) * (2 * n + 1)) as f64;
        sum += term;
    }
    sum
}

fn cos_deg(deg: i32) -> f64 {
    sin_deg(deg + 90)
}

fn draw_shapes() {
    // left: the filled shapes, 57 x 25, 7 apart
    G.fill_rect(10, 22, 57, 25, C_BLUE);
    G.fill_round_rect(10, 54, 57, 25, 6, C_TEAL);
    G.fill_ellipse(38, 98, 28, 12, C_ORANGE);
    G.fill_triangle(10, 142, 66, 142, 38, 118, C_RED);
    // centre: concentric circles, 8 apart
    for (i, c) in [C_RED, C_ORANGE, C_TEAL, C_BLUE].into_iter().enumerate() {
        G.draw_circle(114, 82, (i as i32 + 1) * 8, c);
    }
    G.fill_circle(114, 82, 3, C_RED);
    // right: a regular hexagon around (190, 82), r 32, pointing up
    const CX: i32 = 190;
    const CY: i32 = 82;
    const R: f64 = 32.0;
    let (mut vx, mut vy) = ([0; 6], [0; 6]);
    for k in 0..6 {
        let a = -90 + 60 * k as i32;
        vx[k] = CX + round(R * cos_deg(a));
        vy[k] = CY + round(R * sin_deg(a));
    }
    for k in 0..3 {
        G.draw_line(vx[k], vy[k], vx[k + 3], vy[k + 3], C_TEAL);
    }
    G.draw_circle(CX, CY, (R * cos_deg(30)) as i32 - 1, C_ORANGE); // inside, 1 dot clear
    for k in 0..6 {
        G.draw_line(vx[k], vy[k], vx[(k + 1) % 6], vy[(k + 1) % 6], C_BLUE);
    }
    G.fill_circle(CX, CY, 3, C_RED);
}

// ---- page 2: text

impl Tour {
    fn draw_text(&self) {
        let modes = ["default font", "ja font", "mixed (ascii + ja)"];
        text(6, Y0 + 6, modes[self.font_mode], INK_SUB);
        match self.font_mode {
            0 => text(6, Y0 + 20, "ABC abc 123", C_BLUE),
            1 => {
                G.set_font(fmrb::FONT_JA, 12);
                text(6, Y0 + 20, SAMPLE_JA, C_BLUE);
                G.set_font(fmrb::FONT_DEFAULT, 0);
            }
            _ => G.draw_text_mixed(6, Y0 + 20, SAMPLE_JA, C_BLUE, PAPER),
        }
        let mut sum = 0;
        for i in 1..=10 {
            sum += i;
        }
        let rows = [
            *Line::from("language ").push(fmrb::app::language().as_str()),
            *Line::from("sum(1..10) = ").int(sum),
            *Line::from("2^16 = ").int(1 << 16),
            *Line::from("area ")
                .int(G.area_width() as i64)
                .push("x")
                .int(G.area_height() as i64),
            *Line::from("SDK ").push(fmrb::SDK_VERSION),
        ];
        for (i, r) in rows.iter().enumerate() {
            text(6, Y0 + 40 + i as i32 * 10, r.as_str(), INK);
        }
    }

    // ---- page 3: a picture

    fn draw_image(&mut self) {
        if !self.img_tried {
            self.img_tried = true;
            let dest = cached("icon.png");
            if G.sync_file(PICTURE, dest.as_str()) {
                self.img = G.create_image(dest.as_str());
            }
            if self.img.is_none() {
                fmrb::log::warn(Line::from("tour: no picture from ").push(PICTURE).as_str());
            }
        }
        text(6, Y0 + 6, PICTURE, INK_SUB);
        let Some(img) = &self.img else {
            text(6, Y0 + 20, "no picture", C_RED);
            return;
        };
        if self.img_shown {
            G.draw_image(img, 6, Y0 + 20, 2.0);
        }
        text(80, Y0 + 20, Line::from("id ").int(img.id as i64).as_str(), INK);
        text(
            80,
            Y0 + 32,
            Line::new()
                .int(img.width as i64)
                .push("x")
                .int(img.height as i64)
                .push(" px, x2")
                .as_str(),
            INK,
        );
    }

    // ---- page 4: sprites

    fn setup_sprites(&mut self) {
        self.spr_tried = true;
        let mut imgs = [SpriteImage::default(); 4];
        for (i, f) in SPRITE_FILES.iter().enumerate() {
            let src = *Line::from("/usr/share/sprites/shooter/").push(f).push(".png");
            match load_sprite(src.as_str(), Line::from(f).push(".png").as_str(), 16, 12) {
                Some(img) => imgs[i] = img,
                None => {
                    fmrb::log::warn(Line::from("tour: no sprite ").push(f).as_str());
                    return;
                }
            }
        }
        let mut sprites = [Sprite::default(); 4];
        for k in 0..4 {
            let frames = if k % 2 == 1 { &imgs[2..4] } else { &imgs[0..2] };
            self.sx[k] = 16 + 52 * k as i32;
            self.sy[k] = Y0 + 24 + 20 * k as i32;
            match G.new_sprite(frames, self.sx[k], self.sy[k], k as i32) {
                Some(s) => sprites[k] = s,
                None => {
                    fmrb::log::warn("tour: cannot place a sprite");
                    return;
                }
            }
        }
        self.sprites = Some(sprites);
    }

    fn show_sprites(&self, on: bool) {
        if let Some(s) = self.sprites {
            for (k, sp) in s.iter().enumerate() {
                G.set_sprite_visible(*sp, on && !(k == 0 && self.hidden0));
            }
        }
    }

    fn sprite_status(&self) {
        let line = *Line::from("step ")
            .int(self.step as i64)
            .push(if self.paused { "  paused" } else { "  moving" })
            .push(if self.hidden0 { "  1: hidden  " } else { "  1: shown  " });
        text(6, Y0 + 124, line.as_str(), INK);
    }

    fn draw_sprites(&mut self) {
        if !self.spr_tried {
            self.setup_sprites();
        }
        if self.sprites.is_none() {
            text(6, Y0 + 20, "no sprites", C_RED);
            return;
        }
        text(6, Y0 + 4, "4 sprites, 2 frames each", INK_SUB);
        G.draw_rect(6, Y0 + 16, 216, 104, INK_SUB);
        self.sprite_status();
    }

    fn step_sprites(&mut self) {
        let Some(sprites) = self.sprites else { return };
        if self.paused {
            return;
        }
        for (k, s) in sprites.iter().enumerate() {
            bounce(&mut self.sx[k], &mut self.dx[k], 7, 205);
            bounce(&mut self.sy[k], &mut self.dy[k], Y0 + 17, Y0 + 107);
            G.move_sprite(*s, self.sx[k], self.sy[k]);
        }
        self.step += 1;
        if self.step % 4 == 0 {
            for s in sprites {
                G.set_sprite_frame(s, self.step / 4 % 2);
            }
        }
        self.sprite_status();
        G.present();
    }

    // ---- page 5: tiles

    fn draw_tiles(&mut self) {
        if !self.sheet_tried {
            self.sheet_tried = true;
            self.sheet = load_sprite(SHEET_SRC, "tiles.png", 64, 32);
            if self.sheet.is_none() {
                fmrb::log::warn(Line::from("tour: no tiles from ").push(SHEET_SRC).as_str());
            }
        }
        let Some(sheet) = &self.sheet else {
            text(6, Y0 + 20, "no tiles", C_RED);
            return;
        };
        text(6, Y0 + 4, "draw_tile: one tile per call", INK_SUB);
        G.fill_rect(6, Y0 + 16, 72, 36, C_PANEL);
        for i in 0..8 {
            tile(sheet, i, 8 + 18 * (i % 4), Y0 + 18 + 18 * (i / 4));
        }
        text(86, Y0 + 18, "tilesheet.png", INK);
        text(86, Y0 + 30, "64x32 px, 8 tiles", INK);
        text(86, Y0 + 42, "a 12x4 map below", INK);
        G.fill_rect(18, Y0 + 58, 192, 64, C_SKY);
        for (r, line) in TILE_MAP.iter().enumerate() {
            for (c, b) in line.bytes().enumerate() {
                if b != b'.' {
                    tile(sheet, (b - b'0') as i32, 18 + 16 * c as i32, Y0 + 58 + 16 * r as i32);
                }
            }
        }
    }

    // ---- page 6: sound

    /// A note sounds until it is switched off, so its end is booked by the
    /// clock (frames stretch when drawing is slow).
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

    // the tune and the voice

    fn draw_sound(&self) {
        let rows = [
            Line::from("S: a scale on pulse 1"),
            Line::from("B: a beep on pulse 2"),
            Line::from("M: korobeiniki (FMSQ) on / off"),
            Line::from("V: a voice (WAV)"),
            Line::from("X: stop it all"),
            Line::new(),
            *Line::from("tune   ").push(self.tune),
            *Line::from("voice  ").push(self.voice),
        ];
        for (i, r) in rows.iter().enumerate() {
            text(6, Y0 + 6 + i as i32 * 12, r.as_str(), INK);
        }
        text(6, Y0 + 114, "notes end by the clock", INK_SUB);
    }

    fn stop_tune(&mut self) {
        if self.tune == "playing" {
            AUDIO.stop();
            self.tune = "stopped";
        }
    }

    fn toggle_tune(&mut self) {
        if self.tune == "playing" {
            self.stop_tune();
            return;
        }
        if !self.tune_loaded {
            let dest = cached("tune.fmsq");
            self.tune_loaded = G.sync_file(TUNE_SRC, dest.as_str()) && AUDIO.load_fmsq_file(0, dest.as_str());
            if !self.tune_loaded {
                fmrb::log::warn(Line::from("tour: cannot load ").push(TUNE_SRC).as_str());
                self.tune = "cannot load";
                return;
            }
        }
        AUDIO.play_slot(0, fmrb::AUDIO_MAIN);
        self.tune = "playing";
    }

    fn play_voice(&mut self) {
        self.voice = match AUDIO.play_wav(VOICE) {
            1 => "played",
            0 => "not on this machine",
            _ => "failed",
        };
    }

    // ---- page 7: files

    fn draw_files(&self) {
        let mut size = Line::from("-");
        if let Some(n) = fmrb::file::size(HELLO) {
            size.clear().push("hello.txt, ").int(n).push(" B");
        }
        let mut buf = [0u8; 64];
        let read = fmrb::file::read(HELLO, &mut buf)
            .map_or(Line::from("-"), |d| Line::from(core::str::from_utf8(d).unwrap_or("?")));
        let mut data = [0u8; 1024];
        let lines = fmrb::file::read(COUNT, &mut data).map_or(0, |d| d.iter().filter(|&&c| c == b'\n').count());
        let mut list = Line::new();
        if let Some(names) = fmrb::file::list::<64>(DIR) {
            for (i, n) in names.as_str().lines().enumerate() {
                if i > 0 {
                    list.push(" ");
                }
                list.push(n);
            }
        }
        let mut free = Line::from("-");
        if let Some(n) = fmrb::file::free_bytes(DIR) {
            free.clear().int(n / 1024).push(" KB");
        }
        let rows = [
            ("dir", *Line::from(DIR).push("/")),
            ("wrote", size),
            ("read", read),
            ("count", *Line::new().int(lines as i64).push(" lines")),
            ("list", list),
            ("free", free),
            ("last", Line::from(self.file_last)),
        ];
        for (i, (label, value)) in rows.iter().enumerate() {
            row(6, 58, Y0 + 6 + i as i32 * 11, label, value.as_str());
        }
        text(6, Y0 + 86, "all removed when you leave the page", INK_SUB);
    }

    fn file_key(&mut self, sc: i32) {
        match sc {
            0x1A => {
                // W
                fmrb::file::append(COUNT, b"w\n");
                self.file_last = "appended";
            }
            0x07 => {
                // D
                self.file_last = if fmrb::file::delete(COUNT) {
                    "deleted count.txt"
                } else {
                    "no count.txt"
                };
            }
            _ => {}
        }
    }

    // ---- page 8: input

    fn draw_input(&self) {
        text(6, Y0 + 4, "drag inside the box to draw", INK_SUB);
        G.draw_rect(6, Y0 + 16, 216, 84, INK_SUB);
        for i in 0..self.n_pts {
            let (x, y, start) = self.pts[i];
            if start {
                G.set_pixel(x, y, C_BLUE);
            } else {
                let (px, py, _) = self.pts[i - 1];
                G.draw_line(px, py, x, y, C_BLUE);
            }
        }
        row(6, 42, Y0 + 106, "typed", self.typed.as_str());
        row(6, 42, Y0 + 118, "last", self.input.as_str());
    }

    /// Keeps a point of the stroke (the first one starts it) and draws the
    /// line to it.
    fn add_point(&mut self, x: i32, y: i32, start: bool) {
        if self.n_pts >= MAX_POINTS {
            return;
        }
        let (x, y) = (x.clamp(7, 220), y.clamp(Y0 + 17, Y0 + 98));
        let i = self.n_pts;
        self.pts[i] = (x, y, start);
        self.n_pts += 1;
        if start {
            G.set_pixel(x, y, C_BLUE);
        } else {
            let (px, py, _) = self.pts[i - 1];
            G.draw_line(px, py, x, y, C_BLUE);
        }
        G.present();
    }

    // ---- page 9: the system side

    fn draw_system(&self) {
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
        let path = script.as_str();
        let toml_path = *Line::from(path.strip_suffix(".wasm").unwrap_or(path)).push(".toml");
        let mut toml = Line::from("-");
        if let Some(n) = fmrb::file::size(toml_path.as_str()) {
            toml.clear().int(n).push(" B");
        }
        let rows = [
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
        ];
        for (i, (label, value)) in rows.iter().enumerate() {
            row(6, 86, Y0 + 6 + i as i32 * 11, label, value.as_str());
        }
        if self.blink {
            G.fill_circle(G.area_width() - 10, Y0 + 8, 3, C_GREEN);
        }
    }
}

// ---- page 4 and 5: sprite images

/// Syncs a picture and reads it into a new sprite image.
fn load_sprite(src: &str, name: &str, w: i32, h: i32) -> Option<SpriteImage> {
    let dest = cached(name);
    if !G.sync_file(src, dest.as_str()) {
        return None;
    }
    let img = G.new_sprite_image(w, h, 0x00, true)?;
    G.load_sprite_image(&img, dest.as_str()).then_some(img)
}

/// Keeps v in lo..hi, turning d at an end.
fn bounce(v: &mut i32, d: &mut i32, lo: i32, hi: i32) {
    *v += *d;
    if *v < lo {
        *v = lo;
        *d = -*d;
    } else if *v > hi {
        *v = hi;
        *d = -*d;
    }
}

/// Tile i of the sheet (4 to a row) at (x, y).
fn tile(sheet: &SpriteImage, i: i32, x: i32, y: i32) {
    G.draw_tile(sheet, 16 * (i % 4), 16 * (i / 4), 16, 16, x, y);
}

// ---- page 7: files

fn setup_files() {
    fmrb::file::mkdir(DIR);
    fmrb::file::write(HELLO, b"hello from the tour");
}

fn clean_files() {
    fmrb::file::delete(COUNT);
    fmrb::file::delete(HELLO);
    fmrb::file::delete(DIR);
}

// ---- page 8: input

fn in_pad(x: i32, y: i32) -> bool {
    x > 6 && x < 221 && y > Y0 + 16 && y < Y0 + 99
}

// ---- page 10: the clipboard, the clock, the app's wasm numbers

fn draw_system_plus() {
    let y = |i: i32| Y0 + 6 + i * 11;
    let clip = fmrb::app::clipboard::<24>(20);
    let first = clip.as_str().lines().next().unwrap_or("");
    text(6, y(0), "clipboard", INK_SUB);
    if first.is_empty() {
        text(70, y(0), "(empty)", INK);
    } else {
        G.draw_text_mixed(70, y(0), first, INK, PAPER);
    }
    row(
        6,
        70,
        y(1),
        "changes",
        Line::new().int(fmrb::app::clipboard_gen() as i64).as_str(),
    );
    text(6, y(2), "wallclock", INK_SUB);
    if !G.draw_wallclock(70, y(2), INK, PAPER) {
        text(70, y(2), "-", INK);
    }
    let (mut mem, mut binary, mut hooks, mut last) =
        (Line::from("-"), Line::from("-"), Line::from("-"), Line::from("-"));
    if let Some(s) = fmrb::app::wasm_app_stats(fmrb::app::pid()) {
        mem.clear()
            .int(s.pages as i64)
            .push(" pages, max ")
            .int(s.max_pages as i64);
        binary.clear().int(s.binary_size as i64).push(" B");
        hooks.clear().int(s.calls as i64).push(" calls");
        last.clear()
            .int(s.hook_us as i64)
            .push(" us, max ")
            .int(s.hook_max_us as i64);
    }
    let mut apps = Line::from("-");
    if let Some(s) = fmrb::app::wasm_stats() {
        let used = s.pool_used; // packed: copied out first
        apps.clear()
            .int(s.apps as i64)
            .push(", pool ")
            .int((used / 1024) as i64)
            .push(" KB");
    }
    let mut frames = Line::from("-");
    if let Some(s) = fmrb::app::gfx_stats() {
        frames.clear().int(s.presents as i64);
    }
    let rows = [
        ("memory", mem),
        ("binary", binary),
        ("hooks", hooks),
        ("last hook", last),
        ("wasm apps", apps),
        ("frames", frames),
    ];
    for (i, (label, value)) in rows.iter().enumerate() {
        row(6, 70, y(i as i32 + 3), label, value.as_str());
    }
}

fmrb::app!(Tour);
