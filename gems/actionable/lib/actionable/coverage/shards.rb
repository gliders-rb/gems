# frozen_string_literal: true

module Actionable
  module Coverage
    # Per-process shard files, merged later by a report.
    module Shards
      # Writes this process's observed and stubbed runs to +path+ as JSON.
      #
      # @param path [String]
      # @return [void]
      def write(path)
        FileUtils.mkdir_p(File.dirname(path))
        data = { version: 1, observed: strings(observed), stubbed: strings(stubbed) }
        File.write(path, Oj.dump(data, mode: :compat))
      end

      # @param path [String]
      # @return [Hash{Symbol=>Set<Array(String, Symbol, Symbol)>}] +{observed:, stubbed:}+ of +[String, Symbol, Symbol]+ triples
      def read(path)
        data = Oj.load(File.read(path), mode: :compat)
        { observed: triples(data['observed']), stubbed: triples(data['stubbed']) }
      end

      private

      def strings(set)
        set.map { |name, outcome, code| [name, outcome.to_s, code.to_s] }.sort
      end

      def triples(list)
        Set.new(Array(list).map { |name, outcome, code| [name, outcome.to_sym, code.to_sym] })
      end
    end
  end
end
