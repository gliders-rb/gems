# frozen_string_literal: true

require_relative 'results'

# JS-B90: the Ruby half of the differential check. (The Node half runs under `rake differential`.)
RSpec.describe Differential::Results do
  def report(corpus, pool = %w[a b])
    described_class.call(corpus, pool)
  end

  it 'reports the Ruby version and one entry per corpus triple' do
    out = report([['\Aa\z', '', []]])
    expect(out['ruby']).to eq(RUBY_VERSION)
    expect(out['cases'].size).to eq(1)
  end

  it 'JS-B90: records, for a translated Regexp, the pattern and what Ruby answers for extras plus the pool, each once' do
    entry = report([['\Aa\z', '', %w[a zz]]], %w[b a]).fetch('cases').first
    expect(entry).to include('status' => 'translated', 'pattern' => '^a$')
    expect(entry['samples']).to eq([['a', true], ['zz', false], ['b', false]])
  end

  it 'JS-B90: reports a Regexp pattern_for refuses as untranslated, and one Ruby rejects as ruby-rejects' do
    out = report([['\Aa\Z', '', []], ['(', '', []]])
    expect(out['cases'].map { |c| c['status'] }).to eq(%w[untranslated ruby-rejects])
    expect(out['cases'].first).not_to have_key('samples')
  end

  it 'builds the Regexp with the i, m, x and n flags' do
    expect(described_class.build('a', 'imxn').options).to eq(Regexp::IGNORECASE | Regexp::MULTILINE | Regexp::EXTENDED | Regexp::NOENCODING)
    expect(report([['\Aa\z', 'i', []]]).fetch('cases').first['pattern']).to eq('^[aA]$')
  end

  it 'skips a sample Ruby cannot match instead of failing' do
    expect(described_class.answer(Regexp.new('\xFF', Regexp::NOENCODING), 'é')).to be_nil
  end

  describe 'the committed corpus and pool' do
    let(:corpus) { Oj.load(File.read(File.join(described_class::DIR, 'corpus.json'))) }
    let(:pool) { Oj.load(File.read(File.join(described_class::DIR, 'pool.json'))) }

    it 'JS-B92: holds triples with unique sources and flags, and a pool of unique strings' do
      expect(corpus).to all(match([a_kind_of(String), a_string_matching(/\A[imxn]*\z/), a_kind_of(Array)]))
      expect(corpus.map { |source, flags,| [source, flags] }.uniq.size).to eq(corpus.size)
      expect(pool.uniq.size).to eq(pool.size)
    end

    it 'JS-B92: covers the contractual tables of section 6.2 (a sample of them)' do
      sources = corpus.map(&:first)
      expect(sources).to include('\A\d+\.\d+\.\d+\z', '\Aok\z', '\A"(?:[^"\\\\]|\\\\.)*"\z', '\A\d*\d*x\z', '\A(a+)+\z')
    end

    it 'JS-B92: has the sample kinds the spec lists (empty, newlines, long s, Kelvin, ligatures, emoji, Arabic-Indic digits)' do
      expect(pool).to include('', "\n", "\r", "\u{17F}", "\u{212A}", "\u{FB01}", "\u{1F600}", "\u{663}", "\u{A0}")
    end
  end
end
