# frozen_string_literal: true

# Dev-only: reference tables generated from the type registry, written between markers into USAGE.md and the site's
# types page, and checked by spec/docs/generated_tables_spec.rb. The registry is the one source (R-c).
module DocTables
  ROOT = File.expand_path('..', __dir__)
  TARGETS = [
    File.join(ROOT, 'USAGE.md'),
    File.expand_path('../../site/src/content/docs/reference/field-struct/types.md', ROOT)
  ].freeze

  module_function

  # Every table this file can generate, by marker name.
  #
  # @return [Hash{String => String}]
  def tables
    { 'option-types' => option_types }
  end

  # Which built-in types take each type-specific option, in registration order.
  #
  # @return [String] a Markdown table
  def option_types
    registry = FieldStruct.types
    owners = Hash.new { |hash, key| hash[key] = [] }
    registry.names.each do |name|
      registry.lookup(name).option_schema.each_key { |option| owners[option] << name }
    end
    rows = owners.map { |option, names| "| `#{option}:` | #{names.map { |n| "`:#{n}`" }.join(', ')} |" }
    (['| Option | Types |', '|---|---|'] + rows).join("\n")
  end

  # The text with each marked region replaced by its generated table.
  #
  # @param text [String]
  # @param path [String] named in errors
  # @return [String]
  # @raise [ArgumentError] for a marker naming no table, or one with no end
  def fill(text, path)
    text.gsub(/^<!-- generated: ([\w-]+) -->\n.*?^<!-- end generated -->\n/m) do
      name = Regexp.last_match(1)
      table = tables.fetch(name) { raise ArgumentError, "#{path}: no generated table named #{name}" }
      "<!-- generated: #{name} -->\n#{table}\n<!-- end generated -->\n"
    end
  end

  # The paths whose committed tables differ from what the registry gives.
  #
  # @return [Array<String>]
  def stale
    TARGETS.reject { |path| (text = File.read(path)) == fill(text, path) }
  end

  # Rewrites every target in place.
  #
  # @return [Array<String>] the paths that changed
  def write
    stale.each { |path| File.write(path, fill(File.read(path), path)) }
  end
end
