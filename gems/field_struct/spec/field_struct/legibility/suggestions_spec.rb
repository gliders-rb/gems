# frozen_string_literal: true

RSpec.describe 'Declaration messages that suggest a fix (FS-B6, FS-B131)' do
  let(:lantern) { Class.new(FieldStruct::Base) }

  describe 'an unknown type name' do
    it 'ends with the registered name it most likely meant' do
      expect { lantern.required(:wick, :strng) }
        .to raise_error(KeyError, 'no FieldStruct type registered for :strng (did you mean :string?)')
    end

    it 'suggests for an element type in of: as well' do
      expect { lantern.optional(:wicks, :array, of: :intger) }
        .to raise_error(KeyError, 'no FieldStruct type registered for :intger (did you mean :integer?)')
    end

    it 'keeps the plain message when nothing registered is close' do
      expect { lantern.required(:wick, :zzqx) }
        .to raise_error(KeyError, 'no FieldStruct type registered for :zzqx')
    end

    it 'draws its candidates from the whole registry chain' do
      registry = FieldStruct::Registry.new(FieldStruct.types)
      registry.register(:lumen_count, FieldStruct.types.lookup(:integer))
      stub_const('Beacons', Module.new)
      Beacons.define_singleton_method(:field_types) { registry }
      stub_const('Beacons::Lamp', Class.new(FieldStruct::Base))

      expect { Beacons::Lamp.required(:glow, :lumen_cont) }
        .to raise_error(KeyError, /\(did you mean :lumen_count\?\)\z/)
    end
  end

  describe 'a Class that is not a FieldStruct type' do
    it 'names the registered type with the same short class name' do
      expect { lantern.required(:wick, String) }
        .to raise_error(ArgumentError, 'String is not a FieldStruct type (subclass FieldStruct::Types::Base); ' \
                                       'did you mean :string?')
    end

    it 'suggests :integer for Integer' do
      expect { lantern.required(:hours, Integer) }.to raise_error(ArgumentError, /; did you mean :integer\?\z/)
    end

    it 'keeps the plain message when no registered type shares the name' do
      expect { lantern.required(:wick, Comparable.class) }
        .to raise_error(ArgumentError, 'Module is not a FieldStruct type (subclass FieldStruct::Types::Base)')
    end
  end

  describe 'Scaffold.from_json with text that is not JSON' do
    it 'raises a FieldStruct::Error with the position only' do
      expect { FieldStruct::Scaffold.from_json('{"lumens": 12,,}') }
        .to raise_error(FieldStruct::Error, /\AScaffold\.from_json: input is not valid JSON \(line 1, column \d+\)\z/)
    end

    it 'never echoes a key or a value from the input' do
      FieldStruct::Scaffold.from_json('{"pilot_secret": "ember-77",,}')
    rescue FieldStruct::Error => e
      expect(e.message).not_to match(/pilot_secret|ember-77/)
    end
  end
end
