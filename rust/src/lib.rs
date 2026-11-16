//! The Rust SDK of Family mruby: the app's side of the boundary between a
//! wasm app and the firmware.
//!
//! An app is a type that implements [`App`] (every hook has a default that
//! does nothing) and [`Default`], named once with [`app!`]:
//!
//! ```ignore
//! #![no_std]
//! #[derive(Default)]
//! struct Hello { count: i64 }
//! impl fmrb::App for Hello {
//!     fn on_update(&mut self) -> i32 { self.count += 1; 100 }
//! }
//! fmrb::app!(Hello);
//! ```
//!
//! The firmware owns the window, its frame and the loop, and calls the
//! hooks; [`WINDOW`] draws in the area inside the frame, whose (0, 0) is its
//! top-left.
//!
//! This module is the hand-written layer: the hooks and Rust shapes for the
//! common functions, with no allocator (strings that come back are a
//! [`Text`], a fixed buffer). Under it, [`raw`] is generated from the
//! boundary (tools/gen_bindings.rb) and has every function, record and
//! choice; call it directly (in `unsafe`) for what is not wrapped here.
//!
//! Build with `cargo build --release --target wasm32-unknown-unknown` and
//! `-C link-arg=-zstack-size=16384` (rust/build.rb does it).
#![no_std]

pub mod raw;

pub use raw::SDK_VERSION;

/// Results of the boundary functions.
pub use raw::{ERR_ARG, ERR_FAILED, NONE};

#[cfg(all(feature = "panic-handler", target_arch = "wasm32"))]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo) -> ! {
    core::arch::wasm32::unreachable()
}

// ---- the app's hooks

/// One input event: FmrbApp::event (the firmware's record; it passes a
/// pointer to it). Which fields mean something depends on its type
/// ([`Event::kind`]), as in Ruby's event Hash: keys have keycode, scancode,
/// modifier and character; mouse events x and y (in the app's area), wx and
/// wy (in the window) and, pressed or released, button; the wheel also
/// delta; gamepad buttons gamepad_id and button; an axis gamepad_id, axis
/// and value; the kana mode mode. The others are 0.
pub type Event = raw::AppEvent;

impl raw::AppEvent {
    /// The event's type: one of [`KEY_DOWN`], [`MOUSE_UP`], ... (the
    /// record's field `type`).
    pub fn kind(&self) -> i32 {
        self.r#type
    }
}

/// Event types: FmrbApp::event's choices (a Symbol in Ruby).
pub const KEY_DOWN: i32 = raw::APP_EVENT_TYPE_KEY_DOWN;
pub const KEY_UP: i32 = raw::APP_EVENT_TYPE_KEY_UP;
pub const MOUSE_DOWN: i32 = raw::APP_EVENT_TYPE_MOUSE_DOWN;
pub const MOUSE_UP: i32 = raw::APP_EVENT_TYPE_MOUSE_UP;
pub const MOUSE_MOVE: i32 = raw::APP_EVENT_TYPE_MOUSE_MOVE;
pub const MOUSE_WHEEL: i32 = raw::APP_EVENT_TYPE_MOUSE_WHEEL;
pub const GAMEPAD_DOWN: i32 = raw::APP_EVENT_TYPE_GAMEPAD_DOWN;
pub const GAMEPAD_UP: i32 = raw::APP_EVENT_TYPE_GAMEPAD_UP;
pub const GAMEPAD_AXIS: i32 = raw::APP_EVENT_TYPE_GAMEPAD_AXIS;
pub const KANA_MODE: i32 = raw::APP_EVENT_TYPE_KANA_MODE;

/// The hooks the firmware calls. Implement the ones the app wants.
pub trait App {
    /// Called once as it starts.
    fn on_create(&mut self) {}
    /// Called every frame; returns the ms until the next call (negative:
    /// the firmware's default, 330 ms).
    fn on_update(&mut self) -> i32 {
        -1
    }
    /// Called on key and mouse input.
    fn on_event(&mut self, _ev: &Event) {}
    /// Called once as it ends.
    fn on_destroy(&mut self) {}
    /// Called when the screen goes to another app.
    fn on_suspend(&mut self) {}
    /// Called when the screen comes back.
    fn on_resume(&mut self) {}
    /// Called when the window is resized.
    fn on_resize(&mut self, _width: i32, _height: i32) {}
    /// Called when it is asked to close.
    fn on_quit_request(&mut self) {}
}

