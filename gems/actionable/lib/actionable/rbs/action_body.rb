# frozen_string_literal: true

module Actionable
  module RBS
    # The members of the action's own class declaration.
    #
    # @private
    class ActionBody
      # @param klass [Class] the action
      # @param base [Proc] maps a result constant name to the class its generated class inherits from
      def initialize(klass, base)
        @klass = klass
        @base = base
      end

      # @return [Array<String>] the member lines, sections separated by one blank line
      def lines
        sections = [run_lines, input_lines, ivar_lines, alias_lines]
        sections.concat(@klass.typed_outcomes? ? TypedSection.new(@klass, @base).sections : untyped_output_lines)
        Lines.join(sections)
      end

      private

      def output = @klass.output_schema

      def typed_input? = !@klass.input_schema.nil? && @klass.input_dispatch.nil?

      def run_lines
        returns = return_type
        return ["def self.run: (*untyped) -> #{returns}"] unless typed_input?

        ["def self.run: (#{keywords}) -> #{returns}", "            | (InputSchema input) -> #{returns}"]
      end

      def return_type
        return '(Success | Skipped | Failure)' if @klass.typed_outcomes?

        output ? 'Result' : '::Actionable::Result'
      end

      def keywords
        @klass.input_schema.metadata.map { |field| keyword(field) }.join(', ')
      end

      def keyword(field)
        return "?#{field.name}: #{FieldStruct::RBS.type_for(field, nullable: true)}" unless field.required?

        optional = field.default.nil? ? nil : '?'
        "#{optional}#{field.name}: #{FieldStruct::RBS.type_for(field, nullable: false)}"
      end

      def input_lines
        return [] unless typed_input?

        ['def input: () -> InputSchema', '', *Lines.struct_class('InputSchema', @klass.input_schema)]
      end

      def ivar_lines
        return [] unless output

        output.metadata.map { |field| "@#{field.name}: #{FieldStruct::RBS.type_for(field, nullable: true)}" }
      end

      def alias_lines
        [alias_line('failure_code', @klass.declared_failures.keys, Action::GEM_FAILURE_CODES),
         alias_line('skip_code', @klass.declared_skips.keys, [])].flatten
      end

      def alias_line(name, declared, extra)
        return [] if declared.empty?

        ["type #{name} = #{(declared + extra).uniq.map(&:inspect).join(' | ')}"]
      end

      def untyped_output_lines
        return [] unless output

        [Lines.struct_class('Output', output), result_class]
      end

      def result_class
        readers = output.metadata.map { |field| "def #{field.name}: () -> #{FieldStruct::RBS.type_for(field)}" }
        Lines.klass('class Result < ::Actionable::Result', Lines.join([['def output: () -> Output'], readers]))
      end
    end
  end
end
