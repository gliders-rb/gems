# frozen_string_literal: true

require_relative '../support/sig_tools'

namespace :docs do
  desc 'Build the YARD docs into tmp/doc, failing on any warning'
  task :generate do
    output, status = SigTools.run('yard', 'doc', '--fail-on-warning', '--no-save', '--no-cache', '--output-dir', 'tmp/doc', '--quiet')
    abort "yard doc failed:\n#{output}" unless status.success?
    puts 'yard doc: no warnings'
  end

  desc 'List undocumented members and fail below 100% (every public member carries a comment and types)'
  task :stats do
    output, status = SigTools.run('yard', 'stats', '--list-undoc', '--no-save', '--no-cache')
    puts output
    abort 'yard stats failed' unless status.success?
    abort 'Undocumented members remain: document them (a short comment and YARD types).' unless output.include?('100.00% documented')
  end

  desc 'Run the README / USAGE / getting-started doctests (each block in its own Ruby process)'
  task :test do
    sh 'bundle', 'exec', 'rspec', '--tag', 'doctest', '--format', 'progress'
  end
end