/// The place the firmware writes the event record into before it calls
/// on_event (raw::EVENT_BUFFER_SIZE bytes, 16-byte aligned). [`app!`]
/// exports its address as fmrb_event_buffer.
#[doc(hidden)]
#[repr(C, align(16))]
pub struct EventBuffer(pub [u8; raw::EVENT_BUFFER_SIZE]);

/// Names the app's type and exports the hooks for it, with the event
/// buffer and the SDK version (the custom section "fmrb.sdk"). The type
/// implements [`App`] and [`Default`]; its value is made before the first
/// hook runs and lives as long as the app.
#[macro_export]
macro_rules! app {
    ($t:ty) => {
        const _: () = {
            static mut APP: ::core::option::Option<$t> = ::core::option::Option::None;
            static mut EVENT_BUFFER: $crate::EventBuffer = $crate::EventBuffer([0; $crate::raw::EVENT_BUFFER_SIZE]);
            // The SDK version, in the module's custom section "fmrb.sdk"
            // (the firmware names it when it refuses an app that imports a
            // function it does not have). In the app's crate, so that it is
            // linked with or without LTO.
            #[unsafe(link_section = "fmrb.sdk")]
            #[used]
            static SDK_VERSION: [u8; $crate::raw::SDK_VERSION_SECTION.len()] = $crate::raw::SDK_VERSION_SECTION;

            fn app() -> &'static mut $t {
                // The firmware calls one hook at a time, on one thread.
                unsafe { (*&raw mut APP).get_or_insert_with(<$t as ::core::default::Default>::default) }
            }

            #[unsafe(no_mangle)]
            pub extern "C" fn on_create() {
                $crate::App::on_create(app())
            }
            #[unsafe(no_mangle)]
            pub extern "C" fn on_update() -> i32 {
                $crate::App::on_update(app())
            }
            // The record is in EVENT_BUFFER: the hook gets it by reference.
            #[unsafe(no_mangle)]
            pub extern "C" fn on_event(ev: *const $crate::Event) {
                let ev = unsafe { &*ev };
                $crate::App::on_event(app(), ev)
            }
            #[unsafe(no_mangle)]
            pub extern "C" fn on_destroy() {
                $crate::App::on_destroy(app())
            }
            #[unsafe(no_mangle)]
            pub extern "C" fn on_suspend() {
                $crate::App::on_suspend(app())
            }
            #[unsafe(no_mangle)]
            pub extern "C" fn on_resume() {
                $crate::App::on_resume(app())
            }
            #[unsafe(no_mangle)]
            pub extern "C" fn on_resize(width: i32, height: i32) {
                $crate::App::on_resize(app(), width, height)
            }
            #[unsafe(no_mangle)]
            pub extern "C" fn on_quit_request() {
                $crate::App::on_quit_request(app())
            }
            // Where the firmware writes on_event's record (asked once).
            // Without it the record would go on the app's stack, and a small
            // app whose optimiser dropped the stack pointer would be refused.
            #[unsafe(no_mangle)]
            pub extern "C" fn fmrb_event_buffer() -> *mut u8 {
                (&raw mut EVENT_BUFFER) as *mut u8
            }
        };
    };
}

// ---- strings without an allocator

/// A string in a fixed buffer of N bytes: what the functions that give a
/// String return, and a way to build a line to draw. What does not fit is
/// cut off (at a character's boundary).
#[derive(Clone, Copy)]
pub struct Text<const N: usize> {
    buf: [u8; N],
    len: usize,
}

impl<const N: usize> Default for Text<N> {
    fn default() -> Self {
        Self::new()
    }
}

impl<const N: usize> Text<N> {
    pub const fn new() -> Self {
        Text { buf: [0; N], len: 0 }
    }

