#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Check that the SDK matches its boundary, and (optionally) what built apps
# import.
#
#   ruby tools/check_bindings.rb [app.wasm ...]
#   ruby tools/check_bindings.rb --against v0.1.0 app.wasm   # an older boundary
#   ruby tools/check_bindings.rb --against old.json app.wasm
#   ruby tools/check_bindings.rb --examples   # build every example, check them
#
# 1. Every generated file (tinygo/fmrb/raw/, rust/src/raw/, zig/src/raw.zig,
#    c/fmrb_sdk_version.h) is what tools/gen_bindings.rb makes from
#    boundary/boundary.json and VERSION now.
# 2. c/fmrb_boundary.h (from fmruby-core) declares the same functions and
#    hooks, with the same wasm types, and has the same ABI hash. The
#    generated TinyGo, Rust and Zig declarations are read back the same way:
#    every function with the boundary's wasm types (a check of the
#    templates, not only of their products).
# 3. Every "fmrb" import of each .wasm given is a function of the boundary
#    with the same wasm type, and every hook it exports has the boundary's
#    type. With --against, the boundary is that git tag's (or that file's)
#    instead of the current one: "would this app run on a firmware of that
#    version?" (a firmware refuses an app that imports what it lacks).
#    With --examples, every example of every language (<lang>/examples/*)
#    is built first with its language's build script into a temporary
#    directory and checked as an app; a language whose toolchain is missing
#    is skipped with a note.
# Exit status 1 on any difference.
require 'optparse'
require 'open3'
require 'tmpdir'
require_relative 'lib/boundary'

against = nil
examples = false
OptionParser.new do |o|
  o.banner = 'usage: check_bindings.rb [--against TAG|FILE] [--examples] [app.wasm ...]'
  o.on('--against REF', 'check the apps against an older boundary (a git tag or a boundary.json)') { |v| against = v }
  o.on('--examples', 'build every example of every language and check them too') { examples = true }
end.parse!

errors = []
manifest = Boundary.load

# ---- 1. generated files
Boundary.render_all(manifest).each do |path, text|
  full = File.join(Boundary::ROOT, path)
  errors << "#{path}: stale (run ruby tools/gen_bindings.rb)" unless File.exist?(full) && File.read(full) == text
end
puts "generated: #{Boundary::OUTPUTS.size} files from boundary #{manifest['abi_hash']}, SDK #{Boundary.version}"

# ---- 2. the C header
header_path = File.join(Boundary::ROOT, 'c', 'fmrb_boundary.h')
header = File.read(header_path)
hash = header[/#define FMRB_ABI_HASH 0x(\h+)u/, 1]
errors << "c/fmrb_boundary.h: ABI hash #{hash}, boundary.json #{manifest['abi_hash']}" if hash != manifest['abi_hash']
c_funcs = {}
header.scan(/FMRB_IMPORT\("(\w+)"\)\s*\n\s*(\w+)\s+\w+\(([^)]*)\);/) do |name, ret, args|
  params = args.strip == 'void' ? [] : args.split(',').map { |a| Boundary.wasm_of(a.sub(/\w+\s*\z/, '')) }
  c_funcs[name] = [params, ret == 'void' ? nil : Boundary.wasm_of(ret)]
end
c_hooks = { '_initialize' => [[], nil] }
header.scan(/FMRB_EXPORT\("(\w+)"\)\s*\n\s*([\w ]+?\s*\*?)\s*\w+\(([^)]*)\);/) do |name, ret, args|
  params = args.strip == 'void' ? [] : args.split(',').map { |a| Boundary.wasm_of(a.sub(/\w+\s*\z/, '')) }
  c_hooks[name] = [params, ret.strip == 'void' ? nil : Boundary.wasm_of(ret)]
end
errors << 'c/fmrb_boundary.h: functions differ from boundary.json' if c_funcs != Boundary.import_sigs(manifest)
errors << 'c/fmrb_boundary.h: hooks differ from boundary.json' if c_hooks != Boundary.hook_sigs(manifest)
puts "c/fmrb_boundary.h: #{c_funcs.size} functions, #{c_hooks.size - 1} hooks"

