//! hello: the app docs/getting_started.md builds. A line of text and a
//! counter that goes up by itself; a key shows its character and space sets
//! the counter back to 0, q ends the app.
const std = @import("std");
const fmrb = @import("fmrb");

pub const panic = fmrb.panic;

const Hello = struct {
    count: i64 = 0,
    key: [8]u8 = undefined,
    key_len: usize = 0,
    bg: i32 = 0,
    fg: i32 = 0,

    pub fn onCreate(self: *Hello) void {
        self.bg = fmrb.rgb(255, 255, 255); // white paper (never 0x01: the transparent key)
        self.fg = fmrb.rgb(0, 0, 0);
        self.setKey("-");
        fmrb.logInfo("hello: started");
    }

    pub fn onUpdate(self: *Hello) i32 {
        self.count += 1;
        const g = fmrb.window;
        var buf: [32]u8 = undefined;
        g.fillRect(0, 0, g.areaWidth(), g.areaHeight(), self.bg);
        g.drawText(4, 4, "Hello, Family mruby!", self.fg);
        g.drawText(4, 16, std.fmt.bufPrint(&buf, "count {d}", .{self.count}) catch "", self.fg);
        g.drawText(4, 28, std.fmt.bufPrint(&buf, "key   {s}", .{self.key[0..self.key_len]}) catch "", self.fg);
        g.present();
        return 100; // call me again in 100 ms
    }

    pub fn onEvent(self: *Hello, ev: *const fmrb.Event) void {
        if (ev.type != fmrb.key_down or ev.character == 0) return;
        switch (ev.character) {
            'q' => fmrb.app.stop(),
            ' ' => {
                self.count = 0;
                self.setKey("space");
            },
            else => {
                const c = std.math.cast(u21, ev.character) orelse return;
                self.key_len = std.unicode.utf8Encode(c, &self.key) catch return;
            },
        }
    }

    pub fn onDestroy(self: *Hello) void {
        var buf: [48]u8 = undefined;
        fmrb.logInfo(std.fmt.bufPrint(&buf, "hello: bye at count {d}", .{self.count}) catch "hello: bye");
    }

    fn setKey(self: *Hello, s: []const u8) void {
        @memcpy(self.key[0..s.len], s);
        self.key_len = s.len;
    }
};

comptime {
    fmrb.exportApp(Hello);
}
