# frozen_string_literal: true

require 'tmpdir'
require 'actionable/rspec'
require 'actionable/rspec/coverage'

RSpec.configure do |config|
  config.before do
    Actionable::Coverage.reset!
    Actionable::Coverage.reset_config!
    Actionable::Coverage.enable!
  end
  config.after do
    Actionable::Coverage.reset!
    Actionable::Coverage.reset_config!
  end
end

# A named action with one step, declared failures and skips taken from the keyword lists.
module CoverageHelpers
  def cov_action(name, fails: [], skips: [], parent: Actionable::Action, &body)
    named_action(name, parent) do
      fails.each { |code| fails code }
      skips.each { |code| skips code }
      step :sail
      define_method(:sail) { nil }
      class_eval(&body) if body
    end
  end
end

RSpec.configure { |config| config.include CoverageHelpers }
