# frozen_string_literal: true

# A one-file Rails app that puts field_struct and actionable-rb through what an app does with them (SH-I9, SH-B62).
# Booted once, production-like: eager loading on, an in-memory SQLite database, the ActiveJob test adapter.

ENV['DATABASE_URL'] = 'sqlite3::memory:'
ENV['RAILS_ENV'] ||= 'production'

require 'bundler/setup'
require 'rails'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'active_job/railtie'

# Loaded as an app's Gemfile and an initializer would load them.
require 'field_struct'
require 'actionable'
require 'actionable/rails'
require 'actionable/job'

require 'rack/test'
require 'rspec/autorun' if $PROGRAM_NAME == __FILE__

class KiteWorkshop < Rails::Application
  config.root = __dir__
  config.eager_load = true
  config.enable_reloading = false
  config.logger = Logger.new(nil)
  config.secret_key_base = 'kite-workshop-integration-only' * 3
  config.hosts.clear
  config.active_job.queue_adapter = :test
  config.action_controller.allow_forgery_protection = false
  config.consider_all_requests_local = false
end
KiteWorkshop.initialize!

ActiveRecord::Migration.verbose = false
ActiveRecord::Schema.define do
  create_table(:kites) do |t|
    t.string :name, null: false
    t.integer :span_cm
  end
  create_table(:flight_logs) { |t| t.string :entry, null: false }
end

class Kite < ActiveRecord::Base; end
class FlightLog < ActiveRecord::Base; end

# A plain struct, as a form or an API body would use it.
class KiteSketch < FieldStruct::Base
  required :name, :string
  optional :span_cm, :integer
end

# Builds a kite and its log entry together; a log entry is written only after the commit.
class BuildKite < Actionable::Action
  transactional model: Kite

  input do
    required :name, :string
    optional :span_cm, :integer
  end

  output { optional :kite_id, :integer }

  fails :too_wide

  step :save_kite
  step :check_span
  step :report

  after_commit :log_build

  private

  def save_kite
    @kite = Kite.create!(name: input.name, span_cm: input.span_cm)
  end

  def check_span
    fail!(:too_wide) if input.span_cm.to_i > 400
  end

  def report
    succeed!(kite_id: @kite.id)
  end

  def log_build
    FlightLog.create!(entry: "built #{input.name}")
  end
end

# Fails with a code a job should retry, then succeeds, so the job's retry path can be seen.
class CheckWind < Actionable::Action
  input { required :site, :string }

  fails :gusty
  fails :no_such_site

  step :read_gauge

  class << self
    attr_accessor :gusts_left
  end

  private

  def read_gauge
    fail!(:no_such_site) if input.site == 'nowhere'
    return unless CheckWind.gusts_left.to_i.positive?

    CheckWind.gusts_left -= 1
    fail!(:gusty)
  end
end

class CheckWindJob < ActiveJob::Base
  include Actionable::Job::Mixin

  retry_on Actionable::Job::RetryableFailure, wait: 0, attempts: 3

  def actionable_permanent_codes = super + %i[no_such_site]

  def perform(site)
    run_actionable(CheckWind, site: site)
  end
end

class KitesController < ActionController::API
  def create
    result = BuildKite.run(**params.require(:kite).permit(:name, :span_cm).to_h.symbolize_keys)
    render json: result, status: result.success? ? :created : :unprocessable_content
  end

  def sketch
    render json: KiteSketch.new(params.require(:kite).permit(:name, :span_cm))
  end
end

KiteWorkshop.routes.draw do
  post '/kites', to: 'kites#create'
  post '/kites/sketch', to: 'kites#sketch'
end

