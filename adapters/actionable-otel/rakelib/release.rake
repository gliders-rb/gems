# frozen_string_literal: true

namespace :release do
  desc 'Everything a release needs: spec, rubocop, doctests, signature guards, YARD docs'
  task check: %w[spec rubocop docs:test sigs:check sigs:validate sigs:untyped docs:generate docs:stats]
end