    /// A Text holding s.
    pub fn from(s: &str) -> Self {
        let mut t = Self::new();
        t.push(s);
        t
    }

    pub fn as_str(&self) -> &str {
        // Only whole characters are ever put in.
        unsafe { core::str::from_utf8_unchecked(&self.buf[..self.len]) }
    }

    pub fn len(&self) -> usize {
        self.len
    }

    pub fn is_empty(&self) -> bool {
        self.len == 0
    }

    pub fn clear(&mut self) -> &mut Self {
        self.len = 0;
        self
    }

    /// Appends s (as much of it as fits).
    pub fn push(&mut self, s: &str) -> &mut Self {
        let mut n = s.len().min(N - self.len);
        while !s.is_char_boundary(n) {
            n -= 1;
        }
        self.buf[self.len..self.len + n].copy_from_slice(&s.as_bytes()[..n]);
        self.len += n;
        self
    }

    /// Appends one character.
    pub fn push_char(&mut self, c: char) -> &mut Self {
        let mut b = [0u8; 4];
        self.push(c.encode_utf8(&mut b))
    }

    /// Appends an integer in decimal.
    pub fn int(&mut self, v: i64) -> &mut Self {
        let mut d = [0u8; 20];
        let mut i = d.len();
        let mut u = v.unsigned_abs();
        loop {
            i -= 1;
            d[i] = b'0' + (u % 10) as u8;
            u /= 10;
            if u == 0 {
                break;
            }
        }
        if v < 0 {
            self.push("-");
        }
        // digits are ASCII
        self.push(unsafe { core::str::from_utf8_unchecked(&d[i..]) })
    }

    /// Appends an integer in decimal, with a 0 before it below 10.
    pub fn int2(&mut self, v: i64) -> &mut Self {
        if (0..10).contains(&v) {
            self.push("0");
        }
        self.int(v)
    }
}

impl<const N: usize> core::fmt::Write for Text<N> {
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        self.push(s);
        Ok(())
    }
}

/// Calls a boundary function that writes a String into the caller's buffer
/// and returns its full length; a longer one is cut off.
fn read_text<const N: usize>(f: impl FnOnce(*mut u8, i32) -> i32) -> Text<N> {
    let mut t = Text::<N>::new();
    let n = f(t.buf.as_mut_ptr(), N as i32);
    if n > 0 {
        let mut n = (n as usize).min(N);
        while core::str::from_utf8(&t.buf[..n]).is_err() {
            n -= 1;
        }
        t.len = n;
    }
    t
}

fn ptr(s: &str) -> (*const u8, i32) {
    (s.as_ptr(), s.len() as i32)
}

// ---- FmrbApp (the app itself; its window functions work from any hook)

/// FmrbApp: the running app and its window.
pub mod app {
    use super::{raw, read_text, Text};

    /// Platforms (FmrbApp#platform).
    pub const ESP32: i32 = raw::APP_PLATFORM_ESP32;
    pub const LINUX: i32 = raw::APP_PLATFORM_LINUX;

