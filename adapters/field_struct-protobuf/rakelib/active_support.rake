# frozen_string_literal: true

namespace :spec do
  desc 'Run the suite with ActiveSupport loaded first, under a non-UTC TZ, deprecations raising (SH-B22)'
  task :active_support do
    env = {
      'ACTIVE_SUPPORT_LANE' => '1',
      'TZ' => 'America/Denver',
      'BUNDLE_GEMFILE' => File.expand_path('../gemfiles/active_support.gemfile', __dir__)
    }
    sh env, 'bundle', 'install', '--local', '--quiet'
    sh env, 'bundle', 'exec', 'rspec', '--tag', '~doctest'
  end
end
