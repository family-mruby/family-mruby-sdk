//! The Zig SDK of Family mruby: the app's side of the boundary between a
//! wasm app and the firmware.
//!
//! An app is a struct whose fields all have defaults, with the hooks it
//! wants as methods (onCreate, onUpdate, onEvent, onDestroy, onSuspend,
//! onResume, onResize, onQuitRequest), exported once from the root file:
//!
//!     const fmrb = @import("fmrb");
//!     pub const panic = fmrb.panic;
//!     const Hello = struct {
//!         count: i64 = 0,
//!         pub fn onUpdate(self: *Hello) i32 { self.count += 1; return 100; }
//!     };
//!     comptime { fmrb.exportApp(Hello); }
//!
//! The firmware owns the window, its frame and the loop, and calls the
//! hooks; `window` draws in the area inside the frame, whose (0, 0) is its
//! top-left.
//!
//! This file is the hand-written layer: the hooks and Zig shapes for the
//! common functions, with no allocator (functions that give a String write
//! it into the caller's buffer and return the slice). Under it, `raw`
//! (raw.zig) is generated from the boundary (tools/gen_bindings.rb) and has
//! every function, record and choice; call it directly for the rest.
//!
//! Build: wasm32-freestanding, no entry point, exported symbols kept
//! (rdynamic), a 16 KB stack (addApp in the build.zig at the repository root).
const std = @import("std");

pub const raw = @import("raw.zig");

pub const sdk_version = raw.sdk_version;

// The SDK version, in the module's custom section "fmrb.sdk" (the firmware
// names it when it refuses an app that imports a function it does not
// have). Zig has no way to make a custom section; the assembler has.
comptime {
    asm (".section .custom_section." ++ raw.sdk_section ++ ",\"\",@\n.ascii \"" ++ raw.sdk_version ++ "\"\n");
}

/// Results of the boundary functions.
pub const err_failed = raw.err_failed;
pub const err_arg = raw.err_arg;
pub const none = raw.none; // nil in Ruby

/// A panic traps: put `pub const panic = fmrb.panic;` in the app's root
/// file (it keeps the app small; a trap ends the app with an error).
pub const panic = std.debug.no_panic;

// ---- the app's hooks

/// One input event: FmrbApp::event (the firmware's record; it passes a
/// pointer to it). Which fields mean something depends on its type
/// (`ev.type`), as in Ruby's event Hash: keys have keycode, scancode,
/// modifier and character; mouse events x and y (in the app's area), wx and
/// wy (in the window) and, pressed or released, button; the wheel also
/// delta; gamepad buttons gamepad_id and button; an axis gamepad_id, axis
/// and value; the kana mode mode. The others are 0.
pub const Event = raw.AppEvent;

/// Event types: FmrbApp::event's choices (a Symbol in Ruby).
pub const key_down = raw.app_event_type_key_down;
pub const key_up = raw.app_event_type_key_up;
pub const mouse_down = raw.app_event_type_mouse_down;
pub const mouse_up = raw.app_event_type_mouse_up;
pub const mouse_move = raw.app_event_type_mouse_move;
pub const mouse_wheel = raw.app_event_type_mouse_wheel;
pub const gamepad_down = raw.app_event_type_gamepad_down;
pub const gamepad_up = raw.app_event_type_gamepad_up;
pub const gamepad_axis = raw.app_event_type_gamepad_axis;
pub const kana_mode = raw.app_event_type_kana_mode;

