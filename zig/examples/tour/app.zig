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
const std = @import("std");
const fmrb = @import("fmrb");

pub const panic = fmrb.panic;

// The page is white and the palette is picked for contrast against it
// (RGB332, RRRGGGBB). 0x01 would be the transparent key: not used.
const paper = 0xFF; // page background (white)
const ink = 0x00; // body text (black)
const ink_sub = 0x49; // captions, labels, frames (dark gray)
const c_red = 0xC0;
const c_green = 0x0C;
const c_blue = 0x02;
const c_orange = 0xE8;
const c_teal = 0x0F;
const c_panel = 0xB6; // light gray fill
const c_sky = 0x9B; // the tile map's sky

const y0 = 14; // the top of a page's body
const cache = "/cache/app/tour/";
const picture = "/usr/share/asterism/icon.png";
const sheet_src = "/usr/share/sprites/test/tilesheet.png";
const tune_src = "/usr/share/music/korobeiniki.fmsq";
const voice_file = "/usr/share/sounds/voice/mahjong/default/pon.wav";
const dir = "/home/tour";
const sample_ja = "\u{3053}\u{3093}\u{306b}\u{3061}\u{306f} ABC \u{65e5}\u{672c}\u{8a9e}"; // konnichiwa ABC nihongo

const Page = enum(usize) { shapes, text, image, sprites, tiles, sound, files, input, system, system_plus };
const n_pages = 10;
const pages = [n_pages][]const u8{ "Shapes", "Text", "Image", "Sprites", "Tiles", "Sound", "Files", "Input", "System", "System+" };
const keys = [n_pages][]const u8{
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
};
const scale = [_]i32{ 262, 294, 330, 349, 392, 440, 494, 523 };
const sprite_files = [4][]const u8{ "enemy1_a", "enemy1_b", "enemy2_a", "enemy2_b" };
const tile_map = [4][]const u8{ "............", "........33..", "..0.1...22..", "444455554444" };
const max_points = 256;

const g = fmrb.window;

fn text(x: i32, y: i32, s: []const u8, color: i32) void {
    g.drawTextBg(x, y, s, color, paper);
}

/// A label and its value on one row.
fn row(x: i32, vx: i32, y: i32, label: []const u8, value: []const u8) void {
    text(x, y, label, ink_sub);
    text(vx, y, value, ink);
}

/// Formats a line into buf (cut off when it does not fit).
fn line(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch buf;
}

fn platform() []const u8 {
    return if (fmrb.app.platform() == fmrb.app.esp32) "esp32" else "linux";
}

const Point = struct { x: i32, y: i32, start: bool }; // start: the first point of a stroke

