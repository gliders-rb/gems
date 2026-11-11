# frozen_string_literal: true

require_relative 'lib/field_struct/protobuf/version'

Gem::Specification.new do |spec|
  spec.name = 'field_struct-protobuf'
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']
  spec.version = FieldStruct::Protobuf::VERSION

  spec.summary = 'proto3 messages, .proto source and wire-format bytes for field_struct classes.'
  spec.description = 'Turns a FieldStruct class into a proto3 message while the program runs, with no protoc step. ' \
                     'It prints the matching .proto source and moves instances between structs, messages and protobuf bytes. ' \
                     'You declare the field numbers.'
  spec.homepage = 'https://github.com/gliders-rb/gems'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/adapters/field_struct-protobuf'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/adapters/field_struct-protobuf/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs'] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']

  spec.add_dependency 'bigdecimal', '>= 3.1'
  spec.add_dependency 'field_struct', '>= 1.0.0.pre1', '< 2'
  spec.add_dependency 'google-protobuf', '~> 4.30'
end
