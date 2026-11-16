# frozen_string_literal: true

RSpec.describe 'Presence: given_fields and nullable: (FS-B34, FS-B34a)' do
  let(:return_slip) do
    Class.new(FieldStruct::Base) do
      required :title, :string
      required :returned_on, :date, nullable: true
      optional :shelf, :string, default: 'B4'
      optional :note, :string
    end
  end

  describe 'given_fields' do
    it 'lists the keys the caller gave, in declaration order, frozen' do
      slip = return_slip.new('note' => 'dog-eared', title: 'Moss Gardens')
      expect(slip.given_fields).to eq(%i[title note])
      expect(slip.given_fields).to be_frozen
    end

    it 'never counts a default or an unknown key' do
      slip = return_slip.new(title: 'Moss Gardens', stamp: 'x')
      expect([slip.shelf, slip.given_fields]).to eq(['B4', [:title]])
    end

    it 'is empty with no input' do
      expect(return_slip.new.given_fields).to eq([])
    end

    it 'counts a writer call and assign_attributes' do
      slip = return_slip.new(title: 'Moss Gardens')
      slip.note = nil
      slip.assign_attributes(shelf: 'C1')
      expect(slip.given_fields).to eq(%i[title shelf note])
    end

    it 'tells "sent as null" from "not sent"' do
      slip = return_slip.new(title: 'Moss Gardens', note: nil)
      expect([slip.given_fields.include?(:note) && slip.note.nil?, slip.given_fields.include?(:shelf)]).to eq([true, false])
    end

    it 'merges in with and copies on dup' do
      slip = return_slip.new(title: 'Moss Gardens')
      expect(slip.with(note: 'mended').given_fields).to eq(%i[title note])
      expect(slip.dup.given_fields).to eq([:title])
      expect(slip.given_fields).to eq([:title])
    end

    it 'counts a mapped JSON key through from_json' do
      mapped = Class.new(FieldStruct::Base) do
        optional :shelf, :string
        serialize :json, shelf: 'shelfCode'
      end
      expect(mapped.from_json('{"shelfCode": "A2"}').given_fields).to eq([:shelf])
    end

    it 'takes no part in equality' do
      expect(return_slip.new(title: 'Moss Gardens', note: nil)).to eq(return_slip.new(title: 'Moss Gardens'))
    end

    it 'is a reserved field name' do
      expect { Class.new(FieldStruct::Base) { optional :given_fields, :string } }
        .to raise_error(ArgumentError, /\Afield :given_fields is reserved/)
    end
  end

  describe 'nullable:' do
    it 'accepts a given nil' do
      slip = return_slip.new(title: 'Moss Gardens', returned_on: nil)
      expect([slip.valid?, slip.returned_on]).to eq([true, nil])
    end

    it 'still requires the key' do
      slip = return_slip.new(title: 'Moss Gardens')
      expect(slip.errors.to_h).to eq(returned_on: ['is required'])
    end

    it 'becomes valid once the writer sets nil' do
      slip = return_slip.new(title: 'Moss Gardens')
      slip.returned_on = nil
      expect(slip).to be_valid
    end

    it 'keeps a given nil over a default, and uses the default when the key is absent' do
      dated = Class.new(FieldStruct::Base) { required :due_on, :date, nullable: true, default: -> { Date.new(2026, 12, 1) } }
      expect(dated.new(due_on: nil).due_on).to be_nil
      expect([dated.new.due_on, dated.new.valid?]).to eq([Date.new(2026, 12, 1), true])
    end

    it 'treats only nil as the null answer: a blank String is still missing' do
      named = Class.new(FieldStruct::Base) { required :label, :string, nullable: true }
      expect(named.new(label: '  ').errors.to_h).to eq(label: ['is required'])
      expect(named.new(label: nil)).to be_valid
    end

    it 'leaves plain required unchanged' do
      expect(return_slip.new(title: nil, returned_on: nil).errors.to_h).to eq(title: ['is required'])
    end

    it 'shows on the Field, in inspect, to_h and describe' do
      field = return_slip.metadata[:returned_on]
      expect([field.required?, field.nullable?, return_slip.metadata[:title].nullable?]).to eq([true, true, false])
      expect(field.inspect).to start_with('#<FieldStruct::Field :returned_on Date required nullable')
      expect(return_slip.metadata.to_h[:returned_on][:nullable]).to be(true)
      expect(return_slip.metadata.to_h[:title]).not_to have_key(:nullable)
      expect(return_slip.describe).to include('returned_on (Date, required, nullable)')
    end

    it 'refuses a value that is not true or false' do
      expect { Class.new(FieldStruct::Base) { required :due_on, :date, nullable: 'yes' } }
        .to raise_error(ArgumentError, 'nullable: must be true or false, got String')
    end

    it 'refuses nullable: true on an optional field' do
      expect { Class.new(FieldStruct::Base) { optional :due_on, :date, nullable: true } }
        .to raise_error(ArgumentError, 'nullable: applies to required fields; an optional field already accepts nil')
    end

    it 'types a nullable reader with ? in the generated RBS' do
      stub_const('ReturnSlip', return_slip)
      expect(FieldStruct::RBS.type_for(ReturnSlip.metadata[:returned_on])).to eq('::Date?')
      expect(FieldStruct::RBS.type_for(ReturnSlip.metadata[:title])).to eq('::String')
    end
  end
end
