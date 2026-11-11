# frozen_string_literal: true

RSpec.describe FieldStruct::Base, 'declaration-time option validation' do
  def declare(type, **options)
    klass = Class.new(described_class)
    klass.field(:x, type, **options)
    klass
  end

  describe 'FS-B9 option on the wrong type' do
    it 'names where the option does apply' do
      expect { declare(:integer, round: 2) }.to raise_error(
        ArgumentError, 'round: option does not apply to Integer fields. It applies to: Float, BigDecimal.'
      )
      expect do
        declare(:integer, enum: [1])
      end.to raise_error(ArgumentError, /enum: option does not apply to Integer fields\. It applies to: /)
      expect { declare(:string, in: 1..2) }.to raise_error(ArgumentError, /in: option does not apply to String fields/)
      expect do
        declare(:string, base: 2)
      end.to raise_error(ArgumentError, 'base: option does not apply to String fields. It applies to: Integer.')
    end

    it 'lists string-family types for strict: in registry order' do
      expect { declare(:float, strict: true) }.to raise_error(
        ArgumentError,
        'strict: option does not apply to Float fields. It applies to: String, ImmutableString, Integer, UUID, URL, Email, Binary.'
      )
    end

    it 'treats keys of custom registered types as reserved for every other type in the chain' do
      custom = Class.new(FieldStruct::Types::Base) do
        def self.own_option_schema = { sparkle: option(type: Integer) }
        def coerce(value, **) = value
        def ruby_type = Object
      end
      stub_const('Sparkly', custom)
      registry = FieldStruct.new_registry { register :sparkly, Sparkly }
      stub_const('Shiny', Module.new.tap { |m| m.define_singleton_method(:field_types) { registry } })
      klass = stub_const('Shiny::Thing', Class.new(described_class))
      expect do
        klass.field :a, :string,
                    sparkle: 1
      end.to raise_error(ArgumentError, 'sparkle: option does not apply to String fields. It applies to: Sparkly.')
      expect { klass.field :a, :sparkly, sparkle: 1 }.not_to raise_error
    end
  end

  describe 'FS-B10 pass-through options' do
    it 'stores unknown keys verbatim on the Field' do
      klass = declare(:integer, avro_doc: 'the id', proto: { tag: 1 })
      expect(klass.metadata[:x].options).to include(avro_doc: 'the id', proto: { tag: 1 })
    end

    it 'FS-B11: keeps universal options off Field#options' do
      klass = declare(:string, required: true, default: 'a', desc: 'd', rbs_type: '::String', sensitive: true, coercion_policy: :replace)
      expect(klass.metadata[:x].options).to eq({})
      expect(klass.metadata[:x]).to be_required.and be_sensitive
    end
  end

  describe 'FS-B8 option shapes' do
    it 'raises the generic shape message' do
      expect { declare(:float, round: '2') }.to raise_error(ArgumentError, 'round: on Float expects Integer, got String ("2")')
      expect do
        declare(:string, strict: 1)
      end.to raise_error(ArgumentError, 'strict: on String expects TrueClass or FalseClass, got Integer (1)')
      expect { declare(:integer, in: 5) }.to raise_error(ArgumentError, 'in: on Integer expects Array or Range, got Integer (5)')
      expect { declare(:boolean, values: 5) }.to raise_error(ArgumentError, 'values: on Boolean expects Hash or Symbol, got Integer (5)')
      expect { declare(:string, format: 'x') }.to raise_error(ArgumentError, 'format: on String expects Regexp or Symbol, got String ("x")')
    end

    it 'accepts nil for any native option' do
      expect { declare(:float, round: nil) }.not_to raise_error
      expect { declare(:string, enum: nil) }.not_to raise_error
    end

    it 'checks the shape after the wrong-type check' do
      expect { declare(:integer, round: 'x') }.to raise_error(ArgumentError, /does not apply to Integer/)
    end
  end

  describe 'type-specific resolve_options' do
    it 'checks base: range' do
      expect { declare(:integer, base: 40) }.to raise_error(ArgumentError, 'base: on Integer expects an Integer from 2 to 36, got 40')
      expect { declare(:integer, base: 1) }.to raise_error(ArgumentError, /from 2 to 36, got 1/)
      expect { declare(:integer, base: 36) }.not_to raise_error
    end

    it 'resolves boolean presets and rejects unknown ones' do
      expect(declare(:boolean, values: :numeric).metadata[:x].options[:values]).to eq(truthy: ['1'], falsy: ['0'])
      expect { declare(:boolean, values: :nope) }.to raise_error(
        ArgumentError, 'unknown :boolean values preset :nope. Available: [:english_yes_no, :english, :numeric]'
      )
    end
  end

  describe 'FS-B7 default format prefill' do
    it 'prefills format: last, after the declared options' do
      options = declare(:uuid, enum: ['a']).metadata[:x].options
      expect(options.keys).to eq(%i[enum format])
      expect(options[:format]).to equal(FieldStruct::Types::UUID.default_format)
    end

    it 'keeps an explicit format: nil and a user-given Regexp' do
      expect(declare(:email, format: nil).metadata[:x].options).to eq(format: nil)
      expect(declare(:url, format: /x/).metadata[:x].options[:format]).to eq(/x/)
    end

    it 'resolves presets to Regexps, rejects unknown ones' do
      expect(declare(:uuid, format: :v4).metadata[:x].options[:format]).to eq(FieldStruct::Types::UUID::PRESETS[:v4])
      expect(declare(:url, format: :https_only).metadata[:x].options[:format]).to eq(FieldStruct::Types::URL::PRESETS[:https_only])
      expect do
        declare(:uuid, format: :zz)
      end.to raise_error(ArgumentError, 'unknown :uuid format preset :zz. Available: [:any_version, :v4, :v7]')
      expect do
        declare(:url, format: :zz)
      end.to raise_error(ArgumentError, 'unknown :url format preset :zz. Available: [:http, :https_only, :any_scheme]')
      expect do
        declare(:email,
                format: :zz)
      end.to raise_error(ArgumentError, 'unknown :email format preset :zz. Available: [:permissive, :default, :strict]')
    end

    it 'FS-B57: leaves a Symbol format on plain :string unresolved and never validates with it' do
      klass = Class.new(described_class) { field :s, :string, format: :whatever }
      expect(klass.metadata[:s].options[:format]).to eq(:whatever)
      expect(klass.new(s: 'anything')).to be_valid
    end

    it 'FS-B163: a subclass overriding default_format changes the stored default' do
      loose = Class.new(FieldStruct::Types::UUID) { def self.default_format = /\Aok\z/ }
      stub_const('LooseUuid', loose)
      klass = Class.new(described_class) { field :id, LooseUuid }
      expect(klass.metadata[:id].options[:format]).to eq(/\Aok\z/)
      expect(klass.new(id: 'ok')).to be_valid
    end
  end

  describe 'FS-B12 description / desc' do
    it 'treats them as aliases and refuses both' do
      expect(declare(:string, description: 'D').metadata[:x]).to have_attributes(description: 'D', desc: 'D')
      expect(declare(:string, desc: 'D').metadata[:x]).to have_attributes(description: 'D', desc: 'D')
      expect { declare(:string, desc: 'a', description: 'b') }.to raise_error(ArgumentError, 'pass either description: or desc:, not both')
    end

    it 'lets a subclass replace the description with nil' do
      parent = Class.new(described_class) { field :x, :string, desc: 'old' }
      child = Class.new(parent) { field :x, :string }
      expect(child.metadata[:x].description).to be_nil
      expect(parent.metadata[:x].description).to eq('old')
    end
  end

  describe 'FS-B14 universal option values' do
    it 'checks rbs_type:' do
      expect { declare(:string, rbs_type: ' ') }.to raise_error(
        ArgumentError, "rbs_type: must be a non-empty String of RBS (e.g. rbs_type: '::ActiveRecord::Relation'), got \" \""
      )
      expect { declare(:string, rbs_type: 5) }.to raise_error(ArgumentError, /got 5\z/)
      expect(declare(:string, rbs_type: '::String').metadata[:x].rbs_type).to eq('::String')
      expect { declare(:string, rbs_type: nil) }.not_to raise_error
    end

    it 'checks sensitive:' do
      expect { declare(:string, sensitive: 1) }.to raise_error(ArgumentError, 'sensitive: must be true or false, got Integer')
      expect(declare(:string, sensitive: false).metadata[:x]).not_to be_sensitive
      expect(declare(:string, sensitive: true).metadata[:x]).to be_sensitive
    end
  end

  describe 'R1 check order' do
    it 'reports a reserved name before anything else' do
      expect { Class.new(described_class).field(:errors, :nope, round: 'x') }.to raise_error(ArgumentError, /is reserved/)
    end

    it 'reports universal option problems before an unknown type' do
      expect { declare(:nope, sensitive: 1) }.to raise_error(ArgumentError, /sensitive: must be/)
      expect { declare(:nope) }.to raise_error(KeyError, 'no FieldStruct type registered for :nope')
    end

    it 'reports wrong-type keys before shape problems' do
      expect { declare(:string, round: 'x') }.to raise_error(ArgumentError, /does not apply to String/)
    end
  end
end
