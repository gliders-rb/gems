# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../support/sig_tools'

RSpec.describe SigTools do
  describe '.without_file' do
    it 'hides the file while the block runs and puts it back after' do
      Dir.mktmpdir do |dir|
        lock = File.join(dir, 'kept.yaml')
        File.write(lock, "pinned: 1\n")
        seen = described_class.without_file(lock) { File.exist?(lock) }
        expect(seen).to be(false)
        expect(File.read(lock)).to eq("pinned: 1\n")
      end
    end

    it 'puts the file back when the block raises' do
      Dir.mktmpdir do |dir|
        lock = File.join(dir, 'kept.yaml')
        File.write(lock, "pinned: 2\n")
        expect { described_class.without_file(lock) { raise 'sord broke' } }.to raise_error(RuntimeError, 'sord broke')
        expect(File.read(lock)).to eq("pinned: 2\n")
      end
    end

    it 'just runs the block when there is no file' do
      Dir.mktmpdir do |dir|
        expect(described_class.without_file(File.join(dir, 'absent.yaml')) { :ran }).to eq(:ran)
      end
    end
  end
end
