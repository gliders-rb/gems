# frozen_string_literal: true

require 'tmpdir'
require_relative '../../support/sig_tools'

RSpec.describe SigTools do
  describe '.prism_sig' do
    it 'AC-B#sigratchet: is the sig/ directory of the prism gem this bundle resolves, with real signatures in it' do
      dir = described_class.prism_sig
      expect(dir).to eq(File.join(Gem::Specification.find_by_name('prism').full_gem_path, 'sig'))
      expect(Dir[File.join(dir, '**', '*.rbs')]).not_to be_empty
    end

    it 'AC-B#sigratchet: no stand-ins are left in support/' do
      expect(Dir.exist?(File.join(described_class::ROOT, 'support', 'external'))).to be(false)
    end
  end

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
