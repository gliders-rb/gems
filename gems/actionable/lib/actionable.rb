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
  end
end