const Tour = struct {
    page: Page = .shapes,
    font_mode: usize = 0,
    started: i64 = 0,
    blink: bool = false,
    second: i64 = 0,
    img: ?fmrb.Image = null,
    img_tried: bool = false,
    img_shown: bool = true,
    note_off_at: [2]i64 = .{ 0, 0 }, // per channel, 0: no note
    scale_i: ?usize = null, // next note of the scale
    scale_at: i64 = 0,
    input_buf: [32]u8 = undefined,
    input: []const u8 = "-", // the last input
    // sprites
    spr_tried: bool = false,
    sprites: ?[4]fmrb.Sprite = null,
    sx: [4]i32 = .{ 0, 0, 0, 0 },
    sy: [4]i32 = .{ 0, 0, 0, 0 },
    dx: [4]i32 = .{ 2, -2, 3, -3 },
    dy: [4]i32 = .{ 1, 2, -1, -2 },
    step: i32 = 0,
    paused: bool = false,
    hidden0: bool = false,
    // tiles
    sheet_tried: bool = false,
    sheet: ?fmrb.SpriteImage = null,
    // a tune and a voice
    tune_loaded: bool = false,
    tune: []const u8 = "stopped",
    voice: []const u8 = "-",
    // files
    file_last: []const u8 = "-",
    // input
    pen: bool = false,
    n_pts: usize = 0,
    pts: [max_points]Point = undefined,
    typed_buf: [30]u8 = undefined,
    n_typed: usize = 0,

    pub fn onCreate(self: *Tour) void {
        self.started = fmrb.uptimeMs();
        var buf: [64]u8 = undefined;
        fmrb.logInfo(line(&buf, "tour: started on {s}", .{platform()}));
        self.draw();
    }

    pub fn onDestroy(self: *Tour) void {
        fmrb.audio.noteOff(0);
        fmrb.audio.noteOff(1);
        fmrb.audio.stop();
        cleanFiles();
        if (self.img) |img| g.deleteImage(img);
        g.deleteAllSprites();
        fmrb.logInfo("tour: bye");
    }

    // ---- the page frame

    fn draw(self: *Tour) void {
        const w = g.areaWidth();
        const h = g.areaHeight();
        g.fillRect(0, 0, w, h, paper);
        const p = @backingInt(self.page);
        var buf: [64]u8 = undefined;
        text(4, 2, line(&buf, "{d}/10 {s}", .{ p + 1, pages[p] }), ink);
        switch (self.page) {
            .shapes => drawShapes(),
            .text => self.drawText(),
            .image => self.drawImage(),
            .sprites => self.drawSprites(),
            .tiles => self.drawTiles(),
            .sound => self.drawSound(),
            .files => self.drawFiles(),
            .input => self.drawInput(),
            .system => self.drawSystem(),
            .system_plus => drawSystemPlus(),
        }
        text(4, h - 10, keys[p], ink_sub);
        g.present();
    }

    /// Leaves the page shown, then enters p.
    fn setPage(self: *Tour, p: usize) void {
        switch (self.page) {
            .sprites => self.showSprites(false),
            .sound => self.stopTune(),
            .files => cleanFiles(),
            else => {},
        }
        self.page = @fromBackingInt(@intCast(p));
        var buf: [64]u8 = undefined;
        fmrb.logInfo(line(&buf, "tour: page {s}", .{pages[p]}));
        switch (self.page) {
            .sprites => self.showSprites(true),
            .files => {
                setupFiles();
                self.file_last = "-";
            },
            else => {},
        }
        self.draw();
    }

    // ---- page 2: text

    fn drawText(self: *Tour) void {
        const modes = [_][]const u8{ "default font", "ja font", "mixed (ascii + ja)" };
        text(6, y0 + 6, modes[self.font_mode], ink_sub);
        switch (self.font_mode) {
            0 => text(6, y0 + 20, "ABC abc 123", c_blue),
            1 => {
                g.setFont(fmrb.font_ja, 12);
                text(6, y0 + 20, sample_ja, c_blue);
                g.setFont(fmrb.font_default, 0);
            },
            else => g.drawTextMixed(6, y0 + 20, sample_ja, c_blue, paper),
        }
        var sum: i32 = 0;
        for (1..11) |i| sum += @intCast(i);
        var lang: [16]u8 = undefined;
        var bufs: [5][64]u8 = undefined;
        const rows = [_][]const u8{
            line(&bufs[0], "language {s}", .{fmrb.app.language(&lang)}),
            line(&bufs[1], "sum(1..10) = {d}", .{sum}),
            line(&bufs[2], "2^16 = {d}", .{@as(i32, 1) << 16}),
            line(&bufs[3], "area {d}x{d}", .{ g.areaWidth(), g.areaHeight() }),
            line(&bufs[4], "SDK {s}", .{fmrb.sdk_version}),
        };
        for (rows, 0..) |r, i| text(6, y0 + 40 + @as(i32, @intCast(i)) * 10, r, ink);
    }

    // ---- page 3: a picture

    fn drawImage(self: *Tour) void {
        if (!self.img_tried) {
            self.img_tried = true;
            if (g.syncFile(picture, cache ++ "icon.png")) self.img = g.createImage(cache ++ "icon.png");
            if (self.img == null) fmrb.logWarn("tour: no picture from " ++ picture);
        }
        text(6, y0 + 6, picture, ink_sub);
        const img = self.img orelse {
            text(6, y0 + 20, "no picture", c_red);
            return;
        };
        if (self.img_shown) g.drawImage(img, 6, y0 + 20, 2.0);
        var buf: [64]u8 = undefined;
        text(80, y0 + 20, line(&buf, "id {d}", .{img.id}), ink);
        text(80, y0 + 32, line(&buf, "{d}x{d} px, x2", .{ img.width, img.height }), ink);
    }

    // ---- page 4: sprites

    fn setupSprites(self: *Tour) void {
        self.spr_tried = true;
        var imgs: [4]fmrb.SpriteImage = undefined;
        for (sprite_files, 0..) |f, i| {
            var src: [64]u8 = undefined;
            var name: [32]u8 = undefined;
            imgs[i] = loadSprite(line(&src, "/usr/share/sprites/shooter/{s}.png", .{f}), line(&name, "{s}.png", .{f}), 16, 12) orelse {
                var buf: [64]u8 = undefined;
                fmrb.logWarn(line(&buf, "tour: no sprite {s}", .{f}));
                return;
            };
        }
        var sprites: [4]fmrb.Sprite = undefined;
        for (0..4) |k| {
            const frames = if (k % 2 == 1) imgs[2..4] else imgs[0..2];
            const ki: i32 = @intCast(k);
            self.sx[k] = 16 + 52 * ki;
            self.sy[k] = y0 + 24 + 20 * ki;
            sprites[k] = g.newSprite(frames, self.sx[k], self.sy[k], ki) orelse {
                fmrb.logWarn("tour: cannot place a sprite");
                return;
            };
        }
        self.sprites = sprites;
    }

    fn showSprites(self: *Tour, on: bool) void {
        const sprites = self.sprites orelse return;
        for (sprites, 0..) |s, k| g.setSpriteVisible(s, on and !(k == 0 and self.hidden0));
    }

    fn spriteStatus(self: *Tour) void {
        var buf: [64]u8 = undefined;
        text(6, y0 + 124, line(&buf, "step {d}  {s}  1: {s}  ", .{
            self.step,
            if (self.paused) "paused" else "moving",
            if (self.hidden0) "hidden" else "shown",
        }), ink);
    }

    fn drawSprites(self: *Tour) void {
        if (!self.spr_tried) self.setupSprites();
        if (self.sprites == null) {
            text(6, y0 + 20, "no sprites", c_red);
            return;
        }
        text(6, y0 + 4, "4 sprites, 2 frames each", ink_sub);
        g.drawRect(6, y0 + 16, 216, 104, ink_sub);
        self.spriteStatus();
    }

    fn stepSprites(self: *Tour) void {
        const sprites = self.sprites orelse return;
        if (self.paused) return;
        for (sprites, 0..) |s, k| {
            bounce(&self.sx[k], &self.dx[k], 7, 205);
            bounce(&self.sy[k], &self.dy[k], y0 + 17, y0 + 107);
            g.moveSprite(s, self.sx[k], self.sy[k]);
        }
        self.step += 1;
        if (@mod(self.step, 4) == 0) {
            for (sprites) |s| g.setSpriteFrame(s, @mod(@divTrunc(self.step, 4), 2));
        }
        self.spriteStatus();
        g.present();
    }

    // ---- page 5: tiles

    fn drawTiles(self: *Tour) void {
        if (!self.sheet_tried) {
            self.sheet_tried = true;
            self.sheet = loadSprite(sheet_src, "tiles.png", 64, 32);
            if (self.sheet == null) fmrb.logWarn("tour: no tiles from " ++ sheet_src);
        }
        const sheet = self.sheet orelse {
            text(6, y0 + 20, "no tiles", c_red);
            return;
        };
        text(6, y0 + 4, "draw_tile: one tile per call", ink_sub);
        g.fillRect(6, y0 + 16, 72, 36, c_panel);
        var i: i32 = 0;
        while (i < 8) : (i += 1) tile(sheet, i, 8 + 18 * @mod(i, 4), y0 + 18 + 18 * @divTrunc(i, 4));
        text(86, y0 + 18, "tilesheet.png", ink);
        text(86, y0 + 30, "64x32 px, 8 tiles", ink);
        text(86, y0 + 42, "a 12x4 map below", ink);
        g.fillRect(18, y0 + 58, 192, 64, c_sky);
        for (tile_map, 0..) |cells, r| {
            for (cells, 0..) |c, col| {
                if (c != '.') tile(sheet, c - '0', 18 + 16 * @as(i32, @intCast(col)), y0 + 58 + 16 * @as(i32, @intCast(r)));
            }
        }
    }

    // ---- page 6: sound

    // A note sounds until it is switched off, so its end is booked by the
    // clock (frames stretch when drawing is slow).
    fn note(self: *Tour, ch: usize, freq: i32, ms: i64, volume: i32) void {
        fmrb.audio.noteOnRaw(@intCast(ch), freq, volume, 2, 0);
        self.note_off_at[ch] = fmrb.uptimeMs() + ms;
    }

    fn silence(self: *Tour) void {
        for (&self.note_off_at, 0..) |*at, ch| {
            fmrb.audio.noteOff(@intCast(ch));
            at.* = 0;
        }
        self.scale_i = null;
    }

    fn tickSound(self: *Tour, now: i64) void {
        for (&self.note_off_at, 0..) |*at, ch| {
            if (at.* != 0 and at.* <= now) {
                fmrb.audio.noteOff(@intCast(ch));
                at.* = 0;
            }
        }
        if (self.scale_i) |i| {
            if (now >= self.scale_at) {
                if (i >= scale.len) {
                    self.scale_i = null;
                    return;
                }
                self.note(0, scale[i], 150, 12);
                self.scale_i = i + 1;
                self.scale_at = now + 200;
            }
        }
    }

    // the tune and the voice

    fn drawSound(self: *Tour) void {
        var bufs: [2][64]u8 = undefined;
        const rows = [_][]const u8{
            "S: a scale on pulse 1",
            "B: a beep on pulse 2",
            "M: korobeiniki (FMSQ) on / off",
            "V: a voice (WAV)",
            "X: stop it all",
            "",
            line(&bufs[0], "tune   {s}", .{self.tune}),
            line(&bufs[1], "voice  {s}", .{self.voice}),
        };
        for (rows, 0..) |r, i| text(6, y0 + 6 + @as(i32, @intCast(i)) * 12, r, ink);
        text(6, y0 + 114, "notes end by the clock", ink_sub);
    }

    fn stopTune(self: *Tour) void {
        if (std.mem.eql(u8, self.tune, "playing")) {
            fmrb.audio.stop();
            self.tune = "stopped";
        }
    }

    fn toggleTune(self: *Tour) void {
        if (std.mem.eql(u8, self.tune, "playing")) {
            self.stopTune();
            return;
        }
        if (!self.tune_loaded) {
            self.tune_loaded = g.syncFile(tune_src, cache ++ "tune.fmsq") and fmrb.audio.loadFmsqFile(0, cache ++ "tune.fmsq");
            if (!self.tune_loaded) {
                fmrb.logWarn("tour: cannot load " ++ tune_src);
                self.tune = "cannot load";
                return;
            }
        }
        fmrb.audio.playSlot(0, fmrb.Audio.main);
        self.tune = "playing";
    }

    fn playVoice(self: *Tour) void {
        const r = fmrb.audio.playWav(voice_file);
        self.voice = if (r == 1) "played" else if (r == 0) "not on this machine" else "failed";
    }

    // ---- page 7: files

    fn drawFiles(self: *Tour) void {
        var bufs: [7][64]u8 = undefined;
        var size: []const u8 = "-";
        if (fmrb.file.size(dir ++ "/hello.txt")) |n| size = line(&bufs[1], "hello.txt, {d} B", .{n});
        const read = fmrb.file.read(dir ++ "/hello.txt", &bufs[2]) orelse "-";
        var data: [1024]u8 = undefined;
        var lines: usize = 0;
        if (fmrb.file.read(dir ++ "/count.txt", &data)) |d| lines = std.mem.count(u8, d, "\n");
        var names: [64]u8 = undefined;
        var list: []const u8 = "";
        if (fmrb.file.list(dir, &names)) |all| {
            var it = std.mem.tokenizeScalar(u8, all, '\n');
            var n: usize = 0;
            while (it.next()) |name| {
                if (n > 0) {
                    bufs[4][n] = ' ';
                    n += 1;
                }
                @memcpy(bufs[4][n .. n + name.len], name);
                n += name.len;
            }
            list = bufs[4][0..n];
        }
        var free: []const u8 = "-";
        if (fmrb.file.freeBytes(dir)) |n| free = line(&bufs[5], "{d} KB", .{@divTrunc(n, 1024)});
        const rows = [_][2][]const u8{
            .{ "dir", dir ++ "/" },
            .{ "wrote", size },
            .{ "read", read },
            .{ "count", line(&bufs[3], "{d} lines", .{lines}) },
            .{ "list", list },
            .{ "free", free },
            .{ "last", self.file_last },
        };
        for (rows, 0..) |r, i| row(6, 58, y0 + 6 + @as(i32, @intCast(i)) * 11, r[0], r[1]);
        text(6, y0 + 86, "all removed when you leave the page", ink_sub);
    }

    fn fileKey(self: *Tour, sc: i32) void {
        switch (sc) {
            0x1A => { // W
                _ = fmrb.file.append(dir ++ "/count.txt", "w\n");
                self.file_last = "appended";
            },
            0x07 => { // D
                self.file_last = if (fmrb.file.delete(dir ++ "/count.txt")) "deleted count.txt" else "no count.txt";
            },
            else => {},
        }
    }

    // ---- page 8: input

    fn drawInput(self: *Tour) void {
        text(6, y0 + 4, "drag inside the box to draw", ink_sub);
        g.drawRect(6, y0 + 16, 216, 84, ink_sub);
        for (self.pts[0..self.n_pts], 0..) |p, i| {
            if (p.start) {
                g.setPixel(p.x, p.y, c_blue);
            } else {
                g.drawLine(self.pts[i - 1].x, self.pts[i - 1].y, p.x, p.y, c_blue);
            }
        }
        row(6, 42, y0 + 106, "typed", self.typed_buf[0..self.n_typed]);
        row(6, 42, y0 + 118, "last", self.input);
    }

    /// Keeps a point of the stroke (the first one starts it) and draws the
    /// line to it.
    fn addPoint(self: *Tour, x: i32, y: i32, start: bool) void {
        if (self.n_pts >= max_points) return;
        const p = Point{ .x = std.math.clamp(x, 7, 220), .y = std.math.clamp(y, y0 + 17, y0 + 98), .start = start };
        const i = self.n_pts;
        self.pts[i] = p;
        self.n_pts += 1;
        if (start) {
            g.setPixel(p.x, p.y, c_blue);
        } else {
            g.drawLine(self.pts[i - 1].x, self.pts[i - 1].y, p.x, p.y, c_blue);
        }
        g.present();
    }

    fn typeChar(self: *Tour, c: u8) void {
        if (self.n_typed == self.typed_buf.len) { // keep the last 30
            std.mem.copyForwards(u8, self.typed_buf[0 .. self.n_typed - 1], self.typed_buf[1..self.n_typed]);
            self.n_typed -= 1;
        }
        self.typed_buf[self.n_typed] = c;
        self.n_typed += 1;
    }

    // ---- page 9: the system side

    fn drawSystem(self: *Tour) void {
        var bufs: [8][64]u8 = undefined;
        var clock: []const u8 = "-";
        if (fmrb.wallclock()) |c| {
            clock = line(&bufs[5], "{d:0>2}:{d:0>2}:{d:0>2}", .{ c.hour, c.minute, c.second });
        }
        // the .app.toml next to the .app.wasm this app was started from
        var path: [128]u8 = undefined;
        const script = fmrb.app.scriptPath(&path);
        var toml: []const u8 = "-";
        if (std.mem.endsWith(u8, script, ".wasm")) {
            var tpath: [133]u8 = undefined;
            const p = line(&tpath, "{s}.toml", .{script[0 .. script.len - 5]});
            if (fmrb.file.size(p)) |n| toml = line(&bufs[7], "{d} B", .{n});
        }
        var name: [64]u8 = undefined;
        var lang: [16]u8 = undefined;
        const rows = [_][2][]const u8{
            .{ "name", fmrb.app.name(&name) },
            .{ "pid", line(&bufs[1], "{d}", .{fmrb.app.pid()}) },
            .{ "platform", platform() },
            .{ "language", fmrb.app.language(&lang) },
            .{ "uptime", line(&bufs[4], "{d} s", .{@divTrunc(fmrb.uptimeMs() - self.started, 1000)}) },
            .{ "clock", clock },
            .{ "memory", line(&bufs[6], "{d} KB free", .{fmrb.memoryFree() / 1024}) },
            .{ "toml", toml },
        };
        for (rows, 0..) |r, i| row(6, 86, y0 + 6 + @as(i32, @intCast(i)) * 11, r[0], r[1]);
        if (self.blink) g.fillCircle(g.areaWidth() - 10, y0 + 8, 3, c_green);
    }

    // ---- the loop and input

    pub fn onUpdate(self: *Tour) i32 {
        const now = fmrb.uptimeMs();
        self.tickSound(now);
        const blink = @mod(@divTrunc(now - self.started, 500), 2) == 0;
        if (blink != self.blink) {
            self.blink = blink;
            if (self.page == .system) self.draw();
        }
        if (self.page == .sprites) self.stepSprites();
        if (@divTrunc(now, 1000) != self.second) {
            self.second = @divTrunc(now, 1000);
            if (self.page == .system_plus) self.draw();
        }
        return 100;
    }

    pub fn onEvent(self: *Tour, ev: *const fmrb.Event) void {
        switch (ev.type) {
            fmrb.mouse_down => {
                if (ev.button == 1 and self.page == .input and inPad(ev.x, ev.y)) {
                    self.pen = true;
                    self.addPoint(ev.x, ev.y, true);
                }
            },
            fmrb.mouse_move => if (self.pen) self.addPoint(ev.x, ev.y, false),
            fmrb.mouse_up => {
                if (ev.button != 1) return;
                self.input = line(&self.input_buf, "click {d},{d}", .{ ev.x, ev.y });
                if (self.pen) {
                    self.pen = false;
                    self.draw();
                    return;
                }
                self.setPage((@backingInt(self.page) + 1) % n_pages);
            },
            fmrb.key_down => {
                if (ev.character > ' ' and ev.character < 127) {
                    self.input = line(&self.input_buf, "key {c}", .{@as(u8, @intCast(ev.character))});
                } else {
                    self.input = line(&self.input_buf, "key code {d}", .{ev.keycode});
                }
                self.key(ev);
            },
            else => {},
        }
    }

    fn key(self: *Tour, ev: *const fmrb.Event) void {
        const sc = ev.scancode;
        const p = @backingInt(self.page);
        if (ev.character == 'q') {
            fmrb.app.stop();
            return;
        }
        switch (sc) {
            0x4F => return self.setPage((p + 1) % n_pages), // right
            0x50 => return self.setPage((p + n_pages - 1) % n_pages), // left
            0x1E...0x26 => return self.setPage(@intCast(sc - 0x1E)), // 1-9
            0x27 => return self.setPage(9), // 0
            else => {},
        }
        switch (self.page) {
            .text => if (sc == 0x17) { // T
                self.font_mode = (self.font_mode + 1) % 3;
            },
            .image => if (sc == 0x0C) { // I
                self.img_shown = !self.img_shown;
            },
            .sprites => if (sc == 0x0B) { // H
                if (self.sprites) |s| {
                    self.hidden0 = !self.hidden0;
                    g.setSpriteVisible(s[0], !self.hidden0);
                }
            } else if (sc == 0x13) { // P
                self.paused = !self.paused;
            },
            .sound => switch (sc) {
                0x16 => { // S
                    self.scale_i = 0;
                    self.scale_at = fmrb.uptimeMs();
                },
                0x05 => self.note(1, 988, 90, 14), // B
                0x10 => self.toggleTune(), // M
                0x19 => self.playVoice(), // V
                0x1B => { // X
                    self.silence();
                    self.stopTune();
                },
                else => {},
            },
            .files => self.fileKey(sc),
            .input => if (sc == 0x2A) { // backspace
                self.n_typed = 0;
                self.n_pts = 0;
            } else if (ev.character >= ' ' and ev.character < 127) {
                self.typeChar(@intCast(ev.character));
            },
            .system_plus => if (sc == 0x06) { // C
                _ = fmrb.app.setClipboard("copied by the tour");
            },
            else => {},
        }
        self.draw();
    }
};

