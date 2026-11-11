# frozen_string_literal: true

module FieldStruct
  # The value checks a field's +format:+ (Regexp), +enum:+ and +in:+ options describe.
  module Restrictions
    # @param value [Object] an already coerced value
    # @param options [Hash{Symbol=>Object}] the field's (or element's) options
    # @return [Boolean] true when any restriction is broken; +nil+ never breaks one
    def self.violated?(value, options)
      return false if value.nil?

      format_broken?(value, options[:format]) || enum_broken?(value, options[:enum]) || range_broken?(value, options[:in])
    end

    def self.format_broken?(value, format)
      format.is_a?(::Regexp) && !format.match?(value.to_s)
    end

    def self.enum_broken?(value, enum)
      !enum.nil? && !enum.include?(value)
    end

    def self.range_broken?(value, bounds)
      return false if bounds.nil?

      bounds.is_a?(::Range) ? !bounds.cover?(comparable(value, bounds)) : !bounds.include?(value)
    end

    # A DateTime compared with plain Date endpoints counts as its calendar date, so 15:00 on the last day is inside.
    def self.comparable(value, range)
      return value unless value.is_a?(::DateTime)

      plain_date = ->(endpoint) { endpoint.is_a?(::Date) && !endpoint.is_a?(::DateTime) }
      plain_date.call(range.begin) || plain_date.call(range.end) ? ::Date.new(value.year, value.mon, value.mday) : value
    end

    private_class_method :format_broken?, :enum_broken?, :range_broken?, :comparable
  end
end
