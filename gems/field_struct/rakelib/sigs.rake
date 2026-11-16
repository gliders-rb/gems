# frozen_string_literal: true

require 'digest'
require 'tempfile'
require_relative '../support/sig_tools'

namespace :sigs do
  desc 'Regenerate sig/field_struct.rbs from the YARD comments (Sord)'
  task :generate do
    text, = SigTools.generate
    FileUtils.mkdir_p(File.dirname(SigTools::SIG))
    File.write(SigTools::SIG, text)
    puts "wrote #{SigTools::SIG.delete_prefix("#{SigTools::ROOT}/")} (#{text.lines.size} lines)"
  end

  desc 'Fail when the committed signature differs from a fresh one, or Sord warnings differ from the allowlist'
  task :check do
    abort "sig/field_struct.rbs doesn't exist yet: run `rake sigs:generate` and commit it." unless File.exist?(SigTools::SIG)

    text, log = SigTools.generate
    committed = File.read(SigTools::SIG)
    unless Digest::SHA256.hexdigest(text) == Digest::SHA256.hexdigest(committed)
      Tempfile.create(%w[fresh .rbs]) do |fresh|
        fresh.write(text)
        fresh.flush
        puts `diff -u #{SigTools::SIG} #{fresh.path}`
      end
      abort 'sig/field_struct.rbs is stale: run `rake sigs:generate` and commit the result.'
    end
    failure = SigGuards.allowlist_failure(warnings: SigGuards.sord_warnings(log), allowlist: SigTools.allowlist)
    abort failure if failure
    puts 'sig/field_struct.rbs is current'
  end

  desc 'Run rbs validate over sig/'
  task :validate do
    libraries = SigTools::LIBRARIES.flat_map { |name| ['-r', name] }
    output, status = SigTools.run('rbs', '--no-collection', *libraries, '-I', 'sig', 'validate')
    abort "rbs validate failed:\n#{output}" unless status.success?
    puts 'rbs validate: ok'
  end

  desc 'Fail unless the `untyped` count, and the `Object`/`top` count, in sig/ equal their committed ceilings'
  task :untyped do
    paths = Dir[File.join(SigTools::ROOT, 'sig', '**', '*.rbs')]
    count = SigGuards.count_untyped(paths)
    loose = SigGuards.count_loose(paths)
    failures = [SigGuards.untyped_failure(count: count, ceiling: SigTools.ceiling),
                SigGuards.loose_failure(count: loose, ceiling: SigTools.loose_ceiling)].compact
    abort failures.join("\n") unless failures.empty?
    puts "sig/ has #{count} `untyped` (ceiling #{SigTools.ceiling})"
    puts "sig/ has #{loose} `Object`/`top` types (ceiling #{SigTools.loose_ceiling})"
  end
end
