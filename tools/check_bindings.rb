#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Check the hand-written TinyGo bindings against the generated C header, and
# (optionally) a built app's imports.
#
#   ruby tools/check_bindings.rb [--header PATH] [app.wasm ...]
#
# The header is fmruby-core's generated sdk/c/fmrb_boundary.h; by default the
# one in a fmruby-core checkout next to this repository
# (../fmruby-core/sdk/c/fmrb_boundary.h). It is not copied here yet: the
# generator writes each description in Japanese and English, and this
# repository keeps its sources ASCII.
#
# 1. Every //go:wasmimport fmrb <name> in tinygo/fmrb/*.go must be a function
#    the header declares (FMRB_IMPORT("<name>")), with the same number of
#    parameters, each of the same wasm type (int32/uint32/pointer -> i32,
#    int64 -> i64, double/float64 -> f64), and the same result.
# 2. Every "fmrb" import of each .wasm given must be in the header with the
#    same wasm type, and every hook it exports (the functions the firmware
#    calls: FMRB_EXPORT("<name>") at the header's end, and _initialize) must
#    have the header's wasm type.
# Exit status 1 on any difference.
require 'optparse'

ROOT = File.expand_path('..', __dir__)
header = ENV['FMRB_HEADER'] || File.expand_path('../fmruby-core/sdk/c/fmrb_boundary.h', ROOT)
OptionParser.new { |o| o.on('--header PATH') { |v| header = v } }.parse!

C_TYPES = { 'int32_t' => 'i32', 'uint32_t' => 'i32', 'int16_t' => 'i32', 'uint16_t' => 'i32',
            'int8_t' => 'i32', 'uint8_t' => 'i32', 'int64_t' => 'i64', 'uint64_t' => 'i64',
            'double' => 'f64', 'float' => 'f32' }.freeze
GO_TYPES = { 'int32' => 'i32', 'uint32' => 'i32', 'unsafe.Pointer' => 'i32', 'uintptr' => 'i32',
             'int64' => 'i64', 'uint64' => 'i64', 'float64' => 'f64', 'float32' => 'f32' }.freeze

def c_wasm_type(t)
  t = t.strip.sub(/\Aconst\s+/, '')
  return 'i32' if t.include?('*')
  C_TYPES.fetch(t.split.first) { abort "unknown C type #{t}" }
end

# name => [params, result]
c = {}
File.read(header).scan(/FMRB_IMPORT\("(\w+)"\)\s*\n\s*(\w+)\s+\w+\(([^)]*)\);/) do |name, ret, args|
  params = args.strip == 'void' ? [] : args.split(',').map { |a| c_wasm_type(a.sub(/\w+\s*\z/, '')) }
  c[name] = [params, ret == 'void' ? nil : c_wasm_type(ret)]
end
abort "no functions read from #{header}" if c.empty?

# the hooks: name => [params, result]
hooks = { '_initialize' => [[], nil] }
File.read(header).scan(/FMRB_EXPORT\("(\w+)"\)\s*\n\s*(\w+)\s+\w+\(([^)]*)\);/) do |name, ret, args|
  params = args.strip == 'void' ? [] : args.split(',').map { |a| c_wasm_type(a.sub(/\w+\s*\z/, '')) }
  hooks[name] = [params, ret == 'void' ? nil : c_wasm_type(ret)]
end
abort "no hooks read from #{header}" if hooks.size == 1

errors = []
go = {}
Dir[File.join(ROOT, 'tinygo', 'fmrb', '*.go')].each do |f|
  File.read(f).scan(/^\/\/go:wasmimport\s+(\w+)\s+(\w+)\s*\nfunc\s+\w+\(([^)]*)\)\s*([\w.]*)/) do |mod, name, args, ret|
    errors << "#{name}: import module #{mod}, expected fmrb" unless mod == 'fmrb'
    # Go groups names before one type: "x, y int32"
    types = []
    pending = 0
    args.split(',').map(&:strip).reject(&:empty?).each do |a|
      parts = a.split
      if parts.size == 1
        pending += 1
      else
        (pending + 1).times { types << GO_TYPES.fetch(parts[1]) { abort "unknown Go type #{parts[1]} in #{name}" } }
        pending = 0
      end
    end
    go[name] = [types, ret.empty? ? nil : GO_TYPES.fetch(ret) { abort "unknown Go type #{ret}" }]
  end
end
go.each do |name, sig|
  if !c.key?(name)
    errors << "#{name}: not in the header"
  elsif c[name] != sig
    errors << "#{name}: Go #{sig.inspect}, header #{c[name].inspect}"
  end
end
puts "tinygo/fmrb: #{go.size} imports checked against #{c.size} functions of #{File.basename(header)}"

# ---- a .wasm's imports and exports
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

ARGV.each do |path|
  s = File.binread(path)
  abort "#{path}: not wasm" unless s[0, 4] == "\0asm"
  i = 8
  types = []
  imports = []
  exports = []
  funcs = [] # type index of each function the module defines
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
        ps = Array.new(np) { (VT[s.getbyte(j)]).tap { j += 1 } }
        nr, j = leb(s, j)
        rs = Array.new(nr) { (VT[s.getbyte(j)]).tap { j += 1 } }
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
          break # tables, memories and globals are not imported by these apps
        end
      end
    when 3
      n, j = leb(s, j)
      n.times { t, j = leb(s, j); funcs << t }
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
    if mod != 'fmrb'
      errors << "#{path}: imports #{mod}.#{name} (the firmware gives only fmrb)"
    elsif !c.key?(name)
      errors << "#{path}: imports fmrb.#{name}, not in the header"
    elsif c[name] != sig
      errors << "#{path}: fmrb.#{name} is #{sig.inspect}, header #{c[name].inspect}"
    end
  end
  found = []
  exports.each do |name, idx|
    next unless hooks.key?(name)

    found << name
    sig = idx < imports.size ? imports[idx][2] : types[funcs[idx - imports.size]]
    errors << "#{path}: exports #{name} as #{sig.inspect}, header #{hooks[name].inspect}" if sig != hooks[name]
  end
  puts "#{File.basename(path)}: #{s.bytesize} bytes, #{imports.size} imports (#{imports.map { |m, n, _| "#{m}.#{n}" }.join(' ')}), hooks #{found.join(' ')}"
end

if errors.empty?
  puts 'ok'
else
  puts errors
  exit 1
end
