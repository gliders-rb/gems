---
title: "Process pages for actions"
description: "Generate a Markdown page with a Mermaid flowchart for each action, so people who don't read the code can see what it does, and check in CI that the pages stay current."
sidebar:
  label: "Process pages"
  order: 7
---

:::note[API may change]
`actionable-docs` is a prerelease, `1.0.0.pre1`, and its API may still change before 1.0.
:::

With `actionable-docs`, each action gets a page a product manager or a support lead can read. It covers what the action does, in what order, why it can stop, and what happens after. The page is Markdown with one Mermaid flowchart, and it's built from the declarations and the descriptions you already wrote. Nothing runs the action.

```ruby
gem 'actionable-docs'
```

## A page from an action

When the action and its parts have a `desc`, the page uses those words. Anything without one gets words made from its name.

```ruby run
require 'actionable/docs'

module Bindery
  class SewSignatures < Actionable::Action
    desc 'Sews the folded sections of a book together.'

    input do
      required :sections, :integer, desc: 'How many folded sections'
      optional :thread_colour, :string
    end

    fails :paper_torn, 'a section tore at the fold', retry: false
    skips :already_sewn, desc: 'The block came in sewn'

    step :punch_holes, desc: 'Punch the sewing holes'
    case_step :binding, desc: 'The binding style' do
      on 'coptic', :sew_chain_stitch
      on %w[case long], :sew_on_tapes
    end
    step :glue_spine, unless: :loose_leaf?

    on_success :log_job

    private

    def binding = 'coptic'
    def loose_leaf? = false
    def punch_holes = nil
    def sew_chain_stitch = nil
    def sew_on_tapes = nil
    def glue_spine = nil
    def log_job = nil
  end
end

page = Actionable::Docs.markdown(Bindery::SewSignatures)

Actionable::Docs.title(Bindery::SewSignatures)      # => "Sew signatures"
Actionable::Docs.path_for(Bindery::SewSignatures)   # => "bindery/sew_signatures.md"
page.include?("2. Depending on the binding style:\n   - coptic: Sew chain stitch\n   - case or long: Sew on tapes") # => true
page.include?('3. Glue spine (skipped when loose leaf)') # => true
page.include?('- When it succeeds: Log job') # => true
```

## What a page holds

In this order, leaving out any section that would be empty:

1. The title, made from the class's last name segment (`SewSignatures` gives "Sew signatures"), and the action's `desc`.
2. The flowchart.
3. **Steps**: numbered, with guards in words (`only when ...`, `skipped when ...`) and a case step's branches nested under it.
4. **It can stop because** and **It can finish early because**: each declared failure and skip with its words and its code in backticks, plus a note when its metadata says `retry: true` or `retry: false`.
5. **What happens after**: the hooks, in a fixed order.
6. **What it needs** and **What it produces**: the input and output fields, with their `desc:` and whether they're required.
7. **Also runs**: actions found in the source, as links.
8. A last line saying the page is generated, so readers edit the action instead.

The page names no class. A child action shows as a link to its own page.

## The flowchart

The happy path runs top to bottom from Start to Done. A guarded step gets a yes/no decision before it, and a case step becomes a decision with one edge per branch, plus `anything else`. A child action is one box with a link to its page, and it never opens up inline, so a page stays short.

Every declared failure and skip hangs off Start with the label `any step`. That's honest about what `describe` knows: it doesn't say which step can end with which code.

## Writing and checking pages

Every call needs a named class, since the title and the path come from its name: an anonymous `Class.new(Actionable::Action)` raises `ArgumentError`.

`Actionable::Docs.write(actions, dir:)` writes each page under `dir` and returns the paths. `Actionable::Docs.stale(actions, dir:)` returns the pages that are missing or differ from fresh ones, and writes nothing.

For a Rakefile:

```ruby
require 'actionable/docs/tasks'

Actionable::Docs::Tasks.define(actions: -> { [Bindery::SewSignatures] }, dir: 'docs/actions')
```

`rake actionable:docs` writes the pages. `rake actionable:docs:check` fails and lists the stale pages when they differ, so run it in CI and the pages can't drift from the code. Pass `actions:` as a lambda so your app loads its code first. Only the actions you list get pages.

## What isn't covered yet

- The headings are fixed English.
- There's no JSON output, Rails view or per-step code list.
- A large action gives a large chart, and nothing collapses it.

## See also

- [Batches and introspection](/reference/actionable/batches-and-introspection/): `describe`, the source of every page
- [LLM and MCP tools](/adapters/tools/)
- [How adapters work](/adapters/how-adapters-work/)
