# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Doctest do
  def page(text)
    path = File.join(Dir.mktmpdir, 'STATION.md')
    File.write(path, text)
    path
  end

  def block(source, line: 1)
    Doctest::Block.new('STATION.md', line, source)
  end

  def script_for(source)
    described_class.script([block(source)])
  end

  describe '.blocks' do
    it 'takes ruby fences whose meta has run, with or without a title, and their first source line' do
      path = page("intro\n\n```ruby run\nwind = 4\n```\n\n```ruby\nshown_only\n```\n\n" \
                  "```ruby run title=\"gauge.rb\"\nrain = 2\n```\n\n```sh\nls\n```\n")
      found = described_class.blocks(path)
      expect(found.map(&:source)).to eq(["wind = 4\n", "rain = 2\n"])
      expect(found.map(&:line)).to eq([4, 12])
    end

    it 'strips the fence indent, as in a list item' do
      path = page("- step\n\n  ```ruby run\n  gust = 9\n  ```\n")
      expect(described_class.blocks(path).map(&:source)).to eq(["gust = 9\n"])
    end

    it 'gives [] for a page with nothing to run' do
      expect(described_class.blocks(page("```ruby\nx = 1\n```\n"))).to eq([])
    end
  end

  describe '.script' do
    it 'turns expr # => value into a check and keeps one line per source line' do
      text = script_for("reading = 3 + 4 # => 7\nputs reading\n")
      expect(text).to include('__doctest_check((reading = 3 + 4), (7), \\"STATION.md:1\\")')
    end

    it 'checks a # => alone under a one-line expression, naming the expression line' do
      text = script_for("readings = [3, 4]\nreadings.sum\n# => 7\n")
      expect(text).to include('__doctest_check((readings.sum), (7), \\"STATION.md:2\\")')
    end

    it 'joins a value that wraps over comment lines, under or beside the expression' do
      text = script_for("levels # => [1,\n#   2]\nlevels.reverse\n# => [2,\n#   1]\n")
      expect(text).to include('([1, 2])').and include('([2, 1])')
    end

    it 'shows but does not check an inspect string' do
      expect(script_for("vane # => #<Vane bearing: 270>\n")).to include('eval("vane\\n"')
    end

    it 'refuses arrows that would check nothing' do
      {
        "# => 3\n" => 'STATION.md:1: a # => needs the expression on the line right before it',
        "end\n# => 3\n" => 'STATION.md:2: a # => needs the expression on the line right before it',
        "gauge # =>\n" => 'STATION.md:1: a # => with no value after it',
        "gauge # => [1,\n" => "STATION.md:1: the documented value isn't Ruby, so it can't be checked: [1,",
        "gauge.dry? # => false, still dry\n" =>
          "STATION.md:1: the documented value isn't Ruby, so it can't be checked: false, still dry"
      }.each do |source, message|
        expect { script_for(source) }.to raise_error(ArgumentError, message)
      end
    end
  end

  describe '.run_file' do
    it 'passes a true page whose blocks build on each other' do
      path = page("```ruby run\nclass Gauge; def mm = 12; end\nlog = []\n```\n\n" \
                  "```ruby run\nlog << Gauge.new.mm\nlog # => [12]\n```\n")
      run = described_class.run_file(path)
      expect([run.ok, run.blocks]).to eq([true, 2]), run.stderr
    end

    it 'reports every mismatch with file:line and both values, then fails' do
      path = page("```ruby run\nwind = 4\nwind + 1 # => 6\nwind * 2\n# => 9\n```\n")
      run = described_class.run_file(path)
      expect(run.ok).to be(false)
      expect(run.stderr).to include("#{path}:3: documented 6, got 5").and include("#{path}:4: documented 9, got 8")
    end

    it 'fails at an exception, with the page line in the backtrace' do
      path = page("```ruby run\nok = 1\nraise 'sensor offline'\n```\n")
      run = described_class.run_file(path)
      expect(run.ok).to be(false)
      expect(run.stderr).to include("#{path}:3").and include('sensor offline')
    end

    it 'requires features first and keeps pages apart' do
      first = page("```ruby run\nPeak = Set.new([1])\nPeak.size # => 1\n```\n")
      second = page("```ruby run\ndefined?(Peak) # => nil\n```\n")
      expect([described_class.run_file(first, requires: ['set']).ok, described_class.run_file(second).ok]).to eq([true, true])
    end

    it 'runs nothing for a page with nothing to run' do
      run = described_class.run_file(page("```ruby\nraise 'never'\n```\n"))
      expect([run.ok, run.blocks]).to eq([true, 0])
    end
  end
end
