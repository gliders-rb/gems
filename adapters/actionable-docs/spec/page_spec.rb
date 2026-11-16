# frozen_string_literal: true

RSpec.describe Actionable::Docs do
  describe 'naming' do
    it 'AD-B2: a title is the last name segment as words, only the first letter upper case' do
      expect(described_class.title(Workshop::ServiceBike)).to eq('Service bike')
      expect(described_class.title(Workshop::TrueWheel)).to eq('True wheel')
    end

    it 'AD-B3: a path underscores each segment' do
      expect(described_class.path_for(Workshop::ServiceBike)).to eq('workshop/service_bike.md')
    end

    it 'AD-B1: refuses anything but a named action' do
      message = /\AActionable::Docs needs a named Actionable::Action subclass, got /
      expect { described_class.markdown(Class.new(Actionable::Action)) }.to raise_error(ArgumentError, message)
      expect { described_class.markdown(String) }.to raise_error(ArgumentError, message)
      expect { described_class.title(:service) }.to raise_error(ArgumentError, message)
    end
  end

  describe 'AD-B10: a whole page' do
    it 'renders a small action exactly' do
      expect(described_class.markdown(Workshop::TrueWheel)).to eq(<<~MARKDOWN)
        # True wheel

        Spins each wheel and tightens spokes until it runs straight.

        ```mermaid
        flowchart TD
          start([Start])
          s1["Spin wheel"]
          start --> s1
          g2{"already true?"}
          s1 --> g2
          s3["Tension spokes"]
          g2 -->|no| s3
          done([Done])
          s3 --> done
          g2 -->|yes| done
          f4[/"Stops: Rim cracked"/]
          start -->|any step| f4
        ```

        ## Steps

        1. Spin wheel
        2. Tension spokes (skipped when already true)

        ## It can stop because

        - **Rim cracked**: the rim is cracked _(don't retry)_ `rim_cracked`

        ## What it needs

        | Field | Meaning | Required |
        |---|---|---|
        | Wheel count | How many wheels came in | yes |

        _Generated from the action's declarations by actionable-docs. Edit the action, not this page._
      MARKDOWN
    end

    it 'says so when there are no steps, and leaves out empty sections' do
      page = described_class.markdown(Workshop::SweepFloor)
      expect(page).to include("## Steps\n\nIt has no steps.")
      expect(page).not_to include('It can stop', 'finish early', 'What happens after', 'What it needs', 'Also runs')
    end

    it 'AD-I2: is the same text every time' do
      expect(described_class.markdown(Workshop::ServiceBike)).to eq(described_class.markdown(Workshop::ServiceBike))
    end

    it 'AD-I3: names no class' do
      expect(described_class.markdown(Workshop::ServiceBike)).not_to include('Workshop::', 'ServiceBike', 'TrueWheel')
    end
  end

  describe 'AD-B11: steps' do
    let(:page) { described_class.markdown(Workshop::ServiceBike) }

    it 'lists steps with their descriptions, child actions as links and guards in words' do
      expect(page).to include(<<~STEPS)
        ## Steps

        1. Check the bike in
        2. [True wheel](true_wheel.md)
        3. Depending on what kind of bike it is:
           - road: Fit rim brakes
           - mountain or cargo: Bleed discs
           - anything else: [Order parts](order_parts.md)
        4. Wax chain (only when chain dry)
      STEPS
    end
  end

  describe 'AD-B12 and the other sections' do
    let(:page) { described_class.markdown(Workshop::ServiceBike) }

    it 'lists failures and skips with their words, retry notes and codes' do
      expect(page).to include(<<~CODES)
        ## It can stop because

        - **Parts missing**: A part we need is not in stock _(worth retrying)_ `parts_missing`
        - **Frame bent**: Frame bent `frame_bent`

        ## It can finish early because

        - **Already serviced**: It was serviced this week, so nothing is done `already_serviced`
      CODES
    end

    it 'lists hooks under What happens after, in a fixed order' do
      expect(page).to include(<<~HOOKS)
        ## What happens after

        - When it succeeds: Text the owner
        - When it stops: Tag bike (only when ticket open)
        - Every time, at the end: [Order parts](order_parts.md)
      HOOKS
    end

    it 'tables the input and output, escaping a pipe' do
      expect(page).to include(<<~FIELDS)
        ## What it needs

        | Field | Meaning | Required |
        |---|---|---|
        | Ticket | The repair ticket \\| number | yes |
        | Kind | road, mountain or cargo | yes |
        | Rush | — | no |

        ## What it produces

        | Field | Meaning | Required |
        |---|---|---|
        | Invoice id | The invoice sent to the owner | no |
      FIELDS
    end

    it 'says a dispatched input takes one of several shapes' do
      road = Class.new(FieldStruct::Base) { required :ticket, :string }
      stub_const('Workshop::Intake', Class.new(Actionable::Action) { input_for(:kind) { on 'road', road } })
      expect(described_class.markdown(Workshop::Intake)).to include("## What it needs\n\nIt takes one of several input shapes.")
    end
  end
end
