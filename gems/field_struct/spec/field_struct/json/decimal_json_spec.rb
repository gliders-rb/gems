# frozen_string_literal: true

RSpec.describe 'Decimals in to_json (FS-B106a)' do
  before do
    stub_const('Assay', Class.new(FieldStruct::Base) do
      required :purity, :decimal
      optional :readings, :array, of: :decimal
      optional :label_price, :decimal, json: :string
      optional :pinned, :array, of: :decimal, element: { json: :string }
      optional :extra, :value
    end)
    stub_const('Batch', Class.new(FieldStruct::Base) { optional :assays, :array, of: Assay })
  end

  let(:assay) do
    Assay.new(purity: BigDecimal('99.950'), readings: [BigDecimal('0.001'), BigDecimal('-12')],
              label_price: BigDecimal('19.99'), pinned: [BigDecimal('0.10')], extra: { 'tare' => BigDecimal('2.25') })
  end

  it 'writes decimals as exact JSON numbers, at every depth' do
    expect(assay.to_json).to eq('{"purity":99.95,"readings":[0.001,-12.0],"label_price":"19.99","pinned":["0.1"],' \
                                '"extra":{"tare":2.25}}')
  end

  it 'treats :hash values like array elements, element: { json: } included' do
    stub_const('Crucible', Class.new(FieldStruct::Base) do
      optional :yields, :hash, of: :decimal
      optional :quoted, :hash, of: :decimal, element: { json: :string }
    end)
    crucible = Crucible.new(yields: { 'gold' => '0.75' }, quoted: { 'silver' => '3.10' })
    expect(crucible.to_json).to eq('{"yields":{"gold":0.75},"quoted":{"silver":"3.1"}}')
    expect(crucible.as_json).to eq(yields: { 'gold' => '0.75' }, quoted: { 'silver' => '3.1' })
  end

  it 'reaches nested structs' do
    expect(Batch.new(assays: [assay]).to_json).to start_with('{"assays":[{"purity":99.95,')
  end

  it 'goes through as_json, so an override (and super inside it) is honoured' do
    stub_const('TaggedAssay', Class.new(Assay) do
      def as_json(_options = nil) = super.merge(lab: 'north')
    end)
    json = TaggedAssay.new(purity: '1.5').to_json
    expect(json).to start_with('{"purity":1.5,').and end_with('"lab":"north"}')
  end

  it 'leaves as_json outside to_json, and other fibers, with Strings' do
    inner = nil
    stub_const('PeekAssay', Class.new(Assay) do
      define_method(:as_json) do |_options = nil|
        inner = Fiber.new { Assay.new(purity: '2.5').as_json[:purity] }.resume
        super()
      end
    end)
    PeekAssay.new(purity: '1').to_json
    expect([inner, Assay.new(purity: '2.5').as_json[:purity]]).to eq(['2.5', '2.5'])
  end

  it 'keeps as_json as Strings' do
    expect(assay.as_json.values_at(:purity, :readings)).to eq(['99.95', ['0.001', '-12.0']])
  end

  it 'round-trips the exact value through from_json' do
    back = Assay.from_json(assay.to_json)
    expect([back.purity, back.readings, back.label_price])
      .to eq([BigDecimal('99.95'), [BigDecimal('0.001'), BigDecimal('-12')], BigDecimal('19.99')])
  end

  it 'lets a type keep strings with json_default' do
    stub_const('Ducats', Class.new(FieldStruct::Types::BigDecimal) { def self.json_default = :string })
    registry = FieldStruct::Registry.new(FieldStruct.types)
    registry.register(:ducats, Ducats)
    stub_const('Mint', Module.new)
    Mint.define_singleton_method(:field_types) { registry }
    stub_const('Mint::Coin', Class.new(FieldStruct::Base))
    Mint::Coin.required :worth, :ducats
    Mint::Coin.optional :weight, :ducats, json: :number
    expect(Mint::Coin.new(worth: '1.5', weight: '3.25').to_json).to eq('{"worth":"1.5","weight":3.25}')
    expect(FieldStruct::Types::BigDecimal.json_default).to eq(:number)
  end

  it 'refuses a json: that is not :number or :string' do
    expect { Class.new(FieldStruct::Base) { optional :rate, :decimal, json: :text } }
      .to raise_error(ArgumentError, 'json: on BigDecimal takes :number or :string, got :text')
    expect { Class.new(FieldStruct::Base) { optional :rate, :decimal, json: 'string' } }
      .to raise_error(ArgumentError, 'json: on BigDecimal expects Symbol, got String ("string")')
  end
end
