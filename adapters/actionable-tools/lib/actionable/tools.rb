# frozen_string_literal: true

require 'oj'
require 'actionable'
require 'field_struct/json_schema'

require_relative 'tools/version'
require_relative 'tools/input_schema'
require_relative 'tools/output_schema'
require_relative 'tools/envelope'
require_relative 'tools/definition'

# The actionable-rb namespace; this gem adds {Tools}.
module Actionable
  # Expose actions as LLM tools. {Tools.definition} builds the form-neutral description; {Tools::MCP} and
  # {Tools::RubyLLM} wrap it for the MCP Ruby SDK and RubyLLM (each loaded by its own require).
  module Tools
    # @return [Array<::String>] the keys of every result a tool call returns, in order
    RESULT_KEYS = %w[status code message output errors metadata].freeze

    module_function

    # Builds the tool description of one named action.
    #
    # @param action [Class] an +Actionable::Action+ subclass with an +input+ block
    # @param description [::String] what the tool does, written for a model
    # @param name [::String, nil] the tool name; defaults to the action's snake-cased class name
    # @param context [::Hash{::Symbol=>::Proc}] input fields the server fills in, each from a proc taking the source
    # @param annotations [::Hash{::Symbol=>Boolean}] behaviour hints (MCP: read_only, destructive, idempotent, open_world)
    # @return [Actionable::Tools::Definition]
    # @raise [::ArgumentError] when the action cannot be a tool
    def definition(action, description:, name: nil, context: {}, annotations: {})
      Definition.new(action, name: name, description: description, annotations: annotations, context: context)
    end
  end
end