    pub fn name() -> Text<64> {
        read_text(|p, n| unsafe { raw::app_name(p, n) })
    }
    /// The language the app runs in (from its .app.toml).
    pub fn language() -> Text<16> {
        read_text(|p, n| unsafe { raw::app_language(p, n) })
    }
    /// The file the app was started from (its .app.wasm).
    pub fn script_path() -> Text<128> {
        read_text(|p, n| unsafe { raw::app_script_path(p, n) })
    }
    pub fn pid() -> i32 {
        unsafe { raw::app_pid() }
    }
    /// One of [`ESP32`], [`LINUX`].
    pub fn platform() -> i32 {
        unsafe { raw::app_platform() }
    }
    pub fn user_area_width() -> i32 {
        unsafe { raw::app_user_area_width() }
    }
    pub fn user_area_height() -> i32 {
        unsafe { raw::app_user_area_height() }
    }
    pub fn theme_bg() -> i32 {
        unsafe { raw::app_theme_bg() }
    }
    pub fn theme_fg() -> i32 {
        unsafe { raw::app_theme_fg() }
    }
    /// The text on the clipboard (one for every app; empty when empty), at
    /// most limit bytes (0: all of it, as much as fits) and never cut
    /// inside a character.
    pub fn clipboard<const N: usize>(limit: i32) -> Text<N> {
        read_text(|p, n| unsafe { raw::app_clipboard_raw(limit, p, n) })
    }
    /// Puts text on the clipboard (false over 64 KB).
    pub fn set_clipboard(text: &str) -> bool {
        let (p, n) = super::ptr(text);
        unsafe { raw::app_set_clipboard(p, n) == 1 }
    }
    /// Counts the clipboard's changes (to see one without reading it).
    pub fn clipboard_gen() -> i32 {
        unsafe { raw::app_clipboard_gen() }
    }
    /// How a wasm app (by pid) is doing: its memory in 64 KB pages, its
    /// .wasm's size, its hook calls and how long they took; None when pid
    /// is not a wasm app.
    pub fn wasm_app_stats(pid: i32) -> Option<raw::AppWasmAppStats> {
        let mut s = raw::AppWasmAppStats::default();
        (unsafe { raw::app_wasm_app_stats(pid, &mut s) } == 1).then_some(s)
    }
    /// The wasm runtime as a whole (apps running, its memory pool).
    pub fn wasm_stats() -> Option<raw::AppWasmStats> {
        let mut s = raw::AppWasmStats::default();
        (unsafe { raw::app_wasm_stats(&mut s) } == 1).then_some(s)
    }
    /// The tally of drawing commands and frames sent.
    pub fn gfx_stats() -> Option<raw::AppGfxStats> {
        let mut s = raw::AppGfxStats::default();
        (unsafe { raw::app_gfx_stats(&mut s) } == 1).then_some(s)
    }
    /// Ends the app after the hook it is called from returns.
    pub fn stop() {
        unsafe { raw::app_stop() };
    }
}

/// The microseconds since power-on.
pub fn uptime_us() -> i64 {
    unsafe { raw::app_uptime_us() }
}

/// The milliseconds since power-on.
pub fn uptime_ms() -> i64 {
    unsafe { raw::app_uptime_ms() }
}

/// The date and time now (FmrbApp.wallclock); None when the device does
/// not know it yet.
pub fn wallclock() -> Option<raw::AppWallclock> {
    let mut c = raw::AppWallclock::default();
    (unsafe { raw::app_wallclock(&mut c) } == 1).then_some(c)
}

/// The free bytes of the whole machine's memory pool.
pub fn memory_free() -> u32 {
    let mut r = raw::AppSysPoolInfo::default();
    if unsafe { raw::app_sys_pool_info(&mut r) } != 1 {
        return 0;
    }
    r.free
}

// ---- FmrbAudio

/// An FmrbAudio receiver: the app's sound (0 for now).
#[derive(Clone, Copy)]
pub struct Audio(pub i32);

/// The app's sound.
pub const AUDIO: Audio = Audio(0);

