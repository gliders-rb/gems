# frozen_string_literal: true

begin
  require 'mcp'
rescue LoadError
  raise LoadError, "actionable/tools/mcp needs the mcp gem: add `gem 'mcp', '~> 1.8'` to your Gemfile"
end
require 'actionable/tools'

module Actionable
  module Tools
    # Wraps a {Definition} as an +MCP::Tool+ subclass for the MCP Ruby SDK.
    module MCP
      # @return [::Hash{::Symbol=>::Symbol}] the annotation keys a tool takes, and the SDK keyword each maps to
      HINTS = {
        read_only: :read_only_hint,
        destructive: :destructive_hint,
        idempotent: :idempotent_hint,
        open_world: :open_world_hint
      }.freeze

      module_function

      # Builds the tool class of one action.
      #
      # @param action [Class] an +Actionable::Action+ subclass
      # @param options [Object] the keywords of {Tools.definition}
      # @return [Class] an +MCP::Tool+ subclass
      def tool(action, **options) # rubocop:disable Style/ArgumentsForwarding -- named so YARD/Sord document the keyword splat
        from(Tools.definition(action, **options)) # rubocop:disable Style/ArgumentsForwarding
      end

      # Builds the tool class of a definition.
      #
      # @param definition [Actionable::Tools::Definition]
      # @return [Class] an +MCP::Tool+ subclass
      # @raise [::ArgumentError] on an annotation key outside {HINTS}
      def from(definition)
        hints = annotations(definition.annotations)
        schemas = { input_schema: definition.input_schema, output_schema: definition.output_schema }
        label = { name: definition.name, description: definition.description, annotations: hints }
        ::MCP::Tool.define(**label, **schemas) do |server_context: nil, **args|
          envelope = definition.call(args, server_context)
          text = { type: 'text', text: Oj.dump(envelope, mode: :compat) }
          ::MCP::Tool::Response.new([text], error: definition.error?(envelope), structured_content: envelope)
        end
      end

      # Maps annotation hints to the SDK's keywords.
      #
      # @param hints [::Hash{::Symbol=>Boolean}]
      # @return [::Hash{::Symbol=>Boolean}, nil] nil when there are no hints
      # @raise [::ArgumentError] on an unknown key
      def annotations(hints)
        return nil if hints.empty?

        known = HINTS.keys
        stray = hints.keys.reject { |key| known.include?(key) }
        raise ArgumentError, "unknown annotations: #{stray.join(', ')} (known: #{known.join(', ')})" if stray.any?

        hints.each_with_object({}) { |(key, value), mapped| mapped[HINTS.fetch(key)] = value }
      end
    end
  end
end
