# frozen_string_literal: true

RSpec.describe FieldStruct::JSONSchema do
  it 'has a version, the draft URI and the shared constants' do
    expect(described_class::VERSION).to eq('1.0.0.pre1')
    expect(described_class::DRAFT).to eq('https://json-schema.org/draft/2020-12/schema')
    expect(described_class::DECIMAL_PATTERN).to eq('^-?[0-9]+\.[0-9]+$')
    expect(described_class::BLANK_STRING).to eq('type' => 'string', 'pattern' => '^[\x00\t\n\v\f\r ]*$')
    expect(described_class::BLANK_STRING).to be_frozen
    expect(described_class::EMPTY_STRING).to eq('type' => 'string', 'maxLength' => 0)
    expect(described_class::EMPTY_STRING).to be_frozen
  end

  describe 'argument errors' do
    it 'refuses a non-struct and the base class' do
      expect { described_class.generate('x') }
        .to raise_error(ArgumentError, 'FieldStruct::JSONSchema.generate expects a FieldStruct::Base subclass, got "x"')
      expect { described_class.generate(FieldStruct::Base) }
        .to raise_error(ArgumentError, /expects a FieldStruct::Base subclass, got FieldStruct::Base\z/)
    end

    it 'refuses a serialization that is not a Symbol or String' do
      expect { described_class.generate(struct, serialization: nil) }
        .to raise_error(ArgumentError, 'FieldStruct::JSONSchema.generate expects serialization: to be a Symbol, got nil')
    end

    it 'refuses a non-Regexp for pattern_for' do
      expect { described_class.pattern_for('abc') }
        .to raise_error(ArgumentError, 'FieldStruct::JSONSchema.pattern_for expects a Regexp, got "abc"')
    end
  end

  it 'JS-B17: takes serialization as a String and keeps field names for a format nobody declares' do
    klass = struct do
      required :given_name, :string
      serialize :json, given_name: 'givenName'
    end
    expect(described_class.generate(klass, serialization: 'json')['properties'].keys).to eq(['givenName'])
    expect(described_class.generate(klass, serialization: :yaml)['properties'].keys).to eq(['given_name'])
  end
end