impl Audio {
    /// Sounds a note on a channel with Ruby's defaults (volume 10, duty 2,
    /// no sweep).
    pub fn note_on(self, channel: i32, freq: i32) {
        self.note_on_raw(channel, freq, 10, 2, 0);
    }
    /// note_on with nothing left out.
    pub fn note_on_raw(self, channel: i32, freq: i32, volume: i32, duty: i32, sweep: i32) {
        unsafe { raw::audio_note_on_raw(self.0, channel, freq, volume, duty, sweep) };
    }
    pub fn note_off(self, channel: i32) {
        unsafe { raw::audio_note_off(self.0, channel) };
    }
    /// Reads an FMSQ tune file into a slot; the path is on the graphics
    /// side (send it there with [`Gfx::sync_file`] first).
    pub fn load_fmsq_file(self, slot: i32, path: &str) -> bool {
        let (p, n) = ptr(path);
        unsafe { raw::audio_load_fmsq_file(self.0, slot, p, n) >= 0 }
    }
    /// Plays the tune in a slot on an instance ([`AUDIO_MAIN`] or
    /// [`AUDIO_SUB`]).
    pub fn play_slot(self, slot: i32, instance: i32) {
        unsafe { raw::audio_play_slot_raw(self.0, slot, instance) };
    }
    /// Stops the tune (an NSF or an FMSQ), whichever is playing.
    pub fn stop(self) {
        unsafe { raw::audio_stop(self.0) };
    }
    /// Sets the volume of the tune on MAIN only, 0-100 (%).
    pub fn set_main_volume(self, percent: i32) {
        unsafe { raw::audio_set_main_volume(self.0, percent) };
    }
    /// Plays a WAV file (mono, 16-bit PCM or IMA-ADPCM) over the APU: 1 when
    /// it plays, 0 where it cannot (Retro), below 0 on an error.
    pub fn play_wav(self, path: &str) -> i32 {
        let (p, n) = ptr(path);
        unsafe { raw::audio_play_wav(self.0, p, n) }
    }
    /// Stops the WAV that is playing.
    pub fn stop_wav(self) {
        unsafe { raw::audio_stop_wav(self.0) };
    }
}

/// The two APU instances that play a tune (play_slot's instance): a long
/// tune on MAIN and short effects on SUB, so an effect never cuts the tune.
pub const AUDIO_MAIN: i32 = 0;
pub const AUDIO_SUB: i32 = 1;

// ---- FmrbFile (by path; the places a Ruby app's File may read and write)

pub mod file {
    use super::{ptr, raw, read_text, Text};

    /// Reads a file into buf; the bytes read (at most buf.len()), None when
    /// there is no such file.
    pub fn read<'a>(path: &str, buf: &'a mut [u8]) -> Option<&'a [u8]> {
        let (p, n) = ptr(path);
        let got = unsafe { raw::file_read(p, n, buf.as_mut_ptr(), buf.len() as i32) };
        if got < 0 {
            return None;
        }
        Some(&buf[..(got as usize).min(buf.len())])
    }
    /// Writes a whole file, replacing it.
    pub fn write(path: &str, data: &[u8]) -> bool {
        let (p, n) = ptr(path);
        unsafe { raw::file_write(p, n, data.as_ptr(), data.len() as i32) == 1 }
    }
    pub fn exist(path: &str) -> bool {
        let (p, n) = ptr(path);
        unsafe { raw::file_exist(p, n) == 1 }
    }
    /// The size in bytes; None when there is no such file.
    pub fn size(path: &str) -> Option<i64> {
        let (p, n) = ptr(path);
        let s = unsafe { raw::file_size(p, n) };
        (s >= 0).then_some(s)
    }
    /// Deletes a file or an empty directory.
    pub fn delete(path: &str) -> bool {
        let (p, n) = ptr(path);
        unsafe { raw::file_delete(p, n) == 1 }
    }
    /// Adds data at the end of a file (making it when there is none).
    pub fn append(path: &str, data: &[u8]) -> bool {
        let (p, n) = ptr(path);
        unsafe { raw::file_append(p, n, data.as_ptr(), data.len() as i32) == 1 }
    }
    /// Makes a directory.
    pub fn mkdir(path: &str) -> bool {
        let (p, n) = ptr(path);
        unsafe { raw::file_mkdir(p, n) == 1 }
    }
    /// The free space of the file system path is on; None when it cannot
    /// be told.
    pub fn free_bytes(path: &str) -> Option<i64> {
        let (p, n) = ptr(path);
        let s = unsafe { raw::file_free_bytes(p, n) };
        (s >= 0).then_some(s)
    }
    /// The names in a directory, one per line (a directory's with a "/"
    /// after it), into a Text; None when it cannot be read.
    /// `as_str().lines()` takes them apart.
    pub fn list<const N: usize>(dir: &str) -> Option<Text<N>> {
        let (p, n) = ptr(dir);
        if unsafe { raw::file_list_raw(p, n, core::ptr::null_mut(), 0) } < 0 {
            return None;
        }
        Some(read_text(|o, on| unsafe { raw::file_list_raw(p, n, o, on) }))
    }
}

