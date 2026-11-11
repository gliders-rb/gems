# frozen_string_literal: true

module Actionable
  # Abstract base of the three outcomes. A FieldStruct, so equality, pattern matching and errors are FieldStruct's.
  class Result < FieldStruct::Base
    # Which output fields a run actually set (Array of Symbols), or nil for a hand-built result.
    # @return [Array<Symbol>, nil]
    attr_accessor :output_fields_set

    # @return [Boolean]
    def success? = false

    # @return [Boolean]
    def failure? = false

    # @return [Boolean]
    def skipped? = false

    # @return [Boolean] same as {#success?}
    def successful? = success?

    # @return [Boolean] same as {#failure?}
    def failed? = failure?

    # @return [Boolean] true unless this is a failure
    def ok?
      !failure?
    end

    required :code, :symbol
    optional :message, :string
    optional :output, :value, default: -> { {} }
    optional :history, :value, default: -> { [] }

    # @return [Symbol] +:success+, +:skipped+ or +:failure+
    def status
      if success? then :success
      elsif skipped? then :skipped
      else :failure
      end
    end

    # @return [Hash{Symbol=>Object}] code, message, output, history and errors as plain data
    def to_h
      {
        code: code,
        message: message,
        output: output_hash,
        history: history_data,
        errors: errors.to_h
      }
    end

    # @param index [Integer, nil]
    # @param id_field [Symbol]
    # @return [Hash{Symbol=>Object}] +{index:, status:, id:, errors:}+
    def to_api_h(index: nil, id_field: :id)
      { index: index, status: status, id: output_id(id_field), errors: errors.to_h }
    end

    # @return [String] +#<Class name=value ...>+, sorted by name
    def inspect
      pairs = attribute_names.map { |name| [name.to_s, public_send(name).inspect] }
      pairs << ['errors', errors.to_h.inspect]
      "#<#{self.class.inspect} #{pairs.sort_by(&:first).map { |name, value| "#{name}=#{value}" }.join(' ')}>"
    end

    alias to_s inspect

    # Copies every message of +source.errors+ onto this result, one at a time.
    #
    # @param source [::FieldStruct::Base] a FieldStruct or another result (anything whose +errors+ answers +to_h+ works)
    # @return [self]
    def absorb_errors_from(source)
      source.errors.to_h.each do |field, messages|
        messages.each { |message| errors.add(field, message) }
      end
      self
    end

    # Names of every public Result method (the reserved output field names, AC-B#reservedout).
    #
    # @return [Array<Symbol>]
    def self.reserved_method_names
      [self, Success, Failure, Skipped].flat_map(&:public_instance_methods).uniq
    end

    # Whether this class was generated for an action by typed outcomes (AC-B#resultclasses).
    #
    # @return [Boolean]
    def self.generated?
      instance_variable_defined?(:@actionable_owner)
    end

    # The class to rebuild a result as when it leaves its action: this class, or the first ancestor that was not
    # generated for an action (the gem class, or a host's own subclass).
    #
    # @return [Class]
    def self.plain_class
      klass = self
      klass = klass.superclass while klass.generated?
      klass
    end

    private

    def method_missing(name, *args, &block)
      return output.public_send(name) if args.empty? && output_field?(name)

      super
    end

    def respond_to_missing?(name, include_private = false)
      output_field?(name) || super
    end

    def output_field?(name)
      output.is_a?(FieldStruct::Base) && output.class.attribute_names.include?(name.to_sym)
    end

    def output_hash
      output.respond_to?(:to_h) ? output.to_h : output
    end

    def history_data
      history.is_a?(History) ? history.as_json : history
    end

    def output_id(field)
      case output
      when FieldStruct::Base then output_field?(field) ? output.public_send(field) : nil
      when Hash then output[field]
      end
    end
  end

  # A run that achieved its goal.
  class Success < Result
    required :code, :symbol, default: :success

    # @return [Boolean]
    def success? = true
  end

  # A run that failed; carries declared metadata.
  class Failure < Result
    required :code, :symbol, default: :error
    optional :metadata, :value, default: -> { {} }

    # @return [Boolean]
    def failure? = true

    # @return [Hash{Symbol=>Object}] {Result#to_h} plus +metadata+
    def to_h
      super.merge(metadata: metadata)
    end
  end

  # A run with nothing to do; not an error, not a success.
  class Skipped < Result
    required :code, :symbol, default: :skipped
    optional :metadata, :value, default: -> { {} }

    # @return [Boolean]
    def skipped? = true

    # @return [Hash{Symbol=>Object}] {Result#to_h} plus +metadata+
    def to_h
      super.merge(metadata: metadata)
    end
  end
end
