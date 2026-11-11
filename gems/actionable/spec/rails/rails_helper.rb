# frozen_string_literal: true

require 'active_record'
require 'active_model'
require 'actionable/rails'

ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table(:voyages) { |t| t.string :tag }
end

class Voyage < ActiveRecord::Base; end

RSpec.configure do |config|
  config.before { Voyage.delete_all }
end
