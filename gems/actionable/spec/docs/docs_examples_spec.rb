# frozen_string_literal: true

require_relative '../../support/doctest'

# Ruby blocks preceded by <!-- doctest --> run in their own process; each `# =>` is asserted by value (AC-I16).
# Tagged :doctest: skipped by the default rake task, run by `rake docs:test` (part of release:check).
RSpec.describe 'docs examples', :doctest do
  root = File.expand_path('../..', __dir__)

  %w[README.md USAGE.md docs/getting_started.md].each do |relative|
    path = File.join(root, relative)

    Doctest.blocks(path).each do |block|
      it "AC-I16: runs as documented (#{relative}:#{block.line})" do
        passed, stderr = Doctest.run(block, requires: ['actionable'], includes: [File.join(root, 'lib')])
        expect(passed).to be(true), stderr
      end
    end
  end
end