RSpec.describe 'field_struct and actionable-rb inside a Rails app' do
  include Rack::Test::Methods

  def app = KiteWorkshop

  def json_body = JSON.parse(last_response.body)

  around do |example|
    ActiveRecord::Base.transaction do
      example.run
      raise ActiveRecord::Rollback
    end
  end

  # The around hook holds a transaction open, so after_commit would wait for it; these examples need real commits.
  def without_wrapping_transaction(&)
    ActiveRecord::Base.connection.rollback_transaction
    yield
  ensure
    Kite.delete_all
    FlightLog.delete_all
    ActiveRecord::Base.connection.begin_transaction(joinable: false)
  end

  describe 'request params' do
    let(:raw) { ActionController::Parameters.new(kite: { name: 'Sled', span_cm: '150', colour: 'red' }) }

    it 'builds a struct from permitted params and coerces the values' do
      sketch = KiteSketch.new(raw.require(:kite).permit(:name, :span_cm))
      expect([sketch.name, sketch.span_cm, sketch.valid?]).to eq(['Sled', 150, true])
    end

    it 'leaves unpermitted params to Rails, which refuses to turn them into a Hash' do
      expect { KiteSketch.new(raw.require(:kite)) }.to raise_error(ActionController::UnfilteredParameters)
    end

    it 'runs an action from permitted params splatted as keywords' do
      result = BuildKite.run(**raw.require(:kite).permit(:name, :span_cm).to_h.symbolize_keys)
      expect([result.success?, Kite.find(result.output.kite_id).span_cm]).to eq([true, 150])
    end

    it 'ignores a positional params object, as it ignores any positional Hash' do
      result = BuildKite.run(raw.require(:kite).permit(:name, :span_cm))
      expect([result.code, result.errors.to_h]).to eq([:invalid_input, { name: ['is required'] }])
    end
  end

  describe 'render json:' do
    it 'answers with the struct as_json, encoded' do
      post '/kites/sketch', kite: { name: 'Delta', span_cm: '210' }
      expect([last_response.status, json_body]).to eq([200, { 'name' => 'Delta', 'span_cm' => 210 }])
    end

    it 'answers with the result as_json, encoded, for a success and a failure' do
      post '/kites', kite: { name: 'Box', span_cm: '90' }
      expect(last_response.status).to eq(201)
      expect(json_body).to include('status' => 'success', 'code' => 'success', 'output' => { 'kite_id' => Kite.last.id })

      post '/kites', kite: { name: 'Barn door', span_cm: '900' }
      expect([last_response.status, json_body['status'], json_body['code']]).to eq([422, 'failure', 'too_wide'])
    end

    it 'matches what as_json gives outside a request' do
      sketch = KiteSketch.new(name: 'Rokkaku', span_cm: 180)
      expect(JSON.parse(ActiveSupport::JSON.encode(sketch))).to eq(JSON.parse(Oj.dump(sketch.as_json, mode: :compat)))
    end
  end

  describe 'transactional runs and after_commit' do
    it 'keeps the rows of a success and logs it once, after the commit' do
      without_wrapping_transaction do
        result = BuildKite.run(name: 'Genki', span_cm: 120)
        expect([result.success?, Kite.count, FlightLog.pluck(:entry)]).to eq([true, 1, ['built Genki']])
      end
    end

    it 'rolls back a failure and never logs it' do
      without_wrapping_transaction do
        result = BuildKite.run(name: 'Barn door', span_cm: 900)
        expect([result.code, Kite.count, FlightLog.count]).to eq([:too_wide, 0, 0])
      end
    end

    it 'waits for the outermost transaction before logging' do
      without_wrapping_transaction do
        Kite.transaction do
          BuildKite.run(name: 'Eddy', span_cm: 100)
          expect(FlightLog.count).to eq(0)
        end
        expect(FlightLog.pluck(:entry)).to eq(['built Eddy'])
      end
    end
  end

  # ActiveJob::TestHelper needs Minitest's assertions, so the examples drive the :test adapter directly.
  describe 'perform_later' do
    let(:queue) { ActiveJob::Base.queue_adapter }

    def performed_jobs = queue.performed_jobs
    def enqueued_jobs = queue.enqueued_jobs

    def perform_enqueued_jobs
      queue.perform_enqueued_jobs = true
      queue.perform_enqueued_at_jobs = true
      yield
    ensure
      queue.perform_enqueued_jobs = false
      queue.perform_enqueued_at_jobs = false
    end

    before do
      CheckWind.gusts_left = 0
      performed_jobs.clear
      enqueued_jobs.clear
    end

    it 'acks a success' do
      perform_enqueued_jobs { CheckWindJob.perform_later('hill') }
      expect(performed_jobs.size).to eq(1)
    end

    it 're-enqueues a retryable failure until it succeeds' do
      CheckWind.gusts_left = 2
      perform_enqueued_jobs { CheckWindJob.perform_later('hill') }
      expect([performed_jobs.size, CheckWind.gusts_left]).to eq([3, 0])
    end

    it 'discards a permanent failure without a retry' do
      perform_enqueued_jobs { CheckWindJob.perform_later('nowhere') }
      expect([performed_jobs.size, enqueued_jobs.size]).to eq([1, 0])
    end
  end

  describe 'eager loading' do
    it 'boots with eager loading on and eager loads again without error' do
      expect(Rails.application.config.eager_load).to be(true)
      expect { Rails.application.eager_load! }.not_to raise_error
    end
  end

  describe 'form_with model:' do
    it 'SH-B62: names the fields after the param_key and fills in the values' do
      html = ActionView::Base.empty.form_with(model: KiteSketch.new(name: 'Sled'), url: '/kites') { |f| f.text_field(:name) }
      expect(html).to include('name="kite_sketch[name]"', 'value="Sled"', 'action="/kites"')
    end
  end
end
