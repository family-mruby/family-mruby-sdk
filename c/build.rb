#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build a C example into a Family mruby wasm app.
#
#   ruby c/build.rb tour                      # -> c/build/tour.app.wasm
#   ruby c/build.rb tour -o <dir or file>     # e.g. fmruby-core/flash/app/c
#
# The compiler: zig cc (ZIG, default the newest ~/toolchains/zig-*/zig; Zig
# 0.13 or later has the wasm32 target and its linker built in). CC=clang
# uses clang instead (--target=wasm32, with wasm-ld on PATH). The settings
# the SDK fixes: freestanding wasm32 (no libc, no WASI), no entry point (the
# firmware calls the hooks), size optimisation, a 16 KB stack.
#
# The example's <name>.app.toml is copied next to the .wasm when there is
# none there yet.
require 'fileutils'
require 'optparse'

C_DIR = File.expand_path(__dir__)
TOOLCHAINS = File.expand_path(ENV.fetch('TOOLCHAINS', '~/toolchains'))

out = nil
OptionParser.new do |o|
  o.banner = 'usage: build.rb <example> [-o <dir or file>]'
  o.on('-o PATH') { |v| out = v }
end.parse!
name = ARGV.shift or abort 'usage: build.rb <example> [-o <dir or file>]'
src = File.join(C_DIR, 'examples', name)
abort "no example #{src}" unless File.directory?(src)
sources = Dir[File.join(src, '*.c')].sort
abort "no .c in #{src}" if sources.empty?

out ||= File.join(C_DIR, 'build')
out = File.join(out, "#{name}.app.wasm") if File.directory?(out) || !out.end_with?('.wasm')
FileUtils.mkdir_p(File.dirname(out))

flags = ['-nostdlib', '-Os', "-I#{C_DIR}", '-Wl,--no-entry', '-Wl,-z,stack-size=16384', '-Wl,--strip-all']
env = {}
if ENV['CC']
  cmd = [ENV['CC'], '--target=wasm32', *flags, *sources, '-o', File.expand_path(out)]
else
  zig = ENV['ZIG'] || Dir[File.join(TOOLCHAINS, 'zig-*', 'zig')].max
  abort "no zig (put it in #{TOOLCHAINS}/zig-<version>/, or set ZIG= or CC=clang)" unless zig && File.executable?(zig)
  cache = File.join(TOOLCHAINS, 'cache')
  env = { 'ZIG_GLOBAL_CACHE_DIR' => File.join(cache, 'zig'), 'ZIG_LOCAL_CACHE_DIR' => File.join(cache, 'zig-local') }
  cmd = [zig, 'cc', '-target', 'wasm32-freestanding', *flags, *sources, '-o', File.expand_path(out)]
end
puts cmd.join(' ')
system(env, *cmd) or abort 'build failed'
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