/// Exports the hooks for the app's type T, with the event buffer. Call it
/// from a comptime block of the root file. T's value is made with its
/// fields' defaults and lives as long as the app; a hook T does not have
/// does nothing (onUpdate: the firmware's default interval).
pub fn exportApp(comptime T: type) void {
    const H = struct {
        var the_app: T = .{};
        // Where the firmware writes on_event's record (asked once). Without
        // it the record would go on the app's stack, and a small app whose
        // optimiser dropped the stack pointer would be refused.
        var event_buffer: [raw.event_buffer_size]u8 align(16) = undefined;

        fn onCreate() callconv(.c) void {
            if (@hasDecl(T, "onCreate")) the_app.onCreate();
        }
        /// The ms until the next call (negative: the firmware's default, 330 ms).
        fn onUpdate() callconv(.c) i32 {
            return if (@hasDecl(T, "onUpdate")) the_app.onUpdate() else -1;
        }
        // The record is in event_buffer: the hook gets a pointer to it.
        fn onEvent(ev: *const Event) callconv(.c) void {
            if (@hasDecl(T, "onEvent")) the_app.onEvent(ev);
        }
        fn onDestroy() callconv(.c) void {
            if (@hasDecl(T, "onDestroy")) the_app.onDestroy();
        }
        fn onSuspend() callconv(.c) void {
            if (@hasDecl(T, "onSuspend")) the_app.onSuspend();
        }
        fn onResume() callconv(.c) void {
            if (@hasDecl(T, "onResume")) the_app.onResume();
        }
        fn onResize(w: i32, h: i32) callconv(.c) void {
            if (@hasDecl(T, "onResize")) the_app.onResize(w, h);
        }
        fn onQuitRequest() callconv(.c) void {
            if (@hasDecl(T, "onQuitRequest")) the_app.onQuitRequest();
        }
        fn eventBuffer() callconv(.c) [*]u8 {
            return &event_buffer;
        }
    };
    @export(&H.onCreate, .{ .name = "on_create" });
    @export(&H.onUpdate, .{ .name = "on_update" });
    @export(&H.onEvent, .{ .name = "on_event" });
    @export(&H.onDestroy, .{ .name = "on_destroy" });
    @export(&H.onSuspend, .{ .name = "on_suspend" });
    @export(&H.onResume, .{ .name = "on_resume" });
    @export(&H.onResize, .{ .name = "on_resize" });
    @export(&H.onQuitRequest, .{ .name = "on_quit_request" });
    @export(&H.eventBuffer, .{ .name = raw.event_buffer_export });
}

/// Calls a boundary function that writes a String into the caller's
/// buffer and returns its full length; a longer one is cut off.
fn readString(buf: []u8, n: i32) []const u8 {
    if (n <= 0) return buf[0..0];
    return buf[0..@min(@as(usize, @intCast(n)), buf.len)];
}

fn len(s: []const u8) i32 {
    return @intCast(s.len);
}

// ---- FmrbApp (the app itself; its window functions work from any hook)

/// FmrbApp: the running app and its window.
pub const app = struct {
    /// Platforms (FmrbApp#platform).
    pub const esp32 = raw.app_platform_esp32;
    pub const linux = raw.app_platform_linux;

    pub fn name(buf: []u8) []const u8 {
        return readString(buf, raw.app_name(buf.ptr, len(buf)));
    }
    /// The language the app runs in (from its .app.toml).
    pub fn language(buf: []u8) []const u8 {
        return readString(buf, raw.app_language(buf.ptr, len(buf)));
    }
    /// The file the app was started from (its .app.wasm).
    pub fn scriptPath(buf: []u8) []const u8 {
        return readString(buf, raw.app_script_path(buf.ptr, len(buf)));
    }
    pub fn pid() i32 {
        return raw.app_pid();
    }
    /// One of esp32, linux.
    pub fn platform() i32 {
        return raw.app_platform();
    }
    pub fn userAreaWidth() i32 {
        return raw.app_user_area_width();
    }
    pub fn userAreaHeight() i32 {
        return raw.app_user_area_height();
    }
    pub fn themeBg() i32 {
        return raw.app_theme_bg();
    }
    pub fn themeFg() i32 {
        return raw.app_theme_fg();
    }
    /// The text on the clipboard (one for every app; empty when empty),
    /// written into buf: at most limit bytes (0: all of it, as much as
    /// fits), never cut inside a character.
    pub fn clipboard(buf: []u8, limit: i32) []const u8 {
        return readString(buf, raw.app_clipboard_raw(limit, buf.ptr, len(buf)));
    }
    /// Puts text on the clipboard (false over 64 KB).
    pub fn setClipboard(text: []const u8) bool {
        return raw.app_set_clipboard(text.ptr, len(text)) == 1;
    }
    /// Counts the clipboard's changes (to see one without reading it).
    pub fn clipboardGen() i32 {
        return raw.app_clipboard_gen();
    }
    /// How a wasm app (by pid) is doing: its memory in 64 KB pages, its
    /// .wasm's size, its hook calls and how long they took; null when pid
    /// is not a wasm app.
    pub fn wasmAppStats(app_pid: i32) ?raw.AppWasmAppStats {
        var s: raw.AppWasmAppStats = .{};
        return if (raw.app_wasm_app_stats(app_pid, &s) == 1) s else null;
    }
    /// The wasm runtime as a whole (apps running, its memory pool).
    pub fn wasmStats() ?raw.AppWasmStats {
        var s: raw.AppWasmStats = .{};
        return if (raw.app_wasm_stats(&s) == 1) s else null;
    }
    /// The tally of drawing commands and frames sent.
    pub fn gfxStats() ?raw.AppGfxStats {
        var s: raw.AppGfxStats = .{};
        return if (raw.app_gfx_stats(&s) == 1) s else null;
    }
    /// Ends the app after the hook it is called from returns.
    pub fn stop() void {
        _ = raw.app_stop();
    }
};

