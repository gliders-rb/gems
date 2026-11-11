# frozen_string_literal: true

require_relative 'lib/field_struct/version'

Gem::Specification.new do |spec|
  spec.name = 'field_struct'
  spec.version = FieldStruct::VERSION
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']

  spec.summary = 'Typed plain Ruby objects with declared, coerced, validated fields.'
  spec.description = 'Declare fields with a name, a type and options. Every assignment coerces the value, ' \
                     'records validation errors for that field, and keeps the object usable.'
  spec.homepage = 'https://github.com/gliders-rb/gems'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/gems/field_struct'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/gems/field_struct/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo. Specs, benchmarks, rake tasks, lint and type
  # config, CI and the design record stay out of the package.
  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs', 'docs/**/*.md', 'skills/**/*.md', '.claude-plugin/*.json'] +
               %w[README.md USAGE.md AGENTS.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'bigdecimal', '>= 3.0'
  spec.add_dependency 'oj', '>= 3.11.2'
  spec.add_dependency 'tzinfo', '~> 2.0'
end
