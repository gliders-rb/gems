# frozen_string_literal: true

# Chooses the workloads worth profiling from results/*-yjit_on.json: the 5 slowest per logical operation overall,
# then the slowest of every gem that none of those five came from. Prints "<gem dir>\t<workload>" lines.
require 'json'

DIRS = {
  'field_struct' => 'gems/field_struct', 'actionable' => 'gems/actionable',
  'field_struct-json_schema' => 'adapters/field_struct-json_schema', 'field_struct-avro' => 'adapters/field_struct-avro',
  'field_struct-protobuf' => 'adapters/field_struct-protobuf', 'actionable-otel' => 'adapters/actionable-otel',
  'actionable-tools' => 'adapters/actionable-tools'
}.freeze
dir = ENV.fetch('PERF_OUT', File.expand_path('results', __dir__))
rows = Dir[File.join(dir, '*-yjit_on.json')].flat_map { |f| JSON.parse(File.read(f)) }
rows.reject! { |r| r['workload'].start_with?('reference:') || r['gem'] == 'actionable-otel-untraced' }
# Cold-cache and class-declaration workloads are one-off costs; the profile is for steady-state paths too.
ranked = rows.sort_by { |r| -r['us_per_item'] }
picked = ranked.first(5)
(DIRS.keys - picked.map { |r| r['gem'] }).each do |gem|
  best = ranked.find { |r| r['gem'] == gem }
  picked << best if best
end
# Then the slowest steady-state workload of every gem (cold-cache and class-declaration costs are one-offs), plus
# the common paths people actually hit: construction, JSON, a plain run, and the adapters' single-object encode.
steady = ranked.reject { |r| r['workload'].match?(/cold|class declaration/) }
DIRS.each_key { |gem| (best = steady.find { |r| r['gem'] == gem }) && picked << best }
EXTRA = [['field_struct', 'new from symbol-key Hash'], ['field_struct', 'from_json'], ['field_struct', 'to_json'],
         ['actionable', 'run success, measure none'], ['actionable', 'run success, measure all (history)'],
         ['field_struct-avro', 'encode, 1 order'], ['field_struct-protobuf', 'encode, 1 order']].freeze
EXTRA.each { |gem, name| (r = rows.find { |x| x['gem'] == gem && x['workload'] == name }) && picked << r }
picked.uniq! { |r| [r['gem'], r['workload']] }
picked.each { |r| puts "#{DIRS.fetch(r['gem'])}\t#{r['workload']}" }
