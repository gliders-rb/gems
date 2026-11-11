# frozen_string_literal: true

require 'open3'
require_relative 'rails_helper'

RSpec.describe 'Rails adapter: loading' do
  def ruby(code)
    lib = File.expand_path('../../lib', __dir__)
    out, status = Open3.capture2e('bundle', 'exec', 'ruby', "-I#{lib}", '-e', code, chdir: File.expand_path('../..', __dir__))
    [out.strip, status]
  end

  it 'AC-B#railsload: never auto-loads, even with ActiveRecord defined' do
    out, = ruby("require 'active_record'; require 'actionable'; " \
                'print [Actionable::Action.respond_to?(:transactional), defined?(Actionable::ProxyValidator).inspect].inspect')
    expect(out).to eq('[false, "nil"]')
  end

  it 'AC-B#railsload: transactional is a plain NoMethodError without it' do
    out, = ruby("require 'actionable'; begin; Class.new(Actionable::Action) { transactional model: 1 }; " \
                'rescue NoMethodError => e; print e.class; end')
    expect(out).to eq('NoMethodError')
  end

  it 'AC-B#railsload: extends Action once the adapter is required' do
    expect(Actionable::Action).to respond_to(:transactional, :transaction_config, :after_commit, :after_commit_hooks)
  end

  it 'AC-B#railsload: defines a Railtie only when Rails::Railtie exists' do
    expect(defined?(Actionable::Railtie)).to be_nil
    out, = ruby("module Rails; class Railtie; end; end; require 'actionable'; require 'actionable/rails'; " \
                'print Actionable::Railtie.ancestors.include?(Rails::Railtie)')
    expect(out).to eq('true')
  end

  it 'AC-B#railsload: exposes the Rollback error' do
    expect(Actionable::Rails::Rollback.ancestors).to include(StandardError)
  end
end
