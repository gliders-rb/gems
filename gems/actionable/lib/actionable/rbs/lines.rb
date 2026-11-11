# frozen_string_literal: true

module Actionable
  module RBS
    # Line-level helpers shared by the generator parts.
    #
    # @private
    module Lines
      module_function

      # Two spaces per level; blank lines stay empty.
      def indent(lines)
        lines.map { |line| line.empty? ? line : "  #{line}" }
      end

      # Joins sections (arrays of lines) with one blank line between them, dropping empty ones.
      def join(sections)
        sections.reject(&:empty?).each_with_index.flat_map { |lines, index| index.zero? ? lines : ['', *lines] }
      end

      # A class declaration around +members+ (already-built lines).
      def klass(header, members)
        [header, *indent(members), 'end']
      end

      # A FieldStruct-shaped class: per field a reader and a writer taking nil, a blank line between fields.
      def struct_class(name, schema, superclass = '::FieldStruct::Base')
        entries = schema.metadata.map do |field|
          writer = FieldStruct::RBS.type_for(field, nullable: true)
          ["attr_reader #{field.name}: #{FieldStruct::RBS.type_for(field)}", "def #{field.name}=: (#{writer} value) -> #{writer}"]
        end
        klass("class #{name} < #{superclass}", join(entries))
      end

      # The empty +Success+, +Skipped+ and +Failure+ classes of a typed action, or nothing for an untyped one.
      def result_classes(klass, base)
        return [] unless klass.typed_outcomes?

        join(%w[Success Skipped Failure].map { |const| klass("class #{const} < #{base.call(const)}", []) })
      end
    end
  end
end
