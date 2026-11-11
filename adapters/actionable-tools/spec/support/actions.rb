# frozen_string_literal: true

require 'bigdecimal'

# Fixture actions: a gauge recalibration with every feature the tools adapter reads.
module Tides
  class Mooring < FieldStruct::Base
    required :basin, :string
  end

  class RecalibrateGauge < Actionable::Action
    input do
      required :gauge_id, :string, description: 'The gauge to recalibrate'
      required :offset_mm, :big_decimal, in: 0.01..500
      optional :cause, :string, enum: %w[drifted fouled]
      required :operator_id, :integer
      optional :moored_at, Mooring
    end

    output do
      required :record_id, :string
      required :offset_mm, :big_decimal
      optional :moored_at, Mooring
    end

    fails :out_of_tolerance, 'offsets over 100 need a surveyor', kind: :rejected
    skips :already_calibrated

    step :recalibrate

    private

    def recalibrate
      fail!(:out_of_tolerance) if input.offset_mm > 100
      skip!(:already_calibrated) if input.gauge_id == 'stale'
      @record_id = "cal_#{input.gauge_id}"
      @offset_mm = input.offset_mm
      @moored_at = input.moored_at
    end
  end

  class Heartbeat < Actionable::Action
    step :ok

    private

    def ok = succeed('fine')
  end

  class RouteFeed < Actionable::Action
    input_for :kind do
      on(:tidal, Class.new(FieldStruct::Base) { required :gauge, :string })
      on(:river, Class.new(FieldStruct::Base) { required :basin, :string })
    end
    step :noop

    private

    def noop = succeed
  end

  # Free-form output: no output block, the result carries whatever the step hands over.
  class Probe < Actionable::Action
    input { required :echo, :string }
    step :pong

    private

    def pong = succeed(echo: input.echo)
  end
end

module Harbor
  class RecalibrateGauge < Actionable::Action
    input { required :gauge_id, :string }
    step :ok

    private

    def ok = succeed
  end
end

class HTTPClient < Actionable::Action
  input { required :url, :string }
  step :ok

  private

  def ok = succeed
end

class Gauge2Buoy < Actionable::Action
  input { required :id, :string }
  step :ok

  private

  def ok = succeed
end

module Tides
  class Glitch < Actionable::Action
    input { required :n, :integer }
    step :boom

    private

    def boom = raise(KeyError, 'sensor fault')
  end

  class Remap < Actionable::Action
    input do
      required :level, :integer
      required :station, :string
      serialize :json, level: :peak_level, station: :site
    end
    step :go

    private

    def go = succeed(level: input.level, station: input.station)
  end
end
