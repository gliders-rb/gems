# frozen_string_literal: true

require_relative 'rails_helper'

RSpec.describe 'Rails adapter: transactional' do
  describe 'AC-B#transactional' do
    it 'stores the model and options and reads them back' do
      klass = build_action { transactional model: Voyage, isolation: :serializable }
      expect(klass.transaction_config).to eq(model: Voyage, options: { isolation: :serializable })
    end

    it 'is nil when no ancestor set one' do
      expect(build_action.transaction_config).to be_nil
    end

    it 'is inherited from the nearest ancestor and overridable' do
      parent = build_action { transactional model: Voyage }
      child = Class.new(parent)
      grandchild = Class.new(child) { transactional model: :voyage, requires_new: false }
      expect(child.transaction_config).to eq(model: Voyage, options: {})
      expect(grandchild.transaction_config).to eq(model: :voyage, options: { requires_new: false })
    end
  end

  describe 'AC-B#txrun' do
    def tx_action(tag: 'a', &body)
      build_action do
        transactional model: Voyage
        step :write
        define_method(:write) { Voyage.create!(tag: tag) }
        class_eval(&body) if body
      end
    end

    it 'commits a success' do
      expect(tx_action.run).to be_success
      expect(Voyage.count).to eq(1)
    end

    it 'commits a skip' do
      action = build_action do
        transactional model: Voyage
        step :write
        def write
          Voyage.create!(tag: 'x')
          skip(:nothing_more)
        end
      end
      expect(action.run).to be_skipped
      expect(Voyage.count).to eq(1)
    end

    it 'rolls back a recorded failure and returns the failure' do
      action = build_action do
        transactional model: Voyage
        step :write
        def write
          Voyage.create!(tag: 'x')
          fail!(:adrift, 'no')
        end
      end
      result = action.run
      expect(result).to be_failure
      expect(result.code).to eq(:adrift)
      expect(Voyage.count).to eq(0)
    end

    it 'rolls back a raised exception and propagates it' do
      action = build_action do
        transactional model: Voyage
        step :write
        def write
          Voyage.create!(tag: 'x')
          raise 'kraken'
        end
      end
      expect { action.run }.to raise_error(RuntimeError, 'kraken')
      expect(Voyage.count).to eq(0)
    end

    it 'rolls back a failure adopted from an on_success hook' do
      action = build_action do
        transactional model: Voyage
        step :write
        on_success :late
        def write = Voyage.create!(tag: 'x')
        def late = fail!(:late_no)
      end
      expect(action.run.code).to eq(:late_no)
      expect(Voyage.count).to eq(0)
    end

    it 'runs all four hook kinds, always included, inside the transaction' do
      seen = []
      action = build_action do
        transactional model: Voyage
        step :one
        on_success :a
        always :b
        define_method(:one) { seen << [:step, Voyage.connection.transaction_open?] }
        define_method(:a) { seen << [:success, Voyage.connection.transaction_open?] }
        define_method(:b) { seen << [:always, Voyage.connection.transaction_open?] }
      end
      action.run
      expect(seen).to eq([[:step, true], [:success, true], [:always, true]])
    end

    it 'writes made by an always hook share the failed run fate' do
      action = build_action do
        transactional model: Voyage
        step :one
        always :audit
        def one = fail!(:bad)
        def audit = Voyage.create!(tag: 'audit')
      end
      action.run
      expect(Voyage.count).to eq(0)
    end

    it 'resolves a Symbol or String model by camelize and constantize' do
      %i[voyage Voyage].each do |model|
        action = build_action do
          transactional model: model
          step :write
          def write = Voyage.create!(tag: 'x')
        end
        expect { action.run }.to change(Voyage, :count).by(1)
      end
      action = build_action do
        transactional model: 'voyage'
        step :write
        def write = Voyage.create!(tag: 'x')
      end
      expect { action.run }.to change(Voyage, :count).by(1)
    end
  end

  describe 'AC-B#txsavepoint' do
    let(:inner) do
      build_action do
        transactional model: Voyage
        step :write
        def write
          Voyage.create!(tag: 'inner')
          fail!(:inner_no)
        end
      end
    end

    it 'takes its own savepoint inside an open transaction' do
      Voyage.transaction do
        Voyage.create!(tag: 'outer')
        inner.run
      end
      expect(Voyage.pluck(:tag)).to eq(['outer'])
    end

    it 'passes requires_new: true when a transaction is open and none was given' do
      allow(Voyage).to receive(:transaction).and_call_original
      Voyage.transaction { inner.run }
      expect(Voyage).to have_received(:transaction).with(requires_new: true)
    end

    it 'joins the outer transaction with an explicit requires_new: false' do
      allow(Voyage).to receive(:transaction).and_call_original
      action = build_action do
        transactional model: Voyage, requires_new: false
        step :write
        def write = Voyage.create!(tag: 'j')
      end
      Voyage.transaction { action.run }
      expect(Voyage).to have_received(:transaction).with(requires_new: false)
    end

    it 'passes the options verbatim and adds nothing outside a transaction' do
      allow(Voyage).to receive(:transaction).and_call_original
      action = build_action do
        transactional model: Voyage, joinable: false
        step :write
        def write = nil
      end
      action.run
      expect(Voyage).to have_received(:transaction).with(joinable: false)
    end

    it 'leaves non-transactional actions untouched' do
      allow(Voyage).to receive(:transaction).and_call_original
      build_action { step(:noop) }.tap { |a| a.define_method(:noop) { nil } }.run
      expect(Voyage).not_to have_received(:transaction)
    end
  end
end
