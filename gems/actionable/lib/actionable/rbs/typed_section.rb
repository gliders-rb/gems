# frozen_string_literal: true

module Actionable
  module RBS
    # The output and result classes of an action with typed outcomes (AC-B#rbstyped).
    #
    # @private
    class TypedSection
      HASH = '::Hash[::Symbol, untyped]'

      # @param klass [Class] the action
      # @param base [Proc] maps a result constant name to its superclass
      def initialize(klass, base)
        @klass = klass
        @base = base
        @skip_outputs = code_outputs(:skip, klass.skip_declarations)
        @failure_outputs = code_outputs(:failure, klass.failure_declarations)
      end

      # @return [Array<Array<String>>] sections: output classes, then Success, Skipped, Failure
      def sections
        outputs = []
        outputs << Lines.struct_class('Output', @klass.output_schema) if @klass.output_schema
        (@skip_outputs + @failure_outputs).each { |(name, _code, schema)| outputs << Lines.struct_class(name, schema) }
        [*outputs, success_class, skipped_class, failure_class]
      end

      private

      # [[class name, code, schema]] for the codes that declare a schema; refuses names that clash or are not valid.
      def code_outputs(kind, declarations)
        named = {}
        declarations.each_key.filter_map do |code|
          schema = kind == :skip ? @klass.skip_output_schema(code) : @klass.failure_output_schema(code)
          next unless schema

          name = Names.output_class_name(@klass, kind, code)
          if named.key?(name)
            raise ::ArgumentError, "#{@klass.name}: #{kind} codes #{named[name].inspect} and #{code.inspect} both name #{name} " \
                                   'in the generated RBS; rename one of the codes'
          end
          named[name] = code
          [name, code, schema]
        end
      end

      def success_class
        schema = @klass.output_schema
        members = ['def code: () -> :success', "def output: () -> #{schema ? 'Output' : HASH}"]
        readers = schema ? readers_for([schema], nullable: false) : []
        Lines.klass("class Success < #{@base.call('Success')}", Lines.join([members, readers]))
      end

      def skipped_class
        schemas = @skip_outputs.map(&:last)
        members = ["def code: () -> #{alias_or('skip_code', @klass.declared_skips)}", "def output: () -> #{union(@skip_outputs, HASH)}"]
        Lines.klass("class Skipped < #{@base.call('Skipped')}", Lines.join([members, readers_for(schemas, nullable: false)]))
      end

      def failure_class
        members = ["def code: () -> #{alias_or('failure_code', @klass.declared_failures)}",
                   "def output: () -> #{union(@failure_outputs + @skip_outputs, @klass.output_schema ? 'Output' : nil, HASH)}"]
        schemas = [*@failure_outputs, *@skip_outputs].map(&:last)
        schemas << @klass.output_schema if @klass.output_schema
        Lines.klass("class Failure < #{@base.call('Failure')}", Lines.join([members, readers_for(schemas, nullable: true)]))
      end

      def alias_or(name, declared)
        declared.empty? ? '::Symbol' : name
      end

      def union(outputs, *rest)
        members = [*outputs.map(&:first), *rest].compact
        members.size == 1 ? members.first : "(#{members.join(' | ')})"
      end

      # One reader per field name across the schemas: the union of the field's types, nullable when any is.
      def readers_for(schemas, nullable:)
        types = {}
        schemas.each do |schema|
          schema.metadata.each { |field| (types[field.name] ||= []) << FieldStruct::RBS.type_for(field) }
        end
        types.map { |name, found| "def #{name}: () -> #{merge(found, nullable)}" }
      end

      def merge(found, nullable)
        nullable ||= found.any? { |type| type.end_with?('?') }
        bases = found.map { |type| type.delete_suffix('?') }.uniq
        return 'untyped' if bases.include?('untyped')

        type = bases.size == 1 ? bases.first : "(#{bases.join(' | ')})"
        nullable ? "#{type}?" : type
      end
    end
  end
end
