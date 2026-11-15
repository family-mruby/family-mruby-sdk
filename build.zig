//! The Zig SDK of Family mruby (the rest of this repository is the other
//! languages; build.zig.zon keeps the package to build.zig and zig/src).
//!
//! In an app of your own (docs/getting_started.md):
//!
//!     zig fetch --save git+https://github.com/family-mruby/family-mruby-sdk
//!
//! and in its build.zig:
//!
//!     const std = @import("std");
//!     const fmrb_sdk = @import("family_mruby_sdk");
//!
//!     pub fn build(b: *std.Build) void {
//!         const app = fmrb_sdk.addApp(b, .{
//!             .name = "hello",
//!             .root_source_file = b.path("src/main.zig"),
//!             .app_toml = b.path("hello.app.toml"),
//!         });
//!         b.installArtifact(app);
//!     }
//!
//! `zig build` then writes zig-out/bin/hello.app.wasm (and copies
//! hello.app.toml next to it).
//!
//! Here: `zig build -Dexample=tour` builds zig/examples/tour/app.zig into
//! zig-out/bin/tour.app.wasm (zig/build.rb runs it).
const std = @import("std");

pub fn build(b: *std.Build) void {
    const fmrb = b.addModule("fmrb", .{ .root_source_file = b.path("zig/src/fmrb.zig") });
    const example = b.option([]const u8, "example", "the example to build (zig/examples/<name>/app.zig)") orelse "tour";
    const app = addAppModule(b, example, b.path(b.fmt("zig/examples/{s}/app.zig", .{example})), fmrb);
    b.installArtifact(app);
}

pub const AppOptions = struct {
    /// The app's name: the output is <name>.app.wasm.
    name: []const u8,
    /// The app's root file; it imports the module "fmrb".
    root_source_file: std.Build.LazyPath,
    /// The app's .app.toml, installed next to the .wasm (optional).
    app_toml: ?std.Build.LazyPath = null,
};

/// A Family mruby app for the build.zig of a project that has this SDK as
/// the dependency "family_mruby_sdk": the module "fmrb" and the settings of
/// addAppModule. Install it with b.installArtifact.
pub fn addApp(b: *std.Build, options: AppOptions) *std.Build.Step.Compile {
    const sdk = b.dependency("family_mruby_sdk", .{});
    const app = addAppModule(b, options.name, options.root_source_file, sdk.module("fmrb"));
    if (options.app_toml) |toml| {
        b.getInstallStep().dependOn(&b.addInstallBinFile(toml, b.fmt("{s}.app.toml", .{options.name})).step);
    }
    return app;
}

/// A Family mruby app: wasm32-freestanding, no entry point (the firmware
/// calls the hooks), its exports kept, size-optimised and a 16 KB stack.
pub fn addAppModule(b: *std.Build, name: []const u8, root: std.Build.LazyPath, fmrb: *std.Build.Module) *std.Build.Step.Compile {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const exe = b.addExecutable(.{
        .name = b.fmt("{s}.app", .{name}),
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
