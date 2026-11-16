# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'
require 'open3'

require_relative 'fixtures/lib/apiary'

RSpec.describe DocCheck do
  let(:root) { File.join(__dir__, 'fixtures') }
  let(:lib) { File.join(root, 'lib') }

  describe '.code_text' do
    it 'SH-B70: keeps fenced and inline code, drops prose' do
      text = "Prose says honey.\n\n```ruby\nhive.frames = 2\n```\n\nAlso `Hive.inspect_all` here.\n"
      code = described_class.code_text(text)
      expect(code).to include('hive.frames = 2', 'Hive.inspect_all')
      expect(code).not_to include('Prose says')
    end

    it 'SH-B70: reads ~~~ fences and fences with a meta' do
      expect(described_class.code_text("~~~\nwax\n~~~\n```ruby run\npollen\n```\n")).to include('wax', 'pollen')
    end
  end

  describe '.public_methods_of' do
    it 'SH-B71: lists instance, singleton and macro methods defined under lib' do
      expect(described_class.public_methods_of('Apiary::Hive', :instance, lib: lib)).to eq(%w[frames= honey to_s])
      expect(described_class.public_methods_of('Apiary::Hive', :singleton, lib: lib)).to eq(%w[inspect_all])
      expect(described_class.public_methods_of('Apiary::Hive', :macros, lib: lib)).to eq(%w[hive_count inspect_all])
    end

    it 'SH-B71: leaves out a method whose YARD comment says @api private' do
      expect(described_class.public_methods_of('Apiary::Hive', :instance, lib: lib)).not_to include('wax')
    end

    it 'SH-B71: leaves out methods defined outside lib' do
      expect(described_class.public_methods_of('Apiary::Hive', :instance, lib: '/nowhere')).to eq([])
    end
  end

  describe '.unnamed_methods' do
    let(:api) { [['Apiary::Hive', :instance], ['Apiary::Hive', :macros]] }

    it 'SH-B71: names each missing method as Const#name or Const.name, never the conventional ones' do
      expect(described_class.unnamed_methods('', api: api, lib: lib))
        .to eq(%w[Apiary::Hive#frames= Apiary::Hive#honey Apiary::Hive.hive_count Apiary::Hive.inspect_all])
    end

    it 'SH-B70: counts a name only inside code; a setter is named by its reader name' do
      text = "honey in prose\n\n```ruby\nhive.frames = 2\nHive.hive_count\n```\n"
      expect(described_class.unnamed_methods(text, api: api, lib: lib))
        .to eq(%w[Apiary::Hive#honey Apiary::Hive.inspect_all])
    end

    it 'SH-B74: skips allowlisted entries, bare or qualified' do
      expect(described_class.unnamed_methods('', api: api, lib: lib, allowlist: %w[honey Apiary::Hive#frames= Apiary::Hive.hive_count]))
        .to eq(%w[Apiary::Hive.inspect_all])
    end

    it 'SH-B70: needs a whole word, so honeycomb does not name honey' do
      expect(described_class.unnamed_methods('`honeycomb`', api: [['Apiary::Hive', :instance]], lib: lib))
        .to include('Apiary::Hive#honey')
    end
  end

  describe '.stale_allowlist' do
    it 'SH-B74: reports entries that match no method of the API' do
      api = [['Apiary::Hive', :instance]]
      expect(described_class.stale_allowlist(%w[honey Apiary::Hive#frames= queen Apiary::Hive#drone], api: api, lib: lib))
        .to eq(%w[queen Apiary::Hive#drone])
    end
  end

  describe '.unnamed_words' do
    it 'SH-B70: an option is named only as x: inside code' do
      text = "smoke: in prose\n\n`smoke:` and `veil`\n"
      expect(described_class.unnamed_words(text, %w[smoke veil gloves], form: :option)).to eq(%w[veil gloves])
    end

    it 'SH-B70: a key is named as x, :x or x: inside code' do
      text = "`:nectar` and `pollen:` and `wax`\n"
      expect(described_class.unnamed_words(text, %w[nectar pollen wax royal], form: :key)).to eq(%w[royal])
    end

    it 'SH-B71: refuses an unknown form' do
      expect { described_class.unnamed_words('', %w[x], form: :method) }.to raise_error(ArgumentError, /form/)
    end
  end

  describe '.parse_allowlist' do
    it 'SH-B71: drops comments and blanks, strips entries' do
      expect(described_class.parse_allowlist("# why\n\n honey \nApiary::Hive#frames=\n")).to eq(%w[honey Apiary::Hive#frames=])
    end
  end

  describe '.unreleased_entry?' do
    it 'SH-B71: is true only when the [Unreleased] section has content' do
      expect(described_class.unreleased_entry?("## [Unreleased]\n\n## [1.0.0]\n- old\n")).to be(false)
      expect(described_class.unreleased_entry?("## [Unreleased]\n\n- Added smoke\n\n## [1.0.0]\n")).to be(true)
      expect(described_class.unreleased_entry?("## [1.0.0]\n- old\n")).to be(false)
    end
  end

  describe '.changelog_failure' do
    def git(dir, *args)
      _out, status = Open3.capture2e('git', *args, chdir: dir)
      raise "git #{args.join(' ')} failed" unless status.success?
    end

    def repo
      Dir.mktmpdir do |dir|
        git(dir, 'init', '-q', '-b', 'main')
        git(dir, 'config', 'user.email', 'keeper@example.invalid')
        git(dir, 'config', 'user.name', 'Keeper')
        FileUtils.mkdir_p(File.join(dir, 'lib'))
        File.write(File.join(dir, 'lib/hive.rb'), "# one\n")
        File.write(File.join(dir, 'CHANGELOG.md'), "## [Unreleased]\n\n## [1.0.0]\n")
        git(dir, 'add', '.')
        git(dir, 'commit', '-q', '-m', 'start')
        git(dir, 'tag', 'base')
        yield dir
      end
    end

    it 'SH-B75: is nil when lib/ did not change' do
      repo { |dir| expect(described_class.changelog_failure(dir, base: 'base')).to be_nil }
    end

    it 'SH-B75: names the changed files when lib/ changed and [Unreleased] is empty' do
      repo do |dir|
        File.write(File.join(dir, 'lib/hive.rb'), "# two\n")
        expect(described_class.changelog_failure(dir, base: 'base')).to include('[Unreleased]', 'lib/hive.rb')
      end
    end

    it 'SH-B75: is nil when lib/ changed and [Unreleased] has an entry' do
      repo do |dir|
        File.write(File.join(dir, 'lib/hive.rb'), "# two\n")
        File.write(File.join(dir, 'CHANGELOG.md'), "## [Unreleased]\n\n- Changed hive\n\n## [1.0.0]\n")
        expect(described_class.changelog_failure(dir, base: 'base')).to be_nil
      end
    end

    it 'SH-B75: is nil, with a note, when the base does not resolve' do
      repo do |dir|
        expect { expect(described_class.changelog_failure(dir, base: 'nope/main')).to be_nil }
          .to output(%r{nope/main}).to_stderr
      end
    end
  end

  describe '.check' do
    let(:api) { [['Apiary::Hive', :instance]] }

    it 'SH-B71: is nil when every target names everything; the CHANGELOG check is skipped without a base' do
      text = '`honey` `frames` `smoke:`'
      result = nil
      expect do
        result = described_class.check(root: root, api: api, targets: { 'USAGE.md' => text }, words: { option: %w[smoke] },
                                       base: 'nope/main')
      end.to output(/nope/).to_stderr
      expect(result).to be_nil
    end

    it 'SH-B76: reports each target, words included, and stale allowlist entries' do
      result = nil
      expect do
        targets = { 'USAGE.md' => '`honey`', 'site' => '' }
        result = described_class.check(root: File.join(root, 'stale'), lib: lib, api: api, targets: targets,
                                       words: { option: %w[smoke] }, base: 'nope/main')
      end.to output.to_stderr
      expect(result).to include("USAGE.md doesn't name", 'Apiary::Hive#frames=', 'smoke', "site doesn't name", 'Apiary::Hive#honey')
      expect(result).to include('match nothing', 'Apiary::Hive#drone')
    end
  end

  describe '.check without a base' do
    it 'SH-B71: skips the CHANGELOG check quietly when base is nil' do
      result = :unset
      expect { result = described_class.check(root: root, api: [['Apiary::Hive', :instance]], targets: { 'USAGE.md' => '`honey` `frames`' }, base: nil) }
        .not_to output.to_stderr
      expect(result).to be_nil
    end
  end

  describe '.report' do
    it 'SH-B76: lists each target with its missing names and how to fix them' do
      text = described_class.report('USAGE.md' => %w[Apiary::Hive#honey], 'site reference' => [])
      expect(text).to include('USAGE.md', 'Apiary::Hive#honey', 'docs_allowlist.txt')
      expect(text).not_to include('site reference')
      expect(described_class.report('USAGE.md' => [])).to be_nil
    end
  end
end
