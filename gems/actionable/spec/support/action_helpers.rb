# frozen_string_literal: true

# Builds an anonymous action class from a block, optionally naming it for the example.
module ActionHelpers
  def build_action(parent = Actionable::Action, &block)
    Class.new(parent, &block)
  end

  # The class is named before its body runs, so messages and the registry see the name.
  def named_action(name, parent = Actionable::Action, &block)
    klass = Class.new(parent)
    stub_const(name, klass)
    klass.class_eval(&block)
    klass
  end
end

RSpec.configure { |config| config.include ActionHelpers }
