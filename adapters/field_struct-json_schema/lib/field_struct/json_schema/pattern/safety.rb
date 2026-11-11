# frozen_string_literal: true

require_relative 'safety/groups'
require_relative 'safety/paths'
require_relative 'safety/chains'

module FieldStruct
  module JSONSchema
    module Pattern
      # The ReDoS analysis (JS-B60..B65): refuses a translated pattern a backtracking engine could run in exponential time,
      # or in more than quadratic time, on a crafted input. Conservative: a false refusal is acceptable, a false acceptance
      # is not (JS-I3). Internal.
      module Safety
        module_function

        # @param alternatives [::Array<::Array<Item>>] the top-level alternatives the translator read
        # @return [::Boolean] true when the pattern is safe to hand to a JavaScript engine
        def safe?(alternatives)
          catch(:unsafe) do
            Groups.check(alternatives)
            alternatives.each { |sequence| Chains.check(Paths.expand_top(sequence)) }
            return true
          end
          false
        end
      end
    end
  end
end
