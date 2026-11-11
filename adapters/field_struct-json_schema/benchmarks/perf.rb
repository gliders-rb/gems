# frozen_string_literal: true

# Baseline performance workloads for field_struct-json_schema. Run from this directory:
#   bundle exec ruby [--yjit] benchmarks/perf.rb
ENV['PERF_GEM'] ||= 'field_struct-json_schema'
require_relative '../lib/field_struct/json_schema'
require_relative '../../../benchmarks/perf/harness'
require_relative '../../../benchmarks/perf/order_model'

Catalog = PerfModel.define.first
FieldStruct::JSONSchema.generate(Catalog)

Perf.workload('generate (cached, deep copy returned)') { FieldStruct::JSONSchema.generate(Catalog) }
Perf.workload('generate (cold: cache cleared each call)') do
  FieldStruct::JSONSchema.clear_cache
  FieldStruct::JSONSchema.generate(Catalog)
end
