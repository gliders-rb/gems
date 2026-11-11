# frozen_string_literal: true

# Baseline performance workloads for field_struct. Run from this directory:
#   bundle exec ruby [--yjit] benchmarks/perf.rb
# See benchmarks/perf/harness.rb (repo root) for the PERF_* environment knobs.
ENV['PERF_GEM'] ||= 'field_struct'
require_relative '../lib/field_struct'
require_relative '../../../benchmarks/perf/harness'
require_relative '../../../benchmarks/perf/order_model'

CLASSES = PerfModel.define
Planting = CLASSES[0]
LineItem = CLASSES[1]
SYM = PerfModel.order_hash.freeze
STR = PerfModel.order_hash(symbol_keys: false).freeze
ORDER = Planting.new(SYM)
JSON_TEXT = ORDER.to_json.freeze
BAD = SYM.merge(number: 'x', customer_email: 'nope', lines: [{ sku: 'a', qty: '0', unit_price: '1' }]).freeze
LINE = SYM[:lines].first.freeze
raise 'order invalid' unless ORDER.valid?

Perf.workload('new from symbol-key Hash') { Planting.new(SYM) }
Perf.workload('new from string-key Hash') { Planting.new(STR) }
Perf.workload('new invalid input (error path)') { Planting.new(BAD) }
Perf.workload('new LineItem (one nested struct)') { LineItem.new(LINE) }
Perf.workload('from_json') { Planting.from_json(JSON_TEXT) }
Perf.workload('as_json') { ORDER.as_json }
Perf.workload('to_json') { ORDER.to_json }
Perf.workload('valid?') { ORDER.valid? }
Perf.workload('attribute assignment: 1 setter (integer)') { ORDER.number = '1043' }
Perf.workload('attribute assignment: 1 setter (time w/ zone)') { ORDER.placed_at = '2026-07-01T08:15:30-06:00' }
Perf.workload('attribute assignment: assign_attributes x4') do
  ORDER.assign_attributes(number: '5', customer_name: 'B', express: 'false', total: '10.5')
end
Perf.workload('with(total:)') { ORDER.with(total: '200.00') }
Perf.workload('class declaration (Planting + LineItem)') { PerfModel.define }
