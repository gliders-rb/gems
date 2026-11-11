# frozen_string_literal: true

require_relative 'lib/field_struct/json_schema/version'

Gem::Specification.new do |spec|
  spec.name = 'field_struct-json_schema'
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']
  spec.version = FieldStruct::JSONSchema::VERSION

  spec.summary = 'JSON Schema (draft 2020-12) for field_struct classes.'
  spec.description = 'Generates the JSON Schema of the JSON a FieldStruct class writes with to_json and reads with from_json, ' \
                     'and translates Ruby Regexps into exact ECMA-262 patterns.'
  spec.required_ruby_version = '>= 3.3'
  spec.license = 'MIT'
  spec.homepage = 'https://github.com/gliders-rb/gems'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/adapters/field_struct-json_schema'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/adapters/field_struct-json_schema/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs'] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'field_struct', '>= 1.0.0.pre1', '< 2'
end
