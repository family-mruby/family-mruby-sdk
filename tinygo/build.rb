#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build a TinyGo example into a Family mruby wasm app.
#
#   ruby tinygo/build.rb bounce                      # -> tinygo/build/bounce.app.wasm
#   ruby tinygo/build.rb bounce -o <dir or file>     # e.g. fmruby-core/flash/app/tinygo
#
# The toolchain: TINYGO (default ~/toolchains/tinygo/bin/tinygo) and its Go
# (~/toolchains/go/bin, put first on PATH). Caches stay under
# ~/toolchains/cache. The settings the SDK fixes: the target wasm-unknown
# (no WASI), the freeing GC (conservative, doc/wasm_apps decision 1), size
# optimisation and no debug info.
#
# The .app.toml next to the .wasm gets sdk_version = this SDK's VERSION (the
# firmware names it when it refuses an app that imports a function it does
# not have). When there is none yet, the example's <name>.app.toml is copied
# there first; one that is already there keeps everything else.
require 'fileutils'
require 'optparse'

TINYGO_DIR = File.expand_path(__dir__)
TOOLCHAINS = File.expand_path(ENV.fetch('TOOLCHAINS', '~/toolchains'))
TINYGO = ENV.fetch('TINYGO', File.join(TOOLCHAINS, 'tinygo', 'bin', 'tinygo'))
FLAGS = %w[-target=wasm-unknown -gc=conservative -opt=z -no-debug].freeze

out = nil
OptionParser.new do |o|
  o.banner = 'usage: build.rb <example> [-o <dir or file>]'
  o.on('-o PATH') { |v| out = v }
end.parse!
name = ARGV.shift or abort 'usage: build.rb <example> [-o <dir or file>]'
src = File.join(TINYGO_DIR, 'examples', name)
abort "no example #{src}" unless File.directory?(src)
abort "no TinyGo at #{TINYGO}" unless File.executable?(TINYGO)

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

version = File.read(File.join(TINYGO_DIR, '..', 'VERSION')).strip
toml_out = out.sub(/\.app\.wasm\z/, '').sub(/\.wasm\z/, '') + '.app.toml'
toml_src = File.exist?(toml_out) ? toml_out : File.join(src, "#{name}.app.toml")
if File.exist?(toml_src)
  toml = File.read(toml_src)
  line = %(sdk_version = "#{version}")
  toml = if toml.match?(/^sdk_version\s*=.*$/)
           toml.sub(/^sdk_version\s*=.*$/, line)
         else
           "#{toml.chomp}\n#{line}\n"
         end
  File.write(toml_out, toml)
  puts "#{toml_out} (#{line})"
end
