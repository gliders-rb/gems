# frozen_string_literal: true

require_relative 'lib/field_struct/avro/version'

Gem::Specification.new do |spec|
  spec.name = 'field_struct-avro'
  spec.version = FieldStruct::Avro::VERSION
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']

  spec.summary = 'Apache Avro schemas, datums and binary encoding for field_struct classes.'
  spec.description = 'Generates an Avro record schema from a FieldStruct class, converts instances to and from Avro datums, ' \
                     'and reads and writes the Avro binary encoding, including bytes written with an older schema.'
  spec.homepage = 'https://github.com/gliders-rb/gems'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/adapters/field_struct-avro'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/adapters/field_struct-avro/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs'] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'avro', '~> 1.12'
  spec.add_dependency 'bigdecimal', '>= 3.1'
  spec.add_dependency 'field_struct', '>= 1.0.0.pre1', '< 2'
  spec.add_dependency 'oj', '>= 3.11.2'
  spec.add_dependency 'tzinfo', '~> 2.0'
end
