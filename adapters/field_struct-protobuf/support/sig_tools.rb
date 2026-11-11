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
  SIG = File.join(ROOT, 'sig', 'field_struct-protobuf.rbs')
  BASE_SIG = File.expand_path('../../gems/field_struct/sig', ROOT)
  GEMFILE = File.join(ROOT, 'gemfiles', 'sigs.gemfile')
  SORD_GEN = File.join(ROOT, 'support', 'sord_gen.rb')
  CEILING_FILE = File.join(ROOT, 'support', 'untyped_ceiling.txt')
  ALLOWLIST_FILE = File.join(ROOT, 'support', 'sord_allowlist.txt')
  LIBRARIES = %w[date time bigdecimal pathname pp].freeze

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
    # Sord's RBS loader would pick up a collection lock left by the types lane and fail on gems it lists.
    FileUtils.rm_f(File.join(ROOT, 'rbs_collection.lock.yaml'))
    yard_output, yard = run('yard', 'doc', '--no-output', '--quiet')
    raise "yard failed:\n#{yard_output}" unless yard.success?

    Dir.mktmpdir('protobuf_sig') do |dir|
      target = File.join(dir, 'field_struct-protobuf.rbs')
      log, sord = run('ruby', SORD_GEN, target, BASE_SIG)
      raise "sord failed (exit #{sord.exitstatus}):\n#{log}" unless sord.success? && File.exist?(target)

      unresolved = SigGuards.unresolved_names(log)
      unless unresolved.empty?
        raise "Sord could not resolve these YARD types: #{unresolved.join(', ')}. Write them in full " \
              '(::String, FieldStruct::Field): Sord parses only this adapter.'
      end

      [File.read(target), log]
    end
  end

  # @return [Integer]
  def ceiling
    Integer(File.read(CEILING_FILE).strip)
  end

  # @return [Array<String>]
  def allowlist
    SigGuards.parse_allowlist(File.read(ALLOWLIST_FILE))
  end
end
