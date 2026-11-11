# frozen_string_literal: true

module FieldStruct
  module Avro
    # Puts a decoded time back in the field's +zone:+ (AV-B26); Avro times carry no offset and the avro gem returns UTC.
    module Zone
      module_function

      # @param time [::Object] a Time; anything else is returned as given
      # @param zone [::Object] the field's +zone:+; anything but a String leaves the time as it is
      # @return [::Object] a new Time at the same instant
      def apply(time, zone)
        return time unless time.is_a?(::Time) && zone.is_a?(::String)
        return time.getutc if zone == 'UTC'
        return time.getlocal(zone) unless zone.include?('/')

        require 'tzinfo'
        offset = TZInfo::Timezone.get(zone).period_for_utc(time.getutc).utc_total_offset
        time.getlocal(offset)
      end
    end
  end
end
