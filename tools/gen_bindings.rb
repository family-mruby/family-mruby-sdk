#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Generate the language bindings from boundary/boundary.json and VERSION.
#
#   ruby tools/gen_bindings.rb          # write what changed
#
# boundary/boundary.json and c/fmrb_boundary.h come from fmruby-core
# (`rake boundary:sdk SDK=<this checkout>` there, which runs its
# tools/boundary/gen.rb --sdk); everything else is made here, one template
# per file (tools/lib/boundary.rb, OUTPUTS). tools/check_bindings.rb fails
# when a product is stale.
require_relative 'lib/boundary'

wrote = Boundary.render_all.select do |path, text|
  full = File.join(Boundary::ROOT, path)
  next false if File.exist?(full) && File.read(full) == text

  FileUtils.mkdir_p(File.dirname(full))
  File.write(full, text)
  true
end.keys
m = Boundary.load
puts "bindings: SDK #{Boundary.version}, boundary #{m['abi_hash']} (#{m['functions'].size} functions, " \
     "#{m['records'].size} records, #{m['hooks'].size} hooks): " \
     "#{wrote.empty? ? 'nothing changed' : "wrote #{wrote.join(', ')}"}"
