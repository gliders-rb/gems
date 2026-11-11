# frozen_string_literal: true

require_relative 'lib/actionable/otel/version'

repo_url = 'https://github.com/gliders-rb/gems'
gem_home = "#{repo_url}/%s/main/adapters/actionable-otel"

Gem::Specification.new do |gem|
  gem.summary = 'OpenTelemetry tracing for actionable-rb actions.'
  gem.description = 'One span per Action.run, a child span per executed step and hook, the outcome and result code as ' \
                    'attributes, and never an input or output value.'
  gem.name = 'actionable-otel'
  gem.version = Actionable::Otel::VERSION
  gem.license = 'MIT'
  gem.authors = ['Adrian Madrid']
  gem.email = ['adrian.madrid@timeworxs.com']
  gem.homepage = repo_url
  gem.required_ruby_version = '>= 3.3'

  gem.metadata = {
    'source_code_uri' => format(gem_home, 'tree'),
    'changelog_uri' => "#{format(gem_home, 'blob')}/CHANGELOG.md",
    'rubygems_mfa_required' => 'true'
  }

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  gem.require_paths = ['lib']
  gem.files = Dir['lib/**/*.rb', 'sig/**/*.rbs'] + %w[README.md CHANGELOG.md LICENSE.txt]

  gem.add_dependency 'actionable-rb', '>= 2.0.0.pre1', '< 3'
  gem.add_dependency 'opentelemetry-api', '~> 1.7'
end
