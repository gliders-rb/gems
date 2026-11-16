# frozen_string_literal: true

RSpec.describe 'errors.paths (FS-B40a)' do
  before do
    stub_const('Hinge', Class.new(FieldStruct::Base) do
      required :pin, :string
      optional :turns, :integer, in: 0..4
    end)
    stub_const('Shutter', Class.new(FieldStruct::Base) do
      required :label, :string
      optional :hinge, Hinge
      optional :hinges, :array, of: Hinge
      optional :spare, :value
    end)
  end

  it 'leaves to_h unchanged and names the nested field that failed' do
    shutter = Shutter.new(label: 'east', hinge: { turns: 9 })
    expect(shutter.errors.to_h).to eq(hinge: ['is invalid'])
    expect(shutter.errors.paths).to eq('hinge.pin' => ['is required'], 'hinge.turns' => ['is invalid'])
  end

  it 'indexes array elements, in order, skipping valid ones' do
    shutter = Shutter.new(label: 'east', hinges: [{ pin: 'a' }, {}, { pin: 'c', turns: 7 }])
    expect(shutter.errors.paths).to eq('hinges[1].pin' => ['is required'], 'hinges[2].turns' => ['is invalid'])
  end

  it 'keeps plain fields as their names, in entry order' do
    shutter = Shutter.new(hinge: {})
    expect(shutter.errors.paths).to eq('label' => ['is required'], 'hinge.pin' => ['is required'])
  end

  it 'walks a struct held by a :value field' do
    shutter = Shutter.new(label: 'east', spare: Hinge.new)
    expect(shutter.errors.paths).to eq('spare.pin' => ['is required'])
  end

  it 'goes as deep as the structs do' do
    stub_const('Frame', Class.new(FieldStruct::Base) { optional :shutters, :array, of: Shutter })
    frame = Frame.new(shutters: [{ label: 'n', hinges: [{ pin: 'x' }, { turns: 1 }] }])
    expect(frame.errors.paths).to eq('shutters[0].hinges[1].pin' => ['is required'])
  end

  it "keeps the parent's own entry when no child accounts for it (fixed in place)" do
    shutter = Shutter.new(label: 'east', hinge: {})
    shutter.hinge.pin = 'brass'
    expect([shutter.errors.to_h, shutter.errors.paths]).to eq([{ hinge: ['is invalid'] }, { 'hinge' => ['is invalid'] }])
  end

  it 'adds nothing for a child broken in place, like valid?' do
    shutter = Shutter.new(label: 'east', hinge: { pin: 'brass' })
    shutter.hinge.pin = nil
    expect([shutter.valid?, shutter.errors.paths]).to eq([true, {}])
  end

  it 'keeps other messages on an expanded field at its own path' do
    shutter = Shutter.new(label: 'east', hinge: {})
    shutter.errors.add(:hinge, 'is rusted')
    expect(shutter.errors.paths).to eq('hinge.pin' => ['is required'], 'hinge' => ['is rusted'])
  end

  it 'puts the root :base at "base" and a nested :base at the nested path' do
    stub_const('Latch', Class.new(FieldStruct::Base) do
      optional :side, :string
      validate :needs_side
      def needs_side = side || errors.add(:base, 'needs a side')
    end)
    stub_const('Gate', Class.new(FieldStruct::Base) do
      optional :latch, Latch
      validate :always
      def always = errors.add(:base, 'is shut')
    end)
    gate = Gate.new(latch: {})
    expect(gate.errors.paths).to eq('latch' => ['needs a side'], 'base' => ['is shut'])
  end

  it 'runs no validators and changes nothing' do
    shutter = Shutter.new(label: 'east', hinge: {})
    before = shutter.errors.to_h
    2.times { shutter.errors.paths }
    expect(shutter.errors.to_h).to eq(before)
  end

  it 'gives a copy its own owner' do
    shutter = Shutter.new(label: 'east', hinge: {})
    copy = shutter.with(hinge: { pin: 'brass' })
    expect([copy.errors.paths, shutter.errors.paths]).to eq([{}, { 'hinge.pin' => ['is required'] }])
  end

  it 'returns String keys for a standalone Errors' do
    errors = FieldStruct::Errors.new
    errors.add(:moss, 'is damp')
    expect(errors.paths).to eq('moss' => ['is damp'])
  end

  it 'returns a new Hash with copied arrays each call' do
    shutter = Shutter.new(label: 'east', hinge: {})
    shutter.errors.paths['hinge.pin'] << 'tampered'
    expect(shutter.errors.paths).to eq('hinge.pin' => ['is required'])
  end
end
