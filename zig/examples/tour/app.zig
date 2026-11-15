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
const std = @import("std");
const fmrb = @import("fmrb");

pub const panic = fmrb.panic;

// The page is white and the palette is picked for contrast against it
// (RGB332, RRRGGGBB). 0x01 would be the transparent key: not used.
const paper = 0xFF; // page background (white)
const ink = 0x00; // body text and outlines (black)
const ink_sub = 0x49; // captions (dark gray)
const c_red = 0xC0;
const c_green = 0x0C;
const c_blue = 0x02;
const c_orange = 0xE8; // stands in for yellow
const c_teal = 0x0F; // stands in for cyan
const c_purple = 0x82; // stands in for magenta
const c_panel = 0xB6; // light gray fill

const picture = "/usr/share/asterism/icon.png";
const cached = "/cache/app/tour/icon.png";
const data_file = "/home/tour.txt";
const sample_ja = "\u{3053}\u{3093}\u{306b}\u{3061}\u{306f} ABC \u{65e5}\u{672c}\u{8a9e}"; // konnichiwa ABC nihongo

const pages = [_][]const u8{ "Shapes", "Text", "Image", "Sound", "System" };
const keys = [_][]const u8{
    "click or 1-5: pages  q: quit",
    "T: font",
    "I: show / hide the picture",
    "1 scale  3 beep  0 stop",
    "W: write a file",
};
const scale = [_]i32{ 262, 294, 330, 349, 392, 440, 494, 523 };

const g = fmrb.window;

fn text(x: i32, y: i32, s: []const u8, color: i32) void {
    g.drawTextBg(x, y, s, color, paper);
}

/// Formats a line into buf (cut off when it does not fit).
fn line(buf: []u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch buf;
}

fn platform() []const u8 {
    return if (fmrb.app.platform() == fmrb.app.esp32) "esp32" else "linux";
}