// ---- FmrbGfx

/// A drawer: a canvas, a drawing origin and an area.
#[derive(Clone, Copy)]
pub struct Gfx(pub i32);

/// The app window's drawer, opened by the firmware before on_create.
pub const WINDOW: Gfx = Gfx(0);

/// As a text background: leaves what is under the text.
pub const TRANSPARENT: i32 = -1;

/// Fonts (FmrbGfx#set_font's family).
pub const FONT_DEFAULT: i32 = raw::GFX_SET_FONT_RAW_FAMILY_DEFAULT;
pub const FONT_JA: i32 = raw::GFX_SET_FONT_RAW_FAMILY_JA;
pub const FONT_JA_BOLD: i32 = raw::GFX_SET_FONT_RAW_FAMILY_JA_BOLD;

/// Turns 0-255 components into the firmware's 8-bit color (RGB332).
pub fn rgb(r: i32, g: i32, b: i32) -> i32 {
    unsafe { raw::gfx_rgb_to_332(r, g, b) }
}

/// A picture the graphics side decoded (FmrbGfx#create_image).
#[derive(Clone, Copy, Default)]
pub struct Image {
    pub id: i32,
    pub width: i32,
    pub height: i32,
}

/// A picture on the graphics side that sprites show and tiles are cut from
/// (SpriteImage in Ruby).
#[derive(Clone, Copy, Default)]
pub struct SpriteImage {
    pub id: i32,
    pub width: i32,
    pub height: i32,
}

/// A placed sprite (SpriteInstance in Ruby): one or more sprite images (the
/// frames of a flip book) at a position, drawn over the canvas at each
/// present.
#[derive(Clone, Copy, Default)]
pub struct Sprite(pub i32);

impl Gfx {
    pub fn area_width(self) -> i32 {
        unsafe { raw::gfx_area_width(self.0) }
    }
    pub fn area_height(self) -> i32 {
        unsafe { raw::gfx_area_height(self.0) }
    }
    pub fn clear(self, color: i32) {
        unsafe { raw::gfx_clear(self.0, color) };
    }
    pub fn set_pixel(self, x: i32, y: i32, color: i32) {
        unsafe { raw::gfx_set_pixel(self.0, x, y, color) };
    }
    pub fn draw_line(self, x0: i32, y0: i32, x1: i32, y1: i32, color: i32) {
        unsafe { raw::gfx_draw_line(self.0, x0, y0, x1, y1, color) };
    }
    pub fn draw_rect(self, x: i32, y: i32, w: i32, h: i32, color: i32) {
        unsafe { raw::gfx_draw_rect(self.0, x, y, w, h, color) };
    }
    pub fn fill_rect(self, x: i32, y: i32, w: i32, h: i32, color: i32) {
        unsafe { raw::gfx_fill_rect(self.0, x, y, w, h, color) };
    }
    pub fn draw_round_rect(self, x: i32, y: i32, w: i32, h: i32, r: i32, color: i32) {
        unsafe { raw::gfx_draw_round_rect(self.0, x, y, w, h, r, color) };
    }
    pub fn fill_round_rect(self, x: i32, y: i32, w: i32, h: i32, r: i32, color: i32) {
        unsafe { raw::gfx_fill_round_rect(self.0, x, y, w, h, r, color) };
    }
    pub fn draw_circle(self, x: i32, y: i32, r: i32, color: i32) {
        unsafe { raw::gfx_draw_circle(self.0, x, y, r, color) };
    }
    pub fn fill_circle(self, x: i32, y: i32, r: i32, color: i32) {
        unsafe { raw::gfx_fill_circle(self.0, x, y, r, color) };
    }
    pub fn draw_ellipse(self, x: i32, y: i32, rx: i32, ry: i32, color: i32) {
        unsafe { raw::gfx_draw_ellipse(self.0, x, y, rx, ry, color) };
    }
    pub fn fill_ellipse(self, x: i32, y: i32, rx: i32, ry: i32, color: i32) {
        unsafe { raw::gfx_fill_ellipse(self.0, x, y, rx, ry, color) };
    }
    #[allow(clippy::too_many_arguments)]
    pub fn draw_triangle(self, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: i32) {
        unsafe { raw::gfx_draw_triangle(self.0, x0, y0, x1, y1, x2, y2, color) };
    }
    #[allow(clippy::too_many_arguments)]
    pub fn fill_triangle(self, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: i32) {
        unsafe { raw::gfx_fill_triangle(self.0, x0, y0, x1, y1, x2, y2, color) };
    }

