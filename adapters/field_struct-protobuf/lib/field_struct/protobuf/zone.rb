# frozen_string_literal: true

module FieldStruct
  module Protobuf
    # Puts a decoded time back in the field's +zone:+ (PB-B53); a Timestamp carries no offset.
    module Zone
      module_function

      # @param time [::Time] a UTC time
      # @param zone [::Object] the field's +zone:+; anything but a String leaves the time in UTC
      # @return [::Time] a new Time at the same instant
      def apply(time, zone)
        case zone
        when ::String
          return time.getutc if zone == 'UTC'
          return time.getlocal(zone) unless zone.include?('/')

          require 'tzinfo'
          seconds = TZInfo::Timezone.get(zone).period_for_utc(time.getutc).utc_total_offset
          time.getlocal(seconds)
        else
          time
        end
      end
    end
  end
end
