# frozen_string_literal: true

# Every spec class whose message gets registered. Messages live in google-protobuf's process-wide pool, so these are
# defined once, at top level, and never redefined per example (PB-I7).
module DockNet
  class Station < FieldStruct::Base
    required :district, :string, proto: { number: 1 }
    optional :dock, :string, proto: { number: 2 }
  end

  module Depot
    class Alert < FieldStruct::Base
      required :notify_to, :email, proto: { number: 1 }
    end
  end

  class Trip < FieldStruct::Base
    required :id, :uuid, proto: { number: 1 }
    required :fare, :big_decimal, round: 2, proto: { number: 2 }
    required :started, :time, zone: 'America/Denver', proto: { number: 3 }
    optional :spotted, :datetime, proto: { number: 4 }
    optional :grade, :symbol, enum: %i[standard electric], proto: { number: 5 }
    optional :service_day, :date, proto: { number: 6 }
    optional :returned, :boolean, proto: { number: 7 }
    optional :legs, :integer, proto: { number: 8 }
    optional :charge, :float, proto: { number: 9 }
    optional :telemetry, :binary, proto: { number: 10 }
    optional :extras, :value, proto: { number: 11 }
    optional :labels, :array, of: :string, proto: { number: 12 }
    optional :end_dock, Station, proto: { number: 13 }
    optional :stops, :array, of: Station, proto: { number: 14 }
    optional :pings, :array, of: :time, element: { zone: 'UTC' }, proto: { number: 15 }
    optional :alert, Depot::Alert, proto: { number: 17 }
    optional :logged_at, :time, zone: '+05:30', proto: { number: 18 }
  end
  Trip.optional :prior, Trip, proto: { number: 16 }

  class Relabeled < FieldStruct::Base
    required :trip_no, :integer, proto: { number: 1 }
    optional :end_dock, :string, proto: { number: 2 }
    serialize :protobuf, end_dock: 'endDock'
  end

  class Pickup < FieldStruct::Base
    required :id, :integer, proto: { number: 1 }
  end

  class Dropoff < FieldStruct::Base
    optional :pickup, Pickup, proto: { number: 1 }
  end
  Pickup.optional :dropoff, Dropoff, proto: { number: 2 }

  class Twin < FieldStruct::Base
    required :a, :string, proto: { number: 1 }
  end

  class Outdated < FieldStruct::Base
    required :a, :string, proto: { number: 1 }
  end

  class Sealed < FieldStruct::Base
    required :a, :string, proto: { number: 1 }
    optional :key_code, :value, sensitive: true, proto: { number: 2 }
    optional :seals, :array, of: :string, sensitive: true, proto: { number: 3 }
  end

  class Rival < FieldStruct::Base
    required :a, :string, proto: { number: 1 }
    optional :station, Station, proto: { number: 2 }
  end
end
