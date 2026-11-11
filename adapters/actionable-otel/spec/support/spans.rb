# frozen_string_literal: true

# Helpers over the in-memory exporter.
module SpanHelpers
  def spans = OTEL_EXPORTER.finished_spans

  def span_named(name) = spans.find { |s| s.name == name }

  def spans_named(name) = spans.select { |s| s.name == name }

  def children_of(span) = spans.select { |s| s.parent_span_id == span.span_id }
end

RSpec.configure { |c| c.include SpanHelpers }
