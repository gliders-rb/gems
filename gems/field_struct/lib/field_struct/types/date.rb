# frozen_string_literal: true

module FieldStruct
  module Types
    # A calendar date. Strings must name a whole, existing day; a declared +format:+ anchors.
    class Date < Temporal
      # Named formats the +format:+ option accepts (strptime Strings, or the RFC 3339 reader).
      # @return [::Hash{::Symbol=>::Object}]
      PRESETS = { iso8601: Rfc3339Format::DATE, us: '%m/%d/%Y', eu: '%d/%m/%Y' }.freeze

      class << self
        # @return [::Hash{::Symbol=>::Object}] +iso8601+ (RFC 3339), +us+ and +eu+
        def presets
          PRESETS
        end
      end

      # @return [::Class]
      def ruby_type
        ::Date
      end

      private

      # A date ignores time-of-day text.
      def time_parts(_parts)
        {}
      end

      def assemble(components, _zone)
        ::Date.new(components[:year], components[:mon], components[:mday])
      end

      def from_datetime(value)
        ::Date.new(value.year, value.mon, value.mday)
      end
      alias from_time from_datetime

      def from_date(value, _zone)
        value.instance_of?(::Date) ? value : from_datetime(value)
      end
    end
  end
end
