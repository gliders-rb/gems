# frozen_string_literal: true

# Baseline performance workloads for field_struct-avro. Run from this directory:
#   bundle exec ruby [--yjit] benchmarks/perf.rb
ENV['PERF_GEM'] ||= 'field_struct-avro'
require_relative '../lib/field_struct/avro'
require_relative '../../../benchmarks/perf/harness'
require_relative '../../../benchmarks/perf/order_model'

Order = PerfModel.define.first
ORDER = Order.new(PerfModel.order_hash)
ORDERS = Array.new(1000) { |i| Order.new(PerfModel.order_hash.merge(number: i.to_s)) }.freeze
BYTES = FieldStruct::Avro.encode(ORDER)
BYTES_1000 = ORDERS.map { |o| FieldStruct::Avro.encode(o) }.freeze
DATUM = FieldStruct::Avro.to_datum(ORDER)

Perf.workload('schema (cached)') { FieldStruct::Avro.schema(Order) }
Perf.workload('schema (cold: cache cleared)') do
  FieldStruct::Avro.clear_cache
  FieldStruct::Avro.schema(Order)
end
Perf.workload('to_datum') { FieldStruct::Avro.to_datum(ORDER) }
Perf.workload('from_datum') { FieldStruct::Avro.from_datum(Order, DATUM) }
Perf.workload('encode, 1 order') { FieldStruct::Avro.encode(ORDER) }
Perf.workload('decode, 1 order') { FieldStruct::Avro.decode(Order, BYTES) }
Perf.workload('encode, 1000 orders', items: 1000) { ORDERS.each { |o| FieldStruct::Avro.encode(o) } }
Perf.workload('decode, 1000 orders', items: 1000) { BYTES_1000.each { |b| FieldStruct::Avro.decode(Order, b) } }
