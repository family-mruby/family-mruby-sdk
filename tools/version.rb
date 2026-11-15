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
#   ruby tools/version.rb --write          # also write VERSION and regenerate
#
# MAJOR: something an app built before may use changed or went away -- a
#   function removed or its parameters or result changed (C types, not only
#   wasm types: an int32 that became a uint8 means another thing), a record
#   changed (a firmware would write past an older app's struct), a choice
#   renumbered or removed, a hook removed or changed, the event buffer's size.
# MINOR: only additions -- functions, records, hooks, choices after the last.
# PATCH: the boundary is the same (its ABI hash); the SDK's own changes.
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

major = []
minor = []

# functions: the C parameters and result an app was built with
shape = ->(f) { [f['params'].map { |p| p['c'] }, f['result']['c'], f['result']['kind'] == 'void'] }
of = new['functions'].to_h { |f| [f['import'], f] }
old['functions'].each do |f|
  n = of[f['import']]
  if n.nil?
    major << "function #{f['import']} removed"
  elsif shape.(n) != shape.(f)
    major << "function #{f['import']} changed: #{shape.(f).first.join(', ')} -> #{shape.(n).first.join(', ')}"
  else
    [[f['args'], n['args']], [[f['result']], [n['result']]]].each do |oa, na|
      oa.zip(na).each do |o, x|
        next unless o && x && o['choices']

        oc = o['choices']
        nc = x['choices'] || []
        if nc.first(oc.size) != oc
          major << "#{f['import']}: choices #{oc.join('|')} -> #{nc.join('|')}"
        elsif nc.size > oc.size
          minor << "#{f['import']}: choices added #{(nc - oc).join(', ')}"
        end
      end
    end
  end
end
(new['functions'].map { |f| f['import'] } - old['functions'].map { |f| f['import'] }).each do |n|
  minor << "function #{n} added"
end

# records (field names, types and order; a choice list may grow at the end)
orr = old['records'].to_h { |r| [r['c_name'], r] }
new['records'].each do |r|
  o = orr.delete(r['c_name'])
  if o.nil?
    minor << "record #{r['c_name']} added"
    next
  end
  if o['fields'].map { |f| [f['name'], f['c']] } != r['fields'].map { |f| [f['name'], f['c']] }
    major << "record #{r['c_name']} changed"
    next
  end
  o['fields'].zip(r['fields']).each do |of_, nf|
    next unless of_['choices']

    if nf['choices'].first(of_['choices'].size) != of_['choices']
      major << "#{r['c_name']}.#{nf['name']}: choices renumbered or removed"
    elsif nf['choices'].size > of_['choices'].size
      minor << "#{r['c_name']}.#{nf['name']}: choices added #{(nf['choices'] - of_['choices']).join(', ')}"
    end
  end
end
orr.each_key { |n| major << "record #{n} removed" }

# hooks
hshape = ->(h) { [h['params'].map { |p| p['c'] }, h['result']] }
oh = old['hooks'].to_h { |h| [h['export'], h] }
new['hooks'].each do |h|
  o = oh.delete(h['export'])
  if o.nil? then minor << "hook #{h['export']} added"
  elsif hshape.(o) != hshape.(h) then major << "hook #{h['export']} changed"
  end
end
oh.each_key { |n| major << "hook #{n} removed" }
major << 'the event buffer changed' if old['event_buffer'] != new['event_buffer']

level = if major.any? then :major
        elsif minor.any? then :minor
        else :patch
        end
if old['abi_hash'] != new['abi_hash'] && level == :patch
  # The hash also covers what the rules above do not tell apart (a record
  # only reordered and back, ...): be safe.
  minor << "the ABI hash changed (#{old['abi_hash']} -> #{new['abi_hash']}) with no difference found"
  level = :minor
end

puts "base: #{base}#{base_version ? " (#{base_version})" : ''}, boundary #{old['abi_hash']} -> #{new['abi_hash']}"
major.each { |l| puts "  major: #{l}" }
minor.each { |l| puts "  minor: #{l}" }
if base_version
  ma, mi, pa = base_version.split('.').map(&:to_i)
  nxt = case level
        when :major then "#{ma + 1}.0.0"
        when :minor then "#{ma}.#{mi + 1}.0"
        else "#{ma}.#{mi}.#{pa + 1}"
        end
  puts "#{level}: the next version is #{nxt} (VERSION is #{current})"
  if write && nxt != current
    File.write(Boundary::VERSION_FILE, "#{nxt}\n")
    system(RbConfig.ruby, File.join(__dir__, 'gen_bindings.rb')) or abort 'gen_bindings failed'
  end
else
  puts "#{level} (the base has no version number to count from)"
  abort '--write needs a base with a version (a vX.Y.Z tag)' if write
end
