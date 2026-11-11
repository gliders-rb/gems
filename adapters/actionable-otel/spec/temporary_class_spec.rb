# frozen_string_literal: true

RSpec.describe 'OT-B9: temporary class names are not cached' do
  def cache_sizes
    step_cache = Actionable::Otel.instance_variable_get(:@step_cache)
    run_names = Actionable::Otel.instance_variable_get(:@run_names) || {}
    [run_names.size, step_cache[Probe.steps.first]&.size.to_i]
  end

  before do
    Actionable::Otel.instance_variable_set(:@run_names, nil)
    Actionable::Otel.instance_variable_set(:@step_cache, ObjectSpace::WeakKeyMap.new)
    stub_const('Probe', Class.new(Actionable::Action) do
      step :scan
      define_method(:scan) { nil }
    end)
  end

  it 'does not grow the tables over many temporarily named subclasses' do
    Probe.run
    before = cache_sizes
    20.times do |i|
      Class.new(Probe).tap { |k| k.set_temporary_name("temp-apiary-#{i}") }.run
    end
    expect(cache_sizes).to eq(before)
    expect(spans_named('temp-apiary-19.run').size).to eq(1)
    expect(spans_named('temp-apiary-19/scan').size).to eq(1)
  end

  it 'does not grow the tables over many anonymous subclasses' do
    Probe.run
    before = cache_sizes
    20.times { Class.new(Probe).run }
    expect(cache_sizes).to eq(before)
    expect(spans_named('Actionable::Action.run').size).to eq(20)
  end

  it 'still caches a named class' do
    Probe.run
    expect(cache_sizes).to eq([1, 1])
    Probe.run
    expect(cache_sizes).to eq([1, 1])
  end

  it 'names a class that is named after its first run' do
    klass = Class.new(Probe)
    klass.set_temporary_name('before-naming')
    klass.run
    stub_const('Named', klass)
    klass.run
    expect(spans_named('Named.run').size).to eq(1)
    expect(spans_named('Named/scan').size).to eq(1)
  end
end
