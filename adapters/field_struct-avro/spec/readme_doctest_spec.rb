# frozen_string_literal: true

# The ```ruby run blocks of each file run in order in one fresh process; each `# =>` is asserted by value.
# Tagged :doctest: skipped by the default rake task, run by `rake docs:test` (part of release:check).
RSpec.describe 'docs examples', :doctest do
  root = File.expand_path('..', __dir__)

  %w[README.md].each do |relative|
    it "runs as documented (#{relative})" do
      require 'doctest' # only in the dev bundle; the other lanes load this file but skip the tag
      path = File.join(root, relative)
      expect(Doctest.blocks(path)).not_to be_empty, "#{relative} has no ```ruby run blocks"

      run = Doctest.run_file(path, requires: ['field_struct/avro'], includes: [File.join(root, 'lib')])
      expect(run.ok).to be(true), run.stderr
    end
  end
end
