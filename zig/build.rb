#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build a Zig example into a Family mruby wasm app.
#
#   ruby zig/build.rb tour                      # -> zig/build/tour.app.wasm
#   ruby zig/build.rb tour -o <dir or file>     # e.g. fmruby-core/flash/app/zig
#
# The toolchain: zig (ZIG, default the newest ~/toolchains/zig-*/zig; 0.15
# or later). Nothing is downloaded. It runs `zig build -Dexample=<name>`
# (zig/build.zig, whose addApp holds the settings the SDK fixes:
# wasm32-freestanding, no entry point, exports kept, ReleaseSmall,
# stripped, a 16 KB stack). Caches stay under ~/toolchains/cache.
#
# The .app.toml next to the .wasm gets sdk_version = this SDK's VERSION, as
# tinygo/build.rb does (copied from the example when there is none yet).
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
system(env, *cmd, chdir: ZIG_DIR) or abort 'zig build failed'
FileUtils.cp(File.join(prefix, 'bin', "#{name}.wasm"), out)
puts "#{out} (#{File.size(out)} bytes)"

version = File.read(File.join(ZIG_DIR, '..', 'VERSION')).strip
toml_out = out.sub(/\.app\.wasm\z/, '').sub(/\.wasm\z/, '') + '.app.toml'
toml_src = File.exist?(toml_out) ? toml_out : File.join(src, "#{name}.app.toml")
if File.exist?(toml_src)
  toml = File.read(toml_src)
  line = %(sdk_version = "#{version}")
  toml = toml.match?(/^sdk_version\s*=.*$/) ? toml.sub(/^sdk_version\s*=.*$/, line) : "#{toml.chomp}\n#{line}\n"
  File.write(toml_out, toml)
  puts "#{toml_out} (#{line})"
end
