# frozen_string_literal: true

require 'rbconfig'

RSpec.describe Actionable do
  it 'AC-I11: loads from the gem-named shim and exposes a version' do
    expect(Actionable::VERSION).to eq('2.0.0.pre1')
    expect(Gem::Specification.load(File.expand_path('../actionable-rb.gemspec', __dir__)).name).to eq('actionable-rb')
  end

  it 'AC-I10: loading the core does not pull in Rails, RSpec adapters or coverage' do
    expect(defined?(Actionable::Coverage)).to be_nil
    expect(defined?(Actionable::Job)).to be_nil
    expect(defined?(ActiveSupport)).to be_nil
  end

  describe 'halt primitive' do
    it 'AC-I1: HALT is :actionable_halt' do
      expect(Actionable::HALT).to eq(:actionable_halt)
    end

    it 'AC-I1: catch_halt returns the block value, or the thrown value' do
      expect(described_class.catch_halt { 5 }).to eq(5)
      expect(described_class.catch_halt { throw Actionable::HALT, :x }).to eq(:x)
      expect(described_class.catch_halt { throw Actionable::HALT }).to be_nil
    end

    it 'AC-I1: catch_halt does not rescue exceptions' do
      expect { described_class.catch_halt { raise 'kraken' } }.to raise_error(RuntimeError, 'kraken')
    end
  end

  describe 'errors' do
    it '4.1: forms the documented hierarchy' do
      expect(Actionable::Error.superclass).to eq(StandardError)
      expect(Actionable::DefinitionError.superclass).to eq(Actionable::Error)
    end
  end

  describe 'verb position switch' do
    around do |example|
      original = described_class.verb_position_check?
      example.run
    ensure
      described_class.verb_position_check = original
    end

    it '4.1: defaults to on in a fresh process' do
      lib = File.expand_path('../lib', __dir__)
      out = IO.popen([RbConfig.ruby, '-I', lib, '-e', 'require "actionable"; print Actionable.verb_position_check?'], &:read)
      expect(out).to eq('true')
    end

    it '4.1: coerces to a boolean' do
      described_class.verb_position_check = nil
      expect(described_class.verb_position_check?).to be(false)
      described_class.verb_position_check = 1
      expect(described_class.verb_position_check?).to be(true)
    end
  end

  it '4.1: registry is process-wide and memoized' do
    expect(described_class.registry).to be_a(Actionable::Registry)
    expect(described_class.registry).to equal(described_class.registry)
  end
end
