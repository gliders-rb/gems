# frozen_string_literal: true

require 'open3'

namespace :differential do
  # About 85% of what the corpus translates: a pattern_for that gave up on everything must not pass (JS-B91).
  floor = 680

  desc "Compare pattern_for with Node's RegExp over spec/differential/corpus.json (needs node; JS-B90..B92)"
  task :run do
    abort 'differential needs node on the PATH' unless system('node', '--version', out: File::NULL, err: File::NULL)

    results = Open3.pipeline(
      [RbConfig.ruby, '-Ilib', 'spec/differential/results.rb'],
      [{ 'MIN_TRANSLATED' => floor.to_s }, 'node', 'spec/differential/check.mjs']
    )
    abort 'differential: Ruby and Node disagree (see above)' unless results.all?(&:success?)
  end
end

desc 'Run the differential check against Node (alias for differential:run)'
task differential: 'differential:run'
