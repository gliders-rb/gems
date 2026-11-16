# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = 'gems-doctest'
  spec.authors = ['Adrian Madrid']
  spec.email = ['adrian.madrid@timeworxs.com']
  spec.version = '0.1.0'

  spec.summary = 'Runs the Ruby examples in this monorepo\'s READMEs, USAGE files and site pages.'
  spec.description = 'A private dev tool, loaded by path from each gem\'s Gemfile. Never published.'
  spec.required_ruby_version = '>= 3.3'
  spec.license = 'MIT'
  spec.homepage = 'https://github.com/gliders-rb/gems'

  # Never published: no server answers this host, so `gem push` refuses.
  spec.metadata['allowed_push_host'] = 'https://push.invalid'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb']
  spec.require_paths = ['lib']
end
