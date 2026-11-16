# frozen_string_literal: true

# Field options the core specs declare as an app would: registered once, for the whole run (FS-B10a).
FieldStruct.register_option(:shelf_mark, type: String, owner: 'field_struct specs')
FieldStruct.register_option(:archive, type: Hash, owner: 'field_struct specs')
