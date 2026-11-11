# frozen_string_literal: true

# Indicative timings, not a gate. No dependencies beyond the gem: `bundle exec rake bench`.
# BENCH_ITERATIONS sets the loop count (default 20000; the unit of work below is one run).
require_relative '../lib/actionable'

ITERATIONS = Integer(ENV.fetch('BENCH_ITERATIONS', '20000'))

class BenchTrivial < Actionable::Action; end

class BenchFive < Actionable::Action
  step :a
  step :b
  step :c
  step :d
  step :e

  private

  def a = nil
  def b = nil
  def c = nil
  def d = nil
  def e = nil
end

class BenchFiveNone < BenchFive
  measure :none
end

class BenchFiveAll < BenchFive
  measure :all
end

class BenchInput < Actionable::Action
  input do
    required :name, :string
    required :callsign, :email
    required :age, :integer
    required :score, :float
    optional :seen, :boolean
  end
end

class BenchChild < Actionable::Action
  step :work

  private

  def work = @done = true
end

class BenchParent < Actionable::Action
  step BenchChild
end

class BenchParentMeasured < BenchParent
  measure :all
end

class BenchFail < Actionable::Action
  step :sail

  private

  def sail = fail!(:adrift)
end

class BenchSkip < Actionable::Action
  step :sail

  private

  def sail = skip!(:nothing)
end

def measure(label, &block)
  yield # warm up
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ITERATIONS.times(&block)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  puts format('%-34<label>s %9.0<rate>f ops/s  %8.2<micros>f us/op', label: label, rate: ITERATIONS / [elapsed, 1e-9].max,
                                                                     micros: elapsed / ITERATIONS * 1_000_000)
end

puts "actionable-rb #{Actionable::VERSION} on Ruby #{RUBY_VERSION}, #{ITERATIONS} iterations"
Actionable.verb_position_check = false
INPUT = { name: 'Ana', callsign: 'ana@example.com', age: '31', score: '9.5', seen: 'true' }.freeze
HISTORY = BenchFiveAll.run.history

measure('trivial run') { BenchTrivial.run }
measure('5 steps, measure :none') { BenchFiveNone.run }
measure('5 steps, measure :all') { BenchFiveAll.run }
measure('5-field input coercion') { BenchInput.run(**INPUT) }
measure('nested action') { BenchParent.run }
measure('nested action, measured') { BenchParentMeasured.run }
measure('history.to_json') { HISTORY.to_json }
measure('fail! action') { BenchFail.run }
measure('skip! action') { BenchSkip.run }
