# frozen_string_literal: true

# rubocop:disable Style/RedundantRegexpCharacterClass, Style/RedundantRegexpEscape, Lint/DuplicateRegexpCharacterClassElement
# rubocop:disable Lint/MixedRegexpCaptureTypes, Lint/MixedCaseRange, Lint/UnescapedBracketInRegexp, Style/RegexpLiteral
# The Regexps in this file are the subject under test: they are deliberately redundant, odd or ill-advised.
#
# pattern_for: the Regexp to ECMA-262 translator (JS-B50..B55, tables of 6.2). The ReDoS analysis (JS-B60..B65) is in
# pattern_safety_spec.rb.
RSpec.describe 'FieldStruct::JSONSchema.pattern_for' do
  # The tables write U+017F and U+212A as the escape text; the pattern contains the characters themselves.
  def lit(text)
    text.gsub('\u017F', "\u017F").gsub('\u212A', "\u212A")
  end

  def translate(regexp)
    FieldStruct::JSONSchema.pattern_for(regexp)
  end

  def rx(source, *options)
    Regexp.new(source, options.sum)
  end

  describe 'JS-B52 / 6.2 the translation table' do
    {
      /\A\d+\.\d+\.\d+\z/ => '^\d+\.\d+\.\d+$',
      Regexp.new('\Aa\-b\ c\@d\z') => '^a-b c@d$',
      /\A[\w\-]+\z/ => '^[\w\-]+$',
      /\Aabc.\z/ => '^abc[^\n]$',
      /\A\s\S\z/ => '^[\t\n\v\f\r ][^\t\n\v\f\r ]$',
      /^foo$/ => '(?:^|(?<=\n)(?!$))foo(?![^\n])',
      /\A\h{2}\z/i => '^[0-9a-fA-F]{2}$',
      /\Aask\z/i => '^[aA][sS\u017F][kK\u212A]$',
      /\A[a-f8]\z/i => '^[a-fA-F8]$',
      /\A[^r-t]+\z/i => '^[^r-tR-T\u017F]+$',
      /\A(?<d>\d)(?<=7)\z/ => '^(?<d>\d)(?<=7)$',
      /\Asky\z/i => '^[sS\u017F][kK\u212A][yY]$',
      /\Ac{2,4}?d\z/ => '^c{2,4}?d$',
      /\A🗿+\z/ => '^(?:🗿)+$',
      /\A[\s\S]*\z/ => '^[\s\S]*$',
      /\A[a-z]{4,12}\z/i => '^[a-zA-Z\u017F\u212A]{4,12}$',
      /\A[^s]{3}\z/i => '^[^sS\u017F]{3}$',
      /\A\d{1,2}(;\d{2})*\z/ => '^\d{1,2}(;\d{2})*$',
      /\A(?:\d{2}\.){3}\d{5}\z/ => '^(?:\d{2}\.){3}\d{5}$',
      /\Ax+|y+\z/ => '^x+|y+$',
      /\A(?:tif|raw)\z/ => '^(?:tif|raw)$',
      /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/ => '^[a-z0-9]+(?:-[a-z0-9]+)*$',
      /\A"(?:[^"\\]|\\.)*"\z/ => '^"(?:[^"\\\\]|\\\\[^\n])*"$',
      Regexp.new('\Aa}b]c{d\z') => '^a\}b\]c\{d$',
      /\A\x41\z/ => '^\x41$',
      Regexp.new('\A\x7F\z') => '^\x7F$',
      /\A[-a]\z/i => '^[-aA]$',
      /\A(a+){1}\z/ => '^(a+){1}$',
      /\A(?:a|aa){0,1}\z/ => '^(?:a|aa){0,1}$',
      /\A[\s\h]+\z/ => '^[\t\n\v\f\r 0-9a-fA-F]+$',
      /\A$/ => '^(?![^\n])',
      /\A\_\z/ => '^_$'
    }.each do |regexp, expected|
      it "translates #{regexp.inspect}" do
        expect(translate(regexp)).to eq(lit(expected))
      end
    end
  end

  describe 'JS-B50 options and the source' do
    it 'refuses x and m, and folds i' do
      expect(translate(/a/x)).to be_nil
      expect(translate(/a/m)).to be_nil
      expect(translate(/\Aa\z/i)).to eq('^[aA]$')
    end

    it 'translates the source text, not the inspect form' do
      expect(translate(%r{\A/a\z})).to eq('^/a$')
      expect(translate(rx('\A\/a\z'))).to eq('^\/a$')
    end

    it 'JS-I2: answers a Regexp that is not exact with nil, never a guess' do
      expect(translate(/\A\p{L}\z/)).to be_nil
    end
  end

  describe 'JS-B52 anchors and the group syntax' do
    it 'translates the anchors and refuses the unportable ones' do
      expect(translate(/\Aa\z/)).to eq('^a$')
      [/\Aa\Z/, /\Ga/, /\bfoo\b/, /\Ba/].each { |re| expect(translate(re)).to be_nil, re.inspect }
    end

    it 'keeps plain, non-capturing, lookaround and named groups; refuses every other (?' do
      expect(translate(/\A(a)(?:b)(?=c)(?!d)(?<=e)(?<!f)(?<n_1>g)\z/)).to eq('^(a)(?:b)(?=c)(?!d)(?<=e)(?<!f)(?<n_1>g)$')
      [/\A(?#c)a\z/, /(?i)abc/, /\A(?a)\w\z/, /\A(?>a)\z/, /(?i:a)/, /\A(?<d>\d)\g<d>\z/, /\A(?'x'a)\z/].each do |re|
        expect(translate(re)).to be_nil, re.inspect
      end
    end

    it 'refuses a duplicate group name and a backreference' do
      expect(translate(/\A(?:(?<n>a)|(?<n>b))\z/)).to be_nil
      expect(translate(/\A(a)\1\z/)).to be_nil
      expect(translate(/\A(?<q>a)\k<q>\z/)).to be_nil
    end

    it 'JS-B55: refuses an unterminated class or group and an unbalanced ) (the translator takes a source Ruby would reject)' do
      translator = FieldStruct::JSONSchema::Pattern::Translator
      ['\A(a', '\Aa)', '\A[a', '\A(?:a', '\A(a))', '\A[a-', '\Aa\\'].each do |source|
        expect(translator.new(source, fold_case: false).call).to be_nil, source
      end
    end
  end

  describe 'JS-B52 quantifiers' do
    it 'keeps the intervals and the lazy form' do
      expect(translate(/\Aa{2}b{2,}c{1,3}d*e+f?\z/)).to eq('^a{2}b{2,}c{1,3}d*e+f?$')
      expect(translate(/\Aa*?b+?c??d{2,}?e{1,2}?\z/)).to eq('^a*?b+?c??d{2,}?e{1,2}?$')
    end

    it 'refuses {n}?, possessive, stacked, {,n} and quantified anchors or lookarounds' do
      [/\Aa{2}?\z/, /\Aa++\z/, /\Aa{2}+\z/, rx('\Aa**\z'), rx('\Aa{2}{3}\z'), /\Aa{,3}\z/, /\A(?=a)*a\z/, rx('\A^*a\z'), rx('\Aa$+\z'),
       rx('\A*a\z'), rx('\Aa*+b\z')].each { |re| expect(translate(re)).to be_nil, re.inspect }
    end

    it 'reads a { that starts no interval as a literal' do
      expect(translate(rx('\Aa{b\z'))).to eq('^a\{b$')
      expect(translate(rx('\Aa{1,x}\z'))).to eq('^a\{1,x\}$')
      expect(translate(rx('\A{\z'))).to eq('^\{$')
    end
  end

  describe 'JS-B52 escapes outside a class' do
    it 'keeps the shared escapes' do
      expect(translate(/\A\d\D\w\W\n\r\t\f\v\z/)).to eq('^\d\D\w\W\n\r\t\f\v$')
      expect(translate(rx('\A\^\$\\\\\.\*\+\?\(\)\[\]\{\}\|\/\z'))).to eq('^\^\$\\\\\.\*\+\?\(\)\[\]\{\}\|\/$')
    end

    it 'expands \h and \H' do
      expect(translate(/\A\h\H\z/)).to eq('^[0-9a-fA-F][^0-9a-fA-F]$')
    end

    it 'drops the backslash of an escaped non-syntax character, which u mode rejects' do
      expect(translate(rx('\A\-\ \@\_\%\"\<\#\!\&\,\:\=\>\~\z'))).to eq('^- @_%"<#!&,:=>~$')
    end

    it 'handles \0, \xHH, \uHHHH and \cX' do
      expect(translate(rx('\A\0\z'))).to eq('^\0$')
      expect(translate(rx('\A\01\z'))).to be_nil
      expect(translate(rx('\A\u00e9\z'))).to eq('^\u00e9$')
      expect(translate(rx('\A\cA\z'))).to eq('^\cA$')
      expect(translate(rx('\A\x4\z'))).to be_nil
      expect(translate(rx('\A\u{41}\z'))).to be_nil
      expect(translate(rx('\A\c1\z'))).to be_nil
    end

    it 'refuses any other alphanumeric escape' do
      %w[\e \a \R \X \K \p{L} \P{L} \o{101} \C-a \Q \é \z\Z \w\é].each do |escape|
        expect(translate(rx("\\A#{escape}\\z"))).to be_nil, escape
      end
    end

    it 'refuses a byte-valued escape in a no-encoding Regexp' do
      expect(translate(Regexp.new('\A\xC3\xA9\z', Regexp::NOENCODING))).to be_nil
      expect(translate(Regexp.new('\A\x80\z', Regexp::NOENCODING))).to be_nil
    end

    it 'wraps a character above U+FFFF so it is one atom, and keeps BMP characters' do
      expect(translate(/\A😀{2}é\z/)).to eq('^(?:😀){2}é$')
    end
  end

  describe 'JS-B53 character classes' do
    it 'keeps ranges, negation and the shared escapes' do
      expect(translate(/\A[^a-z0-9_\-.]\z/)).to eq('^[^a-z0-9_\-.]$')
      expect(translate(/\A[\d\D\w\W\n\r\t\f\v\b]\z/)).to eq('^[\d\D\w\W\n\r\t\f\v\b]$')
      expect(translate(/\A[\s\h]\z/)).to eq('^[\t\n\v\f\r 0-9a-fA-F]$')
      expect(translate(rx('\A[\^\$\\\\\.\]\[\/]\z'))).to eq('^[\^\$\\\\\.\]\[\/]$')
    end

    it 'keeps an unescaped - at either end and a range with escaped ends' do
      expect(translate(/\A[-a]\z/)).to eq('^[-a]$')
      expect(translate(/\A[a-]\z/)).to eq('^[a-]$')
      expect(translate(/\A[\x20-\x7E]\z/)).to eq('^[\x20-\x7E]$')
      expect(translate(/\A[\t-~]\z/)).to eq('^[\t-~]$')
    end

    it 'drops the backslash of an escaped non-syntax character' do
      expect(translate(rx('\A[\@\_\ \%]\z'))).to eq('^[@_ %]$')
    end

    it 'refuses a leading ], a nested [, POSIX, &&, \B, \S, \H and astral members' do
      [rx('\A[]a]\z'), rx('\A[^]a]\z'), /\A[[:alpha:]]\z/, rx('\A[a[b]]\z'), /\A[a-z&&[^aeiou]]\z/, rx('\A[\B]\z'), rx('\A[\S]\z'),
       rx('\A[\H]\z'), rx('\A[😀]\z'), rx('\A[\A]\z'), rx('\A[\k]\z')].each do |re|
        expect(translate(re)).to be_nil, re.inspect
      end
    end
  end

  describe 'JS-B54 case folding' do
    it 'folds letters outside a class, with the extra folds of s and k' do
      expect(translate(/\Aabc\z/i)).to eq('^[aA][bB][cC]$')
      expect(translate(/\Aok\z/i)).to eq(lit('^[oO][kK\u212A]$'))
      expect(translate(/\A\d+x\z/i)).to eq('^\d+[xX]$')
    end

    it 'folds inside a class: letters, same-case ranges, extras covered by a range' do
      expect(translate(/\A[a-f8]\z/i)).to eq('^[a-fA-F8]$')
      expect(translate(/\A[A-F]\z/i)).to eq('^[A-Fa-f]$')
      expect(translate(/\A[a-z]\z/i)).to eq(lit('^[a-zA-Z\u017F\u212A]$'))
      expect(translate(/\A[^r-t]\z/i)).to eq(lit('^[^r-tR-T\u017F]$'))
      expect(translate(/\A[xs]\z/i)).to eq(lit('^[xXsS\u017F]$'))
      expect(translate(/\A[0-9_-]\z/i)).to eq('^[0-9_-]$')
      expect(translate(/\A[!-\/]\z/i)).to eq('^[!-/]$')
    end

    it 'does not fold group names or escapes such as \d, \h' do
      expect(translate(/\A(?<Ab>a)\z/i)).to eq('^(?<Ab>[aA])$')
    end

    it 'refuses the pairs Ruby folds to one character, wherever they sit in the source' do
      %w[ss ff fi fl st SS Fi].each { |pair| expect(translate(rx("\\A#{pair}\\z", Regexp::IGNORECASE))).to be_nil, pair }
      expect(translate(/\Afile\z/i)).to be_nil
    end

    it 'refuses non-ASCII sources and x/u escapes under i' do
      expect(translate(/\Aé\z/i)).to be_nil
      expect(translate(rx('\A\u00e9\z', Regexp::IGNORECASE))).to be_nil
      expect(translate(/\A\x41\z/i)).to be_nil
      expect(translate(rx('\A[\x41]\z', Regexp::IGNORECASE))).to be_nil
      expect(translate(rx("\\A[\u00A1-\u00BF]\\z", Regexp::IGNORECASE))).to be_nil
      expect(translate(rx("\\Ai\u0307\\z", Regexp::IGNORECASE))).to be_nil
    end

    it 'refuses \W and \D in a class, and ranges that are not two same-case letters' do
      [/\A[\W]\z/i, /\A[\D]\z/i, /\A[!-~]\z/i, /\A[0-z]\z/i, rx('\A[\t-~]\z', Regexp::IGNORECASE), /\A[A-z]\z/i,
       rx('\A[\\\\-f]\z', Regexp::IGNORECASE), rx('\A[\x41-\x5A]\z', Regexp::IGNORECASE)].each do |re|
        expect(translate(re)).to be_nil, re.inspect
      end
    end

    it 'refuses one-letter atoms Ruby would merge into a folding string' do
      [/\As{2}\z/i, /\A[s]s\z/i, /\A[s-s]{2}\z/i, /\A[f]i\z/i, /\Af{2}\z/i, /\A[s]t\z/i, /\Af[f]\z/i, /\Af[l]\z/i].each do |re|
        expect(translate(re)).to be_nil, re.inspect
      end
    end

    it 'keeps single-letter atoms that cannot merge' do
      expect(translate(/\As+t\z/i)).to eq(lit('^[sS\u017F]+[tT]$'))
      expect(translate(/\A(?:s)t\z/i)).to eq(lit('^(?:[sS\u017F])[tT]$'))
      expect(translate(/\As*s\z/i)).to eq(lit('^[sS\u017F]*[sS\u017F]$'))
    end
  end

  describe 'JS-B51 the output compiles under the u flag' do
    it 'drops identity escapes and escapes a lone brace or bracket' do
      expect(translate(rx('\A\}\]\{x\z'))).to eq('^\}\]\{x$')
      expect(translate(rx('\Aa}b]c\z'))).to eq('^a\}b\]c$')
    end
  end

  describe 'JS-B10 with the translator' do
    it 'turns the default URL and email Regexps of the string types into patterns' do
      url = FieldStruct::Types::URL.default_format
      expect(translate(url)).to eq(lit('^[hH][tT][tT][pP][sS\u017F]?://[^\\t\\n\\v\\f\\r /$.?#][^\\t\\n\\v\\f\\r ]*$'))
      email = FieldStruct::Types::Email.default_format
      expect(translate(email)).to eq('^[^@\\t\\n\\v\\f\\r ]+@[^@\\t\\n\\v\\f\\r ]+\\.[^@\\t\\n\\v\\f\\r ]+$')
    end

    it 'emits pattern, not x-ruby-pattern, for a translatable format: and keeps the annotation for the rest' do
      klass = Class.new(FieldStruct::Base) do
        required :id, :uuid, format: /\A[A-Z]{3}\z/
        required :slug, :string, format: /\A\p{L}+\z/
      end
      props = FieldStruct::JSONSchema.generate(klass)['properties']
      expect(props['id']).to eq('type' => 'string', 'pattern' => '^[A-Z]{3}$')
      expect(props['slug']).to eq('type' => 'string', 'x-ruby-pattern' => '\A\p{L}+\z')
    end
  end

  describe 'JS-I1 a validator agrees with the struct' do
    it 'accepts what the struct accepts and rejects what it rejects, for the default url and email formats' do
      klass = Class.new(FieldStruct::Base) do
        required :site, :url
        required :mail, :email
      end
      schema = FieldStruct::JSONSchema.generate(klass)
      expect(schema['properties']['site']).to include('pattern')
      expect(schema['properties']['mail']).to include('pattern')
      good = { 'site' => 'HTTPS://example.com/a?b=1', 'mail' => 'me@example.com' }
      expect(valid_value?(schema, good)).to be(true)
      expect(klass.from_json(Oj.dump(good, mode: :compat)).to_h).to eq(site: 'HTTPS://example.com/a?b=1', mail: 'me@example.com')
      bads = [{ 'site' => 'ftp://example.com' }, { 'site' => 'http://exa mple.com' }, { 'mail' => 'me@example' },
              { 'mail' => "me@exam\nple.com" }]
      bads.each do |bad|
        expect(valid_value?(schema, good.merge(bad))).to be(false), bad.inspect
      end
    end
  end
end

# rubocop:enable all
