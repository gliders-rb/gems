# frozen_string_literal: true

# Every adapter is loaded here, so reflection sees the whole public surface. This lane runs in its own process.
require 'rbs'
require 'actionable/rails'
require 'actionable/job'
require 'actionable/rspec'
require 'actionable/rspec/coverage'

RSpec.describe 'adapter signatures' do
  root = File.expand_path('../..', __dir__)

  let(:env) do
    loader = RBS::EnvironmentLoader.new
    %w[date time bigdecimal pathname pp field_struct].each { |name| loader.add(library: name) }
    loader.add(path: Pathname(File.join(root, 'sig')))
    loader.add(path: Pathname(File.join(root, 'support/external')))
    RBS::Environment.from_loader(loader).resolve_type_names
  end
  let(:builder) { RBS::DefinitionBuilder.new(env: env) }

  # Methods the RBS says this type itself defines (not inherited from Object, Module or other types).
  def declared_instance(klass)
    name = RBS::TypeName.parse("::#{klass.name}")
    builder.build_instance(name).methods.select { |_n, m| m.defined_in == name && m.accessibility == :public }.keys.sort
  end

  def declared_singleton(klass)
    name = RBS::TypeName.parse("::#{klass.name}")
    builder.build_singleton(name).methods.select { |_n, m| m.defined_in == name && m.accessibility == :public }.keys.sort
  end

  def actual_instance(klass)
    klass.public_instance_methods(false).select { |name| ours?(klass, name) }.sort
  end

  def actual_singleton(klass)
    klass.singleton_class.public_instance_methods(false).select { |name| ours?(klass, name, singleton: true) }.sort
  end

  # RBS adds these itself (constructors from initialize, the pp mixin); reflection adds the framework's own.
  noise = %i[new initialize pretty_print pretty_print_cycle pretty_print_inspect pretty_print_instance_variables yaml_tag].freeze

  define_method(:report) do |actual, declared|
    { undeclared: actual - declared - noise, nonexistent: declared - actual - noise }
  end

  # Only methods this gem's lib defines count: ActiveModel adds callback readers to ProxyValidator, for one.
  def ours?(owner, name, singleton: false)
    method = singleton ? owner.method(name) : owner.instance_method(name)
    location = method.source_location&.first
    location.nil? || location.start_with?(File.join(File.expand_path('../..', __dir__), 'lib'))
  end

  it 'AC-B#adaptersigspec: every public class method of Action, adapters loaded, is declared (and nothing else is)' do
    actual = (Actionable::Action.singleton_class.public_instance_methods - Class.public_instance_methods).sort
    declared = builder.build_singleton(RBS::TypeName.parse('::Actionable::Action')).methods
                      .reject { |_n, m| m.defined_in.to_s.match?(/\A::(Object|Kernel|BasicObject|Module|Class)\z/) }.keys
    # The Recorder prepend wraps run (already declared); nothing else of it is public.
    expect(report(actual, declared.sort)).to eq(undeclared: [], nonexistent: [])
  end

  it 'AC-B#adaptersigspec: the public instance methods of Action are declared' do
    declared = builder.build_instance(RBS::TypeName.parse('::Actionable::Action')).methods
                      .reject { |_n, m| m.defined_in.to_s.match?(/\A::(Object|Kernel|BasicObject)\z/) }.keys
    actual = (Actionable::Action.public_instance_methods - Object.public_instance_methods).sort
    expect(report(actual, declared.sort)).to eq(undeclared: [], nonexistent: [])
  end

  {
    Actionable::Rails::Transactions => :instance, Actionable::Rails::AfterCommit => :instance,
    Actionable::Rails::Rollback => :instance, Actionable::ProxyValidator => :both,
    Actionable::Job::Mixin => :instance, Actionable::Job::RetryMacro => :instance,
    Actionable::Job::RetryableFailure => :instance, Actionable::Job => :singleton,
    Actionable::RSpec::Matchers => :instance, Actionable::RSpec::Stubs => :instance,
    Actionable::RSpec::Results => :instance, Actionable::RSpec::PerformActionable => :instance,
    Actionable::Coverage::Report => :instance, Actionable::Coverage::Settings => :instance,
    Actionable::Coverage::Outcomes => :instance, Actionable::Coverage::Shards => :instance
  }.each do |klass, kind|
    it "AC-B#adaptersigspec: #{klass} matches its declarations" do
      if %i[instance both].include?(kind)
        expect(report(actual_instance(klass), declared_instance(klass))).to eq(undeclared: [], nonexistent: [])
      end
      if %i[singleton both].include?(kind)
        expect(report(actual_singleton(klass), declared_singleton(klass))).to eq(undeclared: [], nonexistent: [])
      end
    end
  end
end
