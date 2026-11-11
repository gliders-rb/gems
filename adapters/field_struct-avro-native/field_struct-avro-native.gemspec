# frozen_string_literal: true

require_relative 'lib/field_struct/avro/native/version'

Gem::Specification.new do |spec|
  spec.name = 'field_struct-avro-native'
  spec.version = FieldStruct::Avro::Native::VERSION
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']

  spec.summary = 'An optional Rust encoder for field_struct-avro: the same Avro bytes, written faster.'
  spec.description = "Compiles each writer schema into an encoding plan and writes field_struct-avro's datums to Avro binary " \
                     'in Rust. Anything it is not sure about goes to the pure-Ruby path, so output and errors stay the same.'
  spec.homepage = 'https://github.com/gliders-rb/gems'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['source_code_uri'] = 'https://github.com/gliders-rb/gems/tree/main/adapters/field_struct-avro-native'
  spec.metadata['changelog_uri'] = 'https://github.com/gliders-rb/gems/blob/main/adapters/field_struct-avro-native/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Explicit globs, not `git ls-files`: this gem lives in a monorepo.
  spec.files = Dir['lib/**/*.rb', 'sig/**/*.rbs', 'ext/**/*.{rs,rb,toml}', 'Cargo.toml', 'Cargo.lock'] +
               %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ['lib']
  spec.extensions = ['ext/field_struct_avro_native/extconf.rb']

  spec.add_dependency 'field_struct-avro', '>= 1.0.0.pre1', '< 2'
  spec.add_dependency 'rb_sys', '~> 0.9'
end
