# frozen_string_literal: true

namespace :release do
  lanes = ['spec', *ADAPTER_SPEC_DIRS.map { |dir| "spec:#{dir}" }, 'rubocop']
  desc 'Everything a release needs: every spec lane, rubocop, doctests, signature guards, the docs check, YARD docs'
  task check: lanes + %w[docs:test sigs:check sigs:validate sigs:untyped docs:check docs:generate docs:stats]
end
