#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build a Zig example of this repository into a Family mruby wasm app (for
# the SDK's maintainers and its examples; an app of your own is built with
# `zig build` and the SDK's addApp, docs/getting_started.md).
#
#   ruby zig/build.rb tour                      # -> zig/build/tour.app.wasm
#   ruby zig/build.rb tour -o <dir or file>     # e.g. fmruby-core/flash/app/zig
#
# The toolchain: zig (ZIG, default the newest ~/toolchains/zig-*/zig; 0.15
# or later). Nothing is downloaded. It runs `zig build -Dexample=<name>` at
# the repository's root (build.zig, whose addAppModule holds the settings:
# wasm32-freestanding, no entry point, exports kept, ReleaseSmall,
# stripped, a 16 KB stack). Caches stay under ~/toolchains/cache.
#
# The example's <name>.app.toml is copied next to the .wasm when there is
# none there yet.
require 'fileutils'
require 'optparse'

ZIG_DIR = File.expand_path(__dir__)
TOOLCHAINS = File.expand_path(ENV.fetch('TOOLCHAINS', '~/toolchains'))

out = nil
OptionParser.new do |o|
  o.banner = 'usage: build.rb <example> [-o <dir or file>]'
  o.on('-o PATH') { |v| out = v }
end.parse!
name = ARGV.shift or abort 'usage: build.rb <example> [-o <dir or file>]'
src = File.join(ZIG_DIR, 'examples', name)
abort "no example #{src}" unless File.exist?(File.join(src, 'app.zig'))
zig = ENV['ZIG'] || Dir[File.join(TOOLCHAINS, 'zig-*', 'zig')].max
abort "no zig (put it in #{TOOLCHAINS}/zig-<version>/, or set ZIG=)" unless zig && File.executable?(zig)

out ||= File.join(ZIG_DIR, 'build')
out = File.join(out, "#{name}.app.wasm") if File.directory?(out) || !out.end_with?('.wasm')
FileUtils.mkdir_p(File.dirname(out))

prefix = File.join(ZIG_DIR, 'build', 'out')
cache = File.join(TOOLCHAINS, 'cache')
env = { 'ZIG_GLOBAL_CACHE_DIR' => File.join(cache, 'zig'), 'ZIG_LOCAL_CACHE_DIR' => File.join(cache, 'zig-local') }
cmd = [zig, 'build', "-Dexample=#{name}", '--prefix', prefix]
puts cmd.join(' ')
system(env, *cmd, chdir: File.dirname(ZIG_DIR)) or abort 'zig build failed'
FileUtils.cp(File.join(prefix, 'bin', "#{name}.app.wasm"), out)
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
