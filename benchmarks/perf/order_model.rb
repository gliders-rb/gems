# frozen_string_literal: true

# Shared, neutral workload: an Order with 15 fields and five nested LineItems.
# `PerfModel.define(union: true)` returns [Order, LineItem] in a fresh namespace module so each gem script
# can pick the variant its adapter supports (protobuf has no unions, so it asks for union: false).
require 'bigdecimal'
require 'date'
require 'securerandom'

module PerfModel
  def self.define(union: true, proto: false, avro: false)
    ns = Module.new
    ns.const_set(:LineItem, line_item(proto))
    ns.const_set(:Order, order(ns::LineItem, union: union, proto: proto))
    [ns::Order, ns::LineItem]
  end

  def self.line_item(proto)
    Class.new(FieldStruct::Base) do
      def self.name = 'PerfLineItem'
      required :sku, :string, **(proto ? { proto: { number: 1 } } : {})
      required :qty, :integer, in: 1..1000, **(proto ? { proto: { number: 2 } } : {})
      required :unit_price, :decimal, round: 2, **(proto ? { proto: { number: 3 } } : {})
      optional :gift, :boolean, **(proto ? { proto: { number: 4 } } : {})
      serialize :json, unit_price: 'unitPrice'
    end
  end

  def self.order(line_item, union:, proto:)
    n = proc { |i| proto ? { proto: { number: i } } : {} }
    Class.new(FieldStruct::Base) do
      def self.name = 'PerfOrder'
      required :id, :uuid, **n.(1)
      required :number, :integer, **n.(2)
      required :customer_name, :string, **n.(3)
      required :customer_email, :email, **n.(4)
      required :status, :symbol, enum: %i[pending paid shipped cancelled], **n.(5)
      required :total, :decimal, round: 2, **n.(6)
      required :express, :boolean, **n.(7)
      required :ordered_on, :date, **n.(8)
      required :placed_at, :time, zone: 'America/Denver', format: :iso8601, **n.(9)
      optional :note, :string, **n.(10)
      optional :discount, :float, round: 2, **n.(11)
      optional :tags, :array, of: :string, **n.(12)
      required :lines, :array, of: line_item, **n.(13)
      optional :reference, :union, of: %i[integer string] if union
      optional :channel, :string, enum: %w[web store phone], **n.(14)
      serialize :json, customer_name: 'customerName', customer_email: 'customerEmail', placed_at: 'placedAt',
                       ordered_on: 'orderedOn'
    end
  end

  def self.order_hash(symbol_keys: true, union: true)
    h = {
      id: '8b1f4d4a-0d0e-4b29-9f4d-6a1b3d3c9f00', number: '1042', customer_name: 'Ana Perez',
      customer_email: 'ana@example.com', status: 'paid', total: '149.95', express: 'true',
      ordered_on: '2026-07-01', placed_at: '2026-07-01T08:15:30-06:00', note: 'leave at door',
      discount: '5.5', tags: %w[gift rush], channel: 'web',
      lines: Array.new(5) { |i| { sku: "SKU-#{i}", qty: (i + 1).to_s, unit_price: "#{i + 1}.99", gift: i.even? } }
    }
    h[:reference] = '77' if union
    symbol_keys ? h : stringify(h)
  end

  def self.stringify(obj)
    case obj
    when Hash then obj.to_h { |k, v| [k.to_s, stringify(v)] }
    when Array then obj.map { |v| stringify(v) }
    else obj
    end
  end
end
