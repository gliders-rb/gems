# frozen_string_literal: true

require_relative 'lib/actionable/docs/version'

Gem::Specification.new do |spec|
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']
  spec.version = Actionable::Docs::VERSION
  spec.name = 'actionable-docs'

  spec.summary = 'Process pages for actionable-rb actions: Markdown and a Mermaid flowchart a product manager can read.'
  spec.description = 'Renders each action as a page (steps, why it can stop, what happens after, what it needs and ' \
                     'produces) from its declarations, with rake tasks that write the pages and fail when they drift.'
  spec.homepage = 'https://github.com/gliders-rb/gems'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/adapters/actionable-docs'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/adapters/actionable-docs/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs'] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'actionable-rb', '>= 2.0.0.pre1', '< 3'
end
