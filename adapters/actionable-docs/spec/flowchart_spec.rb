# frozen_string_literal: true

RSpec.describe 'the flowchart' do
  let(:chart) do
    page = Actionable::Docs.markdown(Workshop::ServiceBike)
    page[/```mermaid\n(.*?)```/m, 1]
  end

  it 'AD-B20: runs from Start to Done, one node per step, in order' do
    expect(chart.lines.first(3).map(&:chomp)).to eq(['flowchart TD', '  start([Start])', '  s1["Check the bike in"]'])
    expect(chart).to include('  start --> s1', '  done([Done])')
  end

  it 'AD-B21: draws a child action as one linked box, never its steps' do
    expect(chart).to include('  s2[["True wheel"]]', '  click s2 "true_wheel.md"', '  s1 --> s2')
    expect(chart).not_to include('Spin wheel', 'Tension spokes')
  end

  it 'AD-B23: gives a case step a decision with one edge per branch, and a default' do
    expect(chart).to include('  c3{"What kind of bike it is?"}', '  s2 --> c3', '  s4["Fit rim brakes"]',
                             '  c3 -->|road| s4', '  c3 -->|mountain or cargo| s5', '  c3 -->|anything else| s6',
                             '  s6[["Order parts"]]', '  click s6 "order_parts.md"')
  end

  it 'AD-B22: puts a decision before a guarded step; every branch joins it' do
    expect(chart).to include('  g7{"chain dry?"}', '  s4 --> g7', '  s5 --> g7', '  s6 --> g7',
                             '  g7 -->|yes| s8', '  s8 --> done', '  g7 -->|no| done')
  end

  it 'AD-B24: hangs every declared failure and skip off Start, and draws no hooks' do
    expect(chart).to include('  f9[/"Stops: Parts missing"/]', '  start -->|any step| f9',
                             '  f10[/"Stops: Frame bent"/]', '  k11[/"Finishes early: Already serviced"/]',
                             '  start -->|any step| k11')
    expect(chart).not_to include('Text the owner')
  end

  it 'AD-B23: sends a case step with no default straight on' do
    stub_const('Workshop::PickSaddle', Class.new(Actionable::Action) do
      case_step(:size) { on 'small', :fit_short }
      step :tighten_bolt
    end)
    text = Actionable::Docs.markdown(Workshop::PickSaddle)
    expect(text).to include('  c1 -->|small| s2', '  c1 -->|anything else| s3', '  s2 --> s3')
  end

  it 'AD-B21: turns a double quote in a label into a single one' do
    stub_const('Workshop::Measure', Class.new(Actionable::Action) { step :read_gauge, desc: 'Read the "PSI" gauge' })
    expect(Actionable::Docs.markdown(Workshop::Measure)).to include(%(  s1["Read the 'PSI' gauge"]))
  end
end
