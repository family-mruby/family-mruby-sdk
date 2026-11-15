#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build a Rust example of this repository into a Family mruby wasm app
# (for the SDK's maintainers and its examples; an app of your own is built
# with `cargo build --release`, docs/getting_started.md).
#
#   ruby rust/build.rb tour                      # -> rust/build/tour.app.wasm
#   ruby rust/build.rb tour -o <dir or file>     # e.g. fmruby-core/flash/app/rust
#
# The toolchain: cargo with the wasm32-unknown-unknown target (rustup target
# add wasm32-unknown-unknown; CARGO overrides the command). Nothing is
# downloaded: the crate has no dependencies. The settings are those of
# rust/.cargo/config.toml, the file an app copies into its crate: the target,
# the release profile (size optimisation, LTO, abort on panic, stripped) and
# a 16 KB stack (-zstack-size=16384: without it the linker reserves 1 MiB
# and the module starts at 17 pages of memory).
#
# The example's <name>.app.toml is copied next to the .wasm when there is
# none there yet.
require 'fileutils'
require 'optparse'

RUST_DIR = File.expand_path(__dir__)
TARGET = 'wasm32-unknown-unknown'

out = nil
OptionParser.new do |o|
  o.banner = 'usage: build.rb <example> [-o <dir or file>]'
  o.on('-o PATH') { |v| out = v }
end.parse!
name = ARGV.shift or abort 'usage: build.rb <example> [-o <dir or file>]'
src = File.join(RUST_DIR, 'examples', name)
abort "no example #{src}" unless File.exist?(File.join(src, 'Cargo.toml'))

out ||= File.join(RUST_DIR, 'build')
out = File.join(out, "#{name}.app.wasm") if File.directory?(out) || !out.end_with?('.wasm')
FileUtils.mkdir_p(File.dirname(out))

target_dir = File.join(RUST_DIR, 'build', 'target')
env = { 'CARGO_TARGET_DIR' => target_dir }
cmd = [ENV.fetch('CARGO', 'cargo'), 'build', '--release', '-p', name]
puts cmd.join(' ')
system(env, *cmd, chdir: RUST_DIR) or abort 'cargo build failed (is the target there? rustup target add wasm32-unknown-unknown)'
FileUtils.cp(File.join(target_dir, TARGET, 'release', "#{name.tr('-', '_')}.wasm"), out)
puts "#{out} (#{File.size(out)} bytes)"

# The example's .app.toml goes next to the .wasm when there is none there
# yet (one already there is kept as it is). The SDK version is in the
# .wasm itself, the custom section "fmrb.sdk".
toml_src = File.join(src, "#{name}.app.toml")
toml_out = "#{out.sub(/\.app\.wasm\z/, '').sub(/\.wasm\z/, '')}.app.toml"
if File.exist?(toml_src) && !File.exist?(toml_out)
  FileUtils.cp(toml_src, toml_out)
  puts toml_out
end
