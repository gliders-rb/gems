# frozen_string_literal: true

require 'open3'
require_relative '../support/sig_tools'
require_relative '../support/docs_check'

namespace :docs do
  desc 'Build the YARD docs into tmp/doc, failing on any warning'
  task :generate do
    output, status = SigTools.run('yard', 'doc', '--fail-on-warning', '--no-save', '--no-cache', '--output-dir', 'tmp/doc')
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

  desc 'Require a CHANGELOG [Unreleased] entry when lib/ changed, and USAGE.md to name every public API method'
  task :check do
    require 'actionable'
    %w[actionable/rails actionable/job actionable/rspec actionable/rspec/coverage].each { |feature| require feature }
    root = File.expand_path('..', __dir__)
    allowlist = DocsCheck.parse_allowlist(File.read(File.join(root, 'support/docs_allowlist.txt')))
    missing = DocsCheck.unnamed(File.read(File.join(root, 'USAGE.md')), allowlist: allowlist)
    unless missing.empty?
      abort "USAGE.md does not name these public methods (document them, or allowlist them in support/docs_allowlist.txt):\n  " \
            "#{missing.join("\n  ")}"
    end

    base = ENV.fetch('DOCS_CHECK_BASE', 'origin/main')
    _out, found = Open3.capture2e('git', 'rev-parse', '--verify', '--quiet', base, chdir: root)
    if found.success?
      changed, = Open3.capture2e('git', 'diff', '--name-only', '--relative', base, '--', 'lib', chdir: root)
      if !changed.strip.empty? && !DocsCheck.unreleased_entry?(File.read(File.join(root, 'CHANGELOG.md')))
        abort "lib/ changed since #{base} but CHANGELOG.md has no entry under [Unreleased]:\n#{changed}"
      end
    else
      puts "docs:check: no #{base} to compare with, skipping the CHANGELOG check"
    end
    puts 'docs:check: ok'
  end

  desc 'Run the README / USAGE / getting-started doctests (each block in its own Ruby process)'
  task :test do
    sh 'bundle', 'exec', 'rspec', '--tag', 'doctest', '--format', 'progress'
  end
end
