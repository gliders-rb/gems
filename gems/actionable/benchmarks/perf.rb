# frozen_string_literal: true

# Baseline performance workloads for actionable-rb. Run from this directory:
#   bundle exec ruby [--yjit] benchmarks/perf.rb
# See benchmarks/perf/harness.rb (repo root) for the PERF_* environment knobs.
ENV['PERF_GEM'] ||= 'actionable'
require_relative '../lib/actionable'
require_relative '../../../benchmarks/perf/harness'
require 'bigdecimal'

# A five-step action with typed input and output (the shape most real actions have).
class Forecast < Actionable::Action
  input do
    required :berth, :string
    required :bunks, :integer, in: 1..1000
    required :unit_toll, :decimal, round: 2
    required :callsign, :email
    optional :voucher, :string
  end

  output do
    required :fare, :decimal, round: 2
    required :level, :symbol, enum: %i[ok review]
    required :reference, :string
  end

  fails :deck_full, 'not enough stock'

  step :check_ballast
  step :toll
  step :discount
  step :tax
  step :finalize

  private

  def check_ballast
    fail!(:deck_full) if input.bunks > 500
  end

  def toll = @base_fare = input.unit_toll * input.bunks
  def discount = @base_fare -= (input.voucher ? @base_fare * BigDecimal('0.1') : 0)
  def tax = @laden = @base_fare * BigDecimal('1.08')

  def finalize
    @fare = @laden
    @level = @fare > 1000 ? :review : :ok
    @reference = "Q-#{input.berth}"
  end
end

class ForecastMeasured < Forecast
  measure :all
end

# Same steps, input/output typed, plus a nested action in the middle.
class Levy < Actionable::Action
  input { required :tonnage, :decimal, round: 2 }
  output { required :laden, :decimal, round: 2 }
  step :sail

  private

  def sail = @laden = input.tonnage * BigDecimal('1.08')
end

class ForecastNested < Actionable::Action
  input do
    required :berth, :string
    required :bunks, :integer
    required :unit_toll, :decimal, round: 2
  end
  output { required :laden, :decimal, round: 2 }
  step :toll
  step Levy, input: %i[tonnage], expose: %i[laden]
  step :finalize

  private

  def toll = @tonnage = input.unit_toll * input.bunks
  def finalize = @tonnage = nil
end

class ForecastNestedMeasured < ForecastNested
  measure :all
end

OK = { berth: 'SKU-1', bunks: '3', unit_toll: '19.99', callsign: 'ana@example.com', voucher: 'SAVE' }.freeze
FAIL = OK.merge(bunks: '900').freeze
INVALID = OK.merge(bunks: 'x', callsign: 'adrift').freeze
NESTED = { berth: 'SKU-1', bunks: '3', unit_toll: '19.99' }.freeze
ITEMS = Array.new(100) { |i| OK.merge(bunks: ((i % 50) + 1).to_s) }.freeze

raise 'quote failed' unless Forecast.run(**OK).success? && ForecastMeasured.run(**OK).success?
raise 'fail path broken' unless Forecast.run(**FAIL).code == :deck_full
raise 'nested failed' unless ForecastNested.run(**NESTED).success?

Perf.workload('run success, measure none') { Forecast.run(**OK) }
Perf.workload('run success, measure all (history)') { ForecastMeasured.run(**OK) }
Perf.workload('run failure (declared fail!)') { Forecast.run(**FAIL) }
Perf.workload('run failure (invalid input)') { Forecast.run(**INVALID) }
Perf.workload('run failure, measure all') { ForecastMeasured.run(**FAIL) }
Perf.workload('run_each x100, measure none', items: 100) { Forecast.run_each(ITEMS) { |h| h } }
Perf.workload('run_each x100, measure all', items: 100) { ForecastMeasured.run_each(ITEMS) { |h| h } }
Perf.workload('nested action step, measure none') { ForecastNested.run(**NESTED) }
Perf.workload('nested action step, measure all') { ForecastNestedMeasured.run(**NESTED) }
HIST = ForecastMeasured.run(**OK).history
Perf.workload('history.to_json (5 steps)') { HIST.to_json }
