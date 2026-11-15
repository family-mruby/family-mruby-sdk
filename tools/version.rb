#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Work out the next SDK version by comparing boundary/boundary.json with the
# last release's (doc/wasm_apps decision 14).
#
#   ruby tools/version.rb                  # against the latest tag vX.Y.Z
#   ruby tools/version.rb --base v0.1.0    # against that tag
#   ruby tools/version.rb --base old.json --from 0.1.0
#                                          # against a boundary.json of 0.1.0
#   ruby tools/version.rb --write          # also write VERSION (and the version in
#                                          # rust/Cargo.toml and zig/build.zig.zon)
#                                          # and regenerate
#
# Breaking: something an app built before may use changed or went away -- a
#   function removed or its parameters or result changed (C types, not only
#   wasm types: an int32 that became a uint8 means another thing), a record
#   changed (a firmware would write past an older app's struct), a choice
#   renumbered or removed, a hook removed or changed, the event buffer's size.
# Addition: only additions -- functions, records, hooks, choices after the last.
# Same: the boundary is the same (its ABI hash); the SDK's own changes.
#
# From 1.0.0 on, breaking bumps MAJOR, an addition MINOR and the rest PATCH.
# While the version is 0.x (semver's convention for a boundary that is not
# stable yet) everything moves one place down: breaking bumps MINOR
# (0.1.0 -> 0.2.0), an addition or the rest PATCH (0.1.0 -> 0.1.1). 1.0.0 is
# never computed: it is written into VERSION by hand when the boundary is
# declared stable (Boundary.next_version, tested by tools/test_version.rb).
#
# With no tag yet, VERSION is the first release's and is kept as written.
require 'optparse'
require 'open3'
require_relative 'lib/boundary'

base = nil
from = nil
write = false
OptionParser.new do |o|
  o.banner = 'usage: version.rb [--base TAG|FILE] [--write]'
  o.on('--base REF') { |v| base = v }
  o.on('--from VERSION', "the base's version, when --base is a file") { |v| from = v }
  o.on('--write') { write = true }
end.parse!

def git(*args)
  out, _err, st = Open3.capture3('git', '-C', Boundary::ROOT, *args)
  st.success? ? out : nil
end

current = Boundary.version
unless base
  base = git('describe', '--tags', '--abbrev=0', '--match', 'v[0-9]*.[0-9]*.[0-9]*')&.strip
  if base.nil? || base.empty?
    puts "no release tag yet: the first release is VERSION as written (#{current})"
    exit
  end
end
old = if File.exist?(base)
        Boundary.load(base)
      else
        text = git('show', "#{base}:boundary/boundary.json") or abort "#{base}: no such file or git ref with boundary/boundary.json"
        JSON.parse(text)
      end
new = Boundary.load
base_version = from || base[/\Av?(\d+\.\d+\.\d+)\z/, 1] ||
               (File.exist?(base) ? nil : git('show', "#{base}:VERSION")&.strip)

breaking = []
added = []

# functions: the C parameters and result an app was built with
shape = ->(f) { [f['params'].map { |p| p['c'] }, f['result']['c'], f['result']['kind'] == 'void'] }
of = new['functions'].to_h { |f| [f['import'], f] }
old['functions'].each do |f|
  n = of[f['import']]
  if n.nil?
    breaking << "function #{f['import']} removed"
  elsif shape.(n) != shape.(f)
    breaking << "function #{f['import']} changed: #{shape.(f).first.join(', ')} -> #{shape.(n).first.join(', ')}"
  else
    [[f['args'], n['args']], [[f['result']], [n['result']]]].each do |oa, na|
      oa.zip(na).each do |o, x|
        next unless o && x && o['choices']

        oc = o['choices']
        nc = x['choices'] || []
        if nc.first(oc.size) != oc
          breaking << "#{f['import']}: choices #{oc.join('|')} -> #{nc.join('|')}"
        elsif nc.size > oc.size
          added << "#{f['import']}: choices added #{(nc - oc).join(', ')}"
        end
      end
    end
  end
end
(new['functions'].map { |f| f['import'] } - old['functions'].map { |f| f['import'] }).each do |n|
  added << "function #{n} added"
end

# records (field names, types and order; a choice list may grow at the end)
orr = old['records'].to_h { |r| [r['c_name'], r] }
new['records'].each do |r|
  o = orr.delete(r['c_name'])
  if o.nil?
    added << "record #{r['c_name']} added"
    next
  end
  if o['fields'].map { |f| [f['name'], f['c']] } != r['fields'].map { |f| [f['name'], f['c']] }
    breaking << "record #{r['c_name']} changed"
    next
  end
  o['fields'].zip(r['fields']).each do |of_, nf|
    next unless of_['choices']

    if nf['choices'].first(of_['choices'].size) != of_['choices']
      breaking << "#{r['c_name']}.#{nf['name']}: choices renumbered or removed"
    elsif nf['choices'].size > of_['choices'].size
      added << "#{r['c_name']}.#{nf['name']}: choices added #{(nf['choices'] - of_['choices']).join(', ')}"
    end
  end
end
orr.each_key { |n| breaking << "record #{n} removed" }

# hooks
hshape = ->(h) { [h['params'].map { |p| p['c'] }, h['result']] }
oh = old['hooks'].to_h { |h| [h['export'], h] }
new['hooks'].each do |h|
  o = oh.delete(h['export'])
  if o.nil? then added << "hook #{h['export']} added"
  elsif hshape.(o) != hshape.(h) then breaking << "hook #{h['export']} changed"
  end
end
oh.each_key { |n| breaking << "hook #{n} removed" }
breaking << 'the event buffer changed' if old['event_buffer'] != new['event_buffer']

level = if breaking.any? then :breaking
        elsif added.any? then :addition
        else :same
        end
if old['abi_hash'] != new['abi_hash'] && level == :same
  # The hash also covers what the rules above do not tell apart (a record
  # only reordered and back, ...): be safe.
  added << "the ABI hash changed (#{old['abi_hash']} -> #{new['abi_hash']}) with no difference found"
  level = :addition
end

puts "base: #{base}#{base_version ? " (#{base_version})" : ''}, boundary #{old['abi_hash']} -> #{new['abi_hash']}"
breaking.each { |l| puts "  breaking: #{l}" }
added.each { |l| puts "  added: #{l}" }
if base_version
  nxt = Boundary.next_version(base_version, level)
  puts "#{level}: the next version is #{nxt} (VERSION is #{current})"
  if write && nxt != current
    File.write(Boundary::VERSION_FILE, "#{nxt}\n")
    Boundary.write_package_versions(nxt)
    system(RbConfig.ruby, File.join(__dir__, 'gen_bindings.rb')) or abort 'gen_bindings failed'
  end
else
  puts "#{level} (the base has no version number to count from)"
  abort '--write needs a base with a version (a vX.Y.Z tag)' if write
end