// ---- page 1: shapes

/// round to the nearest integer, halves away from zero
fn round(v: f64) i32 {
    return if (v >= 0) @intFromFloat(v + 0.5) else -@as(i32, @intFromFloat(-v + 0.5));
}

/// sin of an angle in degrees: folded into -90..90, then the Taylor series
/// to x^13 (@sin would bring compiler-rt's, 7 KB more).
fn sinDeg(deg: i32) f64 {
    var d = @mod(deg, 360); // 0..359
    if (d > 180) d -= 360; // -179..180
    if (d > 90) {
        d = 180 - d;
    } else if (d < -90) {
        d = -180 - d;
    }
    const x = @as(f64, @floatFromInt(d)) * 3.141592653589793 / 180.0;
    var term = x;
    var sum = x;
    var n: i32 = 1;
    while (n <= 6) : (n += 1) {
        term *= -x * x / @as(f64, @floatFromInt((2 * n) * (2 * n + 1)));
        sum += term;
    }
    return sum;
}

fn cosDeg(deg: i32) f64 {
    return sinDeg(deg + 90);
}

fn drawShapes() void {
    // left: the filled shapes, 57 x 25, 7 apart
    g.fillRect(10, 22, 57, 25, c_blue);
    g.fillRoundRect(10, 54, 57, 25, 6, c_teal);
    g.fillEllipse(38, 98, 28, 12, c_orange);
    g.fillTriangle(10, 142, 66, 142, 38, 118, c_red);
    // centre: concentric circles, 8 apart
    for ([_]i32{ c_red, c_orange, c_teal, c_blue }, 1..) |c, i| g.drawCircle(114, 82, @as(i32, @intCast(i)) * 8, c);
    g.fillCircle(114, 82, 3, c_red);
    // right: a regular hexagon around (190, 82), r 32, pointing up
    const cx = 190;
    const cy = 82;
    const r = 32.0;
    var vx: [6]i32 = undefined;
    var vy: [6]i32 = undefined;
    for (0..6) |k| {
        const a = -90 + 60 * @as(i32, @intCast(k));
        vx[k] = cx + round(r * cosDeg(a));
        vy[k] = cy + round(r * sinDeg(a));
    }
    for (0..3) |k| g.drawLine(vx[k], vy[k], vx[k + 3], vy[k + 3], c_teal);
    g.drawCircle(cx, cy, @as(i32, @intFromFloat(r * cosDeg(30))) - 1, c_orange); // inside, 1 dot clear
    for (0..6) |k| g.drawLine(vx[k], vy[k], vx[(k + 1) % 6], vy[(k + 1) % 6], c_blue);
    g.fillCircle(cx, cy, 3, c_red);
}

