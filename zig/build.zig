//! The Zig SDK of Family mruby.
//!
//! As a dependency: the module "fmrb" (src/fmrb.zig). An app's build.zig
//! takes it with b.dependency("family_mruby_sdk", .{}).module("fmrb") and
//! builds a wasm32-freestanding executable with the settings of
//! `addApp` below.
//!
//! Here: `zig build -Dexample=tour` builds examples/tour/app.zig into
//! zig-out/bin/tour.wasm (zig/build.rb runs it and writes the .app.toml).
const std = @import("std");

pub fn build(b: *std.Build) void {
    const fmrb = b.addModule("fmrb", .{ .root_source_file = b.path("src/fmrb.zig") });
    const example = b.option([]const u8, "example", "the example to build (examples/<name>/app.zig)") orelse "tour";
    const app = addApp(b, example, b.path(b.fmt("examples/{s}/app.zig", .{example})), fmrb);
    b.installArtifact(app);
}

/// A Family mruby app: wasm32-freestanding, no entry point (the firmware
/// calls the hooks), its exports kept, size-optimised and a 16 KB stack.
pub fn addApp(b: *std.Build, name: []const u8, root: std.Build.LazyPath, fmrb: *std.Build.Module) *std.Build.Step.Compile {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const exe = b.addExecutable(.{
        .name = name,
        .root_module = b.createModule(.{
            .root_source_file = root,
            .target = target,
            .optimize = .ReleaseSmall,
            .strip = true,
            .imports = &.{.{ .name = "fmrb", .module = fmrb }},
        }),
    });
    exe.entry = .disabled;
    exe.rdynamic = true;
    exe.stack_size = 16384;
    return exe;
}
