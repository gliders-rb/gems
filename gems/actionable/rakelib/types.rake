# frozen_string_literal: true

require 'open3'

namespace :types do
  desc 'Report-only: run Steep over lib/ against sig/ and print the problem count (never fails the build)'
  task :report do
    env = { 'BUNDLE_GEMFILE' => File.expand_path('../gemfiles/types.gemfile', __dir__) }
    Bundler.with_unbundled_env do
      system(env, 'bundle check > /dev/null 2>&1 || bundle install --quiet')
      system(env, 'bundle', 'exec', 'rbs', 'collection', 'install', out: File::NULL, err: File::NULL)
      output, = Open3.capture2e(env, 'bundle', 'exec', 'steep', 'check', '--severity-level=hint')
      puts output.lines.last(15).join
      count = output[/Detected (\d+) problem/, 1] || (output.include?('No type error detected') ? '0' : nil)
      puts count ? "types: Steep reports #{count} problems (report only; never gates)" : 'types: Steep gave no result (report only)'
    end
  end
end
