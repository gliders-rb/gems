# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'tmpdir'
require_relative 'sig_guards'

# Dev-only runner behind the sigs:* and docs:* rake tasks. YARD, Sord and RBS run under gemfiles/sigs.gemfile
# (a bundle apart from the main one: Sord loads every bundled gem's rbi/ directory, and RuboCop's prism dependency
# ships one that Parlour cannot parse).
module SigTools
  ROOT = File.expand_path('..', __dir__)
  SIG = File.join(ROOT, 'sig', 'actionable.rbs')
  GEMFILE = File.join(ROOT, 'gemfiles', 'sigs.gemfile')
  CEILING_FILE = File.join(ROOT, 'support', 'untyped_ceiling.txt')
  LOOSE_CEILING_FILE = File.join(ROOT, 'support', 'loose_ceiling.txt')
  COLLECTION_LOCK = File.join(ROOT, 'rbs_collection.lock.yaml')
  ALLOWLIST_FILE = File.join(ROOT, 'support', 'sord_allowlist.txt')
  LIBRARIES = %w[date time bigdecimal pathname pp field_struct].freeze

  module_function

  # Runs a command under the sigs bundle, in the gem directory, outside the caller's bundle.
  #
  # @return [Array(String, Process::Status)] combined output and status
  def run(*command)
    env = { 'BUNDLE_GEMFILE' => GEMFILE }
    Bundler.with_unbundled_env do
      system(env, 'bundle check > /dev/null 2>&1 || bundle install --quiet', chdir: ROOT, out: File::NULL)
      Open3.capture2e(env, 'bundle', 'exec', *command, chdir: ROOT)
    end
  end

  # Generates the signature text with YARD and Sord.
  #
  # @return [Array(String, String)] the RBS text and Sord's log
  # @raise [RuntimeError] when YARD or Sord fails, or Sord cannot resolve a YARD type
  def generate
    FileUtils.rm_rf(File.join(ROOT, '.yardoc'))
    yard_output, yard = run('yard', 'doc', '--no-output', '--quiet')
    raise "yard failed:\n#{yard_output}" unless yard.success?

    Dir.mktmpdir('actionable_sig') do |dir|
      # Sord's RBS loader would read a collection lock left by the types lane and fail on gems it lists, so the
      # lock is moved away while Sord runs and put back after (the types lane needs it).
      text, log, full = without_file(COLLECTION_LOCK) { [*sord(dir, 'public', '--hide-private'), sord(dir, 'full').first] }
      unresolved = SigGuards.unresolved_names(log)
      unless unresolved.empty?
        raise "Sord could not resolve these YARD types: #{unresolved.join(', ')}. Write them in full " \
              '(::String, ::Prism::DefNode), so Sord can tell them from names inside Actionable.'
      end

      # Only the first run's log is checked: the full run warns about every undocumented private helper.
      [SigGuards.add_private_verbs(SigGuards.fix_up(text), full), log]
    end
  end

  # Runs Sord once into +dir+.
  #
  # @param dir [String]
  # @param name [String] the output file's base name
  # @param flags [Array<String>] extra Sord flags
  # @return [Array(String, String)] the RBS text and Sord's log
  # @raise [RuntimeError] when Sord fails
  def sord(dir, name, *flags)
    target = File.join(dir, "#{name}.rbs")
    log, status = run('sord', 'gen', target, '--rbs', '--no-sord-comments', *flags, '--no-regenerate')
    raise "sord failed (exit #{status.exitstatus}):\n#{log}" unless status.success? && File.exist?(target)

    [File.read(target), log]
  end

  # Moves +path+ (when it exists) out of the way while the block runs, and puts it back afterwards, raise or not.
  #
  # @param path [String]
  # @return [Object] the block's value
  def without_file(path)
    return yield unless File.exist?(path)

    Dir.mktmpdir('without_file') do |dir|
      parked = File.join(dir, File.basename(path))
      FileUtils.mv(path, parked)
      begin
        yield
      ensure
        FileUtils.mv(parked, path)
      end
    end
  end

  # Prism's own signatures, for rbs validate. The sigs bundle has no prism (its gemfile leaves out the gemspec), and
  # `-r prism` there finds only Ruby's default prism gem, which ships no sig/. So this resolves the prism gem from the
  # bundle the rake task runs in (the main one, where prism is a runtime dependency) and passes its sig/ with -I.
  #
  # @return [String]
  def prism_sig
    File.join(Gem::Specification.find_by_name('prism').full_gem_path, 'sig')
  end

  # @return [Integer]
  def ceiling
    Integer(File.read(CEILING_FILE).strip)
  end

  # @return [Integer] the ceiling for +Object+ and +top+ types (SigGuards.count_loose)
  def loose_ceiling
    Integer(File.read(LOOSE_CEILING_FILE).strip)
  end

  # @return [Array<String>]
  def allowlist
    SigGuards.parse_allowlist(File.read(ALLOWLIST_FILE))
  end
end
