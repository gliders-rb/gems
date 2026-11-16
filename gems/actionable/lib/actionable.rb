# frozen_string_literal: true

require 'oj'
require 'time'
require 'field_struct'

require_relative 'actionable/version'
require_relative 'actionable/errors'
require_relative 'actionable/value_match'
require_relative 'actionable/registry'
require_relative 'actionable/history'
require_relative 'actionable/measurement'
require_relative 'actionable/result'
require_relative 'actionable/batch_result'
require_relative 'actionable/step_options'
require_relative 'actionable/steps'
require_relative 'actionable/runner'
require_relative 'actionable/schema_builder'
require_relative 'actionable/input_dispatch'
require_relative 'actionable/schema_macros'
require_relative 'actionable/measure_macros'
require_relative 'actionable/introspection'
require_relative 'actionable/declaration_macros'
require_relative 'actionable/declarations'
require_relative 'actionable/typed_outcomes'
require_relative 'actionable/verb_position'
require_relative 'actionable/hidden_calls'
require_relative 'actionable/verbs'
require_relative 'actionable/layout'
require_relative 'actionable/action'
require_relative 'actionable/rbs'

# Typed, composable service objects: declared inputs, ordered steps and three strict outcomes.
module Actionable
  # The throw tag every halting verb uses.
  # @return [Symbol]
  HALT = :actionable_halt

  @verb_position_check = true
  @step_options = {}

  class << self
    # Runs the block under the halt tag.
    #
    # @yield the code that may throw {HALT}
    # @return [Object] the block value, or the thrown value (+nil+ for a bare throw)
    def catch_halt(&block)
      catch(HALT, &block)
    end

    # @return [Actionable::Registry] the process-wide registry of action classes
    def registry
      @registry ||= Registry.new
    end

    # Turns the first-run verb-position check on or off for the process.
    #
    # @param value [Object] coerced to true or false
    # @return [Boolean]
    def verb_position_check=(value)
      @verb_position_check = value ? true : false
    end

    # @param klass [Class]
    # @return [String] the class name, or +action+ for an anonymous class (used in messages)
    def label_for(klass)
      klass.name || 'action'
    end

    # @return [Boolean] whether the first-run verb-position check is on (default true)
    def verb_position_check?
      @verb_position_check
    end

    # Accepts a step option key an adapter or app reads from +step.options+; any other unknown key fails at
    # declaration. Register before the actions that use it are declared.
    #
    # @param name [Symbol, String]
    # @param owner [String] the gem or app that reads the key, named in messages
    # @return [Symbol] the name
    # @raise [ArgumentError] for a core key, a key another owner registered, or a missing owner
    def register_step_option(name, owner:)
      unless owner.is_a?(String) && !owner.empty?
        raise ArgumentError, 'register_step_option needs owner: a non-empty String naming the gem or app that reads the key'
      end

      key = name.to_sym
      raise ArgumentError, "step option #{key}: is built into actionable-rb and can't be registered" if StepOptions::CORE.include?(key)

      existing = @step_options[key]
      raise ArgumentError, "step option #{key}: is already registered by #{existing}" if existing && existing != owner

      @step_options[key] = owner.dup.freeze
      key
    end

    # @return [Hash{Symbol=>String}] the registered step option keys and their owners (core keys not included), frozen
    def registered_step_options
      @step_options.dup.freeze
    end
  end
end
