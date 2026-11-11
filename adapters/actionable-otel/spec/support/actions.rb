# frozen_string_literal: true

# Beekeeping example actions (hive inspections). Defined per example with stub_const through `define_inspection`.
module ActionFixtures
  def define_inspection(queenless: false, raise_in: nil, **)
    stub_const('HiveInspection', Class.new(Actionable::Action) do
      input { optional :hive_tag, :string }
      output { optional :note, :string }
      fails :queen_missing
      skips :no_hive_due

      step :open_hive
      step :count_frames
      on_success :file_report
      on_failure :reseal_hive
      always :stamp_log

      define_method(:open_hive) { @note = "note-#{input.hive_tag}" }
      define_method(:count_frames) do
        raise ArgumentError, "frame counter jammed on hive #{input.hive_tag}" if raise_in == :charge

        fail!(:queen_missing, 'no queen') if queenless
      end
      define_method(:file_report) { @filed = true }
      define_method(:reseal_hive) { @resealed = true }
      define_method(:stamp_log) { @stamped = true }
    end)
  end
end

RSpec.configure { |c| c.include ActionFixtures }
