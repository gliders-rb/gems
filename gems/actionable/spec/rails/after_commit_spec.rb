# frozen_string_literal: true

require_relative 'rails_helper'

# ActiveRecord 7.1 has no after_all_transactions_commit: the CI lane for it runs the second group instead.
AFTER_COMMIT_SUPPORTED = ActiveRecord.respond_to?(:after_all_transactions_commit)

RSpec.describe 'Rails adapter: after_commit', skip: (AFTER_COMMIT_SUPPORTED ? false : 'needs ActiveRecord >= 7.2') do
  let(:log) { [] }

  def hooked(log, name: 'x', succeeds: true, transact: false, **hook_opts, &extra)
    build_action do
      transactional model: Voyage if transact
      step :work
      after_commit :notify, **hook_opts
      define_method(:work) { Voyage.create!(tag: name) && (succeeds ? nil : fail!(:bad)) }
      define_method(:notify) { log << [name, Voyage.connection.transaction_open?, Voyage.count] }
      class_eval(&extra) if extra
    end
  end

  describe 'AC-B#aftercommit' do
    it 'lists the declared hooks, inherited by copy' do
      parent = hooked(log)
      child = Class.new(parent) { after_commit :other }
      expect(parent.after_commit_hooks.map(&:name)).to eq([:notify])
      expect(child.after_commit_hooks.map(&:name)).to eq(%i[notify other])
    end

    it 'raises DefinitionError without ActiveRecord loaded' do
      hide_const('ActiveRecord')
      expect { build_action { after_commit :x } }.to raise_error(
        Actionable::DefinitionError,
        'after_commit needs ActiveRecord >= 7.2 (ActiveRecord.after_all_transactions_commit); ' \
        'load a supported ActiveRecord before declaring it'
      )
    end

    it 'raises DefinitionError on an ActiveRecord without after_all_transactions_commit' do
      stub_const('ActiveRecord', Module.new)
      expect { build_action { after_commit :x } }.to raise_error(Actionable::DefinitionError, /after_commit needs ActiveRecord >= 7.2/)
    end

    it 'accepts a nested action as a hook' do
      child = build_action { step(:sail) && nil }
      expect { build_action.after_commit(child, if: :ok?) }.not_to raise_error
    end
  end

  describe 'AC-B#aftercommitwhen' do
    it 'runs immediately after a success when no transaction is open' do
      hooked(log).run
      expect(log).to eq([['x', false, 1]])
    end

    it 'runs after the action own transaction commits' do
      hooked(log, transact: true).run
      expect(log).to eq([['x', false, 1]])
    end

    it 'waits for the outermost transaction, not the savepoint' do
      action = hooked(log, transact: true)
      Voyage.transaction do
        action.run
        expect(log).to be_empty
      end
      expect(log).to eq([['x', false, 1]])
    end

    it 'never runs when the enclosing transaction rolls back' do
      action = hooked(log)
      Voyage.transaction do
        action.run
        raise ActiveRecord::Rollback
      end
      expect(log).to be_empty
    end

    it 'never runs after a Failure or a Skipped' do
      hooked(log, succeeds: false).run
      log = self.log
      skipper = build_action do
        step :sail
        after_commit :notify
        def sail = skip('no')
        define_method(:notify) { log << :skip }
      end
      skipper.run
      expect(log).to be_empty
    end

    it 'runs the hooks once, in declaration order' do
      log = self.log
      action = build_action do
        step :sail
        after_commit :one
        after_commit :two
        define_method(:sail) { nil }
        define_method(:one) { log << 1 }
        define_method(:two) { log << 2 }
      end
      action.run
      expect(log).to eq([1, 2])
    end

    it 'runs each nested action hooks once, child first, after the outermost commit' do
      child = hooked(log, name: 'child')
      parent = hooked(log, name: 'parent', transact: true) { step child }
      Voyage.transaction { parent.run }
      expect(log.map(&:first)).to eq(%w[child parent])
      expect(log.map { |row| row[1] }).to eq([false, false])
    end

    it 'drops a successful child pending hook when a transactional parent then fails' do
      child = hooked(log, name: 'child')
      parent = build_action do
        transactional model: Voyage
        step child
        step :bust
        def bust = fail!(:late)
      end
      expect(parent.run).to be_failure
      expect(log).to be_empty
    end
  end

  describe 'AC-B#aftercommitnature' do
    it 'cannot change the returned result, and a halting verb only stops the remaining hooks' do
      log = self.log
      action = build_action do
        step :sail
        after_commit :one
        after_commit :two
        define_method(:sail) { succeed('done') }
        define_method(:one) { log << 1 and fail!(:late) }
        define_method(:two) { log << 2 }
      end
      result = action.run
      expect(result).to be_success
      expect(result.message).to eq('done')
      expect(log).to eq([1])
    end

    it 'is not recorded in the history' do
      action = hooked(log) { measure :all }
      expect(action.run.history.steps.map(&:name)).to eq([:work])
    end

    it 'makes no record call' do
      calls = []
      spy = Module.new do
        define_method(:record) do |section, step, &blk|
          calls << [section, step.name]
          super(section, step, &blk)
        end
      end
      Actionable::Runner.prepend(spy)
      hooked(log).run
      expect(calls).to eq([%i[main work]])
    end

    it 'propagates an exception from where the commit happened, after the writes committed' do
      action = build_action do
        step :sail
        after_commit :kraken
        define_method(:sail) { Voyage.create!(tag: 'kept') }
        def kraken = raise('hook kraken')
      end
      expect { action.run }.to raise_error('hook kraken')
      expect(Voyage.count).to eq(1)
      expect { Voyage.transaction { action.run } }.to raise_error('hook kraken')
      expect(Voyage.count).to eq(2)
    end

    it 'evaluates guards when the hooks fire' do
      flag = false
      log = self.log
      action = build_action do
        step :sail
        after_commit :notify, if: ->(_action) { flag }
        define_method(:sail) { nil }
        define_method(:notify) { log << :fired }
      end
      Voyage.transaction do
        action.run
        flag = true
      end
      expect(log).to eq([:fired])
    end
  end

  describe 'AC-B#aftercommitdescribe' do
    it 'lists the names in describe and a text line only when non-empty' do
      action = hooked(log)
      expect(action.describe[:hooks][:after_commit]).to eq([:notify])
      expect(action.describe_text).to include('after_commit: notify')
      expect(build_action.describe[:hooks][:after_commit]).to eq([])
      expect(build_action.describe_text).not_to include('after_commit')
    end

    it 'covers the hooks in the missing-method check' do
      action = build_action do
        step(:sail)
        after_commit :ghost
        def sail = nil
      end
      expect { action.run }.to raise_error(Actionable::DefinitionError, /:ghost/)
    end

    it 'covers the hooks in the verb check' do
      Actionable.verb_position_check = true
      action = named_action('BadAfterCommit') do
        step :sail
        after_commit :notify
        def sail = nil

        def notify
          succeed('x')
          nil
        end
      end
      expect { action.run }.to raise_error(Actionable::DefinitionError, /notify/)
    ensure
      Actionable.verb_position_check = false
    end
  end
end

RSpec.describe 'Rails adapter: after_commit on an old ActiveRecord',
               skip: (AFTER_COMMIT_SUPPORTED ? 'ActiveRecord >= 7.2 is loaded' : false) do
  it 'AC-B#railsci: refuses to declare, while transactions keep working' do
    expect do
      Class.new(Actionable::Action) do
        after_commit :x
      end
    end.to raise_error(Actionable::DefinitionError, /after_commit needs ActiveRecord >= 7.2/)
    action = Class.new(Actionable::Action) do
      transactional model: Voyage
      step :sail
      define_method(:sail) { Voyage.create!(tag: 'a') && fail!(:bad) }
    end
    expect(action.run.code).to eq(:bad)
    expect(Voyage.count).to eq(0)
  end
end
