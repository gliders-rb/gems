# frozen_string_literal: true

require_relative '../support/doctest'

# SH-B7: Ruby blocks preceded by <!-- doctest --> run in their own process; each `# =>` is asserted by value.
# Tagged :doctest: skipped by the default rake task, run by `rake docs:test` (part of release:check).
RSpec.describe 'README examples', :doctest do
  root = File.expand_path('..', __dir__)
  path = File.join(root, 'README.md')

  Doctest.blocks(path).each do |block|
    it "run as documented (README.md:#{block.line})" do
      passed, stderr = Doctest.run(block, requires: ['field_struct/protobuf'], includes: [File.join(root, 'lib')])
      expect(passed).to be(true), stderr
    end
  end
end
