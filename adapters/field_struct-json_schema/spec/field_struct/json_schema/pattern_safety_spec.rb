# frozen_string_literal: true

# The ReDoS analysis (JS-B60..B65, JS-I3). The lists are the review-hardened cases of the spec and are contractual.
RSpec.describe 'FieldStruct::JSONSchema.pattern_for safety' do
  def translate(source, options = 0)
    FieldStruct::JSONSchema.pattern_for(Regexp.new(source, options))
  end

  def self.lines(text)
    text.lines.map(&:chomp).reject(&:empty?)
  end

  describe 'JS-B60 repeated ambiguous groups' do
    accepted = <<~'LIST'
      (?:\d{1,3}\.){3}
      (?:-[a-z0-9]+)*
      (?:[^"\\]|\\.)*
      (?:[a-z0-9-]+\.)+
      (?:a|b){2}
      (ab)+
      (\d+\.)?\d+
      \d{1,3}(,\d{3})*
      (a+){1}
      (?:a|aa){0,1}
    LIST
    refused = <<~'LIST'
      (a+)+
      (x+x+)+y
      ([^\n]*a){20}
      (\w+\s?)+
      ((a+)b)+
      (a?){20}
      (a{2,3})+
      (?:a|a)+
      (?:\w|\d)+
      (?:a|aa)+
      (?:a|b|ab)*
      (?:ab|abab)+
      (?:(?:a|aa){2}b)+
      (?:a|aa){20}
      (?:a?a)+
      (?:\d+\.?)+
      (?:a+b|a)+
    LIST

    lines(accepted).each do |source|
      it "accepts #{source}" do
        expect(translate(source)).not_to be_nil
      end
    end

    lines(refused).each do |source|
      it "refuses #{source}" do
        expect(translate(source)).to be_nil
      end
    end

    it 'refuses the same shapes anchored, and with a lazy quantifier on the group' do
      expect(translate('\A(a+)+\z')).to be_nil
      expect(translate('\A(?:a+)+?\z')).to be_nil
      expect(translate('\A(?:a|aa)*?\z')).to be_nil
    end

    it 'does not count a fixed count over a plain atom, nor a quantifier whose maximum is 1' do
      expect(translate('\A(?:\d{3}-){2}\d{4}\z')).to eq('^(?:\d{3}-){2}\d{4}$')
      expect(translate('\A(a+)?\z')).to eq('^(a+)?$')
      expect(translate('\A(?:a|aa){0,1}\z')).to eq('^(?:a|aa){0,1}$')
    end

    it 'refuses an empty alternative or one made of items that match nothing' do
      expect(translate('\A(?:a|)+\z')).to be_nil
      expect(translate('\A(?:a|b?)+\z')).to be_nil
      expect(translate('\A(?:a|^)+\z')).to be_nil
    end
  end

  describe 'JS-B61..B64 polynomial chains and the retry' do
    accepted = <<~'LIST'
      \A\d*\d*x\z => ^\d*\d*x$
      \d+x => \d+x
      \A\d*(?=\d*x)\d*y\z => ^\d*(?=\d*x)\d*y$
      \A\d*(?:x\d*)?\d*y\z => ^\d*(?:x\d*)?\d*y$
      \Aa*b*a*b*x\z => ^a*b*a*b*x$
      \A\d?\d?x\z => ^\d?\d?x$
      \Aa*(?:ab?)+\z => ^a*(?:ab?)+$
      \A(?:a)+(?:ab|b)+y\z => ^(?:a)+(?:ab|b)+y$
      \Aa*(?:b|)?a*y\z => ^a*(?:b|)?a*y$
    LIST
    refused = <<~'LIST'
      \A\d*\d*\d*x\z
      \A\d*\w*\d+x\z
      \A(?:a)?\w+\d*\d*!\z
      \A(?:\d*)\d*\d*x\z
      \A\d*(?:a|\d*)\d*x\z
      \A(?:\d*\d*)\d*x\z
      \A(?:ba*){2}a*a*x\z
      \Aa*b*a*b*a*x\z
      \A\s*\w*\s*\w*\s*\w*\s*\z
      \A(?:ab)+(?:ab)+(?:ab)+x\z
      \A(?:\d(?!\d*\d*y))+x\z
      \A\d*(?=\d*\d*x)
      \A\d*(?=\d*(?=\d*x))
      \A\w+(?=\w*\w*\d)\z
      \d*\d*x
      \w*\d+x\z
      \A\d*\d*x\d*\d*y\z
      \A[a-z]+[a-z0-9]*\.[a-z]+[a-z0-9]*\z
      \A.*x.*y.*z\z
      \A\d*\d*[a-z]*[a-z]*x\z
      \A\d*\w*[a-z]*x\z
      \d*x\d*\d*y
      \A\d*\d*(?=x\d*\d*y)\z
      \A\d{0,8}\d{0,8}\d{0,8}x\z
      \A\d?\d?\d?x\z
      \Aa*(?:ab?)+a*y\z
      \A\d*(?:\d,?)+\d*y\z
      \A\d*(?:\d|[a-z]x)+\d*y\z
      \d*(?:\d,?)+y
      \Ax*(?:x\d*)+\d*y\z
      \A\d*(?:\d*x)+x*y\z
      \Aa*(?:a){2,50}a*y\z
      \Aa*(?:a)?a*y\z
    LIST

    lines(accepted).each do |line|
      source, output = line.split(' => ')
      it "accepts #{source}" do
        expect(translate(source)).to eq(output)
      end
    end

    lines(refused).each do |source|
      it "refuses #{source}" do
        expect(translate(source)).to be_nil
      end
    end
  end

  describe 'JS-B63 the retry of an unanchored pattern' do
    it 'adds a leading variable item unless the alternative starts at \A (not inside a group, and ^ does not count)' do
      expect(translate('\d+x')).to eq('\d+x')
      expect(translate('\d*\d*x')).to be_nil
      expect(translate('\A\d*\d*x\z')).to eq('^\d*\d*x$')
      expect(translate('(?:\A\d*\d*x)')).to be_nil
      expect(translate('^\d*\d*x')).to be_nil
    end

    it 'gives each top-level alternative its own retry' do
      expect(translate('\A\d*\d*x\z|y')).to eq('^\d*\d*x$|y')
      expect(translate('\A\d*\d*x\z|\d*\d*y')).to be_nil
    end
  end

  describe 'JS-B65 conservatism' do
    it 'refuses the unanchored email shape but translates the anchored one' do
      expect(translate('[^@\s]+@[^@\s]+\.[^@\s]+')).to be_nil
      expect(translate('\A[^@\s]+@[^@\s]+\.[^@\s]+\z')).to eq('^[^@\t\n\v\f\r ]+@[^@\t\n\v\f\r ]+\.[^@\t\n\v\f\r ]+$')
    end

    it 'refuses a group nested inside a repeated group' do
      expect(translate('\A(?:(?:ab)+c)+\z')).to be_nil
    end
  end

  describe 'JS-B62 paths' do
    it 'refuses a sequence that expands to more than 1024 paths' do
      expect(translate("\\A#{'(?:a|b)' * 11}x\\z")).to be_nil
      expect(translate("\\A#{'(?:a|b)' * 5}x\\z")).not_to be_nil
    end
  end

  describe 'JS-I3 the built-in format presets stay translatable' do
    it 'translates the uuid, url and email presets of field_struct' do
      presets = [FieldStruct::Types::UUID, FieldStruct::Types::URL, FieldStruct::Types::Email].flat_map { |type| type.presets.values }
      presets.reject! { |regexp| regexp == FieldStruct::Types::Email.presets[:strict] }
      presets.each { |regexp| expect(FieldStruct::JSONSchema.pattern_for(regexp)).not_to be_nil, regexp.inspect }
    end
  end
end