# ---- 2a. the language packages carry VERSION (tools/version.rb --write sets them)
Boundary::PACKAGE_VERSIONS.each do |path, re|
  full = File.join(Boundary::ROOT, path)
  next unless File.exist?(full)

  v = File.read(full)[re, 1]
  errors << "#{path}: version #{v.inspect}, VERSION #{Boundary.version}" if v != Boundary.version
end

# ---- 2b. the generated declarations of the other languages, read back
WASM_OF_LANG = {
  # a language's type spelling => wasm type (pointers are i32 on wasm32)
  'go' => ->(t) { { 'int64' => 'i64', 'uint64' => 'i64', 'float64' => 'f64', 'float32' => 'f32' }.fetch(t, 'i32') },
  'rust' => ->(t) { t.start_with?('*') ? 'i32' : { 'i64' => 'i64', 'u64' => 'i64', 'f64' => 'f64', 'f32' => 'f32' }.fetch(t, 'i32') },
  'zig' => ->(t) { t.start_with?('?', '*', '[') ? 'i32' : { 'i64' => 'i64', 'u64' => 'i64', 'f64' => 'f64', 'f32' => 'f32' }.fetch(t, 'i32') }
}.freeze
DECLS = {
  'tinygo/fmrb/raw/raw.go' => ['go', %r{^//go:wasmimport (\w+) (\w+)\nfunc \w+\(([^)]*)\) (\S+)$}],
  'rust/src/raw/mod.rs' => ['rust', /^    pub fn (\w+)\(([^)]*)\) -> ([^;]+);$/],
  'zig/src/raw.zig' => ['zig', /^pub extern "(\w+)" fn (\w+)\(([^)]*)\) (\S+);$/]
}.freeze
DECLS.each do |path, (lang, re)|
  full = File.join(Boundary::ROOT, path)
  next unless File.exist?(full)

  wasm = WASM_OF_LANG.fetch(lang)
  got = {}
  File.read(full).scan(re) do |*caps|
    caps = caps.flatten
    caps.unshift(manifest['import_module']) if lang == 'rust' # the module is the block's link attribute
    mod, name, args, ret = caps
    errors << "#{path}: #{name} imports from #{mod}" if mod != manifest['import_module']
    types = args.strip.empty? ? [] : args.split(', ').map { |a| lang == 'go' ? a.split(' ', 2).last : a.split(': ', 2).last }
    got[name] = [types.map { |t| wasm.call(t.strip) }, wasm.call(ret.strip)]
  end
  errors << "#{path}: functions differ from boundary.json" if got != Boundary.import_sigs(manifest)
  puts "#{path}: #{got.size} functions"
end

# ---- 3. apps
if against
  path = against
  unless File.exist?(path)
    text, st = Open3.capture2('git', '-C', Boundary::ROOT, 'show', "#{against}:boundary/boundary.json")
    abort "--against #{against}: no such file, and no boundary/boundary.json at that git ref" unless st.success?
    path = nil
  end
  manifest = path ? Boundary.load(path) : JSON.parse(text)
  puts "apps against the boundary of #{against} (#{manifest['abi_hash']})"
end
funcs = Boundary.import_sigs(manifest)
hooks = Boundary.hook_sigs(manifest)

def leb(s, i)
  v = 0
  shift = 0
  loop do
    b = s.getbyte(i)
    i += 1
    v |= (b & 0x7f) << shift
    shift += 7
    return [v, i] if b < 0x80
  end
end

VT = { 0x7f => 'i32', 0x7e => 'i64', 0x7d => 'f32', 0x7c => 'f64' }.freeze

