# frozen_string_literal: true

require 'tmpdir'

RSpec.describe 'writing and checking pages' do
  let(:actions) { [Workshop::ServiceBike, Workshop::TrueWheel, Workshop::ServiceBike] }

  it 'AD-B30: writes each page once under the docs folder and returns the paths' do
    Dir.mktmpdir do |dir|
      paths = Actionable::Docs.write(actions, dir: dir)
      expect(paths).to eq([File.join(dir, 'workshop/service_bike.md'), File.join(dir, 'workshop/true_wheel.md')])
      expect(File.read(paths.last)).to eq(Actionable::Docs.markdown(Workshop::TrueWheel))
    end
  end

  it 'AD-B31: names the missing and the changed pages, and writes nothing' do
    Dir.mktmpdir do |dir|
      expect(Actionable::Docs.stale(actions, dir: dir).size).to eq(2)
      expect(Dir.children(dir)).to be_empty
      Actionable::Docs.write(actions, dir: dir)
      expect(Actionable::Docs.stale(actions, dir: dir)).to eq([])
      File.write(File.join(dir, 'workshop/true_wheel.md'), 'edited by hand')
      expect(Actionable::Docs.stale(actions, dir: dir)).to eq([File.join(dir, 'workshop/true_wheel.md')])
    end
  end

  describe 'AD-B32: the rake tasks' do
    around do |example|
      original = Rake.application
      Rake.application = Rake::Application.new
      example.run
    ensure
      Rake.application = original
    end

    it 'defines actionable:docs and actionable:docs:check, reading a callable when they run' do
      Dir.mktmpdir do |dir|
        asked = 0
        Actionable::Docs::Tasks.define(actions: -> { (asked += 1) && [Workshop::TrueWheel] }, dir: dir)
        expect(asked).to eq(0)
        expect { Rake::Task['actionable:docs:check'].invoke }
          .to raise_error(SystemExit).and output(/out of date; run rake actionable:docs and commit them:\n.*true_wheel\.md/).to_stderr
        expect { Rake::Task['actionable:docs'].invoke }.to output(/actionable-docs: wrote .*true_wheel\.md/).to_stdout
        Rake::Task['actionable:docs:check'].reenable
        expect { Rake::Task['actionable:docs:check'].invoke }.to output("actionable-docs: 1 pages are current\n").to_stdout
        expect(asked).to eq(3)
      end
    end

    it 'takes a plain Array too' do
      Dir.mktmpdir do |dir|
        Actionable::Docs::Tasks.define(actions: [Workshop::OrderParts], dir: dir)
        expect { Rake::Task['actionable:docs'].invoke }.to output(/order_parts\.md/).to_stdout
      end
    end
  end
end
