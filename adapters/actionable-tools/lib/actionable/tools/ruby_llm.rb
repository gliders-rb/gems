# frozen_string_literal: true

begin
  require 'ruby_llm'
rescue LoadError
  raise LoadError, "actionable/tools/ruby_llm needs the ruby_llm gem: add `gem 'ruby_llm', '~> 2.1'` to your Gemfile"
end
require 'actionable/tools'

module Actionable
  module Tools
    # Wraps a {Definition} as a +RubyLLM::Tool+ subclass.
    module RubyLLM
      module_function

      # Builds the tool class of one action.
      #
      # @param action [Class] an +Actionable::Action+ subclass
      # @param approval [Boolean] true makes the chat pause for a decision before the tool runs
      # @param options [Object] the keywords of {Tools.definition}
      # @return [Class] a +RubyLLM::Tool+ subclass; construct it with the source handed to the context procs
      def tool(action, approval: false, **options) # rubocop:disable Style/ArgumentsForwarding -- named for YARD/Sord
        from(Tools.definition(action, **options), approval: approval) # rubocop:disable Style/ArgumentsForwarding
      end

      # Builds the tool class of a definition.
      #
      # @param definition [Actionable::Tools::Definition]
      # @param approval [Boolean]
      # @return [Class] a +RubyLLM::Tool+ subclass
      def from(definition, approval: false)
        klass = Class.new(::RubyLLM::Tool)
        klass.description(definition.description)
        klass.parameters(definition.input_schema)
        klass.requires_approval if approval
        klass.define_singleton_method(:tool_name) { definition.name }
        klass.class_exec do
          def initialize(source = nil)
            super()
            @source = source
          end
        end
        klass.define_method(:execute) { |**args| definition.call(args, @source) }
        klass
      end
    end
  end
end
