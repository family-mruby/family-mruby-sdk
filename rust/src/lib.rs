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
/// buffer. The type implements [`App`] and [`Default`]; its value is made
/// before the first hook runs and lives as long as the app.
#[macro_export]
macro_rules! app {
    ($t:ty) => {
        const _: () = {
            static mut APP: ::core::option::Option<$t> = ::core::option::Option::None;
            static mut EVENT_BUFFER: $crate::EventBuffer = $crate::EventBuffer([0; $crate::raw::EVENT_BUFFER_SIZE]);

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
}

// ---- FmrbFile (by path; the places a Ruby app's File may read and write)

pub mod file {
    use super::{ptr, raw};

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