const Tour = struct {
    page: usize = 0,
    font_mode: usize = 0,
    started: i64 = 0,
    blink: bool = false,
    img: ?fmrb.Image = null,
    img_tried: bool = false,
    img_shown: bool = true,
    note_off_at: [2]i64 = .{ 0, 0 }, // per channel, 0: no note
    scale_i: ?usize = null, // next note of the scale
    scale_at: i64 = 0,
    file_buf: [16]u8 = undefined,
    file_text: []const u8 = "-",
    input_buf: [32]u8 = undefined,
    input: []const u8 = "-",

    pub fn onCreate(self: *Tour) void {
        self.started = fmrb.uptimeMs();
        self.readData();
        var buf: [64]u8 = undefined;
        fmrb.logInfo(line(&buf, "tour: started on {s}", .{platform()}));
        self.draw();
    }

    pub fn onDestroy(self: *Tour) void {
        fmrb.audio.noteOff(0);
        fmrb.audio.noteOff(1);
        if (self.img) |img| g.deleteImage(img);
        fmrb.logInfo("tour: bye");
    }

    // ---- the page frame

    fn draw(self: *Tour) void {
        const w = g.areaWidth();
        const h = g.areaHeight();
        g.fillRect(0, 0, w, h, paper);
        var buf: [64]u8 = undefined;
        text(4, 2, line(&buf, "{d}/5 {s}", .{ self.page + 1, pages[self.page] }), ink);
        const y0 = 14;
        switch (self.page) {
            0 => self.drawShapes(y0),
            1 => self.drawText(y0),
            2 => self.drawImage(y0),
            3 => self.drawSound(y0),
            else => self.drawSystem(y0),
        }
        text(4, h - 10, keys[self.page], ink_sub);
        g.present();
    }

    fn setPage(self: *Tour, p: usize) void {
        self.page = p;
        var buf: [64]u8 = undefined;
        fmrb.logInfo(line(&buf, "tour: page {s}", .{pages[p]}));
        self.draw();
    }

    // ---- page 1: shapes

    fn drawShapes(_: *Tour, y0: i32) void {
        g.drawRoundRect(6, y0 + 4, 56, 26, 6, c_teal);
        g.fillRoundRect(70, y0 + 4, 56, 26, 6, c_green);
        g.drawEllipse(34, y0 + 52, 26, 14, c_purple);
        g.fillEllipse(98, y0 + 52, 26, 14, c_red);
        g.drawTriangle(8, y0 + 104, 60, y0 + 104, 34, y0 + 74, c_orange);
        g.fillTriangle(72, y0 + 104, 124, y0 + 104, 98, y0 + 74, c_blue);
        const colors = [_]i32{ c_red, c_orange, c_green, c_teal };
        for ([_]i32{ -30, -10, 10, 30 }, colors) |dx, color| {
            g.drawLine(160, y0 + 104, 160 + dx, y0 + 8, color);
        }
        var i: i32 = 0;
        while (i < 3) : (i += 1) {
            g.drawCircle(140 + i * 22, y0 + 40, 9, ink);
            g.fillCircle(140 + i * 22, y0 + 40, 4, c_panel);
        }
    }

    // ---- page 2: text

    fn drawText(self: *Tour, y0: i32) void {
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

    fn drawImage(self: *Tour, y0: i32) void {
        if (!self.img_tried) {
            self.img_tried = true;
            if (g.syncFile(picture, cached)) self.img = g.createImage(cached);
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

    // ---- page 4: sound

    fn drawSound(_: *Tour, y0: i32) void {
        const rows = [_][]const u8{ "1: a scale on pulse 1", "3: a beep on pulse 2", "0: stop", "", "notes end by the clock" };
        for (rows, 0..) |r, i| text(6, y0 + 6 + @as(i32, @intCast(i)) * 12, r, if (i == 4) ink_sub else ink);
    }

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

    // ---- page 5: the system side

    fn readData(self: *Tour) void {
        self.file_text = fmrb.file.read(data_file, &self.file_buf) orelse "-";
    }

    // W: count the writes in a file of the app's own (under /home).
    fn writeData(self: *Tour) void {
        var buf: [16]u8 = undefined;
        var n: i64 = 0;
        for (fmrb.file.read(data_file, &buf) orelse "") |c| {
            if (c >= '0' and c <= '9') n = n * 10 + (c - '0');
        }
        var out: [24]u8 = undefined;
        if (!fmrb.file.write(data_file, line(&out, "{d}", .{n + 1}))) {
            fmrb.logWarn("tour: cannot write " ++ data_file);
        }
        self.readData();
    }

    fn drawSystem(self: *Tour, y0: i32) void {
        var bufs: [10][64]u8 = undefined;
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
            .{ "file", self.file_text },
            .{ "input", self.input },
        };
        for (rows, 0..) |r, i| {
            const y = y0 + 6 + @as(i32, @intCast(i)) * 11;
            text(6, y, r[0], ink_sub);
            text(86, y, r[1], ink);
        }
        if (self.blink) g.fillCircle(g.areaWidth() - 10, y0 + 8, 3, c_green);
    }

    // ---- the loop and input

    pub fn onUpdate(self: *Tour) i32 {
        const now = fmrb.uptimeMs();
        self.tickSound(now);
        const blink = @mod(@divTrunc(now - self.started, 500), 2) == 0;
        if (blink != self.blink) {
            self.blink = blink;
            if (self.page == 4) self.draw();
        }
        return 100;
    }

    pub fn onEvent(self: *Tour, ev: *const fmrb.Event) void {
        switch (ev.type) {
            fmrb.mouse_up => {
                if (ev.button != 1) return;
                self.input = line(&self.input_buf, "click {d},{d}", .{ ev.x, ev.y });
                self.setPage((self.page + 1) % pages.len);
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
        if (ev.character == 'q') {
            fmrb.app.stop();
            return;
        }
        if (self.page == 3) {
            switch (sc) {
                0x1E => { // 1
                    self.scale_i = 0;
                    self.scale_at = fmrb.uptimeMs();
                    return;
                },
                0x20 => { // 3
                    self.note(1, 988, 90, 14);
                    return;
                },
                0x27 => { // 0
                    self.silence();
                    return;
                },
                else => {},
            }
        }
        if (sc >= 0x1E and sc <= 0x22) { // 1-5
            self.setPage(@intCast(sc - 0x1E));
            return;
        }
        if (self.page == 1 and sc == 0x17) { // T
            self.font_mode = (self.font_mode + 1) % 3;
        } else if (self.page == 2 and sc == 0x0C) { // I
            self.img_shown = !self.img_shown;
        } else if (self.page == 4 and sc == 0x1A) { // W
            self.writeData();
        }
        self.draw();
    }
};

comptime {
    fmrb.exportApp(Tour);
}
