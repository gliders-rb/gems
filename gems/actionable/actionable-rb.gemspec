# frozen_string_literal: true

require_relative 'lib/actionable/version'

Gem::Specification.new do |spec|
  spec.name = 'actionable-rb'
  spec.version = Actionable::VERSION
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']

  spec.summary = 'Typed, composable service objects: declared inputs, steps and outcomes.'
  spec.description = 'Subclass Actionable::Action, declare steps, and call run. Every run returns one Success, Failure ' \
                     'or Skipped result with a code, a message, structured errors, a typed output and a history.'
  spec.homepage = 'https://github.com/gliders-rb/gems'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/gems/actionable'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/gems/actionable/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'
  spec.metadata['default_lint_roller_plugin'] = 'Actionable::RubocopPlugin'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  spec.files = Dir['lib/**/*.rb', 'lib/**/*.yml', 'sig/**/*.rbs', 'docs/**/*.md', 'skills/**/*.md', '.claude-plugin/*.json'] +
               %w[README.md USAGE.md AGENTS.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'field_struct', '>= 1.0.0.pre1'
  spec.add_dependency 'oj', '>= 3.0'
  spec.add_dependency 'prism', '>= 1.0'
end
