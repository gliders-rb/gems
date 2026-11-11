# frozen_string_literal: true

# Builds a FieldStruct class and gives it a constant name (stub_const), so message names exist (SH-B53).
# Only for specs that never register a message: the descriptor pool is process-wide, so registered classes live in
# spec/support/classes.rb and are defined once.
module StructHelpers
  def define_struct(name, parent = FieldStruct::Base, &)
    klass = Class.new(parent, &)
    stub_const(name, klass)
    klass
  end
end

RSpec.configure { |config| config.include StructHelpers }
