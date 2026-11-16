# frozen_string_literal: true

require 'open3'

# FS-I21 and AC-I18: with ActiveSupport and ActiveModel loaded, the public names of the three
# core classes overlap framework names only where the allowlist in the specs says so.
RSpec.describe 'public names against ActiveSupport and ActiveModel' do
  # The allowlist from FS-I21, by class and side. Result gets its names from FieldStruct::Base.
  struct_names = {
    'instance' => %w[as_json assign_attributes attribute_names attributes errors invalid? model_name to_json
                     to_model valid? with],
    'class' => %w[attribute_names model_name validate validators]
  }
  allowed = {
    'FieldStruct::Base' => struct_names,
    'Actionable::Result' => struct_names,
    'Actionable::Action' => { 'instance' => [], 'class' => [] }
  }

  # Runs in a child process so this suite never loads ActiveSupport itself (FS-I6).
  # Prints, per class and side, the names it shares with the frameworks.
  probe = <<~RUBY
    require 'active_support'
    require 'active_support/all'
    require 'active_model'
    require 'actionable'
    require 'oj'

    eval(ARGV.fetch(0, ''))

    framework_on = lambda do |base|
      base.public_instance_methods.select do |name|
        loc = base.instance_method(name).source_location
        loc&.first&.match?(%r{/active_(support|model)/})
      end
    end

    shaped = Class.new do
      include ActiveModel::Model
      include ActiveModel::Attributes
      include ActiveModel::Serializers::JSON
      include ActiveModel::Dirty
    end
    framework = {
      'instance' => framework_on.call(Object) | (shaped.public_instance_methods - Object.public_instance_methods),
      'class' => framework_on.call(Class) |
                 (shaped.singleton_class.public_instance_methods - Class.public_instance_methods)
    }

    own = lambda do |base, stop|
      mine = base.ancestors.take_while { |mod| mod != stop }
      base.public_instance_methods.select { |name| mine.include?(base.instance_method(name).owner) }
    end

    report = { 'sample' => { 'instance' => (framework['instance'] & %i[presence valid?]).sort,
                             'class' => (framework['class'] & %i[class_attribute model_name]).sort } }
    [FieldStruct::Base, Actionable::Result, Actionable::Action].each do |klass|
      report[klass.name] = {
        'instance' => (own.call(klass, Object) & framework['instance']).map(&:to_s).sort,
        'class' => (own.call(klass.singleton_class, Object.singleton_class) & framework['class']).map(&:to_s).sort
      }
    end
    print Oj.dump(report, mode: :compat)
  RUBY

  define_method(:overlaps) do |prelude = ''|
    out, status = Open3.capture2e('bundle', 'exec', 'ruby', "-I#{File.expand_path('../lib', __dir__)}",
                                  '-e', probe, prelude, chdir: File.expand_path('..', __dir__))
    raise "probe failed:\n#{out}" unless status.success?

    Oj.load(out)
  end

  it 'FS-I21: sees the framework names it compares against' do
    expect(overlaps['sample']).to eq('instance' => %w[presence valid?], 'class' => %w[class_attribute model_name])
  end

  it 'FS-I21, AC-I18: the three core classes overlap only the allowlisted names' do
    expect(overlaps.except('sample')).to eq(allowed)
  end

  it 'FS-I21: a new public name that collides shows up as an overlap' do
    report = overlaps('FieldStruct::Base.class_eval { def presence = self }')
    expect(report['FieldStruct::Base']['instance']).to include('presence')
    expect(report['Actionable::Result']['instance']).to include('presence')
  end
end
