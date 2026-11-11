# frozen_string_literal: true

module FieldStruct
  # Per-field validation messages. A plain value object; keys are Symbols.
  class Errors
    def initialize
      @messages = {}
    end

    # @param field [Symbol, String]
    # @return [Array<String>] the field's messages, or a throwaway empty Array
    def [](field)
      @messages.fetch(field.to_sym) { [] }
    end

    # Appends a message for a field.
    #
    # @param field [Symbol, String]
    # @param message [String]
    # @return [Array<String>] the field's messages
    def add(field, message)
      (@messages[field.to_sym] ||= []) << message
    end

    # Removes all messages for a field.
    #
    # @param field [Symbol, String]
    # @return [nil]
    def clear(field)
      @messages.delete(field.to_sym)
      nil
    end

    # @return [Boolean] true when no field has a message
    def empty?
      @messages.each_value { |messages| return false unless messages.empty? }
      true
    end

    # @return [Hash{Symbol=>Array<String>}] only fields that have messages
    def to_h
      present.transform_values(&:dup)
    end

    # Same as {#to_h}.
    #
    # @return [Hash{Symbol=>Array<String>}]
    def messages
      to_h
    end

    # @return [Array<String>] humanized field name plus message; +:base+ is unprefixed
    def full_messages
      present.flat_map do |field, messages|
        field == :base ? messages.dup : messages.map { |message| "#{humanize(field)} #{message}" }
      end
    end

    # @return [String]
    def inspect
      pairs = present.map { |field, messages| "#{field}=#{messages.inspect}" }
      "#<#{FieldStruct.inspect_namespace}::Errors #{pairs.empty? ? 'empty' : pairs.join(' ')}>"
    end

    private

    def initialize_copy(source)
      super
      @messages = source.instance_variable_get(:@messages).transform_values(&:dup)
    end

    def present
      @messages.reject { |_field, messages| messages.empty? }
    end

    def humanize(field)
      text = field.to_s.tr('_', ' ')
      text.empty? ? text : text[0].upcase + text[1..]
    end
  end
end