    /// Draws text with a transparent background.
    pub fn draw_text(self, x: i32, y: i32, text: &str, color: i32) {
        self.draw_text_bg(x, y, text, color, TRANSPARENT);
    }
    /// Draws text on a background color ([`TRANSPARENT`] for none).
    pub fn draw_text_bg(self, x: i32, y: i32, text: &str, color: i32, bg: i32) {
        let (p, n) = ptr(text);
        unsafe { raw::gfx_draw_text_raw(self.0, x, y, p, n, color, bg, 0) };
    }
    /// Draws text that mixes ASCII (the default font) and Japanese (the ja
    /// font) on one line.
    pub fn draw_text_mixed(self, x: i32, y: i32, text: &str, color: i32, bg: i32) {
        let (p, n) = ptr(text);
        unsafe { raw::gfx_draw_text_raw(self.0, x, y, p, n, color, bg, 1) };
    }
    pub fn set_text_size(self, size: i32) {
        unsafe { raw::gfx_set_text_size_raw(self.0, size) };
    }
    /// Picks the font; size is the ja font's height (12 or 16; 0: its
    /// default).
    pub fn set_font(self, family: i32, size: i32) {
        unsafe { raw::gfx_set_font_raw(self.0, family, size) };
    }

    /// Copies a file to where the graphics side reads it (dest, under
    /// /cache); create_image and the like read from there.
    pub fn sync_file(self, path: &str, dest: &str) -> bool {
        let (p, n) = ptr(path);
        let (d, dn) = ptr(dest);
        unsafe { raw::gfx_sync_file_raw(self.0, p, n, d, dn) == 1 }
    }
    /// Decodes a picture file (PNG); None when it cannot.
    pub fn create_image(self, path: &str) -> Option<Image> {
        let (p, n) = ptr(path);
        let mut r = raw::GfxImageInfo::default();
        if unsafe { raw::gfx_create_image(self.0, p, n, &mut r) } != 1 {
            return None;
        }
        Some(Image {
            id: r.id as i32,
            width: r.width as i32,
            height: r.height as i32,
        })
    }
    /// Draws an image at a scale (1.0: its own size).
    pub fn draw_image(self, img: &Image, x: i32, y: i32, scale: f64) {
        unsafe { raw::gfx_draw_image_raw(self.0, img.id, x, y, scale, 0.0) };
    }
    pub fn delete_image(self, img: &Image) {
        unsafe { raw::gfx_delete_image(self.0, img.id) };
    }
    /// Draws the time now at (x, y), formatted by the firmware; false when
    /// the device does not know it.
    pub fn draw_wallclock(self, x: i32, y: i32, color: i32, bg: i32) -> bool {
        unsafe { raw::gfx_draw_wallclock(self.0, x, y, color, bg) == 1 }
    }

    // ---- sprites and tiles

