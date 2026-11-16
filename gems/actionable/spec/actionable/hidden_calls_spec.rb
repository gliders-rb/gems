# frozen_string_literal: true

module Lighthouse
  class TrimWick < Actionable::Action
    step :trim

    private

    def trim; end
  end

  class LogWeather < Actionable::Action
    step :note

    private

    def note; end
  end

  class SoundHorn < Actionable::Action
    step :blast

    private

    def blast; end
  end

  # Not an action, though it answers .run.
  class Tide
    def self.run = :high
  end

  class NightWatch < Actionable::Action
    step :light_lamp
    step :survey
    on_success :sign_log

    private

    def light_lamp
      TrimWick.run
      check_fog
    end

    def survey
      self.check_fog # rubocop:disable Style/RedundantSelf -- the self. form is what this case covers
      Lighthouse::LogWeather.run!
      Tide.run
      [TrimWick].first.run
    end

    def check_fog
      check_fog if false # rubocop:disable Lint/LiteralAsCondition
      SoundHorn.run
      TrimWick.run
    end

    def sign_log
      LogWeather.run
    end
  end

  class QuietNight < Actionable::Action
    step :rest

    private

    def rest; end
  end
end

RSpec.describe 'hidden child runs (calls)' do
  it 'AC-B#describe: lists the actions run by hand, in order of first appearance, without repeats' do
    expect(Lighthouse::NightWatch.describe[:calls])
      .to eq([Lighthouse::TrimWick, Lighthouse::SoundHorn, Lighthouse::LogWeather])
  end

  it 'AC-B#describe: is empty when nothing is run by hand' do
    expect(Lighthouse::QuietNight.describe[:calls]).to eq([])
  end

  it 'AC-B#describetext: adds a Calls line only when there are calls' do
    expect(Lighthouse::NightWatch.describe_text.lines.last)
      .to eq('  Calls: Lighthouse::TrimWick, Lighthouse::SoundHorn, Lighthouse::LogWeather (found in source)')
    expect(Lighthouse::QuietNight.describe_text).not_to include('Calls:')
  end
end
