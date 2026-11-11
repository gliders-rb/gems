# frozen_string_literal: true

module FieldStruct
  module Types
    # An instant with an offset. A zone-less string lands in the process zone, or in +zone:+ when declared.
    class Time < Temporal
      # Named formats the +format:+ option accepts (strptime Strings, or the RFC 3339 reader).
      # @return [::Hash{::Symbol=>::Object}]
      PRESETS = { iso8601: Rfc3339Format::TIMESTAMP, rfc2822: '%a, %d %b %Y %H:%M:%S %z', db: '%Y-%m-%d %H:%M:%S' }.freeze

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
        ::Time
      end

      private

      def default_time(*)
        ::Time.local(*)
      end

      def assemble(components, zone)
        time_from(components, zone)
      end

      def from_datetime(value)
        ::Time.new(value.year, value.mon, value.mday, value.hour, value.min, value.sec + value.sec_fraction,
                   (value.offset * 86_400).to_i)
      end

      def from_date(value, zone)
        zone ? zone.start_of_day(value.year, value.mon, value.mday) : ::Time.local(value.year, value.mon, value.mday)
      end

      def from_time(value)
        return value if value.instance_of?(::Time)

        rebuilt = ::Time.at(value.to_r)
        value.utc? ? rebuilt.utc : rebuilt.localtime(value.utc_offset)
      end
    end
  end
end
