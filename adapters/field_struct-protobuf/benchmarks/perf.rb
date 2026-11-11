# frozen_string_literal: true

# Baseline performance workloads for field_struct-protobuf. Run from this directory:
#   bundle exec ruby [--yjit] benchmarks/perf.rb
# The Order here has no union field (protobuf cannot map a union), everything else matches the shared Order.
ENV['PERF_GEM'] ||= 'field_struct-protobuf'
require_relative '../lib/field_struct/protobuf'
require_relative '../../../benchmarks/perf/harness'
require_relative '../../../benchmarks/perf/order_model'

Order = PerfModel.define(union: false, proto: true).first
HASH = PerfModel.order_hash(union: false)
ORDER = Order.new(HASH)
ORDERS = Array.new(1000) { |i| Order.new(HASH.merge(number: i.to_s)) }.freeze
PB = FieldStruct::Protobuf
MESSAGE = PB.to_message(ORDER)
BYTES = PB.encode(ORDER)
MESSAGES_1000 = ORDERS.map { |o| PB.to_message(o) }.freeze
BYTES_1000 = ORDERS.map { |o| PB.encode(o) }.freeze

Perf.workload('to_message, 1 order') { PB.to_message(ORDER) }
Perf.workload('from_message, 1 order') { PB.from_message(Order, MESSAGE) }
Perf.workload('encode, 1 order') { PB.encode(ORDER) }
Perf.workload('decode, 1 order') { PB.decode(Order, BYTES) }
Perf.workload('to_message, 1000 orders', items: 1000) { ORDERS.each { |o| PB.to_message(o) } }
Perf.workload('from_message, 1000 orders', items: 1000) { MESSAGES_1000.each { |m| PB.from_message(Order, m) } }
Perf.workload('encode, 1000 orders', items: 1000) { ORDERS.each { |o| PB.encode(o) } }
Perf.workload('decode, 1000 orders', items: 1000) { BYTES_1000.each { |b| PB.decode(Order, b) } }
# Reference: the same wire work with google-protobuf alone (message already built), to separate gem cost from C-ext cost.
Perf.workload('reference: raw message encode (google-protobuf only)') { MESSAGE.class.encode(MESSAGE) }
Perf.workload('reference: raw message decode (google-protobuf only)') { MESSAGE.class.decode(BYTES) }
