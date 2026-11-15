#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build a Rust example into a Family mruby wasm app.
#
#   ruby rust/build.rb tour                      # -> rust/build/tour.app.wasm
#   ruby rust/build.rb tour -o <dir or file>     # e.g. fmruby-core/flash/app/rust
#
# The toolchain: cargo with the wasm32-unknown-unknown target (rustup target
# add wasm32-unknown-unknown; CARGO overrides the command). Nothing is
# downloaded: the crate has no dependencies. The settings the SDK fixes: the
# release profile of rust/Cargo.toml (size optimisation, LTO, abort on
# panic, stripped) and a 16 KB stack (-zstack-size=16384: without it the
# linker reserves 1 MiB and the module starts at 17 pages of memory,
# doc/wasm_apps decision 1).
#
# The .app.toml next to the .wasm gets sdk_version = this SDK's VERSION, as
# tinygo/build.rb does (copied from the example when there is none yet).
require 'fileutils'
require 'optparse'

RUST_DIR = File.expand_path(__dir__)
TARGET = 'wasm32-unknown-unknown'
RUSTFLAGS = '-C link-arg=-zstack-size=16384'

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
env = { 'RUSTFLAGS' => [ENV['RUSTFLAGS'], RUSTFLAGS].compact.join(' '), 'CARGO_TARGET_DIR' => target_dir }
cmd = [ENV.fetch('CARGO', 'cargo'), 'build', '--release', '--target', TARGET, '-p', name]
puts "RUSTFLAGS=#{env['RUSTFLAGS'].inspect} #{cmd.join(' ')}"
system(env, *cmd, chdir: RUST_DIR) or abort 'cargo build failed (is the target there? rustup target add wasm32-unknown-unknown)'
FileUtils.cp(File.join(target_dir, TARGET, 'release', "#{name.tr('-', '_')}.wasm"), out)
puts "#{out} (#{File.size(out)} bytes)"

version = File.read(File.join(RUST_DIR, '..', 'VERSION')).strip
toml_out = out.sub(/\.app\.wasm\z/, '').sub(/\.wasm\z/, '') + '.app.toml'
toml_src = File.exist?(toml_out) ? toml_out : File.join(src, "#{name}.app.toml")
if File.exist?(toml_src)
  toml = File.read(toml_src)
  line = %(sdk_version = "#{version}")
  toml = toml.match?(/^sdk_version\s*=.*$/) ? toml.sub(/^sdk_version\s*=.*$/, line) : "#{toml.chomp}\n#{line}\n"
  File.write(toml_out, toml)
  puts "#{toml_out} (#{line})"
end
