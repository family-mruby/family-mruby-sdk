# frozen_string_literal: true
#
# The boundary as the SDK sees it: boundary/boundary.json (written by
# fmruby-core's tools/boundary/gen.rb from its sig/*.rbs) and the templates
# that turn it into each language's bindings. Used by tools/gen_bindings.rb
# (write), tools/check_bindings.rb (compare) and tools/version.rb.
#
# Adding a language is adding its templates under tools/templates/<lang>/
# and a line in OUTPUTS; the helpers a template needs (names, types) go in a
# module next to Go below.
require 'erb'
require 'json'
require 'fileutils'

module Boundary
  ROOT = File.expand_path('../..', __dir__)
  MANIFEST = File.join(ROOT, 'boundary', 'boundary.json')
  VERSION_FILE = File.join(ROOT, 'VERSION')
  TEMPLATES = File.join(ROOT, 'tools', 'templates')

  # template (under tools/templates) => product (under the repository root)
  OUTPUTS = {
    'tinygo/raw.go.erb' => 'tinygo/fmrb/raw/raw.go',
    'tinygo/types.go.erb' => 'tinygo/fmrb/raw/types.go',
    'c/fmrb_sdk_version.h.erb' => 'c/fmrb_sdk_version.h',
    'rust/raw.rs.erb' => 'rust/src/raw/mod.rs',
    'rust/types.rs.erb' => 'rust/src/raw/types.rs',
    'zig/raw.zig.erb' => 'zig/src/raw.zig'
  }.freeze

  module_function

  def load(path = MANIFEST) = JSON.parse(File.read(path))

  def version
    v = File.read(VERSION_FILE).strip
    abort "VERSION: #{v.inspect} is not MAJOR.MINOR.PATCH" unless v.match?(/\A\d+\.\d+\.\d+\z/)
    v
  end

  # { product path => text } for every output, from the manifest and VERSION.
  def render_all(manifest = load, ver = version)
    OUTPUTS.to_h do |tmpl, out|
      text = ERB.new(File.read(File.join(TEMPLATES, tmpl)), trim_mode: '-')
                .result_with_hash(m: manifest, version: ver, go: Go, rust: Rust, zig: Zig)
      [out, text]
    end
  end

  def record(manifest, c_name) = manifest['records'].find { |r| r['c_name'] == c_name }

  # A record whose fields all sit at a multiple of their own size, and whose
  # size is a multiple of the largest: a language's plain struct has the same
  # bytes as the packed C one. The others are given as byte arrays.
  def natural?(rec)
    sizes = rec['fields'].map { |f| C_SIZE.fetch(f['c']) }
    rec['fields'].zip(sizes).all? { |f, s| (f['offset'] % s).zero? } && (rec['size'] % sizes.max).zero?
  end

  C_SIZE = { 'int8_t' => 1, 'uint8_t' => 1, 'int16_t' => 2, 'uint16_t' => 2, 'int32_t' => 4,
             'uint32_t' => 4, 'int64_t' => 8, 'uint64_t' => 8, 'float' => 4, 'double' => 8 }.freeze

  # The wasm type of a C type, as a module's import section spells it.
  def wasm_of(ctype)
    t = ctype.strip.sub(/\Aconst\s+/, '')
    return 'i32' if t.include?('*')

    { 'int64_t' => 'i64', 'uint64_t' => 'i64', 'double' => 'f64', 'float' => 'f32' }.fetch(t.split.first, 'i32')
  end

  # name => [wasm params, wasm result or nil] for the functions and the hooks
  def import_sigs(manifest)
    manifest['functions'].to_h { |f| [f['import'], [f['params'].map { |p| p['wasm'] }, f['result']['wasm']]] }
  end

  def hook_sigs(manifest)
    h = manifest['hooks'].to_h { |k| [k['export'], [k['params'].map { |p| p['wasm'] }, k['result'] && k['result']['wasm']]] }
    h['_initialize'] = [[], nil]
    h[manifest['event_buffer']['export']] = [[], 'i32'] if manifest['event_buffer']
    h
  end

  # The choice constants of a function, in the C header's spelling without
  # its FMRB_ prefix: [[GFX_SET_FONT_RAW_FAMILY_JA, value, comment]]. Each
  # language spells the name its own way.
  def function_choices(f)
    out = []
    f['args'].each do |a|
      next unless a['choices']

      a['choices'].each_with_index do |v, i|
        out << ["#{f['c_name']}_#{a['name']}_#{v}".upcase.delete_prefix('FMRB_'), i,
                ":#{v} (#{a['name']} of #{f['ruby']})"]
      end
    end
    (f['result']['choices'] || []).each_with_index do |v, i|
      out << ["#{f['c_name']}_#{v}".upcase.delete_prefix('FMRB_'), i, ":#{v} (the result of #{f['ruby']})"]
    end
    out
  end

  # The choice constants of a record's fields: [[record, field, [[APP_EVENT_TYPE_KEY_DOWN, value, :key_down]]]]
  def record_choices(manifest)
    manifest['records'].flat_map do |r|
      r['fields'].select { |f| f['choices'] }.map do |f|
        stem = r['c_name'].delete_prefix('fmrb_').delete_suffix('_t')
        [r, f, f['choices'].each_with_index.map { |v, i| ["#{stem}_#{f['name']}_#{v}".upcase, i, ":#{v}"] }]
      end
    end
  end

  # The parts the Rust and Zig templates share: a record's stem and type
  # name, and the C type a pointer points to.
  def stem(c_name) = c_name.delete_prefix('fmrb_').delete_suffix('_t')

  # fmrb_app_wallclock_t -> AppWallclock
  def type_name(c_name) = stem(c_name).split('_').map(&:capitalize).join

  # "const fmrb_gfx_image_info_t *" -> [true, "fmrb_gfx_image_info_t"]
  def pointee(ctype)
    t = ctype.strip
    [t.start_with?('const '), t.delete_prefix('const ').delete_suffix('*').strip]
  end

  # Names and types for the Rust templates (rust/src/raw/): functions keep
  # the import's name (gfx_fill_rect), records are AppWallclock, constants
  # are the C header's without FMRB_ (GFX_SET_FONT_RAW_FAMILY_JA).
  module Rust
    module_function

    KEYWORDS = %w[as async await break const continue crate dyn else enum extern false fn for gen if impl in
                  let loop match mod move mut pub ref return self static struct super trait true try type
                  unsafe use where while abstract become box do final macro override priv typeof unsized
                  virtual yield].freeze

    def ident(name) = KEYWORDS.include?(name) ? "r##{name}" : name

    INT = { 'int8_t' => 'i8', 'uint8_t' => 'u8', 'int16_t' => 'i16', 'uint16_t' => 'u16', 'int32_t' => 'i32',
            'uint32_t' => 'u32', 'int64_t' => 'i64', 'uint64_t' => 'u64', 'float' => 'f32', 'double' => 'f64',
            'char' => 'u8' }.freeze

    def scalar(ctype) = INT.fetch(ctype)

    # A parameter's or result's Rust type: a pointer is *const / *mut of
    # its pointee (a String or bytes: u8; a record: its struct).
    def param_type(ctype)
      return scalar(ctype) unless ctype.include?('*')

      const, to = Boundary.pointee(ctype)
      "#{const ? '*const' : '*mut'} #{to.start_with?('fmrb_') ? Boundary.type_name(to) : scalar(to)}"
    end
  end

  # Names and types for the Zig templates (zig/src/raw.zig): functions keep
  # the import's name, records are AppWallclock (extern structs), constants
  # are snake_case (gfx_set_font_raw_family_ja). Pointers are optional, so
  # a size query can pass null as C passes NULL.
  module Zig
    module_function

    KEYWORDS = %w[addrspace align allowzero and anyframe anytype asm break callconv catch comptime const
                  continue defer else enum errdefer error export extern fn for if inline linksection noalias
                  noinline nosuspend opaque or orelse packed pub resume return struct suspend switch test
                  threadlocal try union unreachable var volatile while].freeze
    # Primitive type names: a field may be called so (ev.type), a parameter
    # may not.
    PRIMITIVES = %w[type bool void anyopaque noreturn anyerror comptime_int comptime_float].freeze

    def ident(name) = (KEYWORDS + PRIMITIVES).include?(name) ? %(@"#{name}") : name

    def field_ident(name) = KEYWORDS.include?(name) ? %(@"#{name}") : name

    def scalar(ctype) = Rust::INT.fetch(ctype)

    # many: the pointer is to an array of records (a parameter with a count)
    def param_type(ctype, many: false)
      return scalar(ctype) unless ctype.include?('*')

      const, to = Boundary.pointee(ctype)
      if to.start_with?('fmrb_')
        "?#{many ? '[*]' : '*'}#{const ? 'const ' : ''}#{Boundary.type_name(to)}"
      else
        "?[*]#{const ? 'const ' : ''}#{scalar(to)}"
      end
    end

    # A function's parameters: "name: type, ..."
    def params(f)
      counts = f['params'].select { |p| p['role'] == 'count' }.map { |p| p['name'] }
      f['params'].map do |p|
        "#{ident(p['name'])}: #{param_type(p['c'], many: counts.include?("#{p['name']}_count"))}"
      end.join(', ')
    end
  end

  # Names and types for the TinyGo templates.
  module Go
    module_function

    INITIALISMS = { 'id' => 'ID', 'wx' => 'WX', 'wy' => 'WY' }.freeze
    KEYWORDS = %w[break case chan const continue default defer else fallthrough for func go goto if
                  import interface map package range return select struct switch type var].freeze

    # gfx_fill_rect -> GfxFillRect, gamepad_id -> GamepadID
    def exported(snake) = snake.split('_').map { |w| INITIALISMS[w] || w.capitalize }.join

    # text_len -> textLen (a parameter)
    def local(snake)
      parts = snake.split('_')
      name = parts.first + parts.drop(1).map { |w| INITIALISMS[w] || w.capitalize }.join
      KEYWORDS.include?(name) ? "#{name}_" : name
    end

    # fmrb_app_wallclock_t -> AppWallclock (the stem of its choice constants)
    def record_name(c_name) = exported(c_name.delete_prefix('fmrb_').delete_suffix('_t'))

    # fmrb_app_wallclock_t -> AppWallclockRecord, the Go type (the function
    # that fills it is AppWallclock)
    def record_type(c_name) = "#{record_name(c_name)}Record"

    # FMRB_GFX_SET_FONT_RAW_FAMILY_JA -> GfxSetFontRawFamilyJa
    def const_name(c_const) = exported(c_const.delete_prefix('FMRB_').downcase)

    # A parameter's Go type. Every i32 that is not a pointer is int32 but
    # uint32_t, which keeps its sign (a byte or a short travels as an i32).
    def param_type(ctype)
      return 'unsafe.Pointer' if ctype.include?('*')

      { 'int64_t' => 'int64', 'uint64_t' => 'uint64', 'double' => 'float64', 'float' => 'float32',
        'uint32_t' => 'uint32' }.fetch(ctype, 'int32')
    end

    # A record field's Go type: its own width.
    def field_type(ctype)
      { 'int8_t' => 'int8', 'uint8_t' => 'uint8', 'int16_t' => 'int16', 'uint16_t' => 'uint16',
        'int32_t' => 'int32', 'uint32_t' => 'uint32', 'int64_t' => 'int64', 'uint64_t' => 'uint64',
        'float' => 'float32', 'double' => 'float64' }.fetch(ctype)
    end

    # The unsigned type of the same width (for a byte array's accessors).
    def bits_type(ctype)
      { 1 => 'uint8', 2 => 'uint16', 4 => 'uint32', 8 => 'uint64' }.fetch(C_SIZE.fetch(ctype))
    end

    # The choice constants of a function: [[Go name, value, comment]]
    def function_choices(f)
      Boundary.function_choices(f).map { |n, v, c| [const_name(n), v, c] }
    end
  end
end
