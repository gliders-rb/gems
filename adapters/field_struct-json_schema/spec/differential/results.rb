# frozen_string_literal: true

# The Ruby half of the differential check (JS-B90): reads the corpus and the sample pool, runs pattern_for on every
# Regexp, and for each translated one records whether Ruby matches each sample, computed on the running Ruby (Onigmo
# differs between Rubies, so the answers are never stored). Writes JSON to stdout for check.mjs.
#
#   ruby -Ilib spec/differential/results.rb | node spec/differential/check.mjs
require 'oj'
require 'field_struct/json_schema'

module Differential
  # Builds the report Node compares.
  module Results
    FLAGS = { 'i' => Regexp::IGNORECASE, 'm' => Regexp::MULTILINE, 'x' => Regexp::EXTENDED, 'n' => Regexp::NOENCODING }.freeze
    DIR = __dir__

    module_function

    # @param corpus [Array<Array>] +[source, flags, extra_samples]+ triples
    # @param pool [Array<String>] samples tried against every translated pattern
    # @return [Hash] +{ruby:, cases:}+
    def call(corpus, pool)
      { 'ruby' => RUBY_VERSION, 'cases' => corpus.map { |source, flags, extras| one(source, flags, extras, pool) } }
    end

    # @return [Hash]
    def one(source, flags, extras, pool)
      regexp = build(source, flags)
      return { 'source' => source, 'flags' => flags, 'status' => 'ruby-rejects' } unless regexp

      pattern = FieldStruct::JSONSchema.pattern_for(regexp)
      return { 'source' => source, 'flags' => flags, 'status' => 'untranslated' } unless pattern

      samples = (extras + pool).uniq.filter_map { |sample| answer(regexp, sample) }
      { 'source' => source, 'flags' => flags, 'status' => 'translated', 'pattern' => pattern, 'samples' => samples }
    end

    # @return [Regexp, nil] nil when Ruby rejects the source
    def build(source, flags)
      Regexp.new(source, flags.each_char.sum { |flag| FLAGS.fetch(flag) })
    rescue RegexpError
      nil
    end

    # @return [Array(String, Boolean), nil] the sample and whether Ruby matches it; nil when Ruby cannot say
    def answer(regexp, sample)
      [sample, regexp.match?(sample)]
    rescue ArgumentError, EncodingError
      nil
    end

    # Runs as a script: corpus and pool from this directory, JSON to stdout.
    def main
      $VERBOSE = nil
      corpus = Oj.load(File.read(File.join(DIR, 'corpus.json')))
      pool = Oj.load(File.read(File.join(DIR, 'pool.json')))
      $stdout.write(Oj.dump(call(corpus, pool), mode: :compat))
    end
  end
end

Differential::Results.main if $PROGRAM_NAME == __FILE__
