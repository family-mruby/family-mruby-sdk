#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Tests of the version numbering (tools/version.rb, Boundary.next_version):
# the rule while 0.x and from 1.0.0 on, and version.rb end to end against
# made-up older boundaries (one with a function this one lacks: this one
# broke it; one without a function this one has: this one added it; the
# same one).
#
#   ruby tools/test_version.rb
require 'json'
require 'open3'
require 'tmpdir'
require_relative 'lib/boundary'

failures = 0
check = lambda do |what, got, want|
  if got == want
    puts "ok   #{what}: #{got}"
  else
    puts "FAIL #{what}: #{got.inspect}, expected #{want.inspect}"
    failures += 1
  end
end

# ---- the rule
{
  ['0.1.0', :breaking] => '0.2.0', ['0.1.0', :addition] => '0.1.1', ['0.1.0', :same] => '0.1.1',
  ['0.3.4', :breaking] => '0.4.0', ['0.3.4', :addition] => '0.3.5',
  ['1.0.0', :breaking] => '2.0.0', ['1.0.0', :addition] => '1.1.0', ['1.0.0', :same] => '1.0.1',
  ['1.2.3', :breaking] => '2.0.0', ['1.2.3', :addition] => '1.3.0', ['1.2.3', :same] => '1.2.4'
}.each { |(base, level), want| check.call("next_version(#{base}, #{level})", Boundary.next_version(base, level), want) }

# ---- version.rb against made-up older boundaries
now = Boundary.load
broke = JSON.parse(JSON.generate(now))
broke['functions'] << broke['functions'].first.merge('import' => 'gfx_draw_hologram', 'c_name' => 'fmrb_gfx_draw_hologram')
grown = JSON.parse(JSON.generate(now))
grown['functions'].pop
Dir.mktmpdir do |dir|
  { 'breaking' => broke, 'addition' => grown, 'same' => now }.each do |name, old|
    path = File.join(dir, "#{name}.json")
    File.write(path, JSON.generate(old))
    { '0.1.0' => { 'breaking' => '0.2.0', 'addition' => '0.1.1', 'same' => '0.1.1' },
      '1.4.2' => { 'breaking' => '2.0.0', 'addition' => '1.5.0', 'same' => '1.4.3' } }.each do |from, wants|
      out, st = Open3.capture2(RbConfig.ruby, File.join(__dir__, 'version.rb'), '--base', path, '--from', from)
      got = st.success? ? out[/the next version is (\S+)/, 1] : "exit #{st.exitstatus}"
      check.call("version.rb, #{name} since #{from}", got, wants[name])
    end
  end
end

puts failures.zero? ? 'all passed' : "#{failures} failed"
exit(failures.zero? ? 0 : 1)
