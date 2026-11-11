# frozen_string_literal: true

require_relative 'lib/actionable/tools/version'

Gem::Specification.new do |spec|
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']
  spec.version = Actionable::Tools::VERSION
  spec.name = 'actionable-tools'

  spec.summary = 'Expose actionable-rb actions as LLM tools (MCP and RubyLLM).'
  spec.description = 'One form-neutral tool definition built from an action, with thin wrappers for the MCP Ruby SDK and ' \
                     'RubyLLM. Context fields (identity, station) are filled by the server, never by the model.'
  spec.homepage = 'https://github.com/gliders-rb/gems'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/adapters/actionable-tools'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/adapters/actionable-tools/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs'] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'actionable-rb', '>= 2.0.0.pre1', '< 3'
  spec.add_dependency 'field_struct-json_schema', '>= 1.0.0.pre1', '< 2'
  spec.add_dependency 'oj', '~> 3.16'
end