// ---- page 4 and 5: sprite images

/// Syncs a picture and reads it into a new sprite image.
fn loadSprite(src: []const u8, name: []const u8, w: i32, h: i32) ?fmrb.SpriteImage {
    var buf: [64]u8 = undefined;
    const dest = line(&buf, cache ++ "{s}", .{name});
    if (!g.syncFile(src, dest)) return null;
    const img = g.newSpriteImage(w, h, 0x00, true) orelse return null;
    return if (g.loadSpriteImage(img, dest)) img else null;
}

/// Keeps v in lo..hi, turning d at an end.
fn bounce(v: *i32, d: *i32, lo: i32, hi: i32) void {
    v.* += d.*;
    if (v.* < lo) {
        v.* = lo;
        d.* = -d.*;
    } else if (v.* > hi) {
        v.* = hi;
        d.* = -d.*;
    }
}

/// Tile i of the sheet (4 to a row) at (x, y).
fn tile(sheet: fmrb.SpriteImage, i: i32, x: i32, y: i32) void {
    g.drawTile(sheet, 16 * @mod(i, 4), 16 * @divTrunc(i, 4), 16, 16, x, y);
}

// ---- page 7: files

fn setupFiles() void {
    _ = fmrb.file.mkdir(dir);
    _ = fmrb.file.write(dir ++ "/hello.txt", "hello from the tour");
}