/// The microseconds since power-on.
pub fn uptimeUs() i64 {
    return raw.app_uptime_us();
}

/// The milliseconds since power-on.
pub fn uptimeMs() i64 {
    return raw.app_uptime_ms();
}

/// The date and time now (FmrbApp.wallclock); null when the device does
/// not know it yet.
pub fn wallclock() ?raw.AppWallclock {
    var c: raw.AppWallclock = .{};
    return if (raw.app_wallclock(&c) == 1) c else null;
}

/// The free bytes of the whole machine's memory pool.
pub fn memoryFree() u32 {
    var r: raw.AppSysPoolInfo = .{};
    return if (raw.app_sys_pool_info(&r) == 1) r.free else 0;
}

// ---- FmrbAudio

/// An FmrbAudio receiver: the app's sound (0 for now).
pub const Audio = struct {
    id: i32,

    /// Sounds a note on a channel with Ruby's defaults (volume 10, duty 2,
    /// no sweep).
    pub fn noteOn(self: Audio, channel: i32, freq: i32) void {
        self.noteOnRaw(channel, freq, 10, 2, 0);
    }
    /// note_on with nothing left out.
    pub fn noteOnRaw(self: Audio, channel: i32, freq: i32, volume: i32, duty: i32, sweep: i32) void {
        _ = raw.audio_note_on_raw(self.id, channel, freq, volume, duty, sweep);
    }
    pub fn noteOff(self: Audio, channel: i32) void {
        _ = raw.audio_note_off(self.id, channel);
    }
    /// Reads an FMSQ tune file into a slot; the path is on the graphics
    /// side (send it there with Gfx.syncFile first).
    pub fn loadFmsqFile(self: Audio, slot: i32, path: []const u8) bool {
        return raw.audio_load_fmsq_file(self.id, slot, path.ptr, len(path)) >= 0;
    }
    /// Plays the tune in a slot on an instance (Audio.main or Audio.sub).
    pub fn playSlot(self: Audio, slot: i32, instance: i32) void {
        _ = raw.audio_play_slot_raw(self.id, slot, instance);
    }
    /// Stops the tune (an NSF or an FMSQ), whichever is playing.
    pub fn stop(self: Audio) void {
        _ = raw.audio_stop(self.id);
    }
    /// Sets the volume of the tune on MAIN only, 0-100 (%).
    pub fn setMainVolume(self: Audio, percent: i32) void {
        _ = raw.audio_set_main_volume(self.id, percent);
    }
    /// Plays a WAV file (mono, 16-bit PCM or IMA-ADPCM) over the APU: 1 when
    /// it plays, 0 where it cannot (Retro), below 0 on an error.
    pub fn playWav(self: Audio, path: []const u8) i32 {
        return raw.audio_play_wav(self.id, path.ptr, len(path));
    }
    /// Stops the WAV that is playing.
    pub fn stopWav(self: Audio) void {
        _ = raw.audio_stop_wav(self.id);
    }

    /// The two APU instances that play a tune (playSlot's instance): a long
    /// tune on main and short effects on sub, so an effect never cuts the
    /// tune.
    pub const main: i32 = 0;
    pub const sub: i32 = 1;
};

/// The app's sound.
pub const audio = Audio{ .id = 0 };

// ---- FmrbFile (by path; the places a Ruby app's File may read and write)

