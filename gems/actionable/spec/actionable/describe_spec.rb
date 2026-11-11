# frozen_string_literal: true

RSpec.describe 'Action introspection' do
  let(:probe) do
    named_action('Probe') do
      output { required :count, :integer }
      step :compute

      private

      def compute = @count = 1
    end
  end

  describe '.describe' do
    it 'AC-B#describe: has exactly the documented keys' do
      expect(probe.describe.keys).to eq(%i[name input output steps failures skips hooks measure transactional])
    end

    it 'AC-B#describe: free-form action with one step' do
      description = probe.describe
      expect(description[:name]).to eq('Probe')
      expect(description[:input]).to be_nil
      expect(description[:output]).to eq(probe.output_schema.metadata.to_h)
      expect(description[:steps]).to eq([{ type: :method, name: :compute, options: {} }])
      expect(description[:failures]).to eq({})
      expect(description[:skips]).to eq({})
      expect(description[:hooks]).to eq(on_success: [], on_failure: [], on_skip: [], always: [])
      expect([description[:measure], description[:transactional]]).to eq([:none, nil])
    end

    it 'AC-B#describe: anonymous actions have a nil name; fixed input is its metadata' do
      action = build_action { input { required :n, :integer } }
      expect(action.describe[:name]).to be_nil
      expect(action.describe[:input]).to eq(action.input_schema.metadata.to_h)
    end

    it 'AC-B#describe: steps list kinds, action classes and options; hooks list names' do
      child = named_action('DescribeChild') { nil }
      action = build_action do
        step :a, if: :sail
        step child, input: %i[x]
        case_step(:kind) { on 'a', :b }
        on_success :s
        on_failure :f
        on_skip :k
        always child
      end
      expect(action.describe[:steps]).to eq([
                                              { type: :method, name: :a, options: { if: :sail } },
                                              { type: :action, name: child, options: { input: %i[x] } },
                                              { type: :case, name: :kind, options: {} }
                                            ])
      expect(action.describe[:hooks]).to eq(on_success: [:s], on_failure: [:f], on_skip: [:k], always: [child])
    end

    it 'AC-B#describe: a dispatched input reports the discriminator and the match values' do
      freight = Class.new(FieldStruct::Base)
      other = Class.new(FieldStruct::Base)
      action = build_action do
        input_for(:manifest_kind) do
          on 'freight', freight
          on %w[rebate return], other
          default other
        end
      end
      expect(action.describe[:input]).to eq(discriminated_on: :manifest_kind, shapes: ['freight', %w[rebate return]])
    end
  end

  describe '.describe_text' do
    it 'AC-B#describetext: header, free-form input, output fields and steps' do
      field_lines = probe.output_schema.metadata.describe.lines(chomp: true).map { |line| "  #{line}" }
      expected = ['Probe (measure: none)', '  Input: (free-form)', '  Output:', *field_lines,
                  '  Steps:', '    - compute (method)'].join("\n")
      expect(probe.describe_text).to eq(expected)
    end

    it 'AC-B#describetext: free-form output, no steps, anonymous label and measure mode' do
      action = build_action { measure :all }
      expect(action.describe_text).to eq(
        "action (measure: all)\n  Input: (free-form)\n  Output: (free-form)\n  Steps:\n    (none)"
      )
    end

    it 'AC-B#describetext: an empty schema renders FieldStruct (no fields) line' do
      action = build_action { input { nil } }
      expect(action.describe_text.lines(chomp: true)[1..2]).to eq(['  Input:', '  (no fields)'])
    end

    it 'AC-B#describetext: dispatched input and hooks, only non-empty sections' do
      one = Class.new(FieldStruct::Base)
      child = named_action('TextChild') { nil }
      action = build_action do
        input_for(:manifest_kind) do
          on 'freight', one
          on %w[a b], one
        end
        step child
        case_step(:kind) { on 'a', :b }
        on_success :s1
        on_success :s2
        always :z
      end
      text = action.describe_text
      expect(text).to include('  Input: (discriminated on manifest_kind: "freight", ["a", "b"])')
      expect(text).to include("  Steps:\n    - TextChild (action)\n    - kind (case)")
      expect(text).to end_with("  Hooks:\n    on_success: s1, s2\n    always: z")
      expect(text).not_to include('on_failure')
      expect(text).not_to end_with("\n")
    end
  end
end
