# frozen_string_literal: true

# Dev-only checks behind `rake docs:check` (AC-B#docs). Pure functions; the rake task loads the gem and does the running.
# Not packaged with the gem.
module DocsCheck
  # The API classes and modules whose public methods USAGE.md must name, with the kind of method to read.
  # @return [Array<Array(String, Symbol)>]
  API = [
    ['Actionable', :singleton], ['Actionable::Action', :macros], ['Actionable::Action', :instance],
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

  # Names every class has by Ruby convention; USAGE does not need to list them.
  CONVENTIONAL = %w[== eql? hash inspect to_s method_missing respond_to_missing?].freeze

  module_function

  # @param path [String] the allowlist: one method name per line, +#+ lines and blanks ignored
  # @return [Array<String>]
  def parse_allowlist(text)
    text.lines.map(&:strip).reject { |line| line.empty? || line.start_with?('#') }
  end

  # Public method names defined by +name+ itself (not inherited from Object or FieldStruct).
  #
  # @param name [String] a constant path
  # @param kind [Symbol] +:instance+, +:singleton+ or +:both+
  # @return [Array<String>]
  def public_methods_of(name, kind)
    owner = Object.const_get(name)
    found = []
    found.concat(owner.public_instance_methods(false).select { |m| ours?(owner.instance_method(m)) }) if %i[instance both].include?(kind)
    found.concat(singleton_methods_of(owner, kind)) if %i[singleton both macros].include?(kind)
    found.map(&:to_s).uniq.sort
  end

  # Class-level methods: the ones the class itself defines, and for +:macros+ also those it gets from extended modules.
  def singleton_methods_of(owner, kind)
    names = owner.singleton_class.public_instance_methods(false)
    names |= owner.singleton_class.public_instance_methods - Class.public_instance_methods if kind == :macros
    names.select { |m| ours?(owner.method(m).unbind) }
  end

  # Only methods this gem's lib defines: ActiveModel adds callback readers to ProxyValidator, for one.
  def ours?(method)
    location = method.source_location&.first
    location.nil? || location.start_with?(File.expand_path('../lib', __dir__))
  end

  # The methods USAGE does not name, as +Class#method+ strings.
  #
  # @param usage [String] the text of USAGE.md
  # @param allowlist [Array<String>] +Class#method+ or bare names that need no mention
  # @return [Array<String>]
  def unnamed(usage, allowlist: [])
    API.flat_map do |name, kind|
      public_methods_of(name, kind).filter_map do |method|
        next if CONVENTIONAL.include?(method) || allowlist.include?(method) || allowlist.include?("#{name}##{method}")

        needle = method.delete_suffix('=')
        next if usage.match?(/(?<!\w)#{Regexp.escape(needle)}(?!\w)/)

        "#{name}##{method}"
      end
    end
  end

  # @param changelog [String]
  # @return [Boolean] whether the [Unreleased] section holds at least one non-blank line
  def unreleased_entry?(changelog)
    section = changelog[/^## \[Unreleased\]\s*\n(.*?)(?=^## \[|\z)/m, 1]
    !section.nil? && section.lines.any? { |line| !line.strip.empty? }
  end
end
