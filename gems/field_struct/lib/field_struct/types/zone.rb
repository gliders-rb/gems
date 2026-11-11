# frozen_string_literal: true

module FieldStruct
  module Types
    # INTERNAL. A resolved +zone:+ declaration: UTC, a fixed offset or an IANA zone (tzinfo, required on first use).
    # Hands back plain Time objects; they do not carry the zone (FS-B99).
    class Zone
      FIXED_OFFSET = /\A([+-])([01]\d|2[0-3]):([0-5]\d)\z/
      RAILS_NAME = /[\s()&]/
      SHAPE = 'an IANA name like "America/Denver", "UTC" or a UTC offset like "-06:00"'
      GENERIC_HINT = 'Use an Area/Location name: abbreviations and aliases are refused ("MST" is a fixed -07:00 in the zone ' \
                     'database, not Mountain time with DST), and an offset needs its colon.'
      RAILS_HINT = 'Rails zone names are an ActiveSupport alias, not IANA names, and exist only when ActiveSupport is loaded: ' \
                   'use the name it maps to (ActiveSupport::TimeZone::MAPPING[name]).'
      UNKNOWN_HINT = 'The zone database has no zone by that name.'

      @cache = {}
      @lock = Mutex.new

      class << self
        # Declaration-time validation.
        #
        # @param name [::String]
        # @param label [::String] the type's short name, used in the message
        # @return [void]
        # @raise [ArgumentError] when the name is not UTC, a "+-HH:MM" offset or a known IANA name
        def check!(name, label)
          return if name == 'UTC' || FIXED_OFFSET.match?(name)

          hint = GENERIC_HINT
          if name.include?('/') && !RAILS_NAME.match?(name)
            return if iana_known?(name, label)

            hint = UNKNOWN_HINT
          elsif RAILS_NAME.match?(name)
            hint = RAILS_HINT
          end
          raise ::ArgumentError, "zone: on #{label} expects #{SHAPE}, got #{name.inspect}. #{hint}"
        end

        # @param name [::String] a name that passed {.check!}
        # @return [FieldStruct::Types::Zone] cached per name
        def fetch(name)
          @lock.synchronize { @cache[name] ||= new(name) }
        end

        private

        def iana_known?(name, label)
          require 'tzinfo'
          TZInfo::Timezone.get(name)
          true
        rescue TZInfo::InvalidTimezoneIdentifier
          false
        rescue TZInfo::DataSourceNotFound
          raise ::ArgumentError, "zone: on #{label} names #{name.inspect}, but no time zone data was found on this system. " \
                                 'Add the tzinfo-data gem to your Gemfile (or install the OS zoneinfo package).'
        end
      end

      # @return [::String]
      attr_reader :name

      # @param name [::String]
      def initialize(name)
        @name = name
        match = FIXED_OFFSET.match(name)
        @fixed = if match
                   (match[1] == '-' ? -1 : 1) * ((match[2].to_i * 3600) + (match[3].to_i * 60))
                 end
        @utc = name == 'UTC'
        load_iana unless @utc || @fixed
      end

      # The wall clock in this zone as a Time with the zone's offset at that moment.
      #
      # @param wall [::Array<::Numeric>] year, month, day, hour, minute, second
      # @return [::Time]
      # @raise [ArgumentError] when a daylight-saving change skips that wall time
      def time_at_local(*wall)
        return ::Time.utc(*wall) if @utc
        return ::Time.new(*wall, @fixed) if @fixed

        periods = @tz.periods_for_local(::Time.utc(*wall))
        raise ::ArgumentError, "names a local time that does not exist in #{name} (skipped by a daylight-saving change)" if periods.empty?

        ::Time.new(*wall, (periods.find(&:dst?) || periods.first).observed_utc_offset)
      end

      # @param seconds [::Numeric] seconds since the epoch
      # @return [::Time] that instant, shown at this zone's offset then
      def time_at_epoch(seconds)
        return ::Time.at(seconds).utc if @utc
        return ::Time.at(seconds, in: @fixed) if @fixed

        ::Time.at(seconds, in: @tz.period_for_utc(::Time.at(seconds).utc).observed_utc_offset)
      end

      # @return [::Time] midnight of that day here, or the first moment of the day if midnight is skipped
      def start_of_day(year, mon, mday)
        time_at_local(year, mon, mday, 0, 0, 0)
      rescue ::ArgumentError
        (1..23).each do |hour|
          periods = @tz.periods_for_local(::Time.utc(year, mon, mday, hour, 0, 0))
          return time_at_epoch(periods.last.starts_at.to_i) unless periods.empty?
        end
        raise
      end

      private

      def load_iana
        require 'tzinfo'
        @tz = TZInfo::Timezone.get(name)
      end
    end
  end
end
