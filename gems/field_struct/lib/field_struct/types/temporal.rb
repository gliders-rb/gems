# frozen_string_literal: true

module FieldStruct
  module Types
    # INTERNAL base of +:date+, +:time+ and +:datetime+. Dispatches on explicit stdlib classes only and parses through
    # the stdlib class methods, never through anything ActiveSupport redefines (FS-I6). Refuses rather than guesses (FS-I12).
    class Temporal < Base
      # Zone names read as UTC.
      # @return [::Array<::String>]
      UTC_TEXT = %w[Z UTC GMT UT].freeze
      # Message tail for a zone name with no fixed offset.
      # @return [::String]
      NO_FIXED_OFFSET = 'names a time zone with no fixed offset, which zone: does not override'

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}] +format+, +in+ and (time family) +zone+
        def own_option_schema
          format_option = option(type: [::String, ::Symbol], presets: presets.keys)
          range_option = option(type: [::Array, ::Range])
          return { format: format_option, in: range_option } unless zoned?

          { format: format_option, in: range_option, zone: option(type: ::String) }
        end

        # @return [nil] temporal types prefill +format: nil+ (FS-B7)
        def default_format
          nil
        end

        # @return [::Hash{::Symbol=>::Object}] preset name to strptime String (or RFC 3339 format object)
        def presets
          {}
        end

        # @return [Boolean] whether the type takes +zone:+
        def zoned?
          false
        end

        # Checks the preset name and the zone at declaration; the declared +format:+ is kept as written (FS-B15).
        #
        # @param options [::Hash{::Symbol=>::Object}]
        # @return [::Hash{::Symbol=>::Object}] the same options
        # @raise [ArgumentError] for an unknown preset or an invalid zone
        def resolve_options(options, **)
          PresetResolver.call(options, :format, presets, label: "#{preset_caption} format")
          Zone.check!(options[:zone], short_name) if options[:zone]
          options
        end

        # @param value [::Date, ::DateTime, ::Time]
        # @return [::String] the fraction digits of the sub-second part, to nanoseconds, trailing zeros trimmed ('' when none)
        def fraction_digits(value)
          subsec = value.is_a?(::DateTime) ? value.sec_fraction : value.subsec
          nanos = (subsec * 1_000_000_000).floor
          nanos.zero? ? '' : format('%09d', nanos).sub(/0+\z/, '')
        end

        # @return [::String] how preset errors name the type
        def preset_caption
          short_name.downcase
        end
      end

      # @param value [::Object] nil, a String, a Date, DateTime or Time
      # @param format [::String, ::Symbol, nil] a strptime String or preset name
      # @param zone [::String, nil] what a zone-less string means
      # @return [::Date, ::Time, ::DateTime, nil]
      # @raise [ArgumentError] for anything refused
      def coerce(value, format: nil, zone: nil, **)
        return nil if value.nil?

        spec = format_spec(format)
        zone_object = zone && Zone.fetch(zone)
        case value
        when ::String then from_string(value, spec, zone_object)
        when ::DateTime then from_datetime(value)
        when ::Date then from_date(value, zone_object)
        when ::Time then from_time(value)
        else raise ::ArgumentError, "expected a String, Date, DateTime or Time, got #{value.class}"
        end
      end

      # Renders a value the way +as_json+ writes it: by +format:+ (RFC 3339 preset, strftime String) or ISO 8601.
      #
      # @param value [::Date, ::DateTime, ::Time]
      # @param format [::String, ::Symbol, nil]
      # @return [::String]
      def render(value, format: nil, **)
        spec = format_spec(format)
        case spec
        when nil then iso8601(value)
        when ::String then value.strftime(spec)
        else spec.render(value)
        end
      end

      private

      def iso8601(value)
        return value.iso8601 if value.is_a?(::Date) && !value.is_a?(::DateTime)

        value.iso8601(self.class.fraction_digits(value).length)
      end

      def format_spec(format)
        return format unless format.is_a?(::Symbol)

        self.class.presets.fetch(format) do
          raise ::ArgumentError, "unknown #{self.class.preset_caption} format preset #{format.inspect}. " \
                                 "Available: #{self.class.presets.keys.inspect}"
        end
      end

      def from_string(text, spec, zone)
        components = case spec
                     when Rfc3339Format then spec.parse(text)
                     when ::String then strptime_components(text, spec, zone)
                     else free_components(text, zone)
                     end
        components[:epoch] ? from_epoch(components[:epoch], zone) : assemble(components, zone)
      end

      # No format: the string must name a whole, existing day (FS-B87).
      def free_components(text, zone)
        parts = ::Date._parse(text)
        raise ::ArgumentError, 'expected a date with a year, a month and a day' unless parts[:year] && parts[:mon] && parts[:mday]
        raise ::ArgumentError, 'invalid date' unless ::Date.valid_date?(parts[:year], parts[:mon], parts[:mday])

        time_parts(parts).merge(year: parts[:year], mon: parts[:mon], mday: parts[:mday], offset: offset_of(parts, zone))
      end

      # A declared format anchors: the whole string must match (FS-B88).
      def strptime_components(text, format, zone)
        parts = strptime(text, format)
        return { epoch: parts[:seconds] } if parts[:seconds]

        time_parts(parts).merge(date_parts(parts, zone)).merge(offset: offset_of(parts, zone))
      end

      def strptime(text, format)
        parts = ::Date._strptime(text, format) unless text.match?(/\A\s/) && !format.match?(/\A\s/)
        raise ::ArgumentError, "does not match format #{format.inspect}" if parts.nil?
        raise ::ArgumentError, "does not match format #{format.inspect} — unexpected trailing characters" if parts[:leftover]

        parts
      end

      def date_parts(parts, zone)
        today = today_in(zone)
        if parts[:yday] && !parts[:mon] && !parts[:mday]
          year = parts[:year] || today[0]
          raise ::ArgumentError, 'invalid date' unless ::Date.valid_ordinal?(year, parts[:yday])

          day = ::Date.ordinal(year, parts[:yday])
          return { year: day.year, mon: day.mon, mday: day.mday }
        end
        year, mon, mday = fill_date(parts.values_at(:year, :mon, :mday), today)
        raise ::ArgumentError, 'invalid date' unless ::Date.valid_date?(year, mon, mday)

        { year: year, mon: mon, mday: mday }
      end

      # Units above the most significant written one come from today, units below it start at 1.
      def fill_date(given, today)
        first = given.index { |unit| !unit.nil? }
        return today if first.nil?

        given.each_with_index.map { |unit, index| unit || (index < first ? today[index] : 1) }
      end

      def today_in(zone)
        now = zone ? zone.time_at_epoch(::Time.now.to_r) : ::Time.now
        [now.year, now.mon, now.mday]
      end

      def time_parts(parts)
        hour, min, sec = parts.values_at(:hour, :min, :sec).map { |unit| unit || 0 }
        raise ::ArgumentError, 'invalid time of day' if hour > 23 || min > 59 || sec > 59

        { hour: hour, min: min, sec: sec, subsec: parts[:sec_fraction] || 0 }
      end

      # The offset a string carries: :utc for Z/UTC/GMT, seconds for others, nil for none.
      def offset_of(parts, zone)
        if parts[:offset]
          return UTC_TEXT.include?(parts[:zone].to_s.upcase) ? :utc : parts[:offset]
        end
        raise ::ArgumentError, NO_FIXED_OFFSET if parts[:zone] && zone

        nil
      end

      # A plain Time for string components: an offset the string carries wins, then the declared zone, then the default.
      def time_from(components, zone)
        args = components.values_at(:year, :mon, :mday, :hour, :min)
        args << (components[:sec] + components[:subsec])
        case (offset = components[:offset])
        when :utc then ::Time.utc(*args)
        when ::Integer then ::Time.new(*args, offset)
        else zone ? zone.time_at_local(*args) : default_time(*args)
        end
      end

      def default_time(*)
        ::Time.utc(*)
      end

      def from_epoch(seconds, zone)
        from_time(zone ? zone.time_at_epoch(seconds) : epoch_time(seconds))
      end

      def epoch_time(seconds)
        ::Time.at(seconds)
      end
    end
  end
end
