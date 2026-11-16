# frozen_string_literal: true

module FieldStruct
  # The value checks a field's +format:+ (Regexp), +enum:+, +in:+ and +length:+ options describe.
  module Restrictions
    # The one message a broken restriction gives: the +length:+ message wins (FS-B37a), else +"is invalid"+.
    #
    # @param value [Object] an already coerced value
    # @param options [Hash{Symbol=>Object}] the field's (or element's) options
    # @return [String, nil] +nil+ when nothing is broken; +nil+ never breaks a restriction
    def self.problem(value, options)
      return nil if value.nil?

      too = size_message(value, options)
      too || ('is invalid' if format_broken?(value, options[:format]) || enum_broken?(value, options[:enum]) ||
                              range_broken?(value, options[:in]))
    end

    # The specific message for a value outside its +length:+ bounds (FS-B37a). It names the declared limit, never the value.
    #
    # @param value [String] an already coerced value
    # @param bounds [Range, nil] the field's +length:+
    # @return [String, nil] +nil+ when there is no bound or the value is within it
    # +length:+ on a String, +max_items:+ on an Array (FS-B168), or nil.
    def self.size_message(value, options)
      return length_message(value, options[:length]) if value.is_a?(::String)

      limit = options[:max_items]
      "has too many items (maximum is #{limit})" if limit && value.is_a?(::Array) && value.size > limit
    end

    def self.length_message(value, bounds)
      return nil if bounds.nil?

      size = value.length
      min = bounds.begin
      return "is too short (minimum is #{min})" if min && size < min

      max = length_max(bounds)
      "is too long (maximum is #{max})" if max && size > max
    end

    # @param bounds [Range]
    # @return [Boolean] whether each end is an Integer >= 0 or nil, at least one is set, and the Range is not empty
    def self.usable_length?(bounds)
      return false unless whole_ends?(bounds)

      max = length_max(bounds)
      bounds.begin.nil? || max.nil? || bounds.begin <= max
    end

    # @param bounds [Range]
    # @return [Boolean] each end is an Integer >= 0 or nil, and at least one is set
    def self.whole_ends?(bounds)
      ends = [bounds.begin, bounds.end]
      ends.all? { |n| n.nil? || (n.is_a?(::Integer) && n >= 0) } && ends.any?
    end

    # @param bounds [Range]
    # @return [Integer, nil] the largest allowed length; an exclusive end allows one less
    def self.length_max(bounds)
      last = bounds.end
      last && bounds.exclude_end? ? last - 1 : last
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

    private_class_method :format_broken?, :enum_broken?, :range_broken?, :comparable, :length_max, :whole_ends?
  end
end
