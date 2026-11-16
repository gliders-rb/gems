# frozen_string_literal: true

# Dev-only: what `rake docs:check` requires each page to name (doc coverage, SH-B70..B76). Not packaged.
module DocsCoverage
  ROOT = File.expand_path('..', __dir__)
  SITE = File.expand_path('../../site/src/content/docs', ROOT)

  module_function

  # @return [Array<Array(String, Symbol)>] the public constants and which of their methods count
  def api
    require 'field_struct'
    [['FieldStruct', :singleton], ['FieldStruct::Base', :instance], ['FieldStruct::Presence', :instance], ['FieldStruct::Base', :macros],
     ['FieldStruct::Errors', :instance], ['FieldStruct::Registry', :instance], ['FieldStruct::ModelName', :instance],
     ['FieldStruct::Field', :instance], ['FieldStruct::Metadata', :instance], ['FieldStruct::Introspection', :singleton],
     ['FieldStruct::Introspection::Property', :instance], ['FieldStruct::Introspection::ScalarNode', :instance],
     ['FieldStruct::Introspection::ArrayNode', :instance], ['FieldStruct::Introspection::MapNode', :instance],
     ['FieldStruct::Introspection::StructNode', :instance],
     ['FieldStruct::Introspection::UnionNode', :instance], ['FieldStruct::RBS', :singleton], ['FieldStruct::Scaffold', :singleton],
     ['FieldStruct::RegisteredOption', :instance],
     ['FieldStruct::Types::Base', :both], ['FieldStruct::CoercionError', :instance], ['FieldStruct::UnknownAttributeError', :instance]]
  end

  # @return [Hash{String => String}] each target's label and Markdown text
  def targets
    reference = Dir[File.join(SITE, 'reference/field-struct/*.md')] + [File.join(SITE, 'adapters/introspection.md')]
    { 'USAGE.md' => File.read(File.join(ROOT, 'USAGE.md')),
      'the site reference (reference/field-struct, adapters/introspection)' => reference.sort.map { |path| File.read(path) }.join("\n") }
  end

  # @return [Hash{Symbol => Array<String>}] option and key names every target names
  def words
    registry = FieldStruct.types
    options = FieldStruct::FieldBuilder::UNIVERSAL_OPTIONS.map(&:to_s)
    registry.names.each { |name| options |= registry.lookup(name).option_schema.keys.map(&:to_s) }
    { option: options }
  end
end
