# frozen_string_literal: true

# Prints markdown tables (one per gem) from results/*.json, and a hotspot listing from results/profiles/*.json.
require 'json'

dir = ENV.fetch('PERF_OUT', File.expand_path('results', __dir__))
load_rows = lambda do |mode|
  Dir[File.join(dir, "*-yjit_#{mode}.json")].flat_map { |f| JSON.parse(File.read(f)) }.group_by { |r| r['gem'] }
end
off = load_rows.call('off')
on = load_rows.call('on')

def ips(value) = value >= 1000 ? format('%.0f', value).reverse.scan(/\d{1,3}/).join(',').reverse : format('%.1f', value)
def num(value) = value >= 100 ? ips(value) : format('%.1f', value)

(on.keys | off.keys).sort.each do |gem|
  puts "### #{gem}\n\n"
  puts '| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |'
  puts '|---|---:|---:|---:|---:|---:|'
  (on[gem] || off[gem]).each do |row|
    name = row['workload']
    o = off[gem]&.find { |r| r['workload'] == name }
    n = on[gem]&.find { |r| r['workload'] == name }
    puts "| #{name} | #{row['items']} | #{o ? ips(o['ips']) : '-'} | #{n ? ips(n['ips']) : '-'} | " \
         "#{n ? num(n['us_per_item']) : '-'} | #{num((n || o)['allocs_per_item'])} |"
  end
  puts
end

puts "## Hotspot listing (cpu, YJIT on)\n\n"
Dir[File.join(dir, 'profiles', '*-cpu.json')].sort.each do |f|
  prof = JSON.parse(File.read(f))
  puts "### #{prof['gem']}: #{prof['workload']} (#{prof['samples']} samples excl. GC; GC = #{prof['gc_wall_pct']}% of wall)\n\n"
  puts '| self % | total % | frame | defined at | hottest line |'
  puts '|---:|---:|---|---|---:|'
  prof['top'].each do |t|
    file = t['file'].to_s.sub(%r{.*/timeworxs/gems/}, '')
    puts "| #{t['self_pct']} | #{t['total_pct']} | `#{t['name']}` | #{file}:#{t['line']} | #{t['hot_line']} |"
  end
  puts
end
