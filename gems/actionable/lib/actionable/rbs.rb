# frozen_string_literal: true

require_relative 'rbs/lines'
require_relative 'rbs/names'
require_relative 'rbs/typed_section'
require_relative 'rbs/action_body'

module Actionable
  # Writes RBS for one of your actions, from its input and output schemas (AC-B#rbsargs to AC-B#rbsformat).
  # Inside +module Actionable+, +RBS+ means this module; the RBS gem is +::RBS+.
  module RBS
    class << self
      # Builds the signature text for one action: its named ancestors (empty declarations that merge across files),
      # then the action with its +run+, input, instance variables, code aliases and result types.
      #
      # @param klass [Class] a named subclass of +Actionable::Action+
      # @return [::String] RBS source ending in a newline
      # @raise [::ArgumentError] for anything else, an anonymous action, or an +InputSchema+ constant already in use
      def generate(klass)
        check_class!(klass)
        check_input_constant!(klass)
        blocks = ancestor_chain(klass).map { |ancestor| declaration(ancestor, Lines.result_classes(ancestor, Names.base_of(ancestor))) }
        blocks << declaration(klass, ActionBody.new(klass, Names.base_of(klass)).lines)
        "#{blocks.map { |lines| lines.join("\n") }.join("\n\n")}\n"
      end

      private

      def check_class!(klass)
        unless klass.is_a?(::Class) && klass < Actionable::Action
          raise ::ArgumentError, "Actionable::RBS.generate expects an Actionable::Action subclass, got #{klass.inspect}"
        end
        raise ::ArgumentError, 'cannot generate RBS for an anonymous action' if klass.name.nil?
      end

      # +InputSchema+ exists only in the RBS; a real constant of that name (not a top-level one) would clash with it.
      def check_input_constant!(klass)
        return if klass.input_schema.nil? || klass.input_dispatch

        owner = klass.ancestors.find { |ancestor| !::Object.ancestors.include?(ancestor) && ancestor.const_defined?(:InputSchema, false) }
        return unless owner

        raise ::ArgumentError, "#{klass.name}::InputSchema is already defined (in #{owner.name}); Actionable::RBS.generate " \
                               'names the generated input type InputSchema, so rename that constant'
      end

      # Named ancestors between +klass+ and +Action+, outermost first.
      def ancestor_chain(klass)
        klass.ancestors.drop(1).select { |ancestor| ancestor.is_a?(::Class) && ancestor < Actionable::Action && ancestor.name }.reverse
      end

      def declaration(klass, members)
        header = "class #{klass.name.split('::').last} < #{Names.superclass_name(klass)}"
        wrap(klass.name.split('::'), [header, *Lines.indent(members), 'end'])
      end

      def wrap(segments, lines)
        segments[0...-1].each_with_index.reverse_each.reduce(lines) do |body, (segment, depth)|
          ["#{keyword(segments[0..depth])} #{segment}", *Lines.indent(body), 'end']
        end
      end

      def keyword(path)
        ::Object.const_get(path.join('::')).is_a?(::Class) ? 'class' : 'module'
      rescue ::NameError
        'module'
      end
    end

    private_constant :Lines, :Names, :ActionBody, :TypedSection
  end
end