apps = ARGV.dup
tmp = nil
if examples
  tmp = Dir.mktmpdir('fmrb-examples')
  Dir[File.join(Boundary::ROOT, '*', 'build.rb')].sort.each do |script|
    lang = File.basename(File.dirname(script))
    Dir[File.join(Boundary::ROOT, lang, 'examples', '*')].sort.each do |dir|
      next unless File.directory?(dir)

      name = File.basename(dir)
      out = File.join(tmp, lang, "#{name}.app.wasm")
      log, st = Open3.capture2e(RbConfig.ruby, script, name, '-o', out)
      if st.success?
        apps << out
      elsif log.match?(/\bno (TinyGo|zig)\b|cargo build failed|No such file or directory - cargo/)
        puts "#{lang}/#{name}: skipped (#{log.lines.last.strip})"
      else
        errors << "#{lang}/#{name}: build failed:\n#{log.lines.last(15).join}"
      end
    end
  end
end

apps.each do |path|
  s = File.binread(path)
  abort "#{path}: not wasm" unless s[0, 4] == "\0asm"
  i = 8
  types = []
  imports = []
  exports = []
  funcs_defined = [] # type index of each function the module defines
  while i < s.bytesize
    id = s.getbyte(i)
    size, i = leb(s, i + 1)
    j = i
    case id
    when 1
      n, j = leb(s, j)
      n.times do
        j += 1 # 0x60
        np, j = leb(s, j)
        ps = Array.new(np) { VT[s.getbyte(j)].tap { j += 1 } }
        nr, j = leb(s, j)
        rs = Array.new(nr) { VT[s.getbyte(j)].tap { j += 1 } }
        types << [ps, rs.first]
      end
    when 2
      n, j = leb(s, j)
      n.times do
        l, j = leb(s, j); mod = s[j, l]; j += l
        l, j = leb(s, j); name = s[j, l]; j += l
        kind = s.getbyte(j); j += 1
        if kind.zero?
          t, j = leb(s, j)
          imports << [mod, name, types[t]]
        else
          errors << "#{path}: imports #{mod}.#{name} that is not a function (the firmware gives functions only)"
          break
        end
      end
    when 3
      n, j = leb(s, j)
      n.times { t, j = leb(s, j); funcs_defined << t }
    when 7
      n, j = leb(s, j)
      n.times do
        l, j = leb(s, j); name = s[j, l]; j += l
        kind = s.getbyte(j); j += 1
        idx, j = leb(s, j)
        exports << [name, idx] if kind.zero?
      end
    end
    i += size
  end
  imports.each do |mod, name, sig|
    if mod != manifest['import_module']
      errors << "#{path}: imports #{mod}.#{name} (the firmware gives only #{manifest['import_module']})"
    elsif !funcs.key?(name)
      errors << "#{path}: imports #{mod}.#{name}, not in the boundary"
    elsif funcs[name] != sig
      errors << "#{path}: #{mod}.#{name} is #{sig.inspect}, the boundary's #{funcs[name].inspect}"
    end
  end
  found = []
  exports.each do |name, idx|
    next unless hooks.key?(name)

    found << name
    sig = idx < imports.size ? imports[idx][2] : types[funcs_defined[idx - imports.size]]
    errors << "#{path}: exports #{name} as #{sig.inspect}, the boundary's #{hooks[name].inspect}" if sig != hooks[name]
  end
  buf = manifest['event_buffer'] && manifest['event_buffer']['export']
  if buf && found.include?('on_event') && !found.include?(buf)
    puts "#{File.basename(path)}: note: on_event without #{buf} (built with an older SDK; " \
         'the firmware puts the record on the stack)'
  end
  label = tmp && path.start_with?(tmp) ? path.delete_prefix("#{tmp}/") : File.basename(path)
  puts "#{label}: #{s.bytesize} bytes, #{imports.size} imports " \
       "(#{imports.map { |_, n, _| n }.join(' ')}), hooks #{found.join(' ')}"
end

FileUtils.rm_rf(tmp) if tmp

if errors.empty?
  puts 'ok'
else
  puts errors
  exit 1
end
