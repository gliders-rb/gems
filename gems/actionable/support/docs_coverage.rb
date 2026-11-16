# frozen_string_literal: true

# Dev-only: what `rake docs:check` requires each page to name (doc coverage, SH-B70..B76). Not packaged.
module DocsCoverage
  ROOT = File.expand_path('..', __dir__)
  SITE = File.expand_path('../../site/src/content/docs', ROOT)
  FEATURES = %w[actionable actionable/rails actionable/job actionable/rspec actionable/rspec/coverage].freeze

  # The API classes and modules whose public methods every page must name, with the kind of method to read.
  API = [
    ['Actionable', :singleton], ['Actionable::Action', :macros], ['Actionable::Action', :instance],
    ['Actionable::Verbs', :instance], ['Actionable::Declarations', :instance],
    ['Actionable::Result', :instance], ['Actionable::Failure', :instance], ['Actionable::BatchResult', :instance],
    ['Actionable::Registry', :instance], ['Actionable::History', :instance], ['Actionable::InputDispatch', :both],
    ['Actionable::InputDispatch::Builder', :instance], ['Actionable::Steps::Base', :instance],
    ['Actionable::Steps::Case', :both], ['Actionable::Steps::Case::Builder', :instance], ['Actionable::ValueMatch', :singleton],
    ['Actionable::VerbPosition', :singleton], ['Actionable::RBS', :singleton], ['Actionable::Job', :singleton],
    ['Actionable::Job::Mixin', :instance], ['Actionable::Job::RetryMacro', :instance],
    ['Actionable::Rails::Transactions', :instance], ['Actionable::ProxyValidator', :instance],
    ['Actionable::RSpec::Matchers', :instance], ['Actionable::RSpec::Stubs', :instance],
    ['Actionable::RSpec::PerformActionable', :instance], ['Actionable::Coverage', :singleton], ['Actionable::Coverage::Report', :instance],
    ['Actionable::Coverage::Settings', :instance], ['Actionable::Coverage::Outcomes', :instance],
    ['Actionable::Coverage::Shards', :instance], ['Actionable::Coverage::Recorder', :instance]
  ].freeze

  module_function

  # @return [Array<Array(String, Symbol)>]
  def api
    FEATURES.each { |feature| require feature }
    API
  end

  # @return [Hash{String => String}] each target's label and Markdown text
  def targets
    reference = Dir[File.join(SITE, 'reference/actionable/*.md')]
    { 'USAGE.md' => File.read(File.join(ROOT, 'USAGE.md')),
      'the site reference (reference/actionable)' => reference.map { |path| File.read(path) }.join("\n") }
  end

  # @return [Hash{Symbol => Array<String>}] every +describe+ key, read from a bare action
  def words
    api
    { key: Class.new(Actionable::Action).describe.keys.map(&:to_s) }
  end
end