    /// Makes a width x height sprite image; with use_key the pixels of key
    /// are see-through. None when it cannot be made.
    pub fn new_sprite_image(self, width: i32, height: i32, key: i32, use_key: bool) -> Option<SpriteImage> {
        let id = unsafe { raw::gfx_create_sprite_image(self.0, width, height, key, use_key as i32) };
        (id > 0).then_some(SpriteImage { id, width, height })
    }
    /// Reads a PNG (or an RGB332 BMP) into a sprite image; the path is on
    /// the graphics side (send it there with [`Gfx::sync_file`] first).
    pub fn load_sprite_image(self, img: &SpriteImage, path: &str) -> bool {
        let (p, n) = ptr(path);
        unsafe { raw::gfx_load_sprite_image(self.0, img.id, p, n) >= 0 }
    }
    /// What is drawn next goes into img, in its own coordinates; None goes
    /// back to the canvas.
    pub fn draw_into(self, img: Option<&SpriteImage>) {
        unsafe { raw::gfx_set_sprite_image_target(self.0, img.map_or(0, |i| i.id)) };
    }
    pub fn delete_sprite_image(self, img: &SpriteImage) {
        unsafe { raw::gfx_delete_sprite_image(self.0, img.id) };
    }
    /// Places sprite images (1 to 8 frames) at (x, y) of the area; a larger
    /// z is nearer. None when it cannot be placed.
    pub fn new_sprite(self, frames: &[SpriteImage], x: i32, y: i32, z: i32) -> Option<Sprite> {
        if frames.is_empty() || frames.len() > 8 {
            return None;
        }
        let mut ids = [0u16; 8];
        for (i, f) in frames.iter().enumerate() {
            ids[i] = f.id as u16;
        }
        let id = unsafe { raw::gfx_create_sprite_instance(self.0, ids.as_ptr(), frames.len() as i32, x, y, z) };
        (id > 0).then_some(Sprite(id))
    }
    /// Moves a placed sprite (shown at the next present).
    pub fn move_sprite(self, s: Sprite, x: i32, y: i32) {
        unsafe { raw::gfx_move_sprite(self.0, s.0, x, y) };
    }
    pub fn set_sprite_visible(self, s: Sprite, visible: bool) {
        unsafe { raw::gfx_set_sprite_visible(self.0, s.0, visible as i32) };
    }
    /// Which frame a placed sprite shows (0: the first).
    pub fn set_sprite_frame(self, s: Sprite, frame: i32) {
        unsafe { raw::gfx_set_sprite_frame(self.0, s.0, frame) };
    }
    pub fn delete_sprite(self, s: Sprite) {
        unsafe { raw::gfx_delete_sprite_instance(self.0, s.0) };
    }
    /// Lets go of every placed sprite and sprite image of the drawer's
    /// canvas.
    pub fn delete_all_sprites(self) {
        unsafe { raw::gfx_delete_all_sprites(self.0) };
    }
    /// Keeps sprites inside a rectangle of the area (a window's sprites
    /// start clipped to its area).
    pub fn set_sprite_clip(self, x: i32, y: i32, w: i32, h: i32) {
        unsafe { raw::gfx_set_sprite_clip(self.0, x, y, w, h) };
    }
    pub fn clear_sprite_clip(self) {
        unsafe { raw::gfx_clear_sprite_clip(self.0) };
    }
    /// Draws the w x h piece of sheet at (sx, sy) to (x, y), into the
    /// canvas (its see-through pixels leave what is there).
    #[allow(clippy::too_many_arguments)]
    pub fn draw_tile(self, sheet: &SpriteImage, sx: i32, sy: i32, w: i32, h: i32, x: i32, y: i32) {
        unsafe { raw::gfx_draw_tile_raw(self.0, sheet.id, sx, sy, w, h, x, y) };
    }

    /// Shows what was drawn, at the window's place.
    pub fn present(self) {
        unsafe { raw::gfx_present_raw(self.0, 0, 0, 0) };
    }
}

// ---- the log (the same log as a Ruby app's)

pub mod log {
    use super::{ptr, raw};

    pub fn debug(msg: &str) {
        let (p, n) = ptr(msg);
        unsafe { raw::log_debug_raw(p, n) };
    }
    pub fn info(msg: &str) {
        let (p, n) = ptr(msg);
        unsafe { raw::log_info_raw(p, n) };
    }
    pub fn warn(msg: &str) {
        let (p, n) = ptr(msg);
        unsafe { raw::log_warn_raw(p, n) };
    }
    pub fn error(msg: &str) {
        let (p, n) = ptr(msg);
        unsafe { raw::log_error_raw(p, n) };
    }
}
