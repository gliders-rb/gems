# frozen_string_literal: true

# Fixture actions: a bicycle workshop servicing a bike.
module Workshop
  # Trues a wheel.
  class TrueWheel < Actionable::Action
    desc 'Spins each wheel and tightens spokes until it runs straight.'

    input { required :wheel_count, :integer, desc: 'How many wheels came in' }

    fails :rim_cracked, 'the rim is cracked', retry: false

    step :spin_wheel
    step :tension_spokes, unless: :already_true?

    private

    def already_true? = false
    def spin_wheel = nil
    def tension_spokes = nil
  end

  # Orders parts for a bike.
  class OrderParts < Actionable::Action
    step :place_order

    private

    def place_order = nil
  end

  # Services one bike.
  class ServiceBike < Actionable::Action
    desc 'Checks a bike in, fixes what is worn, and tells the owner it is ready.'

    input do
      required :ticket, :string, desc: 'The repair ticket | number'
      required :kind, :string, desc: 'road, mountain or cargo'
      optional :rush, :boolean
    end

    output { optional :invoice_id, :string, desc: 'The invoice sent to the owner' }

    fails :parts_missing, 'a part is out of stock', retry: true, desc: 'A part we need is not in stock'
    fails :frame_bent
    skips :already_serviced, desc: 'It was serviced this week, so nothing is done'

    step :check_in, desc: 'Check the bike in'
    step TrueWheel
    case_step :kind, desc: 'What kind of bike it is' do
      on 'road', :fit_road_brakes, desc: 'Fit rim brakes'
      on %w[mountain cargo], :bleed_discs
      default OrderParts
    end
    step :wax_chain, if: :chain_dry?

    on_success :text_owner, desc: 'Text the owner'
    on_failure :tag_bike, if: :ticket_open?
    always OrderParts

    private

    def check_in = nil
    def kind = input.kind
    def fit_road_brakes = nil
    def bleed_discs = nil
    def chain_dry? = true
    def wax_chain = nil
    def text_owner = nil
    def tag_bike = nil
    def ticket_open? = true
  end

  # Has no steps, no schema and no codes.
  class SweepFloor < Actionable::Action
  end
end
