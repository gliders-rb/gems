# frozen_string_literal: true

# Fixtures for the method checks; their source is under spec/fixtures/lib, the "lib" the specs pass.
module Apiary
  # A class macro module, the way a gem's macros reach a class.
  module Macros
    def hive_count = 3
  end

  class Hive
    extend Macros

    def self.inspect_all = []

    def honey = 1

    # @api private
    # Read by the smoker, not by keepers.
    def wax = 2
    def frames=(value); end
    def to_s = 'hive'
  end
end
