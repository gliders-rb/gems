# frozen_string_literal: true

# Dev-only: what `rake docs:check` requires the README and the site page to name (doc coverage, SH-B70..B76).
# Not packaged.
module DocsCoverage
  ROOT = File.expand_path('..', __dir__)
  PAGE = File.expand_path('../../site/src/content/docs/adapters/protobuf.md', ROOT)

  module_function

  # @return [Array<Array(String, Symbol)>] the public constants and which of their methods count
  def api
    require 'field_struct/protobuf'
    [['FieldStruct::Protobuf', :singleton]]
  end

  # @return [Hash{String => String}] each target's label and Markdown text
  def targets
    { 'README.md' => File.read(File.join(ROOT, 'README.md')), 'the site page (adapters/protobuf.md)' => File.read(PAGE) }
  end

  # @return [Hash{Symbol => Array<String>}] option and key names every target names: the field option this adapter
  #   registers (SH-B73)
  def words
    require 'field_struct/protobuf'
    mine = FieldStruct.registered_options.values.select { |entry| entry.owner == 'field_struct-protobuf' }
    { option: mine.map { |entry| entry.name.to_s } }
  end
end