fn cleanFiles() void {
    _ = fmrb.file.delete(dir ++ "/count.txt");
    _ = fmrb.file.delete(dir ++ "/hello.txt");
    _ = fmrb.file.delete(dir);
}

// ---- page 8: input

fn inPad(x: i32, y: i32) bool {
    return x > 6 and x < 221 and y > y0 + 16 and y < y0 + 99;
}

// ---- page 10: the clipboard, the clock, the app's wasm numbers

fn sysY(i: i32) i32 {
    return y0 + 6 + i * 11;
}

fn drawSystemPlus() void {
    var clip_buf: [24]u8 = undefined;
    const clip = fmrb.app.clipboard(&clip_buf, 20);
    const first = clip[0 .. std.mem.indexOfScalar(u8, clip, '\n') orelse clip.len];
    text(6, sysY(0), "clipboard", ink_sub);
    if (first.len == 0) text(70, sysY(0), "(empty)", ink) else g.drawTextMixed(70, sysY(0), first, ink, paper);
    var bufs: [7][64]u8 = undefined;
    row(6, 70, sysY(1), "changes", line(&bufs[0], "{d}", .{fmrb.app.clipboardGen()}));
    text(6, sysY(2), "wallclock", ink_sub);
    if (!g.drawWallclock(70, sysY(2), ink, paper)) text(70, sysY(2), "-", ink);
    var v = [_][]const u8{ "-", "-", "-", "-", "-", "-" };
    if (fmrb.app.wasmAppStats(fmrb.app.pid())) |s| {
        v[0] = line(&bufs[1], "{d} pages, max {d}", .{ s.pages, s.max_pages });
        v[1] = line(&bufs[2], "{d} B", .{s.binary_size});
        v[2] = line(&bufs[3], "{d} calls", .{s.calls});
        v[3] = line(&bufs[4], "{d} us, max {d}", .{ s.hook_us, s.hook_max_us });
    }
    if (fmrb.app.wasmStats()) |s| v[4] = line(&bufs[5], "{d}, pool {d} KB", .{ s.apps, s.pool_used / 1024 });
    if (fmrb.app.gfxStats()) |s| v[5] = line(&bufs[6], "{d}", .{s.presents});
    const labels = [_][]const u8{ "memory", "binary", "hooks", "last hook", "wasm apps", "frames" };
    for (labels, v, 0..) |label, value, i| row(6, 70, sysY(@as(i32, @intCast(i)) + 3), label, value);
}

comptime {
    fmrb.exportApp(Tour);
}
