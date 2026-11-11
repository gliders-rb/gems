# frozen_string_literal: true

module FieldStruct
  module Types
    # An instant as a DateTime. A zone-less string lands at offset 0, or in +zone:+ when declared.
    class DateTime < Temporal
      # Named formats the +format:+ option accepts (strptime Strings, or the RFC 3339 reader).
      # @return [::Hash{::Symbol=>::Object}]
      PRESETS = Time::PRESETS

      class << self
        # @return [::Hash{::Symbol=>::Object}] +iso8601+ (RFC 3339), +rfc2822+ and +db+
        def presets
          PRESETS
        end

        # @return [true]
        def zoned?
          true
        end
      end

      # @return [::Class]
      def ruby_type
        ::DateTime
      end

      private

      def epoch_time(seconds)
        ::Time.at(seconds, in: 0)
      end

      def assemble(components, zone)
        from_time(time_from(components, zone))
      end

      def from_datetime(value)
        value
      end

      def from_date(value, zone)
        return from_time(zone.start_of_day(value.year, value.mon, value.mday)) if zone

        ::DateTime.new(value.year, value.mon, value.mday, 0, 0, 0, 0)
      end

      def from_time(value)
        ::DateTime.new(value.year, value.mon, value.mday, value.hour, value.min, value.sec + value.subsec,
                       Rational(value.utc_offset, 86_400))
      end
    end
  end
end
