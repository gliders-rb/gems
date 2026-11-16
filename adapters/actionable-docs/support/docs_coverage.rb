# frozen_string_literal: true

# Dev-only: what `rake docs:check` requires the README and the site page to name (doc coverage, SH-B70..B76).
# Not packaged.
module DocsCoverage
  ROOT = File.expand_path('..', __dir__)
  PAGE = File.expand_path('../../site/src/content/docs/adapters/process-docs.md', ROOT)

  module_function

  # @return [Array<Array(String, Symbol)>] the public constants and which of their methods count
  def api
    require 'actionable/docs'
    require 'actionable/docs/tasks'
    [['Actionable::Docs', :singleton], ['Actionable::Docs::Tasks', :singleton]]
  end

  # @return [Hash{String => String}] each target's label and Markdown text
  def targets
    { 'README.md' => File.read(File.join(ROOT, 'README.md')), 'the site page (adapters/process-docs.md)' => File.read(PAGE) }
  end

  # @return [Hash{Symbol => Array<String>}] option and key names every target names
  def words
    {}
  end
end
