#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build a TinyGo example of this repository into a Family mruby wasm app
# (for the SDK's maintainers and its examples; an app of your own is built
# with `tinygo build -target=fmrb.json`, docs/getting_started.md).
#
#   ruby tinygo/build.rb bounce                      # -> tinygo/build/bounce.app.wasm
#   ruby tinygo/build.rb bounce -o <dir or file>     # e.g. fmruby-core/flash/app/tinygo
#
# The toolchain: TINYGO (default ~/toolchains/tinygo/bin/tinygo when it is
# there, else tinygo on PATH) and its Go (~/toolchains/go/bin, put first on
# PATH). Caches stay under ~/toolchains/cache. The settings are the SDK's
# target file, tinygo/fmrb.json: wasm-unknown (no WASI), the freeing GC
# (conservative), size optimisation (TinyGo's default) and no debug info.
#
# The example's <name>.app.toml is copied next to the .wasm when there is
# none there yet.
require 'fileutils'
require 'optparse'

TINYGO_DIR = File.expand_path(__dir__)
TOOLCHAINS = File.expand_path(ENV.fetch('TOOLCHAINS', '~/toolchains'))
TINYGO = ENV['TINYGO'] || [File.join(TOOLCHAINS, 'tinygo', 'bin', 'tinygo')].find { |t| File.executable?(t) } ||
         ENV['PATH'].split(':').map { |d| File.join(d, 'tinygo') }.find { |t| File.executable?(t) }
FLAGS = %w[-target=fmrb.json].freeze

out = nil
OptionParser.new do |o|
  o.banner = 'usage: build.rb <example> [-o <dir or file>]'
  o.on('-o PATH') { |v| out = v }
end.parse!
name = ARGV.shift or abort 'usage: build.rb <example> [-o <dir or file>]'
src = File.join(TINYGO_DIR, 'examples', name)
abort "no example #{src}" unless File.directory?(src)
abort 'no TinyGo (put it in ~/toolchains/tinygo/, on PATH, or set TINYGO=)' unless TINYGO && File.executable?(TINYGO)

out ||= File.join(TINYGO_DIR, 'build')
out = File.join(out, "#{name}.app.wasm") if File.directory?(out) || !out.end_with?('.wasm')
FileUtils.mkdir_p(File.dirname(out))

cache = File.join(TOOLCHAINS, 'cache')
env = {
  'PATH' => [File.join(TOOLCHAINS, 'go', 'bin'), File.dirname(TINYGO), ENV['PATH']].join(':'),
  'XDG_CACHE_HOME' => cache, 'XDG_CONFIG_HOME' => File.join(cache, 'config'),
  'GOPATH' => File.join(cache, 'gopath'), 'GOTOOLCHAIN' => 'local', 'GOTELEMETRY' => 'off',
  'GOFLAGS' => '-mod=mod'
}
cmd = [TINYGO, 'build', *FLAGS, '-o', File.expand_path(out), "./examples/#{name}"]
puts cmd.join(' ')
system(env, *cmd, chdir: TINYGO_DIR) or abort 'tinygo build failed'
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
