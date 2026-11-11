# frozen_string_literal: true

module FieldStruct
  module Types
    # INTERNAL. The RFC 3339 reader and writer behind +format: :iso8601+, in a date variant and a timestamp
    # variant. Strict by design (FS-B90): the stdlib's ISO 8601 parsers disagree with each other and one rolls 30 February forward.
    class Rfc3339Format
      DATE_PATTERN = /\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/
      TIMESTAMP_PATTERN = /
        \A([0-9]{4})-([0-9]{2})-([0-9]{2})
        [Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})
        (?:\.([0-9]+))?
        (?:([Zz])|([+-])([0-9]{2}):?([0-9]{2}))\z
      /x

      # @return [::Symbol] +:date+ or +:timestamp+
      attr_reader :kind

      # @param kind [::Symbol] +:date+ or +:timestamp+
      def initialize(kind)
        @kind = kind
        freeze
      end

      # The date-only variant.
      DATE = new(:date)
      # The timestamp variant.
      TIMESTAMP = new(:timestamp)

      # @param text [::String]
      # @return [::Hash{::Symbol=>::Object}] components: +year mon mday+ and, for a timestamp, +hour min sec subsec offset+
      #   (+offset+ in seconds, +Z+ being a fixed 0)
      # @raise [ArgumentError] with the documented messages
      def parse(text)
        match = (kind == :date ? DATE_PATTERN : TIMESTAMP_PATTERN).match(text)
        raise ::ArgumentError, "expected an RFC 3339 #{kind}" unless match

        components = kind == :date ? date_components(match) : timestamp_components(match)
        check_day(components)
        components
      end

      # @param value [::Date, ::DateTime, ::Time]
      # @return [::String] +YYYY-MM-DD+ or +YYYY-MM-DDThh:mm:ss[.f]Z|+-hh:mm+
      def render(value)
        date = format('%<y>04d-%<m>02d-%<d>02d', y: value.year, m: value.mon, d: value.mday)
        return date if kind == :date || (value.is_a?(::Date) && !value.is_a?(::DateTime))

        "#{date}T#{format('%<h>02d:%<i>02d:%<s>02d', h: value.hour, i: value.min, s: value.sec)}" \
          "#{fraction_text(value)}#{offset_text(value)}"
      end

      private

      def date_components(match)
        { year: match[1].to_i, mon: match[2].to_i, mday: match[3].to_i }
      end

      def timestamp_components(match)
        hour = match[4].to_i
        min = match[5].to_i
        sec = match[6].to_i
        raise ::ArgumentError, 'invalid time of day' if hour > 23 || min > 59 || sec > 59

        { year: match[1].to_i, mon: match[2].to_i, mday: match[3].to_i, hour: hour, min: min, sec: sec,
          subsec: match[7] ? Rational(match[7].to_i, 10**match[7].length) : 0, offset: offset_seconds(match) }
      end

      def offset_seconds(match)
        return 0 if match[8]

        hours = match[10].to_i
        minutes = match[11].to_i
        raise ::ArgumentError, 'invalid UTC offset' if hours > 23 || minutes > 59

        (match[9] == '-' ? -1 : 1) * ((hours * 3600) + (minutes * 60))
      end

      def check_day(components)
        return if ::Date.valid_date?(components[:year], components[:mon], components[:mday])

        raise ::ArgumentError, 'invalid date'
      end

      def fraction_text(value)
        digits = Temporal.fraction_digits(value)
        return '' if digits.empty?

        ".#{digits}"
      end

      def offset_text(value)
        seconds = value.is_a?(::DateTime) ? (value.offset * 86_400).to_i : value.utc_offset
        return 'Z' if seconds.zero?

        minutes = seconds.abs / 60
        format('%<sign>s%<h>02d:%<m>02d', sign: seconds.negative? ? '-' : '+', h: minutes / 60, m: minutes % 60)
      end
    end
  end
end
