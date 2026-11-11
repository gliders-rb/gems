# frozen_string_literal: true

require 'bigdecimal'

# Regression guard for the performance pass: objects allocated per construction and per dump of a representative
# struct. Counts do not depend on YJIT or machine speed. Ceilings are the measured count plus 10%; if a change
# trips one, find the new allocation before raising the number.
RSpec.describe 'allocations per operation', :allocations do
  let(:crate_class) do
    Class.new(FieldStruct::Base) do
      def self.name = 'AllocationCrate'

      required :serial, :string
      required :count, :integer
      required :weight, :decimal, round: 2
      required :fragile, :boolean
      required :packed_on, :date
      required :shipped_at, :time, zone: 'America/Denver', format: :iso8601
      optional :note, :string
      optional :labels, :array, of: :string
      optional :kind, :symbol, enum: %i[box pallet]
      serialize :json, packed_on: 'packedOn', shipped_at: 'shippedAt'
    end
  end
  let(:input) do
    { serial: 'C-1001', count: '12', weight: '4.256', fragile: 'true', packed_on: '2026-07-01',
      shipped_at: '2026-07-01T08:15:30-06:00', note: 'handle with care', labels: %w[a b], kind: 'box' }.freeze
  end

  def allocations_of(&block)
    runs = 50
    runs.times(&block)
    GC.start
    GC.disable
    before = GC.stat(:total_allocated_objects)
    runs.times(&block)
    (GC.stat(:total_allocated_objects) - before).fdiv(runs)
  ensure
    GC.enable
  end

  it 'constructs from a Hash within 74 objects' do
    # Ruby 3.3's VM allocates more for the same code: measured 81 there, 67 on 3.4+.
    expect(allocations_of { crate_class.new(input) }).to be <= (RUBY_VERSION < '3.4' ? 89 : 74)
  end

  it 'dumps to JSON within 25 objects' do
    crate = crate_class.new(input)
    expect(allocations_of { crate.to_json }).to be <= 25 # measured 22
  end

  it 'reports validity without allocating' do
    crate = crate_class.new(input)
    expect(allocations_of { crate.valid? }).to be < 0.5 # none per call; tolerates one stray object in the sample
  end
end
