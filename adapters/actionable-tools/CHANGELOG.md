# Changelog

## [Unreleased]

- First release: `Actionable::Tools.definition`, the MCP wrapper and the RubyLLM wrapper.
- The input and output schemas ask field_struct-json_schema for `decimals: :string`, so a decimal is a string in both,
  as the envelope (`output.as_json`) carries it.
