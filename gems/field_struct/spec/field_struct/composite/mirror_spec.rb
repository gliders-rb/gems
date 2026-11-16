# frozen_string_literal: true

# Sources are plain Ruby objects standing in for records: a weather station and its readings.
RSpec.describe 'mirrors and max_items: (FS-B166..FS-B170)' do
  let(:reading_class) do
    Struct.new(:celsius, :taken_at, :calibration_secret, keyword_init: true)
  end
  let(:station_class) do
    Struct.new(:code, :elevation_m, :readings, :keeper, keyword_init: true)
  end

  # A stand-in for a lazy relation: answers first(n) and counts how many it handed out.
  let(:lazy_class) do
    Class.new do
      attr_reader :served

      def initialize(rows) = (@rows = rows)

      def first(count)
        @served = count
        @rows.first(count)
      end
    end
  end

  before do
    stub_const('ReadingView', Class.new(FieldStruct::Base) do
      mirror!
      required :celsius, :float
      optional :taken_at, :time
    end)
    stub_const('KeeperView', Class.new(FieldStruct::Base) do
      mirror!
      required :name, :string
    end)
    stub_const('StationView', Class.new(FieldStruct::Base) do
      mirror!
      required :code, :string
      optional :elevation_m, :integer
      optional :readings, :array, of: ReadingView, max_items: 3
      optional :keeper, KeeperView
    end)
    stub_const('Bulletin', Class.new(FieldStruct::Base) do
      required :station, StationView
      optional :log, :array, of: ReadingView
      optional :by_hour, :hash, of: ReadingView
    end)
  end

  let(:keeper) { Struct.new(:name, :pager).new('Ines', '555') }
  let(:readings) { [reading_class.new(celsius: 4.5, calibration_secret: 'x'), reading_class.new(celsius: '5.25')] }
  let(:station) { station_class.new(code: 'PK-7', elevation_m: '2210', readings: readings, keeper: keeper) }

  describe 'FS-B166 mirror!' do
    it 'is one-way, inherited and returns true' do
      expect(StationView.mirror?).to be(true)
      expect(Class.new(StationView).mirror?).to be(true)
      expect(Bulletin.mirror?).to be(false)
      expect(FieldStruct::Base.mirror?).to be(false)
      expect(Class.new(FieldStruct::Base).mirror!).to be(true)
    end

    it 'still builds from a Hash and keeps an instance' do
      view = StationView.new(code: 'PK-1')
      expect(Bulletin.new(station: view).station).to equal(view)
      expect(Bulletin.new(station: { code: 'PK-2' }).station.code).to eq('PK-2')
    end
  end

  describe 'FS-B167 reading a source' do
    it 'reads one reader per declared field, coercing as new does, nested mirrors included' do
      bulletin = Bulletin.new(station: station)
      expect(bulletin.station).to be_a(StationView)
      expect(bulletin.station.elevation_m).to eq(2210)
      expect(bulletin.station.readings.map(&:celsius)).to eq([4.5, 5.25])
      expect(bulletin.station.keeper.to_h).to eq(name: 'Ines')
      expect(bulletin).to be_valid
    end

    it 'reads array elements and map values' do
      bulletin = Bulletin.new(station: { code: 'PK-3' }, log: readings, by_hour: { '06' => readings.first })
      expect(bulletin.log.map(&:celsius)).to eq([4.5, 5.25])
      expect(bulletin.by_hour['06'].celsius).to eq(4.5)
    end

    it 'reads only declared fields, by field name' do
      source = Object.new
      def source.name = 'Ines'
      def source.pager = raise('not declared, never read')
      expect(Bulletin.new(station: { code: 'x', keeper: source }).station.keeper.name).to eq('Ines')
    end

    it 'refuses a source missing a reader, always, before reading any' do
      source = Struct.new(:code).new('PK-9')
      expect { Bulletin.new(station: source) }.to raise_error(
        ArgumentError,
        /\AStationView mirrors #<Class:0x\h+>, but #<Class:0x\h+> has no public readers for :elevation_m, :readings, :keeper\z/
      )
      lenient = Class.new(FieldStruct::Base) do
        coercion_policy :replace
        optional :keeper, KeeperView, default: nil
      end
      expect do
        lenient.new(keeper: Object.new)
      end.to raise_error(ArgumentError, /KeeperView mirrors Object, but Object has no public reader for :name\z/)
    end

    it 'leaves a failed coercion to the policy as usual' do
      bad = station_class.new(code: 'PK-4', elevation_m: 'high', readings: [], keeper: nil)
      expect(Bulletin.new(station: bad).station.errors[:elevation_m].first).to start_with('could not be coerced')
    end

    it 'does not read through a union member' do
      either = Class.new(FieldStruct::Base) { optional :who, :union, of: [KeeperView, :integer] }
      expect(either.new(who: keeper).errors[:who].first).to start_with('could not be coerced')
    end
  end

  describe 'FS-B168 max_items:' do
    it 'is a field error past the limit, on any array' do
      capped = Class.new(FieldStruct::Base) { optional :tags, :array, of: :string, max_items: 2 }
      expect(capped.new(tags: %w[a b]).errors).to be_empty
      record = capped.new(tags: %w[a b c])
      expect(record.errors[:tags]).to eq(['has too many items (maximum is 2)'])
      expect(record.tags).to eq(%w[a b c])
    end

    it 'refuses a negative limit at declaration' do
      expect { Class.new(FieldStruct::Base) { optional :tags, :array, of: :string, max_items: -1 } }.to raise_error(
        ArgumentError, 'max_items: on Array takes a whole number from 0, got -1'
      )
      expect { Class.new(FieldStruct::Base) { optional :tags, :array, of: :string, max_items: '2' } }.to raise_error(
        ArgumentError, 'max_items: on Array expects Integer, got String ("2")'
      )
    end
  end

  describe 'FS-B169 sources for an array of mirrors' do
    it 'reads a loaded source with to_a' do
      loaded = Struct.new(:rows) do
        def loaded? = true
        def to_a = rows
      end
      bulletin = Bulletin.new(station: { code: 'PK-5' }, log: loaded.new(readings))
      expect(bulletin.log.size).to eq(2)
    end

    it 'reads a lazy source with first(max_items + 1), so going over is an error, not a cut' do
      lazy = lazy_class.new(readings * 3)
      view = StationView.new(code: 'PK-6', readings: lazy)
      expect(lazy.served).to eq(4)
      expect(view.readings.size).to eq(4)
      expect(view.errors[:readings]).to eq(['has too many items (maximum is 3)'])
    end

    it 'refuses a lazy source without max_items:, naming the field' do
      expect { Bulletin.new(station: { code: 'PK-8' }, log: lazy_class.new(readings)) }.to raise_error(
        ArgumentError, 'set max_items: on Bulletin#log, or load the relation yourself'
      )
      anonymous = Class.new(FieldStruct::Base) { optional :log, :array, of: ReadingView }
      expect { anonymous.new(log: lazy_class.new([])) }.to raise_error(ArgumentError, /\Aset max_items: on field :log,/)
    end

    it 'keeps expected Array for anything else' do
      plain = Class.new(FieldStruct::Base) { optional :tags, :array, of: :string }
      expect(plain.new(tags: lazy_class.new(%w[a])).errors[:tags].first).to include('expected Array, got')
      expect(Bulletin.new(station: { code: 'x' }, log: 42).errors[:log].first).to include('expected Array, got Integer')
    end
  end

  it 'FS-B170: exporters see a struct' do
    property = FieldStruct::Introspection.properties(Bulletin).first
    expect(property.node).to be_a(FieldStruct::Introspection::StructNode)
    expect(StationView.metadata[:readings].options[:max_items]).to eq(3)
  end
end
