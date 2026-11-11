# frozen_string_literal: true

module Actionable
  # Picks an input schema at run time from the value of one keyword.
  class InputDispatch
    # The DSL block of +input_for+.
    class Builder
      # @return [Array<Array(Object, Class)>] +[match_value, schema]+ pairs in declaration order
      attr_reader :branches

      # @return [Class, nil]
      attr_reader :default_schema

      def initialize
        @branches = []
        @default_schema = nil
      end

      # @param match_value [Object] matched with {ValueMatch.matches?}; an Array is ONE branch
      # @param schema [Class]
      # @return [void]
      def on(match_value, schema)
        @branches.push([match_value, schema])
      end

      # @param schema [Class]
      # @return [void]
      def default(schema)
        @default_schema = schema
      end
    end

    # @param discriminator [Symbol, String]
    # @yield evaluated with a {Builder} as +self+
    # @return [InputDispatch]
    def self.define(discriminator, &block)
      recorder = Builder.new
      recorder.instance_eval(&block) if block
      new(discriminator.to_sym, recorder.branches, recorder.default_schema)
    end

    # @return [Symbol]
    attr_reader :discriminator

    # @return [Array<Array(Object, Class)>]
    attr_reader :branches

    # @return [Class, nil]
    attr_reader :default_schema

    # @param discriminator [Symbol] the keyword that picks the schema
    # @param branches [Array<Array(Object, Class)>]
    # @param default_schema [Class, nil]
    def initialize(discriminator, branches, default_schema)
      @discriminator = discriminator
      @branches = branches.freeze
      @default_schema = default_schema
    end

    # @param value [Object] the discriminator value
    # @return [Class, nil] the first matching branch's schema, else the default
    def schema_for(value)
      hit = @branches.detect { |candidate, _| ValueMatch.matches?(candidate, value) }
      hit.nil? ? @default_schema : hit[1]
    end

    # @return [Array<Object>] the branch match values in order (the default is not included)
    def variants
      @branches.collect(&:first)
    end

    # @return [Array<Class>] every reachable schema: branches in order, then the default, de-duplicated
    def schemas
      @branches.collect(&:last).push(@default_schema).compact.uniq
    end
  end
end
