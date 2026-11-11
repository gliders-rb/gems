# frozen_string_literal: true

module Actionable
  module Coverage
    # Which outcomes an action should reach, and which actions are in scope.
    module Outcomes
      # @param action [Class]
      # @return [Array<String>] +"success"+, +"failure:<code>"+, +"skipped:<code>"+
      def expected_outcomes(action)
        keys = ['success']
        keys.concat(action.declared_failures.keys.map { |code| "failure:#{code}" })
        keys.concat(action.declared_skips.keys.map { |code| "skipped:#{code}" })
        keys << 'failure:invalid_input' if gem_codes.include?(:invalid_input) && invalid_input_possible?(action)
        keys << 'failure:invalid_output' if gem_codes.include?(:invalid_output) && invalid_output_possible?(action)
        keys.uniq
      end

      # @return [Array<Class>] named actions with steps under {#root}, sorted by name
      def actions
        loader&.call
        found = descendants(root).select { |klass| reportable?(klass) }
        found.uniq.sort_by(&:name)
      end

      private

      def descendants(klass)
        klass.subclasses.flat_map { |child| [child, *descendants(child)] }
      end

      def reportable?(klass)
        klass.name && klass.steps.any? && resolves?(klass) && included?(klass.name)
      end

      def resolves?(klass)
        Object.const_get(klass.name).equal?(klass)
      rescue NameError
        false
      end

      def included?(name)
        return false if exclude_prefixes.any? { |filter| prefix_match?(filter, name) }

        include_prefixes.empty? || include_prefixes.any? { |filter| prefix_match?(filter, name) }
      end

      def prefix_match?(filter, name)
        filter.is_a?(Regexp) ? filter.match?(name) : name.start_with?(filter.to_s)
      end

      def invalid_input_possible?(action)
        dispatch = action.input_dispatch
        return dispatch.default_schema.nil? || dispatch.schemas.any? { |schema| required_field?(schema) } if dispatch

        required_field?(action.input_schema)
      end

      def invalid_output_possible?(action)
        schemas = [action.output_schema, *action.failure_declarations.values.map { |d| d[:output_schema] },
                   *action.skip_declarations.values.map { |d| d[:output_schema] }]
        schemas.any? { |schema| required_field?(schema) }
      end

      def required_field?(schema)
        return false unless schema

        schema.attribute_names.any? { |name| schema.metadata[name].required? }
      end
    end
  end
end
