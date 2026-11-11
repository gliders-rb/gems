# frozen_string_literal: true

# Measures (never ships) how much of `new` is the per-call Symbol building in Field#ivar_name / #setter_name:
# the same Planting.new before and after a monkeypatch that returns precomputed Symbols. Run:
#   bundle exec ruby --yjit benchmarks/headroom.rb
ENV['PERF_GEM'] ||= 'field_struct-headroom'
require_relative '../lib/field_struct'
require_relative '../../../benchmarks/perf/harness'
require_relative '../../../benchmarks/perf/order_model'

Planting = PerfModel.define.first
SYM = PerfModel.order_hash.freeze

timings = lambda do |label|
  200.times { Planting.new(SYM) } # warm
  best = Array.new(7) do
    t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    2000.times { Planting.new(SYM) }
    (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t) / 2000 * 1e6
  end.min
  allocs = Perf.allocs_per_call(-> { Planting.new(SYM) }, 1)
  puts format('%-34<l>s %7.2<u>f us/new  %6.1<a>f allocs/new', l: label, u: best, a: allocs)
  best
end

before = timings.call('baseline')
ivars = Hash.new { |h, name| h[name] = :"@#{name}" }
setters = Hash.new { |h, name| h[name] = :"#{name}=" }
FieldStruct::Field.define_method(:ivar_name) { ivars[name] }
FieldStruct::Field.define_method(:setter_name) { setters[name] }
after = timings.call('cached ivar/setter Symbols')
puts format('speedup %.2fx', before / after)
Perf.workloads.clear
