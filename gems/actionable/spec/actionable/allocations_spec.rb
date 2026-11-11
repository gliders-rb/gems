# frozen_string_literal: true

require 'bigdecimal'

# Regression guard for the performance pass: objects allocated per run of a typed five-step action. Counts do
# not depend on YJIT or machine speed. Ceilings are the measured count plus 10%; if a change trips one, find the
# new allocation before raising the number.
RSpec.describe 'allocations per run', :allocations do
  let(:action_class) do
    named_action('AllocationFreight') do
      input do
        required :lane, :string
        required :pallets, :integer, in: 1..1000
        required :rate, :decimal, round: 2
        required :contact, :email
        optional :coupon, :string
      end
      output do
        required :charge, :decimal, round: 2
        required :band, :symbol, enum: %i[ok review]
        required :ticket, :string
      end
      fails :overweight, 'too heavy'

      step :weigh
      step :base
      step :rebate
      step :levy
      step :settle

      def weigh = (fail!(:overweight) if input.pallets > 500)
      def base = @gross = input.rate * input.pallets
      def rebate = @gross -= (input.coupon ? @gross * BigDecimal('0.1') : 0)
      def levy = @taxed = @gross * BigDecimal('1.08')

      def settle
        @charge = @taxed
        @band = @charge > 1000 ? :review : :ok
        @ticket = "T-#{input.lane}"
      end
    end
  end
  let(:good) { { lane: 'L-1', pallets: '3', rate: '19.99', contact: 'ana@example.com', coupon: 'SAVE' }.freeze }
  let(:heavy) { good.merge(pallets: '900').freeze }

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

  it 'runs a successful five-step typed action within 52 objects' do
    expect(action_class.run(**good)).to be_success
    # Ruby 3.3's VM allocates more for the same code: measured 64 there, 47 on 3.4+.
    expect(allocations_of { action_class.run(**good) }).to be <= (RUBY_VERSION < '3.4' ? 70 : 52)
  end

  it 'runs a declared failure within 52 objects' do
    expect(action_class.run(**heavy).code).to eq(:overweight)
    # Measured 60 on Ruby 3.3, 47 on 3.4+.
    expect(allocations_of { action_class.run(**heavy) }).to be <= (RUBY_VERSION < '3.4' ? 66 : 52)
  end

  it 'keeps no history, and allocates none for it, when the run is not measured' do
    measured = Class.new(action_class) { measure :all }
    expect(action_class.run(**good).history).to eq([])
    expect(measured.run(**good).history.steps.size).to eq(5)
    expect(allocations_of { action_class.run(**good) }).to be < allocations_of { measured.run(**good) }
  end
end
