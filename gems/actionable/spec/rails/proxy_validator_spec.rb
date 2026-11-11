# frozen_string_literal: true

require_relative 'rails_helper'

RSpec.describe Actionable::ProxyValidator do
  let(:rules_class) do
    Class.new(described_class) do
      validates :hull, presence: true
      validates :bunks, numericality: { greater_than: 0 }
    end
  end

  let(:delegate) { Struct.new(:hull, :bunks).new('', 0) }

  it 'AC-B#proxy: forwards attribute reads to the delegate and exposes it' do
    rules = rules_class.new(delegate)
    expect(rules.delegate).to equal(delegate)
    expect(rules.hull).to eq('')
  end

  it 'AC-B#proxy: formatted_errors runs valid? and returns errors.to_hash' do
    rules = rules_class.new(delegate)
    expect(rules.formatted_errors).to eq(hull: ["can't be blank"], bunks: ['must be greater than 0'])
  end

  it 'AC-B#proxy: is empty for a valid delegate' do
    delegate.hull = 'a'
    delegate.bunks = 2
    expect(rules_class.new(delegate).formatted_errors).to eq({})
  end

  it 'AC-B#proxy: raises as usual for reads the delegate cannot answer' do
    expect { rules_class.new(delegate).nothing_here }.to raise_error(NoMethodError)
    expect(rules_class.new(delegate)).not_to respond_to(:nothing_here)
  end

  it 'AC-B#proxy: builds model_name from the class name, or ProxyValidator when anonymous' do
    stub_const('CrossingRules', Class.new(described_class))
    expect(CrossingRules.model_name.name).to eq('CrossingRules')
    expect(Class.new(described_class).model_name.name).to eq('ProxyValidator')
  end

  it 'AC-B#proxy: splats into fail' do
    rules = rules_class.new(delegate)
    action = build_action do
      step :check
      define_method(:check) { fail!(:invalid, 'bad', **rules.formatted_errors) }
    end
    expect(action.run.errors.to_h).to eq(hull: ["can't be blank"], bunks: ['must be greater than 0'])
  end
end