pub const file = struct {
    /// Reads a file into buf; the bytes read (at most buf.len), null when
    /// there is no such file.
    pub fn read(path: []const u8, buf: []u8) ?[]u8 {
        const got = raw.file_read(path.ptr, len(path), buf.ptr, len(buf));
        if (got < 0) return null;
        return buf[0..@min(@as(usize, @intCast(got)), buf.len)];
    }
    /// Writes a whole file, replacing it.
    pub fn write(path: []const u8, data: []const u8) bool {
        return raw.file_write(path.ptr, len(path), data.ptr, len(data)) == 1;
    }
    pub fn exist(path: []const u8) bool {
        return raw.file_exist(path.ptr, len(path)) == 1;
    }
    /// The size in bytes; null when there is no such file.
    pub fn size(path: []const u8) ?i64 {
        const s = raw.file_size(path.ptr, len(path));
        return if (s >= 0) s else null;
    }
    /// Deletes a file or an empty directory.
    pub fn delete(path: []const u8) bool {
        return raw.file_delete(path.ptr, len(path)) == 1;
    }
    /// Adds data at the end of a file (making it when there is none).
    pub fn append(path: []const u8, data: []const u8) bool {
        return raw.file_append(path.ptr, len(path), data.ptr, len(data)) == 1;
    }
    /// Makes a directory.
    pub fn mkdir(path: []const u8) bool {
        return raw.file_mkdir(path.ptr, len(path)) == 1;
    }
    /// The free space of the file system path is on; null when it cannot
    /// be told.
    pub fn freeBytes(path: []const u8) ?i64 {
        const n = raw.file_free_bytes(path.ptr, len(path));
        return if (n >= 0) n else null;
    }
    /// The names in a directory, one per line (a directory's with a "/"
    /// after it), written into buf; null when it cannot be read.
    /// std.mem.tokenizeScalar(u8, names, '\n') takes them apart.
    pub fn list(dir: []const u8, buf: []u8) ?[]const u8 {
        const n = raw.file_list_raw(dir.ptr, len(dir), buf.ptr, len(buf));
        if (n < 0) return null;
        return readString(buf, n);
    }
};

// ---- FmrbGfx

/// As a text background: leaves what is under the text.
pub const transparent: i32 = -1;

/// Fonts (FmrbGfx#set_font's family).
pub const font_default = raw.gfx_set_font_raw_family_default;
pub const font_ja = raw.gfx_set_font_raw_family_ja;
pub const font_ja_bold = raw.gfx_set_font_raw_family_ja_bold;

/// Turns 0-255 components into the firmware's 8-bit color (RGB332).
pub fn rgb(r: i32, g: i32, b: i32) i32 {
    return raw.gfx_rgb_to_332(r, g, b);
}

/// A picture the graphics side decoded (FmrbGfx#create_image).
pub const Image = struct { id: i32, width: i32, height: i32 };

/// A picture on the graphics side that sprites show and tiles are cut from
/// (SpriteImage in Ruby).
pub const SpriteImage = struct { id: i32, width: i32, height: i32 };

/// A placed sprite (SpriteInstance in Ruby): one or more sprite images (the
/// frames of a flip book) at a position, drawn over the canvas at each
/// present.
pub const Sprite = struct { id: i32 };

