# frozen_string_literal: true

RSpec.describe 'FieldStruct.register_option' do
  def declare(type = :string, name: 'Herbarium::Sheet', **options)
    klass = Class.new(FieldStruct::Base)
    stub_const(name, klass) if name
    klass.field(:genus, type, **options)
    klass
  end

  describe 'FS-B10 unknown keys' do
    it 'refuses a key nobody declares or registers, naming the class and field' do
      expect { declare(ribbon: 'x') }.to raise_error(ArgumentError, 'unknown option ribbon: on Herbarium::Sheet#genus')
    end

    it 'suggests a close native, universal or registered key' do
      expect do
        declare(:float, rund: 2)
      end.to raise_error(ArgumentError, 'unknown option rund: on Herbarium::Sheet#genus (did you mean round:?)')
      expect { declare(sensitiv: true) }.to raise_error(ArgumentError, /\(did you mean sensitive:\?\)\z/)
      expect { declare(shelf_mak: 'B4') }.to raise_error(ArgumentError, /\(did you mean shelf_mark:\?\)\z/)
    end

    it 'labels a field of an anonymous class by its name' do
      expect { declare(name: nil, ribbon: 'x') }.to raise_error(ArgumentError, 'unknown option ribbon: on field :genus')
    end

    it 'says to require the adapter when its key is used before it is loaded' do
      expect { declare(proto: { number: 1 }) }.to raise_error(
        ArgumentError,
        'unknown option proto: on Herbarium::Sheet#genus; proto: is registered by field_struct-protobuf, ' \
        "so require 'field_struct/protobuf' before declaring the field"
      )
      expect do
        declare(avro: {})
      end.to raise_error(ArgumentError, %r{avro: is registered by field_struct-avro, so require 'field_struct/avro'})
      expect { declare(json_schema: false) }.to raise_error(ArgumentError, %r{require 'field_struct/json_schema'})
    end

    it 'still refuses a registered key inside element:' do
      expect { declare(:array, of: :string, element: { shelf_mark: 'B4' }) }.to raise_error(
        ArgumentError, /in element: of array field :genus, shelf_mark: is not a String option/
      )
    end
  end

  describe 'FS-B10a registered keys' do
    it 'stores a registered key verbatim, on scalar and nested fields' do
      expect(declare(shelf_mark: 'B4').metadata[:genus].options).to eq(shelf_mark: 'B4')
      stub_const('Herbarium::Label', Class.new(FieldStruct::Base) { optional :ink, :string })
      expect(declare(Herbarium::Label, archive: { box: 3 }).metadata[:genus].options).to include(archive: { box: 3 })
    end

    it 'checks the value against the registered classes, allowing nil' do
      expect { declare(:integer, archive: 5) }.to raise_error(ArgumentError, 'archive: on Integer expects Hash, got Integer (5)')
      expect { declare(archive: nil) }.not_to raise_error
    end

    it 'returns the name, is idempotent and lists entries in registration order' do
      expect(FieldStruct.register_option(:shelf_mark, type: String, owner: 'field_struct specs')).to eq(:shelf_mark)
      entry = FieldStruct.registered_options.fetch(:shelf_mark)
      expect(entry).to be_a(FieldStruct::RegisteredOption).and be_frozen
      expect([entry.name, entry.type, entry.owner]).to eq([:shelf_mark, [String], 'field_struct specs'])
      expect(FieldStruct.registered_options).to be_frozen
      expect(FieldStruct.registered_options.keys.first(2)).to eq(%i[shelf_mark archive])
    end

    it 'takes an Array of classes' do
      FieldStruct.register_option(:pressing, type: [Hash, TrueClass, FalseClass], owner: 'field_struct specs')
      expect { declare(pressing: true) }.not_to raise_error
      expect do
        declare(pressing: 'yes')
      end.to raise_error(ArgumentError, 'pressing: on String expects Hash or TrueClass or FalseClass, got String ("yes")')
    end
  end

  describe 'FS-B10a refusals' do
    it 'refuses a changed type or owner' do
      expect { FieldStruct.register_option(:shelf_mark, type: String, owner: 'another gem') }.to raise_error(
        ArgumentError,
        'shelf_mark: is already registered by field_struct specs (type String); register it again only with the same type: and owner:'
      )
      expect do
        FieldStruct.register_option(:shelf_mark, type: Symbol, owner: 'field_struct specs')
      end.to raise_error(ArgumentError, /already registered/)
    end

    it 'refuses universal and built-in native keys' do
      expect { FieldStruct.register_option(:desc, type: String, owner: 'x') }.to raise_error(
        ArgumentError, "desc: is a universal field option, so it can't be registered"
      )
      expect { FieldStruct.register_option(:round, type: Integer, owner: 'x') }.to raise_error(
        ArgumentError, "round: is a native option of Float, BigDecimal, so it can't be registered"
      )
    end

    it 'checks its arguments' do
      expect { FieldStruct.register_option('stem', type: String, owner: 'x') }.to raise_error(
        ArgumentError, 'register_option takes the option name as a Symbol, got String ("stem")'
      )
      expect { FieldStruct.register_option(:stem, type: 'Hash', owner: 'x') }.to raise_error(
        ArgumentError, 'register_option type: must be a Class or an Array of Classes, got "Hash"'
      )
      expect { FieldStruct.register_option(:stem, type: [], owner: 'x') }.to raise_error(ArgumentError, /type: must be a Class/)
      expect { FieldStruct.register_option(:stem, type: String, owner: nil) }.to raise_error(
        ArgumentError, 'register_option owner: must name the gem or app that reads the option, got nil'
      )
      expect { FieldStruct.register_option(:stem, type: String, owner: ' ') }.to raise_error(ArgumentError, /owner: must name/)
      expect { FieldStruct.register_option(:stem, type: String) }.to raise_error(ArgumentError, /missing keyword: :owner/)
      expect(FieldStruct.registered_options).not_to have_key(:stem)
    end
  end
end
