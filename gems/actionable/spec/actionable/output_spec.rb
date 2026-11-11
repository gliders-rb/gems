# frozen_string_literal: true

RSpec.describe 'Action output' do
  def action_with(output_block = nil, &body)
    build_action do
      output(&output_block) if output_block
      step :sail
      define_method(:sail, &body)
      private :sail
    end
  end

  describe 'declaration' do
    it 'AC-B#outputdecl: builds a FieldStruct schema from the block; no block reads; subclasses share it' do
      action = build_action { output { required :fare, :integer } }
      expect(action.output).to be < FieldStruct::Base
      expect(action.output_schema).to equal(action.output)
      expect(action.output.attribute_names).to eq(%i[fare])
      expect(build_action(action).output).to equal(action.output)
      expect(build_action.output).to be_nil
    end

    it 'AC-B#reservedout: refuses result attributes, public Result methods and action names, listing them all' do
      expect do
        build_action do
          output do
            required :code, :string
            required :status, :string
            required :to_h, :string
            required :result, :string
            required :input, :string
            required :ok?, :string
            optional :fine, :string
          end
        end
      end.to raise_error(Actionable::DefinitionError,
                         'action: output field(s) :code, :status, :to_h, :result, :input, :ok? conflict with reserved ' \
                         'result attributes / methods / instance variables; rename them')
    end

    it 'AC-B#reservedout: names the action when it has a name' do
      expect do
        named_action('Reserved') { output { required :message, :string } }
      end.to raise_error(Actionable::DefinitionError, /\AReserved: output field\(s\) :message conflict/)
    end

    it 'AC-B#reservedout: covers metadata, history, errors and output_fields_set' do
      %i[metadata history errors output output_fields_set absorb_errors_from].each do |name|
        expect { build_action { output { optional name, :string } } }.to raise_error(Actionable::DefinitionError, /#{name.inspect}/)
      end
    end

    it 'AC-B#reservedout: input field names are not guarded' do
      expect { build_action { input { required :code, :string } } }.not_to raise_error
    end
  end

  describe 'refresh' do
    it 'AC-B#refresh: a success is built from declared fields whose ivars are defined' do
      action = action_with(proc { required :fare, :integer }) { @fare = 5 }
      result = action.run
      expect(result).to be_success
      expect(result.output).to be_a(action.output)
      expect(result.fare).to eq(5)
      expect(result.output_fields_set).to eq(%i[fare])
    end

    it 'AC-B#refresh: a defined nil counts as set' do
      action = action_with(proc { optional :note, :string }) { @note = nil }
      expect(action.run.output_fields_set).to eq(%i[note])
      expect(action_with(proc { optional :note, :string }) { nil }.run.output_fields_set).to eq([])
    end

    it 'AC-B#coerceout: values are coerced; undeclared ivars never appear' do
      action = action_with(proc {
        required :fare, :integer
        required :s, :string
      }) do
        @fare = '42'
        @s = 3
        @secret = 'x'
      end
      result = action.run
      expect([result.fare, result.s]).to eq([42, '3'])
      expect(result.output.to_h.keys).to eq(%i[fare s])
      expect { result.secret }.to raise_error(NoMethodError)
    end

    it 'AC-B#succeedkw: keywords that match no declared field are dropped when a schema exists' do
      action = action_with(proc { required :fare, :integer }) { succeed(fare: 1, stray: 2) }
      expect(action.run.output.to_h).to eq(fare: 1)
    end

    it 'AC-B#kwargswin: keywords override ivars and satisfy a required field' do
      action = action_with(proc { required :fare, :integer }) do
        @fare = 1
        succeed(fare: 99)
      end
      expect(action.run.fare).to eq(99)
      only_kw = action_with(proc { required :fare, :integer }) { succeed(fare: 7) }
      expect(only_kw.run.fare).to eq(7)
    end

    it 'AC-B#kwargswin: keywords stay in force across later refreshes of the same result' do
      action = action_with(proc { required :fare, :integer }) { succeed(fare: 99) }
      instance = action.new
      instance.__send__(:sail)
      runner = Actionable::Runner.new(instance)
      2.times { runner.__send__(:refresh_output) }
      expect(instance.result.fare).to eq(99)
    end

    it 'AC-B#freeformout: no schema keeps the keyword Hash; auto-success leaves {}' do
      result = action_with { succeed(a: 1) }.run
      expect(result.output).to eq(a: 1)
      expect { result.a }.to raise_error(NoMethodError)
      expect(action_with { @x = 1 }.run.output).to eq({})
    end

    it 'AC-B#hashoutput: verbs never raise for an unknown output keyword' do
      expect { action_with { skip(:x, nil, anything: 1) }.run }.not_to raise_error
    end
  end

  describe 'invalid output' do
    it 'AC-B#invalidout: a required field never set becomes Failure(:invalid_output) carrying the invalid struct' do
      action = action_with(proc { required :fare, :integer }) { @other = 1 }
      result = action.run
      expect(result).to be_failure
      expect([result.code, result.message]).to eq([:invalid_output, 'output failed validation'])
      expect(result.errors.to_h).to eq(fare: ['is required'])
      expect(result.output.valid?).to be(false)
      expect(result.metadata).to eq({})
    end

    it 'AC-B#invalidout: a value that will not coerce is invalid too, without the incidental output error' do
      action = action_with(proc { required :fare, :integer }) { @fare = 'adrift' }
      result = action.run
      expect(result.code).to eq(:invalid_output)
      expect(result.errors.to_h.keys).to eq(%i[fare])
    end

    it 'AC-B#invalidoutstays: refreshing a gem-built failure keeps the invalid output' do
      action = action_with(proc { required :fare, :integer }) { @other = 1 }
      instance = action.new
      runner = Actionable::Runner.new(instance)
      runner.run
      2.times { runner.__send__(:refresh_output) }
      failure = instance.result
      expect(failure.code).to eq(:invalid_output)
      expect(failure.output.valid?).to be(false)
      expect(failure.errors.to_h).to eq(fare: ['is required'])
    end
  end

  describe 'failures and skips without their own schema' do
    let(:out) do
      proc {
        required :fare, :integer
        optional :note, :string
      }
    end

    it 'AC-B#failureoutput: a failure gets a best-effort struct of what was set, unvalidated, no errors added' do
      action = action_with(out) do
        @note = 'hi'
        fail!(:adrift)
      end
      result = action.run
      expect(result.output).to be_a(action.output)
      expect([result.output.fare, result.output.note]).to eq([nil, 'hi'])
      expect(result.errors.to_h).to eq({})
      expect(result.output.valid?).to be(false)
    end

    it 'AC-B#skipoutput: skip keywords are captured best-effort and never validated' do
      action = action_with(proc { optional :existing_id, :integer }) { skip!(:duplicate, 'seen', existing_id: 42) }
      result = action.run
      expect(result).to be_skipped
      expect(result.existing_id).to eq(42)
    end

    it 'AC-B#skipoutput: without a schema the keywords stay a Hash' do
      expect(action_with { skip!(:duplicate, 'seen', existing_id: 42) }.run.output).to eq(existing_id: 42)
    end

    it 'AC-B#refresh: a caller-recorded output error on a failure survives the clearing' do
      action = action_with(out) { fail!(:adrift, nil, output: 'recorded') }
      result = action.run
      expect(result.errors[:output]).to eq(['recorded'])
    end
  end

  it 'AC-B#resultreserved: leaving a non-Result in @result raises DefinitionError' do
    named_action('Clobber') do
      step :sail
      define_method(:sail) { @result = 'oops' }
      private :sail
    end
    expect { Clobber.run }.to raise_error(Actionable::DefinitionError,
                                          "Clobber set @result to a String; @result is reserved for the run's result, " \
                                          'so rename the instance variable')
  end

  it 'AC-B#resultreserved: a Result the step builds and assigns is accepted' do
    action = build_action do
      step :sail
      define_method(:sail) { @result = Actionable::Failure.new(code: :mine) }
      private :sail
    end
    expect(action.run.code).to eq(:mine)
  end
end