/// A drawer: a canvas, a drawing origin and an area.
pub const Gfx = struct {
    id: i32,

    pub fn areaWidth(g: Gfx) i32 {
        return raw.gfx_area_width(g.id);
    }
    pub fn areaHeight(g: Gfx) i32 {
        return raw.gfx_area_height(g.id);
    }
    pub fn clear(g: Gfx, color: i32) void {
        _ = raw.gfx_clear(g.id, color);
    }
    pub fn setPixel(g: Gfx, x: i32, y: i32, color: i32) void {
        _ = raw.gfx_set_pixel(g.id, x, y, color);
    }
    pub fn drawLine(g: Gfx, x0: i32, y0: i32, x1: i32, y1: i32, color: i32) void {
        _ = raw.gfx_draw_line(g.id, x0, y0, x1, y1, color);
    }
    pub fn drawRect(g: Gfx, x: i32, y: i32, w: i32, h: i32, color: i32) void {
        _ = raw.gfx_draw_rect(g.id, x, y, w, h, color);
    }
    pub fn fillRect(g: Gfx, x: i32, y: i32, w: i32, h: i32, color: i32) void {
        _ = raw.gfx_fill_rect(g.id, x, y, w, h, color);
    }
    pub fn drawRoundRect(g: Gfx, x: i32, y: i32, w: i32, h: i32, r: i32, color: i32) void {
        _ = raw.gfx_draw_round_rect(g.id, x, y, w, h, r, color);
    }
    pub fn fillRoundRect(g: Gfx, x: i32, y: i32, w: i32, h: i32, r: i32, color: i32) void {
        _ = raw.gfx_fill_round_rect(g.id, x, y, w, h, r, color);
    }
    pub fn drawCircle(g: Gfx, x: i32, y: i32, r: i32, color: i32) void {
        _ = raw.gfx_draw_circle(g.id, x, y, r, color);
    }
    pub fn fillCircle(g: Gfx, x: i32, y: i32, r: i32, color: i32) void {
        _ = raw.gfx_fill_circle(g.id, x, y, r, color);
    }
    pub fn drawEllipse(g: Gfx, x: i32, y: i32, rx: i32, ry: i32, color: i32) void {
        _ = raw.gfx_draw_ellipse(g.id, x, y, rx, ry, color);
    }
    pub fn fillEllipse(g: Gfx, x: i32, y: i32, rx: i32, ry: i32, color: i32) void {
        _ = raw.gfx_fill_ellipse(g.id, x, y, rx, ry, color);
    }
    pub fn drawTriangle(g: Gfx, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: i32) void {
        _ = raw.gfx_draw_triangle(g.id, x0, y0, x1, y1, x2, y2, color);
    }
    pub fn fillTriangle(g: Gfx, x0: i32, y0: i32, x1: i32, y1: i32, x2: i32, y2: i32, color: i32) void {
        _ = raw.gfx_fill_triangle(g.id, x0, y0, x1, y1, x2, y2, color);
    }

    /// Draws text with a transparent background.
    pub fn drawText(g: Gfx, x: i32, y: i32, text: []const u8, color: i32) void {
        g.drawTextBg(x, y, text, color, transparent);
    }
    /// Draws text on a background color (transparent for none).
    pub fn drawTextBg(g: Gfx, x: i32, y: i32, text: []const u8, color: i32, bg: i32) void {
        _ = raw.gfx_draw_text_raw(g.id, x, y, text.ptr, len(text), color, bg, 0);
    }
    /// Draws text that mixes ASCII (the default font) and Japanese (the ja
    /// font) on one line.
    pub fn drawTextMixed(g: Gfx, x: i32, y: i32, text: []const u8, color: i32, bg: i32) void {
        _ = raw.gfx_draw_text_raw(g.id, x, y, text.ptr, len(text), color, bg, 1);
    }
    pub fn setTextSize(g: Gfx, size: i32) void {
        _ = raw.gfx_set_text_size_raw(g.id, size);
    }
    /// Picks the font; size is the ja font's height (12 or 16; 0: its
    /// default).
    pub fn setFont(g: Gfx, family: i32, size: i32) void {
        _ = raw.gfx_set_font_raw(g.id, family, size);
    }

    /// Copies a file to where the graphics side reads it (dest, under
    /// /cache); createImage and the like read from there.
    pub fn syncFile(g: Gfx, path: []const u8, dest: []const u8) bool {
        return raw.gfx_sync_file_raw(g.id, path.ptr, len(path), dest.ptr, len(dest)) == 1;
    }
    /// Decodes a picture file (PNG); null when it cannot.
    pub fn createImage(g: Gfx, path: []const u8) ?Image {
        var r: raw.GfxImageInfo = .{};
        if (raw.gfx_create_image(g.id, path.ptr, len(path), &r) != 1) return null;
        return .{ .id = r.id, .width = r.width, .height = r.height };
    }
    /// Draws an image at a scale (1.0: its own size).
    pub fn drawImage(g: Gfx, img: Image, x: i32, y: i32, scale: f64) void {
        _ = raw.gfx_draw_image_raw(g.id, img.id, x, y, scale, 0);
    }
    pub fn deleteImage(g: Gfx, img: Image) void {
        _ = raw.gfx_delete_image(g.id, img.id);
    }
    /// Draws the time now at (x, y), formatted by the firmware; false when
    /// the device does not know it.
    pub fn drawWallclock(g: Gfx, x: i32, y: i32, color: i32, bg: i32) bool {
        return raw.gfx_draw_wallclock(g.id, x, y, color, bg) == 1;
    }

    // ---- sprites and tiles

    /// Makes a width x height sprite image; with use_key the pixels of key
    /// are see-through. null when it cannot be made.
    pub fn newSpriteImage(g: Gfx, width: i32, height: i32, key: i32, use_key: bool) ?SpriteImage {
        const id = raw.gfx_create_sprite_image(g.id, width, height, key, @intFromBool(use_key));
        return if (id > 0) .{ .id = id, .width = width, .height = height } else null;
    }
    /// Reads a PNG (or an RGB332 BMP) into a sprite image; the path is on
    /// the graphics side (send it there with syncFile first).
    pub fn loadSpriteImage(g: Gfx, img: SpriteImage, path: []const u8) bool {
        return raw.gfx_load_sprite_image(g.id, img.id, path.ptr, len(path)) >= 0;
    }
    /// What is drawn next goes into img, in its own coordinates; null goes
    /// back to the canvas.
    pub fn drawInto(g: Gfx, img: ?SpriteImage) void {
        _ = raw.gfx_set_sprite_image_target(g.id, if (img) |i| i.id else 0);
    }
    pub fn deleteSpriteImage(g: Gfx, img: SpriteImage) void {
        _ = raw.gfx_delete_sprite_image(g.id, img.id);
    }
    /// Places sprite images (1 to 8 frames) at (x, y) of the area; a larger
    /// z is nearer. null when it cannot be placed.
    pub fn newSprite(g: Gfx, frames: []const SpriteImage, x: i32, y: i32, z: i32) ?Sprite {
        if (frames.len == 0 or frames.len > 8) return null;
        var ids: [8]u16 = undefined;
        for (frames, 0..) |f, i| ids[i] = @intCast(f.id);
        const id = raw.gfx_create_sprite_instance(g.id, &ids, @intCast(frames.len), x, y, z);
        return if (id > 0) .{ .id = id } else null;
    }
    /// Moves a placed sprite (shown at the next present).
    pub fn moveSprite(g: Gfx, s: Sprite, x: i32, y: i32) void {
        _ = raw.gfx_move_sprite(g.id, s.id, x, y);
    }
    pub fn setSpriteVisible(g: Gfx, s: Sprite, visible: bool) void {
        _ = raw.gfx_set_sprite_visible(g.id, s.id, @intFromBool(visible));
    }
    /// Which frame a placed sprite shows (0: the first).
    pub fn setSpriteFrame(g: Gfx, s: Sprite, frame: i32) void {
        _ = raw.gfx_set_sprite_frame(g.id, s.id, frame);
    }
    pub fn deleteSprite(g: Gfx, s: Sprite) void {
        _ = raw.gfx_delete_sprite_instance(g.id, s.id);
    }
    /// Lets go of every placed sprite and sprite image of the drawer's
    /// canvas.
    pub fn deleteAllSprites(g: Gfx) void {
        _ = raw.gfx_delete_all_sprites(g.id);
    }
    /// Keeps sprites inside a rectangle of the area (a window's sprites
    /// start clipped to its area).
    pub fn setSpriteClip(g: Gfx, x: i32, y: i32, w: i32, h: i32) void {
        _ = raw.gfx_set_sprite_clip(g.id, x, y, w, h);
    }
    pub fn clearSpriteClip(g: Gfx) void {
        _ = raw.gfx_clear_sprite_clip(g.id);
    }
    /// Draws the w x h piece of sheet at (sx, sy) to (x, y), into the
    /// canvas (its see-through pixels leave what is there).
    pub fn drawTile(g: Gfx, sheet: SpriteImage, sx: i32, sy: i32, w: i32, h: i32, x: i32, y: i32) void {
        _ = raw.gfx_draw_tile_raw(g.id, sheet.id, sx, sy, w, h, x, y);
    }

    /// Shows what was drawn, at the window's place.
    pub fn present(g: Gfx) void {
        _ = raw.gfx_present_raw(g.id, 0, 0, 0);
    }
};

/// The app window's drawer, opened by the firmware before onCreate.
pub const window = Gfx{ .id = 0 };

// ---- the log (the same log as a Ruby app's)

pub fn logDebug(msg: []const u8) void {
    _ = raw.log_debug_raw(msg.ptr, len(msg));
}
pub fn logInfo(msg: []const u8) void {
    _ = raw.log_info_raw(msg.ptr, len(msg));
}
pub fn logWarn(msg: []const u8) void {
    _ = raw.log_warn_raw(msg.ptr, len(msg));
}
pub fn logError(msg: []const u8) void {
    _ = raw.log_error_raw(msg.ptr, len(msg));
}
